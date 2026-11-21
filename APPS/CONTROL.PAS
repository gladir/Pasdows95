{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: CONTROL - Panneau de configuration de Pasdows 95 (Win32).
}

Program CONTROL;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\CONTROL.PAS CONTROL.EXE

  Comme le Panneau de configuration de Windows 95 (Demarrer,
  Parametres) : une fenetre d'icones, une par applet ; double-clic ou
  Entree l'ouvre. Les applets sont designees comme sous Windows par
  leur fichier .CPL : leur icone vient d'ExtractIcon (SHELL32) et
  Control_RunDLL (SHELL32) ouvre les boites du systeme (Affichage
  desk.cpl, Date/Heure timedate.cpl, Systeme sysdm.cpl, Ajout/
  Suppression de programmes appwiz.cpl, Multimedia mmsys.cpl, Reseau
  netcpl.cpl). Souris et Clavier (main.cpl) et Parametres regionaux
  (intl.cpl) sont des boites de ce programme : SystemParametersInfo,
  SwapMouseButton et le registre (HKCU\Control Panel), comme Windows.
  CONTROL MAIN.CPL, CONTROL MAIN.CPL,@1, CONTROL INTL.CPL, CONTROL
  DESK.CPL... ouvrent directement une applet ; CONTROL MOUSE,
  CONTROL KEYBOARD, CONTROL FONTS aussi. }

Const
  NApp = 11;
  CellW = 104; CellH = 88; StH = 20;
  CM_OPEN = 101; CM_QUIT = 102; CM_REFRESH = 301; CM_ABOUT = 501;
  ID_OK = 1; ID_CANCEL = 2; ID_APPLY = 3;
  ID_SWAP = 10; ID_DBL = 11; ID_SPD = 12; ID_TEST = 13;
  ID_DELAY = 20; ID_RATE = 21; ID_KTEST = 22;
  ID_LANG = 30;
  SBS_HORZ = 0; SB_CTL = 2; BS_GROUPBOX = 7;
  SPI_GETKEYBOARDSPEED = 10; SPI_SETKEYBOARDSPEED = 11;
  SPI_GETKEYBOARDDELAY = 22; SPI_SETKEYBOARDDELAY = 23;
  SPI_SETDOUBLECLICKTIME = 32; SPI_SETMOUSEBUTTONSWAP = 33;
  SPI_GETMOUSESPEED = 112; SPI_SETMOUSESPEED = 113; SM_SWAPBUTTON = 23;
  SB_LEFT = 6; SB_RIGHT = 7;
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

