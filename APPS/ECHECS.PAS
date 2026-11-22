{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: ECHECS - jeu d'echecs contre l'ordinateur pour Pasdows 95
                (Win32), porte du jeu du Presentation Manager d'OS2-0.
}

Program ECHECS;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\ECHECS.PAS ECHECS.EXE

  Le jeu d'echecs d'OS2-0 (ECHECS.PAS, Presentation Manager) porte pour
  les API de Windows : menu Demarrer, Programmes, Accessoires, Jeux,
  Echecs. Les regles et le moteur sont inchanges : deplacements, prises,
  roque (petit et grand), prise en passant, promotion (en dame), echec,
  echec et mat, pat, regle des 50 coups et materiel insuffisant ;
  l'ordinateur joue les noirs (ou les blancs : Options, Jouer avec les
  noirs ; ou personne : Deux joueurs), recherche alpha-beta (negamax) a
  profondeur 1, 2 ou 3 selon le niveau, suivie d'une recherche des prises
  (quiescence) ; evaluation : materiel et position des pieces.

  Portage : WinCreateStdWindow, menus PM, GpiBox, GpiLine, WinDrawText
  et WinFillRect deviennent CreateWindowEx, CreateMenu, RoundRect,
  LineTo, TextOut et FillRect ; les coordonnees de PM (origine en bas a
  gauche) sont retournees (origine en haut a gauche) par FY ; le dessin
  se fait dans une image en memoire (sans scintillement).

  Souris : cliquer une piece (ses cases d'arrivee sont marquees), puis la
  case d'arrivee. Clavier : F2 nouvelle partie, Ctrl+Z annuler le dernier
  coup (et la reponse de l'ordinateur), F1 regles.
  Notation des coups (francaise) : R roi, D dame, T tour, F fou,
  C cavalier ; "Cg1-f3", "e5xd6", "O-O", "+" echec, "#" mat. }

Const
  WM_THINK = $0401;
  CLR_WHITE = $FFFFFF; CLR_BLACK = 0; CLR_BLUE = $FF0000; CLR_GREEN = $00C000; CLR_YELLOW = $40E0F0;
  CLR_DARKBLUE = $800000; CLR_DARKRED = $000080; CLR_DARKGREEN = $006000; CLR_PALEGRAY = $C0C0C0;
  CLR_LIGHTSQ = $99CCFF; CLR_DARKSQ = $3366CC; CLR_FRAME = $1F3F6F; CLR_GRAYEDGE = $A0A0A0;
  DRO_FILL = 1; DRO_OUTLINE = 2;
  CM_NEW = 101; CM_UNDO = 102; CM_QUIT = 103; CM_LEVEL1 = 201; CM_LEVEL2 = 202; CM_LEVEL3 = 203;
  CM_BLACK = 210; CM_TWO = 211; CM_RULES = 301; CM_ABOUT = 302;
  { pieces : 1 pion, 2 cavalier, 3 fou, 4 tour, 5 dame, 6 roi (noir < 0) }
  PAWN = 1; KNIGHT = 2; BISHOP = 3; ROOK = 4; QUEEN = 5; KING = 6;
  Sq = 44;                       { taille d'une case (pels) }
  MaxPly = 32;                   { profondeur de la recherche (avec les prises) }
  MaxHist = 600;                 { demi-coups de la partie }
  MaxMoves = 256;
  Inf = 1000000; MateVal = 100000;
  PieceVal : Array[0..6] Of LongInt = (0, 100, 320, 330, 500, 900, 0);
  { tables de position (pour les blancs, case a1 = 0) }
  PstPawn : Array[0..63] Of LongInt = (
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10,-20,-20, 10, 10,  5,
     5, -5,-10,  0,  0,-10, -5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5,  5, 10, 25, 25, 10,  5,  5,
    10, 10, 20, 30, 30, 20, 10, 10,
    50, 50, 50, 50, 50, 50, 50, 50,
     0,  0,  0,  0,  0,  0,  0,  0);
  PstKnight : Array[0..63] Of LongInt = (
   -50,-40,-30,-30,-30,-30,-40,-50,
   -40,-20,  0,  5,  5,  0,-20,-40,
   -30,  5, 10, 15, 15, 10,  5,-30,
   -30,  0, 15, 20, 20, 15,  0,-30,
   -30,  5, 15, 20, 20, 15,  5,-30,
   -30,  0, 10, 15, 15, 10,  0,-30,
   -40,-20,  0,  0,  0,  0,-20,-40,
   -50,-40,-30,-30,-30,-30,-40,-50);
  PstBishop : Array[0..63] Of LongInt = (
   -20,-10,-10,-10,-10,-10,-10,-20,
   -10,  5,  0,  0,  0,  0,  5,-10,
   -10, 10, 10, 10, 10, 10, 10,-10,
   -10,  0, 10, 10, 10, 10,  0,-10,
   -10,  5,  5, 10, 10,  5,  5,-10,
   -10,  0,  5, 10, 10,  5,  0,-10,
   -10,  0,  0,  0,  0,  0,  0,-10,
   -20,-10,-10,-10,-10,-10,-10,-20);
  PstKing : Array[0..63] Of LongInt = (
    20, 30, 10,  0,  0, 10, 30, 20,
    20, 20,  0,  0,  0,  0, 20, 20,
   -10,-20,-20,-20,-20,-20,-20,-10,
   -20,-30,-30,-40,-40,-30,-30,-20,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30,
   -30,-40,-40,-50,-50,-40,-40,-30);
  KnightD : Array[0..7] Of LongInt = (-17, -15, -10, -6, 6, 10, 15, 17);
  KnightF : Array[0..7] Of LongInt = (-1, 1, -2, 2, -2, 2, -1, 1);
  KingD : Array[0..7] Of LongInt = (-9, -8, -7, -1, 1, 7, 8, 9);
  KingF : Array[0..7] Of LongInt = (-1, 0, 1, -1, 1, -1, 0, 1);

Var
  CW, CH, MemDC, MemBmp, FontS, MOpts : LongInt;
  { position : Bd (a1 = 0, h8 = 63), trait (1 blancs, -1 noirs), roques
    (1 petit blanc, 2 grand blanc, 4 petit noir, 8 grand noir), case de
    prise en passant (-1), demi-coups sans prise ni pion }
  Bd : Array[0..63] Of LongInt;
  Side, Castle, EpSq, Fifty : LongInt;
  { pile de la recherche (copie de la position a chaque demi-coup) }
  SBd : Array[0..MaxPly * 64 - 1] Of LongInt;
  SSide, SCastle, SEp, SFifty : Array[0..MaxPly - 1] Of LongInt;
  Ply : LongInt;
  { coups generes : par niveau de la recherche }
  MvList : Array[0..MaxPly * MaxMoves - 1] Of LongInt;
  MvScore : Array[0..MaxPly * MaxMoves - 1] Of LongInt;
  LegL : Array[0..MaxMoves - 1] Of LongInt;      { coups legaux (LegalMoves) }
  { partie : positions et coups joues }
  HBd : Array[0..MaxHist * 64 - 1] Of Byte;          { piece + 8 }
  HSide, HCastle, HEp, HFifty, HMove : Array[0..MaxHist - 1] Of LongInt;
  HText : Array[0..MaxHist - 1] Of String[12];
  NHist : LongInt;
  Level, CompSide, TwoPlayers : LongInt;
  Sel : LongInt;                      { case choisie (-1) }
  LastFrom, LastTo : LongInt;
  Over : LongInt;                     { 0 en cours, 1 mat, 2 pat, 3 nulle }
  Thinking : LongInt;
  Nodes : LongInt;
  Status : String;
Const
  WM_CREATE = $0001; WM_DESTROY = $0002; WM_SIZE = $0005; WM_SETFOCUS = $0007;
  WM_PAINT = $000F; WM_CLOSE = $0010; WM_ERASEBKGND = $0014; WM_SETFONT = $0030;
  WM_KEYDOWN = $0100; WM_CHAR = $0102; WM_COMMAND = $0111; WM_TIMER = $0113;
  WM_HSCROLL = $0114; WM_VSCROLL = $0115;
  WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201; WM_LBUTTONUP = $0202;
  WM_LBUTTONDBLCLK = $0203; WM_RBUTTONDOWN = $0204; WM_USER = $0400;
  WS_POPUP = LongInt($80000000); WS_CHILD = $40000000; WS_VISIBLE = $10000000;
  WS_DISABLED = $08000000; WS_CLIPCHILDREN = $02000000; WS_CAPTION = $00C00000;
  WS_BORDER = $00800000; WS_VSCROLL = $00200000; WS_HSCROLL = $00100000;
  WS_SYSMENU = $00080000; WS_THICKFRAME = $00040000; WS_MINIMIZEBOX = $00020000;
  WS_MAXIMIZEBOX = $00010000; WS_TABSTOP = $00010000;
  WS_OVERLAPPEDWINDOW = $00CF0000; WS_EX_DLGMODALFRAME = 1;
  ES_AUTOHSCROLL = $0080; ES_MULTILINE = $0004; ES_AUTOVSCROLL = $0040;
  ES_READONLY = $0800; ES_WANTRETURN = $1000;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1; BS_AUTOCHECKBOX = 3;
  BM_GETCHECK = $00F0; BM_SETCHECK = $00F1;
  LBS_NOTIFY = 1; LB_ADDSTRING = $0180; LB_RESETCONTENT = $0184;
  LB_SETCURSEL = $0186; LB_GETCURSEL = $0188; LB_GETCOUNT = $018B;
  LBN_SELCHANGE = 1; LBN_DBLCLK = 2; EN_CHANGE = $0300;
  EM_SETSEL = $00B1; EM_REPLACESEL = $00C2;
  CS_DBLCLKS = 8; IDC_ARROW = 32512; IDC_WAIT = 32514;
  SM_CXSCREEN = 0; SM_CYSCREEN = 1;
  MF_STRING = 0; MF_GRAYED = 1; MF_POPUP = $10; MF_SEPARATOR = $800;
  MF_CHECKED = 8; MF_BYCOMMAND = 0;
  MB_OK = 0; MB_OKCANCEL = 1; MB_YESNO = 4; MB_ICONERROR = $10;
  MB_ICONQUESTION = $20; MB_ICONWARNING = $30; MB_ICONINFO = $40; IDYES = 6;
  VK_BACK = $08; VK_TAB = $09; VK_RETURN = $0D; VK_SHIFT = $10;
  VK_CONTROL = $11; VK_ESCAPE = $1B; VK_SPACE = $20; VK_PRIOR = $21;
  VK_NEXT = $22; VK_END = $23; VK_HOME = $24; VK_LEFT = $25; VK_UP = $26;
  VK_RIGHT = $27; VK_DOWN = $28; VK_DELETE = $2E; VK_F1 = $70; VK_F2 = $71;
  VK_F3 = $72;
  VK_F5 = $74;
  SRCCOPY = $00CC0020; OPAQUE = 2; TRANSPARENT = 1; OEM_CHARSET = 255;
  SB_LINEUP = 0; SB_LINEDOWN = 1; SB_PAGEUP = 2; SB_PAGEDOWN = 3;
  SB_THUMBPOSITION = 4; SB_THUMBTRACK = 5; SB_HORZ = 0; SB_VERT = 1;
  GENERIC_READ = LongInt($80000000); GENERIC_WRITE = $40000000;
  FILE_SHARE_READ = 1; CREATE_ALWAYS = 2; OPEN_EXISTING = 3;
  INVALID_HANDLE = -1; CF_TEXT = 1;
  ClrFace = $C0C0C0; ClrShadow = $808080; ClrHi = $FFFFFF; ClrDark = 0;
  ClrSel = $800000; ClrWin = $FFFFFF;

Type
  TWndCls = Record
    Style, Proc, ClsExtra, WndExtra, Inst, Icon, Cursor, Brush, MenuName, ClassName : LongInt;
  End;
  PByt = ^Byte;
  PLng = ^LongInt;

Var
  Inst, Wnd, Dummy, OemOut : LongInt;
  NameZ, NameZ2, TxtBuf : Array[0..1023] Of Byte;
  Qmsg : Array[0..7] Of LongInt;

Function GetModuleHandleA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetModuleHandleA';
Procedure ExitProcess(Code : LongInt); stdcall; external 'kernel32.dll' name 'ExitProcess';
Function GetTickCount : LongInt; stdcall; external 'kernel32.dll' name 'GetTickCount';
Procedure Sleep(Ms : LongInt); stdcall; external 'kernel32.dll' name 'Sleep';
Function CreateFileA(Name, Access, Share, Sec, Disp, Flags, Tmpl : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateFileA';
Function ReadFile(H, Buf, N, PRead, Ov : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'ReadFile';
Function WriteFile(H, Buf, N, PWritten, Ov : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'WriteFile';
Function SetFilePointer(H, Dist, PHigh, Method : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'SetFilePointer';
Function GetFileSize(H, PHigh : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetFileSize';
Function CloseHandle(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CloseHandle';
Function FindFirstFileA(Spec, Data : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindFirstFileA';
Function FindNextFileA(H, Data : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindNextFileA';
Function FindClose(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindClose';
Function GetLogicalDrives : LongInt; stdcall; external 'kernel32.dll' name 'GetLogicalDrives';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GlobalAlloc';
Function VirtualAlloc(A, N, T, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'VirtualAlloc';
Function VirtualFree(A, N, T : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'VirtualFree';
Function RegOpenKeyExA(K, Sub, Opt, Sam, PRes : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(K, Name, Res, PTyp, Data, PLen : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'RegCloseKey';

Function RegisterClassA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex, Cls, Title, Style, X, Y, W, H, Par, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function DestroyWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DestroyWindow';
Function ShowWindow(H, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ShowWindow';
Function UpdateWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'UpdateWindow';
Function MoveWindow(H, X, Y, W, Hh, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MoveWindow';
Function DefWindowProcA(H, Msg, WP, LP : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(P, H, F, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(Code : LongInt); stdcall; external 'user32.dll' name 'PostQuitMessage';
Function PostMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall; external 'user32.dll' name 'PostMessageA';
Function SendMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SendMessageA';
Function BeginPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'BeginPaint';
Function EndPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EndPaint';
Function GetDC(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetDC';
Function ReleaseDC(H, Dc : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ReleaseDC';
Function InvalidateRect(H, P, Erase : LongInt) : LongInt; stdcall; external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetClientRect';
Function AdjustWindowRectEx(P, Style, Menu, Ex : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'AdjustWindowRectEx';
Function SetWindowTextA(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetWindowTextA';
Function GetWindowTextA(H, P, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetWindowTextA';
Function SetFocus(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetFocus';
Function EnableWindow(H, On : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EnableWindow';
Function SetTimer(H, Id, Ms, Proc : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetTimer';
Function KillTimer(H, Id : LongInt) : LongInt; stdcall; external 'user32.dll' name 'KillTimer';
Function MessageBoxA(H, Text, Cap, Typ : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MessageBoxA';
Function MessageBeep(T : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MessageBeep';
Function CreateMenu : LongInt; stdcall; external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall; external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(M, Flags, Id, Text : LongInt) : LongInt; stdcall; external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetMenu';
Function DestroyMenu(M : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DestroyMenu';
Function CheckMenuItem(M, Id, Flags : LongInt) : LongInt; stdcall; external 'user32.dll' name 'CheckMenuItem';
Function TrackPopupMenu(M, Flags, X, Y, R, H, Rc : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'TrackPopupMenu';
Function ClientToScreen(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ClientToScreen';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetSystemMetrics';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'LoadCursorA';
Function SetCursor(C : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetCursor';
Function SetCapture(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall; external 'user32.dll' name 'ReleaseCapture';
Function GetKeyState(K : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetKeyState';
Function FillRect(Dc, P, Br : LongInt) : LongInt; stdcall; external 'user32.dll' name 'FillRect';
Function SetScrollRange(H, Bar, A, B, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetScrollRange';
Function SetScrollPos(H, Bar, P, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetScrollPos';
Function OpenClipboard(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'OpenClipboard';
Function EmptyClipboard : LongInt; stdcall; external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetClipboardData';
Function CloseClipboard : LongInt; stdcall; external 'user32.dll' name 'CloseClipboard';

Function CreateCompatibleDC(Dc : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreateCompatibleDC';
Function CreateCompatibleBitmap(Dc, W, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleBitmap';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(Style, W, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreatePen';
Function DeleteObject(H : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'DeleteObject';
Function GetStockObject(I : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'GetStockObject';
Function CreateFontA(H, W, Esc, Ori, Wt, It, Un, St, Cs, Op, Cp, Q, Pf, Face : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateFontA';
Function SelectObject(Dc, Obj : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SelectObject';
Function BitBlt(D, X, Y, W, H, S, XS, YS, Op : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'BitBlt';
Function TextOutA(Dc, X, Y, P, N : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'TextOutA';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetTextColor';
Function SetBkColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetBkColor';
Function SetBkMode(Dc, M : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetBkMode';
Function MoveToEx(Dc, X, Y, P : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'MoveToEx';
Function LineTo(Dc, X, Y : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'LineTo';
Function StretchDIBits(Dc, X, Y, W, H, SX, SY, SW, SH, Bits, Bmi, Use, Op : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'StretchDIBits';

{ ==================================================================== }
{ Utilitaires                                                           }
{ ==================================================================== }

Procedure PutZ(A : LongInt; S : String);
Var K : LongInt; P : PByt;
Begin
  For K := 1 To Length(S) Do
  Begin
    P := PByt(A + K - 1); P^ := Ord(S[K]);
  End;
  P := PByt(A + Length(S)); P^ := 0;
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

Function GetZ(A : LongInt) : String;
Var S : String; P : PByt;
Begin
  S := '';
  P := PByt(A);
  While (P^ <> 0) And (Length(S) < 255) Do
  Begin
    S := S + Chr(P^);
    P := PByt(LongInt(P) + 1);
  End;
  GetZ := S;
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function MinI(A, B : LongInt) : LongInt;
Begin
  If A < B Then MinI := A Else MinI := B;
End;

Function MaxI(A, B : LongInt) : LongInt;
Begin
  If A > B Then MaxI := A Else MaxI := B;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Function UpS(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do S[K] := UpCase(S[K]);
  UpS := S;
End;

Function TrimS(S : String) : String;
Begin
  While (S <> '') And (S[1] <= ' ') Do Delete(S, 1, 1);
  While (S <> '') And (S[Length(S)] <= ' ') Do Delete(S, Length(S), 1);
  TrimS := S;
End;

Function Two(V : LongInt) : String;
Begin
  Two := Chr(48 + (V Div 10) Mod 10) + Chr(48 + V Mod 10);
End;

{ ANSI (1252) -> page 437 de la police de l'ecran de Pasdows }
Const
  AnsiOem : Array[128..255] Of Byte = (
    69, 63, 44, 102, 34, 46, 197, 206, 94, 63, 83, 60, 79, 63, 90, 63, 63,
    39, 39, 34, 34, 249, 45, 45, 126, 159, 115, 62, 111, 63, 122, 89, 255,
    173, 155, 156, 63, 157, 124, 21, 34, 169, 166, 174, 170, 45, 158, 196,
    248, 241, 253, 51, 39, 230, 20, 250, 44, 49, 167, 175, 172, 171, 63, 168,
    65, 65, 65, 65, 142, 143, 146, 128, 69, 144, 69, 69, 73, 73, 73, 73, 68,
    165, 79, 79, 79, 79, 153, 120, 79, 85, 85, 85, 154, 89, 63, 225, 133,
    160, 131, 97, 132, 134, 145, 135, 138, 130, 136, 137, 141, 161, 140, 139,
    63, 164, 149, 162, 147, 111, 148, 246, 111, 151, 163, 150, 129, 121, 63,
    152);

{ texte ANSI du programme tel qu'il s'affiche : page 437 sous Pasdows 95
  (qui affiche les programmes de WPC avec la police de l'ecran), tel
  quel sous Windows }
Function Disp(S : String) : String;
Var K : LongInt;
Begin
  If OemOut <> 0 Then
    For K := 1 To Length(S) Do
      If Ord(S[K]) >= 128 Then S[K] := Chr(AnsiOem[Ord(S[K])]);
  Disp := S;
End;

{ inverse (texte lu dans un controle -> ANSI) }
Function UnDisp(S : String) : String;
Var K, C : LongInt;
Begin
  If OemOut <> 0 Then
    For K := 1 To Length(S) Do
      If Ord(S[K]) >= 128 Then
        For C := 160 To 255 Do
          If AnsiOem[C] = Ord(S[K]) Then
          Begin
            S[K] := Chr(C);
            Break;
          End;
  UnDisp := S;
End;

Procedure DetectOem;
Var K, T, N : LongInt; B : Array[0..63] Of Byte; S : String;
Begin
  OemOut := 0;
  K := 0;
  If RegOpenKeyExA(LongInt($80000002), Z('Software\Microsoft\Windows\CurrentVersion'), 0, $20019,
                   LongInt(@K)) <> 0 Then Exit;
  N := 63; T := 0; B[0] := 0;
  If RegQueryValueExA(K, Z('ProductName'), 0, LongInt(@T), LongInt(@B), LongInt(@N)) = 0 Then
  Begin
    B[63] := 0;
    S := ''; T := 0;
    While (T < 7) And (B[T] <> 0) Do Begin S := S + UpCase(Chr(B[T])); Inc(T); End;
    If S = 'PASDOWS' Then OemOut := 1;
  End;
  Dummy := RegCloseKey(K);
End;

Function Ask(Text, Cap : String; Fl : LongInt) : LongInt;
Begin
  Ask := MessageBoxA(Wnd, Z(Disp(Text)), Z2(Disp(Cap)), Fl);
End;

{ dessin : rectangle plein, texte, reliefs de Windows 95 }
Procedure Bar(Dc, X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; B : LongInt;
Begin
  If (X2 <= X1) Or (Y2 <= Y1) Then Exit;
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2; Rc[3] := Y2;
  B := CreateSolidBrush(C);
  Dummy := FillRect(Dc, LongInt(@Rc), B);
  Dummy := DeleteObject(B);
End;

Procedure Txt(Dc, X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(LongInt(@TxtBuf), Disp(S));
  Dummy := SetTextColor(Dc, Fg);
  Dummy := SetBkColor(Dc, Bg);
  Dummy := TextOutA(Dc, X, Y, LongInt(@TxtBuf), Length(S));
End;

{ cadre en relief (X2, Y2 exclus) : Up bouton, sinon creux }
Procedure Bevel(Dc, X1, Y1, X2, Y2 : LongInt; Up : Boolean);
Var L, D : LongInt;
Begin
  If Up Then Begin L := ClrHi; D := ClrDark; End Else Begin L := ClrShadow; D := ClrHi; End;
  Bar(Dc, X1, Y1, X2, Y1 + 1, L); Bar(Dc, X1, Y1, X1 + 1, Y2, L);
  Bar(Dc, X1, Y2 - 1, X2, Y2, D); Bar(Dc, X2 - 1, Y1, X2, Y2, D);
  If Up Then
  Begin
    Bar(Dc, X1 + 1, Y2 - 2, X2 - 1, Y2 - 1, ClrShadow);
    Bar(Dc, X2 - 2, Y1 + 1, X2 - 1, Y2 - 1, ClrShadow);
  End
  Else
  Begin
    Bar(Dc, X1 + 1, Y1 + 1, X2 - 1, Y1 + 2, ClrDark);
    Bar(Dc, X1 + 1, Y1 + 1, X1 + 2, Y2 - 1, ClrDark);
  End;
End;

Procedure RegClass(Name : String; Proc, Style : LongInt);
Var C : TWndCls;
Begin
  PutZ(LongInt(@NameZ2), Name);
  C.Style := Style; C.Proc := Proc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, IDC_ARROW); C.Brush := 0;
  C.MenuName := 0; C.ClassName := LongInt(@NameZ2);
  Dummy := RegisterClassA(LongInt(@C));
End;

{ controle enfant de P }
Function Ctl(P : LongInt; Cls, T : String; Style, X, Y, W, H, Id : LongInt) : LongInt;
Begin
  Ctl := CreateWindowExA(0, Z2(Cls), Z(Disp(T)), WS_CHILD Or WS_VISIBLE Or Style, X, Y, W, H, P, Id, Inst, 0);
End;

Function CtlText(H : LongInt) : String;
Begin
  TxtBuf[0] := 0;
  Dummy := GetWindowTextA(H, LongInt(@TxtBuf), 255);
  CtlText := UnDisp(GetZ(LongInt(@TxtBuf)));
End;

Procedure SetText(H : LongInt; S : String);
Begin
  Dummy := SetWindowTextA(H, Z(Disp(S)));
End;

{ menus : ~ (lettre soulignee) -> & ; Id 0 : separateur }
Procedure MItem(M, Id : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  If Id = 0 Then Dummy := AppendMenuA(M, MF_SEPARATOR, 0, 0)
  Else Dummy := AppendMenuA(M, MF_STRING, Id, Z(Disp(S)));
End;

Procedure MSub(Bar0, P : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  Dummy := AppendMenuA(Bar0, MF_POPUP, P, Z(Disp(S)));
End;

Procedure MCheck(M, Id : LongInt; On : Boolean);
Begin
  If On Then Dummy := CheckMenuItem(M, Id, MF_CHECKED) Else Dummy := CheckMenuItem(M, Id, 0);
End;

{ fenetre principale centree, zone client W x H }
Function MainWindow(Cls, Title : String; Style, W, H : LongInt; HasMenu : Boolean) : LongInt;
Var Rc : Array[0..3] Of LongInt; Fw, Fh : LongInt;
Begin
  Rc[0] := 0; Rc[1] := 0; Rc[2] := W; Rc[3] := H;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), Style, Ord(HasMenu), 0);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  PutZ(LongInt(@NameZ2), Cls);
  MainWindow := CreateWindowExA(0, LongInt(@NameZ2), Z(Disp(Title)), Style,
                                MaxI(0, (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2),
                                MaxI(0, (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2), Fw, Fh, 0, 0, Inst, 0);
End;

Procedure MsgLoop;
Begin
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
End;


{ ==================================================================== }
{ Dessin : coordonnees de PM (origine en bas a gauche) retournees       }
{ ==================================================================== }

Function RoundRect(Dc, X1, Y1, X2, Y2, W, H : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'RoundRect';

Function AbsI(A : LongInt) : LongInt;
Begin
  If A < 0 Then AbsI := -A Else AbsI := A;
End;

Function FY(Y : LongInt) : LongInt;
Begin
  FY := CH - 1 - Y;
End;

Procedure ShowMsg(Text, Cap : String);
Begin
  Dummy := Ask(Text, Cap, MB_OK Or MB_ICONINFO);
End;

{ rectangle (X1, Y1)-(X2, Y2) de PM, bornes comprises, plein ou contour,
  coins arrondis de diametre R }
Procedure GBox(Dc, X1, Y1, X2, Y2, C, Fl, R : LongInt);
Var Pen, Br, OP, OB, T : LongInt;
Begin
  If X1 > X2 Then Begin T := X1; X1 := X2; X2 := T; End;
  If Y1 > Y2 Then Begin T := Y1; Y1 := Y2; Y2 := T; End;
  Pen := CreatePen(0, 1, C);
  OP := SelectObject(Dc, Pen);
  If Fl = DRO_FILL Then Br := CreateSolidBrush(C) Else Br := GetStockObject(5);
  OB := SelectObject(Dc, Br);
  Dummy := RoundRect(Dc, X1, FY(Y2), X2 + 1, FY(Y1) + 1, R, R);
  Dummy := SelectObject(Dc, OB);
  Dummy := SelectObject(Dc, OP);
  Dummy := DeleteObject(Pen);
  If Fl = DRO_FILL Then Dummy := DeleteObject(Br);
End;

Procedure Shape(Dc, X1, Y1, X2, Y2, Fill, Edge, R : LongInt);
Begin
  GBox(Dc, X1, Y1, X2, Y2, Fill, DRO_FILL, R);
  GBox(Dc, X1, Y1, X2, Y2, Edge, DRO_OUTLINE, R);
End;

Procedure GLn(Dc, X1, Y1, X2, Y2, C : LongInt);
Var Pen, OP : LongInt;
Begin
  Pen := CreatePen(0, 1, C);
  OP := SelectObject(Dc, Pen);
  Dummy := MoveToEx(Dc, X1, FY(Y1), 0);
  Dummy := LineTo(Dc, X2, FY(Y2));
  Dummy := SelectObject(Dc, OP);
  Dummy := DeleteObject(Pen);
End;

{ texte dont le bas est en Y (PM) }
Procedure TextXY(Dc, X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  Txt(Dc, X, FY(Y) - 15, S, Fg, Bg);
End;

Procedure FillBox(Dc, X1, Y1, X2, Y2, C : LongInt);
Begin
  { (X1, Y1) bas gauche, (X2, Y2) haut droit exclus, comme WinFillRect }
  Bar(Dc, X1, FY(Y2) + 1, X2, FY(Y1) + 1, C);
End;

{ ==================================================================== }
{ coup : depart + arrivee * 64 + promotion * 4096 + drapeaux * 32768
  (1 prise en passant, 2 roque, 4 avance de deux cases) }

Function MvFrom(M : LongInt) : LongInt;
Begin
  MvFrom := M And 63;
End;

Function MvTo(M : LongInt) : LongInt;
Begin
  MvTo := (M Shr 6) And 63;
End;

Function MvPromo(M : LongInt) : LongInt;
Begin
  MvPromo := (M Shr 12) And 7;
End;

Function MvFlags(M : LongInt) : LongInt;
Begin
  MvFlags := (M Shr 15) And 7;
End;

Function Mk(F, T, P, Fl : LongInt) : LongInt;
Begin
  Mk := F + T * 64 + P * 4096 + Fl * 32768;
End;

{ la case Sq est-elle attaquee par le camp By (1 ou -1) ? }
Function Attacked(Sq, By : LongInt) : Boolean;
Var K, T, F, R, Df, Dr, P, Dir : LongInt;
Begin
  Attacked := True;
  F := Sq And 7; R := Sq Shr 3;
  { pions }
  If By = 1 Then
  Begin
    If (R > 0) And (F > 0) And (Bd[Sq - 9] = PAWN) Then Exit;
    If (R > 0) And (F < 7) And (Bd[Sq - 7] = PAWN) Then Exit;
  End
  Else
  Begin
    If (R < 7) And (F > 0) And (Bd[Sq + 7] = -PAWN) Then Exit;
    If (R < 7) And (F < 7) And (Bd[Sq + 9] = -PAWN) Then Exit;
  End;
  { cavaliers et roi }
  For K := 0 To 7 Do
  Begin
    T := Sq + KnightD[K];
    If (T >= 0) And (T < 64) And (AbsI((T And 7) - F) <= 2) And (Bd[T] = By * KNIGHT) Then Exit;
    T := Sq + KingD[K];
    If (T >= 0) And (T < 64) And (AbsI((T And 7) - F) <= 1) And (Bd[T] = By * KING) Then Exit;
  End;
  { lignes et diagonales }
  For Dir := 0 To 7 Do
  Begin
    Case Dir Of
      0 : Begin Df := 1; Dr := 0; End;
      1 : Begin Df := -1; Dr := 0; End;
      2 : Begin Df := 0; Dr := 1; End;
      3 : Begin Df := 0; Dr := -1; End;
      4 : Begin Df := 1; Dr := 1; End;
      5 : Begin Df := -1; Dr := 1; End;
      6 : Begin Df := 1; Dr := -1; End;
    Else
      Begin Df := -1; Dr := -1; End;
    End;
    T := F + Df; P := R + Dr;
    While (T >= 0) And (T < 8) And (P >= 0) And (P < 8) Do
    Begin
      K := Bd[P * 8 + T];
      If K <> 0 Then
      Begin
        If K = By * QUEEN Then Exit;
        If (Dir < 4) And (K = By * ROOK) Then Exit;
        If (Dir >= 4) And (K = By * BISHOP) Then Exit;
        T := 99;
      End
      Else
      Begin
        T := T + Df; P := P + Dr;
      End;
    End;
  End;
  Attacked := False;
End;

Function KingSq(S : LongInt) : LongInt;
Var K, R : LongInt;
Begin
  R := -1;
  For K := 0 To 63 Do
    If Bd[K] = S * KING Then R := K;
  KingSq := R;
End;

Function InCheck(S : LongInt) : Boolean;
Var K : LongInt;
Begin
  K := KingSq(S);
  InCheck := (K >= 0) And Attacked(K, -S);
End;

{ coups pseudo-legaux du camp au trait, a partir de Base dans MvList ;
  Caps : prises (et promotions) seulement ; rend le nombre }
Var GN, GBase : LongInt; GCaps : Boolean;

Procedure Add(Fr, To_, Pr, Fl : LongInt);
Begin
  If GN < MaxMoves Then
  Begin
    MvList[GBase + GN] := Mk(Fr, To_, Pr, Fl);
    Inc(GN);
  End;
End;

Procedure AddPawn(Fr, To_, Fl : LongInt);
Begin
  If ((To_ Shr 3) = 7) Or ((To_ Shr 3) = 0) Then
  Begin
    Add(Fr, To_, QUEEN, Fl);
    If Not GCaps Then
    Begin
      Add(Fr, To_, KNIGHT, Fl); Add(Fr, To_, ROOK, Fl); Add(Fr, To_, BISHOP, Fl);
    End;
  End
  Else Add(Fr, To_, 0, Fl);
End;

Function GenMoves(Base : LongInt; Caps : Boolean) : LongInt;
Var Sq, P, A, F, R, T, K, Df, Dr, Tf, Tr, Dir, Fwd, Start, Last : LongInt;
Begin
  GN := 0; GBase := Base; GCaps := Caps;
  For Sq := 0 To 63 Do
  Begin
    P := Bd[Sq];
    If P * Side <= 0 Then Continue;
    A := AbsI(P); F := Sq And 7; R := Sq Shr 3;
    Case A Of
      PAWN :
        Begin
          Fwd := Side * 8;
          If Side = 1 Then
          Begin
            Start := 1; Last := 6;
          End
          Else
          Begin
            Start := 6; Last := 1;
          End;
          T := Sq + Fwd;
          If (T >= 0) And (T < 64) And (Bd[T] = 0) Then
          Begin
            If (Not Caps) Or (R = Last) Then AddPawn(Sq, T, 0);
            If (Not Caps) And (R = Start) And (Bd[T + Fwd] = 0) Then Add(Sq, T + Fwd, 0, 4);
          End;
          For K := 0 To 1 Do
          Begin
            If K = 0 Then Df := -1 Else Df := 1;
            If (F + Df >= 0) And (F + Df < 8) Then
            Begin
              T := Sq + Fwd + Df;
              If (T >= 0) And (T < 64) Then
              Begin
                If Bd[T] * Side < 0 Then AddPawn(Sq, T, 0)
                Else If T = EpSq Then Add(Sq, T, 0, 1);
              End;
            End;
          End;
        End;
      KNIGHT, KING :
        For K := 0 To 7 Do
        Begin
          If A = KNIGHT Then
          Begin
            T := Sq + KnightD[K]; Df := 2;
          End
          Else
          Begin
            T := Sq + KingD[K]; Df := 1;
          End;
          If (T >= 0) And (T < 64) And (AbsI((T And 7) - F) <= Df) Then
            If Bd[T] * Side <= 0 Then
              If (Bd[T] <> 0) Or Not Caps Then Add(Sq, T, 0, 0);
        End;
    Else
      For Dir := 0 To 7 Do
      Begin
        If (A = ROOK) And (Dir >= 4) Then Continue;
        If (A = BISHOP) And (Dir < 4) Then Continue;
        Case Dir Of
          0 : Begin Df := 1; Dr := 0; End;
          1 : Begin Df := -1; Dr := 0; End;
          2 : Begin Df := 0; Dr := 1; End;
          3 : Begin Df := 0; Dr := -1; End;
          4 : Begin Df := 1; Dr := 1; End;
          5 : Begin Df := -1; Dr := 1; End;
          6 : Begin Df := 1; Dr := -1; End;
        Else
          Begin Df := -1; Dr := -1; End;
        End;
        Tf := F + Df; Tr := R + Dr;
        While (Tf >= 0) And (Tf < 8) And (Tr >= 0) And (Tr < 8) Do
        Begin
          T := Tr * 8 + Tf;
          If Bd[T] = 0 Then
          Begin
            If Not Caps Then Add(Sq, T, 0, 0);
          End
          Else
          Begin
            If Bd[T] * Side < 0 Then Add(Sq, T, 0, 0);
            Tf := 99;
          End;
          Tf := Tf + Df; Tr := Tr + Dr;
        End;
      End;
    End;
  End;
  { roques (le roi n'est pas en echec et ne traverse pas une case attaquee) }
  If Not Caps Then
  Begin
    If Side = 1 Then
    Begin
      If ((Castle And 1) <> 0) And (Bd[5] = 0) And (Bd[6] = 0) And (Bd[4] = KING) And (Bd[7] = ROOK) Then
        If Not Attacked(4, -1) And Not Attacked(5, -1) And Not Attacked(6, -1) Then Add(4, 6, 0, 2);
      If ((Castle And 2) <> 0) And (Bd[3] = 0) And (Bd[2] = 0) And (Bd[1] = 0) And (Bd[4] = KING) And (Bd[0] = ROOK) Then
        If Not Attacked(4, -1) And Not Attacked(3, -1) And Not Attacked(2, -1) Then Add(4, 2, 0, 2);
    End
    Else
    Begin
      If ((Castle And 4) <> 0) And (Bd[61] = 0) And (Bd[62] = 0) And (Bd[60] = -KING) And (Bd[63] = -ROOK) Then
        If Not Attacked(60, 1) And Not Attacked(61, 1) And Not Attacked(62, 1) Then Add(60, 62, 0, 2);
      If ((Castle And 8) <> 0) And (Bd[59] = 0) And (Bd[58] = 0) And (Bd[57] = 0) And (Bd[60] = -KING) And
         (Bd[56] = -ROOK) Then
        If Not Attacked(60, 1) And Not Attacked(59, 1) And Not Attacked(58, 1) Then Add(60, 58, 0, 2);
    End;
  End;
  GenMoves := GN;
End;

{ sauvegarde et restauration de la position (pile de la recherche) }
Procedure PushPos;
Var K : LongInt;
Begin
  For K := 0 To 63 Do SBd[Ply * 64 + K] := Bd[K];
  SSide[Ply] := Side; SCastle[Ply] := Castle; SEp[Ply] := EpSq; SFifty[Ply] := Fifty;
  Inc(Ply);
End;

Procedure PopPos;
Var K : LongInt;
Begin
  Dec(Ply);
  For K := 0 To 63 Do Bd[K] := SBd[Ply * 64 + K];
  Side := SSide[Ply]; Castle := SCastle[Ply]; EpSq := SEp[Ply]; Fifty := SFifty[Ply];
End;

{ jouer le coup M (sans verifier) }
Procedure DoMove(M : LongInt);
Var F, T, P, Pr, Fl : LongInt;
Begin
  F := MvFrom(M); T := MvTo(M); Pr := MvPromo(M); Fl := MvFlags(M);
  P := Bd[F];
  If (AbsI(P) = PAWN) Or (Bd[T] <> 0) Then Fifty := 0 Else Inc(Fifty);
  Bd[T] := P; Bd[F] := 0;
  If (Fl And 1) <> 0 Then Bd[T - Side * 8] := 0;           { prise en passant }
  If Pr <> 0 Then Bd[T] := Side * Pr;
  If (Fl And 2) <> 0 Then
  Begin
    { roque : la tour suit }
    Case T Of
      6 : Begin Bd[5] := Bd[7]; Bd[7] := 0; End;
      2 : Begin Bd[3] := Bd[0]; Bd[0] := 0; End;
      62 : Begin Bd[61] := Bd[63]; Bd[63] := 0; End;
      58 : Begin Bd[59] := Bd[56]; Bd[56] := 0; End;
    End;
  End;
  If (Fl And 4) <> 0 Then EpSq := (F + T) Div 2 Else EpSq := -1;
  { droits de roque }
  If (F = 4) Or (T = 4) Then Castle := Castle And Not 3;
  If (F = 60) Or (T = 60) Then Castle := Castle And Not 12;
  If (F = 7) Or (T = 7) Then Castle := Castle And Not 1;
  If (F = 0) Or (T = 0) Then Castle := Castle And Not 2;
  If (F = 63) Or (T = 63) Then Castle := Castle And Not 4;
  If (F = 56) Or (T = 56) Then Castle := Castle And Not 8;
  Side := -Side;
End;

{ coup legal (le roi du camp qui joue n'est pas en echec ensuite) }
Function MakeLegal(M : LongInt) : Boolean;
Begin
  PushPos;
  DoMove(M);
  If InCheck(-Side) Then
  Begin
    PopPos;
    MakeLegal := False;
  End
  Else MakeLegal := True;
End;

{ coups legaux dans L (rend le nombre) }
Function LegalMoves : LongInt;
Var N, K, C, Base : LongInt;
Begin
  Base := Ply * MaxMoves;
  N := GenMoves(Base, False);
  C := 0;
  For K := 0 To N - 1 Do
    If MakeLegal(MvList[Base + K]) Then
    Begin
      PopPos;
      LegL[C] := MvList[Base + K];
      Inc(C);
    End;
  LegalMoves := C;
End;

{ materiel insuffisant (roi seul, ou roi et une piece mineure) }
Function Insufficient : Boolean;
Var K, Minor, Other : LongInt;
Begin
  Minor := 0; Other := 0;
  For K := 0 To 63 Do
    Case AbsI(Bd[K]) Of
      KNIGHT, BISHOP : Inc(Minor);
      PAWN, ROOK, QUEEN : Inc(Other);
    End;
  Insufficient := (Other = 0) And (Minor <= 1);
End;

{ ==================================================================== }
{ Recherche                                                             }
{ ==================================================================== }

Function Evaluate : LongInt;
Var K, P, A, S, V : LongInt;
Begin
  V := 0;
  For K := 0 To 63 Do
  Begin
    P := Bd[K];
    If P <> 0 Then
    Begin
      A := AbsI(P);
      If P > 0 Then S := K Else S := (7 - (K Shr 3)) * 8 + (K And 7);
      Case A Of
        PAWN : S := PieceVal[A] + PstPawn[S];
        KNIGHT : S := PieceVal[A] + PstKnight[S];
        BISHOP : S := PieceVal[A] + PstBishop[S];
        KING : S := PstKing[S];
      Else
        S := PieceVal[A];
      End;
      If P > 0 Then V := V + S Else V := V - S;
    End;
  End;
  Evaluate := V * Side;
End;

{ ordre : prises (victime chere, attaquant bon marche) puis promotions }
Procedure OrderMoves(Base, N : LongInt);
Var K, J, M, S, T : LongInt;
Begin
  For K := 0 To N - 1 Do
  Begin
    M := MvList[Base + K];
    S := 0;
    If Bd[MvTo(M)] <> 0 Then S := 10 * PieceVal[AbsI(Bd[MvTo(M)])] - PieceVal[AbsI(Bd[MvFrom(M)])] + 1000;
    If MvPromo(M) = QUEEN Then S := S + 800;
    MvScore[Base + K] := S;
  End;
  For K := 1 To N - 1 Do
  Begin
    M := MvList[Base + K]; S := MvScore[Base + K]; J := K - 1;
    While (J >= 0) And (MvScore[Base + J] < S) Do
    Begin
      MvList[Base + J + 1] := MvList[Base + J]; MvScore[Base + J + 1] := MvScore[Base + J];
      Dec(J);
    End;
    MvList[Base + J + 1] := M; MvScore[Base + J + 1] := S;
  End;
  T := 0;
End;

Function Quiesce(Alpha, Beta : LongInt) : LongInt;
Var Stand, N, K, Base, V : LongInt;
Begin
  Inc(Nodes);
  Stand := Evaluate;
  If (Stand >= Beta) Or (Ply >= MaxPly - 2) Then
  Begin
    Quiesce := Stand;
    Exit;
  End;
  If Stand > Alpha Then Alpha := Stand;
  Base := Ply * MaxMoves;
  N := GenMoves(Base, True);
  OrderMoves(Base, N);
  For K := 0 To N - 1 Do
    If MakeLegal(MvList[Base + K]) Then
    Begin
      V := -Quiesce(-Beta, -Alpha);
      PopPos;
      If V >= Beta Then
      Begin
        Quiesce := V;
        Exit;
      End;
      If V > Alpha Then Alpha := V;
    End;
  Quiesce := Alpha;
End;

Function Search(Depth, Alpha, Beta : LongInt) : LongInt;
Var N, K, Base, V, Legal : LongInt;
Begin
  If Depth <= 0 Then
  Begin
    Search := Quiesce(Alpha, Beta);
    Exit;
  End;
  Inc(Nodes);
  Base := Ply * MaxMoves;
  N := GenMoves(Base, False);
  OrderMoves(Base, N);
  Legal := 0;
  For K := 0 To N - 1 Do
    If MakeLegal(MvList[Base + K]) Then
    Begin
      Inc(Legal);
      V := -Search(Depth - 1, -Beta, -Alpha);
      PopPos;
      If V >= Beta Then
      Begin
        Search := V;
        Exit;
      End;
      If V > Alpha Then Alpha := V;
    End;
  If Legal = 0 Then
  Begin
    If InCheck(Side) Then Search := -MateVal + Ply Else Search := 0;
    Exit;
  End;
  Search := Alpha;
End;

{ meilleur coup du camp au trait (profondeur D) }
Function BestMove(D : LongInt) : LongInt;
Var N, K, Base, V, Best, BestV, Alpha : LongInt;
Begin
  Nodes := 0;
  Base := Ply * MaxMoves;
  N := GenMoves(Base, False);
  OrderMoves(Base, N);
  Best := 0; BestV := -Inf; Alpha := -Inf;
  For K := 0 To N - 1 Do
    If MakeLegal(MvList[Base + K]) Then
    Begin
      V := -Search(D - 1, -Inf, -Alpha);
      PopPos;
      If (V > BestV) Or (Best = 0) Then
      Begin
        BestV := V; Best := MvList[Base + K];
      End;
      If V > Alpha Then Alpha := V;
    End;
  BestMove := Best;
End;

{ ==================================================================== }
{ Partie                                                                }
{ ==================================================================== }

Function PieceLetter(A : LongInt) : String;
Begin
  Case A Of
    KNIGHT : PieceLetter := 'C';
    BISHOP : PieceLetter := 'F';
    ROOK : PieceLetter := 'T';
    QUEEN : PieceLetter := 'D';
    KING : PieceLetter := 'R';
  Else
    PieceLetter := '';
  End;
End;

Function SqName(S : LongInt) : String;
Begin
  SqName := Chr(97 + (S And 7)) + Chr(49 + (S Shr 3));
End;

{ notation du coup M (position avant le coup) }
Function MoveText(M : LongInt) : String;
Var S : String; F, T, P : LongInt;
Begin
  F := MvFrom(M); T := MvTo(M); P := AbsI(Bd[F]);
  If (MvFlags(M) And 2) <> 0 Then
  Begin
    If (T And 7) = 6 Then S := 'O-O' Else S := 'O-O-O';
  End
  Else
  Begin
    S := PieceLetter(P) + SqName(F);
    If (Bd[T] <> 0) Or ((MvFlags(M) And 1) <> 0) Then S := S + 'x' Else S := S + '-';
    S := S + SqName(T);
    If MvPromo(M) <> 0 Then S := S + '=' + PieceLetter(MvPromo(M));
  End;
  MoveText := S;
End;

Procedure SaveHist(M : LongInt; T : String);
Var K : LongInt;
Begin
  If NHist >= MaxHist Then Exit;
  For K := 0 To 63 Do HBd[NHist * 64 + K] := Bd[K] + 8;
  HSide[NHist] := Side; HCastle[NHist] := Castle; HEp[NHist] := EpSq; HFifty[NHist] := Fifty;
  HMove[NHist] := M; HText[NHist] := T;
  Inc(NHist);
End;

Procedure UpdateStatus;
Var N : LongInt; Who : String;
Begin
  N := LegalMoves;
  If Side = 1 Then Who := 'blancs' Else Who := 'noirs';
  Over := 0;
  If N = 0 Then
  Begin
    If InCheck(Side) Then
    Begin
      Over := 1;
      If Side = 1 Then Status := #201'chec et mat : les noirs gagnent.' Else Status := #201'chec et mat : les blancs gagnent.';
      If NHist > 0 Then HText[NHist - 1] := HText[NHist - 1] + '#';
    End
    Else
    Begin
      Over := 2;
      Status := 'Pat : partie nulle.';
    End;
  End
  Else If Fifty >= 100 Then
  Begin
    Over := 3; Status := 'Nulle (50 coups sans prise ni pion).';
  End
  Else If Insufficient Then
  Begin
    Over := 3; Status := 'Nulle (mat'#233'riel insuffisant).';
  End
  Else If InCheck(Side) Then
  Begin
    Status := #201'chec ! Aux ' + Who + ' de jouer.';
    If NHist > 0 Then HText[NHist - 1] := HText[NHist - 1] + '+';
  End
  Else Status := 'Aux ' + Who + ' de jouer.';
End;

Procedure PlayMove(M : LongInt);
Var T : String;
Begin
  T := MoveText(M);
  SaveHist(M, T);
  DoMove(M);
  LastFrom := MvFrom(M); LastTo := MvTo(M);
  Sel := -1;
  UpdateStatus;
  Dummy := InvalidateRect(Wnd, 0, 0);
  If Over <> 0 Then ShowMsg(Status, #201'checs')
  Else If (TwoPlayers = 0) And (Side = CompSide) Then
  Begin
    Thinking := 1;
    Status := 'L''ordinateur r'#233'fl'#233'chit...';
    Dummy := PostMessageA(Wnd, WM_THINK, 0, 0);
  End;
End;

Procedure NewGame;
Const Back : Array[0..7] Of LongInt = (ROOK, KNIGHT, BISHOP, QUEEN, KING, BISHOP, KNIGHT, ROOK);
Var K : LongInt;
Begin
  For K := 0 To 63 Do Bd[K] := 0;
  For K := 0 To 7 Do
  Begin
    Bd[K] := Back[K]; Bd[8 + K] := PAWN;
    Bd[48 + K] := -PAWN; Bd[56 + K] := -Back[K];
  End;
  Side := 1; Castle := 15; EpSq := -1; Fifty := 0; Ply := 0;
  NHist := 0; Sel := -1; LastFrom := -1; LastTo := -1; Thinking := 0;
  UpdateStatus;
  Dummy := InvalidateRect(Wnd, 0, 0);
  If (TwoPlayers = 0) And (CompSide = 1) Then
  Begin
    Thinking := 1;
    Status := 'L''ordinateur r'#233'fl'#233'chit...';
    Dummy := PostMessageA(Wnd, WM_THINK, 0, 0);
  End;
End;

Procedure ComputerMove;
Var M : LongInt;
Begin
  Thinking := 0;
  If (Over <> 0) Or (Side <> CompSide) Or (TwoPlayers <> 0) Then Exit;
  Ply := 0;
  M := BestMove(Level);
  If M <> 0 Then PlayMove(M) Else UpdateStatus;
  Dummy := InvalidateRect(Wnd, 0, 0);
End;

Procedure UndoMove;
Var N, K : LongInt;
Begin
  If (NHist = 0) Or (Thinking <> 0) Then Exit;
  { le coup du joueur (et la reponse de l'ordinateur) }
  If (TwoPlayers = 0) And (Side <> CompSide) And (NHist >= 2) Then N := 2 Else N := 1;
  If (TwoPlayers = 0) And (Side <> CompSide) And (NHist = 1) Then Exit;
  NHist := NHist - N;
  For K := 0 To 63 Do Bd[K] := LongInt(HBd[NHist * 64 + K]) - 8;
  Side := HSide[NHist]; Castle := HCastle[NHist]; EpSq := HEp[NHist]; Fifty := HFifty[NHist];
  If NHist > 0 Then
  Begin
    LastFrom := MvFrom(HMove[NHist - 1]); LastTo := MvTo(HMove[NHist - 1]);
  End
  Else
  Begin
    LastFrom := -1; LastTo := -1;
  End;
  Sel := -1;
  UpdateStatus;
  Dummy := InvalidateRect(Wnd, 0, 0);
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }
Procedure BoardOrigin(Var X0, Y0 : LongInt);
Begin
  X0 := 24; Y0 := (CH - 8 * Sq) Div 2 + 4;
End;

{ case -> coin bas gauche (l'echiquier se retourne quand l'ordinateur a
  les blancs) }
Procedure SqXY(S : LongInt; Var X, Y : LongInt);
Var X0, Y0, F, R : LongInt;
Begin
  BoardOrigin(X0, Y0);
  F := S And 7; R := S Shr 3;
  If (CompSide = 1) And (TwoPlayers = 0) Then
  Begin
    F := 7 - F; R := 7 - R;
  End;
  X := X0 + F * Sq; Y := Y0 + R * Sq;
End;

Function SqAt(X, Y : LongInt) : LongInt;
Var X0, Y0, F, R : LongInt;
Begin
  BoardOrigin(X0, Y0);
  SqAt := -1;
  If (X < X0) Or (Y < Y0) Or (X >= X0 + 8 * Sq) Or (Y >= Y0 + 8 * Sq) Then Exit;
  F := (X - X0) Div Sq; R := (Y - Y0) Div Sq;
  If (CompSide = 1) And (TwoPlayers = 0) Then
  Begin
    F := 7 - F; R := 7 - R;
  End;
  SqAt := R * 8 + F;
End;

{ piece P dans la case de coin bas gauche (X, Y) : dessins vectoriels }
Procedure DrawPiece(Dc, X, Y, P : LongInt);
Var A, Fill, Edge, Cx : LongInt;
Begin
  A := AbsI(P);
  If P > 0 Then
  Begin
    Fill := CLR_WHITE; Edge := CLR_BLACK;
  End
  Else
  Begin
    Fill := CLR_BLACK; Edge := CLR_PALEGRAY;
  End;
  Cx := X + Sq Div 2;
  { socle }
  Shape(Dc, Cx - 14, Y + 5, Cx + 14, Y + 10, Fill, Edge, 4);
  Case A Of
    PAWN :
      Begin
        Shape(Dc, Cx - 8, Y + 10, Cx + 8, Y + 22, Fill, Edge, 6);
        Shape(Dc, Cx - 7, Y + 21, Cx + 7, Y + 35, Fill, Edge, 14);
      End;
    ROOK :
      Begin
        Shape(Dc, Cx - 9, Y + 10, Cx + 9, Y + 30, Fill, Edge, 0);
        Shape(Dc, Cx - 12, Y + 30, Cx + 12, Y + 35, Fill, Edge, 0);
        Shape(Dc, Cx - 12, Y + 35, Cx - 7, Y + 40, Fill, Edge, 0);
        Shape(Dc, Cx - 2, Y + 35, Cx + 2, Y + 40, Fill, Edge, 0);
        Shape(Dc, Cx + 7, Y + 35, Cx + 12, Y + 40, Fill, Edge, 0);
      End;
    KNIGHT :
      Begin
        Shape(Dc, Cx - 7, Y + 10, Cx + 9, Y + 28, Fill, Edge, 6);
        Shape(Dc, Cx - 13, Y + 24, Cx + 7, Y + 36, Fill, Edge, 8);
        Shape(Dc, Cx + 1, Y + 34, Cx + 7, Y + 41, Fill, Edge, 0);
        GBox(Dc, Cx - 3, Y + 30, Cx - 1, Y + 32, Edge, DRO_FILL, 0);
        GLn(Dc, Cx + 9, Y + 30, Cx + 9, Y + 14, Edge);
      End;
    BISHOP :
      Begin
        Shape(Dc, Cx - 9, Y + 10, Cx + 9, Y + 15, Fill, Edge, 0);
        Shape(Dc, Cx - 8, Y + 14, Cx + 8, Y + 36, Fill, Edge, 16);
        Shape(Dc, Cx - 3, Y + 35, Cx + 3, Y + 41, Fill, Edge, 6);
        GLn(Dc, Cx - 3, Y + 28, Cx + 4, Y + 22, Edge);
      End;
    QUEEN :
      Begin
        Shape(Dc, Cx - 10, Y + 10, Cx + 10, Y + 16, Fill, Edge, 0);
        Shape(Dc, Cx - 8, Y + 15, Cx + 8, Y + 30, Fill, Edge, 0);
        Shape(Dc, Cx - 13, Y + 28, Cx + 13, Y + 33, Fill, Edge, 0);
        Shape(Dc, Cx - 14, Y + 33, Cx - 9, Y + 38, Fill, Edge, 5);
        Shape(Dc, Cx - 7, Y + 33, Cx - 2, Y + 41, Fill, Edge, 5);
        Shape(Dc, Cx + 2, Y + 33, Cx + 7, Y + 41, Fill, Edge, 5);
        Shape(Dc, Cx + 9, Y + 33, Cx + 14, Y + 38, Fill, Edge, 5);
      End;
    KING :
      Begin
        Shape(Dc, Cx - 10, Y + 10, Cx + 10, Y + 16, Fill, Edge, 0);
        Shape(Dc, Cx - 8, Y + 15, Cx + 8, Y + 31, Fill, Edge, 0);
        Shape(Dc, Cx - 11, Y + 29, Cx + 11, Y + 34, Fill, Edge, 0);
        Shape(Dc, Cx - 2, Y + 33, Cx + 2, Y + 43, Fill, Edge, 0);
        Shape(Dc, Cx - 6, Y + 36, Cx + 6, Y + 40, Fill, Edge, 0);
      End;
  End;
End;

Procedure DrawAll(Dc : LongInt);
Var S, X, Y, X0, Y0, K, N, Base, C, Row : LongInt; T : String;
Begin
  Bar(Dc, 0, 0, CW, CH, CLR_PALEGRAY);
  BoardOrigin(X0, Y0);
  Shape(Dc, X0 - 5, Y0 - 5, X0 + 8 * Sq + 4, Y0 + 8 * Sq + 4, CLR_FRAME, CLR_BLACK, 0);
  { coups possibles de la piece choisie }
  N := 0;
  If Sel >= 0 Then N := LegalMoves;
  For S := 0 To 63 Do
  Begin
    SqXY(S, X, Y);
    If Odd((S And 7) + (S Shr 3)) Then C := CLR_LIGHTSQ Else C := CLR_DARKSQ;
    If S = Sel Then C := CLR_YELLOW;
    FillBox(Dc, X, Y, X + Sq, Y + Sq, C);
    If (S = LastFrom) Or (S = LastTo) Then
    Begin
      GBox(Dc, X + 1, Y + 1, X + Sq - 2, Y + Sq - 2, CLR_BLUE, DRO_OUTLINE, 0);
      GBox(Dc, X + 2, Y + 2, X + Sq - 3, Y + Sq - 3, CLR_BLUE, DRO_OUTLINE, 0);
    End;
    If Bd[S] <> 0 Then DrawPiece(Dc, X, Y, Bd[S]);
  End;
  For K := 0 To N - 1 Do
    If MvFrom(LegL[K]) = Sel Then
    Begin
      SqXY(MvTo(LegL[K]), X, Y);
      Shape(Dc, X + Sq Div 2 - 5, Y + Sq Div 2 - 5, X + Sq Div 2 + 5, Y + Sq Div 2 + 5, CLR_GREEN, CLR_DARKGREEN,
            10);
    End;
  { coordonnees }
  For K := 0 To 7 Do
  Begin
    SqXY(K, X, Y);
    TextXY(Dc, X + Sq Div 2 - 4, Y0 - 24, Chr(97 + K), CLR_BLACK, CLR_PALEGRAY);
    SqXY(K * 8, X, Y);
    TextXY(Dc, X0 - 18, Y + Sq Div 2 - 8, Chr(49 + K), CLR_BLACK, CLR_PALEGRAY);
  End;
  { panneau : etat et coups joues }
  X := X0 + 8 * Sq + 20;
  TextXY(Dc, X, CH - 26, #201'checs', CLR_DARKBLUE, CLR_PALEGRAY);
  If TwoPlayers <> 0 Then T := 'Deux joueurs'
  Else
  Begin
    Case Level Of
      1 : T := 'Niveau : facile';
      2 : T := 'Niveau : moyen';
    Else
      T := 'Niveau : difficile';
    End;
  End;
  TextXY(Dc, X, CH - 44, T, CLR_BLACK, CLR_PALEGRAY);
  { etat sur deux lignes au besoin }
  T := Status;
  If Length(T) > 26 Then
  Begin
    K := 26;
    While (K > 1) And (T[K] <> ' ') Do Dec(K);
    TextXY(Dc, X, CH - 68, Copy(T, 1, K - 1), CLR_DARKRED, CLR_PALEGRAY);
    TextXY(Dc, X, CH - 84, Copy(T, K + 1, 255), CLR_DARKRED, CLR_PALEGRAY);
  End
  Else TextXY(Dc, X, CH - 68, T, CLR_DARKRED, CLR_PALEGRAY);
  TextXY(Dc, X, CH - 110, 'Coups :', CLR_DARKBLUE, CLR_PALEGRAY);
  Base := MaxI(0, ((NHist + 1) Div 2) - (CH - 140) Div 16);
  Row := 0;
  K := Base * 2;
  While K < NHist Do
  Begin
    T := IStr(K Div 2 + 1) + '. ' + HText[K];
    If K + 1 < NHist Then
    Begin
      While Length(T) < 15 Do T := T + ' ';
      T := T + HText[K + 1];
    End;
    TextXY(Dc, X, CH - 128 - Row * 16, T, CLR_BLACK, CLR_PALEGRAY);
    Inc(Row);
    K := K + 2;
  End;
End;

{ ==================================================================== }
{ Fenetre                                                               }
{ ==================================================================== }

Procedure ClickSquare(S : LongInt);
Var N, K, M : LongInt;
Begin
  If (S < 0) Or (Over <> 0) Or (Thinking <> 0) Then Exit;
  If (TwoPlayers = 0) And (Side = CompSide) Then Exit;
  If Bd[S] * Side > 0 Then
  Begin
    { piece du camp au trait : choisie }
    If Sel = S Then Sel := -1 Else Sel := S;
    Dummy := InvalidateRect(Wnd, 0, 0);
    Exit;
  End;
  If Sel < 0 Then Exit;
  N := LegalMoves;
  M := 0;
  For K := 0 To N - 1 Do
    If (MvFrom(LegL[K]) = Sel) And (MvTo(LegL[K]) = S) Then
      If (M = 0) Or (MvPromo(LegL[K]) = QUEEN) Then M := LegL[K];
  If M <> 0 Then PlayMove(M)
  Else
  Begin
    Sel := -1;
    Dummy := InvalidateRect(Wnd, 0, 0);
  End;
End;

Procedure SetMarks;
Begin
  MCheck(MOpts, CM_LEVEL1, Level = 1); MCheck(MOpts, CM_LEVEL2, Level = 2); MCheck(MOpts, CM_LEVEL3, Level = 3);
  MCheck(MOpts, CM_BLACK, CompSide = 1); MCheck(MOpts, CM_TWO, TwoPlayers <> 0);
End;

Procedure SetLevel(N : LongInt);
Begin
  Level := N;
  SetMarks;
  Dummy := InvalidateRect(Wnd, 0, 0);
End;

Procedure Command(Id : LongInt);
Begin
  If Thinking <> 0 Then Exit;
  Case Id Of
    CM_NEW : NewGame;
    CM_UNDO : UndoMove;
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_LEVEL1 : SetLevel(1);
    CM_LEVEL2 : SetLevel(2);
    CM_LEVEL3 : SetLevel(3);
    CM_BLACK :
      Begin
        CompSide := -CompSide;
        SetMarks;
        NewGame;
      End;
    CM_TWO :
      Begin
        TwoPlayers := 1 - TwoPlayers;
        SetMarks;
        NewGame;
      End;
    CM_RULES : ShowMsg('Cliquez une de vos pi'#232'ces : ses cases d''arriv'#233'e sont marqu'#233'es ; cliquez ensuite ' +
                       'la case choisie. Roque : d'#233'placez le roi de deux cases. Un pion qui atteint la derni'#232're ' +
                       'rang'#233'e devient une dame. F2 : nouvelle partie, Ctrl+Z : annuler le dernier coup.',
                       #201'checs - R'#232'gles');
    CM_ABOUT : ShowMsg(#201'checs pour Pasdows 95 : r'#232'gles compl'#232'tes, recherche alpha-b'#234'ta. Port'#233' du ' +
                       'jeu d''OS2-0 (Presentation Manager) pour les API de Windows ; programme '#233'crit en Pascal ' +
                       'et compil'#233' par WPC.', #192' propos des '#201'checs');
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then Begin CW := MinI(Rc[2], 1024); CH := MinI(Rc[3], 768); End;
        Dummy := InvalidateRect(H, 0, 0);
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN : ClickSquare(SqAt(S16(LP), FY(S16(LP Shr 16))));
    WM_THINK :
      Begin
        Dummy := UpdateWindow(H);
        Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
        ComputerMove;
        Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
        Dummy := UpdateWindow(H);
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_KEYDOWN :
      If WP = VK_F2 Then Command(CM_NEW)
      Else If WP = VK_F1 Then Command(CM_RULES)
      Else MainProc := DefWindowProcA(H, Msg, WP, LP);
    WM_CHAR :
      If WP = 26 Then Command(CM_UNDO)                  { Ctrl+Z }
      Else MainProc := DefWindowProcA(H, Msg, WP, LP);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  MenuBar, MGame, MHelp, Dc0 : LongInt;
  Rc0 : Array[0..3] Of LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Level := 2; CompSide := -1; TwoPlayers := 0; Status := ''; Ply := 0;
  CW := 8 * Sq + 24 + 20 + 216; CH := 8 * Sq + 40;
  RegClass('Echecs', LongInt(@MainProc), 0);
  Wnd := MainWindow('Echecs', #201'checs', WS_CAPTION Or WS_SYSMENU Or WS_MINIMIZEBOX, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MGame := CreatePopupMenu; MOpts := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MGame, CM_NEW, '~Nouvelle partie'#9'F2');
  MItem(MGame, CM_UNDO, '~Annuler le coup'#9'Ctrl+Z');
  MItem(MGame, 0, '');
  MItem(MGame, CM_QUIT, '~Quitter');
  MItem(MOpts, CM_LEVEL1, 'Niveau ~facile');
  MItem(MOpts, CM_LEVEL2, 'Niveau ~moyen');
  MItem(MOpts, CM_LEVEL3, 'Niveau ~difficile');
  MItem(MOpts, 0, '');
  MItem(MOpts, CM_BLACK, 'Jouer avec les ~noirs');
  MItem(MOpts, CM_TWO, '~Deux joueurs');
  MItem(MHelp, CM_RULES, '~Comment jouer'#9'F1');
  MItem(MHelp, CM_ABOUT, #192' ~propos des '#201'checs');
  MSub(MenuBar, MGame, '~Partie');
  MSub(MenuBar, MOpts, '~Options');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  Dc0 := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc0);
  MemBmp := CreateCompatibleBitmap(Dc0, 1024, 768);
  Dummy := ReleaseDC(Wnd, Dc0);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  SetMarks;
  NewGame;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
