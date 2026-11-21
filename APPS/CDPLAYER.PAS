{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: CDPLAYER - Lecteur CD de Pasdows 95 (Win32), comme celui
                des Accessoires de Windows 95 (Multimedia).
}

Program CDPLAYER;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\CDPLAYER.PAS CDPLAYER.EXE

  Lecteur de CD audio par MCI (mciSendStringA, peripherique cdaudio),
  comme le Lecteur CD de Windows 95 :
  - afficheur : piste et temps en chiffres a sept segments (temps ecoule
    ou restant de la piste, ou restant du disque : menu Affichage) ;
  - boutons Lecture, Pause, Arret, piste precedente, retour et avance
    rapides (5 s), piste suivante, Ejecter ;
  - Artiste, Titre et Piste : un clic sur la piste ouvre la liste des
    pistes (avec leur duree) ;
  - Options : lecture aleatoire, lecture continue, introduction (les
    10 premieres secondes de chaque piste) ;
  - barre d'etat : duree totale du disque et de la piste.
  L'etat du lecteur est relu deux fois par seconde : un disque insere ou
  ejecte est vu tout de suite. Sous Pasdows, le noyau lit la musique en
  numerique (READ CD) et la joue par la carte son. }

Const
  CW0 = 380; CH0 = 206;
  CM_QUIT = 101; CM_ELAPSED = 201; CM_TREMAIN = 202; CM_DREMAIN = 203;
  CM_RANDOM = 301; CM_CONT = 302; CM_INTRO = 303; CM_ABOUT = 401;
  CM_TRACK0 = 1000;
  { boutons : 0 lecture, 1 pause, 2 arret, 3 piste precedente, 4 retour,
    5 avance, 6 piste suivante, 7 ejecter }
  NBtn = 8;

Var
  MemDC, MemBmp, FontS, MenuBar, MOpt, MView : LongInt;
  NTrk, CurTrk, PosSec, Mode, ShowMode, BtnDown, Ticks0 : LongInt;
  TrkLen : Array[1..99] Of LongInt;               { secondes }
  TrkAudio : Array[1..99] Of Boolean;
  Media, Loaded, Random0, Cont, Intro, WasPlay : Boolean;
  Seed, IntroT : LongInt;
  Ret : Array[0..255] Of Byte;

Function mciSendStringA(Cmd, R, N, Cb : LongInt) : LongInt; stdcall;
  external 'winmm.dll' name 'mciSendStringA';
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
{ MCI                                                                   }
{ ==================================================================== }

Function Mci(S : String) : String;
Begin
  Ret[0] := 0;
  If mciSendStringA(Z(S), LongInt(@Ret), 255, Wnd) <> 0 Then Mci := ''
  Else Mci := GetZ(LongInt(@Ret));
End;

{ "tt:mm:ss:ff" ou "mm:ss:ff" -> nombres }
Procedure Parts(S : String; Var A, B, C, D : LongInt);
Var V, N, I : LongInt; P : Array[0..3] Of LongInt;
Begin
  For I := 0 To 3 Do P[I] := 0;
  N := 0; V := 0;
  For I := 1 To Length(S) + 1 Do
    If (I > Length(S)) Or (S[I] = ':') Then
    Begin
      If N <= 3 Then P[N] := V;
      Inc(N); V := 0;
    End
    Else If (S[I] >= '0') And (S[I] <= '9') Then V := V * 10 + Ord(S[I]) - 48;
  A := P[0]; B := P[1]; C := P[2]; D := P[3];
End;

Function NumOf(S : String) : LongInt;
Var A, B, C, D : LongInt;
Begin
  Parts(S, A, B, C, D);
  NumOf := A;
End;

Function Rnd(N : LongInt) : LongInt;
Begin
  Seed := (Seed * 1103515245 + 12345) And $7FFFFFFF;
  Rnd := (Seed Shr 8) Mod MaxI(1, N);
End;

