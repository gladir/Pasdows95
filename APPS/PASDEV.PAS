{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: PASDEV - Pascal Developer, environnement de developpement
                integre (EDI) Pascal de Pasdows 95 (Win32), venu de
                l'EDI du Presentation Manager d'OS/2-0.
}

Program PASDEV;

{$R-,S-,I-}
{$IFDEF WPC}{$APPTYPE GUI}{$ENDIF}

{ Compilation : WPC -CW32 PASDEV.PAS PASDEV.EXE

  Pascal Developer est l'environnement de developpement du dossier
  Developer Kit du menu Demarrer : un editeur de sources Pascal a
  fenetres multiples (MDI) avec coloration syntaxique, dans l'esprit de
  Borland Pascal mais avec l'apparence de Windows 95. Le compilateur est
  WPC.EXE (Windows 95 Pascal Compiler, WPC compile par lui-meme), lance
  avec sa sortie standard redirigee vers un fichier
  (STARTF_USESTDHANDLES) : ses messages s'affichent dans la fenetre
  Messages (double clic ou Entree : la ligne en cause). Pendant la
  compilation, une boite montre l'etape, la ligne et une barre de
  progression (WPC -PRG, memoire partagee WPC.PRG) ; Annuler arrete
  le compilateur.

  Menus : Fichier (Nouveau, Ouvrir, Enregistrer, Enregistrer sous,
  Enregistrer tout, Fermer, Quitter), Edition (Couper, Copier, Coller,
  Effacer, Tout selectionner), Recherche (Rechercher, Occurrence suivante,
  Aller a la ligne, Ouvrir le fichier au curseur), Executer (Executer,
  Parametres), Compiler (Compiler, Information, Destination : Windows
  (fenetres) par defaut, ou Console Win32), Fenetre (Mosaique, Cascade,
  Suivante, Messages, Fermer tout, liste des fenetres), Aide (Touches,
  A propos). Barre d'etat : ligne et colonne du curseur, Insertion ou
  Refrappe, fichier modifie, destination de la compilation. Menu
  contextuel de l'editeur (bouton droit de la souris ou Maj+F10) :
  Couper, Copier, Coller, Effacer, Tout selectionner, Ouvrir le fichier
  au curseur, Aller a la ligne, Compiler, Executer, Information.

  Les fenetres d'edition sont dessinees dans la zone de travail de la
  fenetre principale : barre de titre (deplacement, double clic :
  agrandir), case de fermeture, case d'agrandissement, barres de
  defilement et coin de redimensionnement.

  Touches (Borland et CUA) : F2 enregistrer, F3 ouvrir, Alt+F3 fermer,
  F6 fenetre suivante, F9 compiler, Ctrl+F9 executer, Alt+X
  quitter, Ins insertion/refrappe, Maj+fleches selection, Ctrl+Ins ou
  Ctrl+C copier, Maj+Suppr ou Ctrl+X couper, Maj+Ins ou Ctrl+V coller,
  Ctrl+Suppr effacer, Ctrl+A tout selectionner, Ctrl+Y supprimer la
  ligne, Ctrl+F rechercher, Ctrl+L occurrence suivante, Ctrl+G aller a
  la ligne, Ctrl+Entree ouvrir le fichier au curseur, Ctrl+fleches mot
  par mot, Ctrl+Origine/Fin debut/fin du fichier.

  Parametres : fichiers sources a ouvrir. }

Uses Dos;

