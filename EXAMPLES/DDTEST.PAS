{ DDTEST.PAS - Essai de DirectDraw, DirectSound et DirectInput : plein
  ecran 640x480 en 256 couleurs avec palette, double tampon (Flip),
  Lock, remplissage par Blt, texte par GetDC, tampon DirectSound en
  boucle, clavier DirectInput (Echap pour quitter, sinon 60 secondes).

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 DDTEST.PAS DDTEST.EXE

  Les objets COM sont appeles par leur table de methodes (vtable). }

Program DDTest;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  PLong = ^LongInt;
  PByt = ^Byte;
  TC1 = Function(T : LongInt) : LongInt; stdcall;
  TC2 = Function(T, A : LongInt) : LongInt; stdcall;
  TC3 = Function(T, A, B : LongInt) : LongInt; stdcall;
  TC4 = Function(T, A, B, C : LongInt) : LongInt; stdcall;
  TC5 = Function(T, A, B, C, D : LongInt) : LongInt; stdcall;
  TC6 = Function(T, A, B, C, D, E : LongInt) : LongInt; stdcall;
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
  TGuid = Record
    D1 : LongInt;
    D2, D3 : Word;
    D4 : Array[0..7] Of Byte;
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
Function SetBkMode(Dc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function TextOutA(Dc, X, Y : LongInt; S : PChar; N : LongInt) : LongInt;
  stdcall; external 'gdi32.dll' name 'TextOutA';
Function GetModuleHandleA(N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Procedure Sleep(Ms : LongInt); stdcall;
  external 'kernel32.dll' name 'Sleep';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Function DirectDrawCreate(G : LongInt; Var DD : LongInt; O : LongInt)
  : LongInt; stdcall; external 'ddraw.dll' name 'DirectDrawCreate';
Function DirectSoundCreate(G : LongInt; Var DS : LongInt; O : LongInt)
  : LongInt; stdcall; external 'dsound.dll' name 'DirectSoundCreate';
Function DirectInputCreateA(H, V : LongInt; Var DI : LongInt; O : LongInt)
  : LongInt; stdcall; external 'dinput.dll' name 'DirectInputCreateA';

Const
  { GUID_SysKeyboard et GUID_Key (DirectInput) }
  GuidSysKbd : TGuid = (D1 : $6F1D2B61; D2 : $D5A0; D3 : $11CF;
    D4 : ($BF, $C7, $44, $45, $53, $54, $00, $00));
  GuidKey : TGuid = (D1 : $55728220; D2 : $D33C; D3 : $11CF;
    D4 : ($BF, $C7, $44, $45, $53, $54, $00, $00));

Var
  { format c_dfDIKeyboard : 256 touches d'un octet }
  KbObjs : Array[0..256 * 4 - 1] Of LongInt;
  KbFmt : Array[0..5] Of LongInt;

{ methode I de l'objet COM O }
Function Vt(O, I : LongInt) : Pointer;
Begin
  Vt := Pointer(PLong(PLong(O)^ + I * 4)^);
End;

Function WndProc(H, M, W, L : LongInt) : LongInt; stdcall;
Begin
  WndProc := 0;
  If M = $0002 Then PostQuitMessage(0)
  Else WndProc := DefWindowProcA(H, M, W, L);
End;

Procedure Text(Dc, X, Y : LongInt; S : String);
Var T : String;
Begin
  T := S + #0;
  TextOutA(Dc, X, Y, @T[1], Length(S));
End;

Var
  Wc : TWndClass;
  Msg : TMsg;
  Hw, Hi, DD, Prim, Back, Pal, DS, SB, DI, Kb, Dc, I, X, Y, Frame, T0,
    Pos, WPos, A1, A2, N1, N2, P : LongInt;
  Ok : Boolean;
  Sd : Array[0..26] Of LongInt;
  Caps : Array[0..0] Of LongInt;
  Pe : Array[0..255] Of LongInt;
  Fx : Array[0..24] Of LongInt;
  R : Array[0..3] Of LongInt;
  Wf : Array[0..4] Of LongInt;
  Bd : Array[0..4] Of LongInt;
  Keys : Array[0..255] Of Byte;

Begin
  Hi := GetModuleHandleA(0);
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.WndProc := @WndProc; Wc.Inst := Hi; Wc.ClassName := 'DDTEST';
  RegisterClassA(Wc);
  Hw := CreateWindowExA(8, 'DDTEST', 'DirectX', LongInt($90000000), 0, 0,
                        640, 480, 0, 0, Hi, 0);
  If DirectDrawCreate(0, DD, 0) <> 0 Then ExitProcess(1);
  TC3(Vt(DD, 20))(DD, Hw, $11);
  TC4(Vt(DD, 21))(DD, 640, 480, 8);
  FillChar(Sd, SizeOf(Sd), 0);
  Sd[0] := 108; Sd[1] := 1 Or $20;
  Sd[26] := $200 Or $10 Or $8;
  Sd[5] := 1;
  If TC4(Vt(DD, 6))(DD, LongInt(@Sd), LongInt(@Prim), 0) <> 0 Then
    ExitProcess(2);
  Caps[0] := 4;
  If TC3(Vt(Prim, 12))(Prim, LongInt(@Caps), LongInt(@Back)) <> 0 Then
    ExitProcess(3);
  { palette : du rouge au bleu, 0 noir et 255 blanc }
  For I := 0 To 255 Do
  Begin
    If I < 128 Then X := I * 2 Else X := 255;
    Pe[I] := X Or (I Shl 8) Or ((255 - I) Shl 16);
  End;
  Pe[0] := 0; Pe[255] := $FFFFFF;
  TC5(Vt(DD, 5))(DD, 4 Or $40, LongInt(@Pe), LongInt(@Pal), 0);
  TC2(Vt(Prim, 31))(Prim, Pal);

  { DirectSound : un tampon d'une seconde en boucle }
  SB := 0;
  If DirectSoundCreate(0, DS, 0) = 0 Then
  Begin
    TC3(Vt(DS, 6))(DS, Hw, 1);
    { PCM, mono, 22050 Hz, 8 bits }
    Wf[0] := 1 Or (1 Shl 16); Wf[1] := 22050; Wf[2] := 22050;
    Wf[3] := 1 Or (8 Shl 16); Wf[4] := 0;
    Bd[0] := 20; Bd[1] := 0; Bd[2] := 22050; Bd[3] := 0;
    Bd[4] := LongInt(@Wf);
    If TC4(Vt(DS, 3))(DS, LongInt(@Bd), LongInt(@SB), 0) = 0 Then
    Begin
      If TC8(Vt(SB, 11))(SB, 0, 22050, LongInt(@A1), LongInt(@N1),
                         LongInt(@A2), LongInt(@N2), 0) = 0 Then
      Begin
        For I := 0 To N1 - 1 Do
          PByt(A1 + I)^ := 128 + ((I Div 25) And 1) * 40;
        TC5(Vt(SB, 19))(SB, A1, N1, A2, N2);
      End;
      TC4(Vt(SB, 12))(SB, 0, 0, 1);
    End;
  End;

  { DirectInput : clavier }
  Kb := 0;
  For I := 0 To 255 Do
  Begin
    KbObjs[I * 4] := LongInt(@GuidKey);
    KbObjs[I * 4 + 1] := I;
    KbObjs[I * 4 + 2] := LongInt($8000000C) Or (I Shl 8);
    KbObjs[I * 4 + 3] := 0;
  End;
  KbFmt[0] := 24; KbFmt[1] := 16; KbFmt[2] := 2; KbFmt[3] := 256;
  KbFmt[4] := 256; KbFmt[5] := LongInt(@KbObjs);
  If DirectInputCreateA(Hi, $300, DI, 0) = 0 Then
    If TC4(Vt(DI, 3))(DI, LongInt(@GuidSysKbd), LongInt(@Kb), 0) = 0 Then
    Begin
      TC2(Vt(Kb, 11))(Kb, LongInt(@KbFmt));
      TC1(Vt(Kb, 7))(Kb);
    End;

  T0 := GetTickCount;
  Ok := True;
  Frame := 0;
  While Ok And (GetTickCount - T0 < 60000) Do
  Begin
    While PeekMessageA(Msg, 0, 0, 0, 1) <> 0 Do
    Begin
      If Msg.Msg = $0012 Then Ok := False;
      TranslateMessage(Msg); DispatchMessageA(Msg);
    End;
    { motif en diagonale, dessine directement dans le tampon arriere }
    Sd[0] := 108;
    If TC5(Vt(Back, 25))(Back, 0, LongInt(@Sd), 1, 0) = 0 Then
    Begin
      For Y := 0 To 479 Do
      Begin
        P := Sd[9] + Y * Sd[4];
        For X := 0 To 639 Do PByt(P + X)^ := (X + Y + Frame * 4) And $FE;
      End;
      TC2(Vt(Back, 32))(Back, 0);
    End;
    FillChar(Fx, SizeOf(Fx), 0);
    Fx[0] := 100; Fx[20] := 255;
    R[0] := 220 + (Frame * 3) Mod 200; R[1] := 300; R[2] := R[0] + 100;
    R[3] := 340;
    TC6(Vt(Back, 5))(Back, LongInt(@R), 0, 0, $400 Or $1000000,
                     LongInt(@Fx));
    If TC2(Vt(Back, 17))(Back, LongInt(@Dc)) = 0 Then
    Begin
      SetBkMode(Dc, 1); SetTextColor(Dc, $FFFFFF);
      Text(Dc, 180, 200, 'DirectDraw sur Pasdows 95');
      If SB <> 0 Then
      Begin
        TC3(Vt(SB, 4))(SB, LongInt(@Pos), LongInt(@WPos));
        Text(Dc, 180, 230, 'DirectSound : lecture');
      End;
      If Kb <> 0 Then Text(Dc, 180, 260, 'DirectInput : Echap pour quitter')
      Else Text(Dc, 180, 260, 'pas de DirectInput');
      TC2(Vt(Back, 26))(Back, Dc);
    End;
    TC3(Vt(Prim, 11))(Prim, 0, 1);
    If Kb <> 0 Then
      If TC3(Vt(Kb, 9))(Kb, 256, LongInt(@Keys)) = 0 Then
        If (Keys[1] And $80) <> 0 Then Ok := False;
    Sleep(20);
    Inc(Frame);
  End;
  If SB <> 0 Then TC1(Vt(SB, 18))(SB);
  TC1(Vt(Prim, 2))(Prim);
  TC1(Vt(DD, 2))(DD);
  ExitProcess(0);
End.
