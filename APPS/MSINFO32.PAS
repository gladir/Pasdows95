{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: MSINFO32 - Informations systeme de Pasdows 95 (Win32).
}

Program MSINFO32;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\MSINFO32.PAS MSINFO32.EXE

  Comme les Informations systeme de Windows 98 (Accessoires, Outils
  systeme) : a gauche, les categories ; a droite, les elements et leurs
  valeurs :
  - Resume systeme : systeme d'exploitation, ordinateur, utilisateur,
    processeur, memoire, dossiers, affichage, DirectX, duree de
    fonctionnement ;
  - Ressources materielles : IRQ, DMA, E/S et memoire de chaque
    peripherique (liste du Gestionnaire de peripheriques publiee par le
    noyau dans HKEY_LOCAL_MACHINE\Enum\Pasdows) ;
  - Composants : multimedia (waveOut, midiOut, manettes), affichage,
    reseau (nom et adresse IP), stockage (lecteurs, systeme de fichiers,
    taille et espace libre), ports, peripheriques d'entree, tous les
    peripheriques ;
  - Environnement logiciel : taches en cours et modules charges
    (Toolhelp32), variables d'environnement.
  Fichier, Enregistrer : un rapport texte ; Edition, Copier ; Outils :
  Defragmenteur, Nettoyage de disque, ScanDisk (Verifier), Outil de
  diagnostic DirectX, Gestionnaire des taches. }

Const
  MaxRows = 600;
  NNodes = 16;
  TreeW = 200; RowH = 18; HdrH = 20; SbW = 16;
  CM_SAVE = 101; CM_QUIT = 102; CM_COPY = 201; CM_REFRESH = 301;
  CM_DEFRAG = 401; CM_CLEAN = 402; CM_DXDIAG = 403; CM_TASKMGR = 404;
  CM_ABOUT = 501;

Type
  TRow = Record
    Item : String[47];
    Value : String[120];
  End;
  PRow = ^TRow;

Var
  Rows : Array[0..MaxRows - 1] Of PRow;
  NRows, Node, Top, CW, CH, MemDC, MemBmp, FontS, VSb : LongInt;
  NodeLvl : Array[0..NNodes - 1] Of LongInt;
  Buf : Array[0..4095] Of Byte;
  WsaData : Array[0..399] Of Byte;
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

