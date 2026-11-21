{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: MSTASK - Planificateur de taches de Pasdows 95 (Win32) :
                Taches planifiees et agent.
}

Program MSTASK;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\MSTASK.PAS MSTASK.EXE

  Comme le Planificateur de taches de Windows 98 (Accessoires, Outils
  systeme, Taches planifiees) :
  - la liste des taches : nom, planification, prochaine et derniere
    execution, etat ; "Ajouter une tache planifiee", Proprietes (double
    clic), Supprimer, Executer maintenant ;
  - une tache lance une ligne de commande (programme et arguments ;
    Parcourir) une seule fois (date et heure), chaque jour, certains
    jours de la semaine, ou au demarrage de Pasdows ; elle peut etre
    desactivee ; Avance, Suspendre le Planificateur de taches ;
  - les taches sont gardees dans TACHES.DAT (dossier du programme) ;
  - l'agent (MSTASK /AGENT, sans fenetre visible, une seule instance :
    mutex PasdowsTaskAgent) verifie les taches toutes les 15 secondes et
    lance celles qui sont dues (ShellExecute) ; il est inscrit dans
    HKLM\Software\Microsoft\Windows\CurrentVersion\Run, que le noyau de
    Pasdows lance au demarrage (les taches "au demarrage" partent
    alors). }

Const
  MaxT = 64;
  CM_NEW = 101; CM_PROPS = 102; CM_DELETE = 103; CM_RUN = 104; CM_QUIT = 105;
  CM_PAUSE = 201; CM_ABOUT = 301;
  ID_OK = 1; ID_CANCEL = 2; ID_BROWSE = 30;
  ID_ONCE = 40; ID_DAILY = 41; ID_WEEKLY = 42; ID_BOOT = 43;
  WM_TIMER2 = $0113;
  RowH = 18; HdrH = 20; StH = 22; TopH = 0;
  WS_GROUP = $20000; BS_AUTORADIOBUTTON = 9; BS_GROUPBOX = 7;

Type
  TTask = Record
    Name : String[63];
    Cmd : String[200];
    Kind, Hour, Min, Date, Days : LongInt;      { Date : AAAAMMJJ ; Days : bit 0 dimanche }
    Enabled : Boolean;
    Last : LongInt;                             { minutes depuis 2000 (0 : jamais) }
  End;
  PTask = ^TTask;

Var
  T : Array[0..MaxT - 1] Of PTask;
  NT, Sel, Top, CW, CH, MemDC, MemBmp, FontS, MAdv : LongInt;
  DataPath, ExeDir : String;
  Paused, Agent, Boot : Boolean;
  DlgW, DlgIdx : LongInt;
  Ed : Array[0..15] Of LongInt;
  St : Array[0..7] Of Word;
  LineB : Array[0..511] Of Byte;
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

