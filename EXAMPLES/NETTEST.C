/* NETTEST : essai de TCP/IP (Winsock 1.1, ICMP.DLL) sur Pasdows 95 */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -nostdlib -e _start@0 -mwindows -x c
     -o NETTEST.EXE NETTEST.C -lkernel32 -luser32 -lgdi32 -lwsock32
     -lmsvcrt */
#include <windows.h>
#include <winsock.h>

static char lines[24][100];
static int nl = 0;

static void out(const char *s)
{
  if (nl < 24) lstrcpynA(lines[nl++], s, 100);
  OutputDebugStringA(s);
}

static void outf(const char *f, int a, int b)
{
  char t[120];
  wsprintfA(t, f, a, b);
  out(t);
}

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_PAINT) {
    PAINTSTRUCT ps; int i;
    HDC dc = BeginPaint(h, &ps);
    SetBkMode(dc, TRANSPARENT);
    for (i = 0; i < nl; i++) TextOutA(dc, 8, 6 + i * 18, lines[i], lstrlenA(lines[i]));
    EndPaint(h, &ps);
    return 0;
  }
  if (m == WM_KEYDOWN && w == VK_ESCAPE) { DestroyWindow(h); return 0; }
  if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcA(h, m, w, l);
}

typedef HANDLE (WINAPI *PCREATE)(void);
typedef DWORD (WINAPI *PECHO)(HANDLE, DWORD, LPVOID, WORD, LPVOID, LPVOID, DWORD, DWORD);

