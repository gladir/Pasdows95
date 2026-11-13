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
                                { (debut reel : ExeTop, voir plus bas) }

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
  MaxGdi      = 1024;
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
  ExeTop     : LongInt;   { fin de la zone des images de programmes }
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
  { espaces, tabulations et autres caracteres de controle }
  While (Length(S) > 0) And (S[1] <= ' ') Do Delete(S, 1, 1);
  While (Length(S) > 0) And (S[Length(S)] <= ' ') Do
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
  Gdt      : Array[0..17] Of LongInt;
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
  { DirectInput : etat des touches par code de balayage (E0 : +80h),
    deplacements et boutons de la souris depuis la derniere lecture }
  ScanDown : Array[0..255] Of Byte;
  ScanE0 : Boolean;
  ScanHit : Array[0..255] Of Byte;
  DIMX, DIMY, DIMBtn : LongInt;
  { DirectDraw : surface primaire affichee en plein ecran (exclusif) }
  DDShow, DDDirty : Boolean;
  DDBuf, DDW, DDH : LongInt;

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
Var I : LongInt;
Begin
  Gdt[0] := 0;          Gdt[1] := 0;
  Gdt[2] := $0000FFFF;  Gdt[3] := $00CF9A00;
  Gdt[4] := $0000FFFF;  Gdt[5] := $00CF9200;
  Gdt[6] := $0000FFFF;  Gdt[7] := $00CF9200;
  Gdt[8] := 0;          Gdt[9] := 0;
  For I := 10 To 17 Do Gdt[I] := 0;
  GdtPtr.Limit := 9 * 8 - 1;
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
  { etat DirectInput des touches, a l'instant de l'interruption }
  If B = $E0 Then ScanE0 := True
  Else
  Begin
    N := (B And $7F) + Ord(ScanE0) * $80;
    ScanDown[N] := Ord((B And $80) = 0) * $80;
    { appui memorise jusqu'a la prochaine lecture de l'etat }
    If (B And $80) = 0 Then ScanHit[N] := $80;
    ScanE0 := False;
  End;
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
  Port[$21] := $50; Port[$A1] := $58;
  Port[$21] := $04; Port[$A1] := $02;
  Port[$21] := $01; Port[$A1] := $01;
  { IRQ 0 et 2 seulement : l'IRQ 1 est demasquee a la fin d'InitInput -
    demasquee ici, la reponse du 8042 a sa commande 20h declenchait le
    gestionnaire du clavier, qui la lisait a la place de KbcRead (attente
    de 200000 lectures, plus d'une seconde au demarrage). }
  Port[$21] := $FA; Port[$A1] := $FF;
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
  { IRQ en 50h-5Fh (comme Windows 95) : 20h-2Fh restent aux appels
    logiciels des programmes 16 bits (INT 21h, INT 2Fh, INT 31h) }
  For I := $50 To $57 Do SetGate(I, LongInt(@IrqMaster));
  For I := $58 To $5F Do SetGate(I, LongInt(@IrqSlave));
  SetGate($50, LongInt(@IrqTimer));
  SetGate($51, LongInt(@IrqKeyboard));
  SetGate($5C, LongInt(@IrqMouse));
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
  memoire (C:\WINDOWS, C:\TEMP...) ou les programmes peuvent ecrire,
  sauf si un disque dur porte un volume FAT (partie 3b). }

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
  KObjOwner : Array[0..MaxKObj - 1] Of LongInt;
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
      KObjOwner[I] := HeapOwner;
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

Function FatVolOf(Const Path : String) : LongInt; Forward;
Function FatPathInfo(Const Path : String; Var Attr, Size, Time : LongInt)
  : Boolean; Forward;
Function FatLoad(Const Path : String; Var Size : LongInt) : LongInt;
  Forward;

{ Repertoires fixes du disque C: }
Function IsCDir(Path : String) : Boolean;
Var I, Attr, Size, Time : LongInt;
Begin
  If FatVolOf(Path) >= 0 Then
  Begin
    IsCDir := FatPathInfo(Path, Attr, Size, Time) And
              ((Attr And $10) <> 0);
    Exit;
  End;
  IsCDir := (Path = 'C:\') Or (Path = 'C:\WINDOWS') Or
            (Path = 'C:\WINDOWS\SYSTEM') Or (Path = 'C:\TEMP') Or
            (Path = 'C:\WINDOWS\TEMP');
  { repertoires crees (entrees d'attribut 10h du disque en memoire) }
  For I := 0 To MaxRam - 1 Do
    If RamFiles[I].Used And (RamFiles[I].Attr = $10) And
       (RamFiles[I].Path = Path) Then IsCDir := True;
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
  Lba := -1; Size := 0; Time := 0; Attr := 0; Ram := -1;
  { volume FAT d'un disque dur }
  If FatVolOf(Path) >= 0 Then
  Begin
    PathInfo := FatPathInfo(Path, Attr, Size, Time);
    Exit;
  End;
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
  If FatVolOf(Path) >= 0 Then
  Begin
    LoadWholeFile := FatLoad(Path, Size);
    Exit;
  End;
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
{ Partie 3b - Disques durs ATA et systemes de fichiers FAT12, FAT16 et  }
{             FAT32 (noms longs VFAT), en lecture et en ecriture       }
{ ==================================================================== }

{ Comme Windows 95 OSR2, VMM32 lit et ecrit les volumes FAT32 (et FAT12
  / FAT16) des disques durs IDE : table de partitions (primaires et
  logiques) ou disque sans partition. Le premier volume FAT devient C:
  (il remplace alors le disque virtuel en memoire), les suivants E:,
  F:... (D: reste le CD-ROM). Disques ATA en PIO, LBA 28 bits (128 Go).
  Les secteurs passent par un petit cache a ecriture immediate. }

Const
  MaxDisk = 4;
  MaxVol = 4;
  MaxFo = 32;
  SecSlots = 64;
  FatEoc = $0FFFFFFF;

Var
  DiskN     : LongInt;
  DiskBase, DiskCtrl, DiskSecs : Array[0..MaxDisk - 1] Of LongInt;
  DiskSlave : Array[0..MaxDisk - 1] Of Boolean;
  VolN      : LongInt;
  VolDisk, VolStart, VolSecs, VolType, VolSpc, VolRsvd, VolNFats,
  VolFatSz, VolRootClus, VolRootSec, VolRootCnt, VolData, VolClus,
  VolFree, VolNext, VolFsInfo, VolSerial, VolLetter, VolActFat
    : Array[0..MaxVol - 1] Of LongInt;
  VolFsDirty : Array[0..MaxVol - 1] Of Boolean;
  VolLab    : Array[0..MaxVol - 1] Of String[11];
  SecLba, SecDisk, SecBuf, SecAge : Array[0..SecSlots - 1] Of LongInt;
  SecTick   : LongInt;
  FatIoErr  : Boolean;
  FatScratch, FatZero : LongInt;
  { derniere entree trouvee (FatResolve, DirNext, DirCreate) }
  FfName, FfShort : String;
  FfAttr, FfClus, FfSize, FfTime, FfDirClus, FfIdx, FfNEnt : LongInt;
  { fichiers ouverts }
  FoUsed    : Array[0..MaxFo - 1] Of Boolean;
  FoVol, FoClus, FoSize, FoDir, FoIdx, FoCIdx, FoCClus, FoTime
    : Array[0..MaxFo - 1] Of LongInt;
  FoDirty   : Array[0..MaxFo - 1] Of Boolean;
  { parcours de repertoire (cache du dernier cluster) }
  DcVol, DcDir, DcK, DcClus : LongInt;
  LfnBuf    : Array[0..259] Of LongInt;

{ ------------------------------------------------------------------ }
{ Disques ATA (PIO, LBA 28 bits)                                       }
{ ------------------------------------------------------------------ }

Function HdWait(B : LongInt) : LongInt;
Var N, St : LongInt;
Begin
  N := 0;
  Repeat
    St := Port[B + 7];
    If (St And $80) = 0 Then
    Begin
      HdWait := St;
      Exit;
    End;
    Inc(N);
  Until N > 3000000;
  HdWait := -1;
End;

{ Attendre DRQ (donnees pretes) ; False si erreur }
Function HdDrq(B : LongInt) : Boolean;
Var N, St : LongInt;
Begin
  HdDrq := False;
  N := 0;
  Repeat
    St := Port[B + 7];
    If (St And $80) = 0 Then
    Begin
      If (St And $21) <> 0 Then Exit;
      If (St And 8) <> 0 Then
      Begin
        HdDrq := True;
        Exit;
      End;
    End;
    Inc(N);
  Until N > 3000000;
End;

Procedure HdSetup(D, Lba, Cnt, Cmd : LongInt);
Var B, I, X : LongInt;
Begin
  B := DiskBase[D];
  HdWait(B);
  Port[B + 6] := $E0 Or (Ord(DiskSlave[D]) Shl 4) Or ((Lba Shr 24) And $0F);
  For I := 1 To 4 Do X := Port[DiskCtrl[D]];
  HdWait(B);
  Port[B + 1] := 0;
  Port[B + 2] := Cnt And $FF;
  Port[B + 3] := Lba And $FF;
  Port[B + 4] := (Lba Shr 8) And $FF;
  Port[B + 5] := (Lba Shr 16) And $FF;
  Port[B + 7] := Cmd;
  For I := 1 To 4 Do X := Port[DiskCtrl[D]];
End;

{ Lire Cnt secteurs (1..128) a l'adresse Dst }
Function HdRead(D, Lba, Cnt, Dst : LongInt) : Boolean;
Var B, K, A : LongInt;
Begin
  HdRead := False;
  If (Lba < 0) Or (Lba + Cnt > DiskSecs[D]) Then Exit;
  B := DiskBase[D];
  HdSetup(D, Lba, Cnt, $20);
  For K := 0 To Cnt - 1 Do
  Begin
    If Not HdDrq(B) Then Exit;
    A := Dst + K * 512;
    asm
      push edi
      mov edi,A
      mov ecx,256
      mov edx,B
      cld
      rep insw
      pop edi
    end;
  End;
  HdRead := True;
End;

Function HdWrite(D, Lba, Cnt, Src : LongInt) : Boolean;
Var B, K, A : LongInt;
Begin
  HdWrite := False;
  If (Lba < 0) Or (Lba + Cnt > DiskSecs[D]) Then Exit;
  B := DiskBase[D];
  HdSetup(D, Lba, Cnt, $30);
  For K := 0 To Cnt - 1 Do
  Begin
    If Not HdDrq(B) Then Exit;
    A := Src + K * 512;
    asm
      push esi
      mov esi,A
      mov ecx,256
      mov edx,B
      cld
      rep outsw
      pop esi
    end;
  End;
  If HdWait(B) < 0 Then Exit;
  HdWrite := (Port[B + 7] And $21) = 0;
End;

{ Vider le cache d'ecriture du disque }
Procedure HdFlush(D : LongInt);
Begin
  HdSetup(D, 0, 0, $E7);
  HdWait(DiskBase[D]);
End;

{ IDENTIFY DEVICE : disque ATA (pas ATAPI) present ? }
Function HdIdentify(Base, Ctrl : LongInt; Slave : Boolean) : Boolean;
Var St, I, A : LongInt;
Begin
  HdIdentify := False;
  If Port[Base + 7] = $FF Then Exit;
  If AtaFound And (AtaBase = Base) And (AtaSlave = Slave) Then Exit;
  Port[Ctrl] := 2;                       { pas d'interruptions }
  If Slave Then Port[Base + 6] := $B0 Else Port[Base + 6] := $A0;
  For I := 1 To 4 Do St := Port[Ctrl];
  Port[Base + 2] := 0; Port[Base + 3] := 0;
  Port[Base + 4] := 0; Port[Base + 5] := 0;
  Port[Base + 7] := $EC;
  For I := 1 To 4 Do St := Port[Ctrl];
  If Port[Base + 7] = 0 Then Exit;
  If HdWait(Base) < 0 Then Exit;
  If (Port[Base + 4] <> 0) Or (Port[Base + 5] <> 0) Then Exit;  { ATAPI }
  If Not HdDrq(Base) Then Exit;
  A := FatScratch;
  asm
    push edi
    mov edi,A
    mov ecx,256
    mov edx,Base
    cld
    rep insw
    pop edi
  end;
  If DiskN >= MaxDisk Then Exit;
  DiskBase[DiskN] := Base; DiskCtrl[DiskN] := Ctrl;
  DiskSlave[DiskN] := Slave;
  DiskSecs[DiskN] := MemL[0:A + 120];    { mots 60-61 : secteurs LBA28 }
  If DiskSecs[DiskN] <= 0 Then Exit;
  Inc(DiskN);
  HdIdentify := True;
End;

{ ------------------------------------------------------------------ }
{ Cache de secteurs (ecriture immediate)                               }
{ ------------------------------------------------------------------ }

Function SecFind(D, Lba : LongInt) : LongInt;
Var I, R : LongInt;
Begin
  R := -1;
  For I := 0 To SecSlots - 1 Do
    If (SecLba[I] = Lba) And (SecDisk[I] = D) Then R := I;
  SecFind := R;
End;

{ Adresse du secteur Lba (absolu) du disque D dans le cache }
Function SecGet(D, Lba : LongInt) : LongInt;
Var I, Best : LongInt;
Begin
  Inc(SecTick);
  I := SecFind(D, Lba);
  If I < 0 Then
  Begin
    Best := 0;
    For I := 1 To SecSlots - 1 Do
      If SecAge[I] < SecAge[Best] Then Best := I;
    I := Best;
    SecLba[I] := -1;
    If Not HdRead(D, Lba, 1, SecBuf[I]) Then
    Begin
      FatIoErr := True;
      FillMem(FatScratch, 512, 0);
      SecGet := FatScratch;
      Exit;
    End;
    SecLba[I] := Lba; SecDisk[I] := D;
  End;
  SecAge[I] := SecTick;
  SecGet := SecBuf[I];
End;

{ Ecrire sur le disque le secteur modifie dans le cache }
Procedure SecPut(D, Lba : LongInt);
Var I : LongInt;
Begin
  I := SecFind(D, Lba);
  If I < 0 Then Exit;
  If Not HdWrite(D, Lba, 1, SecBuf[I]) Then FatIoErr := True;
End;

Procedure SecInval(D, Lba, Cnt : LongInt);
Var I : LongInt;
Begin
  For I := 0 To SecSlots - 1 Do
    If (SecDisk[I] = D) And (SecLba[I] >= Lba) And (SecLba[I] < Lba + Cnt)
    Then SecLba[I] := -1;
End;

{ Secteur relatif au volume }
Function VSec(V, S : LongInt) : LongInt;
Begin
  VSec := SecGet(VolDisk[V], VolStart[V] + S);
End;

Procedure VPut(V, S : LongInt);
Begin
  SecPut(VolDisk[V], VolStart[V] + S);
End;

{ ------------------------------------------------------------------ }
{ Table d'allocation (FAT)                                             }
{ ------------------------------------------------------------------ }

Function FatByte(V, F, Off : LongInt) : LongInt;
Begin
  FatByte := Mem[0:VSec(V, VolRsvd[V] + F * VolFatSz[V] + Off Div 512) +
                 Off Mod 512];
End;

Procedure FatPutByte(V, F, Off, B : LongInt);
Var S : LongInt;
Begin
  S := VolRsvd[V] + F * VolFatSz[V] + Off Div 512;
  Mem[0:VSec(V, S) + Off Mod 512] := B;
  VPut(V, S);
End;

{ Entree C de la FAT (FatEoc pour une fin de chaine) }
Function FatGet(V, C : LongInt) : LongInt;
Var F, Off, R, A : LongInt;
Begin
  F := VolActFat[V];
  If F < 0 Then F := 0;
  Case VolType[V] Of
    32 :
    Begin
      Off := C * 4;
      A := VSec(V, VolRsvd[V] + F * VolFatSz[V] + Off Div 512);
      R := MemL[0:A + Off Mod 512] And $0FFFFFFF;
      If R >= $0FFFFFF8 Then R := FatEoc;
    End;
    16 :
    Begin
      Off := C * 2;
      A := VSec(V, VolRsvd[V] + F * VolFatSz[V] + Off Div 512);
      R := MemW[0:A + Off Mod 512];
      If R >= $FFF8 Then R := FatEoc
      Else If R = $FFF7 Then R := $0FFFFFF7;
    End;
  Else
    Off := C + C Div 2;
    R := FatByte(V, F, Off) Or (FatByte(V, F, Off + 1) Shl 8);
    If (C And 1) <> 0 Then R := R Shr 4 Else R := R And $FFF;
    If R >= $FF8 Then R := FatEoc
    Else If R = $FF7 Then R := $0FFFFFF7;
  End;
  FatGet := R;
End;

Procedure FatSet(V, C, Val : LongInt);
Var F, Off, A, S, Old : LongInt;
Begin
  For F := 0 To VolNFats[V] - 1 Do
  Begin
    If (VolActFat[V] >= 0) And (F <> VolActFat[V]) Then Continue;
    Case VolType[V] Of
      32 :
      Begin
        Off := C * 4;
        S := VolRsvd[V] + F * VolFatSz[V] + Off Div 512;
        A := VSec(V, S) + Off Mod 512;
        MemL[0:A] := (MemL[0:A] And LongInt($F0000000)) Or
                     (Val And $0FFFFFFF);
        VPut(V, S);
      End;
      16 :
      Begin
        Off := C * 2;
        S := VolRsvd[V] + F * VolFatSz[V] + Off Div 512;
        A := VSec(V, S) + Off Mod 512;
        MemW[0:A] := Val And $FFFF;
        VPut(V, S);
      End;
    Else
      Off := C + C Div 2;
      Val := Val And $FFF;
      If (C And 1) <> 0 Then
      Begin
        Old := FatByte(V, F, Off);
        FatPutByte(V, F, Off, (Old And $0F) Or ((Val And $0F) Shl 4));
        FatPutByte(V, F, Off + 1, (Val Shr 4) And $FF);
      End
      Else
      Begin
        FatPutByte(V, F, Off, Val And $FF);
        Old := FatByte(V, F, Off + 1);
        FatPutByte(V, F, Off + 1, (Old And $F0) Or ((Val Shr 8) And $0F));
      End;
    End;
  End;
End;

Function ClusOk(V, C : LongInt) : Boolean;
Begin
  ClusOk := (C >= 2) And (C < VolClus[V] + 2);
End;

Function ClusSec(V, C : LongInt) : LongInt;
Begin
  ClusSec := VolData[V] + (C - 2) * VolSpc[V];
End;

Function ClusBytes(V : LongInt) : LongInt;
Begin
  ClusBytes := VolSpc[V] * 512;
End;

{ Compter les clusters libres (si FSInfo ne le dit pas) }
Procedure FatCountFree(V : LongInt);
Var C, N : LongInt;
Begin
  N := 0;
  For C := 2 To VolClus[V] + 1 Do
    If FatGet(V, C) = 0 Then Inc(N);
  VolFree[V] := N;
End;

{ Ecrire des zeros dans Cnt secteurs relatifs au volume }
Procedure VZero(V, S, Cnt : LongInt);
Var K : LongInt;
Begin
  While Cnt > 0 Do
  Begin
    K := Min(Cnt, 64);
    If Not HdWrite(VolDisk[V], VolStart[V] + S, K, FatZero) Then
      FatIoErr := True;
    SecInval(VolDisk[V], VolStart[V] + S, K);
    S := S + K; Cnt := Cnt - K;
  End;
End;

{ Nouveau cluster (fin de chaine), chaine apres Prev ; 0 si plein }
Function FatAlloc(V, Prev : LongInt; Zero : Boolean) : LongInt;
Var C, K, N, R : LongInt;
Begin
  R := 0;
  N := VolClus[V];
  C := VolNext[V];
  If Not ClusOk(V, C) Then C := 2;
  For K := 0 To N - 1 Do
  Begin
    If FatGet(V, C) = 0 Then
    Begin
      R := C;
      Break;
    End;
    Inc(C);
    If C >= N + 2 Then C := 2;
  End;
  FatAlloc := R;
  If R = 0 Then Exit;
  FatSet(V, R, FatEoc);
  If Prev <> 0 Then FatSet(V, Prev, R);
  VolNext[V] := R + 1;
  If VolFree[V] > 0 Then Dec(VolFree[V]);
  VolFsDirty[V] := True;
  If Zero Then VZero(V, ClusSec(V, R), VolSpc[V]);
End;

Procedure FatFreeChain(V, C : LongInt);
Var N, K : LongInt;
Begin
  K := 0;
  While ClusOk(V, C) And (K <= VolClus[V]) Do
  Begin
    N := FatGet(V, C);
    FatSet(V, C, 0);
    If VolFree[V] >= 0 Then Inc(VolFree[V]);
    C := N;
    Inc(K);
  End;
  VolFsDirty[V] := True;
End;

{ Lire / ecrire N octets a la position Off du cluster C }
Procedure ClusIo(V, C, Off, N, Buf : LongInt; Wr : Boolean);
Var S, SO, K, Run, A, D : LongInt;
Begin
  D := VolDisk[V];
  S := VolStart[V] + ClusSec(V, C) + Off Div 512;
  SO := Off Mod 512;
  While N > 0 Do
  Begin
    If (SO = 0) And (N >= 512) Then
    Begin
      { secteurs entiers : transfert direct }
      Run := N Div 512;
      If Wr Then
      Begin
        If Not HdWrite(D, S, Run, Buf) Then FatIoErr := True;
        SecInval(D, S, Run);
      End
      Else
      Begin
        If Not HdRead(D, S, Run, Buf) Then FatIoErr := True;
      End;
      S := S + Run; Buf := Buf + Run * 512; N := N - Run * 512;
    End
    Else
    Begin
      K := Min(N, 512 - SO);
      A := SecGet(D, S);
      If Wr Then
      Begin
        MoveMem(Buf, A + SO, K);
        SecPut(D, S);
      End
      Else MoveMem(A + SO, Buf, K);
      Inc(S); SO := 0; Buf := Buf + K; N := N - K;
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Repertoires et noms longs                                            }
{ ------------------------------------------------------------------ }

{ Cluster de la racine (0 : racine fixe de FAT12/16) }
Function RootOf(V : LongInt) : LongInt;
Begin
  If VolType[V] = 32 Then RootOf := VolRootClus[V] Else RootOf := 0;
End;

{ Adresse (cache) de l'entree Idx du repertoire Dir ; Sec : secteur
  relatif. 0 apres la fin (Grow : agrandir le repertoire). }
Function DirEnt(V, Dir, Idx : LongInt; Var Sec : LongInt; Grow : Boolean)
  : LongInt;
Var EPC, K, I, C, N : LongInt;
Begin
  DirEnt := 0;
  If Idx < 0 Then Exit;
  If Dir = 0 Then
  Begin
    If Idx >= VolRootCnt[V] Then Exit;
    Sec := VolRootSec[V] + Idx Div 16;
  End
  Else
  Begin
    EPC := VolSpc[V] * 16;
    K := Idx Div EPC;
    If (DcVol = V) And (DcDir = Dir) And (DcK <= K) And (DcK >= 0) Then
    Begin
      I := DcK; C := DcClus;
    End
    Else
    Begin
      I := 0; C := Dir;
    End;
    While I < K Do
    Begin
      N := FatGet(V, C);
      If Not ClusOk(V, N) Then
      Begin
        If Not Grow Then Exit;
        N := FatAlloc(V, C, True);
        If N = 0 Then Exit;
      End;
      C := N;
      Inc(I);
    End;
    DcVol := V; DcDir := Dir; DcK := K; DcClus := C;
    Sec := ClusSec(V, C) + (Idx Mod EPC) Div 16;
  End;
  DirEnt := VSec(V, Sec) + (Idx Mod 16) * 32;
End;

Function LfnSum(Const SN : String) : LongInt;
Var I, S : LongInt;
Begin
  S := 0;
  For I := 1 To 11 Do
    S := ((((S And 1) Shl 7) + (S Shr 1)) + Ord(SN[I])) And $FF;
  LfnSum := S;
End;

{ Nom court affichable (NOM.EXT) d'une entree }
Function ShortOf(A : LongInt; Var Raw : String) : String;
Var I, C : LongInt; B, E : String;
Begin
  Raw := '';
  For I := 0 To 10 Do Raw := Raw + Chr(Mem[0:A + I]);
  If Raw[1] = #5 Then Raw[1] := #229;
  B := ''; E := '';
  For I := 1 To 8 Do
    If Raw[I] <> ' ' Then
    Begin
      C := Ord(Raw[I]);
      If ((Mem[0:A + 12] And 8) <> 0) And (C >= 65) And (C <= 90) Then
        C := C + 32;
      B := B + Chr(C);
    End;
  For I := 9 To 11 Do
    If Raw[I] <> ' ' Then
    Begin
      C := Ord(Raw[I]);
      If ((Mem[0:A + 12] And 16) <> 0) And (C >= 65) And (C <= 90) Then
        C := C + 32;
      E := E + Chr(C);
    End;
  If E <> '' Then ShortOf := B + '.' + E Else ShortOf := B;
End;

{ Entree suivante (a partir de Idx) : Ff* ; False a la fin }
Function DirNext(V, Dir : LongInt; Var Idx : LongInt) : Boolean;
Var A, Sec, B, Seq, K, W, LN, LStart, Ck, P, N : LongInt;
    Raw, Nm : String; Ok : Boolean;
Begin
  DirNext := False;
  LN := 0; LStart := -1; Ck := -1;
  Repeat
    A := DirEnt(V, Dir, Idx, Sec, False);
    If A = 0 Then Exit;
    B := Mem[0:A];
    If B = 0 Then Exit;
    Inc(Idx);
    If B = $E5 Then
    Begin
      LN := 0;
      Continue;
    End;
    If Mem[0:A + 11] = $0F Then
    Begin
      Seq := B And $1F;
      If (B And $40) <> 0 Then
      Begin
        LN := Seq; LStart := Idx - 1; Ck := Mem[0:A + 13];
        For K := 0 To 259 Do LfnBuf[K] := 0;
      End;
      If (LN = 0) Or (Seq < 1) Or (Seq > 20) Or (Mem[0:A + 13] <> Ck) Then
      Begin
        LN := 0;
        Continue;
      End;
      P := (Seq - 1) * 13;
      For K := 0 To 12 Do
      Begin
        If K < 5 Then W := MemW[0:A + 1 + K * 2]
        Else If K < 11 Then W := MemW[0:A + 14 + (K - 5) * 2]
        Else W := MemW[0:A + 28 + (K - 11) * 2];
        If P + K < 260 Then LfnBuf[P + K] := W;
      End;
      Continue;
    End;
    If (Mem[0:A + 11] And 8) <> 0 Then
    Begin
      LN := 0;                       { etiquette de volume }
      Continue;
    End;
    FfShort := ShortOf(A, Raw);
    Nm := '';
    Ok := (LN > 0) And (LfnSum(Raw) = Ck) And (Idx - 1 - LStart = LN);
    If Ok Then
    Begin
      N := 0;
      While (N < 255) And (LfnBuf[N] <> 0) And (LfnBuf[N] <> $FFFF) Do
      Begin
        If LfnBuf[N] < 256 Then Nm := Nm + Chr(LfnBuf[N])
        Else Nm := Nm + '_';
        Inc(N);
      End;
    End;
    If Nm = '' Then
    Begin
      FfName := FfShort;
      FfNEnt := 1;
    End
    Else
    Begin
      FfName := Nm;
      FfNEnt := LN + 1;
    End;
    FfAttr := Mem[0:A + 11];
    FfClus := MemW[0:A + 26];
    If VolType[V] = 32 Then FfClus := FfClus Or (MemW[0:A + 20] Shl 16);
    FfSize := MemL[0:A + 28];
    FfTime := (MemW[0:A + 24] Shl 16) Or MemW[0:A + 22];
    FfDirClus := Dir;
    FfIdx := Idx - 1;
    DirNext := True;
    Exit;
  Until False;
End;

{ Chercher Name (majuscules) dans le repertoire Dir }
Function DirFind(V, Dir : LongInt; Const Name : String) : Boolean;
Var Idx : LongInt;
Begin
  DirFind := False;
  Idx := 0;
  While DirNext(V, Dir, Idx) Do
    If (UpStr(FfName) = Name) Or (UpStr(FfShort) = Name) Then
    Begin
      DirFind := True;
      Exit;
    End;
End;

{ Volume FAT d'un chemin complet (X:\...) ; -1 sinon }
Function FatVolOf(Const Path : String) : LongInt;
Var V, R : LongInt;
Begin
  R := -1;
  If Length(Path) >= 2 Then
    For V := 0 To VolN - 1 Do
      If Ord(Path[1]) = VolLetter[V] Then R := V;
  FatVolOf := R;
End;

{ Resoudre un chemin complet : Ff* decrit l'objet (la racine : Ff Idx
  -1) ; False s'il n'existe pas }
Function FatResolve(V : LongInt; Path : String) : Boolean;
Var Cur, P : LongInt; Part : String;
Begin
  FatResolve := False;
  Path := Copy(Path, 4, 255);
  Cur := RootOf(V);
  FfName := Chr(VolLetter[V]) + ':\'; FfShort := FfName;
  FfAttr := $10; FfClus := Cur; FfSize := 0; FfTime := 0;
  FfDirClus := -1; FfIdx := -1; FfNEnt := 0;
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
    If Part = '' Then Continue;
    If Not DirFind(V, Cur, Part) Then Exit;
    If (Path <> '') And ((FfAttr And $10) = 0) Then Exit;
    Cur := FfClus;
    If ((FfAttr And $10) <> 0) And (Cur = 0) Then Cur := RootOf(V);
  End;
  FatResolve := True;
End;

{ Cluster du repertoire Path (-1 s'il n'existe pas) }
Function FatDirClus(V : LongInt; Const Path : String) : LongInt;
Begin
  FatDirClus := -1;
  If Not FatResolve(V, Path) Then Exit;
  If (FfAttr And $10) = 0 Then Exit;
  If FfIdx < 0 Then FatDirClus := RootOf(V)
  Else If FfClus = 0 Then FatDirClus := RootOf(V)
  Else FatDirClus := FfClus;
End;

{ Mettre a jour cluster, taille et date d'une entree }
Procedure EntSet(V, Dir, Idx, Clus, Size : LongInt; Touch : Boolean);
Var A, Sec, T : LongInt;
Begin
  A := DirEnt(V, Dir, Idx, Sec, False);
  If A = 0 Then Exit;
  MemW[0:A + 26] := Clus And $FFFF;
  If VolType[V] = 32 Then MemW[0:A + 20] := (Clus Shr 16) And $FFFF;
  MemL[0:A + 28] := Size;
  If Touch Then
  Begin
    T := DosNow;
    MemW[0:A + 22] := T And $FFFF;
    MemW[0:A + 24] := (T Shr 16) And $FFFF;
    MemW[0:A + 18] := (T Shr 16) And $FFFF;
  End;
  VPut(V, Sec);
End;

Function Valid83Ch(C : Char) : Boolean;
Var S : String; I : LongInt; R : Boolean;
Begin
  R := ((C >= 'A') And (C <= 'Z')) Or ((C >= '0') And (C <= '9')) Or
       (Ord(C) >= 128);
  S := '!#$%&''()-@^_`{}~';
  For I := 1 To Length(S) Do If S[I] = C Then R := True;
  Valid83Ch := R;
End;

{ Nom 8.3 deja present dans le repertoire ? (SN : 11 caracteres) }
Function ShortTaken(V, Dir : LongInt; Const SN : String) : Boolean;
Var Idx, A, Sec, I : LongInt; Same : Boolean;
Begin
  ShortTaken := False;
  Idx := 0;
  Repeat
    A := DirEnt(V, Dir, Idx, Sec, False);
    If (A = 0) Or (Mem[0:A] = 0) Then Exit;
    If (Mem[0:A] <> $E5) And (Mem[0:A + 11] <> $0F) Then
    Begin
      Same := True;
      For I := 0 To 10 Do
        If Mem[0:A + I] <> Ord(SN[I + 1]) Then Same := False;
      If Same Then
      Begin
        ShortTaken := True;
        Exit;
      End;
    End;
    Inc(Idx);
  Until False;
End;

{ Nom 8.3 (11 caracteres) pour Disp ; NeedLfn si un nom long est requis }
Function MakeShort(V, Dir : LongInt; Const Disp : String;
                   Var NeedLfn : Boolean) : String;
Var U, B, E, SN, T : String; I, P, N : LongInt; Ok : Boolean;
Begin
  U := UpStr(Disp);
  P := 0;
  For I := 1 To Length(U) Do If U[I] = '.' Then P := I;
  If P > 0 Then
  Begin
    B := Copy(U, 1, P - 1); E := Copy(U, P + 1, 255);
  End
  Else
  Begin
    B := U; E := '';
  End;
  Ok := (U = Disp) And (Length(B) >= 1) And (Length(B) <= 8) And
        (Length(E) <= 3) And Not ((P > 0) And (E = ''));
  For I := 1 To Length(B) Do If Not Valid83Ch(B[I]) Then Ok := False;
  For I := 1 To Length(E) Do If Not Valid83Ch(E[I]) Then Ok := False;
  NeedLfn := Not Ok;
  If Ok Then
  Begin
    SN := B;
    While Length(SN) < 8 Do SN := SN + ' ';
    SN := SN + E;
    While Length(SN) < 11 Do SN := SN + ' ';
    MakeShort := SN;
    Exit;
  End;
  { base : caracteres valides, sans espaces ni points }
  T := '';
  For I := 1 To Length(B) Do
    If (B[I] <> ' ') And (B[I] <> '.') Then
      If Valid83Ch(B[I]) Then T := T + B[I] Else T := T + '_';
  If T = '' Then T := 'FICHIER';
  B := T;
  T := '';
  For I := 1 To Length(E) Do
    If (E[I] <> ' ') And (Length(T) < 3) Then
      If Valid83Ch(E[I]) Then T := T + E[I] Else T := T + '_';
  E := T;
  While Length(E) < 3 Do E := E + ' ';
  N := 1;
  Repeat
    T := '~' + IntStr(N);
    SN := Copy(B, 1, 8 - Length(T)) + T;
    While Length(SN) < 8 Do SN := SN + ' ';
    SN := SN + E;
    Inc(N);
  Until Not ShortTaken(V, Dir, SN) Or (N > 99999);
  MakeShort := SN;
End;

{ Creer l'entree Disp (casse conservee) dans Dir ; Ff* la decrit }
Function DirCreate(V, Dir : LongInt; Const Disp : String;
                   Attr, Clus : LongInt) : Boolean;
Var SN : String; NeedLfn : Boolean;
    Cnt, Idx, Run, Start, A, Sec, K, Seq, P, W, Ck, T, J : LongInt;
Begin
  DirCreate := False;
  SN := MakeShort(V, Dir, Disp, NeedLfn);
  Cnt := 1;
  If NeedLfn Then Cnt := (Length(Disp) + 12) Div 13 + 1;
  Idx := 0; Run := 0; Start := -1;
  Repeat
    A := DirEnt(V, Dir, Idx, Sec, True);
    If A = 0 Then Exit;                  { racine pleine ou disque plein }
    If (Mem[0:A] = 0) Or (Mem[0:A] = $E5) Then
    Begin
      Inc(Run);
      If Run = Cnt Then Start := Idx - Cnt + 1;
    End
    Else Run := 0;
    Inc(Idx);
  Until Start >= 0;
  Ck := LfnSum(SN);
  { entrees du nom long (ordre inverse) }
  For Seq := 1 To Cnt - 1 Do
  Begin
    A := DirEnt(V, Dir, Start + Cnt - 1 - Seq, Sec, False);
    FillMem(A, 32, 0);
    If Seq = Cnt - 1 Then Mem[0:A] := Seq Or $40 Else Mem[0:A] := Seq;
    Mem[0:A + 11] := $0F;
    Mem[0:A + 13] := Ck;
    For K := 0 To 12 Do
    Begin
      P := (Seq - 1) * 13 + K;
      If P < Length(Disp) Then W := Ord(Disp[P + 1])
      Else If P = Length(Disp) Then W := 0
      Else W := $FFFF;
      If K < 5 Then J := A + 1 + K * 2
      Else If K < 11 Then J := A + 14 + (K - 5) * 2
      Else J := A + 28 + (K - 11) * 2;
      MemW[0:J] := W;
    End;
    VPut(V, Sec);
  End;
  { entree 8.3 }
  A := DirEnt(V, Dir, Start + Cnt - 1, Sec, False);
  FillMem(A, 32, 0);
  For K := 1 To 11 Do Mem[0:A + K - 1] := Ord(SN[K]);
  If Mem[0:A] = $E5 Then Mem[0:A] := 5;
  Mem[0:A + 11] := Attr;
  T := DosNow;
  MemW[0:A + 14] := T And $FFFF; MemW[0:A + 16] := (T Shr 16) And $FFFF;
  MemW[0:A + 18] := (T Shr 16) And $FFFF;
  MemW[0:A + 22] := T And $FFFF; MemW[0:A + 24] := (T Shr 16) And $FFFF;
  MemW[0:A + 26] := Clus And $FFFF;
  If VolType[V] = 32 Then MemW[0:A + 20] := (Clus Shr 16) And $FFFF;
  VPut(V, Sec);
  FfName := Disp; FfShort := ShortOf(A, SN);
  FfAttr := Attr; FfClus := Clus; FfSize := 0; FfTime := T;
  FfDirClus := Dir; FfIdx := Start + Cnt - 1; FfNEnt := Cnt;
  DirCreate := True;
End;

{ Effacer l'entree Idx et ses NEnt - 1 entrees de nom long }
Procedure DirErase(V, Dir, Idx, NEnt : LongInt);
Var K, A, Sec : LongInt;
Begin
  For K := Idx - NEnt + 1 To Idx Do
  Begin
    A := DirEnt(V, Dir, K, Sec, False);
    If A <> 0 Then
    Begin
      Mem[0:A] := $E5;
      VPut(V, Sec);
    End;
  End;
End;

{ Repertoire vide (hors . et ..) ? }
Function DirEmpty(V, Dir : LongInt) : Boolean;
Var Idx : LongInt;
Begin
  DirEmpty := True;
  Idx := 0;
  While DirNext(V, Dir, Idx) Do
    If (FfShort <> '.') And (FfShort <> '..') Then
    Begin
      DirEmpty := False;
      Exit;
    End;
End;

{ ------------------------------------------------------------------ }
{ Montage                                                              }
{ ------------------------------------------------------------------ }

{ Secteur d'amorce FAT valide en A ? }
Function BpbOk(A : LongInt) : Boolean;
Var Spc : LongInt;
Begin
  Spc := Mem[0:A + 13];
  BpbOk := (MemW[0:A + 11] = 512) And (Spc > 0) And
           ((Spc And (Spc - 1)) = 0) And (Mem[0:A + 16] >= 1) And
           (Mem[0:A + 16] <= 2) And (MemW[0:A + 14] >= 1) And
           (Mem[0:A + 21] >= $F0);
End;

Function VolMount(D, Start, Secs : LongInt) : Boolean;
Var V, A, Tot, FatSz, RootSecs, DataSecs, K : LongInt; S : String;
Begin
  VolMount := False;
  If VolN >= MaxVol Then Exit;
  V := VolN;
  VolDisk[V] := D; VolStart[V] := Start;
  A := SecGet(D, Start);
  If FatIoErr Or Not BpbOk(A) Then
  Begin
    FatIoErr := False;
    Exit;
  End;
  VolSpc[V] := Mem[0:A + 13];
  VolRsvd[V] := MemW[0:A + 14];
  VolNFats[V] := Mem[0:A + 16];
  VolRootCnt[V] := MemW[0:A + 17];
  Tot := MemW[0:A + 19];
  If Tot = 0 Then Tot := MemL[0:A + 32];
  FatSz := MemW[0:A + 22];
  If FatSz = 0 Then FatSz := MemL[0:A + 36];
  If (Tot <= 0) Or (FatSz <= 0) Then Exit;
  If (Secs > 0) And (Tot > Secs) Then Tot := Secs;
  VolSecs[V] := Tot;
  VolFatSz[V] := FatSz;
  RootSecs := (VolRootCnt[V] * 32 + 511) Div 512;
  VolRootSec[V] := VolRsvd[V] + VolNFats[V] * FatSz;
  VolData[V] := VolRootSec[V] + RootSecs;
  DataSecs := Tot - VolData[V];
  If DataSecs <= 0 Then Exit;
  VolClus[V] := DataSecs Div VolSpc[V];
  If VolClus[V] < 4085 Then VolType[V] := 12
  Else If VolClus[V] < 65525 Then VolType[V] := 16
  Else VolType[V] := 32;
  VolActFat[V] := -1;
  VolFree[V] := -1; VolNext[V] := 2; VolFsInfo[V] := 0;
  VolRootClus[V] := 0;
  If VolType[V] = 32 Then
  Begin
    VolRootClus[V] := MemL[0:A + 44];
    If (MemW[0:A + 40] And $80) <> 0 Then
      VolActFat[V] := MemW[0:A + 40] And 15;
    VolFsInfo[V] := MemW[0:A + 48];
    VolSerial[V] := MemL[0:A + 67];
    S := '';
    For K := 0 To 10 Do S := S + Chr(Mem[0:A + 71 + K]);
  End
  Else
  Begin
    VolSerial[V] := MemL[0:A + 39];
    S := '';
    For K := 0 To 10 Do S := S + Chr(Mem[0:A + 43 + K]);
  End;
  If Mem[0:A + 38 + 28 * Ord(VolType[V] = 32)] <> $29 Then S := '';
  If S = 'NO NAME    ' Then S := '';
  VolLab[V] := Trim(S);
  If (VolType[V] = 32) And (VolFsInfo[V] > 0) And
     (VolFsInfo[V] < VolRsvd[V]) Then
  Begin
    A := VSec(V, VolFsInfo[V]);
    If (MemL[0:A] = $41615252) And (MemL[0:A + 484] = $61417272) Then
    Begin
      If (MemL[0:A + 488] >= 0) And (MemL[0:A + 488] <= VolClus[V]) Then
        VolFree[V] := MemL[0:A + 488];
      If ClusOk(V, MemL[0:A + 492]) Then VolNext[V] := MemL[0:A + 492];
    End;
  End;
  VolFsDirty[V] := False;
  If VolN = 0 Then VolLetter[V] := Ord('C')
  Else VolLetter[V] := Ord('D') + VolN;
  Inc(VolN);
  { etiquette dans la racine (prioritaire, comme Windows) }
  K := 0;
  Repeat
    A := DirEnt(V, RootOf(V), K, FatSz, False);
    If (A = 0) Or (Mem[0:A] = 0) Then Break;
    If (Mem[0:A] <> $E5) And (Mem[0:A + 11] And $1F = 8) Then
    Begin
      S := '';
      For FatSz := 0 To 10 Do S := S + Chr(Mem[0:A + FatSz]);
      VolLab[V] := Trim(S);
      Break;
    End;
    Inc(K);
  Until K > 64;
  KLog('FAT' + IntStr(VolType[V]) + ' : ' + Chr(VolLetter[V]) +
       ': disque ' + IntStr(D) + ' secteur ' + IntStr(Start) + ', ' +
       IntStr(VolClus[V]) + ' clusters de ' + IntStr(VolSpc[V] * 512) +
       ' octets, etiquette ' + VolLab[V]);
  VolMount := True;
End;

Function IsFatPart(T : LongInt) : Boolean;
Begin
  IsFatPart := (T = $01) Or (T = $04) Or (T = $06) Or (T = $0B) Or
               (T = $0C) Or (T = $0E);
End;

{ Partitions d'un disque : primaires puis logiques ; sans table de
  partitions, le disque entier }
Procedure DiskScan(D : LongInt);
Var A, I, T, St, Sz, Ext, Ebr, N : LongInt; Found : Boolean;
    PT, PS, PZ : Array[0..3] Of LongInt;
Begin
  A := SecGet(D, 0);
  If FatIoErr Then
  Begin
    FatIoErr := False;
    Exit;
  End;
  If MemW[0:A + 510] <> $AA55 Then Exit;
  Found := False;
  For I := 0 To 3 Do
  Begin
    PT[I] := Mem[0:A + 446 + I * 16 + 4];
    PS[I] := MemL[0:A + 446 + I * 16 + 8];
    PZ[I] := MemL[0:A + 446 + I * 16 + 12];
    If (PT[I] <> 0) And ((Mem[0:A + 446 + I * 16] And $7F) <> 0) Then
      PT[I] := -1;                       { pas une table de partitions }
  End;
  If BpbOk(A) And ((PT[0] < 0) Or (PT[0] = 0) Or (PS[0] = 0)) Then
  Begin
    VolMount(D, 0, DiskSecs[D]);
    Exit;
  End;
  Ext := 0;
  For I := 0 To 3 Do
  Begin
    T := PT[I];
    If IsFatPart(T) And (PS[I] > 0) Then
      If VolMount(D, PS[I], PZ[I]) Then Found := True;
    If (T = $05) Or (T = $0F) Or (T = $85) Then Ext := PS[I];
  End;
  { partitions logiques de la partition etendue }
  Ebr := Ext; N := 0;
  While (Ext > 0) And (Ebr > 0) And (N < 16) Do
  Begin
    A := SecGet(D, Ebr);
    If FatIoErr Or (MemW[0:A + 510] <> $AA55) Then Break;
    T := Mem[0:A + 446 + 4];
    St := MemL[0:A + 446 + 8];
    Sz := MemL[0:A + 446 + 12];
    I := MemL[0:A + 446 + 16 + 8];
    If (Mem[0:A + 446 + 16 + 4] = 0) Or (I = 0) Then I := -1;
    If IsFatPart(T) And (St > 0) Then VolMount(D, Ebr + St, Sz);
    If I < 0 Then Ebr := 0 Else Ebr := Ext + I;
    Inc(N);
  End;
  FatIoErr := False;
End;

{ Ecrire FSInfo et vider les caches des disques }
Procedure FatFlush;
Var V, A, D : LongInt;
Begin
  For V := 0 To VolN - 1 Do
    If VolFsDirty[V] Then
    Begin
      VolFsDirty[V] := False;
      If (VolType[V] = 32) And (VolFsInfo[V] > 0) Then
      Begin
        A := VSec(V, VolFsInfo[V]);
        If MemL[0:A] = $41615252 Then
        Begin
          MemL[0:A + 488] := VolFree[V];
          MemL[0:A + 492] := VolNext[V];
          VPut(V, VolFsInfo[V]);
        End;
      End;
    End;
  For D := 0 To DiskN - 1 Do HdFlush(D);
End;

Function FatMkDirIn(V, Parent : LongInt; Const Disp : String) : Boolean;
  Forward;

{ Repertoires de Windows sur C: (crees s'ils manquent) }
Procedure FatWinDirs;
Var R, W : LongInt;
Begin
  If (VolN = 0) Or (VolLetter[0] <> Ord('C')) Then Exit;
  R := RootOf(0);
  If Not DirFind(0, R, 'WINDOWS') Then
  Begin
    FatMkDirIn(0, R, 'WINDOWS');
    KLog('FAT : C:\WINDOWS cree');
  End;
  W := FatDirClus(0, 'C:\WINDOWS');
  If W >= 0 Then
  Begin
    If Not DirFind(0, W, 'SYSTEM') Then FatMkDirIn(0, W, 'SYSTEM');
    If Not DirFind(0, W, 'TEMP') Then FatMkDirIn(0, W, 'TEMP');
  End;
  If Not DirFind(0, R, 'TEMP') Then FatMkDirIn(0, R, 'TEMP');
  FatFlush;
End;

Procedure FatInit;
Var I, HO : LongInt;
Begin
  HO := HeapOwner;
  HeapOwner := 0;
  FatScratch := KAlloc(1024);
  FatZero := KAlloc(64 * 512);
  For I := 0 To SecSlots - 1 Do
  Begin
    SecBuf[I] := KAlloc(512);
    SecLba[I] := -1; SecDisk[I] := -1; SecAge[I] := 0;
  End;
  HeapOwner := HO;
  FillMem(FatZero, 64 * 512, 0);
  For I := 0 To MaxFo - 1 Do FoUsed[I] := False;
  DcVol := -1;
  DiskN := 0; VolN := 0;
  HdIdentify($1F0, $3F6, False);
  HdIdentify($1F0, $3F6, True);
  HdIdentify($170, $376, False);
  HdIdentify($170, $376, True);
  For I := 0 To DiskN - 1 Do
  Begin
    KLog('Disque ' + IntStr(I) + ' : ' + HexStr(DiskBase[I], 3) +
         ' esclave=' + IntStr(Ord(DiskSlave[I])) + ', ' +
         IntStr(DiskSecs[I] Div 2048) + ' Mo');
    DiskScan(I);
  End;
  FatWinDirs;
End;

{ ------------------------------------------------------------------ }
{ Operations sur les fichiers (appelees par l'API Win32)               }
{ ------------------------------------------------------------------ }

{ Informations sur un chemin complet d'un volume FAT }
Function FatPathInfo(Const Path : String; Var Attr, Size, Time : LongInt)
  : Boolean;
Var V : LongInt;
Begin
  FatPathInfo := False;
  V := FatVolOf(Path);
  If (V < 0) Or Not FatResolve(V, Path) Then Exit;
  Attr := FfAttr And $37;
  If Attr = 0 Then Attr := $80;
  Size := FfSize; Time := FfTime;
  If (FfAttr And $10) <> 0 Then Size := 0;
  FatPathInfo := True;
End;

Function FatMkDirIn(V, Parent : LongInt; Const Disp : String) : Boolean;
Var C, A, Sec, T, PC : LongInt;
Begin
  FatMkDirIn := False;
  C := FatAlloc(V, 0, True);
  If C = 0 Then Exit;
  { . et .. }
  A := DirEnt(V, C, 0, Sec, False);
  T := DosNow;
  FillMem(A, 64, 0);
  FillMem(A, 11, 32); Mem[0:A] := 46;
  FillMem(A + 32, 11, 32); Mem[0:A + 32] := 46; Mem[0:A + 33] := 46;
  If Parent = RootOf(V) Then PC := 0 Else PC := Parent;
  Mem[0:A + 11] := $10; Mem[0:A + 43] := $10;
  MemW[0:A + 22] := T And $FFFF; MemW[0:A + 24] := (T Shr 16) And $FFFF;
  MemW[0:A + 54] := T And $FFFF; MemW[0:A + 56] := (T Shr 16) And $FFFF;
  MemW[0:A + 26] := C And $FFFF; MemW[0:A + 58] := PC And $FFFF;
  If VolType[V] = 32 Then
  Begin
    MemW[0:A + 20] := (C Shr 16) And $FFFF;
    MemW[0:A + 52] := (PC Shr 16) And $FFFF;
  End;
  VPut(V, Sec);
  If Not DirCreate(V, Parent, Disp, $10, C) Then
  Begin
    FatFreeChain(V, C);
    Exit;
  End;
  FatMkDirIn := True;
End;

{ Nom affiche : base d'origine (casse conservee) si elle correspond }
Function DispName(Const Path, Orig : String) : String;
Var B : String;
Begin
  B := BaseName(Path);
  If (Orig <> '') And (UpStr(Orig) = B) Then DispName := Orig
  Else DispName := B;
End;

{ Codes d'erreur Win32 : 0 succes }
Function FatMkDir(Const Path, Orig : String) : LongInt;
Var V, P : LongInt;
Begin
  FatMkDir := 3;                                   { chemin introuvable }
  V := FatVolOf(Path);
  If (V < 0) Or (Length(Path) <= 3) Then Exit;
  If FatResolve(V, Path) Then
  Begin
    FatMkDir := 183;                               { existe deja }
    Exit;
  End;
  P := FatDirClus(V, ParentDir(Path));
  If P < 0 Then Exit;
  If FatMkDirIn(V, P, DispName(Path, Orig)) Then FatMkDir := 0
  Else FatMkDir := 112;                            { disque plein }
  FatFlush;
End;

Function FatRmDir(Const Path : String) : LongInt;
Var V, C : LongInt;
Begin
  FatRmDir := 3;
  V := FatVolOf(Path);
  If (V < 0) Or Not FatResolve(V, Path) Or (FfIdx < 0) Then Exit;
  If (FfAttr And $10) = 0 Then Exit;
  C := FfClus;
  If Not DirEmpty(V, C) Then
  Begin
    FatRmDir := 145;                               { pas vide }
    Exit;
  End;
  FatResolve(V, Path);
  DirErase(V, FfDirClus, FfIdx, FfNEnt);
  FatFreeChain(V, C);
  DcVol := -1;
  FatFlush;
  FatRmDir := 0;
End;

Function FatDelete(Const Path : String) : LongInt;
Var V, I : LongInt;
Begin
  FatDelete := 2;                                  { introuvable }
  V := FatVolOf(Path);
  If (V < 0) Or Not FatResolve(V, Path) Or (FfIdx < 0) Then Exit;
  If (FfAttr And $10) <> 0 Then
  Begin
    FatDelete := 5;
    Exit;
  End;
  For I := 0 To MaxFo - 1 Do
    If FoUsed[I] And (FoVol[I] = V) And (FoDir[I] = FfDirClus) And
       (FoIdx[I] = FfIdx) Then
    Begin
      FatDelete := 32;                             { fichier ouvert }
      Exit;
    End;
  DirErase(V, FfDirClus, FfIdx, FfNEnt);
  FatFreeChain(V, FfClus);
  FatFlush;
  FatDelete := 0;
End;

{ Renommer / deplacer (meme volume) }
Function FatRename(Const Src, Dst, Orig : String) : LongInt;
Var V, P, Attr, Clus, Size, Time, Dir, Idx, NEnt, A, Sec : LongInt;
Begin
  FatRename := 2;
  V := FatVolOf(Src);
  If (V < 0) Or (FatVolOf(Dst) <> V) Then
  Begin
    If V >= 0 Then FatRename := 17;                { autre volume }
    Exit;
  End;
  If Not FatResolve(V, Src) Or (FfIdx < 0) Then Exit;
  Attr := FfAttr; Clus := FfClus; Size := FfSize; Time := FfTime;
  Dir := FfDirClus; Idx := FfIdx; NEnt := FfNEnt;
  If FatResolve(V, Dst) Then
  Begin
    FatRename := 183;
    Exit;
  End;
  P := FatDirClus(V, ParentDir(Dst));
  If P < 0 Then
  Begin
    FatRename := 3;
    Exit;
  End;
  If Not DirCreate(V, P, DispName(Dst, Orig), Attr, Clus) Then
  Begin
    FatRename := 112;
    Exit;
  End;
  EntSet(V, FfDirClus, FfIdx, Clus, Size, False);
  A := DirEnt(V, FfDirClus, FfIdx, Sec, False);
  MemW[0:A + 22] := Time And $FFFF; MemW[0:A + 24] := (Time Shr 16) And $FFFF;
  VPut(V, Sec);
  DirErase(V, Dir, Idx, NEnt);
  { repertoire deplace : mettre a jour son entree .. }
  If ((Attr And $10) <> 0) And (Dir <> P) And ClusOk(V, Clus) Then
  Begin
    A := DirEnt(V, Clus, 1, Sec, False);
    If (A <> 0) And (Mem[0:A] = 46) And (Mem[0:A + 1] = 46) Then
    Begin
      If P = RootOf(V) Then P := 0;
      MemW[0:A + 26] := P And $FFFF;
      If VolType[V] = 32 Then MemW[0:A + 20] := (P Shr 16) And $FFFF;
      VPut(V, Sec);
    End;
  End;
  DcVol := -1;
  FatFlush;
  FatRename := 0;
End;

{ Ouvrir un fichier : indice de fichier ouvert, ou -1 (Err) }
Function FatOpen(Const Path, Orig : String; Wr : Boolean;
                 Disp : LongInt; Var Err : LongInt) : LongInt;
Var V, F, I, P : LongInt; Ex : Boolean;
Begin
  FatOpen := -1;
  V := FatVolOf(Path);
  Err := 3;
  If V < 0 Then Exit;
  Ex := FatResolve(V, Path);
  If Ex And ((FfAttr And $10) <> 0) Then
  Begin
    Err := 5;
    Exit;
  End;
  If Ex And (Disp = 1) Then
  Begin
    Err := 80;                                     { existe deja }
    Exit;
  End;
  If Not Ex And ((Disp = 3) Or (Disp = 5)) Then
  Begin
    Err := 2;
    If FatDirClus(V, ParentDir(Path)) < 0 Then Err := 3;
    Exit;
  End;
  If Ex And Wr And ((FfAttr And 1) <> 0) Then
  Begin
    Err := 5;                                      { lecture seule }
    Exit;
  End;
  F := -1;
  For I := MaxFo - 1 DownTo 0 Do If Not FoUsed[I] Then F := I;
  If F < 0 Then
  Begin
    Err := 4;
    Exit;
  End;
  If Not Ex Then
  Begin
    P := FatDirClus(V, ParentDir(Path));
    If P < 0 Then Exit;
    If Not DirCreate(V, P, DispName(Path, Orig), $20, 0) Then
    Begin
      Err := 112;
      Exit;
    End;
  End;
  FoUsed[F] := True;
  FoVol[F] := V; FoClus[F] := FfClus; FoSize[F] := FfSize;
  FoDir[F] := FfDirClus; FoIdx[F] := FfIdx; FoTime[F] := FfTime;
  FoCIdx[F] := -1; FoCClus[F] := 0;
  FoDirty[F] := Not Ex;
  If Ex And ((Disp = 2) Or (Disp = 5)) And (FoSize[F] > 0) Then
  Begin
    FatFreeChain(V, FoClus[F]);
    FoClus[F] := 0; FoSize[F] := 0;
    EntSet(V, FoDir[F], FoIdx[F], 0, 0, True);
    FoDirty[F] := True;
  End;
  Err := 0;
  FatOpen := F;
End;

{ Cluster d'indice K du fichier F (Grow : allonger la chaine) ; 0 sinon }
Function FoClusAt(F, K : LongInt; Grow : Boolean) : LongInt;
Var V, I, C, N : LongInt;
Begin
  FoClusAt := 0;
  V := FoVol[F];
  If FoClus[F] = 0 Then
  Begin
    If Not Grow Then Exit;
    C := FatAlloc(V, 0, False);
    If C = 0 Then Exit;
    FoClus[F] := C;
    EntSet(V, FoDir[F], FoIdx[F], C, FoSize[F], True);
  End;
  If (FoCIdx[F] >= 0) And (FoCIdx[F] <= K) Then
  Begin
    I := FoCIdx[F]; C := FoCClus[F];
  End
  Else
  Begin
    I := 0; C := FoClus[F];
  End;
  While I < K Do
  Begin
    N := FatGet(V, C);
    If Not ClusOk(V, N) Then
    Begin
      If Not Grow Then Exit;
      N := FatAlloc(V, C, False);
      If N = 0 Then Exit;
    End;
    C := N;
    Inc(I);
  End;
  FoCIdx[F] := K; FoCClus[F] := C;
  FoClusAt := C;
End;

Function FatRead(F, Pos0, N, Dst : LongInt) : LongInt;
Var CB, Done, K, Off, L, C : LongInt;
Begin
  If Pos0 + N > FoSize[F] Then N := FoSize[F] - Pos0;
  If N < 0 Then N := 0;
  CB := ClusBytes(FoVol[F]);
  Done := 0;
  While Done < N Do
  Begin
    K := (Pos0 + Done) Div CB;
    Off := (Pos0 + Done) Mod CB;
    L := Min(N - Done, CB - Off);
    C := FoClusAt(F, K, False);
    If C = 0 Then Break;
    ClusIo(FoVol[F], C, Off, L, Dst + Done, False);
    Done := Done + L;
  End;
  FatRead := Done;
End;

Function FatWrite(F, Pos0, N, Src : LongInt) : LongInt;
Var CB, Done, K, Off, L, C, Z : LongInt;
Begin
  FatWrite := -1;
  { ecriture au-dela de la fin : remplir l'intervalle de zeros }
  While FoSize[F] < Pos0 Do
  Begin
    Z := Min(Pos0 - FoSize[F], 32768);
    If FatWrite(F, FoSize[F], Z, FatZero) < Z Then Exit;
  End;
  CB := ClusBytes(FoVol[F]);
  Done := 0;
  While Done < N Do
  Begin
    K := (Pos0 + Done) Div CB;
    Off := (Pos0 + Done) Mod CB;
    L := Min(N - Done, CB - Off);
    C := FoClusAt(F, K, True);
    If C = 0 Then Break;
    ClusIo(FoVol[F], C, Off, L, Src + Done, True);
    Done := Done + L;
  End;
  If Pos0 + Done > FoSize[F] Then FoSize[F] := Pos0 + Done;
  EntSet(FoVol[F], FoDir[F], FoIdx[F], FoClus[F], FoSize[F], True);
  FoDirty[F] := True;
  FatWrite := Done;
End;

{ Fixer la taille du fichier (troncature ou extension) }
Function FatSetSize(F, NewSize : LongInt) : Boolean;
Var V, CB, K, C, N : LongInt;
Begin
  FatSetSize := True;
  If NewSize = FoSize[F] Then Exit;
  If NewSize > FoSize[F] Then
  Begin
    FatSetSize := FatWrite(F, NewSize, 0, FatZero) >= 0;
    Exit;
  End;
  V := FoVol[F];
  CB := ClusBytes(V);
  K := (NewSize + CB - 1) Div CB;
  If K = 0 Then
  Begin
    FatFreeChain(V, FoClus[F]);
    FoClus[F] := 0;
  End
  Else
  Begin
    C := FoClusAt(F, K - 1, False);
    If C <> 0 Then
    Begin
      N := FatGet(V, C);
      FatSet(V, C, FatEoc);
      If ClusOk(V, N) Then FatFreeChain(V, N);
    End;
  End;
  FoCIdx[F] := -1;
  FoSize[F] := NewSize;
  EntSet(V, FoDir[F], FoIdx[F], FoClus[F], NewSize, True);
  FoDirty[F] := True;
End;

Procedure FatClose(F : LongInt);
Begin
  If (F < 0) Or (F >= MaxFo) Or Not FoUsed[F] Then Exit;
  FoUsed[F] := False;
  If FoDirty[F] Then FatFlush;
End;

{ Fichier entier dans un bloc du tas (0 si erreur) }
Function FatLoad(Const Path : String; Var Size : LongInt) : LongInt;
Var F, E, A : LongInt;
Begin
  FatLoad := 0;
  F := FatOpen(Path, '', False, 3, E);
  If F < 0 Then Exit;
  Size := FoSize[F];
  A := KAlloc(Size + 16);
  If A <> 0 Then
    If FatRead(F, 0, Size, A) <> Size Then
    Begin
      KFree(A);
      A := 0;
    End;
  FoUsed[F] := False;
  FatLoad := A;
End;

{ Entree N d'un repertoire (hors . et ..) pour FindFirstFile et
  l'Explorateur }
Function FatDirEntry(Const Dir : String; N : LongInt; Var Idx : LongInt)
  : Boolean;
Var V, C, K : LongInt;
Begin
  FatDirEntry := False;
  V := FatVolOf(Dir);
  If V < 0 Then Exit;
  C := FatDirClus(V, Dir);
  If C < 0 Then Exit;
  K := 0;
  While DirNext(V, C, Idx) Do
    If (FfShort <> '.') And (FfShort <> '..') Then
    Begin
      FatDirEntry := True;
      Exit;
    End;
End;

{ Espace libre et total d'un volume (en clusters) }
Procedure FatSpace(V : LongInt; Var Free0, Total, Spc : LongInt);
Begin
  If VolFree[V] < 0 Then FatCountFree(V);
  Free0 := VolFree[V]; Total := VolClus[V]; Spc := VolSpc[V];
End;

{ ------------------------------------------------------------------ }
{ Formatage FAT32 d'un disque vierge (une partition sur tout le disque) }
{ ------------------------------------------------------------------ }

Function FatFormat(D : LongInt; Const Lab : String) : Boolean;
Var Start, Secs, Spc, Rsvd, FatSz, A, B, K, T, Mb : LongInt; S : String;
Begin
  FatFormat := False;
  Start := 2048;
  Secs := DiskSecs[D] - Start;
  Mb := DiskSecs[D] Div 2048;
  If Mb < 40 Then Exit;
  If Mb <= 260 Then Spc := 1
  Else If Mb <= 8192 Then Spc := 8
  Else If Mb <= 16384 Then Spc := 16
  Else If Mb <= 32768 Then Spc := 32
  Else Spc := 64;
  Rsvd := 32;
  T := (256 * Spc + 2) Div 2;
  FatSz := (Secs - Rsvd + T - 1) Div T;
  KLog('FAT32 : formatage du disque ' + IntStr(D) + ' (' + IntStr(Mb) +
       ' Mo, clusters de ' + IntStr(Spc * 512) + ' octets)');
  A := FatScratch;
  { table de partitions : une partition FAT32 (LBA) active }
  FillMem(A, 512, 0);
  Mem[0:A] := $CD; Mem[0:A + 1] := $18;              { int 18h }
  B := A + 446;
  Mem[0:B] := $80; Mem[0:B + 1] := $FE; Mem[0:B + 2] := $FF;
  Mem[0:B + 3] := $FF; Mem[0:B + 4] := $0C; Mem[0:B + 5] := $FE;
  Mem[0:B + 6] := $FF; Mem[0:B + 7] := $FF;
  MemL[0:B + 8] := Start; MemL[0:B + 12] := Secs;
  MemW[0:A + 510] := $AA55;
  If Not HdWrite(D, 0, 1, A) Then Exit;
  { zones reservees et FAT }
  K := 0;
  While K < Rsvd + 2 * FatSz + Spc Do
  Begin
    T := Min(64, Rsvd + 2 * FatSz + Spc - K);
    If Not HdWrite(D, Start + K, T, FatZero) Then Exit;
    K := K + T;
  End;
  { secteur d'amorce (BPB FAT32) }
  FillMem(A, 512, 0);
  Mem[0:A] := $EB; Mem[0:A + 1] := $58; Mem[0:A + 2] := $90;
  S := 'MSWIN4.1';
  For K := 1 To 8 Do Mem[0:A + 2 + K] := Ord(S[K]);
  MemW[0:A + 11] := 512; Mem[0:A + 13] := Spc; MemW[0:A + 14] := Rsvd;
  Mem[0:A + 16] := 2; Mem[0:A + 21] := $F8;
  MemW[0:A + 24] := 63; MemW[0:A + 26] := 255;
  MemL[0:A + 28] := Start; MemL[0:A + 32] := Secs;
  MemL[0:A + 36] := FatSz; MemL[0:A + 44] := 2;
  MemW[0:A + 48] := 1; MemW[0:A + 50] := 6;
  Mem[0:A + 64] := $80; Mem[0:A + 66] := $29;
  MemL[0:A + 67] := DosNow;
  FillMem(A + 71, 11, 32);
  For K := 1 To Min(Length(Lab), 11) Do Mem[0:A + 70 + K] := Ord(Lab[K]);
  S := 'FAT32   ';
  For K := 1 To 8 Do Mem[0:A + 81 + K] := Ord(S[K]);
  Mem[0:A + 90] := $CD; Mem[0:A + 91] := $18;        { int 18h }
  MemW[0:A + 510] := $AA55;
  If Not HdWrite(D, Start, 1, A) Then Exit;
  If Not HdWrite(D, Start + 6, 1, A) Then Exit;
  { FSInfo }
  FillMem(A, 512, 0);
  MemL[0:A] := $41615252; MemL[0:A + 484] := $61417272;
  MemL[0:A + 488] := (Secs - Rsvd - 2 * FatSz) Div Spc - 1;
  MemL[0:A + 492] := 3;
  MemW[0:A + 510] := $AA55;
  If Not HdWrite(D, Start + 1, 1, A) Then Exit;
  If Not HdWrite(D, Start + 7, 1, A) Then Exit;
  { FAT : entrees 0, 1 et racine (cluster 2) }
  FillMem(A, 512, 0);
  MemL[0:A] := $0FFFFFF8; MemL[0:A + 4] := $0FFFFFFF;
  MemL[0:A + 8] := $0FFFFFFF;
  If Not HdWrite(D, Start + Rsvd, 1, A) Then Exit;
  If Not HdWrite(D, Start + Rsvd + FatSz, 1, A) Then Exit;
  { etiquette dans la racine }
  If Lab <> '' Then
  Begin
    FillMem(A, 512, 0);
    FillMem(A, 11, 32);
    For K := 1 To Min(Length(Lab), 11) Do Mem[0:A + K - 1] := Ord(Lab[K]);
    Mem[0:A + 11] := 8;
    T := DosNow;
    MemW[0:A + 22] := T And $FFFF; MemW[0:A + 24] := (T Shr 16) And $FFFF;
    If Not HdWrite(D, Start + Rsvd + 2 * FatSz, 1, A) Then Exit;
  End;
  HdFlush(D);
  SecInval(D, 0, DiskSecs[D]);
  DiskScan(D);
  FatWinDirs;
  FatFormat := VolN > 0;
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
  { VGA 16 couleurs (mode 12h, 4 plans) quand IO.SYS n'a pas trouve de
    mode VESA : l'ecran 256 couleurs (Back) est converti a la copie }
  VgaPlanar : Boolean;
  VgaMapChanged : Boolean;
  VgaMap    : Array[0..255] Of Byte;     { indice -> couleur VGA 0..15 }
  VgaP      : Array[0..319] Of Byte;     { 4 plans de 80 octets }
  VgaTmp    : Array[0..47] Of Byte;
  { VgaTab[K * 256 + I] : bits des 4 plans (un octet par plan) du pixel
    d'indice I en position K (0 = bit 7) d'un octet ; refaite quand
    VgaMap change }
  VgaTab    : Array[0..2047] Of LongInt;
  VgaTabOk  : Boolean;
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

Const
  { couleurs du pilote VGA de Windows, dans l'ordre de l'interface 16
    couleurs d'IO.SYS (1 bordeaux, 4 marine...) : le logo de demarrage
    qu'IO.SYS laisse a l'ecran garde ses couleurs }
  VgaRGB : Array[0..15] Of LongInt = (
    $000000, $800000, $008000, $808000, $000080, $800080, $008080,
    $C0C0C0, $808080, $FF0000, $00FF00, $FFFF00, $0000FF, $FF00FF,
    $00FFFF, $FFFFFF);

Procedure VgaInit;
Var I, B : LongInt;
Begin
  { attributs : plan i -> registre DAC i ; DAC 0..15 = couleurs VGA }
  B := Port[$3DA];
  For I := 0 To 15 Do
  Begin
    Port[$3C0] := I;
    Port[$3C0] := I;
  End;
  Port[$3C0] := $14;
  Port[$3C0] := 0;
  Port[$3C0] := $20;
  For I := 0 To 15 Do
  Begin
    Port[$3C8] := I;
    Port[$3C9] := ((VgaRGB[I] Shr 16) And 255) Shr 2;
    Port[$3C9] := ((VgaRGB[I] Shr 8) And 255) Shr 2;
    Port[$3C9] := (VgaRGB[I] And 255) Shr 2;
  End;
  { mode d'ecriture 0, sans Set/Reset ni rotation, tous les bits }
  Port[$3CE] := 1; Port[$3CF] := 0;
  Port[$3CE] := 3; Port[$3CF] := 0;
  Port[$3CE] := 5; Port[$3CF] := 0;
  Port[$3CE] := 8; Port[$3CF] := $FF;
  VgaMapChanged := True;
  VgaTabOk := False;
End;

{ Couleur VGA la plus proche de l'entree I de la palette systeme }
Procedure VgaMapSet(I : LongInt);
Var K, Best, D, BestD, DR, DG, DB : LongInt;
Begin
  Best := 0; BestD := $7FFFFFFF;
  For K := 0 To 15 Do
  Begin
    DR := SysPal[I * 3] - ((VgaRGB[K] Shr 16) And 255);
    DG := SysPal[I * 3 + 1] - ((VgaRGB[K] Shr 8) And 255);
    DB := SysPal[I * 3 + 2] - (VgaRGB[K] And 255);
    D := DR * DR + DG * DG + DB * DB;
    If D < BestD Then
    Begin
      BestD := D; Best := K;
    End;
  End;
  If VgaMap[I] <> Best Then
  Begin
    VgaMap[I] := Best;
    VgaMapChanged := True;
    VgaTabOk := False;
  End;
End;

Procedure VgaTabBuild;
Var K, I, C, Bit, V : LongInt;
Begin
  For K := 0 To 7 Do
  Begin
    Bit := $80 Shr K;
    For I := 0 To 255 Do
    Begin
      C := VgaMap[I]; V := 0;
      If (C And 1) <> 0 Then V := V Or Bit;
      If (C And 2) <> 0 Then V := V Or (Bit Shl 8);
      If (C And 4) <> 0 Then V := V Or (Bit Shl 16);
      If (C And 8) <> 0 Then V := V Or (Bit Shl 24);
      VgaTab[K * 256 + I] := V;
    End;
  End;
  VgaTabOk := True;
End;

{ Ecrire la ligne Y, octets B0..B1 (pixels B0*8..B1*8+7), depuis Src :
  pixels 8 bits a partir de B0*8 }
Procedure VgaWriteRow(Y, B0, B1, Src : LongInt);
Var N, TabA, PA, A : LongInt;
Begin
  If B0 < 0 Then B0 := 0;
  If B1 > 79 Then B1 := 79;
  If (B0 > B1) Or (Y < 0) Or (Y >= ScrH) Then Exit;
  If Not VgaTabOk Then VgaTabBuild;
  N := B1 - B0 + 1;
  TabA := LongInt(@VgaTab);
  PA := LongInt(@VgaP);
  { 8 pixels -> 4 octets de plans : 8 consultations de VgaTab (une table
    de 1024 octets par position), en assembleur - la version Pascal
    coutait environ 250 instructions par octet, ce qui laissait l'ecran
    noir de longues secondes au demarrage }
  asm
    push esi
    push edi
    push ebx
    mov esi,Src
    mov edi,PA
    mov ecx,N
    mov ebx,TabA
  @lp:
    movzx eax,byte ptr [esi]
    shl eax,2
    add eax,ebx
    mov edx,[eax]
    movzx eax,byte ptr [esi+1]
    shl eax,2
    add eax,ebx
    or edx,[eax+1024]
    movzx eax,byte ptr [esi+2]
    shl eax,2
    add eax,ebx
    or edx,[eax+2048]
    movzx eax,byte ptr [esi+3]
    shl eax,2
    add eax,ebx
    or edx,[eax+3072]
    movzx eax,byte ptr [esi+4]
    shl eax,2
    add eax,ebx
    or edx,[eax+4096]
    movzx eax,byte ptr [esi+5]
    shl eax,2
    add eax,ebx
    or edx,[eax+5120]
    movzx eax,byte ptr [esi+6]
    shl eax,2
    add eax,ebx
    or edx,[eax+6144]
    movzx eax,byte ptr [esi+7]
    shl eax,2
    add eax,ebx
    or edx,[eax+7168]
    mov [edi],dl
    mov [edi+80],dh
    shr edx,16
    mov [edi+160],dl
    mov [edi+240],dh
    add esi,8
    inc edi
    dec ecx
    jnz @lp
    pop ebx
    pop edi
    pop esi
  end;
  A := Lfb + Y * LfbPitch + B0;
  Port[$3C4] := 2;
  Port[$3C5] := 1;
  MoveMem(PA, A, N);
  Port[$3C5] := 2;
  MoveMem(PA + 80, A, N);
  Port[$3C5] := 4;
  MoveMem(PA + 160, A, N);
  Port[$3C5] := 8;
  MoveMem(PA + 240, A, N);
  Port[$3C5] := $0F;
End;

Procedure DacSet(I : LongInt);
Begin
  If VgaPlanar Then
  Begin
    VgaMapSet(I);
    Exit;
  End;
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
  If VgaPlanar Then
  Begin
    For Y := R.T To R.B - 1 Do
      VgaWriteRow(Y, R.L Shr 3, (R.R - 1) Shr 3,
                  Back.Bits + Y * Back.Pitch + (R.L And Not 7));
    Exit;
  End;
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

{ Pointeur en VGA 16 couleurs : ligne recomposee (fond de Back puis
  pointeur) dans VgaTmp, puis ecrite dans les 4 plans }
Procedure CursorDrawVga;
Var X, Y, PX, PY, V, X0, B0, B1, I : LongInt;
Begin
  X0 := CurX - CurHotX;
  B0 := X0; If B0 < 0 Then B0 := 0;
  B0 := B0 Shr 3;
  B1 := X0 + CurW - 1; If B1 > ScrW - 1 Then B1 := ScrW - 1;
  If B1 < 0 Then Exit;
  B1 := B1 Shr 3;
  For Y := 0 To CurHh - 1 Do
  Begin
    PY := CurY - CurHotY + Y;
    If (PY >= 0) And (PY < ScrH) Then
    Begin
      For I := 0 To (B1 - B0 + 1) * 8 - 1 Do
        VgaTmp[I] := Mem[0:Back.Bits + PY * Back.Pitch + B0 * 8 + I];
      For X := 0 To CurW - 1 Do
      Begin
        PX := X0 + X;
        V := CurMap[Y * 32 + X];
        If (V <> 0) And (PX >= B0 * 8) And (PX < (B1 + 1) * 8) Then
        Begin
          If V = 1 Then VgaTmp[PX - B0 * 8] := cBlack
          Else If V = 2 Then VgaTmp[PX - B0 * 8] := cWhite
          Else VgaTmp[PX - B0 * 8] := VgaTmp[PX - B0 * 8] Xor 255;
        End;
      End;
      VgaWriteRow(PY, B0, B1, LongInt(@VgaTmp));
    End;
  End;
  CurShownB := True;
End;

Procedure CursorDraw;
Var X, Y, PX, PY, V, A : LongInt;
Begin
  If CurHide < 0 Then Exit;
  If VgaPlanar Then
  Begin
    CursorDrawVga;
    Exit;
  End;
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
Var R, C, I : TRect; Y : LongInt;
Begin
  { VGA 16 couleurs : palette changee, tout l'ecran a reconvertir }
  If VgaPlanar And VgaMapChanged Then
  Begin
    VgaMapChanged := False;
    If DDShow Then DDDirty := True
    Else If (Dirty.L <= 0) And (Dirty.T <= 0) And (Dirty.R >= ScrW) And
            (Dirty.B >= ScrH) Then
      { tout l'ecran va etre recompose et converti juste apres }
    Else
    Begin
      SetR(R, 0, 0, ScrW, ScrH);
      LfbCopy(R);
      If CurShownB Then CursorDraw;
    End;
  End;
  { DirectDraw en mode exclusif : la surface primaire occupe l'ecran }
  If DDShow Then
  Begin
    If DDDirty Then
      For Y := 0 To Min(DDH, ScrH) - 1 Do
        If VgaPlanar Then
          VgaWriteRow(Y, 0, (Min(DDW, ScrW) - 1) Shr 3, DDBuf + Y * DDW)
        Else
          MoveMem(DDBuf + Y * DDW, Lfb + Y * LfbPitch, Min(DDW, ScrW));
    DDDirty := False;
    SetR(Dirty, 0, 0, 0, 0);
    Exit;
  End;
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
  { par tache : pile de l'anneau 0 pour le code 16 bits (TSS.ESP0),
    proprietaire des blocs memoire (1 Win32, 2 Win16), tache Win16 }
  ThrEsp0  : Array[0..MaxThread - 1] Of LongInt;
  ThrOwner : Array[0..MaxThread - 1] Of LongInt;
  ThrW16   : Array[0..MaxThread - 1] Of Boolean;
  TssBase  : LongInt;
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
  HeapOwner := ThrOwner[N];
  If TssBase <> 0 Then MemL[0:TssBase + 4] := ThrEsp0[N];
  ThreadSetFs(N);
  SliceStart := Ticks;
  SwitchCtx;
  HeapOwner := ThrOwner[CurT];
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
  Eip := MemL[0:F + 44];
  { code 16 bits (anneau 3) : toujours preemptible }
  If (MemL[0:F + 48] And 3) <> 3 Then
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
  ThrOwner[T] := Ord(IsApp);
  ThrW16[T] := False;
  ThrEsp0[T] := (Threads[T].Stack + StackSz - 64) And Not 15;
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
  WS_OVERLAPPED = 0;
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
  { #1 : touche sans caractere (WPC concatene les chaines comme des
    PChar : un #0 couperait la chaine) }
  KeyLo := #1#27'1234567890-='#8#9'qwertyuiop[]'#13#1 +
           'asdfghjkl;''`'#1'\zxcvbnm,./'#1'*'#1' ';
  KeyHi := #1#27'!@#$%^&*()_+'#8#9'QWERTYUIOP{}'#13#1 +
           'ASDFGHJKL:"~'#1'|ZXCVBNM<>?'#1'*'#1' ';
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
  If C <> #1 Then ScanToChar := Ord(C);
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
    DIMX := DIMX + Dx; DIMY := DIMY + Dy; DIMBtn := Bt;
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
  cmSafeMode = 10; cmDosMode = 11; cmNetwork = 12;
  cmDocBase = 100; cmExeBase = 200;
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
Procedure NetConfigBox; Forward;
Function NetRunCmd(S : String) : Boolean; Forward;

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
    mnSettings : MenuCount := 3;
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
      Else If I = 2 Then
      Begin
        T := L('R'#130'seau (TCP/IP)...', 'Network (TCP/IP)...',
               'Netzwerk (TCP/IP)...', 'Rete (TCP/IP)...',
               'Red (TCP/IP)...');
        Cmd := cmNetwork; Icon := icComputer;
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

Var
  FmtAskW : LongInt;          { boite ? formater le disque ? ? }

{ Formater le disque dur 0 en FAT32 (reponse Oui) }
Procedure FormatDisk0;
Var I : LongInt;
Begin
  If FatFormat(0, 'PASDOWS') Then
    MsgBoxOpen(L('Formatage', 'Format', 'Formatieren', 'Formattazione',
      'Formatear'), L('Le disque C: est format'#130' (FAT32).',
      'Drive C: has been formatted (FAT32).',
      'Laufwerk C: wurde formatiert (FAT32).',
      'L''unit'#133' C: '#138' stata formattata (FAT32).',
      'La unidad C: ha sido formateada (FAT32).'), $40)
  Else
    MsgBoxOpen(L('Formatage', 'Format', 'Formatieren', 'Formattazione',
      'Formatear'), L('Impossible de formater le disque.',
      'Unable to format the disk.', 'Formatieren nicht m'#148'glich.',
      'Impossibile formattare il disco.',
      'No se puede formatear el disco.'), $10);
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And (Wnds[I].IKind = ikExplorer) Then KRepaint(I);
End;

Procedure MsgBoxEnd(W, Res : LongInt);
Begin
  If (W = FmtAskW) And (FmtAskW >= 0) Then
  Begin
    FmtAskW := -1;
    If Res = IDYES Then FormatDisk0;
  End;
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

Var
  ExpCW, ExpCI, ExpCIdx : LongInt;      { parcours FAT en cours }
  ExpCS : String[127];

Function ExpEntry(W, I : LongInt; Var Nm : String; Var Fl, Size : LongInt)
  : Boolean;
Var DL, DS, Lba, Tm, V, Idx, K : LongInt; Ok : Boolean;
Begin
  ExpEntry := False;
  If Wnds[W].KS = '' Then
  Begin
    { lecteurs : C:, D: (CD-ROM), puis les autres volumes FAT }
    Fl := 2; Size := 0;
    If I = 0 Then
    Begin
      If VolN > 0 Then Nm := Trim(VolLab[0] + ' (C:)') Else Nm := '(C:)';
      ExpEntry := True;
    End
    Else If I = 1 Then
    Begin
      Nm := VolLabel + ' (D:)'; ExpEntry := True;
    End
    Else If I < VolN + 1 Then
    Begin
      V := I - 1;
      Nm := Trim(VolLab[V] + ' (' + Chr(VolLetter[V]) + ':)');
      ExpEntry := True;
    End;
    Exit;
  End;
  If FatVolOf(Wnds[W].KS) >= 0 Then
  Begin
    { volume FAT : reprendre le parcours precedent si possible }
    If (ExpCW = W) And (ExpCS = Wnds[W].KS) And (ExpCI < I) Then
    Begin
      K := ExpCI; Idx := ExpCIdx;
    End
    Else
    Begin
      K := -1; Idx := 0;
    End;
    Ok := True;
    While Ok And (K < I) Do
    Begin
      Ok := FatDirEntry(Wnds[W].KS, 0, Idx);
      Inc(K);
    End;
    If Not Ok Then
    Begin
      ExpCW := -1;
      Exit;
    End;
    ExpCW := W; ExpCS := Wnds[W].KS; ExpCI := I; ExpCIdx := Idx;
    Nm := FfName; Size := FfSize;
    If (FfAttr And $10) <> 0 Then Fl := 2 Else Fl := 0;
    ExpEntry := True;
    Exit;
  End;
  If Not ExpDirLba(W, DL, DS) Then Exit;
  ExpEntry := IsoDirEntry(DL, DS, I, Nm, Lba, Size, Fl, Tm);
End;

Function ExpIcon(Nm : String; Fl : LongInt) : LongInt;
Var E : String;
Begin
  E := UpStr(Copy(Nm, Pos('.', Nm) + 1, 3));
  If Pos('(D:)', Nm) > 0 Then ExpIcon := icCdrom
  Else If (Pos(':)', Nm) > 0) And (Nm[Length(Nm)] = ')') Then
    ExpIcon := icHardDisk
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
    If (I = 0) And (VolN = 0) And (DiskN > 0) Then
    Begin
      { disque dur sans volume FAT : proposer de le formater }
      FmtAskW := MsgBoxOpen(L('Poste de travail', 'My Computer',
        'Arbeitsplatz', 'Risorse del computer', 'Mi PC'), L(
        'Le disque dur (' + IntStr(DiskSecs[0] Div 2048) + ' Mo) n''est ' +
        'pas format'#130'. Voulez-vous le formater en FAT32 ? Toutes ses ' +
        'donn'#130'es seront effac'#130'es.',
        'The hard disk (' + IntStr(DiskSecs[0] Div 2048) + ' MB) is not ' +
        'formatted. Do you want to format it (FAT32)? All data on it ' +
        'will be erased.',
        'Die Festplatte ist nicht formatiert. Jetzt mit FAT32 ' +
        'formatieren? Alle Daten werden gel'#148'scht.',
        'Il disco non '#138' formattato. Formattarlo in FAT32? Tutti i dati ' +
        'verranno cancellati.',
        'El disco no est'#160' formateado. '#168'Desea formatearlo en FAT32? ' +
        'Se borrar'#160'n todos los datos.'), $34);
      Exit;
    End;
    If (I = 0) And (VolN = 0) Then
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
    If I = 0 Then Wnds[W].KS := 'C:'
    Else If I = 1 Then Wnds[W].KS := 'D:'
    Else Wnds[W].KS := Chr(VolLetter[I - 1]) + ':';
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
      If Not NetRunCmd(S) And Not RunExe(S, '') Then
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
  FatFlush;
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
    cmNetwork : NetConfigBox;
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
    Err := MemL[0:Frame + 44];
    Eip := MemL[0:Frame + 48];
  End
  Else
  Begin
    Err := 0;
    Eip := MemL[0:Frame + 44];
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
  S := Nm + ' EIP=' + HexStr(Eip, 8) + ' CS=' +
       HexStr(MemL[0:Frame + 48 + 4 * Ord(Vec >= 256)], 4)
       + ' ERR=' + HexStr(Err, 4) +
       ' EAX=' + HexStr(MemL[0:Frame + 40], 8) + ' EBX=' +
       HexStr(MemL[0:Frame + 28], 8) + ' ECX=' + HexStr(MemL[0:Frame + 36], 8)
       + ' EDX=' + HexStr(MemL[0:Frame + 32], 8) + ' ESI=' +
       HexStr(MemL[0:Frame + 16], 8) + ' EDI=' + HexStr(MemL[0:Frame + 12], 8)
       + ' EBP=' + HexStr(MemL[0:Frame + 20], 8) + ' ESP=' +
       HexStr(Frame + 56 + 4 * Ord(Vec >= 256), 8);
  KLog('FAUTE (tache ' + IntStr(CurT) + ') ' + S);
  X := Frame + 56 + 4 * Ord(Vec >= 256);
  Nm := 'Pile :';
  For V := 0 To 11 Do Nm := Nm + ' ' + HexStr(MemL[0:X + V * 4], 8);
  KLog(Nm);
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
{ Nom de base tel que le programme l'a ecrit (casse conservee) }
Function OrigBase(Const Name : String) : String;
Var P, E, I : LongInt; R : String;
Begin
  E := Length(Name);
  While (E > 0) And ((Name[E] <= ' ') Or (Name[E] = '\') Or
        (Name[E] = '/')) Do Dec(E);
  P := E;
  While (P > 0) And (Name[P] <> '\') And (Name[P] <> '/') And
        (Name[P] <> ':') Do Dec(P);
  R := '';
  For I := P + 1 To E Do R := R + Name[I];
  OrigBase := R;
End;

Function KOpenFile(Name : String; Wr : Boolean; Disp : LongInt) : LongInt;
Var Path, Ob : String; Attr, Size, Time, Lba, Ram, I, F, E : LongInt;
    Ex : Boolean;
Begin
  KOpenFile := INVALID_HANDLE;
  If (UpStr(Name) = 'CON') Or (UpStr(Name) = 'CONOUT$') Then
  Begin
    KOpenFile := HStdOut;
    Exit;
  End;
  If (UpStr(Name) = 'NUL') Or (UpStr(Name) = 'C:\NUL') Then
  Begin
    { peripherique nul : lectures vides, ecritures ignorees }
    I := KObjNew(koFile);
    If I < 0 Then Exit;
    KObjs[I].F1 := -1; KObjs[I].F4 := -2; KObjs[I].F5 := 1;
    KObjs[I].Name := 'NUL';
    KOpenFile := KHandle(I);
    Exit;
  End;
  Path := FullPath(Name);
  If FatVolOf(Path) >= 0 Then
  Begin
    { volume FAT d'un disque dur }
    Ob := OrigBase(Name);
    F := FatOpen(Path, Ob, Wr, Disp, E);
    If ApiTrace Then KLog('Fichier FAT : ' + Path + ' -> ' + IntStr(F));
    If F < 0 Then
    Begin
      SetErr(E);
      Exit;
    End;
    I := KObjNew(koFile);
    If I < 0 Then
    Begin
      FatClose(F);
      SetErr(4);
      Exit;
    End;
    KObjs[I].F1 := -1;
    KObjs[I].F2 := FoSize[F];
    KObjs[I].F3 := 0;
    KObjs[I].F4 := -1000 - F;
    KObjs[I].F5 := Ord(Wr);
    KObjs[I].F6 := FoTime[F];
    KObjs[I].Name := Path;
    If (Disp = 4) And Not FoDirty[F] Then SetErr(183) Else SetErr(0);
    KOpenFile := KHandle(I);
    Exit;
  End;
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
  If (KObjs[I].Kind = koFile) And (KObjs[I].F4 <= -1000) Then
    FatClose(-1000 - KObjs[I].F4);
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
  If KObjs[I].F4 <= -1000 Then
  Begin
    R := -1000 - KObjs[I].F4;
    FatIoErr := False;
    Got := FatRead(R, KObjs[I].F3, N, Buf);
    KObjs[I].F3 := KObjs[I].F3 + Got;
    KObjs[I].F2 := FoSize[R];
    If FatIoErr Then SetErr(30);
    KReadFile := Not FatIoErr;
    Exit;
  End;
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
  If (I >= 0) And (KObjs[I].F4 = -2) Then
  Begin
    KWriteFile := N;                               { NUL }
    Exit;
  End;
  If (I >= 0) And (KObjs[I].F4 <= -1000) And (KObjs[I].F5 <> 0) Then
  Begin
    R := -1000 - KObjs[I].F4;
    FatIoErr := False;
    E := FatWrite(R, KObjs[I].F3, N, Buf);
    If E < 0 Then E := 0;
    KObjs[I].F3 := KObjs[I].F3 + E;
    KObjs[I].F2 := FoSize[R];
    If (E < N) Or FatIoErr Then
    Begin
      If FatIoErr Then SetErr(29) Else SetErr(112);
      If E = 0 Then Exit;
    End;
    KWriteFile := E;
    Exit;
  End;
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
  If (I >= 0) And (KObjs[I].F4 <= -1000) And (KObjs[I].F5 <> 0) Then
  Begin
    If Not FatSetSize(-1000 - KObjs[I].F4, KObjs[I].F3) Then
    Begin
      SetErr(112);
      Exit;
    End;
    KObjs[I].F2 := KObjs[I].F3;
    SetEndOfFile := 1;
    Exit;
  End;
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
Var R : LongInt; S : String;
Begin
  DeleteFileA := 0;
  S := FullPath(PStr(PName));
  If FatVolOf(S) >= 0 Then
  Begin
    R := FatDelete(S);
    If R <> 0 Then SetErr(R) Else DeleteFileA := 1;
    Exit;
  End;
  R := RamFind(S);
  If R < 0 Then
  Begin
    SetErr(ErrFileNotFound);
    Exit;
  End;
  If RamFiles[R].Data <> 0 Then KFree(RamFiles[R].Data);
  RamFiles[R].Used := False;
  DeleteFileA := 1;
End;

Function CreateDirectoryA(PName, Sec : LongInt) : LongInt;
Var S, Ob : String; R, Attr, Size, Time, Lba, Ram : LongInt;
Begin
  CreateDirectoryA := 0;
  S := FullPath(PStr(PName));
  If Length(S) > 3 Then
    If S[Length(S)] = '\' Then S := Copy(S, 1, Length(S) - 1);
  If FatVolOf(S) >= 0 Then
  Begin
    Ob := PStr(PName);
    Ob := OrigBase(Ob);
    R := FatMkDir(S, Ob);
    If R <> 0 Then SetErr(R) Else CreateDirectoryA := 1;
    Exit;
  End;
  If PathInfo(S, Attr, Size, Time, Lba, Ram) Then
  Begin
    SetErr(183);
    Exit;
  End;
  If (Copy(S, 1, 2) <> 'C:') Then
  Begin
    SetErr(ErrAccessDenied);
    Exit;
  End;
  If Not IsCDir(ParentDir(S)) Then
  Begin
    SetErr(ErrPathNotFound);
    Exit;
  End;
  R := RamNew(S);
  If R < 0 Then
  Begin
    SetErr(4);
    Exit;
  End;
  RamFiles[R].Attr := $10;
  CreateDirectoryA := 1;
End;

Function RemoveDirectoryA(PName : LongInt) : LongInt;
Var S : String; R, I : LongInt;
Begin
  RemoveDirectoryA := 0;
  S := FullPath(PStr(PName));
  If FatVolOf(S) >= 0 Then
  Begin
    R := FatRmDir(S);
    If R <> 0 Then SetErr(R) Else RemoveDirectoryA := 1;
    Exit;
  End;
  R := RamFind(S);
  If (R < 0) Or (RamFiles[R].Attr <> $10) Then
  Begin
    SetErr(ErrPathNotFound);
    Exit;
  End;
  For I := 0 To MaxRam - 1 Do
    If RamFiles[I].Used And (ParentDir(RamFiles[I].Path) = S) Then
    Begin
      SetErr(145);
      Exit;
    End;
  RamFiles[R].Used := False;
  RemoveDirectoryA := 1;
End;

Function MoveFileA(PSrc, PDst : LongInt) : LongInt;
Var R, A, Size, H, V : LongInt; S, D, Ob : String;
Begin
  MoveFileA := 0;
  S := FullPath(PStr(PSrc)); D := FullPath(PStr(PDst));
  V := FatVolOf(S);
  If (V >= 0) And (FatVolOf(D) = V) Then
  Begin
    Ob := PStr(PDst);
    Ob := OrigBase(Ob);
    R := FatRename(S, D, Ob);
    If R <> 0 Then SetErr(R) Else MoveFileA := 1;
    Exit;
  End;
  If (V >= 0) Or (FatVolOf(D) >= 0) Then
  Begin
    { d'un volume a l'autre : copier puis supprimer }
    A := LoadWholeFile(S, Size);
    If A = 0 Then
    Begin
      SetErr(ErrFileNotFound);
      Exit;
    End;
    H := KOpenFile(PStr(PDst), True, 1);
    If H <> INVALID_HANDLE Then
    Begin
      R := KWriteFile(H, A, Size);
      CloseHandle(H);
      If R = Size Then
      Begin
        If V >= 0 Then FatDelete(S)
        Else
        Begin
          R := RamFind(S);
          If R >= 0 Then
          Begin
            If RamFiles[R].Data <> 0 Then KFree(RamFiles[R].Data);
            RamFiles[R].Used := False;
          End;
        End;
        MoveFileA := 1;
      End;
    End;
    KFree(A);
    Exit;
  End;
  R := RamFind(S);
  If R < 0 Then
  Begin
    SetErr(ErrAccessDenied);
    Exit;
  End;
  RamFiles[R].Path := D;
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

{ Volume FAT de la racine PRoot (0 : repertoire courant) ; -1 sinon }
Function RootVol(PRoot : LongInt) : LongInt;
Var S : String;
Begin
  If PRoot = 0 Then S := CurDirS Else S := UpStr(PStr(PRoot));
  If S = '' Then S := CurDirS;
  RootVol := FatVolOf(Copy(S, 1, 1) + ':');
End;

Function GetDiskFreeSpaceA(PRoot, PSpc, PBps, PFree, PTotal : LongInt)
  : LongInt;
Var V, Fr, Tot, Spc, Mx : LongInt;
Begin
  V := RootVol(PRoot);
  If V >= 0 Then
  Begin
    FatSpace(V, Fr, Tot, Spc);
    { comme Windows 95 : au plus 2 Go annonces }
    Mx := $7FFF8000 Div (Spc * 512);
    If PSpc <> 0 Then MemL[0:PSpc] := Spc;
    If PBps <> 0 Then MemL[0:PBps] := 512;
    If PFree <> 0 Then MemL[0:PFree] := Min(Fr, Mx);
    If PTotal <> 0 Then MemL[0:PTotal] := Min(Tot, Mx);
    GetDiskFreeSpaceA := 1;
    Exit;
  End;
  If PSpc <> 0 Then MemL[0:PSpc] := 8;
  If PBps <> 0 Then MemL[0:PBps] := 512;
  If PFree <> 0 Then MemL[0:PFree] := HeapFreeBytes Div 4096;
  If PTotal <> 0 Then MemL[0:PTotal] := (MemTop Div 4096);
  GetDiskFreeSpaceA := 1;
End;

{ Octets d'un nombre de clusters (64 bits) en P }
Procedure PutBytes64(P, Clus, Spc : LongInt);
Var Sh, B : LongInt;
Begin
  If P = 0 Then Exit;
  Sh := 9; B := Spc;
  While B > 1 Do
  Begin
    Inc(Sh);
    B := B Shr 1;
  End;
  MemL[0:P] := Clus Shl Sh;
  MemL[0:P + 4] := Clus Shr (32 - Sh);
End;

{ GetDiskFreeSpaceExA (Windows 95 OSR2) : tailles sur 64 bits }
Function GetDiskFreeSpaceExA(PRoot, PAvail, PTotal, PFree : LongInt)
  : LongInt;
Var V, Fr, Tot, Spc : LongInt;
Begin
  V := RootVol(PRoot);
  If V >= 0 Then FatSpace(V, Fr, Tot, Spc)
  Else
  Begin
    Spc := 8; Fr := HeapFreeBytes Div 4096; Tot := MemTop Div 4096;
  End;
  PutBytes64(PAvail, Fr, Spc);
  PutBytes64(PTotal, Tot, Spc);
  PutBytes64(PFree, Fr, Spc);
  GetDiskFreeSpaceExA := 1;
End;

Function GetDriveTypeA(PRoot : LongInt) : LongInt;
Var S : String;
Begin
  If PRoot = 0 Then S := CurDirS Else S := UpStr(PStr(PRoot));
  If S = '' Then S := CurDirS;
  If FatVolOf(Copy(S, 1, 1) + ':') >= 0 Then
  Begin
    GetDriveTypeA := 3;
    Exit;
  End;
  Case S[1] Of
    'C' : GetDriveTypeA := 3;
    'D' : GetDriveTypeA := 5;
  Else
    GetDriveTypeA := 1;
  End;
End;

Function GetLogicalDrives : LongInt;
Var V, R : LongInt;
Begin
  R := 12;
  For V := 0 To VolN - 1 Do R := R Or (1 Shl (VolLetter[V] - 65));
  GetLogicalDrives := R;
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
Var D : String; V : LongInt;
Begin
  If PRoot <> 0 Then D := UpStr(PStr(PRoot)) Else D := CurDirS;
  V := FatVolOf(Copy(D, 1, 1) + ':');
  If V >= 0 Then
  Begin
    { volume FAT : noms longs, casse conservee, Unicode sur le disque }
    If PVol <> 0 Then PutPStr(PVol, VolLab[V], VolSize);
    If PSerial <> 0 Then MemL[0:PSerial] := VolSerial[V];
    If PMaxComp <> 0 Then MemL[0:PMaxComp] := 255;
    If PFlags <> 0 Then MemL[0:PFlags] := 6;
    If PFs <> 0 Then
      If VolType[V] = 32 Then PutPStr(PFs, 'FAT32', FsSize)
      Else PutPStr(PFs, 'FAT', FsSize);
  End
  Else If (D <> '') And (D[1] = 'C') Then
  Begin
    { disque en memoire : noms longs (VFAT), casse conservee }
    If PVol <> 0 Then PutPStr(PVol, 'PASDOWS', VolSize);
    If PSerial <> 0 Then MemL[0:PSerial] := $19951995;
    If PMaxComp <> 0 Then MemL[0:PMaxComp] := 255;
    If PFlags <> 0 Then MemL[0:PFlags] := 2;
    If PFs <> 0 Then PutPStr(PFs, 'FAT', FsSize);
  End
  Else
  Begin
    If PVol <> 0 Then PutPStr(PVol, VolLabel, VolSize);
    If PSerial <> 0 Then MemL[0:PSerial] := $19950824;
    If PMaxComp <> 0 Then MemL[0:PMaxComp] := 12;
    If PFlags <> 0 Then MemL[0:PFlags] := 0;
    If PFs <> 0 Then PutPStr(PFs, 'CDFS', FsSize);
  End;
  GetVolumeInformationA := 1;
End;

{ Recherche : F1 position, F2 0 = CD, 1 = disque virtuel ; Name chemin
  du repertoire, Mask masque }
Function FindStep(I, P : LongInt) : Boolean;
Var Nm : String; Lba, Size, Fl, Tm, DL, DS, Attr, R, Idx : LongInt;
Begin
  FindStep := False;
  If KObjs[I].F2 = 2 Then
  Begin
    { volume FAT : noms longs et noms courts }
    Idx := KObjs[I].F1;
    While FatDirEntry(KObjs[I].Name, 0, Idx) Do
    Begin
      KObjs[I].F1 := Idx;
      If MatchMask(UpStr(FfName), KObjs[I].Mask) Or
         MatchMask(UpStr(FfShort), KObjs[I].Mask) Then
      Begin
        FillMem(P, 318, 0);
        Attr := FfAttr And $37;
        If Attr = 0 Then Attr := $80;
        MemL[0:P] := Attr;
        DosToFileTime(FfTime, P + 4);
        DosToFileTime(FfTime, P + 12);
        DosToFileTime(FfTime, P + 20);
        If (FfAttr And $10) = 0 Then MemL[0:P + 32] := FfSize;
        PutPStr(P + 44, FfName, 260);
        If FfShort <> FfName Then PutPStr(P + 304, FfShort, 14);
        FindStep := True;
        Exit;
      End;
    End;
    KObjs[I].F1 := Idx;
    Exit;
  End;
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
  If FatVolOf(KObjs[I].Name) >= 0 Then KObjs[I].F2 := 2;
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
  { OF_REOPEN : chemin pris dans le tampon OFSTRUCT d'une ouverture
    precedente }
  If ((Style And $8000) <> 0) And (POf <> 0) Then S := PStr(POf + 8)
  Else S := FullPath(PStr(PName));
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
    S := S + #0;
    OpenFile := DeleteFileA(LongInt(@S[1]));
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
        Cur := UpStr(Trim(Copy(Line, 2, Pos(']', Line) - 2)));
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

{ Noms des cles d'une section (ou des sections si Sect = #0), separes
  par des zeros, double zero final ; nombre d'octets ecrits }
Function IniEnum(F, Sect : String; Buf, N : LongInt) : LongInt;
Var A, Size, P, C, O : LongInt; Line, Cur, Nm : String; InSect : Boolean;
Begin
  IniEnum := 0;
  If N < 2 Then Exit;
  Mem[0:Buf] := 0; Mem[0:Buf + 1] := 0;
  A := LoadWholeFile(IniPath(F), Size);
  If A = 0 Then Exit;
  Sect := UpStr(Sect);
  InSect := False; Line := ''; O := 0;
  For P := 0 To Size Do
  Begin
    If P < Size Then C := Mem[0:A + P] Else C := 10;
    If (C = 10) Or (C = 13) Then
    Begin
      Line := Trim(Line);
      Nm := '';
      If (Length(Line) > 1) And (Line[1] = '[') Then
      Begin
        Cur := Trim(Copy(Line, 2, Pos(']', Line) - 2));
        InSect := UpStr(Cur) = Sect;
        If Sect = #0 Then Nm := Cur;
      End
      Else If InSect And (Pos('=', Line) > 0) And (Line[1] <> ';') Then
        Nm := Trim(Copy(Line, 1, Pos('=', Line) - 1));
      If (Nm <> '') And (O + Length(Nm) + 2 <= N) Then
      Begin
        For C := 1 To Length(Nm) Do Mem[0:Buf + O + C - 1] := Ord(Nm[C]);
        O := O + Length(Nm) + 1;
        Mem[0:Buf + O - 1] := 0;
        Mem[0:Buf + O] := 0;
      End;
      Line := '';
    End
    Else If Length(Line) < 250 Then Line := Line + Chr(C);
  End;
  KFree(A);
  IniEnum := O;
End;

Function GetPrivateProfileStringA(App, Key, Def, Buf, N, F : LongInt)
  : LongInt;
Var V : String;
Begin
  If (App = 0) Or (Key = 0) Then
  Begin
    If App = 0 Then V := #0 Else V := PStr(App);
    GetPrivateProfileStringA := IniEnum(PStr(F), V, Buf, N);
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
  { mutex nomme deja cree : meme objet, ERROR_ALREADY_EXISTS }
  If Name <> 0 Then
    For I := 0 To MaxKObj - 1 Do
      If KObjs[I].Used And (KObjs[I].Kind = koMutex) And
         (KObjs[I].Name = UpStr(PStr(Name))) Then
      Begin
        SetErr(183);
        CreateMutexA := KHandle(I);
        Exit;
      End;
  I := KObjNew(koMutex);
  If I < 0 Then
  Begin
    CreateMutexA := 0;
    Exit;
  End;
  If Name <> 0 Then KObjs[I].Name := UpStr(PStr(Name));
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

{ ------------------------------------------------------------------ }
{ ADVAPI32 : registre en memoire (cles et valeurs), partage avec les   }
{ programmes 16 bits (SHELL.DLL). Racines : 80000000h CLASSES_ROOT    }
{ (1 en Win16), ...01h CURRENT_USER, ...02h LOCAL_MACHINE, ...03h     }
{ USERS, ...05h CURRENT_CONFIG, ...06h DYN_DATA ; autres cles :       }
{ poignee 00C00000h + indice.                                         }
{ ------------------------------------------------------------------ }

Const
  MaxRK = 400;
  MaxRV = 800;
  HKBase = $00C00000;

Var
  RKUsed : Array[0..MaxRK - 1] Of Boolean;
  RKPar : Array[0..MaxRK - 1] Of LongInt;
  RKNameP : Array[0..MaxRK - 1] Of LongInt;
  RVUsed : Array[0..MaxRV - 1] Of Boolean;
  RVKey, RVType, RVData, RVSize : Array[0..MaxRV - 1] Of LongInt;
  RVNameP : Array[0..MaxRV - 1] Of LongInt;

{ Noms des cles et valeurs : chaines terminees par zero dans le tas }
Function RegStrNew(S : String) : LongInt;
Var A : LongInt;
Begin
  A := KAlloc(Length(S) + 1);
  PutPStr(A, S, Length(S) + 1);
  RegStrNew := A;
End;

Function RKName(I : LongInt) : String;
Begin
  If RKNameP[I] = 0 Then RKName := '' Else RKName := PStr(RKNameP[I]);
End;

Function RVName(I : LongInt) : String;
Begin
  If RVNameP[I] = 0 Then RVName := '' Else RVName := PStr(RVNameP[I]);
End;

Function RegKeyOf(H : LongInt) : LongInt;
Begin
  RegKeyOf := -1;
  If H = 1 Then RegKeyOf := 0
  Else If (H >= LongInt($80000000)) And (H <= LongInt($80000006)) Then
  Begin
    H := H And 7;
    If H = 4 Then Exit;
    If H >= 5 Then H := H - 1;
    RegKeyOf := H;
  End
  Else If (H >= HKBase) And (H < HKBase + MaxRK) Then
    If RKUsed[H - HKBase] Then RegKeyOf := H - HKBase;
End;

Function RegChild(K : LongInt; Nm : String; Create : Boolean) : LongInt;
Var I : LongInt; U : String;
Begin
  RegChild := -1;
  U := UpStr(Nm);
  For I := 0 To MaxRK - 1 Do
    If RKUsed[I] And (RKPar[I] = K) And (UpStr(RKName(I)) = U) Then
    Begin
      RegChild := I;
      Exit;
    End;
  If Not Create Then Exit;
  For I := 6 To MaxRK - 1 Do
    If Not RKUsed[I] Then
    Begin
      RKUsed[I] := True; RKPar[I] := K; RKNameP[I] := RegStrNew(Nm);
      RegChild := I;
      Exit;
    End;
End;

{ Cle Path sous K (creee si Create) ; -1 si absente }
Function RegWalk(K : LongInt; Path : String; Create : Boolean) : LongInt;
Var P : LongInt; Part : String;
Begin
  RegWalk := -1;
  If K < 0 Then Exit;
  While Path <> '' Do
  Begin
    P := Pos('\', Path);
    If P > 0 Then
    Begin
      Part := Copy(Path, 1, P - 1); Delete(Path, 1, P);
    End
    Else
    Begin
      Part := Path; Path := '';
    End;
    If Part <> '' Then
    Begin
      K := RegChild(K, Part, Create);
      If K < 0 Then Exit;
    End;
  End;
  RegWalk := K;
End;

Function RegVal(K : LongInt; Nm : String) : LongInt;
Var I : LongInt; U : String;
Begin
  RegVal := -1;
  U := UpStr(Nm);
  For I := 0 To MaxRV - 1 Do
    If RVUsed[I] And (RVKey[I] = K) And (UpStr(RVName(I)) = U) Then
    Begin
      RegVal := I;
      Exit;
    End;
End;

Function RegSetK(K : LongInt; Nm : String; Typ, Data, Size : LongInt)
  : LongInt;
Var I, J : LongInt;
Begin
  RegSetK := 1;
  If K < 0 Then Exit;
  I := RegVal(K, Nm);
  If I < 0 Then
    For J := MaxRV - 1 DownTo 0 Do
      If Not RVUsed[J] Then I := J;
  If I < 0 Then Exit;
  If RVUsed[I] And (RVData[I] <> 0) Then KFree(RVData[I]);
  If Not RVUsed[I] Then RVNameP[I] := RegStrNew(Nm);
  RVUsed[I] := True; RVKey[I] := K; RVType[I] := Typ;
  If Size < 0 Then Size := 0;
  RVData[I] := KAlloc(Size + 2);
  FillMem(RVData[I], Size + 2, 0);
  If (Data <> 0) And (Size > 0) Then MoveMem(Data, RVData[I], Size);
  RVSize[I] := Size;
  RegSetK := 0;
End;

Procedure RegSetStr(Path, Nm, V : String);
Var K : LongInt;
Begin
  K := RegWalk(2, Path, True);
  V := V + #0;
  RegSetK(K, Nm, 1, LongInt(@V[1]), Length(V));
End;

Procedure RegDelTree(K : LongInt);
Var I : LongInt;
Begin
  For I := 0 To MaxRK - 1 Do
    If RKUsed[I] And (RKPar[I] = K) And (I <> K) Then RegDelTree(I);
  For I := 0 To MaxRV - 1 Do
    If RVUsed[I] And (RVKey[I] = K) Then
    Begin
      If RVData[I] <> 0 Then KFree(RVData[I]);
      RVUsed[I] := False;
    End;
  If K >= 6 Then RKUsed[K] := False;
End;

Procedure RegInit;
Var I : LongInt; S : String;
Begin
  For I := 0 To 5 Do
  Begin
    RKUsed[I] := True; RKPar[I] := -1; RKNameP[I] := 0;
  End;
  S := 'Software\Microsoft\Windows\CurrentVersion';
  RegSetStr(S, 'ProgramFilesDir', 'C:\Program Files');
  RegSetStr(S, 'CommonFilesDir', 'C:\Program Files\Common Files');
  RegSetStr(S, 'SystemRoot', 'C:\WINDOWS');
  RegSetStr(S, 'Version', 'Windows 95');
  RegSetStr(S, 'VersionNumber', '4.00.950');
  RegSetStr(S, 'ProductName', 'Pasdows 95');
  RegSetStr(S, 'RegisteredOwner', 'Pasdows');
  RegSetStr(S, 'RegisteredOrganization', '');
  RegSetStr(S, 'SourcePath', 'D:\');
  RegSetStr(S, 'DevicePath', 'C:\WINDOWS\INF');
  RegSetStr(S, 'MediaPath', 'C:\WINDOWS\MEDIA');
  RegWalk(2, S + '\App Paths', True);
  RegWalk(2, S + '\Uninstall', True);
  RegWalk(2, 'System\CurrentControlSet\Control', True);
  RegWalk(1, 'Software\Microsoft\Windows\CurrentVersion\Explorer', True);
  RegWalk(1, 'Control Panel\International', True);
  S := 'C:\Program Files' + #0;
  CreateDirectoryA(LongInt(@S[1]), 0);
  S := 'C:\Program Files\Common Files' + #0;
  CreateDirectoryA(LongInt(@S[1]), 0);
End;

Function RegOpenKeyA(K, Sub, PR : LongInt) : LongInt;
Var I : LongInt;
Begin
  RegOpenKeyA := 2;
  I := RegKeyOf(K);
  If (I >= 0) And (Sub <> 0) Then I := RegWalk(I, PStr(Sub), False);
  If I < 0 Then Exit;
  If PR <> 0 Then MemL[0:PR] := HKBase + I;
  RegOpenKeyA := 0;
End;

Function RegOpenKeyExA(K, Sub, Opt, Sam, PR : LongInt) : LongInt;
Begin
  RegOpenKeyExA := RegOpenKeyA(K, Sub, PR);
End;

Function RegCreateKeyExA(K, Sub, Res, Cls, Opt, Sam, Sec, PR, PDisp
  : LongInt) : LongInt;
Var I, J : LongInt;
Begin
  RegCreateKeyExA := 2;
  I := RegKeyOf(K);
  If (I >= 0) And (Sub <> 0) Then
  Begin
    J := RegWalk(I, PStr(Sub), False);
    If PDisp <> 0 Then MemL[0:PDisp] := 1 + Ord(J >= 0);
    I := RegWalk(I, PStr(Sub), True);
  End;
  If I < 0 Then Exit;
  If PR <> 0 Then MemL[0:PR] := HKBase + I;
  RegCreateKeyExA := 0;
End;

Function RegCreateKeyA(K, Sub, PR : LongInt) : LongInt;
Begin
  RegCreateKeyA := RegCreateKeyExA(K, Sub, 0, 0, 0, 0, 0, PR, 0);
End;

Function RegCloseKey(K : LongInt) : LongInt;
Begin
  RegCloseKey := 0;
End;

Function RegFlushKey(K : LongInt) : LongInt;
Begin
  RegFlushKey := 0;
End;

Function RegDeleteKeyA(K, Sub : LongInt) : LongInt;
Var I : LongInt;
Begin
  RegDeleteKeyA := 2;
  I := RegKeyOf(K);
  If (I >= 0) And (Sub <> 0) Then I := RegWalk(I, PStr(Sub), False);
  If I < 6 Then Exit;
  RegDelTree(I);
  RegDeleteKeyA := 0;
End;

Function RegSetValueExA(K, N, R, T, D, Sz : LongInt) : LongInt;
Var Nm : String;
Begin
  If N = 0 Then Nm := '' Else Nm := PStr(N);
  If (T = 1) Or (T = 2) Then
    If (Sz = 0) And (D <> 0) Then Sz := StrLenZ(D) + 1;
  RegSetValueExA := RegSetK(RegKeyOf(K), Nm, T, D, Sz);
End;

Function RegQueryValueExA(K, N, R, PT, PD, PN : LongInt) : LongInt;
Var I, V : LongInt; Nm : String;
Begin
  RegQueryValueExA := 2;
  I := RegKeyOf(K);
  If I < 0 Then Exit;
  If N = 0 Then Nm := '' Else Nm := PStr(N);
  V := RegVal(I, Nm);
  If V < 0 Then Exit;
  If PT <> 0 Then MemL[0:PT] := RVType[V];
  RegQueryValueExA := 0;
  If PN = 0 Then Exit;
  If PD <> 0 Then
  Begin
    If MemL[0:PN] < RVSize[V] Then RegQueryValueExA := 234
    Else MoveMem(RVData[V], PD, RVSize[V]);
  End;
  MemL[0:PN] := RVSize[V];
End;

Function RegSetValueA(K, Sub, T, D, Len : LongInt) : LongInt;
Var I : LongInt;
Begin
  RegSetValueA := 2;
  I := RegKeyOf(K);
  If (I >= 0) And (Sub <> 0) Then I := RegWalk(I, PStr(Sub), True);
  If (I < 0) Or (D = 0) Then Exit;
  RegSetValueA := RegSetK(I, '', 1, D, StrLenZ(D) + 1);
End;

Function RegQueryValueA(K, Sub, PD, PN : LongInt) : LongInt;
Var I, V, N : LongInt;
Begin
  RegQueryValueA := 2;
  I := RegKeyOf(K);
  If (I >= 0) And (Sub <> 0) Then I := RegWalk(I, PStr(Sub), False);
  If I < 0 Then Exit;
  V := RegVal(I, '');
  RegQueryValueA := 0;
  If V < 0 Then N := 1 Else N := RVSize[V];
  If (PD <> 0) And (PN <> 0) Then
  Begin
    If MemL[0:PN] < N Then RegQueryValueA := 234
    Else If V < 0 Then Mem[0:PD] := 0
    Else MoveMem(RVData[V], PD, N);
  End;
  If PN <> 0 Then MemL[0:PN] := N;
End;

Function RegChildN(K, N : LongInt) : LongInt;
Var I : LongInt;
Begin
  RegChildN := -1;
  For I := 0 To MaxRK - 1 Do
    If RKUsed[I] And (RKPar[I] = K) And (I <> K) Then
    Begin
      If N = 0 Then
      Begin
        RegChildN := I;
        Exit;
      End;
      Dec(N);
    End;
End;

Function RegEnumKeyExA(K, N, Buf, PLen, R, Cls, PCls, PFt : LongInt)
  : LongInt;
Var I : LongInt;
Begin
  RegEnumKeyExA := 259;
  I := RegKeyOf(K);
  If I < 0 Then Exit;
  I := RegChildN(I, N);
  If I < 0 Then Exit;
  If PLen <> 0 Then
  Begin
    PutPStr(Buf, RKName(I), MemL[0:PLen]);
    MemL[0:PLen] := Length(RKName(I));
  End;
  RegEnumKeyExA := 0;
End;

Function RegEnumKeyA(K, N, Buf, Len : LongInt) : LongInt;
Var L : LongInt;
Begin
  L := Len;
  RegEnumKeyA := RegEnumKeyExA(K, N, Buf, LongInt(@L), 0, 0, 0, 0);
End;

Function RegEnumValueA(K, N, NBuf, PNLen, R, PT, PD, PDLen : LongInt)
  : LongInt;
Var I, V : LongInt;
Begin
  RegEnumValueA := 259;
  I := RegKeyOf(K);
  If I < 0 Then Exit;
  For V := 0 To MaxRV - 1 Do
    If RVUsed[V] And (RVKey[V] = I) Then
    Begin
      If N = 0 Then
      Begin
        If PNLen <> 0 Then
        Begin
          PutPStr(NBuf, RVName(V), MemL[0:PNLen]);
          MemL[0:PNLen] := Length(RVName(V));
        End;
        If PT <> 0 Then MemL[0:PT] := RVType[V];
        If (PD <> 0) And (PDLen <> 0) Then
          MoveMem(RVData[V], PD, Min(RVSize[V], MemL[0:PDLen]));
        If PDLen <> 0 Then MemL[0:PDLen] := RVSize[V];
        RegEnumValueA := 0;
        Exit;
      End;
      Dec(N);
    End;
End;

Function RegDeleteValueA(K, N : LongInt) : LongInt;
Var I, V : LongInt; Nm : String;
Begin
  RegDeleteValueA := 2;
  I := RegKeyOf(K);
  If I < 0 Then Exit;
  If N = 0 Then Nm := '' Else Nm := PStr(N);
  V := RegVal(I, Nm);
  If V < 0 Then Exit;
  KFree(RVData[V]);
  RVUsed[V] := False;
  RegDeleteValueA := 0;
End;

Function RegQueryInfoKeyA(K, Cls, PCls, R, PSub, PMaxSub, PMaxCls, PVal,
  PMaxVN, PMaxVL, PSec, PFt : LongInt) : LongInt;
Var I, J, NS, NV, MS, MN, ML : LongInt;
Begin
  RegQueryInfoKeyA := 2;
  I := RegKeyOf(K);
  If I < 0 Then Exit;
  NS := 0; NV := 0; MS := 0; MN := 0; ML := 0;
  For J := 0 To MaxRK - 1 Do
    If RKUsed[J] And (RKPar[J] = I) And (J <> I) Then
    Begin
      Inc(NS);
      MS := Max(MS, Length(RKName(J)));
    End;
  For J := 0 To MaxRV - 1 Do
    If RVUsed[J] And (RVKey[J] = I) Then
    Begin
      Inc(NV);
      MN := Max(MN, Length(RVName(J)));
      ML := Max(ML, RVSize[J]);
    End;
  If PCls <> 0 Then MemL[0:PCls] := 0;
  If PSub <> 0 Then MemL[0:PSub] := NS;
  If PMaxSub <> 0 Then MemL[0:PMaxSub] := MS;
  If PMaxCls <> 0 Then MemL[0:PMaxCls] := 0;
  If PVal <> 0 Then MemL[0:PVal] := NV;
  If PMaxVN <> 0 Then MemL[0:PMaxVN] := MN;
  If PMaxVL <> 0 Then MemL[0:PMaxVL] := ML;
  If PSec <> 0 Then MemL[0:PSec] := 0;
  If PFt <> 0 Then
  Begin
    MemL[0:PFt] := 0; MemL[0:PFt + 4] := 0;
  End;
  RegQueryInfoKeyA := 0;
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
  SysDllN = 20;
  SysDlls : Array[0..SysDllN - 1] Of String[12] = ('KERNEL32.DLL',
    'USER32.DLL', 'GDI32.DLL', 'WINMM.DLL', 'COMDLG32.DLL', 'SHELL32.DLL',
    'OLE32.DLL', 'MSVFW32.DLL', 'ADVAPI32.DLL', 'VERSION.DLL',
    'COMCTL32.DLL', 'OLEAUT32.DLL', 'MSVCRT.DLL', 'WSOCK32.DLL',
    'DDRAW.DLL', 'DSOUND.DLL', 'DINPUT.DLL', 'DSETUP.DLL', 'WS2_32.DLL',
    'ICMP.DLL');

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
Var F, D, R : LongInt; S : String;
Begin
  If TraceCount < 60000 Then
  Begin
    Inc(TraceCount);
    asm
      mov eax,ebp
      mov F,eax
    end;
    S := '> ' + PStr(Name) + ' @' + HexStr(MemL[0:F + 44], 8);
    S := S + ' ' + HexStr(MemL[0:F + 48], 8) + ' ' + HexStr(MemL[0:F + 52], 8);
    S := S + ' ' + HexStr(MemL[0:F + 56], 8) + ' ' + HexStr(MemL[0:F + 60], 8);
    { arguments qui pointent sur du texte }
    For D := 0 To 3 Do
    Begin
      R := MemL[0:F + 48 + D * 4];
      If (R >= $10000) And (R < MemTop) Then
        If (Mem[0:R] >= 32) And (Mem[0:R] < 127) And
           ((Mem[0:R + 1] = 0) Or ((Mem[0:R + 1] >= 32) And
           (Mem[0:R + 1] < 127))) Then
          S := S + ' "' + Copy(PStr(R), 1, 50) + '"';
    End;
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
  TraceSkip := TraceSkip + 'GETDEVICECAPS CHARNEXTA CHARPREVA ISDBCSLEADBYTE ';
  TraceSkip := TraceSkip + 'LSTRLENA LSTRCMPA ';
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
  For I := 0 To SysDllN - 1 Do
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

Function IsWsDll(Dll : String) : Boolean; Forward;
Function WsOrdName(N : LongInt) : String; Forward;
Procedure NetAppExit; Forward;

Function ResolveImport(Dll, Name : String; Ordinal : LongInt) : LongInt;
Var M, A : LongInt; Nm : String;
Begin
  A := 0;
  { Winsock : fonctions WS_nom du noyau (par nom ou par ordinal) }
  If IsWsDll(Dll) Then
  Begin
    If Name = '' Then Name := WsOrdName(Ordinal);
    If Name <> '' Then A := KernelExport('WS_' + Name);
  End;
  { importations par ordinal des DLL systeme connues }
  If (Name = '') And (UpStr(BaseName(Dll)) = 'MSVFW32.DLL') And
     (Ordinal = 2) Then Name := 'VideoForWindowsVersion';
  If (A = 0) And Not IsSysDll(Dll) Then
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
  If Not IsDll And (Base >= $00400000) And (Base + ImgSize <= ExeTop) Then
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
  For I := 0 To SysDllN - 1 Do
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
    Else If (H >= HDllBase) And (H < HDllBase + SysDllN * $10000) Then
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
Var M, R : LongInt; Nm : String; Ws : Boolean;
Begin
  GetProcAddress := 0;
  M := ModOfBase(H);
  Ws := (M < 0) And (H >= HDllBase) And (H < HDllBase + SysDllN * $10000);
  If Ws Then Ws := IsWsDll(SysDlls[(H - HDllBase) Div $10000]);
  If (P >= 0) And (P < $10000) Then
  Begin
    If M >= 0 Then GetProcAddress := ModuleExport(M, '', P)
    Else If Ws And (WsOrdName(P) <> '') Then
      GetProcAddress := KernelExport('WS_' + WsOrdName(P));
    Exit;
  End;
  Nm := PStr(P);
  R := 0;
  If Ws Then R := KernelExport('WS_' + Nm);
  If R = 0 Then
  Begin
    If M >= 0 Then R := ModuleExport(M, Nm, 0)
    Else R := KernelExport(Nm);
  End;
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
  NetAppExit;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And (Wnds[I].Thread > 0) And
       Threads[Wnds[I].Thread].IsApp And Not ThrW16[Wnds[I].Thread] Then
    Begin
      Wnds[I].Proc := 0;
      Wnds[I].IKind := ikStatic;
      DestroyW(I);
    End;
  For I := 1 To MaxThread - 1 Do
    If Threads[I].Used And Threads[I].IsApp And (I <> CurT) And
       Not ThrW16[I] Then
      Threads[I].State := tsDead;
  For I := 0 To MaxTimer - 1 Do WTimers[I].Used := False;
  For I := 0 To MaxMMTimer - 1 Do MMTimers[I].Used := False;
  For I := 0 To MaxKObj - 1 Do
    If KObjs[I].Used And (KObjs[I].Kind In [koFile, koFind]) And
       (KObjOwner[I] = 1) Then
      KObjs[I].Used := False;
  For I := 0 To MaxDC - 1 Do
    If Dcs[I].Used And (Gdis[Dcs[I].Gdi].Owner = 1) Then DcFree(I);
  For I := 0 To MaxGdi - 1 Do
    If Gdis[I].Used And (Gdis[I].Owner = 1) Then Gdis[I].Used := False;
  For I := 0 To MaxVBlk - 1 Do VBlks[I].Used := False;
  For I := 0 To MaxMod - 1 Do Mods[I].Used := False;
  For I := 0 To MaxClass - 1 Do
    If Classes[I].Used And (Classes[I].IKind = ikNone) And
       ((Classes[I].Inst <= 0) Or (Classes[I].Inst > $FFFF)) Then
      Classes[I].Used := False;
  KFreeOwner(1);
  StubArea := 0;
  HeapOwner := 0;
  AppRunning := False;
  AppBase := 0;
  DDShow := False;
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
Function IsNeFile(Path : String) : Boolean; Forward;
Function RunNe(Path, Args : String; Show : LongInt) : Boolean; Forward;

Function RunExe(Path, Args : String) : Boolean;
Var M, T, Sub : LongInt; S : String;
Begin
  RunExe := False;
  { programme Windows 3.x (NE) : sous-systeme Win16 }
  S := FindModuleFile(Path);
  If (S <> '') And IsNeFile(S) Then
  Begin
    KLog('Lancement de ' + S + ' (Win16)');
    RunExe := RunNe(S, Args, 1);
    Exit;
  End;
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

{ ==================================================================== }
{ Partie 12 bis - Complements Win32 pour les installateurs (ACME)      }
{ ==================================================================== }

Const
  koMapping = 9;
  MaxView = 32;

Var
  ViewAddr, ViewMap, ViewOfs, ViewSize : Array[0..MaxView - 1] Of LongInt;
  DdeStr : Array[0..63] Of String[63];
  DdeData : Array[0..15] Of LongInt;

{ ------------------------------- KERNEL32 ------------------------- }

Procedure RtlMoveMemory(D, S, N : LongInt);
Begin
  MoveMem(S, D, N);
End;

Procedure RtlZeroMemory(D, N : LongInt);
Begin
  FillMem(D, N, 0);
End;

Procedure RtlFillMemory(D, N, V : LongInt);
Begin
  FillMem(D, N, V And $FF);
End;

Function OpenMutexA(Acc, Inh, Name : LongInt) : LongInt;
Var I : LongInt; S : String;
Begin
  OpenMutexA := 0;
  If Name = 0 Then Exit;
  S := UpStr(PStr(Name));
  For I := 0 To MaxKObj - 1 Do
    If KObjs[I].Used And (KObjs[I].Kind = koMutex) And
       (KObjs[I].Name = S) Then
    Begin
      OpenMutexA := KHandle(I);
      Exit;
    End;
  SetErr(ErrFileNotFound);
End;

Function GetShortPathNameA(PLong, PShort, N : LongInt) : LongInt;
Var S : String;
Begin
  S := PStr(PLong);
  If (PShort <> 0) And (N > Length(S)) Then PutPStr(PShort, S, N);
  GetShortPathNameA := Length(S);
End;

Function GetLogicalDriveStringsA(N, Buf : LongInt) : LongInt;
Var M, I, K : LongInt;
Begin
  { X:\<0> pour chaque lecteur, puis <0> }
  M := GetLogicalDrives;
  K := 0;
  For I := 0 To 25 Do
    If (M And (1 Shl I)) <> 0 Then K := K + 4;
  GetLogicalDriveStringsA := K;
  If N < K + 1 Then Exit;
  K := 0;
  For I := 0 To 25 Do
    If (M And (1 Shl I)) <> 0 Then
    Begin
      Mem[0:Buf + K] := 65 + I; Mem[0:Buf + K + 1] := 58;
      Mem[0:Buf + K + 2] := 92; Mem[0:Buf + K + 3] := 0;
      K := K + 4;
    End;
  Mem[0:Buf + K] := 0;
End;

Function MoveFileExA(PSrc, PDst, Flags : LongInt) : LongInt;
Begin
  MoveFileExA := 1;
  { suppression au redemarrage : sans objet }
  If PDst = 0 Then Exit;
  If ((Flags And 1) <> 0) And (GetFileAttributesA(PDst) <> -1) Then
    DeleteFileA(PDst);
  MoveFileExA := MoveFileA(PSrc, PDst);
End;

Function GetTempFileNameA(PPath, PPre, Uniq, Buf : LongInt) : LongInt;
Var S, P, Pre : String; N, H : LongInt;
Begin
  P := PStr(PPath);
  If (P <> '') And (P[Length(P)] <> '\') Then P := P + '\';
  Pre := Copy(PStr(PPre), 1, 3);
  N := Uniq And $FFFF;
  If N = 0 Then N := (Ticks And $FFF) + 1;
  Repeat
    S := P + Pre + HexStr(N, 4) + '.TMP';
    If Uniq <> 0 Then Break;
    PutPStr(Buf, S, 260);
    If GetFileAttributesA(Buf) = -1 Then
    Begin
      H := KOpenFile(S, True, 2);
      If H <> INVALID_HANDLE Then CloseHandle(H);
      Break;
    End;
    N := (N + 1) And $FFFF;
  Until False;
  PutPStr(Buf, S, 260);
  GetTempFileNameA := N;
End;

Function SearchPathA(PPath, PFile, PExt, N, Buf, PPart : LongInt)
  : LongInt;
Var F, S, D : String; K : LongInt;
Begin
  SearchPathA := 0;
  F := PStr(PFile);
  If (PExt <> 0) And (Pos('.', BaseName(F)) = 0) Then F := F + PStr(PExt);
  For K := 0 To 5 Do
  Begin
    Case K Of
      0 : If PPath <> 0 Then D := PStr(PPath) Else D := ParentDir(AppPath);
      1 : D := CurDirS;
      2 : D := 'C:\WINDOWS\SYSTEM';
      3 : D := 'C:\WINDOWS';
      4 : D := 'D:';
    Else
      D := '';
    End;
    If (Pos('\', F) > 0) Or (Pos(':', F) > 0) Then S := FullPath(F)
    Else If D = '' Then Continue
    Else S := FullPath(D + '\' + F);
    PutPStr(Buf, S, N);
    If GetFileAttributesA(Buf) <> -1 Then
    Begin
      If PPart <> 0 Then
        MemL[0:PPart] := Buf + Length(S) - Length(BaseName(S));
      SearchPathA := Length(S);
      Exit;
    End;
    If (Pos('\', F) > 0) Or (Pos(':', F) > 0) Then Break;
  End;
  If N > 0 Then Mem[0:Buf] := 0;
  SetErr(ErrFileNotFound);
End;

Function SystemTimeToFileTime(St, Ft : LongInt) : LongInt;
Var Dos : LongInt;
Begin
  Dos := ((MemW[0:St] - 1980) Shl 25) Or (MemW[0:St + 2] Shl 21) Or
         (MemW[0:St + 6] Shl 16) Or (MemW[0:St + 8] Shl 11) Or
         (MemW[0:St + 10] Shl 5) Or (MemW[0:St + 12] Div 2);
  DosToFileTime(Dos, Ft);
  SystemTimeToFileTime := 1;
End;

{ Valeurs regionales courantes (francais ou anglais) }
Function GetLocaleInfoA(Lcid, Typ, Buf, N : LongInt) : LongInt;
Var S : String;
Begin
  Case Typ And $FFFF Of
    1 : S := '040C';
    2, 4 : S := 'Francais';
    3 : S := 'FRA';
    5, 6, 7 : S := 'France';
    8 : S := '33';
    $B : S := '850';
    $C : S := ';';
    $E : S := ',';
    $F : S := ' ';
    $14 : S := 'F';
    $15 : S := 'FRF';
    $1D : S := '/';
    $1E : S := ':';
    $1F : S := 'dd/MM/yy';
    $20 : S := 'dddd d MMMM yyyy';
    $21 : S := '1';
    $23 : S := '1';
    $1004 : S := '1252';
    $5A : S := 'FR';
  Else
    S := '0';
  End;
  If Language = _English Then
    Case Typ And $FFFF Of
      1 : S := '0409';
      2, 4 : S := 'English';
      3 : S := 'ENU';
      5, 6, 7 : S := 'United States';
      8 : S := '1';
      $B : S := '437';
      $C, $E : S := ',';
      $D : S := '.';
    End;
  If (Buf <> 0) And (N > 0) Then PutPStr(Buf, S, N);
  GetLocaleInfoA := Length(S) + 1;
End;

{ Projection de fichiers : la vue est une copie du fichier, recrite a
  UnmapViewOfFile / FlushViewOfFile si elle est modifiable }
Function CreateFileMappingA(HFile, Sec, Prot, SzHi, SzLo, Name : LongInt)
  : LongInt;
Var I, Sz : LongInt;
Begin
  CreateFileMappingA := 0;
  I := KObjNew(koMapping);
  If I < 0 Then Exit;
  Sz := SzLo;
  If (Sz = 0) And (HFile <> -1) Then Sz := GetFileSize(HFile, 0);
  KObjs[I].F1 := HFile;
  KObjs[I].F2 := Sz;
  KObjs[I].F3 := Prot;
  CreateFileMappingA := KHandle(I);
End;

Function ViewFlush(V : LongInt) : LongInt;
Var I, H, N : LongInt;
Begin
  ViewFlush := 1;
  I := KObjOf(ViewMap[V], koMapping);
  If I < 0 Then Exit;
  H := KObjs[I].F1;
  If (H = -1) Or ((KObjs[I].F3 And 4) = 0) Then Exit;
  SetFilePointer(H, ViewOfs[V], 0, 0);
  N := KWriteFile(H, ViewAddr[V], ViewSize[V]);
End;

Function MapViewOfFile(HMap, Acc, OfsHi, OfsLo, N : LongInt) : LongInt;
Var I, V, A, Got, K : LongInt;
Begin
  MapViewOfFile := 0;
  I := KObjOf(HMap, koMapping);
  If I < 0 Then Exit;
  V := -1;
  For K := MaxView - 1 DownTo 0 Do
    If ViewAddr[K] = 0 Then V := K;
  If V < 0 Then Exit;
  If (N = 0) Or (OfsLo + N > KObjs[I].F2) Then N := KObjs[I].F2 - OfsLo;
  If N <= 0 Then N := 1;
  A := KAlloc(N + 4096);
  If A = 0 Then Exit;
  FillMem(A, N, 0);
  If KObjs[I].F1 <> -1 Then
  Begin
    SetFilePointer(KObjs[I].F1, OfsLo, 0, 0);
    KReadFile(KObjs[I].F1, A, N, Got);
  End;
  ViewAddr[V] := A; ViewMap[V] := HMap; ViewOfs[V] := OfsLo;
  ViewSize[V] := N;
  MapViewOfFile := A;
End;

Function FlushViewOfFile(A, N : LongInt) : LongInt;
Var V : LongInt;
Begin
  FlushViewOfFile := 1;
  For V := 0 To MaxView - 1 Do
    If (ViewAddr[V] <> 0) And (A >= ViewAddr[V]) And
       (A < ViewAddr[V] + ViewSize[V]) Then ViewFlush(V);
End;

Function UnmapViewOfFile(A : LongInt) : LongInt;
Var V : LongInt;
Begin
  UnmapViewOfFile := 0;
  For V := 0 To MaxView - 1 Do
    If ViewAddr[V] = A Then
    Begin
      ViewFlush(V);
      KFree(A);
      ViewAddr[V] := 0;
      UnmapViewOfFile := 1;
    End;
End;

{ --------------------------------- GDI32 --------------------------- }

Function CreateScalableFontResourceA(H, PRes, PFont, PPath : LongInt)
  : LongInt;
Begin
  CreateScalableFontResourceA := 0;
End;

{ --------------------------------- USER32 -------------------------- }

Function CreateCaret(H, Bmp, W, Ht : LongInt) : LongInt;
Begin
  CreateCaret := 1;
End;

Function DestroyCaret : LongInt;
Begin
  DestroyCaret := 1;
End;

Function SetCaretPos(X, Y : LongInt) : LongInt;
Begin
  SetCaretPos := 1;
End;

Function ShowCaret(H : LongInt) : LongInt;
Begin
  ShowCaret := 1;
End;

Function HideCaret(H : LongInt) : LongInt;
Begin
  HideCaret := 1;
End;

Function ExcludeUpdateRgn(Hdc, H : LongInt) : LongInt;
Begin
  ExcludeUpdateRgn := 2;
End;

Function GetLastActivePopup(H : LongInt) : LongInt;
Begin
  GetLastActivePopup := H;
End;

{ DDE : un Gestionnaire de programmes (PROGMAN) minimal accepte les
  commandes [CreateGroup(...)], [AddItem(...)]... et les journalise }
Function DdeInitializeA(PId, Cb, Cmd, Res : LongInt) : LongInt;
Begin
  If PId <> 0 Then MemL[0:PId] := 1;
  DdeInitializeA := 0;
End;

Function DdeUninitialize(Id : LongInt) : LongInt;
Begin
  DdeUninitialize := 1;
End;

Function DdeCreateStringHandleA(Id, P, Cp : LongInt) : LongInt;
Var I : LongInt;
Begin
  DdeCreateStringHandleA := 0;
  For I := 1 To 63 Do
    If DdeStr[I] = '' Then
    Begin
      DdeStr[I] := Copy(PStr(P), 1, 63);
      If DdeStr[I] = '' Then DdeStr[I] := ' ';
      DdeCreateStringHandleA := I;
      Exit;
    End;
End;

Function DdeFreeStringHandle(Id, H : LongInt) : LongInt;
Begin
  If (H > 0) And (H < 64) Then DdeStr[H] := '';
  DdeFreeStringHandle := 1;
End;

Function DdeConnect(Id, HSrv, HTop, PCC : LongInt) : LongInt;
Begin
  DdeConnect := 0;
  If (HSrv > 0) And (HSrv < 64) Then
  Begin
    KLog('DDE : connexion a ' + DdeStr[HSrv]);
    If UpStr(DdeStr[HSrv]) = 'PROGMAN' Then DdeConnect := $5150;
  End;
End;

Function DdeDisconnect(H : LongInt) : LongInt;
Begin
  DdeDisconnect := 1;
End;

Function DdeClientTransaction(PData, Cb, HConv, HItem, Fmt, Typ, Tmo,
  PRes : LongInt) : LongInt;
Var S : String; A : LongInt;
Begin
  DdeClientTransaction := 0;
  If PRes <> 0 Then MemL[0:PRes] := 0;
  If HConv <> $5150 Then Exit;
  Case Typ And $FF Of
    $50 :
    Begin
      { XTYP_EXECUTE }
      KLog('DDE PROGMAN : ' + Copy(PStr(PData), 1, 200));
      DdeClientTransaction := 1;
    End;
    $B0 :
    Begin
      { XTYP_REQUEST (liste des groupes...) : vide }
      A := KAlloc(16);
      Mem[0:A] := 0;
      DdeClientTransaction := A;
    End;
  Else
    DdeClientTransaction := 1;
  End;
End;

Function DdeAccessData(H, PSz : LongInt) : LongInt;
Begin
  If PSz <> 0 Then MemL[0:PSz] := 1;
  DdeAccessData := H;
End;

Function DdeUnaccessData(H : LongInt) : LongInt;
Begin
  DdeUnaccessData := 1;
End;

Function DdeFreeDataHandle(H : LongInt) : LongInt;
Begin
  DdeFreeDataHandle := 1;
End;

Function DdeGetLastError(Id : LongInt) : LongInt;
Begin
  DdeGetLastError := 0;
End;

{ ------------------------------ VERSION ---------------------------- }
{ Pas d'informations de version : les fichiers sont copies d'apres
  leur date (comportement documente pour les fichiers sans version) }

Function GetFileVersionInfoSizeA(PFile, PH : LongInt) : LongInt;
Begin
  If PH <> 0 Then MemL[0:PH] := 0;
  SetErr(1812);
  GetFileVersionInfoSizeA := 0;
End;

Function GetFileVersionInfoA(PFile, H, N, Buf : LongInt) : LongInt;
Begin
  GetFileVersionInfoA := 0;
End;

Function VerQueryValueA(Blk, PSub, PPtr, PLen : LongInt) : LongInt;
Begin
  VerQueryValueA := 0;
End;

Function VerFindFileA(Flags, PFile, PWin, PApp, PCur, PCurLen, PDst,
  PDstLen : LongInt) : LongInt;
Begin
  If (PCur <> 0) And (PCurLen <> 0) And (MemL[0:PCurLen] > 0) Then
    Mem[0:PCur] := 0;
  If PCurLen <> 0 Then MemL[0:PCurLen] := 1;
  If (PDst <> 0) And (PDstLen <> 0) Then
  Begin
    If PApp <> 0 Then PutPStr(PDst, PStr(PApp), MemL[0:PDstLen])
    Else Mem[0:PDst] := 0;
    MemL[0:PDstLen] := StrLenZ(PDst) + 1;
  End;
  VerFindFileA := 0;
End;

Function VerInstallFileA(Flags, PSrc, PDst, PSrcDir, PDstDir, PCurDir,
  PTmp, PTmpLen : LongInt) : LongInt;
Var A, B : String;
Begin
  A := PStr(PSrcDir) + '\' + PStr(PSrc) + #0;
  B := PStr(PDstDir) + '\' + PStr(PDst) + #0;
  If CopyFileA(LongInt(@A[1]), LongInt(@B[1]), 0) <> 0 Then
    VerInstallFileA := 0
  Else VerInstallFileA := $8000;
End;

Function CopyFileA(PSrc, PDst, FailExist : LongInt) : LongInt;
Var HS, HD, B, N : LongInt;
Begin
  CopyFileA := 0;
  If (FailExist <> 0) And (GetFileAttributesA(PDst) <> -1) Then
  Begin
    SetErr(80);
    Exit;
  End;
  HS := KOpenFile(PStr(PSrc), False, 3);
  If HS = INVALID_HANDLE Then Exit;
  HD := KOpenFile(PStr(PDst), True, 2);
  If HD = INVALID_HANDLE Then
  Begin
    CloseHandle(HS);
    Exit;
  End;
  B := KAlloc(16384);
  Repeat
    If Not KReadFile(HS, B, 16384, N) Then N := 0;
    If N > 0 Then KWriteFile(HD, B, N);
  Until N <= 0;
  KFree(B);
  CloseHandle(HS);
  CloseHandle(HD);
  CopyFileA := 1;
End;

{ -------------------------------- LZ32 ----------------------------- }

Function LZOpenFileA(PName, POf, Style : LongInt) : LongInt;
Begin
  LZOpenFileA := OpenFile(PName, POf, Style);
End;

Function LZClose(H : LongInt) : LongInt;
Begin
  CloseHandle(H);
  LZClose := 0;
End;

Function LZCopy(HSrc, HDst : LongInt) : LongInt;
Var B, N, T : LongInt;
Begin
  B := KAlloc(16384);
  T := 0;
  Repeat
    If Not KReadFile(HSrc, B, 16384, N) Then N := 0;
    If N > 0 Then
    Begin
      KWriteFile(HDst, B, N);
      T := T + N;
    End;
  Until N <= 0;
  KFree(B);
  LZCopy := T;
End;

{ -------------------------------- MPR ------------------------------ }
{ Pas de reseau }

Function WNetGetConnectionA(PLocal, PRemote, PLen : LongInt) : LongInt;
Begin
  WNetGetConnectionA := 2250;
End;

Function WNetAddConnectionA(PRemote, PPass, PLocal : LongInt) : LongInt;
Begin
  WNetAddConnectionA := 1222;
End;

Function WNetAddConnection2A(PRes, PPass, PUser, Flags : LongInt) : LongInt;
Begin
  WNetAddConnection2A := 1222;
End;

Function WNetCancelConnectionA(PName, Force : LongInt) : LongInt;
Begin
  WNetCancelConnectionA := 2250;
End;

Function WNetCancelConnection2A(PName, Flags, Force : LongInt) : LongInt;
Begin
  WNetCancelConnection2A := 2250;
End;

Function WNetConnectionDialog(H, Typ : LongInt) : LongInt;
Begin
  WNetConnectionDialog := 1222;
End;

Function WNetGetLastErrorA(PErr, PBuf, NBuf, PName, NName : LongInt)
  : LongInt;
Begin
  If PErr <> 0 Then MemL[0:PErr] := 0;
  WNetGetLastErrorA := 0;
End;

{ ----------------------- Unicode et parametres regionaux ------------ }

Function GetEnvironmentStringsW : LongInt;
Var P, N, W, I : LongInt;
Begin
  P := GetEnvironmentStringsA;
  N := 0;
  While (MemW[0:P + N] <> 0) And (N < 8000) Do Inc(N);
  W := KAlloc((N + 2) * 2);
  For I := 0 To N + 1 Do MemW[0:W + I * 2] := Mem[0:P + I];
  GetEnvironmentStringsW := W;
End;

Function FreeEnvironmentStringsW(P : LongInt) : LongInt;
Begin
  FreeEnvironmentStringsW := 1;
End;

Function GetLocaleInfoW(Lcid, Typ, Buf, N : LongInt) : LongInt;
Var T, R, I : LongInt;
Begin
  T := KAlloc(256);
  R := GetLocaleInfoA(Lcid, Typ, T, 256);
  If (Buf <> 0) And (N > 0) Then
    For I := 0 To Min(R, N) - 1 Do MemW[0:Buf + I * 2] := Mem[0:T + I];
  KFree(T);
  GetLocaleInfoW := R;
End;

{ CT_CTYPE1 : 1 majuscule, 2 minuscule, 4 chiffre, 8 espace,
  10h ponctuation, 20h controle, 80h hexadecimal, 100h lettre }
Function CharType1(C : LongInt) : LongInt;
Var T : LongInt;
Begin
  T := 0;
  If (C >= 65) And (C <= 90) Then T := $101;
  If (C >= 97) And (C <= 122) Then T := $102;
  If (C >= 192) And (C <= 255) Then T := $100;
  If (C >= 48) And (C <= 57) Then T := $84;
  If ((C >= 65) And (C <= 70)) Or ((C >= 97) And (C <= 102)) Then
    T := T Or $80;
  If (C = 32) Or ((C >= 9) And (C <= 13)) Then T := T Or 8;
  If C = 32 Then T := T Or $40;
  If C < 32 Then T := T Or $20;
  If ((C >= 33) And (C <= 47)) Or ((C >= 58) And (C <= 64)) Or
     ((C >= 91) And (C <= 96)) Or ((C >= 123) And (C <= 126)) Then
    T := T Or $10;
  CharType1 := T;
End;

Function GetStringTypeA(Lcid, Info, Src, N, PType : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N < 0 Then N := StrLenZ(Src) + 1;
  For I := 0 To N - 1 Do
    If Info = 1 Then MemW[0:PType + I * 2] := CharType1(Mem[0:Src + I])
    Else MemW[0:PType + I * 2] := 0;
  GetStringTypeA := 1;
End;

Function GetStringTypeW(Info, Src, N, PType : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N < 0 Then
  Begin
    N := 0;
    While MemW[0:Src + N * 2] <> 0 Do Inc(N);
    Inc(N);
  End;
  For I := 0 To N - 1 Do
    If Info = 1 Then
      MemW[0:PType + I * 2] := CharType1(MemW[0:Src + I * 2] And $FF)
    Else MemW[0:PType + I * 2] := 0;
  GetStringTypeW := 1;
End;

Function MapCaseC(C, Flags : LongInt) : LongInt;
Begin
  If ((Flags And $200) <> 0) And (C >= 97) And (C <= 122) Then C := C - 32;
  If ((Flags And $100) <> 0) And (C >= 65) And (C <= 90) Then C := C + 32;
  MapCaseC := C;
End;

Function LCMapStringA(Lcid, Flags, Src, N, Dst, DN : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N < 0 Then N := StrLenZ(Src) + 1;
  LCMapStringA := N;
  If DN = 0 Then Exit;
  If N > DN Then N := DN;
  For I := 0 To N - 1 Do Mem[0:Dst + I] := MapCaseC(Mem[0:Src + I], Flags);
  LCMapStringA := N;
End;

Function LCMapStringW(Lcid, Flags, Src, N, Dst, DN : LongInt) : LongInt;
Var I : LongInt;
Begin
  If N < 0 Then
  Begin
    N := 0;
    While MemW[0:Src + N * 2] <> 0 Do Inc(N);
    Inc(N);
  End;
  LCMapStringW := N;
  If DN = 0 Then Exit;
  If N > DN Then N := DN;
  For I := 0 To N - 1 Do
    MemW[0:Dst + I * 2] := MapCaseC(MemW[0:Src + I * 2], Flags);
  LCMapStringW := N;
End;

{ 1 inferieur, 2 egal, 3 superieur ; NORM_IGNORECASE (1) }
Function CmpChars(A, B, NA, NB, Flags, W : LongInt) : LongInt;
Var I, CA, CB : LongInt;
Begin
  I := 0;
  Repeat
    If I < NA Then
    Begin
      If W = 2 Then CA := MemW[0:A + I * 2] Else CA := Mem[0:A + I];
    End
    Else CA := 0;
    If I < NB Then
    Begin
      If W = 2 Then CB := MemW[0:B + I * 2] Else CB := Mem[0:B + I];
    End
    Else CB := 0;
    If (Flags And 1) <> 0 Then
    Begin
      CA := MapCaseC(CA, $200); CB := MapCaseC(CB, $200);
    End;
    If CA < CB Then
    Begin
      CmpChars := 1;
      Exit;
    End;
    If CA > CB Then
    Begin
      CmpChars := 3;
      Exit;
    End;
    Inc(I);
  Until (I >= NA) And (I >= NB);
  CmpChars := 2;
End;

Function CompareStringA(Lcid, Flags, A, NA, B, NB : LongInt) : LongInt;
Begin
  If NA < 0 Then NA := StrLenZ(A);
  If NB < 0 Then NB := StrLenZ(B);
  CompareStringA := CmpChars(A, B, NA, NB, Flags, 1);
End;

Function CompareStringW(Lcid, Flags, A, NA, B, NB : LongInt) : LongInt;
Begin
  If NA < 0 Then
  Begin
    NA := 0;
    While MemW[0:A + NA * 2] <> 0 Do Inc(NA);
  End;
  If NB < 0 Then
  Begin
    NB := 0;
    While MemW[0:B + NB * 2] <> 0 Do Inc(NB);
  End;
  CompareStringW := CmpChars(A, B, NA, NB, Flags, 2);
End;

{ ----------------------------- Divers ------------------------------- }

Function GetMapMode(Hdc : LongInt) : LongInt;
Begin
  GetMapMode := 1;
End;

Function SetMapMode(Hdc, M : LongInt) : LongInt;
Begin
  SetMapMode := 1;
End;

Function MessageBoxIndirectA(P : LongInt) : LongInt;
Begin
  MessageBoxIndirectA := MessageBoxA(MemL[0:P + 4], MemL[0:P + 12],
                                     MemL[0:P + 16], MemL[0:P + 20]);
End;

Function SetFileTime(H, PC, PA, PW : LongInt) : LongInt;
Begin
  SetFileTime := 1;
End;

Function SetHandleCount(N : LongInt) : LongInt;
Begin
  SetHandleCount := N;
End;

Function DisableThreadLibraryCalls(H : LongInt) : LongInt;
Begin
  DisableThreadLibraryCalls := 1;
End;

Function ExtEscape(Hdc, Esc, NIn, PIn, NOut, POut : LongInt) : LongInt;
Begin
  ExtEscape := 0;
End;

{ Thunks plats 16/32 bits (DSETUP16.DLL...) : non pris en charge, la
  connexion echoue proprement }
Function ThunkConnect32(P1, P2, P3, P4, P5, P6 : LongInt) : LongInt;
Begin
  ThunkConnect32 := 0;
End;

Function SMapLS_IP_EBP_12 : LongInt;
Begin
  SMapLS_IP_EBP_12 := 0;
End;

Function SMapLS_IP_EBP_16 : LongInt;
Begin
  SMapLS_IP_EBP_16 := 0;
End;

Function SMapLS_IP_EBP_20 : LongInt;
Begin
  SMapLS_IP_EBP_20 := 0;
End;

Function SMapLS_IP_EBP_24 : LongInt;
Begin
  SMapLS_IP_EBP_24 := 0;
End;

Function SUnMapLS_IP_EBP_12 : LongInt;
Begin
  SUnMapLS_IP_EBP_12 := 0;
End;

Function SUnMapLS_IP_EBP_16 : LongInt;
Begin
  SUnMapLS_IP_EBP_16 := 0;
End;

Function SUnMapLS_IP_EBP_20 : LongInt;
Begin
  SUnMapLS_IP_EBP_20 := 0;
End;

Function SUnMapLS_IP_EBP_24 : LongInt;
Begin
  SUnMapLS_IP_EBP_24 := 0;
End;

Function SHFileOperation(P : LongInt) : LongInt;
Begin
  SHFileOperation := 1;
End;

{ Table des API Win16 : module (K KERNEL, U USER, G GDI, B KEYBOARD,
  L LZEXPAND, S SHELL, M MMSYSTEM, E WIN87EM, N WING, V VER, C COMMDLG,
  T TOOLHELP, Y SYSTEM, D DISPLAY, O SOUND), ordinal, arguments dans
  l'ordre de declaration (W mot, I entier signe, L long, P pointeur
  lointain converti, S pointeur lointain brut, D double, V variable),
  resultat (W AX, L DX:AX, R registres) ; =n : constante ; X inconnue.
  Ordinaux d'apres la documentation de l'API Windows 3.1. }

Const
  W16ApiN = 1760;
  W16Apis : Array[0..W16ApiN - 1] Of String[40] = (
    'K001:X>W FatalExit',
    'K002:>W ExitKernel',
    'K003:>L GetVersion',
    'K004:WWW>W LocalInit',
    'K005:WW>W LocalAlloc',
    'K006:WWW>W LocalReAlloc',
    'K007:W>W LocalFree',
    'K008:W>L LocalLock',
    'K009:W>W LocalUnlock',
    'K010:W>W LocalSize',
    'K011:W>W LocalHandle',
    'K012:W>W LocalFlags',
    'K013:W>W LocalCompact',
    'K014:L>L LocalNotify',
    'K015:WL>W GlobalAlloc',
    'K016:WLW>W GlobalReAlloc',
    'K017:W>W GlobalFree',
    'K018:W>L GlobalLock',
    'K019:W>W GlobalUnlock',
    'K020:W>L GlobalSize',
    'K021:W>L GlobalHandle',
    'K022:W>W GlobalFlags',
    'K023:W>W LockSegment',
    'K024:W>W UnlockSegment',
    'K025:L>L GlobalCompact',
    'K026:W>W GlobalFreeAll',
    'K027:WPW>W GetModuleName',
    'K028:>L GlobalMasterHandle',
    'K029:>W Yield',
    'K030:W>W WaitEvent',
    'K031:W>W PostEvent',
    'K032:WI>W SetPriority',
    'K033:W>W LockCurrentTask',
    'K034:WW>W SetTaskQueue',
    'K035:W>W GetTaskQueue',
    'K036:>L GetCurrentTask',
    'K037:>L GetCurrentPDB',
    'K038:WS>L SetTaskSignalProc',
    'K039:X>W SetTaskSwitchProc',
    'K040:X>W SetTaskInterchange',
    'K041:>W EnableDos',
    'K042:>W DisableDos',
    'K043:X>W IsScreenGrab',
    'K044:X>W BuildPDB',
    'K045:PP>W LoadModule',
    'K046:W>W FreeModule',
    'K047:S>L GetModuleHandle',
    'K048:W>W GetModuleUsage',
    'K049:WPI>W GetModuleFileName',
    'K050:WP>L GetProcAddress',
    'K051:SW>L MakeProcInstance',
    'K052:S>W FreeProcInstance',
    'K053:X>W CallProcInstance',
    'K054:WWW>W GetInstanceData',
    'K055:R>R Catch',
    'K056:R>R Throw',
    'K057:PPI>W GetProfileInt',
    'K058:PPPPW>W GetProfileString',
    'K059:PPP>W WriteProfileString',
    'K060:WPP>W FindResource',
    'K061:WW>W LoadResource',
    'K062:W>L LockResource',
    'K063:W>W FreeResource',
    'K064:WW>W AccessResource',
    'K065:WW>L SizeofResource',
    'K066:WWL>W AllocResource',
    'K067:WPS>L SetResourceHandler',
    'K068:W>W InitAtomTable',
    'K069:P>W FindAtom',
    'K070:P>W AddAtom',
    'K071:W>W DeleteAtom',
    'K072:WPW>W GetAtomName',
    'K073:W>W GetAtomHandle',
    'K074:PPW>W OpenFile',
    'K075:X>W OpenPathName',
    'K076:X>W DeletePathName',
    'K077:S>L Reserved1',
    'K078:SS>L Reserved2',
    'K079:S>L Reserved3',
    'K080:S>L Reserved4',
    'K081:W>W _lclose',
    'K082:WSW>W _lread',
    'K083:PW>W _lcreat',
    'K084:WLW>L _llseek',
    'K085:PW>W _lopen',
    'K086:WPW>W _lwrite',
    'K087:PP>W Reserved5',
    'K088:SP>L lstrcpy',
    'K089:SP>L lstrcat',
    'K090:P>W lstrlen',
    'K091:R>R InitTask',
    'K092:W>L GetTempDrive',
    'K093:S>L GetCodeHandle',
    'K094:W>W DefineHandleTable',
    'K095:P>W LoadLibrary',
    'K096:W>W FreeLibrary',
    'K097:WPWP>W GetTempFileName',
    'K098:>W GetLastDiskChange',
    'K099:>L GetLPErrMode',
    'K100:>W ValidateCodeSegments',
    'K101:X>W NoHookDosCall',
    'K102:R>R DOS3Call',
    'K103:R>R NetBIOSCall',
    'K104:SP>W GetCodeInfo',
    'K105:>W GetExeVersion',
    'K106:W>L SetSwapAreaSize',
    'K107:W>W SetErrorMode',
    'K108:WWW>W SwitchStackTo',
    'K109:R>R SwitchStackBack',
    'K110:W>L PatchCodeHandle',
    'K111:W>L GlobalWire',
    'K112:W>W GlobalUnWire',
    'K113:=3 __AHSHIFT',
    'K114:=8 __AHINCR',
    'K115:P>W OutputDebugString',
    'K116:X>W InitLib',
    'K117:>W OldYield',
    'K118:>W GetTaskQueueDS',
    'K119:>W GetTaskQueueES',
    'K120:X>W UndefDynLink',
    'K121:WW>W LocalShrink',
    'K122:>W IsTaskLocked',
    'K123:>W KbdRst',
    'K124:>W EnableKernel',
    'K125:>W DisableKernel',
    'K126:X>W MemoryFreed',
    'K127:PPIP>W GetPrivateProfileInt',
    'K128:PPPPWP>W GetPrivateProfileStrin',
    'K129:PPPP>W WritePrivateProfileStr',
    'K130:P>L FileCDR',
    'K131:>L GetDOSEnvironment',
    'K132:>L GetWinFlags',
    'K133:W>W GetExePtr',
    'K134:PW>W GetWindowsDirectory',
    'K135:PW>W GetSystemDirectory',
    'K136:W>W GetDriveType',
    'K137:WP>W FatalAppExit',
    'K138:W>L GetHeapSpaces',
    'K139:X>W DoSignal',
    'K140:SPPWW>W SetSigHandler',
    'K141:X>W InitTask1',
    'K142:PW>W GetProfileSectionNames',
    'K143:PWP>W GetPrivateProfileSecti',
    'K144:PP>W CreateDirectory',
    'K145:P>W RemoveDirectory',
    'K146:P>W DeleteFile',
    'K147:L>W SetLastError',
    'K148:>L GetLastError',
    'K149:P>W GetVersionEx',
    'K150:W>W DirectedYield',
    'K151:X>W WinOldApCall',
    'K152:>W GetNumTasks',
    'K154:S>W GlobalNotify',
    'K155:>W GetTaskDS',
    'K156:L>L LimitEMSPages',
    'K157:L>L GetCurPID',
    'K158:W>W IsWinOldApTask',
    'K159:W>L GlobalHandleNoRIP',
    'K160:X>W EMSCopy',
    'K161:>W LocalCountFree',
    'K162:>W LocalHeapSize',
    'K163:W>W GlobalLRUOldest',
    'K164:W>W GlobalLRUNewest',
    'K165:W>W A20Proc',
    'K166:PW>W WinExec',
    'K167:W>W GetExpWinVer',
    'K168:WWW>W DirectResAlloc',
    'K169:W>L GetFreeSpace',
    'K170:W>W AllocCStoDSAlias',
    'K171:W>W AllocDStoCSAlias',
    'K172:W>W AllocAlias',
    'K173:=0 __ROMBIOS',
    'K174:=0 __A000H',
    'K175:W>W AllocSelector',
    'K176:W>W FreeSelector',
    'K177:WW>W PrestoChangoSelector',
    'K178:=1043 __WINFLAGS',
    'K179:=0 __D000H',
    'K180:LL>W LongPtrAdd',
    'K181:=0 __B000H',
    'K182:=0 __B800H',
    'K183:=0 __0000H',
    'K184:L>L GlobalDOSAlloc',
    'K185:W>W GlobalDOSFree',
    'K186:W>L GetSelectorBase',
    'K187:WL>W SetSelectorBase',
    'K188:W>L GetSelectorLimit',
    'K189:WL>W SetSelectorLimit',
    'K190:=0 __E000H',
    'K191:W>W GlobalPageLock',
    'K192:W>W GlobalPageUnlock',
    'K193:=0 __0040H',
    'K194:=0 __F000H',
    'K195:=0 __C000H',
    'K196:WWW>W SelectorAccessRights',
    'K197:W>W GlobalFix',
    'K198:W>W GlobalUnfix',
    'K199:W>W SetHandleCount',
    'K200:>W ValidateFreeSpaces',
    'K201:X>W ReplaceInst',
    'K202:X>W RegisterPtrace',
    'K203:R>R DebugBreak',
    'K204:X>W SwapRecording',
    'K205:X>W CVWBreak',
    'K206:W>W AllocSelectorArray',
    'K207:W>W IsDBCSLeadByte',
    'K208:WLLL>L K208',
    'K209:LLWL>L K209',
    'K210:LLWLL>L K210',
    'K211:LLW>L K211',
    'K213:LLWW>L K213',
    'K214:LLW>L K214',
    'K215:LW>L K215',
    'K216:LLPL>L RegEnumKey',
    'K217:LPP>L RegOpenKey',
    'K218:LPP>L RegCreateKey',
    'K219:LP>L RegDeleteKey',
    'K220:L>L RegCloseKey',
    'K221:LPLPL>L RegSetValue',
    'K222:LP>L RegDeleteValue',
    'K223:LLPPPPPP>L RegEnumValue',
    'K224:LPPP>L RegQueryValue',
    'K225:LPPPPP>L RegQueryValueEx',
    'K226:LPLLPL>L RegSetValueEx',
    'K227:L>L RegFlushKey',
    'K228:W>W K228',
    'K229:L>W K229',
    'K230:W>L GlobalSmartPageLock',
    'K231:W>L GlobalSmartPageUnlock',
    'K232:X>W RegLoadKey',
    'K233:X>W RegUnloadKey',
    'K234:X>W RegSaveKey',
    'K235:X>W InvalidateNlsCache',
    'K236:X>W GetProductName',
    'K237:>W K237',
    'K262:X>W WOWWaitForMsgAndEvent',
    'K263:X>W WOWMsgBox',
    'K273:X>W K273',
    'K274:PPW>W GetShortPathName',
    'K310:W>W LocalHandleDelta',
    'K311:P>L GetSetKernelDOSProc',
    'K314:X>W DebugDefineSegment',
    'K315:>W WriteOutProfiles',
    'K316:>L GetFreeMemInfo',
    'K318:X>W FatalExitHook',
    'K319:X>W FlushCachedFileHandle',
    'K320:W>W IsTask',
    'K323:W>W IsRomModule',
    'K324:WP>W LogError',
    'K325:WPP>W LogParamError',
    'K326:W>W IsRomFile',
    'K327:R>R K327',
    'K328:V>W _DebugOutput',
    'K329:PW>W K329',
    'K332:=0 THHOOK',
    'K334:SW>W IsBadReadPtr',
    'K335:SW>W IsBadWritePtr',
    'K336:S>W IsBadCodePtr',
    'K337:SW>W IsBadStringPtr',
    'K338:S>W HasGPHandler',
    'K339:>W DiagQuery',
    'K340:P>W DiagOutput',
    'K341:P>L ToolHelpHook',
    'K342:=0 __GP',
    'K343:X>W RegisterWinOldApHook',
    'K344:X>W GetWinOldApHooks',
    'K345:W>W IsSharedSelector',
    'K346:SL>W IsBadHugeReadPtr',
    'K347:SL>W IsBadHugeWritePtr',
    'K348:PPL>W hmemcpy',
    'K349:WSL>L _hread',
    'K350:WPL>L _hwrite',
    'K351:>W BUNNY_351',
    'K352:SPW>L lstrcatn',
    'K353:SPW>L lstrcpyn',
    'K354:W>L GetAppCompatFlags',
    'K355:PW>W GetWinDebugInfo',
    'K356:P>W SetWinDebugInfo',
    'K357:S>L MapSL',
    'K358:L>L MapLS',
    'K359:S>L UnMapLS',
    'K360:PPW>W OpenFileEx',
    'K361:>W PIGLET_361',
    'K362:X>W ThunkTerminateProcess',
    'K365:R>R GlobalChangeLockCount',
    'K403:WW>W FarSetOwner',
    'K404:W>W FarGetOwner',
    'K406:PPPWP>W WritePrivateProfileStr',
    'K407:PPPWP>W GetPrivateProfileStruc',
    'K408:X>W KERNEL_408',
    'K409:X>W KERNEL_409',
    'K410:X>W CreateProcessFromWinEx',
    'K411:LP>L GetCurrentDirectory',
    'K412:P>W SetCurrentDirectory',
    'K413:PP>W FindFirstFile',
    'K414:WP>W FindNextFile',
    'K415:W>W FindClose',
    'K416:PPP>W WritePrivateProfileSec',
    'K417:PP>W WriteProfileSection',
    'K418:PPWP>W GetPrivateProfileSecti',
    'K419:PPW>W GetProfileSection',
    'K420:P>L GetFileAttributes',
    'K421:PL>W SetFileAttributes',
    'K422:PPPPP>W GetDiskFreeSpace',
    'K423:P>W LogApiThk',
    'K431:PW>W IsPeFormat',
    'K432:X>W FileTimeToLocalFileTim',
    'K434:PPW>W UnicodeToAnsi',
    'K435:X>W GetTaskFlags',
    'K436:P>W _ConfirmSysLevel',
    'K437:P>W _CheckNotSysLevel',
    'K438:PL>W _CreateSysLevel',
    'K439:P>W _EnterSysLevel',
    'K440:P>W _LeaveSysLevel',
    'K441:PLSSLP>L CreateThread16',
    'K442:>L VWin32_EventCreate',
    'K443:L>L VWin32_EventDestroy',
    'K444:PW>W Local32Info',
    'K445:PW>W Local32First',
    'K446:P>W Local32Next',
    'K447:>W WIN32_OldYield',
    'K448:X>W KERNEL_448',
    'K449:>L GetpWin16Lock',
    'K450:L>L VWin32_EventWait',
    'K451:L>L VWin32_EventSet',
    'K452:P>L LoadLibrary32',
    'K453:LP>L GetProcAddress32',
    'K454:=0 __FLATCS',
    'K455:=0 __FLATDS',
    'K456:WWW>L DefResourceHandler',
    'K457:LL>L CreateW32Event',
    'K458:L>L SetW32Event',
    'K459:L>L ResetW32Event',
    'K460:LL>L WaitForSingleObject',
    'K461:LPLL>L WaitForMultipleObjects',
    'K462:>L GetCurrentThreadId',
    'K463:LW>L SetThreadQueue',
    'K464:L>L GetThreadQueue',
    'K465:X>W NukeProcess',
    'K466:W>W ExitProcess',
    'K467:X>W WOACreateConsole',
    'K468:X>W WOASpawnConApp',
    'K469:X>W WOAGimmeTitle',
    'K470:X>W WOADestroyConsole',
    'K471:>L GetCurrentProcessId',
    'K472:R>R MapHInstLS',
    'K473:R>R MapHInstSL',
    'K474:L>L CloseW32Handle',
    'K475:>W GetTEBSelectorFS',
    'K476:L>L ConvertToGlobalHandle',
    'K477:X>W WOAFullScreen',
    'K478:X>W WOATerminateProcess',
    'K479:L>L KERNEL_479',
    'K480:>W _EnterWin16Lock',
    'K481:>W _LeaveWin16Lock',
    'K482:P>L LoadSystemLibrary32',
    'K483:L>L MapProcessHandle',
    'K484:LIL>L SetProcessDword',
    'K485:LI>L GetProcessDword',
    'K486:L>L FreeLibrary32',
    'K487:LPW>L GetModuleFileName32',
    'K488:P>L GetModuleHandle32',
    'K489:X>W KERNEL_489',
    'K490:W>W KERNEL_490',
    'K491:LL>L RegisterServiceProcess',
    'K492:X>W WOAAbort',
    'K493:LLLL>W UTInit',
    'K494:X>W KERNEL_494',
    'K495:LPLLL>L WaitForMultipleObjects',
    'K500:V>L WOW16Call',
    'K501:X>W KDDBGOUT',
    'K502:X>W WOWGETNEXTVDMCOMMAND',
    'K503:X>W WOWREGISTERSHELLWINDOW',
    'K504:X>W WOWLOADMODULE',
    'K505:X>W WOWQUERYPERFORMANCECOU',
    'K506:X>W WOWCURSORICONOP',
    'K507:X>W WOWFAILEDEXEC',
    'K508:X>W WOWCLOSECOMPORT',
    'K511:X>W WOWKILLREMOTETASK',
    'K512:X>W WOWQUERYDEBUG',
    'K513:PLL>L LoadLibraryEx32W',
    'K514:L>L FreeLibrary32W',
    'K515:LP>L GetProcAddress32W',
    'K516:SW>L GetVDMPointer32W',
    'K517:V>L CallProc32W',
    'K518:V>L _CallProcEx32W',
    'K519:X>W EXITKERNELTHUNK',
    'K520:=4200 __MOD_KERNEL',
    'K521:=4201 __MOD_DKERNEL',
    'K522:=4203 __MOD_USER',
    'K523:=4204 __MOD_DUSER',
    'K524:=4205 __MOD_GDI',
    'K525:=4206 __MOD_DGDI',
    'K526:=4207 __MOD_KEYBOARD',
    'K527:=4208 __MOD_SOUND',
    'K528:=4209 __MOD_SHELL',
    'K529:=4210 __MOD_WINSOCK',
    'K530:=4211 __MOD_TOOLHELP',
    'K531:=4212 __MOD_MMEDIA',
    'K532:=4213 __MOD_COMMDLG',
    'K541:X>W WOWSETEXITONLASTAPP',
    'K544:X>W WOWSETCOMPATHANDLE',
    'K533:X>W ConvertDDEHandleLS',
    'K534:X>W ConvertDDEHandleSL',
    'K535:LL>L VWin32_BoostThreadGrou',
    'K536:LL>L VWin32_BoostThreadStat',
    'K537:X>W KERNEL_537',
    'K538:X>W ThunkTheTemplateHandle',
    'K540:X>W KERNEL_540',
    'K542:X>W KERNEL_542',
    'K543:X>W KERNEL_543',
    'K560:LS>L SetThunkletCallbackGlu',
    'K561:SL>L AllocLSThunkletCallbac',
    'K562:LL>L AllocSLThunkletCallbac',
    'K563:SL>L FindLSThunkletCallback',
    'K564:LL>L FindSLThunkletCallback',
    'K566:X>W KERNEL_566',
    'K567:SLW>L AllocLSThunkletCallbac',
    'K568:LLW>L AllocSLThunkletCallbac',
    'K600:X>W AllocCodeAlias',
    'K601:X>W FreeCodeAlias',
    'K602:>W GetDummyModuleHandleDS',
    'K603:X>W KERNEL_603',
    'K604:R>R CBClientGlueSL',
    'K605:LL>L AllocSLThunkletCallbac',
    'K606:SL>L AllocLSThunkletCallbac',
    'K607:SLL>L AllocLSThunkletSysthun',
    'K608:LSL>L AllocSLThunkletSysthun',
    'K609:SL>L FindLSThunkletCallback',
    'K610:LL>L FindSLThunkletCallback',
    'K611:LL>W FreeThunklet',
    'K612:P>W IsSLThunklet',
    'K613:X>W HugeMapLS',
    'K614:X>W HugeUnMapLS',
    'K615:LLL>W ConvertDialog32To16',
    'K616:LLL>W ConvertMenu32To16',
    'K617:P>W GetMenu32Size',
    'K618:P>W GetDialog32Size',
    'K619:WSL>W RegisterCBClient',
    'K620:R>R CBClientThunkSL',
    'K621:R>R CBClientThunkSLEx',
    'K622:WSL>W UnRegisterCBClient',
    'K623:L>W InitCBClient',
    'K624:LL>L SetFastQueue',
    'K625:>L GetFastQueue',
    'K626:X>W SmashEnvironment',
    'K627:SLW>W IsBadFlatReadWritePtr',
    'K630:R>R C16ThkSL',
    'K631:R>R C16ThkSL01',
    'K651:PPWLPPW>L ThunkConnect16',
    'K652:X>W IsThreadId',
    'K653:X>W OkWithKernelToChangeUs',
    'K666:PLPL>L UTGlue16',
    'K667:WW>L EntryAddrProc',
    'K668:WWW>L MyAlloc',
    'K669:LWWWLW>W DllEntryPoint',
    'K700:>L SSInit',
    'K701:X>W SSOnBigStack',
    'K702:X>W SSCall',
    'K703:X>W CallProc32WFix',
    'K704:R>R SSConfirmSmallStack',
    'K901:R>R __wine_vxd_vmm',
    'K905:R>R __wine_vxd_timer',
    'K909:R>R __wine_vxd_reboot',
    'K910:R>R __wine_vxd_vdd',
    'K912:R>R __wine_vxd_vmd',
    'K914:R>R __wine_vxd_comm',
    'K923:R>R __wine_vxd_shell',
    'K933:R>R __wine_vxd_pagefile',
    'K938:R>R __wine_vxd_apm',
    'K939:R>R __wine_vxd_vxdloader',
    'K945:R>R __wine_vxd_win32s',
    'K951:R>R __wine_vxd_configmg',
    'K955:R>R __wine_vxd_enable',
    'U001:WPPW>W MessageBox',
    'U002:>W OldExitWindows',
    'U003:X>W EnableOEMLayer',
    'U004:X>W DisableOEMLayer',
    'U005:W>W InitApp',
    'U006:W>W PostQuitMessage',
    'U007:LW>W ExitWindows',
    'U010:WWWS>W SetTimer',
    'U011:WWWS>W SetSystemTimer',
    'U012:WW>W KillTimer',
    'U013:>L GetTickCount',
    'U014:>L GetTimerResolution',
    'U015:>L GetCurrentTime',
    'U016:P>W ClipCursor',
    'U017:P>W GetCursorPos',
    'U018:W>W SetCapture',
    'U019:>W ReleaseCapture',
    'U020:W>W SetDoubleClickTime',
    'U021:>W GetDoubleClickTime',
    'U022:W>W SetFocus',
    'U023:>W GetFocus',
    'U024:WP>W RemoveProp',
    'U025:WP>W GetProp',
    'U026:WPW>W SetProp',
    'U027:WS>W EnumProps',
    'U028:WP>W ClientToScreen',
    'U029:WP>W ScreenToClient',
    'U030:L>W WindowFromPoint',
    'U031:W>W IsIconic',
    'U032:WP>W GetWindowRect',
    'U033:WP>W GetClientRect',
    'U034:WW>W EnableWindow',
    'U035:W>W IsWindowEnabled',
    'U036:WSW>W GetWindowText',
    'U037:WS>W SetWindowText',
    'U038:W>W GetWindowTextLength',
    'U039:WP>W BeginPaint',
    'U040:WP>W EndPaint',
    'U041:PPLIIIIWWWS>W CreateWindow',
    'U042:WW>W ShowWindow',
    'U043:W>W CloseWindow',
    'U044:W>W OpenIcon',
    'U045:W>W BringWindowToTop',
    'U046:W>W GetParent',
    'U047:W>W IsWindow',
    'U048:WW>W IsChild',
    'U049:W>W IsWindowVisible',
    'U050:PP>W FindWindow',
    'U051:X>W BEAR51',
    'U052:>W AnyPopup',
    'U053:W>W DestroyWindow',
    'U054:SL>W EnumWindows',
    'U055:WSL>W EnumChildWindows',
    'U056:WWWWWW>W MoveWindow',
    'U057:P>W RegisterClass',
    'U058:WPW>W GetClassName',
    'U059:W>W SetActiveWindow',
    'U060:>W GetActiveWindow',
    'U061:WIIPP>W ScrollWindow',
    'U062:WWIW>W SetScrollPos',
    'U063:WW>W GetScrollPos',
    'U064:WWIIW>W SetScrollRange',
    'U065:WWPP>W GetScrollRange',
    'U066:W>W GetDC',
    'U067:W>W GetWindowDC',
    'U068:WW>W ReleaseDC',
    'U069:W>W SetCursor',
    'U070:WW>W SetCursorPos',
    'U071:W>W ShowCursor',
    'U072:PIIII>W SetRect',
    'U073:P>W SetRectEmpty',
    'U074:PP>W CopyRect',
    'U075:P>W IsRectEmpty',
    'U076:PL>W PtInRect',
    'U077:PII>W OffsetRect',
    'U078:PII>W InflateRect',
    'U079:PPP>W IntersectRect',
    'U080:PPP>W UnionRect',
    'U081:WPW>W FillRect',
    'U082:WP>W InvertRect',
    'U083:WPW>W FrameRect',
    'U084:WIIW>W DrawIcon',
    'U085:WPIPW>W DrawText',
    'U086:>L IconSize',
    'U087:WPWS>W DialogBox',
    'U088:WI>W EndDialog',
    'U089:WPWS>W CreateDialog',
    'U090:WP>W IsDialogMessage',
    'U091:WW>W GetDlgItem',
    'U092:WWS>W SetDlgItemText',
    'U093:WWSW>W GetDlgItemText',
    'U094:WWWW>W SetDlgItemInt',
    'U095:WIPW>W GetDlgItemInt',
    'U096:WWWW>W CheckRadioButton',
    'U097:WWW>W CheckDlgButton',
    'U098:WW>W IsDlgButtonChecked',
    'U099:WPW>W DlgDirSelect',
    'U100:WPWWW>W DlgDirList',
    'U101:WWWWL>L SendDlgItemMessage',
    'U102:PLW>W AdjustWindowRect',
    'U103:WP>W MapDialogRect',
    'U104:W>W MessageBeep',
    'U105:WW>W FlashWindow',
    'U106:W>W GetKeyState',
    'U107:WWWL>L DefWindowProc',
    'U108:PWWW>W GetMessage',
    'U109:PWWWW>W PeekMessage',
    'U110:WWWL>W PostMessage',
    'U111:WWWL>L SendMessage',
    'U112:>W WaitMessage',
    'U113:P>W TranslateMessage',
    'U114:P>L DispatchMessage',
    'U115:L>W ReplyMessage',
    'U116:WWWL>W PostAppMessage',
    'U117:W>W WindowFromDC',
    'U118:P>W RegisterWindowMessage',
    'U119:>L GetMessagePos',
    'U120:>L GetMessageTime',
    'U121:IS>L SetWindowsHook',
    'U122:SWWWL>L CallWindowProc',
    'U123:PI>W CallMsgFilter',
    'U124:W>W UpdateWindow',
    'U125:WPW>W InvalidateRect',
    'U126:WWW>W InvalidateRgn',
    'U127:WP>W ValidateRect',
    'U128:WW>W ValidateRgn',
    'U129:WI>W GetClassWord',
    'U130:WIW>W SetClassWord',
    'U131:WI>L GetClassLong',
    'U132:WIL>L SetClassLong',
    'U133:WI>W GetWindowWord',
    'U134:WIW>W SetWindowWord',
    'U135:WI>L GetWindowLong',
    'U136:WIL>L SetWindowLong',
    'U137:W>W OpenClipboard',
    'U138:>W CloseClipboard',
    'U139:>W EmptyClipboard',
    'U140:>W GetClipboardOwner',
    'U141:WW>W SetClipboardData',
    'U142:W>W GetClipboardData',
    'U143:>W CountClipboardFormats',
    'U144:W>W EnumClipboardFormats',
    'U145:P>W RegisterClipboardForma',
    'U146:WPI>W GetClipboardFormatName',
    'U147:W>W SetClipboardViewer',
    'U148:>W GetClipboardViewer',
    'U149:WW>W ChangeClipboardChain',
    'U150:WP>W LoadMenu',
    'U151:>W CreateMenu',
    'U152:W>W DestroyMenu',
    'U153:WWSWW>W ChangeMenu',
    'U154:WWW>W CheckMenuItem',
    'U155:WWW>W EnableMenuItem',
    'U156:WW>W GetSystemMenu',
    'U157:W>W GetMenu',
    'U158:WW>W SetMenu',
    'U159:WW>W GetSubMenu',
    'U160:W>W DrawMenuBar',
    'U161:WWPIW>W GetMenuString',
    'U162:WWWW>W HiliteMenuItem',
    'U163:WWWW>W CreateCaret',
    'U164:>W DestroyCaret',
    'U165:WW>W SetCaretPos',
    'U166:W>W HideCaret',
    'U167:W>W ShowCaret',
    'U168:W>W SetCaretBlinkTime',
    'U169:>W GetCaretBlinkTime',
    'U170:W>W ArrangeIconicWindows',
    'U171:WPWL>W WinHelp',
    'U172:WW>W SwitchToThisWindow',
    'U173:WP>W LoadCursor',
    'U174:WP>W LoadIcon',
    'U175:WP>W LoadBitmap',
    'U176:WWPI>W LoadString',
    'U177:WP>W LoadAccelerators',
    'U178:WWP>W TranslateAccelerator',
    'U179:I>W GetSystemMetrics',
    'U180:W>L GetSysColor',
    'U181:WPP>W SetSysColors',
    'U182:WW>W KillSystemTimer',
    'U183:P>W GetCaretPos',
    'U184:X>W QuerySendMessage',
    'U185:WWSSIIIII>W GrayString',
    'U186:W>W SwapMouseButton',
    'U187:>W EndMenu',
    'U188:W>W SetSysModalWindow',
    'U189:>W GetSysModalWindow',
    'U190:WPW>W GetUpdateRect',
    'U191:WL>W ChildWindowFromPoint',
    'U192:>W InSendMessage',
    'U193:W>W IsClipboardFormatAvail',
    'U194:WPW>W DlgDirSelectComboBox',
    'U195:WPWWW>W DlgDirListComboBox',
    'U196:WIIPIIPI>L TabbedTextOut',
    'U197:WPWWP>L GetTabbedTextExtent',
    'U198:WW>W CascadeChildWindows',
    'U199:WW>W TileChildWindows',
    'U200:PWW>W OpenComm',
    'U201:P>W SetCommState',
    'U202:WP>W GetCommState',
    'U203:WP>W GetCommError',
    'U204:WPW>W ReadComm',
    'U205:WPW>W WriteComm',
    'U206:WW>W TransmitCommChar',
    'U207:W>W CloseComm',
    'U208:WW>L SetCommEventMask',
    'U209:WW>W GetCommEventMask',
    'U210:W>W SetCommBreak',
    'U211:W>W ClearCommBreak',
    'U212:WW>W UngetCommChar',
    'U213:PP>W BuildCommDCB',
    'U214:WW>L EscapeCommFunction',
    'U215:WW>W FlushComm',
    'U216:WWWW>L UserSeeUserDo',
    'U217:WI>W LookupMenuHandle',
    'U218:WWWS>W DialogBoxIndirect',
    'U219:WPWS>W CreateDialogIndirect',
    'U220:P>W LoadMenuIndirect',
    'U221:WIIPPWP>W ScrollDC',
    'U222:P>W GetKeyboardState',
    'U223:P>W SetKeyboardState',
    'U224:W>W GetWindowTask',
    'U225:WSL>W EnumTaskWindows',
    'U226:X>W LockInput',
    'U227:WWW>W GetNextDlgGroupItem',
    'U228:WWW>W GetNextDlgTabItem',
    'U229:W>W GetTopWindow',
    'U230:WW>W GetNextWindow',
    'U231:>W GetSystemDebugState',
    'U232:WWWWWWW>W SetWindowPos',
    'U233:WW>W SetParent',
    'U234:IS>W UnhookWindowsHook',
    'U235:IWLP>L DefHookProc',
    'U236:>W GetCapture',
    'U237:WWW>W GetUpdateRgn',
    'U238:WW>W ExcludeUpdateRgn',
    'U239:WPWSL>W DialogBoxParam',
    'U240:WWWSL>W DialogBoxIndirectParam',
    'U241:WPWSL>W CreateDialogParam',
    'U242:WPWSL>W CreateDialogIndirectPa',
    'U243:>L GetDialogBaseUnits',
    'U244:PP>W EqualRect',
    'U245:IWII>W EnableCommNotification',
    'U246:PP>W ExitWindowsExec',
    'U247:>W GetCursor',
    'U248:>W GetOpenClipboardWindow',
    'U249:W>W GetAsyncKeyState',
    'U250:WWW>W GetMenuState',
    'U251:WWLL>L SendDriverMessage',
    'U252:PPL>W OpenDriver',
    'U253:WLL>L CloseDriver',
    'U254:W>W GetDriverModuleHandle',
    'U255:LWWLL>L DefDriverProc',
    'U256:WP>W GetDriverInfo',
    'U257:WL>W GetNextDriver',
    'U258:WWPW>W MapWindowPoints',
    'U259:I>W BeginDeferWindowPos',
    'U260:WWWIIIIW>W DeferWindowPos',
    'U261:W>W EndDeferWindowPos',
    'U262:WW>W GetWindow',
    'U263:W>W GetMenuItemCount',
    'U264:WW>W GetMenuItemID',
    'U265:WW>W ShowOwnedPopups',
    'U266:W>W SetMessageQueue',
    'U267:WWW>W ShowScrollBar',
    'U268:P>W GlobalAddAtom',
    'U269:W>W GlobalDeleteAtom',
    'U270:P>W GlobalFindAtom',
    'U271:WPI>W GlobalGetAtomName',
    'U272:W>W IsZoomed',
    'U273:WWP>W ControlPanelInfo',
    'U274:X>W GetNextQueueWindow',
    'U275:X>W RepaintScreen',
    'U276:X>W LockMyTask',
    'U277:W>W GetDlgCtrlID',
    'U278:>W GetDesktopHwnd',
    'U279:>W OldSetDeskPattern',
    'U280:WW>W SetSystemMenu',
    'U281:W>W GetSysColorBrush',
    'U282:WWW>W SelectPalette',
    'U283:W>W RealizePalette',
    'U284:W>W GetFreeSystemResources',
    'U285:P>W SetDeskWallpaper',
    'U286:>W GetDesktopWindow',
    'U287:W>W GetLastActivePopup',
    'U288:>L GetMessageExtraInfo',
    'U289:R>R keybd_event',
    'U290:WPWW>W RedrawWindow',
    'U291:ISWW>L SetWindowsHookEx',
    'U292:S>W UnhookWindowsHookEx',
    'U293:SIWL>L CallNextHookEx',
    'U294:W>W LockWindowUpdate',
    'U299:R>R mouse_event',
    'U300:X>W UnloadInstalledDrivers',
    'U301:X>W EDITWNDPROC',
    'U302:X>W STATICWNDPROC',
    'U303:X>W BUTTONWNDPROC',
    'U304:X>W SBWNDPROC',
    'U305:X>W DESKTOPWNDPROC',
    'U306:X>W MENUWNDPROC',
    'U307:X>W LBOXCTLWNDPROC',
    'U308:WWWL>L DefDlgProc',
    'U309:P>W GetClipCursor',
    'U314:WWWWW>W SignalProc',
    'U319:WIIPPWPW>W ScrollWindowEx',
    'U320:X>W SysErrorBox',
    'U321:S>L SetEventHook',
    'U322:X>W WinOldAppHackOMatic',
    'U323:X>W GetMessage2',
    'U324:WWWW>W FillWindow',
    'U325:WWWWP>W PaintRect',
    'U326:WWW>W GetControlBrush',
    'U331:W>W EnableHardwareInput',
    'U332:>W UserYield',
    'U333:>W IsUserIdle',
    'U334:W>L GetQueueStatus',
    'U335:>W GetInputState',
    'U336:WWW>W LoadCursorIconHandler',
    'U337:>L GetMouseEventProc',
    'U338:X>W ECGETDS',
    'U343:X>W GetFilePortName',
    'U344:X>W COMBOBOXCTLWNDPROC',
    'U345:X>W BEAR345',
    'U356:WWW>W LoadDIBCursorHandler',
    'U357:WWW>W LoadDIBIconHandler',
    'U358:W>W IsMenu',
    'U359:WWL>W GetDCEx',
    'U362:WWLL>W DCHook',
    'U364:PWWWW>W LookupIconIdFromDirect',
    'U368:WW>W CopyIcon',
    'U369:WW>W CopyCursor',
    'U370:WP>W GetWindowPlacement',
    'U371:WP>W SetWindowPlacement',
    'U372:X>W GetInternalIconHeader',
    'U373:PPP>W SubtractRect',
    'U374:LWWWLW>W DllEntryPoint',
    'U375:X>W DrawTextEx',
    'U376:X>W SetMessageExtraInfo',
    'U378:X>W SetPropEx',
    'U379:X>W GetPropEx',
    'U380:X>W RemovePropEx',
    'U382:X>W SetWindowContextHelpID',
    'U383:X>W GetWindowContextHelpID',
    'U384:WW>W SetMenuContextHelpId',
    'U385:W>W GetMenuContextHelpId',
    'U389:WPWWWW>L LoadImage',
    'U390:WWWWW>W CopyImage',
    'U391:LLLW>W SignalProc32',
    'U394:WWWWWWWWW>W DrawIconEx',
    'U395:WP>W GetIconInfo',
    'U397:P>W RegisterClassEx',
    'U398:WSP>W GetClassInfoEx',
    'U399:WLW>W ChildWindowFromPointEx',
    'U400:>W FinalUserInit',
    'U402:PI>W GetPriorityClipboardFo',
    'U403:PW>W UnregisterClass',
    'U404:WSP>W GetClassInfo',
    'U406:WWWWWPP>W CreateCursor',
    'U407:WWWWWPP>W CreateIcon',
    'U408:WPPP>W CreateCursorIconIndire',
    'U409:WW>W InitThreadInput',
    'U410:WWWWS>W InsertMenu',
    'U411:WWWS>W AppendMenu',
    'U412:WWW>W RemoveMenu',
    'U413:WWW>W DeleteMenu',
    'U414:WWWWS>W ModifyMenu',
    'U415:>W CreatePopupMenu',
    'U416:WWIIIWP>W TrackPopupMenu',
    'U417:>L GetMenuCheckMarkDimens',
    'U418:WWWWW>W SetMenuItemBitmaps',
    'U420:V>W _wsprintf',
    'U421:PPP>W wvsprintf',
    'U422:WPWW>W DlgDirSelectEx',
    'U423:WPWW>W DlgDirSelectComboBoxEx',
    'U427:WWPP>W FindWindowEx',
    'U428:X>W TileWindows',
    'U429:X>W CascadeWindows',
    'U430:PP>W lstrcmp',
    'U431:S>L AnsiUpper',
    'U432:S>L AnsiLower',
    'U433:W>W IsCharAlpha',
    'U434:W>W IsCharAlphaNumeric',
    'U435:W>W IsCharUpper',
    'U436:W>W IsCharLower',
    'U437:PW>W AnsiUpperBuff',
    'U438:PW>W AnsiLowerBuff',
    'U441:WWWP>W InsertMenuItem',
    'U443:X>W GetMenuItemInfo',
    'U445:WWWWL>L DefFrameProc',
    'U446:X>W SetMenuItemInfo',
    'U447:WWWL>L DefMDIChildProc',
    'U448:WWPP>W DrawAnimatedRects',
    'U449:WWSLWIIIIW>W DrawState',
    'U450:PLWLWWW>W CreateIconFromResource',
    'U451:WP>W TranslateMDISysAccel',
    'U452:LPPLIIIIWWWS>W CreateWindowEx',
    'U454:PLWL>W AdjustWindowRectEx',
    'U455:WL>W GetIconID',
    'U456:WW>W LoadIconHandler',
    'U457:W>W DestroyIcon',
    'U458:W>W DestroyCursor',
    'U459:SPPP>L DumpIcon',
    'U460:WPP>W GetInternalWindowPos',
    'U461:WWPP>W SetInternalWindowPos',
    'U462:WW>W CalcChildScroll',
    'U463:WWWL>W ScrollChildren',
    'U464:WWWWWW>L DragObject',
    'U465:WL>W DragDetect',
    'U466:WP>W DrawFocusRect',
    'U470:X>W StringFunc',
    'U471:PP>W lstrcmpi',
    'U472:S>L AnsiNext',
    'U473:PS>L AnsiPrev',
    'U475:WIPW>W SetScrollInfo',
    'U476:WIP>W GetScrollInfo',
    'U477:P>W GetKeyboardLayoutName',
    'U478:X>W LoadKeyboardLayout',
    'U479:X>W MenuItemFromPoint',
    'U480:X>W GetUserLocalObjType',
    'U482:WWW>W EnableScrollBar',
    'U483:WWPW>W SystemParametersInfo',
    'U489:>W USER_489',
    'U490:>W USER_490',
    'U492:>W USER_492',
    'U496:>W USER_496',
    'U498:X>W BEAR498',
    'U499:WPW>W WNetErrorText',
    'U500:X>W FARCALLNETDRIVER',
    'U501:PPWP>W WNetOpenJob',
    'U502:WPP>W WNetCloseJob',
    'U503:PW>W WNetAbortJob',
    'U504:PW>W WNetHoldJob',
    'U505:PW>W WNetReleaseJob',
    'U506:PW>W WNetCancelJob',
    'U507:PWW>W WNetSetJobCopies',
    'U508:WPPW>W WNetWatchQueue',
    'U509:P>W WNetUnwatchQueue',
    'U510:PPP>W WNetLockQueueData',
    'U511:P>W WNetUnlockQueueData',
    'U512:PPP>W WNetGetConnection',
    'U513:W>W WNetGetCaps',
    'U514:W>W WNetDeviceMode',
    'U515:WWP>W WNetBrowseDialog',
    'U516:PP>W WNetGetUser',
    'U517:PPP>W WNetAddConnection',
    'U518:PW>W WNetCancelConnection',
    'U519:P>W WNetGetError',
    'U520:WPP>W WNetGetErrorText',
    'U521:X>W WNetEnable',
    'U522:X>W WNetDisable',
    'U523:WP>W WNetRestoreConnection',
    'U524:WPP>W WNetWriteJob',
    'U525:WW>W WNetConnectDialog',
    'U526:WW>W WNetDisconnectDialog',
    'U527:WW>W WNetConnectionDialog',
    'U528:WP>W WNetViewQueueDialog',
    'U529:WWWPW>W WNetPropertyDialog',
    'U530:PP>W WNetGetDirectoryType',
    'U531:WPW>W WNetDirectoryNotify',
    'U532:WWPPWW>W WNetGetPropertyText',
    'U533:X>W WNetInitialize',
    'U534:X>W WNetLogon',
    'U535:X>W WOWWORDBREAKPROC',
    'U537:X>W MOUSEEVENT',
    'U538:X>W KEYBDEVENT',
    'U595:X>W OLDEXITWINDOWS',
    'U600:>W GetShellWindow',
    'U601:X>W DoHotkeyStuff',
    'U602:X>W SetCheckCursorTimer',
    'U604:X>W BroadcastSystemMessage',
    'U605:X>W HackTaskMonitor',
    'U606:LSWWPWP>W FormatMessage',
    'U608:>W GetForegroundWindow',
    'U609:W>W SetForegroundWindow',
    'U610:WW>W DestroyIcon32',
    'U620:PL>L ChangeDisplaySettings',
    'U621:PLP>W EnumDisplaySettings',
    'U640:LPLLL>L MsgWaitForMultipleObje',
    'U650:X>W ActivateKeyboardLayout',
    'U651:X>W GetKeyboardLayout',
    'U652:X>W GetKeyboardLayoutList',
    'U654:X>W UnloadKeyboardLayout',
    'U655:X>W PostPostedMessages',
    'U656:WPWW>W DrawFrameControl',
    'U657:WWPWWPW>W DrawCaptionTemp',
    'U658:X>W DispatchInput',
    'U659:WPWW>W DrawEdge',
    'U660:WWPW>W DrawCaption',
    'U661:X>W SetSysColorsTemp',
    'U662:X>W DrawMenubarTemp',
    'U663:X>W GetMenuDefaultItem',
    'U664:X>W SetMenuDefaultItem',
    'U665:WWWP>W GetMenuItemRect',
    'U666:WWWWW>W CheckMenuRadioItem',
    'U667:X>W TrackPopupMenuEx',
    'U668:WWW>W SetWindowRgn',
    'U669:X>W GetWindowRgn',
    'U800:X>W CHOOSEFONT_CALLBACK16',
    'U801:X>W FINDREPLACE_CALLBACK16',
    'U802:X>W OPENFILENAME_CALLBACK1',
    'U803:X>W PRINTDLG_CALLBACK16',
    'U804:X>W CHOOSECOLOR_CALLBACK16',
    'U819:PWWWWW>W PeekMessage32',
    'U820:PWWWW>L GetMessage32',
    'U821:PW>W TranslateMessage32',
    'U822:PW>L DispatchMessage32',
    'U823:PWW>W CallMsgFilter32',
    'U825:X>W PostMessage32',
    'U826:X>W PostThreadMessage32',
    'U827:P>W MessageBoxIndirect',
    'U851:X>W MsgThkConnectionDataLS',
    'U853:X>W FT_USRFTHKTHKCONNECTIO',
    'U854:X>W FT__USRF2THKTHKCONNECT',
    'U855:X>W Usr32ThkConnectionData',
    'U890:X>W InstallIMT',
    'U891:X>W UninstallIMT',
    'U902:WWPWW>W LoadSystemLanguageStri',
    'U905:>W ChangeDialogTemplate',
    'U906:>W GetNumLanguages',
    'U907:WWPW>W GetLanguageName',
    'U909:WPW>W SetWindowTextEx',
    'U910:>W BiDiMessageBoxEx',
    'U911:WWPW>W SetDlgItemTextEx',
    'U912:WW>L ChangeKeyboardLanguage',
    'U913:WW>W GetCodePageSystemFont',
    'U914:WWWL>W QueryCodePage',
    'U915:W>L GetAppCodePage',
    'U916:WPWPLWWPW>W CreateDialogIndirectPa',
    'U918:WWWPLWWPW>W DialogBoxIndirectParam',
    'U919:WWWPW>W LoadLanguageString',
    'U920:WWWW>L SetAppCodePage',
    'U922:>L GetBaseCodePage',
    'U923:WPPW>W FindLanguageResource',
    'U924:WW>L ChangeKeyboardCodePage',
    'U930:WPPWW>W MessageBoxEx',
    'G001:WL>L SetBkColor',
    'G002:WW>W SetBkMode',
    'G003:WW>W SetMapMode',
    'G004:WW>W SetROP2',
    'G005:WW>W SetRelAbs',
    'G006:WW>W SetPolyFillMode',
    'G007:WW>W SetStretchBltMode',
    'G008:WI>W SetTextCharacterExtra',
    'G009:WL>L SetTextColor',
    'G010:WII>W SetTextJustification',
    'G011:WII>L SetWindowOrg',
    'G012:WII>L SetWindowExt',
    'G013:WII>L SetViewportOrg',
    'G014:WII>L SetViewportExt',
    'G015:WII>L OffsetWindowOrg',
    'G016:WIIII>L ScaleWindowExt',
    'G017:WII>L OffsetViewportOrg',
    'G018:WIIII>L ScaleViewportExt',
    'G019:WII>W LineTo',
    'G020:WII>L MoveTo',
    'G021:WIIII>W ExcludeClipRect',
    'G022:WIIII>W IntersectClipRect',
    'G023:WIIIIIIII>W Arc',
    'G024:WIIII>W Ellipse',
    'G025:WIIL>W FloodFill',
    'G026:WIIIIIIII>W Pie',
    'G027:WIIII>W Rectangle',
    'G028:WIIIIII>W RoundRect',
    'G029:WIIIIL>W PatBlt',
    'G030:W>W SaveDC',
    'G031:WIIL>L SetPixel',
    'G032:WII>W OffsetClipRgn',
    'G033:WIIPW>W TextOut',
    'G034:WIIIIWIIL>W BitBlt',
    'G035:WIIIIWIIIIL>W StretchBlt',
    'G036:>W Polygon',
    'G037:>W Polyline',
    'G038:WWWSP>L Escape',
    'G039:WI>W RestoreDC',
    'G040:WWW>W FillRgn',
    'G041:WWWWW>W FrameRgn',
    'G042:WW>W InvertRgn',
    'G043:WW>W PaintRgn',
    'G044:WW>W SelectClipRgn',
    'G045:WW>W SelectObject',
    'G046:X>W BITMAPBITS',
    'G047:WWWI>W CombineRgn',
    'G048:WWWWP>W CreateBitmap',
    'G049:P>W CreateBitmapIndirect',
    'G050:P>W CreateBrushIndirect',
    'G051:WWW>W CreateCompatibleBitmap',
    'G052:W>W CreateCompatibleDC',
    'G053:PPPP>W CreateDC',
    'G054:IIII>W CreateEllipticRgn',
    'G055:P>W CreateEllipticRgnIndir',
    'G056:IIIIIWWWWWWWWP>W CreateFont',
    'G057:P>W CreateFontIndirect',
    'G058:WL>W CreateHatchBrush',
    'G060:W>W CreatePatternBrush',
    'G061:IIL>W CreatePen',
    'G062:P>W CreatePenIndirect',
    'G063:PWW>W CreatePolygonRgn',
    'G064:IIII>W CreateRectRgn',
    'G065:P>W CreateRectRgnIndirect',
    'G066:L>W CreateSolidBrush',
    'G067:WPI>W DPtoLP',
    'G068:W>W DeleteDC',
    'G069:W>W DeleteObject',
    'G070:WPSL>W EnumFonts',
    'G071:WWSL>W EnumObjects',
    'G072:WW>W EqualRgn',
    'G073:WIIII>W ExcludeVisRect',
    'G074:WLP>L GetBitmapBits',
    'G075:W>L GetBkColor',
    'G076:W>W GetBkMode',
    'G077:WP>W GetClipBox',
    'G078:W>L GetCurrentPosition',
    'G079:W>L GetDCOrg',
    'G080:WI>W GetDeviceCaps',
    'G081:W>W GetMapMode',
    'G082:WIP>W GetObject',
    'G083:WII>L GetPixel',
    'G084:W>W GetPolyFillMode',
    'G085:W>W GetROP2',
    'G086:W>W GetRelAbs',
    'G087:W>W GetStockObject',
    'G088:W>W GetStretchBltMode',
    'G089:W>W GetTextCharacterExtra',
    'G090:W>L GetTextColor',
    'G091:WPI>L GetTextExtent',
    'G092:WIP>W GetTextFace',
    'G093:WP>W GetTextMetrics',
    'G094:W>L GetViewportExt',
    'G095:W>L GetViewportOrg',
    'G096:W>L GetWindowExt',
    'G097:W>L GetWindowOrg',
    'G098:WIIII>W IntersectVisRect',
    'G099:WPI>W LPtoDP',
    'G100:IIIISL>W LineDDA',
    'G101:WII>W OffsetRgn',
    'G102:WII>W OffsetVisRgn',
    'G103:WII>W PtVisible',
    'G104:WP>W RectVisibleOld',
    'G105:WW>W SelectVisRgn',
    'G106:WLP>L SetBitmapBits',
    'G117:WII>L SetDCOrg',
    'G118:X>W InternalCreateDC',
    'G119:P>W AddFontResource',
    'G120:X>W GetContinuingTextExten',
    'G121:W>W Death',
    'G122:WWWWWWW>W Resurrection',
    'G123:WW>W PlayMetaFile',
    'G124:P>W GetMetaFile',
    'G125:P>W CreateMetaFile',
    'G126:W>W CloseMetaFile',
    'G127:W>W DeleteMetaFile',
    'G128:III>W MulDiv',
    'G129:W>W SaveVisRgn',
    'G130:W>W RestoreVisRgn',
    'G131:W>W InquireVisRgn',
    'G132:PPW>W SetEnvironment',
    'G133:PPW>W GetEnvironment',
    'G134:WP>W GetRgnBox',
    'G136:P>W RemoveFontResource',
    'G137:X>W GSV',
    'G138:X>W DPXlate',
    'G139:X>W SetWinViewExt',
    'G140:X>W ScaleExt',
    'G141:X>W WordSet',
    'G142:X>W RectStuff',
    'G143:X>W OffsetOrg',
    'G144:X>W LockDC',
    'G145:X>W UnlockDC',
    'G146:X>W LockUnlock',
    'G147:X>W GDI_FarFrame',
    'G148:WII>L SetBrushOrg',
    'G149:W>L GetBrushOrg',
    'G150:W>W UnrealizeObject',
    'G151:WP>W CopyMetaFile',
    'G152:X>W GDIInitApp',
    'G153:PPPP>W CreateIC',
    'G154:WL>L GetNearestColor',
    'G155:WW>W QueryAbort',
    'G156:WWW>W CreateDiscardableBitma',
    'G157:X>W CompatibleBitmap',
    'G158:X>W EnumCallback',
    'G159:W>W GetMetaFileBits',
    'G160:W>W SetMetaFileBits',
    'G161:WII>W PtInRegion',
    'G162:W>L GetBitmapDimension',
    'G163:WII>L SetBitmapDimension',
    'G164:X>W PixToLine',
    'G169:X>W IsDCDirty',
    'G170:X>W SetDCStatus',
    'G171:X>W LVBUNION',
    'G172:WIIII>W SetRectRgn',
    'G173:W>W GetClipRgn',
    'G174:X>W BLOAT',
    'G175:WWSL>W EnumMetaFile',
    'G176:WPPW>W PlayMetaFileRecord',
    'G177:X>W RCOS',
    'G178:X>W RSIN',
    'G179:W>W GetDCState',
    'G180:WW>W SetDCState',
    'G181:WP>W RectInRegionOld',
    'G182:X>W REQUESTSEM',
    'G183:X>W CLEARSEM',
    'G184:X>W STUFFVISIBLE',
    'G185:X>W STUFFINREGION',
    'G186:X>W DELETEABOVELINEFONTS',
    'G188:X>W GetTextExtentEx',
    'G190:WSL>W SetDCHook',
    'G191:WP>L GetDCHook',
    'G192:WW>W SetHookFlags',
    'G193:WPW>W SetBoundsRect',
    'G194:WPW>W GetBoundsRect',
    'G195:X>W SelectBitmap',
    'G196:W>W SetMetaFileBitsBetter',
    'G201:X>W DMBITBLT',
    'G202:X>W DMCOLORINFO',
    'G206:X>W dmEnumDFonts',
    'G207:X>W DMENUMOBJ',
    'G208:X>W DMOUTPUT',
    'G209:X>W DMPIXEL',
    'G210:X>W dmRealizeObject',
    'G211:X>W DMSTRBLT',
    'G212:X>W DMSCANLR',
    'G213:X>W BRUTE',
    'G214:X>W DMEXTTEXTOUT',
    'G215:X>W DMGETCHARWIDTH',
    'G216:X>W DMSTRETCHBLT',
    'G217:X>W DMDIBBITS',
    'G218:X>W DMSTRETCHDIBITS',
    'G219:X>W DMSETDIBTODEV',
    'G220:X>W DMTRANSPOSE',
    'G230:W>W CreatePQ',
    'G231:W>W MinPQ',
    'G232:W>W ExtractPQ',
    'G233:WWW>W InsertPQ',
    'G234:WW>W SizePQ',
    'G235:W>W DeletePQ',
    'G240:PPW>W OpenJob',
    'G241:WPW>W WriteSpool',
    'G242:WPW>W WriteDialog',
    'G243:W>W CloseJob',
    'G244:WW>W DeleteJob',
    'G245:WP>L GetSpoolJob',
    'G246:W>W StartSpoolPage',
    'G247:W>W EndSpoolPage',
    'G248:X>W QueryJob',
    'G250:PPW>W Copy',
    'G253:X>W DeleteSpoolPage',
    'G254:X>W SpoolFile',
    'G267:X>W StartDocPrintEra',
    'G268:X>W StartPagePrinter',
    'G269:X>W WritePrinter',
    'G270:X>W EndPagePrinter',
    'G271:X>W AbortPrinter',
    'G272:X>W EndDocPrinter',
    'G274:X>W ClosePrinter',
    'G280:X>W GetRealDriverInfo',
    'G281:PPLPL>L DrvSetPrinterData',
    'G282:PPPPLP>L DrvGetPrinterData',
    'G299:X>W ENGINEGETCHARWIDTHEX',
    'G300:PSL>L EngineEnumerateFont',
    'G301:P>W EngineDeleteFont',
    'G302:PPP>L EngineRealizeFont',
    'G303:PWWP>W EngineGetCharWidth',
    'G304:PW>W EngineSetFontContext',
    'G305:WPWWPLP>W EngineGetGlyphBMP',
    'G306:WPP>L EngineMakeFontDir',
    'G307:WWWP>W GetCharABCWidths',
    'G308:WWP>W GetOutlineTextMetrics',
    'G309:WWWPLPP>L GetGlyphOutline',
    'G310:WPPP>W CreateScalableFontReso',
    'G311:WLLPL>L GetFontData',
    'G312:X>W ConvertOutLineFontFile',
    'G313:PW>W GetRasterizerCaps',
    'G314:X>W EngineExtTextOut',
    'G315:LLLL>L EngineRealizeFontExt',
    'G316:X>W EngineGetCharWidthStr',
    'G317:X>W EngineGetGlyphBmpExt',
    'G330:WPSL>W EnumFontFamilies',
    'G332:WWP>W GetKerningPairs',
    'G345:W>W GetTextAlign',
    'G346:WW>W SetTextAlign',
    'G347:X>W MFDRAWTEXT',
    'G348:WIIIIIIII>W Chord',
    'G349:WL>L SetMapperFlags',
    'G350:WWWP>W GetCharWidth',
    'G351:WIIWPPWP>W ExtTextOut',
    'G352:X>W GetPhysicalFontHandle',
    'G353:X>W GetAspectRatioFilter',
    'G354:X>W ShrinkGDIHeap',
    'G355:X>W FTrapping0',
    'G360:P>W CreatePalette',
    'G361:WWW>W GDISelectPalette',
    'G362:W>W GDIRealizePalette',
    'G363:WWWP>W GetPaletteEntries',
    'G364:WWWP>W SetPaletteEntries',
    'G365:W>W RealizeDefaultPalette',
    'G366:W>W UpdateColors',
    'G367:WWWP>W AnimatePalette',
    'G368:WW>W ResizePalette',
    'G370:WL>W GetNearestPaletteIndex',
    'G372:WIILW>W ExtFloodFill',
    'G373:WW>W SetSystemPaletteUse',
    'G374:W>W GetSystemPaletteUse',
    'G375:WWWP>W GetSystemPaletteEntrie',
    'G376:WP>W ResetDC',
    'G377:WP>W StartDoc',
    'G378:W>W EndDoc',
    'G379:W>W StartPage',
    'G380:W>W EndPage',
    'G381:WS>W SetAbortProc',
    'G382:W>W AbortDoc',
    'G400:WPIIL>W FastWindowFrame',
    'G401:X>W GDIMOVEBITMAP',
    'G402:X>W GDIGETBITSGLOBAL',
    'G403:WW>W GdiInit2',
    'G404:X>W GetTTGlyphIndexMap',
    'G405:W>W FinalGdiInit',
    'G406:X>W CREATEREALBITMAPINDIRE',
    'G407:WWWWP>W CreateUserBitmap',
    'G408:X>W CREATEREALBITMAP',
    'G409:WWW>W CreateUserDiscardableB',
    'G410:>W IsValidMetaFile',
    'G411:W>W GetCurLogFont',
    'G412:W>W IsDCCurrentPalette',
    'G439:>W StretchDIBits',
    'G440:WWWWPPW>W SetDIBits',
    'G441:WWWWPPW>W GetDIBits',
    'G442:WPLPPW>W CreateDIBitmap',
    'G443:WIIIIIIWWPPW>W SetDIBitsToDevice',
    'G444:IIIIII>W CreateRoundRectRgn',
    'G445:WW>W CreateDIBPatternBrush',
    'G449:X>W DEVICECOLORMATCH',
    'G450:WPPW>W PolyPolygon',
    'G451:PPWW>W CreatePolyPolygonRgn',
    'G452:WWWW>L GdiSeeGdiDo',
    'G460:X>W GDITASKTERMINATION',
    'G461:WW>W SetObjectOwner',
    'G462:W>W IsGDIObject',
    'G463:WW>W MakeObjectPrivate',
    'G464:X>W FIXUPBOGUSPUBLISHERMET',
    'G465:WP>W RectVisible',
    'G466:WP>W RectInRegion',
    'G467:X>W UNICODETOANSI',
    'G468:WP>W GetBitmapDimensionEx',
    'G469:WP>W GetBrushOrgEx',
    'G470:WP>W GetCurrentPositionEx',
    'G471:WPIP>W GetTextExtentPoint',
    'G472:WP>W GetViewportExtEx',
    'G473:WP>W GetViewportOrgEx',
    'G474:WP>W GetWindowExtEx',
    'G475:WP>W GetWindowOrgEx',
    'G476:WIIP>W OffsetViewportOrgEx',
    'G477:WIIP>W OffsetWindowOrgEx',
    'G478:WIIP>W SetBitmapDimensionEx',
    'G479:WIIP>W SetViewportExtEx',
    'G480:WIIP>W SetViewportOrgEx',
    'G481:WIIP>W SetWindowExtEx',
    'G482:WIIP>W SetWindowOrgEx',
    'G483:WIIP>W MoveToEx',
    'G484:WIIIIP>W ScaleViewportExtEx',
    'G485:WIIIIP>W ScaleWindowExtEx',
    'G486:WP>W GetAspectRatioFilterEx',
    'G489:WPWPLL>W CreateDIBSection',
    'G490:X>W CloseEnhMetafile',
    'G491:X>W CopyEnhMetafile',
    'G492:X>W CreateEnhMetafile',
    'G493:X>W DeleteEnhMetafile',
    'G495:X>W GDIComment',
    'G496:X>W GetEnhMetafile',
    'G497:X>W GetEnhMetafileBits',
    'G498:X>W GetEnhMetafileDescript',
    'G499:X>W GetEnhMetafileHeader',
    'G501:X>W GetEnhMetafilePaletteE',
    'G502:WPW>W PolyBezier',
    'G503:WPW>W PolyBezierTo',
    'G504:X>W PlayEnhMetafileRecord',
    'G505:X>W SetEnhMetafileBits',
    'G506:X>W SetMetaRgn',
    'G508:WWW>W ExtSelectClipRgn',
    'G511:W>W AbortPath',
    'G512:W>W BeginPath',
    'G513:W>W CloseFigure',
    'G514:W>W EndPath',
    'G515:W>W FillPath',
    'G516:W>W FlattenPath',
    'G517:WPPW>W GetPath',
    'G518:W>W PathToRegion',
    'G519:WW>W SelectClipPath',
    'G520:W>W StrokeAndFillPath',
    'G521:W>W StrokePath',
    'G522:W>W WidenPath',
    'G523:X>W ExtCreatePen',
    'G524:W>W GetArcDirection',
    'G525:WW>W SetArcDirection',
    'G526:X>W GetMiterLimit',
    'G527:X>W SetMiterLimit',
    'G528:X>W GDIParametersInfo',
    'G529:W>W CreateHalftonePalette',
    'G530:>W RawTextOut',
    'G531:>W RawExtTextOut',
    'G532:WPW>W RawGetTextExtent',
    'G536:>W BiDiLayout',
    'G538:>W BiDiCreateTabString',
    'G540:>W BiDiGlyphOut',
    'G543:>W BiDiGetStringExtent',
    'G555:>W BiDiDeleteString',
    'G556:>W BiDiSetDefaults',
    'G558:>W BiDiGetDefaults',
    'G560:>W BiDiShape',
    'G561:>W BiDiFontComplement',
    'G564:>W BiDiSetKashida',
    'G565:>W BiDiKExtTextOut',
    'G566:>W BiDiShapeEx',
    'G569:>W BiDiCreateStringEx',
    'G571:>W GetTextExtentRtoL',
    'G572:>W GetHDCCharSet',
    'G573:>W BiDiLayoutEx',
    'G602:WWWP>W SetDIBColorTable',
    'G603:WWWP>W GetDIBColorTable',
    'G604:WL>W SetSolidBrush',
    'G605:W>W SysDeleteObject',
    'G606:WLW>W SetMagicColors',
    'G607:WLP>L GetRegionData',
    'G608:X>W ExtCreateRegion',
    'G609:L>W GdiFreeResources',
    'G610:LLLW>W GdiSignalProc32',
    'G611:X>W GetRandomRgn',
    'G612:W>W GetTextCharset',
    'G613:WPSLL>W EnumFontFamiliesEx',
    'G614:X>W AddLpkToGDI',
    'G615:X>W GetCharacterPlacement',
    'G616:W>L GetFontLanguageInfo',
    'G650:X>W BuildInverseTableDIB',
    'G701:X>W GDITHKCONNECTIONDATALS',
    'G702:X>W FT_GDIFTHKTHKCONNECTIO',
    'G703:X>W FDTHKCONNECTIONDATASL',
    'G704:X>W ICMTHKCONNECTIONDATASL',
    'G820:X>W ICMCreateTransform',
    'G821:X>W ICMDeleteTransform',
    'G822:X>W ICMTranslateRGB',
    'G823:X>W ICMTranslateRGBs',
    'G824:X>W ICMCheckColorsInGamut',
    'B001:P>W Inquire',
    'B002:SP>W Enable',
    'B003:>W Disable',
    'B004:WWPPW>W ToAscii',
    'B005:PP>W AnsiToOem',
    'B006:PP>W OemToAnsi',
    'B007:W>W SetSpeed',
    'B009:X>W INQUIREEX',
    'B010:X>W TOASCIIEX',
    'B011:X>W VKKEYSCANEX',
    'B012:X>W MAPVIRTUALKEYEX',
    'B013:X>W NEWTABLEEX',
    'B014:X>W __EXPORTEDSTUB',
    'B100:W>L ScreenSwitchEnable',
    'B128:W>L OemKeyScan',
    'B129:W>W VkKeyScan',
    'B130:W>W GetKeyboardType',
    'B131:WW>W MapVirtualKey',
    'B132:>W GetKBCodePage',
    'B133:LPW>W GetKeyNameText',
    'B134:PPW>W AnsiToOemBuff',
    'B135:PPW>W OemToAnsiBuff',
    'L001:WW>L LZCopy',
    'L002:PPW>W LZOpenFile',
    'L003:W>W LZInit',
    'L004:WLW>L LZSeek',
    'L005:WPW>W LZRead',
    'L006:W>W LZClose',
    'L007:>W LZStart',
    'L008:WW>L CopyLZFile',
    'L009:>W LZDone',
    'L010:PP>W GetExpandedName',
    'S001:LPP>L RegOpenKey',
    'S002:LPP>L RegCreateKey',
    'S003:L>L RegCloseKey',
    'S004:LP>L RegDeleteKey',
    'S005:LPLPL>L RegSetValue',
    'S006:LPPP>L RegQueryValue',
    'S007:LLPL>L RegEnumKey',
    'S009:WW>W DragAcceptFiles',
    'S011:WIPI>W DragQueryFile',
    'S012:W>W DragFinish',
    'S013:WP>W DragQueryPoint',
    'S020:WPPPPI>W ShellExecute',
    'S021:PPP>W FindExecutable',
    'S022:WPPW>W ShellAbout',
    'S033:WWWL>W AboutDlgProc',
    'S034:WPI>W ExtractIcon',
    'S036:WPP>W ExtractAssociatedIcon',
    'S037:PW>L DoEnvironmentSubst',
    'S038:P>L FindEnvironmentString',
    'S039:WPIW>W InternalExtractIcon',
    'S040:PWPPW>W ExtractIconEx',
    'S101:LWWWLW>L DllEntryPoint',
    'S102:WW>W RegisterShellHook',
    'S103:WWL>L ShellHookProc',
    'S157:X>W RESTARTDIALOG',
    'S262:L>W DriveType',
    'S401:X>W SHCHECKDRIVE',
    'M001:WWWP>L WEP',
    'M002:PW>L sndPlaySound',
    'M003:PWL>L PlaySound',
    'M004:LWWWLW>L DllEntryPoint',
    'M005:>L mmsystemGetVersion',
    'M006:LWWLL>L DriverProc',
    'M008:>L WMMMidiRunOnce',
    'M030:P>W OutputDebugStr',
    'M031:LWWWLLL>L DriverCallback',
    'M032:>L StackEnter',
    'M033:>L StackLeave',
    'M034:X>W MMDRVINSTALL',
    'M101:>L joyGetNumDevs',
    'M102:WPW>L joyGetDevCaps',
    'M103:WP>L joyGetPos',
    'M104:WP>L joyGetThreshold',
    'M105:W>L joyReleaseCapture',
    'M106:WWWW>L joySetCapture',
    'M107:WW>L joySetThreshold',
    'M109:W>L joySetCalibration',
    'M110:WP>L joyGetPosEx',
    'M111:X>W JOYCONFIGCHANGED',
    'M201:>L midiOutGetNumDevs',
    'M202:WPW>L midiOutGetDevCaps',
    'M203:WPW>L midiOutGetErrorText',
    'M204:PWLLL>L midiOutOpen',
    'M205:W>L midiOutClose',
    'M206:WSW>L midiOutPrepareHeader',
    'M207:WSW>L midiOutUnprepareHeader',
    'M208:WL>L midiOutShortMsg',
    'M209:WSW>L midiOutLongMsg',
    'M210:W>L midiOutReset',
    'M211:WP>L midiOutGetVolume',
    'M212:WL>L midiOutSetVolume',
    'M213:WWPW>L midiOutCachePatches',
    'M214:WWPW>L midiOutCacheDrumPatche',
    'M215:WP>L midiOutGetID',
    'M216:WWLL>L midiOutMessage',
    'M250:WPL>L midiStreamProperty',
    'M251:PPLLLL>L midiStreamOpen',
    'M252:W>L midiStreamClose',
    'M253:WPW>L midiStreamPosition',
    'M254:WPW>L midiStreamOut',
    'M255:W>L midiStreamPause',
    'M256:W>L midiStreamRestart',
    'M257:W>L midiStreamStop',
    'M301:>L midiInGetNumDevs',
    'M302:WPW>L midiInGetDevCaps',
    'M303:WPW>L midiInGetErrorText',
    'M304:PWLLL>L midiInOpen',
    'M305:W>L midiInClose',
    'M306:WSW>L midiInPrepareHeader',
    'M307:WSW>L midiInUnprepareHeader',
    'M308:WSW>L midiInAddBuffer',
    'M309:W>L midiInStart',
    'M310:W>L midiInStop',
    'M311:W>L midiInReset',
    'M312:WP>L midiInGetID',
    'M313:WWLL>L midiInMessage',
    'M350:>L auxGetNumDevs',
    'M351:WPW>L auxGetDevCaps',
    'M352:WP>L auxGetVolume',
    'M353:WL>L auxSetVolume',
    'M354:WWLL>L auxOutMessage',
    'M401:>L waveOutGetNumDevs',
    'M402:WPW>L waveOutGetDevCaps',
    'M403:WPW>L waveOutGetErrorText',
    'M404:PWPLLL>L waveOutOpen',
    'M405:W>L waveOutClose',
    'M406:WSW>L waveOutPrepareHeader',
    'M407:WSW>L waveOutUnprepareHeader',
    'M408:WSW>L waveOutWrite',
    'M409:W>L waveOutPause',
    'M410:W>L waveOutRestart',
    'M411:W>L waveOutReset',
    'M412:WPW>L waveOutGetPosition',
    'M413:WP>L waveOutGetPitch',
    'M414:WL>L waveOutSetPitch',
    'M415:WP>L waveOutGetVolume',
    'M416:WL>L waveOutSetVolume',
    'M417:WP>L waveOutGetPlaybackRate',
    'M418:WL>L waveOutSetPlaybackRate',
    'M419:W>L waveOutBreakLoop',
    'M420:WP>L waveOutGetID',
    'M421:WWLL>L waveOutMessage',
    'M501:>L waveInGetNumDevs',
    'M502:WPW>L waveInGetDevCaps',
    'M503:WPW>L waveInGetErrorText',
    'M504:PWPLLL>L waveInOpen',
    'M505:W>L waveInClose',
    'M506:WSW>L waveInPrepareHeader',
    'M507:WSW>L waveInUnprepareHeader',
    'M508:WSW>L waveInAddBuffer',
    'M509:W>L waveInStart',
    'M510:W>L waveInStop',
    'M511:W>L waveInReset',
    'M512:WPW>L waveInGetPosition',
    'M513:WP>L waveInGetID',
    'M514:WWLL>L waveInMessage',
    'M601:PW>L timeGetSystemTime',
    'M602:WWSLW>L timeSetEvent',
    'M603:W>L timeKillEvent',
    'M604:PW>L timeGetDevCaps',
    'M605:W>L timeBeginPeriod',
    'M606:W>L timeEndPeriod',
    'M607:>L timeGetTime',
    'M701:WWLL>L mciSendCommand',
    'M702:PPWW>L mciSendString',
    'M703:P>L mciGetDeviceID',
    'M705:WPW>L mciLoadCommandResource',
    'M706:LPW>L mciGetErrorString',
    'M707:WL>L mciSetDriverData',
    'M708:W>L mciGetDriverData',
    'M710:W>L mciDriverYield',
    'M711:WWW>L mciDriverNotify',
    'M712:P>L mciExecute',
    'M713:W>L mciFreeCommandResource',
    'M714:WPL>L mciSetYieldProc',
    'M715:LP>L mciGetDeviceIDFromElem',
    'M716:WP>L mciGetYieldProc',
    'M717:W>L mciGetCreatorTask',
    'M800:>L mixerGetNumDevs',
    'M801:WPW>L mixerGetDevCaps',
    'M802:PWLLL>L mixerOpen',
    'M803:W>L mixerClose',
    'M804:WWLL>L mixerMessage',
    'M805:WPL>L mixerGetLineInfo',
    'M806:WPL>L mixerGetID',
    'M807:WPL>L mixerGetLineControls',
    'M808:WPL>L mixerGetControlDetails',
    'M809:WPL>L mixerSetControlDetails',
    'M900:LPL>L mmTaskCreate',
    'M902:W>L mmTaskBlock',
    'M903:W>L mmTaskSignal',
    'M904:>W mmGetCurrentTask',
    'M905:>L mmTaskYield',
    'E001:R>R __fpMath',
    'E003:PW>W __WinEm87Info',
    'E004:PW>W __WinEm87Restore',
    'E005:PW>W __WinEm87Save',
    'V002:PPPP>L GetFileResourceSize',
    'V003:PPPLLP>L GetFileResource',
    'V006:PP>L GetFileVersionInfoSize',
    'V007:PLLP>L GetFileVersionInfo',
    'V008:WPPPPPPP>L VerFindFile',
    'V009:WPPPPPPP>L VerInstallFile',
    'V010:WPW>L VerLanguageName',
    'V011:SPPP>L VerQueryValue',
    'V020:X>W GETFILEVERSIONINFORAW',
    'C001:S>W GetOpenFileName',
    'C002:S>W GetSaveFileName',
    'C005:P>W ChooseColor',
    'C006:WWWL>L FileOpenDlgProc',
    'C007:WWWL>L FileSaveDlgProc',
    'C008:WWWL>L ColorDlgProc',
    'C011:S>W FindText',
    'C012:S>W ReplaceText',
    'C013:WWWL>L FindTextDlgProc',
    'C014:WWWL>L ReplaceTextDlgProc',
    'C015:P>W ChooseFont',
    'C016:WWWL>W FormatCharDlgProc',
    'C018:PPWL>W FontStyleEnumProc',
    'C019:PPWL>W FontFamilyEnumProc',
    'C020:P>W PrintDlg',
    'C021:WWWL>L PrintDlgProc',
    'C022:WWWL>L PrintSetupDlgProc',
    'C026:>L CommDlgExtendedError',
    'C027:PPW>W GetFileTitle',
    'T050:W>W GlobalHandleToSel',
    'T051:PW>W GlobalFirst',
    'T052:PW>W GlobalNext',
    'T053:P>W GlobalInfo',
    'T054:PW>W GlobalEntryHandle',
    'T055:PWW>W GlobalEntryModule',
    'T056:PW>W LocalInfo',
    'T057:PW>W LocalFirst',
    'T058:P>W LocalNext',
    'T059:P>W ModuleFirst',
    'T060:P>W ModuleNext',
    'T061:PP>W ModuleFindName',
    'T062:PW>W ModuleFindHandle',
    'T063:P>W TaskFirst',
    'T064:P>W TaskNext',
    'T065:PW>W TaskFindHandle',
    'T066:PW>W StackTraceFirst',
    'T067:PWWWW>W StackTraceCSIPFirst',
    'T068:P>W StackTraceNext',
    'T069:X>W ClassFirst',
    'T070:X>W ClassNext',
    'T071:P>W SystemHeapInfo',
    'T072:P>W MemManInfo',
    'T073:WSW>W NotifyRegister',
    'T074:W>W NotifyUnregister',
    'T075:WS>W InterruptRegister',
    'T076:W>W InterruptUnRegister',
    'T077:WW>W TerminateApp',
    'T078:WLPL>L MemoryRead',
    'T079:WLPL>L MemoryWrite',
    'T080:P>W TimerCount',
    'T081:X>W TASKSETCSIP',
    'T082:X>W TASKGETCSIP',
    'T083:X>W TASKSWITCH',
    'T084:PW>W Local32Info',
    'T085:PW>W Local32First',
    'T086:P>W Local32Next',
    'Y001:WW>L InquireSystem',
    'Y002:WS>W CreateSystemTimer',
    'Y003:W>W KillSystemTimer',
    'Y004:>W EnableSystemTimers',
    'Y005:>W DisableSystemTimers',
    'Y006:>L GetSystemMSecCount',
    'Y007:>W Get80x87SaveSize',
    'Y008:P>W Save80x87State',
    'Y009:P>W Restore80x87State',
    'Y013:X>W INQUIRELONGINTS',
    'Y020:W>W A20_Proc',
    'D001:X>W BitBlt',
    'D002:X>W ColorInfo',
    'D003:X>W Control',
    'D004:X>W Disable',
    'D005:X>W Enable',
    'D006:X>W EnumFonts',
    'D007:X>W EnumObj',
    'D008:X>W Output',
    'D009:X>W Pixel',
    'D010:X>W RealizeObject',
    'D011:X>W StrBlt',
    'D012:X>W ScanLR',
    'D013:X>W DeviceMode',
    'D014:X>W ExtTextOut',
    'D015:X>W GetCharWidth',
    'D016:X>W DeviceBitmap',
    'D017:X>W FastBorder',
    'D018:X>W SetAttribute',
    'D019:X>W DeviceBitmapBits',
    'D020:X>W CreateBitmap',
    'D021:X>W DIBScreenBlt',
    'D022:X>W SetPalette',
    'D023:X>W GetPalette',
    'D024:X>W SetPaletteTranslate',
    'D025:X>W GetPaletteTranslate',
    'D026:X>W UpdateColors',
    'D027:X>W StretchBlt',
    'D028:X>W StretchDIBits',
    'D029:X>W SelectBitmap',
    'D030:X>W BitmapBits',
    'D031:X>W ReEnable',
    'D039:X>W DIBBlt',
    'D040:X>W CreateDIBitmap',
    'D041:X>W DIBToDevice',
    'D090:X>W Do_Polylines',
    'D091:X>W Do_Scanlines',
    'D092:X>W SaveScreenBitmap',
    'D101:P>W Inquire',
    'D102:P>W SetCursor',
    'D103:WW>W MoveCursor',
    'D104:>W CheckCursor',
    'D400:X>W PExtTextOut',
    'D401:X>W PStrBlt',
    'D402:X>W RExtTextOut',
    'D403:X>W RStrBlt',
    'D450:WP>L GetDriverResourceID',
    'D500:W>W UserRepaintDisable',
    'D501:X>W ORDINAL_ONLY1',
    'D502:X>W ORDINAL_ONLY2',
    'D600:X>W InkReady',
    'D601:X>W GetLPDevice',
    'O001:>W OpenSound',
    'O002:>W CloseSound',
    'O003:WW>W SetVoiceQueueSize',
    'O004:WWWW>W SetVoiceNote',
    'O005:WWWWW>W SetVoiceAccent',
    'O006:WWW>W SetVoiceEnvelope',
    'O007:WW>W SetSoundNoise',
    'O008:WLW>W SetVoiceSound',
    'O009:>W StartSound',
    'O010:>W StopSound',
    'O011:W>W WaitSoundState',
    'O012:>W SyncAllVoices',
    'O013:W>W CountVoiceNotes',
    'O014:>L GetThresholdEvent',
    'O015:>W GetThresholdStatus',
    'O016:WW>W SetVoiceThreshold',
    'O017:>W DoBeep',
    'O018:X>W MYOPENSOUND');

{ ==================================================================== }
{ Partie 14 - Sous-systeme Win16 : anneau 3, LDT, passerelles, memoire }
{ ==================================================================== }
{ Les programmes Windows 3.x (format NE) s'executent comme sous
  Windows 95 : en mode protege 16 bits, a l'anneau 3, dans des
  segments decrits par une LDT. Une interruption survenue dans du code
  16 bits bascule sur la pile de l'anneau 0 de la tache (TSS.ESP0).
  Les appels d'API passent par une passerelle d'appel (GDT 38h) :
  chaque fonction importee est une petite souche 16 bits
  (push n / call far 3Bh:0 / retf taille). Les rappels (procedures de
  fenetre 16 bits...) sont appeles par Call16 et reviennent par la
  passerelle 43h.
  Selecteurs : (indice LDT * 8) + 7 ; increment des blocs > 64 Ko
  (__AHINCR) : 8. }

Const
  LdtMax = 4096;
  SelGateApi = $3B;
  SelGateCb = $43;
  W16CbOfs = $FFF0;        { souche de retour des rappels }

Var
  Ldt : Array[0..LdtMax * 2 - 1] Of LongInt;
  LdtUsed : Array[0..LdtMax - 1] Of Boolean;
  { blocs globaux : taille, nombre de tuiles, adresse, proprietaire }
  GSize, GTiles, GLin, GOwner, GLock : Array[0..LdtMax - 1] Of LongInt;
  Tss : Array[0..31] Of LongInt;
  W16ThunkSel, W16ThunkLin : LongInt;
  EnterStub, ApiGateStub, CbGateStub : LongInt;
  Ret16Ax, Ret16Dx, W16Cf : LongInt;
  Ctx16 : Array[0..MaxThread * 16 - 1] Of LongInt;
  Ctx16N : Array[0..MaxThread - 1] Of LongInt;
  { pile 16 bits courante de chaque tache (dernier appel d'API) }
  T16Ss, T16Sp, T16Ds, T16Mod : Array[0..MaxThread - 1] Of LongInt;
  { bloc de parametres de Call16 }
  C16 : Array[0..15] Of LongInt;
  W16Ready : Boolean;

{ ------------------------------------------------------------------ }
{ Descripteurs                                                       }
{ ------------------------------------------------------------------ }

{ Acc : $FA code 16 bits, $F2 donnees 16 bits (anneau 3) }
Procedure DescSet(I, Base, Limit, Acc : LongInt);
Var G : LongInt;
Begin
  G := 0;
  If Limit > $FFFFF Then
  Begin
    Limit := Limit Shr 12;
    G := $800000;
  End;
  Ldt[I * 2] := (Limit And $FFFF) Or ((Base And $FFFF) Shl 16);
  Ldt[I * 2 + 1] := ((Base Shr 16) And $FF) Or (Acc Shl 8) Or
                    (Limit And $F0000) Or G Or (Base And LongInt($FF000000));
End;

Function SelBase(Sel : LongInt) : LongInt;
Var I : LongInt;
Begin
  SelBase := 0;
  If (Sel And 4) = 0 Then Exit;
  I := (Sel Shr 3) And $1FFF;
  If I >= LdtMax Then Exit;
  SelBase := ((Ldt[I * 2] Shr 16) And $FFFF) Or
             ((Ldt[I * 2 + 1] And $FF) Shl 16) Or
             (Ldt[I * 2 + 1] And LongInt($FF000000));
End;

Function SelLimit(Sel : LongInt) : LongInt;
Var I, L : LongInt;
Begin
  SelLimit := 0;
  If (Sel And 4) = 0 Then Exit;
  I := (Sel Shr 3) And $1FFF;
  If I >= LdtMax Then Exit;
  L := (Ldt[I * 2] And $FFFF) Or (Ldt[I * 2 + 1] And $F0000);
  If (Ldt[I * 2 + 1] And $800000) <> 0 Then L := (L Shl 12) Or $FFF;
  SelLimit := L;
End;

Function SelValid(Sel : LongInt) : Boolean;
Var I : LongInt;
Begin
  I := (Sel Shr 3) And $1FFF;
  SelValid := ((Sel And 4) <> 0) And (I > 0) And (I < LdtMax) And
              LdtUsed[I];
End;

{ N selecteurs consecutifs ; selecteur du premier ou 0 }
Function SelAlloc(N : LongInt) : LongInt;
Var I, K, Run : LongInt;
Begin
  SelAlloc := 0;
  Run := 0;
  For I := 1 To LdtMax - 1 Do
  Begin
    If LdtUsed[I] Then Run := 0 Else Inc(Run);
    If Run = N Then
    Begin
      For K := I - N + 1 To I Do
      Begin
        LdtUsed[K] := True;
        GSize[K] := 0; GTiles[K] := 0; GLin[K] := 0; GLock[K] := 0;
        GOwner[K] := HeapOwner;
        Ldt[K * 2] := 0; Ldt[K * 2 + 1] := 0;
      End;
      SelAlloc := ((I - N + 1) Shl 3) Or 7;
      Exit;
    End;
  End;
  KLog('Win16 : LDT pleine');
End;

Procedure SelFree(Sel, N : LongInt);
Var I, K : LongInt;
Begin
  I := (Sel Shr 3) And $1FFF;
  For K := I To I + N - 1 Do
    If (K > 0) And (K < LdtMax) Then
    Begin
      LdtUsed[K] := False;
      Ldt[K * 2] := 0; Ldt[K * 2 + 1] := 0;
      GSize[K] := 0; GTiles[K] := 0;
    End;
End;

{ Pointeur 16:16 -> adresse lineaire (0 si nul) }
Function Lin16(P : LongInt) : LongInt;
Var S : LongInt;
Begin
  S := (P Shr 16) And $FFFF;
  If S = 0 Then Lin16 := 0
  Else Lin16 := SelBase(S) + (P And $FFFF);
End;

Function MakeFar(Sel, Ofs : LongInt) : LongInt;
Begin
  MakeFar := ((Sel And $FFFF) Shl 16) Or (Ofs And $FFFF);
End;

{ ------------------------------------------------------------------ }
{ Memoire globale 16 bits : poignee = selecteur                     }
{ ------------------------------------------------------------------ }

Procedure GDescs(I, Lin, Size, Tiles, Acc : LongInt);
Var K : LongInt;
Begin
  For K := 0 To Tiles - 1 Do
    DescSet(I + K, Lin + K * $10000, Size - K * $10000 - 1, Acc);
End;

Function GAlloc16(Size : LongInt; Code : Boolean) : LongInt;
Var Lin, Tiles, Sel, I, Acc : LongInt;
Begin
  GAlloc16 := 0;
  If Size <= 0 Then Size := 1;
  Size := (Size + 15) And Not 15;
  Tiles := (Size + $FFFF) Div $10000;
  Lin := KAlloc(Size);
  If Lin = 0 Then Exit;
  FillMem(Lin, Size, 0);
  Sel := SelAlloc(Tiles);
  If Sel = 0 Then
  Begin
    KFree(Lin);
    Exit;
  End;
  I := Sel Shr 3;
  If Code Then Acc := $FA Else Acc := $F2;
  GDescs(I, Lin, Size, Tiles, Acc);
  GSize[I] := Size; GTiles[I] := Tiles; GLin[I] := Lin;
  GAlloc16 := Sel;
End;

Function GIdx(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  GIdx := -1;
  If Not SelValid(H) Then Exit;
  I := (H Shr 3) And $1FFF;
  If GTiles[I] > 0 Then GIdx := I;
End;

Procedure GFree16(H : LongInt);
Var I : LongInt;
Begin
  I := GIdx(H);
  If I < 0 Then Exit;
  KFree(GLin[I]);
  SelFree(H, GTiles[I]);
End;

Function GReAlloc16(H, Size : LongInt) : LongInt;
Var I, Lin, Tiles, Sel, J, Acc : LongInt;
Begin
  GReAlloc16 := 0;
  I := GIdx(H);
  If I < 0 Then Exit;
  If Size <= 0 Then Size := 1;
  Size := (Size + 15) And Not 15;
  Tiles := (Size + $FFFF) Div $10000;
  Lin := KAlloc(Size);
  If Lin = 0 Then Exit;
  FillMem(Lin, Size, 0);
  MoveMem(GLin[I], Lin, Min(Size, GSize[I]));
  KFree(GLin[I]);
  Acc := (Ldt[I * 2 + 1] Shr 8) And $FF;
  If Tiles <= GTiles[I] Then
  Begin
    If Tiles < GTiles[I] Then
      SelFree(((I + Tiles) Shl 3) Or 7, GTiles[I] - Tiles);
    Sel := H;
    J := I;
  End
  Else
  Begin
    Sel := SelAlloc(Tiles);
    If Sel = 0 Then Exit;
    SelFree(H, GTiles[I]);
    J := Sel Shr 3;
  End;
  GDescs(J, Lin, Size, Tiles, Acc);
  GSize[J] := Size; GTiles[J] := Tiles; GLin[J] := Lin;
  GReAlloc16 := Sel;
End;

{ Liberer les blocs et selecteurs d'un proprietaire (fin de tache) }
Procedure GFreeOwner(Own : LongInt);
Var I : LongInt;
Begin
  For I := 1 To LdtMax - 1 Do
    If LdtUsed[I] And (GOwner[I] = Own) Then
    Begin
      If GTiles[I] > 0 Then KFree(GLin[I]);
      LdtUsed[I] := False;
      Ldt[I * 2] := 0; Ldt[I * 2 + 1] := 0;
      GTiles[I] := 0;
    End;
End;

{ ------------------------------------------------------------------ }
{ Tas local d'un segment de donnees (LocalAlloc) : blocs precedes   }
{ d'un en-tete (mot taille totale, mot 1 si occupe)                  }
{ ------------------------------------------------------------------ }

Const
  MaxLHeap = 32;

Var
  LHSel, LHStart, LHEnd : Array[0..MaxLHeap - 1] Of LongInt;

Function LHeapOf(Sel : LongInt) : LongInt;
Var I : LongInt;
Begin
  LHeapOf := -1;
  For I := 0 To MaxLHeap - 1 Do
    If (LHSel[I] = (Sel Or 3)) And (LHSel[I] <> 0) Then
    Begin
      LHeapOf := I;
      Exit;
    End;
End;

Function LocalInitK(Sel, Start, Stop : LongInt) : Boolean;
Var I, B : LongInt;
Begin
  LocalInitK := False;
  If Not SelValid(Sel) Then Exit;
  I := LHeapOf(Sel);
  If I < 0 Then
    For B := MaxLHeap - 1 DownTo 0 Do
      If LHSel[B] = 0 Then I := B;
  If I < 0 Then Exit;
  Start := (Start + 3) And Not 3;
  If Stop > SelLimit(Sel) Then Stop := SelLimit(Sel) + 1;
  If Stop > $FFF0 Then Stop := $FFF0;
  If Stop - Start < 16 Then Exit;
  LHSel[I] := Sel Or 3; LHStart[I] := Start; LHEnd[I] := Stop;
  B := SelBase(Sel);
  MemW[0:B + Start] := Stop - Start;
  MemW[0:B + Start + 2] := 0;
  { InstanceData : pLocalHeap }
  MemW[0:B + 6] := Start;
  LocalInitK := True;
End;

Function LocalAllocK(Sel, Flags, Size : LongInt) : LongInt;
Var H, B, P, Sz, Need, R : LongInt;
Begin
  LocalAllocK := 0;
  H := LHeapOf(Sel);
  If H < 0 Then Exit;
  B := SelBase(Sel);
  If Size <= 0 Then Size := 1;
  Need := ((Size + 3) And Not 3) + 4;
  { fusion des blocs libres consecutifs puis premier ajuste }
  P := LHStart[H];
  While P < LHEnd[H] Do
  Begin
    Sz := MemW[0:B + P];
    If Sz < 4 Then Exit;
    If MemW[0:B + P + 2] = 0 Then
    Begin
      While (P + Sz < LHEnd[H]) And (MemW[0:B + P + Sz + 2] = 0) And
            (MemW[0:B + P + Sz] >= 4) Do
      Begin
        Sz := Sz + MemW[0:B + P + Sz];
        MemW[0:B + P] := Sz;
      End;
      If Sz >= Need Then
      Begin
        If Sz - Need >= 8 Then
        Begin
          MemW[0:B + P + Need] := Sz - Need;
          MemW[0:B + P + Need + 2] := 0;
          MemW[0:B + P] := Need;
        End;
        MemW[0:B + P + 2] := 1;
        R := P + 4;
        FillMem(B + R, MemW[0:B + P] - 4, 0);
        LocalAllocK := R;
        Exit;
      End;
    End;
    P := P + Sz;
  End;
End;

Function LocalSizeK(Sel, Hd : LongInt) : LongInt;
Var B : LongInt;
Begin
  LocalSizeK := 0;
  If (Hd < 4) Or (LHeapOf(Sel) < 0) Then Exit;
  B := SelBase(Sel);
  LocalSizeK := MemW[0:B + Hd - 4] - 4;
End;

Procedure LocalFreeK(Sel, Hd : LongInt);
Begin
  If (Hd < 4) Or (LHeapOf(Sel) < 0) Then Exit;
  MemW[0:SelBase(Sel) + Hd - 2] := 0;
End;

Function LocalReAllocK(Sel, Hd, Size, Flags : LongInt) : LongInt;
Var N, Old : LongInt;
Begin
  LocalReAllocK := 0;
  If Hd = 0 Then Exit;
  Old := LocalSizeK(Sel, Hd);
  If (Size <= Old) And (Size > 0) Then
  Begin
    LocalReAllocK := Hd;
    Exit;
  End;
  N := LocalAllocK(Sel, Flags, Size);
  If N = 0 Then Exit;
  MoveMem(SelBase(Sel) + Hd, SelBase(Sel) + N, Min(Old, Size));
  LocalFreeK(Sel, Hd);
  LocalReAllocK := N;
End;

{ ------------------------------------------------------------------ }
{ Passage a l'anneau 3 et retour                                     }
{ ------------------------------------------------------------------ }

Procedure PutB(Var A : LongInt; B : LongInt);
Begin
  Mem[0:A] := B And $FF;
  Inc(A);
End;

Procedure PutD(Var A : LongInt; D : LongInt);
Begin
  MemL[0:A] := D;
  A := A + 4;
End;

Function CbFinish : LongInt;
Begin
  CbFinish := Ctx16[CurT * 16 + Ctx16N[CurT] - 1];
End;

Procedure W16ApiEntry(Frame : LongInt); Forward;

{ Souches en code machine (adresses lineaires, segment de code 08h) }
Procedure BuildW16Stubs;
Var A, Ret : LongInt;
Begin
  A := KAlloc(512);
  { EnterStub : EAX = bloc C16 (CS, IP, SS, SP, DS, ES, AX, BX, CX, DX,
    SI, DI, BP, adresse de sauvegarde d'ESP) }
  EnterStub := A;
  PutB(A, $55); PutB(A, $53); PutB(A, $56); PutB(A, $57);
  PutB(A, $8B); PutB(A, $50); PutB(A, 52);          { mov edx,[eax+52] }
  Ret := EnterStub + 96;
  PutB(A, $68); PutD(A, Ret);                       { push Ret }
  PutB(A, $89); PutB(A, $22);                       { mov [edx],esp }
  PutB(A, $89); PutB(A, $25); PutD(A, TssBase + 4); { mov [esp0],esp }
  PutB(A, $8B); PutB(A, $48); PutB(A, 56);          { mov ecx,[eax+56] }
  PutB(A, $89); PutB(A, $21);                       { mov [ecx],esp }
  PutB(A, $FF); PutB(A, $70); PutB(A, 8);           { push [eax+8] SS }
  PutB(A, $FF); PutB(A, $70); PutB(A, 12);          { push [eax+12] SP }
  PutB(A, $68); PutD(A, $3202);                     { push EFLAGS }
  PutB(A, $FF); PutB(A, $30);                       { push [eax] CS }
  PutB(A, $FF); PutB(A, $70); PutB(A, 4);           { push [eax+4] IP }
  PutB(A, $8B); PutB(A, $58); PutB(A, 28);          { mov ebx,[eax+28] }
  PutB(A, $8B); PutB(A, $48); PutB(A, 32);          { mov ecx,[eax+32] }
  PutB(A, $8B); PutB(A, $50); PutB(A, 36);          { mov edx,[eax+36] }
  PutB(A, $8B); PutB(A, $70); PutB(A, 40);          { mov esi,[eax+40] }
  PutB(A, $8B); PutB(A, $78); PutB(A, 44);          { mov edi,[eax+44] }
  PutB(A, $8B); PutB(A, $68); PutB(A, 48);          { mov ebp,[eax+48] }
  PutB(A, $FF); PutB(A, $70); PutB(A, 20);          { push [eax+20] ES }
  PutB(A, $FF); PutB(A, $70); PutB(A, 16);          { push [eax+16] DS }
  PutB(A, $8B); PutB(A, $40); PutB(A, 24);          { mov eax,[eax+24] }
  PutB(A, $1F); PutB(A, $07);                       { pop ds ; pop es }
  PutB(A, $CF);                                     { iretd }
  A := Ret;
  PutB(A, $5F); PutB(A, $5E); PutB(A, $5B); PutB(A, $5D);
  PutB(A, $C3);
  { ApiGateStub : entree de la passerelle d'appel des API }
  A := EnterStub + 128;
  ApiGateStub := A;
  PutB(A, $60); PutB(A, $1E); PutB(A, $06);         { pushad ds es }
  PutB(A, $66); PutB(A, $B8); PutB(A, $10); PutB(A, 0);
  PutB(A, $8E); PutB(A, $D8); PutB(A, $8E); PutB(A, $C0);
  PutB(A, $55); PutB(A, $89); PutB(A, $E5);         { push ebp ; mov }
  PutB(A, $FC); PutB(A, $55);                       { cld ; push ebp }
  PutB(A, $B8); PutD(A, LongInt(@W16ApiEntry));
  PutB(A, $FF); PutB(A, $D0);                       { call eax }
  PutB(A, $8D); PutB(A, $64); PutB(A, $24); PutB(A, 4); { lea esp,+4 }
  PutB(A, $5D);                                     { pop ebp }
  PutB(A, $0F); PutB(A, $BA); PutB(A, $25);         { bt [W16Cf],0 }
  PutD(A, LongInt(@W16Cf)); PutB(A, 0);
  PutB(A, $07); PutB(A, $1F); PutB(A, $61);         { pop es ds ; popad }
  PutB(A, $CB);                                     { retf }
  { CbGateStub : retour d'un rappel 16 bits }
  A := EnterStub + 256;
  CbGateStub := A;
  PutB(A, $66); PutB(A, $B9); PutB(A, $10); PutB(A, 0);
  PutB(A, $8E); PutB(A, $D9); PutB(A, $8E); PutB(A, $C1);
  PutB(A, $A3); PutD(A, LongInt(@Ret16Ax));
  PutB(A, $89); PutB(A, $15); PutD(A, LongInt(@Ret16Dx));
  PutB(A, $B8); PutD(A, LongInt(@CbFinish));
  PutB(A, $FF); PutB(A, $D0);
  PutB(A, $89); PutB(A, $C4);                       { mov esp,eax }
  PutB(A, $C3);
End;

{ Appel d'un code 16 bits CS:IP (anneau 3) ; rend DX:AX.
  Les registres d'entree sont pris dans C16[6..12]. }
Function Call16(Cs, Ip, Ss, Sp, Ds, Es : LongInt) : LongInt;
Var A, OldE, N, S : LongInt;
Begin
  Call16 := 0;
  N := Ctx16N[CurT];
  If N >= 16 Then
  Begin
    KLog('Win16 : rappels trop imbriques');
    Exit;
  End;
  C16[0] := Cs And $FFFF; C16[1] := Ip And $FFFF;
  C16[2] := Ss And $FFFF; C16[3] := Sp And $FFFF;
  C16[4] := Ds And $FFFF; C16[5] := Es And $FFFF;
  C16[13] := LongInt(@Ctx16[CurT * 16 + N]);
  C16[14] := LongInt(@ThrEsp0[CurT]);
  Ctx16N[CurT] := N + 1;
  OldE := ThrEsp0[CurT];
  A := LongInt(@C16);
  S := EnterStub;
  asm
    mov eax,A
    mov ecx,S
    call ecx
  end;
  { de retour par la passerelle 43h : ESP0 de nouveau celui d'avant }
  Ctx16N[CurT] := N;
  ThrEsp0[CurT] := OldE;
  MemL[0:TssBase + 4] := OldE;
  Call16 := (Ret16Ax And $FFFF) Or ((Ret16Dx And $FFFF) Shl 16);
End;

Procedure InitW16;
Var B, I, A : LongInt;
Begin
  { TSS : pile de l'anneau 0 (SS0 = 10h), pas de table d'E/S }
  FillMem(LongInt(@Tss), 128, 0);
  TssBase := LongInt(@Tss);
  Tss[2] := $10;
  Tss[25] := 104 Shl 16;
  B := TssBase;
  Gdt[10] := 103 Or ((B And $FFFF) Shl 16);
  Gdt[11] := ((B Shr 16) And $FF) Or $8900 Or (B And LongInt($FF000000));
  { LDT }
  B := LongInt(@Ldt);
  Gdt[12] := ((LdtMax * 8 - 1) And $FFFF) Or ((B And $FFFF) Shl 16);
  Gdt[13] := ((B Shr 16) And $FF) Or $8200 Or (B And LongInt($FF000000));
  BuildW16Stubs;
  { passerelles d'appel 386 de niveau 3 vers le segment de code 08h }
  Gdt[14] := (ApiGateStub And $FFFF) Or ($08 Shl 16);
  Gdt[15] := (ApiGateStub And LongInt($FFFF0000)) Or $EC00;
  Gdt[16] := (CbGateStub And $FFFF) Or ($08 Shl 16);
  Gdt[17] := (CbGateStub And LongInt($FFFF0000)) Or $EC00;
  For I := 0 To LdtMax - 1 Do LdtUsed[I] := False;
  LdtUsed[0] := True;
  asm
    mov ax,28h
    ltr ax
    mov ax,30h
    lldt ax
  end;
  { segment des souches 16 bits (une souche de 16 octets par API) }
  W16ThunkSel := GAlloc16($10000, True);
  W16ThunkLin := SelBase(W16ThunkSel);
  GOwner[W16ThunkSel Shr 3] := 0;
  A := W16ThunkLin + W16CbOfs;
  PutB(A, $9A); PutB(A, 0); PutB(A, 0);             { call far 43h:0 }
  PutB(A, SelGateCb); PutB(A, 0);
  { ESP0 de la tache 0 }
  ThrEsp0[0] := 0;
  W16Ready := True;
  KLog('Win16 : LDT ' + IntStr(LdtMax) + ' selecteurs, souches pretes');
End;

{ ------------------------------------------------------------------ }
{ Modules NE (executables et DLL Windows 3.x)                         }
{ ------------------------------------------------------------------ }

Const
  MaxNe = 24;
  MaxNeSeg = 96;
  W16SysLet = 'KUGBLSMENVCTYDO';
  W16SysMods : Array[1..15] Of String[8] = ('KERNEL', 'USER', 'GDI',
    'KEYBOARD', 'LZEXPAND', 'SHELL', 'MMSYSTEM', 'WIN87EM', 'WING', 'VER',
    'COMMDLG', 'TOOLHELP', 'SYSTEM', 'DISPLAY', 'SOUND');

Var
  NeUsed, NeDll, NeInit : Array[0..MaxNe - 1] Of Boolean;
  NeName : Array[0..MaxNe - 1] Of String[12];
  NePath : Array[0..MaxNe - 1] Of String[80];
  NeFile, NeHdr, NeNSeg, NeAuto, NeHMod, NeInst : Array[0..MaxNe - 1]
    Of LongInt;
  NeSegSel : Array[0..MaxNe * MaxNeSeg - 1] Of LongInt;
  { API : module (lettre), ordinal, signature, taille des arguments }
  ApiLet : Array[0..W16ApiN - 1] Of Char;
  ApiOrd, ApiArgB, ApiEq : Array[0..W16ApiN - 1] Of LongInt;
  ApiWarned : Array[0..W16ApiN - 1] Of Boolean;
  W16Env : LongInt;
  SysLetS : String;
  W16ErrMode : LongInt;

{ Parametres d'un appel d'API en cours }
Var
  ArgV : Array[1..16] Of LongInt;
  ArgRaw : Array[1..16] Of LongInt;
  ArgLin, ArgF, ArgIdx : LongInt;

Function ApiSig(I : LongInt) : String;
Var S : String; P : LongInt;
Begin
  S := W16Apis[I];
  P := Pos(':', S);
  S := Copy(S, P + 1, 40);
  P := Pos('>', S);
  If P > 0 Then ApiSig := Copy(S, 1, P - 1) Else ApiSig := S;
End;

Function ApiRet(I : LongInt) : Char;
Var S : String; P : LongInt;
Begin
  S := W16Apis[I];
  P := Pos('>', S);
  If P > 0 Then ApiRet := S[P + 1] Else ApiRet := 'W';
End;

Function ApiName(I : LongInt) : String;
Var S : String; P : LongInt;
Begin
  S := W16Apis[I];
  P := Pos(' ', S);
  ApiName := Copy(S, P + 1, 40);
End;

Function SigBytes(S : String) : LongInt;
Var I, N : LongInt;
Begin
  N := 0;
  For I := 1 To Length(S) Do
    Case S[I] Of
      'W', 'I' : N := N + 2;
      'L', 'P', 'S' : N := N + 4;
      'D' : N := N + 8;
    End;
  SigBytes := N;
End;

{ Souches 16 bits : push n / call far 3Bh:0 / retf taille }
Procedure InitW16Apis;
Var I, A, V : LongInt; S, Sg : String;
Begin
  SysLetS := W16SysLet;
  For I := 0 To W16ApiN - 1 Do
  Begin
    S := W16Apis[I];
    ApiLet[I] := S[1];
    Val(Copy(S, 2, 3), ApiOrd[I], V);
    ApiEq[I] := -1;
    ApiWarned[I] := False;
    If S[6] = '=' Then
    Begin
      Sg := Copy(S, 7, 20);
      If Pos(' ', Sg) > 0 Then Sg := Copy(Sg, 1, Pos(' ', Sg) - 1);
      Val(Sg, ApiEq[I], V);
      ApiArgB[I] := 0;
      Continue;
    End;
    Sg := ApiSig(I);
    If (Sg = 'V') Or (Sg = 'R') Or (Sg = 'X') Then ApiArgB[I] := 0
    Else ApiArgB[I] := SigBytes(Sg);
    A := W16ThunkLin + I * 16;
    PutB(A, $68); PutB(A, I And $FF); PutB(A, I Shr 8);
    PutB(A, $9A); PutB(A, 0); PutB(A, 0); PutB(A, SelGateApi); PutB(A, 0);
    If ApiArgB[I] = 0 Then PutB(A, $CB)
    Else
    Begin
      PutB(A, $CA); PutB(A, ApiArgB[I] And $FF); PutB(A, ApiArgB[I] Shr 8);
    End;
  End;
  { __WINFLAGS : mode protege, 486, mode etendu, coprocesseur, pagination }
  For I := 0 To W16ApiN - 1 Do
    If (ApiLet[I] = 'K') And (ApiOrd[I] = 178) Then ApiEq[I] := $0C29;
End;

Function ApiFind(Let : Char; Ord : LongInt) : LongInt;
Var I : LongInt;
Begin
  ApiFind := -1;
  For I := 0 To W16ApiN - 1 Do
    If (ApiLet[I] = Let) And (ApiOrd[I] = Ord) Then
    Begin
      ApiFind := I;
      Exit;
    End;
End;

Function SysModLet(Name : String) : Char;
Var I : LongInt;
Begin
  SysModLet := ' ';
  Name := UpStr(Name);
  For I := 1 To 15 Do
    If W16SysMods[I] = Name Then SysModLet := SysLetS[I];
End;

{ Chaine de N octets a l'adresse A }
Function PStrN(A, N : LongInt) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  If N > 255 Then N := 255;
  For I := 0 To N - 1 Do S := S + Chr(Mem[0:A + I]);
  PStrN := S;
End;

Function NeFind(Name : String) : LongInt;
Var I : LongInt;
Begin
  NeFind := -1;
  Name := UpStr(Name);
  For I := 0 To MaxNe - 1 Do
    If NeUsed[I] And (NeName[I] = Name) Then
    Begin
      NeFind := I;
      Exit;
    End;
End;

{ Module d'une poignee d'instance, de module ou de segment }
Function NeOfHandle(H : LongInt) : LongInt;
Var I, K : LongInt;
Begin
  NeOfHandle := -1;
  H := H Or 3;
  For I := 0 To MaxNe - 1 Do
    If NeUsed[I] Then
    Begin
      If ((NeHMod[I] Or 3) = H) Or ((NeInst[I] <> 0) And
         ((NeInst[I] Or 3) = H)) Then
      Begin
        NeOfHandle := I;
        Exit;
      End;
      For K := 0 To NeNSeg[I] - 1 Do
        If (NeSegSel[I * MaxNeSeg + K] Or 3) = H Then
        Begin
          NeOfHandle := I;
          Exit;
        End;
    End;
  If (H = 3) And (CurT >= 0) Then NeOfHandle := T16Mod[CurT];
End;

{ Entree Ord d'un module : segment (1..n) et deplacement }
Function NeEntry(M, Ord : LongInt; Var Seg, Ofs : LongInt) : Boolean;
Var P, N, Ind, Cur, K : LongInt;
Begin
  NeEntry := False;
  P := NeHdr[M] + MemW[0:NeHdr[M] + 4];
  Cur := 1;
  Repeat
    N := Mem[0:P];
    If N = 0 Then Exit;
    Ind := Mem[0:P + 1];
    P := P + 2;
    If Ind = 0 Then
    Begin
      Cur := Cur + N;
      Continue;
    End;
    For K := 0 To N - 1 Do
    Begin
      If Cur = Ord Then
      Begin
        If Ind = $FF Then
        Begin
          Seg := Mem[0:P + 3]; Ofs := MemW[0:P + 4];
        End
        Else
        Begin
          Seg := Ind; Ofs := MemW[0:P + 1];
        End;
        NeEntry := True;
        Exit;
      End;
      If Ind = $FF Then P := P + 6 Else P := P + 3;
      Inc(Cur);
    End;
  Until False;
End;

{ Ordinal d'un nom exporte (tables des noms residents et non residents) }
Function NeNameOrd(M : LongInt; Name : String) : LongInt;
Var P, L, Pass : LongInt; S : String;
Begin
  NeNameOrd := 0;
  Name := UpStr(Name);
  For Pass := 0 To 1 Do
  Begin
    If Pass = 0 Then P := NeHdr[M] + MemW[0:NeHdr[M] + $26]
    Else
    Begin
      If MemL[0:NeHdr[M] + $2C] = 0 Then Exit;
      P := NeFile[M] + MemL[0:NeHdr[M] + $2C];
    End;
    L := Mem[0:P];
    While L <> 0 Do
    Begin
      S := PStrN(P + 1, L);
      If UpStr(S) = Name Then
      Begin
        NeNameOrd := MemW[0:P + 1 + L];
        Exit;
      End;
      P := P + L + 3;
      L := Mem[0:P];
    End;
  End;
End;

Function NeEntryFar(M, Ord : LongInt) : LongInt;
Var Sg, Of2 : LongInt;
Begin
  NeEntryFar := 0;
  If NeEntry(M, Ord, Sg, Of2) And (Sg >= 1) And (Sg <= NeNSeg[M]) Then
    NeEntryFar := MakeFar(NeSegSel[M * MaxNeSeg + Sg - 1], Of2);
End;

Function LoadNe(Path : String; IsDll : Boolean) : LongInt; Forward;

{ Cible d'une importation : pointeur 16:16 (ou constante si Eq) }
Function NeImport(M, ModIdx, Ord : LongInt; ByName : String;
                  Var Eq : Boolean) : LongInt;
Var Nm : String; L : Char; I, D : LongInt;
Begin
  NeImport := 0;
  Eq := False;
  I := NeHdr[M] + MemW[0:NeHdr[M] + $2A] +
       MemW[0:NeHdr[M] + MemW[0:NeHdr[M] + $28] + (ModIdx - 1) * 2];
  Nm := UpStr(PStrN(I + 1, Mem[0:I]));
  L := SysModLet(Nm);
  If L <> ' ' Then
  Begin
    If ByName <> '' Then
    Begin
      ByName := UpStr(ByName);
      I := -1;
      For D := 0 To W16ApiN - 1 Do
        If (ApiLet[D] = L) And (UpStr(ApiName(D)) = ByName) Then I := D;
    End
    Else I := ApiFind(L, Ord);
    If I < 0 Then
    Begin
      KLog('Win16 : ordinal inconnu ' + Nm + '.' + IntStr(Ord));
      Exit;
    End;
    If ApiEq[I] >= 0 Then
    Begin
      Eq := True;
      NeImport := ApiEq[I];
      Exit;
    End;
    NeImport := MakeFar(W16ThunkSel, I * 16);
    Exit;
  End;
  D := NeFind(Nm);
  If D < 0 Then D := LoadNe(Nm + '.DLL', True);
  If D < 0 Then
  Begin
    KLog('Win16 : module introuvable ' + Nm);
    Exit;
  End;
  If ByName <> '' Then Ord := NeNameOrd(D, ByName);
  NeImport := NeEntryFar(D, Ord);
End;

{ Relocations d'un segment }
Procedure NeRelocate(M, S : LongInt);
Var Sg, Fl, Lin, R, Cnt, K, Src, Ty, Ofs, A, B, V, Sel, Next, Tgt,
    Guard : LongInt;
    Eq, Add : Boolean; Nm : String;
Begin
  Sg := NeHdr[M] + MemW[0:NeHdr[M] + $22] + S * 8;
  Fl := MemW[0:Sg + 4];
  If (Fl And $100) = 0 Then Exit;
  R := NeFile[M] + (MemW[0:Sg] Shl MemW[0:NeHdr[M] + $32]);
  If MemW[0:Sg + 2] = 0 Then R := R + $10000 Else R := R + MemW[0:Sg + 2];
  Lin := SelBase(NeSegSel[M * MaxNeSeg + S]);
  Cnt := MemW[0:R];
  For K := 0 To Cnt - 1 Do
  Begin
    Src := Mem[0:R + 2 + K * 8];
    Ty := Mem[0:R + 3 + K * 8];
    Ofs := MemW[0:R + 4 + K * 8];
    A := MemW[0:R + 6 + K * 8];
    B := MemW[0:R + 8 + K * 8];
    Add := (Ty And 4) <> 0;
    Eq := False;
    Tgt := 0;
    Case Ty And 3 Of
      0 :
        If (A And $FF) = $FF Then Tgt := NeEntryFar(M, B)
        Else If (A And $FF) <= NeNSeg[M] Then
          Tgt := MakeFar(NeSegSel[M * MaxNeSeg + (A And $FF) - 1], B);
      1 : Tgt := NeImport(M, A, B, '', Eq);
      2 :
      Begin
        V := NeHdr[M] + MemW[0:NeHdr[M] + $2A] + B;
        Nm := PStrN(V + 1, Mem[0:V]);
        Tgt := NeImport(M, A, 0, Nm, Eq);
      End;
      3 : Continue;   { correction du coprocesseur : sans objet }
    End;
    Sel := (Tgt Shr 16) And $FFFF;
    Guard := 0;
    Repeat
      Next := MemW[0:Lin + Ofs];
      Case Src Of
        0 :
          If Add Then Mem[0:Lin + Ofs] := (Mem[0:Lin + Ofs] + Tgt) And $FF
          Else Mem[0:Lin + Ofs] := Tgt And $FF;
        2 :
          If Eq Then MemW[0:Lin + Ofs] := Tgt And $FFFF
          Else If Add Then MemW[0:Lin + Ofs] := MemW[0:Lin + Ofs] + Sel
          Else MemW[0:Lin + Ofs] := Sel;
        3 :
          If Add Then
            MemW[0:Lin + Ofs] := MemW[0:Lin + Ofs] + (Tgt And $FFFF)
          Else
          Begin
            MemW[0:Lin + Ofs] := Tgt And $FFFF;
            MemW[0:Lin + Ofs + 2] := Sel;
          End;
        5 :
          If Add Then
            MemW[0:Lin + Ofs] := MemW[0:Lin + Ofs] + (Tgt And $FFFF)
          Else MemW[0:Lin + Ofs] := Tgt And $FFFF;
        11 :
        Begin
          MemL[0:Lin + Ofs] := Tgt And $FFFF;
          MemW[0:Lin + Ofs + 4] := Sel;
        End;
        13 :
          If Add Then MemL[0:Lin + Ofs] := MemL[0:Lin + Ofs] + (Tgt And $FFFF)
          Else MemL[0:Lin + Ofs] := Tgt And $FFFF;
      End;
      If Add Then Break;
      Ofs := Next;
      Inc(Guard);
    Until (Ofs = $FFFF) Or (Guard > 32768);
  End;
End;

{ Prologues des fonctions exportees : push ds / pop ax / nop (1E 58 90)
  ou mov ax,ds / nop (8C D8 90) -> mov ax,DGROUP }
Procedure NePatchExports(M : LongInt);
Var P, N, Ind, K, Sg, Of2, Lin : LongInt;
Begin
  If NeInst[M] = 0 Then Exit;
  P := NeHdr[M] + MemW[0:NeHdr[M] + 4];
  Repeat
    N := Mem[0:P];
    If N = 0 Then Exit;
    Ind := Mem[0:P + 1];
    P := P + 2;
    If Ind = 0 Then Continue;
    For K := 0 To N - 1 Do
    Begin
      If Ind = $FF Then
      Begin
        Sg := Mem[0:P + 3]; Of2 := MemW[0:P + 4];
      End
      Else
      Begin
        Sg := Ind; Of2 := MemW[0:P + 1];
      End;
      If ((Mem[0:P] And 1) <> 0) And (Sg >= 1) And (Sg <= NeNSeg[M]) Then
      Begin
        Lin := SelBase(NeSegSel[M * MaxNeSeg + Sg - 1]) + Of2;
        If (Mem[0:Lin + 2] = $90) And (((Mem[0:Lin] = $1E) And
           (Mem[0:Lin + 1] = $58)) Or ((Mem[0:Lin] = $8C) And
           (Mem[0:Lin + 1] = $D8))) Then
        Begin
          Mem[0:Lin] := $B8;
          MemW[0:Lin + 1] := NeInst[M];
        End;
      End;
      If Ind = $FF Then P := P + 6 Else P := P + 3;
    End;
  Until False;
End;

Function LoadNe(Path : String; IsDll : Boolean) : LongInt;
Var M, I, F, FSize, Ne, Sg, Off, Len, Fl, Mn, Sz, Sel, Lin, Own,
    L : LongInt; Nm : String;
Begin
  LoadNe := -1;
  Path := FindModuleFile(Path);
  If Path = '' Then Exit;
  M := -1;
  For I := MaxNe - 1 DownTo 0 Do
    If Not NeUsed[I] Then M := I;
  If M < 0 Then Exit;
  F := LoadWholeFile(Path, FSize);
  If F = 0 Then Exit;
  Ne := F + MemW[0:F + $3C];
  If (MemW[0:F] <> $5A4D) Or (MemW[0:Ne] <> $454E) Then
  Begin
    KFree(F);
    Exit;
  End;
  NeUsed[M] := True; NeInit[M] := False;
  NeFile[M] := F; NeHdr[M] := Ne;
  NeDll[M] := (MemW[0:Ne + $0C] And $8000) <> 0;
  NeNSeg[M] := Min(MemW[0:Ne + $1C], MaxNeSeg);
  NeAuto[M] := MemW[0:Ne + $0E];
  L := Ne + MemW[0:Ne + $26];
  NeName[M] := UpStr(PStrN(L + 1, Mem[0:L]));
  NePath[M] := Path;
  KLog('Win16 : module ' + NeName[M] + ' (' + Path + '), ' +
       IntStr(NeNSeg[M]) + ' segments');
  Own := HeapOwner;
  NeHMod[M] := GAlloc16(64, False);
  NeInst[M] := 0;
  { segments }
  For I := 0 To NeNSeg[M] - 1 Do
  Begin
    Sg := Ne + MemW[0:Ne + $22] + I * 8;
    Off := MemW[0:Sg] Shl MemW[0:Ne + $32];
    Len := MemW[0:Sg + 2];
    Fl := MemW[0:Sg + 4];
    Mn := MemW[0:Sg + 6];
    If (Len = 0) And (Off <> 0) Then Len := $10000;
    If Mn = 0 Then Sz := $10000 Else Sz := Mn;
    If Sz < Len Then Sz := Len;
    If I + 1 = NeAuto[M] Then Sz := $10000;
    Sel := GAlloc16(Sz, (Fl And 1) = 0);
    NeSegSel[M * MaxNeSeg + I] := Sel;
    If Sel = 0 Then Exit;
    Lin := SelBase(Sel);
    If (Off <> 0) And (Len > 0) Then MoveMem(F + Off, Lin, Len);
    If I + 1 = NeAuto[M] Then
    Begin
      NeInst[M] := Sel;
      { segment automatique : limite 64 Ko }
      DescSet(Sel Shr 3, Lin, $FFFF, $F2);
    End;
  End;
  { relocations (les DLL importees se chargent au passage) }
  For I := 0 To NeNSeg[M] - 1 Do NeRelocate(M, I);
  NePatchExports(M);
  HeapOwner := Own;
  LoadNe := M;
End;

{ ------------------------------------------------------------------ }
{ Appel d'une procedure 16 bits avec arguments sur la pile de la     }
{ tache : Args = mots/longs dans l'ordre Pascal (premier empile en    }
{ premier, donc a l'adresse la plus haute)                           }
{ ------------------------------------------------------------------ }

Var
  CbStkSel : Array[0..MaxThread - 1] Of LongInt;
  PArgN : LongInt;
  PArgV, PArgS : Array[0..15] Of LongInt;

Procedure PArgClear;
Begin
  PArgN := 0;
End;

Procedure PArgW(V : LongInt);
Begin
  PArgV[PArgN] := V And $FFFF; PArgS[PArgN] := 2; Inc(PArgN);
End;

Procedure PArgL(V : LongInt);
Begin
  PArgV[PArgN] := V; PArgS[PArgN] := 4; Inc(PArgN);
End;

{ Pile 16 bits a utiliser pour un rappel : celle de la tache appelante
  (en cours d'appel d'API) ou une pile de secours }
Procedure CbStack(Var Ss, Sp : LongInt);
Begin
  If T16Sp[CurT] <> 0 Then
  Begin
    Ss := T16Ss[CurT]; Sp := T16Sp[CurT] And $FFFE;
    Exit;
  End;
  If CbStkSel[CurT] = 0 Then CbStkSel[CurT] := GAlloc16($8000, False);
  Ss := CbStkSel[CurT]; Sp := $7FF0;
End;

{ Reserve N octets sur la pile 16 bits ; rend l'adresse 16:16 }
Function StkReserve(Ss : LongInt; Var Sp : LongInt; N : LongInt)
  : LongInt;
Begin
  Sp := (Sp - N) And $FFFE;
  StkReserve := MakeFar(Ss, Sp);
End;

Function CallProc16(Proc, Ds, Ss, Sp : LongInt) : LongInt;
Var I, B, OS, OP : LongInt;
Begin
  B := SelBase(Ss);
  For I := 0 To PArgN - 1 Do
  Begin
    Sp := Sp - PArgS[I];
    If PArgS[I] = 2 Then MemW[0:B + Sp] := PArgV[I]
    Else MemL[0:B + Sp] := PArgV[I];
  End;
  Sp := Sp - 4;
  MemW[0:B + Sp] := W16CbOfs;
  MemW[0:B + Sp + 2] := W16ThunkSel;
  C16[6] := 0; C16[7] := 0; C16[8] := 0; C16[9] := 0;
  C16[10] := 0; C16[11] := 0; C16[12] := 0;
  { pendant le rappel, la pile de la tache est sous Sp }
  OS := T16Ss[CurT]; OP := T16Sp[CurT];
  T16Ss[CurT] := Ss; T16Sp[CurT] := Sp;
  CallProc16 := Call16((Proc Shr 16) And $FFFF, Proc And $FFFF, Ss, Sp,
                       Ds, Ds);
  T16Ss[CurT] := OS; T16Sp[CurT] := OP;
End;

{ ------------------------------------------------------------------ }
{ Procedures 16 bits vues comme des procedures 32 bits : une souche   }
{ (pop ecx / push n / push ecx / jmp W16Bridge) par procedure         }
{ ------------------------------------------------------------------ }

Const
  MaxPr16 = 256;

Var
  W16Trace : Boolean;
  Pr16Proc, Pr16Ds, Pr16Stub, Pr16Thr : Array[0..MaxPr16 - 1] Of LongInt;
  Pr16N : LongInt;
  BridgeThunk : LongInt;
  RcTmp : Array[0..15] Of LongInt;

Function MakeBridge(Proc, Ds : LongInt) : LongInt;
Var I, A : LongInt;
Begin
  MakeBridge := 0;
  If Proc = 0 Then Exit;
  For I := 0 To Pr16N - 1 Do
    If (Pr16Proc[I] = Proc) And (Pr16Ds[I] = Ds) Then
    Begin
      MakeBridge := Pr16Stub[I];
      Exit;
    End;
  If Pr16N >= MaxPr16 Then Exit;
  If BridgeThunk = 0 Then BridgeThunk := KernelExport('W16Bridge');
  I := Pr16N;
  Inc(Pr16N);
  A := KAlloc(16);
  Pr16Proc[I] := Proc; Pr16Ds[I] := Ds; Pr16Stub[I] := A;
  Pr16Thr[I] := CurT;
  PutB(A, $59);
  PutB(A, $68); PutD(A, I);
  PutB(A, $51);
  PutB(A, $B8); PutD(A, BridgeThunk);
  PutB(A, $FF); PutB(A, $E0);
  MakeBridge := Pr16Stub[I];
End;

{ Procedure 16 bits d'une souche (0 si procedure 32 bits) }
Function Proc16Of(A : LongInt) : LongInt;
Var I : LongInt;
Begin
  Proc16Of := 0;
  For I := 0 To Pr16N - 1 Do
    If Pr16Stub[I] = A Then
    Begin
      Proc16Of := Pr16Proc[I];
      Exit;
    End;
End;

Procedure Rect16To32(P16, P32 : LongInt);
Var K, V : LongInt;
Begin
  For K := 0 To 3 Do
  Begin
    V := MemW[0:P16 + K * 2];
    If V >= $8000 Then V := V - $10000;
    MemL[0:P32 + K * 4] := V;
  End;
End;

Procedure Rect32To16(P32, P16 : LongInt);
Var K : LongInt;
Begin
  For K := 0 To 3 Do MemW[0:P16 + K * 2] := MemL[0:P32 + K * 4] And $FFFF;
End;

Function SX16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  SX16 := V;
End;

Function StrToStack(Ss : LongInt; Var Sp : LongInt; P : LongInt)
  : LongInt;
Var N, B : LongInt;
Begin
  StrToStack := P;
  If (P = 0) Or ((P Shr 16) = 0) Then Exit;
  N := StrLenZ(P) + 1;
  B := SelBase(Ss);
  StrToStack := StkReserve(Ss, Sp, N);
  MoveMem(P, B + Sp, N);
End;

{ Appel d'une procedure de fenetre 16 bits (via sa souche n) }
Function W16Bridge(Idx, H, M, WP, LP : LongInt) : LongInt;
Var Ss, Sp, B, M16, W16, L16, R, Post, P16, A, K : LongInt;
Begin
  W16Bridge := 0;
  If (Idx < 0) Or (Idx >= Pr16N) Then Exit;
  CbStack(Ss, Sp);
  B := SelBase(Ss);
  Sp := Sp - 16;
  M16 := M; W16 := WP And $FFFF; L16 := LP; Post := 0; P16 := 0;
  Case M Of
    $111 :
      L16 := (LP And $FFFF) Or (((WP Shr 16) And $FFFF) Shl 16);
    $132..$138 :
    Begin
      M16 := $19;
      L16 := (LP And $FFFF) Or ((M - $132) Shl 16);
    End;
    $114, $115 :
      L16 := ((WP Shr 16) And $FFFF) Or ((LP And $FFFF) Shl 16);
    6 :
      L16 := (LP And $FFFF) Or (((WP Shr 16) And $FFFF) Shl 16);
    $113 : L16 := 0;
    1, $81 :
      If LP <> 0 Then
      Begin
        P16 := StkReserve(Ss, Sp, 34);
        A := B + Sp;
        MemL[0:A] := MemL[0:LP];
        MemW[0:A + 4] := MemL[0:LP + 4];
        MemW[0:A + 6] := MemL[0:LP + 8];
        MemW[0:A + 8] := MemL[0:LP + 12];
        MemW[0:A + 10] := MemL[0:LP + 16];
        MemW[0:A + 12] := MemL[0:LP + 20];
        MemW[0:A + 14] := MemL[0:LP + 24];
        MemW[0:A + 16] := MemL[0:LP + 28];
        MemL[0:A + 18] := MemL[0:LP + 32];
        MemL[0:A + 30] := MemL[0:LP + 44];
        K := StrToStack(Ss, Sp, MemL[0:LP + 36]);
        MemL[0:B + (P16 And $FFFF) + 22] := K;
        K := StrToStack(Ss, Sp, MemL[0:LP + 40]);
        MemL[0:B + (P16 And $FFFF) + 26] := K;
        L16 := P16;
      End;
    $0C : L16 := StrToStack(Ss, Sp, LP);
    $0D :
    Begin
      K := Min(WP, 2048);
      P16 := StkReserve(Ss, Sp, K + 2);
      Mem[0:B + Sp] := 0;
      L16 := P16; Post := 1;
    End;
    $24 :
    Begin
      P16 := StkReserve(Ss, Sp, 20);
      For K := 0 To 9 Do MemW[0:B + Sp + K * 2] := MemL[0:LP + K * 4];
      L16 := P16; Post := 2;
    End;
    $46, $47 :
    Begin
      P16 := StkReserve(Ss, Sp, 14);
      For K := 0 To 6 Do MemW[0:B + Sp + K * 2] := MemL[0:LP + K * 4];
      L16 := P16; Post := 3;
    End;
    $83 :
    Begin
      P16 := StkReserve(Ss, Sp, 28);
      For K := 0 To 11 Do
        MemW[0:B + Sp + K * 2] := MemL[0:LP + K * 4];
      MemL[0:B + Sp + 24] := 0;
      L16 := P16; Post := 4;
    End;
  End;
  PArgClear;
  PArgW(H); PArgW(M16); PArgW(W16); PArgL(L16);
  R := CallProc16(Pr16Proc[Idx], Pr16Ds[Idx], Ss, Sp);
  A := B + (P16 And $FFFF);
  Case Post Of
    1 :
    Begin
      K := Min(WP, 2048);
      If K > 0 Then
      Begin
        MoveMem(A, LP, K);
        Mem[0:LP + K - 1] := 0;
      End;
      R := R And $FFFF;
    End;
    2 : For K := 0 To 9 Do MemL[0:LP + K * 4] := SX16(MemW[0:A + K * 2]);
    3 :
      If M = $46 Then
        For K := 2 To 6 Do MemL[0:LP + K * 4] := SX16(MemW[0:A + K * 2]);
    4 :
    Begin
      For K := 0 To 11 Do MemL[0:LP + K * 4] := SX16(MemW[0:A + K * 2]);
      R := R And $FFFF;
    End;
  End;
  { resultat 16 bits signe pour les messages qui rendent un mot }
  If (M <> $111) And ((R Shr 16) = 0) And (M <> 1) And (M <> $81) Then
    R := R And $FFFF;
  W16Bridge := R;
End;

{ ------------------------------------------------------------------ }
{ Messages d'un programme 16 bits vers une fenetre 32 bits           }
{ ------------------------------------------------------------------ }

Var
  MFix, MFixP : LongInt;

Procedure Msg16To32(H : LongInt; Var M, WP, LP : LongInt);
Var W, K, N : LongInt;
Begin
  MFix := 0;
  WP := WP And $FFFF;
  Case M Of
    $111 :
    Begin
      WP := WP Or (((LP Shr 16) And $FFFF) Shl 16);
      LP := LP And $FFFF;
      Exit;
    End;
    $19 :
    Begin
      M := $132 + ((LP Shr 16) And $FFFF);
      LP := LP And $FFFF;
      Exit;
    End;
    $114, $115 :
    Begin
      WP := WP Or ((LP And $FFFF) Shl 16);
      LP := (LP Shr 16) And $FFFF;
      Exit;
    End;
    6 :
    Begin
      WP := WP Or (((LP Shr 16) And $FFFF) Shl 16);
      LP := LP And $FFFF;
      Exit;
    End;
    $0C, $0D : LP := Lin16(LP);
  End;
  If (M < $400) Or (M > $43F) Then Exit;
  W := WndOf(H);
  If W < 0 Then Exit;
  N := M - $400;
  K := Wnds[W].IKind;
  If K = ikEdit Then
  Begin
    M := $B0 + N;
    Case N Of
      1 :
      Begin
        WP := LP And $FFFF;
        LP := (LP Shr 16) And $FFFF;
      End;
      2, 3, 4 :
      Begin
        MFixP := Lin16(LP);
        If N > 2 Then Rect16To32(MFixP, LongInt(@RcTmp));
        LP := LongInt(@RcTmp);
        If N = 2 Then MFix := 1;
      End;
      $12, $14 : LP := Lin16(LP);
    End;
  End
  Else If K = ikButton Then M := $F0 + N
  Else If K = ikStatic Then M := $170 + N
  Else If K = ikListBox Then
  Begin
    M := $180 + N - 1;
    If (N = 1) Or (N = 2) Or (N = $A) Or (N = $D) Or (N = $E) Or
       (N = $10) Or (N = $23) Then LP := Lin16(LP);
    If N = $19 Then
    Begin
      MFixP := Lin16(LP);
      LP := LongInt(@RcTmp);
      MFix := 1;
    End;
  End
  Else If K = ikComboBox Then
  Begin
    M := $140 + N;
    If (N = 3) Or (N = 5) Or (N = 8) Or (N = $A) Or (N = $C) Or
       (N = $D) Or (N = $18) Then LP := Lin16(LP);
  End;
End;

Procedure Msg16Fix;
Begin
  If MFix = 1 Then Rect32To16(LongInt(@RcTmp), MFixP);
  MFix := 0;
End;

{ Message 16 bits vers une fenetre : procedure 16 bits directement,
  sinon traduction et appel de la procedure 32 bits }
Function Pr16Of(A : LongInt) : LongInt;
Var I : LongInt;
Begin
  Pr16Of := -1;
  For I := 0 To Pr16N - 1 Do
    If Pr16Stub[I] = A Then Pr16Of := I;
End;

{ Message 16 bits vers une procedure : procedure 16 bits appelee
  directement, sinon traduction et procedure 32 bits (ou defaut) }
Function CallWnd16(P, H, M, WP, LP : LongInt; Def : Boolean) : LongInt;
Var I, R, Ss, Sp : LongInt;
Begin
  I := Pr16Of(P);
  If (I >= 0) And Not Def Then
  Begin
    CbStack(Ss, Sp);
    PArgClear;
    PArgW(H); PArgW(M); PArgW(WP); PArgL(LP);
    CallWnd16 := CallProc16(Pr16Proc[I], Pr16Ds[I], Ss, Sp - 16);
    Exit;
  End;
  Msg16To32(H, M, WP, LP);
  If Def Then R := DefWindowProcA(H, M, WP, LP)
  Else If P <> 0 Then R := CallWindowProcA(P, H, M, WP, LP)
  Else R := SendMessageA(H, M, WP, LP);
  Msg16Fix;
  CallWnd16 := R;
End;

Function SendMsg16(H, M, WP, LP : LongInt) : LongInt;
Var W : LongInt;
Begin
  W := WndOf(H);
  If (W >= 0) And (Pr16Of(Wnds[W].Proc) >= 0) Then
    SendMsg16 := CallWnd16(Wnds[W].Proc, H, M, WP, LP, False)
  Else SendMsg16 := CallWnd16(0, H, M, WP, LP, False);
End;

{ ------------------------------------------------------------------ }
{ Entree de la passerelle des API 16 bits                            }
{ ------------------------------------------------------------------ }

Procedure W16Dispatch(Idx : LongInt); Forward;

Procedure SetAX(V : LongInt);
Begin
  MemL[0:ArgF + 40] := (MemL[0:ArgF + 40] And LongInt($FFFF0000)) Or
                       (V And $FFFF);
End;

Procedure SetDXAX(V : LongInt);
Begin
  SetAX(V);
  MemL[0:ArgF + 32] := (MemL[0:ArgF + 32] And LongInt($FFFF0000)) Or
                       ((V Shr 16) And $FFFF);
End;

Function RegW(Ofs : LongInt) : LongInt;
Begin
  RegW := MemL[0:ArgF + Ofs] And $FFFF;
End;

Procedure SetRegW(Ofs, V : LongInt);
Begin
  MemL[0:ArgF + Ofs] := (MemL[0:ArgF + Ofs] And LongInt($FFFF0000)) Or
                        (V And $FFFF);
End;

{ Retirer N octets d'arguments de la pile 16 bits (fonctions PASCAL a
  nombre variable d'arguments) : l'adresse de retour remonte }
Procedure W16PopArgs(N : LongInt);
Var Ss, Sp, B : LongInt;
Begin
  Ss := MemL[0:ArgF + 56] And $FFFF;
  Sp := MemL[0:ArgF + 52] And $FFFF;
  B := SelBase(Ss);
  MemL[0:B + Sp + N] := MemL[0:B + Sp];
  MemL[0:ArgF + 52] := (MemL[0:ArgF + 52] And LongInt($FFFF0000)) Or
                       ((Sp + N) And $FFFF);
End;

Procedure W16ApiEntry(Frame : LongInt);
Var Ss, Esp3, Sp, B, Idx, OS, OP, K, Off, N, V, OL, OF2, OI : LongInt;
    Sv, SvR : Array[1..16] Of LongInt;
    Sg, S : String;
Begin
  Ss := MemL[0:Frame + 56] And $FFFF;
  Esp3 := MemL[0:Frame + 52];
  Sp := Esp3 And $FFFF;
  B := SelBase(Ss);
  Idx := MemW[0:B + Sp];
  MemL[0:Frame + 52] := (Esp3 And LongInt($FFFF0000)) Or ((Sp + 2) And $FFFF);
  For K := 1 To 16 Do
  Begin
    Sv[K] := ArgV[K]; SvR[K] := ArgRaw[K];
  End;
  OL := ArgLin; OF2 := ArgF; OI := ArgIdx;
  OS := T16Ss[CurT]; OP := T16Sp[CurT];
  T16Ss[CurT] := Ss; T16Sp[CurT] := Sp;
  ArgF := Frame;
  ArgLin := B + Sp + 6;
  ArgIdx := Idx;
  W16Cf := 0;
  If (Idx >= 0) And (Idx < W16ApiN) Then
  Begin
    Sg := ApiSig(Idx);
    If (Sg <> 'V') And (Sg <> 'R') And (Sg <> 'X') Then
    Begin
      N := Length(Sg);
      Off := 0;
      For K := N DownTo 1 Do
      Begin
        Case Sg[K] Of
          'W', 'I' :
          Begin
            V := MemW[0:ArgLin + Off];
            If (Sg[K] = 'I') And (V >= $8000) Then V := V - $10000;
            Off := Off + 2;
          End;
          'D' :
          Begin
            V := MemL[0:ArgLin + Off];
            Off := Off + 8;
          End;
        Else
          V := MemL[0:ArgLin + Off];
          Off := Off + 4;
        End;
        If K <= 16 Then
        Begin
          ArgRaw[K] := V;
          If Sg[K] = 'P' Then ArgV[K] := Lin16(V) Else ArgV[K] := V;
        End;
      End;
    End;
    If W16Trace Then
    Begin
      S := '16> ' + ApiName(Idx);
      If (Sg <> 'V') And (Sg <> 'R') And (Sg <> 'X') Then
        For K := 1 To Min(Length(Sg), 8) Do
        Begin
          S := S + ' ' + HexStr(ArgRaw[K], 4);
          If (Sg[K] = 'P') And (ArgV[K] <> 0) Then
            If (Mem[0:ArgV[K]] >= 32) And (Mem[0:ArgV[K]] < 127) Then
              S := S + '"' + Copy(PStr(ArgV[K]), 1, 40) + '"';
        End;
      KLog(S);
    End;
    W16Dispatch(Idx);
    If W16Trace Then
      KLog('16< ' + ApiName(Idx) + ' = ' + HexStr(RegW(32), 4) + ':' +
           HexStr(RegW(40), 4));
  End;
  T16Ss[CurT] := OS; T16Sp[CurT] := OP;
  For K := 1 To 16 Do
  Begin
    ArgV[K] := Sv[K]; ArgRaw[K] := SvR[K];
  End;
  ArgLin := OL; ArgF := OF2; ArgIdx := OI;
End;

{ ------------------------------------------------------------------ }
{ Taches Win16                                                       }
{ ------------------------------------------------------------------ }

Var
  T16Psp, T16Show : Array[0..MaxThread - 1] Of LongInt;
  T16Cmd : Array[0..MaxThread - 1] Of String[127];
  NeSeq : Array[0..MaxNe - 1] Of LongInt;
  NeSeqN : LongInt;

Procedure W16Terminate(Code : LongInt);
Var I, M, K, Own : LongInt;
Begin
  KLog('Win16 : fin de la tache ' + IntStr(CurT) + ' (' + IntStr(Code) +
       ')');
  KillingApp := True;
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And (Wnds[I].Thread = CurT) Then
    Begin
      Wnds[I].Proc := 0;
      Wnds[I].IKind := ikStatic;
      DestroyW(I);
    End;
  KillingApp := False;
  Own := ThrOwner[CurT];
  For I := 0 To MaxGdi - 1 Do
    If Gdis[I].Used And (Gdis[I].Owner = Own) And Not Gdis[I].Stock Then
      Gdis[I].Used := False;
  For I := 0 To MaxKObj - 1 Do
    If KObjs[I].Used And (KObjOwner[I] = Own) And
       (KObjs[I].Kind In [koFile, koFind]) Then KObjs[I].Used := False;
  M := T16Mod[CurT];
  If (M >= 0) And NeUsed[M] And Not NeDll[M] Then
  Begin
    For K := 0 To NeNSeg[M] - 1 Do GFree16(NeSegSel[M * MaxNeSeg + K]);
    GFree16(NeHMod[M]);
    KFree(NeFile[M]);
    NeUsed[M] := False;
  End;
  GFreeOwner(Own);
  T16Mod[CurT] := -1;
  CbStkSel[CurT] := 0;
  ExitThreadK(Code);
End;

Procedure W16InitDll(M, Ss, Sp : LongInt);
Var Ne, Cs, Ip, Ds : LongInt;
Begin
  NeInit[M] := True;
  Ne := NeHdr[M];
  Cs := MemW[0:Ne + $16]; Ip := MemW[0:Ne + $14];
  If (Cs = 0) Or (Cs > NeNSeg[M]) Then Exit;
  Ds := NeInst[M];
  KLog('Win16 : initialisation de ' + NeName[M]);
  C16[6] := 0; C16[7] := 0; C16[8] := MemW[0:Ne + $10]; C16[9] := 0;
  C16[10] := 0; C16[11] := Ds; C16[12] := 0;
  If Ds = 0 Then C16[11] := NeHMod[M];
  Call16(NeSegSel[M * MaxNeSeg + Cs - 1], Ip, Ss, Sp, Ds, 0);
End;

Function W16TaskMain(M : LongInt) : LongInt;
Var Ne, Ds, Ss, Sp, StkSz, Heap, Lin, Cs, Ip, I, J, Best, DataSz,
    Sg : LongInt; S : String;
Begin
  W16TaskMain := 0;
  T16Mod[CurT] := M;
  Ne := NeHdr[M];
  Ds := NeInst[M];
  StkSz := MemW[0:Ne + $12];
  If StkSz < $1400 Then StkSz := $1400;
  Heap := MemW[0:Ne + $10];
  Sg := Ne + MemW[0:Ne + $22] + (NeAuto[M] - 1) * 8;
  DataSz := MemW[0:Sg + 6];
  If DataSz = 0 Then DataSz := MemW[0:Sg + 2];
  Ss := Ds;
  If MemW[0:Ne + $1A] <> NeAuto[M] Then
    Ss := NeSegSel[M * MaxNeSeg + MemW[0:Ne + $1A] - 1];
  Sp := MemW[0:Ne + $18];
  If Sp = 0 Then Sp := DataSz + StkSz;
  If Sp > $FFFE Then Sp := $FFFE;
  Sp := Sp And $FFFE;
  { PSP : INT 20h, environnement, ligne de commande }
  T16Psp[CurT] := GAlloc16(256, False);
  Lin := SelBase(T16Psp[CurT]);
  Mem[0:Lin] := $CD; Mem[0:Lin + 1] := $20;
  MemW[0:Lin + $2C] := W16Env;
  S := T16Cmd[CurT];
  If S <> '' Then S := ' ' + S;
  If Length(S) > 125 Then S := Copy(S, 1, 125);
  Mem[0:Lin + $80] := Length(S);
  For I := 1 To Length(S) Do Mem[0:Lin + $80 + I] := Ord(S[I]);
  Mem[0:Lin + $81 + Length(S)] := 13;
  { donnees d'instance : pile }
  Lin := SelBase(Ds);
  MemW[0:Lin + $0A] := Sp - StkSz + 16;
  MemW[0:Lin + $0C] := Sp;
  MemW[0:Lin + $0E] := Sp;
  T16Ds[CurT] := Ds;
  { DLL dans l'ordre de fin de chargement }
  Repeat
    Best := -1;
    For J := 0 To MaxNe - 1 Do
      If NeUsed[J] And NeDll[J] And Not NeInit[J] Then
        If (Best < 0) Or (NeSeq[J] < NeSeq[Best]) Then Best := J;
    If Best >= 0 Then W16InitDll(Best, Ss, Sp - 16);
  Until Best < 0;
  Cs := MemW[0:Ne + $16]; Ip := MemW[0:Ne + $14];
  KLog('Win16 : lancement de ' + NeName[M] + ' CS:IP ' + HexStr(Cs, 2) +
       ':' + HexStr(Ip, 4) + ' SS:SP ' + HexStr(Ss, 4) + ':' + HexStr(Sp, 4));
  C16[6] := 0; C16[7] := StkSz; C16[8] := Heap; C16[9] := 0;
  C16[10] := 0; C16[11] := Ds; C16[12] := 0;
  Call16(NeSegSel[M * MaxNeSeg + Cs - 1], Ip, Ss, Sp, Ds, T16Psp[CurT]);
  W16Terminate(0);
End;

Function IsNeFile(Path : String) : Boolean;
Var H, Buf, N : LongInt;
Begin
  IsNeFile := False;
  Buf := KAlloc(64);
  H := KOpenFile(Path, False, 3);
  If H <> INVALID_HANDLE Then
  Begin
    If KReadFile(H, Buf, 64, N) And (N = 64) And (MemW[0:Buf] = $5A4D)
    Then
    Begin
      SetFilePointer(H, MemL[0:Buf + $3C], 0, 0);
      If KReadFile(H, Buf, 2, N) And (MemW[0:Buf] = $454E) Then
        IsNeFile := True;
    End;
    CloseHandle(H);
  End;
  KFree(Buf);
End;

Function RunNe(Path, Args : String; Show : LongInt) : Boolean;
Var M, T, J, Own : LongInt;
Begin
  RunNe := False;
  If Not W16Ready Then Exit;
  Own := HeapOwner;
  HeapOwner := 2;
  M := LoadNe(Path, False);
  If M < 0 Then
  Begin
    HeapOwner := Own;
    Exit;
  End;
  For J := 0 To MaxNe - 1 Do
    If NeUsed[J] And (NeSeq[J] = 0) Then
    Begin
      Inc(NeSeqN);
      NeSeq[J] := NeSeqN;
    End;
  T := ThreadNew(LongInt(@W16TaskMain), M, $10000, True);
  HeapOwner := Own;
  If T < 0 Then Exit;
  ThrW16[T] := True;
  ThrOwner[T] := 16 + T;
  T16Cmd[T] := Args;
  T16Show[T] := Show;
  T16Sp[T] := 0;
  RunNe := True;
End;

{ ------------------------------------------------------------------ }
{ Fichiers DOS des programmes 16 bits : numeros 5..63 (les          }
{ bibliotheques C 16 bits indexent leurs tables par ce numero)        }
{ ------------------------------------------------------------------ }

Var
  DosH : Array[0..63] Of LongInt;
  T16Dta : Array[0..MaxThread - 1] Of LongInt;
  RegHN : LongInt;

Function DosHNew(KH : LongInt) : LongInt;
Var I : LongInt;
Begin
  DosHNew := -1;
  If KH = INVALID_HANDLE Then Exit;
  For I := 5 To 63 Do
    If DosH[I] = 0 Then
    Begin
      DosH[I] := KH;
      DosHNew := I;
      Exit;
    End;
  CloseHandle(KH);
End;

Function DosHGet(H : LongInt) : LongInt;
Begin
  DosHGet := INVALID_HANDLE;
  H := H And $FFFF;
  If (H >= 5) And (H <= 63) And (DosH[H] <> 0) Then DosHGet := DosH[H]
  Else If H <= 4 Then DosHGet := HStdOut;
End;

Procedure DosHClose(H : LongInt);
Var I, K : LongInt;
Begin
  H := H And $FFFF;
  If (H >= 5) And (H <= 63) And (DosH[H] <> 0) Then
  Begin
    K := DosH[H];
    DosH[H] := 0;
    { un numero duplique (45h) partage l'objet fichier }
    For I := 5 To 63 Do
      If DosH[I] = K Then Exit;
    CloseHandle(K);
  End;
End;

Function DosHDup(H : LongInt) : LongInt;
Var I : LongInt;
Begin
  DosHDup := -1;
  H := H And $FFFF;
  If (H < 5) Or (H > 63) Or (DosH[H] = 0) Then Exit;
  For I := 5 To 63 Do
    If DosH[I] = 0 Then
    Begin
      DosH[I] := DosH[H];
      DosHDup := I;
      Exit;
    End;
End;

Function T16DtaOf : LongInt;
Begin
  If T16Dta[CurT] = 0 Then T16Dta[CurT] := MakeFar(T16Psp[CurT], $80);
  T16DtaOf := T16Dta[CurT];
End;

{ Ressource d'un module NE : Typ/Id entiers (bit 15 force) ou noms }
Function NeRes(M, Typ, Id : LongInt; TName, IName : String;
               Var Ptr, Len : LongInt) : Boolean;
Var R, Sh, T, Cnt, K, E, V : LongInt; Ok : Boolean;

  Function RName(Ofs : LongInt) : String;
  Begin
    RName := UpStr(PStrN(R + Ofs + 1, Mem[0:R + Ofs]));
  End;

Begin
  NeRes := False;
  If (M < 0) Or Not NeUsed[M] Then Exit;
  If MemW[0:NeHdr[M] + $24] = MemW[0:NeHdr[M] + $26] Then Exit;
  R := NeHdr[M] + MemW[0:NeHdr[M] + $24];
  Sh := MemW[0:R];
  T := R + 2;
  While MemW[0:T] <> 0 Do
  Begin
    V := MemW[0:T];
    Cnt := MemW[0:T + 2];
    If (V And $8000) <> 0 Then Ok := (TName = '') And ((V And $7FFF) = Typ)
    Else Ok := (TName <> '') And (RName(V) = TName);
    If Ok Then
      For K := 0 To Cnt - 1 Do
      Begin
        E := T + 8 + K * 12;
        V := MemW[0:E + 6];
        If (V And $8000) <> 0 Then Ok := (IName = '') And ((V And $7FFF) = Id)
        Else Ok := (IName <> '') And (RName(V) = IName);
        If Ok Then
        Begin
          Ptr := NeFile[M] + (MemW[0:E] Shl Sh);
          Len := MemW[0:E + 2] Shl Sh;
          NeRes := True;
          Exit;
        End;
      End;
    T := T + 8 + Cnt * 12;
  End;
End;

{ Nom ou entier d'une ressource passee par pointeur 16:16 }
Procedure ResKey(Raw : LongInt; Var N : LongInt; Var S : String);
Var E : LongInt;
Begin
  S := '';
  N := Raw And $FFFF;
  If (Raw Shr 16) <> 0 Then
  Begin
    S := UpStr(PStr(Lin16(Raw)));
    If (Length(S) > 1) And (S[1] = '#') Then
    Begin
      Val(Copy(S, 2, 10), N, E);
      S := '';
    End;
  End;
End;

Function LoadString16(Inst, Id, Buf, Max : LongInt) : LongInt;
Var M, P, L, K, N : LongInt;
Begin
  LoadString16 := 0;
  M := NeOfHandle(Inst);
  If Not NeRes(M, 6, (Id Shr 4) + 1, '', '', P, L) Then Exit;
  For K := 0 To (Id And 15) - 1 Do P := P + 1 + Mem[0:P];
  N := Mem[0:P];
  If Max <= 0 Then Exit;
  If N > Max - 1 Then N := Max - 1;
  MoveMem(P + 1, Buf, N);
  Mem[0:Buf + N] := 0;
  LoadString16 := N;
End;

{ wsprintf 16 bits : %d %i %u %x %X %c %s (%ld %lu %lx pour les longs) }
Function WSPrintf16(Dst, Fmt, Va : LongInt) : LongInt;
Var I, N, V, W, L : LongInt; C : Char; S, Pad : String; Lng, Left,
    Zero : Boolean;
Begin
  N := 0;
  I := 0;
  While Mem[0:Fmt + I] <> 0 Do
  Begin
    C := Chr(Mem[0:Fmt + I]);
    Inc(I);
    If C <> '%' Then
    Begin
      Mem[0:Dst + N] := Ord(C);
      Inc(N);
      Continue;
    End;
    Left := False; Zero := False; W := 0; Lng := False;
    If Chr(Mem[0:Fmt + I]) = '-' Then Begin Left := True; Inc(I) End;
    If Chr(Mem[0:Fmt + I]) = '0' Then Begin Zero := True; Inc(I) End;
    While (Mem[0:Fmt + I] >= 48) And (Mem[0:Fmt + I] <= 57) Do
    Begin
      W := W * 10 + Mem[0:Fmt + I] - 48;
      Inc(I);
    End;
    If Chr(Mem[0:Fmt + I]) = '.' Then
    Begin
      Inc(I);
      While (Mem[0:Fmt + I] >= 48) And (Mem[0:Fmt + I] <= 57) Do Inc(I);
    End;
    If UpCase(Chr(Mem[0:Fmt + I])) = 'L' Then Begin Lng := True; Inc(I) End;
    C := Chr(Mem[0:Fmt + I]);
    Inc(I);
    S := '';
    Case C Of
      'd', 'i', 'u', 'x', 'X' :
      Begin
        If Lng Then Begin V := MemL[0:Va]; Va := Va + 4 End
        Else
        Begin
          V := MemW[0:Va]; Va := Va + 2;
          If (C In ['d', 'i']) And (V >= $8000) Then V := V - $10000;
        End;
        If C In ['x', 'X'] Then
        Begin
          If Lng Then S := HexStr(V, 8) Else S := HexStr(V, 4);
          While (Length(S) > 1) And (S[1] = '0') Do Delete(S, 1, 1);
          If C = 'x' Then
            For L := 1 To Length(S) Do
              If S[L] In ['A'..'F'] Then S[L] := Chr(Ord(S[L]) + 32);
        End
        Else S := IntStr(V);
      End;
      'c' :
      Begin
        S := Chr(MemW[0:Va] And $FF); Va := Va + 2;
      End;
      's' :
      Begin
        S := PStr(Lin16(MemL[0:Va])); Va := Va + 4;
      End;
      '%' : S := '%';
    End;
    Pad := '';
    While Length(S) + Length(Pad) < W Do
      If Zero And Not Left Then Pad := Pad + '0' Else Pad := Pad + ' ';
    If Left Then S := S + Pad Else S := Pad + S;
    For L := 1 To Length(S) Do
    Begin
      Mem[0:Dst + N] := Ord(S[L]);
      Inc(N);
    End;
  End;
  Mem[0:Dst + N] := 0;
  WSPrintf16 := N;
End;

{ Fenetre de premier niveau d'une classe et/ou d'un titre }
Function FindWin(Cls, Name : LongInt) : LongInt;
Var I : LongInt; C, N : String;
Begin
  FindWin := 0;
  C := ''; N := '';
  If Cls <> 0 Then C := UpStr(PStr(Cls));
  If Name <> 0 Then N := PStr(Name);
  For I := 0 To MaxWnd - 1 Do
    If Wnds[I].Used And Not IsChildW(I) And (Wnds[I].IKind = ikNone) Then
      If ((C = '') Or (UpStr(Classes[Wnds[I].Cls].Name) = C)) And
         ((Name = 0) Or (Wnds[I].Text = N)) Then
      Begin
        FindWin := HwndOf(I);
        Exit;
      End;
End;

Function FindWindowA(Cls, Name : LongInt) : LongInt;
Begin
  If (Cls <> 0) And (Cls < $10000) Then Cls := 0;
  FindWindowA := FindWin(Cls, Name);
End;

{ MSG 32 bits (28 octets) <-> MSG 16 bits (18 octets) }
Procedure Msg32To16(P32, P16 : LongInt);
Var M, WP, LP : LongInt;
Begin
  M := MemL[0:P32 + 4]; WP := MemL[0:P32 + 8]; LP := MemL[0:P32 + 12];
  Case M Of
    $111 : LP := (LP And $FFFF) Or (((WP Shr 16) And $FFFF) Shl 16);
    $114, $115 :
      LP := ((WP Shr 16) And $FFFF) Or ((LP And $FFFF) Shl 16);
    $113 : LP := 0;
  End;
  MemW[0:P16] := MemL[0:P32];
  MemW[0:P16 + 2] := M;
  MemW[0:P16 + 4] := WP;
  MemL[0:P16 + 6] := LP;
  MemL[0:P16 + 10] := MemL[0:P32 + 16];
  MemW[0:P16 + 14] := MemL[0:P32 + 20];
  MemW[0:P16 + 16] := MemL[0:P32 + 24];
End;

Procedure Msg16To32P(P16, P32 : LongInt);
Var H, M, WP, LP : LongInt;
Begin
  H := MemW[0:P16]; M := MemW[0:P16 + 2];
  WP := MemW[0:P16 + 4]; LP := MemL[0:P16 + 6];
  Msg16To32(H, M, WP, LP);
  MemL[0:P32] := H; MemL[0:P32 + 4] := M;
  MemL[0:P32 + 8] := WP; MemL[0:P32 + 12] := LP;
  MemL[0:P32 + 16] := MemL[0:P16 + 10];
  MemL[0:P32 + 20] := SX16(MemW[0:P16 + 14]);
  MemL[0:P32 + 24] := SX16(MemW[0:P16 + 16]);
End;

{ Appel d'une fonction stdcall 32 bits : N arguments a partir de A
  (A[0] premier argument) }
Function CallStd(Proc, A, N : LongInt) : LongInt;
Var R, P, K : LongInt;
Begin
  R := 0;
  P := A + (N - 1) * 4;
  asm
    mov ecx,N
    mov edx,P
  @l:
    test ecx,ecx
    jz @c
    push dword ptr [edx]
    sub edx,4
    dec ecx
    jmp @l
  @c:
    mov eax,Proc
    call eax
    mov R,eax
  end;
  CallStd := R;
End;

Procedure W16Fail(Msg : String);
Begin
  MsgBoxOpen('Pasdows', Msg, $10);
  W16Terminate(1);
End;

{ ------------------------------------------------------------------ }
{ DOS3Call / INT 21h                                                 }
{ ------------------------------------------------------------------ }

Var
  DosIsInt : Boolean;
  W16Tmp : LongInt;

Procedure DosCF(E : LongInt);
Begin
  If DosIsInt Then
  Begin
    If E <> 0 Then MemL[0:ArgF + 52] := MemL[0:ArgF + 52] Or 1
    Else MemL[0:ArgF + 52] := MemL[0:ArgF + 52] And Not 1;
  End
  Else W16Cf := Ord(E <> 0);
  If E <> 0 Then SetAX(E);
End;

Function DosPtr(SegOfs, Ofs : LongInt) : LongInt;
Begin
  DosPtr := SelBase(RegW(SegOfs)) + RegW(Ofs);
End;

Function DosErr : LongInt;
Var E : LongInt;
Begin
  E := Threads[CurT].LastErr;
  If (E <= 0) Or (E > 255) Then E := 5;
  DosErr := E;
End;

Function DosDrive : LongInt;
Begin
  DosDrive := Ord(UpCase(CurDirS[1])) - 65;
End;

Procedure DosFind(Dta : LongInt; First : Boolean);
Var H, Fd, Ok, Attr, Mask, D, T : LongInt; S : String;
Begin
  Fd := W16Tmp;
  If First Then
  Begin
    Mask := RegW(36);
    H := FindFirstFileA(DosPtr(8, 32), Fd);
    If H = INVALID_HANDLE Then
    Begin
      DosCF(18);
      Exit;
    End;
    MemL[0:Dta] := H;
    Mem[0:Dta + 4] := Mask;
    Ok := 1;
  End
  Else
  Begin
    H := MemL[0:Dta];
    Mask := Mem[0:Dta + 4];
    Ok := FindNextFileA(H, Fd);
  End;
  While Ok <> 0 Do
  Begin
    Attr := MemL[0:Fd];
    If ((Attr And $16) And Not Mask) = 0 Then
    Begin
      Mem[0:Dta + 21] := Attr;
      D := 0; T := 0;
      FileTimeToDosDateTime(Fd + 20, LongInt(@D), LongInt(@T));
      MemW[0:Dta + 22] := T; MemW[0:Dta + 24] := D;
      MemL[0:Dta + 26] := MemL[0:Fd + 32];
      S := UpStr(PStr(Fd + 44));
      If Length(S) > 12 Then S := Copy(S, 1, 12);
      PutPStr(Dta + 30, S, 13);
      DosCF(0);
      Exit;
    End;
    Ok := FindNextFileA(H, Fd);
  End;
  FindClose(H);
  DosCF(18);
End;

Procedure W16Dos;
Var AH, AL, H, N, R, P, D, T : LongInt; S : String;
Begin
  AH := (RegW(40) Shr 8) And $FF;
  AL := RegW(40) And $FF;
  If W16Tmp = 0 Then W16Tmp := KAlloc(512);
  DosCF(0);
  If W16Trace Then
  Begin
    P := DosPtr(8, 32);
    If (Mem[0:P] >= 32) And (Mem[0:P] < 127) Then S := Copy(PStr(P), 1, 40)
    Else S := '';
    KLog('INT 21h AH=' + HexStr(AH, 2) + ' AL=' + HexStr(AL, 2) + ' BX=' +
         HexStr(RegW(28), 4) + ' CX=' + HexStr(RegW(36), 4) + ' DX=' +
         HexStr(RegW(32), 4) + ' ' + S);
  End;
  Case AH Of
    $0D : ;
    $0E :
    Begin
      If RegW(32) And $FF = 2 Then CurDirS := 'C:'
      Else If RegW(32) And $FF = 3 Then CurDirS := 'D:';
      SetAX((RegW(40) And $FF00) Or 4);
    End;
    $19 : SetAX((RegW(40) And $FF00) Or DosDrive);
    $1A : T16Dta[CurT] := MakeFar(RegW(8), RegW(32));
    $2F :
    Begin
      If T16Dta[CurT] = 0 Then T16Dta[CurT] := MakeFar(T16Psp[CurT], $80);
      SetRegW(4, (T16Dta[CurT] Shr 16) And $FFFF);
      SetRegW(28, T16Dta[CurT] And $FFFF);
    End;
    $25 : ;
    $35 :
    Begin
      SetRegW(4, 0); SetRegW(28, 0);
    End;
    $2A :
    Begin
      GetLocalTime(W16Tmp);
      SetRegW(36, MemW[0:W16Tmp]);
      SetRegW(32, (MemW[0:W16Tmp + 2] Shl 8) Or MemW[0:W16Tmp + 6]);
      SetAX((RegW(40) And $FF00) Or MemW[0:W16Tmp + 4]);
    End;
    $2C :
    Begin
      GetLocalTime(W16Tmp);
      SetRegW(36, (MemW[0:W16Tmp + 8] Shl 8) Or MemW[0:W16Tmp + 10]);
      SetRegW(32, (MemW[0:W16Tmp + 12] Shl 8) Or
                  (MemW[0:W16Tmp + 14] Div 10));
    End;
    $30 :
    Begin
      SetAX($0007);
      SetRegW(28, 0); SetRegW(36, 0);
    End;
    $33 : SetRegW(32, 0);
    $36 :
    Begin
      S := Chr(64 + (RegW(32) And $FF)) + ':\';
      If RegW(32) And $FF = 0 Then S := Copy(CurDirS, 1, 2) + '\';
      PutPStr(W16Tmp + 400, S, 8);
      If GetDiskFreeSpaceA(W16Tmp + 400, W16Tmp, W16Tmp + 4, W16Tmp + 8,
                           W16Tmp + 12) <> 0 Then
      Begin
        SetAX(MemL[0:W16Tmp]);
        SetRegW(28, Min(MemL[0:W16Tmp + 8], $FFFF));
        SetRegW(36, MemL[0:W16Tmp + 4]);
        SetRegW(32, Min(MemL[0:W16Tmp + 12], $FFFF));
      End
      Else SetAX($FFFF);
    End;
    $39 : If CreateDirectoryA(DosPtr(8, 32), 0) = 0 Then DosCF(DosErr);
    $3A : If RemoveDirectoryA(DosPtr(8, 32)) = 0 Then DosCF(DosErr);
    $3B : If SetCurrentDirectoryA(DosPtr(8, 32)) = 0 Then DosCF(3);
    $3C, $5B :
    Begin
      If AH = $3C Then D := 2 Else D := 1;
      H := DosHNew(KOpenFile(PStr(DosPtr(8, 32)), True, D));
      If H < 0 Then DosCF(DosErr) Else SetAX(H);
    End;
    $3D :
    Begin
      H := DosHNew(KOpenFile(PStr(DosPtr(8, 32)), (AL And 3) <> 0, 3));
      If H < 0 Then DosCF(DosErr) Else SetAX(H);
    End;
    $3E : DosHClose(RegW(28));
    $3F :
    Begin
      H := DosHGet(RegW(28));
      If (RegW(28) <= 4) Then SetAX(0)
      Else If KReadFile(H, DosPtr(8, 32), RegW(36), N) Then SetAX(N)
      Else DosCF(6);
    End;
    $40 :
    Begin
      H := DosHGet(RegW(28));
      If RegW(36) = 0 Then
      Begin
        SetEndOfFile(H);
        SetAX(0);
      End
      Else
      Begin
        N := KWriteFile(H, DosPtr(8, 32), RegW(36));
        If N < 0 Then DosCF(5) Else SetAX(N);
      End;
    End;
    $41 : If DeleteFileA(DosPtr(8, 32)) = 0 Then DosCF(2);
    $42 :
    Begin
      H := DosHGet(RegW(28));
      R := SetFilePointer(H, (RegW(36) Shl 16) Or RegW(32), 0, AL);
      If R = -1 Then DosCF(6)
      Else
      Begin
        SetAX(R); SetRegW(32, (R Shr 16) And $FFFF);
      End;
    End;
    $43 :
      If AL = 0 Then
      Begin
        R := GetFileAttributesA(DosPtr(8, 32));
        If R = -1 Then DosCF(2) Else SetRegW(36, R);
      End
      Else SetFileAttributesA(DosPtr(8, 32), RegW(36));
    $44 :
      Case AL Of
        0 :
          If RegW(28) <= 4 Then SetRegW(32, $80D3)
          Else SetRegW(32, DosDrive);
        8 : SetAX(1);
        9 :
          If ((RegW(28) And $FF) = 4) Or
             (((RegW(28) And $FF) = 0) And (DosDrive = 3)) Then
            SetRegW(32, $1000)
          Else SetRegW(32, 0);
      Else
        DosCF(1);
      End;
    $45 :
    Begin
      N := DosHDup(RegW(28));
      If N < 0 Then DosCF(4) Else SetAX(N);
    End;
    $47 :
    Begin
      S := CurDirS;
      If Length(S) > 3 Then S := Copy(S, 4, 255) Else S := '';
      PutPStr(DosPtr(8, 16), S, 64);
    End;
    $48 :
    Begin
      H := GAlloc16(RegW(28) * 16, False);
      If H = 0 Then
      Begin
        SetRegW(28, 0);
        DosCF(8);
      End
      Else SetAX(H);
    End;
    $49 : GFree16(RegW(4));
    $4A :
      If GReAlloc16(RegW(4), RegW(28) * 16) <> (RegW(4) Or 3) Then
        DosCF(8);
    $4C : W16Terminate(AL);
    $4E : DosFind(Lin16(T16DtaOf), True);
    $4F : DosFind(Lin16(T16DtaOf), False);
    $50 : ;
    $51, $62 : SetRegW(28, T16Psp[CurT]);
    $56 : If MoveFileA(DosPtr(8, 32), DosPtr(4, 12)) = 0 Then DosCF(5);
    $57 :
      If AL = 0 Then
      Begin
        H := DosHGet(RegW(28));
        D := 0; T := 0;
        If GetFileTime(H, 0, 0, W16Tmp) <> 0 Then
          FileTimeToDosDateTime(W16Tmp, LongInt(@D), LongInt(@T));
        SetRegW(36, T); SetRegW(32, D);
      End;
    $59 :
    Begin
      SetAX(DosErr); SetRegW(28, $0D01); SetRegW(36, 0);
    End;
    $6C :
    Begin
      P := DosPtr(8, 16);
      D := RegW(32);
      If GetFileAttributesA(P) <> -1 Then
      Begin
        If (D And 3) = 0 Then N := 0
        Else If (D And 3) = 1 Then
        Begin
          N := 3; R := 1;
        End
        Else
        Begin
          N := 2; R := 3;
        End;
      End
      Else If (D And $10) <> 0 Then
      Begin
        N := 1; R := 2;
      End
      Else N := -1;
      If N = 0 Then DosCF(80)
      Else If N < 0 Then DosCF(2)
      Else
      Begin
        H := DosHNew(KOpenFile(PStr(P), (RegW(28) And 3) <> 0, N));
        If H < 0 Then DosCF(DosErr)
        Else
        Begin
          SetAX(H);
          SetRegW(36, R);
        End;
      End;
    End;
    $71 : DosCF($7100);
  Else
    KLog('Win16 : INT 21h AH=' + HexStr(AH, 2) + 'h non gere');
    DosCF(1);
  End;
End;

Procedure Int21Tail;
Var F, OF2 : LongInt;
Begin
  asm
    mov eax,[ebp]
    mov F,eax
    sti
  end;
  OF2 := ArgF;
  ArgF := F;
  DosIsInt := True;
  W16Dos;
  DosIsInt := False;
  ArgF := OF2;
End;

Procedure Int21Gate; Interrupt;
Begin
  Int21Tail;
End;

{ INT 2Fh (multiplexage) et INT 31h (DPMI) : rien d'installe }
Procedure Int2FGate; Interrupt;
Begin
End;

{ ------------------------------------------------------------------ }
{ API Win16 : code = rang du module * 1000 + ordinal                 }
{ (1 KERNEL, 2 USER, 3 GDI, 4 KEYBOARD, 5 LZEXPAND, 6 SHELL,         }
{  7 MMSYSTEM, 8 WIN87EM, 9 WING, 10 VER, 11 COMMDLG, 12 TOOLHELP)   }
{ ------------------------------------------------------------------ }

Var
  W16Buf : LongInt;
  WinIni, WinDirZ, SysDirZ : String;

Function A(K : LongInt) : LongInt;
Begin
  A := ArgV[K];
End;

Function W16Inst : LongInt;
Begin
  W16Inst := T16Ds[CurT];
End;

Procedure RetStrCopy(Dst, Src, Max : LongInt);
Var N : LongInt;
Begin
  N := StrLenZ(Src);
  If N > Max - 1 Then N := Max - 1;
  If N < 0 Then N := 0;
  MoveMem(Src, Dst, N);
  Mem[0:Dst + N] := 0;
  SetAX(N);
End;

Procedure W16RegisterClass(P : LongInt);
Var C : LongInt;
Begin
  C := W16Buf;
  FillMem(C, 48, 0);
  MemL[0:C] := MemW[0:P];
  MemL[0:C + 4] := MakeBridge(MemL[0:P + 2], W16Inst);
  MemL[0:C + 8] := SX16(MemW[0:P + 6]);
  MemL[0:C + 12] := SX16(MemW[0:P + 8]);
  MemL[0:C + 16] := MemW[0:P + 10];
  MemL[0:C + 20] := MemW[0:P + 12];
  MemL[0:C + 24] := MemW[0:P + 14];
  MemL[0:C + 28] := MemW[0:P + 16];
  If (MemL[0:P + 18] Shr 16) <> 0 Then MemL[0:C + 32] := Lin16(MemL[0:P + 18])
  Else MemL[0:C + 32] := MemW[0:P + 18];
  If (MemL[0:P + 22] Shr 16) <> 0 Then MemL[0:C + 36] := Lin16(MemL[0:P + 22])
  Else MemL[0:C + 36] := MemW[0:P + 22];
  SetAX(RegisterClassA(C));
End;

Procedure W16WinExec(Cmd : String; Show : LongInt);
Var P : LongInt; Prog, Args : String;
Begin
  Cmd := Trim(Cmd);
  P := Pos(' ', Cmd);
  If P > 0 Then
  Begin
    Prog := Copy(Cmd, 1, P - 1);
    Args := Trim(Copy(Cmd, P + 1, 255));
  End
  Else
  Begin
    Prog := Cmd; Args := '';
  End;
  If Pos('.', BaseName(Prog)) = 0 Then Prog := Prog + '.EXE';
  KLog('WinExec ' + Prog + ' [' + Args + ']');
  If FindModuleFile(Prog) = '' Then
  Begin
    SetAX(2);
    Exit;
  End;
  If IsNeFile(FindModuleFile(Prog)) Then
  Begin
    If RunNe(FindModuleFile(Prog), Args, Show) Then SetAX(33) Else SetAX(11);
  End
  Else If RunExe(Prog, Args) Then SetAX(33)
  Else SetAX(11);
End;

Procedure W16Dispatch(Idx : LongInt);
Var Code, R, P, K, N, S, H, M, T, F, Ss, Sp : LongInt; Str : String;
Begin
  If W16Buf = 0 Then W16Buf := KAlloc(4096);
  Code := Pos(ApiLet[Idx], SysLetS) * 1000 + ApiOrd[Idx];
  If ApiSig(Idx) <> 'R' Then SetDXAX(0);
  Case Code Of
    { -------------------------------- KERNEL ------------------------ }
    1001, 1137 :
    Begin
      If Code = 1137 Then Str := PStr(A(2)) Else Str := 'FatalExit';
      W16Fail(NeName[T16Mod[CurT]] + ' : ' + Str);
    End;
    1003 : SetDXAX($07005F03);
    1004 :
    Begin
      S := A(1);
      If S = 0 Then S := RegW(8);
      SetAX(Ord(LocalInitK(S, A(2), A(3))));
    End;
    1005 : SetAX(LocalAllocK(RegW(8), A(1), A(2)));
    1006 : SetAX(LocalReAllocK(RegW(8), A(1), A(2), A(3)));
    1007 :
    Begin
      LocalFreeK(RegW(8), A(1));
      SetAX(0);
    End;
    1008 : SetDXAX(MakeFar(RegW(8), A(1)));
    1009 : SetAX(0);
    1010 : SetAX(LocalSizeK(RegW(8), A(1)));
    1012 : SetAX(0);
    1013 : SetDXAX(0);
    1015 :
    Begin
      R := GAlloc16(A(2), False);
      SetAX(R);
    End;
    1016 :
      If (A(3) And $80) <> 0 Then SetAX(A(1))
      Else SetAX(GReAlloc16(A(1), A(2)));
    1017 :
    Begin
      GFree16(A(1));
      SetAX(0);
    End;
    1018, 1023 :
      If GIdx(A(1)) >= 0 Then SetDXAX(MakeFar(A(1), 0))
      Else If (Code = 1023) And (A(1) = $FFFF) Then SetAX(RegW(8))
      Else If SelValid(A(1)) Then SetDXAX(MakeFar(A(1), 0));
    1019, 1024 : SetAX(0);
    1020 :
    Begin
      K := GIdx(A(1));
      If K >= 0 Then SetDXAX(GSize[K]);
    End;
    1021 : SetDXAX(MakeFar(A(1), A(1)));
    1022 : SetAX(0);
    1025 : SetDXAX(HeapFreeBytes);
    1029, 1030 : KYield;
    1036 : SetDXAX($8000 + CurT);
    1037 : SetAX(T16Psp[CurT]);
    1047 :
    Begin
      If (ArgRaw[1] Shr 16) = 0 Then
      Begin
        M := NeOfHandle(ArgRaw[1]);
        If M >= 0 Then SetAX(NeHMod[M]);
        Exit;
      End;
      Str := UpStr(PStr(Lin16(ArgRaw[1])));
      If Pos('.', Str) > 0 Then Str := Copy(Str, 1, Pos('.', Str) - 1);
      M := NeFind(Str);
      If M >= 0 Then SetAX(NeHMod[M]);
    End;
    1048 :
    Begin
      M := NeOfHandle(A(1));
      If M >= 0 Then SetAX(1);
    End;
    1049 :
    Begin
      M := NeOfHandle(A(1));
      If M >= 0 Then RetStrCopy(A(2), LongInt(@NePath[M]) + 1, A(3))
      Else SetAX(0);
      If M >= 0 Then PutPStr(A(2), NePath[M], A(3));
    End;
    1050 :
    Begin
      M := NeOfHandle(A(1));
      If M >= 0 Then
      Begin
        If (ArgRaw[2] Shr 16) = 0 Then N := ArgRaw[2] And $FFFF
        Else N := NeNameOrd(M, PStr(A(2)));
        SetDXAX(NeEntryFar(M, N));
      End;
    End;
    1051 : SetDXAX(ArgRaw[1]);
    1052 : ;
    1057 : SetAX(GetPrivateProfileIntA(A(1), A(2), A(3), LongInt(@WinIni) + 1));
    1058 :
      SetAX(GetPrivateProfileStringA(A(1), A(2), A(3), A(4), A(5),
                                     LongInt(@WinIni) + 1));
    1059 :
      SetAX(WritePrivateProfileStringA(A(1), A(2), A(3),
                                       LongInt(@WinIni) + 1));
    1074 :
    Begin
      R := OpenFile(A(1), A(2), A(3));
      If (R = -1) Or (R = 0) And ((A(3) And $4200) = 0) Then SetAX($FFFF)
      Else If (A(3) And $4200) <> 0 Then
      Begin
        If R <> 0 Then CloseHandle(R);
        SetAX(1);
      End
      Else SetAX(DosHNew(R));
    End;
    1081 :
    Begin
      DosHClose(A(1));
      SetAX(0);
    End;
    1082, 1349 :
    Begin
      If KReadFile(DosHGet(A(1)), Lin16(A(2)), A(3), N) Then SetDXAX(N)
      Else SetDXAX(-1);
      If Code = 1082 Then SetRegW(32, 0);
    End;
    1083 :
    Begin
      R := DosHNew(KOpenFile(PStr(A(1)), True, 2));
      If R < 0 Then SetAX($FFFF) Else SetAX(R);
    End;
    1084 :
    Begin
      R := SetFilePointer(DosHGet(A(1)), A(2), 0, A(3));
      SetDXAX(R);
    End;
    1085 :
    Begin
      R := DosHNew(KOpenFile(PStr(A(1)), (A(2) And 3) <> 0, 3));
      If R < 0 Then SetAX($FFFF) Else SetAX(R);
    End;
    1086, 1350 :
    Begin
      R := KWriteFile(DosHGet(A(1)), A(2), A(3));
      SetDXAX(R);
      If Code = 1086 Then SetRegW(32, 0);
    End;
    1088 :
    Begin
      RetStrCopy(Lin16(A(1)), A(2), 65536);
      SetDXAX(A(1));
    End;
    1089 :
    Begin
      P := Lin16(A(1));
      RetStrCopy(P + StrLenZ(P), A(2), 65536);
      SetDXAX(A(1));
    End;
    1090 : SetAX(StrLenZ(A(1)));
    1091 :
    Begin
      { InitTask : tas local, pile, ligne de commande }
      M := T16Mod[CurT];
      S := RegW(8);
      P := SelBase(S);
      LocalInitK(S, Max(MemW[0:P + $0E], $100), $FFF0);
      SetAX(1);
      SetRegW(36, MemW[0:NeHdr[M] + $12]);
      SetRegW(12, S);
      SetRegW(16, 0);
      SetRegW(4, T16Psp[CurT]);
      SetRegW(28, $81);
      If T16Show[CurT] = 0 Then T16Show[CurT] := 1;
      SetRegW(32, T16Show[CurT]);
    End;
    1102 : W16Dos;
    1107 :
    Begin
      SetAX(W16ErrMode);
      W16ErrMode := A(1);
    End;
    1127 : SetAX(GetPrivateProfileIntA(A(1), A(2), A(3), A(4)));
    1128 : SetAX(GetPrivateProfileStringA(A(1), A(2), A(3), A(4), A(5),
                                          A(6)));
    1129 : SetAX(WritePrivateProfileStringA(A(1), A(2), A(3), A(4)));
    1131 : SetDXAX(MakeFar(W16Env, 0));
    1132 : SetDXAX($0C29);
    1134 : RetStrCopy(A(1), LongInt(@WinDirZ) + 1, A(2));
    1135 : RetStrCopy(A(1), LongInt(@SysDirZ) + 1, A(2));
    1136 :
      Case A(1) Of
        2 : SetAX(3);
        3 : SetAX(4);
      Else
        SetAX(0);
      End;
    1166 : W16WinExec(PStr(A(1)), A(2));
    1207 : SetAX(0);
    1513 : SetDXAX(LoadLibraryA(A(1)));
    1514 : SetDXAX(1);
    1515 :
      If (ArgRaw[2] Shr 16) = 0 Then
        SetDXAX(GetProcAddress(A(1), ArgRaw[2] And $FFFF))
      Else SetDXAX(GetProcAddress(A(1), A(2)));
    1516 : SetDXAX(Lin16(ArgRaw[1]));
    1517 :
    Begin
      { CallProc32W(p1..pN, proc, conversions, N) : PASCAL variable }
      N := MemL[0:ArgLin];
      F := MemL[0:ArgLin + 4];
      P := MemL[0:ArgLin + 8];
      If N > 32 Then N := 32;
      For K := 0 To N - 1 Do
      Begin
        R := MemL[0:ArgLin + 12 + K * 4];
        If ((F Shr K) And 1) <> 0 Then R := Lin16(R);
        MemL[0:W16Buf + (N - 1 - K) * 4] := R;
      End;
      R := CallStd(P, W16Buf, N);
      W16PopArgs(12 + N * 4);
      SetDXAX(R);
    End;
    { --------------------------------- USER ------------------------- }
    2001 : SetAX(MessageBoxA(A(1), A(2), A(3), A(4)));
    2005 : SetAX(1);
    2010 : SetAX(SetTimer(A(1), A(2), A(3), MakeBridge(ArgRaw[4], W16Inst)));
    2012 : SetAX(KillTimer(A(1), A(2)));
    2013 : SetDXAX(Ticks);
    2014 : SetDXAX(Ticks);
    2015 : SetDXAX(Ticks);
    2018 : SetAX(SetCapture(A(1)));
    2019 : ReleaseCapture;
    2022 : SetAX(SetFocus(A(1)));
    2023 : SetAX(GetFocus);
    2024 : SetAX(RemovePropA(A(1), A(2)));
    2025 : SetAX(GetPropA(A(1), A(2)));
    2026 : SetAX(SetPropA(A(1), A(2), A(3)));
    2017 :
    Begin
      R := GetCursorPos(W16Buf);
      MemW[0:A(1)] := MemL[0:W16Buf]; MemW[0:A(1) + 2] := MemL[0:W16Buf + 4];
    End;
    2032, 2033 :
    Begin
      If Code = 2032 Then R := GetWindowRect(A(1), W16Buf)
      Else R := GetClientRect(A(1), W16Buf);
      Rect32To16(W16Buf, A(2));
    End;
    2034 : SetAX(EnableWindow(A(1), A(2)));
    2035 : SetAX(IsWindowEnabled(A(1)));
    2036 :
    Begin
      R := GetWindowTextA(A(1), Lin16(A(2)), A(3));
      SetAX(R);
    End;
    2037 : SetAX(SetWindowTextA(A(1), Lin16(A(2))));
    2038 : SetAX(GetWindowTextLengthA(A(1)));
    2039 :
    Begin
      R := BeginPaint(A(1), W16Buf);
      P := A(2);
      FillMem(P, 32, 0);
      MemW[0:P] := R;
      MemW[0:P + 2] := MemL[0:W16Buf + 4];
      Rect32To16(W16Buf + 8, P + 4);
      SetAX(R);
    End;
    2040 :
    Begin
      MemL[0:W16Buf] := MemW[0:A(2)];
      R := EndPaint(A(1), W16Buf);
      SetAX(1);
    End;
    2041, 2452 :
    Begin
      If Code = 2041 Then K := 0 Else K := 1;
      { CreateWindowEx : style etendu en premier argument }
      If K = 0 Then T := 0 Else T := A(1);
      For N := 4 To 7 Do
        If ArgV[N + K] = -32768 Then ArgV[N + K] := LongInt($80000000);
      P := A(1 + K);
      If (ArgRaw[1 + K] Shr 16) = 0 Then P := ArgRaw[1 + K] And $FFFF;
      R := CreateWindowExA(T, P, A(2 + K), A(3 + K), A(4 + K), A(5 + K),
                           A(6 + K), A(7 + K), A(8 + K), A(9 + K),
                           A(10 + K), ArgRaw[11 + K]);
      SetAX(R);
    End;
    2042 : SetAX(ShowWindow(A(1), A(2)));
    2043 : SetAX(ShowWindow(A(1), 6));
    2044 : SetAX(ShowWindow(A(1), 9));
    2045 : SetAX(BringWindowToTop(A(1)));
    2046 : SetAX(GetParent(A(1)));
    2047 : SetAX(IsWindow(A(1)));
    2048 : SetAX(IsChild(A(1), A(2)));
    2049 : SetAX(IsWindowVisible(A(1)));
    2050 : SetAX(FindWin(A(1), A(2)));
    2053 : SetAX(DestroyWindow(A(1)));
    2056 :
      SetAX(MoveWindow(A(1), SX16(A(2)), SX16(A(3)), SX16(A(4)), SX16(A(5)),
                       A(6)));
    2057 : W16RegisterClass(A(1));
    2058 : SetAX(GetClassNameA(A(1), A(2), A(3)));
    2059 : SetAX(SetActiveWindow(A(1)));
    2060 : SetAX(GetActiveWindow);
    2066 : SetAX(GetDC(A(1)));
    2067 : SetAX(GetWindowDC(A(1)));
    2068 : SetAX(ReleaseDC(A(1), A(2)));
    2069 : SetAX(SetCursor(A(1)));
    2071 : SetAX(ShowCursor(A(1)));
    2076 :
    Begin
      Rect16To32(A(1), W16Buf);
      SetAX(PtInRect(W16Buf, SX16(A(2)), SX16(A(2) Shr 16)));
    End;
    2072 :
    Begin
      MemL[0:W16Buf] := A(2); MemL[0:W16Buf + 4] := A(3);
      MemL[0:W16Buf + 8] := A(4); MemL[0:W16Buf + 12] := A(5);
      Rect32To16(W16Buf, A(1));
    End;
    2081 :
    Begin
      Rect16To32(A(2), W16Buf);
      SetAX(FillRect(A(1), W16Buf, A(3)));
    End;
    2085 :
    Begin
      Rect16To32(A(4), W16Buf);
      R := DrawTextA(A(1), A(2), A(3), W16Buf, A(5));
      Rect32To16(W16Buf, A(4));
      SetAX(R);
    End;
    2106 : SetAX(GetKeyState(A(1)));
    2107 : SetDXAX(CallWnd16(0, A(1), A(2), A(3), A(4), True));
    2108, 2109 :
    Begin
      If Code = 2108 Then R := GetMessageA(W16Buf + 64, A(2), A(3), A(4))
      Else R := PeekMessageA(W16Buf + 64, A(2), A(3), A(4), A(5));
      If (R <> 0) Or (Code = 2108) Then Msg32To16(W16Buf + 64, A(1));
      SetAX(R);
    End;
    2110 :
    Begin
      H := A(1); M := A(2); P := A(3); R := A(4);
      Msg16To32(H, M, P, R);
      SetAX(PostMessageA(H, M, P, R));
    End;
    2111 : SetDXAX(SendMsg16(A(1), A(2), A(3), A(4)));
    2112 : SetAX(WaitMessage);
    2113 :
    Begin
      Msg16To32P(A(1), W16Buf + 64);
      SetAX(TranslateMessage(W16Buf + 64));
    End;
    2114 :
    Begin
      P := A(1);
      H := MemW[0:P];
      K := WndOf(H);
      If (K >= 0) And (Pr16Of(Wnds[K].Proc) >= 0) And
         (MemW[0:P + 2] <> $113) Then
        SetDXAX(CallWnd16(Wnds[K].Proc, H, MemW[0:P + 2], MemW[0:P + 4],
                          MemL[0:P + 6], False))
      Else
      Begin
        Msg16To32P(P, W16Buf + 64);
        SetDXAX(DispatchMessageA(W16Buf + 64));
      End;
    End;
    2118 : SetAX(RegisterWindowMessageA(A(1)));
    2122 :
    Begin
      P := ArgRaw[1];
      For K := 0 To Pr16N - 1 Do
        If Pr16Proc[K] = P Then P := Pr16Stub[K];
      SetDXAX(CallWnd16(P, A(2), A(3), A(4), A(5), False));
    End;
    2124 : SetAX(UpdateWindow(A(1)));
    2125 :
      If A(2) = 0 Then SetAX(InvalidateRect(A(1), 0, A(3)))
      Else
      Begin
        Rect16To32(A(2), W16Buf);
        SetAX(InvalidateRect(A(1), W16Buf, A(3)));
      End;
    2126 : SetAX(InvalidateRgn(A(1), A(2), A(3)));
    2127 :
      If A(2) = 0 Then SetAX(ValidateRect(A(1), 0))
      Else
      Begin
        Rect16To32(A(2), W16Buf);
        SetAX(ValidateRect(A(1), W16Buf));
      End;
    2128 : SetAX(ValidateRect(A(1), 0));
    2133 : SetAX(GetWindowWord(A(1), A(2)));
    2134 : SetAX(SetWindowWord(A(1), A(2), A(3)));
    2135 :
    Begin
      R := GetWindowLongA(A(1), A(2));
      If (A(2) = -4) And (Proc16Of(R) <> 0) Then R := Proc16Of(R);
      SetDXAX(R);
    End;
    2136 :
    Begin
      R := A(3);
      If A(2) = -4 Then R := MakeBridge(ArgRaw[3], W16Inst);
      R := SetWindowLongA(A(1), A(2), R);
      If (A(2) = -4) And (Proc16Of(R) <> 0) Then R := Proc16Of(R);
      SetDXAX(R);
    End;
    2150 : SetAX(LoadMenuA(W16Inst, A(2)));
    2158 : SetAX(SetMenu(A(1), A(2)));
    2157 : SetAX(GetMenu(A(1)));
    2173 :
    Begin
      If (ArgRaw[2] Shr 16) = 0 Then P := ArgRaw[2] And $FFFF Else P := A(2);
      If A(1) = 0 Then SetAX(LoadCursorA(0, P))
      Else SetAX(LoadCursorA(0, $7F00));
    End;
    2174 :
    Begin
      If (ArgRaw[2] Shr 16) = 0 Then P := ArgRaw[2] And $FFFF Else P := A(2);
      If A(1) = 0 Then SetAX(LoadIconA(0, P)) Else SetAX(LoadIconA(0, $7F00));
    End;
    2176 : SetAX(LoadString16(A(1), A(2), A(3), A(4)));
    2179 : SetAX(GetSystemMetrics(A(1)));
    2180 : SetDXAX(GetSysColor(A(1)));
    2232 :
      SetAX(SetWindowPos(A(1), A(2), SX16(A(3)), SX16(A(4)), SX16(A(5)),
                         SX16(A(6)), A(7)));
    2262 : SetAX(GetWindow(A(1), A(2)));
    2284 : SetAX(90);
    2224 :
    Begin
      K := WndOf(A(1));
      If K >= 0 Then SetAX($8000 + Wnds[K].Thread);
    End;
    2286 : SetAX(GetDesktopWindow);
    2420 :
    Begin
      R := WSPrintf16(Lin16(MemL[0:ArgLin]), Lin16(MemL[0:ArgLin + 4]),
                      ArgLin + 8);
      SetAX(R);
    End;
    2421 :
      SetAX(WSPrintf16(A(1), A(2), Lin16(ArgRaw[3])));
    2430 : SetAX(lstrcmpA(A(1), A(2)));
    2431, 2432 :
    Begin
      If (ArgRaw[1] Shr 16) = 0 Then
      Begin
        R := ArgRaw[1] And $FF;
        If (Code = 2431) And (R >= 97) And (R <= 122) Then R := R - 32;
        If (Code = 2432) And (R >= 65) And (R <= 90) Then R := R + 32;
        SetDXAX(R);
      End
      Else
      Begin
        P := Lin16(ArgRaw[1]);
        While Mem[0:P] <> 0 Do
        Begin
          R := Mem[0:P];
          If (Code = 2431) And (R >= 97) And (R <= 122) Then Mem[0:P] := R - 32;
          If (Code = 2432) And (R >= 65) And (R <= 90) Then Mem[0:P] := R + 32;
          Inc(P);
        End;
        SetDXAX(ArgRaw[1]);
      End;
    End;
    2471 : SetAX(lstrcmpiA(A(1), A(2)));
    2472 :
      If Mem[0:Lin16(ArgRaw[1])] <> 0 Then SetDXAX(ArgRaw[1] + 1)
      Else SetDXAX(ArgRaw[1]);
    2473 :
      If Lin16(ArgRaw[2]) > A(1) Then SetDXAX(ArgRaw[2] - 1)
      Else SetDXAX(ArgRaw[2]);
    { ---------------------------------- GDI -------------------------- }
    3001 : SetDXAX(SetBkColor(A(1), A(2)));
    3002 : SetAX(SetBkMode(A(1), A(2)));
    3009 : SetDXAX(SetTextColor(A(1), A(2)));
    3033 : SetAX(TextOutA(A(1), SX16(A(2)), SX16(A(3)), A(4), A(5)));
    3045 : SetAX(SelectObject(A(1), A(2)));
    3066 : SetAX(CreateSolidBrush(A(1)));
    3069 : SetAX(DeleteObject(A(1)));
    3080 : SetAX(GetDeviceCaps(A(1), A(2)));
    3087 : SetAX(GetStockObject(A(1)));
    { ------------------------------- KEYBOARD ------------------------ }
    4005, 4006 :
    Begin
      If A(1) <> A(2) Then RetStrCopy(A(2), A(1), 65536);
      SetAX(1);
    End;
    { ------------------------------- LZEXPAND ------------------------ }
    5001 :
    Begin
      N := 0;
      Repeat
        If Not KReadFile(DosHGet(A(1)), W16Buf, 4096, K) Then K := 0;
        If K > 0 Then
        Begin
          KWriteFile(DosHGet(A(2)), W16Buf, K);
          N := N + K;
        End;
      Until K <= 0;
      SetDXAX(N);
    End;
    5002 :
    Begin
      R := OpenFile(A(1), A(2), A(3));
      If R = -1 Then SetAX($FFFF) Else SetAX(DosHNew(R));
    End;
    5006 : DosHClose(A(1));
    { --------------------------------- SHELL ------------------------- }
    6001 : SetDXAX(RegOpenKeyA(A(1), A(2), A(3)));
    6002 : SetDXAX(RegCreateKeyA(A(1), A(2), A(3)));
    6003 : SetDXAX(0);
    6004 : SetDXAX(RegDeleteKeyA(A(1), A(2)));
    6005 : SetDXAX(RegSetValueA(A(1), A(2), A(3), A(4), A(5)));
    6006 : SetDXAX(RegQueryValueA(A(1), A(2), A(3), A(4)));
    6007 : SetDXAX(RegEnumKeyA(A(1), A(2), A(3), A(4)));
  Else
    If Not ApiWarned[Idx] Then
    Begin
      ApiWarned[Idx] := True;
      KLog('Win16 : API non implementee ' + ApiName(Idx) + ' (' +
           W16SysMods[Pos(ApiLet[Idx], SysLetS)] + '.' +
           IntStr(ApiOrd[Idx]) + ')');
    End;
  End;
End;

{ Environnement DOS, chemins et portes d'interruption de niveau 3 }
Procedure W16Init2;
Var P, N : LongInt;
Begin
  W16Trace := False;
  WinIni := 'C:\WINDOWS\WIN.INI';
  WinDirZ := 'C:\WINDOWS';
  SysDirZ := 'C:\WINDOWS\SYSTEM';
  P := GetEnvironmentStringsA;
  N := 0;
  While (MemW[0:P + N] <> 0) And (N < 4000) Do Inc(N);
  W16Env := GAlloc16(N + 64, False);
  GOwner[W16Env Shr 3] := 0;
  MoveMem(P, SelBase(W16Env), N + 2);
  SetGate($21, LongInt(@Int21Gate));
  SetGate($2F, LongInt(@Int2FGate));
  SetGate($31, LongInt(@Int2FGate));
  Idt[$21].Flags := $EE00;
  Idt[$2F].Flags := $EE00;
  Idt[$31].Flags := $EE00;
End;

{ ==================================================================== }
{ Partie 15 - DirectX : DirectDraw, DirectSound, DirectInput, DSETUP   }
{ ==================================================================== }
{ DirectX est integre au noyau comme les autres DLL systeme (DDRAW.DLL,
  DSOUND.DLL, DINPUT.DLL, DSETUP.DLL) : les objets COM sont des blocs
  dont le premier mot pointe sur une table de methodes ; chaque methode
  est une fonction du noyau exportee en stdcall.
  Objet : +0 table, +4 references, +8 sorte (1 DirectDraw, 2 vue
  DirectDraw2, 3 surface, 4 palette, 5 decoupeur, 6 DirectSound,
  7 tampon de son, 8 DirectInput, 9 peripherique d'entree).
  DirectDraw : affichage 640x480 en 256 couleurs ; en mode exclusif la
  surface primaire est copiee telle quelle sur l'ecran (FlushScreen) et
  sa palette devient la palette materielle. DirectSound : tampons
  muets dont la position de lecture avance en temps reel (comme la
  carte son muette). DirectInput : clavier (codes de balayage) et
  souris (deplacements relatifs). }

Const
  DD_OK = 0;
  E_NOTIMPL = LongInt($80004001);
  E_NOINTERFACE = LongInt($80004002);
  DDERR_INVALIDPARAMS = LongInt($80070057);
  DDERR_INVALIDMODE = LongInt($88760078);
  DDERR_NOTFOUND = LongInt($887600FF);
  DDERR_WASSTILLDRAWING = LongInt($8876021C);

Var
  VtDD, VtDD2, VtSurf, VtPal, VtClip, VtDS, VtDSB, VtDI, VtDID : LongInt;
  DDCoopWnd, DDCoopFl, DDBpp : LongInt;
  DDPrimary : LongInt;

{ Table de methodes : VtNew puis VtAdd('nom,nom,...') (listes courtes,
  une chaine Pascal est limitee a 255 caracteres) }
Var
  VtCur, VtCnt : LongInt;

Function VtNew : LongInt;
Begin
  VtCur := KAlloc(256);
  VtCnt := 0;
  VtNew := VtCur;
End;

Procedure VtAdd(S : String);
Var P : LongInt; Nm : String;
Begin
  While S <> '' Do
  Begin
    P := Pos(',', S);
    If P > 0 Then
    Begin
      Nm := Copy(S, 1, P - 1); Delete(S, 1, P);
    End
    Else
    Begin
      Nm := S; S := '';
    End;
    Nm := Trim(Nm);
    MemL[0:VtCur + VtCnt * 4] := KernelExport(Nm);
    If MemL[0:VtCur + VtCnt * 4] = 0 Then
      KLog('DirectX : methode absente ' + Nm);
    Inc(VtCnt);
  End;
End;

Function ComNew(Vt, Kind, Size : LongInt) : LongInt;
Var O : LongInt;
Begin
  O := KAlloc(Size);
  FillMem(O, Size, 0);
  MemL[0:O] := Vt;
  MemL[0:O + 4] := 1;
  MemL[0:O + 8] := Kind;
  ComNew := O;
End;

Function GuidIs(P, D1 : LongInt) : Boolean;
Begin
  GuidIs := (P <> 0) And (MemL[0:P] = D1);
End;

{ Methodes non ecrites, selon le nombre d'arguments (This compris) }
Function DXNI1(T : LongInt) : LongInt;
Begin
  DXNI1 := E_NOTIMPL;
End;

Function DXNI2(T, A : LongInt) : LongInt;
Begin
  DXNI2 := E_NOTIMPL;
End;

Function DXNI3(T, A, B : LongInt) : LongInt;
Begin
  DXNI3 := E_NOTIMPL;
End;

Function DXNI4(T, A, B, C : LongInt) : LongInt;
Begin
  DXNI4 := E_NOTIMPL;
End;

Function DXNI5(T, A, B, C, D : LongInt) : LongInt;
Begin
  DXNI5 := E_NOTIMPL;
End;

Function DXNI6(T, A, B, C, D, E : LongInt) : LongInt;
Begin
  DXNI6 := E_NOTIMPL;
End;

Function DXOK1(T : LongInt) : LongInt;
Begin
  DXOK1 := DD_OK;
End;

Function DXOK2(T, A : LongInt) : LongInt;
Begin
  DXOK2 := DD_OK;
End;

Function DXOK3(T, A, B : LongInt) : LongInt;
Begin
  DXOK3 := DD_OK;
End;

Function COMAddRef(T : LongInt) : LongInt;
Begin
  MemL[0:T + 4] := MemL[0:T + 4] + 1;
  COMAddRef := MemL[0:T + 4];
End;

Procedure SurfFreeK(S : LongInt);
Begin
  If S = DDPrimary Then
  Begin
    DDPrimary := 0;
    DDShow := False;
    DefaultPalette;
    MarkAll;
  End
  Else If MemL[0:S + 24] <> 0 Then KFree(MemL[0:S + 24]);
  If MemL[0:S + 32] <> 0 Then SurfFreeK(MemL[0:S + 32]);
End;

Function COMRelease(T : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := MemL[0:T + 4] - 1;
  MemL[0:T + 4] := R;
  COMRelease := R;
  If R > 0 Then Exit;
  If MemL[0:T + 8] = 3 Then SurfFreeK(T);
  If (MemL[0:T + 8] = 7) And (MemL[0:T + 16] <> 0) Then
    KFree(MemL[0:T + 16]);
  If MemL[0:T + 8] = 1 Then
  Begin
    DDShow := False;
    DDCoopFl := 0;
    MarkAll;
  End;
End;

Function COMQIUnk(T, Riid, Ppv : LongInt) : LongInt;
Begin
  COMQIUnk := E_NOINTERFACE;
  If Ppv = 0 Then Exit;
  MemL[0:Ppv] := 0;
  If GuidIs(Riid, 0) Then
  Begin
    MemL[0:Ppv] := T;
    COMAddRef(T);
    COMQIUnk := DD_OK;
  End;
End;

{ ------------------------------------------------------------------ }
{ DirectDraw                                                         }
{ ------------------------------------------------------------------ }

Procedure DDInitVt;
Begin
  If VtDD <> 0 Then Exit;
  VtDD := VtNew;
  VtAdd('DD_QI,COMAddRef,COMRelease,DXOK1,DD_CreateClipper,');
  VtAdd('DD_CreatePalette,DD_CreateSurface,DXNI3,DD_EnumDisplayModes,');
  VtAdd('DXNI5,DD_FlipToGDISurface,DD_GetCaps,DD_GetDisplayMode,DXNI3,');
  VtAdd('DXNI2,DD_GetMonitorFrequency,DD_GetScanLine,DD_GetVBStatus,');
  VtAdd('DXOK2,DD_RestoreDisplayMode,DD_SetCooperativeLevel,');
  VtAdd('DD_SetDisplayMode,DD_WaitForVB');
  VtDD2 := VtNew;
  VtAdd('DD_QI,COMAddRef,COMRelease,DXOK1,DD_CreateClipper,');
  VtAdd('DD_CreatePalette,DD_CreateSurface,DXNI3,DD_EnumDisplayModes,');
  VtAdd('DXNI5,DD_FlipToGDISurface,DD_GetCaps,DD_GetDisplayMode,DXNI3,');
  VtAdd('DXNI2,DD_GetMonitorFrequency,DD_GetScanLine,DD_GetVBStatus,');
  VtAdd('DXOK2,DD_RestoreDisplayMode,DD_SetCooperativeLevel,');
  VtAdd('DD_SetDisplayMode2,DD_WaitForVB,DD_GetAvailableVidMem');
  VtSurf := VtNew;
  VtAdd('SF_QI,COMAddRef,COMRelease,DXOK2,DXNI2,SF_Blt,');
  VtAdd('DXNI4,SF_BltFast,DXOK3,DXNI3,DXNI4,SF_Flip,SF_GetAttachedSurface,');
  VtAdd('DXOK2,SF_GetCaps,DXNI2,SF_GetColorKey,SF_GetDC,DXOK2,DXNI3,');
  VtAdd('SF_GetPalette,SF_GetPixelFormat,SF_GetSurfaceDesc,DXOK3,DXOK1,');
  VtAdd('SF_Lock,SF_ReleaseDC,DXOK1,SF_SetClipper,SF_SetColorKey,DXNI3,');
  VtAdd('SF_SetPalette,SF_Unlock,DXNI6,DXNI2,DXNI3,SF_GetDDInterface,');
  VtAdd('DXOK2,DXOK2,DXNI3');
  VtPal := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,PL_GetCaps,');
  VtAdd('PL_GetEntries,DXOK4,PL_SetEntries');
  VtClip := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,DXNI4,CL_GetHWnd,');
  VtAdd('DXOK3,CL_IsClipListChanged,DXOK3,CL_SetHWnd');
End;

Function DXOK4(T, A, B, C : LongInt) : LongInt;
Begin
  DXOK4 := DD_OK;
End;

Function DirectDrawCreate(Guid, PDD, Outer : LongInt) : LongInt;
Var O : LongInt;
Begin
  DDInitVt;
  DirectDrawCreate := DDERR_INVALIDPARAMS;
  If PDD = 0 Then Exit;
  O := ComNew(VtDD, 1, 32);
  MemL[0:PDD] := O;
  If DDW = 0 Then
  Begin
    DDW := 640; DDH := 480; DDBpp := 8;
  End;
  KLog('DirectDraw : objet cree');
  DirectDrawCreate := DD_OK;
End;

Function DirectDrawEnumerateA(Cb, Ctx : LongInt) : LongInt;
Var S1, S2 : String;
Begin
  S1 := 'Pasdows 95 VESA' + #0;
  S2 := 'display' + #0;
  If W16Buf = 0 Then W16Buf := KAlloc(4096);
  MemL[0:W16Buf] := 0;
  MemL[0:W16Buf + 4] := LongInt(@S1[1]);
  MemL[0:W16Buf + 8] := LongInt(@S2[1]);
  MemL[0:W16Buf + 12] := Ctx;
  CallStd(Cb, W16Buf, 4);
  DirectDrawEnumerateA := DD_OK;
End;

Function DD_QI(T, Riid, Ppv : LongInt) : LongInt;
Var O : LongInt;
Begin
  DD_QI := E_NOINTERFACE;
  If Ppv = 0 Then Exit;
  MemL[0:Ppv] := 0;
  If GuidIs(Riid, LongInt($6C14DB80)) Or GuidIs(Riid, 0) Then
  Begin
    MemL[0:Ppv] := T;
    COMAddRef(T);
    DD_QI := DD_OK;
  End
  Else If GuidIs(Riid, LongInt($B3A6F3E0)) Then
  Begin
    O := ComNew(VtDD2, 2, 32);
    MemL[0:Ppv] := O;
    DD_QI := DD_OK;
  End;
End;

Function DD_SetCooperativeLevel(T, H, Fl : LongInt) : LongInt;
Begin
  DDCoopWnd := H;
  DDCoopFl := Fl;
  KLog('DirectDraw : niveau de cooperation ' + HexStr(Fl, 4));
  DD_SetCooperativeLevel := DD_OK;
End;

Function DD_SetDisplayMode(T, W, H, Bpp : LongInt) : LongInt;
Begin
  DD_SetDisplayMode := DDERR_INVALIDMODE;
  KLog('DirectDraw : mode ' + IntStr(W) + 'x' + IntStr(H) + 'x' +
       IntStr(Bpp));
  If (Bpp <> 8) Or (W > ScrW) Or (H > ScrH) Or (W <= 0) Or (H <= 0) Then
    Exit;
  DDW := W; DDH := H; DDBpp := 8;
  DD_SetDisplayMode := DD_OK;
End;

Function DD_SetDisplayMode2(T, W, H, Bpp, Rate, Fl : LongInt) : LongInt;
Begin
  DD_SetDisplayMode2 := DD_SetDisplayMode(T, W, H, Bpp);
End;

Function DD_RestoreDisplayMode(T : LongInt) : LongInt;
Begin
  DDW := 640; DDH := 480;
  DD_RestoreDisplayMode := DD_OK;
End;

Function DD_FlipToGDISurface(T : LongInt) : LongInt;
Begin
  DD_FlipToGDISurface := DD_OK;
End;

{ DDSURFACEDESC (108 octets) d'une surface 8 bits }
Procedure DDFillDesc(P, W, H, Pitch, Bits, Caps : LongInt);
Begin
  FillMem(P, 108, 0);
  MemL[0:P] := 108;
  MemL[0:P + 4] := $100F Or $800;
  MemL[0:P + 8] := H;
  MemL[0:P + 12] := W;
  MemL[0:P + 16] := Pitch;
  MemL[0:P + 36] := Bits;
  MemL[0:P + 72] := 32;
  MemL[0:P + 76] := $60;
  MemL[0:P + 84] := 8;
  MemL[0:P + 104] := Caps;
End;

Function DD_EnumDisplayModes(T, Fl, PDesc, Ctx, Cb : LongInt) : LongInt;
Var D, K, W, H : LongInt;
Begin
  D := KAlloc(128);
  For K := 0 To 2 Do
  Begin
    Case K Of
      0 : Begin W := 320; H := 200 End;
      1 : Begin W := 320; H := 240 End;
    Else
      W := 640; H := 480;
    End;
    DDFillDesc(D, W, H, W, 0, 0);
    MemL[0:D + 4] := $1006;
    If W16Buf = 0 Then W16Buf := KAlloc(4096);
    MemL[0:W16Buf] := D;
    MemL[0:W16Buf + 4] := Ctx;
    If CallStd(Cb, W16Buf, 2) = 0 Then Break;
  End;
  KFree(D);
  DD_EnumDisplayModes := DD_OK;
End;

Function DD_GetDisplayMode(T, P : LongInt) : LongInt;
Begin
  DDFillDesc(P, DDW, DDH, DDW, 0, 0);
  MemL[0:P + 4] := $100E;
  DD_GetDisplayMode := DD_OK;
End;

{ DDCAPS : capacites materielles et logicielles }
Function DD_GetCaps(T, PHal, PHel : LongInt) : LongInt;
Var K, P, Sz : LongInt;
Begin
  For K := 0 To 1 Do
  Begin
    If K = 0 Then P := PHal Else P := PHel;
    If P = 0 Then Continue;
    Sz := MemL[0:P];
    If (Sz <= 0) Or (Sz > 512) Then Sz := 316;
    FillMem(P + 4, Sz - 4, 0);
    MemL[0:P + 4] := $40 Or $200 Or $400000 Or $04000000 Or $08000000;
    MemL[0:P + 16] := $200;
    MemL[0:P + 28] := 4;
    MemL[0:P + 60] := 4 * 1024 * 1024;
    MemL[0:P + 64] := 4 * 1024 * 1024;
    MemL[0:P + 72] := $240;
  End;
  DD_GetCaps := DD_OK;
End;

Function DD_GetMonitorFrequency(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := 60;
  DD_GetMonitorFrequency := DD_OK;
End;

Function DD_GetScanLine(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := (Ticks * 31) Mod 525;
  DD_GetScanLine := DD_OK;
End;

Function DD_GetVBStatus(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := Ord(Ticks Mod 16 < 2);
  DD_GetVBStatus := DD_OK;
End;

Function DD_WaitForVB(T, Fl, Ev : LongInt) : LongInt;
Begin
  KSleep(16 - Ticks Mod 16);
  DD_WaitForVB := DD_OK;
End;

Function DD_GetAvailableVidMem(T, Caps, PTot, PFree : LongInt) : LongInt;
Begin
  If PTot <> 0 Then MemL[0:PTot] := 4 * 1024 * 1024;
  If PFree <> 0 Then MemL[0:PFree] := 4 * 1024 * 1024;
  DD_GetAvailableVidMem := DD_OK;
End;

{ Surface : +12 largeur, +16 hauteur, +20 pas, +24 bits, +28 capacites,
  +32 tampon arriere attache, +36 palette, +40/+44 cle de couleur
  source, +48 cle active, +52 DC, +56 decoupeur }
Function SurfMake(W, H, Caps, Bits : LongInt) : LongInt;
Var S : LongInt;
Begin
  S := ComNew(VtSurf, 3, 64);
  MemL[0:S + 12] := W; MemL[0:S + 16] := H;
  MemL[0:S + 20] := (W + 3) And Not 3;
  If Bits = 0 Then
  Begin
    Bits := KAlloc(MemL[0:S + 20] * H + 16);
    FillMem(Bits, MemL[0:S + 20] * H, 0);
  End
  Else MemL[0:S + 20] := W;
  MemL[0:S + 24] := Bits;
  MemL[0:S + 28] := Caps;
  SurfMake := S;
End;

Function DD_CreateSurface(T, PDesc, PSurf, Outer : LongInt) : LongInt;
Var Fl, Caps, W, H, S, B, N : LongInt;
Begin
  DD_CreateSurface := DDERR_INVALIDPARAMS;
  If (PDesc = 0) Or (PSurf = 0) Then Exit;
  Fl := MemL[0:PDesc + 4];
  Caps := 0;
  If (Fl And 1) <> 0 Then Caps := MemL[0:PDesc + 104];
  If (Caps And $200) <> 0 Then
  Begin
    { surface primaire : l'ecran }
    If DDBuf = 0 Then DDBuf := KAlloc(ScrW * ScrH + 16);
    FillMem(DDBuf, ScrW * ScrH, 0);
    S := SurfMake(DDW, DDH, Caps Or $20 Or $4000, DDBuf);
    DDPrimary := S;
    If (DDCoopFl And $11) = $11 Then
    Begin
      DDShow := True;
      DDDirty := True;
    End;
    N := 0;
    If (Fl And $20) <> 0 Then N := MemL[0:PDesc + 20];
    If N > 0 Then
    Begin
      B := SurfMake(DDW, DDH, (Caps And Not $220) Or 4 Or $4000, 0);
      MemL[0:S + 32] := B;
    End;
    KLog('DirectDraw : surface primaire ' + IntStr(DDW) + 'x' +
         IntStr(DDH) + ', ' + IntStr(N) + ' tampon(s) arriere');
  End
  Else
  Begin
    W := MemL[0:PDesc + 12]; H := MemL[0:PDesc + 8];
    If ((Fl And 4) = 0) Or (W <= 0) Then W := DDW;
    If ((Fl And 2) = 0) Or (H <= 0) Then H := DDH;
    S := SurfMake(W, H, Caps Or $40, 0);
    If (Fl And $10000) <> 0 Then
    Begin
      MemL[0:S + 40] := MemL[0:PDesc + 64];
      MemL[0:S + 44] := MemL[0:PDesc + 68];
      MemL[0:S + 48] := 1;
    End;
  End;
  MemL[0:PSurf] := S;
  DD_CreateSurface := DD_OK;
End;

Function DD_CreatePalette(T, Fl, PEnt, PPal, Outer : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := ComNew(VtPal, 4, 16 + 1024);
  If PEnt <> 0 Then MoveMem(PEnt, P + 16, 1024);
  MemL[0:P + 12] := Fl;
  If PPal <> 0 Then MemL[0:PPal] := P;
  DD_CreatePalette := DD_OK;
End;

Function DD_CreateClipper(T, Fl, PClip, Outer : LongInt) : LongInt;
Begin
  If PClip <> 0 Then MemL[0:PClip] := ComNew(VtClip, 5, 16);
  DD_CreateClipper := DD_OK;
End;

{ Palette : +12 drapeaux, +16 entrees ; appliquee a l'ecran si elle est
  celle de la surface primaire }
Procedure PalApply(P : LongInt);
Var I, E : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    E := P + 16 + I * 4;
    SysPalSet(I, Mem[0:E], Mem[0:E + 1], Mem[0:E + 2]);
  End;
  Inc(PalVer);
  DacAll;
End;

Function PL_GetCaps(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := 4 Or $400;
  PL_GetCaps := DD_OK;
End;

Function PL_GetEntries(T, Fl, Start, N, PEnt : LongInt) : LongInt;
Begin
  If (Start >= 0) And (Start + N <= 256) Then
    MoveMem(T + 16 + Start * 4, PEnt, N * 4);
  PL_GetEntries := DD_OK;
End;

Function PL_SetEntries(T, Fl, Start, N, PEnt : LongInt) : LongInt;
Begin
  PL_SetEntries := DDERR_INVALIDPARAMS;
  If (Start < 0) Or (Start + N > 256) Then Exit;
  MoveMem(PEnt, T + 16 + Start * 4, N * 4);
  If (DDPrimary <> 0) And (MemL[0:DDPrimary + 36] = T) Then PalApply(T);
  PL_SetEntries := DD_OK;
End;

Function CL_GetHWnd(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := MemL[0:T + 12];
  CL_GetHWnd := DD_OK;
End;

Function CL_IsClipListChanged(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := 0;
  CL_IsClipListChanged := DD_OK;
End;

Function CL_SetHWnd(T, Fl, H : LongInt) : LongInt;
Begin
  MemL[0:T + 12] := H;
  CL_SetHWnd := DD_OK;
End;

{ Surfaces }

Function SF_QI(T, Riid, Ppv : LongInt) : LongInt;
Begin
  SF_QI := E_NOINTERFACE;
  If Ppv = 0 Then Exit;
  MemL[0:Ppv] := 0;
  If GuidIs(Riid, 0) Or GuidIs(Riid, LongInt($6C14DB81)) Or
     GuidIs(Riid, LongInt($57805885)) Or GuidIs(Riid, LongInt($DA044E00))
  Then
  Begin
    MemL[0:Ppv] := T;
    COMAddRef(T);
    SF_QI := DD_OK;
  End;
End;

{ Mise a jour de l'ecran apres un changement de la surface primaire }
Procedure SurfTouched(S : LongInt);
Var R : TRect; Y : LongInt;
Begin
  If S <> DDPrimary Then Exit;
  If DDShow Then
  Begin
    DDDirty := True;
    Exit;
  End;
  { fenetre : la primaire est l'ecran, recopiee dans le tampon }
  For Y := 0 To Min(DDH, ScrH) - 1 Do
    MoveMem(DDBuf + Y * DDW, Back.Bits + Y * Back.Pitch, Min(DDW, ScrW));
  SetR(R, 0, 0, ScrW, ScrH);
  MarkDirty(R);
End;

Function SF_GetSurfaceDesc(T, P : LongInt) : LongInt;
Begin
  DDFillDesc(P, MemL[0:T + 12], MemL[0:T + 16], MemL[0:T + 20],
             MemL[0:T + 24], MemL[0:T + 28]);
  SF_GetSurfaceDesc := DD_OK;
End;

Function SF_Lock(T, PRect, PDesc, Fl, Ev : LongInt) : LongInt;
Begin
  SF_GetSurfaceDesc(T, PDesc);
  If PRect <> 0 Then
    MemL[0:PDesc + 36] := MemL[0:T + 24] + MemL[0:PRect + 4] *
                          MemL[0:T + 20] + MemL[0:PRect];
  SF_Lock := DD_OK;
End;

Function SF_Unlock(T, P : LongInt) : LongInt;
Begin
  SurfTouched(T);
  SF_Unlock := DD_OK;
End;

Function SF_GetCaps(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := MemL[0:T + 28];
  SF_GetCaps := DD_OK;
End;

Function SF_GetPixelFormat(T, P : LongInt) : LongInt;
Begin
  FillMem(P, 32, 0);
  MemL[0:P] := 32; MemL[0:P + 4] := $60; MemL[0:P + 12] := 8;
  SF_GetPixelFormat := DD_OK;
End;

Function SF_GetAttachedSurface(T, PCaps, PSurf : LongInt) : LongInt;
Begin
  SF_GetAttachedSurface := DDERR_NOTFOUND;
  If (PSurf = 0) Or (MemL[0:T + 32] = 0) Then Exit;
  MemL[0:PSurf] := MemL[0:T + 32];
  COMAddRef(MemL[0:T + 32]);
  SF_GetAttachedSurface := DD_OK;
End;

{ Echange des tampons de la chaine primaire / arriere }
Function SF_Flip(T, Ovr, Fl : LongInt) : LongInt;
Var B, Tmp : LongInt;
Begin
  SF_Flip := DD_OK;
  B := MemL[0:T + 32];
  If B = 0 Then Exit;
  If T = DDPrimary Then
  Begin
    { la primaire garde DDBuf : on y recopie le tampon arriere, qui
      recoit l'ancienne image (echange) }
    Tmp := KAlloc(DDW * DDH);
    MoveMem(DDBuf, Tmp, DDW * DDH);
    MoveMem(MemL[0:B + 24], DDBuf, DDW * DDH);
    MoveMem(Tmp, MemL[0:B + 24], DDW * DDH);
    KFree(Tmp);
    SurfTouched(T);
  End
  Else
  Begin
    Tmp := MemL[0:T + 24];
    MemL[0:T + 24] := MemL[0:B + 24];
    MemL[0:B + 24] := Tmp;
  End;
End;

Function SF_GetColorKey(T, Fl, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    MemL[0:P] := MemL[0:T + 40]; MemL[0:P + 4] := MemL[0:T + 44];
  End;
  SF_GetColorKey := DD_OK;
End;

Function SF_SetColorKey(T, Fl, P : LongInt) : LongInt;
Begin
  If P = 0 Then MemL[0:T + 48] := 0
  Else
  Begin
    MemL[0:T + 40] := MemL[0:P]; MemL[0:T + 44] := MemL[0:P + 4];
    MemL[0:T + 48] := 1;
  End;
  SF_SetColorKey := DD_OK;
End;

Function SF_SetPalette(T, P : LongInt) : LongInt;
Begin
  MemL[0:T + 36] := P;
  If P <> 0 Then COMAddRef(P);
  If (T = DDPrimary) And (P <> 0) And DDShow Then
  Begin
    PalApply(P);
    DDDirty := True;
  End;
  SF_SetPalette := DD_OK;
End;

Function SF_GetPalette(T, PP : LongInt) : LongInt;
Begin
  SF_GetPalette := DDERR_NOTFOUND;
  If (PP = 0) Or (MemL[0:T + 36] = 0) Then Exit;
  MemL[0:PP] := MemL[0:T + 36];
  COMAddRef(MemL[0:T + 36]);
  SF_GetPalette := DD_OK;
End;

Function SF_SetClipper(T, C : LongInt) : LongInt;
Begin
  MemL[0:T + 56] := C;
  SF_SetClipper := DD_OK;
End;

Function SF_GetDDInterface(T, P : LongInt) : LongInt;
Begin
  SF_GetDDInterface := E_NOTIMPL;
End;

{ Transfert de SRect (src) vers DRect (dst) avec mise a l'echelle et
  cle de couleur source eventuelle }
Procedure SurfBlt(D, DL, DT, DR, DB, S, SL, ST, SR, SB : LongInt;
                  Key : Boolean);
Var X, Y, SX, SY, DW, DH, SW, SH, V, K, DA, SA : LongInt;
Begin
  If DL < 0 Then DL := 0;
  If DT < 0 Then DT := 0;
  If DR > MemL[0:D + 12] Then DR := MemL[0:D + 12];
  If DB > MemL[0:D + 16] Then DB := MemL[0:D + 16];
  DW := DR - DL; DH := DB - DT; SW := SR - SL; SH := SB - ST;
  If (DW <= 0) Or (DH <= 0) Or (SW <= 0) Or (SH <= 0) Then Exit;
  K := MemL[0:S + 40] And $FF;
  For Y := 0 To DH - 1 Do
  Begin
    SY := ST + (Y * SH) Div DH;
    If (SY < 0) Or (SY >= MemL[0:S + 16]) Then Continue;
    DA := MemL[0:D + 24] + (DT + Y) * MemL[0:D + 20] + DL;
    SA := MemL[0:S + 24] + SY * MemL[0:S + 20];
    If (DW = SW) And Not Key And (SL >= 0) And
       (SL + SW <= MemL[0:S + 12]) Then
    Begin
      MoveMem(SA + SL, DA, DW);
      Continue;
    End;
    For X := 0 To DW - 1 Do
    Begin
      SX := SL + (X * SW) Div DW;
      If (SX < 0) Or (SX >= MemL[0:S + 12]) Then Continue;
      V := Mem[0:SA + SX];
      If Key And (V = K) Then Continue;
      Mem[0:DA + X] := V;
    End;
  End;
End;

Procedure RectOr(P, W, H : LongInt; Var L, T, R, B : LongInt);
Begin
  If P = 0 Then
  Begin
    L := 0; T := 0; R := W; B := H;
  End
  Else
  Begin
    L := MemL[0:P]; T := MemL[0:P + 4];
    R := MemL[0:P + 8]; B := MemL[0:P + 12];
  End;
End;

Function SF_Blt(T, PDst, Src, PSrc, Fl, Fx : LongInt) : LongInt;
Var DL, DT, DR, DB, SL, ST, SR, SB, Y, C : LongInt;
Begin
  RectOr(PDst, MemL[0:T + 12], MemL[0:T + 16], DL, DT, DR, DB);
  If (Fl And $400) <> 0 Then
  Begin
    { DDBLT_COLORFILL }
    C := 0;
    If Fx <> 0 Then C := MemL[0:Fx + 80] And $FF;
    If DL < 0 Then DL := 0;
    If DT < 0 Then DT := 0;
    If DR > MemL[0:T + 12] Then DR := MemL[0:T + 12];
    If DB > MemL[0:T + 16] Then DB := MemL[0:T + 16];
    For Y := DT To DB - 1 Do
      If DR > DL Then
        FillMem(MemL[0:T + 24] + Y * MemL[0:T + 20] + DL, DR - DL, C);
  End
  Else If Src <> 0 Then
  Begin
    RectOr(PSrc, MemL[0:Src + 12], MemL[0:Src + 16], SL, ST, SR, SB);
    SurfBlt(T, DL, DT, DR, DB, Src, SL, ST, SR, SB,
            ((Fl And $8000) <> 0) And (MemL[0:Src + 48] <> 0));
  End;
  SurfTouched(T);
  SF_Blt := DD_OK;
End;

Function SF_BltFast(T, X, Y, Src, PSrc, Trans : LongInt) : LongInt;
Var SL, ST, SR, SB : LongInt;
Begin
  SF_BltFast := DDERR_INVALIDPARAMS;
  If Src = 0 Then Exit;
  RectOr(PSrc, MemL[0:Src + 12], MemL[0:Src + 16], SL, ST, SR, SB);
  SurfBlt(T, X, Y, X + SR - SL, Y + SB - ST, Src, SL, ST, SR, SB,
          ((Trans And 1) <> 0) And (MemL[0:Src + 48] <> 0));
  SurfTouched(T);
  SF_BltFast := DD_OK;
End;

{ Contexte GDI sur la surface : DIB 8 bits (haut en bas) partageant la
  memoire de la surface, table de couleurs = palette systeme }
Function SF_GetDC(T, PHdc : LongInt) : LongInt;
Var B, Hdc, I : LongInt;
Begin
  SF_GetDC := DDERR_INVALIDPARAMS;
  If PHdc = 0 Then Exit;
  B := GdiNew(goBitmap);
  If B < 0 Then Exit;
  Gdis[B].I1 := MemL[0:T + 24];
  Gdis[B].I2 := MemL[0:T + 12]; Gdis[B].I3 := MemL[0:T + 16];
  Gdis[B].I4 := 8; Gdis[B].I5 := MemL[0:T + 20];
  Gdis[B].I7 := 1 Or 2 Or 8;
  Gdis[B].I6 := KAlloc(1024);
  For I := 0 To 255 Do
    MemL[0:Gdis[B].I6 + I * 4] := (SysPal[I * 3] Shl 16) Or
      (SysPal[I * 3 + 1] Shl 8) Or SysPal[I * 3 + 2];
  Hdc := CreateCompatibleDC(0);
  SelectObject(Hdc, GdiH(B));
  MemL[0:T + 52] := Hdc;
  MemL[0:T + 60] := B;
  MemL[0:PHdc] := Hdc;
  SF_GetDC := DD_OK;
End;

Function SF_ReleaseDC(T, Hdc : LongInt) : LongInt;
Var B : LongInt;
Begin
  DeleteDC(Hdc);
  B := MemL[0:T + 60];
  If (B >= 0) And (MemL[0:T + 52] = Hdc) Then
  Begin
    If Gdis[B].I6 <> 0 Then KFree(Gdis[B].I6);
    Gdis[B].I6 := 0;
    Gdis[B].Used := False;
  End;
  MemL[0:T + 52] := 0;
  SurfTouched(T);
  SF_ReleaseDC := DD_OK;
End;

{ ------------------------------------------------------------------ }
{ DirectSound (muet) : tampon +12 taille, +16 donnees, +20 lecture,  }
{ +24 en boucle, +28 debut (Ticks), +32 octets/s, +36 position de    }
{ depart, +40 WAVEFORMATEX, +60 volume, +64 balance, +68 frequence   }
{ ------------------------------------------------------------------ }

Procedure DSInitVt;
Begin
  If VtDS <> 0 Then Exit;
  VtDS := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,DS_CreateSoundBuffer,');
  VtAdd('DS_GetCaps,DS_DuplicateSoundBuffer,DXOK3,DXOK1,DS_GetSpeakerConfig,');
  VtAdd('DXOK2,DXOK2');
  VtDSB := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,DSB_GetCaps,');
  VtAdd('DSB_GetCurrentPosition,DSB_GetFormat,DSB_GetVolume,DSB_GetPan,');
  VtAdd('DSB_GetFrequency,DSB_GetStatus,DXOK3,DSB_Lock,DSB_Play,');
  VtAdd('DSB_SetCurrentPosition,DXOK2,DSB_SetVolume,DSB_SetPan,');
  VtAdd('DSB_SetFrequency,DSB_Stop,DXOK5,DXOK1');
End;

Function DXOK5(T, A, B, C, D : LongInt) : LongInt;
Begin
  DXOK5 := DD_OK;
End;

Function DirectSoundCreate(Guid, PDS, Outer : LongInt) : LongInt;
Begin
  DSInitVt;
  DirectSoundCreate := DDERR_INVALIDPARAMS;
  If PDS = 0 Then Exit;
  MemL[0:PDS] := ComNew(VtDS, 6, 32);
  KLog('DirectSound : objet cree (son muet)');
  DirectSoundCreate := DD_OK;
End;

Function DirectSoundEnumerateA(Cb, Ctx : LongInt) : LongInt;
Var S1, S2 : String;
Begin
  S1 := 'Pasdows Son' + #0;
  S2 := '' + #0;
  If W16Buf = 0 Then W16Buf := KAlloc(4096);
  MemL[0:W16Buf] := 0;
  MemL[0:W16Buf + 4] := LongInt(@S1[1]);
  MemL[0:W16Buf + 8] := LongInt(@S2[1]);
  MemL[0:W16Buf + 12] := Ctx;
  CallStd(Cb, W16Buf, 4);
  DirectSoundEnumerateA := DD_OK;
End;

Function DS_GetCaps(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    FillMem(P + 4, 92, 0);
    MemL[0:P + 4] := $F0F;
    MemL[0:P + 8] := 100; MemL[0:P + 12] := 100000;
  End;
  DS_GetCaps := DD_OK;
End;

Function DS_GetSpeakerConfig(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := 4;
  DS_GetSpeakerConfig := DD_OK;
End;

Function DS_CreateSoundBuffer(T, PDesc, PBuf, Outer : LongInt) : LongInt;
Var B, Sz, Fmt : LongInt;
Begin
  DS_CreateSoundBuffer := DDERR_INVALIDPARAMS;
  If (PDesc = 0) Or (PBuf = 0) Then Exit;
  B := ComNew(VtDSB, 7, 96);
  Sz := MemL[0:PDesc + 8];
  Fmt := MemL[0:PDesc + 16];
  If (MemL[0:PDesc + 4] And 1) <> 0 Then Sz := 16384;
  If Sz <= 0 Then Sz := 4096;
  MemL[0:B + 12] := Sz;
  MemL[0:B + 16] := KAlloc(Sz + 16);
  FillMem(MemL[0:B + 16], Sz, 0);
  MemL[0:B + 32] := 22050;
  If Fmt <> 0 Then
  Begin
    MoveMem(Fmt, B + 40, 18);
    If MemL[0:Fmt + 8] > 0 Then MemL[0:B + 32] := MemL[0:Fmt + 8];
    MemL[0:B + 68] := MemL[0:Fmt + 4];
  End;
  MemL[0:PBuf] := B;
  DS_CreateSoundBuffer := DD_OK;
End;

Function DS_DuplicateSoundBuffer(T, Src, PDst : LongInt) : LongInt;
Begin
  If (Src <> 0) And (PDst <> 0) Then
  Begin
    MemL[0:PDst] := Src;
    COMAddRef(Src);
  End;
  DS_DuplicateSoundBuffer := DD_OK;
End;

{ Position de lecture courante d'un tampon (avance en temps reel) }
Function DSBPos(B : LongInt) : LongInt;
Var P, N : LongInt;
Begin
  P := MemL[0:B + 36];
  If MemL[0:B + 20] <> 0 Then
  Begin
    N := ((Ticks - MemL[0:B + 28]) Div 10) * (MemL[0:B + 32] Div 100);
    P := P + N;
    If P >= MemL[0:B + 12] Then
    Begin
      If MemL[0:B + 24] <> 0 Then P := P Mod MemL[0:B + 12]
      Else
      Begin
        P := 0;
        MemL[0:B + 20] := 0;
        MemL[0:B + 36] := 0;
      End;
    End;
  End;
  DSBPos := P;
End;

Function DSB_GetCaps(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    MemL[0:P + 4] := 8; MemL[0:P + 8] := MemL[0:T + 12];
    MemL[0:P + 12] := 0; MemL[0:P + 16] := 0;
  End;
  DSB_GetCaps := DD_OK;
End;

Function DSB_GetCurrentPosition(T, PPlay, PWrite : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := DSBPos(T);
  If PPlay <> 0 Then MemL[0:PPlay] := P;
  If PWrite <> 0 Then MemL[0:PWrite] := (P + 512) Mod MemL[0:T + 12];
  DSB_GetCurrentPosition := DD_OK;
End;

Function DSB_GetFormat(T, P, N, PN : LongInt) : LongInt;
Begin
  If (P <> 0) And (N >= 16) Then MoveMem(T + 40, P, Min(N, 18));
  If PN <> 0 Then MemL[0:PN] := 18;
  DSB_GetFormat := DD_OK;
End;

Function DSB_GetVolume(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := MemL[0:T + 60];
  DSB_GetVolume := DD_OK;
End;

Function DSB_GetPan(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := MemL[0:T + 64];
  DSB_GetPan := DD_OK;
End;

Function DSB_GetFrequency(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then MemL[0:P] := MemL[0:T + 68];
  DSB_GetFrequency := DD_OK;
End;

Function DSB_GetStatus(T, P : LongInt) : LongInt;
Begin
  DSBPos(T);
  If P <> 0 Then
    MemL[0:P] := Ord(MemL[0:T + 20] <> 0) Or (Ord(MemL[0:T + 24] <> 0) * 4);
  DSB_GetStatus := DD_OK;
End;

Function DSB_Lock(T, Ofs, N, P1, N1, P2, N2, Fl : LongInt) : LongInt;
Var Sz, A : LongInt;
Begin
  Sz := MemL[0:T + 12];
  If (Fl And 1) <> 0 Then Ofs := (DSBPos(T) + 512) Mod Sz;
  If (Fl And 2) <> 0 Then
  Begin
    Ofs := 0; N := Sz;
  End;
  If N > Sz Then N := Sz;
  Ofs := Ofs Mod Sz;
  A := Min(N, Sz - Ofs);
  If P1 <> 0 Then MemL[0:P1] := MemL[0:T + 16] + Ofs;
  If N1 <> 0 Then MemL[0:N1] := A;
  If P2 <> 0 Then
  Begin
    If N > A Then MemL[0:P2] := MemL[0:T + 16] Else MemL[0:P2] := 0;
  End;
  If N2 <> 0 Then MemL[0:N2] := N - A;
  DSB_Lock := DD_OK;
End;

Function DSB_Play(T, R1, R2, Fl : LongInt) : LongInt;
Begin
  If MemL[0:T + 20] = 0 Then
  Begin
    MemL[0:T + 28] := Ticks;
    MemL[0:T + 20] := 1;
  End;
  MemL[0:T + 24] := Fl And 1;
  DSB_Play := DD_OK;
End;

Function DSB_Stop(T : LongInt) : LongInt;
Begin
  MemL[0:T + 36] := DSBPos(T);
  MemL[0:T + 20] := 0;
  DSB_Stop := DD_OK;
End;

Function DSB_SetCurrentPosition(T, P : LongInt) : LongInt;
Begin
  MemL[0:T + 36] := P Mod MemL[0:T + 12];
  MemL[0:T + 28] := Ticks;
  DSB_SetCurrentPosition := DD_OK;
End;

Function DSB_SetVolume(T, V : LongInt) : LongInt;
Begin
  MemL[0:T + 60] := V;
  DSB_SetVolume := DD_OK;
End;

Function DSB_SetPan(T, V : LongInt) : LongInt;
Begin
  MemL[0:T + 64] := V;
  DSB_SetPan := DD_OK;
End;

Function DSB_SetFrequency(T, V : LongInt) : LongInt;
Begin
  MemL[0:T + 68] := V;
  If V > 0 Then
    MemL[0:T + 32] := V * MemW[0:T + 40 + 12];
  DSB_SetFrequency := DD_OK;
End;

{ ------------------------------------------------------------------ }
{ DirectInput : peripherique +12 sorte (1 clavier, 2 souris)          }
{ ------------------------------------------------------------------ }

Procedure DIInitVt;
Begin
  If VtDI <> 0 Then Exit;
  VtDI := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,DI_CreateDevice,');
  VtAdd('DI_EnumDevices,DI_GetDeviceStatus,DXOK3,DXOK3');
  VtDID := VtNew;
  VtAdd('COMQIUnk,COMAddRef,COMRelease,DID_GetCapabilities,');
  VtAdd('DXOK4,DXNI3,DXOK3,DXOK1,DXOK1,DID_GetDeviceState,DID_GetDeviceData,');
  VtAdd('DXOK2,DXOK2,DXOK3,DXNI4,DXNI2,DXOK3,DXOK4');
End;

Function DirectInputCreateA(Inst, Ver, PDI, Outer : LongInt) : LongInt;
Begin
  DIInitVt;
  DirectInputCreateA := DDERR_INVALIDPARAMS;
  If PDI = 0 Then Exit;
  MemL[0:PDI] := ComNew(VtDI, 8, 32);
  KLog('DirectInput : objet cree');
  DirectInputCreateA := DD_OK;
End;

Function DI_CreateDevice(T, Guid, PDev, Outer : LongInt) : LongInt;
Var D : LongInt;
Begin
  DI_CreateDevice := DDERR_NOTFOUND;
  If (PDev = 0) Or (Guid = 0) Then Exit;
  D := ComNew(VtDID, 9, 32);
  If MemL[0:Guid] = LongInt($6F1D2B61) Then MemL[0:D + 12] := 1
  Else If MemL[0:Guid] = LongInt($6F1D2B60) Then MemL[0:D + 12] := 2
  Else Exit;
  MemL[0:PDev] := D;
  DI_CreateDevice := DD_OK;
End;

Function DI_EnumDevices(T, Typ, Cb, Ctx, Fl : LongInt) : LongInt;
Begin
  DI_EnumDevices := DD_OK;
End;

Function DI_GetDeviceStatus(T, Guid : LongInt) : LongInt;
Begin
  DI_GetDeviceStatus := DD_OK;
End;

Function DID_GetCapabilities(T, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    FillMem(P + 4, 40, 0);
    MemL[0:P + 4] := 5;
    If MemL[0:T + 12] = 1 Then
    Begin
      MemL[0:P + 8] := 3; MemL[0:P + 16] := 128;
    End
    Else
    Begin
      MemL[0:P + 8] := 2; MemL[0:P + 12] := 2; MemL[0:P + 16] := 3;
    End;
  End;
  DID_GetCapabilities := DD_OK;
End;

Function DID_GetDeviceState(T, N, P : LongInt) : LongInt;
Var I : LongInt;
Begin
  If MemL[0:T + 12] = 1 Then
  Begin
    For I := 0 To Min(N, 256) - 1 Do
    Begin
      Mem[0:P + I] := ScanDown[I] Or ScanHit[I];
      ScanHit[I] := 0;
    End;
  End
  Else If N >= 16 Then
  Begin
    MemL[0:P] := DIMX; MemL[0:P + 4] := DIMY; MemL[0:P + 8] := 0;
    DIMX := 0; DIMY := 0;
    Mem[0:P + 12] := Ord((DIMBtn And 1) <> 0) * $80;
    Mem[0:P + 13] := Ord((DIMBtn And 2) <> 0) * $80;
    Mem[0:P + 14] := 0; Mem[0:P + 15] := 0;
  End;
  DID_GetDeviceState := DD_OK;
End;

Function DID_GetDeviceData(T, Sz, P, PN, Fl : LongInt) : LongInt;
Begin
  If PN <> 0 Then MemL[0:PN] := 0;
  DID_GetDeviceData := DD_OK;
End;

{ ------------------------------------------------------------------ }
{ DSETUP.DLL : DirectX 3 est deja present dans Pasdows               }
{ ------------------------------------------------------------------ }

Function DirectXSetup(H, Root, Fl : LongInt) : LongInt;
Begin
  KLog('DirectXSetup : DirectX integre a Pasdows, rien a installer');
  DirectXSetup := 0;
End;

Function DirectXSetupA(H, Root, Fl : LongInt) : LongInt;
Begin
  DirectXSetupA := 0;
End;

Function DirectXDeviceDriverSetup(H, Drv, Dir, Fl : LongInt) : LongInt;
Begin
  DirectXDeviceDriverSetup := 0;
End;

Function DirectXSetupGetVersion(PVer, PRev : LongInt) : LongInt;
Begin
  If PVer <> 0 Then MemL[0:PVer] := $00040004;
  If PRev <> 0 Then MemL[0:PRev] := $00000044;
  DirectXSetupGetVersion := 1;
End;

Function DirectXSetupSetCallback(Cb : LongInt) : LongInt;
Begin
  DirectXSetupSetCallback := 0;
End;

Function DirectXRegisterApplication(H, P : LongInt) : LongInt;
Begin
  DirectXRegisterApplication := 1;
End;

Function DirectXUnRegisterApplication(H, P : LongInt) : LongInt;
Begin
  DirectXUnRegisterApplication := 1;
End;

{ ==================================================================== }
{ Partie 16 - Reseau : pilote NE2000 et pile TCP/IP (ARP, IP, ICMP,    }
{             UDP, TCP), client DHCP et resolveur DNS                  }
{ ==================================================================== }

{ Comme Windows 95 avec sa carte ? NE2000 compatible ?, VMM32 pilote une
  carte DP8390 : RTL8029 PCI (10EC:8029) ou carte ISA en 300h. Les
  trames sont lues par scrutation (NetPoll), depuis la boucle du systeme
  et pendant les appels bloquants de Winsock. Les adresses IP sont
  gardees dans l'ordre du reseau (telles qu'en memoire, MemL), les ports
  et numeros de sequence dans l'ordre de l'hote. }

Const
  MaxSock = 32;
  MaxArp = 16;
  MaxLoop = 8;
  SkRxSize = 32768;
  SkTxSize = 16384;
  SockBase = $80;                    { premier descripteur de socket }
  NetMss = 1460;
  NeTxPage = $40; NeRxStart = $46; NeRxStop = $80;
  tcClosed = 0; tcListen = 1; tcSynSent = 2; tcSynRcvd = 3; tcEstab = 4;
  tcFinWait1 = 5; tcFinWait2 = 6; tcCloseWait = 7; tcClosing = 8;
  tcLastAck = 9; tcTimeWait = 10;
  { SkFlags }
  sfNonBlock = 1; sfFinRcvd = 2; sfFinWant = 4; sfFinSent = 8;
  sfAppClosed = 16; sfBound = 32; sfUdpConn = 64; sfAccepted = 128;
  { evenements WSAAsyncSelect }
  FD_READ = 1; FD_WRITE = 2; FD_OOB = 4; FD_ACCEPT = 8; FD_CONNECT = 16;
  FD_CLOSE = 32;
  { TCP }
  thFin = 1; thSyn = 2; thRst = 4; thPsh = 8; thAck = 16;

Var
  NicBase   : LongInt;                { port de la carte (0 : aucune) }
  NicPci    : Boolean;
  NicMac    : Array[0..5] Of Byte;
  NetIP, NetMask, NetGw, NetDns, NetDhcpSrv, NetLease : LongInt;
  DhcpState, DhcpNext, DhcpXid, DhcpTries, DhcpOffer : LongInt;
  NetRx, NetTx, NetAux, NetHdr, NetLoop, NetLoopRx : LongInt;
  LoopHead, LoopN : LongInt;
  NetIpId, NetPortNext, NetLastTick, NetIss : LongInt;
  NetPktIn, NetPktOut : LongInt;
  NetPolling : Boolean;
  NetRxTtl : LongInt;
  ArpIP     : Array[0..MaxArp - 1] Of LongInt;
  ArpMac    : Array[0..MaxArp * 6 - 1] Of Byte;
  ArpNext   : LongInt;
  PingId, PingSeq, PingGotAt, PingTtl, PingFrom, PingData : LongInt;
  PingLen, PingReq : LongInt;
  WsBuf     : LongInt;    { structures statiques de Winsock }
  DnsId, DnsPort, DnsResult : LongInt;
  DnsBusy   : Boolean;
  { sockets (tableaux plats) }
  SkUsed    : Array[0..MaxSock - 1] Of Boolean;
  SkType, SkLPort, SkRIP, SkRPort, SkState, SkErr : Array[0..MaxSock - 1]
    Of LongInt;
  SkRx, SkRxHead, SkRxLen, SkTx, SkTxLen : Array[0..MaxSock - 1] Of LongInt;
  SkSndUna, SkSndNxt, SkRcvNxt, SkSndWnd : Array[0..MaxSock - 1] Of LongInt;
  SkRetx, SkRto, SkTries, SkParent, SkBacklog : Array[0..MaxSock - 1]
    Of LongInt;
  SkFlags, SkAWnd, SkAMsg, SkAEv, SkASent, SkTimer : Array[0..MaxSock - 1]
    Of LongInt;
  SkLastWnd : Array[0..MaxSock - 1] Of LongInt;

{ ------------------------------------------------------------------ }
{ Outils : ordre des octets, adresses, somme de controle              }
{ ------------------------------------------------------------------ }

Function NGetW(A : LongInt) : LongInt;
Begin
  NGetW := (Mem[0:A] Shl 8) Or Mem[0:A + 1];
End;

Procedure NPutW(A, V : LongInt);
Begin
  Mem[0:A] := (V Shr 8) And $FF;
  Mem[0:A + 1] := V And $FF;
End;

Function NGetL(A : LongInt) : LongInt;
Begin
  NGetL := (Mem[0:A] Shl 24) Or (Mem[0:A + 1] Shl 16) Or
           (Mem[0:A + 2] Shl 8) Or Mem[0:A + 3];
End;

Procedure NPutL(A, V : LongInt);
Begin
  Mem[0:A] := (V Shr 24) And $FF;
  Mem[0:A + 1] := (V Shr 16) And $FF;
  Mem[0:A + 2] := (V Shr 8) And $FF;
  Mem[0:A + 3] := V And $FF;
End;

Function Swap16(V : LongInt) : LongInt;
Begin
  Swap16 := ((V And $FF) Shl 8) Or ((V Shr 8) And $FF);
End;

Function Swap32(V : LongInt) : LongInt;
Begin
  Swap32 := ((V And $FF) Shl 24) Or (((V Shr 8) And $FF) Shl 16) Or
            (((V Shr 16) And $FF) Shl 8) Or ((V Shr 24) And $FF);
End;

{ Adresse IP (ordre du reseau) en notation pointee }
Function IpStr(IP : LongInt) : String;
Begin
  IpStr := IntStr(IP And $FF) + '.' + IntStr((IP Shr 8) And $FF) + '.' +
           IntStr((IP Shr 16) And $FF) + '.' + IntStr((IP Shr 24) And $FF);
End;

{ Notation pointee -> adresse (ordre du reseau) ; False si invalide }
Function ParseIp(S : String; Var IP : LongInt) : Boolean;
Var I, N, V, R, Digits : LongInt; C : Char;
Begin
  ParseIp := False;
  R := 0; N := 0; V := 0; Digits := 0;
  For I := 1 To Length(S) + 1 Do
  Begin
    If I > Length(S) Then C := '.' Else C := S[I];
    If (C >= '0') And (C <= '9') Then
    Begin
      V := V * 10 + Ord(C) - 48;
      Inc(Digits);
      If (V > 255) Or (Digits > 3) Then Exit;
    End
    Else If C = '.' Then
    Begin
      If (Digits = 0) Or (N > 3) Then Exit;
      R := R Or (V Shl (N * 8));
      Inc(N); V := 0; Digits := 0;
    End
    Else Exit;
  End;
  If N <> 4 Then Exit;
  IP := R;
  ParseIp := True;
End;

Function MacStr : String;
Var I : LongInt; S : String;
Begin
  S := '';
  For I := 0 To 5 Do
  Begin
    If I > 0 Then S := S + '-';
    S := S + HexStr(NicMac[I], 2);
  End;
  MacStr := S;
End;

{ Somme de controle de l'Internet (complement a un) }
Function NetSum(A, N, Init : LongInt) : LongInt;
Var S, I : LongInt;
Begin
  S := Init; I := 0;
  While I + 1 < N Do
  Begin
    S := S + (Mem[0:A + I] Shl 8) + Mem[0:A + I + 1];
    I := I + 2;
  End;
  If I < N Then S := S + (Mem[0:A + I] Shl 8);
  While (S Shr 16) <> 0 Do S := (S And $FFFF) + (S Shr 16);
  NetSum := S;
End;

{ Pseudo-en-tete TCP/UDP }
Function PseudoSum(Src, Dst, Proto, Len : LongInt) : LongInt;
Begin
  PseudoSum := ((Src And $FF) Shl 8) + ((Src Shr 8) And $FF) +
               (((Src Shr 16) And $FF) Shl 8) + ((Src Shr 24) And $FF) +
               ((Dst And $FF) Shl 8) + ((Dst Shr 8) And $FF) +
               (((Dst Shr 16) And $FF) Shl 8) + ((Dst Shr 24) And $FF) +
               Proto + Len;
End;

{ ------------------------------------------------------------------ }
{ Bus PCI (mecanisme de configuration 1)                               }
{ ------------------------------------------------------------------ }

Function PciRead(Bus, Dev, Fn, Reg : LongInt) : LongInt;
Var A, R : LongInt;
Begin
  A := LongInt($80000000) Or (Bus Shl 16) Or (Dev Shl 11) Or (Fn Shl 8) Or
       (Reg And $FC);
  asm
    mov eax,A
    mov edx,0CF8h
    out dx,eax
    mov edx,0CFCh
    in eax,dx
    mov R,eax
  end;
  PciRead := R;
End;

Procedure PciWrite(Bus, Dev, Fn, Reg, V : LongInt);
Var A : LongInt;
Begin
  A := LongInt($80000000) Or (Bus Shl 16) Or (Dev Shl 11) Or (Fn Shl 8) Or
       (Reg And $FC);
  asm
    mov eax,A
    mov edx,0CF8h
    out dx,eax
    mov eax,V
    mov edx,0CFCh
    out dx,eax
  end;
End;

{ ------------------------------------------------------------------ }
{ Pilote NE2000 (DP8390, transferts en mots de 16 bits)                }
{ ------------------------------------------------------------------ }

Procedure NeDma(Addr, Count, Cmd : LongInt);
Begin
  Port[NicBase + $0A] := Count And $FF;
  Port[NicBase + $0B] := (Count Shr 8) And $FF;
  Port[NicBase + $08] := Addr And $FF;
  Port[NicBase + $09] := (Addr Shr 8) And $FF;
  Port[NicBase] := Cmd;
End;

Procedure NeWaitDma;
Var I : LongInt;
Begin
  I := 0;
  While ((Port[NicBase + 7] And $40) = 0) And (I < 100000) Do Inc(I);
  Port[NicBase + 7] := $40;
End;

{ Lire Count octets de la memoire de la carte (arrondi au mot) }
Procedure NeRead(Addr, Dst, Count : LongInt);
Var P, N : LongInt;
Begin
  N := (Count + 1) And Not 1;
  NeDma(Addr, N, $0A);
  P := NicBase + $10;
  N := N Shr 1;
  asm
    push edi
    mov edi,Dst
    mov ecx,N
    mov edx,P
    cld
    rep insw
    pop edi
  end;
  NeWaitDma;
End;

Procedure NeWrite(Addr, Src, Count : LongInt);
Var P, N : LongInt;
Begin
  N := (Count + 1) And Not 1;
  Port[NicBase + 7] := $40;
  NeDma(Addr, N, $12);
  P := NicBase + $10;
  N := N Shr 1;
  asm
    push esi
    mov esi,Src
    mov ecx,N
    mov edx,P
    cld
    rep outsw
    pop esi
  end;
  NeWaitDma;
End;

Function NeReset(B : LongInt) : Boolean;
Var I, V : LongInt;
Begin
  NeReset := False;
  V := Port[B + $1F];
  Port[B + $1F] := V;
  I := 0;
  While ((Port[B + 7] And $80) = 0) And (I < 200000) Do Inc(I);
  If (Port[B + 7] And $80) = 0 Then Exit;
  Port[B + 7] := $FF;
  NeReset := True;
End;

Procedure NeInit;
Var B, I : LongInt;
Begin
  B := NicBase;
  Port[B] := $21;                  { page 0, arret, pas de DMA }
  Port[B + $0E] := $49;            { DCR : mots, FIFO 8 octets }
  Port[B + $0A] := 0; Port[B + $0B] := 0;
  Port[B + $0F] := 0;              { IMR : scrutation }
  Port[B + 7] := $FF;
  Port[B + $0C] := $20;            { RCR : moniteur }
  Port[B + $0D] := $02;            { TCR : boucle interne }
  { adresse Ethernet : PROM (octets doubles en mode mot) }
  FillMem(NetHdr, 64, 0);
  NeRead(0, NetHdr, 32);
  For I := 0 To 5 Do NicMac[I] := Mem[0:NetHdr + I * 2];
  Port[B] := $21;
  Port[B + $01] := NeRxStart;
  Port[B + $02] := NeRxStop;
  Port[B + $03] := NeRxStart;
  Port[B + $04] := NeTxPage;
  Port[B + 7] := $FF;
  Port[B] := $61;                  { page 1 }
  For I := 0 To 5 Do Port[B + 1 + I] := NicMac[I];
  For I := 0 To 7 Do Port[B + 8 + I] := $FF;
  Port[B + 7] := NeRxStart + 1;    { CURR }
  Port[B] := $22;                  { page 0, demarrage }
  Port[B + 7] := $FF;
  Port[B + $0D] := 0;              { TCR normal }
  Port[B + $0C] := $04;            { RCR : diffusion acceptee }
End;

Function NeProbe : Boolean;
Var Bus, Dev, Id, Bar, Cmd : LongInt;
Begin
  NeProbe := False;
  NicBase := 0;
  For Bus := 0 To 3 Do
    For Dev := 0 To 31 Do
      If NicBase = 0 Then
      Begin
        Id := PciRead(Bus, Dev, 0, 0);
        If Id = $802910EC Then
        Begin
          Bar := PciRead(Bus, Dev, 0, $10);
          If (Bar And 1) <> 0 Then
          Begin
            Cmd := PciRead(Bus, Dev, 0, 4);
            PciWrite(Bus, Dev, 0, 4, (Cmd And $FFFF) Or 5);
            NicBase := Bar And $FFFC;
            NicPci := True;
          End;
        End;
      End;
  If NicBase = 0 Then
  Begin
    { carte ISA a l'adresse habituelle }
    If (Port[$300] <> $FF) And NeReset($300) Then
    Begin
      NicBase := $300;
      NicPci := False;
    End;
  End
  Else If Not NeReset(NicBase) Then NicBase := 0;
  If NicBase = 0 Then Exit;
  NeInit;
  NeProbe := True;
End;

Procedure NeSend(Src, Len : LongInt);
Var I : LongInt;
Begin
  If NicBase = 0 Then Exit;
  If Len < 60 Then
  Begin
    FillMem(Src + Len, 60 - Len, 0);
    Len := 60;
  End;
  I := 0;
  While ((Port[NicBase] And 4) <> 0) And (I < 200000) Do Inc(I);
  NeWrite(NeTxPage * 256, Src, Len);
  Port[NicBase + 4] := NeTxPage;
  Port[NicBase + 5] := Len And $FF;
  Port[NicBase + 6] := (Len Shr 8) And $FF;
  Port[NicBase] := $26;
  Inc(NetPktOut);
End;

{ Trame recue dans Dst : longueur, ou 0 si aucune }
Function NeRecv(Dst : LongInt) : LongInt;
Var B, Curr, Bnry, Nxt, NextPg, Len : LongInt;
Begin
  NeRecv := 0;
  B := NicBase;
  Port[B] := $62;
  Curr := Port[B + 7];
  Port[B] := $22;
  Bnry := Port[B + 3];
  Nxt := Bnry + 1;
  If Nxt >= NeRxStop Then Nxt := NeRxStart;
  If Nxt = Curr Then
  Begin
    If (Port[B + 7] And $10) <> 0 Then Port[B + 7] := $10;
    Exit;
  End;
  NeRead(Nxt * 256, NetHdr, 4);
  NextPg := Mem[0:NetHdr + 1];
  Len := MemW[0:NetHdr + 2] - 4;
  If (NextPg < NeRxStart) Or (NextPg >= NeRxStop) Or (Len > 2000) Then
  Begin
    { anneau incoherent : tout abandonner }
    If Curr - 1 < NeRxStart Then Port[B + 3] := NeRxStop - 1
    Else Port[B + 3] := Curr - 1;
    Port[B + 7] := $FF;
    Exit;
  End;
  If (Len > 0) And (Len <= 1536) Then NeRead(Nxt * 256 + 4, Dst, Len)
  Else Len := 0;
  If NextPg - 1 < NeRxStart Then Port[B + 3] := NeRxStop - 1
  Else Port[B + 3] := NextPg - 1;
  Port[B + 7] := $15;
  Inc(NetPktIn);
  If Len = 0 Then Len := -1;
  NeRecv := Len;
End;

{ ------------------------------------------------------------------ }
{ Ethernet et ARP                                                      }
{ ------------------------------------------------------------------ }

Function ArpFind(IP : LongInt) : LongInt;
Var I, R : LongInt;
Begin
  R := -1;
  For I := 0 To MaxArp - 1 Do
    If (ArpIP[I] = IP) And (IP <> 0) Then R := I;
  ArpFind := R;
End;

Procedure ArpAdd(IP, Mac : LongInt);
Var I, K : LongInt;
Begin
  If (IP = 0) Or (IP = -1) Then Exit;
  I := ArpFind(IP);
  If I < 0 Then
  Begin
    I := ArpNext;
    ArpNext := (ArpNext + 1) Mod MaxArp;
  End;
  ArpIP[I] := IP;
  For K := 0 To 5 Do ArpMac[I * 6 + K] := Mem[0:Mac + K];
End;

{ En-tete Ethernet en F (destination Mac, 0 : diffusion) }
Procedure EthHeader(F, Mac, EType : LongInt);
Var K : LongInt;
Begin
  For K := 0 To 5 Do
  Begin
    If Mac = 0 Then Mem[0:F + K] := $FF Else Mem[0:F + K] := Mem[0:Mac + K];
    Mem[0:F + 6 + K] := NicMac[K];
  End;
  NPutW(F + 12, EType);
End;

Procedure ArpSend(Op, TMac, TIP : LongInt);
Var F, K : LongInt;
Begin
  F := NetAux;
  EthHeader(F, TMac, $0806);
  NPutW(F + 14, 1); NPutW(F + 16, $0800);
  Mem[0:F + 18] := 6; Mem[0:F + 19] := 4;
  NPutW(F + 20, Op);
  For K := 0 To 5 Do
  Begin
    Mem[0:F + 22 + K] := NicMac[K];
    If TMac = 0 Then Mem[0:F + 32 + K] := 0
    Else Mem[0:F + 32 + K] := Mem[0:TMac + K];
  End;
  MemL[0:F + 28] := NetIP;
  MemL[0:F + 38] := TIP;
  NeSend(F, 42);
End;

Procedure ArpInput(P, Len : LongInt);
Var SIP, TIP : LongInt;
Begin
  If Len < 28 Then Exit;
  If (NGetW(P) <> 1) Or (NGetW(P + 2) <> $0800) Then Exit;
  SIP := MemL[0:P + 14];
  TIP := MemL[0:P + 24];
  If (NetIP <> 0) And (TIP = NetIP) Then
  Begin
    ArpAdd(SIP, P + 8);
    If NGetW(P + 6) = 1 Then
    Begin
      MoveMem(P + 8, NetHdr + 16, 6);
      ArpSend(2, NetHdr + 16, SIP);
    End;
  End
  Else If ArpFind(SIP) >= 0 Then ArpAdd(SIP, P + 8);
End;

Function IsLoop(IP : LongInt) : Boolean;
Begin
  IsLoop := ((IP And $FF) = 127) Or ((IP = NetIP) And (IP <> 0));
End;

{ Prochain saut vers IP (-1 : diffusion) }
Function NextHop(IP : LongInt) : LongInt;
Begin
  If (IP = -1) Or (NetIP = 0) Then NextHop := -1
  Else If ((IP Xor NetIP) And NetMask) <> 0 Then NextHop := NetGw
  Else If (IP Or NetMask) = -1 Then NextHop := -1
  Else NextHop := IP;
End;

{ ------------------------------------------------------------------ }
{ IP                                                                   }
{ ------------------------------------------------------------------ }

{ Emettre le datagramme dont la charge (Len octets) est en NetTx + 34 }
Function IpSend(Dst, Proto, Len : LongInt) : Boolean;
Var H, Hop, I, A : LongInt;
Begin
  IpSend := False;
  H := NetTx + 14;
  Mem[0:H] := $45; Mem[0:H + 1] := 0;
  NPutW(H + 2, 20 + Len);
  NPutW(H + 4, NetIpId);
  NetIpId := (NetIpId + 1) And $FFFF;
  NPutW(H + 6, 0);
  Mem[0:H + 8] := 128; Mem[0:H + 9] := Proto;
  NPutW(H + 10, 0);
  If IsLoop(Dst) Then MemL[0:H + 12] := Dst Else MemL[0:H + 12] := NetIP;
  MemL[0:H + 16] := Dst;
  NPutW(H + 10, (Not NetSum(H, 20, 0)) And $FFFF);
  If IsLoop(Dst) Then
  Begin
    { boucle locale : file traitee par NetPoll }
    If LoopN >= MaxLoop Then Exit;
    A := NetLoop + ((LoopHead + LoopN) Mod MaxLoop) * 1600;
    MemL[0:A] := 20 + Len;
    MoveMem(H, A + 4, 20 + Len);
    Inc(LoopN);
    IpSend := True;
    Exit;
  End;
  If NicBase = 0 Then Exit;
  Hop := NextHop(Dst);
  If Hop = -1 Then EthHeader(NetTx, 0, $0800)
  Else
  Begin
    I := ArpFind(Hop);
    If I < 0 Then
    Begin
      ArpSend(1, 0, Hop);
      Exit;
    End;
    EthHeader(NetTx, LongInt(@ArpMac) + I * 6, $0800);
  End;
  NeSend(NetTx, 34 + Len);
  IpSend := True;
End;

Procedure IcmpInput(Src, P, Len : LongInt); Forward;
Procedure UdpInput(Src, Dst, P, Len : LongInt); Forward;
Procedure TcpInput(Src, P, Len : LongInt); Forward;

Procedure IpInput(P, Len : LongInt);
Var HL, TL, Src, Dst : LongInt;
Begin
  If Len < 20 Then Exit;
  If (Mem[0:P] Shr 4) <> 4 Then Exit;
  HL := (Mem[0:P] And 15) * 4;
  TL := NGetW(P + 2);
  If (TL > Len) Or (TL < HL) Then Exit;
  If (NGetW(P + 6) And $3FFF) <> 0 Then Exit;   { fragments ignores }
  Src := MemL[0:P + 12];
  Dst := MemL[0:P + 16];
  If NetIP = 0 Then
  Begin
    { en attente de DHCP : seulement UDP }
    If (Mem[0:P + 9] <> 17) And Not IsLoop(Dst) Then Exit;
  End
  Else If (Dst <> NetIP) And (Dst <> -1) And Not IsLoop(Dst) And
          ((Dst Or NetMask) <> -1) Then Exit;
  NetRxTtl := Mem[0:P + 8];
  Case Mem[0:P + 9] Of
    1 : IcmpInput(Src, P + HL, TL - HL);
    6 : TcpInput(Src, P + HL, TL - HL);
    17 : UdpInput(Src, Dst, P + HL, TL - HL);
  End;
End;

Procedure EthInput(F, Len : LongInt);
Var T : LongInt;
Begin
  If Len < 14 Then Exit;
  T := NGetW(F + 12);
  If T = $0806 Then ArpInput(F + 14, Len - 14)
  Else If T = $0800 Then IpInput(F + 14, Len - 14);
End;

{ ------------------------------------------------------------------ }
{ ICMP : echo (ping)                                                   }
{ ------------------------------------------------------------------ }

Procedure IcmpInput(Src, P, Len : LongInt);
Var T : LongInt;
Begin
  If Len < 8 Then Exit;
  T := Mem[0:P];
  If (T = 8) And (Len <= 1472) Then
  Begin
    MoveMem(P, NetTx + 34, Len);
    Mem[0:NetTx + 34] := 0;
    NPutW(NetTx + 36, 0);
    NPutW(NetTx + 36, (Not NetSum(NetTx + 34, Len, 0)) And $FFFF);
    IpSend(Src, 1, Len);
  End
  Else If (T = 0) And (NGetW(P + 4) = PingId) And
          (NGetW(P + 6) = PingSeq) Then
  Begin
    PingGotAt := Ticks;
    PingTtl := NetRxTtl;
    PingFrom := Src;
    PingLen := Min(Len - 8, 1024);
    If PingData <> 0 Then MoveMem(P + 8, PingData, PingLen);
  End;
End;

{ ------------------------------------------------------------------ }
{ UDP                                                                  }
{ ------------------------------------------------------------------ }

{ Emettre un datagramme dont les donnees sont en NetTx + 42 }
Function UdpOut(SPort, Dst, DPort, Len : LongInt) : Boolean;
Var U, S, Src : LongInt;
Begin
  U := NetTx + 34;
  NPutW(U, SPort); NPutW(U + 2, DPort);
  NPutW(U + 4, Len + 8); NPutW(U + 6, 0);
  If IsLoop(Dst) Then Src := Dst Else Src := NetIP;
  S := NetSum(U, Len + 8, PseudoSum(Src, Dst, 17, Len + 8));
  S := (Not S) And $FFFF;
  If S = 0 Then S := $FFFF;
  NPutW(U + 6, S);
  UdpOut := IpSend(Dst, 17, Len + 8);
End;

Procedure DhcpInput(P, Len : LongInt); Forward;
Procedure DnsInput(P, Len : LongInt); Forward;
Procedure NetNotify(S, Ev : LongInt); Forward;

{ Anneau de reception d'un socket }
Procedure RingPut(S, Src, N : LongInt);
Var Pos0, K : LongInt;
Begin
  Pos0 := (SkRxHead[S] + SkRxLen[S]) Mod SkRxSize;
  K := Min(N, SkRxSize - Pos0);
  MoveMem(Src, SkRx[S] + Pos0, K);
  If N > K Then MoveMem(Src + K, SkRx[S], N - K);
  SkRxLen[S] := SkRxLen[S] + N;
End;

Procedure RingGet(S, Dst, N : LongInt; Peek : Boolean);
Var K : LongInt;
Begin
  K := Min(N, SkRxSize - SkRxHead[S]);
  If Dst <> 0 Then
  Begin
    MoveMem(SkRx[S] + SkRxHead[S], Dst, K);
    If N > K Then MoveMem(SkRx[S], Dst + K, N - K);
  End;
  If Not Peek Then
  Begin
    SkRxHead[S] := (SkRxHead[S] + N) Mod SkRxSize;
    SkRxLen[S] := SkRxLen[S] - N;
  End;
End;

Procedure UdpInput(Src, Dst, P, Len : LongInt);
Var SP, DP, UL, D, S, I : LongInt;
Begin
  If Len < 8 Then Exit;
  SP := NGetW(P); DP := NGetW(P + 2); UL := NGetW(P + 4);
  If (UL < 8) Or (UL > Len) Then Exit;
  D := P + 8; UL := UL - 8;
  If (DP = 68) And (DhcpState In [1, 2]) Then
  Begin
    DhcpInput(D, UL);
    Exit;
  End;
  If DnsBusy And (DP = DnsPort) And (SP = 53) Then
  Begin
    DnsInput(D, UL);
    Exit;
  End;
  S := -1;
  For I := 0 To MaxSock - 1 Do
    If SkUsed[I] And (SkType[I] = 2) And (SkLPort[I] = DP) Then
      If ((SkFlags[I] And sfUdpConn) = 0) Or
         ((SkRIP[I] = Src) And (SkRPort[I] = SP)) Then S := I;
  If S < 0 Then Exit;
  If SkRxLen[S] + UL + 8 > SkRxSize Then Exit;
  MemL[0:NetHdr] := UL;
  MemL[0:NetHdr + 4] := Src;
  MemL[0:NetHdr + 8] := SP;
  RingPut(S, NetHdr, 12);
  RingPut(S, D, UL);
  NetNotify(S, FD_READ);
End;

{ ------------------------------------------------------------------ }
{ DHCP (client)                                                        }
{ ------------------------------------------------------------------ }

Procedure DhcpSend(Typ : LongInt);
Var D, O, K : LongInt; Hn : String;
Begin
  D := NetTx + 42;
  FillMem(D, 300, 0);
  Mem[0:D] := 1; Mem[0:D + 1] := 1; Mem[0:D + 2] := 6;
  NPutL(D + 4, DhcpXid);
  NPutW(D + 10, $8000);
  For K := 0 To 5 Do Mem[0:D + 28 + K] := NicMac[K];
  NPutL(D + 236, $63825363);
  O := D + 240;
  Mem[0:O] := 53; Mem[0:O + 1] := 1; Mem[0:O + 2] := Typ; O := O + 3;
  Mem[0:O] := 61; Mem[0:O + 1] := 7; Mem[0:O + 2] := 1;
  For K := 0 To 5 Do Mem[0:O + 3 + K] := NicMac[K];
  O := O + 9;
  Mem[0:O] := 12; Mem[0:O + 1] := 7;
  Hn := 'PASDOWS';
  For K := 1 To 7 Do Mem[0:O + 1 + K] := Ord(Hn[K]);
  O := O + 9;
  If Typ = 3 Then
  Begin
    Mem[0:O] := 50; Mem[0:O + 1] := 4; MemL[0:O + 2] := DhcpOffer;
    O := O + 6;
    Mem[0:O] := 54; Mem[0:O + 1] := 4; MemL[0:O + 2] := NetDhcpSrv;
    O := O + 6;
  End;
  Mem[0:O] := 55; Mem[0:O + 1] := 4; Mem[0:O + 2] := 1; Mem[0:O + 3] := 3;
  Mem[0:O + 4] := 6; Mem[0:O + 5] := 15;
  O := O + 6;
  Mem[0:O] := 255;
  UdpOut(68, -1, 67, 300);
End;

Procedure DhcpInput(P, Len : LongInt);
Var O, E, Typ, C, N, Mask, Gw, Dns, Srv, Lease : LongInt;
Begin
  If (Len < 244) Or (Mem[0:P] <> 2) Then Exit;
  If NGetL(P + 4) <> DhcpXid Then Exit;
  If NGetL(P + 236) <> $63825363 Then Exit;
  Typ := 0; Mask := 0; Gw := 0; Dns := 0; Srv := 0; Lease := 0;
  O := P + 240; E := P + Len;
  While O < E Do
  Begin
    C := Mem[0:O];
    If C = 255 Then Break;
    If C = 0 Then
    Begin
      Inc(O);
      Continue;
    End;
    N := Mem[0:O + 1];
    Case C Of
      53 : Typ := Mem[0:O + 2];
      1 : Mask := MemL[0:O + 2];
      3 : Gw := MemL[0:O + 2];
      6 : Dns := MemL[0:O + 2];
      51 : Lease := NGetL(O + 2);
      54 : Srv := MemL[0:O + 2];
    End;
    O := O + 2 + N;
  End;
  If (Typ = 2) And (DhcpState = 1) Then
  Begin
    DhcpOffer := MemL[0:P + 16];
    NetDhcpSrv := Srv;
    DhcpState := 2;
    DhcpNext := Ticks + 3000;
    DhcpSend(3);
  End
  Else If (Typ = 5) And (DhcpState = 2) Then
  Begin
    NetIP := MemL[0:P + 16];
    If Mask <> 0 Then NetMask := Mask Else NetMask := $00FFFFFF;
    NetGw := Gw; NetDns := Dns; NetLease := Lease;
    DhcpState := 3;
    KLog('TCP/IP : adresse ' + IpStr(NetIP) + ' masque ' + IpStr(NetMask) +
         ' passerelle ' + IpStr(NetGw) + ' DNS ' + IpStr(NetDns) +
         ' (DHCP ' + IpStr(NetDhcpSrv) + ')');
  End
  Else If Typ = 6 Then
  Begin
    DhcpState := 1;
    DhcpNext := Ticks + 1000;
  End;
End;

Procedure DhcpTick;
Begin
  If (NicBase = 0) Or Not (DhcpState In [1, 2]) Then Exit;
  If Ticks < DhcpNext Then Exit;
  Inc(DhcpTries);
  DhcpState := 1;
  DhcpXid := DhcpXid + 1;
  DhcpSend(1);
  DhcpNext := Ticks + Min(2000 * DhcpTries, 30000);
End;

{ ------------------------------------------------------------------ }
{ TCP                                                                  }
{ ------------------------------------------------------------------ }

Function SkWnd(S : LongInt) : LongInt;
Begin
  SkWnd := Min(SkRxSize - SkRxLen[S], 65535);
End;

{ Segment TCP : Len octets de donnees depuis Data (adresse lineaire) }
Function TcpRaw(Dst, SP, DP, Seq, Ack, Fl, Wnd, Data, Len : LongInt)
  : Boolean;
Var T, HL, S, Src : LongInt;
Begin
  T := NetTx + 34;
  HL := 20;
  If (Fl And thSyn) <> 0 Then HL := 24;
  NPutW(T, SP); NPutW(T + 2, DP);
  NPutL(T + 4, Seq); NPutL(T + 8, Ack);
  Mem[0:T + 12] := (HL Div 4) Shl 4;
  Mem[0:T + 13] := Fl;
  NPutW(T + 14, Wnd);
  NPutW(T + 16, 0); NPutW(T + 18, 0);
  If HL = 24 Then
  Begin
    Mem[0:T + 20] := 2; Mem[0:T + 21] := 4; NPutW(T + 22, NetMss);
  End;
  If Len > 0 Then MoveMem(Data, T + HL, Len);
  If IsLoop(Dst) Then Src := Dst Else Src := NetIP;
  S := NetSum(T, HL + Len, PseudoSum(Src, Dst, 6, HL + Len));
  NPutW(T + 16, (Not S) And $FFFF);
  TcpRaw := IpSend(Dst, 6, HL + Len);
End;

Procedure TcpSend(S, Fl, Seq, Off, Len : LongInt);
Begin
  If (Fl And thAck) <> 0 Then SkLastWnd[S] := SkWnd(S);
  TcpRaw(SkRIP[S], SkLPort[S], SkRPort[S], Seq, SkRcvNxt[S], Fl, SkWnd(S),
         SkTx[S] + Off, Len);
End;

Procedure TcpArm(S : LongInt);
Begin
  If SkRetx[S] = 0 Then SkRetx[S] := Ticks + SkRto[S];
End;

{ Emettre les donnees en attente et le FIN demande }
Procedure TcpOutput(S : LongInt);
Var Off, Avail, N, K, St : LongInt;
Begin
  St := SkState[S];
  If Not (St In [tcEstab, tcCloseWait, tcFinWait1, tcClosing, tcLastAck])
  Then Exit;
  If (SkFlags[S] And sfFinSent) = 0 Then
  Begin
    Off := SkSndNxt[S] - SkSndUna[S];
    Avail := Min(SkTxLen[S], SkSndWnd[S]) - Off;
    K := 0;
    While (Avail > 0) And (K < 8) Do
    Begin
      N := Min(Avail, NetMss);
      TcpSend(S, thAck Or thPsh, SkSndNxt[S], Off, N);
      SkSndNxt[S] := SkSndNxt[S] + N;
      Off := Off + N; Avail := Avail - N;
      TcpArm(S);
      Inc(K);
    End;
    If ((SkFlags[S] And sfFinWant) <> 0) And (Off = SkTxLen[S]) Then
    Begin
      TcpSend(S, thFin Or thAck, SkSndNxt[S], 0, 0);
      SkSndNxt[S] := SkSndNxt[S] + 1;
      SkFlags[S] := SkFlags[S] Or sfFinSent;
      If St = tcEstab Then SkState[S] := tcFinWait1
      Else If St = tcCloseWait Then SkState[S] := tcLastAck;
      TcpArm(S);
    End;
  End;
End;

Procedure SockFree(S : LongInt);
Var HO : LongInt;
Begin
  If Not SkUsed[S] Then Exit;
  HO := HeapOwner;
  HeapOwner := 0;
  If SkRx[S] <> 0 Then KFree(SkRx[S]);
  If SkTx[S] <> 0 Then KFree(SkTx[S]);
  HeapOwner := HO;
  SkRx[S] := 0; SkTx[S] := 0;
  SkUsed[S] := False;
End;

{ Connexion terminee : liberer le socket si le programme l'a ferme }
Procedure TcpClosed(S : LongInt);
Begin
  SkState[S] := tcClosed;
  SkRetx[S] := 0;
  If (SkFlags[S] And sfAppClosed) <> 0 Then SockFree(S)
  Else If (SkParent[S] >= 0) And ((SkFlags[S] And sfAccepted) = 0) Then
    SockFree(S)
  Else NetNotify(S, FD_CLOSE);
End;

Function SockAlloc(Typ : LongInt) : LongInt; Forward;

Function NewIss : LongInt;
Begin
  NetIss := NetIss + 64000 + Ticks * 250;
  NewIss := NetIss;
End;

Procedure TcpRst(Src, DP, SP, Seq, Ack, Fl, DLen : LongInt);
Begin
  If (Fl And thAck) <> 0 Then
    TcpRaw(Src, DP, SP, Ack, 0, thRst, 0, 0, 0)
  Else
  Begin
    If (Fl And thSyn) <> 0 Then Inc(DLen);
    If (Fl And thFin) <> 0 Then Inc(DLen);
    TcpRaw(Src, DP, SP, 0, Seq + DLen, thRst Or thAck, 0, 0, 0);
  End;
End;

Procedure TcpInput(Src, P, Len : LongInt);
Var SP, DP, Seq, Ack, HL, Fl, Wnd, DLen, D, S, I, C, N, A, Sent,
    Free0, St, Cnt : LongInt;
    NeedAck, FinAck : Boolean;
Begin
  If Len < 20 Then Exit;
  SP := NGetW(P); DP := NGetW(P + 2);
  Seq := NGetL(P + 4); Ack := NGetL(P + 8);
  HL := (Mem[0:P + 12] Shr 4) * 4;
  Fl := Mem[0:P + 13];
  Wnd := NGetW(P + 14);
  If (HL < 20) Or (HL > Len) Then Exit;
  D := P + HL; DLen := Len - HL;
  S := -1;
  For I := 0 To MaxSock - 1 Do
    If SkUsed[I] And (SkType[I] = 1) And (SkLPort[I] = DP) And
       (SkRPort[I] = SP) And (SkRIP[I] = Src) And
       Not (SkState[I] In [tcClosed, tcListen]) Then S := I;
  If S < 0 Then
    For I := 0 To MaxSock - 1 Do
      If SkUsed[I] And (SkType[I] = 1) And (SkLPort[I] = DP) And
         (SkState[I] = tcListen) Then S := I;
  If S < 0 Then
  Begin
    If (Fl And thRst) = 0 Then TcpRst(Src, DP, SP, Seq, Ack, Fl, DLen);
    Exit;
  End;
  St := SkState[S];
  If St = tcListen Then
  Begin
    If (Fl And (thSyn Or thAck Or thRst)) <> thSyn Then
    Begin
      If (Fl And thRst) = 0 Then TcpRst(Src, DP, SP, Seq, Ack, Fl, DLen);
      Exit;
    End;
    Cnt := 0;
    For I := 0 To MaxSock - 1 Do
      If SkUsed[I] And (SkParent[I] = S) And
         ((SkFlags[I] And sfAccepted) = 0) Then Inc(Cnt);
    If Cnt >= SkBacklog[S] Then Exit;
    C := SockAlloc(1);
    If C < 0 Then Exit;
    SkParent[C] := S;
    SkLPort[C] := DP; SkRIP[C] := Src; SkRPort[C] := SP;
    SkFlags[C] := (SkFlags[S] And sfNonBlock) Or sfBound;
    SkAWnd[C] := SkAWnd[S]; SkAMsg[C] := SkAMsg[S]; SkAEv[C] := SkAEv[S];
    SkRcvNxt[C] := Seq + 1;
    SkSndUna[C] := NewIss;
    SkSndNxt[C] := SkSndUna[C] + 1;
    SkSndWnd[C] := Wnd;
    SkState[C] := tcSynRcvd;
    TcpSend(C, thSyn Or thAck, SkSndUna[C], 0, 0);
    TcpArm(C);
    Exit;
  End;
  If St = tcSynSent Then
  Begin
    If ((Fl And thAck) <> 0) And (Ack <> SkSndNxt[S]) Then
    Begin
      If (Fl And thRst) = 0 Then TcpRst(Src, DP, SP, Seq, Ack, Fl, DLen);
      Exit;
    End;
    If (Fl And thRst) <> 0 Then
    Begin
      If (Fl And thAck) <> 0 Then
      Begin
        SkErr[S] := 10061;                     { WSAECONNREFUSED }
        TcpClosed(S);
      End;
      Exit;
    End;
    If ((Fl And thSyn) <> 0) And ((Fl And thAck) <> 0) Then
    Begin
      SkRcvNxt[S] := Seq + 1;
      SkSndUna[S] := Ack;
      SkSndWnd[S] := Wnd;
      SkState[S] := tcEstab;
      SkRetx[S] := 0; SkTries[S] := 0; SkRto[S] := 500;
      TcpSend(S, thAck, SkSndNxt[S], 0, 0);
      NetNotify(S, FD_CONNECT);
      NetNotify(S, FD_WRITE);
      TcpOutput(S);
    End;
    Exit;
  End;
  { etats synchronises }
  If (Fl And thRst) <> 0 Then
  Begin
    If (Seq - SkRcvNxt[S] >= 0) And (Seq - SkRcvNxt[S] < 65536) Then
    Begin
      If St In [tcEstab, tcFinWait1, tcFinWait2, tcCloseWait] Then
        SkErr[S] := 10054;                     { WSAECONNRESET }
      TcpClosed(S);
    End;
    Exit;
  End;
  If (Fl And thSyn) <> 0 Then
  Begin
    { SYN repete (notre ACK perdu) : le confirmer de nouveau }
    TcpSend(S, thAck, SkSndNxt[S], 0, 0);
    Exit;
  End;
  If (Fl And thAck) = 0 Then Exit;
  NeedAck := False;
  If St = tcSynRcvd Then
  Begin
    If Ack <> SkSndNxt[S] Then
    Begin
      TcpRst(Src, DP, SP, Seq, Ack, Fl, DLen);
      Exit;
    End;
    SkSndUna[S] := Ack;
    SkState[S] := tcEstab;
    St := tcEstab;
    SkRetx[S] := 0; SkTries[S] := 0; SkRto[S] := 500;
    If SkParent[S] >= 0 Then NetNotify(SkParent[S], FD_ACCEPT);
  End;
  { donnees et FIN confirmes }
  A := Ack - SkSndUna[S];
  Sent := SkSndNxt[S] - SkSndUna[S];
  If (A > 0) And (A <= Sent) Then
  Begin
    FinAck := ((SkFlags[S] And sfFinSent) <> 0) And (A = Sent);
    N := A;
    If FinAck Then N := A - 1;
    If N > SkTxLen[S] Then N := SkTxLen[S];
    If N > 0 Then
    Begin
      MoveMem(SkTx[S] + N, SkTx[S], SkTxLen[S] - N);
      SkTxLen[S] := SkTxLen[S] - N;
    End;
    SkSndUna[S] := Ack;
    SkTries[S] := 0; SkRto[S] := 500;
    If SkSndUna[S] = SkSndNxt[S] Then SkRetx[S] := 0
    Else SkRetx[S] := Ticks + SkRto[S];
    If N > 0 Then NetNotify(S, FD_WRITE);
    If FinAck Then
    Begin
      If St = tcFinWait1 Then
      Begin
        SkState[S] := tcFinWait2;
        St := tcFinWait2;
        If (SkFlags[S] And sfAppClosed) <> 0 Then SkTimer[S] := Ticks + 30000;
      End
      Else If St = tcClosing Then
      Begin
        SkState[S] := tcTimeWait;
        SkTimer[S] := Ticks + 2000;
        Exit;
      End
      Else If St = tcLastAck Then
      Begin
        TcpClosed(S);
        Exit;
      End;
    End;
  End;
  SkSndWnd[S] := Wnd;
  { donnees recues }
  If DLen > 0 Then
  Begin
    NeedAck := True;
    If (St In [tcEstab, tcFinWait1, tcFinWait2]) And (Seq = SkRcvNxt[S])
    Then
    Begin
      Free0 := SkRxSize - SkRxLen[S];
      N := Min(DLen, Free0);
      If N > 0 Then
      Begin
        RingPut(S, D, N);
        SkRcvNxt[S] := SkRcvNxt[S] + N;
        NetNotify(S, FD_READ);
      End;
      If N < DLen Then Fl := Fl And Not thFin;
    End
    Else Fl := Fl And Not thFin;
  End;
  { FIN du correspondant }
  If ((Fl And thFin) <> 0) And (Seq + DLen = SkRcvNxt[S]) And
     ((SkFlags[S] And sfFinRcvd) = 0) Then
  Begin
    SkRcvNxt[S] := SkRcvNxt[S] + 1;
    SkFlags[S] := SkFlags[S] Or sfFinRcvd;
    NeedAck := True;
    If St = tcEstab Then SkState[S] := tcCloseWait
    Else If St = tcFinWait1 Then SkState[S] := tcClosing
    Else If St = tcFinWait2 Then
    Begin
      SkState[S] := tcTimeWait;
      SkTimer[S] := Ticks + 2000;
    End;
    NetNotify(S, FD_READ);
    NetNotify(S, FD_CLOSE);
  End
  Else If ((Fl And thFin) <> 0) And ((SkFlags[S] And sfFinRcvd) <> 0) Then
    NeedAck := True;
  If NeedAck Then TcpSend(S, thAck, SkSndNxt[S], 0, 0);
  TcpOutput(S);
End;

{ Minuteries : retransmission, TIME-WAIT }
Procedure TcpTimers;
Var S, St, N : LongInt;
Begin
  For S := 0 To MaxSock - 1 Do
    If SkUsed[S] And (SkType[S] = 1) Then
    Begin
      St := SkState[S];
      If (SkTimer[S] <> 0) And (Ticks >= SkTimer[S]) Then
      Begin
        SkTimer[S] := 0;
        If (St In [tcTimeWait, tcFinWait2]) Or
           ((SkFlags[S] And sfAppClosed) <> 0) Then
        Begin
          If St <> tcTimeWait Then
            TcpSend(S, thRst Or thAck, SkSndNxt[S], 0, 0);
          TcpClosed(S);
          Continue;
        End;
      End;
      If (SkRetx[S] <> 0) And (Ticks >= SkRetx[S]) Then
      Begin
        SkRetx[S] := 0;
        Inc(SkTries[S]);
        If (SkTries[S] > 8) Or ((St = tcSynSent) And (SkTries[S] > 3)) Then
        Begin
          SkErr[S] := 10060;                   { WSAETIMEDOUT }
          TcpSend(S, thRst Or thAck, SkSndNxt[S], 0, 0);
          TcpClosed(S);
          Continue;
        End;
        SkRto[S] := Min(SkRto[S] * 2, 8000);
        If St = tcSynSent Then
          TcpSend(S, thSyn, SkSndUna[S], 0, 0)
        Else If St = tcSynRcvd Then
          TcpSend(S, thSyn Or thAck, SkSndUna[S], 0, 0)
        Else
        Begin
          { reprendre a partir du plus ancien octet non confirme }
          SkSndNxt[S] := SkSndUna[S];
          SkFlags[S] := SkFlags[S] And Not sfFinSent;
          If St = tcFinWait1 Then SkState[S] := tcEstab
          Else If St = tcLastAck Then SkState[S] := tcCloseWait
          Else If St = tcClosing Then SkState[S] := tcEstab;
          If (SkSndWnd[S] = 0) And (SkTxLen[S] > 0) Then
          Begin
            { sonde de fenetre nulle : un octet }
            TcpSend(S, thAck, SkSndNxt[S], 0, 1);
            SkSndNxt[S] := SkSndNxt[S] + 1;
          End
          Else TcpOutput(S);
          If St = tcClosing Then
          Begin
            If (SkFlags[S] And sfFinSent) <> 0 Then SkState[S] := tcClosing;
          End;
        End;
        TcpArm(S);
      End;
    End;
End;

{ ------------------------------------------------------------------ }
{ Sockets (communs a Winsock et aux outils de Pasdows)                 }
{ ------------------------------------------------------------------ }

Function SockAlloc(Typ : LongInt) : LongInt;
Var I, S, HO : LongInt;
Begin
  S := -1;
  For I := MaxSock - 1 DownTo 0 Do
    If Not SkUsed[I] Then S := I;
  SockAlloc := S;
  If S < 0 Then Exit;
  HO := HeapOwner;
  HeapOwner := 0;
  SkRx[S] := KAlloc(SkRxSize);
  If Typ = 1 Then SkTx[S] := KAlloc(SkTxSize) Else SkTx[S] := 0;
  HeapOwner := HO;
  If (SkRx[S] = 0) Or ((Typ = 1) And (SkTx[S] = 0)) Then
  Begin
    SkUsed[S] := True;
    SockFree(S);
    SockAlloc := -1;
    Exit;
  End;
  SkUsed[S] := True;
  SkType[S] := Typ;
  SkLPort[S] := 0; SkRIP[S] := 0; SkRPort[S] := 0;
  SkState[S] := tcClosed; SkErr[S] := 0;
  SkRxHead[S] := 0; SkRxLen[S] := 0; SkTxLen[S] := 0;
  SkSndUna[S] := 0; SkSndNxt[S] := 0; SkRcvNxt[S] := 0; SkSndWnd[S] := 0;
  SkRetx[S] := 0; SkRto[S] := 500; SkTries[S] := 0;
  SkParent[S] := -1; SkBacklog[S] := 0;
  SkFlags[S] := 0; SkAWnd[S] := 0; SkAMsg[S] := 0; SkAEv[S] := 0;
  SkASent[S] := 0; SkTimer[S] := 0; SkLastWnd[S] := 0;
End;

Function PortUsed(Typ, Pt : LongInt) : Boolean;
Var I : LongInt; R : Boolean;
Begin
  R := False;
  For I := 0 To MaxSock - 1 Do
    If SkUsed[I] And (SkType[I] = Typ) And (SkLPort[I] = Pt) And
       ((SkFlags[I] And sfBound) <> 0) And (SkParent[I] < 0) Then R := True;
  PortUsed := R;
End;

Function EphemeralPort(Typ : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  Repeat
    Inc(NetPortNext);
    If (NetPortNext < 1025) Or (NetPortNext > 5000) Then NetPortNext := 1025;
    Inc(N);
  Until Not PortUsed(Typ, NetPortNext) Or (N > 4000);
  EphemeralPort := NetPortNext;
End;

{ Avis WSAAsyncSelect (une fois par evenement, rearme par l'appel
  correspondant : recv, send, accept) }
Procedure NetNotify(S, Ev : LongInt);
Begin
  If (S < 0) Or Not SkUsed[S] Then Exit;
  If (SkAWnd[S] = 0) Or ((SkAEv[S] And Ev) = 0) Then Exit;
  If (SkASent[S] And Ev) <> 0 Then Exit;
  SkASent[S] := SkASent[S] Or Ev;
  PostMessageA(SkAWnd[S], SkAMsg[S], SockBase + S, Ev);
End;

{ Fermer tous les sockets (fin du programme Win32) }
Procedure NetAppExit;
Var S : LongInt;
Begin
  For S := 0 To MaxSock - 1 Do
    If SkUsed[S] Then
    Begin
      If (SkType[S] = 1) And Not (SkState[S] In [tcClosed, tcListen,
         tcTimeWait]) Then TcpSend(S, thRst Or thAck, SkSndNxt[S], 0, 0);
      SockFree(S);
    End;
  DnsBusy := False;
End;

{ ------------------------------------------------------------------ }
{ Scrutation                                                           }
{ ------------------------------------------------------------------ }

Procedure NetPoll;
Var N, K, A : LongInt;
Begin
  If NetPolling Or (NetRx = 0) Then Exit;
  NetPolling := True;
  K := 0;
  While (NicBase <> 0) And (K < 32) Do
  Begin
    N := NeRecv(NetRx);
    If N = 0 Then Break;
    If N > 0 Then EthInput(NetRx, N);
    Inc(K);
  End;
  K := 0;
  While (LoopN > 0) And (K < 16) Do
  Begin
    A := NetLoop + LoopHead * 1600;
    LoopHead := (LoopHead + 1) Mod MaxLoop;
    Dec(LoopN);
    MoveMem(A + 4, NetLoopRx, MemL[0:A]);
    IpInput(NetLoopRx, MemL[0:A]);
    Inc(K);
  End;
  If Ticks - NetLastTick >= 10 Then
  Begin
    NetLastTick := Ticks;
    DhcpTick;
    TcpTimers;
  End;
  NetPolling := False;
End;

{ Attendre un peu en laissant tourner le reste du systeme }
Procedure NetWait;
Begin
  NetPoll;
  If CurT = 0 Then Idle Else KSleep(1);
End;

{ Attendre la configuration DHCP (au plus Ms millisecondes) }
Function NetReady(Ms : LongInt) : Boolean;
Var T : LongInt;
Begin
  T := Ticks;
  While (NicBase <> 0) And (DhcpState <> 3) And (Ticks - T < Ms) Do
    NetWait;
  NetReady := DhcpState = 3;
End;

{ S'assurer que l'adresse Ethernet du prochain saut est connue }
Function NetResolve(IP : LongInt) : Boolean;
Var Hop, T, K : LongInt;
Begin
  NetResolve := True;
  If IsLoop(IP) Then Exit;
  NetResolve := False;
  If NicBase = 0 Then Exit;
  If Not NetReady(5000) Then Exit;
  Hop := NextHop(IP);
  NetResolve := True;
  If (Hop = -1) Or (ArpFind(Hop) >= 0) Then Exit;
  For K := 1 To 3 Do
  Begin
    ArpSend(1, 0, Hop);
    T := Ticks;
    While Ticks - T < 1000 Do
    Begin
      NetWait;
      If ArpFind(Hop) >= 0 Then Exit;
    End;
  End;
  NetResolve := False;
End;

{ Echo ICMP : True si reponse (Rtt en ms) }
Function NetPing(IP, Size, Timeout : LongInt; Var Rtt : LongInt) : Boolean;
Var T0, K : LongInt;
Begin
  NetPing := False;
  Rtt := 0;
  If Not NetResolve(IP) Then Exit;
  If Size > 1024 Then Size := 1024;
  Inc(PingSeq);
  PingSeq := PingSeq And $FFFF;
  PingGotAt := 0;
  Mem[0:NetTx + 34] := 8; Mem[0:NetTx + 35] := 0;
  NPutW(NetTx + 36, 0);
  NPutW(NetTx + 38, PingId); NPutW(NetTx + 40, PingSeq);
  If PingReq <> 0 Then MoveMem(PingReq, NetTx + 42, Size)
  Else
    For K := 0 To Size - 1 Do Mem[0:NetTx + 42 + K] := 97 + K Mod 23;
  NPutW(NetTx + 36, (Not NetSum(NetTx + 34, Size + 8, 0)) And $FFFF);
  T0 := Ticks;
  IpSend(IP, 1, Size + 8);
  While (PingGotAt = 0) And (Ticks - T0 < Timeout) Do NetWait;
  If PingGotAt = 0 Then Exit;
  Rtt := PingGotAt - T0;
  NetPing := True;
End;

{ ------------------------------------------------------------------ }
{ DNS (resolveur)                                                      }
{ ------------------------------------------------------------------ }

Function DnsSkipName(P : LongInt) : LongInt;
Var B : LongInt;
Begin
  Repeat
    B := Mem[0:P];
    If B = 0 Then
    Begin
      DnsSkipName := P + 1;
      Exit;
    End;
    If (B And $C0) = $C0 Then
    Begin
      DnsSkipName := P + 2;
      Exit;
    End;
    P := P + 1 + B;
  Until False;
End;

Procedure DnsInput(P, Len : LongInt);
Var QD, AN, I, Q, Typ, RL, E : LongInt;
Begin
  If (Len < 12) Or (NGetW(P) <> DnsId) Then Exit;
  If (Mem[0:P + 3] And 15) <> 0 Then
  Begin
    DnsResult := -2;
    Exit;
  End;
  QD := NGetW(P + 4); AN := NGetW(P + 6);
  Q := P + 12; E := P + Len;
  For I := 1 To QD Do Q := DnsSkipName(Q) + 4;
  For I := 1 To AN Do
  Begin
    If Q >= E Then Break;
    Q := DnsSkipName(Q);
    Typ := NGetW(Q); RL := NGetW(Q + 8);
    If (Typ = 1) And (RL = 4) And (NGetW(Q + 2) = 1) Then
    Begin
      DnsResult := MemL[0:Q + 10];
      Exit;
    End;
    Q := Q + 10 + RL;
  End;
  DnsResult := -2;
End;

{ Nom -> adresse IP ; False si introuvable }
Function NetLookup(Name : String; Var IP : LongInt) : Boolean;
Var D, O, I, K, N, T, Try0 : LongInt; Lb : String; U : String;
Begin
  NetLookup := True;
  If ParseIp(Name, IP) Then Exit;
  U := UpStr(Name);
  If (U = 'LOCALHOST') Or (U = '') Then
  Begin
    IP := $0100007F;
    Exit;
  End;
  If (U = 'PASDOWS') And (NetIP <> 0) Then
  Begin
    IP := NetIP;
    Exit;
  End;
  NetLookup := False;
  If (NicBase = 0) Or DnsBusy Then Exit;
  If Not NetReady(5000) Or (NetDns = 0) Then Exit;
  If Not NetResolve(NetDns) Then Exit;
  DnsBusy := True;
  For Try0 := 1 To 3 Do
  Begin
    DnsId := (DnsId + 1) And $FFFF;
    DnsPort := EphemeralPort(2);
    D := NetTx + 42;
    NPutW(D, DnsId); NPutW(D + 2, $0100);
    NPutW(D + 4, 1); NPutW(D + 6, 0); NPutW(D + 8, 0); NPutW(D + 10, 0);
    O := D + 12;
    Lb := Name + '.';
    K := 1;
    For I := 1 To Length(Lb) Do
      If Lb[I] = '.' Then
      Begin
        N := I - K;
        If N > 0 Then
        Begin
          Mem[0:O] := N;
          For T := 0 To N - 1 Do Mem[0:O + 1 + T] := Ord(Lb[K + T]);
          O := O + 1 + N;
        End;
        K := I + 1;
      End;
    Mem[0:O] := 0;
    NPutW(O + 1, 1); NPutW(O + 3, 1);
    O := O + 5;
    DnsResult := 0;
    UdpOut(DnsPort, NetDns, 53, O - D);
    T := Ticks;
    While (DnsResult = 0) And (Ticks - T < 2000) Do NetWait;
    If DnsResult <> 0 Then Break;
  End;
  DnsBusy := False;
  If (DnsResult = 0) Or (DnsResult = -2) Then Exit;
  IP := DnsResult;
  NetLookup := True;
End;

{ ------------------------------------------------------------------ }
{ Demarrage                                                            }
{ ------------------------------------------------------------------ }

Procedure NetInit;
Var I, HO : LongInt;
Begin
  HO := HeapOwner;
  HeapOwner := 0;
  NetRx := KAlloc(2048);
  NetTx := KAlloc(2048);
  NetAux := KAlloc(2048);
  NetHdr := KAlloc(128);
  NetLoop := KAlloc(MaxLoop * 1600);
  NetLoopRx := KAlloc(1600);
  WsBuf := KAlloc(512);
  HeapOwner := HO;
  For I := 0 To MaxSock - 1 Do SkUsed[I] := False;
  For I := 0 To MaxArp - 1 Do ArpIP[I] := 0;
  NetIpId := Ticks And $FFFF;
  NetIss := Ticks * 7919;
  NetPortNext := 1024 + Ticks Mod 1000;
  PingId := $0200;
  DnsId := Ticks And $FFFF;
  NetMask := $00FFFFFF;
  If Not NeProbe Then
  Begin
    KLog('Reseau : aucune carte NE2000 (TCP/IP en boucle locale seulement)');
    Exit;
  End;
  If NicPci Then
    KLog('Reseau : carte NE2000 PCI (RTL8029) en ' + HexStr(NicBase, 4) +
         'h, adresse ' + MacStr)
  Else
    KLog('Reseau : carte NE2000 ISA en ' + HexStr(NicBase, 4) +
         'h, adresse ' + MacStr);
  DhcpXid := (NicMac[3] Shl 24) Or (NicMac[4] Shl 16) Or (NicMac[5] Shl 8) Or
             (Ticks And $FF);
  DhcpState := 1;
  DhcpTries := 0;
  DhcpNext := Ticks;
End;
{ ==================================================================== }
{ Partie 16b - Winsock 1.1 (WSOCK32.DLL, WS2_32.DLL), ICMP.DLL et       }
{              outils TCP/IP de Pasdows (ping, winipcfg)               }
{ ==================================================================== }

{ Les fonctions Winsock sont ecrites WS_nom : ResolveImport et
  GetProcAddress ajoutent le prefixe pour les DLL Winsock (importations
  par nom ou par ordinal), ce qui evite les conflits avec les noms du
  noyau (send, select, connect...). }

Var
  WsaErr     : LongInt;
  WsAsyncN   : LongInt;

Const
  FIONBIO = LongInt($8004667E);
  FIONREAD = $4004667F;
  SIOCATMARK = $40047307;

{ Nom Winsock d'un ordinal de WSOCK32.DLL / WS2_32.DLL }
Function WsOrdName(N : LongInt) : String;
Var S : String;
Begin
  S := '';
  Case N Of
    1 : S := 'accept'; 2 : S := 'bind'; 3 : S := 'closesocket';
    4 : S := 'connect'; 5 : S := 'getpeername'; 6 : S := 'getsockname';
    7 : S := 'getsockopt'; 8 : S := 'htonl'; 9 : S := 'htons';
    10 : S := 'inet_addr'; 11 : S := 'inet_ntoa'; 12 : S := 'ioctlsocket';
    13 : S := 'listen'; 14 : S := 'ntohl'; 15 : S := 'ntohs';
    16 : S := 'recv'; 17 : S := 'recvfrom'; 18 : S := 'select';
    19 : S := 'send'; 20 : S := 'sendto'; 21 : S := 'setsockopt';
    22 : S := 'shutdown'; 23 : S := 'socket';
    51 : S := 'gethostbyaddr'; 52 : S := 'gethostbyname';
    53 : S := 'getprotobyname'; 54 : S := 'getprotobynumber';
    55 : S := 'getservbyname'; 56 : S := 'getservbyport';
    57 : S := 'gethostname';
    101 : S := 'WSAAsyncSelect'; 102 : S := 'WSAAsyncGetHostByAddr';
    103 : S := 'WSAAsyncGetHostByName'; 104 : S := 'WSAAsyncGetProtoByNumber';
    105 : S := 'WSAAsyncGetProtoByName'; 106 : S := 'WSAAsyncGetServByPort';
    107 : S := 'WSAAsyncGetServByName'; 108 : S := 'WSACancelAsyncRequest';
    109 : S := 'WSASetBlockingHook'; 110 : S := 'WSAUnhookBlockingHook';
    111 : S := 'WSAGetLastError'; 112 : S := 'WSASetLastError';
    113 : S := 'WSACancelBlockingCall'; 114 : S := 'WSAIsBlocking';
    115 : S := 'WSAStartup'; 116 : S := 'WSACleanup';
    151 : S := '__WSAFDIsSet'; 1107 : S := 'WSARecvEx';
  End;
  WsOrdName := S;
End;

Function IsWsDll(Dll : String) : Boolean;
Begin
  Dll := UpStr(BaseName(Dll));
  IsWsDll := (Dll = 'WSOCK32.DLL') Or (Dll = 'WS2_32.DLL') Or
             (Dll = 'WSOCK32') Or (Dll = 'WS2_32');
End;

Function WsSock(H : LongInt) : LongInt;
Var S : LongInt;
Begin
  S := H - SockBase;
  If (S < 0) Or (S >= MaxSock) Then S := -1
  Else If Not SkUsed[S] Or ((SkFlags[S] And sfAppClosed) <> 0) Then S := -1;
  If S < 0 Then WsaErr := 10038;                   { WSAENOTSOCK }
  WsSock := S;
End;

Function WsFail(E : LongInt) : LongInt;
Begin
  WsaErr := E;
  WsFail := -1;
End;

Procedure WsAutoBind(S : LongInt);
Begin
  If (SkFlags[S] And sfBound) <> 0 Then Exit;
  SkLPort[S] := EphemeralPort(SkType[S]);
  SkFlags[S] := SkFlags[S] Or sfBound;
End;

{ sockaddr_in : famille, port (ordre du reseau), adresse }
Procedure WsPutAddr(A, LenP, IP, Pt : LongInt);
Begin
  If A = 0 Then Exit;
  If LenP <> 0 Then
    If MemL[0:LenP] < 16 Then Exit;
  FillMem(A, 16, 0);
  MemW[0:A] := 2;
  MemW[0:A + 2] := Swap16(Pt);
  MemL[0:A + 4] := IP;
  If LenP <> 0 Then MemL[0:LenP] := 16;
End;

Function WS_WSAStartup(Ver, P : LongInt) : LongInt;
Begin
  If P <> 0 Then
  Begin
    FillMem(P, 400, 0);
    If (Ver And $FF) >= 2 Then MemW[0:P] := $0202
    Else MemW[0:P] := Ver And $FFFF;
    MemW[0:P + 2] := $0202;
    PutPStr(P + 4, 'Pasdows 95 TCP/IP (Winsock 1.1)', 256);
    PutPStr(P + 261, 'Running', 128);
    MemW[0:P + 390] := MaxSock;
    MemW[0:P + 392] := 1472;
  End;
  WS_WSAStartup := 0;
End;

Function WS_WSACleanup : LongInt;
Begin
  WS_WSACleanup := 0;
End;

Function WS_WSAGetLastError : LongInt;
Begin
  WS_WSAGetLastError := WsaErr;
End;

Procedure WS_WSASetLastError(E : LongInt);
Begin
  WsaErr := E;
End;

Function WS_socket(Af, Typ, Proto : LongInt) : LongInt;
Var S : LongInt;
Begin
  WS_socket := -1;
  If Af <> 2 Then
  Begin
    WsaErr := 10047;                              { WSAEAFNOSUPPORT }
    Exit;
  End;
  If (Typ <> 1) And (Typ <> 2) Then
  Begin
    WsaErr := 10044;                              { WSAESOCKTNOSUPPORT }
    Exit;
  End;
  S := SockAlloc(Typ);
  If S < 0 Then
  Begin
    WsaErr := 10024;                              { WSAEMFILE }
    Exit;
  End;
  WS_socket := SockBase + S;
End;

Function WS_closesocket(H : LongInt) : LongInt;
Var S, I : LongInt;
Begin
  WS_closesocket := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  WS_closesocket := 0;
  SkAWnd[S] := 0;
  If SkType[S] = 2 Then
  Begin
    SockFree(S);
    Exit;
  End;
  Case SkState[S] Of
    tcListen :
    Begin
      For I := 0 To MaxSock - 1 Do
        If SkUsed[I] And (SkParent[I] = S) And
           ((SkFlags[I] And sfAccepted) = 0) Then
        Begin
          If SkState[I] <> tcClosed Then
            TcpSend(I, thRst Or thAck, SkSndNxt[I], 0, 0);
          SockFree(I);
        End;
      SockFree(S);
    End;
    tcClosed, tcSynSent : SockFree(S);
    tcSynRcvd :
    Begin
      TcpSend(S, thRst Or thAck, SkSndNxt[S], 0, 0);
      SockFree(S);
    End;
    tcEstab, tcCloseWait :
    Begin
      SkFlags[S] := SkFlags[S] Or sfFinWant Or sfAppClosed;
      SkTimer[S] := Ticks + 60000;
      TcpOutput(S);
    End;
  Else
    SkFlags[S] := SkFlags[S] Or sfAppClosed;
  End;
End;

Function WS_bind(H, A, Len : LongInt) : LongInt;
Var S, Pt : LongInt;
Begin
  WS_bind := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If (A = 0) Or (Len < 8) Then
  Begin
    WsaErr := 10014;                              { WSAEFAULT }
    Exit;
  End;
  If (SkFlags[S] And sfBound) <> 0 Then
  Begin
    WsaErr := 10022;                              { WSAEINVAL }
    Exit;
  End;
  Pt := Swap16(MemW[0:A + 2]);
  If Pt = 0 Then Pt := EphemeralPort(SkType[S])
  Else If PortUsed(SkType[S], Pt) Then
  Begin
    WsaErr := 10048;                              { WSAEADDRINUSE }
    Exit;
  End;
  SkLPort[S] := Pt;
  SkFlags[S] := SkFlags[S] Or sfBound;
  WS_bind := 0;
End;

Function WS_listen(H, Bl : LongInt) : LongInt;
Var S : LongInt;
Begin
  WS_listen := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkType[S] <> 1 Then
  Begin
    WsaErr := 10045;                              { WSAEOPNOTSUPP }
    Exit;
  End;
  If Not (SkState[S] In [tcClosed, tcListen]) Then
  Begin
    WsaErr := 10056;                              { WSAEISCONN }
    Exit;
  End;
  WsAutoBind(S);
  SkState[S] := tcListen;
  If (Bl < 1) Or (Bl > 5) Then Bl := 5;
  SkBacklog[S] := Bl;
  WS_listen := 0;
End;

Function WsPending(S : LongInt) : LongInt;
Var I, R : LongInt;
Begin
  R := -1;
  For I := MaxSock - 1 DownTo 0 Do
    If SkUsed[I] And (SkParent[I] = S) And
       ((SkFlags[I] And sfAccepted) = 0) And
       (SkState[I] In [tcEstab, tcCloseWait]) Then R := I;
  WsPending := R;
End;

Function WS_accept(H, A, LenP : LongInt) : LongInt;
Var S, C : LongInt;
Begin
  WS_accept := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkState[S] <> tcListen Then
  Begin
    WsaErr := 10022;
    Exit;
  End;
  Repeat
    NetPoll;
    C := WsPending(S);
    If C >= 0 Then Break;
    If (SkFlags[S] And sfNonBlock) <> 0 Then
    Begin
      SkASent[S] := SkASent[S] And Not FD_ACCEPT;
      WsaErr := 10035;                            { WSAEWOULDBLOCK }
      Exit;
    End;
    NetWait;
    If Not SkUsed[S] Or (SkState[S] <> tcListen) Then
    Begin
      WsaErr := 10004;                            { WSAEINTR }
      Exit;
    End;
  Until False;
  SkFlags[C] := SkFlags[C] Or sfAccepted;
  WsPutAddr(A, LenP, SkRIP[C], SkRPort[C]);
  SkASent[S] := SkASent[S] And Not FD_ACCEPT;
  If WsPending(S) >= 0 Then NetNotify(S, FD_ACCEPT);
  If SkRxLen[C] > 0 Then NetNotify(C, FD_READ);
  NetNotify(C, FD_WRITE);
  WS_accept := SockBase + C;
End;

Function WS_connect(H, A, Len : LongInt) : LongInt;
Var S, IP, Pt : LongInt;
Begin
  WS_connect := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If (A = 0) Or (Len < 8) Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  IP := MemL[0:A + 4];
  Pt := Swap16(MemW[0:A + 2]);
  If SkType[S] = 2 Then
  Begin
    WsAutoBind(S);
    SkRIP[S] := IP; SkRPort[S] := Pt;
    If IP = 0 Then SkFlags[S] := SkFlags[S] And Not sfUdpConn
    Else SkFlags[S] := SkFlags[S] Or sfUdpConn;
    WS_connect := 0;
    Exit;
  End;
  If SkState[S] = tcSynSent Then
  Begin
    WsaErr := 10037;                              { WSAEALREADY }
    Exit;
  End;
  If SkState[S] <> tcClosed Then
  Begin
    WsaErr := 10056;
    Exit;
  End;
  If (IP = 0) Or (Pt = 0) Then
  Begin
    WsaErr := 10049;                              { WSAEADDRNOTAVAIL }
    Exit;
  End;
  If Not NetResolve(IP) Then
  Begin
    If NicBase = 0 Then WsaErr := 10050           { WSAENETDOWN }
    Else WsaErr := 10065;                         { WSAEHOSTUNREACH }
    Exit;
  End;
  WsAutoBind(S);
  SkRIP[S] := IP; SkRPort[S] := Pt; SkErr[S] := 0;
  SkFlags[S] := SkFlags[S] And (sfNonBlock Or sfBound);
  SkRxHead[S] := 0; SkRxLen[S] := 0; SkTxLen[S] := 0;
  SkSndUna[S] := NewIss;
  SkSndNxt[S] := SkSndUna[S] + 1;
  SkState[S] := tcSynSent;
  SkRto[S] := 1000; SkTries[S] := 0; SkRetx[S] := 0;
  TcpSend(S, thSyn, SkSndUna[S], 0, 0);
  TcpArm(S);
  If (SkFlags[S] And sfNonBlock) <> 0 Then
  Begin
    WsaErr := 10035;
    Exit;
  End;
  While SkState[S] = tcSynSent Do NetWait;
  If SkState[S] In [tcEstab, tcCloseWait] Then WS_connect := 0
  Else
  Begin
    WsaErr := SkErr[S];
    If WsaErr = 0 Then WsaErr := 10061;
  End;
End;

Function WS_sendto(H, Buf, Len, Fl, ToA, ToLen : LongInt) : LongInt;
  Forward;
Function WS_recvfrom(H, Buf, Len, Fl, FromA, FromLenP : LongInt) : LongInt;
  Forward;

Function WS_send(H, Buf, Len, Fl : LongInt) : LongInt;
Var S, N, Done : LongInt;
Begin
  WS_send := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkType[S] = 2 Then
  Begin
    WS_send := WS_sendto(H, Buf, Len, Fl, 0, 0);
    Exit;
  End;
  Done := 0;
  Repeat
    If SkErr[S] <> 0 Then
    Begin
      WsaErr := SkErr[S];
      If Done > 0 Then WS_send := Done;
      Exit;
    End;
    If Not (SkState[S] In [tcEstab, tcCloseWait]) Then
    Begin
      WsaErr := 10057;                            { WSAENOTCONN }
      If Done > 0 Then WS_send := Done;
      Exit;
    End;
    If (SkFlags[S] And sfFinWant) <> 0 Then
    Begin
      WsaErr := 10058;                            { WSAESHUTDOWN }
      Exit;
    End;
    N := Min(Len - Done, SkTxSize - SkTxLen[S]);
    If N > 0 Then
    Begin
      MoveMem(Buf + Done, SkTx[S] + SkTxLen[S], N);
      SkTxLen[S] := SkTxLen[S] + N;
      Done := Done + N;
      TcpOutput(S);
    End;
    If Done >= Len Then Break;
    If (SkFlags[S] And sfNonBlock) <> 0 Then
    Begin
      If Done > 0 Then Break;
      SkASent[S] := SkASent[S] And Not FD_WRITE;
      WsaErr := 10035;
      Exit;
    End;
    NetWait;
    If Not SkUsed[S] Then Exit;
  Until False;
  WS_send := Done;
End;

Function WS_recv(H, Buf, Len, Fl : LongInt) : LongInt;
Var S, N : LongInt;
Begin
  WS_recv := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkType[S] = 2 Then
  Begin
    WS_recv := WS_recvfrom(H, Buf, Len, Fl, 0, 0);
    Exit;
  End;
  Repeat
    NetPoll;
    If (SkRxLen[S] > 0) And (Len > 0) Then
    Begin
      N := Min(Len, SkRxLen[S]);
      RingGet(S, Buf, N, (Fl And 2) <> 0);
      SkASent[S] := SkASent[S] And Not FD_READ;
      If SkRxLen[S] > 0 Then NetNotify(S, FD_READ);
      { fenetre rouverte : le dire au correspondant }
      If (SkState[S] In [tcEstab, tcFinWait1, tcFinWait2]) And
         (SkWnd(S) - SkLastWnd[S] >= 2 * NetMss) Then
        TcpSend(S, thAck, SkSndNxt[S], 0, 0);
      WS_recv := N;
      Exit;
    End;
    If (SkFlags[S] And sfFinRcvd) <> 0 Then
    Begin
      WS_recv := 0;
      Exit;
    End;
    If SkErr[S] <> 0 Then
    Begin
      WsaErr := SkErr[S];
      Exit;
    End;
    If Not (SkState[S] In [tcSynSent, tcSynRcvd, tcEstab, tcFinWait1,
                           tcFinWait2]) Then
    Begin
      If SkState[S] = tcClosed Then WsaErr := 10057
      Else WsaErr := 10022;
      Exit;
    End;
    If Len <= 0 Then
    Begin
      WS_recv := 0;
      Exit;
    End;
    If (SkFlags[S] And sfNonBlock) <> 0 Then
    Begin
      SkASent[S] := SkASent[S] And Not FD_READ;
      WsaErr := 10035;
      Exit;
    End;
    NetWait;
    If Not SkUsed[S] Then Exit;
  Until False;
End;

Function WS_sendto(H, Buf, Len, Fl, ToA, ToLen : LongInt) : LongInt;
Var S, IP, Pt : LongInt;
Begin
  WS_sendto := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkType[S] = 1 Then
  Begin
    WS_sendto := WS_send(H, Buf, Len, Fl);
    Exit;
  End;
  If ToA <> 0 Then
  Begin
    If ToLen < 8 Then
    Begin
      WsaErr := 10014;
      Exit;
    End;
    IP := MemL[0:ToA + 4];
    Pt := Swap16(MemW[0:ToA + 2]);
  End
  Else If (SkFlags[S] And sfUdpConn) <> 0 Then
  Begin
    IP := SkRIP[S]; Pt := SkRPort[S];
  End
  Else
  Begin
    WsaErr := 10039;                              { WSAEDESTADDRREQ }
    Exit;
  End;
  If (Len < 0) Or (Len > 1472) Then
  Begin
    WsaErr := 10040;                              { WSAEMSGSIZE }
    Exit;
  End;
  If (IP = 0) Or (Pt = 0) Then
  Begin
    WsaErr := 10049;
    Exit;
  End;
  If Not NetResolve(IP) Then
  Begin
    If NicBase = 0 Then WsaErr := 10050 Else WsaErr := 10065;
    Exit;
  End;
  WsAutoBind(S);
  If Len > 0 Then MoveMem(Buf, NetTx + 42, Len);
  UdpOut(SkLPort[S], IP, Pt, Len);
  WS_sendto := Len;
End;

Function WS_recvfrom(H, Buf, Len, Fl, FromA, FromLenP : LongInt) : LongInt;
Var S, N, DL, IP, Pt, OH, OL, R : LongInt;
Begin
  WS_recvfrom := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If SkType[S] = 1 Then
  Begin
    R := WS_recv(H, Buf, Len, Fl);
    If R >= 0 Then WsPutAddr(FromA, FromLenP, SkRIP[S], SkRPort[S]);
    WS_recvfrom := R;
    Exit;
  End;
  Repeat
    NetPoll;
    If SkRxLen[S] >= 12 Then
    Begin
      OH := SkRxHead[S]; OL := SkRxLen[S];
      RingGet(S, NetHdr + 32, 12, False);
      DL := MemL[0:NetHdr + 32];
      IP := MemL[0:NetHdr + 36];
      Pt := MemL[0:NetHdr + 40];
      N := Min(Len, DL);
      If N > 0 Then RingGet(S, Buf, N, False);
      If DL > N Then RingGet(S, 0, DL - N, False);
      If (Fl And 2) <> 0 Then
      Begin
        SkRxHead[S] := OH; SkRxLen[S] := OL;
      End;
      WsPutAddr(FromA, FromLenP, IP, Pt);
      SkASent[S] := SkASent[S] And Not FD_READ;
      If SkRxLen[S] > 0 Then NetNotify(S, FD_READ);
      If DL > Len Then WsaErr := 10040 Else WS_recvfrom := N;
      Exit;
    End;
    If (SkFlags[S] And sfNonBlock) <> 0 Then
    Begin
      SkASent[S] := SkASent[S] And Not FD_READ;
      WsaErr := 10035;
      Exit;
    End;
    NetWait;
    If Not SkUsed[S] Then Exit;
  Until False;
End;

Function WS_shutdown(H, How : LongInt) : LongInt;
Var S : LongInt;
Begin
  WS_shutdown := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If (SkType[S] = 1) And ((How = 1) Or (How = 2)) Then
  Begin
    SkFlags[S] := SkFlags[S] Or sfFinWant;
    TcpOutput(S);
  End;
  WS_shutdown := 0;
End;

Function WS_ioctlsocket(H, Cmd, Arg : LongInt) : LongInt;
Var S, N : LongInt;
Begin
  WS_ioctlsocket := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If Arg = 0 Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  NetPoll;
  If Cmd = FIONBIO Then
  Begin
    If MemL[0:Arg] <> 0 Then SkFlags[S] := SkFlags[S] Or sfNonBlock
    Else SkFlags[S] := SkFlags[S] And Not sfNonBlock;
  End
  Else If Cmd = FIONREAD Then
  Begin
    N := SkRxLen[S];
    If SkType[S] = 2 Then
    Begin
      If N >= 12 Then
      Begin
        RingGet(S, NetHdr + 32, 4, True);
        N := MemL[0:NetHdr + 32];
      End
      Else N := 0;
    End;
    MemL[0:Arg] := N;
  End
  Else If Cmd = SIOCATMARK Then MemL[0:Arg] := 1
  Else
  Begin
    WsaErr := 10022;
    Exit;
  End;
  WS_ioctlsocket := 0;
End;

Function WS_setsockopt(H, Lvl, Opt, Val, Len : LongInt) : LongInt;
Begin
  WS_setsockopt := -1;
  If WsSock(H) < 0 Then Exit;
  WS_setsockopt := 0;
End;

Function WS_getsockopt(H, Lvl, Opt, Val, LenP : LongInt) : LongInt;
Var S, V : LongInt;
Begin
  WS_getsockopt := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If (Val = 0) Or (LenP = 0) Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  V := 0;
  If Lvl = $FFFF Then
    Case Opt Of
      $1007 :
      Begin
        V := SkErr[S];
        SkErr[S] := 0;
      End;
      $1008 : V := SkType[S];
      $1001 : V := SkTxSize;
      $1002 : V := SkRxSize;
      2 : V := Ord(SkState[S] = tcListen);
    End;
  If MemL[0:LenP] >= 4 Then
  Begin
    MemL[0:Val] := V;
    MemL[0:LenP] := 4;
  End
  Else If MemL[0:LenP] >= 1 Then Mem[0:Val] := V;
  WS_getsockopt := 0;
End;

Function WS_getpeername(H, A, LenP : LongInt) : LongInt;
Var S : LongInt;
Begin
  WS_getpeername := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If ((SkType[S] = 1) And Not (SkState[S] In [tcEstab, tcCloseWait,
     tcFinWait1, tcFinWait2])) Or
     ((SkType[S] = 2) And ((SkFlags[S] And sfUdpConn) = 0)) Then
  Begin
    WsaErr := 10057;
    Exit;
  End;
  WsPutAddr(A, LenP, SkRIP[S], SkRPort[S]);
  WS_getpeername := 0;
End;

Function WS_getsockname(H, A, LenP : LongInt) : LongInt;
Var S, IP : LongInt;
Begin
  WS_getsockname := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  If (SkFlags[S] And sfBound) = 0 Then
  Begin
    WsaErr := 10022;
    Exit;
  End;
  IP := 0;
  If (SkType[S] = 1) And (SkState[S] <> tcListen) And
     (SkState[S] <> tcClosed) Then
  Begin
    If IsLoop(SkRIP[S]) Then IP := SkRIP[S] Else IP := NetIP;
  End;
  WsPutAddr(A, LenP, IP, SkLPort[S]);
  WS_getsockname := 0;
End;

Function WS_htons(V : LongInt) : LongInt;
Begin
  WS_htons := Swap16(V);
End;

Function WS_ntohs(V : LongInt) : LongInt;
Begin
  WS_ntohs := Swap16(V);
End;

Function WS_htonl(V : LongInt) : LongInt;
Begin
  WS_htonl := Swap32(V);
End;

Function WS_ntohl(V : LongInt) : LongInt;
Begin
  WS_ntohl := Swap32(V);
End;

Function WS_inet_addr(P : LongInt) : LongInt;
Var IP : LongInt;
Begin
  If (P <> 0) And ParseIp(Trim(PStr(P)), IP) Then WS_inet_addr := IP
  Else WS_inet_addr := -1;
End;

Function WS_inet_ntoa(IP : LongInt) : LongInt;
Begin
  PutPStr(WsBuf + 288, IpStr(IP), 31);
  WS_inet_ntoa := WsBuf + 288;
End;

{ hostent en B : nom, alias (aucun), AF_INET, 4 octets, une adresse }
Function WsMakeHost(B : LongInt; Const Nm : String; IP : LongInt)
  : LongInt;
Begin
  MemL[0:B] := B + 32; MemL[0:B + 4] := B + 16;
  MemW[0:B + 8] := 2; MemW[0:B + 10] := 4;
  MemL[0:B + 12] := B + 20;
  MemL[0:B + 16] := 0;
  MemL[0:B + 20] := B + 28; MemL[0:B + 24] := 0;
  MemL[0:B + 28] := IP;
  PutPStr(B + 32, Nm, 255);
  WsMakeHost := 33 + Length(Nm);
End;

Function WS_gethostbyname(P : LongInt) : LongInt;
Var Nm : String; IP : LongInt;
Begin
  WS_gethostbyname := 0;
  If P = 0 Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  Nm := Trim(PStr(P));
  If Not NetLookup(Nm, IP) Then
  Begin
    WsaErr := 11001;                              { WSAHOST_NOT_FOUND }
    Exit;
  End;
  WsMakeHost(WsBuf, Nm, IP);
  WS_gethostbyname := WsBuf;
End;

Function WsAddrName(IP : LongInt) : String;
Begin
  If (IP And $FF) = 127 Then WsAddrName := 'localhost'
  Else If (IP = NetIP) And (IP <> 0) Then WsAddrName := 'pasdows'
  Else WsAddrName := IpStr(IP);
End;

Function WS_gethostbyaddr(A, Len, Typ : LongInt) : LongInt;
Var IP : LongInt;
Begin
  WS_gethostbyaddr := 0;
  If (A = 0) Or (Len < 4) Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  IP := MemL[0:A];
  WsMakeHost(WsBuf, WsAddrName(IP), IP);
  WS_gethostbyaddr := WsBuf;
End;

Function WS_gethostname(Buf, Len : LongInt) : LongInt;
Begin
  WS_gethostname := -1;
  If (Buf = 0) Or (Len < 8) Then
  Begin
    WsaErr := 10014;
    Exit;
  End;
  PutPStr(Buf, 'pasdows', Len);
  WS_gethostname := 0;
End;

{ Services connus (etc\services) }
Function WsServ(I : LongInt; Var Pt : LongInt) : String;
Var S : String;
Begin
  S := ''; Pt := 0;
  Case I Of
    0 : Begin S := 'echo'; Pt := 7 End;
    1 : Begin S := 'discard'; Pt := 9 End;
    2 : Begin S := 'daytime'; Pt := 13 End;
    3 : Begin S := 'ftp-data'; Pt := 20 End;
    4 : Begin S := 'ftp'; Pt := 21 End;
    5 : Begin S := 'telnet'; Pt := 23 End;
    6 : Begin S := 'smtp'; Pt := 25 End;
    7 : Begin S := 'time'; Pt := 37 End;
    8 : Begin S := 'domain'; Pt := 53 End;
    9 : Begin S := 'gopher'; Pt := 70 End;
    10 : Begin S := 'finger'; Pt := 79 End;
    11 : Begin S := 'http'; Pt := 80 End;
    12 : Begin S := 'www'; Pt := 80 End;
    13 : Begin S := 'pop3'; Pt := 110 End;
    14 : Begin S := 'nntp'; Pt := 119 End;
    15 : Begin S := 'ntp'; Pt := 123 End;
    16 : Begin S := 'irc'; Pt := 194 End;
  End;
  WsServ := S;
End;

{ servent en B (16 octets + chaines) }
Function WsMakeServ(B : LongInt; Const Nm, Pr : String; Pt : LongInt)
  : LongInt;
Begin
  MemL[0:B] := B + 24; MemL[0:B + 4] := B + 16;
  MemW[0:B + 8] := Swap16(Pt); MemW[0:B + 10] := 0;
  MemL[0:B + 12] := B + 56;
  MemL[0:B + 16] := 0;
  PutPStr(B + 24, Nm, 31);
  PutPStr(B + 56, Pr, 15);
  WsMakeServ := 72;
End;

Function WsFindServ(Nm : String; Pt : LongInt; Var RNm : String;
                    Var RPt : LongInt) : Boolean;
Var I, P : LongInt; S : String;
Begin
  WsFindServ := False;
  Nm := UpStr(Nm);
  For I := 0 To 16 Do
  Begin
    S := WsServ(I, P);
    If ((Nm <> '') And (UpStr(S) = Nm)) Or ((Nm = '') And (P = Pt)) Then
    Begin
      RNm := S; RPt := P;
      WsFindServ := True;
      Exit;
    End;
  End;
End;

Function WsProtoStr(P : LongInt) : String;
Begin
  If P = 0 Then WsProtoStr := 'tcp' Else WsProtoStr := PStr(P);
End;

Function WS_getservbyname(NmP, PrP : LongInt) : LongInt;
Var S : String; Pt : LongInt;
Begin
  WS_getservbyname := 0;
  If (NmP = 0) Or Not WsFindServ(PStr(NmP), 0, S, Pt) Then
  Begin
    WsaErr := 11004;                              { WSANO_DATA }
    Exit;
  End;
  WsMakeServ(WsBuf + 320, S, WsProtoStr(PrP), Pt);
  WS_getservbyname := WsBuf + 320;
End;

Function WS_getservbyport(Pt, PrP : LongInt) : LongInt;
Var S : String; P : LongInt;
Begin
  WS_getservbyport := 0;
  If Not WsFindServ('', Swap16(Pt), S, P) Then
  Begin
    WsaErr := 11004;
    Exit;
  End;
  WsMakeServ(WsBuf + 320, S, WsProtoStr(PrP), P);
  WS_getservbyport := WsBuf + 320;
End;

Function WsProtoNum(Nm : String) : LongInt;
Begin
  Nm := UpStr(Nm);
  If Nm = 'IP' Then WsProtoNum := 0
  Else If Nm = 'ICMP' Then WsProtoNum := 1
  Else If Nm = 'TCP' Then WsProtoNum := 6
  Else If Nm = 'UDP' Then WsProtoNum := 17
  Else WsProtoNum := -1;
End;

Function WsMakeProto(N : LongInt) : LongInt;
Var B : LongInt; S : String;
Begin
  WsMakeProto := 0;
  Case N Of
    0 : S := 'ip';
    1 : S := 'icmp';
    6 : S := 'tcp';
    17 : S := 'udp';
  Else
    WsaErr := 11004;
    Exit;
  End;
  B := WsBuf + 400;
  MemL[0:B] := B + 16; MemL[0:B + 4] := B + 12;
  MemW[0:B + 8] := N; MemW[0:B + 10] := 0;
  MemL[0:B + 12] := 0;
  PutPStr(B + 16, S, 15);
  WsMakeProto := B;
End;

Function WS_getprotobyname(P : LongInt) : LongInt;
Begin
  If P = 0 Then WS_getprotobyname := 0
  Else WS_getprotobyname := WsMakeProto(WsProtoNum(PStr(P)));
End;

Function WS_getprotobynumber(N : LongInt) : LongInt;
Begin
  WS_getprotobynumber := WsMakeProto(N);
End;

{ select : etat d'un socket (0 lecture, 1 ecriture, 2 exception) }
Function WsReady(S, Kind : LongInt) : Boolean;
Var R : Boolean;
Begin
  R := False;
  If SkType[S] = 2 Then
  Begin
    If Kind = 0 Then R := SkRxLen[S] > 0
    Else If Kind = 1 Then R := True;
  End
  Else If Kind = 0 Then
  Begin
    If SkState[S] = tcListen Then R := WsPending(S) >= 0
    Else R := (SkRxLen[S] > 0) Or ((SkFlags[S] And sfFinRcvd) <> 0) Or
              (SkErr[S] <> 0);
  End
  Else If Kind = 1 Then
    R := (SkState[S] In [tcEstab, tcCloseWait]) And (SkTxLen[S] < SkTxSize)
  Else
    R := (SkState[S] = tcClosed) And (SkErr[S] <> 0);
  WsReady := R;
End;

Function WsSelCount(P, Kind : LongInt; Var Bad : Boolean) : LongInt;
Var I, N, S, C : LongInt;
Begin
  C := 0;
  If P <> 0 Then
  Begin
    N := Min(MemL[0:P], 64);
    For I := 0 To N - 1 Do
    Begin
      S := MemL[0:P + 4 + I * 4] - SockBase;
      If (S < 0) Or (S >= MaxSock) Then Bad := True
      Else If Not SkUsed[S] Then Bad := True
      Else If WsReady(S, Kind) Then Inc(C);
    End;
  End;
  WsSelCount := C;
End;

Procedure WsSelFilter(P, Kind : LongInt);
Var I, N, K, H : LongInt;
Begin
  If P = 0 Then Exit;
  N := Min(MemL[0:P], 64);
  K := 0;
  For I := 0 To N - 1 Do
  Begin
    H := MemL[0:P + 4 + I * 4];
    If WsReady(H - SockBase, Kind) Then
    Begin
      MemL[0:P + 4 + K * 4] := H;
      Inc(K);
    End;
  End;
  MemL[0:P] := K;
End;

Function WS_select(N, R, W, E, Tv : LongInt) : LongInt;
Var T0, Ms, C : LongInt; Bad : Boolean;
Begin
  WS_select := -1;
  If Tv = 0 Then Ms := -1
  Else Ms := MemL[0:Tv] * 1000 + MemL[0:Tv + 4] Div 1000;
  T0 := Ticks;
  Repeat
    NetPoll;
    Bad := False;
    C := WsSelCount(R, 0, Bad) + WsSelCount(W, 1, Bad) +
         WsSelCount(E, 2, Bad);
    If Bad Then
    Begin
      WsaErr := 10038;
      Exit;
    End;
    If (C > 0) Or ((Ms >= 0) And (Ticks - T0 >= Ms)) Then Break;
    NetWait;
  Until False;
  WsSelFilter(R, 0);
  WsSelFilter(W, 1);
  WsSelFilter(E, 2);
  WS_select := C;
End;

Function WS___WSAFDIsSet(H, P : LongInt) : LongInt;
Var I, R : LongInt;
Begin
  R := 0;
  If P <> 0 Then
    For I := 0 To Min(MemL[0:P], 64) - 1 Do
      If MemL[0:P + 4 + I * 4] = H Then R := 1;
  WS___WSAFDIsSet := R;
End;

Function WS_WSAAsyncSelect(H, Wnd, Msg, Ev : LongInt) : LongInt;
Var S : LongInt;
Begin
  WS_WSAAsyncSelect := -1;
  S := WsSock(H);
  If S < 0 Then Exit;
  SkAWnd[S] := Wnd; SkAMsg[S] := Msg; SkAEv[S] := Ev;
  SkASent[S] := 0;
  If Ev = 0 Then SkAWnd[S] := 0;
  SkFlags[S] := SkFlags[S] Or sfNonBlock;
  WS_WSAAsyncSelect := 0;
  If SkAWnd[S] = 0 Then Exit;
  NetPoll;
  If (SkType[S] = 1) And (SkState[S] = tcListen) Then
  Begin
    If WsPending(S) >= 0 Then NetNotify(S, FD_ACCEPT);
  End
  Else If WsReady(S, 0) Then NetNotify(S, FD_READ);
  If WsReady(S, 1) Then NetNotify(S, FD_WRITE);
  If (SkType[S] = 1) And ((SkFlags[S] And sfFinRcvd) <> 0) Then
    NetNotify(S, FD_CLOSE);
End;

Function WS_WSAAsyncGetHostByName(Wnd, Msg, NmP, Buf, BufLen : LongInt)
  : LongInt;
Var Nm : String; IP, N : LongInt;
Begin
  Inc(WsAsyncN);
  WS_WSAAsyncGetHostByName := WsAsyncN;
  Nm := Trim(PStr(NmP));
  If (Buf <> 0) And (BufLen >= 34 + Length(Nm)) And NetLookup(Nm, IP) Then
  Begin
    N := WsMakeHost(Buf, Nm, IP);
    PostMessageA(Wnd, Msg, WsAsyncN, N);
  End
  Else PostMessageA(Wnd, Msg, WsAsyncN, LongInt(11001) Shl 16);
End;

Function WS_WSAAsyncGetHostByAddr(Wnd, Msg, A, Len, Typ, Buf, BufLen
  : LongInt) : LongInt;
Var Nm : String; N, IP : LongInt;
Begin
  Inc(WsAsyncN);
  WS_WSAAsyncGetHostByAddr := WsAsyncN;
  If (A = 0) Or (Buf = 0) Or (BufLen < 64) Then
  Begin
    PostMessageA(Wnd, Msg, WsAsyncN, LongInt(10014) Shl 16);
    Exit;
  End;
  IP := MemL[0:A];
  Nm := WsAddrName(IP);
  N := WsMakeHost(Buf, Nm, IP);
  PostMessageA(Wnd, Msg, WsAsyncN, N);
End;

Function WS_WSAAsyncGetServByName(Wnd, Msg, NmP, PrP, Buf, BufLen
  : LongInt) : LongInt;
Var S : String; Pt : LongInt;
Begin
  Inc(WsAsyncN);
  WS_WSAAsyncGetServByName := WsAsyncN;
  If (Buf <> 0) And (BufLen >= 72) And (NmP <> 0) And
     WsFindServ(PStr(NmP), 0, S, Pt) Then
    PostMessageA(Wnd, Msg, WsAsyncN, WsMakeServ(Buf, S, WsProtoStr(PrP), Pt))
  Else PostMessageA(Wnd, Msg, WsAsyncN, LongInt(11004) Shl 16);
End;

Function WS_WSAAsyncGetServByPort(Wnd, Msg, Pt, PrP, Buf, BufLen
  : LongInt) : LongInt;
Var S : String; P : LongInt;
Begin
  Inc(WsAsyncN);
  WS_WSAAsyncGetServByPort := WsAsyncN;
  If (Buf <> 0) And (BufLen >= 72) And WsFindServ('', Swap16(Pt), S, P) Then
    PostMessageA(Wnd, Msg, WsAsyncN, WsMakeServ(Buf, S, WsProtoStr(PrP), P))
  Else PostMessageA(Wnd, Msg, WsAsyncN, LongInt(11004) Shl 16);
End;

Function WS_WSACancelAsyncRequest(H : LongInt) : LongInt;
Begin
  WS_WSACancelAsyncRequest := 0;
End;

Function WS_WSASetBlockingHook(P : LongInt) : LongInt;
Begin
  WS_WSASetBlockingHook := 0;
End;

Function WS_WSAUnhookBlockingHook : LongInt;
Begin
  WS_WSAUnhookBlockingHook := 0;
End;

Function WS_WSACancelBlockingCall : LongInt;
Begin
  WS_WSACancelBlockingCall := 0;
End;

Function WS_WSAIsBlocking : LongInt;
Begin
  WS_WSAIsBlocking := 0;
End;

Function WS_WSARecvEx(H, Buf, Len, FlP : LongInt) : LongInt;
Begin
  If FlP <> 0 Then MemL[0:FlP] := 0;
  WS_WSARecvEx := WS_recv(H, Buf, Len, 0);
End;

{ ------------------------------------------------------------------ }
{ ICMP.DLL : IcmpSendEcho (utilise par PING.EXE)                       }
{ ------------------------------------------------------------------ }

Function IcmpCreateFile : LongInt;
Begin
  IcmpCreateFile := $1C3;
End;

Function IcmpCloseHandle(H : LongInt) : LongInt;
Begin
  IcmpCloseHandle := 1;
End;

Function IcmpSendEcho(H, Dst, Req, ReqSize, Opts, Reply, ReplySize,
                      Timeout : LongInt) : LongInt;
Var Rtt : LongInt; Ok : Boolean;
Begin
  IcmpSendEcho := 0;
  If (Reply = 0) Or (ReplySize < 28) Then Exit;
  If ReplySize >= 28 + ReqSize Then PingData := Reply + 28
  Else PingData := 0;
  PingReq := Req;
  Ok := NetPing(Dst, ReqSize, Max(Timeout, 100), Rtt);
  PingReq := 0;
  PingData := 0;
  FillMem(Reply, 28, 0);
  If Ok Then
  Begin
    MemL[0:Reply] := PingFrom;
    MemL[0:Reply + 8] := Rtt;
    If ReplySize >= 28 + ReqSize Then MemW[0:Reply + 12] := PingLen;
    MemL[0:Reply + 16] := Reply + 28;
    Mem[0:Reply + 20] := PingTtl;
    IcmpSendEcho := 1;
  End
  Else
  Begin
    MemL[0:Reply] := Dst;
    MemL[0:Reply + 4] := 11010;                   { IP_REQ_TIMED_OUT }
    SetErr(11010);
  End;
End;

{ ------------------------------------------------------------------ }
{ Outils de Pasdows : configuration IP (winipcfg) et ping              }
{ ------------------------------------------------------------------ }

Function NetTitle : String;
Begin
  NetTitle := L('Configuration IP', 'IP Configuration', 'IP-Konfiguration',
                'Configurazione IP', 'Configuraci'#162'n IP');
End;

Procedure NetConfigBox;
Var S, A : String;
Begin
  NetPoll;
  If NicBase = 0 Then
  Begin
    MsgBoxOpen(NetTitle, L('Aucune carte r'#130'seau NE2000 n''a ' +
      #130't'#130' d'#130'tect'#130'e. TCP/IP fonctionne seulement en boucle ' +
      'locale ' +
      '(127.0.0.1).', 'No NE2000 network adapter was detected. TCP/IP ' +
      'only works on the loopback address (127.0.0.1).',
      'Keine NE2000-Netzwerkkarte gefunden. TCP/IP nur lokal ' +
      '(127.0.0.1).', 'Nessuna scheda di rete NE2000 rilevata. TCP/IP ' +
      'solo in locale (127.0.0.1).', 'No se detect'#162' ning'#163'n ' +
      'adaptador NE2000. TCP/IP s'#162'lo en local (127.0.0.1).'), $30);
    Exit;
  End;
  If NicPci Then A := 'NE2000 PCI' Else A := 'NE2000 ISA';
  S := L('Carte', 'Adapter', 'Karte', 'Scheda', 'Adaptador') + ' : ' + A +
       '|' + L('Adresse de la carte', 'Adapter address', 'Kartenadresse',
       'Indirizzo scheda', 'Direcci'#162'n') + ' : ' + MacStr + '|' +
       L('Adresse IP', 'IP address', 'IP-Adresse', 'Indirizzo IP',
       'Direcci'#162'n IP') + ' : ' + IpStr(NetIP) + '|' +
       L('Masque de sous-r'#130'seau', 'Subnet mask', 'Subnetzmaske',
       'Subnet mask', 'M'#160'scara') + ' : ' + IpStr(NetMask) + '|' +
       L('Passerelle', 'Gateway', 'Gateway', 'Gateway', 'Puerta') + ' : ' +
       IpStr(NetGw) + '|DNS : ' + IpStr(NetDns) + '|';
  If DhcpState = 3 Then
    S := S + 'DHCP : ' + IpStr(NetDhcpSrv)
  Else
    S := S + L('DHCP en cours...', 'DHCP in progress...', 'DHCP l'#132'uft...',
               'DHCP in corso...', 'DHCP en curso...');
  MsgBoxOpen(NetTitle, S, $40);
End;

Procedure NetPingBox(Host : String);
Var IP, I, Ok, Rtt, Mn, Mx, Sum, Ttl : LongInt; S : String;
Begin
  If Not NetLookup(Host, IP) Then
  Begin
    MsgBoxOpen('Ping', L('H'#147'te inconnu : ', 'Unknown host: ',
               'Unbekannter Host: ', 'Host sconosciuto: ',
               'Host desconocido: ') + Host, $10);
    Exit;
  End;
  Ok := 0; Mn := 999999; Mx := 0; Sum := 0; Ttl := 0;
  For I := 1 To 4 Do
    If NetPing(IP, 32, 1000, Rtt) Then
    Begin
      Inc(Ok);
      Mn := Min(Mn, Rtt); Mx := Max(Mx, Rtt); Sum := Sum + Rtt;
      Ttl := PingTtl;
    End;
  S := 'Ping ' + Host + ' [' + IpStr(IP) + '] : 32 ' +
       L('octets', 'bytes', 'Bytes', 'byte', 'bytes') + '||';
  If Ok > 0 Then
    S := S + L('R'#130'ponse de ', 'Reply from ', 'Antwort von ',
               'Risposta da ', 'Respuesta desde ') + IpStr(IP) +
         ' : TTL=' + IntStr(Ttl) + '|' +
         L('Dur'#130'e', 'Time', 'Zeit', 'Tempo', 'Tiempo') + ' : min ' +
         IntStr(Mn) + ' ms, max ' + IntStr(Mx) + ' ms, ' +
         L('moyenne', 'average', 'Mittel', 'media', 'media') + ' ' +
         IntStr(Sum Div Ok) + ' ms|'
  Else
    S := S + L('D'#130'lai d''attente d'#130'pass'#130'.', 'Request timed out.',
               'Zeit'#129'berschreitung.', 'Richiesta scaduta.',
               'Tiempo agotado.') + '|';
  S := S + L('Paquets : envoy'#130's = 4, re'#135'us = ',
             'Packets: sent = 4, ' +
             'received = ', 'Pakete: gesendet = 4, empfangen = ',
             'Pacchetti: inviati = 4, ricevuti = ',
             'Paquetes: enviados = 4, recibidos = ') + IntStr(Ok);
  If Ok > 0 Then I := $40 Else I := $30;
  MsgBoxOpen('Ping', S, I);
End;

{ Commandes TCP/IP de la boite Executer }
Function NetRunCmd(S : String) : Boolean;
Var U : String;
Begin
  NetRunCmd := True;
  S := Trim(S);
  U := UpStr(S);
  If (U = 'WINIPCFG') Or (U = 'WINIPCFG.EXE') Or (U = 'IPCONFIG') Or
     (U = 'IPCONFIG.EXE') Then NetConfigBox
  Else If (Copy(U, 1, 5) = 'PING ') And (Length(Trim(Copy(S, 6, 255))) > 0)
  Then NetPingBox(Trim(Copy(S, 6, 255)))
  Else NetRunCmd := False;
End;
{ Fonctions Win32 exportees par VMM32.VXD (thunks stdcall) }

exports VideoForWindowsVersion, GetDiskFreeSpaceExA,
  WS_WSAStartup, WS_WSACleanup, WS_WSAGetLastError, WS_WSASetLastError,
  WS_socket, WS_closesocket, WS_bind, WS_listen, WS_accept, WS_connect,
  WS_sendto, WS_recvfrom, WS_send, WS_recv, WS_shutdown, WS_ioctlsocket,
  WS_setsockopt, WS_getsockopt, WS_getpeername, WS_getsockname, WS_htons,
  WS_ntohs, WS_htonl, WS_ntohl, WS_inet_addr, WS_inet_ntoa, WS_gethostbyname,
  WS_gethostbyaddr, WS_gethostname, WS_getservbyname, WS_getservbyport,
  WS_getprotobyname, WS_getprotobynumber, WS_select, WS___WSAFDIsSet,
  WS_WSAAsyncSelect, WS_WSAAsyncGetHostByName, WS_WSAAsyncGetHostByAddr,
  WS_WSAAsyncGetServByName, WS_WSAAsyncGetServByPort,
  WS_WSACancelAsyncRequest, WS_WSASetBlockingHook, WS_WSAUnhookBlockingHook,
  WS_WSACancelBlockingCall, WS_WSAIsBlocking, WS_WSARecvEx, IcmpCreateFile,
  IcmpCloseHandle, IcmpSendEcho,
  DXNI1, DXNI2, DXNI3, DXNI4, DXNI5, DXNI6, DXOK1, DXOK2, DXOK3, COMAddRef,
  COMRelease, COMQIUnk, DXOK4, DirectDrawCreate, DirectDrawEnumerateA, DD_QI,
  DD_SetCooperativeLevel, DD_SetDisplayMode, DD_SetDisplayMode2,
  DD_RestoreDisplayMode, DD_FlipToGDISurface, DD_EnumDisplayModes,
  DD_GetDisplayMode, DD_GetCaps, DD_GetMonitorFrequency, DD_GetScanLine,
  DD_GetVBStatus, DD_WaitForVB, DD_GetAvailableVidMem, DD_CreateSurface,
  DD_CreatePalette, DD_CreateClipper, PL_GetCaps, PL_GetEntries,
  PL_SetEntries, CL_GetHWnd, CL_IsClipListChanged, CL_SetHWnd, SF_QI,
  SF_GetSurfaceDesc, SF_Lock, SF_Unlock, SF_GetCaps, SF_GetPixelFormat,
  SF_GetAttachedSurface, SF_Flip, SF_GetColorKey, SF_SetColorKey,
  SF_SetPalette, SF_GetPalette, SF_SetClipper, SF_GetDDInterface, SF_Blt,
  SF_BltFast, SF_GetDC, SF_ReleaseDC, DXOK5, DirectSoundCreate,
  DirectSoundEnumerateA, DS_GetCaps, DS_GetSpeakerConfig,
  DS_CreateSoundBuffer, DS_DuplicateSoundBuffer, DSB_GetCaps,
  DSB_GetCurrentPosition, DSB_GetFormat, DSB_GetVolume, DSB_GetPan,
  DSB_GetFrequency, DSB_GetStatus, DSB_Lock, DSB_Play, DSB_Stop,
  DSB_SetCurrentPosition, DSB_SetVolume, DSB_SetPan, DSB_SetFrequency,
  DirectInputCreateA, DI_CreateDevice, DI_EnumDevices, DI_GetDeviceStatus,
  DID_GetCapabilities, DID_GetDeviceState, DID_GetDeviceData, DirectXSetup,
  DirectXSetupA, DirectXDeviceDriverSetup, DirectXSetupGetVersion,
  DirectXSetupSetCallback, DirectXRegisterApplication,
  DirectXUnRegisterApplication,
  GetEnvironmentStringsW, FreeEnvironmentStringsW, GetLocaleInfoW,
  GetStringTypeA, GetStringTypeW, LCMapStringA, LCMapStringW, CompareStringA,
  CompareStringW, GetMapMode, SetMapMode, MessageBoxIndirectA, SetFileTime,
  SetHandleCount, DisableThreadLibraryCalls, ExtEscape, ThunkConnect32,
  SMapLS_IP_EBP_12, SMapLS_IP_EBP_16, SMapLS_IP_EBP_20, SMapLS_IP_EBP_24,
  SUnMapLS_IP_EBP_12, SUnMapLS_IP_EBP_16, SUnMapLS_IP_EBP_20,
  SUnMapLS_IP_EBP_24, SHFileOperation, W16Bridge, CreateDirectoryA,
  RemoveDirectoryA, FindWindowA, RegCreateKeyExA, RegFlushKey,
  RegDeleteKeyA, RegSetValueA, RegQueryValueA, RegEnumKeyExA, RegEnumKeyA,
  RegEnumValueA, RegDeleteValueA, RegQueryInfoKeyA,
  RtlMoveMemory, RtlZeroMemory, RtlFillMemory, OpenMutexA, GetShortPathNameA,
  GetLogicalDriveStringsA, MoveFileExA, GetTempFileNameA, SearchPathA,
  SystemTimeToFileTime, GetLocaleInfoA, CreateFileMappingA, MapViewOfFile,
  FlushViewOfFile, UnmapViewOfFile, CreateScalableFontResourceA, CreateCaret,
  DestroyCaret, SetCaretPos, ShowCaret, HideCaret, ExcludeUpdateRgn,
  GetLastActivePopup, DdeInitializeA, DdeUninitialize,
  DdeCreateStringHandleA, DdeFreeStringHandle, DdeConnect, DdeDisconnect,
  DdeClientTransaction, DdeAccessData, DdeUnaccessData, DdeFreeDataHandle,
  DdeGetLastError, GetFileVersionInfoSizeA, GetFileVersionInfoA,
  VerQueryValueA, VerFindFileA, VerInstallFileA, CopyFileA,
  LZOpenFileA, LZClose,
  LZCopy, WNetGetConnectionA, WNetAddConnectionA, WNetAddConnection2A,
  WNetCancelConnectionA, WNetCancelConnection2A, WNetConnectionDialog,
  WNetGetLastErrorA,
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
    NetPoll;
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
  { Image du programme a son adresse preferee : de 4 Mo a ExeTop. Avec
    moins de 32 Mo, 4 Mo lui suffisent et le tas commence a 8 Mo : il
    commencait toujours a 16 Mo, et avec 16 Mo de memoire il ne restait
    que 544 Ko libres - aucun programme ne pouvait demarrer. Une image
    plus grande est chargee dans le tas (relocalisee), comme une DLL. }
  If MemTop >= $02000000 Then ExeTop := HeapBase Else ExeTop := $00800000;
  HeapInit(ExeTop, MemTop);
  Case Mem[0:BootInfo + 3] Mod 5 Of
    1 : Language := _English;
    2 : Language := _Germany;
    3 : Language := _Italian;
    4 : Language := _Spain;
  Else
    Language := _French;
  End;
  OptFlags := MemL[0:BootInfo + $30];
  Lfb := MemL[0:BootInfo + $0C];
  LfbPitch := MemW[0:BootInfo + $10];
  VgaPlanar := MemW[0:BootInfo + $16] = 4;
  If VgaPlanar Then VgaInit;
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
  FmtAskW := -1; ExpCW := -1;
  FatInit;
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
  RegInit;
  InitW16;
  InitW16Apis;
  W16Init2;
  NetInit;
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
