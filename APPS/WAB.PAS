{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: WAB - Carnet d'adresses de Pasdows 95 (Win32), comme celui
                des Accessoires de Windows 95.
}

Program WAB;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\WAB.PAS WAB.EXE

  Comme le Carnet d'adresses de Windows :
  - liste des contacts (Nom, Adresse de messagerie, Telephone au bureau,
    Telephone au domicile), triee par nom, prenom ou adresse ; la zone
    "Tapez le nom..." choisit le premier contact qui commence ainsi ;
  - Nouveau contact, Proprietes (double clic ou Entree), Supprimer :
    fiche avec prenom, nom, adresse de messagerie, telephones, adresse,
    ville, code postal, pays, societe, fonction et remarques ;
  - Fichier, Importer et Exporter : fichier texte CSV (separateur
    virgule, entete, guillemets), comme l'Assistant Exportation de
    Windows ; Edition, Copier : la fiche en texte dans le presse-papiers ;
  - le carnet est garde dans CARNET.WAB (texte, un contact par ligne,
    champs separes par des tabulations) dans le dossier du programme. }

Const
  NFld = 13;
  MaxCon = 2000;
  CM_NEW = 101; CM_PROPS = 102; CM_DELETE = 103; CM_IMPORT = 104; CM_EXPORT = 105; CM_QUIT = 106;
  CM_COPY = 201; CM_FIND = 202;
  CM_SORTNAME = 301; CM_SORTFIRST = 302; CM_SORTMAIL = 303;
  CM_ABOUT = 401;
  ID_SEARCH = 10; ID_OK = 1; ID_CANCEL = 2; ID_FLD0 = 30;
  TbH = 34; RowH = 18; HdrH = 20; StH = 22; SbW = 16;
  ListY = 92;

Type
  TContact = Array[0..NFld - 1] Of String[79];
  PContact = ^TContact;

Var
  Con : Array[0..MaxCon - 1] Of PContact;
  NCon, Sel, Top, SortBy, BtnDown : LongInt;
  CW, CH, MemDC, MemBmp, FontS, SrchW, VSb, MenuBar, MView : LongInt;
  DlgW, DlgIdx : LongInt;
  DlgEd : Array[0..NFld - 1] Of LongInt;
  DataPath : String;
  Dirty : Boolean;
  Ofn : Array[0..21] Of LongInt;
  OfnFile : Array[0..259] Of Byte;
  FiltBuf : Array[0..255] Of Byte;
  LineBuf : Array[0..4095] Of Byte;
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

Function GetOpenFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetOpenFileNameA';
Function GetSaveFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetSaveFileNameA';

Function FldName(F : LongInt) : String;
Begin
  Case F Of
    0 : FldName := 'Pr'#233'nom';
    1 : FldName := 'Nom';
    2 : FldName := 'Adresse de messagerie';
    3 : FldName := 'T'#233'l'#233'phone (domicile)';
    4 : FldName := 'T'#233'l'#233'phone (bureau)';
    5 : FldName := 'T'#233'l'#233'phone mobile';
    6 : FldName := 'Adresse';
    7 : FldName := 'Ville';
    8 : FldName := 'Code postal';
    9 : FldName := 'Pays';
    10 : FldName := 'Soci'#233't'#233;
    11 : FldName := 'Fonction';
  Else
    FldName := 'Remarques';
  End;
End;

Function FullName(I : LongInt) : String;
Var S : String;
Begin
  S := TrimS(Con[I]^[0] + ' ' + Con[I]^[1]);
  If S = '' Then S := Con[I]^[2];
  If S = '' Then S := '(sans nom)';
  FullName := S;
End;

Function SortKey(I : LongInt) : String;
Begin
  Case SortBy Of
    1 : SortKey := UpS(Con[I]^[0] + ' ' + Con[I]^[1]);
    2 : SortKey := UpS(Con[I]^[2]);
  Else
    SortKey := UpS(Con[I]^[1] + ' ' + Con[I]^[0]);
  End;
End;

Procedure SortList;
Var I, J : LongInt; P : PContact; K : String;
Begin
  For I := 1 To NCon - 1 Do
  Begin
    P := Con[I]; K := SortKey(I);
    J := I - 1;
    While (J >= 0) And (SortKey(J) > K) Do
    Begin
      Con[J + 1] := Con[J];
      Dec(J);
    End;
    Con[J + 1] := P;
  End;
End;