Function GetVersionExA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetVersionExA';
Procedure GetSystemInfo(P : LongInt); stdcall; external 'kernel32.dll' name 'GetSystemInfo';
Procedure GlobalMemoryStatus(P : LongInt); stdcall; external 'kernel32.dll' name 'GlobalMemoryStatus';
Function GetComputerNameA(B, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetComputerNameA';
Function GetUserNameA(B, N : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'GetUserNameA';
Function GetWindowsDirectoryA(B, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetWindowsDirectoryA';
Function GetSystemDirectoryA(B, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetSystemDirectoryA';
Function GetTempPathA(N, B : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetTempPathA';
Function GetDeviceCaps(Dc, I : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'GetDeviceCaps';
Function GetDriveTypeA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetDriveTypeA';
Function GetVolumeInformationA(R, V, VN, Ser, MC, Fl, FS, FSN : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetVolumeInformationA';
Function GetDiskFreeSpaceA(R, Spc, Bps, Fr, Tot : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetDiskFreeSpaceA';
Function waveOutGetNumDevs : LongInt; stdcall; external 'winmm.dll' name 'waveOutGetNumDevs';
Function waveOutGetDevCapsA(Id, P, N : LongInt) : LongInt; stdcall; external 'winmm.dll' name 'waveOutGetDevCapsA';
Function midiOutGetNumDevs : LongInt; stdcall; external 'winmm.dll' name 'midiOutGetNumDevs';
Function midiOutGetDevCapsA(Id, P, N : LongInt) : LongInt; stdcall; external 'winmm.dll' name 'midiOutGetDevCapsA';
Function joyGetNumDevs : LongInt; stdcall; external 'winmm.dll' name 'joyGetNumDevs';
Function CreateToolhelp32Snapshot(F, P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateToolhelp32Snapshot';
Function Process32First(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'Process32First';
Function Process32Next(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'Process32Next';
Function Module32First(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'Module32First';
Function Module32Next(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'Module32Next';
Function GetEnvironmentStringsA : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentStringsA';
Function WSAStartup(V, P : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'WSAStartup';
Function gethostname(B, N : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'gethostname';
Function gethostbyname(N : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'gethostbyname';
Function ShellExecuteA(H, Op, F, P, D, Sh : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ShellExecuteA';
Function RegEnumKeyA(K, I, B, N : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'RegEnumKeyA';

Function NodeName(N : LongInt) : String;
Begin
  Case N Of
    0 : NodeName := 'R'#233'sum'#233' syst'#232'me';
    1 : NodeName := 'Ressources mat'#233'rielles';
    2 : NodeName := 'IRQ';
    3 : NodeName := 'DMA';
    4 : NodeName := 'E/S';
    5 : NodeName := 'M'#233'moire';
    6 : NodeName := 'Composants';
    7 : NodeName := 'Multim'#233'dia';
    8 : NodeName := 'Affichage';
    9 : NodeName := 'R'#233'seau';
    10 : NodeName := 'Stockage';
    11 : NodeName := 'Ports';
    12 : NodeName := 'P'#233'riph'#233'riques';
    13 : NodeName := 'Environnement logiciel';
    14 : NodeName := 'T'#226'ches en cours';
  Else
    NodeName := 'Variables d''environnement';
  End;
End;

{ ==================================================================== }
{ Lignes                                                                }
{ ==================================================================== }

Procedure ClearRows;
Var I : LongInt;
Begin
  For I := 0 To NRows - 1 Do FreeMem(Rows[I], SizeOf(TRow));
  NRows := 0; Top := 0;
End;

Procedure Add(It, V : String);
Var P : PRow;
Begin
  If NRows >= MaxRows Then Exit;
  GetMem(P, SizeOf(TRow));
  P^.Item := Copy(It, 1, 47); P^.Value := Copy(V, 1, 120);
  Rows[NRows] := P;
  Inc(NRows);
End;

Function ZStr(A : LongInt) : String;
Begin
  ZStr := UnDisp(GetZ(A));
End;

Function MoStr(B : LongInt) : String;
Begin
  If B < 0 Then MoStr := IStr((B Shr 20) And $FFF) + ' Mo'
  Else If B >= 1048576 Then MoStr := IStr(B Div 1048576) + ' Mo'
  Else MoStr := IStr(B Div 1024) + ' Ko';
End;

Function HexW(V, D : LongInt) : String;
Const H : String[16] = '0123456789ABCDEF';
Var S : String; K : LongInt;
Begin
  S := '';
  For K := 1 To D Do
  Begin
    S := H[(V And 15) + 1] + S;
    V := V Shr 4;
  End;
  HexW := S;
End;

{ registre : chaine (ou '') }
Function RegStr(Root : LongInt; Path, Nm : String) : String;
Var K, T, N : LongInt;
Begin
  RegStr := '';
  If RegOpenKeyExA(Root, Z(Path), 0, $20019, LongInt(@K)) <> 0 Then Exit;
  N := 1024; Buf[0] := 0;
  If RegQueryValueExA(K, Z2(Nm), 0, LongInt(@T), LongInt(@Buf), LongInt(@N)) = 0 Then
  Begin
    Buf[MinI(N, 1023)] := 0;
    RegStr := ZStr(LongInt(@Buf));
  End;
  Dummy := RegCloseKey(K);
End;

{ peripheriques publies par le noyau }
Function DevCount : LongInt;
Var V, E : LongInt;
Begin
  Val(RegStr(LongInt($80000002), 'Enum\Pasdows', 'Count'), V, E);
  If E <> 0 Then V := 0;
  DevCount := V;
End;

Function DevKey(I : LongInt) : String;
Begin
  DevKey := 'Enum\Pasdows\' + Chr(48 + I Div 10) + Chr(48 + I Mod 10);
End;

Function DevField(I : LongInt; F : String) : String;
Begin
  DevField := RegStr(LongInt($80000002), DevKey(I), F);
End;

{ ressources de type Ty (I, Q, D, M) du peripherique I, separees par ;
  (texte), ou la premiere valeur numerique (Num) }
Procedure DevRes(I : LongInt; Ty : Char; Var Lst : String);
Var R, T : String; K : LongInt;
Begin
  R := DevField(I, 'Resources');
  Lst := '';
  While R <> '' Do
  Begin
    K := Pos('|', R);
    If K = 0 Then K := Length(R) + 1;
    T := Copy(R, 1, K - 1);
    Delete(R, 1, K);
    If (T <> '') And (T[1] = Ty) Then
    Begin
      If Lst <> '' Then Lst := Lst + ';';
      Lst := Lst + Copy(T, 2, 40);
    End;
  End;
End;

{ ==================================================================== }
{ Categories                                                            }
{ ==================================================================== }

Procedure Summary;
Var V : Array[0..39] Of LongInt; M : Array[0..7] Of LongInt; Si : Array[0..8] Of LongInt; N, Dc, T : LongInt;
    S : String;
Begin
  S := RegStr(LongInt($80000002), 'Software\Microsoft\Windows\CurrentVersion', 'ProductName');
  If S = '' Then S := 'Windows 95';
  V[0] := 148;
  Dummy := GetVersionExA(LongInt(@V));
  Add('Syst'#232'me d''exploitation', S);
  Add('Version', IStr(V[1]) + '.' + Two(V[2]) + '.' + IStr(V[3] And $FFFF) + ' ' + ZStr(LongInt(@V[5])));
  N := 255; Buf[0] := 0; Dummy := GetComputerNameA(LongInt(@Buf), LongInt(@N));
  Add('Nom de l''ordinateur', ZStr(LongInt(@Buf)));
  N := 255; Buf[0] := 0; Dummy := GetUserNameA(LongInt(@Buf), LongInt(@N));
  Add('Utilisateur', ZStr(LongInt(@Buf)));
  S := RegStr(LongInt($80000002), 'Software\Microsoft\Windows\CurrentVersion', 'RegisteredOwner');
  If S <> '' Then Add('Propri'#233'taire enregistr'#233, S);
  S := RegStr(LongInt($80000002), 'Hardware\Description\System\CentralProcessor\0', 'ProcessorNameString');
  If S = '' Then S := 'Processeur x86';
  Add('Processeur', S);
  S := RegStr(LongInt($80000002), 'Hardware\Description\System\CentralProcessor\0', '~MHz');
  If S <> '' Then Add('Fr'#233'quence', S + ' MHz');
  GetSystemInfo(LongInt(@Si));
  Add('Nombre de processeurs', IStr(Si[5]));
  Add('Taille des pages', IStr(Si[1]) + ' octets');
  M[0] := 32;
  GlobalMemoryStatus(LongInt(@M));
  Add('M'#233'moire physique totale', MoStr(M[2]));
  Add('M'#233'moire physique disponible', MoStr(M[3]));
  Add('M'#233'moire utilis'#233'e', IStr(M[1]) + ' %');
  Add('M'#233'moire virtuelle totale', MoStr(M[6]));
  Add('M'#233'moire virtuelle disponible', MoStr(M[7]));
  Buf[0] := 0; Dummy := GetWindowsDirectoryA(LongInt(@Buf), 255);
  Add('Dossier Windows', ZStr(LongInt(@Buf)));
  Buf[0] := 0; Dummy := GetSystemDirectoryA(LongInt(@Buf), 255);
  Add('Dossier syst'#232'me', ZStr(LongInt(@Buf)));
  Buf[0] := 0; Dummy := GetTempPathA(255, LongInt(@Buf));
  Add('Dossier temporaire', ZStr(LongInt(@Buf)));
  Dc := GetDC(0);
  Add('Affichage', IStr(GetSystemMetrics(0)) + ' x ' + IStr(GetSystemMetrics(1)) + ', ' + IStr(GetDeviceCaps(Dc, 12) *
      GetDeviceCaps(Dc, 14)) + ' bits par pixel');
  Dummy := ReleaseDC(0, Dc);
  S := RegStr(LongInt($80000002), 'Software\Microsoft\DirectX', 'Version');
  If S <> '' Then Add('Version de DirectX', S);
  T := GetTickCount Div 1000;
  Add('Dur'#233'e de fonctionnement', IStr(T Div 3600) + ' h ' + Two((T Div 60) Mod 60) + ' min ' + Two(T Mod 60) + ' s');
End;

{ ressources : une ligne par valeur, triee par la valeur }
Procedure Resources(Ty : Char);
Var I, J, K, N : LongInt; L, T, Nm : String; Keys : Array[0..127] Of String[24]; Who : Array[0..127] Of String[63];
    Tmp : String[63];
Begin
  N := 0;
  For I := 0 To DevCount - 1 Do
  Begin
    DevRes(I, Ty, L);
    Nm := DevField(I, 'DeviceDesc');
    While (L <> '') And (N < 128) Do
    Begin
      K := Pos(';', L);
      If K = 0 Then K := Length(L) + 1;
      T := Copy(L, 1, K - 1);
      Delete(L, 1, K);
      Keys[N] := T; Who[N] := Nm;
      Inc(N);
    End;
  End;
  { tri }
  For I := 1 To N - 1 Do
  Begin
    J := I;
    While (J > 0) And (Keys[J] < Keys[J - 1]) Do
    Begin
      Tmp := Keys[J]; Keys[J] := Keys[J - 1]; Keys[J - 1] := Tmp;
      Tmp := Who[J]; Who[J] := Who[J - 1]; Who[J - 1] := Tmp;
      Dec(J);
    End;
  End;
  For I := 0 To N - 1 Do
    Case Ty Of
      'Q' : Add('IRQ ' + Keys[I], Who[I]);
      'D' : Add('Canal ' + Keys[I], Who[I]);
    Else
      Add(Keys[I] + 'h', Who[I]);
    End;
  If N = 0 Then Add('(aucune)', '');
End;

{ peripheriques dont la classe contient C (ou tous) }
Procedure Devices(C : String);
Var I : LongInt; Cl, R, S : String;
Begin
  For I := 0 To DevCount - 1 Do
  Begin
    Cl := DevField(I, 'Class');
    If (C = '') Or (Pos(UpS(C), UpS(Cl)) > 0) Then
    Begin
      Add(DevField(I, 'DeviceDesc'), Cl);
      S := DevField(I, 'Mfg');
      If S <> '' Then Add('  Fabricant', S);
      DevRes(I, 'Q', R); If R <> '' Then Add('  IRQ', R);
      DevRes(I, 'I', R); If R <> '' Then Add('  E/S', R);
      DevRes(I, 'D', R); If R <> '' Then Add('  DMA', R);
      DevRes(I, 'M', R); If R <> '' Then Add('  M'#233'moire', R);
    End;
  End;
End;

Procedure Multimedia;
Var I, N : LongInt; Caps : Array[0..31] Of LongInt;
Begin
  N := waveOutGetNumDevs;
  Add('P'#233'riph'#233'riques audio (waveOut)', IStr(N));
  For I := 0 To N - 1 Do
    If waveOutGetDevCapsA(I, LongInt(@Caps), 52) = 0 Then Add('  Sortie audio ' + IStr(I), ZStr(LongInt(@Caps[2])));
  N := midiOutGetNumDevs;
  Add('P'#233'riph'#233'riques MIDI (midiOut)', IStr(N));
  For I := 0 To N - 1 Do
    If midiOutGetDevCapsA(I, LongInt(@Caps), 52) = 0 Then Add('  Sortie MIDI ' + IStr(I), ZStr(LongInt(@Caps[2])));
  Add('Manettes de jeu', IStr(joyGetNumDevs));
  Add('', '');
  Devices('son');
End;

Procedure Display;
Var Dc : LongInt;
Begin
  Dc := GetDC(0);
  Add('R'#233'solution', IStr(GetSystemMetrics(0)) + ' x ' + IStr(GetSystemMetrics(1)));
  Add('Couleurs', IStr(GetDeviceCaps(Dc, 12) * GetDeviceCaps(Dc, 14)) + ' bits par pixel');
  Add('R'#233'solution logique', IStr(GetDeviceCaps(Dc, 88)) + ' points par pouce');
  Dummy := ReleaseDC(0, Dc);
  Add('', '');
  Devices('graphique');
  Devices('oniteur');
End;

Procedure Network;
Var H, L, A, K : LongInt; P : PLng; B : PByt; S : String;
Begin
  If WSAStartup($101, LongInt(@WsaData)) = 0 Then
  Begin
    Buf[0] := 0;
    Dummy := gethostname(LongInt(@Buf), 255);
    S := ZStr(LongInt(@Buf));
    Add('Nom d''h'#244'te', S);
    H := gethostbyname(Z(S));
    If H <> 0 Then
    Begin
      P := PLng(H + 12); L := P^;
      K := 0;
      While K < 4 Do
      Begin
        P := PLng(L + K * 4);
        If P^ = 0 Then Break;
        A := P^;
        B := PByt(A);
        S := IStr(B^);
        B := PByt(A + 1); S := S + '.' + IStr(B^);
        B := PByt(A + 2); S := S + '.' + IStr(B^);
        B := PByt(A + 3); S := S + '.' + IStr(B^);
        Add('Adresse IP', S);
        Inc(K);
      End;
    End;
  End
  Else Add('TCP/IP', 'non disponible');
  Add('', '');
  Devices('seau');
End;

Procedure Storage;
Var D, K, T, Ser, Mc, Fl, Spc, Bps, Fr, Tot : LongInt; R, S : String; FsB : Array[0..31] Of Byte;
Begin
  D := GetLogicalDrives;
  For K := 0 To 25 Do
    If (D And (1 Shl K)) <> 0 Then
    Begin
      R := Chr(65 + K) + ':\';
      T := GetDriveTypeA(Z(R));
      If T < 2 Then Continue;
      Case T Of
        2 : S := 'Disquette';
        3 : S := 'Disque dur';
        4 : S := 'Lecteur r'#233'seau';
        5 : S := 'CD-ROM';
        6 : S := 'Disque virtuel';
      Else
        S := 'Lecteur';
      End;
      Add('Lecteur ' + Chr(65 + K) + ':', S);
      If T <> 2 Then
      Begin
        Buf[0] := 0; FsB[0] := 0;
        If GetVolumeInformationA(Z(R), LongInt(@Buf), 255, LongInt(@Ser), LongInt(@Mc), LongInt(@Fl), LongInt(@FsB),
                                 32) <> 0 Then
        Begin
          Add('  Nom de volume', ZStr(LongInt(@Buf)));
          Add('  Syst'#232'me de fichiers', ZStr(LongInt(@FsB)));
          Add('  Num'#233'ro de s'#233'rie', HexW(Ser Shr 16, 4) + '-' + HexW(Ser, 4));
        End;
        If GetDiskFreeSpaceA(Z(R), LongInt(@Spc), LongInt(@Bps), LongInt(@Fr), LongInt(@Tot)) <> 0 Then
        Begin
          Add('  Taille', IStr((Tot Div 1024) * (Spc * Bps) Div 1024) + ' Mo');
          Add('  Espace libre', IStr((Fr Div 1024) * (Spc * Bps) Div 1024) + ' Mo');
          Add('  Taille d''un cluster', IStr(Spc * Bps) + ' octets');
        End;
      End;
    End;
  Add('', '');
  Devices('isque');
  Devices('CD-ROM');
End;

Procedure Processes;
Var H, H2 : LongInt; Pe : Array[0..73] Of LongInt; Me : Array[0..137] Of LongInt; N : LongInt; P : PLng;
Begin
  H := CreateToolhelp32Snapshot(2, 0);
  If H = -1 Then Exit;
  Pe[0] := 296;
  N := 0;
  If Process32First(H, LongInt(@Pe)) <> 0 Then
    Repeat
      Add(ZStr(LongInt(@Pe[9])), 'processus ' + IStr(Pe[2]) + ', ' + IStr(Pe[5]) + ' t'#226'che(s)');
      Inc(N);
      Pe[0] := 296;
    Until Process32Next(H, LongInt(@Pe)) = 0;
  Dummy := CloseHandle(H);
  Add('', '');
  Add('Modules charg'#233's', '');
  H2 := CreateToolhelp32Snapshot(8, 0);
  If H2 = -1 Then Exit;
  Me[0] := 548;
  If Module32First(H2, LongInt(@Me)) <> 0 Then
    Repeat
      Add('  ' + ZStr(LongInt(@Me[8])), HexW(Me[5], 8) + 'h, ' + IStr(Me[6] Div 1024) + ' Ko');
      Me[0] := 548;
    Until Module32Next(H2, LongInt(@Me)) = 0;
  Dummy := CloseHandle(H2);
End;

Procedure Environment;
Var A, K : LongInt; S : String; P : PByt;
Begin
  A := GetEnvironmentStringsA;
  If A = 0 Then Exit;
  Repeat
    S := '';
    P := PByt(A);
    While (P^ <> 0) And (Length(S) < 250) Do
    Begin
      S := S + Chr(P^);
      Inc(A);
      P := PByt(A);
    End;
    Inc(A);
    If S = '' Then Break;
    K := Pos('=', S);
    If K > 1 Then Add(Copy(S, 1, K - 1), UnDisp(Copy(S, K + 1, 200)));
    P := PByt(A);
  Until P^ = 0;
End;

Procedure Fill;
Begin
  ClearRows;
  Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
  Case Node Of
    0 : Summary;
    1 : Begin Add('Choisissez IRQ, DMA, E/S ou M'#233'moire', ''); Add('', ''); Devices(''); End;
    2 : Resources('Q');
    3 : Resources('D');
    4 : Resources('I');
    5 : Resources('M');
    6 : Devices('');
    7 : Multimedia;
    8 : Display;
    9 : Network;
    10 : Storage;
    11 : Devices('Ports');
    12 : Begin Devices('Clavier'); Devices('Souris'); Devices('autre'); Devices('syst'); End;
    13, 14 : Processes;
  Else
    Environment;
  End;
  Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }

Function NRowsVis : LongInt;
Begin
  NRowsVis := MaxI(1, (CH - HdrH - 6) Div RowH);
End;

Procedure ClipT(Dc, X, Y, W : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If W < 10 Then Exit;
  If Length(S) * 8 > W - 2 Then S := Copy(S, 1, MaxI(0, (W - 2) Div 8 - 1)) + #187;
  Txt(Dc, X, Y, S, Fg, Bg);
End;

Procedure DrawTree(Dc : LongInt);
Var N, Y, X, Fg, Bg : LongInt;
Begin
  Bar(Dc, 0, 0, TreeW, CH, ClrWin);
  Bevel(Dc, 0, 0, TreeW, CH, False);
  For N := 0 To NNodes - 1 Do
  Begin
    Y := 4 + N * RowH;
    X := 8 + NodeLvl[N] * 16;
    If NodeLvl[N] > 0 Then
    Begin
      Bar(Dc, X - 10, Y + 8, X - 3, Y + 9, ClrShadow);
      Bar(Dc, X - 10, Y - 6, X - 9, Y + 9, ClrShadow);
    End
    Else
    Begin
      { case "-" des categories }
      Bar(Dc, X, Y + 4, X + 9, Y + 13, ClrShadow);
      Bar(Dc, X + 1, Y + 5, X + 8, Y + 12, ClrWin);
      Bar(Dc, X + 2, Y + 8, X + 7, Y + 9, ClrDark);
    End;
    If N = Node Then Begin Fg := ClrHi; Bg := ClrSel; End Else Begin Fg := ClrDark; Bg := ClrWin; End;
    ClipT(Dc, X + 12 * Ord(NodeLvl[N] = 0), Y + 1, TreeW - X - 14, NodeName(N), Fg, Bg);
  End;
End;

Procedure DrawList(Dc : LongInt);
Var X0, X1, X2, R, I, Y : LongInt;
Begin
  X0 := TreeW + 4; X2 := CW - SbW;
  X1 := X0 + (X2 - X0) Div 2;
  Bar(Dc, X0, 0, CW, CH, ClrFace);
  Bevel(Dc, X0, 0, X1, HdrH, True);
  Bevel(Dc, X1, 0, X2, HdrH, True);
  Txt(Dc, X0 + 4, 2, #201'l'#233'ment', ClrDark, ClrFace);
  Txt(Dc, X1 + 4, 2, 'Valeur', ClrDark, ClrFace);
  Bar(Dc, X0, HdrH, X2, CH, ClrWin);
  For R := 0 To NRowsVis - 1 Do
  Begin
    I := Top + R;
    If I >= NRows Then Break;
    Y := HdrH + 3 + R * RowH;
    ClipT(Dc, X0 + 4, Y, X1 - X0 - 6, Rows[I]^.Item, ClrDark, ClrWin);
    ClipT(Dc, X1 + 4, Y, X2 - X1 - 6, Rows[I]^.Value, ClrDark, ClrWin);
  End;
End;

Procedure DrawAll(Dc : LongInt);
Begin
  DrawTree(Dc);
  DrawList(Dc);
End;

Procedure Ensure;
Begin
  If Top > MaxI(0, NRows - NRowsVis) Then Top := MaxI(0, NRows - NRowsVis);
  If Top < 0 Then Top := 0;
  Dummy := SetScrollRange(VSb, 2, 0, MaxI(0, NRows - NRowsVis), 0);
  Dummy := SetScrollPos(VSb, 2, Top, 1);
End;

Procedure Paint0;
Var Dc : LongInt;
Begin
  Ensure;
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW - SbW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Commandes                                                             }
{ ==================================================================== }

Var
  Ofn : Array[0..21] Of LongInt;
  OfnFile : Array[0..259] Of Byte;
  FiltBuf : Array[0..63] Of Byte;

Function GetSaveFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetSaveFileNameA';

Procedure SaveReport;
Var H, N, W, K, Old : LongInt; S, P, F : String;
Begin
  F := 'Fichier texte (*.txt)|*.txt|';
  For K := 1 To Length(F) Do If F[K] = '|' Then FiltBuf[K - 1] := 0 Else FiltBuf[K - 1] := Ord(F[K]);
  FiltBuf[Length(F)] := 0;
  For K := 0 To 21 Do Ofn[K] := 0;
  PutZ(LongInt(@OfnFile), 'MSINFO.TXT');
  Ofn[0] := 76; Ofn[1] := Wnd; Ofn[3] := LongInt(@FiltBuf); Ofn[6] := 1;
  Ofn[7] := LongInt(@OfnFile); Ofn[8] := 260;
  If GetSaveFileNameA(LongInt(@Ofn)) = 0 Then Exit;
  P := GetZ(LongInt(@OfnFile));
  H := CreateFileA(Z(P), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  Old := Node;
  For N := 0 To NNodes - 1 Do
  Begin
    Node := N;
    Fill;
    S := Disp('[' + NodeName(N) + ']') + #13#10;
    Dummy := WriteFile(H, LongInt(@S[1]), Length(S), LongInt(@W), 0);
    For K := 0 To NRows - 1 Do
    Begin
      S := Rows[K]^.Item;
      While Length(S) < 34 Do S := S + ' ';
      S := Disp(S + ' ' + Rows[K]^.Value) + #13#10;
      Dummy := WriteFile(H, LongInt(@S[1]), Length(S), LongInt(@W), 0);
    End;
    S := #13#10;
    Dummy := WriteFile(H, LongInt(@S[1]), Length(S), LongInt(@W), 0);
  End;
  Dummy := CloseHandle(H);
  Node := Old;
  Fill;
  Paint0;
  Dummy := Ask('Rapport enregistr'#233' dans ' + P + '.', 'Informations syst'#232'me', MB_OK Or MB_ICONINFO);
End;

Procedure CopyAll;
Var H, K, N, J : LongInt; S : String; P : PByt;
Begin
  If OpenClipboard(Wnd) = 0 Then Exit;
  Dummy := EmptyClipboard;
  H := GlobalAlloc(0, NRows * 172 + 1);
  If H <> 0 Then
  Begin
    N := 0;
    For K := 0 To NRows - 1 Do
    Begin
      S := Disp(Rows[K]^.Item + #9 + Rows[K]^.Value) + #13#10;
      For J := 1 To Length(S) Do Begin P := PByt(H + N); P^ := Ord(S[J]); Inc(N); End;
    End;
    P := PByt(H + N); P^ := 0;
    Dummy := SetClipboardData(CF_TEXT, H);
  End;
  Dummy := CloseClipboard;
End;

Procedure Run(Exe : String);
Begin
  If ShellExecuteA(Wnd, Z2('open'), Z(Exe), 0, 0, 1) <= 32 Then
    Dummy := Ask(Exe + ' est introuvable.', 'Informations syst'#232'me', MB_OK Or MB_ICONERROR);
End;

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    CM_SAVE : SaveReport;
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_COPY : CopyAll;
    CM_REFRESH : Begin Fill; Paint0; End;
    CM_DEFRAG : Run('DEFRAG.EXE');
    CM_CLEAN : Run('CLEANMGR.EXE');
    CM_DXDIAG : Run('DXDIAG.EXE');
    CM_TASKMGR : Run('TASKMGR.EXE');
    CM_ABOUT : Dummy := Ask('Informations syst'#232'me de Pasdows 95'#10#10'Programme '#233'crit en Pascal et compil'#233 +
                            ' par WPC.', #192' propos des Informations syst'#232'me', MB_OK Or MB_ICONINFO);
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, X, Y, N : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 300) And (Rc[3] > 100) Then
        Begin
          CW := MinI(Rc[2], 1024); CH := MinI(Rc[3], 768);
          If VSb <> 0 Then Dummy := MoveWindow(VSb, CW - SbW, 0, SbW, CH, 1);
          Ensure;
          Dummy := InvalidateRect(H, 0, 0);
        End;
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW - SbW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN :
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        If X < TreeW Then
        Begin
          N := (Y - 4) Div RowH;
          If (N >= 0) And (N < NNodes) And (N <> Node) Then
          Begin
            Node := N;
            Fill;
            Paint0;
          End;
        End;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_UP : If Node > 0 Then Begin Dec(Node); Fill; Paint0; End;
        VK_DOWN : If Node < NNodes - 1 Then Begin Inc(Node); Fill; Paint0; End;
        VK_PRIOR : Begin Top := Top - NRowsVis; Paint0; End;
        VK_NEXT : Begin Top := Top + NRowsVis; Paint0; End;
        VK_F5 : Command(CM_REFRESH);
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_VSCROLL :
      Begin
        Case WP And $FFFF Of
          SB_LINEUP : Dec(Top);
          SB_LINEDOWN : Inc(Top);
          SB_PAGEUP : Top := Top - NRowsVis;
          SB_PAGEDOWN : Top := Top + NRowsVis;
          SB_THUMBPOSITION, SB_THUMBTRACK : Top := (WP Shr 16) And $FFFF;
        End;
        Paint0;
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  MenuBar, MFile, MEdit, MView, MTools, MHelp, Dc0, K : LongInt;
  Rc0 : Array[0..3] Of LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  NRows := 0; Node := 0; Top := 0; VSb := 0;
  For K := 0 To NNodes - 1 Do NodeLvl[K] := 1;
  NodeLvl[0] := 0; NodeLvl[1] := 0; NodeLvl[6] := 0; NodeLvl[13] := 0;
  CW := 620; CH := 380;
  RegClass('MsInfoWnd', LongInt(@MainProc), 0);
  Wnd := MainWindow('MsInfoWnd', 'Informations syst'#232'me', WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MEdit := CreatePopupMenu; MView := CreatePopupMenu; MTools := CreatePopupMenu;
  MHelp := CreatePopupMenu;
  MItem(MFile, CM_SAVE, '~Enregistrer le rapport...');
  MItem(MFile, 0, '');
  MItem(MFile, CM_QUIT, '~Quitter');
  MItem(MEdit, CM_COPY, '~Copier'#9'Ctrl+C');
  MItem(MView, CM_REFRESH, '~Actualiser'#9'F5');
  MItem(MTools, CM_DEFRAG, '~D'#233'fragmenteur de disque');
  MItem(MTools, CM_CLEAN, '~Nettoyage de disque');
  MItem(MTools, CM_DXDIAG, 'Outil de diagnostic ~DirectX');
  MItem(MTools, CM_TASKMGR, '~Gestionnaire des t'#226'ches');
  MItem(MHelp, CM_ABOUT, #192' ~propos des Informations syst'#232'me');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MEdit, '~Edition');
  MSub(MenuBar, MView, '~Affichage');
  MSub(MenuBar, MTools, '~Outils');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  VSb := Ctl(Wnd, 'SCROLLBAR', '', 1, CW - SbW, 0, SbW, CH, 30);
  Dc0 := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc0);
  MemBmp := CreateCompatibleBitmap(Dc0, 1024, 768);
  Dummy := ReleaseDC(Wnd, Dc0);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  Fill;
  Ensure;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
