{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: IMAGING - Visionneuse d'images de Pasdows 95 (Win32),
                comme Imaging des Accessoires de Windows 95.
}

Program IMAGING;

{$APPTYPE GUI}
{$R-,S-,I-}
{$M 8388608}

{ Compilation : WPC -CW32 APPS\IMAGING.PAS IMAGING.EXE

  Comme l'application Imaging des Accessoires de Windows 95 : afficher
  des images, les agrandir, les reduire, les faire pivoter et les
  enregistrer.
  - formats : TIFF (format natif d'Imaging : non compresse, PackBits,
    LZW avec ou sans predicteur, 1, 4, 8 bits gris ou palette, 24 et 32
    bits, plusieurs pages), BMP, GIF, PNG et JPEG (decodeurs du Navigateur
    Web de Pasdows) ;
  - zoom : avant, arriere, 25 a 400 %, ajuster a la fenetre ou a la
    largeur, taille reelle ; barres de defilement et fleches ;
  - image : pivoter de 90 degres a gauche ou a droite, de 180 degres,
    retourner (miroir) ;
  - pages d'un TIFF : premiere, precedente, suivante, derniere ;
  - Enregistrer sous : BMP 24 bits ; Proprietes : format, taille,
    dimensions ;
  - barre d'outils et barre d'etat (page, zoom, dimensions).
  Parametre : le fichier a ouvrir. }

Const
  MEM_COMMIT = $1000; MEM_RESERVE = $2000; MEM_RELEASE = $8000; PAGE_READWRITE = 4;
  SBS_HORZ = 0; SBS_VERT = 1;
  CM_OPEN = 101; CM_SAVEAS = 102; CM_PROPS = 103; CM_QUIT = 104;
  CM_ZIN = 201; CM_ZOUT = 202; CM_FIT = 203; CM_FITW = 204; CM_ACTUAL = 205;
  CM_Z25 = 206; CM_Z50 = 207; CM_Z200 = 208; CM_Z400 = 209;
  CM_ROTL = 301; CM_ROTR = 302; CM_ROT180 = 303; CM_FLIP = 304;
  CM_PFIRST = 401; CM_PPREV = 402; CM_PNEXT = 403; CM_PLAST = 404;
  CM_TOOLBAR = 501; CM_STATUS = 502; CM_ABOUT = 601;
  TbH = 30; StH = 22; SbW = 16;
  NTool = 9;

Type
  PByteP = ^Byte;
  PLong = ^LongInt;

Var
  { arene et tampon des decodeurs (Navigateur Web) }
  ArBase, ArSize, ArUsed, ImgBuf, ImgLen, PageBg, NImgs : LongInt;
  ArFull : Boolean;
  ImBmi, ImBits, ImW, ImH : Array[0..0] Of LongInt;
  { image affichee : DIB 24 bits (en-tete de 40 octets + pels) }
  Pic, PicW, PicH, PicBytes : LongInt;
  FilePath, FileFmt : String;
  FileSize, Page, Pages : LongInt;
  Zoom, ScrX, ScrY, FitMode : LongInt;       { zoom en % ; 1 fenetre, 2 largeur }
  CW, CH, MemDC, MemBmp, FontS, HSb, VSb, MenuBar, MView, MZoom : LongInt;
  ShowTb, ShowSt : Boolean;
  BtnDown : LongInt;
  Ofn : Array[0..21] Of LongInt;
  OfnFile : Array[0..259] Of Byte;
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

{ ==================================================================== }
{ Memoire (comme dans le Navigateur Web, pour ses decodeurs)            }
{ ==================================================================== }

Function RdB(A : LongInt) : LongInt;
Var Q : PByteP;
Begin
  Q := Pointer(A);
  RdB := Q^ And $FF;
End;

Procedure WrB(A, V : LongInt);
Var Q : PByteP;
Begin
  Q := Pointer(A);
  Q^ := V And $FF;
End;

Function RdL(A : LongInt) : LongInt;
Var Q : PLong;
Begin
  Q := Pointer(A);
  RdL := Q^;
End;

Procedure WrL(A, V : LongInt);
Var Q : PLong;
Begin
  Q := Pointer(A);
  Q^ := V;
End;

Procedure MemCopy(Src, Dst, N : LongInt);
Var I : LongInt;
Begin
  If (N <= 0) Or (Src = 0) Or (Dst = 0) Then Exit;
  If Dst <= Src Then
  Begin
    I := 0;
    While I + 4 <= N Do
    Begin
      WrL(Dst + I, RdL(Src + I));
      I := I + 4;
    End;
    While I < N Do
    Begin
      WrB(Dst + I, RdB(Src + I));
      Inc(I);
    End;
  End
  Else
    For I := N - 1 DownTo 0 Do WrB(Dst + I, RdB(Src + I));
End;

Procedure MemFill(Dst, N, V : LongInt);
Var I, W : LongInt;
Begin
  If (N <= 0) Or (Dst = 0) Then Exit;
  V := V And $FF;
  W := V Or (V Shl 8) Or (V Shl 16) Or (V Shl 24);
  I := 0;
  While I + 4 <= N Do
  Begin
    WrL(Dst + I, W);
    I := I + 4;
  End;
  While I < N Do
  Begin
    WrB(Dst + I, V);
    Inc(I);
  End;
End;

Function MemAlloc(N : LongInt) : LongInt;
Begin
  MemAlloc := VirtualAlloc(0, N, MEM_COMMIT Or MEM_RESERVE, PAGE_READWRITE);
End;

Procedure MemRelease(A : LongInt);
Begin
  If A <> 0 Then Dummy := VirtualFree(A, 0, MEM_RELEASE);
End;

Function ArAlloc(N : LongInt) : LongInt;
Begin
  ArAlloc := 0;
  If (ArBase = 0) Or (N < 0) Then Exit;
  N := (N + 3) And Not 3;
  If ArUsed + N > ArSize Then
  Begin
    ArFull := True;
    Exit;
  End;
  ArAlloc := ArBase + ArUsed;
  MemFill(ArBase + ArUsed, N, 0);
  ArUsed := ArUsed + N;
End;

