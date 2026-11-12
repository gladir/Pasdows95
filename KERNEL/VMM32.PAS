{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CVMM32)
  @description: VMM32.VXD - noyau 32 bits de Pasdows 95 : interface
                graphique 256 couleurs et sous-systeme Win32 capable
                d'executer de vrais programmes Windows 95 (PE 32 bits).
}

Program VMM32;

{ Compilation : WPC -CVMM32 VMM32.PAS VMM32.VXD

  Comme sous Windows 95, IO.SYS (mode reel) prepare la machine puis
  charge VMM32.VXD : une image PE 80386 liee a 00100000h (1 Mo). IO.SYS
  active le mode VESA 640x480 en 256 couleurs (memoire video lineaire),
  recopie la police 8x16 du BIOS en 00002000h et l'environnement en
  00003000h, passe en mode protege (GDT plate) et saute au programme
  principal avec une pile en 00090000h. Le bloc d'information est en
  00000500h (voir IO.PAS).

  Le noyau est ecrit en un seul fichier, par parties :

    Partie 1  - Constantes, types, variables et utilitaires
    Partie 2  - Processeur (GDT, IDT, exceptions), PIC, minuterie,
                horloge, clavier et souris PS/2
    Partie 3  - CD-ROM ATAPI, ISO 9660, fichiers et disque virtuel
    Partie 4  - Graphisme 8 bits : palette systeme, surfaces, police,
                composition de l'ecran et pointeur
    Partie 5  - Taches (threads cooperatifs) et objets de synchronisation
    Partie 6  - Gestionnaire de fenetres (USER) et files de messages
    Partie 7  - Interface de Pasdows : bureau, barre des taches, menu
                Demarrer, Poste de travail, boites de dialogue
    Partie 8  - API Win32 KERNEL32
    Partie 9  - API Win32 USER32
    Partie 10 - API Win32 GDI32
    Partie 11 - API Win32 WINMM, COMDLG32, SHELL32, OLE32, MSVFW32
    Partie 12 - Chargeur de programmes PE (EXE Windows 95)
    Partie 13 - Demarrage

  Sous-systeme Win32 : chaque fonction exportee par la clause exports
  (KERNEL32, USER32, GDI32...) est une procedure Pascal du noyau dont
  les parametres sont des valeurs 32 bits (LongInt) ; WPC produit pour
  chacune un thunk stdcall et l'inscrit dans la table d'exportation de
  VMM32.VXD. Le chargeur lie les importations des programmes Windows a
  ces procedures par leur nom. Les pointeurs sont des adresses
  lineaires lues et ecrites avec Mem, MemW et MemL[0:adresse].

  Les programmes s'executent en anneau 0, sans pagination, a leur
  adresse de base (00400000h en general). Chaque tache (thread) a sa
  propre pile et son bloc d'information (TIB, segment FS) ; les taches
  sont cooperatives : elles se cedent le processeur dans GetMessage,
  PeekMessage, Sleep, WaitForSingleObject... La tache 0 du noyau gere
  les peripheriques, le bureau et la composition de l'ecran. }

{$R-,S-,I-}

{ ==================================================================== }
{ Partie 1 - Constantes, types, variables et utilitaires               }
{ ==================================================================== }

Const
  KVersion    = '4.00.950';
  BootInfo    = $00000500;
  FontAddr    = $00002000;
  Com1        = $3F8;
  KStackTop   = $00090000;
  HeapBase    = $01000000;      { tas : de 16 Mo a la fin de la memoire }

  SelCode     = $08;
  SelData     = $10;
  SelFs       = $18;

  ScrW        = 640;
  ScrH        = 480;
  TaskH       = 28;
  TaskY       = ScrH - TaskH;

  { Couleurs statiques de la palette systeme (20 couleurs de Windows) }
  cBlack   = 0;   cMaroon  = 1;   cGreen   = 2;   cOlive   = 3;
  cNavy    = 4;   cPurple  = 5;   cTeal    = 6;   cSilver  = 7;
  cMoney   = 8;   cSky     = 9;   cCream   = 246; cMedGray = 247;
  cGray    = 248; cRed     = 249; cLime    = 250; cYellow  = 251;
  cBlue    = 252; cFuchsia = 253; cAqua    = 254; cWhite   = 255;

  { Tables }
  MaxWnd      = 256;
  MaxClass    = 64;
  MaxGdi      = 2048;
  MaxKObj     = 256;
  MaxThread   = 16;
  MaxQueue    = 256;
  MaxTimer    = 32;
  MaxMMTimer  = 16;
  MaxAtom     = 128;
  MaxRam      = 32;
  MaxMenu     = 64;
  MaxMenuItem = 1024;
  MaxProp     = 128;
  MaxHook     = 8;

  { Bases des poignees : valeurs 16 bits comme sous Windows 95 (les
    programmes issus de Win16 tronquent HFILE, HWND, HDC sur 16 bits) }
  HKObjBase   = $00000100;
  HGdiBase    = $00001000;
  HWndBase    = $00000800;
  HMenuBase   = $00000600;
  HDllBase    = $7F000000;

  { Sortes d'objets du noyau }
  koFile      = 1;  koFind = 2;   koThread = 3; koEvent = 4;
  koSemaphore = 5;  koMutex = 6;  koProcess = 7; koConsole = 8;

  { Sortes d'objets GDI }
  goPen = 1; goBrush = 2; goFont = 3; goBitmap = 4; goPalette = 5;
  goRegion = 6; goDC = 7;

  { Erreurs Win32 }
  ErrFileNotFound = 2; ErrPathNotFound = 3; ErrAccessDenied = 5;
  ErrInvalidHandle = 6; ErrNotEnoughMem = 8; ErrNoMoreFiles = 18;
  ErrInvalidParam = 87; ErrResNotFound = 1814;

Type
  TLanguage = (_French, _English, _Germany, _Italian, _Spain);

  TDescPtr = Record
    Limit : Word;
    Base  : LongInt;
  End;

  TGate = Record
    OfsLo : Word;
    Sel   : Word;
    Flags : Word;
    OfsHi : Word;
  End;

  TRect = Record
    L, T, R, B : LongInt;
  End;

Var
  Language   : TLanguage;
  BootDrive  : LongInt;
  MemTop     : LongInt;
  SerialOk   : Boolean;
  LogOn      : Boolean;
  ApiTrace   : Boolean;          { journal des appels d API (serie) }
  PreemptOn  : Boolean;          { preemption des taches Win32 }
  SliceStart : LongInt;          { debut de la tranche de temps }
  KImgLo, KImgHi : LongInt;      { image du noyau (jamais preemptee) }
  Ticks      : LongInt;          { millisecondes depuis le demarrage }
  HeapStart, HeapEnd, HeapRover : LongInt;
  HeapOwner  : LongInt;          { 1 : bloc d'un programme Win32 }
  OptFlags   : LongInt;

{ ------------------------------------------------------------------ }
{ Memoire et chaines                                                 }
{ ------------------------------------------------------------------ }

Procedure MoveMem(Src, Dst, N : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push esi
    push edi
    mov esi,Src
    mov edi,Dst
    mov ecx,N
    cld
    cmp esi,edi
    jae @fwd
    add esi,ecx
    add edi,ecx
    dec esi
    dec edi
    std
    rep movsb
    cld
    jmp @done
  @fwd:
    mov edx,ecx
    shr ecx,2
    rep movsd
    mov ecx,edx
    and ecx,3
    rep movsb
  @done:
    pop edi
    pop esi
  end;
End;

Procedure FillMem(Dst, N, B : LongInt);
Begin
  If N <= 0 Then Exit;
  asm
    push edi
    mov edi,Dst
    mov ecx,N
    mov eax,B
    and eax,0FFh
    mov ah,al
    mov edx,eax
    shl eax,16
    or eax,edx
    mov edx,ecx
    shr ecx,2
    cld
    rep stosd
    mov ecx,edx
    and ecx,3
    rep stosb
    pop edi
  end;
End;

{ Chaine ASCIIZ (adresse lineaire) -> chaine Pascal }
Function PStr(A : LongInt) : String;
Var S : String; N, C : LongInt;
Begin
  S := '';
  If (A <> 0) And (A > $1000) Then
  Begin
    N := 0;
    C := Mem[0:A];
    While (C <> 0) And (N < 255) Do
    Begin
      S := S + Chr(C);
      Inc(N);
      C := Mem[0:A + N];
    End;
  End;
  PStr := S;
End;

{ Chaine Pascal -> ASCIIZ en A (au plus Max octets, zero compris) }
Procedure PutPStr(A : LongInt; S : String; MaxN : LongInt);
Var I : LongInt;
Begin
  If (A = 0) Or (MaxN <= 0) Then Exit;
  If Length(S) > MaxN - 1 Then S := Copy(S, 1, MaxN - 1);
  For I := 1 To Length(S) Do Mem[0:A + I - 1] := Ord(S[I]);
  Mem[0:A + Length(S)] := 0;
End;

Function StrLenZ(A : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  If A <> 0 Then
    While Mem[0:A + N] <> 0 Do Inc(N);
  StrLenZ := N;
End;

Function UpStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    If (S[I] >= 'a') And (S[I] <= 'z') Then S[I] := Chr(Ord(S[I]) - 32);
  UpStr := S;
End;

Function UpCh(C : LongInt) : LongInt;
Begin
  If (C >= 97) And (C <= 122) Then C := C - 32;
  UpCh := C;
End;

Function IntStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IntStr := S;
End;

Function HexStr(V, Digits : LongInt) : String;
Const Hx : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 1 To Digits Do
  Begin
    S := Hx[(V And 15) + 1] + S;
    V := V Shr 4;
  End;
  HexStr := S;
End;

Function Trim(S : String) : String;
Begin
  While (Length(S) > 0) And (S[1] = ' ') Do Delete(S, 1, 1);
  While (Length(S) > 0) And (S[Length(S)] = ' ') Do
    Delete(S, Length(S), 1);
  Trim := S;
End;

Function Pad2(V : LongInt) : String;
Var S : String;
Begin
  S := IntStr(V);
  If Length(S) < 2 Then S := '0' + S;
  Pad2 := S;
End;

Function Min(A, B : LongInt) : LongInt;
Begin
  If A < B Then Min := A Else Min := B;
End;

Function Max(A, B : LongInt) : LongInt;
Begin
  If A > B Then Max := A Else Max := B;
End;

Function InRect(PX, PY, X1, Y1, X2, Y2 : LongInt) : Boolean;
Begin
  InRect := (PX >= X1) And (PX <= X2) And (PY >= Y1) And (PY <= Y2);
End;

Procedure SetR(Var R : TRect; L, T, Rt, B : LongInt);
Begin
  R.L := L; R.T := T; R.R := Rt; R.B := B;
End;

{ Intersection ; vrai si non vide (rectangles a bornes exclusives) }
Function RInter(Var D : TRect; A, B : TRect) : Boolean;
Begin
  D.L := Max(A.L, B.L); D.T := Max(A.T, B.T);
  D.R := Min(A.R, B.R); D.B := Min(A.B, B.B);
  RInter := (D.L < D.R) And (D.T < D.B);
End;

Procedure RUnion(Var D : TRect; A : TRect);
Begin
  If (A.L >= A.R) Or (A.T >= A.B) Then Exit;
  If (D.L >= D.R) Or (D.T >= D.B) Then
  Begin
    D := A;
    Exit;
  End;
  D.L := Min(D.L, A.L); D.T := Min(D.T, A.T);
  D.R := Max(D.R, A.R); D.B := Max(D.B, A.B);
End;

{ Lire / ecrire un RECT Win32 en memoire }
Procedure GetRectAt(A : LongInt; Var R : TRect);
Begin
  R.L := MemL[0:A]; R.T := MemL[0:A + 4];
  R.R := MemL[0:A + 8]; R.B := MemL[0:A + 12];
End;

Procedure PutRectAt(A : LongInt; R : TRect);
Begin
  If A = 0 Then Exit;
  MemL[0:A] := R.L; MemL[0:A + 4] := R.T;
  MemL[0:A + 8] := R.R; MemL[0:A + 12] := R.B;
End;

{ ------------------------------------------------------------------ }
{ Journal sur le port serie COM1                                     }
{ ------------------------------------------------------------------ }

Procedure SerialInit;
Begin
  Port[Com1 + 1] := 0;
  Port[Com1 + 3] := $80;
  Port[Com1] := 1;
  Port[Com1 + 1] := 0;
  Port[Com1 + 3] := 3;
  Port[Com1 + 2] := $C7;
  Port[Com1 + 4] := 3;
  SerialOk := Port[Com1 + 5] <> $FF;
End;

Procedure SerialPut(C : Char);
Var N : LongInt;
Begin
  If Not SerialOk Then Exit;
  N := 0;
  While ((Port[Com1 + 5] And $20) = 0) And (N < 100000) Do Inc(N);
  Port[Com1] := Ord(C);
End;

Procedure KLog(S : String);
Var I : LongInt;
Begin
  If Not LogOn Then Exit;
  For I := 1 To Length(S) Do SerialPut(S[I]);
  SerialPut(#13);
  SerialPut(#10);
End;

{ ------------------------------------------------------------------ }
{ Langue                                                             }
{ ------------------------------------------------------------------ }

Function L(Const F, E, G, I, S : String) : String;
Begin
  Case Language Of
    _English : L := E;
    _Germany : L := G;
    _Italian : L := I;
    _Spain   : L := S;
  Else
    L := F;
  End;
End;

{ ------------------------------------------------------------------ }
{ Tas du noyau (blocs avec en-tete de 16 octets)                     }
{   +0 signature  +4 taille totale  +8 proprietaire  +12 reserve     }
{ ------------------------------------------------------------------ }

Const
  HeapUsed = $55534544;
  HeapFree0 = $45455246;

Procedure HeapInit(Start, Stop : LongInt);
Begin
  HeapStart := (Start + 15) And Not 15;
  HeapEnd := Stop And Not 15;
  MemL[0:HeapStart] := HeapFree0;
  MemL[0:HeapStart + 4] := HeapEnd - HeapStart;
  MemL[0:HeapStart + 8] := 0;
  HeapRover := HeapStart;
End;

Function KAllocFrom(Start, Need : LongInt) : LongInt;
Var P, BS : LongInt;
Begin
  KAllocFrom := 0;
  P := Start;
  While P < HeapEnd Do
  Begin
    BS := MemL[0:P + 4];
    If BS <= 0 Then Exit;
    If MemL[0:P] = HeapFree0 Then
    Begin
      While (P + BS < HeapEnd) And (MemL[0:P + BS] = HeapFree0) Do
      Begin
        BS := BS + MemL[0:P + BS + 4];
        MemL[0:P + 4] := BS;
      End;
      If BS >= Need Then
      Begin
        If BS - Need >= 64 Then
        Begin
          MemL[0:P + Need] := HeapFree0;
          MemL[0:P + Need + 4] := BS - Need;
          MemL[0:P + 4] := Need;
        End;
        MemL[0:P] := HeapUsed;
        MemL[0:P + 8] := HeapOwner;
        HeapRover := P;
        KAllocFrom := P + 16;
        Exit;
      End;
    End;
    P := P + BS;
  End;
End;

{ Bloc de Size octets (mis a zero) ; 0 si memoire insuffisante }
Function KAlloc(Size : LongInt) : LongInt;
Var Need, A : LongInt;
Begin
  If Size <= 0 Then Size := 1;
  Need := ((Size + 15) And Not 15) + 16;
  A := KAllocFrom(HeapRover, Need);
  If A = 0 Then A := KAllocFrom(HeapStart, Need);
  If A = 0 Then KLog('KAlloc: memoire epuisee (' + IntStr(Size) + ')')
  Else FillMem(A, Need - 16, 0);
  KAlloc := A;
End;

Procedure KFree(A : LongInt);
Begin
  If (A < HeapStart + 16) Or (A >= HeapEnd) Then Exit;
  If MemL[0:A - 16] <> HeapUsed Then Exit;
  MemL[0:A - 16] := HeapFree0;
  If A - 16 < HeapRover Then HeapRover := A - 16;
End;

Function KSize(A : LongInt) : LongInt;
Begin
  If (A >= HeapStart + 16) And (A < HeapEnd) And
     (MemL[0:A - 16] = HeapUsed) Then
    KSize := MemL[0:A - 12] - 16
  Else
    KSize := 0;
End;

Function KRealloc(A, Size : LongInt) : LongInt;
Var B, Old : LongInt;
Begin
  If A = 0 Then
  Begin
    KRealloc := KAlloc(Size);
    Exit;
  End;
  Old := KSize(A);
  If Old >= Size Then
  Begin
    KRealloc := A;
    Exit;
  End;
  B := KAlloc(Size);
  If B <> 0 Then
  Begin
    MoveMem(A, B, Old);
    KFree(A);
  End;
  KRealloc := B;
End;

{ Liberer tous les blocs d'un proprietaire (fin d'un programme) }
Procedure KFreeOwner(Owner : LongInt);
Var P, BS : LongInt;
Begin
  P := HeapStart;
  While P < HeapEnd Do
  Begin
    BS := MemL[0:P + 4];
    If BS <= 0 Then Exit;
    If (MemL[0:P] = HeapUsed) And (MemL[0:P + 8] = Owner) Then
      MemL[0:P] := HeapFree0;
    P := P + BS;
  End;
  HeapRover := HeapStart;
End;

Function HeapFreeBytes : LongInt;
Var P, BS, T : LongInt;
Begin
  T := 0;
  P := HeapStart;
  While P < HeapEnd Do
  Begin
    BS := MemL[0:P + 4];
    If BS <= 0 Then Break;
    If MemL[0:P] = HeapFree0 Then T := T + BS;
    P := P + BS;
  End;
  HeapFreeBytes := T;
End;

{ ==================================================================== }
{ Partie 2 - Processeur, PIC, minuterie, horloge, clavier et souris    }
{ ==================================================================== }

Var
  Gdt      : Array[0..9] Of LongInt;
  GdtPtr   : TDescPtr;
  Idt      : Array[0..255] Of TGate;
  IdtPtr   : TDescPtr;
  { file brute du clavier (codes de balayage) }
  KbQ      : Array[0..255] Of LongInt;
  KbHead, KbTail : LongInt;
  { souris }
  MouOk    : Boolean;
  MouPk    : Array[0..2] Of LongInt;
  MouIdx   : LongInt;
  MouQDx, MouQDy, MouQBtn : Array[0..255] Of LongInt;
  MouHead, MouTail : LongInt;
  { horloge temps reel }
  RtcYear, RtcMonth, RtcDay, RtcHour, RtcMin, RtcSec, RtcDow : LongInt;

Procedure SetGate(N, Addr : LongInt);
Begin
  Idt[N].OfsLo := Addr And $FFFF;
  Idt[N].Sel := SelCode;
  Idt[N].Flags := $8E00;
  Idt[N].OfsHi := (Addr Shr 16) And $FFFF;
End;

{ Base du segment FS (bloc d'information de la tache courante) }
Procedure SetFsBase(Base : LongInt);
Begin
  Gdt[6] := $0000FFFF Or ((Base And $FFFF) Shl 16);
  Gdt[7] := ((Base Shr 16) And $FF) Or $00CF9200 Or
            (Base And LongInt($FF000000));
  asm
    mov ax,18h
    mov fs,ax
  end;
End;

Procedure InitGdt;
Begin
  Gdt[0] := 0;          Gdt[1] := 0;
  Gdt[2] := $0000FFFF;  Gdt[3] := $00CF9A00;
  Gdt[4] := $0000FFFF;  Gdt[5] := $00CF9200;
  Gdt[6] := $0000FFFF;  Gdt[7] := $00CF9200;
  Gdt[8] := 0;          Gdt[9] := 0;
  GdtPtr.Limit := 5 * 8 - 1;
  GdtPtr.Base := LongInt(@Gdt);
  asm
    lgdt GdtPtr
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov gs,ax
    mov ss,ax
    mov ax,18h
    mov fs,ax
  end;
End;

Procedure KFault(Vec, Frame : LongInt); Forward;

Procedure Trap(Vec : LongInt);
Var F : LongInt;
Begin
  asm
    mov eax,[ebp]
    mov F,eax
  end;
  KFault(Vec, F);
End;

Procedure Exc00; Interrupt; Begin Trap(0) End;
Procedure Exc01; Interrupt; Begin Trap(1) End;
Procedure Exc02; Interrupt; Begin Trap(2) End;
Procedure Exc03; Interrupt; Begin Trap(3) End;
Procedure Exc04; Interrupt; Begin Trap(4) End;
Procedure Exc05; Interrupt; Begin Trap(5) End;
Procedure Exc06; Interrupt; Begin Trap(6) End;
Procedure Exc07; Interrupt; Begin Trap(7) End;
Procedure Exc08; Interrupt; Begin Trap(8 + 256) End;
Procedure Exc0A; Interrupt; Begin Trap(10 + 256) End;
Procedure Exc0B; Interrupt; Begin Trap(11 + 256) End;
Procedure Exc0C; Interrupt; Begin Trap(12 + 256) End;
Procedure Exc0D; Interrupt; Begin Trap(13 + 256) End;
Procedure Exc0E; Interrupt; Begin Trap(14 + 256) End;
Procedure Exc10; Interrupt; Begin Trap(16) End;
Procedure Exc11; Interrupt; Begin Trap(17 + 256) End;
Procedure Exc13; Interrupt; Begin Trap(19) End;
Procedure ExcOther; Interrupt; Begin Trap(255) End;

Procedure IrqMaster; Interrupt;
Begin
  Port[$20] := $20;
End;

Procedure IrqSlave; Interrupt;
Begin
  Port[$A0] := $20;
  Port[$20] := $20;
End;

Procedure TimerTail; Forward;

Procedure IrqTimer; Interrupt;
Begin
  Inc(Ticks);
  Port[$20] := $20;
  If PreemptOn Then TimerTail;
End;

Procedure IrqKeyboard; Interrupt;
Var B, N : LongInt;
Begin
  B := Port[$60];
  N := (KbTail + 1) And 255;
  If N <> KbHead Then
  Begin
    KbQ[KbTail] := B;
    KbTail := N;
  End;
  Port[$20] := $20;
End;

Procedure IrqMouse; Interrupt;
Var B, N, Dx, Dy : LongInt;
Begin
  If (Port[$64] And $21) = $21 Then
  Begin
    B := Port[$60];
    If (MouIdx = 0) And ((B And 8) = 0) Then
    Else
    Begin
      MouPk[MouIdx] := B;
      Inc(MouIdx);
      If MouIdx = 3 Then
      Begin
        MouIdx := 0;
        Dx := MouPk[1];
        If (MouPk[0] And $10) <> 0 Then Dx := Dx - 256;
        Dy := MouPk[2];
        If (MouPk[0] And $20) <> 0 Then Dy := Dy - 256;
        If (MouPk[0] And $C0) <> 0 Then
        Begin
          Dx := 0; Dy := 0;
        End;
        N := (MouTail + 1) And 255;
        If N <> MouHead Then
        Begin
          MouQDx[MouTail] := Dx;
          MouQDy[MouTail] := -Dy;
          MouQBtn[MouTail] := MouPk[0] And 7;
          MouTail := N;
        End;
      End;
    End;
  End;
  Port[$A0] := $20;
  Port[$20] := $20;
End;

Procedure InitPic;
Begin
  Port[$20] := $11; Port[$A0] := $11;
  Port[$21] := $20; Port[$A1] := $28;
  Port[$21] := $04; Port[$A1] := $02;
  Port[$21] := $01; Port[$A1] := $01;
  Port[$21] := $F8; Port[$A1] := $FF;
End;

Procedure InitIdt;
Var I : LongInt;
Begin
  For I := 0 To 255 Do SetGate(I, LongInt(@ExcOther));
  SetGate(0, LongInt(@Exc00));  SetGate(1, LongInt(@Exc01));
  SetGate(2, LongInt(@Exc02));  SetGate(3, LongInt(@Exc03));
  SetGate(4, LongInt(@Exc04));  SetGate(5, LongInt(@Exc05));
  SetGate(6, LongInt(@Exc06));  SetGate(7, LongInt(@Exc07));
  SetGate(8, LongInt(@Exc08));  SetGate(10, LongInt(@Exc0A));
  SetGate(11, LongInt(@Exc0B)); SetGate(12, LongInt(@Exc0C));
  SetGate(13, LongInt(@Exc0D)); SetGate(14, LongInt(@Exc0E));
  SetGate(16, LongInt(@Exc10)); SetGate(17, LongInt(@Exc11));
  SetGate(19, LongInt(@Exc13));
  For I := $20 To $27 Do SetGate(I, LongInt(@IrqMaster));
  For I := $28 To $2F Do SetGate(I, LongInt(@IrqSlave));
  SetGate($20, LongInt(@IrqTimer));
  SetGate($21, LongInt(@IrqKeyboard));
  SetGate($2C, LongInt(@IrqMouse));
  IdtPtr.Limit := 256 * 8 - 1;
  IdtPtr.Base := LongInt(@Idt);
  asm
    lidt IdtPtr
  end;
End;

{ PIT canal 0 a 1000 Hz (Ticks en millisecondes) }
Procedure InitTimer;
Begin
  Port[$43] := $36;
  Port[$40] := 1193 And $FF;
  Port[$40] := 1193 Shr 8;
End;

Procedure Idle;
Begin
  asm
    sti
    hlt
  end;
End;

Procedure KDelay(Ms : LongInt);
Var T : LongInt;
Begin
  T := Ticks + Ms;
  While Ticks < T Do Idle;
End;

Procedure KSound(Hz : LongInt);
Var D : LongInt;
Begin
  If Hz < 20 Then Exit;
  D := 1193180 Div Hz;
  Port[$43] := $B6;
  Port[$42] := D And $FF;
  Port[$42] := (D Shr 8) And $FF;
  Port[$61] := Port[$61] Or 3;
End;

Procedure KNoSound;
Begin
  Port[$61] := Port[$61] And $FC;
End;

Procedure KBeep;
Begin
  KSound(880);
  KDelay(60);
  KNoSound;
End;

Function CmosRead(R : LongInt) : LongInt;
Begin
  Port[$70] := R;
  CmosRead := Port[$71];
End;

Procedure CmosWrite(R, V : LongInt);
Begin
  Port[$70] := R;
  Port[$71] := V;
End;

Function Bcd(V : LongInt) : LongInt;
Begin
  If (CmosRead($0B) And 4) <> 0 Then Bcd := V
  Else Bcd := (V Shr 4) * 10 + (V And 15);
End;

Procedure ReadRtc;
Var N : LongInt;
Begin
  N := 0;
  While ((CmosRead($0A) And $80) <> 0) And (N < 100000) Do Inc(N);
  RtcSec := Bcd(CmosRead($00));
  RtcMin := Bcd(CmosRead($02));
  RtcHour := Bcd(CmosRead($04) And $7F);
  RtcDay := Bcd(CmosRead($07));
  RtcMonth := Bcd(CmosRead($08));
  RtcYear := Bcd(CmosRead($09)) + 2000;
  If (RtcMonth < 1) Or (RtcMonth > 12) Then RtcMonth := 1;
  If (RtcDay < 1) Or (RtcDay > 31) Then RtcDay := 1;
End;

Function DayOfWeek(Y, M, D : LongInt) : LongInt;
Const T : Array[1..12] Of LongInt = (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4);
Begin
  If M < 3 Then Dec(Y);
  DayOfWeek := (Y + Y Div 4 - Y Div 100 + Y Div 400 + T[M] + D) Mod 7;
End;

{ Date et heure au format DOS (date shl 16 or heure) }
Function DosNow : LongInt;
Begin
  ReadRtc;
  DosNow := (((RtcYear - 1980) Shl 9) Or (RtcMonth Shl 5) Or RtcDay) Shl
            16 Or ((RtcHour Shl 11) Or (RtcMin Shl 5) Or (RtcSec Div 2));
End;

{ Controleur 8042 : clavier (IRQ 1) et souris PS/2 (IRQ 12) }
Function KbcWaitIn : Boolean;
Var N : LongInt;
Begin
  N := 0;
  While ((Port[$64] And 2) <> 0) And (N < 100000) Do Inc(N);
  KbcWaitIn := N < 100000;
End;

Function KbcRead : LongInt;
Var N, R : LongInt;
Begin
  N := 0;
  R := -1;
  While (R < 0) And (N < 200000) Do
  Begin
    If (Port[$64] And 1) <> 0 Then R := Port[$60];
    Inc(N);
  End;
  KbcRead := R;
End;

Function MouCmd(B : LongInt) : Boolean;
Begin
  KbcWaitIn;
  Port[$64] := $D4;
  KbcWaitIn;
  Port[$60] := B;
  MouCmd := KbcRead = $FA;
End;

Procedure InitInput;
Var Cb, X, I : LongInt;
Begin
  KbHead := 0; KbTail := 0;
  MouOk := False; MouIdx := 0; MouHead := 0; MouTail := 0;
  For I := 1 To 32 Do
    If (Port[$64] And 1) <> 0 Then X := Port[$60];
  KbcWaitIn;
  Port[$64] := $A8;
  KbcWaitIn;
  Port[$64] := $20;
  Cb := KbcRead;
  If Cb < 0 Then Cb := $45;
  KbcWaitIn;
  Port[$64] := $60;
  KbcWaitIn;
  Port[$60] := (Cb And Not $23) And $FF;
  If MouCmd($F6) Then
    If MouCmd($F4) Then MouOk := True;
  For I := 1 To 8 Do
    If (Port[$64] And 1) <> 0 Then X := Port[$60];
  Cb := (Cb Or 1) And Not $10;
  If MouOk Then Cb := (Cb Or 2) And Not $20 Else Cb := Cb And Not 2;
  KbcWaitIn;
  Port[$64] := $60;
  KbcWaitIn;
  Port[$60] := Cb And $FF;
  Port[$21] := Port[$21] And Not $02;
  If MouOk Then Port[$A1] := Port[$A1] And Not $10;
End;

{ ==================================================================== }
{ Partie 3 - CD-ROM ATAPI, ISO 9660, objets du noyau et fichiers       }
{ ==================================================================== }
{ D: est le CD-ROM d'amorcage (lecture seule), C: un disque virtuel en
  memoire (C:\WINDOWS, C:\TEMP...) ou les programmes peuvent ecrire. }

Const
  CacheSlots = 64;

Type
  TKObj = Record
    Used   : Boolean;
    Kind   : LongInt;
    F1, F2, F3, F4, F5, F6 : LongInt;
    Name   : String[127];
    Mask   : String[15];
  End;

  TRamFile = Record
    Used : Boolean;
    Path : String[127];
    Attr : LongInt;
    Data : LongInt;
    Size : LongInt;
    Cap  : LongInt;
    Time : LongInt;
  End;

Var
  AtaBase, AtaCtrl : LongInt;
  AtaSlave, AtaFound : Boolean;
  CacheLba  : Array[0..CacheSlots - 1] Of LongInt;
  CacheData : Array[0..CacheSlots - 1] Of LongInt;
  CacheNext : LongInt;
  RootLba, RootSize : LongInt;
  VolLabel  : String[32];
  KObjs     : Array[0..MaxKObj - 1] Of TKObj;
  RamFiles  : Array[0..MaxRam - 1] Of TRamFile;
  CurDirS   : String[127];
  LastErr0  : LongInt;

Function AtaWaitBusy : LongInt;
Var N, St : LongInt;
Begin
  N := 0;
  Repeat
    St := Port[AtaBase + 7];
    If (St And $80) = 0 Then
    Begin
      AtaWaitBusy := St;
      Exit;
    End;
    Inc(N);
  Until N > 2000000;
  AtaWaitBusy := -1;
End;

Procedure AtaDelay;
Var I, X : LongInt;
Begin
  For I := 1 To 4 Do X := Port[AtaCtrl];
End;

Procedure AtaSelect;
Begin
  If AtaSlave Then Port[AtaBase + 6] := $B0 Else Port[AtaBase + 6] := $A0;
  AtaDelay;
End;

Function AtaProbe(Base, Ctrl : LongInt; Slave : Boolean) : Boolean;
Var St, I, X : LongInt;
Begin
  AtaProbe := False;
  AtaBase := Base; AtaCtrl := Ctrl; AtaSlave := Slave;
  If Port[Base + 7] = $FF Then Exit;
  Port[Ctrl] := 2;
  AtaSelect;
  If Port[Base + 7] = 0 Then Exit;
  Port[Base + 7] := $A1;
  AtaDelay;
  St := AtaWaitBusy;
  If (St < 0) Or ((St And 1) <> 0) Or ((St And 8) = 0) Then Exit;
  For I := 0 To 255 Do X := PortW[Base];
  AtaProbe := True;
End;

Procedure AtaInit;
Begin
  AtaFound := AtaProbe($170, $376, False);
  If Not AtaFound Then AtaFound := AtaProbe($170, $376, True);
  If Not AtaFound Then AtaFound := AtaProbe($1F0, $3F6, False);
  If Not AtaFound Then AtaFound := AtaProbe($1F0, $3F6, True);
  KLog('ATAPI : ' + HexStr(AtaBase, 3) + ' trouve=' +
       IntStr(Ord(AtaFound)));
End;

Function AtaReadSector(Lba, Dst : LongInt) : Boolean;
Var St, Cnt, Got, Tries, B : LongInt;
Begin
  AtaReadSector := False;
  If Not AtaFound Then Exit;
  For Tries := 1 To 3 Do
  Begin
    AtaSelect;
    If AtaWaitBusy < 0 Then Continue;
    Port[AtaBase + 1] := 0;
    Port[AtaBase + 4] := 2048 And $FF;
    Port[AtaBase + 5] := 2048 Shr 8;
    Port[AtaBase + 7] := $A0;
    AtaDelay;
    St := AtaWaitBusy;
    If (St < 0) Or ((St And 8) = 0) Then Continue;
    PortW[AtaBase] := $0028;
    PortW[AtaBase] := ((Lba Shr 24) And $FF) Or
                      (((Lba Shr 16) And $FF) Shl 8);
    PortW[AtaBase] := ((Lba Shr 8) And $FF) Or ((Lba And $FF) Shl 8);
    PortW[AtaBase] := $0000;
    PortW[AtaBase] := $0001;
    PortW[AtaBase] := $0000;
    Got := 0;
    Repeat
      AtaDelay;
      St := AtaWaitBusy;
      If (St < 0) Or ((St And 1) <> 0) Then Break;
      If (St And 8) = 0 Then Break;
      Cnt := Port[AtaBase + 4] Or (Port[AtaBase + 5] Shl 8);
      If (Cnt <= 0) Or (Got + Cnt > 2048) Then Break;
      B := Dst + Got;
      asm
        push edi
        mov edi,B
        mov ecx,Cnt
        shr ecx,1
        mov edx,AtaBase
        cld
        rep insw
        pop edi
      end;
      Got := Got + Cnt;
    Until Got >= 2048;
    AtaWaitBusy;
    If Got = 2048 Then
    Begin
      AtaReadSector := True;
      Exit;
    End;
  End;
End;

{ Secteur Lba (antememoire) ; adresse des 2048 octets ou 0 }
Function CdSector(Lba : LongInt) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To CacheSlots - 1 Do
    If (CacheLba[I] = Lba) And (CacheData[I] <> 0) Then
    Begin
      CdSector := CacheData[I];
      Exit;
    End;
  I := CacheNext;
  CacheNext := (CacheNext + 1) Mod CacheSlots;
  If CacheData[I] = 0 Then CacheData[I] := KAlloc(2048);
  CacheLba[I] := -1;
  If AtaReadSector(Lba, CacheData[I]) Then
  Begin
    CacheLba[I] := Lba;
    CdSector := CacheData[I];
  End
  Else
    CdSector := 0;
End;

Function GetD(A : LongInt) : LongInt;
Begin
  GetD := MemL[0:A];
End;

{ Lire N octets du CD a partir de l'octet Ofs du fichier commencant au
  secteur Lba, vers Dst }
Function CdReadBytes(Lba, Ofs, N, Dst : LongInt) : Boolean;
Var S, O, C, A : LongInt;
Begin
  CdReadBytes := False;
  While N > 0 Do
  Begin
    S := Lba + Ofs Div 2048;
    O := Ofs Mod 2048;
    C := 2048 - O;
    If C > N Then C := N;
    If (O = 0) And (C = 2048) Then
    Begin
      If Not AtaReadSector(S, Dst) Then Exit;
    End
    Else
    Begin
      A := CdSector(S);
      If A = 0 Then Exit;
      MoveMem(A + O, Dst, C);
    End;
    Ofs := Ofs + C; Dst := Dst + C; N := N - C;
  End;
  CdReadBytes := True;
End;

{ Entree Index d'un repertoire ISO ; False a la fin }
Function IsoDirEntry(DirLba, DirSize, Index : LongInt; Var Name : String;
                     Var Lba, Size, Flags, Time : LongInt) : Boolean;
Var Sect, NSect, A, Ofs, Rec, N, K, C : LongInt;
Begin
  IsoDirEntry := False;
  N := 0;
  NSect := (DirSize + 2047) Div 2048;
  For Sect := 0 To NSect - 1 Do
  Begin
    A := CdSector(DirLba + Sect);
    If A = 0 Then Exit;
    Ofs := 0;
    While Ofs < 2048 Do
    Begin
      Rec := Mem[0:A + Ofs];
      If Rec = 0 Then Ofs := 2048
      Else
      Begin
        K := Mem[0:A + Ofs + 32];
        If Not ((K = 1) And (Mem[0:A + Ofs + 33] <= 1)) Then
        Begin
          If N = Index Then
          Begin
            Name := '';
            C := 0;
            While C < K Do
            Begin
              If Mem[0:A + Ofs + 33 + C] = Ord(';') Then C := K
              Else Name := Name + Chr(UpCh(Mem[0:A + Ofs + 33 + C]));
              Inc(C);
            End;
            If (Length(Name) > 0) And (Name[Length(Name)] = '.') Then
              Delete(Name, Length(Name), 1);
            Lba := GetD(A + Ofs + 2);
            Size := GetD(A + Ofs + 10);
            Flags := Mem[0:A + Ofs + 25];
            Time := (((Mem[0:A + Ofs + 18] + 1900 - 1980) Shl 9) Or
                    (Mem[0:A + Ofs + 19] Shl 5) Or Mem[0:A + Ofs + 20]) Shl
                    16 Or ((Mem[0:A + Ofs + 21] Shl 11) Or
                    (Mem[0:A + Ofs + 22] Shl 5) Or
                    (Mem[0:A + Ofs + 23] Div 2));
            IsoDirEntry := True;
            Exit;
          End;
          Inc(N);
        End;
        Ofs := Ofs + Rec;
      End;
    End;
  End;
End;

{ Chemin du CD (sans D:\, en majuscules) -> secteur, taille, attributs }
Function IsoLookup(Path : String; Var Lba, Size, Flags, Time : LongInt)
  : Boolean;
Var Part, Nm : String; P, I, DL, DS : LongInt; Ok : Boolean;
Begin
  IsoLookup := False;
  DL := RootLba; DS := RootSize;
  Lba := RootLba; Size := RootSize; Flags := 2; Time := 0;
  While (Length(Path) > 0) And (Path[1] = '\') Do Delete(Path, 1, 1);
  While Path <> '' Do
  Begin
    P := Pos('\', Path);
    If P > 0 Then
    Begin
      Part := Copy(Path, 1, P - 1);
      Delete(Path, 1, P);
    End
    Else
    Begin
      Part := Path;
      Path := '';
    End;
    If (Part = '') Or (Part = '.') Then Continue;
    I := 0; Ok := False;
    While IsoDirEntry(DL, DS, I, Nm, Lba, Size, Flags, Time) Do
    Begin
      If Nm = Part Then
      Begin
        Ok := True;
        Break;
      End;
      Inc(I);
    End;
    If Not Ok Then Exit;
    DL := Lba; DS := Size;
  End;
  IsoLookup := True;
End;

Procedure CdInit;
Var A, K : LongInt;
Begin
  RootLba := MemL[0:BootInfo + 4];
  RootSize := MemL[0:BootInfo + 8];
  VolLabel := '';
  A := CdSector(16);
  If A <> 0 Then
  Begin
    RootLba := GetD(A + 158);
    RootSize := GetD(A + 166);
    For K := 0 To 31 Do VolLabel := VolLabel + Chr(Mem[0:A + 40 + K]);
    VolLabel := Trim(VolLabel);
  End;
  KLog('CD : racine LBA ' + IntStr(RootLba) + ' etiquette ' + VolLabel);
End;

{ ------------------------------------------------------------------ }
{ Objets du noyau (poignees Win32 : fichiers, taches, evenements...) }
{ ------------------------------------------------------------------ }

Function KObjNew(Kind : LongInt) : LongInt;
Var I : LongInt;
Begin
  KObjNew := -1;
  For I := 0 To MaxKObj - 1 Do
    If Not KObjs[I].Used Then
    Begin
      KObjs[I].Used := True;
      KObjs[I].Kind := Kind;
      KObjs[I].F1 := 0; KObjs[I].F2 := 0; KObjs[I].F3 := 0;
      KObjs[I].F4 := 0; KObjs[I].F5 := 0; KObjs[I].F6 := 0;
      KObjs[I].Name := ''; KObjs[I].Mask := '';
      KObjNew := I;
      Exit;
    End;
End;

Function KHandle(I : LongInt) : LongInt;
Begin
  KHandle := HKObjBase + I * 4;
End;

{ Index de l'objet de la poignee H (de la sorte Kind, 0 = toute) }
Function KObjOf(H, Kind : LongInt) : LongInt;
Var I : LongInt;
Begin
  KObjOf := -1;
  If (H < HKObjBase) Or (H >= HKObjBase + MaxKObj * 4) Then Exit;
  I := (H - HKObjBase) Div 4;
  If Not KObjs[I].Used Then Exit;
  If (Kind <> 0) And (KObjs[I].Kind <> Kind) Then Exit;
  KObjOf := I;
End;

{ ------------------------------------------------------------------ }
{ Chemins                                                            }
{ ------------------------------------------------------------------ }

{ Chemin complet en majuscules : X:\REP\NOM }
Function FullPath(Name : String) : String;
Var S, R, Part : String; P : LongInt;
Begin
  S := UpStr(Trim(Name));
  For P := 1 To Length(S) Do If S[P] = '/' Then S[P] := '\';
  If (Length(S) >= 2) And (S[2] = ':') Then
  Begin
    If (Length(S) = 2) Or (S[3] <> '\') Then
    Begin
      If S[1] = CurDirS[1] Then S := CurDirS + '\' + Copy(S, 3, 255)
      Else S := Copy(S, 1, 2) + '\' + Copy(S, 3, 255);
    End;
  End
  Else If (Length(S) > 0) And (S[1] = '\') Then S := Copy(CurDirS, 1, 2) + S
  Else S := CurDirS + '\' + S;
  { normaliser . et .. }
  R := Copy(S, 1, 2);
  S := Copy(S, 3, 255);
  While S <> '' Do
  Begin
    While (Length(S) > 0) And (S[1] = '\') Do Delete(S, 1, 1);
    If S = '' Then Break;
    P := Pos('\', S);
    If P > 0 Then
    Begin
      Part := Copy(S, 1, P - 1);
      Delete(S, 1, P);
    End
    Else
    Begin
      Part := S;
      S := '';
    End;
    If Part = '.' Then Continue;
    If Part = '..' Then
    Begin
      P := Length(R);
      While (P > 2) And (R[P] <> '\') Do Dec(P);
      If P > 2 Then R := Copy(R, 1, P - 1) Else R := Copy(R, 1, 2);
      Continue;
    End;
    R := R + '\' + Part;
  End;
  If Length(R) = 2 Then R := R + '\';
  FullPath := R;
End;

Function ParentDir(Path : String) : String;
Var P : LongInt;
Begin
  P := Length(Path);
  While (P > 0) And (Path[P] <> '\') Do Dec(P);
  If P <= 3 Then ParentDir := Copy(Path, 1, 3)
  Else ParentDir := Copy(Path, 1, P - 1);
End;

Function BaseName(Path : String) : String;
Var P : LongInt;
Begin
  P := Length(Path);
  While (P > 0) And (Path[P] <> '\') And (Path[P] <> ':') Do Dec(P);
  BaseName := Copy(Path, P + 1, 255);
End;

{ Repertoires fixes du disque C: }
Function IsCDir(Path : String) : Boolean;
Begin
  IsCDir := (Path = 'C:\') Or (Path = 'C:\WINDOWS') Or
            (Path = 'C:\WINDOWS\SYSTEM') Or (Path = 'C:\TEMP') Or
            (Path = 'C:\WINDOWS\TEMP');
End;

Function RamFind(Path : String) : LongInt;
Var I : LongInt;
Begin
  RamFind := -1;
  For I := 0 To MaxRam - 1 Do
    If RamFiles[I].Used And (RamFiles[I].Path = Path) Then
    Begin
      RamFind := I;
      Exit;
    End;
End;

Function RamNew(Path : String) : LongInt;
Var I : LongInt;
Begin
  RamNew := -1;
  For I := 0 To MaxRam - 1 Do
    If Not RamFiles[I].Used Then
    Begin
      RamFiles[I].Used := True;
      RamFiles[I].Path := Path;
      RamFiles[I].Attr := $20;
      RamFiles[I].Data := 0;
      RamFiles[I].Size := 0;
      RamFiles[I].Cap := 0;
      RamFiles[I].Time := DosNow;
      RamNew := I;
      Exit;
    End;
End;

Function RamReserve(R, NewSize : LongInt) : Boolean;
Var Cap, A : LongInt;
Begin
  RamReserve := True;
  If NewSize <= RamFiles[R].Cap Then Exit;
  Cap := RamFiles[R].Cap * 2;
  If Cap < NewSize Then Cap := NewSize + 4096;
  A := KAlloc(Cap);
  If A = 0 Then
  Begin
    RamReserve := False;
    Exit;
  End;
  If RamFiles[R].Data <> 0 Then
  Begin
    MoveMem(RamFiles[R].Data, A, RamFiles[R].Size);
    KFree(RamFiles[R].Data);
  End;
  RamFiles[R].Data := A;
  RamFiles[R].Cap := Cap;
End;

{ Informations sur un chemin complet ; False s'il n'existe pas.
  Attr : attributs DOS (10h repertoire) ; Lba : secteur du CD ou -1 ;
  Ram : fichier du disque virtuel ou -1 }
Function PathInfo(Path : String; Var Attr, Size, Time, Lba, Ram : LongInt)
  : Boolean;
Var Fl : LongInt;
Begin
  PathInfo := False;
  Lba := -1; Size := 0; Time := 0; Attr := 0;
  Ram := RamFind(Path);
  If Ram >= 0 Then
  Begin
    Attr := RamFiles[Ram].Attr;
    Size := RamFiles[Ram].Size;
    Time := RamFiles[Ram].Time;
    PathInfo := True;
    Exit;
  End;
  If Copy(Path, 1, 2) = 'C:' Then
  Begin
    If IsCDir(Path) Then
    Begin
      Attr := $10;
      PathInfo := True;
    End;
    Exit;
  End;
  If Copy(Path, 1, 2) <> 'D:' Then Exit;
  If IsoLookup(Copy(Path, 3, 255), Lba, Size, Fl, Time) Then
  Begin
    If (Fl And 2) <> 0 Then Attr := $11 Else Attr := $21;
    PathInfo := True;
  End;
End;

{ Correspondance avec un masque DOS (* et ?) }
Function MatchMask(Name, Mask : String) : Boolean;
Var NB, NE, MB, ME, P : String; I : LongInt;

  Function MPart(A, B : String) : Boolean;
  Var K : LongInt;
  Begin
    MPart := False;
    K := 1;
    While K <= Length(B) Do
    Begin
      If B[K] = '*' Then
      Begin
        MPart := True;
        Exit;
      End;
      If K > Length(A) Then Exit;
      If (B[K] <> '?') And (B[K] <> A[K]) Then Exit;
      Inc(K);
    End;
    MPart := Length(A) = Length(B);
  End;

Begin
  If (Mask = '*.*') Or (Mask = '*') Then
  Begin
    MatchMask := True;
    Exit;
  End;
  I := Pos('.', Name);
  If I > 0 Then Begin NB := Copy(Name, 1, I - 1); NE := Copy(Name, I + 1, 3) End
  Else Begin NB := Name; NE := '' End;
  I := Pos('.', Mask);
  If I > 0 Then Begin MB := Copy(Mask, 1, I - 1); ME := Copy(Mask, I + 1, 3) End
  Else Begin MB := Mask; ME := '' End;
  P := ME;
  MatchMask := MPart(NB, MB) And MPart(NE, P);
End;

{ Contenu d'un fichier entier dans un bloc du tas ; adresse ou 0 }
Function LoadWholeFile(Path : String; Var Size : LongInt) : LongInt;
Var Attr, Time, Lba, Ram, A : LongInt;
Begin
  LoadWholeFile := 0;
  Path := FullPath(Path);
  If Not PathInfo(Path, Attr, Size, Time, Lba, Ram) Then Exit;
  If (Attr And $10) <> 0 Then Exit;
  A := KAlloc(Size + 16);
  If A = 0 Then Exit;
  If Ram >= 0 Then MoveMem(RamFiles[Ram].Data, A, Size)
  Else If Not CdReadBytes(Lba, 0, Size, A) Then
  Begin
    KFree(A);
    Exit;
  End;
  LoadWholeFile := A;
End;

{ ==================================================================== }
{ Partie 4 - Graphisme 8 bits, palette, police, composition, pointeur  }
{ ==================================================================== }
{ Chaque fenetre de premier niveau dessine dans sa propre surface 8 bits
  (indices de la palette systeme, comme un affichage 256 couleurs de
  Windows 95). L'ecran est compose dans un tampon (bureau puis fenetres
  dans l'ordre Z) et seule la zone modifiee est recopiee dans la memoire
  video lineaire ; le pointeur de la souris est dessine par-dessus. }

Const
  icComputer = 1;  icRecycle  = 2;  icDos      = 3;  icNotepad  = 4;
  icCalc     = 5;  icText     = 6;  icFolder   = 7;  icCdrom    = 8;
  icFloppy   = 9;  icControl  = 10; icDisplay  = 11; icRegional = 12;
  icSystem   = 13; icClock    = 14; icHelp     = 15; icRun      = 16;
  icShutdown = 17; icPaint    = 18; icInfo     = 19; icWarn     = 20;
  icError    = 21; icPrograms = 22; icDocs     = 23; icSettings = 24;
  icApp      = 25; icHardDisk = 26; icLogo     = 27; icExplorer = 28;
  icQuestion = 29;

  CurH = 19;
  CurShape : Array[0..18] Of String[12] = (
    'X           ', 'XX          ', 'XWX         ', 'XWWX        ',
    'XWWWX       ', 'XWWWWX      ', 'XWWWWWX     ', 'XWWWWWWX    ',
    'XWWWWWWWX   ', 'XWWWWWWWWX  ', 'XWWWWWWWWWX ', 'XWWWWWWXXXXX',
    'XWWWXWWX    ', 'XWWXXWWX    ', 'XWX  XWWX   ', 'XX   XWWX   ',
    'X     XWWX  ', '      XWWX  ', '       XX   ');
  WaitShape : Array[0..18] Of String[12] = (
    'XXXXXXXXXXX ', 'XWWWWWWWWWX ', ' XWWWWWWWX  ', ' XWWWWWWWX  ',
    ' XWXWXWXWX  ', ' XWWXWXWWX  ', '  XWWXWWX   ', '   XWWWX    ',
    '    XWX     ', '    XWX     ', '   XWWWX    ', '  XWWWWWX   ',
    ' XWWWXWWWX  ', ' XWWXWXWWX  ', ' XWXWXWXWX  ', ' XWWWWWWWX  ',
    'XWWWWWWWWWX ', 'XXXXXXXXXXX ', '            ');

  StaticRGB : Array[0..19] Of LongInt = (
    $000000, $800000, $008000, $808000, $000080, $800080, $008080,
    $C0C0C0, $C0DCC0, $A6CAF0,
    $FFFBF0, $A0A0A4, $808080, $FF0000, $00FF00, $FFFF00, $0000FF,
    $FF00FF, $00FFFF, $FFFFFF);

Type
  TSurf = Record
    Bits, W, H, Pitch : LongInt;
  End;

Var
  Lfb, LfbPitch : LongInt;
  Back      : TSurf;
  SysPal    : Array[0..767] Of Byte;       { R, G, B (8 bits) }
  PalVer    : LongInt;
  NcKey     : Array[0..4095] Of LongInt;   { antememoire RGB -> indice }
  NcVal     : Array[0..4095] Of Byte;
  NcVer     : Array[0..4095] Of LongInt;
  { cible de dessin courante (coordonnees ecran, bornes incluses) }
  DS        : TSurf;
  DOX, DOY  : LongInt;
  ClipX1, ClipY1, ClipX2, ClipY2 : LongInt;
  { pointeur }
  CurX, CurY : LongInt;
  CurShownB  : Boolean;
  CurKind    : LongInt;      { 0 fleche, 1 sablier, 2 personnalise }
  CurHide    : LongInt;      { compteur de ShowCursor }
  CurCustom  : LongInt;      { curseur Win32 (bits AND/XOR 32x32) }
  CurHotX, CurHotY : LongInt;

Function SurfNew(Var S : TSurf; W, H : LongInt) : Boolean;
Begin
  S.W := W; S.H := H; S.Pitch := (W + 3) And Not 3;
  S.Bits := KAlloc(S.Pitch * H + 16);
  SurfNew := S.Bits <> 0;
End;

Procedure SurfFree(Var S : TSurf);
Begin
  If S.Bits <> 0 Then KFree(S.Bits);
  S.Bits := 0; S.W := 0; S.H := 0;
End;

{ ------------------------------------------------------------------ }
{ Palette systeme                                                    }
{ ------------------------------------------------------------------ }

Procedure DacSet(I : LongInt);
Begin
  Port[$3C8] := I;
  Port[$3C9] := SysPal[I * 3] Shr 2;
  Port[$3C9] := SysPal[I * 3 + 1] Shr 2;
  Port[$3C9] := SysPal[I * 3 + 2] Shr 2;
End;

Procedure DacAll;
Var I : LongInt;
Begin
  For I := 0 To 255 Do DacSet(I);
End;

Procedure SysPalSet(I, R, G, B : LongInt);
Begin
  SysPal[I * 3] := R; SysPal[I * 3 + 1] := G; SysPal[I * 3 + 2] := B;
End;

{ 20 couleurs statiques, cube 6x6x6 et gris au milieu }
Procedure DefaultPalette;
Var I, R, G, B, V : LongInt;
Begin
  For I := 0 To 9 Do
    SysPalSet(I, (StaticRGB[I] Shr 16) And 255, (StaticRGB[I] Shr 8) And 255,
              StaticRGB[I] And 255);
  For I := 10 To 19 Do
    SysPalSet(236 + I, (StaticRGB[I] Shr 16) And 255,
              (StaticRGB[I] Shr 8) And 255, StaticRGB[I] And 255);
  I := 10;
  For R := 0 To 5 Do
    For G := 0 To 5 Do
      For B := 0 To 5 Do
      Begin
        SysPalSet(I, R * 51, G * 51, B * 51);
        Inc(I);
      End;
  For V := 0 To 19 Do
  Begin
    SysPalSet(I, 10 + V * 12, 10 + V * 12, 10 + V * 12);
    Inc(I);
  End;
  Inc(PalVer);
  DacAll;
End;

{ Indice de la palette systeme le plus proche de R, G, B }
Function NearestIdx(R, G, B : LongInt) : LongInt;
Var Key, H, I, D, BestD, Best, DR, DG, DB : LongInt;
Begin
  Key := (R Shl 16) Or (G Shl 8) Or B;
  H := ((R * 7) Xor (G * 31) Xor (B * 131) Xor (R Shr 3)) And 4095;
  If (NcVer[H] = PalVer) And (NcKey[H] = Key) Then
  Begin
    NearestIdx := NcVal[H];
    Exit;
  End;
  Best := 0; BestD := $7FFFFFFF;
  For I := 0 To 255 Do
  Begin
    DR := SysPal[I * 3] - R; DG := SysPal[I * 3 + 1] - G;
    DB := SysPal[I * 3 + 2] - B;
    D := DR * DR + DG * DG + DB * DB;
    If D < BestD Then
    Begin
      BestD := D; Best := I;
      If D = 0 Then Break;
    End;
  End;
  NcVer[H] := PalVer; NcKey[H] := Key; NcVal[H] := Best;
  NearestIdx := Best;
End;

{ COLORREF (00BBGGRR) -> indice ; PALETTEINDEX (01xxxxxx) direct }
Function ColorIdx(C : LongInt) : LongInt;
Begin
  If (C Shr 24) = 1 Then ColorIdx := C And 255
  Else ColorIdx := NearestIdx(C And 255, (C Shr 8) And 255,
                              (C Shr 16) And 255);
End;

Function IdxColor(I : LongInt) : LongInt;
Begin
  IdxColor := SysPal[I * 3] Or (SysPal[I * 3 + 1] Shl 8) Or
              (SysPal[I * 3 + 2] Shl 16);
End;

{ ------------------------------------------------------------------ }
{ Cible de dessin et primitives (bornes incluses, coord. ecran)      }
{ ------------------------------------------------------------------ }

Procedure SetTarget(Var S : TSurf; OX, OY : LongInt);
Begin
  DS := S; DOX := OX; DOY := OY;
  ClipX1 := OX; ClipY1 := OY;
  ClipX2 := OX + S.W - 1; ClipY2 := OY + S.H - 1;
End;

Procedure SetClip(X1, Y1, X2, Y2 : LongInt);
Begin
  ClipX1 := Max(X1, DOX); ClipY1 := Max(Y1, DOY);
  ClipX2 := Min(X2, DOX + DS.W - 1); ClipY2 := Min(Y2, DOY + DS.H - 1);
End;

Function ClipEmpty : Boolean;
Begin
  ClipEmpty := (ClipX1 > ClipX2) Or (ClipY1 > ClipY2);
End;

Procedure FBar(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Var Y, A, N : LongInt;
Begin
  If X1 < ClipX1 Then X1 := ClipX1;
  If Y1 < ClipY1 Then Y1 := ClipY1;
  If X2 > ClipX2 Then X2 := ClipX2;
  If Y2 > ClipY2 Then Y2 := ClipY2;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  N := X2 - X1 + 1;
  A := DS.Bits + (Y1 - DOY) * DS.Pitch + (X1 - DOX);
  For Y := Y1 To Y2 Do
  Begin
    FillMem(A, N, C);
    A := A + DS.Pitch;
  End;
End;

Procedure HLine(X1, X2, Y : LongInt; C : LongInt);
Begin
  FBar(X1, Y, X2, Y, C);
End;

Procedure VLine(X, Y1, Y2 : LongInt; C : LongInt);
Begin
  FBar(X, Y1, X, Y2, C);
End;

Procedure Pix(X, Y : LongInt; C : LongInt);
Begin
  If (X < ClipX1) Or (X > ClipX2) Or (Y < ClipY1) Or (Y > ClipY2) Then
    Exit;
  Mem[0:DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX)] := C;
End;

Function GetPix(X, Y : LongInt) : LongInt;
Begin
  If (X < DOX) Or (Y < DOY) Or (X >= DOX + DS.W) Or (Y >= DOY + DS.H) Then
    GetPix := 0
  Else
    GetPix := Mem[0:DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX)];
End;

Procedure Box(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Begin
  HLine(X1, X2, Y1, C); HLine(X1, X2, Y2, C);
  VLine(X1, Y1, Y2, C); VLine(X2, Y1, Y2, C);
End;

{ Trame : couleur C sur un point sur deux }
Procedure Dither(X1, Y1, X2, Y2 : LongInt; C : LongInt; Phase : LongInt);
Var X, Y : LongInt;
Begin
  For Y := Max(Y1, ClipY1) To Min(Y2, ClipY2) Do
    For X := Max(X1, ClipX1) To Min(X2, ClipX2) Do
      If Odd(X + Y + Phase) Then
        Mem[0:DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX)] := C;
End;

Procedure DrawChar(X, Y : LongInt; Ch : Char; C : LongInt);
Var R, CX, B, F, A : LongInt;
Begin
  If (X > ClipX2) Or (X + 7 < ClipX1) Or (Y > ClipY2) Or
     (Y + 15 < ClipY1) Then Exit;
  F := FontAddr + Ord(Ch) * 16;
  If (X >= ClipX1) And (X + 7 <= ClipX2) And (Y >= ClipY1) And
     (Y + 15 <= ClipY2) Then
  Begin
    A := DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX);
    For R := 0 To 15 Do
    Begin
      B := Mem[0:F + R];
      If B <> 0 Then
        For CX := 0 To 7 Do
          If (B And ($80 Shr CX)) <> 0 Then Mem[0:A + CX] := C;
      A := A + DS.Pitch;
    End;
    Exit;
  End;
  For R := 0 To 15 Do
  Begin
    B := Mem[0:F + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then Pix(X + CX, Y + R, C);
  End;
End;

{ Primitives et interface (reprises d'IO.PAS) }

Procedure DLine(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Var DX, DY, SX, SY, E, E2 : LongInt;
Begin
  If Y1 = Y2 Then
  Begin
    If X1 <= X2 Then HLine(X1, X2, Y1, C) Else HLine(X2, X1, Y1, C);
    Exit;
  End;
  If X1 = X2 Then
  Begin
    If Y1 <= Y2 Then VLine(X1, Y1, Y2, C) Else VLine(X1, Y2, Y1, C);
    Exit;
  End;
  DX := Abs(X2 - X1); DY := -Abs(Y2 - Y1);
  If X1 < X2 Then SX := 1 Else SX := -1;
  If Y1 < Y2 Then SY := 1 Else SY := -1;
  E := DX + DY;
  While True Do
  Begin
    Pix(X1, Y1, C);
    If (X1 = X2) And (Y1 = Y2) Then Exit;
    E2 := 2 * E;
    If E2 >= DY Then Begin E := E + DY; X1 := X1 + SX End;
    If E2 <= DX Then Begin E := E + DX; Y1 := Y1 + SY End;
  End;
End;

Function ISqrt(V : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := 0;
  While (R + 1) * (R + 1) <= V Do Inc(R);
  ISqrt := R;
End;

Procedure Disc(CX, CY, R : LongInt; C : LongInt);
Var DY, DX : LongInt;
Begin
  For DY := -R To R Do
  Begin
    DX := ISqrt(LongInt(R) * R - LongInt(DY) * DY);
    HLine(CX - DX, CX + DX, CY + DY, C);
  End;
End;

Procedure Circ(CX, CY, R : LongInt; C : LongInt);
Var DY, DX, PX : LongInt;
Begin
  PX := R;
  For DY := 0 To R Do
  Begin
    DX := ISqrt(LongInt(R) * R - LongInt(DY) * DY);
    HLine(CX + DX, CX + PX, CY + DY, C);
    HLine(CX - PX, CX - DX, CY + DY, C);
    HLine(CX + DX, CX + PX, CY - DY, C);
    HLine(CX - PX, CX - DX, CY - DY, C);
    PX := DX;
    If PX < 1 Then PX := 1;
  End;
End;

{ Tramage : couleur C sur un point sur deux (Phase 0 ou 1) }

Procedure OutTxt(X, Y : LongInt; Const S : String; C : LongInt);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
  Begin
    If S[K] <> ' ' Then DrawChar(X, Y, S[K], C);
    X := X + 8;
  End;
End;

Procedure OutBold(X, Y : LongInt; Const S : String; C : LongInt);
Begin
  OutTxt(X, Y, S, C);
  OutTxt(X + 1, Y, S, C);
End;

Function TextW(Const S : String) : LongInt;
Begin
  TextW := Length(S) * 8;
End;

{ Texte centre entre X1 et X2 }
Procedure OutCenter(X1, X2, Y : LongInt; Const S : String; C : LongInt);
Begin
  OutTxt(X1 + (X2 - X1 + 1 - TextW(S)) Div 2, Y, S, C);
End;

{ Texte tronque a MaxW pixels (avec ...) }
Function Fit(Const S : String; MaxW : LongInt) : String;
Var N : LongInt;
Begin
  N := MaxW Div 8;
  If N < 0 Then N := 0;
  If Length(S) <= N Then Fit := S
  Else If N > 3 Then Fit := Copy(S, 1, N - 3) + '...'
  Else Fit := Copy(S, 1, N);
End;

{ Caractere agrandi (Scale x Scale par point) }
Procedure BigChar(X, Y : LongInt; Ch : Char; C : LongInt; Sc : LongInt);
Var R, CX : LongInt; B : LongInt;
Begin
  For R := 0 To 15 Do
  Begin
    B := Mem[0:FontAddr + Ord(Ch) * 16 + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then
        FBar(X + CX * Sc, Y + R * Sc, X + CX * Sc + Sc - 1,
            Y + R * Sc + Sc - 1, C);
  End;
End;

Procedure BigText(X, Y : LongInt; Const S : String; C : LongInt;
                  Sc : LongInt);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    BigChar(X + (K - 1) * 8 * Sc, Y, S[K], C, Sc);
End;

{ Texte avec retour a la ligne automatique ; retourne le nombre de
  lignes. Draw = False : seulement compter }
Function WrapText(X, Y, W : LongInt; Const S : String; C : LongInt;
                  Draw : Boolean) : LongInt;
Var Cols, I, N, Last : LongInt; Line, Word0 : String;
Begin
  Cols := W Div 8;
  N := 0; Line := ''; Word0 := '';
  I := 1;
  While I <= Length(S) + 1 Do
  Begin
    If (I > Length(S)) Or (S[I] = ' ') Or (S[I] = '|') Then
    Begin
      If Length(Line) + Length(Word0) + 1 > Cols Then
      Begin
        If Line <> '' Then
        Begin
          If Draw Then OutTxt(X, Y + N * 16, Line, C);
          Inc(N);
        End;
        Line := Word0;
      End
      Else If Line = '' Then Line := Word0
      Else Line := Line + ' ' + Word0;
      Word0 := '';
      If (I <= Length(S)) And (S[I] = '|') Then
      Begin
        If Draw Then OutTxt(X, Y + N * 16, Line, C);
        Inc(N);
        Line := '';
      End;
    End
    Else
      Word0 := Word0 + S[I];
    Inc(I);
  End;
  If Line <> '' Then
  Begin
    If Draw Then OutTxt(X, Y + N * 16, Line, C);
    Inc(N);
  End;
  Last := N;
  WrapText := Last;
End;

{ ------------------------------------------------------------------ }
{ Reliefs de Windows 95                                              }
{ ------------------------------------------------------------------ }

Procedure Edge(X1, Y1, X2, Y2 : LongInt; TL, BR : LongInt);
Begin
  HLine(X1, X2 - 1, Y1, TL);
  VLine(X1, Y1, Y2 - 1, TL);
  HLine(X1, X2, Y2, BR);
  VLine(X2, Y1, Y2, BR);
End;

{ Bouton en relief (ou enfonce) }
Procedure Raised(X1, Y1, X2, Y2 : LongInt; Pressed : Boolean);
Begin
  FBar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, cSilver);
  If Pressed Then
  Begin
    Edge(X1, Y1, X2, Y2, cBlack, cWhite);
    Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cGray, cSilver);
  End
  Else
  Begin
    Edge(X1, Y1, X2, Y2, cWhite, cBlack);
    Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cSilver, cGray);
  End;
End;

{ Champ en creux (zone de saisie, liste) }
Procedure Sunken(X1, Y1, X2, Y2 : LongInt; Fill : LongInt);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cBlack, cSilver);
  FBar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, Fill);
End;

{ Cadre grave (groupe d'options) }
Procedure GroupBox(X1, Y1, X2, Y2 : LongInt; Const Title : String);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cWhite, cGray);
  If Title <> '' Then
  Begin
    FBar(X1 + 6, Y1 - 7, X1 + 9 + TextW(Title), Y1 + 8, cSilver);
    OutTxt(X1 + 8, Y1 - 7, Title, cBlack);
  End;
End;

Procedure PushButton(X1, Y1, X2, Y2 : LongInt; Const S : String;
                     Pressed, Def : Boolean);
Var D : LongInt;
Begin
  If Def Then
  Begin
    Box(X1, Y1, X2, Y2, cBlack);
    Raised(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, Pressed);
  End
  Else
    Raised(X1, Y1, X2, Y2, Pressed);
  If Pressed Then D := 1 Else D := 0;
  OutCenter(X1 + D, X2 + D, (Y1 + Y2 - 15) Div 2 + D, S, cBlack);
End;

Procedure RadioButton(X, Y : LongInt; Const S : String; On : Boolean);
Begin
  Circ(X + 6, Y + 7, 6, cGray);
  Disc(X + 6, Y + 7, 4, cWhite);
  HLine(X + 3, X + 9, Y + 13, cWhite);
  VLine(X + 12, Y + 4, Y + 10, cWhite);
  If On Then Disc(X + 6, Y + 7, 2, cBlack);
  OutTxt(X + 18, Y, S, cBlack);
End;

{ Petit triangle (fleche) : Dir 0 droite, 1 bas, 2 haut }
Procedure Arrow(X, Y, Dir : LongInt; C : LongInt);
Var I : LongInt;
Begin
  For I := 0 To 3 Do
    Case Dir Of
      0 : VLine(X + I, Y + I, Y + 6 - I, C);
      1 : HLine(X + I, X + 6 - I, Y + I, C);
    Else
      HLine(X + 3 - I, X + 3 + I, Y + I, C);
    End;
End;


{ ------------------------------------------------------------------ }
{ Icones (dessinees dans une grille de 32x32, mises a l'echelle S)   }
{ ------------------------------------------------------------------ }

Var
  IcX, IcY, IcS : LongInt;

Function IcP(V : LongInt) : LongInt;
Begin
  IcP := V * IcS Div 32;
End;

Procedure QR(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Begin
  FBar(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2 + 1) - 1,
      IcY + IcP(Y2 + 1) - 1, C);
End;

Procedure QB(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Var A, B, CC, D : LongInt;
Begin
  A := IcX + IcP(X1); B := IcY + IcP(Y1);
  CC := IcX + IcP(X2 + 1) - 1; D := IcY + IcP(Y2 + 1) - 1;
  Box(A, B, CC, D, C);
End;

Procedure QL(X1, Y1, X2, Y2 : LongInt; C : LongInt);
Begin
  DLine(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2), IcY + IcP(Y2), C);
End;

Procedure QD(CX, CY, R : LongInt; C : LongInt);
Begin
  Disc(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

Procedure QC(CX, CY, R : LongInt; C : LongInt);
Begin
  Circ(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

{ Boite en relief (fond F, contour noir) }
Procedure IFrame(X1, Y1, X2, Y2 : LongInt; F : LongInt);
Begin
  QR(X1, Y1, X2, Y2, F);
  QB(X1, Y1, X2, Y2, cBlack);
End;

Procedure IconMonitor(Screen : LongInt);
Begin
  IFrame(4, 2, 27, 21, cSilver);
  QR(5, 3, 26, 3, cWhite);
  IFrame(7, 5, 24, 17, Screen);
  IFrame(11, 22, 20, 24, cSilver);
End;

Procedure IconFolder(C : LongInt);
Begin
  IFrame(3, 6, 13, 10, C);
  IFrame(3, 9, 28, 27, C);
  QR(4, 10, 27, 10, cWhite);
End;

Procedure IconPage;
Begin
  IFrame(6, 2, 25, 29, cWhite);
  QR(20, 2, 25, 7, cSilver);
  QL(20, 2, 25, 7, cBlack);
End;

Procedure PaintIcon(Id, X, Y, S : LongInt);
Var I : LongInt;
Begin
  IcX := X; IcY := Y; IcS := S;
  Case Id Of
    icComputer, icSystem :
    Begin
      IconMonitor(cTeal);
      IFrame(2, 25, 29, 29, cSilver);
      QR(5, 27, 26, 27, cGray);
      If Id = icSystem Then
      Begin
        QR(14, 7, 17, 8, cWhite);
        QR(14, 10, 17, 15, cWhite);
      End;
    End;
    icDisplay :
    Begin
      IconMonitor(cBlue);
      QR(8, 12, 23, 16, cGreen);
      QD(19, 9, 3, cYellow);
    End;
    icRecycle :
    Begin
      IFrame(7, 9, 24, 29, cSilver);
      QR(8, 10, 9, 28, cWhite);
      IFrame(5, 5, 26, 8, cSilver);
      QR(13, 3, 18, 5, cGray);
      For I := 0 To 2 Do QR(12 + I * 4, 12, 12 + I * 4, 26, cGray);
    End;
    icDos :
    Begin
      IFrame(2, 4, 29, 27, cSilver);
      QR(3, 5, 28, 9, cNavy);
      QR(3, 10, 28, 26, cBlack);
      QR(6, 13, 9, 14, cSilver);
      QR(11, 13, 14, 14, cSilver);
      QR(6, 18, 12, 19, cSilver);
      QR(14, 18, 16, 19, cWhite);
    End;
    icNotepad, icText :
    Begin
      IconPage;
      For I := 0 To 4 Do QR(9, 10 + I * 4, 22, 10 + I * 4, cGray);
      If Id = icNotepad Then
      Begin
        QR(6, 2, 25, 5, cNavy);
        For I := 0 To 4 Do QR(8 + I * 4, 1, 8 + I * 4, 4, cSilver);
      End;
    End;
    icCalc :
    Begin
      IFrame(7, 2, 24, 29, cSilver);
      IFrame(9, 4, 22, 9, cWhite);
      For I := 0 To 11 Do
        QR(10 + (I Mod 3) * 4, 12 + (I Div 3) * 4,
           11 + (I Mod 3) * 4, 13 + (I Div 3) * 4, cBlack);
      QR(23 - 2, 12, 22, 25, cRed);
    End;
    icFolder : IconFolder(cYellow);
    icPrograms :
    Begin
      IconFolder(cYellow);
      IFrame(10, 13, 22, 23, cWhite);
      QR(11, 14, 21, 15, cNavy);
    End;
    icDocs :
    Begin
      IconFolder(cYellow);
      IFrame(12, 11, 22, 25, cWhite);
      QR(14, 15, 20, 15, cGray); QR(14, 18, 20, 18, cGray);
    End;
    icSettings, icControl :
    Begin
      IconFolder(cYellow);
      IFrame(9, 14, 17, 22, cSilver);
      QR(11, 16, 15, 20, cTeal);
      QD(22, 19, 4, cRed);
      QC(22, 19, 4, cBlack);
    End;
    icCdrom :
    Begin
      IFrame(3, 14, 28, 25, cSilver);
      QR(6, 20, 25, 21, cBlack);
      QR(22, 16, 25, 17, cLime);
      QD(16, 8, 7, cSilver);
      QC(16, 8, 7, cGray);
      QD(16, 8, 2, cWhite);
      QL(12, 4, 15, 7, cAqua);
    End;
    icFloppy, icHardDisk :
    Begin
      IFrame(3, 12, 28, 23, cSilver);
      QR(4, 13, 27, 13, cWhite);
      If Id = icFloppy Then QR(8, 17, 23, 18, cBlack)
      Else QR(6, 19, 12, 20, cGray);
      QR(23, 20, 25, 21, cLime);
    End;
    icRegional :
    Begin
      QD(16, 16, 13, cBlue);
      QR(9, 9, 15, 15, cGreen);
      QR(17, 17, 24, 23, cGreen);
      QR(12, 19, 15, 25, cGreen);
      QC(16, 16, 13, cNavy);
    End;
    icClock :
    Begin
      QD(16, 16, 13, cWhite);
      QC(16, 16, 13, cBlack);
      QL(16, 16, 16, 7, cBlack);
      QL(16, 16, 23, 16, cBlack);
      For I := 0 To 3 Do
        QR(15 + (I Mod 2) * 0, 4, 16, 5, cBlack);
      QR(26, 15, 27, 16, cBlack);
      QR(15, 26, 16, 27, cBlack);
      QR(4, 15, 5, 16, cBlack);
    End;
    icHelp :
    Begin
      IFrame(5, 3, 26, 28, cNavy);
      QR(7, 5, 24, 26, cBlue);
      QR(23, 4, 25, 27, cWhite);
      QR(12, 9, 18, 10, cYellow);
      QR(18, 10, 19, 14, cYellow);
      QR(14, 15, 18, 16, cYellow);
      QR(14, 17, 15, 19, cYellow);
      QR(14, 22, 15, 23, cYellow);
    End;
    icRun :
    Begin
      IFrame(2, 6, 25, 27, cSilver);
      QR(3, 7, 24, 10, cNavy);
      QR(3, 11, 24, 26, cWhite);
      QL(14, 18, 29, 3, cBlack);
      QL(15, 18, 30, 3, cBlack);
      QR(24, 2, 30, 3, cBlack);
      QR(29, 2, 30, 8, cBlack);
    End;
    icShutdown :
    Begin
      IconMonitor(cBlack);
      IFrame(2, 25, 29, 29, cSilver);
      QC(16, 11, 4, cRed);
      QR(15, 5, 16, 11, cRed);
    End;
    icPaint :
    Begin
      QD(16, 17, 13, cSilver);
      QC(16, 17, 13, cBlack);
      QD(10, 12, 3, cRed);
      QD(18, 9, 3, cYellow);
      QD(24, 15, 3, cBlue);
      QD(22, 23, 3, cLime);
      QD(11, 21, 3, cWhite);
      QL(4, 30, 15, 17, cMaroon);
      QL(5, 30, 16, 17, cMaroon);
    End;
    icInfo :
    Begin
      QD(16, 15, 13, cWhite);
      QC(16, 15, 13, cBlack);
      QR(14, 7, 17, 10, cBlue);
      QR(14, 13, 17, 24, cBlue);
      QR(12, 23, 19, 24, cBlue);
    End;
    icWarn :
    Begin
      For I := 0 To 25 Do
        QR(16 - I Div 2, 3 + I, 16 + I Div 2, 3 + I, cYellow);
      QL(16, 3, 3, 28, cBlack);
      QL(16, 3, 29, 28, cBlack);
      QR(3, 28, 29, 28, cBlack);
      QR(15, 10, 17, 20, cBlack);
      QR(15, 23, 17, 25, cBlack);
    End;
    icError :
    Begin
      QD(16, 16, 13, cRed);
      QC(16, 16, 13, cMaroon);
      QL(11, 11, 21, 21, cWhite); QL(12, 11, 22, 21, cWhite);
      QL(21, 11, 11, 21, cWhite); QL(22, 11, 12, 21, cWhite);
    End;
    icQuestion :
    Begin
      QD(16, 15, 13, cWhite);
      QC(16, 15, 13, cBlack);
      QR(12, 8, 19, 10, cBlue);
      QR(18, 10, 20, 14, cBlue);
      QR(15, 14, 18, 17, cBlue);
      QR(15, 21, 17, 23, cBlue);
    End;
    icApp :
    Begin
      IFrame(3, 6, 28, 26, cSilver);
      QR(4, 7, 27, 10, cNavy);
      QR(4, 11, 27, 25, cWhite);
    End;
    icExplorer :
    Begin
      IconFolder(cYellow);
      QD(19, 18, 6, cAqua);
      QC(19, 18, 6, cNavy);
      QL(14, 23, 9, 28, cBlack);
      QL(15, 23, 10, 28, cBlack);
    End;
    icLogo :
    Begin
      QR(2, 4, 29, 27, cNavy);
      QR(5, 7, 26, 10, cRed);
      QR(5, 12, 26, 15, cYellow);
      QR(5, 17, 26, 20, cLime);
      QR(5, 22, 26, 25, cAqua);
    End;
  End;
End;



{ ------------------------------------------------------------------ }
{ Ecran : zone modifiee, recopie vers la memoire video, pointeur     }
{ ------------------------------------------------------------------ }

Var
  Dirty   : TRect;
  CurMap  : Array[0..1023] Of Byte;  { 0 transparent 1 noir 2 blanc 3 inv. }
  CurW, CurHh : LongInt;

Procedure ComposeRect(R : TRect); Forward;

Procedure MarkDirty(X1, Y1, X2, Y2 : LongInt);
Var R : TRect;
Begin
  SetR(R, Max(X1, 0), Max(Y1, 0), Min(X2, ScrW), Min(Y2, ScrH));
  RUnion(Dirty, R);
End;

Procedure MarkAll;
Begin
  SetR(Dirty, 0, 0, ScrW, ScrH);
End;

{ Recopier une zone du tampon dans la memoire video }
Procedure LfbCopy(R : TRect);
Var Y, S, D, N : LongInt;
Begin
  If R.L < 0 Then R.L := 0;
  If R.T < 0 Then R.T := 0;
  If R.R > ScrW Then R.R := ScrW;
  If R.B > ScrH Then R.B := ScrH;
  If (R.L >= R.R) Or (R.T >= R.B) Then Exit;
  N := R.R - R.L;
  S := Back.Bits + R.T * Back.Pitch + R.L;
  D := Lfb + R.T * LfbPitch + R.L;
  For Y := R.T To R.B - 1 Do
  Begin
    MoveMem(S, D, N);
    S := S + Back.Pitch;
    D := D + LfbPitch;
  End;
End;

{ Forme du pointeur : fleche (0), sablier (1) }
Procedure CursorSetShape(K : LongInt);
Var R, I : LongInt; Ch : Char;
Begin
  FillMem(LongInt(@CurMap), 1024, 0);
  For R := 0 To CurH - 1 Do
    For I := 1 To 12 Do
    Begin
      If K = 1 Then Ch := WaitShape[R][I] Else Ch := CurShape[R][I];
      If Ch = 'X' Then CurMap[R * 32 + I - 1] := 1
      Else If Ch = 'W' Then CurMap[R * 32 + I - 1] := 2;
    End;
  CurW := 12; CurHh := CurH;
  If K = 1 Then
  Begin
    CurHotX := 5; CurHotY := 9;
  End
  Else
  Begin
    CurHotX := 0; CurHotY := 0;
  End;
  CurKind := K;
End;

Procedure CursorRect(Var R : TRect);
Begin
  SetR(R, CurX - CurHotX, CurY - CurHotY, CurX - CurHotX + CurW,
       CurY - CurHotY + CurHh);
End;

Procedure CursorDraw;
Var X, Y, PX, PY, V, A : LongInt;
Begin
  If CurHide < 0 Then Exit;
  For Y := 0 To CurHh - 1 Do
  Begin
    PY := CurY - CurHotY + Y;
    If (PY >= 0) And (PY < ScrH) Then
      For X := 0 To CurW - 1 Do
      Begin
        PX := CurX - CurHotX + X;
        V := CurMap[Y * 32 + X];
        If (V <> 0) And (PX >= 0) And (PX < ScrW) Then
        Begin
          A := Lfb + PY * LfbPitch + PX;
          If V = 1 Then Mem[0:A] := cBlack
          Else If V = 2 Then Mem[0:A] := cWhite
          Else Mem[0:A] := Mem[0:Back.Bits + PY * Back.Pitch + PX] Xor 255;
        End;
      End;
  End;
  CurShownB := True;
End;

Procedure CursorErase;
Var R : TRect;
Begin
  If Not CurShownB Then Exit;
  CursorRect(R);
  LfbCopy(R);
  CurShownB := False;
End;

Procedure CursorMoveTo(X, Y : LongInt);
Begin
  If (X = CurX) And (Y = CurY) And CurShownB Then Exit;
  CursorErase;
  CurX := X; CurY := Y;
  CursorDraw;
End;

{ Composer la zone modifiee et l'afficher }
Procedure FlushScreen;
Var R, C, I : TRect;
Begin
  If (Dirty.L >= Dirty.R) Or (Dirty.T >= Dirty.B) Then Exit;
  R := Dirty;
  SetR(Dirty, 0, 0, 0, 0);
  ComposeRect(R);
  CursorRect(C);
  If RInter(I, R, C) Then
  Begin
    LfbCopy(R);
    CursorDraw;
  End
  Else
    LfbCopy(R);
End;

{ ==================================================================== }
{ Partie 5 - Taches cooperatives, synchronisation, files de messages   }
{ ==================================================================== }
{ La tache 0 est celle du noyau (peripheriques, bureau, composition de
  l'ecran) ; elle est toujours prete. Les taches des programmes Win32
  cedent le processeur dans les fonctions bloquantes. Chaque tache a un
  TIB (segment FS) : +0 chaine SEH, +4 sommet de pile, +8 limite,
  +18h adresse du TIB, +20h processus, +24h tache, +2Ch TLS. }

Const
  tsReady = 0; tsSleep = 1; tsWait = 2; tsMsg = 3; tsDead = 4;
  TlsSlots = 64;

Type
  TThread = Record
    Used     : Boolean;
    Esp      : LongInt;
    Stack    : LongInt;
    StackSz  : LongInt;
    Tib      : LongInt;
    State    : LongInt;
    WakeAt   : LongInt;
    WaitH    : LongInt;
    LastErr  : LongInt;
    QHead, QTail : LongInt;
    QuitFlag : Boolean;
    QuitCode : LongInt;
    Start, Param : LongInt;
    ExitCode : LongInt;
    KObj     : LongInt;
    IsApp    : Boolean;
    PaintReq : Boolean;
  End;

  TMsgRec = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
  End;

  TMMTimer = Record
    Used : Boolean;
    Delay, Next, Proc, User, Flags : LongInt;
  End;

Var
  Threads  : Array[0..MaxThread - 1] Of TThread;
  MsgQ     : Array[0..MaxThread * MaxQueue - 1] Of TMsgRec;
  CurT     : LongInt;
  FpuArea  : Array[0..MaxThread * 112 - 1] Of Byte;
  SwSave   : LongInt;
  SwNew    : LongInt;
  NextTid  : LongInt;
  MMTimers : Array[0..MaxMMTimer - 1] Of TMMTimer;
  InMMTimer : Boolean;
  AppRunning : Boolean;
  TlsUsed  : Array[0..TlsSlots - 1] Of Boolean;

Function ThreadId(T : LongInt) : LongInt;
Begin
  ThreadId := $100 + T * 4;
End;

Function ThreadOfId(Id : LongInt) : LongInt;
Begin
  If (Id < $100) Or (Id >= $100 + MaxThread * 4) Then ThreadOfId := -1
  Else ThreadOfId := (Id - $100) Div 4;
End;

Procedure ThreadSetFs(T : LongInt);
Begin
  SetFsBase(Threads[T].Tib);
End;

Function NewTib(T, StackTop, StackSz : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := KAlloc(4096 + TlsSlots * 4);
  MemL[0:A] := -1;
  MemL[0:A + 4] := StackTop;
  MemL[0:A + 8] := StackTop - StackSz;
  MemL[0:A + $18] := A;
  MemL[0:A + $20] := $50;
  MemL[0:A + $24] := ThreadId(T);
  MemL[0:A + $2C] := A + 4096;
  NewTib := A;
End;

{ Changement de contexte vers SwNew (sauvegarde dans [SwSave]) }
Procedure SwitchCtx;
Begin
  asm
    pushad
    pushfd
    mov eax,SwSave
    mov [eax],esp
    mov esp,SwNew
    popfd
    popad
  end;
End;

Function ObjSignaled(H : LongInt; Consume : Boolean) : Boolean; Forward;
Function MsgPending(T : LongInt) : Boolean; Forward;
Procedure RunMMTimers; Forward;

Function ThreadRunnable(T : LongInt) : Boolean;
Begin
  ThreadRunnable := False;
  If Not Threads[T].Used Then Exit;
  Case Threads[T].State Of
    tsReady : ThreadRunnable := True;
    tsSleep : ThreadRunnable := Ticks >= Threads[T].WakeAt;
    tsWait :
      ThreadRunnable := ObjSignaled(Threads[T].WaitH, False) Or
                        ((Threads[T].WakeAt >= 0) And
                         (Ticks >= Threads[T].WakeAt));
    tsMsg :
      ThreadRunnable := MsgPending(T) Or
                        ((Threads[T].WakeAt >= 0) And
                         (Ticks >= Threads[T].WakeAt));
  End;
End;

{ Passer a la tache suivante prete (tourniquet) }
Procedure KSchedule;
Var I, N, A : LongInt;
Begin
  N := -1;
  For I := 1 To MaxThread Do
    If ThreadRunnable((CurT + I) Mod MaxThread) Then
    Begin
      N := (CurT + I) Mod MaxThread;
      Break;
    End;
  If (N < 0) Or (N = CurT) Then Exit;
  { etat du coprocesseur de la tache quittee (FNSAVE reinitialise) }
  A := LongInt(@FpuArea) + CurT * 112;
  asm
    mov eax,A
    fnsave [eax]
  end;
  SwSave := LongInt(@Threads[CurT].Esp);
  SwNew := Threads[N].Esp;
  CurT := N;
  HeapOwner := Ord(Threads[N].IsApp);
  ThreadSetFs(N);
  SliceStart := Ticks;
  SwitchCtx;
  HeapOwner := Ord(Threads[CurT].IsApp);
  A := LongInt(@FpuArea) + CurT * 112;
  asm
    mov eax,A
    frstor [eax]
  end;
End;

{ Fin de l'interruption d'horloge : une tache Win32 qui execute son
  propre code (jamais le noyau) depuis plus de 20 ms cede le processeur,
  comme sous Windows 95 (multitache preemptif des fils Win32) }
Procedure TimerTail;
Var F, Eip : LongInt;
Begin
  asm
    mov eax,[ebp]
    mov F,eax
  end;
  If (CurT <= 0) Or (Ticks - SliceStart < 20) Then Exit;
  If Not Threads[CurT].IsApp Then Exit;
  Eip := MemL[0:F + 36];
  If (Eip >= KImgLo) And (Eip < KImgHi) Then Exit;
  KSchedule;
End;

{ Ceder le processeur (la tache reste prete) }
Procedure KYield;
Begin
  Threads[CurT].State := tsReady;
  KSchedule;
End;

{ Bloquer la tache courante jusqu'a ce qu'elle redevienne executable }
Procedure KBlock;
Begin
  While Not ThreadRunnable(CurT) Do
  Begin
    If CurT = 0 Then
    Begin
      Threads[0].State := tsReady;
      Exit;
    End;
    KSchedule;
  End;
  Threads[CurT].State := tsReady;
End;

Procedure KSleep(Ms : LongInt);
Begin
  If CurT = 0 Then
  Begin
    KDelay(Ms);
    Exit;
  End;
  Threads[CurT].State := tsSleep;
  Threads[CurT].WakeAt := Ticks + Ms;
  KBlock;
End;

Procedure ExitThreadK(Code : LongInt); Forward;

{ Point d'entree d'une nouvelle tache (atteint par le RET de SwitchCtx) }
Procedure ThreadStartup;
Var S, P, R : LongInt;
Begin
  S := Threads[CurT].Start;
  P := Threads[CurT].Param;
  asm
    sti
    mov eax,P
    push eax
    mov eax,S
    call eax
    mov R,eax
  end;
  ExitThreadK(R);
End;

{ Creer une tache (Start(Param), convention stdcall) ; indice ou -1 }
Function ThreadNew(Start, Param, StackSz : LongInt; IsApp : Boolean)
  : LongInt;
Var T, I, Top, FP : LongInt;
Begin
  ThreadNew := -1;
  T := -1;
  For I := 1 To MaxThread - 1 Do
    If Not Threads[I].Used Then
    Begin
      T := I;
      Break;
    End;
  If T < 0 Then Exit;
  If StackSz < 65536 Then StackSz := 65536;
  If StackSz > 4194304 Then StackSz := 4194304;
  Threads[T].Stack := KAlloc(StackSz);
  If Threads[T].Stack = 0 Then Exit;
  Threads[T].Used := True;
  Threads[T].StackSz := StackSz;
  Top := (Threads[T].Stack + StackSz - 64) And Not 15;
  Threads[T].Tib := NewTib(T, Top, StackSz);
  Threads[T].State := tsReady;
  Threads[T].WakeAt := -1;
  Threads[T].WaitH := 0;
  Threads[T].LastErr := 0;
  Threads[T].QHead := 0; Threads[T].QTail := 0;
  Threads[T].QuitFlag := False;
  Threads[T].Start := Start;
  Threads[T].Param := Param;
  Threads[T].ExitCode := 259;
  Threads[T].IsApp := IsApp;
  Threads[T].PaintReq := False;
  Threads[T].KObj := KObjNew(koThread);
  If Threads[T].KObj >= 0 Then KObjs[Threads[T].KObj].F1 := T;
  { cadre initial : EFLAGS, PUSHAD, puis EBP -> [0, ThreadStartup] }
  FP := Top - 16;
  MemL[0:FP] := 0;
  MemL[0:FP + 4] := LongInt(@ThreadStartup);
  Threads[T].Esp := FP - 64;
  MemL[0:Threads[T].Esp] := $202;
  For I := 1 To 8 Do MemL[0:Threads[T].Esp + I * 4] := 0;
  MemL[0:Threads[T].Esp + 12] := FP;
  ThreadNew := T;
End;

Procedure ExitThreadK(Code : LongInt);
Begin
  Threads[CurT].ExitCode := Code;
  Threads[CurT].State := tsDead;
  If CurT = 0 Then Exit;
  KSchedule;
End;

{ Liberer les taches terminees (appele par la tache 0) }
Procedure ReapThreads;
Var I : LongInt;
Begin
  For I := 1 To MaxThread - 1 Do
    If Threads[I].Used And (Threads[I].State = tsDead) And (I <> CurT) Then
    Begin
      KFree(Threads[I].Stack);
      KFree(Threads[I].Tib);
      Threads[I].Used := False;
      If Threads[I].KObj >= 0 Then
        KObjs[Threads[I].KObj].F2 := 1;    { tache terminee : signalee }
    End;
End;

Procedure ThreadInit0;
Begin
  Threads[0].Used := True;
  Threads[0].StackSz := $80000;
  Threads[0].Tib := NewTib(0, KStackTop, $80000);
  Threads[0].State := tsReady;
  Threads[0].KObj := -1;
  Threads[0].IsApp := False;
  CurT := 0;
  ThreadSetFs(0);
End;

{ ------------------------------------------------------------------ }
{ Objets de synchronisation                                          }
{ ------------------------------------------------------------------ }

Function ObjSignaled(H : LongInt; Consume : Boolean) : Boolean;
Var I : LongInt;
Begin
  ObjSignaled := False;
  I := KObjOf(H, 0);
  If I < 0 Then
  Begin
    ObjSignaled := True;
    Exit;
  End;
  Case KObjs[I].Kind Of
    koEvent :
      If KObjs[I].F1 <> 0 Then
      Begin
        ObjSignaled := True;
        If Consume And (KObjs[I].F2 = 0) Then KObjs[I].F1 := 0;
      End;
    koSemaphore :
      If KObjs[I].F1 > 0 Then
      Begin
        ObjSignaled := True;
        If Consume Then Dec(KObjs[I].F1);
      End;
    koMutex :
      If (KObjs[I].F1 = 0) Or (KObjs[I].F1 = ThreadId(CurT)) Then
      Begin
        ObjSignaled := True;
        If Consume Then
        Begin
          KObjs[I].F1 := ThreadId(CurT);
          Inc(KObjs[I].F2);
        End;
      End;
    koThread :
      ObjSignaled := (KObjs[I].F2 <> 0) Or
                     Not Threads[KObjs[I].F1].Used Or
                     (Threads[KObjs[I].F1].State = tsDead);
    koProcess :
      ObjSignaled := KObjs[I].F2 <> 0;
  Else
    ObjSignaled := True;
  End;
End;

{ Attente d'un objet : 0 signale, 102h delai ecoule }
Function KWait(H, Ms : LongInt) : LongInt;
Begin
  If ObjSignaled(H, True) Then
  Begin
    KWait := 0;
    Exit;
  End;
  KWait := $102;
  If Ms = 0 Then Exit;
  Threads[CurT].State := tsWait;
  Threads[CurT].WaitH := H;
  If Ms = -1 Then Threads[CurT].WakeAt := -1
  Else Threads[CurT].WakeAt := Ticks + Ms;
  Repeat
    If CurT = 0 Then KDelay(1) Else KSchedule;
    If ObjSignaled(H, True) Then
    Begin
      Threads[CurT].State := tsReady;
      KWait := 0;
      Exit;
    End;
    If (Ms <> -1) And (Ticks >= Threads[CurT].WakeAt) Then
    Begin
      Threads[CurT].State := tsReady;
      Exit;
    End;
    Threads[CurT].State := tsWait;
  Until False;
End;

{ ------------------------------------------------------------------ }
{ Files de messages                                                  }
{ ------------------------------------------------------------------ }

Function QPost(T, Hwnd, Msg, WP, LP : LongInt) : Boolean;
Var N, I : LongInt;
Begin
  QPost := False;
  If (T < 0) Or (T >= MaxThread) Or Not Threads[T].Used Then Exit;
  { regrouper les deplacements de la souris }
  If (Msg = $200) And (Threads[T].QTail <> Threads[T].QHead) Then
  Begin
    I := (Threads[T].QTail + MaxQueue - 1) Mod MaxQueue;
    If (MsgQ[T * MaxQueue + I].Msg = $200) And
       (MsgQ[T * MaxQueue + I].Hwnd = Hwnd) Then
    Begin
      MsgQ[T * MaxQueue + I].WP := WP;
      MsgQ[T * MaxQueue + I].LP := LP;
      MsgQ[T * MaxQueue + I].X := CurX;
      MsgQ[T * MaxQueue + I].Y := CurY;
      MsgQ[T * MaxQueue + I].Time := Ticks;
      QPost := True;
      Exit;
    End;
  End;
  N := (Threads[T].QTail + 1) Mod MaxQueue;
  If N = Threads[T].QHead Then Exit;
  I := T * MaxQueue + Threads[T].QTail;
  MsgQ[I].Hwnd := Hwnd; MsgQ[I].Msg := Msg;
  MsgQ[I].WP := WP; MsgQ[I].LP := LP;
  MsgQ[I].Time := Ticks; MsgQ[I].X := CurX; MsgQ[I].Y := CurY;
  Threads[T].QTail := N;
  QPost := True;
End;

{ Multimedia : timeSetEvent (appeles par la tache 0) }
Procedure RunMMTimers;
Var I, P, U, Id : LongInt;
Begin
  If InMMTimer Then Exit;
  InMMTimer := True;
  For I := 0 To MaxMMTimer - 1 Do
    If MMTimers[I].Used And (Ticks >= MMTimers[I].Next) Then
    Begin
      P := MMTimers[I].Proc; U := MMTimers[I].User; Id := I + 1;
      If (MMTimers[I].Flags And 1) <> 0 Then
        MMTimers[I].Next := Ticks + MMTimers[I].Delay
      Else
        MMTimers[I].Used := False;
      If (MMTimers[I].Flags And $30) <> 0 Then
      Begin
        { TIME_CALLBACK_EVENT_SET / PULSE : P est un evenement }
        Id := KObjOf(P, koEvent);
        If Id >= 0 Then KObjs[Id].F1 := 1;
      End
      Else If P <> 0 Then
        asm
          push 0
          push 0
          mov eax,U
          push eax
          push 0
          mov eax,Id
          push eax
          mov eax,P
          call eax
        end;
    End;
  InMMTimer := False;
End;

{ ==================================================================== }
{ Partie 6 - Gestionnaire de fenetres (USER) et files de messages      }
{ ==================================================================== }
{ Les fenetres de premier niveau ont leur propre surface (cadre compris)
  ; les fenetres filles dessinent dans la surface de leur ancetre. Le
  noyau dessine le cadre (bordure, barre de titre, boutons) a la maniere
  de Windows 95 et gere lui-meme le deplacement des fenetres ; la zone
  client des fenetres Win32 est peinte par le programme (WM_PAINT). Les
  fenetres du noyau (bureau, barre des taches, menus, Poste de travail,
  boites de dialogue...) ont une sorte interne (IKind). }

Const
  WS_POPUP = LongInt($80000000); WS_CHILD = $40000000;
  WS_MINIMIZE = $20000000; WS_VISIBLE = $10000000; WS_DISABLED = $08000000;
  WS_MAXIMIZE = $01000000; WS_CAPTION = $00C00000; WS_BORDER = $00800000;
  WS_DLGFRAME = $00400000; WS_VSCROLL = $00200000; WS_HSCROLL = $00100000;
  WS_SYSMENU = $00080000; WS_THICKFRAME = $00040000;
  WS_MINIMIZEBOX = $00020000; WS_MAXIMIZEBOX = $00010000;
  WS_EX_DLGMODALFRAME = 1; WS_EX_TOPMOST = 8; WS_EX_TOOLWINDOW = $80;
  WS_EX_CLIENTEDGE = $200;

  WM_CREATE = 1; WM_DESTROY = 2; WM_MOVE = 3; WM_SIZE = 5;
  WM_ACTIVATE = 6; WM_SETFOCUS = 7; WM_KILLFOCUS = 8; WM_ENABLE = $A;
  WM_SETTEXT = $C; WM_GETTEXT = $D; WM_GETTEXTLENGTH = $E; WM_PAINT = $F;
  WM_CLOSE = $10; WM_QUIT = $12; WM_ERASEBKGND = $14; WM_SYSCOLORCHANGE = $15;
  WM_SHOWWINDOW = $18; WM_ACTIVATEAPP = $1C; WM_SETCURSOR = $20;
  WM_MOUSEACTIVATE = $21; WM_GETMINMAXINFO = $24; WM_SETFONT = $30;
  WM_GETFONT = $31; WM_WINDOWPOSCHANGED = $47; WM_NCCREATE = $81;
  WM_NCDESTROY = $82; WM_NCCALCSIZE = $83; WM_NCHITTEST = $84;
  WM_NCPAINT = $85; WM_NCACTIVATE = $86; WM_GETDLGCODE = $87;
  WM_KEYDOWN = $100; WM_KEYUP = $101; WM_CHAR = $102; WM_SYSKEYDOWN = $104;
  WM_SYSKEYUP = $105; WM_SYSCHAR = $106; WM_INITDIALOG = $110;
  WM_COMMAND = $111; WM_SYSCOMMAND = $112; WM_TIMER = $113;
  WM_HSCROLL = $114; WM_VSCROLL = $115; WM_INITMENU = $116;
  WM_INITMENUPOPUP = $117; WM_MENUSELECT = $11F; WM_ENTERIDLE = $121;
  WM_CTLCOLORMSGBOX = $132; WM_CTLCOLORSTATIC = $138;
  WM_MOUSEMOVE = $200; WM_LBUTTONDOWN = $201; WM_LBUTTONUP = $202;
  WM_LBUTTONDBLCLK = $203; WM_RBUTTONDOWN = $204; WM_RBUTTONUP = $205;
  WM_RBUTTONDBLCLK = $206; WM_QUERYNEWPALETTE = $30F;
  WM_PALETTEISCHANGING = $310; WM_PALETTECHANGED = $311; WM_USER = $400;

  SC_SIZE = $F000; SC_MOVE = $F010; SC_MINIMIZE = $F020;
  SC_MAXIMIZE = $F030; SC_CLOSE = $F060; SC_RESTORE = $F120;

  CS_DBLCLKS = 8; CS_OWNDC = $20; CS_CLASSDC = $40;

  { sortes internes de fenetres }
  ikNone = 0; ikTaskbar = 1; ikMenu = 2; ikExplorer = 3; ikMsgBox = 4;
  ikAbout = 5; ikRun = 6; ikShutdown = 7; ikHelp = 8; ikWelcome = 9;
  ikNotepad = 10; ikButton = 20; ikStatic = 21; ikEdit = 22;
  ikListBox = 23; ikScrollBar = 24; ikComboBox = 25; ikDialog = 26;
  ikMdiClient = 27;

Type
  TClass = Record
    Used   : Boolean;
    Name   : String[63];
    Atom   : LongInt;
    Style, Proc, ClsExtra, WndExtra, Inst : LongInt;
    Icon, Cursor, Brush, MenuName : LongInt;
    IKind  : LongInt;
    Extra  : LongInt;
  End;

  TWnd = Record
    Used     : Boolean;
    Visible  : Boolean;
    Enabled  : Boolean;
    Destroying : Boolean;
    Parent, Owner, Cls : LongInt;
    Style, ExStyle : LongInt;
    X, Y, W, H : LongInt;    { relatif au client du parent (ou ecran) }
    Text     : String[127];
    Proc     : LongInt;
    IKind    : LongInt;
    Thread   : LongInt;
    Id       : LongInt;
    Menu     : LongInt;
    UserData : LongInt;
    Extra, ExtraSz : LongInt;
    Inst     : LongInt;
    Upd      : TRect;
    UpdErase : Boolean;
    Surf     : TSurf;
    Min, Max : Boolean;
    NX, NY, NW, NH : LongInt;
    CL, CT, CR, CB : LongInt;    { client : decalages dans la fenetre }
    OwnDC    : LongInt;
    Seq      : LongInt;           { ordre de creation }
    NeedNc   : Boolean;
    KNeedPaint : Boolean;
    K1, K2, K3, K4 : LongInt;     { etat des fenetres internes }
    KS       : String;
    Font     : LongInt;
    DlgProc  : LongInt;
    DlgResult : LongInt;
    DlgEnded : Boolean;
    Cursor   : LongInt;
    HScrollPos, VScrollPos : LongInt;
  End;

  TProp = Record
    Used : Boolean;
    Wnd  : LongInt;
    Name : String[63];
    Val  : LongInt;
  End;

  TTimerW = Record
    Used : Boolean;
    Wnd, Id, Elapse, Next, Proc, Thread : LongInt;
  End;

Var
  Classes  : Array[0..MaxClass - 1] Of TClass;
  Wnds     : Array[0..MaxWnd - 1] Of TWnd;
  ZList    : Array[0..MaxWnd - 1] Of LongInt;
  ZCnt     : LongInt;
  Props    : Array[0..MaxProp - 1] Of TProp;
  WTimers  : Array[0..MaxTimer - 1] Of TTimerW;
  ActiveWin, FocusWin, CaptureWin : LongInt;
  WndSeq   : LongInt;
  DeskColor : LongInt;
  { saisie }
  KeyState : Array[0..255] Of Byte;
  KExt     : Boolean;
  LastClickT, LastClickW, LastClickX, LastClickY : LongInt;
  MouseBtn : LongInt;
  { deplacement d'une fenetre par sa barre de titre }
  DragWin, DragDX, DragDY : LongInt;
  PressWin, PressBtn : LongInt;
  AppCursorSet : Boolean;
  KeyLo, KeyHi : String[60];
  KillingApp : Boolean;

Procedure KPaint(W : LongInt); Forward;
Function KWndProc(W, Msg, WP, LP : LongInt) : LongInt; Forward;
Procedure KMouse(W, Msg, X, Y : LongInt); Forward;
Procedure KKey(W, Msg, VK, Ch : LongInt); Forward;
Procedure DeskDraw(R : TRect); Forward;
Procedure TaskbarChanged; Forward;
Procedure KActivated(W : LongInt); Forward;

Function HwndOf(W : LongInt) : LongInt;
Begin
  If W < 0 Then HwndOf := 0 Else HwndOf := HWndBase + W * 4;
End;

Function WndOf(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  WndOf := -1;
  If (H < HWndBase) Or (H >= HWndBase + MaxWnd * 4) Then Exit;
  I := (H - HWndBase) Div 4;
  If Wnds[I].Used Then WndOf := I;
End;

Function IsChildW(W : LongInt) : Boolean;
Begin
  IsChildW := (Wnds[W].Style And WS_CHILD) <> 0;
End;

{ Fenetre de premier niveau ancetre }
Function TopOf(W : LongInt) : LongInt;
Begin
  While (W >= 0) And IsChildW(W) And (Wnds[W].Parent >= 0) Do
    W := Wnds[W].Parent;
  TopOf := W;
End;

{ Metriques du cadre selon le style }
Procedure CalcNc(W : LongInt);
Var B, T : LongInt;
Begin
  B := 0;
  If (Wnds[W].Style And WS_THICKFRAME) <> 0 Then B := 4
  Else If ((Wnds[W].Style And WS_DLGFRAME) <> 0) Or
          ((Wnds[W].ExStyle And WS_EX_DLGMODALFRAME) <> 0) Then B := 3
  Else If (Wnds[W].Style And WS_BORDER) <> 0 Then B := 1;
  If (Wnds[W].ExStyle And WS_EX_CLIENTEDGE) <> 0 Then B := B + 2;
  T := B;
  If (Wnds[W].Style And WS_CAPTION) = WS_CAPTION Then T := T + 19;
  Wnds[W].CL := B; Wnds[W].CT := T;
  Wnds[W].CR := Max(B, Wnds[W].W - B);
  Wnds[W].CB := Max(T, Wnds[W].H - B);
End;

{ Position ecran du coin superieur gauche de la fenetre }
Procedure WndScreenPos(W : LongInt; Var X, Y : LongInt);
Var P : LongInt;
Begin
  X := Wnds[W].X; Y := Wnds[W].Y;
  If IsChildW(W) Then
  Begin
    P := Wnds[W].Parent;
    While P >= 0 Do
    Begin
      X := X + Wnds[P].X + Wnds[P].CL;
      Y := Y + Wnds[P].Y + Wnds[P].CT;
      If Not IsChildW(P) Then Break;
      P := Wnds[P].Parent;
    End;
  End;
End;

Procedure WndScreenRect(W : LongInt; Var R : TRect);
Var X, Y : LongInt;
Begin
  WndScreenPos(W, X, Y);
  SetR(R, X, Y, X + Wnds[W].W, Y + Wnds[W].H);
End;

Procedure ClientScreenOrg(W : LongInt; Var X, Y : LongInt);
Begin
  WndScreenPos(W, X, Y);
  X := X + Wnds[W].CL;
  Y := Y + Wnds[W].CT;
End;

Function WndVisible(W : LongInt) : Boolean;
Begin
  WndVisible := False;
  While W >= 0 Do
  Begin
    If Not Wnds[W].Visible Or Wnds[W].Min Then Exit;
    If Not IsChildW(W) Then Break;
    W := Wnds[W].Parent;
  End;
  WndVisible := W >= 0;
End;

{ Cible de dessin d'une fenetre : surface de l'ancetre, origine de la
  zone (client ou fenetre) dans cette surface et decoupage }
Function WndTarget(W : LongInt; Client : Boolean; Var S : TSurf;
                   Var OX, OY : LongInt; Var Clip : TRect) : Boolean;
Var T, X, Y, TX, TY, P, PX, PY : LongInt; R : TRect;
Begin
  WndTarget := False;
  If W < 0 Then Exit;
  T := TopOf(W);
  If (T < 0) Or (Wnds[T].Surf.Bits = 0) Then Exit;
  S := Wnds[T].Surf;
  WndScreenPos(W, X, Y);
  TX := Wnds[T].X; TY := Wnds[T].Y;
  If Client Then
  Begin
    OX := X - TX + Wnds[W].CL; OY := Y - TY + Wnds[W].CT;
    SetR(Clip, OX, OY, X - TX + Wnds[W].CR, Y - TY + Wnds[W].CB);
  End
  Else
  Begin
    OX := X - TX; OY := Y - TY;
    SetR(Clip, OX, OY, OX + Wnds[W].W, OY + Wnds[W].H);
  End;
  P := W;
  While IsChildW(P) And (Wnds[P].Parent >= 0) Do
  Begin
    P := Wnds[P].Parent;
    WndScreenPos(P, PX, PY);
    SetR(R, PX - TX + Wnds[P].CL, PY - TY + Wnds[P].CT,
         PX - TX + Wnds[P].CR, PY - TY + Wnds[P].CB);
    If Not RInter(Clip, Clip, R) Then SetR(Clip, 0, 0, 0, 0);
  End;
  SetR(R, 0, 0, S.W, S.H);
  If Not RInter(Clip, Clip, R) Then SetR(Clip, 0, 0, 0, 0);
  WndTarget := True;
End;

Procedure DirtyWnd(W : LongInt);
Var R : TRect;
Begin
  If W < 0 Then Exit;
  WndScreenRect(TopOf(W), R);
  MarkDirty(R.L, R.T, R.R, R.B);
End;

{ ------------------------------------------------------------------ }
{ Ordre Z des fenetres de premier niveau                             }
{ ------------------------------------------------------------------ }

Procedure ZRemove(W : LongInt);
Var I, J : LongInt;
Begin
  J := 0;
  For I := 0 To ZCnt - 1 Do
    If ZList[I] <> W Then
    Begin
      ZList[J] := ZList[I];
      Inc(J);
    End;
  ZCnt := J;
End;

{ Placer W au sommet (sous les fenetres toujours visibles) }
Procedure ZTop(W : LongInt);
Var I, P : LongInt;
Begin
  ZRemove(W);
  P := ZCnt;
  If (Wnds[W].ExStyle And WS_EX_TOPMOST) = 0 Then
    While (P > 0) And ((Wnds[ZList[P - 1]].ExStyle And WS_EX_TOPMOST) <> 0) Do
      Dec(P);
  For I := ZCnt DownTo P + 1 Do ZList[I] := ZList[I - 1];
  ZList[P] := W;
  Inc(ZCnt);
End;

Procedure ZBottom(W : LongInt);
Var I : LongInt;
Begin
  ZRemove(W);
  For I := ZCnt DownTo 1 Do ZList[I] := ZList[I - 1];
  ZList[0] := W;
  Inc(ZCnt);
End;

{ Composer une zone de l'ecran : bureau puis fenetres (ordre Z) }
Procedure ComposeRect(R : TRect);
Var I, W, Y, S, D, N, X0, Y0 : LongInt; WR, X : TRect;
Begin
  DeskDraw(R);
  For I := 0 To ZCnt - 1 Do
  Begin
    W := ZList[I];
    If Wnds[W].Used And Wnds[W].Visible And Not Wnds[W].Min And
       (Wnds[W].Surf.Bits <> 0) Then
    Begin
      SetR(WR, Wnds[W].X, Wnds[W].Y, Wnds[W].X + Wnds[W].W,
           Wnds[W].Y + Wnds[W].H);
      If RInter(X, R, WR) Then
      Begin
        N := X.R - X.L;
        X0 := X.L - Wnds[W].X; Y0 := X.T - Wnds[W].Y;
        S := Wnds[W].Surf.Bits + Y0 * Wnds[W].Surf.Pitch + X0;
        D := Back.Bits + X.T * Back.Pitch + X.L;
        For Y := X.T To X.B - 1 Do
        Begin
          MoveMem(S, D, N);
          S := S + Wnds[W].Surf.Pitch;
          D := D + Back.Pitch;
        End;
      End;
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Cadre des fenetres (zone non client), a la maniere de Windows 95   }
{ ------------------------------------------------------------------ }

Function CapButtonCount(W : LongInt) : LongInt;
Begin
  If (Wnds[W].Style And WS_SYSMENU) = 0 Then CapButtonCount := 0
  Else If (Wnds[W].Style And (WS_MINIMIZEBOX Or WS_MAXIMIZEBOX)) = 0 Then
    CapButtonCount := 1
  Else CapButtonCount := 3;
End;

{ Bouton B (0 fermer, 1 agrandir, 2 reduire), coord. dans la fenetre }
Procedure CapBtnRect(W, B : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Var Bd : LongInt;
Begin
  Bd := Wnds[W].CL;
  If (Wnds[W].ExStyle And WS_EX_CLIENTEDGE) <> 0 Then Bd := Bd - 2;
  X2 := Wnds[W].W - Bd - 3;
  Y1 := Bd + 2;
  Y2 := Y1 + 13;
  If B >= 1 Then X2 := X2 - 18;
  If B >= 2 Then X2 := X2 - 16;
  X1 := X2 - 15;
End;

Procedure NcPaint(W : LongInt);
Var Bd, X0, Y0, WW, HH, B, I, X1, Y1, X2, Y2, D : LongInt;
    Active : Boolean; Fg, C : LongInt; T : String;
Begin
  If Wnds[W].Surf.Bits = 0 Then Exit;
  Wnds[W].NeedNc := False;
  X0 := Wnds[W].X; Y0 := Wnds[W].Y; WW := Wnds[W].W; HH := Wnds[W].H;
  SetTarget(Wnds[W].Surf, X0, Y0);
  Bd := Wnds[W].CL;
  If (Wnds[W].ExStyle And WS_EX_CLIENTEDGE) <> 0 Then
  Begin
    Bd := Bd - 2;
    Edge(X0 + Bd, Y0 + Wnds[W].CT - 2, X0 + WW - Bd - 1, Y0 + HH - Bd - 1,
         cGray, cWhite);
    Edge(X0 + Bd + 1, Y0 + Wnds[W].CT - 1, X0 + WW - Bd - 2,
         Y0 + HH - Bd - 2, cBlack, cSilver);
  End;
  If Bd >= 2 Then
  Begin
    Edge(X0, Y0, X0 + WW - 1, Y0 + HH - 1, cSilver, cBlack);
    Edge(X0 + 1, Y0 + 1, X0 + WW - 2, Y0 + HH - 2, cWhite, cGray);
    For I := 2 To Bd - 1 Do
      Box(X0 + I, Y0 + I, X0 + WW - 1 - I, Y0 + HH - 1 - I, cSilver);
  End
  Else If Bd = 1 Then Box(X0, Y0, X0 + WW - 1, Y0 + HH - 1, cBlack);
  If (Wnds[W].Style And WS_CAPTION) = WS_CAPTION Then
  Begin
    Active := (W = ActiveWin);
    If Active Then C := cNavy Else C := cGray;
    If Active Then Fg := cWhite Else Fg := cSilver;
    FBar(X0 + Bd, Y0 + Bd, X0 + WW - Bd - 1, Y0 + Bd + 17, C);
    HLine(X0 + Bd, X0 + WW - Bd - 1, Y0 + Bd + 18, cSilver);
    B := CapButtonCount(W);
    I := 4;
    If (Wnds[W].Style And WS_SYSMENU) <> 0 Then
    Begin
      If Wnds[W].IKind <> ikNone Then
        PaintIcon(Wnds[W].K4, X0 + Bd + 2, Y0 + Bd + 1, 16)
      Else
        PaintIcon(icApp, X0 + Bd + 2, Y0 + Bd + 1, 16);
      I := 21;
    End;
    T := Fit(Wnds[W].Text, WW - Bd * 2 - I - 4 - 18 * B);
    OutBold(X0 + Bd + I, Y0 + Bd + 1, T, Fg);
    For I := 0 To B - 1 Do
    Begin
      CapBtnRect(W, I, X1, Y1, X2, Y2);
      X1 := X1 + X0; X2 := X2 + X0; Y1 := Y1 + Y0; Y2 := Y2 + Y0;
      Raised(X1, Y1, X2, Y2, (PressWin = W) And (PressBtn = -1 - I));
      If (PressWin = W) And (PressBtn = -1 - I) Then D := 1 Else D := 0;
      X1 := X1 + D; Y1 := Y1 + D;
      Case I Of
        0 :
          For D := 0 To 6 Do
          Begin
            Pix(X1 + 4 + D, Y1 + 3 + D, cBlack);
            Pix(X1 + 5 + D, Y1 + 3 + D, cBlack);
            Pix(X1 + 10 - D, Y1 + 3 + D, cBlack);
            Pix(X1 + 11 - D, Y1 + 3 + D, cBlack);
          End;
        1 :
        Begin
          If (Wnds[W].Style And WS_MAXIMIZEBOX) <> 0 Then C := cBlack
          Else C := cGray;
          If Wnds[W].Max Then
          Begin
            Box(X1 + 6, Y1 + 2, X1 + 11, Y1 + 6, C);
            HLine(X1 + 6, X1 + 11, Y1 + 3, C);
            FBar(X1 + 3, Y1 + 5, X1 + 8, Y1 + 10, cSilver);
            Box(X1 + 3, Y1 + 5, X1 + 8, Y1 + 10, C);
            HLine(X1 + 3, X1 + 8, Y1 + 6, C);
          End
          Else
          Begin
            Box(X1 + 3, Y1 + 2, X1 + 11, Y1 + 10, C);
            HLine(X1 + 3, X1 + 11, Y1 + 3, C);
          End;
        End;
      Else
        If (Wnds[W].Style And WS_MINIMIZEBOX) <> 0 Then C := cBlack
        Else C := cGray;
        FBar(X1 + 4, Y1 + 9, X1 + 9, Y1 + 10, C);
      End;
    End;
  End;
  DirtyWnd(W);
End;

{ ------------------------------------------------------------------ }
{ Invalidation et peinture                                           }
{ ------------------------------------------------------------------ }

Procedure InvalW(W : LongInt; R : TRect; Erase : Boolean);
Var C : TRect;
Begin
  If W < 0 Then Exit;
  SetR(C, 0, 0, Wnds[W].CR - Wnds[W].CL, Wnds[W].CB - Wnds[W].CT);
  If Not RInter(R, R, C) Then Exit;
  RUnion(Wnds[W].Upd, R);
  If Erase Then Wnds[W].UpdErase := True;
  If Wnds[W].IKind <> ikNone Then Wnds[TopOf(W)].KNeedPaint := True
  Else If (Wnds[W].Thread >= 0) And (Wnds[W].Thread < MaxThread) Then
    Threads[Wnds[W].Thread].PaintReq := True;
End;

Procedure InvalAll(W : LongInt; Erase : Boolean);
Var R : TRect; I : LongInt;
Begin
  SetR(R, 0, 0, 30000, 30000);
  InvalW(W, R, Erase);
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And IsChildW(I) And (Wnds[I].Parent = W) Then
      InvalAll(I, Erase);
End;

Function HasUpdate(W : LongInt) : Boolean;
Begin
  HasUpdate := (Wnds[W].Upd.L < Wnds[W].Upd.R) And
               (Wnds[W].Upd.T < Wnds[W].Upd.B);
End;

{ ------------------------------------------------------------------ }
{ Messages                                                           }
{ ------------------------------------------------------------------ }

Function CallProc(P, H, M, WP, LP : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := 0;
  asm
    mov eax,LP
    push eax
    mov eax,WP
    push eax
    mov eax,M
    push eax
    mov eax,H
    push eax
    mov eax,P
    call eax
    mov R,eax
  end;
  CallProc := R;
End;

Function SendMsgW(W, Msg, WP, LP : LongInt) : LongInt;
Begin
  SendMsgW := 0;
  If (W < 0) Or Not Wnds[W].Used Then Exit;
  If Wnds[W].Proc <> 0 Then
  Begin
    If Not KillingApp Then
      SendMsgW := CallProc(Wnds[W].Proc, HwndOf(W), Msg, WP, LP);
  End
  Else
    SendMsgW := KWndProc(W, Msg, WP, LP);
End;

Function PostMsgW(W, Msg, WP, LP : LongInt) : Boolean;
Begin
  PostMsgW := False;
  If (W < 0) Or Not Wnds[W].Used Then Exit;
  If (Wnds[W].IKind <> ikNone) And (Wnds[W].IKind <> ikDialog) Then
  Begin
    KWndProc(W, Msg, WP, LP);
    PostMsgW := True;
  End
  Else
    PostMsgW := QPost(Wnds[W].Thread, HwndOf(W), Msg, WP, LP);
End;

{ Message en attente pour la tache T (y compris WM_PAINT et WM_TIMER) }
Function MsgPending(T : LongInt) : Boolean;
Var I : LongInt;
Begin
  MsgPending := True;
  If Threads[T].QHead <> Threads[T].QTail Then Exit;
  If Threads[T].QuitFlag Then Exit;
  If Threads[T].PaintReq Then Exit;
  For I := 0 To MaxTimer - 1 Do
    If WTimers[I].Used And (WTimers[I].Thread = T) And
       (Ticks >= WTimers[I].Next) Then Exit;
  MsgPending := False;
End;

{ ------------------------------------------------------------------ }
{ Creation, destruction, activation                                  }
{ ------------------------------------------------------------------ }

Function ClassFind(Name : String) : LongInt;
Var I : LongInt;
Begin
  ClassFind := -1;
  Name := UpStr(Name);
  For I := 0 To MaxClass - 1 Do
    If Classes[I].Used And (Classes[I].Name = Name) Then
    Begin
      ClassFind := I;
      Exit;
    End;
End;

Function ClassAdd(Name : String; Proc, IKind, Style : LongInt) : LongInt;
Var I : LongInt;
Begin
  ClassAdd := -1;
  For I := 0 To MaxClass - 1 Do
    If Not Classes[I].Used Then
    Begin
      FillMem(LongInt(@Classes[I]), SizeOf(TClass), 0);
      Classes[I].Used := True;
      Classes[I].Name := UpStr(Name);
      Classes[I].Atom := $C000 + I;
      Classes[I].Proc := Proc;
      Classes[I].IKind := IKind;
      Classes[I].Style := Style;
      Classes[I].Brush := 6;      { COLOR_WINDOW + 1 }
      ClassAdd := I;
      Exit;
    End;
End;

Function WndAlloc : LongInt;
Var I : LongInt;
Begin
  WndAlloc := -1;
  For I := 0 To MaxWnd - 1 Do
    If Not Wnds[I].Used Then
    Begin
      FillMem(LongInt(@Wnds[I]), SizeOf(TWnd), 0);
      Wnds[I].Used := True;
      Wnds[I].Parent := -1;
      Wnds[I].Owner := -1;
      Wnds[I].Enabled := True;
      Inc(WndSeq);
      Wnds[I].Seq := WndSeq;
      WndAlloc := I;
      Exit;
    End;
End;

{ (Re)allouer la surface d'une fenetre de premier niveau }
Procedure WndSurf(W : LongInt);
Var WW, HH : LongInt;
Begin
  If IsChildW(W) Then Exit;
  WW := Max(1, Wnds[W].W); HH := Max(1, Wnds[W].H);
  If (Wnds[W].Surf.Bits <> 0) And (Wnds[W].Surf.W = WW) And
     (Wnds[W].Surf.H = HH) Then Exit;
  SurfFree(Wnds[W].Surf);
  If SurfNew(Wnds[W].Surf, WW, HH) Then
    FillMem(Wnds[W].Surf.Bits, Wnds[W].Surf.Pitch * HH, cSilver);
  Wnds[W].NeedNc := True;
End;

Function IsTaskWin(W : LongInt) : Boolean;
Begin
  IsTaskWin := Wnds[W].Used And Wnds[W].Visible And Not IsChildW(W) And
    (Wnds[W].Owner < 0) And ((Wnds[W].ExStyle And WS_EX_TOOLWINDOW) = 0)
    And (Wnds[W].IKind <> ikTaskbar) And (Wnds[W].IKind <> ikMenu) And
    ((Wnds[W].Text <> '') Or ((Wnds[W].Style And WS_CAPTION) <> 0));
End;

Procedure SetFocusW(W : LongInt);
Var Old : LongInt;
Begin
  If W = FocusWin Then Exit;
  Old := FocusWin;
  FocusWin := W;
  If (Old >= 0) And Wnds[Old].Used Then
    PostMsgW(Old, WM_KILLFOCUS, HwndOf(W), 0);
  If W >= 0 Then PostMsgW(W, WM_SETFOCUS, HwndOf(Old), 0);
End;

Procedure ActivateW(W : LongInt);
Var Old : LongInt;
Begin
  If W >= 0 Then W := TopOf(W);
  If (W >= 0) And ((Wnds[W].IKind = ikTaskbar) Or
     (Wnds[W].IKind = ikMenu)) Then Exit;
  Old := ActiveWin;
  If (W >= 0) And Wnds[W].Visible Then ZTop(W);
  If W = Old Then
  Begin
    If W >= 0 Then DirtyWnd(W);
    Exit;
  End;
  ActiveWin := W;
  If (Old >= 0) And Wnds[Old].Used Then
  Begin
    NcPaint(Old);
    If Wnds[Old].IKind = ikNone Then
    Begin
      PostMsgW(Old, WM_ACTIVATE, 0, HwndOf(W));
      If (W < 0) Or (Wnds[W].Thread <> Wnds[Old].Thread) Then
        PostMsgW(Old, WM_ACTIVATEAPP, 0, 0);
    End
    Else
      Wnds[Old].KNeedPaint := True;
  End;
  If W >= 0 Then
  Begin
    NcPaint(W);
    If Wnds[W].IKind = ikNone Then
    Begin
      If (Old < 0) Or (Wnds[Old].Thread <> Wnds[W].Thread) Then
        PostMsgW(W, WM_ACTIVATEAPP, 1, 0);
      PostMsgW(W, WM_ACTIVATE, 1, HwndOf(Old));
      PostMsgW(W, WM_QUERYNEWPALETTE, 0, 0);
    End
    Else
      Wnds[W].KNeedPaint := True;
    SetFocusW(W);
    KActivated(W);
  End;
  TaskbarChanged;
End;

{ Fenetre suivante a activer apres fermeture ou reduction }
Procedure ActivateNext;
Var I, W : LongInt;
Begin
  For I := ZCnt - 1 DownTo 0 Do
  Begin
    W := ZList[I];
    If Wnds[W].Used And Wnds[W].Visible And Not Wnds[W].Min And
       (Wnds[W].IKind <> ikTaskbar) And (Wnds[W].IKind <> ikMenu) Then
    Begin
      ActivateW(W);
      Exit;
    End;
  End;
  ActivateW(-1);
End;

Procedure ShowW(W : LongInt; Show, Activate : Boolean);
Begin
  If Wnds[W].Visible = Show Then
  Begin
    If Show And Activate And Not IsChildW(W) Then ActivateW(W);
    Exit;
  End;
  Wnds[W].Visible := Show;
  If Show Then
  Begin
    InvalAll(W, True);
    If Not IsChildW(W) Then
    Begin
      Wnds[W].NeedNc := True;
      If Activate Then ActivateW(W) Else ZTop(W);
    End;
  End
  Else If (W = ActiveWin) Then ActivateNext;
  DirtyWnd(W);
  If Not IsChildW(W) Then TaskbarChanged;
End;

{ Changer la position et la taille (coordonnees relatives au parent) }
Procedure MoveW(W, X, Y, WW, HH : LongInt; Repaint : Boolean);
Var Sized, Moved : Boolean; R : TRect;
Begin
  If WW < 0 Then WW := 0;
  If HH < 0 Then HH := 0;
  Sized := (WW <> Wnds[W].W) Or (HH <> Wnds[W].H);
  Moved := (X <> Wnds[W].X) Or (Y <> Wnds[W].Y);
  If Not Sized And Not Moved Then Exit;
  DirtyWnd(W);
  WndScreenRect(W, R);
  Wnds[W].X := X; Wnds[W].Y := Y; Wnds[W].W := WW; Wnds[W].H := HH;
  CalcNc(W);
  If Sized Then
  Begin
    WndSurf(W);
    If Not IsChildW(W) Then NcPaint(W);
    InvalAll(W, True);
    SendMsgW(W, WM_SIZE, 0, ((Wnds[W].CB - Wnds[W].CT) Shl 16) Or
             ((Wnds[W].CR - Wnds[W].CL) And $FFFF));
  End;
  If Moved Then
    SendMsgW(W, WM_MOVE, 0, (Wnds[W].Y Shl 16) Or (Wnds[W].X And $FFFF));
  If IsChildW(W) Then
  Begin
    { l'ancienne zone de la fille doit etre repeinte par le parent }
    If Wnds[W].Parent >= 0 Then InvalAll(Wnds[W].Parent, True);
  End;
  DirtyWnd(W);
End;

Procedure DestroyW(W : LongInt);
Var I, T : LongInt;
Begin
  If (W < 0) Or Not Wnds[W].Used Or Wnds[W].Destroying Then Exit;
  Wnds[W].Destroying := True;
  If Wnds[W].Visible And Not IsChildW(W) Then DirtyWnd(W);
  SendMsgW(W, WM_DESTROY, 0, 0);
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And ((Wnds[I].Parent = W) Or (Wnds[I].Owner = W)) And
       (I <> W) Then DestroyW(I);
  SendMsgW(W, WM_NCDESTROY, 0, 0);
  For I := 0 To MaxTimer - 1 Do
    If WTimers[I].Used And (WTimers[I].Wnd = W) Then
      WTimers[I].Used := False;
  For I := 0 To MaxProp - 1 Do
    If Props[I].Used And (Props[I].Wnd = W) Then Props[I].Used := False;
  If IsChildW(W) And (Wnds[W].Parent >= 0) Then
    InvalAll(Wnds[W].Parent, True);
  If Not IsChildW(W) Then
  Begin
    DirtyWnd(W);
    ZRemove(W);
    SurfFree(Wnds[W].Surf);
  End;
  If Wnds[W].Extra <> 0 Then KFree(Wnds[W].Extra);
  T := Wnds[W].Thread;
  Wnds[W].Used := False;
  If CaptureWin = W Then CaptureWin := -1;
  If DragWin = W Then DragWin := -1;
  If PressWin = W Then PressWin := -1;
  If FocusWin = W Then FocusWin := -1;
  If ActiveWin = W Then
  Begin
    ActiveWin := -1;
    ActivateNext;
  End;
  TaskbarChanged;
End;

{ Creer une fenetre ; indice ou -1. Param : CREATESTRUCT.lpCreateParams }
Function CreateW(ExStyle, Cls : LongInt; Name : String; Style, X, Y, WW,
                 HH, Parent, Menu, Inst, Param : LongInt) : LongInt;
Var W, CS, R : LongInt;
Begin
  CreateW := -1;
  W := WndAlloc;
  If W < 0 Then Exit;
  Wnds[W].Cls := Cls;
  Wnds[W].Style := Style And Not WS_VISIBLE;
  Wnds[W].ExStyle := ExStyle;
  Wnds[W].Text := Name;
  Wnds[W].Proc := Classes[Cls].Proc;
  Wnds[W].IKind := Classes[Cls].IKind;
  Wnds[W].Thread := CurT;
  Wnds[W].Inst := Inst;
  Wnds[W].Cursor := Classes[Cls].Cursor;
  If (Style And WS_CHILD) <> 0 Then
  Begin
    Wnds[W].Parent := Parent;
    Wnds[W].Id := Menu;
  End
  Else
  Begin
    Wnds[W].Owner := Parent;
    Wnds[W].Menu := Menu;
  End;
  If Classes[Cls].WndExtra > 0 Then
  Begin
    Wnds[W].ExtraSz := Classes[Cls].WndExtra;
    Wnds[W].Extra := KAlloc(Classes[Cls].WndExtra);
  End;
  { CW_USEDEFAULT }
  If X = LongInt($80000000) Then
  Begin
    X := 40 + (W Mod 8) * 24; Y := 30 + (W Mod 8) * 20;
  End;
  If WW = LongInt($80000000) Then
  Begin
    WW := 480; HH := 340;
  End;
  Wnds[W].X := X; Wnds[W].Y := Y; Wnds[W].W := Max(0, WW);
  Wnds[W].H := Max(0, HH);
  CalcNc(W);
  WndSurf(W);
  If Not IsChildW(W) Then ZTop(W);
  { CREATESTRUCT dans un bloc du tas }
  CS := KAlloc(64 + 256);
  MemL[0:CS] := Param; MemL[0:CS + 4] := Inst; MemL[0:CS + 8] := Menu;
  MemL[0:CS + 12] := HwndOf(Parent); MemL[0:CS + 16] := HH;
  MemL[0:CS + 20] := WW; MemL[0:CS + 24] := Y; MemL[0:CS + 28] := X;
  MemL[0:CS + 32] := Style;
  PutPStr(CS + 64, Name, 128);
  MemL[0:CS + 36] := CS + 64;
  PutPStr(CS + 192, Classes[Cls].Name, 64);
  MemL[0:CS + 40] := CS + 192;
  MemL[0:CS + 44] := ExStyle;
  CreateW := W;
  If SendMsgW(W, WM_NCCREATE, 0, CS) = 0 Then
    If Wnds[W].Proc <> 0 Then
    Begin
      KFree(CS);
      DestroyW(W);
      CreateW := -1;
      Exit;
    End;
  R := SendMsgW(W, WM_CREATE, 0, CS);
  KFree(CS);
  If R = -1 Then
  Begin
    DestroyW(W);
    CreateW := -1;
    Exit;
  End;
  If Not Wnds[W].Used Then
  Begin
    CreateW := -1;
    Exit;
  End;
  SendMsgW(W, WM_SIZE, 0, ((Wnds[W].CB - Wnds[W].CT) Shl 16) Or
           ((Wnds[W].CR - Wnds[W].CL) And $FFFF));
  SendMsgW(W, WM_MOVE, 0, (Wnds[W].Y Shl 16) Or (Wnds[W].X And $FFFF));
  If (Style And WS_MAXIMIZE) <> 0 Then
  Begin
    Wnds[W].Max := True;
    Wnds[W].NX := Wnds[W].X; Wnds[W].NY := Wnds[W].Y;
    Wnds[W].NW := Wnds[W].W; Wnds[W].NH := Wnds[W].H;
  End;
  If (Style And WS_VISIBLE) <> 0 Then
    ShowW(W, True, Not IsChildW(W));
End;

{ ------------------------------------------------------------------ }
{ Recherche de la fenetre sous un point de l'ecran                   }
{ ------------------------------------------------------------------ }

Function ChildAt(W, X, Y : LongInt) : LongInt;
Var I, Best, BestSeq, CX, CY : LongInt; R : TRect;
Begin
  Best := -1; BestSeq := -1;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And Wnds[I].Visible And IsChildW(I) And
       (Wnds[I].Parent = W) Then
    Begin
      WndScreenRect(I, R);
      If InRect(X, Y, R.L, R.T, R.R - 1, R.B - 1) Then
        If Wnds[I].Seq > BestSeq Then
        Begin
          Best := I; BestSeq := Wnds[I].Seq;
        End;
    End;
  If Best >= 0 Then ChildAt := ChildAt(Best, X, Y) Else ChildAt := W;
  CX := 0; CY := CX;
End;

Function TopAt(X, Y : LongInt) : LongInt;
Var I, W : LongInt;
Begin
  TopAt := -1;
  For I := ZCnt - 1 DownTo 0 Do
  Begin
    W := ZList[I];
    If Wnds[W].Used And Wnds[W].Visible And Not Wnds[W].Min Then
      If InRect(X, Y, Wnds[W].X, Wnds[W].Y, Wnds[W].X + Wnds[W].W - 1,
                Wnds[W].Y + Wnds[W].H - 1) Then
      Begin
        TopAt := W;
        Exit;
      End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Clavier : codes de balayage -> touches virtuelles                  }
{ ------------------------------------------------------------------ }

Procedure InitKeyTables;
Begin
  KeyLo := #0#27'1234567890-='#8#9'qwertyuiop[]'#13#0 +
           'asdfghjkl;''`'#0'\zxcvbnm,./'#0'*'#0' ';
  KeyHi := #0#27'!@#$%^&*()_+'#8#9'QWERTYUIOP{}'#13#0 +
           'ASDFGHJKL:"~'#0'|ZXCVBNM<>?'#0'*'#0' ';
End;

Function ScanToVk(Sc : LongInt; Ext : Boolean) : LongInt;
Var C : Char;
Begin
  ScanToVk := 0;
  Case Sc Of
    $01 : ScanToVk := $1B;   $0E : ScanToVk := 8;   $0F : ScanToVk := 9;
    $1C : ScanToVk := $0D;   $1D : ScanToVk := $11; $2A, $36 : ScanToVk := $10;
    $38 : ScanToVk := $12;   $39 : ScanToVk := $20; $3A : ScanToVk := $14;
    $3B..$44 : ScanToVk := $70 + Sc - $3B;
    $57 : ScanToVk := $7A;   $58 : ScanToVk := $7B;
    $47 : ScanToVk := $24;   $48 : ScanToVk := $26; $49 : ScanToVk := $21;
    $4B : ScanToVk := $25;   $4D : ScanToVk := $27; $4F : ScanToVk := $23;
    $50 : ScanToVk := $28;   $51 : ScanToVk := $22; $52 : ScanToVk := $2D;
    $53 : ScanToVk := $2E;   $4A : ScanToVk := $6D; $4E : ScanToVk := $6B;
    $37 : ScanToVk := $6A;   $5B : ScanToVk := $5B; $5C : ScanToVk := $5C;
    $5D : ScanToVk := $5D;
  Else
    If Sc <= $39 Then
    Begin
      C := UpCase(KeyLo[Sc + 1]);
      Case C Of
        'A'..'Z', '0'..'9' : ScanToVk := Ord(C);
        ';' : ScanToVk := $BA; '=' : ScanToVk := $BB; ',' : ScanToVk := $BC;
        '-' : ScanToVk := $BD; '.' : ScanToVk := $BE; '/' : ScanToVk := $BF;
        '`' : ScanToVk := $C0; '[' : ScanToVk := $DB; '\' : ScanToVk := $DC;
        ']' : ScanToVk := $DD; '''' : ScanToVk := $DE;
      End;
    End;
  End;
End;

{ Caractere d'une touche (selon Majuscules et Verr. maj.) ; 0 si aucun }
Function ScanToChar(Sc : LongInt) : LongInt;
Var C : Char; Sh : Boolean;
Begin
  ScanToChar := 0;
  If (Sc > $39) Or (Sc = 0) Then Exit;
  Sh := (KeyState[$10] And $80) <> 0;
  If Sh Then C := KeyHi[Sc + 1] Else C := KeyLo[Sc + 1];
  If ((KeyState[$14] And 1) <> 0) And (UpCase(C) >= 'A') And
     (UpCase(C) <= 'Z') Then
  Begin
    If Sh Then C := KeyLo[Sc + 1] Else C := KeyHi[Sc + 1];
  End;
  ScanToChar := Ord(C);
End;

{ ------------------------------------------------------------------ }
{ Reduire, agrandir, restaurer                                       }
{ ------------------------------------------------------------------ }

Procedure MinimizeW(W : LongInt);
Begin
  If Wnds[W].Min Then Exit;
  DirtyWnd(W);
  Wnds[W].Min := True;
  If W = ActiveWin Then ActivateNext;
  PostMsgW(W, WM_SIZE, 1, 0);
  TaskbarChanged;
End;

Procedure RestoreW(W : LongInt);
Begin
  If Wnds[W].Min Then
  Begin
    Wnds[W].Min := False;
    DirtyWnd(W);
    ActivateW(W);
    PostMsgW(W, WM_SIZE, 0, ((Wnds[W].CB - Wnds[W].CT) Shl 16) Or
             ((Wnds[W].CR - Wnds[W].CL) And $FFFF));
    InvalAll(W, True);
    Exit;
  End;
  If Wnds[W].Max Then
  Begin
    Wnds[W].Max := False;
    MoveW(W, Wnds[W].NX, Wnds[W].NY, Wnds[W].NW, Wnds[W].NH, True);
    NcPaint(W);
  End;
End;

Procedure MaximizeW(W : LongInt);
Begin
  If Wnds[W].Max Or ((Wnds[W].Style And WS_THICKFRAME) = 0) Then Exit;
  Wnds[W].NX := Wnds[W].X; Wnds[W].NY := Wnds[W].Y;
  Wnds[W].NW := Wnds[W].W; Wnds[W].NH := Wnds[W].H;
  Wnds[W].Max := True;
  MoveW(W, -Wnds[W].CL, -Wnds[W].CL, ScrW + 2 * Wnds[W].CL,
        TaskY + 2 * Wnds[W].CL, True);
  NcPaint(W);
End;

{ Commande systeme (bouton ou menu systeme) }
Procedure SysCommand(W, Cmd : LongInt);
Begin
  Case Cmd And $FFF0 Of
    SC_CLOSE : PostMsgW(W, WM_CLOSE, 0, 0);
    SC_MINIMIZE : MinimizeW(W);
    SC_MAXIMIZE : MaximizeW(W);
    SC_RESTORE : RestoreW(W);
  End;
End;

{ ------------------------------------------------------------------ }
{ Souris (tache 0)                                                   }
{ ------------------------------------------------------------------ }

Function MouseKeys : LongInt;
Var K : LongInt;
Begin
  K := 0;
  If (MouseBtn And 1) <> 0 Then K := K Or 1;
  If (MouseBtn And 2) <> 0 Then K := K Or 2;
  If (KeyState[$10] And $80) <> 0 Then K := K Or 4;
  If (KeyState[$11] And $80) <> 0 Then K := K Or 8;
  MouseKeys := K;
End;

{ Message souris vers la fenetre W (coordonnees client) }
Procedure MouseTo(W, Msg : LongInt);
Var X, Y : LongInt;
Begin
  ClientScreenOrg(W, X, Y);
  X := CurX - X; Y := CurY - Y;
  If Wnds[W].IKind >= ikButton Then
  Begin
    If Wnds[W].IKind <> ikDialog Then
      KWndProc(W, Msg, MouseKeys, ((Y And $FFFF) Shl 16) Or (X And $FFFF));
  End
  Else If Wnds[W].IKind <> ikNone Then KMouse(W, Msg, X, Y)
  Else
    PostMsgW(W, Msg, MouseKeys, ((Y And $FFFF) Shl 16) Or (X And $FFFF));
End;

Function ModalBlocked(T : LongInt) : Boolean; Forward;

Procedure MouseButton(Down : Boolean; Btn : LongInt);
Var T, W, B, X1, Y1, X2, Y2, Msg, OX, OY : LongInt; Dbl : Boolean;
Begin
  If Btn = 1 Then KeyState[1] := Ord(Down) * $80
  Else KeyState[2] := Ord(Down) * $80;
  { capture de la souris }
  If (CaptureWin >= 0) And Wnds[CaptureWin].Used Then
  Begin
    If Btn = 1 Then
      If Down Then Msg := WM_LBUTTONDOWN Else Msg := WM_LBUTTONUP
    Else If Down Then Msg := WM_RBUTTONDOWN Else Msg := WM_RBUTTONUP;
    MouseTo(CaptureWin, Msg);
    Exit;
  End;
  { fin d'un deplacement ou d'un bouton de titre }
  If Not Down And (Btn = 1) Then
  Begin
    If DragWin >= 0 Then
    Begin
      DragWin := -1;
      Exit;
    End;
    If PressWin >= 0 Then
    Begin
      W := PressWin; B := -1 - PressBtn;
      PressWin := -1;
      NcPaint(W);
      CapBtnRect(W, B, X1, Y1, X2, Y2);
      If InRect(CurX - Wnds[W].X, CurY - Wnds[W].Y, X1, Y1, X2, Y2) Then
        Case B Of
          0 : SysCommand(W, SC_CLOSE);
          1 : If Wnds[W].Max Then SysCommand(W, SC_RESTORE)
              Else SysCommand(W, SC_MAXIMIZE);
          2 : SysCommand(W, SC_MINIMIZE);
        End;
      Exit;
    End;
  End;
  T := TopAt(CurX, CurY);
  If T < 0 Then
  Begin
    If Down Then KMouse(-1, WM_LBUTTONDOWN + 3 * (Btn - 1), CurX, CurY)
    Else KMouse(-1, WM_LBUTTONUP + 3 * (Btn - 1), CurX, CurY);
    Exit;
  End;
  If Down And ModalBlocked(T) Then
  Begin
    KBeep;
    Exit;
  End;
  If Down And (T <> ActiveWin) Then ActivateW(T);
  OX := CurX - Wnds[T].X; OY := CurY - Wnds[T].Y;
  { zone non client : barre de titre et boutons }
  If Down And (Btn = 1) And
     Not InRect(OX, OY, Wnds[T].CL, Wnds[T].CT, Wnds[T].CR - 1,
                Wnds[T].CB - 1) Then
  Begin
    For B := 0 To CapButtonCount(T) - 1 Do
    Begin
      CapBtnRect(T, B, X1, Y1, X2, Y2);
      If InRect(OX, OY, X1, Y1, X2, Y2) Then
      Begin
        PressWin := T; PressBtn := -1 - B;
        NcPaint(T);
        Exit;
      End;
    End;
    If ((Wnds[T].Style And WS_CAPTION) = WS_CAPTION) And
       (OY < Wnds[T].CL + 19) Then
    Begin
      Dbl := (LastClickW = -2 - T) And (Ticks - LastClickT < 700);
      LastClickW := -2 - T; LastClickT := Ticks;
      If Dbl And ((Wnds[T].Style And WS_MAXIMIZEBOX) <> 0) Then
      Begin
        If Wnds[T].Max Then RestoreW(T) Else MaximizeW(T);
        Exit;
      End;
      If Not Wnds[T].Max Then
      Begin
        DragWin := T; DragDX := OX; DragDY := OY;
      End;
    End;
    If Wnds[T].IKind <> ikNone Then KMouse(T, WM_LBUTTONDOWN, OX, OY);
    Exit;
  End;
  If (Not Down) And (Btn = 1) And (Wnds[T].IKind <> ikNone) And
     Not InRect(OX, OY, Wnds[T].CL, Wnds[T].CT, Wnds[T].CR - 1,
                Wnds[T].CB - 1) Then Exit;
  { zone client : fenetre fille la plus profonde }
  W := ChildAt(T, CurX, CurY);
  If Not Wnds[W].Enabled Then Exit;
  If Btn = 1 Then
  Begin
    If Down Then
    Begin
      Dbl := (LastClickW = W) And (Ticks - LastClickT < 700) And
             (Abs(CurX - LastClickX) < 4) And (Abs(CurY - LastClickY) < 4);
      LastClickW := W; LastClickT := Ticks;
      LastClickX := CurX; LastClickY := CurY;
      If Dbl And (((Classes[Wnds[W].Cls].Style And CS_DBLCLKS) <> 0) Or
         (Wnds[W].IKind <> ikNone)) Then
      Begin
        Msg := WM_LBUTTONDBLCLK;
        LastClickW := -1;
      End
      Else Msg := WM_LBUTTONDOWN;
      If (W <> FocusWin) And IsChildW(W) And (Wnds[W].Proc = 0) Then
        SetFocusW(W);
    End
    Else Msg := WM_LBUTTONUP;
  End
  Else If Down Then Msg := WM_RBUTTONDOWN Else Msg := WM_RBUTTONUP;
  MouseTo(W, Msg);
End;

Procedure MouseMoved;
Var T, W, NX, NY : LongInt;
Begin
  If DragWin >= 0 Then
  Begin
    NX := CurX - DragDX; NY := CurY - DragDY;
    If NY < 0 Then NY := 0;
    If NY > TaskY - 20 Then NY := TaskY - 20;
    MoveW(DragWin, NX, NY, Wnds[DragWin].W, Wnds[DragWin].H, False);
    Exit;
  End;
  If PressWin >= 0 Then Exit;
  If (CaptureWin >= 0) And Wnds[CaptureWin].Used Then
  Begin
    MouseTo(CaptureWin, WM_MOUSEMOVE);
    Exit;
  End;
  T := TopAt(CurX, CurY);
  If T < 0 Then
  Begin
    KMouse(-1, WM_MOUSEMOVE, CurX, CurY);
    If CurKind <> 0 Then CursorSetShape(0);
    Exit;
  End;
  W := ChildAt(T, CurX, CurY);
  If Wnds[W].IKind <> ikNone Then
  Begin
    If CurKind <> 0 Then CursorSetShape(0);
    MouseTo(W, WM_MOUSEMOVE);
  End
  Else
  Begin
    If InRect(CurX - Wnds[T].X, CurY - Wnds[T].Y, Wnds[T].CL, Wnds[T].CT,
              Wnds[T].CR - 1, Wnds[T].CB - 1) Then
      MouseTo(W, WM_MOUSEMOVE)
    Else If CurKind = 2 Then CursorSetShape(0);
  End;
End;

{ ------------------------------------------------------------------ }
{ Clavier (tache 0)                                                  }
{ ------------------------------------------------------------------ }

Procedure KeyEvent(Sc : LongInt; Up, Ext : Boolean);
Var Vk, Lp, Msg, W, Ch : LongInt; Alt : Boolean;
Begin
  Vk := ScanToVk(Sc, Ext);
  If Vk = 0 Then Exit;
  If Up Then KeyState[Vk] := KeyState[Vk] And $7F
  Else
  Begin
    If (KeyState[Vk] And $80) = 0 Then KeyState[Vk] := KeyState[Vk] Xor 1;
    KeyState[Vk] := KeyState[Vk] Or $80;
  End;
  Alt := (KeyState[$12] And $80) <> 0;
  Lp := 1 Or (Sc Shl 16);
  If Ext Then Lp := Lp Or $01000000;
  If Alt Then Lp := Lp Or $20000000;
  If Up Then Lp := Lp Or LongInt($C0000000);
  Ch := 0;
  If Not Up Then Ch := ScanToChar(Sc);
  { raccourcis du systeme }
  If Not Up Then
  Begin
    KKey(-1, WM_KEYDOWN, Vk, Ch);
    If Vk = 0 Then Exit;
  End;
  W := FocusWin;
  If (W < 0) Or Not Wnds[W].Used Then W := ActiveWin;
  If W < 0 Then
  Begin
    If Not Up Then KKey(-2, WM_KEYDOWN, Vk, Ch);
    Exit;
  End;
  If Wnds[W].IKind <> ikNone Then
  Begin
    If Up Then KKey(W, WM_KEYUP, Vk, Ch) Else KKey(W, WM_KEYDOWN, Vk, Ch);
    Exit;
  End;
  If Alt Or (Vk = $12) Or (Vk = $79) Then
    If Up Then Msg := WM_SYSKEYUP Else Msg := WM_SYSKEYDOWN
  Else If Up Then Msg := WM_KEYUP Else Msg := WM_KEYDOWN;
  PostMsgW(W, Msg, Vk, Lp);
End;

{ Traiter les evenements materiels en attente }
Procedure ProcessInput;
Var B, Dx, Dy, Bt, NX, NY : LongInt; Moved : Boolean;
Begin
  While KbHead <> KbTail Do
  Begin
    B := KbQ[KbHead];
    KbHead := (KbHead + 1) And 255;
    If B = $E0 Then KExt := True
    Else
    Begin
      KeyEvent(B And $7F, (B And $80) <> 0, KExt);
      KExt := False;
    End;
  End;
  Moved := False;
  NX := CurX; NY := CurY;
  While MouHead <> MouTail Do
  Begin
    Dx := MouQDx[MouHead]; Dy := MouQDy[MouHead]; Bt := MouQBtn[MouHead];
    MouHead := (MouHead + 1) And 255;
    NX := NX + Dx; NY := NY + Dy;
    If NX < 0 Then NX := 0;
    If NY < 0 Then NY := 0;
    If NX > ScrW - 1 Then NX := ScrW - 1;
    If NY > ScrH - 1 Then NY := ScrH - 1;
    If (NX <> CurX) Or (NY <> CurY) Then
    Begin
      CursorMoveTo(NX, NY);
      Moved := True;
    End;
    If (Bt And 1) <> (MouseBtn And 1) Then
    Begin
      If Moved Then MouseMoved;
      Moved := False;
      MouseBtn := (MouseBtn And Not 1) Or (Bt And 1);
      MouseButton((Bt And 1) <> 0, 1);
    End;
    If (Bt And 2) <> (MouseBtn And 2) Then
    Begin
      MouseBtn := (MouseBtn And Not 2) Or (Bt And 2);
      MouseButton((Bt And 2) <> 0, 2);
    End;
  End;
  If Moved Then MouseMoved;
End;

{ ------------------------------------------------------------------ }
{ Lecture des messages d'une tache (GetMessage / PeekMessage)        }
{ ------------------------------------------------------------------ }

Function MsgMatch(Var M : TMsgRec; Hwnd, MinM, MaxM : LongInt) : Boolean;
Begin
  MsgMatch := ((Hwnd = 0) Or (M.Hwnd = Hwnd)) And
    (((MinM = 0) And (MaxM = 0)) Or ((M.Msg >= MinM) And (M.Msg <= MaxM)));
End;

{ Message suivant pour la tache T ; False si aucun. Remove : retirer }
Function KPeekMsg(T : LongInt; Var M : TMsgRec; Hwnd, MinM, MaxM : LongInt;
                  Remove : Boolean) : Boolean;
Var I, J, K, W : LongInt;
Begin
  KPeekMsg := True;
  I := Threads[T].QHead;
  While I <> Threads[T].QTail Do
  Begin
    If MsgMatch(MsgQ[T * MaxQueue + I], Hwnd, MinM, MaxM) Then
    Begin
      M := MsgQ[T * MaxQueue + I];
      If Remove Then
      Begin
        { retirer l'element I de la file }
        J := I;
        While J <> Threads[T].QHead Do
        Begin
          K := (J + MaxQueue - 1) Mod MaxQueue;
          MsgQ[T * MaxQueue + J] := MsgQ[T * MaxQueue + K];
          J := K;
        End;
        Threads[T].QHead := (Threads[T].QHead + 1) Mod MaxQueue;
      End;
      Exit;
    End;
    I := (I + 1) Mod MaxQueue;
  End;
  If Threads[T].QuitFlag Then
  Begin
    M.Hwnd := 0; M.Msg := WM_QUIT; M.WP := Threads[T].QuitCode; M.LP := 0;
    M.Time := Ticks; M.X := CurX; M.Y := CurY;
    If Remove Then Threads[T].QuitFlag := False;
    Exit;
  End;
  { WM_PAINT }
  If Threads[T].PaintReq Then
  Begin
    Threads[T].PaintReq := False;
    For W := 0 To MaxWnd - 1 Do
      If Wnds[W].Used And (Wnds[W].Thread = T) And (Wnds[W].IKind = ikNone)
         And HasUpdate(W) And WndVisible(W) Then
      Begin
        Threads[T].PaintReq := True;
        If ((Hwnd = 0) Or (HwndOf(W) = Hwnd)) And
           (((MinM = 0) And (MaxM = 0)) Or
            ((MinM <= WM_PAINT) And (MaxM >= WM_PAINT))) Then
        Begin
          M.Hwnd := HwndOf(W); M.Msg := WM_PAINT; M.WP := 0; M.LP := 0;
          M.Time := Ticks; M.X := CurX; M.Y := CurY;
          Exit;
        End;
      End;
  End;
  { WM_TIMER }
  For I := 0 To MaxTimer - 1 Do
    If WTimers[I].Used And (WTimers[I].Thread = T) And
       (Ticks >= WTimers[I].Next) Then
    Begin
      If ((Hwnd = 0) Or (HwndOf(WTimers[I].Wnd) = Hwnd)) And
         (((MinM = 0) And (MaxM = 0)) Or
          ((MinM <= WM_TIMER) And (MaxM >= WM_TIMER))) Then
      Begin
        M.Hwnd := HwndOf(WTimers[I].Wnd); M.Msg := WM_TIMER;
        M.WP := WTimers[I].Id; M.LP := WTimers[I].Proc;
        M.Time := Ticks; M.X := CurX; M.Y := CurY;
        If Remove Then WTimers[I].Next := Ticks + WTimers[I].Elapse;
        Exit;
      End;
    End;
  KPeekMsg := False;
End;

{ ==================================================================== }
{ Partie 7 - Interface de Pasdows : bureau, barre des taches, menus,   }
{            Poste de travail, Bloc-notes et boites de dialogue        }
{ ==================================================================== }

Const
  mnStart = 1; mnPrograms = 2; mnDocs = 3; mnSettings = 4;
  cmNone = 0; cmExplorer = 1; cmComputer = 2; cmNotepad = 3; cmHelp = 4;
  cmRun = 5; cmAbout = 6; cmShutdown = 7; cmReadme = 8; cmRecycle = 9;
  cmSafeMode = 10; cmDosMode = 11; cmDocBase = 100; cmExeBase = 200;
  MaxDesk = 12;

Var
  KClass    : Array[0..31] Of LongInt;     { classe interne par sorte }
  TaskbarW  : LongInt;
  MenuW     : Array[0..3] Of LongInt;      { menus ouverts (niveaux) }
  MenuDepth : LongInt;
  DeskSel   : LongInt;
  DeskCnt   : LongInt;
  DeskName  : Array[0..MaxDesk - 1] Of String[63];
  DeskIco   : Array[0..MaxDesk - 1] Of LongInt;
  DeskCmd   : Array[0..MaxDesk - 1] Of LongInt;
  DeskPath  : Array[0..MaxDesk - 1] Of String[63];
  LastMinute : LongInt;
  DimOn     : Boolean;
  ExePaths  : Array[0..15] Of String[63];
  ExeCnt    : LongInt;
  NoteBuf   : LongInt;

Function RunExe(Path, Args : String) : Boolean; Forward;
Procedure KCommand(Cmd : LongInt); Forward;

Function TxtOk : String;
Begin
  TxtOk := 'OK';
End;

Function TxtCancel : String;
Begin
  TxtCancel := L('Annuler', 'Cancel', 'Abbrechen', 'Annulla', 'Cancelar');
End;

Function StartText : String;
Begin
  StartText := L('D'#130'marrer', 'Start', 'Start', 'Avvio', 'Inicio');
End;

Function TimeStr : String;
Begin
  ReadRtc;
  If Language = _English Then
  Begin
    If RtcHour = 0 Then TimeStr := '12:' + Pad2(RtcMin) + ' AM'
    Else If RtcHour < 12 Then
      TimeStr := IntStr(RtcHour) + ':' + Pad2(RtcMin) + ' AM'
    Else If RtcHour = 12 Then TimeStr := '12:' + Pad2(RtcMin) + ' PM'
    Else TimeStr := IntStr(RtcHour - 12) + ':' + Pad2(RtcMin) + ' PM';
  End
  Else
    TimeStr := Pad2(RtcHour) + ':' + Pad2(RtcMin);
End;

{ Zone client d'une fenetre interne en coordonnees ecran (incluses) }
Procedure KClient(W : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Begin
  X1 := Wnds[W].X + Wnds[W].CL; Y1 := Wnds[W].Y + Wnds[W].CT;
  X2 := Wnds[W].X + Wnds[W].CR - 1; Y2 := Wnds[W].Y + Wnds[W].CB - 1;
End;

{ Creer une fenetre interne }
Function KCreate(Kind : LongInt; Title : String; Icon, X, Y, WW, HH,
                 Style, ExStyle : LongInt) : LongInt;
Var W, HO : LongInt;
Begin
  HO := HeapOwner;
  HeapOwner := 0;
  W := CreateW(ExStyle, KClass[Kind], Title, Style And Not WS_VISIBLE, X, Y,
               WW, HH, -1, 0, 0, 0);
  HeapOwner := HO;
  If W >= 0 Then
  Begin
    Wnds[W].Thread := 0;
    Wnds[W].K4 := Icon;
    Wnds[W].KNeedPaint := True;
    If (Style And WS_VISIBLE) <> 0 Then ShowW(W, True, True);
  End;
  KCreate := W;
End;

Function KFindKind(Kind : LongInt) : LongInt;
Var I : LongInt;
Begin
  KFindKind := -1;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And (Wnds[I].IKind = Kind) Then
    Begin
      KFindKind := I;
      Exit;
    End;
End;

Procedure KRepaint(W : LongInt);
Begin
  If (W >= 0) And Wnds[W].Used Then Wnds[TopOf(W)].KNeedPaint := True;
End;

{ ------------------------------------------------------------------ }
{ Bureau                                                             }
{ ------------------------------------------------------------------ }

Procedure DeskAdd(Name : String; Ico, Cmd : LongInt; Path : String);
Begin
  If DeskCnt >= MaxDesk Then Exit;
  DeskName[DeskCnt] := Name; DeskIco[DeskCnt] := Ico;
  DeskCmd[DeskCnt] := Cmd; DeskPath[DeskCnt] := Path;
  Inc(DeskCnt);
End;

{ Icones du bureau : Poste de travail, Corbeille, Lisez-moi et les
  programmes .EXE de la racine du CD-ROM }
Procedure DeskBuild;
Var I, Lba, Size, Fl, Tm : LongInt; Nm : String;
Begin
  DeskCnt := 0; ExeCnt := 0;
  DeskAdd(L('Poste de travail', 'My Computer', 'Arbeitsplatz',
            'Risorse del computer', 'Mi PC'), icComputer, cmComputer, '');
  DeskAdd(L('Corbeille', 'Recycle Bin', 'Papierkorb', 'Cestino',
            'Papelera de reciclaje'), icRecycle, cmRecycle, '');
  DeskAdd(L('Lisez-moi', 'Read Me', 'Liesmich', 'Leggimi', 'L'#130'ame'),
          icText, cmReadme, '');
  I := 0;
  While IsoDirEntry(RootLba, RootSize, I, Nm, Lba, Size, Fl, Tm) Do
  Begin
    If ((Fl And 2) = 0) And (Copy(Nm, Length(Nm) - 3, 4) = '.EXE') And
       (ExeCnt < 16) Then
    Begin
      ExePaths[ExeCnt] := 'D:\' + Nm;
      DeskAdd(Copy(Nm, 1, Length(Nm) - 4), icApp, cmExeBase + ExeCnt,
              'D:\' + Nm);
      Inc(ExeCnt);
    End;
    Inc(I);
  End;
End;

Procedure DeskPos(I : LongInt; Var X, Y : LongInt);
Begin
  X := 6 + (I Div 6) * 84;
  Y := 8 + (I Mod 6) * 72;
End;

Procedure SplitLabel(Const S : String; N : LongInt; Var A, B : String);
Var P, K : LongInt;
Begin
  A := S; B := '';
  If Length(S) <= N Then Exit;
  P := 0;
  For K := 1 To Min(N + 1, Length(S)) Do
    If S[K] = ' ' Then P := K;
  If P = 0 Then P := N + 1;
  A := Copy(S, 1, P - 1);
  B := Trim(Copy(S, P, 255));
  If Length(B) > N Then B := Copy(B, 1, N - 3) + '...';
End;

Procedure DrawLabel(X, Y, W : LongInt; Const S : String; Sel : Boolean;
                    Fg : LongInt);
Var A, B : String; K, Y2 : LongInt;
Begin
  SplitLabel(S, W Div 8, A, B);
  If B <> '' Then Y2 := Y + 31 Else Y2 := Y + 15;
  If Sel Then
  Begin
    K := Max(TextW(A), TextW(B));
    FBar(X + (W - K) Div 2 - 2, Y, X + (W + K) Div 2 + 1, Y2, cNavy);
    Fg := cWhite;
  End;
  OutCenter(X, X + W - 1, Y, A, Fg);
  If B <> '' Then OutCenter(X, X + W - 1, Y + 16, B, Fg);
End;

Procedure DeskDraw(R : TRect);
Var I, X, Y : LongInt; T : TRect; Fg : LongInt;
Begin
  SetTarget(Back, 0, 0);
  SetClip(R.L, R.T, R.R - 1, R.B - 1);
  FBar(R.L, R.T, R.R - 1, R.B - 1, DeskColor);
  If DeskColor = cSilver Then Fg := cBlack Else Fg := cWhite;
  For I := 0 To DeskCnt - 1 Do
  Begin
    DeskPos(I, X, Y);
    SetR(T, X, Y, X + 84, Y + 70);
    If RInter(T, T, R) Then
    Begin
      PaintIcon(DeskIco[I], X + 26, Y, 32);
      DrawLabel(X + 2, Y + 35, 80, DeskName[I], DeskSel = I, Fg);
    End;
  End;
  If DimOn Then
  Begin
    SetClip(R.L, R.T, R.R - 1, R.B - 1);
    Dither(R.L, R.T, R.R - 1, R.B - 1, cBlack, 0);
  End;
End;

Function DeskHit(PX, PY : LongInt) : LongInt;
Var I, X, Y : LongInt;
Begin
  DeskHit := -1;
  For I := 0 To DeskCnt - 1 Do
  Begin
    DeskPos(I, X, Y);
    If InRect(PX, PY, X + 22, Y, X + 61, Y + 33) Or
       InRect(PX, PY, X + 4, Y + 35, X + 79, Y + 66) Then
    Begin
      DeskHit := I;
      Exit;
    End;
  End;
End;

Procedure DeskRedraw(I : LongInt);
Var X, Y : LongInt;
Begin
  If I < 0 Then Exit;
  DeskPos(I, X, Y);
  MarkDirty(X, Y, X + 86, Y + 70);
End;

{ ------------------------------------------------------------------ }
{ Barre des taches                                                   }
{ ------------------------------------------------------------------ }

Function StartW : LongInt;
Begin
  StartW := TextW(StartText) + 30;
End;

Function TrayX : LongInt;
Begin
  TrayX := ScrW - 4 - (TextW(TimeStr) + 34);
End;

Function TaskCount : LongInt;
Var I, N : LongInt;
Begin
  N := 0;
  For I := 0 To MaxWnd - 1 Do
    If IsTaskWin(I) Then Inc(N);
  TaskCount := N;
End;

{ N-ieme fenetre de la barre des taches (ordre de creation) }
Function TaskWin(N : LongInt) : LongInt;
Var I, J, Best, BS, LastSeq : LongInt;
Begin
  TaskWin := -1;
  LastSeq := -1;
  For J := 0 To N Do
  Begin
    Best := -1; BS := $7FFFFFFF;
    For I := 0 To MaxWnd - 1 Do
      If IsTaskWin(I) And (Wnds[I].Seq > LastSeq) And (Wnds[I].Seq < BS)
      Then
      Begin
        Best := I; BS := Wnds[I].Seq;
      End;
    If Best < 0 Then Exit;
    LastSeq := BS;
    TaskWin := Best;
  End;
End;

Function TaskBtnW : LongInt;
Var N, A : LongInt;
Begin
  N := Max(1, TaskCount);
  A := (TrayX - 6 - (StartW + 8)) Div N;
  If A > 160 Then A := 160;
  TaskBtnW := A;
End;

Procedure PaintTaskbar(W : LongInt);
Var I, N, X1, X2, K, D : LongInt; Pressed : Boolean; T : String;
Begin
  FBar(0, TaskY, ScrW - 1, ScrH - 1, cSilver);
  HLine(0, ScrW - 1, TaskY + 1, cWhite);
  Pressed := (MenuDepth > 0) And (Wnds[MenuW[0]].K1 = mnStart);
  Raised(2, TaskY + 4, StartW + 1, TaskY + 25, Pressed);
  If Pressed Then D := 1 Else D := 0;
  PaintIcon(icLogo, 6 + D, TaskY + 7 + D, 16);
  OutBold(25 + D, TaskY + 7 + D, StartText, cBlack);
  N := TaskCount;
  For I := 0 To N - 1 Do
  Begin
    K := TaskWin(I);
    If K < 0 Then Break;
    X1 := StartW + 8 + I * TaskBtnW;
    X2 := X1 + TaskBtnW - 4;
    Pressed := (K = ActiveWin) And Not Wnds[K].Min;
    Raised(X1, TaskY + 4, X2, TaskY + 25, Pressed);
    If Pressed Then Dither(X1 + 2, TaskY + 6, X2 - 2, TaskY + 23, cWhite, 0);
    If Wnds[K].IKind <> ikNone Then PaintIcon(Wnds[K].K4, X1 + 4, TaskY + 7, 16)
    Else PaintIcon(icApp, X1 + 4, TaskY + 7, 16);
    T := Fit(Wnds[K].Text, X2 - X1 - 26);
    If Pressed Then OutBold(X1 + 23, TaskY + 8, T, cBlack)
    Else OutTxt(X1 + 23, TaskY + 7, T, cBlack);
  End;
  X1 := TrayX;
  Edge(X1, TaskY + 4, ScrW - 4, TaskY + 25, cGray, cWhite);
  PaintIcon(icDisplay, X1 + 4, TaskY + 7, 16);
  OutTxt(X1 + 26, TaskY + 7, TimeStr, cBlack);
End;

Procedure TaskbarChanged;
Begin
  If (TaskbarW >= 0) And Wnds[TaskbarW].Used Then
    Wnds[TaskbarW].KNeedPaint := True;
End;

Procedure OpenStartMenu; Forward;
Procedure CloseMenus(Lv : LongInt); Forward;

Procedure TaskbarMouse(Msg, X, Y : LongInt);
Var I, N, X1, X2, K : LongInt;
Begin
  If Msg <> WM_LBUTTONDOWN Then Exit;
  X := X + Wnds[TaskbarW].X; Y := Y + Wnds[TaskbarW].Y;
  If InRect(X, Y, 2, TaskY + 4, StartW + 1, TaskY + 25) Then
  Begin
    If (MenuDepth > 0) And (Wnds[MenuW[0]].K1 = mnStart) Then CloseMenus(0)
    Else OpenStartMenu;
    Exit;
  End;
  CloseMenus(0);
  N := TaskCount;
  For I := 0 To N - 1 Do
  Begin
    X1 := StartW + 8 + I * TaskBtnW;
    X2 := X1 + TaskBtnW - 4;
    If (X >= X1) And (X <= X2) Then
    Begin
      K := TaskWin(I);
      If K < 0 Then Exit;
      If Wnds[K].Min Then RestoreW(K)
      Else If K = ActiveWin Then MinimizeW(K)
      Else ActivateW(K);
      Exit;
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Menus du menu Demarrer (fenetres surgissantes)                     }
{ ------------------------------------------------------------------ }

{ Fichier texte N de la racine du CD (menu Documents) }
Function DocFile(N : LongInt; Var Nm : String) : Boolean;
Var I, C, Lba, Size, Fl, Tm : LongInt; E : String;
Begin
  DocFile := False;
  I := 0; C := 0;
  While IsoDirEntry(RootLba, RootSize, I, Nm, Lba, Size, Fl, Tm) Do
  Begin
    E := Copy(Nm, Pos('.', Nm) + 1, 3);
    If ((Fl And 2) = 0) And ((E = 'TXT') Or (E = 'BAT') Or (E = 'INI'))
    Then
    Begin
      If C = N Then
      Begin
        DocFile := True;
        Exit;
      End;
      Inc(C);
    End;
    Inc(I);
  End;
End;

Function MenuCount(M : LongInt) : LongInt;
Var N : LongInt; S : String;
Begin
  Case M Of
    mnStart : MenuCount := 8;
    mnPrograms : MenuCount := 3 + ExeCnt;
    mnSettings : MenuCount := 2;
    mnDocs :
    Begin
      N := 0;
      While (N < 10) And DocFile(N, S) Do Inc(N);
      If N = 0 Then N := 1;
      MenuCount := N;
    End;
  Else
    MenuCount := 0;
  End;
End;

Procedure MenuItem(M, I : LongInt; Var T : String;
                   Var Cmd, Sub, Icon : LongInt);
Begin
  T := '-'; Cmd := cmNone; Sub := 0; Icon := 0;
  Case M Of
    mnStart :
      Case I Of
        0 : Begin
              T := L('Programmes', 'Programs', 'Programme', 'Programmi',
                     'Programas');
              Sub := mnPrograms; Icon := icPrograms;
            End;
        1 : Begin
              T := L('Documents', 'Documents', 'Dokumente', 'Documenti',
                     'Documentos');
              Sub := mnDocs; Icon := icDocs;
            End;
        2 : Begin
              T := L('Param'#138'tres', 'Settings', 'Einstellungen',
                     'Impostazioni', 'Configuraci'#162'n');
              Sub := mnSettings; Icon := icSettings;
            End;
        3 : Begin
              T := L('Aide', 'Help', 'Hilfe', 'Guida', 'Ayuda');
              Cmd := cmHelp; Icon := icHelp;
            End;
        4 : Begin
              T := L('Ex'#130'cuter...', 'Run...', 'Ausf'#129'hren...',
                     'Esegui...', 'Ejecutar...');
              Cmd := cmRun; Icon := icRun;
            End;
        5 : Begin
              T := L('A propos...', 'About...', 'Info...',
                     'Informazioni...', 'Acerca de...');
              Cmd := cmAbout; Icon := icInfo;
            End;
        7 : Begin
              T := L('Arr'#136'ter...', 'Shut Down...', 'Beenden...',
                     'Chiudi sessione...', 'Apagar el sistema...');
              Cmd := cmShutdown; Icon := icShutdown;
            End;
      End;
    mnPrograms :
      If I = 0 Then
      Begin
        T := L('Explorateur Windows', 'Windows Explorer',
               'Windows-Explorer', 'Gestione risorse',
               'Explorador de Windows');
        Cmd := cmExplorer; Icon := icExplorer;
      End
      Else If I = 1 Then
      Begin
        T := L('Bloc-notes', 'Notepad', 'Editor', 'Blocco note',
               'Bloc de notas');
        Cmd := cmNotepad; Icon := icNotepad;
      End
      Else If I = 2 Then
      Begin
        T := '-';
      End
      Else
      Begin
        T := BaseName(ExePaths[I - 3]);
        Cmd := cmExeBase + I - 3; Icon := icApp;
      End;
    mnSettings :
      If I = 0 Then
      Begin
        T := L('Mode sans '#130'chec (16 couleurs)', 'Safe mode (16 colors)',
               'Abgesicherter Modus', 'Modalit'#133' provvisoria',
               'Modo a prueba de fallos');
        Cmd := cmSafeMode; Icon := icDisplay;
      End
      Else
      Begin
        T := L('Mode MS-DOS', 'MS-DOS mode', 'MS-DOS-Modus',
               'Modalit'#133' MS-DOS', 'Modo MS-DOS');
        Cmd := cmDosMode; Icon := icDos;
      End;
    mnDocs :
      If DocFile(I, T) Then
      Begin
        Cmd := cmDocBase + I; Icon := icText;
      End
      Else
        T := L('(vide)', '(empty)', '(leer)', '(vuoto)', '(vac'#161'o)');
  End;
End;

Function MenuItemH(M : LongInt) : LongInt;
Begin
  If M = mnStart Then MenuItemH := 32 Else MenuItemH := 20;
End;

{ Ouvrir le menu M au niveau Lv (coin X, Y ; Up : au-dessus de Y) }
Procedure OpenMenu(Lv, M, X, Y : LongInt; Up : Boolean);
Var I, WW, HH, Cmd, Sub, Ic : LongInt; T : String;
Begin
  CloseMenus(Lv);
  WW := 0; HH := 6;
  For I := 0 To MenuCount(M) - 1 Do
  Begin
    MenuItem(M, I, T, Cmd, Sub, Ic);
    If T = '-' Then HH := HH + 8
    Else
    Begin
      HH := HH + MenuItemH(M);
      If TextW(T) > WW Then WW := TextW(T);
    End;
  End;
  WW := WW + 62;
  If M = mnStart Then WW := WW + 40;
  If WW < 140 Then WW := 140;
  If Up Then Y := Y - HH;
  If Y + HH > TaskY Then Y := TaskY - HH;
  If Y < 0 Then Y := 0;
  If X + WW > ScrW Then X := ScrW - WW;
  MenuW[Lv] := KCreate(ikMenu, '', 0, X, Y, WW, HH, WS_POPUP,
                       WS_EX_TOPMOST Or WS_EX_TOOLWINDOW);
  If MenuW[Lv] < 0 Then Exit;
  Wnds[MenuW[Lv]].K1 := M;
  Wnds[MenuW[Lv]].K2 := -1;
  Wnds[MenuW[Lv]].K3 := Lv;
  ShowW(MenuW[Lv], True, False);
  ZTop(MenuW[Lv]);
  MenuDepth := Lv + 1;
  TaskbarChanged;
End;

Procedure CloseMenus(Lv : LongInt);
Var I : LongInt;
Begin
  For I := MenuDepth - 1 DownTo Lv Do
    If (MenuW[I] >= 0) And Wnds[MenuW[I]].Used Then DestroyW(MenuW[I]);
  If MenuDepth > Lv Then MenuDepth := Lv;
  TaskbarChanged;
End;

Procedure OpenStartMenu;
Begin
  CloseMenus(0);
  OpenMenu(0, mnStart, 2, TaskY + 2, True);
End;

{ Texte vertical (bandeau du menu Demarrer), de bas en haut }
Procedure RotText(X, Y : LongInt; Const S : String; C : LongInt);
Var K, R, CX, B : LongInt;
Begin
  For K := 1 To Length(S) Do
  Begin
    For R := 0 To 15 Do
    Begin
      B := Mem[0:FontAddr + Ord(S[K]) * 16 + R];
      For CX := 0 To 7 Do
        If (B And ($80 Shr CX)) <> 0 Then
        Begin
          Pix(X + R, Y - CX, C);
          Pix(X + R, Y - CX - 1, C);
        End;
    End;
    Y := Y - 9;
  End;
End;

Procedure PaintMenu(W : LongInt);
Var I, X, Y, WW, HH, YY, Cmd, Sub, Ic, TX, M, Fg, IH : LongInt;
    T : String;
Begin
  X := Wnds[W].X; Y := Wnds[W].Y; WW := Wnds[W].W; HH := Wnds[W].H;
  M := Wnds[W].K1;
  IH := MenuItemH(M);
  Edge(X, Y, X + WW - 1, Y + HH - 1, cSilver, cBlack);
  Edge(X + 1, Y + 1, X + WW - 2, Y + HH - 2, cWhite, cGray);
  FBar(X + 2, Y + 2, X + WW - 3, Y + HH - 3, cSilver);
  TX := X + 8;
  If M = mnStart Then
  Begin
    FBar(X + 3, Y + 3, X + 24, Y + HH - 4, cGray);
    RotText(X + 6, Y + HH - 8, 'Pasdows', cSilver);
    RotText(X + 6, Y + HH - 8 - 7 * 9 - 4, '95', cWhite);
    TX := X + 30;
  End;
  YY := Y + 3;
  For I := 0 To MenuCount(M) - 1 Do
  Begin
    MenuItem(M, I, T, Cmd, Sub, Ic);
    If T = '-' Then
    Begin
      HLine(TX - 2, X + WW - 5, YY + 3, cGray);
      HLine(TX - 2, X + WW - 5, YY + 4, cWhite);
      YY := YY + 8;
    End
    Else
    Begin
      Fg := cBlack;
      If I = Wnds[W].K2 Then
      Begin
        FBar(TX - 4, YY, X + WW - 4, YY + IH - 1, cNavy);
        Fg := cWhite;
      End;
      If Ic <> 0 Then
      Begin
        If M = mnStart Then PaintIcon(Ic, TX, YY + 4, 24)
        Else PaintIcon(Ic, TX, YY + 2, 16);
      End;
      If M = mnStart Then OutTxt(TX + 32, YY + 8, T, Fg)
      Else OutTxt(TX + 22, YY + 2, T, Fg);
      If Sub <> 0 Then Arrow(X + WW - 14, YY + IH Div 2 - 3, 0, Fg);
      YY := YY + IH;
    End;
  End;
End;

Function MenuHitItem(W, Y : LongInt; Var ItemY : LongInt) : LongInt;
Var I, YY, Cmd, Sub, Ic, H : LongInt; T : String;
Begin
  MenuHitItem := -1;
  YY := 3;
  For I := 0 To MenuCount(Wnds[W].K1) - 1 Do
  Begin
    MenuItem(Wnds[W].K1, I, T, Cmd, Sub, Ic);
    If T = '-' Then H := 8 Else H := MenuItemH(Wnds[W].K1);
    If (Y >= YY) And (Y < YY + H) And (T <> '-') Then
    Begin
      MenuHitItem := I;
      ItemY := YY;
      Exit;
    End;
    YY := YY + H;
  End;
End;

Procedure MenuMouse(W, Msg, X, Y : LongInt);
Var I, IY, Cmd, Sub, Ic, Lv : LongInt; T : String;
Begin
  I := MenuHitItem(W, Y, IY);
  Lv := Wnds[W].K3;
  If I < 0 Then Exit;
  MenuItem(Wnds[W].K1, I, T, Cmd, Sub, Ic);
  If Msg = WM_MOUSEMOVE Then
  Begin
    If Wnds[W].K2 <> I Then
    Begin
      Wnds[W].K2 := I;
      KRepaint(W);
      If Sub <> 0 Then
        OpenMenu(Lv + 1, Sub, Wnds[W].X + Wnds[W].W - 3,
                 Wnds[W].Y + IY - 3, False)
      Else
        CloseMenus(Lv + 1);
    End;
    Exit;
  End;
  If Msg = WM_LBUTTONUP Then
  Begin
    If Sub <> 0 Then Exit;
    CloseMenus(0);
    If Cmd <> cmNone Then KCommand(Cmd);
  End;
End;

{ ------------------------------------------------------------------ }
{ Boites de message et dialogues simples                             }
{ ------------------------------------------------------------------ }

Const
  IDOK = 1; IDCANCEL = 2; IDABORT = 3; IDRETRY = 4; IDIGNORE = 5;
  IDYES = 6; IDNO = 7;

{ Boutons d'une boite de message selon MB_* }
Function MbCount(Typ : LongInt) : LongInt;
Begin
  Case Typ And 15 Of
    1, 4, 5 : MbCount := 2;
    2, 3 : MbCount := 3;
  Else
    MbCount := 1;
  End;
End;

Function MbId(Typ, I : LongInt) : LongInt;
Begin
  Case Typ And 15 Of
    1 : If I = 0 Then MbId := IDOK Else MbId := IDCANCEL;
    2 : Case I Of 0 : MbId := IDABORT; 1 : MbId := IDRETRY;
        Else MbId := IDIGNORE End;
    3 : Case I Of 0 : MbId := IDYES; 1 : MbId := IDNO;
        Else MbId := IDCANCEL End;
    4 : If I = 0 Then MbId := IDYES Else MbId := IDNO;
    5 : If I = 0 Then MbId := IDRETRY Else MbId := IDCANCEL;
  Else
    MbId := IDOK;
  End;
End;

Function MbText(Id : LongInt) : String;
Begin
  Case Id Of
    IDOK : MbText := 'OK';
    IDCANCEL : MbText := TxtCancel;
    IDABORT : MbText := L('Abandonner', 'Abort', 'Abbrechen', 'Interrompi',
                          'Anular');
    IDRETRY : MbText := L('R'#130'essayer', 'Retry', 'Wiederholen', 'Riprova',
                          'Reintentar');
    IDIGNORE : MbText := L('Ignorer', 'Ignore', 'Ignorieren', 'Ignora',
                           'Omitir');
    IDYES : MbText := L('Oui', 'Yes', 'Ja', 'S'#141, 'S'#161);
  Else
    MbText := L('Non', 'No', 'Nein', 'No', 'No');
  End;
End;

Procedure MbBtnRect(W, I : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Var CX1, CY1, CX2, CY2, N : LongInt;
Begin
  KClient(W, CX1, CY1, CX2, CY2);
  N := MbCount(Wnds[W].K2);
  X1 := (CX1 + CX2) Div 2 - (N * 90 - 6) Div 2 + I * 90;
  X2 := X1 + 83;
  Y2 := CY2 - 10; Y1 := Y2 - 22;
End;

{ Boite de message : K1 resultat (0 tant qu'elle est ouverte),
  K2 type MB_*, K3 icone, KS texte }
Function MsgBoxOpen(Title, Text : String; Typ : LongInt) : LongInt;
Var W, N, Ic, WW : LongInt;
Begin
  Case Typ And $F0 Of
    $10 : Ic := icError;
    $20 : Ic := icQuestion;
    $30 : Ic := icWarn;
    $40 : Ic := icInfo;
  Else
    Ic := 0;
  End;
  SetTarget(Back, 0, 0);
  N := WrapText(0, 0, 320, Text, 0, False);
  If N < 2 Then N := 2;
  WW := 420;
  W := KCreate(ikMsgBox, Title, icLogo, (ScrW - WW) Div 2,
               (TaskY - (110 + N * 16)) Div 2, WW, 110 + N * 16,
               WS_POPUP Or WS_CAPTION Or WS_SYSMENU, WS_EX_DLGMODALFRAME);
  If W >= 0 Then
  Begin
    Wnds[W].KS := Text;
    Wnds[W].K1 := 0; Wnds[W].K2 := Typ; Wnds[W].K3 := Ic;
    ShowW(W, True, True);
    If Ic = icError Then KBeep;
  End;
  MsgBoxOpen := W;
End;

Procedure PaintMsgBox(W : LongInt);
Var X1, Y1, X2, Y2, I, BX1, BY1, BX2, BY2, TX : LongInt;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y2, cSilver);
  TX := X1 + 16;
  If Wnds[W].K3 <> 0 Then
  Begin
    PaintIcon(Wnds[W].K3, X1 + 14, Y1 + 14, 32);
    TX := X1 + 62;
  End;
  WrapText(TX, Y1 + 18, X2 - TX - 10, Wnds[W].KS, cBlack, True);
  For I := 0 To MbCount(Wnds[W].K2) - 1 Do
  Begin
    MbBtnRect(W, I, BX1, BY1, BX2, BY2);
    PushButton(BX1, BY1, BX2, BY2, MbText(MbId(Wnds[W].K2, I)),
               (PressWin = W) And (PressBtn = I), I = 0);
  End;
End;

Procedure MsgBoxEnd(W, Res : LongInt);
Begin
  Wnds[W].K1 := Res;
  Wnds[W].DlgEnded := True;
  ShowW(W, False, False);
End;

Procedure MsgBoxMouse(W, Msg, X, Y : LongInt);
Var I, X1, Y1, X2, Y2 : LongInt;
Begin
  X := X + Wnds[W].X + Wnds[W].CL; Y := Y + Wnds[W].Y + Wnds[W].CT;
  For I := 0 To MbCount(Wnds[W].K2) - 1 Do
  Begin
    MbBtnRect(W, I, X1, Y1, X2, Y2);
    If InRect(X, Y, X1, Y1, X2, Y2) Then
    Begin
      If Msg = WM_LBUTTONDOWN Then
      Begin
        PressWin := W; PressBtn := I;
        CaptureWin := W;
        KRepaint(W);
      End
      Else If (Msg = WM_LBUTTONUP) And (PressWin = W) And (PressBtn = I)
      Then
      Begin
        PressWin := -1; CaptureWin := -1;
        MsgBoxEnd(W, MbId(Wnds[W].K2, I));
      End;
      Exit;
    End;
  End;
  If Msg = WM_LBUTTONUP Then
  Begin
    If PressWin = W Then
    Begin
      PressWin := -1;
      KRepaint(W);
    End;
    CaptureWin := -1;
  End;
End;

{ Boite de message modale (bloque la tache appelante) }
Function MsgBoxModal(Title, Text : String; Typ : LongInt) : LongInt;
Var W, R : LongInt;
Begin
  W := MsgBoxOpen(Title, Text, Typ);
  If W < 0 Then
  Begin
    MsgBoxModal := IDCANCEL;
    Exit;
  End;
  If CurT = 0 Then
  Begin
    MsgBoxModal := 0;
    Exit;
  End;
  While Not Wnds[W].DlgEnded Do KYield;
  R := Wnds[W].K1;
  DestroyW(W);
  MsgBoxModal := R;
End;

Function ModalBlocked(T : LongInt) : Boolean;
Var I : LongInt;
Begin
  ModalBlocked := False;
  If (T < 0) Or (Wnds[T].IKind = ikTaskbar) Or (Wnds[T].IKind = ikMenu) Then
    Exit;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And Wnds[I].Visible And (I <> T) And
       ((Wnds[I].IKind = ikMsgBox) Or (Wnds[I].IKind = ikShutdown)) Then
    Begin
      ModalBlocked := True;
      Exit;
    End;
End;

{ ------------------------------------------------------------------ }
{ Poste de travail / Explorateur (K1 selection, KS chemin du CD)     }
{ ------------------------------------------------------------------ }

Procedure NoteOpen(Path : String); Forward;

Function ExpDirLba(W : LongInt; Var Lba, Size : LongInt) : Boolean;
Var Fl, Tm : LongInt;
Begin
  ExpDirLba := IsoLookup(Copy(Wnds[W].KS, 3, 255), Lba, Size, Fl, Tm);
End;

Function ExpEntry(W, I : LongInt; Var Nm : String; Var Fl, Size : LongInt)
  : Boolean;
Var DL, DS, Lba, Tm : LongInt;
Begin
  ExpEntry := False;
  If Wnds[W].KS = '' Then
  Begin
    If I = 0 Then
    Begin
      Nm := '(C:)'; Fl := 2; Size := 0; ExpEntry := True;
    End
    Else If I = 1 Then
    Begin
      Nm := VolLabel + ' (D:)'; Fl := 2; Size := 0; ExpEntry := True;
    End;
    Exit;
  End;
  If Not ExpDirLba(W, DL, DS) Then Exit;
  ExpEntry := IsoDirEntry(DL, DS, I, Nm, Lba, Size, Fl, Tm);
End;

Function ExpIcon(Nm : String; Fl : LongInt) : LongInt;
Var E : String;
Begin
  E := Copy(Nm, Pos('.', Nm) + 1, 3);
  If Nm = '(C:)' Then ExpIcon := icHardDisk
  Else If Pos('(D:)', Nm) > 0 Then ExpIcon := icCdrom
  Else If (Fl And 2) <> 0 Then ExpIcon := icFolder
  Else If (E = 'EXE') Or (E = 'COM') Then ExpIcon := icApp
  Else If (E = 'TXT') Or (E = 'BAT') Or (E = 'INI') Or (E = 'SYS') Then
    ExpIcon := icText
  Else ExpIcon := icDocs;
End;

Procedure PaintExplorer(W : LongInt);
Var X1, Y1, X2, Y2, I, X, Y, Fl, Size, Cols, N : LongInt; Nm, S : String;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y1 + 29, cSilver);
  Raised(X1 + 4, Y1 + 4, X1 + 29, Y1 + 26, False);
  PaintIcon(icFolder, X1 + 8, Y1 + 7, 16);
  Arrow(X1 + 13, Y1 + 11, 2, cBlack);
  Sunken(X1 + 36, Y1 + 4, X2 - 4, Y1 + 26, cWhite);
  If Wnds[W].KS = '' Then
    OutTxt(X1 + 42, Y1 + 7, L('Poste de travail', 'My Computer',
           'Arbeitsplatz', 'Risorse del computer', 'Mi PC'), cBlack)
  Else OutTxt(X1 + 42, Y1 + 7, Wnds[W].KS, cBlack);
  Y1 := Y1 + 30;
  Sunken(X1, Y1, X2, Y2 - 22, cWhite);
  Edge(X1, Y2 - 19, X2, Y2, cGray, cWhite);
  FBar(X1 + 1, Y2 - 18, X2 - 1, Y2 - 1, cSilver);
  Cols := Max(1, (X2 - X1 - 8) Div 100);
  SetClip(X1 + 2, Y1 + 2, X2 - 2, Y2 - 24);
  I := 0; N := 0;
  While ExpEntry(W, I, Nm, Fl, Size) Do
  Begin
    X := X1 + 6 + (I Mod Cols) * 100;
    Y := Y1 + 6 + (I Div Cols) * 70 - Wnds[W].K2 * 70;
    If (Y > Y1 - 70) And (Y < Y2) Then
    Begin
      PaintIcon(ExpIcon(Nm, Fl), X + 32, Y, 32);
      DrawLabel(X, Y + 34, 96, Nm, I = Wnds[W].K1, cBlack);
    End;
    If I = Wnds[W].K1 Then
    Begin
      S := Nm;
      If (Fl And 2) = 0 Then S := S + ' : ' + IntStr(Size) + ' ' +
         L('octets', 'bytes', 'Byte', 'byte', 'bytes');
    End;
    Inc(I); Inc(N);
  End;
  SetClip(X1, Y1, X2, Y2);
  If Wnds[W].K1 < 0 Then
    S := IntStr(N) + ' ' + L('objet(s)', 'object(s)', 'Objekt(e)',
                              'oggetti', 'objeto(s)');
  OutTxt(X1 + 4, Y2 - 17, Fit(S, X2 - X1 - 8), cBlack);
End;

Procedure ExpOpenItem(W, I : LongInt);
Var Nm, P, E : String; Fl, Size : LongInt;
Begin
  If Not ExpEntry(W, I, Nm, Fl, Size) Then Exit;
  If Wnds[W].KS = '' Then
  Begin
    If I = 0 Then
    Begin
      MsgBoxOpen(L('Poste de travail', 'My Computer', 'Arbeitsplatz',
                   'Risorse del computer', 'Mi PC'), L(
        'C: est un disque virtuel en m'#130'moire (C:\WINDOWS, C:\TEMP).',
        'C: is a virtual RAM disk (C:\WINDOWS, C:\TEMP).',
        'C: ist ein virtuelles RAM-Laufwerk.',
        'C: '#138' un disco virtuale in memoria.',
        'C: es un disco virtual en memoria.'), $40);
      Exit;
    End;
    Wnds[W].KS := 'D:';
  End
  Else
  Begin
    P := Wnds[W].KS + '\' + Nm;
    If (Fl And 2) <> 0 Then Wnds[W].KS := P
    Else
    Begin
      E := Copy(Nm, Pos('.', Nm) + 1, 3);
      If (E = 'EXE') Or (E = 'COM') Then RunExe(P, '')
      Else NoteOpen(P);
      Exit;
    End;
  End;
  Wnds[W].K1 := -1; Wnds[W].K2 := 0;
  KRepaint(W);
End;

Procedure ExpUp(W : LongInt);
Var P : LongInt;
Begin
  If Wnds[W].KS = '' Then Exit;
  If Length(Wnds[W].KS) <= 2 Then Wnds[W].KS := ''
  Else
  Begin
    P := Length(Wnds[W].KS);
    While (P > 0) And (Wnds[W].KS[P] <> '\') Do Dec(P);
    Wnds[W].KS := Copy(Wnds[W].KS, 1, P - 1);
  End;
  Wnds[W].K1 := -1; Wnds[W].K2 := 0;
  KRepaint(W);
End;

Procedure ExpMouse(W, Msg, X, Y : LongInt);
Var X1, Y1, X2, Y2, Cols, I, Fl, Size : LongInt; Nm : String;
Begin
  If (Msg <> WM_LBUTTONDOWN) And (Msg <> WM_LBUTTONDBLCLK) Then Exit;
  X := X + Wnds[W].X + Wnds[W].CL; Y := Y + Wnds[W].Y + Wnds[W].CT;
  KClient(W, X1, Y1, X2, Y2);
  If InRect(X, Y, X1 + 4, Y1 + 4, X1 + 29, Y1 + 26) Then
  Begin
    ExpUp(W);
    Exit;
  End;
  Y1 := Y1 + 30;
  Cols := Max(1, (X2 - X1 - 8) Div 100);
  If (X < X1 + 6) Or (Y < Y1 + 6) Then Exit;
  I := ((Y - Y1 - 6) Div 70 + Wnds[W].K2) * Cols + (X - X1 - 6) Div 100;
  If (X - X1 - 6) Div 100 >= Cols Then Exit;
  If Not ExpEntry(W, I, Nm, Fl, Size) Then I := -1;
  If (Msg = WM_LBUTTONDBLCLK) And (I >= 0) Then ExpOpenItem(W, I)
  Else If I <> Wnds[W].K1 Then
  Begin
    Wnds[W].K1 := I;
    KRepaint(W);
  End;
End;

{ ------------------------------------------------------------------ }
{ Bloc-notes (lecture et edition d'un fichier texte)                 }
{   K1 longueur, K2 curseur, K3 premiere ligne affichee, KS nom      }
{ ------------------------------------------------------------------ }

Const
  NoteMax = 60000;

Function NLineStart(B, P : LongInt) : LongInt;
Begin
  While (P > 0) And (Mem[0:B + P - 1] <> 13) Do Dec(P);
  NLineStart := P;
End;

Function NLineEnd(B, P, N : LongInt) : LongInt;
Begin
  While (P < N) And (Mem[0:B + P] <> 13) Do Inc(P);
  NLineEnd := P;
End;

Procedure NoteOpen(Path : String);
Var W, A, Size, R, Wr, B : LongInt; CR : Boolean;
Begin
  W := KFindKind(ikNotepad);
  If W < 0 Then
  Begin
    W := KCreate(ikNotepad, '', icNotepad, 110, 46, 480, 340,
                 WS_OVERLAPPED Or WS_CAPTION Or WS_SYSMENU Or WS_THICKFRAME
                 Or WS_MINIMIZEBOX Or WS_MAXIMIZEBOX, WS_EX_CLIENTEDGE);
    If W < 0 Then Exit;
    Wnds[W].Extra := KAlloc(NoteMax + 16);
  End;
  B := Wnds[W].Extra;
  Wnds[W].K1 := 0; Wnds[W].K2 := 0; Wnds[W].K3 := 0;
  Wnds[W].KS := '';
  If Path <> '' Then
  Begin
    A := LoadWholeFile(Path, Size);
    If A <> 0 Then
    Begin
      If Size > NoteMax Then Size := NoteMax;
      Wr := 0; CR := False;
      For R := 0 To Size - 1 Do
      Begin
        If Mem[0:A + R] = 13 Then
        Begin
          Mem[0:B + Wr] := 13; Inc(Wr); CR := True;
        End
        Else If Mem[0:A + R] = 10 Then
        Begin
          If Not CR Then Begin Mem[0:B + Wr] := 13; Inc(Wr) End;
          CR := False;
        End
        Else
        Begin
          If (Mem[0:A + R] <> 26) And (Mem[0:A + R] <> 0) Then
          Begin
            Mem[0:B + Wr] := Mem[0:A + R]; Inc(Wr);
          End;
          CR := False;
        End;
      End;
      KFree(A);
      Wnds[W].K1 := Wr;
      Wnds[W].KS := BaseName(Path);
    End;
  End;
  If Wnds[W].KS = '' Then
    Wnds[W].Text := L('Sans titre', 'Untitled', 'Unbenannt', 'Senza nome',
                      'Sin t'#161'tulo')
  Else Wnds[W].Text := Wnds[W].KS;
  Wnds[W].Text := Wnds[W].Text + ' - ' + L('Bloc-notes', 'Notepad',
                  'Editor', 'Blocco note', 'Bloc de notas');
  Wnds[W].NeedNc := True;
  KRepaint(W);
  ShowW(W, True, True);
  ActivateW(W);
  TaskbarChanged;
End;

Procedure PaintNotepad(W : LongInt);
Var X1, Y1, X2, Y2, Rows, Cols, R, CC, B, N, P, E, Q : LongInt;
    S : String; Ch : LongInt;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y2, cWhite);
  B := Wnds[W].Extra; N := Wnds[W].K1;
  Rows := (Y2 - Y1 - 4) Div 16;
  Cols := (X2 - X1 - 6) Div 8;
  P := Wnds[W].K3;
  For R := 0 To Rows - 1 Do
  Begin
    If P > N Then Exit;
    E := NLineEnd(B, P, N);
    S := '';
    Q := P; CC := 0;
    While (Q < E) And (CC < Cols) Do
    Begin
      Ch := Mem[0:B + Q];
      If Ch < 32 Then Ch := 32;
      S := S + Chr(Ch);
      Inc(Q); Inc(CC);
    End;
    OutTxt(X1 + 3, Y1 + 2 + R * 16, S, cBlack);
    If (Wnds[W].K2 >= P) And (Wnds[W].K2 <= E) And (W = ActiveWin) Then
    Begin
      CC := Wnds[W].K2 - P;
      If CC <= Cols Then
        VLine(X1 + 3 + CC * 8, Y1 + 2 + R * 16, Y1 + 16 + R * 16, cBlack);
    End;
    P := E + 1;
  End;
End;

Procedure NoteKey(W, VK, Ch : LongInt);
Var B, N, C, LS, LE, Col, X1, Y1, X2, Y2, Rows, Ln, P : LongInt;
Begin
  B := Wnds[W].Extra; N := Wnds[W].K1; C := Wnds[W].K2;
  Case VK Of
    $25 : If C > 0 Then Dec(C);
    $27 : If C < N Then Inc(C);
    $24 : C := NLineStart(B, C);
    $23 : C := NLineEnd(B, C, N);
    $26 :
    Begin
      LS := NLineStart(B, C); Col := C - LS;
      If LS > 0 Then
      Begin
        LS := NLineStart(B, LS - 1); LE := NLineEnd(B, LS, N);
        C := Min(LS + Col, LE);
      End;
    End;
    $28 :
    Begin
      LS := NLineStart(B, C); Col := C - LS;
      LE := NLineEnd(B, C, N);
      If LE < N Then
      Begin
        LS := LE + 1; LE := NLineEnd(B, LS, N);
        C := Min(LS + Col, LE);
      End;
    End;
    $2E :
      If C < N Then
      Begin
        MoveMem(B + C + 1, B + C, N - C - 1);
        Dec(N);
      End;
    8 :
      If C > 0 Then
      Begin
        MoveMem(B + C, B + C - 1, N - C);
        Dec(N); Dec(C);
      End;
  Else
    If (Ch = 13) Or (Ch >= 32) Then
    Begin
      If N >= NoteMax Then Exit;
      MoveMem(B + C, B + C + 1, N - C);
      Mem[0:B + C] := Ch;
      Inc(N); Inc(C);
    End
    Else Exit;
  End;
  Wnds[W].K1 := N; Wnds[W].K2 := C;
  { premiere ligne affichee }
  KClient(W, X1, Y1, X2, Y2);
  Rows := Max(1, (Y2 - Y1 - 4) Div 16);
  If C < Wnds[W].K3 Then Wnds[W].K3 := NLineStart(B, C)
  Else
  Begin
    Ln := 0; P := Wnds[W].K3;
    While P < NLineStart(B, C) Do
    Begin
      P := NLineEnd(B, P, N) + 1;
      Inc(Ln);
    End;
    While Ln >= Rows Do
    Begin
      Wnds[W].K3 := NLineEnd(B, Wnds[W].K3, N) + 1;
      Dec(Ln);
    End;
  End;
  KRepaint(W);
End;

{ ------------------------------------------------------------------ }
{ A propos, Executer, Arreter, Aide                                  }
{ ------------------------------------------------------------------ }

Procedure DlgBtnRect(W, I, N : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Var CX1, CY1, CX2, CY2 : LongInt;
Begin
  KClient(W, CX1, CY1, CX2, CY2);
  Y2 := CY2 - 8; Y1 := Y2 - 22;
  X2 := CX2 - 10 - (N - 1 - I) * 92;
  X1 := X2 - 85;
End;

Function ShutText(I : LongInt) : String;
Begin
  Case I Of
    0 : ShutText := L('Arr'#136'ter l''ordinateur ?', 'Shut down the computer?',
                      'Computer herunterfahren?', 'Arrestare il sistema?',
                      #168'Apagar el equipo?');
    1 : ShutText := L('Red'#130'marrer l''ordinateur ?',
                      'Restart the computer?', 'Computer neu starten?',
                      'Riavviare il sistema?', #168'Reiniciar el equipo?');
  Else
    ShutText := L('Red'#130'marrer en mode MS-DOS ?',
                  'Restart the computer in MS-DOS mode?',
                  'Im MS-DOS-Modus neu starten?',
                  'Riavviare in modalit'#133' MS-DOS?',
                  #168'Reiniciar en modo MS-DOS?');
  End;
End;

Function MemKb : LongInt;
Begin
  MemKb := MemL[0:BootInfo + $18] + 1024;
End;

Procedure PaintDialog(W : LongInt);
Var X1, Y1, X2, Y2, I, BX1, BY1, BX2, BY2, N : LongInt; T : String;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y2, cSilver);
  Case Wnds[W].IKind Of
    ikAbout :
    Begin
      PaintIcon(icLogo, X1 + 14, Y1 + 14, 64);
      OutBold(X1 + 96, Y1 + 14, 'Pasdows 95', cBlack);
      OutTxt(X1 + 96, Y1 + 32, 'Version ' + KVersion + ' (VMM32)', cBlack);
      OutTxt(X1 + 96, Y1 + 48, 'Copyright (C) 2026 Gladir.com', cBlack);
      WrapText(X1 + 96, Y1 + 72, X2 - X1 - 104, L(
        'Noyau 32 bits capable d''ex'#130'cuter des programmes Windows 95 ' +
        '(KERNEL32, USER32, GDI32, WINMM).',
        '32-bit kernel able to run Windows 95 programs (KERNEL32, ' +
        'USER32, GDI32, WINMM).',
        '32-Bit-Kern f'#129'r Windows 95-Programme.',
        'Nucleo a 32 bit per programmi Windows 95.',
        'N'#163'cleo de 32 bits para programas de Windows 95.'),
        cBlack, True);
      HLine(X1 + 96, X2 - 10, Y1 + 120, cGray);
      HLine(X1 + 96, X2 - 10, Y1 + 121, cWhite);
      OutTxt(X1 + 96, Y1 + 130, L('M'#130'moire : ', 'Memory: ', 'Speicher: ',
             'Memoria: ', 'Memoria: ') + IntStr(MemKb) + ' Ko', cBlack);
      OutTxt(X1 + 96, Y1 + 148, L('Libre : ', 'Free: ', 'Frei: ',
             'Libera: ', 'Libre: ') + IntStr(HeapFreeBytes Div 1024) +
             ' Ko', cBlack);
      N := 1;
    End;
    ikRun :
    Begin
      PaintIcon(icRun, X1 + 12, Y1 + 12, 32);
      WrapText(X1 + 56, Y1 + 10, X2 - X1 - 64, L(
        'Tapez le nom d''un programme ou d''un document, et Pasdows ' +
        'l''ouvrira pour vous.',
        'Type the name of a program or document, and Pasdows will ' +
        'open it for you.',
        'Geben Sie den Namen eines Programms oder Dokuments ein.',
        'Digitare il nome del programma o documento da aprire.',
        'Escriba el nombre del programa o documento que desea abrir.'),
        cBlack, True);
      OutTxt(X1 + 12, Y1 + 68, L('Ouvrir :', 'Open:', #153'ffnen:', 'Apri:',
             'Abrir:'), cBlack);
      Sunken(X1 + 84, Y1 + 64, X2 - 12, Y1 + 87, cWhite);
      OutTxt(X1 + 89, Y1 + 68, Wnds[W].KS, cBlack);
      VLine(X1 + 89 + TextW(Wnds[W].KS), Y1 + 67, Y1 + 83, cBlack);
      N := 2;
    End;
    ikShutdown :
    Begin
      PaintIcon(icShutdown, X1 + 12, Y1 + 14, 32);
      OutTxt(X1 + 60, Y1 + 12, L('Voulez-vous vraiment :',
             'Are you sure you want to:', 'M'#148'chten Sie wirklich:',
             'Si desidera:', #168'Est'#160' seguro de que desea:'), cBlack);
      For I := 0 To 2 Do
        RadioButton(X1 + 60, Y1 + 38 + I * 24, ShutText(I), I = Wnds[W].K1);
      N := 2;
    End;
  Else
    N := 0;
  End;
  For I := 0 To N - 1 Do
  Begin
    DlgBtnRect(W, I, N, BX1, BY1, BX2, BY2);
    If Wnds[W].IKind = ikShutdown Then
    Begin
      If I = 0 Then T := L('Oui', 'Yes', 'Ja', 'S'#141, 'S'#161)
      Else T := L('Non', 'No', 'Nein', 'No', 'No');
    End
    Else If I = 0 Then T := TxtOk Else T := TxtCancel;
    PushButton(BX1, BY1, BX2, BY2, T, (PressWin = W) And (PressBtn = I),
               I = 0);
  End;
End;

Procedure DoShutdown(Mode : LongInt); Forward;

Procedure DialogAction(W, B : LongInt);
Var S : String; K : LongInt;
Begin
  K := Wnds[W].IKind;
  If K = ikRun Then
  Begin
    S := Trim(Wnds[W].KS);
    DestroyW(W);
    If (B = 0) And (S <> '') Then
      If Not RunExe(S, '') Then
        MsgBoxOpen(L('Ex'#130'cuter', 'Run', 'Ausf'#129'hren', 'Esegui',
          'Ejecutar'),
          L('Impossible de trouver '#174' ', 'Cannot find "', '"',
            'Impossibile trovare "', 'No se encuentra "') + S +
          L(' '#175'.', '".', '" nicht gefunden.', '".', '".'), $10);
    Exit;
  End;
  If K = ikShutdown Then
  Begin
    K := Wnds[W].K1;
    DestroyW(W);
    DimOn := False;
    MarkAll;
    If B = 0 Then DoShutdown(K);
    Exit;
  End;
  DestroyW(W);
End;

Procedure DialogMouse(W, Msg, X, Y : LongInt);
Var I, N, X1, Y1, X2, Y2, CX1, CY1, CX2, CY2 : LongInt;
Begin
  X := X + Wnds[W].X + Wnds[W].CL; Y := Y + Wnds[W].Y + Wnds[W].CT;
  If Wnds[W].IKind = ikAbout Then N := 1 Else N := 2;
  If (Wnds[W].IKind = ikShutdown) And (Msg = WM_LBUTTONDOWN) Then
  Begin
    KClient(W, CX1, CY1, CX2, CY2);
    For I := 0 To 2 Do
      If InRect(X, Y, CX1 + 60, CY1 + 38 + I * 24, CX2 - 8,
                CY1 + 54 + I * 24) Then
      Begin
        Wnds[W].K1 := I;
        KRepaint(W);
      End;
  End;
  For I := 0 To N - 1 Do
  Begin
    DlgBtnRect(W, I, N, X1, Y1, X2, Y2);
    If InRect(X, Y, X1, Y1, X2, Y2) Then
    Begin
      If Msg = WM_LBUTTONDOWN Then
      Begin
        PressWin := W; PressBtn := I; CaptureWin := W;
        KRepaint(W);
      End
      Else If (Msg = WM_LBUTTONUP) And (PressWin = W) And (PressBtn = I)
      Then
      Begin
        PressWin := -1; CaptureWin := -1;
        DialogAction(W, I);
      End;
      Exit;
    End;
  End;
  If Msg = WM_LBUTTONUP Then
  Begin
    If PressWin = W Then
    Begin
      PressWin := -1;
      KRepaint(W);
    End;
    CaptureWin := -1;
  End;
End;

Procedure PaintHelp(W : LongInt);
Var X1, Y1, X2, Y2 : LongInt;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y2, cWhite);
  PaintIcon(icHelp, X1 + 10, Y1 + 10, 32);
  OutBold(X1 + 52, Y1 + 18, Wnds[W].Text, cNavy);
  WrapText(X1 + 12, Y1 + 54, X2 - X1 - 24, L(
    'Double-cliquez sur un programme .EXE du bureau ou du Poste de ' +
    'travail pour l''ex'#130'cuter : Pasdows charge les vrais programmes ' +
    'Windows 95 (32 bits) et leur fournit KERNEL32, USER32, GDI32 et ' +
    'WINMM.|Menu D'#130'marrer : Ctrl+'#144'chap. Alt+F4 ferme la ' +
    'fen'#136'tre active, Alt+Tab change de fen'#136'tre.',
    'Double-click a .EXE program on the desktop or in My Computer to ' +
    'run it: Pasdows loads real Windows 95 (32-bit) programs and ' +
    'provides KERNEL32, USER32, GDI32 and WINMM.|Start menu: Ctrl+Esc. ' +
    'Alt+F4 closes the active window, Alt+Tab switches windows.',
    'Doppelklicken Sie auf ein .EXE-Programm, um es auszuf'#129'hren.|' +
    'Startmen'#129': Strg+Esc. Alt+F4 schlie'#225't das aktive Fenster.',
    'Fare doppio clic su un programma .EXE per eseguirlo.|' +
    'Menu Avvio: Ctrl+Esc. Alt+F4 chiude la finestra attiva.',
    'Haga doble clic en un programa .EXE para ejecutarlo.|' +
    'Men'#163' Inicio: Ctrl+Esc. Alt+F4 cierra la ventana activa.'),
    cBlack, True);
End;

{ ------------------------------------------------------------------ }
{ Arret, redemarrage, mode MS-DOS                                    }
{ ------------------------------------------------------------------ }

Procedure HaltCpu;
Begin
  asm
    cli
  @h:
    hlt
    jmp @h
  end;
End;

Procedure KReboot;
Begin
  KDelay(100);
  Port[$64] := $FE;
  KDelay(500);
  HaltCpu;
End;

Procedure DoShutdown(Mode : LongInt);
Var A, B : String;
Begin
  CursorErase;
  SetTarget(Back, 0, 0);
  FBar(0, 0, ScrW - 1, ScrH - 1, cBlack);
  If Mode = 2 Then
  Begin
    { IO.SYS demarrera directement l'invite MS-DOS }
    CmosWrite($7E, $D0);
    KReboot;
  End;
  If Mode = 1 Then
  Begin
    MarkAll; LfbCopy(Dirty);
    KReboot;
  End;
  A := L('Vous pouvez maintenant', 'It''s now safe to turn off',
         'Sie k'#148'nnen den Computer', 'Ora '#138' possibile spegnere',
         'Ahora puede apagar');
  B := L(#130'teindre votre ordinateur.', 'your computer.',
         'jetzt ausschalten.', 'il computer.', 'el equipo.');
  BigText((ScrW - TextW(A) * 2) Div 2, 190, A, cYellow, 2);
  BigText((ScrW - TextW(B) * 2) Div 2, 232, B, cYellow, 2);
  SetR(Dirty, 0, 0, ScrW, ScrH);
  LfbCopy(Dirty);
  { mise hors tension ACPI de QEMU/Bochs, sinon arret }
  PortW[$604] := $2000;
  PortW[$B004] := $2000;
  HaltCpu;
End;

{ ------------------------------------------------------------------ }
{ Commandes et procedure des fenetres internes                       }
{ ------------------------------------------------------------------ }

Procedure KCommand(Cmd : LongInt);
Var W : LongInt; Nm : String;
Begin
  Case Cmd Of
    cmComputer, cmExplorer :
    Begin
      W := KCreate(ikExplorer, '', icComputer, 60 + Ticks Mod 40,
                   36 + Ticks Mod 30, 440, 320, WS_OVERLAPPED Or WS_CAPTION Or
                   WS_SYSMENU Or WS_THICKFRAME Or WS_MINIMIZEBOX Or
                   WS_MAXIMIZEBOX, 0);
      If W < 0 Then Exit;
      Wnds[W].K1 := -1;
      If Cmd = cmExplorer Then Wnds[W].KS := 'D:' Else Wnds[W].KS := '';
      If Cmd = cmExplorer Then
      Begin
        Wnds[W].Text := L('Explorateur', 'Exploring', 'Explorer',
                          'Esplora', 'Explorando') + ' - ' + VolLabel;
        Wnds[W].K4 := icExplorer;
      End
      Else
        Wnds[W].Text := L('Poste de travail', 'My Computer', 'Arbeitsplatz',
                          'Risorse del computer', 'Mi PC');
      ShowW(W, True, True);
    End;
    cmNotepad : NoteOpen('');
    cmReadme : NoteOpen('D:\LISEZMOI.TXT');
    cmRecycle :
      MsgBoxOpen(L('Corbeille', 'Recycle Bin', 'Papierkorb', 'Cestino',
                   'Papelera'), L('La Corbeille est vide.',
                   'The Recycle Bin is empty.', 'Der Papierkorb ist leer.',
                   'Il Cestino '#138' vuoto.',
                   'La Papelera est'#160' vac'#161'a.'), $40);
    cmHelp :
    Begin
      W := KCreate(ikHelp, L('Aide de Pasdows', 'Pasdows Help',
                   'Pasdows-Hilfe', 'Guida di Pasdows', 'Ayuda de Pasdows'),
                   icHelp, 90, 40, 460, 300, WS_OVERLAPPED Or WS_CAPTION Or
                   WS_SYSMENU Or WS_THICKFRAME Or WS_MINIMIZEBOX Or
                   WS_MAXIMIZEBOX, 0);
      If W >= 0 Then ShowW(W, True, True);
    End;
    cmAbout :
    Begin
      W := KCreate(ikAbout, L('A propos de Pasdows 95', 'About Pasdows 95',
                   'Info '#129'ber Pasdows 95', 'Informazioni su Pasdows 95',
                   'Acerca de Pasdows 95'), icLogo, 115, 100, 410, 240,
                   WS_POPUP Or WS_CAPTION Or WS_SYSMENU, WS_EX_DLGMODALFRAME);
      If W >= 0 Then ShowW(W, True, True);
    End;
    cmRun :
    Begin
      W := KCreate(ikRun, L('Ex'#130'cuter', 'Run', 'Ausf'#129'hren', 'Esegui',
                   'Ejecutar'), icRun, 6, TaskY - 180, 370, 172,
                   WS_POPUP Or WS_CAPTION Or WS_SYSMENU, WS_EX_DLGMODALFRAME);
      If W >= 0 Then ShowW(W, True, True);
    End;
    cmShutdown :
    Begin
      DimOn := True;
      MarkAll;
      W := KCreate(ikShutdown, L('Arr'#136'ter Pasdows', 'Shut Down Pasdows',
                   'Pasdows beenden', 'Chiudi sessione', 'Apagar Pasdows'),
                   icShutdown, 140, 123, 360, 206, WS_POPUP Or WS_CAPTION Or
                   WS_SYSMENU, WS_EX_DLGMODALFRAME Or WS_EX_TOOLWINDOW Or
                   WS_EX_TOPMOST);
      If W >= 0 Then ShowW(W, True, True);
    End;
    cmSafeMode :
      MsgBoxOpen('Pasdows', L(
        'Pour d'#130'marrer en mode sans '#130'chec (interface 16 couleurs '
        + 'd''IO.SYS), red'#130'marrez et appuyez sur F5 ou F8.',
        'To start in safe mode (16-color IO.SYS interface), restart and '
        + 'press F5 or F8.',
        'Neu starten und F5 oder F8 dr'#129'cken.',
        'Riavviare e premere F5 o F8.',
        'Reinicie y pulse F5 o F8.'), $40);
    cmDosMode : DoShutdown(2);
  Else
    If Cmd >= cmExeBase Then RunExe(ExePaths[Cmd - cmExeBase], '')
    Else If Cmd >= cmDocBase Then
    Begin
      If DocFile(Cmd - cmDocBase, Nm) Then NoteOpen('D:\' + Nm);
    End
  End;
End;

Procedure KMouse(W, Msg, X, Y : LongInt);
Var I : LongInt;
Begin
  If W < 0 Then
  Begin
    { bureau }
    If (Msg <> WM_LBUTTONDOWN) And (Msg <> WM_RBUTTONDOWN) Then Exit;
    If MenuDepth > 0 Then CloseMenus(0);
    I := DeskHit(X, Y);
    If (I >= 0) And (I = LastClickW - 10000) And (Ticks - LastClickT < 700)
    Then
    Begin
      LastClickW := -1;
      KCommand(DeskCmd[I]);
      Exit;
    End;
    LastClickW := 10000 + I; LastClickT := Ticks;
    If I <> DeskSel Then
    Begin
      DeskRedraw(DeskSel);
      DeskSel := I;
      DeskRedraw(I);
    End;
    ActivateW(-1);
    Exit;
  End;
  If (MenuDepth > 0) And (Wnds[W].IKind <> ikMenu) And
     (Msg = WM_LBUTTONDOWN) Then CloseMenus(0);
  Case Wnds[W].IKind Of
    ikTaskbar : TaskbarMouse(Msg, X, Y);
    ikMenu : MenuMouse(W, Msg, X, Y);
    ikMsgBox : MsgBoxMouse(W, Msg, X, Y);
    ikExplorer : ExpMouse(W, Msg, X, Y);
    ikAbout, ikRun, ikShutdown : DialogMouse(W, Msg, X, Y);
  End;
End;

Procedure KKey(W, Msg, VK, Ch : LongInt);
Var I : LongInt;
Begin
  If W = -1 Then
  Begin
    { raccourcis globaux (avant la fenetre active) }
    If (VK = $5B) Or ((VK = $1B) And ((KeyState[$11] And $80) <> 0)) Then
    Begin
      If MenuDepth > 0 Then CloseMenus(0) Else OpenStartMenu;
      KeyState[$11] := KeyState[$11] And $7F;
      Exit;
    End;
    If MenuDepth > 0 Then
    Begin
      If VK = $1B Then CloseMenus(MenuDepth - 1);
      Exit;
    End;
    If ((KeyState[$12] And $80) <> 0) And (VK = $73) Then
    Begin
      I := ActiveWin;
      If I < 0 Then KCommand(cmShutdown)
      Else If Wnds[I].IKind <> ikNone Then
      Begin
        If Wnds[I].IKind = ikMsgBox Then MsgBoxEnd(I, IDCANCEL)
        Else If Wnds[I].IKind = ikShutdown Then DialogAction(I, 1)
        Else DestroyW(I);
      End
      Else PostMsgW(I, WM_CLOSE, 0, 0);
      Exit;
    End;
    If ((KeyState[$12] And $80) <> 0) And (VK = 9) Then
    Begin
      For I := 0 To ZCnt - 1 Do
        If IsTaskWin(ZList[I]) And (ZList[I] <> ActiveWin) Then
        Begin
          If Wnds[ZList[I]].Min Then RestoreW(ZList[I])
          Else ActivateW(ZList[I]);
          Exit;
        End;
      Exit;
    End;
    Exit;
  End;
  If W = -2 Then
  Begin
    If (VK = $0D) And (DeskSel >= 0) Then KCommand(DeskCmd[DeskSel]);
    Exit;
  End;
  If Msg <> WM_KEYDOWN Then Exit;
  If Wnds[W].IKind >= ikButton Then
  Begin
    I := TopOf(W);
    If (VK = $0D) And (Wnds[I].IKind = ikDialog) Then
      PostMsgW(I, WM_COMMAND, IDOK, 0)
    Else If (VK = $1B) And (Wnds[I].IKind = ikDialog) Then
      PostMsgW(I, WM_COMMAND, IDCANCEL, 0)
    Else If (Ch <> 0) And (Wnds[W].IKind = ikEdit) Then
      KWndProc(W, WM_CHAR, Ch, 0);
    Exit;
  End;
  Case Wnds[W].IKind Of
    ikMsgBox :
      If VK = $0D Then MsgBoxEnd(W, MbId(Wnds[W].K2, 0))
      Else If VK = $1B Then MsgBoxEnd(W, MbId(Wnds[W].K2,
                                       MbCount(Wnds[W].K2) - 1));
    ikRun :
      If VK = $0D Then DialogAction(W, 0)
      Else If VK = $1B Then DialogAction(W, 1)
      Else If VK = 8 Then
      Begin
        Delete(Wnds[W].KS, Length(Wnds[W].KS), 1);
        KRepaint(W);
      End
      Else If (Ch >= 32) And (Length(Wnds[W].KS) < 30) Then
      Begin
        Wnds[W].KS := Wnds[W].KS + Chr(Ch);
        KRepaint(W);
      End;
    ikShutdown :
      If VK = $0D Then DialogAction(W, 0)
      Else If VK = $1B Then DialogAction(W, 1)
      Else If (VK = $26) Or (VK = $28) Then
      Begin
        If VK = $26 Then Wnds[W].K1 := (Wnds[W].K1 + 2) Mod 3
        Else Wnds[W].K1 := (Wnds[W].K1 + 1) Mod 3;
        KRepaint(W);
      End;
    ikAbout : If (VK = $0D) Or (VK = $1B) Then DestroyW(W);
    ikNotepad : NoteKey(W, VK, Ch);
    ikExplorer :
      If VK = 8 Then ExpUp(W)
      Else If (VK = $0D) And (Wnds[W].K1 >= 0) Then ExpOpenItem(W, Wnds[W].K1);
  End;
End;

Procedure KActivated(W : LongInt);
Begin
  If MenuDepth > 0 Then
    If (W < 0) Or (Wnds[W].IKind <> ikMenu) Then CloseMenus(0);
End;

{ Fond d'une boite de dialogue d'un programme ; ses controles sont
  redessines ensuite }
Procedure PaintDlgBack(W : LongInt);
Var X1, Y1, X2, Y2, I : LongInt;
Begin
  KClient(W, X1, Y1, X2, Y2);
  FBar(X1, Y1, X2, Y2, cSilver);
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And IsChildW(I) And (Wnds[I].Parent = W) Then
      InvalAll(I, True);
End;

{ Dessiner une fenetre interne de premier niveau }
Procedure KPaint(W : LongInt);
Begin
  If Not Wnds[W].Used Or (Wnds[W].Surf.Bits = 0) Then Exit;
  Wnds[W].KNeedPaint := False;
  SetR(Wnds[W].Upd, 0, 0, 0, 0);
  NcPaint(W);
  SetTarget(Wnds[W].Surf, Wnds[W].X, Wnds[W].Y);
  Case Wnds[W].IKind Of
    ikTaskbar : PaintTaskbar(W);
    ikMenu : PaintMenu(W);
    ikMsgBox : PaintMsgBox(W);
    ikExplorer : PaintExplorer(W);
    ikAbout, ikRun, ikShutdown : PaintDialog(W);
    ikHelp : PaintHelp(W);
    ikNotepad : PaintNotepad(W);
    ikDialog : PaintDlgBack(W);
  End;
  DirtyWnd(W);
End;

{ Fenetres internes a repeindre (tache 0) }
Procedure KPaintAll;
Var I : LongInt;
Begin
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And Not IsChildW(I) Then
    Begin
      If Wnds[I].IKind <> ikNone Then
      Begin
        If Wnds[I].KNeedPaint Then KPaint(I);
      End
      Else If Wnds[I].NeedNc Then NcPaint(I);
    End;
  ReadRtc;
  If RtcMin <> LastMinute Then
  Begin
    LastMinute := RtcMin;
    TaskbarChanged;
  End;
End;

{ ------------------------------------------------------------------ }
{ Controles standard (BUTTON, STATIC, EDIT, LISTBOX, SCROLLBAR...)   }
{   Button : K1 etat (coche), K2 enfonce                             }
{   ListBox : Extra = liste de chaines (bloc), K1 nombre, K2 choix   }
{ ------------------------------------------------------------------ }

Const
  BS_TYPEMASK = $F; BS_CHECKBOX = 2; BS_AUTOCHECKBOX = 3; BS_RADIOBUTTON = 4;
  BS_3STATE = 5; BS_GROUPBOX = 7; BS_AUTORADIOBUTTON = 9;
  BM_GETCHECK = $F0; BM_SETCHECK = $F1; BM_GETSTATE = $F2;
  BN_CLICKED = 0;
  LB_ADDSTRING = $180; LB_RESETCONTENT = $184; LB_SETCURSEL = $186;
  LB_GETCURSEL = $188; LB_GETTEXT = $189; LB_GETTEXTLEN = $18A;
  LB_GETCOUNT = $18B;
  CB_ADDSTRING = $143; CB_GETCURSEL = $147; CB_RESETCONTENT = $14B;
  CB_SETCURSEL = $14E;
  LBItemMax = 128;

Procedure DrawCtl(W : LongInt);
Var S : TSurf; OX, OY, X1, Y1, X2, Y2, Typ, I, A : LongInt; Clip : TRect;
    T : String; Fg : LongInt;
Begin
  If Not WndVisible(W) Then Exit;
  If Not WndTarget(W, False, S, OX, OY, Clip) Then Exit;
  SetR(Wnds[W].Upd, 0, 0, 0, 0);
  SetTarget(S, 0, 0);
  ClipX1 := Clip.L; ClipY1 := Clip.T; ClipX2 := Clip.R - 1;
  ClipY2 := Clip.B - 1;
  X1 := OX; Y1 := OY; X2 := OX + Wnds[W].W - 1; Y2 := OY + Wnds[W].H - 1;
  If Wnds[W].Enabled Then Fg := cBlack Else Fg := cGray;
  T := Wnds[W].Text;
  I := Pos('&', T);
  If I > 0 Then Delete(T, I, 1);
  Case Wnds[W].IKind Of
    ikButton :
    Begin
      Typ := Wnds[W].Style And BS_TYPEMASK;
      If Typ = BS_GROUPBOX Then GroupBox(X1, Y1 + 7, X2, Y2, T)
      Else If (Typ = BS_CHECKBOX) Or (Typ = BS_AUTOCHECKBOX) Or
              (Typ = BS_3STATE) Then
      Begin
        FBar(X1, Y1, X2, Y2, cSilver);
        Sunken(X1, (Y1 + Y2) Div 2 - 6, X1 + 12, (Y1 + Y2) Div 2 + 6, cWhite);
        If Wnds[W].K1 <> 0 Then
          For I := 0 To 2 Do
            DLine(X1 + 3, (Y1 + Y2) Div 2 - 1 + I, X1 + 5,
                  (Y1 + Y2) Div 2 + 1 + I, cBlack);
        If Wnds[W].K1 <> 0 Then
          For I := 0 To 2 Do
            DLine(X1 + 5, (Y1 + Y2) Div 2 + 1 + I, X1 + 9,
                  (Y1 + Y2) Div 2 - 3 + I, cBlack);
        OutTxt(X1 + 18, (Y1 + Y2) Div 2 - 8, T, Fg);
      End
      Else If (Typ = BS_RADIOBUTTON) Or (Typ = BS_AUTORADIOBUTTON) Then
      Begin
        FBar(X1, Y1, X2, Y2, cSilver);
        RadioButton(X1, (Y1 + Y2) Div 2 - 7, T, Wnds[W].K1 <> 0);
      End
      Else
        PushButton(X1, Y1, X2, Y2, T, Wnds[W].K2 <> 0,
                   (Wnds[W].Style And 1) <> 0);
    End;
    ikStatic :
    Begin
      Typ := Wnds[W].Style And $1F;
      If (Typ = 7) Or (Typ = 8) Or (Typ = 9) Then
        Edge(X1, Y1, X2, Y2, cGray, cWhite)
      Else If Typ = 3 Then PaintIcon(icApp, X1, Y1, 32)
      Else
      Begin
        FBar(X1, Y1, X2, Y2, cSilver);
        If Typ = 1 Then WrapText(X1 + (Wnds[W].W - TextW(T)) Div 2, Y1,
                                 Wnds[W].W, T, Fg, True)
        Else WrapText(X1, Y1, Wnds[W].W, T, Fg, True);
      End;
    End;
    ikEdit :
    Begin
      Sunken(X1, Y1, X2, Y2, cWhite);
      OutTxt(X1 + 4, Y1 + (Wnds[W].H - 16) Div 2, Fit(T, Wnds[W].W - 8),
             cBlack);
      If W = FocusWin Then
        VLine(X1 + 4 + TextW(T), Y1 + 3, Y2 - 3, cBlack);
    End;
    ikListBox, ikComboBox :
    Begin
      Sunken(X1, Y1, X2, Y2, cWhite);
      A := Wnds[W].Extra;
      For I := 0 To Wnds[W].K1 - 1 Do
        If Y1 + 2 + I * 16 < Y2 - 16 Then
        Begin
          If I = Wnds[W].K2 Then
          Begin
            FBar(X1 + 2, Y1 + 2 + I * 16, X2 - 2, Y1 + 17 + I * 16, cNavy);
            OutTxt(X1 + 4, Y1 + 2 + I * 16, PStr(MemL[0:A + I * 4]), cWhite);
          End
          Else
            OutTxt(X1 + 4, Y1 + 2 + I * 16, PStr(MemL[0:A + I * 4]), cBlack);
        End;
    End;
    ikScrollBar :
    Begin
      FBar(X1, Y1, X2, Y2, cSilver);
      Dither(X1, Y1, X2, Y2, cWhite, 0);
    End;
    ikDialog, ikMdiClient :
      FBar(X1, Y1, X2, Y2, cSilver);
  End;
  DirtyWnd(W);
End;

Procedure LBAdd(W : LongInt; S : String);
Var A : LongInt;
Begin
  If Wnds[W].Extra = 0 Then Wnds[W].Extra := KAlloc(LBItemMax * 4);
  If Wnds[W].K1 >= LBItemMax Then Exit;
  A := KAlloc(Length(S) + 1);
  PutPStr(A, S, 256);
  MemL[0:Wnds[W].Extra + Wnds[W].K1 * 4] := A;
  Inc(Wnds[W].K1);
End;

Procedure LBClear(W : LongInt);
Var I : LongInt;
Begin
  For I := 0 To Wnds[W].K1 - 1 Do KFree(MemL[0:Wnds[W].Extra + I * 4]);
  Wnds[W].K1 := 0; Wnds[W].K2 := -1;
End;

Procedure Notify(W, Code : LongInt);
Begin
  If (Wnds[W].Parent >= 0) Then
    PostMsgW(Wnds[W].Parent, WM_COMMAND, (Code Shl 16) Or
             (Wnds[W].Id And $FFFF), HwndOf(W));
End;

{ Procedure des controles et des fenetres internes }
Function KWndProc(W, Msg, WP, LP : LongInt) : LongInt;
Var Typ, I, N : LongInt; S : String;
Begin
  KWndProc := 0;
  If (Wnds[W].IKind = ikDialog) And (Wnds[W].DlgProc <> 0) And
     Not KillingApp Then
  Begin
    I := CallProc(Wnds[W].DlgProc, HwndOf(W), Msg, WP, LP);
    If I <> 0 Then
    Begin
      If (Msg = WM_CTLCOLORMSGBOX) Or ((Msg > WM_CTLCOLORMSGBOX) And
         (Msg <= WM_CTLCOLORSTATIC)) Or (Msg = WM_INITDIALOG) Then
        KWndProc := I
      Else KWndProc := Wnds[W].DlgResult;
      Exit;
    End;
    If Not Wnds[W].Used Then Exit;
    If Msg = WM_CLOSE Then
    Begin
      PostMsgW(W, WM_COMMAND, IDCANCEL, 0);
      Exit;
    End;
    If Msg = WM_PAINT Then
    Begin
      Wnds[W].KNeedPaint := True;
      Exit;
    End;
  End;
  Case Msg Of
    WM_NCCREATE : KWndProc := 1;
    WM_CREATE :
      If Wnds[W].IKind In [ikListBox, ikComboBox] Then Wnds[W].K2 := -1;
    WM_CLOSE :
      If Not IsChildW(W) Then
      Begin
        If Wnds[W].IKind = ikMsgBox Then MsgBoxEnd(W, IDCANCEL)
        Else If Wnds[W].IKind = ikShutdown Then DialogAction(W, 1)
        Else DestroyW(W);
      End;
    WM_SETTEXT :
    Begin
      Wnds[W].Text := PStr(LP);
      KWndProc := 1;
      If IsChildW(W) Then InvalAll(W, True) Else Wnds[W].NeedNc := True;
    End;
    WM_GETTEXT :
    Begin
      PutPStr(LP, Wnds[W].Text, WP);
      KWndProc := Min(Length(Wnds[W].Text), Max(0, WP - 1));
    End;
    WM_GETTEXTLENGTH : KWndProc := Length(Wnds[W].Text);
    WM_PAINT : If IsChildW(W) Then DrawCtl(W);
    WM_SETFONT : Wnds[W].Font := WP;
    WM_GETFONT : KWndProc := Wnds[W].Font;
    WM_ENABLE : InvalAll(W, True);
    BM_GETCHECK : KWndProc := Wnds[W].K1;
    BM_SETCHECK :
    Begin
      Wnds[W].K1 := WP;
      InvalAll(W, True);
    End;
    BM_GETSTATE : KWndProc := Wnds[W].K1 Or (Wnds[W].K2 Shl 2);
    WM_LBUTTONDOWN :
      If Wnds[W].IKind = ikButton Then
      Begin
        Wnds[W].K2 := 1;
        CaptureWin := W;
        InvalAll(W, True);
      End
      Else If Wnds[W].IKind In [ikListBox, ikComboBox] Then
      Begin
        I := ((LP Shr 16) And $FFFF - 2) Div 16;
        If (I >= 0) And (I < Wnds[W].K1) Then
        Begin
          Wnds[W].K2 := I;
          InvalAll(W, True);
          Notify(W, 1);
        End;
      End;
    WM_LBUTTONUP :
      If (Wnds[W].IKind = ikButton) And (Wnds[W].K2 <> 0) Then
      Begin
        Wnds[W].K2 := 0;
        If CaptureWin = W Then CaptureWin := -1;
        Typ := Wnds[W].Style And BS_TYPEMASK;
        If Typ = BS_AUTOCHECKBOX Then Wnds[W].K1 := 1 - Wnds[W].K1;
        If Typ = BS_AUTORADIOBUTTON Then
        Begin
          For I := 0 To MaxWnd - 1 Do
            If Wnds[I].Used And (Wnds[I].Parent = Wnds[W].Parent) And
               (Wnds[I].IKind = ikButton) And
               ((Wnds[I].Style And BS_TYPEMASK) = BS_AUTORADIOBUTTON) Then
            Begin
              Wnds[I].K1 := 0;
              InvalAll(I, True);
            End;
          Wnds[W].K1 := 1;
        End;
        InvalAll(W, True);
        Notify(W, BN_CLICKED);
      End;
    WM_LBUTTONDBLCLK :
      If Wnds[W].IKind In [ikListBox, ikComboBox] Then Notify(W, 2);
    WM_CHAR :
      If Wnds[W].IKind = ikEdit Then
      Begin
        If WP = 8 Then Delete(Wnds[W].Text, Length(Wnds[W].Text), 1)
        Else If (WP >= 32) And (Length(Wnds[W].Text) < 120) Then
          Wnds[W].Text := Wnds[W].Text + Chr(WP);
        InvalAll(W, True);
        Notify(W, $300);
      End;
    LB_ADDSTRING, CB_ADDSTRING :
    Begin
      LBAdd(W, PStr(LP));
      KWndProc := Wnds[W].K1 - 1;
      InvalAll(W, True);
    End;
    LB_RESETCONTENT, CB_RESETCONTENT :
    Begin
      LBClear(W);
      InvalAll(W, True);
    End;
    LB_SETCURSEL, CB_SETCURSEL :
    Begin
      Wnds[W].K2 := WP;
      InvalAll(W, True);
    End;
    LB_GETCURSEL, CB_GETCURSEL : KWndProc := Wnds[W].K2;
    LB_GETCOUNT, $146 : KWndProc := Wnds[W].K1;
    LB_GETTEXT, $148 :
      If (WP >= 0) And (WP < Wnds[W].K1) Then
      Begin
        S := PStr(MemL[0:Wnds[W].Extra + WP * 4]);
        PutPStr(LP, S, 256);
        KWndProc := Length(S);
      End
      Else KWndProc := -1;
    LB_GETTEXTLEN, $149 :
      If (WP >= 0) And (WP < Wnds[W].K1) Then
        KWndProc := StrLenZ(MemL[0:Wnds[W].Extra + WP * 4])
      Else KWndProc := -1;
  End;
  N := 0;
End;

{ ------------------------------------------------------------------ }
{ Fautes du processeur                                               }
{ ------------------------------------------------------------------ }

Procedure KillApp; Forward;

Procedure KFault(Vec, Frame : LongInt);
Var Eip, Err, V, X : LongInt; Nm, S : String;
Begin
  V := Vec And 255;
  If Vec >= 256 Then
  Begin
    Err := MemL[0:Frame + 36];
    Eip := MemL[0:Frame + 40];
  End
  Else
  Begin
    Err := 0;
    Eip := MemL[0:Frame + 36];
  End;
  Case V Of
    0 : Nm := 'Division par zero';
    6 : Nm := 'Code operation invalide';
    13 : Nm := 'Protection generale';
    14 : Nm := 'Faute de page';
    3 : Nm := 'Point d''arret';
  Else
    Nm := 'Exception ' + IntStr(V);
  End;
  S := Nm + ' EIP=' + HexStr(Eip, 8) + ' ERR=' + HexStr(Err, 4) +
       ' EAX=' + HexStr(MemL[0:Frame + 32], 8) + ' EBX=' +
       HexStr(MemL[0:Frame + 20], 8) + ' ECX=' + HexStr(MemL[0:Frame + 28], 8)
       + ' EDX=' + HexStr(MemL[0:Frame + 24], 8) + ' ESI=' +
       HexStr(MemL[0:Frame + 8], 8) + ' EDI=' + HexStr(MemL[0:Frame + 4], 8)
       + ' EBP=' + HexStr(MemL[0:Frame], 8) + ' ESP=' +
       HexStr(Frame + 40 + 4 * Ord(Vec >= 256), 8);
  KLog('FAUTE (tache ' + IntStr(CurT) + ') ' + S);
  X := Frame + 40 + 4 * Ord(Vec >= 256);
  S := 'Pile :';
  For V := 0 To 11 Do S := S + ' ' + HexStr(MemL[0:X + V * 4], 8);
  KLog(S);
  V := Vec And 255;
  HeapOwner := 0;
  If (CurT > 0) And Threads[CurT].IsApp Then
  Begin
    MsgBoxOpen(L('Erreur', 'Error', 'Fehler', 'Errore', 'Error'), L(
      'Ce programme va '#136'tre arr'#136't'#130' car il a effectu'#130' une '
      + 'op'#130'ration non conforme.',
      'This program has performed an illegal operation and '
      + 'will be shut down.', 'Dieses Programm hat eine ung'#129'ltige ' +
      'Operation durchgef'#129'hrt und wird geschlossen.',
      'Il programma ha eseguito un''operazione non valida e sar'#133' chiuso.',
      'Este programa ha efectuado una operaci'#162'n no v'#160'lida y se ' +
      'apagar'#160'.') + '|' + S, $10);
    KillApp;
    { reprendre la tache 0 (le cadre de la faute est abandonne) }
    Threads[CurT].State := tsDead;
    X := 0;
    SwSave := LongInt(@X);
    SwNew := Threads[0].Esp;
    CurT := 0;
    ThreadSetFs(0);
    SwitchCtx;
  End;
  { faute du noyau : ecran bleu }
  CursorErase;
  SetTarget(Back, 0, 0);
  FBar(0, 0, ScrW - 1, ScrH - 1, cNavy);
  OutBold(232, 120, ' Pasdows 95 ', cNavy);
  FBar(230, 118, 330, 136, cSilver);
  OutBold(234, 120, 'Pasdows', cNavy);
  WrapText(40, 170, 560, L('Une erreur fatale s''est produite dans ' +
           'VMM32.VXD. Le syst'#138'me est arr'#136't'#130'.',
           'A fatal exception has occurred in VMM32.VXD. The system is ' +
           'halted.', 'Ein schwerer Ausnahmefehler ist in VMM32.VXD ' +
           'aufgetreten.', 'Errore irreversibile in VMM32.VXD.',
           'Error grave en VMM32.VXD.'), cWhite, True);
  WrapText(40, 230, 560, S, cWhite, True);
  SetR(Dirty, 0, 0, ScrW, ScrH);
  LfbCopy(Dirty);
  HaltCpu;
End;

{ ==================================================================== }
{ Partie 8 - API Win32 KERNEL32                                        }
{ ==================================================================== }

Const
  INVALID_HANDLE = -1;
  HStdIn = $10; HStdOut = $11; HStdErr = $12;
  MaxVBlk = 64;

Type
  TVBlk = Record
    Used : Boolean;
    Base, Size, Orig : LongInt;
  End;

  TAtom = Record
    Used : Boolean;
    Name : String[63];
    Refs : LongInt;
  End;

Var
  { programme Win32 en cours }
  AppBase, AppSize, AppEntry : LongInt;
  AppPath    : String[127];
  AppCmd     : LongInt;     { ligne de commande ASCIIZ }
  AppEnv     : LongInt;     { bloc d'environnement }
  AppStdOut  : LongInt;
  AppErrMode : LongInt;
  AppExcFilter : LongInt;
  VBlks      : Array[0..MaxVBlk - 1] Of TVBlk;
  Atoms      : Array[0..MaxAtom - 1] Of TAtom;
  EnvBlk     : Array[0..4095] Of Byte;
  EnvLen     : LongInt;

Procedure SetErr(E : LongInt);
Begin
  Threads[CurT].LastErr := E;
End;

{ ------------------------------------------------------------------ }
{ Environnement (recopie par IO.SYS en 00003000h)                    }
{ ------------------------------------------------------------------ }

Procedure LoadEnvironment;
Var A, N : LongInt;
Begin
  A := MemL[0:BootInfo + $2C];
  N := 0;
  If A <> 0 Then
    While (N < 4090) And Not ((Mem[0:A + N] = 0) And
          ((N = 0) Or (Mem[0:A + N - 1] = 0))) Do
    Begin
      EnvBlk[N] := Mem[0:A + N];
      Inc(N);
    End;
  If N = 0 Then
  Begin
    PutPStr(LongInt(@EnvBlk), 'PATH=D:\', 64);
    N := 9;
  End;
  EnvBlk[N] := 0; EnvBlk[N + 1] := 0;
  EnvLen := N;
End;

Function EnvFind(Name : String; Var Vs : LongInt) : Boolean;
Var A, P : LongInt; U : String;
Begin
  EnvFind := False;
  U := UpStr(Name) + '=';
  A := LongInt(@EnvBlk);
  P := 0;
  While (P < EnvLen) And (EnvBlk[P] <> 0) Do
  Begin
    If UpStr(Copy(PStr(A + P), 1, Length(U))) = U Then
    Begin
      Vs := A + P + Length(U);
      EnvFind := True;
      Exit;
    End;
    While EnvBlk[P] <> 0 Do Inc(P);
    Inc(P);
  End;
End;

Procedure EnvSet(Name, Value : String);
Var A, P, Q, N : LongInt; U, S : String;
Begin
  U := UpStr(Name) + '=';
  A := LongInt(@EnvBlk);
  P := 0;
  While (P < EnvLen) And (EnvBlk[P] <> 0) Do
  Begin
    If UpStr(Copy(PStr(A + P), 1, Length(U))) = U Then
    Begin
      Q := P;
      While EnvBlk[Q] <> 0 Do Inc(Q);
      Inc(Q);
      N := EnvLen + 1 - Q;
      MoveMem(A + Q, A + P, N + 1);
      EnvLen := EnvLen - (Q - P);
      Break;
    End;
    While EnvBlk[P] <> 0 Do Inc(P);
    Inc(P);
  End;
  If Value = '' Then Exit;
  S := UpStr(Name) + '=' + Value;
  If EnvLen + Length(S) + 2 >= 4090 Then Exit;
  PutPStr(A + EnvLen, S, 256);
  EnvLen := EnvLen + Length(S) + 1;
  EnvBlk[EnvLen] := 0;
End;

Function GetEnvironmentVariableA(Name, Buf, Size : LongInt) : LongInt;
Var V : LongInt; S : String;
Begin
  GetEnvironmentVariableA := 0;
  If Not EnvFind(PStr(Name), V) Then
  Begin
    SetErr(203);
    Exit;
  End;
  S := PStr(V);
  If Size > Length(S) Then
  Begin
    PutPStr(Buf, S, Size);
    GetEnvironmentVariableA := Length(S);
  End
  Else GetEnvironmentVariableA := Length(S) + 1;
End;

Function SetEnvironmentVariableA(Name, Value : LongInt) : LongInt;
Begin
  If Value = 0 Then EnvSet(PStr(Name), '') Else EnvSet(PStr(Name), PStr(Value));
  SetEnvironmentVariableA := 1;
End;

Function GetEnvironmentStrings : LongInt;
Begin
  GetEnvironmentStrings := LongInt(@EnvBlk);
End;

Function GetEnvironmentStringsA : LongInt;
Begin
  GetEnvironmentStringsA := LongInt(@EnvBlk);
End;

Function FreeEnvironmentStringsA(P : LongInt) : LongInt;
Begin
  FreeEnvironmentStringsA := 1;
End;

{ ------------------------------------------------------------------ }
{ Processus, version, systeme                                        }
{ ------------------------------------------------------------------ }

Function GetVersion : LongInt;
Begin
  GetVersion := LongInt($C3B60004);
End;

Function GetVersionExA(P : LongInt) : LongInt;
Begin
  MemL[0:P + 4] := 4;
  MemL[0:P + 8] := 0;
  MemL[0:P + 12] := $040003B6;
  MemL[0:P + 16] := 1;
  Mem[0:P + 20] := 0;
  GetVersionExA := 1;
End;

Procedure GetSystemInfo(P : LongInt);
Begin
  FillMem(P, 36, 0);
  MemL[0:P + 4] := 4096;
  MemL[0:P + 8] := $10000;
  MemL[0:P + 12] := $7FFEFFFF;
  MemL[0:P + 16] := 1;
  MemL[0:P + 20] := 1;
  MemL[0:P + 24] := 586;
  MemL[0:P + 28] := 65536;
  MemW[0:P + 32] := 5;
End;

Function GetCommandLineA : LongInt;
Begin
  GetCommandLineA := AppCmd;
End;

Procedure GetStartupInfoA(P : LongInt);
Begin
  FillMem(P, 68, 0);
  MemL[0:P] := 68;
  MemW[0:P + 48] := 1;
End;

Function GetStdHandle(N : LongInt) : LongInt;
Begin
  Case N Of
    -10 : GetStdHandle := HStdIn;
    -11 : GetStdHandle := HStdOut;
    -12 : GetStdHandle := HStdErr;
  Else
    GetStdHandle := INVALID_HANDLE;
  End;
End;

Function SetStdHandle(N, H : LongInt) : LongInt;
Begin
  SetStdHandle := 1;
End;

Function GetLastError : LongInt;
Begin
  GetLastError := Threads[CurT].LastErr;
End;

Procedure SetLastError(E : LongInt);
Begin
  Threads[CurT].LastErr := E;
End;

Function SetErrorMode(M : LongInt) : LongInt;
Begin
  SetErrorMode := AppErrMode;
  AppErrMode := M;
End;

Procedure OutputDebugStringA(S : LongInt);
Begin
  KLog('ODS: ' + PStr(S));
End;

Function SetUnhandledExceptionFilter(F : LongInt) : LongInt;
Begin
  SetUnhandledExceptionFilter := AppExcFilter;
  If CurT > 0 Then AppExcFilter := F;
End;

Function UnhandledExceptionFilter(P : LongInt) : LongInt;
Begin
  UnhandledExceptionFilter := 1;
End;

Function GetCurrentProcess : LongInt;
Begin
  GetCurrentProcess := -1;
End;

Function GetCurrentProcessId : LongInt;
Begin
  GetCurrentProcessId := $50;
End;

Function GetCurrentThread : LongInt;
Begin
  GetCurrentThread := -2;
End;

Function GetCurrentThreadId : LongInt;
Begin
  GetCurrentThreadId := ThreadId(CurT);
End;

Procedure ExitProcessK(Code : LongInt); Forward;

Procedure ExitProcess(Code : LongInt);
Begin
  ExitProcessK(Code);
End;

Function TerminateProcess(H, Code : LongInt) : LongInt;
Begin
  ExitProcessK(Code);
  TerminateProcess := 1;
End;

Procedure RaiseException(Code, Flags, N, Args : LongInt); Forward;

Procedure RtlUnwind(Frame, Ip, Rec, Ret : LongInt); Forward;

Function WinExec(Cmd, Show : LongInt) : LongInt;
Var S, A : String; P : LongInt;
Begin
  S := Trim(PStr(Cmd));
  P := Pos(' ', S);
  If P > 0 Then
  Begin
    A := Copy(S, P + 1, 255);
    S := Copy(S, 1, P - 1);
  End
  Else A := '';
  If RunExe(S, A) Then WinExec := 33 Else WinExec := 2;
End;

{ ------------------------------------------------------------------ }
{ Temps                                                              }
{ ------------------------------------------------------------------ }

Function GetTickCount : LongInt;
Begin
  GetTickCount := Ticks;
End;

Procedure Sleep(Ms : LongInt);
Begin
  If Ms <= 0 Then KYield Else KSleep(Ms);
End;

Function DaysFrom1601(Y, M, D : LongInt) : LongInt;
Const Cum : Array[1..12] Of LongInt = (0, 31, 59, 90, 120, 151, 181, 212,
                                       243, 273, 304, 334);
Var N, Y1 : LongInt;
Begin
  Y1 := Y - 1601;
  N := Y1 * 365 + Y1 Div 4 - Y1 Div 100 + Y1 Div 400;
  N := N + Cum[M] + D - 1;
  If (M > 2) And ((Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or (Y Mod 400 = 0)))
  Then Inc(N);
  DaysFrom1601 := N;
End;

{ Date DOS -> FILETIME (centaines de ns depuis 1601) }
Procedure DosToFileTime(Dos, P : LongInt);
Var Y, M, D, H, Mi, S : LongInt; Sec, FT, HiR, LoR : Real;
Begin
  Y := ((Dos Shr 25) And 127) + 1980; M := (Dos Shr 21) And 15;
  D := (Dos Shr 16) And 31;
  H := (Dos Shr 11) And 31; Mi := (Dos Shr 5) And 63; S := (Dos And 31) * 2;
  If (M < 1) Or (M > 12) Then M := 1;
  If D < 1 Then D := 1;
  Sec := DaysFrom1601(Y, M, D) * 86400.0 + H * 3600.0 + Mi * 60.0 + S;
  FT := Sec * 78125.0 * 128.0;
  HiR := Int(FT / 4294967296.0);
  LoR := FT - HiR * 4294967296.0;
  If LoR >= 2147483648.0 Then LoR := LoR - 4294967296.0;
  MemL[0:P] := Trunc(LoR);
  MemL[0:P + 4] := Trunc(HiR);
End;

{ FILETIME -> SYSTEMTIME }
Function FileTimeToSystemTime(Ft, St : LongInt) : LongInt;
Var FT2, LoR, Sec : Real; Days, Rem, Y, M, Dim : LongInt;
Begin
  LoR := MemL[0:Ft];
  If LoR < 0 Then LoR := LoR + 4294967296.0;
  FT2 := MemL[0:Ft + 4] * 4294967296.0 + LoR;
  Sec := Int(FT2 / 10000000.0);
  Days := Trunc(Int(Sec / 86400.0));
  Rem := Trunc(Sec - Days * 86400.0);
  Y := 1601;
  While Days >= 365 + Ord((Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or
        (Y Mod 400 = 0))) Do
  Begin
    Days := Days - 365 - Ord((Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or
            (Y Mod 400 = 0)));
    Inc(Y);
  End;
  M := 1;
  Repeat
    Case M Of
      4, 6, 9, 11 : Dim := 30;
      2 : If (Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or (Y Mod 400 = 0)) Then
            Dim := 29 Else Dim := 28;
    Else
      Dim := 31;
    End;
    If Days >= Dim Then
    Begin
      Days := Days - Dim;
      Inc(M);
    End
    Else Break;
  Until M > 12;
  MemW[0:St] := Y; MemW[0:St + 2] := M;
  MemW[0:St + 4] := DayOfWeek(Y, M, Days + 1);
  MemW[0:St + 6] := Days + 1;
  MemW[0:St + 8] := Rem Div 3600; MemW[0:St + 10] := (Rem Div 60) Mod 60;
  MemW[0:St + 12] := Rem Mod 60; MemW[0:St + 14] := 0;
  FileTimeToSystemTime := 1;
End;

Function FileTimeToLocalFileTime(Src, Dst : LongInt) : LongInt;
Begin
  MemL[0:Dst] := MemL[0:Src];
  MemL[0:Dst + 4] := MemL[0:Src + 4];
  FileTimeToLocalFileTime := 1;
End;

Function LocalFileTimeToFileTime(Src, Dst : LongInt) : LongInt;
Begin
  LocalFileTimeToFileTime := FileTimeToLocalFileTime(Src, Dst);
End;

Function FileTimeToDosDateTime(Ft, PDate, PTime : LongInt) : LongInt;
Var St : Array[0..7] Of Word;
Begin
  FileTimeToSystemTime(Ft, LongInt(@St));
  If PDate <> 0 Then
    MemW[0:PDate] := ((St[0] - 1980) Shl 9) Or (St[1] Shl 5) Or St[3];
  If PTime <> 0 Then
    MemW[0:PTime] := (St[4] Shl 11) Or (St[5] Shl 5) Or (St[6] Div 2);
  FileTimeToDosDateTime := 1;
End;

Function DosDateTimeToFileTime(DDate, DTime, Ft : LongInt) : LongInt;
Begin
  DosToFileTime(((DDate And $FFFF) Shl 16) Or (DTime And $FFFF), Ft);
  DosDateTimeToFileTime := 1;
End;

Procedure GetLocalTime(P : LongInt);
Begin
  ReadRtc;
  MemW[0:P] := RtcYear; MemW[0:P + 2] := RtcMonth;
  MemW[0:P + 4] := DayOfWeek(RtcYear, RtcMonth, RtcDay);
  MemW[0:P + 6] := RtcDay; MemW[0:P + 8] := RtcHour;
  MemW[0:P + 10] := RtcMin; MemW[0:P + 12] := RtcSec;
  MemW[0:P + 14] := Ticks Mod 1000;
End;

Procedure GetSystemTime(P : LongInt);
Begin
  GetLocalTime(P);
End;

Function GetTimeZoneInformation(P : LongInt) : LongInt;
Begin
  FillMem(P, 172, 0);
  GetTimeZoneInformation := 0;
End;

{ ------------------------------------------------------------------ }
{ Fichiers                                                           }
{ ------------------------------------------------------------------ }

Function IsConsoleH(H : LongInt) : Boolean;
Begin
  IsConsoleH := (H = HStdIn) Or (H = HStdOut) Or (H = HStdErr);
End;

{ Ouvrir un fichier ; Disp : 1 CREATE_NEW 2 CREATE_ALWAYS 3 OPEN_EXISTING
  4 OPEN_ALWAYS 5 TRUNCATE_EXISTING ; poignee ou -1 }
Function KOpenFile(Name : String; Wr : Boolean; Disp : LongInt) : LongInt;
Var Path : String; Attr, Size, Time, Lba, Ram, I : LongInt; Ex : Boolean;
Begin
  KOpenFile := INVALID_HANDLE;
  If (UpStr(Name) = 'CON') Or (UpStr(Name) = 'CONOUT$') Then
  Begin
    KOpenFile := HStdOut;
    Exit;
  End;
  If (UpStr(Name) = 'NUL') Then Name := 'C:\NUL';
  Path := FullPath(Name);
  Ex := PathInfo(Path, Attr, Size, Time, Lba, Ram);
  If ApiTrace Then KLog('Fichier : ' + Path + ' existe=' + IntStr(Ord(Ex)));
  If Ex And ((Attr And $10) <> 0) Then
  Begin
    SetErr(ErrAccessDenied);
    Exit;
  End;
  If (Disp = 1) And Ex Then
  Begin
    SetErr(80);
    Exit;
  End;
  If ((Disp = 3) Or (Disp = 5)) And Not Ex Then
  Begin
    SetErr(ErrFileNotFound);
    Exit;
  End;
  If Wr Or (Disp = 1) Or (Disp = 2) Then
  Begin
    If Copy(Path, 1, 2) = 'D:' Then
    Begin
      SetErr(ErrAccessDenied);
      Exit;
    End;
    If Not IsCDir(ParentDir(Path)) Then
    Begin
      SetErr(ErrPathNotFound);
      Exit;
    End;
    If Ram < 0 Then
    Begin
      Ram := RamNew(Path);
      If Ram < 0 Then
      Begin
        SetErr(4);
        Exit;
      End;
    End;
    If (Disp = 2) Or (Disp = 5) Then RamFiles[Ram].Size := 0;
    Lba := -1;
  End
  Else If Not Ex Then
  Begin
    If Disp = 4 Then
    Begin
      SetErr(ErrAccessDenied);
      Exit;
    End;
    SetErr(ErrFileNotFound);
    Exit;
  End;
  I := KObjNew(koFile);
  If I < 0 Then
  Begin
    SetErr(4);
    Exit;
  End;
  KObjs[I].F1 := Lba;
  If Ram >= 0 Then KObjs[I].F2 := RamFiles[Ram].Size Else KObjs[I].F2 := Size;
  KObjs[I].F3 := 0;
  KObjs[I].F4 := Ram;
  KObjs[I].F5 := Ord(Wr);
  KObjs[I].F6 := Time;
  KObjs[I].Name := Path;
  SetErr(0);
  KOpenFile := KHandle(I);
End;

Function CreateFileA(PName, Access, Share, Sec, Disp, Flags, Templ : LongInt)
  : LongInt;
Begin
  CreateFileA := KOpenFile(PStr(PName), (Access And $40000000) <> 0, Disp);
End;

Function CloseHandle(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  CloseHandle := 1;
  If IsConsoleH(H) Then Exit;
  I := KObjOf(H, 0);
  If I < 0 Then
  Begin
    CloseHandle := 0;
    SetErr(ErrInvalidHandle);
    Exit;
  End;
  If KObjs[I].Kind = koThread Then
  Begin
    { la tache continue ; l'objet sera libere a sa fin }
    If (KObjs[I].F1 >= 0) And Threads[KObjs[I].F1].Used Then Exit;
  End;
  KObjs[I].Used := False;
End;

Function KReadFile(H, Buf, N : LongInt; Var Got : LongInt) : Boolean;
Var I, R : LongInt;
Begin
  KReadFile := False; Got := 0;
  I := KObjOf(H, koFile);
  If I < 0 Then
  Begin
    SetErr(ErrInvalidHandle);
    Exit;
  End;
  If N < 0 Then N := 0;
  If KObjs[I].F3 + N > KObjs[I].F2 Then N := KObjs[I].F2 - KObjs[I].F3;
  If N < 0 Then N := 0;
  R := KObjs[I].F4;
  If R >= 0 Then MoveMem(RamFiles[R].Data + KObjs[I].F3, Buf, N)
  Else If N > 0 Then
    If Not CdReadBytes(KObjs[I].F1, KObjs[I].F3, N, Buf) Then
    Begin
      SetErr(30);
      Exit;
    End;
  KObjs[I].F3 := KObjs[I].F3 + N;
  Got := N;
  KReadFile := True;
End;

Function ReadFile(H, Buf, N, PRead, Ovl : LongInt) : LongInt;
Var Got : LongInt;
Begin
  ReadFile := Ord(KReadFile(H, Buf, N, Got));
  If PRead <> 0 Then MemL[0:PRead] := Got;
End;

Function KWriteFile(H, Buf, N : LongInt) : LongInt;
Var I, R, E : LongInt; S : String;
Begin
  KWriteFile := -1;
  If IsConsoleH(H) Then
  Begin
    S := '';
    For I := 0 To Min(N, 200) - 1 Do
      If Mem[0:Buf + I] >= 32 Then S := S + Chr(Mem[0:Buf + I]);
    KLog('CON: ' + S);
    KWriteFile := N;
    Exit;
  End;
  I := KObjOf(H, koFile);
  If (I < 0) Or (KObjs[I].F4 < 0) Then
  Begin
    SetErr(ErrAccessDenied);
    Exit;
  End;
  R := KObjs[I].F4;
  E := KObjs[I].F3 + N;
  If Not RamReserve(R, E) Then
  Begin
    SetErr(112);
    Exit;
  End;
  If KObjs[I].F3 > RamFiles[R].Size Then
    FillMem(RamFiles[R].Data + RamFiles[R].Size, KObjs[I].F3 -
            RamFiles[R].Size, 0);
  MoveMem(Buf, RamFiles[R].Data + KObjs[I].F3, N);
  KObjs[I].F3 := E;
  If E > RamFiles[R].Size Then RamFiles[R].Size := E;
  KObjs[I].F2 := RamFiles[R].Size;
  RamFiles[R].Time := DosNow;
  KWriteFile := N;
End;

Function WriteFile(H, Buf, N, PWritten, Ovl : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := KWriteFile(H, Buf, N);
  If PWritten <> 0 Then MemL[0:PWritten] := Max(R, 0);
  WriteFile := Ord(R >= 0);
End;

Function SetFilePointer(H, Dist, PHigh, Method : LongInt) : LongInt;
Var I, P : LongInt;
Begin
  SetFilePointer := -1;
  I := KObjOf(H, koFile);
  If I < 0 Then
  Begin
    SetErr(ErrInvalidHandle);
    Exit;
  End;
  Case Method Of
    0 : P := Dist;
    1 : P := KObjs[I].F3 + Dist;
  Else
    P := KObjs[I].F2 + Dist;
  End;
  If P < 0 Then
  Begin
    SetErr(131);
    Exit;
  End;
  KObjs[I].F3 := P;
  If PHigh <> 0 Then MemL[0:PHigh] := 0;
  SetFilePointer := P;
End;

Function GetFileSize(H, PHigh : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koFile);
  If PHigh <> 0 Then MemL[0:PHigh] := 0;
  If I < 0 Then GetFileSize := -1 Else GetFileSize := KObjs[I].F2;
End;

Function SetEndOfFile(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  SetEndOfFile := 0;
  I := KObjOf(H, koFile);
  If (I < 0) Or (KObjs[I].F4 < 0) Then Exit;
  RamFiles[KObjs[I].F4].Size := KObjs[I].F3;
  KObjs[I].F2 := KObjs[I].F3;
  SetEndOfFile := 1;
End;

Function FlushFileBuffers(H : LongInt) : LongInt;
Begin
  FlushFileBuffers := 1;
End;

Function GetFileType(H : LongInt) : LongInt;
Begin
  If IsConsoleH(H) Then GetFileType := 2
  Else If KObjOf(H, koFile) >= 0 Then GetFileType := 1
  Else GetFileType := 0;
End;

Function GetFileTime(H, PC, PA, PW : LongInt) : LongInt;
Var I : LongInt;
Begin
  GetFileTime := 0;
  I := KObjOf(H, koFile);
  If I < 0 Then Exit;
  If PC <> 0 Then DosToFileTime(KObjs[I].F6, PC);
  If PA <> 0 Then DosToFileTime(KObjs[I].F6, PA);
  If PW <> 0 Then DosToFileTime(KObjs[I].F6, PW);
  GetFileTime := 1;
End;

Function GetFileAttributesA(PName : LongInt) : LongInt;
Var Attr, Size, Time, Lba, Ram : LongInt;
Begin
  If PathInfo(FullPath(PStr(PName)), Attr, Size, Time, Lba, Ram) Then
  Begin
    If Attr = 0 Then Attr := $80;
    GetFileAttributesA := Attr;
  End
  Else
  Begin
    SetErr(ErrFileNotFound);
    GetFileAttributesA := -1;
  End;
End;

Function SetFileAttributesA(PName, Attr : LongInt) : LongInt;
Begin
  SetFileAttributesA := 1;
End;

Function DeleteFileA(PName : LongInt) : LongInt;
Var R : LongInt;
Begin
  DeleteFileA := 0;
  R := RamFind(FullPath(PStr(PName)));
  If R < 0 Then
  Begin
    SetErr(ErrFileNotFound);
    Exit;
  End;
  If RamFiles[R].Data <> 0 Then KFree(RamFiles[R].Data);
  RamFiles[R].Used := False;
  DeleteFileA := 1;
End;

Function MoveFileA(PSrc, PDst : LongInt) : LongInt;
Var R : LongInt;
Begin
  MoveFileA := 0;
  R := RamFind(FullPath(PStr(PSrc)));
  If R < 0 Then
  Begin
    SetErr(ErrAccessDenied);
    Exit;
  End;
  RamFiles[R].Path := FullPath(PStr(PDst));
  MoveFileA := 1;
End;

Function GetFullPathNameA(PName, N, Buf, PFile : LongInt) : LongInt;
Var S : String; P : LongInt;
Begin
  S := FullPath(PStr(PName));
  If N > Length(S) Then
  Begin
    PutPStr(Buf, S, N);
    If PFile <> 0 Then
    Begin
      P := Length(S);
      While (P > 0) And (S[P] <> '\') Do Dec(P);
      MemL[0:PFile] := Buf + P;
    End;
    GetFullPathNameA := Length(S);
  End
  Else GetFullPathNameA := Length(S) + 1;
End;

Function GetCurrentDirectoryA(N, Buf : LongInt) : LongInt;
Var S : String;
Begin
  S := CurDirS;
  If Length(S) = 2 Then S := S + '\';
  If N > Length(S) Then
  Begin
    PutPStr(Buf, S, N);
    GetCurrentDirectoryA := Length(S);
  End
  Else GetCurrentDirectoryA := Length(S) + 1;
End;

Function SetCurrentDirectoryA(PName : LongInt) : LongInt;
Var S : String; Attr, Size, Time, Lba, Ram : LongInt;
Begin
  SetCurrentDirectoryA := 0;
  S := FullPath(PStr(PName));
  If Not PathInfo(S, Attr, Size, Time, Lba, Ram) Or ((Attr And $10) = 0)
  Then
  Begin
    SetErr(ErrPathNotFound);
    Exit;
  End;
  If (Length(S) = 3) Then S := Copy(S, 1, 2);
  CurDirS := S;
  SetCurrentDirectoryA := 1;
End;

Function GetDiskFreeSpaceA(PRoot, PSpc, PBps, PFree, PTotal : LongInt)
  : LongInt;
Begin
  If PSpc <> 0 Then MemL[0:PSpc] := 8;
  If PBps <> 0 Then MemL[0:PBps] := 512;
  If PFree <> 0 Then MemL[0:PFree] := HeapFreeBytes Div 4096;
  If PTotal <> 0 Then MemL[0:PTotal] := (MemTop Div 4096);
  GetDiskFreeSpaceA := 1;
End;

Function GetDriveTypeA(PRoot : LongInt) : LongInt;
Var S : String;
Begin
  If PRoot = 0 Then S := CurDirS Else S := UpStr(PStr(PRoot));
  If S = '' Then S := CurDirS;
  Case S[1] Of
    'C' : GetDriveTypeA := 3;
    'D' : GetDriveTypeA := 5;
  Else
    GetDriveTypeA := 1;
  End;
End;

Function GetLogicalDrives : LongInt;
Begin
  GetLogicalDrives := 12;
End;

Function GetWindowsDirectoryA(Buf, N : LongInt) : LongInt;
Begin
  PutPStr(Buf, 'C:\WINDOWS', N);
  GetWindowsDirectoryA := 10;
End;

Function GetSystemDirectoryA(Buf, N : LongInt) : LongInt;
Begin
  PutPStr(Buf, 'C:\WINDOWS\SYSTEM', N);
  GetSystemDirectoryA := 17;
End;

Function GetTempPathA(N, Buf : LongInt) : LongInt;
Begin
  PutPStr(Buf, 'C:\TEMP\', N);
  GetTempPathA := 8;
End;

Function GetVolumeInformationA(PRoot, PVol, VolSize, PSerial, PMaxComp,
  PFlags, PFs, FsSize : LongInt) : LongInt;
Begin
  If PVol <> 0 Then PutPStr(PVol, VolLabel, VolSize);
  If PSerial <> 0 Then MemL[0:PSerial] := $19950824;
  If PMaxComp <> 0 Then MemL[0:PMaxComp] := 12;
  If PFlags <> 0 Then MemL[0:PFlags] := 0;
  If PFs <> 0 Then PutPStr(PFs, 'CDFS', FsSize);
  GetVolumeInformationA := 1;
End;

{ Recherche : F1 position, F2 0 = CD, 1 = disque virtuel ; Name chemin
  du repertoire, Mask masque }
Function FindStep(I, P : LongInt) : Boolean;
Var Nm : String; Lba, Size, Fl, Tm, DL, DS, Attr, R : LongInt;
Begin
  FindStep := False;
  If KObjs[I].F2 = 0 Then
  Begin
    If Copy(KObjs[I].Name, 1, 2) = 'D:' Then
      If IsoLookup(Copy(KObjs[I].Name, 3, 255), DL, DS, Fl, Tm) Then
        While IsoDirEntry(DL, DS, KObjs[I].F1, Nm, Lba, Size, Fl, Tm) Do
        Begin
          Inc(KObjs[I].F1);
          If MatchMask(Nm, KObjs[I].Mask) Then
          Begin
            FillMem(P, 318, 0);
            If (Fl And 2) <> 0 Then Attr := $11 Else Attr := $21;
            MemL[0:P] := Attr;
            DosToFileTime(Tm, P + 4);
            DosToFileTime(Tm, P + 12);
            DosToFileTime(Tm, P + 20);
            MemL[0:P + 32] := Size;
            PutPStr(P + 44, Nm, 260);
            PutPStr(P + 304, Nm, 14);
            FindStep := True;
            Exit;
          End;
        End;
    KObjs[I].F2 := 1;
    KObjs[I].F1 := 0;
  End;
  While KObjs[I].F1 < MaxRam Do
  Begin
    R := KObjs[I].F1;
    Inc(KObjs[I].F1);
    If RamFiles[R].Used And (ParentDir(RamFiles[R].Path) = KObjs[I].Name)
       And MatchMask(BaseName(RamFiles[R].Path), KObjs[I].Mask) Then
    Begin
      FillMem(P, 318, 0);
      MemL[0:P] := RamFiles[R].Attr;
      DosToFileTime(RamFiles[R].Time, P + 20);
      MemL[0:P + 32] := RamFiles[R].Size;
      PutPStr(P + 44, BaseName(RamFiles[R].Path), 260);
      FindStep := True;
      Exit;
    End;
  End;
End;

Function FindFirstFileA(PName, P : LongInt) : LongInt;
Var I : LongInt; S : String;
Begin
  FindFirstFileA := INVALID_HANDLE;
  I := KObjNew(koFind);
  If I < 0 Then Exit;
  S := FullPath(PStr(PName));
  KObjs[I].Name := ParentDir(S);
  If Length(KObjs[I].Name) = 3 Then
    KObjs[I].Name := Copy(KObjs[I].Name, 1, 3);
  KObjs[I].Mask := Copy(BaseName(S), 1, 15);
  If Length(KObjs[I].Name) = 3 Then
    KObjs[I].Name := Copy(KObjs[I].Name, 1, 2) + '\';
  If KObjs[I].Name = 'D:\' Then KObjs[I].Name := 'D:';
  If FindStep(I, P) Then FindFirstFileA := KHandle(I)
  Else
  Begin
    KObjs[I].Used := False;
    SetErr(ErrFileNotFound);
  End;
End;

Function FindNextFileA(H, P : LongInt) : LongInt;
Var I : LongInt;
Begin
  FindNextFileA := 0;
  I := KObjOf(H, koFind);
  If I < 0 Then Exit;
  If FindStep(I, P) Then FindNextFileA := 1 Else SetErr(ErrNoMoreFiles);
End;

Function FindClose(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koFind);
  If I >= 0 Then KObjs[I].Used := False;
  FindClose := 1;
End;

{ Fonctions de fichiers 16 bits (_lopen...) }
Function _lopen(PName, Mode : LongInt) : LongInt;
Begin
  _lopen := KOpenFile(PStr(PName), (Mode And 3) <> 0, 3);
End;

Function _lcreat(PName, Attr : LongInt) : LongInt;
Begin
  _lcreat := KOpenFile(PStr(PName), True, 2);
End;

Function _lclose(H : LongInt) : LongInt;
Begin
  CloseHandle(H);
  _lclose := 0;
End;

Function _lread(H, Buf, N : LongInt) : LongInt;
Var Got : LongInt;
Begin
  If KReadFile(H, Buf, N, Got) Then _lread := Got Else _lread := -1;
End;

Function _hread(H, Buf, N : LongInt) : LongInt;
Begin
  _hread := _lread(H, Buf, N);
End;

Function _lwrite(H, Buf, N : LongInt) : LongInt;
Begin
  _lwrite := KWriteFile(H, Buf, N);
End;

Function _hwrite(H, Buf, N : LongInt) : LongInt;
Begin
  _hwrite := KWriteFile(H, Buf, N);
End;

Function _llseek(H, Ofs, Org : LongInt) : LongInt;
Begin
  _llseek := SetFilePointer(H, Ofs, 0, Org);
End;

{ OpenFile (OFSTRUCT : +0 taille, +2 disque fixe, +4 erreur,
  +8 chemin) }
Function OpenFile(PName, POf, Style : LongInt) : LongInt;
Var S : String; Attr, Size, Time, Lba, Ram, H : LongInt;
Begin
  OpenFile := -1;
  S := FullPath(PStr(PName));
  If POf <> 0 Then
  Begin
    Mem[0:POf] := 136; Mem[0:POf + 1] := 0;
    MemW[0:POf + 2] := 0;
    PutPStr(POf + 8, S, 128);
  End;
  If (Style And $100) <> 0 Then
  Begin
    OpenFile := 0;
    Exit;
  End;
  If (Style And $4000) <> 0 Then
  Begin
    If PathInfo(S, Attr, Size, Time, Lba, Ram) Then OpenFile := 1
    Else If POf <> 0 Then MemW[0:POf + 2] := ErrFileNotFound;
    Exit;
  End;
  If (Style And $200) <> 0 Then
  Begin
    OpenFile := DeleteFileA(PName);
    Exit;
  End;
  If (Style And $1000) <> 0 Then H := KOpenFile(S, True, 2)
  Else H := KOpenFile(S, (Style And 3) <> 0, 3);
  If (H = -1) And (POf <> 0) Then MemW[0:POf + 2] := GetLastError;
  OpenFile := H;
End;

{ ------------------------------------------------------------------ }
{ Memoire                                                            }
{ ------------------------------------------------------------------ }

Function GetProcessHeap : LongInt;
Begin
  GetProcessHeap := $00010001;
End;

Function HeapCreate(Opt, Init, Mx : LongInt) : LongInt;
Begin
  HeapCreate := $00010002;
End;

Function HeapDestroy(H : LongInt) : LongInt;
Begin
  HeapDestroy := 1;
End;

Function HeapAlloc(Heap, Flags, Size : LongInt) : LongInt;
Begin
  HeapAlloc := KAlloc(Size);
End;

Function HeapFree(Heap, Flags, A : LongInt) : LongInt;
Begin
  KFree(A);
  HeapFree := 1;
End;

Function HeapReAlloc(Heap, Flags, A, Size : LongInt) : LongInt;
Begin
  HeapReAlloc := KRealloc(A, Size);
End;

Function HeapSize(Heap, Flags, A : LongInt) : LongInt;
Begin
  HeapSize := KSize(A);
End;

Function GlobalAlloc(Flags, Size : LongInt) : LongInt;
Begin
  GlobalAlloc := KAlloc(Size);
End;

Function GlobalLock(H : LongInt) : LongInt;
Begin
  GlobalLock := H;
End;

Function GlobalUnlock(H : LongInt) : LongInt;
Begin
  GlobalUnlock := 0;
  SetErr(0);
End;

Function GlobalFree(H : LongInt) : LongInt;
Begin
  KFree(H);
  GlobalFree := 0;
End;

Function GlobalReAlloc(H, Size, Flags : LongInt) : LongInt;
Var Old, B : LongInt;
Begin
  If (Flags And $80) <> 0 Then
  Begin
    GlobalReAlloc := H;
    Exit;
  End;
  Old := KSize(H);
  B := KRealloc(H, Size);
  If (B <> 0) And (Size > Old) And ((Flags And $40) <> 0) Then
    FillMem(B + Old, Size - Old, 0);
  GlobalReAlloc := B;
End;

Function GlobalSize(H : LongInt) : LongInt;
Begin
  GlobalSize := KSize(H);
End;

Function GlobalHandle(P : LongInt) : LongInt;
Begin
  GlobalHandle := P;
End;

Function GlobalCompact(Mn : LongInt) : LongInt;
Begin
  GlobalCompact := HeapFreeBytes;
End;

Function GlobalFlags(H : LongInt) : LongInt;
Begin
  GlobalFlags := 0;
End;

Function LocalAlloc(Flags, Size : LongInt) : LongInt;
Begin
  LocalAlloc := KAlloc(Size);
End;

Function LocalFree(H : LongInt) : LongInt;
Begin
  KFree(H);
  LocalFree := 0;
End;

Function LocalLock(H : LongInt) : LongInt;
Begin
  LocalLock := H;
End;

Function LocalUnlock(H : LongInt) : LongInt;
Begin
  LocalUnlock := 0;
End;

Function LocalReAlloc(H, Size, Flags : LongInt) : LongInt;
Begin
  LocalReAlloc := GlobalReAlloc(H, Size, Flags);
End;

Function LocalSize(H : LongInt) : LongInt;
Begin
  LocalSize := KSize(H);
End;

Procedure GlobalMemoryStatus(P : LongInt);
Var F : LongInt;
Begin
  F := HeapFreeBytes;
  MemL[0:P] := 32;
  MemL[0:P + 4] := 100 - Trunc(F / (MemTop / 100.0));
  MemL[0:P + 8] := MemTop;
  MemL[0:P + 12] := F;
  MemL[0:P + 16] := MemTop;
  MemL[0:P + 20] := F;
  MemL[0:P + 24] := $7FFE0000;
  MemL[0:P + 28] := F;
End;

{ VirtualAlloc : blocs alignes sur 4 Ko }
Function VirtualAlloc(Addr, Size, Typ, Prot : LongInt) : LongInt;
Var I, O, A : LongInt;
Begin
  VirtualAlloc := 0;
  If Addr <> 0 Then
    For I := 0 To MaxVBlk - 1 Do
      If VBlks[I].Used And (Addr >= VBlks[I].Base) And
         (Addr < VBlks[I].Base + VBlks[I].Size) Then
      Begin
        VirtualAlloc := Addr And Not 4095;
        Exit;
      End;
  { adresse imposee hors des regions connues : refus (Windows : 487) }
  If Addr <> 0 Then
  Begin
    SetErr(487);
    Exit;
  End;
  If Size <= 0 Then Exit;
  Size := (Size + 4095) And Not 4095;
  For I := 0 To MaxVBlk - 1 Do
    If Not VBlks[I].Used Then
    Begin
      { regions alignees sur 64 Ko, comme sous Windows }
      O := KAlloc(Size + 65536);
      If O = 0 Then
      Begin
        SetErr(ErrNotEnoughMem);
        Exit;
      End;
      A := (O + 65535) And Not 65535;
      VBlks[I].Used := True; VBlks[I].Base := A; VBlks[I].Size := Size;
      VBlks[I].Orig := O;
      VirtualAlloc := A;
      Exit;
    End;
  SetErr(ErrNotEnoughMem);
End;

Function VirtualFree(Addr, Size, Typ : LongInt) : LongInt;
Var I : LongInt;
Begin
  VirtualFree := 1;
  If (Typ And $8000) = 0 Then Exit;
  For I := 0 To MaxVBlk - 1 Do
    If VBlks[I].Used And (VBlks[I].Base = Addr) Then
    Begin
      KFree(VBlks[I].Orig);
      VBlks[I].Used := False;
      Exit;
    End;
End;

Function VirtualQuery(Addr, Buf, Len : LongInt) : LongInt;
Var I : LongInt;
Begin
  FillMem(Buf, 28, 0);
  MemL[0:Buf] := Addr And Not 4095;
  MemL[0:Buf + 4] := Addr And Not 4095;
  MemL[0:Buf + 8] := 4;
  MemL[0:Buf + 12] := 4096;
  MemL[0:Buf + 16] := $1000;
  MemL[0:Buf + 20] := 4;
  MemL[0:Buf + 24] := $20000;
  For I := 0 To MaxVBlk - 1 Do
    If VBlks[I].Used And (Addr >= VBlks[I].Base) And
       (Addr < VBlks[I].Base + VBlks[I].Size) Then
    Begin
      MemL[0:Buf] := Addr And Not 4095;
      MemL[0:Buf + 4] := VBlks[I].Base;
      MemL[0:Buf + 12] := VBlks[I].Base + VBlks[I].Size - (Addr And Not 4095);
    End;
  VirtualQuery := 28;
End;

Function IsBadReadPtr(P, N : LongInt) : LongInt;
Begin
  IsBadReadPtr := Ord((P = 0) And (N > 0));
End;

Function IsBadWritePtr(P, N : LongInt) : LongInt;
Begin
  IsBadWritePtr := Ord((P = 0) And (N > 0));
End;

Function IsBadCodePtr(P : LongInt) : LongInt;
Begin
  IsBadCodePtr := Ord(P = 0);
End;

Function IsBadStringPtrA(P, N : LongInt) : LongInt;
Begin
  IsBadStringPtrA := Ord(P = 0);
End;

{ ------------------------------------------------------------------ }
{ Chaines                                                            }
{ ------------------------------------------------------------------ }

Function lstrlenA(P : LongInt) : LongInt;
Begin
  lstrlenA := StrLenZ(P);
End;

Function lstrlenW(P : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  If P <> 0 Then
    While MemW[0:P + N * 2] <> 0 Do Inc(N);
  lstrlenW := N;
End;

Function lstrcpyA(Dst, Src : LongInt) : LongInt;
Begin
  MoveMem(Src, Dst, StrLenZ(Src) + 1);
  lstrcpyA := Dst;
End;

Function lstrcpynA(Dst, Src, N : LongInt) : LongInt;
Var LN : LongInt;
Begin
  If N > 0 Then
  Begin
    LN := Min(StrLenZ(Src), N - 1);
    MoveMem(Src, Dst, LN);
    Mem[0:Dst + LN] := 0;
  End;
  lstrcpynA := Dst;
End;

Function lstrcatA(Dst, Src : LongInt) : LongInt;
Begin
  MoveMem(Src, Dst + StrLenZ(Dst), StrLenZ(Src) + 1);
  lstrcatA := Dst;
End;

Function KStrCmp(A, B : LongInt; NoCase : Boolean) : LongInt;
Var I, X, Y : LongInt;
Begin
  I := 0;
  Repeat
    X := Mem[0:A + I]; Y := Mem[0:B + I];
    If NoCase Then
    Begin
      X := UpCh(X); Y := UpCh(Y);
    End;
    If X <> Y Then
    Begin
      If X < Y Then KStrCmp := -1 Else KStrCmp := 1;
      Exit;
    End;
    Inc(I);
  Until X = 0;
  KStrCmp := 0;
End;

Function lstrcmpA(A, B : LongInt) : LongInt;
Begin
  lstrcmpA := KStrCmp(A, B, False);
End;

Function lstrcmpiA(A, B : LongInt) : LongInt;
Begin
  lstrcmpiA := KStrCmp(A, B, True);
End;

Function MultiByteToWideChar(Cp, Flags, Src, N, Dst, M : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N = -1 Then N := StrLenZ(Src) + 1;
  If M = 0 Then
  Begin
    MultiByteToWideChar := N;
    Exit;
  End;
  If N > M Then N := M;
  For I := 0 To N - 1 Do MemW[0:Dst + I * 2] := Mem[0:Src + I];
  MultiByteToWideChar := N;
End;

Function WideCharToMultiByte(Cp, Flags, Src, N, Dst, M, Def, Used : LongInt)
  : LongInt;
Var I, C : LongInt;
Begin
  If N = -1 Then N := lstrlenW(Src) + 1;
  If Used <> 0 Then MemL[0:Used] := 0;
  If M = 0 Then
  Begin
    WideCharToMultiByte := N;
    Exit;
  End;
  If N > M Then N := M;
  For I := 0 To N - 1 Do
  Begin
    C := MemW[0:Src + I * 2];
    If C > 255 Then C := Ord('?');
    Mem[0:Dst + I] := C;
  End;
  WideCharToMultiByte := N;
End;

Function IsDBCSLeadByte(B : LongInt) : LongInt;
Begin
  IsDBCSLeadByte := 0;
End;

Function GetACP : LongInt;
Begin
  GetACP := 1252;
End;

Function GetOEMCP : LongInt;
Begin
  GetOEMCP := 437;
End;

Function GetCPInfo(Cp, P : LongInt) : LongInt;
Begin
  FillMem(P, 20, 0);
  MemL[0:P] := 1;
  Mem[0:P + 4] := Ord('?');
  GetCPInfo := 1;
End;

Function MulDiv(A, B, C : LongInt) : LongInt;
Var R : Real;
Begin
  If C = 0 Then
  Begin
    MulDiv := -1;
    Exit;
  End;
  R := (A * 1.0) * B / C;
  If R >= 0 Then R := R + 0.5 Else R := R - 0.5;
  MulDiv := Trunc(R);
End;

{ ------------------------------------------------------------------ }
{ Atomes                                                             }
{ ------------------------------------------------------------------ }

Function AtomFind(S : String) : LongInt;
Var I : LongInt;
Begin
  AtomFind := 0;
  S := UpStr(S);
  For I := 0 To MaxAtom - 1 Do
    If Atoms[I].Used And (Atoms[I].Name = S) Then
    Begin
      AtomFind := $C000 + I;
      Exit;
    End;
End;

Function AtomAdd(S : String) : LongInt;
Var I, A : LongInt;
Begin
  A := AtomFind(S);
  If A <> 0 Then
  Begin
    Inc(Atoms[A - $C000].Refs);
    AtomAdd := A;
    Exit;
  End;
  AtomAdd := 0;
  For I := 0 To MaxAtom - 1 Do
    If Not Atoms[I].Used Then
    Begin
      Atoms[I].Used := True;
      Atoms[I].Name := UpStr(S);
      Atoms[I].Refs := 1;
      AtomAdd := $C000 + I;
      Exit;
    End;
End;

Function GlobalAddAtomA(P : LongInt) : LongInt;
Begin
  If (P >= 0) And (P < $10000) Then GlobalAddAtomA := P
  Else GlobalAddAtomA := AtomAdd(PStr(P));
End;

Function GlobalFindAtomA(P : LongInt) : LongInt;
Begin
  If (P >= 0) And (P < $10000) Then GlobalFindAtomA := P
  Else GlobalFindAtomA := AtomFind(PStr(P));
End;

Function GlobalDeleteAtom(A : LongInt) : LongInt;
Begin
  If (A >= $C000) And (A < $C000 + MaxAtom) Then
  Begin
    Dec(Atoms[A - $C000].Refs);
    If Atoms[A - $C000].Refs <= 0 Then Atoms[A - $C000].Used := False;
  End;
  GlobalDeleteAtom := 0;
End;

Function GlobalGetAtomNameA(A, Buf, N : LongInt) : LongInt;
Begin
  GlobalGetAtomNameA := 0;
  If (A >= $C000) And (A < $C000 + MaxAtom) And Atoms[A - $C000].Used Then
  Begin
    PutPStr(Buf, Atoms[A - $C000].Name, N);
    GlobalGetAtomNameA := Length(Atoms[A - $C000].Name);
  End;
End;

Function AddAtomA(P : LongInt) : LongInt;
Begin
  AddAtomA := GlobalAddAtomA(P);
End;

Function DeleteAtom(A : LongInt) : LongInt;
Begin
  DeleteAtom := GlobalDeleteAtom(A);
End;

Function FindAtomA(P : LongInt) : LongInt;
Begin
  FindAtomA := GlobalFindAtomA(P);
End;

{ ------------------------------------------------------------------ }
{ Fichiers .INI (lecture ; les ecritures sont ignorees)              }
{ ------------------------------------------------------------------ }

Function IniPath(F : String) : String;
Begin
  If (Pos('\', F) = 0) And (Pos(':', F) = 0) Then
  Begin
    If RamFind('C:\WINDOWS\' + UpStr(F)) >= 0 Then F := 'C:\WINDOWS\' + F
    Else F := 'D:\' + F;
  End;
  IniPath := F;
End;

{ Valeur Key de la section Sect du fichier F ; False si absente }
Function IniGet(F, Sect, Key : String; Var V : String) : Boolean;
Var A, Size, P : LongInt; Line, Cur : String; C : LongInt; InSect : Boolean;
Begin
  IniGet := False;
  A := LoadWholeFile(IniPath(F), Size);
  If A = 0 Then Exit;
  Sect := UpStr(Sect); Key := UpStr(Key);
  InSect := False; Line := '';
  For P := 0 To Size Do
  Begin
    If P < Size Then C := Mem[0:A + P] Else C := 10;
    If (C = 10) Or (C = 13) Then
    Begin
      Line := Trim(Line);
      If (Length(Line) > 1) And (Line[1] = '[') Then
      Begin
        Cur := UpStr(Copy(Line, 2, Pos(']', Line) - 2));
        InSect := Cur = Sect;
      End
      Else If InSect And (Pos('=', Line) > 0) Then
        If UpStr(Trim(Copy(Line, 1, Pos('=', Line) - 1))) = Key Then
        Begin
          V := Trim(Copy(Line, Pos('=', Line) + 1, 255));
          IniGet := True;
          KFree(A);
          Exit;
        End;
      Line := '';
    End
    Else If Length(Line) < 250 Then Line := Line + Chr(C);
  End;
  KFree(A);
End;

Function GetPrivateProfileStringA(App, Key, Def, Buf, N, F : LongInt)
  : LongInt;
Var V : String;
Begin
  If (App = 0) Or (Key = 0) Then
  Begin
    If N >= 2 Then
    Begin
      Mem[0:Buf] := 0; Mem[0:Buf + 1] := 0;
    End;
    GetPrivateProfileStringA := 0;
    Exit;
  End;
  If Not IniGet(PStr(F), PStr(App), PStr(Key), V) Then V := PStr(Def);
  PutPStr(Buf, V, N);
  GetPrivateProfileStringA := Min(Length(V), N - 1);
End;

Function GetPrivateProfileIntA(App, Key, Def, F : LongInt) : LongInt;
Var V : String; R, E : LongInt;
Begin
  GetPrivateProfileIntA := Def;
  If IniGet(PStr(F), PStr(App), PStr(Key), V) Then
  Begin
    Val(V, R, E);
    If E = 0 Then GetPrivateProfileIntA := R;
  End;
End;

Function GetProfileStringA(App, Key, Def, Buf, N : LongInt) : LongInt;
Var F : String;
Begin
  F := 'WIN.INI' + #0;
  GetProfileStringA := GetPrivateProfileStringA(App, Key, Def, Buf, N,
                                                LongInt(@F[1]));
End;

Function GetProfileIntA(App, Key, Def : LongInt) : LongInt;
Var F : String;
Begin
  F := 'WIN.INI' + #0;
  GetProfileIntA := GetPrivateProfileIntA(App, Key, Def, LongInt(@F[1]));
End;

Function WriteProfileStringA(App, Key, V : LongInt) : LongInt;
Begin
  WriteProfileStringA := 1;
End;

Function WritePrivateProfileStringA(App, Key, V, F : LongInt) : LongInt;
Begin
  WritePrivateProfileStringA := 1;
End;

{ ------------------------------------------------------------------ }
{ Taches et synchronisation                                          }
{ ------------------------------------------------------------------ }

Function CreateThread(Sec, Stack, Start, Param, Flags, PTid : LongInt)
  : LongInt;
Var T : LongInt;
Begin
  CreateThread := 0;
  T := ThreadNew(Start, Param, Max(Stack, $40000), True);
  If T < 0 Then
  Begin
    SetErr(8);
    Exit;
  End;
  KLog('CreateThread ' + IntStr(T) + ' -> ' + HexStr(Start, 8));
  If PTid <> 0 Then MemL[0:PTid] := ThreadId(T);
  CreateThread := KHandle(Threads[T].KObj);
End;

Procedure ExitThread(Code : LongInt);
Begin
  ExitThreadK(Code);
End;

Function SetThreadPriority(H, P : LongInt) : LongInt;
Begin
  SetThreadPriority := 1;
End;

Function GetThreadPriority(H : LongInt) : LongInt;
Begin
  GetThreadPriority := 0;
End;

Function ResumeThread(H : LongInt) : LongInt;
Begin
  ResumeThread := 1;
End;

Function GetExitCodeThread(H, P : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koThread);
  If (I >= 0) And (P <> 0) Then
  Begin
    If KObjs[I].F2 <> 0 Then MemL[0:P] := 0
    Else MemL[0:P] := Threads[KObjs[I].F1].ExitCode;
  End;
  GetExitCodeThread := Ord(I >= 0);
End;

Function CreateSemaphoreA(Sec, Init, Mx, Name : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjNew(koSemaphore);
  If I < 0 Then
  Begin
    CreateSemaphoreA := 0;
    Exit;
  End;
  KObjs[I].F1 := Init; KObjs[I].F2 := Mx;
  CreateSemaphoreA := KHandle(I);
End;

Function ReleaseSemaphore(H, N, Prev : LongInt) : LongInt;
Var I : LongInt;
Begin
  ReleaseSemaphore := 0;
  I := KObjOf(H, koSemaphore);
  If I < 0 Then Exit;
  If Prev <> 0 Then MemL[0:Prev] := KObjs[I].F1;
  KObjs[I].F1 := Min(KObjs[I].F1 + N, KObjs[I].F2);
  ReleaseSemaphore := 1;
End;

Function CreateEventA(Sec, Manual, Init, Name : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjNew(koEvent);
  If I < 0 Then
  Begin
    CreateEventA := 0;
    Exit;
  End;
  KObjs[I].F1 := Ord(Init <> 0); KObjs[I].F2 := Ord(Manual <> 0);
  CreateEventA := KHandle(I);
End;

Function SetEvent(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koEvent);
  If I >= 0 Then KObjs[I].F1 := 1;
  SetEvent := Ord(I >= 0);
End;

Function ResetEvent(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koEvent);
  If I >= 0 Then KObjs[I].F1 := 0;
  ResetEvent := Ord(I >= 0);
End;

Function PulseEvent(H : LongInt) : LongInt;
Begin
  SetEvent(H);
  KYield;
  PulseEvent := ResetEvent(H);
End;

Function CreateMutexA(Sec, Own, Name : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjNew(koMutex);
  If I < 0 Then
  Begin
    CreateMutexA := 0;
    Exit;
  End;
  If Own <> 0 Then
  Begin
    KObjs[I].F1 := ThreadId(CurT); KObjs[I].F2 := 1;
  End;
  CreateMutexA := KHandle(I);
End;

Function ReleaseMutex(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := KObjOf(H, koMutex);
  If I >= 0 Then
  Begin
    Dec(KObjs[I].F2);
    If KObjs[I].F2 <= 0 Then
    Begin
      KObjs[I].F1 := 0; KObjs[I].F2 := 0;
    End;
  End;
  ReleaseMutex := Ord(I >= 0);
End;

Function WaitForSingleObject(H, Ms : LongInt) : LongInt;
Begin
  WaitForSingleObject := KWait(H, Ms);
End;

{ CRITICAL_SECTION : +4 LockCount, +8 RecursionCount, +12 OwningThread }
Procedure InitializeCriticalSection(Cs : LongInt);
Begin
  FillMem(Cs, 24, 0);
  MemL[0:Cs + 4] := -1;
End;

Procedure DeleteCriticalSection(Cs : LongInt);
Begin
End;

Procedure EnterCriticalSection(Cs : LongInt);
Var Me : LongInt;
Begin
  Me := ThreadId(CurT);
  While (MemL[0:Cs + 12] <> 0) And (MemL[0:Cs + 12] <> Me) Do
  Begin
    If ThreadOfId(MemL[0:Cs + 12]) < 0 Then Break;
    If Not Threads[ThreadOfId(MemL[0:Cs + 12])].Used Or
       (Threads[ThreadOfId(MemL[0:Cs + 12])].State = tsDead) Then Break;
    KYield;
  End;
  MemL[0:Cs + 12] := Me;
  MemL[0:Cs + 8] := MemL[0:Cs + 8] + 1;
  MemL[0:Cs + 4] := MemL[0:Cs + 4] + 1;
End;

Procedure LeaveCriticalSection(Cs : LongInt);
Begin
  MemL[0:Cs + 8] := MemL[0:Cs + 8] - 1;
  MemL[0:Cs + 4] := MemL[0:Cs + 4] - 1;
  If MemL[0:Cs + 8] <= 0 Then
  Begin
    MemL[0:Cs + 8] := 0;
    MemL[0:Cs + 12] := 0;
    MemL[0:Cs + 4] := -1;
  End;
End;

Function InterlockedIncrement(P : LongInt) : LongInt;
Begin
  MemL[0:P] := MemL[0:P] + 1;
  InterlockedIncrement := MemL[0:P];
End;

Function InterlockedDecrement(P : LongInt) : LongInt;
Begin
  MemL[0:P] := MemL[0:P] - 1;
  InterlockedDecrement := MemL[0:P];
End;

Function InterlockedExchange(P, V : LongInt) : LongInt;
Begin
  InterlockedExchange := MemL[0:P];
  MemL[0:P] := V;
End;

Function TlsAlloc : LongInt;
Var I : LongInt;
Begin
  TlsAlloc := -1;
  For I := 0 To TlsSlots - 1 Do
    If Not TlsUsed[I] Then
    Begin
      TlsUsed[I] := True;
      TlsAlloc := I;
      Exit;
    End;
End;

Function TlsFree(I : LongInt) : LongInt;
Begin
  If (I >= 0) And (I < TlsSlots) Then TlsUsed[I] := False;
  TlsFree := 1;
End;

Function TlsGetValue(I : LongInt) : LongInt;
Begin
  TlsGetValue := 0;
  If (I >= 0) And (I < TlsSlots) Then
    TlsGetValue := MemL[0:Threads[CurT].Tib + 4096 + I * 4];
  SetErr(0);
End;

Function TlsSetValue(I, V : LongInt) : LongInt;
Begin
  TlsSetValue := 0;
  If (I < 0) Or (I >= TlsSlots) Then Exit;
  MemL[0:Threads[CurT].Tib + 4096 + I * 4] := V;
  TlsSetValue := 1;
End;

{ ==================================================================== }
{ Partie 9 - API Win32 GDI32                                           }
{ ==================================================================== }
{ Objets GDI (poignee = 00020000h + 4 * indice) :
    stylo   : I1 style, I2 largeur, I3 couleur
    pinceau : I1 style (0 plein, 1 nul, 2 hachures, 3 motif), I2 couleur,
              I3 hachure, I4 bitmap du motif
    police  : I1 hauteur, I3 graisse, Name nom
    bitmap  : I1 bits, I2 largeur, I3 hauteur, I4 bits par point,
              I5 octets par ligne, I6 table de couleurs (RGBQUAD) ou 0,
              I7 drapeaux (1 DIB, 2 de haut en bas, 4 monochrome),
              I8 contexte qui l'a selectionne (+1)
    palette : I1 entrees (PALETTEENTRY), I2 nombre, I3 correspondance
              vers la palette systeme (256 octets)
    region  : I1..I4 rectangle (bornes exclusives), I5 sorte
    contexte: I1 indice dans Dcs
  Les bitmaps compatibles (DDB) contiennent des indices de la palette
  systeme, 8 bits par point ; les DIB gardent leur format et leur table
  de couleurs, traduites lors des transferts. }

Const
  MaxDC = 96;
  SRCCOPY = $CC0020; SRCPAINT = $EE0086; SRCAND = $8800C6;
  SRCINVERT = $660046; SRCERASE = $440328; NOTSRCCOPY = $330008;
  NOTSRCERASE = $1100A6; MERGECOPY = $C000CA; MERGEPAINT = $BB0226;
  PATCOPY = $F00021; PATPAINT = $FB0A09; PATINVERT = $5A0049;
  DSTINVERT = $550009; BLACKNESS = $42; WHITENESS = $FF0062;

Type
  TGdi = Record
    Used  : Boolean;
    Kind  : LongInt;
    Stock : Boolean;
    Owner : LongInt;
    I1, I2, I3, I4, I5, I6, I7, I8 : LongInt;
    Name  : String[31];
  End;

  TDC = Record
    Used      : Boolean;
    Wnd       : LongInt;      { fenetre (-1 : memoire ou ecran) }
    Client    : Boolean;
    Screen    : Boolean;
    Bmp, Pen, Brush, Font, Pal : LongInt;   { indices d'objets GDI }
    BkColor, TextColor, BkMode, Rop2, TextAlign, StretchMode : LongInt;
    PolyFill  : LongInt;
    PosX, PosY, VpX, VpY, WinX, WinY : LongInt;
    HasClip   : Boolean;
    ClipR     : TRect;        { coordonnees du periph. (origine du DC) }
    HasPaint  : Boolean;
    PaintR    : TRect;
    Gdi       : LongInt;      { objet GDI du contexte }
    Saved     : LongInt;      { pile SaveDC (bloc du tas) }
    NSaved    : LongInt;
    Owned     : Boolean;      { CS_OWNDC }
  End;

Var
  Gdis      : Array[0..MaxGdi - 1] Of TGdi;
  Dcs       : Array[0..MaxDC - 1] Of TDC;
  StockObj  : Array[0..19] Of LongInt;
  DefBmp    : LongInt;        { bitmap monochrome 1x1 par defaut }
  SysPalUse : LongInt;
  DefPal    : LongInt;
  XlatTab   : Array[0..255] Of Byte;
  { cible de dessin d'un contexte }
  GSurf     : TSurf;
  GOX, GOY  : LongInt;
  GClip     : TRect;
  GDc       : LongInt;
  GTab      : LongInt;        { table de couleurs de la cible (DIB) ou 0 }
  GTop      : LongInt;        { fenetre de premier niveau ou -1 }

Function GdiNew(Kind : LongInt) : LongInt;
Var I : LongInt;
Begin
  GdiNew := -1;
  For I := 0 To MaxGdi - 1 Do
    If Not Gdis[I].Used Then
    Begin
      FillMem(LongInt(@Gdis[I]), SizeOf(TGdi), 0);
      Gdis[I].Used := True;
      Gdis[I].Kind := Kind;
      Gdis[I].Owner := HeapOwner;
      GdiNew := I;
      Exit;
    End;
  KLog('GDI : table pleine');
End;

Function GdiH(I : LongInt) : LongInt;
Begin
  If I < 0 Then GdiH := 0 Else GdiH := HGdiBase + I * 4;
End;

Function GdiOf(H, Kind : LongInt) : LongInt;
Var I : LongInt;
Begin
  GdiOf := -1;
  If (H < HGdiBase) Or (H >= HGdiBase + MaxGdi * 4) Then Exit;
  I := (H - HGdiBase) Div 4;
  If Not Gdis[I].Used Then Exit;
  If (Kind <> 0) And (Gdis[I].Kind <> Kind) Then Exit;
  GdiOf := I;
End;

Function DcOf(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  DcOf := -1;
  I := GdiOf(H, goDC);
  If I >= 0 Then DcOf := Gdis[I].I1;
End;

{ ------------------------------------------------------------------ }
{ Bitmaps                                                            }
{ ------------------------------------------------------------------ }

Function BmpNew(W, H, Bpp : LongInt; Mono : Boolean) : LongInt;
Var B, Pitch : LongInt;
Begin
  BmpNew := -1;
  B := GdiNew(goBitmap);
  If B < 0 Then Exit;
  If W < 1 Then W := 1;
  If H < 1 Then H := 1;
  Pitch := (W + 3) And Not 3;
  Gdis[B].I1 := KAlloc(Pitch * H + 16);
  If Gdis[B].I1 = 0 Then
  Begin
    Gdis[B].Used := False;
    Exit;
  End;
  Gdis[B].I2 := W; Gdis[B].I3 := H; Gdis[B].I4 := 8; Gdis[B].I5 := Pitch;
  Gdis[B].I7 := 2;
  If Mono Then
  Begin
    Gdis[B].I7 := 2 Or 4;
    Gdis[B].I4 := 1;
  End;
  BmpNew := B;
End;

{ Surface d'un bitmap 8 bits (les DIB de bas en haut ont un pas negatif)}
Function BmpSurf(B : LongInt; Var S : TSurf) : Boolean;
Begin
  BmpSurf := False;
  If (B < 0) Or (Gdis[B].I4 <> 8) And ((Gdis[B].I7 And 4) = 0) Then Exit;
  S.W := Gdis[B].I2; S.H := Gdis[B].I3;
  If (Gdis[B].I7 And 2) <> 0 Then
  Begin
    S.Bits := Gdis[B].I1; S.Pitch := Gdis[B].I5;
  End
  Else
  Begin
    S.Bits := Gdis[B].I1 + (Gdis[B].I3 - 1) * Gdis[B].I5;
    S.Pitch := -Gdis[B].I5;
  End;
  BmpSurf := True;
End;

Procedure BmpFree(B : LongInt);
Begin
  If (Gdis[B].I7 And 8) = 0 Then KFree(Gdis[B].I1);
  If Gdis[B].I6 <> 0 Then KFree(Gdis[B].I6);
  Gdis[B].Used := False;
End;

{ ------------------------------------------------------------------ }
{ Contextes                                                          }
{ ------------------------------------------------------------------ }

Function DcNew(Wnd : LongInt; Client : Boolean) : LongInt;
Var I, G : LongInt;
Begin
  DcNew := 0;
  For I := 0 To MaxDC - 1 Do
    If Not Dcs[I].Used Then
    Begin
      G := GdiNew(goDC);
      If G < 0 Then Exit;
      FillMem(LongInt(@Dcs[I]), SizeOf(TDC), 0);
      Dcs[I].Used := True;
      Dcs[I].Wnd := Wnd;
      Dcs[I].Client := Client;
      Dcs[I].Bmp := -1;
      Dcs[I].Pen := StockObj[7];
      Dcs[I].Brush := StockObj[0];
      Dcs[I].Font := StockObj[13];
      Dcs[I].Pal := DefPal;
      Dcs[I].BkColor := $FFFFFF;
      Dcs[I].TextColor := 0;
      Dcs[I].BkMode := 2;
      Dcs[I].Rop2 := 13;
      Dcs[I].StretchMode := 1;
      Dcs[I].PolyFill := 1;
      Dcs[I].Gdi := G;
      Gdis[G].I1 := I;
      DcNew := GdiH(G);
      Exit;
    End;
  KLog('GDI : plus de contextes');
End;

Procedure DcFree(D : LongInt);
Begin
  If (D < 0) Or Not Dcs[D].Used Then Exit;
  If (Dcs[D].Bmp >= 0) And Gdis[Dcs[D].Bmp].Used Then
    Gdis[Dcs[D].Bmp].I8 := 0;
  If Dcs[D].Saved <> 0 Then KFree(Dcs[D].Saved);
  Gdis[Dcs[D].Gdi].Used := False;
  Dcs[D].Used := False;
End;

{ Preparer le dessin dans le contexte D : DS, DOX, DOY, ClipX1.. en
  coordonnees logiques. False si rien a dessiner }
Function DcBegin(D : LongInt) : Boolean;
Var S : TSurf; OX, OY, B : LongInt; Clip, R : TRect;
Begin
  DcBegin := False;
  If (D < 0) Or Not Dcs[D].Used Then Exit;
  GTab := 0; GTop := -1;
  If Dcs[D].Wnd >= 0 Then
  Begin
    If Not Wnds[Dcs[D].Wnd].Used Then Exit;
    If Not WndTarget(Dcs[D].Wnd, Dcs[D].Client, S, OX, OY, Clip) Then Exit;
    GTop := TopOf(Dcs[D].Wnd);
  End
  Else If Dcs[D].Screen Then
  Begin
    S := Back; OX := 0; OY := 0;
    SetR(Clip, 0, 0, ScrW, ScrH);
  End
  Else
  Begin
    B := Dcs[D].Bmp;
    If B < 0 Then B := DefBmp;
    If Not BmpSurf(B, S) Then Exit;
    OX := 0; OY := 0;
    SetR(Clip, 0, 0, S.W, S.H);
    GTab := Gdis[B].I6;
  End;
  If Dcs[D].HasClip Then
  Begin
    R := Dcs[D].ClipR;
    R.L := R.L + OX; R.R := R.R + OX; R.T := R.T + OY; R.B := R.B + OY;
    If Not RInter(Clip, Clip, R) Then Exit;
  End;
  If Dcs[D].HasPaint Then
  Begin
    R := Dcs[D].PaintR;
    R.L := R.L + OX; R.R := R.R + OX; R.T := R.T + OY; R.B := R.B + OY;
    If Not RInter(Clip, Clip, R) Then Exit;
  End;
  GSurf := S; GOX := OX; GOY := OY; GClip := Clip; GDc := D;
  { coordonnees logiques -> surface : x + VpX - WinX + OX }
  DS := S;
  DOX := -(OX + Dcs[D].VpX - Dcs[D].WinX);
  DOY := -(OY + Dcs[D].VpY - Dcs[D].WinY);
  ClipX1 := Clip.L + DOX; ClipY1 := Clip.T + DOY;
  ClipX2 := Clip.R - 1 + DOX; ClipY2 := Clip.B - 1 + DOY;
  DcBegin := (ClipX1 <= ClipX2) And (ClipY1 <= ClipY2);
End;

{ Signaler qu'une zone logique (bornes incluses) a ete dessinee }
Procedure DcDirty(X1, Y1, X2, Y2 : LongInt);
Begin
  If GTop >= 0 Then
    MarkDirty(Wnds[GTop].X + Max(X1 - DOX, GClip.L),
              Wnds[GTop].Y + Max(Y1 - DOY, GClip.T),
              Wnds[GTop].X + Min(X2 - DOX + 1, GClip.R),
              Wnds[GTop].Y + Min(Y2 - DOY + 1, GClip.B))
  Else If (GDc >= 0) And Dcs[GDc].Screen Then
    MarkDirty(X1, Y1, X2 + 1, Y2 + 1);
End;

Procedure DcDirtyAll;
Begin
  DcDirty(ClipX1, ClipY1, ClipX2, ClipY2);
End;

{ Couleur (COLORREF) -> indice dans la cible courante }
Function GColor(C : LongInt) : LongInt;
Var I, Best, BD, D, R, G, B, T : LongInt;
Begin
  If GTab = 0 Then
  Begin
    GColor := ColorIdx(C);
    Exit;
  End;
  If (C Shr 24) = 1 Then
  Begin
    GColor := C And 255;
    Exit;
  End;
  R := C And 255; G := (C Shr 8) And 255; B := (C Shr 16) And 255;
  Best := 0; BD := $7FFFFFFF;
  For I := 0 To 255 Do
  Begin
    T := MemL[0:GTab + I * 4];
    D := Sqr(((T Shr 16) And 255) - R) + Sqr(((T Shr 8) And 255) - G) +
         Sqr((T And 255) - B);
    If D < BD Then
    Begin
      BD := D; Best := I;
      If D = 0 Then Break;
    End;
  End;
  GColor := Best;
End;

{ ------------------------------------------------------------------ }
{ Objets de base et objets predefinis                                }
{ ------------------------------------------------------------------ }

Function CreatePen(Style, Width, Color : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goPen);
  If I >= 0 Then
  Begin
    Gdis[I].I1 := Style; Gdis[I].I2 := Width; Gdis[I].I3 := Color;
  End;
  CreatePen := GdiH(I);
End;

Function CreatePenIndirect(P : LongInt) : LongInt;
Begin
  CreatePenIndirect := CreatePen(MemL[0:P], MemL[0:P + 4], MemL[0:P + 12]);
End;

Function CreateSolidBrush(Color : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goBrush);
  If I >= 0 Then Gdis[I].I2 := Color;
  CreateSolidBrush := GdiH(I);
End;

Function CreateHatchBrush(Hatch, Color : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goBrush);
  If I >= 0 Then
  Begin
    Gdis[I].I1 := 2; Gdis[I].I2 := Color; Gdis[I].I3 := Hatch;
  End;
  CreateHatchBrush := GdiH(I);
End;

Function CreateBrushIndirect(P : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goBrush);
  If I >= 0 Then
  Begin
    Case MemL[0:P] Of
      1 : Gdis[I].I1 := 1;
      2 : Gdis[I].I1 := 2;
      3 : Gdis[I].I1 := 3;
    Else
      Gdis[I].I1 := 0;
    End;
    Gdis[I].I2 := MemL[0:P + 4];
    Gdis[I].I3 := MemL[0:P + 8];
    If Gdis[I].I1 = 3 Then Gdis[I].I4 := GdiOf(MemL[0:P + 8], goBitmap);
  End;
  CreateBrushIndirect := GdiH(I);
End;

Function CreatePatternBrush(Hbm : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goBrush);
  If I >= 0 Then
  Begin
    Gdis[I].I1 := 3;
    Gdis[I].I4 := GdiOf(Hbm, goBitmap);
    If Gdis[I].I4 < 0 Then Gdis[I].I1 := 0;
  End;
  CreatePatternBrush := GdiH(I);
End;

Function CreateDIBitmapK(Bmi, Bits, Usage : LongInt) : LongInt; Forward;

Function CreateDIBPatternBrush(HGlob, Usage : LongInt) : LongInt;
Var I, B : LongInt;
Begin
  I := GdiNew(goBrush);
  If I >= 0 Then
  Begin
    B := CreateDIBitmapK(HGlob, 0, Usage);
    Gdis[I].I1 := 3;
    Gdis[I].I4 := B;
    If B < 0 Then Gdis[I].I1 := 0;
  End;
  CreateDIBPatternBrush := GdiH(I);
End;

Function CreateFontA(H, W, Esc, Orient, Weight, Italic, Under, Strike,
  CharSet, OutPrec, ClipPrec, Quality, Pitch, Face : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goFont);
  If I >= 0 Then
  Begin
    Gdis[I].I1 := H; Gdis[I].I2 := W; Gdis[I].I3 := Weight;
    Gdis[I].I4 := Italic; Gdis[I].I5 := Under;
    Gdis[I].Name := Copy(PStr(Face), 1, 31);
  End;
  CreateFontA := GdiH(I);
End;

Function CreateFontIndirectA(P : LongInt) : LongInt;
Begin
  CreateFontIndirectA := CreateFontA(MemL[0:P], MemL[0:P + 4], 0, 0,
    MemL[0:P + 16], Mem[0:P + 20], Mem[0:P + 21], Mem[0:P + 22], 0, 0, 0,
    0, 0, P + 28);
End;

Function AddFontResourceA(P : LongInt) : LongInt;
Begin
  AddFontResourceA := 1;
End;

Function RemoveFontResourceA(P : LongInt) : LongInt;
Begin
  RemoveFontResourceA := 1;
End;

Function GetStockObject(I : LongInt) : LongInt;
Begin
  If (I >= 0) And (I <= 19) And (StockObj[I] >= 0) Then
    GetStockObject := GdiH(StockObj[I])
  Else GetStockObject := 0;
End;

Procedure InitGdi;
Var I, B, P : LongInt;
Begin
  For I := 0 To 19 Do StockObj[I] := -1;
  StockObj[0] := GdiOf(CreateSolidBrush($FFFFFF), 0);
  StockObj[1] := GdiOf(CreateSolidBrush($C0C0C0), 0);
  StockObj[2] := GdiOf(CreateSolidBrush($808080), 0);
  StockObj[3] := GdiOf(CreateSolidBrush($404040), 0);
  StockObj[4] := GdiOf(CreateSolidBrush(0), 0);
  StockObj[5] := GdiOf(CreateSolidBrush(0), 0);
  Gdis[StockObj[5]].I1 := 1;
  StockObj[6] := GdiOf(CreatePen(0, 1, $FFFFFF), 0);
  StockObj[7] := GdiOf(CreatePen(0, 1, 0), 0);
  StockObj[8] := GdiOf(CreatePen(5, 1, 0), 0);
  For I := 10 To 17 Do
    StockObj[I] := GdiOf(CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0), 0);
  Gdis[StockObj[10]].Name := 'Terminal';
  Gdis[StockObj[13]].Name := 'System';
  Gdis[StockObj[17]].Name := 'MS Sans Serif';
  { palette par defaut : les 20 couleurs statiques }
  P := GdiNew(goPalette);
  Gdis[P].I1 := KAlloc(20 * 4); Gdis[P].I2 := 20;
  Gdis[P].I3 := KAlloc(256);
  For I := 0 To 19 Do
  Begin
    If I < 10 Then B := I Else B := 236 + I;
    Mem[0:Gdis[P].I1 + I * 4] := SysPal[B * 3];
    Mem[0:Gdis[P].I1 + I * 4 + 1] := SysPal[B * 3 + 1];
    Mem[0:Gdis[P].I1 + I * 4 + 2] := SysPal[B * 3 + 2];
    Mem[0:Gdis[P].I3 + I] := B;
  End;
  StockObj[15] := P;
  DefPal := P;
  For I := 0 To 19 Do
    If StockObj[I] >= 0 Then
    Begin
      Gdis[StockObj[I]].Stock := True;
      Gdis[StockObj[I]].Owner := 0;
    End;
  DefBmp := BmpNew(1, 1, 1, True);
  Gdis[DefBmp].Stock := True;
  Gdis[DefBmp].Owner := 0;
  SysPalUse := 1;
End;

Function DeleteObject(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  DeleteObject := 1;
  I := GdiOf(H, 0);
  If I < 0 Then
  Begin
    DeleteObject := 0;
    Exit;
  End;
  If Gdis[I].Stock Then Exit;
  Case Gdis[I].Kind Of
    goBitmap :
    Begin
      If Gdis[I].I8 <> 0 Then
      Begin
        DeleteObject := 0;
        Exit;
      End;
      BmpFree(I);
    End;
    goPalette :
    Begin
      KFree(Gdis[I].I1);
      KFree(Gdis[I].I3);
      Gdis[I].Used := False;
    End;
    goDC : DeleteObject := 0;
  Else
    Gdis[I].Used := False;
  End;
End;

Function UnrealizeObject(H : LongInt) : LongInt;
Begin
  UnrealizeObject := 1;
End;

{ GetObjectA : BITMAP, DIBSECTION, LOGPEN, LOGBRUSH, LOGFONT, palette }
Function GetObjectA(H, N, Buf : LongInt) : LongInt;
Var I, B : LongInt;
Begin
  GetObjectA := 0;
  I := GdiOf(H, 0);
  If I < 0 Then Exit;
  Case Gdis[I].Kind Of
    goBitmap :
    Begin
      If Buf = 0 Then
      Begin
        GetObjectA := 24;
        Exit;
      End;
      FillMem(Buf, Min(N, 84), 0);
      MemL[0:Buf + 4] := Gdis[I].I2;
      MemL[0:Buf + 8] := Gdis[I].I3;
      If (Gdis[I].I7 And 4) <> 0 Then
        MemL[0:Buf + 12] := ((Gdis[I].I2 + 15) Div 16) * 2
      Else MemL[0:Buf + 12] := Gdis[I].I5;
      MemW[0:Buf + 16] := 1;
      MemW[0:Buf + 18] := Gdis[I].I4;
      If (Gdis[I].I7 And 1) <> 0 Then MemL[0:Buf + 20] := Gdis[I].I1;
      GetObjectA := 24;
      If ((Gdis[I].I7 And 1) <> 0) And (N >= 84) Then
      Begin
        B := Buf + 24;
        MemL[0:B] := 40;
        MemL[0:B + 4] := Gdis[I].I2;
        If (Gdis[I].I7 And 2) <> 0 Then MemL[0:B + 8] := -Gdis[I].I3
        Else MemL[0:B + 8] := Gdis[I].I3;
        MemW[0:B + 12] := 1;
        MemW[0:B + 14] := Gdis[I].I4;
        MemL[0:B + 20] := Gdis[I].I5 * Gdis[I].I3;
        GetObjectA := 84;
      End;
    End;
    goPen :
    Begin
      MemL[0:Buf] := Gdis[I].I1; MemL[0:Buf + 4] := Gdis[I].I2;
      MemL[0:Buf + 8] := 0; MemL[0:Buf + 12] := Gdis[I].I3;
      GetObjectA := 16;
    End;
    goBrush :
    Begin
      MemL[0:Buf] := Gdis[I].I1; MemL[0:Buf + 4] := Gdis[I].I2;
      MemL[0:Buf + 8] := Gdis[I].I3;
      GetObjectA := 12;
    End;
    goFont :
    Begin
      FillMem(Buf, Min(N, 60), 0);
      MemL[0:Buf] := Gdis[I].I1; MemL[0:Buf + 4] := Gdis[I].I2;
      MemL[0:Buf + 16] := Gdis[I].I3;
      If N >= 60 Then PutPStr(Buf + 28, Gdis[I].Name, 32);
      GetObjectA := Min(N, 60);
    End;
    goPalette :
    Begin
      MemW[0:Buf] := Gdis[I].I2;
      GetObjectA := 2;
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Palettes                                                           }
{ ------------------------------------------------------------------ }

{ LOGPALETTE : +0 version, +2 nombre, +4 entrees (R, G, B, drapeaux) }
Function CreatePalette(P : LongInt) : LongInt;
Var I, N : LongInt;
Begin
  I := GdiNew(goPalette);
  If I >= 0 Then
  Begin
    N := MemW[0:P + 2];
    If N > 256 Then N := 256;
    Gdis[I].I2 := N;
    Gdis[I].I1 := KAlloc(Max(N, 1) * 4);
    Gdis[I].I3 := KAlloc(256);
    MoveMem(P + 4, Gdis[I].I1, N * 4);
    For N := 0 To 255 Do Mem[0:Gdis[I].I3 + N] := N;
  End;
  CreatePalette := GdiH(I);
End;

Function GetPaletteEntries(H, Start, N, Buf : LongInt) : LongInt;
Var I : LongInt;
Begin
  GetPaletteEntries := 0;
  I := GdiOf(H, goPalette);
  If I < 0 Then Exit;
  If Buf = 0 Then
  Begin
    GetPaletteEntries := Gdis[I].I2;
    Exit;
  End;
  N := Min(N, Gdis[I].I2 - Start);
  If N <= 0 Then Exit;
  MoveMem(Gdis[I].I1 + Start * 4, Buf, N * 4);
  GetPaletteEntries := N;
End;

Function SetPaletteEntries(H, Start, N, Buf : LongInt) : LongInt;
Var I : LongInt;
Begin
  SetPaletteEntries := 0;
  I := GdiOf(H, goPalette);
  If I < 0 Then Exit;
  N := Min(N, Gdis[I].I2 - Start);
  If N <= 0 Then Exit;
  MoveMem(Buf, Gdis[I].I1 + Start * 4, N * 4);
  SetPaletteEntries := N;
End;

Function SelectPalette(Hdc, Hpal, Bg : LongInt) : LongInt;
Var D, P, Old : LongInt;
Begin
  SelectPalette := 0;
  D := DcOf(Hdc);
  P := GdiOf(Hpal, goPalette);
  If (D < 0) Or (P < 0) Then Exit;
  Old := Dcs[D].Pal;
  Dcs[D].Pal := P;
  SelectPalette := GdiH(Old);
End;

{ Realiser la palette du contexte dans la palette systeme }
Function RealizePalette(Hdc : LongInt) : LongInt;
Var D, P, N, I, Lo, Hi, Slot, E, Changed : LongInt;
Begin
  RealizePalette := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  P := Dcs[D].Pal;
  If (P < 0) Or (P = DefPal) Then Exit;
  N := Gdis[P].I2;
  If SysPalUse = 2 Then
  Begin
    Lo := 1; Hi := 254;
  End
  Else
  Begin
    Lo := 10; Hi := 245;
  End;
  Changed := 0;
  If N >= 256 Then
  Begin
    { palette complete : identite pour les entrees non statiques }
    For I := 0 To 255 Do
    Begin
      E := Gdis[P].I1 + I * 4;
      If (I >= Lo) And (I <= Hi) Then
      Begin
        SysPalSet(I, Mem[0:E], Mem[0:E + 1], Mem[0:E + 2]);
        Mem[0:Gdis[P].I3 + I] := I;
        Inc(Changed);
      End;
    End;
    Inc(PalVer);
    For I := 0 To 255 Do
      If (I < Lo) Or (I > Hi) Then
      Begin
        E := Gdis[P].I1 + I * 4;
        Mem[0:Gdis[P].I3 + I] := NearestIdx(Mem[0:E], Mem[0:E + 1],
                                             Mem[0:E + 2]);
      End;
  End
  Else
  Begin
    Slot := Lo;
    For I := 0 To N - 1 Do
    Begin
      E := Gdis[P].I1 + I * 4;
      If Slot <= Hi Then
      Begin
        SysPalSet(Slot, Mem[0:E], Mem[0:E + 1], Mem[0:E + 2]);
        Mem[0:Gdis[P].I3 + I] := Slot;
        Inc(Slot);
        Inc(Changed);
      End
      Else
        Mem[0:Gdis[P].I3 + I] := NearestIdx(Mem[0:E], Mem[0:E + 1],
                                             Mem[0:E + 2]);
    End;
    Inc(PalVer);
  End;
  DacAll;
  RealizePalette := Changed;
End;

Function AnimatePalette(H, Start, N, Entries : LongInt) : LongInt;
Var I, P, S, E : LongInt;
Begin
  AnimatePalette := 0;
  P := GdiOf(H, goPalette);
  If P < 0 Then Exit;
  For I := 0 To N - 1 Do
    If Start + I < Gdis[P].I2 Then
    Begin
      E := Entries + I * 4;
      MemL[0:Gdis[P].I1 + (Start + I) * 4] := MemL[0:E];
      S := Mem[0:Gdis[P].I3 + Start + I];
      SysPalSet(S, Mem[0:E], Mem[0:E + 1], Mem[0:E + 2]);
      DacSet(S);
    End;
  Inc(PalVer);
  AnimatePalette := 1;
End;

Function GetSystemPaletteEntries(Hdc, Start, N, Buf : LongInt) : LongInt;
Var I : LongInt;
Begin
  If Buf = 0 Then
  Begin
    GetSystemPaletteEntries := 256;
    Exit;
  End;
  For I := 0 To N - 1 Do
    If Start + I < 256 Then
    Begin
      Mem[0:Buf + I * 4] := SysPal[(Start + I) * 3];
      Mem[0:Buf + I * 4 + 1] := SysPal[(Start + I) * 3 + 1];
      Mem[0:Buf + I * 4 + 2] := SysPal[(Start + I) * 3 + 2];
      Mem[0:Buf + I * 4 + 3] := 0;
    End;
  GetSystemPaletteEntries := N;
End;

Function SetSystemPaletteUse(Hdc, Use : LongInt) : LongInt;
Begin
  SetSystemPaletteUse := SysPalUse;
  SysPalUse := Use;
End;

Function GetSystemPaletteUse(Hdc : LongInt) : LongInt;
Begin
  GetSystemPaletteUse := SysPalUse;
End;

Function GetNearestColor(Hdc, C : LongInt) : LongInt;
Begin
  GetNearestColor := IdxColor(ColorIdx(C));
End;

Function GetNearestPaletteIndex(H, C : LongInt) : LongInt;
Var P, I, Best, BD, D, E : LongInt;
Begin
  GetNearestPaletteIndex := 0;
  P := GdiOf(H, goPalette);
  If P < 0 Then Exit;
  Best := 0; BD := $7FFFFFFF;
  For I := 0 To Gdis[P].I2 - 1 Do
  Begin
    E := Gdis[P].I1 + I * 4;
    D := Sqr(Mem[0:E] - (C And 255)) + Sqr(Mem[0:E + 1] - ((C Shr 8) And
         255)) + Sqr(Mem[0:E + 2] - ((C Shr 16) And 255));
    If D < BD Then
    Begin
      BD := D; Best := I;
    End;
  End;
  GetNearestPaletteIndex := Best;
End;

{ ------------------------------------------------------------------ }
{ Creation des contextes et selection                                }
{ ------------------------------------------------------------------ }

Function CreateCompatibleDC(Hdc : LongInt) : LongInt;
Var H : LongInt;
Begin
  H := DcNew(-1, False);
  CreateCompatibleDC := H;
End;

Function CreateDCA(Drv, Dev, Out, Init : LongInt) : LongInt;
Var H : LongInt;
Begin
  H := DcNew(-1, False);
  If H <> 0 Then Dcs[DcOf(H)].Screen := True;
  CreateDCA := H;
End;

Function CreateICA(Drv, Dev, Out, Init : LongInt) : LongInt;
Begin
  CreateICA := CreateDCA(Drv, Dev, Out, Init);
End;

Function DeleteDC(Hdc : LongInt) : LongInt;
Begin
  DcFree(DcOf(Hdc));
  DeleteDC := 1;
End;

Function SelectObject(Hdc, H : LongInt) : LongInt;
Var D, I, Old : LongInt;
Begin
  SelectObject := 0;
  D := DcOf(Hdc);
  I := GdiOf(H, 0);
  If (D < 0) Or (I < 0) Then Exit;
  Case Gdis[I].Kind Of
    goPen : Begin Old := Dcs[D].Pen; Dcs[D].Pen := I End;
    goBrush : Begin Old := Dcs[D].Brush; Dcs[D].Brush := I End;
    goFont : Begin Old := Dcs[D].Font; Dcs[D].Font := I End;
    goBitmap :
    Begin
      Old := Dcs[D].Bmp;
      If Old < 0 Then Old := DefBmp;
      If (Old >= 0) And Gdis[Old].Used Then Gdis[Old].I8 := 0;
      Dcs[D].Bmp := I;
      Gdis[I].I8 := D + 1;
    End;
    goRegion :
    Begin
      Dcs[D].HasClip := True;
      SetR(Dcs[D].ClipR, Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
      SelectObject := 2;
      Exit;
    End;
  Else
    Exit;
  End;
  SelectObject := GdiH(Old);
End;

{ ------------------------------------------------------------------ }
{ Attributs                                                          }
{ ------------------------------------------------------------------ }

Function SetBkColor(Hdc, C : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetBkColor := -1;
  If D < 0 Then Exit;
  SetBkColor := Dcs[D].BkColor;
  Dcs[D].BkColor := C;
End;

Function GetBkColor(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetBkColor := 0 Else GetBkColor := Dcs[D].BkColor;
End;

Function SetTextColor(Hdc, C : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetTextColor := -1;
  If D < 0 Then Exit;
  SetTextColor := Dcs[D].TextColor;
  Dcs[D].TextColor := C;
End;

Function GetTextColor(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetTextColor := 0 Else GetTextColor := Dcs[D].TextColor;
End;

Function SetBkMode(Hdc, M : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetBkMode := 0;
  If D < 0 Then Exit;
  SetBkMode := Dcs[D].BkMode;
  Dcs[D].BkMode := M;
End;

Function GetBkMode(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetBkMode := 0 Else GetBkMode := Dcs[D].BkMode;
End;

Function SetROP2(Hdc, M : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetROP2 := 0;
  If D < 0 Then Exit;
  SetROP2 := Dcs[D].Rop2;
  Dcs[D].Rop2 := M;
End;

Function GetROP2(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetROP2 := 0 Else GetROP2 := Dcs[D].Rop2;
End;

Function SetTextAlign(Hdc, A : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetTextAlign := 0;
  If D < 0 Then Exit;
  SetTextAlign := Dcs[D].TextAlign;
  Dcs[D].TextAlign := A;
End;

Function GetTextAlign(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetTextAlign := 0 Else GetTextAlign := Dcs[D].TextAlign;
End;

Function SetStretchBltMode(Hdc, M : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetStretchBltMode := 0;
  If D < 0 Then Exit;
  SetStretchBltMode := Dcs[D].StretchMode;
  Dcs[D].StretchMode := M;
End;

Function GetStretchBltMode(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then GetStretchBltMode := 0
  Else GetStretchBltMode := Dcs[D].StretchMode;
End;

Function SetPolyFillMode(Hdc, M : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetPolyFillMode := 0;
  If D < 0 Then Exit;
  SetPolyFillMode := Dcs[D].PolyFill;
  Dcs[D].PolyFill := M;
End;

Function SetTextJustification(Hdc, Extra, Count : LongInt) : LongInt;
Begin
  SetTextJustification := 1;
End;

Function SetBrushOrgEx(Hdc, X, Y, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    MemL[0:P] := 0; MemL[0:P + 4] := 0;
  End;
  SetBrushOrgEx := 1;
End;

Function SetViewportOrgEx(Hdc, X, Y, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetViewportOrgEx := 0;
  If D < 0 Then Exit;
  If P <> 0 Then
  Begin
    MemL[0:P] := Dcs[D].VpX; MemL[0:P + 4] := Dcs[D].VpY;
  End;
  Dcs[D].VpX := X; Dcs[D].VpY := Y;
  SetViewportOrgEx := 1;
End;

Function SetWindowOrgEx(Hdc, X, Y, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  SetWindowOrgEx := 0;
  If D < 0 Then Exit;
  If P <> 0 Then
  Begin
    MemL[0:P] := Dcs[D].WinX; MemL[0:P + 4] := Dcs[D].WinY;
  End;
  Dcs[D].WinX := X; Dcs[D].WinY := Y;
  SetWindowOrgEx := 1;
End;

Function DPtoLP(Hdc, Pts, N : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  D := DcOf(Hdc);
  If D >= 0 Then
    For I := 0 To N - 1 Do
    Begin
      MemL[0:Pts + I * 8] := MemL[0:Pts + I * 8] - Dcs[D].VpX + Dcs[D].WinX;
      MemL[0:Pts + I * 8 + 4] := MemL[0:Pts + I * 8 + 4] - Dcs[D].VpY +
                                 Dcs[D].WinY;
    End;
  DPtoLP := 1;
End;

Function LPtoDP(Hdc, Pts, N : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  D := DcOf(Hdc);
  If D >= 0 Then
    For I := 0 To N - 1 Do
    Begin
      MemL[0:Pts + I * 8] := MemL[0:Pts + I * 8] + Dcs[D].VpX - Dcs[D].WinX;
      MemL[0:Pts + I * 8 + 4] := MemL[0:Pts + I * 8 + 4] + Dcs[D].VpY -
                                 Dcs[D].WinY;
    End;
  LPtoDP := 1;
End;

Function GetDCOrgEx(Hdc, P : LongInt) : LongInt;
Var D, X, Y : LongInt;
Begin
  D := DcOf(Hdc);
  X := 0; Y := 0;
  If (D >= 0) And (Dcs[D].Wnd >= 0) Then
  Begin
    If Dcs[D].Client Then ClientScreenOrg(Dcs[D].Wnd, X, Y)
    Else WndScreenPos(Dcs[D].Wnd, X, Y);
  End;
  MemL[0:P] := X; MemL[0:P + 4] := Y;
  GetDCOrgEx := 1;
End;

Function GetCurrentPositionEx(Hdc, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  GetCurrentPositionEx := 0;
  If D < 0 Then Exit;
  MemL[0:P] := Dcs[D].PosX; MemL[0:P + 4] := Dcs[D].PosY;
  GetCurrentPositionEx := 1;
End;

Function SaveDC(Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  SaveDC := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  If Dcs[D].Saved = 0 Then Dcs[D].Saved := KAlloc(SizeOf(TDC) * 8);
  If Dcs[D].NSaved >= 8 Then Exit;
  MoveMem(LongInt(@Dcs[D]), Dcs[D].Saved + Dcs[D].NSaved * SizeOf(TDC),
          SizeOf(TDC));
  Inc(Dcs[D].NSaved);
  SaveDC := Dcs[D].NSaved;
End;

Function RestoreDC(Hdc, N : LongInt) : LongInt;
Var D, S, K : LongInt;
Begin
  RestoreDC := 0;
  D := DcOf(Hdc);
  If (D < 0) Or (Dcs[D].NSaved = 0) Then Exit;
  If N < 0 Then N := Dcs[D].NSaved + 1 + N;
  If (N < 1) Or (N > Dcs[D].NSaved) Then Exit;
  S := Dcs[D].Saved; K := Dcs[D].NSaved;
  MoveMem(S + (N - 1) * SizeOf(TDC), LongInt(@Dcs[D]), SizeOf(TDC));
  Dcs[D].Saved := S; Dcs[D].NSaved := N - 1;
  If (Dcs[D].Bmp >= 0) And Gdis[Dcs[D].Bmp].Used Then
    Gdis[Dcs[D].Bmp].I8 := D + 1;
  RestoreDC := Ord(K > 0);
End;

{ ------------------------------------------------------------------ }
{ Regions (rectangulaires)                                           }
{ ------------------------------------------------------------------ }

Function RgnNew(L0, T0, R0, B0 : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiNew(goRegion);
  If I >= 0 Then
  Begin
    Gdis[I].I1 := Min(L0, R0); Gdis[I].I2 := Min(T0, B0);
    Gdis[I].I3 := Max(L0, R0); Gdis[I].I4 := Max(T0, B0);
    Gdis[I].I5 := 2;
  End;
  RgnNew := GdiH(I);
End;

Function RgnType(I : LongInt) : LongInt;
Begin
  If (Gdis[I].I1 >= Gdis[I].I3) Or (Gdis[I].I2 >= Gdis[I].I4) Then
    RgnType := 1
  Else RgnType := 2;
End;

Function CreateRectRgn(L0, T0, R0, B0 : LongInt) : LongInt;
Begin
  CreateRectRgn := RgnNew(L0, T0, R0, B0);
End;

Function CreateRectRgnIndirect(P : LongInt) : LongInt;
Begin
  CreateRectRgnIndirect := RgnNew(MemL[0:P], MemL[0:P + 4], MemL[0:P + 8],
                                  MemL[0:P + 12]);
End;

Function CreateEllipticRgnIndirect(P : LongInt) : LongInt;
Begin
  CreateEllipticRgnIndirect := CreateRectRgnIndirect(P);
End;

Function CreateEllipticRgn(L0, T0, R0, B0 : LongInt) : LongInt;
Begin
  CreateEllipticRgn := RgnNew(L0, T0, R0, B0);
End;

Function CreateRoundRectRgn(L0, T0, R0, B0, W, H : LongInt) : LongInt;
Begin
  CreateRoundRectRgn := RgnNew(L0, T0, R0, B0);
End;

Function CreatePolygonRgn(Pts, N, Mode : LongInt) : LongInt;
Var I, L0, T0, R0, B0 : LongInt;
Begin
  L0 := $7FFFFFF; T0 := $7FFFFFF; R0 := -$7FFFFFF; B0 := -$7FFFFFF;
  For I := 0 To N - 1 Do
  Begin
    L0 := Min(L0, MemL[0:Pts + I * 8]); R0 := Max(R0, MemL[0:Pts + I * 8]);
    T0 := Min(T0, MemL[0:Pts + I * 8 + 4]);
    B0 := Max(B0, MemL[0:Pts + I * 8 + 4]);
  End;
  If N = 0 Then
  Begin
    L0 := 0; T0 := 0; R0 := 0; B0 := 0;
  End;
  CreatePolygonRgn := RgnNew(L0, T0, R0, B0);
End;

Function SetRectRgn(H, L0, T0, R0, B0 : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiOf(H, goRegion);
  SetRectRgn := 0;
  If I < 0 Then Exit;
  Gdis[I].I1 := L0; Gdis[I].I2 := T0; Gdis[I].I3 := R0; Gdis[I].I4 := B0;
  SetRectRgn := 1;
End;

Function CombineRgn(Dst, S1, S2, Mode : LongInt) : LongInt;
Var D, A, B : LongInt; RA, RB, RR : TRect;
Begin
  CombineRgn := 0;
  D := GdiOf(Dst, goRegion); A := GdiOf(S1, goRegion);
  B := GdiOf(S2, goRegion);
  If (D < 0) Or (A < 0) Then Exit;
  SetR(RA, Gdis[A].I1, Gdis[A].I2, Gdis[A].I3, Gdis[A].I4);
  If B >= 0 Then SetR(RB, Gdis[B].I1, Gdis[B].I2, Gdis[B].I3, Gdis[B].I4)
  Else RB := RA;
  Case Mode Of
    1 : If Not RInter(RR, RA, RB) Then SetR(RR, 0, 0, 0, 0);
    2, 3 :
    Begin
      RR := RA;
      RUnion(RR, RB);
    End;
  Else
    RR := RA;
  End;
  Gdis[D].I1 := RR.L; Gdis[D].I2 := RR.T; Gdis[D].I3 := RR.R;
  Gdis[D].I4 := RR.B;
  CombineRgn := RgnType(D);
End;

Function OffsetRgn(H, X, Y : LongInt) : LongInt;
Var I : LongInt;
Begin
  OffsetRgn := 0;
  I := GdiOf(H, goRegion);
  If I < 0 Then Exit;
  Gdis[I].I1 := Gdis[I].I1 + X; Gdis[I].I3 := Gdis[I].I3 + X;
  Gdis[I].I2 := Gdis[I].I2 + Y; Gdis[I].I4 := Gdis[I].I4 + Y;
  OffsetRgn := RgnType(I);
End;

Function GetRgnBox(H, P : LongInt) : LongInt;
Var I : LongInt;
Begin
  GetRgnBox := 0;
  I := GdiOf(H, goRegion);
  If I < 0 Then Exit;
  MemL[0:P] := Gdis[I].I1; MemL[0:P + 4] := Gdis[I].I2;
  MemL[0:P + 8] := Gdis[I].I3; MemL[0:P + 12] := Gdis[I].I4;
  GetRgnBox := RgnType(I);
End;

Function EqualRgn(A, B : LongInt) : LongInt;
Var I, J : LongInt;
Begin
  I := GdiOf(A, goRegion); J := GdiOf(B, goRegion);
  EqualRgn := Ord((I >= 0) And (J >= 0) And (Gdis[I].I1 = Gdis[J].I1) And
    (Gdis[I].I2 = Gdis[J].I2) And (Gdis[I].I3 = Gdis[J].I3) And
    (Gdis[I].I4 = Gdis[J].I4));
End;

Function PtInRegion(H, X, Y : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := GdiOf(H, goRegion);
  PtInRegion := Ord((I >= 0) And (X >= Gdis[I].I1) And (X < Gdis[I].I3) And
                    (Y >= Gdis[I].I2) And (Y < Gdis[I].I4));
End;

Function SelectClipRgn(Hdc, H : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  SelectClipRgn := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  I := GdiOf(H, goRegion);
  If I < 0 Then
  Begin
    Dcs[D].HasClip := False;
    SelectClipRgn := 3;
    Exit;
  End;
  Dcs[D].HasClip := True;
  SetR(Dcs[D].ClipR, Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
  SelectClipRgn := RgnType(I);
End;

Function IntersectClipRect(Hdc, L0, T0, R0, B0 : LongInt) : LongInt;
Var D : LongInt; R : TRect;
Begin
  IntersectClipRect := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  SetR(R, L0 + Dcs[D].VpX - Dcs[D].WinX, T0 + Dcs[D].VpY - Dcs[D].WinY,
       R0 + Dcs[D].VpX - Dcs[D].WinX, B0 + Dcs[D].VpY - Dcs[D].WinY);
  If Dcs[D].HasClip Then
  Begin
    If Not RInter(Dcs[D].ClipR, Dcs[D].ClipR, R) Then
      SetR(Dcs[D].ClipR, 0, 0, 0, 0);
  End
  Else Dcs[D].ClipR := R;
  Dcs[D].HasClip := True;
  IntersectClipRect := 2;
End;

Function GetClipBox(Hdc, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  GetClipBox := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  If Not DcBegin(D) Then
  Begin
    PutRectAt(P, Dcs[D].ClipR);
    GetClipBox := 1;
    Exit;
  End;
  MemL[0:P] := ClipX1; MemL[0:P + 4] := ClipY1;
  MemL[0:P + 8] := ClipX2 + 1; MemL[0:P + 12] := ClipY2 + 1;
  GetClipBox := 2;
End;

Function GetClipRgn(Hdc, H : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  GetClipRgn := 0;
  D := DcOf(Hdc);
  I := GdiOf(H, goRegion);
  If (D < 0) Or (I < 0) Or Not Dcs[D].HasClip Then Exit;
  Gdis[I].I1 := Dcs[D].ClipR.L; Gdis[I].I2 := Dcs[D].ClipR.T;
  Gdis[I].I3 := Dcs[D].ClipR.R; Gdis[I].I4 := Dcs[D].ClipR.B;
  GetClipRgn := 1;
End;

{ ------------------------------------------------------------------ }
{ Remplissage et formes                                              }
{ ------------------------------------------------------------------ }

{ Remplir (X1,Y1)-(X2,Y2) inclus avec le pinceau B (indice GDI) }
Procedure BrushFill(X1, Y1, X2, Y2, B : LongInt);
Var C, X, Y, PB, PX, PY : LongInt; PS : TSurf;
Begin
  If (B < 0) Or Not Gdis[B].Used Then Exit;
  Case Gdis[B].I1 Of
    1 : Exit;
    2 :
    Begin
      C := GColor(Gdis[B].I2);
      For Y := Max(Y1, ClipY1) To Min(Y2, ClipY2) Do
        For X := Max(X1, ClipX1) To Min(X2, ClipX2) Do
          If ((Gdis[B].I3 = 0) And (Y Mod 8 = 0)) Or
             ((Gdis[B].I3 = 1) And (X Mod 8 = 0)) Or
             ((Gdis[B].I3 >= 2) And ((X + Y) Mod 8 = 0)) Then Pix(X, Y, C);
    End;
    3 :
    Begin
      PB := Gdis[B].I4;
      If (PB < 0) Or Not BmpSurf(PB, PS) Then Exit;
      For Y := Max(Y1, ClipY1) To Min(Y2, ClipY2) Do
      Begin
        PY := Y Mod PS.H;
        If PY < 0 Then PY := PY + PS.H;
        For X := Max(X1, ClipX1) To Min(X2, ClipX2) Do
        Begin
          PX := X Mod PS.W;
          If PX < 0 Then PX := PX + PS.W;
          C := Mem[0:PS.Bits + PY * PS.Pitch + PX];
          If (Gdis[PB].I7 And 4) <> 0 Then
          Begin
            If C = 0 Then C := GColor(Dcs[GDc].TextColor)
            Else C := GColor(Dcs[GDc].BkColor);
          End
          Else If Gdis[PB].I6 <> 0 Then
            C := ColorIdx(((MemL[0:Gdis[PB].I6 + C * 4] Shr 16) And 255) Or
                 (MemL[0:Gdis[PB].I6 + C * 4] And $FF00) Or
                 ((MemL[0:Gdis[PB].I6 + C * 4] And 255) Shl 16));
          Pix(X, Y, C);
        End;
      End;
    End;
  Else
    FBar(X1, Y1, X2, Y2, GColor(Gdis[B].I2));
  End;
End;

Function PatBlt(Hdc, X, Y, W, H, Rop : LongInt) : LongInt;
Var D, C, YY, XX, A : LongInt;
Begin
  PatBlt := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  If W < 0 Then
  Begin
    X := X + W; W := -W;
  End;
  If H < 0 Then
  Begin
    Y := Y + H; H := -H;
  End;
  Case Rop Of
    PATCOPY : BrushFill(X, Y, X + W - 1, Y + H - 1, Dcs[D].Brush);
    BLACKNESS : FBar(X, Y, X + W - 1, Y + H - 1, GColor(0));
    WHITENESS : FBar(X, Y, X + W - 1, Y + H - 1, GColor($FFFFFF));
    DSTINVERT, PATINVERT :
    Begin
      C := 255;
      If Rop = PATINVERT Then C := GColor(Gdis[Dcs[D].Brush].I2);
      For YY := Max(Y, ClipY1) To Min(Y + H - 1, ClipY2) Do
        For XX := Max(X, ClipX1) To Min(X + W - 1, ClipX2) Do
        Begin
          A := DS.Bits + (YY - DOY) * DS.Pitch + (XX - DOX);
          Mem[0:A] := Mem[0:A] Xor C;
        End;
    End;
  Else
    BrushFill(X, Y, X + W - 1, Y + H - 1, Dcs[D].Brush);
  End;
  DcDirty(X, Y, X + W - 1, Y + H - 1);
End;

{ Trait avec le stylo du contexte }
Function PenColor(D : LongInt; Var C : LongInt) : Boolean;
Begin
  PenColor := False;
  If (Dcs[D].Pen < 0) Or (Gdis[Dcs[D].Pen].I1 = 5) Then Exit;
  C := GColor(Gdis[Dcs[D].Pen].I3);
  If Dcs[D].Rop2 = 1 Then C := GColor(0);
  If Dcs[D].Rop2 = 16 Then C := GColor($FFFFFF);
  PenColor := True;
End;

Procedure PenLine(D, X1, Y1, X2, Y2 : LongInt);
Var C, W, K : LongInt;
Begin
  If Not PenColor(D, C) Then Exit;
  W := Gdis[Dcs[D].Pen].I2;
  DLine(X1, Y1, X2, Y2, C);
  If W > 1 Then
    For K := 1 To W - 1 Do
    Begin
      DLine(X1 + K, Y1, X2 + K, Y2, C);
      DLine(X1, Y1 + K, X2, Y2 + K, C);
    End;
  DcDirty(Min(X1, X2), Min(Y1, Y2), Max(X1, X2) + W, Max(Y1, Y2) + W);
End;

Function MoveToEx(Hdc, X, Y, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  MoveToEx := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  If P <> 0 Then
  Begin
    MemL[0:P] := Dcs[D].PosX; MemL[0:P + 4] := Dcs[D].PosY;
  End;
  Dcs[D].PosX := X; Dcs[D].PosY := Y;
  MoveToEx := 1;
End;

Function LineTo(Hdc, X, Y : LongInt) : LongInt;
Var D : LongInt;
Begin
  LineTo := 1;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  If DcBegin(D) Then
  Begin
    { le point final n'est pas dessine }
    PenLine(D, Dcs[D].PosX, Dcs[D].PosY, X, Y);
  End;
  Dcs[D].PosX := X; Dcs[D].PosY := Y;
End;

Function Polyline(Hdc, Pts, N : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  Polyline := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  For I := 0 To N - 2 Do
    PenLine(D, MemL[0:Pts + I * 8], MemL[0:Pts + I * 8 + 4],
            MemL[0:Pts + I * 8 + 8], MemL[0:Pts + I * 8 + 12]);
End;

{ Polygone plein (balayage, regle pair-impair) puis contour }
Procedure FillPoly(D, Pts, N : LongInt);
Var Y, I, J, X1, Y1, X2, Y2, K, T, MinY, MaxY : LongInt;
    Xs : Array[0..63] Of LongInt;
Begin
  If (N < 3) Or (Dcs[D].Brush < 0) Or (Gdis[Dcs[D].Brush].I1 = 1) Then Exit;
  MinY := $7FFFFFF; MaxY := -$7FFFFFF;
  For I := 0 To N - 1 Do
  Begin
    MinY := Min(MinY, MemL[0:Pts + I * 8 + 4]);
    MaxY := Max(MaxY, MemL[0:Pts + I * 8 + 4]);
  End;
  For Y := Max(MinY, ClipY1) To Min(MaxY, ClipY2) Do
  Begin
    K := 0;
    J := N - 1;
    For I := 0 To N - 1 Do
    Begin
      X1 := MemL[0:Pts + I * 8]; Y1 := MemL[0:Pts + I * 8 + 4];
      X2 := MemL[0:Pts + J * 8]; Y2 := MemL[0:Pts + J * 8 + 4];
      If ((Y1 <= Y) And (Y2 > Y)) Or ((Y2 <= Y) And (Y1 > Y)) Then
        If K < 64 Then
        Begin
          Xs[K] := X1 + (Y - Y1) * (X2 - X1) Div (Y2 - Y1);
          Inc(K);
        End;
      J := I;
    End;
    For I := 0 To K - 2 Do
      For J := I + 1 To K - 1 Do
        If Xs[J] < Xs[I] Then
        Begin
          T := Xs[I]; Xs[I] := Xs[J]; Xs[J] := T;
        End;
    I := 0;
    While I + 1 < K Do
    Begin
      BrushFill(Xs[I], Y, Xs[I + 1], Y, Dcs[D].Brush);
      I := I + 2;
    End;
  End;
End;

Function Polygon(Hdc, Pts, N : LongInt) : LongInt;
Var D, I, J : LongInt;
Begin
  Polygon := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  FillPoly(D, Pts, N);
  For I := 0 To N - 1 Do
  Begin
    J := (I + 1) Mod N;
    PenLine(D, MemL[0:Pts + I * 8], MemL[0:Pts + I * 8 + 4],
            MemL[0:Pts + J * 8], MemL[0:Pts + J * 8 + 4]);
  End;
  DcDirtyAll;
End;

Function PolyPolygon(Hdc, Pts, Counts, N : LongInt) : LongInt;
Var I, P : LongInt;
Begin
  P := Pts;
  For I := 0 To N - 1 Do
  Begin
    Polygon(Hdc, P, MemL[0:Counts + I * 4]);
    P := P + MemL[0:Counts + I * 4] * 8;
  End;
  PolyPolygon := 1;
End;

Function Rectangle(Hdc, L0, T0, R0, B0 : LongInt) : LongInt;
Var D, C : LongInt;
Begin
  Rectangle := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  BrushFill(L0 + 1, T0 + 1, R0 - 2, B0 - 2, Dcs[D].Brush);
  If PenColor(D, C) Then Box(L0, T0, R0 - 1, B0 - 1, C)
  Else BrushFill(L0, T0, R0 - 1, B0 - 1, Dcs[D].Brush);
  DcDirty(L0, T0, R0, B0);
End;

Function RoundRect(Hdc, L0, T0, R0, B0, W, H : LongInt) : LongInt;
Begin
  RoundRect := Rectangle(Hdc, L0, T0, R0, B0);
End;

Function Ellipse(Hdc, L0, T0, R0, B0 : LongInt) : LongInt;
Var D, C, CX, CY, RX, RY, Y, DX, PX : LongInt; Ok : Boolean;
Begin
  Ellipse := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  CX := (L0 + R0 - 1) Div 2; CY := (T0 + B0 - 1) Div 2;
  RX := Max(1, (R0 - L0 - 1) Div 2); RY := Max(1, (B0 - T0 - 1) Div 2);
  Ok := PenColor(D, C);
  PX := 0;
  For Y := -RY To RY Do
  Begin
    DX := ISqrt(RX * RX - MulDiv(RX * RX, Y * Y, RY * RY));
    BrushFill(CX - DX, CY + Y, CX + DX, CY + Y, Dcs[D].Brush);
    If Ok Then
    Begin
      Pix(CX - DX, CY + Y, C); Pix(CX + DX, CY + Y, C);
      If Abs(Y) = RY Then HLine(CX - DX, CX + DX, CY + Y, C);
      If (Y > -RY) And (Abs(DX - PX) > 1) Then
      Begin
        HLine(Min(CX - DX, CX - PX), Max(CX - DX, CX - PX), CY + Y, C);
        HLine(Min(CX + DX, CX + PX), Max(CX + DX, CX + PX), CY + Y, C);
      End;
    End;
    PX := DX;
  End;
  DcDirty(L0, T0, R0, B0);
End;

Function FillRgn(Hdc, H, Br : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  FillRgn := 1;
  D := DcOf(Hdc);
  I := GdiOf(H, goRegion);
  If (I < 0) Or Not DcBegin(D) Then Exit;
  BrushFill(Gdis[I].I1, Gdis[I].I2, Gdis[I].I3 - 1, Gdis[I].I4 - 1,
            GdiOf(Br, goBrush));
  DcDirty(Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
End;

Function PaintRgn(Hdc, H : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(Hdc);
  If D < 0 Then PaintRgn := 0
  Else PaintRgn := FillRgn(Hdc, H, GdiH(Dcs[D].Brush));
End;

Function FrameRgn(Hdc, H, Br, W, Hh : LongInt) : LongInt;
Var D, I, B : LongInt;
Begin
  FrameRgn := 1;
  D := DcOf(Hdc);
  I := GdiOf(H, goRegion);
  B := GdiOf(Br, goBrush);
  If (I < 0) Or Not DcBegin(D) Then Exit;
  BrushFill(Gdis[I].I1, Gdis[I].I2, Gdis[I].I3 - 1, Gdis[I].I2 + Hh - 1, B);
  BrushFill(Gdis[I].I1, Gdis[I].I4 - Hh, Gdis[I].I3 - 1, Gdis[I].I4 - 1, B);
  BrushFill(Gdis[I].I1, Gdis[I].I2, Gdis[I].I1 + W - 1, Gdis[I].I4 - 1, B);
  BrushFill(Gdis[I].I3 - W, Gdis[I].I2, Gdis[I].I3 - 1, Gdis[I].I4 - 1, B);
  DcDirty(Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
End;

Function InvertRgn(Hdc, H : LongInt) : LongInt;
Var D, I, X, Y, A : LongInt;
Begin
  InvertRgn := 1;
  D := DcOf(Hdc);
  I := GdiOf(H, goRegion);
  If (I < 0) Or Not DcBegin(D) Then Exit;
  For Y := Max(Gdis[I].I2, ClipY1) To Min(Gdis[I].I4 - 1, ClipY2) Do
    For X := Max(Gdis[I].I1, ClipX1) To Min(Gdis[I].I3 - 1, ClipX2) Do
    Begin
      A := DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX);
      Mem[0:A] := Mem[0:A] Xor 255;
    End;
  DcDirty(Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
End;

Function SetPixel(Hdc, X, Y, C : LongInt) : LongInt;
Var D : LongInt;
Begin
  SetPixel := C;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  Pix(X, Y, GColor(C));
  DcDirty(X, Y, X, Y);
End;

Function GetPixel(Hdc, X, Y : LongInt) : LongInt;
Var D, I : LongInt;
Begin
  GetPixel := -1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  If (X < ClipX1) Or (X > ClipX2) Or (Y < ClipY1) Or (Y > ClipY2) Then Exit;
  I := GetPix(X, Y);
  If GTab <> 0 Then
    GetPixel := ((MemL[0:GTab + I * 4] Shr 16) And 255) Or
                (MemL[0:GTab + I * 4] And $FF00) Or
                ((MemL[0:GTab + I * 4] And 255) Shl 16)
  Else GetPixel := IdxColor(I);
End;

{ ------------------------------------------------------------------ }
{ Texte (police 8x16)                                                }
{ ------------------------------------------------------------------ }

Procedure TextAt(D, X, Y, Str, N, Opt, PRect : LongInt);
Var I, C, Bg, W, A : LongInt; R : TRect;
Begin
  W := N * 8;
  A := Dcs[D].TextAlign;
  If (A And 1) <> 0 Then
  Begin
    X := Dcs[D].PosX; Y := Dcs[D].PosY;
  End;
  If (A And 6) = 6 Then X := X - W Div 2
  Else If (A And 2) <> 0 Then X := X - W;
  If (A And 24) = 24 Then Y := Y - 12
  Else If (A And 8) <> 0 Then Y := Y - 16;
  If (A And 1) <> 0 Then Dcs[D].PosX := X + W;
  C := GColor(Dcs[D].TextColor);
  Bg := GColor(Dcs[D].BkColor);
  If (PRect <> 0) And ((Opt And 2) <> 0) Then
  Begin
    GetRectAt(PRect, R);
    FBar(R.L, R.T, R.R - 1, R.B - 1, Bg);
    DcDirty(R.L, R.T, R.R, R.B);
  End;
  If (PRect <> 0) And ((Opt And 4) <> 0) Then
  Begin
    GetRectAt(PRect, R);
    ClipX1 := Max(ClipX1, R.L); ClipY1 := Max(ClipY1, R.T);
    ClipX2 := Min(ClipX2, R.R - 1); ClipY2 := Min(ClipY2, R.B - 1);
  End;
  If (Dcs[D].BkMode = 2) And ((Opt And 2) = 0) Then
    FBar(X, Y, X + W - 1, Y + 15, Bg);
  For I := 0 To N - 1 Do DrawChar(X + I * 8, Y, Chr(Mem[0:Str + I]), C);
  DcDirty(X, Y, X + W, Y + 16);
End;

Function TextOutA(Hdc, X, Y, Str, N : LongInt) : LongInt;
Var D : LongInt;
Begin
  TextOutA := 1;
  D := DcOf(Hdc);
  If DcBegin(D) Then TextAt(D, X, Y, Str, N, 0, 0);
End;

Function ExtTextOutA(Hdc, X, Y, Opt, PRect, Str, N, Dx : LongInt) : LongInt;
Var D : LongInt;
Begin
  ExtTextOutA := 1;
  D := DcOf(Hdc);
  If DcBegin(D) Then TextAt(D, X, Y, Str, N, Opt, PRect);
End;

Function GetTextExtentPointA(Hdc, Str, N, P : LongInt) : LongInt;
Begin
  MemL[0:P] := N * 8; MemL[0:P + 4] := 16;
  GetTextExtentPointA := 1;
End;

Function GetTextExtentPoint32A(Hdc, Str, N, P : LongInt) : LongInt;
Begin
  GetTextExtentPoint32A := GetTextExtentPointA(Hdc, Str, N, P);
End;

{ TEXTMETRIC (56 octets) }
Function GetTextMetricsA(Hdc, P : LongInt) : LongInt;
Begin
  FillMem(P, 56, 0);
  MemL[0:P] := 16; MemL[0:P + 4] := 12; MemL[0:P + 8] := 4;
  MemL[0:P + 20] := 8; MemL[0:P + 24] := 8; MemL[0:P + 28] := 400;
  MemL[0:P + 36] := 96; MemL[0:P + 40] := 96;
  Mem[0:P + 44] := 32; Mem[0:P + 45] := 255; Mem[0:P + 46] := Ord('?');
  Mem[0:P + 47] := 32; Mem[0:P + 51] := $30;
  GetTextMetricsA := 1;
End;

Function GetTextFaceA(Hdc, N, Buf : LongInt) : LongInt;
Var D : LongInt; S : String;
Begin
  D := DcOf(Hdc);
  S := 'System';
  If (D >= 0) And (Dcs[D].Font >= 0) And (Gdis[Dcs[D].Font].Name <> '') Then
    S := Gdis[Dcs[D].Font].Name;
  PutPStr(Buf, S, N);
  GetTextFaceA := Length(S);
End;

{ EnumFontsA : une seule police (System) annoncee }
Function EnumFontsA(Hdc, Face, Proc, Lp : LongInt) : LongInt;
Var Lf, Tm, R : LongInt;
Begin
  EnumFontsA := 1;
  If Proc = 0 Then Exit;
  Lf := KAlloc(60); Tm := KAlloc(64);
  MemL[0:Lf] := 16; MemL[0:Lf + 4] := 8; MemL[0:Lf + 16] := 400;
  PutPStr(Lf + 28, 'System', 32);
  GetTextMetricsA(Hdc, Tm);
  R := 0;
  asm
    mov eax,Lp
    push eax
    push 1
    mov eax,Tm
    push eax
    mov eax,Lf
    push eax
    mov eax,Proc
    call eax
    mov R,eax
  end;
  KFree(Lf); KFree(Tm);
  EnumFontsA := R;
End;

{ ------------------------------------------------------------------ }
{ Transferts de blocs                                                }
{ ------------------------------------------------------------------ }

{ Source d'un transfert : surface, table de couleurs (DIB) et
  monochrome. Rend False si la source n'est pas lisible }
Function SrcInfo(D : LongInt; Var S : TSurf; Var Tab : LongInt;
                 Var Mono : Boolean; Var OX, OY : LongInt) : Boolean;
Var B : LongInt; Clip : TRect;
Begin
  SrcInfo := False;
  Tab := 0; Mono := False; OX := 0; OY := 0;
  If (D < 0) Or Not Dcs[D].Used Then Exit;
  If Dcs[D].Wnd >= 0 Then
  Begin
    If Not WndTarget(Dcs[D].Wnd, Dcs[D].Client, S, OX, OY, Clip) Then Exit;
  End
  Else If Dcs[D].Screen Then
  Begin
    S := Back;
  End
  Else
  Begin
    B := Dcs[D].Bmp;
    If B < 0 Then B := DefBmp;
    If Not BmpSurf(B, S) Then Exit;
    Tab := Gdis[B].I6;
    Mono := (Gdis[B].I7 And 4) <> 0;
  End;
  OX := OX + Dcs[D].VpX - Dcs[D].WinX;
  OY := OY + Dcs[D].VpY - Dcs[D].WinY;
  SrcInfo := True;
End;

{ Couleur Q (RGBQUAD) de l'entree I d'une table de DIB vers un indice
  de la palette systeme : comme Windows, une couleur presente dans la
  palette logique du contexte (de preference au meme indice) prend
  l'indice systeme realise de cette entree ; sinon la plus proche }
Function PalMatch(D, I, Q, C : LongInt) : LongInt;
Var P, N, E, J, R : LongInt;
Begin
  P := Dcs[D].Pal;
  If (P >= 0) And (P <> DefPal) And (Gdis[P].I3 <> 0) Then
  Begin
    N := Gdis[P].I2;
    R := ((Q Shr 16) And 255) Or (Q And $FF00) Or ((Q And 255) Shl 16);
    If I < N Then
    Begin
      E := Gdis[P].I1 + I * 4;
      If (MemL[0:E] And $FFFFFF) = R Then
      Begin
        PalMatch := Mem[0:Gdis[P].I3 + I];
        Exit;
      End;
    End;
    For J := 0 To N - 1 Do
      If (MemL[0:Gdis[P].I1 + J * 4] And $FFFFFF) = R Then
      Begin
        PalMatch := Mem[0:Gdis[P].I3 + J];
        Exit;
      End;
  End;
  PalMatch := GColor(C);
End;

{ Table de traduction source -> cible (XlatTab) ; False si identite }
Function BuildXlat(STab : LongInt; SMono : Boolean; D : LongInt) : Boolean;
Var I, Q, C : LongInt; Same : Boolean;
Begin
  BuildXlat := False;
  If SMono Then
  Begin
    For I := 0 To 255 Do XlatTab[I] := GColor(Dcs[D].BkColor);
    XlatTab[0] := GColor(Dcs[D].TextColor);
    BuildXlat := True;
    Exit;
  End;
  If (STab = 0) And (GTab = 0) Then Exit;
  If (STab <> 0) And (GTab <> 0) Then
  Begin
    Same := True;
    For I := 0 To 255 Do
      If MemL[0:STab + I * 4] <> MemL[0:GTab + I * 4] Then
      Begin
        Same := False;
        Break;
      End;
    If Same Then Exit;
  End;
  For I := 0 To 255 Do
  Begin
    If STab <> 0 Then
    Begin
      Q := MemL[0:STab + I * 4];
      C := ((Q Shr 16) And 255) Or (Q And $FF00) Or ((Q And 255) Shl 16);
      If GTab = 0 Then
        XlatTab[I] := PalMatch(D, I, Q And $FFFFFF, C)
      Else XlatTab[I] := GColor(C);
    End
    Else XlatTab[I] := GColor(IdxColor(I));
  End;
  BuildXlat := True;
End;

{ Combiner un point selon une ROP3 (P motif, S source, D cible) }
Function Rop3(Rop, P, S, D : LongInt) : LongInt;
Var R, I : LongInt;
Begin
  Case Rop Of
    SRCCOPY : Rop3 := S;
    SRCPAINT : Rop3 := S Or D;
    SRCAND : Rop3 := S And D;
    SRCINVERT : Rop3 := S Xor D;
    NOTSRCCOPY : Rop3 := (Not S) And 255;
    SRCERASE : Rop3 := S And Not D And 255;
    MERGEPAINT : Rop3 := (Not S Or D) And 255;
    NOTSRCERASE : Rop3 := (Not (S Or D)) And 255;
    MERGECOPY : Rop3 := P And S;
    DSTINVERT : Rop3 := (Not D) And 255;
    PATCOPY : Rop3 := P;
    PATINVERT : Rop3 := P Xor D;
    BLACKNESS : Rop3 := 0;
    WHITENESS : Rop3 := 255;
  Else
    R := 0;
    I := (Rop Shr 16) And 255;
    If (I And $01) <> 0 Then R := R Or (Not P And Not S And Not D);
    If (I And $02) <> 0 Then R := R Or (Not P And Not S And D);
    If (I And $04) <> 0 Then R := R Or (Not P And S And Not D);
    If (I And $08) <> 0 Then R := R Or (Not P And S And D);
    If (I And $10) <> 0 Then R := R Or (P And Not S And Not D);
    If (I And $20) <> 0 Then R := R Or (P And Not S And D);
    If (I And $40) <> 0 Then R := R Or (P And S And Not D);
    If (I And $80) <> 0 Then R := R Or (P And S And D);
    Rop3 := R And 255;
  End;
End;

{ Transfert (avec mise a l'echelle) de la source S vers le contexte
  courant (DcBegin deja fait). Coordonnees logiques de la cible }
Procedure BltCore(DX, DY, DW, DH : LongInt; Var S : TSurf; SX, SY, SW,
                  SH : LongInt; Xl : Boolean; Rop : LongInt);
Var X, Y, SXX, SYY, A, V, P, X0, X1, Y0, Y1, SRow, Pc, DMono : LongInt;
    Flip : Boolean; Simple : Boolean;
Begin
  If (DW = 0) Or (DH = 0) Or (SW = 0) Or (SH = 0) Then Exit;
  If DW < 0 Then
  Begin
    DX := DX + DW + 1; DW := -DW; SX := SX + SW - 1; SW := -SW;
  End;
  If DH < 0 Then
  Begin
    DY := DY + DH + 1; DH := -DH; SY := SY + SH - 1; SH := -SH;
  End;
  X0 := Max(DX, ClipX1); X1 := Min(DX + DW - 1, ClipX2);
  Y0 := Max(DY, ClipY1); Y1 := Min(DY + DH - 1, ClipY2);
  If (X0 > X1) Or (Y0 > Y1) Then Exit;
  Pc := 0;
  If (Dcs[GDc].Brush >= 0) Then Pc := GColor(Gdis[Dcs[GDc].Brush].I2);
  DMono := 0;
  If (Dcs[GDc].Bmp >= 0) And ((Gdis[Dcs[GDc].Bmp].I7 And 4) <> 0) And
     (Dcs[GDc].Wnd < 0) And Not Dcs[GDc].Screen Then DMono := 1;
  Simple := (Rop = SRCCOPY) And Not Xl And (DW = SW) And (DH = SH) And
            (DMono = 0);
  For Y := Y0 To Y1 Do
  Begin
    SYY := SY + ((Y - DY) * SH) Div DH;
    If (SYY < 0) Or (SYY >= S.H) Then Continue;
    SRow := S.Bits + SYY * S.Pitch;
    A := DS.Bits + (Y - DOY) * DS.Pitch - DOX;
    If Simple Then
    Begin
      SXX := SX + (X0 - DX);
      X := X0;
      If SXX < 0 Then
      Begin
        X := X - SXX; SXX := 0;
      End;
      If X <= X1 Then
        MoveMem(SRow + SXX, A + X, Min(X1 - X + 1, S.W - SXX));
      Continue;
    End;
    For X := X0 To X1 Do
    Begin
      SXX := SX + ((X - DX) * SW) Div DW;
      If (SXX < 0) Or (SXX >= S.W) Then Continue;
      V := Mem[0:SRow + SXX];
      If DMono = 1 Then
      Begin
        If Xl Then V := XlatTab[V];
        If V = GColor(Dcs[GDc].BkColor) Then V := 1 Else V := 0;
      End
      Else If Xl Then V := XlatTab[V];
      If Rop <> SRCCOPY Then V := Rop3(Rop, Pc, V, Mem[0:A + X]);
      Mem[0:A + X] := V;
    End;
  End;
  DcDirty(X0, Y0, X1, Y1);
End;

Function StretchBlt(Hdc, X, Y, W, H, Src, SX, SY, SW, SH, Rop : LongInt)
  : LongInt;
Var D, SD, STab, OX, OY : LongInt; S : TSurf; SMono, Xl : Boolean;
Begin
  StretchBlt := 1;
  D := DcOf(Hdc);
  If (Rop = PATCOPY) Or (Rop = BLACKNESS) Or (Rop = WHITENESS) Or
     (Rop = DSTINVERT) Or (Rop = PATINVERT) Then
  Begin
    StretchBlt := PatBlt(Hdc, X, Y, W, H, Rop);
    Exit;
  End;
  SD := DcOf(Src);
  If Not SrcInfo(SD, S, STab, SMono, OX, OY) Then Exit;
  If Not DcBegin(D) Then Exit;
  Xl := BuildXlat(STab, SMono, D);
  BltCore(X, Y, W, H, S, SX + OX, SY + OY, SW, SH, Xl, Rop);
End;

Function BitBlt(Hdc, X, Y, W, H, Src, SX, SY, Rop : LongInt) : LongInt;
Begin
  BitBlt := StretchBlt(Hdc, X, Y, W, H, Src, SX, SY, W, H, Rop);
End;

{ ------------------------------------------------------------------ }
{ DIB : BITMAPINFOHEADER +0 taille +4 largeur +8 hauteur +12 plans    }
{       +14 bits par point +16 compression +32 couleurs utilisees      }
{ ------------------------------------------------------------------ }

Function DibColors(Bmi : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := MemL[0:Bmi + 32];
  If (N = 0) And (MemW[0:Bmi + 14] <= 8) Then N := 1 Shl MemW[0:Bmi + 14];
  If MemW[0:Bmi + 14] > 8 Then N := 0;
  If MemL[0:Bmi + 16] = 3 Then N := 3;
  DibColors := N;
End;

Function DibPitch(W, Bpp : LongInt) : LongInt;
Begin
  DibPitch := ((W * Bpp + 31) Div 32) * 4;
End;

{ Table RGBQUAD (256 entrees) d'apres BITMAPINFO et Usage
  (0 DIB_RGB_COLORS, 1 DIB_PAL_COLORS : indices dans la palette du DC) }
Procedure DibTable(Bmi, Usage, D, Dst : LongInt);
Var I, N, T, P, E, Q : LongInt;
Begin
  FillMem(Dst, 1024, 0);
  N := DibColors(Bmi);
  If N > 256 Then N := 256;
  T := Bmi + MemL[0:Bmi];
  For I := 0 To N - 1 Do
    If Usage = 1 Then
    Begin
      Q := MemW[0:T + I * 2];
      If (D >= 0) And (Dcs[D].Pal >= 0) Then P := Dcs[D].Pal Else P := DefPal;
      If Q < Gdis[P].I2 Then
      Begin
        E := Gdis[P].I1 + Q * 4;
        MemL[0:Dst + I * 4] := (Mem[0:E] Shl 16) Or (Mem[0:E + 1] Shl 8) Or
                               Mem[0:E + 2];
      End;
    End
    Else MemL[0:Dst + I * 4] := MemL[0:T + I * 4] And $FFFFFF;
End;

{ Lire le point (X, Y) d'une DIB (Y depuis le haut) comme indice de la
  table (1, 4, 8 bits) ou couleur RGB (16, 24, 32 bits, avec bit 31) }
Function DibPix(Bits, W, H, Bpp, X, Y : LongInt; TopDown : Boolean)
  : LongInt;
Var Row, A, V : LongInt;
Begin
  If Not TopDown Then Y := H - 1 - Y;
  Row := Bits + Y * DibPitch(W, Bpp);
  Case Bpp Of
    8 : DibPix := Mem[0:Row + X];
    4 :
    Begin
      V := Mem[0:Row + X Div 2];
      If Odd(X) Then DibPix := V And 15 Else DibPix := V Shr 4;
    End;
    1 : DibPix := (Mem[0:Row + X Div 8] Shr (7 - X Mod 8)) And 1;
    24 :
    Begin
      A := Row + X * 3;
      DibPix := LongInt($80000000) Or (Mem[0:A + 2] Shl 16) Or
                (Mem[0:A + 1] Shl 8) Or Mem[0:A];
    End;
    32 : DibPix := LongInt($80000000) Or (MemL[0:Row + X * 4] And $FFFFFF);
    16 :
    Begin
      V := MemW[0:Row + X * 2];
      DibPix := LongInt($80000000) Or (((V Shr 10) And 31) Shl 19) Or
                (((V Shr 5) And 31) Shl 11) Or ((V And 31) Shl 3);
    End;
  Else
    DibPix := 0;
  End;
End;

{ Transferer une DIB (memoire de l'appelant) vers le contexte courant }
Procedure DibToDc(D, DX, DY, DW, DH, SX, SY, SW, SH, Bits, Bmi, Usage,
                  Rop : LongInt);
Var W, H, Bpp, X, Y, SXX, SYY, V, A, X0, X1, Y0, Y1, Tab, Q, P, N,
    T : LongInt;
    Top : Boolean;
Begin
  W := MemL[0:Bmi + 4]; H := MemL[0:Bmi + 8]; Bpp := MemW[0:Bmi + 14];
  Top := H < 0;
  If Top Then H := -H;
  If (DW = 0) Or (DH = 0) Or (SW = 0) Or (SH = 0) Then Exit;
  Tab := KAlloc(1024);
  DibTable(Bmi, Usage, D, Tab);
  For V := 0 To 255 Do
  Begin
    Q := MemL[0:Tab + V * 4];
    XlatTab[V] := GColor(((Q Shr 16) And 255) Or (Q And $FF00) Or
                         ((Q And 255) Shl 16));
  End;
  KFree(Tab);
  { DIB_PAL_COLORS : indices de la palette logique -> indices systeme
    realises (sans passer par RVB : les fondus de palette restent
    possibles) }
  If Usage = 1 Then
  Begin
    P := Dcs[D].Pal;
    If (P >= 0) And (Gdis[P].I3 <> 0) Then
    Begin
      N := Min(DibColors(Bmi), 256);
      T := Bmi + MemL[0:Bmi];
      For V := 0 To N - 1 Do
      Begin
        Q := MemW[0:T + V * 2];
        If Q < Gdis[P].I2 Then XlatTab[V] := Mem[0:Gdis[P].I3 + Q];
      End;
    End;
  End;
  If DW < 0 Then
  Begin
    DX := DX + DW + 1; DW := -DW; SX := SX + SW - 1; SW := -SW;
  End;
  If DH < 0 Then
  Begin
    DY := DY + DH + 1; DH := -DH; SY := SY + SH - 1; SH := -SH;
  End;
  X0 := Max(DX, ClipX1); X1 := Min(DX + DW - 1, ClipX2);
  Y0 := Max(DY, ClipY1); Y1 := Min(DY + DH - 1, ClipY2);
  If (X0 > X1) Or (Y0 > Y1) Then Exit;
  For Y := Y0 To Y1 Do
  Begin
    SYY := SY + ((Y - DY) * SH) Div DH;
    If (SYY < 0) Or (SYY >= H) Then Continue;
    A := DS.Bits + (Y - DOY) * DS.Pitch - DOX;
    For X := X0 To X1 Do
    Begin
      SXX := SX + ((X - DX) * SW) Div DW;
      If (SXX < 0) Or (SXX >= W) Then Continue;
      V := DibPix(Bits, W, H, Bpp, SXX, SYY, Top);
      If V < 0 Then
        V := GColor(((V Shr 16) And 255) Or (V And $FF00) Or
                    ((V And 255) Shl 16))
      Else V := XlatTab[V And 255];
      If Rop <> SRCCOPY Then V := Rop3(Rop, 0, V, Mem[0:A + X]);
      Mem[0:A + X] := V;
    End;
  End;
  DcDirty(X0, Y0, X1, Y1);
End;

Function StretchDIBits(Hdc, X, Y, W, H, SX, SY, SW, SH, Bits, Bmi, Usage,
  Rop : LongInt) : LongInt;
Var D, BH : LongInt;
Begin
  StretchDIBits := SH;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  BH := Abs(MemL[0:Bmi + 8]);
  { SY est mesure depuis le bas pour une DIB de bas en haut }
  If MemL[0:Bmi + 8] > 0 Then SY := BH - SY - SH;
  DibToDc(D, X, Y, W, H, SX, SY, SW, SH, Bits, Bmi, Usage, Rop);
End;

Function SetDIBitsToDevice(Hdc, X, Y, W, H, SX, SY, Start, Lines, Bits, Bmi,
  Usage : LongInt) : LongInt;
Var D, BH : LongInt;
Begin
  SetDIBitsToDevice := Lines;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  BH := Abs(MemL[0:Bmi + 8]);
  If MemL[0:Bmi + 8] > 0 Then SY := BH - SY - H;
  DibToDc(D, X, Y, W, H, SX, SY, W, H, Bits, Bmi, Usage, SRCCOPY);
End;

{ Creer un bitmap compatible (8 bits) a partir d'une DIB }
Function CreateDIBitmapK(Bmi, Bits, Usage : LongInt) : LongInt;
Var B, W, H, Y, X, V, Q, Tab : LongInt; Top : Boolean;
Begin
  W := MemL[0:Bmi + 4]; H := MemL[0:Bmi + 8];
  Top := H < 0;
  If Top Then H := -H;
  If Bits = 0 Then Bits := Bmi + MemL[0:Bmi] + DibColors(Bmi) * 4;
  B := BmpNew(W, H, 8, False);
  CreateDIBitmapK := B;
  If B < 0 Then Exit;
  Tab := KAlloc(1024);
  DibTable(Bmi, Usage, -1, Tab);
  For V := 0 To 255 Do
  Begin
    Q := MemL[0:Tab + V * 4];
    XlatTab[V] := ColorIdx(((Q Shr 16) And 255) Or (Q And $FF00) Or
                           ((Q And 255) Shl 16));
  End;
  KFree(Tab);
  For Y := 0 To H - 1 Do
    For X := 0 To W - 1 Do
    Begin
      V := DibPix(Bits, W, H, MemW[0:Bmi + 14], X, Y, Top);
      If V < 0 Then
        V := ColorIdx(((V Shr 16) And 255) Or (V And $FF00) Or
                      ((V And 255) Shl 16))
      Else V := XlatTab[V And 255];
      Mem[0:Gdis[B].I1 + Y * Gdis[B].I5 + X] := V;
    End;
End;

Function CreateDIBitmap(Hdc, Bih, Init, Bits, Bmi, Usage : LongInt)
  : LongInt;
Var B : LongInt;
Begin
  If ((Init And 4) <> 0) And (Bits <> 0) And (Bmi <> 0) Then
    B := CreateDIBitmapK(Bmi, Bits, Usage)
  Else
    B := BmpNew(MemL[0:Bih + 4], Abs(MemL[0:Bih + 8]), 8, False);
  CreateDIBitmap := GdiH(B);
End;

{ Section DIB : les bits restent au format de l'application }
Function CreateDIBSection(Hdc, Bmi, Usage, PBits, HSec, Ofs : LongInt)
  : LongInt;
Var B, W, H, Bpp, Pitch : LongInt;
Begin
  CreateDIBSection := 0;
  W := MemL[0:Bmi + 4]; H := MemL[0:Bmi + 8]; Bpp := MemW[0:Bmi + 14];
  B := GdiNew(goBitmap);
  If B < 0 Then Exit;
  Pitch := DibPitch(W, Bpp);
  Gdis[B].I1 := KAlloc(Pitch * Abs(H) + 16);
  Gdis[B].I2 := W; Gdis[B].I3 := Abs(H); Gdis[B].I4 := Bpp;
  Gdis[B].I5 := Pitch;
  Gdis[B].I7 := 1;
  If H < 0 Then Gdis[B].I7 := Gdis[B].I7 Or 2;
  If Bpp <= 8 Then
  Begin
    Gdis[B].I6 := KAlloc(1024);
    DibTable(Bmi, Usage, DcOf(Hdc), Gdis[B].I6);
  End;
  If PBits <> 0 Then MemL[0:PBits] := Gdis[B].I1;
  CreateDIBSection := GdiH(B);
End;

Function SetDIBColorTable(Hdc, Start, N, Rgbq : LongInt) : LongInt;
Var D, B : LongInt;
Begin
  SetDIBColorTable := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  B := Dcs[D].Bmp;
  If (B < 0) Or (Gdis[B].I6 = 0) Then Exit;
  N := Min(N, 256 - Start);
  MoveMem(Rgbq, Gdis[B].I6 + Start * 4, N * 4);
  SetDIBColorTable := N;
End;

Function GetDIBColorTable(Hdc, Start, N, Rgbq : LongInt) : LongInt;
Var D, B : LongInt;
Begin
  GetDIBColorTable := 0;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  B := Dcs[D].Bmp;
  If (B < 0) Or (Gdis[B].I6 = 0) Then Exit;
  N := Min(N, 256 - Start);
  MoveMem(Gdis[B].I6 + Start * 4, Rgbq, N * 4);
  GetDIBColorTable := N;
End;

{ Bitmap compatible avec un contexte (monochrome si le contexte est un
  contexte memoire avec le bitmap par defaut) }
Function CreateCompatibleBitmap(Hdc, W, H : LongInt) : LongInt;
Var D, B : LongInt; Mono : Boolean;
Begin
  D := DcOf(Hdc);
  Mono := (D >= 0) And (Dcs[D].Wnd < 0) And Not Dcs[D].Screen And
          ((Dcs[D].Bmp < 0) Or (Dcs[D].Bmp = DefBmp));
  B := BmpNew(W, H, 8, Mono);
  CreateCompatibleBitmap := GdiH(B);
End;

Function CreateDiscardableBitmap(Hdc, W, H : LongInt) : LongInt;
Begin
  CreateDiscardableBitmap := CreateCompatibleBitmap(Hdc, W, H);
End;

{ CreateBitmap : 1 bit (lignes alignees sur 16 bits) ou 8 bits }
Function CreateBitmap(W, H, Planes, Bpp, Bits : LongInt) : LongInt;
Var B, X, Y, WB : LongInt;
Begin
  B := BmpNew(W, H, 8, Bpp = 1);
  CreateBitmap := GdiH(B);
  If (B < 0) Or (Bits = 0) Then Exit;
  If Bpp = 1 Then
  Begin
    WB := ((W + 15) Div 16) * 2;
    For Y := 0 To H - 1 Do
      For X := 0 To W - 1 Do
        Mem[0:Gdis[B].I1 + Y * Gdis[B].I5 + X] :=
          (Mem[0:Bits + Y * WB + X Div 8] Shr (7 - X Mod 8)) And 1;
  End
  Else If Bpp = 8 Then
  Begin
    WB := ((W + 1) Div 2) * 2;
    For Y := 0 To H - 1 Do
      MoveMem(Bits + Y * WB, Gdis[B].I1 + Y * Gdis[B].I5, W);
  End;
End;

Function CreateBitmapIndirect(P : LongInt) : LongInt;
Begin
  CreateBitmapIndirect := CreateBitmap(MemL[0:P + 4], MemL[0:P + 8],
                          MemW[0:P + 16], MemW[0:P + 18], MemL[0:P + 20]);
End;

Function GetBitmapBits(H, N, Bits : LongInt) : LongInt;
Var B, Y, X, WB, V : LongInt;
Begin
  GetBitmapBits := 0;
  B := GdiOf(H, goBitmap);
  If B < 0 Then Exit;
  If (Gdis[B].I7 And 4) <> 0 Then
  Begin
    WB := ((Gdis[B].I2 + 15) Div 16) * 2;
    FillMem(Bits, Min(N, WB * Gdis[B].I3), 0);
    For Y := 0 To Gdis[B].I3 - 1 Do
      For X := 0 To Gdis[B].I2 - 1 Do
        If (Y * WB + X Div 8 < N) And
           (Mem[0:Gdis[B].I1 + Y * Gdis[B].I5 + X] <> 0) Then
        Begin
          V := Bits + Y * WB + X Div 8;
          Mem[0:V] := Mem[0:V] Or ($80 Shr (X Mod 8));
        End;
    GetBitmapBits := Min(N, WB * Gdis[B].I3);
    Exit;
  End;
  WB := ((Gdis[B].I2 + 1) Div 2) * 2;
  For Y := 0 To Gdis[B].I3 - 1 Do
    If (Y + 1) * WB <= N Then
      MoveMem(Gdis[B].I1 + Y * Gdis[B].I5, Bits + Y * WB, Gdis[B].I2);
  GetBitmapBits := Min(N, WB * Gdis[B].I3);
End;

Function SetBitmapBits(H, N, Bits : LongInt) : LongInt;
Var B, Y, X, WB : LongInt;
Begin
  SetBitmapBits := 0;
  B := GdiOf(H, goBitmap);
  If B < 0 Then Exit;
  If (Gdis[B].I7 And 4) <> 0 Then
  Begin
    WB := ((Gdis[B].I2 + 15) Div 16) * 2;
    For Y := 0 To Gdis[B].I3 - 1 Do
      For X := 0 To Gdis[B].I2 - 1 Do
        If Y * WB + X Div 8 < N Then
          Mem[0:Gdis[B].I1 + Y * Gdis[B].I5 + X] :=
            (Mem[0:Bits + Y * WB + X Div 8] Shr (7 - X Mod 8)) And 1;
    SetBitmapBits := N;
    Exit;
  End;
  WB := ((Gdis[B].I2 + 1) Div 2) * 2;
  For Y := 0 To Gdis[B].I3 - 1 Do
    If (Y + 1) * WB <= N Then
      MoveMem(Bits + Y * WB, Gdis[B].I1 + Y * Gdis[B].I5, Gdis[B].I2);
  SetBitmapBits := N;
End;

{ GetDIBits : bitmap -> DIB (8 bits ; table de couleurs remplie) }
Function GetDIBits(Hdc, H, Start, Lines, Bits, Bmi, Usage : LongInt)
  : LongInt;
Var B, W, Hh, Y, X, SY, Pitch, I, V, Bpp : LongInt;
Begin
  GetDIBits := 0;
  B := GdiOf(H, goBitmap);
  If B < 0 Then Exit;
  W := Gdis[B].I2; Hh := Gdis[B].I3;
  If MemW[0:Bmi + 14] = 0 Then
  Begin
    MemL[0:Bmi + 4] := W; MemL[0:Bmi + 8] := Hh;
    MemW[0:Bmi + 12] := 1; MemW[0:Bmi + 14] := 8;
    MemL[0:Bmi + 16] := 0; MemL[0:Bmi + 20] := ((W + 3) And Not 3) * Hh;
    MemL[0:Bmi + 32] := 0;
    GetDIBits := Hh;
    Exit;
  End;
  Bpp := MemW[0:Bmi + 14];
  For I := 0 To 255 Do
  Begin
    If Gdis[B].I6 <> 0 Then V := MemL[0:Gdis[B].I6 + I * 4]
    Else V := (SysPal[I * 3] Shl 16) Or (SysPal[I * 3 + 1] Shl 8) Or
              SysPal[I * 3 + 2];
    MemL[0:Bmi + MemL[0:Bmi] + I * 4] := V;
  End;
  If (Bits = 0) Or (Bpp <> 8) Then
  Begin
    GetDIBits := Hh;
    Exit;
  End;
  Pitch := DibPitch(W, 8);
  For Y := Start To Min(Start + Lines, Hh) - 1 Do
  Begin
    If (Gdis[B].I7 And 2) <> 0 Then SY := Hh - 1 - Y Else SY := Y;
    For X := 0 To W - 1 Do
      Mem[0:Bits + (Y - Start) * Pitch + X] :=
        Mem[0:Gdis[B].I1 + SY * Gdis[B].I5 + X];
  End;
  GetDIBits := Min(Lines, Hh - Start);
End;

Function SetDIBits(Hdc, H, Start, Lines, Bits, Bmi, Usage : LongInt)
  : LongInt;
Var B, W, Hh, Y, X, V, Q, Tab, SY : LongInt; Top : Boolean;
Begin
  SetDIBits := 0;
  B := GdiOf(H, goBitmap);
  If B < 0 Then Exit;
  W := MemL[0:Bmi + 4]; Hh := MemL[0:Bmi + 8];
  Top := Hh < 0;
  If Top Then Hh := -Hh;
  Tab := KAlloc(1024);
  DibTable(Bmi, Usage, DcOf(Hdc), Tab);
  For V := 0 To 255 Do
  Begin
    Q := MemL[0:Tab + V * 4];
    XlatTab[V] := ColorIdx(((Q Shr 16) And 255) Or (Q And $FF00) Or
                           ((Q And 255) Shl 16));
  End;
  KFree(Tab);
  For Y := 0 To Min(Hh, Gdis[B].I3) - 1 Do
  Begin
    If (Gdis[B].I7 And 2) <> 0 Then SY := Y Else SY := Gdis[B].I3 - 1 - Y;
    For X := 0 To Min(W, Gdis[B].I2) - 1 Do
    Begin
      V := DibPix(Bits, W, Hh, MemW[0:Bmi + 14], X, Y, Top);
      If V < 0 Then
        V := ColorIdx(((V Shr 16) And 255) Or (V And $FF00) Or
                      ((V And 255) Shl 16))
      Else V := XlatTab[V And 255];
      Mem[0:Gdis[B].I1 + SY * Gdis[B].I5 + X] := V;
    End;
  End;
  SetDIBits := Lines;
End;

{ ------------------------------------------------------------------ }
{ Informations sur le peripherique, impression                       }
{ ------------------------------------------------------------------ }

Function GetDeviceCaps(Hdc, I : LongInt) : LongInt;
Begin
  Case I Of
    0 : GetDeviceCaps := $400;      { DRIVERVERSION }
    2 : GetDeviceCaps := 1;         { TECHNOLOGY : raster }
    4 : GetDeviceCaps := 169;       { HORZSIZE mm }
    6 : GetDeviceCaps := 127;
    8 : GetDeviceCaps := ScrW;      { HORZRES }
    10 : GetDeviceCaps := ScrH;     { VERTRES }
    12 : GetDeviceCaps := 8;        { BITSPIXEL }
    14 : GetDeviceCaps := 1;        { PLANES }
    16 : GetDeviceCaps := -1;
    18 : GetDeviceCaps := 0;
    20 : GetDeviceCaps := 0;
    22 : GetDeviceCaps := 0;
    24 : GetDeviceCaps := 20;       { NUMCOLORS }
    26 : GetDeviceCaps := 0;
    28 : GetDeviceCaps := 1;
    38 : GetDeviceCaps := $7F99;    { RASTERCAPS (avec RC_PALETTE) }
    40 : GetDeviceCaps := 36;
    42 : GetDeviceCaps := 36;
    44 : GetDeviceCaps := 51;
    88 : GetDeviceCaps := 96;       { LOGPIXELSX }
    90 : GetDeviceCaps := 96;
    104 : GetDeviceCaps := 256;     { SIZEPALETTE }
    106 : GetDeviceCaps := 20;      { NUMRESERVED }
    108 : GetDeviceCaps := 18;      { COLORRES }
    116 : GetDeviceCaps := 60;      { VREFRESH }
  Else
    GetDeviceCaps := 0;
  End;
End;

Function GdiSetBatchLimit(N : LongInt) : LongInt;
Begin
  GdiSetBatchLimit := 1;
End;

Function GdiFlush : LongInt;
Begin
  GdiFlush := 1;
End;

Function Escape(Hdc, Esc, N, PIn, POut : LongInt) : LongInt;
Begin
  Escape := 0;
End;

Function StartDocA(Hdc, P : LongInt) : LongInt;
Begin
  StartDocA := -1;
End;

Function EndDoc(Hdc : LongInt) : LongInt;
Begin
  EndDoc := 0;
End;

Function AbortDoc(Hdc : LongInt) : LongInt;
Begin
  AbortDoc := 0;
End;

Function StartPage(Hdc : LongInt) : LongInt;
Begin
  StartPage := 0;
End;

Function EndPage(Hdc : LongInt) : LongInt;
Begin
  EndPage := 0;
End;

Function SetAbortProc(Hdc, P : LongInt) : LongInt;
Begin
  SetAbortProc := 1;
End;

{ ==================================================================== }
{ Partie 10 - API Win32 USER32                                         }
{ ==================================================================== }

Const
  HDesktop = HWndBase - 4;
  KProcToken = $7FFF0000;
  MF_POPUP = $10; MF_SEPARATOR = $800; MF_BYPOSITION = $400;
  MF_CHECKED = 8; MF_GRAYED = 1; MF_DISABLED = 2;

Type
  TMenuItemR = Record
    Used  : Boolean;
    Menu  : LongInt;
    Flags : LongInt;
    Id    : LongInt;
    Seq   : LongInt;
    Text  : String[63];
  End;

  TCursorR = Record
    Used : Boolean;
    HX, HY : LongInt;
    Map  : LongInt;     { 1024 octets : 0 transp. 1 noir 2 blanc 3 inv. }
  End;

Var
  MenuUsed  : Array[0..MaxMenu - 1] Of Boolean;
  MItems    : Array[0..MaxMenuItem - 1] Of TMenuItemR;
  MSeq      : LongInt;
  Cursors   : Array[0..31] Of TCursorR;
  AppCursor : LongInt;

Function ResFind(Module, Name, Typ : LongInt) : LongInt; Forward;
Function ResData(Module, Entry : LongInt; Var Size : LongInt) : LongInt;
  Forward;
Function AppModule(H : LongInt) : LongInt; Forward;

Function WndOfH(H : LongInt) : LongInt;
Begin
  WndOfH := WndOf(H);
End;

{ ------------------------------------------------------------------ }
{ Classes                                                            }
{ ------------------------------------------------------------------ }

Function ClassOfName(P : LongInt) : LongInt;
Var I : LongInt;
Begin
  ClassOfName := -1;
  If (P > 0) And (P < $10000) Then
  Begin
    For I := 0 To MaxClass - 1 Do
      If Classes[I].Used And (Classes[I].Atom = P) Then
      Begin
        ClassOfName := I;
        Exit;
      End;
    Case P Of
      $80 : ClassOfName := KClass[ikButton];
      $81 : ClassOfName := KClass[ikEdit];
      $82 : ClassOfName := KClass[ikStatic];
      $83 : ClassOfName := KClass[ikListBox];
      $84 : ClassOfName := KClass[ikScrollBar];
      $85 : ClassOfName := KClass[ikComboBox];
    End;
    Exit;
  End;
  ClassOfName := ClassFind(PStr(P));
End;

{ WNDCLASS : style, proc, cbClsExtra, cbWndExtra, hInstance, hIcon,
  hCursor, hbrBackground, lpszMenuName, lpszClassName }
Function RegisterClassA(P : LongInt) : LongInt;
Var I, N : LongInt; Nm : String;
Begin
  RegisterClassA := 0;
  N := MemL[0:P + 36];
  If (N > 0) And (N < $10000) Then Nm := '#' + IntStr(N) Else Nm := PStr(N);
  I := ClassFind(Nm);
  If (I >= 0) And (Classes[I].IKind = ikNone) Then
  Begin
    SetErr(1410);
    Exit;
  End;
  If I < 0 Then I := ClassAdd(Nm, 0, ikNone, 0);
  If I < 0 Then Exit;
  Classes[I].IKind := ikNone;
  Classes[I].Style := MemL[0:P];
  Classes[I].Proc := MemL[0:P + 4];
  Classes[I].ClsExtra := MemL[0:P + 8];
  Classes[I].WndExtra := MemL[0:P + 12];
  Classes[I].Inst := MemL[0:P + 16];
  Classes[I].Icon := MemL[0:P + 20];
  Classes[I].Cursor := MemL[0:P + 24];
  Classes[I].Brush := MemL[0:P + 28];
  Classes[I].MenuName := MemL[0:P + 32];
  If Classes[I].ClsExtra > 0 Then
    Classes[I].Extra := KAlloc(Classes[I].ClsExtra);
  RegisterClassA := Classes[I].Atom;
End;

Function UnregisterClassA(N, Inst : LongInt) : LongInt;
Var I : LongInt;
Begin
  I := ClassOfName(N);
  If (I >= 0) And (Classes[I].IKind = ikNone) Then Classes[I].Used := False;
  UnregisterClassA := Ord(I >= 0);
End;

Function GetClassInfoA(Inst, N, P : LongInt) : LongInt;
Var I : LongInt;
Begin
  GetClassInfoA := 0;
  I := ClassOfName(N);
  If I < 0 Then Exit;
  MemL[0:P] := Classes[I].Style;
  If Classes[I].Proc <> 0 Then MemL[0:P + 4] := Classes[I].Proc
  Else MemL[0:P + 4] := KProcToken + Classes[I].IKind;
  MemL[0:P + 8] := Classes[I].ClsExtra; MemL[0:P + 12] := Classes[I].WndExtra;
  MemL[0:P + 16] := Classes[I].Inst; MemL[0:P + 20] := Classes[I].Icon;
  MemL[0:P + 24] := Classes[I].Cursor; MemL[0:P + 28] := Classes[I].Brush;
  MemL[0:P + 32] := Classes[I].MenuName; MemL[0:P + 36] := N;
  GetClassInfoA := 1;
End;

Function GetClassNameA(H, Buf, N : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetClassNameA := 0;
  If W < 0 Then Exit;
  PutPStr(Buf, Classes[Wnds[W].Cls].Name, N);
  GetClassNameA := Length(Classes[Wnds[W].Cls].Name);
End;

Function SetClassLongA(H, I, V : LongInt) : LongInt;
Var W, C : LongInt;
Begin
  SetClassLongA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  C := Wnds[W].Cls;
  Case I Of
    -10 : Begin SetClassLongA := Classes[C].Brush; Classes[C].Brush := V End;
    -12 : Begin SetClassLongA := Classes[C].Cursor; Classes[C].Cursor := V End;
    -14 : Begin SetClassLongA := Classes[C].Icon; Classes[C].Icon := V End;
    -24 : Begin SetClassLongA := Classes[C].Proc; Classes[C].Proc := V End;
    -26 : Begin SetClassLongA := Classes[C].Style; Classes[C].Style := V End;
  Else
    If (I >= 0) And (I + 4 <= Classes[C].ClsExtra) Then
    Begin
      SetClassLongA := MemL[0:Classes[C].Extra + I];
      MemL[0:Classes[C].Extra + I] := V;
    End;
  End;
End;

Function GetClassLongA(H, I : LongInt) : LongInt;
Var W, C : LongInt;
Begin
  GetClassLongA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  C := Wnds[W].Cls;
  Case I Of
    -10 : GetClassLongA := Classes[C].Brush;
    -12 : GetClassLongA := Classes[C].Cursor;
    -14 : GetClassLongA := Classes[C].Icon;
    -24 : GetClassLongA := Classes[C].Proc;
    -26 : GetClassLongA := Classes[C].Style;
  Else
    If (I >= 0) And (I + 4 <= Classes[C].ClsExtra) Then
      GetClassLongA := MemL[0:Classes[C].Extra + I];
  End;
End;

{ ------------------------------------------------------------------ }
{ Creation et etat des fenetres                                      }
{ ------------------------------------------------------------------ }

Function CreateWindowExA(Ex, Cls, Name, Style, X, Y, W, H, Parent, Menu,
  Inst, Param : LongInt) : LongInt;
Var C, P, R : LongInt; Nm : String;
Begin
  CreateWindowExA := 0;
  C := ClassOfName(Cls);
  If C < 0 Then
  Begin
    KLog('CreateWindowExA : classe inconnue ' + PStr(Cls));
    SetErr(1407);
    Exit;
  End;
  P := WndOf(Parent);
  If (Parent <> 0) And (Parent <> HDesktop) And (P < 0) Then
  Begin
    SetErr(1400);
    Exit;
  End;
  If (Style And WS_CHILD) <> 0 Then
  Begin
    If P < 0 Then Exit;
  End
  Else
  Begin
    { fenetre de premier niveau : cadre par defaut }
    If (Style And WS_POPUP) = 0 Then
      Style := Style Or WS_CAPTION Or WS_BORDER;
  End;
  If (Name > 0) And (Name < $10000) Then Nm := ''
  Else Nm := PStr(Name);
  R := CreateW(Ex, C, Nm, Style, X, Y, W, H, P, Menu, Inst, Param);
  If (R >= 0) And Not IsChildW(R) Then
    KLog('Fenetre ' + HexStr(HwndOf(R), 8) + ' ' + Classes[C].Name + ' "' +
         Nm + '" ' + IntStr(Wnds[R].X) + ',' + IntStr(Wnds[R].Y) + ' ' +
         IntStr(Wnds[R].W) + 'x' + IntStr(Wnds[R].H) + ' style ' +
         HexStr(Style, 8));
  CreateWindowExA := HwndOf(R);
End;

Function CreateWindowA(Cls, Name, Style, X, Y, W, H, Parent, Menu, Inst,
  Param : LongInt) : LongInt;
Begin
  CreateWindowA := CreateWindowExA(0, Cls, Name, Style, X, Y, W, H, Parent,
                                   Menu, Inst, Param);
End;

Function DestroyWindow(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  DestroyWindow := Ord(W >= 0);
  If W >= 0 Then DestroyW(W);
End;

Function ShowWindow(H, Cmd : LongInt) : LongInt;
Var W : LongInt;
Begin
  ShowWindow := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  ShowWindow := Ord(Wnds[W].Visible);
  Case Cmd Of
    0 : ShowW(W, False, False);
    2, 6, 7 :
    Begin
      ShowW(W, True, False);
      If Not IsChildW(W) Then MinimizeW(W);
    End;
    3 :
    Begin
      ShowW(W, True, True);
      If Not IsChildW(W) Then MaximizeW(W);
    End;
    4, 8 : ShowW(W, True, False);
    9 :
    Begin
      ShowW(W, True, True);
      If Not IsChildW(W) Then RestoreW(W);
    End;
  Else
    ShowW(W, True, True);
  End;
End;

Function IsWindow(H : LongInt) : LongInt;
Begin
  IsWindow := Ord((WndOf(H) >= 0) Or (H = HDesktop));
End;

Function IsWindowVisible(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  IsWindowVisible := Ord((W >= 0) And WndVisible(W));
End;

Function IsWindowEnabled(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  IsWindowEnabled := Ord((W >= 0) And Wnds[W].Enabled);
End;

Function EnableWindow(H, En : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  EnableWindow := 0;
  If W < 0 Then Exit;
  EnableWindow := Ord(Not Wnds[W].Enabled);
  If Wnds[W].Enabled <> (En <> 0) Then
  Begin
    Wnds[W].Enabled := En <> 0;
    SendMsgW(W, WM_ENABLE, En, 0);
  End;
End;

Function IsIconic(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  IsIconic := Ord((W >= 0) And Wnds[W].Min);
End;

Function IsZoomed(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  IsZoomed := Ord((W >= 0) And Wnds[W].Max);
End;

Function IsChild(HP, H : LongInt) : LongInt;
Var W, P : LongInt;
Begin
  IsChild := 0;
  W := WndOf(H); P := WndOf(HP);
  While (W >= 0) And IsChildW(W) Do
  Begin
    W := Wnds[W].Parent;
    If W = P Then
    Begin
      IsChild := 1;
      Exit;
    End;
  End;
End;

Function GetParent(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetParent := 0;
  If W < 0 Then Exit;
  If IsChildW(W) Then GetParent := HwndOf(Wnds[W].Parent)
  Else GetParent := HwndOf(Wnds[W].Owner);
End;

Function SetParent(H, HP : LongInt) : LongInt;
Var W, P : LongInt;
Begin
  W := WndOf(H); P := WndOf(HP);
  SetParent := 0;
  If W < 0 Then Exit;
  SetParent := HwndOf(Wnds[W].Parent);
  If IsChildW(W) And (P >= 0) Then Wnds[W].Parent := P;
End;

Function GetDesktopWindow : LongInt;
Begin
  GetDesktopWindow := HDesktop;
End;

{ GetWindow : 0 premiere, 1 derniere, 2 suivante, 3 precedente,
  4 proprietaire, 5 premiere fille }
Function GetWindow(H, Cmd : LongInt) : LongInt;
Var W, I, Best, BS : LongInt;
Begin
  GetWindow := 0;
  W := WndOf(H);
  Case Cmd Of
    4 : If (W >= 0) And Not IsChildW(W) Then GetWindow := HwndOf(Wnds[W].Owner);
    5 :
    Begin
      Best := -1; BS := -1;
      For I := 0 To MaxWnd - 1 Do
        If Wnds[I].Used And IsChildW(I) And ((Wnds[I].Parent = W) Or
           ((H = HDesktop) And (W < 0))) And (Wnds[I].Seq > BS) Then
        Begin
          Best := I; BS := Wnds[I].Seq;
        End;
      If H = HDesktop Then
      Begin
        If ZCnt > 0 Then Best := ZList[ZCnt - 1];
      End;
      GetWindow := HwndOf(Best);
    End;
    0, 1, 2, 3 :
    Begin
      If W < 0 Then Exit;
      If Not IsChildW(W) Then
      Begin
        For I := 0 To ZCnt - 1 Do
          If ZList[I] = W Then
          Begin
            Case Cmd Of
              0 : GetWindow := HwndOf(ZList[ZCnt - 1]);
              1 : GetWindow := HwndOf(ZList[0]);
              2 : If I > 0 Then GetWindow := HwndOf(ZList[I - 1]);
              3 : If I < ZCnt - 1 Then GetWindow := HwndOf(ZList[I + 1]);
            End;
            Exit;
          End;
        Exit;
      End;
      { freres : ordre de creation (le plus recent en premier) }
      Best := -1;
      If Cmd = 2 Then BS := -1 Else BS := $7FFFFFFF;
      For I := 0 To MaxWnd - 1 Do
        If Wnds[I].Used And IsChildW(I) And
           (Wnds[I].Parent = Wnds[W].Parent) And (I <> W) Then
          If ((Cmd = 2) And (Wnds[I].Seq < Wnds[W].Seq) And
              (Wnds[I].Seq > BS)) Or
             ((Cmd = 3) And (Wnds[I].Seq > Wnds[W].Seq) And
              (Wnds[I].Seq < BS)) Then
          Begin
            Best := I; BS := Wnds[I].Seq;
          End;
      GetWindow := HwndOf(Best);
    End;
  End;
End;

Function GetTopWindow(H : LongInt) : LongInt;
Begin
  GetTopWindow := GetWindow(H, 5);
End;

Function GetActiveWindow : LongInt;
Begin
  GetActiveWindow := HwndOf(ActiveWin);
End;

Function SetActiveWindow(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  SetActiveWindow := HwndOf(ActiveWin);
  W := WndOf(H);
  If W >= 0 Then ActivateW(W);
End;

Function GetForegroundWindow : LongInt;
Begin
  GetForegroundWindow := HwndOf(ActiveWin);
End;

Function SetForegroundWindow(H : LongInt) : LongInt;
Begin
  SetActiveWindow(H);
  SetForegroundWindow := 1;
End;

Function BringWindowToTop(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  BringWindowToTop := Ord(W >= 0);
  If (W >= 0) And Not IsChildW(W) Then ActivateW(W);
End;

Function GetFocus : LongInt;
Begin
  GetFocus := HwndOf(FocusWin);
End;

Function SetFocus(H : LongInt) : LongInt;
Begin
  SetFocus := HwndOf(FocusWin);
  SetFocusW(WndOf(H));
End;

Function GetCapture : LongInt;
Begin
  GetCapture := HwndOf(CaptureWin);
End;

Function SetCapture(H : LongInt) : LongInt;
Begin
  SetCapture := HwndOf(CaptureWin);
  CaptureWin := WndOf(H);
End;

Function ReleaseCapture : LongInt;
Begin
  CaptureWin := -1;
  ReleaseCapture := 1;
End;

{ ------------------------------------------------------------------ }
{ Position et taille                                                 }
{ ------------------------------------------------------------------ }

Function MoveWindow(H, X, Y, W, Hh, Repaint : LongInt) : LongInt;
Var K : LongInt;
Begin
  K := WndOf(H);
  MoveWindow := Ord(K >= 0);
  If K >= 0 Then MoveW(K, X, Y, W, Hh, Repaint <> 0);
End;

Function SetWindowPos(H, After, X, Y, CX, CY, Flags : LongInt) : LongInt;
Var W : LongInt;
Begin
  SetWindowPos := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  If (Flags And 1) <> 0 Then
  Begin
    CX := Wnds[W].W; CY := Wnds[W].H;
  End;
  If (Flags And 2) <> 0 Then
  Begin
    X := Wnds[W].X; Y := Wnds[W].Y;
  End;
  If Not IsChildW(W) And ((Flags And 4) = 0) Then
  Begin
    If After = -1 Then Wnds[W].ExStyle := Wnds[W].ExStyle Or WS_EX_TOPMOST
    Else If After = -2 Then
      Wnds[W].ExStyle := Wnds[W].ExStyle And Not WS_EX_TOPMOST;
    If After = 1 Then ZBottom(W) Else ZTop(W);
    DirtyWnd(W);
  End;
  MoveW(W, X, Y, CX, CY, True);
  If (Flags And $40) <> 0 Then ShowW(W, True, (Flags And $10) = 0);
  If (Flags And $80) <> 0 Then ShowW(W, False, False);
  If ((Flags And $10) = 0) And ((Flags And $80) = 0) And Not IsChildW(W) And
     Wnds[W].Visible And ((Flags And 4) = 0) Then ActivateW(W);
  SetWindowPos := 1;
End;

Function GetWindowRect(H, P : LongInt) : LongInt;
Var W : LongInt; R : TRect;
Begin
  W := WndOf(H);
  If H = HDesktop Then
  Begin
    SetR(R, 0, 0, ScrW, ScrH);
    PutRectAt(P, R);
    GetWindowRect := 1;
    Exit;
  End;
  GetWindowRect := 0;
  If W < 0 Then Exit;
  WndScreenRect(W, R);
  PutRectAt(P, R);
  GetWindowRect := 1;
End;

Function GetClientRect(H, P : LongInt) : LongInt;
Var W : LongInt; R : TRect;
Begin
  W := WndOf(H);
  If H = HDesktop Then SetR(R, 0, 0, ScrW, ScrH)
  Else If W < 0 Then
  Begin
    GetClientRect := 0;
    Exit;
  End
  Else SetR(R, 0, 0, Wnds[W].CR - Wnds[W].CL, Wnds[W].CB - Wnds[W].CT);
  PutRectAt(P, R);
  GetClientRect := 1;
End;

Procedure NcSize(Style, Ex : LongInt; Menu : Boolean; Var B, T : LongInt);
Begin
  B := 0;
  If (Style And WS_THICKFRAME) <> 0 Then B := 4
  Else If ((Style And WS_DLGFRAME) <> 0) Or
          ((Ex And WS_EX_DLGMODALFRAME) <> 0) Then B := 3
  Else If (Style And WS_BORDER) <> 0 Then B := 1;
  If (Ex And WS_EX_CLIENTEDGE) <> 0 Then B := B + 2;
  T := B;
  If (Style And WS_CAPTION) = WS_CAPTION Then T := T + 19;
End;

Function AdjustWindowRectEx(P, Style, Menu, Ex : LongInt) : LongInt;
Var B, T : LongInt;
Begin
  If ((Style And WS_CHILD) = 0) And ((Style And WS_POPUP) = 0) Then
    Style := Style Or WS_CAPTION;
  NcSize(Style, Ex, Menu <> 0, B, T);
  MemL[0:P] := MemL[0:P] - B; MemL[0:P + 4] := MemL[0:P + 4] - T;
  MemL[0:P + 8] := MemL[0:P + 8] + B; MemL[0:P + 12] := MemL[0:P + 12] + B;
  AdjustWindowRectEx := 1;
End;

Function AdjustWindowRect(P, Style, Menu : LongInt) : LongInt;
Begin
  AdjustWindowRect := AdjustWindowRectEx(P, Style, Menu, 0);
End;

Function ClientToScreen(H, P : LongInt) : LongInt;
Var W, X, Y : LongInt;
Begin
  W := WndOf(H);
  ClientToScreen := 0;
  If W < 0 Then Exit;
  ClientScreenOrg(W, X, Y);
  MemL[0:P] := MemL[0:P] + X; MemL[0:P + 4] := MemL[0:P + 4] + Y;
  ClientToScreen := 1;
End;

Function ScreenToClient(H, P : LongInt) : LongInt;
Var W, X, Y : LongInt;
Begin
  W := WndOf(H);
  ScreenToClient := 0;
  If W < 0 Then Exit;
  ClientScreenOrg(W, X, Y);
  MemL[0:P] := MemL[0:P] - X; MemL[0:P + 4] := MemL[0:P + 4] - Y;
  ScreenToClient := 1;
End;

Function MapWindowPoints(HF, HT, P, N : LongInt) : LongInt;
Var W, FX, FY, TX, TY, I : LongInt;
Begin
  FX := 0; FY := 0; TX := 0; TY := 0;
  W := WndOf(HF);
  If W >= 0 Then ClientScreenOrg(W, FX, FY);
  W := WndOf(HT);
  If W >= 0 Then ClientScreenOrg(W, TX, TY);
  For I := 0 To N - 1 Do
  Begin
    MemL[0:P + I * 8] := MemL[0:P + I * 8] + FX - TX;
    MemL[0:P + I * 8 + 4] := MemL[0:P + I * 8 + 4] + FY - TY;
  End;
  MapWindowPoints := ((FY - TY) Shl 16) Or ((FX - TX) And $FFFF);
End;

Function WindowFromPoint(X, Y : LongInt) : LongInt;
Var T : LongInt;
Begin
  T := TopAt(X, Y);
  If T < 0 Then WindowFromPoint := HDesktop
  Else WindowFromPoint := HwndOf(ChildAt(T, X, Y));
End;

Function ChildWindowFromPoint(H, X, Y : LongInt) : LongInt;
Var W, OX, OY : LongInt;
Begin
  W := WndOf(H);
  ChildWindowFromPoint := 0;
  If W < 0 Then Exit;
  ClientScreenOrg(W, OX, OY);
  ChildWindowFromPoint := HwndOf(ChildAt(W, X + OX, Y + OY));
End;

{ ------------------------------------------------------------------ }
{ Texte et donnees des fenetres                                      }
{ ------------------------------------------------------------------ }

Function SetWindowTextA(H, S : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  SetWindowTextA := 0;
  If W < 0 Then Exit;
  SetWindowTextA := 1;
  SendMsgW(W, WM_SETTEXT, 0, S);
End;

Function GetWindowTextA(H, Buf, N : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetWindowTextA := 0;
  If W < 0 Then Exit;
  GetWindowTextA := SendMsgW(W, WM_GETTEXT, N, Buf);
End;

Function GetWindowTextLengthA(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetWindowTextLengthA := 0;
  If W >= 0 Then GetWindowTextLengthA := Length(Wnds[W].Text);
End;

Function GetWindowLongA(H, I : LongInt) : LongInt;
Var W : LongInt;
Begin
  GetWindowLongA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  Case I Of
    -4 : If Wnds[W].Proc <> 0 Then GetWindowLongA := Wnds[W].Proc
         Else GetWindowLongA := KProcToken + Wnds[W].IKind;
    -6 : GetWindowLongA := Wnds[W].Inst;
    -8 : GetWindowLongA := HwndOf(Wnds[W].Owner);
    -12 : GetWindowLongA := Wnds[W].Id;
    -16 :
    Begin
      GetWindowLongA := Wnds[W].Style;
      If Wnds[W].Visible Then GetWindowLongA := Wnds[W].Style Or WS_VISIBLE;
    End;
    -20 : GetWindowLongA := Wnds[W].ExStyle;
    -21 : GetWindowLongA := Wnds[W].UserData;
  Else
    If (Wnds[W].IKind = ikDialog) And (I = 4) Then
      GetWindowLongA := Wnds[W].DlgProc
    Else If (Wnds[W].IKind = ikDialog) And (I = 0) Then
      GetWindowLongA := Wnds[W].DlgResult
    Else If (I >= 0) And (I + 4 <= Wnds[W].ExtraSz) Then
      GetWindowLongA := MemL[0:Wnds[W].Extra + I]
    Else If (Wnds[W].IKind = ikDialog) And (I = 8) Then
      GetWindowLongA := Wnds[W].UserData;
  End;
End;

Function SetWindowLongA(H, I, V : LongInt) : LongInt;
Var W : LongInt;
Begin
  SetWindowLongA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  SetWindowLongA := GetWindowLongA(H, I);
  Case I Of
    -4 :
      If (V >= KProcToken) And (V < KProcToken + 64) Then Wnds[W].Proc := 0
      Else Wnds[W].Proc := V;
    -6 : Wnds[W].Inst := V;
    -8 : Wnds[W].Owner := WndOf(V);
    -12 : Wnds[W].Id := V;
    -16 :
    Begin
      Wnds[W].Style := V And Not WS_VISIBLE;
      CalcNc(W);
      Wnds[W].NeedNc := True;
    End;
    -20 : Wnds[W].ExStyle := V;
    -21 : Wnds[W].UserData := V;
  Else
    If (Wnds[W].IKind = ikDialog) And (I = 4) Then Wnds[W].DlgProc := V
    Else If (Wnds[W].IKind = ikDialog) And (I = 0) Then Wnds[W].DlgResult := V
    Else If (I >= 0) And (I + 4 <= Wnds[W].ExtraSz) Then
      MemL[0:Wnds[W].Extra + I] := V
    Else If (Wnds[W].IKind = ikDialog) And (I = 8) Then Wnds[W].UserData := V;
  End;
End;

Function GetWindowWord(H, I : LongInt) : LongInt;
Var W : LongInt;
Begin
  GetWindowWord := 0;
  W := WndOf(H);
  If (W >= 0) And (I >= 0) And (I + 2 <= Wnds[W].ExtraSz) Then
    GetWindowWord := MemW[0:Wnds[W].Extra + I]
  Else If (W >= 0) And (I = -12) Then GetWindowWord := Wnds[W].Id And $FFFF;
End;

Function SetWindowWord(H, I, V : LongInt) : LongInt;
Var W : LongInt;
Begin
  SetWindowWord := 0;
  W := WndOf(H);
  If (W >= 0) And (I >= 0) And (I + 2 <= Wnds[W].ExtraSz) Then
  Begin
    SetWindowWord := MemW[0:Wnds[W].Extra + I];
    MemW[0:Wnds[W].Extra + I] := V;
  End;
End;

{ Proprietes (SetPropA) }
Function PropName(P : LongInt) : String;
Begin
  If (P > 0) And (P < $10000) Then PropName := '#' + IntStr(P)
  Else PropName := UpStr(PStr(P));
End;

Function SetPropA(H, S, V : LongInt) : LongInt;
Var W, I, F : LongInt; N : String;
Begin
  SetPropA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  N := PropName(S);
  F := -1;
  For I := 0 To MaxProp - 1 Do
    If Props[I].Used And (Props[I].Wnd = W) And (Props[I].Name = N) Then
    Begin
      Props[I].Val := V;
      SetPropA := 1;
      Exit;
    End
    Else If Not Props[I].Used And (F < 0) Then F := I;
  If F < 0 Then Exit;
  Props[F].Used := True; Props[F].Wnd := W; Props[F].Name := N;
  Props[F].Val := V;
  SetPropA := 1;
End;

Function GetPropA(H, S : LongInt) : LongInt;
Var W, I : LongInt; N : String;
Begin
  GetPropA := 0;
  W := WndOf(H);
  N := PropName(S);
  For I := 0 To MaxProp - 1 Do
    If Props[I].Used And (Props[I].Wnd = W) And (Props[I].Name = N) Then
    Begin
      GetPropA := Props[I].Val;
      Exit;
    End;
End;

Function RemovePropA(H, S : LongInt) : LongInt;
Var W, I : LongInt; N : String;
Begin
  RemovePropA := 0;
  W := WndOf(H);
  N := PropName(S);
  For I := 0 To MaxProp - 1 Do
    If Props[I].Used And (Props[I].Wnd = W) And (Props[I].Name = N) Then
    Begin
      RemovePropA := Props[I].Val;
      Props[I].Used := False;
      Exit;
    End;
End;

{ ------------------------------------------------------------------ }
{ Messages                                                           }
{ ------------------------------------------------------------------ }

Function SendMessageA(H, Msg, WP, LP : LongInt) : LongInt;
Var I : LongInt;
Begin
  SendMessageA := 0;
  If H = $FFFF Then
  Begin
    For I := 0 To ZCnt - 1 Do
      If Wnds[ZList[I]].Used And (Wnds[ZList[I]].IKind = ikNone) Then
        SendMsgW(ZList[I], Msg, WP, LP);
    Exit;
  End;
  SendMessageA := SendMsgW(WndOf(H), Msg, WP, LP);
End;

Function PostMessageA(H, Msg, WP, LP : LongInt) : LongInt;
Var I : LongInt;
Begin
  If H = 0 Then
  Begin
    PostMessageA := Ord(QPost(CurT, 0, Msg, WP, LP));
    Exit;
  End;
  If H = $FFFF Then
  Begin
    For I := 0 To ZCnt - 1 Do
      If Wnds[ZList[I]].Used And (Wnds[ZList[I]].IKind = ikNone) Then
        PostMsgW(ZList[I], Msg, WP, LP);
    PostMessageA := 1;
    Exit;
  End;
  PostMessageA := Ord(PostMsgW(WndOf(H), Msg, WP, LP));
End;

Function PostThreadMessageA(Tid, Msg, WP, LP : LongInt) : LongInt;
Begin
  PostThreadMessageA := Ord(QPost(ThreadOfId(Tid), 0, Msg, WP, LP));
End;

Procedure PostQuitMessage(Code : LongInt);
Begin
  Threads[CurT].QuitFlag := True;
  Threads[CurT].QuitCode := Code;
End;

Procedure PutMsg(P : LongInt; Var M : TMsgRec);
Begin
  MemL[0:P] := M.Hwnd; MemL[0:P + 4] := M.Msg; MemL[0:P + 8] := M.WP;
  MemL[0:P + 12] := M.LP; MemL[0:P + 16] := M.Time; MemL[0:P + 20] := M.X;
  MemL[0:P + 24] := M.Y;
End;

Function GetMessageA(P, H, MinM, MaxM : LongInt) : LongInt;
Var M : TMsgRec;
Begin
  While Not KPeekMsg(CurT, M, H, MinM, MaxM, True) Do
  Begin
    If CurT = 0 Then
    Begin
      ProcessInput;
      Idle;
    End
    Else
    Begin
      Threads[CurT].State := tsMsg;
      Threads[CurT].WakeAt := -1;
      KSchedule;
      Threads[CurT].State := tsReady;
    End;
  End;
  PutMsg(P, M);
  GetMessageA := Ord(M.Msg <> WM_QUIT);
End;

Function PeekMessageA(P, H, MinM, MaxM, Remove : LongInt) : LongInt;
Var M : TMsgRec;
Begin
  If (Remove And 2) = 0 Then KYield;
  If KPeekMsg(CurT, M, H, MinM, MaxM, (Remove And 1) <> 0) Then
  Begin
    PutMsg(P, M);
    PeekMessageA := 1;
  End
  Else PeekMessageA := 0;
End;

Function WaitMessage : LongInt;
Begin
  If Not MsgPending(CurT) Then
  Begin
    Threads[CurT].State := tsMsg;
    Threads[CurT].WakeAt := -1;
    KSchedule;
    Threads[CurT].State := tsReady;
  End;
  WaitMessage := 1;
End;

Function GetMessageTime : LongInt;
Begin
  GetMessageTime := Ticks;
End;

Function GetMessagePos : LongInt;
Begin
  GetMessagePos := (CurY Shl 16) Or CurX;
End;

Function TranslateMessage(P : LongInt) : LongInt;
Var M, Sc, Ch : LongInt;
Begin
  TranslateMessage := 0;
  M := MemL[0:P + 4];
  If (M <> WM_KEYDOWN) And (M <> WM_SYSKEYDOWN) Then Exit;
  Sc := (MemL[0:P + 12] Shr 16) And $FF;
  If (MemL[0:P + 12] And $01000000) <> 0 Then
  Begin
    If MemL[0:P + 8] = $0D Then Ch := 13 Else Exit;
  End
  Else Ch := ScanToChar(Sc);
  If (KeyState[$11] And $80) <> 0 Then
  Begin
    If (Ch >= 97) And (Ch <= 122) Then Ch := Ch - 96
    Else If (Ch >= 65) And (Ch <= 90) Then Ch := Ch - 64;
  End;
  If Ch = 0 Then Exit;
  If M = WM_KEYDOWN Then
    QPost(CurT, MemL[0:P], WM_CHAR, Ch, MemL[0:P + 12])
  Else
    QPost(CurT, MemL[0:P], WM_SYSCHAR, Ch, MemL[0:P + 12]);
  TranslateMessage := 1;
End;

Function DispatchMessageA(P : LongInt) : LongInt;
Var W, Msg : LongInt;
Begin
  DispatchMessageA := 0;
  Msg := MemL[0:P + 4];
  If (Msg = WM_TIMER) And (MemL[0:P + 12] <> 0) Then
  Begin
    DispatchMessageA := CallProc(MemL[0:P + 12], MemL[0:P], WM_TIMER,
                                 MemL[0:P + 8], Ticks);
    Exit;
  End;
  W := WndOf(MemL[0:P]);
  If W < 0 Then Exit;
  DispatchMessageA := SendMsgW(W, Msg, MemL[0:P + 8], MemL[0:P + 12]);
  { WM_PAINT non traite : valider pour ne pas boucler }
  If (Msg = WM_PAINT) And Wnds[W].Used Then
  Begin
    SetR(Wnds[W].Upd, 0, 0, 0, 0);
    Wnds[W].UpdErase := False;
  End;
End;

Function SetTimer(H, Id, Ms, Proc : LongInt) : LongInt;
Var I, W, F : LongInt;
Begin
  SetTimer := 0;
  W := WndOf(H);
  If Ms < 10 Then Ms := 10;
  F := -1;
  For I := 0 To MaxTimer - 1 Do
    If WTimers[I].Used And (WTimers[I].Wnd = W) And (W >= 0) And
       (WTimers[I].Id = Id) Then F := I;
  If F < 0 Then
    For I := 0 To MaxTimer - 1 Do
      If Not WTimers[I].Used Then
      Begin
        F := I;
        Break;
      End;
  If F < 0 Then Exit;
  If W < 0 Then Id := F + 1;
  WTimers[F].Used := True; WTimers[F].Wnd := W; WTimers[F].Id := Id;
  WTimers[F].Elapse := Ms; WTimers[F].Next := Ticks + Ms;
  WTimers[F].Proc := Proc; WTimers[F].Thread := CurT;
  SetTimer := Id;
End;

Function KillTimer(H, Id : LongInt) : LongInt;
Var I, W : LongInt;
Begin
  KillTimer := 0;
  W := WndOf(H);
  For I := 0 To MaxTimer - 1 Do
    If WTimers[I].Used And (WTimers[I].Wnd = W) And (WTimers[I].Id = Id) Then
    Begin
      WTimers[I].Used := False;
      KillTimer := 1;
    End;
End;

{ ------------------------------------------------------------------ }
{ Peinture                                                           }
{ ------------------------------------------------------------------ }

Function GetDC(H : LongInt) : LongInt;
Var W, R, D : LongInt;
Begin
  If (H = 0) Or (H = HDesktop) Then
  Begin
    R := DcNew(-1, False);
    If R <> 0 Then Dcs[DcOf(R)].Screen := True;
    GetDC := R;
    Exit;
  End;
  W := WndOf(H);
  GetDC := 0;
  If W < 0 Then Exit;
  If (Classes[Wnds[W].Cls].Style And CS_OWNDC) <> 0 Then
  Begin
    If (Wnds[W].OwnDC = 0) Or (DcOf(Wnds[W].OwnDC) < 0) Then
    Begin
      Wnds[W].OwnDC := DcNew(W, True);
      If Wnds[W].OwnDC <> 0 Then Dcs[DcOf(Wnds[W].OwnDC)].Owned := True;
    End;
    D := DcOf(Wnds[W].OwnDC);
    If D >= 0 Then Dcs[D].HasPaint := False;
    GetDC := Wnds[W].OwnDC;
    Exit;
  End;
  GetDC := DcNew(W, True);
End;

Function GetWindowDC(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  If W < 0 Then GetWindowDC := GetDC(0) Else GetWindowDC := DcNew(W, False);
End;

Function GetDCEx(H, Rgn, Flags : LongInt) : LongInt;
Begin
  GetDCEx := GetDC(H);
End;

Function ReleaseDC(H, Hdc : LongInt) : LongInt;
Var D : LongInt;
Begin
  ReleaseDC := 1;
  D := DcOf(Hdc);
  If (D < 0) Or Dcs[D].Owned Then Exit;
  DcFree(D);
End;

Function KBrushOf(Br : LongInt) : LongInt; Forward;

{ Effacer le fond d'une fenetre avec le pinceau de sa classe }
Procedure EraseBkgnd(W, Hdc : LongInt);
Var B, D : LongInt;
Begin
  B := KBrushOf(Classes[Wnds[W].Cls].Brush);
  D := DcOf(Hdc);
  If (B < 0) Or Not DcBegin(D) Then Exit;
  BrushFill(ClipX1, ClipY1, ClipX2, ClipY2, B);
  DcDirtyAll;
End;

{ PAINTSTRUCT : hdc, fErase, rcPaint, fRestore, fIncUpdate, reserve }
Function BeginPaint(H, P : LongInt) : LongInt;
Var W, Hdc, D : LongInt; R : TRect; Er : Boolean;
Begin
  BeginPaint := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  R := Wnds[W].Upd;
  Er := Wnds[W].UpdErase;
  SetR(Wnds[W].Upd, 0, 0, 0, 0);
  Wnds[W].UpdErase := False;
  Hdc := GetDC(H);
  D := DcOf(Hdc);
  If D >= 0 Then
  Begin
    Dcs[D].HasPaint := True;
    Dcs[D].PaintR := R;
  End;
  If Er Then
    If SendMsgW(W, WM_ERASEBKGND, Hdc, 0) = 0 Then Er := True
    Else Er := False;
  FillMem(P, 64, 0);
  MemL[0:P] := Hdc;
  MemL[0:P + 4] := Ord(Er);
  PutRectAt(P + 8, R);
  BeginPaint := Hdc;
End;

Function EndPaint(H, P : LongInt) : LongInt;
Var D : LongInt;
Begin
  D := DcOf(MemL[0:P]);
  If D >= 0 Then Dcs[D].HasPaint := False;
  ReleaseDC(H, MemL[0:P]);
  DirtyWnd(WndOf(H));
  EndPaint := 1;
End;

Function InvalidateRect(H, P, Erase : LongInt) : LongInt;
Var W : LongInt; R : TRect;
Begin
  InvalidateRect := 1;
  W := WndOf(H);
  If W < 0 Then
  Begin
    If (H = 0) Or (H = HDesktop) Then MarkAll;
    Exit;
  End;
  If P = 0 Then SetR(R, 0, 0, 30000, 30000) Else GetRectAt(P, R);
  InvalW(W, R, Erase <> 0);
End;

Function InvalidateRgn(H, Rgn, Erase : LongInt) : LongInt;
Var W, I : LongInt; R : TRect;
Begin
  InvalidateRgn := 1;
  W := WndOf(H);
  If W < 0 Then Exit;
  I := GdiOf(Rgn, goRegion);
  If I < 0 Then SetR(R, 0, 0, 30000, 30000)
  Else SetR(R, Gdis[I].I1, Gdis[I].I2, Gdis[I].I3, Gdis[I].I4);
  InvalW(W, R, Erase <> 0);
End;

Function ValidateRect(H, P : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  If W >= 0 Then SetR(Wnds[W].Upd, 0, 0, 0, 0);
  ValidateRect := 1;
End;

Function ValidateRgn(H, Rgn : LongInt) : LongInt;
Begin
  ValidateRgn := ValidateRect(H, 0);
End;

Function GetUpdateRgn(H, Rgn, Erase : LongInt) : LongInt;
Var W, I : LongInt;
Begin
  GetUpdateRgn := 1;
  W := WndOf(H);
  I := GdiOf(Rgn, goRegion);
  If (W < 0) Or (I < 0) Then Exit;
  Gdis[I].I1 := Wnds[W].Upd.L; Gdis[I].I2 := Wnds[W].Upd.T;
  Gdis[I].I3 := Wnds[W].Upd.R; Gdis[I].I4 := Wnds[W].Upd.B;
  GetUpdateRgn := RgnType(I);
End;

Function GetUpdateRect(H, P, Erase : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetUpdateRect := 0;
  If W < 0 Then Exit;
  If P <> 0 Then PutRectAt(P, Wnds[W].Upd);
  GetUpdateRect := Ord(HasUpdate(W));
End;

Function UpdateWindow(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  UpdateWindow := 1;
  W := WndOf(H);
  If (W < 0) Or Not HasUpdate(W) Then Exit;
  If Wnds[W].IKind <> ikNone Then Exit;
  SendMsgW(W, WM_PAINT, 0, 0);
  SetR(Wnds[W].Upd, 0, 0, 0, 0);
End;

Function RedrawWindow(H, P, Rgn, Flags : LongInt) : LongInt;
Begin
  InvalidateRect(H, P, Flags And 4);
  If (Flags And $100) <> 0 Then UpdateWindow(H);
  RedrawWindow := 1;
End;

{ ScrollDC : deplacer une zone d'un contexte }
Function ScrollDC(Hdc, DX, DY, PScroll, PClip, Rgn, PUpd : LongInt)
  : LongInt;
Var D, Y, A, S : LongInt; R : TRect; Row : LongInt;
Begin
  ScrollDC := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  If PScroll <> 0 Then GetRectAt(PScroll, R)
  Else SetR(R, ClipX1, ClipY1, ClipX2 + 1, ClipY2 + 1);
  R.L := Max(R.L, ClipX1); R.T := Max(R.T, ClipY1);
  R.R := Min(R.R, ClipX2 + 1); R.B := Min(R.B, ClipY2 + 1);
  If (R.L >= R.R) Or (R.T >= R.B) Then Exit;
  Row := KAlloc(R.R - R.L + 16);
  If DY > 0 Then
  Begin
    For Y := R.B - 1 - DY DownTo R.T Do
    Begin
      S := DS.Bits + (Y - DOY) * DS.Pitch + (R.L - DOX);
      A := DS.Bits + (Y + DY - DOY) * DS.Pitch + (R.L + DX - DOX);
      MoveMem(S, Row, R.R - R.L);
      MoveMem(Row, A, R.R - R.L - Abs(DX));
    End;
  End
  Else
    For Y := R.T - DY To R.B - 1 Do
    Begin
      S := DS.Bits + (Y - DOY) * DS.Pitch + (R.L - DOX);
      A := DS.Bits + (Y + DY - DOY) * DS.Pitch + (R.L + DX - DOX);
      MoveMem(S, Row, R.R - R.L);
      MoveMem(Row, A, R.R - R.L - Abs(DX));
    End;
  KFree(Row);
  DcDirty(R.L, R.T, R.R, R.B);
  If PUpd <> 0 Then PutRectAt(PUpd, R);
End;

Function ScrollWindow(H, DX, DY, PR, PC : LongInt) : LongInt;
Begin
  InvalidateRect(H, 0, 1);
  ScrollWindow := 1;
End;

{ ------------------------------------------------------------------ }
{ Rectangles                                                         }
{ ------------------------------------------------------------------ }

Function SetRect(P, L0, T0, R0, B0 : LongInt) : LongInt;
Begin
  MemL[0:P] := L0; MemL[0:P + 4] := T0; MemL[0:P + 8] := R0;
  MemL[0:P + 12] := B0;
  SetRect := 1;
End;

Function SetRectEmpty(P : LongInt) : LongInt;
Begin
  SetRectEmpty := SetRect(P, 0, 0, 0, 0);
End;

Function CopyRect(D, S : LongInt) : LongInt;
Begin
  MoveMem(S, D, 16);
  CopyRect := 1;
End;

Function OffsetRect(P, DX, DY : LongInt) : LongInt;
Begin
  MemL[0:P] := MemL[0:P] + DX; MemL[0:P + 8] := MemL[0:P + 8] + DX;
  MemL[0:P + 4] := MemL[0:P + 4] + DY; MemL[0:P + 12] := MemL[0:P + 12] + DY;
  OffsetRect := 1;
End;

Function InflateRect(P, DX, DY : LongInt) : LongInt;
Begin
  MemL[0:P] := MemL[0:P] - DX; MemL[0:P + 8] := MemL[0:P + 8] + DX;
  MemL[0:P + 4] := MemL[0:P + 4] - DY; MemL[0:P + 12] := MemL[0:P + 12] + DY;
  InflateRect := 1;
End;

Function IntersectRect(D, A, B : LongInt) : LongInt;
Var RA, RB, R : TRect;
Begin
  GetRectAt(A, RA); GetRectAt(B, RB);
  If RInter(R, RA, RB) Then
  Begin
    PutRectAt(D, R);
    IntersectRect := 1;
  End
  Else
  Begin
    SetR(R, 0, 0, 0, 0);
    PutRectAt(D, R);
    IntersectRect := 0;
  End;
End;

Function UnionRect(D, A, B : LongInt) : LongInt;
Var RA, RB : TRect;
Begin
  GetRectAt(A, RA); GetRectAt(B, RB);
  RUnion(RA, RB);
  PutRectAt(D, RA);
  UnionRect := 1;
End;

Function EqualRect(A, B : LongInt) : LongInt;
Begin
  EqualRect := Ord((MemL[0:A] = MemL[0:B]) And
    (MemL[0:A + 4] = MemL[0:B + 4]) And (MemL[0:A + 8] = MemL[0:B + 8]) And
    (MemL[0:A + 12] = MemL[0:B + 12]));
End;

Function IsRectEmpty(P : LongInt) : LongInt;
Begin
  IsRectEmpty := Ord((MemL[0:P] >= MemL[0:P + 8]) Or
                     (MemL[0:P + 4] >= MemL[0:P + 12]));
End;

Function PtInRect(P, X, Y : LongInt) : LongInt;
Begin
  PtInRect := Ord((X >= MemL[0:P]) And (X < MemL[0:P + 8]) And
                  (Y >= MemL[0:P + 4]) And (Y < MemL[0:P + 12]));
End;

{ ------------------------------------------------------------------ }
{ Dessin USER (FillRect, DrawText, DrawEdge...)                      }
{ ------------------------------------------------------------------ }

Function SysColorRGB(I : LongInt) : LongInt;
Begin
  Case I Of
    0, 4, 10, 11, 15, 22 : SysColorRGB := $C0C0C0;
    1 : SysColorRGB := $808000;
    2, 13 : SysColorRGB := $800000;
    3, 12, 16, 17 : SysColorRGB := $808080;
    5, 9, 14, 20 : SysColorRGB := $FFFFFF;
    19 : SysColorRGB := $C0C0C0;
    24 : SysColorRGB := $E1FFFF;
  Else
    SysColorRGB := 0;
  End;
End;

Function GetSysColor(I : LongInt) : LongInt;
Begin
  GetSysColor := SysColorRGB(I);
End;

Function SetSysColors(N, PE, PC : LongInt) : LongInt;
Begin
  SetSysColors := 1;
End;

Var
  SysBrush : Array[0..30] Of LongInt;

{ Pinceau : poignee, ou COLOR_xxx + 1 (classes) }
Function KBrushOf(Br : LongInt) : LongInt;
Begin
  KBrushOf := -1;
  If (Br > 0) And (Br <= 31) Then
  Begin
    If SysBrush[Br - 1] = 0 Then
      SysBrush[Br - 1] := CreateSolidBrush(SysColorRGB(Br - 1));
    KBrushOf := GdiOf(SysBrush[Br - 1], goBrush);
    Exit;
  End;
  KBrushOf := GdiOf(Br, goBrush);
End;

Function GetSysColorBrush(I : LongInt) : LongInt;
Begin
  GetSysColorBrush := GdiH(KBrushOf(I + 1));
End;

Function FillRect(Hdc, P, Br : LongInt) : LongInt;
Var D : LongInt; R : TRect;
Begin
  FillRect := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  BrushFill(R.L, R.T, R.R - 1, R.B - 1, KBrushOf(Br));
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function FrameRect(Hdc, P, Br : LongInt) : LongInt;
Var D, B : LongInt; R : TRect;
Begin
  FrameRect := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  B := KBrushOf(Br);
  BrushFill(R.L, R.T, R.R - 1, R.T, B);
  BrushFill(R.L, R.B - 1, R.R - 1, R.B - 1, B);
  BrushFill(R.L, R.T, R.L, R.B - 1, B);
  BrushFill(R.R - 1, R.T, R.R - 1, R.B - 1, B);
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function InvertRect(Hdc, P : LongInt) : LongInt;
Var D, X, Y, A : LongInt; R : TRect;
Begin
  InvertRect := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  For Y := Max(R.T, ClipY1) To Min(R.B - 1, ClipY2) Do
    For X := Max(R.L, ClipX1) To Min(R.R - 1, ClipX2) Do
    Begin
      A := DS.Bits + (Y - DOY) * DS.Pitch + (X - DOX);
      Mem[0:A] := Mem[0:A] Xor 255;
    End;
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function DrawEdge(Hdc, P, EdgeT, Flags : LongInt) : LongInt;
Var D : LongInt; R : TRect;
Begin
  DrawEdge := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  If (EdgeT And 5) <> 0 Then
  Begin
    If (EdgeT And 1) <> 0 Then Edge(R.L, R.T, R.R - 1, R.B - 1, cSilver, cBlack)
    Else Edge(R.L, R.T, R.R - 1, R.B - 1, cWhite, cBlack);
    Edge(R.L + 1, R.T + 1, R.R - 2, R.B - 2, cWhite, cGray);
  End
  Else
  Begin
    Edge(R.L, R.T, R.R - 1, R.B - 1, cGray, cWhite);
    Edge(R.L + 1, R.T + 1, R.R - 2, R.B - 2, cBlack, cSilver);
  End;
  If (Flags And $800) <> 0 Then
    FBar(R.L + 2, R.T + 2, R.R - 3, R.B - 3, cSilver);
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function DrawFrameControl(Hdc, P, Typ, State : LongInt) : LongInt;
Var D : LongInt; R : TRect;
Begin
  DrawFrameControl := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  Raised(R.L, R.T, R.R - 1, R.B - 1, (State And $200) <> 0);
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function DrawCaption(H, Hdc, P, Flags : LongInt) : LongInt;
Var D, W : LongInt; R : TRect;
Begin
  DrawCaption := 1;
  D := DcOf(Hdc);
  W := WndOf(H);
  If (W < 0) Or Not DcBegin(D) Then Exit;
  GetRectAt(P, R);
  If (Flags And 1) <> 0 Then FBar(R.L, R.T, R.R - 1, R.B - 1, cNavy)
  Else FBar(R.L, R.T, R.R - 1, R.B - 1, cGray);
  OutBold(R.L + 4, R.T + 1, Fit(Wnds[W].Text, R.R - R.L - 8), cWhite);
  DcDirty(R.L, R.T, R.R, R.B);
End;

Function DrawIcon(Hdc, X, Y, Icon : LongInt) : LongInt;
Var D : LongInt;
Begin
  DrawIcon := 1;
  D := DcOf(Hdc);
  If Not DcBegin(D) Then Exit;
  PaintIcon(icApp, X, Y, 32);
  DcDirty(X, Y, X + 32, Y + 32);
End;

Function DrawFocusRect(Hdc, P : LongInt) : LongInt;
Begin
  DrawFocusRect := 1;
End;

{ DrawTextA : DT_CENTER 1, DT_RIGHT 2, DT_VCENTER 4, DT_BOTTOM 8,
  DT_WORDBREAK 10h, DT_SINGLELINE 20h, DT_CALCRECT 400h }
Function DrawTextA(Hdc, Str, N, P, Fmt : LongInt) : LongInt;
Var D, Cols, Lines, I, X, Y, Bg, C : LongInt; R : TRect; S, Ln, Wd : String;
    LnArr : Array[0..15] Of String[80];
Begin
  DrawTextA := 16;
  D := DcOf(Hdc);
  If D < 0 Then Exit;
  If N = -1 Then N := StrLenZ(Str);
  S := '';
  For I := 0 To Min(N, 255) - 1 Do S := S + Chr(Mem[0:Str + I]);
  I := Pos('&', S);
  If I > 0 Then Delete(S, I, 1);
  GetRectAt(P, R);
  Cols := Max(1, (R.R - R.L) Div 8);
  Lines := 0;
  If (Fmt And $10) <> 0 Then
  Begin
    Ln := ''; Wd := '';
    For I := 1 To Length(S) + 1 Do
      If (I > Length(S)) Or (S[I] = ' ') Or (S[I] = #13) Or (S[I] = #10) Then
      Begin
        If (Length(Ln) + Length(Wd) + 1 > Cols) And (Ln <> '') Then
        Begin
          If Lines < 16 Then LnArr[Lines] := Ln;
          Inc(Lines);
          Ln := Wd;
        End
        Else If Ln = '' Then Ln := Wd Else Ln := Ln + ' ' + Wd;
        Wd := '';
        If (I <= Length(S)) And (S[I] = #10) Then
        Begin
          If Lines < 16 Then LnArr[Lines] := Ln;
          Inc(Lines);
          Ln := '';
        End;
      End
      Else If S[I] <> #13 Then Wd := Wd + S[I];
    If Ln <> '' Then
    Begin
      If Lines < 16 Then LnArr[Lines] := Ln;
      Inc(Lines);
    End;
  End
  Else
  Begin
    LnArr[0] := S;
    Lines := 1;
  End;
  If Lines > 16 Then Lines := 16;
  If (Fmt And $400) <> 0 Then
  Begin
    C := 0;
    For I := 0 To Lines - 1 Do C := Max(C, Length(LnArr[I]));
    R.R := R.L + C * 8; R.B := R.T + Lines * 16;
    PutRectAt(P, R);
    DrawTextA := Lines * 16;
    Exit;
  End;
  If Not DcBegin(D) Then Exit;
  Y := R.T;
  If (Fmt And $24) = $24 Then Y := (R.T + R.B - 16) Div 2
  Else If (Fmt And $28) = $28 Then Y := R.B - 16;
  C := GColor(Dcs[D].TextColor);
  Bg := GColor(Dcs[D].BkColor);
  If (Fmt And $100) = 0 Then
  Begin
    ClipX1 := Max(ClipX1, R.L); ClipY1 := Max(ClipY1, R.T);
    ClipX2 := Min(ClipX2, R.R - 1); ClipY2 := Min(ClipY2, R.B - 1);
  End;
  For I := 0 To Lines - 1 Do
  Begin
    X := R.L;
    If (Fmt And 1) <> 0 Then X := (R.L + R.R - TextW(LnArr[I])) Div 2
    Else If (Fmt And 2) <> 0 Then X := R.R - TextW(LnArr[I]);
    If Dcs[D].BkMode = 2 Then
      FBar(X, Y, X + TextW(LnArr[I]) - 1, Y + 15, Bg);
    OutTxt(X, Y, LnArr[I], C);
    Y := Y + 16;
  End;
  DcDirty(R.L, R.T, R.R, R.B);
  DrawTextA := Lines * 16;
End;

Function GrayStringA(Hdc, Br, Proc, Lp, N, X, Y, W, H : LongInt) : LongInt;
Begin
  GrayStringA := 1;
End;

{ ------------------------------------------------------------------ }
{ Clavier, souris, metriques, divers                                 }
{ ------------------------------------------------------------------ }

Function GetKeyState(Vk : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := KeyState[Vk And 255] And 1;
  If (KeyState[Vk And 255] And $80) <> 0 Then R := R Or LongInt($FFFFFF80);
  GetKeyState := R;
End;

Function GetAsyncKeyState(Vk : LongInt) : LongInt;
Begin
  If (KeyState[Vk And 255] And $80) <> 0 Then
    GetAsyncKeyState := LongInt($FFFF8000)
  Else GetAsyncKeyState := 0;
End;

Function GetKeyboardState(P : LongInt) : LongInt;
Begin
  MoveMem(LongInt(@KeyState), P, 256);
  GetKeyboardState := 1;
End;

Function SetKeyboardState(P : LongInt) : LongInt;
Begin
  MoveMem(P, LongInt(@KeyState), 256);
  SetKeyboardState := 1;
End;

Function ToAscii(Vk, Sc, State, Buf, Flags : LongInt) : LongInt;
Var C : LongInt;
Begin
  C := ScanToChar(Sc And $FF);
  If C = 0 Then
  Begin
    ToAscii := 0;
    Exit;
  End;
  MemW[0:Buf] := C;
  ToAscii := 1;
End;

Function MapVirtualKeyA(Code, Typ : LongInt) : LongInt;
Begin
  MapVirtualKeyA := 0;
End;

Function GetCursorPos(P : LongInt) : LongInt;
Begin
  MemL[0:P] := CurX; MemL[0:P + 4] := CurY;
  GetCursorPos := 1;
End;

Function SetCursorPos(X, Y : LongInt) : LongInt;
Begin
  CursorMoveTo(Max(0, Min(ScrW - 1, X)), Max(0, Min(ScrH - 1, Y)));
  SetCursorPos := 1;
End;

Function GetDoubleClickTime : LongInt;
Begin
  GetDoubleClickTime := 500;
End;

Function GetCaretBlinkTime : LongInt;
Begin
  GetCaretBlinkTime := 530;
End;

Function MessageBeep(T : LongInt) : LongInt;
Begin
  KBeep;
  MessageBeep := 1;
End;

Function GetSystemMetrics(I : LongInt) : LongInt;
Begin
  Case I Of
    0, 16 : GetSystemMetrics := ScrW;
    1 : GetSystemMetrics := ScrH;
    17 : GetSystemMetrics := TaskY - 19;
    2, 3, 9, 10, 20, 21 : GetSystemMetrics := 16;
    4, 15 : GetSystemMetrics := 18;
    5, 6 : GetSystemMetrics := 1;
    7, 8 : GetSystemMetrics := 3;
    11, 12, 13, 14, 38, 39 : GetSystemMetrics := 32;
    19, 43 : GetSystemMetrics := 2;
    28 : GetSystemMetrics := 112;
    29 : GetSystemMetrics := 27;
    30, 31 : GetSystemMetrics := 18;
    32, 33 : GetSystemMetrics := 4;
    34 : GetSystemMetrics := 112;
    35 : GetSystemMetrics := 27;
    36, 37 : GetSystemMetrics := 4;
    49, 50 : GetSystemMetrics := 16;
    61, 62 : GetSystemMetrics := ScrW;
  Else
    GetSystemMetrics := 0;
  End;
End;

Function SystemParametersInfoA(Act, Param, PV, WinIni : LongInt) : LongInt;
Var R : TRect;
Begin
  SystemParametersInfoA := 1;
  Case Act Of
    48 :
    Begin
      SetR(R, 0, 0, ScrW, TaskY);
      PutRectAt(PV, R);
    End;
  Else
    If PV <> 0 Then
      If (Act And 1) = 0 Then MemL[0:PV] := 0;
  End;
End;

Function ExitWindowsEx(Flags, Res : LongInt) : LongInt;
Begin
  If (Flags And 2) <> 0 Then DoShutdown(1) Else DoShutdown(0);
  ExitWindowsEx := 1;
End;

Function WinHelpA(H, F, Cmd, Data : LongInt) : LongInt;
Begin
  WinHelpA := 0;
End;

Function FlashWindow(H, Inv : LongInt) : LongInt;
Begin
  FlashWindow := 0;
End;

Function SetMessageQueue(N : LongInt) : LongInt;
Begin
  SetMessageQueue := 1;
End;

Function CallNextHookEx(Hk, Code, WP, LP : LongInt) : LongInt;
Begin
  CallNextHookEx := 0;
End;

Function SetWindowsHookExA(Id, Proc, Inst, Tid : LongInt) : LongInt;
Begin
  SetWindowsHookExA := $1234;
End;

Function UnhookWindowsHookEx(H : LongInt) : LongInt;
Begin
  UnhookWindowsHookEx := 1;
End;

Function SetScrollPos(H, Bar, Pos0, Redraw : LongInt) : LongInt;
Var W : LongInt;
Begin
  SetScrollPos := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  If Bar = 1 Then
  Begin
    SetScrollPos := Wnds[W].VScrollPos; Wnds[W].VScrollPos := Pos0;
  End
  Else
  Begin
    SetScrollPos := Wnds[W].HScrollPos; Wnds[W].HScrollPos := Pos0;
  End;
End;

Function GetScrollPos(H, Bar : LongInt) : LongInt;
Var W : LongInt;
Begin
  GetScrollPos := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  If Bar = 1 Then GetScrollPos := Wnds[W].VScrollPos
  Else GetScrollPos := Wnds[W].HScrollPos;
End;

Function SetScrollRange(H, Bar, Mn, Mx, Redraw : LongInt) : LongInt;
Begin
  SetScrollRange := 1;
End;

Function ShowScrollBar(H, Bar, Show : LongInt) : LongInt;
Begin
  ShowScrollBar := 1;
End;

{ Presse-papiers (vide) }
Function OpenClipboard(H : LongInt) : LongInt;
Begin
  OpenClipboard := 1;
End;

Function CloseClipboard : LongInt;
Begin
  CloseClipboard := 1;
End;

Function EmptyClipboard : LongInt;
Begin
  EmptyClipboard := 1;
End;

Function GetClipboardData(F : LongInt) : LongInt;
Begin
  GetClipboardData := 0;
End;

Function SetClipboardData(F, H : LongInt) : LongInt;
Begin
  SetClipboardData := H;
End;

Function EnumClipboardFormats(F : LongInt) : LongInt;
Begin
  EnumClipboardFormats := 0;
End;

Function IsClipboardFormatAvailable(F : LongInt) : LongInt;
Begin
  IsClipboardFormatAvailable := 0;
End;

Function RegisterClipboardFormatA(S : LongInt) : LongInt;
Begin
  RegisterClipboardFormatA := AtomAdd(PStr(S));
End;

Function SetClipboardViewer(H : LongInt) : LongInt;
Begin
  SetClipboardViewer := 0;
End;

Function ChangeClipboardChain(H, Nxt : LongInt) : LongInt;
Begin
  ChangeClipboardChain := 0;
End;

Function RegisterWindowMessageA(S : LongInt) : LongInt;
Begin
  RegisterWindowMessageA := AtomAdd(PStr(S));
End;

{ ------------------------------------------------------------------ }
{ Chaines et caracteres                                              }
{ ------------------------------------------------------------------ }

Function CharUpperA(P : LongInt) : LongInt;
Var I : LongInt;
Begin
  If (P >= 0) And (P < $10000) Then
  Begin
    CharUpperA := UpCh(P);
    Exit;
  End;
  I := 0;
  While Mem[0:P + I] <> 0 Do
  Begin
    Mem[0:P + I] := UpCh(Mem[0:P + I]);
    Inc(I);
  End;
  CharUpperA := P;
End;

Function CharLowerA(P : LongInt) : LongInt;
Var I, C : LongInt;
Begin
  If (P >= 0) And (P < $10000) Then
  Begin
    If (P >= 65) And (P <= 90) Then P := P + 32;
    CharLowerA := P;
    Exit;
  End;
  I := 0;
  While Mem[0:P + I] <> 0 Do
  Begin
    C := Mem[0:P + I];
    If (C >= 65) And (C <= 90) Then Mem[0:P + I] := C + 32;
    Inc(I);
  End;
  CharLowerA := P;
End;

Function CharUpperBuffA(P, N : LongInt) : LongInt;
Var I : LongInt;
Begin
  For I := 0 To N - 1 Do Mem[0:P + I] := UpCh(Mem[0:P + I]);
  CharUpperBuffA := N;
End;

Function CharNextA(P : LongInt) : LongInt;
Begin
  If Mem[0:P] <> 0 Then CharNextA := P + 1 Else CharNextA := P;
End;

Function CharPrevA(S, P : LongInt) : LongInt;
Begin
  If P > S Then CharPrevA := P - 1 Else CharPrevA := S;
End;

Function CharToOemBuffA(S, D, N : LongInt) : LongInt;
Begin
  MoveMem(S, D, N);
  CharToOemBuffA := 1;
End;

Function CharToOemA(S, D : LongInt) : LongInt;
Begin
  lstrcpyA(D, S);
  CharToOemA := 1;
End;

Function OemToCharA(S, D : LongInt) : LongInt;
Begin
  lstrcpyA(D, S);
  OemToCharA := 1;
End;

Function IsCharAlphaA(C : LongInt) : LongInt;
Begin
  C := UpCh(C And 255);
  IsCharAlphaA := Ord((C >= 65) And (C <= 90));
End;

{ wsprintfA (cdecl) : %s %c %d %i %u %x %X %ld %lu %lx %%, largeur,
  '-' et '0' }
Function wsprintfA(Buf, Fmt, A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11,
  A12 : LongInt) : LongInt;
Var Args : Array[0..11] Of LongInt; F, O, K, Wd, V : LongInt; C : Char;
    S : String; Left, Zero : Boolean; R : Real;

  Procedure Emit(Const T : String);
  Var J : LongInt; P : String;
  Begin
    P := T;
    While Length(P) < Wd Do
      If Left Then P := P + ' '
      Else If Zero Then P := '0' + P
      Else P := ' ' + P;
    For J := 1 To Length(P) Do
    Begin
      Mem[0:Buf + O] := Ord(P[J]);
      Inc(O);
    End;
  End;

Begin
  Args[0] := A1; Args[1] := A2; Args[2] := A3; Args[3] := A4;
  Args[4] := A5; Args[5] := A6; Args[6] := A7; Args[7] := A8;
  Args[8] := A9; Args[9] := A10; Args[10] := A11; Args[11] := A12;
  F := Fmt; O := 0; K := 0;
  While (Mem[0:F] <> 0) And (O < 1000) Do
  Begin
    C := Chr(Mem[0:F]);
    Inc(F);
    If C <> '%' Then
    Begin
      Mem[0:Buf + O] := Ord(C);
      Inc(O);
      Continue;
    End;
    Left := False; Zero := False; Wd := 0;
    If Chr(Mem[0:F]) = '-' Then Begin Left := True; Inc(F) End;
    If Chr(Mem[0:F]) = '0' Then Begin Zero := True; Inc(F) End;
    While (Mem[0:F] >= 48) And (Mem[0:F] <= 57) Do
    Begin
      Wd := Wd * 10 + Mem[0:F] - 48;
      Inc(F);
    End;
    If Chr(Mem[0:F]) = '.' Then
    Begin
      Inc(F);
      While (Mem[0:F] >= 48) And (Mem[0:F] <= 57) Do Inc(F);
    End;
    While Chr(Mem[0:F]) In ['l', 'h'] Do Inc(F);
    C := Chr(Mem[0:F]);
    Inc(F);
    If K <= 11 Then V := Args[K] Else V := 0;
    Case C Of
      '%' : Emit('%');
      'c' : Begin Emit(Chr(V And 255)); Inc(K) End;
      's' : Begin Emit(PStr(V)); Inc(K) End;
      'd', 'i' : Begin Emit(IntStr(V)); Inc(K) End;
      'u' :
      Begin
        If V >= 0 Then S := IntStr(V)
        Else
        Begin
          R := V + 4294967296.0;
          Str(R:0:0, S);
        End;
        Emit(S); Inc(K);
      End;
      'x' :
      Begin
        S := HexStr(V, 8);
        While (Length(S) > 1) And (S[1] = '0') Do Delete(S, 1, 1);
        For V := 1 To Length(S) Do
          If S[V] In ['A'..'F'] Then S[V] := Chr(Ord(S[V]) + 32);
        Emit(S); Inc(K);
      End;
      'X' :
      Begin
        S := HexStr(V, 8);
        While (Length(S) > 1) And (S[1] = '0') Do Delete(S, 1, 1);
        Emit(S); Inc(K);
      End;
    Else
      Emit(C);
    End;
  End;
  Mem[0:Buf + O] := 0;
  wsprintfA := O;
End;

{ wvsprintfA (arguments dans un tableau) }
Function wvsprintfA(Buf, Fmt, Arg : LongInt) : LongInt;
Begin
  wvsprintfA := wsprintfA(Buf, Fmt, MemL[0:Arg], MemL[0:Arg + 4],
    MemL[0:Arg + 8], MemL[0:Arg + 12], MemL[0:Arg + 16], MemL[0:Arg + 20],
    MemL[0:Arg + 24], MemL[0:Arg + 28], MemL[0:Arg + 32], MemL[0:Arg + 36],
    MemL[0:Arg + 40], MemL[0:Arg + 44]);
End;

{ ------------------------------------------------------------------ }
{ Ressources : chaines, curseurs, icones, bitmaps, accelerateurs     }
{ ------------------------------------------------------------------ }

Function LoadStringA(Inst, Id, Buf, N : LongInt) : LongInt;
Var E, A, Size, I, LN, K : LongInt;
Begin
  LoadStringA := 0;
  If N > 0 Then Mem[0:Buf] := 0;
  E := ResFind(AppModule(Inst), Id Div 16 + 1, 6);
  If E = 0 Then Exit;
  A := ResData(AppModule(Inst), E, Size);
  For I := 0 To (Id Mod 16) - 1 Do A := A + 2 + MemW[0:A] * 2;
  LN := MemW[0:A];
  If LN >= N Then LN := N - 1;
  For K := 0 To LN - 1 Do Mem[0:Buf + K] := MemW[0:A + 2 + K * 2] And 255;
  Mem[0:Buf + LN] := 0;
  LoadStringA := LN;
End;

Function CursorNew(HX, HY : LongInt) : LongInt;
Var I : LongInt;
Begin
  CursorNew := 0;
  For I := 1 To 31 Do
    If Not Cursors[I].Used Then
    Begin
      Cursors[I].Used := True;
      Cursors[I].HX := HX; Cursors[I].HY := HY;
      Cursors[I].Map := KAlloc(1024);
      CursorNew := $6000 + I;
      Exit;
    End;
End;

{ Masques ET / OU exclusif 1 bit (W x H) -> carte du curseur }
Procedure CursorFromMasks(C, W, H, AndM, XorM, Pitch : LongInt;
                          BottomUp : Boolean);
Var X, Y, A, Xo, SY : LongInt;
Begin
  For Y := 0 To Min(H, 32) - 1 Do
  Begin
    If BottomUp Then SY := H - 1 - Y Else SY := Y;
    For X := 0 To Min(W, 32) - 1 Do
    Begin
      A := (Mem[0:AndM + SY * Pitch + X Div 8] Shr (7 - X Mod 8)) And 1;
      Xo := (Mem[0:XorM + SY * Pitch + X Div 8] Shr (7 - X Mod 8)) And 1;
      If A = 0 Then Mem[0:Cursors[C].Map + Y * 32 + X] := 1 + Xo
      Else If Xo = 1 Then Mem[0:Cursors[C].Map + Y * 32 + X] := 3
      Else Mem[0:Cursors[C].Map + Y * 32 + X] := 0;
    End;
  End;
End;

Function CreateCursor(Inst, HX, HY, W, H, AndM, XorM : LongInt) : LongInt;
Var C : LongInt;
Begin
  C := CursorNew(HX, HY);
  If C <> 0 Then
    CursorFromMasks(C - $6000, W, H, AndM, XorM, (W + 15) Div 16 * 2,
                    False);
  CreateCursor := C;
End;

Function DestroyCursor(C : LongInt) : LongInt;
Begin
  If (C > $6000) And (C < $6020) And Cursors[C - $6000].Used Then
  Begin
    KFree(Cursors[C - $6000].Map);
    Cursors[C - $6000].Used := False;
  End;
  DestroyCursor := 1;
End;

{ LoadCursorA : curseurs du systeme (IDC_*) ou ressource RT_CURSOR }
Function LoadCursorA(Inst, Name : LongInt) : LongInt;
Var E, G, Size, Id, A, C, W, H : LongInt;
Begin
  LoadCursorA := $5000 + 32512;
  If (Inst = 0) Or (Name = 32512) Then
  Begin
    If (Name > 0) And (Name < $10000) Then LoadCursorA := $5000 + Name;
    Exit;
  End;
  { groupe RT_GROUP_CURSOR (12) -> premier curseur RT_CURSOR (1) }
  E := ResFind(AppModule(Inst), Name, 12);
  If E = 0 Then Exit;
  G := ResData(AppModule(Inst), E, Size);
  Id := MemW[0:G + 6 + 12];
  E := ResFind(AppModule(Inst), Id, 1);
  If E = 0 Then Exit;
  A := ResData(AppModule(Inst), E, Size);
  C := CursorNew(MemW[0:A], MemW[0:A + 2]);
  If C = 0 Then Exit;
  A := A + 4;
  W := MemL[0:A + 4]; H := MemL[0:A + 8] Div 2;
  { BITMAPINFOHEADER, 2 couleurs, masque XOR puis masque ET }
  CursorFromMasks(C - $6000, W, H, A + 40 + 8 + H * ((W + 31) Div 32 * 4),
                  A + 40 + 8, (W + 31) Div 32 * 4, True);
  LoadCursorA := C;
End;

Function SetCursor(C : LongInt) : LongInt;
Begin
  SetCursor := AppCursor;
  AppCursor := C;
  If C = 0 Then
  Begin
    CursorErase;
    FillMem(LongInt(@CurMap), 1024, 0);
    CurKind := 2;
    Exit;
  End;
  CursorErase;
  If (C > $6000) And (C < $6020) And Cursors[C - $6000].Used Then
  Begin
    MoveMem(Cursors[C - $6000].Map, LongInt(@CurMap), 1024);
    CurW := 32; CurHh := 32;
    CurHotX := Cursors[C - $6000].HX; CurHotY := Cursors[C - $6000].HY;
    CurKind := 2;
  End
  Else If (C = $5000 + 32514) Or (C = $5000 + 32650) Then
  Begin
    CursorSetShape(1);
    CurKind := 2;
  End
  Else
  Begin
    CursorSetShape(0);
    CurKind := 2;
  End;
  CursorDraw;
End;

Function GetCursor : LongInt;
Begin
  GetCursor := AppCursor;
End;

Function ShowCursor(Show : LongInt) : LongInt;
Begin
  If Show <> 0 Then Inc(CurHide) Else Dec(CurHide);
  If CurHide < 0 Then CursorErase Else CursorDraw;
  ShowCursor := CurHide;
End;

Function ClipCursor(P : LongInt) : LongInt;
Begin
  ClipCursor := 1;
End;

Function LoadIconA(Inst, Name : LongInt) : LongInt;
Begin
  LoadIconA := $7000 + (Name And $FFF);
End;

Function DestroyIcon(H : LongInt) : LongInt;
Begin
  DestroyIcon := 1;
End;

Function LoadBitmapA(Inst, Name : LongInt) : LongInt;
Var E, A, Size, B : LongInt;
Begin
  LoadBitmapA := 0;
  If Inst = 0 Then Exit;
  E := ResFind(AppModule(Inst), Name, 2);
  If E = 0 Then Exit;
  A := ResData(AppModule(Inst), E, Size);
  B := CreateDIBitmapK(A, 0, 0);
  LoadBitmapA := GdiH(B);
End;

Function LoadAcceleratorsA(Inst, Name : LongInt) : LongInt;
Var E, Size : LongInt;
Begin
  LoadAcceleratorsA := 0;
  E := ResFind(AppModule(Inst), Name, 9);
  If E <> 0 Then LoadAcceleratorsA := ResData(AppModule(Inst), E, Size);
End;

Function CreateAcceleratorTableA(P, N : LongInt) : LongInt;
Var A : LongInt;
Begin
  A := KAlloc(N * 6 + 8);
  MoveMem(P, A, N * 6);
  CreateAcceleratorTableA := A;
End;

Function CopyAcceleratorTableA(H, Dst, N : LongInt) : LongInt;
Begin
  If Dst <> 0 Then MoveMem(H, Dst, N * 6);
  CopyAcceleratorTableA := 0;
End;

Function DestroyAcceleratorTable(H : LongInt) : LongInt;
Begin
  DestroyAcceleratorTable := 1;
End;

Function TranslateAcceleratorA(H, Acc, Msg : LongInt) : LongInt;
Begin
  TranslateAcceleratorA := 0;
End;

Function TranslateMDISysAccel(H, Msg : LongInt) : LongInt;
Begin
  TranslateMDISysAccel := 0;
End;

{ ------------------------------------------------------------------ }
{ Menus (donnees ; la barre de menus n'est pas affichee)             }
{ ------------------------------------------------------------------ }

Function MenuNew : LongInt;
Var I : LongInt;
Begin
  MenuNew := 0;
  For I := 0 To MaxMenu - 1 Do
    If Not MenuUsed[I] Then
    Begin
      MenuUsed[I] := True;
      MenuNew := HMenuBase + I * 4;
      Exit;
    End;
End;

Function MenuIdx(H : LongInt) : LongInt;
Begin
  If (H >= HMenuBase) And (H < HMenuBase + MaxMenu * 4) And
     MenuUsed[(H - HMenuBase) Div 4] Then MenuIdx := (H - HMenuBase) Div 4
  Else MenuIdx := -1;
End;

Function CreateMenu : LongInt;
Begin
  CreateMenu := MenuNew;
End;

Function CreatePopupMenu : LongInt;
Begin
  CreatePopupMenu := MenuNew;
End;

{ N-ieme element d'un menu (par position) ; -1 si absent }
Function MItemAt(M, Pos0 : LongInt) : LongInt;
Var I, J, Best, BS, Last : LongInt;
Begin
  MItemAt := -1;
  Last := -1;
  For J := 0 To Pos0 Do
  Begin
    Best := -1; BS := $7FFFFFFF;
    For I := 0 To MaxMenuItem - 1 Do
      If MItems[I].Used And (MItems[I].Menu = M) And (MItems[I].Seq > Last)
         And (MItems[I].Seq < BS) Then
      Begin
        Best := I; BS := MItems[I].Seq;
      End;
    If Best < 0 Then Exit;
    Last := BS;
    MItemAt := Best;
  End;
End;

Function MItemFind(M, Id, Flags : LongInt) : LongInt;
Var I : LongInt;
Begin
  If (Flags And MF_BYPOSITION) <> 0 Then
  Begin
    MItemFind := MItemAt(M, Id);
    Exit;
  End;
  MItemFind := -1;
  For I := 0 To MaxMenuItem - 1 Do
    If MItems[I].Used And (MItems[I].Menu = M) And (MItems[I].Id = Id) Then
    Begin
      MItemFind := I;
      Exit;
    End;
End;

Function AppendMenuA(H, Flags, Id, Item : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  AppendMenuA := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  For I := 0 To MaxMenuItem - 1 Do
    If Not MItems[I].Used Then
    Begin
      MItems[I].Used := True; MItems[I].Menu := M;
      MItems[I].Flags := Flags; MItems[I].Id := Id;
      Inc(MSeq); MItems[I].Seq := MSeq;
      If ((Flags And (MF_SEPARATOR Or 4 Or $100)) = 0) And (Item <> 0) Then
        MItems[I].Text := Copy(PStr(Item), 1, 63)
      Else MItems[I].Text := '';
      AppendMenuA := 1;
      Exit;
    End;
End;

Function InsertMenuA(H, Pos0, Flags, Id, Item : LongInt) : LongInt;
Begin
  InsertMenuA := AppendMenuA(H, Flags And Not MF_BYPOSITION, Id, Item);
End;

Function ModifyMenuA(H, Pos0, Flags, Id, Item : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  ModifyMenuA := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Pos0, Flags);
  If I < 0 Then Exit;
  MItems[I].Flags := Flags And Not MF_BYPOSITION; MItems[I].Id := Id;
  If ((Flags And (MF_SEPARATOR Or 4 Or $100)) = 0) And (Item <> 0) Then
    MItems[I].Text := Copy(PStr(Item), 1, 63);
  ModifyMenuA := 1;
End;

Function DeleteMenu(H, Pos0, Flags : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  DeleteMenu := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Pos0, Flags);
  If I < 0 Then Exit;
  MItems[I].Used := False;
  DeleteMenu := 1;
End;

Function RemoveMenu(H, Pos0, Flags : LongInt) : LongInt;
Begin
  RemoveMenu := DeleteMenu(H, Pos0, Flags);
End;

Function DestroyMenu(H : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  DestroyMenu := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  For I := 0 To MaxMenuItem - 1 Do
    If MItems[I].Used And (MItems[I].Menu = M) Then MItems[I].Used := False;
  MenuUsed[M] := False;
  DestroyMenu := 1;
End;

Function GetMenuItemCount(H : LongInt) : LongInt;
Var M, I, N : LongInt;
Begin
  M := MenuIdx(H);
  N := 0;
  If M >= 0 Then
    For I := 0 To MaxMenuItem - 1 Do
      If MItems[I].Used And (MItems[I].Menu = M) Then Inc(N);
  If M < 0 Then N := -1;
  GetMenuItemCount := N;
End;

Function GetMenuItemID(H, Pos0 : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  GetMenuItemID := -1;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemAt(M, Pos0);
  If (I >= 0) And ((MItems[I].Flags And MF_POPUP) = 0) Then
    GetMenuItemID := MItems[I].Id;
End;

Function GetSubMenu(H, Pos0 : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  GetSubMenu := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemAt(M, Pos0);
  If (I >= 0) And ((MItems[I].Flags And MF_POPUP) <> 0) Then
    GetSubMenu := MItems[I].Id;
End;

Function GetMenuState(H, Id, Flags : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  GetMenuState := -1;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Id, Flags);
  If I >= 0 Then GetMenuState := MItems[I].Flags And $FF;
End;

Function GetMenuStringA(H, Id, Buf, N, Flags : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  GetMenuStringA := 0;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Id, Flags);
  If I < 0 Then Exit;
  If Buf <> 0 Then PutPStr(Buf, MItems[I].Text, N);
  GetMenuStringA := Length(MItems[I].Text);
End;

Function CheckMenuItem(H, Id, Flags : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  CheckMenuItem := -1;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Id, Flags);
  If I < 0 Then Exit;
  CheckMenuItem := MItems[I].Flags And MF_CHECKED;
  MItems[I].Flags := (MItems[I].Flags And Not MF_CHECKED) Or
                     (Flags And MF_CHECKED);
End;

Function EnableMenuItem(H, Id, Flags : LongInt) : LongInt;
Var M, I : LongInt;
Begin
  EnableMenuItem := -1;
  M := MenuIdx(H);
  If M < 0 Then Exit;
  I := MItemFind(M, Id, Flags);
  If I < 0 Then Exit;
  EnableMenuItem := MItems[I].Flags And 3;
  MItems[I].Flags := (MItems[I].Flags And Not 3) Or (Flags And 3);
End;

Function HiliteMenuItem(H, M, Id, Flags : LongInt) : LongInt;
Begin
  HiliteMenuItem := 1;
End;

Function GetMenuCheckMarkDimensions : LongInt;
Begin
  GetMenuCheckMarkDimensions := (13 Shl 16) Or 13;
End;

Function GetMenu(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  If W < 0 Then GetMenu := 0 Else GetMenu := Wnds[W].Menu;
End;

Function SetMenu(H, M : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  SetMenu := 0;
  If W < 0 Then Exit;
  Wnds[W].Menu := M;
  { la barre de menus n'est pas affichee : pas de changement du cadre }
  SetMenu := 1;
End;

Function DrawMenuBar(H : LongInt) : LongInt;
Begin
  DrawMenuBar := 1;
End;

Function GetSystemMenu(H, Revert : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  GetSystemMenu := 0;
  If W < 0 Then Exit;
  If Wnds[W].K1 = 0 Then Wnds[W].K1 := MenuNew;
  GetSystemMenu := Wnds[W].K1;
End;

Function TrackPopupMenu(H, Flags, X, Y, Res, Hw, P : LongInt) : LongInt;
Begin
  TrackPopupMenu := 0;
End;

Function LoadMenuA(Inst, Name : LongInt) : LongInt;
Begin
  LoadMenuA := MenuNew;
End;

{ ------------------------------------------------------------------ }
{ Procedure par defaut des fenetres                                  }
{ ------------------------------------------------------------------ }

Function DefWindowProcA(H, Msg, WP, LP : LongInt) : LongInt;
Var W, Hdc, C : LongInt;
Begin
  DefWindowProcA := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  Case Msg Of
    WM_NCCREATE : DefWindowProcA := 1;
    WM_CLOSE : DestroyW(W);
    WM_PAINT :
    Begin
      { BeginPaint/EndPaint : envoie WM_ERASEBKGND si necessaire }
      C := KAlloc(64);
      If C <> 0 Then
      Begin
        BeginPaint(H, C);
        EndPaint(H, C);
        KFree(C);
      End;
      SetR(Wnds[W].Upd, 0, 0, 0, 0);
      Wnds[W].UpdErase := False;
    End;
    WM_ERASEBKGND :
    Begin
      EraseBkgnd(W, WP);
      DefWindowProcA := 1;
    End;
    WM_SETTEXT :
    Begin
      Wnds[W].Text := PStr(LP);
      Wnds[W].NeedNc := True;
      TaskbarChanged;
      DefWindowProcA := 1;
    End;
    WM_GETTEXT :
    Begin
      PutPStr(LP, Wnds[W].Text, WP);
      DefWindowProcA := Min(Length(Wnds[W].Text), Max(0, WP - 1));
    End;
    WM_GETTEXTLENGTH : DefWindowProcA := Length(Wnds[W].Text);
    WM_SYSCOMMAND : SysCommand(TopOf(W), WP);
    WM_SYSKEYDOWN :
      If WP = $73 Then PostMsgW(TopOf(W), WM_CLOSE, 0, 0);
    WM_SETCURSOR :
    Begin
      C := Classes[Wnds[W].Cls].Cursor;
      If C <> 0 Then SetCursor(C);
      DefWindowProcA := Ord(C <> 0);
    End;
    WM_MOUSEACTIVATE : DefWindowProcA := 1;
    WM_NCHITTEST : DefWindowProcA := 1;
    WM_ACTIVATE :
      If (WP And $FFFF) <> 0 Then SetFocusW(W);
    WM_CTLCOLORMSGBOX..WM_CTLCOLORSTATIC :
    Begin
      SetBkColor(WP, $C0C0C0);
      DefWindowProcA := GdiH(KBrushOf(16));
    End;
    WM_QUERYNEWPALETTE : DefWindowProcA := 0;
    WM_SHOWWINDOW : ;
  End;
  Hdc := 0;
End;

Function DefFrameProcA(H, HC, Msg, WP, LP : LongInt) : LongInt;
Begin
  DefFrameProcA := DefWindowProcA(H, Msg, WP, LP);
End;

Function DefMDIChildProcA(H, Msg, WP, LP : LongInt) : LongInt;
Begin
  DefMDIChildProcA := DefWindowProcA(H, Msg, WP, LP);
End;

Function CallWindowProcA(P, H, Msg, WP, LP : LongInt) : LongInt;
Var W : LongInt;
Begin
  CallWindowProcA := 0;
  If (P >= KProcToken) And (P < KProcToken + 64) Then
  Begin
    W := WndOf(H);
    If W >= 0 Then CallWindowProcA := KWndProc(W, Msg, WP, LP);
    Exit;
  End;
  If P <> 0 Then CallWindowProcA := CallProc(P, H, Msg, WP, LP);
End;

{ ------------------------------------------------------------------ }
{ Boites de dialogue (modeles DLGTEMPLATE et DLGTEMPLATEEX)          }
{ ------------------------------------------------------------------ }

{ Element sz_Or_Ord : chaine ou ordinal ; rend l'adresse suivante }
Function Sx16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= 32768 Then V := V - 65536;
  Sx16 := V;
End;

Function SzOrOrd(A : LongInt; Var S : String; Var Ord0 : LongInt)
  : LongInt;
Var C : LongInt;
Begin
  S := ''; Ord0 := 0;
  C := MemW[0:A];
  If C = 0 Then
  Begin
    SzOrOrd := A + 2;
    Exit;
  End;
  If C = $FFFF Then
  Begin
    Ord0 := MemW[0:A + 2];
    SzOrOrd := A + 4;
    Exit;
  End;
  While MemW[0:A] <> 0 Do
  Begin
    If Length(S) < 120 Then S := S + Chr(MemW[0:A] And 255);
    A := A + 2;
  End;
  SzOrOrd := A + 2;
End;

Function DlgCreate(Inst, T, Parent, Proc, Lp : LongInt) : LongInt;
Var Ex, Style, N, X, Y, CX, CY, A, I, Ord0, Cls, W, C, B, TT, Id,
    IStyle, IEx, Focus, CC : LongInt; Ext : Boolean; S, Title, ClsN : String;
    P : LongInt;
Begin
  DlgCreate := -1;
  Ext := MemL[0:T] = LongInt($FFFF0001);
  If Ext Then
  Begin
    Ex := MemL[0:T + 8]; Style := MemL[0:T + 12]; N := MemW[0:T + 16];
    X := Sx16(MemW[0:T + 18]); Y := Sx16(MemW[0:T + 20]);
    CX := MemW[0:T + 22]; CY := MemW[0:T + 24];
    A := T + 26;
  End
  Else
  Begin
    Style := MemL[0:T]; Ex := MemL[0:T + 4]; N := MemW[0:T + 8];
    X := Sx16(MemW[0:T + 10]); Y := Sx16(MemW[0:T + 12]);
    CX := MemW[0:T + 14]; CY := MemW[0:T + 16];
    A := T + 18;
  End;
  A := SzOrOrd(A, S, Ord0);            { menu }
  A := SzOrOrd(A, ClsN, Ord0);         { classe }
  A := SzOrOrd(A, Title, Ord0);        { titre }
  If (Style And $40) <> 0 Then
  Begin
    If Ext Then A := A + 6 Else A := A + 2;
    A := SzOrOrd(A, S, Ord0);
  End;
  Cls := KClass[ikDialog];
  If ClsN <> '' Then
  Begin
    C := ClassFind(ClsN);
    If C >= 0 Then Cls := C;
  End;
  NcSize(Style, Ex, False, B, TT);
  CX := CX * 2 + 2 * B; CY := CY * 2 + TT + B;
  If ((Style And $800) <> 0) Or (Parent = 0) Then
  Begin
    X := (ScrW - CX) Div 2; Y := (TaskY - CY) Div 2;
  End
  Else
  Begin
    W := WndOf(Parent);
    If W >= 0 Then
    Begin
      ClientScreenOrg(W, I, C);
      X := X * 2 + I; Y := Y * 2 + C;
    End
    Else
    Begin
      X := X * 2; Y := Y * 2;
    End;
  End;
  W := CreateW(Ex, Cls, Title, (Style And Not WS_VISIBLE) And
               Not WS_CHILD, X, Y, CX, CY, WndOf(Parent), 0, Inst, Lp);
  If W < 0 Then Exit;
  Wnds[W].Proc := 0;
  Wnds[W].IKind := ikDialog;
  Wnds[W].DlgProc := Proc;
  Wnds[W].Thread := CurT;
  Wnds[W].K4 := icApp;
  Focus := -1;
  For I := 0 To N - 1 Do
  Begin
    A := (A + 3) And Not 3;
    If Ext Then
    Begin
      IEx := MemL[0:A + 4]; IStyle := MemL[0:A + 8];
      X := Sx16(MemW[0:A + 12]); Y := Sx16(MemW[0:A + 14]);
      CX := MemW[0:A + 16]; CY := MemW[0:A + 18]; Id := MemL[0:A + 20];
      A := A + 24;
    End
    Else
    Begin
      IStyle := MemL[0:A]; IEx := MemL[0:A + 4];
      X := Sx16(MemW[0:A + 8]); Y := Sx16(MemW[0:A + 10]);
      CX := MemW[0:A + 12]; CY := MemW[0:A + 14]; Id := MemW[0:A + 16];
      A := A + 18;
    End;
    A := SzOrOrd(A, ClsN, Ord0);
    If Ord0 <> 0 Then
    Begin
      ClsN := '';
      CC := -1;
      Case Ord0 Of
        $80 : CC := KClass[ikButton];
        $81 : CC := KClass[ikEdit];
        $82 : CC := KClass[ikStatic];
        $83 : CC := KClass[ikListBox];
        $84 : CC := KClass[ikScrollBar];
        $85 : CC := KClass[ikComboBox];
      End;
    End
    Else CC := ClassFind(ClsN);
    A := SzOrOrd(A, S, Ord0);
    P := MemW[0:A];
    A := A + 2 + P;
    If CC < 0 Then CC := KClass[ikStatic];
    C := CreateW(IEx, CC, S, (IStyle Or WS_CHILD) And Not WS_VISIBLE,
                 X * 2, Y * 2, CX * 2, CY * 2, W, Id, Inst, 0);
    If C >= 0 Then
    Begin
      If (IStyle And WS_VISIBLE) <> 0 Then Wnds[C].Visible := True;
      If (IStyle And WS_DISABLED) <> 0 Then Wnds[C].Enabled := False;
      If (Focus < 0) And ((IStyle And $10000) <> 0) Then Focus := C;
    End;
  End;
  If Proc <> 0 Then
    If CallProc(Proc, HwndOf(W), WM_INITDIALOG, HwndOf(Focus), Lp) <> 0 Then
      If Focus >= 0 Then SetFocusW(Focus);
  If Wnds[W].Used And ((Style And WS_VISIBLE) <> 0) Then ShowW(W, True, True);
  Wnds[W].KNeedPaint := True;
  DlgCreate := W;
End;

Function CreateDialogIndirectParamA(Inst, T, Parent, Proc, Lp : LongInt)
  : LongInt;
Begin
  CreateDialogIndirectParamA := HwndOf(DlgCreate(Inst, T, Parent, Proc, Lp));
End;

Function CreateDialogParamA(Inst, Name, Parent, Proc, Lp : LongInt) : LongInt;
Var E, Size : LongInt;
Begin
  CreateDialogParamA := 0;
  E := ResFind(AppModule(Inst), Name, 5);
  If E = 0 Then Exit;
  CreateDialogParamA := HwndOf(DlgCreate(Inst, ResData(AppModule(Inst), E,
                        Size), Parent, Proc, Lp));
End;

Function DlgRun(W, Parent : LongInt) : LongInt;
Var P : LongInt; M : TMsgRec; Pb : Array[0..6] Of LongInt;
Begin
  DlgRun := -1;
  If W < 0 Then Exit;
  P := WndOf(Parent);
  If P >= 0 Then Wnds[P].Enabled := False;
  ShowW(W, True, True);
  While Wnds[W].Used And Not Wnds[W].DlgEnded Do
  Begin
    If KPeekMsg(CurT, M, 0, 0, 0, True) Then
    Begin
      If M.Msg = WM_QUIT Then
      Begin
        PostQuitMessage(M.WP);
        Break;
      End;
      PutMsg(LongInt(@Pb), M);
      TranslateMessage(LongInt(@Pb));
      DispatchMessageA(LongInt(@Pb));
    End
    Else
    Begin
      Threads[CurT].State := tsMsg;
      Threads[CurT].WakeAt := Ticks + 50;
      KSchedule;
      Threads[CurT].State := tsReady;
    End;
  End;
  If P >= 0 Then Wnds[P].Enabled := True;
  If Wnds[W].Used Then
  Begin
    DlgRun := Wnds[W].DlgResult;
    DestroyW(W);
  End;
  If (P >= 0) And Wnds[P].Used Then ActivateW(P);
End;

Function DialogBoxParamA(Inst, Name, Parent, Proc, Lp : LongInt) : LongInt;
Var E, Size, W : LongInt;
Begin
  DialogBoxParamA := -1;
  E := ResFind(AppModule(Inst), Name, 5);
  If E = 0 Then Exit;
  W := DlgCreate(Inst, ResData(AppModule(Inst), E, Size), Parent, Proc, Lp);
  DialogBoxParamA := DlgRun(W, Parent);
End;

Function DialogBoxIndirectParamA(Inst, T, Parent, Proc, Lp : LongInt)
  : LongInt;
Begin
  DialogBoxIndirectParamA := DlgRun(DlgCreate(Inst, T, Parent, Proc, Lp),
                                    Parent);
End;

Function EndDialog(H, Res : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  EndDialog := 0;
  If W < 0 Then Exit;
  Wnds[W].DlgResult := Res;
  Wnds[W].DlgEnded := True;
  ShowW(W, False, False);
  EndDialog := 1;
End;

Function DefDlgProcA(H, Msg, WP, LP : LongInt) : LongInt;
Begin
  DefDlgProcA := 0;
  Case Msg Of
    WM_CLOSE : PostMessageA(H, WM_COMMAND, IDCANCEL, 0);
    WM_ERASEBKGND : DefDlgProcA := 1;
  Else
    DefDlgProcA := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function GetDlgItem(H, Id : LongInt) : LongInt;
Var W, I : LongInt;
Begin
  GetDlgItem := 0;
  W := WndOf(H);
  If W < 0 Then Exit;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And IsChildW(I) And (Wnds[I].Parent = W) And
       (Wnds[I].Id = Id) Then
    Begin
      GetDlgItem := HwndOf(I);
      Exit;
    End;
End;

Function GetDlgCtrlID(H : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  If W < 0 Then GetDlgCtrlID := 0 Else GetDlgCtrlID := Wnds[W].Id;
End;

Function SetDlgItemTextA(H, Id, S : LongInt) : LongInt;
Begin
  SetDlgItemTextA := SetWindowTextA(GetDlgItem(H, Id), S);
End;

Function GetDlgItemTextA(H, Id, Buf, N : LongInt) : LongInt;
Begin
  GetDlgItemTextA := GetWindowTextA(GetDlgItem(H, Id), Buf, N);
End;

Function SetDlgItemInt(H, Id, V, Signed : LongInt) : LongInt;
Var S : String;
Begin
  S := IntStr(V) + #0;
  SetDlgItemInt := SetWindowTextA(GetDlgItem(H, Id), LongInt(@S[1]));
End;

Function GetDlgItemInt(H, Id, POk, Signed : LongInt) : LongInt;
Var W, V, E : LongInt;
Begin
  GetDlgItemInt := 0;
  W := WndOf(GetDlgItem(H, Id));
  If W < 0 Then Exit;
  Val(Trim(Wnds[W].Text), V, E);
  If POk <> 0 Then MemL[0:POk] := Ord(E = 0);
  If E = 0 Then GetDlgItemInt := V;
End;

Function SendDlgItemMessageA(H, Id, Msg, WP, LP : LongInt) : LongInt;
Begin
  SendDlgItemMessageA := SendMessageA(GetDlgItem(H, Id), Msg, WP, LP);
End;

Function IsDlgButtonChecked(H, Id : LongInt) : LongInt;
Begin
  IsDlgButtonChecked := SendDlgItemMessageA(H, Id, BM_GETCHECK, 0, 0);
End;

Function CheckDlgButton(H, Id, C : LongInt) : LongInt;
Begin
  SendDlgItemMessageA(H, Id, BM_SETCHECK, C, 0);
  CheckDlgButton := 1;
End;

Function CheckRadioButton(H, First, Last, Id : LongInt) : LongInt;
Var I : LongInt;
Begin
  For I := First To Last Do
    SendDlgItemMessageA(H, I, BM_SETCHECK, Ord(I = Id), 0);
  CheckRadioButton := 1;
End;

Function IsDialogMessageA(H, P : LongInt) : LongInt;
Var W, M, Hw : LongInt;
Begin
  IsDialogMessageA := 0;
  W := WndOf(H);
  If (W < 0) Or (Wnds[W].IKind <> ikDialog) Then Exit;
  Hw := WndOf(MemL[0:P]);
  If (Hw <> W) And ((Hw < 0) Or (TopOf(Hw) <> W)) Then Exit;
  M := MemL[0:P + 4];
  If M = WM_KEYDOWN Then
  Begin
    If MemL[0:P + 8] = $0D Then
    Begin
      SendMsgW(W, WM_COMMAND, IDOK, 0);
      IsDialogMessageA := 1;
      Exit;
    End;
    If MemL[0:P + 8] = $1B Then
    Begin
      SendMsgW(W, WM_COMMAND, IDCANCEL, 0);
      IsDialogMessageA := 1;
      Exit;
    End;
  End;
  TranslateMessage(P);
  DispatchMessageA(P);
  IsDialogMessageA := 1;
End;

Function GetNextDlgTabItem(H, C, Prev : LongInt) : LongInt;
Begin
  GetNextDlgTabItem := C;
End;

Function MapDialogRect(H, P : LongInt) : LongInt;
Begin
  MemL[0:P] := MemL[0:P] * 2; MemL[0:P + 4] := MemL[0:P + 4] * 2;
  MemL[0:P + 8] := MemL[0:P + 8] * 2; MemL[0:P + 12] := MemL[0:P + 12] * 2;
  MapDialogRect := 1;
End;

Function GetDialogBaseUnits : LongInt;
Begin
  GetDialogBaseUnits := (16 Shl 16) Or 8;
End;

{ Boite de message d'un programme (modale) }
Function MessageBoxA(H, Text, Cap, Typ : LongInt) : LongInt;
Var T : String;
Begin
  If Cap = 0 Then T := 'Erreur' Else T := PStr(Cap);
  KLog('MessageBoxA "' + T + '" : ' + PStr(Text));
  MessageBoxA := MsgBoxModal(T, PStr(Text), Typ);
End;

Function MessageBoxExA(H, Text, Cap, Typ, Lang : LongInt) : LongInt;
Begin
  MessageBoxExA := MessageBoxA(H, Text, Cap, Typ);
End;

{ ==================================================================== }
{ Partie 11 - API Win32 WINMM, COMDLG32, SHELL32, OLE32, MSVFW32       }
{ ==================================================================== }
{ Pasdows emule une carte son muette (waveOut) ; les minuteries
  multimedia et la file des tampons de son sont executees par la
  tache 0. }

Function timeGetTime : LongInt;
Begin
  timeGetTime := Ticks;
End;

Function timeGetDevCaps(P, N : LongInt) : LongInt;
Begin
  MemL[0:P] := 1; MemL[0:P + 4] := 1000000;
  timeGetDevCaps := 0;
End;

Function timeBeginPeriod(P : LongInt) : LongInt;
Begin
  timeBeginPeriod := 0;
End;

Function timeEndPeriod(P : LongInt) : LongInt;
Begin
  timeEndPeriod := 0;
End;

Function timeSetEvent(Delay, Res, Proc, User, Flags : LongInt) : LongInt;
Var I : LongInt;
Begin
  timeSetEvent := 0;
  For I := 0 To MaxMMTimer - 1 Do
    If Not MMTimers[I].Used Then
    Begin
      MMTimers[I].Used := True;
      MMTimers[I].Delay := Max(1, Delay);
      MMTimers[I].Next := Ticks + Max(1, Delay);
      MMTimers[I].Proc := Proc;
      MMTimers[I].User := User;
      MMTimers[I].Flags := Flags;
      timeSetEvent := I + 1;
      Exit;
    End;
End;

Function timeKillEvent(Id : LongInt) : LongInt;
Begin
  timeKillEvent := 97;
  If (Id >= 1) And (Id <= MaxMMTimer) Then
  Begin
    MMTimers[Id - 1].Used := False;
    timeKillEvent := 0;
  End;
End;

{ ------------------------------------------------------------------ }
{ Carte son muette : les tampons waveOut sont acceptes et rendus      }
{ (WHDR_DONE, WOM_DONE) au rythme reel de leur duree, sans emettre de }
{ son ; les programmes synchronises sur le son avancent normalement.  }
{ ------------------------------------------------------------------ }

Const
  MaxWave = 4;
  MaxWaveQ = 64;
  HWaveBase = $9000;
  WOM_OPEN = $3BB; WOM_CLOSE = $3BC; WOM_DONE = $3BD;

Type
  TWaveDev = Record
    Used : Boolean;
    Paused : Boolean;
    Rate, Cb, Inst, CbType, QN, LastEnd, PauseAt : LongInt;
  End;

Var
  WaveDevs : Array[0..MaxWave - 1] Of TWaveDev;
  { files des tampons (peripherique I : entrees I * MaxWaveQ + K) }
  WaveQHdr, WaveQEnd : Array[0..MaxWave * MaxWaveQ - 1] Of LongInt;
  InWave : Boolean;

Function WaveOf(H : LongInt) : LongInt;
Begin
  WaveOf := -1;
  H := H - HWaveBase;
  If (H >= 0) And (H < MaxWave) Then
    If WaveDevs[H].Used Then WaveOf := H;
End;

{ Prevenir le programme (fenetre, tache, evenement ou fonction) }
Procedure WaveNotify(I, Msg, P1 : LongInt);
Var Cb, Inst, H : LongInt;
Begin
  Cb := WaveDevs[I].Cb; Inst := WaveDevs[I].Inst; H := HWaveBase + I;
  If Cb = 0 Then Exit;
  Case WaveDevs[I].CbType Of
    $10000 : PostMessageA(Cb, Msg, H, P1);
    $20000 : PostThreadMessageA(Cb, Msg, H, P1);
    $50000 : SetEvent(Cb);
    $30000 :
      asm
        push 0
        mov eax,P1
        push eax
        mov eax,Inst
        push eax
        mov eax,Msg
        push eax
        mov eax,H
        push eax
        mov eax,Cb
        call eax
      end;
  End;
End;

{ Tampon K de la file du peripherique I termine }
Procedure WaveDone(I, K : LongInt);
Var Hdr, J : LongInt;
Begin
  Hdr := WaveQHdr[I * MaxWaveQ + K];
  For J := K To WaveDevs[I].QN - 2 Do
  Begin
    WaveQHdr[I * MaxWaveQ + J] := WaveQHdr[I * MaxWaveQ + J + 1];
    WaveQEnd[I * MaxWaveQ + J] := WaveQEnd[I * MaxWaveQ + J + 1];
  End;
  Dec(WaveDevs[I].QN);
  MemL[0:Hdr + 16] := (MemL[0:Hdr + 16] And Not 16) Or 1;
  WaveNotify(I, WOM_DONE, Hdr);
End;

{ Appelee par la tache 0 : rendre les tampons dont la duree est passee }
Procedure RunWave;
Var I : LongInt;
Begin
  If InWave Then Exit;
  InWave := True;
  For I := 0 To MaxWave - 1 Do
    If WaveDevs[I].Used And Not WaveDevs[I].Paused Then
      While (WaveDevs[I].QN > 0) And (Ticks >= WaveQEnd[I * MaxWaveQ]) Do
        WaveDone(I, 0);
  InWave := False;
End;

Function waveOutGetNumDevs : LongInt;
Begin
  waveOutGetNumDevs := 1;
End;

{ WAVEOUTCAPSA : +0 fabricant, +2 produit, +4 version, +8 nom (32),
  +40 formats, +44 canaux, +48 possibilites }
Function waveOutGetDevCapsA(Id, P, N : LongInt) : LongInt;
Begin
  waveOutGetDevCapsA := 11;
  If (P = 0) Or (N < 52) Then Exit;
  FillMem(P, 52, 0);
  MemW[0:P] := 1; MemW[0:P + 2] := 1;
  MemL[0:P + 4] := $0400;
  PutPStr(P + 8, 'Pasdows Son', 32);
  MemL[0:P + 40] := $FFF;
  MemW[0:P + 44] := 2;
  MemL[0:P + 48] := $C;
  waveOutGetDevCapsA := 0;
End;

Function waveOutOpen(PH, Id, Fmt, Cb, Inst, Flags : LongInt) : LongInt;
Var I, K : LongInt;
Begin
  waveOutOpen := 0;
  { WAVE_FORMAT_QUERY : tous les formats sont acceptes }
  If (Flags And 1) <> 0 Then Exit;
  I := -1;
  For K := MaxWave - 1 DownTo 0 Do
    If Not WaveDevs[K].Used Then I := K;
  If I < 0 Then
  Begin
    waveOutOpen := 4;
    Exit;
  End;
  WaveDevs[I].Used := True;
  WaveDevs[I].Paused := False;
  WaveDevs[I].Rate := 11025;
  If Fmt <> 0 Then
    If MemL[0:Fmt + 8] > 0 Then WaveDevs[I].Rate := MemL[0:Fmt + 8];
  WaveDevs[I].Cb := Cb;
  WaveDevs[I].Inst := Inst;
  WaveDevs[I].CbType := Flags And $70000;
  WaveDevs[I].QN := 0;
  WaveDevs[I].LastEnd := Ticks;
  If PH <> 0 Then MemL[0:PH] := HWaveBase + I;
  WaveNotify(I, WOM_OPEN, 0);
End;

Function waveOutClose(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  waveOutClose := 5;
  I := WaveOf(H);
  If I < 0 Then Exit;
  If WaveDevs[I].QN > 0 Then
  Begin
    waveOutClose := 33;
    Exit;
  End;
  WaveNotify(I, WOM_CLOSE, 0);
  WaveDevs[I].Used := False;
  waveOutClose := 0;
End;

{ WAVEHDR : +0 donnees, +4 longueur, +8, +12 utilisateur, +16 drapeaux }
Function waveOutPrepareHeader(H, Hdr, N : LongInt) : LongInt;
Begin
  waveOutPrepareHeader := 11;
  If Hdr = 0 Then Exit;
  MemL[0:Hdr + 16] := MemL[0:Hdr + 16] Or 2;
  waveOutPrepareHeader := 0;
End;

Function waveOutUnprepareHeader(H, Hdr, N : LongInt) : LongInt;
Begin
  waveOutUnprepareHeader := 11;
  If Hdr = 0 Then Exit;
  If (MemL[0:Hdr + 16] And 16) <> 0 Then
  Begin
    waveOutUnprepareHeader := 33;
    Exit;
  End;
  MemL[0:Hdr + 16] := MemL[0:Hdr + 16] And Not 2;
  waveOutUnprepareHeader := 0;
End;

Function waveOutWrite(H, Hdr, N : LongInt) : LongInt;
Var I, Len, R, St, Q : LongInt;
Begin
  waveOutWrite := 5;
  I := WaveOf(H);
  If I < 0 Then Exit;
  If (MemL[0:Hdr + 16] And 2) = 0 Then
  Begin
    waveOutWrite := 34;
    Exit;
  End;
  Q := WaveDevs[I].QN;
  If Q >= MaxWaveQ Then
  Begin
    waveOutWrite := 7;
    Exit;
  End;
  MemL[0:Hdr + 16] := (MemL[0:Hdr + 16] Or 16) And Not 1;
  Len := MemL[0:Hdr + 4]; R := WaveDevs[I].Rate;
  St := Max(Ticks, WaveDevs[I].LastEnd);
  WaveDevs[I].LastEnd := St + (Len Div R) * 1000 + ((Len Mod R) * 1000) Div R;
  WaveQHdr[I * MaxWaveQ + Q] := Hdr;
  WaveQEnd[I * MaxWaveQ + Q] := WaveDevs[I].LastEnd;
  WaveDevs[I].QN := Q + 1;
  waveOutWrite := 0;
End;

Function waveOutReset(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  waveOutReset := 5;
  I := WaveOf(H);
  If I < 0 Then Exit;
  While WaveDevs[I].QN > 0 Do WaveDone(I, 0);
  WaveDevs[I].LastEnd := Ticks;
  WaveDevs[I].Paused := False;
  waveOutReset := 0;
End;

Function waveOutPause(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  waveOutPause := 5;
  I := WaveOf(H);
  If I < 0 Then Exit;
  If Not WaveDevs[I].Paused Then
  Begin
    WaveDevs[I].Paused := True;
    WaveDevs[I].PauseAt := Ticks;
  End;
  waveOutPause := 0;
End;

Function waveOutRestart(H : LongInt) : LongInt;
Var I, K, D : LongInt;
Begin
  waveOutRestart := 5;
  I := WaveOf(H);
  If I < 0 Then Exit;
  If WaveDevs[I].Paused Then
  Begin
    D := Ticks - WaveDevs[I].PauseAt;
    For K := 0 To WaveDevs[I].QN - 1 Do
      WaveQEnd[I * MaxWaveQ + K] := WaveQEnd[I * MaxWaveQ + K] + D;
    WaveDevs[I].LastEnd := WaveDevs[I].LastEnd + D;
    WaveDevs[I].Paused := False;
  End;
  waveOutRestart := 0;
End;

Function waveOutGetVolume(H, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := -1;
  waveOutGetVolume := 0;
End;

Function waveOutSetVolume(H, V : LongInt) : LongInt;
Begin
  waveOutSetVolume := 0;
End;

Function midiOutGetNumDevs : LongInt;
Begin
  midiOutGetNumDevs := 0;
End;

Function auxGetNumDevs : LongInt;
Begin
  auxGetNumDevs := 0;
End;

Function sndPlaySoundA(S, F : LongInt) : LongInt;
Begin
  sndPlaySoundA := 1;
End;

Function PlaySoundA(S, M, F : LongInt) : LongInt;
Begin
  PlaySoundA := 1;
End;

Function DefDriverProc(Id, Drv, Msg, P1, P2 : LongInt) : LongInt;
Begin
  DefDriverProc := 0;
End;

Function mciSendCommandA(Id, Msg, Flags, P : LongInt) : LongInt;
Begin
  mciSendCommandA := 263;
End;

Function mciSendStringA(Cmd, Ret, N, Cb : LongInt) : LongInt;
Begin
  KLog('mciSendStringA : ' + PStr(Cmd));
  If (Ret <> 0) And (N > 0) Then Mem[0:Ret] := 0;
  mciSendStringA := 263;
End;

Function mciGetErrorStringA(E, Buf, N : LongInt) : LongInt;
Begin
  PutPStr(Buf, L('Aucun p'#130'riph'#130'rique MCI.', 'No MCI device.',
          'Kein MCI-Ger'#132't.', 'Nessuna periferica MCI.',
          'Ning'#163'n dispositivo MCI.'), N);
  mciGetErrorStringA := 1;
End;

{ COMDLG32 }
Function GetOpenFileNameA(P : LongInt) : LongInt;
Begin
  GetOpenFileNameA := 0;
End;

Function GetSaveFileNameA(P : LongInt) : LongInt;
Begin
  GetSaveFileNameA := 0;
End;

Function PrintDlgA(P : LongInt) : LongInt;
Begin
  PrintDlgA := 0;
End;

Function ChooseColorA(P : LongInt) : LongInt;
Begin
  ChooseColorA := 0;
End;

Function CommDlgExtendedError : LongInt;
Begin
  CommDlgExtendedError := 0;
End;

{ SHELL32 }
Function FindExecutableA(F, D, Res : LongInt) : LongInt;
Begin
  If Res <> 0 Then Mem[0:Res] := 0;
  FindExecutableA := 31;
End;

Function ShellExecuteA(H, Op, F, Prm, D, Show : LongInt) : LongInt;
Begin
  If RunExe(PStr(F), PStr(Prm)) Then ShellExecuteA := 33
  Else ShellExecuteA := 2;
End;

{ OLE32 }
Function CoInitialize(P : LongInt) : LongInt;
Begin
  CoInitialize := 0;
End;

Procedure CoUninitialize;
Begin
End;

Function CoCreateInstance(Clsid, Outer, Ctx, Iid, PP : LongInt) : LongInt;
Begin
  If PP <> 0 Then MemL[0:PP] := 0;
  CoCreateInstance := LongInt($80040154);
End;

Function OleInitialize(P : LongInt) : LongInt;
Begin
  OleInitialize := 0;
End;

Procedure OleUninitialize;
Begin
End;

{ MSVFW32 (Video pour Windows : aucun compresseur) }
Function ICClose(H : LongInt) : LongInt;
Begin
  ICClose := 0;
End;

Function ICGetDisplayFormat(H, PIn, POut, Depth, DX, DY : LongInt)
  : LongInt;
Begin
  ICGetDisplayFormat := 0;
End;

Function ICOpen(T, H, M : LongInt) : LongInt;
Begin
  ICOpen := 0;
End;

Function ICLocate(T, H, PIn, POut, F : LongInt) : LongInt;
Begin
  ICLocate := 0;
End;

{ ADVAPI32 (registre : vide) }
Function RegOpenKeyExA(K, Sub, Opt, Sam, PR : LongInt) : LongInt;
Begin
  RegOpenKeyExA := 2;
End;

Function RegOpenKeyA(K, Sub, PR : LongInt) : LongInt;
Begin
  RegOpenKeyA := 2;
End;

Function RegCreateKeyA(K, Sub, PR : LongInt) : LongInt;
Begin
  If PR <> 0 Then MemL[0:PR] := $4321;
  RegCreateKeyA := 0;
End;

Function RegCloseKey(K : LongInt) : LongInt;
Begin
  RegCloseKey := 0;
End;

Function RegQueryValueExA(K, N, R, PT, PD, PN : LongInt) : LongInt;
Begin
  RegQueryValueExA := 2;
End;

Function RegSetValueExA(K, N, R, T, D, Sz : LongInt) : LongInt;
Begin
  RegSetValueExA := 0;
End;

{ ==================================================================== }
{ Partie 12 - Chargeur de programmes PE (EXE et DLL Windows 95)        }
{ ==================================================================== }
{ Un programme Win32 est charge a son adresse de base si elle est libre
  (fenetre 00400000h-00FFFFFFh, hors du tas), sinon dans le tas avec
  application des relocalisations (.reloc). Chaque importation est liee
  par son nom a la fonction du meme nom de la table d'exportation de
  VMM32.VXD (quelle que soit la DLL : KERNEL32, USER32, GDI32...) ; une
  fonction absente est liee a une souche qui affiche son nom si elle
  est appelee. Les DLL de l'application (LoadLibrary) sont chargees de
  la meme facon et leurs exportations sont consultees en premier. }

Const
  MaxMod = 16;
  SysDlls : Array[0..13] Of String[12] = ('KERNEL32.DLL', 'USER32.DLL',
    'GDI32.DLL', 'WINMM.DLL', 'COMDLG32.DLL', 'SHELL32.DLL', 'OLE32.DLL',
    'MSVFW32.DLL', 'ADVAPI32.DLL', 'VERSION.DLL', 'COMCTL32.DLL',
    'OLEAUT32.DLL', 'MSVCRT.DLL', 'WSOCK32.DLL');

Type
  TModule = Record
    Used : Boolean;
    Base, Size, Entry : LongInt;
    Name : String[63];
    Path : String[127];
    IsDll : Boolean;
  End;

Var
  Mods      : Array[0..MaxMod - 1] Of TModule;
  KExpCount, KExpFuncs, KExpNames, KExpOrds, KBase : LongInt;
  StubArea, StubNext, TraceCount, TraceRetStub : LongInt;
  TrRet, TrName : Array[0..MaxThread * 32 - 1] Of LongInt;
  TrDepth : Array[0..MaxThread - 1] Of LongInt;
  TraceSkip : String;
  AppProcObj : LongInt;
  AppMainT  : LongInt;

{ Table d'exportation du noyau (son image PE) }
Procedure InitExports;
Var Pe, Dir : LongInt;
Begin
  KBase := MemL[0:BootInfo + $1C];
  Pe := KBase + MemL[0:KBase + $3C];
  Dir := MemL[0:Pe + 24 + 96];
  KExpCount := 0;
  If Dir = 0 Then Exit;
  Dir := KBase + Dir;
  KExpCount := MemL[0:Dir + 24];
  KExpFuncs := KBase + MemL[0:Dir + 28];
  KExpNames := KBase + MemL[0:Dir + 32];
  KExpOrds := KBase + MemL[0:Dir + 36];
  KLog('VMM32 : ' + IntStr(KExpCount) + ' fonctions exportees');
End;

Function MemNameEq(A : LongInt; U : String) : Boolean;
Var I, C : LongInt;
Begin
  MemNameEq := False;
  For I := 1 To Length(U) Do
  Begin
    C := Mem[0:A + I - 1];
    If C <> Ord(U[I]) Then Exit;
  End;
  MemNameEq := Mem[0:A + Length(U)] = 0;
End;

{ Recherche dichotomique (noms tries) d'une exportation exacte }
Function KernelExport(Name : String) : LongInt;
Var Lo, Hi, M, A, I, C1, C2, R : LongInt;
Begin
  KernelExport := 0;
  Lo := 0; Hi := KExpCount - 1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    A := KBase + MemL[0:KExpNames + M * 4];
    R := 0; I := 1;
    Repeat
      C1 := Mem[0:A + I - 1];
      If I <= Length(Name) Then C2 := Ord(Name[I]) Else C2 := 0;
      If C1 <> C2 Then
      Begin
        If C2 < C1 Then R := -1 Else R := 1;
        Break;
      End;
      Inc(I);
    Until C1 = 0;
    If R = 0 Then
    Begin
      KernelExport := KBase + MemL[0:KExpFuncs + MemW[0:KExpOrds + M * 2] *
                      4];
      Exit;
    End;
    If R < 0 Then Hi := M - 1 Else Lo := M + 1;
  End;
  { sans tenir compte de la casse (noms ecrits autrement en Pascal) }
  Name := UpStr(Name);
  For I := 0 To KExpCount - 1 Do
  Begin
    A := KBase + MemL[0:KExpNames + I * 4];
    If UpStr(PStr(A)) = Name Then
    Begin
      KernelExport := KBase + MemL[0:KExpFuncs + MemW[0:KExpOrds + I * 2] *
                      4];
      Exit;
    End;
  End;
End;

Procedure ApiMissing(Name : LongInt);
Begin
  KLog('API non disponible : ' + PStr(Name));
  MsgBoxOpen('Pasdows', L('La fonction ', 'The function ', 'Die Funktion ',
             'La funzione ', 'La funci'#162'n ') + PStr(Name) +
             L(' n''est pas disponible.', ' is not available.',
             ' ist nicht verf'#129'gbar.', ' non '#138' disponibile.',
             ' no est'#160' disponible.'), $10);
  If (CurT > 0) And Threads[CurT].IsApp Then
  Begin
    KillApp;
    Threads[CurT].State := tsDead;
    KSchedule;
  End;
  HaltCpu;
End;

Procedure MissingApi(Name : LongInt);
Begin
  ApiMissing(Name);
End;

{ Souche d'une fonction absente : push nom / call MissingApi }
Function MakeStub(Dll, Name : String) : LongInt;
Var A, N : LongInt;
Begin
  If StubArea = 0 Then
  Begin
    StubArea := KAlloc(65536);
    StubNext := StubArea;
  End;
  A := StubNext;
  PutPStr(A + 16, Dll + '!' + Name, 80);
  Mem[0:A] := $68; MemL[0:A + 1] := A + 16;
  Mem[0:A + 5] := $B8; MemL[0:A + 6] := LongInt(@MissingApi);
  Mem[0:A + 10] := $FF; Mem[0:A + 11] := $D0;
  Mem[0:A + 12] := $CC;
  StubNext := StubNext + 16 + Length(Dll) + Length(Name) + 2 + 15;
  StubNext := (StubNext + 15) And Not 15;
  MakeStub := A;
End;

{ Trace des appels d'API (journal serie), active par ApiTrace }
Procedure TraceApi(Name : LongInt);
Var F, D : LongInt; S : String;
Begin
  If TraceCount < 8000 Then
  Begin
    Inc(TraceCount);
    asm
      mov eax,ebp
      mov F,eax
    end;
    S := '> ' + PStr(Name) + ' @' + HexStr(MemL[0:F + 44], 8);
    S := S + ' ' + HexStr(MemL[0:F + 48], 8) + ' ' + HexStr(MemL[0:F + 52], 8);
    S := S + ' ' + HexStr(MemL[0:F + 56], 8) + ' ' + HexStr(MemL[0:F + 60], 8);
    KLog(S);
    { detourner le retour vers TraceRetStub (pile fantome par tache) }
    D := TrDepth[CurT];
    If (D < 32) And (TraceRetStub <> 0) Then
    Begin
      TrRet[CurT * 32 + D] := MemL[0:F + 44];
      TrName[CurT * 32 + D] := Name;
      TrDepth[CurT] := D + 1;
      MemL[0:F + 44] := TraceRetStub;
    End;
  End;
End;

{ Appelee par TraceRetStub : push 0 / pushad / call TraceRetK / popad / ret }
Procedure TraceRetK;
Var F, D : LongInt;
Begin
  asm
    mov eax,ebp
    mov F,eax
  end;
  D := TrDepth[CurT] - 1;
  If D < 0 Then
  Begin
    KLog('TraceRet : pile fantome vide');
    HaltCpu;
  End;
  TrDepth[CurT] := D;
  MemL[0:F + 40] := TrRet[CurT * 32 + D];
  KLog('< ' + PStr(TrName[CurT * 32 + D]) + ' = ' + HexStr(MemL[0:F + 36], 8));
End;

Procedure TraceInit;
Var A : LongInt;
Begin
  A := KAlloc(32);
  Mem[0:A] := $6A; Mem[0:A + 1] := 0;
  Mem[0:A + 2] := $60;
  Mem[0:A + 3] := $B8; MemL[0:A + 4] := LongInt(@TraceRetK);
  Mem[0:A + 8] := $FF; Mem[0:A + 9] := $D0;
  Mem[0:A + 10] := $61;
  Mem[0:A + 11] := $C3;
  TraceRetStub := A;
  TraceSkip := ' SETFILEPOINTER ISBADREADPTR GETTICKCOUNT TIMEGETTIME ';
  TraceSkip := TraceSkip + 'GETASYNCKEYSTATE PEEKMESSAGEA SCREENTOCLIENT ';
  TraceSkip := TraceSkip + 'GETCURSORPOS ISBADWRITEPTR LSTRCMPIA ';
  TraceSkip := TraceSkip + 'GETDEVICECAPS ';
End;

Function MakeTrace(Dll, Name : String; Target : LongInt) : LongInt;
Var A : LongInt;
Begin
  If StubArea = 0 Then
  Begin
    StubArea := KAlloc(65536);
    StubNext := StubArea;
  End;
  A := StubNext;
  If A + 128 > StubArea + 65536 Then
  Begin
    MakeTrace := Target;
    Exit;
  End;
  PutPStr(A + 32, Dll + '!' + Name, 80);
  Mem[0:A] := $60;
  Mem[0:A + 1] := $68; MemL[0:A + 2] := A + 32;
  Mem[0:A + 6] := $B8; MemL[0:A + 7] := LongInt(@TraceApi);
  Mem[0:A + 11] := $FF; Mem[0:A + 12] := $D0;
  Mem[0:A + 13] := $83; Mem[0:A + 14] := $C4; Mem[0:A + 15] := 4;
  Mem[0:A + 16] := $61;
  Mem[0:A + 17] := $B8; MemL[0:A + 18] := Target;
  Mem[0:A + 22] := $FF; Mem[0:A + 23] := $E0;
  StubNext := StubNext + 32 + Length(Dll) + Length(Name) + 2;
  StubNext := (StubNext + 15) And Not 15;
  MakeTrace := A;
End;

Function IsSysDll(Name : String) : Boolean;
Var I : LongInt;
Begin
  IsSysDll := False;
  Name := UpStr(BaseName(Name));
  If Pos('.', Name) = 0 Then Name := Name + '.DLL';
  For I := 0 To 13 Do
    If SysDlls[I] = Name Then IsSysDll := True;
End;

Function FindModule(Name : String) : LongInt;
Var I : LongInt;
Begin
  FindModule := -1;
  Name := UpStr(BaseName(Name));
  If Pos('.', Name) = 0 Then Name := Name + '.DLL';
  For I := 0 To MaxMod - 1 Do
    If Mods[I].Used And (Mods[I].Name = Name) Then
    Begin
      FindModule := I;
      Exit;
    End;
End;

Function ModOfBase(B : LongInt) : LongInt;
Var I : LongInt;
Begin
  ModOfBase := -1;
  For I := 0 To MaxMod - 1 Do
    If Mods[I].Used And (Mods[I].Base = B) Then
    Begin
      ModOfBase := I;
      Exit;
    End;
End;

{ Exportation d'un module charge (par nom, ou par ordinal si Name='') }
Function ModuleExport(M : LongInt; Name : String; Ordinal : LongInt)
  : LongInt;
Var Pe, Dir, N, Funcs, Names, Ords, I, B : LongInt;
Begin
  ModuleExport := 0;
  If (M < 0) Or Not Mods[M].Used Then Exit;
  B := Mods[M].Base;
  Pe := B + MemL[0:B + $3C];
  Dir := MemL[0:Pe + 24 + 96];
  If Dir = 0 Then Exit;
  Dir := B + Dir;
  Funcs := B + MemL[0:Dir + 28];
  If Name = '' Then
  Begin
    I := Ordinal - MemL[0:Dir + 16];
    If (I >= 0) And (I < MemL[0:Dir + 20]) And (MemL[0:Funcs + I * 4] <> 0)
    Then ModuleExport := B + MemL[0:Funcs + I * 4];
    Exit;
  End;
  N := MemL[0:Dir + 24];
  Names := B + MemL[0:Dir + 32];
  Ords := B + MemL[0:Dir + 36];
  For I := 0 To N - 1 Do
    If MemNameEq(B + MemL[0:Names + I * 4], Name) Then
    Begin
      ModuleExport := B + MemL[0:Funcs + MemW[0:Ords + I * 2] * 4];
      Exit;
    End;
End;

Function LoadPE(Path : String; IsDll : Boolean) : LongInt; Forward;

{ MSVFW32 : version de Video pour Windows (1.10) }
Function VideoForWindowsVersion : LongInt;
Begin
  VideoForWindowsVersion := $010A0000;
End;

Function ResolveImport(Dll, Name : String; Ordinal : LongInt) : LongInt;
Var M, A : LongInt; Nm : String;
Begin
  A := 0;
  { importations par ordinal des DLL systeme connues }
  If (Name = '') And (UpStr(BaseName(Dll)) = 'MSVFW32.DLL') And
     (Ordinal = 2) Then Name := 'VideoForWindowsVersion';
  If Not IsSysDll(Dll) Then
  Begin
    M := FindModule(Dll);
    If M < 0 Then M := LoadPE(Dll, True);
    If M >= 0 Then A := ModuleExport(M, Name, Ordinal);
  End;
  If (A = 0) And (Name <> '') Then A := KernelExport(Name);
  If (A = 0) And (Length(Name) > 1) And (Name[1] = '_') Then
    A := KernelExport(Copy(Name, 2, 255));
  If A = 0 Then
  Begin
    If Name = '' Then Name := '#' + IntStr(Ordinal);
    KLog('  importation absente : ' + Dll + '!' + Name);
    A := MakeStub(Dll, Name);
  End;
  If ApiTrace Then
  Begin
    Nm := ' ' + UpStr(Name) + ' ';
    If Pos(Nm, TraceSkip) = 0 Then A := MakeTrace(Dll, Name, A);
  End;
  ResolveImport := A;
End;

{ Chercher un fichier de module : chemin donne, D:\, C:\WINDOWS }
Function FindModuleFile(Name : String) : String;
Var Attr, Size, Time, Lba, Ram : LongInt; S : String;
Begin
  FindModuleFile := '';
  S := FullPath(Name);
  If PathInfo(S, Attr, Size, Time, Lba, Ram) Then
  Begin
    FindModuleFile := S;
    Exit;
  End;
  If Pos('.', BaseName(Name)) = 0 Then
  Begin
    S := FullPath(Name + '.EXE');
    If PathInfo(S, Attr, Size, Time, Lba, Ram) Then
    Begin
      FindModuleFile := S;
      Exit;
    End;
  End;
  S := 'D:\' + UpStr(BaseName(Name));
  If PathInfo(S, Attr, Size, Time, Lba, Ram) Then FindModuleFile := S;
End;

{ Charger un EXE ou une DLL ; indice du module ou -1 }
Function LoadPE(Path : String; IsDll : Boolean) : LongInt;
Var F, FSize, Pe, NSect, OptSz, Base, ImgSize, HdrSize, Load, I, S, VSize,
    VAddr, RawSize, RawPtr, Delta, Dir, DSize, P, PEnd, Cnt, K, T, Ent,
    Imp, NameRva, Thunk, IAT, V, M : LongInt; Dll, Nm : String;
Begin
  LoadPE := -1;
  M := FindModule(Path);
  If M >= 0 Then
  Begin
    LoadPE := M;
    Exit;
  End;
  Path := FindModuleFile(Path);
  If Path = '' Then Exit;
  F := LoadWholeFile(Path, FSize);
  If F = 0 Then Exit;
  KLog('Chargement de ' + Path + ' (' + IntStr(FSize) + ' octets)');
  If MemW[0:F] <> $5A4D Then
  Begin
    KFree(F);
    Exit;
  End;
  Pe := F + MemL[0:F + $3C];
  If (MemL[0:Pe] <> $4550) Or (MemW[0:Pe + 4] <> $014C) Then
  Begin
    KLog('  pas une image PE 80386');
    KFree(F);
    Exit;
  End;
  NSect := MemW[0:Pe + 6];
  OptSz := MemW[0:Pe + 20];
  Base := MemL[0:Pe + 24 + 28];
  ImgSize := MemL[0:Pe + 24 + 56];
  HdrSize := MemL[0:Pe + 24 + 60];
  { adresse de chargement }
  If Not IsDll And (Base >= $00400000) And (Base + ImgSize <= HeapBase) Then
    Load := Base
  Else
  Begin
    Load := KAlloc(ImgSize + 65536);
    If Load = 0 Then
    Begin
      KFree(F);
      Exit;
    End;
    Load := (Load + 65535) And Not 65535;
  End;
  FillMem(Load, ImgSize, 0);
  MoveMem(F, Load, Min(HdrSize, FSize));
  S := Pe + 24 + OptSz;
  For I := 0 To NSect - 1 Do
  Begin
    VSize := MemL[0:S + 8]; VAddr := MemL[0:S + 12];
    RawSize := MemL[0:S + 16]; RawPtr := MemL[0:S + 20];
    If (VSize = 0) Or (RawSize < VSize) Then VSize := RawSize;
    If (RawSize > 0) And (RawPtr + VSize <= FSize) Then
      MoveMem(F + RawPtr, Load + VAddr, Min(VSize, RawSize));
    S := S + 40;
  End;
  KFree(F);
  Pe := Load + MemL[0:Load + $3C];
  { relocalisations }
  Delta := Load - Base;
  If Delta <> 0 Then
  Begin
    Dir := MemL[0:Pe + 24 + 136]; DSize := MemL[0:Pe + 24 + 140];
    If Dir = 0 Then KLog('  pas de relocalisations : chargement a ' +
                         HexStr(Load, 8));
    P := Load + Dir; PEnd := P + DSize;
    While (Dir <> 0) And (P < PEnd) And (MemL[0:P + 4] > 0) Do
    Begin
      Cnt := (MemL[0:P + 4] - 8) Div 2;
      For K := 0 To Cnt - 1 Do
      Begin
        T := MemW[0:P + 8 + K * 2];
        If (T Shr 12) = 3 Then
        Begin
          V := Load + MemL[0:P] + (T And $FFF);
          MemL[0:V] := MemL[0:V] + Delta;
        End;
      End;
      P := P + MemL[0:P + 4];
    End;
    MemL[0:Pe + 24 + 28] := Load;
  End;
  { module }
  M := -1;
  For I := 0 To MaxMod - 1 Do
    If Not Mods[I].Used Then
    Begin
      M := I;
      Break;
    End;
  If M < 0 Then Exit;
  Mods[M].Used := True; Mods[M].Base := Load; Mods[M].Size := ImgSize;
  Mods[M].Entry := MemL[0:Pe + 24 + 16];
  If Mods[M].Entry <> 0 Then Mods[M].Entry := Load + Mods[M].Entry;
  Mods[M].Name := UpStr(BaseName(Path));
  Mods[M].Path := Path;
  Mods[M].IsDll := IsDll;
  { importations }
  Dir := MemL[0:Pe + 24 + 104];
  If Dir <> 0 Then
  Begin
    Imp := Load + Dir;
    While MemL[0:Imp + 12] <> 0 Do
    Begin
      NameRva := MemL[0:Imp + 12];
      Dll := UpStr(PStr(Load + NameRva));
      Thunk := MemL[0:Imp];
      IAT := Load + MemL[0:Imp + 16];
      If Thunk = 0 Then Thunk := MemL[0:Imp + 16];
      Thunk := Load + Thunk;
      Ent := 0;
      While MemL[0:Thunk + Ent * 4] <> 0 Do
      Begin
        V := MemL[0:Thunk + Ent * 4];
        If V < 0 Then
          MemL[0:IAT + Ent * 4] := ResolveImport(Dll, '', V And $FFFF)
        Else
        Begin
          Nm := PStr(Load + V + 2);
          MemL[0:IAT + Ent * 4] := ResolveImport(Dll, Nm, 0);
        End;
        Inc(Ent);
      End;
      Imp := Imp + 20;
    End;
  End;
  KLog('  module ' + Mods[M].Name + ' a ' + HexStr(Load, 8) + ' point ' +
       HexStr(Mods[M].Entry, 8));
  { DllMain(hinst, DLL_PROCESS_ATTACH, 0) }
  If IsDll And (Mods[M].Entry <> 0) Then
  Begin
    V := Mods[M].Entry;
    asm
      push 0
      push 1
      mov eax,Load
      push eax
      mov eax,V
      call eax
    end;
  End;
  LoadPE := M;
End;

{ ------------------------------------------------------------------ }
{ Modules et ressources (KERNEL32)                                   }
{ ------------------------------------------------------------------ }

{ Module d'une instance (0 : le programme) }
Function AppModule(H : LongInt) : LongInt;
Begin
  If (H = 0) Or (H = -1) Then AppModule := AppBase Else AppModule := H;
End;

Function GetModuleHandleA(P : LongInt) : LongInt;
Var Nm : String; M, I : LongInt;
Begin
  If P = 0 Then
  Begin
    GetModuleHandleA := AppBase;
    Exit;
  End;
  Nm := PStr(P);
  M := FindModule(Nm);
  If M >= 0 Then
  Begin
    GetModuleHandleA := Mods[M].Base;
    Exit;
  End;
  M := 0;
  Nm := UpStr(BaseName(Nm));
  If Pos('.', Nm) = 0 Then Nm := Nm + '.DLL';
  For I := 0 To 13 Do
    If SysDlls[I] = Nm Then M := HDllBase + I * $10000;
  If M = 0 Then SetErr(126);
  GetModuleHandleA := M;
End;

Function GetModuleFileNameA(H, Buf, N : LongInt) : LongInt;
Var S : String; M : LongInt;
Begin
  If (H = 0) Or (H = AppBase) Then S := AppPath
  Else
  Begin
    M := ModOfBase(H);
    If M >= 0 Then S := Mods[M].Path
    Else If (H >= HDllBase) And (H < HDllBase + 14 * $10000) Then
      S := 'C:\WINDOWS\SYSTEM\' + SysDlls[(H - HDllBase) Div $10000]
    Else S := AppPath;
  End;
  PutPStr(Buf, S, N);
  GetModuleFileNameA := Min(Length(S), N - 1);
End;

Function LoadLibraryA(P : LongInt) : LongInt;
Var Nm : String; M, H : LongInt;
Begin
  Nm := PStr(P);
  H := 0;
  If IsSysDll(Nm) Then H := GetModuleHandleA(P)
  Else
  Begin
    M := LoadPE(Nm, True);
    If M >= 0 Then H := Mods[M].Base;
  End;
  KLog('LoadLibraryA ' + Nm + ' -> ' + HexStr(H, 8));
  If H = 0 Then SetErr(126);
  LoadLibraryA := H;
End;

Function LoadLibraryExA(P, F, Flags : LongInt) : LongInt;
Begin
  LoadLibraryExA := LoadLibraryA(P);
End;

Function FreeLibrary(H : LongInt) : LongInt;
Begin
  FreeLibrary := 1;
End;

Function GetProcAddress(H, P : LongInt) : LongInt;
Var M, R : LongInt; Nm : String;
Begin
  GetProcAddress := 0;
  M := ModOfBase(H);
  If (P >= 0) And (P < $10000) Then
  Begin
    If M >= 0 Then GetProcAddress := ModuleExport(M, '', P);
    Exit;
  End;
  Nm := PStr(P);
  If M >= 0 Then R := ModuleExport(M, Nm, 0)
  Else R := KernelExport(Nm);
  If (R = 0) And (M < 0) And (Length(Nm) > 1) And (Nm[1] = '_') Then
    R := KernelExport(Copy(Nm, 2, 255));
  If R = 0 Then
  Begin
    KLog('GetProcAddress absent : ' + Nm);
    SetErr(127);
  End;
  GetProcAddress := R;
End;

{ Ressources : repertoire .rsrc (type, nom, langue) }
Function ResDirFind(Base, Dir, Id : LongInt) : LongInt;
Var NNamed, NId, I, E, Nm, S, K : LongInt; U : String; Ok : Boolean;
Begin
  ResDirFind := 0;
  NNamed := MemW[0:Dir + 12]; NId := MemW[0:Dir + 14];
  E := Dir + 16;
  For I := 0 To NNamed + NId - 1 Do
  Begin
    Nm := MemL[0:E + I * 8];
    If (Id >= 0) And (Id < $10000) Then
      Ok := ((Nm And LongInt($80000000)) = 0) And (Nm = Id)
    Else
    Begin
      Ok := False;
      If (Nm And LongInt($80000000)) <> 0 Then
      Begin
        S := Base + (Nm And $7FFFFFFF);
        U := '';
        For K := 0 To MemW[0:S] - 1 Do
          U := U + Chr(UpCh(MemW[0:S + 2 + K * 2] And 255));
        Ok := U = UpStr(PStr(Id));
      End;
    End;
    If Ok Then
    Begin
      ResDirFind := MemL[0:E + I * 8 + 4];
      Exit;
    End;
  End;
End;

{ Entree de donnees (IMAGE_RESOURCE_DATA_ENTRY) ou 0 }
Function ResFind(Module, Name, Typ : LongInt) : LongInt;
Var Pe, Rva, Base, D, E, N, V : LongInt; S : String;
Begin
  ResFind := 0;
  If Module = 0 Then Exit;
  Pe := Module + MemL[0:Module + $3C];
  Rva := MemL[0:Pe + 24 + 112];
  If Rva = 0 Then Exit;
  Base := Module + Rva;
  { "#123" -> 123 }
  If (Name >= $10000) And (Mem[0:Name] = Ord('#')) Then
  Begin
    S := PStr(Name + 1);
    Val(S, N, V);
    If V = 0 Then Name := N;
  End;
  If (Typ >= $10000) And (Mem[0:Typ] = Ord('#')) Then
  Begin
    S := PStr(Typ + 1);
    Val(S, N, V);
    If V = 0 Then Typ := N;
  End;
  E := ResDirFind(Base, Base, Typ);
  If (E And LongInt($80000000)) = 0 Then Exit;
  D := Base + (E And $7FFFFFFF);
  E := ResDirFind(Base, D, Name);
  If (E And LongInt($80000000)) = 0 Then Exit;
  D := Base + (E And $7FFFFFFF);
  { premiere langue }
  If MemW[0:D + 12] + MemW[0:D + 14] = 0 Then Exit;
  E := MemL[0:D + 16 + 4];
  If (E And LongInt($80000000)) <> 0 Then
  Begin
    D := Base + (E And $7FFFFFFF);
    E := MemL[0:D + 16 + 4];
  End;
  ResFind := Base + E;
End;

Function ResData(Module, Entry : LongInt; Var Size : LongInt) : LongInt;
Begin
  Size := MemL[0:Entry + 4];
  ResData := Module + MemL[0:Entry];
End;

Function FindResourceA(Module, Name, Typ : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := ResFind(AppModule(Module), Name, Typ);
  If R = 0 Then SetErr(ErrResNotFound);
  FindResourceA := R;
End;

Function FindResourceExA(Module, Typ, Name, Lang : LongInt) : LongInt;
Begin
  FindResourceExA := FindResourceA(Module, Name, Typ);
End;

Function LoadResource(Module, Res : LongInt) : LongInt;
Var Size : LongInt;
Begin
  If Res = 0 Then LoadResource := 0
  Else LoadResource := ResData(AppModule(Module), Res, Size);
End;

Function LockResource(H : LongInt) : LongInt;
Begin
  LockResource := H;
End;

Function SizeofResource(Module, Res : LongInt) : LongInt;
Begin
  If Res = 0 Then SizeofResource := 0 Else SizeofResource := MemL[0:Res + 4];
End;

Function FreeResource(H : LongInt) : LongInt;
Begin
  FreeResource := 0;
End;

{ ------------------------------------------------------------------ }
{ Exceptions (SEH : chaine FS:[0])                                   }
{ ------------------------------------------------------------------ }

Var
  ExcRec : Array[0..19] Of LongInt;
  ExcCtx : Array[0..203] Of LongInt;

Procedure RaiseException(Code, Flags, N, Args : LongInt);
Var Frame, Handler, R, Disp, I, PD, PC, PR : LongInt;
Begin
  PD := LongInt(@Disp); PC := LongInt(@ExcCtx); PR := LongInt(@ExcRec);
  KLog('RaiseException ' + HexStr(Code, 8));
  FillMem(LongInt(@ExcRec), 80, 0);
  ExcRec[0] := Code; ExcRec[1] := Flags;
  ExcRec[4] := Min(N, 15);
  For I := 0 To ExcRec[4] - 1 Do ExcRec[5 + I] := MemL[0:Args + I * 4];
  Frame := MemL[0:Threads[CurT].Tib];
  While (Frame <> -1) And (Frame <> 0) Do
  Begin
    Handler := MemL[0:Frame + 4];
    Disp := 0;
    R := 1;
    asm
      mov eax,PD
      push eax
      mov eax,PC
      push eax
      mov eax,Frame
      push eax
      mov eax,PR
      push eax
      mov eax,Handler
      call eax
      add esp,16
      mov R,eax
    end;
    If R = 0 Then Exit;
    Frame := MemL[0:Frame];
  End;
  MsgBoxModal(L('Erreur', 'Error', 'Fehler', 'Errore', 'Error'),
              L('Exception non trait'#130'e ', 'Unhandled exception ',
                'Unbehandelte Ausnahme ', 'Eccezione non gestita ',
                'Excepci'#162'n no controlada ') + HexStr(Code, 8), $10);
  ExitProcessK(-1);
End;

{ Deroulement : appeler les gestionnaires jusqu'a TargetFrame }
Procedure RtlUnwind(Frame, Ip, Rec, Ret : LongInt);
Var F, Handler, Disp, R, PD, PC : LongInt;
Begin
  PD := LongInt(@Disp); PC := LongInt(@ExcCtx);
  If Rec = 0 Then
  Begin
    FillMem(LongInt(@ExcRec), 80, 0);
    ExcRec[0] := LongInt($C0000027);
    Rec := LongInt(@ExcRec);
  End;
  MemL[0:Rec + 4] := MemL[0:Rec + 4] Or 2;
  F := MemL[0:Threads[CurT].Tib];
  While (F <> -1) And (F <> 0) And (F <> Frame) Do
  Begin
    Handler := MemL[0:F + 4];
    Disp := 0;
    asm
      mov eax,PD
      push eax
      mov eax,PC
      push eax
      mov eax,F
      push eax
      mov eax,Rec
      push eax
      mov eax,Handler
      call eax
      add esp,16
      mov R,eax
    end;
    F := MemL[0:F];
    MemL[0:Threads[CurT].Tib] := F;
  End;
End;

{ ------------------------------------------------------------------ }
{ Lancement et fin d'un programme                                    }
{ ------------------------------------------------------------------ }

{ Liberer tout ce qui appartient au programme }
Procedure KillApp;
Var I : LongInt;
Begin
  KillingApp := True;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And (Wnds[I].Thread > 0) And
       Threads[Wnds[I].Thread].IsApp Then
    Begin
      Wnds[I].Proc := 0;
      Wnds[I].IKind := ikStatic;
      DestroyW(I);
    End;
  For I := 1 To MaxThread - 1 Do
    If Threads[I].Used And Threads[I].IsApp And (I <> CurT) Then
      Threads[I].State := tsDead;
  For I := 0 To MaxTimer - 1 Do WTimers[I].Used := False;
  For I := 0 To MaxMMTimer - 1 Do MMTimers[I].Used := False;
  For I := 0 To MaxKObj - 1 Do
    If KObjs[I].Used And (KObjs[I].Kind In [koFile, koFind]) Then
      KObjs[I].Used := False;
  For I := 0 To MaxDC - 1 Do
    If Dcs[I].Used And (Gdis[Dcs[I].Gdi].Owner = 1) Then DcFree(I);
  For I := 0 To MaxGdi - 1 Do
    If Gdis[I].Used And (Gdis[I].Owner = 1) Then Gdis[I].Used := False;
  For I := 0 To MaxVBlk - 1 Do VBlks[I].Used := False;
  For I := 0 To MaxMod - 1 Do Mods[I].Used := False;
  For I := 0 To MaxClass - 1 Do
    If Classes[I].Used And (Classes[I].IKind = ikNone) Then
      Classes[I].Used := False;
  KFreeOwner(1);
  StubArea := 0;
  HeapOwner := 0;
  AppRunning := False;
  AppBase := 0;
  If AppProcObj >= 0 Then KObjs[AppProcObj].F2 := 1;
  CaptureWin := -1;
  CurHide := 0;
  CursorErase;
  CursorSetShape(0);
  DefaultPalette;
  MarkAll;
  KillingApp := False;
  KLog('Programme termine');
End;

Procedure ExitProcessK(Code : LongInt);
Var X : LongInt;
Begin
  KLog('ExitProcess(' + IntStr(Code) + ')');
  If (CurT = 0) Or Not Threads[CurT].IsApp Then Exit;
  KillApp;
  Threads[CurT].State := tsDead;
  X := 0;
  KSchedule;
  HaltCpu;
End;

{ Lancer un programme Windows (.EXE du CD-ROM ou du disque virtuel) }
Function RunExe(Path, Args : String) : Boolean;
Var M, T, Sub : LongInt; S : String;
Begin
  RunExe := False;
  If AppRunning Then
  Begin
    MsgBoxOpen('Pasdows', L('Un programme Windows est d'#130'j'#133' en ' +
               'cours d''ex'#130'cution.',
               'A Windows program is already running.',
               'Ein Windows-Programm wird bereits ausgef'#129'hrt.',
               'Un programma Windows '#138' gi'#133' in esecuzione.',
               'Ya se est'#160' ejecutando un programa de Windows.'), $30);
    RunExe := True;
    Exit;
  End;
  S := FindModuleFile(Path);
  If S = '' Then Exit;
  RunExe := True;
  CursorSetShape(1);
  CursorErase; CursorDraw;
  HeapOwner := 1;
  AppRunning := True;
  M := LoadPE(S, False);
  If M < 0 Then
  Begin
    HeapOwner := 0;
    AppRunning := False;
    CursorSetShape(0);
    MsgBoxOpen(BaseName(S), L(
      'Ce fichier n''est pas un programme Windows 32 bits valide.',
      'This file is not a valid 32-bit Windows program.',
      'Diese Datei ist kein g'#129'ltiges 32-Bit-Windows-Programm.',
      'Il file non '#138' un programma Windows a 32 bit valido.',
      'Este archivo no es un programa de Windows de 32 bits v'#160'lido.'),
      $10);
    Exit;
  End;
  AppBase := Mods[M].Base;
  AppSize := Mods[M].Size;
  AppEntry := Mods[M].Entry;
  AppPath := S;
  AppExcFilter := 0;
  AppErrMode := 0;
  Sub := MemW[0:AppBase + MemL[0:AppBase + $3C] + 24 + 68];
  If Args <> '' Then S := S + ' ' + Args;
  AppCmd := KAlloc(256);
  PutPStr(AppCmd, S, 256);
  CurDirS := ParentDir(AppPath);
  If Length(CurDirS) = 3 Then CurDirS := Copy(CurDirS, 1, 2);
  AppProcObj := KObjNew(koProcess);
  KLog('Lancement de ' + AppPath + ' (sous-systeme ' + IntStr(Sub) + ')');
  T := ThreadNew(AppEntry, 0, $100000, True);
  If T < 0 Then
  Begin
    KillApp;
    Exit;
  End;
  AppMainT := T;
  HeapOwner := 0;
  CursorSetShape(0);
End;

{ Fonctions Win32 exportees par VMM32.VXD (thunks stdcall) }

exports VideoForWindowsVersion,
  GetEnvironmentVariableA, SetEnvironmentVariableA,
  GetEnvironmentStrings, GetEnvironmentStringsA, FreeEnvironmentStringsA,
  GetVersion, GetVersionExA, GetSystemInfo, GetCommandLineA, GetStartupInfoA,
  GetStdHandle, SetStdHandle, GetLastError, SetLastError, SetErrorMode,
  OutputDebugStringA, SetUnhandledExceptionFilter, UnhandledExceptionFilter,
  GetCurrentProcess, GetCurrentProcessId, GetCurrentThread,
  GetCurrentThreadId, ExitProcess, TerminateProcess, RaiseException,
  RtlUnwind, WinExec, GetTickCount, Sleep, FileTimeToSystemTime,
  FileTimeToLocalFileTime, LocalFileTimeToFileTime, FileTimeToDosDateTime,
  DosDateTimeToFileTime, GetLocalTime, GetSystemTime, GetTimeZoneInformation,
  CreateFileA, CloseHandle, ReadFile, WriteFile, SetFilePointer, GetFileSize,
  SetEndOfFile, FlushFileBuffers, GetFileType, GetFileTime,
  GetFileAttributesA, SetFileAttributesA, DeleteFileA, MoveFileA,
  GetFullPathNameA, GetCurrentDirectoryA, SetCurrentDirectoryA,
  GetDiskFreeSpaceA, GetDriveTypeA, GetLogicalDrives, GetWindowsDirectoryA,
  GetSystemDirectoryA, GetTempPathA, GetVolumeInformationA, FindFirstFileA,
  FindNextFileA, FindClose, _lopen, _lcreat, _lclose, _lread, _hread, _lwrite,
  _hwrite, _llseek, OpenFile, GetProcessHeap, HeapCreate, HeapDestroy,
  HeapAlloc, HeapFree, HeapReAlloc, HeapSize, GlobalAlloc, GlobalLock,
  GlobalUnlock, GlobalFree, GlobalReAlloc, GlobalSize, GlobalHandle,
  GlobalCompact, GlobalFlags, LocalAlloc, LocalFree, LocalLock, LocalUnlock,
  LocalReAlloc, LocalSize, GlobalMemoryStatus, VirtualAlloc, VirtualFree,
  VirtualQuery, IsBadReadPtr, IsBadWritePtr, IsBadCodePtr, IsBadStringPtrA,
  lstrlenA, lstrlenW, lstrcpyA, lstrcpynA, lstrcatA, lstrcmpA, lstrcmpiA,
  MultiByteToWideChar, WideCharToMultiByte, IsDBCSLeadByte, GetACP, GetOEMCP,
  GetCPInfo, MulDiv, GlobalAddAtomA, GlobalFindAtomA, GlobalDeleteAtom,
  GlobalGetAtomNameA, AddAtomA, DeleteAtom, FindAtomA,
  GetPrivateProfileStringA, GetPrivateProfileIntA, GetProfileStringA,
  GetProfileIntA, WriteProfileStringA, WritePrivateProfileStringA,
  CreateThread, ExitThread, SetThreadPriority, GetThreadPriority,
  ResumeThread, GetExitCodeThread, CreateSemaphoreA, ReleaseSemaphore,
  CreateEventA, SetEvent, ResetEvent, PulseEvent, CreateMutexA, ReleaseMutex,
  WaitForSingleObject, InitializeCriticalSection, DeleteCriticalSection,
  EnterCriticalSection, LeaveCriticalSection, InterlockedIncrement,
  InterlockedDecrement, InterlockedExchange, TlsAlloc, TlsFree, TlsGetValue,
  TlsSetValue, CreatePen, CreatePenIndirect, CreateSolidBrush,
  CreateHatchBrush, CreateBrushIndirect, CreatePatternBrush,
  CreateDIBPatternBrush, CreateFontA, CreateFontIndirectA, AddFontResourceA,
  RemoveFontResourceA, GetStockObject, DeleteObject, UnrealizeObject,
  GetObjectA, CreatePalette, GetPaletteEntries, SetPaletteEntries,
  SelectPalette, RealizePalette, AnimatePalette, GetSystemPaletteEntries,
  SetSystemPaletteUse, GetSystemPaletteUse, GetNearestColor,
  GetNearestPaletteIndex, CreateCompatibleDC, CreateDCA, CreateICA, DeleteDC,
  SelectObject, SetBkColor, GetBkColor, SetTextColor, GetTextColor, SetBkMode,
  GetBkMode, SetROP2, GetROP2, SetTextAlign, GetTextAlign, SetStretchBltMode,
  GetStretchBltMode, SetPolyFillMode, SetTextJustification, SetBrushOrgEx,
  SetViewportOrgEx, SetWindowOrgEx, DPtoLP, LPtoDP, GetDCOrgEx,
  GetCurrentPositionEx, SaveDC, RestoreDC, CreateRectRgn,
  CreateRectRgnIndirect, CreateEllipticRgnIndirect, CreateEllipticRgn,
  CreateRoundRectRgn, CreatePolygonRgn, SetRectRgn, CombineRgn, OffsetRgn,
  GetRgnBox, EqualRgn, PtInRegion, SelectClipRgn, IntersectClipRect,
  GetClipBox, GetClipRgn, PatBlt, MoveToEx, LineTo, Polyline, Polygon,
  PolyPolygon, Rectangle, RoundRect, Ellipse, FillRgn, PaintRgn, FrameRgn,
  InvertRgn, SetPixel, GetPixel, TextOutA, ExtTextOutA, GetTextExtentPointA,
  GetTextExtentPoint32A, GetTextMetricsA, GetTextFaceA, EnumFontsA,
  StretchBlt, BitBlt, StretchDIBits, SetDIBitsToDevice, CreateDIBitmap,
  CreateDIBSection, SetDIBColorTable, GetDIBColorTable,
  CreateCompatibleBitmap, CreateDiscardableBitmap, CreateBitmap,
  CreateBitmapIndirect, GetBitmapBits, SetBitmapBits, GetDIBits, SetDIBits,
  GetDeviceCaps, GdiSetBatchLimit, GdiFlush, Escape, StartDocA, EndDoc,
  AbortDoc, StartPage, EndPage, SetAbortProc, RegisterClassA,
  UnregisterClassA, GetClassInfoA, GetClassNameA, SetClassLongA,
  GetClassLongA, CreateWindowExA, CreateWindowA, DestroyWindow, ShowWindow,
  IsWindow, IsWindowVisible, IsWindowEnabled, EnableWindow, IsIconic,
  IsZoomed, IsChild, GetParent, SetParent, GetDesktopWindow, GetWindow,
  GetTopWindow, GetActiveWindow, SetActiveWindow, GetForegroundWindow,
  SetForegroundWindow, BringWindowToTop, GetFocus, SetFocus, GetCapture,
  SetCapture, ReleaseCapture, MoveWindow, SetWindowPos, GetWindowRect,
  GetClientRect, AdjustWindowRectEx, AdjustWindowRect, ClientToScreen,
  ScreenToClient, MapWindowPoints, WindowFromPoint, ChildWindowFromPoint,
  SetWindowTextA, GetWindowTextA, GetWindowTextLengthA, GetWindowLongA,
  SetWindowLongA, GetWindowWord, SetWindowWord, SetPropA, GetPropA,
  RemovePropA, SendMessageA, PostMessageA, PostThreadMessageA,
  PostQuitMessage, GetMessageA, PeekMessageA, WaitMessage, GetMessageTime,
  GetMessagePos, TranslateMessage, DispatchMessageA, SetTimer, KillTimer,
  GetDC, GetWindowDC, GetDCEx, ReleaseDC, BeginPaint, EndPaint,
  InvalidateRect, InvalidateRgn, ValidateRect, ValidateRgn, GetUpdateRgn,
  GetUpdateRect, UpdateWindow, RedrawWindow, ScrollDC, ScrollWindow, SetRect,
  SetRectEmpty, CopyRect, OffsetRect, InflateRect, IntersectRect, UnionRect,
  EqualRect, IsRectEmpty, PtInRect, GetSysColor, SetSysColors,
  GetSysColorBrush, FillRect, FrameRect, InvertRect, DrawEdge,
  DrawFrameControl, DrawCaption, DrawIcon, DrawFocusRect, DrawTextA,
  GrayStringA, GetKeyState, GetAsyncKeyState, GetKeyboardState,
  SetKeyboardState, ToAscii, MapVirtualKeyA, GetCursorPos, SetCursorPos,
  GetDoubleClickTime, GetCaretBlinkTime, MessageBeep, GetSystemMetrics,
  SystemParametersInfoA, ExitWindowsEx, WinHelpA, FlashWindow,
  SetMessageQueue, CallNextHookEx, SetWindowsHookExA, UnhookWindowsHookEx,
  SetScrollPos, GetScrollPos, SetScrollRange, ShowScrollBar, OpenClipboard,
  CloseClipboard, EmptyClipboard, GetClipboardData, SetClipboardData,
  EnumClipboardFormats, IsClipboardFormatAvailable, RegisterClipboardFormatA,
  SetClipboardViewer, ChangeClipboardChain, RegisterWindowMessageA,
  CharUpperA, CharLowerA, CharUpperBuffA, CharNextA, CharPrevA,
  CharToOemBuffA, CharToOemA, OemToCharA, IsCharAlphaA, wsprintfA, wvsprintfA,
  LoadStringA, CreateCursor, DestroyCursor, LoadCursorA, SetCursor, GetCursor,
  ShowCursor, ClipCursor, LoadIconA, DestroyIcon, LoadBitmapA,
  LoadAcceleratorsA, CreateAcceleratorTableA, CopyAcceleratorTableA,
  DestroyAcceleratorTable, TranslateAcceleratorA, TranslateMDISysAccel,
  CreateMenu, CreatePopupMenu, AppendMenuA, InsertMenuA, ModifyMenuA,
  DeleteMenu, RemoveMenu, DestroyMenu, GetMenuItemCount, GetMenuItemID,
  GetSubMenu, GetMenuState, GetMenuStringA, CheckMenuItem, EnableMenuItem,
  HiliteMenuItem, GetMenuCheckMarkDimensions, GetMenu, SetMenu, DrawMenuBar,
  GetSystemMenu, TrackPopupMenu, LoadMenuA, DefWindowProcA, DefFrameProcA,
  DefMDIChildProcA, CallWindowProcA, CreateDialogIndirectParamA,
  CreateDialogParamA, DialogBoxParamA, DialogBoxIndirectParamA, EndDialog,
  DefDlgProcA, GetDlgItem, GetDlgCtrlID, SetDlgItemTextA, GetDlgItemTextA,
  SetDlgItemInt, GetDlgItemInt, SendDlgItemMessageA, IsDlgButtonChecked,
  CheckDlgButton, CheckRadioButton, IsDialogMessageA, GetNextDlgTabItem,
  MapDialogRect, GetDialogBaseUnits, MessageBoxA, MessageBoxExA, timeGetTime,
  timeGetDevCaps, timeBeginPeriod, timeEndPeriod, timeSetEvent, timeKillEvent,
  waveOutGetNumDevs, waveOutGetDevCapsA, waveOutOpen, waveOutClose,
  waveOutPrepareHeader, waveOutUnprepareHeader, waveOutWrite, waveOutReset,
  waveOutPause, waveOutRestart, waveOutGetVolume, waveOutSetVolume,
  midiOutGetNumDevs, auxGetNumDevs, sndPlaySoundA, PlaySoundA, DefDriverProc,
  mciSendCommandA, mciSendStringA, mciGetErrorStringA, GetOpenFileNameA,
  GetSaveFileNameA, PrintDlgA, ChooseColorA, CommDlgExtendedError,
  FindExecutableA, ShellExecuteA, CoInitialize, CoUninitialize,
  CoCreateInstance, OleInitialize, OleUninitialize, ICClose,
  ICGetDisplayFormat, ICOpen, ICLocate, RegOpenKeyExA, RegOpenKeyA,
  RegCreateKeyA, RegCloseKey, RegQueryValueExA, RegSetValueExA,
  GetModuleHandleA, GetModuleFileNameA, LoadLibraryA, LoadLibraryExA,
  FreeLibrary, GetProcAddress, FindResourceA, FindResourceExA, LoadResource,
  LockResource, SizeofResource, FreeResource;

{ ==================================================================== }
{ Partie 13 - Demarrage                                                }
{ ==================================================================== }

Procedure InitClasses;
Var I : LongInt;
Begin
  For I := 0 To 31 Do KClass[I] := -1;
  KClass[ikTaskbar] := ClassAdd('#Taskbar', 0, ikTaskbar, 0);
  KClass[ikMenu] := ClassAdd('#32768', 0, ikMenu, 0);
  KClass[ikExplorer] := ClassAdd('#Explorer', 0, ikExplorer, CS_DBLCLKS);
  KClass[ikMsgBox] := ClassAdd('#MsgBox', 0, ikMsgBox, 0);
  KClass[ikAbout] := ClassAdd('#About', 0, ikAbout, 0);
  KClass[ikRun] := ClassAdd('#Run', 0, ikRun, 0);
  KClass[ikShutdown] := ClassAdd('#Shutdown', 0, ikShutdown, 0);
  KClass[ikHelp] := ClassAdd('#Help', 0, ikHelp, 0);
  KClass[ikNotepad] := ClassAdd('#Notepad', 0, ikNotepad, 0);
  KClass[ikButton] := ClassAdd('BUTTON', 0, ikButton, CS_DBLCLKS);
  KClass[ikStatic] := ClassAdd('STATIC', 0, ikStatic, 0);
  KClass[ikEdit] := ClassAdd('EDIT', 0, ikEdit, CS_DBLCLKS);
  KClass[ikListBox] := ClassAdd('LISTBOX', 0, ikListBox, CS_DBLCLKS);
  KClass[ikScrollBar] := ClassAdd('SCROLLBAR', 0, ikScrollBar, 0);
  KClass[ikComboBox] := ClassAdd('COMBOBOX', 0, ikComboBox, CS_DBLCLKS);
  KClass[ikDialog] := ClassAdd('#32770', 0, ikDialog, 0);
  KClass[ikMdiClient] := ClassAdd('MDICLIENT', 0, ikMdiClient, 0);
End;


{ Boucle de la tache 0 : peripheriques, fenetres internes, ecran }
Procedure SystemLoop;
Var I : LongInt; Busy : Boolean;
Begin
  Repeat
    ProcessInput;
    RunMMTimers;
    RunWave;
    KPaintAll;
    For I := 0 To MaxWnd - 1 Do
      If Wnds[I].Used And IsChildW(I) And (Wnds[I].IKind <> ikNone) And
         HasUpdate(I) Then DrawCtl(I);
    FlushScreen;
    ReapThreads;
    Busy := False;
    For I := 1 To MaxThread - 1 Do
      If ThreadRunnable(I) Then Busy := True;
    If Busy Then KYield
    Else If (KbHead = KbTail) And (MouHead = MouTail) Then Idle;
  Until False;
End;


BEGIN
  SerialInit;
  LogOn := True;
  KLog('VMM32.VXD : Pasdows 95 ' + KVersion);
  InitGdt;
  InitPic;
  InitIdt;
  InitTimer;
  asm
    sti
  end;
  MemTop := $100000 + MemL[0:BootInfo + $18] * 1024;
  If MemTop > $40000000 Then MemTop := $40000000;
  HeapInit(HeapBase, MemTop);
  Language := TLanguage(Mem[0:BootInfo + 3] Mod 5);
  OptFlags := MemL[0:BootInfo + $30];
  Lfb := MemL[0:BootInfo + $0C];
  LfbPitch := MemW[0:BootInfo + $10];
  ThreadInit0;
  KImgLo := $100000;
  KImgHi := KImgLo + MemL[0:KImgLo + MemL[0:KImgLo + $3C] + 80];
  asm
    finit
  end;
  InitKeyTables;
  DefaultPalette;
  SurfNew(Back, ScrW, ScrH);
  CursorSetShape(0);
  CurX := ScrW Div 2; CurY := ScrH Div 2;
  AtaInit;
  CdInit;
  CurDirS := 'D:';
  { ApiTrace := True journalise chaque appel d'API d'un programme Win32
    (nom, appelant, arguments, resultat) sur le port serie COM1 }
  ApiTrace := False;
  LoadEnvironment;
  InitInput;
  ActiveWin := -1; FocusWin := -1; CaptureWin := -1;
  DragWin := -1; PressWin := -1; LastClickW := -1;
  MenuDepth := 0; DeskSel := -1; TaskbarW := -1;
  DeskColor := cTeal;
  InitClasses;
  InitGdi;
  InitExports;
  If ApiTrace Then TraceInit;
  AppProcObj := -1;
  DeskBuild;
  TaskbarW := KCreate(ikTaskbar, '', 0, 0, TaskY, ScrW, TaskH, WS_POPUP,
                      WS_EX_TOPMOST Or WS_EX_TOOLWINDOW);
  ShowW(TaskbarW, True, False);
  LastMinute := -1;
  PreemptOn := True;
  MarkAll;
  FlushScreen;
  CursorDraw;
  KLog('Memoire libre : ' + IntStr(HeapFreeBytes Div 1024) + ' Ko');
  SystemLoop;
END.
