{ GLTEST.PAS - Essai d'OpenGL 1.1 (OPENGL32.DLL de Pasdows) dans une
  fenetre : cube texture et eclaire (glBegin/glEnd), pyramide en
  tableaux de sommets (glDrawElements), carre translucide (melange
  alpha), sol dans le brouillard, tampon Z et double tampon
  (SwapBuffers). Echap ou fermeture de la fenetre pour quitter.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 GLTEST.PAS GLTEST.EXE

  Les fonctions d'OpenGL qui prennent des flottants sont declarees avec
  des LongInt : FB donne les bits d'un flottant 32 bits, DLo et DHi les
  deux moities d'un flottant 64 bits (glFrustum). }

Program GLTest;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  TWndClass = Record
    Style : LongInt;
    WndProc : Pointer;
    ClsExtra, WndExtra, Inst, Icon, Cursor, Brush : LongInt;
    MenuName, ClassName : PChar;
  End;
  TMsg = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
  End;

Function RegisterClassA(Var C : TWndClass) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex : LongInt; Cls, Title : PChar; Style, X, Y, W,
  H, Parent, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function PeekMessageA(Var M : TMsg; H, A, B, R : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'PeekMessageA';
Function TranslateMessage(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function LoadCursorA(I, C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function GetDC(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetDC';
Function ReleaseDC(H, Dc : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseDC';
Function GetClientRect(H : LongInt; R : Pointer) : LongInt;
  stdcall; external 'user32.dll' name 'GetClientRect';
Function ChoosePixelFormat(Dc : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'ChoosePixelFormat';
Function SetPixelFormat(Dc, F : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetPixelFormat';
Function SwapBuffers(Dc : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SwapBuffers';
Function GetModuleHandleA(N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure OutputDebugStringA(S : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';

Function wglCreateContext(Dc : LongInt) : LongInt; stdcall;
  external 'opengl32.dll' name 'wglCreateContext';
Function wglMakeCurrent(Dc, Rc : LongInt) : LongInt; stdcall;
  external 'opengl32.dll' name 'wglMakeCurrent';
Function wglDeleteContext(Rc : LongInt) : LongInt; stdcall;
  external 'opengl32.dll' name 'wglDeleteContext';
Function glGetString(N : LongInt) : PChar; stdcall;
  external 'opengl32.dll' name 'glGetString';
Function glGetError : LongInt; stdcall;
  external 'opengl32.dll' name 'glGetError';
Procedure glGenTextures(N : LongInt; Var T : LongInt); stdcall;
  external 'opengl32.dll' name 'glGenTextures';
Procedure glBindTexture(Tg, T : LongInt); stdcall;
  external 'opengl32.dll' name 'glBindTexture';
Procedure glTexParameteri(Tg, N, V : LongInt); stdcall;
  external 'opengl32.dll' name 'glTexParameteri';
Procedure glTexImage2D(Tg, Lv, IFmt, W, H, B, F, T : LongInt; P : Pointer);
  stdcall; external 'opengl32.dll' name 'glTexImage2D';
Procedure glTexEnvi(Tg, N, V : LongInt); stdcall;
  external 'opengl32.dll' name 'glTexEnvi';
Procedure glViewport(X, Y, W, H : LongInt); stdcall;
  external 'opengl32.dll' name 'glViewport';
Procedure glMatrixMode(M : LongInt); stdcall;
  external 'opengl32.dll' name 'glMatrixMode';
Procedure glLoadIdentity; stdcall;
  external 'opengl32.dll' name 'glLoadIdentity';
Procedure glFrustum(LL, LH, RL, RH, BL, BH, TL, TH, NL, NH, FL,
  FH : LongInt); stdcall; external 'opengl32.dll' name 'glFrustum';
Procedure glEnable(C : LongInt); stdcall;
  external 'opengl32.dll' name 'glEnable';
Procedure glDisable(C : LongInt); stdcall;
  external 'opengl32.dll' name 'glDisable';
Procedure glClearColor(R, G, B, A : LongInt); stdcall;
  external 'opengl32.dll' name 'glClearColor';
Procedure glClear(M : LongInt); stdcall;
  external 'opengl32.dll' name 'glClear';
Procedure glLightfv(L, N : LongInt; P : Pointer); stdcall;
  external 'opengl32.dll' name 'glLightfv';
Procedure glColorMaterial(F, M : LongInt); stdcall;
  external 'opengl32.dll' name 'glColorMaterial';
Procedure glFogi(N, V : LongInt); stdcall;
  external 'opengl32.dll' name 'glFogi';
Procedure glFogf(N, V : LongInt); stdcall;
  external 'opengl32.dll' name 'glFogf';
Procedure glFogfv(N : LongInt; P : Pointer); stdcall;
  external 'opengl32.dll' name 'glFogfv';
Procedure glPushMatrix; stdcall;
  external 'opengl32.dll' name 'glPushMatrix';
Procedure glPopMatrix; stdcall;
  external 'opengl32.dll' name 'glPopMatrix';
Procedure glTranslatef(X, Y, Z : LongInt); stdcall;
  external 'opengl32.dll' name 'glTranslatef';
Procedure glRotatef(A, X, Y, Z : LongInt); stdcall;
  external 'opengl32.dll' name 'glRotatef';
Procedure glBegin(M : LongInt); stdcall;
  external 'opengl32.dll' name 'glBegin';
Procedure glEnd; stdcall;
  external 'opengl32.dll' name 'glEnd';
Procedure glColor3f(R, G, B : LongInt); stdcall;
  external 'opengl32.dll' name 'glColor3f';
Procedure glColor4f(R, G, B, A : LongInt); stdcall;
  external 'opengl32.dll' name 'glColor4f';
Procedure glNormal3fv(P : Pointer); stdcall;
  external 'opengl32.dll' name 'glNormal3fv';
Procedure glTexCoord2fv(P : Pointer); stdcall;
  external 'opengl32.dll' name 'glTexCoord2fv';
Procedure glVertex3fv(P : Pointer); stdcall;
  external 'opengl32.dll' name 'glVertex3fv';
Procedure glVertex3f(X, Y, Z : LongInt); stdcall;
  external 'opengl32.dll' name 'glVertex3f';
Procedure glEnableClientState(A : LongInt); stdcall;
  external 'opengl32.dll' name 'glEnableClientState';
Procedure glDisableClientState(A : LongInt); stdcall;
  external 'opengl32.dll' name 'glDisableClientState';
Procedure glVertexPointer(Sz, Ty, St : LongInt; P : Pointer); stdcall;
  external 'opengl32.dll' name 'glVertexPointer';
Procedure glColorPointer(Sz, Ty, St : LongInt; P : Pointer); stdcall;
  external 'opengl32.dll' name 'glColorPointer';
Procedure glDrawElements(M, N, Ty : LongInt; P : Pointer); stdcall;
  external 'opengl32.dll' name 'glDrawElements';
Procedure glBlendFunc(S, D : LongInt); stdcall;
  external 'opengl32.dll' name 'glBlendFunc';
Procedure glDepthMask(F : LongInt); stdcall;
  external 'opengl32.dll' name 'glDepthMask';

Const
  GL_TEXTURE_2D = $0DE1;
  GL_DEPTH_TEST = $0B71;
  GL_CULL_FACE = $0B44;
  GL_LIGHTING = $0B50;
  GL_LIGHT0 = $4000;
  GL_COLOR_MATERIAL = $0B57;
  GL_FOG = $0B60;
  GL_BLEND = $0BE2;
  GL_QUADS = 7;
  GL_TRIANGLES = 4;
  GL_TRIANGLE_STRIP = 5;

  { faces du cube : normale, puis 4 coins }
  CubeN : Array[0..17] Of Single = (0, 0, 1, 0, 0, -1, 1, 0, 0, -1, 0, 0,
    0, 1, 0, 0, -1, 0);
  CubeV : Array[0..71] Of Single = (
    -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1,
    1, -1, -1, -1, -1, -1, -1, 1, -1, 1, 1, -1,
    1, -1, 1, 1, -1, -1, 1, 1, -1, 1, 1, 1,
    -1, -1, -1, -1, -1, 1, -1, 1, 1, -1, 1, -1,
    -1, 1, 1, 1, 1, 1, 1, 1, -1, -1, 1, -1,
    -1, -1, -1, 1, -1, -1, 1, -1, 1, -1, -1, 1);
  TC : Array[0..7] Of Single = (0, 0, 1, 0, 1, 1, 0, 1);
  { pyramide : sommets, couleurs (RGBA) et indices }
  PyrV : Array[0..14] Of Single = (0, 1.2, 0, -1, -0.6, 1, 1, -0.6, 1,
    1, -0.6, -1, -1, -0.6, -1);
  PyrC : Array[0..19] Of Byte = (255, 255, 255, 255, 255, 40, 40, 255,
    40, 255, 40, 255, 40, 40, 255, 255, 255, 230, 40, 255);
  PyrI : Array[0..11] Of Word = (0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1);
  LPos : Array[0..3] Of Single = (2, 3, 4, 0);
  LAmb : Array[0..3] Of Single = (0.25, 0.25, 0.3, 1);
  LDif : Array[0..3] Of Single = (1, 1, 0.95, 1);
  FogC : Array[0..3] Of Single = (0.05, 0.07, 0.15, 1);

Var
  Running : Boolean;
  Tex : Array[0..64 * 64 * 4 - 1] Of Byte;

Function FB(X : Single) : LongInt;
Var L : LongInt;
Begin
  Move(X, L, 4);
  FB := L;
End;

Function DLo(X : Double) : LongInt;
Var A : Array[0..1] Of LongInt;
Begin
  Move(X, A, 8);
  DLo := A[0];
End;

Function DHi(X : Double) : LongInt;
Var A : Array[0..1] Of LongInt;
Begin
  Move(X, A, 8);
  DHi := A[1];
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Procedure Log(S : String);
Var T : String;
Begin
  T := S + #0;
  OutputDebugStringA(@T[1]);
End;

Function WndProc(H, M, W, L : LongInt) : LongInt; stdcall;
Begin
  WndProc := 0;
  If M = $0002 Then
  Begin
    Running := False;
    PostQuitMessage(0);
  End
  Else If (M = $0100) And (W = $1B) Then DestroyWindow(H)
  Else WndProc := DefWindowProcA(H, M, W, L);
End;

{ damier 64 x 64 (RGBA) : bleu et blanc, bord orange }
Procedure MakeTex;
Var X, Y, P : LongInt;
Begin
  For Y := 0 To 63 Do
    For X := 0 To 63 Do
    Begin
      P := (Y * 64 + X) * 4;
      If (X < 3) Or (Y < 3) Or (X > 60) Or (Y > 60) Then
      Begin
        Tex[P] := 255; Tex[P + 1] := 140; Tex[P + 2] := 0;
      End
      Else If (((X Shr 3) Xor (Y Shr 3)) And 1) <> 0 Then
      Begin
        Tex[P] := 30; Tex[P + 1] := 80; Tex[P + 2] := 200;
      End
      Else
      Begin
        Tex[P] := 235; Tex[P + 1] := 235; Tex[P + 2] := 235;
      End;
      Tex[P + 3] := 255;
    End;
End;

Procedure Frustum(W, H : LongInt);
Var A : Double; I : LongInt;
    V : Array[0..5] Of Double; Q : Array[0..11] Of LongInt;
Begin
  A := W / H;
  V[0] := -0.6 * A; V[1] := 0.6 * A; V[2] := -0.6; V[3] := 0.6;
  V[4] := 1; V[5] := 40;
  { chaque double en deux mots, calcules avant l'appel }
  For I := 0 To 5 Do
  Begin
    Q[I * 2] := DLo(V[I]); Q[I * 2 + 1] := DHi(V[I]);
  End;
  glMatrixMode($1701);
  glLoadIdentity;
  glFrustum(Q[0], Q[1], Q[2], Q[3], Q[4], Q[5], Q[6], Q[7], Q[8], Q[9],
            Q[10], Q[11]);
  glMatrixMode($1700);
End;

Var
  Wc : TWndClass;
  Msg : TMsg;
  Pfd : Array[0..39] Of Byte;
  R : Array[0..3] Of LongInt;
  Hw, Dc, Rc, Pf, Frame, F, K, TexN : LongInt;

Begin
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.Style := $20;      { CS_OWNDC }
  Wc.WndProc := @WndProc; Wc.Inst := GetModuleHandleA(0);
  Wc.Cursor := LoadCursorA(0, 32512); Wc.ClassName := 'GLTEST';
  RegisterClassA(Wc);
  Hw := CreateWindowExA(0, 'GLTEST', 'OpenGL - Pasdows', $10CF0000, 60, 40,
                        400, 330, 0, 0, Wc.Inst, 0);
  Dc := GetDC(Hw);
  FillChar(Pfd, SizeOf(Pfd), 0);
  Pfd[0] := 40; Pfd[2] := 1;
  Pfd[4] := $25;        { DRAW_TO_WINDOW, SUPPORT_OPENGL, DOUBLEBUFFER }
  Pfd[9] := 32; Pfd[23] := 24;
  Pf := ChoosePixelFormat(Dc, @Pfd);
  SetPixelFormat(Dc, Pf, @Pfd);
  Rc := wglCreateContext(Dc);
  wglMakeCurrent(Dc, Rc);
  Log('GLTEST : ' + StrPas(glGetString($1F01)));

  MakeTex;
  glGenTextures(1, TexN);
  glBindTexture(GL_TEXTURE_2D, TexN);
  glTexParameteri(GL_TEXTURE_2D, $2801, $2601);
  glTexParameteri(GL_TEXTURE_2D, $2800, $2601);
  glTexImage2D(GL_TEXTURE_2D, 0, $1908, 64, 64, 0, $1908, $1401, @Tex);
  glTexEnvi($2300, $2200, $2100);

  GetClientRect(Hw, @R);
  glViewport(0, 0, R[2], R[3]);
  Frustum(R[2], R[3]);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_CULL_FACE);
  glClearColor(FB(FogC[0]), FB(FogC[1]), FB(FogC[2]), FB(1));
  glLightfv(GL_LIGHT0, $1200, @LAmb);
  glLightfv(GL_LIGHT0, $1201, @LDif);
  glEnable(GL_LIGHT0);
  glEnable(GL_COLOR_MATERIAL);
  glColorMaterial($408, $1602);
  glFogi($0B65, $2601);
  glFogf($0B63, FB(4));
  glFogf($0B64, FB(14));
  glFogfv($0B66, @FogC);
  glEnable(GL_FOG);

  Running := True;
  Frame := 0;
  While Running Do
  Begin
    While PeekMessageA(Msg, 0, 0, 0, 1) <> 0 Do
    Begin
      TranslateMessage(Msg);
      DispatchMessageA(Msg);
    End;
    If Not Running Then Break;
    glClear($4000 Or $100);
    glLoadIdentity;
    glLightfv(GL_LIGHT0, $1203, @LPos);

    { cube : texture, eclairage }
    glPushMatrix;
    glTranslatef(FB(-1.3), FB(0.2), FB(-6.5));
    glRotatef(FB(Frame * 3.0), FB(0.3), FB(1), FB(0.2));
    glEnable(GL_LIGHTING);
    glEnable(GL_TEXTURE_2D);
    glColor3f(FB(1), FB(1), FB(1));
    glBegin(GL_QUADS);
    For F := 0 To 5 Do
    Begin
      glNormal3fv(@CubeN[F * 3]);
      For K := 0 To 3 Do
      Begin
        glTexCoord2fv(@TC[K * 2]);
        glVertex3fv(@CubeV[(F * 4 + K) * 3]);
      End;
    End;
    glEnd;
    glDisable(GL_TEXTURE_2D);
    glDisable(GL_LIGHTING);
    glPopMatrix;

    { pyramide : tableaux de sommets et de couleurs }
    glPushMatrix;
    glTranslatef(FB(1.5), FB(-0.1), FB(-7.5));
    glRotatef(FB(-Frame * 2.0), FB(0), FB(1), FB(0));
    glEnableClientState($8074);
    glEnableClientState($8076);
    glVertexPointer(3, $1406, 0, @PyrV);
    glColorPointer(4, $1401, 0, @PyrC);
    glDrawElements(GL_TRIANGLES, 12, $1403, @PyrI);
    glDisableClientState($8076);
    glDisableClientState($8074);
    glPopMatrix;

    { sol lointain (brouillard) et carre translucide devant }
    glDisable(GL_CULL_FACE);
    glBegin(GL_TRIANGLE_STRIP);
    glColor3f(FB(0.3), FB(0.6), FB(0.3));
    glVertex3f(FB(-8), FB(-1.8), FB(-3));
    glVertex3f(FB(8), FB(-1.8), FB(-3));
    glVertex3f(FB(-8), FB(-1.8), FB(-20));
    glVertex3f(FB(8), FB(-1.8), FB(-20));
    glEnd;
    glEnable(GL_BLEND);
    glBlendFunc($0302, $0303);
    glDepthMask(0);
    glBegin(GL_QUADS);
    glColor4f(FB(1), FB(0.9), FB(0.2), FB(0.35));
    glVertex3f(FB(-0.9), FB(-1.2), FB(-4.2));
    glVertex3f(FB(0.9), FB(-1.2), FB(-4.2));
    glColor4f(FB(1), FB(0.3), FB(0.1), FB(0.6));
    glVertex3f(FB(0.9), FB(0.1), FB(-4.2));
    glVertex3f(FB(-0.9), FB(0.1), FB(-4.2));
    glEnd;
    glDepthMask(1);
    glDisable(GL_BLEND);
    glEnable(GL_CULL_FACE);

    SwapBuffers(Dc);
    Inc(Frame);
    If Frame = 30 Then
      Log('GLTEST : 30 images, erreur GL ' + IStr(glGetError));
  End;
  wglMakeCurrent(0, 0);
  wglDeleteContext(Rc);
  ReleaseDC(Hw, Dc);
  ExitProcess(0);
End.