{ ==================================================================== }
{ Images : GIF, PNG, JPEG (de base) et BMP (d'apres les decodeurs du    }
{ navigateur d'origine) ; resultat : pels 24 bits (B, V, R) de bas   }
{ en haut, dessines par GpiDrawBits. Chaque lecture est bornee : un     }
{ fichier tronque ou corrompu donne une image ignoree, sans plantage.   }
{ ==================================================================== }

Const
  IMG_MAXPIX = 8000000;          { pels au plus (8 millions) }
  SCRATCH = 33554432;            { memoire de travail des decodeurs }

Type
  THArr = Array[0..319] Of LongInt;

Var
  ScBase, ScUsed : LongInt;
  IErr : Boolean;
  IW, IH, IPix, IStride : LongInt;
  { LZW (GIF) }
  LzPre : Array[0..4095] Of LongInt;
  LzSuf : Array[0..4095] Of LongInt;
  LzStk : Array[0..4199] Of LongInt;
  { inflate }
  InSrc, InLen, InPos, InBit, InCnt : LongInt;
  OutBuf, OutCap, OutPos : LongInt;
  HLenCnt, HLenSym, HDstCnt, HDstSym, HLens : THArr;
  { JPEG (tableaux a une dimension : table * taille + indice) }
  JQ : Array[0..255] Of LongInt;
  JHBits : Array[0..143] Of LongInt;
  JHVal : Array[0..2047] Of LongInt;
  JHMax, JHMin, JHPtr : Array[0..143] Of LongInt;
  JNComp, JHmx, JVmx, JRst : LongInt;
  JCid, JCh, JCv, JCq, JCtd, JCta, JCpred, JCplane, JCw, JCh2 : Array[0..3] Of LongInt;
  JBitBuf, JBitCnt, JPos, JEnd : LongInt;
  JBlk, JTmp, JCos, JRow : Array[0..63] Of LongInt;

Procedure ScratchInit;
Begin
  ScBase := 0;
  ScBase := MemAlloc(SCRATCH);
  ScUsed := 0;
End;

Function ScAlloc(N : LongInt) : LongInt;
Begin
  ScAlloc := 0;
  N := (N + 3) And Not 3;
  If (ScBase = 0) Or (N <= 0) Or (ScUsed + N > SCRATCH) Then
  Begin
    IErr := True;
    Exit;
  End;
  ScAlloc := ScBase + ScUsed;
  ScUsed := ScUsed + N;
End;

{ octet I du fichier image (0 et erreur au-dela de la fin) }
Function IB(I : LongInt) : LongInt;
Begin
  If (I < 0) Or (I >= ImgLen) Then
  Begin
    IErr := True;
    IB := 0;
  End
  Else IB := RdB(ImgBuf + I);
End;

Function IW16(I : LongInt) : LongInt;
Begin
  IW16 := IB(I) Or (IB(I + 1) Shl 8);
End;

Function IB16(I : LongInt) : LongInt;
Begin
  IB16 := (IB(I) Shl 8) Or IB(I + 1);
End;

Function IL32(I : LongInt) : LongInt;
Begin
  IL32 := IB(I) Or (IB(I + 1) Shl 8) Or (IB(I + 2) Shl 16) Or (IB(I + 3) Shl 24);
End;

Function IB32(I : LongInt) : LongInt;
Begin
  IB32 := (IB(I) Shl 24) Or (IB(I + 1) Shl 16) Or (IB(I + 2) Shl 8) Or IB(I + 3);
End;

{ image de destination W x H (pels mis au fond de la page) }
Function NewImage(I, W, H : LongInt) : Boolean;
Var A, Bg, K : LongInt;
Begin
  NewImage := False;
  If (W <= 0) Or (H <= 0) Or (W > 8000) Or (H > 8000) Or (W * H > IMG_MAXPIX) Then Exit;
  { 24 bits par pel (B, V, R), lignes alignees sur 4 octets, de bas en
    haut : DIB de Windows (BITMAPINFOHEADER de 40 octets) }
  IStride := ((W * 3 + 3) Div 4) * 4;
  A := ArAlloc(IStride * H + 40);
  If A = 0 Then Exit;
  ImBmi[I] := A;
  MemFill(A, 40, 0);
  WrL(A, 40); WrL(A + 4, W); WrL(A + 8, H); WrL(A + 12, 1 Or (24 Shl 16));
  ImBits[I] := A + 40;
  ImW[I] := W; ImH[I] := H;
  IW := W; IH := H; IPix := A + 40;
  Bg := PageBg;
  For K := 0 To W - 1 Do
  Begin
    WrB(IPix + K * 3, Bg And 255); WrB(IPix + K * 3 + 1, (Bg Shr 8) And 255); WrB(IPix + K * 3 + 2, (Bg Shr 16) And 255);
  End;
  For K := 1 To H - 1 Do MemCopy(IPix, IPix + K * IStride, IStride);
  NewImage := True;
End;

{ pel (X, Y depuis le haut) en RVB }
Procedure PutPel(X, Y, Rgb : LongInt);
Var A : LongInt;
Begin
  If (X < 0) Or (Y < 0) Or (X >= IW) Or (Y >= IH) Then Exit;
  A := IPix + (IH - 1 - Y) * IStride + X * 3;
  WrB(A, Rgb And 255); WrB(A + 1, (Rgb Shr 8) And 255); WrB(A + 2, (Rgb Shr 16) And 255);
End;

{ pel avec transparence A (0..255) sur le fond de la page }
Procedure PutPelA(X, Y, Rgb, A : LongInt);
Var R, G, B, Bg : LongInt;
Begin
  If A >= 255 Then
  Begin
    PutPel(X, Y, Rgb);
    Exit;
  End;
  If A <= 0 Then Exit;
  Bg := PageBg;
  R := (((Rgb Shr 16) And 255) * A + ((Bg Shr 16) And 255) * (255 - A)) Div 255;
  G := (((Rgb Shr 8) And 255) * A + ((Bg Shr 8) And 255) * (255 - A)) Div 255;
  B := ((Rgb And 255) * A + (Bg And 255) * (255 - A)) Div 255;
  PutPel(X, Y, (R Shl 16) Or (G Shl 8) Or B);
End;

{ --- GIF (premiere image ; transparence) --- }

Function DecodeGif(Ix : LongInt) : Boolean;
Var P, Flags, Gct, GctN, LctN, Pal, Trans, L, T, W, H, Inter, MinCode, Data, DLen, N, K,
    Clear, Eoi, Avail, CodeSize, CodeMask, OldCode, Code, InCode, First, Sp, Bits, BitCnt, DPos, X, Y,
    Pass, Step, Cnt : LongInt; Stop : Boolean;
Begin
  DecodeGif := False;
  If Not NewImage(Ix, IW16(6), IW16(8)) Then Exit;
  Flags := IB(10);
  P := 13; Gct := 0; GctN := 0;
  If (Flags And $80) <> 0 Then
  Begin
    Gct := P; GctN := 2 Shl (Flags And 7);
    P := P + 3 * GctN;
  End;
  Trans := -1;
  Repeat
    If IErr Or (P >= ImgLen) Then Exit;
    K := IB(P);
    If K = $21 Then
    Begin
      { extension : controle graphique (transparence) }
      If (IB(P + 1) = $F9) And ((IB(P + 3) And 1) <> 0) Then Trans := IB(P + 6);
      P := P + 2;
      While (P < ImgLen) And (IB(P) <> 0) Do P := P + IB(P) + 1;
      Inc(P);
    End
    Else If K = $2C Then Break
    Else Exit;
  Until False;
  L := IW16(P + 1); T := IW16(P + 3); W := IW16(P + 5); H := IW16(P + 7); Flags := IB(P + 9);
  P := P + 10;
  Pal := Gct; LctN := GctN;
  If (Flags And $80) <> 0 Then
  Begin
    Pal := P; LctN := 2 Shl (Flags And 7);
    P := P + 3 * LctN;
  End;
  Inter := Flags And $40;
  If (Pal = 0) Or (W <= 0) Or (H <= 0) Then Exit;
  MinCode := IB(P);
  Inc(P);
  If (MinCode < 2) Or (MinCode > 11) Then Exit;
  { donnees LZW : sous-blocs concatenes }
  Data := ScAlloc(ImgLen);
  If Data = 0 Then Exit;
  DLen := 0;
  While (P < ImgLen) And (IB(P) <> 0) Do
  Begin
    N := IB(P);
    For K := 1 To N Do
      If P + K < ImgLen Then
      Begin
        WrB(Data + DLen, IB(P + K));
        Inc(DLen);
      End;
    P := P + N + 1;
  End;
  { decodage LZW }
  Clear := 1 Shl MinCode; Eoi := Clear + 1;
  Avail := Clear + 2; CodeSize := MinCode + 1; CodeMask := (1 Shl CodeSize) - 1;
  OldCode := -1; First := 0; Sp := 0;
  For K := 0 To 4095 Do
  Begin
    LzPre[K] := -1;
    If K < Clear Then LzSuf[K] := K Else LzSuf[K] := 0;
  End;
  Bits := 0; BitCnt := 0; DPos := 0;
  X := 0; Y := 0; Pass := 0;
  If Inter <> 0 Then Step := 8 Else Step := 1;
  Cnt := 0; Stop := False;
  While (Y < H) And (Cnt < W * H) And Not Stop Do
  Begin
    If Sp = 0 Then
    Begin
      While BitCnt < CodeSize Do
      Begin
        If DPos >= DLen Then
        Begin
          Stop := True;
          Break;
        End;
        Bits := Bits Or (RdB(Data + DPos) Shl BitCnt);
        Inc(DPos);
        BitCnt := BitCnt + 8;
      End;
      If Stop Then Break;
      Code := Bits And CodeMask;
      Bits := Bits Shr CodeSize;
      BitCnt := BitCnt - CodeSize;
      If Code = Clear Then
      Begin
        CodeSize := MinCode + 1; CodeMask := (1 Shl CodeSize) - 1; Avail := Clear + 2; OldCode := -1;
        Continue;
      End;
      If Code = Eoi Then Break;
      If OldCode = -1 Then
      Begin
        If Code >= Clear Then Break;
        LzStk[Sp] := LzSuf[Code]; Inc(Sp);
        OldCode := Code; First := Code;
      End
      Else
      Begin
        InCode := Code;
        If Code >= Avail Then
        Begin
          If Code > Avail Then Break;
          LzStk[Sp] := First; Inc(Sp);
          Code := OldCode;
        End;
        While (Code >= Clear) And (Sp < 4096) Do
        Begin
          LzStk[Sp] := LzSuf[Code]; Inc(Sp);
          Code := LzPre[Code];
          If Code < 0 Then Break;
        End;
        If (Code < 0) Or (Sp >= 4096) Then Break;
        First := LzSuf[Code];
        LzStk[Sp] := First; Inc(Sp);
        If Avail < 4096 Then
        Begin
          LzPre[Avail] := OldCode; LzSuf[Avail] := First;
          Inc(Avail);
          If ((Avail And CodeMask) = 0) And (Avail < 4096) Then
          Begin
            Inc(CodeSize);
            CodeMask := (1 Shl CodeSize) - 1;
          End;
        End;
        OldCode := InCode;
      End;
    End;
    { pel suivant }
    Dec(Sp);
    K := LzStk[Sp];
    If (K <> Trans) And (K < LctN) Then
      PutPel(L + X, T + Y, (IB(Pal + K * 3) Shl 16) Or (IB(Pal + K * 3 + 1) Shl 8) Or IB(Pal + K * 3 + 2));
    Inc(Cnt);
    Inc(X);
    If X >= W Then
    Begin
      X := 0;
      Y := Y + Step;
      If (Inter <> 0) And (Y >= H) Then
      Begin
        Inc(Pass);
        Case Pass Of
          1 :
            Begin
              Y := 4; Step := 8;
            End;
          2 :
            Begin
              Y := 2; Step := 4;
            End;
          3 :
            Begin
              Y := 1; Step := 2;
            End;
        End;
      End;
    End;
  End;
  DecodeGif := Cnt > 0;
End;

{ --- inflate (zlib, RFC 1950 / 1951 ; d'apres "puff" de Mark Adler) --- }

Function GetBit : LongInt;
Begin
  If InCnt = 0 Then
  Begin
    If InPos >= InLen Then
    Begin
      IErr := True;
      GetBit := 0;
      Exit;
    End;
    InBit := RdB(InSrc + InPos);
    Inc(InPos);
    InCnt := 8;
  End;
  GetBit := InBit And 1;
  InBit := InBit Shr 1;
  Dec(InCnt);
End;

Function GetBits(N : LongInt) : LongInt;
Var V, K : LongInt;
Begin
  V := 0;
  For K := 0 To N - 1 Do V := V Or (GetBit Shl K);
  GetBits := V;
End;

{ table de Huffman canonique : nombre de codes par longueur (Cnt[1..15])
  et symboles dans l'ordre des codes (Sym) }
Procedure HBuild(Var Cnt, Sym, Lens : THArr; N : LongInt);
Var Offs : Array[0..16] Of LongInt; K : LongInt;
Begin
  For K := 0 To 15 Do Cnt[K] := 0;
  For K := 0 To N - 1 Do Inc(Cnt[Lens[K] And 15]);
  Cnt[0] := 0;
  Offs[1] := 0;
  For K := 1 To 14 Do Offs[K + 1] := Offs[K] + Cnt[K];
  For K := 0 To N - 1 Do
    If Lens[K] <> 0 Then
    Begin
      Sym[Offs[Lens[K]]] := K;
      Inc(Offs[Lens[K]]);
    End;
End;

{ un symbole (D = 0 : longueurs et litteraux, D = 1 : distances) }
Function HDecode(D : LongInt) : LongInt;
Var Code, First, Idx, Len, Count : LongInt;
Begin
  Code := 0; First := 0; Idx := 0;
  For Len := 1 To 15 Do
  Begin
    Code := Code Or GetBit;
    If D = 0 Then Count := HLenCnt[Len] Else Count := HDstCnt[Len];
    If Code - Count < First Then
    Begin
      If D = 0 Then HDecode := HLenSym[Idx + (Code - First)] Else HDecode := HDstSym[Idx + (Code - First)];
      Exit;
    End;
    Idx := Idx + Count;
    First := (First + Count) Shl 1;
    Code := Code Shl 1;
    If IErr Then Break;
  End;
  IErr := True;
  HDecode := -1;
End;

Procedure OutByte(B : LongInt);
Begin
  If OutPos < OutCap Then WrB(OutBuf + OutPos, B) Else IErr := True;
  Inc(OutPos);
End;

Const
  LBase : Array[0..28] Of LongInt = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
                                     115, 131, 163, 195, 227, 258);
  LExt : Array[0..28] Of LongInt = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DBase : Array[0..29] Of LongInt = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
                                     1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577);
  DExt : Array[0..29] Of LongInt = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
                                    12, 12, 13, 13);
  CLOrd : Array[0..18] Of LongInt = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);

Procedure InflateCodes;
Var S, L, D, K : LongInt;
Begin
  Repeat
    S := HDecode(0);
    If IErr Or (S < 0) Then Exit;
    If S < 256 Then OutByte(S)
    Else If S > 256 Then
    Begin
      S := S - 257;
      If S > 28 Then
      Begin
        IErr := True;
        Exit;
      End;
      L := LBase[S] + GetBits(LExt[S]);
      S := HDecode(1);
      If (S < 0) Or (S > 29) Then
      Begin
        IErr := True;
        Exit;
      End;
      D := DBase[S] + GetBits(DExt[S]);
      If D > OutPos Then
      Begin
        IErr := True;
        Exit;
      End;
      For K := 1 To L Do
      Begin
        If OutPos < OutCap Then WrB(OutBuf + OutPos, RdB(OutBuf + OutPos - D)) Else IErr := True;
        Inc(OutPos);
      End;
    End;
  Until (S = 256) Or IErr;
End;

Function Inflate(Src, SLen, Dst, DCap : LongInt) : LongInt;
Var Last, Typ, K, N, NLen, NDist, NCode, S, Rep, Prev : LongInt;
Begin
  InSrc := Src; InLen := SLen; InPos := 0; InCnt := 0; InBit := 0;
  OutBuf := Dst; OutCap := DCap; OutPos := 0;
  Repeat
    Last := GetBit;
    Typ := GetBits(2);
    If Typ = 0 Then
    Begin
      { bloc stocke }
      InCnt := 0;
      If InPos + 4 > InLen Then
      Begin
        IErr := True;
        Break;
      End;
      N := RdB(InSrc + InPos) Or (RdB(InSrc + InPos + 1) Shl 8);
      InPos := InPos + 4;
      For K := 1 To N Do
      Begin
        If InPos >= InLen Then
        Begin
          IErr := True;
          Break;
        End;
        OutByte(RdB(InSrc + InPos));
        Inc(InPos);
      End;
    End
    Else If Typ = 1 Then
    Begin
      { codes fixes }
      For K := 0 To 143 Do HLens[K] := 8;
      For K := 144 To 255 Do HLens[K] := 9;
      For K := 256 To 279 Do HLens[K] := 7;
      For K := 280 To 287 Do HLens[K] := 8;
      HBuild(HLenCnt, HLenSym, HLens, 288);
      For K := 0 To 29 Do HLens[K] := 5;
      HBuild(HDstCnt, HDstSym, HLens, 30);
      InflateCodes;
    End
    Else If Typ = 2 Then
    Begin
      { codes dynamiques }
      NLen := GetBits(5) + 257; NDist := GetBits(5) + 1; NCode := GetBits(4) + 4;
      If (NLen > 286) Or (NDist > 30) Then
      Begin
        IErr := True;
        Break;
      End;
      For K := 0 To 18 Do HLens[K] := 0;
      For K := 0 To NCode - 1 Do HLens[CLOrd[K]] := GetBits(3);
      HBuild(HLenCnt, HLenSym, HLens, 19);
      K := 0;
      While (K < NLen + NDist) And Not IErr Do
      Begin
        S := HDecode(0);
        If S < 0 Then Break;
        If S < 16 Then
        Begin
          HLens[K] := S;
          Inc(K);
        End
        Else
        Begin
          Prev := 0;
          If S = 16 Then
          Begin
            If K = 0 Then
            Begin
              IErr := True;
              Break;
            End;
            Prev := HLens[K - 1];
            Rep := 3 + GetBits(2);
          End
          Else If S = 17 Then Rep := 3 + GetBits(3)
          Else Rep := 11 + GetBits(7);
          If K + Rep > NLen + NDist Then
          Begin
            IErr := True;
            Break;
          End;
          While Rep > 0 Do
          Begin
            HLens[K] := Prev;
            Inc(K); Dec(Rep);
          End;
        End;
      End;
      If IErr Then Break;
      HBuild(HLenCnt, HLenSym, HLens, NLen);
      For K := 0 To NDist - 1 Do HLens[K] := HLens[NLen + K];
      HBuild(HDstCnt, HDstSym, HLens, NDist);
      InflateCodes;
    End
    Else IErr := True;
  Until (Last = 1) Or IErr;
  Inflate := OutPos;
End;

{ --- PNG --- }

Function Paeth(A, B, C : LongInt) : LongInt;
Var P, Pa, Pb, Pc : LongInt;
Begin
  P := A + B - C;
  Pa := Abs(P - A); Pb := Abs(P - B); Pc := Abs(P - C);
  If (Pa <= Pb) And (Pa <= Pc) Then Paeth := A
  Else If Pb <= Pc Then Paeth := B
  Else Paeth := C;
End;

{ defiltrage de H lignes de RowB octets (filtre en tete de ligne), Bpp
  octets par pel }
Function Unfilter(Src, RowB, H, Bpp : LongInt) : Boolean;
Var Y, X, F, R, Pr, A, B, C, V : LongInt;
Begin
  Unfilter := False;
  For Y := 0 To H - 1 Do
  Begin
    R := Src + Y * (RowB + 1);
    F := RdB(R);
    Inc(R);
    If Y > 0 Then Pr := Src + (Y - 1) * (RowB + 1) + 1 Else Pr := 0;
    If F > 4 Then Exit;
    If F <> 0 Then
      For X := 0 To RowB - 1 Do
      Begin
        If X >= Bpp Then A := RdB(R + X - Bpp) Else A := 0;
        If Pr <> 0 Then B := RdB(Pr + X) Else B := 0;
        If (Pr <> 0) And (X >= Bpp) Then C := RdB(Pr + X - Bpp) Else C := 0;
        V := RdB(R + X);
        Case F Of
          1 : V := V + A;
          2 : V := V + B;
          3 : V := V + (A + B) Div 2;
          4 : V := V + Paeth(A, B, C);
        End;
        WrB(R + X, V And 255);
      End;
  End;
  Unfilter := True;
End;

Var
  PngCT, PngBD, PngPal, PngPalN, PngTrns, PngTrnsN : LongInt;

{ pel X d'une ligne defiltree -> RVB et alpha }
Procedure PngPel(R, X : LongInt; Var Rgb, A : LongInt);
Var V, Sh, Mx, G : LongInt;
Begin
  A := 255; Rgb := 0;
  Case PngCT Of
    0, 3 :
      Begin
        If PngBD = 8 Then V := RdB(R + X)
        Else If PngBD = 16 Then V := RdB(R + X * 2)
        Else
        Begin
          Sh := 8 - PngBD - (X * PngBD) Mod 8;
          V := (RdB(R + (X * PngBD) Div 8) Shr Sh) And ((1 Shl PngBD) - 1);
        End;
        If PngCT = 3 Then
        Begin
          If V < PngPalN Then Rgb := (IB(PngPal + V * 3) Shl 16) Or (IB(PngPal + V * 3 + 1) Shl 8) Or IB(PngPal + V * 3 + 2);
          If V < PngTrnsN Then A := IB(PngTrns + V);
        End
        Else
        Begin
          If PngBD < 8 Then
          Begin
            Mx := (1 Shl PngBD) - 1;
            G := (V * 255) Div Mx;
          End
          Else G := V;
          Rgb := (G Shl 16) Or (G Shl 8) Or G;
          If (PngTrnsN >= 2) And (PngBD < 8) And (V = (IB(PngTrns + 1) And ((1 Shl PngBD) - 1))) Then A := 0;
          If (PngTrnsN >= 2) And (PngBD = 8) And (V = IB(PngTrns + 1)) Then A := 0;
        End;
      End;
    2 :
      If PngBD = 8 Then Rgb := (RdB(R + X * 3) Shl 16) Or (RdB(R + X * 3 + 1) Shl 8) Or RdB(R + X * 3 + 2)
      Else Rgb := (RdB(R + X * 6) Shl 16) Or (RdB(R + X * 6 + 2) Shl 8) Or RdB(R + X * 6 + 4);
    4 :
      If PngBD = 8 Then
      Begin
        G := RdB(R + X * 2); A := RdB(R + X * 2 + 1);
        Rgb := (G Shl 16) Or (G Shl 8) Or G;
      End
      Else
      Begin
        G := RdB(R + X * 4); A := RdB(R + X * 4 + 2);
        Rgb := (G Shl 16) Or (G Shl 8) Or G;
      End;
    6 :
      If PngBD = 8 Then
      Begin
        Rgb := (RdB(R + X * 4) Shl 16) Or (RdB(R + X * 4 + 1) Shl 8) Or RdB(R + X * 4 + 2);
        A := RdB(R + X * 4 + 3);
      End
      Else
      Begin
        Rgb := (RdB(R + X * 8) Shl 16) Or (RdB(R + X * 8 + 2) Shl 8) Or RdB(R + X * 8 + 4);
        A := RdB(R + X * 8 + 6);
      End;
  End;
End;

Const
  AX0 : Array[0..6] Of LongInt = (0, 4, 0, 2, 0, 1, 0);
  AY0 : Array[0..6] Of LongInt = (0, 0, 4, 0, 2, 0, 1);
  ADX : Array[0..6] Of LongInt = (8, 8, 4, 4, 2, 2, 1);
  ADY : Array[0..6] Of LongInt = (8, 8, 8, 4, 4, 2, 2);

Function DecodePng(Ix : LongInt) : Boolean;
Var P, L, T, W, H, Inter, Idat, ILen, Raw, RawCap, Got, Chans, BitsPx, Bpp, RowB, Y, X, Rgb, A, Pass, Pw, Ph,
    Off, Px0, Py0, Dx, Dy : LongInt;
Begin
  DecodePng := False;
  W := IB32(16); H := IB32(20); PngBD := IB(24); PngCT := IB(25); Inter := IB(28);
  If (W <= 0) Or (H <= 0) Or (W > 8000) Or (H > 8000) Or (W * H > IMG_MAXPIX) Then Exit;
  Case PngCT Of
    0, 3 : Chans := 1;
    2 : Chans := 3;
    4 : Chans := 2;
    6 : Chans := 4;
  Else
    Exit;
  End;
  If Not (PngBD In [1, 2, 4, 8, 16]) Then Exit;
  BitsPx := Chans * PngBD;
  Bpp := MaxI(1, BitsPx Div 8);
  { morceaux : PLTE, tRNS, IDAT }
  PngPal := 0; PngPalN := 0; PngTrns := 0; PngTrnsN := 0;
  Idat := ScAlloc(ImgLen);
  If Idat = 0 Then Exit;
  ILen := 0;
  P := 8;
  While (P + 8 <= ImgLen) And Not IErr Do
  Begin
    L := IB32(P); T := IB32(P + 4);
    If (L < 0) Or (P + 12 + L > ImgLen) Then Break;
    If T = $504C5445 Then
    Begin
      PngPal := P + 8; PngPalN := L Div 3;
    End
    Else If T = $74524E53 Then
    Begin
      PngTrns := P + 8; PngTrnsN := L;
    End
    Else If T = $49444154 Then
    Begin
      MemCopy(ImgBuf + P + 8, Idat + ILen, L);
      ILen := ILen + L;
    End
    Else If T = $49454E44 Then Break;
    P := P + 12 + L;
  End;
  IErr := False;
  If (ILen < 3) Or ((PngCT = 3) And (PngPal = 0)) Then Exit;
  { taille des donnees decompressees }
  RawCap := ((W * BitsPx + 7) Div 8 + 1) * H;
  If Inter <> 0 Then RawCap := RawCap * 2 + 64;
  Raw := ScAlloc(RawCap + 16);
  If Raw = 0 Then Exit;
  Got := Inflate(Idat + 2, ILen - 2, Raw, RawCap + 16);
  IErr := False;
  If Got <= 0 Then Exit;
  If Not NewImage(Ix, W, H) Then Exit;
  If Inter = 0 Then
  Begin
    RowB := (W * BitsPx + 7) Div 8;
    If Got < (RowB + 1) * H Then H := Got Div (RowB + 1);
    If Not Unfilter(Raw, RowB, H, Bpp) Then Exit;
    For Y := 0 To H - 1 Do
      For X := 0 To W - 1 Do
      Begin
        PngPel(Raw + Y * (RowB + 1) + 1, X, Rgb, A);
        PutPelA(X, Y, Rgb, A);
      End;
  End
  Else
  Begin
    { Adam7 : sept passes }
    Off := 0;
    For Pass := 0 To 6 Do
    Begin
      Px0 := AX0[Pass]; Py0 := AY0[Pass]; Dx := ADX[Pass]; Dy := ADY[Pass];
      If W > Px0 Then Pw := (W - Px0 + Dx - 1) Div Dx Else Pw := 0;
      If H > Py0 Then Ph := (H - Py0 + Dy - 1) Div Dy Else Ph := 0;
      If (Pw = 0) Or (Ph = 0) Then Continue;
      RowB := (Pw * BitsPx + 7) Div 8;
      If Off + (RowB + 1) * Ph > Got Then Break;
      If Not Unfilter(Raw + Off, RowB, Ph, Bpp) Then Exit;
      For Y := 0 To Ph - 1 Do
        For X := 0 To Pw - 1 Do
        Begin
          PngPel(Raw + Off + Y * (RowB + 1) + 1, X, Rgb, A);
          PutPelA(Px0 + X * Dx, Py0 + Y * Dy, Rgb, A);
        End;
      Off := Off + (RowB + 1) * Ph;
    End;
  End;
  DecodePng := True;
End;

{ --- BMP (1, 4, 8, 24 et 32 bits, non compresse) --- }

Function DecodeBmp(Ix : LongInt) : Boolean;
Var Hd, W, H, Bpp, Cmp, Pal, PalSz, Bits, Stride, X, Y, Yy, V, A, Top : LongInt;
Begin
  DecodeBmp := False;
  Hd := 14;
  If IL32(Hd) = 12 Then
  Begin
    W := IW16(Hd + 4); H := IW16(Hd + 6); Bpp := IW16(Hd + 10); Cmp := 0; PalSz := 3;
  End
  Else
  Begin
    W := IL32(Hd + 4); H := IL32(Hd + 8); Bpp := IW16(Hd + 14); Cmp := IL32(Hd + 16); PalSz := 4;
  End;
  Top := 0;
  If H < 0 Then
  Begin
    H := -H; Top := 1;
  End;
  If Not (Bpp In [1, 4, 8, 24, 32]) Or ((Cmp <> 0) And (Cmp <> 3)) Then Exit;
  Pal := Hd + IL32(Hd);
  Bits := IL32(10);
  Stride := ((W * Bpp + 31) Div 32) * 4;
  If Not NewImage(Ix, W, H) Then Exit;
  For Y := 0 To H - 1 Do
  Begin
    If Top = 1 Then Yy := Y Else Yy := H - 1 - Y;
    A := Bits + Yy * Stride;
    If A + Stride > ImgLen Then Continue;
    For X := 0 To W - 1 Do
    Begin
      Case Bpp Of
        1 : V := (IB(A + X Shr 3) Shr (7 - (X And 7))) And 1;
        4 : V := (IB(A + X Shr 1) Shr (4 * (1 - (X And 1)))) And 15;
        8 : V := IB(A + X);
        24 : V := -1 - ((IB(A + X * 3 + 2) Shl 16) Or (IB(A + X * 3 + 1) Shl 8) Or IB(A + X * 3));
      Else
        V := -1 - ((IB(A + X * 4 + 2) Shl 16) Or (IB(A + X * 4 + 1) Shl 8) Or IB(A + X * 4));
      End;
      If V >= 0 Then V := (IB(Pal + V * PalSz + 2) Shl 16) Or (IB(Pal + V * PalSz + 1) Shl 8) Or IB(Pal + V * PalSz)
      Else V := -1 - V;
      PutPel(X, Y, V);
    End;
  End;
  DecodeBmp := True;
End;

{ --- JPEG (de base, Huffman ; sous-echantillonnage, reprises) --- }

Const
  ZigZag : Array[0..63] Of LongInt = (0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
                                      41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15,
                                      23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63);
  { cos(k pi / 16) * 4096, k = 0..8 }
  CosT : Array[0..8] Of LongInt = (4096, 4017, 3784, 3406, 2896, 2276, 1567, 799, 0);

{ cosinus de l'IDCT : C(u) cos((2x + 1) u pi / 16) * 4096 }
Procedure JInitCos;
Var X, U, K, S : LongInt;
Begin
  For X := 0 To 7 Do
    For U := 0 To 7 Do
    Begin
      K := ((2 * X + 1) * U) Mod 32;
      S := 1;
      If K > 16 Then K := 32 - K;
      If K > 8 Then
      Begin
        K := 16 - K; S := -1;
      End;
      If U = 0 Then JCos[X * 8 + U] := 2896
      Else JCos[X * 8 + U] := S * CosT[K];
    End;
End;

Function JByte : LongInt;
Begin
  If JPos < JEnd Then
  Begin
    JByte := IB(JPos);
    Inc(JPos);
  End
  Else JByte := 0;
End;

Function JBit : LongInt;
Var B : LongInt;
Begin
  If JBitCnt = 0 Then
  Begin
    B := JByte;
    If B = $FF Then
    Begin
      { octet de bourrage FF00 ; un marqueur arrete les donnees }
      If (JPos < JEnd) And (IB(JPos) = 0) Then Inc(JPos)
      Else
      Begin
        Dec(JPos);
        B := 0;
      End;
    End;
    JBitBuf := B;
    JBitCnt := 8;
  End;
  Dec(JBitCnt);
  JBit := (JBitBuf Shr JBitCnt) And 1;
End;

Function JBits(N : LongInt) : LongInt;
Var V, K : LongInt;
Begin
  V := 0;
  For K := 1 To N Do V := (V Shl 1) Or JBit;
  JBits := V;
End;

Function JExtend(V, N : LongInt) : LongInt;
Begin
  If N = 0 Then JExtend := 0
  Else If V < (1 Shl (N - 1)) Then JExtend := V - (1 Shl N) + 1
  Else JExtend := V;
End;

Function JDecode(T : LongInt) : LongInt;
Var Code, L : LongInt;
Begin
  Code := JBit;
  L := 1;
  While (L <= 16) And ((JHMax[T * 18 + L] < 0) Or (Code > JHMax[T * 18 + L])) Do
  Begin
    Code := (Code Shl 1) Or JBit;
    Inc(L);
  End;
  If L > 16 Then
  Begin
    IErr := True;
    JDecode := 0;
    Exit;
  End;
  JDecode := JHVal[T * 256 + ((JHPtr[T * 18 + L] + Code - JHMin[T * 18 + L]) And 255)];
End;

{ IDCT 8 x 8 (separable, virgule fixe) de JBlk vers JTmp (0..255) }
Procedure JIdct;
Var X, Y, U, S : LongInt;
Begin
  For Y := 0 To 7 Do
    For X := 0 To 7 Do
    Begin
      S := 0;
      For U := 0 To 7 Do
        If JBlk[Y * 8 + U] <> 0 Then S := S + JBlk[Y * 8 + U] * JCos[X * 8 + U];
      JRow[Y * 8 + X] := S Div 4096;
    End;
  For X := 0 To 7 Do
    For Y := 0 To 7 Do
    Begin
      S := 0;
      For U := 0 To 7 Do S := S + JRow[U * 8 + X] * JCos[Y * 8 + U];
      S := S Div 16384 + 128;
      If S < 0 Then S := 0 Else If S > 255 Then S := 255;
      JTmp[Y * 8 + X] := S;
    End;
End;

Procedure JBlock(C, Bx, By : LongInt);
Var K, S, R, V, Q, X, Y, Pl, W : LongInt;
Begin
  For K := 0 To 63 Do JBlk[K] := 0;
  { coefficient continu }
  S := JDecode(JCtd[C]);
  If (S < 0) Or (S > 15) Then
  Begin
    IErr := True;
    Exit;
  End;
  V := JExtend(JBits(S), S);
  JCpred[C] := JCpred[C] + V;
  Q := JCq[C] * 64;
  JBlk[0] := JCpred[C] * JQ[Q];
  { coefficients alternatifs }
  K := 1;
  While (K < 64) And Not IErr Do
  Begin
    S := JDecode(4 + JCta[C]);
    R := (S Shr 4) And 15; S := S And 15;
    If S = 0 Then
    Begin
      If R = 15 Then K := K + 16 Else Break;
    End
    Else
    Begin
      K := K + R;
      If K > 63 Then Break;
      V := JExtend(JBits(S), S);
      JBlk[ZigZag[K]] := V * JQ[Q + K];
      Inc(K);
    End;
  End;
  JIdct;
  Pl := JCplane[C]; W := JCw[C];
  For Y := 0 To 7 Do
    If By + Y < JCh2[C] Then
      For X := 0 To 7 Do
        If Bx + X < W Then WrB(Pl + (By + Y) * W + Bx + X, JTmp[Y * 8 + X]);
End;

Function DecodeJpeg(Ix : LongInt) : Boolean;
Var P, M, L, K, J, T, N, C, Code, Cnt, Mx, My, Mcx, Mcy, X, Y, Yy, Cb, Cr, R, G, B, Sx, Sy, Restart,
    W, H, Base : LongInt; Done : Boolean;
Begin
  DecodeJpeg := False;
  JInitCos;
  For K := 0 To 143 Do JHMax[K] := -1;
  W := 0; H := 0; JNComp := 0; JRst := 0;
  P := 2; Done := False;
  While (P + 4 <= ImgLen) And Not Done And Not IErr Do
  Begin
    If IB(P) <> $FF Then
    Begin
      Inc(P);
      Continue;
    End;
    M := IB(P + 1);
    If (M = $FF) Or (M = $D8) Or ((M >= $D0) And (M <= $D7)) Or (M = 1) Then
    Begin
      Inc(P);
      Continue;
    End;
    L := IB16(P + 2);
    Base := P + 4;
    Case M Of
      $DB :
        Begin
          { tables de quantification }
          K := Base;
          While K < P + 2 + L Do
          Begin
            T := IB(K) And 3;
            If (IB(K) Shr 4) = 0 Then
            Begin
              For J := 0 To 63 Do JQ[T * 64 + J] := IB(K + 1 + J);
              K := K + 65;
            End
            Else
            Begin
              For J := 0 To 63 Do JQ[T * 64 + J] := IB16(K + 1 + J * 2);
              K := K + 129;
            End;
          End;
        End;
      $C0, $C1 :
        Begin
          H := IB16(Base + 1); W := IB16(Base + 3); JNComp := IB(Base + 5);
          If (JNComp <> 1) And (JNComp <> 3) Then Exit;
          JHmx := 1; JVmx := 1;
          For C := 0 To JNComp - 1 Do
          Begin
            JCid[C] := IB(Base + 6 + C * 3);
            JCh[C] := IB(Base + 7 + C * 3) Shr 4; JCv[C] := IB(Base + 7 + C * 3) And 15;
            JCq[C] := IB(Base + 8 + C * 3) And 3;
            If (JCh[C] < 1) Or (JCh[C] > 4) Or (JCv[C] < 1) Or (JCv[C] > 4) Then Exit;
            If JCh[C] > JHmx Then JHmx := JCh[C];
            If JCv[C] > JVmx Then JVmx := JCv[C];
          End;
        End;
      $C2, $C3, $C5, $C6, $C7, $C9, $CA, $CB, $CD, $CE, $CF : Exit;   { progressif, sans perte, arithmetique }
      $C4 :
        Begin
          { tables de Huffman }
          K := Base;
          While (K < P + 2 + L) And Not IErr Do
          Begin
            T := (IB(K) And 3) + ((IB(K) Shr 4) And 1) * 4;
            N := 0;
            For J := 1 To 16 Do
            Begin
              JHBits[T * 18 + J] := IB(K + J);
              N := N + JHBits[T * 18 + J];
            End;
            If N > 256 Then Exit;
            For J := 0 To N - 1 Do JHVal[T * 256 + J] := IB(K + 17 + J);
            { codes canoniques : minimum, maximum, indice }
            Code := 0; Cnt := 0;
            For J := 1 To 16 Do
            Begin
              JHPtr[T * 18 + J] := Cnt;
              JHMin[T * 18 + J] := Code;
              Code := Code + JHBits[T * 18 + J];
              Cnt := Cnt + JHBits[T * 18 + J];
              If JHBits[T * 18 + J] > 0 Then JHMax[T * 18 + J] := Code - 1 Else JHMax[T * 18 + J] := -1;
              Code := Code Shl 1;
            End;
            K := K + 17 + N;
          End;
        End;
      $DD : JRst := IB16(Base);
      $DA :
        Begin
          { debut des donnees : composantes du balayage }
          N := IB(Base);
          For J := 0 To N - 1 Do
            For C := 0 To JNComp - 1 Do
              If JCid[C] = IB(Base + 1 + J * 2) Then
              Begin
                JCtd[C] := (IB(Base + 2 + J * 2) Shr 4) And 3;
                JCta[C] := IB(Base + 2 + J * 2) And 3;
              End;
          JPos := P + 2 + L; JEnd := ImgLen;
          Done := True;
        End;
      $D9 : Exit;
    End;
    If Not Done Then P := P + 2 + L;
  End;
  If (Not Done) Or IErr Or (W <= 0) Or (H <= 0) Or (JNComp = 0) Or (W * H > IMG_MAXPIX) Then Exit;
  { plans des composantes (taille arrondie aux MCU) }
  Mcx := (W + 8 * JHmx - 1) Div (8 * JHmx);
  Mcy := (H + 8 * JVmx - 1) Div (8 * JVmx);
  For C := 0 To JNComp - 1 Do
  Begin
    JCw[C] := Mcx * JCh[C] * 8; JCh2[C] := Mcy * JCv[C] * 8;
    JCplane[C] := ScAlloc(JCw[C] * JCh2[C]);
    If JCplane[C] = 0 Then Exit;
    MemFill(JCplane[C], JCw[C] * JCh2[C], 128);
    JCpred[C] := 0;
  End;
  JBitCnt := 0; Restart := 0;
  For My := 0 To Mcy - 1 Do
  Begin
    For Mx := 0 To Mcx - 1 Do
    Begin
      If IErr Then Break;
      If (JRst > 0) And (Restart = JRst) Then
      Begin
        { marqueur de reprise RSTn }
        JBitCnt := 0;
        While (JPos + 1 < JEnd) And Not ((IB(JPos) = $FF) And (IB(JPos + 1) >= $D0) And (IB(JPos + 1) <= $D7)) Do
          Inc(JPos);
        JPos := JPos + 2;
        For C := 0 To JNComp - 1 Do JCpred[C] := 0;
        Restart := 0;
      End;
      For C := 0 To JNComp - 1 Do
        For Sy := 0 To JCv[C] - 1 Do
          For Sx := 0 To JCh[C] - 1 Do
            If Not IErr Then JBlock(C, (Mx * JCh[C] + Sx) * 8, (My * JCv[C] + Sy) * 8);
      Inc(Restart);
    End;
    If IErr Then Break;
  End;
  { image partielle gardee si les donnees sont tronquees }
  IErr := False;
  If Not NewImage(Ix, W, H) Then Exit;
  For Y := 0 To H - 1 Do
    For X := 0 To W - 1 Do
    Begin
      Yy := RdB(JCplane[0] + ((Y * JCv[0]) Div JVmx) * JCw[0] + (X * JCh[0]) Div JHmx);
      If JNComp = 3 Then
      Begin
        Cb := RdB(JCplane[1] + ((Y * JCv[1]) Div JVmx) * JCw[1] + (X * JCh[1]) Div JHmx) - 128;
        Cr := RdB(JCplane[2] + ((Y * JCv[2]) Div JVmx) * JCw[2] + (X * JCh[2]) Div JHmx) - 128;
        R := Yy + (91881 * Cr) Div 65536;
        G := Yy - (22554 * Cb + 46802 * Cr) Div 65536;
        B := Yy + (116130 * Cb) Div 65536;
        If R < 0 Then R := 0 Else If R > 255 Then R := 255;
        If G < 0 Then G := 0 Else If G > 255 Then G := 255;
        If B < 0 Then B := 0 Else If B > 255 Then B := 255;
        PutPel(X, Y, (R Shl 16) Or (G Shl 8) Or B);
      End
      Else PutPel(X, Y, (Yy Shl 16) Or (Yy Shl 8) Or Yy);
    End;
  DecodeJpeg := True;
End;

{ decode l'image I (ImgBuf, ImgLen octets) ; format reconnu par sa
  signature }
{ ==================================================================== }
{ TIFF (format natif d'Imaging)                                         }
{ ==================================================================== }

Var
  TBig : Boolean;

Function TW(I : LongInt) : LongInt;
Begin
  If TBig Then TW := IB16(I) Else TW := IW16(I);
End;

Function TL(I : LongInt) : LongInt;
Begin
  If TBig Then TL := IB32(I) Else TL := IL32(I);
End;

{ valeur K d'une entree (type 3 SHORT ou 4 LONG) }
Function TVal(E, K : LongInt) : LongInt;
Var Ty, N, Sz, P : LongInt;
Begin
  Ty := TW(E + 2); N := TL(E + 4);
  If Ty = 3 Then Sz := 2 Else If Ty = 1 Then Sz := 1 Else Sz := 4;
  If N * Sz <= 4 Then P := E + 8 Else P := TL(E + 8);
  If Ty = 3 Then TVal := TW(P + K * 2)
  Else If Ty = 1 Then TVal := IB(P + K)
  Else TVal := TL(P + K * 4);
End;

{ nombre de pages (repertoires) d'un TIFF }
Function TiffPages : LongInt;
Var P, N, K : LongInt;
Begin
  TBig := IB(0) = $4D;
  P := TL(4); N := 0;
  While (P > 0) And (P < ImgLen) And (N < 1000) Do
  Begin
    Inc(N);
    K := TW(P);
    P := TL(P + 2 + K * 12);
  End;
  TiffPages := N;
End;

{ LZW de TIFF : codes de 9 a 12 bits, poids fort d'abord, changement de
  taille anticipe ; Src (N octets) -> Dst (Cap octets), octets produits }
Function TiffLzw(Src, N, Dst, Cap : LongInt) : LongInt;
Var Bit, Width, Code, Old, Next, Out0, First, Sp, C, K, V : LongInt;
Begin
  Bit := 0; Width := 9; Next := 258; Old := -1; Out0 := 0; First := 0;
  For K := 0 To 255 Do Begin LzPre[K] := -1; LzSuf[K] := K; End;
  While (Bit + Width <= N * 8) And (Out0 < Cap) Do
  Begin
    { code de Width bits a la position Bit }
    V := 0;
    For K := 0 To Width - 1 Do
      V := (V Shl 1) Or ((RdB(Src + (Bit + K) Shr 3) Shr (7 - ((Bit + K) And 7))) And 1);
    Bit := Bit + Width;
    Code := V;
    If Code = 257 Then Break;
    If Code = 256 Then
    Begin
      Width := 9; Next := 258; Old := -1;
      Continue;
    End;
    If Old = -1 Then
    Begin
      If Code > 255 Then Break;
      WrB(Dst + Out0, Code); Inc(Out0);
      First := Code; Old := Code;
      Continue;
    End;
    { chaine du code (ou de l'ancien + son premier octet) }
    Sp := 0;
    If Code < Next Then C := Code
    Else
    Begin
      LzStk[Sp] := First; Inc(Sp);
      C := Old;
    End;
    While (C > 255) And (Sp < 4190) Do
    Begin
      LzStk[Sp] := LzSuf[C]; Inc(Sp);
      C := LzPre[C];
    End;
    LzStk[Sp] := C; Inc(Sp);
    First := C;
    While (Sp > 0) And (Out0 < Cap) Do
    Begin
      Dec(Sp);
      WrB(Dst + Out0, LzStk[Sp]); Inc(Out0);
    End;
    If Next < 4096 Then
    Begin
      LzPre[Next] := Old; LzSuf[Next] := First;
      Inc(Next);
      If (Next = 511) Or (Next = 1023) Or (Next = 2047) Then Inc(Width);
      If Width > 12 Then Width := 12;
    End;
    Old := Code;
  End;
  TiffLzw := Out0;
End;

{ PackBits : Src (N) -> Dst (Cap) }
Function TiffPack(Src, N, Dst, Cap : LongInt) : LongInt;
Var I, O, C, K, V : LongInt;
Begin
  I := 0; O := 0;
  While (I < N) And (O < Cap) Do
  Begin
    C := RdB(Src + I); Inc(I);
    If C < 128 Then
    Begin
      For K := 0 To C Do
        If (I < N) And (O < Cap) Then Begin WrB(Dst + O, RdB(Src + I)); Inc(O); Inc(I); End;
    End
    Else If C > 128 Then
    Begin
      V := RdB(Src + I); Inc(I);
      For K := 0 To 256 - C Do
        If O < Cap Then Begin WrB(Dst + O, V); Inc(O); End;
    End;
  End;
  TiffPack := O;
End;

Function DecodeTiff(Ix, PageNo : LongInt) : Boolean;
Var P, N, K, E, Tag, W, H, Bps, Comp, Photo, Spp, Rps, Pred, NStrip, EOff, ECnt, Cmap, CmN, RowB, Buf, Got,
    S, Off, Len, Y0, X, Y, V, R, G, B, Row, Raw, BitP : LongInt;
Begin
  DecodeTiff := False;
  TBig := IB(0) = $4D;
  P := TL(4);
  For K := 1 To PageNo Do
  Begin
    N := TW(P);
    P := TL(P + 2 + N * 12);
    If (P <= 0) Or (P >= ImgLen) Then Exit;
  End;
  N := TW(P);
  W := 0; H := 0; Bps := 1; Comp := 1; Photo := 1; Spp := 1; Rps := MaxLongInt; Pred := 1;
  EOff := 0; ECnt := 0; Cmap := 0; NStrip := 0;
  For K := 0 To N - 1 Do
  Begin
    E := P + 2 + K * 12;
    Tag := TW(E);
    Case Tag Of
      256 : W := TVal(E, 0);
      257 : H := TVal(E, 0);
      258 : Bps := TVal(E, 0);
      259 : Comp := TVal(E, 0);
      262 : Photo := TVal(E, 0);
      273 : Begin EOff := E; NStrip := TL(E + 4); End;
      277 : Spp := TVal(E, 0);
      278 : Rps := TVal(E, 0);
      279 : ECnt := E;
      317 : Pred := TVal(E, 0);
      320 : Cmap := E;
    End;
  End;
  If (W <= 0) Or (H <= 0) Or (EOff = 0) Or (NStrip <= 0) Then Exit;
  If (Comp <> 1) And (Comp <> 5) And (Comp <> 32773) Then Exit;
  If (Bps <> 1) And (Bps <> 4) And (Bps <> 8) Then Exit;
  If Rps > H Then Rps := H;
  If Not NewImage(Ix, W, H) Then Exit;
  RowB := (W * Spp * Bps + 7) Div 8;
  Buf := ScAlloc(RowB * Rps + 16);
  If Buf = 0 Then Exit;
  CmN := 1 Shl Bps;
  Y0 := 0;
  For S := 0 To NStrip - 1 Do
  Begin
    If Y0 >= H Then Break;
    Off := TVal(EOff, S);
    If ECnt <> 0 Then Len := TVal(ECnt, S) Else Len := RowB * Rps;
    If (Off < 0) Or (Off + Len > ImgLen) Then Len := MaxI(0, ImgLen - Off);
    Case Comp Of
      5 : Got := TiffLzw(ImgBuf + Off, Len, Buf, RowB * Rps);
      32773 : Got := TiffPack(ImgBuf + Off, Len, Buf, RowB * Rps);
    Else
      Begin
        Got := MinI(Len, RowB * Rps);
        MemCopy(ImgBuf + Off, Buf, Got);
      End;
    End;
    For Row := 0 To Got Div RowB - 1 Do
    Begin
      Y := Y0 + Row;
      If Y >= H Then Break;
      Raw := Buf + Row * RowB;
      { predicteur horizontal (8 bits) }
      If (Pred = 2) And (Bps = 8) Then
        For X := Spp To RowB - 1 Do WrB(Raw + X, RdB(Raw + X) + RdB(Raw + X - Spp));
      For X := 0 To W - 1 Do
      Begin
        If Spp >= 3 Then
        Begin
          R := RdB(Raw + X * Spp); G := RdB(Raw + X * Spp + 1); B := RdB(Raw + X * Spp + 2);
          PutPel(X, Y, (R Shl 16) Or (G Shl 8) Or B);
        End
        Else
        Begin
          If Bps = 8 Then V := RdB(Raw + X)
          Else If Bps = 4 Then V := (RdB(Raw + X Div 2) Shr (4 * (1 - (X And 1)))) And 15
          Else
          Begin
            BitP := X;
            V := (RdB(Raw + BitP Div 8) Shr (7 - (BitP And 7))) And 1;
          End;
          If (Photo = 3) And (Cmap <> 0) Then
          Begin
            R := TVal(Cmap, V) Shr 8; G := TVal(Cmap, CmN + V) Shr 8; B := TVal(Cmap, 2 * CmN + V) Shr 8;
          End
          Else
          Begin
            V := (V * 255) Div (CmN - 1);
            If Photo = 0 Then V := 255 - V;
            R := V; G := V; B := V;
          End;
          PutPel(X, Y, (R Shl 16) Or (G Shl 8) Or B);
        End;
      End;
    End;
    Y0 := Y0 + Rps;
  End;
  DecodeTiff := Not IErr Or (Y0 > 0);
End;

{ decode le fichier (ImgBuf, ImgLen) ; format reconnu par sa signature }
Function DecodeImage(I : LongInt) : Boolean;
Var Ok : Boolean;
Begin
  DecodeImage := False;
  If ImgLen < 8 Then Exit;
  If ScBase = 0 Then ScratchInit;
  If ScBase = 0 Then Exit;
  ScUsed := 0; IErr := False; ArUsed := 0;
  Ok := False;
  FileFmt := '';
  If (IB(0) = $47) And (IB(1) = $49) And (IB(2) = $46) Then Begin FileFmt := 'GIF'; Ok := DecodeGif(I); End
  Else If (IB(0) = $89) And (IB(1) = $50) And (IB(2) = $4E) And (IB(3) = $47) Then
  Begin
    FileFmt := 'PNG'; Ok := DecodePng(I);
  End
  Else If (IB(0) = $FF) And (IB(1) = $D8) Then Begin FileFmt := 'JPEG'; Ok := DecodeJpeg(I); End
  Else If (IB(0) = $42) And (IB(1) = $4D) Then Begin FileFmt := 'BMP'; Ok := DecodeBmp(I); End
  Else If ((IB(0) = $49) And (IB(1) = $49) And (IB(2) = 42)) Or ((IB(0) = $4D) And (IB(1) = $4D) And (IB(3) = 42))
  Then
  Begin
    FileFmt := 'TIFF'; Ok := DecodeTiff(I, Page);
  End;
  DecodeImage := Ok;
End;

{ ==================================================================== }
{ Fichier                                                               }
{ ==================================================================== }

Function ReadWhole(P : String) : Boolean;
Var H, N, Got : LongInt;
Begin
  ReadWhole := False;
  H := CreateFileA(Z(P), GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  N := GetFileSize(H, 0);
  If (N <= 0) Or (N > 64000000) Then Begin Dummy := CloseHandle(H); Exit; End;
  MemRelease(ImgBuf);
  ImgBuf := MemAlloc(N + 16);
  ImgLen := 0;
  If ImgBuf <> 0 Then
  Begin
    Got := 0;
    Dummy := ReadFile(H, ImgBuf, N, LongInt(@Got), 0);
    ImgLen := Got;
  End;
  Dummy := CloseHandle(H);
  FileSize := ImgLen;
  ReadWhole := ImgLen > 0;
End;

{ image decodee (arene) -> DIB de l'image affichee }
Procedure TakePicture;
Var N : LongInt;
Begin
  MemRelease(Pic);
  N := 40 + (((ImW[0] * 3 + 3) Div 4) * 4) * ImH[0];
  Pic := MemAlloc(N);
  If Pic = 0 Then Exit;
  MemCopy(ImBmi[0], Pic, N);
  PicW := ImW[0]; PicH := ImH[0]; PicBytes := N;
End;

Function Stride(W : LongInt) : LongInt;
Begin
  Stride := ((W * 3 + 3) Div 4) * 4;
End;

Procedure Relayout; Forward;
Procedure SetTitle; Forward;

{ charger la page Pg du fichier deja lu }
Function LoadPage(Pg : LongInt) : Boolean;
Begin
  LoadPage := False;
  Page := Pg;
  If Not DecodeImage(0) Then Exit;
  TakePicture;
  LoadPage := Pic <> 0;
End;

Function OpenFile(P : String) : Boolean;
Var Ok : Boolean;
Begin
  Ok := False;
  SetCursor(LoadCursorA(0, IDC_WAIT));
  If ReadWhole(P) Then
  Begin
    Pages := 1;
    If ((IB(0) = $49) And (IB(1) = $49)) Or ((IB(0) = $4D) And (IB(1) = $4D)) Then Pages := MaxI(1, TiffPages);
    If LoadPage(0) Then
    Begin
      FilePath := P;
      Ok := True;
    End;
  End;
  SetCursor(LoadCursorA(0, IDC_ARROW));
  If Not Ok Then
    Dummy := Ask('Impossible d''ouvrir ' + P + #10#10'Formats reconnus : TIFF, BMP, GIF, PNG et JPEG.', 'Imaging',
                 MB_OK Or MB_ICONWARNING)
  Else
  Begin
    FitMode := 1; ScrX := 0; ScrY := 0;
    SetTitle;
    Relayout;
  End;
  OpenFile := Ok;
End;

Function SaveBmp(P : String) : Boolean;
Var H, W, Hd : LongInt; Fh : Array[0..13] Of Byte;
Begin
  SaveBmp := False;
  If Pic = 0 Then Exit;
  H := CreateFileA(Z(P), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  Fh[0] := Ord('B'); Fh[1] := Ord('M');
  Hd := PicBytes + 14;
  Fh[2] := Hd And 255; Fh[3] := (Hd Shr 8) And 255; Fh[4] := (Hd Shr 16) And 255; Fh[5] := (Hd Shr 24) And 255;
  Fh[6] := 0; Fh[7] := 0; Fh[8] := 0; Fh[9] := 0;
  Fh[10] := 54; Fh[11] := 0; Fh[12] := 0; Fh[13] := 0;
  W := 0;
  Dummy := WriteFile(H, LongInt(@Fh), 14, LongInt(@W), 0);
  WrL(Pic + 20, PicBytes - 40);
  Dummy := WriteFile(H, Pic, PicBytes, LongInt(@W), 0);
  Dummy := CloseHandle(H);
  SaveBmp := W = PicBytes;
End;

{ boites Ouvrir / Enregistrer sous (COMDLG32) }
Function GetOpenFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetOpenFileNameA';
Function GetSaveFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetSaveFileNameA';

Var
  FiltBuf : Array[0..255] Of Byte;

Function FileDlg(Save : Boolean; Var P : String) : Boolean;
Var K, N : LongInt; F : String;
Begin
  If Save Then F := 'Bitmap 24 bits (*.bmp)|*.bmp|'
  Else F := 'Toutes les images|*.tif;*.tiff;*.bmp;*.gif;*.png;*.jpg;*.jpeg|Images TIFF (*.tif)|*.tif;*.tiff|' +
            'Bitmap (*.bmp)|*.bmp|GIF (*.gif)|*.gif|PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg;*.jpeg|';
  N := Length(F);
  For K := 1 To N Do If F[K] = '|' Then FiltBuf[K - 1] := 0 Else FiltBuf[K - 1] := Ord(F[K]);
  FiltBuf[N] := 0;
  For K := 0 To 21 Do Ofn[K] := 0;
  If Save Then PutZ(LongInt(@OfnFile), 'IMAGE.BMP') Else OfnFile[0] := 0;
  Ofn[0] := 76; Ofn[1] := Wnd; Ofn[3] := LongInt(@FiltBuf); Ofn[6] := 1;
  Ofn[7] := LongInt(@OfnFile); Ofn[8] := 260;
  If Save Then Ofn[15] := LongInt(Z2('bmp'));
  If Save Then K := GetSaveFileNameA(LongInt(@Ofn)) Else K := GetOpenFileNameA(LongInt(@Ofn));
  P := GetZ(LongInt(@OfnFile));
  FileDlg := (K <> 0) And (P <> '');
End;

{ ==================================================================== }
{ Transformations (nouvelle DIB)                                        }
{ ==================================================================== }

{ Mode : 1 gauche, 2 droite, 3 180 degres, 4 miroir }
Procedure Transform(Mode : LongInt);
Var NW, NH, SS, DS, N, Dst, X, Y, SX, SY, A, B : LongInt;
Begin
  If Pic = 0 Then Exit;
  If Mode <= 2 Then Begin NW := PicH; NH := PicW; End Else Begin NW := PicW; NH := PicH; End;
  SS := Stride(PicW); DS := Stride(NW);
  N := 40 + DS * NH;
  Dst := MemAlloc(N);
  If Dst = 0 Then Exit;
  SetCursor(LoadCursorA(0, IDC_WAIT));
  MemCopy(Pic, Dst, 40);
  WrL(Dst + 4, NW); WrL(Dst + 8, NH);
  { pels de haut en bas : ligne Y du haut = ligne H - 1 - Y de la DIB }
  For Y := 0 To NH - 1 Do
    For X := 0 To NW - 1 Do
    Begin
      Case Mode Of
        1 : Begin SX := PicW - 1 - Y; SY := X; End;
        2 : Begin SX := Y; SY := PicH - 1 - X; End;
        3 : Begin SX := PicW - 1 - X; SY := PicH - 1 - Y; End;
      Else
        Begin SX := PicW - 1 - X; SY := Y; End;
      End;
      A := Pic + 40 + (PicH - 1 - SY) * SS + SX * 3;
      B := Dst + 40 + (NH - 1 - Y) * DS + X * 3;
      WrB(B, RdB(A)); WrB(B + 1, RdB(A + 1)); WrB(B + 2, RdB(A + 2));
    End;
  MemRelease(Pic);
  Pic := Dst; PicW := NW; PicH := NH; PicBytes := N;
  SetCursor(LoadCursorA(0, IDC_ARROW));
  Relayout;
End;

{ ==================================================================== }
{ Affichage                                                             }
{ ==================================================================== }

Function ViewTop : LongInt;
Begin
  If ShowTb Then ViewTop := TbH Else ViewTop := 0;
End;

Function ViewW : LongInt;
Begin
  ViewW := MaxI(16, CW - SbW);
End;

Function ViewH : LongInt;
Begin
  ViewH := MaxI(16, CH - ViewTop - SbW - Ord(ShowSt) * StH);
End;

Function ShownW : LongInt;
Begin
  ShownW := MaxI(1, (PicW * Zoom) Div 100);
End;

Function ShownH : LongInt;
Begin
  ShownH := MaxI(1, (PicH * Zoom) Div 100);
End;

Procedure Relayout;
Var M : LongInt;
Begin
  If Pic <> 0 Then
  Begin
    If FitMode = 1 Then
    Begin
      Zoom := MinI((ViewW * 100) Div PicW, (ViewH * 100) Div PicH);
      If Zoom > 100 Then Zoom := 100;
    End
    Else If FitMode = 2 Then Zoom := (ViewW * 100) Div PicW;
    If Zoom < 2 Then Zoom := 2;
    If Zoom > 800 Then Zoom := 800;
  End;
  If HSb <> 0 Then
  Begin
    Dummy := MoveWindow(HSb, 0, ViewTop + ViewH, ViewW, SbW, 1);
    Dummy := MoveWindow(VSb, ViewW, ViewTop, SbW, ViewH, 1);
    M := MaxI(0, ShownW - ViewW);
    If ScrX > M Then ScrX := M;
    If ScrX < 0 Then ScrX := 0;
    Dummy := SetScrollRange(HSb, 2, 0, MaxI(0, M Div 8), 0);
    Dummy := SetScrollPos(HSb, 2, ScrX Div 8, 1);
    M := MaxI(0, ShownH - ViewH);
    If ScrY > M Then ScrY := M;
    If ScrY < 0 Then ScrY := 0;
    Dummy := SetScrollRange(VSb, 2, 0, MaxI(0, M Div 8), 0);
    Dummy := SetScrollPos(VSb, 2, ScrY Div 8, 1);
  End;
  Dummy := InvalidateRect(Wnd, 0, 0);
End;

Function ToolText(I : LongInt) : String;
Begin
  Case I Of
    0 : ToolText := 'Ouvrir';
    1 : ToolText := 'Zoom +';
    2 : ToolText := 'Zoom -';
    3 : ToolText := 'Ajuster';
    4 : ToolText := '100 %';
    5 : ToolText := 'Pivoter G';
    6 : ToolText := 'Pivoter D';
    7 : ToolText := '< Page';
  Else
    ToolText := 'Page >';
  End;
End;

Procedure ToolRect(I : LongInt; Var X1, X2 : LongInt);
Var K : LongInt;
Begin
  X1 := 4;
  For K := 0 To I - 1 Do X1 := X1 + Length(ToolText(K)) * 8 + 14 + 4 * Ord((K = 0) Or (K = 4) Or (K = 6));
  X2 := X1 + Length(ToolText(I)) * 8 + 12;
End;

Function ToolOn(I : LongInt) : Boolean;
Begin
  If I = 0 Then ToolOn := True
  Else If (I = 7) Then ToolOn := (Pic <> 0) And (Page > 0)
  Else If (I = 8) Then ToolOn := (Pic <> 0) And (Page < Pages - 1)
  Else ToolOn := Pic <> 0;
End;

Procedure DrawAll(Dc : LongInt);
Var I, X1, X2, Y, VW, VH, DW, DH, OX, OY, C : LongInt; S : String;
Begin
  VW := ViewW; VH := ViewH;
  If ShowTb Then
  Begin
    Bar(Dc, 0, 0, CW, TbH, ClrFace);
    Bar(Dc, 0, TbH - 1, CW, TbH, ClrShadow);
    For I := 0 To NTool - 1 Do
    Begin
      ToolRect(I, X1, X2);
      If X2 > CW Then Break;
      Bar(Dc, X1, 3, X2, TbH - 4, ClrFace);
      Bevel(Dc, X1, 3, X2, TbH - 4, BtnDown <> I);
      If ToolOn(I) Then C := ClrDark Else C := ClrShadow;
      Txt(Dc, X1 + 6 + Ord(BtnDown = I), 6 + Ord(BtnDown = I), ToolText(I), C, ClrFace);
    End;
  End;
  { zone de l'image : fond gris fonce, image centree ou defilee }
  Y := ViewTop;
  If Pic = 0 Then
  Begin
    Bar(Dc, 0, Y, VW, Y + VH, ClrShadow);
    Txt(Dc, 16, Y + 16, 'Fichier, Ouvrir : une image TIFF, BMP, GIF, PNG ou JPEG.', ClrHi, ClrShadow);
  End
  Else
  Begin
    DW := ShownW; DH := ShownH;
    If DW < VW Then OX := (VW - DW) Div 2 Else OX := -ScrX;
    If DH < VH Then OY := (VH - DH) Div 2 Else OY := -ScrY;
    Bar(Dc, 0, Y, VW, Y + MaxI(0, OY), ClrShadow);
    Bar(Dc, 0, Y + OY + DH, VW, Y + VH, ClrShadow);
    Bar(Dc, 0, Y, MaxI(0, OX), Y + VH, ClrShadow);
    Bar(Dc, OX + DW, Y, VW, Y + VH, ClrShadow);
    Dummy := StretchDIBits(Dc, OX, Y + OY, DW, DH, 0, 0, PicW, PicH, Pic + 40, Pic, 0, SRCCOPY);
  End;
  { coin des barres de defilement }
  Bar(Dc, VW, Y + VH, CW, Y + VH + SbW, ClrFace);
  If ShowSt Then
  Begin
    Y := CH - StH;
    Bar(Dc, 0, Y, CW, CH, ClrFace);
    Bar(Dc, 0, Y, CW, Y + 1, ClrHi);
    Bevel(Dc, 2, Y + 3, CW Div 2, CH - 2, False);
    Bevel(Dc, CW Div 2 + 2, Y + 3, CW - 2, CH - 2, False);
    If Pic <> 0 Then
    Begin
      S := 'Page ' + IStr(Page + 1) + ' sur ' + IStr(Pages) + '    Zoom ' + IStr(Zoom) + ' %';
      Txt(Dc, 6, Y + 4, S, ClrDark, ClrFace);
      S := IStr(PicW) + ' x ' + IStr(PicH) + ' pixels, ' + FileFmt;
      Txt(Dc, CW Div 2 + 6, Y + 4, S, ClrDark, ClrFace);
    End
    Else Txt(Dc, 6, Y + 4, 'Pr'#234't', ClrDark, ClrFace);
  End;
End;

Procedure Paint0;
Var Dc : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

Procedure SetTitle;
Var S : String; K : LongInt;
Begin
  If FilePath = '' Then S := 'Imaging'
  Else
  Begin
    K := Length(FilePath);
    While (K > 0) And (FilePath[K] <> '\') Do Dec(K);
    S := 'Imaging - ' + Copy(FilePath, K + 1, 255);
  End;
  SetText(Wnd, S);
End;

Procedure SetZoom(Z0 : LongInt);
Begin
  If Pic = 0 Then Exit;
  FitMode := 0;
  Zoom := MaxI(2, MinI(800, Z0));
  Relayout;
End;

Procedure SetMarks;
Begin
  MCheck(MView, CM_TOOLBAR, ShowTb);
  MCheck(MView, CM_STATUS, ShowSt);
  MCheck(MZoom, CM_FIT, FitMode = 1);
  MCheck(MZoom, CM_FITW, FitMode = 2);
  MCheck(MZoom, CM_ACTUAL, (FitMode = 0) And (Zoom = 100));
End;

Procedure Command(Id : LongInt);
Var P : String;
Begin
  Case Id Of
    CM_OPEN : If FileDlg(False, P) Then Dummy := Ord(OpenFile(P));
    CM_SAVEAS :
      If Pic <> 0 Then
        If FileDlg(True, P) Then
          If Not SaveBmp(P) Then Dummy := Ask('Impossible d''enregistrer ' + P + '.', 'Imaging', MB_OK Or MB_ICONWARNING);
    CM_PROPS :
      If Pic <> 0 Then
        Dummy := Ask('Fichier : ' + FilePath + #10 + 'Format : ' + FileFmt + #10 + 'Taille : ' + IStr(FileSize) +
                     ' octets' + #10 + 'Dimensions : ' + IStr(PicW) + ' x ' + IStr(PicH) + ' pixels' + #10 +
                     'Pages : ' + IStr(Pages), 'Propri'#233't'#233's de l''image', MB_OK Or MB_ICONINFO);
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_ZIN : SetZoom((Zoom * 3) Div 2);
    CM_ZOUT : SetZoom((Zoom * 2) Div 3);
    CM_FIT : Begin FitMode := 1; Relayout; End;
    CM_FITW : Begin FitMode := 2; Relayout; End;
    CM_ACTUAL : SetZoom(100);
    CM_Z25 : SetZoom(25);
    CM_Z50 : SetZoom(50);
    CM_Z200 : SetZoom(200);
    CM_Z400 : SetZoom(400);
    CM_ROTL : Transform(1);
    CM_ROTR : Transform(2);
    CM_ROT180 : Transform(3);
    CM_FLIP : Transform(4);
    CM_PFIRST, CM_PPREV, CM_PNEXT, CM_PLAST :
      If (Pic <> 0) And (Pages > 1) Then
      Begin
        Case Id Of
          CM_PFIRST : Page := 0;
          CM_PPREV : Page := MaxI(0, Page - 1);
          CM_PNEXT : Page := MinI(Pages - 1, Page + 1);
        Else
          Page := Pages - 1;
        End;
        Dummy := Ord(LoadPage(Page));
        Relayout;
      End;
    CM_TOOLBAR : Begin ShowTb := Not ShowTb; Relayout; End;
    CM_STATUS : Begin ShowSt := Not ShowSt; Relayout; End;
    CM_ABOUT : Dummy := Ask('Imaging pour Pasdows 95'#10#10'Afficher, agrandir, faire pivoter et enregistrer des ' +
                            'images TIFF, BMP, GIF, PNG et JPEG. Programme '#233'crit en Pascal et compil'#233' par WPC.',
                            #192' propos d''Imaging', MB_OK Or MB_ICONINFO);
  End;
  SetMarks;
End;

Function ToolCmd(I : LongInt) : LongInt;
Begin
  Case I Of
    0 : ToolCmd := CM_OPEN;
    1 : ToolCmd := CM_ZIN;
    2 : ToolCmd := CM_ZOUT;
    3 : ToolCmd := CM_FIT;
    4 : ToolCmd := CM_ACTUAL;
    5 : ToolCmd := CM_ROTL;
    6 : ToolCmd := CM_ROTR;
    7 : ToolCmd := CM_PPREV;
  Else
    ToolCmd := CM_PNEXT;
  End;
End;

Function HitTool(X, Y : LongInt) : LongInt;
Var I, X1, X2 : LongInt;
Begin
  HitTool := -1;
  If Not ShowTb Or (Y < 3) Or (Y >= TbH - 4) Then Exit;
  For I := 0 To NTool - 1 Do
  Begin
    ToolRect(I, X1, X2);
    If (X >= X1) And (X < X2) Then HitTool := I;
  End;
End;

Procedure Scroll(Bar0, Code, Pos0 : LongInt);
Var Step, Pg : LongInt;
Begin
  Step := 32;
  If Bar0 = 0 Then Pg := ViewW - 32 Else Pg := ViewH - 32;
  If Bar0 = 0 Then
    Case Code Of
      SB_LINEUP : ScrX := ScrX - Step;
      SB_LINEDOWN : ScrX := ScrX + Step;
      SB_PAGEUP : ScrX := ScrX - Pg;
      SB_PAGEDOWN : ScrX := ScrX + Pg;
      SB_THUMBPOSITION, SB_THUMBTRACK : ScrX := Pos0 * 8;
    End
  Else
    Case Code Of
      SB_LINEUP : ScrY := ScrY - Step;
      SB_LINEDOWN : ScrY := ScrY + Step;
      SB_PAGEUP : ScrY := ScrY - Pg;
      SB_PAGEDOWN : ScrY := ScrY + Pg;
      SB_THUMBPOSITION, SB_THUMBTRACK : ScrY := Pos0 * 8;
    End;
  Relayout;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, I : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then
        Begin
          CW := MinI(Rc[2], 2048); CH := MinI(Rc[3], 1536);
          Relayout;
        End;
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_HSCROLL : Scroll(0, WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_VSCROLL : Scroll(1, WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_LBUTTONDOWN :
      Begin
        Dummy := SetFocus(H);
        I := HitTool(S16(LP), S16(LP Shr 16));
        If (I >= 0) And ToolOn(I) Then Begin BtnDown := I; Dummy := SetCapture(H); Paint0; End;
      End;
    WM_LBUTTONUP :
      If BtnDown >= 0 Then
      Begin
        I := BtnDown; BtnDown := -1;
        Dummy := ReleaseCapture;
        Paint0;
        If HitTool(S16(LP), S16(LP Shr 16)) = I Then Command(ToolCmd(I));
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_LEFT : Scroll(0, SB_LINEUP, 0);
        VK_RIGHT : Scroll(0, SB_LINEDOWN, 0);
        VK_UP : Scroll(1, SB_LINEUP, 0);
        VK_DOWN : Scroll(1, SB_LINEDOWN, 0);
        VK_PRIOR : Command(CM_PPREV);
        VK_NEXT : Command(CM_PNEXT);
        VK_HOME : Command(CM_PFIRST);
        VK_END : Command(CM_PLAST);
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_CHAR :
      Case Chr(WP And 255) Of
        '+', '=' : Command(CM_ZIN);
        '-' : Command(CM_ZOUT);
        #15 : Command(CM_OPEN);
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND : If LP = 0 Then Command(WP And $FFFF);
    WM_CLOSE : Dummy := DestroyWindow(H);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  Dc, MFile, MImg, MPage, MHelp, K : LongInt;
  Rc0 : Array[0..3] Of LongInt;
  S : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Pic := 0; ImgBuf := 0; ImgLen := 0; PageBg := $808080; NImgs := 1; ScBase := 0;
  FilePath := ''; Page := 0; Pages := 0; Zoom := 100; FitMode := 1; ShowTb := True; ShowSt := True; BtnDown := -1;
  { arene des decodeurs : 32 Mo, ou moins si la memoire manque }
  ArSize := 33554432; ArBase := 0;
  While (ArBase = 0) And (ArSize >= 2097152) Do
  Begin
    ArBase := MemAlloc(ArSize);
    If ArBase = 0 Then ArSize := ArSize Div 2;
  End;
  CW := 620; CH := 420;
  RegClass('ImagingWnd', LongInt(@MainProc), CS_DBLCLKS);
  Wnd := MainWindow('ImagingWnd', 'Imaging', WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, CW,
                    MinI(CH, GetSystemMetrics(SM_CYSCREEN) - 90), True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MView := CreatePopupMenu; MZoom := CreatePopupMenu; MImg := CreatePopupMenu;
  MPage := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MFile, CM_OPEN, '~Ouvrir...'#9'Ctrl+O');
  MItem(MFile, CM_SAVEAS, 'Enregistrer ~sous...');
  MItem(MFile, 0, '');
  MItem(MFile, CM_PROPS, 'Propri'#233't'#233's de l''~image...');
  MItem(MFile, 0, '');
  MItem(MFile, CM_QUIT, '~Quitter');
  MItem(MView, CM_TOOLBAR, '~Barre d''outils');
  MItem(MView, CM_STATUS, 'Barre d'''#233'~tat');
  MItem(MZoom, CM_ZIN, 'Zoom ~avant'#9'+');
  MItem(MZoom, CM_ZOUT, 'Zoom a~rri'#232're'#9'-');
  MItem(MZoom, 0, '');
  MItem(MZoom, CM_FIT, 'Ajuster '#224' la ~fen'#234'tre');
  MItem(MZoom, CM_FITW, 'Ajuster '#224' la ~largeur');
  MItem(MZoom, CM_ACTUAL, '~Taille r'#233'elle (100 %)');
  MItem(MZoom, 0, '');
  MItem(MZoom, CM_Z25, '25 %');
  MItem(MZoom, CM_Z50, '50 %');
  MItem(MZoom, CM_Z200, '200 %');
  MItem(MZoom, CM_Z400, '400 %');
  MItem(MImg, CM_ROTL, 'Faire pivoter '#224' ~gauche');
  MItem(MImg, CM_ROTR, 'Faire pivoter '#224' ~droite');
  MItem(MImg, CM_ROT180, 'Faire pivoter de ~180'#176);
  MItem(MImg, CM_FLIP, '~Retourner (miroir)');
  MItem(MPage, CM_PFIRST, '~Premi'#232're page'#9'Origine');
  MItem(MPage, CM_PPREV, 'Page pr'#233'~c'#233'dente'#9'Pg pr'#233'c');
  MItem(MPage, CM_PNEXT, 'Page ~suivante'#9'Pg suiv');
  MItem(MPage, CM_PLAST, '~Derni'#232're page'#9'Fin');
  MItem(MHelp, CM_ABOUT, #192' ~propos d''Imaging');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MView, '~Affichage');
  MSub(MenuBar, MZoom, '~Zoom');
  MSub(MenuBar, MImg, '~Image');
  MSub(MenuBar, MPage, '~Page');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  HSb := Ctl(Wnd, 'SCROLLBAR', '', SBS_HORZ, 0, 0, 100, SbW, 10);
  VSb := Ctl(Wnd, 'SCROLLBAR', '', SBS_VERT, 0, 0, SbW, 100, 11);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  Relayout;
  Dc := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, 2048, 1536);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  SetMarks;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  S := '';
  For K := 1 To ParamCount Do
  Begin
    If S <> '' Then S := S + ' ';
    S := S + ParamStr(K);
  End;
  If (S <> '') And (S[1] = '"') Then S := Copy(S, 2, Length(S) - 2);
  If S <> '' Then Dummy := Ord(OpenFile(S));
  MsgLoop;
  ExitProcess(0);
END.
