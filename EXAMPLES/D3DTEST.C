/* D3DTEST : essai de Direct3D 7 (DirectDraw 7, tampon Z, texture,
   eclairage, melange alpha) en plein ecran 640x480x16 */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -nostdlib -e _start@0 -mwindows -x c
     -o D3DTEST.EXE D3DTEST.C -lkernel32 -luser32 -lgdi32 -lddraw -ldxguid */
#define INITGUID
#include <windows.h>
#include <ddraw.h>
#include <d3d.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcA(h, m, w, l);
}

static void Log(const char *s) { OutputDebugStringA(s); }

static void Zero(void *p, int n) { char *c = p; while (n--) *c++ = 0; }

/* sinus et cosinus (serie de Taylor) : pas de bibliotheque C */
static float Sin(float x)
{
  float r, t; int i;
  while (x > 3.14159265f) x -= 6.2831853f;
  while (x < -3.14159265f) x += 6.2831853f;
  r = x; t = x;
  for (i = 1; i < 8; i++) { t = -t * x * x / ((2 * i) * (2 * i + 1)); r += t; }
  return r;
}
static float Cos(float x) { return Sin(x + 1.5707963f); }

typedef struct { float x, y, z, nx, ny, nz, u, v; } VTX;   /* D3DFVF_VERTEX */
typedef struct { float x, y, z, rhw; DWORD c, s; float u, v; } TLV;

static VTX cube[36];

static void Face(int k, float ax, float ay, float az, float ux, float uy,
                 float uz, float vx, float vy, float vz)
{
  static const float cu[6] = {0, 1, 1, 0, 1, 0}, cv[6] = {0, 0, 1, 0, 1, 1};
  static const float su[6] = {-1, 1, 1, -1, 1, -1}, sv[6] = {1, 1, -1, 1, -1, -1};
  int i;
  for (i = 0; i < 6; i++) {
    VTX *p = &cube[k * 6 + i];
    p->x = ax + ux * su[i] + vx * sv[i];
    p->y = ay + uy * su[i] + vy * sv[i];
    p->z = az + uz * su[i] + vz * sv[i];
    p->nx = ax; p->ny = ay; p->nz = az;
    p->u = cu[i]; p->v = cv[i];
  }
}

static void Ident(D3DMATRIX *m)
{
  Zero(m, sizeof(*m)); m->_11 = m->_22 = m->_33 = m->_44 = 1;
}

