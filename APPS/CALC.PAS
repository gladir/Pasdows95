{ CALC.PAS - Calculatrice de Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 CALC.PAS CALC.EXE

  Comme la Calculatrice de Windows 95 en mode Standard : affichage,
  indicateur de memoire, touches Retour arriere, CE et C, memoire (MC,
  MR, MS, M+), chiffres, virgule, +/-, les quatre operations, racine
  carree, pourcentage, inverse (1/x) et egal (repete la derniere
  operation). Les touches sont dessinees comme celles de Windows 95 :
  chiffres en bleu, operations et memoire en rouge.

  Clavier : chiffres, virgule ou point, + - * /, Entree ou = (egal), @
  (racine carree), % , R (1/x), F9 (+/-), Retour arriere, Suppr (CE),
  Echap (C), Ctrl+L (MC), Ctrl+R (MR), Ctrl+M (MS), Ctrl+P (M+),
  Ctrl+C (Copier), Ctrl+V (Coller : le texte est tape touche par touche).

  Le separateur decimal suit les parametres regionaux (GetLocaleInfoA) et
  l'interface la variable d'environnement LANGUAGE (FR, EN, GR, IT, SP).
  Calcul en double precision, affichage sur 15 chiffres significatifs
  (notation scientifique au-dela). }

Program Calc;

{$IFDEF WPC}{$APPTYPE GUI}{$R-}{$ENDIF}

