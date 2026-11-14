{ DXDIAG.PAS - DirectX Diagnostic Tool pour Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 DXDIAG.PAS DXDIAG.EXE

  Comme le DXDIAG de DirectX 8, l'outil presente l'ordinateur et les
  composants DirectX dans des onglets (System, DirectX Files, Display,
  Sound, Music, Input, Network, More Help), interroge vraiment les API
  (DirectDraw 7, Direct3D 7, DirectSound, DirectInput, DirectPlay,
  Direct3D 8) et propose les tests de DirectDraw (plein ecran), de
  Direct3D (cube tournant dans une fenetre) et de DirectSound (son).
  "Save All Information..." enregistre le rapport dans un fichier texte.
  Sous Pasdows 95, toutes ces DLL sont fournies par le noyau VMM32. }

Program DxDiag;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  PLong = ^LongInt;
  PWrd = ^Word;
  PByt = ^Byte;
  TC1 = Function(T : LongInt) : LongInt; stdcall;
  TC2 = Function(T, A : LongInt) : LongInt; stdcall;
  TC3 = Function(T, A, B : LongInt) : LongInt; stdcall;
  TC4 = Function(T, A, B, C : LongInt) : LongInt; stdcall;
  TC5 = Function(T, A, B, C, D : LongInt) : LongInt; stdcall;
  TC6 = Function(T, A, B, C, D, E : LongInt) : LongInt; stdcall;
  TC7 = Function(T, A, B, C, D, E, F : LongInt) : LongInt; stdcall;
  TC9 = Function(T, A, B, C, D, E, F, G, H : LongInt) : LongInt; stdcall;
  TWndClass = Record
    Style : LongInt;
    WndProc : Pointer;
    ClsExtra, WndExtra, Inst, Icon, Cursor, Brush : LongInt;
    MenuName, ClassName : PChar;
  End;
  TMsg = Record
    Hwnd, Msg, WP, LP, Time, X, Y : LongInt;
  End;
  TRect = Record
    L, T, R, B : LongInt;
  End;
  TPaint = Record
    Hdc, Erase : LongInt;
    Rc : TRect;
    Rest : Array[0..39] Of Byte;
  End;

{ ---------------------------------------------------------------- API }