{ table des pistes (duree en secondes) }
Procedure LoadDisc;
Var T, A, B, C, D : LongInt;
Begin
  Loaded := False; NTrk := 0;
  If Not Media Then Exit;
  NTrk := NumOf(Mci('status cd number of tracks'));
  If NTrk > 99 Then NTrk := 99;
  For T := 1 To NTrk Do
  Begin
    Parts(Mci('status cd length track ' + IStr(T)), A, B, C, D);
    TrkLen[T] := A * 60 + B;
    TrkAudio[T] := Mci('status cd type track ' + IStr(T)) <> 'other';
  End;
  Loaded := NTrk > 0;
  CurTrk := 1; PosSec := 0;
End;

Function AnyAudio : Boolean;
Var T : LongInt;
Begin
  AnyAudio := False;
  For T := 1 To NTrk Do If TrkAudio[T] Then AnyAudio := True;
End;

Function DiscLen : LongInt;
Var T, N : LongInt;
Begin
  N := 0;
  For T := 1 To NTrk Do N := N + TrkLen[T];
  DiscLen := N;
End;

{ lecture de la piste T (jusqu'a la fin du disque, ou de la piste
  seule en lecture aleatoire ou en introduction) }
Procedure PlayTrack(T : LongInt);
Begin
  If Not Loaded Then Exit;
  If (T < 1) Or (T > NTrk) Then T := 1;
  CurTrk := T; PosSec := 0;
  If (Random0 Or Intro) And (T < NTrk) Then
    Dummy := Ord(Mci('play cd from ' + IStr(T) + ' to ' + IStr(T + 1)) = '')
  Else Dummy := Ord(Mci('play cd from ' + IStr(T)) = '');
  IntroT := GetTickCount;
  WasPlay := True;
End;

Procedure PlayAt(T, Sec : LongInt);
Begin
  If Not Loaded Then Exit;
  If Sec < 0 Then Sec := 0;
  CurTrk := T;
  Dummy := Ord(Mci('play cd from ' + IStr(T) + ':' + Two(Sec Div 60) + ':' + Two(Sec Mod 60) + ':00') = '');
  WasPlay := True;
End;

Function NextTrack : LongInt;
Var T : LongInt;
Begin
  If Random0 Then NextTrack := 1 + Rnd(NTrk)
  Else
  Begin
    T := CurTrk + 1;
    If T > NTrk Then T := 1;
    NextTrack := T;
  End;
End;

{ etat : media, mode, position (deux fois par seconde) }
Procedure Poll;
Var S : String; A, B, C, D : LongInt; M : Boolean;
Begin
  M := Mci('status cd media present') = 'true';
  If M <> Media Then
  Begin
    Media := M;
    If Media Then LoadDisc Else Begin Loaded := False; NTrk := 0; End;
  End;
  If Media And Not Loaded Then LoadDisc;
  S := Mci('status cd mode');
  If S = 'playing' Then Mode := 1
  Else If S = 'paused' Then Mode := 2
  Else Mode := 0;
  If Loaded Then
  Begin
    Parts(Mci('status cd position'), A, B, C, D);
    If (A >= 1) And (A <= NTrk) Then CurTrk := A;
    PosSec := B * 60 + C;
  End;
  { fin de lecture : suite (aleatoire, introduction, continue) }
  If WasPlay And (Mode = 0) And Loaded Then
  Begin
    WasPlay := False;
    If Random0 Or Intro Then
    Begin
      If (CurTrk < NTrk) Or Cont Or Random0 Then PlayTrack(NextTrack);
    End
    Else If Cont Then PlayTrack(1);
  End;
  If Intro And (Mode = 1) And (GetTickCount - IntroT > 10000) Then
  Begin
    IntroT := GetTickCount;
    PlayTrack(NextTrack);
  End;
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }

