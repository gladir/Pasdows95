/* D3D8TEST : essai de Direct3D 8 dans une fenetre (tampons de sommets
   et d'index, texture, eclairage, tampon Z automatique, Present) */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -s -nostdlib -e _start@0 -mwindows -x c
     -o D3D8TEST.EXE D3D8TEST.C -lkernel32 -luser32 -ld3d8 */
#include <windows.h>
#include <d3d8.h>

static int quit;

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_DESTROY) { quit = 1; PostQuitMessage(0); return 0; }
  if (m == WM_KEYDOWN && w == VK_ESCAPE) { DestroyWindow(h); return 0; }
  return DefWindowProcA(h, m, w, l);
}

static void Zero(void *p, int n) { char *c = p; while (n--) *c++ = 0; }

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

typedef struct { float x, y, z, nx, ny, nz; DWORD c; float u, v; } V;
#define FVF (D3DFVF_XYZ | D3DFVF_NORMAL | D3DFVF_DIFFUSE | D3DFVF_TEX1)

void __stdcall start(void)
{
  WNDCLASSA wc; HWND hw; MSG msg; HINSTANCE hi = GetModuleHandleA(0);
  IDirect3D8 *d3d; IDirect3DDevice8 *dev; D3DPRESENT_PARAMETERS pp;
  IDirect3DVertexBuffer8 *vb; IDirect3DIndexBuffer8 *ib; IDirect3DTexture8 *tx;
  D3DLOCKED_RECT lr; D3DMATERIAL8 mt; D3DLIGHT8 lt; D3DMATRIX m;
  V *v; WORD *ix; int i, x, y, frame = 0, fails = 0; DWORD t0; float a; char buf[96];

  wc.style = 0; wc.lpfnWndProc = WndProc; wc.cbClsExtra = 0; wc.cbWndExtra = 0;
  wc.hInstance = hi; wc.hIcon = 0; wc.hCursor = LoadCursorA(0, IDC_ARROW);
  wc.hbrBackground = 0; wc.lpszMenuName = 0; wc.lpszClassName = "D3D8TEST";
  RegisterClassA(&wc);
  hw = CreateWindowExA(0, "D3D8TEST", "Direct3D 8", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
                       60, 40, 328, 270, 0, 0, hi, 0);
  d3d = Direct3DCreate8(D3D_SDK_VERSION);
  if (!d3d) { OutputDebugStringA("D3D8TEST: Direct3DCreate8"); ExitProcess(1); }
  Zero(&pp, sizeof(pp));
  pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
  pp.BackBufferFormat = D3DFMT_UNKNOWN; pp.EnableAutoDepthStencil = TRUE;
  pp.AutoDepthStencilFormat = D3DFMT_D16;
  if (IDirect3D8_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, hw,
        D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dev) != D3D_OK) {
    OutputDebugStringA("D3D8TEST: CreateDevice"); ExitProcess(2);
  }
  /* pyramide : 4 faces + base */
  if (IDirect3DDevice8_CreateVertexBuffer(dev, 16 * sizeof(V), 0, FVF, D3DPOOL_MANAGED, &vb) != D3D_OK ||
      IDirect3DDevice8_CreateIndexBuffer(dev, 18 * 2, 0, D3DFMT_INDEX16, D3DPOOL_MANAGED, &ib) != D3D_OK ||
      IDirect3DDevice8_CreateTexture(dev, 32, 32, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &tx) != D3D_OK) {
    OutputDebugStringA("D3D8TEST: ressources"); ExitProcess(3);
  }
  IDirect3DVertexBuffer8_Lock(vb, 0, 0, (BYTE**)&v, 0);
  {
    static const float bx[4] = {-1, 1, 1, -1}, bz[4] = {-1, -1, 1, 1};
    static const DWORD col[4] = {0xFFFF4040, 0xFF40FF40, 0xFF4040FF, 0xFFFFFF40};
    for (i = 0; i < 4; i++) {
      int j = (i + 1) & 3; V *f = &v[i * 3];
      float nx = (bx[i] + bx[j]) * 0.7f, nz = (bz[i] + bz[j]) * 0.7f;
      f[0].x = 0; f[0].y = 1.2f; f[0].z = 0; f[0].u = 0.5f; f[0].v = 0;
      f[1].x = bx[j]; f[1].y = -0.8f; f[1].z = bz[j]; f[1].u = 1; f[1].v = 1;
      f[2].x = bx[i]; f[2].y = -0.8f; f[2].z = bz[i]; f[2].u = 0; f[2].v = 1;
      for (x = 0; x < 3; x++) { f[x].nx = nx; f[x].ny = 0.5f; f[x].nz = nz; f[x].c = col[i]; }
    }
    for (i = 0; i < 4; i++) {
      v[12 + i].x = bx[i]; v[12 + i].y = -0.8f; v[12 + i].z = bz[i];
      v[12 + i].nx = 0; v[12 + i].ny = -1; v[12 + i].nz = 0; v[12 + i].c = 0xFFFFFFFF;
      v[12 + i].u = bx[i] > 0; v[12 + i].v = bz[i] > 0;
    }
  }
  IDirect3DVertexBuffer8_Unlock(vb);
  IDirect3DIndexBuffer8_Lock(ib, 0, 0, (BYTE**)&ix, 0);
  for (i = 0; i < 12; i++) ix[i] = (WORD)i;
  ix[12] = 12; ix[13] = 13; ix[14] = 14; ix[15] = 12; ix[16] = 14; ix[17] = 15;
  IDirect3DIndexBuffer8_Unlock(ib);
  IDirect3DTexture8_LockRect(tx, 0, &lr, 0, 0);
  for (y = 0; y < 32; y++) for (x = 0; x < 32; x++)
    ((DWORD*)((char*)lr.pBits + y * lr.Pitch))[x] = ((x ^ y) & 4) ? 0xFFFFFFFF : 0xFF808080;
  IDirect3DTexture8_UnlockRect(tx, 0);
  Zero(&mt, sizeof(mt));
  mt.Diffuse.r = mt.Diffuse.g = mt.Diffuse.b = mt.Diffuse.a = 1;
  mt.Ambient.r = mt.Ambient.g = mt.Ambient.b = 1;
  IDirect3DDevice8_SetMaterial(dev, &mt);
  Zero(&lt, sizeof(lt)); lt.Type = D3DLIGHT_DIRECTIONAL;
  lt.Diffuse.r = lt.Diffuse.g = lt.Diffuse.b = 1;
  lt.Direction.x = -0.4f; lt.Direction.y = -0.6f; lt.Direction.z = 1;
  IDirect3DDevice8_SetLight(dev, 0, &lt);
  IDirect3DDevice8_LightEnable(dev, 0, TRUE);
  IDirect3DDevice8_SetRenderState(dev, D3DRS_AMBIENT, 0x00404040);
  IDirect3DDevice8_SetRenderState(dev, D3DRS_ZENABLE, D3DZB_TRUE);
  IDirect3DDevice8_SetTextureStageState(dev, 0, D3DTSS_COLOROP, D3DTOP_MODULATE);
  IDirect3DDevice8_SetTexture(dev, 0, (IDirect3DBaseTexture8*)tx);
  IDirect3DDevice8_SetVertexShader(dev, FVF);
  IDirect3DDevice8_SetStreamSource(dev, 0, vb, sizeof(V));
  IDirect3DDevice8_SetIndices(dev, ib, 0);
  Zero(&m, sizeof(m));
  m._11 = 1.3f; m._22 = 1.732f; m._33 = 1.0f; m._34 = 1; m._43 = -0.1f;
  IDirect3DDevice8_SetTransform(dev, D3DTS_PROJECTION, &m);
  Zero(&m, sizeof(m)); m._11 = m._22 = m._33 = m._44 = 1; m._43 = 4;
  IDirect3DDevice8_SetTransform(dev, D3DTS_VIEW, &m);
  OutputDebugStringA("D3D8TEST: initialisation reussie");
  t0 = GetTickCount();
  while (!quit && GetTickCount() - t0 < 30000) {
    while (PeekMessageA(&msg, 0, 0, 0, PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
    if (quit) break;
    a = (GetTickCount() - t0) / 800.0f;
    Zero(&m, sizeof(m));
    m._11 = Cos(a); m._13 = -Sin(a); m._22 = 1; m._31 = Sin(a); m._33 = Cos(a); m._44 = 1;
    IDirect3DDevice8_SetTransform(dev, D3DTS_WORLD, &m);
    IDirect3DDevice8_Clear(dev, 0, 0, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER, 0xFF103060, 1.0f, 0);
    IDirect3DDevice8_BeginScene(dev);
    if (IDirect3DDevice8_DrawIndexedPrimitive(dev, D3DPT_TRIANGLELIST, 0, 16, 0, 6) != D3D_OK) fails++;
    IDirect3DDevice8_EndScene(dev);
    if (IDirect3DDevice8_Present(dev, 0, 0, 0, 0) != D3D_OK) fails++;
    if (++frame == 10) {
      wsprintfA(buf, "D3D8TEST: 10 images en %d ms, echecs %d", (int)(GetTickCount() - t0), fails);
      OutputDebugStringA(buf);
    }
  }
  wsprintfA(buf, "D3D8TEST: fin, %d images, echecs %d", frame, fails);
  OutputDebugStringA(buf);
  IDirect3DTexture8_Release(tx); IDirect3DIndexBuffer8_Release(ib);
  IDirect3DVertexBuffer8_Release(vb); IDirect3DDevice8_Release(dev);
  IDirect3D8_Release(d3d);
  ExitProcess(0);
}
