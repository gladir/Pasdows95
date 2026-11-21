{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: DEFRAG - Defragmenteur de disque de Pasdows 95 (Win32).
}

Program DEFRAG;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\DEFRAG.PAS DEFRAG.EXE

  Comme le Defragmenteur de disque de Windows 95 (Accessoires, Outils
  systeme) : choisir un lecteur (ou DEFRAG C:), l'analyser (pourcentage
  de fragmentation), puis Demarrer ; Pause et Arreter ; la carte des
  clusters montre en direct les donnees optimisees, non optimisees,
  celles qui ne seront pas deplacees, l'espace libre, et les clusters
  lus et ecrits. Parametres : defragmentation complete (fichiers et
  espace libre), fichiers seulement, ou espace libre seulement.

  Le programme utilise les commandes de defragmentation de Windows NT,
  fournies par le noyau de Pasdows pour les volumes FAT12/16/32 :
  CreateFile("\\.\C:"), DeviceIoControl FSCTL_GET_VOLUME_BITMAP (clusters
  occupes), FSCTL_GET_RETRIEVAL_POINTERS (morceaux de chaque fichier) et
  FSCTL_MOVE_FILE (le noyau copie les clusters, refait la chaine de la
  FAT et libere les anciens). Les dossiers et les fichiers systeme
  (IO.SYS, MSDOS.SYS : attribut systeme) ne sont pas deplaces. }

Const
  MaxF = 6000;
  CellW = 7;
  MapX = 8; MapY = 8;
  StPanel = 112;
  WM_STEP = $0401;
  CM_DRIVE = 500; CM_FULL = 601; CM_FILES = 602; CM_FREE = 603; CM_LEGEND = 604;
  ID_START = 10; ID_PAUSE = 11; ID_STOP = 12; ID_DRIVE = 13; ID_SETTINGS = 14; ID_LEGEND = 15;
  { etats des clusters }
  csFree = 0; csFixed = 1; csOk = 2; csFrag = 3; csRead = 4; csWrite = 5;
  ClrFree = $FFFFFF; ClrFixed = $000080; ClrOk = $800000; ClrFrag = $FFFF00; ClrRead = $00C000; ClrWrite = $0000FF;

Type
  PStr = ^String;

Var
  FPath : Array[0..MaxF - 1] Of PStr;
  FFirst, FLen, FFrags : Array[0..MaxF - 1] Of LongInt;
  NF, NDirs : LongInt;
  Dirs : Array[0..1999] Of PStr;
  St : PByt;                                  { un octet par cluster }
  NClus, Drive, Phase, Method, Cur, CurV, Steps, StepsDone, MapCols, MapRows, PerCell : LongInt;
  VolH : LongInt;
  Paused, Busy, ShowLegend : Boolean;
  CW, CH, MemDC, MemBmp, FontS : LongInt;
  StartW, PauseW, StopW, DriveW, SetW, LegW : LongInt;
  MSet : LongInt;
  StatusS, Status2 : String;
  FData : Array[0..319] Of Byte;
  RpIn : Array[0..1] Of LongInt;
  RpOut : Array[0..2063] Of LongInt;         { 16 + 512 morceaux }
  MvIn : Array[0..7] Of LongInt;
  BmOut : PByt;
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

