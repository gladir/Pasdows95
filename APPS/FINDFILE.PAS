{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: FINDFILE - Rechercher de Pasdows 95 (Win32) : fichiers ou
                dossiers, et ordinateur (/C), comme Windows 95.
}

Program FindFile;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\FINDFILE.PAS FINDFILE.EXE

  Menu Demarrer, Rechercher :
  - "Fichiers ou dossiers..." (FINDFILE) : Nomme (modeles * et ?
    separes par ; ou , ; sans joker, le nom contient le texte),
    Contenant le texte, Rechercher dans (Parcourir : les lecteurs),
    Inclure les sous-dossiers ; la recherche avance par petits
    morceaux (la fenetre repond, Arreter l'interrompt) ; resultats
    Nom, Dans le dossier, Taille, Type, Modifie, tries en cliquant sur
    l'en-tete ; double clic ou Entree : ouvrir (ShellExecute), menu
    contextuel : Ouvrir, Ouvrir le dossier contenant, Copier le chemin ;
  - "Ordinateur..." (FINDFILE /C) : le nom est resolu par
    gethostbyname (DNS de la pile TCP/IP), le poste lui-meme par
    GetComputerName. }

Const
  MaxRes = 4000;
  MaxDirs = 2000;
  CM_OPEN = 101; CM_OPENDIR = 102; CM_COPYPATH = 103; CM_CLOSE = 104; CM_SAVE = 105;
  CM_CASE = 201; CM_NEWSRCH = 202;
  CM_ABOUT = 301;
  CM_DRIVE = 500;
  ID_NAME = 10; ID_TEXT = 11; ID_DIR = 12; ID_SUB = 13; ID_BROWSE = 14;
  ID_FIND = 20; ID_STOP = 2; ID_NEW = 22;
  WM_STEP = $0401;
  TopH = 172; RowH = 18; HdrH = 20; StH = 22; SbW = 16; PanW = 164;

Type
  TRes = Record
    Name : String[79];
    Dir : String;
    Size, Attr, Tm, Ip : LongInt;
  End;
  PRes = ^TRes;
  TDirS = String;
  PDirS = ^TDirS;

Var
  Res : Array[0..MaxRes - 1] Of PRes;
  Dirs : Array[0..MaxDirs - 1] Of PDirS;
  NRes, NDirs, Sel, Top, SortCol, CW, CH, MemDC, MemBmp, FontS, VSb : LongInt;
  NameW, TextW, DirW, SubW, BrowseW, FindW, StopW, NewW, CtxMenu, MOpts : LongInt;
  CompMode, Busy, CaseOn, SubOn : Boolean;
  Pats : Array[0..15] Of String[79];
  NPats : LongInt;
  Needle, CurDir, StatusS : String;
  NScan : LongInt;
  FindH : LongInt;
  FData : Array[0..319] Of Byte;
  FBuf : Array[0..16383] Of Byte;
  ClipBuf : Array[0..1023] Of Byte;
  St : Array[0..7] Of Word;
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

