{ D3DTEST.PAS - Essai de Direct3D 7 : DirectDraw 7 en plein ecran
  640x480x16, tampon Z, texture, eclairage directionnel, cube qui tourne
  (DrawPrimitive, sommets D3DFVF_VERTEX) et rectangle pre-transforme
  translucide (melange alpha). Echap pour quitter, sinon 30 secondes.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 D3DTEST.PAS D3DTEST.EXE

  Le resultat ("D3DTEST: ... echecs 0") est ecrit dans le journal du
  noyau par OutputDebugStringA. }

Program D3DTest;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  PLong = ^LongInt;
  PWrd = ^Word;
  TC1 = Function(T : LongInt) : LongInt; stdcall;
  TC2 = Function(T, A : LongInt) : LongInt; stdcall;
  TC3 = Function(T, A, B : LongInt) : LongInt; stdcall;
  TC4 = Function(T, A, B, C : LongInt) : LongInt; stdcall;
  TC5 = Function(T, A, B, C, D : LongInt) : LongInt; stdcall;
  TC6 = Function(T, A, B, C, D, E : LongInt) : LongInt; stdcall;
  TC7 = Function(T, A, B, C, D, E, F : LongInt) : LongInt; stdcall;
  TWndClass = Record
    Style : LongInt;
    WndProc : Pointer;
    ClsExtra, WndExtra, Inst, Icon, Cursor, Brush : LongInt;
    MenuName, ClassName : PChar;
  End;
  TMsg = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
  End;
  TGuid = Record
    D1 : LongInt;
    D2, D3 : Word;
    D4 : Array[0..7] Of Byte;
  End;
  TMat = Array[0..15] Of Single;

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
Function ShowCursor(S : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ShowCursor';
Function GetModuleHandleA(N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure OutputDebugStringA(S : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Function DirectDrawCreateEx(G : LongInt; Var DD : LongInt; Var Iid : TGuid;
  O : LongInt) : LongInt; stdcall;
  external 'ddraw.dll' name 'DirectDrawCreateEx';

Const
  IID_DD7 : TGuid = (D1 : $15E65EC0; D2 : $3B9C; D3 : $11D2;
    D4 : ($B9, $2F, $00, $60, $97, $97, $EA, $5B));
  IID_D3D7 : TGuid = (D1 : LongInt($F5049E77); D2 : $4861; D3 : $11D2;
    D4 : ($A4, $07, $00, $A0, $C9, $06, $29, $A8));
  IID_HAL : TGuid = (D1 : LongInt($84E63DE0); D2 : $46AA; D3 : $11CF;
    D4 : ($81, $6F, $00, $00, $C0, $20, $15, $6E));
  { faces du cube : centre, axes U et V }
  Fc : Array[0..53] Of Single = (
    0, 0, -1, 1, 0, 0, 0, 1, 0,    0, 0, 1, -1, 0, 0, 0, 1, 0,
    -1, 0, 0, 0, 0, -1, 0, 1, 0,   1, 0, 0, 0, 0, 1, 0, 1, 0,
    0, 1, 0, 1, 0, 0, 0, 0, 1,     0, -1, 0, 1, 0, 0, 0, 0, -1);
  CU : Array[0..5] Of Single = (0, 1, 1, 0, 1, 0);
  CV : Array[0..5] Of Single = (0, 0, 1, 0, 1, 1);
  SU : Array[0..5] Of Single = (-1, 1, 1, -1, 1, -1);
  SV : Array[0..5] Of Single = (1, 1, -1, 1, -1, -1);

Var
  Cube : Array[0..36 * 8 - 1] Of Single;   { x y z nx ny nz u v }
  Fails : LongInt;

Function Vt(O, I : LongInt) : Pointer;
Begin
  Vt := Pointer(PLong(PLong(O)^ + I * 4)^);
End;

{ bits d'un flottant 32 bits (parametres Single passes en LongInt) }
Function FB(X : Single) : LongInt;
Var L : LongInt;
Begin
  Move(X, L, 4);
  FB := L;
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
  If M = $0002 Then PostQuitMessage(0)
  Else WndProc := DefWindowProcA(H, M, W, L);
End;

Procedure MakeCube;
Var K, I, B, F : LongInt;
Begin
  For K := 0 To 5 Do
    For I := 0 To 5 Do
    Begin
      B := (K * 6 + I) * 8; F := K * 9;
      Cube[B] := Fc[F] + Fc[F + 3] * SU[I] + Fc[F + 6] * SV[I];
      Cube[B + 1] := Fc[F + 1] + Fc[F + 4] * SU[I] + Fc[F + 7] * SV[I];
      Cube[B + 2] := Fc[F + 2] + Fc[F + 5] * SU[I] + Fc[F + 8] * SV[I];
      Cube[B + 3] := Fc[F]; Cube[B + 4] := Fc[F + 1];
      Cube[B + 5] := Fc[F + 2];
      Cube[B + 6] := CU[I]; Cube[B + 7] := CV[I];
    End;
End;

Procedure Ident(Var M : TMat);
Var I : LongInt;
Begin
  For I := 0 To 15 Do M[I] := 0;
  M[0] := 1; M[5] := 1; M[10] := 1; M[15] := 1;
End;

Procedure Die(S : String; C : LongInt);
Begin
  Log('D3DTEST: ' + S);
  ExitProcess(C);
End;

Var
  Wc : TWndClass;
  Msg : TMsg;
  Hw, Hi, DD, Prim, Back, ZB, Tex, D3, Dev, I, X, Y, Frame, T0, P, V : LongInt;
  Ok : Boolean;
  A : Single;
  Sd : Array[0..30] Of LongInt;
  Caps : Array[0..3] Of LongInt;
  Vp : Array[0..5] Of LongInt;
  Mt : Array[0..16] Of Single;
  Lt : Array[0..25] Of LongInt;
  M, R : TMat;
  Q : Array[0..31] Of LongInt;

Begin
  Hi := GetModuleHandleA(0);
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.WndProc := @WndProc; Wc.Inst := Hi; Wc.ClassName := 'D3DTEST';
  RegisterClassA(Wc);
  Hw := CreateWindowExA(8, 'D3DTEST', 'Direct3D', LongInt($90000000), 0, 0,
                        640, 480, 0, 0, Hi, 0);
  ShowCursor(0);
  If DirectDrawCreateEx(0, DD, IID_DD7, 0) <> 0 Then
    Die('DirectDrawCreateEx', 1);
  TC3(Vt(DD, 20))(DD, Hw, $10 Or $1 Or $20);
  If TC6(Vt(DD, 21))(DD, 640, 480, 16, 0, 0) <> 0 Then
    Die('SetDisplayMode', 2);
  FillChar(Sd, SizeOf(Sd), 0);
  Sd[0] := 124; Sd[1] := 1 Or $20; Sd[5] := 1;
  Sd[26] := $200 Or $10 Or $8 Or $2000;
  If TC4(Vt(DD, 6))(DD, LongInt(@Sd), LongInt(@Prim), 0) <> 0 Then
    Die('primaire', 3);
  FillChar(Caps, SizeOf(Caps), 0);
  Caps[0] := 4;
  If TC3(Vt(Prim, 12))(Prim, LongInt(@Caps), LongInt(@Back)) <> 0 Then
    Die('arriere', 4);
  If TC3(Vt(DD, 0))(DD, LongInt(@IID_D3D7), LongInt(@D3)) <> 0 Then
    Die('IDirect3D7', 5);
  { tampon Z de 16 bits }
  FillChar(Sd, SizeOf(Sd), 0);
  Sd[0] := 124; Sd[1] := 1 Or 2 Or 4 Or $1000;
  Sd[3] := 640; Sd[2] := 480;
  Sd[18] := 32; Sd[19] := $400; Sd[21] := 16; Sd[23] := $FFFF;
  Sd[26] := $20000 Or $4000;
  If TC4(Vt(DD, 6))(DD, LongInt(@Sd), LongInt(@ZB), 0) <> 0 Then
    Die('tampon Z', 6);
  TC2(Vt(Back, 3))(Back, ZB);
  If TC4(Vt(D3, 4))(D3, LongInt(@IID_HAL), Back, LongInt(@Dev)) <> 0 Then
    Die('CreateDevice', 7);
  { texture 64x64 en damier (565) }
  FillChar(Sd, SizeOf(Sd), 0);
  Sd[0] := 124; Sd[1] := 1 Or 2 Or 4 Or $1000;
  Sd[3] := 64; Sd[2] := 64; Sd[26] := $1000;
  Sd[18] := 32; Sd[19] := $40; Sd[21] := 16;
  Sd[22] := $F800; Sd[23] := $07E0; Sd[24] := $001F;
  If TC4(Vt(DD, 6))(DD, LongInt(@Sd), LongInt(@Tex), 0) <> 0 Then
    Die('texture', 8);
  FillChar(Sd, SizeOf(Sd), 0);
  Sd[0] := 124;
  If TC5(Vt(Tex, 25))(Tex, 0, LongInt(@Sd), 1, 0) = 0 Then
  Begin
    For Y := 0 To 63 Do
    Begin
      P := Sd[9] + Y * Sd[4];
      For X := 0 To 63 Do
      Begin
        If (((X Shr 3) Xor (Y Shr 3)) And 1) <> 0 Then V := $FFE0
        Else V := $001F Or (X Shl 11);
        PWrd(P + X * 2)^ := V;
      End;
    End;
    TC2(Vt(Tex, 32))(Tex, 0);
  End;
  Vp[0] := 0; Vp[1] := 0; Vp[2] := 640; Vp[3] := 480;
  Vp[4] := FB(0); Vp[5] := FB(1);
  TC2(Vt(Dev, 13))(Dev, LongInt(@Vp));
  For I := 0 To 16 Do Mt[I] := 0;
  For I := 0 To 3 Do Mt[I] := 1;
  For I := 4 To 6 Do Mt[I] := 1;
  TC2(Vt(Dev, 16))(Dev, LongInt(@Mt));
  FillChar(Lt, SizeOf(Lt), 0);
  Lt[0] := 3;
  Lt[1] := FB(1); Lt[2] := FB(1); Lt[3] := FB(1);
  Lt[16] := FB(0.3); Lt[17] := FB(-0.5); Lt[18] := FB(1);
  TC3(Vt(Dev, 18))(Dev, 0, LongInt(@Lt));
  TC3(Vt(Dev, 44))(Dev, 0, 1);
  TC3(Vt(Dev, 20))(Dev, 139, $00303030);
  TC3(Vt(Dev, 20))(Dev, 7, 1);
  TC3(Vt(Dev, 35))(Dev, 0, Tex);
  { projection (perspective, 60 degres) et vue (recul de 4) }
  For I := 0 To 15 Do M[I] := 0;
  M[0] := 1.3; M[5] := 1.732; M[10] := 1; M[11] := 1; M[14] := -0.1;
  TC3(Vt(Dev, 11))(Dev, 3, LongInt(@M));
  Ident(M); M[14] := 4;
  TC3(Vt(Dev, 11))(Dev, 2, LongInt(@M));
  MakeCube;
  Log('D3DTEST: initialisation reussie');
  T0 := GetTickCount;
  Ok := True;
  Frame := 0;
  While Ok And (GetTickCount - T0 < 30000) Do
  Begin
    While PeekMessageA(Msg, 0, 0, 0, 1) <> 0 Do
    Begin
      If Msg.Msg = $0012 Then Ok := False;
      If (Msg.Msg = $0100) And (Msg.WP = $1B) Then Ok := False;
      TranslateMessage(Msg); DispatchMessageA(Msg);
    End;
    A := (GetTickCount - T0) / 1000;
    TC7(Vt(Dev, 10))(Dev, 0, 0, 1 Or 2, $00204080, FB(1), 0);
    If TC1(Vt(Dev, 5))(Dev) <> 0 Then Inc(Fails);
    Ident(M);
    M[0] := Cos(A); M[2] := -Sin(A); M[8] := Sin(A); M[10] := Cos(A);
    Ident(R);
    R[5] := Cos(A * 0.7); R[6] := Sin(A * 0.7);
    R[9] := -Sin(A * 0.7); R[10] := Cos(A * 0.7);
    TC3(Vt(Dev, 11))(Dev, 1, LongInt(@R));
    TC3(Vt(Dev, 14))(Dev, 1, LongInt(@M));
    TC3(Vt(Dev, 20))(Dev, 137, 1);
    TC3(Vt(Dev, 35))(Dev, 0, Tex);
    If TC6(Vt(Dev, 25))(Dev, 4, $112, LongInt(@Cube), 36, 0) <> 0 Then
      Inc(Fails);
    { rectangle translucide pre-transforme (melange alpha) }
    TC3(Vt(Dev, 35))(Dev, 0, 0);
    TC3(Vt(Dev, 20))(Dev, 27, 1);
    TC3(Vt(Dev, 20))(Dev, 19, 5);
    TC3(Vt(Dev, 20))(Dev, 20, 6);
    For I := 0 To 3 Do
    Begin
      If (I And 1) <> 0 Then Q[I * 8] := FB(600) Else Q[I * 8] := FB(40);
      If (I And 2) <> 0 Then Q[I * 8 + 1] := FB(470)
      Else Q[I * 8 + 1] := FB(400);
      Q[I * 8 + 2] := FB(0); Q[I * 8 + 3] := FB(1);
      If (I And 1) <> 0 Then Q[I * 8 + 4] := LongInt($80FF2020)
      Else Q[I * 8 + 4] := LongInt($8020FF20);
      Q[I * 8 + 5] := 0; Q[I * 8 + 6] := 0; Q[I * 8 + 7] := 0;
    End;
    TC6(Vt(Dev, 25))(Dev, 5, $1C4, LongInt(@Q), 4, 0);
    TC3(Vt(Dev, 20))(Dev, 27, 0);
    TC1(Vt(Dev, 6))(Dev);
    TC3(Vt(Prim, 11))(Prim, 0, 1);
    If Frame = 10 Then
      Log('D3DTEST: 10 images en ' + IStr(GetTickCount - T0) +
          ' ms, echecs ' + IStr(Fails));
    Inc(Frame);
  End;
  Log('D3DTEST: fin, ' + IStr(Frame) + ' images, echecs ' + IStr(Fails));
  TC1(Vt(Dev, 2))(Dev);
  TC1(Vt(Prim, 2))(Prim);
  TC1(Vt(DD, 19))(DD);
  TC1(Vt(DD, 2))(DD);
  ExitProcess(0);
End.