void __stdcall start(void)
{
  WNDCLASSA wc; HWND hw; MSG msg; HINSTANCE hi = GetModuleHandleA(0);
  LPDIRECTDRAW7 dd; LPDIRECTDRAWSURFACE7 prim, back, zb, tex;
  LPDIRECT3D7 d3d; LPDIRECT3DDEVICE7 dev; DDSURFACEDESC2 sd; DDSCAPS2 caps;
  D3DVIEWPORT7 vp; D3DMATERIAL7 mt; D3DLIGHT7 lt; D3DMATRIX m;
  DDPIXELFORMAT zpf; HRESULT hr; int i, x, y, frame, ok = 1, fails = 0;
  DWORD t0; float a; TLV q[4]; char buf[96];

  wc.style = 0; wc.lpfnWndProc = WndProc; wc.cbClsExtra = 0; wc.cbWndExtra = 0;
  wc.hInstance = hi; wc.hIcon = 0; wc.hCursor = 0; wc.hbrBackground = 0;
  wc.lpszMenuName = 0; wc.lpszClassName = "D3DTEST";
  RegisterClassA(&wc);
  hw = CreateWindowExA(WS_EX_TOPMOST, "D3DTEST", "Direct3D", WS_POPUP | WS_VISIBLE,
                       0, 0, 640, 480, 0, 0, hi, 0);
  ShowCursor(FALSE);
  if (DirectDrawCreateEx(0, (void**)&dd, &IID_IDirectDraw7, 0) != DD_OK) { Log("D3DTEST: DirectDrawCreateEx"); ExitProcess(1); }
  IDirectDraw7_SetCooperativeLevel(dd, hw, DDSCL_EXCLUSIVE | DDSCL_FULLSCREEN | DDSCL_FPUSETUP);
  if (IDirectDraw7_SetDisplayMode(dd, 640, 480, 16, 0, 0) != DD_OK) { Log("D3DTEST: SetDisplayMode"); ExitProcess(2); }
  Zero(&sd, sizeof(sd)); sd.dwSize = sizeof(sd);
  sd.dwFlags = DDSD_CAPS | DDSD_BACKBUFFERCOUNT; sd.dwBackBufferCount = 1;
  sd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE | DDSCAPS_FLIP | DDSCAPS_COMPLEX | DDSCAPS_3DDEVICE;
  if (IDirectDraw7_CreateSurface(dd, &sd, &prim, 0) != DD_OK) { Log("D3DTEST: primaire"); ExitProcess(3); }
  Zero(&caps, sizeof(caps)); caps.dwCaps = DDSCAPS_BACKBUFFER;
  if (IDirectDrawSurface7_GetAttachedSurface(prim, &caps, &back) != DD_OK) { Log("D3DTEST: arriere"); ExitProcess(4); }
  if (IDirectDraw7_QueryInterface(dd, &IID_IDirect3D7, (void**)&d3d) != DD_OK) { Log("D3DTEST: IDirect3D7"); ExitProcess(5); }
  /* tampon Z de 16 bits */
  Zero(&zpf, sizeof(zpf)); zpf.dwSize = sizeof(zpf); zpf.dwFlags = DDPF_ZBUFFER;
  zpf.dwZBufferBitDepth = 16; zpf.dwZBitMask = 0xFFFF;
  Zero(&sd, sizeof(sd)); sd.dwSize = sizeof(sd);
  sd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT | DDSD_PIXELFORMAT;
  sd.dwWidth = 640; sd.dwHeight = 480; sd.ddpfPixelFormat = zpf;
  sd.ddsCaps.dwCaps = DDSCAPS_ZBUFFER | DDSCAPS_VIDEOMEMORY;
  if (IDirectDraw7_CreateSurface(dd, &sd, &zb, 0) != DD_OK) { Log("D3DTEST: tampon Z"); ExitProcess(6); }
  IDirectDrawSurface7_AddAttachedSurface(back, zb);
  if (IDirect3D7_CreateDevice(d3d, &IID_IDirect3DHALDevice, back, &dev) != D3D_OK) { Log("D3DTEST: CreateDevice"); ExitProcess(7); }
  /* texture 64x64 en damier (565) */
  Zero(&sd, sizeof(sd)); sd.dwSize = sizeof(sd);
  sd.dwFlags = DDSD_CAPS | DDSD_WIDTH | DDSD_HEIGHT | DDSD_PIXELFORMAT;
  sd.dwWidth = 64; sd.dwHeight = 64; sd.ddsCaps.dwCaps = DDSCAPS_TEXTURE;
  sd.ddpfPixelFormat.dwSize = sizeof(DDPIXELFORMAT); sd.ddpfPixelFormat.dwFlags = DDPF_RGB;
  sd.ddpfPixelFormat.dwRGBBitCount = 16; sd.ddpfPixelFormat.dwRBitMask = 0xF800;
  sd.ddpfPixelFormat.dwGBitMask = 0x07E0; sd.ddpfPixelFormat.dwBBitMask = 0x001F;
  if (IDirectDraw7_CreateSurface(dd, &sd, &tex, 0) != DD_OK) { Log("D3DTEST: texture"); ExitProcess(8); }
  Zero(&sd, sizeof(sd)); sd.dwSize = sizeof(sd);
  if (IDirectDrawSurface7_Lock(tex, 0, &sd, DDLOCK_WAIT, 0) == DD_OK) {
    for (y = 0; y < 64; y++) for (x = 0; x < 64; x++)
      ((WORD*)((char*)sd.lpSurface + y * sd.lPitch))[x] =
        (((x >> 3) ^ (y >> 3)) & 1) ? 0xFFE0 : 0x001F | (x << 11);
    IDirectDrawSurface7_Unlock(tex, 0);
  }
  vp.dwX = 0; vp.dwY = 0; vp.dwWidth = 640; vp.dwHeight = 480; vp.dvMinZ = 0; vp.dvMaxZ = 1;
  IDirect3DDevice7_SetViewport(dev, &vp);
  Zero(&mt, sizeof(mt));
  mt.diffuse.r = mt.diffuse.g = mt.diffuse.b = mt.diffuse.a = 1;
  mt.ambient.r = mt.ambient.g = mt.ambient.b = 1;
  IDirect3DDevice7_SetMaterial(dev, &mt);
  Zero(&lt, sizeof(lt)); lt.dltType = D3DLIGHT_DIRECTIONAL;
  lt.dcvDiffuse.r = lt.dcvDiffuse.g = lt.dcvDiffuse.b = 1;
  lt.dvDirection.x = 0.3f; lt.dvDirection.y = -0.5f; lt.dvDirection.z = 1;
  IDirect3DDevice7_SetLight(dev, 0, &lt);
  IDirect3DDevice7_LightEnable(dev, 0, TRUE);
  IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_AMBIENT, 0x00303030);
  IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_ZENABLE, TRUE);
  IDirect3DDevice7_SetTexture(dev, 0, tex);
  /* projection (perspective, 60 degres) et vue (recul de 4) */
  Zero(&m, sizeof(m));
  m._11 = 1.3f; m._22 = 1.732f; m._33 = 1.0f; m._34 = 1; m._43 = -0.1f;
  IDirect3DDevice7_SetTransform(dev, D3DTRANSFORMSTATE_PROJECTION, &m);
  Ident(&m); m._43 = 4;
  IDirect3DDevice7_SetTransform(dev, D3DTRANSFORMSTATE_VIEW, &m);
  Face(0, 0, 0, -1, 1, 0, 0, 0, 1, 0); Face(1, 0, 0, 1, -1, 0, 0, 0, 1, 0);
  Face(2, -1, 0, 0, 0, 0, -1, 0, 1, 0); Face(3, 1, 0, 0, 0, 0, 1, 0, 1, 0);
  Face(4, 0, 1, 0, 1, 0, 0, 0, 0, 1); Face(5, 0, -1, 0, 1, 0, 0, 0, 0, -1);
  Log("D3DTEST: initialisation reussie");
  t0 = GetTickCount();
  for (frame = 0; ok && GetTickCount() - t0 < 30000; frame++) {
    while (PeekMessageA(&msg, 0, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) ok = 0;
      if (msg.message == WM_KEYDOWN && msg.wParam == VK_ESCAPE) ok = 0;
      TranslateMessage(&msg); DispatchMessageA(&msg);
    }
    a = (GetTickCount() - t0) / 1000.0f;
    IDirect3DDevice7_Clear(dev, 0, 0, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, 0x00204080, 1.0f, 0);
    if (IDirect3DDevice7_BeginScene(dev) != D3D_OK) fails++;
    Ident(&m);
    m._11 = Cos(a); m._13 = -Sin(a); m._31 = Sin(a); m._33 = Cos(a);
    {
      D3DMATRIX r; Ident(&r);
      r._22 = Cos(a * 0.7f); r._23 = Sin(a * 0.7f); r._32 = -Sin(a * 0.7f); r._33 = Cos(a * 0.7f);
      IDirect3DDevice7_SetTransform(dev, D3DTRANSFORMSTATE_WORLD, &r);
      IDirect3DDevice7_MultiplyTransform(dev, D3DTRANSFORMSTATE_WORLD, &m);
    }
    IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_LIGHTING, TRUE);
    IDirect3DDevice7_SetTexture(dev, 0, tex);
    if (IDirect3DDevice7_DrawPrimitive(dev, D3DPT_TRIANGLELIST, D3DFVF_VERTEX, cube, 36, 0) != D3D_OK) fails++;
    /* rectangle transparent pre-transforme (melange alpha) */
    IDirect3DDevice7_SetTexture(dev, 0, 0);
    IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_ALPHABLENDENABLE, TRUE);
    IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_SRCBLEND, D3DBLEND_SRCALPHA);
    IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_DESTBLEND, D3DBLEND_INVSRCALPHA);
    for (i = 0; i < 4; i++) {
      q[i].x = (i & 1) ? 600.0f : 40.0f; q[i].y = (i & 2) ? 470.0f : 400.0f;
      q[i].z = 0; q[i].rhw = 1; q[i].c = (i & 1) ? 0x80FF2020 : 0x8020FF20; q[i].s = 0;
      q[i].u = 0; q[i].v = 0;
    }
    IDirect3DDevice7_DrawPrimitive(dev, D3DPT_TRIANGLESTRIP, D3DFVF_TLVERTEX, q, 4, 0);
    IDirect3DDevice7_SetRenderState(dev, D3DRENDERSTATE_ALPHABLENDENABLE, FALSE);
    IDirect3DDevice7_EndScene(dev);
    IDirectDrawSurface7_Flip(prim, 0, DDFLIP_WAIT);
    if (frame == 10) {
      wsprintfA(buf, "D3DTEST: 10 images en %d ms, echecs %d", (int)(GetTickCount() - t0), fails);
      Log(buf);
    }
  }
  wsprintfA(buf, "D3DTEST: fin, %d images, echecs %d", frame, fails);
  Log(buf);
  IDirect3DDevice7_Release(dev);
  IDirectDrawSurface7_Release(prim);
  IDirectDraw7_RestoreDisplayMode(dd);
  IDirectDraw7_Release(dd);
  ExitProcess(0);
}
