{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW95IO)
  @description: IO.SYS - noyau de Pasdows 95, un clone de Windows 95
                ecrit en Pascal, amorcable directement depuis un CD-ROM.
}

Program IO;

{ Compilation : WPC -CW95IO IO.PAS IO.SYS

  WPC (Windows 95 Pascal Compiler, TOOLS/WPC.PAS) produit une image
  binaire brute 8086 dont les 2 premiers Ko sont charges par le BIOS
  (El Torito, sans emulation) en 0000:7C00 ; l'amorce placee en tete
  de l'image par le compilateur relit le reste d'IO.SYS depuis le
  CD-ROM puis saute au programme principal avec DL = unite d'amorcage
  (disponible ici dans PrefixSeg).

  Comme le IO.SYS de Windows 95, ce fichier contient tout ce qu'il
  faut pour demarrer le systeme. Il n'utilise ni DOS ni unite :
  seulement le BIOS (video, disque, horloge) et le materiel (VGA,
  controleur clavier 8042, souris PS/2, haut-parleur).

    - ecran de demarrage texte, menu de demarrage (F8) ;
    - lecture du CD-ROM ISO 9660 (INT 13h etendue), des options de
      MSDOS.SYS ([Options] BootMenu, BootGUI, Logo, BootDelay) et
      execution des commandes SET de AUTOEXEC.BAT (variables
      d'environnement) ;
    - langue : francais par defaut, LANGUAGE=EN (anglais),
      LANGUAGE=GR (allemand), LANGUAGE=SP (espagnol) ou
      LANGUAGE=IT (italien) ;
    - interface graphique VGA 640x480 en 16 couleurs : ecran
      d'accueil, bureau et icones, barre des taches, menu Demarrer,
      fenetres deplacables (reduire, agrandir, fermer), souris ;
    - applications : Poste de travail (explorateur du CD-ROM),
      Bloc-notes, Calculatrice, Paint, Invite MS-DOS, Panneau de
      configuration (Affichage, Date/Heure, Parametres regionaux,
      Systeme), Corbeille, Aide, Executer, Arreter Windows ;
    - mode MS-DOS plein ecran (texte 80x25).

  Carte memoire (mode reel) :
    00000h-07BFFh  vecteurs, BIOS, pile (0000:7C00 vers le bas)
    07C00h-....    IO.SYS (code, puis donnees et BSS)
    60000h-64FFFh  toile de Paint (256x160, 4 bits par pixel)
    70000h-7FFFFh  texte du Bloc-notes
    80000h-807FFh  tampon d'un secteur du CD-ROM
    81000h-887FFh  lecture des fichiers (30 Ko)                     }

{$S-,R-,I-}

Const
  ScrW      = 640;
  ScrH      = 480;
  VSeg      = $A000;
  PaintSeg  = $6000;
  NoteSeg   = $7000;
  CdSeg     = $8000;
  TmpSeg    = $8100;
  NoteMax   = 60000;
  TmpMax    = 30720;
  Version   = '4.00.950';

  { Palette de Windows 95 (16 couleurs) }
  cBlack   = 0;  cMaroon  = 1;  cGreen   = 2;  cOlive   = 3;
  cNavy    = 4;  cPurple  = 5;  cTeal    = 6;  cSilver  = 7;
  cGray    = 8;  cRed     = 9;  cLime    = 10; cYellow  = 11;
  cBlue    = 12; cFuchsia = 13; cAqua    = 14; cWhite   = 15;
  PalR : Array[0..15] Of Byte = (0, 32, 0, 32, 0, 32, 0, 48,
                                 32, 63, 0, 63, 0, 63, 0, 63);
  PalG : Array[0..15] Of Byte = (0, 0, 32, 32, 0, 0, 32, 48,
                                 32, 0, 63, 63, 0, 0, 63, 63);
  PalB : Array[0..15] Of Byte = (0, 0, 0, 0, 32, 32, 32, 48,
                                 32, 0, 0, 0, 63, 63, 63, 63);

  { Barre des taches }
  TaskH = 28;
  TaskY = ScrH - TaskH;

  { Sortes de fenetres (une seule instance de chaque) }
  wkExplorer = 1;  wkNotepad  = 2;  wkCalc     = 3;  wkDos      = 4;
  wkControl  = 5;  wkDisplay  = 6;  wkRegional = 7;  wkSystem   = 8;
  wkAbout    = 9;  wkRun      = 10; wkShutdown = 11; wkRecycle  = 12;
  wkHelp     = 13; wkMsg      = 14; wkWelcome  = 15; wkPaint    = 16;
  wkDateTime = 17;
  WinMax     = 17;

  { Icones }
  icComputer = 1;  icRecycle  = 2;  icDos      = 3;  icNotepad  = 4;
  icCalc     = 5;  icText     = 6;  icFolder   = 7;  icCdrom    = 8;
  icFloppy   = 9;  icControl  = 10; icDisplay  = 11; icRegional = 12;
  icSystem   = 13; icClock    = 14; icHelp     = 15; icRun      = 16;
  icShutdown = 17; icPaint    = 18; icInfo     = 19; icWarn     = 20;
  icError    = 21; icPrograms = 22; icDocs     = 23; icSettings = 24;
  icApp      = 25; icHardDisk = 26; icLogo     = 27; icExplorer = 28;

  { Commandes }
  cmNone     = 0;  cmNotepad  = 1;  cmCalc     = 2;  cmPaint    = 3;
  cmDos      = 4;  cmComputer = 5;  cmControl  = 6;  cmDisplay  = 7;
  cmRegional = 8;  cmSystem   = 9;  cmDateTime = 10; cmHelp     = 11;
  cmRun      = 12; cmShutdown = 13; cmAbout    = 14; cmRecycle  = 15;
  cmNoteNew  = 16; cmNoteOpen = 17; cmClose    = 18; cmNoteTime = 19;
  cmNoteClear = 20; cmExpOpen = 21; cmExpUp    = 22; cmPaintNew = 23;
  cmEmptyBin = 24; cmExplorer = 25; cmReadme   = 26; cmWelcome  = 27;
  cmDocBase  = 100;

  { Menus }
  mnStart    = 1;  mnPrograms = 2;  mnDocs     = 3;  mnSettings = 4;
  mnAccess   = 5;  mnNoteFile = 6;  mnNoteEdit = 7;  mnHelp     = 8;
  mnExpFile  = 9;  mnPaintFile = 10; mnBinFile = 11;

  { Evenements }
  evKey  = 1;
  evDown = 2;
  evUp   = 3;

  { Dimensions des applications }
  ConMaxC = 80;
  ConMaxR = 25;
  CanW    = 256;
  CanH    = 160;
  CdMax   = 48;
  EnvMax  = 24;

  { Curseur de la souris (fleche) : X = noir, W = blanc }
  CurH = 19;
  CurShape : Array[0..18] Of String[12] = (
    'X           ', 'XX          ', 'XWX         ', 'XWWX        ',
    'XWWWX       ', 'XWWWWX      ', 'XWWWWWX     ', 'XWWWWWWX    ',
    'XWWWWWWWX   ', 'XWWWWWWWWX  ', 'XWWWWWWWWWX ', 'XWWWWWWXXXXX',
    'XWWWXWWX    ', 'XWWXXWWX    ', 'XWX  XWWX   ', 'XX   XWWX   ',
    'X     XWWX  ', '      XWWX  ', '       XX   ');


  { Touches speciales (champ Sc des evenements clavier) }
  scEsc = $01; scBack = $0E; scTab = $0F; scEnter = $1C;
  scF1 = $3B; scF4 = $3E; scF5 = $3F; scF8 = $42;
  scHome = $47; scUp = $48; scPgUp = $49; scLeft = $4B;
  scRight = $4D; scEnd = $4F; scDown = $50; scPgDn = $51;
  scIns = $52; scDel = $53; scWin = $5B;

Type
  TLanguage = (_French, _English, _Germany, _Italian, _Spain);

  TWin = Record
    Open, Min, Max : Boolean;
    X, Y, W, H : Integer;
    NX, NY, NW, NH : Integer;
  End;

  TCdFile = Record
    Name : String[12];
    Size, Lba : LongInt;
    Dir : Boolean;
    Yr, Mo, Dy, Hr, Mi : Byte;
  End;

  TMenuLevel = Record
    Id, X, Y, W, H, Hot, Count, ItemH : Integer;
  End;

  TEvent = Record
    Kind : Byte;
    Ch : Char;
    Sc : Byte;
    Shift, Ctrl, Alt : Boolean;
    X, Y : Integer;
    Btn : Byte;
  End;

  TDap = Record
    Size   : Byte;
    Res    : Byte;
    Count  : Word;
    BufOfs : Word;
    BufSg  : Word;
    LbaLo  : LongInt;
    LbaHi  : LongInt;
  End;

Var
  Language    : TLanguage;
  BootDrive   : Byte;
  FontSeg     : Word;
  FontOfs     : Word;
  { Decoupage (rectangle d'affichage permis) }
  ClipX1, ClipY1, ClipX2, ClipY2 : Integer;
  AreaX1, AreaY1, AreaX2, AreaY2 : Integer;
  { Fenetres }
  Wins        : Array[1..WinMax] Of TWin;
  ZOrd        : Array[0..WinMax] Of Byte;
  ZCnt        : Integer;
  TaskOrd     : Array[0..WinMax] Of Byte;
  TaskCnt     : Integer;
  DeskColor   : Byte;
  SafeMode    : Boolean;
  GuiOn       : Boolean;
  QuitGui     : Byte;
  DeskSel     : Integer;
  { Souris }
  MouseX, MouseY : Integer;
  MouseBtn    : Byte;
  MouseOk     : Boolean;
  MPhase      : Integer;
  MPack       : Array[0..2] Of Byte;
  CurShown    : Boolean;
  CurX, CurY  : Integer;
  CurSave     : Array[0..3, 0..18, 0..2] Of Byte;
  LastMX, LastMY : Integer;
  { Clavier }
  KExt, KShift, KCtrl, KAlt, KCaps : Boolean;
  KeyLo, KeyHi : String[60];
  { File d'evenements }
  EvQ         : Array[0..31] Of TEvent;
  EvHead, EvTail : Integer;
  { Glisser une fenetre }
  DragWin     : Integer;
  DragDX, DragDY, DragX, DragY : Integer;
  { Bouton enfonce (fenetre, bouton) }
  PressWin, PressBtn : Integer;
  { Double-clic }
  ClickTick   : Word;
  ClickTarget : Integer;
  { Menus deroulants }
  Menus       : Array[0..3] Of TMenuLevel;
  MenuDepth   : Integer;
  MenuOwner   : Integer;
  { Environnement }
  EnvStr      : Array[1..EnvMax] Of String[80];
  EnvCnt      : Integer;
  { CD-ROM }
  Dap         : TDap;
  RootLba, RootSize : LongInt;
  VolLabel    : String[32];
  CdFiles     : Array[0..CdMax - 1] Of TCdFile;
  CdCount     : Integer;
  CdOk        : Boolean;
  { Horloge }
  LastMin     : Integer;
  LastSec     : Integer;
  { Explorateur }
  ExpView     : Integer;
  ExpSel      : Integer;
  { Panneau de configuration }
  CtlSel      : Integer;
  { Bloc-notes }
  NoteLen, NoteCur, NoteTop, NoteLeft : Word;
  NoteName    : String[12];
  { Calculatrice }
  CalcDisp    : String[40];
  CalcAcc, CalcMem : Real;
  CalcOp      : Char;
  CalcNew, CalcErr : Boolean;
  { Paint }
  PaintColor  : Byte;
  PaintTool   : Integer;
  PaintDown   : Boolean;
  PaintLX, PaintLY : Integer;
  { Invite MS-DOS }
  ConBuf      : Array[0..ConMaxC * ConMaxR - 1] Of Char;
  ConCols, ConRows, ConX, ConY : Integer;
  ConLine     : String;
  ConText     : Boolean;
  ConQuit     : Boolean;
  { Dialogues }
  DispSel     : Integer;
  RegSel      : Integer;
  ShutSel     : Integer;
  RunText     : String[60];
  MsgTitle    : String[40];
  MsgText     : String;
  MsgIcon     : Integer;
  TipNo       : Integer;
  { Options de MSDOS.SYS }
  OptBootMenu, OptBootGUI, OptLogo : Boolean;
  OptBootDelay : Integer;
  { Divers }
  MemConv, MemExt : Word;
  CpuType     : Integer;

{ ================================================================== }
{ Utilitaires                                                        }
{ ================================================================== }

{ Tables du clavier : jeu de codes 1, disposition americaine }
Procedure InitKeyTables;
Begin
  KeyLo := #0#27'1234567890-='#8#9'qwertyuiop[]'#13#0 +
           'asdfghjkl;''`'#0'\zxcvbnm,./'#0'*'#0' ';
  KeyHi := #0#27'!@#$%^&*()_+'#8#9'QWERTYUIOP{}'#13#0 +
           'ASDFGHJKL:"~'#0'|ZXCVBNM<>?'#0'*'#0' ';
End;

Function IntToStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IntToStr := S;
End;

Function HexByte(B : Byte) : String;
Const HX : String[16] = '0123456789ABCDEF';
Begin
  HexByte := HX[(B Shr 4) + 1] + HX[(B And 15) + 1];
End;

Function Pad2(V : Integer) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  Pad2 := S;
End;

Function UpStr(S : String) : String;
Var I : Integer;
Begin
  For I := 1 To Length(S) Do
    If (S[I] >= 'a') And (S[I] <= 'z') Then S[I] := Chr(Ord(S[I]) - 32);
  UpStr := S;
End;

Function Trim(S : String) : String;
Begin
  While (Length(S) > 0) And ((S[1] = ' ') Or (S[1] = #9)) Do
    Delete(S, 1, 1);
  While (Length(S) > 0) And ((S[Length(S)] = ' ') Or
        (S[Length(S)] = #9)) Do
    Delete(S, Length(S), 1);
  Trim := S;
End;

Function Min(A, B : Integer) : Integer;
Begin
  If A < B Then Min := A Else Min := B;
End;

Function Max(A, B : Integer) : Integer;
Begin
  If A > B Then Max := A Else Max := B;
End;

Function InRect(PX, PY, X1, Y1, X2, Y2 : Integer) : Boolean;
Begin
  InRect := (PX >= X1) And (PX <= X2) And (PY >= Y1) And (PY <= Y2);
End;

{ Compteur de l'horloge du BIOS (18,2 tops par seconde) }
Function Ticks : Word;
Begin
  Ticks := MemW[$0040:$006C];
End;

Procedure WaitTicks(N : Word);
Var T : Word;
Begin
  T := Ticks;
  While Word(Ticks - T) < N Do;
End;

{ ================================================================== }
{ Langue                                                             }
{ ================================================================== }

{ Choisir le texte selon la langue : francais, anglais, allemand,
  italien, espagnol }
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

Function LangCode : String;
Begin
  LangCode := L('FR', 'EN', 'GR', 'IT', 'SP');
End;

{ Separateur des milliers selon la langue }
Function FmtNum(V : LongInt) : String;
Var S, R : String; N : Integer; Sep : Char;
Begin
  Str(V, S);
  Case Language Of
    _English : Sep := ',';
    _French  : Sep := ' ';
  Else
    Sep := '.';
  End;
  R := ''; N := 0;
  While Length(S) > 0 Do
  Begin
    If (N > 0) And (N Mod 3 = 0) And (S[Length(S)] <> '-') Then
      R := Sep + R;
    R := S[Length(S)] + R;
    Delete(S, Length(S), 1);
    Inc(N);
  End;
  FmtNum := R;
End;

Function MonthName(M : Integer) : String;
Begin
  Case M Of
    1 : MonthName := L('janvier', 'January', 'Januar', 'gennaio',
                       'enero');
    2 : MonthName := L('f'#130'vrier', 'February', 'Februar', 'febbraio',
                       'febrero');
    3 : MonthName := L('mars', 'March', 'M'#132'rz', 'marzo', 'marzo');
    4 : MonthName := L('avril', 'April', 'April', 'aprile', 'abril');
    5 : MonthName := L('mai', 'May', 'Mai', 'maggio', 'mayo');
    6 : MonthName := L('juin', 'June', 'Juni', 'giugno', 'junio');
    7 : MonthName := L('juillet', 'July', 'Juli', 'luglio', 'julio');
    8 : MonthName := L('ao'#150't', 'August', 'August', 'agosto',
                       'agosto');
    9 : MonthName := L('septembre', 'September', 'September',
                       'settembre', 'septiembre');
    10 : MonthName := L('octobre', 'October', 'Oktober', 'ottobre',
                        'octubre');
    11 : MonthName := L('novembre', 'November', 'November',
                        'novembre', 'noviembre');
  Else
    MonthName := L('d'#130'cembre', 'December', 'Dezember', 'dicembre',
                   'diciembre');
  End;
End;

Function DayLetters : String;
Begin
  DayLetters := L('DLMMJVS', 'SMTWTFS', 'SMDMDFS', 'DLMMGVS',
                  'DLMMJVS');
End;

{ ================================================================== }
{ Environnement (variables SET)                                      }
{ ================================================================== }

Function EnvIndex(Const Name : String) : Integer;
Var I, P : Integer; U : String;
Begin
  EnvIndex := 0;
  U := UpStr(Name);
  For I := 1 To EnvCnt Do
  Begin
    P := Pos('=', EnvStr[I]);
    If (P > 0) And (UpStr(Copy(EnvStr[I], 1, P - 1)) = U) Then
    Begin
      EnvIndex := I;
      Exit;
    End;
  End;
End;

Function GetEnv(Const Name : String) : String;
Var I : Integer;
Begin
  I := EnvIndex(Name);
  If I = 0 Then GetEnv := ''
  Else GetEnv := Copy(EnvStr[I], Pos('=', EnvStr[I]) + 1, 255);
End;

Procedure SetEnv(Name, Value : String);
Var I, J : Integer;
Begin
  Name := UpStr(Trim(Name));
  If Name = '' Then Exit;
  I := EnvIndex(Name);
  If Value = '' Then
  Begin
    If I > 0 Then
    Begin
      For J := I To EnvCnt - 1 Do EnvStr[J] := EnvStr[J + 1];
      Dec(EnvCnt);
    End;
    Exit;
  End;
  If I = 0 Then
  Begin
    If EnvCnt >= EnvMax Then Exit;
    Inc(EnvCnt);
    I := EnvCnt;
  End;
  EnvStr[I] := Name + '=' + Value;
End;

{ Langue d'apres la variable d'environnement LANGUAGE }
Procedure ApplyLanguage;
Var S : String;
Begin
  S := GetEnv('LANGUAGE');
  If (Length(S) > 0) And (S[1] = '"') Then S := Copy(S, 2, 255);
  S := UpStr(Copy(S, 1, 2));
  Language := _French;
  If S = 'EN' Then Language := _English Else
  If S = 'GR' Then Language := _Germany Else
  If S = 'IT' Then Language := _Italian Else
  If S = 'SP' Then Language := _Spain;
End;

{ ================================================================== }
{ BIOS : horloge, memoire, processeur, haut-parleur                  }
{ ================================================================== }

Function Bcd(B : Byte) : Integer;
Begin
  Bcd := (B Shr 4) * 10 + (B And 15);
End;

Procedure RtcTime(Var H, M, S : Integer);
Var VHr, VMn, VSc : Byte;
Begin
  asm
    mov ah,02h
    int 1Ah
    mov VHr,ch
    mov VMn,cl
    mov VSc,dh
  end;
  H := Bcd(VHr); M := Bcd(VMn); S := Bcd(VSc);
End;

Procedure RtcDate(Var Y, M, D : Integer);
Var VCe, VYr, VMo, VDy : Byte;
Begin
  asm
    mov ah,04h
    int 1Ah
    mov VCe,ch
    mov VYr,cl
    mov VMo,dh
    mov VDy,dl
  end;
  Y := Bcd(VCe) * 100 + Bcd(VYr);
  M := Bcd(VMo); D := Bcd(VDy);
  If Y < 1980 Then Y := 2026;
  If (M < 1) Or (M > 12) Then M := 1;
  If (D < 1) Or (D > 31) Then D := 1;
End;

Function TimeStr : String;
Var H, M, S : Integer;
Begin
  RtcTime(H, M, S);
  If Language = _English Then
  Begin
    If H = 0 Then TimeStr := '12:' + Pad2(M) + ' AM'
    Else If H < 12 Then TimeStr := IntToStr(H) + ':' + Pad2(M) + ' AM'
    Else If H = 12 Then TimeStr := '12:' + Pad2(M) + ' PM'
    Else TimeStr := IntToStr(H - 12) + ':' + Pad2(M) + ' PM';
  End
  Else
    TimeStr := Pad2(H) + ':' + Pad2(M);
End;

Function DateStr : String;
Var Y, M, D : Integer;
Begin
  RtcDate(Y, M, D);
  Case Language Of
    _English : DateStr := Pad2(M) + '/' + Pad2(D) + '/' + IntToStr(Y);
    _Germany : DateStr := Pad2(D) + '.' + Pad2(M) + '.' + IntToStr(Y);
  Else
    DateStr := Pad2(D) + '/' + Pad2(M) + '/' + IntToStr(Y);
  End;
End;

{ Jour de la semaine (0 = dimanche) }
Function DayOfWeek(Y, M, D : Integer) : Integer;
Const T : Array[1..12] Of Integer = (0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4);
Begin
  If M < 3 Then Dec(Y);
  DayOfWeek := (Y + Y Div 4 - Y Div 100 + Y Div 400 + T[M] + D) Mod 7;
End;

Function DaysInMonth(Y, M : Integer) : Integer;
Begin
  Case M Of
    4, 6, 9, 11 : DaysInMonth := 30;
    2 : If ((Y Mod 4 = 0) And (Y Mod 100 <> 0)) Or (Y Mod 400 = 0) Then
          DaysInMonth := 29
        Else
          DaysInMonth := 28;
  Else
    DaysInMonth := 31;
  End;
End;

Procedure DetectSystem;
Var C, E, T : Word;
Begin
  asm
    int 12h
    mov C,ax
    mov ah,88h
    int 15h
    jnc @ok
    xor ax,ax
  @ok:
    mov E,ax
    pushf
    pop ax
    and ax,0FFFh
    push ax
    popf
    pushf
    pop ax
    and ax,0F000h
    cmp ax,0F000h
    mov bx,0
    je @fin
    or ax,0F000h
    push ax
    popf
    pushf
    pop ax
    and ax,0F000h
    mov bx,1
    jz @fin
    mov bx,2
  @fin:
    mov T,bx
  end;
  MemConv := C; MemExt := E; CpuType := T;
End;

Procedure Sound(Hz : Word);
Var D : Word;
Begin
  If Hz < 20 Then Exit;
  D := Word(1193180 Div LongInt(Hz));
  Port[$43] := $B6;
  Port[$42] := Lo(D);
  Port[$42] := Hi(D);
  Port[$61] := Port[$61] Or 3;
End;

Procedure NoSound;
Begin
  Port[$61] := Port[$61] And $FC;
End;

Procedure Beep;
Begin
  Sound(880);
  WaitTicks(2);
  NoSound;
End;

Procedure StartupSound;
Begin
  Sound(523); WaitTicks(3);
  Sound(659); WaitTicks(3);
  Sound(784); WaitTicks(3);
  Sound(1047); WaitTicks(6);
  NoSound;
End;

{ ================================================================== }
{ CD-ROM ISO 9660 (INT 13h etendue)                                  }
{ ================================================================== }

Function CdRead(Lba : LongInt; BSeg : Word) : Boolean;
Var Drv, Err, Tries : Byte;
Begin
  Tries := 0;
  Repeat
    Dap.Size := 16; Dap.Res := 0; Dap.Count := 1;
    Dap.BufOfs := 0; Dap.BufSg := BSeg;
    Dap.LbaLo := Lba; Dap.LbaHi := 0;
    Drv := BootDrive;
    asm
      push si
      mov ah,42h
      mov dl,Drv
      lea si,Dap
      int 13h
      mov al,0
      adc al,0
      mov Err,al
      pop si
    end;
    If Err = 0 Then
    Begin
      CdRead := True;
      Exit;
    End;
    asm
      xor ah,ah
      mov dl,Drv
      int 13h
    end;
    Inc(Tries);
  Until Tries >= 3;
  CdRead := False;
End;

Function GetD(Seg, Ofs : Word) : LongInt;
Begin
  GetD := LongInt(MemW[Seg:Ofs]) + LongInt(MemW[Seg:Ofs + 2]) * 65536;
End;

{ Lire le descripteur de volume et le repertoire racine }
Procedure CdScan;
Var Sector, NSect : LongInt; Ofs, RecLen, NLen, K : Word;
    Name : String; C : Char;
Begin
  CdOk := False; CdCount := 0; VolLabel := '';
  If Not CdRead(16, CdSeg) Then Exit;
  If (Mem[CdSeg:0] <> 1) Or (Mem[CdSeg:1] <> Ord('C')) Then Exit;
  RootLba := GetD(CdSeg, 156 + 2);
  RootSize := GetD(CdSeg, 156 + 10);
  For K := 0 To 31 Do VolLabel := VolLabel + Chr(Mem[CdSeg:40 + K]);
  VolLabel := Trim(VolLabel);
  CdOk := True;
  NSect := (RootSize + 2047) Div 2048;
  Sector := 0;
  While (Sector < NSect) And (CdCount < CdMax) Do
  Begin
    If Not CdRead(RootLba + Sector, CdSeg) Then Exit;
    Ofs := 0;
    While Ofs < 2048 Do
    Begin
      RecLen := Mem[CdSeg:Ofs];
      If RecLen = 0 Then Ofs := 2048
      Else
      Begin
        NLen := Mem[CdSeg:Ofs + 32];
        If (NLen > 1) Or (Mem[CdSeg:Ofs + 33] > 1) Then
        Begin
          Name := '';
          K := 0;
          While K < NLen Do
          Begin
            C := Chr(Mem[CdSeg:Ofs + 33 + K]);
            If C = ';' Then K := NLen
            Else Name := Name + UpCase(C);
            Inc(K);
          End;
          If (Length(Name) > 0) And (Name[Length(Name)] = '.') Then
            Delete(Name, Length(Name), 1);
          If CdCount < CdMax Then
          Begin
            CdFiles[CdCount].Name := Copy(Name, 1, 12);
            CdFiles[CdCount].Lba := GetD(CdSeg, Ofs + 2);
            CdFiles[CdCount].Size := GetD(CdSeg, Ofs + 10);
            CdFiles[CdCount].Yr := Mem[CdSeg:Ofs + 18];
            CdFiles[CdCount].Mo := Mem[CdSeg:Ofs + 19];
            CdFiles[CdCount].Dy := Mem[CdSeg:Ofs + 20];
            CdFiles[CdCount].Hr := Mem[CdSeg:Ofs + 21];
            CdFiles[CdCount].Mi := Mem[CdSeg:Ofs + 22];
            CdFiles[CdCount].Dir := (Mem[CdSeg:Ofs + 25] And 2) <> 0;
            Inc(CdCount);
          End;
        End;
        Ofs := Ofs + RecLen;
      End;
    End;
    Inc(Sector);
  End;
End;

Function CdFind(Name : String) : Integer;
Var I : Integer;
Begin
  CdFind := -1;
  Name := UpStr(Name);
  For I := 0 To CdCount - 1 Do
    If CdFiles[I].Name = Name Then
    Begin
      CdFind := I;
      Exit;
    End;
End;

{ Charger un fichier du CD-ROM en Seg:0000 (au plus MaxLen octets) ;
  retourne le nombre d'octets lus }
Function CdLoad(Idx : Integer; Seg : Word; MaxLen : LongInt) : Word;
Var N, Sector, NSect : LongInt;
Begin
  CdLoad := 0;
  If (Idx < 0) Or (Idx >= CdCount) Then Exit;
  N := CdFiles[Idx].Size;
  If N > MaxLen Then N := MaxLen;
  NSect := (N + 2047) Div 2048;
  Sector := 0;
  While Sector < NSect Do
  Begin
    If Not CdRead(CdFiles[Idx].Lba + Sector, Seg + Word(Sector) * 128) Then
    Begin
      CdLoad := Word(Sector * 2048);
      Exit;
    End;
    Inc(Sector);
  End;
  CdLoad := Word(N);
End;

Function IsTextFile(Const Name : String) : Boolean;
Var E : String; P : Integer;
Begin
  P := Pos('.', Name);
  If P = 0 Then E := '' Else E := Copy(Name, P + 1, 3);
  IsTextFile := (E = 'TXT') Or (E = 'BAT') Or (E = 'INI') Or
                (E = 'DOC') Or (E = 'PAS') Or (E = 'LOG') Or
                (Name = 'CONFIG.SYS') Or (Name = 'MSDOS.SYS');
End;

Function OptOn(Const V : String) : Boolean;
Begin
  OptOn := (V = '1') Or (V = 'YES') Or (V = 'ON') Or (V = 'TRUE');
End;

{ Options de demarrage de MSDOS.SYS (section [Options], comme sous
  Windows 95) : BootMenu=1, BootGUI=0, Logo=0, BootDelay=n }
Procedure ReadMsdosSys;
Var I, N, P, E : Integer; Line, K, V : String; C : Char;
Begin
  OptBootMenu := False; OptBootGUI := True; OptLogo := True;
  OptBootDelay := 2;
  I := CdFind('MSDOS.SYS');
  If I < 0 Then Exit;
  N := CdLoad(I, TmpSeg, TmpMax);
  Line := '';
  For P := 0 To N Do
  Begin
    If P < N Then C := Chr(Mem[TmpSeg:P]) Else C := #10;
    If (C = #10) Or (C = #13) Then
    Begin
      Line := UpStr(Trim(Line));
      If (Pos('=', Line) > 0) And (Line[1] <> ';') Then
      Begin
        K := Trim(Copy(Line, 1, Pos('=', Line) - 1));
        V := Trim(Copy(Line, Pos('=', Line) + 1, 255));
        If K = 'BOOTMENU' Then OptBootMenu := OptOn(V)
        Else If K = 'BOOTGUI' Then OptBootGUI := OptOn(V)
        Else If K = 'LOGO' Then OptLogo := OptOn(V)
        Else If K = 'BOOTDELAY' Then
        Begin
          Val(V, OptBootDelay, E);
          If (E <> 0) Or (OptBootDelay < 0) Then OptBootDelay := 2;
          If OptBootDelay > 30 Then OptBootDelay := 30;
        End;
      End;
      Line := '';
    End
    Else If (C <> #26) And (Length(Line) < 250) Then Line := Line + C;
  End;
End;

{ Executer les commandes SET de AUTOEXEC.BAT }
Procedure ReadAutoexec;
Var I, N, P : Integer; Line, U : String; C : Char;
Begin
  I := CdFind('AUTOEXEC.BAT');
  If I < 0 Then Exit;
  N := CdLoad(I, TmpSeg, TmpMax);
  Line := '';
  For P := 0 To N Do
  Begin
    If P < N Then C := Chr(Mem[TmpSeg:P]) Else C := #10;
    If (C = #10) Or (C = #13) Then
    Begin
      Line := Trim(Line);
      U := UpStr(Line);
      If Copy(U, 1, 4) = 'SET ' Then
      Begin
        Line := Trim(Copy(Line, 5, 255));
        If Pos('=', Line) > 0 Then
          SetEnv(Copy(Line, 1, Pos('=', Line) - 1),
                 Trim(Copy(Line, Pos('=', Line) + 1, 255)));
      End;
      Line := '';
    End
    Else If (C <> #26) And (Length(Line) < 250) Then Line := Line + C;
  End;
End;

{ ================================================================== }
{ Video VGA 640x480 en 16 couleurs (mode 12h, mode d'ecriture 2)     }
{ ================================================================== }

Procedure GcSet(Idx, Val : Byte);
Begin
  Port[$3CE] := Idx;
  Port[$3CF] := Val;
End;

Procedure SeqSet(Idx, Val : Byte);
Begin
  Port[$3C4] := Idx;
  Port[$3C5] := Val;
End;

{ Etat normal des registres : mode d'ecriture 2, remplacement }
Procedure VgaNormal;
Begin
  GcSet(1, 0);
  GcSet(3, 0);
  GcSet(5, 2);
  GcSet(8, $FF);
  SeqSet(2, $0F);
End;

Procedure SetPalette;
Var I : Integer; R, G, B : Byte; Idx : Byte;
Begin
  For I := 0 To 15 Do
  Begin
    Idx := I;
    asm
      mov ax,1000h
      mov bl,Idx
      mov bh,Idx
      int 10h
    end;
    R := PalR[I]; G := PalG[I]; B := PalB[I];
    asm
      mov ax,1010h
      mov bl,Idx
      xor bh,bh
      mov dh,R
      mov ch,G
      mov cl,B
      int 10h
    end;
  End;
End;

Procedure GraphMode;
Var FSg, FOf : Word;
Begin
  asm
    mov ax,0012h
    int 10h
    push bp
    push es
    mov ax,1130h
    mov bh,6
    int 10h
    mov ax,es
    mov dx,bp
    pop es
    pop bp
    mov FSg,ax
    mov FOf,dx
  end;
  FontSeg := FSg; FontOfs := FOf;
  SetPalette;
  VgaNormal;
  GuiOn := True;
End;

Procedure TextMode;
Begin
  asm
    mov ax,0003h
    int 10h
  end;
  GuiOn := False;
End;

Procedure FullClip;
Begin
  ClipX1 := 0; ClipY1 := 0; ClipX2 := ScrW - 1; ClipY2 := ScrH - 1;
End;

{ Decoupage = zone a redessiner inter (X1,Y1)-(X2,Y2) }
Procedure SetClip(X1, Y1, X2, Y2 : Integer);
Begin
  ClipX1 := Max(X1, AreaX1); ClipY1 := Max(Y1, AreaY1);
  ClipX2 := Min(X2, AreaX2); ClipY2 := Min(Y2, AreaY2);
End;

Procedure SetArea(X1, Y1, X2, Y2 : Integer);
Begin
  AreaX1 := Max(X1, 0); AreaY1 := Max(Y1, 0);
  AreaX2 := Min(X2, ScrW - 1); AreaY2 := Min(Y2, ScrH - 1);
  ClipX1 := AreaX1; ClipY1 := AreaY1;
  ClipX2 := AreaX2; ClipY2 := AreaY2;
End;

Function ClipEmpty : Boolean;
Begin
  ClipEmpty := (ClipX1 > ClipX2) Or (ClipY1 > ClipY2);
End;

{ Rectangle plein, decoupe }
Procedure Bar(X1, Y1, X2, Y2 : Integer; C : Byte);
Var L, R, Y, N : Integer; O : Word; LM, RM, D : Byte;
Begin
  If X1 < ClipX1 Then X1 := ClipX1;
  If Y1 < ClipY1 Then Y1 := ClipY1;
  If X2 > ClipX2 Then X2 := ClipX2;
  If Y2 > ClipY2 Then Y2 := ClipY2;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  L := X1 Shr 3; R := X2 Shr 3;
  LM := $FF Shr (X1 And 7);
  RM := Byte($FF Shl (7 - (X2 And 7)));
  If L = R Then
  Begin
    GcSet(8, LM And RM);
    O := Word(Y1) * 80 + Word(L);
    For Y := Y1 To Y2 Do
    Begin
      D := Mem[VSeg:O]; Mem[VSeg:O] := C;
      O := O + 80;
    End;
    GcSet(8, $FF);
    Exit;
  End;
  GcSet(8, LM);
  O := Word(Y1) * 80 + Word(L);
  For Y := Y1 To Y2 Do
  Begin
    D := Mem[VSeg:O]; Mem[VSeg:O] := C;
    O := O + 80;
  End;
  GcSet(8, RM);
  O := Word(Y1) * 80 + Word(R);
  For Y := Y1 To Y2 Do
  Begin
    D := Mem[VSeg:O]; Mem[VSeg:O] := C;
    O := O + 80;
  End;
  GcSet(8, $FF);
  N := R - L - 1;
  If N > 0 Then
  Begin
    O := Word(Y1) * 80 + Word(L + 1);
    For Y := Y1 To Y2 Do
    Begin
      asm
        push es
        push di
        mov ax,0A000h
        mov es,ax
        mov di,O
        mov cx,N
        mov al,C
        cld
        rep stosb
        pop di
        pop es
      end;
      O := O + 80;
    End;
  End;
End;

Procedure HLine(X1, X2, Y : Integer; C : Byte);
Begin
  Bar(X1, Y, X2, Y, C);
End;

Procedure VLine(X, Y1, Y2 : Integer; C : Byte);
Begin
  Bar(X, Y1, X, Y2, C);
End;

Procedure Pix(X, Y : Integer; C : Byte);
Var O : Word; D : Byte;
Begin
  If (X < ClipX1) Or (X > ClipX2) Or (Y < ClipY1) Or (Y > ClipY2) Then
    Exit;
  O := Word(Y) * 80 + Word(X) Shr 3;
  GcSet(8, $80 Shr (X And 7));
  D := Mem[VSeg:O]; Mem[VSeg:O] := C;
End;

Procedure Box(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  HLine(X1, X2, Y1, C); HLine(X1, X2, Y2, C);
  VLine(X1, Y1, Y2, C); VLine(X2, Y1, Y2, C);
End;

Procedure Line(X1, Y1, X2, Y2 : Integer; C : Byte);
Var DX, DY, SX, SY, E, E2 : Integer;
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

Function ISqrt(V : LongInt) : Integer;
Var R : LongInt;
Begin
  R := 0;
  While (R + 1) * (R + 1) <= V Do Inc(R);
  ISqrt := R;
End;

Procedure Disc(CX, CY, R : Integer; C : Byte);
Var DY, DX : Integer;
Begin
  For DY := -R To R Do
  Begin
    DX := ISqrt(LongInt(R) * R - LongInt(DY) * DY);
    HLine(CX - DX, CX + DX, CY + DY, C);
  End;
End;

Procedure Circle(CX, CY, R : Integer; C : Byte);
Var DY, DX, PX : Integer;
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
Procedure Dither(X1, Y1, X2, Y2 : Integer; C : Byte; Phase : Integer);
Var Y, X : Integer; O : Word; D, M : Byte;
Begin
  If X1 < ClipX1 Then X1 := ClipX1;
  If Y1 < ClipY1 Then Y1 := ClipY1;
  If X2 > ClipX2 Then X2 := ClipX2;
  If Y2 > ClipY2 Then Y2 := ClipY2;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  For Y := Y1 To Y2 Do
  Begin
    If Odd(Y + Phase) Then M := $AA Else M := $55;
    X := X1;
    While X <= X2 Do
    Begin
      D := $FF Shr (X And 7);
      If (X Or 7) > X2 Then D := D And Byte($FF Shl (7 - (X2 And 7)));
      GcSet(8, D And M);
      O := Word(Y) * 80 + Word(X) Shr 3;
      D := Mem[VSeg:O]; Mem[VSeg:O] := C;
      X := (X Or 7) + 1;
    End;
  End;
  GcSet(8, $FF);
End;

{ Ligne en OU exclusif (contour de deplacement des fenetres) }
Procedure XorBar(X1, Y1, X2, Y2 : Integer);
Var Y, X : Integer; O : Word; D : Byte;
Begin
  If X1 < 0 Then X1 := 0;
  If Y1 < 0 Then Y1 := 0;
  If X2 > ScrW - 1 Then X2 := ScrW - 1;
  If Y2 > ScrH - 1 Then Y2 := ScrH - 1;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  GcSet(3, $18);
  For Y := Y1 To Y2 Do
  Begin
    X := X1;
    While X <= X2 Do
    Begin
      D := $FF Shr (X And 7);
      If (X Or 7) > X2 Then D := D And Byte($FF Shl (7 - (X2 And 7)));
      GcSet(8, D);
      O := Word(Y) * 80 + Word(X) Shr 3;
      D := Mem[VSeg:O]; Mem[VSeg:O] := 15;
      X := (X Or 7) + 1;
    End;
  End;
  GcSet(3, 0);
  GcSet(8, $FF);
End;

Procedure XorFrame(X1, Y1, X2, Y2 : Integer);
Begin
  XorBar(X1, Y1, X2, Y1 + 2);
  XorBar(X1, Y2 - 2, X2, Y2);
  XorBar(X1, Y1 + 3, X1 + 2, Y2 - 3);
  XorBar(X2 - 2, Y1 + 3, X2, Y2 - 3);
End;

{ ------------------------------------------------------------------ }
{ Texte (police 8x16 du BIOS video)                                  }
{ ------------------------------------------------------------------ }

Procedure DrawChar(X, Y : Integer; Ch : Char; C : Byte);
Var R, Sh, CX : Integer; O, F : Word; B, M, D : Byte;
Begin
  If (X > ClipX2) Or (X + 7 < ClipX1) Or (Y > ClipY2) Or
     (Y + 15 < ClipY1) Then Exit;
  F := FontOfs + Word(Ord(Ch)) * 16;
  If (X >= ClipX1) And (X + 7 <= ClipX2) And (Y >= ClipY1) And
     (Y + 15 <= ClipY2) Then
  Begin
    O := Word(Y) * 80 + Word(X) Shr 3; Sh := X And 7;
    For R := 0 To 15 Do
    Begin
      B := Mem[FontSeg:F + R];
      If B <> 0 Then
      Begin
        M := B Shr Sh;
        If M <> 0 Then
        Begin
          GcSet(8, M); D := Mem[VSeg:O]; Mem[VSeg:O] := C;
        End;
        If Sh <> 0 Then
        Begin
          M := Byte(B Shl (8 - Sh));
          If M <> 0 Then
          Begin
            GcSet(8, M); D := Mem[VSeg:O + 1]; Mem[VSeg:O + 1] := C;
          End;
        End;
      End;
      O := O + 80;
    End;
    GcSet(8, $FF);
    Exit;
  End;
  For R := 0 To 15 Do
  Begin
    B := Mem[FontSeg:F + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then Pix(X + CX, Y + R, C);
  End;
  GcSet(8, $FF);
End;

Procedure OutText(X, Y : Integer; Const S : String; C : Byte);
Var K : Integer;
Begin
  For K := 1 To Length(S) Do
  Begin
    If S[K] <> ' ' Then DrawChar(X, Y, S[K], C);
    X := X + 8;
  End;
End;

Procedure OutBold(X, Y : Integer; Const S : String; C : Byte);
Begin
  OutText(X, Y, S, C);
  OutText(X + 1, Y, S, C);
End;

Function TextW(Const S : String) : Integer;
Begin
  TextW := Length(S) * 8;
End;

{ Texte centre entre X1 et X2 }
Procedure OutCenter(X1, X2, Y : Integer; Const S : String; C : Byte);
Begin
  OutText(X1 + (X2 - X1 + 1 - TextW(S)) Div 2, Y, S, C);
End;

{ Texte tronque a MaxW pixels (avec ...) }
Function Fit(Const S : String; MaxW : Integer) : String;
Var N : Integer;
Begin
  N := MaxW Div 8;
  If N < 0 Then N := 0;
  If Length(S) <= N Then Fit := S
  Else If N > 3 Then Fit := Copy(S, 1, N - 3) + '...'
  Else Fit := Copy(S, 1, N);
End;

{ Caractere agrandi (Scale x Scale par point) }
Procedure BigChar(X, Y : Integer; Ch : Char; C : Byte; Sc : Integer);
Var R, CX : Integer; B : Byte;
Begin
  For R := 0 To 15 Do
  Begin
    B := Mem[FontSeg:FontOfs + Word(Ord(Ch)) * 16 + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then
        Bar(X + CX * Sc, Y + R * Sc, X + CX * Sc + Sc - 1,
            Y + R * Sc + Sc - 1, C);
  End;
End;

Procedure BigText(X, Y : Integer; Const S : String; C : Byte;
                  Sc : Integer);
Var K : Integer;
Begin
  For K := 1 To Length(S) Do
    BigChar(X + (K - 1) * 8 * Sc, Y, S[K], C, Sc);
End;

{ Texte avec retour a la ligne automatique ; retourne le nombre de
  lignes. Draw = False : seulement compter }
Function WrapText(X, Y, W : Integer; Const S : String; C : Byte;
                  Draw : Boolean) : Integer;
Var Cols, I, N, Last : Integer; Line, Word0 : String;
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
          If Draw Then OutText(X, Y + N * 16, Line, C);
          Inc(N);
        End;
        Line := Word0;
      End
      Else If Line = '' Then Line := Word0
      Else Line := Line + ' ' + Word0;
      Word0 := '';
      If (I <= Length(S)) And (S[I] = '|') Then
      Begin
        If Draw Then OutText(X, Y + N * 16, Line, C);
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
    If Draw Then OutText(X, Y + N * 16, Line, C);
    Inc(N);
  End;
  Last := N;
  WrapText := Last;
End;

{ ------------------------------------------------------------------ }
{ Reliefs de Windows 95                                              }
{ ------------------------------------------------------------------ }

Procedure Edge(X1, Y1, X2, Y2 : Integer; TL, BR : Byte);
Begin
  HLine(X1, X2 - 1, Y1, TL);
  VLine(X1, Y1, Y2 - 1, TL);
  HLine(X1, X2, Y2, BR);
  VLine(X2, Y1, Y2, BR);
End;

{ Bouton en relief (ou enfonce) }
Procedure Raised(X1, Y1, X2, Y2 : Integer; Pressed : Boolean);
Begin
  Bar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, cSilver);
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
Procedure Sunken(X1, Y1, X2, Y2 : Integer; Fill : Byte);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cBlack, cSilver);
  Bar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, Fill);
End;

{ Cadre grave (groupe d'options) }
Procedure GroupBox(X1, Y1, X2, Y2 : Integer; Const Title : String);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cWhite, cGray);
  If Title <> '' Then
  Begin
    Bar(X1 + 6, Y1 - 7, X1 + 9 + TextW(Title), Y1 + 8, cSilver);
    OutText(X1 + 8, Y1 - 7, Title, cBlack);
  End;
End;

Procedure PushButton(X1, Y1, X2, Y2 : Integer; Const S : String;
                     Pressed, Def : Boolean);
Var D : Integer;
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

Procedure RadioButton(X, Y : Integer; Const S : String; On : Boolean);
Begin
  Circle(X + 6, Y + 7, 6, cGray);
  Disc(X + 6, Y + 7, 4, cWhite);
  HLine(X + 3, X + 9, Y + 13, cWhite);
  VLine(X + 12, Y + 4, Y + 10, cWhite);
  If On Then Disc(X + 6, Y + 7, 2, cBlack);
  OutText(X + 18, Y, S, cBlack);
End;

{ Petit triangle (fleche) : Dir 0 droite, 1 bas, 2 haut }
Procedure Arrow(X, Y, Dir : Integer; C : Byte);
Var I : Integer;
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
{ Curseur de la souris (dessine par logiciel)                        }
{ ------------------------------------------------------------------ }

Procedure HideCursor;
Var P, R, B, BX : Integer; O : Word;
Begin
  If Not CurShown Then Exit;
  CurShown := False;
  GcSet(5, 0); GcSet(8, $FF);
  BX := CurX Shr 3;
  For P := 0 To 3 Do
  Begin
    SeqSet(2, 1 Shl P);
    For R := 0 To CurH - 1 Do
      If CurY + R < ScrH Then
      Begin
        O := Word(CurY + R) * 80 + Word(BX);
        For B := 0 To 2 Do
          If BX + B < 80 Then Mem[VSeg:O + B] := CurSave[P, R, B];
      End;
  End;
  VgaNormal;
End;

Procedure ShowCursor;
Var P, R, B, BX, I : Integer; O : Word;
    SX1, SY1, SX2, SY2 : Integer; Ch : Char;
Begin
  If CurShown Or Not GuiOn Then Exit;
  CurX := MouseX; CurY := MouseY;
  BX := CurX Shr 3;
  For P := 0 To 3 Do
  Begin
    GcSet(4, P);
    For R := 0 To CurH - 1 Do
      If CurY + R < ScrH Then
      Begin
        O := Word(CurY + R) * 80 + Word(BX);
        For B := 0 To 2 Do
          If BX + B < 80 Then CurSave[P, R, B] := Mem[VSeg:O + B];
      End;
  End;
  SX1 := ClipX1; SY1 := ClipY1; SX2 := ClipX2; SY2 := ClipY2;
  FullClip;
  For R := 0 To CurH - 1 Do
    For I := 1 To 12 Do
    Begin
      Ch := CurShape[R][I];
      If Ch = 'X' Then Pix(CurX + I - 1, CurY + R, cBlack)
      Else If Ch = 'W' Then Pix(CurX + I - 1, CurY + R, cWhite);
    End;
  GcSet(8, $FF);
  ClipX1 := SX1; ClipY1 := SY1; ClipX2 := SX2; ClipY2 := SY2;
  CurShown := True;
End;

{ ------------------------------------------------------------------ }
{ Icones (dessinees dans une grille de 32x32, mises a l'echelle S)   }
{ ------------------------------------------------------------------ }

Var
  IcX, IcY, IcS : Integer;

Function IcP(V : Integer) : Integer;
Begin
  IcP := V * IcS Div 32;
End;

Procedure QR(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  Bar(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2 + 1) - 1,
      IcY + IcP(Y2 + 1) - 1, C);
End;

Procedure QB(X1, Y1, X2, Y2 : Integer; C : Byte);
Var A, B, CC, D : Integer;
Begin
  A := IcX + IcP(X1); B := IcY + IcP(Y1);
  CC := IcX + IcP(X2 + 1) - 1; D := IcY + IcP(Y2 + 1) - 1;
  Box(A, B, CC, D, C);
End;

Procedure QL(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  Line(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2), IcY + IcP(Y2), C);
End;

Procedure QD(CX, CY, R : Integer; C : Byte);
Begin
  Disc(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

Procedure QC(CX, CY, R : Integer; C : Byte);
Begin
  Circle(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

{ Boite en relief (fond F, contour noir) }
Procedure IFrame(X1, Y1, X2, Y2 : Integer; F : Byte);
Begin
  QR(X1, Y1, X2, Y2, F);
  QB(X1, Y1, X2, Y2, cBlack);
End;

Procedure IconMonitor(Screen : Byte);
Begin
  IFrame(4, 2, 27, 21, cSilver);
  QR(5, 3, 26, 3, cWhite);
  IFrame(7, 5, 24, 17, Screen);
  IFrame(11, 22, 20, 24, cSilver);
End;

Procedure IconFolder(C : Byte);
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

Procedure DrawIcon(Id, X, Y, S : Integer);
Var I : Integer;
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

{ ================================================================== }
{ Gestionnaire de fenetres                                           }
{ ================================================================== }

Procedure RedrawArea(X1, Y1, X2, Y2 : Integer); Forward;
Procedure Execute(Cmd : Integer); Forward;
Procedure DrawClient(K : Integer); Forward;

Function TopWin : Integer;
Var I : Integer;
Begin
  TopWin := 0;
  For I := ZCnt - 1 DownTo 0 Do
    If Not Wins[ZOrd[I]].Min Then
    Begin
      TopWin := ZOrd[I];
      Exit;
    End;
End;

Function IsDialog(K : Integer) : Boolean;
Begin
  IsDialog := (K = wkDisplay) Or (K = wkRegional) Or (K = wkSystem) Or
              (K = wkAbout) Or (K = wkRun) Or (K = wkShutdown) Or
              (K = wkMsg) Or (K = wkWelcome) Or (K = wkDateTime);
End;

Function IsModal(K : Integer) : Boolean;
Begin
  IsModal := (K = wkMsg) Or (K = wkShutdown);
End;

Function CanMax(K : Integer) : Boolean;
Begin
  CanMax := Not IsDialog(K) And (K <> wkCalc);
End;

Function NoteTitle : String;
Begin
  If NoteName = '' Then
    NoteTitle := L('Sans titre', 'Untitled', 'Unbenannt', 'Senza nome',
                   'Sin t'#161'tulo')
  Else
    NoteTitle := NoteName;
End;

Function DriveLabel : String;
Begin
  If VolLabel = '' Then DriveLabel := 'CD-ROM (D:)'
  Else DriveLabel := VolLabel + ' (D:)';
End;

Function CtlName(I : Integer) : String;
Begin
  Case I Of
    0 : CtlName := L('Affichage', 'Display', 'Anzeige', 'Schermo',
                     'Pantalla');
    1 : CtlName := L('Date/Heure', 'Date/Time', 'Datum/Uhrzeit',
                     'Data/Ora', 'Fecha/Hora');
    2 : CtlName := L('Param'#138'tres r'#130'gionaux', 'Regional Settings',
                     'L'#132'ndereinstellungen', 'Impostazioni internazionali',
                     'Configuraci'#162'n regional');
  Else
    CtlName := L('Syst'#138'me', 'System', 'System', 'Sistema', 'Sistema');
  End;
End;

Function WinTitle(K : Integer) : String;
Begin
  Case K Of
    wkExplorer :
      If ExpView = 0 Then
        WinTitle := L('Poste de travail', 'My Computer', 'Arbeitsplatz',
                      'Risorse del computer', 'Mi PC')
      Else
        WinTitle := DriveLabel;
    wkNotepad : WinTitle := NoteTitle + ' - ' +
                L('Bloc-notes', 'Notepad', 'Editor', 'Blocco note',
                  'Bloc de notas');
    wkCalc : WinTitle := L('Calculatrice', 'Calculator', 'Rechner',
                           'Calcolatrice', 'Calculadora');
    wkDos : WinTitle := L('Invite MS-DOS', 'MS-DOS Prompt',
                          'MS-DOS-Eingabeaufforderung', 'Prompt di MS-DOS',
                          'S'#161'mbolo del sistema');
    wkControl : WinTitle := L('Panneau de configuration', 'Control Panel',
                              'Systemsteuerung', 'Pannello di controllo',
                              'Panel de control');
    wkDisplay : WinTitle := L('Propri'#130't'#130's de Affichage',
                              'Display Properties', 'Eigenschaften von Anzeige',
                              'Propriet'#133' - Schermo',
                              'Propiedades de Pantalla');
    wkRegional : WinTitle := L('Param'#138'tres r'#130'gionaux',
                               'Regional Settings',
                               'L'#132'ndereinstellungen', 'Internazionale',
                               'Configuraci'#162'n regional');
    wkSystem : WinTitle := L('Propri'#130't'#130's Syst'#138'me',
                             'System Properties',
                             'Eigenschaften von System',
                             'Propriet'#133' - Sistema',
                             'Propiedades del Sistema');
    wkAbout : WinTitle := L('A propos de Pasdows 95', 'About Pasdows 95',
                            'Info '#129'ber Pasdows 95',
                            'Informazioni su Pasdows 95',
                            'Acerca de Pasdows 95');
    wkRun : WinTitle := L('Ex'#130'cuter', 'Run', 'Ausf'#129'hren', 'Esegui',
                          'Ejecutar');
    wkShutdown : WinTitle := L('Arr'#136'ter Pasdows', 'Shut Down Pasdows',
                               'Pasdows beenden', 'Chiudi sessione',
                               'Apagar Pasdows');
    wkRecycle : WinTitle := L('Corbeille', 'Recycle Bin', 'Papierkorb',
                              'Cestino', 'Papelera de reciclaje');
    wkHelp : WinTitle := L('Aide de Pasdows', 'Pasdows Help',
                           'Pasdows-Hilfe', 'Guida di Pasdows',
                           'Ayuda de Pasdows');
    wkMsg : WinTitle := MsgTitle;
    wkWelcome : WinTitle := L('Bienvenue', 'Welcome', 'Willkommen',
                              'Benvenuti', 'Bienvenido');
    wkPaint : WinTitle := L('sans titre - Paint', 'untitled - Paint',
                            'Unbenannt - Paint', 'Senza nome - Paint',
                            'sin t'#161'tulo - Paint');
    wkDateTime : WinTitle := L('Propri'#130't'#130's de Date/Heure',
                               'Date/Time Properties',
                               'Eigenschaften von Datum/Uhrzeit',
                               'Propriet'#133' - Data/Ora',
                               'Propiedades de Fecha y hora');
  Else
    WinTitle := '';
  End;
End;

Function WinIcon(K : Integer) : Integer;
Begin
  Case K Of
    wkExplorer : If ExpView = 0 Then WinIcon := icComputer
                 Else WinIcon := icCdrom;
    wkNotepad : WinIcon := icNotepad;
    wkCalc : WinIcon := icCalc;
    wkDos : WinIcon := icDos;
    wkControl : WinIcon := icControl;
    wkDisplay : WinIcon := icDisplay;
    wkRegional : WinIcon := icRegional;
    wkSystem : WinIcon := icSystem;
    wkRun : WinIcon := icRun;
    wkShutdown : WinIcon := icShutdown;
    wkRecycle : WinIcon := icRecycle;
    wkHelp : WinIcon := icHelp;
    wkPaint : WinIcon := icPaint;
    wkDateTime : WinIcon := icClock;
  Else
    WinIcon := icLogo;
  End;
End;

{ Barre de menus des applications }
Function MenuBarCount(K : Integer) : Integer;
Begin
  Case K Of
    wkNotepad : MenuBarCount := 3;
    wkExplorer, wkPaint, wkRecycle : MenuBarCount := 2;
    wkCalc : MenuBarCount := 1;
  Else
    MenuBarCount := 0;
  End;
End;

Procedure MenuBarItem(K, I : Integer; Var T : String; Var M : Integer);
Begin
  If I = MenuBarCount(K) - 1 Then
  Begin
    T := '?'; M := mnHelp;
    Exit;
  End;
  If (I = 0) And (K = wkNotepad) Then M := mnNoteFile;
  If (I = 0) And (K = wkExplorer) Then M := mnExpFile;
  If (I = 0) And (K = wkPaint) Then M := mnPaintFile;
  If (I = 0) And (K = wkRecycle) Then M := mnBinFile;
  T := L('Fichier', 'File', 'Datei', 'File', 'Archivo');
  If I = 1 Then
  Begin
    T := L(#144'dition', 'Edit', 'Bearbeiten', 'Modifica', 'Edici'#162'n');
    M := mnNoteEdit;
  End;
End;

Function MenuBarX(K, I : Integer) : Integer;
Var J, X, M : Integer; T : String;
Begin
  X := Wins[K].X + 6;
  For J := 0 To I - 1 Do
  Begin
    MenuBarItem(K, J, T, M);
    X := X + TextW(T) + 14;
  End;
  MenuBarX := X;
End;

{ Zone client (sous la barre de titre et la barre de menus) }
Procedure ClientRect(K : Integer; Var X1, Y1, X2, Y2 : Integer);
Begin
  X1 := Wins[K].X + 4;
  Y1 := Wins[K].Y + 23;
  X2 := Wins[K].X + Wins[K].W - 5;
  Y2 := Wins[K].Y + Wins[K].H - 5;
  If MenuBarCount(K) > 0 Then Y1 := Y1 + 19;
End;

{ Boutons de la barre de titre : 0 fermer, 1 agrandir, 2 reduire }
Procedure CapButton(K, B : Integer; Var X1, Y1, X2, Y2 : Integer);
Begin
  X2 := Wins[K].X + Wins[K].W - 7;
  Y1 := Wins[K].Y + 6;
  Y2 := Y1 + 13;
  If B >= 1 Then X2 := X2 - 18;
  If B >= 2 Then X2 := X2 - 16;
  X1 := X2 - 15;
End;

Function CapButtons(K : Integer) : Integer;
Begin
  If IsDialog(K) Then CapButtons := 1 Else CapButtons := 3;
End;

Procedure DrawCapButton(K, B : Integer; Pressed : Boolean);
Var X1, Y1, X2, Y2, D, I : Integer; C : Byte;
Begin
  CapButton(K, B, X1, Y1, X2, Y2);
  Raised(X1, Y1, X2, Y2, Pressed);
  If Pressed Then D := 1 Else D := 0;
  X1 := X1 + D; Y1 := Y1 + D;
  Case B Of
    0 :
      For I := 0 To 6 Do
      Begin
        Pix(X1 + 4 + I, Y1 + 3 + I, cBlack);
        Pix(X1 + 5 + I, Y1 + 3 + I, cBlack);
        Pix(X1 + 10 - I, Y1 + 3 + I, cBlack);
        Pix(X1 + 11 - I, Y1 + 3 + I, cBlack);
      End;
    1 :
    Begin
      If CanMax(K) Then C := cBlack Else C := cGray;
      If Wins[K].Max Then
      Begin
        Box(X1 + 6, Y1 + 2, X1 + 11, Y1 + 6, C);
        HLine(X1 + 6, X1 + 11, Y1 + 3, C);
        Bar(X1 + 3, Y1 + 5, X1 + 8, Y1 + 10, cSilver);
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
    Bar(X1 + 4, Y1 + 9, X1 + 9, Y1 + 10, cBlack);
  End;
End;

Procedure DrawMenuBar(K : Integer);
Var I, X, M, Y : Integer; T : String;
Begin
  Y := Wins[K].Y + 23;
  Bar(Wins[K].X + 4, Y, Wins[K].X + Wins[K].W - 5, Y + 18, cSilver);
  For I := 0 To MenuBarCount(K) - 1 Do
  Begin
    MenuBarItem(K, I, T, M);
    X := MenuBarX(K, I);
    If (MenuDepth > 0) And (MenuOwner = K) And (Menus[0].Id = M) Then
    Begin
      Edge(X, Y + 1, X + TextW(T) + 11, Y + 17, cGray, cWhite);
      OutText(X + 7, Y + 2, T, cBlack);
    End
    Else
      OutText(X + 6, Y + 1, T, cBlack);
  End;
End;

Procedure DrawWindow(K : Integer);
Var X, Y, W, H, X1, Y1, X2, Y2, B : Integer; Active : Boolean;
    Fg : Byte;
Begin
  X := Wins[K].X; Y := Wins[K].Y; W := Wins[K].W; H := Wins[K].H;
  SetClip(X, Y, X + W - 1, Y + H - 1);
  If ClipEmpty Then Exit;
  Active := K = TopWin;
  Edge(X, Y, X + W - 1, Y + H - 1, cSilver, cBlack);
  Edge(X + 1, Y + 1, X + W - 2, Y + H - 2, cWhite, cGray);
  Bar(X + 2, Y + 2, X + W - 3, Y + 3, cSilver);
  Bar(X + 2, Y + 4, X + 3, Y + H - 3, cSilver);
  Bar(X + W - 4, Y + 4, X + W - 3, Y + H - 3, cSilver);
  Bar(X + 2, Y + H - 4, X + W - 3, Y + H - 3, cSilver);
  Bar(X + 4, Y + 22, X + W - 5, Y + 22, cSilver);
  { barre de titre }
  If Active Then
  Begin
    Bar(X + 4, Y + 4, X + W - 5, Y + 21, cNavy);
    Fg := cWhite;
  End
  Else
  Begin
    Bar(X + 4, Y + 4, X + W - 5, Y + 21, cGray);
    Fg := cSilver;
  End;
  DrawIcon(WinIcon(K), X + 6, Y + 5, 16);
  OutBold(X + 25, Y + 5, Fit(WinTitle(K), W - 30 - 18 * CapButtons(K)),
          Fg);
  For B := 0 To CapButtons(K) - 1 Do
    DrawCapButton(K, B, (PressWin = K) And (PressBtn = -1 - B));
  If MenuBarCount(K) > 0 Then DrawMenuBar(K);
  ClientRect(K, X1, Y1, X2, Y2);
  SetClip(X1, Y1, X2, Y2);
  If Not ClipEmpty Then DrawClient(K);
End;

{ ------------------------------------------------------------------ }
{ Ouvrir, fermer, activer                                            }
{ ------------------------------------------------------------------ }

Procedure WinRedraw(K : Integer);
Begin
  If Wins[K].Open And Not Wins[K].Min Then
    RedrawArea(Wins[K].X, Wins[K].Y, Wins[K].X + Wins[K].W - 1,
               Wins[K].Y + Wins[K].H - 1);
End;

{ Redessiner une partie de la fenetre K : directement si elle est au
  premier plan (rien ne la recouvre), sinon par RedrawArea }
Procedure WinPartRedraw(K, X1, Y1, X2, Y2 : Integer);
Begin
  If Not Wins[K].Open Or Wins[K].Min Then Exit;
  If (K = TopWin) And (MenuDepth = 0) And (DragWin = 0) Then
  Begin
    HideCursor;
    SetArea(X1, Y1, X2, Y2);
    If (AreaX1 <= AreaX2) And (AreaY1 <= AreaY2) Then DrawWindow(K);
    SetArea(0, 0, ScrW - 1, ScrH - 1);
  End
  Else
    RedrawArea(X1, Y1, X2, Y2);
End;

Procedure ClientRedraw(K : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  If Not Wins[K].Open Or Wins[K].Min Then Exit;
  ClientRect(K, X1, Y1, X2, Y2);
  WinPartRedraw(K, X1, Y1, X2, Y2);
End;

Procedure TaskbarRedraw;
Begin
  RedrawArea(0, TaskY, ScrW - 1, ScrH - 1);
End;

Procedure ZRemove(K : Integer);
Var I, J : Integer;
Begin
  J := 0;
  For I := 0 To ZCnt - 1 Do
    If ZOrd[I] <> K Then
    Begin
      ZOrd[J] := ZOrd[I];
      Inc(J);
    End;
  ZCnt := J;
End;

Procedure Activate(K : Integer);
Var Old : Integer;
Begin
  Old := TopWin;
  ZRemove(K);
  ZOrd[ZCnt] := K;
  Inc(ZCnt);
  If Wins[K].Min Then Wins[K].Min := False;
  If (Old <> 0) And (Old <> K) Then WinRedraw(Old);
  WinRedraw(K);
  TaskbarRedraw;
End;

Procedure CenterWin(K, W, H : Integer);
Begin
  Wins[K].W := W; Wins[K].H := H;
  Wins[K].X := (ScrW - W) Div 2;
  Wins[K].Y := (TaskY - H) Div 2;
End;

Procedure PlaceWin(K, X, Y, W, H : Integer);
Begin
  Wins[K].X := X; Wins[K].Y := Y; Wins[K].W := W; Wins[K].H := H;
End;

Procedure OpenWin(K : Integer);
Begin
  If Wins[K].Open Then
  Begin
    Activate(K);
    Exit;
  End;
  Wins[K].Open := True;
  Wins[K].Min := False;
  Wins[K].Max := False;
  Case K Of
    wkExplorer : PlaceWin(K, 70, 40, 430, 310);
    wkNotepad : PlaceWin(K, 110, 46, 480, 330);
    wkCalc : PlaceWin(K, 230, 80, 262, 252);
    wkDos : PlaceWin(K, 40, 64, 520, 316);
    wkControl : PlaceWin(K, 140, 90, 380, 250);
    wkDisplay : CenterWin(K, 340, 340);
    wkRegional : CenterWin(K, 330, 270);
    wkSystem : CenterWin(K, 390, 290);
    wkAbout : CenterWin(K, 410, 262);
    wkRun : PlaceWin(K, 6, TaskY - 180, 370, 172);
    wkShutdown : CenterWin(K, 360, 206);
    wkRecycle : PlaceWin(K, 160, 110, 360, 240);
    wkHelp : PlaceWin(K, 90, 30, 460, 380);
    wkWelcome : CenterWin(K, 480, 290);
    wkPaint : PlaceWin(K, 170, 60, 310, 252);
    wkDateTime : CenterWin(K, 390, 300);
  End;
  If K = wkShutdown Then
  Begin
    { boite modale sur l'ecran assombri : ne redessiner qu'elle }
    ZRemove(K);
    ZOrd[ZCnt] := K;
    Inc(ZCnt);
    WinRedraw(K);
    Exit;
  End;
  If K <> wkMsg Then
  Begin
    TaskOrd[TaskCnt] := K;
    Inc(TaskCnt);
  End;
  Activate(K);
End;

Procedure CloseWin(K : Integer);
Var I, J, X1, Y1, X2, Y2 : Integer;
Begin
  If Not Wins[K].Open Then Exit;
  Wins[K].Open := False;
  ZRemove(K);
  J := 0;
  For I := 0 To TaskCnt - 1 Do
    If TaskOrd[I] <> K Then
    Begin
      TaskOrd[J] := TaskOrd[I];
      Inc(J);
    End;
  TaskCnt := J;
  If PressWin = K Then PressWin := 0;
  If Wins[K].Min Then
  Begin
    TaskbarRedraw;
    Exit;
  End;
  X1 := Wins[K].X; Y1 := Wins[K].Y;
  X2 := X1 + Wins[K].W - 1; Y2 := Y1 + Wins[K].H - 1;
  RedrawArea(X1, Y1, X2, Y2);
  I := TopWin;
  If I <> 0 Then WinRedraw(I);
  TaskbarRedraw;
End;

Procedure MinimizeWin(K : Integer);
Var I : Integer;
Begin
  If Wins[K].Min Then Exit;
  Wins[K].Min := True;
  RedrawArea(Wins[K].X, Wins[K].Y, Wins[K].X + Wins[K].W - 1,
             Wins[K].Y + Wins[K].H - 1);
  I := TopWin;
  If I <> 0 Then WinRedraw(I);
  TaskbarRedraw;
End;

Procedure ToggleMax(K : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  If Not CanMax(K) Then Exit;
  X1 := Wins[K].X; Y1 := Wins[K].Y;
  X2 := X1 + Wins[K].W - 1; Y2 := Y1 + Wins[K].H - 1;
  If Wins[K].Max Then
  Begin
    Wins[K].X := Wins[K].NX; Wins[K].Y := Wins[K].NY;
    Wins[K].W := Wins[K].NW; Wins[K].H := Wins[K].NH;
    Wins[K].Max := False;
    RedrawArea(X1, Y1, X2, Y2);
  End
  Else
  Begin
    Wins[K].NX := X1; Wins[K].NY := Y1;
    Wins[K].NW := Wins[K].W; Wins[K].NH := Wins[K].H;
    Wins[K].X := -2; Wins[K].Y := -2;
    Wins[K].W := ScrW + 4; Wins[K].H := TaskY + 4;
    Wins[K].Max := True;
    WinRedraw(K);
  End;
End;

{ Boite de message }
Procedure MessageBox(Const Title, Text : String; Icon : Integer);
Var N : Integer;
Begin
  If Wins[wkMsg].Open Then CloseWin(wkMsg);
  MsgTitle := Title; MsgText := Text; MsgIcon := Icon;
  N := WrapText(0, 0, 280, Text, 0, False);
  If N < 2 Then N := 2;
  CenterWin(wkMsg, 380, 100 + N * 16);
  Wins[wkMsg].Open := True;
  Wins[wkMsg].Min := False;
  Wins[wkMsg].Max := False;
  Activate(wkMsg);
  Beep;
End;

Function AppName : String;
Begin
  AppName := 'Pasdows';
End;

{ ------------------------------------------------------------------ }
{ Barre des taches                                                   }
{ ------------------------------------------------------------------ }

Function StartText : String;
Begin
  StartText := L('D'#130'marrer', 'Start', 'Start', 'Avvio', 'Inicio');
End;

Function StartW : Integer;
Begin
  StartW := TextW(StartText) + 30;
End;

Function TrayX : Integer;
Begin
  TrayX := ScrW - 4 - (TextW(TimeStr) + 34);
End;

Function TaskBtnW : Integer;
Var N, A : Integer;
Begin
  N := TaskCnt;
  If N = 0 Then N := 1;
  A := (TrayX - 6 - (StartW + 8)) Div N;
  If A > 160 Then A := 160;
  TaskBtnW := A;
End;

Procedure TaskBtn(I : Integer; Var X1, X2 : Integer);
Begin
  X1 := StartW + 8 + I * TaskBtnW;
  X2 := X1 + TaskBtnW - 4;
End;

Procedure DrawClock;
Var X : Integer;
Begin
  X := TrayX;
  Bar(X, TaskY + 4, ScrW - 4, TaskY + 25, cSilver);
  Edge(X, TaskY + 4, ScrW - 4, TaskY + 25, cGray, cWhite);
  DrawIcon(icDisplay, X + 4, TaskY + 7, 16);
  OutText(X + 26, TaskY + 7, TimeStr, cBlack);
End;

Procedure DrawTaskbar;
Var I, X1, X2, K : Integer; Pressed : Boolean; T : String;
Begin
  SetClip(0, TaskY, ScrW - 1, ScrH - 1);
  If ClipEmpty Then Exit;
  Bar(0, TaskY, ScrW - 1, ScrH - 1, cSilver);
  HLine(0, ScrW - 1, TaskY + 1, cWhite);
  Pressed := (MenuDepth > 0) And (MenuOwner = 0);
  Raised(2, TaskY + 4, StartW + 1, TaskY + 25, Pressed);
  If Pressed Then I := 1 Else I := 0;
  DrawIcon(icLogo, 6 + I, TaskY + 7 + I, 16);
  OutBold(25 + I, TaskY + 7 + I, StartText, cBlack);
  For I := 0 To TaskCnt - 1 Do
  Begin
    K := TaskOrd[I];
    TaskBtn(I, X1, X2);
    Pressed := (K = TopWin);
    If Pressed Then
    Begin
      Raised(X1, TaskY + 4, X2, TaskY + 25, True);
      Dither(X1 + 2, TaskY + 6, X2 - 2, TaskY + 23, cWhite, 0);
    End
    Else
      Raised(X1, TaskY + 4, X2, TaskY + 25, False);
    DrawIcon(WinIcon(K), X1 + 4, TaskY + 7, 16);
    T := Fit(WinTitle(K), X2 - X1 - 26);
    If Pressed Then OutBold(X1 + 23, TaskY + 8, T, cBlack)
    Else OutText(X1 + 23, TaskY + 7, T, cBlack);
  End;
  DrawClock;
End;

{ ------------------------------------------------------------------ }
{ Bureau                                                             }
{ ------------------------------------------------------------------ }

Const
  DeskCount = 7;

Function DeskIconId(I : Integer) : Integer;
Begin
  Case I Of
    0 : DeskIconId := icComputer;
    1 : DeskIconId := icRecycle;
    2 : DeskIconId := icDos;
    3 : DeskIconId := icNotepad;
    4 : DeskIconId := icCalc;
    5 : DeskIconId := icPaint;
  Else
    DeskIconId := icText;
  End;
End;

Function DeskLabel(I : Integer) : String;
Begin
  Case I Of
    0 : DeskLabel := WinTitle(wkExplorer);
    1 : DeskLabel := WinTitle(wkRecycle);
    2 : DeskLabel := WinTitle(wkDos);
    3 : DeskLabel := L('Bloc-notes', 'Notepad', 'Editor', 'Blocco note',
                       'Bloc de notas');
    4 : DeskLabel := WinTitle(wkCalc);
    5 : DeskLabel := 'Paint';
  Else
    DeskLabel := L('Lisez-moi', 'Read Me', 'Liesmich', 'Leggimi',
                   'L'#130'ame');
  End;
End;

Function DeskCmd(I : Integer) : Integer;
Begin
  Case I Of
    0 : DeskCmd := cmComputer;
    1 : DeskCmd := cmRecycle;
    2 : DeskCmd := cmDos;
    3 : DeskCmd := cmNotepad;
    4 : DeskCmd := cmCalc;
    5 : DeskCmd := cmPaint;
  Else
    DeskCmd := cmReadme;
  End;
End;

Procedure DeskPos(I : Integer; Var X, Y : Integer);
Begin
  X := 6 + (I Div 6) * 84;
  Y := 8 + (I Mod 6) * 72;
End;

{ Etiquette sur deux lignes (au plus N caracteres par ligne) }
Procedure SplitLabel(Const S : String; N : Integer; Var A, B : String);
Var P, K : Integer;
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

Procedure DrawLabel(X, Y, W : Integer; Const S : String; Sel : Boolean;
                    Bg, Fg : Byte);
Var A, B : String; K, Y2 : Integer;
Begin
  SplitLabel(S, W Div 8, A, B);
  If B <> '' Then Y2 := Y + 31 Else Y2 := Y + 15;
  If Sel Then
  Begin
    K := Max(TextW(A), TextW(B));
    Bar(X + (W - K) Div 2 - 2, Y, X + (W + K) Div 2 + 1, Y2, cNavy);
    Fg := cWhite;
  End;
  OutCenter(X, X + W - 1, Y, A, Fg);
  If B <> '' Then OutCenter(X, X + W - 1, Y + 16, B, Fg);
End;

Procedure DrawDesktop;
Var I, X, Y : Integer; Fg : Byte; S : String;
Begin
  SetClip(0, 0, ScrW - 1, TaskY - 1);
  If ClipEmpty Then Exit;
  Bar(0, 0, ScrW - 1, TaskY - 1, DeskColor);
  If (DeskColor = cWhite) Or (DeskColor = cSilver) Or
     (DeskColor = cAqua) Or (DeskColor = cYellow) Then Fg := cBlack
  Else Fg := cWhite;
  For I := 0 To DeskCount - 1 Do
  Begin
    DeskPos(I, X, Y);
    If (X + 80 >= ClipX1) And (X <= ClipX2) And (Y + 68 >= ClipY1) And
       (Y <= ClipY2) Then
    Begin
      DrawIcon(DeskIconId(I), X + 24, Y, 32);
      DrawLabel(X, Y + 35, 80, DeskLabel(I), DeskSel = I, DeskColor, Fg);
    End;
  End;
  If SafeMode Then
  Begin
    S := L('Mode sans '#130'chec', 'Safe mode', 'Abgesicherter Modus',
           'Modalit'#133' provvisoria', 'Modo a prueba de fallos');
    OutBold(4, 2, S, cWhite);
    OutBold(ScrW - 6 - TextW(S), 2, S, cWhite);
    OutBold(4, TaskY - 18, S, cWhite);
    OutBold(ScrW - 6 - TextW(S), TaskY - 18, S, cWhite);
  End;
End;

Function DeskHit(PX, PY : Integer) : Integer;
Var I, X, Y : Integer;
Begin
  DeskHit := -1;
  For I := 0 To DeskCount - 1 Do
  Begin
    DeskPos(I, X, Y);
    If InRect(PX, PY, X + 20, Y, X + 59, Y + 33) Or
       InRect(PX, PY, X + 4, Y + 35, X + 75, Y + 66) Then
    Begin
      DeskHit := I;
      Exit;
    End;
  End;
End;

Procedure DeskRedrawIcon(I : Integer);
Var X, Y : Integer;
Begin
  If I < 0 Then Exit;
  DeskPos(I, X, Y);
  RedrawArea(X, Y, X + 83, Y + 68);
End;

{ ------------------------------------------------------------------ }
{ Menus (menu Demarrer et menus des applications)                    }
{ ------------------------------------------------------------------ }

{ Fichiers texte du CD-ROM (menu Documents) }
Function DocFile(N : Integer) : Integer;
Var I, C : Integer;
Begin
  DocFile := -1;
  C := 0;
  For I := 0 To CdCount - 1 Do
    If Not CdFiles[I].Dir And IsTextFile(CdFiles[I].Name) Then
    Begin
      If C = N Then
      Begin
        DocFile := I;
        Exit;
      End;
      Inc(C);
    End;
End;

Function MenuCount(M : Integer) : Integer;
Var N : Integer;
Begin
  Case M Of
    mnStart : MenuCount := 8;
    mnPrograms : MenuCount := 3;
    mnAccess : MenuCount := 3;
    mnSettings : MenuCount := 3;
    mnDocs :
    Begin
      N := 0;
      While (N < 10) And (DocFile(N) >= 0) Do Inc(N);
      If N = 0 Then N := 1;
      MenuCount := N;
    End;
    mnNoteFile : MenuCount := 4;
    mnNoteEdit : MenuCount := 2;
    mnHelp : MenuCount := 2;
    mnExpFile : MenuCount := 4;
    mnPaintFile : MenuCount := 3;
    mnBinFile : MenuCount := 3;
  Else
    MenuCount := 0;
  End;
End;

Function TxtClose : String;
Begin
  TxtClose := L('Fermer', 'Close', 'Schlie'#225'en', 'Chiudi', 'Cerrar');
End;

Function TxtQuit : String;
Begin
  TxtQuit := L('Quitter', 'Exit', 'Beenden', 'Esci', 'Salir');
End;

Procedure MenuItem(M, I : Integer; Var T : String;
                   Var Cmd, Sub, Icon : Integer);
Var F : Integer;
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
      Case I Of
        0 : Begin
              T := L('Accessoires', 'Accessories', 'Zubeh'#148'r',
                     'Accessori', 'Accesorios');
              Sub := mnAccess; Icon := icPrograms;
            End;
        1 : Begin
              T := L('Explorateur Windows', 'Windows Explorer',
                     'Windows-Explorer', 'Gestione risorse',
                     'Explorador de Windows');
              Cmd := cmExplorer; Icon := icExplorer;
            End;
        2 : Begin
              T := WinTitle(wkDos); Cmd := cmDos; Icon := icDos;
            End;
      End;
    mnAccess :
      Case I Of
        0 : Begin
              T := L('Bloc-notes', 'Notepad', 'Editor', 'Blocco note',
                     'Bloc de notas');
              Cmd := cmNotepad; Icon := icNotepad;
            End;
        1 : Begin
              T := WinTitle(wkCalc); Cmd := cmCalc; Icon := icCalc;
            End;
        2 : Begin
              T := 'Paint'; Cmd := cmPaint; Icon := icPaint;
            End;
      End;
    mnSettings :
      Case I Of
        0 : Begin
              T := WinTitle(wkControl); Cmd := cmControl;
              Icon := icControl;
            End;
        1 : Begin
              T := CtlName(0); Cmd := cmDisplay; Icon := icDisplay;
            End;
        2 : Begin
              T := CtlName(2); Cmd := cmRegional; Icon := icRegional;
            End;
      End;
    mnDocs :
    Begin
      F := DocFile(I);
      If F < 0 Then
        T := L('(vide)', '(empty)', '(leer)', '(vuoto)', '(vac'#161'o)')
      Else
      Begin
        T := CdFiles[F].Name; Cmd := cmDocBase + F; Icon := icText;
      End;
    End;
    mnNoteFile :
      Case I Of
        0 : Begin
              T := L('Nouveau', 'New', 'Neu', 'Nuovo', 'Nuevo');
              Cmd := cmNoteNew;
            End;
        1 : Begin
              T := L('Ouvrir...', 'Open...', #153'ffnen...', 'Apri...',
                     'Abrir...');
              Cmd := cmNoteOpen;
            End;
        3 : Begin
              T := TxtQuit; Cmd := cmClose;
            End;
      End;
    mnNoteEdit :
      Case I Of
        0 : Begin
              T := L('Heure/Date  F5', 'Time/Date  F5', 'Uhrzeit/Datum F5',
                     'Ora/Data  F5', 'Hora/Fecha  F5');
              Cmd := cmNoteTime;
            End;
        1 : Begin
              T := L('Effacer tout', 'Clear all', 'Alles l'#148'schen',
                     'Cancella tutto', 'Borrar todo');
              Cmd := cmNoteClear;
            End;
      End;
    mnHelp :
      Case I Of
        0 : Begin
              T := L('Rubriques d''aide', 'Help Topics', 'Hilfethemen',
                     'Argomenti della Guida', 'Temas de Ayuda');
              Cmd := cmHelp;
            End;
        1 : Begin
              T := L('A propos de Pasdows 95', 'About Pasdows 95',
                     'Info '#129'ber Pasdows 95', 'Informazioni su Pasdows',
                     'Acerca de Pasdows 95');
              Cmd := cmAbout;
            End;
      End;
    mnExpFile :
      Case I Of
        0 : Begin
              T := L('Ouvrir', 'Open', #153'ffnen', 'Apri', 'Abrir');
              Cmd := cmExpOpen;
            End;
        1 : Begin
              T := L('Dossier parent', 'Up One Level',
                     #154'bergeordneter Ordner', 'Livello superiore',
                     'Subir un nivel');
              Cmd := cmExpUp;
            End;
        3 : Begin
              T := TxtClose; Cmd := cmClose;
            End;
      End;
    mnPaintFile :
      Case I Of
        0 : Begin
              T := L('Nouveau', 'New', 'Neu', 'Nuovo', 'Nuevo');
              Cmd := cmPaintNew;
            End;
        2 : Begin
              T := TxtQuit; Cmd := cmClose;
            End;
      End;
    mnBinFile :
      Case I Of
        0 : Begin
              T := L('Vider la Corbeille', 'Empty Recycle Bin',
                     'Papierkorb leeren', 'Svuota Cestino',
                     'Vaciar Papelera');
              Cmd := cmEmptyBin;
            End;
        2 : Begin
              T := TxtClose; Cmd := cmClose;
            End;
      End;
  End;
End;

Function MenuItemH(M : Integer) : Integer;
Begin
  If M = mnStart Then MenuItemH := 32 Else MenuItemH := 20;
End;

Function MenuHasIcons(M : Integer) : Boolean;
Begin
  MenuHasIcons := (M = mnStart) Or (M = mnPrograms) Or (M = mnAccess) Or
                  (M = mnSettings) Or (M = mnDocs);
End;

Function MenuItemY(Lv, I : Integer) : Integer;
Var J, Y, Cmd, Sub, Ic : Integer; T : String;
Begin
  Y := Menus[Lv].Y + 3;
  For J := 0 To I - 1 Do
  Begin
    MenuItem(Menus[Lv].Id, J, T, Cmd, Sub, Ic);
    If T = '-' Then Y := Y + 8 Else Y := Y + Menus[Lv].ItemH;
  End;
  MenuItemY := Y;
End;

Procedure LayoutMenu(Lv, M, X, Y : Integer; Up : Boolean);
Var I, W, H, Cmd, Sub, Ic : Integer; T : String;
Begin
  Menus[Lv].Id := M;
  Menus[Lv].Count := MenuCount(M);
  Menus[Lv].ItemH := MenuItemH(M);
  Menus[Lv].Hot := -1;
  W := 0; H := 6;
  For I := 0 To Menus[Lv].Count - 1 Do
  Begin
    MenuItem(M, I, T, Cmd, Sub, Ic);
    If T = '-' Then H := H + 8
    Else
    Begin
      H := H + Menus[Lv].ItemH;
      If TextW(T) > W Then W := TextW(T);
    End;
  End;
  W := W + 40;
  If MenuHasIcons(M) Then W := W + 22;
  If M = mnStart Then W := W + 30;
  If W < 120 Then W := 120;
  If Up Then Y := Y - H;
  If Y + H > TaskY Then Y := TaskY - H;
  If Y < 0 Then Y := 0;
  If X + W > ScrW Then X := ScrW - W;
  Menus[Lv].X := X; Menus[Lv].Y := Y;
  Menus[Lv].W := W; Menus[Lv].H := H;
End;

{ Texte vertical (bandeau du menu Demarrer), de bas en haut }
Procedure RotText(X, Y : Integer; Const S : String; C : Byte);
Var K, R, CX : Integer; B : Byte;
Begin
  For K := 1 To Length(S) Do
  Begin
    For R := 0 To 15 Do
    Begin
      B := Mem[FontSeg:FontOfs + Word(Ord(S[K])) * 16 + R];
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

Procedure DrawMenu(Lv : Integer);
Var I, X, Y, W, H, YY, Cmd, Sub, Ic, TX : Integer; T : String;
    Fg : Byte; Hot : Boolean;
Begin
  X := Menus[Lv].X; Y := Menus[Lv].Y;
  W := Menus[Lv].W; H := Menus[Lv].H;
  SetClip(X, Y, X + W - 1, Y + H - 1);
  If ClipEmpty Then Exit;
  Edge(X, Y, X + W - 1, Y + H - 1, cSilver, cBlack);
  Edge(X + 1, Y + 1, X + W - 2, Y + H - 2, cWhite, cGray);
  Bar(X + 2, Y + 2, X + W - 3, Y + H - 3, cSilver);
  TX := X + 8;
  If Menus[Lv].Id = mnStart Then
  Begin
    Bar(X + 3, Y + 3, X + 24, Y + H - 4, cGray);
    RotText(X + 6, Y + H - 8, 'Pasdows', cSilver);
    RotText(X + 6, Y + H - 8 - 7 * 9 - 4, '95', cWhite);
    TX := X + 30;
  End;
  YY := Y + 3;
  For I := 0 To Menus[Lv].Count - 1 Do
  Begin
    MenuItem(Menus[Lv].Id, I, T, Cmd, Sub, Ic);
    If T = '-' Then
    Begin
      HLine(TX - 2, X + W - 5, YY + 3, cGray);
      HLine(TX - 2, X + W - 5, YY + 4, cWhite);
      YY := YY + 8;
    End
    Else
    Begin
      Hot := I = Menus[Lv].Hot;
      Fg := cBlack;
      If Hot Then
      Begin
        Bar(TX - 4, YY, X + W - 4, YY + Menus[Lv].ItemH - 1, cNavy);
        Fg := cWhite;
      End;
      If Ic <> 0 Then
      Begin
        If Menus[Lv].Id = mnStart Then
          DrawIcon(Ic, TX, YY + 4, 24)
        Else
          DrawIcon(Ic, TX, YY + 2, 16);
      End;
      If MenuHasIcons(Menus[Lv].Id) Then
      Begin
        If Menus[Lv].Id = mnStart Then
          OutText(TX + 32, YY + 8, T, Fg)
        Else
          OutText(TX + 22, YY + 2, T, Fg);
      End
      Else
        OutText(TX + 12, YY + 2, T, Fg);
      If Sub <> 0 Then
        Arrow(X + W - 14, YY + Menus[Lv].ItemH Div 2 - 3, 0, Fg);
      YY := YY + Menus[Lv].ItemH;
    End;
  End;
End;

Procedure OpenMenu(Lv, M, X, Y : Integer; Up : Boolean);
Begin
  LayoutMenu(Lv, M, X, Y, Up);
  MenuDepth := Lv + 1;
  RedrawArea(Menus[Lv].X, Menus[Lv].Y, Menus[Lv].X + Menus[Lv].W - 1,
             Menus[Lv].Y + Menus[Lv].H - 1);
End;

{ Fermer les menus de niveau >= Lv }
Procedure CloseMenus(Lv : Integer);
Var I, D : Integer;
Begin
  If MenuDepth <= Lv Then Exit;
  D := MenuDepth;
  MenuDepth := Lv;
  For I := D - 1 DownTo Lv Do
    RedrawArea(Menus[I].X, Menus[I].Y, Menus[I].X + Menus[I].W - 1,
               Menus[I].Y + Menus[I].H - 1);
  If Lv = 0 Then
  Begin
    If MenuOwner = 0 Then TaskbarRedraw
    Else If Wins[MenuOwner].Open Then
      RedrawArea(Wins[MenuOwner].X, Wins[MenuOwner].Y + 23,
                 Wins[MenuOwner].X + Wins[MenuOwner].W - 1,
                 Wins[MenuOwner].Y + 42);
  End;
End;

Procedure OpenStartMenu;
Begin
  CloseMenus(0);
  MenuOwner := 0;
  LayoutMenu(0, mnStart, 2, TaskY + 2, True);
  MenuDepth := 1;
  TaskbarRedraw;
  RedrawArea(Menus[0].X, Menus[0].Y, Menus[0].X + Menus[0].W - 1,
             Menus[0].Y + Menus[0].H - 1);
End;

Procedure OpenBarMenu(K, I : Integer);
Var T : String; M : Integer;
Begin
  CloseMenus(0);
  MenuBarItem(K, I, T, M);
  MenuOwner := K;
  LayoutMenu(0, M, MenuBarX(K, I), Wins[K].Y + 42, False);
  MenuDepth := 1;
  RedrawArea(Wins[K].X, Wins[K].Y + 23, Wins[K].X + Wins[K].W - 1,
             Wins[K].Y + 42);
  RedrawArea(Menus[0].X, Menus[0].Y, Menus[0].X + Menus[0].W - 1,
             Menus[0].Y + Menus[0].H - 1);
End;

{ Element de menu sous le point (niveau dans Lv) ; -1 si aucun }
Function MenuHit(PX, PY : Integer; Var Lv : Integer) : Integer;
Var I, J, Y, Cmd, Sub, Ic, H : Integer; T : String;
Begin
  MenuHit := -1;
  For I := MenuDepth - 1 DownTo 0 Do
    If InRect(PX, PY, Menus[I].X, Menus[I].Y, Menus[I].X + Menus[I].W - 1,
              Menus[I].Y + Menus[I].H - 1) Then
    Begin
      Lv := I;
      Y := Menus[I].Y + 3;
      For J := 0 To Menus[I].Count - 1 Do
      Begin
        MenuItem(Menus[I].Id, J, T, Cmd, Sub, Ic);
        If T = '-' Then H := 8 Else H := Menus[I].ItemH;
        If (PY >= Y) And (PY < Y + H) And (T <> '-') Then
        Begin
          MenuHit := J;
          Exit;
        End;
        Y := Y + H;
      End;
      MenuHit := -2;
      Exit;
    End;
End;

Procedure SetMenuHot(Lv, I : Integer);
Var T : String; Cmd, Sub, Ic : Integer;
Begin
  If Menus[Lv].Hot <> I Then
  Begin
    Menus[Lv].Hot := I;
    RedrawArea(Menus[Lv].X, Menus[Lv].Y, Menus[Lv].X + Menus[Lv].W - 1,
               Menus[Lv].Y + Menus[Lv].H - 1);
  End;
  If I < 0 Then Exit;
  MenuItem(Menus[Lv].Id, I, T, Cmd, Sub, Ic);
  If Sub <> 0 Then
  Begin
    If (MenuDepth > Lv + 1) And (Menus[Lv + 1].Id = Sub) Then Exit;
    CloseMenus(Lv + 1);
    OpenMenu(Lv + 1, Sub, Menus[Lv].X + Menus[Lv].W - 3,
             MenuItemY(Lv, I) - 3, False);
  End
  Else
    CloseMenus(Lv + 1);
End;

Procedure MenuChoose(Lv, I : Integer);
Var T : String; Cmd, Sub, Ic : Integer;
Begin
  MenuItem(Menus[Lv].Id, I, T, Cmd, Sub, Ic);
  If Sub <> 0 Then
  Begin
    SetMenuHot(Lv, I);
    Exit;
  End;
  CloseMenus(0);
  If Cmd <> cmNone Then Execute(Cmd);
End;

{ ------------------------------------------------------------------ }
{ Redessiner une zone de l'ecran (algorithme du peintre)             }
{ ------------------------------------------------------------------ }

Procedure RedrawArea(X1, Y1, X2, Y2 : Integer);
Var I, K : Integer;
Begin
  HideCursor;
  SetArea(X1, Y1, X2, Y2);
  If (AreaX1 > AreaX2) Or (AreaY1 > AreaY2) Then
  Begin
    SetArea(0, 0, ScrW - 1, ScrH - 1);
    Exit;
  End;
  If AreaY1 < TaskY Then DrawDesktop;
  For I := 0 To ZCnt - 1 Do
  Begin
    K := ZOrd[I];
    If Wins[K].Open And Not Wins[K].Min Then
      If (Wins[K].X <= AreaX2) And (Wins[K].X + Wins[K].W > AreaX1) And
         (Wins[K].Y <= AreaY2) And (Wins[K].Y + Wins[K].H > AreaY1) Then
        DrawWindow(K);
  End;
  If AreaY2 >= TaskY Then DrawTaskbar;
  For I := 0 To MenuDepth - 1 Do DrawMenu(I);
  SetArea(0, 0, ScrW - 1, ScrH - 1);
End;

Procedure RedrawAll;
Begin
  RedrawArea(0, 0, ScrW - 1, ScrH - 1);
End;

{ ================================================================== }
{ Applications                                                       }
{ ================================================================== }

Function TxtOk : String;
Begin
  TxtOk := 'OK';
End;

Function TxtCancel : String;
Begin
  TxtCancel := L('Annuler', 'Cancel', 'Abbrechen', 'Annulla',
                 'Cancelar');
End;

Function TxtApply : String;
Begin
  TxtApply := L('Appliquer', 'Apply', #154'bernehmen', 'Applica',
                'Aplicar');
End;

Function TxtObjects(N : Integer) : String;
Begin
  TxtObjects := IntToStr(N) + ' ' + L('objet(s)', 'object(s)',
                'Objekt(e)', 'oggetti', 'objeto(s)');
End;

Function TxtBytes : String;
Begin
  TxtBytes := L('octets', 'bytes', 'Byte', 'byte', 'bytes');
End;

{ Zone blanche en creux et barre d'etat (Explorateur, Corbeille...) }
Procedure ListFrame(X1, Y1, X2, Y2 : Integer; Const Status : String);
Begin
  Sunken(X1, Y1, X2, Y2 - 22, cWhite);
  Edge(X1, Y2 - 19, X2, Y2, cGray, cWhite);
  Bar(X1 + 1, Y2 - 18, X2 - 1, Y2 - 1, cSilver);
  OutText(X1 + 4, Y2 - 17, Status, cBlack);
End;

{ ------------------------------------------------------------------ }
{ Boutons des boites de dialogue                                     }
{ ------------------------------------------------------------------ }

Function DlgBtnCount(K : Integer) : Integer;
Begin
  Case K Of
    wkMsg, wkAbout : DlgBtnCount := 1;
    wkWelcome, wkSystem, wkDateTime : DlgBtnCount := 2;
    wkRun, wkShutdown, wkDisplay, wkRegional : DlgBtnCount := 3;
  Else
    DlgBtnCount := 0;
  End;
End;

Procedure DlgBtn(K, I : Integer; Var X1, Y1, X2, Y2 : Integer;
                 Var T : String);
Var CX1, CY1, CX2, CY2, N : Integer;
Begin
  ClientRect(K, CX1, CY1, CX2, CY2);
  N := DlgBtnCount(K);
  Y2 := CY2 - 8; Y1 := Y2 - 22;
  If K = wkRun Then
  Begin
    X2 := CX2 - 10 - (N - 1 - I) * 110;
    X1 := X2 - 103;
  End
  Else
  Begin
    X2 := CX2 - 10 - (N - 1 - I) * 92;
    X1 := X2 - 85;
  End;
  T := '';
  Case K Of
    wkMsg :
    Begin
      X1 := (CX1 + CX2) Div 2 - 42; X2 := X1 + 85;
      T := TxtOk;
    End;
    wkAbout : T := TxtOk;
    wkWelcome :
    Begin
      X2 := CX2 - 10; X1 := X2 - 125;
      Y1 := CY1 + 12 + I * 30; Y2 := Y1 + 22;
      If I = 0 Then T := TxtClose
      Else T := L('Astuce suivante', 'Next Tip', 'N'#132'chster Tipp',
                  'Suggerimento', 'Siguiente');
    End;
    wkRun :
      Case I Of
        0 : T := TxtOk;
        1 : T := TxtCancel;
      Else
        T := L('Parcourir...', 'Browse...', 'Durchsuchen',
               'Sfoglia...', 'Examinar...');
      End;
    wkShutdown :
      Case I Of
        0 : T := L('Oui', 'Yes', 'Ja', 'S'#141, 'S'#161);
        1 : T := L('Non', 'No', 'Nein', 'No', 'No');
      Else
        T := L('Aide', 'Help', 'Hilfe', 'Guida', 'Ayuda');
      End;
    wkDisplay, wkRegional :
      Case I Of
        0 : T := TxtOk;
        1 : T := TxtCancel;
      Else
        T := TxtApply;
      End;
    wkSystem, wkDateTime :
      If I = 0 Then T := TxtOk Else T := TxtCancel;
  End;
End;

Procedure DrawDlgButtons(K : Integer);
Var I, X1, Y1, X2, Y2 : Integer; T : String;
Begin
  For I := 0 To DlgBtnCount(K) - 1 Do
  Begin
    DlgBtn(K, I, X1, Y1, X2, Y2, T);
    PushButton(X1, Y1, X2, Y2, T, (PressWin = K) And (PressBtn = I),
               I = 0);
  End;
End;

Function DlgBtnHit(K, PX, PY : Integer) : Integer;
Var I, X1, Y1, X2, Y2 : Integer; T : String;
Begin
  DlgBtnHit := -1;
  For I := 0 To DlgBtnCount(K) - 1 Do
  Begin
    DlgBtn(K, I, X1, Y1, X2, Y2, T);
    If InRect(PX, PY, X1, Y1, X2, Y2) Then
    Begin
      DlgBtnHit := I;
      Exit;
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Poste de travail / Explorateur du CD-ROM                           }
{ ------------------------------------------------------------------ }

Function ExpCount : Integer;
Begin
  If ExpView = 0 Then ExpCount := 4 Else ExpCount := CdCount;
End;

Procedure ExpItem(I : Integer; Var T : String; Var Ic : Integer);
Begin
  If ExpView = 0 Then
    Case I Of
      0 : Begin
            T := L('Disquette 3'#171' (A:)', '3'#171' Floppy (A:)',
                   '3'#171'-Diskette (A:)', 'Floppy da 3,5 (A:)',
                   'Disco de 3'#171' (A:)');
            Ic := icFloppy;
          End;
      1 : Begin T := '(C:)'; Ic := icHardDisk; End;
      2 : Begin T := DriveLabel; Ic := icCdrom; End;
    Else
      T := WinTitle(wkControl); Ic := icControl;
    End
  Else
  Begin
    T := CdFiles[I].Name;
    If CdFiles[I].Dir Then Ic := icFolder
    Else If IsTextFile(T) Then Ic := icText
    Else Ic := icApp;
  End;
End;

Procedure ExpArea(Var X1, Y1, X2, Y2 : Integer);
Begin
  ClientRect(wkExplorer, X1, Y1, X2, Y2);
  Y1 := Y1 + 30;
End;

Function ExpCols : Integer;
Var X1, Y1, X2, Y2 : Integer;
Begin
  ExpArea(X1, Y1, X2, Y2);
  ExpCols := Max(1, (X2 - X1 - 8) Div 100);
End;

Procedure ExpCell(I : Integer; Var X, Y : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  ExpArea(X1, Y1, X2, Y2);
  X := X1 + 6 + (I Mod ExpCols) * 100;
  Y := Y1 + 6 + (I Div ExpCols) * 70;
End;

Procedure DrawExplorer;
Var X1, Y1, X2, Y2, I, X, Y, Ic : Integer; T, S : String;
Begin
  ClientRect(wkExplorer, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y1 + 29, cSilver);
  HLine(X1, X2, Y1, cWhite);
  { bouton Dossier parent }
  Raised(X1 + 4, Y1 + 4, X1 + 29, Y1 + 26, False);
  DrawIcon(icFolder, X1 + 8, Y1 + 7, 16);
  Arrow(X1 + 13, Y1 + 11, 2, cBlack);
  { adresse }
  Sunken(X1 + 36, Y1 + 4, X2 - 4, Y1 + 26, cWhite);
  If ExpView = 0 Then
  Begin
    DrawIcon(icComputer, X1 + 40, Y1 + 7, 16);
    OutText(X1 + 60, Y1 + 7, WinTitle(wkExplorer), cBlack);
  End
  Else
  Begin
    DrawIcon(icCdrom, X1 + 40, Y1 + 7, 16);
    OutText(X1 + 60, Y1 + 7, 'D:\', cBlack);
  End;
  S := TxtObjects(ExpCount);
  If (ExpView = 1) And (ExpSel >= 0) And (ExpSel < CdCount) Then
    S := S + '   ' + CdFiles[ExpSel].Name + ' : ' +
         FmtNum(CdFiles[ExpSel].Size) + ' ' + TxtBytes;
  ExpArea(X1, Y1, X2, Y2);
  ListFrame(X1, Y1, X2, Y2, Fit(S, X2 - X1 - 8));
  If (ExpView = 1) And Not CdOk Then
    OutText(X1 + 10, Y1 + 10, L('Le CD-ROM est illisible.',
            'The CD-ROM cannot be read.', 'CD-ROM nicht lesbar.',
            'CD-ROM illeggibile.', 'CD-ROM ilegible.'), cBlack);
  SetClip(X1 + 2, Y1 + 2, X2 - 2, Y2 - 24);
  For I := 0 To ExpCount - 1 Do
  Begin
    ExpItem(I, T, Ic);
    ExpCell(I, X, Y);
    DrawIcon(Ic, X + 32, Y, 32);
    DrawLabel(X, Y + 34, 96, T, I = ExpSel, cWhite, cBlack);
  End;
End;

Function ExpHit(PX, PY : Integer) : Integer;
Var I, X, Y : Integer;
Begin
  ExpHit := -1;
  For I := 0 To ExpCount - 1 Do
  Begin
    ExpCell(I, X, Y);
    If InRect(PX, PY, X + 4, Y, X + 91, Y + 66) Then
    Begin
      ExpHit := I;
      Exit;
    End;
  End;
End;

Procedure NoteOpenFile(Idx : Integer); Forward;

Procedure ExpOpen(I : Integer);
Begin
  If I < 0 Then Exit;
  If ExpView = 0 Then
    Case I Of
      0 : MessageBox(WinTitle(wkExplorer), L(
            'A:\ n''est pas accessible.|Le p'#130'riph'#130'rique n''est ' +
            'pas pr'#136't.',
            'A:\ is not accessible.|The device is not ready.',
            'Auf A:\ kann nicht zugegriffen werden.|Das Ger'#132't ist ' +
            'nicht bereit.',
            'Impossibile accedere ad A:\.|Periferica non pronta.',
            'No se puede tener acceso a A:\.|El dispositivo no est'#160' ' +
            'listo.'), icError);
      1 : MessageBox(WinTitle(wkExplorer), L(
            'Aucun disque dur n''a '#130't'#130' d'#130'tect'#130'.',
            'No hard disk was detected.', 'Keine Festplatte gefunden.',
            'Nessun disco rigido rilevato.',
            'No se detect'#162' ning'#163'n disco duro.'), icWarn);
      2 : Begin
            ExpView := 1; ExpSel := -1;
            WinRedraw(wkExplorer);
            TaskbarRedraw;
          End;
    Else
      Execute(cmControl);
    End
  Else If I < CdCount Then
  Begin
    If IsTextFile(CdFiles[I].Name) Then NoteOpenFile(I)
    Else
      MessageBox(CdFiles[I].Name, CdFiles[I].Name + ' : ' +
                 FmtNum(CdFiles[I].Size) + ' ' + TxtBytes + '.|' +
                 L('Ce fichier ne peut pas '#136'tre ouvert.',
                   'This file cannot be opened.',
                   'Diese Datei kann nicht ge'#148'ffnet werden.',
                   'Impossibile aprire il file.',
                   'No se puede abrir este archivo.'), icInfo);
  End;
End;

Procedure ExpUp;
Begin
  If ExpView <> 0 Then
  Begin
    ExpView := 0; ExpSel := -1;
    WinRedraw(wkExplorer);
    TaskbarRedraw;
  End;
End;

{ ------------------------------------------------------------------ }
{ Panneau de configuration et Corbeille                              }
{ ------------------------------------------------------------------ }

Function CtlIcon(I : Integer) : Integer;
Begin
  Case I Of
    0 : CtlIcon := icDisplay;
    1 : CtlIcon := icClock;
    2 : CtlIcon := icRegional;
  Else
    CtlIcon := icSystem;
  End;
End;

Procedure CtlCell(I : Integer; Var X, Y : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkControl, X1, Y1, X2, Y2);
  X := X1 + 8 + I * 88;
  Y := Y1 + 10;
End;

Procedure DrawControl;
Var X1, Y1, X2, Y2, I, X, Y : Integer;
Begin
  ClientRect(wkControl, X1, Y1, X2, Y2);
  ListFrame(X1, Y1, X2, Y2, TxtObjects(4));
  SetClip(X1 + 2, Y1 + 2, X2 - 2, Y2 - 24);
  For I := 0 To 3 Do
  Begin
    CtlCell(I, X, Y);
    DrawIcon(CtlIcon(I), X + 28, Y, 32);
    DrawLabel(X, Y + 34, 88, CtlName(I), I = CtlSel, cWhite, cBlack);
  End;
End;

Function CtlHit(PX, PY : Integer) : Integer;
Var I, X, Y : Integer;
Begin
  CtlHit := -1;
  For I := 0 To 3 Do
  Begin
    CtlCell(I, X, Y);
    If InRect(PX, PY, X, Y, X + 87, Y + 66) Then CtlHit := I;
  End;
End;

Procedure CtlOpen(I : Integer);
Begin
  Case I Of
    0 : Execute(cmDisplay);
    1 : Execute(cmDateTime);
    2 : Execute(cmRegional);
    3 : Execute(cmSystem);
  End;
End;

Procedure DrawRecycle;
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkRecycle, X1, Y1, X2, Y2);
  ListFrame(X1, Y1, X2, Y2, TxtObjects(0));
  OutText(X1 + 10, Y1 + 10, L('La Corbeille est vide.',
          'The Recycle Bin is empty.', 'Der Papierkorb ist leer.',
          'Il Cestino '#138' vuoto.', 'La Papelera est'#160' vac'#161'a.'),
          cGray);
End;

{ ------------------------------------------------------------------ }
{ Bloc-notes                                                         }
{ ------------------------------------------------------------------ }

Function NCh(P : Word) : Char;
Begin
  NCh := Chr(Mem[NoteSeg:P]);
End;

Function NLineStart(P : Word) : Word;
Begin
  While (P > 0) And (Mem[NoteSeg:P - 1] <> 13) Do Dec(P);
  NLineStart := P;
End;

Function NLineEnd(P : Word) : Word;
Begin
  While (P < NoteLen) And (Mem[NoteSeg:P] <> 13) Do Inc(P);
  NLineEnd := P;
End;

Procedure NoteGeom(Var X1, Y1, X2, Y2, Rows, Cols : Integer);
Begin
  ClientRect(wkNotepad, X1, Y1, X2, Y2);
  Rows := (Y2 - Y1 - 5) Div 16;
  Cols := (X2 - X1 - 24) Div 8;
  If Rows < 1 Then Rows := 1;
  If Cols < 1 Then Cols := 1;
End;

Procedure NoteVisible;
Var X1, Y1, X2, Y2, Rows, Cols, N : Integer; P, Col : Word;
Begin
  NoteGeom(X1, Y1, X2, Y2, Rows, Cols);
  If NoteCur < NoteTop Then NoteTop := NLineStart(NoteCur)
  Else
  Begin
    N := 0; P := NoteTop;
    While P < NLineStart(NoteCur) Do
    Begin
      P := NLineEnd(P) + 1;
      Inc(N);
    End;
    While N >= Rows Do
    Begin
      NoteTop := NLineEnd(NoteTop) + 1;
      Dec(N);
    End;
  End;
  Col := NoteCur - NLineStart(NoteCur);
  If Col < NoteLeft Then NoteLeft := Col;
  If Col >= NoteLeft + Cols Then NoteLeft := Col - Cols + 1;
End;

Procedure DrawNotepad;
Var X1, Y1, X2, Y2, Rows, Cols, R, CC : Integer;
    P, E, Q, LS : Word; S : String; Ch : Char;
Begin
  NoteGeom(X1, Y1, X2, Y2, Rows, Cols);
  Sunken(X1, Y1, X2, Y2, cWhite);
  { barre de defilement }
  Bar(X2 - 17, Y1 + 2, X2 - 2, Y2 - 2, cSilver);
  Dither(X2 - 17, Y1 + 2, X2 - 2, Y2 - 2, cWhite, 0);
  Raised(X2 - 17, Y1 + 2, X2 - 2, Y1 + 17, False);
  Arrow(X2 - 13, Y1 + 8, 2, cBlack);
  Raised(X2 - 17, Y2 - 17, X2 - 2, Y2 - 2, False);
  Arrow(X2 - 13, Y2 - 12, 1, cBlack);
  If NoteLen > 0 Then
  Begin
    R := Y1 + 18 + Integer(LongInt(NoteTop) * (Y2 - Y1 - 52) Div NoteLen);
    Raised(X2 - 17, R, X2 - 2, R + 15, False);
  End;
  SetClip(X1 + 2, Y1 + 2, X2 - 18, Y2 - 2);
  P := NoteTop;
  For R := 0 To Rows - 1 Do
  Begin
    If P > NoteLen Then Exit;
    LS := P;
    E := NLineEnd(P);
    S := '';
    Q := P + NoteLeft;
    CC := 0;
    While (Q < E) And (CC < Cols) Do
    Begin
      Ch := NCh(Q);
      If Ch < ' ' Then Ch := ' ';
      S := S + Ch;
      Inc(Q); Inc(CC);
    End;
    OutText(X1 + 4, Y1 + 3 + R * 16, S, cBlack);
    If (NoteCur >= LS) And (NoteCur <= E) And (TopWin = wkNotepad) Then
    Begin
      CC := (NoteCur - LS) - NoteLeft;
      If (CC >= 0) And (CC <= Cols) Then
        VLine(X1 + 4 + CC * 8, Y1 + 3 + R * 16, Y1 + 17 + R * 16,
              cBlack);
    End;
    P := E + 1;
  End;
End;

Procedure NoteInsert(C : Char);
Var N, A : Word; B : Byte;
Begin
  If NoteLen >= NoteMax Then
  Begin
    Beep;
    Exit;
  End;
  N := NoteLen - NoteCur;
  A := NoteLen;
  B := Ord(C);
  If N > 0 Then
    asm
      push ds
      push si
      push di
      mov cx,N
      mov di,A
      mov si,di
      dec si
      mov ax,7000h
      mov ds,ax
      mov es,ax
      std
      rep movsb
      cld
      pop di
      pop si
      pop ds
    end;
  Mem[NoteSeg:NoteCur] := B;
  Inc(NoteLen);
  Inc(NoteCur);
End;

Procedure NoteDelete(P : Word);
Var N : Word;
Begin
  If P >= NoteLen Then Exit;
  N := NoteLen - P - 1;
  If N > 0 Then
    asm
      push ds
      push si
      push di
      mov cx,N
      mov di,P
      mov si,di
      inc si
      mov ax,7000h
      mov ds,ax
      mov es,ax
      cld
      rep movsb
      pop di
      pop si
      pop ds
    end;
  Dec(NoteLen);
End;

Procedure NoteInsStr(Const S : String);
Var I : Integer;
Begin
  For I := 1 To Length(S) Do NoteInsert(S[I]);
End;

Procedure NoteReset;
Begin
  NoteLen := 0; NoteCur := 0; NoteTop := 0; NoteLeft := 0;
  NoteName := '';
End;

Procedure NoteOpenFile(Idx : Integer);
Var N, R, W : Word; B : Byte; CR : Boolean;
Begin
  NoteReset;
  If (Idx >= 0) And (Idx < CdCount) Then
  Begin
    N := CdLoad(Idx, NoteSeg, NoteMax);
    W := 0; CR := False;
    R := 0;
    While R < N Do
    Begin
      B := Mem[NoteSeg:R];
      If B = 13 Then
      Begin
        Mem[NoteSeg:W] := 13; Inc(W); CR := True;
      End
      Else If B = 10 Then
      Begin
        If Not CR Then
        Begin
          Mem[NoteSeg:W] := 13; Inc(W);
        End;
        CR := False;
      End
      Else
      Begin
        If (B <> 26) And (B <> 0) Then
        Begin
          Mem[NoteSeg:W] := B; Inc(W);
        End;
        CR := False;
      End;
      Inc(R);
    End;
    NoteLen := W;
    NoteName := CdFiles[Idx].Name;
  End;
  If Wins[wkNotepad].Open Then
  Begin
    Activate(wkNotepad);
    WinRedraw(wkNotepad);
  End
  Else
    OpenWin(wkNotepad);
End;

Procedure NoteKey(Const E : TEvent);
Var X1, Y1, X2, Y2, Rows, Cols, I : Integer; Col, LS, LE : Word;
Begin
  NoteGeom(X1, Y1, X2, Y2, Rows, Cols);
  Case E.Sc Of
    scLeft : If NoteCur > 0 Then Dec(NoteCur);
    scRight : If NoteCur < NoteLen Then Inc(NoteCur);
    scHome : NoteCur := NLineStart(NoteCur);
    scEnd : NoteCur := NLineEnd(NoteCur);
    scUp, scDown, scPgUp, scPgDn :
    Begin
      If (E.Sc = scUp) Or (E.Sc = scDown) Then I := 1 Else I := Rows - 1;
      While I > 0 Do
      Begin
        LS := NLineStart(NoteCur);
        Col := NoteCur - LS;
        If (E.Sc = scUp) Or (E.Sc = scPgUp) Then
        Begin
          If LS = 0 Then I := 1
          Else
          Begin
            LS := NLineStart(LS - 1);
            LE := NLineEnd(LS);
            If LS + Col > LE Then NoteCur := LE Else NoteCur := LS + Col;
          End;
        End
        Else
        Begin
          LE := NLineEnd(NoteCur);
          If LE >= NoteLen Then I := 1
          Else
          Begin
            LS := LE + 1;
            LE := NLineEnd(LS);
            If LS + Col > LE Then NoteCur := LE Else NoteCur := LS + Col;
          End;
        End;
        Dec(I);
      End;
    End;
    scDel : NoteDelete(NoteCur);
    scBack :
      If NoteCur > 0 Then
      Begin
        Dec(NoteCur);
        NoteDelete(NoteCur);
      End;
    scEnter : NoteInsert(#13);
    scF5 : NoteInsStr(TimeStr + ' ' + DateStr);
    scTab : NoteInsStr('    ');
  Else
    If E.Ch >= ' ' Then NoteInsert(E.Ch)
    Else Exit;
  End;
  NoteVisible;
  ClientRedraw(wkNotepad);
End;

Procedure NoteClick(PX, PY : Integer);
Var X1, Y1, X2, Y2, Rows, Cols, R, C : Integer; P, E : Word;
Begin
  NoteGeom(X1, Y1, X2, Y2, Rows, Cols);
  If PX > X2 - 18 Then
  Begin
    { fleches de la barre de defilement }
    For R := 1 To Rows Div 2 Do
      If PY < (Y1 + Y2) Div 2 Then
      Begin
        If NoteTop > 0 Then NoteTop := NLineStart(NoteTop - 1);
      End
      Else If NLineEnd(NoteTop) < NoteLen Then
        NoteTop := NLineEnd(NoteTop) + 1;
    ClientRedraw(wkNotepad);
    Exit;
  End;
  R := (PY - Y1 - 3) Div 16;
  C := (PX - X1 - 4 + 4) Div 8 + NoteLeft;
  If R < 0 Then R := 0;
  If C < 0 Then C := 0;
  P := NoteTop;
  While (R > 0) And (NLineEnd(P) < NoteLen) Do
  Begin
    P := NLineEnd(P) + 1;
    Dec(R);
  End;
  E := NLineEnd(P);
  If P + C > E Then NoteCur := E Else NoteCur := P + C;
  ClientRedraw(wkNotepad);
End;

{ ------------------------------------------------------------------ }
{ Calculatrice                                                       }
{ ------------------------------------------------------------------ }

Function CalcLabel(R, C : Integer) : String;
Const
  Lab : Array[0..23] Of String[4] = (
    'MC', '7', '8', '9', '/', 'sqrt',
    'MR', '4', '5', '6', '*', '%',
    'MS', '1', '2', '3', '-', '1/x',
    'M+', '0', '+/-', '.', '+', '=');
Begin
  CalcLabel := Lab[R * 6 + C];
End;

Function CalcTopLabel(I : Integer) : String;
Begin
  Case I Of
    0 : CalcTopLabel := L('Retour', 'Back', 'R'#129'ck', 'Indietro',
                          'Retroceso');
    1 : CalcTopLabel := 'CE';
  Else
    CalcTopLabel := 'C';
  End;
End;

{ Bouton I (0..23 grille, 24..26 rangee du haut) }
Procedure CalcBtn(I : Integer; Var X1, Y1, X2, Y2 : Integer);
Var CX1, CY1, CX2, CY2, R, C, W : Integer;
Begin
  ClientRect(wkCalc, CX1, CY1, CX2, CY2);
  If I >= 24 Then
  Begin
    W := (CX2 - 8 - (CX1 + 56) - 8) Div 3;
    X1 := CX1 + 56 + (I - 24) * (W + 4);
    X2 := X1 + W - 1;
    Y1 := CY1 + 38; Y2 := Y1 + 24;
    Exit;
  End;
  R := I Div 6; C := I Mod 6;
  Y1 := CY1 + 70 + R * 32; Y2 := Y1 + 26;
  If C = 0 Then X1 := CX1 + 8 Else X1 := CX1 + 56 + (C - 1) * 38;
  X2 := X1 + 33;
End;

Function FmtReal(V : Real) : String;
Var S : String;
Begin
  If (Abs(V) < 1E9) And (V = Trunc(V)) Then
    S := IntToStr(Trunc(V))
  Else If (Abs(V) >= 1E15) Or ((Abs(V) < 1E-6) And (V <> 0)) Then
  Begin
    Str(V, S);
    S := Trim(S);
  End
  Else
  Begin
    Str(V:0:10, S);
    While (Length(S) > 1) And (S[Length(S)] = '0') Do
      Delete(S, Length(S), 1);
    If S[Length(S)] = '.' Then Delete(S, Length(S), 1);
  End;
  If Length(S) > 26 Then S := Copy(S, 1, 26);
  FmtReal := S;
End;

Function CalcValue : Real;
Var V : Real; E : Integer;
Begin
  Val(CalcDisp, V, E);
  If E <> 0 Then V := 0;
  CalcValue := V;
End;

Procedure CalcSetValue(V : Real);
Begin
  CalcDisp := FmtReal(V);
End;

Procedure CalcError;
Begin
  CalcDisp := L('Division par z'#130'ro impossible', 'Cannot divide by zero',
                'Division durch Null', 'Impossibile dividere per 0',
                'No se puede dividir por 0');
  CalcErr := True;
  CalcOp := #0;
  CalcNew := True;
End;

Procedure CalcCompute;
Var V : Real;
Begin
  V := CalcValue;
  Case CalcOp Of
    '+' : CalcAcc := CalcAcc + V;
    '-' : CalcAcc := CalcAcc - V;
    '*' : CalcAcc := CalcAcc * V;
    '/' : If V = 0 Then
          Begin
            CalcError;
            Exit;
          End
          Else CalcAcc := CalcAcc / V;
  Else
    CalcAcc := V;
  End;
  CalcSetValue(CalcAcc);
End;

Procedure CalcPress(Const B : String);
Var V : Real;
Begin
  If CalcErr And (B <> 'C') And (B <> 'CE') Then Exit;
  If (Length(B) = 1) And (B[1] In ['0'..'9']) Then
  Begin
    If CalcNew Or (CalcDisp = '0') Then CalcDisp := B
    Else If Length(CalcDisp) < 20 Then CalcDisp := CalcDisp + B;
    CalcNew := False;
  End
  Else If B = '.' Then
  Begin
    If CalcNew Then CalcDisp := '0.'
    Else If Pos('.', CalcDisp) = 0 Then CalcDisp := CalcDisp + '.';
    CalcNew := False;
  End
  Else If (B = '+') Or (B = '-') Or (B = '*') Or (B = '/') Then
  Begin
    If (CalcOp <> #0) And Not CalcNew Then CalcCompute
    Else CalcAcc := CalcValue;
    If CalcErr Then Exit;
    CalcOp := B[1];
    CalcNew := True;
  End
  Else If B = '=' Then
  Begin
    If CalcOp <> #0 Then CalcCompute;
    CalcOp := #0;
    CalcNew := True;
  End
  Else If B = 'C' Then
  Begin
    CalcDisp := '0'; CalcAcc := 0; CalcOp := #0; CalcNew := True;
    CalcErr := False;
  End
  Else If B = 'CE' Then
  Begin
    CalcDisp := '0'; CalcNew := True; CalcErr := False;
  End
  Else If B = CalcTopLabel(0) Then
  Begin
    If Not CalcNew Then
    Begin
      Delete(CalcDisp, Length(CalcDisp), 1);
      If (CalcDisp = '') Or (CalcDisp = '-') Then CalcDisp := '0';
    End;
  End
  Else If B = '+/-' Then
  Begin
    If CalcDisp[1] = '-' Then Delete(CalcDisp, 1, 1)
    Else If CalcDisp <> '0' Then CalcDisp := '-' + CalcDisp;
  End
  Else If B = 'sqrt' Then
  Begin
    V := CalcValue;
    If V < 0 Then CalcError Else CalcSetValue(Sqrt(V));
    CalcNew := True;
  End
  Else If B = '%' Then
  Begin
    CalcSetValue(CalcAcc * CalcValue / 100);
    CalcNew := True;
  End
  Else If B = '1/x' Then
  Begin
    V := CalcValue;
    If V = 0 Then CalcError Else CalcSetValue(1 / V);
    CalcNew := True;
  End
  Else If B = 'MC' Then CalcMem := 0
  Else If B = 'MR' Then
  Begin
    CalcSetValue(CalcMem);
    CalcNew := True;
  End
  Else If B = 'MS' Then
  Begin
    CalcMem := CalcValue;
    CalcNew := True;
  End
  Else If B = 'M+' Then
  Begin
    CalcMem := CalcMem + CalcValue;
    CalcNew := True;
  End;
  ClientRedraw(wkCalc);
End;

Procedure DrawCalc;
Var CX1, CY1, CX2, CY2, I, X1, Y1, X2, Y2, D : Integer; T : String;
    C : Byte; P : Boolean;
Begin
  ClientRect(wkCalc, CX1, CY1, CX2, CY2);
  Bar(CX1, CY1, CX2, CY2, cSilver);
  Sunken(CX1 + 8, CY1 + 6, CX2 - 8, CY1 + 28, cWhite);
  OutText(CX2 - 13 - TextW(CalcDisp), CY1 + 10, CalcDisp, cBlack);
  Sunken(CX1 + 10, CY1 + 38, CX1 + 40, CY1 + 62, cSilver);
  If CalcMem <> 0 Then OutText(CX1 + 21, CY1 + 42, 'M', cBlack);
  For I := 0 To 26 Do
  Begin
    CalcBtn(I, X1, Y1, X2, Y2);
    If I >= 24 Then
    Begin
      T := CalcTopLabel(I - 24);
      C := cRed;
    End
    Else
    Begin
      T := CalcLabel(I Div 6, I Mod 6);
      If (I Mod 6 = 0) Or (I Mod 6 = 4) Or (T = '=') Then C := cRed
      Else C := cBlue;
    End;
    P := (PressWin = wkCalc) And (PressBtn = I);
    Raised(X1, Y1, X2, Y2, P);
    If P Then D := 1 Else D := 0;
    OutCenter(X1 + D, X2 + D, (Y1 + Y2 - 15) Div 2 + D, T, C);
  End;
End;

Function CalcHit(PX, PY : Integer) : Integer;
Var I, X1, Y1, X2, Y2 : Integer;
Begin
  CalcHit := -1;
  For I := 0 To 26 Do
  Begin
    CalcBtn(I, X1, Y1, X2, Y2);
    If InRect(PX, PY, X1, Y1, X2, Y2) Then
    Begin
      CalcHit := I;
      Exit;
    End;
  End;
End;

Procedure CalcBtnPress(I : Integer);
Begin
  If I >= 24 Then CalcPress(CalcTopLabel(I - 24))
  Else If I >= 0 Then CalcPress(CalcLabel(I Div 6, I Mod 6));
End;

Procedure CalcKey(Const E : TEvent);
Begin
  Case E.Sc Of
    scEnter : CalcPress('=');
    scEsc : CalcPress('C');
    scBack : CalcPress(CalcTopLabel(0));
    scDel : CalcPress('CE');
  Else
    Case E.Ch Of
      '0'..'9', '+', '-', '*', '/', '.', '%' : CalcPress(E.Ch);
      ',' : CalcPress('.');
      '=' : CalcPress('=');
    End;
  End;
End;

{ ------------------------------------------------------------------ }
{ Paint                                                              }
{ ------------------------------------------------------------------ }

Procedure PaintOrigin(Var X, Y : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkPaint, X1, Y1, X2, Y2);
  X := X1 + 38; Y := Y1 + 4;
End;

Function PaintGet(X, Y : Integer) : Byte;
Var B : Byte;
Begin
  B := Mem[PaintSeg:Word(Y) * 128 + Word(X) Shr 1];
  If Odd(X) Then PaintGet := B And 15 Else PaintGet := B Shr 4;
End;

Procedure PaintSet(X, Y : Integer; C : Byte);
Var O : Word; B : Byte;
Begin
  O := Word(Y) * 128 + Word(X) Shr 1;
  B := Mem[PaintSeg:O];
  If Odd(X) Then B := (B And $F0) Or C Else B := (B And $0F) Or (C Shl 4);
  Mem[PaintSeg:O] := B;
End;

Procedure PaintClear;
Var O : Word;
Begin
  For O := 0 To CanW * CanH Div 2 - 1 Do Mem[PaintSeg:O] := $FF;
End;

Procedure DrawPaint;
Var X1, Y1, X2, Y2, OX, OY, X, Y, S, I : Integer; C, C0 : Byte;
    O : Word;
Begin
  ClientRect(wkPaint, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  { outils }
  For I := 0 To 2 Do
  Begin
    Raised(X1 + 4, Y1 + 4 + I * 28, X1 + 29, Y1 + 29 + I * 28,
           PaintTool = I);
    X := X1 + 8; Y := Y1 + 8 + I * 28;
    Case I Of
      0 : Begin
            Line(X + 3, Y + 15, X + 15, Y + 3, cBlack);
            Line(X + 4, Y + 15, X + 16, Y + 3, cYellow);
            Pix(X + 3, Y + 16, cBlack);
          End;
      1 : Begin
            Disc(X + 8, Y + 8, 5, cNavy);
            VLine(X + 8, Y + 13, Y + 17, cMaroon);
          End;
    Else
      Bar(X + 2, Y + 6, X + 15, Y + 13, cFuchsia);
      Box(X + 2, Y + 6, X + 15, Y + 13, cBlack);
      Bar(X + 3, Y + 7, X + 7, Y + 12, cWhite);
    End;
  End;
  { toile }
  PaintOrigin(OX, OY);
  Sunken(OX - 2, OY - 2, OX + CanW + 1, OY + CanH + 1, cWhite);
  SetClip(OX, OY, OX + CanW - 1, OY + CanH - 1);
  If Not ClipEmpty Then
    For Y := 0 To CanH - 1 Do
      If (OY + Y >= ClipY1) And (OY + Y <= ClipY2) Then
      Begin
        S := 0;
        O := Word(Y) * 128;
        C0 := Mem[PaintSeg:O] Shr 4;
        X := 1;
        While X <= CanW Do
        Begin
          If X >= CanW Then C := 255
          Else If Odd(X) Then C := Mem[PaintSeg:O + Word(X Shr 1)] And 15
          Else C := Mem[PaintSeg:O + Word(X Shr 1)] Shr 4;
          If C <> C0 Then
          Begin
            If C0 <> cWhite Then HLine(OX + S, OX + X - 1, OY + Y, C0);
            S := X; C0 := C;
          End;
          Inc(X);
        End;
      End;
  { palette }
  ClientRect(wkPaint, X1, Y1, X2, Y2);
  SetClip(X1, Y1, X2, Y2);
  Y := OY + CanH + 8;
  Sunken(X1 + 4, Y, X1 + 31, Y + 31, cSilver);
  Bar(X1 + 10, Y + 6, X1 + 25, Y + 25, PaintColor);
  Box(X1 + 10, Y + 6, X1 + 25, Y + 25, cBlack);
  For I := 0 To 15 Do
  Begin
    X := OX + (I Mod 8) * 17;
    S := Y + (I Div 8) * 17;
    Sunken(X, S, X + 15, S + 15, I);
  End;
End;

Procedure PaintPlot(X, Y : Integer);
Var R, DX, DY, OX, OY : Integer; C : Byte;
Begin
  Case PaintTool Of
    0 : R := 0;
    1 : R := 1;
  Else
    R := 3;
  End;
  If PaintTool = 2 Then C := cWhite Else C := PaintColor;
  PaintOrigin(OX, OY);
  For DY := -R To R Do
    For DX := -R To R Do
      If (X + DX >= 0) And (X + DX < CanW) And (Y + DY >= 0) And
         (Y + DY < CanH) Then
      Begin
        PaintSet(X + DX, Y + DY, C);
        Pix(OX + X + DX, OY + Y + DY, C);
      End;
End;

{ Tracer de (X1,Y1) a (X2,Y2) sur la toile (coordonnees de la toile) }
Procedure PaintStroke(X1, Y1, X2, Y2 : Integer);
Var DX, DY, SX, SY, E, E2, OX, OY : Integer;
Begin
  HideCursor;
  PaintOrigin(OX, OY);
  SetArea(0, 0, ScrW - 1, ScrH - 1);
  SetClip(OX, OY, OX + CanW - 1, OY + CanH - 1);
  DX := Abs(X2 - X1); DY := -Abs(Y2 - Y1);
  If X1 < X2 Then SX := 1 Else SX := -1;
  If Y1 < Y2 Then SY := 1 Else SY := -1;
  E := DX + DY;
  While True Do
  Begin
    PaintPlot(X1, Y1);
    If (X1 = X2) And (Y1 = Y2) Then
    Begin
      FullClip;
      GcSet(8, $FF);
      Exit;
    End;
    E2 := 2 * E;
    If E2 >= DY Then Begin E := E + DY; X1 := X1 + SX End;
    If E2 <= DX Then Begin E := E + DX; Y1 := Y1 + SY End;
  End;
End;

Procedure PaintClick(PX, PY : Integer);
Var X1, Y1, X2, Y2, OX, OY, I, X, Y : Integer;
Begin
  ClientRect(wkPaint, X1, Y1, X2, Y2);
  PaintOrigin(OX, OY);
  For I := 0 To 2 Do
    If InRect(PX, PY, X1 + 4, Y1 + 4 + I * 28, X1 + 29, Y1 + 29 + I * 28)
    Then
    Begin
      PaintTool := I;
      ClientRedraw(wkPaint);
      Exit;
    End;
  Y := OY + CanH + 8;
  For I := 0 To 15 Do
  Begin
    X := OX + (I Mod 8) * 17;
    If InRect(PX, PY, X, Y + (I Div 8) * 17, X + 15, Y + (I Div 8) * 17 + 15)
    Then
    Begin
      PaintColor := I;
      If PaintTool = 2 Then PaintTool := 0;
      ClientRedraw(wkPaint);
      Exit;
    End;
  End;
  If InRect(PX, PY, OX, OY, OX + CanW - 1, OY + CanH - 1) Then
  Begin
    PaintDown := True;
    PaintLX := PX - OX; PaintLY := PY - OY;
    PaintStroke(PaintLX, PaintLY, PaintLX, PaintLY);
  End;
End;

Procedure PaintMove(PX, PY : Integer);
Var OX, OY, X, Y : Integer;
Begin
  PaintOrigin(OX, OY);
  X := PX - OX; Y := PY - OY;
  If X < 0 Then X := 0;
  If Y < 0 Then Y := 0;
  If X >= CanW Then X := CanW - 1;
  If Y >= CanH Then Y := CanH - 1;
  If (X <> PaintLX) Or (Y <> PaintLY) Then
  Begin
    PaintStroke(PaintLX, PaintLY, X, Y);
    PaintLX := X; PaintLY := Y;
  End;
End;

{ ------------------------------------------------------------------ }
{ Invite MS-DOS (fenetre ou plein ecran texte)                       }
{ ------------------------------------------------------------------ }

Procedure ConClear;
Var I : Integer;
Begin
  For I := 0 To ConMaxC * ConMaxR - 1 Do ConBuf[I] := ' ';
  ConX := 0; ConY := 0;
End;

Procedure ConInit(TextScr : Boolean);
Begin
  ConText := TextScr;
  If TextScr Then
  Begin
    ConCols := 80; ConRows := 25;
  End
  Else
  Begin
    ConCols := 64; ConRows := 18;
  End;
  ConClear;
  ConLine := '';
End;

Procedure ConScroll;
Var I : Integer;
Begin
  For I := 0 To (ConRows - 1) * ConCols - 1 Do
    ConBuf[I] := ConBuf[I + ConCols];
  For I := (ConRows - 1) * ConCols To ConRows * ConCols - 1 Do
    ConBuf[I] := ' ';
  ConY := ConRows - 1;
End;

Procedure ConNewLine;
Begin
  ConX := 0;
  Inc(ConY);
  If ConY >= ConRows Then ConScroll;
End;

Procedure ConPutC(C : Char);
Begin
  If C = #13 Then Exit;
  If C = #10 Then
  Begin
    ConNewLine;
    Exit;
  End;
  If C = #9 Then C := ' ';
  ConBuf[ConY * ConCols + ConX] := C;
  Inc(ConX);
  If ConX >= ConCols Then ConNewLine;
End;

Procedure ConWrite(Const S : String);
Var I : Integer;
Begin
  For I := 1 To Length(S) Do ConPutC(S[I]);
End;

Procedure ConWriteLn(Const S : String);
Begin
  ConWrite(S);
  ConNewLine;
End;

{ Afficher la console (ecran texte : memoire B800h) }
Procedure ConRefresh;
Var I : Integer; P : Word; R, C : Byte;
Begin
  If ConText Then
  Begin
    For I := 0 To 80 * 25 - 1 Do
      MemW[$B800:I * 2] := Ord(ConBuf[I]) Or $0700;
    R := ConY; C := ConX;
    asm
      mov ah,02h
      xor bh,bh
      mov dh,R
      mov dl,C
      int 10h
    end;
  End
  Else
    ClientRedraw(wkDos);
  P := 0;
End;

Procedure DrawDos;
Var X1, Y1, X2, Y2, R, C, N : Integer; S : String;
Begin
  ClientRect(wkDos, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cBlack);
  For R := 0 To ConRows - 1 Do
  Begin
    N := ConCols;
    While (N > 0) And (ConBuf[R * ConCols + N - 1] = ' ') Do Dec(N);
    S := '';
    For C := 0 To N - 1 Do S := S + ConBuf[R * ConCols + C];
    OutText(X1, Y1 + R * 16, S, cSilver);
  End;
  Bar(X1 + ConX * 8, Y1 + ConY * 16 + 13, X1 + ConX * 8 + 7,
      Y1 + ConY * 16 + 14, cSilver);
End;

Procedure ConPrompt;
Begin
  ConWrite(GetEnv('PROMPTDIR') + 'D:\>');
End;

Function RunProgram(Name : String) : Boolean; Forward;

Procedure ConDir(Wide : Boolean);
Var I, N, P : Integer; T : LongInt; S, B, E : String;
Begin
  ConWriteLn(' ' + L('Le volume dans le lecteur D est ',
             'Volume in drive D is ', 'Datentr'#132'ger in Laufwerk D ist ',
             'Il volume nell''unit'#133' D '#138' ',
             'El volumen de la unidad D es ')
             + VolLabel);
  ConWriteLn(' ' + L('R'#130'pertoire de D:\', 'Directory of D:\',
             'Verzeichnis von D:\', 'Directory di D:\',
             'Directorio de D:\'));
  ConWriteLn('');
  N := 0; T := 0; S := '';
  For I := 0 To CdCount - 1 Do
  Begin
    P := Pos('.', CdFiles[I].Name);
    If P > 0 Then
    Begin
      B := Copy(CdFiles[I].Name, 1, P - 1);
      E := Copy(CdFiles[I].Name, P + 1, 3);
    End
    Else
    Begin
      B := CdFiles[I].Name; E := '';
    End;
    If Wide Then
    Begin
      B := CdFiles[I].Name;
      While Length(B) < 16 Do B := B + ' ';
      S := S + B;
      If Length(S) >= 64 Then
      Begin
        ConWriteLn(S);
        S := '';
      End;
    End
    Else
    Begin
      While Length(B) < 9 Do B := B + ' ';
      While Length(E) < 4 Do E := E + ' ';
      If CdFiles[I].Dir Then S := '<REP>     '
      Else
      Begin
        S := IntToStr(CdFiles[I].Size);
        While Length(S) < 10 Do S := ' ' + S;
      End;
      ConWriteLn(B + E + S + '  ' + Pad2(CdFiles[I].Dy) + '/' +
                 Pad2(CdFiles[I].Mo) + '/' +
                 Pad2((1900 + CdFiles[I].Yr) Mod 100) + '  ' +
                 Pad2(CdFiles[I].Hr) + ':' + Pad2(CdFiles[I].Mi));
      S := '';
    End;
    Inc(N);
    T := T + CdFiles[I].Size;
  End;
  If S <> '' Then ConWriteLn(S);
  ConWriteLn('    ' + IntToStr(N) + ' ' + L('fichier(s)', 'file(s)',
             'Datei(en)', 'file', 'archivo(s)') + '  ' + FmtNum(T) + ' ' +
             TxtBytes);
  ConWriteLn('    0 ' + L('octets libres', 'bytes free', 'Byte frei',
             'byte disponibili', 'bytes libres'));
End;

Procedure ConType(Name : String);
Var I, N, P : Integer; C : Char;
Begin
  I := CdFind(Trim(Name));
  If I < 0 Then
  Begin
    ConWriteLn(L('Fichier introuvable', 'File not found',
               'Datei nicht gefunden', 'File non trovato',
               'No se encontr'#162' el archivo'));
    Exit;
  End;
  N := CdLoad(I, TmpSeg, TmpMax);
  P := 0;
  While P < N Do
  Begin
    C := Chr(Mem[TmpSeg:P]);
    If C = #26 Then P := N
    Else ConPutC(C);
    Inc(P);
  End;
  If ConX > 0 Then ConNewLine;
End;

Procedure ConHelp;
Begin
  ConWriteLn(L('Commandes disponibles :', 'Available commands:',
             'Verf'#129'gbare Befehle:', 'Comandi disponibili:',
             'Comandos disponibles:'));
  ConWriteLn('  CLS  DATE  DIR [/W]  ECHO  EXIT  HELP  MEM  SET  TIME');
  ConWriteLn('  TYPE  VER  VOL  WIN  CALC  CONTROL  EXPLORER  NOTEPAD');
  ConWriteLn('  PAINT  WINVER');
  ConWriteLn(L('Exemple : SET LANGUAGE=EN (anglais), GR, IT, SP ou FR',
             'Example: SET LANGUAGE=FR (French), GR, IT, SP or EN',
             'Beispiel: SET LANGUAGE=EN (Englisch), FR, IT, SP',
             'Esempio: SET LANGUAGE=EN (inglese), FR, GR, SP',
             'Ejemplo: SET LANGUAGE=EN (ingl'#130's), FR, GR, IT'));
End;

Procedure LanguageChanged; Forward;

Procedure ConExec(Line : String);
Var Cmd, Arg, U : String; P, I : Integer; H, M, S : Integer;
    OldLang : TLanguage;
Begin
  Line := Trim(Line);
  If Line = '' Then Exit;
  P := 1;
  While (P <= Length(Line)) And Not (Line[P] In [' ', '/', '\']) Do Inc(P);
  Cmd := UpStr(Copy(Line, 1, P - 1));
  Arg := Trim(Copy(Line, P, 255));
  If (Cmd = 'HELP') Or (Cmd = 'AIDE') Or (Cmd = '?') Then ConHelp
  Else If Cmd = 'CLS' Then ConClear
  Else If Cmd = 'VER' Then
  Begin
    ConWriteLn('');
    ConWriteLn('Pasdows 95. [Version ' + Version + ']');
  End
  Else If Cmd = 'DIR' Then ConDir(Pos('/W', UpStr(Arg)) > 0)
  Else If Cmd = 'TYPE' Then ConType(Arg)
  Else If Cmd = 'ECHO' Then ConWriteLn(Arg)
  Else If Cmd = 'VOL' Then
    ConWriteLn(' ' + L('Le volume dans le lecteur D est ',
               'Volume in drive D is ', 'Datentr'#132'ger in Laufwerk D ist ',
               'Il volume nell''unit'#133' D '#138' ',
               'El volumen de la unidad D es ') + VolLabel)
  Else If Cmd = 'DATE' Then
    ConWriteLn(L('La date du jour est ', 'Current date is ',
               'Aktuelles Datum: ', 'La data corrente '#138' ',
               'La fecha actual es ') + DateStr)
  Else If Cmd = 'TIME' Then
  Begin
    RtcTime(H, M, S);
    ConWriteLn(L('L''heure actuelle est ', 'Current time is ',
               'Aktuelle Uhrzeit: ', 'L''ora corrente '#138' ',
               'La hora actual es ') + Pad2(H) + ':' + Pad2(M) + ':' +
               Pad2(S));
  End
  Else If Cmd = 'MEM' Then
  Begin
    ConWriteLn('');
    ConWriteLn(L('M'#130'moire conventionnelle : ', 'Conventional memory: ',
               'Konventioneller Speicher: ', 'Memoria convenzionale: ',
               'Memoria convencional: ') + FmtNum(MemConv) + ' Ko');
    ConWriteLn(L('M'#130'moire '#130'tendue         : ',
               'Extended memory:     ',
               'Erweiterungsspeicher:     ', 'Memoria estesa:        ',
               'Memoria extendida:    ') + FmtNum(MemExt) + ' Ko');
  End
  Else If Cmd = 'SET' Then
  Begin
    If Arg = '' Then
      For I := 1 To EnvCnt Do ConWriteLn(EnvStr[I])
    Else If Pos('=', Arg) = 0 Then
      ConWriteLn(UpStr(Arg) + '=' + GetEnv(Arg))
    Else
    Begin
      U := UpStr(Trim(Copy(Arg, 1, Pos('=', Arg) - 1)));
      SetEnv(U, Trim(Copy(Arg, Pos('=', Arg) + 1, 255)));
      If U = 'LANGUAGE' Then
      Begin
        OldLang := Language;
        ApplyLanguage;
        If OldLang <> Language Then LanguageChanged;
      End;
    End;
  End
  Else If (Cmd = 'CD') Or (Cmd = 'CHDIR') Then
  Begin
    If (Arg = '') Or (Arg = '\') Or (Arg = '..') Or (Arg = '.') Then
      ConWriteLn('D:\')
    Else
      ConWriteLn(L('R'#130'pertoire non valide', 'Invalid directory',
                 'Ung'#129'ltiges Verzeichnis', 'Directory non valida',
                 'Directorio no v'#160'lido'));
  End
  Else If Cmd = 'D:' Then
  Else If (Length(Cmd) = 2) And (Cmd[2] = ':') Then
    ConWriteLn(L('Lecteur non valide', 'Invalid drive specification',
               'Ung'#129'ltige Laufwerksangabe', 'Unit'#133' non valida',
               'Unidad no v'#160'lida'))
  Else If Cmd = 'EXIT' Then ConQuit := True
  Else If Cmd = 'WIN' Then
  Begin
    If ConText Then ConQuit := True
    Else ConWriteLn(L('Pasdows est d'#130'j'#133' en cours d''ex'#130'cution.',
                      'Pasdows is already running.',
                      'Pasdows wird bereits ausgef'#129'hrt.',
                      'Pasdows '#138' gi'#133' in esecuzione.',
                      'Pasdows ya se est'#160' ejecutando.'));
  End
  Else If ConText Then
    ConWriteLn(L('Commande ou nom de fichier incorrect',
               'Bad command or file name',
               'Befehl oder Dateiname nicht gefunden',
               'Comando o nome di file non valido',
               'Comando o nombre de archivo incorrecto'))
  Else If Not RunProgram(Line) Then
    ConWriteLn(L('Commande ou nom de fichier incorrect',
               'Bad command or file name',
               'Befehl oder Dateiname nicht gefunden',
               'Comando o nome di file non valido',
               'Comando o nombre de archivo incorrecto'));
End;

Procedure ConBanner;
Begin
  ConWriteLn('');
  ConWriteLn('Pasdows 95. [Version ' + Version + ']');
  ConWriteLn('(C) Copyright Gladir.com 2026.');
  ConWriteLn('');
  ConPrompt;
End;

Procedure ConKey(Const E : TEvent);
Begin
  If E.Sc = scEnter Then
  Begin
    ConNewLine;
    ConQuit := False;
    ConExec(ConLine);
    If ConQuit Then Exit;
    If ConX > 0 Then ConNewLine;
    If (Trim(ConLine) <> '') And (UpStr(Trim(ConLine)) <> 'CLS') Then
      ConNewLine;
    ConLine := '';
    ConPrompt;
  End
  Else If E.Sc = scBack Then
  Begin
    If Length(ConLine) > 0 Then
    Begin
      Delete(ConLine, Length(ConLine), 1);
      If ConX > 0 Then Dec(ConX)
      Else If ConY > 0 Then
      Begin
        Dec(ConY); ConX := ConCols - 1;
      End;
      ConBuf[ConY * ConCols + ConX] := ' ';
    End;
  End
  Else If E.Sc = scEsc Then
  Begin
    While Length(ConLine) > 0 Do
    Begin
      Delete(ConLine, Length(ConLine), 1);
      If ConX > 0 Then Dec(ConX);
      ConBuf[ConY * ConCols + ConX] := ' ';
    End;
  End
  Else If (E.Ch >= ' ') And (Length(ConLine) < 120) Then
  Begin
    ConLine := ConLine + E.Ch;
    ConPutC(E.Ch);
  End
  Else
    Exit;
  ConRefresh;
End;

{ ------------------------------------------------------------------ }
{ Boites de dialogue                                                 }
{ ------------------------------------------------------------------ }

Function ColorName(I : Integer) : String;
Begin
  Case I Of
    0 : ColorName := L('Sarcelle', 'Teal', 'Blaugr'#129'n', 'Verde acqua',
                       'Verde azulado');
    1 : ColorName := L('Bleu marine', 'Navy', 'Marineblau', 'Blu marino',
                       'Azul marino');
    2 : ColorName := L('Vert', 'Green', 'Gr'#129'n', 'Verde', 'Verde');
    3 : ColorName := L('Pourpre', 'Purple', 'Violett', 'Viola',
                       'P'#163'rpura');
    4 : ColorName := L('Bordeaux', 'Maroon', 'Kastanienbraun', 'Bordeaux',
                       'Granate');
    5 : ColorName := L('Olive', 'Olive', 'Oliv', 'Oliva', 'Oliva');
    6 : ColorName := L('Gris', 'Gray', 'Grau', 'Grigio', 'Gris');
  Else
    ColorName := L('Noir', 'Black', 'Schwarz', 'Nero', 'Negro');
  End;
End;

Function ColorOf(I : Integer) : Byte;
Begin
  Case I Of
    0 : ColorOf := cTeal;
    1 : ColorOf := cNavy;
    2 : ColorOf := cGreen;
    3 : ColorOf := cPurple;
    4 : ColorOf := cMaroon;
    5 : ColorOf := cOlive;
    6 : ColorOf := cGray;
  Else
    ColorOf := cBlack;
  End;
End;

Procedure ColorRadio(I : Integer; Var X, Y : Integer);
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkDisplay, X1, Y1, X2, Y2);
  X := X1 + 20 + (I Div 4) * 150;
  Y := Y1 + 160 + (I Mod 4) * 20;
End;

Procedure DrawDisplay;
Var X1, Y1, X2, Y2, I, X, Y, MX : Integer;
Begin
  ClientRect(wkDisplay, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  { moniteur d'apercu }
  MX := (X1 + X2) Div 2;
  Raised(MX - 80, Y1 + 10, MX + 80, Y1 + 120, False);
  Bar(MX - 70, Y1 + 18, MX + 70, Y1 + 104, ColorOf(DispSel));
  Edge(MX - 71, Y1 + 17, MX + 71, Y1 + 105, cGray, cWhite);
  Bar(MX - 40, Y1 + 36, MX + 30, Y1 + 80, cSilver);
  Bar(MX - 38, Y1 + 38, MX + 28, Y1 + 46, cNavy);
  Bar(MX - 70, Y1 + 97, MX + 70, Y1 + 104, cSilver);
  Bar(MX - 68, Y1 + 99, MX - 52, Y1 + 103, cGray);
  Raised(MX - 20, Y1 + 121, MX + 20, Y1 + 128, False);
  GroupBox(X1 + 8, Y1 + 144, X2 - 8, Y2 - 44,
           L('Arri'#138're-plan', 'Background', 'Hintergrund', 'Sfondo',
             'Fondo'));
  For I := 0 To 7 Do
  Begin
    ColorRadio(I, X, Y);
    Bar(X + 18, Y + 3, X + 27, Y + 12, ColorOf(I));
    Box(X + 18, Y + 3, X + 27, Y + 12, cBlack);
    RadioButton(X, Y, '    ' + ColorName(I), I = DispSel);
  End;
  DrawDlgButtons(wkDisplay);
End;

Procedure DisplayApply;
Begin
  DeskColor := ColorOf(DispSel);
  RedrawAll;
End;

Function LangName(I : Integer) : String;
Begin
  Case I Of
    0 : LangName := 'Fran'#135'ais (FR)';
    1 : LangName := 'English (EN)';
    2 : LangName := 'Deutsch (GR)';
    3 : LangName := 'Italiano (IT)';
  Else
    LangName := 'Espa'#164'ol (SP)';
  End;
End;

Procedure DrawRegional;
Var X1, Y1, X2, Y2, I : Integer;
Begin
  ClientRect(wkRegional, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(icRegional, X1 + 12, Y1 + 12, 32);
  WrapText(X1 + 56, Y1 + 10, X2 - X1 - 64, L(
    'Choisissez la langue de Pasdows (variable LANGUAGE).',
    'Choose the language of Pasdows (LANGUAGE variable).',
    'W'#132'hlen Sie die Sprache von Pasdows (Variable LANGUAGE).',
    'Scegliere la lingua di Pasdows (variabile LANGUAGE).',
    'Elija el idioma de Pasdows (variable LANGUAGE).'), cBlack, True);
  GroupBox(X1 + 8, Y1 + 62, X2 - 8, Y2 - 42,
           L('Langue', 'Language', 'Sprache', 'Lingua', 'Idioma'));
  For I := 0 To 4 Do
    RadioButton(X1 + 22, Y1 + 74 + I * 20, LangName(I), I = RegSel);
  DrawDlgButtons(wkRegional);
End;

Procedure RegionalApply;
Var OldLang : TLanguage;
Begin
  OldLang := Language;
  SetEnv('LANGUAGE', Copy(LangName(RegSel), Length(LangName(RegSel)) - 2,
         2));
  ApplyLanguage;
  If OldLang <> Language Then LanguageChanged;
End;

Function CpuName : String;
Begin
  Case CpuType Of
    0 : CpuName := '8086/8088';
    1 : CpuName := '80286';
  Else
    CpuName := L('80386 ou sup'#130'rieur', '80386 or higher',
                 '80386 oder h'#148'her', '80386 o superiore',
                 '80386 o superior');
  End;
End;

Function RamText : String;
Var K : LongInt;
Begin
  K := LongInt(MemExt) + 1024;
  RamText := FmtNum(K) + L(' Ko de RAM', ' KB RAM', ' KB RAM',
             ' KB di RAM', ' KB de RAM');
End;

Procedure DrawSystem;
Var X1, Y1, X2, Y2, X : Integer;
Begin
  ClientRect(wkSystem, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(icComputer, X1 + 24, Y1 + 30, 96);
  X := X1 + 170;
  OutText(X, Y1 + 12, L('Syst'#138'me :', 'System:', 'System:', 'Sistema:',
          'Sistema:'), cBlack);
  OutText(X + 16, Y1 + 30, 'Pasdows 95', cBlack);
  OutText(X + 16, Y1 + 46, Version, cBlack);
  OutText(X, Y1 + 70, L('Enregistr'#130' '#133' :', 'Registered to:',
          'Registriert f'#129'r:', 'Registrato a:', 'Registrado a:'), cBlack);
  OutText(X + 16, Y1 + 88, 'Gladir.com', cBlack);
  OutText(X, Y1 + 112, L('Ordinateur :', 'Computer:', 'Computer:',
          'Computer:', 'Equipo:'), cBlack);
  OutText(X + 16, Y1 + 130, CpuName, cBlack);
  OutText(X + 16, Y1 + 146, RamText, cBlack);
  OutText(X + 16, Y1 + 162, L('D'#130'marrage : CD-ROM ', 'Boot: CD-ROM ',
          'Start: CD-ROM ', 'Avvio: CD-ROM ', 'Inicio: CD-ROM ') +
          '(' + HexByte(BootDrive) + 'h)', cBlack);
  DrawDlgButtons(wkSystem);
End;

Procedure DrawAbout;
Var X1, Y1, X2, Y2, X : Integer;
Begin
  ClientRect(wkAbout, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(icLogo, X1 + 14, Y1 + 14, 64);
  X := X1 + 96;
  OutBold(X, Y1 + 14, 'Pasdows 95', cBlack);
  OutText(X, Y1 + 32, 'Version ' + Version, cBlack);
  OutText(X, Y1 + 48, 'Copyright (C) 2026 Gladir.com', cBlack);
  WrapText(X, Y1 + 72, X2 - X - 8, L(
    'Clone de Windows 95 '#130'crit en Pascal (IO.SYS, compilateur WPC).',
    'Windows 95 clone written in Pascal (IO.SYS, WPC compiler).',
    'Windows 95-Klon in Pascal (IO.SYS, WPC-Compiler).',
    'Clone di Windows 95 scritto in Pascal (IO.SYS, compilatore WPC).',
    'Clon de Windows 95 escrito en Pascal (IO.SYS, compilador WPC).'),
    cBlack, True);
  HLine(X, X2 - 10, Y1 + 114, cGray);
  HLine(X, X2 - 10, Y1 + 115, cWhite);
  OutText(X, Y1 + 124, L('M'#130'moire : ', 'Memory: ', 'Speicher: ',
          'Memoria: ', 'Memoria: ') + RamText, cBlack);
  OutText(X, Y1 + 142, L('Processeur : ', 'Processor: ', 'Prozessor: ',
          'Processore: ', 'Procesador: ') + CpuName, cBlack);
  DrawDlgButtons(wkAbout);
End;

Procedure DrawMsg;
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkMsg, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(MsgIcon, X1 + 14, Y1 + 14, 32);
  WrapText(X1 + 62, Y1 + 18, 280, MsgText, cBlack, True);
  DrawDlgButtons(wkMsg);
End;

Procedure DrawRun;
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkRun, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(icRun, X1 + 12, Y1 + 12, 32);
  WrapText(X1 + 56, Y1 + 10, X2 - X1 - 64, L(
    'Tapez le nom d''un programme ou d''un document, et Pasdows ' +
    'l''ouvrira pour vous.',
    'Type the name of a program or document, and Pasdows will open ' +
    'it for you.',
    'Geben Sie den Namen eines Programms oder Dokuments ein.',
    'Digitare il nome del programma o documento da aprire.',
    'Escriba el nombre del programa o documento que desea abrir.'),
    cBlack, True);
  OutText(X1 + 12, Y1 + 68, L('Ouvrir :', 'Open:', #153'ffnen:', 'Apri:',
          'Abrir:'), cBlack);
  Sunken(X1 + 84, Y1 + 64, X2 - 12, Y1 + 87, cWhite);
  OutText(X1 + 89, Y1 + 68, RunText, cBlack);
  VLine(X1 + 89 + TextW(RunText), Y1 + 67, Y1 + 83, cBlack);
  DrawDlgButtons(wkRun);
End;

Function ShutText(I : Integer) : String;
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

Procedure DrawShutdown;
Var X1, Y1, X2, Y2, I : Integer;
Begin
  ClientRect(wkShutdown, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  DrawIcon(icShutdown, X1 + 12, Y1 + 14, 32);
  OutText(X1 + 60, Y1 + 12, L('Voulez-vous vraiment :',
          'Are you sure you want to:', 'M'#148'chten Sie wirklich:',
          'Si desidera:', #168'Est'#160' seguro de que desea:'), cBlack);
  For I := 0 To 2 Do
    RadioButton(X1 + 60, Y1 + 38 + I * 24, ShutText(I), I = ShutSel);
  DrawDlgButtons(wkShutdown);
End;

Function TipText(I : Integer) : String;
Begin
  Case I Mod 4 Of
    0 : TipText := L(
      'Pour ouvrir un programme, cliquez sur le bouton D'#130'marrer, puis ' +
      'sur Programmes.',
      'To open a program, click the Start button, and then click ' +
      'Programs.',
      'Um ein Programm zu '#148'ffnen, klicken Sie auf Start und dann auf ' +
      'Programme.',
      'Per aprire un programma, fare clic su Avvio, quindi su ' +
      'Programmi.',
      'Para abrir un programa, haga clic en Inicio y luego en ' +
      'Programas.');
    1 : TipText := L(
      'Tapez SET LANGUAGE=EN dans l''Invite MS-DOS pour passer '#133' ' +
      'l''anglais (GR, IT, SP ou FR).',
      'Type SET LANGUAGE=FR in the MS-DOS Prompt to switch to French ' +
      '(GR, IT, SP or EN).',
      'Geben Sie SET LANGUAGE=FR in der Eingabeaufforderung ein, um ' +
      'auf Franz'#148'sisch umzuschalten.',
      'Digitare SET LANGUAGE=FR nel prompt di MS-DOS per passare al ' +
      'francese.',
      'Escriba SET LANGUAGE=FR en el s'#161'mbolo del sistema para cambiar ' +
      'al franc'#130's.');
    2 : TipText := L(
      'Double-cliquez sur Poste de travail pour parcourir le CD-ROM.',
      'Double-click My Computer to browse the CD-ROM.',
      'Doppelklicken Sie auf Arbeitsplatz, um die CD-ROM zu durchsuchen.',
      'Fare doppio clic su Risorse del computer per esplorare il CD-ROM.',
      'Haga doble clic en Mi PC para explorar el CD-ROM.');
  Else
    TipText := L(
      'Alt+F4 ferme la fen'#136'tre active, Alt+Tab passe '#133' la ' +
      'fen'#136'tre ' +
      'suivante et Ctrl+'#144'chap ouvre le menu D'#130'marrer.',
      'Alt+F4 closes the active window, Alt+Tab switches windows and ' +
      'Ctrl+Esc opens the Start menu.',
      'Alt+F4 schlie'#225't das aktive Fenster, Alt+Tab wechselt das ' +
      'Fenster, Strg+Esc '#148'ffnet das Startmen'#129'.',
      'Alt+F4 chiude la finestra attiva, Alt+Tab cambia finestra e ' +
      'Ctrl+Esc apre il menu Avvio.',
      'Alt+F4 cierra la ventana activa, Alt+Tab cambia de ventana y ' +
      'Ctrl+Esc abre el men'#163' Inicio.');
  End;
End;

Procedure DrawWelcome;
Var X1, Y1, X2, Y2 : Integer;
Begin
  ClientRect(wkWelcome, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  OutText(X1 + 14, Y1 + 12, L('Bienvenue dans', 'Welcome to',
          'Willkommen bei', 'Benvenuti in', 'Bienvenido a'), cBlack);
  BigText(X1 + 14, Y1 + 30, 'Pasdows', cBlack, 2);
  BigText(X1 + 15, Y1 + 30, 'Pasdows', cBlack, 2);
  BigText(X1 + 14 + 7 * 16 + 8, Y1 + 30, '95', cWhite, 2);
  Sunken(X1 + 12, Y1 + 76, X2 - 146, Y2 - 12, cWhite);
  DrawIcon(icInfo, X1 + 22, Y1 + 88, 32);
  OutBold(X1 + 64, Y1 + 92, L('Le saviez-vous...', 'Did you know...',
          'Wussten Sie schon...', 'Lo sapevate...', #168'Sab'#161'a que...'),
          cBlack);
  WrapText(X1 + 64, Y1 + 118, X2 - 146 - X1 - 76, TipText(TipNo),
           cBlack, True);
  DrawDlgButtons(wkWelcome);
End;

Function HelpPara(I : Integer) : String;
Begin
  Case I Of
    0 : HelpPara := L(
      'Menu D'#130'marrer : cliquez sur D'#130'marrer (ou Ctrl+'#144'chap) ' +
      'pour lancer ' +
      'les programmes : Bloc-notes, Calculatrice, Paint, Invite MS-DOS.',
      'Start menu: click Start (or Ctrl+Esc) to run programs: Notepad, ' +
      'Calculator, Paint, MS-DOS Prompt.',
      'Startmen'#129': Klicken Sie auf Start (oder Strg+Esc), um Programme ' +
      'zu starten: Editor, Rechner, Paint, MS-DOS.',
      'Menu Avvio: fare clic su Avvio (o Ctrl+Esc) per avviare i ' +
      'programmi: Blocco note, Calcolatrice, Paint, MS-DOS.',
      'Men'#163' Inicio: haga clic en Inicio (o Ctrl+Esc) para ejecutar ' +
      'programas: Bloc de notas, Calculadora, Paint, MS-DOS.');
    1 : HelpPara := L(
      'Fen'#136'tres : faites glisser la barre de titre pour ' +
      'd'#130'placer une fen'#136'tre ; les boutons de droite la ' +
      'r'#130'duisent, l''agrandissent ou ' +
      'la ferment (Alt+F4). Alt+Tab change de fen'#136'tre.',
      'Windows: drag the title bar to move a window; the buttons on the ' +
      'right minimize, maximize or close it (Alt+F4). Alt+Tab switches ' +
      'windows.',
      'Fenster: Ziehen Sie die Titelleiste, um ein Fenster zu ' +
      'verschieben; die Schaltfl'#132'chen rechts minimieren, maximieren ' +
      'oder schlie'#225'en es (Alt+F4).',
      'Finestre: trascinare la barra del titolo per spostare una ' +
      'finestra; i pulsanti a destra la riducono, la ingrandiscono o la ' +
      'chiudono (Alt+F4).',
      'Ventanas: arrastre la barra de t'#161'tulo para mover una ventana; ' +
      'los botones de la derecha la minimizan, maximizan o cierran ' +
      '(Alt+F4).');
    2 : HelpPara := L(
      'Poste de travail : parcourez le CD-ROM et double-cliquez sur un ' +
      'fichier texte pour l''ouvrir dans le Bloc-notes.',
      'My Computer: browse the CD-ROM and double-click a text file to ' +
      'open it in Notepad.',
      'Arbeitsplatz: Durchsuchen Sie die CD-ROM und doppelklicken Sie ' +
      'auf eine Textdatei, um sie im Editor zu '#148'ffnen.',
      'Risorse del computer: esplorare il CD-ROM e fare doppio clic su ' +
      'un file di testo per aprirlo nel Blocco note.',
      'Mi PC: explore el CD-ROM y haga doble clic en un archivo de ' +
      'texto para abrirlo en el Bloc de notas.');
  Else
    HelpPara := L(
      'Langue : SET LANGUAGE=EN, GR, IT, SP ou FR dans AUTOEXEC.BAT ou ' +
      'dans l''Invite MS-DOS, ou Param'#138'tres r'#130'gionaux dans le ' +
      'Panneau ' +
      'de configuration.',
      'Language: SET LANGUAGE=FR, GR, IT, SP or EN in AUTOEXEC.BAT or ' +
      'in the MS-DOS Prompt, or Regional Settings in the Control Panel.',
      'Sprache: SET LANGUAGE=FR, EN, IT, SP oder GR in AUTOEXEC.BAT ' +
      'oder in der Eingabeaufforderung, oder L'#132'ndereinstellungen in ' +
      'der Systemsteuerung.',
      'Lingua: SET LANGUAGE=FR, EN, GR, SP o IT in AUTOEXEC.BAT o nel ' +
      'prompt di MS-DOS, oppure Impostazioni internazionali nel ' +
      'Pannello di controllo.',
      'Idioma: SET LANGUAGE=FR, EN, GR, IT o SP en AUTOEXEC.BAT o en ' +
      'el s'#161'mbolo del sistema, o Configuraci'#162'n regional en el ' +
      'Panel ' +
      'de control.');
  End;
End;

Procedure DrawHelp;
Var X1, Y1, X2, Y2, I, Y : Integer;
Begin
  ClientRect(wkHelp, X1, Y1, X2, Y2);
  Sunken(X1, Y1, X2, Y2, cWhite);
  DrawIcon(icHelp, X1 + 10, Y1 + 10, 32);
  OutBold(X1 + 52, Y1 + 18, WinTitle(wkHelp), cNavy);
  Y := Y1 + 54;
  For I := 0 To 3 Do
  Begin
    Bar(X1 + 12, Y + 6, X1 + 15, Y + 9, cNavy);
    Y := Y + 16 * WrapText(X1 + 22, Y, X2 - X1 - 34, HelpPara(I),
                           cBlack, True) + 8;
  End;
End;

{ Fond de la boite Date/Heure : calendrier et horloge }
Const
  SinTab : Array[0..15] Of Integer = (0, 105, 208, 309, 407, 500, 588,
           669, 743, 809, 866, 914, 951, 978, 995, 1000);

Function ISin(A : Integer) : Integer;
Begin
  A := A Mod 60;
  If A < 0 Then A := A + 60;
  If A <= 15 Then ISin := SinTab[A]
  Else If A <= 30 Then ISin := SinTab[30 - A]
  Else If A <= 45 Then ISin := -SinTab[A - 30]
  Else ISin := -SinTab[60 - A];
End;

Procedure ClockHand(CX, CY, A, R : Integer; C : Byte; Thick : Boolean);
Var X, Y : Integer;
Begin
  X := CX + Integer(LongInt(ISin(A)) * R Div 1000);
  Y := CY - Integer(LongInt(ISin(A + 15)) * R Div 1000);
  Line(CX, CY, X, Y, C);
  If Thick Then
  Begin
    Line(CX + 1, CY, X + 1, Y, C);
    Line(CX, CY + 1, X, Y + 1, C);
  End;
End;

Procedure DrawDateTime;
Var X1, Y1, X2, Y2, Y, M, D, H, Mi, S, I, DW, N, CX, CY, GX : Integer;
    T : String; C : Byte;
Begin
  ClientRect(wkDateTime, X1, Y1, X2, Y2);
  Bar(X1, Y1, X2, Y2, cSilver);
  RtcDate(Y, M, D);
  RtcTime(H, Mi, S);
  GroupBox(X1 + 8, Y1 + 12, X1 + 196, Y2 - 42, 'Date');
  T := MonthName(M) + ' ' + IntToStr(Y);
  OutCenter(X1 + 8, X1 + 196, Y1 + 22, T, cBlack);
  GX := X1 + 18;
  Sunken(GX - 4, Y1 + 42, GX + 7 * 24, Y1 + 42 + 7 * 18 + 6, cWhite);
  Bar(GX - 2, Y1 + 44, GX + 7 * 24 - 2, Y1 + 60, cGray);
  T := DayLetters;
  For I := 0 To 6 Do
    DrawChar(GX + I * 24 + 6, Y1 + 44, T[I + 1], cWhite);
  DW := DayOfWeek(Y, M, 1);
  N := DaysInMonth(Y, M);
  For I := 1 To N Do
  Begin
    CX := GX + ((DW + I - 1) Mod 7) * 24;
    CY := Y1 + 62 + ((DW + I - 1) Div 7) * 17;
    C := cBlack;
    If I = D Then
    Begin
      Bar(CX, CY, CX + 21, CY + 15, cNavy);
      C := cWhite;
    End;
    T := IntToStr(I);
    OutText(CX + 19 - TextW(T), CY, T, C);
  End;
  GroupBox(X1 + 206, Y1 + 12, X2 - 8, Y2 - 42,
           L('Heure', 'Time', 'Uhrzeit', 'Ora', 'Hora'));
  CX := (X1 + 206 + X2 - 8) Div 2;
  CY := Y1 + 90;
  Disc(CX, CY, 56, cWhite);
  Circle(CX, CY, 56, cGray);
  For I := 0 To 11 Do
  Begin
    N := ISin(I * 5);
    Bar(CX + Integer(LongInt(N) * 50 Div 1000) - 1,
        CY - Integer(LongInt(ISin(I * 5 + 15)) * 50 Div 1000) - 1,
        CX + Integer(LongInt(N) * 50 Div 1000) + 1,
        CY - Integer(LongInt(ISin(I * 5 + 15)) * 50 Div 1000) + 1,
        cTeal);
  End;
  ClockHand(CX, CY, (H Mod 12) * 5 + Mi Div 12, 30, cBlack, True);
  ClockHand(CX, CY, Mi, 44, cBlack, True);
  ClockHand(CX, CY, S, 48, cRed, False);
  T := Pad2(H) + ':' + Pad2(Mi) + ':' + Pad2(S);
  Sunken(CX - 40, Y1 + 156, CX + 40, Y1 + 178, cWhite);
  OutCenter(CX - 40, CX + 40, Y1 + 159, T, cBlack);
  DrawDlgButtons(wkDateTime);
End;

{ Dessin du contenu d'une fenetre }
Procedure DrawClient(K : Integer);
Begin
  Case K Of
    wkExplorer : DrawExplorer;
    wkNotepad : DrawNotepad;
    wkCalc : DrawCalc;
    wkDos : DrawDos;
    wkControl : DrawControl;
    wkDisplay : DrawDisplay;
    wkRegional : DrawRegional;
    wkSystem : DrawSystem;
    wkAbout : DrawAbout;
    wkRun : DrawRun;
    wkShutdown : DrawShutdown;
    wkRecycle : DrawRecycle;
    wkHelp : DrawHelp;
    wkMsg : DrawMsg;
    wkWelcome : DrawWelcome;
    wkPaint : DrawPaint;
    wkDateTime : DrawDateTime;
  End;
End;

{ ================================================================== }
{ Commandes                                                          }
{ ================================================================== }

Procedure LanguageChanged;
Begin
  If GuiOn Then
  Begin
    CloseMenus(0);
    RedrawAll;
  End;
End;

Procedure CloseApp(K : Integer);
Begin
  CloseWin(K);
  If K = wkShutdown Then RedrawAll;
  If K = wkPaint Then PaintDown := False;
End;

Procedure CalcReset;
Begin
  CalcDisp := '0'; CalcAcc := 0; CalcMem := 0; CalcOp := #0;
  CalcNew := True; CalcErr := False;
End;

Function RunProgram(Name : String) : Boolean;
Var U : String; P, I : Integer;
Begin
  RunProgram := True;
  U := UpStr(Trim(Name));
  P := Pos(' ', U);
  If P > 0 Then U := Copy(U, 1, P - 1);
  If Copy(U, 1, 3) = 'D:\' Then Delete(U, 1, 3);
  If (Copy(U, Length(U) - 3, 4) = '.EXE') Or
     (Copy(U, Length(U) - 3, 4) = '.COM') Then
    U := Copy(U, 1, Length(U) - 4);
  If (U = 'NOTEPAD') Or (U = 'EDIT') Then Execute(cmNotepad)
  Else If U = 'CALC' Then Execute(cmCalc)
  Else If (U = 'MSPAINT') Or (U = 'PBRUSH') Or (U = 'PAINT') Then
    Execute(cmPaint)
  Else If (U = 'COMMAND') Or (U = 'CMD') Or (U = 'DOSPRMPT') Then
    Execute(cmDos)
  Else If (U = 'EXPLORER') Or (U = 'WINFILE') Then Execute(cmExplorer)
  Else If U = 'CONTROL' Then Execute(cmControl)
  Else If (U = 'WINVER') Or (U = 'ABOUT') Then Execute(cmAbout)
  Else If (U = 'WINHELP') Or (U = 'HELP') Then Execute(cmHelp)
  Else If U = 'DESK.CPL' Then Execute(cmDisplay)
  Else If U = 'TIMEDATE.CPL' Then Execute(cmDateTime)
  Else If U = 'INTL.CPL' Then Execute(cmRegional)
  Else If U = 'SYSDM.CPL' Then Execute(cmSystem)
  Else If (U = 'WELCOME') Or (U = 'TOUR') Then Execute(cmWelcome)
  Else
  Begin
    I := CdFind(U);
    If I < 0 Then RunProgram := False
    Else If IsTextFile(U) Then NoteOpenFile(I)
    Else
      MessageBox(U, U + ' : ' + FmtNum(CdFiles[I].Size) + ' ' +
                 TxtBytes + '.', icInfo);
  End;
End;

Procedure DimScreen;
Begin
  HideCursor;
  SetArea(0, 0, ScrW - 1, ScrH - 1);
  Dither(0, 0, ScrW - 1, ScrH - 1, cBlack, 0);
End;

Procedure Execute(Cmd : Integer);
Var I : Integer;
Begin
  Case Cmd Of
    cmNotepad : OpenWin(wkNotepad);
    cmCalc : OpenWin(wkCalc);
    cmPaint : OpenWin(wkPaint);
    cmDos :
    Begin
      If Not Wins[wkDos].Open Then
      Begin
        ConInit(False);
        ConBanner;
      End;
      OpenWin(wkDos);
    End;
    cmComputer, cmExplorer :
    Begin
      If Cmd = cmComputer Then ExpView := 0 Else ExpView := 1;
      ExpSel := -1;
      If Wins[wkExplorer].Open Then
      Begin
        Activate(wkExplorer);
        WinRedraw(wkExplorer);
      End
      Else
        OpenWin(wkExplorer);
    End;
    cmControl : OpenWin(wkControl);
    cmDisplay :
    Begin
      DispSel := 7;
      For I := 0 To 7 Do
        If ColorOf(I) = DeskColor Then DispSel := I;
      OpenWin(wkDisplay);
    End;
    cmRegional :
    Begin
      RegSel := Ord(Language);
      OpenWin(wkRegional);
    End;
    cmSystem : OpenWin(wkSystem);
    cmDateTime : OpenWin(wkDateTime);
    cmHelp : OpenWin(wkHelp);
    cmRun :
    Begin
      RunText := '';
      If Wins[wkRun].Open Then WinRedraw(wkRun);
      OpenWin(wkRun);
    End;
    cmShutdown :
    Begin
      ShutSel := 0;
      CloseMenus(0);
      DimScreen;
      OpenWin(wkShutdown);
    End;
    cmAbout : OpenWin(wkAbout);
    cmRecycle : OpenWin(wkRecycle);
    cmWelcome : OpenWin(wkWelcome);
    cmNoteNew :
    Begin
      NoteReset;
      If Wins[wkNotepad].Open Then WinRedraw(wkNotepad)
      Else OpenWin(wkNotepad);
      TaskbarRedraw;
    End;
    cmNoteOpen :
    Begin
      ExpView := 1; ExpSel := -1;
      If Wins[wkExplorer].Open Then WinRedraw(wkExplorer);
      OpenWin(wkExplorer);
    End;
    cmClose :
    Begin
      I := TopWin;
      If I <> 0 Then CloseApp(I);
    End;
    cmNoteTime :
    Begin
      NoteInsStr(TimeStr + ' ' + DateStr);
      NoteVisible;
      ClientRedraw(wkNotepad);
    End;
    cmNoteClear :
    Begin
      NoteLen := 0; NoteCur := 0; NoteTop := 0; NoteLeft := 0;
      ClientRedraw(wkNotepad);
    End;
    cmExpOpen : ExpOpen(ExpSel);
    cmExpUp : ExpUp;
    cmPaintNew :
    Begin
      PaintClear;
      ClientRedraw(wkPaint);
    End;
    cmEmptyBin :
      MessageBox(WinTitle(wkRecycle), L('La Corbeille est d'#130'j'#133' vide.',
                 'The Recycle Bin is already empty.',
                 'Der Papierkorb ist bereits leer.',
                 'Il Cestino '#138' gi'#133' vuoto.',
                 'La Papelera ya est'#160' vac'#161'a.'), icInfo);
    cmReadme :
    Begin
      I := CdFind('LISEZMOI.TXT');
      If I < 0 Then I := CdFind('README.TXT');
      If I < 0 Then
        MessageBox('Pasdows', L('Fichier introuvable : LISEZMOI.TXT',
                   'File not found: LISEZMOI.TXT',
                   'Datei nicht gefunden: LISEZMOI.TXT',
                   'File non trovato: LISEZMOI.TXT',
                   'No se encontr'#162': LISEZMOI.TXT'), icError)
      Else
        NoteOpenFile(I);
    End;
  Else
    If Cmd >= cmDocBase Then NoteOpenFile(Cmd - cmDocBase);
  End;
End;

{ ================================================================== }
{ Ecrans de demarrage et d'arret                                     }
{ ================================================================== }

Const
  Bayer : Array[0..15] Of Byte = (0, 8, 2, 10, 12, 4, 14, 6,
                                  3, 11, 1, 9, 15, 7, 13, 5);

{ Ligne tramee : couleur C sur une proportion Density/16 des points }
Procedure DitherLine(Y : Integer; C : Byte; Density : Integer);
Var X, B : Integer; M : Byte; O : Word; D : Byte;
Begin
  M := 0;
  For X := 0 To 7 Do
    If Bayer[(Y And 3) * 4 + (X And 3)] < Density Then
      M := M Or ($80 Shr X);
  If M = 0 Then Exit;
  GcSet(8, M);
  O := Word(Y) * 80;
  For B := 0 To 79 Do
  Begin
    D := Mem[VSeg:O]; Mem[VSeg:O] := C;
    Inc(O);
  End;
  GcSet(8, $FF);
End;

Procedure Cloud(X, Y, S : Integer);
Begin
  Disc(X, Y + 4, S, cSilver);
  Disc(X + S, Y + 6, S - S Div 4, cSilver);
  Disc(X, Y, S, cWhite);
  Disc(X - S, Y + 4, S - S Div 3, cWhite);
  Disc(X + S, Y + 2, S - S Div 4, cWhite);
  Disc(X + S Div 2, Y - S Div 2, S - S Div 3, cWhite);
End;

Procedure DrawSky;
Var Y : Integer;
Begin
  FullClip;
  Bar(0, 0, ScrW - 1, ScrH - 1, cBlue);
  For Y := 0 To ScrH - 1 Do
    DitherLine(Y, cAqua, Y * 12 Div ScrH);
  Cloud(90, 90, 30);
  Cloud(530, 70, 26);
  Cloud(470, 330, 36);
  Cloud(120, 370, 28);
  Cloud(330, 420, 20);
End;

Procedure DrawLogo(Y : Integer);
Begin
  DrawIcon(icLogo, 96, Y, 96);
  BigText(212, Y + 14, 'Pasdows', cBlack, 4);
  BigText(208, Y + 10, 'Pasdows', cWhite, 4);
  BigText(212, Y + 78, '95', cNavy, 3);
  BigText(209, Y + 75, '95', cYellow, 3);
End;

Procedure Splash;
Var I, X, K : Integer; C : Byte;
Begin
  HideCursor;
  DrawSky;
  DrawLogo(140);
  OutBold(ScrW - 8 - TextW('Gladir.com'), 440, 'Gladir.com', cWhite);
  For I := 0 To 44 Do
  Begin
    For K := 0 To 7 Do
    Begin
      X := ((K * 80 + I * 12) Mod 640);
      Case K Mod 4 Of
        0 : C := cRed;
        1 : C := cYellow;
        2 : C := cLime;
      Else
        C := cBlue;
      End;
      Bar(X, ScrH - 10, Min(X + 79, ScrW - 1), ScrH - 1, C);
      If X + 79 > ScrW - 1 Then Bar(0, ScrH - 10, X + 79 - ScrW, ScrH - 1, C);
    End;
    WaitTicks(1);
  End;
End;

Procedure PowerOff;
Begin
  asm
    mov ax,5301h
    xor bx,bx
    int 15h
    mov ax,530Eh
    xor bx,bx
    mov cx,0102h
    int 15h
    mov ax,5307h
    mov bx,0001h
    mov cx,0003h
    int 15h
  end;
End;

Procedure Halt0;
Begin
  asm
    cli
  @h:
    hlt
    jmp @h
  end;
End;

Procedure Reboot;
Begin
  WaitTicks(2);
  Port[$64] := $FE;
  WaitTicks(9);
  asm
    int 19h
  end;
End;

Procedure ShutdownScreen;
Var A, B : String;
Begin
  HideCursor;
  DrawSky;
  DrawLogo(110);
  A := L('Veuillez patienter pendant l''arr'#136't de l''ordinateur.',
         'Please wait while your computer shuts down.',
         'Bitte warten, der Computer wird heruntergefahren.',
         'Attendere l''arresto del sistema.',
         'Espere mientras se apaga el equipo.');
  OutBold((ScrW - TextW(A)) Div 2 + 1, 253, A, cNavy);
  OutBold((ScrW - TextW(A)) Div 2, 252, A, cWhite);
  WaitTicks(30);
  FullClip;
  Bar(0, 0, ScrW - 1, ScrH - 1, cBlack);
  A := L('Vous pouvez maintenant', 'It''s now safe to turn off',
         'Sie k'#148'nnen den Computer', 'Ora '#138' possibile spegnere',
         'Ahora puede apagar');
  B := L(#130'teindre votre ordinateur.', 'your computer.',
         'jetzt ausschalten.', 'il computer.', 'el equipo.');
  BigText((ScrW - TextW(A) * 2) Div 2, 190, A, cMaroon, 2);
  BigText((ScrW - TextW(A) * 2) Div 2 - 2, 188, A, cYellow, 2);
  BigText((ScrW - TextW(B) * 2) Div 2, 232, B, cMaroon, 2);
  BigText((ScrW - TextW(B) * 2) Div 2 - 2, 230, B, cYellow, 2);
  GuiOn := False;
End;

{ ================================================================== }
{ Clavier et souris (controleur 8042 interroge, IRQ 1 et 12 masquees) }
{ ================================================================== }

Procedure KbcWaitIn;
Var I : Integer;
Begin
  For I := 1 To 30000 Do
    If (Port[$64] And 2) = 0 Then Exit;
End;

Function KbcRead : Integer;
Var I : Integer;
Begin
  KbcRead := -1;
  For I := 1 To 30000 Do
    If (Port[$64] And 1) <> 0 Then
    Begin
      KbcRead := Port[$60];
      Exit;
    End;
End;

Procedure KbcCmd(B : Byte);
Begin
  KbcWaitIn;
  Port[$64] := B;
End;

Procedure KbcData(B : Byte);
Begin
  KbcWaitIn;
  Port[$60] := B;
End;

Function MouseCmd(B : Byte) : Boolean;
Begin
  KbcCmd($D4);
  KbcData(B);
  MouseCmd := KbcRead = $FA;
End;

Procedure InitInput;
Var I, CB : Integer;
Begin
  asm
    cli
  end;
  Port[$21] := Port[$21] Or $02;
  Port[$A1] := Port[$A1] Or $10;
  asm
    sti
  end;
  For I := 1 To 32 Do
    If (Port[$64] And 1) <> 0 Then CB := Port[$60];
  KbcCmd($A8);
  KbcCmd($20);
  CB := KbcRead;
  If CB < 0 Then CB := $45;
  CB := CB And $DC;
  KbcCmd($60);
  KbcData(CB);
  MouseOk := MouseCmd($F6);
  If MouseOk Then MouseOk := MouseCmd($F4);
  MPhase := 0;
  MouseX := ScrW Div 2; MouseY := ScrH Div 2;
  LastMX := MouseX; LastMY := MouseY;
  MouseBtn := 0;
  KExt := False; KShift := False; KCtrl := False; KAlt := False;
  KCaps := False;
  EvHead := 0; EvTail := 0;
End;

Procedure PushEvent(Var E : TEvent);
Var N : Integer;
Begin
  N := (EvTail + 1) Mod 32;
  If N = EvHead Then Exit;
  EvQ[EvTail] := E;
  EvTail := N;
End;

Procedure KeyByte(B : Byte);
Var Sc : Byte; Rel : Boolean; E : TEvent; C : Char;
Begin
  If B = $E0 Then
  Begin
    KExt := True;
    Exit;
  End;
  Rel := (B And $80) <> 0;
  Sc := B And $7F;
  Case Sc Of
    $2A, $36 : If Not KExt Then KShift := Not Rel;
    $1D : KCtrl := Not Rel;
    $38 : KAlt := Not Rel;
    $3A : If Not Rel Then KCaps := Not KCaps;
  Else
    If Not Rel Then
    Begin
      C := #0;
      If KExt Then
      Begin
        If Sc = $1C Then C := #13
        Else If Sc = $35 Then C := '/';
      End
      Else If (Sc <= $39) And ((Sc < $47) Or (Sc > $53)) Then
      Begin
        If KShift Then C := KeyHi[Sc + 1] Else C := KeyLo[Sc + 1];
        If KCaps And (UpCase(C) >= 'A') And (UpCase(C) <= 'Z') Then
        Begin
          If KShift Then C := KeyLo[Sc + 1] Else C := KeyHi[Sc + 1];
        End;
      End
      Else If Sc = $4A Then C := '-'
      Else If Sc = $4E Then C := '+';
      If KCtrl And (C >= ' ') Then C := #0;
      E.Kind := evKey; E.Ch := C; E.Sc := Sc;
      E.Shift := KShift; E.Ctrl := KCtrl; E.Alt := KAlt;
      E.X := MouseX; E.Y := MouseY; E.Btn := 0;
      PushEvent(E);
    End;
  End;
  KExt := False;
End;

Procedure MouseByte(B : Byte);
Var DX, DY, I : Integer; NB : Byte; E : TEvent;
Begin
  If (MPhase = 0) And ((B And 8) = 0) Then Exit;
  MPack[MPhase] := B;
  Inc(MPhase);
  If MPhase < 3 Then Exit;
  MPhase := 0;
  DX := MPack[1];
  If (MPack[0] And $10) <> 0 Then DX := DX - 256;
  DY := MPack[2];
  If (MPack[0] And $20) <> 0 Then DY := DY - 256;
  If (MPack[0] And $C0) <> 0 Then
  Begin
    DX := 0; DY := 0;
  End;
  MouseX := MouseX + DX;
  MouseY := MouseY - DY;
  If MouseX < 0 Then MouseX := 0;
  If MouseY < 0 Then MouseY := 0;
  If MouseX > ScrW - 1 Then MouseX := ScrW - 1;
  If MouseY > ScrH - 1 Then MouseY := ScrH - 1;
  NB := MPack[0] And 3;
  For I := 0 To 1 Do
    If ((NB Xor MouseBtn) And (1 Shl I)) <> 0 Then
    Begin
      If (NB And (1 Shl I)) <> 0 Then E.Kind := evDown Else E.Kind := evUp;
      E.Btn := I + 1;
      E.X := MouseX; E.Y := MouseY;
      E.Ch := #0; E.Sc := 0;
      E.Shift := KShift; E.Ctrl := KCtrl; E.Alt := KAlt;
      PushEvent(E);
    End;
  MouseBtn := NB;
End;

Procedure PollInput;
Var St, B : Byte;
Begin
  St := Port[$64];
  While (St And 1) <> 0 Do
  Begin
    B := Port[$60];
    If (St And $20) <> 0 Then MouseByte(B) Else KeyByte(B);
    St := Port[$64];
  End;
End;

{ ================================================================== }
{ Mode MS-DOS plein ecran                                            }
{ ================================================================== }

Procedure TextConsole;
Var E : TEvent;
Begin
  TextMode;
  ConInit(True);
  ConBanner;
  ConRefresh;
  ConQuit := False;
  Repeat
    PollInput;
    While (EvHead <> EvTail) And Not ConQuit Do
    Begin
      E := EvQ[EvHead];
      EvHead := (EvHead + 1) Mod 32;
      If E.Kind = evKey Then ConKey(E);
    End;
  Until ConQuit;
End;

{ ================================================================== }
{ Evenements de l'interface graphique                                }
{ ================================================================== }

Function IsDouble(Target : Integer) : Boolean;
Begin
  If (Target = ClickTarget) And (Word(Ticks - ClickTick) <= 9) Then
  Begin
    IsDouble := True;
    ClickTarget := -999;
  End
  Else
  Begin
    IsDouble := False;
    ClickTarget := Target;
    ClickTick := Ticks;
  End;
End;

Procedure RedrawRect(X1, Y1, X2, Y2 : Integer);
Begin
  RedrawArea(X1, Y1, X2, Y2);
End;

Procedure RedrawDlgBtn(K, B : Integer);
Var X1, Y1, X2, Y2 : Integer; T : String;
Begin
  If B < 0 Then CapButton(K, -1 - B, X1, Y1, X2, Y2)
  Else If K = wkCalc Then CalcBtn(B, X1, Y1, X2, Y2)
  Else DlgBtn(K, B, X1, Y1, X2, Y2, T);
  WinPartRedraw(K, X1, Y1, X2, Y2);
End;

Procedure DoShutdown(Mode : Integer);
Begin
  CloseWin(wkShutdown);
  Case Mode Of
    0 :
    Begin
      ShutdownScreen;
      PowerOff;
      Halt0;
    End;
    1 :
    Begin
      ShutdownScreen;
      Reboot;
      Halt0;
    End;
  Else
    TextConsole;
    GraphMode;
    CurShown := False;
    If Wins[wkDos].Open Then
    Begin
      ConInit(False);
      ConBanner;
    End;
    RedrawAll;
  End;
End;

Procedure DlgAction(K, B : Integer);
Var S : String;
Begin
  Case K Of
    wkMsg, wkAbout, wkSystem, wkDateTime : CloseWin(K);
    wkWelcome :
      If B = 0 Then CloseWin(K)
      Else
      Begin
        Inc(TipNo);
        ClientRedraw(K);
      End;
    wkRun :
    Begin
      S := Trim(RunText);
      CloseWin(wkRun);
      If B = 2 Then Execute(cmExplorer)
      Else If (B = 0) And (S <> '') Then
        If Not RunProgram(S) Then
          MessageBox(WinTitle(wkRun), L('Impossible de trouver '#174' ',
                     'Cannot find "', '"', 'Impossibile trovare "',
                     'No se encuentra "') + S +
                     L(' '#175'. V'#130'rifiez le nom puis r'#130'essayez.',
                     '". Make sure you typed the name correctly.',
                     '" wurde nicht gefunden.', '". Verificare il nome.',
                     '". Compruebe el nombre.'), icError);
    End;
    wkShutdown :
      Case B Of
        0 : DoShutdown(ShutSel);
        1 : CloseApp(wkShutdown);
      Else
        CloseApp(wkShutdown);
        Execute(cmHelp);
      End;
    wkDisplay :
      Case B Of
        0 : Begin
              CloseWin(wkDisplay);
              DisplayApply;
            End;
        1 : CloseWin(wkDisplay);
      Else
        DisplayApply;
      End;
    wkRegional :
      Case B Of
        0 : Begin
              CloseWin(wkRegional);
              RegionalApply;
            End;
        1 : CloseWin(wkRegional);
      Else
        RegionalApply;
      End;
  End;
End;

Procedure ClientMouseDown(K, X, Y : Integer);
Var B, I, CX1, CY1, CX2, CY2, RX, RY : Integer;
Begin
  B := DlgBtnHit(K, X, Y);
  If B >= 0 Then
  Begin
    PressWin := K; PressBtn := B;
    RedrawDlgBtn(K, B);
    Exit;
  End;
  ClientRect(K, CX1, CY1, CX2, CY2);
  Case K Of
    wkExplorer :
      If InRect(X, Y, CX1 + 4, CY1 + 4, CX1 + 29, CY1 + 26) Then ExpUp
      Else
      Begin
        I := ExpHit(X, Y);
        If (I >= 0) And IsDouble(100 + I) Then ExpOpen(I)
        Else If I <> ExpSel Then
        Begin
          ExpSel := I;
          ClientRedraw(wkExplorer);
        End;
      End;
    wkControl :
    Begin
      I := CtlHit(X, Y);
      If (I >= 0) And IsDouble(200 + I) Then CtlOpen(I)
      Else If I <> CtlSel Then
      Begin
        CtlSel := I;
        ClientRedraw(wkControl);
      End;
    End;
    wkNotepad : NoteClick(X, Y);
    wkCalc :
    Begin
      I := CalcHit(X, Y);
      If I >= 0 Then
      Begin
        PressWin := wkCalc; PressBtn := I;
        RedrawDlgBtn(wkCalc, I);
      End;
    End;
    wkPaint : PaintClick(X, Y);
    wkDisplay :
      For I := 0 To 7 Do
      Begin
        ColorRadio(I, RX, RY);
        If InRect(X, Y, RX, RY, RX + 140, RY + 16) Then
        Begin
          DispSel := I;
          ClientRedraw(wkDisplay);
        End;
      End;
    wkRegional :
      For I := 0 To 4 Do
        If InRect(X, Y, CX1 + 22, CY1 + 74 + I * 20, CX2 - 20,
                  CY1 + 90 + I * 20) Then
        Begin
          RegSel := I;
          ClientRedraw(wkRegional);
        End;
    wkShutdown :
      For I := 0 To 2 Do
        If InRect(X, Y, CX1 + 60, CY1 + 38 + I * 24, CX2 - 8,
                  CY1 + 54 + I * 24) Then
        Begin
          ShutSel := I;
          ClientRedraw(wkShutdown);
        End;
    wkDateTime, wkWelcome, wkAbout : ;
  End;
End;

Procedure WinMouseDown(K, X, Y : Integer);
Var B, X1, Y1, X2, Y2, I, M : Integer; T : String;
Begin
  If K <> TopWin Then Activate(K);
  For B := 0 To CapButtons(K) - 1 Do
  Begin
    CapButton(K, B, X1, Y1, X2, Y2);
    If InRect(X, Y, X1, Y1, X2, Y2) Then
    Begin
      If (B = 1) And Not CanMax(K) Then Exit;
      PressWin := K; PressBtn := -1 - B;
      RedrawDlgBtn(K, PressBtn);
      Exit;
    End;
  End;
  If InRect(X, Y, Wins[K].X + 4, Wins[K].Y + 4, Wins[K].X + Wins[K].W - 5,
            Wins[K].Y + 21) Then
  Begin
    If IsDouble(3000 + K) Then
    Begin
      ToggleMax(K);
      Exit;
    End;
    If Wins[K].Max Then Exit;
    DragWin := K;
    DragDX := X - Wins[K].X; DragDY := Y - Wins[K].Y;
    DragX := Wins[K].X; DragY := Wins[K].Y;
    HideCursor;
    XorFrame(DragX, DragY, DragX + Wins[K].W - 1, DragY + Wins[K].H - 1);
    Exit;
  End;
  If (MenuBarCount(K) > 0) And InRect(X, Y, Wins[K].X + 4, Wins[K].Y + 23,
     Wins[K].X + Wins[K].W - 5, Wins[K].Y + 41) Then
  Begin
    For I := 0 To MenuBarCount(K) - 1 Do
    Begin
      MenuBarItem(K, I, T, M);
      X1 := MenuBarX(K, I);
      If (X >= X1) And (X < X1 + TextW(T) + 12) Then
      Begin
        OpenBarMenu(K, I);
        Exit;
      End;
    End;
    Exit;
  End;
  ClientRect(K, X1, Y1, X2, Y2);
  If InRect(X, Y, X1, Y1, X2, Y2) Then ClientMouseDown(K, X, Y);
End;

Procedure TaskbarClick(X, Y : Integer);
Var I, X1, X2, K : Integer;
Begin
  If InRect(X, Y, 2, TaskY + 4, StartW + 1, TaskY + 25) Then
  Begin
    OpenStartMenu;
    Exit;
  End;
  If X >= TrayX Then
  Begin
    If IsDouble(4000) Then Execute(cmDateTime);
    Exit;
  End;
  For I := 0 To TaskCnt - 1 Do
  Begin
    TaskBtn(I, X1, X2);
    If (X >= X1) And (X <= X2) Then
    Begin
      K := TaskOrd[I];
      If (K = TopWin) And Not IsModal(K) Then MinimizeWin(K)
      Else Activate(K);
      Exit;
    End;
  End;
End;

Procedure DeskClick(X, Y : Integer);
Var I, Old : Integer;
Begin
  I := DeskHit(X, Y);
  If (I >= 0) And IsDouble(1000 + I) Then
  Begin
    Execute(DeskCmd(I));
    Exit;
  End;
  If I <> DeskSel Then
  Begin
    Old := DeskSel;
    DeskSel := I;
    DeskRedrawIcon(Old);
    DeskRedrawIcon(I);
  End;
End;

Procedure HandleDown(Const E : TEvent);
Var I, Lv, K, T : Integer; WasStart : Boolean;
Begin
  If E.Btn <> 1 Then Exit;
  If MenuDepth > 0 Then
  Begin
    I := MenuHit(E.X, E.Y, Lv);
    If I >= 0 Then
    Begin
      MenuChoose(Lv, I);
      Exit;
    End;
    If I = -2 Then Exit;
    WasStart := MenuOwner = 0;
    CloseMenus(0);
    If WasStart And InRect(E.X, E.Y, 2, TaskY + 4, StartW + 1,
                           TaskY + 25) Then Exit;
    Exit;
  End;
  T := TopWin;
  If (T <> 0) And IsModal(T) Then
    If Not InRect(E.X, E.Y, Wins[T].X, Wins[T].Y, Wins[T].X + Wins[T].W - 1,
                  Wins[T].Y + Wins[T].H - 1) Then
    Begin
      Beep;
      Exit;
    End;
  If E.Y >= TaskY Then
  Begin
    TaskbarClick(E.X, E.Y);
    Exit;
  End;
  For I := ZCnt - 1 DownTo 0 Do
  Begin
    K := ZOrd[I];
    If Wins[K].Open And Not Wins[K].Min Then
      If InRect(E.X, E.Y, Wins[K].X, Wins[K].Y, Wins[K].X + Wins[K].W - 1,
                Wins[K].Y + Wins[K].H - 1) Then
      Begin
        WinMouseDown(K, E.X, E.Y);
        Exit;
      End;
  End;
  DeskClick(E.X, E.Y);
End;

Procedure HandleUp(Const E : TEvent);
Var K, B, X1, Y1, X2, Y2 : Integer;
Begin
  If E.Btn <> 1 Then Exit;
  If DragWin <> 0 Then
  Begin
    K := DragWin;
    DragWin := 0;
    HideCursor;
    XorFrame(DragX, DragY, DragX + Wins[K].W - 1, DragY + Wins[K].H - 1);
    If (DragX <> Wins[K].X) Or (DragY <> Wins[K].Y) Then
    Begin
      X1 := Wins[K].X; Y1 := Wins[K].Y;
      X2 := X1 + Wins[K].W - 1; Y2 := Y1 + Wins[K].H - 1;
      Wins[K].X := DragX; Wins[K].Y := DragY;
      RedrawArea(X1, Y1, X2, Y2);
      WinRedraw(K);
    End;
    Exit;
  End;
  If PaintDown Then
  Begin
    PaintDown := False;
    Exit;
  End;
  If PressWin <> 0 Then
  Begin
    K := PressWin; B := PressBtn;
    PressWin := 0;
    If Not Wins[K].Open Then Exit;
    RedrawDlgBtn(K, B);
    If B < 0 Then
    Begin
      CapButton(K, -1 - B, X1, Y1, X2, Y2);
      If InRect(E.X, E.Y, X1, Y1, X2, Y2) Then
        Case -1 - B Of
          0 : CloseApp(K);
          1 : ToggleMax(K);
          2 : MinimizeWin(K);
        End;
    End
    Else If K = wkCalc Then
    Begin
      If CalcHit(E.X, E.Y) = B Then CalcBtnPress(B);
    End
    Else If DlgBtnHit(K, E.X, E.Y) = B Then DlgAction(K, B);
  End;
End;

Procedure HandleMove;
Var NX, NY, Lv, I, K : Integer;
Begin
  LastMX := MouseX; LastMY := MouseY;
  If DragWin <> 0 Then
  Begin
    K := DragWin;
    NX := MouseX - DragDX; NY := MouseY - DragDY;
    If NY < 0 Then NY := 0;
    If NY > TaskY - 24 Then NY := TaskY - 24;
    If NX < 40 - Wins[K].W Then NX := 40 - Wins[K].W;
    If NX > ScrW - 40 Then NX := ScrW - 40;
    If (NX <> DragX) Or (NY <> DragY) Then
    Begin
      HideCursor;
      XorFrame(DragX, DragY, DragX + Wins[K].W - 1, DragY + Wins[K].H - 1);
      DragX := NX; DragY := NY;
      XorFrame(DragX, DragY, DragX + Wins[K].W - 1, DragY + Wins[K].H - 1);
    End;
  End
  Else If PaintDown Then PaintMove(MouseX, MouseY)
  Else If MenuDepth > 0 Then
  Begin
    I := MenuHit(MouseX, MouseY, Lv);
    If I >= 0 Then SetMenuHot(Lv, I);
  End;
End;

Procedure MenuKey(Const E : TEvent);
Var Lv, I, N, Cmd, Sub, Ic : Integer; T : String;
Begin
  Lv := MenuDepth - 1;
  N := Menus[Lv].Count;
  Case E.Sc Of
    scEsc : CloseMenus(Lv);
    scUp, scDown :
    Begin
      I := Menus[Lv].Hot;
      Repeat
        If E.Sc = scUp Then I := (I - 1 + N) Mod N Else I := (I + 1) Mod N;
        MenuItem(Menus[Lv].Id, I, T, Cmd, Sub, Ic);
      Until T <> '-';
      Menus[Lv].Hot := I;
      RedrawArea(Menus[Lv].X, Menus[Lv].Y, Menus[Lv].X + Menus[Lv].W - 1,
                 Menus[Lv].Y + Menus[Lv].H - 1);
    End;
    scRight, scEnter :
      If Menus[Lv].Hot >= 0 Then
      Begin
        MenuItem(Menus[Lv].Id, Menus[Lv].Hot, T, Cmd, Sub, Ic);
        If Sub <> 0 Then
        Begin
          SetMenuHot(Lv, Menus[Lv].Hot);
          If MenuDepth > Lv + 1 Then
          Begin
            Menus[Lv + 1].Hot := 0;
            RedrawArea(Menus[Lv + 1].X, Menus[Lv + 1].Y,
                       Menus[Lv + 1].X + Menus[Lv + 1].W - 1,
                       Menus[Lv + 1].Y + Menus[Lv + 1].H - 1);
          End;
        End
        Else If E.Sc = scEnter Then MenuChoose(Lv, Menus[Lv].Hot);
      End;
    scLeft : If Lv > 0 Then CloseMenus(Lv);
  End;
End;

Procedure DeskKey(Const E : TEvent);
Var Old : Integer;
Begin
  Old := DeskSel;
  Case E.Sc Of
    scUp : If DeskSel > 0 Then Dec(DeskSel);
    scDown : If DeskSel < DeskCount - 1 Then Inc(DeskSel);
    scLeft : If DeskSel >= 6 Then DeskSel := DeskSel - 6;
    scRight : If DeskSel + 6 < DeskCount Then DeskSel := DeskSel + 6;
    scEnter : If DeskSel >= 0 Then Execute(DeskCmd(DeskSel));
  Else
    Exit;
  End;
  If DeskSel < 0 Then DeskSel := 0;
  If Old <> DeskSel Then
  Begin
    DeskRedrawIcon(Old);
    DeskRedrawIcon(DeskSel);
  End;
End;

Procedure GridKey(Const E : TEvent; Var Sel : Integer; N, Cols : Integer;
                  K : Integer);
Var Old : Integer;
Begin
  Old := Sel;
  Case E.Sc Of
    scLeft : Dec(Sel);
    scRight : Inc(Sel);
    scUp : Sel := Sel - Cols;
    scDown : Sel := Sel + Cols;
  Else
    Exit;
  End;
  If Sel < 0 Then Sel := 0;
  If Sel >= N Then Sel := N - 1;
  If Old <> Sel Then ClientRedraw(K);
End;

Procedure WinKey(K : Integer; Const E : TEvent);
Begin
  Case K Of
    wkNotepad : NoteKey(E);
    wkCalc : CalcKey(E);
    wkDos :
    Begin
      ConQuit := False;
      ConKey(E);
      If ConQuit Then CloseApp(wkDos);
    End;
    wkRun :
    Begin
      If E.Sc = scEnter Then DlgAction(wkRun, 0)
      Else If E.Sc = scEsc Then CloseWin(wkRun)
      Else
      Begin
        If E.Sc = scBack Then Delete(RunText, Length(RunText), 1)
        Else If (E.Ch >= ' ') And (Length(RunText) < 30) Then
          RunText := RunText + E.Ch;
        ClientRedraw(wkRun);
      End;
    End;
    wkExplorer :
      If E.Sc = scEnter Then ExpOpen(ExpSel)
      Else If E.Sc = scBack Then ExpUp
      Else GridKey(E, ExpSel, ExpCount, ExpCols, wkExplorer);
    wkControl :
      If E.Sc = scEnter Then CtlOpen(CtlSel)
      Else GridKey(E, CtlSel, 4, 4, wkControl);
    wkMsg, wkAbout, wkWelcome, wkSystem, wkDateTime :
      If (E.Sc = scEnter) Or (E.Sc = scEsc) Then DlgAction(K, 0);
    wkDisplay, wkRegional, wkShutdown :
      If E.Sc = scEnter Then DlgAction(K, 0)
      Else If E.Sc = scEsc Then DlgAction(K, 1)
      Else If (E.Sc = scUp) Or (E.Sc = scDown) Then
      Begin
        If K = wkDisplay Then
          GridKey(E, DispSel, 8, 1, K)
        Else If K = wkRegional Then
          GridKey(E, RegSel, 5, 1, K)
        Else
          GridKey(E, ShutSel, 3, 1, K);
      End;
  End;
End;

Procedure HandleKey(Const E : TEvent);
Var T, I : Integer;
Begin
  If (E.Sc = scWin) Or (E.Ctrl And (E.Sc = scEsc)) Then
  Begin
    If MenuDepth > 0 Then CloseMenus(0)
    Else If Not IsModal(TopWin) Then
    Begin
      OpenStartMenu;
      Menus[0].Hot := 0;
      RedrawArea(Menus[0].X, Menus[0].Y, Menus[0].X + Menus[0].W - 1,
                 Menus[0].Y + Menus[0].H - 1);
    End;
    Exit;
  End;
  If MenuDepth > 0 Then
  Begin
    MenuKey(E);
    Exit;
  End;
  T := TopWin;
  If E.Alt And (E.Sc = scF4) Then
  Begin
    If T <> 0 Then
    Begin
      If T = wkShutdown Then DlgAction(T, 1) Else CloseApp(T);
    End
    Else
      Execute(cmShutdown);
    Exit;
  End;
  If E.Alt And (E.Sc = scTab) Then
  Begin
    If (ZCnt > 1) And Not IsModal(T) Then
    Begin
      I := ZOrd[0];
      Activate(I);
    End;
    Exit;
  End;
  If (E.Sc = scF1) And Not IsModal(T) Then
  Begin
    Execute(cmHelp);
    Exit;
  End;
  If T = 0 Then DeskKey(E) Else WinKey(T, E);
End;

Procedure Periodic;
Var H, M, S : Integer;
Begin
  If Word(Ticks - ClickTick) > 30000 Then ClickTick := Ticks - 100;
  RtcTime(H, M, S);
  If M <> LastMin Then
  Begin
    LastMin := M;
    RedrawArea(TrayX - 40, TaskY, ScrW - 1, ScrH - 1);
  End;
  If (S <> LastSec) Then
  Begin
    LastSec := S;
    If TopWin = wkDateTime Then
      WinPartRedraw(wkDateTime, Wins[wkDateTime].X + 214,
                    Wins[wkDateTime].Y + 50,
                    Wins[wkDateTime].X + Wins[wkDateTime].W - 16,
                    Wins[wkDateTime].Y + 205);
  End;
End;

Procedure GuiLoop;
Var E : TEvent; T : Word;
Begin
  T := Ticks;
  Repeat
    PollInput;
    While EvHead <> EvTail Do
    Begin
      E := EvQ[EvHead];
      EvHead := (EvHead + 1) Mod 32;
      Case E.Kind Of
        evKey : HandleKey(E);
        evDown : HandleDown(E);
        evUp : HandleUp(E);
      End;
      PollInput;
    End;
    If (MouseX <> LastMX) Or (MouseY <> LastMY) Then HandleMove;
    If Word(Ticks - T) >= 4 Then
    Begin
      T := Ticks;
      Periodic;
    End;
    If CurShown And ((CurX <> MouseX) Or (CurY <> MouseY)) Then
      HideCursor;
    ShowCursor;
  Until QuitGui <> 0;
End;

{ ================================================================== }
{ Ecran de demarrage texte et menu de demarrage (F8)                 }
{ ================================================================== }

Procedure TWrite(X, Y : Integer; Const S : String; A : Byte);
Var I : Integer;
Begin
  For I := 1 To Length(S) Do
    MemW[$B800:((Y * 80) + X + I - 1) * 2] := Ord(S[I]) Or (Word(A) Shl 8);
End;

Procedure TClear;
Var I : Integer;
Begin
  For I := 0 To 80 * 25 - 1 Do MemW[$B800:I * 2] := $0720;
End;

Procedure TCursor(X, Y : Integer);
Var R, C : Byte;
Begin
  R := Y; C := X;
  asm
    mov ah,02h
    xor bh,bh
    mov dh,R
    mov dl,C
    int 10h
  end;
End;

{ Touche du BIOS (INT 16h) : 0 si aucune ; scan * 256 + ascii }
Function BiosKey : Word;
Var K : Word;
Begin
  asm
    mov ah,01h
    int 16h
    mov ax,0
    jz @none
    mov ah,00h
    int 16h
  @none:
    mov K,ax
  end;
  BiosKey := K;
End;

Function BootItem(I : Integer) : String;
Begin
  Case I Of
    0 : BootItem := 'Normal';
    1 : BootItem := L('Mode sans '#130'chec', 'Safe mode',
                      'Abgesicherter Modus', 'Modalit'#133' provvisoria',
                      'Modo a prueba de fallos');
    2 : BootItem := L('Invite de commandes seulement',
                      'Command prompt only', 'Nur Eingabeaufforderung',
                      'Solo prompt dei comandi',
                      'S'#162'lo s'#161'mbolo del sistema');
  Else
    BootItem := L('Red'#130'marrer l''ordinateur', 'Restart the computer',
                  'Computer neu starten', 'Riavvia il computer',
                  'Reiniciar el equipo');
  End;
End;

Function BootMenu : Integer;
Var Sel, I : Integer; K : Word; S : String; A : Byte;
Begin
  Sel := 0;
  Repeat
    TClear;
    S := L('Menu de d'#130'marrage de Pasdows 95', 'Pasdows 95 Startup Menu',
           'Startmen'#129' von Pasdows 95', 'Menu di avvio di Pasdows 95',
           'Men'#163' de inicio de Pasdows 95');
    TWrite((80 - Length(S)) Div 2, 2, S, $07);
    For I := 1 To Length(S) Do TWrite((80 - Length(S)) Div 2 + I - 1, 3,
                                      '=', $07);
    For I := 0 To 3 Do
    Begin
      If I = Sel Then A := $70 Else A := $07;
      TWrite(14, 6 + I, ' ' + IntToStr(I + 1) + '. ' + BootItem(I) + ' ',
             A);
    End;
    S := L('Entrez votre choix : ', 'Enter a choice: ',
           'Bitte w'#132'hlen: ', 'Immettere una scelta: ',
           'Escriba su elecci'#162'n: ') + IntToStr(Sel + 1);
    TWrite(14, 12, S, $07);
    TWrite(0, 23, L('F5=Mode sans '#130'chec  Maj+F5=Invite de commandes',
           'F5=Safe mode  Shift+F5=Command prompt',
           'F5=Abgesichert  Umschalt+F5=Eingabeaufforderung',
           'F5=Provvisoria  Maiusc+F5=Prompt dei comandi',
           'F5=A prueba de fallos  May'#163's+F5=S'#161'mbolo del sistema'),
           $07);
    TCursor(14 + Length(S), 12);
    Repeat
      K := BiosKey;
    Until K <> 0;
    Case Hi(K) Of
      $48 : Sel := (Sel + 3) Mod 4;
      $50 : Sel := (Sel + 1) Mod 4;
      $3F : Begin BootMenu := 1; Exit End;
      $58 : Begin BootMenu := 2; Exit End;
      $1C : Begin BootMenu := Sel; Exit End;
    Else
      If (Lo(K) >= Ord('1')) And (Lo(K) <= Ord('4')) Then
        Sel := Lo(K) - Ord('1');
    End;
  Until False;
End;

Function BootScreen : Integer;
Var T : Word; K : Word; S : String;
Begin
  TextMode;
  TClear;
  S := L('D'#130'marrage de Pasdows 95...', 'Starting Pasdows 95...',
         'Pasdows 95 wird gestartet...', 'Avvio di Pasdows 95 in corso...',
         'Iniciando Pasdows 95...');
  TWrite(0, 0, S, $07);
  TCursor(0, 1);
  BootScreen := 0;
  If OptBootMenu Then
  Begin
    BootScreen := BootMenu;
    Exit;
  End;
  T := Ticks;
  While Word(Ticks - T) < Word(OptBootDelay * 18) Do
  Begin
    K := BiosKey;
    Case Hi(K) Of
      $42 : Begin BootScreen := BootMenu; Exit End;
      $3F : Begin BootScreen := 1; Exit End;
      $58 : Begin BootScreen := 2; Exit End;
    End;
  End;
End;

{ ================================================================== }
{ Chargement du noyau 32 bits VMM32.VXD (mode protege)               }
{ ================================================================== }

{ Comme le IO.SYS de Windows 95, IO.SYS prepare la machine puis passe
  la main au gestionnaire de machine virtuelle 32 bits VMM32.VXD
  (KERNEL/VMM32.PAS, WPC -CVMM32) qui contient l'interface graphique
  256 couleurs et le sous-systeme Win32 (programmes Windows 95). Le
  mode sans echec reste l'interface 16 couleurs d'IO.SYS.

  Bloc d'information pour VMM32 (0000:0500) :
    +00 mot 'PW'           +02 unite d'amorcage   +03 langue
    +04 LBA racine CD      +08 taille racine      +0C memoire video
    +10 octets par ligne   +12 largeur            +14 hauteur
    +16 bits par point     +18 memoire etendue (Ko)
    +1C base du noyau      +20 taille de l'image  +24 point d'entree
    +28 police 8x16 (0000:2000)  +2C environnement (0000:3000)
    +30 options : bit 0 ecran d'accueil, bit 1 son
  GDT temporaire en 0000:0A00, GDTR en 0000:0A20, transition 32 bits en
  0000:0A40, zone de transit du fichier en 00400000h. }

Const
  VInfo     = $0500;
  VGdt      = $0A00;
  VGdtr     = $0A20;
  VTramp    = $0A40;
  VFont     = $2000;
  VEnv      = $3000;
  VStaging  = $00400000;
  CmosDosFlag = $7E;

Var
  MoveGdt   : Array[0..47] Of Byte;
  VbeBuf    : Array[0..255] Of Byte;
  VEntry    : LongInt;

Function CmosRead(R : Byte) : Byte;
Begin
  Port[$70] := R;
  CmosRead := Port[$71];
End;

Procedure CmosWrite(R, V : Byte);
Begin
  Port[$70] := R;
  Port[$71] := V;
End;

Procedure SetDesc(Ofs : Integer; Base : LongInt);
Begin
  MoveGdt[Ofs] := $FF; MoveGdt[Ofs + 1] := $FF;
  MoveGdt[Ofs + 2] := Base And $FF;
  MoveGdt[Ofs + 3] := (Base Shr 8) And $FF;
  MoveGdt[Ofs + 4] := (Base Shr 16) And $FF;
  MoveGdt[Ofs + 5] := $93;
  MoveGdt[Ofs + 6] := 0;
  MoveGdt[Ofs + 7] := (Base Shr 24) And $FF;
End;

{ Copie en memoire etendue (INT 15h AH=87h), Bytes <= 65536 }
Function ExtCopy(Src, Dst, Bytes : LongInt) : Boolean;
Var I : Integer; Words : Word; Err : Byte;
Begin
  For I := 0 To 47 Do MoveGdt[I] := 0;
  SetDesc(16, Src);
  SetDesc(24, Dst);
  Words := Word((Bytes + 1) Div 2);
  asm
    push es
    push si
    push ds
    pop es
    lea si,MoveGdt
    mov cx,Words
    mov ah,87h
    int 15h
    mov al,0
    adc al,0
    mov Err,al
    pop si
    pop es
  end;
  ExtCopy := Err = 0;
End;

Function BigCopy(Src, Dst, Bytes : LongInt) : Boolean;
Var N : LongInt;
Begin
  BigCopy := False;
  While Bytes > 0 Do
  Begin
    If Bytes > 16384 Then N := 16384 Else N := Bytes;
    If Not ExtCopy(Src, Dst, N) Then Exit;
    Src := Src + N; Dst := Dst + N; Bytes := Bytes - N;
  End;
  BigCopy := True;
End;

Procedure EnableA20;
Begin
  asm
    mov ax,2401h
    int 15h
    in al,92h
    or al,2
    and al,0FEh
    out 92h,al
  end;
End;

{ Memoire etendue en Ko (INT 15h E801h, sinon 88h) }
Function ExtMemKb : LongInt;
Var W1, W2 : Word; Ok : Byte;
Begin
  W1 := 0; W2 := 0; Ok := 0;
  asm
    mov ax,0E801h
    int 15h
    jc @no801
    or ax,ax
    jnz @use
    mov ax,cx
    mov bx,dx
  @use:
    mov W1,ax
    mov W2,bx
    mov Ok,1
  @no801:
  end;
  If Ok <> 0 Then ExtMemKb := LongInt(W1) + LongInt(W2) * 64
  Else ExtMemKb := MemExt;
End;

Function VGetD(Seg, Ofs : Word) : LongInt;
Begin
  VGetD := LongInt(MemW[Seg:Ofs]) + LongInt(MemW[Seg:Ofs + 2]) * 65536;
End;

Procedure PutInfoD(Ofs : Word; V : LongInt);
Begin
  MemW[0:VInfo + Ofs] := Word(V);
  MemW[0:VInfo + Ofs + 2] := Word(V Shr 16);
End;

{ Mode VESA 101h (640x480, 256 couleurs) avec memoire lineaire }
Function VbeSetup : Boolean;
Var R : Word; Lfb : LongInt; I : Integer;
Begin
  VbeSetup := False;
  For I := 0 To 255 Do VbeBuf[I] := 0;
  asm
    push es
    push di
    push ds
    pop es
    lea di,VbeBuf
    mov ax,4F01h
    mov cx,0101h
    int 10h
    mov R,ax
    pop di
    pop es
  end;
  If R <> $004F Then Exit;
  If (VbeBuf[0] And $81) <> $81 Then Exit;
  Lfb := LongInt(VbeBuf[$28]) + LongInt(VbeBuf[$29]) Shl 8 +
         LongInt(VbeBuf[$2A]) Shl 16 + LongInt(VbeBuf[$2B]) Shl 24;
  If Lfb = 0 Then Exit;
  asm
    mov ax,4F02h
    mov bx,4101h
    int 10h
    mov R,ax
  end;
  If R <> $004F Then Exit;
  PutInfoD($0C, Lfb);
  MemW[0:VInfo + $10] := VbeBuf[$10] + Word(VbeBuf[$11]) Shl 8;
  MemW[0:VInfo + $12] := 640;
  MemW[0:VInfo + $14] := 480;
  MemW[0:VInfo + $16] := 8;
  VbeSetup := True;
End;

{ Police 8x16 du BIOS recopiee en 0000:2000 }
Procedure CopyFont;
Var FSg, FOf, I : Word;
Begin
  asm
    push bp
    push es
    mov ax,1130h
    mov bh,6
    int 10h
    mov ax,es
    mov dx,bp
    pop es
    pop bp
    mov FSg,ax
    mov FOf,dx
  end;
  For I := 0 To 4095 Do Mem[0:VFont + I] := Mem[FSg:FOf + I];
End;

{ Environnement (chaines ASCIIZ NOM=VALEUR, terminees par 0) }
Procedure CopyEnv;
Var I, J : Integer; P : Word;
Begin
  P := VEnv;
  For I := 1 To EnvCnt Do
    If P + Length(EnvStr[I]) + 2 < VEnv + 2040 Then
    Begin
      For J := 1 To Length(EnvStr[I]) Do
      Begin
        Mem[0:P] := Ord(EnvStr[I][J]);
        Inc(P);
      End;
      Mem[0:P] := 0;
      Inc(P);
    End;
  Mem[0:P] := 0;
End;

Procedure PutB(Var P : Word; B : Byte);
Begin
  Mem[0:P] := B;
  Inc(P);
End;

Procedure PutDW(Var P : Word; D : LongInt);
Begin
  PutB(P, D And $FF); PutB(P, (D Shr 8) And $FF);
  PutB(P, (D Shr 16) And $FF); PutB(P, (D Shr 24) And $FF);
End;

{ GDT plate et code de transition 32 bits (pile 00090000h) }
Procedure BuildGdt;
Var P : Word;
Begin
  P := VGdt;
  PutDW(P, 0); PutDW(P, 0);
  PutDW(P, $0000FFFF); PutDW(P, $00CF9A00);
  PutDW(P, $0000FFFF); PutDW(P, $00CF9200);
  MemW[0:VGdtr] := 3 * 8 - 1;
  MemW[0:VGdtr + 2] := VGdt;
  MemW[0:VGdtr + 4] := 0;
  P := VTramp;
  PutB(P, $66); PutB(P, $B8); PutB(P, $10); PutB(P, $00);
  PutB(P, $8E); PutB(P, $D8);
  PutB(P, $8E); PutB(P, $C0);
  PutB(P, $8E); PutB(P, $E0);
  PutB(P, $8E); PutB(P, $E8);
  PutB(P, $8E); PutB(P, $D0);
  PutB(P, $BC); PutDW(P, $00090000);
  PutB(P, $BB); PutDW(P, VInfo);
  PutB(P, $B8); PutDW(P, VEntry);
  PutB(P, $FF); PutB(P, $E0);
End;

{ Lire VMM32.VXD et le placer a son adresse ; False si impossible }
Function LoadVmm32 : Boolean;
Var Idx, I, NSect, OptSize : Integer; Sector, NSectors : LongInt;
    PeOfs, SO : Word; KBase, KImg, KHdr, VSize, VAddr, RawSize,
    RawPtr, N : LongInt;
Begin
  LoadVmm32 := False;
  Idx := CdFind('VMM32.VXD');
  If Idx < 0 Then Exit;
  NSectors := (CdFiles[Idx].Size + 2047) Div 2048;
  If NSectors > 3072 Then Exit;
  Sector := 0;
  While Sector < NSectors Do
  Begin
    If Not CdRead(CdFiles[Idx].Lba + Sector, CdSeg) Then Exit;
    If Not ExtCopy(LongInt(CdSeg) * 16, VStaging + Sector * 2048, 2048)
    Then Exit;
    If (Sector And 15) = 0 Then TWrite(Integer(Sector Div 16) Mod 80, 2,
                                       #219, $07);
    Inc(Sector);
  End;
  If Not ExtCopy(VStaging, LongInt(TmpSeg) * 16, 4096) Then Exit;
  If MemW[TmpSeg:0] <> $5A4D Then Exit;
  PeOfs := MemW[TmpSeg:$3C];
  If (MemW[TmpSeg:PeOfs] <> $4550) Or (MemW[TmpSeg:PeOfs + 4] <> $014C)
  Then Exit;
  NSect := MemW[TmpSeg:PeOfs + 6];
  OptSize := MemW[TmpSeg:PeOfs + 20];
  VEntry := VGetD(TmpSeg, PeOfs + 24 + 16);
  KBase := VGetD(TmpSeg, PeOfs + 24 + 28);
  KImg := VGetD(TmpSeg, PeOfs + 24 + 56);
  KHdr := VGetD(TmpSeg, PeOfs + 24 + 60);
  If (KBase < $00100000) Or (KBase + KImg > VStaging) Then Exit;
  { mise a zero de l'image (tampon de zeros en CdSeg) }
  For I := 0 To 1023 Do MemW[CdSeg:I * 2] := 0;
  N := 0;
  While N < KImg Do
  Begin
    If Not ExtCopy(LongInt(CdSeg) * 16, KBase + N, 2048) Then Exit;
    N := N + 2048;
  End;
  If Not BigCopy(VStaging, KBase, KHdr) Then Exit;
  SO := PeOfs + 24 + OptSize;
  For I := 0 To NSect - 1 Do
  Begin
    VSize := VGetD(TmpSeg, SO + 8);
    VAddr := VGetD(TmpSeg, SO + 12);
    RawSize := VGetD(TmpSeg, SO + 16);
    RawPtr := VGetD(TmpSeg, SO + 20);
    If RawSize > VSize Then N := VSize Else N := RawSize;
    If N > 0 Then
      If Not BigCopy(VStaging + RawPtr, KBase + VAddr, N) Then Exit;
    SO := SO + 40;
  End;
  PutInfoD($1C, KBase);
  PutInfoD($20, KImg);
  VEntry := KBase + VEntry;
  PutInfoD($24, VEntry);
  LoadVmm32 := True;
End;

{ Demarrer Pasdows en mode protege ; ne revient qu'en cas d'echec }
Procedure StartVmm32;
Var Flags : Byte;
Begin
  If CdFind('VMM32.VXD') < 0 Then Exit;
  If ExtMemKb < 15 * 1024 Then Exit;
  TextMode;
  TClear;
  TWrite(0, 0, L('Chargement de Pasdows 95 (VMM32.VXD)...',
         'Loading Pasdows 95 (VMM32.VXD)...',
         'Pasdows 95 wird geladen (VMM32.VXD)...',
         'Caricamento di Pasdows 95 (VMM32.VXD)...',
         'Cargando Pasdows 95 (VMM32.VXD)...'), $07);
  EnableA20;
  If Not LoadVmm32 Then Exit;
  CopyFont;
  CopyEnv;
  MemW[0:VInfo] := $5750;
  Mem[0:VInfo + 2] := BootDrive;
  Mem[0:VInfo + 3] := Ord(Language);
  PutInfoD($04, RootLba);
  PutInfoD($08, RootSize);
  PutInfoD($18, ExtMemKb);
  PutInfoD($28, VFont);
  PutInfoD($2C, VEnv);
  Flags := 2;
  If OptLogo Then Flags := Flags Or 1;
  PutInfoD($30, Flags);
  If Not VbeSetup Then
  Begin
    TextMode;
    Exit;
  End;
  BuildGdt;
  asm
    cli
    mov al,0FFh
    out 0A1h,al
    out 21h,al
    xor ax,ax
    mov ds,ax
    db 0Fh,01h,16h
    dw 0A20h
    db 0Fh,20h,0C0h
    db 0Ch,01h
    db 0Fh,22h,0C0h
    db 0EAh
    dw 0A40h
    dw 0008h
  end;
End;

{ ================================================================== }
{ Programme principal                                                }
{ ================================================================== }

Procedure InitState;
Var I : Integer;
Begin
  For I := 1 To WinMax Do
  Begin
    Wins[I].Open := False; Wins[I].Min := False; Wins[I].Max := False;
  End;
  ZCnt := 0; TaskCnt := 0;
  DeskColor := cTeal; DeskSel := -1;
  MenuDepth := 0; MenuOwner := 0;
  DragWin := 0; PressWin := 0; PressBtn := 0;
  ClickTarget := -999; ClickTick := Ticks;
  ExpView := 0; ExpSel := -1; CtlSel := -1;
  NoteReset;
  CalcReset;
  PaintColor := cBlack; PaintTool := 0; PaintDown := False;
  PaintClear;
  ConInit(False);
  TipNo := 0; RunText := '';
  LastMin := -1; LastSec := -1;
  CurShown := False;
  GuiOn := False; QuitGui := 0;
  SetArea(0, 0, ScrW - 1, ScrH - 1);
End;

Var
  Mode : Integer;

BEGIN
  BootDrive := Lo(PrefixSeg);
  InitKeyTables;
  DetectSystem;
  EnvCnt := 0;
  SetEnv('PATH', 'D:\');
  SetEnv('COMSPEC', 'D:\IO.SYS');
  SetEnv('PROMPT', '$P$G');
  SetEnv('WINDIR', 'D:\');
  CdScan;
  ReadMsdosSys;
  ReadAutoexec;
  ApplyLanguage;
  InitState;
  If CmosRead(CmosDosFlag) = $D0 Then
  Begin
    { Redemarrer en mode MS-DOS (demande par VMM32) }
    CmosWrite(CmosDosFlag, 0);
    Mode := 2;
  End
  Else
    Mode := BootScreen;
  If (Mode = 0) And Not OptBootGUI Then Mode := 2;
  If Mode = 3 Then Reboot;
  If Mode = 0 Then StartVmm32;
  InitInput;
  If Mode = 2 Then
  Begin
    TextConsole;
    StartVmm32;
  End;
  SafeMode := Mode = 1;
  If SafeMode Then DeskColor := cBlack;
  GraphMode;
  If Not SafeMode And OptLogo Then Splash;
  RedrawAll;
  If Not SafeMode Then StartupSound;
  If SafeMode Then
    MessageBox('Pasdows', L('Pasdows fonctionne en mode sans '#130'chec. ' +
               'Ce mode sp'#130'cial de diagnostic d'#130'marre sans les ' +
               #130'l'#130'ments facultatifs.',
               'Pasdows is running in safe mode. This special diagnostic ' +
               'mode starts without optional components.',
               'Pasdows wird im abgesicherten Modus ausgef'#129'hrt.',
               'Pasdows '#138' in esecuzione in modalit'#133' provvisoria.',
               'Pasdows se est'#160' ejecutando en modo a prueba de fallos.'),
               icWarn)
  Else
    Execute(cmWelcome);
  GuiLoop;
END.