Function ExtractIconA(I, F, N : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ExtractIconA';
Procedure Control_RunDLLA(H, I, Cmd, Show : LongInt); stdcall; external 'shell32.dll' name 'Control_RunDLLA';
Function ShellExecuteA(H, Op, F, P, D, Sh : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ShellExecuteA';
Function DrawIcon(Dc, X, Y, Ic : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DrawIcon';
Function SystemParametersInfoA(A, P, PV, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SystemParametersInfoA';
Function SwapMouseButton(S : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SwapMouseButton';
Function GetDoubleClickTime : LongInt; stdcall; external 'user32.dll' name 'GetDoubleClickTime';
Function GetScrollPos(H, Bar : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetScrollPos';
Function ExitWindowsEx(F, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ExitWindowsEx';
Function GetCommandLineA : LongInt; stdcall; external 'kernel32.dll' name 'GetCommandLineA';
Function CreateDirectoryA(P, S : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateDirectoryA';
Function GetUserDefaultLCID : LongInt; stdcall; external 'kernel32.dll' name 'GetUserDefaultLCID';
Function RegCreateKeyA(K, Sub, PRes : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'RegCreateKeyA';
Function RegSetValueExA(K, Name, Res, Typ, Data, Len : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegSetValueExA';

{ ==================================================================== }
{ Applets                                                               }
{ ==================================================================== }

Type
  TApp = Record
    Name : String[40];
    Cpl : String[16];            { fichier .CPL (ExtractIcon, Control_RunDLL) }
    Idx : LongInt;               { numero de l'applet dans le .CPL }
    Desc : String[100];
    Icon : LongInt;
  End;

Var
  Apps : Array[0..NApp - 1] Of TApp;
  Sel, CW, CH, DlgW, DlgKind : LongInt;
  CtlSwap, CtlDbl, CtlSpd, CtlDelay, CtlRate, CtlLang, CtlTest : LongInt;
  TestOn, Changed : Boolean;
  Langs : Array[0..4] Of String[40];
  LangId : Array[0..4] Of String[8];

Procedure SetApp(I : LongInt; N, C : String; X : LongInt; D : String);
Begin
  Apps[I].Name := N; Apps[I].Cpl := C; Apps[I].Idx := X; Apps[I].Desc := D;
  PutZ(LongInt(@NameZ), C);
  Apps[I].Icon := ExtractIconA(Inst, LongInt(@NameZ), X);
End;

{ dans l'ordre alphabetique, comme le dossier de Windows 95 }
Procedure InitApps;
Begin
  SetApp(0, 'Affichage', 'DESK.CPL', 0, 'Change l''apparence et la r'#233'solution de l'''#233'cran.');
  SetApp(1, 'Ajout/Suppression de programmes', 'APPWIZ.CPL', 0,
         'Installe et supprime des programmes.');
  SetApp(2, 'Clavier', 'MAIN.CPL', 1, 'Change le d'#233'lai et la vitesse de r'#233'p'#233'tition des touches.');
  SetApp(3, 'Contr'#244'le du volume', 'MMSYS.CPL', 1, 'R'#232'gle le volume des sons et de la musique.');
  SetApp(4, 'Date/Heure', 'TIMEDATE.CPL', 0, 'Change la date, l''heure et le fuseau horaire.');
  SetApp(5, 'Multim'#233'dia', 'MMSYS.CPL', 0, 'Propri'#233't'#233's des p'#233'riph'#233'riques audio.');
  SetApp(6, 'Param'#232'tres r'#233'gionaux', 'INTL.CPL', 0, 'Change la langue de Pasdows.');
  SetApp(7, 'Polices', 'MAIN.CPL', 2, 'Ouvre le dossier des polices.');
  SetApp(8, 'R'#233'seau', 'NETCPL.CPL', 0, 'Configuration TCP/IP et lecteurs r'#233'seau.');
  SetApp(9, 'Souris', 'MAIN.CPL', 0, 'Change les boutons, le double-clic et la vitesse du pointeur.');
  SetApp(10, 'Syst'#232'me', 'SYSDM.CPL', 0, 'Informations sur le syst'#232'me et Gestionnaire de p'#233'riph'#233'riques.');
End;

{ ==================================================================== }
{ Fenetre principale : icones                                           }
{ ==================================================================== }

Function Cols : LongInt;
Begin
  Cols := MaxI(1, (CW - 8) Div CellW);
End;

{ Nom coupe aux espaces (et apres '/') en lignes de 13 caracteres }
Function Cut(Var S : String) : String;
Var K : LongInt;
Begin
  If Length(S) <= 13 Then
  Begin
    Cut := S; S := '';
    Exit;
  End;
  K := 14;
  While (K > 1) And (S[K] <> ' ') And (S[K - 1] <> '/') Do Dec(K);
  If K <= 1 Then K := 13 Else If S[K] <> ' ' Then Dec(K);
  Cut := TrimS(Copy(S, 1, K));
  S := TrimS(Copy(S, K + 1, 255));
End;

Procedure PaintAll(Dc : LongInt);
Var I, X, Y, N, Bg, Fg, L : LongInt; A, B : String;
Begin
  Bar(Dc, 0, 0, CW, CH - StH, ClrWin);
  N := Cols;
  For I := 0 To NApp - 1 Do
  Begin
    X := 4 + (I Mod N) * CellW; Y := 6 + (I Div N) * CellH;
    If Apps[I].Icon <> 0 Then Dummy := DrawIcon(Dc, X + (CellW - 32) Div 2, Y, Apps[I].Icon);
    If I = Sel Then Begin Bg := ClrSel; Fg := ClrHi; End Else Begin Bg := ClrWin; Fg := ClrDark; End;
    B := Apps[I].Name;
    For L := 0 To 2 Do
    Begin
      A := Cut(B);
      If (L = 2) And (B <> '') Then A := Copy(A, 1, 9) + '...';
      Txt(Dc, X + (CellW - Length(A) * 8) Div 2, Y + 36 + L * 16, A, Fg, Bg);
    End;
  End;
  { barre d'etat }
  Bar(Dc, 0, CH - StH, CW, CH, ClrFace);
  Bevel(Dc, 2, CH - StH + 2, CW - 2, CH - 1, False);
  If (Sel >= 0) And (Sel < NApp) Then A := Apps[Sel].Desc Else A := IStr(NApp) + ' objet(s)';
  If Length(A) * 8 > CW - 12 Then A := Copy(A, 1, (CW - 12) Div 8);
  Txt(Dc, 6, CH - StH + 3, A, ClrDark, ClrFace);
End;

Procedure Repaint;
Begin
  Dummy := InvalidateRect(Wnd, 0, 0);
End;

Function HitApp(X, Y : LongInt) : LongInt;
Var C, R, I : LongInt;
Begin
  HitApp := -1;
  If (X < 4) Or (Y < 6) Or (Y >= CH - StH) Then Exit;
  C := (X - 4) Div CellW; R := (Y - 6) Div CellH;
  If C >= Cols Then Exit;
  I := R * Cols + C;
  If (I >= 0) And (I < NApp) Then HitApp := I;
End;

Procedure OpenDlg(Kind : LongInt); Forward;

{ Ouvrir l'applet I : boites du systeme par Control_RunDLL, boites de
  ce programme (souris, clavier, regional), dossier des polices }
Procedure OpenApp(I : LongInt);
Var S : String;
Begin
  If (I < 0) Or (I >= NApp) Then Exit;
  S := Apps[I].Cpl;
  If S = 'MAIN.CPL' Then
  Begin
    Case Apps[I].Idx Of
      0 : OpenDlg(1);
      1 : OpenDlg(2);
    Else
      Begin
        Dummy := CreateDirectoryA(Z('C:\WINDOWS\FONTS'), 0);
        Dummy := ShellExecuteA(Wnd, Z2('open'), Z('C:\WINDOWS\FONTS'), 0, 0, 1);
      End;
    End;
    Exit;
  End;
  If S = 'INTL.CPL' Then
  Begin
    OpenDlg(3);
    Exit;
  End;
  If Apps[I].Idx > 0 Then S := S + ',@' + IStr(Apps[I].Idx);
  PutZ(LongInt(@NameZ), S);
  Control_RunDLLA(Wnd, Inst, LongInt(@NameZ), 1);
End;

{ ==================================================================== }
{ Boites Souris, Clavier et Parametres regionaux                        }
{ ==================================================================== }

Procedure SetSb(H, Lo, Hi, P : LongInt);
Begin
  Dummy := SetScrollRange(H, SB_CTL, Lo, Hi, 0);
  Dummy := SetScrollPos(H, SB_CTL, P, 1);
End;

Function DlgCtl(Cls, T : String; Style, X, Y, W, H, Id : LongInt) : LongInt;
Begin
  DlgCtl := Ctl(DlgW, Cls, T, Style, X, Y, W, H, Id);
End;

Procedure Buttons(W, H : LongInt);
Begin
  Dummy := DlgCtl('BUTTON', 'OK', BS_DEFPUSHBUTTON Or WS_TABSTOP, W - 270, H - 34, 80, 24, ID_OK);
  Dummy := DlgCtl('BUTTON', 'Annuler', BS_PUSHBUTTON Or WS_TABSTOP, W - 182, H - 34, 80, 24, ID_CANCEL);
  Dummy := DlgCtl('BUTTON', 'Appliquer', BS_PUSHBUTTON Or WS_TABSTOP, W - 94, H - 34, 84, 24, ID_APPLY);
End;

Procedure LangInit;
Begin
  Langs[0] := 'Fran'#231'ais'; LangId[0] := '0000040C';
  Langs[1] := 'Anglais (English)'; LangId[1] := '00000409';
  Langs[2] := 'Allemand (Deutsch)'; LangId[2] := '00000407';
  Langs[3] := 'Italien (Italiano)'; LangId[3] := '00000410';
  Langs[4] := 'Espagnol (Espa'#241'ol)'; LangId[4] := '0000040A';
End;

Function LangOfLcid(L : LongInt) : LongInt;
Begin
  Case L And $3FF Of
    9 : LangOfLcid := 1;
    7 : LangOfLcid := 2;
    $10 : LangOfLcid := 3;
    $0A : LangOfLcid := 4;
  Else
    LangOfLcid := 0;
  End;
End;

Procedure OpenDlg(Kind : LongInt);
Var W, H, V : LongInt; T : String;
Begin
  If DlgW <> 0 Then
  Begin
    Dummy := SetFocus(DlgW);
    Exit;
  End;
  DlgKind := Kind; Changed := False; TestOn := False;
  W := 400;
  Case Kind Of
    1 : Begin T := 'Propri'#233't'#233's de Souris'; H := 300; End;
    2 : Begin T := 'Propri'#233't'#233's de Clavier'; H := 250; End;
  Else
    Begin T := 'Propri'#233't'#233's de Param'#232'tres r'#233'gionaux'; H := 250; End;
  End;
  DlgW := MainWindow('CplDlg', T, WS_POPUP Or WS_CAPTION Or WS_SYSMENU, W, H, False);
  If DlgW = 0 Then Exit;
  Case Kind Of
    1 :
    Begin
      Dummy := DlgCtl('BUTTON', 'Boutons', BS_GROUPBOX, 8, 6, W - 16, 54, 0);
      CtlSwap := DlgCtl('BUTTON', 'Inverser les boutons (gaucher)',
                        BS_AUTOCHECKBOX Or WS_TABSTOP, 20, 28, W - 40, 20, ID_SWAP);
      If GetSystemMetrics(SM_SWAPBUTTON) <> 0 Then Dummy := SendMessageA(CtlSwap, BM_SETCHECK, 1, 0);
      Dummy := DlgCtl('BUTTON', 'Vitesse du double-clic', BS_GROUPBOX, 8, 66, 284, 106, 0);
      Dummy := DlgCtl('STATIC', 'Lente', 0, 20, 90, 48, 18, 0);
      Dummy := DlgCtl('STATIC', 'Rapide', 0, 232, 90, 56, 18, 0);
      CtlDbl := DlgCtl('SCROLLBAR', '', SBS_HORZ Or WS_TABSTOP, 70, 90, 156, 18, ID_DBL);
      { Lente 900 ms ... Rapide 200 ms }
      SetSb(CtlDbl, 0, 14, (900 - MinI(900, MaxI(200, GetDoubleClickTime))) Div 50);
      Dummy := DlgCtl('STATIC', 'Double-cliquez dans la zone de test, '#224' droite.', 0, 20, 116, 264, 36, 0);
      Dummy := DlgCtl('STATIC', 'Test', 0, 322, 70, 40, 18, 0);
      Dummy := DlgCtl('BUTTON', 'Vitesse du pointeur', BS_GROUPBOX, 8, 178, W - 16, 64, 0);
      Dummy := DlgCtl('STATIC', 'Lente', 0, 20, 206, 48, 18, 0);
      Dummy := DlgCtl('STATIC', 'Rapide', 0, 300, 206, 56, 18, 0);
      CtlSpd := DlgCtl('SCROLLBAR', '', SBS_HORZ Or WS_TABSTOP, 70, 206, 224, 18, ID_SPD);
      V := 10;
      Dummy := SystemParametersInfoA(SPI_GETMOUSESPEED, 0, LongInt(@V), 0);
      SetSb(CtlSpd, 1, 20, V);
    End;
    2 :
    Begin
      Dummy := DlgCtl('BUTTON', 'R'#233'p'#233'tition des caract'#232'res', BS_GROUPBOX, 8, 6, W - 16, 130, 0);
      Dummy := DlgCtl('STATIC', 'D'#233'lai de r'#233'p'#233'tition :', 0, 20, 28, 200, 18, 0);
      Dummy := DlgCtl('STATIC', 'Long', 0, 20, 50, 40, 18, 0);
      Dummy := DlgCtl('STATIC', 'Court', 0, 292, 50, 48, 18, 0);
      CtlDelay := DlgCtl('SCROLLBAR', '', SBS_HORZ Or WS_TABSTOP, 64, 50, 220, 18, ID_DELAY);
      V := 1;
      Dummy := SystemParametersInfoA(SPI_GETKEYBOARDDELAY, 0, LongInt(@V), 0);
      SetSb(CtlDelay, 0, 3, 3 - V);
      Dummy := DlgCtl('STATIC', 'Vitesse de r'#233'p'#233'tition :', 0, 20, 78, 200, 18, 0);
      Dummy := DlgCtl('STATIC', 'Lente', 0, 20, 100, 40, 18, 0);
      Dummy := DlgCtl('STATIC', 'Rapide', 0, 292, 100, 56, 18, 0);
      CtlRate := DlgCtl('SCROLLBAR', '', SBS_HORZ Or WS_TABSTOP, 64, 100, 220, 18, ID_RATE);
      V := 31;
      Dummy := SystemParametersInfoA(SPI_GETKEYBOARDSPEED, 0, LongInt(@V), 0);
      SetSb(CtlRate, 0, 31, V);
      Dummy := DlgCtl('STATIC', 'Maintenez une touche enfonc'#233'e ici pour tester :',
                      0, 12, 146, W - 24, 18, 0);
      CtlTest := DlgCtl('EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP, 12, 168, W - 24, 22, ID_KTEST);
    End;
  Else
    Begin
      LangInit;
      Dummy := DlgCtl('STATIC', 'Choisissez la langue de Pasdows 95 (menus, bo'#238'tes, messages) :',
                      0, 12, 10, W - 24, 18, 0);
      CtlLang := DlgCtl('LISTBOX', '', WS_BORDER Or WS_VSCROLL Or LBS_NOTIFY Or WS_TABSTOP,
                        12, 34, W - 24, 100, ID_LANG);
      For V := 0 To 4 Do
        Dummy := SendMessageA(CtlLang, LB_ADDSTRING, 0, Z(Disp(Langs[V])));
      Dummy := SendMessageA(CtlLang, LB_SETCURSEL, LangOfLcid(GetUserDefaultLCID), 0);
      Dummy := DlgCtl('STATIC', 'Le nouveau choix prend effet au red'#233'marrage de l''ordinateur.',
                      0, 12, 144, W - 24, 36, 0);
    End;
  End;
  Buttons(W, H);
  Dummy := ShowWindow(DlgW, 1);
  Dummy := UpdateWindow(DlgW);
End;

{ OK / Appliquer : 0 (fermer), sinon la boite reste ouverte }
Procedure DlgApply;
Var V, K, D : LongInt;
Begin
  Case DlgKind Of
    1 :
    Begin
      V := Ord(SendMessageA(CtlSwap, BM_GETCHECK, 0, 0) <> 0);
      Dummy := SystemParametersInfoA(SPI_SETMOUSEBUTTONSWAP, V, 0, 3);
      Dummy := SwapMouseButton(V);
      V := 900 - GetScrollPos(CtlDbl, SB_CTL) * 50;
      Dummy := SystemParametersInfoA(SPI_SETDOUBLECLICKTIME, V, 0, 3);
      Dummy := SystemParametersInfoA(SPI_SETMOUSESPEED, 0, GetScrollPos(CtlSpd, SB_CTL), 3);
    End;
    2 :
    Begin
      Dummy := SystemParametersInfoA(SPI_SETKEYBOARDDELAY, 3 - GetScrollPos(CtlDelay, SB_CTL), 0, 3);
      Dummy := SystemParametersInfoA(SPI_SETKEYBOARDSPEED, GetScrollPos(CtlRate, SB_CTL), 0, 3);
    End;
    3 :
    Begin
      V := SendMessageA(CtlLang, LB_GETCURSEL, 0, 0);
      If (V < 0) Or (V > 4) Or (V = LangOfLcid(GetUserDefaultLCID)) Then Exit;
      K := 0;
      If RegCreateKeyA(LongInt($80000001), Z('Control Panel\International'), LongInt(@K)) = 0 Then
      Begin
        PutZ(LongInt(@NameZ2), LangId[V]);
        Dummy := RegSetValueExA(K, Z('Locale'), 0, 1, LongInt(@NameZ2), 9);
        Dummy := RegCloseKey(K);
      End;
      D := MessageBoxA(DlgW, Z(Disp('Vous devez red'#233'marrer l''ordinateur pour que les ' +
                       'nouveaux param'#232'tres prennent effet.'#13#10#13#10 +
                       'Voulez-vous red'#233'marrer maintenant ?')),
                       Z2(Disp('Param'#232'tres r'#233'gionaux')), MB_YESNO Or MB_ICONQUESTION);
      If D = IDYES Then Dummy := ExitWindowsEx(2, 0);
    End;
  End;
  Changed := False;
End;

Procedure DlgClose;
Begin
  If DlgW <> 0 Then Dummy := DestroyWindow(DlgW);
  DlgW := 0;
  { ouverte seule (CONTROL MAIN.CPL...) : le programme se termine }
  If Wnd = 0 Then PostQuitMessage(0);
End;

{ curseur horizontal : position suivant la commande de defilement }
Procedure SbScroll(H, Code, Pos : LongInt);
Var P, Lo, Hi : LongInt;
Begin
  P := GetScrollPos(H, SB_CTL);
  Lo := 0; Hi := 31;
  If H = CtlDbl Then Hi := 14
  Else If H = CtlSpd Then Begin Lo := 1; Hi := 20; End
  Else If H = CtlDelay Then Hi := 3;
  Case Code Of
    SB_LINEUP : Dec(P);
    SB_LINEDOWN : Inc(P);
    SB_PAGEUP : P := P - MaxI(1, (Hi - Lo) Div 4);
    SB_PAGEDOWN : P := P + MaxI(1, (Hi - Lo) Div 4);
    SB_THUMBPOSITION, SB_THUMBTRACK : P := Pos;
    SB_LEFT : P := Lo;
    SB_RIGHT : P := Hi;
  End;
  If P < Lo Then P := Lo;
  If P > Hi Then P := Hi;
  Dummy := SetScrollPos(H, SB_CTL, P, 1);
  Changed := True;
End;

{ zone de test du double-clic (Souris) : une boite qui s'ouvre et se
  ferme ; le delai est celui du curseur, pas encore applique }
Procedure PaintTest(Dc : LongInt);
Var X, Y : LongInt;
Begin
  X := 300; Y := 90;
  Bar(Dc, X, Y, X + 76, Y + 70, ClrFace);
  Bevel(Dc, X, Y, X + 76, Y + 70, False);
  If TestOn Then
  Begin
    Bar(Dc, X + 22, Y + 30, X + 54, Y + 62, $00C000);
    Bar(Dc, X + 30, Y + 8, X + 46, Y + 30, $00FFFF);
    Bar(Dc, X + 33, Y + 14, X + 36, Y + 17, ClrDark);
    Bar(Dc, X + 40, Y + 14, X + 43, Y + 17, ClrDark);
  End
  Else
  Begin
    Bar(Dc, X + 22, Y + 30, X + 54, Y + 62, $00C000);
    Bar(Dc, X + 20, Y + 28, X + 56, Y + 32, $008000);
  End;
End;

Var
  TestT : LongInt;

Function DlgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Dc, X, Y : LongInt;
Begin
  DlgProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        If DlgKind = 1 Then PaintTest(Dc);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND :
      Begin
        Bar(WP, 0, 0, 800, 600, ClrFace);
        DlgProc := 1;
      End;
    WM_HSCROLL : SbScroll(LP, WP And $FFFF, S16(WP Shr 16));
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      If DlgKind = 1 Then
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        If (X >= 300) And (X < 376) And (Y >= 90) And (Y < 160) Then
        Begin
          { double-clic d'apres le delai choisi dans le curseur }
          If GetTickCount - TestT <= 900 - GetScrollPos(CtlDbl, SB_CTL) * 50 Then
          Begin
            TestOn := Not TestOn;
            TestT := 0;
            Dummy := InvalidateRect(H, 0, 1);
          End
          Else TestT := GetTickCount;
        End;
      End;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_OK : Begin DlgApply; DlgClose; End;
        ID_CANCEL : DlgClose;
        ID_APPLY : DlgApply;
        ID_LANG : If (WP Shr 16) = LBN_DBLCLK Then Begin DlgApply; DlgClose; End;
      End;
    WM_KEYDOWN :
      If WP = VK_ESCAPE Then DlgClose
      Else If WP = VK_RETURN Then Begin DlgApply; DlgClose; End;
    WM_CLOSE : DlgClose;
  Else
    DlgProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

{ ==================================================================== }
{ Fenetre principale                                                    }
{ ==================================================================== }

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    CM_OPEN : OpenApp(Sel);
    CM_QUIT : Dummy := DestroyWindow(Wnd);
    CM_REFRESH : Repaint;
    CM_ABOUT : Dummy := Ask('Panneau de configuration'#13#10'Pasdows 95 - Gladir.com, 2026'#13#10#13#10 +
                            'Les applets sont d'#233'sign'#233'es par leur fichier .CPL, comme sous Windows ' +
                            '(Control_RunDLL).', #192' propos du Panneau de configuration', MB_ICONINFO);
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, I, N : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 100) And (Rc[3] > 60) Then
        Begin
          CW := Rc[2]; CH := Rc[3];
          Dummy := InvalidateRect(H, 0, 0);
        End;
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        PaintAll(Dc);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        I := HitApp(S16(LP), S16(LP Shr 16));
        If I <> Sel Then Begin Sel := I; Repaint; End;
        If (Msg = WM_LBUTTONDBLCLK) And (I >= 0) Then OpenApp(I);
      End;
    WM_KEYDOWN :
      Begin
        N := Cols;
        Case WP Of
          VK_LEFT : If Sel > 0 Then Dec(Sel);
          VK_RIGHT : If Sel < NApp - 1 Then Inc(Sel);
          VK_UP : If Sel >= N Then Sel := Sel - N;
          VK_DOWN : If Sel + N < NApp Then Sel := Sel + N;
          VK_HOME : Sel := 0;
          VK_END : Sel := NApp - 1;
          VK_RETURN : OpenApp(Sel);
          VK_F5 : ;
        Else
          Begin
            MainProc := DefWindowProcA(H, Msg, WP, LP);
            Exit;
          End;
        End;
        If Sel < 0 Then Sel := 0;
        Repaint;
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

{ Ligne de commande : CONTROL [applet.CPL[,@n]] ou CONTROL MOUSE... }
Function CmdArg : String;
Var S : String; K : LongInt; Q : Boolean;
Begin
  S := GetZ(GetCommandLineA);
  { nom du programme (entre guillemets ou jusqu'a l'espace) }
  K := 1; Q := False;
  While (K <= Length(S)) And (Q Or (S[K] <> ' ')) Do
  Begin
    If S[K] = '"' Then Q := Not Q;
    Inc(K);
  End;
  S := UpS(TrimS(Copy(S, K, 255)));
  While Pos('"', S) > 0 Do Delete(S, Pos('"', S), 1);
  CmdArg := S;
End;

Var
  MenuBar, MFile, MView, MHelp, K : LongInt;
  A : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Sel := 0; DlgW := 0; Wnd := 0; TestT := 0;
  InitApps;
  RegClass('CplDlg', LongInt(@DlgProc), CS_DBLCLKS);
  { applet demandee sur la ligne de commande : sa boite seule }
  A := CmdArg;
  If A <> '' Then
  Begin
    If (Pos('MAIN.CPL', A) > 0) And (Pos('@1', A) > 0) Or (A = 'KEYBOARD') Then K := 2
    Else If (Pos('MAIN.CPL', A) > 0) And (Pos('@2', A) > 0) Or (A = 'FONTS') Then K := 7
    Else If (Pos('MAIN.CPL', A) > 0) Or (A = 'MOUSE') Then K := 1
    Else If (Pos('INTL.CPL', A) > 0) Or (A = 'INTERNATIONAL') Then K := 3
    Else K := 0;
    If K = 7 Then
    Begin
      OpenApp(7);
      ExitProcess(0);
    End;
    If K > 0 Then
    Begin
      OpenDlg(K);
      MsgLoop;
      ExitProcess(0);
    End;
    { autre .CPL : la boite du systeme }
    PutZ(LongInt(@NameZ), A);
    Control_RunDLLA(0, Inst, LongInt(@NameZ), 1);
    ExitProcess(0);
  End;
  CW := 4 * CellW + 8; CH := 3 * CellH + 12 + StH;
  RegClass('CplWnd', LongInt(@MainProc), CS_DBLCLKS);
  Wnd := MainWindow('CplWnd', 'Panneau de configuration', WS_OVERLAPPEDWINDOW, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MView := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MFile, CM_OPEN, '~Ouvrir'#9'Entr'#233'e');
  MItem(MFile, 0, '');
  MItem(MFile, CM_QUIT, '~Fermer');
  MItem(MView, CM_REFRESH, '~Actualiser'#9'F5');
  MItem(MHelp, CM_ABOUT, #192' ~propos du Panneau de configuration');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MView, '~Affichage');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