Function FileTimeToSystemTime(Ft, Sy : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FileTimeToSystemTime';
Function FileTimeToLocalFileTime(A, B : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'FileTimeToLocalFileTime';
Function GetComputerNameA(B, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetComputerNameA';
Function ShellExecuteA(H, Op, F, P, D, Sh : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ShellExecuteA';
Function WSAStartup(V, P : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'WSAStartup';
Function gethostbyname(N : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'gethostbyname';
Function PeekMessageA(P, H, A, B, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'PeekMessageA';

Var
  WsaData : Array[0..399] Of Byte;

{ ==================================================================== }
{ Modeles de noms                                                       }
{ ==================================================================== }

{ * et ? ; sans casse }
Function Match(P, S : String) : Boolean;
Var I, J, SI, SJ : LongInt;
Begin
  I := 1; J := 1; SI := 0; SJ := 0;
  While J <= Length(S) Do
  Begin
    If (I <= Length(P)) And ((P[I] = '?') Or (P[I] = S[J])) Then Begin Inc(I); Inc(J); End
    Else If (I <= Length(P)) And (P[I] = '*') Then Begin SI := I; SJ := J; Inc(I); End
    Else If SI > 0 Then Begin I := SI + 1; Inc(SJ); J := SJ; End
    Else Begin Match := False; Exit; End;
  End;
  While (I <= Length(P)) And (P[I] = '*') Do Inc(I);
  Match := I > Length(P);
End;

Procedure SetPats(S : String);
Var K : LongInt; T : String;
Begin
  NPats := 0;
  S := UpS(S) + ';';
  T := '';
  For K := 1 To Length(S) Do
    If (S[K] = ';') Or (S[K] = ',') Then
    Begin
      T := TrimS(T);
      If (T <> '') And (NPats < 16) Then
      Begin
        { sans joker : le nom contient le texte (comme Windows 95) }
        If (Pos('*', T) = 0) And (Pos('?', T) = 0) Then T := '*' + T + '*';
        Pats[NPats] := T;
        Inc(NPats);
      End;
      T := '';
    End
    Else T := T + S[K];
End;

Function NameOk(N : String) : Boolean;
Var K : LongInt;
Begin
  NameOk := NPats = 0;
  N := UpS(N);
  For K := 0 To NPats - 1 Do
    If Match(Pats[K], N) Then NameOk := True;
End;

{ le fichier contient Needle (deja en majuscules sauf CaseOn) }
Function HasText(P : String) : Boolean;
Var H, N, K, J, L, Keep, C : LongInt; Ok : Boolean;
Begin
  HasText := False;
  L := Length(Needle);
  If L = 0 Then Begin HasText := True; Exit; End;
  H := CreateFileA(Z(P), GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  Keep := 0;
  Repeat
    N := 0;
    Dummy := ReadFile(H, LongInt(@FBuf[Keep]), SizeOf(FBuf) - Keep, LongInt(@N), 0);
    If N <= 0 Then Break;
    N := N + Keep;
    For K := 0 To N - L Do
    Begin
      Ok := True;
      For J := 1 To L Do
      Begin
        C := FBuf[K + J - 1];
        If (Not CaseOn) And (C >= 97) And (C <= 122) Then C := C - 32;
        If (Not CaseOn) And (C >= 224) And (C <= 254) And (C <> 247) Then C := C - 32;
        If C <> Ord(Needle[J]) Then Begin Ok := False; Break; End;
      End;
      If Ok Then
      Begin
        HasText := True;
        Dummy := CloseHandle(H);
        Exit;
      End;
    End;
    { garder la fin (le texte peut etre a cheval) }
    Keep := MinI(L - 1, N);
    For K := 0 To Keep - 1 Do FBuf[K] := FBuf[N - Keep + K];
  Until False;
  Dummy := CloseHandle(H);
End;

Function UpAnsi(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If ((S[K] >= 'a') And (S[K] <= 'z')) Or ((Ord(S[K]) >= 224) And (Ord(S[K]) <= 254) And (Ord(S[K]) <> 247)) Then
      S[K] := Chr(Ord(S[K]) - 32);
  UpAnsi := S;
End;

{ ==================================================================== }
{ Resultats                                                             }
{ ==================================================================== }

Function TypeOf0(I : LongInt) : String;
Var E, N : String; K : LongInt;
Begin
  If CompMode Then Begin TypeOf0 := 'Ordinateur'; Exit; End;
  If (Res[I]^.Attr And $10) <> 0 Then Begin TypeOf0 := 'Dossier de fichiers'; Exit; End;
  N := Res[I]^.Name; K := Length(N);
  While (K > 0) And (N[K] <> '.') Do Dec(K);
  If K = 0 Then E := '' Else E := UpS(Copy(N, K + 1, 9));
  If (E = 'EXE') Or (E = 'COM') Then TypeOf0 := 'Application'
  Else If E = 'TXT' Then TypeOf0 := 'Document texte'
  Else If E = 'INI' Then TypeOf0 := 'Param'#232'tres de configuration'
  Else If E = 'DLL' Then TypeOf0 := 'Extension de l''application'
  Else If E = 'HLP' Then TypeOf0 := 'Fichier d''aide'
  Else If E = 'BMP' Then TypeOf0 := 'Image bitmap'
  Else If (E = 'JPG') Or (E = 'JPEG') Or (E = 'GIF') Or (E = 'PNG') Or (E = 'TIF') Or (E = 'TIFF') Then
    TypeOf0 := 'Image ' + E
  Else If (E = 'MP3') Or (E = 'WAV') Or (E = 'MID') Then TypeOf0 := 'Son ' + E
  Else If (E = 'HTM') Or (E = 'HTML') Then TypeOf0 := 'Document HTML'
  Else If E = 'BAT' Then TypeOf0 := 'Fichier de commandes MS-DOS'
  Else If E = 'SYS' Then TypeOf0 := 'Fichier syst'#232'me'
  Else If E = 'PAS' Then TypeOf0 := 'Source Pascal'
  Else If E = '' Then TypeOf0 := 'Fichier'
  Else TypeOf0 := 'Fichier ' + E;
End;

Function SizeStr(I : LongInt) : String;
Var V : LongInt;
Begin
  If CompMode Or ((Res[I]^.Attr And $10) <> 0) Then Begin SizeStr := ''; Exit; End;
  V := Res[I]^.Size;
  If V = 0 Then SizeStr := '0 Ko'
  Else If V < 1024 * 1000 Then SizeStr := IStr((V + 1023) Div 1024) + ' Ko'
  Else SizeStr := IStr(V Div 1048576) + ',' + IStr((V Mod 1048576) * 10 Div 1048576) + ' Mo';
End;

Function DateStr(I : LongInt) : String;
Var T : LongInt;
Begin
  T := Res[I]^.Tm;
  If CompMode Then
  Begin
    DateStr := IStr((T Shr 0) And 255) + '.' + IStr((T Shr 8) And 255) + '.' + IStr((T Shr 16) And 255) + '.' +
               IStr((T Shr 24) And 255);
    Exit;
  End;
  If T = 0 Then Begin DateStr := ''; Exit; End;
  { T : jour 5 bits, mois 4, annee - 1980 7, heure 5, minute 6 }
  DateStr := Two(T And 31) + '/' + Two((T Shr 5) And 15) + '/' + Two(((T Shr 9) And 127) + 80) + ' ' +
             Two((T Shr 16) And 31) + ':' + Two((T Shr 21) And 63);
End;

Function ColKey(I, C : LongInt) : String;
Var S : String;
Begin
  Case C Of
    1 : ColKey := UpS(Res[I]^.Dir) + #1 + UpS(Res[I]^.Name);
    2 : Begin
          S := IStr(Res[I]^.Size);
          While Length(S) < 11 Do S := '0' + S;
          ColKey := S;
        End;
    3 : ColKey := UpS(TypeOf0(I)) + #1 + UpS(Res[I]^.Name);
    4 : Begin
          S := IStr(Res[I]^.Tm);
          While Length(S) < 11 Do S := '0' + S;
          ColKey := S;
        End;
  Else
    ColKey := UpS(Res[I]^.Name) + #1 + UpS(Res[I]^.Dir);
  End;
End;

Procedure SortRes;
Var I, J : LongInt; P : PRes; K : String;
Begin
  For I := 1 To NRes - 1 Do
  Begin
    P := Res[I]; K := ColKey(I, SortCol);
    J := I - 1;
    While (J >= 0) And (ColKey(J, SortCol) > K) Do
    Begin
      Res[J + 1] := Res[J];
      Dec(J);
    End;
    Res[J + 1] := P;
  End;
End;

Procedure ClearRes;
Var I : LongInt;
Begin
  For I := 0 To NRes - 1 Do FreeMem(Res[I], SizeOf(TRes));
  NRes := 0; Sel := -1; Top := 0;
End;

Function AddRes(N, D : String; Sz, At, T : LongInt) : Boolean;
Var P : PRes;
Begin
  AddRes := False;
  If NRes >= MaxRes Then Exit;
  GetMem(P, SizeOf(TRes));
  P^.Name := Copy(N, 1, 79); P^.Dir := D; P^.Size := Sz; P^.Attr := At; P^.Tm := T; P^.Ip := 0;
  Res[NRes] := P;
  Inc(NRes);
  AddRes := True;
End;

Function FullPath(I : LongInt) : String;
Var D : String;
Begin
  D := Res[I]^.Dir;
  If (D <> '') And (D[Length(D)] <> '\') Then D := D + '\';
  FullPath := D + Res[I]^.Name;
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }

Function NRows : LongInt;
Begin
  NRows := MaxI(1, (CH - StH - TopH - HdrH - 4) Div RowH);
End;

Function NCols : LongInt;
Begin
  If CompMode Then NCols := 3 Else NCols := 5;
End;

Function ColName(C : LongInt) : String;
Begin
  If CompMode Then
    Case C Of
      0 : ColName := 'Nom';
      1 : ColName := 'Emplacement';
    Else ColName := 'Adresse IP';
    End
  Else
    Case C Of
      0 : ColName := 'Nom';
      1 : ColName := 'Dans le dossier';
      2 : ColName := 'Taille';
      3 : ColName := 'Type';
    Else ColName := 'Modifi'#233;
    End;
End;

Procedure ColRange(C : LongInt; Var X1, X2 : LongInt);
Var W : LongInt;
  Function At(K : LongInt) : LongInt;
  Begin
    If CompMode Then
      Case K Of
        0 : At := 0; 1 : At := 40; 2 : At := 70;
      Else At := 100;
      End
    Else
      Case K Of
        0 : At := 0; 1 : At := 22; 2 : At := 50; 3 : At := 60; 4 : At := 76;
      Else At := 100;
      End;
  End;
Begin
  W := CW - SbW - 4;
  X1 := 2 + (W * At(C)) Div 100;
  X2 := 2 + (W * At(C + 1)) Div 100;
End;

Procedure Clip(Dc, X, Y, W : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If W < 12 Then Exit;
  If Length(S) * 8 > W - 4 Then S := Copy(S, 1, MaxI(0, (W - 4) Div 8 - 1)) + #187;
  Txt(Dc, X, Y, S, Fg, Bg);
End;

Function CellText(I, C : LongInt) : String;
Begin
  If CompMode Then
    Case C Of
      0 : CellText := Res[I]^.Name;
      1 : CellText := Res[I]^.Dir;
    Else CellText := DateStr(I);
    End
  Else
    Case C Of
      0 : CellText := Res[I]^.Name;
      1 : CellText := Res[I]^.Dir;
      2 : CellText := SizeStr(I);
      3 : CellText := TypeOf0(I);
    Else CellText := DateStr(I);
    End;
End;

Procedure DrawTop(Dc : LongInt);
Var X2 : LongInt;
Begin
  Bar(Dc, 0, 0, CW, TopH, ClrFace);
  X2 := CW - PanW - 8;
  { onglet "Nom et emplacement" et son cadre }
  Bar(Dc, 8, 8, 8 + 160, 9, ClrHi);
  Bar(Dc, 8, 8, 9, 30, ClrHi);
  Bar(Dc, 8 + 159, 9, 8 + 160, 30, ClrDark);
  Bar(Dc, 8 + 158, 10, 8 + 159, 30, ClrShadow);
  If CompMode Then Txt(Dc, 16, 12, 'Nom', ClrDark, ClrFace)
  Else Txt(Dc, 16, 12, 'Nom et emplacement', ClrDark, ClrFace);
  Bar(Dc, 8, 30, 9, TopH - 8, ClrHi);
  Bar(Dc, 168, 30, X2, 31, ClrHi);
  Bar(Dc, 8, TopH - 9, X2, TopH - 8, ClrDark);
  Bar(Dc, 9, TopH - 10, X2 - 1, TopH - 9, ClrShadow);
  Bar(Dc, X2 - 1, 30, X2, TopH - 8, ClrDark);
  Bar(Dc, X2 - 2, 31, X2 - 1, TopH - 9, ClrShadow);
  Txt(Dc, 20, 48, 'Nomm'#233' :', ClrDark, ClrFace);
  If Not CompMode Then
  Begin
    Txt(Dc, 20, 78, 'Contenant le texte :', ClrDark, ClrFace);
    Txt(Dc, 20, 108, 'Rechercher dans :', ClrDark, ClrFace);
  End;
  { animation : loupe }
  Bar(Dc, CW - PanW + 40, 118, CW - PanW + 80, 120, ClrFace);
End;

Procedure DrawList(Dc : LongInt);
Var C, R, I, Y, X1, X2, Fg, Bg : LongInt; S : String;
Begin
  Y := TopH;
  Bar(Dc, 0, Y, CW, CH, ClrFace);
  For C := 0 To NCols - 1 Do
  Begin
    ColRange(C, X1, X2);
    If C = NCols - 1 Then X2 := CW - SbW - 2;
    Bevel(Dc, X1, Y, X2, Y + HdrH, True);
    S := ColName(C);
    If C = SortCol Then S := S + ' ' + #31;
    Clip(Dc, X1 + 4, Y + 2, X2 - X1 - 4, S, ClrDark, ClrFace);
  End;
  Bar(Dc, 2, Y + HdrH, CW - SbW - 2, CH - StH - 2, ClrWin);
  For R := 0 To NRows - 1 Do
  Begin
    I := Top + R;
    If I >= NRes Then Break;
    Y := TopH + HdrH + 1 + R * RowH;
    If I = Sel Then Begin Bg := ClrSel; Fg := ClrHi; End Else Begin Bg := ClrWin; Fg := ClrDark; End;
    For C := 0 To NCols - 1 Do
    Begin
      ColRange(C, X1, X2);
      If C = NCols - 1 Then X2 := CW - SbW - 2;
      If C = 0 Then
      Begin
        Bar(Dc, X1 + 2, Y, X1 + 4 + Length(Res[I]^.Name) * 8 + 4, Y + RowH, Bg);
        Clip(Dc, X1 + 4, Y + 1, X2 - X1 - 2, CellText(I, C), Fg, Bg);
      End
      Else Clip(Dc, X1 + 4, Y + 1, X2 - X1 - 2, CellText(I, C), ClrDark, ClrWin);
    End;
  End;
  Bevel(Dc, 0, TopH - 1, CW - SbW - 1, CH - StH - 1, False);
  Y := CH - StH;
  Bar(Dc, 0, Y, CW, CH, ClrFace);
  Bevel(Dc, 2, Y + 2, CW - 2, CH - 1, False);
  Clip(Dc, 6, Y + 4, CW - 12, StatusS, ClrDark, ClrFace);
End;

Procedure PaintList;
Var Dc : LongInt;
Begin
  DrawList(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, TopH, CW - SbW - 1, CH - TopH, MemDC, 0, TopH, SRCCOPY);
  Dummy := BitBlt(Dc, CW - SbW - 1, CH - StH, SbW + 1, StH, MemDC, CW - SbW - 1, CH - StH, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

Procedure Ensure;
Begin
  If Sel >= NRes Then Sel := NRes - 1;
  If (Sel >= 0) And (Sel < Top) Then Top := Sel;
  If (Sel >= 0) And (Sel >= Top + NRows) Then Top := Sel - NRows + 1;
  If Top > MaxI(0, NRes - NRows) Then Top := MaxI(0, NRes - NRows);
  If Top < 0 Then Top := 0;
  Dummy := SetScrollRange(VSb, 2, 0, MaxI(0, NRes - NRows), 0);
  Dummy := SetScrollPos(VSb, 2, Top, 1);
End;

Procedure Refresh;
Begin
  Ensure;
  PaintList;
End;

Procedure CountStatus;
Begin
  If NRes = 0 Then StatusS := 'Aucun '#233'l'#233'ment trouv'#233
  Else If NRes = 1 Then StatusS := '1 '#233'l'#233'ment trouv'#233
  Else StatusS := IStr(NRes) + ' '#233'l'#233'ments trouv'#233's';
  If NRes >= MaxRes Then StatusS := StatusS + ' (limite atteinte)';
End;

Procedure SetBusy(B : Boolean);
Begin
  Busy := B;
  Dummy := EnableWindow(FindW, Ord(Not B));
  Dummy := EnableWindow(StopW, Ord(B));
  Dummy := EnableWindow(NewW, Ord(Not B));
  If B Then Dummy := SetCursor(LoadCursorA(0, IDC_WAIT)) Else Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
End;

{ ==================================================================== }
{ Recherche de fichiers, par morceaux (WM_STEP)                         }
{ ==================================================================== }

Procedure PushDir(D : String);
Var P : PDirS;
Begin
  If NDirs >= MaxDirs Then Exit;
  GetMem(P, SizeOf(TDirS));
  P^ := D;
  Dirs[NDirs] := P;
  Inc(NDirs);
End;

Function PopDir(Var D : String) : Boolean;
Begin
  PopDir := False;
  If NDirs = 0 Then Exit;
  Dec(NDirs);
  D := Dirs[NDirs]^;
  FreeMem(Dirs[NDirs], SizeOf(TDirS));
  PopDir := True;
End;

Procedure StopSearch(Why : String);
Var D : String;
Begin
  If FindH <> INVALID_HANDLE Then Dummy := FindClose(FindH);
  FindH := INVALID_HANDLE;
  While PopDir(D) Do ;
  SetBusy(False);
  SortRes;
  CountStatus;
  If Why <> '' Then StatusS := StatusS + ' - ' + Why;
  Refresh;
End;

Function DosTime(I : LongInt) : LongInt;
Var Lf : Array[0..1] Of LongInt;
Begin
  DosTime := 0;
  If FileTimeToLocalFileTime(LongInt(@FData[20]), LongInt(@Lf)) = 0 Then Exit;
  If FileTimeToSystemTime(LongInt(@Lf), LongInt(@St)) = 0 Then Exit;
  If St[0] < 1980 Then Exit;
  DosTime := St[3] Or (St[1] Shl 5) Or ((St[0] - 1980) Shl 9) Or (St[4] Shl 16) Or (St[5] Shl 21);
End;

{ une entree du dossier CurDir }
Procedure OneEntry;
Var N, P : String; A, Sz : LongInt; L : PLng;
Begin
  N := GetZ(LongInt(@FData[44]));
  If (N = '.') Or (N = '..') Then Exit;
  L := PLng(LongInt(@FData[0])); A := L^;
  L := PLng(LongInt(@FData[32])); Sz := L^;
  P := CurDir;
  If P[Length(P)] <> '\' Then P := P + '\';
  If ((A And $10) <> 0) And SubOn Then PushDir(P + N);
  Inc(NScan);
  If Not NameOk(N) Then Exit;
  If Needle <> '' Then
  Begin
    If (A And $10) <> 0 Then Exit;
    If Not HasText(P + N) Then Exit;
  End;
  If Not AddRes(N, CurDir, Sz, A, DosTime(0)) Then StopSearch('');
End;

Procedure Step;
Var T0 : LongInt; P : String;
Begin
  If Not Busy Then Exit;
  T0 := GetTickCount;
  Repeat
    If FindH = INVALID_HANDLE Then
    Begin
      If Not PopDir(CurDir) Then
      Begin
        StopSearch('');
        Exit;
      End;
      P := CurDir;
      If P[Length(P)] <> '\' Then P := P + '\';
      FindH := FindFirstFileA(Z(P + '*.*'), LongInt(@FData));
      If FindH <> INVALID_HANDLE Then OneEntry;
    End
    Else
    Begin
      If FindNextFileA(FindH, LongInt(@FData)) <> 0 Then OneEntry
      Else
      Begin
        Dummy := FindClose(FindH);
        FindH := INVALID_HANDLE;
      End;
    End;
    If Not Busy Then Exit;
  Until GetTickCount - T0 > 60;
  StatusS := 'Recherche dans ' + CurDir + '...  (' + IStr(NRes) + ' trouv'#233'(s))';
  Ensure;
  PaintList;
  Dummy := PostMessageA(Wnd, WM_STEP, 0, 0);
End;

{ ==================================================================== }
{ Recherche d'ordinateur                                                }
{ ==================================================================== }

Procedure FindComputer;
Var N, Me : String; H, K : LongInt; L, A : PLng; B : PByt; Sz : LongInt;
Begin
  N := TrimS(CtlText(NameW));
  If N = '' Then
  Begin
    Dummy := Ask('Tapez le nom de l''ordinateur '#224' rechercher.', 'Rechercher : Ordinateur',
                 MB_OK Or MB_ICONINFO);
    Exit;
  End;
  ClearRes;
  StatusS := 'Recherche de ' + N + '...';
  PaintList;
  { le poste lui-meme }
  Sz := 255;
  ClipBuf[0] := 0;
  Dummy := GetComputerNameA(LongInt(@ClipBuf), LongInt(@Sz));
  Me := GetZ(LongInt(@ClipBuf));
  If (Me <> '') And (UpS(Me) = UpS(N)) Then
    If AddRes(Me, 'Poste de travail', 0, 0, $0100007F) Then ;
  If NRes = 0 Then
  Begin
    H := gethostbyname(Z(N));
    If H <> 0 Then
    Begin
      L := PLng(H); B := PByt(L^);
      Me := GetZ(L^);
      If Me = '' Then Me := N;
      L := PLng(H + 12);
      K := 0;
      If L^ <> 0 Then
        Repeat
          A := PLng(L^ + K * 4);
          If A^ = 0 Then Break;
          A := PLng(A^);
          If AddRes(Me, 'R'#233'seau (DNS)', 0, 0, A^) Then ;
          Inc(K);
        Until K >= 8;
    End;
  End;
  CountStatus;
  If NRes = 0 Then StatusS := 'Ordinateur introuvable : ' + N;
  Refresh;
End;

Procedure StartSearch;
Var D, T : String;
Begin
  If Busy Then Exit;
  If CompMode Then
  Begin
    FindComputer;
    Exit;
  End;
  ClearRes;
  SetPats(CtlText(NameW));
  T := CtlText(TextW);
  If CaseOn Then Needle := T Else Needle := UpAnsi(T);
  SubOn := SendMessageA(SubW, BM_GETCHECK, 0, 0) <> 0;
  D := TrimS(CtlText(DirW));
  If D = '' Then D := 'C:\';
  If (Length(D) = 2) And (D[2] = ':') Then D := D + '\';
  If (Length(D) > 3) And (D[Length(D)] = '\') Then D := Copy(D, 1, Length(D) - 1);
  { plusieurs dossiers separes par ; }
  D := D + ';';
  T := '';
  NDirs := 0;
  While Pos(';', D) > 0 Do
  Begin
    T := TrimS(Copy(D, 1, Pos(';', D) - 1));
    Delete(D, 1, Pos(';', D));
    If T <> '' Then PushDir(T);
  End;
  NScan := 0;
  FindH := INVALID_HANDLE;
  SetBusy(True);
  StatusS := 'Recherche en cours...';
  Refresh;
  Dummy := PostMessageA(Wnd, WM_STEP, 0, 0);
End;

Procedure NewSearch;
Begin
  If Busy Then StopSearch('');
  ClearRes;
  SetText(NameW, '');
  If Not CompMode Then SetText(TextW, '');
  StatusS := '';
  Refresh;
  Dummy := SetFocus(NameW);
End;

{ ==================================================================== }
{ Commandes                                                             }
{ ==================================================================== }

Procedure CopyText(S : String);
Var H, K : LongInt; P : PByt;
Begin
  S := Disp(S);
  If OpenClipboard(Wnd) = 0 Then Exit;
  Dummy := EmptyClipboard;
  H := GlobalAlloc(0, Length(S) + 1);
  If H <> 0 Then
  Begin
    For K := 1 To Length(S) Do Begin P := PByt(H + K - 1); P^ := Ord(S[K]); End;
    P := PByt(H + Length(S)); P^ := 0;
    Dummy := SetClipboardData(CF_TEXT, H);
  End;
  Dummy := CloseClipboard;
End;

Procedure OpenSel(Folder : Boolean);
Var P : String;
Begin
  If (Sel < 0) Or (Sel >= NRes) Then Exit;
  If CompMode Then
  Begin
    Dummy := Ask(Res[Sel]^.Name + #10'Adresse IP : ' + DateStr(Sel) + #10'Emplacement : ' + Res[Sel]^.Dir,
                 'Ordinateur', MB_OK Or MB_ICONINFO);
    Exit;
  End;
  If Folder Then P := Res[Sel]^.Dir Else P := FullPath(Sel);
  If ShellExecuteA(Wnd, Z2('open'), Z(P), 0, 0, 1) <= 32 Then
    Dummy := Ask('Impossible d''ouvrir ' + P + '.', 'Rechercher', MB_OK Or MB_ICONERROR);
End;

Procedure SaveResults;
Var H, I, W : LongInt; S : String;
Begin
  If NRes = 0 Then Exit;
  H := CreateFileA(Z('C:\RECHERCH.TXT'), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  For I := 0 To NRes - 1 Do
  Begin
    If CompMode Then S := Res[I]^.Name + #9 + DateStr(I) Else S := FullPath(I) + #9 + IStr(Res[I]^.Size) + #9 + DateStr(I);
    S := Disp(S) + #13#10;
    Dummy := WriteFile(H, LongInt(@S[1]), Length(S), LongInt(@W), 0);
  End;
  Dummy := CloseHandle(H);
  Dummy := Ask('R'#233'sultats enregistr'#233's dans C:\RECHERCH.TXT.', 'Rechercher', MB_OK Or MB_ICONINFO);
End;

Procedure Browse;
Var M, K, D, R : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  M := CreatePopupMenu;
  D := GetLogicalDrives;
  For K := 2 To 25 Do
    If (D And (1 Shl K)) <> 0 Then MItem(M, CM_DRIVE + K, Chr(65 + K) + ':\');
  If (D And 1) <> 0 Then MItem(M, CM_DRIVE, 'A:\');
  MItem(M, 0, '');
  MItem(M, CM_DRIVE + 26, 'C:\WINDOWS');
  MItem(M, CM_DRIVE + 27, 'Tous les disques durs');
  Rc[0] := CW - PanW - 100; Rc[1] := 126;
  Dummy := ClientToScreen(Wnd, LongInt(@Rc));
  R := TrackPopupMenu(M, $100, Rc[0], Rc[1], 0, Wnd, 0);
  Dummy := DestroyMenu(M);
  If R >= CM_DRIVE Then
  Begin
    K := R - CM_DRIVE;
    If K < 26 Then SetText(DirW, Chr(65 + K) + ':\')
    Else If K = 26 Then SetText(DirW, 'C:\WINDOWS')
    Else
    Begin
      { C: et les suivants }
      Rc[2] := 0;
      For K := 2 To 25 Do
        If (D And (1 Shl K)) <> 0 Then
        Begin
          If Rc[2] = 0 Then SetText(DirW, Chr(65 + K) + ':\')
          Else SetText(DirW, CtlText(DirW) + ';' + Chr(65 + K) + ':\');
          Rc[2] := 1;
        End;
    End;
  End;
End;

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    ID_FIND : StartSearch;
    ID_STOP : If Busy Then StopSearch('recherche interrompue');
    ID_NEW, CM_NEWSRCH : NewSearch;
    ID_BROWSE : Browse;
    CM_OPEN : OpenSel(False);
    CM_OPENDIR : OpenSel(True);
    CM_COPYPATH : If (Sel >= 0) And (Sel < NRes) Then If CompMode Then CopyText(Res[Sel]^.Name)
                  Else CopyText(FullPath(Sel));
    CM_SAVE : SaveResults;
    CM_CLOSE : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_CASE : Begin CaseOn := Not CaseOn; MCheck(MOpts, CM_CASE, CaseOn); End;
    CM_ABOUT : Dummy := Ask('Rechercher de Pasdows 95'#10#10'Recherche de fichiers et dossiers (noms, mod'#232'les, ' +
                            'texte contenu) et d''ordinateurs (DNS). Programme '#233'crit en Pascal et compil'#233' par WPC.',
                            #192' propos de Rechercher', MB_OK Or MB_ICONINFO);
  End;
End;

Procedure ContextMenu(X, Y : LongInt);
Var Rc : Array[0..1] Of LongInt; R : LongInt;
Begin
  Rc[0] := X; Rc[1] := Y;
  Dummy := ClientToScreen(Wnd, LongInt(@Rc));
  R := TrackPopupMenu(CtxMenu, $100, Rc[0], Rc[1], 0, Wnd, 0);
  If R > 0 Then Command(R);
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, I, X, Y, C, X1, X2 : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then
        Begin
          CW := MinI(MaxI(Rc[2], 420), 1024); CH := MinI(Rc[3], 768);
          If VSb <> 0 Then
          Begin
            Dummy := MoveWindow(VSb, CW - SbW - 1, TopH, SbW, CH - StH - TopH - 1, 1);
            X := CW - PanW;
            Dummy := MoveWindow(FindW, X, 34, PanW - 10, 26, 1);
            Dummy := MoveWindow(StopW, X, 66, PanW - 10, 26, 1);
            Dummy := MoveWindow(NewW, X, 98, PanW - 10, 26, 1);
            Dummy := MoveWindow(NameW, 190, 44, CW - PanW - 210, 22, 1);
            If Not CompMode Then
            Begin
              Dummy := MoveWindow(TextW, 190, 74, CW - PanW - 210, 22, 1);
              Dummy := MoveWindow(DirW, 190, 104, CW - PanW - 306, 22, 1);
              Dummy := MoveWindow(BrowseW, CW - PanW - 110, 103, 90, 24, 1);
            End;
          End;
          Ensure;
          Dummy := InvalidateRect(H, 0, 0);
        End;
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawTop(MemDC);
        DrawList(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_STEP : Step;
    WM_VSCROLL :
      Begin
        Case WP And $FFFF Of
          SB_LINEUP : Dec(Top);
          SB_LINEDOWN : Inc(Top);
          SB_PAGEUP : Top := Top - NRows;
          SB_PAGEDOWN : Top := Top + NRows;
          SB_THUMBPOSITION, SB_THUMBTRACK : Top := (WP Shr 16) And $FFFF;
        End;
        If Top > NRes - NRows Then Top := NRes - NRows;
        If Top < 0 Then Top := 0;
        Refresh;
      End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK, WM_RBUTTONDOWN :
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        If (Y >= TopH) And (Y < TopH + HdrH) And (Msg = WM_LBUTTONDOWN) Then
        Begin
          For C := 0 To NCols - 1 Do
          Begin
            ColRange(C, X1, X2);
            If (X >= X1) And (X < X2) Then
              If SortCol <> C Then
              Begin
                SortCol := C;
                If Not Busy Then SortRes;
                Refresh;
              End;
          End;
        End
        Else If (Y >= TopH + HdrH) And (Y < CH - StH) Then
        Begin
          Dummy := SetFocus(H);
          I := Top + (Y - TopH - HdrH - 1) Div RowH;
          If (I >= 0) And (I < NRes) Then
          Begin
            Sel := I;
            Refresh;
            If Msg = WM_LBUTTONDBLCLK Then OpenSel(False)
            Else If Msg = WM_RBUTTONDOWN Then ContextMenu(X, Y);
          End;
        End;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_UP : Begin If Sel > 0 Then Dec(Sel); Refresh; End;
        VK_DOWN : Begin If Sel < NRes - 1 Then Inc(Sel); Refresh; End;
        VK_HOME : Begin Sel := 0; Refresh; End;
        VK_END : Begin Sel := NRes - 1; Refresh; End;
        VK_PRIOR : Begin Sel := MaxI(0, Sel - NRows); Refresh; End;
        VK_NEXT : Begin Sel := MinI(NRes - 1, Sel + NRows); Refresh; End;
        VK_RETURN : OpenSel(False);
        VK_ESCAPE : If Busy Then StopSearch('recherche interrompue');
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_CLOSE :
      Begin
        If Busy Then StopSearch('');
        Dummy := DestroyWindow(H);
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  Dc, MenuBar, MFile, MHelp, K : LongInt;
  Rc0 : Array[0..3] Of LongInt;
  A : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  CompMode := False;
  For K := 1 To ParamCount Do
  Begin
    A := UpS(ParamStr(K));
    If (A = '/C') Or (A = '-C') Then CompMode := True;
  End;
  NRes := 0; NDirs := 0; Sel := -1; Top := 0; SortCol := 0; VSb := 0; Busy := False; CaseOn := False;
  FindH := INVALID_HANDLE; StatusS := '';
  If CompMode Then Dummy := WSAStartup($101, LongInt(@WsaData));
  CW := 600; CH := 400;
  RegClass('FindWnd', LongInt(@MainProc), CS_DBLCLKS);
  If CompMode Then A := 'Rechercher : Ordinateur' Else A := 'Rechercher : Tous les fichiers';
  Wnd := MainWindow('FindWnd', A, WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MOpts := CreatePopupMenu; MHelp := CreatePopupMenu;
  CtxMenu := CreatePopupMenu;
  If CompMode Then
  Begin
    MItem(MFile, CM_OPEN, '~Propri'#233't'#233's');
    MItem(MFile, CM_COPYPATH, '~Copier le nom');
  End
  Else
  Begin
    MItem(MFile, CM_OPEN, '~Ouvrir');
    MItem(MFile, CM_OPENDIR, 'Ouvrir le ~dossier contenant');
    MItem(MFile, CM_COPYPATH, '~Copier le chemin');
    MItem(CtxMenu, CM_OPEN, '~Ouvrir');
    MItem(CtxMenu, CM_OPENDIR, 'Ouvrir le ~dossier contenant');
    MItem(CtxMenu, 0, '');
    MItem(CtxMenu, CM_COPYPATH, '~Copier le chemin');
  End;
  MItem(MFile, CM_SAVE, '~Enregistrer les r'#233'sultats');
  MItem(MFile, 0, '');
  MItem(MFile, CM_CLOSE, '~Fermer');
  MItem(MOpts, CM_CASE, '~Respecter la casse');
  MItem(MOpts, CM_NEWSRCH, '~Nouvelle recherche');
  MItem(MHelp, CM_ABOUT, #192' ~propos de Rechercher');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MOpts, '~Options');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  NameW := Ctl(Wnd, 'EDIT', '', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 180, 44, 260, 22, ID_NAME);
  If Not CompMode Then
  Begin
    TextW := Ctl(Wnd, 'EDIT', '', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 180, 74, 260, 22, ID_TEXT);
    DirW := Ctl(Wnd, 'EDIT', 'C:\', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 180, 104, 170, 22, ID_DIR);
    BrowseW := Ctl(Wnd, 'BUTTON', 'Parcourir...', WS_TABSTOP, 360, 103, 90, 24, ID_BROWSE);
    SubW := Ctl(Wnd, 'BUTTON', 'Inclure les sous-dossiers', WS_TABSTOP Or BS_AUTOCHECKBOX, 20, 136, 220, 20, ID_SUB);
    Dummy := SendMessageA(SubW, BM_SETCHECK, 1, 0);
  End;
  FindW := Ctl(Wnd, 'BUTTON', 'Rechercher', WS_TABSTOP Or BS_DEFPUSHBUTTON, 470, 34, 120, 26, ID_FIND);
  StopW := Ctl(Wnd, 'BUTTON', 'Arr'#234'ter', WS_TABSTOP, 470, 66, 120, 26, ID_STOP);
  NewW := Ctl(Wnd, 'BUTTON', 'Nouvelle recherche', WS_TABSTOP, 470, 98, 120, 26, ID_NEW);
  VSb := Ctl(Wnd, 'SCROLLBAR', '', 1, CW - SbW - 1, TopH, SbW, CH - StH - TopH - 1, 30);
  Dummy := EnableWindow(StopW, 0);
  Dc := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, 1024, 768);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  { place des controles selon la vraie zone client }
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  Dummy := SendMessageA(Wnd, WM_SIZE, 0, (Rc0[3] Shl 16) Or Rc0[2]);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(NameW);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  ExitProcess(0);
END.
