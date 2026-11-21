{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: SOL - Solitaire (Klondike) de Pasdows 95 (Win32), comme
                le Solitaire de Windows 95.
}

Program SOL;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\SOL.PAS SOL.EXE

  Le Solitaire (Klondike) : sept colonnes (1 a 7 cartes, la derniere
  retournee), la pioche, le talon et quatre piles de couleur (de l'as au
  roi). Dans les colonnes, les cartes descendent en alternant rouge et
  noir ; une colonne vide ne recoit qu'un roi.

  - souris : glisser une carte (ou une suite de cartes) d'une colonne,
    du talon ou d'une pile de couleur ; cliquer la pioche pour tirer une
    ou trois cartes (et la retourner quand elle est vide) ; cliquer une
    carte face cachee pour la retourner ; double clic : la carte va sur
    sa pile de couleur ; clic droit : toutes les cartes possibles y vont ;
  - Jeu : Distribuer (F2), Annuler (Ctrl+Z, le dernier coup), Dos des
    cartes (six dessins), Options (tirer une ou trois cartes, score
    standard, Vegas ou aucun, partie chronometree, barre d'etat, score
    cumule de Vegas) ;
  - score standard : talon -> colonne +5, vers une pile de couleur +10,
    carte retournee +5, pile de couleur -> colonne -15, pioche
    recommencee -100 (une carte) ou -20 (trois cartes, apres trois
    passages) ; chronometre : -2 toutes les 10 secondes et une prime a la
    fin (700 000 / secondes) ; Vegas : la partie coute 52 $, chaque carte
    sur une pile de couleur rapporte 5 $, un seul passage (trois en
    tirant trois cartes) ;
  - partie gagnee : les cartes s'envolent des piles et rebondissent. }

Const
  CardW = 71; CardH = 96; TopY = 8; UpGap = 16; DownGap = 4;
  ColY = TopY + CardH + 16;
  NP = 13;                                 { 0 pioche, 1 talon, 2-5 piles, 6-12 colonnes }
  PSTOCK = 0; PWASTE = 1; PFOUND = 2; PTAB = 6;
  StH = 22;
  CM_DEAL = 101; CM_UNDO = 102; CM_BACK = 103; CM_OPTS = 104; CM_QUIT = 105;
  CM_HELP = 201; CM_ABOUT = 202;
  ID_DRAW1 = 11; ID_DRAW3 = 12; ID_STD = 13; ID_VEGAS = 14; ID_NONE = 15; ID_TIMED = 16; ID_STATUS = 17;
  ID_CUMUL = 18; ID_OK = 1; ID_CANCEL = 2;
  Felt = $008000;
  ClrRed = $0000C0;
  WS_GROUP = $20000; BS_GROUPBOX = 7; BS_AUTORADIOBUTTON = 9;

Type
  TState = Record
    Cd : Array[0..NP * 52 - 1] Of Byte;         { carte (bit 7 : face visible) }
    Cnt : Array[0..NP - 1] Of LongInt;
    Score, Passes, WasteShow : LongInt;
  End;

Var
  S, Undo : TState;
  HasUndo, Won, Timed, ShowStatus, Cumul, Started : Boolean;
  DrawN, ScoreMode, Secs, BackNo, CumScore : LongInt;
  CW, CH, MemDC, MemBmp, CardDC, CardBmp, FontS, Seed : LongInt;
  { glisser-deposer }
  DragP, DragI, DragDX, DragDY, DragX, DragY, DownX, DownY : LongInt;
  Dragging, Moved : Boolean;
  { animation de fin }
  AnimOn : Boolean;
  AnimCard, AnimF, AnimX, AnimY, AnimVX, AnimVY : LongInt;
  DlgW, BackW, BackSel : LongInt;
  DlgCtl : Array[0..15] Of LongInt;
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
  VK_RIGHT = $27; VK_DOWN = $28; VK_DELETE = $2E; VK_F1 = $70; VK_F3 = $72;
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