{ chiffre a sept segments (14 x 26) }
Procedure Seg7(Dc, X, Y, N, C : LongInt);
Const Mask : Array[0..9] Of Byte = ($3F, $06, $5B, $4F, $66, $6D, $7D, $07, $7F, $6F);
Var M : LongInt;
Begin
  If (N < 0) Or (N > 9) Then Exit;
  M := Mask[N];
  If (M And 1) <> 0 Then Bar(Dc, X + 2, Y, X + 13, Y + 2, C);
  If (M And 2) <> 0 Then Bar(Dc, X + 12, Y + 2, X + 15, Y + 12, C);
  If (M And 4) <> 0 Then Bar(Dc, X + 12, Y + 14, X + 15, Y + 24, C);
  If (M And 8) <> 0 Then Bar(Dc, X + 2, Y + 24, X + 13, Y + 26, C);
  If (M And 16) <> 0 Then Bar(Dc, X, Y + 14, X + 3, Y + 24, C);
  If (M And 32) <> 0 Then Bar(Dc, X, Y + 2, X + 3, Y + 12, C);
  If (M And 64) <> 0 Then Bar(Dc, X + 2, Y + 12, X + 13, Y + 14, C);
End;

Procedure BtnRect(I : LongInt; Var X1, Y1, X2, Y2 : LongInt);
Begin
  If I < 3 Then
  Begin
    Y1 := 10; Y2 := 38;
    Case I Of
      0 : Begin X1 := 212; X2 := 282; End;
      1 : Begin X1 := 284; X2 := 326; End;
    Else
      Begin X1 := 328; X2 := 370; End;
    End;
  End
  Else
  Begin
    Y1 := 40; Y2 := 66;
    X1 := 212 + (I - 3) * 32 + Ord(I = 7) * 2; X2 := X1 + 30;
  End;
End;

{ triangle plein : pointe a droite (D 1) ou a gauche (-1), en haut (2) }
Procedure Tri(Dc, X, Y, H, D, C : LongInt);
Var K, W : LongInt;
Begin
  For K := -H To H Do
  Begin
    W := H - Abs(K);
    If D = 2 Then Bar(Dc, X + K, Y + Abs(K) - H, X + K + 1, Y + 1, C)
    Else If D > 0 Then Bar(Dc, X, Y + K, X + W + 1, Y + K + 1, C)
    Else Bar(Dc, X - W, Y + K, X + 1, Y + K + 1, C);
  End;
End;

Procedure DrawBtn(Dc, I : LongInt);
Var X1, Y1, X2, Y2, Cx, Cy, Dn, C : LongInt; On : Boolean;
Begin
  BtnRect(I, X1, Y1, X2, Y2);
  On := ((I = 0) And (Mode = 1)) Or ((I = 1) And (Mode = 2));
  Bar(Dc, X1, Y1, X2, Y2, ClrFace);
  Bevel(Dc, X1, Y1, X2, Y2, Not ((BtnDown = I) Or On));
  Dn := Ord((BtnDown = I) Or On);
  Cx := (X1 + X2) Div 2 + Dn; Cy := (Y1 + Y2) Div 2 + Dn;
  If Loaded Or (I = 7) Then C := ClrDark Else C := ClrShadow;
  Case I Of
    0 : Begin If Mode = 1 Then C := $008000; Tri(Dc, Cx - 4, Cy, 7, 1, C); End;
    1 : Begin Bar(Dc, Cx - 5, Cy - 6, Cx - 1, Cy + 7, C); Bar(Dc, Cx + 2, Cy - 6, Cx + 6, Cy + 7, C); End;
    2 : Bar(Dc, Cx - 6, Cy - 6, Cx + 7, Cy + 7, C);
    3 : Begin Bar(Dc, Cx - 8, Cy - 5, Cx - 6, Cy + 6, C); Tri(Dc, Cx - 1, Cy, 5, -1, C); Tri(Dc, Cx + 6, Cy, 5, -1, C); End;
    4 : Begin Tri(Dc, Cx - 1, Cy, 5, -1, C); Tri(Dc, Cx + 6, Cy, 5, -1, C); End;
    5 : Begin Tri(Dc, Cx - 6, Cy, 5, 1, C); Tri(Dc, Cx + 1, Cy, 5, 1, C); End;
    6 : Begin Tri(Dc, Cx - 7, Cy, 5, 1, C); Tri(Dc, Cx, Cy, 5, 1, C); Bar(Dc, Cx + 6, Cy - 5, Cx + 8, Cy + 6, C); End;
    7 : Begin Tri(Dc, Cx, Cy + 1, 6, 2, C); Bar(Dc, Cx - 6, Cy + 3, Cx + 7, Cy + 6, C); End;
  End;