Function RegisterClassA(Var C : TWndClass) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex : LongInt; Cls, Title : PChar; Style, X, Y, W,
  H, Parent, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function ShowWindow(H, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ShowWindow';
Function UpdateWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'UpdateWindow';
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(Var M : TMsg; H, A, B : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetMessageA';
Function PeekMessageA(Var M : TMsg; H, A, B, R : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'PeekMessageA';
Function TranslateMessage(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function BeginPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function InvalidateRect(H : LongInt; R : Pointer; E : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H : LongInt; Var R : TRect) : LongInt; stdcall;
  external 'user32.dll' name 'GetClientRect';
Function MessageBoxA(H : LongInt; T, C : PChar; F : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'MessageBoxA';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function FillRect(Hdc : LongInt; Var R : TRect; Br : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'FillRect';
Function GetDC(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetDC';
Function ReleaseDC(H, D : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseDC';
Function TextOutA(Hdc, X, Y : LongInt; S : PChar; N : LongInt) : LongInt;
  stdcall; external 'gdi32.dll' name 'TextOutA';
Function SetBkMode(Hdc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
Function SetTextColor(Hdc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(S, W, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreatePen';
Function DeleteObject(H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
Function SelectObject(Hdc, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function MoveToEx(Hdc, X, Y : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'MoveToEx';
Function GdiLineTo(Hdc, X, Y : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'LineTo';
Function GetModuleHandleA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Procedure Sleep(Ms : LongInt); stdcall;
  external 'kernel32.dll' name 'Sleep';
Procedure GetLocalTime(P : Pointer); stdcall;
  external 'kernel32.dll' name 'GetLocalTime';
Procedure GlobalMemoryStatus(P : Pointer); stdcall;
  external 'kernel32.dll' name 'GlobalMemoryStatus';
Function GetVersionExA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetVersionExA';
Function GetLocaleInfoA(Lc, Ty : LongInt; P : Pointer; N : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetLocaleInfoA';
Function CreateFileA(N : PChar; A, S : LongInt; Sec : Pointer; C, F,
  T : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileA';
Function WriteFile(H : LongInt; B : Pointer; N : LongInt; Var W : LongInt;
  O : Pointer) : LongInt; stdcall; external 'kernel32.dll' name 'WriteFile';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GetSaveFileNameA(P : Pointer) : LongInt; stdcall;
  external 'comdlg32.dll' name 'GetSaveFileNameA';
Function RegOpenKeyExA(K : LongInt; S : PChar; O, Sam : LongInt;
  Var R : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(K : LongInt; N : PChar; R : Pointer;
  Var T : LongInt; D : Pointer; Var L : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';
Function midiOutGetNumDevs : LongInt; stdcall;
  external 'winmm.dll' name 'midiOutGetNumDevs';
Function waveOutGetNumDevs : LongInt; stdcall;
  external 'winmm.dll' name 'waveOutGetNumDevs';
Function DirectDrawCreateEx(G : Pointer; Var DD : LongInt; Iid : Pointer;
  O : Pointer) : LongInt; stdcall; external 'ddraw.dll' name 'DirectDrawCreateEx';
Function DirectDrawCreate(G : Pointer; Var DD : LongInt; O : Pointer)
  : LongInt; stdcall; external 'ddraw.dll' name 'DirectDrawCreate';
Function DirectSoundEnumerateA(Cb : Pointer; Ctx : LongInt) : LongInt;
  stdcall; external 'dsound.dll' name 'DirectSoundEnumerateA';
Function DirectSoundCreate(G : Pointer; Var DS : LongInt; O : Pointer)
  : LongInt; stdcall; external 'dsound.dll' name 'DirectSoundCreate';
Function DirectInputCreateA(I, V : LongInt; Var DI : LongInt; O : Pointer)
  : LongInt; stdcall; external 'dinput.dll' name 'DirectInputCreateA';
Function DirectPlayEnumerateA(Cb : Pointer; Ctx : LongInt) : LongInt;
  stdcall; external 'dplayx.dll' name 'DirectPlayEnumerateA';
Function Direct3DCreate8(V : LongInt) : LongInt; stdcall;
  external 'd3d8.dll' name 'Direct3DCreate8';

Const
  WM_DESTROY = 2; WM_PAINT = $F; WM_KEYDOWN = $100; WM_LBUTTONDOWN = $201;
  WM_LBUTTONUP = $202; WM_CLOSE = $10;
  MB_YESNO = 4; MB_ICONINFO = $40; MB_ICONQUESTION = $20; IDYES = 6;
  cFace = $C0C0C0; cWhite = $FFFFFF; cGray = $808080; cBlack = 0;
  cDark = $404040;
  NTab = 8;
  { IID_IDirectDraw7, IID_IDirect3D7, IID_IDirect3DHALDevice }
  IIDDD7 : Array[0..3] Of LongInt = ($15E65EC0, $11D23B9C, $60002FB9,
    $5BEA9797);
  IIDD3D7 : Array[0..3] Of LongInt = (LongInt($F5049E77), $11D24861,
    LongInt($A00007A4), LongInt($A82906C9));
  IIDHAL : Array[0..3] Of LongInt = (LongInt($84E63DE0), $11CF46AA,
    $00006F81, $6E1520C0);
  IIDTex7 : Array[0..3] Of LongInt = (0, 0, 0, 0);

Var
  Wnd, Inst, Tab, Down, BrFace : LongInt;
  { informations recueillies }
  SDate, SOS, SLang, SCpu, SMem, SPage, SDx, SDxVer : String;
  DName, DMfr, DChip, DMem, DMode, DDraw, D3D, DD8 : String;
  SndName, SndDrv, SndCaps, SndRate : String;
  InpDev : Array[0..7] Of String;
  InpN : LongInt;
  NetN : LongInt;
  NetSp : Array[0..7] Of String;
  TestDD, TestD3D, TestDS : String;
  Notes : Array[0..NTab - 1] Of String;

{ ------------------------------------------------------- utilitaires }

Function Pk(A : LongInt) : LongInt;
Begin
  Pk := PLong(A)^;
End;

Function PkW(A : LongInt) : LongInt;
Begin
  PkW := PWrd(A)^;
End;

Procedure Po(A, V : LongInt);
Begin
  PLong(A)^ := V;
End;

Function Vt(O, I : LongInt) : Pointer;
Begin
  Vt := Pointer(Pk(Pk(O) + I * 4));
End;

Procedure Rel(Var O : LongInt);
Begin
  If O <> 0 Then TC1(Vt(O, 2))(O);
  O := 0;
End;

Function Z(S : String) : String;
Begin
  Z := S + #0;
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function Pad2(V : LongInt) : String;
Begin
  If V < 10 Then Pad2 := '0' + IStr(V) Else Pad2 := IStr(V);
End;

{ Chaine C en memoire -> Pascal }
Function CStr(A : LongInt) : String;
Var S : String; C : LongInt;
Begin
  S := '';
  If A <> 0 Then
    While Length(S) < 200 Do
    Begin
      C := PByt(A)^;
      If C = 0 Then Break;
      S := S + Chr(C);
      Inc(A);
    End;
  CStr := S;
End;

Function Hex4(V : LongInt) : String;
Const H : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 3 DownTo 0 Do S := S + H[((V Shr (I * 4)) And 15) + 1];
  Hex4 := S;
End;

Function GetEnvironmentVariableA(N : PChar; B : Pointer; Sz : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';

Var
  Lang : LongInt;     { 0 FR, 1 EN, 2 GR, 3 IT, 4 SP (variable LANGUAGE) }

Procedure LangInit;
Var B : Array[0..63] Of Char; S, N : String;
Begin
  Lang := 0;
  N := 'LANGUAGE'#0;
  B[0] := #0;
  GetEnvironmentVariableA(@N[1], @B, 60);
  S := CStr(LongInt(@B));
  If (S <> '') And (S[1] = '"') Then S := Copy(S, 2, 255);
  S := Copy(S, 1, 2);
  If (S = 'EN') Or (S = 'en') Then Lang := 1
  Else If (S = 'GR') Or (S = 'gr') Or (S = 'DE') Or (S = 'de') Then Lang := 2
  Else If (S = 'IT') Or (S = 'it') Then Lang := 3
  Else If (S = 'SP') Or (S = 'sp') Or (S = 'ES') Or (S = 'es') Then Lang := 4;
End;

{ Texte dans la langue courante }
Function L(Fr, En, De, It, Es : String) : String;
Begin
  Case Lang Of
    1 : L := En;
    2 : L := De;
    3 : L := It;
    4 : L := Es;
  Else
    L := Fr;
  End;
End;

Procedure Zero(A, N : LongInt);
Var I : LongInt;
Begin
  For I := 0 To N - 1 Do PByt(A + I)^ := 0;
End;

{ ------------------------------------------------------ informations }

Function RegStr(Path, Name : String) : String;
Var K, T, L : LongInt; Buf : Array[0..255] Of Char; P, N : String;
Begin
  RegStr := '';
  P := Z(Path); N := Z(Name);
  If RegOpenKeyExA(LongInt($80000002), @P[1], 0, $20019, K) <> 0 Then Exit;
  L := 250; T := 0;
  Zero(LongInt(@Buf), 256);
  If RegQueryValueExA(K, @N[1], Nil, T, @Buf, L) = 0 Then
    RegStr := CStr(LongInt(@Buf));
  RegCloseKey(K);
End;

{ Processeur : publie par le noyau dans le registre (comme Windows) }
Procedure CpuInfo;
Var M : String;
Begin
  SCpu := RegStr('Hardware\Description\System\CentralProcessor\0',
                 'ProcessorNameString');
  If SCpu = '' Then SCpu := RegStr('Hardware\Description\System\' +
                                   'CentralProcessor\0', 'Identifier');
  If SCpu = '' Then SCpu := 'Intel 80486 or better';
  M := RegStr('Hardware\Description\System\CentralProcessor\0', '~MHz');
  If M <> '' Then SCpu := SCpu + ', ~' + M + 'MHz';
End;

Function Max0(V : LongInt) : LongInt;
Begin
  If V < 1 Then V := 1;
  If V > 12 Then V := 12;
  Max0 := V;
End;

Function DayName(D : LongInt) : String;
Begin
  Case D Mod 7 Of
    0 : DayName := L('dimanche', 'Sunday', 'Sonntag', 'domenica', 'domingo');
    1 : DayName := L('lundi', 'Monday', 'Montag', 'luned'#141, 'lunes');
    2 : DayName := L('mardi', 'Tuesday', 'Dienstag', 'marted'#141, 'martes');
    3 : DayName := L('mercredi', 'Wednesday', 'Mittwoch', 'mercoled'#141, 'mi'#130'rcoles');
    4 : DayName := L('jeudi', 'Thursday', 'Donnerstag', 'gioved'#141, 'jueves');
    5 : DayName := L('vendredi', 'Friday', 'Freitag', 'venerd'#141, 'viernes');
    6 : DayName := L('samedi', 'Saturday', 'Samstag', 'sabato', 's'#160'bado');
  End;
End;

Function MonthName(M : LongInt) : String;
Begin
  Case M Of
    1 : MonthName := L('janvier', 'January', 'Januar', 'gennaio', 'enero');
    2 : MonthName := L('f'#130'vrier', 'February', 'Februar', 'febbraio', 'febrero');
    3 : MonthName := L('mars', 'March', 'M'#132'rz', 'marzo', 'marzo');
    4 : MonthName := L('avril', 'April', 'April', 'aprile', 'abril');
    5 : MonthName := L('mai', 'May', 'Mai', 'maggio', 'mayo');
    6 : MonthName := L('juin', 'June', 'Juni', 'giugno', 'junio');
    7 : MonthName := L('juillet', 'July', 'Juli', 'luglio', 'julio');
    8 : MonthName := L('ao'#150't', 'August', 'August', 'agosto', 'agosto');
    9 : MonthName := L('septembre', 'September', 'September', 'settembre', 'septiembre');
    10 : MonthName := L('octobre', 'October', 'Oktober', 'ottobre', 'octubre');
    11 : MonthName := L('novembre', 'November', 'November', 'novembre', 'noviembre');
    12 : MonthName := L('d'#130'cembre', 'December', 'Dezember', 'dicembre', 'diciembre');
  Else
    MonthName := '';
  End;
End;

Procedure SysInfo;
Var T : Array[0..7] Of Word; M : Array[0..7] Of LongInt;
    V : Array[0..39] Of LongInt; Lb : Array[0..63] Of Char;
    Hm : String;
Begin
  GetLocalTime(@T);
  Hm := Pad2(T[4]) + ':' + Pad2(T[5]) + ':' + Pad2(T[6]);
  If Lang = 1 Then
    SDate := DayName(T[2]) + ', ' + MonthName(T[1]) + ' ' + IStr(T[3]) +
             ', ' + IStr(T[0]) + ', ' + Hm
  Else If Lang = 2 Then
    SDate := DayName(T[2]) + ', ' + IStr(T[3]) + '. ' + MonthName(T[1]) +
             ' ' + IStr(T[0]) + ', ' + Hm
  Else
    SDate := DayName(T[2]) + ' ' + IStr(T[3]) + ' ' + MonthName(T[1]) + ' ' +
             IStr(T[0]) + ', ' + Hm;
  Zero(LongInt(@V), 160);
  V[0] := 148;
  GetVersionExA(@V);
  SOS := 'Pasdows 95 (' + IStr(V[1]) + '.' + Pad2(V[2]) + ', ' +
         L('version ', 'Build ', 'Build ', 'build ', 'compilaci'#162'n ') +
         IStr(V[3] And $FFFF) + ')';
  Case Lang Of
    1 : SLang := 'English (Regional Setting: English)';
    2 : SLang := 'Deutsch (Gebietsschema: Deutsch)';
    3 : SLang := 'Italiano (Impostazioni internazionali: Italiano)';
    4 : SLang := 'Espa'#164'ol (Configuraci'#162'n regional: Espa'#164'ol)';
  Else
    SLang := 'Fran'#135'ais (Param'#138'tres r'#130'gionaux : Fran'#135'ais)';
  End;
  M[0] := 32;
  GlobalMemoryStatus(@M);
  SMem := IStr((M[2] + 512 * 1024) Div (1024 * 1024)) +
          L(' Mo de RAM', 'MB RAM', ' MB RAM', ' MB di RAM', ' MB de RAM');
  SPage := IStr((M[4] - M[5]) Div (1024 * 1024)) +
           L(' Mo utilis'#130's, ', 'MB used, ', ' MB belegt, ', ' MB usati, ',
             ' MB usados, ') + IStr(M[5] Div (1024 * 1024)) +
           L(' Mo disponibles', 'MB available', ' MB frei', ' MB liberi',
             ' MB libres');
  CpuInfo;
  SDxVer := RegStr('Software\Microsoft\DirectX', 'Version');
  If SDxVer = '' Then SDxVer := '4.08.00.0400';
  If Copy(SDxVer, 1, 7) = '4.08.00' Then SDx := 'DirectX 8.0'
  Else If Copy(SDxVer, 1, 4) = '4.07' Then SDx := 'DirectX 7.0'
  Else SDx := 'DirectX ' + SDxVer;
  SDx := SDx + ' (' + SDxVer + ')';
End;


{ --------------------------------------------------------- DirectX }

Function ClientToScreen(H : LongInt; Var P : TRect) : LongInt; stdcall;
  external 'user32.dll' name 'ClientToScreen';
Procedure OutputDebugStringA(P : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';

Procedure Dbg(S : String);
Begin
  S := S + #0;
  OutputDebugStringA(@S[1]);
End;

Function EnumD3D(D, N, Desc, Ctx : LongInt) : LongInt; stdcall;
Begin
  If Pos('HAL', CStr(N)) > 0 Then PLong(Ctx)^ := PLong(Ctx)^ + 1;
  EnumD3D := 1;
End;

Function EnumSnd(G, D, M, Ctx : LongInt) : LongInt; stdcall;
Begin
  If G <> 0 Then
  Begin
    SndName := CStr(D); SndDrv := CStr(M);
  End
  Else If SndName = '' Then SndName := CStr(D);
  EnumSnd := 1;
End;

Function EnumDI(P, Ctx : LongInt) : LongInt; stdcall;
Var T : LongInt; S : String;
Begin
  If InpN < 8 Then
  Begin
    T := Pk(P + 36) And 255;
    S := CStr(P + 40);
    Case T Of
      2, $12 : S := S + L(' (souris)', ' (mouse)', ' (Maus)', ' (mouse)', ' (mouse)');
      3, $13 : S := S + L(' (clavier)', ' (keyboard)', ' (Tastatur)', ' (tastiera)', ' (teclado)');
      4, $14 : S := S + L(' (manette)', ' (joystick)', ' (Joystick)', ' (joystick)', ' (joystick)');
    End;
    InpDev[InpN] := S + L(', connect'#130,
        ', attached',
        ', angeschlossen',
        ', collegato',
        ', conectado');
    Inc(InpN);
  End;
  EnumDI := 1;
End;

Function EnumDP(G, N, Ma, Mi, Ctx : LongInt) : LongInt; stdcall;
Begin
  If NetN < 8 Then
  Begin
    NetSp[NetN] := CStr(N);
    Inc(NetN);
  End;
  EnumDP := 1;
End;

Procedure DispInfo;
Var DD, D3, I, V, N, Tot, Fr : LongInt;
    Id : Array[0..279] Of LongInt; Dsc : Array[0..31] Of LongInt;
    Cp : Array[0..95] Of LongInt; Caps : Array[0..3] Of LongInt;
Begin
  DName := 'n/a'; DMfr := 'n/a'; DChip := 'n/a'; DMem := 'n/a';
  DMode := 'n/a'; DDraw := L('Non disponible',
      'Not Available',
      'Nicht verf'#129'gbar',
      'Non disponibile',
      'No disponible'); D3D := L('Non disponible',
      'Not Available',
      'Nicht verf'#129'gbar',
      'Non disponibile',
      'No disponible');
  DD := 0;
  If DirectDrawCreateEx(Nil, DD, @IIDDD7, Nil) <> 0 Then Exit;
  Zero(LongInt(@Id), SizeOf(Id));
  If TC3(Vt(DD, 27))(DD, LongInt(@Id), 0) = 0 Then
  Begin
    DName := CStr(LongInt(@Id) + 512);
    V := Id[258]; N := Id[259];
    Case V Of
      $15AD : DMfr := 'VMware, Inc.';
      $80EE : DMfr := 'Oracle (VirtualBox)';
      $1234 : DMfr := 'QEMU / Bochs';
    Else
      DMfr := L('(Types d''affichage standard)',
          '(Standard display types)',
          '(Standard-Grafikkarten)',
          '(Schede video standard)',
          '(Tipos de pantalla est'#160'ndar)');
    End;
    If V <> 0 Then
      DChip := 'PCI ' + Hex4(V) + ':' + Hex4(N)
    Else DChip := 'VESA VBE';
  End;
  Caps[0] := $4000; Caps[1] := 0; Caps[2] := 0; Caps[3] := 0;
  Tot := 0; Fr := 0;
  If TC4(Vt(DD, 23))(DD, LongInt(@Caps), LongInt(@Tot), LongInt(@Fr)) = 0
  Then DMem := IStr(Tot Div (1024 * 1024)) + '.0 MB';
  Zero(LongInt(@Dsc), SizeOf(Dsc));
  Dsc[0] := 124;
  If TC2(Vt(DD, 12))(DD, LongInt(@Dsc)) = 0 Then
    DMode := IStr(Dsc[3]) + ' x ' + IStr(Dsc[2]) + ' (' + IStr(Dsc[21]) +
             ' bit) (' + IStr(Dsc[6]) + 'Hz)';
  Zero(LongInt(@Cp), SizeOf(Cp));
  Cp[0] := 380;
  If TC3(Vt(DD, 11))(DD, LongInt(@Cp), 0) = 0 Then
    If (Cp[1] And $40) <> 0 Then DDraw := L('Activ'#130'e',
        'Enabled',
        'Aktiviert',
        'Attivata',
        'Activada');
  D3 := 0;
  If TC3(Vt(DD, 0))(DD, LongInt(@IIDD3D7), LongInt(@D3)) = 0 Then
  Begin
    I := 0;
    TC3(Vt(D3, 3))(D3, LongInt(@EnumD3D), LongInt(@I));
    If I > 0 Then D3D := L('Activ'#130'e', 'Enabled', 'Aktiviert', 'Attivata', 'Activada');
    Rel(D3);
  End;
  Rel(DD);
  I := Direct3DCreate8(220);
  If I <> 0 Then
  Begin
    DD8 := L('disponible', 'available', 'verf'#129'gbar', 'disponibile', 'disponible');
    Rel(I);
  End
  Else DD8 := L('non disponible',
      'not available',
      'nicht verf'#129'gbar',
      'non disponibile',
      'no disponible');
End;

Procedure SndInfo;
Var DS : LongInt; C : Array[0..23] Of LongInt;
Begin
  SndName := ''; SndDrv := '';
  DirectSoundEnumerateA(@EnumSnd, 0);
  If SndName = '' Then SndName := 'n/a';
  If SndDrv = '' Then SndDrv := 'n/a';
  SndCaps := 'n/a'; SndRate := 'n/a';
  DS := 0;
  If DirectSoundCreate(Nil, DS, Nil) <> 0 Then Exit;
  Zero(LongInt(@C), SizeOf(C));
  C[0] := 96;
  If TC2(Vt(DS, 4))(DS, LongInt(@C)) = 0 Then
  Begin
    If (C[1] And $20) <> 0 Then SndCaps := L('Emul'#130' (sans carte)',
        'Emulated (no hardware)',
        'Emuliert (ohne Karte)',
        'Emulato (senza scheda)',
        'Emulado (sin tarjeta)')
    Else SndCaps := L('Oui (DMA, 8/16 bits, mono/st'#130'r'#130'o)',
        'Yes (DMA, 8/16 bit, mono/stereo)',
        'Ja (DMA, 8/16 Bit, Mono/Stereo)',
        'S'#141' (DMA, 8/16 bit, mono/stereo)',
        'S'#161' (DMA, 8/16 bits, mono/est'#130'reo)');
    SndRate := IStr(C[2]) + ' - ' + IStr(C[3]) + ' Hz';
  End;
  Rel(DS);
End;

Procedure InpInfo;
Var DI : LongInt;
Begin
  InpN := 0;
  DI := 0;
  If DirectInputCreateA(Inst, $700, DI, Nil) <> 0 Then Exit;
  TC5(Vt(DI, 4))(DI, 0, LongInt(@EnumDI), 0, 1);
  Rel(DI);
End;

Procedure NetInfo;
Begin
  NetN := 0;
  DirectPlayEnumerateA(@EnumDP, 0);
End;

{ ------------------------------------------------------------ tests }

Function Ask(S : String) : Boolean;
Var T, C : String;
Begin
  T := Z(S); C := Z(L('Outil de diagnostic DirectX',
      'DirectX Diagnostic Tool',
      'DirectX-Diagnoseprogramm',
      'Strumento di diagnostica DirectX',
      'Herramienta de diagn'#162'stico de DirectX'));
  Ask := MessageBoxA(Wnd, @T[1], @C[1], MB_YESNO Or MB_ICONQUESTION) = IDYES;
End;

Procedure Info(S : String);
Var T, C : String;
Begin
  T := Z(S); C := Z(L('Outil de diagnostic DirectX',
      'DirectX Diagnostic Tool',
      'DirectX-Diagnoseprogramm',
      'Strumento di diagnostica DirectX',
      'Herramienta de diagn'#162'stico de DirectX'));
  MessageBoxA(Wnd, @T[1], @C[1], MB_ICONINFO);
End;

Procedure Pump;
Var M : TMsg;
Begin
  While PeekMessageA(M, 0, 0, 0, 1) <> 0 Do
  Begin
    TranslateMessage(M);
    DispatchMessageA(M);
  End;
End;

Procedure DoTestDD;
Var DD, Pr, Bk, Pal, I, T0, X : LongInt;
    D : Array[0..26] Of LongInt; Cp : Array[0..0] Of LongInt;
    Fx : Array[0..24] Of LongInt; Pe : Array[0..255] Of LongInt;
    R : TRect; Ok : Boolean;
Begin
  If Not Ask(L('Le fonctionnement de DirectDraw va '#136'tre test'#130'.',
      'This will test DirectDraw functionality on this device.',
      'DirectDraw wird jetzt getestet.',
      'Verr'#133' provato il funzionamento di DirectDraw.',
      'Se va a probar DirectDraw.') +
             ' ' + L('L'''#130'cran passera quelques secondes en 640x480, ',
                 'The screen will switch to 640x480, 256 colors for a few ',
                 'Der Bildschirm wechselt einige Sekunden auf 640x480, ',
                 'Lo schermo passer'#133' per alcuni secondi a 640x480, ',
                 'La pantalla pasar'#160' unos segundos a 640x480, ') +
             L('256 couleurs. Continuer ?',
                 'seconds. Continue?',
                 '256 Farben. Fortfahren?',
                 '256 colori. Continuare?',
                 '256 colores. '#168'Continuar?')) Then Exit;
  TestDD := L('Echec : DirectDraw n''a pu '#136'tre initialis'#130'.',
      'Failure: DirectDraw could not be initialized.',
      'Fehler: DirectDraw konnte nicht starten.',
      'Errore: impossibile avviare DirectDraw.',
      'Error: no se pudo iniciar DirectDraw.');
  DD := 0; Pr := 0; Bk := 0; Pal := 0;
  If DirectDrawCreate(Nil, DD, Nil) <> 0 Then Exit;
  Ok := False;
  TC3(Vt(DD, 20))(DD, Wnd, $11);
  If TC4(Vt(DD, 21))(DD, 640, 480, 8) = 0 Then
  Begin
    Zero(LongInt(@D), SizeOf(D));
    D[0] := 108; D[1] := 1 Or $20; D[5] := 1;
    D[26] := $200 Or $10 Or $8;
    If TC4(Vt(DD, 6))(DD, LongInt(@D), LongInt(@Pr), 0) = 0 Then
    Begin
      Cp[0] := 4;
      TC3(Vt(Pr, 12))(Pr, LongInt(@Cp), LongInt(@Bk));
      For I := 0 To 255 Do
        Pe[I] := ((I * 3) And 255) Or (((255 - I) And 255) Shl 8) Or
                 ((I Div 2) Shl 16);
      Pe[0] := 0; Pe[255] := $FFFFFF;
      TC5(Vt(DD, 5))(DD, 4 Or $40, LongInt(@Pe), LongInt(@Pal), 0);
      TC2(Vt(Pr, 31))(Pr, Pal);
      T0 := GetTickCount;
      While (GetTickCount - T0 < 3000) And (Bk <> 0) Do
      Begin
        Zero(LongInt(@Fx), SizeOf(Fx));
        Fx[0] := 100;
        Fx[20] := ((GetTickCount - T0) Div 20) And 127;
        TC6(Vt(Bk, 5))(Bk, 0, 0, 0, $400 Or $1000000, LongInt(@Fx));
        X := ((GetTickCount - T0) Div 6) Mod 540;
        R.L := X; R.T := 190; R.R := X + 100; R.B := 290;
        Fx[20] := 255;
        TC6(Vt(Bk, 5))(Bk, LongInt(@R), 0, 0, $400 Or $1000000, LongInt(@Fx));
        TC3(Vt(Pr, 11))(Pr, 0, 1);
        Pump;
      End;
      Ok := True;
    End;
  End;
  Rel(Pal); Rel(Bk); Rel(Pr);
  TC1(Vt(DD, 19))(DD);
  TC3(Vt(DD, 20))(DD, Wnd, 8);
  Rel(DD);
  InvalidateRect(Wnd, Nil, 1);
  Pump;
  If Not Ok Then
  Begin
    TestDD := L('Echec : le mode d''affichage est refus'#130'.',
        'Failure: the display mode could not be set.',
        'Fehler: Anzeigemodus nicht m'#148'glich.',
        'Errore: modalit'#133' video non impostata.',
        'Error: no se pudo fijar el modo.');
    Exit;
  End;
  If Ask(L('Avez-vous vu un carr'#130' blanc traverser l'''#130'cran ?',
      'Did you see a white box moving across the screen?',
      'Haben Sie ein wei'#225'es Quadrat wandern sehen?',
      'Avete visto un quadrato bianco muoversi?',
      #168'Vio un cuadrado blanco moverse?')) Then
    TestDD := L('Tous les tests ont r'#130'ussi.',
        'All tests were successful.',
        'Alle Tests waren erfolgreich.',
        'Tutte le prove sono riuscite.',
        'Todas las pruebas fueron correctas.')
  Else TestDD := L('L''utilisateur signale un '#130'chec.',
      'The user reported that the DirectDraw test failed.',
      'Laut Benutzer fehlgeschlagen.',
      'L''utente segnala un errore.',
      'El usuario indica un error.');
End;

{ Cube : 36 sommets XYZ + normale + couleur (7 valeurs) }
Var
  Cube : Array[0..36 * 7 - 1] Of Single;

Procedure CubeFace(K, AX, AY, AZ, UX, UY, UZ, VX, VY, VZ, C : LongInt);
Var I, B, V, SU, SV : LongInt;
Begin
  For I := 0 To 5 Do
  Begin
    Case I Of
      0 : Begin SU := -1; SV := 1; End;
      1 : Begin SU := 1; SV := 1; End;
      2 : Begin SU := 1; SV := -1; End;
      3 : Begin SU := -1; SV := 1; End;
      4 : Begin SU := 1; SV := -1; End;
    Else
      Begin SU := -1; SV := -1; End;
    End;
    B := (K * 6 + I) * 7;
    V := AX + UX * SU + VX * SV; Cube[B] := V;
    V := AY + UY * SU + VY * SV; Cube[B + 1] := V;
    V := AZ + UZ * SU + VZ * SV; Cube[B + 2] := V;
    V := AX; Cube[B + 3] := V;
    V := AY; Cube[B + 4] := V;
    V := AZ; Cube[B + 5] := V;
    PLong(LongInt(@Cube[B + 6]))^ := C;
  End;
End;

Function D3WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Begin
  D3WndProc := DefWindowProcA(H, M, W, LP);
End;

Procedure DoTestD3D;
Var DD, Pr, Cl, RT, ZB, D3, Dev, Hw, T0, I : LongInt;
    D : Array[0..30] Of LongInt; M : Array[0..15] Of Single;
    VP : Array[0..5] Of LongInt; Mt : Array[0..16] Of Single;
    Lt : Array[0..25] Of LongInt; R : TRect; A : Single;
    WC : TWndClass; Cls, Ttl : String; Ok : Boolean;
Begin
  If Not Ask(L('Le fonctionnement de Direct3D va '#136'tre test'#130'.',
      'This will test Direct3D functionality on this device.',
      'Direct3D wird jetzt getestet.',
      'Verr'#133' provato il funzionamento di Direct3D.',
      'Se va a probar Direct3D.') +
             ' ' + L('Un cube tournant sera dessin'#130'. Continuer ?',
                 'A rotating cube will be drawn in a window. Continue?',
                 'Ein drehender W'#129'rfel wird gezeichnet. Fortfahren?',
                 'Verr'#133' disegnato un cubo rotante. Continuare?',
                 'Se dibujar'#160' un cubo giratorio. '#168'Continuar?')) Then
    Exit;
  TestD3D := L('Echec : Direct3D n''a pu '#136'tre initialis'#130'.',
      'Failure: Direct3D could not be initialized.',
      'Fehler: Direct3D konnte nicht starten.',
      'Errore: impossibile avviare Direct3D.',
      'Error: no se pudo iniciar Direct3D.');
  Cls := Z('DxDiagD3D'); Ttl := Z(L('Test de Direct3D',
      'Direct3D Test',
      'Direct3D-Test',
      'Prova Direct3D',
      'Prueba de Direct3D'));
  WC.Style := 0; WC.WndProc := @D3WndProc; WC.ClsExtra := 0;
  WC.WndExtra := 0; WC.Inst := Inst; WC.Icon := 0;
  WC.Cursor := LoadCursorA(0, 32512); WC.Brush := 0;
  WC.MenuName := Nil; WC.ClassName := @Cls[1];
  RegisterClassA(WC);
  Hw := CreateWindowExA(0, @Cls[1], @Ttl[1], $00C80000 Or $10000000, 180,
                        100, 272, 282, Wnd, 0, Inst, 0);
  Pump;
  DD := 0; Pr := 0; Cl := 0; RT := 0; ZB := 0; D3 := 0; Dev := 0;
  Ok := False;
  If DirectDrawCreateEx(Nil, DD, @IIDDD7, Nil) = 0 Then
  Begin
    TC3(Vt(DD, 20))(DD, Hw, 8);
    Zero(LongInt(@D), SizeOf(D));
    D[0] := 124; D[1] := 1; D[26] := $200;
    TC4(Vt(DD, 6))(DD, LongInt(@D), LongInt(@Pr), 0);
    TC4(Vt(DD, 4))(DD, 0, LongInt(@Cl), 0);
    If Cl <> 0 Then
    Begin
      TC3(Vt(Cl, 8))(Cl, 0, Hw);
      If Pr <> 0 Then TC2(Vt(Pr, 28))(Pr, Cl);
    End;
    Zero(LongInt(@D), SizeOf(D));
    D[0] := 124; D[1] := 1 Or 2 Or 4 Or $1000; D[2] := 256; D[3] := 256;
    D[18] := 32; D[19] := $40; D[21] := 16; D[22] := $F800; D[23] := $7E0;
    D[24] := $1F;
    D[26] := $40 Or $2000;
    TC4(Vt(DD, 6))(DD, LongInt(@D), LongInt(@RT), 0);
    Zero(LongInt(@D), SizeOf(D));
    D[0] := 124; D[1] := 1 Or 2 Or 4 Or $1000; D[2] := 256; D[3] := 256;
    D[18] := 32; D[19] := $400; D[21] := 16; D[23] := $FFFF;
    D[26] := $20000;
    TC4(Vt(DD, 6))(DD, LongInt(@D), LongInt(@ZB), 0);
    If (RT <> 0) And (ZB <> 0) Then TC2(Vt(RT, 3))(RT, ZB);
    If (RT <> 0) And (TC3(Vt(DD, 0))(DD, LongInt(@IIDD3D7), LongInt(@D3)) = 0)
    Then TC4(Vt(D3, 4))(D3, LongInt(@IIDHAL), RT, LongInt(@Dev));
  End;
  If Dev <> 0 Then
  Begin
    VP[0] := 0; VP[1] := 0; VP[2] := 256; VP[3] := 256;
    PLong(LongInt(@VP[4]))^ := 0; PLong(LongInt(@VP[5]))^ := $3F800000;
    TC2(Vt(Dev, 13))(Dev, LongInt(@VP));
    For I := 0 To 16 Do Mt[I] := 0;
    For I := 0 To 7 Do Mt[I] := 1;
    TC2(Vt(Dev, 16))(Dev, LongInt(@Mt));
    For I := 0 To 25 Do Lt[I] := 0;
    Lt[0] := 3;
    PLong(LongInt(@Lt[1]))^ := $3F800000; PLong(LongInt(@Lt[2]))^ := $3F800000;
    PLong(LongInt(@Lt[3]))^ := $3F800000;
    PLong(LongInt(@Lt[16]))^ := $3E99999A;
    PLong(LongInt(@Lt[17]))^ := LongInt($BF000000);
    PLong(LongInt(@Lt[18]))^ := $3F800000;
    TC3(Vt(Dev, 18))(Dev, 0, LongInt(@Lt));
    TC3(Vt(Dev, 44))(Dev, 0, 1);
    TC3(Vt(Dev, 20))(Dev, 139, $00404040);
    TC3(Vt(Dev, 20))(Dev, 7, 1);
    For I := 0 To 15 Do M[I] := 0;
    M[0] := 1.732; M[5] := 1.732; M[10] := 1; M[11] := 1; M[14] := -0.1;
    TC3(Vt(Dev, 11))(Dev, 3, LongInt(@M));
    For I := 0 To 15 Do M[I] := 0;
    M[0] := 1; M[5] := 1; M[10] := 1; M[15] := 1; M[14] := 4.5;
    TC3(Vt(Dev, 11))(Dev, 2, LongInt(@M));
    CubeFace(0, 0, 0, -1, 1, 0, 0, 0, 1, 0, LongInt($FFFF4040));
    CubeFace(1, 0, 0, 1, -1, 0, 0, 0, 1, 0, LongInt($FF40FF40));
    CubeFace(2, -1, 0, 0, 0, 0, -1, 0, 1, 0, LongInt($FF4040FF));
    CubeFace(3, 1, 0, 0, 0, 0, 1, 0, 1, 0, LongInt($FFFFFF40));
    CubeFace(4, 0, 1, 0, 1, 0, 0, 0, 0, 1, LongInt($FF40FFFF));
    CubeFace(5, 0, -1, 0, 1, 0, 0, 0, 0, -1, LongInt($FFFF40FF));
    T0 := GetTickCount;
    While GetTickCount - T0 < 5000 Do
    Begin
      A := (GetTickCount - T0) / 700;
      For I := 0 To 15 Do M[I] := 0;
      M[0] := Cos(A); M[2] := -Sin(A); M[8] := Sin(A); M[10] := Cos(A);
      M[5] := 1; M[15] := 1;
      M[4] := 0;
      TC3(Vt(Dev, 11))(Dev, 1, LongInt(@M));
      TC7(Vt(Dev, 10))(Dev, 0, 0, 3, $00102040, $3F800000, 0);
      TC1(Vt(Dev, 5))(Dev);
      TC6(Vt(Dev, 25))(Dev, 4, $052, LongInt(@Cube), 36, 0);
      TC1(Vt(Dev, 6))(Dev);
      R.L := 0; R.T := 0;
      ClientToScreen(Hw, R);
      R.R := R.L + 256; R.B := R.T + 256;
      If Pr <> 0 Then
        TC6(Vt(Pr, 5))(Pr, LongInt(@R), RT, 0, $1000000, 0);
      Pump;
    End;
    Ok := True;
  End;
  Rel(Dev); Rel(D3); Rel(ZB); Rel(RT); Rel(Cl); Rel(Pr); Rel(DD);
  DestroyWindow(Hw);
  Pump;
  If Not Ok Then Exit;
  If Ask(L('Avez-vous vu un cube tourner ?',
      'Did you see a rotating cube?',
      'Haben Sie einen drehenden W'#129'rfel gesehen?',
      'Avete visto un cubo ruotare?',
      #168'Vio un cubo girar?')) Then
    TestD3D := L('Tous les tests ont r'#130'ussi.',
        'All tests were successful.',
        'Alle Tests waren erfolgreich.',
        'Tutte le prove sono riuscite.',
        'Todas las pruebas fueron correctas.')
  Else TestD3D := L('L''utilisateur signale un '#130'chec.',
      'The user reported that the Direct3D test failed.',
      'Laut Benutzer fehlgeschlagen.',
      'L''utente segnala un errore.',
      'El usuario indica un error.');
End;

Procedure DoTestDS;
Var DS, B, P1, N1, P2, N2, I, V : LongInt;
    Wf : Array[0..4] Of LongInt; Bd : Array[0..4] Of LongInt;
Begin
  If Not Ask(L('Le fonctionnement de DirectSound va '#136'tre test'#130'.',
      'This will test DirectSound functionality on this device.',
      'DirectSound wird jetzt getestet.',
      'Verr'#133' provato il funzionamento di DirectSound.',
      'Se va a probar DirectSound.') +
             ' ' + L('Un son sera jou'#130' pendant une seconde. Continuer ?',
                 'A tone will be played for one second. Continue?',
                 'Ein Ton wird eine Sekunde gespielt. Fortfahren?',
                 'Verr'#133' riprodotto un suono. Continuare?',
                 'Se oir'#160' un tono un segundo. '#168'Continuar?')) Then
    Exit;
  TestDS := L('Echec : DirectSound n''a pu '#136'tre initialis'#130'.',
      'Failure: DirectSound could not be initialized.',
      'Fehler: DirectSound konnte nicht starten.',
      'Errore: impossibile avviare DirectSound.',
      'Error: no se pudo iniciar DirectSound.');
  DS := 0; B := 0;
  If DirectSoundCreate(Nil, DS, Nil) <> 0 Then Exit;
  TC3(Vt(DS, 6))(DS, Wnd, 1);
  Zero(LongInt(@Wf), SizeOf(Wf));
  PWrd(LongInt(@Wf))^ := 1; PWrd(LongInt(@Wf) + 2)^ := 1;
  Wf[1] := 22050; Wf[2] := 44100;
  PWrd(LongInt(@Wf) + 12)^ := 2; PWrd(LongInt(@Wf) + 14)^ := 16;
  Bd[0] := 20; Bd[1] := $80; Bd[2] := 44100; Bd[3] := 0;
  Bd[4] := LongInt(@Wf);
  If TC4(Vt(DS, 3))(DS, LongInt(@Bd), LongInt(@B), 0) = 0 Then
  Begin
    If TC9(Vt(B, 11))(B, 0, 44100, LongInt(@P1), LongInt(@N1), LongInt(@P2),
                      LongInt(@N2), 0, 0) = 0 Then
    Begin
      For I := 0 To N1 Div 2 - 1 Do
      Begin
        V := Round(Sin(I * 2 * Pi * 440 / 22050) * 12000);
        If I > 20000 Then V := (V * (22050 - I)) Div 2050;
        PWrd(P1 + I * 2)^ := V And $FFFF;
      End;
      TC5(Vt(B, 19))(B, P1, N1, P2, N2);
    End;
    TC4(Vt(B, 12))(B, 0, 0, 0);
    Sleep(1200);
    TC1(Vt(B, 18))(B);
    Rel(B);
  End;
  Rel(DS);
  If Ask(L('Avez-vous entendu un son ?',
      'Did you hear a tone?',
      'Haben Sie einen Ton geh'#148'rt?',
      'Avete sentito un suono?',
      #168'Oy'#162' un tono?')) Then TestDS := L('Tous les tests ont r'#130'ussi.',
      'All tests were successful.',
      'Alle Tests waren erfolgreich.',
      'Tutte le prove sono riuscite.',
      'Todas las pruebas fueron correctas.')
  Else TestDS := L('L''utilisateur signale un '#130'chec.',
      'The user reported that the DirectSound test failed.',
      'Laut Benutzer fehlgeschlagen.',
      'L''utente segnala un errore.',
      'El usuario indica un error.');
End;

{ ------------------------------------------------------- interface }

Const
  MaxZone = 40;

Var
  DC, PenW, PenG, PenD, PenB, OldPen : LongInt;
  ZR : Array[0..MaxZone - 1] Of TRect;
  ZId : Array[0..MaxZone - 1] Of LongInt;
  ZN, CW, CH : LongInt;

Function TabName(I : LongInt) : String;
Begin
  Case I Of
    0 : TabName := L('Syst'#138'me', 'System', 'System', 'Sistema', 'Sistema');
    1 : TabName := L('Fichiers DirectX',
        'DirectX Files',
        'DirectX-Dateien',
        'File DirectX',
        'Archivos DirectX');
    2 : TabName := L('Affichage', 'Display', 'Anzeige', 'Schermo', 'Pantalla');
    3 : TabName := L('Son', 'Sound', 'Sound', 'Audio', 'Sonido');
    4 : TabName := L('Musique', 'Music', 'Musik', 'Musica', 'M'#163'sica');
    5 : TabName := L('Entr'#130'e', 'Input', 'Eingabe', 'Input', 'Entrada');
    6 : TabName := L('R'#130'seau', 'Network', 'Netzwerk', 'Rete', 'Red');
    7 : TabName := L('Plus d''aide', 'More Help', 'Weitere Hilfe', 'Altre info', 'M'#160's ayuda');
  End;
End;

Procedure Txt(X, Y : LongInt; S : String);
Begin
  If S = '' Then Exit;
  TextOutA(DC, X, Y, @S[1], Length(S));
End;

{ texte aligne a droite sur X }
Procedure TxtR(X, Y : LongInt; S : String);
Begin
  Txt(X - Length(S) * 8, Y, S);
End;

Procedure HLine(X1, X2, Y, Pen : LongInt);
Begin
  SelectObject(DC, Pen);
  MoveToEx(DC, X1, Y, Nil);
  GdiLineTo(DC, X2, Y);
End;

Procedure VLine(X, Y1, Y2, Pen : LongInt);
Begin
  SelectObject(DC, Pen);
  MoveToEx(DC, X, Y1, Nil);
  GdiLineTo(DC, X, Y2);
End;

{ Relief : saillant (boutons) ou creux }
Procedure Bevel(X1, Y1, X2, Y2 : LongInt; Raised : Boolean);
Begin
  If Raised Then
  Begin
    HLine(X1, X2, Y1, PenW); VLine(X1, Y1, Y2, PenW);
    HLine(X1, X2 + 1, Y2, PenB); VLine(X2, Y1, Y2, PenB);
    HLine(X1 + 1, X2, Y2 - 1, PenG); VLine(X2 - 1, Y1 + 1, Y2 - 1, PenG);
  End
  Else
  Begin
    HLine(X1, X2, Y1, PenG); VLine(X1, Y1, Y2, PenG);
    HLine(X1, X2 + 1, Y2, PenW); VLine(X2, Y1, Y2 + 1, PenW);
  End;
End;

Procedure Zone(X1, Y1, X2, Y2, Id : LongInt);
Begin
  If ZN >= MaxZone Then Exit;
  ZR[ZN].L := X1; ZR[ZN].T := Y1; ZR[ZN].R := X2; ZR[ZN].B := Y2;
  ZId[ZN] := Id;
  Inc(ZN);
End;

Procedure Button(X1, Y1, X2, Y2 : LongInt; S : String; Id : LongInt;
                 Enabled : Boolean);
Var X, Y : LongInt;
Begin
  X := (X1 + X2) Div 2 - Length(S) * 4;
  Y := (Y1 + Y2) Div 2 - 8;
  If Down = Id Then
  Begin
    Bevel(X1, Y1, X2, Y2, False);
    Inc(X); Inc(Y);
  End
  Else Bevel(X1, Y1, X2, Y2, True);
  If Enabled Then
  Begin
    SetTextColor(DC, cBlack);
    Txt(X, Y, S);
    Zone(X1, Y1, X2, Y2, Id);
  End
  Else
  Begin
    SetTextColor(DC, cWhite);
    Txt(X + 1, Y + 1, S);
    SetTextColor(DC, cGray);
    Txt(X, Y, S);
    SetTextColor(DC, cBlack);
  End;
End;

{ Cadre avec titre }
Procedure Group(X1, Y1, X2, Y2 : LongInt; S : String);
Var R : TRect;
Begin
  Bevel(X1, Y1 + 8, X2, Y2, False);
  Bevel(X1 + 1, Y1 + 9, X2 - 1, Y2 - 1, True);
  R.L := X1 + 6; R.T := Y1; R.R := X1 + 10 + Length(S) * 8; R.B := Y1 + 16;
  FillRect(DC, R, BrFace);
  Txt(X1 + 8, Y1, S);
End;

{ Ligne "etiquette : valeur" ; etiquettes alignees sur X }
Procedure Row(X, Y : LongInt; L, V : String);
Begin
  TxtR(X, Y, L + ':');
  Txt(X + 8, Y, V);
End;

Procedure PageNotes(X1, Y1, X2, Y2, K : LongInt);
Begin
  Group(X1, Y1, X2, Y2, L('Remarques', 'Notes', 'Hinweise', 'Note', 'Notas'));
  Txt(X1 + 16, Y1 + 22, '- ' + Notes[K]);
End;

Procedure PageSystem(X, Y, R, B : LongInt);
Begin
  Txt(X,
      Y,
      L('Cet outil fournit des informations d'#130'taill'#130'es sur les',
      'This tool reports detailed information about the DirectX',
      'Dieses Programm zeigt genaue Informationen '#129'ber die',
      'Questo strumento fornisce informazioni dettagliate sui',
      'Esta herramienta informa en detalle sobre los'));
  Txt(X,
      Y + 16,
      L('composants et pilotes DirectX install'#130's. Il permet de',
      'components and drivers installed on your system. It lets',
      'installierten DirectX-Komponenten und Treiber. Sie',
      'componenti e driver DirectX installati. Permette di',
      'componentes y controladores DirectX instalados. Permite'));
  Txt(X,
      Y + 32,
      L('tester leur fonctionnement, de diagnostiquer les probl'#138'mes',
      'you test functionality, diagnose problems, and change your',
      'k'#148'nnen damit Funktionen testen, Probleme analysieren und',
      'verificarne il funzionamento, diagnosticare i problemi e',
      'probar su funcionamiento, diagnosticar problemas y'));
  Txt(X,
      Y + 48,
      L('et de r'#130'gler la configuration du syst'#138'me.',
      'system configuration to work best.',
      'die Systemkonfiguration anpassen.',
      'ottimizzare la configurazione del sistema.',
      'ajustar la configuraci'#162'n del sistema.'));
  Txt(X,
      Y + 72,
      L('Si vous savez quelle partie pose probl'#138'me, cliquez sur',
      'If you know what area is causing the problem, click the',
      'Wenn Sie wissen, wo das Problem liegt, klicken Sie oben',
      'Se sapete dove si trova il problema, fate clic sulla',
      'Si sabe qu'#130' parte causa el problema, haga clic en la'));
  Txt(X,
      Y + 88,
      L('l''onglet correspondant. Sinon, utilisez le bouton',
      'appropriate tab above. Otherwise, you can use the "Next',
      'auf die passende Registerkarte. Andernfalls k'#148'nnen Sie',
      'scheda corrispondente. Altrimenti usate il pulsante',
      'ficha correspondiente. Si no, use el bot'#162'n "P'#160'gina'));
  Txt(X,
      Y + 104,
      L('"Page suivante" pour parcourir les pages une '#133' une.',
      'Page" button below to visit each page in sequence.',
      'mit "N'#132'chste Seite" alle Seiten nacheinander ansehen.',
      '"Pagina succ." per visitare le pagine una per una.',
      'sig." para recorrer las p'#160'ginas una a una.'));
  Group(X - 4,
      Y + 128,
      R,
      B - 22,
      L('Informations syst'#138'me',
      'System Information',
      'Systeminformationen',
      'Informazioni di sistema',
      'Informaci'#162'n del sistema'));
  Row(X + 236,
      Y + 152,
      L('Date et heure',
      'Current Date/Time',
      'Datum/Uhrzeit',
      'Data e ora',
      'Fecha y hora'),
      SDate);
  Row(X + 236,
      Y + 168,
      L('Nom de l''ordinateur',
      'Computer Name',
      'Computername',
      'Nome computer',
      'Nombre del equipo'),
      'PASDOWS');
  Row(X + 236,
      Y + 184,
      L('Syst'#138'me d''exploitation',
      'Operating System',
      'Betriebssystem',
      'Sistema operativo',
      'Sistema operativo'),
      SOS);
  Row(X + 236, Y + 200, L('Langue', 'Language', 'Sprache', 'Lingua', 'Idioma'), SLang);
  Row(X + 236,
      Y + 216,
      L('Processeur',
      'Processor',
      'Prozessor',
      'Processore',
      'Procesador'),
      SCpu);
  Row(X + 236, Y + 232, L('M'#130'moire', 'Memory', 'Speicher', 'Memoria', 'Memoria'), SMem);
  Row(X + 236,
      Y + 248,
      L('Fichier d'''#130'change',
      'Page file',
      'Auslagerungsdatei',
      'File di paging',
      'Archivo de paginaci'#162'n'),
      SPage);
  Row(X + 236,
      Y + 264,
      L('Version de DirectX',
      'DirectX Version',
      'DirectX-Version',
      'Versione DirectX',
      'Versi'#162'n de DirectX'),
      SDx);
  TxtR(R, B - 18, 'DxDiag ' + SDxVer + '  Pasdows 95');
End;

Procedure PageFiles(X, Y, R, B : LongInt);
Const
  F : Array[0..10] Of String[12] = ('ddraw.dll', 'd3dim.dll',
    'd3dim700.dll', 'd3d8.dll', 'dsound.dll', 'dinput.dll', 'dinput8.dll',
    'dplayx.dll', 'dplay.dll', 'dsetup.dll', 'dxdiag.exe');
Var I : LongInt;
Begin
  Group(X - 4,
      Y,
      R,
      B - 76,
      L('Fichiers DirectX',
      'DirectX Files',
      'DirectX-Dateien',
      'File DirectX',
      'Archivos DirectX'));
  Txt(X + 8, Y + 20, L('Nom', 'Name', 'Name', 'Nome', 'Nombre'));
  Txt(X + 136, Y + 20, 'Version');
  Txt(X + 264, Y + 20, L('Attributs', 'Attributes', 'Attribute', 'Attributi', 'Atributos'));
  Txt(X + 400, Y + 20, L('Module', 'Module', 'Modul', 'Modulo', 'M'#162'dulo'));
  HLine(X + 4, R - 8, Y + 37, PenG);
  For I := 0 To 10 Do
  Begin
    Txt(X + 8, Y + 42 + I * 16, F[I]);
    Txt(X + 136, Y + 42 + I * 16, SDxVer);
    Txt(X + 264,
        Y + 42 + I * 16,
        L('Version finale',
        'Final Retail',
        'Endversion',
        'Versione finale',
        'Versi'#162'n final'));
    If I = 10 Then Txt(X + 400, Y + 42 + I * 16, 'DXDIAG.EXE')
    Else Txt(X + 400, Y + 42 + I * 16, 'VMM32.VXD');
  End;
  PageNotes(X - 4, B - 70, R, B, 1);
End;

Procedure PageDisplay(X, Y, R, B : LongInt);
Begin
  Group(X - 4,
      Y,
      R,
      Y + 128,
      L('P'#130'riph'#130'rique',
      'Device',
      'Ger'#132't',
      'Periferica',
      'Dispositivo'));
  Row(X + 148, Y + 20, L('Nom', 'Name', 'Name', 'Nome', 'Nombre'), DName);
  Row(X + 148,
      Y + 36,
      L('Fabricant',
      'Manufacturer',
      'Hersteller',
      'Produttore',
      'Fabricante'),
      DMfr);
  Row(X + 148,
      Y + 52,
      L('Type de puce',
      'Chip Type',
      'Chiptyp',
      'Tipo di chip',
      'Tipo de chip'),
      DChip);
  Row(X + 148,
      Y + 68,
      L('M'#130'moire vid'#130'o',
      'Display Memory',
      'Grafikspeicher',
      'Memoria video',
      'Memoria de v'#161'deo'),
      DMem);
  Row(X + 148,
      Y + 84,
      L('Mode actuel',
      'Current Mode',
      'Aktueller Modus',
      'Modalit'#133' attuale',
      'Modo actual'),
      DMode);
  Row(X + 148,
      Y + 100,
      L('Pilote',
      'Driver',
      'Treiber',
      'Driver',
      'Controlador'),
      'vmm32.vxd ' + SDxVer + ', DDI 8, ' +
      'Direct3D 8 ' + DD8);
  Group(X - 4,
      Y + 136,
      R,
      B - 76,
      L('Fonctions DirectX',
      'DirectX Features',
      'DirectX-Funktionen',
      'Funzionalit'#133' DirectX',
      'Caracter'#161'sticas DirectX'));
  Row(X + 220,
      Y + 160,
      L('Acc'#130'l'#130'ration DirectDraw',
      'DirectDraw Acceleration',
      'DirectDraw-Beschleunigung',
      'Accelerazione DirectDraw',
      'Aceleraci'#162'n DirectDraw'),
      DDraw);
  Row(X + 220,
      Y + 182,
      L('Acc'#130'l'#130'ration Direct3D',
      'Direct3D Acceleration',
      'Direct3D-Beschleunigung',
      'Accelerazione Direct3D',
      'Aceleraci'#162'n Direct3D'),
      D3D);
  Row(X + 220,
      Y + 204,
      L('Acc'#130'l'#130'ration AGP',
      'AGP Texture Acceleration',
      'AGP-Texturbeschleunigung',
      'Accelerazione AGP',
      'Aceleraci'#162'n AGP'),
      L('Non disponible',
      'Not Available',
      'Nicht verf'#129'gbar',
      'Non disponibile',
      'No disponible'));
  Button(R - 150,
      Y + 156,
      R - 12,
      Y + 178,
      L('Tester DirectDraw',
      'Test DirectDraw',
      'DirectDraw testen',
      'Prova DirectDraw',
      'Probar DirectDraw'),
      10,
      True);
  Button(R - 150,
      Y + 182,
      R - 12,
      Y + 204,
      L('Tester Direct3D',
      'Test Direct3D',
      'Direct3D testen',
      'Prova Direct3D',
      'Probar Direct3D'),
      11,
      True);
  Group(X - 4, B - 70, R, B, L('Remarques', 'Notes', 'Hinweise', 'Note', 'Notas'));
  Txt(X + 12,
      B - 48,
      L('- Test DirectDraw : ',
      '- DirectDraw test: ',
      '- DirectDraw-Test: ',
      '- Prova DirectDraw: ',
      '- Prueba DirectDraw: ') + TestDD);
  Txt(X + 12,
      B - 32,
      L('- Test Direct3D : ',
      '- Direct3D test: ',
      '- Direct3D-Test: ',
      '- Prova Direct3D: ',
      '- Prueba Direct3D: ') + TestD3D);
End;

Procedure PageSound(X, Y, R, B : LongInt);
Begin
  Group(X - 4,
      Y,
      R,
      Y + 112,
      L('P'#130'riph'#130'rique',
      'Device',
      'Ger'#132't',
      'Periferica',
      'Dispositivo'));
  Row(X + 160,
      Y + 20,
      L('Description',
      'Description',
      'Beschreibung',
      'Descrizione',
      'Descripci'#162'n'),
      SndName);
  Row(X + 160, Y + 36, L('Pilote', 'Driver', 'Treiber', 'Driver', 'Controlador'), SndDrv);
  Row(X + 160,
      Y + 52,
      L('Mixage mat'#130'riel',
      'Hardware Mixing',
      'Hardware-Mischung',
      'Mixaggio hardware',
      'Mezcla por hardware'),
      SndCaps);
  Row(X + 160,
      Y + 68,
      L('Fr'#130'quences d'''#130'ch.',
      'Sample Rates',
      'Abtastraten',
      'Frequenze',
      'Frecuencias'),
      SndRate);
  Row(X + 160,
      Y + 84,
      L('Type',
      'Device Type',
      'Ger'#132'tetyp',
      'Tipo',
      'Tipo'),
      L('VxD (noyau de Pasdows 95)',
      'VxD (Pasdows 95 kernel)',
      'VxD (Pasdows 95-Kernel)',
      'VxD (nucleo di Pasdows 95)',
      'VxD (n'#163'cleo de Pasdows 95)'));
  Group(X - 4,
      Y + 120,
      R,
      B - 76,
      L('Fonctions DirectX',
      'DirectX Features',
      'DirectX-Funktionen',
      'Funzionalit'#133' DirectX',
      'Caracter'#161'sticas DirectX'));
  Row(X + 260,
      Y + 144,
      L('Acc'#130'l'#130'ration du son',
      'Hardware Sound Acceleration',
      'Sound-Beschleunigung',
      'Accelerazione audio',
      'Aceleraci'#162'n de sonido'),
      L('Compl'#138'te',
      'Full',
      'Vollst'#132'ndig',
      'Completa',
      'Completa'));
  Row(X + 260,
      Y + 166,
      'DirectSound 3D',
      L('Logiciel (3D logiciel)',
      'Software (software 3D)',
      'Software (3D per Software)',
      'Software (3D software)',
      'Software (3D por software)'));
  Button(R - 160,
      Y + 184,
      R - 12,
      Y + 206,
      L('Tester DirectSound',
      'Test DirectSound',
      'DirectSound testen',
      'Prova DirectSound',
      'Probar DirectSound'),
      12,
      True);
  Group(X - 4, B - 70, R, B, L('Remarques', 'Notes', 'Hinweise', 'Note', 'Notas'));
  Txt(X + 12,
      B - 48,
      L('- Test DirectSound : ',
      '- DirectSound test: ',
      '- DirectSound-Test: ',
      '- Prova DirectSound: ',
      '- Prueba DirectSound: ') + TestDS);
End;

Procedure PageMusic(X, Y, R, B : LongInt);
Begin
  Group(X - 4, Y, R, Y + 80, L('G'#130'n'#130'ral', 'General', 'Allgemein', 'Generale', 'General'));
  Row(X + 160,
      Y + 20,
      L('Port par d'#130'faut',
      'Default Port',
      'Standardanschluss',
      'Porta predefinita',
      'Puerto predeterminado'),
      L('Synth'#130'tiseur FM Pasdows (AdLib)',
      'Pasdows FM synthesizer (AdLib)',
      'Pasdows FM-Synthesizer (AdLib)',
      'Sintetizzatore FM Pasdows (AdLib)',
      'Sintetizador FM Pasdows (AdLib)'));
  Row(X + 160,
      Y + 36,
      L('P'#130'riph'#130'riques MIDI',
      'MIDI Devices',
      'MIDI-Ger'#132'te',
      'Periferiche MIDI',
      'Dispositivos MIDI'),
      IStr(midiOutGetNumDevs));
  Row(X + 160,
      Y + 52,
      L('P'#130'riph'#130'riques Wave',
      'Wave Devices',
      'Wave-Ger'#132'te',
      'Periferiche Wave',
      'Dispositivos Wave'),
      IStr(waveOutGetNumDevs));
  Group(X - 4,
      Y + 88,
      R,
      B - 76,
      L('Ports de musique',
      'Music Ports',
      'Musikanschl'#129'sse',
      'Porte musicali',
      'Puertos de m'#163'sica'));
  Txt(X + 8,
      Y + 110,
      L('Synth'#130'tiseur FM Pasdows : sortie, MIDI (MMSYSTEM),',
      'Pasdows FM synthesizer: Output, MIDI (MMSYSTEM),',
      'Pasdows FM-Synthesizer: Ausgabe, MIDI (MMSYSTEM),',
      'Sintetizzatore FM Pasdows: uscita, MIDI (MMSYSTEM),',
      'Sintetizador FM Pasdows: salida, MIDI (MMSYSTEM),'));
  Txt(X + 8,
      Y + 126,
      L('  9 voix, compatible OPL2.',
      '  9 voices, OPL2 compatible.',
      '  9 Stimmen, OPL2-kompatibel.',
      '  9 voci, compatibile OPL2.',
      '  9 voces, compatible OPL2.'));
  Txt(X + 8,
      Y + 150,
      L('DirectMusic : non install'#130' (le MIDI passe par',
      'DirectMusic: not installed (MIDI goes through the',
      'DirectMusic: nicht installiert (MIDI '#129'ber die',
      'DirectMusic: non installato (il MIDI usa',
      'DirectMusic: no instalado (el MIDI usa'));
  Txt(X + 8,
      Y + 166,
      L('  l''API multim'#130'dia midiOut).',
      '  Windows multimedia midiOut API).',
      '  Multimedia-API midiOut).',
      '  l''API multimediale midiOut).',
      '  la API multimedia midiOut).'));
  PageNotes(X - 4, B - 70, R, B, 4);
End;

Procedure PageInput(X, Y, R, B : LongInt);
Var I : LongInt;
Begin
  Group(X - 4,
      Y,
      R,
      Y + 128,
      L('P'#130'riph'#130'riques DirectInput',
      'DirectInput Devices',
      'DirectInput-Ger'#132'te',
      'Periferiche DirectInput',
      'Dispositivos DirectInput'));
  If InpN = 0 Then Txt(X + 8,
      Y + 22,
      L('Aucun p'#130'riph'#130'rique DirectInput.',
      'No DirectInput devices.',
      'Keine DirectInput-Ger'#132'te.',
      'Nessuna periferica DirectInput.',
      'Ning'#163'n dispositivo DirectInput.'));
  For I := 0 To InpN - 1 Do Txt(X + 8, Y + 22 + I * 16, InpDev[I]);
  Group(X - 4,
      Y + 136,
      R,
      B - 76,
      L('P'#130'riph'#130'riques d''entr'#130'e',
      'Input Related Devices',
      'Eingabeger'#132'te',
      'Periferiche di input',
      'Dispositivos de entrada'));
  Txt(X + 8,
      Y + 158,
      L('+ P'#130'riph'#130'riques PS/2',
      '+ PS/2 Devices',
      '+ PS/2-Ger'#132'te',
      '+ Periferiche PS/2',
      '+ Dispositivos PS/2'));
  Txt(X + 8,
      Y + 174,
      L('    Clavier standard 101/102 touches',
      '    Standard 101/102-key Keyboard',
      '    Standardtastatur 101/102 Tasten',
      '    Tastiera standard 101/102 tasti',
      '    Teclado est'#160'ndar de 101/102 teclas'));
  Txt(X + 8,
      Y + 190,
      L('    Souris compatible PS/2',
      '    PS/2 Compatible Mouse',
      '    PS/2-kompatible Maus',
      '    Mouse compatibile PS/2',
      '    Mouse compatible PS/2'));
  Txt(X + 8,
      Y + 206,
      L('+ Port de jeu : aucun',
      '+ Gameport Devices: none',
      '+ Gameport-Ger'#132'te: keine',
      '+ Porta giochi: nessuna',
      '+ Puerto de juegos: ninguno'));
  PageNotes(X - 4, B - 70, R, B, 5);
End;

Procedure PageNetwork(X, Y, R, B : LongInt);
Var I : LongInt;
Begin
  Group(X - 4,
      Y,
      R,
      Y + 112,
      L('Fournisseurs de services DirectPlay',
      'DirectPlay Service Providers',
      'DirectPlay-Dienstanbieter',
      'Provider di servizi DirectPlay',
      'Proveedores de servicios DirectPlay'));
  If NetN = 0 Then
    Txt(X + 8,
        Y + 22,
        L('Aucun fournisseur DirectPlay n''est inscrit.',
        'No DirectPlay service providers are registered.',
        'Keine DirectPlay-Dienstanbieter registriert.',
        'Nessun provider DirectPlay registrato.',
        'No hay proveedores DirectPlay registrados.'));
  For I := 0 To NetN - 1 Do Txt(X + 8, Y + 22 + I * 16, NetSp[I]);
  Group(X - 4,
      Y + 120,
      R,
      B - 76,
      L('Applications DirectPlay inscrites',
      'Registered Lobbyable Applications',
      'Registrierte Lobby-Anwendungen',
      'Applicazioni lobby registrate',
      'Aplicaciones de lobby registradas'));
  Txt(X + 8, Y + 142, L('Aucune.', 'None.', 'Keine.', 'Nessuna.', 'Ninguna.'));
  Button(R - 150,
      B - 104,
      R - 12,
      B - 82,
      L('Tester DirectPlay',
      'Test DirectPlay',
      'DirectPlay testen',
      'Prova DirectPlay',
      'Probar DirectPlay'),
      13,
      True);
  PageNotes(X - 4, B - 70, R, B, 6);
End;

Procedure PageHelp(X, Y, R, B : LongInt);
Begin
  Txt(X,
      Y,
      L('Pour plus d''aide, utilisez les boutons ci-dessous.',
      'For additional help, use the buttons below.',
      'Weitere Hilfe erhalten Sie mit den Schaltfl'#132'chen unten.',
      'Per altro aiuto usate i pulsanti qui sotto.',
      'Para m'#160's ayuda, use los botones siguientes.'));
  Button(X,
      Y + 30,
      X + 140,
      Y + 54,
      L('D'#130'panner',
      'Troubleshoot',
      'Probleml'#148'sung',
      'Risoluzione',
      'Solucionar'),
      20,
      True);
  Txt(X + 152,
      Y + 34,
      L('Lancer le d'#130'panneur DirectX.',
      'Start the DirectX Troubleshooter.',
      'DirectX-Probleml'#148'sung starten.',
      'Avvia la risoluzione problemi DirectX.',
      'Iniciar el solucionador de DirectX.'));
  Button(X, Y + 64, X + 140, Y + 88, L('Son', 'Sound', 'Sound', 'Audio', 'Sonido'), 21, True);
  Txt(X + 152,
      Y + 68,
      L('Lancer le d'#130'panneur du son.',
      'Start the Sound Troubleshooter.',
      'Sound-Probleml'#148'sung starten.',
      'Avvia la risoluzione problemi audio.',
      'Iniciar el solucionador de sonido.'));
  Button(X, Y + 98, X + 140, Y + 122, 'MSInfo', 22, False);
  Txt(X + 152,
      Y + 102,
      L('Informations syst'#138'me (non disponible).',
      'System Information (not available).',
      'Systeminformationen (nicht verf'#129'gbar).',
      'Informazioni di sistema (non disponibile).',
      'Informaci'#162'n del sistema (no disponible).'));
  Button(X,
      Y + 132,
      X + 140,
      Y + 156,
      L('Forcer',
      'Override',
      #154'berschreiben',
      'Forza',
      'Forzar'),
      23,
      True);
  Txt(X + 152,
      Y + 136,
      L('Forcer la fr'#130'quence de DirectDraw.',
      'Override the DirectDraw refresh rate.',
      'DirectDraw-Bildfrequenz festlegen.',
      'Forza la frequenza di DirectDraw.',
      'Forzar la frecuencia de DirectDraw.'));
End;

Procedure Paint;
Var P : TPaint; Rc : TRect; I, X, W, Y0, PB : LongInt;
Begin
  DC := BeginPaint(Wnd, P);
  GetClientRect(Wnd, Rc);
  CW := Rc.R; CH := Rc.B;
  FillRect(DC, Rc, BrFace);
  SetBkMode(DC, 1);
  SetTextColor(DC, cBlack);
  ZN := 0;
  PB := CH - 44;
  { onglets }
  X := 8;
  For I := 0 To NTab - 1 Do
  Begin
    W := Length(TabName(I)) * 8 + 8;
    If I = Tab Then Y0 := 4 Else Y0 := 7;
    HLine(X + 2, X + W - 2, Y0, PenW);
    VLine(X, Y0 + 2, 28, PenW);
    MoveToEx(DC, X, Y0 + 2, Nil); GdiLineTo(DC, X + 2, Y0);
    VLine(X + W - 1, Y0 + 2, 28, PenB);
    VLine(X + W - 2, Y0 + 1, 28, PenG);
    Txt(X + 4, Y0 + 3, TabName(I));
    Zone(X, Y0, X + W, 28, 100 + I);
    X := X + W;
  End;
  { cadre de la page }
  HLine(6, CW - 6, 28, PenW);
  VLine(6, 28, PB, PenW);
  HLine(6, CW - 6, PB, PenB); VLine(CW - 6, 28, PB + 1, PenB);
  HLine(7, CW - 7, PB - 1, PenG); VLine(CW - 7, 29, PB, PenG);
  { trait de l'onglet actif ouvert sur la page }
  X := 8;
  For I := 0 To Tab - 1 Do X := X + Length(TabName(I)) * 8 + 8;
  HLine(X + 1, X + Length(TabName(Tab)) * 8 + 6, 28, PenD);
  SelectObject(DC, PenD);
  Rc.L := X + 1; Rc.T := 27; Rc.R := X + Length(TabName(Tab)) * 8 + 6;
  Rc.B := 29;
  FillRect(DC, Rc, BrFace);
  Case Tab Of
    0 : PageSystem(18, 40, CW - 16, PB - 10);
    1 : PageFiles(18, 38, CW - 16, PB - 10);
    2 : PageDisplay(18, 38, CW - 16, PB - 10);
    3 : PageSound(18, 38, CW - 16, PB - 10);
    4 : PageMusic(18, 38, CW - 16, PB - 10);
    5 : PageInput(18, 38, CW - 16, PB - 10);
    6 : PageNetwork(18, 38, CW - 16, PB - 10);
  Else
    PageHelp(24, 44, CW - 16, PB - 10);
  End;
  { boutons du bas }
  Button(8, CH - 36, 108, CH - 10, L('Aide', 'Help', 'Hilfe', '?', 'Ayuda'), 1, True);
  Button(CW - 438,
      CH - 36,
      CW - 318,
      CH - 10,
      L('Page suivante',
      'Next Page',
      'N'#132'chste Seite',
      'Pagina succ.',
      'P'#160'gina sig.'),
      2,
      True);
  Button(CW - 310,
      CH - 36,
      CW - 110,
      CH - 10,
      L('Enregistrer les infos...',
      'Save All Information...',
      'Alle Infos speichern...',
      'Salva informazioni...',
      'Guardar informaci'#162'n...'),
         3, True);
  Button(CW - 102,
      CH - 36,
      CW - 8,
      CH - 10,
      L('Quitter',
      'Exit',
      'Beenden',
      'Esci',
      'Salir'),
      4,
      True);
  SelectObject(DC, OldPen);
  EndPaint(Wnd, P);
End;

{ ------------------------------------------------------ rapport }

Var
  RepH : LongInt;

Procedure RepL(S : String);
Var N : LongInt;
Begin
  S := S + #13#10;
  WriteFile(RepH, @S[1], Length(S), N, Nil);
End;

Procedure SaveReport;
Var Ofn : Array[0..19] Of LongInt; Fn : Array[0..259] Of Char; S, Flt,
    Ext : String;
    I : LongInt;
Begin
  S := 'DxDiag.txt';
  For I := 0 To 259 Do Fn[I] := #0;
  For I := 1 To Length(S) Do Fn[I - 1] := S[I];
  Flt := 'Text File'#0'*.txt'#0#0;
  Ext := Z('txt');
  For I := 0 To 19 Do Ofn[I] := 0;
  Ofn[0] := 76; Ofn[1] := Wnd; Ofn[3] := LongInt(@Flt[1]);
  Ofn[7] := LongInt(@Fn); Ofn[8] := 260; Ofn[13] := $2;
  Ofn[15] := LongInt(@Ext[1]);
  If GetSaveFileNameA(@Ofn) = 0 Then Exit;
  RepH := CreateFileA(@Fn, $40000000, 0, Nil, 2, $80, 0);
  If RepH = -1 Then
  Begin
    Info(L('Le fichier n''a pu '#136'tre cr'#130#130'.',
        'The file could not be created.',
        'Die Datei konnte nicht erstellt werden.',
        'Impossibile creare il file.',
        'No se pudo crear el archivo.'));
    Exit;
  End;
  RepL('------------------');
  RepL(L('Informations syst'#138'me',
      'System Information',
      'Systeminformationen',
      'Informazioni di sistema',
      'Informaci'#162'n del sistema'));
  RepL('------------------');
  RepL('Time of this report: ' + SDate);
  RepL('     Operating System: ' + SOS);
  RepL('             Language: ' + SLang);
  RepL('            Processor: ' + SCpu);
  RepL('               Memory: ' + SMem);
  RepL('            Page File: ' + SPage);
  RepL('      DirectX Version: ' + SDx);
  RepL('       DxDiag Version: ' + SDxVer);
  RepL('');
  RepL('---------------');
  RepL('Display Devices');
  RepL('---------------');
  RepL('        Card name: ' + DName);
  RepL('     Manufacturer: ' + DMfr);
  RepL('        Chip type: ' + DChip);
  RepL('   Display Memory: ' + DMem);
  RepL('     Current Mode: ' + DMode);
  RepL('      Driver Name: vmm32.vxd');
  RepL('   Driver Version: ' + SDxVer);
  RepL('    DDraw Status: ' + DDraw);
  RepL('      D3D Status: ' + D3D);
  RepL('     Direct3D 8 : ' + DD8);
  RepL('     DDraw Test : ' + TestDD);
  RepL('      D3D Test  : ' + TestD3D);
  RepL('');
  RepL('-------------');
  RepL('Sound Devices');
  RepL('-------------');
  RepL('      Description: ' + SndName);
  RepL('      Driver Name: ' + SndDrv);
  RepL('  Hardware Mixing: ' + SndCaps);
  RepL('     Sample Rates: ' + SndRate);
  RepL('  DirectSound Test: ' + TestDS);
  RepL('');
  RepL('---------------------');
  RepL(L('P'#130'riph'#130'riques DirectInput',
      'DirectInput Devices',
      'DirectInput-Ger'#132'te',
      'Periferiche DirectInput',
      'Dispositivos DirectInput'));
  RepL('---------------------');
  For I := 0 To InpN - 1 Do RepL('      ' + InpDev[I]);
  RepL('');
  RepL('----------------------------');
  RepL(L('Fournisseurs de services DirectPlay',
      'DirectPlay Service Providers',
      'DirectPlay-Dienstanbieter',
      'Provider di servizi DirectPlay',
      'Proveedores de servicios DirectPlay'));
  RepL('----------------------------');
  If NetN = 0 Then RepL('      (none)');
  For I := 0 To NetN - 1 Do RepL('      ' + NetSp[I]);
  CloseHandle(RepH);
  Info(L('Les informations ont '#130't'#130' enregistr'#130'es.',
      'The information was saved.',
      'Die Informationen wurden gespeichert.',
      'Le informazioni sono state salvate.',
      'La informaci'#162'n se ha guardado.'));
End;

{ ------------------------------------------------------- actions }

Procedure Action(Id : LongInt);
Begin
  Case Id Of
    1 : Info(L('Outil de diagnostic DirectX de Pasdows 95. Chaque onglet d'#130'crit une partie de DirectX ; les boutons de test des onglets Affichage et Son v'#130'rifient DirectDraw, Direct3D et DirectSound.',
        'DirectX Diagnostic Tool for Pasdows 95. Each tab describes one part of DirectX; the Test buttons of the Display and Sound tabs verify DirectDraw, Direct3D and DirectSound.',
        'DirectX-Diagnoseprogramm von Pasdows 95. Jede Seite beschreibt einen Teil von DirectX; die Testschaltfl'#132'chen der Seiten Anzeige und Sound pr'#129'fen DirectDraw, Direct3D und DirectSound.',
        'Strumento di diagnostica DirectX di Pasdows 95. Ogni scheda descrive una parte di DirectX; i pulsanti di prova delle schede Schermo e Audio verificano DirectDraw, Direct3D e DirectSound.',
        'Herramienta de diagn'#162'stico de DirectX de Pasdows 95. Cada ficha describe una parte de DirectX; los botones de prueba de Pantalla y Sonido verifican DirectDraw, Direct3D y DirectSound.'));
    2 :
    Begin
      Tab := (Tab + 1) Mod NTab;
      InvalidateRect(Wnd, Nil, 1);
    End;
    3 : SaveReport;
    4 : DestroyWindow(Wnd);
    10 : DoTestDD;
    11 : DoTestD3D;
    12 : DoTestDS;
    13 : Info(L('Aucun fournisseur DirectPlay n''est install'#130' : rien '#133' tester.',
        'No DirectPlay service provider is installed: there is nothing to test.',
        'Kein DirectPlay-Dienstanbieter installiert: nichts zu testen.',
        'Nessun provider DirectPlay installato: niente da provare.',
        'No hay proveedores DirectPlay: nada que probar.'));
    20 : Info(L('D'#130'panneur DirectX : aucun probl'#138'me trouv'#130'. Si un programme '#130'choue, lancez les tests des onglets Affichage et Son.',
        'DirectX Troubleshooter: no problems were found. If a program fails, run the Display and Sound tests.',
        'DirectX-Probleml'#148'sung: keine Probleme gefunden. Wenn ein Programm versagt, starten Sie die Tests der Seiten Anzeige und Sound.',
        'Risoluzione DirectX: nessun problema. Se un programma non funziona, eseguite le prove delle schede Schermo e Audio.',
        'Solucionador de DirectX: sin problemas. Si un programa falla, realice las pruebas de Pantalla y Sonido.'));
    21 : Info(L('D'#130'panneur du son : v'#130'rifiez que la Sound Blaster figure dans le Gestionnaire de p'#130'riph'#130'riques et que le volume est mont'#130'.',
        'Sound Troubleshooter: check that the Sound Blaster is present in the Device Manager and that the volume is up.',
        'Sound-Probleml'#148'sung: pr'#129'fen Sie, ob die Sound Blaster im Ger'#132'te-Manager steht und die Lautst'#132'rke aufgedreht ist.',
        'Risoluzione audio: verificate che la Sound Blaster sia nella Gestione periferiche e che il volume sia alto.',
        'Solucionador de sonido: compruebe que la Sound Blaster est'#160' en el Administrador de dispositivos y que el volumen est'#160' alto.'));
    23 : Info(L('La fr'#130'quence est fix'#130'e '#133' 60 Hz par Pasdows 95.',
        'The refresh rate is fixed at 60 Hz by Pasdows 95.',
        'Die Bildfrequenz ist in Pasdows 95 fest 60 Hz.',
        'La frequenza '#138' fissata a 60 Hz da Pasdows 95.',
        'Pasdows 95 fija la frecuencia en 60 Hz.'));
  Else
    If (Id >= 100) And (Id < 100 + NTab) Then
    Begin
      Tab := Id - 100;
      InvalidateRect(Wnd, Nil, 1);
    End;
  End;
  InvalidateRect(Wnd, Nil, 1);
End;

Function HitZone(X, Y : LongInt) : LongInt;
Var I : LongInt;
Begin
  HitZone := 0;
  For I := 0 To ZN - 1 Do
    If (X >= ZR[I].L) And (X < ZR[I].R) And (Y >= ZR[I].T) And
       (Y < ZR[I].B) Then
    Begin
      HitZone := ZId[I];
      Exit;
    End;
End;

Function WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var Id : LongInt;
Begin
  WndProc := 0;
  Case M Of
    WM_PAINT : Paint;
    WM_LBUTTONDOWN :
    Begin
      Down := HitZone(LP And $FFFF, (LP Shr 16) And $FFFF);
      If (Down >= 100) Then
      Begin
        Action(Down);
        Down := 0;
      End
      Else If Down <> 0 Then InvalidateRect(Wnd, Nil, 0);
    End;
    WM_LBUTTONUP :
    Begin
      Id := Down;
      Down := 0;
      If Id <> 0 Then
      Begin
        InvalidateRect(Wnd, Nil, 0);
        If HitZone(LP And $FFFF, (LP Shr 16) And $FFFF) = Id Then Action(Id);
      End;
    End;
    WM_KEYDOWN :
      If W = 27 Then DestroyWindow(H)
      Else If W = 9 Then Action(2);
    WM_DESTROY : PostQuitMessage(0);
  Else
    WndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

Var
  WC : TWndClass;
  Msg : TMsg;
  Cls, Ttl : String;
  I : LongInt;

Begin
  Inst := GetModuleHandleA(Nil);
  LangInit;
  BrFace := CreateSolidBrush(cFace);
  PenW := CreatePen(0, 1, cWhite); PenG := CreatePen(0, 1, cGray);
  PenD := CreatePen(0, 1, cFace); PenB := CreatePen(0, 1, cBlack);
  For I := 0 To NTab - 1 Do Notes[I] := L('Aucun probl'#138'me trouv'#130'.',
      'No problems found.',
      'Keine Probleme gefunden.',
      'Nessun problema rilevato.',
      'No se encontraron problemas.');
  TestDD := L('Non effectu'#130'.',
      'Not run.',
      'Nicht ausgef'#129'hrt.',
      'Non eseguito.',
      'No realizada.'); TestD3D := L('Non effectu'#130'.',
      'Not run.',
      'Nicht ausgef'#129'hrt.',
      'Non eseguito.',
      'No realizada.'); TestDS := L('Non effectu'#130'.',
      'Not run.',
      'Nicht ausgef'#129'hrt.',
      'Non eseguito.',
      'No realizada.');
  Cls := Z('DxDiag'); Ttl := Z(L('Outil de diagnostic DirectX',
      'DirectX Diagnostic Tool',
      'DirectX-Diagnoseprogramm',
      'Strumento di diagnostica DirectX',
      'Herramienta de diagn'#162'stico de DirectX'));
  WC.Style := 3; WC.WndProc := @WndProc; WC.ClsExtra := 0;
  WC.WndExtra := 0; WC.Inst := Inst; WC.Icon := 0;
  WC.Cursor := LoadCursorA(0, 32512); WC.Brush := 0;
  WC.MenuName := Nil; WC.ClassName := @Cls[1];
  RegisterClassA(WC);
  SysInfo;
  DispInfo;
  SndInfo;
  InpInfo;
  NetInfo;
  Wnd := CreateWindowExA(0, @Cls[1], @Ttl[1], $00CA0000 Or $10000000, 4, 4,
                         632, 444, 0, 0, Inst, 0);
  ShowWindow(Wnd, 1);
  UpdateWindow(Wnd);
  While GetMessageA(Msg, 0, 0, 0) <> 0 Do
  Begin
    TranslateMessage(Msg);
    DispatchMessageA(Msg);
  End;
  ExitProcess(0);
End.