Type
  PByt = ^Byte;
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
  TSize = Record
    CX, CY : LongInt;
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
Function DefWindowProcA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(Var M : TMsg; H, A, B : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetMessageA';
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
Function MessageBoxA(H : LongInt; T, C : PChar; F : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'MessageBoxA';
Function MessageBeep(T : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBeep';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function FillRect(Hdc : LongInt; Var R : TRect; Br : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'FillRect';
Function SetCapture(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseCapture';
Function AdjustWindowRect(Var R : TRect; Style, Menu : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'AdjustWindowRect';
Function CreateMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(H, F, Id : LongInt; S : PChar) : LongInt; stdcall;
  external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetMenu';
Function OpenClipboard(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'OpenClipboard';
Function CloseClipboard : LongInt; stdcall;
  external 'user32.dll' name 'CloseClipboard';
Function EmptyClipboard : LongInt; stdcall;
  external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetClipboardData';
Function GetClipboardData(F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetClipboardData';
Function TextOutA(Hdc, X, Y : LongInt; S : PChar; N : LongInt) : LongInt;
  stdcall; external 'gdi32.dll' name 'TextOutA';
Function GetTextExtentPoint32A(Hdc : LongInt; S : PChar; N : LongInt;
  Var Sz : TSize) : LongInt; stdcall;
  external 'gdi32.dll' name 'GetTextExtentPoint32A';
Function SetBkMode(Hdc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
Function SetTextColor(Hdc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(S, W, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreatePen';
Function SelectObject(Hdc, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function MoveToEx(Hdc, X, Y : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'MoveToEx';
Function GdiLineTo(Hdc, X, Y : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'LineTo';
Function GetModuleHandleA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalAlloc';
Function GlobalLock(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalLock';
Function GlobalUnlock(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalUnlock';
Function GetLocaleInfoA(Lc, Ty : LongInt; P : Pointer; N : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetLocaleInfoA';
Function GetEnvironmentVariableA(N : PChar; B : Pointer; Sz : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';

Const
  WM_DESTROY = 2; WM_PAINT = $F; WM_KEYDOWN = $100; WM_CHAR = $102;
  WM_COMMAND = $111; WM_LBUTTONDOWN = $201; WM_LBUTTONUP = $202;
  WM_LBUTTONDBLCLK = $203; WM_MOUSEMOVE = $200;
  MF_STRING = 0; MF_GRAYED = 1; MF_CHECKED = 8; MF_POPUP = $10;
  MF_SEPARATOR = $800;
  cFace = $C0C0C0; cWhite = $FFFFFF; cGray = $808080; cBlack = 0;
  cRed = $0000FF; cBlue = $FF0000; cNavy = $800000;
  { touches : fonctions (identifiants des boutons et du clavier) }
  kBack = 20; kCE = 21; kC = 22; kMC = 23; kMR = 24; kMS = 25; kMP = 26;
  kDiv = 27; kMul = 28; kSub = 29; kAdd = 30; kEq = 31; kSqrt = 32;
  kPct = 33; kInv = 34; kNeg = 35; kDot = 36;
  { menus }
  idCopy = 100; idPaste = 101; idStd = 110; idSci = 111; idHelp = 120;
  idAbout = 121;
  NBtn = 28;
  { zone client }
  CliW = 276; CliH = 216;

Var
  Inst, Wnd, Lang : LongInt;
  BrFace, BrWhite, PenW, PenG, PenB, PenL : LongInt;
  DecSep : Char;
  { boutons }
  BX, BY, BW, BH, BK, BC : Array[0..NBtn - 1] Of LongInt;
  BT : Array[0..NBtn - 1] Of String[6];
  Pressed, Hot : LongInt;
  { etat du calcul }
  Acc, Cur, Mem, LastVal : Double;
  Op, LastOp : LongInt;
  Entering, HaveLast, Err : Boolean;
  Disp : String;               { nombre en cours de saisie (sans le
                                 separateur final) }
  ErrMsg : String;

{ ------------------------------------------------------- utilitaires }

Function CStr(A : LongInt) : String;
Var S : String; C : Byte;
Begin
  S := '';
  If A <> 0 Then
    While Length(S) < 250 Do
    Begin
      C := PByt(A)^;
      If C = 0 Then Break;
      S := S + Chr(C);
      Inc(A);
    End;
  CStr := S;
End;

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
  { separateur decimal des parametres regionaux (LOCALE_SDECIMAL) }
  DecSep := '.';
  B[0] := #0;
  If GetLocaleInfoA($400, $E, @B, 8) > 0 Then
    If B[0] <> #0 Then DecSep := B[0];
End;

{ Texte dans la langue courante (page de codes 850) }
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

Procedure AddItem(M, Id : LongInt; S : String; F : LongInt);
Var T : String;
Begin
  T := S + #0;
  AppendMenuA(M, F, Id, @T[1]);
End;

Procedure AddPopup(M, Sub : LongInt; S : String);
Var T : String;
Begin
  T := S + #0;
  AppendMenuA(M, MF_POPUP, Sub, @T[1]);
End;

Procedure Box(T, M : String; F : LongInt);
Var A, B : String;
Begin
  A := T + #0; B := M + #0;
  MessageBoxA(Wnd, @B[1], @A[1], F);
End;

{ ------------------------------------------------- nombres et texte }

{ Les N derniers chiffres de l'entier V (V >= 0, exact en double) }
Function Digits(V : Double; N : LongInt) : String;
Var S : String; Q, D : Double; I : LongInt;
Begin
  S := '';
  For I := 1 To N Do
  Begin
    Q := Int(V / 10);
    D := V - Q * 10;
    If D < 0 Then D := 0;
    If D > 9 Then D := 9;
    S := Chr(48 + Trunc(D + 0.5)) + S;
    V := Q;
  End;
  Digits := S;
End;

Function Pow10(N : LongInt) : Double;
Var R : Double; I : LongInt;
Begin
  R := 1;
  If N >= 0 Then
    For I := 1 To N Do R := R * 10
  Else
    For I := 1 To -N Do R := R / 10;
  Pow10 := R;
End;

Function StripZeros(S : String) : String;
Begin
  While (Length(S) > 0) And (S[Length(S)] = '0') Do Delete(S, Length(S), 1);
  StripZeros := S;
End;

{ Nombre affiche comme Windows 95 : 15 chiffres significatifs, separateur
  decimal toujours present ("12,"), notation scientifique "1,5e+020" }
Function FmtNum(X : Double) : String;
Var Neg : Boolean; E, Dc, N : LongInt; M, V : Double; S, IP, FP, R : String;
Begin
  If X = 0 Then
  Begin
    FmtNum := '0' + DecSep;
    Exit;
  End;
  Neg := X < 0;
  X := Abs(X);
  { exposant decimal : 1 <= X / 10^E < 10 }
  M := X; E := 0;
  While M >= 10 Do
  Begin
    M := M / 10; Inc(E);
  End;
  While M < 1 Do
  Begin
    M := M * 10; Dec(E);
  End;
  If (E >= 15) Or (E < -15) Then
  Begin
    V := Int(M * 1E14 + 0.5);
    If V >= 1E15 Then
    Begin
      V := Int(V / 10 + 0.5); Inc(E);
    End;
    S := Digits(V, 15);
    R := S[1] + DecSep + StripZeros(Copy(S, 2, 14)) + 'e';
    If E < 0 Then R := R + '-' Else R := R + '+';
    S := Digits(Abs(E), 3);
    R := R + S;
  End
  Else
  Begin
    Dc := 14 - E;
    V := Int(X * Pow10(Dc) + 0.5);
    If V >= 1E15 Then
    Begin
      Dec(Dc);
      V := Int(X * Pow10(Dc) + 0.5);
    End;
    If Dc < 0 Then Dc := 0;
    N := Dc + 1;
    If N < 15 Then N := 15;
    S := Digits(V, N);
    IP := Copy(S, 1, N - Dc);
    FP := StripZeros(Copy(S, N - Dc + 1, Dc));
    While (Length(IP) > 1) And (IP[1] = '0') Do Delete(IP, 1, 1);
    R := IP + DecSep + FP;
  End;
  If Neg Then R := '-' + R;
  FmtNum := R;
End;

{ Valeur d'un texte de nombre (separateur '.' ou ',', exposant 'e') }
Function ParseNum(S : String) : Double;
Var I, E, ES : LongInt; V, F : Double; Neg, InFrac : Boolean; C : Char;
Begin
  V := 0; F := 1; Neg := False; InFrac := False; E := 0; ES := 1;
  I := 1;
  If (Length(S) > 0) And (S[1] = '-') Then
  Begin
    Neg := True; I := 2;
  End;
  While I <= Length(S) Do
  Begin
    C := S[I];
    If (C >= '0') And (C <= '9') Then
    Begin
      If InFrac Then
      Begin
        F := F / 10;
        V := V + (Ord(C) - 48) * F;
      End
      Else V := V * 10 + (Ord(C) - 48);
    End
    Else If (C = '.') Or (C = ',') Then InFrac := True
    Else If (C = 'e') Or (C = 'E') Then
    Begin
      Inc(I);
      If (I <= Length(S)) And (S[I] = '-') Then ES := -1;
      If (I <= Length(S)) And ((S[I] = '-') Or (S[I] = '+')) Then Inc(I);
      While (I <= Length(S)) And (S[I] >= '0') And (S[I] <= '9') Do
      Begin
        E := E * 10 + Ord(S[I]) - 48;
        Inc(I);
      End;
      V := V * Pow10(E * ES);
      Break;
    End;
    Inc(I);
  End;
  If Neg Then V := -V;
  ParseNum := V;
End;

{ Texte de l'affichage }
Function DispText : String;
Begin
  If Err Then DispText := ErrMsg
  Else If Entering Then
  Begin
    If Pos(DecSep, Disp) > 0 Then DispText := Disp
    Else DispText := Disp + DecSep;
  End
  Else DispText := FmtNum(Cur);
End;

Function CurVal : Double;
Begin
  If Entering Then CurVal := ParseNum(Disp) Else CurVal := Cur;
End;

{ ------------------------------------------------------------- calcul }

Procedure SetErr(Const M : String);
Begin
  Err := True; ErrMsg := M;
  Entering := False; Op := 0; HaveLast := False;
End;

Function DivZero : String;
Begin
  DivZero := L('Impossible de diviser par z'#130'ro.', 'Cannot divide by ' +
               'zero.', 'Division durch Null nicht m'#148'glich.',
               'Impossibile dividere per zero.',
               'No se puede dividir por cero.');
End;

Function Calc2(A : Double; O : LongInt; B : Double) : Double;
Var R : Double;
Begin
  R := 0;
  Case O Of
    kAdd : R := A + B;
    kSub : R := A - B;
    kMul : R := A * B;
    kDiv :
      If B = 0 Then SetErr(DivZero)
      Else R := A / B;
  End;
  If Not Err And ((R > 1E300) Or (R < -1E300)) Then
  Begin
    SetErr(L('D'#130'passement de capacit'#130'.', 'Overflow.',
             #154'berlauf.', 'Overflow.', 'Desbordamiento.'));
    R := 0;
  End;
  Calc2 := R;
End;

Procedure Key(K : LongInt);
Var V : Double;
Begin
  If Err And (K <> kC) And (K <> kCE) Then
  Begin
    MessageBeep(0);
    Exit;
  End;
  Case K Of
    0..9 :
    Begin
      If Not Entering Then
      Begin
        Disp := ''; Entering := True;
      End;
      If (Disp = '0') Or (Disp = '-0') Then Delete(Disp, Length(Disp), 1);
      If Length(Disp) < 32 Then Disp := Disp + Chr(48 + K)
      Else MessageBeep(0);
      If Disp = '' Then Disp := '0';
    End;
    kDot :
    Begin
      If Not Entering Then
      Begin
        Disp := '0'; Entering := True;
      End;
      If Pos(DecSep, Disp) = 0 Then Disp := Disp + DecSep;
    End;
    kBack :
      If Entering Then
      Begin
        Delete(Disp, Length(Disp), 1);
        If (Disp = '') Or (Disp = '-') Then Disp := '0';
      End;
    kCE :
    Begin
      Err := False; Entering := False; Cur := 0;
    End;
    kC :
    Begin
      Err := False; Entering := False; Cur := 0; Acc := 0; Op := 0;
      HaveLast := False;
    End;
    kNeg :
      If Entering Then
      Begin
        If (Length(Disp) > 0) And (Disp[1] = '-') Then Delete(Disp, 1, 1)
        Else Disp := '-' + Disp;
      End
      Else Cur := -Cur;
    kAdd, kSub, kMul, kDiv :
    Begin
      V := CurVal;
      If (Op <> 0) And Entering Then Acc := Calc2(Acc, Op, V)
      Else If Op = 0 Then Acc := V;
      If Not Err Then
      Begin
        Cur := Acc; Op := K; Entering := False; HaveLast := False;
      End;
    End;
    kEq :
    Begin
      If Op <> 0 Then
      Begin
        V := CurVal;
        Cur := Calc2(Acc, Op, V);
        LastOp := Op; LastVal := V; HaveLast := True; Op := 0;
        Acc := Cur;
      End
      Else If HaveLast Then
      Begin
        Cur := Calc2(CurVal, LastOp, LastVal);
        Acc := Cur;
      End
      Else Cur := CurVal;
      Entering := False;
    End;
    kSqrt :
    Begin
      V := CurVal;
      If V < 0 Then SetErr(L('Entr'#130'e non valide pour la fonction.',
                             'Invalid input for function.',
                             'Ung'#129'ltige Eingabe f'#129'r die Funktion.',
                             'Input non valido per la funzione.',
                             'Entrada no v'#160'lida para la funci'#162'n.'))
      Else
      Begin
        Cur := Sqrt(V); Entering := False;
      End;
    End;
    kPct :
    Begin
      Cur := Acc * CurVal / 100; Entering := False;
    End;
    kInv :
    Begin
      V := CurVal;
      If V = 0 Then SetErr(DivZero)
      Else
      Begin
        Cur := 1 / V; Entering := False;
      End;
    End;
    kMC : Mem := 0;
    kMR :
    Begin
      Cur := Mem; Entering := False;
    End;
    kMS : Mem := CurVal;
    kMP : Mem := Mem + CurVal;
  End;
  InvalidateRect(Wnd, Nil, 0);
End;

{ Caractere tape (clavier ou Coller) -> touche ; -1 si aucune }
Function CharKey(C : LongInt) : LongInt;
Begin
  Case C Of
    48..57 : CharKey := C - 48;
    46, 44 : CharKey := kDot;          { . , }
    43 : CharKey := kAdd;              { + }
    45 : CharKey := kSub;              { - }
    42 : CharKey := kMul;              { * }
    47 : CharKey := kDiv;              { / }
    61, 13 : CharKey := kEq;           { = Entree }
    64 : CharKey := kSqrt;             { @ }
    37 : CharKey := kPct;              { % }
    82, 114 : CharKey := kInv;         { R r }
    8 : CharKey := kBack;
    27 : CharKey := kC;
    12 : CharKey := kMC;           { Ctrl+L }
    18 : CharKey := kMR;           { Ctrl+R }
    16 : CharKey := kMP;           { Ctrl+P }
  Else
    CharKey := -1;
  End;
End;

{ ------------------------------------------------------ presse-papiers }

Procedure CopyText;
Var S : String; H, P, I : LongInt;
Begin
  S := DispText;
  If Not Err And (Length(S) > 0) And (S[Length(S)] = DecSep) Then
    Delete(S, Length(S), 1);
  H := GlobalAlloc(2, Length(S) + 1);
  If H = 0 Then Exit;
  P := GlobalLock(H);
  For I := 1 To Length(S) Do PByt(P + I - 1)^ := Ord(S[I]);
  PByt(P + Length(S))^ := 0;
  GlobalUnlock(H);
  If OpenClipboard(Wnd) <> 0 Then
  Begin
    EmptyClipboard;
    SetClipboardData(1, H);
    CloseClipboard;
  End;
End;

Procedure PasteText;
Var S : String; H, I, K : LongInt;
Begin
  S := '';
  If OpenClipboard(Wnd) = 0 Then Exit;
  H := GetClipboardData(1);
  If H <> 0 Then S := CStr(GlobalLock(H));
  If H <> 0 Then GlobalUnlock(H);
  CloseClipboard;
  For I := 1 To Length(S) Do
  Begin
    K := CharKey(Ord(S[I]));
    If (K >= 0) And (K <> kC) Then Key(K);
  End;
End;

{ ------------------------------------------------------------ dessin }

Procedure AddBtn(I, X, Y, W, K, C : LongInt; Const T : String);
Begin
  BX[I] := X; BY[I] := Y; BW[I] := W; BH[I] := 28; BK[I] := K;
  BC[I] := C; BT[I] := T;
End;

{ Disposition de la Calculatrice de Windows 95 (mode Standard) }
Procedure Layout;
Const
  Pad : Array[0..19] Of LongInt = (
    7, 8, 9, kDiv, kSqrt, 4, 5, 6, kMul, kPct,
    1, 2, 3, kSub, kInv, 0, kNeg, kDot, kAdd, kEq);
Var R, C, I, K, Col : LongInt; T : String;
Begin
  AddBtn(0, 60, 40, 64, kBack, cRed, L('Retour', 'Back', 'R'#129'ck',
         'Canc', 'Retr'));
  AddBtn(1, 130, 40, 64, kCE, cRed, 'CE');
  AddBtn(2, 200, 40, 64, kC, cRed, 'C');
  AddBtn(3, 12, 78, 36, kMC, cRed, 'MC');
  AddBtn(4, 12, 112, 36, kMR, cRed, 'MR');
  AddBtn(5, 12, 146, 36, kMS, cRed, 'MS');
  AddBtn(6, 12, 180, 36, kMP, cRed, 'M+');
  I := 7;
  For R := 0 To 3 Do
    For C := 0 To 4 Do
    Begin
      K := Pad[R * 5 + C];
      Col := cBlue;
      Case K Of
        0..9 : T := Chr(48 + K);
        kDiv : T := '/';
        kMul : T := '*';
        kSub : T := '-';
        kAdd : T := '+';
        kEq : T := '=';
        kSqrt : T := 'sqrt';
        kPct : T := '%';
        kInv : T := '1/x';
        kNeg : T := '+/-';
        kDot : T := DecSep;
      End;
      If (K = kDiv) Or (K = kMul) Or (K = kSub) Or (K = kAdd) Or (K = kEq)
      Then Col := cRed
      Else If (K = kSqrt) Or (K = kPct) Or (K = kInv) Then Col := cNavy;
      AddBtn(I, 60 + C * 42, 78 + R * 34, 36, K, Col, T);
      Inc(I);
    End;
End;

Procedure Line(Hdc, X1, Y1, X2, Y2, P : LongInt);
Begin
  SelectObject(Hdc, P);
  MoveToEx(Hdc, X1, Y1, Nil);
  GdiLineTo(Hdc, X2, Y2);
End;

{ Cadre en relief (Down : enfonce) }
Procedure Bevel(Hdc, X1, Y1, X2, Y2 : LongInt; Down : Boolean);
Begin
  If Down Then
  Begin
    Line(Hdc, X1, Y2 - 1, X1, Y1, PenB); GdiLineTo(Hdc, X2, Y1);
    Line(Hdc, X1 + 1, Y2 - 2, X1 + 1, Y1 + 1, PenG);
    GdiLineTo(Hdc, X2 - 1, Y1 + 1);
    Line(Hdc, X1, Y2, X2, Y2, PenW); GdiLineTo(Hdc, X2, Y1 - 1);
  End
  Else
  Begin
    Line(Hdc, X1, Y2 - 1, X1, Y1, PenW); GdiLineTo(Hdc, X2, Y1);
    Line(Hdc, X1, Y2, X2, Y2, PenB); GdiLineTo(Hdc, X2, Y1 - 1);
    Line(Hdc, X1 + 1, Y2 - 1, X2 - 1, Y2 - 1, PenG);
    GdiLineTo(Hdc, X2 - 1, Y1);
  End;
End;

Procedure Sunken(Hdc, X1, Y1, X2, Y2 : LongInt);
Begin
  Line(Hdc, X1, Y2, X1, Y1, PenG); GdiLineTo(Hdc, X2 + 1, Y1);
  Line(Hdc, X1 + 1, Y2 - 1, X1 + 1, Y1 + 1, PenB);
  GdiLineTo(Hdc, X2, Y1 + 1);
  Line(Hdc, X1 + 1, Y2, X2, Y2, PenW); GdiLineTo(Hdc, X2, Y1);
  Line(Hdc, X1 + 2, Y2 - 1, X2 - 1, Y2 - 1, PenL);
  GdiLineTo(Hdc, X2 - 1, Y1 + 1);
End;

Procedure CenterText(Hdc, X1, X2, Y : LongInt; Const S : String;
                     C : LongInt);
Var T : String; Sz : TSize;
Begin
  T := S + #0;
  Sz.CX := Length(S) * 8; Sz.CY := 16;
  GetTextExtentPoint32A(Hdc, @T[1], Length(S), Sz);
  SetTextColor(Hdc, C);
  TextOutA(Hdc, (X1 + X2 - Sz.CX) Div 2, Y, @T[1], Length(S));
End;

Procedure DrawBtn(Hdc, I : LongInt);
Var R : TRect; Dn : Boolean; D : LongInt;
Begin
  Dn := (Pressed = I) And (Hot = I);
  R.L := BX[I]; R.T := BY[I]; R.R := BX[I] + BW[I]; R.B := BY[I] + BH[I];
  FillRect(Hdc, R, BrFace);
  Bevel(Hdc, R.L, R.T, R.R - 1, R.B - 1, Dn);
  D := Ord(Dn);
  CenterText(Hdc, R.L + D, R.R + D, R.T + 6 + D, BT[I], BC[I]);
End;

Procedure Paint(Hdc : LongInt);
Var R : TRect; I : LongInt; S, T : String; Sz : TSize;
Begin
  R.L := 0; R.T := 0; R.R := CliW; R.B := CliH;
  FillRect(Hdc, R, BrFace);
  SetBkMode(Hdc, 1);
  { affichage }
  R.L := 12; R.T := 8; R.R := 264; R.B := 30;
  FillRect(Hdc, R, BrWhite);
  Sunken(Hdc, 10, 6, 265, 31);
  S := DispText;
  T := S + #0;
  Sz.CX := Length(S) * 8; Sz.CY := 16;
  GetTextExtentPoint32A(Hdc, @T[1], Length(S), Sz);
  SetTextColor(Hdc, cBlack);
  TextOutA(Hdc, 258 - Sz.CX, 11, @T[1], Length(S));
  { indicateur de memoire }
  Sunken(Hdc, 12, 40, 47, 67);
  If Mem <> 0 Then CenterText(Hdc, 13, 48, 46, 'M', cBlack);
  For I := 0 To NBtn - 1 Do DrawBtn(Hdc, I);
End;

Function HitBtn(X, Y : LongInt) : LongInt;
Var I, R : LongInt;
Begin
  R := -1;
  For I := 0 To NBtn - 1 Do
    If (X >= BX[I]) And (X < BX[I] + BW[I]) And (Y >= BY[I]) And
       (Y < BY[I] + BH[I]) Then R := I;
  HitBtn := R;
End;

{ ------------------------------------------------------------- menus }

Procedure BuildMenus;
Var Bar, M : LongInt;
Begin
  Bar := CreateMenu;
  M := CreatePopupMenu;
  AddItem(M, idCopy, L('Copier'#9'Ctrl+C', 'Copy'#9'Ctrl+C',
          'Kopieren'#9'Strg+C', 'Copia'#9'Ctrl+C', 'Copiar'#9'Ctrl+C'), 0);
  AddItem(M, idPaste, L('Coller'#9'Ctrl+V', 'Paste'#9'Ctrl+V',
          'Einf'#129'gen'#9'Strg+V', 'Incolla'#9'Ctrl+V',
          'Pegar'#9'Ctrl+V'), 0);
  AddPopup(Bar, M, L('Edition', 'Edit', 'Bearbeiten', 'Modifica',
           'Edici'#162'n'));
  M := CreatePopupMenu;
  AddItem(M, idSci, L('Scientifique', 'Scientific', 'Wissenschaftlich',
          'Scientifica', 'Cient'#161'fica'), MF_GRAYED);
  AddItem(M, idStd, L('Standard', 'Standard', 'Standard', 'Standard',
          'Est'#160'ndar'), MF_CHECKED);
  AddPopup(Bar, M, L('Affichage', 'View', 'Ansicht', 'Visualizza', 'Ver'));
  M := CreatePopupMenu;
  AddItem(M, idHelp, L('Rubriques d''aide', 'Help Topics', 'Hilfethemen',
          'Guida in linea', 'Temas de Ayuda'), MF_GRAYED);
  AddItem(M, 0, '', MF_SEPARATOR);
  AddItem(M, idAbout, L(#133' propos de la Calculatrice', 'About Calculator',
          #142'ber Rechner', 'Informazioni su Calcolatrice',
          'Acerca de Calculadora'), 0);
  AddPopup(Bar, M, '?');
  SetMenu(Wnd, Bar);
End;

{ ------------------------------------------------- fenetre principale }

Function WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var P : TPaint; Hdc, I, X, Y, K : LongInt;
Begin
  WndProc := 0;
  Case M Of
    WM_PAINT :
    Begin
      Hdc := BeginPaint(H, P);
      Paint(Hdc);
      EndPaint(H, P);
    End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
    Begin
      X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
      I := HitBtn(X, Y);
      If I >= 0 Then
      Begin
        Pressed := I; Hot := I;
        SetCapture(H);
        InvalidateRect(H, Nil, 0);
      End;
    End;
    WM_MOUSEMOVE :
      If Pressed >= 0 Then
      Begin
        X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
        I := HitBtn(X, Y);
        If I <> Hot Then
        Begin
          Hot := I;
          InvalidateRect(H, Nil, 0);
        End;
      End;
    WM_LBUTTONUP :
      If Pressed >= 0 Then
      Begin
        X := LP And $FFFF; Y := (LP Shr 16) And $FFFF;
        I := Pressed;
        Pressed := -1; Hot := -1;
        ReleaseCapture;
        If HitBtn(X, Y) = I Then Key(BK[I])
        Else InvalidateRect(H, Nil, 0);
      End;
    WM_CHAR :
    Begin
      If W = 3 Then CopyText
      Else If W = 22 Then PasteText
      Else If W = 13 Then Key(kEq)
      Else
      Begin
        K := CharKey(W);
        If K >= 0 Then Key(K);
      End;
    End;
    WM_KEYDOWN :
      Case W Of
        $2E : Key(kCE);               { Suppr }
        $78 : Key(kNeg);              { F9 }
      End;
    WM_COMMAND :
      Case W And $FFFF Of
        idCopy : CopyText;
        idPaste : PasteText;
        idAbout :
          Box(L(#133' propos de la Calculatrice', 'About Calculator',
                #142'ber Rechner', 'Informazioni su Calcolatrice',
                'Acerca de Calculadora'),
              L('Calculatrice', 'Calculator', 'Rechner', 'Calcolatrice',
                'Calculadora') + #13#10'Pasdows 95 4.00.950'#13#10 +
              L('Auteur : ', 'Author: ', 'Autor: ', 'Autore: ', 'Autor: ') +
              'Sylvain Maltais'#13#10 + L('Licence : ', 'License: ',
              'Lizenz: ', 'Licenza: ', 'Licencia: ') + 'MIT', $40);
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    WndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

Var
  C : TWndClass;
  M : TMsg;
  R : TRect;
  Cls, Ttl : String;
  Style : LongInt;

Begin
  LangInit;
  Inst := GetModuleHandleA(Nil);
  BrFace := CreateSolidBrush(cFace);
  BrWhite := CreateSolidBrush(cWhite);
  PenW := CreatePen(0, 1, cWhite);
  PenG := CreatePen(0, 1, cGray);
  PenB := CreatePen(0, 1, cBlack);
  PenL := CreatePen(0, 1, cFace);
  Pressed := -1; Hot := -1;
  Acc := 0; Cur := 0; Mem := 0; Op := 0; Err := False; Entering := False;
  Disp := '0';
  Layout;
  Cls := 'PasdowsCalc'#0;
  C.Style := 8; C.WndProc := @WndProc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, 32512);
  C.Brush := 0; C.MenuName := Nil; C.ClassName := @Cls[1];
  RegisterClassA(C);
  Ttl := L('Calculatrice', 'Calculator', 'Rechner', 'Calcolatrice',
           'Calculadora') + #0;
  { fenetre de taille fixe : titre, menu systeme, reduction }
  Style := $00CA0000 Or $10000000;
  R.L := 0; R.T := 0; R.R := CliW; R.B := CliH;
  AdjustWindowRect(R, Style, 1);
  Wnd := CreateWindowExA(0, @Cls[1], @Ttl[1], Style, 160, 80, R.R - R.L,
                         R.B - R.T, 0, 0, Inst, 0);
  BuildMenus;
  ShowWindow(Wnd, 1);
  UpdateWindow(Wnd);
  While GetMessageA(M, 0, 0, 0) <> 0 Do
  Begin
    TranslateMessage(M);
    DispatchMessageA(M);
  End;
  ExitProcess(0);
End.
