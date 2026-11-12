/* FATTEST : essai du systeme de fichiers FAT32 de Pasdows 95 */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -O1 -nostdlib -e _start@0 -mwindows -x c
     -o FATTEST.EXE FATTEST.C -lkernel32 -luser32 -lgdi32
     -lmsvcrt */
#include <windows.h>

static char lines[26][100];
static int nl = 0;
static char big[300000];

static void out(const char *s)
{
  if (nl < 26) lstrcpynA(lines[nl++], s, 100);
  OutputDebugStringA(s);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_PAINT) {
    PAINTSTRUCT ps; int i;
    HDC dc = BeginPaint(h, &ps);
    SetBkMode(dc, TRANSPARENT);
    for (i = 0; i < nl; i++) TextOutA(dc, 8, 4 + i * 16, lines[i], lstrlenA(lines[i]));
    EndPaint(h, &ps);
    return 0;
  }
  if (m == WM_KEYDOWN && w == VK_ESCAPE) { DestroyWindow(h); return 0; }
  if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcA(h, m, w, l);
}

static unsigned sum(const char *p, int n)
{
  unsigned s = 0; int i;
  for (i = 0; i < n; i++) s += (unsigned char)p[i];
  return s;
}

static void tests(void)
{
  char t[300], vol[64], fs[16], buf[600]; DWORD ser, mc, fl, spc, bps, fr, tot, n, i;
  WIN32_FIND_DATAA fd; HANDLE h, f; int cnt; ULARGE_INTEGER a, b, c;

  GetVolumeInformationA("C:\\", vol, 64, &ser, &mc, &fl, fs, 16);
  wsprintfA(t, "C: = %s, %s, serie %08X, noms de %d car.", vol, fs, ser, mc); out(t);
  GetDiskFreeSpaceA("C:\\", &spc, &bps, &fr, &tot);
  GetDiskFreeSpaceExA("C:\\", &a, &b, &c);
  wsprintfA(t, "clusters %d x %d o : %d libres / %d ; Ex : %d Ko libres", spc, bps, fr, tot, (int)(a.QuadPart / 1024)); out(t);
  n = GetLogicalDriveStringsA(sizeof(buf), buf);
  for (i = 0; i < n; i++) if (!buf[i]) buf[i] = ' ';
  wsprintfA(t, "lecteurs : %s", buf); out(t);

  /* liste de la racine */
  t[0] = 0; cnt = 0;
  h = FindFirstFileA("C:\\*.*", &fd);
  if (h != INVALID_HANDLE_VALUE) {
    do { if (lstrlenA(t) < 200) { lstrcatA(t, fd.cFileName); lstrcatA(t, (fd.dwFileAttributes & 16) ? "\\ " : " "); } cnt++; }
    while (FindNextFileA(h, &fd));
    FindClose(h);
  }
  out("C:\\ :"); out(t);
  cnt = 0;
  h = FindFirstFileA("C:\\JEUX\\*.txt", &fd);
  if (h != INVALID_HANDLE_VALUE) { do cnt++; while (FindNextFileA(h, &fd)); FindClose(h); }
  wsprintfA(t, "C:\\JEUX\\*.txt : %d fichiers", cnt); out(t);

  /* lecture d'un nom long */
  f = CreateFileA("C:\\Mes Documents\\Lettre a Marie.txt", GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  n = 0; ReadFile(f, buf, 100, &n, 0); CloseHandle(f); buf[n] = 0;
  for (i = 0; i < n; i++) if (buf[i] < 32) buf[i] = 0;
  wsprintfA(t, "Lettre a Marie.txt : '%s'", buf); out(t);
  f = CreateFileA("C:\\JEUX\\Donnees du jeu.bin", GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  n = 0; ReadFile(f, big, sizeof(big), &n, 0);
  wsprintfA(t, "Donnees du jeu.bin : %d octets, taille %d, somme %u", n, GetFileSize(f, 0), sum(big, n)); out(t);
  SetFilePointer(f, 100000, 0, FILE_BEGIN); ReadFile(f, buf, 4, &n, 0);
  wsprintfA(t, "a 100000 : %02X %02X %02X %02X", (unsigned char)buf[0], (unsigned char)buf[1], (unsigned char)buf[2], (unsigned char)buf[3]); out(t);
  CloseHandle(f);

  /* ecriture */
  wsprintfA(t, "CreateDirectory(Nouveau dossier) = %d", CreateDirectoryA("C:\\Nouveau dossier", 0)); out(t);
  for (i = 0; i < 200000; i++) big[i] = (char)(i * 7 + i / 1000);
  f = CreateFileA("C:\\Nouveau dossier\\Un fichier ecrit par Pasdows.dat", GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  WriteFile(f, big, 150000, &n, 0); WriteFile(f, big + 150000, 50000, &n, 0); CloseHandle(f);
  f = CreateFileA("C:\\NOUVEAU DOSSIER\\un fichier ECRIT par pasdows.dat", GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  n = 0; ReadFile(f, big + 200000, 100000, &n, 0);
  wsprintfA(t, "relu (autre casse) : %d / %d octets, somme %u = %u", n, GetFileSize(f, 0), sum(big + 200000, 100000), sum(big, 100000)); out(t);
  CloseHandle(f);
  f = CreateFileA("C:\\ajout.txt", GENERIC_WRITE, 0, 0, OPEN_ALWAYS, 0, 0);
  SetFilePointer(f, 0, 0, FILE_END); WriteFile(f, "ligne 1\r\n", 9, &n, 0); CloseHandle(f);
  f = CreateFileA("C:\\ajout.txt", GENERIC_WRITE, 0, 0, OPEN_ALWAYS, 0, 0);
  SetFilePointer(f, 0, 0, FILE_END); WriteFile(f, "ligne 2\r\n", 9, &n, 0); CloseHandle(f);
  f = CreateFileA("C:\\tronque.bin", GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  WriteFile(f, big, 100000, &n, 0); SetFilePointer(f, 1000, 0, FILE_BEGIN); SetEndOfFile(f); CloseHandle(f);
  f = CreateFileA("C:\\tronque.bin", GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  wsprintfA(t, "tronque.bin : %d octets", GetFileSize(f, 0)); out(t); CloseHandle(f);
  wsprintfA(t, "MoveFile = %d, DeleteFile = %d, RemoveDirectory = %d",
    MoveFileA("C:\\JEUX\\fichier numero 1.txt", "C:\\Mes Documents\\Renomme et deplace.txt"),
    DeleteFileA("C:\\JEUX\\fichier numero 2.txt"),
    RemoveDirectoryA("C:\\Mes Documents\\Sous dossier")); out(t);
  CreateDirectoryA("C:\\Vide", 0);
  wsprintfA(t, "RemoveDirectory(Vide) = %d ; attributs C:\\WINDOWS = %X", RemoveDirectoryA("C:\\Vide"), GetFileAttributesA("C:\\WINDOWS")); out(t);
  GetDiskFreeSpaceA("C:\\", &spc, &bps, &fr, &tot);
  wsprintfA(t, "clusters libres : %d", fr); out(t);
  out("Termine.");
}

void __stdcall start(void)
{
  WNDCLASSA wc; HWND h; MSG msg;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = WndProc; wc.hInstance = GetModuleHandleA(0);
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); wc.lpszClassName = "FatTest";
  wc.hCursor = LoadCursorA(0, IDC_ARROW);
  RegisterClassA(&wc);
  h = CreateWindowA("FatTest", "Essai FAT32", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                    10, 10, 620, 440, 0, 0, wc.hInstance, 0);
  tests();
  InvalidateRect(h, 0, TRUE);
  while (GetMessageA(&msg, 0, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
  ExitProcess(0);
}
