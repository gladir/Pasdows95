/* DDTEST : essai de DirectDraw, DirectSound et DirectInput */
/* Compilation (MinGW) :
   i686-w64-mingw32-gcc -march=i386 -O1 -nostdlib -e _start@0 -mwindows -x c
     -o DDTEST.EXE DDTEST.C -lkernel32 -luser32 -lgdi32 -lddraw -ldsound
     -ldinput -ldxguid */
#define INITGUID
#define DIRECTINPUT_VERSION 0x0300
#include <windows.h>
#include <ddraw.h>
#include <dsound.h>
#include <dinput.h>

static LRESULT CALLBACK WndProc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcA(h, m, w, l);
}

void __stdcall start(void)
{
  WNDCLASSA wc; HWND hw; MSG msg; LPDIRECTDRAW dd; LPDIRECTDRAWSURFACE prim, back;
  LPDIRECTDRAWPALETTE pal; DDSURFACEDESC sd; DDSCAPS caps; PALETTEENTRY pe[256];
  LPDIRECTSOUND ds; LPDIRECTSOUNDBUFFER sb; DSBUFFERDESC bd; WAVEFORMATEX wf;
  LPDIRECTINPUTA di; LPDIRECTINPUTDEVICEA kb; BYTE keys[256];
  DDBLTFX fx; HDC dc; int i, x, y, frame, ok = 1; DWORD t0, pos = 0, wpos;
  HINSTANCE hi = GetModuleHandleA(0);
  char *p; void *a1, *a2; DWORD n1, n2;

  wc.style = 0; wc.lpfnWndProc = WndProc; wc.cbClsExtra = 0; wc.cbWndExtra = 0;
  wc.hInstance = hi; wc.hIcon = 0; wc.hCursor = 0; wc.hbrBackground = 0;
  wc.lpszMenuName = 0; wc.lpszClassName = "DDTEST";
  RegisterClassA(&wc);
  hw = CreateWindowExA(WS_EX_TOPMOST, "DDTEST", "DirectX", WS_POPUP | WS_VISIBLE,
                       0, 0, 640, 480, 0, 0, hi, 0);
  if (DirectDrawCreate(0, &dd, 0) != DD_OK) ExitProcess(1);
  IDirectDraw_SetCooperativeLevel(dd, hw, DDSCL_EXCLUSIVE | DDSCL_FULLSCREEN);
  IDirectDraw_SetDisplayMode(dd, 640, 480, 8);
  for (i = 0; i < (int)sizeof(sd); i++) ((char*)&sd)[i] = 0;
  sd.dwSize = sizeof(sd); sd.dwFlags = DDSD_CAPS | DDSD_BACKBUFFERCOUNT;
  sd.ddsCaps.dwCaps = DDSCAPS_PRIMARYSURFACE | DDSCAPS_FLIP | DDSCAPS_COMPLEX;
  sd.dwBackBufferCount = 1;
  if (IDirectDraw_CreateSurface(dd, &sd, &prim, 0) != DD_OK) ExitProcess(2);
  caps.dwCaps = DDSCAPS_BACKBUFFER;
  if (IDirectDrawSurface_GetAttachedSurface(prim, &caps, &back) != DD_OK) ExitProcess(3);
  for (i = 0; i < 256; i++) {
    pe[i].peRed = (BYTE)(i < 128 ? i * 2 : 255); pe[i].peGreen = (BYTE)(i);
    pe[i].peBlue = (BYTE)(255 - i); pe[i].peFlags = 0;
  }
  pe[0].peRed = pe[0].peGreen = pe[0].peBlue = 0;
  pe[255].peRed = pe[255].peGreen = pe[255].peBlue = 255;
  IDirectDraw_CreatePalette(dd, DDPCAPS_8BIT | DDPCAPS_ALLOW256, pe, &pal, 0);
  IDirectDrawSurface_SetPalette(prim, pal);
  /* DirectSound : un tampon d'une seconde en boucle */
  sb = 0;
  if (DirectSoundCreate(0, &ds, 0) == DS_OK) {
    IDirectSound_SetCooperativeLevel(ds, hw, DSSCL_NORMAL);
    wf.wFormatTag = WAVE_FORMAT_PCM; wf.nChannels = 1; wf.nSamplesPerSec = 22050;
    wf.wBitsPerSample = 8; wf.nBlockAlign = 1; wf.nAvgBytesPerSec = 22050; wf.cbSize = 0;
    bd.dwSize = sizeof(bd); bd.dwFlags = 0; bd.dwBufferBytes = 22050;
    bd.dwReserved = 0; bd.lpwfxFormat = &wf;
    if (IDirectSound_CreateSoundBuffer(ds, &bd, &sb, 0) == DS_OK) {
      if (IDirectSoundBuffer_Lock(sb, 0, 22050, &a1, &n1, &a2, &n2, 0) == DS_OK) {
        for (i = 0; i < (int)n1; i++) ((BYTE*)a1)[i] = (BYTE)(128 + ((i / 25) & 1) * 40);
        IDirectSoundBuffer_Unlock(sb, a1, n1, a2, n2);
      }
      IDirectSoundBuffer_Play(sb, 0, 0, DSBPLAY_LOOPING);
    }
  }
  /* DirectInput : clavier */
  kb = 0;
  if (DirectInputCreateA(hi, DIRECTINPUT_VERSION, &di, 0) == DI_OK) {
    if (IDirectInput_CreateDevice(di, &GUID_SysKeyboard, &kb, 0) == DI_OK) {
      IDirectInputDevice_SetDataFormat(kb, &c_dfDIKeyboard);
      IDirectInputDevice_Acquire(kb);
    }
  }
  t0 = GetTickCount();
  for (frame = 0; ok && GetTickCount() - t0 < 60000; frame++) {
    while (PeekMessageA(&msg, 0, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) ok = 0;
      TranslateMessage(&msg); DispatchMessageA(&msg);
    }
    sd.dwSize = sizeof(sd);
    if (IDirectDrawSurface_Lock(back, 0, &sd, DDLOCK_WAIT, 0) == DD_OK) {
      for (y = 0; y < 480; y++) {
        p = (char*)sd.lpSurface + y * sd.lPitch;
        for (x = 0; x < 640; x++) p[x] = (char)((x + y + frame * 4) & 0xFE);
      }
      IDirectDrawSurface_Unlock(back, 0);
    }
    fx.dwSize = sizeof(fx); fx.dwFillColor = 255;
    {
      RECT r; r.left = 220 + (frame * 3) % 200; r.top = 300; r.right = r.left + 100; r.bottom = 340;
      IDirectDrawSurface_Blt(back, &r, 0, 0, DDBLT_COLORFILL | DDBLT_WAIT, &fx);
    }
    if (IDirectDrawSurface_GetDC(back, &dc) == DD_OK) {
      SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(255, 255, 255));
      TextOutA(dc, 180, 200, "DirectDraw sur Pasdows 95", 25);
      if (sb) {
        IDirectSoundBuffer_GetCurrentPosition(sb, &pos, &wpos);
        TextOutA(dc, 180, 230, "DirectSound : lecture", 21);
      }
      TextOutA(dc, 180, 260, kb ? "DirectInput : Echap pour quitter" : "pas de DirectInput", kb ? 32 : 18);
      IDirectDrawSurface_ReleaseDC(back, dc);
    }
    IDirectDrawSurface_Flip(prim, 0, DDFLIP_WAIT);
    if (kb && IDirectInputDevice_GetDeviceState(kb, 256, keys) == DI_OK && (keys[DIK_ESCAPE] & 0x80)) ok = 0;
    Sleep(20);
  }
  if (sb) IDirectSoundBuffer_Stop(sb);
  IDirectDrawSurface_Release(prim);
  IDirectDraw_Release(dd);
  ExitProcess(0);
}
