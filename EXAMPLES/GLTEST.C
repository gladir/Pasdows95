/* GLTEST : essai d'OpenGL 1.1 (OPENGL32.DLL de Pasdows) dans une
   fenetre : cube texture et eclaire (glBegin/glEnd), pyramide en
   tableaux de sommets (glDrawElements), carre translucide (melange
   alpha), brouillard, tampon Z et double tampon (SwapBuffers) */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -nostdlib -e _start@0 -mwindows -x c
     -o GLTEST.EXE GLTEST.C -lkernel32 -luser32 -lgdi32 -lopengl32 */
#include <windows.h>
#include <GL/gl.h>

static int Running = 1;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_DESTROY) { Running = 0; PostQuitMessage(0); return 0; }
  if (m == WM_KEYDOWN && w == VK_ESCAPE) { DestroyWindow(h); return 0; }
  return DefWindowProcA(h, m, w, l);
}

static void Log(const char *s) { OutputDebugStringA(s); }

/* nombre -> texte (sans bibliotheque C) */
static void Num(char *d, int v)
{
  char t[16]; int n = 0;
  if (v < 0) { *d++ = '-'; v = -v; }
  do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v);
  while (n) *d++ = t[--n];
  *d = 0;
}

/* damier 64 x 64 (RGBA) : bleu et blanc, bord orange */
static unsigned char Tex[64 * 64 * 4];

static void MakeTex(void)
{
  int x, y;
  for (y = 0; y < 64; y++)
    for (x = 0; x < 64; x++) {
      unsigned char *p = &Tex[(y * 64 + x) * 4];
      int c = ((x >> 3) ^ (y >> 3)) & 1;
      if (x < 3 || y < 3 || x > 60 || y > 60) {
        p[0] = 255; p[1] = 140; p[2] = 0;
      } else if (c) {
        p[0] = 30; p[1] = 80; p[2] = 200;
      } else {
        p[0] = 235; p[1] = 235; p[2] = 235;
      }
      p[3] = 255;
    }
}

/* faces du cube : normale, puis 4 coins */
static const float CubeN[6][3] = {
  {0, 0, 1}, {0, 0, -1}, {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}
};
static const float CubeV[6][4][3] = {
  {{-1, -1, 1}, {1, -1, 1}, {1, 1, 1}, {-1, 1, 1}},
  {{1, -1, -1}, {-1, -1, -1}, {-1, 1, -1}, {1, 1, -1}},
  {{1, -1, 1}, {1, -1, -1}, {1, 1, -1}, {1, 1, 1}},
  {{-1, -1, -1}, {-1, -1, 1}, {-1, 1, 1}, {-1, 1, -1}},
  {{-1, 1, 1}, {1, 1, 1}, {1, 1, -1}, {-1, 1, -1}},
  {{-1, -1, -1}, {1, -1, -1}, {1, -1, 1}, {-1, -1, 1}}
};
static const float TC[4][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}};

/* pyramide : sommets (x, y, z), couleurs (r, g, b) et indices */
static const float PyrV[5 * 3] = {
  0, 1.2f, 0, -1, -0.6f, 1, 1, -0.6f, 1, 1, -0.6f, -1, -1, -0.6f, -1
};
static const unsigned char PyrC[5 * 4] = {
  255, 255, 255, 255, 255, 40, 40, 255, 40, 255, 40, 255,
  40, 40, 255, 255, 255, 230, 40, 255
};
static const unsigned short PyrI[12] = {0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1};

static void Frustum(double w, double h)
{
  double a = w / h;
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  glFrustum(-0.6 * a, 0.6 * a, -0.6, 0.6, 1.0, 40.0);
  glMatrixMode(GL_MODELVIEW);
}

