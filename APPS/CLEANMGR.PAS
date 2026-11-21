{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: CLEANMGR - Nettoyage de disque de Pasdows 95 (Win32).
}

Program CLEANMGR;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\CLEANMGR.PAS CLEANMGR.EXE

  Comme le Nettoyage de disque de Windows (Accessoires, Outils systeme ;
  CLEANMGR C: pour un lecteur) : le programme calcule l'espace occupe
  par chaque categorie de fichiers inutiles, les coche ou non, montre la
  description de la categorie choisie et l'espace total libere ;
  Afficher les fichiers ouvre le dossier dans l'Explorateur ; OK
  supprime les fichiers des categories cochees (apres confirmation),
  avec une barre de progression.
  Categories : fichiers temporaires (\WINDOWS\TEMP, \TEMP), fichiers
  temporaires d'installation (~*.*, *.TMP, *.$$$ a la racine et dans
  \WINDOWS), anciens fichiers de ScanDisk (FOUND.nnn\*.CHK, *.CHK a la
  racine), fichiers de sauvegarde (*.BAK, *.OLD, *.SAV : racine et
  \WINDOWS), journaux (*.LOG de \WINDOWS : installation, programmes) et
  la Corbeille (\RECYCLED). Les fichiers en lecture seule, caches ou
  systeme sont laisses. }

Const
  NCat = 6;
  MaxFiles = 3000;
  CM_DRIVE = 500;
  ID_VIEW = 10; ID_OK = 1; ID_CANCEL = 2; ID_DRIVE = 11;
  ListX = 16; ListY = 78; RowH = 20; ListRows = 6;

Type
  PStr = ^String;

Var
  CatOn : Array[0..NCat - 1] Of Boolean;
  CatSize, CatCount : Array[0..NCat - 1] Of LongInt;
  FPath : Array[0..MaxFiles - 1] Of PStr;
  FCat, FSize : Array[0..MaxFiles - 1] Of LongInt;
  NF, Sel, Drive, CW, CH, MemDC, MemBmp, FontS : LongInt;
  ViewW, OkW, CancelW, DriveW : LongInt;
  Busy : Boolean;
  FData : Array[0..319] Of Byte;
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

