{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: MSTSC - Connexion Bureau a distance (client RDP) de
  Pasdows 95 (Win32).
}

Program MSTSC;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\MSTSC.PAS MSTSC.EXE

  Client du protocole RDP (Remote Desktop Protocol) de Windows, pour
  ouvrir une session sur Windows Server 2008 a 2022 (et Windows 7 a 11,
  xrdp, FreeRDP) : Demarrer, Programmes, Accessoires, Communications,
  Connexion Bureau a distance (MSTSC.EXE, comme Windows).
  - Securite : TLS 1.2 (ECDHE x25519, AES-128-GCM, la couche TLS du
    noyau reprise ici) et l'authentification NLA de Windows Server 2019
    (CredSSP version 6 : NTLMv2 avec signature et scellement RC4, cle
    publique du serveur liee par SHA-256 avec un nonce, TSCredentials).
    La securite RDP standard (RC4 de RDP 5) n'est pas proposee : Windows
    Server 2019 utilise TLS ou NLA par defaut.
  - Connexion : X.224 (negociation de la securite), MCS et GCC
    (donnees du client : 16 bits par point, taille choisie), Erect
    Domain, Attach User, Channel Join, Client Info (ouverture de session
    automatique), licence, Demand Active / Confirm Active (capacites :
    sans ordres de dessin, l'ecran arrive en bitmaps), Synchronize,
    Control, Font List.
  - Affichage : mises a jour par le chemin rapide (fast-path, fragments
    reassembles) ou classiques, bitmaps non compresses ou compresses en
    RLE entrelace (8, 15, 16 et 24 bits), dans une image 16 bits dessinee
    par StretchDIBits.
  - Entrees : clavier par codes de balayage, souris (boutons, molette),
    par le chemin rapide ; Ctrl+Alt+Fin envoie Ctrl+Alt+Suppr,
    Ctrl+Alt+Pause (ou Ctrl+Alt+Entree) bascule le plein ecran.
  La reception tourne dans une tache (CreateThread) ; les envois sont
  proteges par une section critique. Le dernier ordinateur et
  l'utilisateur sont gardes comme Windows dans HKEY_CURRENT_USER\
  Software\Microsoft\Terminal Server Client. }

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
{ Memoire (pointeurs : Mem[] n'existe pas pour les programmes Win32),   }
{ Winsock                                                                }
{ ==================================================================== }

Type
  PWrd = ^Word;

Procedure RtlMoveMemory(D, S, N : LongInt); stdcall; external 'kernel32.dll' name 'RtlMoveMemory';
Procedure RtlZeroMemory(D, N : LongInt); stdcall; external 'kernel32.dll' name 'RtlZeroMemory';
Function CreateThread(Sec, Stk, Proc, Prm, Fl, PId : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateThread';
Procedure InitializeCriticalSection(P : LongInt); stdcall; external 'kernel32.dll' name 'InitializeCriticalSection';
Procedure EnterCriticalSection(P : LongInt); stdcall; external 'kernel32.dll' name 'EnterCriticalSection';
Procedure LeaveCriticalSection(P : LongInt); stdcall; external 'kernel32.dll' name 'LeaveCriticalSection';
Function QueryPerformanceCounter(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'QueryPerformanceCounter';
Function GetCursorPos(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetCursorPos';
Function WSAStartup(V, P : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'WSAStartup';
Function socket(Af, Typ, Pr : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'socket';
Function connect(S, A, L : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'connect';
Function send(S, B, N, F : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'send';
Function recv(S, B, N, F : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'recv';
Function closesocket(S : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'closesocket';
Function gethostbyname(N : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'gethostbyname';
Function inet_addr(N : LongInt) : LongInt; stdcall; external 'wsock32.dll' name 'inet_addr';

Function GB(A : LongInt) : LongInt;
Begin
  GB := PByt(A)^;
End;

Procedure SB(A, V : LongInt);
Begin
  PByt(A)^ := V And 255;
End;

{ mots et doubles mots petit-boutistes }
Function GW(A : LongInt) : LongInt;
Begin
  GW := PByt(A)^ Or (PByt(A + 1)^ Shl 8);
End;

Procedure SW(A, V : LongInt);
Begin
  PByt(A)^ := V And 255; PByt(A + 1)^ := (V Shr 8) And 255;
End;

Function GL(A : LongInt) : LongInt;
Begin
  GL := PLng(A)^;
End;

Procedure SL(A, V : LongInt);
Begin
  PLng(A)^ := V;
End;

{ mots gros-boutistes (TPKT, MCS) }
Function GWB(A : LongInt) : LongInt;
Begin
  GWB := (PByt(A)^ Shl 8) Or PByt(A + 1)^;
End;

Procedure SWB(A, V : LongInt);
Begin
  PByt(A)^ := (V Shr 8) And 255; PByt(A + 1)^ := V And 255;
End;

Procedure MoveB(Src, Dst, N : LongInt);
Begin
  If N > 0 Then RtlMoveMemory(Dst, Src, N);
End;

Procedure ZeroB(A, N : LongInt);
Begin
  If N > 0 Then RtlZeroMemory(A, N);
End;

Function NewMem(N : LongInt) : LongInt;
Begin
  NewMem := GlobalAlloc($40, N);
End;

{ ---- fonctions attendues par la couche TLS (reprise du noyau) ---- }

Type
  TlPtr = LongInt;

Var
  TlCert : Array[0..8191] Of Byte;       { certificat du serveur (DER) }
  TlCertLen : LongInt;
  NetStop : Boolean;                      { deconnexion demandee }

Function TlGet(A : TlPtr) : LongInt;
Begin
  TlGet := PByt(A)^;
End;

Procedure TlPut(A : TlPtr; V : LongInt);
Begin
  PByt(A)^ := V And 255;
End;

Function TlNew(N : LongInt) : TlPtr;
Begin
  TlNew := NewMem(N);
End;

Procedure TlEntropy; Forward;

Function TlSockSend(S, A, N : LongInt) : LongInt;
Begin
  TlSockSend := send(S, A, N, 0);
End;

Function TlSockRecv(S, A, N : LongInt) : LongInt;
Begin
  If NetStop Then TlSockRecv := -1
  Else TlSockRecv := recv(S, A, N, 0);
End;

Procedure TlSockClose(S : LongInt);
Begin
  Dummy := closesocket(S);
End;

Function TlIsIp(S : String) : Boolean;
Var K : LongInt;
Begin
  TlIsIp := False;
  For K := 1 To Length(S) Do
    If Not (S[K] In ['0'..'9', '.']) Then Exit;
  TlIsIp := S <> '';
End;

{ connexion TCP : socket ou -1 (Err : message) }
Function TcpOpen(Host : String; Port : LongInt; Var Err : String) : LongInt;
Var A : Array[0..15] Of Byte; S, IP, H : LongInt;
Begin
  TcpOpen := -1;
  PutZ(LongInt(@NameZ2), Host);
  IP := inet_addr(LongInt(@NameZ2));
  If (IP = -1) Or (IP = 0) Then
  Begin
    H := gethostbyname(LongInt(@NameZ2));
    If H = 0 Then
    Begin
      Err := 'Ordinateur introuvable : ' + Host;
      Exit;
    End;
    IP := GL(GL(GL(H + 12)));
  End;
  S := socket(2, 1, 6);
  If S = -1 Then
  Begin
    Err := 'Socket impossible';
    Exit;
  End;
  ZeroB(LongInt(@A[0]), 16);
  A[0] := 2; A[2] := (Port Shr 8) And 255; A[3] := Port And 255;
  SL(LongInt(@A[4]), IP);
  If connect(S, LongInt(@A[0]), 16) <> 0 Then
  Begin
    Err := 'L''ordinateur distant ne r'#233'pond pas sur le port ' + IStr(Port) +
           ' (Bureau '#224' distance d'#233'sactiv'#233' ou pare-feu).';
    Dummy := closesocket(S);
    Exit;
  End;
  TcpOpen := S;
End;
{ ==================================================================== }
{ Cryptographie de TLS 1.2 : SHA-256, HMAC, PRF, AES-128-GCM, X25519  }
{ (mots de 32 bits en LongInt ; Shr est un decalage logique)          }
{ ==================================================================== }

Type
  TlSha = Record
    H : Array[0..7] Of LongInt;
    B : Array[0..63] Of Byte;
    N : LongInt;                     { octets en attente dans B }
    Len : LongInt;                   { longueur totale (octets) }
  End;
  TlFe = Array[0..31] Of LongInt;    { element de GF(2^255-19), 8 bits }
  TlAes = Record
    RK : Array[0..43] Of LongInt;    { cles de tour (AES-128) }
    M : Array[0..63] Of LongInt;     { GHASH : 16 multiples de H }
  End;

Const
  TlShaKC : Array[0..63] Of LongWord = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1,
    $923F82A4, $AB1C5ED5, $D807AA98, $12835B01, $243185BE, $550C7DC3,
    $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174, $E49B69C1, $EFBE4786,
    $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147,
    $06CA6351, $14292967, $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13,
    $650A7354, $766A0ABB, $81C2C92E, $92722C85, $A2BFE8A1, $A81A664B,
    $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A,
    $5B9CCA4F, $682E6FF3, $748F82EE, $78A5636F, $84C87814, $8CC70208,
    $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2);
  TlSBox : Array[0..255] Of Byte = (
    $63, $7C, $77, $7B, $F2, $6B, $6F, $C5, $30, $01, $67, $2B,
    $FE, $D7, $AB, $76, $CA, $82, $C9, $7D, $FA, $59, $47, $F0,
    $AD, $D4, $A2, $AF, $9C, $A4, $72, $C0, $B7, $FD, $93, $26,
    $36, $3F, $F7, $CC, $34, $A5, $E5, $F1, $71, $D8, $31, $15,
    $04, $C7, $23, $C3, $18, $96, $05, $9A, $07, $12, $80, $E2,
    $EB, $27, $B2, $75, $09, $83, $2C, $1A, $1B, $6E, $5A, $A0,
    $52, $3B, $D6, $B3, $29, $E3, $2F, $84, $53, $D1, $00, $ED,
    $20, $FC, $B1, $5B, $6A, $CB, $BE, $39, $4A, $4C, $58, $CF,
    $D0, $EF, $AA, $FB, $43, $4D, $33, $85, $45, $F9, $02, $7F,
    $50, $3C, $9F, $A8, $51, $A3, $40, $8F, $92, $9D, $38, $F5,
    $BC, $B6, $DA, $21, $10, $FF, $F3, $D2, $CD, $0C, $13, $EC,
    $5F, $97, $44, $17, $C4, $A7, $7E, $3D, $64, $5D, $19, $73,
    $60, $81, $4F, $DC, $22, $2A, $90, $88, $46, $EE, $B8, $14,
    $DE, $5E, $0B, $DB, $E0, $32, $3A, $0A, $49, $06, $24, $5C,
    $C2, $D3, $AC, $62, $91, $95, $E4, $79, $E7, $C8, $37, $6D,
    $8D, $D5, $4E, $A9, $6C, $56, $F4, $EA, $65, $7A, $AE, $08,
    $BA, $78, $25, $2E, $1C, $A6, $B4, $C6, $E8, $DD, $74, $1F,
    $4B, $BD, $8B, $8A, $70, $3E, $B5, $66, $48, $03, $F6, $0E,
    $61, $35, $57, $B9, $86, $C1, $1D, $9E, $E1, $F8, $98, $11,
    $69, $D9, $8E, $94, $9B, $1E, $87, $E9, $CE, $55, $28, $DF,
    $8C, $A1, $89, $0D, $BF, $E6, $42, $68, $41, $99, $2D, $0F,
    $B0, $54, $BB, $16);
  TlLast4 : Array[0..15] Of LongInt = ($0000, $1C20, $3840, $2460,
    $7080, $6CA0, $48C0, $54E0, $E100, $FD20, $D940, $C560, $9180,
    $8DA0, $A9C0, $B5E0);

Var
  TlK : Array[0..63] Of LongInt;
  TlTe : Array[0..255] Of LongInt;   { table T0 de l'AES }
  TlReady : Boolean;

Function TlRor(X, N : LongInt) : LongInt;
Begin
  TlRor := (X Shr N) Or (X Shl (32 - N));
End;

Function TlXt(B : LongInt) : LongInt;
Begin
  B := B Shl 1;
  If (B And $100) <> 0 Then B := B Xor $11B;
  TlXt := B And 255;
End;

Procedure TlInit;
Var I, S, S2, S3 : LongInt; W : LongInt;
Begin
  If TlReady Then Exit;
  For I := 0 To 63 Do Begin W := TlShaKC[I]; TlK[I] := W; End;
  For I := 0 To 255 Do
  Begin
    S := TlSBox[I]; S2 := TlXt(S); S3 := S2 Xor S;
    TlTe[I] := (S2 Shl 24) Or (S Shl 16) Or (S Shl 8) Or S3;
  End;
  TlReady := True;
End;

{ ---- SHA-256 ---- }

Procedure TlShaBlock(Var C : TlSha);
Var W : Array[0..63] Of LongInt; I, A, B, D, E, F, G, H, T1, T2,
    Cc, S0, S1 : LongInt;
Begin
  For I := 0 To 15 Do
    W[I] := (C.B[I * 4] Shl 24) Or (C.B[I * 4 + 1] Shl 16) Or
            (C.B[I * 4 + 2] Shl 8) Or C.B[I * 4 + 3];
  For I := 16 To 63 Do
  Begin
    S0 := TlRor(W[I - 15], 7) Xor TlRor(W[I - 15], 18) Xor
          (W[I - 15] Shr 3);
    S1 := TlRor(W[I - 2], 17) Xor TlRor(W[I - 2], 19) Xor
          (W[I - 2] Shr 10);
    W[I] := W[I - 16] + S0 + W[I - 7] + S1;
  End;
  A := C.H[0]; B := C.H[1]; Cc := C.H[2]; D := C.H[3];
  E := C.H[4]; F := C.H[5]; G := C.H[6]; H := C.H[7];
  For I := 0 To 63 Do
  Begin
    S1 := TlRor(E, 6) Xor TlRor(E, 11) Xor TlRor(E, 25);
    T1 := H + S1 + ((E And F) Xor ((Not E) And G)) + TlK[I] + W[I];
    S0 := TlRor(A, 2) Xor TlRor(A, 13) Xor TlRor(A, 22);
    T2 := S0 + ((A And B) Xor (A And Cc) Xor (B And Cc));
    H := G; G := F; F := E; E := D + T1;
    D := Cc; Cc := B; B := A; A := T1 + T2;
  End;
  C.H[0] := C.H[0] + A; C.H[1] := C.H[1] + B; C.H[2] := C.H[2] + Cc;
  C.H[3] := C.H[3] + D; C.H[4] := C.H[4] + E; C.H[5] := C.H[5] + F;
  C.H[6] := C.H[6] + G; C.H[7] := C.H[7] + H;
End;

Procedure TlShaInit(Var C : TlSha);
Begin
  TlInit;
  C.H[0] := $6A09E667; C.H[1] := LongInt($BB67AE85);
  C.H[2] := $3C6EF372; C.H[3] := LongInt($A54FF53A);
  C.H[4] := $510E527F; C.H[5] := LongInt($9B05688C);
  C.H[6] := $1F83D9AB; C.H[7] := $5BE0CD19;
  C.N := 0; C.Len := 0;
End;

{ ajoute N octets a partir de l'adresse A }
Procedure TlShaAdd(Var C : TlSha; A : TlPtr; N : LongInt);
Var I : LongInt;
Begin
  For I := 0 To N - 1 Do
  Begin
    C.B[C.N] := TlGet(A + I);
    Inc(C.N);
    If C.N = 64 Then Begin TlShaBlock(C); C.N := 0; End;
  End;
  C.Len := C.Len + N;
End;

Procedure TlShaByte(Var C : TlSha; V : LongInt);
Var B : Array[0..0] Of Byte;
Begin
  B[0] := V And 255;
  TlShaAdd(C, TlPtr(@B[0]), 1);
End;

{ empreinte de 32 octets a l'adresse Out (C est detruit) }
Procedure TlShaDone(Var C : TlSha; Out0 : TlPtr);
Var I, L : LongInt;
Begin
  L := C.Len;
  TlShaByte(C, $80);
  While C.N <> 56 Do TlShaByte(C, 0);
  TlShaByte(C, 0); TlShaByte(C, 0); TlShaByte(C, 0);
  TlShaByte(C, (L Shr 29) And 7);
  TlShaByte(C, (L Shr 21) And 255); TlShaByte(C, (L Shr 13) And 255);
  TlShaByte(C, (L Shr 5) And 255); TlShaByte(C, (L Shl 3) And 255);
  For I := 0 To 7 Do
  Begin
    TlPut(Out0 + I * 4, C.H[I] Shr 24);
    TlPut(Out0 + I * 4 + 1, C.H[I] Shr 16);
    TlPut(Out0 + I * 4 + 2, C.H[I] Shr 8);
    TlPut(Out0 + I * 4 + 3, C.H[I]);
  End;
End;

{ ---- HMAC-SHA256 (cle de 64 octets au plus) et PRF de TLS 1.2 ---- }

Procedure TlHmac(Key : TlPtr; KLen : LongInt; Msg : TlPtr;
  MLen : LongInt; Msg2 : TlPtr; M2Len : LongInt; Out0 : TlPtr);
Var C : TlSha; Pad : Array[0..63] Of Byte; In0 : Array[0..31] Of Byte;
    I : LongInt;
Begin
  For I := 0 To 63 Do
    If I < KLen Then Pad[I] := TlGet(Key + I) Xor $36
    Else Pad[I] := $36;
  TlShaInit(C);
  TlShaAdd(C, TlPtr(@Pad[0]), 64);
  TlShaAdd(C, Msg, MLen);
  If M2Len > 0 Then TlShaAdd(C, Msg2, M2Len);
  TlShaDone(C, TlPtr(@In0[0]));
  For I := 0 To 63 Do Pad[I] := Pad[I] Xor ($36 Xor $5C);
  TlShaInit(C);
  TlShaAdd(C, TlPtr(@Pad[0]), 64);
  TlShaAdd(C, TlPtr(@In0[0]), 32);
  TlShaDone(C, Out0);
End;

{ PRF(secret, label + seed) sur N octets }
Procedure TlPrf(Sec : TlPtr; SLen : LongInt; Const Lbl : String;
  Seed : TlPtr; SdLen : LongInt; Out0 : TlPtr; N : LongInt);
Var LS : Array[0..127] Of Byte; A, T : Array[0..31] Of Byte;
    I, L, Done : LongInt;
Begin
  L := Length(Lbl);
  For I := 1 To L Do LS[I - 1] := Ord(Lbl[I]);
  For I := 0 To SdLen - 1 Do LS[L + I] := TlGet(Seed + I);
  L := L + SdLen;
  TlHmac(Sec, SLen, TlPtr(@LS[0]), L, TlPtr(@LS[0]), 0, TlPtr(@A[0]));
  Done := 0;
  While Done < N Do
  Begin
    TlHmac(Sec, SLen, TlPtr(@A[0]), 32, TlPtr(@LS[0]), L,
           TlPtr(@T[0]));
    I := 0;
    While (I < 32) And (Done < N) Do
    Begin
      TlPut(Out0 + Done, T[I]); Inc(I); Inc(Done);
    End;
    TlHmac(Sec, SLen, TlPtr(@A[0]), 32, TlPtr(@A[0]), 0, TlPtr(@A[0]));
  End;
End;

{ ---- AES-128 (chiffrement seulement : GCM n'utilise que lui) ---- }

Type
  TlBlk = Array[0..15] Of Byte;
  TlKey32 = Array[0..31] Of Byte;

Var
  TlTe1, TlTe2, TlTe3 : Array[0..255] Of LongInt;

Procedure TlAesTables;
Var I : LongInt;
Begin
  TlInit;
  For I := 0 To 255 Do
  Begin
    TlTe1[I] := TlRor(TlTe[I], 8);
    TlTe2[I] := TlRor(TlTe[I], 16);
    TlTe3[I] := TlRor(TlTe[I], 24);
  End;
End;

Function TlSubW(W : LongInt) : LongInt;
Begin
  TlSubW := (TlSBox[(W Shr 24) And 255] Shl 24) Or
            (TlSBox[(W Shr 16) And 255] Shl 16) Or
            (TlSBox[(W Shr 8) And 255] Shl 8) Or TlSBox[W And 255];
End;

Function TlGetW(Var B : TlBlk; I : LongInt) : LongInt;
Begin
  TlGetW := (B[I] Shl 24) Or (B[I + 1] Shl 16) Or (B[I + 2] Shl 8) Or
            B[I + 3];
End;

Procedure TlPutW(Var B : TlBlk; I, W : LongInt);
Begin
  B[I] := (W Shr 24) And 255; B[I + 1] := (W Shr 16) And 255;
  B[I + 2] := (W Shr 8) And 255; B[I + 3] := W And 255;
End;

Procedure TlAesEnc(Var A : TlAes; Var Inp, Outp : TlBlk);
Var S0, S1, S2, S3, T0, T1, T2, T3, R, K : LongInt;
Begin
  S0 := TlGetW(Inp, 0) Xor A.RK[0]; S1 := TlGetW(Inp, 4) Xor A.RK[1];
  S2 := TlGetW(Inp, 8) Xor A.RK[2]; S3 := TlGetW(Inp, 12) Xor A.RK[3];
  K := 4;
  For R := 1 To 9 Do
  Begin
    T0 := TlTe[S0 Shr 24] Xor TlTe1[(S1 Shr 16) And 255] Xor
          TlTe2[(S2 Shr 8) And 255] Xor TlTe3[S3 And 255] Xor A.RK[K];
    T1 := TlTe[S1 Shr 24] Xor TlTe1[(S2 Shr 16) And 255] Xor
          TlTe2[(S3 Shr 8) And 255] Xor TlTe3[S0 And 255] Xor
          A.RK[K + 1];
    T2 := TlTe[S2 Shr 24] Xor TlTe1[(S3 Shr 16) And 255] Xor
          TlTe2[(S0 Shr 8) And 255] Xor TlTe3[S1 And 255] Xor
          A.RK[K + 2];
    T3 := TlTe[S3 Shr 24] Xor TlTe1[(S0 Shr 16) And 255] Xor
          TlTe2[(S1 Shr 8) And 255] Xor TlTe3[S2 And 255] Xor
          A.RK[K + 3];
    S0 := T0; S1 := T1; S2 := T2; S3 := T3;
    K := K + 4;
  End;
  T0 := (TlSBox[S0 Shr 24] Shl 24) Or (TlSBox[(S1 Shr 16) And 255] Shl 16)
        Or (TlSBox[(S2 Shr 8) And 255] Shl 8) Or TlSBox[S3 And 255];
  T1 := (TlSBox[S1 Shr 24] Shl 24) Or (TlSBox[(S2 Shr 16) And 255] Shl 16)
        Or (TlSBox[(S3 Shr 8) And 255] Shl 8) Or TlSBox[S0 And 255];
  T2 := (TlSBox[S2 Shr 24] Shl 24) Or (TlSBox[(S3 Shr 16) And 255] Shl 16)
        Or (TlSBox[(S0 Shr 8) And 255] Shl 8) Or TlSBox[S1 And 255];
  T3 := (TlSBox[S3 Shr 24] Shl 24) Or (TlSBox[(S0 Shr 16) And 255] Shl 16)
        Or (TlSBox[(S1 Shr 8) And 255] Shl 8) Or TlSBox[S2 And 255];
  TlPutW(Outp, 0, T0 Xor A.RK[40]); TlPutW(Outp, 4, T1 Xor A.RK[41]);
  TlPutW(Outp, 8, T2 Xor A.RK[42]); TlPutW(Outp, 12, T3 Xor A.RK[43]);
End;

{ cle de 16 octets ; prepare aussi les tables de GHASH (H = E(0)) }
Procedure TlAesKey(Var A : TlAes; Var Key : TlBlk);
Const Rc : Array[0..9] Of LongInt = ($01, $02, $04, $08, $10, $20,
  $40, $80, $1B, $36);
Var I, T, V0, V1, V2, V3, J, B : LongInt; Z : TlBlk;
Begin
  TlAesTables;
  For I := 0 To 3 Do A.RK[I] := TlGetW(Key, I * 4);
  For I := 4 To 43 Do
  Begin
    T := A.RK[I - 1];
    If (I And 3) = 0 Then
      T := TlSubW(TlRor(T, 24)) Xor (Rc[I Div 4 - 1] Shl 24);
    A.RK[I] := A.RK[I - 4] Xor T;
  End;
  For I := 0 To 15 Do Z[I] := 0;
  TlAesEnc(A, Z, Z);
  V0 := TlGetW(Z, 0); V1 := TlGetW(Z, 4);
  V2 := TlGetW(Z, 8); V3 := TlGetW(Z, 12);
  For I := 0 To 3 Do A.M[I] := 0;
  A.M[32] := V0; A.M[33] := V1; A.M[34] := V2; A.M[35] := V3;
  I := 4;
  While I > 0 Do
  Begin
    B := V3 And 1;
    V3 := (V3 Shr 1) Or (V2 Shl 31);
    V2 := (V2 Shr 1) Or (V1 Shl 31);
    V1 := (V1 Shr 1) Or (V0 Shl 31);
    V0 := V0 Shr 1;
    If B <> 0 Then V0 := V0 Xor LongInt($E1000000);
    A.M[I * 4] := V0; A.M[I * 4 + 1] := V1;
    A.M[I * 4 + 2] := V2; A.M[I * 4 + 3] := V3;
    I := I Div 2;
  End;
  I := 2;
  While I <= 8 Do
  Begin
    For J := 1 To I - 1 Do
      For B := 0 To 3 Do
        A.M[(I + J) * 4 + B] := A.M[I * 4 + B] Xor A.M[J * 4 + B];
    I := I * 2;
  End;
End;

{ Y := Y * H dans GF(2^128) (tables de 4 bits, comme mbed TLS) }
Procedure TlGMul(Var A : TlAes; Var Y : TlBlk);
Var Z0, Z1, Z2, Z3, I, Lo, Hi, R : LongInt;
Begin
  Lo := Y[15] And 15;
  Z0 := A.M[Lo * 4]; Z1 := A.M[Lo * 4 + 1];
  Z2 := A.M[Lo * 4 + 2]; Z3 := A.M[Lo * 4 + 3];
  For I := 15 DownTo 0 Do
  Begin
    Lo := Y[I] And 15; Hi := (Y[I] Shr 4) And 15;
    If I <> 15 Then
    Begin
      R := Z3 And 15;
      Z3 := (Z3 Shr 4) Or (Z2 Shl 28); Z2 := (Z2 Shr 4) Or (Z1 Shl 28);
      Z1 := (Z1 Shr 4) Or (Z0 Shl 28);
      Z0 := (Z0 Shr 4) Xor (TlLast4[R] Shl 16);
      Z0 := Z0 Xor A.M[Lo * 4]; Z1 := Z1 Xor A.M[Lo * 4 + 1];
      Z2 := Z2 Xor A.M[Lo * 4 + 2]; Z3 := Z3 Xor A.M[Lo * 4 + 3];
    End;
    R := Z3 And 15;
    Z3 := (Z3 Shr 4) Or (Z2 Shl 28); Z2 := (Z2 Shr 4) Or (Z1 Shl 28);
    Z1 := (Z1 Shr 4) Or (Z0 Shl 28);
    Z0 := (Z0 Shr 4) Xor (TlLast4[R] Shl 16);
    Z0 := Z0 Xor A.M[Hi * 4]; Z1 := Z1 Xor A.M[Hi * 4 + 1];
    Z2 := Z2 Xor A.M[Hi * 4 + 2]; Z3 := Z3 Xor A.M[Hi * 4 + 3];
  End;
  TlPutW(Y, 0, Z0); TlPutW(Y, 4, Z1); TlPutW(Y, 8, Z2); TlPutW(Y, 12, Z3);
End;

{ AES-128-GCM sur N octets a l'adresse D (chiffre ou dechiffre sur
  place) ; Iv : 12 octets, Aad : NA octets ; Tag : 16 octets calcules
  (sur le texte chiffre) }
Procedure TlGcm(Var A : TlAes; Var Iv : TlBlk; Var Aad : TlBlk;
  NA : LongInt; D : TlPtr; N : LongInt; Enc : Boolean; Var Tag : TlBlk);
Var J0, Cb, Ks, Y : TlBlk; I, K, L, C : LongInt;
Begin
  For I := 0 To 11 Do J0[I] := Iv[I];
  J0[12] := 0; J0[13] := 0; J0[14] := 0; J0[15] := 1;
  Cb := J0;
  For I := 0 To 15 Do Y[I] := 0;
  For I := 0 To NA - 1 Do Y[I] := Aad[I];
  If NA > 0 Then TlGMul(A, Y);
  K := 0;
  While K < N Do
  Begin
    { compteur sur 32 bits }
    I := 15;
    Repeat
      C := (Cb[I] + 1) And 255; Cb[I] := C; Dec(I);
    Until (C <> 0) Or (I < 12);
    TlAesEnc(A, Cb, Ks);
    L := N - K; If L > 16 Then L := 16;
    For I := 0 To L - 1 Do
    Begin
      C := TlGet(D + K + I);
      If Enc Then
      Begin
        C := C Xor Ks[I]; TlPut(D + K + I, C);
      End
      Else TlPut(D + K + I, C Xor Ks[I]);
      Y[I] := Y[I] Xor C;
    End;
    TlGMul(A, Y);
    K := K + L;
  End;
  { longueurs en bits (64 bits chacune) }
  For I := 0 To 15 Do Ks[I] := 0;
  TlPutW(Ks, 4, NA * 8);
  TlPutW(Ks, 8, N Shr 29); TlPutW(Ks, 12, N Shl 3);
  For I := 0 To 15 Do Y[I] := Y[I] Xor Ks[I];
  TlGMul(A, Y);
  TlAesEnc(A, J0, Ks);
  For I := 0 To 15 Do Tag[I] := Y[I] Xor Ks[I];
End;

{ ---- X25519 (RFC 7748) : 32 chiffres de 8 bits signes ---- }

Procedure TlFeCarry(Var A : TlFe);
Var I, C, V, P : LongInt;
Begin
  For P := 1 To 2 Do
    For I := 0 To 31 Do
    Begin
      V := A[I];
      If V >= 0 Then C := V Shr 8 Else C := -((255 - V) Shr 8);
      A[I] := V - C * 256;
      If I < 31 Then A[I + 1] := A[I + 1] + C
      Else A[0] := A[0] + 38 * C;
    End;
End;

Procedure TlFeAdd(Var R : TlFe; Var A, B : TlFe);
Var I : LongInt;
Begin
  For I := 0 To 31 Do R[I] := A[I] + B[I];
  TlFeCarry(R);
End;

Procedure TlFeSub(Var R : TlFe; Var A, B : TlFe);
Var I : LongInt;
Begin
  For I := 0 To 31 Do R[I] := A[I] - B[I];
  TlFeCarry(R);
End;

Procedure TlFeMul(Var R : TlFe; Var A, B : TlFe);
Var T : Array[0..63] Of LongInt; I, J, X : LongInt;
Begin
  For I := 0 To 63 Do T[I] := 0;
  For I := 0 To 31 Do
  Begin
    X := A[I];
    If X <> 0 Then
      For J := 0 To 31 Do T[I + J] := T[I + J] + X * B[J];
  End;
  For I := 0 To 31 Do R[I] := T[I] + 38 * T[I + 32];
  TlFeCarry(R);
End;

Procedure TlFeMulK(Var R : TlFe; Var A : TlFe; K : LongInt);
Var I : LongInt;
Begin
  For I := 0 To 31 Do R[I] := A[I] * K;
  TlFeCarry(R);
End;

Procedure TlFeSwap(Var A, B : TlFe; S : LongInt);
Var I, T, M : LongInt;
Begin
  M := -S;
  For I := 0 To 31 Do
  Begin
    T := M And (A[I] Xor B[I]);
    A[I] := A[I] Xor T; B[I] := B[I] Xor T;
  End;
End;

Procedure TlFeInv(Var R : TlFe; Var A : TlFe);
Var C, T : TlFe; I : LongInt;
Begin
  C := A;
  For I := 253 DownTo 0 Do
  Begin
    TlFeMul(T, C, C); C := T;
    If (I <> 2) And (I <> 4) Then Begin TlFeMul(T, C, A); C := T; End;
  End;
  R := C;
End;

{ valeur canonique (0..p-1) en 32 octets }
Procedure TlFePack(Var A : TlFe; Var O : TlKey32);
Var T : TlFe; I, K, B, V : LongInt;
Begin
  TlFeCarry(A); TlFeCarry(A);
  For K := 1 To 2 Do
  Begin
    B := 0;
    For I := 0 To 31 Do
    Begin
      If I = 0 Then V := A[0] - $ED
      Else If I = 31 Then V := A[31] - $7F
      Else V := A[I] - $FF;
      V := V - B;
      If V < 0 Then Begin V := V + 256; B := 1; End Else B := 0;
      T[I] := V;
    End;
    If B = 0 Then A := T;
  End;
  For I := 0 To 31 Do O[I] := A[I] And 255;
End;

{ Out := X25519(K, U) ; tableaux de 32 octets }
Procedure TlX25519(Var Out0, K, U : TlKey32);
Var X1, X2, Z2, X3, Z3, A, AA, B, BB, E, C, D, DA, CB, T : TlFe;
    E0 : Array[0..31] Of Byte; I, Bit, Sw : LongInt;
Begin
  For I := 0 To 31 Do E0[I] := K[I];
  E0[0] := E0[0] And 248; E0[31] := (E0[31] And 127) Or 64;
  For I := 0 To 31 Do
  Begin
    X1[I] := U[I]; X2[I] := 0; Z2[I] := 0; Z3[I] := 0;
  End;
  X1[31] := X1[31] And 127;
  X2[0] := 1; Z3[0] := 1; X3 := X1;
  Sw := 0;
  For I := 254 DownTo 0 Do
  Begin
    Bit := (E0[I Shr 3] Shr (I And 7)) And 1;
    Sw := Sw Xor Bit;
    TlFeSwap(X2, X3, Sw); TlFeSwap(Z2, Z3, Sw);
    Sw := Bit;
    TlFeAdd(A, X2, Z2); TlFeMul(AA, A, A);
    TlFeSub(B, X2, Z2); TlFeMul(BB, B, B);
    TlFeSub(E, AA, BB);
    TlFeAdd(C, X3, Z3); TlFeSub(D, X3, Z3);
    TlFeMul(DA, D, A); TlFeMul(CB, C, B);
    TlFeAdd(T, DA, CB); TlFeMul(X3, T, T);
    TlFeSub(T, DA, CB); TlFeMul(D, T, T); TlFeMul(Z3, X1, D);
    TlFeMul(X2, AA, BB);
    TlFeMulK(T, E, 121665); TlFeAdd(T, AA, T); TlFeMul(Z2, E, T);
  End;
  TlFeSwap(X2, X3, Sw); TlFeSwap(Z2, Z3, Sw);
  TlFeInv(T, Z2); TlFeMul(A, X2, T);
  TlFePack(A, Out0);
End;

{ ---- TLS 1.2 client : ECDHE (x25519) + AES-128-GCM + SHA-256 ---- }
{ Suites TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (C02F) et              }
{ TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 (C02B). Le certificat du    }
{ serveur n'est pas verifie (Pasdows n'a pas de magasin de            }
{ certificats racines) : la connexion est chiffree, pas authentifiee. }

Const
  TlMaxConn = 4;
  TlRecMax = 18500;                  { enregistrement chiffre + marge }
  TlHsMax = 65536;                   { messages de la poignee de main }

Type
  TlConn = Record
    Used, Tls, Enc, Dec, Eof : Boolean;
    Sock : LongInt;
    CAes, SAes : TlAes;
    CIv, SIv : TlBlk;
    CSeq, SSeq : LongInt;
    RB : Array[0..TlRecMax - 1] Of Byte;   { enregistrement recu }
    RPos, REnd : LongInt;                  { texte clair disponible }
    OB : Array[0..TlRecMax - 1] Of Byte;   { enregistrement a envoyer }
  End;

  PTlConn = ^TlConn;
  TlHsBuf = Array[0..TlHsMax - 1] Of Byte;
  PTlHsBuf = ^TlHsBuf;

Var
  TlC : Array[0..TlMaxConn - 1] Of PTlConn;  { alloues au premier usage }
  TlHs : PTlHsBuf;
  TlHsLen : LongInt;
  TlErr : String;
  TlPool : TlSha;
  TlPoolN : LongInt;

{ ---- aleas : SHA-256 d'un compteur et des evenements du systeme ---- }

Procedure TlSeed(V : LongInt);
Begin
  If TlPoolN = 0 Then TlShaInit(TlPool);
  Inc(TlPoolN);
  TlShaByte(TlPool, V); TlShaByte(TlPool, V Shr 8);
  TlShaByte(TlPool, V Shr 16); TlShaByte(TlPool, V Shr 24);
End;

Procedure TlRandom(A : TlPtr; N : LongInt);
Var C : TlSha; H : TlKey32; I, K : LongInt;
Begin
  TlEntropy;
  K := 0;
  While K < N Do
  Begin
    TlSeed(K);
    C := TlPool;
    TlShaDone(C, TlPtr(@H[0]));
    I := 0;
    While (I < 32) And (K < N) Do
    Begin
      TlPut(A + K, H[I]); Inc(I); Inc(K);
    End;
  End;
End;

{ ---- envoi et reception d'enregistrements ---- }

Function TlSendAll(Var C : TlConn; A : TlPtr; N : LongInt) : Boolean;
Var R : LongInt;
Begin
  TlSendAll := False;
  While N > 0 Do
  Begin
    R := TlSockSend(C.Sock, A, N);
    If R <= 0 Then Begin TlErr := 'envoi TCP impossible'; Exit; End;
    A := A + R; N := N - R;
  End;
  TlSendAll := True;
End;

Function TlRecvAll(Var C : TlConn; A : TlPtr; N : LongInt) : Boolean;
Var R : LongInt;
Begin
  TlRecvAll := False;
  While N > 0 Do
  Begin
    R := TlSockRecv(C.Sock, A, N);
    If R <= 0 Then Begin TlErr := 'connexion fermee'; Exit; End;
    A := A + R; N := N - R;
  End;
  TlRecvAll := True;
End;

Procedure TlSeqBytes(Seq : LongInt; Var B : TlBlk; Ofs : LongInt);
Begin
  B[Ofs] := 0; B[Ofs + 1] := 0; B[Ofs + 2] := 0; B[Ofs + 3] := 0;
  B[Ofs + 4] := (Seq Shr 24) And 255; B[Ofs + 5] := (Seq Shr 16) And 255;
  B[Ofs + 6] := (Seq Shr 8) And 255; B[Ofs + 7] := Seq And 255;
End;

{ envoie un enregistrement de type Typ (N octets a l'adresse A) }
Function TlSendRec(Var C : TlConn; Typ : LongInt; A : TlPtr;
  N : LongInt) : Boolean;
Var Iv, Aad, Tag : TlBlk; I, L : LongInt; P : TlPtr;
Begin
  P := TlPtr(@C.OB[0]);
  C.OB[0] := Typ; C.OB[1] := 3; C.OB[2] := 3;
  If C.Enc Then
  Begin
    For I := 0 To N - 1 Do C.OB[13 + I] := TlGet(A + I);
    For I := 0 To 3 Do Iv[I] := C.CIv[I];
    TlSeqBytes(C.CSeq, Iv, 4);
    For I := 0 To 7 Do C.OB[5 + I] := Iv[4 + I];
    TlSeqBytes(C.CSeq, Aad, 0);
    Aad[8] := Typ; Aad[9] := 3; Aad[10] := 3;
    Aad[11] := (N Shr 8) And 255; Aad[12] := N And 255;
    TlGcm(C.CAes, Iv, Aad, 13, P + 13, N, True, Tag);
    For I := 0 To 15 Do C.OB[13 + N + I] := Tag[I];
    Inc(C.CSeq);
    L := N + 24;
  End
  Else
  Begin
    For I := 0 To N - 1 Do C.OB[5 + I] := TlGet(A + I);
    L := N;
  End;
  C.OB[3] := (L Shr 8) And 255; C.OB[4] := L And 255;
  TlSendRec := TlSendAll(C, P, L + 5);
End;

{ lit un enregistrement : type rendu, texte clair dans RB[RPos..REnd) ;
  -1 en cas d'erreur }
Function TlRecvRec(Var C : TlConn) : LongInt;
Var Typ, L, I : LongInt; Iv, Aad, Tag : TlBlk; P : TlPtr;
Begin
  TlRecvRec := -1;
  P := TlPtr(@C.RB[0]);
  If Not TlRecvAll(C, P, 5) Then Exit;
  Typ := C.RB[0];
  L := (C.RB[3] Shl 8) Or C.RB[4];
  If (L > TlRecMax - 5) Or (C.RB[1] <> 3) Then
  Begin
    TlErr := 'enregistrement TLS invalide'; Exit;
  End;
  If Not TlRecvAll(C, P + 5, L) Then Exit;
  C.RPos := 5; C.REnd := 5 + L;
  If C.Dec Then
  Begin
    If L < 24 Then Begin TlErr := 'enregistrement trop court'; Exit; End;
    For I := 0 To 3 Do Iv[I] := C.SIv[I];
    For I := 0 To 7 Do Iv[4 + I] := C.RB[5 + I];
    L := L - 24;
    TlSeqBytes(C.SSeq, Aad, 0);
    Aad[8] := Typ; Aad[9] := 3; Aad[10] := 3;
    Aad[11] := (L Shr 8) And 255; Aad[12] := L And 255;
    TlGcm(C.SAes, Iv, Aad, 13, P + 13, L, False, Tag);
    For I := 0 To 15 Do
      If Tag[I] <> C.RB[13 + L + I] Then
      Begin
        TlErr := 'enregistrement TLS altere (GCM)'; Exit;
      End;
    Inc(C.SSeq);
    C.RPos := 13; C.REnd := 13 + L;
  End;
  If Typ = 21 Then
  Begin
    If (C.REnd - C.RPos >= 2) And (C.RB[C.RPos + 1] = 0) Then
    Begin
      C.Eof := True; C.RPos := C.REnd; TlRecvRec := 23; Exit;
    End;
    Str(C.RB[C.RPos + 1], TlErr);
    TlErr := 'alerte TLS ' + TlErr;
    Exit;
  End;
  TlRecvRec := Typ;
End;

{ ---- poignee de main ---- }

{ message de la poignee de main suivant : type, corps dans TlHs^[4..] }
Function TlNextHs(Var C : TlConn; Var Tr : TlSha; Var Body : LongInt)
  : LongInt;
Var Typ, L, I : LongInt;
Begin
  TlNextHs := -1;
  { completer TlHs avec les enregistrements de type 22 }
  While True Do
  Begin
    If TlHsLen >= 4 Then
    Begin
      L := (TlHs^[1] Shl 16) Or (TlHs^[2] Shl 8) Or TlHs^[3];
      If L + 4 > TlHsMax Then Begin TlErr := 'message trop long'; Exit; End;
      If TlHsLen >= L + 4 Then Break;
    End;
    If C.RPos >= C.REnd Then
    Begin
      Typ := TlRecvRec(C);
      If Typ < 0 Then Exit;
      If Typ <> 22 Then Begin TlErr := 'message inattendu'; Exit; End;
    End;
    While (C.RPos < C.REnd) And (TlHsLen < TlHsMax) Do
    Begin
      TlHs^[TlHsLen] := C.RB[C.RPos]; Inc(TlHsLen); Inc(C.RPos);
    End;
  End;
  Typ := TlHs^[0];
  Body := L;
  TlShaAdd(Tr, TlPtr(@TlHs^[0]), L + 4);
  TlNextHs := Typ;
End;

{ retire le message traite de TlHs }
Procedure TlDropHs;
Var L, I : LongInt;
Begin
  L := ((TlHs^[1] Shl 16) Or (TlHs^[2] Shl 8) Or TlHs^[3]) + 4;
  For I := L To TlHsLen - 1 Do TlHs^[I - L] := TlHs^[I];
  TlHsLen := TlHsLen - L;
End;

Function TlHandshake(Var C : TlConn; Host : String) : Boolean;
Var M : Array[0..511] Of Byte; N, I, L, Typ, Body, Suite, P : LongInt;
    Tr, T2 : TlSha; CR, SR, Priv, Pub, SPub, Pms : TlKey32;
    Ms : Array[0..47] Of Byte; Kb : Array[0..39] Of Byte;
    Seed : Array[0..63] Of Byte; Hh : TlKey32; Key : TlBlk;
    GotKey : Boolean;

  Procedure B(V : LongInt);
  Begin
    M[N] := V And 255; Inc(N);
  End;

  Procedure W(V : LongInt);
  Begin
    B(V Shr 8); B(V);
  End;

Begin
  TlHandshake := False;
  C.Enc := False; C.Dec := False; C.CSeq := 0; C.SSeq := 0;
  C.RPos := 0; C.REnd := 0; C.Eof := False;
  TlHsLen := 0;
  TlRandom(TlPtr(@CR[0]), 32);
  TlRandom(TlPtr(@Priv[0]), 32);
  { ClientHello }
  N := 0;
  B(1); B(0); B(0); B(0);
  B(3); B(3);
  For I := 0 To 31 Do B(CR[I]);
  B(0);
  W(6); W($C02F); W($C02B); W($00FF);
  B(1); B(0);
  L := N; W(0);                      { longueur des extensions }
  { nom du serveur (SNI), pas pour une adresse IP }
  If Not TlIsIp(Host) Then
  Begin
    W(0); W(Length(Host) + 5); W(Length(Host) + 3); B(0);
    W(Length(Host));
    For I := 1 To Length(Host) Do B(Ord(Host[I]));
  End;
  W($000A); W(6); W(4); W($001D); W($0017);
  W($000B); W(2); B(1); B(0);
  W($000D); W(22); W(20);
  W($0401); W($0501); W($0601); W($0403); W($0503); W($0603);
  W($0804); W($0805); W($0806); W($0201);
  M[L] := ((N - L - 2) Shr 8) And 255; M[L + 1] := (N - L - 2) And 255;
  M[1] := 0; M[2] := ((N - 4) Shr 8) And 255; M[3] := (N - 4) And 255;
  TlShaInit(Tr);
  TlShaAdd(Tr, TlPtr(@M[0]), N);
  If Not TlSendRec(C, 22, TlPtr(@M[0]), N) Then Exit;
  { ServerHello ... ServerHelloDone }
  GotKey := False; Suite := 0;
  Repeat
    Typ := TlNextHs(C, Tr, Body);
    If Typ < 0 Then Exit;
    If Typ = 2 Then
    Begin
      If (TlHs^[4] <> 3) Or (TlHs^[5] <> 3) Then
      Begin
        TlErr := 'le serveur refuse TLS 1.2'; Exit;
      End;
      For I := 0 To 31 Do SR[I] := TlHs^[6 + I];
      P := 38 + TlHs^[38] + 1;
      Suite := (TlHs^[P] Shl 8) Or TlHs^[P + 1];
      If (Suite <> $C02F) And (Suite <> $C02B) Then
      Begin
        TlErr := 'suite de chiffrement non prise en charge'; Exit;
      End;
    End
    Else If Typ = 12 Then
    Begin
      If (TlHs^[4] <> 3) Or (TlHs^[5] <> 0) Or (TlHs^[6] <> $1D) Or
         (TlHs^[7] <> 32) Then
      Begin
        TlErr := 'courbe x25519 refusee par le serveur'; Exit;
      End;
      For I := 0 To 31 Do SPub[I] := TlHs^[8 + I];
      GotKey := True;
    End
    Else If Typ = 11 Then
    Begin
      { premier certificat (cle publique du serveur pour CredSSP) }
      L := (TlHs^[7] Shl 16) Or (TlHs^[8] Shl 8) Or TlHs^[9];
      If L > SizeOf(TlCert) Then L := SizeOf(TlCert);
      For I := 0 To L - 1 Do TlCert[I] := TlHs^[10 + I];
      TlCertLen := L;
    End
    Else If Typ = 13 Then
    Begin
      TlErr := 'certificat client demande'; Exit;
    End;
    TlDropHs;
  Until Typ = 14;
  If (Suite = 0) Or Not GotKey Then
  Begin
    TlErr := 'poignee de main incomplete'; Exit;
  End;
  { ClientKeyExchange, cles }
  For I := 0 To 31 Do Pub[I] := 0;
  Pub[0] := 9;
  TlX25519(Pub, Priv, Pub);
  TlX25519(Pms, Priv, SPub);
  N := 0;
  B(16); B(0); B(0); B(33); B(32);
  For I := 0 To 31 Do B(Pub[I]);
  TlShaAdd(Tr, TlPtr(@M[0]), N);
  If Not TlSendRec(C, 22, TlPtr(@M[0]), N) Then Exit;
  For I := 0 To 31 Do
  Begin
    Seed[I] := CR[I]; Seed[32 + I] := SR[I];
  End;
  TlPrf(TlPtr(@Pms[0]), 32, 'master secret', TlPtr(@Seed[0]), 64,
        TlPtr(@Ms[0]), 48);
  For I := 0 To 31 Do
  Begin
    Seed[I] := SR[I]; Seed[32 + I] := CR[I];
  End;
  TlPrf(TlPtr(@Ms[0]), 48, 'key expansion', TlPtr(@Seed[0]), 64,
        TlPtr(@Kb[0]), 40);
  For I := 0 To 15 Do Key[I] := Kb[I];
  TlAesKey(C.CAes, Key);
  For I := 0 To 15 Do Key[I] := Kb[16 + I];
  TlAesKey(C.SAes, Key);
  For I := 0 To 3 Do
  Begin
    C.CIv[I] := Kb[32 + I]; C.SIv[I] := Kb[36 + I];
  End;
  { ChangeCipherSpec et Finished }
  M[0] := 1;
  If Not TlSendRec(C, 20, TlPtr(@M[0]), 1) Then Exit;
  C.Enc := True;
  T2 := Tr; TlShaDone(T2, TlPtr(@Hh[0]));
  M[0] := 20; M[1] := 0; M[2] := 0; M[3] := 12;
  TlPrf(TlPtr(@Ms[0]), 48, 'client finished', TlPtr(@Hh[0]), 32,
        TlPtr(@M[4]), 12);
  TlShaAdd(Tr, TlPtr(@M[0]), 16);
  If Not TlSendRec(C, 22, TlPtr(@M[0]), 16) Then Exit;
  { ChangeCipherSpec et Finished du serveur }
  Repeat
    Typ := TlRecvRec(C);
    If Typ < 0 Then Exit;
    If Typ = 22 Then
    Begin
      { NewSessionTicket eventuel avant le ChangeCipherSpec }
      C.RPos := C.REnd;
    End
    Else If Typ <> 20 Then Begin TlErr := 'ChangeCipherSpec attendu'; Exit;
    End;
  Until Typ = 20;
  C.Dec := True;
  C.RPos := C.REnd;
  T2 := Tr; TlShaDone(T2, TlPtr(@Hh[0]));
  TlPrf(TlPtr(@Ms[0]), 48, 'server finished', TlPtr(@Hh[0]), 32,
        TlPtr(@M[100]), 12);
  TlHsLen := 0;
  Typ := TlNextHs(C, T2, Body);
  If (Typ <> 20) Or (Body <> 12) Then
  Begin
    If Typ >= 0 Then TlErr := 'Finished du serveur attendu';
    Exit;
  End;
  For I := 0 To 11 Do
    If TlHs^[4 + I] <> M[100 + I] Then
    Begin
      TlErr := 'Finished du serveur invalide'; Exit;
    End;
  TlHandshake := True;
End;

{ ---- donnees de l'application ---- }

{ lit au plus N octets ; 0 a la fin, -1 en cas d'erreur }
Function TlRead(Var C : TlConn; A : TlPtr; N : LongInt) : LongInt;
Var Typ, K : LongInt;
Begin
  TlRead := -1;
  If Not C.Tls Then
  Begin
    TlRead := TlSockRecv(C.Sock, A, N);
    Exit;
  End;
  While C.RPos >= C.REnd Do
  Begin
    If C.Eof Then Begin TlRead := 0; Exit; End;
    Typ := TlRecvRec(C);
    If Typ < 0 Then
    Begin
      { fermeture TCP sans close_notify : fin des donnees }
      If TlErr = 'connexion fermee' Then TlRead := 0;
      Exit;
    End;
    If Typ <> 23 Then C.RPos := C.REnd;
  End;
  K := C.REnd - C.RPos;
  If K > N Then K := N;
  For Typ := 0 To K - 1 Do TlPut(A + Typ, C.RB[C.RPos + Typ]);
  C.RPos := C.RPos + K;
  TlRead := K;
End;

Function TlWrite(Var C : TlConn; A : TlPtr; N : LongInt) : Boolean;
Var K : LongInt;
Begin
  TlWrite := False;
  If Not C.Tls Then
  Begin
    TlWrite := TlSendAll(C, A, N); Exit;
  End;
  While N > 0 Do
  Begin
    K := N; If K > 16384 Then K := 16384;
    If Not TlSendRec(C, 23, A, K) Then Exit;
    A := A + K; N := N - K;
  End;
  TlWrite := True;
End;

Const
  Md5K : Array[0..63] Of LongWord = (
    $D76AA478, $E8C7B756, $242070DB, $C1BDCEEE, $F57C0FAF, $4787C62A,
    $A8304613, $FD469501, $698098D8, $8B44F7AF, $FFFF5BB1, $895CD7BE,
    $6B901122, $FD987193, $A679438E, $49B40821, $F61E2562, $C040B340,
    $265E5A51, $E9B6C7AA, $D62F105D, $02441453, $D8A1E681, $E7D3FBC8,
    $21E1CDE6, $C33707D6, $F4D50D87, $455A14ED, $A9E3E905, $FCEFA3F8,
    $676F02D9, $8D2A4C8A, $FFFA3942, $8771F681, $6D9D6122, $FDE5380C,
    $A4BEEA44, $4BDECFA9, $F6BB4B60, $BEBFBC70, $289B7EC6, $EAA127FA,
    $D4EF3085, $04881D05, $D9D4D039, $E6DB99E5, $1FA27CF8, $C4AC5665,
    $F4292244, $432AFF97, $AB9423A7, $FC93A039, $655B59C3, $8F0CCC92,
    $FFEFF47D, $85845DD1, $6FA87E4F, $FE2CE6E0, $A3014314, $4E0811A1,
    $F7537E82, $BD3AF235, $2AD7D2BB, $EB86D391);
  Md5S : Array[0..15] Of Byte = (7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16,
    23, 6, 10, 15, 21);
  Md4S : Array[0..11] Of Byte = (3, 7, 11, 19, 3, 5, 9, 13, 3, 9, 11, 15);
  Md4K2 : Array[0..15] Of Byte = (0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14,
    3, 7, 11, 15);
  Md4K3 : Array[0..15] Of Byte = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13,
    3, 11, 7, 15);
  { SPNEGO : OID de SPNEGO puis mechTypes (NTLMSSP) }
  SpnOid : Array[0..7] Of Byte = ($06, $06, $2B, $06, $01, $05, $05, $02);
  SpnMech : Array[0..15] Of Byte = ($A0, $0E, $30, $0C, $06, $0A, $2B,
    $06, $01, $04, $01, $82, $37, $02, $02, $0A);

Type
  TMd = Record
    H : Array[0..3] Of LongInt;
    B : Array[0..63] Of Byte;
    N, Len : LongInt;
    Four : Boolean;                  { MD4 (sinon MD5) }
  End;

{ ---- MD4 et MD5 (RFC 1320 et 1321) ---- }

Function MdRol(X, N : LongInt) : LongInt;
Begin
  MdRol := (X Shl N) Or (X Shr (32 - N));
End;

Procedure MdBlock(Var C : TMd);
Var M : Array[0..15] Of LongInt; X : Array[0..3] Of LongInt;
    I, T, A, B, Cc, D, F, G, S : LongInt;
Begin
  For I := 0 To 15 Do
    M[I] := C.B[I * 4] Or (C.B[I * 4 + 1] Shl 8) Or (C.B[I * 4 + 2] Shl 16)
            Or (C.B[I * 4 + 3] Shl 24);
  For I := 0 To 3 Do X[I] := C.H[I];
  If C.Four Then
    For I := 0 To 47 Do
    Begin
      T := (4 - (I And 3)) And 3;
      A := X[T]; B := X[(T + 1) And 3]; Cc := X[(T + 2) And 3];
      D := X[(T + 3) And 3];
      If I < 16 Then
      Begin
        F := (B And Cc) Or ((Not B) And D); G := I; S := Md4S[I And 3];
      End
      Else If I < 32 Then
      Begin
        F := (B And Cc) Or (B And D) Or (Cc And D);
        F := F + $5A827999; G := Md4K2[I - 16]; S := Md4S[4 + (I And 3)];
      End
      Else
      Begin
        F := (B Xor Cc Xor D) + LongInt($6ED9EBA1); G := Md4K3[I - 32];
        S := Md4S[8 + (I And 3)];
      End;
      X[T] := MdRol(A + F + M[G], S);
    End
  Else
    For I := 0 To 63 Do
    Begin
      T := (4 - (I And 3)) And 3;
      A := X[T]; B := X[(T + 1) And 3]; Cc := X[(T + 2) And 3];
      D := X[(T + 3) And 3];
      If I < 16 Then
      Begin
        F := (B And Cc) Or ((Not B) And D); G := I;
      End
      Else If I < 32 Then
      Begin
        F := (D And B) Or ((Not D) And Cc); G := (5 * I + 1) And 15;
      End
      Else If I < 48 Then
      Begin
        F := B Xor Cc Xor D; G := (3 * I + 5) And 15;
      End
      Else
      Begin
        F := Cc Xor (B Or (Not D)); G := (7 * I) And 15;
      End;
      X[T] := B + MdRol(A + F + LongInt(Md5K[I]) + M[G],
                        Md5S[(I Shr 4) * 4 + (I And 3)]);
    End;
  For I := 0 To 3 Do C.H[I] := C.H[I] + X[I];
End;

Procedure MdInit(Var C : TMd; Four : Boolean);
Begin
  C.H[0] := $67452301; C.H[1] := LongInt($EFCDAB89);
  C.H[2] := LongInt($98BADCFE); C.H[3] := $10325476;
  C.N := 0; C.Len := 0; C.Four := Four;
End;

Procedure MdAdd(Var C : TMd; A, N : LongInt);
Var I : LongInt;
Begin
  For I := 0 To N - 1 Do
  Begin
    C.B[C.N] := GB(A + I);
    Inc(C.N);
    If C.N = 64 Then
    Begin
      MdBlock(C);
      C.N := 0;
    End;
  End;
  C.Len := C.Len + N;
End;

Procedure MdDone(Var C : TMd; Out0 : LongInt);
Var Z : Array[0..7] Of Byte; L, I : LongInt;
Begin
  L := C.Len;
  Z[0] := $80;
  MdAdd(C, LongInt(@Z[0]), 1);
  Z[0] := 0;
  While C.N <> 56 Do MdAdd(C, LongInt(@Z[0]), 1);
  Z[0] := (L Shl 3) And 255; Z[1] := (L Shr 5) And 255;
  Z[2] := (L Shr 13) And 255; Z[3] := (L Shr 21) And 255;
  Z[4] := (L Shr 29) And 7; Z[5] := 0; Z[6] := 0; Z[7] := 0;
  MdAdd(C, LongInt(@Z[0]), 8);
  For I := 0 To 3 Do SL(Out0 + I * 4, C.H[I]);
End;

{ HMAC-MD5 (cle de 64 octets au plus) de Msg puis Msg2 }
Procedure HmacMd5(Key, KLen, Msg, MLen, Msg2, M2Len, Out0 : LongInt);
Var C : TMd; Pad : Array[0..63] Of Byte; In0 : Array[0..15] Of Byte;
    I : LongInt;
Begin
  For I := 0 To 63 Do
    If I < KLen Then Pad[I] := GB(Key + I) Xor $36 Else Pad[I] := $36;
  MdInit(C, False);
  MdAdd(C, LongInt(@Pad[0]), 64);
  MdAdd(C, Msg, MLen);
  If M2Len > 0 Then MdAdd(C, Msg2, M2Len);
  MdDone(C, LongInt(@In0[0]));
  For I := 0 To 63 Do Pad[I] := Pad[I] Xor ($36 Xor $5C);
  MdInit(C, False);
  MdAdd(C, LongInt(@Pad[0]), 64);
  MdAdd(C, LongInt(@In0[0]), 16);
  MdDone(C, Out0);
End;

{ Chaine (Latin-1) en UTF-16LE en A ; octets ecrits }
Function Uni16(A : LongInt; S : String) : LongInt;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do SW(A + (I - 1) * 2, Ord(S[I]));
  Uni16 := Length(S) * 2;
End;

{ Hachage NT : MD4 du mot de passe en UTF-16LE }
Procedure NtHash(Pw : String; Out0 : LongInt);
Var C : TMd; B : Array[0..511] Of Byte; N : LongInt;
Begin
  N := Uni16(LongInt(@B[0]), Pw);
  MdInit(C, True);
  MdAdd(C, LongInt(@B[0]), N);
  MdDone(C, Out0);
End;


{ ---- RC4 (scellement NTLM) ---- }

Type
  TRc4 = Record
    S : Array[0..255] Of Byte;
    I, J : LongInt;
  End;

Procedure Rc4Init(Var R : TRc4; Key, N : LongInt);
Var I, J, T : LongInt;
Begin
  For I := 0 To 255 Do R.S[I] := I;
  J := 0;
  For I := 0 To 255 Do
  Begin
    J := (J + R.S[I] + GB(Key + I Mod N)) And 255;
    T := R.S[I]; R.S[I] := R.S[J]; R.S[J] := T;
  End;
  R.I := 0; R.J := 0;
End;

Procedure Rc4(Var R : TRc4; Src, Dst, N : LongInt);
Var K, T : LongInt;
Begin
  For K := 0 To N - 1 Do
  Begin
    R.I := (R.I + 1) And 255;
    R.J := (R.J + R.S[R.I]) And 255;
    T := R.S[R.I]; R.S[R.I] := R.S[R.J]; R.S[R.J] := T;
    SB(Dst + K, GB(Src + K) Xor R.S[(R.S[R.I] + R.S[R.J]) And 255]);
  End;
End;

Procedure Md5Of(A, N, Out0 : LongInt);
Var C : TMd;
Begin
  MdInit(C, False);
  MdAdd(C, A, N);
  MdDone(C, Out0);
End;

{ ==================================================================== }
{ NTLMv2 (avec signature et scellement) et CredSSP (MS-CSSP)            }
{ ==================================================================== }

Const
  { UNICODE, REQUEST_TARGET, SIGN, SEAL, NTLM, ALWAYS_SIGN,
    EXTENDED_SESSIONSECURITY, TARGET_INFO, 128, KEY_EXCH, 56 }
  NtlmCFlags = LongInt($E0888235);

Var
  NtUser, NtDom, NtPass : String;
  NtKeyX : Array[0..15] Of Byte;          { ExportedSessionKey }
  NtSignK : Array[0..15] Of Byte;         { client -> serveur }
  NtSeal : TRc4;
  NtSeq : LongInt;
  Wk1, Wk2, Wk3 : LongInt;                { tampons de travail (16 Ko) }

{ Tag, longueur DER puis N octets de Src en Dst ; octets ecrits }
Function DerWrap(Tag, Src, N, Dst : LongInt) : LongInt;
Var H : LongInt;
Begin
  SB(Dst, Tag);
  If N < 128 Then
  Begin
    SB(Dst + 1, N); H := 2;
  End
  Else If N < 256 Then
  Begin
    SB(Dst + 1, $81); SB(Dst + 2, N); H := 3;
  End
  Else
  Begin
    SB(Dst + 1, $82); SB(Dst + 2, N Shr 8); SB(Dst + 3, N); H := 4;
  End;
  MoveB(Src, Dst + H, N);
  DerWrap := H + N;
End;

{ Longueur DER en A : valeur ; Hl : octets de l'entete (tag compris) }
Function DerLen(A : LongInt; Var Hl : LongInt) : LongInt;
Var L, K, I : LongInt;
Begin
  L := GB(A + 1);
  Hl := 2;
  If L >= $80 Then
  Begin
    K := L And $7F; L := 0;
    For I := 1 To K Do L := (L Shl 8) Or GB(A + 1 + I);
    Hl := 2 + K;
  End;
  DerLen := L;
End;

Function NtlmFind(A, N : LongInt) : LongInt;
Var I : LongInt;
Begin
  NtlmFind := 0;
  For I := 0 To N - 8 Do
    If (GL(A + I) = $4D4C544E) And (GL(A + I + 4) = $00505353) Then
    Begin
      NtlmFind := A + I;
      Exit;
    End;
End;

Procedure NtlmField(M, F, Len, Ofs : LongInt);
Begin
  SW(M + F, Len); SW(M + F + 2, Len); SL(M + F + 4, Ofs);
End;

Function NtlmNegotiate(Dst : LongInt) : LongInt;
Begin
  ZeroB(Dst, 32);
  SL(Dst, $4D4C544E); SL(Dst + 4, $00505353);
  SL(Dst + 8, 1); SL(Dst + 12, NtlmCFlags);
  NtlmNegotiate := 32;
End;

{ cle derivee : MD5(cle exportee + constante + 0) }
Procedure NtlmKey(Magic : String; Out0 : LongInt);
Var B : Array[0..99] Of Byte; K : LongInt;
Begin
  MoveB(LongInt(@NtKeyX[0]), LongInt(@B[0]), 16);
  For K := 1 To Length(Magic) Do B[15 + K] := Ord(Magic[K]);
  B[16 + Length(Magic)] := 0;
  Md5Of(LongInt(@B[0]), 17 + Length(Magic), Out0);
End;

{ AUTHENTICATE (NTLMv2) d'apres le CHALLENGE C ; octets ecrits en Dst }
Function NtlmAuth(C, CLen, Dst : LongInt) : LongInt;
Var TI, TLen, P, K, Q, Id, Ln, Tmp, TmpN, Fl : LongInt;
    NtV2, Proof, Base, Hash : Array[0..15] Of Byte; SealK : Array[0..15] Of Byte;
    Ts, Cc : Array[0..7] Of Byte; U : Array[0..299] Of Byte; Dom : String;
    R : TRc4;
Begin
  TLen := GW(C + 40); TI := C + GL(C + 44);
  If GL(C + 44) + TLen > CLen Then TLen := 0;
  Fl := NtlmCFlags And GL(C + 20);
  Dom := NtDom;
  If Dom = '' Then
  Begin
    K := GW(C + 12); Q := C + GL(C + 16);
    For P := 0 To MinI(K Div 2, 63) - 1 Do Dom := Dom + Chr(GB(Q + P * 2));
  End;
  { horodatage du serveur (MsvAvTimestamp) }
  ZeroB(LongInt(@Ts[0]), 8);
  P := 0;
  While P + 4 <= TLen Do
  Begin
    Id := GW(TI + P); Ln := GW(TI + P + 2);
    If Id = 0 Then Break;
    If (Id = 7) And (Ln = 8) Then MoveB(TI + P + 4, LongInt(@Ts[0]), 8);
    P := P + 4 + Ln;
  End;
  TlRandom(LongInt(@Cc[0]), 8);
  NtHash(NtPass, LongInt(@Hash[0]));
  K := Uni16(LongInt(@U[0]), UpS(NtUser));
  K := K + Uni16(LongInt(@U[K]), Dom);
  HmacMd5(LongInt(@Hash[0]), 16, LongInt(@U[0]), K, 0, 0, LongInt(@NtV2[0]));
  ZeroB(Dst, 64);
  SL(Dst, $4D4C544E); SL(Dst + 4, $00505353); SL(Dst + 8, 3);
  SL(Dst + 60, Fl);
  P := 64;
  K := Uni16(Dst + P, Dom); NtlmField(Dst, 28, K, P); P := P + K;
  K := Uni16(Dst + P, NtUser); NtlmField(Dst, 36, K, P); P := P + K;
  K := Uni16(Dst + P, 'PASDOWS'); NtlmField(Dst, 44, K, P); P := P + K;
  ZeroB(Dst + P, 24); NtlmField(Dst, 12, 24, P); P := P + 24;
  Tmp := Dst + P + 16;
  ZeroB(Tmp, 28);
  SB(Tmp, 1); SB(Tmp + 1, 1);
  MoveB(LongInt(@Ts[0]), Tmp + 8, 8);
  MoveB(LongInt(@Cc[0]), Tmp + 16, 8);
  MoveB(TI, Tmp + 28, TLen);
  ZeroB(Tmp + 28 + TLen, 4);
  TmpN := 32 + TLen;
  HmacMd5(LongInt(@NtV2[0]), 16, C + 24, 8, Tmp, TmpN, LongInt(@Proof[0]));
  MoveB(LongInt(@Proof[0]), Dst + P, 16);
  NtlmField(Dst, 20, 16 + TmpN, P); P := P + 16 + TmpN;
  { cle de session : SessionBaseKey ; avec KEY_EXCH, une cle aleatoire
    chiffree par RC4 (EncryptedRandomSessionKey) }
  HmacMd5(LongInt(@NtV2[0]), 16, LongInt(@Proof[0]), 16, 0, 0,
          LongInt(@Base[0]));
  If (Fl And $40000000) <> 0 Then
  Begin
    TlRandom(LongInt(@NtKeyX[0]), 16);
    Rc4Init(R, LongInt(@Base[0]), 16);
    Rc4(R, LongInt(@NtKeyX[0]), Dst + P, 16);
    NtlmField(Dst, 52, 16, P); P := P + 16;
  End
  Else
  Begin
    MoveB(LongInt(@Base[0]), LongInt(@NtKeyX[0]), 16);
    NtlmField(Dst, 52, 0, P);
  End;
  NtlmKey('session key to client-to-server signing key magic constant',
          LongInt(@NtSignK[0]));
  NtlmKey('session key to client-to-server sealing key magic constant',
          LongInt(@SealK[0]));
  Rc4Init(NtSeal, LongInt(@SealK[0]), 16);
  NtSeq := 0;
  NtlmAuth := P;
End;

{ Scellement (EncryptMessage) : signature de 16 octets puis le message
  chiffre ; octets ecrits en Dst }
Function NtlmSeal(Src, N, Dst : LongInt) : LongInt;
Var Mac : Array[0..15] Of Byte; Sq : Array[0..3] Of Byte;
    Chk : Array[0..7] Of Byte;
Begin
  SL(LongInt(@Sq[0]), NtSeq);
  HmacMd5(LongInt(@NtSignK[0]), 16, LongInt(@Sq[0]), 4, Src, N,
          LongInt(@Mac[0]));
  Rc4(NtSeal, Src, Dst + 16, N);
  Rc4(NtSeal, LongInt(@Mac[0]), LongInt(@Chk[0]), 8);
  SL(Dst, 1);
  MoveB(LongInt(@Chk[0]), Dst + 4, 8);
  SL(Dst + 12, NtSeq);
  Inc(NtSeq);
  NtlmSeal := N + 16;
End;

{ TSRequest (version 6) : jeton NTLM, authInfo, pubKeyAuth, clientNonce
  (N = 0 : absent) ; octets ecrits en Dst }
Function TsReq(Tok, TokN, Auth, AuthN, Pub, PubN, Nonce, NonceN,
               Dst : LongInt) : LongInt;
Var K, L : LongInt;
Begin
  K := 0;
  SB(Wk1, $A0); SB(Wk1 + 1, 3); SB(Wk1 + 2, 2); SB(Wk1 + 3, 1);
  SB(Wk1 + 4, 6);
  K := 5;
  If TokN > 0 Then
  Begin
    L := DerWrap($04, Tok, TokN, Wk2);
    L := DerWrap($A0, Wk2, L, Wk3);
    L := DerWrap($30, Wk3, L, Wk2);
    L := DerWrap($30, Wk2, L, Wk3);
    K := K + DerWrap($A1, Wk3, L, Wk1 + K);
  End;
  If AuthN > 0 Then
  Begin
    L := DerWrap($04, Auth, AuthN, Wk2);
    K := K + DerWrap($A2, Wk2, L, Wk1 + K);
  End;
  If PubN > 0 Then
  Begin
    L := DerWrap($04, Pub, PubN, Wk2);
    K := K + DerWrap($A3, Wk2, L, Wk1 + K);
  End;
  If NonceN > 0 Then
  Begin
    L := DerWrap($04, Nonce, NonceN, Wk2);
    K := K + DerWrap($A5, Wk2, L, Wk1 + K);
  End;
  TsReq := DerWrap($30, Wk1, K, Dst);
End;

{ Champ [Tag] de premier niveau d'un TSRequest (A, N) : adresse de son
  contenu, 0 s'il manque }
Function TsField(A, N, Tag : LongInt; Var FL : LongInt) : LongInt;
Var P, E, Hl, L : LongInt;
Begin
  TsField := 0;
  L := DerLen(A, Hl);
  P := A + Hl; E := A + Hl + L;
  If E > A + N Then E := A + N;
  While P < E Do
  Begin
    L := DerLen(P, Hl);
    If GB(P) = Tag Then
    Begin
      TsField := P + Hl; FL := L;
      Exit;
    End;
    P := P + Hl + L;
  End;
End;

{ Cle publique du certificat du serveur (subjectPublicKey sans l'octet
  des bits inutilises) : adresse et longueur }
Function CertPubKey(Var N : LongInt) : LongInt;
Var P, Hl, L, I, A : LongInt;
Begin
  CertPubKey := 0; N := 0;
  If TlCertLen < 32 Then Exit;
  A := LongInt(@TlCert[0]);
  L := DerLen(A, Hl);                     { Certificate }
  P := A + Hl;
  L := DerLen(P, Hl);                     { tbsCertificate }
  P := P + Hl;
  If GB(P) = $A0 Then                     { [0] version }
  Begin
    L := DerLen(P, Hl); P := P + Hl + L;
  End;
  { serialNumber, signature, issuer, validity, subject }
  For I := 1 To 5 Do
  Begin
    L := DerLen(P, Hl); P := P + Hl + L;
  End;
  L := DerLen(P, Hl);                     { subjectPublicKeyInfo }
  P := P + Hl;
  L := DerLen(P, Hl); P := P + Hl + L;    { algorithm }
  If GB(P) <> $03 Then Exit;              { BIT STRING }
  L := DerLen(P, Hl);
  CertPubKey := P + Hl + 1;
  N := L - 1;
End;

{ ==================================================================== }
{ Protocole RDP (MS-RDPBCGR) : X.224, MCS/GCC, CredSSP, activation,     }
{ mises a jour graphiques (bitmaps, RLE entrelace), entrees             }
{ ==================================================================== }

Var
  Tc : TlConn;
  RdpHost, RdpUser, RdpDom, RdpPass : String;
  RdpPort, KbdLay : LongInt;
  ReqW, ReqH : LongInt;                   { taille demandee }
  FbW, FbH, FbPitch, Fb : LongInt;        { ecran distant 16 bits, descendant }
  IoChan, UserChan, ShareId, SrvChan, Proto : LongInt;
  Tx, Rx, InB, Frag, FragLen, DecB, Pool, ViewX, ViewY : LongInt;
  SendCs : Array[0..15] Of LongInt;
  Active, Licensed, Connected, FirstAct : Boolean;
  ErrInfo : LongInt;
  RdpErr, RdpStatus : String;
  Pal565 : Array[0..255] Of LongInt;
  BmiH : Array[0..15] Of LongInt;         { BITMAPINFOHEADER + masques }
  SessWnd, DlgWnd : LongInt;
  DirtyL, DirtyT, DirtyR, DirtyB : LongInt;

Const
  WM_RDPSTATUS = $0401; WM_RDPACTIVE = $0402; WM_RDPEND = $0403;

Function HexS(V : LongInt) : String;
Const D : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 7 DownTo 0 Do S := S + D[((V Shr (I * 4)) And 15) + 1];
  HexS := S;
End;

Function PoolB(I : LongInt) : LongInt;
Begin
  PoolB := Pool + I * 16384;
End;

Procedure Status(S : String);
Begin
  RdpStatus := S;
  If DlgWnd <> 0 Then Dummy := PostMessageA(DlgWnd, WM_RDPSTATUS, 0, 0);
End;


{ ---- transport ---- }

Function SendRaw(A, N : LongInt) : Boolean;
Begin
  EnterCriticalSection(LongInt(@SendCs[0]));
  SendRaw := TlWrite(Tc, A, N);
  LeaveCriticalSection(LongInt(@SendCs[0]));
End;

Function RecvAll(A, N : LongInt) : Boolean;
Var R : LongInt;
Begin
  RecvAll := False;
  While N > 0 Do
  Begin
    R := TlRead(Tc, A, N);
    If R <= 0 Then Exit;
    A := A + R; N := N - R;
  End;
  RecvAll := True;
End;

{ PDU suivante dans Rx : 1 (TPKT), 2 (chemin rapide), 0 erreur ; Len :
  octets de la PDU entiere }
Function RecvPdu(Var Len : LongInt) : LongInt;
Var B, L : LongInt;
Begin
  RecvPdu := 0; Len := 0;
  If Not RecvAll(Rx, 1) Then Exit;
  B := GB(Rx);
  If B = 3 Then
  Begin
    If Not RecvAll(Rx + 1, 3) Then Exit;
    L := GWB(Rx + 2);
    If (L < 4) Or (L > 65535) Then Exit;
    If Not RecvAll(Rx + 4, L - 4) Then Exit;
    Len := L;
    RecvPdu := 1;
    Exit;
  End;
  If (B And 3) <> 0 Then Exit;
  If Not RecvAll(Rx + 1, 1) Then Exit;
  L := GB(Rx + 1);
  If (L And $80) <> 0 Then
  Begin
    If Not RecvAll(Rx + 2, 1) Then Exit;
    L := ((L And $7F) Shl 8) Or GB(Rx + 2);
    If Not RecvAll(Rx + 3, L - 3) Then Exit;
  End
  Else If Not RecvAll(Rx + 2, L - 2) Then Exit;
  Len := L;
  RecvPdu := 2;
End;

{ TPKT et X.224 (donnees) autour de N octets deja places en A + 7 }
Function SendTpkt(A, N : LongInt) : Boolean;
Begin
  SB(A, 3); SB(A + 1, 0); SWB(A + 2, N + 7);
  SB(A + 4, 2); SB(A + 5, $F0); SB(A + 6, $80);
  SendTpkt := SendRaw(A, N + 7);
End;

{ MCS Send Data Request vers Chan : le contenu (N octets) est en A + 15 }
Function SendMcs(A, Chan, N : LongInt) : Boolean;
Begin
  SB(A + 7, $64);
  SWB(A + 8, UserChan - 1001);
  SWB(A + 10, Chan);
  SB(A + 12, $70);
  SB(A + 13, $80 Or ((N Shr 8) And $7F)); SB(A + 14, N And 255);
  SendMcs := SendTpkt(A, N + 8);
End;

{ PDU de donnees (Share Data) de type Typ2 : contenu de N octets en
  Tx + 33 }
Function SendData(Typ2, N : LongInt) : Boolean;
Var P : LongInt;
Begin
  P := Tx + 15;
  SW(P, N + 18); SW(P + 2, $17); SW(P + 4, UserChan);
  SL(P + 6, ShareId); SB(P + 10, 0); SB(P + 11, 1);
  SW(P + 12, N + 4); SB(P + 14, Typ2); SB(P + 15, 0); SW(P + 16, 0);
  SendData := SendMcs(Tx, IoChan, N + 18);
End;


{ ---- CredSSP (NLA) ---- }

Function RecvTs(Dst : LongInt) : LongInt;
Var L, K, I : LongInt;
Begin
  RecvTs := 0;
  If Not RecvAll(Dst, 2) Then Exit;
  L := GB(Dst + 1); K := 0;
  If (L And $80) <> 0 Then
  Begin
    K := L And $7F;
    If (K < 1) Or (K > 3) Then Exit;
    If Not RecvAll(Dst + 2, K) Then Exit;
    L := 0;
    For I := 0 To K - 1 Do L := (L Shl 8) Or GB(Dst + 2 + I);
  End;
  If L > 16000 Then Exit;
  If Not RecvAll(Dst + 2 + K, L) Then Exit;
  RecvTs := L + 2 + K;
End;

{ errorCode d'un TSRequest (0 : aucun) }
Function TsError(A, N : LongInt) : LongInt;
Var P, L, V, I : LongInt;
Begin
  TsError := 0;
  P := TsField(A, N, $A4, L);
  If (P = 0) Or (GB(P) <> 2) Then Exit;
  V := 0;
  For I := 1 To GB(P + 1) Do V := (V Shl 8) Or GB(P + 1 + I);
  TsError := V;
End;

Function CredSsp : Boolean;
Var Tok, Chal, Seal, Msg, CrA, CrB, CrC, K, L, S, Ver, P, FL, PK, PN,
    E : LongInt;
    Nonce : Array[0..31] Of Byte; Hash : Array[0..31] Of Byte;
    Sh : TlSha; Mag : String;
Begin
  CredSsp := False;
  Tok := PoolB(0); Chal := PoolB(1); Seal := PoolB(2); Msg := PoolB(3);
  CrA := PoolB(4); CrB := PoolB(5); CrC := PoolB(6);
  NtUser := RdpUser; NtDom := RdpDom; NtPass := RdpPass;
  { NEGOTIATE }
  K := NtlmNegotiate(Tok);
  L := TsReq(Tok, K, 0, 0, 0, 0, 0, 0, Msg);
  If Not SendRaw(Msg, L) Then Exit;
  { CHALLENGE }
  L := RecvTs(Msg);
  If L = 0 Then
  Begin
    RdpErr := 'Le serveur a ferm'#233' la connexion (CredSSP).';
    Exit;
  End;
  E := TsError(Msg, L);
  P := TsField(Msg, L, $A0, FL);
  Ver := 2;
  If (P <> 0) And (GB(P) = 2) Then Ver := GB(P + 1 + GB(P + 1));
  P := NtlmFind(Msg, L);
  If (P = 0) Or (E <> 0) Then
  Begin
    RdpErr := 'R'#233'ponse NTLM invalide du serveur.';
    Exit;
  End;
  FL := Msg + L - P;
  MoveB(P, Chal, FL);
  { AUTHENTICATE et cle publique du serveur }
  K := NtlmAuth(Chal, FL, Tok);
  PK := CertPubKey(PN);
  If PK = 0 Then
  Begin
    RdpErr := 'Certificat du serveur illisible.';
    Exit;
  End;
  If Ver >= 5 Then
  Begin
    TlRandom(LongInt(@Nonce[0]), 32);
    { (WPC perd un #0 final : l'octet nul est ajoute a part) }
    Mag := 'CredSSP Client-To-Server Binding Hash';
    TlShaInit(Sh);
    TlShaAdd(Sh, LongInt(@Mag[1]), Length(Mag));
    TlShaByte(Sh, 0);
    TlShaAdd(Sh, LongInt(@Nonce[0]), 32);
    TlShaAdd(Sh, PK, PN);
    TlShaDone(Sh, LongInt(@Hash[0]));
    S := NtlmSeal(LongInt(@Hash[0]), 32, Seal);
    L := TsReq(Tok, K, 0, 0, Seal, S, LongInt(@Nonce[0]), 32, Msg);
  End
  Else
  Begin
    S := NtlmSeal(PK, PN, Seal);
    L := TsReq(Tok, K, 0, 0, Seal, S, 0, 0, Msg);
  End;
  If Not SendRaw(Msg, L) Then Exit;
  { pubKeyAuth du serveur, ou erreur (mauvais mot de passe...) }
  L := RecvTs(Msg);
  E := 0;
  If L > 0 Then E := TsError(Msg, L);
  If (L = 0) Or (E <> 0) Or (TsField(Msg, L, $A3, FL) = 0) Then
  Begin
    If (E = LongInt($C000006D)) Or (E = LongInt($8009030C)) Or (L = 0) Then
      RdpErr := 'Nom d''utilisateur ou mot de passe incorrect.'
    Else If E = LongInt($C0000072) Then RdpErr := 'Ce compte est d'#233'sactiv'#233'.'
    Else If E = LongInt($C0000071) Then RdpErr := 'Le mot de passe a expir'#233'.'
    Else RdpErr := 'Authentification refus'#233'e (code ' + HexS(E) + ').';
    Exit;
  End;
  { TSCredentials : TSPasswordCreds (domaine, utilisateur, mot de passe) }
  K := 0;
  S := Uni16(CrC, RdpDom); S := DerWrap($04, CrC, S, CrB);
  K := K + DerWrap($A0, CrB, S, CrA + K);
  S := Uni16(CrC, RdpUser); S := DerWrap($04, CrC, S, CrB);
  K := K + DerWrap($A1, CrB, S, CrA + K);
  S := Uni16(CrC, RdpPass); S := DerWrap($04, CrC, S, CrB);
  K := K + DerWrap($A2, CrB, S, CrA + K);
  S := DerWrap($30, CrA, K, CrB);
  S := DerWrap($04, CrB, S, CrC);
  SB(CrA, $A0); SB(CrA + 1, 3); SB(CrA + 2, 2); SB(CrA + 3, 1); SB(CrA + 4, 1);
  S := DerWrap($A1, CrC, S, CrA + 5);
  S := DerWrap($30, CrA, S + 5, CrB);
  S := NtlmSeal(CrB, S, Seal);
  ZeroB(CrB, 600);
  L := TsReq(0, 0, Seal, S, 0, 0, 0, 0, Msg);
  If Not SendRaw(Msg, L) Then Exit;
  CredSsp := True;
End;

{ ---- connexion MCS ---- }

Function BerInt(V, Dst : LongInt) : LongInt;
Begin
  SB(Dst, 2);
  If V < $80 Then
  Begin
    SB(Dst + 1, 1); SB(Dst + 2, V); BerInt := 3;
  End
  Else If V < $8000 Then
  Begin
    SB(Dst + 1, 2); SWB(Dst + 2, V); BerInt := 4;
  End
  Else
  Begin
    SB(Dst + 1, 3); SB(Dst + 2, 0); SWB(Dst + 3, V); BerInt := 5;
  End;
End;

Function BerWrap(Tag, Src, N, Dst : LongInt) : LongInt;
Var H : LongInt;
Begin
  H := 0;
  If Tag > 255 Then
  Begin
    SB(Dst, Tag Shr 8); H := 1;
  End;
  SB(Dst + H, Tag And 255); Inc(H);
  If N < 128 Then
  Begin
    SB(Dst + H, N); Inc(H);
  End
  Else
  Begin
    SB(Dst + H, $82); SWB(Dst + H + 1, N); H := H + 3;
  End;
  MoveB(Src, Dst + H, N);
  BerWrap := H + N;
End;

Function DomParams(A, B, C, D, E, F, G, H, Dst : LongInt) : LongInt;
Var T : Array[0..63] Of Byte; K : LongInt;
Begin
  K := 0;
  K := K + BerInt(A, LongInt(@T[K])); K := K + BerInt(B, LongInt(@T[K]));
  K := K + BerInt(C, LongInt(@T[K])); K := K + BerInt(D, LongInt(@T[K]));
  K := K + BerInt(E, LongInt(@T[K])); K := K + BerInt(F, LongInt(@T[K]));
  K := K + BerInt(G, LongInt(@T[K])); K := K + BerInt(H, LongInt(@T[K]));
  DomParams := BerWrap($30, LongInt(@T[0]), K, Dst);
End;

{ MCS Connect-Initial avec la demande GCC (donnees du client) dans Tx }
Function ConnectInitial : Boolean;
Var U, G, M, K, N, L : LongInt; Nm : String;
Begin
  U := PoolB(0); G := PoolB(1); M := PoolB(2);
  ZeroB(U, 600);
  { CS_CORE }
  SW(U, $C001); SW(U + 2, 216);
  SL(U + 4, $00080004);
  SW(U + 8, ReqW); SW(U + 10, ReqH);
  SW(U + 12, $CA01); SW(U + 14, $AA03);
  SL(U + 16, KbdLay);                     { disposition du clavier }
  SL(U + 20, 2600);
  Nm := 'PASDOWS';
  Dummy := Uni16(U + 24, Nm);
  SL(U + 56, 4); SL(U + 60, 0); SL(U + 64, 12);
  SW(U + 132, $CA01); SW(U + 134, 1); SL(U + 136, 0);
  SW(U + 140, 16);                        { highColorDepth }
  SW(U + 142, $0006);                     { 15 et 16 bits }
  SW(U + 144, $0001);                     { SUPPORT_ERRINFO_PDU }
  SL(U + 212, Proto);                     { serverSelectedProtocol }
  K := 216;
  { CS_SECURITY, CS_NET, CS_CLUSTER }
  SW(U + K, $C002); SW(U + K + 2, 12); K := K + 12;
  SW(U + K, $C003); SW(U + K + 2, 8); K := K + 8;
  SW(U + K, $C004); SW(U + K + 2, 12); SL(U + K + 4, $0D); K := K + 12;
  { GCC Conference Create Request (PER) }
  N := 0;
  SB(G, 0); SB(G + 1, 5); SB(G + 2, 0); SB(G + 3, $14); SB(G + 4, $7C);
  SB(G + 5, 0); SB(G + 6, 1);
  SB(G + 7, $80 Or ((K + 14) Shr 8)); SB(G + 8, (K + 14) And 255);
  SB(G + 9, 0); SB(G + 10, 8); SB(G + 11, 0); SB(G + 12, $10);
  SB(G + 13, 0); SB(G + 14, 1); SB(G + 15, $C0); SB(G + 16, 0);
  SB(G + 17, Ord('D')); SB(G + 18, Ord('u')); SB(G + 19, Ord('c'));
  SB(G + 20, Ord('a'));
  SB(G + 21, $80 Or (K Shr 8)); SB(G + 22, K And 255);
  MoveB(U, G + 23, K);
  N := 23 + K;
  { MCS Connect-Initial (BER) }
  L := 0;
  SB(M, 4); SB(M + 1, 1); SB(M + 2, 1);
  SB(M + 3, 4); SB(M + 4, 1); SB(M + 5, 1);
  SB(M + 6, 1); SB(M + 7, 1); SB(M + 8, $FF);
  L := 9;
  L := L + DomParams(34, 2, 0, 1, 0, 1, $FFFF, 2, M + L);
  L := L + DomParams(1, 1, 1, 1, 0, 1, $420, 2, M + L);
  L := L + DomParams($FFFF, $FC17, $FFFF, 1, 0, 1, $FFFF, 2, M + L);
  L := L + BerWrap(4, G, N, M + L);
  L := BerWrap($7F65, M, L, Tx + 7);
  ConnectInitial := SendTpkt(Tx, L);
End;

{ Canal d'E/S d'apres la reponse MCS Connect-Response (donnees GCC) }
Function ConnectResponse(Len : LongInt) : Boolean;
Var P, E, T, L : LongInt;
Begin
  ConnectResponse := False;
  P := Rx + 7; E := Rx + Len;
  While (P < E - 4) And (GL(P) <> $6E44634D) Do Inc(P);   { "McDn" }
  If P >= E - 4 Then
  Begin
    RdpErr := 'R'#233'ponse MCS invalide.';
    Exit;
  End;
  P := P + 4;
  If (GB(P) And $80) <> 0 Then P := P + 2 Else P := P + 1;
  IoChan := 1003;
  While P + 4 <= E Do
  Begin
    T := GW(P); L := GW(P + 2);
    If L < 4 Then Break;
    If T = $0C03 Then IoChan := GW(P + 4);
    P := P + L;
  End;
  ConnectResponse := True;
End;

{ Erect Domain, Attach User, Channel Join (utilisateur et E/S) }
Function McsAttach : Boolean;
Var L, K, Ch : LongInt;
Begin
  McsAttach := False;
  SB(Tx + 7, $04); SB(Tx + 8, 1); SB(Tx + 9, 0); SB(Tx + 10, 1);
  SB(Tx + 11, 0);
  If Not SendTpkt(Tx, 5) Then Exit;
  SB(Tx + 7, $28);
  If Not SendTpkt(Tx, 1) Then Exit;
  If RecvPdu(L) <> 1 Then Exit;
  If (GB(Rx + 7) And $FC) <> $2C Then
  Begin
    RdpErr := 'Attach User refus'#233'.';
    Exit;
  End;
  UserChan := GWB(Rx + 9) + 1001;
  For K := 0 To 1 Do
  Begin
    If K = 0 Then Ch := UserChan Else Ch := IoChan;
    SB(Tx + 7, $38); SWB(Tx + 8, UserChan - 1001); SWB(Tx + 10, Ch);
    If Not SendTpkt(Tx, 5) Then Exit;
    If RecvPdu(L) <> 1 Then Exit;
    If ((GB(Rx + 7) And $FC) <> $3C) Or (GB(Rx + 8) <> 0) Then
    Begin
      RdpErr := 'Channel Join refus'#233'.';
      Exit;
    End;
  End;
  McsAttach := True;
End;

{ Client Info PDU (utilisateur, domaine, mot de passe, performances) }
Function SendClientInfo : Boolean;
Var P, K, N : LongInt; S : String;
Begin
  P := Tx + 15;
  SW(P, $40); SW(P + 2, 0);              { SEC_INFO_PKT }
  K := P + 4;
  ZeroB(K, 1200);
  SL(K, 0);
  SL(K + 4, $1 Or $2 Or $8 Or $10 Or $20 Or $40 Or $100 Or $20000 Or
            $80000);
  SW(K + 8, Length(RdpDom) * 2); SW(K + 10, Length(RdpUser) * 2);
  SW(K + 12, Length(RdpPass) * 2); SW(K + 14, 0); SW(K + 16, 0);
  N := K + 18;
  N := N + Uni16(N, RdpDom) + 2;
  N := N + Uni16(N, RdpUser) + 2;
  N := N + Uni16(N, RdpPass) + 2;
  N := N + 2 + 2;                         { shell et dossier vides }
  { informations etendues }
  S := '0.0.0.0';
  SW(N, 2); SW(N + 2, Length(S) * 2 + 2); N := N + 4;
  N := N + Uni16(N, S) + 2;
  S := 'C:\WINDOWS\MSTSC.EXE';
  SW(N, Length(S) * 2 + 2); N := N + 2;
  N := N + Uni16(N, S) + 2;
  N := N + 172;                           { fuseau horaire }
  SL(N, 0); SL(N + 4, $6F); SW(N + 8, 0);
  N := N + 10;
  SendClientInfo := SendMcs(Tx, IoChan, N - P);
End;

{ ---- activation : Confirm Active et capacites ---- }

Var
  CapP, CapN : LongInt;

Function Cap(Typ, Len : LongInt) : LongInt;
Begin
  SW(CapP, Typ); SW(CapP + 2, Len);
  ZeroB(CapP + 4, Len - 4);
  Cap := CapP + 4;
  CapP := CapP + Len;
  Inc(CapN);
End;

Function SendConfirmActive : Boolean;
Var P, C, Caps, Tot : LongInt;
Begin
  P := Tx + 15;
  SL(P + 6, ShareId);
  SW(P + 10, $03EA);
  SW(P + 12, 6);
  SB(P + 16, Ord('M')); SB(P + 17, Ord('S')); SB(P + 18, Ord('T'));
  SB(P + 19, Ord('S')); SB(P + 20, Ord('C')); SB(P + 21, 0);
  Caps := P + 22;
  CapP := Caps + 4; CapN := 0;
  C := Cap(1, 24);                        { General }
  SW(C, 1); SW(C + 2, 3); SW(C + 4, $200);
  SW(C + 10, $0001 Or $0004 Or $0400);    { fast-path, sans en-tete }
  SB(C + 18, 1); SB(C + 19, 1);
  C := Cap(2, 28);                        { Bitmap }
  SW(C, 16); SW(C + 2, 1); SW(C + 4, 1); SW(C + 6, 1);
  SW(C + 8, FbW); SW(C + 10, FbH);
  SW(C + 14, 1); SW(C + 16, 1); SW(C + 20, 1);
  C := Cap(3, 88);                        { Order : aucun ordre }
  SW(C + 20, 1); SW(C + 22, 20); SW(C + 26, 1);
  SW(C + 30, $2A);
  C := Cap(4, 40);                        { BitmapCache }
  C := Cap(5, 12);                        { Control }
  SW(C + 4, 2); SW(C + 6, 2);
  C := Cap(7, 12);                        { Activation }
  C := Cap(8, 10);                        { Pointer }
  SW(C, 1); SW(C + 2, 20); SW(C + 4, 20);
  C := Cap(9, 8);                         { Share }
  C := Cap(10, 8);                        { ColorCache }
  SW(C, 6);
  C := Cap(12, 8);                        { Sound }
  C := Cap(13, 88);                       { Input }
  SW(C, $0001 Or $0004 Or $0010 Or $0020);
  SL(C + 4, KbdLay); SL(C + 8, 4); SL(C + 12, 0); SL(C + 16, 12);
  C := Cap(14, 8);                        { Font }
  SW(C, 1);
  C := Cap(15, 8);                        { Brush }
  C := Cap(16, 52);                       { GlyphCache }
  C := Cap(17, 12);                       { OffscreenCache }
  C := Cap(20, 12);                       { VirtualChannel }
  SL(C + 4, 1600);
  SW(Caps, CapN); SW(Caps + 2, 0);
  SW(P + 14, CapP - Caps);
  Tot := CapP - P;
  SW(P, Tot); SW(P + 2, $13); SW(P + 4, UserChan);
  SendConfirmActive := SendMcs(Tx, IoChan, Tot);
End;

{ Synchronize, Control (Cooperate, Request Control), Font List }
Function SendFinalize : Boolean;
Var P : LongInt;
Begin
  SendFinalize := False;
  P := Tx + 33;
  SW(P, 1); SW(P + 2, SrvChan);
  If Not SendData(31, 4) Then Exit;
  SW(P, 4); SW(P + 2, 0); SL(P + 4, 0);
  If Not SendData(20, 8) Then Exit;
  SW(P, 1); SW(P + 2, 0); SL(P + 4, 0);
  If Not SendData(20, 8) Then Exit;
  SW(P, 0); SW(P + 2, 0); SW(P + 4, 3); SW(P + 6, $32);
  SendFinalize := SendData(39, 8);
End;

{ Demand Active : partage, taille de l'ecran distant }
Procedure DemandActive(A, N : LongInt);
Var P, E, Nc, I, T, L, W, H, Ls, Lc : LongInt;
Begin
  SrvChan := GW(A + 4);
  ShareId := GL(A + 6);
  Ls := GW(A + 10); Lc := GW(A + 12);
  P := A + 14 + Ls;
  Nc := GW(P); P := P + 4;
  E := A + N;
  W := FbW; H := FbH;
  For I := 1 To Nc Do
  Begin
    If P + 4 > E Then Break;
    T := GW(P); L := GW(P + 2);
    If L < 4 Then Break;
    If T = 2 Then
    Begin
      W := GW(P + 12); H := GW(P + 14);
    End;
    P := P + L;
  End;
  If (W <> FbW) Or (H <> FbH) Or (Fb = 0) Then
  Begin
    FbW := W; FbH := H;
    FbPitch := (FbW * 2 + 3) And Not 3;
    Fb := NewMem(FbPitch * FbH + 64);
    BmiH[0] := 40; BmiH[1] := FbW; BmiH[2] := -FbH;
    BmiH[3] := $00100001;                 { 1 plan, 16 bits }
    BmiH[4] := 3;                         { BI_BITFIELDS }
    BmiH[5] := 0; BmiH[6] := 0; BmiH[7] := 0; BmiH[8] := 0; BmiH[9] := 0;
    BmiH[10] := $F800; BmiH[11] := $07E0; BmiH[12] := $001F;
  End;
  If SendConfirmActive Then
    If SendFinalize Then
    Begin
      Active := True;
      If Not FirstAct Then
      Begin
        FirstAct := True;
        Dummy := PostMessageA(DlgWnd, WM_RDPACTIVE, 0, 0);
      End;
    End;
End;

{ ---- bitmaps ---- }

Procedure Dirty(L, T, R, B : LongInt);
Begin
  If DirtyR <= DirtyL Then
  Begin
    DirtyL := L; DirtyT := T; DirtyR := R; DirtyB := B;
  End
  Else
  Begin
    DirtyL := MinI(DirtyL, L); DirtyT := MinI(DirtyT, T);
    DirtyR := MaxI(DirtyR, R); DirtyB := MaxI(DirtyB, B);
  End;
End;

Procedure FlushDirty;
Var Rc : Array[0..3] Of LongInt;
Begin
  If (DirtyR <= DirtyL) Or (SessWnd = 0) Then Exit;
  Rc[0] := DirtyL - ViewX; Rc[1] := DirtyT - ViewY;
  Rc[2] := DirtyR - ViewX; Rc[3] := DirtyB - ViewY;
  Dummy := InvalidateRect(SessWnd, LongInt(@Rc), 0);
  DirtyR := DirtyL;
End;

Function RdPx(A, Bp : LongInt) : LongInt;
Begin
  Case Bp Of
    1 : RdPx := GB(A);
    2 : RdPx := GW(A);
  Else
    RdPx := GW(A) Or (GB(A + 2) Shl 16);
  End;
End;

Procedure WrPx(A, Bp, V : LongInt);
Begin
  Case Bp Of
    1 : SB(A, V);
    2 : SW(A, V);
  Else
    Begin
      SW(A, V); SB(A + 2, V Shr 16);
    End;
  End;
End;

{ RLE entrelace (MS-RDPBCGR 2.2.9.1.1.3.1.2.4), Bp octets par point ;
  le resultat (de bas en haut) est dans DecB ; False si invalide }
Function RleDecode(Src, SLen, W, H, Bp : LongInt) : Boolean;
Var S, E, D, DE, Row, Code, Len, Fg, Px, Px2, Mask, K, Adv, White,
    B0 : LongInt;
    First, InsFg : Boolean;

  Procedure Put(V : LongInt);
  Begin
    If D + Bp <= DE Then WrPx(D, Bp, V);
    D := D + Bp;
  End;

  Function Above : LongInt;
  Begin
    Above := RdPx(D - Row, Bp);
  End;

  Procedure FgBg(Bits, N : LongInt);
  Var I : LongInt;
  Begin
    For I := 0 To N - 1 Do
    Begin
      If First Then
      Begin
        If (Bits And (1 Shl I)) <> 0 Then Put(Fg) Else Put(0);
      End
      Else If (Bits And (1 Shl I)) <> 0 Then Put(Above Xor Fg)
      Else Put(Above);
    End;
  End;

Begin
  RleDecode := False;
  S := Src; E := Src + SLen; D := DecB; Row := W * Bp; DE := DecB + Row * H;
  Fg := $FFFFFF; If Bp = 2 Then Fg := $FFFF; If Bp = 1 Then Fg := $FF;
  White := Fg;
  First := True; InsFg := False;
  While (S < E) And (D < DE) Do
  Begin
    If First And (D - DecB >= Row) Then
    Begin
      First := False; InsFg := False;
    End;
    B0 := GB(S);
    If (B0 And $F0) = $F0 Then Code := B0
    Else
    Begin
      Code := B0 Shr 5;
      If Code > 4 Then Code := B0 Shr 4;
    End;
    { longueur }
    Adv := 1;
    Case Code Of
      0, 1, 3, 4 :
      Begin
        Len := B0 And $1F;
        If Len = 0 Then Begin Len := GB(S + 1) + 32; Adv := 2; End;
      End;
      2 :
      Begin
        Len := B0 And $1F;
        If Len = 0 Then Begin Len := GB(S + 1) + 1; Adv := 2; End
        Else Len := Len * 8;
      End;
      $C, $E :
      Begin
        Len := B0 And $0F;
        If Len = 0 Then Begin Len := GB(S + 1) + 16; Adv := 2; End;
      End;
      $D :
      Begin
        Len := B0 And $0F;
        If Len = 0 Then Begin Len := GB(S + 1) + 1; Adv := 2; End
        Else Len := Len * 8;
      End;
      $F0, $F1, $F2, $F3, $F4, $F6, $F7, $F8 :
      Begin
        Len := GW(S + 1); Adv := 3;
      End;
    Else
      Begin
        Len := 0; Adv := 1;
      End;
    End;
    S := S + Adv;
    { fond (copie de la ligne precedente) }
    If (Code = 0) Or (Code = $F0) Then
    Begin
      If First Then
      Begin
        If InsFg Then Begin Put(Fg); Dec(Len); End;
        While Len > 0 Do Begin Put(0); Dec(Len); End;
      End
      Else
      Begin
        If InsFg Then Begin Put(Above Xor Fg); Dec(Len); End;
        While Len > 0 Do Begin Put(Above); Dec(Len); End;
      End;
      InsFg := True;
      Continue;
    End;
    InsFg := False;
    Case Code Of
      1, $F1, $C, $F6 :
      Begin
        If (Code = $C) Or (Code = $F6) Then
        Begin
          Fg := RdPx(S, Bp); S := S + Bp;
        End;
        While Len > 0 Do
        Begin
          If First Then Put(Fg) Else Put(Above Xor Fg);
          Dec(Len);
        End;
      End;
      $E, $F8 :
      Begin
        Px := RdPx(S, Bp); Px2 := RdPx(S + Bp, Bp); S := S + 2 * Bp;
        While Len > 0 Do
        Begin
          Put(Px); Put(Px2); Dec(Len);
        End;
      End;
      3, $F3 :
      Begin
        Px := RdPx(S, Bp); S := S + Bp;
        While Len > 0 Do Begin Put(Px); Dec(Len); End;
      End;
      2, $F2, $D, $F7 :
      Begin
        If (Code = $D) Or (Code = $F7) Then
        Begin
          Fg := RdPx(S, Bp); S := S + Bp;
        End;
        While Len > 8 Do
        Begin
          Mask := GB(S); Inc(S);
          FgBg(Mask, 8);
          Len := Len - 8;
        End;
        If Len > 0 Then
        Begin
          Mask := GB(S); Inc(S);
          FgBg(Mask, Len);
        End;
      End;
      4, $F4 :
      Begin
        K := Len * Bp;
        If D + K <= DE Then MoveB(S, D, K);
        D := D + K; S := S + K;
      End;
      $F9 : FgBg($03, 8);
      $FA : FgBg($05, 8);
      $FD : Put(White);
      $FE : Put(0);
    Else
      Exit;
    End;
  End;
  RleDecode := True;
End;

{ Point (format Bpp) -> RGB 5-6-5 }
Function To565(V, Bpp : LongInt) : LongInt;
Begin
  Case Bpp Of
    16 : To565 := V;
    15 : To565 := ((V And $7C00) Shl 1) Or ((V And $3E0) Shl 1) Or
                  ((V Shr 4) And $20) Or (V And $1F);
    8 : To565 := Pal565[V And 255];
  Else
    To565 := (((V Shr 19) And $1F) Shl 11) Or (((V Shr 10) And $3F) Shl 5) Or
             ((V Shr 3) And $1F);
  End;
End;

{ Rectangle decode (W x H, de bas en haut, en A) -> Fb en (L, T)..(R, B) }
Procedure Blit(A, W, H, Bpp, L, T, R, B : LongInt);
Var Y, X, Bp, Sr, Dr, Cx, V : LongInt;
Begin
  Bp := (Bpp + 7) Div 8;
  If R >= FbW Then R := FbW - 1;
  If B >= FbH Then B := FbH - 1;
  Cx := R - L + 1;
  If Cx > W Then Cx := W;
  For Y := 0 To B - T Do
  Begin
    If Y >= H Then Break;
    Sr := A + (H - 1 - Y) * W * Bp;
    Dr := Fb + (T + Y) * FbPitch + L * 2;
    If Bpp = 16 Then MoveB(Sr, Dr, Cx * 2)
    Else
      For X := 0 To Cx - 1 Do
      Begin
        If Bp = 4 Then V := GL(Sr + X * 4) And $FFFFFF
        Else V := RdPx(Sr + X * Bp, Bp);
        SW(Dr + X * 2, To565(V, Bpp));
      End;
  End;
  Dirty(L, T, R + 1, B + 1);
End;

{ TS_UPDATE_BITMAP_DATA (updateType, numberRectangles, rectangles) }
Procedure BitmapUpdate(A, N : LongInt);
Var P, E, I, Cnt, L, T, R, B, W, H, Bpp, Fl, Len, D, DL : LongInt;
Begin
  If Fb = 0 Then Exit;
  Cnt := GW(A + 2); P := A + 4; E := A + N;
  For I := 1 To Cnt Do
  Begin
    If P + 18 > E Then Break;
    L := GW(P); T := GW(P + 2); R := GW(P + 4); B := GW(P + 6);
    W := GW(P + 8); H := GW(P + 10); Bpp := GW(P + 12); Fl := GW(P + 14);
    Len := GW(P + 16);
    P := P + 18;
    D := P; DL := Len;
    If (W > 0) And (H > 0) And (W * H <= 1048576) And (L < FbW) And
       (T < FbH) Then
    Begin
      If (Fl And 1) <> 0 Then
      Begin
        If (Fl And $400) = 0 Then
        Begin
          D := D + 8; DL := DL - 8;
        End;
        If RleDecode(D, DL, W, H, (Bpp + 7) Div 8) Then
          Blit(DecB, W, H, Bpp, L, T, R, B);
      End
      Else Blit(D, W, H, Bpp, L, T, R, B);
    End;
    P := P + Len;
  End;
  FlushDirty;
End;

Procedure PaletteUpdate(A, N : LongInt);
Var I, C, P : LongInt;
Begin
  C := GL(A + 4);
  If C > 256 Then C := 256;
  For I := 0 To C - 1 Do
  Begin
    P := A + 8 + I * 3;
    Pal565[I] := ((GB(P) Shr 3) Shl 11) Or ((GB(P + 1) Shr 2) Shl 5) Or
                 (GB(P + 2) Shr 3);
  End;
End;

{ ---- PDU recues ---- }

{ Chemin rapide : mises a jour (fragments reassembles) }
Procedure FastPath(Len : LongInt);
Var P, E, H, Code, Fr, Sz, Cf : LongInt;
Begin
  P := Rx + 2;
  If (GB(Rx + 1) And $80) <> 0 Then P := Rx + 3;
  E := Rx + Len;
  While P + 3 <= E Do
  Begin
    H := GB(P); Inc(P);
    Code := H And $0F; Fr := (H Shr 4) And 3;
    Cf := 0;
    If ((H Shr 6) And 3) = 2 Then
    Begin
      Cf := GB(P); Inc(P);
    End;
    Sz := GW(P); P := P + 2;
    If P + Sz > E Then Break;
    If (Cf And $20) = 0 Then
    Begin
      If Fr = 0 Then
      Begin
        If Code = 1 Then BitmapUpdate(P, Sz)
        Else If Code = 2 Then PaletteUpdate(P, Sz);
      End
      Else
      Begin
        If Fr = 2 Then FragLen := 0;
        If FragLen + Sz <= 4194304 Then
        Begin
          MoveB(P, Frag + FragLen, Sz);
          FragLen := FragLen + Sz;
        End;
        If Fr = 1 Then
        Begin
          If Code = 1 Then BitmapUpdate(Frag, FragLen)
          Else If Code = 2 Then PaletteUpdate(Frag, FragLen);
          FragLen := 0;
        End;
      End;
    End;
    P := P + Sz;
  End;
End;

{ Client New License Request (reponse a LICENSE_REQUEST) : sans cle
  RSA du serveur, le secret est un alea ; les serveurs sans gestionnaire
  de licences (xrdp, Windows en mode administration) l'acceptent }
Procedure SendLicenseRequest(A, N : LongInt);
Var P, K, L : LongInt; S : String;
Begin
  P := Tx + 15;
  SW(P, $80); SW(P + 2, 0);
  SB(P + 4, $13); SB(P + 5, $83);
  K := P + 8;
  SL(K, 1); SL(K + 4, $04010000);
  TlRandom(K + 8, 32);
  K := K + 40;
  SW(K, 2); SW(K + 2, 72); TlRandom(K + 4, 64); ZeroB(K + 68, 8);
  K := K + 76;
  S := Copy(RdpUser, 1, 60);
  SW(K, $0F); SW(K + 2, Length(S) + 1);
  For L := 1 To Length(S) Do SB(K + 3 + L, Ord(S[L]));
  SB(K + 4 + Length(S), 0);
  K := K + 5 + Length(S);
  S := 'PASDOWS';
  SW(K, $10); SW(K + 2, Length(S) + 1);
  For L := 1 To Length(S) Do SB(K + 3 + L, Ord(S[L]));
  SB(K + 4 + Length(S), 0);
  K := K + 5 + Length(S);
  SW(P + 6, K - P - 4);
  Dummy := Ord(SendMcs(Tx, IoChan, K - P));
End;

{ PDU sur le canal d'E/S (A : en-tete de partage ou de securite) ;
  False : fin de la session }
Function SlowPdu(A, N : LongInt) : Boolean;
Var Typ, T2, P, Er : LongInt;
Begin
  SlowPdu := True;
  If N < 4 Then Exit;
  { licence : en-tete de securite SEC_LICENSE_PKT (le premier mot d'une
    PDU de partage est sa longueur) }
  If (GW(A) <> N) And (GW(A) <> $8000) And ((GW(A) And $80) <> 0) Then
  Begin
    Case GB(A + 4) Of
      $FF :                               { ERROR_ALERT }
        If (GL(A + 8) = 7) Or (GL(A + 8) = 0) Then Licensed := True
        Else
        Begin
          RdpErr := 'Erreur de licence du serveur (code ' + IStr(GL(A + 8)) + ').';
          SlowPdu := False;
        End;
      1 : SendLicenseRequest(A + 8, N - 8);   { LICENSE_REQUEST }
      2 :                                 { PLATFORM_CHALLENGE }
      Begin
        RdpErr := 'Le serveur exige une licence d''acc'#232's client (CAL) ' +
                  'des services Bureau '#224' distance, que Pasdows ne sait pas encore ' +
                  'obtenir. Les deux sessions d''administration de Windows ' +
                  'Server n''en demandent pas.';
        SlowPdu := False;
      End;
      3, 4 : Licensed := True;            { NEW_LICENSE, UPGRADE_LICENSE }
    End;
    Exit;
  End;
  If GW(A) = $8000 Then Exit;             { controle de flux }
  Typ := GW(A + 2) And $0F;
  Case Typ Of
    1 : DemandActive(A, N);
    6 : Active := False;                  { Deactivate All }
    7 :
    Begin
      T2 := GB(A + 14);
      P := A + 18;
      If GB(A + 15) <> 0 Then Exit;       { compresse : non demande }
      Case T2 Of
        2 :
          If GW(P) = 1 Then BitmapUpdate(P, N - 18)
          Else If GW(P) = 2 Then PaletteUpdate(P, N - 18);
        47 :
        Begin
          Er := GL(P);
          If Er <> 0 Then ErrInfo := Er;
        End;
        36 :                              { Shutdown Denied }
          ;
      End;
    End;
  End;
End;

{ ---- entrees (chemin rapide, depuis la fenetre) ---- }

Function SendInput(N, Cnt : LongInt) : Boolean;
Begin
  SendInput := False;
  If Not Active Then Exit;
  { en-tete : action 0, nombre d'evenements ; longueur sur 1 ou 2 octets }
  SB(InB, Cnt Shl 2);
  If N + 2 < 128 Then
  Begin
    SB(InB + 1, N + 2);
    MoveB(InB + 8, InB + 2, N);
    SendInput := SendRaw(InB, N + 2);
  End
  Else
  Begin
    SB(InB + 1, $80 Or ((N + 3) Shr 8)); SB(InB + 2, (N + 3) And 255);
    MoveB(InB + 8, InB + 3, N);
    SendInput := SendRaw(InB, N + 3);
  End;
End;

Procedure SendKey(Sc : LongInt; Ext, Up : Boolean);
Var F : LongInt;
Begin
  F := 0;
  If Up Then F := F Or 1;
  If Ext Then F := F Or 2;
  SB(InB + 8, F); SB(InB + 9, Sc);
  Dummy := Ord(SendInput(2, 1));
End;

Procedure SendMouse(Fl, X, Y : LongInt);
Begin
  SB(InB + 8, 1 Shl 5);
  SW(InB + 9, Fl); SW(InB + 11, X); SW(InB + 13, Y);
  Dummy := Ord(SendInput(7, 1));
End;

Procedure SendSync(Fl : LongInt);
Begin
  SB(InB + 8, (3 Shl 5) Or (Fl And $1F));
  Dummy := Ord(SendInput(1, 1));
End;

{ ---- session (tache de connexion et de reception) ---- }

Function X224Connect(S : LongInt) : Boolean;
Var N, L, P : LongInt; Ck : String;
Begin
  X224Connect := False;
  Ck := 'Cookie: mstshash=' + Copy(RdpUser, 1, 9) + #13#10;
  N := 11 + Length(Ck) + 8;
  SB(Tx, 3); SB(Tx + 1, 0); SWB(Tx + 2, N);
  SB(Tx + 4, N - 5); SB(Tx + 5, $E0);
  SW(Tx + 6, 0); SW(Tx + 8, 0); SB(Tx + 10, 0);
  For L := 1 To Length(Ck) Do SB(Tx + 10 + L, Ord(Ck[L]));
  P := Tx + 11 + Length(Ck);
  SB(P, 1); SB(P + 1, 0); SW(P + 2, 8);
  SL(P + 4, 3);                           { TLS et CredSSP (NLA) }
  If Not SendRaw(Tx, N) Then Exit;
  If RecvPdu(L) <> 1 Then
  Begin
    RdpErr := 'Pas de r'#233'ponse X.224 du serveur.';
    Exit;
  End;
  Proto := 0;
  If L >= 19 Then
  Begin
    If GB(Rx + 11) = 2 Then Proto := GL(Rx + 15)
    Else If GB(Rx + 11) = 3 Then
    Begin
      Case GL(Rx + 15) Of
        2 : RdpErr := 'Le serveur n''accepte que la s'#233'curit'#233' RDP standard ' +
                      '(activez TLS ou NLA sur le serveur).';
        5 : RdpErr := 'Le serveur exige l''authentification NLA.';
      Else
        RdpErr := 'N'#233'gociation de la s'#233'curit'#233' refus'#233'e (code ' +
                  IStr(GL(Rx + 15)) + ').';
      End;
      Exit;
    End;
  End;
  If (Proto <> 1) And (Proto <> 2) Then
  Begin
    RdpErr := 'Le serveur n''accepte que la s'#233'curit'#233' RDP standard, que ' +
              'Pasdows ne g'#232're pas (activez TLS ou NLA).';
    Exit;
  End;
  X224Connect := True;
End;

Function RdpSession : Boolean;
Var S, L, K : LongInt; E : String;
Begin
  RdpSession := False;
  Status('Connexion '#224' ' + RdpHost + '...');
  S := TcpOpen(RdpHost, RdpPort, E);
  If S < 0 Then
  Begin
    RdpErr := E;
    Exit;
  End;
  Tc.Sock := S; Tc.Tls := False; Tc.Used := True;
  Tc.Enc := False; Tc.Dec := False; Tc.RPos := 0; Tc.REnd := 0;
  Tc.Eof := False;
  If Not X224Connect(S) Then Exit;
  Status('S'#233'curisation de la connexion (TLS)...');
  Tc.Tls := True;
  If Not TlHandshake(Tc, RdpHost) Then
  Begin
    RdpErr := 'TLS : ' + TlErr;
    Exit;
  End;
  If Proto = 2 Then
  Begin
    Status('Authentification (NLA)...');
    If Not CredSsp Then Exit;
  End;
  Status('Ouverture de la session...');
  If Not ConnectInitial Then Exit;
  K := RecvPdu(L);
  If (K <> 1) Or Not ConnectResponse(L) Then
  Begin
    If RdpErr = '' Then RdpErr := 'Le serveur a refus'#233' la connexion MCS.';
    Exit;
  End;
  If Not McsAttach Then
  Begin
    If RdpErr = '' Then RdpErr := 'Connexion MCS interrompue.';
    Exit;
  End;
  If Not SendClientInfo Then Exit;
  Connected := True;
  Status('Bureau '#224' distance...');
  { reception jusqu'a la fin de la session }
  Repeat
    K := RecvPdu(L);
    If K = 2 Then FastPath(L)
    Else If K = 1 Then
    Begin
      { MCS : Send Data Indication ou Disconnect Provider Ultimatum }
      If (GB(Rx + 7) And $FC) = $20 Then Break;
      If (GB(Rx + 7) And $FC) = $68 Then
      Begin
        If (GB(Rx + 13) And $80) <> 0 Then K := Rx + 15 Else K := Rx + 14;
        If Not SlowPdu(K, Rx + L - K) Then Break;
      End;
    End;
  Until (K = 0) Or NetStop;
  RdpSession := True;
End;

{ tache : session complete puis message de fin a la boite }
Function RdpThread(P : LongInt) : LongInt; stdcall;
Begin
  RdpErr := ''; ErrInfo := 0;
  Dummy := Ord(RdpSession);
  If Tc.Sock <> 0 Then TlSockClose(Tc.Sock);
  Tc.Sock := 0;
  Active := False;
  Dummy := PostMessageA(DlgWnd, WM_RDPEND, 0, 0);
  RdpThread := 0;
End;

{ ---- aleas ---- }

Procedure TlEntropy;
Var Q : Array[0..1] Of LongInt; Pt : Array[0..1] Of LongInt;
Begin
  Dummy := QueryPerformanceCounter(LongInt(@Q[0]));
  TlSeed(Q[0]); TlSeed(Q[1]); TlSeed(GetTickCount);
  Dummy := GetCursorPos(LongInt(@Pt[0]));
  TlSeed(Pt[0] * 65536 + Pt[1]);
  TlSeed(LongInt(@Q[0]));
End;

{ ==================================================================== }
{ Interface : boite Connexion Bureau a distance et fenetre de session   }
{ ==================================================================== }

Const
  ID_CONNECT = 1; ID_QUIT = 2; ID_HOST = 10; ID_USER = 11; ID_PASS = 12;
  ID_DOM = 13; ID_SIZE = 14; ID_STAT = 15;
  WM_KILLFOCUS = $0008; WM_MBUTTONDOWN = $0207; WM_MBUTTONUP = $0208;
  WM_RBUTTONUP = $0205; WM_MOUSEWHEEL = $020A; WM_SYSKEYDOWN = $0104;
  WM_SYSKEYUP = $0105; WM_KEYUP = $0101; WM_SYSCOMMAND = $0112;
  ES_PASSWORD = $0020; SM_CXFULL = 0;

Function RegCreateKeyA(K, Sub, PRes : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'RegCreateKeyA';
Function RegSetValueExA(K, Name, Res, Typ, Data, Len : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegSetValueExA';
Function GetScrollPos(H, Bar : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetScrollPos';

Function GetKeyboardLayout(T : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetKeyboardLayout';

Const
  SbW = 16; SB_CTL = 2;

Var
  EHost, EUser, EPass, EDom, LSize, SStat, BConn, HSb, VSb : LongInt;
  FullScr, Busy : Boolean;
  SessCW, SessCH, Sizes : LongInt;
  QuitBuf : Array[0..15] Of Byte;

{ ---- registre : dernier ordinateur et utilisateur (comme mstsc) ---- }

Function RegRead(Path, Nm : String) : String;
Var K, T, N : LongInt; B : Array[0..255] Of Byte;
Begin
  RegRead := '';
  K := 0;
  If RegOpenKeyExA(LongInt($80000001), Z(Path), 0, $20019, LongInt(@K)) <> 0 Then
    Exit;
  N := 255; T := 0; B[0] := 0;
  If RegQueryValueExA(K, Z(Nm), 0, LongInt(@T), LongInt(@B[0]), LongInt(@N)) = 0 Then
  Begin
    B[255] := 0;
    RegRead := GetZ(LongInt(@B[0]));
  End;
  Dummy := RegCloseKey(K);
End;

Procedure RegWrite(Path, Nm, V : String);
Var K : LongInt;
Begin
  K := 0;
  If RegCreateKeyA(LongInt($80000001), Z(Path), LongInt(@K)) <> 0 Then Exit;
  PutZ(LongInt(@NameZ2), V);
  Dummy := RegSetValueExA(K, Z(Nm), 0, 1, LongInt(@NameZ2), Length(V) + 1);
  Dummy := RegCloseKey(K);
End;

{ ---- fenetre de session ---- }

{ barres de defilement (controles SCROLLBAR) quand l'ecran distant
  depasse la fenetre ; SessCW, SessCH : zone visible }
Procedure SetScrolls;
Var Rc : Array[0..3] Of LongInt; CW, CH : LongInt; NH, NV : Boolean;
Begin
  Dummy := GetClientRect(SessWnd, LongInt(@Rc));
  CW := Rc[2]; CH := Rc[3];
  If (CW <= 0) Or (CH <= 0) Then Exit;
  NH := FbW > CW; NV := FbH > CH;
  If NH Then CH := CH - SbW;
  If NV Then CW := CW - SbW;
  If Not NH And (FbW > CW) Then
  Begin
    NH := True; CH := CH - SbW;
  End;
  SessCW := CW; SessCH := CH;
  If ViewX > FbW - SessCW Then ViewX := MaxI(0, FbW - SessCW);
  If ViewY > FbH - SessCH Then ViewY := MaxI(0, FbH - SessCH);
  If NH Then
  Begin
    If HSb = 0 Then HSb := Ctl(SessWnd, 'SCROLLBAR', '', 0, 0, CH, CW, SbW, 30)
    Else Dummy := MoveWindow(HSb, 0, CH, CW, SbW, 1);
    Dummy := SetScrollRange(HSb, SB_CTL, 0, FbW - SessCW, 0);
    Dummy := SetScrollPos(HSb, SB_CTL, ViewX, 1);
  End
  Else If HSb <> 0 Then
  Begin
    Dummy := DestroyWindow(HSb); HSb := 0;
  End;
  If NV Then
  Begin
    If VSb = 0 Then VSb := Ctl(SessWnd, 'SCROLLBAR', '', 1, CW, 0, SbW, CH, 31)
    Else Dummy := MoveWindow(VSb, CW, 0, SbW, CH, 1);
    Dummy := SetScrollRange(VSb, SB_CTL, 0, FbH - SessCH, 0);
    Dummy := SetScrollPos(VSb, SB_CTL, ViewY, 1);
  End
  Else If VSb <> 0 Then
  Begin
    Dummy := DestroyWindow(VSb); VSb := 0;
  End;
End;

Procedure ScrollTo(Bar, Code, Pos : LongInt);
Var V, Mx, Pg : LongInt;
Begin
  If Bar = SB_HORZ Then
  Begin
    V := ViewX; Mx := MaxI(0, FbW - SessCW); Pg := SessCW;
  End
  Else
  Begin
    V := ViewY; Mx := MaxI(0, FbH - SessCH); Pg := SessCH;
  End;
  Case Code Of
    SB_LINEUP : V := V - 16;
    SB_LINEDOWN : V := V + 16;
    SB_PAGEUP : V := V - Pg;
    SB_PAGEDOWN : V := V + Pg;
    SB_THUMBPOSITION, SB_THUMBTRACK : V := Pos;
    { fin du defilement : position tenue par le controle }
    8 :
      If (Bar = SB_HORZ) And (HSb <> 0) Then V := GetScrollPos(HSb, SB_CTL)
      Else If (Bar = SB_VERT) And (VSb <> 0) Then V := GetScrollPos(VSb, SB_CTL);
  End;
  If V > Mx Then V := Mx;
  If V < 0 Then V := 0;
  If Bar = SB_HORZ Then ViewX := V Else ViewY := V;
  If (Bar = SB_HORZ) And (HSb <> 0) Then Dummy := SetScrollPos(HSb, SB_CTL, V, 1);
  If (Bar = SB_VERT) And (VSb <> 0) Then Dummy := SetScrollPos(VSb, SB_CTL, V, 1);
  Dummy := InvalidateRect(SessWnd, 0, 0);
End;

{ relacher les touches de modification (perte du focus) }
Procedure ReleaseMods;
Begin
  SendKey($1D, False, True); SendKey($38, False, True);
  SendKey($2A, False, True); SendKey($36, False, True);
  SendKey($1D, True, True); SendKey($38, True, True);
End;

Procedure MakeSession; Forward;

Procedure Disconnect;
Begin
  { MCS Disconnect Provider Ultimatum, puis fermeture }
  QuitBuf[7] := $21; QuitBuf[8] := $80;
  QuitBuf[0] := 3; QuitBuf[1] := 0; QuitBuf[2] := 0; QuitBuf[3] := 9;
  QuitBuf[4] := 2; QuitBuf[5] := $F0; QuitBuf[6] := $80;
  If Active Then Dummy := Ord(SendRaw(LongInt(@QuitBuf[0]), 9));
  NetStop := True;
  Active := False;
  If Tc.Sock <> 0 Then Dummy := closesocket(Tc.Sock);
End;

Function SessProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt;
    Dc, X, Y, W, Hh, Sc, Fl : LongInt; Ext : Boolean;
Begin
  SessProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        X := Ps[2]; Y := Ps[3]; W := Ps[4] - Ps[2]; Hh := Ps[5] - Ps[3];
        If (W <= 0) Or (Hh <= 0) Then
        Begin
          X := 0; Y := 0; W := SessCW; Hh := SessCH;
        End;
        If X + W > SessCW Then W := SessCW - X;
        If Y + Hh > SessCH Then Hh := SessCH - Y;
        If X + ViewX + W > FbW Then W := FbW - X - ViewX;
        If Y + ViewY + Hh > FbH Then Hh := FbH - Y - ViewY;
        If (Fb <> 0) And (W > 0) And (Hh > 0) Then
          Dummy := StretchDIBits(Dc, X, Y, W, Hh, X + ViewX, Y + ViewY, W, Hh,
                                 Fb, LongInt(@BmiH[0]), 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : SessProc := 1;
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then SetScrolls;
      End;
    WM_HSCROLL : ScrollTo(SB_HORZ, WP And $FFFF, S16(WP Shr 16));
    WM_VSCROLL : ScrollTo(SB_VERT, WP And $FFFF, S16(WP Shr 16));
    WM_MOUSEMOVE, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_RBUTTONDOWN,
    WM_RBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_LBUTTONDBLCLK :
      Begin
        X := MaxI(0, S16(LP) + ViewX); Y := MaxI(0, S16(LP Shr 16) + ViewY);
        Case Msg Of
          WM_MOUSEMOVE : Fl := $0800;
          WM_LBUTTONDOWN, WM_LBUTTONDBLCLK : Fl := $8000 Or $1000;
          WM_LBUTTONUP : Fl := $1000;
          WM_RBUTTONDOWN : Fl := $8000 Or $2000;
          WM_RBUTTONUP : Fl := $2000;
          WM_MBUTTONDOWN : Fl := $8000 Or $4000;
        Else
          Fl := $4000;
        End;
        If (Fl And $8000) <> 0 Then Dummy := SetCapture(H)
        Else If Msg <> WM_MOUSEMOVE Then Dummy := ReleaseCapture;
        SendMouse(Fl, X, Y);
      End;
    WM_MOUSEWHEEL :
      SendMouse($0200 Or (S16(WP Shr 16) And $1FF), 0, 0);
    WM_KEYDOWN, WM_SYSKEYDOWN, WM_KEYUP, WM_SYSKEYUP :
      Begin
        Sc := (LP Shr 16) And $FF;
        Ext := (LP And $01000000) <> 0;
        { Ctrl+Alt+Fin : Ctrl+Alt+Suppr sur l'ordinateur distant ;
          Ctrl+Alt+Pause (comme mstsc) ou Ctrl+Alt+Entree : plein ecran
          ou fenetre }
        If ((GetKeyState(VK_CONTROL) And $8000) <> 0) And
           ((GetKeyState($12) And $8000) <> 0) Then
        Begin
          If WP = VK_END Then
          Begin
            Sc := $53; Ext := True;
          End
          Else If (WP = $13) Or (WP = $03) Or (WP = VK_RETURN) Then
          Begin
            If (Msg = WM_KEYDOWN) Or (Msg = WM_SYSKEYDOWN) Then
            Begin
              FullScr := Not FullScr;
              ReleaseMods;
              MakeSession;
            End;
            Exit;
          End;
        End;
        If Sc <> 0 Then
          SendKey(Sc, Ext, (Msg = WM_KEYUP) Or (Msg = WM_SYSKEYUP));
      End;
    WM_CHAR, $0106 : ;
    WM_KILLFOCUS : If Active Then ReleaseMods;
    WM_CLOSE :
      If Ask('Votre session '#224' distance va '#234'tre d'#233'connect'#233'e.',
             'Connexion Bureau '#224' distance', MB_OKCANCEL Or MB_ICONINFO) = 1
      Then Disconnect;
    WM_DESTROY : ;
  Else
    SessProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

{ (re)creer la fenetre de session : plein ecran ou fenetre avec barres
  de defilement si l'ecran distant est plus grand }
Procedure MakeSession;
Var Old, Sw, Sh, W, H, St : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  Old := SessWnd;
  Sw := GetSystemMetrics(SM_CXSCREEN); Sh := GetSystemMetrics(SM_CYSCREEN);
  ViewX := 0; ViewY := 0;
  If FullScr Then
  Begin
    PutZ(LongInt(@NameZ2), 'MstscSess');
    SessWnd := CreateWindowExA(0, LongInt(@NameZ2), Z(Disp(RdpHost + ' - Connexion Bureau ' +
                               #224' distance')), WS_POPUP Or WS_VISIBLE, 0, 0, Sw, Sh, 0, 0, Inst, 0);
    SessCW := Sw; SessCH := Sh;
  End
  Else
  Begin
    St := WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN;
    W := FbW; H := FbH;
    { trop grand pour l'ecran : fenetre agrandie, barres de defilement }
    If (W > Sw - 8) Or (H > Sh - 58) Then
    Begin
      W := Sw - 8; H := Sh - 58;
    End;
    SessWnd := MainWindow('MstscSess', RdpHost + ' - Connexion Bureau ' + #224' distance',
                          St, W, H, False);
  End;
  If Old <> 0 Then Dummy := DestroyWindow(Old);
  HSb := 0; VSb := 0;
  Dummy := ShowWindow(SessWnd, 1);
  SetScrolls;
  Dummy := UpdateWindow(SessWnd);
  Dummy := SetFocus(SessWnd);
End;

{ ---- boite de connexion ---- }

Procedure SetBusy(B : Boolean);
Begin
  Busy := B;
  Dummy := EnableWindow(BConn, Ord(Not B));
  Dummy := EnableWindow(EHost, Ord(Not B));
  Dummy := EnableWindow(EUser, Ord(Not B));
  Dummy := EnableWindow(EPass, Ord(Not B));
  Dummy := EnableWindow(EDom, Ord(Not B));
  If B Then SetText(SStat, '') ;
End;

Procedure StartConnect;
Var U, P : String; K, S : LongInt;
Begin
  If Busy Then Exit;
  RdpHost := TrimS(CtlText(EHost));
  { serveur:port (3389 par defaut), comme mstsc }
  RdpPort := 3389;
  K := Pos(':', RdpHost);
  If K > 0 Then
  Begin
    Val(Copy(RdpHost, K + 1, 5), RdpPort, S);
    If (S <> 0) Or (RdpPort <= 0) Then RdpPort := 3389;
    RdpHost := Copy(RdpHost, 1, K - 1);
  End;
  KbdLay := GetKeyboardLayout(0) And $FFFF;
  If KbdLay = 0 Then KbdLay := $040C;
  U := TrimS(CtlText(EUser));
  RdpPass := CtlText(EPass);
  RdpDom := TrimS(CtlText(EDom));
  If RdpHost = '' Then
  Begin
    Dummy := Ask('Tapez le nom ou l''adresse IP de l''ordinateur distant.',
                 'Connexion Bureau '#224' distance', MB_ICONWARNING);
    Exit;
  End;
  { DOMAINE\utilisateur ou utilisateur@domaine }
  K := Pos('\', U);
  If K > 0 Then
  Begin
    RdpDom := Copy(U, 1, K - 1); U := Copy(U, K + 1, 255);
  End;
  RdpUser := U;
  RegWrite('Software\Microsoft\Terminal Server Client\Default', 'MRU0', TrimS(CtlText(EHost)));
  RegWrite('Software\Microsoft\Terminal Server Client\Servers\' + RdpHost,
           'UsernameHint', TrimS(CtlText(EUser)));
  If RdpDom <> '' Then
    RegWrite('Software\Pasdows\Mstsc', 'Domain', RdpDom);
  S := SendMessageA(LSize, LB_GETCURSEL, 0, 0);
  RegWrite('Software\Pasdows\Mstsc', 'Size', IStr(S));
  FullScr := False;
  Case S Of
    0 : Begin ReqW := 640; ReqH := 480; End;
    1 : Begin ReqW := 800; ReqH := 600; End;
    2 : Begin ReqW := 1024; ReqH := 768; End;
  Else
    Begin
      ReqW := GetSystemMetrics(SM_CXSCREEN); ReqH := GetSystemMetrics(SM_CYSCREEN);
      FullScr := True;
    End;
  End;
  FbW := ReqW; FbH := ReqH;
  NetStop := False; Active := False; FirstAct := False; Connected := False;
  Licensed := False; Tc.Sock := 0; FragLen := 0;
  SetBusy(True);
  Dummy := CreateThread(0, 0, LongInt(@RdpThread), 0, 0, LongInt(@K));
End;

Procedure PaintBanner(Dc : LongInt);
Var I : LongInt;
Begin
  Bar(Dc, 0, 0, 420, 64, $800000);
  For I := 0 To 5 Do Bar(Dc, 330 + I * 14, 10 + I * 9, 420, 64, $900000 + I * $100000);
  Bar(Dc, 0, 64, 420, 66, ClrShadow);
  Txt(Dc, 16, 12, 'Connexion Bureau '#224' distance', $FFFFFF, $800000);
  Txt(Dc, 16, 36, 'Pasdows 95 - client RDP (TLS, NLA)', $FFFF00, $800000);
End;

Function DlgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Dc : LongInt; S : String;
Begin
  DlgProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        PaintBanner(Dc);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND :
      Begin
        Bar(WP, 0, 66, 600, 600, ClrFace);
        DlgProc := 1;
      End;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_CONNECT : StartConnect;
        ID_QUIT :
          If Busy Then Disconnect Else Dummy := DestroyWindow(H);
      End;
    WM_RDPSTATUS : SetText(SStat, RdpStatus);
    WM_RDPACTIVE :
      Begin
        MakeSession;
        Dummy := ShowWindow(DlgWnd, 0);
        SendSync(0);
      End;
    WM_RDPEND :
      Begin
        If SessWnd <> 0 Then Dummy := DestroyWindow(SessWnd);
        SessWnd := 0;
        Dummy := ShowWindow(DlgWnd, 1);
        SetBusy(False);
        SetText(SStat, '');
        S := '';
        If RdpErr <> '' Then S := RdpErr
        Else If Not NetStop Then
          Case ErrInfo Of
            0, $C, $B : If Not FirstAct Then S := 'La connexion a '#233't'#233' interrompue.';
            1 : S := 'La session a '#233't'#233' d'#233'connect'#233'e par un administrateur.';
            2 : S := 'La session a '#233't'#233' ferm'#233'e par un administrateur.';
            3 : S := 'Session d'#233'connect'#233'e : d'#233'lai d''inactivit'#233' d'#233'pass'#233'.';
            4 : S := 'Session d'#233'connect'#233'e : d'#233'lai d''ouverture de session d'#233'pass'#233'.';
            5 : S := 'Un autre utilisateur s''est connect'#233' '#224' la session.';
            7 : S := 'Le serveur a refus'#233' la connexion.';
            9 : S := 'Vous n''avez pas l''autorisation d''ouvrir une session ' +
                     'Bureau '#224' distance (groupe Utilisateurs du Bureau '#224' distance).';
          Else
            S := 'La session a '#233't'#233' d'#233'connect'#233'e (code ' + HexS(ErrInfo) + ').';
          End;
        If S <> '' Then
          Dummy := Ask(S, 'Connexion Bureau '#224' distance', MB_ICONERROR);
        Dummy := SetFocus(EHost);
      End;
    WM_CLOSE :
      Begin
        If Busy Then Disconnect;
        Dummy := DestroyWindow(H);
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    DlgProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Procedure Lbl(T : String; Y : LongInt);
Begin
  Dummy := Ctl(DlgWnd, 'STATIC', T, 0, 16, Y + 3, 150, 18, 0);
End;

Var
  K : LongInt;
  S, Hs : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Dummy := WSAStartup($0101, LongInt(@TlCert[0]));
  InitializeCriticalSection(LongInt(@SendCs[0]));
  Tx := NewMem(70000); Rx := NewMem(70000); InB := NewMem(256);
  Pool := NewMem(16384 * 8); Wk1 := NewMem(16384); Wk2 := NewMem(16384);
  Wk3 := NewMem(16384);
  Frag := NewMem(4194304 + 64); DecB := NewMem(4194304 + 64);
  TlHs := PTlHsBuf(TlNew(SizeOf(TlHsBuf)));
  TlInit;
  Fb := 0; FbW := 0; FbH := 0; SessWnd := 0; Busy := False; HSb := 0; VSb := 0;
  For K := 0 To 255 Do
    Pal565[K] := ((K Shr 5) Shl 13) Or (((K Shr 2) And 7) Shl 8) Or ((K And 3) Shl 3);
  RegClass('MstscDlg', LongInt(@DlgProc), 0);
  RegClass('MstscSess', LongInt(@SessProc), 0);
  DlgWnd := MainWindow('MstscDlg', 'Connexion Bureau '#224' distance', WS_POPUP Or WS_CAPTION Or
                       WS_SYSMENU Or WS_MINIMIZEBOX, 420, 318, False);
  If DlgWnd = 0 Then ExitProcess(1);
  Wnd := DlgWnd;
  Lbl('Ordinateur :', 78);
  EHost := Ctl(DlgWnd, 'EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP, 170, 78, 232, 22, ID_HOST);
  Lbl('Nom d''utilisateur :', 106);
  EUser := Ctl(DlgWnd, 'EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP, 170, 106, 232, 22, ID_USER);
  Lbl('Mot de passe :', 134);
  EPass := Ctl(DlgWnd, 'EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or ES_PASSWORD Or WS_TABSTOP, 170, 134,
               232, 22, ID_PASS);
  Lbl('Domaine :', 162);
  EDom := Ctl(DlgWnd, 'EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP, 170, 162, 232, 22, ID_DOM);
  Lbl('Taille de l'''#233'cran :', 190);
  LSize := Ctl(DlgWnd, 'LISTBOX', '', WS_BORDER Or LBS_NOTIFY Or WS_TABSTOP, 170, 190, 232, 70, ID_SIZE);
  Dummy := SendMessageA(LSize, LB_ADDSTRING, 0, Z('640 x 480'));
  Dummy := SendMessageA(LSize, LB_ADDSTRING, 0, Z('800 x 600'));
  Dummy := SendMessageA(LSize, LB_ADDSTRING, 0, Z('1024 x 768'));
  Dummy := SendMessageA(LSize, LB_ADDSTRING, 0, Z(Disp('Plein '#233'cran')));
  SStat := Ctl(DlgWnd, 'STATIC', '', 0, 16, 266, 220, 40, ID_STAT);
  BConn := Ctl(DlgWnd, 'BUTTON', 'Connexion', BS_DEFPUSHBUTTON Or WS_TABSTOP, 236, 280, 84, 26, ID_CONNECT);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Quitter', BS_PUSHBUTTON Or WS_TABSTOP, 326, 280, 78, 26, ID_QUIT);
  { valeurs de la derniere connexion }
  Hs := RegRead('Software\Microsoft\Terminal Server Client\Default', 'MRU0');
  SetText(EHost, Hs);
  If Hs <> '' Then
    SetText(EUser, RegRead('Software\Microsoft\Terminal Server Client\Servers\' + Hs, 'UsernameHint'));
  S := RegRead('Software\Pasdows\Mstsc', 'Domain');
  If Pos('\', CtlText(EUser)) = 0 Then SetText(EDom, S);
  S := RegRead('Software\Pasdows\Mstsc', 'Size');
  K := 1;
  If GetSystemMetrics(SM_CXSCREEN) < 1024 Then K := 3;
  If (S <> '') And (S[1] >= '0') And (S[1] <= '3') Then K := Ord(S[1]) - 48;
  Dummy := SendMessageA(LSize, LB_SETCURSEL, K, 0);
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := UpdateWindow(DlgWnd);
  If Hs = '' Then Dummy := SetFocus(EHost) Else Dummy := SetFocus(EPass);
  MsgLoop;
  ExitProcess(0);
END.