End;

Function TimeTxt(S : LongInt) : String;
Begin
  If S < 0 Then S := 0;
  TimeTxt := Two(S Div 60) + ':' + Two(S Mod 60);
End;

Procedure Field(Dc, Y : LongInt; Lab, S : String);
Begin
  Txt(Dc, 8, Y + 4, Lab, ClrDark, ClrFace);
  Bar(Dc, 80, Y, CW0 - 8, Y + 24, ClrWin);
  Bevel(Dc, 80, Y, CW0 - 8, Y + 24, False);
  Txt(Dc, 86, Y + 4, S, ClrDark, ClrWin);
End;

Procedure DrawAll(Dc : LongInt);
Var I, S, X, G : LongInt; T, A : String;
Begin
  Bar(Dc, 0, 0, CW0, CH0, ClrFace);
  { afficheur }
  Bar(Dc, 8, 10, 204, 66, ClrDark);
  Bevel(Dc, 8, 10, 204, 66, False);
  G := $00FFFF;
  If Loaded And AnyAudio Then
  Begin
    S := PosSec;
    Case ShowMode Of
      1 : S := TrkLen[CurTrk] - PosSec;
      2 : Begin
            S := TrkLen[CurTrk] - PosSec;
            For I := CurTrk + 1 To NTrk Do S := S + TrkLen[I];
          End;
    End;
    X := 20;
    Bar(Dc, X, 25, X + 2, 53, G); Bar(Dc, X, 25, X + 6, 27, G); Bar(Dc, X, 51, X + 6, 53, G);
    Seg7(Dc, X + 8, 26, CurTrk Div 10, G); Seg7(Dc, X + 26, 26, CurTrk Mod 10, G);
    Bar(Dc, X + 48, 25, X + 50, 53, G); Bar(Dc, X + 44, 25, X + 50, 27, G); Bar(Dc, X + 44, 51, X + 50, 53, G);
    If ShowMode > 0 Then Bar(Dc, X + 60, 38, X + 68, 41, G);
    Seg7(Dc, X + 72, 26, (S Div 60) Div 10 Mod 10, G); Seg7(Dc, X + 90, 26, (S Div 60) Mod 10, G);
    Bar(Dc, X + 110, 32, X + 113, 35, G); Bar(Dc, X + 110, 44, X + 113, 47, G);
    Seg7(Dc, X + 118, 26, (S Mod 60) Div 10, G); Seg7(Dc, X + 136, 26, S Mod 10, G);
  End
  Else
  Begin
    If Not Media Then T := 'Pas de disque'
    Else If Loaded Then T := 'Disque de donn'#233'es'
    Else T := 'Lecture du disque...';
    Txt(Dc, 106 - Length(T) * 4, 30, T, G, ClrDark);
  End;
  For I := 0 To NBtn - 1 Do DrawBtn(Dc, I);
  { artiste, titre, piste }
  If Not Media Then A := 'Ins'#233'rez un disque audio'
  Else If Loaded And AnyAudio Then A := 'Disque audio (' + IStr(NTrk) + ' pistes)'
  Else A := 'Pas un disque audio';
  Field(Dc, 76, 'Artiste :', A);
  If Loaded And AnyAudio Then T := '<Titre inconnu>' Else T := '';
  Field(Dc, 104, 'Titre :', T);
  If Loaded And AnyAudio Then T := 'Piste ' + IStr(CurTrk) + '  <' + Two(CurTrk) + '>' Else T := '';
  Field(Dc, 132, 'Piste :', T);
  If Loaded Then
    For I := 0 To 3 Do Bar(Dc, CW0 - 22 + I, 141 + I, CW0 - 14 - I, 142 + I, ClrDark);
  { barre d'etat }
  Bar(Dc, 0, CH0 - 24, CW0, CH0 - 23, ClrShadow);
  Bar(Dc, 0, CH0 - 23, CW0, CH0 - 22, ClrHi);
  Bevel(Dc, 4, CH0 - 20, 196, CH0 - 2, False);
  Bevel(Dc, 200, CH0 - 20, CW0 - 4, CH0 - 2, False);
  If Loaded And AnyAudio Then
  Begin
    Txt(Dc, 8, CH0 - 19, 'Dur'#233'e totale : ' + TimeTxt(DiscLen) + ' m:s', ClrDark, ClrFace);
    Txt(Dc, 204, CH0 - 19, 'Piste : ' + TimeTxt(TrkLen[CurTrk]) + ' m:s', ClrDark, ClrFace);
  End;
End;

Procedure Redraw;
Var Dc : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW0, CH0, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Commandes                                                             }
{ ==================================================================== }

Procedure Button(I : LongInt);
Begin
  If (I <> 7) And Not Loaded Then Exit;
  Case I Of
    0 : If Mode = 2 Then Dummy := Ord(Mci('resume cd') = '')
        Else If Mode = 0 Then PlayTrack(CurTrk);
    1 : If Mode = 1 Then Dummy := Ord(Mci('pause cd') = '')
        Else If Mode = 2 Then Dummy := Ord(Mci('resume cd') = '');
    2 : Begin
          WasPlay := False;
          Dummy := Ord(Mci('stop cd') = '');
          Dummy := Ord(Mci('seek cd to 1') = '');
          CurTrk := 1; PosSec := 0;
        End;
    3 : If (PosSec > 2) And (Mode = 1) Then PlayTrack(CurTrk)
        Else If Mode = 1 Then PlayTrack(MaxI(1, CurTrk - 1))
        Else Begin CurTrk := MaxI(1, CurTrk - 1); PosSec := 0; End;
    4 : If Mode = 1 Then PlayAt(CurTrk, PosSec - 5);
    5 : If Mode = 1 Then PlayAt(CurTrk, MinI(TrkLen[CurTrk] - 1, PosSec + 5));
    6 : If Mode = 1 Then PlayTrack(NextTrack)
        Else Begin CurTrk := MinI(NTrk, CurTrk + 1); PosSec := 0; End;
    7 : Begin
          WasPlay := False;
          If Media Then Dummy := Ord(Mci('set cd door open') = '')
          Else Dummy := Ord(Mci('set cd door closed') = '');
          Media := False; Loaded := False; NTrk := 0;
        End;
  End;
  Poll;
  Redraw;
End;

Procedure TrackMenu;
Var M, T : LongInt; Pt : Array[0..1] Of LongInt;
Begin
  If Not Loaded Then Exit;
  M := CreatePopupMenu;
  For T := 1 To NTrk Do
    Dummy := AppendMenuA(M, MF_STRING Or (MF_CHECKED * Ord(T = CurTrk)), CM_TRACK0 + T,
                         Z(Disp('Piste ' + IStr(T) + '  <' + Two(T) + '>   ' + TimeTxt(TrkLen[T]))));
  Pt[0] := 80; Pt[1] := 156;
  Dummy := ClientToScreen(Wnd, LongInt(@Pt));
  Dummy := TrackPopupMenu(M, 0, Pt[0], Pt[1], 0, Wnd, 0);
  Dummy := DestroyMenu(M);
End;

Procedure SetMarks;
Begin
  MCheck(MView, CM_ELAPSED, ShowMode = 0);
  MCheck(MView, CM_TREMAIN, ShowMode = 1);
  MCheck(MView, CM_DREMAIN, ShowMode = 2);
  MCheck(MOpt, CM_RANDOM, Random0);
  MCheck(MOpt, CM_CONT, Cont);
  MCheck(MOpt, CM_INTRO, Intro);
End;

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_ELAPSED : ShowMode := 0;
    CM_TREMAIN : ShowMode := 1;
    CM_DREMAIN : ShowMode := 2;
    CM_RANDOM : Random0 := Not Random0;
    CM_CONT : Cont := Not Cont;
    CM_INTRO : Intro := Not Intro;
    CM_ABOUT : Dummy := Ask('Lecteur CD de Pasdows 95'#10#10'Musique des disques audio par MCI (cdaudio) ; ' +
                            'programme '#233'crit en Pascal et compil'#233' par WPC.', #192' propos du Lecteur CD',
                            MB_OK Or MB_ICONINFO);
  Else
    If (Id > CM_TRACK0) And (Id <= CM_TRACK0 + NTrk) Then
    Begin
      If Mode = 1 Then PlayTrack(Id - CM_TRACK0)
      Else Begin CurTrk := Id - CM_TRACK0; PosSec := 0; End;
    End;
  End;
  SetMarks;
  Redraw;
End;

Function HitBtn(X, Y : LongInt) : LongInt;
Var I, X1, Y1, X2, Y2 : LongInt;
Begin
  HitBtn := -1;
  For I := 0 To NBtn - 1 Do
  Begin
    BtnRect(I, X1, Y1, X2, Y2);
    If (X >= X1) And (X < X2) And (Y >= Y1) And (Y < Y2) Then HitBtn := I;
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Dc, I, X, Y : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW0, CH0, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_TIMER : Begin Poll; Redraw; End;
    WM_LBUTTONDOWN :
      Begin
        X := S16(LP); Y := S16(LP Shr 16);
        I := HitBtn(X, Y);
        If I >= 0 Then
        Begin
          BtnDown := I; Dummy := SetCapture(H); Redraw;
        End
        Else If (Y >= 132) And (Y < 156) And (X >= 80) Then TrackMenu;
      End;
    WM_LBUTTONUP :
      If BtnDown >= 0 Then
      Begin
        I := BtnDown; BtnDown := -1;
        Dummy := ReleaseCapture;
        If HitBtn(S16(LP), S16(LP Shr 16)) = I Then Button(I) Else Redraw;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_SPACE : If Mode = 1 Then Button(1) Else Button(0);
        VK_LEFT : Button(3);
        VK_RIGHT : Button(6);
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
  Dc, MDisc, MHelp : LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Seed := GetTickCount Or 1;
  BtnDown := -1; ShowMode := 0; Mode := 0; NTrk := 0; CurTrk := 1;
  Media := False; Loaded := False; Random0 := False; Cont := False; Intro := False; WasPlay := False;
  RegClass('CdPlayerWnd', LongInt(@MainProc), 0);
  Wnd := MainWindow('CdPlayerWnd', 'Lecteur CD', WS_CAPTION Or WS_SYSMENU Or WS_MINIMIZEBOX, CW0, CH0, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MDisc := CreatePopupMenu; MView := CreatePopupMenu; MOpt := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MDisc, CM_QUIT, '~Quitter');
  MItem(MView, CM_ELAPSED, 'Temps ~'#233'coul'#233' de la piste');
  MItem(MView, CM_TREMAIN, 'Temps ~restant de la piste');
  MItem(MView, CM_DREMAIN, 'Temps restant du ~disque');
  MItem(MOpt, CM_RANDOM, 'Lecture ~al'#233'atoire');
  MItem(MOpt, CM_CONT, 'Lecture ~continue');
  MItem(MOpt, CM_INTRO, '~Introduction (10 s par piste)');
  MItem(MHelp, CM_ABOUT, #192' ~propos du Lecteur CD');
  MSub(MenuBar, MDisc, '~Disque');
  MSub(MenuBar, MView, '~Affichage');
  MSub(MenuBar, MOpt, '~Options');
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  SetMarks;
  Dc := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, CW0, CH0);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  If Mci('open cdaudio alias cd shareable') = '' Then
    Dummy := Ask('Le lecteur de CD-ROM n''est pas disponible (MCI cdaudio).', 'Lecteur CD', MB_OK Or MB_ICONWARNING);
  Dummy := Ord(Mci('set cd time format tmsf') = '');
  Poll;
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetTimer(Wnd, 1, 500, 0);
  MsgLoop;
  Dummy := Ord(Mci('close cd') = '');
  ExitProcess(0);
END.