Function DeviceIoControl(H, Code, PIn, NIn, POut, NOut, PRet, Ov : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'DeviceIoControl';
Function GetDriveTypeA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetDriveTypeA';
Function GetLastError : LongInt; stdcall; external 'kernel32.dll' name 'GetLastError';
Function CreateFileA2(Name, Access, Share, Sec, Disp, Flags, Tmpl : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateFileA';

{ ==================================================================== }
{ Carte des clusters                                                    }
{ ==================================================================== }

Function CS(C : LongInt) : LongInt;
Var P : PByt;
Begin
  CS := csFixed;
  If (C < 0) Or (C >= NClus) Then Exit;
  P := PByt(LongInt(St) + C);
  CS := P^;
End;

Procedure SetCS(C, V : LongInt);
Var P : PByt;
Begin
  If (C < 0) Or (C >= NClus) Then Exit;
  P := PByt(LongInt(St) + C);
  P^ := V;
End;

Function MapH : LongInt;
Begin
  MapH := CH - StPanel - MapY - 4;
End;

Procedure Layout;
Var N : LongInt;
Begin
  MapCols := MaxI(1, (CW - 2 * MapX) Div CellW);
  MapRows := MaxI(1, MapH Div CellW);
  N := MapCols * MapRows;
  If NClus > 0 Then PerCell := (NClus + N - 1) Div N Else PerCell := 1;
  If PerCell < 1 Then PerCell := 1;
End;

Function StateColor(S : LongInt) : LongInt;
Begin
  Case S Of
    csFixed : StateColor := ClrFixed;
    csOk : StateColor := ClrOk;
    csFrag : StateColor := ClrFrag;
    csRead : StateColor := ClrRead;
    csWrite : StateColor := ClrWrite;
  Else
    StateColor := ClrFree;
  End;
End;

{ couleur d'une case : lecture/ecriture, puis fragmente, fixe, optimise,
  libre (une case = PerCell clusters) }
Function CellState(I : LongInt) : LongInt;
Var C, E, S, R, Used : LongInt;
Begin
  C := I * PerCell; E := MinI(NClus, C + PerCell);
  R := csFree; Used := 0;
  While C < E Do
  Begin
    S := CS(C);
    If (S = csRead) Or (S = csWrite) Then
    Begin
      CellState := S;
      Exit;
    End;
    If S = csFrag Then R := csFrag
    Else If (S = csFixed) And (R <> csFrag) Then R := csFixed
    Else If (S = csOk) And (R = csFree) Then R := csOk;
    If S <> csFree Then Inc(Used);
    Inc(C);
  End;
  CellState := R;
End;

Procedure DrawCell(Dc, I : LongInt);
Var X, Y, S : LongInt;
Begin
  If (I < 0) Or (I >= MapCols * MapRows) Then Exit;
  X := MapX + (I Mod MapCols) * CellW; Y := MapY + (I Div MapCols) * CellW;
  If I * PerCell >= NClus Then
  Begin
    Bar(Dc, X, Y, X + CellW, Y + CellW, ClrFace);
    Exit;
  End;
  S := CellState(I);
  Bar(Dc, X, Y, X + CellW - 1, Y + CellW - 1, StateColor(S));
  If S = csFixed Then Bar(Dc, X + 2, Y + 2, X + 4, Y + 4, ClrHi);
  Bar(Dc, X + CellW - 1, Y, X + CellW, Y + CellW, ClrShadow);
  Bar(Dc, X, Y + CellW - 1, X + CellW, Y + CellW, ClrShadow);
End;

Procedure LegendItem(Dc, X, Y, C : LongInt; S : String; Fixed : Boolean);
Begin
  Bar(Dc, X, Y + 4, X + 10, Y + 14, C);
  If Fixed Then Bar(Dc, X + 3, Y + 7, X + 6, Y + 10, ClrHi);
  Bevel(Dc, X - 1, Y + 3, X + 11, Y + 15, False);
  Txt(Dc, X + 16, Y, S, ClrDark, ClrFace);
End;

Procedure ClipTxt(Dc, X, Y, W : LongInt; S : String);
Begin
  If Length(S) * 8 > W Then S := Copy(S, 1, MaxI(0, W Div 8 - 1)) + #187;
  Txt(Dc, X, Y, S, ClrDark, ClrFace);
End;

Procedure DrawPanel(Dc : LongInt);
Var Y, W, P, TW : LongInt;
Begin
  Y := CH - StPanel;
  TW := CW - 212;
  Bar(Dc, 0, Y, CW - 200, CH, ClrFace);
  If ShowLegend Then
  Begin
    LegendItem(Dc, 12, Y + 4, ClrOk, 'Optimis'#233, False);
    LegendItem(Dc, 124, Y + 4, ClrFrag, 'Non optimis'#233, False);
    LegendItem(Dc, 252, Y + 4, ClrFixed, 'Non d'#233'pla'#231'able', True);
    LegendItem(Dc, 12, Y + 22, ClrFree, 'Espace libre', False);
    LegendItem(Dc, 124, Y + 22, ClrRead, 'Lecture', False);
    LegendItem(Dc, 252, Y + 22, ClrWrite, #201'criture', False);
    Y := Y + 42;
  End
  Else Y := Y + 6;
  ClipTxt(Dc, 12, Y, TW, StatusS);
  { barre de progression et pourcentage }
  If Steps > 0 Then P := MinI(100, (StepsDone * 100) Div Steps) Else P := 0;
  If Phase = 4 Then P := 100;
  Bevel(Dc, 12, Y + 20, TW - 48, Y + 38, False);
  W := ((TW - 64) * P) Div 100;
  Bar(Dc, 14, Y + 22, TW - 50, Y + 36, ClrFace);
  Bar(Dc, 14, Y + 22, 14 + W, Y + 36, ClrSel);
  If Phase >= 2 Then Txt(Dc, TW - 40, Y + 21, IStr(P) + ' %', ClrDark, ClrFace);
  ClipTxt(Dc, 12, Y + 42, TW, Status2);
End;

Procedure DrawAll(Dc : LongInt);
Var I : LongInt;
Begin
  Bar(Dc, 0, 0, CW, CH, ClrFace);
  Bevel(Dc, MapX - 2, MapY - 2, MapX + MapCols * CellW + 2, MapY + MapRows * CellW + 2, False);
  For I := 0 To MapCols * MapRows - 1 Do DrawCell(Dc, I);
  DrawPanel(Dc);
End;

Procedure Show(Y1, Y2 : LongInt);
Var Dc : LongInt;
Begin
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, Y1, CW - 200, Y2 - Y1, MemDC, 0, Y1, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

Procedure ShowPanel;
Begin
  DrawPanel(MemDC);
  Show(CH - StPanel, CH);
End;

{ redessiner les cases des clusters C..C+N-1 }
Procedure ShowRange(C, N : LongInt);
Var I, I1, I2, Y1, Y2 : LongInt;
Begin
  If (N <= 0) Or (PerCell <= 0) Then Exit;
  I1 := C Div PerCell; I2 := (C + N - 1) Div PerCell;
  For I := I1 To I2 Do DrawCell(MemDC, I);
  Y1 := MapY + (I1 Div MapCols) * CellW; Y2 := MapY + (I2 Div MapCols + 1) * CellW;
  Show(Y1, Y2);
End;

{ ==================================================================== }
{ Analyse                                                               }
{ ==================================================================== }

Procedure ClearFiles;
Var I : LongInt;
Begin
  For I := 0 To NF - 1 Do FreeMem(FPath[I], Length(FPath[I]^) + 2);
  NF := 0;
  For I := 0 To NDirs - 1 Do FreeMem(Dirs[I], 256);
  NDirs := 0;
End;

Function DriveRoot : String;
Begin
  DriveRoot := Chr(65 + Drive) + ':\';
End;

{ morceaux du fichier I : premier LCN, nombre de clusters, de morceaux
  (avec les LCN de chaque morceau dans RpOut) ; False si vide }
Function Extents(H : LongInt; Var First, Len, Frags : LongInt) : Boolean;
Var R, K, N, Vcn, PrevV : LongInt; More : Boolean;
Begin
  Extents := False;
  First := -1; Len := 0; Frags := 0; Vcn := 0;
  Repeat
    RpIn[0] := Vcn; RpIn[1] := 0;
    R := 0;
    More := False;
    If DeviceIoControl(H, $90073, LongInt(@RpIn), 8, LongInt(@RpOut), SizeOf(RpOut), LongInt(@R), 0) = 0 Then
    Begin
      If GetLastError <> 234 Then Exit;
      More := True;
    End;
    N := RpOut[0];
    PrevV := RpOut[2];
    For K := 0 To N - 1 Do
    Begin
      If First < 0 Then First := RpOut[6 + K * 4];
      Len := Len + RpOut[4 + K * 4] - PrevV;
      PrevV := RpOut[4 + K * 4];
      Inc(Frags);
    End;
    Vcn := PrevV;
    If N = 0 Then More := False;
  Until Not More;
  Extents := Len > 0;
End;

{ marquer les clusters du fichier (etat S) d'apres RpOut, ou tout }
Procedure MarkFile(H, S : LongInt);
Var R, K, N, Vcn, PrevV, L, J : LongInt; More : Boolean;
Begin
  Vcn := 0;
  Repeat
    RpIn[0] := Vcn; RpIn[1] := 0;
    More := False;
    If DeviceIoControl(H, $90073, LongInt(@RpIn), 8, LongInt(@RpOut), SizeOf(RpOut), LongInt(@R), 0) = 0 Then
    Begin
      If GetLastError <> 234 Then Exit;
      More := True;
    End;
    N := RpOut[0];
    PrevV := RpOut[2];
    For K := 0 To N - 1 Do
    Begin
      L := RpOut[6 + K * 4];
      For J := 0 To RpOut[4 + K * 4] - PrevV - 1 Do SetCS(L + J, S);
      PrevV := RpOut[4 + K * 4];
    End;
    Vcn := PrevV;
    If N = 0 Then More := False;
  Until Not More;
End;

Function OpenF(P : String) : LongInt;
Begin
  OpenF := CreateFileA(Z(P), GENERIC_READ, 3, 0, OPEN_EXISTING, 0, 0);
End;

Procedure AddDir(P : String);
Var Q : PStr;
Begin
  If NDirs >= 2000 Then Exit;
  GetMem(Q, 256);
  Q^ := P;
  Dirs[NDirs] := Q;
  Inc(NDirs);
End;

{ un dossier : ses fichiers dans la liste, ses sous-dossiers a suivre }
Procedure ScanDir(D : String);
Var H, A, Fi, F, L, Fr, Hf : LongInt; N, P : String; L4 : PLng; Q : PStr;
Begin
  If D[Length(D)] <> '\' Then D := D + '\';
  H := FindFirstFileA(Z(D + '*.*'), LongInt(@FData));
  If H = INVALID_HANDLE Then Exit;
  Repeat
    N := GetZ(LongInt(@FData[44]));
    L4 := PLng(LongInt(@FData[0])); A := L4^;
    P := D + N;
    If (N <> '.') And (N <> '..') Then
    Begin
      If (A And $10) <> 0 Then AddDir(P)
      Else If ((A And 4) = 0) And (NF < MaxF) Then
      Begin
        Hf := OpenF(P);
        If Hf <> INVALID_HANDLE Then
        Begin
          If Extents(Hf, F, L, Fr) Then
          Begin
            Fi := NF;
            GetMem(Q, Length(P) + 2);
            Q^ := P;
            FPath[Fi] := Q; FFirst[Fi] := F; FLen[Fi] := L; FFrags[Fi] := Fr;
            Inc(NF);
            If Fr > 1 Then MarkFile(Hf, csFrag) Else MarkFile(Hf, csOk);
          End;
          Dummy := CloseHandle(Hf);
        End;
      End;
    End;
  Until FindNextFileA(H, LongInt(@FData)) = 0;
  Dummy := FindClose(H);
End;

Function LoadBitmap : Boolean;
Var R, K, B : LongInt; In0 : Array[0..1] Of LongInt; P : PByt; Lp : PLng;
Begin
  LoadBitmap := False;
  If VolH <> INVALID_HANDLE Then Dummy := CloseHandle(VolH);
  VolH := CreateFileA(Z('\\.\' + Chr(65 + Drive) + ':'), GENERIC_READ, 3, 0, OPEN_EXISTING, 0, 0);
  If VolH = INVALID_HANDLE Then Exit;
  In0[0] := 0; In0[1] := 0;
  If BmOut = Nil Then BmOut := PByt(VirtualAlloc(0, 1048576 + 64, $3000, 4));
  If DeviceIoControl(VolH, $9006F, LongInt(@In0), 8, LongInt(BmOut), 1048576 + 16, LongInt(@R), 0) = 0 Then Exit;
  Lp := PLng(LongInt(BmOut) + 8);
  NClus := Lp^;
  If St <> Nil Then Dummy := VirtualFree(LongInt(St), 0, $8000);
  St := PByt(VirtualAlloc(0, NClus + 16, $3000, 4));
  If St = Nil Then Exit;
  For K := 0 To NClus - 1 Do
  Begin
    P := PByt(LongInt(BmOut) + 16 + K Shr 3);
    B := P^;
    If (B And (1 Shl (K And 7))) <> 0 Then SetCS(K, csFixed) Else SetCS(K, csFree);
  End;
  LoadBitmap := True;
End;

Function UsedPct : LongInt;
Var K, U : LongInt;
Begin
  U := 0;
  For K := 0 To NClus - 1 Do If CS(K) <> csFree Then Inc(U);
  If NClus > 0 Then UsedPct := (U * 100) Div NClus Else UsedPct := 0;
End;

Function FragPct : LongInt;
Var I, T, Fr : LongInt;
Begin
  T := 0; Fr := 0;
  For I := 0 To NF - 1 Do
  Begin
    T := T + FLen[I];
    If FFrags[I] > 1 Then Fr := Fr + FLen[I];
  End;
  If T > 0 Then FragPct := (Fr * 100 + T - 1) Div T Else FragPct := 0;
End;

Function FragCount : LongInt;
Var I, N : LongInt;
Begin
  N := 0;
  For I := 0 To NF - 1 Do If FFrags[I] > 1 Then Inc(N);
  FragCount := N;
End;

Procedure SetButtons;
Begin
  Dummy := EnableWindow(StartW, Ord(Not Busy And (Phase = 1)));
  Dummy := EnableWindow(PauseW, Ord(Busy));
  Dummy := EnableWindow(StopW, Ord(Busy));
  Dummy := EnableWindow(DriveW, Ord(Not Busy));
  Dummy := EnableWindow(SetW, Ord(Not Busy));
  If Paused Then SetText(PauseW, 'Reprendre') Else SetText(PauseW, 'Pause');
End;

Procedure Analyze;
Var D : String; Dc : LongInt;
Begin
  ClearFiles;
  Phase := 0; Steps := 0; StepsDone := 0;
  StatusS := 'Analyse du lecteur ' + Chr(65 + Drive) + ':...';
  Status2 := '';
  Dummy := SetWindowTextA(Wnd, Z(Disp('D'#233'fragmentation du lecteur ' + Chr(65 + Drive) + ':')));
  If Not LoadBitmap Then
  Begin
    NClus := 0;
    Layout;
    StatusS := 'Le lecteur ' + Chr(65 + Drive) + ': ne peut pas '#234'tre d'#233'fragment'#233'.';
    Status2 := 'Seuls les disques FAT (12, 16 et 32) peuvent l'''#234'tre.';
    DrawAll(MemDC);
    Dummy := InvalidateRect(Wnd, 0, 0);
    SetButtons;
    Exit;
  End;
  Layout;
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
  { parcours des dossiers (une pile) }
  AddDir(DriveRoot);
  While NDirs > 0 Do
  Begin
    Dec(NDirs);
    D := Dirs[NDirs]^;
    FreeMem(Dirs[NDirs], 256);
    ScanDir(D);
  End;
  Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
  Phase := 1;
  StatusS := 'Le lecteur ' + Chr(65 + Drive) + ': est fragment'#233' '#224' ' + IStr(FragPct) + ' %.';
  Status2 := IStr(NF) + ' fichiers, dont ' + IStr(FragCount) + ' fragment'#233's ; ' + IStr(UsedPct) +
             ' % du disque occup'#233' (' + IStr(NClus) + ' clusters).';
  DrawAll(MemDC);
  Dummy := InvalidateRect(Wnd, 0, 0);
  SetButtons;
End;

{ ==================================================================== }
{ Defragmentation                                                       }
{ ==================================================================== }

{ premiere suite d'au moins N clusters libres a partir de From (Before :
  limite) ; -1 si aucune }
Function FindFree(From, N, Before : LongInt) : LongInt;
Var C, Run : LongInt;
Begin
  FindFree := -1;
  Run := 0;
  C := From;
  While C < Before Do
  Begin
    If CS(C) = csFree Then
    Begin
      Inc(Run);
      If Run >= N Then
      Begin
        FindFree := C - N + 1;
        Exit;
      End;
    End
    Else Run := 0;
    Inc(C);
  End;
End;

Function FreeRun(C : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  While (C + N < NClus) And (CS(C + N) = csFree) Do Inc(N);
  FreeRun := N;
End;

{ deplacer le fichier I vers les clusters libres T.. (contigus) }
Var
  OldL, OldN : Array[0..511] Of LongInt;

Function MoveFile(I, T : LongInt) : Boolean;
Var H, Vcn, N, R, K, J, PrevV, NE : LongInt; Ok : Boolean;
Begin
  MoveFile := False;
  H := OpenF(FPath[I]^);
  If H = INVALID_HANDLE Then Exit;
  { anciens morceaux }
  RpIn[0] := 0; RpIn[1] := 0;
  Dummy := DeviceIoControl(H, $90073, LongInt(@RpIn), 8, LongInt(@RpOut), SizeOf(RpOut), LongInt(@R), 0);
  NE := MinI(512, RpOut[0]); PrevV := 0;
  For K := 0 To NE - 1 Do
  Begin
    OldL[K] := RpOut[6 + K * 4];
    OldN[K] := RpOut[4 + K * 4] - PrevV;
    PrevV := RpOut[4 + K * 4];
  End;
  { en lecture, en ecriture }
  For K := 0 To NE - 1 Do
  Begin
    For J := 0 To OldN[K] - 1 Do SetCS(OldL[K] + J, csRead);
    ShowRange(OldL[K], OldN[K]);
  End;
  For K := 0 To FLen[I] - 1 Do SetCS(T + K, csWrite);
  ShowRange(T, FLen[I]);
  Status2 := 'Fichier : ' + FPath[I]^;
  ShowPanel;
  Ok := True;
  Vcn := 0;
  While Vcn < FLen[I] Do
  Begin
    N := MinI(256, FLen[I] - Vcn);
    MvIn[0] := H; MvIn[1] := 0;
    MvIn[2] := Vcn; MvIn[3] := 0;
    MvIn[4] := T + Vcn; MvIn[5] := 0;
    MvIn[6] := N; MvIn[7] := 0;
    If DeviceIoControl(VolH, $90074, LongInt(@MvIn), 28, 0, 0, LongInt(@R), 0) = 0 Then
    Begin
      Ok := False;
      Break;
    End;
    Vcn := Vcn + N;
  End;
  { etat final }
  For K := 0 To NE - 1 Do
    For J := 0 To OldN[K] - 1 Do SetCS(OldL[K] + J, csFree);
  For K := 0 To FLen[I] - 1 Do SetCS(T + K, csFree);
  If Ok Then
  Begin
    For K := 0 To FLen[I] - 1 Do SetCS(T + K, csOk);
    FFirst[I] := T; FFrags[I] := 1;
  End
  Else
  Begin
    Dummy := Extents(H, FFirst[I], J, FFrags[I]);
    If FFrags[I] > 1 Then MarkFile(H, csFrag) Else MarkFile(H, csOk);
  End;
  Dummy := CloseHandle(H);
  For K := 0 To NE - 1 Do ShowRange(OldL[K], OldN[K]);
  ShowRange(T, FLen[I]);
  MoveFile := Ok;
End;

{ fichiers dans l'ordre du disque (pour regrouper l'espace libre) }
Procedure SortByFirst;
Var I, J, T : LongInt; P : PStr;
Begin
  For I := 1 To NF - 1 Do
  Begin
    J := I;
    While (J > 0) And (FFirst[J - 1] > FFirst[J]) Do
    Begin
      P := FPath[J]; FPath[J] := FPath[J - 1]; FPath[J - 1] := P;
      T := FFirst[J]; FFirst[J] := FFirst[J - 1]; FFirst[J - 1] := T;
      T := FLen[J]; FLen[J] := FLen[J - 1]; FLen[J - 1] := T;
      T := FFrags[J]; FFrags[J] := FFrags[J - 1]; FFrags[J - 1] := T;
      Dec(J);
    End;
  End;
End;

Procedure Finish(Msg : String);
Begin
  Busy := False; Paused := False;
  Phase := 4;
  StatusS := Msg;
  Status2 := 'Le lecteur ' + Chr(65 + Drive) + ': est fragment'#233' '#224' ' + IStr(FragPct) + ' %.';
  SetButtons;
  ShowPanel;
  Dummy := InvalidateRect(Wnd, 0, 0);
  If Ask('La d'#233'fragmentation du lecteur ' + Chr(65 + Drive) + ': est termin'#233'e.'#10#10 +
         'Voulez-vous quitter le D'#233'fragmenteur de disque ?', 'D'#233'fragmenteur de disque',
         MB_YESNO Or MB_ICONQUESTION) = IDYES Then Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0)
  Else
  Begin
    Phase := 1;
    SetButtons;
  End;
End;

{ un pas : un fichier }
Procedure Step;
Var T, I, Run, Best : LongInt;
Begin
  If Not Busy Or Paused Then Exit;
  If Phase = 2 Then
  Begin
    { fichiers fragmentes : vers la premiere place libre assez grande }
    While (Cur < NF) And (FFrags[Cur] <= 1) Do Inc(Cur);
    If Cur >= NF Then
    Begin
      If Method = 1 Then
      Begin
        Finish('D'#233'fragmentation termin'#233'e.');
        Exit;
      End;
      Phase := 3; Cur := 0; CurV := 0;
      SortByFirst;
      StatusS := 'Regroupement de l''espace libre...';
    End
    Else
    Begin
      StatusS := 'D'#233'fragmentation des fichiers...';
      T := FindFree(0, FLen[Cur], NClus);
      If T >= 0 Then Dummy := MoveFile(Cur, T);
      Inc(Cur); Inc(StepsDone);
    End;
  End
  Else If Phase = 3 Then
  Begin
    { regrouper : remplir chaque trou avec le premier fichier suivant qui
      y tient }
    While (CurV < NClus) And (CS(CurV) <> csFree) Do Inc(CurV);
    If CurV >= NClus Then
    Begin
      Finish('D'#233'fragmentation termin'#233'e.');
      Exit;
    End;
    Run := FreeRun(CurV);
    Best := -1;
    For I := 0 To NF - 1 Do
      If (FFirst[I] > CurV) And (FFrags[I] <= 1) And (FLen[I] <= Run) Then
      Begin
        Best := I;
        Break;
      End;
    If Best < 0 Then
    Begin
      { rien ne tient dans ce trou : le suivant }
      CurV := CurV + Run;
      StepsDone := Steps - (Steps * (NClus - CurV)) Div MaxI(1, NClus) Div 2;
    End
    Else
    Begin
      If MoveFile(Best, CurV) Then CurV := CurV + FLen[Best] Else FFrags[Best] := 2;
      Inc(StepsDone);
    End;
  End;
  If StepsDone > Steps Then StepsDone := Steps;
  ShowPanel;
  Dummy := PostMessageA(Wnd, WM_STEP, 0, 0);
End;

Procedure StartDefrag;
Begin
  If Busy Or (Phase <> 1) Then Exit;
  Busy := True; Paused := False;
  Cur := 0; CurV := 0; StepsDone := 0;
  If Method = 2 Then
  Begin
    Phase := 3;
    SortByFirst;
    Steps := NF;
  End
  Else
  Begin
    Phase := 2;
    Steps := FragCount;
    If Method = 0 Then Steps := Steps + NF;
  End;
  If Steps = 0 Then Steps := 1;
  SetButtons;
  Dummy := PostMessageA(Wnd, WM_STEP, 0, 0);
End;

{ ==================================================================== }
{ Fenetre                                                               }
{ ==================================================================== }

Procedure ChooseDrive;
Var M, K, R, D, T : LongInt; Rc : Array[0..1] Of LongInt; S : String;
Begin
  M := CreatePopupMenu;
  D := GetLogicalDrives;
  For K := 0 To 25 Do
    If (D And (1 Shl K)) <> 0 Then
    Begin
      S := Chr(65 + K) + ':\';
      T := GetDriveTypeA(Z(S));
      If T = 2 Then MItem(M, CM_DRIVE + K, 'Lecteur ' + Chr(65 + K) + ': (disquette)')
      Else If T = 3 Then MItem(M, CM_DRIVE + K, 'Lecteur ' + Chr(65 + K) + ': (disque dur)');
    End;
  Rc[0] := CW - 196; Rc[1] := CH - StPanel + 4 + 3 * 30;
  Dummy := ClientToScreen(Wnd, LongInt(@Rc));
  R := TrackPopupMenu(M, $100, Rc[0], Rc[1], 0, Wnd, 0);
  Dummy := DestroyMenu(M);
  If R >= CM_DRIVE Then
  Begin
    Drive := R - CM_DRIVE;
    Analyze;
  End;
End;

Procedure ChooseMethod;
Var M, R : LongInt; Rc : Array[0..1] Of LongInt;
Begin
  M := CreatePopupMenu;
  MItem(M, CM_FULL, 'D'#233'fragmentation ~compl'#232'te (fichiers et espace libre)');
  MItem(M, CM_FILES, 'D'#233'fragmenter les ~fichiers seulement');
  MItem(M, CM_FREE, 'Regrouper l''~espace libre seulement');
  MCheck(M, CM_FULL, Method = 0); MCheck(M, CM_FILES, Method = 1); MCheck(M, CM_FREE, Method = 2);
  Rc[0] := CW - 196; Rc[1] := CH - StPanel + 4 + 4 * 30;
  Dummy := ClientToScreen(Wnd, LongInt(@Rc));
  R := TrackPopupMenu(M, $100, Rc[0], Rc[1], 0, Wnd, 0);
  Dummy := DestroyMenu(M);
  If (R >= CM_FULL) And (R <= CM_FREE) Then Method := R - CM_FULL;
End;

Procedure Relayout;
Var X, Y : LongInt;
Begin
  X := CW - 192; Y := CH - StPanel + 2;
  Dummy := MoveWindow(StartW, X, Y, 90, 26, 1);
  Dummy := MoveWindow(PauseW, X + 96, Y, 90, 26, 1);
  Dummy := MoveWindow(StopW, X, Y + 30, 90, 26, 1);
  Dummy := MoveWindow(LegW, X + 96, Y + 30, 90, 26, 1);
  Dummy := MoveWindow(DriveW, X, Y + 60, 186, 26, 1);
  Dummy := MoveWindow(SetW, X, Y + 90, 186, 22, 1);
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 300) And (Rc[3] > 200) Then
        Begin
          CW := MinI(Rc[2], 1024); CH := MinI(Rc[3], 768);
          Layout;
          If StartW <> 0 Then Relayout;
          DrawAll(MemDC);
          Dummy := InvalidateRect(H, 0, 0);
        End;
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_STEP : Step;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_START : StartDefrag;
        ID_PAUSE :
          Begin
            Paused := Not Paused;
            If Paused Then StatusS := 'D'#233'fragmentation interrompue (Pause).'
            Else Dummy := PostMessageA(H, WM_STEP, 0, 0);
            SetButtons;
            ShowPanel;
          End;
        ID_STOP :
          If Ask('Voulez-vous arr'#234'ter la d'#233'fragmentation ?', 'D'#233'fragmenteur de disque',
                 MB_YESNO Or MB_ICONQUESTION) = IDYES Then
          Begin
            Busy := False; Paused := False; Phase := 1;
            StatusS := 'D'#233'fragmentation arr'#234't'#233'e. Le lecteur est fragment'#233' '#224' ' + IStr(FragPct) + ' %.';
            Status2 := '';
            SetButtons;
            ShowPanel;
          End;
        ID_DRIVE : ChooseDrive;
        ID_SETTINGS : ChooseMethod;
        ID_LEGEND :
          Begin
            ShowLegend := Not ShowLegend;
            DrawAll(MemDC);
            Dummy := InvalidateRect(H, 0, 0);
          End;
      End;
    WM_CLOSE :
      If Busy And (Ask('La d'#233'fragmentation n''est pas termin'#233'e. Voulez-vous quitter ?',
                       'D'#233'fragmenteur de disque', MB_YESNO Or MB_ICONQUESTION) <> IDYES) Then
      Else Dummy := DestroyWindow(H);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  Dc0, K : LongInt;
  A : String;
  Rc0 : Array[0..3] Of LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  NF := 0; NDirs := 0; St := Nil; BmOut := Nil; NClus := 0; VolH := INVALID_HANDLE;
  Phase := 0; Method := 0; Busy := False; Paused := False; ShowLegend := True; StartW := 0;
  Drive := 2;
  For K := 1 To ParamCount Do
  Begin
    A := UpS(ParamStr(K));
    If (Length(A) >= 2) And (A[2] = ':') And (A[1] >= 'A') And (A[1] <= 'Z') Then Drive := Ord(A[1]) - 65;
  End;
  CW := 600; CH := 400;
  RegClass('DefragWnd', LongInt(@MainProc), 0);
  Wnd := MainWindow('DefragWnd', 'D'#233'fragmenteur de disque', WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, CW, CH,
                    False);
  If Wnd = 0 Then ExitProcess(1);
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
  StartW := Ctl(Wnd, 'BUTTON', 'D'#233'marrer', WS_TABSTOP Or BS_DEFPUSHBUTTON, 0, 0, 90, 26, ID_START);
  PauseW := Ctl(Wnd, 'BUTTON', 'Pause', WS_TABSTOP, 0, 0, 90, 26, ID_PAUSE);
  StopW := Ctl(Wnd, 'BUTTON', 'Arr'#234'ter', WS_TABSTOP, 0, 0, 90, 26, ID_STOP);
  LegW := Ctl(Wnd, 'BUTTON', 'L'#233'gende', WS_TABSTOP, 0, 0, 90, 26, ID_LEGEND);
  DriveW := Ctl(Wnd, 'BUTTON', 'S'#233'lectionner un lecteur...', WS_TABSTOP, 0, 0, 186, 26, ID_DRIVE);
  SetW := Ctl(Wnd, 'BUTTON', 'Param'#232'tres...', WS_TABSTOP, 0, 0, 186, 22, ID_SETTINGS);
  Layout;
  Relayout;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Analyze;
  MsgLoop;
  If VolH <> INVALID_HANDLE Then Dummy := CloseHandle(VolH);
  ExitProcess(0);
END.
