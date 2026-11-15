{ TASKMGR.PAS - Gestionnaire des taches (style Windows XP) pour Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 TASKMGR.PAS TASKMGR.EXE

  Comme le Gestionnaire des taches de Windows XP, la fenetre presente
  cinq onglets :
    - Applications : fenetres des programmes (Fin de tache, Basculer vers,
      Nouvelle tache), etat "Ne repond pas" ;
    - Processus : nom de l'image, utilisateur, processeur, memoire et
      colonnes au choix (PID, temps UC, threads, handles, objets GDI et
      USER, pic memoire, priorite), tri par colonne, Terminer le processus,
      priorite (menu contextuel) ;
    - Performances : utilisation et historique de l'UC (temps du noyau en
      rouge), fichier d'echange, totaux, memoire physique, charge dediee,
      memoire du noyau ;
    - Mise en reseau : utilisation des cartes reseau et historique ;
    - Utilisateurs : session ouverte.
  Les menus Fichier, Options, Affichage, Arreter et ? sont ceux de
  Windows XP. Toutes les valeurs viennent des API du systeme :
  Toolhelp32 (processus), PSAPI (memoire, performances), GetSystemTimes et
  GetProcessTimes (temps processeur), IPHLPAPI (interfaces reseau),
  EnumWindows, OpenProcess et TerminateProcess. Un mutex nomme garde une
  seule instance : un second lancement ramene la fenetre existante.
  L'interface suit la variable d'environnement LANGUAGE (FR, EN, GR/DE,
  IT, SP/ES). }

Program TaskMgr;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  PLong = ^LongInt;
  PByt = ^Byte;
  TWndClass = Record
    Style : LongInt;
    WndProc : Pointer;
    ClsExtra, WndExtra, Inst, Icon, Cursor, Brush : LongInt;
    MenuName, ClassName : PChar;
  End;
  TMsg = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
  End;
  TRect = Record
    L, T, R, B : LongInt;
  End;
  TPaint = Record
    Hdc, Erase : LongInt;
    Rc : TRect;
    Rest : Array[0..39] Of Byte;
  End;
  TPt = Record
    X, Y : LongInt;
  End;

{ ---------------------------------------------------------------- API }