Function DeleteFileA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'DeleteFileA';
Function RemoveDirectoryA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'RemoveDirectoryA';
Function GetDriveTypeA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetDriveTypeA';
Function GetDiskFreeSpaceA(R, Spc, Bps, Fr, Tot : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetDiskFreeSpaceA';
Function ShellExecuteA(H, Op, F, P, D, Sh : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ShellExecuteA';

Function CatName(C : LongInt) : String;
Begin
  Case C Of
    0 : CatName := 'Fichiers temporaires';
    1 : CatName := 'Fichiers temporaires d''installation';
    2 : CatName := 'Anciens fichiers de ScanDisk';
    3 : CatName := 'Fichiers de sauvegarde';
    4 : CatName := 'Fichiers journaux';
  Else
    CatName := 'Corbeille';
  End;
End;

Function CatText(C : LongInt) : String;
Begin
  Case C Of
    0 : CatText := 'Les programmes stockent parfois des informations temporaires dans un dossier TEMP. Avant de ' +
                   'quitter, ils les suppriment en g'#233'n'#233'ral.';
    1 : CatText := 'Fichiers laiss'#233's par les programmes d''installation (~*.*, *.TMP, *.$$$) dans la racine ' +
                   'du disque et dans le dossier Windows.';
    2 : CatText := 'ScanDisk peut enregistrer des fragments de fichiers perdus dans le dossier FOUND (fichiers ' +
                   '*.CHK). Ils sont g'#233'n'#233'ralement inutiles.';
    3 : CatText := 'Copies de sauvegarde (*.BAK, *.OLD, *.SAV) laiss'#233'es dans la racine du disque et dans le ' +
                   'dossier Windows par les '#233'diteurs et les programmes d''installation.';
    4 : CatText := 'Journaux (*.LOG) '#233'crits par les programmes d''installation et par Windows dans le dossier ' +
                   'Windows.';
  Else
    CatText := 'La Corbeille contient les fichiers supprim'#233's de votre ordinateur. Ils ne sont d'#233'finitivement ' +
               'supprim'#233's que lorsque vous la videz.';
  End;
End;

Function Root : String;
Begin
  Root := Chr(65 + Drive) + ':\';
End;

Function CatDir(C : LongInt) : String;
Begin
  Case C Of
    0 : CatDir := Root + 'WINDOWS\TEMP';
    2 : CatDir := Root + 'FOUND.000';
    5 : CatDir := Root + 'RECYCLED';
  Else
    CatDir := Root + 'WINDOWS';
  End;
End;

Function KStr(B : LongInt) : String;
Begin
  If B = 0 Then KStr := '0 Ko'
  Else KStr := IStr((B + 1023) Div 1024) + ' Ko';
End;

{ ==================================================================== }
{ Recherche des fichiers                                                }
{ ==================================================================== }

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

Procedure AddFile(P : String; C, Sz : LongInt);
Var Q : PStr;
Begin
  If NF >= MaxFiles Then Exit;
  GetMem(Q, Length(P) + 2);
  Q^ := P;
  FPath[NF] := Q; FCat[NF] := C; FSize[NF] := Sz;
  Inc(NF);
  CatSize[C] := CatSize[C] + Sz;
  Inc(CatCount[C]);
End;

{ fichiers du dossier D qui correspondent a un des modeles (separes par
  ;), sous-dossiers si Sub }
Procedure Scan(D, Pats : String; C : LongInt; Sub : Boolean; Depth : LongInt);
Var H, A, K, Sz : LongInt; N, U, P, T : String; L : PLng; Ok : Boolean;
    Subs : Array[0..15] Of String[79];
    NS : LongInt;
Begin
  If Depth > 6 Then Exit;
  If D[Length(D)] <> '\' Then D := D + '\';
  NS := 0;
  H := FindFirstFileA(Z(D + '*.*'), LongInt(@FData));
  If H = INVALID_HANDLE Then Exit;
  Repeat
    N := GetZ(LongInt(@FData[44]));
    L := PLng(LongInt(@FData[0])); A := L^;
    L := PLng(LongInt(@FData[32])); Sz := L^;
    If (N <> '.') And (N <> '..') Then
    Begin
      If (A And $10) <> 0 Then
      Begin
        If Sub And (NS < 16) Then Begin Subs[NS] := N; Inc(NS); End;
      End
      Else If (A And 7) = 0 Then
      Begin
        U := UpS(N);
        Ok := False;
        P := Pats + ';';
        While (P <> '') And Not Ok Do
        Begin
          K := Pos(';', P);
          T := Copy(P, 1, K - 1);
          Delete(P, 1, K);
          If (T <> '') And Match(T, U) Then Ok := True;
        End;
        If Ok Then AddFile(D + N, C, Sz);
      End;
    End;
  Until FindNextFileA(H, LongInt(@FData)) = 0;
  Dummy := FindClose(H);
  For K := 0 To NS - 1 Do Scan(D + Subs[K], Pats, C, Sub, Depth + 1);
End;

Procedure ScanAll;
Var K : LongInt; R : String;
Begin
  For K := 0 To NF - 1 Do FreeMem(FPath[K], Length(FPath[K]^) + 2);
  NF := 0;
  For K := 0 To NCat - 1 Do Begin CatSize[K] := 0; CatCount[K] := 0; End;
  R := Root;
  Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
  Scan(R + 'WINDOWS\TEMP', '*', 0, True, 0);
  Scan(R + 'TEMP', '*', 0, True, 0);
  Scan(R, '~*;*.TMP;*.$$$', 1, False, 0);
  Scan(R + 'WINDOWS', '~*;*.TMP;*.$$$', 1, False, 0);
  For K := 0 To 9 Do Scan(R + 'FOUND.00' + Chr(48 + K), '*.CHK', 2, False, 0);
  Scan(R, '*.CHK', 2, False, 0);
  Scan(R, '*.BAK;*.OLD;*.SAV', 3, False, 0);
  Scan(R + 'WINDOWS', '*.BAK;*.OLD;*.SAV', 3, False, 0);
  Scan(R + 'WINDOWS', '*.LOG', 4, False, 0);
  Scan(R + 'RECYCLED', '*', 5, True, 0);
  Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
End;

Function TotalOn : LongInt;
Var K, T : LongInt;
Begin
  T := 0;
  For K := 0 To NCat - 1 Do If CatOn[K] Then T := T + CatSize[K];
  TotalOn := T;
End;

Function TotalAll : LongInt;
Var K, T : LongInt;
Begin
  T := 0;
  For K := 0 To NCat - 1 Do T := T + CatSize[K];
  TotalAll := T;
End;

{ ==================================================================== }
{ Affichage                                                             }
{ ==================================================================== }

{ texte sur plusieurs lignes (largeur W en caracteres) }
Procedure Para(Dc, X, Y, W : LongInt; S : String; MaxL : LongInt);
Var K, N : LongInt;
Begin
  N := 0;
  While (S <> '') And (N < MaxL) Do
  Begin
    If Length(S) <= W Then K := Length(S) + 1
    Else
    Begin
      K := W + 1;
      While (K > 1) And (S[K] <> ' ') Do Dec(K);
      If K <= 1 Then K := W + 1;
    End;
    Txt(Dc, X, Y + N * 16, Copy(S, 1, K - 1), ClrDark, ClrFace);
    Delete(S, 1, K);
    Inc(N);
  End;
End;

Procedure DrawIcon(Dc, X, Y : LongInt);
Begin
  { disque dur et balai }
  Bar(Dc, X, Y + 10, X + 32, Y + 26, ClrShadow);
  Bar(Dc, X + 1, Y + 11, X + 31, Y + 25, ClrFace);
  Bar(Dc, X + 24, Y + 20, X + 28, Y + 22, $00C000);
  Bar(Dc, X + 22, Y - 2, X + 24, Y + 16, $004080);
  Bar(Dc, X + 16, Y + 14, X + 30, Y + 20, $40C0E0);
End;

Procedure DrawAll(Dc : LongInt);
Var K, Y, X2 : LongInt; S : String;
Begin
  Bar(Dc, 0, 0, CW, CH, ClrFace);
  DrawIcon(Dc, 16, 12);
  If Busy Then S := 'Calcul de l''espace pouvant '#234'tre lib'#233'r'#233' sur (' + Chr(65 + Drive) + ':)...'
  Else S := 'Vous pouvez utiliser le Nettoyage de disque pour lib'#233'rer jusqu'''#224' ' + KStr(TotalAll) +
            ' d''espace disque sur (' + Chr(65 + Drive) + ':).';
  Para(Dc, 60, 12, (CW - 76) Div 8, S, 3);
  Txt(Dc, ListX, ListY - 20, 'Fichiers '#224' supprimer :', ClrDark, ClrFace);
  X2 := CW - 16;
  Bevel(Dc, ListX, ListY, X2, ListY + ListRows * RowH + 4, False);
  Bar(Dc, ListX + 2, ListY + 2, X2 - 2, ListY + ListRows * RowH + 2, ClrWin);
  For K := 0 To NCat - 1 Do
  Begin
    Y := ListY + 2 + K * RowH;
    If K = Sel Then Bar(Dc, ListX + 26, Y, X2 - 2, Y + RowH, ClrSel);
    { case a cocher }
    Bar(Dc, ListX + 6, Y + 3, ListX + 20, Y + 17, ClrWin);
    Bevel(Dc, ListX + 5, Y + 2, ListX + 21, Y + 18, False);
    If CatOn[K] Then
    Begin
      Bar(Dc, ListX + 9, Y + 9, ListX + 11, Y + 13, ClrDark);
      Bar(Dc, ListX + 11, Y + 11, ListX + 13, Y + 15, ClrDark);
      Bar(Dc, ListX + 13, Y + 7, ListX + 15, Y + 13, ClrDark);
      Bar(Dc, ListX + 15, Y + 5, ListX + 17, Y + 11, ClrDark);
    End;
    If K = Sel Then
    Begin
      Txt(Dc, ListX + 30, Y + 2, CatName(K), ClrHi, ClrSel);
      S := KStr(CatSize[K]);
      Txt(Dc, X2 - 10 - Length(S) * 8, Y + 2, S, ClrHi, ClrSel);
    End
    Else
    Begin
      Txt(Dc, ListX + 30, Y + 2, CatName(K), ClrDark, ClrWin);
      S := KStr(CatSize[K]);
      Txt(Dc, X2 - 10 - Length(S) * 8, Y + 2, S, ClrDark, ClrWin);
    End;
  End;
  Y := ListY + ListRows * RowH + 12;
  S := 'Espace disque total lib'#233'r'#233' : ';
  Txt(Dc, ListX, Y, S + KStr(TotalOn), ClrDark, ClrFace);
  { description }
  Y := Y + 24;
  Bar(Dc, ListX, Y + 8, X2, Y + 9, ClrShadow);
  Bar(Dc, ListX, Y + 9, X2, Y + 10, ClrHi);
  Txt(Dc, ListX + 8, Y, ' Description ', ClrDark, ClrFace);
  Para(Dc, ListX + 8, Y + 20, (X2 - ListX - 16) Div 8, CatText(Sel) + ' (' + IStr(CatCount[Sel]) + ' fichier(s))', 4);
End;

Procedure Paint0;
Var Dc : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, ListY + ListRows * RowH + 124, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Nettoyage                                                             }
{ ==================================================================== }

Procedure Progress(Dc, Done, Total : LongInt; S : String);
Var W : LongInt;
Begin
  Bar(Dc, 0, 0, 360, 110, ClrFace);
  Txt(Dc, 16, 14, 'Le Nettoyage de disque nettoie les fichiers', ClrDark, ClrFace);
  Txt(Dc, 16, 30, 'inutiles de votre ordinateur.', ClrDark, ClrFace);
  If Length(S) > 40 Then S := Copy(S, 1, 39) + #187;
  Txt(Dc, 16, 54, S, ClrDark, ClrFace);
  Bevel(Dc, 16, 76, 344, 94, False);
  If Total > 0 Then W := (324 * Done) Div Total Else W := 324;
  Bar(Dc, 18, 78, 18 + W, 92, ClrSel);
End;

Procedure Clean;
Var K, N, T, H, Dc, Ok, Fail : LongInt; Rc : Array[0..3] Of LongInt; Ps : String;
Begin
  If TotalOn = 0 Then
  Begin
    Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    Exit;
  End;
  If Ask('Voulez-vous vraiment supprimer ces fichiers ?', 'Nettoyage de disque pour (' + Chr(65 + Drive) + ':)',
         MB_YESNO Or MB_ICONQUESTION) <> IDYES Then Exit;
  T := 0;
  For K := 0 To NF - 1 Do If CatOn[FCat[K]] Then Inc(T);
  Rc[0] := 0; Rc[1] := 0; Rc[2] := 360; Rc[3] := 110;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), WS_POPUP Or WS_CAPTION, 0, WS_EX_DLGMODALFRAME);
  PutZ(LongInt(@NameZ2), 'CleanProg');
  H := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@NameZ2), Z(Disp('Nettoyage de disque')), WS_POPUP Or WS_CAPTION,
                       MaxI(0, (GetSystemMetrics(SM_CXSCREEN) - Rc[2] + Rc[0]) Div 2),
                       MaxI(0, (GetSystemMetrics(SM_CYSCREEN) - Rc[3] + Rc[1]) Div 2), Rc[2] - Rc[0], Rc[3] - Rc[1],
                       Wnd, 0, Inst, 0);
  Dummy := EnableWindow(Wnd, 0);
  Dummy := ShowWindow(H, 1);
  N := 0; Ok := 0; Fail := 0;
  For K := 0 To NF - 1 Do
    If CatOn[FCat[K]] Then
    Begin
      Ps := FPath[K]^;
      If (N Mod 4 = 0) Or (N = T - 1) Then
      Begin
        Dc := GetDC(H);
        Dummy := SelectObject(Dc, FontS);
        Progress(Dc, N, T, 'Nettoyage : ' + CatName(FCat[K]));
        Dummy := ReleaseDC(H, Dc);
      End;
      If DeleteFileA(Z(Ps)) <> 0 Then Inc(Ok) Else Inc(Fail);
      Inc(N);
    End;
  { dossiers de ScanDisk vides et sous-dossiers de TEMP vides }
  For K := 0 To 9 Do Dummy := RemoveDirectoryA(Z(Root + 'FOUND.00' + Chr(48 + K)));
  Dummy := DestroyWindow(H);
  Dummy := EnableWindow(Wnd, 1);
  If Fail > 0 Then
    Dummy := Ask(IStr(Ok) + ' fichier(s) supprim'#233'(s). ' + IStr(Fail) + ' fichier(s) n''ont pas pu l'''#234'tre ' +
                 '(ils sont peut-'#234'tre ouverts par un programme).', 'Nettoyage de disque', MB_OK Or MB_ICONINFO);
  Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
End;

Procedure ChooseDrive;
Var M, K, R, D : LongInt; Rc : Array[0..1] Of LongInt;
Begin
  M := CreatePopupMenu;
  D := GetLogicalDrives;
  For K := 0 To 25 Do
    If (D And (1 Shl K)) <> 0 Then
      If GetDriveTypeA(Z(Chr(65 + K) + ':\')) In [2, 3] Then MItem(M, CM_DRIVE + K, '(' + Chr(65 + K) + ':)');
  Rc[0] := 16; Rc[1] := CH - 34;
  Dummy := ClientToScreen(Wnd, LongInt(@Rc));
  R := TrackPopupMenu(M, $100, Rc[0], Rc[1], 0, Wnd, 0);
  Dummy := DestroyMenu(M);
  If R >= CM_DRIVE Then
  Begin
    Drive := R - CM_DRIVE;
    Busy := True;
    Paint0;
    ScanAll;
    Busy := False;
    SetText(Wnd, 'Nettoyage de disque pour (' + Chr(65 + Drive) + ':)');
    Paint0;
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Dc, X, Y, K : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        K := (Y - ListY - 2) Div RowH;
        If (Y > ListY) And (K >= 0) And (K < NCat) And (X > ListX) And (X < CW - 16) Then
        Begin
          Sel := K;
          If (X < ListX + 24) Or (Msg = WM_LBUTTONDBLCLK) Then CatOn[K] := Not CatOn[K];
          Paint0;
        End;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_UP : Begin If Sel > 0 Then Dec(Sel); Paint0; End;
        VK_DOWN : Begin If Sel < NCat - 1 Then Inc(Sel); Paint0; End;
        VK_SPACE : Begin CatOn[Sel] := Not CatOn[Sel]; Paint0; End;
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_OK : Clean;
        ID_CANCEL : Dummy := PostMessageA(H, WM_CLOSE, 0, 0);
        ID_VIEW : Dummy := ShellExecuteA(H, Z2('open'), Z(CatDir(Sel)), 0, 0, 1);
        ID_DRIVE : ChooseDrive;
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function ProgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  If Msg = WM_ERASEBKGND Then ProgProc := 1 Else ProgProc := DefWindowProcA(H, Msg, WP, LP);
End;

Var
  Dc0, K : LongInt;
  A : String;
  Rc0 : Array[0..3] Of LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Drive := 2; NF := 0; Sel := 0; Busy := False;
  For K := 1 To ParamCount Do
  Begin
    A := UpS(ParamStr(K));
    If (Length(A) >= 2) And (A[2] = ':') And (A[1] >= 'A') And (A[1] <= 'Z') Then Drive := Ord(A[1]) - 65;
  End;
  CatOn[0] := True; CatOn[1] := True; CatOn[2] := True; CatOn[3] := False; CatOn[4] := False; CatOn[5] := True;
  ScanAll;
  CW := 420; CH := 416;
  RegClass('CleanWnd', LongInt(@MainProc), CS_DBLCLKS);
  RegClass('CleanProg', LongInt(@ProgProc), 0);
  Wnd := MainWindow('CleanWnd', 'Nettoyage de disque pour (' + Chr(65 + Drive) + ':)',
                    WS_CAPTION Or WS_SYSMENU Or WS_MINIMIZEBOX Or WS_CLIPCHILDREN, CW, CH, False);
  If Wnd = 0 Then ExitProcess(1);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  Dc0 := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc0);
  MemBmp := CreateCompatibleBitmap(Dc0, 640, 480);
  Dummy := ReleaseDC(Wnd, Dc0);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  DriveW := Ctl(Wnd, 'BUTTON', 'Lecteur...', WS_TABSTOP, 16, CH - 36, 96, 26, ID_DRIVE);
  ViewW := Ctl(Wnd, 'BUTTON', 'Afficher les fichiers', WS_TABSTOP, CW - 186, ListY + ListRows * RowH + 128, 170, 26,
               ID_VIEW);
  OkW := Ctl(Wnd, 'BUTTON', 'OK', WS_TABSTOP Or BS_DEFPUSHBUTTON, CW - 196, CH - 36, 86, 26, ID_OK);
  CancelW := Ctl(Wnd, 'BUTTON', 'Annuler', WS_TABSTOP, CW - 102, CH - 36, 86, 26, ID_CANCEL);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
