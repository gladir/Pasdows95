{ D3D8TEST.PAS - Essai de Direct3D 8 dans une fenetre : tampons de
  sommets et d'index, texture 32 bits, eclairage directionnel, tampon Z
  automatique, Present. Pyramide qui tourne pendant 30 secondes (Echap
  ou fermeture de la fenetre pour quitter).

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 D3D8TEST.PAS D3D8TEST.EXE

  Le resultat ("D3D8TEST: ... echecs 0") est ecrit dans le journal du
  noyau par OutputDebugStringA. }

Program D3D8Test;

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
  TC8 = Function(T, A, B, C, D, E, F, G : LongInt) : LongInt; stdcall;
  TWndClass = Record
    Style : LongInt;
    WndProc : Pointer;
    ClsExtra, WndExtra, Inst, Icon, Cursor, Brush : LongInt;
    MenuName, ClassName : PChar;
  End;
  TMsg = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
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
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function LoadCursorA(I, C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function GetModuleHandleA(N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure OutputDebugStringA(S : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Function Direct3DCreate8(V : LongInt) : LongInt; stdcall;
  external 'd3d8.dll' name 'Direct3DCreate8';

Const
  FVF = $152;           { XYZ, NORMALE, DIFFUSE, TEX1 : 9 mots }
  BX : Array[0..3] Of Single = (-1, 1, 1, -1);
  BZ : Array[0..3] Of Single = (-1, -1, 1, 1);
  Col : Array[0..3] Of LongInt = (LongInt($FFFF4040), LongInt($FF40FF40),
    LongInt($FF4040FF), LongInt($FFFFFF40));

Var
  Quit : Boolean;

Function Vt(O, I : LongInt) : Pointer;
Begin
  Vt := Pointer(PLong(PLong(O)^ + I * 4)^);
End;

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
  If M = $0002 Then
  Begin
    Quit := True;
    PostQuitMessage(0);
  End
  Else If (M = $0100) And (W = $1B) Then DestroyWindow(H)
  Else WndProc := DefWindowProcA(H, M, W, L);
End;

{ sommet K (9 mots) : position, normale, couleur, texture }
Procedure PutV(Base, K : LongInt; X, Y, Z, NX, NY, NZ : Single; C : LongInt;
               U, V : Single);
Var A : LongInt;
Begin
  A := Base + K * 36;
  PLong(A)^ := FB(X); PLong(A + 4)^ := FB(Y); PLong(A + 8)^ := FB(Z);
  PLong(A + 12)^ := FB(NX); PLong(A + 16)^ := FB(NY);
  PLong(A + 20)^ := FB(NZ); PLong(A + 24)^ := C;
  PLong(A + 28)^ := FB(U); PLong(A + 32)^ := FB(V);
End;

Var
  Wc : TWndClass;
  Msg : TMsg;
  Hw, Hi, D3, Dev, VB, IB, Tx, P, I, J, X, Y, Frame, Fails, T0, C : LongInt;
  A, NX, NZ, U, V : Single;
  Pp : Array[0..12] Of LongInt;
  Lr : Array[0..1] Of LongInt;
  Mt : Array[0..16] Of Single;
  Lt : Array[0..25] Of LongInt;
  M : TMat;

Begin
  Hi := GetModuleHandleA(0);
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.WndProc := @WndProc; Wc.Inst := Hi; Wc.ClassName := 'D3D8TEST';
  Wc.Cursor := LoadCursorA(0, 32512);
  RegisterClassA(Wc);
  Hw := CreateWindowExA(0, 'D3D8TEST', 'Direct3D 8', $10CF0000, 60, 40,
                        328, 270, 0, 0, Hi, 0);
  D3 := Direct3DCreate8(220);
  If D3 = 0 Then
  Begin
    Log('D3D8TEST: Direct3DCreate8');
    ExitProcess(1);
  End;
  FillChar(Pp, SizeOf(Pp), 0);
  Pp[5] := 1;           { D3DSWAPEFFECT_DISCARD }
  Pp[7] := 1;           { fenetre }
  Pp[8] := 1;           { tampon Z automatique }
  Pp[9] := 80;          { D3DFMT_D16 }
  If TC7(Vt(D3, 15))(D3, 0, 1, Hw, $20, LongInt(@Pp), LongInt(@Dev)) <> 0 Then
  Begin
    Log('D3D8TEST: CreateDevice');
    ExitProcess(2);
  End;
  { pyramide : 4 faces et la base }
  If (TC6(Vt(Dev, 23))(Dev, 16 * 36, 0, FVF, 1, LongInt(@VB)) <> 0) Or
     (TC6(Vt(Dev, 24))(Dev, 18 * 2, 0, 101, 1, LongInt(@IB)) <> 0) Or
     (TC8(Vt(Dev, 20))(Dev, 32, 32, 1, 0, 21, 1, LongInt(@Tx)) <> 0) Then
  Begin
    Log('D3D8TEST: ressources');
    ExitProcess(3);
  End;
  TC5(Vt(VB, 11))(VB, 0, 0, LongInt(@P), 0);
  For I := 0 To 3 Do
  Begin
    J := (I + 1) And 3;
    NX := (BX[I] + BX[J]) * 0.7; NZ := (BZ[I] + BZ[J]) * 0.7;
    PutV(P, I * 3, 0, 1.2, 0, NX, 0.5, NZ, Col[I], 0.5, 0);
    PutV(P, I * 3 + 1, BX[J], -0.8, BZ[J], NX, 0.5, NZ, Col[I], 1, 1);
    PutV(P, I * 3 + 2, BX[I], -0.8, BZ[I], NX, 0.5, NZ, Col[I], 0, 1);
  End;
  For I := 0 To 3 Do
  Begin
    If BX[I] > 0 Then U := 1 Else U := 0;
    If BZ[I] > 0 Then V := 1 Else V := 0;
    PutV(P, 12 + I, BX[I], -0.8, BZ[I], 0, -1, 0, -1, U, V);
  End;
  TC1(Vt(VB, 12))(VB);
  TC5(Vt(IB, 11))(IB, 0, 0, LongInt(@P), 0);
  For I := 0 To 11 Do PWrd(P + I * 2)^ := I;
  PWrd(P + 24)^ := 12; PWrd(P + 26)^ := 13; PWrd(P + 28)^ := 14;
  PWrd(P + 30)^ := 12; PWrd(P + 32)^ := 14; PWrd(P + 34)^ := 15;
  TC1(Vt(IB, 12))(IB);
  TC5(Vt(Tx, 16))(Tx, 0, LongInt(@Lr), 0, 0);
  For Y := 0 To 31 Do
    For X := 0 To 31 Do
    Begin
      If ((X Xor Y) And 4) <> 0 Then C := -1 Else C := LongInt($FF808080);
      PLong(Lr[1] + Y * Lr[0] + X * 4)^ := C;
    End;
  TC2(Vt(Tx, 17))(Tx, 0);
  For I := 0 To 16 Do Mt[I] := 0;
  For I := 0 To 6 Do Mt[I] := 1;
  TC2(Vt(Dev, 42))(Dev, LongInt(@Mt));
  FillChar(Lt, SizeOf(Lt), 0);
  Lt[0] := 3;
  Lt[1] := FB(1); Lt[2] := FB(1); Lt[3] := FB(1);
  Lt[16] := FB(-0.4); Lt[17] := FB(-0.6); Lt[18] := FB(1);
  TC3(Vt(Dev, 44))(Dev, 0, LongInt(@Lt));
  TC3(Vt(Dev, 46))(Dev, 0, 1);
  TC3(Vt(Dev, 50))(Dev, 139, $00404040);
  TC3(Vt(Dev, 50))(Dev, 7, 1);
  TC4(Vt(Dev, 63))(Dev, 0, 1, 4);
  TC3(Vt(Dev, 61))(Dev, 0, Tx);
  TC2(Vt(Dev, 76))(Dev, FVF);
  TC4(Vt(Dev, 83))(Dev, 0, VB, 36);
  TC3(Vt(Dev, 85))(Dev, IB, 0);
  For I := 0 To 15 Do M[I] := 0;
  M[0] := 1.3; M[5] := 1.732; M[10] := 1; M[11] := 1; M[14] := -0.1;
  TC3(Vt(Dev, 37))(Dev, 3, LongInt(@M));
  For I := 0 To 15 Do M[I] := 0;
  M[0] := 1; M[5] := 1; M[10] := 1; M[15] := 1; M[14] := 4;
  TC3(Vt(Dev, 37))(Dev, 2, LongInt(@M));
  Log('D3D8TEST: initialisation reussie');
  T0 := GetTickCount;
  Frame := 0; Fails := 0;
  While Not Quit And (GetTickCount - T0 < 30000) Do
  Begin
    While PeekMessageA(Msg, 0, 0, 0, 1) <> 0 Do
    Begin
      TranslateMessage(Msg); DispatchMessageA(Msg);
    End;
    If Quit Then Break;
    A := (GetTickCount - T0) / 800;
    For I := 0 To 15 Do M[I] := 0;
    M[0] := Cos(A); M[2] := -Sin(A); M[5] := 1; M[8] := Sin(A);
    M[10] := Cos(A); M[15] := 1;
    TC3(Vt(Dev, 37))(Dev, 256, LongInt(@M));
    TC7(Vt(Dev, 36))(Dev, 0, 0, 1 Or 2, LongInt($FF103060), FB(1), 0);
    TC1(Vt(Dev, 34))(Dev);
    If TC6(Vt(Dev, 71))(Dev, 4, 0, 16, 0, 6) <> 0 Then Inc(Fails);
    TC1(Vt(Dev, 35))(Dev);
    If TC5(Vt(Dev, 15))(Dev, 0, 0, 0, 0) <> 0 Then Inc(Fails);
    Inc(Frame);
    If Frame = 10 Then
      Log('D3D8TEST: 10 images en ' + IStr(GetTickCount - T0) +
          ' ms, echecs ' + IStr(Fails));
  End;
  Log('D3D8TEST: fin, ' + IStr(Frame) + ' images, echecs ' + IStr(Fails));
  TC1(Vt(Tx, 2))(Tx); TC1(Vt(IB, 2))(IB);
  TC1(Vt(VB, 2))(VB); TC1(Vt(Dev, 2))(Dev);
  TC1(Vt(D3, 2))(D3);
  ExitProcess(0);
End.