Function RoundRect(Dc, L, T, R, B, W, H : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'RoundRect';
Function Ellipse(Dc, L, T, R, B : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'Ellipse';
Function Polygon(Dc, P, N : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'Polygon';
Function Rectangle(Dc, L, T, R, B : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'Rectangle';

Var
  Pt : Array[0..15] Of LongInt;
  FontL : LongInt;

Function Rnd(N : LongInt) : LongInt;
Begin
  Seed := (Seed * 1103515245 + 12345) And $7FFFFFFF;
  Rnd := (Seed Shr 8) Mod N;
End;

Function AbsI(A : LongInt) : LongInt;
Begin
  If A < 0 Then AbsI := -A Else AbsI := A;
End;

{ ==================================================================== }
{ Dessin des cartes (une fois, dans CardDC)                              }
{ ==================================================================== }

Procedure UseColor(Dc, C : LongInt; Var Pen, Br : LongInt);
Begin
  Pen := CreatePen(0, 1, C);
  Br := CreateSolidBrush(C);
  Dummy := DeleteObject(SelectObject(Dc, Pen));
  Dummy := DeleteObject(SelectObject(Dc, Br));
End;

Procedure Disk(Dc, X, Y, R : LongInt);
Begin
  Dummy := Ellipse(Dc, X - R, Y - R, X + R + 1, Y + R + 1);
End;

Procedure Tri(Dc, X1, Y1, X2, Y2, X3, Y3 : LongInt);
Begin
  Pt[0] := X1; Pt[1] := Y1; Pt[2] := X2; Pt[3] := Y2; Pt[4] := X3; Pt[5] := Y3;
  Dummy := Polygon(Dc, LongInt(@Pt), 3);
End;

{ symbole de la couleur S (0 coeur, 1 carreau, 2 trefle, 3 pique),
  centre (X, Y), demi-taille R }
Procedure DrawSuit(Dc, X, Y, R, Su : LongInt);
Var Pen, Br, H : LongInt;
Begin
  If Su < 2 Then UseColor(Dc, ClrRed, Pen, Br) Else UseColor(Dc, 0, Pen, Br);
  H := (R + 1) Div 2;
  Case Su Of
    0 :
      Begin
        Disk(Dc, X - H, Y - R Div 3, H);
        Disk(Dc, X + H, Y - R Div 3, H);
        Tri(Dc, X - R, Y - R Div 6, X + R, Y - R Div 6, X, Y + R);
      End;
    1 :
      Begin
        Pt[0] := X; Pt[1] := Y - R; Pt[2] := X + (R * 3) Div 4; Pt[3] := Y;
        Pt[4] := X; Pt[5] := Y + R; Pt[6] := X - (R * 3) Div 4; Pt[7] := Y;
        Dummy := Polygon(Dc, LongInt(@Pt), 4);
      End;
    2 :
      Begin
        Disk(Dc, X, Y - H, (R * 9) Div 20);
        Disk(Dc, X - H, Y + R Div 6, (R * 9) Div 20);
        Disk(Dc, X + H, Y + R Div 6, (R * 9) Div 20);
        Tri(Dc, X, Y, X + R Div 3, Y + R, X - R Div 3, Y + R);
      End;
  Else
    Begin
      Tri(Dc, X, Y - R, X + R, Y + R Div 5, X - R, Y + R Div 5);
      Disk(Dc, X - H, Y + R Div 4, H);
      Disk(Dc, X + H, Y + R Div 4, H);
      Tri(Dc, X, Y, X + R Div 3, Y + R, X - R Div 3, Y + R);
    End;
  End;
  Dummy := SelectObject(Dc, GetStockObject(7));
  Dummy := SelectObject(Dc, GetStockObject(0));
  Dummy := DeleteObject(Pen);
  Dummy := DeleteObject(Br);
End;

Function RankName(R : LongInt) : String;
Begin
  Case R Of
    0 : RankName := 'A';
    10 : RankName := 'V';
    11 : RankName := 'D';
    12 : RankName := 'R';
  Else
    RankName := IStr(R + 1);
  End;
End;

{ disposition des symboles : colonne (G, C, D) et ligne (0 a 6) }
Function PipLayout(N : LongInt) : String;
Begin
  Case N Of
    2 : PipLayout := 'C0C6';
    3 : PipLayout := 'C0C3C6';
    4 : PipLayout := 'G0D0G6D6';
    5 : PipLayout := 'G0D0C3G6D6';
    6 : PipLayout := 'G0D0G3D3G6D6';
    7 : PipLayout := 'G0D0C1G3D3G6D6';
    8 : PipLayout := 'G0D0C1G3D3C5G6D6';
    9 : PipLayout := 'G0D0G2D2C3G4D4G6D6';
  Else
    PipLayout := 'G0D0C1G2D2G4D4C5G6D6';
  End;
End;

Procedure RRect(Dc, X1, Y1, X2, Y2, Fill, Edge, R : LongInt);
Var Pen, Br : LongInt;
Begin
  Pen := CreatePen(0, 1, Edge);
  If Fill < 0 Then Br := GetStockObject(5) Else Br := CreateSolidBrush(Fill);
  Dummy := SelectObject(Dc, Pen);
  Dummy := SelectObject(Dc, Br);
  If R > 0 Then Dummy := RoundRect(Dc, X1, Y1, X2, Y2, R, R) Else Dummy := Rectangle(Dc, X1, Y1, X2, Y2);
  Dummy := SelectObject(Dc, GetStockObject(7));
  Dummy := SelectObject(Dc, GetStockObject(0));
  Dummy := DeleteObject(Pen);
  If Fill >= 0 Then Dummy := DeleteObject(Br);
End;

Procedure Line(Dc, X1, Y1, X2, Y2, C : LongInt);
Var Pen : LongInt;
Begin
  Pen := CreatePen(0, 1, C);
  Dummy := SelectObject(Dc, Pen);
  Dummy := MoveToEx(Dc, X1, Y1, 0);
  Dummy := LineTo(Dc, X2, Y2);
  Dummy := SelectObject(Dc, GetStockObject(7));
  Dummy := DeleteObject(Pen);
End;

Procedure BigTxt(Dc, X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  Dummy := SelectObject(Dc, FontL);
  Txt(Dc, X, Y, S, Fg, Bg);
  Dummy := SelectObject(Dc, FontS);
End;

Procedure DrawFace(Dc, X, Y, C : LongInt);
Var R, Su, Fg, K, Px, Py : LongInt; L, N : String;
Begin
  R := C Mod 13; Su := C Div 13;
  Bar(Dc, X, Y, X + CardW, Y + CardH, Felt);
  RRect(Dc, X, Y, X + CardW, Y + CardH, $FFFFFF, 0, 8);
  If Su < 2 Then Fg := ClrRed Else Fg := 0;
  N := RankName(R);
  { coins : valeur et symbole }
  Txt(Dc, X + 3, Y + 2, N, Fg, $FFFFFF);
  DrawSuit(Dc, X + 7, Y + 25, 5, Su);
  Txt(Dc, X + CardW - 3 - Length(N) * 8, Y + CardH - 18, N, Fg, $FFFFFF);
  DrawSuit(Dc, X + CardW - 8, Y + CardH - 25, 5, Su);
  If R = 0 Then DrawSuit(Dc, X + CardW Div 2, Y + CardH Div 2, 16, Su)
  Else If R >= 10 Then
  Begin
    { figure : cadre, couronne, lettre et symbole }
    RRect(Dc, X + 15, Y + 12, X + CardW - 15, Y + CardH - 12, $C0F0FF, $800000, 0);
    RRect(Dc, X + 17, Y + 14, X + CardW - 17, Y + CardH - 14, -1, Fg, 0);
    If R >= 11 Then
    Begin
      { couronne (dame et roi) }
      Pt[0] := X + 24; Pt[1] := Y + 32; Pt[2] := X + 24; Pt[3] := Y + 20; Pt[4] := X + 30; Pt[5] := Y + 26;
      Pt[6] := X + CardW Div 2; Pt[7] := Y + 17; Pt[8] := X + CardW - 30; Pt[9] := Y + 26;
      Pt[10] := X + CardW - 24; Pt[11] := Y + 20; Pt[12] := X + CardW - 24; Pt[13] := Y + 32;
      UseColor(Dc, $00C0FF, Px, Py);
      Dummy := Polygon(Dc, LongInt(@Pt), 7);
      Dummy := SelectObject(Dc, GetStockObject(7));
      Dummy := SelectObject(Dc, GetStockObject(0));
      Dummy := DeleteObject(Px); Dummy := DeleteObject(Py);
      If R = 12 Then Bar(Dc, X + CardW Div 2 - 1, Y + 14, X + CardW Div 2 + 2, Y + 18, ClrRed);
    End
    Else Line(Dc, X + 22, Y + 28, X + CardW - 22, Y + 28, Fg);
    BigTxt(Dc, X + CardW Div 2 - 8, Y + 34, N, Fg, $C0F0FF);
    DrawSuit(Dc, X + CardW Div 2, Y + CardH - 26, 8, Su);
  End
  Else
  Begin
    L := PipLayout(R + 1);
    K := 1;
    While K < Length(L) Do
    Begin
      Case L[K] Of
        'G' : Px := X + 22;
        'D' : Px := X + CardW - 22;
      Else
        Px := X + CardW Div 2;
      End;
      Py := Y + 17 + ((Ord(L[K + 1]) - 48) * (CardH - 34)) Div 6;
      DrawSuit(Dc, Px, Py, 7, Su);
      K := K + 2;
    End;
  End;
End;

{ dos des cartes : six dessins }
Procedure DrawBack(Dc, X, Y, B : LongInt);
Var K, J, C1, C2 : LongInt;
Begin
  Bar(Dc, X, Y, X + CardW, Y + CardH, Felt);
  RRect(Dc, X, Y, X + CardW, Y + CardH, $FFFFFF, 0, 8);
  Case B Of
    0, 1 :
      Begin
        { treillis bleu ou rouge }
        If B = 0 Then Begin C1 := $800000; C2 := $FF8040; End Else Begin C1 := $000080; C2 := $4040FF; End;
        Bar(Dc, X + 2, Y + 2, X + CardW - 2, Y + CardH - 2, C1);
        K := 0;
        While K < CardW + CardH Do
        Begin
          Line(Dc, X + 2 + MaxI(0, K - (CardH - 4)), Y + 2 + MinI(K, CardH - 5), X + 2 + MinI(K, CardW - 5),
               Y + 2 + MaxI(0, K - (CardW - 4)), C2);
          Line(Dc, X + CardW - 3 - MaxI(0, K - (CardH - 4)), Y + 2 + MinI(K, CardH - 5),
               X + CardW - 3 - MinI(K, CardW - 5), Y + 2 + MaxI(0, K - (CardW - 4)), C2);
          K := K + 7;
        End;
      End;
    2 :
      Begin
        { damier vert }
        For J := 0 To 11 Do
          For K := 0 To 8 Do
          Begin
            If Odd(J + K) Then C1 := $006000 Else C1 := $40C040;
            Bar(Dc, X + 2 + K * 8, Y + 2 + J * 8, MinI(X + 10 + K * 8, X + CardW - 2),
                MinI(Y + 10 + J * 8, Y + CardH - 2), C1);
          End;
      End;
    3 :
      Begin
        { drapeau de Pasdows sur fond bleu nuit }
        Bar(Dc, X + 2, Y + 2, X + CardW - 2, Y + CardH - 2, $400000);
        Bar(Dc, X + 16, Y + 27, X + 34, Y + 46, $0000FF);
        Bar(Dc, X + 37, Y + 27, X + 55, Y + 46, $00C000);
        Bar(Dc, X + 16, Y + 49, X + 34, Y + 68, $FF0000);
        Bar(Dc, X + 37, Y + 49, X + 55, Y + 68, $00FFFF);
      End;
    4 :
      Begin
        { cadres violets }
        For K := 0 To 6 Do
        Begin
          If Odd(K) Then C1 := $C060C0 Else C1 := $600060;
          RRect(Dc, X + 2 + K * 4, Y + 2 + K * 4, X + CardW - 2 - K * 4, Y + CardH - 2 - K * 4, C1, C1, 6);
        End;
      End;
  Else
    Begin
      { briques }
      Bar(Dc, X + 2, Y + 2, X + CardW - 2, Y + CardH - 2, $D0E0E0);
      For J := 0 To 11 Do
        For K := -1 To 4 Do
        Begin
          C1 := X + 4 + K * 16 + Ord(Odd(J)) * 8;
          Bar(Dc, MaxI(C1 + 1, X + 2), Y + 3 + J * 8, MinI(C1 + 15, X + CardW - 2), MinI(Y + 9 + J * 8, Y + CardH - 2),
              $1040A0);
        End;
    End;
  End;
End;

Procedure BuildCards;
Var C, B : LongInt;
Begin
  Bar(CardDC, 0, 0, 13 * CardW, 5 * CardH, Felt);
  For C := 0 To 51 Do DrawFace(CardDC, (C Mod 13) * CardW, (C Div 13) * CardH, C);
  For B := 0 To 5 Do DrawBack(CardDC, B * CardW, 4 * CardH, B);
End;

Procedure BlitCard(Dc, X, Y, C : LongInt);
Begin
  If (C And 128) <> 0 Then
  Begin
    C := C And 63;
    Dummy := BitBlt(Dc, X, Y, CardW, CardH, CardDC, (C Mod 13) * CardW, (C Div 13) * CardH, SRCCOPY);
  End
  Else Dummy := BitBlt(Dc, X, Y, CardW, CardH, CardDC, BackNo * CardW, 4 * CardH, SRCCOPY);
End;

{ ==================================================================== }
{ Regles                                                                }
{ ==================================================================== }

Function Card(P, I : LongInt) : LongInt;
Begin
  Card := S.Cd[P * 52 + I];
End;

Function Top(P : LongInt) : LongInt;
Begin
  If S.Cnt[P] = 0 Then Top := -1 Else Top := S.Cd[P * 52 + S.Cnt[P] - 1];
End;

Function Rank(C : LongInt) : LongInt;
Begin
  Rank := (C And 63) Mod 13;
End;

Function Suit(C : LongInt) : LongInt;
Begin
  Suit := (C And 63) Div 13;
End;

Function Up(C : LongInt) : Boolean;
Begin
  Up := (C And 128) <> 0;
End;

Procedure Push(P, C : LongInt);
Begin
  S.Cd[P * 52 + S.Cnt[P]] := C;
  Inc(S.Cnt[P]);
End;

Function Pop(P : LongInt) : LongInt;
Begin
  Dec(S.Cnt[P]);
  Pop := S.Cd[P * 52 + S.Cnt[P]];
End;

Procedure AddScore(N : LongInt);
Begin
  If ScoreMode = 2 Then Exit;
  S.Score := S.Score + N;
  If (ScoreMode = 0) And (S.Score < 0) Then S.Score := 0;
End;

{ carte C sur la pile de couleur F ? }
Function CanFound(C, F : LongInt) : Boolean;
Var T : LongInt;
Begin
  T := Top(F);
  If T < 0 Then CanFound := Rank(C) = 0
  Else CanFound := (Suit(T) = Suit(C)) And (Rank(T) + 1 = Rank(C));
End;

{ carte C sur la colonne P ? }
Function CanTab(C, P : LongInt) : Boolean;
Var T : LongInt;
Begin
  T := Top(P);
  If T < 0 Then CanTab := Rank(C) = 12
  Else CanTab := Up(T) And ((Suit(T) < 2) <> (Suit(C) < 2)) And (Rank(T) = Rank(C) + 1);
End;

Function FoundCount : LongInt;
Var F, N : LongInt;
Begin
  N := 0;
  For F := PFOUND To PFOUND + 3 Do N := N + S.Cnt[F];
  FoundCount := N;
End;

{ ==================================================================== }
{ Disposition                                                           }
{ ==================================================================== }

Function Gap : LongInt;
Begin
  Gap := MaxI(4, (CW - 7 * CardW) Div 8);
End;

Function ColX(K : LongInt) : LongInt;
Begin
  ColX := Gap + K * (CardW + Gap);
End;

Function PileX(P : LongInt) : LongInt;
Begin
  If P = PSTOCK Then PileX := ColX(0)
  Else If P = PWASTE Then PileX := ColX(1)
  Else If P < PTAB Then PileX := ColX(P - PFOUND + 3)
  Else PileX := ColX(P - PTAB);
End;

Function PlayH : LongInt;
Begin
  If ShowStatus Then PlayH := CH - StH Else PlayH := CH;
End;

{ ecart des cartes visibles d'une colonne : reduit si elle deborde }
Function UpStep(P : LongInt) : LongInt;
Var Dn, Un, K, Av : LongInt;
Begin
  Dn := 0; Un := 0;
  For K := 0 To S.Cnt[P] - 1 Do If Up(Card(P, K)) Then Inc(Un) Else Inc(Dn);
  Av := PlayH - 4 - ColY - CardH - Dn * DownGap;
  If Un <= 1 Then UpStep := UpGap
  Else UpStep := MaxI(5, MinI(UpGap, Av Div (Un - 1)));
End;

{ position de la carte I de la pile P }
Procedure CardPos(P, I : LongInt; Var X, Y : LongInt);
Var K, St, N0 : LongInt;
Begin
  X := PileX(P);
  If P >= PTAB Then
  Begin
    Y := ColY;
    St := UpStep(P);
    For K := 0 To I - 1 Do
      If Up(Card(P, K)) Then Y := Y + St Else Y := Y + DownGap;
  End
  Else
  Begin
    Y := TopY;
    If P = PWASTE Then
    Begin
      { trois cartes du talon en eventail }
      N0 := S.Cnt[P] - MaxI(1, MinI(S.WasteShow, S.Cnt[P]));
      If I > N0 Then X := X + (I - N0) * 14;
    End;
  End;
End;

{ ==================================================================== }
{ Affichage                                                             }
{ ==================================================================== }

Procedure EmptySlot(Dc, X, Y, Mark : LongInt);
Begin
  RRect(Dc, X, Y, X + CardW, Y + CardH, -1, $00C000, 8);
  RRect(Dc, X + 1, Y + 1, X + CardW - 1, Y + CardH - 1, -1, $004000, 8);
  If Mark = 1 Then
  Begin
    { pioche vide : cercle (recommencer) }
    RRect(Dc, X + 18, Y + 31, X + CardW - 18, Y + CardH - 30, -1, $00E000, 36);
    RRect(Dc, X + 19, Y + 32, X + CardW - 19, Y + CardH - 31, -1, $00E000, 34);
  End
  Else If Mark = 2 Then
  Begin
    { plus de passage : croix }
    Line(Dc, X + 20, Y + 30, X + CardW - 20, Y + CardH - 30, $00E000);
    Line(Dc, X + CardW - 20, Y + 30, X + 20, Y + CardH - 30, $00E000);
  End;
End;

Function MaxPasses : LongInt;
Begin
  If ScoreMode <> 1 Then MaxPasses := 1000000
  Else If DrawN = 1 Then MaxPasses := 1
  Else MaxPasses := 3;
End;

Function ScoreText : String;
Var V : LongInt; T : String;
Begin
  If ScoreMode = 1 Then
  Begin
    V := S.Score;
    If Cumul Then V := V + CumScore;
    If V < 0 Then T := '-' + IStr(-V) + ' $' Else T := IStr(V) + ' $';
    ScoreText := 'Score : ' + T;
  End
  Else ScoreText := 'Score : ' + IStr(S.Score);
End;

Procedure DrawBoard(Dc : LongInt);
Var P, I, X, Y, N, Hi : LongInt; T : String;
Begin
  Bar(Dc, 0, 0, CW, PlayH, Felt);
  For P := 0 To NP - 1 Do
  Begin
    X := PileX(P);
    If P >= PTAB Then Y := ColY Else Y := TopY;
    If Dragging And (P = DragP) Then Hi := DragI Else Hi := S.Cnt[P];
    If (S.Cnt[P] = 0) Or (Hi = 0) And (P <> PWASTE) And (P < PTAB) Then
    Begin
      If P = PSTOCK Then
      Begin
        If (S.Cnt[PWASTE] > 0) And (S.Passes + 1 >= MaxPasses) Then N := 2 Else N := 1;
        If S.Cnt[PWASTE] = 0 Then N := 0;
        EmptySlot(Dc, X, Y, N);
      End
      Else If P <> PWASTE Then EmptySlot(Dc, X, Y, 0);
    End;
    If P = PSTOCK Then
    Begin
      { pioche : une pile un peu epaisse }
      N := S.Cnt[P];
      If N > 0 Then
        For I := 0 To MinI(2, (N - 1) Div 8) Do BlitCard(Dc, X + I * 2, Y + I, 0);
    End
    Else If (P = PWASTE) Or (P < PTAB) Then
    Begin
      If P = PWASTE Then N := MaxI(0, S.Cnt[P] - MaxI(1, MinI(S.WasteShow, S.Cnt[P])) - 1)
      Else N := MaxI(0, S.Cnt[P] - 2);
      For I := N To Hi - 1 Do
      Begin
        CardPos(P, I, X, Y);
        BlitCard(Dc, X, Y, Card(P, I));
      End;
    End
    Else
      For I := 0 To Hi - 1 Do
      Begin
        CardPos(P, I, X, Y);
        BlitCard(Dc, X, Y, Card(P, I));
      End;
  End;
  { cartes glissees }
  If Dragging Then
    For I := DragI To S.Cnt[DragP] - 1 Do
      BlitCard(Dc, DragX - DragDX, DragY - DragDY + (I - DragI) * UpGap, Card(DragP, I));
  If ShowStatus Then
  Begin
    Y := CH - StH;
    Bar(Dc, 0, Y, CW, CH, ClrFace);
    Bar(Dc, 0, Y, CW, Y + 1, ClrHi);
    Bevel(Dc, 2, Y + 3, CW - 2, CH - 1, False);
    If ScoreMode <> 2 Then Txt(Dc, 8, Y + 4, ScoreText, ClrDark, ClrFace);
    If Timed Then
    Begin
      T := 'Temps : ' + IStr(Secs);
      Txt(Dc, CW - 10 - Length(T) * 8, Y + 4, T, ClrDark, ClrFace);
    End;
  End;
End;

Procedure Repaint;
Var Dc : LongInt;
Begin
  DrawBoard(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Partie                                                                }
{ ==================================================================== }

Procedure Deal;
Var Deck : Array[0..51] Of LongInt; K, J, T, P : LongInt;
Begin
  AnimOn := False;
  Dummy := KillTimer(Wnd, 2);
  If (ScoreMode = 1) And Cumul And (S.Cnt[PSTOCK] + S.Cnt[PWASTE] + FoundCount > 0) Then
    CumScore := CumScore + S.Score;
  For K := 0 To 51 Do Deck[K] := K;
  For K := 51 DownTo 1 Do
  Begin
    J := Rnd(K + 1);
    T := Deck[K]; Deck[K] := Deck[J]; Deck[J] := T;
  End;
  For P := 0 To NP - 1 Do S.Cnt[P] := 0;
  J := 0;
  For K := 0 To 6 Do
    For P := K To 6 Do
    Begin
      If P = K Then Push(PTAB + P, Deck[J] Or 128) Else Push(PTAB + P, Deck[J]);
      Inc(J);
    End;
  While J < 52 Do
  Begin
    Push(PSTOCK, Deck[J]);
    Inc(J);
  End;
  S.Passes := 0; S.WasteShow := 0;
  If ScoreMode = 1 Then S.Score := -52 Else S.Score := 0;
  Secs := 0; Won := False; HasUndo := False; Started := False; Dragging := False;
  Repaint;
End;

Procedure SaveUndo;
Begin
  Undo := S;
  HasUndo := True;
  Started := True;
End;

Procedure DoUndo;
Begin
  If Not HasUndo Or Won Then Exit;
  S := Undo;
  HasUndo := False;
  Repaint;
End;

Procedure StartAnim; Forward;

Procedure CheckWin;
Begin
  If FoundCount < 52 Then Exit;
  Won := True;
  If Timed And (ScoreMode = 0) And (Secs >= 30) Then S.Score := S.Score + 700000 Div Secs;
  Repaint;
  StartAnim;
End;

{ pioche : tirer une ou trois cartes, ou retourner le talon }
Procedure ClickStock;
Var K, N : LongInt;
Begin
  If S.Cnt[PSTOCK] > 0 Then
  Begin
    SaveUndo;
    N := MinI(DrawN, S.Cnt[PSTOCK]);
    For K := 1 To N Do Push(PWASTE, Pop(PSTOCK) Or 128);
    S.WasteShow := N;
  End
  Else If S.Cnt[PWASTE] > 0 Then
  Begin
    If S.Passes + 1 >= MaxPasses Then
    Begin
      Dummy := MessageBeep(0);
      Exit;
    End;
    SaveUndo;
    While S.Cnt[PWASTE] > 0 Do Push(PSTOCK, Pop(PWASTE) And 63);
    Inc(S.Passes);
    S.WasteShow := 0;
    If ScoreMode = 0 Then
    Begin
      If DrawN = 1 Then AddScore(-100)
      Else If S.Passes >= 3 Then AddScore(-20);
    End;
  End;
  Repaint;
End;

{ deplacer les cartes I.. de la pile P vers D (verifie avant) }
Procedure MoveCards(P, I, D : LongInt);
Var K, N : LongInt;
Begin
  SaveUndo;
  N := S.Cnt[P] - I;
  For K := 0 To N - 1 Do Push(D, Card(P, I + K));
  S.Cnt[P] := I;
  If P = PWASTE Then S.WasteShow := MaxI(1, S.WasteShow - 1);
  { score }
  If ScoreMode = 1 Then
  Begin
    If (D >= PFOUND) And (D < PTAB) And Not ((P >= PFOUND) And (P < PTAB)) Then AddScore(5);
    If (P >= PFOUND) And (P < PTAB) And Not ((D >= PFOUND) And (D < PTAB)) Then AddScore(-5);
  End
  Else
  Begin
    If (P = PWASTE) And (D >= PTAB) Then AddScore(5);
    If ((P = PWASTE) Or (P >= PTAB)) And (D >= PFOUND) And (D < PTAB) Then AddScore(10);
    If (P >= PFOUND) And (P < PTAB) And (D >= PTAB) Then AddScore(-15);
  End;
End;

{ retourner la derniere carte d'une colonne }
Function FlipTop(P : LongInt) : Boolean;
Var C : LongInt;
Begin
  FlipTop := False;
  If (P < PTAB) Or (S.Cnt[P] = 0) Then Exit;
  C := Top(P);
  If Up(C) Then Exit;
  SaveUndo;
  S.Cd[P * 52 + S.Cnt[P] - 1] := C Or 128;
  AddScore(5);
  FlipTop := True;
End;

{ la carte du dessus de P sur sa pile de couleur }
Function ToFound(P : LongInt) : Boolean;
Var C, F : LongInt;
Begin
  ToFound := False;
  If (P = PSTOCK) Or ((P >= PFOUND) And (P < PTAB)) Or (S.Cnt[P] = 0) Then Exit;
  C := Top(P);
  If Not Up(C) Then Exit;
  For F := PFOUND To PFOUND + 3 Do
    If CanFound(C, F) Then
    Begin
      MoveCards(P, S.Cnt[P] - 1, F);
      ToFound := True;
      Exit;
    End;
End;

{ clic droit : tout ce qui peut aller sur les piles de couleur }
Procedure AutoPlay;
Var P : LongInt; Any : Boolean;
Begin
  Repeat
    Any := False;
    For P := PWASTE To PTAB + 6 Do
      If (P = PWASTE) Or (P >= PTAB) Then
        If ToFound(P) Then Any := True;
  Until Not Any;
  Repaint;
  CheckWin;
End;

{ ==================================================================== }
{ Souris                                                                }
{ ==================================================================== }

Function InCard(X, Y, CX, CY : LongInt) : Boolean;
Begin
  InCard := (X >= CX) And (X < CX + CardW) And (Y >= CY) And (Y < CY + CardH);
End;

{ pile et carte sous (X, Y) ; I = -1 : emplacement vide }
Function HitTest(X, Y : LongInt; Var P, I : LongInt) : Boolean;
Var Q, K, CX, CY : LongInt;
Begin
  HitTest := True;
  For Q := 0 To NP - 1 Do
  Begin
    If S.Cnt[Q] = 0 Then
    Begin
      CX := PileX(Q);
      If Q >= PTAB Then CY := ColY Else CY := TopY;
      If InCard(X, Y, CX, CY) Then Begin P := Q; I := -1; Exit; End;
    End
    Else If (Q >= PTAB) Then
    Begin
      For K := S.Cnt[Q] - 1 DownTo 0 Do
      Begin
        CardPos(Q, K, CX, CY);
        If InCard(X, Y, CX, CY) Then Begin P := Q; I := K; Exit; End;
      End;
    End
    Else
    Begin
      CardPos(Q, S.Cnt[Q] - 1, CX, CY);
      If Q = PSTOCK Then Begin CX := PileX(Q); CY := TopY; End;
      If InCard(X, Y, CX, CY) Then Begin P := Q; I := S.Cnt[Q] - 1; Exit; End;
    End;
  End;
  HitTest := False;
End;

{ recouvrement des cartes glissees avec la pile Q }
Function Overlap(Q : LongInt) : LongInt;
Var CX, CY, X1, Y1, W, H : LongInt;
Begin
  If S.Cnt[Q] = 0 Then
  Begin
    CX := PileX(Q);
    If Q >= PTAB Then CY := ColY Else CY := TopY;
  End
  Else CardPos(Q, S.Cnt[Q] - 1, CX, CY);
  X1 := DragX - DragDX; Y1 := DragY - DragDY;
  W := MinI(X1, CX) + CardW - MaxI(X1, CX);
  H := MinI(Y1, CY) + CardH - MaxI(Y1, CY);
  If (W <= 0) Or (H <= 0) Then Overlap := 0 Else Overlap := W * H;
End;

Procedure Drop;
Var Q, Best, BestA, A, C : LongInt;
Begin
  C := Card(DragP, DragI);
  Best := -1; BestA := 0;
  For Q := PFOUND To NP - 1 Do
    If Q <> DragP Then
    Begin
      A := Overlap(Q);
      If A > BestA Then
        If ((Q < PTAB) And (DragI = S.Cnt[DragP] - 1) And CanFound(C, Q)) Or ((Q >= PTAB) And CanTab(C, Q)) Then
        Begin
          Best := Q; BestA := A;
        End;
    End;
  Dragging := False;
  If Best >= 0 Then
  Begin
    MoveCards(DragP, DragI, Best);
    Repaint;
    CheckWin;
  End
  Else Repaint;
End;

Procedure MouseDown(X, Y : LongInt; Dbl : Boolean);
Var P, I, CX, CY : LongInt;
Begin
  If AnimOn Then
  Begin
    AnimOn := False;
    Dummy := KillTimer(Wnd, 2);
    Repaint;
    Exit;
  End;
  If Won Then Exit;
  If Not HitTest(X, Y, P, I) Then Exit;
  If P = PSTOCK Then
  Begin
    ClickStock;
    Exit;
  End;
  If I < 0 Then Exit;
  If Dbl Then
  Begin
    If (I = S.Cnt[P] - 1) And ToFound(P) Then
    Begin
      Repaint;
      CheckWin;
    End;
    Exit;
  End;
  If Not Up(Card(P, I)) Then
  Begin
    If (P >= PTAB) And (I = S.Cnt[P] - 1) And FlipTop(P) Then Repaint;
    Exit;
  End;
  If (P = PWASTE) Or ((P >= PFOUND) And (P < PTAB)) Then I := S.Cnt[P] - 1;
  CardPos(P, I, CX, CY);
  DragP := P; DragI := I;
  DragDX := X - CX; DragDY := Y - CY;
  DragX := X; DragY := Y; DownX := X; DownY := Y;
  Moved := False;
  Dummy := SetCapture(Wnd);
End;

Procedure MouseMove(X, Y : LongInt);
Begin
  If DragP < 0 Then Exit;
  If Not Dragging Then
  Begin
    If (AbsI(X - DownX) < 3) And (AbsI(Y - DownY) < 3) Then Exit;
    Dragging := True;
  End;
  DragX := X; DragY := Y;
  Repaint;
End;

Procedure MouseUp(X, Y : LongInt);
Begin
  If DragP < 0 Then Exit;
  Dummy := ReleaseCapture;
  If Dragging Then
  Begin
    DragX := X; DragY := Y;
    Drop;
  End;
  Dragging := False;
  DragP := -1;
End;

{ ==================================================================== }
{ Fin de partie : les cartes rebondissent                               }
{ ==================================================================== }

Procedure LaunchNext;
Var F, K : LongInt;
Begin
  { la carte du dessus de la pile suivante (rois d'abord) }
  For K := 0 To 3 Do
  Begin
    F := PFOUND + (AnimF + K) Mod 4;
    If S.Cnt[F] > 0 Then
    Begin
      AnimF := (AnimF + K + 1) Mod 4;
      AnimCard := Pop(F);
      AnimX := PileX(F); AnimY := TopY;
      AnimVX := Rnd(6) + 2;
      If Rnd(2) = 0 Then AnimVX := -AnimVX;
      AnimVY := -Rnd(8);
      Exit;
    End;
  End;
  { plus de cartes }
  AnimOn := False;
  Dummy := KillTimer(Wnd, 2);
  Repaint;
  If Ask('Bravo, vous avez gagn'#233' !'#10'Voulez-vous distribuer une nouvelle partie ?', 'Solitaire',
         MB_YESNO Or MB_ICONQUESTION) = IDYES Then Deal;
End;

Procedure StartAnim;
Begin
  AnimOn := True; AnimF := 3;
  LaunchNext;
  Dummy := SetTimer(Wnd, 2, 15, 0);
End;

Procedure AnimStep;
Var K, Dc, Lim : LongInt;
Begin
  If Not AnimOn Then Exit;
  Lim := PlayH - CardH;
  For K := 1 To 4 Do
  Begin
    AnimX := AnimX + AnimVX;
    AnimVY := AnimVY + 1;
    AnimY := AnimY + AnimVY;
    If AnimY > Lim Then
    Begin
      AnimY := Lim;
      AnimVY := -((AnimVY * 3) Div 4);
    End;
    BlitCard(MemDC, AnimX, AnimY, AnimCard);
    If (AnimX + CardW < 0) Or (AnimX > CW) Then
    Begin
      LaunchNext;
      If Not AnimOn Then Exit;
    End;
  End;
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, PlayH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Boites : dos des cartes, options                                       }
{ ==================================================================== }

Procedure CloseDlg(H : LongInt);
Begin
  DlgW := 0;
  Dummy := EnableWindow(Wnd, 1);
  Dummy := DestroyWindow(H);
  Dummy := SetFocus(Wnd);
End;

Procedure BackPaint(H : LongInt);
Var Ps : Array[0..15] Of LongInt; Dc, B, X : LongInt;
Begin
  Dc := BeginPaint(H, LongInt(@Ps));
  Bar(Dc, 0, 0, 520, 200, ClrFace);
  Dummy := SelectObject(Dc, FontS);
  Txt(Dc, 12, 8, 'Choisissez un dos de cartes :', ClrDark, ClrFace);
  For B := 0 To 5 Do
  Begin
    X := 12 + B * (CardW + 10);
    If B = BackSel Then Bar(Dc, X - 4, 28, X + CardW + 4, 32 + CardH + 4, ClrSel);
    Dummy := BitBlt(Dc, X, 32, CardW, CardH, CardDC, B * CardW, 4 * CardH, SRCCOPY);
  End;
  Dummy := EndPaint(H, LongInt(@Ps));
End;

Function BackProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var X, B : LongInt;
Begin
  BackProc := 0;
  Case Msg Of
    WM_PAINT : BackPaint(H);
    WM_ERASEBKGND : BackProc := 1;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        X := S16(LP);
        B := (X - 8) Div (CardW + 10);
        If (B >= 0) And (B <= 5) And (S16(LP Shr 16) >= 28) And (S16(LP Shr 16) < 36 + CardH) Then
        Begin
          BackSel := B;
          Dummy := InvalidateRect(H, 0, 0);
          If Msg = WM_LBUTTONDBLCLK Then Dummy := PostMessageA(H, WM_COMMAND, ID_OK, 0);
        End;
      End;
    WM_COMMAND :
      If (WP And $FFFF) = ID_OK Then
      Begin
        BackNo := BackSel;
        CloseDlg(H);
        Repaint;
      End
      Else If (WP And $FFFF) = ID_CANCEL Then CloseDlg(H);
    WM_CLOSE : CloseDlg(H);
  Else
    BackProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function PopupWin(Cls, Title : String; W, H : LongInt) : LongInt;
Var Rc : Array[0..3] Of LongInt; Fw, Fh, R : LongInt;
Begin
  Rc[0] := 0; Rc[1] := 0; Rc[2] := W; Rc[3] := H;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), WS_POPUP Or WS_CAPTION Or WS_SYSMENU, 0, WS_EX_DLGMODALFRAME);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  PutZ(LongInt(@NameZ2), Cls);
  R := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@NameZ2), Z(Disp(Title)), WS_POPUP Or WS_CAPTION Or WS_SYSMENU,
                       MaxI(0, (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2),
                       MaxI(0, (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2), Fw, Fh, Wnd, 0, Inst, 0);
  If R <> 0 Then Dummy := EnableWindow(Wnd, 0);
  DlgW := R;
  PopupWin := R;
End;

Procedure ChooseBack;
Var H : LongInt;
Begin
  BackSel := BackNo;
  H := PopupWin('SolBack', 'Dos des cartes', 6 * (CardW + 10) + 14, CardH + 84);
  If H = 0 Then Exit;
  Dummy := Ctl(H, 'BUTTON', 'OK', WS_TABSTOP Or BS_DEFPUSHBUTTON, 6 * (CardW + 10) - 186, CardH + 48, 90, 26, ID_OK);
  Dummy := Ctl(H, 'BUTTON', 'Annuler', WS_TABSTOP, 6 * (CardW + 10) - 86, CardH + 48, 90, 26, ID_CANCEL);
  Dummy := ShowWindow(H, 1);
  Dummy := UpdateWindow(H);
End;

Function Checked(H : LongInt) : Boolean;
Begin
  Checked := SendMessageA(H, BM_GETCHECK, 0, 0) <> 0;
End;

Procedure SetCheck(H : LongInt; On : Boolean);
Begin
  Dummy := SendMessageA(H, BM_SETCHECK, Ord(On), 0);
End;

Procedure OptsOk(H : LongInt);
Var NDraw, NScore : LongInt; Again : Boolean;
Begin
  If Checked(DlgCtl[1]) Then NDraw := 3 Else NDraw := 1;
  If Checked(DlgCtl[3]) Then NScore := 1 Else If Checked(DlgCtl[4]) Then NScore := 2 Else NScore := 0;
  Again := (NDraw <> DrawN) Or (NScore <> ScoreMode) Or (Checked(DlgCtl[5]) <> Timed);
  ShowStatus := Checked(DlgCtl[6]);
  Cumul := Checked(DlgCtl[7]);
  If Again Then
  Begin
    DrawN := NDraw;
    If NScore <> ScoreMode Then CumScore := 0;
    ScoreMode := NScore;
    Timed := Checked(DlgCtl[5]);
  End;
  CloseDlg(H);
  If Again Then Deal Else Repaint;
End;

Procedure OptsPaint(H : LongInt);
Var Ps : Array[0..15] Of LongInt; Dc : LongInt;
Begin
  Dc := BeginPaint(H, LongInt(@Ps));
  Bar(Dc, 0, 0, 400, 300, ClrFace);
  Dummy := EndPaint(H, LongInt(@Ps));
End;

Function OptsProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  OptsProc := 0;
  Case Msg Of
    WM_PAINT : OptsPaint(H);
    WM_ERASEBKGND : OptsProc := 1;
    WM_COMMAND :
      If (WP And $FFFF) = ID_OK Then OptsOk(H)
      Else If (WP And $FFFF) = ID_CANCEL Then CloseDlg(H);
    WM_CLOSE : CloseDlg(H);
  Else
    OptsProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Procedure Options;
Var H : LongInt;
Begin
  H := PopupWin('SolOpts', 'Options', 360, 214);
  If H = 0 Then Exit;
  Dummy := Ctl(H, 'BUTTON', 'Tirer', BS_GROUPBOX, 10, 8, 160, 76, 0);
  DlgCtl[0] := Ctl(H, 'BUTTON', 'Une carte', WS_TABSTOP Or WS_GROUP Or BS_AUTORADIOBUTTON, 22, 30, 140, 20, ID_DRAW1);
  DlgCtl[1] := Ctl(H, 'BUTTON', 'Trois cartes', BS_AUTORADIOBUTTON, 22, 54, 140, 20, ID_DRAW3);
  Dummy := Ctl(H, 'BUTTON', 'Score', BS_GROUPBOX, 186, 8, 164, 100, 0);
  DlgCtl[2] := Ctl(H, 'BUTTON', 'Standard', WS_TABSTOP Or WS_GROUP Or BS_AUTORADIOBUTTON, 198, 30, 140, 20, ID_STD);
  DlgCtl[3] := Ctl(H, 'BUTTON', 'Vegas', BS_AUTORADIOBUTTON, 198, 54, 140, 20, ID_VEGAS);
  DlgCtl[4] := Ctl(H, 'BUTTON', 'Aucun', BS_AUTORADIOBUTTON, 198, 78, 140, 20, ID_NONE);
  DlgCtl[5] := Ctl(H, 'BUTTON', 'Partie chronom'#233'tr'#233'e', WS_TABSTOP Or WS_GROUP Or BS_AUTOCHECKBOX, 12, 100,
                   170, 20, ID_TIMED);
  DlgCtl[6] := Ctl(H, 'BUTTON', 'Barre d'''#233'tat', WS_TABSTOP Or BS_AUTOCHECKBOX, 12, 124, 170, 20, ID_STATUS);
  DlgCtl[7] := Ctl(H, 'BUTTON', 'Score cumul'#233, WS_TABSTOP Or BS_AUTOCHECKBOX, 198, 124, 150, 20, ID_CUMUL);
  SetCheck(DlgCtl[0], DrawN = 1); SetCheck(DlgCtl[1], DrawN = 3);
  SetCheck(DlgCtl[2], ScoreMode = 0); SetCheck(DlgCtl[3], ScoreMode = 1); SetCheck(DlgCtl[4], ScoreMode = 2);
  SetCheck(DlgCtl[5], Timed); SetCheck(DlgCtl[6], ShowStatus); SetCheck(DlgCtl[7], Cumul);
  Dummy := Ctl(H, 'BUTTON', 'OK', WS_TABSTOP Or WS_GROUP Or BS_DEFPUSHBUTTON, 160, 174, 90, 26, ID_OK);
  Dummy := Ctl(H, 'BUTTON', 'Annuler', WS_TABSTOP, 260, 174, 90, 26, ID_CANCEL);
  Dummy := ShowWindow(H, 1);
  Dummy := UpdateWindow(H);
End;

{ ==================================================================== }
{ Fenetre principale                                                    }
{ ==================================================================== }

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    CM_DEAL : Deal;
    CM_UNDO : DoUndo;
    CM_BACK : ChooseBack;
    CM_OPTS : Options;
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_HELP : Dummy := Ask('Rangez toutes les cartes sur les quatre piles de couleur, en haut '#224' droite, de l''as '#224' ' +
                           'la reine puis au roi, chaque pile d''une seule couleur.'#10#10'Dans les colonnes, posez une ' +
                           'carte sur une carte de valeur imm'#233'diatement sup'#233'rieure et de l''autre couleur ' +
                           '(rouge sur noir). Seul un roi va dans une colonne vide.'#10#10'Cliquez la pioche pour tirer ' +
                           'des cartes ; glissez les cartes avec la souris ; double clic ou clic droit : vers les ' +
                           'piles de couleur.', 'Comment jouer au Solitaire', MB_OK Or MB_ICONINFO);
    CM_ABOUT : Dummy := Ask('Solitaire de Pasdows 95'#10#10'Le Klondike comme celui de Windows 95. Programme '#233'crit ' +
                            'en Pascal et compil'#233' par WPC.', #192' propos du Solitaire', MB_OK Or MB_ICONINFO);
  End;
End;

Procedure CheatWin;
Var K, F : LongInt;
Begin
  For F := 0 To NP - 1 Do S.Cnt[F] := 0;
  For F := 0 To 3 Do
    For K := 0 To 12 Do Push(PFOUND + F, (F * 13 + K) Or 128);
  Started := True;
  CheckWin;
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
        If Not AnimOn Then Dummy := InvalidateRect(H, 0, 0);
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        If Not AnimOn Then DrawBoard(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN : MouseDown(S16(LP), S16(LP Shr 16), False);
    WM_LBUTTONDBLCLK : MouseDown(S16(LP), S16(LP Shr 16), True);
    WM_MOUSEMOVE : MouseMove(S16(LP), S16(LP Shr 16));
    WM_LBUTTONUP : MouseUp(S16(LP), S16(LP Shr 16));
    WM_RBUTTONDOWN : If Not Won And Not AnimOn Then AutoPlay;
    WM_TIMER :
      If WP = 2 Then AnimStep
      Else If Timed And Started And Not Won And (DlgW = 0) Then
      Begin
        Inc(Secs);
        If (ScoreMode = 0) And (Secs Mod 10 = 0) Then AddScore(-2);
        If ShowStatus And Not AnimOn And Not Dragging Then Repaint;
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_KEYDOWN :
      If WP = VK_F2 Then Command(CM_DEAL)
      Else If WP = VK_F1 Then Command(CM_HELP)
      Else MainProc := DefWindowProcA(H, Msg, WP, LP);
    $0104 :
      { Alt+Maj+2 : la partie est gagnee (raccourci du Solitaire de Windows) }
      If (WP = Ord('2')) And (GetKeyState(VK_SHIFT) < 0) And Not Won And Not AnimOn Then CheatWin
      Else MainProc := DefWindowProcA(H, Msg, WP, LP);
    WM_CHAR :
      If WP = 26 Then Command(CM_UNDO)
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
  Seed := GetTickCount;
  DrawN := 3; ScoreMode := 0; Timed := True; ShowStatus := True; Cumul := False; CumScore := 0; BackNo := 0;
  DragP := -1; Dragging := False; AnimOn := False; DlgW := 0; Started := False; Won := False;
  CW := 7 * CardW + 8 * 12; CH := 380;
  RegClass('Solitaire', LongInt(@MainProc), CS_DBLCLKS);
  RegClass('SolBack', LongInt(@BackProc), CS_DBLCLKS);
  RegClass('SolOpts', LongInt(@OptsProc), 0);
  Wnd := MainWindow('Solitaire', 'Solitaire', WS_OVERLAPPEDWINDOW, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MGame := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MGame, CM_DEAL, '~Distribuer'#9'F2');
  MItem(MGame, 0, '');
  MItem(MGame, CM_UNDO, '~Annuler'#9'Ctrl+Z');
  MItem(MGame, CM_BACK, 'Dos des ~cartes...');
  MItem(MGame, CM_OPTS, '~Options...');
  MItem(MGame, 0, '');
  MItem(MGame, CM_QUIT, '~Quitter');
  MItem(MHelp, CM_HELP, '~Comment jouer'#9'F1');
  MItem(MHelp, CM_ABOUT, #192' ~propos du Solitaire');
  MSub(MenuBar, MGame, '~Jeu');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  Dc0 := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc0);
  MemBmp := CreateCompatibleBitmap(Dc0, 1024, 768);
  CardDC := CreateCompatibleDC(Dc0);
  CardBmp := CreateCompatibleBitmap(Dc0, 13 * CardW, 5 * CardH);
  Dummy := ReleaseDC(Wnd, Dc0);
  Dummy := SelectObject(MemDC, MemBmp);
  Dummy := SelectObject(CardDC, CardBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  FontL := CreateFontA(32, 16, 0, 0, 700, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SelectObject(CardDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  Dummy := SetBkMode(CardDC, OPAQUE);
  BuildCards;
  Deal;
  Dummy := SetTimer(Wnd, 1, 1000, 0);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