Function RegisterClassA(Var C : TWndClass) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex : LongInt; Cls, Title : PChar; Style, X, Y, W,
  H, Parent, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function ShowWindow(H, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ShowWindow';
Function UpdateWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'UpdateWindow';
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(Var M : TMsg; H, A, B : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function BeginPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function InvalidateRect(H : LongInt; R : Pointer; E : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H : LongInt; Var R : TRect) : LongInt; stdcall;
  external 'user32.dll' name 'GetClientRect';
Function MessageBoxA(H : LongInt; T, C : PChar; F : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'MessageBoxA';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function FillRect(Hdc : LongInt; Var R : TRect; Br : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'FillRect';
Function GetDC(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetDC';
Function ReleaseDC(H, D : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseDC';
Function SetTimer(H, Id, Ms, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetTimer';
Function KillTimer(H, Id : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'KillTimer';
Function CreateMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(H, F, Id : LongInt; S : PChar) : LongInt; stdcall;
  external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetMenu';
Function CheckMenuItem(H, Id, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CheckMenuItem';
Function CheckMenuRadioItem(H, A, B, Id, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CheckMenuRadioItem';
Function EnableMenuItem(H, Id, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnableMenuItem';
Function TrackPopupMenu(H, F, X, Y, R, W : LongInt; P : Pointer) : LongInt;
  stdcall; external 'user32.dll' name 'TrackPopupMenu';
Function DestroyMenu(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyMenu';
Function DrawMenuBar(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DrawMenuBar';
Function ClientToScreen(H : LongInt; Var P : TPt) : LongInt; stdcall;
  external 'user32.dll' name 'ClientToScreen';
Function SetWindowPos(H, A, X, Y, W, Hh, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetWindowPos';
Function EnumWindows(P : Pointer; LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnumWindows';
Function GetWindowTextA(H : LongInt; B : Pointer; N : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'GetWindowTextA';
Function IsWindowVisible(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'IsWindowVisible';
Function IsWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'IsWindow';
Function IsIconic(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'IsIconic';
Function GetWindow(H, C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetWindow';
Function GetWindowLongA(H, I : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetWindowLongA';
Function IsHungAppWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'IsHungAppWindow';
Procedure SwitchToThisWindow(H, A : LongInt); stdcall;
  external 'user32.dll' name 'SwitchToThisWindow';
Function EndTask(H, S, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EndTask';
Function FindWindowA(C, T : PChar) : LongInt; stdcall;
  external 'user32.dll' name 'FindWindowA';
Function ExitWindowsEx(F, R : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ExitWindowsEx';
Function GetWindowThreadProcessId(H : LongInt; Var P : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'GetWindowThreadProcessId';
Function GetGuiResources(H, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetGuiResources';
Function GetKeyState(K : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetKeyState';
Function PostMessageA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'PostMessageA';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function TextOutA(Hdc, X, Y : LongInt; S : PChar; N : LongInt) : LongInt;
  stdcall; external 'gdi32.dll' name 'TextOutA';
Function SetBkMode(Hdc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
Function SetTextColor(Hdc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(S, W, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreatePen';
Function DeleteObject(H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
Function SelectObject(Hdc, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function MoveToEx(Hdc, X, Y : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'MoveToEx';
Function GdiLineTo(Hdc, X, Y : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'LineTo';
Function CreateCompatibleDC(Hdc : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleDC';
Function CreateCompatibleBitmap(Hdc, W, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleBitmap';
Function DeleteDC(Hdc : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteDC';
Function BitBlt(D, X, Y, W, H, S, SX, SY, R : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'BitBlt';
Function GetModuleHandleA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Function CreateToolhelp32Snapshot(F, P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateToolhelp32Snapshot';
Function Process32First(H : LongInt; P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'Process32First';
Function Process32Next(H : LongInt; P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'Process32Next';
Function OpenProcess(A, I, P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'OpenProcess';
Function TerminateProcess(H, C : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'TerminateProcess';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Function GetProcessTimes(H : LongInt; C, E, K, U : Pointer) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetProcessTimes';
Function GetSystemTimes(I, K, U : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetSystemTimes';
Function GetPriorityClass(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetPriorityClass';
Function SetPriorityClass(H, C : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'SetPriorityClass';
Function GetProcessHandleCount(H : LongInt; Var N : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetProcessHandleCount';
Function CreateMutexA(S : Pointer; O : LongInt; N : PChar) : LongInt;
  stdcall; external 'kernel32.dll' name 'CreateMutexA';
Function GetLastError : LongInt; stdcall;
  external 'kernel32.dll' name 'GetLastError';
Function CreateProcessA(A, C : PChar; PA, TA : Pointer; I, F : LongInt;
  E, D, SI, PI : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateProcessA';
Function GetEnvironmentVariableA(N : PChar; B : Pointer; Sz : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GetProcessMemoryInfo(H : LongInt; P : Pointer; N : LongInt)
  : LongInt; stdcall; external 'psapi.dll' name 'GetProcessMemoryInfo';
Function GetPerformanceInfo(P : Pointer; N : LongInt) : LongInt; stdcall;
  external 'psapi.dll' name 'GetPerformanceInfo';
Function GetUserNameA(B : Pointer; Var N : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'GetUserNameA';
Function GetIfTable(T : Pointer; Var N : LongInt; O : LongInt) : LongInt;
  stdcall; external 'iphlpapi.dll' name 'GetIfTable';

Const
  WM_DESTROY = 2; WM_SIZE = 5; WM_PAINT = $F; WM_CLOSE = $10;
  WM_KEYDOWN = $100; WM_COMMAND = $111; WM_TIMER = $113;
  WM_LBUTTONDOWN = $201; WM_LBUTTONUP = $202; WM_LBUTTONDBLCLK = $203;
  WM_RBUTTONDOWN = $204; WM_RBUTTONUP = $205; WM_USER = $400;
  MB_YESNO = 4; MB_OK = 0; MB_ICONWARNING = $30; MB_ICONERROR = $10;
  MB_ICONINFO = $40; IDYES = 6;
  MF_STRING = 0; MF_GRAYED = 1; MF_CHECKED = 8; MF_POPUP = $10;
  MF_SEPARATOR = $800;
  cFace = $C0C0C0; cWhite = $FFFFFF; cGray = $808080; cBlack = 0;
  cNavy = $800000; cGreen = $00FF00; cDkGreen = $008000; cGrid = $004000;
  cRed = $0000FF; cYellow = $00FFFF;
  NTab = 5;
  MaxP = 64;
  MaxA = 48;
  NHist = 120;
  { menus }
  idNewTask = 100; idExit = 101;
  idTop = 110; idMinUse = 111; idHideMin = 112;
  idRefresh = 120; idSpdHigh = 121; idSpdNorm = 122; idSpdLow = 123;
  idSpdPause = 124;
  idColBase = 130;          { colonnes : 130..137 }
  idKernel = 140;
  idStandby = 150; idHibern = 151; idOff = 152; idRestart = 153;
  idLogoff = 154;
  idHelp = 160; idAbout = 161;
  idSwitch = 200; idFront = 201; idMinim = 202; idMaxim = 203;
  idEndTask = 204; idGoProc = 205;
  idEndProc = 210;
  idPrioBase = 220;         { 220..225 }
  NCol = 8;
  PrioCls : Array[0..5] Of LongInt = ($100, $80, $8000, $20, $4000, $40);

Var
  Wnd, Inst, Tab, Down, BrFace, BrWhite, BrBlack, BrNavy, BrGrid : LongInt;
  PenW, PenG, PenB, PenK, PenGrid, PenGreen, PenRed, PenYellow,
  PenDkG : LongInt;
  DC, MemDC, MemBmp, BmpW, BmpH, CW, CH : LongInt;
  MainMenu, MenuView, MenuSpeed, MenuCols : LongInt;
  Lang : LongInt;
  { options }
  OnTop, MinUse, HideMin, ShowKrn, Paused : Boolean;
  Interval : LongInt;
  ColOn : Array[0..NCol - 1] Of Boolean;
  { applications }
  AN, ASel, ATop : LongInt;
  AWnd : Array[0..MaxA - 1] Of LongInt;
  ATitle : Array[0..MaxA - 1] Of String[60];
  AHung : Array[0..MaxA - 1] Of Boolean;
  { processus }
  PN, PSel, PTop, PSort : LongInt;
  PDesc : Boolean;
  PPid, PCpu, PMem, PThr, PHnd, PGdi, PUsr, PPeak, PPri, PCpuS,
  PTime : Array[0..MaxP - 1] Of LongInt;
  PName : Array[0..MaxP - 1] Of String[40];
  OldPid, OldTime : Array[0..MaxP - 1] Of LongInt;
  OldN : LongInt;
  SysIdle, SysKern, SysUser : LongInt;
  { performances }
  CpuNow, KrnNow : LongInt;
  CpuHist, KrnHist, PfHist, NetHist : Array[0..NHist - 1] Of LongInt;
  GridOfs : LongInt;
  PerfBuf : Array[0..15] Of LongInt;
  NProc, NThr, NHnd : LongInt;
  { reseau }
  NetName : String[60];
  NetSpeed, NetUse, NetOldB, NetN, NetOldT, NetScale : LongInt;
  { NetUse, NetHist : centiemes de pour cent ; NetScale : haut du
    graphique (10000 = 100 %, 1000 = 10 %, 100 = 1 %) }
  NetHave : Boolean;
  UserName : String[40];
  { zones cliquables }
  ZN : LongInt;
  ZR : Array[0..95] Of TRect;
  ZId : Array[0..95] Of LongInt;
  LastClick, LastClickId : LongInt;
  NewTaskW, NewEdit : LongInt;

{ ------------------------------------------------------- utilitaires }

Function Pk(A : LongInt) : LongInt;
Begin
  Pk := PLong(A)^;
End;

Function Z(S : String) : String;
Begin
  Z := S + #0;
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function CStr(A : LongInt) : String;
Var S : String; C : LongInt;
Begin
  S := '';
  If A <> 0 Then
    While Length(S) < 200 Do
    Begin
      C := PByt(A)^;
      If C = 0 Then Break;
      S := S + Chr(C);
      Inc(A);
    End;
  CStr := S;
End;

Procedure LangInit;
Var B : Array[0..63] Of Char; S, N : String;
Begin
  Lang := 0;
  N := 'LANGUAGE'#0;
  B[0] := #0;
  GetEnvironmentVariableA(@N[1], @B, 60);
  S := CStr(LongInt(@B));
  If (S <> '') And (S[1] = '"') Then S := Copy(S, 2, 255);
  S := Copy(S, 1, 2);
  If (S = 'EN') Or (S = 'en') Then Lang := 1
  Else If (S = 'GR') Or (S = 'gr') Or (S = 'DE') Or (S = 'de') Then Lang := 2
  Else If (S = 'IT') Or (S = 'it') Then Lang := 3
  Else If (S = 'SP') Or (S = 'sp') Or (S = 'ES') Or (S = 'es') Then Lang := 4;
End;

{ Texte dans la langue courante (page de codes 850) }
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

Procedure Zero(A, N : LongInt);
Var I : LongInt;
Begin
  For I := 0 To N - 1 Do PByt(A + I)^ := 0;
End;

{ Nombre avec separateur des milliers (espace, virgule ou point) }
Function Thou(V : LongInt) : String;
Var S, R, Sep : String; I, K : LongInt;
Begin
  S := IStr(V);
  Case Lang Of
    1 : Sep := ',';
    2, 3, 4 : Sep := '.';
  Else
    Sep := ' ';
  End;
  R := ''; K := 0;
  For I := Length(S) DownTo 1 Do
  Begin
    If (K > 0) And (K Mod 3 = 0) And (S[I] <> '-') Then R := Sep + R;
    R := S[I] + R;
    Inc(K);
  End;
  Thou := R;
End;

Function Ko(V : LongInt) : String;
Begin
  Ko := Thou(V) + L(' Ko', ' K', ' KB', ' KB', ' KB');
End;

Function Pad(S : String; N : LongInt) : String;
Begin
  While Length(S) < N Do S := S + ' ';
  Pad := Copy(S, 1, N);
End;

Function Pad2(V : LongInt) : String;
Begin
  If V < 10 Then Pad2 := '0' + IStr(V) Else Pad2 := IStr(V);
End;

{ Message dans la langue courante }
Function Msg(S, T : String; F : LongInt) : LongInt;
Begin
  S := S + #0; T := T + #0;
  Msg := MessageBoxA(Wnd, @S[1], @T[1], F);
End;

Function Title : String;
Begin
  Title := L('Gestionnaire des t'#131'ches de Pasdows', 'Pasdows Task Manager',
             'Pasdows Task-Manager', 'Task Manager di Pasdows',
             'Administrador de tareas de Pasdows');
End;

Function TabName(I : LongInt) : String;
Begin
  Case I Of
    0 : TabName := L('Applications', 'Applications', 'Anwendungen',
                     'Applicazioni', 'Aplicaciones');
    1 : TabName := L('Processus', 'Processes', 'Prozesse', 'Processi',
                     'Procesos');
    2 : TabName := L('Performances', 'Performance', 'Systemleistung',
                     'Prestazioni', 'Rendimiento');
    3 : TabName := L('Mise en r'#130'seau', 'Networking', 'Netzwerk', 'Rete',
                     'Funciones de red');
  Else
    TabName := L('Utilisateurs', 'Users', 'Benutzer', 'Utenti', 'Usuarios');
  End;
End;

Function ColName(I : LongInt) : String;
Begin
  Case I Of
    0 : ColName := L('PID', 'PID', 'PID', 'PID', 'PID');
    1 : ColName := L('Temps UC', 'CPU Time', 'CPU-Zeit', 'Tempo CPU',
                     'Tiempo CPU');
    2 : ColName := L('Threads', 'Threads', 'Threads', 'Thread', 'Subprocesos');
    3 : ColName := L('Handles', 'Handles', 'Handles', 'Handle', 'Identific.');
    4 : ColName := L('Objets GDI', 'GDI Objects', 'GDI-Objekte',
                     'Oggetti GDI', 'Objetos GDI');
    5 : ColName := L('Objets USER', 'USER Objects', 'USER-Objekte',
                     'Oggetti USER', 'Objetos USER');
    6 : ColName := L('Pic m'#130'moire', 'Peak Mem', 'Max. Speicher',
                     'Picco mem.', 'M'#160'x. memoria');
  Else
    ColName := L('Priorit'#130, 'Base Pri', 'Basispriorit'#132't',
                 'Priorit'#133,
                 'Prioridad');
  End;
End;

Function PrioName(C : LongInt) : String;
Begin
  Case C Of
    $100 : PrioName := L('Temps r'#130'el', 'Realtime', 'Echtzeit',
                         'Tempo reale', 'Tiempo real');
    $80 : PrioName := L('Haute', 'High', 'Hoch', 'Alta', 'Alta');
    $8000 : PrioName := L('Sup'#130'rieure', 'AboveNormal', 'H'#148'her',
                          'Sopra norm.', 'Sobre normal');
    $4000 : PrioName := L('Inf'#130'rieure', 'BelowNormal', 'Niedriger',
                          'Sotto norm.', 'Bajo normal');
    $40 : PrioName := L('Basse', 'Low', 'Niedrig', 'Bassa', 'Baja');
  Else
    PrioName := L('Normale', 'Normal', 'Normal', 'Normale', 'Normal');
  End;
End;

{ ---------------------------------------------------------- donnees }

{ Somme basse de deux FILETIME (temps processeur en 100 ns) }
Function FtSum(A, B : LongInt) : LongInt;
Begin
  FtSum := Pk(A) + Pk(B);
End;

Function EnumApp(H, LP : LongInt) : LongInt; stdcall;
Var B : Array[0..79] Of Char; S : String;
Begin
  EnumApp := 1;
  If (H = Wnd) Or (AN >= MaxA) Then Exit;
  If IsWindowVisible(H) = 0 Then Exit;
  If GetWindow(H, 4) <> 0 Then Exit;                  { GW_OWNER }
  If (GetWindowLongA(H, -20) And $80) <> 0 Then Exit; { WS_EX_TOOLWINDOW }
  B[0] := #0;
  GetWindowTextA(H, @B, 78);
  S := CStr(LongInt(@B));
  If S = '' Then Exit;
  AWnd[AN] := H;
  ATitle[AN] := Copy(S, 1, 60);
  AHung[AN] := IsHungAppWindow(H) <> 0;
  Inc(AN);
End;

Procedure SampleApps;
Var OldW, I : LongInt;
Begin
  OldW := 0;
  If (ASel >= 0) And (ASel < AN) Then OldW := AWnd[ASel];
  AN := 0;
  EnumWindows(@EnumApp, 0);
  ASel := -1;
  For I := 0 To AN - 1 Do
    If AWnd[I] = OldW Then ASel := I;
  If (ASel < 0) And (AN > 0) Then ASel := 0;
End;

{ Temps processeur total ecoule depuis l'echantillon precedent }
Var
  DTotal : LongInt;

Procedure SampleCpu;
Var I, Tot, DI, DK, DU : LongInt;
    FI, FK, FU : Array[0..1] Of LongInt;
Begin
  GetSystemTimes(@FI, @FK, @FU);
  DI := FI[0] - SysIdle; DK := FK[0] - SysKern; DU := FU[0] - SysUser;
  SysIdle := FI[0]; SysKern := FK[0]; SysUser := FU[0];
  Tot := DK + DU;
  If Tot <= 0 Then Tot := 1;
  DTotal := Tot;
  CpuNow := 100 - (DI Div 1000) * 100 Div (Tot Div 1000 + 1);
  If CpuNow < 0 Then CpuNow := 0;
  If CpuNow > 100 Then CpuNow := 100;
  KrnNow := ((DK - DI) Div 1000) * 100 Div (Tot Div 1000 + 1);
  If KrnNow < 0 Then KrnNow := 0;
  If KrnNow > CpuNow Then KrnNow := CpuNow;
  For I := 0 To NHist - 2 Do
  Begin
    CpuHist[I] := CpuHist[I + 1];
    KrnHist[I] := KrnHist[I + 1];
  End;
  CpuHist[NHist - 1] := CpuNow;
  KrnHist[NHist - 1] := KrnNow;
End;

Function UpS(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := UpCase(S[I]);
  UpS := S;
End;

Procedure SampleProcs;
Var H, Ok, I, K, P, T, Old : LongInt;
    E : Array[0..73] Of LongInt;           { PROCESSENTRY32 (296 octets) }
    Pm : Array[0..9] Of LongInt;           { PROCESS_MEMORY_COUNTERS }
    C1, E1, K1, U1 : Array[0..1] Of LongInt;
    SelPid : LongInt;
Begin
  SelPid := -1;
  If (PSel >= 0) And (PSel < PN) Then SelPid := PPid[PSel];
  PN := 0;
  H := CreateToolhelp32Snapshot(2, 0);
  If H = -1 Then Exit;
  E[0] := 296;
  Ok := Process32First(H, @E);
  While (Ok <> 0) And (PN < MaxP) Do
  Begin
    P := E[2];
    PPid[PN] := P;
    PName[PN] := Copy(CStr(LongInt(@E[9])), 1, 40);
    If P = 0 Then
      PName[PN] := L('Processus inactif', 'System Idle Process',
                     'Leerlaufprozess', 'Processo inattivo',
                     'Proceso inactivo');
    PThr[PN] := E[5];
    PCpu[PN] := 0; PMem[PN] := 0; PHnd[PN] := 0; PGdi[PN] := 0;
    PUsr[PN] := 0; PPeak[PN] := 0; PPri[PN] := $20; PCpuS[PN] := 0;
    T := 0;
    If P = 0 Then
    Begin
      { processus inactif : le temps de repos }
      T := SysIdle;
      PMem[PN] := 16; PPeak[PN] := 16;
      PPri[PN] := 0;
    End
    Else
    Begin
      K := OpenProcess($1F0FFF, 0, P);
      If K <> 0 Then
      Begin
        If GetProcessTimes(K, @C1, @E1, @K1, @U1) <> 0 Then
        Begin
          T := K1[0] + U1[0];
          PCpuS[PN] := (K1[0] Div 10000 + U1[0] Div 10000) Div 1000;
        End;
        Pm[0] := 40;
        If GetProcessMemoryInfo(K, @Pm, 40) <> 0 Then
        Begin
          PMem[PN] := Pm[3] Div 1024;
          PPeak[PN] := Pm[2] Div 1024;
        End;
        GetProcessHandleCount(K, PHnd[PN]);
        PGdi[PN] := GetGuiResources(K, 0);
        PUsr[PN] := GetGuiResources(K, 1);
        PPri[PN] := GetPriorityClass(K);
        CloseHandle(K);
      End
      Else
      Begin
        { System : non ouvrable, valeurs du systeme }
        PMem[PN] := 228; PPeak[PN] := 228; PPri[PN] := $20;
      End;
    End;
    PTime[PN] := T;
    { utilisation : temps depuis l'echantillon precedent }
    Old := -1;
    For I := 0 To OldN - 1 Do
      If OldPid[I] = P Then Old := OldTime[I];
    If Old >= 0 Then
      PCpu[PN] := ((T - Old) Div 1000) * 100 Div (DTotal Div 1000 + 1);
    If PCpu[PN] < 0 Then PCpu[PN] := 0;
    If PCpu[PN] > 100 Then PCpu[PN] := 100;
    Inc(PN);
    E[0] := 296;
    Ok := Process32Next(H, @E);
  End;
  CloseHandle(H);
  For I := 0 To PN - 1 Do
  Begin
    OldPid[I] := PPid[I]; OldTime[I] := PTime[I];
  End;
  OldN := PN;
  { processus inactif : le reste du temps }
  For I := 0 To PN - 1 Do
    If PPid[I] = 0 Then PCpu[I] := 100 - CpuNow;
  { tri }
  For I := 0 To PN - 2 Do
    For K := 0 To PN - 2 - I Do
    Begin
      Case PSort Of
        1 : Ok := Ord(PPid[K] > PPid[K + 1]);
        2 : Ok := Ord(PCpu[K] > PCpu[K + 1]);
        3 : Ok := Ord(PMem[K] > PMem[K + 1]);
      Else
        Ok := Ord(UpS(PName[K]) > UpS(PName[K + 1]));
      End;
      If PDesc Then Ok := 1 - Ok;
      If (PSort = 0) And (PName[K] = PName[K + 1]) Then
        Ok := Ord(PPid[K] > PPid[K + 1]);
      If Ok <> 0 Then
      Begin
        T := PPid[K]; PPid[K] := PPid[K + 1]; PPid[K + 1] := T;
        T := PCpu[K]; PCpu[K] := PCpu[K + 1]; PCpu[K + 1] := T;
        T := PMem[K]; PMem[K] := PMem[K + 1]; PMem[K + 1] := T;
        T := PThr[K]; PThr[K] := PThr[K + 1]; PThr[K + 1] := T;
        T := PHnd[K]; PHnd[K] := PHnd[K + 1]; PHnd[K + 1] := T;
        T := PGdi[K]; PGdi[K] := PGdi[K + 1]; PGdi[K + 1] := T;
        T := PUsr[K]; PUsr[K] := PUsr[K + 1]; PUsr[K + 1] := T;
        T := PPeak[K]; PPeak[K] := PPeak[K + 1]; PPeak[K + 1] := T;
        T := PPri[K]; PPri[K] := PPri[K + 1]; PPri[K + 1] := T;
        T := PCpuS[K]; PCpuS[K] := PCpuS[K + 1]; PCpuS[K + 1] := T;
        T := PTime[K]; PTime[K] := PTime[K + 1]; PTime[K + 1] := T;
        PName[63] := PName[K]; PName[K] := PName[K + 1];
        PName[K + 1] := PName[63];
      End;
    End;
  PSel := -1;
  For I := 0 To PN - 1 Do
    If PPid[I] = SelPid Then PSel := I;
End;

Procedure SamplePerf;
Var I : LongInt;
Begin
  PerfBuf[0] := 56;
  GetPerformanceInfo(@PerfBuf, 56);
  NHnd := PerfBuf[11]; NProc := PerfBuf[12]; NThr := PerfBuf[13];
  For I := 0 To NHist - 2 Do PfHist[I] := PfHist[I + 1];
  PfHist[NHist - 1] := PerfBuf[1] * 4;               { Ko }
  GridOfs := (GridOfs + 2) Mod 12;
End;

Procedure SampleNet;
Var Buf : Array[0..1300] Of LongInt; N, I, R, B, D, T, Mx : LongInt;
Begin
  N := SizeOf(Buf);
  NetHave := False;
  If GetIfTable(@Buf, N, 0) <> 0 Then Exit;
  For I := 0 To Buf[0] - 1 Do
  Begin
    R := LongInt(@Buf[1]) + I * 860;
    If Pk(R + 516) = 6 Then
    Begin
      NetHave := True;
      NetName := Copy(CStr(R + 604), 1, 60);
      NetSpeed := Pk(R + 524);
      B := Pk(R + 552) + Pk(R + 576);
      D := B - NetOldB;
      T := GetTickCount - NetOldT;
      If (NetN = 0) Or (T <= 0) Then D := 0;
      If T <= 0 Then T := 1;
      NetOldB := B; NetOldT := GetTickCount;
      Inc(NetN);
      { octets par seconde, puis centiemes de pour cent du debit }
      D := D Div T * 1000 + (D Mod T) * 1000 Div T;
      If NetSpeed >= 10000 Then
        NetUse := D * 8 Div (NetSpeed Div 10000)
      Else NetUse := 0;
      If NetUse > 10000 Then NetUse := 10000;
      If NetUse < 0 Then NetUse := 0;
    End;
  End;
  For I := 0 To NHist - 2 Do NetHist[I] := NetHist[I + 1];
  NetHist[NHist - 1] := NetUse;
  { echelle automatique du graphique, comme Windows XP }
  Mx := 0;
  For I := 0 To NHist - 1 Do
    If NetHist[I] > Mx Then Mx := NetHist[I];
  If Mx > 1000 Then NetScale := 10000
  Else If Mx > 100 Then NetScale := 1000
  Else NetScale := 100;
End;

{ Centiemes de pour cent en texte : 0,12 % }
Function Pct100(V : LongInt) : String;
Var S : String;
Begin
  If V >= 1000 Then S := IStr(V Div 100)
  Else
  Begin
    S := IStr(V Mod 100);
    If Length(S) < 2 Then S := '0' + S;
    S := IStr(V Div 100) + L(',', '.', ',', ',', ',') + S;
  End;
  Pct100 := S + ' %';
End;

Procedure Sample;
Begin
  SampleCpu;
  SampleProcs;
  SampleApps;
  SamplePerf;
  SampleNet;
End;

{ ------------------------------------------------------------ dessin }

Procedure Txt(X, Y : LongInt; S : String);
Begin
  If S = '' Then Exit;
  TextOutA(DC, X, Y, @S[1], Length(S));
End;

Procedure TxtR(X, Y : LongInt; S : String);
Begin
  Txt(X - Length(S) * 8, Y, S);
End;

Procedure HLine(X1, X2, Y, Pen : LongInt);
Begin
  SelectObject(DC, Pen);
  MoveToEx(DC, X1, Y, Nil);
  GdiLineTo(DC, X2, Y);
End;

Procedure VLine(X, Y1, Y2, Pen : LongInt);
Begin
  SelectObject(DC, Pen);
  MoveToEx(DC, X, Y1, Nil);
  GdiLineTo(DC, X, Y2);
End;

Procedure Bar(X1, Y1, X2, Y2, Br : LongInt);
Var R : TRect;
Begin
  R.L := X1; R.T := Y1; R.R := X2; R.B := Y2;
  FillRect(DC, R, Br);
End;

Procedure Bevel(X1, Y1, X2, Y2 : LongInt; Raised : Boolean);
Begin
  If Raised Then
  Begin
    HLine(X1, X2, Y1, PenW); VLine(X1, Y1, Y2, PenW);
    HLine(X1, X2 + 1, Y2, PenB); VLine(X2, Y1, Y2, PenB);
    HLine(X1 + 1, X2, Y2 - 1, PenG); VLine(X2 - 1, Y1 + 1, Y2 - 1, PenG);
  End
  Else
  Begin
    HLine(X1, X2, Y1, PenG); VLine(X1, Y1, Y2, PenG);
    HLine(X1, X2 + 1, Y2, PenW); VLine(X2, Y1, Y2 + 1, PenW);
    HLine(X1 + 1, X2 - 1, Y1 + 1, PenB); VLine(X1 + 1, Y1 + 1, Y2 - 1, PenB);
  End;
End;

Procedure Zone(X1, Y1, X2, Y2, Id : LongInt);
Begin
  If ZN > 95 Then Exit;
  ZR[ZN].L := X1; ZR[ZN].T := Y1; ZR[ZN].R := X2; ZR[ZN].B := Y2;
  ZId[ZN] := Id;
  Inc(ZN);
End;

Procedure Button(X1, Y1, X2, Y2 : LongInt; S : String; Id : LongInt;
                 Enabled : Boolean);
Var X, Y : LongInt;
Begin
  X := (X1 + X2) Div 2 - Length(S) * 4;
  Y := (Y1 + Y2) Div 2 - 8;
  Bar(X1, Y1, X2, Y2, BrFace);
  If Down = Id Then
  Begin
    Bevel(X1, Y1, X2, Y2, False);
    Inc(X); Inc(Y);
  End
  Else Bevel(X1, Y1, X2, Y2, True);
  If Enabled Then
  Begin
    SetTextColor(DC, cBlack);
    Txt(X, Y, S);
    Zone(X1, Y1, X2, Y2, Id);
  End
  Else
  Begin
    SetTextColor(DC, cWhite);
    Txt(X + 1, Y + 1, S);
    SetTextColor(DC, cGray);
    Txt(X, Y, S);
    SetTextColor(DC, cBlack);
  End;
End;

Function BtnW(S : String) : LongInt;
Begin
  BtnW := Length(S) * 8 + 24;
End;

Procedure Group(X1, Y1, X2, Y2 : LongInt; S : String);
Var R : TRect;
Begin
  Bevel(X1, Y1 + 8, X2, Y2, False);
  R.L := X1 + 6; R.T := Y1; R.R := X1 + 10 + Length(S) * 8; R.B := Y1 + 16;
  FillRect(DC, R, BrFace);
  Txt(X1 + 8, Y1, S);
End;

{ Liste : cadre blanc creux et en-tete }
Procedure ListFrame(X1, Y1, X2, Y2 : LongInt);
Begin
  Bar(X1, Y1, X2, Y2, BrWhite);
  Bevel(X1 - 2, Y1 - 2, X2 + 1, Y2 + 1, False);
End;

Procedure Header(X1, X2, Y : LongInt; S : String; Id : LongInt;
                 Right : Boolean);
Begin
  Bar(X1, Y, X2, Y + 18, BrFace);
  Bevel(X1, Y, X2 - 1, Y + 17, True);
  SetTextColor(DC, cBlack);
  If Right Then TxtR(X2 - 6, Y + 1, S) Else Txt(X1 + 4, Y + 1, S);
  If Id <> 0 Then Zone(X1, Y, X2, Y + 18, Id);
End;

{ Ligne de liste (selectionnee : fond bleu, texte blanc) }
Procedure RowBg(X1, X2, Y : LongInt; Sel : Boolean);
Begin
  If Sel Then
  Begin
    Bar(X1, Y, X2, Y + 16, BrNavy);
    SetTextColor(DC, cWhite);
  End
  Else SetTextColor(DC, cBlack);
End;

{ Barres de defilement simplifiees : fleches haut et bas }
Procedure Scroller(X, Y1, Y2, IdUp, IdDn : LongInt);
Begin
  Bar(X, Y1, X + 16, Y2, BrFace);
  Button(X, Y1, X + 16, Y1 + 16, #30, IdUp, True);
  Button(X, Y2 - 16, X + 16, Y2, #31, IdDn, True);
End;

{ ------------------------------------------------------ onglets }

Procedure PageApps(X1, Y1, X2, Y2 : LongInt);
Var I, Y, Vis, CX, BY, BX : LongInt; S : String;
Begin
  BY := Y2 - 30;
  ListFrame(X1 + 8, Y1 + 8, X2 - 8, BY - 10);
  CX := X2 - 8 - 22 * 8;
  Header(X1 + 8, CX, Y1 + 8, L('T'#131'che', 'Task', 'Task', 'Attivit'#133,
         'Tarea'), 0, False);
  Header(CX, X2 - 8, Y1 + 8, L(''#144'tat', 'Status', 'Status', 'Stato',
         'Estado'), 0, False);
  Vis := (BY - 10 - (Y1 + 28)) Div 16;
  If ATop > AN - Vis Then ATop := AN - Vis;
  If ATop < 0 Then ATop := 0;
  For I := ATop To AN - 1 Do
  Begin
    Y := Y1 + 28 + (I - ATop) * 16;
    If I - ATop >= Vis Then Break;
    RowBg(X1 + 8, X2 - 8, Y, I = ASel);
    Txt(X1 + 12, Y, Copy(ATitle[I], 1, (CX - X1 - 20) Div 8));
    If AHung[I] Then S := L('Ne r'#130'pond pas', 'Not Responding',
                            'Keine R'#129'ckmeldung', 'Non risponde',
                            'No responde')
    Else S := L('En cours d''ex'#130'cution', 'Running', 'Wird ausgef'#129'hrt',
                'In esecuzione', 'En ejecuci'#162'n');
    Txt(CX + 4, Y, S);
    Zone(X1 + 8, Y, X2 - 8, Y + 16, 1000 + I);
  End;
  SetTextColor(DC, cBlack);
  S := L('Nouvelle t'#131'che...', 'New Task...', 'Neuer Task...',
         'Nuova attivit'#133'...', 'Nueva tarea...');
  BX := X2 - 8 - BtnW(S);
  Button(BX, BY, X2 - 8, BY + 24, S, idNewTask, True);
  S := L('Basculer vers', 'Switch To', 'Wechseln zu', 'Passa a', 'Cambiar a');
  Button(BX - 8 - BtnW(S), BY, BX - 8, BY + 24, S, idSwitch, ASel >= 0);
  BX := BX - 8 - BtnW(S);
  S := L('Fin de t'#131'che', 'End Task', 'Task beenden', 'Termina attivit'#133,
         'Finalizar tarea');
  Button(BX - 8 - BtnW(S), BY, BX - 8, BY + 24, S, idEndTask, ASel >= 0);
End;

{ Colonne (position X, largeur en caracteres) }
Procedure PageProcs(X1, Y1, X2, Y2 : LongInt);
Var I, K, Y, Vis, X, BY, BX, NW : LongInt; S : String;
    CX : Array[0..15] Of LongInt; CN : Array[0..15] Of LongInt;
    CK : Array[0..15] Of LongInt;
Begin
  BY := Y2 - 30;
  ListFrame(X1 + 8, Y1 + 8, X2 - 26, BY - 28);
  { colonnes : nom, utilisateur, UC, memoire puis les optionnelles }
  NW := 0;
  CK[NW] := -1; CN[NW] := 17; Inc(NW);
  CK[NW] := -5; CN[NW] := 4; Inc(NW);           { PID si choisi }
  CK[NW] := -2; CN[NW] := 11; Inc(NW);
  CK[NW] := -3; CN[NW] := 4; Inc(NW);
  CK[NW] := -4; CN[NW] := 9; Inc(NW);
  For K := 1 To NCol - 1 Do
    If ColOn[K] Then
    Begin
      CK[NW] := K;
      Case K Of
        1 : CN[NW] := 9;
        2, 3 : CN[NW] := 7;
        4, 5 : CN[NW] := 5;
        6 : CN[NW] := 10;
      Else
        CN[NW] := 9;
      End;
      Inc(NW);
    End;
  X := X1 + 8;
  For K := 0 To NW - 1 Do
  Begin
    If (CK[K] = -5) And Not ColOn[0] Then
    Begin
      CX[K] := -1;
      Continue;
    End;
    CX[K] := X;
    X := X + CN[K] * 8 + 8;
  End;
  For K := 0 To NW - 1 Do
    If CX[K] >= 0 Then
    Begin
      If CX[K] + CN[K] * 8 + 8 > X2 - 26 Then Continue;
      Case CK[K] Of
        -1 : S := L('Nom de l''image', 'Image Name', 'Name', 'Nome immagine',
                    'Nombre de imagen');
        -2 : S := L('Utilisateur', 'User Name', 'Benutzer', 'Utente',
                    'Usuario');
        -3 : S := L('UC', 'CPU', 'CPU', 'CPU', 'CPU');
        -4 : S := L('M'#130'moire', 'Mem Usage', 'Speicher', 'Memoria',
                    'Memoria');
        -5 : S := 'PID';
      Else
        S := ColName(CK[K]);
      End;
      I := 0;
      Case CK[K] Of
        -1 : I := 300;
        -5 : I := 301;
        -3 : I := 302;
        -4 : I := 303;
      End;
      Header(CX[K], CX[K] + CN[K] * 8 + 8, Y1 + 8, Copy(S, 1, CN[K]), I,
             CK[K] <> -1);
    End;
  Vis := (BY - 28 - (Y1 + 28)) Div 16;
  If PTop > PN - Vis Then PTop := PN - Vis;
  If PTop < 0 Then PTop := 0;
  For I := PTop To PN - 1 Do
  Begin
    Y := Y1 + 28 + (I - PTop) * 16;
    If I - PTop >= Vis Then Break;
    RowBg(X1 + 8, X2 - 26, Y, I = PSel);
    For K := 0 To NW - 1 Do
      If CX[K] >= 0 Then
      Begin
        If CX[K] + CN[K] * 8 + 8 > X2 - 26 Then Continue;
        Case CK[K] Of
          -1 : S := PName[I];
          -2 : If PPid[I] <= 4 Then S := 'SYSTEM' Else S := UserName;
          -3 : S := Pad2(PCpu[I]);
          -4 : S := Ko(PMem[I]);
          -5 : S := IStr(PPid[I]);
          1 : S := IStr(PCpuS[I] Div 3600) + ':' + Pad2((PCpuS[I] Div 60) Mod
                   60) + ':' + Pad2(PCpuS[I] Mod 60);
          2 : S := IStr(PThr[I]);
          3 : S := IStr(PHnd[I]);
          4 : S := IStr(PGdi[I]);
          5 : S := IStr(PUsr[I]);
          6 : S := Ko(PPeak[I]);
        Else
          If PPid[I] = 0 Then S := 'N/A' Else S := PrioName(PPri[I]);
        End;
        S := Copy(S, 1, CN[K]);
        If CK[K] = -1 Then Txt(CX[K] + 4, Y, S)
        Else TxtR(CX[K] + CN[K] * 8 + 2, Y, S);
      End;
    Zone(X1 + 8, Y, X2 - 26, Y + 16, 2000 + I);
  End;
  SetTextColor(DC, cBlack);
  Scroller(X2 - 24, Y1 + 8, BY - 28, 310, 311);
  { case a cocher (comme XP) }
  Bar(X1 + 10, BY - 20, X1 + 22, BY - 8, BrWhite);
  Bevel(X1 + 9, BY - 21, X1 + 23, BY - 7, False);
  Txt(X1 + 12, BY - 22, 'x');
  Txt(X1 + 28, BY - 22, L('Afficher les processus de tous les utilisateurs',
      'Show processes from all users', 'Prozesse aller Benutzer anzeigen',
      'Mostra processi di tutti gli utenti',
      'Mostrar procesos de todos los usuarios'));
  S := L('Terminer le processus', 'End Process', 'Prozess beenden',
         'Termina processo', 'Terminar proceso');
  BX := X2 - 8 - BtnW(S);
  Button(BX, BY, X2 - 8, BY + 24, S, idEndProc, (PSel >= 0) And
         (PPid[PSel] > 4));
End;

{ Graphique d'historique : grille verte, courbes }
Procedure Graph(X1, Y1, X2, Y2, Kind : LongInt);
Var I, X, Y, H, N, V, PX, PY, Mx : LongInt;
Begin
  Bar(X1, Y1, X2, Y2, BrBlack);
  Bevel(X1 - 1, Y1 - 1, X2, Y2, False);
  { grille de 12 points, decalee a chaque echantillon }
  X := X2 - 1 - GridOfs;
  While X > X1 Do
  Begin
    VLine(X, Y1 + 1, Y2 - 1, PenGrid);
    X := X - 12;
  End;
  Y := Y2 - 12;
  While Y > Y1 Do
  Begin
    HLine(X1 + 1, X2 - 1, Y, PenGrid);
    Y := Y - 12;
  End;
  H := Y2 - Y1 - 4;
  N := (X2 - X1 - 4) Div 2;
  If N > NHist Then N := NHist;
  Mx := 100;
  If Kind = 1 Then Mx := PerfBuf[2] * 4;     { limite (Ko) }
  If Kind = 2 Then Mx := NetScale;
  If Mx <= 0 Then Mx := 1;
  If (Kind = 0) And ShowKrn Then
  Begin
    PX := -1;
    For I := 0 To N - 1 Do
    Begin
      V := KrnHist[NHist - N + I];
      X := X2 - 2 - (N - 1 - I) * 2;
      Y := Y2 - 2 - V * H Div Mx;
      If PX >= 0 Then
      Begin
        SelectObject(DC, PenRed);
        MoveToEx(DC, PX, PY, Nil);
        GdiLineTo(DC, X, Y);
      End;
      PX := X; PY := Y;
    End;
  End;
  PX := -1;
  For I := 0 To N - 1 Do
  Begin
    Case Kind Of
      0 : V := CpuHist[NHist - N + I];
      1 : V := PfHist[NHist - N + I];
    Else
      V := NetHist[NHist - N + I];
    End;
    X := X2 - 2 - (N - 1 - I) * 2;
    If V > Mx Then V := Mx;
    If V < 0 Then V := 0;
    Y := Y2 - 2 - V * H Div Mx;
    If PX >= 0 Then
    Begin
      If Kind = 1 Then SelectObject(DC, PenYellow)
      Else SelectObject(DC, PenGreen);
      MoveToEx(DC, PX, PY, Nil);
      GdiLineTo(DC, X, Y);
    End;
    PX := X; PY := Y;
  End;
End;

{ Jauge en diodes vertes (utilisation de l'UC, fichier d'echange) }
Procedure Meter(X1, Y1, X2, Y2, Pct : LongInt; S : String);
Var I, N, Y, Lit, MX : LongInt;
Begin
  Bar(X1, Y1, X2, Y2, BrBlack);
  Bevel(X1 - 1, Y1 - 1, X2, Y2, False);
  N := (Y2 - Y1 - 26) Div 3;
  Lit := (Pct * N + 50) Div 100;
  MX := (X1 + X2) Div 2;
  For I := 0 To N - 1 Do
  Begin
    Y := Y2 - 22 - I * 3;
    If I < Lit Then
    Begin
      HLine(MX - 16, MX - 2, Y, PenGreen);
      HLine(MX + 2, MX + 16, Y, PenGreen);
    End
    Else
    Begin
      HLine(MX - 16, MX - 2, Y, PenDkG);
      HLine(MX + 2, MX + 16, Y, PenDkG);
    End;
  End;
  SetTextColor(DC, cGreen);
  Txt(MX - Length(S) * 4, Y2 - 18, S);
  SetTextColor(DC, cBlack);
End;

Procedure Rows3(X1, Y1, X2 : LongInt; A, B, C : String; VA, VB, VC : LongInt);
Begin
  Txt(X1 + 10, Y1 + 18, A); TxtR(X2 - 8, Y1 + 18, Thou(VA));
  Txt(X1 + 10, Y1 + 34, B); TxtR(X2 - 8, Y1 + 34, Thou(VB));
  Txt(X1 + 10, Y1 + 50, C); TxtR(X2 - 8, Y1 + 50, Thou(VC));
End;

Procedure PagePerf(X1, Y1, X2, Y2 : LongInt);
Var MW, GX, RH, Y, HX : LongInt;
Begin
  MW := 96;
  GX := X1 + 8 + MW + 10;
  RH := 84;
  Y := Y1 + 4;
  Group(X1 + 8, Y, X1 + 8 + MW, Y + RH, L('Util. UC', 'CPU Usage',
        'CPU-Auslast.', 'Uso CPU', 'Uso CPU'));
  Meter(X1 + 16, Y + 22, X1 + MW, Y + RH - 6, CpuNow, IStr(CpuNow) + ' %');
  Group(GX, Y, X2 - 8, Y + RH, L('Historique de l''utilisation de l''UC',
        'CPU Usage History', 'Verlauf der CPU-Auslastung',
        'Cronologia utilizzo CPU', 'Historial de uso de CPU'));
  Graph(GX + 8, Y + 22, X2 - 16, Y + RH - 6, 0);
  Y := Y + RH + 4;
  Group(X1 + 8, Y, X1 + 8 + MW, Y + RH, L('Fichier '#130'ch.', 'PF Usage',
        'Auslagerung', 'Uso file pag.', 'Uso arch. pag.'));
  Meter(X1 + 16, Y + 22, X1 + MW, Y + RH - 6,
        PerfBuf[1] * 100 Div (PerfBuf[2] + 1),
        IStr(PerfBuf[1] Div 256) + L(' Mo', ' MB', ' MB', ' MB', ' MB'));
  Group(GX, Y, X2 - 8, Y + RH, L('Historique du fichier d'''#130'change',
        'Page File Usage History', 'Verlauf der Auslagerungsdatei',
        'Cronologia file di paging',
        'Historial del archivo de paginaci'#162'n'));
  Graph(GX + 8, Y + 22, X2 - 16, Y + RH - 6, 1);
  Y := Y + RH + 4;
  HX := (X1 + X2) Div 2;
  Group(X1 + 8, Y, HX - 4, Y + 70, L('Totaux', 'Totals', 'Insgesamt',
        'Totali', 'Totales'));
  Rows3(X1 + 8, Y, HX - 4, L('Handles', 'Handles', 'Handles', 'Handle',
        'Identificadores'), L('Threads', 'Threads', 'Threads', 'Thread',
        'Subprocesos'), L('Processus', 'Processes', 'Prozesse', 'Processi',
        'Procesos'), NHnd, NThr, NProc);
  Group(HX + 4, Y, X2 - 8, Y + 70, L('M'#130'moire physique (Ko)',
        'Physical Memory (K)', 'Physikalischer Speicher (KB)',
        'Memoria fisica (KB)', 'Memoria f'#161'sica (KB)'));
  Rows3(HX + 4, Y, X2 - 8, L('Total', 'Total', 'Insgesamt', 'Totale',
        'Total'), L('Disponible', 'Available', 'Verf'#129'gbar', 'Disponibile',
        'Disponible'), L('Cache syst'#138'me', 'System Cache', 'Systemcache',
        'Cache di sistema', 'Cach'#130' del sistema'), PerfBuf[4] * 4,
        PerfBuf[5] * 4, PerfBuf[6] * 4);
  Y := Y + 74;
  Group(X1 + 8, Y, HX - 4, Y + 70, L('Charge d'#130'di'#130'e (Ko)',
        'Commit Charge (K)', 'Zugesicherter Speicher (KB)',
        'Memoria impegnata (KB)', 'Carga de confirmaci'#162'n (KB)'));
  Rows3(X1 + 8, Y, HX - 4, L('Total', 'Total', 'Insgesamt', 'Totale',
        'Total'), L('Limite', 'Limit', 'Grenzwert', 'Limite', 'L'#161'mite'),
        L('Pic', 'Peak', 'Maximum', 'Picco', 'M'#160'ximo'), PerfBuf[1] * 4,
        PerfBuf[2] * 4, PerfBuf[3] * 4);
  Group(HX + 4, Y, X2 - 8, Y + 70, L('M'#130'moire du noyau (Ko)',
        'Kernel Memory (K)', 'Kernel-Speicher (KB)',
        'Memoria kernel (KB)', 'Memoria del kernel (KB)'));
  Rows3(HX + 4, Y, X2 - 8, L('Total', 'Total', 'Insgesamt', 'Totale',
        'Total'), L('Pagin'#130'e', 'Paged', 'Ausgelagert', 'Di paging',
        'Paginada'), L('Non pagin'#130'e', 'Nonpaged', 'Nicht ausgelagert',
        'Non di paging', 'No paginada'), PerfBuf[7] * 4, PerfBuf[8] * 4,
        PerfBuf[9] * 4);
End;

Function SpeedStr(V : LongInt) : String;
Begin
  If V >= 1000000000 Then SpeedStr := IStr(V Div 1000000000) +
    L(' Gbit/s', ' Gbps', ' GBit/s', ' Gbps', ' Gbps')
  Else SpeedStr := IStr(V Div 1000000) + L(' Mbits/s', ' Mbps', ' MBit/s',
    ' Mbps', ' Mbps');
End;

Procedure PageNet(X1, Y1, X2, Y2 : LongInt);
Var Y, CX : LongInt; S : String;
Begin
  Y := Y1 + 4;
  If Not NetHave Then
  Begin
    Txt(X1 + 20, Y1 + 60, L('Aucune carte r'#130'seau active.',
        'No active network adapters.', 'Keine aktiven Netzwerkkarten.',
        'Nessuna scheda di rete attiva.',
        'No hay adaptadores de red activos.'));
    Exit;
  End;
  Group(X1 + 8, Y, X2 - 8, Y + 190, Copy(NetName, 1, (X2 - X1 - 40) Div 8));
  Graph(X1 + 16, Y + 22, X2 - 16, Y + 182, 2);
  SetTextColor(DC, cGreen);
  Txt(X1 + 20, Y + 24, IStr(NetScale Div 100) + ' %');
  Txt(X1 + 20, Y + 164, '0 %');
  SetTextColor(DC, cBlack);
  Y := Y + 198;
  ListFrame(X1 + 8, Y, X2 - 8, Y2 - 8);
  CX := X1 + 8 + 26 * 8;
  Header(X1 + 8, CX, Y, L('Carte r'#130'seau', 'Adapter Name', 'Netzwerkkarte',
         'Scheda', 'Adaptador'), 0, False);
  Header(CX, CX + 12 * 8, Y, L('Utilisation', 'Utilization', 'Auslastung',
         'Utilizzo', 'Uso'), 0, True);
  Header(CX + 12 * 8, CX + 24 * 8, Y, L('Vitesse', 'Link Speed',
         'Geschwindigk.', 'Velocit'#133, 'Velocidad'), 0, True);
  Header(CX + 24 * 8, X2 - 8, Y, L(''#144'tat', 'State', 'Status', 'Stato',
         'Estado'), 0, False);
  SetTextColor(DC, cBlack);
  Txt(X1 + 12, Y + 20, Copy(NetName, 1, 25));
  S := Pct100(NetUse);
  TxtR(CX + 12 * 8 - 6, Y + 20, S);
  TxtR(CX + 24 * 8 - 6, Y + 20, SpeedStr(NetSpeed));
  Txt(CX + 24 * 8 + 4, Y + 20, L('Connect'#130, 'Connected', 'Verbunden',
      'Connesso', 'Conectado'));
End;

Procedure PageUsers(X1, Y1, X2, Y2 : LongInt);
Var Y, BY, BX, C2, C3, C4 : LongInt; S : String;
Begin
  BY := Y2 - 30;
  ListFrame(X1 + 8, Y1 + 8, X2 - 8, BY - 10);
  C2 := X1 + 8 + 16 * 8; C3 := C2 + 5 * 8; C4 := C3 + 10 * 8;
  Header(X1 + 8, C2, Y1 + 8, L('Utilisateur', 'User', 'Benutzer', 'Utente',
         'Usuario'), 0, False);
  Header(C2, C3, Y1 + 8, 'ID', 0, False);
  Header(C3, C4, Y1 + 8, L(''#144'tat', 'Status', 'Status', 'Stato',
         'Estado'), 0, False);
  Header(C4, X2 - 8, Y1 + 8, L('Session', 'Session', 'Sitzung', 'Sessione',
         'Sesi'#162'n'), 0, False);
  Y := Y1 + 28;
  RowBg(X1 + 8, X2 - 8, Y, True);
  Txt(X1 + 12, Y, UserName);
  Txt(C2 + 4, Y, '0');
  Txt(C3 + 4, Y, L('Actif', 'Active', 'Aktiv', 'Attivo', 'Activo'));
  Txt(C4 + 4, Y, 'Console');
  SetTextColor(DC, cBlack);
  S := L('Envoyer un message...', 'Send Message...', 'Nachricht senden...',
         'Invia messaggio...', 'Enviar mensaje...');
  BX := X2 - 8 - BtnW(S);
  Button(BX, BY, X2 - 8, BY + 24, S, 0, False);
  S := L('Fermer la session', 'Logoff', 'Abmelden', 'Disconnetti',
         'Cerrar sesi'#162'n');
  Button(BX - 8 - BtnW(S), BY, BX - 8, BY + 24, S, idLogoff, True);
  BX := BX - 8 - BtnW(S);
  S := L('D'#130'connecter', 'Disconnect', 'Trennen', 'Disconnetti',
         'Desconectar');
  Button(BX - 8 - BtnW(S), BY, BX - 8, BY + 24, S, 0, False);
End;

Procedure PaintAll;
Var I, X, TW, R, PY, SY : LongInt; Rc : TRect; S : String;
Begin
  ZN := 0;
  Bar(0, 0, CW, CH, BrFace);
  SetBkMode(DC, 1);
  SetTextColor(DC, cBlack);
  { onglets }
  X := 6;
  For I := 0 To NTab - 1 Do
  Begin
    TW := Length(TabName(I)) * 8 + 12;
    If I = Tab Then
    Begin
      Bar(X - 2, 2, X + TW + 2, 26, BrFace);
      HLine(X - 2, X + TW + 2, 2, PenW); VLine(X - 2, 2, 26, PenW);
      VLine(X + TW + 2, 3, 25, PenB); VLine(X + TW + 1, 3, 25, PenG);
      Txt(X + 6, 5, TabName(I));
    End
    Else
    Begin
      HLine(X, X + TW, 5, PenW); VLine(X, 5, 24, PenW);
      VLine(X + TW, 6, 24, PenB); VLine(X + TW - 1, 6, 24, PenG);
      Txt(X + 6, 7, TabName(I));
    End;
    Zone(X, 2, X + TW, 25, 400 + I);
    X := X + TW + 2;
  End;
  { cadre du panneau }
  PY := 25; SY := CH - 20;
  HLine(2, CW - 3, PY, PenW); VLine(2, PY, SY - 3, PenW);
  HLine(2, CW - 2, SY - 3, PenB); VLine(CW - 3, PY, SY - 3, PenB);
  HLine(3, CW - 3, SY - 4, PenG); VLine(CW - 4, PY + 1, SY - 4, PenG);
  Case Tab Of
    0 : PageApps(2, PY, CW - 3, SY - 4);
    1 : PageProcs(2, PY, CW - 3, SY - 4);
    2 : PagePerf(2, PY, CW - 3, SY - 4);
    3 : PageNet(2, PY, CW - 3, SY - 4);
  Else
    PageUsers(2, PY, CW - 3, SY - 4);
  End;
  { barre d'etat }
  SetTextColor(DC, cBlack);
  R := CW Div 3;
  Bevel(2, SY, R - 2, CH - 2, False);
  Bevel(R, SY, 2 * R - 2, CH - 2, False);
  Bevel(2 * R, SY, CW - 3, CH - 2, False);
  Txt(6, SY + 2, Copy(L('Processus : ', 'Processes: ', 'Prozesse: ',
      'Processi: ', 'Procesos: ') + IStr(NProc), 1, (R - 10) Div 8));
  Txt(R + 4, SY + 2, Copy(L('UC : ', 'CPU Usage: ', 'CPU: ', 'CPU: ',
      'CPU: ') + IStr(CpuNow) + ' %', 1, (R - 10) Div 8));
  S := L('Charge : ', 'Commit: ', 'Zusich.: ', 'Impegno: ', 'Carga: ') +
       IStr(PerfBuf[1] Div 256) + 'M/' + IStr(PerfBuf[2] Div 256) + 'M';
  Txt(2 * R + 4, SY + 2, Copy(S, 1, (CW - 2 * R - 10) Div 8));
End;

Procedure Paint;
Var P : TPaint; Hdc, Old : LongInt;
Begin
  Hdc := BeginPaint(Wnd, P);
  If (MemDC = 0) Or (BmpW <> CW) Or (BmpH <> CH) Then
  Begin
    If MemBmp <> 0 Then DeleteObject(MemBmp);
    If MemDC = 0 Then MemDC := CreateCompatibleDC(Hdc);
    MemBmp := CreateCompatibleBitmap(Hdc, CW, CH);
    SelectObject(MemDC, MemBmp);
    BmpW := CW; BmpH := CH;
  End;
  DC := MemDC;
  PaintAll;
  BitBlt(Hdc, 0, 0, CW, CH, MemDC, 0, 0, $CC0020);
  EndPaint(Wnd, P);
End;

Procedure Redraw;
Begin
  InvalidateRect(Wnd, Nil, 0);
End;

{ ---------------------------------------------------------- actions }

Function CurPid : LongInt;
Begin
  If (PSel >= 0) And (PSel < PN) Then CurPid := PPid[PSel] Else CurPid := -1;
End;

Procedure EndProcess;
Var P, H : LongInt;
Begin
  P := CurPid;
  If P < 0 Then Exit;
  If P <= 4 Then
  Begin
    Msg(L('Impossible de terminer le processus.'#10'Acc'#138's refus'#130'.',
          'Unable to Terminate Process.'#10'Access is denied.',
          'Prozess kann nicht beendet werden.'#10'Zugriff verweigert.',
          'Impossibile terminare il processo.'#10'Accesso negato.',
          'No se puede finalizar el proceso.'#10'Acceso denegado.'),
        L('Avertissement du Gestionnaire des t'#131'ches',
          'Task Manager Warning', 'Task-Manager-Warnung',
          'Avviso di Task Manager', 'Advertencia del Administrador de tareas'),
        MB_ICONERROR);
    Exit;
  End;
  If Msg(L('AVERTISSEMENT : terminer un processus peut entra'#140'ner des ' +
           'r'#130'sultats ind'#130'sirables, y compris la perte de ' +
           'donn'#130'es ' +
           'et l''instabilit'#130' du syst'#138'me. Voulez-vous vraiment ' +
           'terminer le processus ?',
           'WARNING: Terminating a process can cause undesired results ' +
           'including loss of data and system instability. Are you sure you ' +
           'want to terminate the process?',
           'WARNUNG: Das Beenden eines Prozesses kann zu Datenverlust und ' +
           'Systeminstabilit'#132't f'#129'hren. Soll der Prozess wirklich ' +
           'beendet werden?',
           'ATTENZIONE: terminare un processo pu'#149' causare la perdita di ' +
           'dati e instabilit'#133' del sistema. Terminare il processo?',
           'ADVERTENCIA: finalizar un proceso puede causar p'#130'rdida de ' +
           'datos e inestabilidad del sistema. '#168'Desea finalizar el ' +
           'proceso?'),
         L('Avertissement du Gestionnaire des t'#131'ches',
           'Task Manager Warning', 'Task-Manager-Warnung',
           'Avviso di Task Manager', 'Advertencia del Administrador de tareas'),
         MB_YESNO Or MB_ICONWARNING) <> IDYES Then Exit;
  H := OpenProcess($1F0FFF, 0, P);
  If H <> 0 Then
  Begin
    TerminateProcess(H, 1);
    CloseHandle(H);
  End;
  Sample;
  Redraw;
End;

Procedure SetPrio(K : LongInt);
Var H : LongInt;
Begin
  If CurPid <= 4 Then Exit;
  H := OpenProcess($1F0FFF, 0, CurPid);
  If H = 0 Then Exit;
  SetPriorityClass(H, PrioCls[K]);
  CloseHandle(H);
  Sample;
  Redraw;
End;

Procedure GoProcess;
Var P, I : LongInt;
Begin
  If ASel < 0 Then Exit;
  P := 0;
  GetWindowThreadProcessId(AWnd[ASel], P);
  Tab := 1;
  For I := 0 To PN - 1 Do
    If PPid[I] = P Then PSel := I;
  If PSel >= 0 Then PTop := PSel;
  Redraw;
End;

Procedure SwitchApp;
Begin
  If ASel < 0 Then Exit;
  SwitchToThisWindow(AWnd[ASel], 1);
  If MinUse Then ShowWindow(Wnd, 6);
End;

Procedure SetSpeed(Id : LongInt);
Begin
  CheckMenuRadioItem(MenuSpeed, idSpdHigh, idSpdPause, Id, 0);
  KillTimer(Wnd, 1);
  Paused := Id = idSpdPause;
  Case Id Of
    idSpdHigh : Interval := 500;
    idSpdLow : Interval := 4000;
  Else
    Interval := 1000;
  End;
  If Not Paused Then SetTimer(Wnd, 1, Interval, 0);
End;

{ Nouvelle tache : petite fenetre avec une zone de saisie }
Function NewWndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var P : TPaint; Hdc : LongInt; B : Array[0..259] Of Char; S : String;
    Si : Array[0..16] Of LongInt; Pi : Array[0..3] Of LongInt;
    X, Y : LongInt;
Begin
  NewWndProc := 0;
  Case M Of
    WM_PAINT :
    Begin
      Hdc := BeginPaint(H, P);
      SetBkMode(Hdc, 1);
      S := L('Tapez le nom d''un programme, dossier ou document.',
             'Type the name of a program to open.',
             'Geben Sie den Namen eines Programms ein.',
             'Digitare il nome di un programma.',
             'Escriba el nombre de un programa.');
      TextOutA(Hdc, 12, 10, @S[1], Length(S));
      S := L('Ouvrir :', 'Open:', '''Offnen:', 'Apri:', 'Abrir:');
      TextOutA(Hdc, 12, 42, @S[1], Length(S));
      EndPaint(H, P);
    End;
    WM_USER :
      SetFocus(NewEdit);
    WM_COMMAND :
    Begin
      X := W And $FFFF;
      If X = 2 Then DestroyWindow(H)
      Else If X = 3 Then
        Begin
          B[0] := #0;
          GetWindowTextA(NewEdit, @B, 250);
          S := CStr(LongInt(@B));
          If S <> '' Then
          Begin
            S := S + #0;
            Zero(LongInt(@Si), SizeOf(Si)); Si[0] := 68;
            If CreateProcessA(Nil, @S[1], Nil, Nil, 0, 0, Nil, Nil, @Si, @Pi)
               = 0 Then
              Msg(L('Impossible de trouver ', 'Cannot find ',
                    'Nicht gefunden: ', 'Impossibile trovare ',
                    'No se encuentra ') + Copy(S, 1, Length(S) - 1), Title,
                  MB_ICONERROR)
            Else
            Begin
              CloseHandle(Pi[0]); CloseHandle(Pi[1]);
            End;
          End;
          DestroyWindow(H);
        End;
    End;
    WM_DESTROY :
    Begin
      NewTaskW := 0;
      Sample;
      Redraw;
    End;
  Else
    NewWndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

Procedure NewTask;
Var C : TWndClass; Cls, T, E : String;
Begin
  If NewTaskW <> 0 Then Exit;
  Cls := Z('TmNewTask');
  C.Style := 0; C.WndProc := @NewWndProc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, 32512);
  C.Brush := BrFace; C.MenuName := Nil; C.ClassName := @Cls[1];
  RegisterClassA(C);
  T := Z(L('Cr'#130'er une nouvelle t'#131'che', 'Create New Task',
       'Neuen Task erstellen', 'Crea nuova attivit'#133,
       'Crear nueva tarea'));
  NewTaskW := CreateWindowExA(8, @Cls[1], @T[1], $00C80000 Or $10000000,
                              120, 120, 420, 140, Wnd, 0, Inst, 0);
  E := Z('EDIT');
  NewEdit := CreateWindowExA(0, @E[1], Nil, $50800080, 90, 40, 300, 22,
                             NewTaskW, 1, Inst, 0);
  E := Z('BUTTON');
  T := Z('OK');
  CreateWindowExA(0, @E[1], @T[1], $50010001, 196, 76, 92, 24, NewTaskW, 3,
                  Inst, 0);
  T := Z(L('Annuler', 'Cancel', 'Abbrechen', 'Annulla', 'Cancelar'));
  CreateWindowExA(0, @E[1], @T[1], $50010000, 298, 76, 92, 24, NewTaskW, 2,
                  Inst, 0);
  SetFocus(NewEdit);
  { la fenetre est activee ensuite : la saisie revient a la zone }
  PostMessageA(NewTaskW, WM_USER, 0, 0);
End;

Procedure About;
Begin
  Msg(Title + #10 + L('Pasdows 95, version 4.00.950', 'Pasdows 95, ' +
      'version 4.00.950', 'Pasdows 95, Version 4.00.950',
      'Pasdows 95, versione 4.00.950', 'Pasdows 95, versi'#162'n 4.00.950') +
      #10'(C) Gladir.com', L(''#181' propos du Gestionnaire des t'#131'ches',
      'About Task Manager', 'Info '#129'ber Task-Manager',
      'Informazioni su Task Manager', 'Acerca del Administrador de tareas'),
      MB_ICONINFO);
End;

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    idNewTask : NewTask;
    idExit : DestroyWindow(Wnd);
    idTop :
    Begin
      OnTop := Not OnTop;
      If OnTop Then SetWindowPos(Wnd, -1, 0, 0, 0, 0, 3)
      Else SetWindowPos(Wnd, -2, 0, 0, 0, 0, 3);
      CheckMenuItem(MainMenu, idTop, Ord(OnTop) * MF_CHECKED);
    End;
    idMinUse :
    Begin
      MinUse := Not MinUse;
      CheckMenuItem(MainMenu, idMinUse, Ord(MinUse) * MF_CHECKED);
    End;
    idHideMin :
    Begin
      HideMin := Not HideMin;
      CheckMenuItem(MainMenu, idHideMin, Ord(HideMin) * MF_CHECKED);
    End;
    idRefresh :
    Begin
      Sample;
      Redraw;
    End;
    idSpdHigh, idSpdNorm, idSpdLow, idSpdPause : SetSpeed(Id);
    idKernel :
    Begin
      ShowKrn := Not ShowKrn;
      CheckMenuItem(MainMenu, idKernel, Ord(ShowKrn) * MF_CHECKED);
      Redraw;
    End;
    idOff : ExitWindowsEx(1, 0);
    idRestart : ExitWindowsEx(2, 0);
    idLogoff : ExitWindowsEx(0, 0);
    idHelp, idAbout : About;
    idSwitch : SwitchApp;
    idFront : If ASel >= 0 Then SwitchToThisWindow(AWnd[ASel], 0);
    idMinim : If ASel >= 0 Then ShowWindow(AWnd[ASel], 6);
    idMaxim : If ASel >= 0 Then ShowWindow(AWnd[ASel], 3);
    idEndTask :
      If ASel >= 0 Then
      Begin
        EndTask(AWnd[ASel], 0, 0);
        Sample;
        Redraw;
      End;
    idGoProc : GoProcess;
    idEndProc : EndProcess;
  Else
    If (Id >= idColBase) And (Id < idColBase + NCol) Then
    Begin
      ColOn[Id - idColBase] := Not ColOn[Id - idColBase];
      CheckMenuItem(MainMenu, Id, Ord(ColOn[Id - idColBase]) * MF_CHECKED);
      Redraw;
    End
    Else If (Id >= idPrioBase) And (Id <= idPrioBase + 5) Then
      SetPrio(Id - idPrioBase);
  End;
End;

Procedure AddItem(M, Id : LongInt; S : String; F : LongInt);
Begin
  S := S + #0;
  AppendMenuA(M, F, Id, @S[1]);
End;

Procedure AddPopup(M, Sub : LongInt; S : String);
Begin
  S := S + #0;
  AppendMenuA(M, MF_POPUP, Sub, @S[1]);
End;

Procedure BuildMenus;
Var M, K : LongInt;
Begin
  MainMenu := CreateMenu;
  M := CreatePopupMenu;
  AddItem(M, idNewTask, L('Nouvelle t'#131'che (Ex'#130'cuter...)',
          'New Task (Run...)', 'Neuer Task (Ausf'#129'hren...)',
          'Nuova attivit'#133' (Esegui...)', 'Nueva tarea (Ejecutar...)'), 0);
  AddItem(M, 0, '', MF_SEPARATOR);
  AddItem(M, idExit, L('Quitter le Gestionnaire des t'#131'ches',
          'Exit Task Manager', 'Task-Manager beenden', 'Esci da Task Manager',
          'Salir del Administrador de tareas'), 0);
  AddPopup(MainMenu, M, L('Fichier', 'File', 'Datei', 'File', 'Archivo'));
  M := CreatePopupMenu;
  AddItem(M, idTop, L('Toujours visible', 'Always On Top',
          'Immer im Vordergrund', 'Sempre in primo piano', 'Siempre visible'),
          MF_CHECKED);
  AddItem(M, idMinUse, L('R'#130'duire apr'#138's utilisation',
          'Minimize On Use', 'Nach Programmstart minimieren',
          'Riduci a icona dopo l''uso', 'Minimizar al usar'), MF_CHECKED);
  AddItem(M, idHideMin, L('Masquer en r'#130'duction', 'Hide When Minimized',
          'Ausblenden wenn minimiert', 'Nascondi se ridotto a icona',
          'Ocultar al minimizar'), 0);
  AddPopup(MainMenu, M, L('Options', 'Options', 'Optionen', 'Opzioni',
           'Opciones'));
  MenuView := CreatePopupMenu;
  AddItem(MenuView, idRefresh, L('Actualiser maintenant', 'Refresh Now',
          'Jetzt aktualisieren', 'Aggiorna ora', 'Actualizar ahora'), 0);
  MenuSpeed := CreatePopupMenu;
  AddItem(MenuSpeed, idSpdHigh, L('Haute', 'High', 'Hoch', 'Alta', 'Alta'), 0);
  AddItem(MenuSpeed, idSpdNorm, L('Normale', 'Normal', 'Normal', 'Normale',
          'Normal'), MF_CHECKED);
  AddItem(MenuSpeed, idSpdLow, L('Basse', 'Low', 'Niedrig', 'Bassa', 'Baja'),
          0);
  AddItem(MenuSpeed, idSpdPause, L('Suspendue', 'Paused', 'Angehalten',
          'Sospesa', 'En pausa'), 0);
  AddPopup(MenuView, MenuSpeed, L('Fr'#130'quence d''actualisation',
           'Update Speed', 'Aktualisierungsgeschwindigkeit',
           'Velocit'#133' di aggiornamento',
           'Velocidad de actualizaci'#162'n'));
  AddItem(MenuView, 0, '', MF_SEPARATOR);
  MenuCols := CreatePopupMenu;
  For K := 0 To NCol - 1 Do
    AddItem(MenuCols, idColBase + K, ColName(K), Ord(ColOn[K]) * MF_CHECKED);
  AddPopup(MenuView, MenuCols, L('S'#130'lectionner les colonnes',
           'Select Columns', 'Spalten ausw'#132'hlen', 'Seleziona colonne',
           'Seleccionar columnas'));
  AddItem(MenuView, idKernel, L('Afficher les temps du noyau',
          'Show Kernel Times', 'Kernel-Zeiten anzeigen',
          'Mostra tempi kernel', 'Mostrar tiempos del kernel'), 0);
  AddPopup(MainMenu, MenuView, L('Affichage', 'View', 'Ansicht',
           'Visualizza', 'Ver'));
  M := CreatePopupMenu;
  AddItem(M, idStandby, L('Mettre en veille', 'Stand By', 'Standby',
          'Standby', 'Suspender'), MF_GRAYED);
  AddItem(M, idHibern, L('Mettre en veille prolong'#130'e', 'Hibernate',
          'Ruhezustand', 'Sospensione', 'Hibernar'), MF_GRAYED);
  AddItem(M, idOff, L('Arr'#136'ter', 'Turn Off', 'Ausschalten', 'Spegni',
          'Apagar'), 0);
  AddItem(M, idRestart, L('Red'#130'marrer', 'Restart', 'Neu starten',
          'Riavvia', 'Reiniciar'), 0);
  AddItem(M, 0, '', MF_SEPARATOR);
  AddItem(M, idLogoff, L('Fermer la session ', 'Log Off ', 'Abmelden ',
          'Disconnetti ', 'Cerrar sesi'#162'n ') + UserName, 0);
  AddPopup(MainMenu, M, L('Arr'#136'ter', 'Shut Down', 'Herunterfahren',
           'Chiudi sessione', 'Apagar'));
  M := CreatePopupMenu;
  AddItem(M, idHelp, L('Rubriques d''aide du Gestionnaire des t'#131'ches',
          'Task Manager Help Topics', 'Hilfethemen', 'Guida in linea',
          'Temas de ayuda'), 0);
  AddItem(M, 0, '', MF_SEPARATOR);
  AddItem(M, idAbout, L(''#181' propos du Gestionnaire des t'#131'ches',
          'About Task Manager', 'Info', 'Informazioni su Task Manager',
          'Acerca de'), 0);
  AddPopup(MainMenu, M, '?');
  SetMenu(Wnd, MainMenu);
End;

{ Menus contextuels des listes }
Procedure ContextMenu(X, Y : LongInt);
Var M, Sub, K, C : LongInt; P : TPt;
Begin
  M := CreatePopupMenu;
  If Tab = 0 Then
  Begin
    If ASel < 0 Then Exit;
    AddItem(M, idSwitch, L('Basculer vers', 'Switch To', 'Wechseln zu',
            'Passa a', 'Cambiar a'), 0);
    AddItem(M, idFront, L('Mettre au premier plan', 'Bring To Front',
            'In den Vordergrund', 'Porta in primo piano',
            'Traer al frente'), 0);
    AddItem(M, 0, '', MF_SEPARATOR);
    AddItem(M, idMinim, L('R'#130'duire', 'Minimize', 'Minimieren',
            'Riduci a icona', 'Minimizar'), 0);
    AddItem(M, idMaxim, L('Agrandir', 'Maximize', 'Maximieren', 'Ingrandisci',
            'Maximizar'), 0);
    AddItem(M, 0, '', MF_SEPARATOR);
    AddItem(M, idEndTask, L('Fin de t'#131'che', 'End Task', 'Task beenden',
            'Termina attivit'#133, 'Finalizar tarea'), 0);
    AddItem(M, idGoProc, L('Aller au processus', 'Go To Process',
            'Zu Prozess wechseln', 'Vai al processo', 'Ir al proceso'), 0);
  End
  Else If Tab = 1 Then
  Begin
    If PSel < 0 Then Exit;
    AddItem(M, idEndProc, L('Terminer le processus', 'End Process',
            'Prozess beenden', 'Termina processo', 'Terminar proceso'),
            Ord(CurPid <= 4) * MF_GRAYED);
    AddItem(M, 0, '', MF_SEPARATOR);
    Sub := CreatePopupMenu;
    For K := 0 To 5 Do
    Begin
      C := 0;
      If PPri[PSel] = PrioCls[K] Then C := MF_CHECKED;
      If CurPid <= 4 Then C := C Or MF_GRAYED;
      AddItem(Sub, idPrioBase + K, PrioName(PrioCls[K]), C);
    End;
    AddPopup(M, Sub, L('D'#130'finir la priorit'#130, 'Set Priority',
             'Priorit'#132't festlegen', 'Imposta priorit'#133,
             'Establecer prioridad'));
  End
  Else Exit;
  P.X := X; P.Y := Y;
  ClientToScreen(Wnd, P);
  TrackPopupMenu(M, 0, P.X, P.Y, 0, Wnd, Nil);
  DestroyMenu(M);
End;

Function HitZone(X, Y : LongInt) : LongInt;
Var I : LongInt;
Begin
  HitZone := 0;
  For I := ZN - 1 DownTo 0 Do
    If (X >= ZR[I].L) And (X < ZR[I].R) And (Y >= ZR[I].T) And
       (Y < ZR[I].B) Then
    Begin
      HitZone := ZId[I];
      Exit;
    End;
End;

Procedure Click(Id : LongInt; Dbl : Boolean);
Begin
  If (Id >= 400) And (Id < 400 + NTab) Then
  Begin
    Tab := Id - 400;
    Redraw;
    Exit;
  End;
  If (Id >= 1000) And (Id < 1000 + MaxA) Then
  Begin
    ASel := Id - 1000;
    If Dbl Then SwitchApp;
    Redraw;
    Exit;
  End;
  If (Id >= 2000) And (Id < 2000 + MaxP) Then
  Begin
    PSel := Id - 2000;
    Redraw;
    Exit;
  End;
  Case Id Of
    300, 301, 302, 303 :
    Begin
      If PSort = Id - 300 Then PDesc := Not PDesc
      Else
      Begin
        PSort := Id - 300;
        PDesc := (PSort = 2) Or (PSort = 3);
      End;
      Sample;
      Redraw;
    End;
    310 :
    Begin
      Dec(PTop);
      Redraw;
    End;
    311 :
    Begin
      Inc(PTop);
      Redraw;
    End;
  Else
    If Id <> 0 Then Command(Id);
  End;
End;

Function WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var X, Y, Id : LongInt; Rc : TRect;
Begin
  WndProc := 0;
  Case M Of
    WM_PAINT : Paint;
    WM_SIZE :
    Begin
      GetClientRect(H, Rc);
      CW := Rc.R; CH := Rc.B;
      If (W = 1) And HideMin Then ShowWindow(H, 0);
      Redraw;
    End;
    WM_TIMER :
    Begin
      If Not Paused Then
      Begin
        Sample;
        Redraw;
      End;
    End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
    Begin
      X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
      Id := HitZone(X, Y);
      Down := Id;
      If (Id >= 1000) Or (Id >= 400) And (Id < 400 + NTab) Or
         ((Id >= 300) And (Id < 320)) Then
      Begin
        Down := 0;
        Click(Id, (M = WM_LBUTTONDBLCLK) Or ((Id = LastClickId) And
              (GetTickCount - LastClick < 500)));
        LastClick := GetTickCount; LastClickId := Id;
      End
      Else Redraw;
    End;
    WM_LBUTTONUP :
    Begin
      X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
      Id := HitZone(X, Y);
      If (Down <> 0) And (Id = Down) Then
      Begin
        Down := 0;
        Redraw;
        Click(Id, False);
      End
      Else
      Begin
        Down := 0;
        Redraw;
      End;
    End;
    WM_RBUTTONUP :
    Begin
      X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
      Id := HitZone(X, Y);
      If (Id >= 1000) And (Id < 1000 + MaxA) Then ASel := Id - 1000;
      If (Id >= 2000) And (Id < 2000 + MaxP) Then PSel := Id - 2000;
      Redraw;
      { la selection est visible avant le menu (TrackPopupMenu attend) }
      UpdateWindow(H);
      If ((Tab = 0) And (Id >= 1000) And (Id < 1000 + MaxA)) Or
         ((Tab = 1) And (Id >= 2000) And (Id < 2000 + MaxP)) Then
        ContextMenu(X, Y);
    End;
    WM_COMMAND : Command(W And $FFFF);
    WM_KEYDOWN :
    Begin
      Case W Of
        $2E : If Tab = 1 Then EndProcess Else If Tab = 0 Then
                Command(idEndTask);
        $26 :
        Begin
          If (Tab = 1) And (PSel > 0) Then Dec(PSel);
          If (Tab = 0) And (ASel > 0) Then Dec(ASel);
          If PSel < PTop Then PTop := PSel;
        End;
        $28 :
        Begin
          If (Tab = 1) And (PSel < PN - 1) Then Inc(PSel);
          If (Tab = 0) And (ASel < AN - 1) Then Inc(ASel);
        End;
        $09 : Tab := (Tab + 1) Mod NTab;
        $74 : Sample;
        $0D : If Tab = 0 Then SwitchApp;
      End;
      Redraw;
    End;
    WM_DESTROY :
    Begin
      KillTimer(H, 1);
      PostQuitMessage(0);
    End;
  Else
    WndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

Var
  C : TWndClass;
  M : TMsg;
  Cls, Ttl, Mx : String;
  H, I : LongInt;

Begin
  LangInit;
  Inst := GetModuleHandleA(Nil);
  Cls := Z('PasdowsTaskManager');
  { une seule instance : le second lancement ramene la fenetre }
  Mx := Z('PasdowsTaskManagerMutex');
  CreateMutexA(Nil, 1, @Mx[1]);
  If GetLastError = 183 Then
  Begin
    H := FindWindowA(@Cls[1], Nil);
    If H <> 0 Then
    Begin
      If IsIconic(H) <> 0 Then ShowWindow(H, 9);
      ShowWindow(H, 5);
      SwitchToThisWindow(H, 1);
    End;
    ExitProcess(0);
  End;
  BrFace := CreateSolidBrush(cFace);
  BrWhite := CreateSolidBrush(cWhite);
  BrBlack := CreateSolidBrush(cBlack);
  BrNavy := CreateSolidBrush(cNavy);
  BrGrid := CreateSolidBrush(cGrid);
  PenW := CreatePen(0, 1, cWhite);
  PenG := CreatePen(0, 1, cGray);
  PenB := CreatePen(0, 1, cBlack);
  PenK := CreatePen(0, 1, $404040);
  PenGrid := CreatePen(0, 1, $004000);
  PenGreen := CreatePen(0, 1, cGreen);
  PenDkG := CreatePen(0, 1, $004000);
  PenRed := CreatePen(0, 1, cRed);
  PenYellow := CreatePen(0, 1, cYellow);
  OnTop := True; MinUse := True; HideMin := False; ShowKrn := False;
  Interval := 1000; NetScale := 100;
  For I := 0 To NCol - 1 Do ColOn[I] := False;
  ASel := -1; PSel := -1; PSort := 0;
  I := 40;
  UserName := '';
  If GetUserNameA(@Mx[1], I) <> 0 Then UserName := CStr(LongInt(@Mx[1]));
  C.Style := 8; C.WndProc := @WndProc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, 32512);
  C.Brush := 0; C.MenuName := Nil; C.ClassName := @Cls[1];
  RegisterClassA(C);
  Ttl := Z(Title);
  Wnd := CreateWindowExA(8, @Cls[1], @Ttl[1], $00CF0000 Or $10000000, 20, 4,
                         600, 448, 0, 0, Inst, 0);
  BuildMenus;
  { premiers echantillons (l'utilisation demande deux mesures) }
  SampleCpu;
  Sample;
  ShowWindow(Wnd, 1);
  UpdateWindow(Wnd);
  SetTimer(Wnd, 1, Interval, 0);
  While GetMessageA(M, 0, 0, 0) <> 0 Do
  Begin
    TranslateMessage(M);
    DispatchMessageA(M);
  End;
  ExitProcess(0);
End.