void __stdcall start(void)
{
  WNDCLASSA wc;
  HWND h;
  HDC dc;
  HGLRC rc;
  PIXELFORMATDESCRIPTOR pfd;
  MSG msg;
  GLuint tex;
  int pf, frame = 0, f, k;
  RECT r;
  char buf[96], *p;
  static const float lpos[4] = {2, 3, 4, 0};
  static const float lamb[4] = {0.25f, 0.25f, 0.3f, 1};
  static const float ldif[4] = {1, 1, 0.95f, 1};
  static const float fogc[4] = {0.05f, 0.07f, 0.15f, 1};

  wc.style = CS_OWNDC; wc.lpfnWndProc = WndProc; wc.cbClsExtra = 0;
  wc.cbWndExtra = 0; wc.hInstance = GetModuleHandleA(0); wc.hIcon = 0;
  wc.hCursor = LoadCursorA(0, IDC_ARROW); wc.hbrBackground = 0;
  wc.lpszMenuName = 0; wc.lpszClassName = "GLTEST";
  RegisterClassA(&wc);
  h = CreateWindowExA(0, "GLTEST", "OpenGL - Pasdows",
                      WS_OVERLAPPEDWINDOW | WS_VISIBLE, 60, 40, 400, 330,
                      0, 0, wc.hInstance, 0);
  dc = GetDC(h);
  for (k = 0; k < (int)sizeof(pfd); k++) ((char *)&pfd)[k] = 0;
  pfd.nSize = sizeof(pfd); pfd.nVersion = 1;
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
  pfd.iPixelType = PFD_TYPE_RGBA; pfd.cColorBits = 32; pfd.cDepthBits = 24;
  pf = ChoosePixelFormat(dc, &pfd);
  SetPixelFormat(dc, pf, &pfd);
  rc = wglCreateContext(dc);
  wglMakeCurrent(dc, rc);
  Log("GLTEST : ");
  Log((const char *)glGetString(GL_RENDERER));

  MakeTex();
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA,
               GL_UNSIGNED_BYTE, Tex);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

  GetClientRect(h, &r);
  glViewport(0, 0, r.right, r.bottom);
  Frustum(r.right, r.bottom);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_CULL_FACE);
  glClearColor(fogc[0], fogc[1], fogc[2], 1);
  glLightfv(GL_LIGHT0, GL_AMBIENT, lamb);
  glLightfv(GL_LIGHT0, GL_DIFFUSE, ldif);
  glEnable(GL_LIGHT0);
  glEnable(GL_COLOR_MATERIAL);
  glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
  glFogi(GL_FOG_MODE, GL_LINEAR);
  glFogf(GL_FOG_START, 4.0f);
  glFogf(GL_FOG_END, 14.0f);
  glFogfv(GL_FOG_COLOR, fogc);
  glEnable(GL_FOG);

  while (Running) {
    while (PeekMessageA(&msg, 0, 0, 0, PM_REMOVE)) {
      TranslateMessage(&msg);
      DispatchMessageA(&msg);
    }
    if (!Running) break;
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glLoadIdentity();
    glLightfv(GL_LIGHT0, GL_POSITION, lpos);

    /* cube : texture, eclairage */
    glPushMatrix();
    glTranslatef(-1.3f, 0.2f, -6.5f);
    glRotatef(frame * 3.0f, 0.3f, 1, 0.2f);
    glEnable(GL_LIGHTING);
    glEnable(GL_TEXTURE_2D);
    glColor3f(1, 1, 1);
    glBegin(GL_QUADS);
    for (f = 0; f < 6; f++) {
      glNormal3fv(CubeN[f]);
      for (k = 0; k < 4; k++) {
        glTexCoord2fv(TC[k]);
        glVertex3fv(CubeV[f][k]);
      }
    }
    glEnd();
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glPopMatrix();

    /* pyramide : tableaux de sommets et de couleurs */
    glPushMatrix();
    glTranslatef(1.5f, -0.1f, -7.5f);
    glRotatef(-frame * 2.0f, 0, 1, 0);
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glVertexPointer(3, GL_FLOAT, 0, PyrV);
    glColorPointer(4, GL_UNSIGNED_BYTE, 0, PyrC);
    glDrawElements(GL_TRIANGLES, 12, GL_UNSIGNED_SHORT, PyrI);
    glDisableClientState(GL_COLOR_ARRAY);
    glDisableClientState(GL_VERTEX_ARRAY);
    glPopMatrix();

    /* sol lointain (brouillard) et carre translucide devant */
    glDisable(GL_CULL_FACE);
    glBegin(GL_TRIANGLE_STRIP);
    glColor3f(0.3f, 0.6f, 0.3f);
    glVertex3f(-8, -1.8f, -3);
    glVertex3f(8, -1.8f, -3);
    glVertex3f(-8, -1.8f, -20);
    glVertex3f(8, -1.8f, -20);
    glEnd();
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDepthMask(GL_FALSE);
    glBegin(GL_QUADS);
    glColor4f(1, 0.9f, 0.2f, 0.35f);
    glVertex3f(-0.9f, -1.2f, -4.2f);
    glVertex3f(0.9f, -1.2f, -4.2f);
    glColor4f(1, 0.3f, 0.1f, 0.6f);
    glVertex3f(0.9f, 0.1f, -4.2f);
    glVertex3f(-0.9f, 0.1f, -4.2f);
    glEnd();
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
    glEnable(GL_CULL_FACE);

    SwapBuffers(dc);
    frame++;
    if (frame == 30) {
      p = buf;
      lstrcpyA(p, "GLTEST : 30 images, erreur GL ");
      Num(p + lstrlenA(p), (int)glGetError());
      Log(buf);
    }
  }
  wglMakeCurrent(0, 0);
  wglDeleteContext(rc);
  ReleaseDC(h, dc);
  ExitProcess(0);
}