Function NewContact : LongInt;
Var P : PContact; F : LongInt;
Begin
  NewContact := -1;
  If NCon >= MaxCon Then Exit;
  GetMem(P, SizeOf(TContact));
  For F := 0 To NFld - 1 Do P^[F] := '';
  Con[NCon] := P;
  NewContact := NCon;
  Inc(NCon);
End;

{ ==================================================================== }
{ Fichiers : CARNET.WAB (tabulations), CSV                              }
{ ==================================================================== }

Var
  WrH : LongInt;

Procedure WStr(S : String);
Var W : LongInt;
Begin
  If S <> '' Then Dummy := WriteFile(WrH, LongInt(@S[1]), Length(S), LongInt(@W), 0);
End;

{ lignes d'un fichier : Proc(ligne) ; Kind 0 carnet, 1 CSV }
Var
  RdH, RdPos, RdLen : LongInt;
  RdBuf : Array[0..8191] Of Byte;

Function ReadLine(Var S : String) : Boolean;
Var C : LongInt;
Begin
  ReadLine := False;
  S := '';
  Repeat
    If RdPos >= RdLen Then
    Begin
      RdLen := 0; RdPos := 0;
      Dummy := ReadFile(RdH, LongInt(@RdBuf), SizeOf(RdBuf), LongInt(@RdLen), 0);
      If RdLen <= 0 Then
      Begin
        ReadLine := S <> '';
        Exit;
      End;
    End;
    C := RdBuf[RdPos]; Inc(RdPos);
    If C = 10 Then
    Begin
      ReadLine := True;
      Exit;
    End;
    If (C <> 13) And (Length(S) < 255) Then S := S + Chr(C);
  Until False;
End;

Function OpenRd(P : String) : Boolean;
Begin
  RdH := CreateFileA(Z(P), GENERIC_READ, FILE_SHARE_READ, 0, OPEN_EXISTING, 0, 0);
  RdPos := 0; RdLen := 0;
  OpenRd := RdH <> INVALID_HANDLE;
End;

Procedure LoadBook;
Var S : String; I, F, P : LongInt;
Begin
  NCon := 0;
  If Not OpenRd(DataPath) Then Exit;
  While ReadLine(S) Do
  Begin
    If (S = '') Or (Copy(S, 1, 7) = 'PASDOWS') Then Continue;
    I := NewContact;
    If I < 0 Then Break;
    F := 0;
    S := S + #9;
    While (S <> '') And (F < NFld) Do
    Begin
      P := Pos(#9, S);
      Con[I]^[F] := Copy(S, 1, MinI(P - 1, 79));
      Delete(S, 1, P);
      Inc(F);
    End;
  End;
  Dummy := CloseHandle(RdH);
  SortList;
End;

Procedure SaveBook;
Var I, F : LongInt;
Begin
  WrH := CreateFileA(Z(DataPath), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If WrH = INVALID_HANDLE Then Exit;
  WStr('PASDOWS-WAB 1'#13#10);
  For I := 0 To NCon - 1 Do
  Begin
    For F := 0 To NFld - 1 Do
    Begin
      If F > 0 Then WStr(#9);
      WStr(Con[I]^[F]);
    End;
    WStr(#13#10);
  End;
  Dummy := CloseHandle(WrH);
  Dirty := False;
End;

Function CsvField(S : String) : String;
Var K : LongInt; R : String;
Begin
  If (Pos(',', S) = 0) And (Pos('"', S) = 0) Then
  Begin
    CsvField := S;
    Exit;
  End;
  R := '"';
  For K := 1 To Length(S) Do
    If S[K] = '"' Then R := R + '""' Else R := R + S[K];
  CsvField := R + '"';
End;

Function ExportCsv(P : String) : Boolean;
Var I, F : LongInt;
Begin
  ExportCsv := False;
  WrH := CreateFileA(Z(P), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If WrH = INVALID_HANDLE Then Exit;
  For F := 0 To NFld - 1 Do
  Begin
    If F > 0 Then WStr(',');
    WStr(CsvField(FldName(F)));
  End;
  WStr(#13#10);
  For I := 0 To NCon - 1 Do
  Begin
    For F := 0 To NFld - 1 Do
    Begin
      If F > 0 Then WStr(',');
      WStr(CsvField(Con[I]^[F]));
    End;
    WStr(#13#10);
  End;
  Dummy := CloseHandle(WrH);
  ExportCsv := True;
End;

{ ligne CSV -> champs (dans l'ordre de l'entete Map) }
Function ImportCsv(P : String) : LongInt;
Var S, V : String; K, F, I, N, Sep : LongInt; Q : Boolean; Map : Array[0..31] Of LongInt; Hdr : Boolean;
Begin
  ImportCsv := 0;
  If Not OpenRd(P) Then Exit;
  N := 0; Hdr := True;
  For K := 0 To 31 Do Map[K] := -1;
  While ReadLine(S) Do
  Begin
    If S = '' Then Continue;
    { separateur : virgule, ou point-virgule (Excel en francais) }
    If (Pos(';', S) > 0) And (Pos(',', S) = 0) Then Sep := Ord(';') Else Sep := Ord(',');
    If Hdr Then I := -1 Else I := NewContact;
    If (Not Hdr) And (I < 0) Then Break;
    F := 0; V := ''; Q := False; K := 1;
    While K <= Length(S) + 1 Do
    Begin
      If (K <= Length(S)) And Q Then
      Begin
        If S[K] = '"' Then
        Begin
          If (K < Length(S)) And (S[K + 1] = '"') Then Begin V := V + '"'; Inc(K); End
          Else Q := False;
        End
        Else V := V + S[K];
      End
      Else If (K <= Length(S)) And (S[K] = '"') Then Q := True
      Else If (K > Length(S)) Or (Ord(S[K]) = Sep) Then
      Begin
        If F <= 31 Then
        Begin
          If Hdr Then
          Begin
            V := UpS(TrimS(V));
            For I := 0 To NFld - 1 Do
              If UpS(FldName(I)) = V Then Map[F] := I;
            If (V = 'E-MAIL') Or (V = 'COURRIEL') Or (V = 'ADRESSE E-MAIL') Then Map[F] := 2;
            If (V = 'FIRST NAME') Then Map[F] := 0;
            If (V = 'LAST NAME') Then Map[F] := 1;
          End
          Else If Map[F] >= 0 Then Con[I]^[Map[F]] := Copy(TrimS(V), 1, 79);
        End;
        Inc(F); V := '';
      End
      Else V := V + S[K];
      Inc(K);
    End;
    If Hdr Then
    Begin
      Hdr := False;
      { sans entete reconnue : l'ordre du carnet }
      F := 0;
      For K := 0 To 31 Do If Map[K] >= 0 Then Inc(F);
      If F = 0 Then For K := 0 To NFld - 1 Do Map[K] := K;
    End
    Else Inc(N);
  End;
  Dummy := CloseHandle(RdH);
  SortList;
  Dirty := True;
  ImportCsv := N;
End;

Function FileDlg(Save : Boolean; Var P : String) : Boolean;
Var K, N : LongInt; F : String;
Begin
  F := 'Fichier texte CSV (*.csv)|*.csv|Tous les fichiers (*.*)|*.*|';
  N := Length(F);
  For K := 1 To N Do If F[K] = '|' Then FiltBuf[K - 1] := 0 Else FiltBuf[K - 1] := Ord(F[K]);
  FiltBuf[N] := 0;
  For K := 0 To 21 Do Ofn[K] := 0;
  If Save Then PutZ(LongInt(@OfnFile), 'CARNET.CSV') Else OfnFile[0] := 0;
  Ofn[0] := 76; Ofn[1] := Wnd; Ofn[3] := LongInt(@FiltBuf); Ofn[6] := 1;
  Ofn[7] := LongInt(@OfnFile); Ofn[8] := 260;
  If Save Then Ofn[15] := LongInt(Z2('csv'));
  If Save Then K := GetSaveFileNameA(LongInt(@Ofn)) Else K := GetOpenFileNameA(LongInt(@Ofn));
  P := GetZ(LongInt(@OfnFile));
  FileDlg := (K <> 0) And (P <> '');
End;

{ ==================================================================== }
{ Liste                                                                 }
{ ==================================================================== }

Function NRows : LongInt;
Begin
  NRows := MaxI(1, (CH - StH - ListY - HdrH - 2) Div RowH);
End;

Procedure ColX(K : LongInt; Var X : LongInt);
Var W : LongInt;
Begin
  W := CW - SbW - 8;
  Case K Of
    0 : X := 6;
    1 : X := 6 + (W * 27) Div 100;
    2 : X := 6 + (W * 62) Div 100;
  Else
    X := 6 + (W * 81) Div 100;
  End;
End;

Procedure Clip(Dc, X, Y, W : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If Length(S) * 8 > W - 4 Then S := Copy(S, 1, MaxI(0, (W - 4) Div 8 - 1)) + #187;
  Txt(Dc, X, Y, S, Fg, Bg);
End;

Function ToolText(I : LongInt) : String;
Begin
  Case I Of
    0 : ToolText := 'Nouveau contact';
    1 : ToolText := 'Propri'#233't'#233's';
    2 : ToolText := 'Supprimer';
  Else
    ToolText := 'Rechercher';
  End;
End;

Procedure ToolRect(I : LongInt; Var X1, X2 : LongInt);
Var K : LongInt;
Begin
  X1 := 4;
  For K := 0 To I - 1 Do X1 := X1 + Length(ToolText(K)) * 8 + 20;
  X2 := X1 + Length(ToolText(I)) * 8 + 16;
End;

Function ToolOn(I : LongInt) : Boolean;
Begin
  ToolOn := (I = 0) Or (I = 3) Or ((Sel >= 0) And (Sel < NCon));
End;

Procedure DrawAll(Dc : LongInt);
Var I, R, Y, X0, X1, X2, X3, Fg, Bg, C : LongInt; S : String;
Begin
  Bar(Dc, 0, 0, CW, CH, ClrFace);
  { barre d'outils }
  For I := 0 To 3 Do
  Begin
    ToolRect(I, X1, X2);
    Bevel(Dc, X1, 4, X2, TbH - 4, BtnDown <> I);
    If ToolOn(I) Then C := ClrDark Else C := ClrShadow;
    Txt(Dc, X1 + 8 + Ord(BtnDown = I), 10 + Ord(BtnDown = I), ToolText(I), C, ClrFace);
  End;
  Bar(Dc, 0, TbH, CW, TbH + 1, ClrShadow);
  Bar(Dc, 0, TbH + 1, CW, TbH + 2, ClrHi);
  Txt(Dc, 6, TbH + 8, 'Tapez le nom ou s'#233'lectionnez-le dans la liste :', ClrDark, ClrFace);
  { liste : en-tete des colonnes, lignes }
  ColX(0, X0); ColX(1, X1); ColX(2, X2); ColX(3, X3);
  Y := ListY;
  Bar(Dc, 2, Y, CW - SbW - 2, Y + HdrH, ClrFace);
  For I := 0 To 3 Do
  Begin
    ColX(I, R);
    If I < 3 Then ColX(I + 1, C) Else C := CW - SbW - 2;
    Bevel(Dc, R - 4, Y, C - 4 + Ord(I = 3) * 4, Y + HdrH, True);
    Case I Of
      0 : S := 'Nom';
      1 : S := 'Adresse de messagerie';
      2 : S := 'T'#233'l. bureau';
    Else S := 'T'#233'l. domicile';
    End;
    Clip(Dc, R, Y + 2, C - R - 4, S, ClrDark, ClrFace);
  End;
  Bar(Dc, 2, Y + HdrH, CW - SbW - 2, CH - StH - 2, ClrWin);
  For R := 0 To NRows - 1 Do
  Begin
    I := Top + R;
    If I >= NCon Then Break;
    Y := ListY + HdrH + 1 + R * RowH;
    If I = Sel Then Begin Bg := ClrSel; Fg := ClrHi; End Else Begin Bg := ClrWin; Fg := ClrDark; End;
    Bar(Dc, 2, Y, CW - SbW - 2, Y + RowH, Bg);
    Clip(Dc, X0, Y + 1, X1 - X0, FullName(I), Fg, Bg);
    Clip(Dc, X1, Y + 1, X2 - X1, Con[I]^[2], Fg, Bg);
    Clip(Dc, X2, Y + 1, X3 - X2, Con[I]^[4], Fg, Bg);
    Clip(Dc, X3, Y + 1, CW - SbW - X3 - 4, Con[I]^[3], Fg, Bg);
  End;
  Bevel(Dc, 1, ListY - 1, CW - SbW - 1, CH - StH - 1, False);
  { barre d'etat }
  Y := CH - StH;
  Bevel(Dc, 2, Y + 2, CW - 2, CH - 1, False);
  If NCon = 1 Then S := '1 contact' Else S := IStr(NCon) + ' contacts';
  Txt(Dc, 6, Y + 4, S, ClrDark, ClrFace);
End;

Procedure Paint0;
Var Dc : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  { pas la place des controles (zone de recherche, barre de defilement) }
  Dummy := BitBlt(Dc, 0, 0, CW, TbH + 30, MemDC, 0, 0, SRCCOPY);
  Dummy := BitBlt(Dc, 0, ListY - 2, CW - SbW - 1, CH - ListY + 2, MemDC, 0, ListY - 2, SRCCOPY);
  Dummy := BitBlt(Dc, 0, CH - StH, CW, StH, MemDC, 0, CH - StH, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

Procedure Ensure;
Begin
  If Sel >= NCon Then Sel := NCon - 1;
  If (Sel >= 0) And (Sel < Top) Then Top := Sel;
  If Sel >= Top + NRows Then Top := Sel - NRows + 1;
  If Top > MaxI(0, NCon - NRows) Then Top := MaxI(0, NCon - NRows);
  If Top < 0 Then Top := 0;
  Dummy := SetScrollRange(VSb, 2, 0, MaxI(0, NCon - NRows), 0);
  Dummy := SetScrollPos(VSb, 2, Top, 1);
End;

Procedure Refresh;
Begin
  Ensure;
  Paint0;
End;

{ ==================================================================== }
{ Fiche du contact                                                      }
{ ==================================================================== }

Procedure DlgClose(Ok : Boolean);
Var F, I : LongInt; P : PContact;
Begin
  If DlgW = 0 Then Exit;
  If Ok Then
  Begin
    I := DlgIdx;
    If I < 0 Then I := NewContact;
    If I >= 0 Then
    Begin
      For F := 0 To NFld - 1 Do Con[I]^[F] := Copy(CtlText(DlgEd[F]), 1, 79);
      P := Con[I];
      SortList;
      For F := 0 To NCon - 1 Do If Con[F] = P Then Sel := F;
      Dirty := True;
      SaveBook;
    End;
  End;
  Dummy := EnableWindow(Wnd, 1);
  Dummy := DestroyWindow(DlgW);
  DlgW := 0;
  Dummy := SetFocus(Wnd);
  Refresh;
End;

Function CardLbl(F : LongInt) : String;
Begin
  Case F Of
    2 : CardLbl := 'Messagerie';
    3 : CardLbl := 'T'#233'l. domicile';
    4 : CardLbl := 'T'#233'l. bureau';
    5 : CardLbl := 'T'#233'l. mobile';
  Else
    CardLbl := FldName(F);
  End;
End;

{ place de chaque champ dans la fiche : etiquette en LX, zone de saisie
  en EX (largeur W), ligne Y }
Procedure CardPos(F : LongInt; Var LX, Y, EX, W : LongInt);
Var R, C : LongInt;
Begin
  Case F Of
    0 : Begin R := 0; C := 0; End;
    1 : Begin R := 0; C := 1; End;
    2 : Begin R := 1; C := 2; End;
    3 : Begin R := 2; C := 0; End;
    4 : Begin R := 2; C := 1; End;
    5 : Begin R := 3; C := 0; End;
    10 : Begin R := 3; C := 1; End;
    6 : Begin R := 4; C := 2; End;
    7 : Begin R := 5; C := 0; End;
    8 : Begin R := 5; C := 1; End;
    9 : Begin R := 6; C := 0; End;
    11 : Begin R := 6; C := 1; End;
  Else
    Begin R := 7; C := 2; End;
  End;
  Y := 14 + R * 30;
  If C = 1 Then Begin LX := 304; EX := 420; W := 170; End
  Else Begin LX := 10; EX := 134; If C = 2 Then W := 456 Else W := 156; End;
End;

Procedure DlgPaint(H : LongInt);
Var Ps : Array[0..15] Of LongInt; Dc, F, X, Y, EX, W : LongInt;
Begin
  Dc := BeginPaint(H, LongInt(@Ps));
  Bar(Dc, 0, 0, 600, 420, ClrFace);
  Dummy := SelectObject(Dc, FontS);
  { creees dans l'ordre de Tab : ligne par ligne }
  For K := 0 To NFld - 1 Do
  Begin
    F := TabOrd(K);
    CardPos(F, X, Y, EX, W);
    Txt(Dc, X, Y + 3, CardLbl(F) + ' :', ClrDark, ClrFace);
  End;
  Bar(Dc, 10, 254, 590, 255, ClrShadow);
  Bar(Dc, 10, 255, 590, 256, ClrHi);
  Dummy := EndPaint(H, LongInt(@Ps));
End;

{ ordre de passage (Tab) : celui de la fiche, ligne par ligne }
Function TabOrd(K : LongInt) : LongInt;
Begin
  Case K Of
    0 : TabOrd := 0; 1 : TabOrd := 1; 2 : TabOrd := 2; 3 : TabOrd := 3; 4 : TabOrd := 4;
    5 : TabOrd := 5; 6 : TabOrd := 10; 7 : TabOrd := 6; 8 : TabOrd := 7; 9 : TabOrd := 8;
    10 : TabOrd := 9; 11 : TabOrd := 11;
  Else
    TabOrd := 12;
  End;
End;

Function DlgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  DlgProc := 0;
  Case Msg Of
    WM_PAINT : DlgPaint(H);
    WM_ERASEBKGND : DlgProc := 1;
    WM_COMMAND :
      If (WP And $FFFF) = ID_OK Then DlgClose(True)
      Else If (WP And $FFFF) = ID_CANCEL Then DlgClose(False);
    WM_CLOSE : DlgClose(False);
  Else
    DlgProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

{ I : contact a modifier, -1 : nouveau }
Procedure OpenCard(I : LongInt);
Var F, K, X, Y, W, EX, Fw, Fh : LongInt; Rc : Array[0..3] Of LongInt; T : String;
Begin
  If DlgW <> 0 Then Exit;
  DlgIdx := I;
  If I < 0 Then T := 'Nouveau contact' Else T := 'Propri'#233't'#233's de ' + FullName(I);
  Rc[0] := 0; Rc[1] := 0; Rc[2] := 600; Rc[3] := 304;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), WS_POPUP Or WS_CAPTION Or WS_SYSMENU, 0, WS_EX_DLGMODALFRAME);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  PutZ(LongInt(@NameZ2), 'WabCard');
  DlgW := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@NameZ2), Z(Disp(T)),
                          WS_POPUP Or WS_CAPTION Or WS_SYSMENU Or WS_CLIPCHILDREN,
                          MaxI(0, (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2),
                          MaxI(0, (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2), Fw, Fh, Wnd, 0, Inst, 0);
  If DlgW = 0 Then Exit;
  { creees dans l'ordre de Tab : ligne par ligne }
  For K := 0 To NFld - 1 Do
  Begin
    F := TabOrd(K);
    CardPos(F, X, Y, EX, W);
    DlgEd[F] := Ctl(DlgW, 'EDIT', '', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, EX, Y, W, 22, ID_FLD0 + F);
    If I >= 0 Then SetText(DlgEd[F], Con[I]^[F]);
  End;
  Dummy := Ctl(DlgW, 'BUTTON', 'OK', WS_TABSTOP Or BS_DEFPUSHBUTTON, 600 - 200, 304 - 36, 90, 26, ID_OK);
  Dummy := Ctl(DlgW, 'BUTTON', 'Annuler', WS_TABSTOP, 600 - 100, 304 - 36, 90, 26, ID_CANCEL);
  Dummy := EnableWindow(Wnd, 0);
  Dummy := ShowWindow(DlgW, 1);
  Dummy := UpdateWindow(DlgW);
  Dummy := SetFocus(DlgEd[0]);
End;

{ ==================================================================== }
{ Commandes                                                             }
{ ==================================================================== }

Procedure DeleteSel;
Var K : LongInt;
Begin
  If (Sel < 0) Or (Sel >= NCon) Then Exit;
  If Ask('Supprimer ' + FullName(Sel) + ' du carnet d''adresses ?', 'Carnet d''adresses',
         MB_YESNO Or MB_ICONQUESTION) <> IDYES Then Exit;
  FreeMem(Con[Sel], SizeOf(TContact));
  For K := Sel To NCon - 2 Do Con[K] := Con[K + 1];
  Dec(NCon);
  SaveBook;
  Refresh;
End;

Procedure CopySel;
Var S : String; F, N, H, K : LongInt; P : PByt;
Begin
  If (Sel < 0) Or (Sel >= NCon) Then Exit;
  N := 0;
  For F := 0 To NFld - 1 Do
    If Con[Sel]^[F] <> '' Then
    Begin
      S := Disp(FldName(F) + ' : ' + Con[Sel]^[F]) + #13#10;
      For K := 1 To Length(S) Do If N < 4000 Then Begin LineBuf[N] := Ord(S[K]); Inc(N); End;
    End;
  LineBuf[N] := 0;
  If OpenClipboard(Wnd) = 0 Then Exit;
  Dummy := EmptyClipboard;
  H := GlobalAlloc(0, N + 1);
  If H <> 0 Then
  Begin
    For K := 0 To N Do Begin P := PByt(H + K); P^ := LineBuf[K]; End;
    Dummy := SetClipboardData(CF_TEXT, H);
  End;
  Dummy := CloseClipboard;
End;

{ zone "Tapez le nom" : premier contact qui commence par ce texte }
Procedure SearchName;
Var S : String; I : LongInt;
Begin
  S := UpS(TrimS(CtlText(SrchW)));
  If S = '' Then Exit;
  For I := 0 To NCon - 1 Do
    If (Copy(UpS(FullName(I)), 1, Length(S)) = S) Or (Copy(UpS(Con[I]^[1]), 1, Length(S)) = S) Or
       (Copy(UpS(Con[I]^[2]), 1, Length(S)) = S) Then
    Begin
      Sel := I;
      Refresh;
      Exit;
    End;
End;

Procedure SetMarks;
Begin
  MCheck(MView, CM_SORTNAME, SortBy = 0);
  MCheck(MView, CM_SORTFIRST, SortBy = 1);
  MCheck(MView, CM_SORTMAIL, SortBy = 2);
End;

Procedure Command(Id : LongInt);
Var P : String; N : LongInt;
Begin
  Case Id Of
    CM_NEW : OpenCard(-1);
    CM_PROPS : If (Sel >= 0) And (Sel < NCon) Then OpenCard(Sel);
    CM_DELETE : DeleteSel;
    CM_IMPORT :
      If FileDlg(False, P) Then
      Begin
        N := ImportCsv(P);
        SaveBook;
        Dummy := Ask(IStr(N) + ' contact(s) import'#233'(s) de ' + P + '.', 'Carnet d''adresses', MB_OK Or MB_ICONINFO);
      End;
    CM_EXPORT :
      If FileDlg(True, P) Then
        If ExportCsv(P) Then
          Dummy := Ask(IStr(NCon) + ' contact(s) export'#233'(s) dans ' + P + '.', 'Carnet d''adresses',
                       MB_OK Or MB_ICONINFO);
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_COPY : CopySel;
    CM_FIND : Dummy := SetFocus(SrchW);
    CM_SORTNAME, CM_SORTFIRST, CM_SORTMAIL :
      Begin
        SortBy := Id - CM_SORTNAME;
        SortList;
      End;
    CM_ABOUT : Dummy := Ask('Carnet d''adresses de Pasdows 95'#10#10'Contacts, adresses de messagerie et ' +
                            't'#233'l'#233'phones ; importation et exportation CSV. Programme '#233'crit en Pascal ' +
                            'et compil'#233' par WPC.', #192' propos du Carnet d''adresses', MB_OK Or MB_ICONINFO);
  End;
  SetMarks;
  Refresh;
End;

Function ToolCmd(I : LongInt) : LongInt;
Begin
  Case I Of
    0 : ToolCmd := CM_NEW;
    1 : ToolCmd := CM_PROPS;
    2 : ToolCmd := CM_DELETE;
  Else
    ToolCmd := CM_FIND;
  End;
End;

Function HitTool(X, Y : LongInt) : LongInt;
Var I, X1, X2 : LongInt;
Begin
  HitTool := -1;
  If (Y < 4) Or (Y >= TbH - 4) Then Exit;
  For I := 0 To 3 Do
  Begin
    ToolRect(I, X1, X2);
    If (X >= X1) And (X < X2) Then HitTool := I;
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, I, X, Y : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then
        Begin
          CW := MinI(Rc[2], 1024); CH := MinI(Rc[3], 768);
          If VSb <> 0 Then Dummy := MoveWindow(VSb, CW - SbW - 1, ListY, SbW, CH - StH - ListY - 1, 1);
          Ensure;
          Dummy := InvalidateRect(H, 0, 0);
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
    WM_VSCROLL :
      Begin
        Case WP And $FFFF Of
          SB_LINEUP : Dec(Top);
          SB_LINEDOWN : Inc(Top);
          SB_PAGEUP : Top := Top - NRows;
          SB_PAGEDOWN : Top := Top + NRows;
          SB_THUMBPOSITION, SB_THUMBTRACK : Top := (WP Shr 16) And $FFFF;
        End;
        If Top > NCon - NRows Then Top := NCon - NRows;
        If Top < 0 Then Top := 0;
        Refresh;
      End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        I := HitTool(X, Y);
        If (I >= 0) And (Msg = WM_LBUTTONDOWN) Then
        Begin
          If ToolOn(I) Then Begin BtnDown := I; Dummy := SetCapture(H); Paint0; End;
        End
        Else If Y >= ListY + HdrH Then
        Begin
          Dummy := SetFocus(H);
          I := Top + (Y - ListY - HdrH - 1) Div RowH;
          If (I >= 0) And (I < NCon) Then
          Begin
            Sel := I;
            Refresh;
            If Msg = WM_LBUTTONDBLCLK Then OpenCard(Sel);
          End;
        End;
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
        VK_UP : Begin If Sel > 0 Then Dec(Sel); Refresh; End;
        VK_DOWN : Begin If Sel < NCon - 1 Then Inc(Sel); Refresh; End;
        VK_HOME : Begin Sel := 0; Refresh; End;
        VK_END : Begin Sel := NCon - 1; Refresh; End;
        VK_PRIOR : Begin Sel := MaxI(0, Sel - NRows); Refresh; End;
        VK_NEXT : Begin Sel := MinI(NCon - 1, Sel + NRows); Refresh; End;
        VK_RETURN : Command(CM_PROPS);
        VK_DELETE : Command(CM_DELETE);
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_CHAR :
      Case WP Of
        14 : Command(CM_NEW);                         { Ctrl+N }
        3 : Command(CM_COPY);                         { Ctrl+C }
        6 : Command(CM_FIND);                         { Ctrl+F }
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND :
      If LP = 0 Then Command(WP And $FFFF)
      Else If ((WP And $FFFF) = ID_SEARCH) And (((WP Shr 16) And $FFFF) = EN_CHANGE) Then SearchName;
    WM_CLOSE :
      Begin
        If Dirty Then SaveBook;
        Dummy := DestroyWindow(H);
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  Dc, MFile, MEdit, MHelp, K : LongInt;
  Rc0 : Array[0..3] Of LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  NCon := 0; Sel := 0; Top := 0; SortBy := 0; BtnDown := -1; DlgW := 0; VSb := 0; Dirty := False;
  DataPath := ParamStr(0);
  K := Length(DataPath);
  While (K > 0) And (DataPath[K] <> '\') Do Dec(K);
  DataPath := Copy(DataPath, 1, K) + 'CARNET.WAB';
  LoadBook;
  CW := 600; CH := 340;
  RegClass('WabWnd', LongInt(@MainProc), CS_DBLCLKS);
  RegClass('WabCard', LongInt(@DlgProc), 0);
  Wnd := MainWindow('WabWnd', 'Carnet d''adresses', WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MEdit := CreatePopupMenu; MView := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MFile, CM_NEW, '~Nouveau contact...'#9'Ctrl+N');
  MItem(MFile, CM_PROPS, '~Propri'#233't'#233's'#9'Entr'#233'e');
  MItem(MFile, CM_DELETE, '~Supprimer'#9'Suppr');
  MItem(MFile, 0, '');
  MItem(MFile, CM_IMPORT, '~Importer (fichier CSV)...');
  MItem(MFile, CM_EXPORT, '~Exporter (fichier CSV)...');
  MItem(MFile, 0, '');
  MItem(MFile, CM_QUIT, '~Quitter');
  MItem(MEdit, CM_COPY, '~Copier'#9'Ctrl+C');
  MItem(MEdit, CM_FIND, '~Rechercher'#9'Ctrl+F');
  MItem(MView, CM_SORTNAME, 'Trier par ~nom');
  MItem(MView, CM_SORTFIRST, 'Trier par ~pr'#233'nom');
  MItem(MView, CM_SORTMAIL, 'Trier par ~adresse de messagerie');
  MItem(MHelp, CM_ABOUT, #192' ~propos du Carnet d''adresses');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MEdit, '~Edition');
  MSub(MenuBar, MView, '~Affichage');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  SrchW := Ctl(Wnd, 'EDIT', '', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 6, TbH + 28, 260, 22, ID_SEARCH);
  VSb := Ctl(Wnd, 'SCROLLBAR', '', 1, CW - SbW - 1, ListY, SbW, CH - StH - ListY - 1, 11);
  Dummy := GetClientRect(Wnd, LongInt(@Rc0));
  If (Rc0[2] > 0) And (Rc0[3] > 0) Then Begin CW := Rc0[2]; CH := Rc0[3]; End;
  Dummy := MoveWindow(VSb, CW - SbW - 1, ListY, SbW, CH - StH - ListY - 1, 1);
  Dc := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, 1024, 768);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  SetMarks;
  Ensure;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  If Dirty Then SaveBook;
  ExitProcess(0);
END.