static void tests(void)
{
  WSADATA wd; char buf[600], t[200]; struct sockaddr_in a; int n, len, r;
  SOCKET srv, cli, con, u1, u2; struct hostent *he; unsigned long nb = 1;
  fd_set ws; struct timeval tv; HMODULE hi; DWORD ip;

  r = WSAStartup(MAKEWORD(1, 1), &wd);
  wsprintfA(t, "WSAStartup=%d version %d.%d : %s", r, LOBYTE(wd.wVersion), HIBYTE(wd.wVersion), wd.szDescription);
  out(t);
  gethostname(buf, 100);
  he = gethostbyname(buf);
  wsprintfA(t, "gethostname : %s = %s", buf, he ? inet_ntoa(*(struct in_addr*)he->h_addr_list[0]) : "?");
  out(t);

  /* TCP en boucle locale */
  srv = socket(AF_INET, SOCK_STREAM, 0);
  memset(&a, 0, sizeof(a)); a.sin_family = AF_INET; a.sin_port = htons(7000);
  a.sin_addr.s_addr = inet_addr("127.0.0.1");
  r = bind(srv, (struct sockaddr*)&a, sizeof(a));
  r |= listen(srv, 5);
  cli = socket(AF_INET, SOCK_STREAM, 0);
  ioctlsocket(cli, FIONBIO, &nb);
  n = connect(cli, (struct sockaddr*)&a, sizeof(a));
  outf("TCP local : bind/listen=%d connect=%d", r, n == SOCKET_ERROR ? WSAGetLastError() : 0);
  len = sizeof(a);
  con = accept(srv, (struct sockaddr*)&a, &len);
  FD_ZERO(&ws); FD_SET(cli, &ws); tv.tv_sec = 2; tv.tv_usec = 0;
  r = select(0, 0, &ws, 0, &tv);
  outf("accept=%d select(ecriture)=%d", con != INVALID_SOCKET, r);
  send(cli, "Bonjour Pasdows", 15, 0);
  n = recv(con, buf, 100, 0); if (n > 0) buf[n] = 0; else buf[0] = 0;
  wsprintfA(t, "recu par le serveur : %d octets '%s' de port %d", n, buf, ntohs(a.sin_port));
  out(t);
  send(con, "Salut", 5, 0);
  closesocket(con);
  Sleep(50);
  n = recv(cli, buf, 100, 0); if (n > 0) buf[n] = 0; else buf[0] = 0;
  r = recv(cli, buf + 200, 100, 0);
  wsprintfA(t, "recu par le client : '%s', puis recv=%d (fin)", buf, r);
  out(t);
  closesocket(cli); closesocket(srv);

  /* UDP en boucle locale */
  u1 = socket(AF_INET, SOCK_DGRAM, 0); u2 = socket(AF_INET, SOCK_DGRAM, 0);
  a.sin_port = htons(7001); a.sin_addr.s_addr = inet_addr("127.0.0.1");
  bind(u1, (struct sockaddr*)&a, sizeof(a));
  sendto(u2, "datagramme", 10, 0, (struct sockaddr*)&a, sizeof(a));
  len = sizeof(a);
  n = recvfrom(u1, buf, 100, 0, (struct sockaddr*)&a, &len); if (n > 0) buf[n] = 0;
  wsprintfA(t, "UDP local : %d octets '%s'", n, n > 0 ? buf : "");
  out(t);
  closesocket(u1); closesocket(u2);

  /* ICMP.DLL : ping de la passerelle */
  hi = LoadLibraryA("ICMP.DLL");
  if (hi) {
    PCREATE cf = (PCREATE)GetProcAddress(hi, "IcmpCreateFile");
    PECHO se = (PECHO)GetProcAddress(hi, "IcmpSendEcho");
    if (cf && se) {
      HANDLE h = cf();
      r = se(h, inet_addr("10.0.2.2"), "abcdefgh", 8, 0, buf, sizeof(buf), 2000);
      outf("IcmpSendEcho(10.0.2.2)=%d temps=%d ms", r, r ? *(DWORD*)(buf + 8) : 0);
    } else out("ICMP.DLL : GetProcAddress echoue");
  }

  /* DNS */
  he = gethostbyname("www.example.com");
  if (he) {
    wsprintfA(t, "DNS www.example.com = %s", inet_ntoa(*(struct in_addr*)he->h_addr_list[0]));
    out(t);
  } else outf("DNS www.example.com : erreur %d", WSAGetLastError(), 0);

  /* HTTP vers l'hote (10.0.2.2:8000) */
  cli = socket(AF_INET, SOCK_STREAM, 0);
  a.sin_port = htons(8000); a.sin_addr.s_addr = inet_addr("10.0.2.2");
  if (connect(cli, (struct sockaddr*)&a, sizeof(a)) == 0) {
    const char *rq = "GET /hello.txt HTTP/1.0\r\nHost: 10.0.2.2\r\n\r\n";
    int tot = 0, first = 1;
    send(cli, rq, lstrlenA(rq), 0);
    while ((n = recv(cli, buf, 512, 0)) > 0) {
      if (first) {
        int i; for (i = 0; i < n && buf[i] != '\r'; i++); buf[i] = 0;
        wsprintfA(t, "HTTP : %s", buf); out(t); first = 0;
      }
      tot += n;
    }
    outf("HTTP : %d octets recus, fin=%d", tot, n);
  } else outf("HTTP connect : erreur %d", WSAGetLastError(), 0);
  closesocket(cli);
  /* gros transfert : 300 000 octets, somme de controle */
  cli = socket(AF_INET, SOCK_STREAM, 0);
  if (connect(cli, (struct sockaddr*)&a, sizeof(a)) == 0) {
    const char *rq = "GET /big.bin HTTP/1.0\r\n\r\n";
    unsigned sum = 0; int tot = 0, hdr = 1, i; DWORD t0 = GetTickCount();
    send(cli, rq, lstrlenA(rq), 0);
    while ((n = recv(cli, buf, 512, 0)) > 0) {
      i = 0;
      if (hdr) { /* sauter l'en-tete HTTP (fin : CRLFCRLF, dans le 1er bloc) */
        for (i = 3; i < n; i++) if (buf[i-3]=='\r'&&buf[i-2]=='\n'&&buf[i-1]=='\r'&&buf[i]=='\n') { i++; break; }
        hdr = 0;
      }
      for (; i < n; i++) { sum += (unsigned char)buf[i]; tot++; }
    }
    wsprintfA(t, "big.bin : %d octets, somme %u, %d ms", tot, sum, GetTickCount() - t0);
    out(t);
  }
  closesocket(cli);
  WSACleanup();
  out("Termine.");
}

void __stdcall start(void)
{
  WNDCLASSA wc; HWND h; MSG msg;
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = WndProc; wc.hInstance = GetModuleHandleA(0);
  wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); wc.lpszClassName = "NetTest";
  wc.hCursor = LoadCursorA(0, IDC_ARROW);
  RegisterClassA(&wc);
  h = CreateWindowA("NetTest", "Essai TCP/IP", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                    30, 30, 580, 330, 0, 0, wc.hInstance, 0);
  tests();
  InvalidateRect(h, 0, TRUE);
  while (GetMessageA(&msg, 0, 0, 0) > 0) { TranslateMessage(&msg); DispatchMessageA(&msg); }
  ExitProcess(0);
}
