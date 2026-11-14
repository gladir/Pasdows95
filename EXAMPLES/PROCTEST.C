/* PROCTEST : essai des processus et de la synchronisation de Pasdows 95
   (plusieurs programmes en meme temps, objets nommes, memoire partagee,
   attentes multiples, mutex abandonne, code de sortie, TerminateProcess) */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -s -nostdlib -e _start@0 -x c
     -o PROCTEST.EXE PROCTEST.C -lkernel32 -luser32 */
#include <windows.h>

static HANDLE out;
static int fails;

static void Say(const char *s)
{
  DWORD n;
  WriteFile(out, s, lstrlenA(s), &n, 0);
  OutputDebugStringA(s);
}

static void Check(const char *what, int ok)
{
  char b[160];
  wsprintfA(b, "%s : %s\r\n", what, ok ? "OK" : "ECHEC");
  if (!ok) fails++;
  Say(b);
}

static HANDLE gMutex;

static DWORD WINAPI Holder(LPVOID p)
{
  /* prend le mutex et se termine sans le rendre : mutex abandonne */
  WaitForSingleObject(gMutex, INFINITE);
  return 7;
}

static DWORD WINAPI Sleeper(LPVOID p)
{
  for (;;) Sleep(1000);
  return 0;
}

void __stdcall start(void)
{
  char *cmd = GetCommandLineA(), self[260], line[300], b[200];
  HANDLE map, ev, sem, h[2], th;
  STARTUPINFOA si; PROCESS_INFORMATION pi;
  DWORD code, r, pid;
  volatile LONG *shm;
  int i;

  out = GetStdHandle(STD_OUTPUT_HANDLE);
  map = CreateFileMappingA(INVALID_HANDLE_VALUE, 0, PAGE_READWRITE, 0, 4096,
                           "PasdowsProcTestMem");
  shm = (volatile LONG *)MapViewOfFile(map, FILE_MAP_ALL_ACCESS, 0, 0, 0);
  ev = CreateEventA(0, TRUE, FALSE, "PasdowsProcTestEv");

  /* processus fils : ecrit dans la memoire partagee, signale, code 42 */
  for (i = 0; cmd[i]; i++)
    if (cmd[i] == '/' && cmd[i + 1] == 'c') {
      wsprintfA(b, "Fils : processus %lu, memoire partagee %08lX\r\n",
                GetCurrentProcessId(), (DWORD)shm);
      Say(b);
      shm[0] = 0x1234; shm[1] = (LONG)GetCurrentProcessId();
      SetEvent(ev);
      Sleep(300);
      ExitProcess(42);
    }
    else if (cmd[i] == '/' && cmd[i + 1] == 's') {
      /* fils qui dort : sera arrete par TerminateProcess */
      CreateThread(0, 0, Sleeper, 0, 0, &r);
      for (;;) Sleep(1000);
    }

  Say("PROCTEST : processus et synchronisation\r\n");
  GetModuleFileNameA(0, self, sizeof(self));
  Check("Memoire partagee nommee", map != 0 && shm != 0);
  Check("Evenement nomme", ev != 0);

  /* lancer le fils et l'attendre avec l'evenement */
  wsprintfA(line, "\"%s\" /c", self);
  ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
  i = CreateProcessA(0, line, 0, 0, FALSE, 0, 0, 0, &si, &pi);
  Check("CreateProcessA (fils)", i != 0);
  h[0] = ev; h[1] = pi.hProcess;
  r = WaitForMultipleObjects(2, h, FALSE, 10000);
  Check("WaitForMultipleObjects : evenement d'abord", r == WAIT_OBJECT_0);
  Check("Valeur ecrite par le fils dans la memoire partagee",
        shm[0] == 0x1234 && (DWORD)shm[1] == pi.dwProcessId);
  r = WaitForSingleObject(pi.hProcess, 10000);
  Check("Fin du fils (attente du processus)", r == WAIT_OBJECT_0);
  GetExitCodeProcess(pi.hProcess, &code);
  wsprintfA(b, "Code de sortie du fils = %lu", code);
  Check(b, code == 42);
  CloseHandle(pi.hThread); CloseHandle(pi.hProcess);

  /* deuxieme ouverture du meme nom : meme objet */
  h[0] = CreateEventA(0, TRUE, FALSE, "PasdowsProcTestEv");
  Check("Nom deja cree : ERROR_ALREADY_EXISTS",
        GetLastError() == ERROR_ALREADY_EXISTS);
  ResetEvent(ev);
  Check("Meme objet (non signale)", WaitForSingleObject(h[0], 0) ==
        WAIT_TIMEOUT);
  SetEvent(h[0]);
  Check("Meme objet (signale par l'autre poignee)",
        WaitForSingleObject(ev, 0) == WAIT_OBJECT_0);
  CloseHandle(h[0]);
  Check("OpenEventA apres fermeture d'une poignee",
        (h[0] = OpenEventA(EVENT_ALL_ACCESS, FALSE, "PasdowsProcTestEv"))
        != 0);
  CloseHandle(h[0]);

  /* semaphore */
  sem = CreateSemaphoreA(0, 2, 3, 0);
  Check("Semaphore : deux acquisitions",
        WaitForSingleObject(sem, 0) == WAIT_OBJECT_0 &&
        WaitForSingleObject(sem, 0) == WAIT_OBJECT_0);
  Check("Semaphore : troisieme refusee",
        WaitForSingleObject(sem, 50) == WAIT_TIMEOUT);
  Check("ReleaseSemaphore au-dela du maximum refuse",
        !ReleaseSemaphore(sem, 4, 0) && GetLastError() == 298);
  CloseHandle(sem);

  /* mutex : recursif, proprietaire, abandon */
  gMutex = CreateMutexA(0, FALSE, "PasdowsProcTestMtx");
  Check("Mutex : acquis deux fois par la meme tache",
        WaitForSingleObject(gMutex, 0) == WAIT_OBJECT_0 &&
        WaitForSingleObject(gMutex, 0) == WAIT_OBJECT_0);
  ReleaseMutex(gMutex); ReleaseMutex(gMutex);
  th = CreateThread(0, 0, Holder, 0, 0, &r);
  WaitForSingleObject(th, 5000);
  Check("Mutex abandonne : WAIT_ABANDONED",
        WaitForSingleObject(gMutex, 1000) == WAIT_ABANDONED);
  Check("ReleaseMutex par le nouveau proprietaire", ReleaseMutex(gMutex));
  Check("ReleaseMutex sans etre proprietaire refuse",
        !ReleaseMutex(gMutex) && GetLastError() == 288);
  CloseHandle(th); CloseHandle(gMutex);

  /* OpenProcess et TerminateProcess */
  wsprintfA(line, "\"%s\" /s", self);
  i = CreateProcessA(0, line, 0, 0, FALSE, 0, 0, 0, &si, &pi);
  Sleep(500);
  h[0] = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pi.dwProcessId);
  Check("OpenProcess par identifiant", h[0] != 0);
  Check("Le fils tourne encore", WaitForSingleObject(h[0], 0) ==
        WAIT_TIMEOUT);
  Check("TerminateProcess", TerminateProcess(h[0], 99));
  r = WaitForSingleObject(pi.hProcess, 5000);
  GetExitCodeProcess(pi.hProcess, &code);
  Check("Fils arrete, code 99", r == WAIT_OBJECT_0 && code == 99);

  wsprintfA(b, "PROCTEST : %d echec(s)\r\n", fails);
  Say(b);
  ExitProcess(fails);
}