Const
  { Windows : messages, styles, menus, boites de message }
  WM_CREATE = $0001; WM_DESTROY = $0002; WM_SIZE = $0005; WM_SETFOCUS = $0007;
  WM_PAINT = $000F; WM_CLOSE = $0010; WM_QUIT = $0012; WM_SETCURSOR = $0020;
  WM_KEYDOWN = $0100; WM_CHAR = $0102; WM_SYSKEYDOWN = $0104; WM_SYSCHAR = $0106;
  WM_COMMAND = $0111; WM_TIMER = $0113;
  WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201; WM_LBUTTONUP = $0202;
  WM_LBUTTONDBLCLK = $0203; WM_RBUTTONDOWN = $0204;
  WS_OVERLAPPEDWINDOW = $00CF0000; WS_POPUP = $80000000; WS_CHILD = $40000000;
  WS_VISIBLE = $10000000; WS_CAPTION = $00C00000; WS_SYSMENU = $00080000;
  WS_BORDER = $00800000; WS_VSCROLL = $00200000; WS_TABSTOP = $00010000;
  WS_EX_DLGMODALFRAME = 1; WS_EX_CLIENTEDGE = $200;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1; ES_AUTOHSCROLL = $80; LBS_NOTIFY = 1;
  EM_SETSEL = $00B1; EM_LIMITTEXT = $00C5;
  LB_ADDSTRING = $0180; LB_RESETCONTENT = $0184; LB_SETCURSEL = $0186; LB_GETCURSEL = $0188;
  LBN_SELCHANGE = 1; LBN_DBLCLK = 2;
  MF_STRING = 0; MF_GRAYED = 1; MF_CHECKED = 8; MF_POPUP = $10; MF_SEPARATOR = $800;
  MB_OK = 0; MB_YESNO = 4; MB_YESNOCANCEL = 3; MB_INFORMATION = $40; MB_WARNING = $30;
  MB_ERROR = $10; MB_QUERY = $20; MB_MOVEABLE = 0; MBID_YES = 6; MBID_NO = 7; MBID_CANCEL = 2;
  CS_DBLCLKS = 8;
  IDC_ARROW = 32512; IDC_IBEAM = 32513; IDC_WAIT = 32514; IDC_SIZENWSE = 32642; IDC_SIZEALL = 32646;
  CF_TEXT = 1; GMEM_MOVEABLE = 2; GPTR = $40;
  ETO_OPAQUE = 2; ETO_CLIPPED = 4; SYSTEM_FIXED_FONT = 16;
  TPM_RIGHTBUTTON = 2;
  STARTF_USESTDHANDLES = $100; CREATE_NEW_CONSOLE = $10;
  GENERIC_WRITE = $40000000; FILE_SHARE_READ = 1; CREATE_ALWAYS = 2; FILE_ATTRIBUTE_NORMAL = $80;
  WAIT_TIMEOUT = 258; PAGE_READWRITE = 4; FILE_MAP_ALL_ACCESS = $F001F;
  { touches : codes internes de l'editeur (ceux de l'EDI d'origine ; les
    touches de Windows sont traduites dans MainProc) }
  KC_CHAR = 1; KC_VIRTUALKEY = 2; KC_SHIFT = 8; KC_CTRL = $10; KC_ALT = $20; KC_KEYUP = $40;
  VK_BACKSPACE = $05; VK_TAB = $06; VK_BACKTAB = $07; VK_NEWLINE = $08; VK_ESC = $0F;
  VK_PAGEUP = $11; VK_PAGEDOWN = $12; VK_END = $13; VK_HOME = $14; VK_LEFT = $15; VK_UP = $16;
  VK_RIGHT = $17; VK_DOWN = $18; VK_INSERT = $1A; VK_DELETE = $1B; VK_ENTER = $1E;
  VK_F1 = $20;
  { curseurs de la souris }
  SPTR_ARROW = IDC_ARROW; SPTR_TEXT = IDC_IBEAM; SPTR_WAIT = IDC_WAIT;
  SPTR_SIZENWSE = IDC_SIZENWSE; SPTR_MOVE = IDC_SIZEALL;
  { couleurs (indices ; RVB par ClrRGB) }
  CLR_WHITE = -2; CLR_BLACK = -1; CLR_BLUE = 1; CLR_RED = 2; CLR_PINK = 3; CLR_GREEN = 4;
  CLR_CYAN = 5; CLR_YELLOW = 6; CLR_DARKGRAY = 8; CLR_DARKBLUE = 9; CLR_DARKRED = 10;
  CLR_DARKPINK = 11; CLR_DARKGREEN = 12; CLR_DARKCYAN = 13; CLR_BROWN = 14; CLR_PALEGRAY = 15;
  { couleurs du systeme (barres de titre, comme les fenetres de Windows) }
  SYSCLR_INACTIVETITLE = -22; SYSCLR_ACTIVETITLE = -23;
  SYSCLR_ACTIVETITLETEXT = -28; SYSCLR_INACTIVETITLETEXT = -29;

  { --- commandes --- }
  CM_NEW = 101; CM_OPEN = 102; CM_SAVE = 103; CM_SAVEAS = 104; CM_SAVEALL = 105;
  CM_CLOSE = 106; CM_EXIT = 107;
  CM_CUT = 201; CM_COPY = 202; CM_PASTE = 203; CM_CLEAR = 204; CM_SELALL = 205;
  CM_FIND = 301; CM_FINDNEXT = 302; CM_GOTO = 303; CM_OPENCUR = 304;
  CM_RUN = 401; CM_PARAMS = 402;
  CM_COMPILE = 501; CM_INFO = 502; CM_TGTPM = 503; CM_TGTCON = 504;
  CM_TILE = 601; CM_CASCADE = 602; CM_NEXT = 603; CM_MESSAGES = 604; CM_CLOSEALL = 605;
  CM_WIN0 = 650;                       { 650..665 : fenetres (menu Fenetre) }
  CM_KEYS = 701; CM_ABOUT = 702;
  ID_DOK = 1; ID_DCANCEL = 2; ID_DEF = 20; ID_DLIST = 21;
  { dialogues }
  DM_SAVEAS = 1; DM_FIND = 2; DM_GOTO = 3; DM_PARAMS = 4; DM_OPEN = 5;

  { --- limites et dimensions --- }
  MAXWIN = 16;                         { fenetres (sources et Messages) }
  MAXLEN = 250;                        { longueur d'une ligne de source }
  SLOT = 256;                          { octets par ligne dans le bloc d'un document }
  MAXMSG = 300;                        { lignes de la fenetre Messages }
  CHW = 8; CHH = 16;                   { cellule de la police du systeme }
  BRD = 3;                             { bordure des fenetres d'edition }
  TTLH = 20;                           { barre de titre }
  SBW = 16;                            { barres de defilement }
  STATH = 22;                          { barre d'etat }
  TABSZ = 2;                           { tabulation : espaces }
  WK_EDIT = 1; WK_MSG = 2;
  { glisser de la souris }
  DG_NONE = 0; DG_MOVE = 1; DG_SIZE = 2; DG_VTHUMB = 3; DG_HTHUMB = 4; DG_SEL = 5;
  { etats du lexeur de coloration (debut de ligne) }
  ST_NORMAL = 0; ST_BRACE = 1; ST_PAREN = 2;
  { mots reserves et directives de Turbo Pascal (coloration) }
  { (deux chaines : une constante chaine a au plus 255 caracteres) }
  KEYWORDS = ' AND ARRAY ASM BEGIN CASE CONST CONSTRUCTOR DESTRUCTOR DIV DO DOWNTO ELSE END ' +
             'EXPORTS FILE FOR FUNCTION GOTO IF IMPLEMENTATION IN INHERITED INLINE INTERFACE ';
  KEYWORDS2 = ' LABEL LIBRARY MOD NIL NOT OBJECT OF OR PACKED PROCEDURE PROGRAM RECORD REPEAT SET ' +
              'SHL SHR STRING THEN TO TYPE UNIT UNTIL USES VAR WHILE WITH XOR ';
  DIRECTIVES = ' ABSOLUTE ASSEMBLER EXTERNAL FAR FORWARD INTERRUPT NEAR PRIVATE PUBLIC ' +
               'VIRTUAL NAME INDEX ';

Type
  PStr = ^String;
  PLong = ^LongInt;
  PByte = ^Byte;
  TWin = Record
    Used : Boolean;
    Kind : LongInt;                    { WK_EDIT ou WK_MSG }
    X, Y, W, H : LongInt;              { position dans la zone de travail (haut gauche) }
    NX, NY, NW, NH : LongInt;          { position avant agrandissement }
    Max : Boolean;
    FileName : String;                 { '' : sans nom }
    Untitled : LongInt;                { numero de NONAMEnn.PAS }
    Modified : Boolean;
    NLines, Cap : LongInt;             { lignes, capacite du bloc }
    Mem : LongInt;                     { bloc : lignes (SLOT octets), index, pile libre, etats }
    IdxOfs, FreeOfs, StOfs : LongInt;
    FreeCnt : LongInt;
    StValid : LongInt;                 { etats de coloration valides pour les lignes 0..StValid-1 }
    CX, CY : LongInt;                  { curseur : colonne et ligne (0 = premiere) }
    TopL, LeftC : LongInt;             { defilement }
    SelOn : Boolean;
    SAX, SAY : LongInt;                { ancre de la selection }
    Num : LongInt;                     { numero affiche dans le titre }
    ShownMod : Boolean;                { etat Modifie dessine dans le titre }
  End;

Var
  Inst, Frame, Client, MenuHw, CtxMenu, Dummy, SysFont : LongInt;
  CW, CH : LongInt;                    { zone client }
  Wins : Array[0..MAXWIN - 1] Of TWin;
  ZOrd : Array[0..MAXWIN - 1] Of LongInt;  { ordre d'empilement : ZOrd[NZ-1] = active }
  NZ : LongInt;
  MsgWin : LongInt;                    { fenetre Messages (-1) }
  MsgText : Array[0..MAXMSG - 1] Of String;
  MsgLine : Array[0..MAXMSG - 1] Of LongInt;
  MsgCount, MsgSel, MsgTop : LongInt;
  InsMode : Boolean;
  Target : LongInt;                    { 0 : Windows (fenetres), 1 : Console Win32 }
  RunParams : String;
  FindText : String;
  UntitledSeq, WinSeq : LongInt;
  StatusMsg : String;
  { glisser de la souris }
  Drag, DragWin, DragDX, DragDY : LongInt;
  { derniere compilation (Information) }
  LastSrc, LastExe : String;
  LastOk, LastDone : Boolean;
  LastLines, LastCode, LastData, LastImports, LastSize, LastErrs, LastWarns, LastTime : LongInt;
  LastTarget : LongInt;
  { repertoires }
  ExeDir, WorkDir, CompilerPath : String;
  { dialogue courant (non modal) }
  DlgFr, DlgCl, DlgEf, DlgLb, DlgMode : LongInt;
  DlgPrompt, DlgDir : String;
  { boites Information et A propos }
  InfoFr, AboutFr : LongInt;
  CompFr, CompCl, PrgMem, CompLastLine, CompLastPh : LongInt;   { boite de compilation, progression de WPC }
  NameZ, NameZ2, TxtBuf, ArgBuf, FailBuf : Array[0..1023] Of Byte;
  ClsBuf : Array[0..63] Of Byte;
  Qmsg : Array[0..7] Of LongInt;      { MSG }
  PaintS : Array[0..15] Of LongInt;   { PAINTSTRUCT }
  ClipBuf : Array[0..16383] Of Byte;
  PicBmi : Array[0..39 + 64] Of Byte;  { BITMAPINFOHEADER (40 octets) + 16 couleurs }
  PicBits : Array[0..72 * 176 - 1] Of Byte;
  PicReady : Boolean;

{ --- USER32.DLL, GDI32.DLL, KERNEL32.DLL --- }
Function RegisterClassA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex, Cls, Nm, St, X, Y, W, H, Par, Menu, Ins, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'CreateWindowExA';
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(P, H, A, B : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall; external 'user32.dll' name 'PostQuitMessage';
Function BeginPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'BeginPaint';
Function EndPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EndPaint';
Function FillRect(Dc, R, B : LongInt) : LongInt; stdcall; external 'user32.dll' name 'FillRect';
Function InvalidateRect(H, R, E : LongInt) : LongInt; stdcall; external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetClientRect';
Function SetWindowPos(H, A, X, Y, W, Hh, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetWindowPos';
Function MessageBoxA(H, T, C, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MessageBoxA';
Function DestroyWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DestroyWindow';
Function SetFocus(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetFocus';
Function GetFocus : LongInt; stdcall; external 'user32.dll' name 'GetFocus';
Function SetActiveWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetActiveWindow';
Function GetActiveWindow : LongInt; stdcall; external 'user32.dll' name 'GetActiveWindow';
Function SetForegroundWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetForegroundWindow';
Function SetCursor(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetCursor';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'LoadCursorA';
Function SetCapture(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall; external 'user32.dll' name 'ReleaseCapture';
Function GetDlgItem(H, Id : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetDlgItem';
Function UpdateWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'UpdateWindow';
Function SetTimer(H, Id, Ms, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetTimer';
Function KillTimer(H, Id : LongInt) : LongInt; stdcall; external 'user32.dll' name 'KillTimer';
Function SendMessageA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SendMessageA';
Function PostMessageA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'PostMessageA';
Function SetWindowTextA(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetWindowTextA';
Function GetWindowTextA(H, P, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetWindowTextA';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetSystemMetrics';
Function CreateMenu : LongInt; stdcall; external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall; external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(M, F, Id, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetMenu';
Function CheckMenuItem(M, Id, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'CheckMenuItem';
Function TrackPopupMenu(M, F, X, Y, R, H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'TrackPopupMenu';
Function DestroyMenu(M : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DestroyMenu';
Function ClientToScreen(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ClientToScreen';
Function OpenClipboard(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'OpenClipboard';
Function EmptyClipboard : LongInt; stdcall; external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetClipboardData';
Function GetClipboardData(F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetClipboardData';
Function CloseClipboard : LongInt; stdcall; external 'user32.dll' name 'CloseClipboard';
Function GetKeyState(K : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetKeyState';
Function GetSysColor(I : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetSysColor';
Function ShowWindow(H, C : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ShowWindow';
Function GetParent(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetParent';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(S, W, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreatePen';
Function SelectObject(Dc, O : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SelectObject';
Function DeleteObject(O : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'DeleteObject';
Function MoveToEx(Dc, X, Y, P : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'MoveToEx';
Function LineTo(Dc, X, Y : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'LineTo';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetTextColor';
Function SetBkColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetBkColor';
Function ExtTextOutA(Dc, X, Y, O, R, S, N, D : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'ExtTextOutA';
Function GetStockObject(I : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'GetStockObject';
Function SetDIBitsToDevice(Dc, X, Y, W, H, Sx, Sy, Sl, N, Bits, Bmi, U : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetDIBitsToDevice';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GlobalAlloc';
Function GlobalFree(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GlobalFree';
Function GlobalLock(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GlobalLock';
Function GlobalUnlock(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GlobalUnlock';
Function CreateProcessA(A, C, Pa, Ta, Inh, Fl, Env, Dir, PSi, PPi : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateProcessA';
Function WaitForSingleObject(H, Ms : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'WaitForSingleObject';
Function GetExitCodeProcess(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetExitCodeProcess';
Function TerminateProcess(H, C : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'TerminateProcess';
Function CloseHandle(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CloseHandle';
Function CreateFileA(N, A, Sh, Sec, Disp, Fl, T : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileA';
Function GetTickCount : LongInt; stdcall; external 'kernel32.dll' name 'GetTickCount';
Procedure Sleep(Ms : LongInt); stdcall; external 'kernel32.dll' name 'Sleep';
Function CreateFileMappingA(F, Sec, P, Hi, Lo, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileMappingA';
Function MapViewOfFile(H, A, Hi, Lo, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'MapViewOfFile';
Function GetModuleHandleA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetModuleHandleA';
Function GetLastError : LongInt; stdcall; external 'kernel32.dll' name 'GetLastError';

{ ==================================================================== }
{ Utilitaires                                                           }
{ ==================================================================== }

Procedure WrB(A, V : LongInt);
Var Q : PByte;
Begin
  Q := Pointer(A);
  Q^ := V;
End;

Function RdB(A : LongInt) : LongInt;
Var Q : PByte;
Begin
  Q := Pointer(A);
  RdB := Q^;
End;

Procedure WrL(A, V : LongInt);
Var Q : PLong;
Begin
  Q := Pointer(A);
  Q^ := V;
End;

Function RdL(A : LongInt) : LongInt;
Var Q : PLong;
Begin
  Q := Pointer(A);
  RdL := Q^;
End;

Procedure WrW(A, V : LongInt);
Begin
  WrB(A, V And 255);
  WrB(A + 1, (V Shr 8) And 255);
End;

Procedure PutZ(A : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do WrB(A + K - 1, Ord(S[K]));
  WrB(A + Length(S), 0);
End;

Function GetZ(A : LongInt) : String;
Var S : String; C : LongInt;
Begin
  S := '';
  If A <> 0 Then
  Begin
    C := RdB(A);
    While (C <> 0) And (Length(S) < 255) Do
    Begin
      S := S + Chr(C);
      Inc(A);
      C := RdB(A);
    End;
  End;
  GetZ := S;
End;

Function Z(S : String) : LongInt;
Begin
  PutZ(LongInt(@NameZ), S);
  Z := LongInt(@NameZ);
End;

Function Z2(S : String) : LongInt;
Begin
  PutZ(LongInt(@NameZ2), S);
  Z2 := LongInt(@NameZ2);
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

{ nombre avec separateur des milliers (espace) }
Function NStr(V : LongInt) : String;
Var S, R : String; K, N : LongInt;
Begin
  S := IStr(V);
  R := '';
  N := 0;
  For K := Length(S) DownTo 1 Do
  Begin
    If (N > 0) And (N Mod 3 = 0) And (S[K] <> '-') Then R := ' ' + R;
    R := S[K] + R;
    Inc(N);
  End;
  NStr := R;
End;

Function Lo16(V : LongInt) : LongInt;
Begin
  Lo16 := V And $FFFF;
End;

Function Hi16(V : LongInt) : LongInt;
Begin
  Hi16 := (V Shr 16) And $FFFF;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Function MinI(A, B : LongInt) : LongInt;
Begin
  If A < B Then MinI := A Else MinI := B;
End;

Function MaxI(A, B : LongInt) : LongInt;
Begin
  If A > B Then MaxI := A Else MaxI := B;
End;

Function UpStr(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do S[K] := UpCase(S[K]);
  UpStr := S;
End;

Function Spaces(N : LongInt) : String;
Var S : String;
Begin
  S := '';
  While (N > 0) And (Length(S) < 255) Do
  Begin
    S := S + ' ';
    Dec(N);
  End;
  Spaces := S;
End;

Function TrimR(S : String) : String;
Begin
  While (Length(S) > 0) And (S[Length(S)] = ' ') Do Delete(S, Length(S), 1);
  TrimR := S;
End;

Function Trim(S : String) : String;
Begin
  While (Length(S) > 0) And (S[1] = ' ') Do Delete(S, 1, 1);
  Trim := TrimR(S);
End;

Function IsIdCh(C : Char) : Boolean;
Begin
  IsIdCh := ((C >= 'A') And (C <= 'Z')) Or ((C >= 'a') And (C <= 'z')) Or
            ((C >= '0') And (C <= '9')) Or (C = '_');
End;

{ copie memoire avec recouvrement }
Procedure MemMove(Src, Dst, N : LongInt);
Var Ps, Pd : PByte;
Begin
  If N <= 0 Then Exit;
  Ps := Pointer(Src); Pd := Pointer(Dst);
  Move(Ps^, Pd^, N);
End;

Function FileExists(N : String) : Boolean;
Var F : File; R : LongInt;
Begin
  FileExists := False;
  If N = '' Then Exit;
  Assign(F, N);
  {$I-} Reset(F, 1); {$I+}
  R := IOResult;
  If R = 0 Then
  Begin
    Close(F);
    FileExists := True;
  End;
End;

Function FileSizeOf(N : String) : LongInt;
Var F : File; R : LongInt;
Begin
  FileSizeOf := -1;
  Assign(F, N);
  {$I-} Reset(F, 1); {$I+}
  R := IOResult;
  If R = 0 Then
  Begin
    FileSizeOf := FileSize(F);
    Close(F);
  End;
End;

{ repertoire d'un chemin (avec \ final), nom sans repertoire, extension }
Function DirOf(S : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '\') And (S[K] <> ':') Do Dec(K);
  DirOf := Copy(S, 1, K);
End;

Function NameOf(S : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '\') And (S[K] <> ':') Do Dec(K);
  NameOf := Copy(S, K + 1, 255);
End;

Function ChangeExt(S, E : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '.') And (S[K] <> '\') And (S[K] <> ':') Do Dec(K);
  If (K > 0) And (S[K] = '.') Then S := Copy(S, 1, K - 1);
  ChangeExt := S + E;
End;

Function HasExt(S : String) : Boolean;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '.') And (S[K] <> '\') And (S[K] <> ':') Do Dec(K);
  HasExt := (K > 0) And (S[K] = '.');
End;

{ chemin complet (lecteur et repertoire courants) }
Function FullPath(S : String) : String;
Begin
  If S = '' Then FullPath := ''
  Else FullPath := UpStr(FExpand(S));
End;

Procedure ShowMsg(Text, Cap : String; Fl : LongInt);
Begin
  Dummy := MessageBoxA(Frame, Z(Text), Z2(Cap), Fl);
End;

{ messages de plus de 255 caracteres (limite des chaines) : texte cumule
  dans LBuf par LAdd, puis affiche par LMsgBox }
Var
  LBuf : Array[0..4095] Of Byte;
  LLen : LongInt;

Procedure LClr;
Begin
  LLen := 0;
  LBuf[0] := 0;
End;

Procedure LAdd(S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If LLen < 4094 Then
    Begin
      LBuf[LLen] := Ord(S[K]);
      Inc(LLen);
    End;
  LBuf[LLen] := 0;
End;

Function LMsgBox(Cap : String; Fl : LongInt) : LongInt;
Begin
  LMsgBox := MessageBoxA(Frame, LongInt(@LBuf), Z2(Cap), Fl);
End;

Function AskYesNo(Text, Cap : String; Fl : LongInt) : LongInt;
Begin
  AskYesNo := MessageBoxA(Frame, Z(Text), Z2(Cap), Fl);
End;

{ caracteres accentues (CP437, police de Pasdows) des messages }
Function Acc(S : String) : String;
Var K : LongInt; R : String;
Begin
  R := '';
  K := 1;
  While K <= Length(S) Do
  Begin
    If (S[K] = '^') And (K < Length(S)) Then
    Begin
      Inc(K);
      Case S[K] Of
        'e' : R := R + Chr(130);       { e aigu }
        'E' : R := R + Chr(144);       { E aigu }
        'g' : R := R + Chr(138);       { e grave }
        'a' : R := R + Chr(133);       { a grave }
        'c' : R := R + Chr(135);       { c cedille }
        'o' : R := R + Chr(147);       { o circonflexe }
        'i' : R := R + Chr(140);       { i circonflexe }
        'u' : R := R + Chr(150);       { u circonflexe }
        'x' : R := R + Chr(136);       { e circonflexe }
      Else R := R + S[K];
      End;
    End
    Else R := R + S[K];
    Inc(K);
  End;
  Acc := R;
End;

{ ==================================================================== }
{ Documents : lignes dans un bloc GlobalAlloc                           }
{ ==================================================================== }
{ Bloc d'un document de capacite C : C lignes de SLOT octets (chaines
  Pascal), puis l'index (C LongInt : ligne -> numero de case), la pile
  des cases libres (C LongInt) et l'etat de coloration au debut de
  chaque ligne (C octets). Inserer ou supprimer une ligne deplace
  seulement l'index. }

Function BlockSize(C : LongInt) : LongInt;
Begin
  BlockSize := C * SLOT + C * 4 + C * 4 + C;
End;

Function AllocBlock(C : LongInt) : LongInt;
Begin
  AllocBlock := GlobalAlloc(GPTR, BlockSize(C));
End;

Procedure SetLayout(W : LongInt);
Begin
  Wins[W].IdxOfs := Wins[W].Cap * SLOT;
  Wins[W].FreeOfs := Wins[W].IdxOfs + Wins[W].Cap * 4;
  Wins[W].StOfs := Wins[W].FreeOfs + Wins[W].Cap * 4;
End;

Function SlotOf(W, I : LongInt) : LongInt;
Begin
  SlotOf := RdL(Wins[W].Mem + Wins[W].IdxOfs + I * 4);
End;

Function LineAddr(W, I : LongInt) : LongInt;
Begin
  LineAddr := Wins[W].Mem + SlotOf(W, I) * SLOT;
End;

Function GetLine(W, I : LongInt) : String;
Var P : PStr;
Begin
  If (W < 0) Or (I < 0) Or (I >= Wins[W].NLines) Then GetLine := ''
  Else
  Begin
    P := Pointer(LineAddr(W, I));
    GetLine := P^;
  End;
End;

Function LineLen(W, I : LongInt) : LongInt;
Begin
  If (I < 0) Or (I >= Wins[W].NLines) Then LineLen := 0
  Else LineLen := RdB(LineAddr(W, I));
End;

Procedure Touch(W, I : LongInt);
Begin
  If I < Wins[W].StValid Then Wins[W].StValid := MaxI(0, I);
  Wins[W].Modified := True;
End;

Procedure SetLine(W, I : LongInt; S : String);
Var P : PStr;
Begin
  If (I < 0) Or (I >= Wins[W].NLines) Then Exit;
  If Length(S) > MAXLEN Then S := Copy(S, 1, MAXLEN);
  P := Pointer(LineAddr(W, I));
  P^ := S;
  Touch(W, I + 1);
End;

{ nouveau document vide de capacite C (une ligne vide) }
Function DocInit(W, C : LongInt) : Boolean;
Var K : LongInt;
Begin
  DocInit := False;
  If C < 256 Then C := 256;
  Wins[W].Mem := AllocBlock(C);
  If Wins[W].Mem = 0 Then Exit;
  Wins[W].Cap := C;
  SetLayout(W);
  { cases libres : C-1 ... 0 (la case 0 sort en premier) }
  For K := 0 To C - 1 Do WrL(Wins[W].Mem + Wins[W].FreeOfs + K * 4, C - 1 - K);
  Wins[W].FreeCnt := C;
  Wins[W].NLines := 0;
  Wins[W].StValid := 0;
  DocInit := True;
End;

Procedure DocFree(W : LongInt);
Begin
  If Wins[W].Mem <> 0 Then Dummy := GlobalFree(Wins[W].Mem);
  Wins[W].Mem := 0;
  Wins[W].Cap := 0;
  Wins[W].NLines := 0;
End;

{ doubler la capacite }
Function DocGrow(W : LongInt) : Boolean;
Var NC, NM, K, OldCap, OldMem, OldIdx, OldSt : LongInt;
Begin
  DocGrow := False;
  OldCap := Wins[W].Cap;
  NC := OldCap * 2;
  NM := AllocBlock(NC);
  If NM = 0 Then Exit;
  OldMem := Wins[W].Mem;
  OldIdx := OldMem + Wins[W].IdxOfs;
  OldSt := OldMem + Wins[W].StOfs;
  MemMove(OldMem, NM, OldCap * SLOT);
  Wins[W].Mem := NM;
  Wins[W].Cap := NC;
  SetLayout(W);
  MemMove(OldIdx, NM + Wins[W].IdxOfs, OldCap * 4);
  MemMove(OldSt, NM + Wins[W].StOfs, OldCap);
  { nouvelles cases libres OldCap..NC-1, au-dessous des anciennes libres }
  MemMove(OldMem + OldCap * SLOT + OldCap * 4, NM + Wins[W].FreeOfs + (NC - OldCap) * 4, Wins[W].FreeCnt * 4);
  For K := 0 To NC - OldCap - 1 Do WrL(NM + Wins[W].FreeOfs + K * 4, NC - 1 - K);
  Wins[W].FreeCnt := Wins[W].FreeCnt + NC - OldCap;
  Dummy := GlobalFree(OldMem);
  DocGrow := True;
End;

{ inserer la ligne S avant la ligne I (I = NLines : a la fin) }
Function DocIns(W, I : LongInt; S : String) : Boolean;
Var Sl, A : LongInt;
Begin
  DocIns := False;
  If Wins[W].FreeCnt = 0 Then
    If Not DocGrow(W) Then
    Begin
      ShowMsg(Acc('M^emoire insuffisante : le fichier est trop grand.'), 'Pascal Developer', MB_OK Or MB_ERROR);
      Exit;
    End;
  Dec(Wins[W].FreeCnt);
  Sl := RdL(Wins[W].Mem + Wins[W].FreeOfs + Wins[W].FreeCnt * 4);
  A := Wins[W].Mem + Wins[W].IdxOfs;
  MemMove(A + I * 4, A + (I + 1) * 4, (Wins[W].NLines - I) * 4);
  WrL(A + I * 4, Sl);
  Inc(Wins[W].NLines);
  WrB(Wins[W].Mem + Sl * SLOT, 0);
  SetLine(W, I, S);
  Touch(W, I);
  DocIns := True;
End;

Procedure DocDel(W, I : LongInt);
Var A : LongInt;
Begin
  If (I < 0) Or (I >= Wins[W].NLines) Then Exit;
  A := Wins[W].Mem + Wins[W].IdxOfs;
  WrL(Wins[W].Mem + Wins[W].FreeOfs + Wins[W].FreeCnt * 4, SlotOf(W, I));
  Inc(Wins[W].FreeCnt);
  MemMove(A + (I + 1) * 4, A + I * 4, (Wins[W].NLines - I - 1) * 4);
  Dec(Wins[W].NLines);
  Touch(W, I);
End;

{ ==================================================================== }
{ Coloration syntaxique : etat (commentaire ouvert) au debut des lignes }
{ ==================================================================== }

{ etat a la fin de la ligne S commencee dans l'etat St }
Function ScanState(S : String; St : LongInt) : LongInt;
Var K, N : LongInt; C : Char;
Begin
  K := 1;
  N := Length(S);
  While K <= N Do
  Begin
    C := S[K];
    If St = ST_BRACE Then
    Begin
      If C = '}' Then St := ST_NORMAL;
      Inc(K);
    End
    Else If St = ST_PAREN Then
    Begin
      If (C = '*') And (K < N) And (S[K + 1] = ')') Then
      Begin
        St := ST_NORMAL;
        Inc(K);
      End;
      Inc(K);
    End
    Else
    Begin
      If C = '{' Then St := ST_BRACE
      Else If (C = '(') And (K < N) And (S[K + 1] = '*') Then
      Begin
        St := ST_PAREN;
        Inc(K);
      End
      Else If (C = '/') And (K < N) And (S[K + 1] = '/') Then K := N
      Else If C = '''' Then
      Begin
        Inc(K);
        While (K <= N) And (S[K] <> '''') Do Inc(K);
      End;
      Inc(K);
    End;
  End;
  ScanState := St;
End;

Function StateAt(W, I : LongInt) : LongInt;
Var K, St : LongInt;
Begin
  If I <= 0 Then
  Begin
    StateAt := ST_NORMAL;
    Exit;
  End;
  If I > Wins[W].NLines Then I := Wins[W].NLines;
  If Wins[W].StValid < 1 Then
  Begin
    WrB(Wins[W].Mem + Wins[W].StOfs, ST_NORMAL);
    Wins[W].StValid := 1;
  End;
  K := Wins[W].StValid - 1;
  St := RdB(Wins[W].Mem + Wins[W].StOfs + K);
  While K < I Do
  Begin
    St := ScanState(GetLine(W, K), St);
    Inc(K);
    If K < Wins[W].Cap Then WrB(Wins[W].Mem + Wins[W].StOfs + K, St);
    Wins[W].StValid := K + 1;
  End;
  StateAt := RdB(Wins[W].Mem + Wins[W].StOfs + I);
End;

{ ==================================================================== }
{ Fichiers                                                              }
{ ==================================================================== }

Function ExpandTabs(S : String) : String;
Var R : String; K : LongInt;
Begin
  If Pos(#9, S) = 0 Then
  Begin
    ExpandTabs := S;
    Exit;
  End;
  R := '';
  For K := 1 To Length(S) Do
    If S[K] = #9 Then
    Begin
      Repeat
        R := R + ' ';
      Until (Length(R) Mod 8 = 0) Or (Length(R) >= MAXLEN);
    End
    Else If Length(R) < 255 Then R := R + S[K];
  ExpandTabs := R;
End;

{ charger le fichier N dans le document W (deja initialise) ; Faux si
  le fichier ne peut etre lu }
Function LoadFile(W : LongInt; N : String) : Boolean;
Var F : Text; S : String; R : LongInt;
Begin
  LoadFile := False;
  Assign(F, N);
  {$I-} Reset(F); {$I+}
  R := IOResult;
  If R <> 0 Then Exit;
  While Not EOF(F) Do
  Begin
    ReadLn(F, S);
    S := ExpandTabs(S);
    If Not DocIns(W, Wins[W].NLines, S) Then Break;
  End;
  Close(F);
  If Wins[W].NLines = 0 Then
    If DocIns(W, 0, '') Then ;
  Wins[W].Modified := False;
  LoadFile := True;
End;

Function SaveFile(W : LongInt; N : String) : Boolean;
Var F : Text; K, R, Last : LongInt;
Begin
  SaveFile := False;
  Assign(F, N);
  {$I-} Rewrite(F); {$I+}
  R := IOResult;
  If R <> 0 Then
  Begin
    ShowMsg(Acc('Impossible de cr^eer le fichier ') + N + Acc(' (erreur ') + IStr(R) + ').',
            'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  { sans les lignes vides de la fin }
  Last := Wins[W].NLines - 1;
  While (Last > 0) And (TrimR(GetLine(W, Last)) = '') Do Dec(Last);
  For K := 0 To Last Do WriteLn(F, TrimR(GetLine(W, K)));
  Close(F);
  R := IOResult;
  If R <> 0 Then
  Begin
    ShowMsg(Acc('Erreur d''^ecriture du fichier ') + N + '.', 'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  Wins[W].Modified := False;
  SaveFile := True;
End;

{ ==================================================================== }
{ Dessin (coordonnees depuis le coin haut gauche de la zone client)     }
{ ==================================================================== }

Function WorkH : LongInt;
Begin
  WorkH := MaxI(0, CH - STATH);
End;

{ couleur RVB (COLORREF) d'un indice CLR_ ou SYSCLR_ }
Function ClrRGB(C : LongInt) : LongInt;
Begin
  Case C Of
    CLR_WHITE : ClrRGB := $FFFFFF;
    CLR_BLACK : ClrRGB := 0;
    CLR_BLUE : ClrRGB := $FF0000;
    CLR_RED : ClrRGB := $0000FF;
    CLR_PINK : ClrRGB := $FF00FF;
    CLR_GREEN : ClrRGB := $00FF00;
    CLR_CYAN : ClrRGB := $FFFF00;
    CLR_YELLOW : ClrRGB := $00FFFF;
    CLR_DARKGRAY : ClrRGB := $808080;
    CLR_DARKBLUE : ClrRGB := $800000;
    CLR_DARKRED : ClrRGB := $000080;
    CLR_DARKPINK : ClrRGB := $800080;
    CLR_DARKGREEN : ClrRGB := $008000;
    CLR_DARKCYAN : ClrRGB := $808000;
    CLR_BROWN : ClrRGB := $008080;
    CLR_PALEGRAY : ClrRGB := $C0C0C0;
    SYSCLR_ACTIVETITLE : ClrRGB := GetSysColor(2);
    SYSCLR_INACTIVETITLE : ClrRGB := GetSysColor(3);
    SYSCLR_ACTIVETITLETEXT : ClrRGB := GetSysColor(9);
    SYSCLR_INACTIVETITLETEXT : ClrRGB := GetSysColor(19);
  Else ClrRGB := 0;
  End;
End;

{ rectangle plein (X1, Y1) - (X2, Y2) exclus }
Procedure FillR(Hps, X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; Br : LongInt;
Begin
  If (X2 <= X1) Or (Y2 <= Y1) Then Exit;
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2; Rc[3] := Y2;
  Br := CreateSolidBrush(ClrRGB(C));
  Dummy := FillRect(Hps, LongInt(@Rc), Br);
  Dummy := DeleteObject(Br);
End;

{ ligne de (X1, Y1) a (X2, Y2), extremites comprises }
Procedure DrawLn(Hps, X1, Y1, X2, Y2, C : LongInt);
Var Pn, Old, DX, DY : LongInt;
Begin
  Pn := CreatePen(0, 1, ClrRGB(C));
  Old := SelectObject(Hps, Pn);
  Dummy := MoveToEx(Hps, X1, Y1, 0);
  { LineTo n'allume pas le dernier point : un pas de plus }
  DX := 0; DY := 0;
  If X2 > X1 Then DX := 1 Else If X2 < X1 Then DX := -1;
  If Y2 > Y1 Then DY := 1 Else If Y2 < Y1 Then DY := -1;
  If (DX = 0) And (DY = 0) Then DX := 1;
  Dummy := LineTo(Hps, X2 + DX, Y2 + DY);
  Dummy := SelectObject(Hps, Old);
  Dummy := DeleteObject(Pn);
End;

{ relief : clair en haut a gauche, sombre en bas a droite (Up) ou l'inverse }
Procedure Bevel(Hps, X1, Y1, X2, Y2 : LongInt; Up : Boolean);
Var A, B : LongInt;
Begin
  If Up Then Begin A := CLR_WHITE; B := CLR_DARKGRAY; End
  Else Begin A := CLR_DARKGRAY; B := CLR_WHITE; End;
  DrawLn(Hps, X1, Y1, X2 - 1, Y1, A);
  DrawLn(Hps, X1, Y1, X1, Y2 - 1, A);
  DrawLn(Hps, X1, Y2 - 1, X2 - 1, Y2 - 1, B);
  DrawLn(Hps, X2 - 1, Y1, X2 - 1, Y2 - 1, B);
End;

{ texte : cellule haut gauche (X, Y), coupe a XMax }
Procedure TextAt(Hps, X, Y, XMax : LongInt; S : String; Fg, Bg : LongInt);
Var Rc : Array[0..3] Of LongInt;
Begin
  If (S = '') Or (X >= XMax) Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Rc[0] := X; Rc[1] := Y; Rc[2] := MinI(XMax, X + Length(S) * CHW); Rc[3] := Y + CHH;
  Dummy := SelectObject(Hps, SysFont);
  Dummy := SetTextColor(Hps, ClrRGB(Fg));
  Dummy := SetBkColor(Hps, ClrRGB(Bg));
  Dummy := ExtTextOutA(Hps, X, Y, ETO_OPAQUE Or ETO_CLIPPED, LongInt(@Rc), LongInt(@TxtBuf), Length(S), 0);
End;

{ texte centre dans (X1, Y1) - (X2, Y2) }
Procedure TextCenter(Hps, X1, Y1, X2, Y2 : LongInt; S : String; Fg, Bg : LongInt);
Var X, Y : LongInt;
Begin
  If Length(S) * CHW > X2 - X1 Then S := Copy(S, 1, MaxI(0, (X2 - X1) Div CHW));
  X := X1 + ((X2 - X1) - Length(S) * CHW) Div 2;
  Y := Y1 + ((Y2 - Y1) - CHH) Div 2;
  TextAt(Hps, X, Y, X2, S, Fg, Bg);
End;

{ petits triangles des boutons de defilement : Dir 0 haut, 1 bas, 2 gauche, 3 droite }
Procedure Arrow(Hps, X1, Y1, X2, Y2, Dir : LongInt);
Var Cx, Cy, K : LongInt;
Begin
  Cx := (X1 + X2) Div 2; Cy := (Y1 + Y2) Div 2;
  For K := 0 To 3 Do
    Case Dir Of
      0 : DrawLn(Hps, Cx - K, Cy - 2 + K, Cx + K, Cy - 2 + K, CLR_BLACK);
      1 : DrawLn(Hps, Cx - K, Cy + 1 - K, Cx + K, Cy + 1 - K, CLR_BLACK);
      2 : DrawLn(Hps, Cx - 2 + K, Cy - K, Cx - 2 + K, Cy + K, CLR_BLACK);
      3 : DrawLn(Hps, Cx + 1 - K, Cy - K, Cx + 1 - K, Cy + K, CLR_BLACK);
    End;
End;

{ ==================================================================== }
{ Fenetres : geometrie                                                  }
{ ==================================================================== }

Function TopWin : LongInt;
Begin
  If NZ > 0 Then TopWin := ZOrd[NZ - 1] Else TopWin := -1;
End;

{ fenetre d'edition active (-1 : aucune, ou la fenetre Messages est devant) }
Function ActEdit : LongInt;
Var W : LongInt;
Begin
  W := TopWin;
  If (W >= 0) And (Wins[W].Kind = WK_EDIT) Then ActEdit := W Else ActEdit := -1;
End;

Procedure Geo(W : LongInt; Var X, Y, Wd, Ht : LongInt);
Begin
  If Wins[W].Max Then
  Begin
    X := 0; Y := 0; Wd := CW; Ht := WorkH;
  End
  Else
  Begin
    X := Wins[W].X; Y := Wins[W].Y; Wd := Wins[W].W; Ht := Wins[W].H;
  End;
End;

{ zone du texte (X1, Y1) - (X2, Y2) exclus }
Procedure TextArea(W : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Var X, Y, Wd, Ht : LongInt;
Begin
  Geo(W, X, Y, Wd, Ht);
  X1 := X + BRD; Y1 := Y + BRD + TTLH;
  X2 := X + Wd - BRD - SBW; Y2 := Y + Ht - BRD - SBW;
End;

Function Rows(W : LongInt) : LongInt;
Var X1, Y1, X2, Y2 : LongInt;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  Rows := MaxI(1, (Y2 - Y1) Div CHH);
End;

Function Cols(W : LongInt) : LongInt;
Var X1, Y1, X2, Y2 : LongInt;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  Cols := MaxI(1, (X2 - X1 - 4) Div CHW);
End;

Function ContentLines(W : LongInt) : LongInt;
Begin
  If Wins[W].Kind = WK_MSG Then ContentLines := MsgCount Else ContentLines := Wins[W].NLines;
End;

Function WinTitle(W : LongInt) : String;
Var T : String;
Begin
  If Wins[W].Kind = WK_MSG Then T := 'Messages'
  Else If Wins[W].FileName = '' Then T := 'NONAME' + IStr(Wins[W].Untitled) + '.PAS'
  Else T := Wins[W].FileName;
  If (Wins[W].Kind = WK_EDIT) And Wins[W].Modified Then T := T + ' *';
  WinTitle := T;
End;

{ ==================================================================== }
{ Selection                                                             }
{ ==================================================================== }

{ debut (L1, C1) et fin (L2, C2) exclue de la selection, dans l'ordre }
Procedure SelRange(W : LongInt; Var L1, C1, L2, C2 : LongInt);
Begin
  If (Wins[W].SAY < Wins[W].CY) Or ((Wins[W].SAY = Wins[W].CY) And (Wins[W].SAX <= Wins[W].CX)) Then
  Begin
    L1 := Wins[W].SAY; C1 := Wins[W].SAX; L2 := Wins[W].CY; C2 := Wins[W].CX;
  End
  Else
  Begin
    L1 := Wins[W].CY; C1 := Wins[W].CX; L2 := Wins[W].SAY; C2 := Wins[W].SAX;
  End;
End;

Function HasSel(W : LongInt) : Boolean;
Begin
  HasSel := (W >= 0) And Wins[W].SelOn And
            ((Wins[W].SAX <> Wins[W].CX) Or (Wins[W].SAY <> Wins[W].CY));
End;

{ le caractere (L, C) est-il selectionne ? }
Function InSel(W, L, C : LongInt) : Boolean;
Var L1, C1, L2, C2 : LongInt;
Begin
  InSel := False;
  If Not HasSel(W) Then Exit;
  SelRange(W, L1, C1, L2, C2);
  If (L < L1) Or (L > L2) Then Exit;
  If (L = L1) And (C < C1) Then Exit;
  If (L = L2) And (C >= C2) Then Exit;
  InSel := True;
End;

{ ==================================================================== }
{ Dessin des fenetres                                                   }
{ ==================================================================== }

{ couleurs des caracteres de la ligne S (etat St au debut) dans Col }
Var Col : Array[0..256] Of Byte;     { couleurs des caracteres (ColorLine) }

Procedure ColorLine(S : String; St : LongInt);
Var K, N, J, C0 : LongInt; Wd : String; Dir : Boolean;
Begin
  N := Length(S);
  K := 1;
  Dir := False;
  While K <= N Do
  Begin
    If St = ST_BRACE Then
    Begin
      If Dir Then Col[K] := CLR_DARKCYAN Else Col[K] := CLR_DARKGREEN;
      If S[K] = '}' Then
      Begin
        St := ST_NORMAL;
        Dir := False;
      End;
      Inc(K);
    End
    Else If St = ST_PAREN Then
    Begin
      Col[K] := CLR_DARKGREEN;
      If (S[K] = '*') And (K < N) And (S[K + 1] = ')') Then
      Begin
        Col[K + 1] := CLR_DARKGREEN;
        St := ST_NORMAL;
        Inc(K);
      End;
      Inc(K);
    End
    Else If S[K] = '{' Then
    Begin
      St := ST_BRACE;
      Dir := (K < N) And (S[K + 1] = '$');
      If Dir Then Col[K] := CLR_DARKCYAN Else Col[K] := CLR_DARKGREEN;
      Inc(K);
    End
    Else If (S[K] = '(') And (K < N) And (S[K + 1] = '*') Then
    Begin
      St := ST_PAREN;
      Col[K] := CLR_DARKGREEN; Col[K + 1] := CLR_DARKGREEN;
      K := K + 2;
    End
    Else If (S[K] = '/') And (K < N) And (S[K + 1] = '/') Then
    Begin
      While K <= N Do
      Begin
        Col[K] := CLR_DARKGREEN;
        Inc(K);
      End;
    End
    Else If S[K] = '''' Then
    Begin
      Col[K] := CLR_DARKRED;
      Inc(K);
      While (K <= N) And (S[K] <> '''') Do
      Begin
        Col[K] := CLR_DARKRED;
        Inc(K);
      End;
      If K <= N Then
      Begin
        Col[K] := CLR_DARKRED;
        Inc(K);
      End;
    End
    Else If (S[K] = '#') And (K < N) And (((S[K + 1] >= '0') And (S[K + 1] <= '9')) Or (S[K + 1] = '$')) Then
    Begin
      Col[K] := CLR_DARKRED;
      Inc(K);
      If (K <= N) And (S[K] = '$') Then
      Begin
        Col[K] := CLR_DARKRED;
        Inc(K);
      End;
      While (K <= N) And IsIdCh(S[K]) Do
      Begin
        Col[K] := CLR_DARKRED;
        Inc(K);
      End;
    End
    Else If ((S[K] >= '0') And (S[K] <= '9')) Or
            ((S[K] = '$') And (K < N) And (Pos(UpCase(S[K + 1]), '0123456789ABCDEF') > 0)) Then
    Begin
      Col[K] := CLR_DARKPINK;
      Inc(K);
      While (K <= N) And (IsIdCh(S[K]) Or (S[K] = '.')) Do
      Begin
        If (S[K] = '.') And (K < N) And (S[K + 1] = '.') Then Break;
        Col[K] := CLR_DARKPINK;
        Inc(K);
      End;
    End
    Else If IsIdCh(S[K]) Then
    Begin
      J := K;
      While (J <= N) And IsIdCh(S[J]) Do Inc(J);
      Wd := ' ' + UpStr(Copy(S, K, J - K)) + ' ';
      If (Pos(Wd, KEYWORDS) > 0) Or (Pos(Wd, KEYWORDS2) > 0) Then C0 := CLR_DARKBLUE
      Else If Pos(Wd, DIRECTIVES) > 0 Then C0 := CLR_BLUE
      Else C0 := CLR_BLACK;
      While K < J Do
      Begin
        Col[K] := C0;
        Inc(K);
      End;
    End
    Else
    Begin
      Col[K] := CLR_BLACK;
      Inc(K);
    End;
  End;
End;

{ une ligne de texte de la fenetre d'edition W }
Procedure PaintLine(Hps, W, I, X1, Y, X2 : LongInt; Active : Boolean);
Var S, Run : String; K, C0, Fg, Bg, Fg0, Bg0, X, NC, Lc : LongInt;
  Sel : Boolean;
Begin
  FillR(Hps, X1, Y, X2, Y + CHH, CLR_WHITE);
  If I >= Wins[W].NLines Then Exit;
  S := GetLine(W, I);
  ColorLine(S, StateAt(W, I));
  NC := (X2 - X1 - 4) Div CHW;
  Lc := Wins[W].LeftC;
  X := X1 + 4;
  Run := '';
  Fg0 := 0; Bg0 := 0;
  For K := Lc + 1 To MinI(Length(S) + 1, Lc + NC) Do
  Begin
    Sel := InSel(W, I, K - 1);
    If K > Length(S) Then
    Begin
      { fin de ligne selectionnee : une case }
      If Not Sel Then Break;
      C0 := 32; Fg := CLR_WHITE; Bg := CLR_DARKBLUE;
    End
    Else
    Begin
      C0 := Ord(S[K]);
      If Sel Then Begin Fg := CLR_WHITE; Bg := CLR_DARKBLUE; End
      Else Begin Fg := Col[K]; Bg := CLR_WHITE; End;
    End;
    If (Run <> '') And ((Fg <> Fg0) Or (Bg <> Bg0)) Then
    Begin
      TextAt(Hps, X, Y, X2, Run, Fg0, Bg0);
      X := X + Length(Run) * CHW;
      Run := '';
    End;
    Run := Run + Chr(C0);
    Fg0 := Fg; Bg0 := Bg;
  End;
  If Run <> '' Then TextAt(Hps, X, Y, X2, Run, Fg0, Bg0);
  { curseur }
  If Active And (I = Wins[W].CY) And (Wins[W].CX >= Lc) And (Wins[W].CX < Lc + NC) Then
  Begin
    X := X1 + 4 + (Wins[W].CX - Lc) * CHW;
    If InsMode Then FillR(Hps, X, Y, X + 2, Y + CHH, CLR_BLACK)
    Else
    Begin
      If Wins[W].CX < Length(S) Then C0 := Ord(S[Wins[W].CX + 1]) Else C0 := 32;
      TextAt(Hps, X, Y, X2, Chr(C0), CLR_WHITE, CLR_BLACK);
    End;
  End;
End;

Procedure PaintText(Hps, W : LongInt; Active : Boolean);
Var X1, Y1, X2, Y2, R, K, I, Fg, Bg : LongInt; S : String;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  If (X2 <= X1) Or (Y2 <= Y1) Then Exit;
  R := (Y2 - Y1 + CHH - 1) Div CHH;
  If Wins[W].Kind = WK_MSG Then
  Begin
    For K := 0 To R - 1 Do
    Begin
      I := Wins[W].TopL + K;
      If (I < MsgCount) And (I = MsgSel) And Active Then Begin Fg := CLR_WHITE; Bg := CLR_DARKBLUE; End
      Else If (I < MsgCount) And (MsgLine[I] = -2) Then Begin Fg := CLR_DARKRED; Bg := CLR_WHITE; End
      Else Begin Fg := CLR_BLACK; Bg := CLR_WHITE; End;
      FillR(Hps, X1, Y1 + K * CHH, X2, MinI(Y2, Y1 + (K + 1) * CHH), Bg);
      If I < MsgCount Then
      Begin
        S := Copy(MsgText[I], Wins[W].LeftC + 1, 255);
        TextAt(Hps, X1 + 4, Y1 + K * CHH, X2, S, Fg, Bg);
      End;
    End;
    Exit;
  End;
  For K := 0 To R - 1 Do
  Begin
    If Y1 + (K + 1) * CHH > Y2 Then
    Begin
      FillR(Hps, X1, Y1 + K * CHH, X2, Y2, CLR_WHITE);
      Break;
    End;
    PaintLine(Hps, W, Wins[W].TopL + K, X1, Y1 + K * CHH, X2, Active);
  End;
End;

{ position (0..Len) et taille du curseur d'une barre de defilement }
Procedure ThumbOf(Len, Total, Vis, Pos : LongInt; Var TPos, TSize : LongInt);
Begin
  If Total <= Vis Then
  Begin
    TPos := 0; TSize := Len;
    Exit;
  End;
  TSize := MaxI(12, (Len * Vis) Div Total);
  If TSize > Len Then TSize := Len;
  TPos := ((Len - TSize) * Pos) Div MaxI(1, Total - Vis);
  If TPos > Len - TSize Then TPos := Len - TSize;
  If TPos < 0 Then TPos := 0;
End;

Procedure PaintButton(Hps, X1, Y1, X2, Y2 : LongInt);
Begin
  FillR(Hps, X1, Y1, X2, Y2, CLR_PALEGRAY);
  Bevel(Hps, X1, Y1, X2, Y2, True);
End;

Procedure PaintScrollBars(Hps, W : LongInt);
Var X1, Y1, X2, Y2, L, TP, TS, MaxC : LongInt;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  { verticale }
  FillR(Hps, X2, Y1, X2 + SBW, Y2, CLR_PALEGRAY);
  DrawLn(Hps, X2, Y1, X2, Y2 - 1, CLR_DARKGRAY);
  PaintButton(Hps, X2, Y1, X2 + SBW, Y1 + SBW); Arrow(Hps, X2, Y1, X2 + SBW, Y1 + SBW, 0);
  PaintButton(Hps, X2, Y2 - SBW, X2 + SBW, Y2); Arrow(Hps, X2, Y2 - SBW, X2 + SBW, Y2, 1);
  L := Y2 - Y1 - 2 * SBW;
  If L > 4 Then
  Begin
    ThumbOf(L, ContentLines(W), Rows(W), Wins[W].TopL, TP, TS);
    PaintButton(Hps, X2, Y1 + SBW + TP, X2 + SBW, Y1 + SBW + TP + TS);
  End;
  { horizontale }
  FillR(Hps, X1, Y2, X2, Y2 + SBW, CLR_PALEGRAY);
  DrawLn(Hps, X1, Y2, X2 - 1, Y2, CLR_DARKGRAY);
  PaintButton(Hps, X1, Y2, X1 + SBW, Y2 + SBW); Arrow(Hps, X1, Y2, X1 + SBW, Y2 + SBW, 2);
  PaintButton(Hps, X2 - SBW, Y2, X2, Y2 + SBW); Arrow(Hps, X2 - SBW, Y2, X2, Y2 + SBW, 3);
  L := X2 - X1 - 2 * SBW;
  MaxC := MAXLEN + 1;
  If L > 4 Then
  Begin
    ThumbOf(L, MaxC, Cols(W), Wins[W].LeftC, TP, TS);
    PaintButton(Hps, X1 + SBW + TP, Y2, X1 + SBW + TP + TS, Y2 + SBW);
  End;
  { coin de redimensionnement }
  FillR(Hps, X2, Y2, X2 + SBW, Y2 + SBW, CLR_PALEGRAY);
  DrawLn(Hps, X2 + 4, Y2 + SBW - 2, X2 + SBW - 2, Y2 + 4, CLR_DARKGRAY);
  DrawLn(Hps, X2 + 8, Y2 + SBW - 2, X2 + SBW - 2, Y2 + 8, CLR_DARKGRAY);
  DrawLn(Hps, X2 + 12, Y2 + SBW - 2, X2 + SBW - 2, Y2 + 12, CLR_DARKGRAY);
End;

Procedure PaintFrame(Hps, W : LongInt; Active : Boolean);
Var X, Y, Wd, Ht, Tb, Tf, B, K : LongInt; T : String;
Begin
  Geo(W, X, Y, Wd, Ht);
  { bordure en relief }
  FillR(Hps, X, Y, X + Wd, Y + BRD, CLR_PALEGRAY);
  FillR(Hps, X, Y + Ht - BRD, X + Wd, Y + Ht, CLR_PALEGRAY);
  FillR(Hps, X, Y, X + BRD, Y + Ht, CLR_PALEGRAY);
  FillR(Hps, X + Wd - BRD, Y, X + Wd, Y + Ht, CLR_PALEGRAY);
  Bevel(Hps, X, Y, X + Wd, Y + Ht, True);
  DrawLn(Hps, X + BRD - 1, Y + BRD - 1, X + Wd - BRD, Y + BRD - 1, CLR_DARKGRAY);
  { barre de titre aux couleurs du systeme }
  If Active Then Begin Tb := SYSCLR_ACTIVETITLE; Tf := SYSCLR_ACTIVETITLETEXT; End
  Else Begin Tb := SYSCLR_INACTIVETITLE; Tf := SYSCLR_INACTIVETITLETEXT; End;
  FillR(Hps, X + BRD, Y + BRD, X + Wd - BRD, Y + BRD + TTLH, Tb);
  B := TTLH - 4;
  { case de fermeture (menu systeme) a gauche }
  PaintButton(Hps, X + BRD + 2, Y + BRD + 2, X + BRD + 2 + B, Y + BRD + 2 + B);
  FillR(Hps, X + BRD + 5, Y + BRD + 1 + B Div 2, X + BRD + B - 1, Y + BRD + 3 + B Div 2, CLR_BLACK);
  { case d'agrandissement a droite }
  PaintButton(Hps, X + Wd - BRD - 2 - B, Y + BRD + 2, X + Wd - BRD - 2, Y + BRD + 2 + B);
  If Wins[W].Max Then
  Begin
    { restaurer : deux petites fenetres }
    K := X + Wd - BRD - 2 - B;
    DrawLn(Hps, K + 6, Y + BRD + 5, K + B - 4, Y + BRD + 5, CLR_BLACK);
    DrawLn(Hps, K + B - 4, Y + BRD + 5, K + B - 4, Y + BRD + B - 7, CLR_BLACK);
    FillR(Hps, K + 4, Y + BRD + 8, K + B - 6, Y + BRD + 10, CLR_BLACK);
    DrawLn(Hps, K + 4, Y + BRD + 8, K + 4, Y + BRD + B - 2, CLR_BLACK);
    DrawLn(Hps, K + B - 7, Y + BRD + 8, K + B - 7, Y + BRD + B - 2, CLR_BLACK);
    DrawLn(Hps, K + 4, Y + BRD + B - 2, K + B - 7, Y + BRD + B - 2, CLR_BLACK);
  End
  Else
  Begin
    K := X + Wd - BRD - 2 - B;
    FillR(Hps, K + 4, Y + BRD + 6, K + B - 4, Y + BRD + 8, CLR_BLACK);
    DrawLn(Hps, K + 4, Y + BRD + 6, K + 4, Y + BRD + B - 2, CLR_BLACK);
    DrawLn(Hps, K + B - 5, Y + BRD + 6, K + B - 5, Y + BRD + B - 2, CLR_BLACK);
    DrawLn(Hps, K + 4, Y + BRD + B - 2, K + B - 5, Y + BRD + B - 2, CLR_BLACK);
  End;
  { titre : numero et nom }
  Wins[W].ShownMod := Wins[W].Modified;
  T := IStr(Wins[W].Num) + ' - ' + WinTitle(W);
  TextCenter(Hps, X + BRD + B + 6, Y + BRD, X + Wd - BRD - B - 6, Y + BRD + TTLH, T, Tf, Tb);
End;

Procedure PaintWin(Hps, W : LongInt; Active : Boolean);
Begin
  PaintFrame(Hps, W, Active);
  PaintText(Hps, W, Active);
  PaintScrollBars(Hps, W);
End;

Function TargetName(T : LongInt) : String;
Begin
  If T = 0 Then TargetName := 'Windows' Else TargetName := 'Console Win32';
End;

Procedure PaintStatus(Hps : LongInt);
Var Y, W, X, R : LongInt; S : String;
Begin
  Y := WorkH;
  FillR(Hps, 0, Y, CW, CH, CLR_PALEGRAY);
  DrawLn(Hps, 0, Y, CW - 1, Y, CLR_WHITE);
  W := ActEdit;
  R := CW - 4;
  { champs de droite : destination, modifie, insertion, position }
  S := TargetName(Target);
  X := R - Length(S) * CHW - 8;
  Bevel(Hps, X, Y + 3, R, CH - 2, False);
  TextAt(Hps, X + 4, Y + 4, R, S, CLR_BLACK, CLR_PALEGRAY);
  R := X - 4;
  If InsMode Then S := 'Insertion' Else S := 'Refrappe';
  X := R - 9 * CHW - 8;
  Bevel(Hps, X, Y + 3, R, CH - 2, False);
  TextAt(Hps, X + 4, Y + 4, R, S, CLR_BLACK, CLR_PALEGRAY);
  R := X - 4;
  If (W >= 0) And Wins[W].Modified Then S := Acc('Modifi^e') Else S := '';
  X := R - 7 * CHW - 8;
  Bevel(Hps, X, Y + 3, R, CH - 2, False);
  TextAt(Hps, X + 4, Y + 4, R, S, CLR_DARKRED, CLR_PALEGRAY);
  R := X - 4;
  If W >= 0 Then S := 'Ligne ' + IStr(Wins[W].CY + 1) + '  Col ' + IStr(Wins[W].CX + 1) Else S := '';
  X := R - 17 * CHW - 8;
  Bevel(Hps, X, Y + 3, R, CH - 2, False);
  TextAt(Hps, X + 4, Y + 4, R, S, CLR_BLACK, CLR_PALEGRAY);
  { message ou rappel des touches }
  If StatusMsg <> '' Then S := StatusMsg
  Else S := Acc('F2 Enreg.  F3 Ouvrir  F9 Compiler  Ctrl+F9 Ex^ecuter');
  Bevel(Hps, 4, Y + 3, X - 4, CH - 2, False);
  TextAt(Hps, 8, Y + 4, X - 6, S, CLR_BLACK, CLR_PALEGRAY);
End;

Procedure PaintAll(H : LongInt);
Var Hps, K, W, X1, Y1, X2, Y2 : LongInt; Only : Boolean;
Begin
  Hps := BeginPaint(H, LongInt(@PaintS));
  { seulement la zone de texte de la fenetre active a mettre a jour ? }
  W := TopWin;
  Only := False;
  If W >= 0 Then
  Begin
    TextArea(W, X1, Y1, X2, Y2);
    Only := (PaintS[4] > PaintS[2]) And (PaintS[2] >= X1) And (PaintS[4] <= X2) And
            (PaintS[3] >= Y1) And (PaintS[5] <= Y2);
  End;
  If Only Then PaintText(Hps, W, True)
  Else
  Begin
    FillR(Hps, 0, 0, CW, WorkH, CLR_DARKGRAY);
    For K := 0 To NZ - 1 Do PaintWin(Hps, ZOrd[K], K = NZ - 1);
    If NZ = 0 Then
      TextCenter(Hps, 0, 0, CW, WorkH, Acc('Fichier, Nouveau (Ctrl+N) ou Ouvrir (F3) : un source Pascal'),
                 CLR_PALEGRAY, CLR_DARKGRAY);
    PaintStatus(Hps);
  End;
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

{ ==================================================================== }
{ Invalidation                                                          }
{ ==================================================================== }

Procedure InvRect(X1, Y1, X2, Y2 : LongInt);
Var Rc : Array[0..3] Of LongInt;
Begin
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2; Rc[3] := Y2;
  Dummy := InvalidateRect(Client, LongInt(@Rc), 0);
End;

Procedure Redraw;
Begin
  Dummy := InvalidateRect(Client, 0, 0);
End;

{ texte de la fenetre active seulement (frappe) ; barre d'etat a part }
Procedure RedrawText(W : LongInt);
Var X1, Y1, X2, Y2 : LongInt;
Begin
  If (W <> TopWin) Or (Wins[W].ShownMod <> Wins[W].Modified) Then
  Begin
    Redraw;
    Exit;
  End;
  TextArea(W, X1, Y1, X2, Y2);
  InvRect(X1, Y1, X2, Y2);
  InvRect(0, WorkH, CW, CH);
End;

{ ==================================================================== }
{ Fenetres : creation, activation, disposition                          }
{ ==================================================================== }

Procedure ZRemove(W : LongInt);
Var K, J : LongInt;
Begin
  J := 0;
  For K := 0 To NZ - 1 Do
    If ZOrd[K] <> W Then
    Begin
      ZOrd[J] := ZOrd[K];
      Inc(J);
    End;
  NZ := J;
End;

Procedure Activate(W : LongInt);
Begin
  If (W < 0) Or Not Wins[W].Used Then Exit;
  ZRemove(W);
  ZOrd[NZ] := W;
  Inc(NZ);
  Redraw;
End;

Function FreeWin : LongInt;
Var K : LongInt;
Begin
  FreeWin := -1;
  For K := 0 To MAXWIN - 1 Do
    If Not Wins[K].Used Then
    Begin
      FreeWin := K;
      Exit;
    End;
End;

{ position par defaut d'une nouvelle fenetre (en cascade) }
Procedure PlaceNew(W : LongInt);
Var N : LongInt;
Begin
  N := NZ Mod 8;
  Wins[W].X := 8 + N * 22;
  Wins[W].Y := 6 + N * 22;
  Wins[W].W := MaxI(220, CW - 60 - N * 22);
  Wins[W].H := MaxI(140, WorkH - 50 - N * 22);
  If Wins[W].X + Wins[W].W > CW Then Wins[W].W := MaxI(120, CW - Wins[W].X);
  If Wins[W].Y + Wins[W].H > WorkH Then Wins[W].H := MaxI(100, WorkH - Wins[W].Y);
  Wins[W].Max := False;
End;

Function NewWin(Kind : LongInt) : LongInt;
Var W : LongInt;
Begin
  NewWin := -1;
  W := FreeWin;
  If W < 0 Then
  Begin
    ShowMsg(Acc('Trop de fen^etres ouvertes : fermez-en une.'), 'Pascal Developer', MB_OK Or MB_WARNING);
    Exit;
  End;
  FillChar(Wins[W], SizeOf(TWin), 0);
  Wins[W].Used := True;
  Wins[W].Kind := Kind;
  Wins[W].FileName := '';
  Inc(WinSeq);
  Wins[W].Num := WinSeq;
  PlaceNew(W);
  NewWin := W;
End;

{ document vide sans nom }
Function NewDoc : LongInt;
Var W : LongInt;
Begin
  NewDoc := -1;
  W := NewWin(WK_EDIT);
  If W < 0 Then Exit;
  If Not DocInit(W, 512) Then
  Begin
    Wins[W].Used := False;
    ShowMsg(Acc('M^emoire insuffisante.'), 'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  If DocIns(W, 0, '') Then ;
  Wins[W].Modified := False;
  Inc(UntitledSeq);
  Wins[W].Untitled := UntitledSeq;
  Activate(W);
  NewDoc := W;
End;

Function FindDoc(N : String) : LongInt;
Var K : LongInt;
Begin
  FindDoc := -1;
  N := FullPath(N);
  For K := 0 To MAXWIN - 1 Do
    If Wins[K].Used And (Wins[K].Kind = WK_EDIT) And (Wins[K].FileName = N) Then
    Begin
      FindDoc := K;
      Exit;
    End;
End;

{ ouvrir N (deja ouvert : l'activer) ; Quiet : sans message d'erreur }
Function OpenDoc(N : String; Quiet : Boolean) : LongInt;
Var W, C, Sz : LongInt;
Begin
  OpenDoc := -1;
  N := Trim(N);
  If N = '' Then Exit;
  If Not HasExt(N) And Not FileExists(N) Then N := N + '.PAS';
  N := FullPath(N);
  W := FindDoc(N);
  If W >= 0 Then
  Begin
    Activate(W);
    OpenDoc := W;
    Exit;
  End;
  If Not FileExists(N) Then
  Begin
    If Not Quiet Then ShowMsg(Acc('Fichier introuvable : ') + N, 'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  W := NewWin(WK_EDIT);
  If W < 0 Then Exit;
  { capacite : environ une ligne par 20 octets du fichier }
  Sz := FileSizeOf(N);
  C := MaxI(512, Sz Div 20 + 256);
  If Not DocInit(W, C) Then
  Begin
    Wins[W].Used := False;
    ShowMsg(Acc('M^emoire insuffisante pour ') + N, 'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  If Not LoadFile(W, N) Then
  Begin
    DocFree(W);
    Wins[W].Used := False;
    ShowMsg(Acc('Lecture impossible : ') + N, 'Pascal Developer', MB_OK Or MB_ERROR);
    Exit;
  End;
  Wins[W].FileName := N;
  Activate(W);
  StatusMsg := NameOf(N) + ' : ' + NStr(Wins[W].NLines) + ' lignes';
  OpenDoc := W;
End;

Procedure CloseWinNow(W : LongInt);
Begin
  If W = MsgWin Then MsgWin := -1;
  If Wins[W].Kind = WK_EDIT Then DocFree(W);
  Wins[W].Used := False;
  ZRemove(W);
  Redraw;
End;

Function SaveDoc(W : LongInt) : Boolean; Forward;
Procedure OpenInput(Mode : LongInt; Title, Prompt, Def : String); Forward;

{ fermer W en demandant d'enregistrer ; Faux : annule }
Function CloseWin(W : LongInt) : Boolean;
Var R : LongInt;
Begin
  CloseWin := False;
  If (W < 0) Or Not Wins[W].Used Then Exit;
  If (Wins[W].Kind = WK_EDIT) And Wins[W].Modified Then
  Begin
    Activate(W);
    R := AskYesNo(WinTitle(W) + Acc(' a ^et^e modifi^e. Enregistrer les modifications ?'),
                  'Pascal Developer', MB_YESNOCANCEL Or MB_QUERY);
    If R = MBID_CANCEL Then Exit;
    If R = MBID_YES Then
      If Not SaveDoc(W) Then Exit;
  End;
  CloseWinNow(W);
  CloseWin := True;
End;

Function CloseAll : Boolean;
Var K : LongInt;
Begin
  CloseAll := False;
  For K := 0 To MAXWIN - 1 Do
    If Wins[K].Used Then
      If Not CloseWin(K) Then Exit;
  CloseAll := True;
End;

Procedure Tile;
Var K, N, C, R, I, Wd, Ht, W, AreaH : LongInt;
Begin
  If NZ = 0 Then Exit;
  { Messages en bas sur toute la largeur, les sources en grille au-dessus }
  AreaH := WorkH;
  If (MsgWin >= 0) And Wins[MsgWin].Used Then
  Begin
    Wins[MsgWin].Max := False;
    Wins[MsgWin].H := MaxI(80, WorkH Div 3);
    Wins[MsgWin].X := 0; Wins[MsgWin].W := CW;
    Wins[MsgWin].Y := WorkH - Wins[MsgWin].H;
    AreaH := Wins[MsgWin].Y;
  End;
  N := 0;
  For K := 0 To NZ - 1 Do
    If Wins[ZOrd[K]].Kind = WK_EDIT Then Inc(N);
  If N = 0 Then
  Begin
    Redraw;
    Exit;
  End;
  C := 1;
  While C * C < N Do Inc(C);
  R := (N + C - 1) Div C;
  Wd := CW Div C; Ht := AreaH Div R;
  I := 0;
  For K := 0 To NZ - 1 Do
  Begin
    W := ZOrd[K];
    If Wins[W].Kind = WK_EDIT Then
    Begin
      Wins[W].Max := False;
      Wins[W].X := (I Mod C) * Wd; Wins[W].Y := (I Div C) * Ht;
      Wins[W].W := Wd; Wins[W].H := Ht;
      { derniere rangee incomplete : les fenetres s'elargissent }
      If (I Div C = R - 1) And (N Mod C <> 0) Then
      Begin
        Wins[W].W := CW Div (N Mod C);
        Wins[W].X := (I Mod C) * Wins[W].W;
      End;
      Inc(I);
    End;
  End;
  Redraw;
End;

Procedure Cascade;
Var K, W : LongInt;
Begin
  For K := 0 To NZ - 1 Do
  Begin
    W := ZOrd[K];
    Wins[W].Max := False;
    Wins[W].X := K * 22; Wins[W].Y := K * 22;
    Wins[W].W := MaxI(200, CW - (NZ - 1) * 22);
    Wins[W].H := MaxI(120, WorkH - (NZ - 1) * 22);
  End;
  Redraw;
End;

Procedure NextWin;
Var T : LongInt;
Begin
  If NZ < 2 Then Exit;
  { la fenetre active passe dessous }
  T := ZOrd[NZ - 1];
  MemMove(LongInt(@ZOrd[0]), LongInt(@ZOrd[1]), (NZ - 1) * 4);
  ZOrd[0] := T;
  Redraw;
End;

Procedure ToggleMax(W : LongInt);
Begin
  Wins[W].Max := Not Wins[W].Max;
  Redraw;
End;

{ ==================================================================== }
{ Curseur et defilement                                                 }
{ ==================================================================== }

{ rendre le curseur visible }
Procedure ShowCursor(W : LongInt);
Var R, C : LongInt;
Begin
  R := Rows(W); C := Cols(W);
  If Wins[W].CY < Wins[W].TopL Then Wins[W].TopL := Wins[W].CY;
  If Wins[W].CY >= Wins[W].TopL + R Then Wins[W].TopL := Wins[W].CY - R + 1;
  If Wins[W].CX < Wins[W].LeftC Then Wins[W].LeftC := Wins[W].CX;
  If Wins[W].CX >= Wins[W].LeftC + C Then Wins[W].LeftC := Wins[W].CX - C + 1;
  If Wins[W].TopL < 0 Then Wins[W].TopL := 0;
  If Wins[W].LeftC < 0 Then Wins[W].LeftC := 0;
End;

Procedure ClampCursor(W : LongInt);
Begin
  If Wins[W].CY >= Wins[W].NLines Then Wins[W].CY := Wins[W].NLines - 1;
  If Wins[W].CY < 0 Then Wins[W].CY := 0;
  If Wins[W].CX < 0 Then Wins[W].CX := 0;
  If Wins[W].CX > MAXLEN Then Wins[W].CX := MAXLEN;
End;

{ deplacement : Ext etend la selection (Maj) }
Procedure CurTo(W, X, Y : LongInt; Ext : Boolean);
Begin
  If Ext Then
  Begin
    If Not Wins[W].SelOn Then
    Begin
      Wins[W].SelOn := True;
      Wins[W].SAX := Wins[W].CX; Wins[W].SAY := Wins[W].CY;
    End;
  End
  Else Wins[W].SelOn := False;
  Wins[W].CX := X; Wins[W].CY := Y;
  ClampCursor(W);
  ShowCursor(W);
End;

Procedure ScrollBy(W, DL, DC : LongInt);
Var MaxT : LongInt;
Begin
  MaxT := MaxI(0, ContentLines(W) - 1);
  Wins[W].TopL := Wins[W].TopL + DL;
  If Wins[W].TopL > MaxT Then Wins[W].TopL := MaxT;
  If Wins[W].TopL < 0 Then Wins[W].TopL := 0;
  Wins[W].LeftC := Wins[W].LeftC + DC;
  If Wins[W].LeftC > MAXLEN Then Wins[W].LeftC := MAXLEN;
  If Wins[W].LeftC < 0 Then Wins[W].LeftC := 0;
End;

{ ==================================================================== }
{ Edition                                                               }
{ ==================================================================== }

{ ligne completee d'espaces jusqu'a la colonne X }
Function PadTo(S : String; X : LongInt) : String;
Begin
  While Length(S) < X Do S := S + ' ';
  PadTo := S;
End;

{ supprimer la selection ; Vrai si quelque chose a ete supprime }
Function DeleteSel(W : LongInt) : Boolean;
Var L1, C1, L2, C2, K : LongInt; S, T : String;
Begin
  DeleteSel := False;
  If Not HasSel(W) Then
  Begin
    Wins[W].SelOn := False;
    Exit;
  End;
  SelRange(W, L1, C1, L2, C2);
  S := PadTo(GetLine(W, L1), C1);
  T := GetLine(W, L2);
  S := Copy(S, 1, C1) + Copy(T, C2 + 1, 255);
  For K := L2 DownTo L1 + 1 Do DocDel(W, K);
  SetLine(W, L1, S);
  Wins[W].CX := C1; Wins[W].CY := L1;
  Wins[W].SelOn := False;
  ShowCursor(W);
  DeleteSel := True;
End;

Procedure TypeChar(W : LongInt; C : Char);
Var S : String;
Begin
  If DeleteSel(W) Then ;
  If Wins[W].CX >= MAXLEN Then Exit;
  S := PadTo(GetLine(W, Wins[W].CY), Wins[W].CX);
  If InsMode Or (Wins[W].CX >= Length(S)) Then
  Begin
    If Length(TrimR(S)) >= MAXLEN Then Exit;
    Insert(C, S, Wins[W].CX + 1);
  End
  Else S[Wins[W].CX + 1] := C;
  SetLine(W, Wins[W].CY, S);
  Inc(Wins[W].CX);
  ShowCursor(W);
End;

{ Entree : couper la ligne, retrait de la ligne courante }
Procedure NewLine(W : LongInt);
Var S, Ind : String; K : LongInt;
Begin
  If DeleteSel(W) Then ;
  S := GetLine(W, Wins[W].CY);
  K := 0;
  While (K < Length(S)) And (S[K + 1] = ' ') Do Inc(K);
  If K > Wins[W].CX Then K := Wins[W].CX;
  Ind := Spaces(K);
  If Not DocIns(W, Wins[W].CY + 1, Ind + Trim(Copy(S, Wins[W].CX + 1, 255))) Then Exit;
  SetLine(W, Wins[W].CY, TrimR(Copy(S, 1, Wins[W].CX)));
  Inc(Wins[W].CY);
  Wins[W].CX := K;
  ShowCursor(W);
End;

Procedure BackSpace(W : LongInt);
Var S, P : String;
Begin
  If DeleteSel(W) Then Exit;
  If Wins[W].CX > 0 Then
  Begin
    S := GetLine(W, Wins[W].CY);
    If Wins[W].CX <= Length(S) Then Delete(S, Wins[W].CX, 1);
    SetLine(W, Wins[W].CY, S);
    Dec(Wins[W].CX);
  End
  Else If Wins[W].CY > 0 Then
  Begin
    P := GetLine(W, Wins[W].CY - 1);
    S := GetLine(W, Wins[W].CY);
    If Length(P) + Length(S) > MAXLEN Then Exit;
    SetLine(W, Wins[W].CY - 1, P + S);
    DocDel(W, Wins[W].CY);
    Dec(Wins[W].CY);
    Wins[W].CX := Length(P);
  End;
  ShowCursor(W);
End;

Procedure DeleteChar(W : LongInt);
Var S, N : String;
Begin
  If DeleteSel(W) Then Exit;
  S := GetLine(W, Wins[W].CY);
  If Wins[W].CX < Length(S) Then
  Begin
    Delete(S, Wins[W].CX + 1, 1);
    SetLine(W, Wins[W].CY, S);
  End
  Else If Wins[W].CY < Wins[W].NLines - 1 Then
  Begin
    N := GetLine(W, Wins[W].CY + 1);
    S := PadTo(S, Wins[W].CX);
    If Length(S) + Length(N) > MAXLEN Then Exit;
    SetLine(W, Wins[W].CY, S + N);
    DocDel(W, Wins[W].CY + 1);
  End;
End;

Procedure DeleteLine(W : LongInt);
Begin
  Wins[W].SelOn := False;
  If Wins[W].NLines <= 1 Then SetLine(W, 0, '')
  Else DocDel(W, Wins[W].CY);
  ClampCursor(W);
  Wins[W].CX := 0;
  ShowCursor(W);
End;

Procedure TabKey(W : LongInt);
Var N : LongInt;
Begin
  N := TABSZ - (Wins[W].CX Mod TABSZ);
  While N > 0 Do
  Begin
    TypeChar(W, ' ');
    Dec(N);
  End;
End;

{ mot sous le curseur ; Path : caracteres d'un nom de fichier admis }
Function OkCh(C : Char; Path : Boolean) : Boolean;
Begin
  OkCh := IsIdCh(C) Or (Path And ((C = '.') Or (C = '\') Or (C = ':') Or (C = '-')));
End;

Function WordAt(W : LongInt; Path : Boolean) : String;
Var S : String; A, B : LongInt;
Begin
  S := GetLine(W, Wins[W].CY);
  A := Wins[W].CX + 1;
  If (A > Length(S)) Or Not OkCh(S[A], Path) Then
    If (A > 1) And (A - 1 <= Length(S)) And OkCh(S[A - 1], Path) Then Dec(A);
  If (A > Length(S)) Or Not OkCh(S[A], Path) Then
  Begin
    WordAt := '';
    Exit;
  End;
  B := A;
  While (A > 1) And OkCh(S[A - 1], Path) Do Dec(A);
  While (B < Length(S)) And OkCh(S[B + 1], Path) Do Inc(B);
  WordAt := Copy(S, A, B - A + 1);
End;

{ selectionner le mot sous le curseur (double clic) }
Procedure SelectWord(W : LongInt);
Var S : String; A, B : LongInt;
Begin
  S := GetLine(W, Wins[W].CY);
  A := Wins[W].CX + 1;
  If (A > Length(S)) Or Not IsIdCh(S[A]) Then Exit;
  B := A;
  While (A > 1) And IsIdCh(S[A - 1]) Do Dec(A);
  While (B < Length(S)) And IsIdCh(S[B + 1]) Do Inc(B);
  Wins[W].SelOn := True;
  Wins[W].SAX := A - 1; Wins[W].SAY := Wins[W].CY;
  Wins[W].CX := B;
End;

Procedure SelectAll(W : LongInt);
Begin
  Wins[W].SelOn := True;
  Wins[W].SAX := 0; Wins[W].SAY := 0;
  Wins[W].CY := Wins[W].NLines - 1;
  Wins[W].CX := LineLen(W, Wins[W].CY);
  ShowCursor(W);
End;

{ mot suivant / precedent }
Procedure WordRight(W : LongInt; Ext : Boolean);
Var S : String; X, Y : LongInt;
Begin
  X := Wins[W].CX; Y := Wins[W].CY;
  S := GetLine(W, Y);
  If X >= Length(S) Then
  Begin
    If Y < Wins[W].NLines - 1 Then
    Begin
      Inc(Y);
      S := GetLine(W, Y);
      X := 0;
      While (X < Length(S)) And (S[X + 1] = ' ') Do Inc(X);
    End;
  End
  Else
  Begin
    While (X < Length(S)) And IsIdCh(S[X + 1]) Do Inc(X);
    While (X < Length(S)) And Not IsIdCh(S[X + 1]) Do Inc(X);
  End;
  CurTo(W, X, Y, Ext);
End;

Procedure WordLeft(W : LongInt; Ext : Boolean);
Var S : String; X, Y : LongInt;
Begin
  X := Wins[W].CX; Y := Wins[W].CY;
  S := GetLine(W, Y);
  If X > Length(S) Then X := Length(S);
  If X = 0 Then
  Begin
    If Y > 0 Then
    Begin
      Dec(Y);
      X := LineLen(W, Y);
    End;
  End
  Else
  Begin
    While (X > 0) And Not IsIdCh(S[X]) Do Dec(X);
    While (X > 0) And IsIdCh(S[X]) Do Dec(X);
  End;
  CurTo(W, X, Y, Ext);
End;

{ ==================================================================== }
{ Presse-papiers (CF_TEXT, lignes separees par CR LF)                   }
{ ==================================================================== }

Var ClipN : LongInt;

Procedure ClipPut(C : LongInt);
Begin
  If ClipN < SizeOf(ClipBuf) - 1 Then
  Begin
    ClipBuf[ClipN] := C;
    Inc(ClipN);
  End;
End;

Function SelText(W : LongInt) : Boolean;
Var L1, C1, L2, C2, K, J : LongInt; S : String;
Begin
  SelText := False;
  ClipN := 0;
  If Not HasSel(W) Then Exit;
  SelRange(W, L1, C1, L2, C2);
  For K := L1 To L2 Do
  Begin
    S := GetLine(W, K);
    If K = L2 Then S := Copy(PadTo(S, C2), 1, C2);
    If K = L1 Then S := Copy(S, C1 + 1, 255);
    For J := 1 To Length(S) Do ClipPut(Ord(S[J]));
    If K < L2 Then
    Begin
      ClipPut(13); ClipPut(10);
    End;
  End;
  ClipBuf[ClipN] := 0;
  SelText := True;
End;

Procedure CopySel(W : LongInt);
Var Hg, P : LongInt;
Begin
  If Not SelText(W) Then Exit;
  If OpenClipboard(Frame) <> 0 Then
  Begin
    Dummy := EmptyClipboard;
    Hg := GlobalAlloc(GMEM_MOVEABLE, ClipN + 1);
    If Hg <> 0 Then
    Begin
      P := GlobalLock(Hg);
      MemMove(LongInt(@ClipBuf), P, ClipN + 1);
      Dummy := GlobalUnlock(Hg);
      Dummy := SetClipboardData(CF_TEXT, Hg);
    End;
    Dummy := CloseClipboard;
  End;
End;

Procedure CutSel(W : LongInt);
Begin
  CopySel(W);
  If DeleteSel(W) Then ;
End;

{ inserer le texte T (CR LF, LF) au curseur }
Procedure InsertText(W, A : LongInt);
Var S, Tail, Cur : String; C : LongInt;
Begin
  If DeleteSel(W) Then ;
  S := PadTo(GetLine(W, Wins[W].CY), Wins[W].CX);
  Tail := Copy(S, Wins[W].CX + 1, 255);
  Cur := Copy(S, 1, Wins[W].CX);
  C := RdB(A);
  While C <> 0 Do
  Begin
    If C = 10 Then
    Begin
      SetLine(W, Wins[W].CY, Cur);
      If Not DocIns(W, Wins[W].CY + 1, '') Then Exit;
      Inc(Wins[W].CY);
      Cur := '';
    End
    Else If C = 9 Then
    Begin
      Repeat
        Cur := Cur + ' ';
      Until Length(Cur) Mod 8 = 0;
    End
    Else If (C <> 13) And (Length(Cur) < MAXLEN) Then Cur := Cur + Chr(C);
    Inc(A);
    C := RdB(A);
  End;
  Wins[W].CX := Length(Cur);
  SetLine(W, Wins[W].CY, Cur + Tail);
  ShowCursor(W);
End;

Procedure Paste(W : LongInt);
Var Hg, A : LongInt;
Begin
  If OpenClipboard(Frame) = 0 Then Exit;
  Hg := GetClipboardData(CF_TEXT);
  If Hg <> 0 Then
  Begin
    A := GlobalLock(Hg);
    If A <> 0 Then InsertText(W, A);
    Dummy := GlobalUnlock(Hg);
  End;
  Dummy := CloseClipboard;
End;

{ ==================================================================== }
{ Recherche                                                             }
{ ==================================================================== }

{ occurrence suivante de FindText (sans distinction des majuscules) }
Procedure FindAgain(W : LongInt);
Var K, Y, X, P : LongInt; S, F : String;
Begin
  If (W < 0) Or (FindText = '') Then Exit;
  F := UpStr(FindText);
  Y := Wins[W].CY;
  X := Wins[W].CX;
  For K := 0 To Wins[W].NLines Do
  Begin
    S := UpStr(GetLine(W, Y));
    If K = 0 Then S := Spaces(MinI(X, Length(S))) + Copy(S, X + 1, 255);
    P := Pos(F, S);
    If P > 0 Then
    Begin
      Wins[W].SelOn := True;
      Wins[W].SAY := Y; Wins[W].SAX := P - 1;
      Wins[W].CY := Y; Wins[W].CX := P - 1 + Length(F);
      ShowCursor(W);
      StatusMsg := '';
      Redraw;
      Exit;
    End;
    Inc(Y);
    X := 0;
    If Y >= Wins[W].NLines Then Y := 0;
  End;
  StatusMsg := Acc('Cha^ine introuvable : ') + FindText;
  Redraw;
End;

Procedure GotoLine(W, N : LongInt);
Begin
  If W < 0 Then Exit;
  If N < 1 Then N := 1;
  If N > Wins[W].NLines Then N := Wins[W].NLines;
  Wins[W].SelOn := False;
  Wins[W].CY := N - 1;
  Wins[W].CX := 0;
  { la ligne au premier tiers de la fenetre }
  Wins[W].TopL := MaxI(0, N - 1 - Rows(W) Div 3);
  ShowCursor(W);
  Redraw;
End;

{ ==================================================================== }
{ Fenetre Messages                                                      }
{ ==================================================================== }

Procedure MsgClear;
Begin
  MsgCount := 0;
  MsgSel := -1;
End;

{ Ln : ligne du source (>= 1), -1 : sans ligne, -2 : erreur sans ligne }
Procedure MsgAdd(S : String; L : LongInt);
Begin
  If MsgCount >= MAXMSG Then Exit;
  MsgText[MsgCount] := S;
  MsgLine[MsgCount] := L;
  Inc(MsgCount);
End;

Procedure ShowMessages;
Var W : LongInt;
Begin
  If MsgWin < 0 Then
  Begin
    W := NewWin(WK_MSG);
    If W < 0 Then Exit;
    MsgWin := W;
    Wins[W].X := 0; Wins[W].W := CW;
    Wins[W].H := MaxI(100, WorkH Div 3);
    Wins[W].Y := MaxI(0, WorkH - Wins[W].H);
  End;
  Wins[MsgWin].TopL := 0;
  Activate(MsgWin);
End;

{ aller a la ligne du message I dans le source compile }
Procedure MsgGo(I : LongInt);
Var W : LongInt;
Begin
  If (I < 0) Or (I >= MsgCount) Or (MsgLine[I] < 1) Then Exit;
  W := FindDoc(LastSrc);
  If W < 0 Then W := OpenDoc(LastSrc, False);
  If W < 0 Then Exit;
  Activate(W);
  GotoLine(W, MsgLine[I]);
  StatusMsg := MsgText[I];
End;

{ ==================================================================== }
{ Compilation et execution                                              }
{ ==================================================================== }

{ fenetre d'edition la plus haute (meme si Messages est devant) }
Function SrcWin : LongInt;
Var K : LongInt;
Begin
  SrcWin := -1;
  For K := NZ - 1 DownTo 0 Do
    If Wins[ZOrd[K]].Kind = WK_EDIT Then
    Begin
      SrcWin := ZOrd[K];
      Exit;
    End;
End;

Function SaveDoc(W : LongInt) : Boolean;
Begin
  SaveDoc := False;
  If Wins[W].FileName = '' Then
  Begin
    OpenInput(DM_SAVEAS, 'Enregistrer sous', 'Nom du fichier :', WorkDir + 'NONAME' + IStr(Wins[W].Untitled) + '.PAS');
    Exit;
  End;
  If SaveFile(W, Wins[W].FileName) Then
  Begin
    SaveDoc := True;
    StatusMsg := Acc('Enregistr^e : ') + Wins[W].FileName;
  End;
  Redraw;
End;

{ valeur entiere qui suit Key dans S (ex. 'code=') }
Function NumAfter(S, Key : String) : LongInt;
Var P, V, E : LongInt; T : String;
Begin
  NumAfter := -1;
  P := Pos(Key, S);
  If P = 0 Then Exit;
  T := '';
  P := P + Length(Key);
  While (P <= Length(S)) And (S[P] = ' ') Do Inc(P);
  While (P <= Length(S)) And (S[P] >= '0') And (S[P] <= '9') Do
  Begin
    T := T + S[P];
    Inc(P);
  End;
  If T = '' Then Exit;
  Val(T, V, E);
  If E = 0 Then NumAfter := V;
End;

{ message de WPC -> texte de la fenetre Messages et ligne }
Procedure AddCompilerLine(S : String);
Var L, P : LongInt; Err : Boolean; T : String;
Begin
  { erreur de l'analyseur : "WPC: fichier(ligne,colonne) Erreur: message" }
  P := Pos(') Erreur:', S);
  If (Pos('WPC: ', S) = 1) And (P > 0) Then
  Begin
    T := Copy(S, 1, P);
    While (Length(T) > 0) And (T[Length(T)] <> '(') Do Delete(T, Length(T), 1);
    L := NumAfter(S, T);
    T := Trim(Copy(S, P + 9, 255));
    Inc(LastErrs);
    T := 'Erreur : ' + T;
    If L >= 1 Then T := NameOf(LastSrc) + '(' + IStr(L) + ') ' + T Else L := -2;
    MsgAdd(T, L);
    Exit;
  End;
  Err := Pos('WPC: FATAL:', S) = 1;
  If Err Or (Pos('WPC: warning:', S) = 1) Or (Pos('WPC: avertissement', S) = 1) Then
  Begin
    P := Pos(':', S);
    T := Trim(Copy(S, P + 1, 255));
    P := Pos(':', T);
    T := Trim(Copy(T, P + 1, 255));
    L := -1;
    If Pos('ligne ', T) = 1 Then
    Begin
      L := NumAfter(T, 'ligne ');
      P := Pos(':', T);
      If P > 0 Then T := Trim(Copy(T, P + 1, 255));
    End;
    If Err Then
    Begin
      Inc(LastErrs);
      T := 'Erreur : ' + T;
      If L < 1 Then L := -2;
    End
    Else
    Begin
      Inc(LastWarns);
      T := 'Avertissement : ' + T;
    End;
    If L >= 1 Then T := NameOf(LastSrc) + '(' + IStr(L) + ') ' + T;
    MsgAdd(T, L);
  End
  Else If Pos('PE genere', S) > 0 Then
  Begin
    LastSize := NumAfter(S, '(');
    LastCode := NumAfter(S, 'code=');
    LastData := NumAfter(S, 'data=');
    LastImports := NumAfter(S, 'imports=');
  End
  Else If Pos('Lignes analysees', S) > 0 Then LastLines := NumAfter(S, ':')
  Else If Pos('WPC: attention', S) = 1 Then
  Begin
    Inc(LastWarns);
    MsgAdd('Avertissement : ' + Trim(Copy(S, 16, 255)), -1);
  End
  Else If Pos('WPC:', S) = 1 Then
  Begin
    Inc(LastErrs);
    MsgAdd(Trim(S), -2);
  End
  Else If Pos('Runtime error', S) > 0 Then
  Begin
    Inc(LastErrs);
    MsgAdd(Acc('Erreur interne du compilateur : ') + Trim(S), -2);
  End;
End;

{ prepare ArgBuf : ligne de commande "programme" arguments }
Procedure SetArgs(Prog, Args : String);
Begin
  If Args = '' Then PutZ(LongInt(@ArgBuf), '"' + Prog + '"')
  Else PutZ(LongInt(@ArgBuf), '"' + Prog + '" ' + Args);
End;

Procedure SetWait(On : Boolean);
Begin
  If On Then Dummy := SetCursor(LoadCursorA(0, SPTR_WAIT))
  Else Dummy := SetCursor(LoadCursorA(0, SPTR_ARROW));
End;

Var PendCmd : LongInt;                 { commande a reprendre apres Enregistrer sous }

{ compilation en cours (WPC.EXE lance en asynchrone : l'EDI et le
  bureau restent vivants ; un minuteur attend la fin du compilateur) }
Var
  CompBusy, PendRun, CompCancel : Boolean;
  CompPid, CompT0 : LongInt;           { processus du compilateur (handle) }
  CompEH : LongInt;                    { fichier de sa sortie standard }
  CompErrN : String;
  StartI : Array[0..16] Of LongInt;    { STARTUPINFO }
  ProcI : Array[0..3] Of LongInt;      { PROCESS_INFORMATION }

{ creer le fichier de la sortie du compilateur (-1 : impossible) }
Function CreateOut(N : String) : LongInt;
Begin
  CreateOut := CreateFileA(Z(N), GENERIC_WRITE, FILE_SHARE_READ, 0, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, 0);
End;

{ lancer un programme (ligne de commande dans ArgBuf) ; Out : sortie
  standard (0 : la sienne) ; rend 0 ou le code d'erreur }
Function Launch(Prog : String; Out, Flags : LongInt) : LongInt;
Var K : LongInt;
Begin
  For K := 0 To 16 Do StartI[K] := 0;
  StartI[0] := 68;
  If Out <> 0 Then
  Begin
    StartI[11] := STARTF_USESTDHANDLES;
    StartI[14] := 0; StartI[15] := Out; StartI[16] := Out;
  End;
  For K := 0 To 3 Do ProcI[K] := 0;
  If CreateProcessA(Z(Prog), LongInt(@ArgBuf), 0, 0, 1, Flags, 0, 0, LongInt(@StartI),
                    LongInt(@ProcI)) = 0 Then
  Begin
    K := GetLastError;
    If K = 0 Then K := 2;
    Launch := K;
    Exit;
  End;
  If ProcI[1] <> 0 Then Dummy := CloseHandle(ProcI[1]);
  Launch := 0;
End;

Procedure CompileDone(R, Code : LongInt); Forward;
Procedure CompBoxOpen; Forward;
Procedure CompBoxClose; Forward;

{ le fichier N peut-il etre (re)cree ? absent, ou efface avec succes
  (un fichier du CD-ROM ne peut pas etre remplace) }
Function CanReplace(N : String) : Boolean;
Var F : File;
Begin
  CanReplace := True;
  If Not FileExists(N) Then Exit;
  Assign(F, N);
  {$I-} Erase(F); {$I+}
  CanReplace := IOResult = 0;
End;

{ le source ouvre-t-il des fenetres ? (sinon, meme compile pour
  Windows, ses WriteLn n'auraient nulle part ou s'afficher) }
Function UsesPm(W : LongInt) : Boolean;
Var I : LongInt; S : String;
Begin
  UsesPm := False;
  For I := 0 To Wins[W].NLines - 1 Do
  Begin
    S := UpStr(GetLine(W, I));
    If (Pos('CREATEWINDOW', S) > 0) Or (Pos('MESSAGEBOX', S) > 0) Or
       (Pos('REGISTERCLASS', S) > 0) Or (Pos('DIALOGBOX', S) > 0) Or
       (Pos('APPTYPE GUI', S) > 0) Or (Pos('INITGRAPH', S) > 0) Then
    Begin
      UsesPm := True;
      Exit;
    End;
  End;
End;

Function Compile : Boolean;
Var W, R, K : LongInt; Src, Exe, ErrN, Args : String;
Begin
  Compile := False;
  If CompBusy Then
  Begin
    StatusMsg := Acc('Compilation d^ej^a en cours (Annuler dans la bo^ite Compilation pour l''arr^eter)...');
    InvRect(0, WorkH, CW, CH);
    If CompFr <> 0 Then Dummy := SetActiveWindow(CompFr);
    Exit;
  End;
  W := SrcWin;
  If W < 0 Then
  Begin
    ShowMsg(Acc('Aucun source ^a compiler : ouvrez un fichier Pascal.'), 'Compiler', MB_OK Or MB_INFORMATION);
    Exit;
  End;
  If Wins[W].FileName = '' Then
  Begin
    PendCmd := CM_COMPILE;
    Activate(W);
    If SaveDoc(W) Then ;
    Exit;
  End;
  If Wins[W].Modified Then
    If Not SaveFile(W, Wins[W].FileName) Then Exit;
  If Not FileExists(CompilerPath) Then
  Begin
    ShowMsg(Acc('Le compilateur WPC.EXE est introuvable (') + CompilerPath + ').', 'Compiler', MB_OK Or MB_ERROR);
    Exit;
  End;
  Src := Wins[W].FileName;
  Exe := ChangeExt(Src, '.EXE');
  ErrN := DirOf(Exe) + 'PASDEV.ERR';
  { ancien .EXE qui ne peut pas etre remplace (CD-ROM, lecture seule, en
    cours d'execution) : sorties dans le repertoire de travail }
  If Not CanReplace(Exe) Then
  Begin
    If CanReplace(WorkDir + NameOf(Exe)) And (WorkDir <> DirOf(Exe)) Then
    Begin
      Exe := WorkDir + NameOf(Exe);
      ErrN := WorkDir + 'PASDEV.ERR';
    End
    Else
    Begin
      Exe := 'D:\' + NameOf(Exe);
      ErrN := 'D:\PASDEV.ERR';
    End;
  End;
  { repertoire du source en lecture seule (CD-ROM) : sorties dans le repertoire de travail }
  CompEH := CreateOut(ErrN);
  If CompEH = -1 Then
  Begin
    Exe := WorkDir + NameOf(Exe);
    ErrN := WorkDir + 'PASDEV.ERR';
    CompEH := CreateOut(ErrN);
    If CompEH = -1 Then
    Begin
      ShowMsg(Acc('Impossible de cr^eer ') + ErrN + '.', 'Compiler', MB_OK Or MB_ERROR);
      Exit;
    End;
  End;
  LastSrc := Src; LastExe := Exe; LastTarget := Target;
  LastLines := 0; LastCode := 0; LastData := 0; LastImports := 0; LastSize := 0;
  LastErrs := 0; LastWarns := 0; LastOk := False; LastDone := True;
  StatusMsg := 'Compilation de ' + NameOf(Src) + ' (' + TargetName(Target) + ')...';
  Redraw;
  Dummy := UpdateWindow(Client);
  SetWait(True);
  { destination Windows : programme sans fenetre (WriteLn seulement)
    compile pour la console, ou sa sortie s'affiche }
  If (Target = 0) And UsesPm(W) Then Args := '-v -w -CW32 -WG ' Else Args := '-v -w -CW32 -WC ';
  Args := Args + Src + ' ' + Exe;
  SetArgs(CompilerPath, Args);
  CompT0 := GetTickCount;
  CompErrN := ErrN;
  { progression : WPC -PRG ecrit l'etape et la ligne dans la memoire
    partagee nommee WPC.PRG ; boite de compilation }
  If PrgMem <> 0 Then
  Begin
    For K := 0 To 15 Do WrL(PrgMem + K * 4, 0);
    WrL(PrgMem, $31475250);
    SetArgs(CompilerPath, '-PRG ' + Args);
  End;
  CompLastLine := -1; CompLastPh := -1;
  CompBoxOpen;
  { sortie standard du compilateur -> fichier (STARTF_USESTDHANDLES) ;
    la fin est attendue par un minuteur }
  R := Launch(CompilerPath, CompEH, 0);
  If R <> 0 Then
  Begin
    CompileDone(R, 0);
    Exit;
  End;
  CompPid := ProcI[0];
  CompBusy := True;
  Dummy := SetTimer(Client, 7, 100, 0);
End;

{ fin du compilateur (minuteur 7) : rend vrai quand il est termine }
Function CompilePoll : Boolean;
Var Code : LongInt;
Begin
  CompilePoll := False;
  If Not CompBusy Then Exit;
  If WaitForSingleObject(CompPid, 0) = WAIT_TIMEOUT Then
  Begin
    { compilateur en cours : boite de compilation mise a jour }
    If (PrgMem <> 0) And (CompCl <> 0) Then
      If (RdL(PrgMem + 8) <> CompLastLine) Or (RdL(PrgMem + 4) <> CompLastPh) Then
      Begin
        CompLastLine := RdL(PrgMem + 8); CompLastPh := RdL(PrgMem + 4);
        Dummy := InvalidateRect(CompCl, 0, 0);
      End;
    Exit;
  End;
  CompBusy := False;
  Dummy := KillTimer(Client, 7);
  Code := 0;
  If GetExitCodeProcess(CompPid, LongInt(@Code)) = 0 Then Code := 0;
  Dummy := CloseHandle(CompPid);
  CompileDone(0, Code);
  CompilePoll := True;
End;

Procedure CompileDone(R, Code : LongInt);
Var K : LongInt; S, ErrN, Exe, Src : String; EF : Text;
Begin
  LastTime := GetTickCount - CompT0;
  CompBoxClose;
  If CompEH <> -1 Then Dummy := CloseHandle(CompEH);
  CompEH := -1;
  SetWait(False);
  ErrN := CompErrN; Exe := LastExe; Src := LastSrc;
  MsgClear;
  MsgAdd('Compilation de ' + Src + ' -> ' + Exe + ' (' + TargetName(LastTarget) + ')', -1);
  If CompCancel Then
  Begin
    MsgAdd(Acc('Compilation interrompue : le compilateur a ^et^e arr^et^e (bouton Annuler).'), -2);
    Inc(LastErrs);
    CompCancel := False;
  End;
  If R <> 0 Then
  Begin
    MsgAdd(Acc('Impossible de lancer le compilateur (erreur ') + IStr(R) + ').', -2);
    Inc(LastErrs);
  End
  Else
  Begin
    Assign(EF, ErrN);
    {$I-} Reset(EF); {$I+}
    If IOResult = 0 Then
    Begin
      While Not EOF(EF) Do
      Begin
        ReadLn(EF, S);
        AddCompilerLine(S);
      End;
      Close(EF);
    End;
    If (Code <> 0) And (LastErrs = 0) Then
    Begin
      MsgAdd(Acc('Le compilateur s''est termin^e avec le code ') + IStr(Code) + '.', -2);
      Inc(LastErrs);
    End;
  End;
  { le fichier .ERR n'est plus utile }
  Assign(EF, ErrN);
  {$I-} Erase(EF); {$I+}
  K := IOResult;
  LastOk := (LastErrs = 0) And FileExists(Exe);
  If LastOk And (LastSize <= 0) Then LastSize := FileSizeOf(Exe);
  If LastOk Then
  Begin
    MsgAdd(Acc('Compilation r^eussie : ') + NStr(LastLines) + Acc(' lignes, ') + NameOf(Exe) + ' (' +
           NStr(LastSize) + ' octets), ' + IStr(LastWarns) + ' avertissement(s).', -1);
    StatusMsg := Acc('Compilation r^eussie : ') + NameOf(Exe) + ' (' + NStr(LastSize) + ' octets)';
  End
  Else
  Begin
    MsgAdd(Acc('Compilation ^echou^ee : ') + IStr(LastErrs) + ' erreur(s).', -2);
    StatusMsg := Acc('Compilation ^echou^ee : voir la fen^etre Messages');
    PendRun := False;
  End;
  If (Not LastOk) Or (LastWarns > 0) Then
  Begin
    ShowMessages;
    { premiere erreur avec une ligne : y aller }
    For K := 0 To MsgCount - 1 Do
      If (MsgLine[K] >= 1) And (Pos('Erreur', MsgText[K]) > 0) Then
      Begin
        MsgSel := K;
        MsgGo(K);
        Break;
      End;
  End;
  Redraw;
End;

{ bouton Annuler (ou Echap, ou fermeture) de la boite de compilation :
  arreter le compilateur (WPC.EXE qui ne finirait pas) et rendre la
  main ; la sortie deja produite est affichee dans la fenetre Messages }
Procedure CompileAbort;
Begin
  If Not CompBusy Then Exit;
  Dummy := KillTimer(Client, 7);
  CompBusy := False;
  CompCancel := True;
  { le compilateur seul ; puis attendre sa fin }
  Dummy := TerminateProcess(CompPid, 1);
  Dummy := WaitForSingleObject(CompPid, 1000);
  Dummy := CloseHandle(CompPid);
  CompileDone(0, 0);
End;

Procedure RunProgram;
Var W, Rc : LongInt; Exe, Cmd, Note : String;
Begin
  W := SrcWin;
  If W < 0 Then Exit;
  { compiler d'abord si le source a change depuis la derniere compilation }
  If (Not LastOk) Or (LastSrc <> Wins[W].FileName) Or Wins[W].Modified Or (LastTarget <> Target) Or
     Not FileExists(LastExe) Then
  Begin
    { compilation d'abord (asynchrone) : l'execution suit a sa fin }
    PendRun := True;
    If Not Compile Then Exit;
  End;
  If CompBusy Then Exit;
  Exe := LastExe;
  { repeindre l'EDI maintenant : sinon le dessin en attente (compilation)
    passerait par-dessus la fenetre du programme }
  Dummy := UpdateWindow(Client);
  Note := '';
  If (Target = 0) And Not UsesPm(W) Then
    Note := Acc(' - sans fen^etre : ex^ecut^e en console');
  If (Target = 0) And (Note = '') Then
  Begin
    { Windows : le programme ouvre ses propres fenetres }
    SetArgs(Exe, RunParams);
    Rc := Launch(Exe, 0, 0);
    If Rc <> 0 Then ShowMsg(Acc('Impossible de lancer ') + Exe + ' (erreur ' + IStr(Rc) + ').', Acc('Ex^ecuter'), MB_OK Or MB_ERROR)
    Else
    Begin
      Dummy := CloseHandle(ProcI[0]);
      StatusMsg := Acc('Ex^ecution de ') + NameOf(Exe);
    End;
  End
  Else
  Begin
    { console : l'interpreteur de commandes lance le programme dans la
      fenetre Invite MS-DOS, puis PAUSE (la fenetre reste ouverte, avec
      la sortie du programme, jusqu'a une touche) }
    Cmd := GetEnv('COMSPEC');
    If (Cmd = '') Or Not FileExists(Cmd) Then Cmd := ExeDir + 'COMMAND.EXE';
    If Not FileExists(Cmd) Then Cmd := 'C:\WINDOWS\COMMAND.EXE';
    If Not FileExists(Cmd) Then Cmd := 'C:\COMMAND.EXE';
    If RunParams = '' Then SetArgs(Cmd, '/C ' + Exe + ' /C PAUSE')
    Else SetArgs(Cmd, '/C "' + Exe + ' ' + RunParams + '" /C PAUSE');
    Rc := Launch(Cmd, 0, CREATE_NEW_CONSOLE);
    If Rc <> 0 Then
    Begin
      ShowMsg(Acc('Impossible de lancer ') + Exe + ' (erreur ' + IStr(Rc) + ').', Acc('Ex^ecuter'), MB_OK Or MB_ERROR);
      Exit;
    End;
    Dummy := CloseHandle(ProcI[0]);
    StatusMsg := Acc('Ex^ecution de ') + NameOf(Exe) + ' (console Win32)' + Note;
  End;
  { la barre d'etat seulement : la fenetre du programme est devant l'EDI }
  InvRect(0, WorkH, CW, CH);
End;

{ ==================================================================== }
{ Image de la boite A propos : Blaise Pascal ecrivant Win95            }
{ (144 x 176 pels, 16 couleurs du VGA, une ligne hexadecimale par rangee) }
{ ==================================================================== }
Const
  PIC_W = 144; PIC_H = 176;
  { 0 noir, 1 bleu, 2 vert, 3 cyan, 4 rouge, 5 magenta, 6 brun, 7 gris clair, 8 gris fonce,
    9 bleu clair, A vert clair, B cyan clair, C rouge clair, D rose, E jaune, F blanc }
  PicRows : Array[0..PIC_H - 1] Of String[PIC_W] = (
    '010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222866685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '0C6C6889882A2A284E465D6D110101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '1CECE8E7E8EAEAE8EEE8E7E7601010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222846685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222866685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222866685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222866685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '044441111122222866685555010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '144440111022222066605555501010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '664646686666666666666868666666010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '666666666666666666666666666666801010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '666666666666666666666666666666010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '808080808080808080808080808080101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101010101010101010101010101080806060608010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010101010101080606060606060606080101010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101010101010101010101080606060606060606060606010101010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010101010606060606060606060606060608010101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101010101010101010106060606060606060606060606060601010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010108060606060606060606060606060606060101010101010101010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101010101010101080606060606060606060606060606060606010101010101010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010101010101010806060606060606060606060606060606060601010101010101010101010101010101010101010101010101010101010101010101010101010',
    '0101010101010101010101010101080606060606060606060606060606060606060601010101010101010101010101010101010101010101010101010107EE010101010101010101',
    '101010101010101010101010101080606060606060606060606060606060606060606010101010101010101010101010101010101010101010101010107EEEE01010101010101010',
    '01010101010101010101010101010606060606060606060606060606060606060606060101010101010101010101010101010101010101010101010108EEEEE80101010101010101',
    '10101010101010101010101010106060606060606060606060606060606060606060606010101010101010101010101010101010101010101010101013EEEEE81010101010101010',
    '0101010101010101010101010106060606060606060606060606060606060606060606080101010101010101010101010101010101010101010101010EEEEEEE0101010101010101',
    '1010101010101010101010101060606060606066767676767676767676606060606060601010101010101010101010101010101010101010101010101EEEFEEE6010101010101010',
    '010101010101010101010101080606060606066E6F6F6F6F6F6F6F6F6F660606060606060101010101010101010101010101010101010101010101010EEFFFEE8101010101010101',
    '1010101010101010101010101060606060606076F6F6F6F6F6F6F6F6F6C06060606060606010101010101010101010101010101010101010101010101EEFFFEE8010101010101010',
    '010101010101010101010101060606060606067F6F6F6F6F6F6F6F6F6F680606060606060801010101010101010101010101010101010101010101010EEFFFEE8101010101010101',
    '10101010101010101010101080606060606060F6F6F6F6F6F6F6F6F6F6F760606060606060101010101010101010101010101010101010101010101018EFFFFE1010101010101010',
    '010101010101010101010101060666666606086F6F6F6F6F6F6F6F6C676F66060666666606010101010101010101010101010101010101010101010107EFFFEE0101010101010101',
    '10101010101010101010101066666060666066F6F6F6F6F6F6F6F6C6767770666660606660101010101010101010101010101010101010101010101018EEFFE31010101010101010',
    '0101010101010101010101016606060606060C6F6F6F6F6F6F6F6F676767766606060606060101010101010101010101010101010101010101010101018EFFE10101010101010101',
    '10101010101010101010101660606060606066F6F6F6F6F6F6F6F7767676766060606060606010101010101010101010101010101010101010101010108788801010101010101010',
    '0101010101010101010101680606060606676E6F6E7F6C6F6F6C67676767670606060606060601010101010101010101010101010101010101010101017F87F80101010101010101',
    '10101010101010101010108060606060607676F676868676F6F68686867676606060606060148010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101060106060666666F6F6F6C676F6F6F6F7C68676767066666660606016101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010108610606666606076F6F6E6E7F6F6F6F6C776767676646060666060808410101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010806660606067F6F6F6E787E6F6F6E7877676767660606060606010101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '1010101010101010101010106660606060F6F6F6F7F08CF6F6F7F086767676806060606060601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010866060606066F6F6F6F787F6F666F7867676767660606060606010101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '1010101010101010101010106060606060F6F6F6F6F7F6F6F6F67676767676806060606066601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010606060606666F6F6F6F6F6F6F6C6F6767676767666666060606680101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '1010101010101010101010866060666660C6F6F6F6F6F6F6F4767676767676806066606060601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010606066606066F6F6F6F6F6F6F676F6767676767660606060606080101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010101010606660606076F6F6F6F6F6F6F7667676767676806060606060601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010606660606066E6F6F6F6F6F6F6F6C6767676767060606060606080101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010101080606060606086F6F6F6F6F6F676C67676767676606060606660601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101010606060606066F6F6F6F6F6F6F676E6767676767666606060666060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010101080666060666666F6F6F6F6F7F7C7C7C676767676606660606066601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '0101010101010101010101060606066606077F6F6F6F686808086867676768060606060606060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010101060606066606066F6F6F6F68676C676C886767670606060606060601010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '0101010101010101010101060606660606066F6F6F6F6E7E7E7F7C67676766060606060606060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '10101010101010101010106060606060606086F6F6F6F67676767776767680606060666060608010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '010101010101010101010106060606060606676F6F6F6F4646464C77676766660606066606060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '10101010101010101010106060666060666666F6F6F6F6F6E7F6F6F6768060666060606660606010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '010101010101010101010806060606066606066E6F6F6F6F6C6F6F6F670606060606060606060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '1010101010101010101010606060606660606066E6F6F6F6C076F6F6F06060606060606060606010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '01010101010101010101060606060666060606066E6F6F6F677F6F6F660606060606060606060101010101010101010101010101010101010101010101FFFFF80101010101010101',
    '101010101010101010101060606060606060606066F6F6F6F6F6F6F6606060606066606060606010101010101010101010101010101010101010101010FFFFF11010101010101010',
    '0101010101010101010106060606060606060666666F6F6F6F6F6C676666660606066606060601010101010101010101010101010101010101010166666666666668010101010101',
    '1010101010101010101010606060666060666660607676F6F6F776768060666060606660606060101010101010101010101010101010101010101066666666666660101010101010',
    '010101010101010101010606060606060666060101676767676767670101060606060606060608010101010101010101010101010101010101010166666666666668010101010101',
    '101010101010101010108060606060606660601010767676767676768010806060606060606060101010101010101010101010101010101010101080808080808080101010101010',
    '010101010101010101010606060606066606080101676767676767670101060606060606060608010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010108060606060606060601010767676767676768010806066606060606060101010101010101010101010101010101010101010101010101010101010101010',
    '0101010101010101010106060606060606087FFFFFFFFFFFFFFFFFFFFFFFFF7606660606060606010101010101010101010101010101010101010101010101010101010101010101',
    '101010101010101010106060606060666087FFFFFFFFFFFFFFFFFFFFFFFFFFF660666060606060101010101010101010101010101010101010101010101010101010101010101010',
    '01010101010101010101060606060606067FFFFFFFFFFFFFFFFFFFFFFFFFFFFF06060606060606010101010101010101010101010101010101010101010101010101010101010101',
    '1010101010101010101060606060606068FFFFFFFFFFFFFFFFFFFFFFFFFFFFFF70606060606060101010101010101010101010101010101010101010101010101010101010101010',
    '0101010101010101010106060606060607FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF6060606060606010101010101010101010101010101010101010101010101010101010101010101',
    '1010101010101010101060606060606087FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7606060606060801010101010101010101010101010101010101010101010101010101010101010',
    '010101010101010101080606060606087FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF660606060606010101010101010101010101010101010101010101010101010101010101010101',
    '10101010101010101010606060606067FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF06060606060801010101010101010101010101010101010101010101010101010101010101010',
    '0101010101010101010806060606067FFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFFFFFF80606060606010101010101010101010101010101010101010101010101010101010101010101',
    '1010101010101010101060606060667FFFFFFFFFFFFFFFFF87FFFFFFFFFFFFFFFFFF8000006060601010101010101010101010101010101010101010101010101010101010101010',
    '0101010101010101010606060606087FFFFFFFFFFFFFFFF8088FFFFFFFFFFFFFFFFF7600000606010101010101010101010101010101010101010101010101010109110101010101',
    '101010101010101010006060606087FFFFFFFFFFFFFFFFF08707FFFFFFFFFFFFFFFFF660000000601010101010101010101010101010101010101010101010101087101010101010',
    '01010101010101010006060606067FFFFFFFFFFFFFFFFF0008007FFFFFFFFFFFFFFFFF00000000010101010101010101010101010101010101010101010101010877010101010101',
    '1010101010101000000060606067FFFFFFFFFFFFFFFFF70087008FFFFFFFFFFFFFFFFF700000000000101010101010101010101010101010101010101010101017F8101010101010',
    '0101010101010000000606060667FFFFFFFFFFFFFFFF7000080008FFFFFFFFFFFFFFFFF8000000000001010101010101010101010101010101010101010101016FF1010101010101',
    '101010101010000000006060607FFFFFFFFFFFFFFFFF8000870000FFFFFFFFFFFFFFFFF7000000000000001010101010101010101010101010101010101010117F70101010101010',
    '0101010101000000000606060668777FFFFFFFFFFFF800000800000FFFFFFFFFFF7F7868000000000000000101010101010101010101010101010101010101087F81010101010101',
    '1010101010000000006060606060606060888777FF70000000000007FFF787888060606060000000000000001010101010101010101010101010101010101087FF80101010101010',
    '0101010100000000000606060606060600000000000000000000000000000000060606060000000000000000010101010101010101010101010101010101017FFF01010101010101',
    '10101010100000000060606060606060600000000000000000000000000000000060606060000000000000001010101010101010101010101010101010101877F781101010101010',
    '0101010100000000000406060606060600000000000008080808000000000000060606060600000000000000010101010101010101010101010101010101077FF901010101010101',
    '101010100000000000000000606060606000000000008080808000000000000000606060600000000000000000101010101010101010101010101010101097FFF010101010101010',
    '01010101000000000000000000060606000000000000080808080000000000000006060600000000000000000001010101010101010101010101010101087FFF7101010101010101',
    '1010101000000000000000000000006000000000000080808080000000000000006000000000000000000000001010101010101010101010101010101017FFFF9010101010101010',
    '0101010000000000000000000000000000000000000008080808000000000000000000000000000000000000000101010101010101010101010101010187FFFF0101010101010101',
    '101010100000000000000000000000000000000000008080808000000000000000000000000000000000000000001010101010101010101010101010107FFFF81010101010101010',
    '010101000000000000000000000000000000000000000808080800000000000000000000000000000000000000000101010101010101010101010101087F7F710101010101010101',
    '10101000000000000000000000000000000000000000808080808000000000000000000000000000000000000000001010101010101010101010101087F7FF801010101010101010',
    '0101010000000000000000000000000000000000000008080808000000000000000000000000000000000000000001010101010101010101010101017FFFF9010101010101010101',
    '1010100000000000000000000000000000000000000080808080800000000000000000000000000000000000000000101010101010101010101010187FFFF0101010101010101010',
    '0101000000000000000000000000000000000000000008080808000000000000000000000000000000000000000000010101010101010101010101077FFF11010101010101010101',
    '101010000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000101010101010101010101087FFF710101010101010101010',
    '01010000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000101010101010101010101087FFFF801010101010101010101',
    '101000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000101010101010101010101777F77110101010101010101010',
    '01000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000001010101010101010101877FF70101010101010101010101',
    '1010000000000000000000000000000000000000000080808080800000000000000000000000000000000000000000000010101010101010101177FFF11010101010101010101010',
    '010000000000000000000000000000000000000000080808080800000000000000000000000000000000000000000000000101010101010101087FFF710101010101010101010101',
    '10000000000000000000000000000000000000000000808080808000000000000000000000000000000000000000000000101010101010101087FFF7101181818180101010101010',
    '01000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000010101010101010177FFF8081818000118110101010101',
    '1000000000000000000000000000000000000000000080808080800000000000000000000000000000000000000000000000101010101010187FFF70818100000081811010101010',
    '0000000000000000000000000000000000000000000808080808000000000000000000000000000000000000000000000000010101010101177F7778181800000118180101010101',
    '100000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000000101010101077F7F110118181818181801010101010',
    '00000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000000101010101087FFF7101010818181811000101010101',
    '00000000000000000000000000000000000000000000808080808000000000000000000000000000000000000000000000000010101010177FF71010100010101000001010101010',
    '00000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000000007710101177FF80101000000000000000101010101',
    '000000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000008FFF1101087FF901010100000000000001010101010',
    '00000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000000087FFFFF01017FF7010101000000000000000101010101',
    '000000000000000000000000000000000000000000008080808080000000000000000000000000000000000000000000008FFFFFFF801777F7811010100000000000001010101010',
    '0000000000000000000000000000000000000000000808080808080000000000000000000000000000000000000000008FFFFF7E6F78877F11010101000000000000000101010101',
    '000000000000000000000000000000000000000000008080808080000000000000000000000000000000000000100087FFFFF6F6F6F777F710101010100000000000001010101010',
    '00000000000000000000000000000000000000000008080808080800000000000000000000000000000000000000007FFFFF6F6F6F677FF101010101000000000000000101010101',
    '00000000000000000000000000000000000000000000808080808000000000000000000000000000000000000010008FFFF6F6F6F6F7FFE810101010000000000000000010101010',
    '0000000000000000000000000000000000000000000808080808080000000000000000000000000000000000006E6007FFCF6F6F6F77F76C4E4E4E0001010101010101006E4E4E4E',
    '00000000000000000000000000000000000000000080808080808000000000000000000000000000000000000084E600FFF6F6F6F67FF67674E4E4000000000000000000C4E4E4E4',
    '0000000000000000000000000000000000000000000808080808080000000000000000000000000000000000006E4E607F6F6F6F677F67676E4E4E6800000000000000084E4E4E4E',
    '0000000000000000000000000000000000000000008080808080800000000000000000000000000000000000006666608FF6F6F67776767676666666600000000000606666666666',
    '0000000000000000000000000000000000000000000808080808080000000000000000000000000000000000000666666C7F6F6E8867676766666666666666460666666666666666',
    '0000000000000000000000000000000000000000008080808080800000000000000000000000000000000000000666666668E6E607F676767666666666666666E4E4666666666666',
    '000000000000000000000000000000000000000000080808080808000000000000000000000000000000000000066666666667606768666C6E4E4ECECE7E7FEFEFEF666666666666',
    '00000000000000000000000000000000000000000080808080808000000000000000000000000000000000000066666666E4E660ECE7E7FEFEFEFEFEFEFEFEFEFEFEE66666666666',
    '00000000000000000000000000000000000000000008080808080800000000000000000000060606666E4E4ECE7E7EEFEFEFEE0EEFEFEFEFEFEFEFEFEFEFEFEFEFEFC60606060606',
    '00000000000000000000000000000000000000000080808080808000000060606666E4E6ECE7E7EEFEFEFEFEFEFEFEFEFEFEF07EFEFEFEFEFEFEFEFEFEFEFEFEFEFEE66666666666',
    '000000000000000000000000000000000000000000080808080808066ECE7E7EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF88EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFE66666666666',
    '00000000000000000000000000000000000000000080808080808000EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF707FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF46666666666',
    '00000000000000000000000000000000000000000008080808080806EFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF7FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE6666666666',
    '00000000000000000000000000000000000000000080808080808086FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF76666666666',
    '0000000000000000000000000000000000000000000808080808080EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF6606060606',
    '0000000000000000000000000000000000000000008080808080806CFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE666666666',
    '0000000000000000000000000000000000000000000808080808080EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFC666666666',
    '00000000000000000000000000000000000000000080808080808067FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE666666666',
    '0000000000000000000000000000000000000000000808080808086FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFE666666666',
    '000000000000000000000000000000000000000000808080808080EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF466666666',
    '0000000000000000000000000000000000000000080808080808064FEFEFEF11EFEFEF11EFEFEF11EFEFEFEFEFEFEFEFEFEF111111EFEF1111111111EFEFEFEFEFEFEFEE46060606',
    '000000000000000000000000000000000000000000808080808080EEFEFEFE11FEFEFE11FEFEFE11FEFEFEFEFEFEFEFEFEFE111111FEFE1111111111FEFEFEFEFEFEFEF766666666',
    '0000000000000000000000000000000000000000080808080808067FEFEFEF11EFEFEF11EFEFEFEFEFEFEFEFEFEFEFEFEF11EFEFEF11EF11EFEFEFEFEFEFEFEFEFEFEFEF66666666',
    '000000000000000000000000000000000000000000808080808086FEFEFEFE11FEFEFE11FEFEFEFEFEFEFEFEFEFEFEFEFE11FEFEFE11FE11FEFEFEFEFEFEFEFEFEFEFEFEE6666666',
    '000000000000000000000000000000000000000008080808080806EFEFEFEF11EFEFEF11EFEF1111EFEFEF11EF1111EFEF11EFEFEF11EF11111111EFEFEFEFEFEFEFEFEF86666666',
    '000000000000000000000000000000000000000000808080808084FEFEFEFE11FEFEFE11FEFE1111FEFEFE11FE1111FEFE11FEFEFE11FE11111111FEFEFEFEFEFEFEFEFEE6666666',
    '00000000000000000000000000000000000000000808080808080EEFEFEFEF11EF11EF11EFEFEF11EFEFEF1111EFEF11EFEF11111111EFEFEFEFEF11EFEFEFEFEFEFEFEFE6060606',
    '00000000000000000000000000000000000000000080808080806CFEFEFEFE11FE11FE11FEFEFE11FEFEFE1111FEFE11FEFE11111111FEFEFEFEFE11FEFEFEFEFEFEFEFEF4666666',
    '00000000000000000000000000000000000000000808080808086EEFEFEFEF11EF11EF11EFEFEF11EFEFEF11EFEFEF11EFEFEFEFEF11EFEFEFEFEF11EFEFEFEFEFEFEFEFEE666666',
    '00000000000000000000000000000000000000000080808080806EFEFEFEFE11FE11FE11FEFEFE11FEFEFE11FEFEFE11FEFEFEFEFE11FEFEFEFEFE11FEFEFEFEFEFEFEFEF7666666',
    '00000000000000000000000000000000000000000808080808086FEFEFEFEF1111EF1111EFEFEF11EFEFEF11EFEFEF11EFEFEFEF11EFEF11EFEFEF11EFEFEFEFEFEFEFEFEE666666',
    '0000000000000000000000000000000000000000008080808080EEFEFEFEFE1111FE1111FEFEFE11FEFEFE11FEFEFE11FEFEFEFE11FEFE11FEFEFE11FEFEFEFEFEFEFEFEFE666666',
    '0000000000000000000000000000000000000000080808080806CFEFEFEFEF11EFEFEF11EFEF111111EFEF11EFEFEF11EFEF1111EFEFEFEF111111EFEFEFEFEFEFEFEFEFEF660606',
    '0000000000000000000000000000000000000000008080808080EEFEFEFEFE11FEFEFE11FEFE111111FEFE11FEFEFE11FEFE1111FEFEFEFE111111FEFEFEFEFEFEFEFEFEFEE66666',
    '00000000000000000000000000000000000000000808080808067FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF766666',
    '0000000000000000000000000000000000000000008080808086FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEF66666',
    '000000000000000000000000000000000000000008080808080EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE6666',
    '0000000000000000000000000000000000000000008080808064FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE7EC6666',
    '000000000000000000000000000000000000000008080808080EEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE7E7ECE6E4E666666666606',
    '0000000000000000000000000000000000000000008080808067FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE7E7ECE6E4E666666666666666666666666666',
    '000000000000000000000000000000000000000008080808086FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEE7E7ECE6E4E666666666666666666666666666666666666666666',
    '000000000000000000000000000000000000000080808080806EFEFEFEFEFEFEFEFEFEFEFEFEE7E7ECECE4E666606060666666666666666666666666666666666666666666666666',
    '000000000000000000000000000000000000000008080808084FEFEFEFEFEE7E7ECECE4E666606060000000000000006666666666666666666666666666666666666666666666666',
    '000000000000000000000000000000000000000080808080806CECE4E666606060000000000000000000000000000000606060606060646060606060606060666666666666666666',
    '000000000000000000000000000000000000000008080808080606080000000000000000000000000000000000000000666666666666666666666666666666060606060606060606',
    '000000000000000000000000000000000000000080808080808080800000000000000000000000000000000000000000666666666666666666666666666666666666666666666666',
    '000000000000000000000000000000000000000008080808080808080000000000000000000000000000000000000000666666666666666666666666666666666666666666666666',
    '000000000000000000000000000000000000000080808080808080800000000000000000000000000000000000000000666666666666666666666666666666666666666666666666'
  );

Function HexVal(C : Char) : LongInt;
Begin
  If (C >= '0') And (C <= '9') Then HexVal := Ord(C) - 48
  Else HexVal := Ord(UpCase(C)) - 55;
End;

{ bitmap 4 bits (BITMAPINFO2 de 16 octets + 16 couleurs RVB2), rangees de bas en haut }
Procedure BuildPic;
Const Pal : Array[0..15] Of LongInt = ($000000, $0000AA, $00AA00, $00AAAA, $AA0000, $AA00AA, $AA5500, $AAAAAA,
                                       $555555, $5555FF, $55FF55, $55FFFF, $FF5555, $FF55FF, $FFFF55, $FFFFFF);
Var Y, X, A, B : LongInt; S : String;
Begin
  If PicReady Then Exit;
  { BITMAPINFOHEADER : 4 bits par pixel, rangees de bas en haut }
  For X := 0 To 39 Do PicBmi[X] := 0;
  WrL(LongInt(@PicBmi), 40);
  WrL(LongInt(@PicBmi) + 4, PIC_W);
  WrL(LongInt(@PicBmi) + 8, PIC_H);
  WrW(LongInt(@PicBmi) + 12, 1);
  WrW(LongInt(@PicBmi) + 14, 4);
  WrL(LongInt(@PicBmi) + 32, 16);
  For X := 0 To 15 Do
  Begin
    A := LongInt(@PicBmi) + 40 + X * 4;
    WrB(A, Pal[X] And 255);              { bleu }
    WrB(A + 1, (Pal[X] Shr 8) And 255);  { vert }
    WrB(A + 2, (Pal[X] Shr 16) And 255); { rouge }
    WrB(A + 3, 0);
  End;
  For Y := 0 To PIC_H - 1 Do
  Begin
    S := PicRows[Y];
    A := (PIC_H - 1 - Y) * (PIC_W Div 2);
    For X := 0 To PIC_W Div 2 - 1 Do
    Begin
      B := HexVal(S[X * 2 + 1]) * 16 + HexVal(S[X * 2 + 2]);
      PicBits[A + X] := B;
    End;
  End;
  PicReady := True;
End;

{ dessiner l'image, coin haut gauche (X, Y) }
Procedure DrawPic(Hps, X, Y, Hh : LongInt);
Begin
  BuildPic;
  Dummy := SetDIBitsToDevice(Hps, X, Y, PIC_W, PIC_H, 0, 0, 0, PIC_H, LongInt(@PicBits),
                             LongInt(@PicBmi), 0);
End;

{ ==================================================================== }
{ Boites Information et A propos                                        }
{ ==================================================================== }

{ texte dans une fenetre de dialogue (coin haut gauche ; Hh : hauteur) }
Procedure DlgText(Hps, Hh, X, Y : LongInt; S : String; Fg : LongInt);
Begin
  If S = '' Then Exit;
  TextAt(Hps, X, Y, X + Length(S) * CHW, S, Fg, CLR_PALEGRAY);
End;

{ rectangle Rc (gauche, haut, droite, bas) plein }
Function FillRc(Hps, PR, C : LongInt) : LongInt;
Var Br : LongInt;
Begin
  Br := CreateSolidBrush(ClrRGB(C));
  FillRc := FillRect(Hps, PR, Br);
  Dummy := DeleteObject(Br);
End;

{ controles des dialogues : (X, Yb) depuis le coin bas gauche de la zone
  client (comme dans l'EDI d'origine) ; ordre de la touche Tab }
Var
  TabPar, TabCtl : Array[0..31] Of LongInt;
  TabN : LongInt;

Function Ctl(P : LongInt; Cls, Txt : String; St, Ex, X, Yb, W, Hh, Id : LongInt) : LongInt;
Var Rc : Array[0..3] Of LongInt; H : LongInt;
Begin
  Dummy := GetClientRect(P, LongInt(@Rc));
  PutZ(LongInt(@FailBuf), Txt);
  H := CreateWindowExA(Ex, Z(Cls), LongInt(@FailBuf), WS_CHILD Or WS_VISIBLE Or WS_TABSTOP Or St,
                       X, Rc[3] - Yb - Hh, W, Hh, P, Id, Inst, 0);
  If (H <> 0) And (TabN < 32) Then
  Begin
    TabPar[TabN] := P; TabCtl[TabN] := H;
    Inc(TabN);
  End;
  Ctl := H;
End;

{ oublier les controles d'un dialogue ferme }
Procedure TabPurge(P : LongInt);
Var K, J : LongInt;
Begin
  J := 0;
  For K := 0 To TabN - 1 Do
    If TabPar[K] <> P Then
    Begin
      TabPar[J] := TabPar[K]; TabCtl[J] := TabCtl[K];
      Inc(J);
    End;
  TabN := J;
End;

{ Tab, Maj+Tab : controle suivant ou precedent du dialogue P }
Procedure TabNext(P, Cur : LongInt; Back : Boolean);
Var K, I, N, Idx : LongInt; L : Array[0..31] Of LongInt;
Begin
  N := 0; Idx := -1;
  For K := 0 To TabN - 1 Do
    If TabPar[K] = P Then
    Begin
      If TabCtl[K] = Cur Then Idx := N;
      L[N] := TabCtl[K];
      Inc(N);
    End;
  If N = 0 Then Exit;
  If Idx < 0 Then I := 0
  Else If Back Then I := (Idx + N - 1) Mod N
  Else I := (Idx + 1) Mod N;
  Dummy := SetFocus(L[I]);
End;

Function Btn(P : LongInt; Txt : String; Def : Boolean; X, Yb, W, Hh, Id : LongInt) : LongInt;
Begin
  If Def Then Btn := Ctl(P, 'BUTTON', Txt, BS_DEFPUSHBUTTON, 0, X, Yb, W, Hh, Id)
  Else Btn := Ctl(P, 'BUTTON', Txt, BS_PUSHBUTTON, 0, X, Yb, W, Hh, Id);
End;

Procedure CloseBox(Var Fr : LongInt);
Begin
  If Fr = 0 Then Exit;
  TabPurge(Fr);
  Dummy := DestroyWindow(Fr);
  Fr := 0;
  Dummy := SetActiveWindow(Frame);
  Dummy := SetFocus(Client);
End;

Procedure InfoLine(Hps, Hh, Y : LongInt; L, V : String);
Begin
  DlgText(Hps, Hh, 16, Y, L, CLR_BLACK);
  DlgText(Hps, Hh, 220, Y, V, CLR_DARKBLUE);
End;

Function InfoProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps, Hh, Y, W : LongInt; Rc : Array[0..3] Of LongInt; S : String;
Begin
  InfoProc := 0;
  Case Msg Of
    WM_CREATE :
      Dummy := Btn(H, 'OK', True, 196, 8, 84, 26, ID_DOK);
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        Hh := Rc[3];
        Y := 12;
        W := SrcWin;
        If Not LastDone Then
        Begin
          DlgText(Hps, Hh, 16, Y, Acc('Aucun programme n''a encore ^et^e compil^e.'), CLR_BLACK);
          Y := Y + 24;
          If W >= 0 Then
          Begin
            InfoLine(Hps, Hh, Y, 'Source :', NameOf(WinTitle(W))); Y := Y + 20;
            InfoLine(Hps, Hh, Y, 'Lignes :', NStr(Wins[W].NLines)); Y := Y + 20;
          End;
          InfoLine(Hps, Hh, Y, 'Destination :', TargetName(Target)); Y := Y + 28;
          DlgText(Hps, Hh, 16, Y, Acc('Compilez (F9) pour conna^itre la taille du code'), CLR_DARKGRAY);
          DlgText(Hps, Hh, 16, Y + 18, Acc('et des donn^ees du programme.'), CLR_DARKGRAY);
        End
        Else
        Begin
          If LastOk Then S := Acc('r^eussie') Else S := Acc('^echou^ee');
          InfoLine(Hps, Hh, Y, 'Compilation :', S); Y := Y + 20;
          InfoLine(Hps, Hh, Y, 'Source :', NameOf(LastSrc)); Y := Y + 20;
          InfoLine(Hps, Hh, Y, 'Programme :', NameOf(LastExe)); Y := Y + 20;
          If LastTarget = 0 Then S := Acc('Windows (fen^etres)') Else S := 'Console Win32';
          InfoLine(Hps, Hh, Y, 'Destination :', S); Y := Y + 20;
          InfoLine(Hps, Hh, Y, Acc('Lignes compil^ees :'), NStr(LastLines)); Y := Y + 26;
          InfoLine(Hps, Hh, Y, 'Taille du code :', NStr(LastCode) + ' octets'); Y := Y + 20;
          InfoLine(Hps, Hh, Y, Acc('Taille des donn^ees :'), NStr(LastData) + ' octets'); Y := Y + 20;
          InfoLine(Hps, Hh, Y, 'Taille de la pile :', '262 144 octets'); Y := Y + 20;
          InfoLine(Hps, Hh, Y, 'Importations (API) :', NStr(LastImports)); Y := Y + 20;
          InfoLine(Hps, Hh, Y, Acc('Taille du fichier .EXE :'), NStr(LastSize) + ' octets'); Y := Y + 26;
          InfoLine(Hps, Hh, Y, Acc('Dur^ee :'), IStr(LastTime Div 1000) + ',' + IStr((LastTime Mod 1000) Div 100) + ' s');
          Y := Y + 20;
          InfoLine(Hps, Hh, Y, 'Avertissements :', IStr(LastWarns) + '   Erreurs : ' + IStr(LastErrs));
        End;
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_COMMAND : If Lo16(Mp1) = ID_DOK Then CloseBox(InfoFr);
    WM_CLOSE : CloseBox(InfoFr);
  Else
    InfoProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

Function AboutProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps, Hh, X : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  AboutProc := 0;
  Case Msg Of
    WM_CREATE :
      Dummy := Btn(H, 'OK', True, 326, 12, 90, 26, ID_DOK);
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        Hh := Rc[3];
        { cadre en creux autour de l'image }
        Rc[0] := 10; Rc[1] := 10; Rc[2] := 14 + PIC_W; Rc[3] := 14 + PIC_H;
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_DARKGRAY);
        DrawPic(Hps, 12, 12, Hh);
        X := 180;
        DlgText(Hps, Hh, X, 16, 'Pascal Developer', CLR_DARKBLUE);
        DlgText(Hps, Hh, X, 36, 'Version 1.0', CLR_BLACK);
        DlgText(Hps, Hh, X, 64, Acc('Environnement de d^eveloppement'), CLR_BLACK);
        DlgText(Hps, Hh, X, 82, 'Pascal pour Pasdows 95', CLR_BLACK);
        DlgText(Hps, Hh, X, 100, '(compilateur WPC)', CLR_DARKGRAY);
        DlgText(Hps, Hh, X, 130, 'Auteur : Sylvain Maltais', CLR_BLACK);
        DlgText(Hps, Hh, X, 148, 'Date : 2026', CLR_BLACK);
        DlgText(Hps, Hh, X, 166, 'Licence : MIT', CLR_BLACK);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_COMMAND : If Lo16(Mp1) = ID_DOK Then CloseBox(AboutFr);
    WM_CLOSE : CloseBox(AboutFr);
  Else
    AboutProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ fenetre de dialogue centree, possedee par la fenetre de l'EDI : Cls,
  titre, taille totale ; Cl : la meme fenetre (zone client) }
Function OpenBox(Cls, Title : String; Wd, Ht : LongInt; Var Cl : LongInt) : LongInt;
Var Fr, Sw, Sh : LongInt;
Begin
  Sw := GetSystemMetrics(0); Sh := GetSystemMetrics(1);
  PutZ(LongInt(@ClsBuf), Cls);
  Fr := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@ClsBuf), Z2(Title),
                        WS_POPUP Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE,
                        MaxI(0, (Sw - Wd) Div 2), MaxI(0, (Sh - Ht) Div 2), Wd, Ht, Frame, 0, Inst, 0);
  Cl := Fr;
  If Fr <> 0 Then
  Begin
    Dummy := SetActiveWindow(Fr);
    Dummy := SetFocus(Fr);
  End;
  OpenBox := Fr;
End;

{ boite de compilation (comme celle de Borland Pascal) : fichier,
  destination, etape, ligne, erreurs ; fermee a la fin de la compilation }
Function PhaseName(Ph : LongInt) : String;
Begin
  Case Ph Of
    1 : PhaseName := 'Lecture du source';
    2 : PhaseName := Acc('D^eclarations');
    3 : PhaseName := Acc('Proc^edures et instructions');
    4 : PhaseName := Acc('G^en^eration du code');
    5 : PhaseName := Acc('^Ecriture de ') + NameOf(LastExe);
    9 : PhaseName := Acc('Termin^ee');
  Else
    PhaseName := 'Chargement du compilateur';
  End;
End;

Function CompProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps, Hh, Y, Ph, Ln, Tot, Pc, T, Bw : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  CompProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        Hh := Rc[3]; Bw := Rc[2];
        Ph := 0; Ln := 0; Tot := 0;
        If PrgMem <> 0 Then
        Begin
          Ph := RdL(PrgMem + 4); Ln := RdL(PrgMem + 8); Tot := RdL(PrgMem + 12);
        End;
        If (SrcWin >= 0) And (Wins[SrcWin].NLines > Tot) Then Tot := Wins[SrcWin].NLines;
        If Ln > Tot Then Tot := Ln;
        Y := 12;
        InfoLine(Hps, Hh, Y, 'Fichier principal :', NameOf(LastSrc)); Y := Y + 20;
        InfoLine(Hps, Hh, Y, 'Destination :', TargetName(LastTarget)); Y := Y + 20;
        InfoLine(Hps, Hh, Y, Acc('^Etape :'), PhaseName(Ph)); Y := Y + 20;
        InfoLine(Hps, Hh, Y, 'Ligne :', NStr(Ln) + ' / ' + NStr(Tot)); Y := Y + 20;
        If PrgMem <> 0 Then
        Begin
          InfoLine(Hps, Hh, Y, 'Erreurs :', IStr(RdL(PrgMem + 16)) + '   Avertissements : ' + IStr(RdL(PrgMem + 20)));
          Y := Y + 20;
        End;
        T := GetTickCount - CompT0;
        InfoLine(Hps, Hh, Y, Acc('Dur^ee :'), IStr(T Div 1000) + ',' + IStr((T Mod 1000) Div 100) + ' s');
        Y := Y + 28;
        { barre de progression : lecture 0-20 %, declarations 20-30 %,
          procedures 30-70 % (selon la ligne), code 70-90 %, ecriture 90 % }
        If Tot <= 0 Then Tot := 1;
        Case Ph Of
          1 : Pc := (Ln * 20) Div Tot;
          2 : Pc := 25;
          3 : Pc := 30 + (Ln * 40) Div Tot;
          4 : Pc := 80;
          5 : Pc := 95;
          9 : Pc := 100;
        Else
          Pc := 0;
        End;
        If Pc > 100 Then Pc := 100;
        Rc[0] := 16; Rc[2] := Bw - 16; Rc[1] := Y; Rc[3] := Y + 18;
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_DARKGRAY);
        Rc[0] := 17; Rc[1] := Rc[1] + 1; Rc[3] := Rc[3] - 1; Rc[2] := Bw - 17;
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_WHITE);
        Rc[2] := 17 + ((Bw - 34) * Pc) Div 100;
        If Rc[2] > Rc[0] Then Dummy := FillRc(Hps, LongInt(@Rc), CLR_DARKBLUE);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_CREATE :
      Dummy := Btn(H, 'Annuler', True, 328, 10, 90, 26, ID_DCANCEL);
    { Annuler, Echap ou fermeture : arreter le compilateur ; sinon la boite
      se ferme d'elle-meme a la fin de la compilation }
    WM_COMMAND : If Lo16(Mp1) = ID_DCANCEL Then CompileAbort;
    WM_CLOSE : CompileAbort;
  Else
    CompProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

Procedure CompBoxOpen;
Begin
  If CompFr <> 0 Then CloseBox(CompFr);
  CompFr := OpenBox('PDCOMP', 'Compilation', 440, 250, CompCl);
End;

Procedure CompBoxClose;
Begin
  CloseBox(CompFr);
  CompCl := 0;
  Dummy := SetFocus(Client);
End;

Procedure ShowInfo;
Var Cl : LongInt;
Begin
  CloseBox(InfoFr);
  InfoFr := OpenBox('PDINFO', 'Information', 480, 360, Cl);
  If Cl <> 0 Then Dummy := SetFocus(GetDlgItem(Cl, ID_DOK));
End;

Procedure ShowAbout;
Var Cl : LongInt;
Begin
  CloseBox(AboutFr);
  AboutFr := OpenBox('PDABOUT', Acc('A propos de Pascal Developer'), 440, 250, Cl);
  If Cl <> 0 Then Dummy := SetFocus(GetDlgItem(Cl, ID_DOK));
End;

{ ==================================================================== }
{ Dialogues : saisie, ouverture, liste des fenetres                     }
{ ==================================================================== }

Var
  DlgWin : LongInt;                    { fenetre concernee (Enregistrer sous) }
  DlgItems : Array[0..511] Of String;  { elements de la liste }
  DlgNItems : LongInt;

Procedure CloseDlg;
Begin
  CloseBox(DlgFr);
  DlgCl := 0; DlgEf := 0; DlgLb := 0;
End;

Procedure OpenInput(Mode : LongInt; Title, Prompt, Def : String);
Var Cl : LongInt;
Begin
  CloseDlg;
  DlgMode := Mode; DlgPrompt := Prompt;
  If Mode = DM_SAVEAS Then DlgWin := SrcWin;
  DlgFr := OpenBox('PDINPUT', Title, 460, 130, Cl);
  If DlgFr = 0 Then Exit;
  Dummy := SetWindowTextA(DlgEf, Z(Def));
  Dummy := SendMessageA(DlgEf, EM_SETSEL, 0, Length(Def));
  Dummy := SetFocus(DlgEf);
End;

Procedure ListAdd(S : String);
Begin
  If DlgNItems > 511 Then Exit;
  DlgItems[DlgNItems] := S;
  Inc(DlgNItems);
  Dummy := SendMessageA(DlgLb, LB_ADDSTRING, 0, Z(S));
End;

{ repertoires puis sources (*.PAS, *.INC) de DlgDir }
Procedure FillOpenList;
Var SR : SearchRec; N, E : String; K : LongInt;
Begin
  Dummy := SendMessageA(DlgLb, LB_RESETCONTENT, 0, 0);
  DlgNItems := 0;
  If Length(DlgDir) > 3 Then ListAdd('[..]');
  FindFirst(DlgDir + '*.*', Directory, SR);
  While DosError = 0 Do
  Begin
    If ((SR.Attr And Directory) <> 0) And (SR.Name <> '.') And (SR.Name <> '..') Then ListAdd('[' + SR.Name + ']');
    FindNext(SR);
  End;
  FindFirst(DlgDir + '*.*', AnyFile, SR);
  While DosError = 0 Do
  Begin
    If (SR.Attr And Directory) = 0 Then
    Begin
      N := UpStr(SR.Name);
      K := Length(N);
      While (K > 0) And (N[K] <> '.') Do Dec(K);
      If K > 0 Then E := Copy(N, K, 4) Else E := '';
      If (E = '.PAS') Or (E = '.INC') Or (E = '.PP') Or (E = '.DPR') Then ListAdd(SR.Name);
    End;
    FindNext(SR);
  End;
  Dummy := InvalidateRect(DlgCl, 0, 1);
End;

Procedure OpenFileDlg;
Var Cl : LongInt;
Begin
  CloseDlg;
  DlgMode := DM_OPEN;
  If DlgDir = '' Then DlgDir := WorkDir;
  DlgFr := OpenBox('PDOPEN', 'Ouvrir un fichier', 470, 360, Cl);
  If DlgFr = 0 Then Exit;
  FillOpenList;
  Dummy := SetWindowTextA(DlgEf, Z('*.PAS'));
  Dummy := SendMessageA(DlgEf, EM_SETSEL, 0, 5);
  Dummy := SetFocus(DlgEf);
End;

Procedure WinListDlg;
Var Cl, K, W : LongInt;
Begin
  CloseDlg;
  DlgMode := 0;
  DlgFr := OpenBox('PDWINLIST', Acc('Fen^etres'), 470, 300, Cl);
  If DlgFr = 0 Then Exit;
  DlgNItems := 0;
  For K := NZ - 1 DownTo 0 Do
  Begin
    W := ZOrd[K];
    ListAdd(IStr(Wins[W].Num) + ' - ' + WinTitle(W));
    DlgItems[DlgNItems - 1] := IStr(W);
  End;
  Dummy := SendMessageA(DlgLb, LB_SETCURSEL, 0, 0);
  Dummy := SetFocus(DlgLb);
End;

Procedure Command(Id : LongInt); Forward;

{ chemin d'un repertoire choisi dans la liste ou tape }
Function IsDir(P : String) : Boolean;
Var SR : SearchRec;
Begin
  IsDir := False;
  If P = '' Then Exit;
  If (P[Length(P)] = '\') Or (P[Length(P)] = ':') Then
  Begin
    IsDir := True;
    Exit;
  End;
  FindFirst(P, Directory, SR);
  IsDir := (DosError = 0) And ((SR.Attr And Directory) <> 0);
End;

Procedure OpenChoice(S : String);
Var P : String;
Begin
  S := Trim(S);
  If S = '' Then Exit;
  If S = '[..]' Then
  Begin
    P := Copy(DlgDir, 1, Length(DlgDir) - 1);
    DlgDir := DirOf(P);
    FillOpenList;
    Exit;
  End;
  If (S[1] = '[') And (S[Length(S)] = ']') Then
  Begin
    DlgDir := DlgDir + Copy(S, 2, Length(S) - 2) + '\';
    FillOpenList;
    Exit;
  End;
  If (Length(S) < 2) Or ((S[2] <> ':') And (S[1] <> '\')) Then P := DlgDir + S Else P := S;
  If (Pos('*', P) > 0) Or (Pos('?', P) > 0) Then
  Begin
    DlgDir := DirOf(FullPath(P));
    FillOpenList;
    Exit;
  End;
  If IsDir(P) Then
  Begin
    P := FullPath(P);
    If P[Length(P)] <> '\' Then P := P + '\';
    DlgDir := P;
    FillOpenList;
    Exit;
  End;
  CloseDlg;
  If OpenDoc(P, False) >= 0 Then ;
End;

Procedure DlgDone;
Var S : String; I, V, E, W : LongInt;
Begin
  Dummy := GetWindowTextA(DlgEf, LongInt(@TxtBuf), 255);
  S := Trim(GetZ(LongInt(@TxtBuf)));
  Case DlgMode Of
    DM_SAVEAS :
      Begin
        W := DlgWin;
        If (W < 0) Or Not Wins[W].Used Or (S = '') Then
        Begin
          CloseDlg;
          Exit;
        End;
        If Not HasExt(S) Then S := S + '.PAS';
        S := FullPath(S);
        If FileExists(S) And (S <> Wins[W].FileName) Then
          If AskYesNo(Acc('Le fichier ') + S + Acc(' existe d^ej^a. Le remplacer ?'), 'Enregistrer sous',
                      MB_YESNO Or MB_QUERY) <> MBID_YES Then Exit;
        CloseDlg;
        If SaveFile(W, S) Then
        Begin
          Wins[W].FileName := S;
          StatusMsg := Acc('Enregistr^e : ') + S;
          Redraw;
          If PendCmd <> 0 Then
          Begin
            I := PendCmd;
            PendCmd := 0;
            Command(I);
          End;
        End;
      End;
    DM_FIND :
      Begin
        CloseDlg;
        FindText := S;
        FindAgain(SrcWin);
      End;
    DM_GOTO :
      Begin
        CloseDlg;
        Val(S, V, E);
        If E = 0 Then GotoLine(SrcWin, V);
      End;
    DM_PARAMS :
      Begin
        CloseDlg;
        RunParams := S;
      End;
    DM_OPEN :
      Begin
        I := SendMessageA(DlgLb, LB_GETCURSEL, 0, 0);
        If (S = '') And (I >= 0) And (I < DlgNItems) Then S := DlgItems[I];
        OpenChoice(S);
      End;
  Else
    Begin
      { liste des fenetres }
      I := SendMessageA(DlgLb, LB_GETCURSEL, 0, 0);
      CloseDlg;
      If (I >= 0) And (I < DlgNItems) Then
      Begin
        Val(DlgItems[I], W, E);
        If (E = 0) And (W >= 0) And (W < MAXWIN) And Wins[W].Used Then Activate(W);
      End;
    End;
  End;
End;

{ touches des dialogues (boucle des messages, avant la traduction) :
  Entree (bouton par defaut, ou l'element de la liste), Echap, Tab ;
  vrai si la touche est prise }
Function DlgKey(Hw, Vk : LongInt) : Boolean;
Var D, I : LongInt; Sh : Boolean;
Begin
  DlgKey := False;
  D := 0;
  If (Hw = DlgFr) Or (Hw = InfoFr) Or (Hw = AboutFr) Or (Hw = CompFr) Then D := Hw
  Else
  Begin
    I := GetParent(Hw);
    If (I = DlgFr) Or (I = InfoFr) Or (I = AboutFr) Or (I = CompFr) Then D := I;
  End;
  If D = 0 Then Exit;
  Sh := (GetKeyState($10) And $8000) <> 0;
  Case Vk Of
    9 : TabNext(D, Hw, Sh);
    13 :
      If D = DlgFr Then
      Begin
        If (Hw = DlgLb) And (DlgMode = DM_OPEN) Then
        Begin
          I := SendMessageA(DlgLb, LB_GETCURSEL, 0, 0);
          If (I >= 0) And (I < DlgNItems) Then
          Begin
            Dummy := SetWindowTextA(DlgEf, Z(''));
            OpenChoice(DlgItems[I]);
          End;
        End
        Else DlgDone;
      End
      Else If D = InfoFr Then CloseBox(InfoFr)
      Else If D = AboutFr Then CloseBox(AboutFr);
    27 :
      If D = DlgFr Then CloseDlg
      Else If D = InfoFr Then CloseBox(InfoFr)
      Else If D = AboutFr Then CloseBox(AboutFr)
      Else CompileAbort;
  Else
    Exit;
  End;
  DlgKey := True;
End;

Function InputProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  InputProc := 0;
  Case Msg Of
    WM_CREATE :
      Begin
        DlgCl := H;
        DlgEf := Ctl(H, 'EDIT', '', ES_AUTOHSCROLL, WS_EX_CLIENTEDGE, 8, 42, 432, 22, ID_DEF);
        Dummy := SendMessageA(DlgEf, EM_LIMITTEXT, 250, 0);
        Dummy := Btn(H, 'OK', True, 264, 8, 84, 24, ID_DOK);
        Dummy := Btn(H, 'Annuler', False, 356, 8, 84, 24, ID_DCANCEL);
      End;
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        DlgText(Hps, Rc[3], 8, 10, DlgPrompt, CLR_BLACK);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_COMMAND :
      If Lo16(Mp1) = ID_DOK Then DlgDone Else If Lo16(Mp1) = ID_DCANCEL Then CloseDlg;
    WM_CLOSE : CloseDlg;
  Else
    InputProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

Function OpenProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps, I : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  OpenProc := 0;
  Case Msg Of
    WM_CREATE :
      Begin
        DlgCl := H;
        DlgEf := Ctl(H, 'EDIT', '', ES_AUTOHSCROLL, WS_EX_CLIENTEDGE, 8, 264, 444, 22, ID_DEF);
        Dummy := SendMessageA(DlgEf, EM_LIMITTEXT, 250, 0);
        DlgLb := Ctl(H, 'LISTBOX', '', LBS_NOTIFY Or WS_VSCROLL Or WS_BORDER, WS_EX_CLIENTEDGE,
                     8, 40, 444, 196, ID_DLIST);
        Dummy := Btn(H, 'Ouvrir', True, 276, 8, 84, 24, ID_DOK);
        Dummy := Btn(H, 'Annuler', False, 368, 8, 84, 24, ID_DCANCEL);
      End;
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        DlgText(Hps, Rc[3], 8, Rc[3] - 284 - 20, 'Nom du fichier :', CLR_BLACK);
        DlgText(Hps, Rc[3], 8, Rc[3] - 236 - 20, Acc('R^epertoire : ') + DlgDir, CLR_DARKBLUE);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_COMMAND :
      If Lo16(Mp1) = ID_DLIST Then
      Begin
        I := SendMessageA(DlgLb, LB_GETCURSEL, 0, 0);
        If (I >= 0) And (I < DlgNItems) Then
        Begin
          If Hi16(Mp1) = LBN_DBLCLK Then
          Begin
            Dummy := SetWindowTextA(DlgEf, Z(''));
            OpenChoice(DlgItems[I]);
          End
          Else If Hi16(Mp1) = LBN_SELCHANGE Then
            If DlgItems[I][1] <> '[' Then Dummy := SetWindowTextA(DlgEf, Z(DlgItems[I]));
        End;
      End
      Else If Lo16(Mp1) = ID_DOK Then DlgDone Else If Lo16(Mp1) = ID_DCANCEL Then CloseDlg;
    WM_CLOSE : CloseDlg;
  Else
    OpenProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

Function WinListProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  WinListProc := 0;
  Case Msg Of
    WM_CREATE :
      Begin
        DlgCl := H;
        DlgEf := 0;
        DlgLb := Ctl(H, 'LISTBOX', '', LBS_NOTIFY Or WS_VSCROLL Or WS_BORDER, WS_EX_CLIENTEDGE,
                     8, 40, 444, 210, ID_DLIST);
        Dummy := Btn(H, 'Activer', True, 276, 8, 84, 24, ID_DOK);
        Dummy := Btn(H, 'Annuler', False, 368, 8, 84, 24, ID_DCANCEL);
      End;
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        Dummy := FillRc(Hps, LongInt(@Rc), CLR_PALEGRAY);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_COMMAND :
      If Lo16(Mp1) = ID_DLIST Then
      Begin
        If Hi16(Mp1) = LBN_DBLCLK Then DlgDone;
      End
      Else If Lo16(Mp1) = ID_DOK Then DlgDone Else If Lo16(Mp1) = ID_DCANCEL Then CloseDlg;
    WM_CLOSE : CloseDlg;
  Else
    WinListProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ ==================================================================== }
{ Menus                                                                 }
{ ==================================================================== }

{ menus : pile des menus en construction (barre ou menu surgissant,
  sous-menus) ; MItem avec MIS_SUBMENU annonce le sous-menu que le
  MenuOpen suivant cree }
Const
  MIS_TEXT = 0; MIS_SUBMENU = $10; MIS_SEPARATOR = $800;
  MIA_DISABLED = MF_GRAYED; MIA_CHECKED = MF_CHECKED;
Var
  MStk : Array[0..3] Of LongInt;
  MDepth : LongInt;
  MBar : Boolean;                      { MenuOpen de niveau 0 : barre de menus }
  MSubText : String;

{ texte d'un menu : ~ (lettre soulignee) -> & }
Function MenuText(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  MenuText := S;
End;

Function MenuOpen : LongInt;
Var H : LongInt;
Begin
  If (MDepth = 0) And MBar Then H := CreateMenu Else H := CreatePopupMenu;
  If MDepth > 0 Then Dummy := AppendMenuA(MStk[MDepth - 1], MF_POPUP, H, Z(MenuText(MSubText)));
  If MDepth < 4 Then
  Begin
    MStk[MDepth] := H;
    Inc(MDepth);
  End;
  MenuOpen := H;
End;

Procedure MenuClose(H, Count : LongInt);
Begin
  If MDepth > 0 Then Dec(MDepth);
End;

Procedure MItem(Style, Attr, Id : LongInt; S : String);
Begin
  If (Style And MIS_SUBMENU) <> 0 Then
  Begin
    MSubText := S;
    Exit;
  End;
  If MDepth = 0 Then Exit;
  If (Style And MIS_SEPARATOR) <> 0 Then Dummy := AppendMenuA(MStk[MDepth - 1], MF_SEPARATOR, 0, 0)
  Else Dummy := AppendMenuA(MStk[MDepth - 1], MF_STRING Or Attr, Id, Z(MenuText(S)));
End;

Procedure MSep;
Begin
  MItem(MIS_SEPARATOR, 0, 0, '');
End;

Procedure BuildMenu;
Var H0, H1 : LongInt;
Begin
  MDepth := 0; MBar := True;
  H0 := MenuOpen;
  MBar := False;
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 100, '~Fichier');
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_NEW, '~Nouveau' + Chr(9) + 'Ctrl+N');
  MItem(MIS_TEXT, 0, CM_OPEN, '~Ouvrir...' + Chr(9) + 'F3');
  MItem(MIS_TEXT, 0, CM_SAVE, '~Enregistrer' + Chr(9) + 'F2');
  MItem(MIS_TEXT, 0, CM_SAVEAS, 'Enregistrer ~sous...');
  MItem(MIS_TEXT, 0, CM_SAVEALL, 'Enregistrer ~tout');
  MSep;
  MItem(MIS_TEXT, 0, CM_CLOSE, '~Fermer' + Chr(9) + 'Alt+F3');
  MSep;
  MItem(MIS_TEXT, 0, CM_EXIT, '~Quitter' + Chr(9) + 'Alt+X');
  MenuClose(H1, 9);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 200, '~Edition');
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_CUT, '~Couper' + Chr(9) + 'Maj+Suppr');
  MItem(MIS_TEXT, 0, CM_COPY, 'C~opier' + Chr(9) + 'Ctrl+Ins');
  MItem(MIS_TEXT, 0, CM_PASTE, 'Co~ller' + Chr(9) + 'Maj+Ins');
  MItem(MIS_TEXT, 0, CM_CLEAR, '~Effacer' + Chr(9) + 'Ctrl+Suppr');
  MSep;
  MItem(MIS_TEXT, 0, CM_SELALL, Acc('~Tout s^electionner') + Chr(9) + 'Ctrl+A');
  MenuClose(H1, 6);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 300, '~Recherche');
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_FIND, '~Rechercher...' + Chr(9) + 'Ctrl+F');
  MItem(MIS_TEXT, 0, CM_FINDNEXT, '~Occurrence suivante' + Chr(9) + 'Ctrl+L');
  MItem(MIS_TEXT, 0, CM_GOTO, Acc('~Aller ^a la ligne...') + Chr(9) + 'Ctrl+G');
  MSep;
  MItem(MIS_TEXT, 0, CM_OPENCUR, 'Ouvrir le ~fichier au curseur' + Chr(9) + 'Ctrl+Entr' + Chr(130) + 'e');
  MenuClose(H1, 5);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 400, Acc('Ex^ecu~ter'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_RUN, Acc('~Ex^ecuter') + Chr(9) + 'Ctrl+F9');
  MItem(MIS_TEXT, 0, CM_PARAMS, Acc('~Param^etres...'));
  MenuClose(H1, 2);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 500, '~Compiler');
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_COMPILE, '~Compiler' + Chr(9) + 'F9');
  MItem(MIS_TEXT, 0, CM_INFO, '~Information...');
  MSep;
  MItem(MIS_TEXT, MIA_CHECKED, CM_TGTPM, Acc('Destination ~Windows (fen^etres)'));
  MItem(MIS_TEXT, 0, CM_TGTCON, 'Destination Co~nsole Win32');
  MenuClose(H1, 5);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 600, Acc('Fe~n^etre'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_TILE, Acc('~Mosa^ique'));
  MItem(MIS_TEXT, 0, CM_CASCADE, '~Cascade');
  MItem(MIS_TEXT, 0, CM_NEXT, '~Suivante' + Chr(9) + 'F6');
  MItem(MIS_TEXT, 0, CM_MESSAGES, 'M~essages');
  MItem(MIS_TEXT, 0, CM_WIN0, '~Liste...' + Chr(9) + 'Alt+0');
  MSep;
  MItem(MIS_TEXT, 0, CM_CLOSEALL, '~Fermer tout');
  MenuClose(H1, 7);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, 700, 'A~ide');
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, CM_KEYS, '~Touches' + Chr(9) + 'F1');
  MItem(MIS_TEXT, 0, CM_ABOUT, '~A propos de Pascal Developer...');
  MenuClose(H1, 2);
  MenuClose(H0, 7);
  MenuHw := H0;
  Dummy := SetMenu(Frame, MenuHw);
End;

Procedure SetTarget(T : LongInt);
Begin
  Target := T;
  If T = 0 Then
  Begin
    Dummy := CheckMenuItem(MenuHw, CM_TGTPM, MF_CHECKED);
    Dummy := CheckMenuItem(MenuHw, CM_TGTCON, 0);
  End
  Else
  Begin
    Dummy := CheckMenuItem(MenuHw, CM_TGTCON, MF_CHECKED);
    Dummy := CheckMenuItem(MenuHw, CM_TGTPM, 0);
  End;
  StatusMsg := 'Destination : ' + TargetName(T);
  Redraw;
End;

{ menu contextuel de l'editeur, au point (X, Y) de la zone client }
Procedure ShowContext(X, Y : LongInt);
Var H0, W, A, N : LongInt; F : String; Pt : Array[0..1] Of LongInt;
Begin
  W := ActEdit;
  If W < 0 Then Exit;
  If HasSel(W) Then A := 0 Else A := MIA_DISABLED;
  MDepth := 0; MBar := False;
  If CtxMenu <> 0 Then Dummy := DestroyMenu(CtxMenu);
  H0 := MenuOpen;
  MItem(MIS_TEXT, A, CM_CUT, '~Couper' + Chr(9) + 'Maj+Suppr');
  MItem(MIS_TEXT, A, CM_COPY, 'C~opier' + Chr(9) + 'Ctrl+Ins');
  MItem(MIS_TEXT, 0, CM_PASTE, 'Co~ller' + Chr(9) + 'Maj+Ins');
  MItem(MIS_TEXT, A, CM_CLEAR, '~Effacer' + Chr(9) + 'Ctrl+Suppr');
  MSep;
  MItem(MIS_TEXT, 0, CM_SELALL, Acc('~Tout s^electionner') + Chr(9) + 'Ctrl+A');
  MSep;
  F := WordAt(W, True);
  If F <> '' Then MItem(MIS_TEXT, 0, CM_OPENCUR, 'Ouvrir le ~fichier ' + F)
  Else MItem(MIS_TEXT, MIA_DISABLED, CM_OPENCUR, 'Ouvrir le ~fichier au curseur');
  MItem(MIS_TEXT, 0, CM_GOTO, Acc('~Aller ^a la ligne...'));
  MSep;
  MItem(MIS_TEXT, 0, CM_COMPILE, 'Co~mpiler' + Chr(9) + 'F9');
  MItem(MIS_TEXT, 0, CM_RUN, Acc('Ex^ecute~r') + Chr(9) + 'Ctrl+F9');
  MItem(MIS_TEXT, 0, CM_INFO, '~Information...');
  N := 13;
  MenuClose(H0, N);
  CtxMenu := H0;
  Pt[0] := X; Pt[1] := Y;
  Dummy := ClientToScreen(Client, LongInt(@Pt));
  If CtxMenu <> 0 Then Dummy := TrackPopupMenu(CtxMenu, TPM_RIGHTBUTTON, Pt[0], Pt[1], 0, Frame, 0);
End;

{ Maj+F10 : menu contextuel au curseur du texte }
Procedure ContextAtCursor;
Var W, X1, Y1, X2, Y2, X, Y : LongInt;
Begin
  W := ActEdit;
  If W < 0 Then Exit;
  TextArea(W, X1, Y1, X2, Y2);
  X := MinI(X2 - 1, MaxI(X1, X1 + 4 + (Wins[W].CX - Wins[W].LeftC) * CHW));
  Y := MinI(Y2 - 1, MaxI(Y1, Y1 + (Wins[W].CY - Wins[W].TopL + 1) * CHH));
  ShowContext(X, Y);
End;

{ ouvrir le fichier dont le nom est sous le curseur (directive $I X.INC, Uses X) }
Procedure OpenAtCursor;
Var W, R : LongInt; N, D : String;
Begin
  W := ActEdit;
  If W < 0 Then Exit;
  N := WordAt(W, True);
  If N = '' Then
  Begin
    StatusMsg := Acc('Aucun nom de fichier sous le curseur');
    Redraw;
    Exit;
  End;
  If Wins[W].FileName <> '' Then D := DirOf(Wins[W].FileName) Else D := WorkDir;
  R := -1;
  If FileExists(D + N) Then R := OpenDoc(D + N, True)
  Else If FileExists(D + N + '.PAS') Then R := OpenDoc(D + N + '.PAS', True)
  Else If FileExists(D + N + '.INC') Then R := OpenDoc(D + N + '.INC', True)
  Else If FileExists(N) Then R := OpenDoc(N, True)
  Else If FileExists(N + '.PAS') Then R := OpenDoc(N + '.PAS', True);
  If R < 0 Then ShowMsg(Acc('Fichier introuvable : ') + N, 'Ouvrir le fichier au curseur', MB_OK Or MB_WARNING);
End;

Procedure ShowKeys;
Begin
  Begin
    LClr;
    LAdd('' + Acc('F2 enregistrer, F3 ouvrir, Alt+F3 fermer, F6 fen^etre suivante, Alt+0 liste des fen^etres, ') +
         Acc('F9 compiler, Ctrl+F9 ex^ecuter, Alt+X quitter. Ins : insertion ou refrappe. '));
    LAdd('' + Acc('Maj+fl^eches : s^election ; Ctrl+Ins/Ctrl+C copier, Maj+Suppr/Ctrl+X couper, ') +
         Acc('Maj+Ins/Ctrl+V coller, Ctrl+Suppr effacer, Ctrl+A tout s^electionner, Ctrl+Y supprimer la ligne. '));
    LAdd('' +
         Acc('Ctrl+F rechercher, Ctrl+L suivant, Ctrl+G aller ^a la ligne, Ctrl+Entr^ee ouvrir le fichier ') +
         Acc('au curseur. Bouton 2 de la souris ou Maj+F10 : menu contextuel.'));
    Dummy := LMsgBox('Touches', MB_OK Or MB_INFORMATION);
  End;
End;

Procedure Quit;
Begin
  If CloseAll Then PostQuitMessage(0);
End;

Procedure Command(Id : LongInt);
Var W, K : LongInt;
Begin
  W := ActEdit;
  Case Id Of
    CM_NEW : If NewDoc >= 0 Then ;
    CM_OPEN : OpenFileDlg;
    CM_SAVE : If SrcWin >= 0 Then If SaveDoc(SrcWin) Then ;
    CM_SAVEAS :
      If SrcWin >= 0 Then
      Begin
        If Wins[SrcWin].FileName <> '' Then OpenInput(DM_SAVEAS, 'Enregistrer sous', 'Nom du fichier :', Wins[SrcWin].FileName)
        Else OpenInput(DM_SAVEAS, 'Enregistrer sous', 'Nom du fichier :', WorkDir + 'NONAME' + IStr(Wins[SrcWin].Untitled) + '.PAS');
      End;
    CM_SAVEALL :
      For K := 0 To MAXWIN - 1 Do
        If Wins[K].Used And (Wins[K].Kind = WK_EDIT) And Wins[K].Modified And (Wins[K].FileName <> '') Then
          If SaveFile(K, Wins[K].FileName) Then Redraw;
    CM_CLOSE : If TopWin >= 0 Then If CloseWin(TopWin) Then ;
    CM_EXIT : Quit;
    CM_CUT : If W >= 0 Then Begin CutSel(W); Redraw; End;
    CM_COPY : If W >= 0 Then CopySel(W);
    CM_PASTE : If W >= 0 Then Begin Paste(W); Redraw; End;
    CM_CLEAR : If W >= 0 Then Begin If DeleteSel(W) Then ; Redraw; End;
    CM_SELALL : If W >= 0 Then Begin SelectAll(W); Redraw; End;
    CM_FIND : If SrcWin >= 0 Then OpenInput(DM_FIND, 'Rechercher', Acc('Texte ^a rechercher :'), FindText);
    CM_FINDNEXT : If FindText = '' Then Command(CM_FIND) Else FindAgain(SrcWin);
    CM_GOTO :
      If SrcWin >= 0 Then
        OpenInput(DM_GOTO, Acc('Aller ^a la ligne'), Acc('Num^ero de ligne (1 ^a ') + IStr(Wins[SrcWin].NLines) + ') :',
                  IStr(Wins[SrcWin].CY + 1));
    CM_OPENCUR : OpenAtCursor;
    CM_RUN : RunProgram;
    CM_PARAMS : OpenInput(DM_PARAMS, Acc('Param^etres'), Acc('Param^etres du programme :'), RunParams);
    CM_COMPILE :
      Begin
        PendRun := False;
        If Compile Then ;
      End;
    CM_INFO : ShowInfo;
    CM_TGTPM : SetTarget(0);
    CM_TGTCON : SetTarget(1);
    CM_TILE : Tile;
    CM_CASCADE : Cascade;
    CM_NEXT : NextWin;
    CM_MESSAGES : ShowMessages;
    CM_WIN0 : WinListDlg;
    CM_CLOSEALL : If CloseAll Then ;
    CM_KEYS : ShowKeys;
    CM_ABOUT : ShowAbout;
  End;
  { apres un menu, le clavier revient a l'editeur (sauf dialogue ouvert) }
  If (DlgFr = 0) And (InfoFr = 0) And (AboutFr = 0) And (GetActiveWindow = Frame) Then
    Dummy := SetFocus(Client);
End;

{ ==================================================================== }
{ Souris                                                                }
{ ==================================================================== }

{ fenetre sous le point (X, Y), de la plus haute a la plus basse }
Function HitWin(X, Y : LongInt) : LongInt;
Var K, W, Wx, Wy, Wd, Ht : LongInt;
Begin
  HitWin := -1;
  For K := NZ - 1 DownTo 0 Do
  Begin
    W := ZOrd[K];
    Geo(W, Wx, Wy, Wd, Ht);
    If (X >= Wx) And (X < Wx + Wd) And (Y >= Wy) And (Y < Wy + Ht) Then
    Begin
      HitWin := W;
      Exit;
    End;
  End;
End;

{ position du texte (colonne, ligne) sous le point (X, Y) }
Procedure TextPos(W, X, Y : LongInt; Var C, L : LongInt);
Var X1, Y1, X2, Y2 : LongInt;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  C := Wins[W].LeftC + (X - X1 - 4 + CHW Div 2) Div CHW;
  If X - X1 - 4 < 0 Then C := Wins[W].LeftC;
  If Y < Y1 Then L := Wins[W].TopL - 1
  Else L := Wins[W].TopL + (Y - Y1) Div CHH;
  If C < 0 Then C := 0;
  If C > MAXLEN Then C := MAXLEN;
  If L < 0 Then L := 0;
  If L >= ContentLines(W) Then L := ContentLines(W) - 1;
  If L < 0 Then L := 0;
End;

Procedure ThumbDrag(W, Pos : LongInt; Vert : Boolean);
Var X1, Y1, X2, Y2, L, TP, TS, Total, Vis, NewP : LongInt;
Begin
  TextArea(W, X1, Y1, X2, Y2);
  If Vert Then
  Begin
    L := Y2 - Y1 - 2 * SBW; Total := ContentLines(W); Vis := Rows(W);
    ThumbOf(L, Total, Vis, Wins[W].TopL, TP, TS);
    NewP := Pos - Y1 - SBW - DragDY;
  End
  Else
  Begin
    L := X2 - X1 - 2 * SBW; Total := MAXLEN + 1; Vis := Cols(W);
    ThumbOf(L, Total, Vis, Wins[W].LeftC, TP, TS);
    NewP := Pos - X1 - SBW - DragDX;
  End;
  If L - TS <= 0 Then Exit;
  NewP := (NewP * (Total - Vis) + (L - TS) Div 2) Div (L - TS);
  If NewP > Total - Vis Then NewP := Total - Vis;
  If NewP < 0 Then NewP := 0;
  If Vert Then Wins[W].TopL := NewP Else Wins[W].LeftC := NewP;
  Redraw;
End;

Procedure ButtonDown(X, Y, Kc : LongInt; Dbl : Boolean);
Var W, Wx, Wy, Wd, Ht, B, X1, Y1, X2, Y2, L, TP, TS, C, Ln0 : LongInt;
Begin
  W := HitWin(X, Y);
  If W < 0 Then Exit;
  If W <> TopWin Then Activate(W);
  Geo(W, Wx, Wy, Wd, Ht);
  TextArea(W, X1, Y1, X2, Y2);
  B := TTLH - 4;
  { barre de titre }
  If (Y >= Wy + BRD) And (Y < Wy + BRD + TTLH) Then
  Begin
    If (X >= Wx + BRD + 2) And (X < Wx + BRD + 2 + B) Then
    Begin
      If CloseWin(W) Then ;
      Exit;
    End;
    If (X >= Wx + Wd - BRD - 2 - B) And (X < Wx + Wd - BRD - 2) Then
    Begin
      ToggleMax(W);
      Exit;
    End;
    If Dbl Then
    Begin
      ToggleMax(W);
      Exit;
    End;
    If Not Wins[W].Max Then
    Begin
      Drag := DG_MOVE; DragWin := W; DragDX := X - Wx; DragDY := Y - Wy;
      Dummy := SetCapture(Client);
    End;
    Exit;
  End;
  { coin ou bords droit et bas : taille }
  If ((X >= X2) And (Y >= Y2)) Or (X >= Wx + Wd - BRD) Or (Y >= Wy + Ht - BRD) Then
  Begin
    If Not Wins[W].Max And ((X >= X2) Or (X >= Wx + Wd - BRD)) And ((Y >= Y2) Or (Y >= Wy + Ht - BRD)) Then
    Begin
      Drag := DG_SIZE; DragWin := W; DragDX := Wx + Wd - X; DragDY := Wy + Ht - Y;
      Dummy := SetCapture(Client);
      Exit;
    End;
  End;
  { barre de defilement verticale }
  If (X >= X2) And (X < X2 + SBW) And (Y >= Y1) And (Y < Y2) Then
  Begin
    If Y < Y1 + SBW Then ScrollBy(W, -1, 0)
    Else If Y >= Y2 - SBW Then ScrollBy(W, 1, 0)
    Else
    Begin
      L := Y2 - Y1 - 2 * SBW;
      ThumbOf(L, ContentLines(W), Rows(W), Wins[W].TopL, TP, TS);
      If Y < Y1 + SBW + TP Then ScrollBy(W, -Rows(W), 0)
      Else If Y >= Y1 + SBW + TP + TS Then ScrollBy(W, Rows(W), 0)
      Else
      Begin
        Drag := DG_VTHUMB; DragWin := W; DragDY := Y - (Y1 + SBW + TP);
        Dummy := SetCapture(Client);
      End;
    End;
    Redraw;
    Exit;
  End;
  { barre horizontale }
  If (Y >= Y2) And (Y < Y2 + SBW) And (X >= X1) And (X < X2) Then
  Begin
    If X < X1 + SBW Then ScrollBy(W, 0, -1)
    Else If X >= X2 - SBW Then ScrollBy(W, 0, 1)
    Else
    Begin
      L := X2 - X1 - 2 * SBW;
      ThumbOf(L, MAXLEN + 1, Cols(W), Wins[W].LeftC, TP, TS);
      If X < X1 + SBW + TP Then ScrollBy(W, 0, -Cols(W))
      Else If X >= X1 + SBW + TP + TS Then ScrollBy(W, 0, Cols(W))
      Else
      Begin
        Drag := DG_HTHUMB; DragWin := W; DragDX := X - (X1 + SBW + TP);
        Dummy := SetCapture(Client);
      End;
    End;
    Redraw;
    Exit;
  End;
  { texte }
  If (X >= X1) And (X < X2) And (Y >= Y1) And (Y < Y2) Then
  Begin
    TextPos(W, X, Y, C, Ln0);
    If Wins[W].Kind = WK_MSG Then
    Begin
      If Ln0 < MsgCount Then MsgSel := Ln0;
      If Dbl Then MsgGo(MsgSel) Else Redraw;
      Exit;
    End;
    If Dbl Then
    Begin
      Wins[W].CX := C; Wins[W].CY := Ln0;
      SelectWord(W);
      Redraw;
      Exit;
    End;
    CurTo(W, C, Ln0, (Kc And KC_SHIFT) <> 0);
    If Not Wins[W].SelOn Then
    Begin
      Wins[W].SelOn := True;
      Wins[W].SAX := C; Wins[W].SAY := Ln0;
    End;
    Drag := DG_SEL; DragWin := W;
    Dummy := SetCapture(Client);
    Redraw;
  End;
End;

Procedure MouseMove(X, Y : LongInt);
Var W, NX, NY, C, L, X1, Y1, X2, Y2, P : LongInt;
Begin
  W := DragWin;
  If (Drag = DG_NONE) Or (W < 0) Or Not Wins[W].Used Then
  Begin
    { forme du pointeur }
    W := HitWin(X, Y);
    P := SPTR_ARROW;
    If W >= 0 Then
    Begin
      TextArea(W, X1, Y1, X2, Y2);
      If (X >= X1) And (X < X2) And (Y >= Y1) And (Y < Y2) And (Wins[W].Kind = WK_EDIT) Then P := SPTR_TEXT
      Else If (X >= X2) And (Y >= Y2) And Not Wins[W].Max Then P := SPTR_SIZENWSE;
    End;
    Dummy := SetCursor(LoadCursorA(0, P));
    Exit;
  End;
  Case Drag Of
    DG_MOVE :
      Begin
        NX := X - DragDX; NY := Y - DragDY;
        If NY < 0 Then NY := 0;
        If NY > WorkH - TTLH Then NY := WorkH - TTLH;
        If NX > CW - 40 Then NX := CW - 40;
        If NX < 40 - Wins[W].W Then NX := 40 - Wins[W].W;
        If (NX <> Wins[W].X) Or (NY <> Wins[W].Y) Then
        Begin
          Wins[W].X := NX; Wins[W].Y := NY;
          Redraw;
        End;
      End;
    DG_SIZE :
      Begin
        NX := MaxI(160, X + DragDX - Wins[W].X);
        NY := MaxI(TTLH + 2 * BRD + 3 * SBW + CHH, Y + DragDY - Wins[W].Y);
        If (NX <> Wins[W].W) Or (NY <> Wins[W].H) Then
        Begin
          Wins[W].W := NX; Wins[W].H := NY;
          Redraw;
        End;
      End;
    DG_VTHUMB : ThumbDrag(W, Y, True);
    DG_HTHUMB : ThumbDrag(W, X, False);
    DG_SEL :
      Begin
        TextArea(W, X1, Y1, X2, Y2);
        If Y >= Y2 Then ScrollBy(W, 1, 0);
        If (Y < Y1) And (Wins[W].TopL > 0) Then ScrollBy(W, -1, 0);
        TextPos(W, X, MinI(Y, Y2 - 1), C, L);
        If (C <> Wins[W].CX) Or (L <> Wins[W].CY) Then
        Begin
          Wins[W].CX := C; Wins[W].CY := L;
          ShowCursor(W);
          RedrawText(W);
        End;
      End;
  End;
End;

Procedure ButtonUp;
Begin
  If Drag <> DG_NONE Then Dummy := ReleaseCapture;
  If (Drag = DG_SEL) And (DragWin >= 0) Then
    If Not HasSel(DragWin) Then Wins[DragWin].SelOn := False;
  Drag := DG_NONE;
  DragWin := -1;
End;

{ bouton 2 : menu contextuel (le curseur va au point s'il est hors de la selection) }
Procedure Button2(X, Y : LongInt);
Var W, C, L, X1, Y1, X2, Y2 : LongInt;
Begin
  W := HitWin(X, Y);
  If W < 0 Then Exit;
  If W <> TopWin Then Activate(W);
  If Wins[W].Kind <> WK_EDIT Then Exit;
  TextArea(W, X1, Y1, X2, Y2);
  If (X >= X1) And (X < X2) And (Y >= Y1) And (Y < Y2) Then
  Begin
    TextPos(W, X, Y, C, L);
    If Not InSel(W, L, C) Then CurTo(W, C, L, False);
    Redraw;
  End;
  ShowContext(X, Y);
End;

{ ==================================================================== }
{ Clavier                                                               }
{ ==================================================================== }

Function KeyEdit(W, Fl, Vk, KCh : LongInt) : Boolean;
Var Sh, Ct : Boolean; L : LongInt; S : String;
Begin
  KeyEdit := True;
  Sh := (Fl And KC_SHIFT) <> 0;
  Ct := (Fl And KC_CTRL) <> 0;
  If (Fl And KC_VIRTUALKEY) <> 0 Then
    Case Vk Of
      VK_LEFT :
        Begin
          If Ct Then WordLeft(W, Sh)
          Else If Wins[W].CX > 0 Then CurTo(W, Wins[W].CX - 1, Wins[W].CY, Sh)
          Else If Wins[W].CY > 0 Then CurTo(W, LineLen(W, Wins[W].CY - 1), Wins[W].CY - 1, Sh)
          Else CurTo(W, 0, 0, Sh);
          RedrawText(W);
          Exit;
        End;
      VK_RIGHT :
        Begin
          If Ct Then WordRight(W, Sh) Else CurTo(W, Wins[W].CX + 1, Wins[W].CY, Sh);
          RedrawText(W);
          Exit;
        End;
      VK_UP :
        Begin
          If Ct Then
          Begin
            ScrollBy(W, -1, 0);
            If Wins[W].CY >= Wins[W].TopL + Rows(W) Then Wins[W].CY := Wins[W].TopL + Rows(W) - 1;
          End
          Else CurTo(W, Wins[W].CX, Wins[W].CY - 1, Sh);
          RedrawText(W);
          Exit;
        End;
      VK_DOWN :
        Begin
          If Ct Then
          Begin
            ScrollBy(W, 1, 0);
            If Wins[W].CY < Wins[W].TopL Then Wins[W].CY := Wins[W].TopL;
          End
          Else CurTo(W, Wins[W].CX, Wins[W].CY + 1, Sh);
          RedrawText(W);
          Exit;
        End;
      VK_HOME :
        Begin
          If Ct Then CurTo(W, 0, 0, Sh)
          Else
          Begin
            { premier caractere non blanc, puis colonne 1 }
            L := 0;
            S := GetLine(W, Wins[W].CY);
            While (L < Length(S)) And (S[L + 1] = ' ') Do Inc(L);
            If Wins[W].CX = L Then L := 0;
            CurTo(W, L, Wins[W].CY, Sh);
          End;
          RedrawText(W);
          Exit;
        End;
      VK_END :
        Begin
          If Ct Then CurTo(W, LineLen(W, Wins[W].NLines - 1), Wins[W].NLines - 1, Sh)
          Else CurTo(W, LineLen(W, Wins[W].CY), Wins[W].CY, Sh);
          RedrawText(W);
          Exit;
        End;
      VK_PAGEUP :
        Begin
          If Ct Then CurTo(W, 0, 0, Sh)
          Else
          Begin
            ScrollBy(W, -Rows(W) + 1, 0);
            CurTo(W, Wins[W].CX, Wins[W].CY - Rows(W) + 1, Sh);
          End;
          RedrawText(W);
          Exit;
        End;
      VK_PAGEDOWN :
        Begin
          If Ct Then CurTo(W, LineLen(W, Wins[W].NLines - 1), Wins[W].NLines - 1, Sh)
          Else
          Begin
            ScrollBy(W, Rows(W) - 1, 0);
            CurTo(W, Wins[W].CX, Wins[W].CY + Rows(W) - 1, Sh);
          End;
          RedrawText(W);
          Exit;
        End;
      VK_INSERT :
        Begin
          If Sh Then Paste(W)
          Else If Ct Then CopySel(W)
          Else InsMode := Not InsMode;
          Redraw;
          Exit;
        End;
      VK_DELETE :
        Begin
          If Sh Then CutSel(W)
          Else If Ct Then Begin If DeleteSel(W) Then ; End
          Else DeleteChar(W);
          RedrawText(W);
          Exit;
        End;
      VK_BACKSPACE :
        Begin
          BackSpace(W);
          RedrawText(W);
          Exit;
        End;
      VK_ENTER, VK_NEWLINE :
        Begin
          If Ct Then OpenAtCursor
          Else
          Begin
            NewLine(W);
            RedrawText(W);
          End;
          Exit;
        End;
      VK_TAB :
        Begin
          TabKey(W);
          RedrawText(W);
          Exit;
        End;
    End;
  { caracteres }
  If ((Fl And KC_CHAR) <> 0) And (KCh >= 32) And (KCh < 256) And ((Fl And (KC_CTRL Or KC_ALT)) = 0) Then
  Begin
    TypeChar(W, Chr(KCh));
    RedrawText(W);
    Exit;
  End;
  KeyEdit := False;
End;

Function KeyMsgWin(Fl, Vk : LongInt) : Boolean;
Begin
  KeyMsgWin := True;
  If (Fl And KC_VIRTUALKEY) <> 0 Then
    Case Vk Of
      VK_UP : If MsgSel > 0 Then Dec(MsgSel);
      VK_DOWN : If MsgSel < MsgCount - 1 Then Inc(MsgSel);
      VK_ENTER, VK_NEWLINE : MsgGo(MsgSel);
    Else
      Begin
        KeyMsgWin := False;
        Exit;
      End;
    End
  Else
  Begin
    KeyMsgWin := False;
    Exit;
  End;
  If (MsgWin >= 0) And (MsgSel >= 0) Then
  Begin
    If MsgSel < Wins[MsgWin].TopL Then Wins[MsgWin].TopL := MsgSel;
    If MsgSel >= Wins[MsgWin].TopL + Rows(MsgWin) Then Wins[MsgWin].TopL := MsgSel - Rows(MsgWin) + 1;
  End;
  Redraw;
End;

{ touches de l'EDI ; Faux : a traiter par l'editeur ou PM }
Function KeyGlobal(Fl, Vk, KCh : LongInt) : Boolean;
Var C : LongInt; Ct, Al, Sh : Boolean;
Begin
  KeyGlobal := True;
  Ct := (Fl And KC_CTRL) <> 0;
  Al := (Fl And KC_ALT) <> 0;
  Sh := (Fl And KC_SHIFT) <> 0;
  If (Fl And KC_VIRTUALKEY) <> 0 Then
  Begin
    If Vk = VK_F1 Then Begin Command(CM_KEYS); Exit; End;
    If (Vk = VK_F1 + 1) And Not Al Then Begin Command(CM_SAVE); Exit; End;
    If (Vk = VK_F1 + 2) And Al Then Begin Command(CM_CLOSE); Exit; End;
    If Vk = VK_F1 + 2 Then Begin Command(CM_OPEN); Exit; End;
    If Vk = VK_F1 + 5 Then Begin Command(CM_NEXT); Exit; End;
    If (Vk = VK_F1 + 8) And Ct Then Begin Command(CM_RUN); Exit; End;
    If Vk = VK_F1 + 8 Then Begin Command(CM_COMPILE); Exit; End;
    If (Vk = VK_F1 + 9) And Sh Then Begin ContextAtCursor; Exit; End;
  End;
  If ((Fl And KC_CHAR) <> 0) Or ((Fl And KC_VIRTUALKEY) = 0) Then
  Begin
    C := KCh;
    If (C >= 1) And (C <= 26) Then C := C + 64;
    C := C And $DF;
    If Al And Not Ct Then
    Begin
      If C = Ord('X') Then Begin Command(CM_EXIT); Exit; End;
      If KCh = Ord('0') Then Begin Command(CM_WIN0); Exit; End;
    End;
    If Ct And Not Al Then
    Begin
      Case Chr(C) Of
        'N' : Begin Command(CM_NEW); Exit; End;
        'O' : Begin Command(CM_OPEN); Exit; End;
        'S' : Begin Command(CM_SAVE); Exit; End;
        'F' : Begin Command(CM_FIND); Exit; End;
        'L' : Begin Command(CM_FINDNEXT); Exit; End;
        'G' : Begin Command(CM_GOTO); Exit; End;
        'A' : Begin Command(CM_SELALL); Exit; End;
        'C' : Begin Command(CM_COPY); Exit; End;
        'X' : Begin Command(CM_CUT); Exit; End;
        'V' : Begin Command(CM_PASTE); Exit; End;
        'Y' :
          If ActEdit >= 0 Then
          Begin
            DeleteLine(ActEdit);
            Redraw;
            Exit;
          End;
      End;
    End;
  End;
  KeyGlobal := False;
End;

{ ==================================================================== }
{ Fenetre principale                                                    }
{ ==================================================================== }

{ touche (codes internes de l'editeur) : raccourcis, fenetre Messages,
  edition ; vrai si elle est prise }
Function KeyDispatch(Fl, Vk, KCh : LongInt) : Boolean;
Var W : LongInt;
Begin
  KeyDispatch := True;
  If KeyGlobal(Fl, Vk, KCh) Then Exit;
  W := TopWin;
  If (W >= 0) And (Wins[W].Kind = WK_MSG) Then
  Begin
    If KeyMsgWin(Fl, Vk) Then Exit;
  End
  Else If W >= 0 Then
    If KeyEdit(W, Fl, Vk, KCh) Then
    Begin
      If StatusMsg <> '' Then
      Begin
        StatusMsg := '';
        InvRect(0, WorkH, CW, CH);
      End;
      Exit;
    End;
  KeyDispatch := False;
End;

{ etat des touches Maj, Ctrl et Alt -> indicateurs KC_ }
Function KeyMods : LongInt;
Var F : LongInt;
Begin
  F := 0;
  If (GetKeyState($10) And $8000) <> 0 Then F := F Or KC_SHIFT;
  If (GetKeyState($11) And $8000) <> 0 Then F := F Or KC_CTRL;
  If (GetKeyState($12) And $8000) <> 0 Then F := F Or KC_ALT;
  KeyMods := F;
End;

{ touche virtuelle de Windows -> code interne (0 : aucune) }
Function MapVk(V : LongInt; Sh : Boolean) : LongInt;
Begin
  Case V Of
    8 : MapVk := VK_BACKSPACE;
    9 : If Sh Then MapVk := VK_BACKTAB Else MapVk := VK_TAB;
    13 : MapVk := VK_NEWLINE;
    27 : MapVk := VK_ESC;
    $21 : MapVk := VK_PAGEUP;
    $22 : MapVk := VK_PAGEDOWN;
    $23 : MapVk := VK_END;
    $24 : MapVk := VK_HOME;
    $25 : MapVk := VK_LEFT;
    $26 : MapVk := VK_UP;
    $27 : MapVk := VK_RIGHT;
    $28 : MapVk := VK_DOWN;
    $2D : MapVk := VK_INSERT;
    $2E : MapVk := VK_DELETE;
    $70..$7B : MapVk := VK_F1 + V - $70;
  Else
    MapVk := 0;
  End;
End;

Function MainProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Rc : Array[0..3] Of LongInt; Fl, Vk, Kc : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        CW := Rc[2]; CH := Rc[3];
      End;
    WM_PAINT : PaintAll(H);
    WM_TIMER :
      If (Mp1 And $FFFF) = 7 Then
      Begin
        { fin du compilateur ; Ctrl+F9 : execution ensuite }
        If CompilePoll And PendRun Then
        Begin
          PendRun := False;
          If LastOk Then RunProgram;
        End;
      End
      Else MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        { clic dans l'EDI : le clavier lui revient (apres la fenetre d'un
          programme lance, la boite de compilation...) }
        Dummy := SetFocus(H);
        Kc := 0;
        If (Mp1 And 4) <> 0 Then Kc := KC_SHIFT;
        If (Mp1 And 8) <> 0 Then Kc := Kc Or KC_CTRL;
        ButtonDown(S16(Mp2), S16(Mp2 Shr 16), Kc, Msg = WM_LBUTTONDBLCLK);
      End;
    WM_LBUTTONUP : ButtonUp;
    WM_RBUTTONDOWN : Button2(S16(Mp2), S16(Mp2 Shr 16));
    WM_MOUSEMOVE : MouseMove(S16(Mp2), S16(Mp2 Shr 16));
    WM_SETCURSOR :
      { zone client : la forme du pointeur suit MouseMove }
      If (Mp2 And $FFFF) = 1 Then MainProc := 1
      Else MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
    WM_COMMAND : Command(Lo16(Mp1));
    WM_KEYDOWN, WM_SYSKEYDOWN :
      Begin
        Fl := KeyMods;
        Vk := MapVk(Mp1, (Fl And KC_SHIFT) <> 0);
        If Vk <> 0 Then
        Begin
          If KeyDispatch(KC_VIRTUALKEY Or Fl, Vk, 0) Then Exit;
        End
        Else If ((Fl And (KC_CTRL Or KC_ALT)) <> 0) And
                (((Mp1 >= Ord('A')) And (Mp1 <= Ord('Z'))) Or ((Mp1 >= Ord('0')) And (Mp1 <= Ord('9')))) Then
        Begin
          { Ctrl+lettre, Alt+lettre : comme un caractere (le WM_CHAR qui
            suit est ignore) }
          Kc := Mp1;
          If (Kc >= Ord('A')) And (Kc <= Ord('Z')) Then Kc := Kc + 32;
          If KeyDispatch(KC_CHAR Or Fl, 0, Kc) Then Exit;
        End;
        MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
      End;
    WM_CHAR, WM_SYSCHAR :
      Begin
        Fl := KeyMods;
        { touches deja traitees par WM_KEYDOWN }
        If (Mp1 = 8) Or (Mp1 = 9) Or (Mp1 = 10) Or (Mp1 = 13) Or (Mp1 = 27) Or (Mp1 < 32) Or
           ((Fl And (KC_CTRL Or KC_ALT)) <> 0) Then
        Begin
          If Msg = WM_SYSCHAR Then MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
          Exit;
        End;
        If Not KeyDispatch(KC_CHAR Or (Fl And KC_SHIFT), 0, Mp1 And 255) Then
          MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
      End;
    WM_CLOSE : Quit;
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ le repertoire D (avec \ final) accepte-t-il un nouveau fichier ? }
Function CanWrite(D : String) : Boolean;
Var F : Text; R : LongInt;
Begin
  Assign(F, D + 'PASDEV.$$$');
  {$I-} Rewrite(F); {$I+}
  R := IOResult;
  CanWrite := R = 0;
  If R = 0 Then
  Begin
    Close(F);
    {$I-} Erase(F); {$I+}
    R := IOResult;
  End;
End;

Var
  K : LongInt;
  S : String;

{ classe de fenetre (WNDCLASSA) }
Procedure RegCls(N : String; P, St, Cur, Br : LongInt);
Var C : Array[0..9] Of LongInt;
Begin
  PutZ(LongInt(@ClsBuf), N);
  C[0] := St; C[1] := P; C[2] := 0; C[3] := 0; C[4] := Inst; C[5] := 0;
  C[6] := Cur; C[7] := Br; C[8] := 0; C[9] := LongInt(@ClsBuf);
  Dummy := RegisterClassA(LongInt(@C));
End;

BEGIN
  FileMode := 0;
  InsMode := True;
  Target := 0;
  MsgWin := -1;
  NZ := 0;
  Drag := DG_NONE; DragWin := -1;
  PendCmd := 0;
  CompEH := -1; TabN := 0;
  { repertoires : celui du programme (WPC.EXE a cote), repertoire de travail }
  ExeDir := DirOf(FullPath(ParamStr(0)));
  CompilerPath := ExeDir + 'WPC.EXE';
  If Not FileExists(CompilerPath) Then CompilerPath := 'C:\WINDOWS\WPC.EXE';
  If Not FileExists(CompilerPath) Then CompilerPath := 'C:\WPC.EXE';
  If Not FileExists(CompilerPath) Then CompilerPath := ExeDir + 'WPC.EXE';
  GetDir(0, WorkDir);
  If (WorkDir <> '') And (WorkDir[Length(WorkDir)] <> '\') Then WorkDir := WorkDir + '\';
  WorkDir := UpStr(WorkDir);
  { CD-ROM (lecture seule) : C:\ pour les nouveaux fichiers }
  If Not CanWrite(WorkDir) Then
    If CanWrite('C:\') Then WorkDir := 'C:\';
  DlgDir := WorkDir;
  Inst := GetModuleHandleA(0);
  SysFont := GetStockObject(SYSTEM_FIXED_FONT);
  RegCls('PASDEV', LongInt(@MainProc), CS_DBLCLKS, 0, 0);
  RegCls('PDINPUT', LongInt(@InputProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  RegCls('PDOPEN', LongInt(@OpenProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  RegCls('PDWINLIST', LongInt(@WinListProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  RegCls('PDINFO', LongInt(@InfoProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  RegCls('PDCOMP', LongInt(@CompProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  RegCls('PDABOUT', LongInt(@AboutProc), 0, LoadCursorA(0, IDC_ARROW), 16);
  { memoire partagee de la progression de WPC (-PRG) }
  PrgMem := CreateFileMappingA(-1, 0, PAGE_READWRITE, 0, 4096, Z('WPC.PRG'));
  If PrgMem <> 0 Then PrgMem := MapViewOfFile(PrgMem, FILE_MAP_ALL_ACCESS, 0, 0, 0);
  CompFr := 0; CompCl := 0;
  Frame := CreateWindowExA(0, Z('PASDEV'), Z2('Pascal Developer'), WS_OVERLAPPEDWINDOW,
                           0, 0, GetSystemMetrics(0), GetSystemMetrics(1), 0, 0, Inst, 0);
  Client := Frame;
  BuildMenu;
  Dummy := ShowWindow(Frame, 3);
  Dummy := GetClientRect(Client, LongInt(@Qmsg));
  CW := Qmsg[2]; CH := Qmsg[3];
  { fichiers de la ligne de commande, sinon un document vide }
  For K := 1 To ParamCount Do
  Begin
    S := ParamStr(K);
    If OpenDoc(S, False) >= 0 Then ;
  End;
  If NZ = 0 Then If NewDoc >= 0 Then ;
  If Not FileExists(CompilerPath) Then
    StatusMsg := Acc('Attention : WPC.EXE introuvable (compilation impossible)');
  Dummy := UpdateWindow(Frame);
  Dummy := SetFocus(Client);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    { Entree, Echap et Tab des dialogues }
    If (Qmsg[1] = WM_KEYDOWN) And ((Qmsg[2] = 9) Or (Qmsg[2] = 13) Or (Qmsg[2] = 27)) Then
      If DlgKey(Qmsg[0], Qmsg[2]) Then Continue;
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
END.
