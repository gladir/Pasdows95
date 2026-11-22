{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: PASDBG - Pasdows Debugger, debogueur des programmes Win32
                de Pasdows 95, venu de l'OS2-Zero Debugger d'OS/2-0.
}

{ PASDBG.PAS - Pasdows Debugger : debogueur des programmes Win32 de
  Pasdows 95.

  Compilation : WPC -CW32 PASDBG.PAS PASDBG.EXE

  Un debogueur dans l'esprit de Turbo Debugger (fenetre CPU) avec
  l'apparence de Windows 95 : une fenetre a bordure de taille, sa barre
  de menus (Fichier, Execution, Points d'arret, Donnees, Aide), une
  barre d'outils de boutons et une barre d'etat, et quatre volets a
  barre de defilement :
   - Code : desassemblage x86 32 bits en syntaxe Intel colore (les
     instructions, les registres, les nombres, les symboles, les mots
     cles et la ponctuation ont chacun leur couleur) ; adresse, octets,
     etiquettes des procedures, ligne d'EIP (fleche et fond jaune),
     points d'arret (pastille et fond rouge), saut conditionnel effectue
     ou non a la ligne d'EIP ;
   - Registres : EAX a EIP, EFLAGS et les segments, drapeaux c z s o p a
     i d t ; une valeur changee par le dernier pas est en rouge ; Entree
     (ou double clic) modifie un registre, Espace inverse un drapeau ;
   - Memoire : 16 octets par ligne en hexadecimal et en ASCII, les octets
     changes depuis le dernier arret en rouge ;
   - Pile : ESP et EBP marques, adresses de retour nommees.

  Le programme debogue (PE Win32, par exemple compile par WPC) est lance
  par CreateProcessA (DEBUG_ONLY_THIS_PROCESS) et s'arrete a son point
  d'entree ; l'API de debogage de Windows (WaitForDebugEvent,
  ContinueDebugEvent, GetThreadContext, SetThreadContext,
  ReadProcessMemory, WriteProcessMemory, DebugBreakProcess) donne ses
  evenements, ses registres et sa memoire. Le debogueur pose les points
  d'arret (INT 3), fait le pas a pas (drapeau TF) et voit les exceptions
  du programme avant sa fin. Les fonctions de KERNEL32, USER32, GDI32...
  sont dans le noyau de Pasdows (VMM32) : F7 sur leur appel passe
  par-dessus (comme F8), et on n'y pose pas de point d'arret. Les
  symboles viennent de la table des importations (USER32.CreateWindowExA...),
  des exportations des DLL et de la carte .MAP du programme
  (WPC -GD PROG.PAS).

  Touches (comme Turbo Debugger) : F9 executer, F7 pas a pas (entrer),
  F8 pas (sauter les appels), F4 jusqu'au curseur, Alt+F8 jusqu'au
  retour, F12 pause, F2 point d'arret, Ctrl+F2 redemarrer, Alt+F2
  terminer, Ctrl+G aller a l'adresse, Ctrl+E origine (EIP), Tab volet
  suivant, Ctrl+O ouvrir. PASDBG programme [arguments] debogue un
  programme des le demarrage. L'interface suit la variable
  d'environnement LANGUAGE (FR, EN, GR, IT, SP). }

Program PasDbg;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Const
  WM_CREATE = $0001; WM_DESTROY = $0002; WM_SIZE = $0005; WM_SETFOCUS = $0007; WM_PAINT = $000F;
  WM_CLOSE = $0010; WM_QUIT = $0012; WM_KEYDOWN = $0100; WM_CHAR = $0102; WM_SYSKEYDOWN = $0104;
  WM_COMMAND = $0111; WM_TIMER = $0113; WM_VSCROLL = $0115; WM_INITMENU = $0116;
  WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201; WM_LBUTTONUP = $0202; WM_LBUTTONDBLCLK = $0203;
  WS_OVERLAPPEDWINDOW = $00CF0000; WS_POPUP = $80000000; WS_CHILD = $40000000; WS_VISIBLE = $10000000;
  WS_CAPTION = $00C00000; WS_SYSMENU = $00080000; WS_BORDER = $00800000; WS_VSCROLL = $00200000;
  WS_TABSTOP = $00010000; WS_EX_DLGMODALFRAME = 1; WS_EX_CLIENTEDGE = $200;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1; ES_AUTOHSCROLL = $80; LBS_NOTIFY = 1; SBS_VERT = 1;
  EM_SETSEL = $00B1; EM_LIMITTEXT = $00C5;
  LB_ADDSTRING = $0180; LB_RESETCONTENT = $0184; LB_GETCURSEL = $0188;
  LBN_SELCHANGE = 1; LBN_DBLCLK = 2;
  SB_LINEUP = 0; SB_LINEDOWN = 1; SB_PAGEUP = 2; SB_PAGEDOWN = 3; SB_SLIDERPOSITION = 4; SB_SLIDERTRACK = 5;
  SB_CTL = 2;
  SWP_NOZORDER = 4; SWP_NOACTIVATE = $10;
  MF_STRING = 0; MF_ENABLED = 0; MF_GRAYED = 1; MF_POPUP = $10; MF_SEPARATOR = $800;
  MIS_TEXT = 0; MIS_SEPARATOR = MF_SEPARATOR; MIS_SUBMENU = MF_POPUP;
  MB_OK = 0; MB_YESNO = 4; MB_ICONQUESTION = $20; MB_WARNING = $30; MB_INFORMATION = $40; MB_ERROR = $10;
  MBID_YES = 6; MBID_NO = 7;
  ETO_OPAQUE = 2; ETO_CLIPPED = 4; SYSTEM_FIXED_FONT = 16; IDC_ARROW = 32512; CS_DBLCLKS = 8;
  { debogage (API Win32) }
  DEBUG_ONLY_THIS_PROCESS = 2; DBG_CONTINUE = $00010002; DBG_EXCEPTION_NOT_HANDLED = $80010001;
  CONTEXT_FULL = $00010007;
  { touches : codes internes (ceux du debogueur d'origine ; les touches de
    Windows sont traduites par KeyMsg) }
  KC_CHAR = 1; KC_VIRTUALKEY = 2; KC_SHIFT = 8; KC_CTRL = $10; KC_ALT = $20; KC_KEYUP = $40;
  VK_BACKSPACE = $05; VK_TAB = $06; VK_BACKTAB = $07; VK_NEWLINE = $08; VK_ESC = $0F; VK_SPACE = $10;
  VK_PAGEUP = $11; VK_PAGEDOWN = $12; VK_END = $13; VK_HOME = $14;
  VK_LEFT = $15; VK_UP = $16; VK_RIGHT = $17; VK_DOWN = $18; VK_DELETE = $1B; VK_ENTER = $1E;
  VK_F1 = $20; VK_F2 = $21; VK_F4 = $23; VK_F7 = $26; VK_F8 = $27; VK_F9 = $28; VK_F12 = $2B;
  CLR_WHITE = -2; CLR_BLACK = -1; CLR_BLUE = 1; CLR_RED = 2; CLR_PINK = 3; CLR_GREEN = 4; CLR_CYAN = 5;
  CLR_YELLOW = 6; CLR_DARKGRAY = 8; CLR_DARKBLUE = 9; CLR_DARKRED = 10; CLR_DARKPINK = 11;
  CLR_DARKGREEN = 12; CLR_DARKCYAN = 13; CLR_BROWN = 14; CLR_PALEGRAY = 15;
  { commandes (menus et boutons) }
  idFile = 200; idOpen = 201; idArgs = 202; idRestart = 203; idKill = 204; idExit = 205;
  idRunM = 210; idRun = 211; idStep = 212; idOver = 213; idCursor = 214; idReturn = 215; idPause = 216;
  idBpM = 220; idBpToggle = 221; idBpClear = 222; idBpList = 223;
  idDataM = 230; idGoto = 231; idRegEdit = 232; idOrigin = 233; idFollow = 234;
  idHelpM = 240; idAbout = 241; idKeys = 242;
  { boites de dialogue }
  ID_OK = 1; ID_CANCEL = 2; ID_EF = 20; ID_LIST = 21;
  ChW = 8; ChH = 16;
  HdrH = 20;          { en-tete d'un volet }
  SbW = 16;           { barre de defilement }
  TbH = 34;           { barre d'outils }
  StH = 22;           { barre d'etat }
  { volets }
  PnCode = 0; PnRegs = 1; PnMem = 2; PnStack = 3;
  MaxRows = 100;
  SymMax = 6000;
  BpMax = 64;

Type
  PByte = ^Byte;

{ --- USER32.DLL, GDI32.DLL, KERNEL32.DLL --- }
Function RegisterClassA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex, Cls, Nm, St, X, Y, W, H, Par, Menu, Ins, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'CreateWindowExA';
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(P, H, A, B : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DispatchMessageA';
Function BeginPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'BeginPaint';
Function EndPaint(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EndPaint';
Function FillRect(Dc, R, B : LongInt) : LongInt; stdcall; external 'user32.dll' name 'FillRect';
Function InvalidateRect(H, R, E : LongInt) : LongInt; stdcall; external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetClientRect';
Function SetWindowPos(H, A, X, Y, W, Hh, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetWindowPos';
Function MessageBoxA(H, T, C, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MessageBoxA';
Function DestroyWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'DestroyWindow';
Function SetFocus(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetFocus';
Function GetFocus : LongInt; stdcall; external 'user32.dll' name 'GetFocus';
Function SetActiveWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetActiveWindow';
Function SetForegroundWindow(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetForegroundWindow';
Function EnableWindow(H, E : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EnableWindow';
Function GetParent(H : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetParent';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'LoadCursorA';
Function SetTimer(H, Id, Ms, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetTimer';
Function SendMessageA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SendMessageA';
Function PostMessageA(H, M, W, L : LongInt) : LongInt; stdcall; external 'user32.dll' name 'PostMessageA';
Function SetWindowTextA(H, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetWindowTextA';
Function GetWindowTextA(H, P, N : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetWindowTextA';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetSystemMetrics';
Function CreateMenu : LongInt; stdcall; external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall; external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(M, F, Id, P : LongInt) : LongInt; stdcall; external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetMenu';
Function EnableMenuItem(M, Id, F : LongInt) : LongInt; stdcall; external 'user32.dll' name 'EnableMenuItem';
Function GetKeyState(K : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetKeyState';
Function GetSysColor(I : LongInt) : LongInt; stdcall; external 'user32.dll' name 'GetSysColor';
Function ShowWindow(H, C : LongInt) : LongInt; stdcall; external 'user32.dll' name 'ShowWindow';
Function MessageBeep(T : LongInt) : LongInt; stdcall; external 'user32.dll' name 'MessageBeep';
Function SetScrollRange(H, B, Mn, Mx, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetScrollRange';
Function SetScrollPos(H, B, P, R : LongInt) : LongInt; stdcall; external 'user32.dll' name 'SetScrollPos';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'CreateSolidBrush';
Function SelectObject(Dc, O : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SelectObject';
Function DeleteObject(O : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'DeleteObject';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetTextColor';
Function SetBkColor(Dc, C : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'SetBkColor';
Function ExtTextOutA(Dc, X, Y, O, R, S, N, D : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'ExtTextOutA';
Function GetStockObject(I : LongInt) : LongInt; stdcall; external 'gdi32.dll' name 'GetStockObject';
Function CreateProcessA(A, C, Pa, Ta, Inh, Fl, Env, Dir, PSi, PPi : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateProcessA';
Function TerminateProcess(H, C : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'TerminateProcess';
Function CloseHandle(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CloseHandle';
Function CreateFileA(N, A, Sh, Sec, Disp, Fl, T : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileA';
Function ReadFile(H, B, N, PN, O : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'ReadFile';
Function GetLastError : LongInt; stdcall; external 'kernel32.dll' name 'GetLastError';
Function GetModuleHandleA(P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetModuleHandleA';
Function GetEnvironmentVariableA(N, B, S : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';
Function GetCurrentDirectoryA(N, B : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetCurrentDirectoryA';
Function FindFirstFileA(N, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindFirstFileA';
Function FindNextFileA(H, P : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindNextFileA';
Function FindClose(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FindClose';
Function WaitForDebugEvent(P, Ms : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'WaitForDebugEvent';
Function ContinueDebugEvent(Pid, Tid, St : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'ContinueDebugEvent';
Function DebugBreakProcess(H : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'DebugBreakProcess';
Function GetThreadContext(H, C : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'GetThreadContext';
Function SetThreadContext(H, C : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'SetThreadContext';
Function ReadProcessMemory(H, A, B, N, PN : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'ReadProcessMemory';
Function WriteProcessMemory(H, A, B, N, PN : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'WriteProcessMemory';
Function FlushInstructionCache(H, A, N : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'FlushInstructionCache';
Procedure PostQuitMessage(C : LongInt); stdcall; external 'user32.dll' name 'PostQuitMessage';
Procedure Sleep(Ms : LongInt); stdcall; external 'kernel32.dll' name 'Sleep';

Var
  Inst, Frame, Client, MenuHw, Lang, Dummy, SysFont : LongInt;
  NameZ, NameZ2, TxtBuf, ClsBuf : Array[0..511] Of Byte;
  Qmsg : Array[0..7] Of LongInt;      { MSG }
  PaintS : Array[0..15] Of LongInt;   { PAINTSTRUCT }
  { boites de dialogue }
  DlgEnd : LongInt;
  DlgFr, DlgCl, DlgEf, DlgLb, DlgDl, DlgCliH : LongInt;
  DlgTab : Array[0..15] Of LongInt;   { controles de la touche Tab }
  DlgTabN : LongInt;
  FdDir, FdMask, FdRes : String;
  FdSave : Boolean;
  FdMaskInit : String;
  FdN : LongInt;
  FdItem : Array[0..399] Of String[64];
  FindBuf : Array[0..319] Of Byte;    { WIN32_FIND_DATAA }

{ ------------------------------------------------------- utilitaires }

Procedure WrB(A, V : LongInt);
Var Q : PByte;
Begin
  Q := Pointer(A);
  Q^ := V;
End;

Function RdB(A : LongInt) : LongInt;
Var Q : PByte;
Begin
  Q := Pointer(A);
  RdB := Q^;
End;

Procedure WrW(A, V : LongInt);
Begin
  WrB(A, V And 255);
  WrB(A + 1, (V Shr 8) And 255);
End;

Procedure PutZ(A : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do WrB(A + K - 1, Ord(S[K]));
  WrB(A + Length(S), 0);
End;

Function GetZ(A : LongInt) : String;
Var S : String; C : LongInt;
Begin
  S := '';
  If A <> 0 Then
  Begin
    C := RdB(A);
    While (C <> 0) And (Length(S) < 250) Do
    Begin
      S := S + Chr(C);
      Inc(A);
      C := RdB(A);
    End;
  End;
  GetZ := S;
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

Function Lo16(V : LongInt) : LongInt;
Begin
  Lo16 := V And $FFFF;
End;

Function Hi16(V : LongInt) : LongInt;
Begin
  Hi16 := (V Shr 16) And $FFFF;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Function MinL(A, B : LongInt) : LongInt;
Begin
  If A < B Then MinL := A Else MinL := B;
End;

Function MaxL(A, B : LongInt) : LongInt;
Begin
  If A > B Then MaxL := A Else MaxL := B;
End;

Function UpStr(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If (S[K] >= 'a') And (S[K] <= 'z') Then S[K] := Chr(Ord(S[K]) - 32);
  UpStr := S;
End;

Function IStr(N : LongInt) : String;
Var S : String;
Begin
  Str(N, S);
  IStr := S;
End;

Function Pad2(N : LongInt) : String;
Begin
  If N < 10 Then Pad2 := '0' + IStr(N) Else Pad2 := IStr(N);
End;

Function GetEnvS(N : String) : String;
Var B : Array[0..259] Of Byte;
Begin
  B[0] := 0;
  If GetEnvironmentVariableA(Z(N), LongInt(@B), 250) > 0 Then GetEnvS := GetZ(LongInt(@B)) Else GetEnvS := '';
End;

Procedure LangInit;
Var S : String;
Begin
  S := UpStr(GetEnvS('LANGUAGE'));
  If (S <> '') And (S[1] = '"') Then Delete(S, 1, 1);
  S := Copy(S, 1, 2);
  If (S = '') Or (S = 'FR') Then Lang := 0
  Else If (S = 'GR') Or (S = 'DE') Then Lang := 2
  Else If S = 'IT' Then Lang := 3
  Else If (S = 'SP') Or (S = 'ES') Then Lang := 4
  Else Lang := 1;
End;

{ texte dans la langue courante (page de codes 437, la police de Pasdows) }
Function L(Fr, En, De, It, Es : String) : String;
Begin
  Case Lang Of
    1 : L := En;
    2 : L := De;
    3 : L := It;
    4 : L := Es;
  Else
    L := Fr;
  End;
End;

Function AppName : String;
Begin
  AppName := 'Pasdows Debugger';
End;

Function BaseName(S : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '\') And (S[K] <> ':') Do Dec(K);
  BaseName := Copy(S, K + 1, 255);
End;

Function DirOf(S : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '\') Do Dec(K);
  DirOf := Copy(S, 1, K);
End;

Function MsgBox(T : String; Fl : LongInt) : LongInt;
Var I : LongInt;
Begin
  For I := 1 To Length(T) Do If T[I] = '|' Then T[I] := Chr(10);
  MsgBox := MessageBoxA(Frame, Z(T), Z2(AppName), Fl);
End;

{ repertoire courant (X:\...\) }
Function CurDir : String;
Var B : Array[0..259] Of Byte; S : String;
Begin
  B[0] := 0;
  Dummy := GetCurrentDirectoryA(250, LongInt(@B));
  S := GetZ(LongInt(@B));
  If S = '' Then S := 'C:\';
  If S[Length(S)] <> '\' Then S := S + '\';
  CurDir := S;
End;

{ ------------------------------------------------ boites de dialogue }

{ boite modale : la fenetre principale est desactivee jusqu'a DlgEnd }
{ boite modale : la fenetre principale est desactivee jusqu'a DlgEnd ;
  W, H : taille de la zone client }
Function DlgOpen(Cls, Title : String; W, H : LongInt) : Boolean;
Var X, Y, Fw, Fh : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  Fw := W + 2 * GetSystemMetrics(7); Fh := H + GetSystemMetrics(4) + 2 * GetSystemMetrics(8);
  X := MaxL(0, (GetSystemMetrics(0) - Fw) Div 2);
  Y := MaxL(0, (GetSystemMetrics(1) - Fh) Div 2);
  PutZ(LongInt(@ClsBuf), Cls);
  DlgTabN := 0;
  DlgFr := CreateWindowExA(WS_EX_DLGMODALFRAME, LongInt(@ClsBuf), Z2(Title),
                           WS_POPUP Or WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE, X, Y, Fw, Fh, Frame, 0, Inst, 0);
  DlgCl := DlgFr;
  DlgOpen := DlgFr <> 0;
  If DlgFr = 0 Then Exit;
  Dummy := GetClientRect(DlgFr, LongInt(@Rc));
  DlgCliH := Rc[3];
  If DlgCliH <= 0 Then DlgCliH := H;
End;

{ touches des boites (avant la traduction) : Entree (OK, ou l'element de
  la liste), Echap (Annuler), Tab et Maj+Tab ; vrai si la touche est prise }
Function DlgKeyMsg(Hw, Vk : LongInt) : Boolean;
Var I, K : LongInt;
Begin
  DlgKeyMsg := False;
  If (DlgFr = 0) Or ((Hw <> DlgFr) And (GetParent(Hw) <> DlgFr)) Then Exit;
  Case Vk Of
    13 :
      If (Hw = DlgLb) And (DlgLb <> 0) Then
        Dummy := PostMessageA(DlgFr, WM_COMMAND, ID_LIST Or (LBN_DBLCLK Shl 16), DlgLb)
      Else Dummy := PostMessageA(DlgFr, WM_COMMAND, ID_OK, 0);
    27 : DlgEnd := ID_CANCEL;
    9 :
      Begin
        K := -1;
        For I := 0 To DlgTabN - 1 Do If DlgTab[I] = Hw Then K := I;
        If DlgTabN > 0 Then
        Begin
          If (GetKeyState($10) And $8000) <> 0 Then K := (K + DlgTabN - 1) Mod DlgTabN
          Else K := (K + 1) Mod DlgTabN;
          If K < 0 Then K := 0;
          Dummy := SetFocus(DlgTab[K]);
        End;
      End;
  Else
    Exit;
  End;
  DlgKeyMsg := True;
End;

Function DlgRun(Focus : LongInt) : LongInt;
Begin
  Dummy := EnableWindow(Frame, 0);
  Dummy := SetActiveWindow(DlgFr);
  If Focus <> 0 Then Dummy := SetFocus(Focus);
  DlgEnd := 0;
  While DlgEnd = 0 Do
    If GetMessageA(LongInt(@Qmsg), 0, 0, 0) <= 0 Then
    Begin
      DlgEnd := ID_CANCEL;
      PostQuitMessage(0);
    End
    Else
    Begin
      If (Qmsg[1] = WM_KEYDOWN) And ((Qmsg[2] = 9) Or (Qmsg[2] = 13) Or (Qmsg[2] = 27)) Then
        If DlgKeyMsg(Qmsg[0], Qmsg[2]) Then Continue;
      Dummy := TranslateMessage(LongInt(@Qmsg));
      Dummy := DispatchMessageA(LongInt(@Qmsg));
    End;
  DlgRun := DlgEnd;
End;

Procedure DlgClose;
Begin
  Dummy := EnableWindow(Frame, 1);
  Dummy := SetActiveWindow(Frame);
  Dummy := DestroyWindow(DlgFr);
  DlgFr := 0; DlgLb := 0; DlgEf := 0; DlgTabN := 0;
  Dummy := SetFocus(Client);
End;

{ controle de la boite : (X, Y) depuis le coin bas gauche de la zone
  client (comme dans le debogueur d'origine) }
Function Ctl(Cls, Txt : String; Style, X, Y, W, H, Id : LongInt) : LongInt;
Var C, Ex : LongInt;
Begin
  Ex := 0;
  If (Cls = 'EDIT') Or (Cls = 'LISTBOX') Then Ex := WS_EX_CLIENTEDGE;
  PutZ(LongInt(@ClsBuf), Cls);
  C := CreateWindowExA(Ex, LongInt(@ClsBuf), Z(Txt), Style Or WS_CHILD Or WS_VISIBLE, X, DlgCliH - Y - H, W, H,
                       DlgCl, Id, Inst, 0);
  If (C <> 0) And ((Style And WS_TABSTOP) <> 0) And (DlgTabN < 16) Then
  Begin
    DlgTab[DlgTabN] := C;
    Inc(DlgTabN);
  End;
  Ctl := C;
End;

{ fond gris des textes : celui des controles STATIC de Windows }
Procedure Gray(H : LongInt);
Begin
End;

Function CtlText(H : LongInt) : String;
Var N : LongInt; B : Array[0..259] Of Byte; S : String;
Begin
  N := GetWindowTextA(H, LongInt(@B), 250);
  S := '';
  While (Length(S) < N) And (B[Length(S)] <> 0) Do S := S + Chr(B[Length(S)]);
  CtlText := S;
End;

{ touches communes : Entree = OK, Echap = Annuler }


Procedure DlgPaint(H : LongInt);
Var Hps, Br : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  Hps := BeginPaint(H, LongInt(@PaintS));
  Dummy := GetClientRect(H, LongInt(@Rc));
  Br := CreateSolidBrush($C0C0C0);
  Dummy := FillRect(Hps, LongInt(@Rc), Br);
  Dummy := DeleteObject(Br);
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

{ --- Ouvrir et Enregistrer sous --- }

Function FdMatch(N, M : String) : Boolean;
Var I, J, SI, SJ : LongInt;
Begin
  N := UpStr(N); M := UpStr(M);
  I := 1; J := 1; SI := 0; SJ := 0;
  While I <= Length(N) Do
  Begin
    If (J <= Length(M)) And ((M[J] = '?') Or (M[J] = N[I])) Then Begin Inc(I); Inc(J); End
    Else If (J <= Length(M)) And (M[J] = '*') Then Begin SJ := J; SI := I; Inc(J); End
    Else If SJ > 0 Then Begin J := SJ + 1; Inc(SI); I := SI; End
    Else Begin FdMatch := False; Exit; End;
  End;
  While (J <= Length(M)) And (M[J] = '*') Do Inc(J);
  FdMatch := J > Length(M);
End;

Procedure FdAdd(S : String);
Begin
  If FdN > 399 Then Exit;
  FdItem[FdN] := S; Inc(FdN);
  Dummy := SendMessageA(DlgLb, LB_ADDSTRING, 0, Z(S));
End;

{ repertoires puis fichiers du masque }
Procedure FdFill;
Var H, A, Pass : LongInt; S : String;
Begin
  Dummy := SendMessageA(DlgLb, LB_RESETCONTENT, 0, 0);
  FdN := 0;
  If Length(FdDir) > 3 Then FdAdd('[..]');
  For Pass := 1 To 2 Do
  Begin
    H := FindFirstFileA(Z(FdDir + '*.*'), LongInt(@FindBuf));
    If H <> -1 Then
    Begin
      Repeat
        A := FindBuf[0];
        S := GetZ(LongInt(@FindBuf) + 44);
        If (S <> '.') And (S <> '..') And (S <> '') Then
        Begin
          If Pass = 1 Then
          Begin
            If (A And $10) <> 0 Then FdAdd('[' + S + ']');
          End
          Else If ((A And $10) = 0) And ((FdMask = '*.*') Or FdMatch(S, FdMask)) Then FdAdd(S);
        End;
      Until FindNextFileA(H, LongInt(@FindBuf)) = 0;
      Dummy := FindClose(H);
    End;
  End;
  Dummy := SetWindowTextA(DlgDl, Z(FdDir + FdMask));
End;

Procedure FdEnter(D : String);
Var K : LongInt;
Begin
  If D = '..' Then
  Begin
    K := Length(FdDir) - 1;
    While (K > 0) And (FdDir[K] <> '\') Do Dec(K);
    If K > 0 Then FdDir := Copy(FdDir, 1, K);
  End
  Else FdDir := FdDir + D + '\';
  FdFill;
End;

{ choix du nom S (champ ou liste) : True si la boite est finie }
Function FdChoose(S : String) : Boolean;
Var H, A : LongInt;
Begin
  FdChoose := False;
  While (S <> '') And (S[1] = ' ') Do Delete(S, 1, 1);
  While (S <> '') And (S[Length(S)] = ' ') Do Delete(S, Length(S), 1);
  If S = '' Then Exit;
  If (S[1] = '[') And (S[Length(S)] = ']') Then
  Begin
    FdEnter(Copy(S, 2, Length(S) - 2));
    Exit;
  End;
  If (Pos('*', S) > 0) Or (Pos('?', S) > 0) Then
  Begin
    FdMask := S; FdFill;
    Exit;
  End;
  If (Length(S) = 2) And (S[2] = ':') Then S := S + '\';
  If (Pos(':', S) = 0) And (S[1] <> '\') Then S := FdDir + S
  Else If S[1] = '\' Then S := Copy(FdDir, 1, 2) + S;
  If S[Length(S)] = '\' Then
  Begin
    FdDir := S; FdFill;
    Exit;
  End;
  { repertoire existant : on y entre }
  H := FindFirstFileA(Z(S), LongInt(@FindBuf));
  If H <> -1 Then
  Begin
    A := FindBuf[0];
    Dummy := FindClose(H);
    If (A And $10) <> 0 Then
    Begin
      FdDir := S + '\'; FdFill;
      Exit;
    End;
  End;
  FdRes := S;
  FdChoose := True;
End;

Function FileProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var I : LongInt;
Begin
  FileProc := 0;
  Case Msg Of
    WM_PAINT : DlgPaint(H);
    WM_COMMAND :
      If Lo16(Mp1) = ID_LIST Then
      Begin
        I := SendMessageA(DlgLb, LB_GETCURSEL, 0, 0);
        If (I >= 0) And (I < FdN) Then
        Begin
          If Hi16(Mp1) = LBN_DBLCLK Then
          Begin
            If FdChoose(FdItem[I]) Then DlgEnd := ID_OK;
          End
          Else If Hi16(Mp1) = LBN_SELCHANGE Then
            If FdItem[I][1] <> '[' Then Dummy := SetWindowTextA(DlgEf, Z(FdItem[I]));
        End;
      End
      Else If Lo16(Mp1) = ID_OK Then
      Begin
        If FdChoose(CtlText(DlgEf)) Then DlgEnd := ID_OK;
      End
      Else If Lo16(Mp1) = ID_CANCEL Then DlgEnd := ID_CANCEL;
    WM_CLOSE : DlgEnd := ID_CANCEL;
  Else
    FileProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ boite Ouvrir (Save False) ou Enregistrer sous ; Name : nom propose,
  recoit le nom complet choisi }
Function FileDialog(Save : Boolean; Var Name : String) : Boolean;
Var W, H, C : LongInt; S, Title : String;
Begin
  FileDialog := False;
  W := 440; H := 330;
  If Save Then Title := L('Enregistrer sous', 'Save As', 'Speichern unter', 'Salva con nome', 'Guardar como')
  Else Title := L('Ouvrir', 'Open', #148'ffnen', 'Apri', 'Abrir');
  If Not DlgOpen('NPFILE', Title, W, H) Then Exit;
  C := Ctl('STATIC', (L('Nom du fichier :', 'File name:', 'Dateiname:', 'Nome file:', 'Nombre:')),
           0, 10, H - 28, W - 20, 20, 10);
  Gray(C);
  DlgEf := Ctl('EDIT', '', WS_TABSTOP Or ES_AUTOHSCROLL, 10, H - 52, W - 20, 20, ID_EF);
  Dummy := SendMessageA(DlgEf, EM_LIMITTEXT, 250, 0);
  C := Ctl('STATIC', (L('R'#130'pertoire :', 'Folder:', 'Ordner:', 'Cartella:', 'Carpeta:')),
           0, 10, H - 78, 100, 20, 11);
  Gray(C);
  DlgDl := Ctl('STATIC', '', 0, 110, H - 78, W - 120, 20, 12);
  Gray(DlgDl);
  DlgLb := Ctl('LISTBOX', '', WS_TABSTOP Or LBS_NOTIFY Or WS_VSCROLL, 10, 44, W - 20, H - 44 - 86, ID_LIST);
  If Save Then S := L('Enregistrer', 'Save', 'Speichern', 'Salva', 'Guardar') Else S := L('Ouvrir', 'Open', #148'ffnen', 'Apri', 'Abrir');
  Dummy := Ctl('BUTTON', (S), WS_TABSTOP Or BS_DEFPUSHBUTTON, W - 208, 8, 96, 26, ID_OK);
  Dummy := Ctl('BUTTON', (L('Annuler', 'Cancel', 'Abbrechen', 'Annulla', 'Cancelar')),
               WS_TABSTOP Or BS_PUSHBUTTON, W - 104, 8, 96, 26, ID_CANCEL);
  FdSave := Save;
  FdMask := FdMaskInit;
  FdDir := DirOf(Name);
  If FdDir = '' Then FdDir := CurDir;
  S := BaseName(Name);
  FdFill;
  Dummy := SetWindowTextA(DlgEf, Z(S));
  Dummy := SendMessageA(DlgEf, EM_SETSEL, 0, Length(S));
  FdRes := '';
  If DlgRun(DlgEf) = ID_OK Then
  Begin
    Name := FdRes;
    FileDialog := True;
  End;
  DlgClose;
End;


{ ------------------------------------------------------------- menus }

{ menus : pile des menus en construction ; MItem avec MIS_SUBMENU annonce
  le sous-menu que le MenuOpen suivant cree }
Var
  MStk : Array[0..3] Of LongInt;
  MDepth : LongInt;
  MSubText : String;

Function MenuText(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  MenuText := S;
End;

Function MenuOpen : LongInt;
Var H : LongInt;
Begin
  If MDepth = 0 Then H := CreateMenu Else H := CreatePopupMenu;
  If MDepth > 0 Then Dummy := AppendMenuA(MStk[MDepth - 1], MF_POPUP, H, Z(MenuText(MSubText)));
  If MDepth < 4 Then
  Begin
    MStk[MDepth] := H;
    Inc(MDepth);
  End;
  MenuOpen := H;
End;

Procedure MenuClose(H, Count : LongInt);
Begin
  If MDepth > 0 Then Dec(MDepth);
End;

Procedure MItem(Style, Attr, Id : LongInt; S : String);
Begin
  If (Style And MIS_SUBMENU) <> 0 Then
  Begin
    MSubText := S;
    Exit;
  End;
  If MDepth = 0 Then Exit;
  If (Style And MIS_SEPARATOR) <> 0 Then Dummy := AppendMenuA(MStk[MDepth - 1], MF_SEPARATOR, 0, 0)
  Else Dummy := AppendMenuA(MStk[MDepth - 1], MF_STRING Or Attr, Id, Z(MenuText(S)));
End;


{ ------------------------------------------------------------------ }
{ Desassembleur x86 32 bits (syntaxe Intel, comme Turbo Debugger)    }
{ ------------------------------------------------------------------ }
{ Le texte produit est colore : chaque morceau commence par un code    }
{ de couleur (Chr(1) instruction, Chr(2) registre, Chr(3) nombre,      }
{ Chr(4) symbole, Chr(5) ponctuation, Chr(6) mot-cle : ptr, prefixe). }

Const
  KMnem = 1; KReg = 2; KNum = 3; KSym = 4; KPun = 5; KKey = 6;
  R32 : Array[0..7] Of String[3] = ('eax', 'ecx', 'edx', 'ebx', 'esp', 'ebp', 'esi', 'edi');
  R16 : Array[0..7] Of String[3] = ('ax', 'cx', 'dx', 'bx', 'sp', 'bp', 'si', 'di');
  R8 : Array[0..7] Of String[3] = ('al', 'cl', 'dl', 'bl', 'ah', 'ch', 'dh', 'bh');
  RSeg : Array[0..7] Of String[3] = ('es', 'cs', 'ss', 'ds', 'fs', 'gs', '?', '?');
  Grp1 : Array[0..7] Of String[4] = ('add', 'or', 'adc', 'sbb', 'and', 'sub', 'xor', 'cmp');
  Grp2 : Array[0..7] Of String[4] = ('rol', 'ror', 'rcl', 'rcr', 'shl', 'shr', 'sal', 'sar');
  Grp3 : Array[0..7] Of String[4] = ('test', 'test', 'not', 'neg', 'mul', 'imul', 'div', 'idiv');
  CC : Array[0..15] Of String[3] = ('o', 'no', 'b', 'nb', 'z', 'nz', 'be', 'a', 's', 'ns', 'p', 'np', 'l', 'nl', 'le', 'g');

Var
  DBuf : Array[0..31] Of Byte;      { octets de l'instruction }
  DPos : LongInt;                   { prochain octet de DBuf }
  DAddr : LongInt;                  { adresse de l'instruction }
  DText : String;                   { texte colore }
  DTarget : LongInt;                { destination d'un saut ou d'un appel (-1) }
  DIsCall, DOps16, DBad : Boolean;
  DSeg : LongInt;                   { prefixe de segment (-1) }
  DRep : LongInt;                   { F2h, F3h ou 0 }

Function HexDig(V, N : LongInt) : String;
Const H : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 1 To N Do
  Begin
    S := H[(V And 15) + 1] + S;
    V := V Shr 4;
  End;
  HexDig := S;
End;

{ nombre : decimal sous 10, sinon hexadecimal (0 devant une lettre) suivi de h }
Function NumStr(V : LongInt) : String;
Var S : String;
Begin
  If (V >= 0) And (V < 10) Then
  Begin
    NumStr := Chr(48 + V);
    Exit;
  End;
  S := HexDig(V, 8);
  While (Length(S) > 1) And (S[1] = '0') Do Delete(S, 1, 1);
  If S[1] >= 'A' Then S := '0' + S;
  NumStr := S + 'h';
End;

Procedure Em(K : LongInt; S : String);
Begin
  DText := DText + Chr(K) + S;
End;

Function Fb : LongInt;
Begin
  Fb := DBuf[DPos];
  Inc(DPos);
End;

Function Fw : LongInt;
Begin
  Fw := DBuf[DPos] Or (DBuf[DPos + 1] Shl 8);
  Inc(DPos, 2);
End;

Function Fd : LongInt;
Begin
  Fd := DBuf[DPos] Or (DBuf[DPos + 1] Shl 8) Or (DBuf[DPos + 2] Shl 16) Or (DBuf[DPos + 3] Shl 24);
  Inc(DPos, 4);
End;

Function Sx8(V : LongInt) : LongInt;
Begin
  If V >= $80 Then V := V - $100;
  Sx8 := V;
End;

Function Sx16(V : LongInt) : LongInt;
Begin
  If V >= $8000 Then V := V - $10000;
  Sx16 := V;
End;

{ symbole d'une adresse (defini plus loin par le debogueur) }
Function SymOf(A : LongInt) : String; Forward;

Procedure EmAddr(A : LongInt);
Var S : String;
Begin
  S := SymOf(A);
  If S <> '' Then Em(KSym, S) Else Em(KNum, HexDig(A, 8) + 'h');
End;

Procedure EmMnem(S : String);
Begin
  If DRep = $F3 Then Em(KKey, 'rep ')
  Else If DRep = $F2 Then Em(KKey, 'repne ');
  DRep := 0;
  Em(KMnem, S);
  Em(KPun, ' ');
End;

Procedure EmReg(Size, R : LongInt);
Begin
  Case Size Of
    1 : Em(KReg, R8[R And 7]);
    2 : Em(KReg, R16[R And 7]);
  Else
    Em(KReg, R32[R And 7]);
  End;
End;

Procedure EmImm(V : LongInt);
Var S : String;
Begin
  S := '';
  If (V >= $400000) Or (V < -$10000) Then S := SymOf(V);
  If S <> '' Then
  Begin
    Em(KKey, 'offset ');
    Em(KSym, S);
  End
  Else Em(KNum, NumStr(V));
End;

Procedure Comma;
Begin
  Em(KPun, ',');
End;

{ operande memoire ou registre du ModR/M (Size : 0 sans taille, 1, 2, 4,
  6 fword, 8 qword, 10 tbyte) }
Procedure EmRM(Md, Rm, Size : LongInt);
Var Sib, Base, Idx, Sc, Disp : LongInt; HasBase, HasIdx, First : Boolean; S : String;
Begin
  If Md = 3 Then
  Begin
    EmReg(Size, Rm);
    Exit;
  End;
  Case Size Of
    1 : Em(KKey, 'byte ptr ');
    2 : Em(KKey, 'word ptr ');
    4 : Em(KKey, 'dword ptr ');
    6 : Em(KKey, 'fword ptr ');
    8 : Em(KKey, 'qword ptr ');
    10 : Em(KKey, 'tbyte ptr ');
  End;
  If DSeg >= 0 Then
  Begin
    Em(KReg, RSeg[DSeg]);
    Em(KPun, ':');
  End;
  HasBase := True; HasIdx := False; Base := Rm; Idx := 0; Sc := 0; Disp := 0;
  If Rm = 4 Then
  Begin
    Sib := Fb;
    Sc := Sib Shr 6; Idx := (Sib Shr 3) And 7; Base := Sib And 7;
    HasIdx := Idx <> 4;
    If (Base = 5) And (Md = 0) Then
    Begin
      HasBase := False;
      Disp := Fd;
    End;
  End
  Else If (Rm = 5) And (Md = 0) Then
  Begin
    HasBase := False;
    Disp := Fd;
    Em(KPun, '[');
    S := SymOf(Disp);
    If S <> '' Then Em(KSym, S) Else Em(KNum, HexDig(Disp, 8) + 'h');
    Em(KPun, ']');
    Exit;
  End;
  If Md = 1 Then Disp := Sx8(Fb)
  Else If Md = 2 Then Disp := Fd;
  Em(KPun, '[');
  First := True;
  If HasBase Then
  Begin
    Em(KReg, R32[Base]);
    First := False;
  End;
  If HasIdx Then
  Begin
    If Not First Then Em(KPun, '+');
    Em(KReg, R32[Idx]);
    If Sc > 0 Then
    Begin
      Em(KPun, '*');
      Em(KNum, Chr(48 + (1 Shl Sc)));
    End;
    First := False;
  End;
  If First Then
  Begin
    S := SymOf(Disp);
    If S <> '' Then Em(KSym, S) Else Em(KNum, HexDig(Disp, 8) + 'h');
  End
  Else If Disp < 0 Then
  Begin
    Em(KPun, '-');
    Em(KNum, NumStr(-Disp));
  End
  Else If Disp > 0 Then
  Begin
    Em(KPun, '+');
    S := '';
    If Disp >= $400000 Then S := SymOf(Disp);
    If S <> '' Then Em(KSym, S) Else Em(KNum, NumStr(Disp));
  End;
  Em(KPun, ']');
End;

Procedure EmRel(Rel : LongInt);
Begin
  DTarget := DAddr + DPos + Rel;
  EmAddr(DTarget);
End;

{ instructions du coprocesseur (D8h a DFh) }
Procedure DisFpu(Op : LongInt);
Const
  MD8 : Array[0..7] Of String[5] = ('fadd', 'fmul', 'fcom', 'fcomp', 'fsub', 'fsubr', 'fdiv', 'fdivr');
  MDA : Array[0..7] Of String[6] = ('fiadd', 'fimul', 'ficom', 'ficomp', 'fisub', 'fisubr', 'fidiv', 'fidivr');
  D9R : Array[0..31] Of String[7] = ('fchs', 'fabs', '?', '?', 'ftst', 'fxam', '?', '?',
    'fld1', 'fldl2t', 'fldl2e', 'fldpi', 'fldlg2', 'fldln2', 'fldz', '?',
    'f2xm1', 'fyl2x', 'fptan', 'fpatan', 'fxtract', 'fprem1', 'fdecstp', 'fincstp',
    'fprem', 'fyl2xp1', 'fsqrt', 'fsincos', 'frndint', 'fscale', 'fsin', 'fcos');
Var M, Md, R, Rm : LongInt; S : String;
Begin
  M := Fb; Md := M Shr 6; R := (M Shr 3) And 7; Rm := M And 7;
  If Md <> 3 Then
  Begin
    Case Op Of
      $D8 : Begin EmMnem(MD8[R]); EmRM(Md, Rm, 4); End;
      $DC : Begin EmMnem(MD8[R]); EmRM(Md, Rm, 8); End;
      $DA : Begin EmMnem(MDA[R]); EmRM(Md, Rm, 4); End;
      $DE : Begin EmMnem(MDA[R]); EmRM(Md, Rm, 2); End;
      $D9 :
        Case R Of
          0 : Begin EmMnem('fld'); EmRM(Md, Rm, 4); End;
          2 : Begin EmMnem('fst'); EmRM(Md, Rm, 4); End;
          3 : Begin EmMnem('fstp'); EmRM(Md, Rm, 4); End;
          4 : Begin EmMnem('fldenv'); EmRM(Md, Rm, 0); End;
          5 : Begin EmMnem('fldcw'); EmRM(Md, Rm, 2); End;
          6 : Begin EmMnem('fnstenv'); EmRM(Md, Rm, 0); End;
          7 : Begin EmMnem('fnstcw'); EmRM(Md, Rm, 2); End;
        Else Begin EmMnem('(bad)'); EmRM(Md, Rm, 0); End;
        End;
      $DB :
        Case R Of
          0 : Begin EmMnem('fild'); EmRM(Md, Rm, 4); End;
          1 : Begin EmMnem('fisttp'); EmRM(Md, Rm, 4); End;
          2 : Begin EmMnem('fist'); EmRM(Md, Rm, 4); End;
          3 : Begin EmMnem('fistp'); EmRM(Md, Rm, 4); End;
          5 : Begin EmMnem('fld'); EmRM(Md, Rm, 10); End;
          7 : Begin EmMnem('fstp'); EmRM(Md, Rm, 10); End;
        Else Begin EmMnem('(bad)'); EmRM(Md, Rm, 0); End;
        End;
      $DD :
        Case R Of
          0 : Begin EmMnem('fld'); EmRM(Md, Rm, 8); End;
          1 : Begin EmMnem('fisttp'); EmRM(Md, Rm, 8); End;
          2 : Begin EmMnem('fst'); EmRM(Md, Rm, 8); End;
          3 : Begin EmMnem('fstp'); EmRM(Md, Rm, 8); End;
          4 : Begin EmMnem('frstor'); EmRM(Md, Rm, 0); End;
          6 : Begin EmMnem('fnsave'); EmRM(Md, Rm, 0); End;
          7 : Begin EmMnem('fnstsw'); EmRM(Md, Rm, 2); End;
        Else Begin EmMnem('(bad)'); EmRM(Md, Rm, 0); End;
        End;
      $DF :
        Case R Of
          0 : Begin EmMnem('fild'); EmRM(Md, Rm, 2); End;
          1 : Begin EmMnem('fisttp'); EmRM(Md, Rm, 2); End;
          2 : Begin EmMnem('fist'); EmRM(Md, Rm, 2); End;
          3 : Begin EmMnem('fistp'); EmRM(Md, Rm, 2); End;
          4 : Begin EmMnem('fbld'); EmRM(Md, Rm, 10); End;
          5 : Begin EmMnem('fild'); EmRM(Md, Rm, 8); End;
          6 : Begin EmMnem('fbstp'); EmRM(Md, Rm, 10); End;
          7 : Begin EmMnem('fistp'); EmRM(Md, Rm, 8); End;
        End;
    End;
    Exit;
  End;
  { formes registre : st, st(i) }
  S := 'st(' + Chr(48 + Rm) + ')';
  Case Op Of
    $D8 : Begin EmMnem(MD8[R]); Em(KReg, 'st'); Comma; Em(KReg, S); End;
    $DC :
      Begin
        Case R Of
          4 : EmMnem('fsubr');
          5 : EmMnem('fsub');
          6 : EmMnem('fdivr');
          7 : EmMnem('fdiv');
        Else EmMnem(MD8[R]);
        End;
        Em(KReg, S); Comma; Em(KReg, 'st');
      End;
    $DE :
      If M = $D9 Then EmMnem('fcompp')
      Else
      Begin
        Case R Of
          0 : EmMnem('faddp');
          1 : EmMnem('fmulp');
          4 : EmMnem('fsubrp');
          5 : EmMnem('fsubp');
          6 : EmMnem('fdivrp');
          7 : EmMnem('fdivp');
        Else EmMnem(MD8[R] + 'p');
        End;
        Em(KReg, S); Comma; Em(KReg, 'st');
      End;
    $D9 :
      If R = 0 Then Begin EmMnem('fld'); Em(KReg, S); End
      Else If R = 1 Then Begin EmMnem('fxch'); Em(KReg, S); End
      Else If M = $D0 Then EmMnem('fnop')
      Else If M >= $E0 Then EmMnem(D9R[M - $E0])
      Else EmMnem('(bad)');
    $DA :
      If M = $E9 Then EmMnem('fucompp')
      Else Begin EmMnem('fcmov'); Em(KReg, 'st'); Comma; Em(KReg, S); End;
    $DB :
      If M = $E2 Then EmMnem('fnclex')
      Else If M = $E3 Then EmMnem('fninit')
      Else If R = 5 Then Begin EmMnem('fucomi'); Em(KReg, 'st'); Comma; Em(KReg, S); End
      Else If R = 6 Then Begin EmMnem('fcomi'); Em(KReg, 'st'); Comma; Em(KReg, S); End
      Else Begin EmMnem('fcmovn'); Em(KReg, 'st'); Comma; Em(KReg, S); End;
    $DD :
      Case R Of
        0 : Begin EmMnem('ffree'); Em(KReg, S); End;
        2 : Begin EmMnem('fst'); Em(KReg, S); End;
        3 : Begin EmMnem('fstp'); Em(KReg, S); End;
        4 : Begin EmMnem('fucom'); Em(KReg, S); End;
        5 : Begin EmMnem('fucomp'); Em(KReg, S); End;
      Else EmMnem('(bad)');
      End;
    $DF :
      If M = $E0 Then Begin EmMnem('fnstsw'); Em(KReg, 'ax'); End
      Else If R = 5 Then Begin EmMnem('fucomip'); Em(KReg, 'st'); Comma; Em(KReg, S); End
      Else If R = 6 Then Begin EmMnem('fcomip'); Em(KReg, 'st'); Comma; Em(KReg, S); End
      Else EmMnem('(bad)');
  End;
End;

{ instructions a deux octets (0Fh xx) }
Procedure Dis0F;
Var Op, M, Md, R, Rm, Sz : LongInt;
  Procedure ModRM;
  Begin
    M := Fb; Md := M Shr 6; R := (M Shr 3) And 7; Rm := M And 7;
  End;
Begin
  Op := Fb;
  If DOps16 Then Sz := 2 Else Sz := 4;
  Case Op Of
    $80..$8F :
      Begin
        EmMnem('j' + CC[Op - $80]);
        EmRel(Fd);
      End;
    $90..$9F :
      Begin
        ModRM;
        EmMnem('set' + CC[Op - $90]);
        EmRM(Md, Rm, 1);
      End;
    $40..$4F :
      Begin
        ModRM;
        EmMnem('cmov' + CC[Op - $40]);
        EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz);
      End;
    $B6, $B7, $BE, $BF :
      Begin
        ModRM;
        If Op < $BE Then EmMnem('movzx') Else EmMnem('movsx');
        EmReg(Sz, R); Comma;
        If (Op And 1) = 0 Then EmRM(Md, Rm, 1) Else EmRM(Md, Rm, 2);
      End;
    $AF : Begin ModRM; EmMnem('imul'); EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz); End;
    $A3, $AB, $B3, $BB :
      Begin
        ModRM;
        Case Op Of
          $A3 : EmMnem('bt');
          $AB : EmMnem('bts');
          $B3 : EmMnem('btr');
        Else EmMnem('btc');
        End;
        EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R);
      End;
    $BA :
      Begin
        ModRM;
        Case R Of
          4 : EmMnem('bt');
          5 : EmMnem('bts');
          6 : EmMnem('btr');
        Else EmMnem('btc');
        End;
        EmRM(Md, Rm, Sz); Comma; EmImm(Fb);
      End;
    $BC, $BD :
      Begin
        ModRM;
        If Op = $BC Then EmMnem('bsf') Else EmMnem('bsr');
        EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz);
      End;
    $A4, $A5, $AC, $AD :
      Begin
        ModRM;
        If Op < $AC Then EmMnem('shld') Else EmMnem('shrd');
        EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); Comma;
        If (Op And 1) = 0 Then EmImm(Fb) Else Em(KReg, 'cl');
      End;
    $B0, $B1 : Begin ModRM; EmMnem('cmpxchg'); If Op = $B0 Then Sz := 1; EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
    $C0, $C1 : Begin ModRM; EmMnem('xadd'); If Op = $C0 Then Sz := 1; EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
    $C8..$CF : Begin EmMnem('bswap'); EmReg(4, Op - $C8); End;
    $A0 : Begin EmMnem('push'); Em(KReg, 'fs'); End;
    $A1 : Begin EmMnem('pop'); Em(KReg, 'fs'); End;
    $A8 : Begin EmMnem('push'); Em(KReg, 'gs'); End;
    $A9 : Begin EmMnem('pop'); Em(KReg, 'gs'); End;
    $A2 : EmMnem('cpuid');
    $31 : EmMnem('rdtsc');
    $06 : EmMnem('clts');
    $08 : EmMnem('invd');
    $09 : EmMnem('wbinvd');
    $0B : EmMnem('ud2');
    $20, $22 :
      Begin
        ModRM;
        EmMnem('mov');
        If Op = $20 Then Begin EmReg(4, Rm); Comma; Em(KReg, 'cr' + Chr(48 + R)); End
        Else Begin Em(KReg, 'cr' + Chr(48 + R)); Comma; EmReg(4, Rm); End;
      End;
    $00 :
      Begin
        ModRM;
        Case R Of
          0 : EmMnem('sldt');
          1 : EmMnem('str');
          2 : EmMnem('lldt');
          3 : EmMnem('ltr');
          4 : EmMnem('verr');
          5 : EmMnem('verw');
        Else EmMnem('(bad)');
        End;
        EmRM(Md, Rm, 2);
      End;
    $01 :
      Begin
        ModRM;
        Case R Of
          0 : EmMnem('sgdt');
          1 : EmMnem('sidt');
          2 : EmMnem('lgdt');
          3 : EmMnem('lidt');
          4 : EmMnem('smsw');
          6 : EmMnem('lmsw');
          7 : EmMnem('invlpg');
        Else EmMnem('(bad)');
        End;
        If (R = 4) Or (R = 6) Then EmRM(Md, Rm, 2) Else EmRM(Md, Rm, 0);
      End;
  Else
    Begin
      Em(KMnem, 'db');
      Em(KPun, ' ');
      Em(KNum, '0Fh');
      Comma;
      Em(KNum, HexDig(Op, 2) + 'h');
      DBad := True;
    End;
  End;
End;

{ desassembler l'instruction de DBuf (adresse A) ; rend sa longueur }
Function Disasm(A : LongInt) : LongInt;
Var Op, M, Md, R, Rm, Sz, V, N : LongInt; Done : Boolean;
  Procedure ModRM;
  Begin
    M := Fb; Md := M Shr 6; R := (M Shr 3) And 7; Rm := M And 7;
  End;
  Procedure ImmV;
  Begin
    If DOps16 Then EmImm(Fw) Else EmImm(Fd);
  End;
Begin
  DAddr := A; DPos := 0; DText := ''; DTarget := -1; DIsCall := False; DOps16 := False; DBad := False;
  DSeg := -1; DRep := 0;
  { prefixes }
  Done := False; N := 0;
  Repeat
    Op := DBuf[DPos];
    Case Op Of
      $66 : Begin DOps16 := True; Inc(DPos); End;
      $67 : Inc(DPos);
      $F2, $F3 : Begin DRep := Op; Inc(DPos); End;
      $F0 : Begin Em(KKey, 'lock '); Inc(DPos); End;
      $26 : Begin DSeg := 0; Inc(DPos); End;
      $2E : Begin DSeg := 1; Inc(DPos); End;
      $36 : Begin DSeg := 2; Inc(DPos); End;
      $3E : Begin DSeg := 3; Inc(DPos); End;
      $64 : Begin DSeg := 4; Inc(DPos); End;
      $65 : Begin DSeg := 5; Inc(DPos); End;
    Else Done := True;
    End;
    Inc(N);
  Until Done Or (N > 6);
  If DOps16 Then Sz := 2 Else Sz := 4;
  Op := Fb;
  Case Op Of
    $00..$3F :
      If (Op And 7) <= 5 Then
      Begin
        EmMnem(Grp1[Op Shr 3]);
        Case Op And 7 Of
          0 : Begin ModRM; EmRM(Md, Rm, 1); Comma; EmReg(1, R); End;
          1 : Begin ModRM; EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
          2 : Begin ModRM; EmReg(1, R); Comma; EmRM(Md, Rm, 1); End;
          3 : Begin ModRM; EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz); End;
          4 : Begin Em(KReg, 'al'); Comma; EmImm(Fb); End;
          5 : Begin EmReg(Sz, 0); Comma; ImmV; End;
        End;
      End
      Else
        Case Op Of
          $06, $0E, $16, $1E : Begin EmMnem('push'); Em(KReg, RSeg[Op Shr 3]); End;
          $07, $17, $1F : Begin EmMnem('pop'); Em(KReg, RSeg[Op Shr 3]); End;
          $27 : EmMnem('daa');
          $2F : EmMnem('das');
          $37 : EmMnem('aaa');
          $3F : EmMnem('aas');
          $0F : Dis0F;
        Else Begin EmMnem('(bad)'); DBad := True; End;
        End;
    $40..$47 : Begin EmMnem('inc'); EmReg(Sz, Op - $40); End;
    $48..$4F : Begin EmMnem('dec'); EmReg(Sz, Op - $48); End;
    $50..$57 : Begin EmMnem('push'); EmReg(Sz, Op - $50); End;
    $58..$5F : Begin EmMnem('pop'); EmReg(Sz, Op - $58); End;
    $60 : If DOps16 Then EmMnem('pusha') Else EmMnem('pushad');
    $61 : If DOps16 Then EmMnem('popa') Else EmMnem('popad');
    $62 : Begin ModRM; EmMnem('bound'); EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz * 2); End;
    $63 : Begin ModRM; EmMnem('arpl'); EmRM(Md, Rm, 2); Comma; EmReg(2, R); End;
    $68 : Begin EmMnem('push'); If DOps16 Then EmImm(Fw) Else Begin V := Fd; If SymOf(V) <> '' Then EmAddr(V) Else EmImm(V); End; End;
    $6A : Begin EmMnem('push'); EmImm(Sx8(Fb) And $FFFFFFFF); End;
    $69 : Begin ModRM; EmMnem('imul'); EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz); Comma; ImmV; End;
    $6B : Begin ModRM; EmMnem('imul'); EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz); Comma; EmImm(Sx8(Fb)); End;
    $6C : EmMnem('insb');
    $6D : If DOps16 Then EmMnem('insw') Else EmMnem('insd');
    $6E : EmMnem('outsb');
    $6F : If DOps16 Then EmMnem('outsw') Else EmMnem('outsd');
    $70..$7F : Begin EmMnem('j' + CC[Op - $70]); EmRel(Sx8(Fb)); End;
    $80, $82 : Begin ModRM; EmMnem(Grp1[R]); EmRM(Md, Rm, 1); Comma; EmImm(Fb); End;
    $81 : Begin ModRM; EmMnem(Grp1[R]); EmRM(Md, Rm, Sz); Comma; ImmV; End;
    $83 :
      Begin
        ModRM; EmMnem(Grp1[R]); EmRM(Md, Rm, Sz); Comma;
        V := Sx8(Fb);
        If V < 0 Then Begin Em(KPun, '-'); EmImm(-V); End Else EmImm(V);
      End;
    $84 : Begin ModRM; EmMnem('test'); EmRM(Md, Rm, 1); Comma; EmReg(1, R); End;
    $85 : Begin ModRM; EmMnem('test'); EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
    $86 : Begin ModRM; EmMnem('xchg'); EmRM(Md, Rm, 1); Comma; EmReg(1, R); End;
    $87 : Begin ModRM; EmMnem('xchg'); EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
    $88 : Begin ModRM; EmMnem('mov'); EmRM(Md, Rm, 1); Comma; EmReg(1, R); End;
    $89 : Begin ModRM; EmMnem('mov'); EmRM(Md, Rm, Sz); Comma; EmReg(Sz, R); End;
    $8A : Begin ModRM; EmMnem('mov'); EmReg(1, R); Comma; EmRM(Md, Rm, 1); End;
    $8B : Begin ModRM; EmMnem('mov'); EmReg(Sz, R); Comma; EmRM(Md, Rm, Sz); End;
    $8C : Begin ModRM; EmMnem('mov'); EmRM(Md, Rm, 2); Comma; Em(KReg, RSeg[R]); End;
    $8D : Begin ModRM; EmMnem('lea'); EmReg(Sz, R); Comma; EmRM(Md, Rm, 0); End;
    $8E : Begin ModRM; EmMnem('mov'); Em(KReg, RSeg[R]); Comma; EmRM(Md, Rm, 2); End;
    $8F : Begin ModRM; EmMnem('pop'); EmRM(Md, Rm, Sz); End;
    $90 : If DRep = $F3 Then Begin DRep := 0; EmMnem('pause'); End Else EmMnem('nop');
    $91..$97 : Begin EmMnem('xchg'); EmReg(Sz, 0); Comma; EmReg(Sz, Op - $90); End;
    $98 : If DOps16 Then EmMnem('cbw') Else EmMnem('cwde');
    $99 : If DOps16 Then EmMnem('cwd') Else EmMnem('cdq');
    $9A : Begin EmMnem('call'); Em(KKey, 'far '); V := Fd; Em(KNum, HexDig(Fw, 4)); Em(KPun, ':'); Em(KNum, HexDig(V, 8)); DIsCall := True; End;
    $9B : EmMnem('wait');
    $9C : If DOps16 Then EmMnem('pushf') Else EmMnem('pushfd');
    $9D : If DOps16 Then EmMnem('popf') Else EmMnem('popfd');
    $9E : EmMnem('sahf');
    $9F : EmMnem('lahf');
    $A0..$A3 :
      Begin
        EmMnem('mov'); V := Fd;
        If Op = $A0 Then Begin Em(KReg, 'al'); Comma; End
        Else If Op = $A1 Then Begin EmReg(Sz, 0); Comma; End;
        If Odd(Op) Then Begin If DOps16 Then Em(KKey, 'word ptr ') Else Em(KKey, 'dword ptr '); End
        Else Em(KKey, 'byte ptr ');
        Em(KPun, '['); EmAddr(V); Em(KPun, ']');
        If Op = $A2 Then Begin Comma; Em(KReg, 'al'); End
        Else If Op = $A3 Then Begin Comma; EmReg(Sz, 0); End;
      End;
    $A4 : EmMnem('movsb');
    $A5 : If DOps16 Then EmMnem('movsw') Else EmMnem('movsd');
    $A6 : EmMnem('cmpsb');
    $A7 : If DOps16 Then EmMnem('cmpsw') Else EmMnem('cmpsd');
    $A8 : Begin EmMnem('test'); Em(KReg, 'al'); Comma; EmImm(Fb); End;
    $A9 : Begin EmMnem('test'); EmReg(Sz, 0); Comma; ImmV; End;
    $AA : EmMnem('stosb');
    $AB : If DOps16 Then EmMnem('stosw') Else EmMnem('stosd');
    $AC : EmMnem('lodsb');
    $AD : If DOps16 Then EmMnem('lodsw') Else EmMnem('lodsd');
    $AE : EmMnem('scasb');
    $AF : If DOps16 Then EmMnem('scasw') Else EmMnem('scasd');
    $B0..$B7 : Begin EmMnem('mov'); EmReg(1, Op - $B0); Comma; EmImm(Fb); End;
    $B8..$BF :
      Begin
        EmMnem('mov'); EmReg(Sz, Op - $B8); Comma;
        If DOps16 Then EmImm(Fw)
        Else
        Begin
          V := Fd;
          If (V >= $400000) And (SymOf(V) <> '') Then EmAddr(V) Else EmImm(V);
        End;
      End;
    $C0, $C1 :
      Begin
        ModRM; EmMnem(Grp2[R]);
        If Op = $C0 Then EmRM(Md, Rm, 1) Else EmRM(Md, Rm, Sz);
        Comma; EmImm(Fb);
      End;
    $C2 : Begin EmMnem('ret'); EmImm(Fw); End;
    $C3 : EmMnem('ret');
    $C4 : Begin ModRM; EmMnem('les'); EmReg(Sz, R); Comma; EmRM(Md, Rm, 6); End;
    $C5 : Begin ModRM; EmMnem('lds'); EmReg(Sz, R); Comma; EmRM(Md, Rm, 6); End;
    $C6 : Begin ModRM; EmMnem('mov'); EmRM(Md, Rm, 1); Comma; EmImm(Fb); End;
    $C7 :
      Begin
        ModRM; EmMnem('mov'); EmRM(Md, Rm, Sz); Comma;
        If DOps16 Then EmImm(Fw)
        Else
        Begin
          V := Fd;
          If (V >= $400000) And (SymOf(V) <> '') Then EmAddr(V) Else EmImm(V);
        End;
      End;
    $C8 : Begin EmMnem('enter'); EmImm(Fw); Comma; EmImm(Fb); End;
    $C9 : EmMnem('leave');
    $CA : Begin EmMnem('retf'); EmImm(Fw); End;
    $CB : EmMnem('retf');
    $CC : EmMnem('int3');
    $CD : Begin EmMnem('int'); EmImm(Fb); End;
    $CE : EmMnem('into');
    $CF : If DOps16 Then EmMnem('iret') Else EmMnem('iretd');
    $D0..$D3 :
      Begin
        ModRM; EmMnem(Grp2[R]);
        If Odd(Op) Then EmRM(Md, Rm, Sz) Else EmRM(Md, Rm, 1);
        Comma;
        If Op >= $D2 Then Em(KReg, 'cl') Else EmImm(1);
      End;
    $D4 : Begin EmMnem('aam'); EmImm(Fb); End;
    $D5 : Begin EmMnem('aad'); EmImm(Fb); End;
    $D6 : EmMnem('salc');
    $D7 : EmMnem('xlat');
    $D8..$DF : DisFpu(Op);
    $E0 : Begin EmMnem('loopne'); EmRel(Sx8(Fb)); End;
    $E1 : Begin EmMnem('loope'); EmRel(Sx8(Fb)); End;
    $E2 : Begin EmMnem('loop'); EmRel(Sx8(Fb)); End;
    $E3 : Begin EmMnem('jecxz'); EmRel(Sx8(Fb)); End;
    $E4 : Begin EmMnem('in'); Em(KReg, 'al'); Comma; EmImm(Fb); End;
    $E5 : Begin EmMnem('in'); EmReg(Sz, 0); Comma; EmImm(Fb); End;
    $E6 : Begin EmMnem('out'); EmImm(Fb); Comma; Em(KReg, 'al'); End;
    $E7 : Begin EmMnem('out'); EmImm(Fb); Comma; EmReg(Sz, 0); End;
    $E8 : Begin EmMnem('call'); EmRel(Fd); DIsCall := True; End;
    $E9 : Begin EmMnem('jmp'); EmRel(Fd); End;
    $EA : Begin EmMnem('jmp'); Em(KKey, 'far '); V := Fd; Em(KNum, HexDig(Fw, 4)); Em(KPun, ':'); Em(KNum, HexDig(V, 8)); End;
    $EB : Begin EmMnem('jmp'); Em(KKey, 'short '); EmRel(Sx8(Fb)); End;
    $EC : Begin EmMnem('in'); Em(KReg, 'al'); Comma; Em(KReg, 'dx'); End;
    $ED : Begin EmMnem('in'); EmReg(Sz, 0); Comma; Em(KReg, 'dx'); End;
    $EE : Begin EmMnem('out'); Em(KReg, 'dx'); Comma; Em(KReg, 'al'); End;
    $EF : Begin EmMnem('out'); Em(KReg, 'dx'); Comma; EmReg(Sz, 0); End;
    $F1 : EmMnem('int1');
    $F4 : EmMnem('hlt');
    $F5 : EmMnem('cmc');
    $F6, $F7 :
      Begin
        ModRM; EmMnem(Grp3[R]);
        If Op = $F6 Then EmRM(Md, Rm, 1) Else EmRM(Md, Rm, Sz);
        If R < 2 Then
        Begin
          Comma;
          If Op = $F6 Then EmImm(Fb) Else ImmV;
        End;
      End;
    $F8 : EmMnem('clc');
    $F9 : EmMnem('stc');
    $FA : EmMnem('cli');
    $FB : EmMnem('sti');
    $FC : EmMnem('cld');
    $FD : EmMnem('std');
    $FE :
      Begin
        ModRM;
        If R = 0 Then EmMnem('inc') Else If R = 1 Then EmMnem('dec') Else EmMnem('(bad)');
        EmRM(Md, Rm, 1);
      End;
    $FF :
      Begin
        ModRM;
        Case R Of
          0 : Begin EmMnem('inc'); EmRM(Md, Rm, Sz); End;
          1 : Begin EmMnem('dec'); EmRM(Md, Rm, Sz); End;
          2 : Begin EmMnem('call'); EmRM(Md, Rm, Sz); DIsCall := True; End;
          3 : Begin EmMnem('call'); Em(KKey, 'far '); EmRM(Md, Rm, 6); DIsCall := True; End;
          4 : Begin EmMnem('jmp'); EmRM(Md, Rm, Sz); End;
          5 : Begin EmMnem('jmp'); Em(KKey, 'far '); EmRM(Md, Rm, 6); End;
          6 : Begin EmMnem('push'); EmRM(Md, Rm, Sz); End;
        Else Begin EmMnem('(bad)'); DBad := True; End;
        End;
      End;
  Else
    Begin
      Em(KMnem, 'db');
      Em(KPun, ' ');
      Em(KNum, HexDig(Op, 2) + 'h');
      DBad := True;
    End;
  End;
  { espace final des instructions sans operande }
  While (Length(DText) > 0) And (DText[Length(DText)] = ' ') Do Delete(DText, Length(DText), 1);
  If (Length(DText) > 0) And (DText[Length(DText)] = Chr(KPun)) Then Delete(DText, Length(DText), 1);
  If DPos < 1 Then DPos := 1;
  If DPos > 15 Then DPos := 15;
  Disasm := DPos;
End;

{ texte sans les codes de couleur }
Function PlainText(S : String) : String;
Var I : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do If Ord(S[I]) >= 32 Then R := R + S[I];
  PlainText := R;
End;


{ ================================================================== }
{ Debogueur                                                          }
{ ================================================================== }

Var
  ExePath, ExeArgs, ModName : String;
  Pid : LongInt;                   { PID du programme debogue (0 : aucun) }
  HProc, HThr, DTid : LongInt;     { processus et fil debogues (poignees), fil de l'evenement }
  DEv : Array[0..23] Of LongInt;   { DEBUG_EVENT }
  Ctx : Array[0..203] Of LongInt;  { CONTEXT (716 octets) }
  EvState, EvCode, EvCr2 : LongInt; { evenement en attente : 0 aucun, 1 arret, 2 fin }
  ContSt : LongInt;                { reprise : DBG_CONTINUE ou DBG_EXCEPTION_NOT_HANDLED }
  FirstStop : Boolean;             { premier arret (point d'entree) pas encore vu }
  ExcCode, KillCode : LongInt;     { exception de l'arret ; celle qui termine le programme }
  DState : LongInt;                { 0 aucun, 1 s'execute, 2 arrete, 3 termine }
  Regs, OldRegs : Array[0..15] Of LongInt;
  HaveOld : Boolean;
  ImgBase, ImgSize, ImgPhys, ImgEntry, DataVa, CodeLo, CodeHi : LongInt;
  ExitCode, LastEv : LongInt;
  StatusTxt : String;
  Pausing : Boolean;
  { points d'arret (BpMax : point d'arret temporaire de F4, F8, Alt+F8) }
  BpA : Array[0..BpMax] Of LongInt;
  BpOrig : Array[0..BpMax] Of Byte;
  BpN, TmpBp : LongInt;
  BpIn : Boolean;
  { symboles, tries par adresse ; SymC : adresse de code (etiquette) }
  SymA : Array[0..SymMax - 1] Of LongInt;
  SymS : Array[0..SymMax - 1] Of String[39];
  SymC : Array[0..SymMax - 1] Of Boolean;
  SymN : LongInt;
  SymOk : Boolean;
  ModBase : Array[0..31] Of LongInt;
  ModN : LongInt;
  { memoire du programme : requete du noyau, antememoires }
  MemReq : Array[0..2] Of LongInt;
  CBuf : Array[0..4127] Of Byte;
  CBase, CLen : LongInt;
  RcBuf : Array[0..4127] Of Byte;
  RcBase, RcLen : LongInt;
  MemNow, Snap : Array[0..4095] Of Byte;
  SnapA, SnapN : LongInt;
  { volets et fenetres }
  PaneH, PaneSb, PaneW, PaneHt : Array[0..3] Of LongInt;
  ActPane : LongInt;
  StatusH : LongInt;
  TbBtn, TbW : Array[0..11] Of LongInt;
  TbGap : Array[0..11] Of Boolean;
  TbN : LongInt;
  { volet Code : lignes montrees }
  CodeTop, CodeSel : LongInt;
  LnN : LongInt;
  LnA, LnLen, LnTgt, LnCc : Array[0..MaxRows] Of LongInt;
  LnLab : Array[0..MaxRows] Of Boolean;
  LnTxt : Array[0..MaxRows] Of String;
  { autres volets }
  RegSel, MemAddr, StkTop, StkSel : LongInt;
  PaintW, PaintH : LongInt;
  Dim : Boolean;

Const
  RName : Array[0..8] Of String[3] = ('EAX', 'EBX', 'ECX', 'EDX', 'ESI', 'EDI', 'EBP', 'ESP', 'EIP');
  FlName : String[9] = 'czsopaidt';
  FlBit : Array[0..8] Of Byte = (0, 6, 7, 11, 2, 4, 9, 10, 8);

Function L2(Fr, En : String) : String;
Begin
  If Lang = 0 Then L2 := Fr Else L2 := En;
End;

Function Hex8(V : LongInt) : String;
Begin
  Hex8 := HexDig(V, 8);
End;

{ code de sortie : decimal, ou hexadecimal (exception C0000094h...) }
Function CodeStr(V : LongInt) : String;
Begin
  If (V >= -1) And (V < $10000) Then CodeStr := IStr(V) Else CodeStr := Hex8(V) + 'h';
End;

{ --------------------------------------------- memoire du programme }

{ ------------------------------------------- API de debogage de Windows }

Function ReadMem(A, N, Dst : LongInt) : LongInt;
Var Done : LongInt;
Begin
  Done := 0;
  If (HProc = 0) Or (ReadProcessMemory(HProc, A, Dst, N, LongInt(@Done)) = 0) Then Done := 0;
  ReadMem := Done;
End;

Function WriteMem(A, N, Src : LongInt) : LongInt;
Var Done : LongInt;
Begin
  Done := 0;
  If (HProc = 0) Or (WriteProcessMemory(HProc, A, Src, N, LongInt(@Done)) = 0) Then Done := 0;
  If Done > 0 Then Dummy := FlushInstructionCache(HProc, A, N);
  WriteMem := Done;
End;

{ l'octet a A peut-il recevoir un point d'arret ? (le code du noyau de
  Pasdows, ou vivent KERNEL32, USER32..., est partage et protege) }
Function Writable(A : LongInt) : Boolean;
Var B : Byte;
Begin
  Writable := (ReadMem(A, 1, LongInt(@B)) = 1) And (WriteMem(A, 1, LongInt(@B)) = 1);
End;

{ registres du fil arrete -> Regs (0 EAX, 1 EBX, 2 ECX, 3 EDX, 4 ESI,
  5 EDI, 6 EBP, 7 ESP, 8 EIP, 9 EFLAGS, 10 CS, 11 DS, 12 ES, 13 FS,
  14 evenement, 15 CR2) }
Function GetRegs : LongInt;
Begin
  GetRegs := -1;
  Ctx[0] := CONTEXT_FULL;
  If (HThr = 0) Or (GetThreadContext(HThr, LongInt(@Ctx)) = 0) Then Exit;
  Regs[0] := Ctx[44]; Regs[1] := Ctx[41]; Regs[2] := Ctx[43]; Regs[3] := Ctx[42];
  Regs[4] := Ctx[40]; Regs[5] := Ctx[39]; Regs[6] := Ctx[45]; Regs[7] := Ctx[49];
  Regs[8] := Ctx[46]; Regs[9] := Ctx[48]; Regs[10] := Ctx[47] And $FFFF;
  Regs[11] := Ctx[38] And $FFFF; Regs[12] := Ctx[37] And $FFFF; Regs[13] := Ctx[36] And $FFFF;
  Regs[14] := EvCode; Regs[15] := EvCr2;
  GetRegs := 0;
End;

{ Regs -> registres du fil arrete (ESP ne change pas : cadre du noyau) }
Function SetRegs : LongInt;
Begin
  SetRegs := -1;
  Ctx[0] := CONTEXT_FULL;
  If (HThr = 0) Or (GetThreadContext(HThr, LongInt(@Ctx)) = 0) Then Exit;
  Ctx[44] := Regs[0]; Ctx[41] := Regs[1]; Ctx[43] := Regs[2]; Ctx[42] := Regs[3];
  Ctx[40] := Regs[4]; Ctx[39] := Regs[5]; Ctx[45] := Regs[6];
  Ctx[46] := Regs[8]; Ctx[48] := Regs[9];
  If SetThreadContext(HThr, LongInt(@Ctx)) <> 0 Then SetRegs := 0;
End;

{ evenement de debogage -> etat (0 rien, 1 arret, 2 fin), code (numero
  d'exception ou de l'arret, code de sortie) ; Ms : attente maximale }
Procedure PollDebug(Ms : LongInt);
Var C : LongInt;
Begin
  If (EvState <> 0) Or (Pid = 0) Then Exit;
  While WaitForDebugEvent(LongInt(@DEv), Ms) <> 0 Do
  Begin
    Case DEv[0] Of
      3 :
        Begin
          { CREATE_PROCESS_DEBUG_EVENT : poignees, image, point d'entree }
          HProc := DEv[4]; HThr := DEv[5]; DTid := DEv[2];
          If DEv[6] <> 0 Then ImgBase := DEv[6];
          If DEv[10] <> 0 Then ImgEntry := DEv[10];
          Dummy := ContinueDebugEvent(DEv[1], DEv[2], DBG_CONTINUE);
        End;
      1 :
        Begin
          { EXCEPTION_DEBUG_EVENT : le programme est arrete }
          DTid := DEv[2]; C := DEv[3]; EvCr2 := 0; ExcCode := C;
          ContSt := DBG_CONTINUE;
          If C = LongInt($80000003) Then
          Begin
            If FirstStop Then EvCode := 256
            Else
            Begin
              Ctx[0] := CONTEXT_FULL;
              If GetThreadContext(HThr, LongInt(@Ctx)) <> 0 Then
                If Ctx[46] = DEv[6] + 1 Then
                Begin
                  { INT 3 : EIP revient sur l'instruction }
                  Ctx[46] := DEv[6];
                  Dummy := SetThreadContext(HThr, LongInt(@Ctx));
                  EvCode := 3;
                End
                Else EvCode := 1;         { pause (DebugBreakProcess) }
            End;
            FirstStop := False;
          End
          Else If C = LongInt($80000004) Then EvCode := 1
          Else
          Begin
            ContSt := LongInt(DBG_EXCEPTION_NOT_HANDLED);
            If C = LongInt($C0000094) Then EvCode := 0
            Else If C = LongInt($C0000095) Then EvCode := 4
            Else If C = LongInt($C000008C) Then EvCode := 5
            Else If C = LongInt($C000001D) Then EvCode := 6
            Else If C = LongInt($C0000090) Then EvCode := 16
            Else If C = LongInt($80000002) Then EvCode := 17
            Else If C = LongInt($C0000005) Then
            Begin
              If DEv[7] >= 2 Then
              Begin
                EvCode := 14;
                EvCr2 := DEv[9];
              End
              Else EvCode := 13;
            End
            Else EvCode := 13;
          End;
          EvState := 1;
          Exit;
        End;
      5 :
        Begin
          { EXIT_PROCESS_DEBUG_EVENT : code de sortie (celui de l'exception
            non traitee qui a arrete le programme) }
          EvCode := DEv[3];
          If (EvCode = 0) And (KillCode <> 0) Then EvCode := KillCode;
          KillCode := 0;
          Dummy := ContinueDebugEvent(DEv[1], DEv[2], DBG_CONTINUE);
          EvState := 2;
          Exit;
        End;
    Else
      { fils, DLL, OutputDebugString : on continue }
      Dummy := ContinueDebugEvent(DEv[1], DEv[2], DBG_CONTINUE);
    End;
    Ms := 0;
  End;
End;

{ etat du programme : 0 il s'execute, 1 arrete (Ev), 2 termine (Ev : code) }
Function DbgState(Ms : LongInt; Var Ev : LongInt) : LongInt;
Begin
  PollDebug(Ms);
  Ev := EvCode;
  DbgState := EvState;
End;

{ reprendre le programme arrete (Step : un pas, drapeau TF) }
Procedure DbgGo(Step : Boolean);
Begin
  If EvState <> 1 Then Exit;
  If Step Then
  Begin
    Ctx[0] := CONTEXT_FULL;
    If GetThreadContext(HThr, LongInt(@Ctx)) <> 0 Then
    Begin
      Ctx[48] := Ctx[48] Or $100;
      Dummy := SetThreadContext(HThr, LongInt(@Ctx));
    End;
  End;
  EvState := 0;
  If ContSt = LongInt(DBG_EXCEPTION_NOT_HANDLED) Then KillCode := ExcCode;
  Dummy := ContinueDebugEvent(Pid, DTid, ContSt);
End;

{ lire jusqu'a N octets ; rend le nombre d'octets lisibles a partir de A }
Function ReadSafe(A, N, Dst : LongInt) : LongInt;
Var Done, C : LongInt;
Begin
  ReadSafe := 0;
  If (Pid = 0) Or (N <= 0) Then Exit;
  If ReadMem(A, N, Dst) = N Then
  Begin
    ReadSafe := N;
    Exit;
  End;
  Done := 0;
  While Done < N Do
  Begin
    C := 4096 - ((A + Done) And 4095);
    If C > N - Done Then C := N - Done;
    If ReadMem(A + Done, C, Dst + Done) <> C Then Break;
    Done := Done + C;
  End;
  ReadSafe := Done;
End;

{ octet, mot, double mot du programme (antememoire RcBuf) ; -1 illisible }
Function PrB(A : LongInt) : LongInt;
Begin
  If (A < RcBase) Or (A >= RcBase + RcLen) Then
  Begin
    RcBase := A;
    RcLen := ReadSafe(A, 4096, LongInt(@RcBuf));
  End;
  If (A >= RcBase) And (A < RcBase + RcLen) Then PrB := RcBuf[A - RcBase] Else PrB := -1;
End;

Function PrW(A : LongInt) : LongInt;
Begin
  PrW := (PrB(A) And 255) Or ((PrB(A + 1) And 255) Shl 8);
End;

Function PrL(A : LongInt) : LongInt;
Begin
  PrL := PrW(A) Or (PrW(A + 2) Shl 16);
End;

Function PrStr(A : LongInt) : String;
Var S : String; C : LongInt;
Begin
  S := '';
  C := PrB(A);
  While (C > 0) And (Length(S) < 60) Do
  Begin
    S := S + Chr(C);
    Inc(A);
    C := PrB(A);
  End;
  PrStr := S;
End;

{ DBuf <- les octets de l'instruction a A (antememoire du code) }
Function CodeAt(A : LongInt) : Boolean;
Var I, N : LongInt;
Begin
  If (A < CBase) Or (A + 16 > CBase + CLen) Then
  Begin
    CBase := A;
    CLen := ReadSafe(A, 4096, LongInt(@CBuf));
  End;
  N := CBase + CLen - A;
  If N > 16 Then N := 16;
  If N < 0 Then N := 0;
  For I := 0 To 15 Do
    If I < N Then DBuf[I] := CBuf[A - CBase + I] Else DBuf[I] := 0;
  For I := 16 To 31 Do DBuf[I] := 0;
  CodeAt := N > 0;
End;

{ ---------------------------------------------------------- symboles }

Procedure AddSym(A : LongInt; S : String; C : Boolean);
Begin
  If (SymN >= SymMax) Or (A = 0) Or (A = -1) Or (S = '') Then Exit;
  SymA[SymN] := A; SymS[SymN] := Copy(S, 1, 39); SymC[SymN] := C;
  Inc(SymN);
End;

{ tri de Shell par adresse, puis retrait des doublons }
Procedure SortSyms;
Var Gap, I, J, A, N : LongInt; S : String[39]; C : Boolean;
Begin
  Gap := SymN Div 2;
  While Gap > 0 Do
  Begin
    For I := Gap To SymN - 1 Do
    Begin
      A := SymA[I]; S := SymS[I]; C := SymC[I];
      J := I;
      While (J >= Gap) And (SymA[J - Gap] > A) Do
      Begin
        SymA[J] := SymA[J - Gap]; SymS[J] := SymS[J - Gap]; SymC[J] := SymC[J - Gap];
        J := J - Gap;
      End;
      SymA[J] := A; SymS[J] := S; SymC[J] := C;
    End;
    Gap := Gap Div 2;
  End;
  N := 0;
  For I := 0 To SymN - 1 Do
    If (N = 0) Or (SymA[I] <> SymA[N - 1]) Then
    Begin
      SymA[N] := SymA[I]; SymS[N] := SymS[I]; SymC[N] := SymC[I];
      Inc(N);
    End
    Else If SymC[I] Then SymC[N - 1] := True;
  SymN := N;
End;

{ indice du symbole d'adresse A, ou -1 }
Function SymFind(A : LongInt) : LongInt;
Var Lo, Hi, M : LongInt;
Begin
  SymFind := -1;
  Lo := 0; Hi := SymN - 1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    If SymA[M] = A Then
    Begin
      SymFind := M;
      Exit;
    End;
    If SymA[M] < A Then Lo := M + 1 Else Hi := M - 1;
  End;
End;

{ symbole exact (desassembleur) }
Function SymOf(A : LongInt) : String;
Var K : LongInt;
Begin
  K := SymFind(A);
  If K >= 0 Then SymOf := SymS[K] Else SymOf := '';
End;

{ dernier symbole de code avant A : NOM+dep (dans Lim octets) }
Function SymNear(A, Lim : LongInt) : String;
Var Lo, Hi, M, K : LongInt;
Begin
  SymNear := '';
  Lo := 0; Hi := SymN - 1; K := -1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    If SymA[M] <= A Then Begin K := M; Lo := M + 1; End Else Hi := M - 1;
  End;
  While (K >= 0) And Not SymC[K] Do Dec(K);
  If K < 0 Then Exit;
  If (A - SymA[K] > Lim) Or (A - SymA[K] < 0) Then Exit;
  If SymA[K] = A Then SymNear := SymS[K]
  Else SymNear := SymS[K] + '+' + NumStr(A - SymA[K]);
End;

Function SymLookup(S : String) : LongInt;
Var I : LongInt; U : String;
Begin
  SymLookup := -1;
  S := UpStr(S);
  For I := 0 To SymN - 1 Do
  Begin
    U := UpStr(SymS[I]);
    If (U = S) Or ((Pos('.', U) > 0) And (Copy(U, Pos('.', U) + 1, 255) = S)) Then
    Begin
      SymLookup := I;
      Exit;
    End;
  End;
End;

Function NoExt(S : String) : String;
Var K : LongInt;
Begin
  K := Length(S);
  While (K > 0) And (S[K] <> '.') And (S[K] <> '\') Do Dec(K);
  If (K > 0) And (S[K] = '.') Then NoExt := Copy(S, 1, K - 1) Else NoExt := S;
End;

{ exportations du module charge a M }
Procedure LoadExports(M : LongInt);
Var Pe, E, NN, AF, AN, AO, I, O : LongInt; Mn : String;
Begin
  For I := 0 To ModN - 1 Do If ModBase[I] = M Then Exit;
  If ModN < 32 Then
  Begin
    ModBase[ModN] := M;
    Inc(ModN);
  End;
  Pe := M + PrL(M + $3C);
  If PrL(Pe) <> $4550 Then Exit;
  E := PrL(Pe + 24 + 96);
  If E = 0 Then Exit;
  E := M + E;
  NN := PrL(E + 24);
  AF := M + PrL(E + 28); AN := M + PrL(E + 32); AO := M + PrL(E + 36);
  Mn := UpStr(NoExt(PrStr(M + PrL(E + 12))));
  If NN > 3000 Then NN := 3000;
  For I := 0 To NN - 1 Do
  Begin
    O := PrW(AO + I * 2);
    AddSym(M + PrL(AF + O * 4), Mn + '.' + PrStr(M + PrL(AN + I * 4)), True);
  End;
End;

{ module (en-tete MZ) qui contient l'adresse A (une vraie DLL ; les
  fonctions du noyau de Pasdows n'en ont pas : 256 pages au plus) }
Procedure ModuleOf(A : LongInt);
Var M, K : LongInt;
Begin
  M := A And $FFFFF000;
  For K := 0 To 255 Do
  Begin
    If M < $1000 Then Exit;
    If PrW(M) = $5A4D Then
      If PrL(M + PrL(M + $3C)) = $4550 Then
      Begin
        LoadExports(M);
        Exit;
      End;
    M := M - 4096;
  End;
End;

{ carte .MAP de WPC (-GD) : "00401000 _TPF_NOM" }
Procedure LoadMap;
Var Hf, N, I, K, A, D : LongInt; S, Nm : String; Buf : Array[0..1023] Of Byte;
Begin
  Hf := CreateFileA(Z(NoExt(ExePath) + '.MAP'), $80000000, 1, 0, 3, $80, 0);
  If Hf = -1 Then Exit;
  S := '';
  Repeat
    N := 0;
    If ReadFile(Hf, LongInt(@Buf), 1024, LongInt(@N), 0) = 0 Then N := 0;
    For I := 0 To N - 1 Do
      If (Buf[I] = 10) Or (Buf[I] = 13) Then
      Begin
        If Length(S) > 10 Then
        Begin
          A := 0; K := 1;
          While K <= 8 Do
          Begin
            D := Pos(UpCase(S[K]), '0123456789ABCDEF') - 1;
            If D < 0 Then Break;
            A := (A Shl 4) Or D;
            Inc(K);
          End;
          If K = 9 Then
          Begin
            Nm := Copy(S, 10, 60);
            While (Nm <> '') And (Nm[1] = ' ') Do Delete(Nm, 1, 1);
            If Copy(Nm, 1, 6) = '_TPRT_' Then Delete(Nm, 1, 6)
            Else If (Copy(Nm, 1, 5) = '_TPF_') Or (Copy(Nm, 1, 5) = '_TPX_') Or (Copy(Nm, 1, 5) = '_TPE_') Then
              Delete(Nm, 1, 5);
            AddSym(A, Nm, True);
          End;
        End;
        S := '';
      End
      Else If Length(S) < 250 Then S := S + Chr(Buf[I]);
  Until N < 1024;
  Dummy := CloseHandle(Hf);
End;

{ symboles : importations (cases et fonctions), exportations des DLL,
  carte .MAP, point d'entree ; sections du programme }
Procedure LoadSymbols;
Var Pe, Opt, Imp, D, Th, Iat, J, V, Ns, Sec, I, Fl, Va : LongInt; Dll, Nm : String;
Begin
  SymN := 0; ModN := 0; RcLen := 0;
  CodeLo := ImgBase; CodeHi := ImgBase + ImgSize; DataVa := ImgBase;
  Pe := ImgBase + PrL(ImgBase + $3C);
  If PrL(Pe) = $4550 Then
  Begin
    Ns := PrW(Pe + 6);
    Opt := Pe + 24;
    Sec := Opt + PrW(Pe + 20);
    For I := 0 To Ns - 1 Do
    Begin
      Va := ImgBase + PrL(Sec + 12);
      Fl := PrL(Sec + 36);
      If (Fl And $20) <> 0 Then
      Begin
        If CodeLo = ImgBase Then CodeLo := Va;
        CodeHi := Va + PrL(Sec + 8);
      End
      Else If ((Fl And $40) <> 0) And (DataVa = ImgBase) Then DataVa := Va;
      Sec := Sec + 40;
    End;
    Imp := PrL(Opt + 104);
    If Imp <> 0 Then
    Begin
      D := ImgBase + Imp;
      While (PrL(D + 12) <> 0) And (SymN < SymMax - 10) Do
      Begin
        Dll := UpStr(NoExt(PrStr(ImgBase + PrL(D + 12))));
        Th := PrL(D); Iat := PrL(D + 16);
        If Th = 0 Then Th := Iat;
        J := 0;
        V := PrL(ImgBase + Th);
        While (V > 0) And (J < 4000) Do
        Begin
          Nm := Dll + '.' + PrStr(ImgBase + V + 2);
          AddSym(ImgBase + Iat + J * 4, Nm, False);
          AddSym(PrL(ImgBase + Iat + J * 4), Nm, True);
          Inc(J);
          V := PrL(ImgBase + Th + J * 4);
        End;
        { exportations de la DLL (fonctions internes appelees en pas a pas) }
        If J > 0 Then ModuleOf(PrL(ImgBase + Iat));
        D := D + 20;
      End;
    End;
  End;
  LoadMap;
  AddSym(ImgEntry, ModName + '.Entry', True);
  SortSyms;
  SymOk := True;
  RcLen := 0;
End;

{ ------------------------------------------------- expressions (Ctrl+G) }

Function EvalTerm(S : String; Var V : LongInt) : Boolean;
Var I, D, K : LongInt; U : String;
Begin
  EvalTerm := False;
  U := UpStr(S);
  If U = '' Then Exit;
  For I := 0 To 8 Do
    If U = RName[I] Then
    Begin
      V := Regs[I];
      EvalTerm := True;
      Exit;
    End;
  If (Copy(U, 1, 2) = '0X') Then Delete(U, 1, 2)
  Else If U[1] = '$' Then Delete(U, 1, 1)
  Else If (U[Length(U)] = 'H') And (Length(U) > 1) And (Pos(U[1], '0123456789') > 0) Then Delete(U, Length(U), 1);
  V := 0; K := 0;
  For I := 1 To Length(U) Do
  Begin
    D := Pos(U[I], '0123456789ABCDEF') - 1;
    If D < 0 Then Begin K := -1; Break; End;
    V := (V Shl 4) Or D;
    Inc(K);
  End;
  If (K > 0) And (K <= 8) Then
  Begin
    EvalTerm := True;
    Exit;
  End;
  K := SymLookup(S);
  If K >= 0 Then
  Begin
    V := SymA[K];
    EvalTerm := True;
  End;
End;

{ termes separes par + et - : registres, nombres hexadecimaux, symboles }
Function EvalExpr(S : String; Var V : LongInt) : Boolean;
Var I, T, Sg : LongInt; Cur : String;
Begin
  EvalExpr := False;
  V := 0; Sg := 1; Cur := '';
  S := S + '+';
  For I := 1 To Length(S) Do
    If ((S[I] = '+') Or (S[I] = '-')) And (Cur <> '') Then
    Begin
      If Not EvalTerm(Cur, T) Then Exit;
      V := V + Sg * T;
      If S[I] = '+' Then Sg := 1 Else Sg := -1;
      Cur := '';
    End
    Else If S[I] = '-' Then Sg := -Sg
    Else If (S[I] <> ' ') And (S[I] <> '+') Then Cur := Cur + S[I];
  EvalExpr := True;
End;

{ ---------------------------------------------------- points d'arret }

Function InImage(A : LongInt) : Boolean;
Begin
  InImage := (A >= ImgBase) And (A < ImgBase + ImgSize);
End;

Function BpIndex(A : LongInt) : LongInt;
Var I : LongInt;
Begin
  BpIndex := -1;
  For I := 0 To BpN - 1 Do If BpA[I] = A Then BpIndex := I;
End;

Procedure InsertBps;
Var I : LongInt; B : Byte;
Begin
  If BpIn Then Exit;
  B := $CC;
  For I := 0 To BpN - 1 Do
    If ReadMem(BpA[I], 1, LongInt(@BpOrig[I])) = 1 Then Dummy := WriteMem(BpA[I], 1, LongInt(@B));
  If (TmpBp <> -1) And (BpIndex(TmpBp) < 0) Then
  Begin
    { hors du programme (DLL) : possible hors du code partage du noyau }
    If (ReadMem(TmpBp, 1, LongInt(@BpOrig[BpMax])) = 1) And (WriteMem(TmpBp, 1, LongInt(@B)) = 1) Then
    Else TmpBp := -1;
  End;
  BpIn := True;
End;

Procedure RemoveBps;
Var I : LongInt;
Begin
  If Not BpIn Then Exit;
  If (TmpBp <> -1) And (BpIndex(TmpBp) < 0) Then Dummy := WriteMem(TmpBp, 1, LongInt(@BpOrig[BpMax]));
  For I := BpN - 1 DownTo 0 Do Dummy := WriteMem(BpA[I], 1, LongInt(@BpOrig[I]));
  BpIn := False;
End;

{ --------------------------------------------------------- volets }

Procedure InvAll;
Var K : LongInt;
Begin
  For K := 0 To 3 Do If PaneH[K] <> 0 Then Dummy := InvalidateRect(PaneH[K], 0, 0);
End;

Function PaneRows(K : LongInt) : LongInt;
Begin
  PaneRows := MaxL(1, (PaneHt[K] - HdrH - 4) Div ChH);
End;

Procedure SetStatus(S : String);
Begin
  StatusTxt := S;
  If StatusH <> 0 Then Dummy := SetWindowTextA(StatusH, Z(' ' + S));
End;

Function StateName : String;
Begin
  Case DState Of
    1 : StateName := L2('Ex'#130'cution', 'Running');
    2 : StateName := L2('Arr'#136't'#130, 'Stopped');
    3 : StateName := L2('Termin'#130, 'Terminated');
  Else
    StateName := '';
  End;
End;

Procedure SetTitle;
Var S : String;
Begin
  S := AppName;
  If ExePath <> '' Then S := S + ' - ' + BaseName(ExePath);
  If StateName <> '' Then S := S + ' [' + StateName + ']';
  Dummy := SetWindowTextA(Frame, Z(S));
End;

Procedure UpdateMenu; Forward;

{ boutons et choix selon l'etat }
Procedure UpdateButtons;
Var I : LongInt; En : Boolean;
Begin
  For I := 0 To TbN - 1 Do
  Begin
    En := True;
    Case I Of
      1, 2, 3, 4, 5 : En := DState = 2;
      6 : En := DState = 1;
      7 : En := ExePath <> '';
      8 : En := (DState = 1) Or (DState = 2);
      9 : En := DState = 2;
    End;
    Dummy := EnableWindow(TbBtn[I], Ord(En));
  End;
  UpdateMenu;
  SetTitle;
End;

{ ------------------------------------------------------- volet Code }

Function CondTrue(Cc, Fl : LongInt) : Boolean;
Var C, Zf, Sf, Of_, Pf, R : Boolean;
Begin
  C := (Fl And 1) <> 0; Zf := (Fl And $40) <> 0; Sf := (Fl And $80) <> 0;
  Of_ := (Fl And $800) <> 0; Pf := (Fl And 4) <> 0;
  Case Cc Shr 1 Of
    0 : R := Of_;
    1 : R := C;
    2 : R := Zf;
    3 : R := C Or Zf;
    4 : R := Sf;
    5 : R := Pf;
    6 : R := Sf <> Of_;
  Else
    R := Zf Or (Sf <> Of_);
  End;
  If (Cc And 1) <> 0 Then R := Not R;
  CondTrue := R;
End;

{ lignes du volet Code a partir de CodeTop (etiquettes des procedures) }
Procedure BuildLines;
Var A, R, N, K : LongInt;
Begin
  LnN := 0; A := CodeTop;
  R := MinL(PaneRows(PnCode), MaxRows);
  CBase := 0; CLen := 0;
  While LnN < R Do
  Begin
    K := SymFind(A);
    If (K >= 0) And SymC[K] Then
    Begin
      LnA[LnN] := A; LnLab[LnN] := True; LnTxt[LnN] := SymS[K]; LnLen[LnN] := 0;
      LnTgt[LnN] := -1; LnCc[LnN] := -1;
      Inc(LnN);
      If LnN >= R Then Break;
    End;
    LnLab[LnN] := False; LnA[LnN] := A; LnCc[LnN] := -1; LnTgt[LnN] := -1;
    If CodeAt(A) Then
    Begin
      N := Disasm(A);
      LnTxt[LnN] := DText;
      LnTgt[LnN] := DTarget;
      If (DBuf[0] >= $70) And (DBuf[0] <= $7F) Then LnCc[LnN] := DBuf[0] - $70
      Else If (DBuf[0] = $0F) And (DBuf[1] >= $80) And (DBuf[1] <= $8F) Then LnCc[LnN] := DBuf[1] - $80;
    End
    Else
    Begin
      N := 1;
      LnTxt[LnN] := Chr(KPun) + '??';
    End;
    LnLen[LnN] := N;
    Inc(LnN);
    A := A + N;
  End;
End;

{ instruction precedant A (on resynchronise le desassemblage) }
Function PrevInsn(A : LongInt) : LongInt;
Var K, S, N, Lo, Hi, M : LongInt;
Begin
  { depuis un symbole de code proche }
  Lo := 0; Hi := SymN - 1; K := -1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    If SymA[M] < A Then Begin K := M; Lo := M + 1; End Else Hi := M - 1;
  End;
  If (K >= 0) And (A - SymA[K] <= 256) Then
  Begin
    S := SymA[K];
    While S < A Do
    Begin
      If Not CodeAt(S) Then Break;
      N := Disasm(S);
      If S + N = A Then
      Begin
        PrevInsn := S;
        Exit;
      End;
      S := S + N;
    End;
  End;
  For K := 24 DownTo 1 Do
  Begin
    S := A - K;
    While S < A Do
    Begin
      If Not CodeAt(S) Then Break;
      N := Disasm(S);
      If S + N = A Then
      Begin
        PrevInsn := S;
        Exit;
      End;
      S := S + N;
    End;
  End;
  PrevInsn := A - 1;
End;

{ A visible dans le volet Code (deux lignes avant) }
Procedure CodeShow(A : LongInt);
Var I : LongInt;
Begin
  BuildLines;
  For I := 0 To LnN - 2 Do
    If (Not LnLab[I]) And (LnA[I] = A) Then Exit;
  CodeTop := PrevInsn(PrevInsn(A));
  BuildLines;
  For I := 0 To LnN - 2 Do
    If (Not LnLab[I]) And (LnA[I] = A) Then Exit;
  CodeTop := A;
  BuildLines;
End;

Procedure CodeDown;
Begin
  If LnN = 0 Then BuildLines;
  If LnN > 0 Then
  Begin
    If LnLab[0] And (LnN > 1) Then CodeTop := LnA[1] + LnLen[1]
    Else CodeTop := LnA[0] + MaxL(1, LnLen[0]);
  End;
  BuildLines;
End;

Procedure CodeUp;
Begin
  CodeTop := PrevInsn(CodeTop);
  BuildLines;
End;

{ ligne (instruction) de CodeSel ; -1 si cachee }
Function SelLine : LongInt;
Var I : LongInt;
Begin
  SelLine := -1;
  For I := 0 To LnN - 1 Do
    If (Not LnLab[I]) And (LnA[I] = CodeSel) Then
    Begin
      SelLine := I;
      Exit;
    End;
End;

Procedure CodeKey(Vk : LongInt);
Var I, K : LongInt;
Begin
  BuildLines;
  I := SelLine;
  Case Vk Of
    VK_DOWN :
      Begin
        If I < 0 Then CodeSel := CodeTop
        Else
        Begin
          K := I + 1;
          While (K < LnN) And LnLab[K] Do Inc(K);
          If K >= LnN - 1 Then
          Begin
            CodeDown;
            CodeSel := LnA[I] + LnLen[I];
          End
          Else CodeSel := LnA[K];
        End;
      End;
    VK_UP :
      Begin
        K := I - 1;
        While (K >= 0) And LnLab[K] Do Dec(K);
        If K < 0 Then
        Begin
          CodeUp;
          CodeSel := CodeTop;
        End
        Else CodeSel := LnA[K];
      End;
    VK_PAGEDOWN :
      Begin
        If LnN > 1 Then CodeTop := LnA[LnN - 1];
        CodeSel := CodeTop;
      End;
    VK_PAGEUP :
      Begin
        For K := 1 To MaxL(1, PaneRows(PnCode) - 1) Do CodeTop := PrevInsn(CodeTop);
        CodeSel := CodeTop;
      End;
    VK_HOME :
      If DState = 2 Then
      Begin
        CodeSel := Regs[8];
        CodeShow(CodeSel);
      End;
  End;
  BuildLines;
End;

{ ------------------------------------------------------------ dessin }

{ couleur RVB (COLORREF) d'un indice CLR_ }
Function ClrRGB(C : LongInt) : LongInt;
Begin
  Case C Of
    CLR_WHITE : ClrRGB := $FFFFFF;
    CLR_BLACK : ClrRGB := 0;
    CLR_BLUE : ClrRGB := $FF0000;
    CLR_RED : ClrRGB := $0000FF;
    CLR_PINK : ClrRGB := $FF00FF;
    CLR_GREEN : ClrRGB := $00FF00;
    CLR_CYAN : ClrRGB := $FFFF00;
    CLR_YELLOW : ClrRGB := $00FFFF;
    CLR_DARKGRAY : ClrRGB := $808080;
    CLR_DARKBLUE : ClrRGB := $800000;
    CLR_DARKRED : ClrRGB := $000080;
    CLR_DARKPINK : ClrRGB := $800080;
    CLR_DARKGREEN : ClrRGB := $008000;
    CLR_DARKCYAN : ClrRGB := $808000;
    CLR_BROWN : ClrRGB := $008080;
    CLR_PALEGRAY : ClrRGB := $C0C0C0;
  Else ClrRGB := 0;
  End;
End;

{ rectangle plein (X1, Y1) - (X2, Y2) exclus, ordonnees depuis le bas du
  volet (comme dans le debogueur d'origine) : retournees pour Windows }
Procedure FillR(Hps, X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; Br : LongInt;
Begin
  If (X2 <= X1) Or (Y2 <= Y1) Then Exit;
  Rc[0] := X1; Rc[1] := PaintH - Y2; Rc[2] := X2; Rc[3] := PaintH - Y1;
  Br := CreateSolidBrush(ClrRGB(C));
  Dummy := FillRect(Hps, LongInt(@Rc), Br);
  Dummy := DeleteObject(Br);
End;

{ texte (coin bas gauche X, Y depuis le bas du volet), coupe a X2 }
Procedure TextOutAt(Hps, X, Y, X2 : LongInt; S : String; Fg, Bg : LongInt);
Var Rc : Array[0..3] Of LongInt;
Begin
  If (S = '') Or (X2 <= X) Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Rc[0] := X; Rc[1] := PaintH - Y - ChH; Rc[2] := X2; Rc[3] := PaintH - Y;
  Dummy := SelectObject(Hps, SysFont);
  Dummy := SetTextColor(Hps, ClrRGB(Fg));
  Dummy := SetBkColor(Hps, ClrRGB(Bg));
  Dummy := ExtTextOutA(Hps, X, Rc[1], ETO_OPAQUE Or ETO_CLIPPED, LongInt(@Rc), LongInt(@TxtBuf), Length(S), 0);
End;

{ ordonnee du bas de la ligne Row du contenu d'un volet }
Function RowY(Row : LongInt) : LongInt;
Begin
  RowY := PaintH - HdrH - 2 - (Row + 1) * ChH;
End;

{ texte a la colonne de pixels X de la ligne Row ; rend X apres le texte }
Function TextAt(Hps, X, Row : LongInt; S : String; Fg, Bg, MaxX : LongInt) : LongInt;
Var N : LongInt;
Begin
  TextAt := X + Length(S) * ChW;
  N := (MaxX - X) Div ChW;
  If N <= 0 Then Exit;
  If Length(S) > N Then S := Copy(S, 1, N);
  If S = '' Then Exit;
  TextOutAt(Hps, X, RowY(Row), X + Length(S) * ChW, S, Fg, Bg);
End;

Function TokColor(K : LongInt; S : String) : LongInt;
Begin
  Case K Of
    KMnem :
      If (S[1] = 'j') Or (Copy(S, 1, 4) = 'call') Or (Copy(S, 1, 3) = 'ret') Or (Copy(S, 1, 4) = 'loop') Then
        TokColor := CLR_DARKRED
      Else TokColor := CLR_DARKBLUE;
    KReg : TokColor := CLR_DARKPINK;
    KNum : TokColor := CLR_DARKGREEN;
    KSym : TokColor := CLR_BROWN;
    KKey : TokColor := CLR_DARKGRAY;
  Else
    TokColor := CLR_BLACK;
  End;
End;

{ texte colore du desassembleur (codes 1 a 6) }
Function ColorAt(Hps, X, Row : LongInt; T : String; Bg, Fix, MaxX : LongInt) : LongInt;
Var I, K, C : LongInt; S : String;
Begin
  I := 1;
  While I <= Length(T) Do
  Begin
    K := 0;
    If Ord(T[I]) < 32 Then
    Begin
      K := Ord(T[I]);
      Inc(I);
    End;
    S := '';
    While (I <= Length(T)) And (Ord(T[I]) >= 32) Do
    Begin
      S := S + T[I];
      Inc(I);
    End;
    If S <> '' Then
    Begin
      If Fix <> 0 Then C := Fix Else C := TokColor(K, S);
      X := TextAt(Hps, X, Row, S, C, Bg, MaxX);
    End;
  End;
  ColorAt := X;
End;

{ pastille rouge (point d'arret) }
Procedure Disc(Hps, Cx, Cy, R, C : LongInt);
Var Dy, W : LongInt;
Begin
  For Dy := -R To R Do
  Begin
    W := 0;
    While (W + 1) * (W + 1) + Dy * Dy <= R * R Do Inc(W);
    FillR(Hps, Cx - W, Cy + Dy, Cx + W + 1, Cy + Dy + 1, C);
  End;
End;

{ fleche d'EIP }
Procedure Arrow(Hps, X, Cy, C : LongInt);
Var D : LongInt;
Begin
  FillR(Hps, X, Cy - 1, X + 5, Cy + 2, C);
  For D := 0 To 4 Do FillR(Hps, X + 5 + D, Cy - 4 + D, X + 6 + D, Cy + 5 - D, C);
End;

Procedure PaintCode(Hps, W : LongInt);
Var I, R, X, Bg, Fix, Nb, J, Xb, Xt, Cy, MaxX : LongInt; S : String; IsBp, IsEip : Boolean;
Begin
  MaxX := W - SbW - 2;
  If (DState = 0) Or (DState = 3) Or (Pid = 0) Then
  Begin
    If DState = 3 Then
      S := L2('Le programme s''est termin'#130' (code ', 'The program has terminated (code ') + CodeStr(ExitCode) + ').'
    Else S := L2('Aucun programme : Fichier > Ouvrir (Ctrl+O).', 'No program: File > Open (Ctrl+O).');
    Dummy := TextAt(Hps, 12, 1, S, CLR_DARKGRAY, CLR_WHITE, MaxX);
    If ExePath <> '' Then
      Dummy := TextAt(Hps, 12, 3, L2('Ctrl+F2 : red'#130'marrer ', 'Ctrl+F2: restart ') + BaseName(ExePath), CLR_DARKGRAY,
                      CLR_WHITE, MaxX);
    Exit;
  End;
  BuildLines;
  { colonnes : marge, adresse, octets, instruction, commentaire }
  Nb := 6;
  If W > 760 Then Nb := 8;
  Xb := 18 + 9 * ChW;
  Xt := Xb + (Nb * 2 + 2) * ChW;
  For I := 0 To LnN - 1 Do
  Begin
    R := I;
    Cy := RowY(R) + ChH Div 2;
    If LnLab[I] Then
    Begin
      Dummy := TextAt(Hps, 18, R, LnTxt[I] + ':', CLR_BROWN, CLR_WHITE, MaxX);
      Continue;
    End;
    IsBp := (BpIndex(LnA[I]) >= 0);
    IsEip := (DState = 2) And (LnA[I] = Regs[8]);
    Bg := CLR_WHITE; Fix := 0;
    If Dim Then Fix := CLR_DARKGRAY
    Else If IsEip Then Bg := CLR_YELLOW
    Else If IsBp Then
    Begin
      Bg := CLR_RED; Fix := CLR_WHITE;
    End
    Else If LnA[I] = CodeSel Then
    Begin
      If ActPane = PnCode Then Bg := CLR_CYAN Else Bg := CLR_PALEGRAY;
    End;
    If (LnA[I] = CodeSel) And (IsEip Or IsBp) And (ActPane = PnCode) And Not Dim Then
      FillR(Hps, 16, RowY(R), MaxX, RowY(R) + ChH, CLR_CYAN);
    If Bg <> CLR_WHITE Then
      If (LnA[I] = CodeSel) And (IsEip Or IsBp) And (ActPane = PnCode) And Not Dim Then
        FillR(Hps, 18, RowY(R) + 2, MaxX - 2, RowY(R) + ChH - 2, Bg)
      Else FillR(Hps, 16, RowY(R), MaxX, RowY(R) + ChH, Bg);
    If IsBp Then Disc(Hps, 7, Cy, 5, CLR_RED);
    If IsEip Then Arrow(Hps, 2, Cy, CLR_DARKBLUE);
    { adresse et octets }
    If Fix <> 0 Then J := Fix Else J := CLR_BLACK;
    Dummy := TextAt(Hps, 18, R, Hex8(LnA[I]), J, Bg, MaxX);
    S := '';
    If CodeAt(LnA[I]) Then
      For J := 0 To MinL(LnLen[I], Nb) - 1 Do S := S + HexDig(DBuf[J], 2);
    If LnLen[I] > Nb Then S := Copy(S, 1, Nb * 2 - 1) + '+';
    If Fix <> 0 Then J := Fix Else J := CLR_DARKGRAY;
    Dummy := TextAt(Hps, Xb, R, S, J, Bg, MaxX);
    X := ColorAt(Hps, Xt, R, LnTxt[I], Bg, Fix, MaxX);
    { commentaire : saut effectue ou non a EIP, destination proche d'un symbole }
    S := '';
    If IsEip And (LnCc[I] >= 0) Then
    Begin
      If CondTrue(LnCc[I], Regs[9]) Then
      Begin
        If LnTgt[I] < LnA[I] Then S := L2('saut effectu'#130' '#24, 'jump taken '#24)
        Else S := L2('saut effectu'#130' '#25, 'jump taken '#25);
      End
      Else S := L2('pas de saut', 'no jump');
    End
    Else If (LnTgt[I] <> -1) And (SymFind(LnTgt[I]) < 0) Then S := SymNear(LnTgt[I], $FFFF);
    If S <> '' Then
    Begin
      X := MaxL(X + 2 * ChW, Xt + 34 * ChW);
      If Fix <> 0 Then J := Fix Else J := CLR_DARKCYAN;
      Dummy := TextAt(Hps, X, R, '; ' + S, J, Bg, MaxX);
    End;
  End;
End;

Procedure PaintRegs(Hps, W : LongInt);
Var I, Bg, C, X, V, B : LongInt; Ch : Boolean;
Begin
  If DState <> 2 Then Dim := True;
  If Pid = 0 Then Exit;
  For I := 0 To 9 Do
  Begin
    If I < 9 Then V := Regs[I] Else V := Regs[9];
    Bg := CLR_WHITE;
    If (RegSel = I) And (ActPane = PnRegs) And Not Dim Then
    Begin
      Bg := CLR_CYAN;
      FillR(Hps, 2, RowY(I), 6 + 13 * ChW, RowY(I) + ChH, Bg);
    End;
    If I < 9 Then X := TextAt(Hps, 6, I, RName[I], CLR_DARKPINK, Bg, W)
    Else X := TextAt(Hps, 6, I, 'EFL', CLR_DARKPINK, Bg, W);
    If I < 9 Then Ch := HaveOld And (OldRegs[I] <> Regs[I]) Else Ch := HaveOld And (OldRegs[9] <> Regs[9]);
    If Dim Then C := CLR_DARKGRAY Else If Ch Then C := CLR_RED Else C := CLR_DARKBLUE;
    Dummy := TextAt(Hps, 6 + 4 * ChW, I, Hex8(V), C, Bg, W);
  End;
  { drapeaux }
  For I := 0 To 8 Do
  Begin
    B := (Regs[9] Shr FlBit[I]) And 1;
    Ch := HaveOld And (((OldRegs[9] Shr FlBit[I]) And 1) <> B);
    Bg := CLR_WHITE;
    If (RegSel = 10 + I) And (ActPane = PnRegs) And Not Dim Then
    Begin
      Bg := CLR_CYAN;
      FillR(Hps, 6 + 14 * ChW - 2, RowY(I), 6 + 17 * ChW + 2, RowY(I) + ChH, Bg);
    End;
    If Dim Then C := CLR_DARKGRAY Else C := CLR_BLACK;
    Dummy := TextAt(Hps, 6 + 14 * ChW, I, FlName[I + 1], C, Bg, W);
    If Dim Then C := CLR_DARKGRAY Else If Ch Then C := CLR_RED Else C := CLR_DARKBLUE;
    Dummy := TextAt(Hps, 6 + 16 * ChW, I, Chr(48 + B), C, Bg, W);
  End;
  If Dim Then C := CLR_DARKGRAY Else C := CLR_DARKBLUE;
  X := TextAt(Hps, 6, 10, 'CS', CLR_DARKPINK, CLR_WHITE, W);
  X := TextAt(Hps, X + ChW, 10, HexDig(Regs[10], 4), C, CLR_WHITE, W);
  X := TextAt(Hps, X + 2 * ChW, 10, 'DS', CLR_DARKPINK, CLR_WHITE, W);
  X := TextAt(Hps, X + ChW, 10, HexDig(Regs[11], 4), C, CLR_WHITE, W);
  X := TextAt(Hps, 6, 11, 'ES', CLR_DARKPINK, CLR_WHITE, W);
  X := TextAt(Hps, X + ChW, 11, HexDig(Regs[12], 4), C, CLR_WHITE, W);
  X := TextAt(Hps, X + 2 * ChW, 11, 'FS', CLR_DARKPINK, CLR_WHITE, W);
  X := TextAt(Hps, X + ChW, 11, HexDig(Regs[13], 4), C, CLR_WHITE, W);
  If (LastEv = 14) And (DState = 2) Then
  Begin
    X := TextAt(Hps, 6, 12, 'CR2', CLR_DARKPINK, CLR_WHITE, W);
    X := TextAt(Hps, X + ChW, 12, Hex8(Regs[15]), CLR_RED, CLR_WHITE, W);
  End;
End;

Function MemPerRow : LongInt;
Begin
  If PaneW[PnMem] >= (10 + 16 * 3 + 1 + 16) * ChW + SbW + 12 Then MemPerRow := 16 Else MemPerRow := 8;
End;

Procedure PaintMem(Hps, W : LongInt);
Var R, Rows, N, Pr, I, A, X, C, B, Xa : LongInt; S : String;
Begin
  If (Pid = 0) Or (DState = 3) Then Exit;
  Rows := PaneRows(PnMem);
  Pr := MemPerRow;
  N := ReadSafe(MemAddr, MinL(4096, Rows * Pr), LongInt(@MemNow));
  Xa := 6 + (10 + Pr * 3) * ChW;
  For R := 0 To Rows - 1 Do
  Begin
    A := MemAddr + R * Pr;
    If Dim Then C := CLR_DARKGRAY Else C := CLR_BLACK;
    Dummy := TextAt(Hps, 6, R, Hex8(A), C, CLR_WHITE, W - SbW);
    X := 6 + 10 * ChW;
    S := '';
    For I := 0 To Pr - 1 Do
    Begin
      If R * Pr + I < N Then
      Begin
        B := MemNow[R * Pr + I];
        If Dim Then C := CLR_DARKGRAY
        Else If HaveOld And (A + I >= SnapA) And (A + I < SnapA + SnapN) And (Snap[A + I - SnapA] <> B) Then C := CLR_RED
        Else C := CLR_DARKBLUE;
        Dummy := TextAt(Hps, X, R, HexDig(B, 2), C, CLR_WHITE, W - SbW);
        If (B >= 32) And (B < 127) Then S := S + Chr(B) Else S := S + '.';
      End
      Else
      Begin
        Dummy := TextAt(Hps, X, R, '??', CLR_DARKGRAY, CLR_WHITE, W - SbW);
        S := S + ' ';
      End;
      X := X + 3 * ChW;
    End;
    If Dim Then C := CLR_DARKGRAY Else C := CLR_DARKGREEN;
    Dummy := TextAt(Hps, Xa, R, S, C, CLR_WHITE, W - SbW);
  End;
End;

{ commentaire d'une valeur de la pile : adresse de code nommee }
Function CodeName(V : LongInt) : String;
Var S : String;
Begin
  CodeName := '';
  If (V >= CodeLo) And (V < CodeHi) Then
  Begin
    S := SymNear(V, $FFFF);
    If S = '' Then S := ModName + '+' + NumStr(V - ImgBase);
    CodeName := S;
  End
  Else If (V >= $800000) Then CodeName := SymNear(V, $1000);
End;

Procedure PaintStack(Hps, W : LongInt);
Var R, Rows, N, A, V, Bg, C, X : LongInt; S : String;
Begin
  If (Pid = 0) Or (DState = 3) Then Exit;
  Rows := PaneRows(PnStack);
  N := ReadSafe(StkTop, MinL(4096, Rows * 4), LongInt(@MemNow));
  For R := 0 To Rows - 1 Do
  Begin
    A := StkTop + R * 4;
    Bg := CLR_WHITE;
    If Not Dim Then
    Begin
      If A = Regs[7] Then Bg := CLR_YELLOW;
      If (A = StkSel) And (ActPane = PnStack) Then Bg := CLR_CYAN;
    End;
    If Bg <> CLR_WHITE Then FillR(Hps, 2, RowY(R), W - SbW - 2, RowY(R) + ChH, Bg);
    If (A = Regs[7]) Then Dummy := TextAt(Hps, 4, R, 'ESP', CLR_DARKPINK, Bg, W - SbW)
    Else If (A = Regs[6]) Then Dummy := TextAt(Hps, 4, R, 'EBP', CLR_DARKPINK, Bg, W - SbW);
    If Dim Then C := CLR_DARKGRAY Else C := CLR_BLACK;
    X := TextAt(Hps, 4 + 4 * ChW, R, Hex8(A), C, Bg, W - SbW);
    If R * 4 + 3 < N Then
    Begin
      V := MemNow[R * 4] Or (MemNow[R * 4 + 1] Shl 8) Or (MemNow[R * 4 + 2] Shl 16) Or (MemNow[R * 4 + 3] Shl 24);
      If Dim Then C := CLR_DARKGRAY Else C := CLR_DARKBLUE;
      X := TextAt(Hps, X + ChW, R, Hex8(V), C, Bg, W - SbW);
      S := CodeName(V);
      If S <> '' Then
      Begin
        If Dim Then C := CLR_DARKGRAY Else C := CLR_BROWN;
        Dummy := TextAt(Hps, X + ChW, R, S, C, Bg, W - SbW);
      End;
    End
    Else Dummy := TextAt(Hps, X + ChW, R, '????????', CLR_DARKGRAY, Bg, W - SbW);
  End;
End;

Function PaneTitle(K : LongInt) : String;
Var S : String;
Begin
  Case K Of
    PnCode :
      Begin
        S := 'Code';
        If DState = 2 Then
        Begin
          S := S + ' - EIP ' + Hex8(Regs[8]);
          If SymNear(Regs[8], $FFFF) <> '' Then S := S + '  ' + SymNear(Regs[8], $FFFF);
        End;
      End;
    PnRegs : S := L2('Registres', 'Registers');
    PnMem : S := L2('M'#130'moire', 'Memory') + ' - ' + Hex8(MemAddr);
  Else
    S := L2('Pile', 'Stack') + ' - ESP ' + Hex8(Regs[7]);
  End;
  If DState = 1 Then S := S + L2(' (ex'#130'cution...)', ' (running...)');
  PaneTitle := S;
End;

Procedure PaintPane(K, H : LongInt);
Var Hps, W, Ht, Fg, Bg : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  Hps := BeginPaint(H, LongInt(@PaintS));
  Dummy := GetClientRect(H, LongInt(@Rc));
  W := Rc[2]; Ht := Rc[3];
  PaintW := W; PaintH := Ht;
  { en-tete : bleu fonce pour le volet actif (comme une barre de titre) }
  If K = ActPane Then Begin Bg := CLR_DARKBLUE; Fg := CLR_WHITE; End
  Else Begin Bg := CLR_PALEGRAY; Fg := CLR_BLACK; End;
  FillR(Hps, 0, Ht - HdrH, W, Ht, Bg);
  FillR(Hps, 0, Ht - HdrH, W, Ht - HdrH + 1, CLR_DARKGRAY);
  TextOutAt(Hps, 6, Ht - HdrH + 1 + (HdrH - 1 - ChH) Div 2, W - 4, PaneTitle(K), Fg, Bg);
  { contenu }
  FillR(Hps, 0, 0, W, Ht - HdrH, CLR_WHITE);
  Dim := DState <> 2;
  Case K Of
    PnCode : PaintCode(Hps, W);
    PnRegs : PaintRegs(Hps, W);
    PnMem : PaintMem(Hps, W);
    PnStack : PaintStack(Hps, W);
  End;
  { cadre }
  FillR(Hps, 0, 0, W, 1, CLR_DARKGRAY);
  FillR(Hps, 0, 0, 1, Ht, CLR_DARKGRAY);
  FillR(Hps, W - 1, 0, W, Ht, CLR_DARKGRAY);
  FillR(Hps, 0, Ht - 1, W, Ht, CLR_DARKGRAY);
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

{ etendue de la barre du volet Memoire : l'image, ou 64 Ko autour }
Procedure MemRange(Var Lo, Hi : LongInt);
Begin
  If (MemAddr >= ImgBase) And (MemAddr < ImgBase + ImgSize) Then
  Begin
    Lo := ImgBase; Hi := ImgBase + ImgSize;
  End
  Else
  Begin
    Lo := MemAddr And $FFFF0000; Hi := Lo + $10000;
  End;
End;

Procedure StkRange(Var Lo, Hi : LongInt);
Begin
  Lo := (Regs[7] And $FFFF0000) - $10000;
  Hi := Lo + $30000;
End;

{ barres de defilement des volets Code, Memoire, Pile }
{ barre de defilement H : position P sur 0..N }
Procedure SetBar(H, P, N : LongInt);
Begin
  If H = 0 Then Exit;
  Dummy := SetScrollRange(H, SB_CTL, 0, MaxL(1, N), 0);
  Dummy := SetScrollPos(H, SB_CTL, P, 1);
End;

{ barres de defilement des volets Code, Memoire, Pile }
Procedure UpdateBars;
Var Lo, Hi, P : LongInt;
Begin
  If Pid = 0 Then Exit;
  { Code : l'image du programme, ou 64 Ko autour d'une DLL }
  If (CodeTop >= ImgBase) And (CodeTop < ImgBase + ImgSize) Then
  Begin
    Lo := ImgBase; Hi := ImgBase + ImgSize;
  End
  Else
  Begin
    Lo := CodeTop And $FFFF0000; Hi := Lo + $10000;
  End;
  SetBar(PaneSb[PnCode], (CodeTop - Lo) Div 64, (Hi - Lo) Div 64);
  MemRange(Lo, Hi);
  P := MaxL(0, MinL(Hi - Lo, MemAddr - Lo));
  SetBar(PaneSb[PnMem], P Div 64, (Hi - Lo) Div 64);
  { Pile : 192 Ko autour d'ESP }
  StkRange(Lo, Hi);
  P := MaxL(0, MinL(Hi - Lo, StkTop - Lo));
  SetBar(PaneSb[PnStack], P Div 16, (Hi - Lo) Div 16);
End;

Procedure Refresh;
Begin
  UpdateBars;
  InvAll;
End;

{ --------------------------------------------------------- execution }

Function EventName(E : LongInt) : String;
Begin
  Case E Of
    256 : EventName := L2('Point d''entr'#130'e du programme', 'Program entry point');
    1 : EventName := L2('Pas', 'Step');
    3 : EventName := L2('Point d''arr'#136't', 'Breakpoint');
    0 : EventName := L2('Exception 00h : division par z'#130'ro', 'Exception 00h: divide error');
    4 : EventName := L2('Exception 04h : d'#130'bordement (INTO)', 'Exception 04h: overflow');
    5 : EventName := L2('Exception 05h : limite (BOUND)', 'Exception 05h: bound range');
    6 : EventName := L2('Exception 06h : instruction invalide', 'Exception 06h: invalid opcode');
    7 : EventName := L2('Exception 07h : coprocesseur absent', 'Exception 07h: no coprocessor');
    8 : EventName := L2('Exception 08h : double faute', 'Exception 08h: double fault');
    10 : EventName := L2('Exception 0Ah : TSS invalide', 'Exception 0Ah: invalid TSS');
    11 : EventName := L2('Exception 0Bh : segment absent', 'Exception 0Bh: segment not present');
    12 : EventName := L2('Exception 0Ch : faute de pile', 'Exception 0Ch: stack fault');
    13 : EventName := L2('Exception 0Dh : protection g'#130'n'#130'rale', 'Exception 0Dh: general protection');
    14 : EventName := L2('Exception 0Eh : d'#130'faut de page', 'Exception 0Eh: page fault');
    16 : EventName := L2('Exception 10h : erreur du coprocesseur', 'Exception 10h: FPU error');
    17 : EventName := L2('Exception 11h : alignement', 'Exception 11h: alignment check');
  Else
    EventName := 'Exception ' + HexDig(E, 2) + 'h';
  End;
End;

{ le programme s'est arrete (evenement Ev) }
Procedure Stopped(Ev : LongInt);
Var S : String;
Begin
  RemoveBps;
  Dummy := GetRegs;
  LastEv := Regs[14];
  If LastEv < 0 Then LastEv := Ev;
  { point d'arret temporaire (F4, F8, Alt+F8) : un pas pour l'utilisateur }
  If (LastEv = 3) And (TmpBp = Regs[8]) And (BpIndex(Regs[8]) < 0) Then LastEv := 1;
  TmpBp := -1;
  DState := 2;
  If Not SymOk Then LoadSymbols;
  CodeSel := Regs[8];
  CodeShow(Regs[8]);
  StkTop := Regs[7] And Not 3;
  StkSel := StkTop;
  If (LastEv = 1) And Pausing Then S := 'Pause' Else S := EventName(LastEv);
  Pausing := False;
  S := S + L2(' '#133' ', ' at ') + Hex8(Regs[8]);
  If SymNear(Regs[8], $FFFF) <> '' Then S := S + ' (' + SymNear(Regs[8], $FFFF) + ')';
  SetStatus(StateName + ' : ' + S);
  UpdateButtons;
  Refresh;
  Dummy := SetForegroundWindow(Frame);
  Dummy := SetActiveWindow(Frame);
  Dummy := SetFocus(PaneH[ActPane]);
  If (LastEv <> 1) And (LastEv <> 3) And (LastEv <> 256) Then
  Begin
    Dummy := MessageBeep(MB_ERROR);
    S := S + '.';
    If LastEv = 14 Then S := S + '|CR2 = ' + Hex8(Regs[15]);
    S := S + '||' + L2('Le programme sera termin'#130' si son ex'#130'cution reprend.',
                      'The program will be terminated if execution resumes.');
    Dummy := MsgBox(S, MB_OK Or MB_ERROR);
  End;
End;

Procedure Terminated(Code : LongInt);
Begin
  BpIn := False;
  ExitCode := Code;
  DState := 3;
  Pid := 0; HProc := 0; HThr := 0; EvState := 0;
  SetStatus(StateName + ' : ' + L2('le programme s''est termin'#130' (code ', 'the program has terminated (code ') +
            CodeStr(Code) + ').');
  UpdateButtons;
  InvAll;
End;

{ etat du programme qui s'execute (minuterie) }
{ etat du programme qui s'execute (minuterie) }
Procedure CheckState;
Var S, Ev : LongInt;
Begin
  If (DState <> 1) Or (Pid = 0) Then Exit;
  Ev := 0;
  S := DbgState(0, Ev);
  If S = 1 Then Stopped(Ev)
  Else If S = 2 Then Terminated(Ev);
End;

{ attendre un arret (un pas) ; rend l'etat }
{ attendre un arret (un pas) ; rend l'etat }
Function WaitStop(Ms : LongInt) : LongInt;
Var Ev : LongInt;
Begin
  WaitStop := DbgState(Ms, Ev);
End;

Procedure SnapMem;
Begin
  Move(Regs, OldRegs, SizeOf(Regs));
  HaveOld := True;
  SnapA := MemAddr;
  SnapN := ReadSafe(MemAddr, MinL(4096, PaneRows(PnMem) * MemPerRow), LongInt(@Snap));
End;

{ reprendre l'execution (Step : un seul pas) }
Procedure Resume(Step : Boolean);
Var S, Ev : LongInt;
Begin
  If (DState <> 2) Or (Pid = 0) Then Exit;
  SnapMem;
  If Step Then
  Begin
    DState := 1;
    DbgGo(True);
    S := WaitStop(200);
    If S = 0 Then
    Begin
      SetStatus(StateName + '...');
      UpdateButtons;
      InvAll;
    End
    Else CheckState;
    Exit;
  End;
  { point d'arret sur EIP : un pas sans les points d'arret d'abord }
  If BpIndex(Regs[8]) >= 0 Then
  Begin
    DbgGo(True);
    S := WaitStop(300);
    If S <> 0 Then
    Begin
      Ev := 0;
      Dummy := DbgState(0, Ev);
      If (S <> 1) Or (Ev <> 1) Then
      Begin
        DState := 1;
        CheckState;
        Exit;
      End;
      If (TmpBp <> -1) And (GetRegs >= 0) And (Regs[8] = TmpBp) Then
      Begin
        DState := 1;
        CheckState;
        Exit;
      End;
    End;
  End;
  InsertBps;
  DState := 1;
  DbgGo(False);
  SetStatus(StateName + '... ' + L2('(F12 : pause)', '(F12: pause)'));
  UpdateButtons;
  InvAll;
End;

{ destination d'un appel (E8, FF 15, FF D0+r) ; -1 : inconnue }
Function CallTarget : LongInt;
Const RIx : Array[0..7] Of Byte = (0, 2, 3, 1, 7, 6, 4, 5);
Begin
  CallTarget := DTarget;
  If DBuf[0] = $FF Then
  Begin
    If DBuf[1] = $15 Then CallTarget := PrL(DBuf[2] Or (DBuf[3] Shl 8) Or (DBuf[4] Shl 16) Or (DBuf[5] Shl 24))
    Else If (DBuf[1] >= $D0) And (DBuf[1] <= $D7) Then CallTarget := Regs[RIx[DBuf[1] - $D0]];
  End;
End;

{ F7 : un pas ; un appel d'une fonction du noyau (KERNEL32, USER32...)
  est saute comme avec F8 }
Procedure StepInto;
Var N, T : LongInt;
Begin
  If DState <> 2 Then Exit;
  If CodeAt(Regs[8]) Then
  Begin
    N := Disasm(Regs[8]);
    If DIsCall Then
    Begin
      T := CallTarget;
      If (T <> -1) And Not InImage(T) And Not Writable(T) Then
      Begin
        TmpBp := Regs[8] + N;
        Resume(False);
        Exit;
      End;
    End;
  End;
  Resume(True);
End;

{ F8 : sauter les appels et les instructions repetees }
Procedure StepOver;
Var N : LongInt;
Begin
  If DState <> 2 Then Exit;
  If Not CodeAt(Regs[8]) Then Exit;
  N := Disasm(Regs[8]);
  If DIsCall Or (DBuf[0] = $F3) Or (DBuf[0] = $F2) Or ((DBuf[0] >= $E0) And (DBuf[0] <= $E2)) Or (DBuf[0] = $CD) Then
  Begin
    TmpBp := Regs[8] + N;
    Resume(False);
  End
  Else Resume(True);
End;

{ Alt+F8 : jusqu'au retour (adresse de retour du cadre EBP) }
Procedure TillReturn;
Var A, V : LongInt;
Begin
  If DState <> 2 Then Exit;
  If CodeAt(Regs[8]) And ((DBuf[0] = $C3) Or (DBuf[0] = $C2)) Then
  Begin
    Resume(True);
    Exit;
  End;
  { debut de procedure (push ebp ; mov ebp,esp pas encore faits) : [ESP] }
  A := Regs[6] + 4;
  If CodeAt(Regs[8]) And (DBuf[0] = $55) Then A := Regs[7];
  V := 0;
  If ReadMem(A, 4, LongInt(@V)) <> 4 Then Exit;
  TmpBp := V;
  Resume(False);
End;

Procedure Pause;
Begin
  If (DState = 1) And (Pid <> 0) Then
  Begin
    Dummy := DebugBreakProcess(HProc);
    Pausing := True;
    SetStatus(L2('Pause demand'#130'e...', 'Pause requested...'));
  End;
End;

Procedure KillDebuggee;
Var T : LongInt;
Begin
  If (Pid <> 0) And ((DState = 1) Or (DState = 2)) Then
  Begin
    RemoveBps;
    Dummy := TerminateProcess(HProc, LongInt(-1));
    { la fin (EXIT_PROCESS_DEBUG_EVENT) libere la session de debogage }
    T := 0;
    While (EvState <> 2) And (T < 20) Do
    Begin
      If EvState = 1 Then DbgGo(False);
      PollDebug(100);
      Inc(T);
    End;
  End;
  Pid := 0; HProc := 0; HThr := 0; EvState := 0;
  BpIn := False;
  If DState <> 0 Then DState := 3;
  ExitCode := -1;
End;

{ lancer ExePath sous le debogueur ; il s'arrete a son point d'entree }
{ lancer ExePath sous le debogueur ; il s'arrete a son point d'entree }
Procedure StartDebug;
Var Si : Array[0..16] Of LongInt; Pi : Array[0..3] Of LongInt; Rc : LongInt; S : String;
  CmdB : Array[0..511] Of Byte;
Begin
  KillDebuggee;
  S := '"' + ExePath + '"';
  If ExeArgs <> '' Then S := S + ' ' + ExeArgs;
  PutZ(LongInt(@CmdB), S);
  FillChar(Si, SizeOf(Si), 0);
  Si[0] := 68;
  FillChar(Pi, SizeOf(Pi), 0);
  EvState := 0; FirstStop := True; HProc := 0; HThr := 0; KillCode := 0;
  ImgBase := 0; ImgEntry := 0;
  If CreateProcessA(Z(ExePath), LongInt(@CmdB), 0, 0, 0, DEBUG_ONLY_THIS_PROCESS, 0, Z2(DirOf(ExePath)),
                    LongInt(@Si), LongInt(@Pi)) = 0 Then
  Begin
    Rc := GetLastError;
    DState := 0;
    UpdateButtons;
    Dummy := MsgBox(L2('Impossible de lancer ', 'Cannot start ') + ExePath + ' (' + L2('erreur ', 'error ') + IStr(Rc) + ').',
                    MB_OK Or MB_ERROR);
    InvAll;
    Exit;
  End;
  Pid := Pi[2]; DTid := Pi[3];
  HProc := Pi[0]; HThr := Pi[1];
  ModName := UpStr(NoExt(BaseName(ExePath)));
  SymN := 0; SymOk := False; HaveOld := False; TmpBp := -1; BpIn := False; RcLen := 0; CLen := 0;
  FillChar(Regs, SizeOf(Regs), 0);
  DState := 1;
  SetStatus(L2('Chargement de ', 'Loading ') + ExePath + '...');
  UpdateButtons;
  { CREATE_PROCESS_DEBUG_EVENT puis le point d'entree }
  PollDebug(500);
  If ImgBase = 0 Then ImgBase := $400000;
  ImgSize := PrL(ImgBase + PrL(ImgBase + $3C) + 80);
  If (ImgSize <= 0) Or (ImgSize > $4000000) Then ImgSize := $100000;
  RcLen := 0;
  CodeLo := ImgBase; CodeHi := ImgBase + ImgSize;
  CodeTop := ImgEntry; CodeSel := ImgEntry;
  If WaitStop(2000) <> 0 Then CheckState;
  { donnees : la premiere section de donnees }
  MemAddr := DataVa And Not 15;
  UpdateBars;
  InvAll;
End;

Procedure ToggleBp(A : LongInt);
Var K : LongInt;
Begin
  If (DState <> 2) Then Exit;
  K := BpIndex(A);
  If K >= 0 Then
  Begin
    BpA[K] := BpA[BpN - 1];
    Dec(BpN);
  End
  Else If (A < ImgBase) Or (A >= ImgBase + ImgSize) Then
  Begin
    Dummy := MessageBeep(MB_WARNING);
    SetStatus(L2('Les points d''arr'#136't se posent dans le programme (pas dans le noyau ni les DLL).',
                 'Breakpoints can only be set in the program (not in the kernel or DLLs).'));
    Exit;
  End
  Else If BpN < BpMax Then
  Begin
    BpA[BpN] := A;
    Inc(BpN);
  End;
  InvAll;
End;


{ ------------------------------------------------- boite de saisie }

Function InputProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Begin
  InputProc := 0;
  Case Msg Of
    WM_PAINT : DlgPaint(H);
    WM_COMMAND :
      If Lo16(Mp1) = ID_OK Then DlgEnd := ID_OK
      Else If Lo16(Mp1) = ID_CANCEL Then DlgEnd := ID_CANCEL;
    WM_CLOSE : DlgEnd := ID_CANCEL;
  Else
    InputProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

Function InputBox(Title, Prompt : String; Var S : String) : Boolean;
Var W, H, C : LongInt;
Begin
  InputBox := False;
  W := 380; H := 112;
  If Not DlgOpen('DBGINPUT', Title, W, H) Then Exit;
  C := Ctl('STATIC', (Prompt), 0, 10, H - 30, W - 20, 20, 10);
  Gray(C);
  DlgEf := Ctl('EDIT', '', WS_TABSTOP Or ES_AUTOHSCROLL, 10, H - 56, W - 20, 20, ID_EF);
  Dummy := SendMessageA(DlgEf, EM_LIMITTEXT, 250, 0);
  Dummy := Ctl('BUTTON', ('OK'), WS_TABSTOP Or BS_DEFPUSHBUTTON, W - 208, 8, 96, 26, ID_OK);
  Dummy := Ctl('BUTTON', (L('Annuler', 'Cancel', 'Abbrechen', 'Annulla', 'Cancelar')),
               WS_TABSTOP Or BS_PUSHBUTTON, W - 104, 8, 96, 26, ID_CANCEL);
  Dummy := SetWindowTextA(DlgEf, Z(S));
  Dummy := SendMessageA(DlgEf, EM_SETSEL, 0, Length(S));
  If DlgRun(DlgEf) = ID_OK Then
  Begin
    S := CtlText(DlgEf);
    InputBox := True;
  End;
  DlgClose;
End;

{ ------------------------------------------------------- commandes }

Procedure GotoAddr;
Var S : String; V : LongInt;
Begin
  If DState <> 2 Then Exit;
  If ActPane = PnMem Then S := Hex8(MemAddr)
  Else If ActPane = PnStack Then S := 'ESP'
  Else S := Hex8(CodeSel);
  If Not InputBox(L2('Aller '#133' l''adresse', 'Go to address'),
                  L2('Adresse (hexad'#130'cimal, registre, symbole, + et -) :', 'Address (hex, register, symbol, + and -):'),
                  S) Then Exit;
  If Not EvalExpr(S, V) Then
  Begin
    Dummy := MsgBox(L2('Adresse incorrecte : ', 'Invalid address: ') + S, MB_OK Or MB_WARNING);
    Exit;
  End;
  Case ActPane Of
    PnMem : MemAddr := V And Not 15;
    PnStack : Begin StkTop := V And Not 3; StkSel := StkTop; End;
  Else
    Begin
      CodeSel := V; CodeTop := V;
      BuildLines;
    End;
  End;
  Refresh;
End;

{ modifier le registre RegSel (ou inverser un drapeau) }
Procedure EditReg;
Var S : String; V, I : LongInt;
Begin
  If DState <> 2 Then Exit;
  If RegSel >= 10 Then
  Begin
    I := RegSel - 10;
    Regs[9] := Regs[9] Xor (1 Shl FlBit[I]);
  End
  Else
  Begin
    I := RegSel;
    If I > 9 Then I := 9;
    If I = 9 Then S := Hex8(Regs[9]) Else S := Hex8(Regs[I]);
    If I = 9 Then V := 0 Else V := I;
    If Not InputBox(L2('Modifier le registre', 'Change register'),
                    L2('Nouvelle valeur de ', 'New value of ') + Copy('EAXEBXECXEDXESIEDIEBPESPEIPEFL', I * 3 + 1, 3) + ' :',
                    S) Then Exit;
    If Not EvalExpr(S, V) Then
    Begin
      Dummy := MsgBox(L2('Valeur incorrecte : ', 'Invalid value: ') + S, MB_OK Or MB_WARNING);
      Exit;
    End;
    Regs[I] := V;
  End;
  Dummy := SetRegs;
  Dummy := GetRegs;
  If RegSel = 8 Then
  Begin
    CodeSel := Regs[8];
    CodeShow(Regs[8]);
  End;
  Refresh;
End;

Procedure ListBps;
Var S : String; I : LongInt;
Begin
  If BpN = 0 Then S := L2('Aucun point d''arr'#136't.', 'No breakpoints.')
  Else
  Begin
    S := L2('Points d''arr'#136't :', 'Breakpoints:');
    For I := 0 To MinL(BpN, 12) - 1 Do
    Begin
      S := S + '|' + Hex8(BpA[I]);
      If SymNear(BpA[I], $FFFF) <> '' Then S := S + '  ' + SymNear(BpA[I], $FFFF);
    End;
    If BpN > 12 Then S := S + '|...';
  End;
  Dummy := MsgBox(S, MB_OK Or MB_INFORMATION);
End;

{ volet Pile : la valeur choisie est montree dans Code ou Memoire }
Procedure Follow;
Var V : LongInt;
Begin
  If DState <> 2 Then Exit;
  If ActPane = PnStack Then
  Begin
    V := 0;
    If ReadMem(StkSel, 4, LongInt(@V)) <> 4 Then Exit;
  End
  Else If ActPane = PnCode Then
  Begin
    BuildLines;
    If SelLine < 0 Then Exit;
    V := LnTgt[SelLine];
    If V = -1 Then Exit;
  End
  Else Exit;
  If ((V >= CodeLo) And (V < CodeHi)) Or (V >= $800000) And (SymNear(V, $1000) <> '') Then
  Begin
    CodeSel := V;
    CodeShow(V);
  End
  Else MemAddr := V And Not 15;
  Refresh;
End;

Procedure OpenProgram;
Var S : String;
Begin
  S := ExePath;
  FdMaskInit := '*.EXE';
  If Not FileDialog(False, S) Then Exit;
  If UpStr(S) <> UpStr(ExePath) Then BpN := 0;
  ExePath := S;
  StartDebug;
End;

Procedure About;
Begin
  Dummy := MsgBox('Pasdows Debugger||' +
    L2('D'#130'bogueur des programmes Win32 de Pasdows 95 (PE de WPC) dans l''esprit de Turbo Debugger, '
       + 'avec l''apparence de Windows 95.|D'#130'sassembleur x86 32 bits color'#130', registres, m'#130'moire, '
       + 'pile, points d''arr'#136't, pas '#133' pas.',
       'Debugger for Pasdows 95 Win32 programs (WPC PE) in the spirit of Turbo Debugger, with the Windows 95 '
       + 'look.|Colored x86 32-bit disassembler, registers, memory, stack, breakpoints, single step.'),
    MB_OK Or MB_INFORMATION);
End;

Procedure Keys;
Begin
  Dummy := MsgBox(L2('F9 : ex'#130'cuter|F7 : pas '#133' pas (entrer dans les appels)|F8 : pas (sauter les appels)|'
       + 'F4 : jusqu''au curseur|Alt+F8 : jusqu''au retour|F12 : pause|F2 : point d''arr'#136't|'
       + 'Ctrl+F2 : red'#130'marrer|Alt+F2 : terminer le programme|Ctrl+G : aller '#133' l''adresse|'
       + 'Ctrl+E : origine (EIP)|Entr'#130'e : modifier le registre, suivre une valeur|Tab : volet suivant',
       'F9: run|F7: step into|F8: step over|F4: run to cursor|Alt+F8: run till return|F12: pause|'
       + 'F2: breakpoint|Ctrl+F2: restart|Alt+F2: terminate program|Ctrl+G: go to address|'
       + 'Ctrl+E: origin (EIP)|Enter: change register, follow value|Tab: next pane'),
    MB_OK Or MB_INFORMATION);
End;

Procedure SetActive(K : LongInt);
Begin
  If K = ActPane Then Exit;
  ActPane := K;
  InvAll;
End;

Procedure Command(Id : LongInt);
Var S : String;
Begin
  Case Id Of
    idOpen : OpenProgram;
    idArgs :
      Begin
        S := ExeArgs;
        If InputBox(L2('Arguments', 'Arguments'), L2('Arguments du programme (au prochain d'#130'marrage) :',
                    'Program arguments (next start):'), S) Then ExeArgs := S;
      End;
    idRestart : If ExePath <> '' Then StartDebug;
    idKill :
      If (DState = 1) Or (DState = 2) Then
      Begin
        KillDebuggee;
        Terminated(-1);
      End;
    idExit : Dummy := PostMessageA(Client, WM_CLOSE, 0, 0);
    idRun : Resume(False);
    idStep : StepInto;
    idOver : StepOver;
    idCursor :
      If DState = 2 Then
      Begin
        If Not InImage(CodeSel) And Not Writable(CodeSel) Then
        Begin
          Dummy := MessageBeep(MB_WARNING);
          SetStatus(L2('Pas d''arr'#136't possible dans le code du noyau (KERNEL32, USER32...).',
                       'No stop possible in the kernel code (KERNEL32, USER32...).'));
          Exit;
        End;
        TmpBp := CodeSel;
        Resume(False);
      End;
    idReturn : TillReturn;
    idPause : Pause;
    idBpToggle : ToggleBp(CodeSel);
    idBpClear : Begin BpN := 0; InvAll; End;
    idBpList : ListBps;
    idGoto : GotoAddr;
    idRegEdit : EditReg;
    idOrigin :
      If DState = 2 Then
      Begin
        CodeSel := Regs[8];
        CodeShow(Regs[8]);
        Refresh;
      End;
    idFollow : Follow;
    idAbout : About;
    idKeys : Keys;
  End;
End;

{ touches communes a tous les volets ; True si traitee }
Function GlobalKey(Fl, Ch, Vk : LongInt) : Boolean;
Var Ctrl, Alt, Sh : Boolean;
Begin
  GlobalKey := True;
  Ctrl := (Fl And KC_CTRL) <> 0; Alt := (Fl And KC_ALT) <> 0; Sh := (Fl And KC_SHIFT) <> 0;
  If (Fl And KC_VIRTUALKEY) <> 0 Then
  Begin
    Case Vk Of
      VK_F2 :
        Begin
          If Ctrl Then Command(idRestart)
          Else If Alt Then Command(idKill)
          Else Command(idBpToggle);
          Exit;
        End;
      VK_F4 : Begin Command(idCursor); Exit; End;
      VK_F7 : Begin Command(idStep); Exit; End;
      VK_F8 :
        Begin
          If Alt Then Command(idReturn) Else Command(idOver);
          Exit;
        End;
      VK_F9 : Begin Command(idRun); Exit; End;
      VK_F12 : Begin Command(idPause); Exit; End;
      VK_TAB, VK_BACKTAB :
        Begin
          If (Vk = VK_BACKTAB) Or Sh Then SetActive((ActPane + 3) Mod 4) Else SetActive((ActPane + 1) Mod 4);
          Dummy := SetFocus(PaneH[ActPane]);
          Exit;
        End;
    End;
  End;
  If Ctrl And (Ch > 0) Then
  Begin
    If (Ch >= 1) And (Ch <= 26) Then Ch := Ch + 64;
    Case UpCase(Chr(Ch)) Of
      'G' : Begin Command(idGoto); Exit; End;
      'E' : Begin Command(idOrigin); Exit; End;
      'O' : Begin Command(idOpen); Exit; End;
    End;
  End;
  GlobalKey := False;
End;

Procedure PaneKey(K, Fl, Ch, Vk : LongInt);
Var R : LongInt;
Begin
  If GlobalKey(Fl, Ch, Vk) Then Exit;
  If DState <> 2 Then Exit;
  If (Fl And KC_VIRTUALKEY) = 0 Then Vk := 0;
  Case K Of
    PnCode :
      If (Vk = VK_ENTER) Or (Vk = VK_NEWLINE) Then Follow
      Else If Vk <> 0 Then CodeKey(Vk);
    PnRegs :
      Case Vk Of
        VK_UP : If RegSel > 0 Then Dec(RegSel);
        VK_DOWN : If RegSel < 18 Then Inc(RegSel);
        VK_LEFT : If RegSel >= 10 Then RegSel := RegSel - 10;
        VK_RIGHT : If RegSel < 9 Then RegSel := RegSel + 10;
        VK_ENTER, VK_NEWLINE, VK_SPACE : EditReg;
      End;
    PnMem :
      Begin
        R := PaneRows(PnMem) * MemPerRow;
        Case Vk Of
          VK_UP : MemAddr := MemAddr - MemPerRow;
          VK_DOWN : MemAddr := MemAddr + MemPerRow;
          VK_PAGEUP : MemAddr := MemAddr - R;
          VK_PAGEDOWN : MemAddr := MemAddr + R;
        End;
      End;
    PnStack :
      Begin
        R := PaneRows(PnStack);
        Case Vk Of
          VK_UP : StkSel := StkSel - 4;
          VK_DOWN : StkSel := StkSel + 4;
          VK_PAGEUP : StkSel := StkSel - R * 4;
          VK_PAGEDOWN : StkSel := StkSel + R * 4;
          VK_HOME : StkSel := Regs[7] And Not 3;
          VK_ENTER, VK_NEWLINE : Follow;
        End;
        If StkSel < StkTop Then StkTop := StkSel;
        If StkSel >= StkTop + R * 4 Then StkTop := StkSel - (R - 1) * 4;
      End;
  End;
  Refresh;
End;

Procedure PaneScroll(K, Cmd, P : LongInt);
Var Lo, Hi : LongInt;
Begin
  If DState <> 2 Then Exit;
  Case K Of
    PnCode :
      Begin
        Case Cmd Of
          SB_LINEUP : CodeUp;
          SB_LINEDOWN : CodeDown;
          SB_PAGEUP : CodeKey(VK_PAGEUP);
          SB_PAGEDOWN : CodeKey(VK_PAGEDOWN);
          SB_SLIDERTRACK, SB_SLIDERPOSITION :
            Begin
              If (CodeTop >= ImgBase) And (CodeTop < ImgBase + ImgSize) Then Lo := ImgBase Else Lo := CodeTop And $FFFF0000;
              CodeTop := Lo + P * 64;
              BuildLines;
            End;
        End;
      End;
    PnMem :
      Case Cmd Of
        SB_LINEUP : MemAddr := MemAddr - MemPerRow;
        SB_LINEDOWN : MemAddr := MemAddr + MemPerRow;
        SB_PAGEUP : MemAddr := MemAddr - PaneRows(PnMem) * MemPerRow;
        SB_PAGEDOWN : MemAddr := MemAddr + PaneRows(PnMem) * MemPerRow;
        SB_SLIDERTRACK, SB_SLIDERPOSITION :
          Begin
            MemRange(Lo, Hi);
            MemAddr := Lo + P * 64;
          End;
      End;
    PnStack :
      Case Cmd Of
        SB_LINEUP : StkTop := StkTop - 4;
        SB_LINEDOWN : StkTop := StkTop + 4;
        SB_PAGEUP : StkTop := StkTop - PaneRows(PnStack) * 4;
        SB_PAGEDOWN : StkTop := StkTop + PaneRows(PnStack) * 4;
        SB_SLIDERTRACK, SB_SLIDERPOSITION :
          Begin
            StkRange(Lo, Hi);
            StkTop := (Lo + P * 16) And Not 3;
          End;
      End;
  End;
  Refresh;
End;

{ clic dans un volet (Dbl : double clic) }
Procedure PaneClick(K, X, Y : LongInt; Dbl : Boolean);
Var R : LongInt;
Begin
  SetActive(K);
  If DState <> 2 Then Exit;
  R := (PaneHt[K] - HdrH - 2 - Y) Div ChH;
  If (Y > PaneHt[K] - HdrH) Or (R < 0) Then Exit;
  Case K Of
    PnCode :
      Begin
        BuildLines;
        If R < LnN Then
        Begin
          CodeSel := LnA[R];
          If (X < 16) Or Dbl Then ToggleBp(CodeSel);
        End;
      End;
    PnRegs :
      If R <= 9 Then
      Begin
        If (X >= 6 + 14 * ChW - 2) And (R <= 8) Then RegSel := 10 + R Else RegSel := R;
        If Dbl Then EditReg;
      End;
    PnStack :
      Begin
        StkSel := StkTop + R * 4;
        If Dbl Then Follow;
      End;
  End;
  InvAll;
End;

{ touches de Windows -> codes internes (Fl : KC_..., Ch, Vk) ; faux si
  la touche n'est pas pour le debogueur }
Function KeyMsg(Msg, Wp : LongInt; Var Fl, Ch, Vk : LongInt) : Boolean;
Begin
  KeyMsg := False;
  Fl := 0; Ch := 0; Vk := 0;
  If (GetKeyState($10) And $8000) <> 0 Then Fl := Fl Or KC_SHIFT;
  If (GetKeyState($11) And $8000) <> 0 Then Fl := Fl Or KC_CTRL;
  If (GetKeyState($12) And $8000) <> 0 Then Fl := Fl Or KC_ALT;
  Case Wp Of
    8 : Vk := VK_BACKSPACE;
    9 : If (Fl And KC_SHIFT) <> 0 Then Vk := VK_BACKTAB Else Vk := VK_TAB;
    13 : Vk := VK_NEWLINE;
    27 : Vk := VK_ESC;
    $20 : Vk := VK_SPACE;
    $21 : Vk := VK_PAGEUP;
    $22 : Vk := VK_PAGEDOWN;
    $23 : Vk := VK_END;
    $24 : Vk := VK_HOME;
    $25 : Vk := VK_LEFT;
    $26 : Vk := VK_UP;
    $27 : Vk := VK_RIGHT;
    $28 : Vk := VK_DOWN;
    $2E : Vk := VK_DELETE;
    $70..$7B : Vk := VK_F1 + Wp - $70;
  End;
  If Vk <> 0 Then
  Begin
    { Alt : seulement Alt+F2 et Alt+F8 (le reste va aux menus) }
    If ((Fl And KC_ALT) <> 0) And (Vk <> VK_F2) And (Vk <> VK_F8) Then Exit;
    Fl := Fl Or KC_VIRTUALKEY;
    KeyMsg := True;
  End
  Else If ((Fl And KC_CTRL) <> 0) And ((Fl And KC_ALT) = 0) And (Wp >= Ord('A')) And (Wp <= Ord('Z')) Then
  Begin
    Fl := Fl Or KC_CHAR;
    Ch := Wp - 64;
    KeyMsg := True;
  End;
End;

Function PaneProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var K, I, Fl, Ch, Vk : LongInt;
Begin
  PaneProc := 0;
  K := -1;
  For I := 0 To 3 Do If PaneH[I] = H Then K := I;
  If K < 0 Then
  Begin
    PaneProc := DefWindowProcA(H, Msg, Mp1, Mp2);
    Exit;
  End;
  Case Msg Of
    WM_PAINT : PaintPane(K, H);
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
      Begin
        Dummy := SetFocus(H);
        { ordonnee depuis le bas du volet (comme dans l'original) }
        PaneClick(K, S16(Mp2), PaneHt[K] - 1 - S16(Mp2 Shr 16), Msg = WM_LBUTTONDBLCLK);
      End;
    WM_VSCROLL : PaneScroll(K, Lo16(Mp1), S16(Mp1 Shr 16));
    WM_KEYDOWN, WM_SYSKEYDOWN :
      If KeyMsg(Msg, Mp1, Fl, Ch, Vk) Then PaneKey(K, Fl, Ch, Vk)
      Else PaneProc := DefWindowProcA(H, Msg, Mp1, Mp2);
    WM_CHAR : ;
  Else
    PaneProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ ------------------------------------------------------------- menus }

Procedure BuildMenu;
Var H0, H1 : LongInt;
Begin
  MDepth := 0;
  H0 := MenuOpen;
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, idFile, L('~Fichier', '~File', '~Datei', '~File', '~Archivo'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, idOpen, L2('~Ouvrir un programme...', '~Open program...') + Chr(9) + 'Ctrl+O');
  MItem(MIS_TEXT, 0, idArgs, L2('~Arguments...', '~Arguments...'));
  MItem(MIS_SEPARATOR, 0, 0, '');
  MItem(MIS_TEXT, 0, idRestart, L2('~Red'#130'marrer', '~Restart') + Chr(9) + 'Ctrl+F2');
  MItem(MIS_TEXT, 0, idKill, L2('~Terminer le programme', '~Terminate program') + Chr(9) + 'Alt+F2');
  MItem(MIS_SEPARATOR, 0, 0, '');
  MItem(MIS_TEXT, 0, idExit, L('~Quitter', 'E~xit', '~Beenden', '~Esci', '~Salir'));
  MenuClose(H1, 7);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, idRunM, L2('~Ex'#130'cution', '~Run'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, idRun, L2('~Ex'#130'cuter', '~Run') + Chr(9) + 'F9');
  MItem(MIS_TEXT, 0, idStep, L2('~Pas '#133' pas (entrer)', '~Step into') + Chr(9) + 'F7');
  MItem(MIS_TEXT, 0, idOver, L2('Pa~s (sauter les appels)', 'Step ~over') + Chr(9) + 'F8');
  MItem(MIS_TEXT, 0, idCursor, L2('Jusqu''au ~curseur', 'Run to ~cursor') + Chr(9) + 'F4');
  MItem(MIS_TEXT, 0, idReturn, L2('Jusqu''au ~retour', 'Till ~return') + Chr(9) + 'Alt+F8');
  MItem(MIS_SEPARATOR, 0, 0, '');
  MItem(MIS_TEXT, 0, idPause, L2('Pa~use', 'Pa~use') + Chr(9) + 'F12');
  MenuClose(H1, 7);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, idBpM, L2('~Points d''arr'#136't', '~Breakpoints'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, idBpToggle, L2('~Basculer', '~Toggle') + Chr(9) + 'F2');
  MItem(MIS_TEXT, 0, idBpClear, L2('~Supprimer tous', '~Delete all'));
  MItem(MIS_TEXT, 0, idBpList, L2('~Liste...', '~List...'));
  MenuClose(H1, 3);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, idDataM, L2('~Donn'#130'es', '~Data'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, idGoto, L2('~Aller '#133' l''adresse...', '~Go to address...') + Chr(9) + 'Ctrl+G');
  MItem(MIS_TEXT, 0, idOrigin, L2('~Origine (EIP)', '~Origin (EIP)') + Chr(9) + 'Ctrl+E');
  MItem(MIS_TEXT, 0, idFollow, L2('~Suivre la valeur', '~Follow value') + Chr(9) + L2('Entr'#130'e', 'Enter'));
  MItem(MIS_SEPARATOR, 0, 0, '');
  MItem(MIS_TEXT, 0, idRegEdit, L2('~Modifier le registre...', '~Change register...'));
  MenuClose(H1, 5);
  MItem(MIS_TEXT Or MIS_SUBMENU, 0, idHelpM, L('A~ide', '~Help', '~Hilfe', '~Guida', '~Ayuda'));
  H1 := MenuOpen;
  MItem(MIS_TEXT, 0, idKeys, L2('~Touches...', '~Keys...'));
  MItem(MIS_TEXT, 0, idAbout, L2('~A propos de Pasdows Debugger...', '~About Pasdows Debugger...'));
  MenuClose(H1, 2);
  MenuClose(H0, 5);
  MenuHw := H0;
  Dummy := SetMenu(Frame, MenuHw);
End;

Procedure MenuGray(Id : LongInt; Off : Boolean);
Begin
  If Off Then Dummy := EnableMenuItem(MenuHw, Id, MF_GRAYED)
  Else Dummy := EnableMenuItem(MenuHw, Id, MF_ENABLED);
End;

{ choix des menus selon l'etat }
Procedure UpdateMenu;
Var Run, Stop : Boolean;
Begin
  If MenuHw = 0 Then Exit;
  Run := DState = 1; Stop := DState = 2;
  MenuGray(idRestart, ExePath = '');
  MenuGray(idKill, Not (Run Or Stop));
  MenuGray(idRun, Not Stop); MenuGray(idStep, Not Stop); MenuGray(idOver, Not Stop);
  MenuGray(idCursor, Not Stop); MenuGray(idReturn, Not Stop); MenuGray(idPause, Not Run);
  MenuGray(idBpToggle, Not Stop); MenuGray(idBpClear, BpN = 0);
  MenuGray(idGoto, Not Stop); MenuGray(idOrigin, Not Stop); MenuGray(idRegEdit, Not Stop);
  MenuGray(idFollow, Not Stop);
End;

{ ------------------------------------------- barre d'outils et volets }

Function Child(Cls, Txt : String; Style, Par, Id : LongInt) : LongInt;
Begin
  PutZ(LongInt(@ClsBuf), Cls);
  Child := CreateWindowExA(0, LongInt(@ClsBuf), Z(Txt), Style Or WS_CHILD Or WS_VISIBLE, 0, 0, 10, 10, Par, Id,
                           Inst, 0);
End;

Procedure AddButton(Id : LongInt; S : String; Gap : Boolean);
Begin
  TbBtn[TbN] := Child('BUTTON', S, BS_PUSHBUTTON, Client, Id);
  TbW[TbN] := Length(S);
  TbGap[TbN] := Gap;
  Inc(TbN);
End;

Procedure CreateChildren;
Var K : LongInt;
Begin
  TbN := 0;
  AddButton(idOpen, L2('Ouvrir', 'Open'), False);
  AddButton(idRun, L2('Ex'#130'cuter', 'Run'), True);
  AddButton(idStep, L2('Entrer', 'Into'), False);
  AddButton(idOver, L2('Sauter', 'Over'), False);
  AddButton(idCursor, L2('Curseur', 'Cursor'), False);
  AddButton(idReturn, L2('Retour', 'Return'), False);
  AddButton(idPause, 'Pause', True);
  AddButton(idRestart, L2('Relancer', 'Restart'), False);
  AddButton(idKill, L2('Terminer', 'Kill'), False);
  AddButton(idBpToggle, L2('Arr'#136't', 'Break'), True);
  For K := 0 To 3 Do
  Begin
    PaneH[K] := Child('DBGPANE', '', 0, Client, 100 + K);
    If K <> PnRegs Then PaneSb[K] := Child('SCROLLBAR', '', SBS_VERT, PaneH[K], 10 + K)
    Else PaneSb[K] := 0;
  End;
  StatusH := Child('STATIC', '', 0, Client, 30);
  Gray(StatusH);
End;

{ fenetre fille H en (X, Y) depuis le bas de son parent de hauteur PH }
Procedure PlaceAt(H, X, Y, W, Hh, PH : LongInt);
Begin
  Dummy := SetWindowPos(H, 0, X, PH - Y - Hh, W, Hh, SWP_NOZORDER Or SWP_NOACTIVATE);
  Dummy := ShowWindow(H, 5);
End;

Var LayH : LongInt;                    { hauteur de la zone client }

Procedure PosPane(K, X, Y, W, H : LongInt);
Begin
  W := MaxL(W, 40); H := MaxL(H, HdrH + 20);
  PaneW[K] := W; PaneHt[K] := H;
  PlaceAt(PaneH[K], X, Y, W, H, LayH);
  If PaneSb[K] <> 0 Then PlaceAt(PaneSb[K], W - SbW - 1, 1, SbW, H - HdrH - 1, H);
End;

Procedure Layout;
Var W, H, X, I, Top, Bot, Mid, RW, SW, Pad, Gp : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  If StatusH = 0 Then Exit;
  Dummy := GetClientRect(Client, LongInt(@Rc));
  W := Rc[2]; H := Rc[3];
  LayH := H;
  { marges des boutons reduites si la fenetre est etroite (640 x 480) }
  Pad := 18;
  Repeat
    If Pad >= 14 Then Gp := 10 Else Gp := 3;
    X := 4;
    For I := 0 To TbN - 1 Do
    Begin
      If TbGap[I] Then X := X + Gp;
      X := X + TbW[I] * ChW + Pad + 3;
    End;
    If X <= W - 2 Then Break;
    Pad := Pad - 2;
  Until Pad < 6;
  X := 4;
  For I := 0 To TbN - 1 Do
  Begin
    If TbGap[I] Then X := X + Gp;
    If X + TbW[I] * ChW + Pad <= W - 2 Then
      PlaceAt(TbBtn[I], X, H - TbH + 4, TbW[I] * ChW + Pad, 26, H)
    Else Dummy := ShowWindow(TbBtn[I], 0);
    X := X + TbW[I] * ChW + Pad + 3;
  End;
  PlaceAt(StatusH, 3, 2, W - 6, StH - 4, H);
  Top := H - TbH; Bot := StH;
  { haut : Code et Registres (13 lignes au moins), bas : Memoire et Pile }
  Mid := Bot + (Top - Bot) * 2 Div 5;
  If Top - Mid - 2 < 13 * ChH + HdrH + 6 Then Mid := MaxL(Bot + 5 * ChH, Top - 2 - (13 * ChH + HdrH + 6));
  RW := 6 + 18 * ChW + 8;
  SW := MaxL(280, MinL(380, W Div 3));
  PosPane(PnCode, 3, Mid + 2, W - RW - 8, Top - Mid - 2);
  PosPane(PnRegs, W - RW - 3, Mid + 2, RW, Top - Mid - 2);
  PosPane(PnMem, 3, Bot, W - SW - 8, Mid - Bot);
  PosPane(PnStack, W - SW - 3, Bot, SW, Mid - Bot);
  If Pid <> 0 Then
  Begin
    If DState = 2 Then CodeShow(CodeSel);
    UpdateBars;
  End;
  InvAll;
End;

{ ------------------------------------------------------ zone client }

Function ClientProc(H, Msg, Mp1, Mp2 : LongInt) : LongInt; stdcall;
Var Hps, Fl, Ch, Vk : LongInt; Rc : Array[0..3] Of LongInt;
Begin
  ClientProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Hps := BeginPaint(H, LongInt(@PaintS));
        Dummy := GetClientRect(H, LongInt(@Rc));
        PaintH := Rc[3];
        FillR(Hps, 0, 0, Rc[2], Rc[3], CLR_PALEGRAY);
        { separation de la barre d'outils }
        FillR(Hps, 0, Rc[3] - TbH, Rc[2], Rc[3] - TbH + 1, CLR_DARKGRAY);
        FillR(Hps, 0, Rc[3] - TbH - 1, Rc[2], Rc[3] - TbH, CLR_WHITE);
        Dummy := EndPaint(H, LongInt(@PaintS));
      End;
    WM_SIZE : Layout;
    WM_TIMER : CheckState;
    WM_KEYDOWN, WM_SYSKEYDOWN :
      If Not KeyMsg(Msg, Mp1, Fl, Ch, Vk) Or Not GlobalKey(Fl, Ch, Vk) Then
        ClientProc := DefWindowProcA(H, Msg, Mp1, Mp2);
    WM_INITMENU : UpdateMenu;
    WM_COMMAND :
      Begin
        Command(Lo16(Mp1));
        If (DlgFr = 0) And (PaneH[ActPane] <> 0) Then Dummy := SetFocus(PaneH[ActPane]);
      End;
    WM_CLOSE :
      Begin
        KillDebuggee;
        PostQuitMessage(0);
      End;
  Else
    ClientProc := DefWindowProcA(H, Msg, Mp1, Mp2);
  End;
End;

{ classe de fenetre (WNDCLASSA) }
Procedure RegCls(N : String; P, St, Br : LongInt);
Var C : Array[0..9] Of LongInt;
Begin
  PutZ(LongInt(@ClsBuf), N);
  C[0] := St; C[1] := P; C[2] := 0; C[3] := 0; C[4] := Inst; C[5] := 0;
  C[6] := LoadCursorA(0, IDC_ARROW); C[7] := Br; C[8] := 0; C[9] := LongInt(@ClsBuf);
  Dummy := RegisterClassA(LongInt(@C));
End;

Var
  Sw, Sh, W, H, I : LongInt;
  Arg : String;

BEGIN
  LangInit;
  Pid := 0; DState := 0; BpN := 0; TmpBp := -1; Pausing := False; ActPane := PnCode; RegSel := 0; StatusH := 0;
  ExePath := ''; ExeArgs := ''; SymN := 0; DlgFr := 0; MenuHw := 0; HProc := 0; HThr := 0; EvState := 0;
  FdMaskInit := '*.EXE';
  Inst := GetModuleHandleA(0);
  SysFont := GetStockObject(SYSTEM_FIXED_FONT);
  RegCls('PASDBG', LongInt(@ClientProc), 0, 16);
  RegCls('DBGPANE', LongInt(@PaneProc), CS_DBLCLKS, 0);
  RegCls('NPFILE', LongInt(@FileProc), 0, 16);
  RegCls('DBGINPUT', LongInt(@InputProc), 0, 16);
  Sw := GetSystemMetrics(0); Sh := GetSystemMetrics(1);
  W := MinL(1000, Sw); H := MinL(700, Sh - 30);
  Frame := CreateWindowExA(0, Z('PASDBG'), Z2('Pasdows Debugger'), WS_OVERLAPPEDWINDOW,
                           (Sw - W) Div 2, MaxL(0, (Sh - H - 30) Div 2), W, H, 0, 0, Inst, 0);
  Client := Frame;
  BuildMenu;
  CreateChildren;
  Dummy := ShowWindow(Frame, 1);
  Layout;
  SetStatus(L2('Fichier > Ouvrir un programme (Ctrl+O) pour d'#130'boguer un programme Win32.',
               'File > Open program (Ctrl+O) to debug a Win32 program.'));
  UpdateButtons;
  Dummy := SetTimer(Client, 1, 100, 0);
  Arg := '';
  If ParamCount >= 1 Then
  Begin
    Arg := ParamStr(1);
    If (Arg <> '') And (Arg[1] = '"') Then Arg := Copy(Arg, 2, Length(Arg) - 2);
    If (Pos(':', Arg) = 0) And (Arg <> '') And (Arg[1] <> '\') Then Arg := CurDir + Arg;
    If (Pos('.', BaseName(Arg)) = 0) Then Arg := Arg + '.EXE';
    For I := 2 To ParamCount Do
    Begin
      If ExeArgs <> '' Then ExeArgs := ExeArgs + ' ';
      ExeArgs := ExeArgs + ParamStr(I);
    End;
    ExePath := Arg;
    StartDebug;
  End;
  Dummy := SetActiveWindow(Frame);
  Dummy := SetFocus(PaneH[ActPane]);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  KillDebuggee;
  Dummy := DestroyWindow(Frame);
END.
