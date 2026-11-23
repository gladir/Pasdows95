{ PROCTEST.PAS - Essai des processus et de la synchronisation de
  Pasdows 95 : plusieurs programmes en meme temps, objets nommes,
  memoire partagee, attentes multiples, mutex abandonne, code de sortie,
  TerminateProcess.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 PROCTEST.PAS PROCTEST.EXE

  Utilisation, dans l'Invite DOS : PROCTEST
  (le programme se relance lui-meme avec /c et /s pour ses fils) }

Program ProcTest;

Type
  TStartup = Record
    Cb : LongInt;
    Rest : Array[0..16] Of LongInt;
  End;
  TProcInfo = Record
    HProcess, HThread, Pid, Tid : LongInt;
  End;

Function GetCommandLineA : PChar; stdcall;
  external 'kernel32.dll' name 'GetCommandLineA';
Procedure OutputDebugStringA(S : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';
Function CreateFileMappingA(F, Sec, Prot, Hi, Lo : LongInt;
  Name : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateFileMappingA';
Function MapViewOfFile(H, Acc, Hi, Lo, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'MapViewOfFile';
Function CreateEventA(Sec, Manual, Init : LongInt;
  Name : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateEventA';
Function OpenEventA(Acc, Inh : LongInt; Name : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'OpenEventA';
Function SetEvent(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'SetEvent';
Function ResetEvent(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'ResetEvent';
Function GetCurrentProcessId : LongInt; stdcall;
  external 'kernel32.dll' name 'GetCurrentProcessId';
Procedure Sleep(Ms : LongInt); stdcall;
  external 'kernel32.dll' name 'Sleep';
Procedure ExitProcess(Code : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function CreateThread(Sec, Stack : LongInt; Start : Pointer;
  Param, Fl : LongInt; Var Tid : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateThread';
Function GetModuleFileNameA(M : LongInt; Buf : PChar;
  N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleFileNameA';
Function CreateProcessA(App, Cmd : PChar; PSec, TSec, Inh, Fl, Env,
  Dir : LongInt; Var Si : TStartup; Var Pi : TProcInfo) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateProcessA';
Function WaitForSingleObject(H, Ms : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'WaitForSingleObject';
Function WaitForMultipleObjects(N : LongInt; Hs : Pointer;
  All, Ms : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'WaitForMultipleObjects';
Function GetExitCodeProcess(H : LongInt; Var Code : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetExitCodeProcess';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Function GetLastError : LongInt; stdcall;
  external 'kernel32.dll' name 'GetLastError';
Function CreateSemaphoreA(Sec, Init, Max : LongInt;
  Name : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateSemaphoreA';
Function ReleaseSemaphore(H, N, Prev : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'ReleaseSemaphore';
Function CreateMutexA(Sec, Owner : LongInt; Name : PChar) : LongInt;
  stdcall; external 'kernel32.dll' name 'CreateMutexA';
Function ReleaseMutex(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'ReleaseMutex';
Function OpenProcess(Acc, Inh, Pid : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'OpenProcess';
Function TerminateProcess(H, Code : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'TerminateProcess';

Const
  WAIT_OBJECT_0 = 0;
  WAIT_ABANDONED = $80;
  WAIT_TIMEOUT = 258;
  ERROR_ALREADY_EXISTS = 183;

Type
  PLong = ^LongInt;

Var
  Fails : LongInt;
  GMutex : LongInt;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function HStr(V : LongInt) : String;
Const D : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 7 DownTo 0 Do S := S + D[((V Shr (I * 4)) And 15) + 1];
  HStr := S;
End;

{ texte sur la console et dans le journal du noyau }
Procedure Say(S : String);
Var Z : String;
Begin
  WriteLn(S);
  Z := S + #0;
  OutputDebugStringA(@Z[1]);
End;

Procedure Check(What : String; Ok : Boolean);
Begin
  If Ok Then Say(What + ' : OK')
  Else
  Begin
    Say(What + ' : ECHEC');
    Inc(Fails);
  End;
End;

{ prend le mutex et se termine sans le rendre : mutex abandonne }
Function Holder(P : LongInt) : LongInt; stdcall;
Begin
  WaitForSingleObject(GMutex, -1);
  Holder := 7;
End;

Function Sleeper(P : LongInt) : LongInt; stdcall;
Begin
  While True Do Sleep(1000);
  Sleeper := 0;
End;

Var
  Cmd, Self, Line : String;
  Map, Ev, Sem, Th, Code, R, I, Ok : LongInt;
  Shm : LongInt;
  H : Array[0..1] Of LongInt;
  Si : TStartup;
  Pi : TProcInfo;
  Buf : Array[0..259] Of Char;

{ lancer ce programme avec l'option Opt (/c ou /s) }
Function Spawn(Opt : String) : LongInt;
Begin
  Line := '"' + Self + '" ' + Opt + #0;
  FillChar(Si, SizeOf(Si), 0);
  Si.Cb := SizeOf(Si);
  Spawn := CreateProcessA(Nil, @Line[1], 0, 0, 0, 0, 0, 0, Si, Pi);
End;

Begin
  Cmd := StrPas(GetCommandLineA);
  Map := CreateFileMappingA(-1, 0, 4, 0, 4096, 'PasdowsProcTestMem');
  Shm := MapViewOfFile(Map, $F001F, 0, 0, 0);
  Ev := CreateEventA(0, 1, 0, 'PasdowsProcTestEv');

  { processus fils : ecrit dans la memoire partagee, signale, code 42 }
  If Pos('/c', Cmd) > 0 Then
  Begin
    Say('Fils : processus ' + IStr(GetCurrentProcessId) +
        ', memoire partagee ' + HStr(Shm));
    PLong(Shm)^ := $1234;
    PLong(Shm + 4)^ := GetCurrentProcessId;
    SetEvent(Ev);
    Sleep(300);
    ExitProcess(42);
  End;
  { fils qui dort : sera arrete par TerminateProcess }
  If Pos('/s', Cmd) > 0 Then
  Begin
    CreateThread(0, 0, @Sleeper, 0, 0, R);
    While True Do Sleep(1000);
  End;

  Say('PROCTEST : processus et synchronisation');
  I := GetModuleFileNameA(0, @Buf[0], 260);
  Self := StrPas(@Buf[0]);
  Check('Memoire partagee nommee', (Map <> 0) And (Shm <> 0));
  Check('Evenement nomme', Ev <> 0);

  { lancer le fils et l'attendre avec l'evenement }
  Ok := Spawn('/c');
  Check('CreateProcessA (fils)', Ok <> 0);
  H[0] := Ev; H[1] := Pi.HProcess;
  R := WaitForMultipleObjects(2, @H[0], 0, 10000);
  Check('WaitForMultipleObjects : evenement d''abord', R = WAIT_OBJECT_0);
  Check('Valeur ecrite par le fils dans la memoire partagee',
        (PLong(Shm)^ = $1234) And (PLong(Shm + 4)^ = Pi.Pid));
  R := WaitForSingleObject(Pi.HProcess, 10000);
  Check('Fin du fils (attente du processus)', R = WAIT_OBJECT_0);
  GetExitCodeProcess(Pi.HProcess, Code);
  Check('Code de sortie du fils = ' + IStr(Code), Code = 42);
  CloseHandle(Pi.HThread); CloseHandle(Pi.HProcess);

  { deuxieme ouverture du meme nom : meme objet }
  H[0] := CreateEventA(0, 1, 0, 'PasdowsProcTestEv');
  Check('Nom deja cree : ERROR_ALREADY_EXISTS',
        GetLastError = ERROR_ALREADY_EXISTS);
  ResetEvent(Ev);
  Check('Meme objet (non signale)',
        WaitForSingleObject(H[0], 0) = WAIT_TIMEOUT);
  SetEvent(H[0]);
  Check('Meme objet (signale par l''autre poignee)',
        WaitForSingleObject(Ev, 0) = WAIT_OBJECT_0);
  CloseHandle(H[0]);
  H[0] := OpenEventA($1F0003, 0, 'PasdowsProcTestEv');
  Check('OpenEventA apres fermeture d''une poignee', H[0] <> 0);
  CloseHandle(H[0]);

  { semaphore }
  Sem := CreateSemaphoreA(0, 2, 3, Nil);
  R := WaitForSingleObject(Sem, 0);
  Check('Semaphore : deux acquisitions',
        (R = WAIT_OBJECT_0) And (WaitForSingleObject(Sem, 0) = WAIT_OBJECT_0));
  Check('Semaphore : troisieme refusee',
        WaitForSingleObject(Sem, 50) = WAIT_TIMEOUT);
  R := ReleaseSemaphore(Sem, 4, 0);
  Check('ReleaseSemaphore au-dela du maximum refuse',
        (R = 0) And (GetLastError = 298));
  CloseHandle(Sem);

  { mutex : recursif, proprietaire, abandon }
  GMutex := CreateMutexA(0, 0, 'PasdowsProcTestMtx');
  R := WaitForSingleObject(GMutex, 0);
  Check('Mutex : acquis deux fois par la meme tache',
        (R = WAIT_OBJECT_0) And
        (WaitForSingleObject(GMutex, 0) = WAIT_OBJECT_0));
  ReleaseMutex(GMutex); ReleaseMutex(GMutex);
  Th := CreateThread(0, 0, @Holder, 0, 0, R);
  WaitForSingleObject(Th, 5000);
  Check('Mutex abandonne : WAIT_ABANDONED',
        WaitForSingleObject(GMutex, 1000) = WAIT_ABANDONED);
  Check('ReleaseMutex par le nouveau proprietaire', ReleaseMutex(GMutex) <> 0);
  R := ReleaseMutex(GMutex);
  Check('ReleaseMutex sans etre proprietaire refuse',
        (R = 0) And (GetLastError = 288));
  CloseHandle(Th); CloseHandle(GMutex);

  { OpenProcess et TerminateProcess }
  Spawn('/s');
  Sleep(500);
  H[0] := OpenProcess($1F0FFF, 0, Pi.Pid);
  Check('OpenProcess par identifiant', H[0] <> 0);
  Check('Le fils tourne encore', WaitForSingleObject(H[0], 0) = WAIT_TIMEOUT);
  Check('TerminateProcess', TerminateProcess(H[0], 99) <> 0);
  R := WaitForSingleObject(Pi.HProcess, 5000);
  GetExitCodeProcess(Pi.HProcess, Code);
  Check('Fils arrete, code 99', (R = WAIT_OBJECT_0) And (Code = 99));

  Say('PROCTEST : ' + IStr(Fails) + ' echec(s)');
  ExitProcess(Fails);
End.