Procedure GetLocalTime(P : LongInt); stdcall; external 'kernel32.dll' name 'GetLocalTime';
Function GetLastError : LongInt; stdcall; external 'kernel32.dll' name 'GetLastError';
Function CreateMutexA(S, O, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateMutexA';
Function OpenMutexA(A, I, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'OpenMutexA';
Function WinExec(C, S : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'WinExec';
Function ShellExecuteA(H, Op, F, P, D, Sh : LongInt) : LongInt; stdcall; external 'shell32.dll' name 'ShellExecuteA';
Function RegCreateKeyExA(K, Sub, R, Cls, Opt, Sam, Sec, PRes, PDisp : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCreateKeyExA';
Function RegSetValueExA(K, Nm, R, Typ, Data, N : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegSetValueExA';
Function GetOpenFileNameA(P : LongInt) : LongInt; stdcall; external 'comdlg32.dll' name 'GetOpenFileNameA';
Function RegFlushKey(K : LongInt) : LongInt; stdcall; external 'advapi32.dll' name 'RegFlushKey';

{ ==================================================================== }
{ Dates                                                                 }
{ ==================================================================== }

Function DaysIn(Y, M : LongInt) : LongInt;
Begin
  Case M Of
    4, 6, 9, 11 : DaysIn := 30;
    2 : If (Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or (Y Mod 400 = 0)) Then DaysIn := 29 Else DaysIn := 28;
  Else
    DaysIn := 31;
  End;
End;

{ jour de la semaine (0 dimanche) }
Function Dow(Y, M, D : LongInt) : LongInt;
Var K : LongInt;
Begin
  If M < 3 Then Begin M := M + 12; Dec(Y); End;
  K := (D + (13 * (M + 1)) Div 5 + Y + Y Div 4 - Y Div 100 + Y Div 400) Mod 7;
  Dow := (K + 6) Mod 7;
End;

Procedure NextDay(Var Y, M, D : LongInt);
Begin
  Inc(D);
  If D > DaysIn(Y, M) Then
  Begin
    D := 1; Inc(M);
    If M > 12 Then Begin M := 1; Inc(Y); End;
  End;
End;

{ horodatage comparable : minutes depuis l'an 2000 (mois de 31 jours,
  annees de 12 mois) }
Function Stamp(Y, M, D, H, Mi : LongInt) : LongInt;
Begin
  If Y >= 2000 Then Y := Y - 2000;
  Stamp := (((Y * 12 + M - 1) * 31 + D - 1) * 24 + H) * 60 + Mi;
End;

Function NowStamp : LongInt;
Begin
  GetLocalTime(LongInt(@St));
  NowStamp := Stamp(St[0], St[1], St[3], St[4], St[5]);
End;

Function StampText(S : LongInt) : String;
Var Y, M, D, H, Mi : LongInt;
Begin
  If S <= 0 Then Begin StampText := 'Jamais'; Exit; End;
  Mi := S Mod 60; S := S Div 60;
  H := S Mod 24; S := S Div 24;
  D := S Mod 31 + 1; S := S Div 31;
  M := S Mod 12 + 1; Y := 2000 + S Div 12;
  StampText := Two(H) + ':' + Two(Mi) + ' ' + Two(D) + '/' + Two(M) + '/' + IStr(Y);
End;

Function DayName(K : LongInt) : String;
Begin
  Case K Of
    0 : DayName := 'Di'; 1 : DayName := 'Lu'; 2 : DayName := 'Ma'; 3 : DayName := 'Me';
    4 : DayName := 'Je'; 5 : DayName := 'Ve';
  Else
    DayName := 'Sa';
  End;
End;

{ prochaine execution (horodatage) apres maintenant ; -1 : aucune }
Function NextRun(I : LongInt) : LongInt;
Var Y, M, D, K, S, Nw : LongInt;
Begin
  NextRun := -1;
  If Not T[I]^.Enabled Then Exit;
  GetLocalTime(LongInt(@St));
  Nw := Stamp(St[0], St[1], St[3], St[4], St[5]);
  Case T[I]^.Kind Of
    0 :
      Begin
        Y := T[I]^.Date Div 10000; M := (T[I]^.Date Div 100) Mod 100; D := T[I]^.Date Mod 100;
        S := Stamp(Y, M, D, T[I]^.Hour, T[I]^.Min);
        If (S > T[I]^.Last) And (S >= Nw) Then NextRun := S;
      End;
    1, 2 :
      Begin
        Y := St[0]; M := St[1]; D := St[3];
        For K := 0 To 8 Do
        Begin
          S := Stamp(Y, M, D, T[I]^.Hour, T[I]^.Min);
          If (S >= Nw) And ((T[I]^.Kind = 1) Or ((T[I]^.Days And (1 Shl Dow(Y, M, D))) <> 0)) Then
          Begin
            NextRun := S;
            Exit;
          End;
          NextDay(Y, M, D);
        End;
      End;
  End;
End;

Function SchedText(I : LongInt) : String;
Var S : String; K : LongInt;
Begin
  Case T[I]^.Kind Of
    0 : SchedText := Two(T[I]^.Hour) + ':' + Two(T[I]^.Min) + ' le ' + Two(T[I]^.Date Mod 100) + '/' +
                     Two((T[I]^.Date Div 100) Mod 100) + '/' + IStr(T[I]^.Date Div 10000);
    1 : SchedText := Two(T[I]^.Hour) + ':' + Two(T[I]^.Min) + ' chaque jour';
    2 :
      Begin
        S := '';
        For K := 1 To 7 Do
          If (T[I]^.Days And (1 Shl (K Mod 7))) <> 0 Then
          Begin
            If S <> '' Then S := S + ',';
            S := S + DayName(K Mod 7);
          End;
        SchedText := Two(T[I]^.Hour) + ':' + Two(T[I]^.Min) + ' ' + S;
      End;
  Else
    SchedText := 'Au d'#233'marrage';
  End;
End;

{ ==================================================================== }
{ Fichier TACHES.DAT                                                    }
{ ==================================================================== }

Function NewTask : LongInt;
Var P : PTask;
Begin
  NewTask := -1;
  If NT >= MaxT Then Exit;
  GetMem(P, SizeOf(TTask));
  P^.Name := ''; P^.Cmd := ''; P^.Kind := 1; P^.Hour := 9; P^.Min := 0; P^.Date := 0; P^.Days := 62;
  P^.Enabled := True; P^.Last := 0;
  T[NT] := P;
  NewTask := NT;
  Inc(NT);
End;

Function NumOf(S : String) : LongInt;
Var V, E : LongInt;
Begin
  Val(S, V, E);
  If E <> 0 Then V := 0;
  NumOf := V;
End;

Procedure Load;
Var H, N, K, I, F, P : LongInt; S, Fld : String; Pp : PByt;
Begin
  For K := 0 To NT - 1 Do FreeMem(T[K], SizeOf(TTask));
  NT := 0; Paused := False;
  H := CreateFileA(Z(DataPath), GENERIC_READ, 3, 0, OPEN_EXISTING, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  S := '';
  Repeat
    N := 0;
    Dummy := ReadFile(H, LongInt(@LineB), 1, LongInt(@N), 0);
    If (N = 0) Or (LineB[0] = 10) Then
    Begin
      If S = 'PAUSE' Then Paused := True
      Else If (S <> '') And (S[1] <> ';') Then
      Begin
        I := NewTask;
        If I < 0 Then Break;
        S := S + #9;
        F := 0;
        While S <> '' Do
        Begin
          P := Pos(#9, S);
          Fld := Copy(S, 1, P - 1);
          Delete(S, 1, P);
          Case F Of
            0 : T[I]^.Name := Fld;
            1 : T[I]^.Cmd := Fld;
            2 : T[I]^.Kind := NumOf(Fld);
            3 : T[I]^.Hour := NumOf(Fld);
            4 : T[I]^.Min := NumOf(Fld);
            5 : T[I]^.Date := NumOf(Fld);
            6 : T[I]^.Days := NumOf(Fld);
            7 : T[I]^.Enabled := Fld = '1';
            8 : T[I]^.Last := NumOf(Fld);
          End;
          Inc(F);
        End;
      End;
      S := '';
    End
    Else If (LineB[0] <> 13) And (Length(S) < 255) Then S := S + Chr(LineB[0]);
  Until N = 0;
  Dummy := CloseHandle(H);
End;

Procedure WS(H : LongInt; S : String);
Var W : LongInt;
Begin
  If S <> '' Then Dummy := WriteFile(H, LongInt(@S[1]), Length(S), LongInt(@W), 0);
End;

Procedure Save;
Var H, I : LongInt;
Begin
  H := CreateFileA(Z(DataPath), GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  If H = INVALID_HANDLE Then Exit;
  WS(H, '; Planificateur de taches de Pasdows 95'#13#10);
  If Paused Then WS(H, 'PAUSE'#13#10);
  For I := 0 To NT - 1 Do
    WS(H, T[I]^.Name + #9 + T[I]^.Cmd + #9 + IStr(T[I]^.Kind) + #9 + IStr(T[I]^.Hour) + #9 + IStr(T[I]^.Min) + #9 +
          IStr(T[I]^.Date) + #9 + IStr(T[I]^.Days) + #9 + IStr(Ord(T[I]^.Enabled)) + #9 + IStr(T[I]^.Last) + #13#10);
  Dummy := CloseHandle(H);
End;

{ lancer la ligne de commande de la tache }
Function Launch(I : LongInt) : Boolean;
Var S, P, A : String; K : LongInt;
Begin
  S := TrimS(T[I]^.Cmd);
  If S = '' Then Begin Launch := False; Exit; End;
  If S[1] = '"' Then
  Begin
    Delete(S, 1, 1);
    K := Pos('"', S);
    If K = 0 Then K := Length(S) + 1;
  End
  Else
  Begin
    K := Pos(' ', S);
    If K = 0 Then K := Length(S) + 1;
  End;
  P := Copy(S, 1, K - 1);
  A := TrimS(Copy(S, K + 1, 255));
  If A = '' Then Launch := ShellExecuteA(0, Z2('open'), Z(P), 0, 0, 1) > 32
  Else
  Begin
    PutZ(LongInt(@LineB), A);
    Launch := ShellExecuteA(0, Z2('open'), Z(P), LongInt(@LineB), 0, 1) > 32;
  End;
  T[I]^.Last := NowStamp;
End;

{ ==================================================================== }
{ Agent                                                                 }
{ ==================================================================== }

Procedure AgentTick;
Var I, N, Nw : LongInt; Any : Boolean;
Begin
  Load;
  If Paused Then Exit;
  GetLocalTime(LongInt(@St));
  Nw := Stamp(St[0], St[1], St[3], St[4], St[5]);
  Any := False;
  For I := 0 To NT - 1 Do
    If T[I]^.Enabled Then
    Begin
      If T[I]^.Kind = 3 Then
      Begin
        If Boot Then Begin Dummy := Launch(I); Any := True; End;
      End
      Else
      Begin
        { due : l'occurrence du jour (ou la date) est passee et n'a pas
          encore ete lancee }
        N := Stamp(St[0], St[1], St[3], T[I]^.Hour, T[I]^.Min);
        If T[I]^.Kind = 0 Then
          N := Stamp(T[I]^.Date Div 10000, (T[I]^.Date Div 100) Mod 100, T[I]^.Date Mod 100, T[I]^.Hour, T[I]^.Min);
        If (T[I]^.Kind = 2) And ((T[I]^.Days And (1 Shl Dow(St[0], St[1], St[3]))) = 0) Then N := Nw + 1;
        If (N <= Nw) And (T[I]^.Last < N) And (Nw - N < 60 * 24) Then
        Begin
          Dummy := Launch(I);
          Any := True;
        End;
      End;
    End;
  Boot := False;
  If Any Then Save;
End;

Function AgentProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  AgentProc := 0;
  If Msg = WM_TIMER Then AgentTick
  Else If Msg = WM_DESTROY Then PostQuitMessage(0)
  Else AgentProc := DefWindowProcA(H, Msg, WP, LP);
End;

Procedure RunAgent;
Var H : LongInt;
Begin
  If (CreateMutexA(0, 0, Z('PasdowsTaskAgent')) = 0) Or (GetLastError = 183) Then ExitProcess(0);
  RegClass('PasdowsTaskAgent', LongInt(@AgentProc), 0);
  PutZ(LongInt(@NameZ2), 'PasdowsTaskAgent');
  H := CreateWindowExA(0, LongInt(@NameZ2), Z('Agent du Planificateur'), WS_POPUP, 0, 0, 1, 1, 0, 0, Inst, 0);
  Wnd := H;
  AgentTick;
  Dummy := SetTimer(H, 1, 15000, 0);
  MsgLoop;
  ExitProcess(0);
End;

{ inscrire l'agent (demarrage) et le lancer s'il ne tourne pas }
Procedure EnsureAgent;
Var K, D, M : LongInt; V : String;
Begin
  If RegCreateKeyExA(LongInt($80000002), Z('Software\Microsoft\Windows\CurrentVersion\Run'), 0, 0, 0, $F003F, 0,
                     LongInt(@K), LongInt(@D)) = 0 Then
  Begin
    V := ExeDir + 'MSTASK.EXE /AGENT';
    PutZ(LongInt(@LineB), V);
    Dummy := RegSetValueExA(K, Z('SchedulingAgent'), 0, 1, LongInt(@LineB), Length(V) + 1);
    Dummy := RegFlushKey(K);
    Dummy := RegCloseKey(K);
  End;
  M := OpenMutexA($1F0001, 0, Z('PasdowsTaskAgent'));
  If M <> 0 Then Dummy := CloseHandle(M)
  Else Dummy := WinExec(Z(ExeDir + 'MSTASK.EXE /AGENT'), 0);
End;

{ ==================================================================== }
{ Liste                                                                 }
{ ==================================================================== }

Function NRowsV : LongInt;
Begin
  NRowsV := MaxI(1, (CH - StH - HdrH - 4) Div RowH);
End;

Procedure ColX(K : LongInt; Var X : LongInt);
Var W : LongInt;
Begin
  W := CW - 8;
  Case K Of
    0 : X := 2;
    1 : X := 2 + (W * 28) Div 100;
    2 : X := 2 + (W * 52) Div 100;
    3 : X := 2 + (W * 70) Div 100;
    4 : X := 2 + (W * 88) Div 100;
  Else
    X := CW - 2;
  End;
End;

Procedure ClipT(Dc, X, Y, W : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If W < 10 Then Exit;
  If Length(S) * 8 > W - 4 Then S := Copy(S, 1, MaxI(0, (W - 4) Div 8 - 1)) + #187;
  Txt(Dc, X, Y, S, Fg, Bg);
End;

Procedure TaskIcon(Dc, X, Y : LongInt; Add : Boolean);
Begin
  { horloge (tache) ou etoile (ajouter) }
  Bar(Dc, X + 2, Y + 2, X + 14, Y + 14, ClrDark);
  Bar(Dc, X + 3, Y + 3, X + 13, Y + 13, ClrHi);
  If Add Then
  Begin
    Bar(Dc, X + 7, Y + 4, X + 9, Y + 12, $00A000);
    Bar(Dc, X + 4, Y + 7, X + 12, Y + 9, $00A000);
  End
  Else
  Begin
    Bar(Dc, X + 7, Y + 5, X + 8, Y + 9, ClrDark);
    Bar(Dc, X + 8, Y + 8, X + 11, Y + 9, ClrDark);
  End;
End;

Procedure DrawAll(Dc : LongInt);
Var I, R, Y, K, X1, X2, Fg, Bg, Nx : LongInt; S : String;
Begin
  Bar(Dc, 0, 0, CW, CH, ClrWin);
  For K := 0 To 4 Do
  Begin
    ColX(K, X1); ColX(K + 1, X2);
    Bevel(Dc, X1, 0, X2, HdrH, True);
    Bar(Dc, X1 + 1, 1, X2 - 2, HdrH - 2, ClrFace);
    Case K Of
      0 : S := 'Nom';
      1 : S := 'Planification';
      2 : S := 'Prochaine ex'#233'cution';
      3 : S := 'Derni'#232're ex'#233'cution';
    Else
      S := #201'tat';
    End;
    ClipT(Dc, X1 + 4, 2, X2 - X1 - 4, S, ClrDark, ClrFace);
  End;
  For R := 0 To NRowsV - 1 Do
  Begin
    I := Top + R - 1;
    If I >= NT Then Break;
    Y := HdrH + 2 + R * RowH;
    If I + 1 = Sel Then Begin Fg := ClrHi; Bg := ClrSel; End Else Begin Fg := ClrDark; Bg := ClrWin; End;
    If I < 0 Then
    Begin
      TaskIcon(Dc, 4, Y, True);
      ColX(1, X2);
      Bar(Dc, 22, Y, 26 + 26 * 8, Y + RowH, Bg);
      Txt(Dc, 24, Y + 1, 'Ajouter une t'#226'che planifi'#233'e', Fg, Bg);
      Continue;
    End;
    TaskIcon(Dc, 4, Y, False);
    ColX(1, X2);
    Bar(Dc, 22, Y, MinI(X2, 26 + Length(T[I]^.Name) * 8), Y + RowH, Bg);
    ClipT(Dc, 24, Y + 1, X2 - 24, T[I]^.Name, Fg, Bg);
    ColX(1, X1); ColX(2, X2);
    ClipT(Dc, X1 + 4, Y + 1, X2 - X1, SchedText(I), ClrDark, ClrWin);
    ColX(3, X1);
    Nx := NextRun(I);
    If T[I]^.Kind = 3 Then S := 'Au d'#233'marrage' Else If Nx < 0 Then S := 'Jamais' Else S := StampText(Nx);
    ClipT(Dc, X2 + 4, Y + 1, X1 - X2, S, ClrDark, ClrWin);
    ColX(4, X2);
    ClipT(Dc, X1 + 4, Y + 1, X2 - X1, StampText(T[I]^.Last), ClrDark, ClrWin);
    ColX(5, X1);
    If Paused Then S := 'En pause' Else If T[I]^.Enabled Then S := 'Activ'#233'e' Else S := 'D'#233'sactiv'#233'e';
    ClipT(Dc, X2 + 4, Y + 1, X1 - X2, S, ClrDark, ClrWin);
  End;
  Y := CH - StH;
  Bar(Dc, 0, Y, CW, CH, ClrFace);
  Bevel(Dc, 2, Y + 2, CW - 2, CH - 1, False);
  If Paused Then S := 'Le Planificateur de t'#226'ches est en pause.'
  Else S := IStr(NT) + ' t'#226'che(s) planifi'#233'e(s)';
  Txt(Dc, 6, Y + 4, S, ClrDark, ClrFace);
End;

Procedure Paint0;
Var Dc : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Fiche d'une tache                                                     }
{ ==================================================================== }

Function Chk(H : LongInt) : Boolean;
Begin
  Chk := SendMessageA(H, BM_GETCHECK, 0, 0) <> 0;
End;

Procedure DlgClose(Ok : Boolean);
Var I, K, D, M, Y, E, P : LongInt; S : String;
Begin
  If Ok Then
  Begin
    If TrimS(CtlText(Ed[1])) = '' Then
    Begin
      Dummy := MessageBoxA(DlgW, Z(Disp('Indiquez le programme '#224' ex'#233'cuter.')), Z2(Disp('Planificateur de t'#226'ches')),
                           MB_OK Or MB_ICONWARNING);
      Exit;
    End;
    I := DlgIdx;
    If I < 0 Then I := NewTask;
    If I < 0 Then Exit;
    T[I]^.Name := Copy(TrimS(CtlText(Ed[0])), 1, 63);
    If T[I]^.Name = '' Then T[I]^.Name := 'T'#226'che ' + IStr(I + 1);
    T[I]^.Cmd := Copy(TrimS(CtlText(Ed[1])), 1, 200);
    If Chk(Ed[3]) Then T[I]^.Kind := 0 Else If Chk(Ed[5]) Then T[I]^.Kind := 2 Else If Chk(Ed[6]) Then T[I]^.Kind := 3
    Else T[I]^.Kind := 1;
    S := CtlText(Ed[7]);
    P := Pos(':', S);
    If P > 0 Then
    Begin
      T[I]^.Hour := MinI(23, MaxI(0, NumOf(Copy(S, 1, P - 1))));
      T[I]^.Min := MinI(59, MaxI(0, NumOf(Copy(S, P + 1, 2))));
    End;
    S := CtlText(Ed[8]) + '/';
    D := NumOf(Copy(S, 1, Pos('/', S) - 1)); Delete(S, 1, Pos('/', S));
    M := NumOf(Copy(S, 1, Pos('/', S) - 1)); Delete(S, 1, Pos('/', S));
    Y := NumOf(Copy(S, 1, Pos('/', S) - 1));
    If Y < 100 Then Y := Y + 2000;
    If (D >= 1) And (D <= 31) And (M >= 1) And (M <= 12) Then T[I]^.Date := Y * 10000 + M * 100 + D;
    E := 0;
    For K := 0 To 6 Do If Chk(Ed[9 + K]) Then E := E Or (1 Shl ((K + 1) Mod 7));
    If E = 0 Then E := 62;
    T[I]^.Days := E;
    T[I]^.Enabled := Chk(Ed[2]);
    If DlgIdx < 0 Then T[I]^.Last := 0;
    Save;
    EnsureAgent;
    Sel := I + 1;
  End;
  Dummy := EnableWindow(Wnd, 1);
  Dummy := DestroyWindow(DlgW);
  DlgW := 0;
  Dummy := SetFocus(Wnd);
  Paint0;
End;

Procedure Browse;
Var Ofn : Array[0..21] Of LongInt; Fb : Array[0..259] Of Byte; Fl : Array[0..63] Of Byte; F : String; K : LongInt;
Begin
  F := 'Programmes|*.exe;*.com;*.bat|Tous les fichiers (*.*)|*.*|';
  For K := 1 To Length(F) Do If F[K] = '|' Then Fl[K - 1] := 0 Else Fl[K - 1] := Ord(F[K]);
  Fl[Length(F)] := 0;
  For K := 0 To 21 Do Ofn[K] := 0;
  Fb[0] := 0;
  Ofn[0] := 76; Ofn[1] := DlgW; Ofn[3] := LongInt(@Fl); Ofn[6] := 1; Ofn[7] := LongInt(@Fb); Ofn[8] := 260;
  If GetOpenFileNameA(LongInt(@Ofn)) <> 0 Then
  Begin
    F := GetZ(LongInt(@Fb));
    If Pos(' ', F) > 0 Then F := '"' + F + '"';
    SetText(Ed[1], UnDisp(F));
  End;
End;

Procedure DlgPaint(H : LongInt);
Var Ps : Array[0..15] Of LongInt; Dc : LongInt;
Begin
  Dc := BeginPaint(H, LongInt(@Ps));
  Bar(Dc, 0, 0, 480, 400, ClrFace);
  Dummy := SelectObject(Dc, FontS);
  Txt(Dc, 12, 15, 'Nom :', ClrDark, ClrFace);
  Txt(Dc, 12, 45, 'Ex'#233'cuter :', ClrDark, ClrFace);
  Txt(Dc, 12, 216, 'Heure (HH:MM) :', ClrDark, ClrFace);
  Txt(Dc, 240, 216, 'Date :', ClrDark, ClrFace);
  Txt(Dc, 12, 248, 'Jours :', ClrDark, ClrFace);
  Dummy := EndPaint(H, LongInt(@Ps));
End;

Function DlgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  DlgProc := 0;
  Case Msg Of
    WM_PAINT : DlgPaint(H);
    WM_ERASEBKGND : DlgProc := 1;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_OK : DlgClose(True);
        ID_CANCEL : DlgClose(False);
        ID_BROWSE : Browse;
      End;
    WM_CLOSE : DlgClose(False);
  Else
    DlgProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Procedure OpenCard(I : LongInt);
Var Rc : Array[0..3] Of LongInt; Fw, Fh, K, Tk : LongInt; S : String;
Begin
  If DlgW <> 0 Then Exit;
  DlgIdx := I;
  If I < 0 Then
  Begin
    Tk := NewTask;
    If Tk < 0 Then Exit;
    GetLocalTime(LongInt(@St));
    T[Tk]^.Date := St[0] * 10000 + St[1] * 100 + St[3];
    T[Tk]^.Hour := (St[4] + 1) Mod 24;
    S := 'Nouvelle t'#226'che';
  End
  Else
  Begin
    Tk := I;
    S := 'Propri'#233't'#233's de ' + T[I]^.Name;
  End;
  Rc[0] := 0; Rc[1] := 0; Rc[2] := 470; Rc[3] := 330;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), WS_POPUP Or WS_CAPTION Or WS_SYSMENU, 0, WS_EX_DLGMODALFRAME);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  PutZ(LongInt(@NameZ2), 'TaskCard');
  DlgW := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@NameZ2), Z(Disp(S)), WS_POPUP Or WS_CAPTION Or WS_SYSMENU,
                          MaxI(0, (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2),
                          MaxI(0, (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2), Fw, Fh, Wnd, 0, Inst, 0);
  If DlgW = 0 Then Exit;
  Ed[0] := Ctl(DlgW, 'EDIT', T[Tk]^.Name, WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 110, 12, 348, 22, 10);
  Ed[1] := Ctl(DlgW, 'EDIT', T[Tk]^.Cmd, WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 110, 42, 252, 22, 11);
  Dummy := Ctl(DlgW, 'BUTTON', 'Parcourir...', WS_TABSTOP, 368, 41, 90, 24, ID_BROWSE);
  Ed[2] := Ctl(DlgW, 'BUTTON', 'T'#226'che activ'#233'e',
               WS_TABSTOP Or BS_AUTOCHECKBOX, 110, 72, 348, 20, 12);
  Dummy := Ctl(DlgW, 'BUTTON', 'Planifier la t'#226'che', BS_GROUPBOX, 12, 100, 446, 100, 0);
  Ed[3] := Ctl(DlgW, 'BUTTON', 'Une seule fois', WS_TABSTOP Or WS_GROUP Or BS_AUTORADIOBUTTON, 24, 122, 200, 20,
               ID_ONCE);
  Ed[4] := Ctl(DlgW, 'BUTTON', 'Chaque jour', BS_AUTORADIOBUTTON, 24, 146, 200, 20, ID_DAILY);
  Ed[5] := Ctl(DlgW, 'BUTTON', 'Chaque semaine', BS_AUTORADIOBUTTON, 240, 122, 200, 20, ID_WEEKLY);
  Ed[6] := Ctl(DlgW, 'BUTTON', 'Au d'#233'marrage', BS_AUTORADIOBUTTON, 240, 146, 200, 20, ID_BOOT);
  Ed[7] := Ctl(DlgW, 'EDIT', Two(T[Tk]^.Hour) + ':' + Two(T[Tk]^.Min), WS_GROUP Or WS_BORDER Or WS_TABSTOP, 140, 213,
               70, 22, 13);
  If T[Tk]^.Date > 0 Then S := Two(T[Tk]^.Date Mod 100) + '/' + Two((T[Tk]^.Date Div 100) Mod 100) + '/' +
                              IStr(T[Tk]^.Date Div 10000)
  Else S := '';
  Ed[8] := Ctl(DlgW, 'EDIT', S, WS_BORDER Or WS_TABSTOP, 296, 213, 110, 22, 14);
  For K := 0 To 6 Do
  Begin
    Ed[9 + K] := Ctl(DlgW, 'BUTTON', DayName((K + 1) Mod 7), WS_TABSTOP Or BS_AUTOCHECKBOX, 80 + K * 54, 246, 50, 20,
                     20 + K);
    Dummy := SendMessageA(Ed[9 + K], BM_SETCHECK, Ord((T[Tk]^.Days And (1 Shl ((K + 1) Mod 7))) <> 0), 0);
  End;
  Dummy := SendMessageA(Ed[2], BM_SETCHECK, Ord(T[Tk]^.Enabled), 0);
  Dummy := SendMessageA(Ed[3 + MinI(3, MaxI(0, T[Tk]^.Kind))], BM_SETCHECK, 1, 0);
  Dummy := Ctl(DlgW, 'BUTTON', 'OK', WS_GROUP Or WS_TABSTOP Or BS_DEFPUSHBUTTON, 270, 290, 90, 26, ID_OK);
  Dummy := Ctl(DlgW, 'BUTTON', 'Annuler', WS_TABSTOP, 368, 290, 90, 26, ID_CANCEL);
  If I < 0 Then
  Begin
    { la tache n'existe qu'a OK }
    FreeMem(T[Tk], SizeOf(TTask));
    Dec(NT);
  End;
  Dummy := EnableWindow(Wnd, 0);
  Dummy := ShowWindow(DlgW, 1);
  Dummy := UpdateWindow(DlgW);
  Dummy := SetFocus(Ed[0]);
End;

{ ==================================================================== }
{ Fenetre principale                                                    }
{ ==================================================================== }

Procedure Command(Id : LongInt);
Var I, K : LongInt;
Begin
  I := Sel - 1;
  Case Id Of
    CM_NEW : OpenCard(-1);
    CM_PROPS : If Sel = 0 Then OpenCard(-1) Else If (I >= 0) And (I < NT) Then OpenCard(I);
    CM_DELETE :
      If (I >= 0) And (I < NT) Then
        If Ask('Voulez-vous supprimer la t'#226'che "' + T[I]^.Name + '" ?', 'Planificateur de t'#226'ches',
               MB_YESNO Or MB_ICONQUESTION) = IDYES Then
        Begin
          FreeMem(T[I], SizeOf(TTask));
          For K := I To NT - 2 Do T[K] := T[K + 1];
          Dec(NT);
          If Sel > NT Then Sel := NT;
          Save;
        End;
    CM_RUN :
      If (I >= 0) And (I < NT) Then
      Begin
        If Not Launch(I) Then
          Dummy := Ask('Impossible d''ex'#233'cuter ' + T[I]^.Cmd + '.', 'Planificateur de t'#226'ches',
                       MB_OK Or MB_ICONERROR);
        Save;
      End;
    CM_PAUSE :
      Begin
        Paused := Not Paused;
        Save;
        MCheck(MAdv, CM_PAUSE, Paused);
      End;
    CM_QUIT : Dummy := PostMessageA(Wnd, WM_CLOSE, 0, 0);
    CM_ABOUT : Dummy := Ask('Planificateur de t'#226'ches de Pasdows 95'#10#10'Les t'#226'ches sont lanc'#233'es par ' +
                            'l''agent (MSTASK /AGENT), inscrit au d'#233'marrage de Pasdows. Programme '#233'crit en Pascal ' +
                            'et compil'#233' par WPC.', #192' propos du Planificateur de t'#226'ches', MB_OK Or MB_ICONINFO);
  End;
  Paint0;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Rc : Array[0..3] Of LongInt; Dc, Y, R, M : LongInt; Pt : Array[0..1] Of LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 100) And (Rc[3] > 60) Then Begin CW := MinI(Rc[2], 1024); CH := MinI(Rc[3], 768); End;
        Dummy := InvalidateRect(H, 0, 0);
      End;
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_TIMER : Begin Load; If DlgW = 0 Then Paint0; End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK, WM_RBUTTONDOWN :
      Begin
        Y := S16(LP Shr 16);
        R := Top + (Y - HdrH - 2) Div RowH;
        If (Y > HdrH) And (R >= 0) And (R <= NT) Then
        Begin
          Sel := R;
          Paint0;
          If Msg = WM_LBUTTONDBLCLK Then Command(CM_PROPS)
          Else If (Msg = WM_RBUTTONDOWN) And (R > 0) Then
          Begin
            M := CreatePopupMenu;
            MItem(M, CM_RUN, '~Ex'#233'cuter');
            MItem(M, 0, '');
            MItem(M, CM_DELETE, '~Supprimer');
            MItem(M, CM_PROPS, '~Propri'#233't'#233's');
            Pt[0] := S16(LP); Pt[1] := Y;
            Dummy := ClientToScreen(H, LongInt(@Pt));
            R := TrackPopupMenu(M, $100, Pt[0], Pt[1], 0, H, 0);
            Dummy := DestroyMenu(M);
            If R > 0 Then Command(R);
          End;
        End;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_UP : Begin If Sel > 0 Then Dec(Sel); Paint0; End;
        VK_DOWN : Begin If Sel < NT Then Inc(Sel); Paint0; End;
        VK_RETURN : Command(CM_PROPS);
        VK_DELETE : Command(CM_DELETE);
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND : Command(WP And $FFFF);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Var
  MenuBar, MFile, MHelp, Dc0, K : LongInt;
  A : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  NT := 0; Sel := 0; Top := 0; DlgW := 0; Agent := False; Boot := False;
  ExeDir := ParamStr(0);
  K := Length(ExeDir);
  While (K > 0) And (ExeDir[K] <> '\') Do Dec(K);
  ExeDir := Copy(ExeDir, 1, K);
  DataPath := ExeDir + 'TACHES.DAT';
  For K := 1 To ParamCount Do
  Begin
    A := UpS(ParamStr(K));
    If (A = '/AGENT') Or (A = '-AGENT') Then Begin Agent := True; Boot := GetTickCount < 600000; End;
  End;
  If Agent Then RunAgent;
  Load;
  CW := 600; CH := 300;
  RegClass('TaskWnd', LongInt(@MainProc), CS_DBLCLKS);
  RegClass('TaskCard', LongInt(@DlgProc), 0);
  Wnd := MainWindow('TaskWnd', 'T'#226'ches planifi'#233'es', WS_OVERLAPPEDWINDOW, CW, CH, True);
  If Wnd = 0 Then ExitProcess(1);
  MenuBar := CreateMenu;
  MFile := CreatePopupMenu; MAdv := CreatePopupMenu; MHelp := CreatePopupMenu;
  MItem(MFile, CM_NEW, '~Nouvelle t'#226'che planifi'#233'e...');
  MItem(MFile, CM_RUN, '~Ex'#233'cuter');
  MItem(MFile, CM_DELETE, '~Supprimer'#9'Suppr');
  MItem(MFile, CM_PROPS, '~Propri'#233't'#233's');
  MItem(MFile, 0, '');
  MItem(MFile, CM_QUIT, '~Fermer');
  MItem(MAdv, CM_PAUSE, '~Suspendre le Planificateur de t'#226'ches');
  MItem(MHelp, CM_ABOUT, #192' ~propos du Planificateur de t'#226'ches');
  MSub(MenuBar, MFile, '~Fichier');
  MSub(MenuBar, MAdv, '~Avanc'#233);
  MSub(MenuBar, MHelp, '~?');
  Dummy := SetMenu(Wnd, MenuBar);
  MCheck(MAdv, CM_PAUSE, Paused);
  Dc0 := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc0);
  MemBmp := CreateCompatibleBitmap(Dc0, 1024, 768);
  Dummy := ReleaseDC(Wnd, Dc0);
  Dummy := SelectObject(MemDC, MemBmp);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  If NT > 0 Then EnsureAgent;
  Dummy := SetTimer(Wnd, 1, 20000, 0);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  MsgLoop;
  ExitProcess(0);
END.
