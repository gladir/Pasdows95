{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: CHARMAP - Table de caracteres de Pasdows 95 (Win32),
                comme celle des Accessoires de Windows 95.
}

Program CHARMAP;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\CHARMAP.PAS CHARMAP.EXE

  Comme la Table de caracteres de Windows 95 : la grille montre les 224
  caracteres affichables du jeu de Windows (codes 32 a 255, page de
  codes ANSI 1252), en 32 colonnes et 7 lignes.
  - clic sur un caractere : il est choisi et agrandi tant que le bouton
    de la souris reste enfonce ; les fleches deplacent le choix ;
  - double clic, Entree ou bouton Selectionner : le caractere s'ajoute a
    la zone Caracteres a copier ;
  - Copier : le contenu de cette zone va dans le presse-papiers (CF_TEXT),
    pret a etre colle dans le Bloc-notes ou ailleurs ;
  - barre d'etat : la frappe qui donne le caractere (la touche, ou Alt
    et le code sur le pave numerique, par exemple Alt+0233 pour e aigu).
  Sous Pasdows 95, qui affiche les programmes de WPC avec la police de
  l'ecran (page 437), les caracteres sont convertis pour l'affichage et
  pour le presse-papiers (comme le Bloc-notes) ; sous Windows, ils sont
  passes tels quels. }

Const
  WM_DESTROY = $0002; WM_SIZE = $0005; WM_PAINT = $000F; WM_CLOSE = $0010;
  WM_ERASEBKGND = $0014; WM_SETFONT = $0030; WM_KEYDOWN = $0100;
  WM_COMMAND = $0111; WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201;
  WM_LBUTTONUP = $0202; WM_LBUTTONDBLCLK = $0203;
  WS_CHILD = $40000000; WS_VISIBLE = $10000000; WS_CAPTION = $00C00000;
  WS_BORDER = $00800000; WS_SYSMENU = $00080000; WS_MINIMIZEBOX = $00020000;
  WS_TABSTOP = $00010000; WS_VSCROLL = $00200000; WS_CLIPCHILDREN = $02000000;
  ES_AUTOHSCROLL = $0080; ES_READONLY = $0800; BS_DEFPUSHBUTTON = 1; CBS_DROPDOWNLIST = 3;
  CB_ADDSTRING = $0143; CB_SETCURSEL = $014E;
  EM_SETSEL = $00B1; EM_REPLACESEL = $00C2;
  CS_DBLCLKS = 8; IDC_ARROW = 32512; SM_CXSCREEN = 0; SM_CYSCREEN = 1;
  VK_RETURN = $0D; VK_SPACE = $20; VK_END = $23; VK_HOME = $24;
  VK_LEFT = $25; VK_UP = $26; VK_RIGHT = $27; VK_DOWN = $28;
  SRCCOPY = $00CC0020; OPAQUE = 2; TRANSPARENT = 1; OEM_CHARSET = 255;
  CF_TEXT = 1;
  ID_FONT = 10; ID_EDIT = 11; ID_CLOSE = 12; ID_SELECT = 13; ID_COPY = 14;
  { grille : 32 colonnes de 13 points, 7 lignes de 17 points }
  NCol = 32; NRow = 7; CellW = 13; CellH = 17;
  GX = 8; GY = 40;
  CWant = 528; CHWant = 226;
  ClrFace = $C0C0C0; ClrShadow = $808080; ClrHi = $FFFFFF; ClrSel = $800000;

Type
  TWndCls = Record
    Style, Proc, ClsExtra, WndExtra, Inst, Icon, Cursor, Brush, MenuName, ClassName : LongInt;
  End;

Var
  Inst, Wnd, EdW, CbW, Dummy, OemOut : LongInt;
  MemDC, MemBmp, FontS, FontL : LongInt;
  Sel, Zoom : LongInt;                     { caractere choisi (32..255), agrandi }
  NameZ, NameZ2, TxtBuf : Array[0..1023] Of Byte;
  Qmsg : Array[0..7] Of LongInt;

Function GetModuleHandleA(P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure ExitProcess(Code : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalAlloc';
Function RegOpenKeyExA(K, Sub, Opt, Sam, PRes : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(K, Name, Res, PTyp, Data, PLen : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';
Function RegisterClassA(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex, Cls, Title, Style, X, Y, W, H, Par, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function ShowWindow(H, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ShowWindow';
Function UpdateWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'UpdateWindow';
Function DefWindowProcA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(P, H, F, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(Code : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function SendMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SendMessageA';
Function BeginPaint(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function GetDC(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetDC';
Function ReleaseDC(H, Dc : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseDC';
Function InvalidateRect(H, P, Erase : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'InvalidateRect';
Function AdjustWindowRectEx(P, Style, Menu, Ex : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'AdjustWindowRectEx';
Function GetWindowTextA(H, P, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetWindowTextA';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetSystemMetrics';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function SetCapture(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseCapture';
Function MessageBeep(T : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBeep';
Function OpenClipboard(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'OpenClipboard';
Function EmptyClipboard : LongInt; stdcall;
  external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetClipboardData';
Function CloseClipboard : LongInt; stdcall;
  external 'user32.dll' name 'CloseClipboard';
Function FillRect(Dc, P, Br : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'FillRect';
Function CreateCompatibleDC(Dc : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleDC';
Function CreateCompatibleBitmap(Dc, W, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleBitmap';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function DeleteObject(H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
Function CreateFontA(H, W, Esc, Ori, Wt, It, Un, St, Cs, Op, Cp, Q, Pf, Face : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateFontA';
Function SelectObject(Dc, Obj : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function BitBlt(D, X, Y, W, H, S, XS, YS, Op : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'BitBlt';
Function TextOutA(Dc, X, Y, P, N : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'TextOutA';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function SetBkColor(Dc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkColor';
Function SetBkMode(Dc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';

{ ==================================================================== }
{ Utilitaires                                                           }
{ ==================================================================== }

Type
  PByt = ^Byte;

Procedure PutZ(A : LongInt; S : String);
Var K : LongInt; P : PByt;
Begin
  For K := 1 To Length(S) Do
  Begin
    P := PByt(A + K - 1); P^ := Ord(S[K]);
  End;
  P := PByt(A + Length(S)); P^ := 0;
End;

Function Z(S : String) : LongInt;
Begin
  PutZ(LongInt(@NameZ), S);
  Z := LongInt(@NameZ);
End;

Function Z2(S : String) : LongInt;
Begin
  PutZ(LongInt(@NameZ2), S);
  Z2 := LongInt(@NameZ2);
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

{ ANSI (1252) -> page 437 de la police de l'ecran de Pasdows }
Const
  AnsiOem : Array[128..255] Of Byte = (
    69, 63, 44, 102, 34, 46, 197, 206, 94, 63, 83, 60, 79, 63, 90, 63, 63,
    39, 39, 34, 34, 249, 45, 45, 126, 159, 115, 62, 111, 63, 122, 89, 255,
    173, 155, 156, 63, 157, 124, 21, 34, 169, 166, 174, 170, 45, 158, 196,
    248, 241, 253, 51, 39, 230, 20, 250, 44, 49, 167, 175, 172, 171, 63, 168,
    65, 65, 65, 65, 142, 143, 146, 128, 69, 144, 69, 69, 73, 73, 73, 73, 68,
    165, 79, 79, 79, 79, 153, 120, 79, 85, 85, 85, 154, 89, 63, 225, 133,
    160, 131, 97, 132, 134, 145, 135, 138, 130, 136, 137, 141, 161, 140, 139,
    63, 164, 149, 162, 147, 111, 148, 246, 111, 151, 163, 150, 129, 121, 63,
    152);

{ caractere ANSI C tel qu'il s'affiche (et se copie) }
Function DispCh(C : LongInt) : Char;
Begin
  If (OemOut <> 0) And (C >= 128) Then DispCh := Chr(AnsiOem[C])
  Else DispCh := Chr(C);
End;

{ textes accentues du programme : ecrits en ANSI, affiches par DispCh }
Function Disp(S : String) : String;
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do S[K] := DispCh(Ord(S[K]));
  Disp := S;
End;

Procedure DetectOem;
Var K, T, N : LongInt; B : Array[0..63] Of Byte; S : String;
Begin
  OemOut := 0;
  K := 0;
  If RegOpenKeyExA(LongInt($80000002), Z('Software\Microsoft\Windows\CurrentVersion'), 0, $20019,
                   LongInt(@K)) <> 0 Then Exit;
  N := 63; T := 0; B[0] := 0;
  If RegQueryValueExA(K, Z('ProductName'), 0, LongInt(@T), LongInt(@B), LongInt(@N)) = 0 Then
  Begin
    B[63] := 0;
    S := ''; T := 0;
    While (T < 7) And (B[T] <> 0) Do Begin S := S + UpCase(Chr(B[T])); Inc(T); End;
    If S = 'PASDOWS' Then OemOut := 1;
  End;
  Dummy := RegCloseKey(K);
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }

Procedure Bar(Dc, X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; B : LongInt;
Begin
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2; Rc[3] := Y2;
  B := CreateSolidBrush(C);
  Dummy := FillRect(Dc, LongInt(@Rc), B);
  Dummy := DeleteObject(B);
End;

Procedure Txt(Dc, X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Dummy := SetTextColor(Dc, Fg);
  Dummy := SetBkColor(Dc, Bg);
  Dummy := TextOutA(Dc, X, Y, LongInt(@TxtBuf), Length(S));
End;

Procedure CellXY(C : LongInt; Var X, Y : LongInt);
Begin
  X := GX + ((C - 32) Mod NCol) * CellW;
  Y := GY + ((C - 32) Div NCol) * CellH;
End;

Procedure DrawCell(Dc, C : LongInt);
Var X, Y, Fg, Bg : LongInt;
Begin
  CellXY(C, X, Y);
  If C = Sel Then Begin Bg := ClrSel; Fg := ClrHi; End
  Else Begin Bg := ClrHi; Fg := 0; End;
  Bar(Dc, X + 1, Y + 1, X + CellW, Y + CellH, Bg);
  Txt(Dc, X + 3, Y + 1, DispCh(C), Fg, Bg);
End;

{ barre d'etat : frappe du caractere choisi }
Function KeyText(C : LongInt) : String;
Var S : String;
Begin
  If C = 32 Then S := 'Barre d''espace'
  Else If C < 127 Then S := Chr(C)
  Else
  Begin
    S := IStr(C);
    While Length(S) < 3 Do S := '0' + S;
    S := 'Alt+0' + S;
  End;
  KeyText := Disp('Frappe de touche : ') + Disp(S) + '    ' + Disp('Code : ') + IStr(C);
End;

Procedure DrawAll(Dc : LongInt);
Var I, X, Y : LongInt;
Begin
  Bar(Dc, 0, 0, CWant, CHWant, ClrFace);
  { libelles (les controles sont au-dessus) }
  Dummy := SetBkMode(Dc, TRANSPARENT);
  Txt(Dc, 8, 12, 'Police :', 0, ClrFace);
  Txt(Dc, 216, 12, Disp('Caract' + #232 + 'res ' + #224 + ' copier :'), 0, ClrFace);
  Dummy := SetBkMode(Dc, OPAQUE);
  { grille : traits noirs entre les cases }
  Bar(Dc, GX, GY, GX + NCol * CellW + 1, GY + NRow * CellH + 1, 0);
  For I := 32 To 255 Do DrawCell(Dc, I);
  { caractere agrandi tant que le bouton reste enfonce }
  If Zoom <> 0 Then
  Begin
    CellXY(Sel, X, Y);
    X := X + CellW Div 2 - 18; Y := Y + CellH Div 2 - 22;
    If X < 2 Then X := 2;
    If X + 36 > GX + NCol * CellW Then X := GX + NCol * CellW - 36;
    If Y < GY Then Y := GY;
    If Y + 44 > GY + NRow * CellH Then Y := GY + NRow * CellH - 44;
    Bar(Dc, X, Y, X + 36, Y + 44, 0);
    Bar(Dc, X + 1, Y + 1, X + 35, Y + 43, ClrHi);
    Bar(Dc, X + 2, Y + 42, X + 35, Y + 43, ClrShadow);
    Bar(Dc, X + 34, Y + 2, X + 35, Y + 43, ClrShadow);
    Dummy := SelectObject(Dc, FontL);
    Txt(Dc, X + 10, Y + 6, DispCh(Sel), 0, ClrHi);
    Dummy := SelectObject(Dc, FontS);
  End;
  { barre d'etat }
  Y := CHWant - 22;
  Bar(Dc, 0, Y - 2, CWant, Y - 1, ClrShadow);
  Bar(Dc, 0, Y - 1, CWant, Y, ClrHi);
  Txt(Dc, 8, Y + 4, KeyText(Sel), 0, ClrFace);
End;

{ hors de WM_PAINT : seules la grille et la barre d'etat sont recopiees
  (pas la place des controles) }
Procedure Redraw;
Var Dc, Y : LongInt;
Begin
  DrawAll(MemDC);
  Dc := GetDC(Wnd);
  Dummy := BitBlt(Dc, 0, GY - 2, CWant, NRow * CellH + 4, MemDC, 0, GY - 2, SRCCOPY);
  Y := CHWant - 24;
  Dummy := BitBlt(Dc, 0, Y, CWant, CHWant - Y, MemDC, 0, Y, SRCCOPY);
  Dummy := ReleaseDC(Wnd, Dc);
End;

{ ==================================================================== }
{ Commandes                                                             }
{ ==================================================================== }

{ ajouter le caractere choisi a la zone Caracteres a copier }
Procedure SelectChar;
Var S : String;
Begin
  S := DispCh(Sel);
  Dummy := SendMessageA(EdW, EM_SETSEL, 32767, 32767);
  Dummy := SendMessageA(EdW, EM_REPLACESEL, 0, Z(S));
End;

Procedure CopyChars;
Var N, H, K : LongInt; P : PByt;
Begin
  N := GetWindowTextA(EdW, LongInt(@TxtBuf), 1000);
  If N <= 0 Then
  Begin
    { rien a copier : le caractere choisi }
    TxtBuf[0] := Ord(DispCh(Sel)); TxtBuf[1] := 0; N := 1;
  End;
  If OpenClipboard(Wnd) = 0 Then
  Begin
    Dummy := MessageBeep(0);
    Exit;
  End;
  Dummy := EmptyClipboard;
  H := GlobalAlloc(0, N + 1);                     { GMEM_FIXED }
  If H <> 0 Then
  Begin
    For K := 0 To N Do
    Begin
      P := PByt(H + K); P^ := TxtBuf[K];
    End;
    Dummy := SetClipboardData(CF_TEXT, H);
  End;
  Dummy := CloseClipboard;
End;

Procedure Move(D : LongInt);
Begin
  Sel := Sel + D;
  If Sel < 32 Then Sel := 32;
  If Sel > 255 Then Sel := 255;
  Redraw;
End;

{ caractere sous la souris (0 : hors de la grille) }
Function HitChar(X, Y : LongInt) : LongInt;
Var C, R : LongInt;
Begin
  HitChar := 0;
  If (X < GX) Or (Y < GY) Then Exit;
  C := (X - GX) Div CellW; R := (Y - GY) Div CellH;
  If (C >= NCol) Or (R >= NRow) Then Exit;
  HitChar := 32 + R * NCol + C;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Var Ps : Array[0..15] Of LongInt; Dc, C : LongInt;
Begin
  MainProc := 0;
  Case Msg Of
    WM_PAINT :
      Begin
        Dc := BeginPaint(H, LongInt(@Ps));
        DrawAll(MemDC);
        Dummy := BitBlt(Dc, 0, 0, CWant, CHWant, MemDC, 0, 0, SRCCOPY);
        Dummy := EndPaint(H, LongInt(@Ps));
      End;
    WM_ERASEBKGND : MainProc := 1;
    WM_LBUTTONDOWN :
      Begin
        Dummy := SetFocus(H);
        C := HitChar(S16(LP), S16(LP Shr 16));
        If C <> 0 Then
        Begin
          Sel := C; Zoom := 1;
          Dummy := SetCapture(H);
          Redraw;
        End;
      End;
    WM_MOUSEMOVE :
      If Zoom <> 0 Then
      Begin
        C := HitChar(S16(LP), S16(LP Shr 16));
        If (C <> 0) And (C <> Sel) Then
        Begin
          Sel := C;
          Redraw;
        End;
      End;
    WM_LBUTTONUP :
      If Zoom <> 0 Then
      Begin
        Zoom := 0;
        Dummy := ReleaseCapture;
        Redraw;
      End;
    WM_LBUTTONDBLCLK :
      Begin
        C := HitChar(S16(LP), S16(LP Shr 16));
        If C <> 0 Then
        Begin
          Sel := C;
          SelectChar;
          Redraw;
        End;
      End;
    WM_KEYDOWN :
      Case WP Of
        VK_LEFT : Move(-1);
        VK_RIGHT : Move(1);
        VK_UP : Move(-NCol);
        VK_DOWN : Move(NCol);
        VK_HOME : Move(-255);
        VK_END : Move(255);
        VK_RETURN, VK_SPACE : SelectChar;
      Else
        MainProc := DefWindowProcA(H, Msg, WP, LP);
      End;
    WM_COMMAND :
      Case WP And $FFFF Of
        ID_CLOSE : Dummy := DestroyWindow(H);
        ID_SELECT : Begin SelectChar; Dummy := SetFocus(H); End;
        ID_COPY : Begin CopyChars; Dummy := SetFocus(H); End;
      End;
    WM_CLOSE : Dummy := DestroyWindow(H);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function Ctl(Cls, Txt0 : String; Style, X, Y, W, H, Id : LongInt) : LongInt;
Var C : LongInt;
Begin
  C := CreateWindowExA(0, Z2(Cls), Z(Disp(Txt0)), WS_CHILD Or WS_VISIBLE Or Style, X, Y, W, H, Wnd, Id,
                       Inst, 0);
  Ctl := C;
End;

Var
  C : TWndCls;
  Rc : Array[0..3] Of LongInt;
  Flg, Fw, Fh, Dc, Bx : LongInt;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Sel := 65; Zoom := 0;
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  FontL := CreateFontA(32, 16, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  If OemOut = 0 Then
  Begin
    { Windows : polices ANSI pour la grille }
    PutZ(LongInt(@NameZ2), 'Courier New');
    FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 1, LongInt(@NameZ2));
    FontL := CreateFontA(32, 16, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 1, LongInt(@NameZ2));
  End;
  PutZ(LongInt(@NameZ2), 'CharMapWnd');
  C.Style := CS_DBLCLKS; C.Proc := LongInt(@MainProc); C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, IDC_ARROW); C.Brush := 0;
  C.MenuName := 0; C.ClassName := LongInt(@NameZ2);
  Dummy := RegisterClassA(LongInt(@C));
  Flg := WS_CAPTION Or WS_SYSMENU Or WS_MINIMIZEBOX Or WS_CLIPCHILDREN;
  Rc[0] := 0; Rc[1] := 0; Rc[2] := CWant; Rc[3] := CHWant;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), Flg, 0, 0);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  Wnd := CreateWindowExA(0, LongInt(@NameZ2), Z(Disp('Table de caract' + #232 + 'res')), Flg,
                         (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2,
                         (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2, Fw, Fh, 0, 0, Inst, 0);
  If Wnd = 0 Then ExitProcess(1);
  { une seule police (celle de l'ecran) : son nom, dans un cadre }
  CbW := Ctl('EDIT', 'Terminal', WS_BORDER Or ES_READONLY, 76, 8, 128, 22, ID_FONT);
  EdW := Ctl('EDIT', '', WS_BORDER Or WS_TABSTOP Or ES_AUTOHSCROLL, 384, 8, 136, 22, ID_EDIT);
  { boutons sous la grille (Fermer, Selectionner, Copier) }
  Bx := CWant - 3 * 92 - 8;
  Dummy := Ctl('BUTTON', 'Fermer', WS_TABSTOP, Bx, GY + NRow * CellH + 8, 86, 24, ID_CLOSE);
  Dummy := Ctl('BUTTON', 'S' + #233 + 'lectionner', WS_TABSTOP Or BS_DEFPUSHBUTTON, Bx + 92, GY + NRow * CellH + 8, 86, 24,
               ID_SELECT);
  Dummy := Ctl('BUTTON', 'Copier', WS_TABSTOP, Bx + 184, GY + NRow * CellH + 8, 86, 24, ID_COPY);
  Dc := GetDC(Wnd);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, CWant, CHWant);
  Dummy := ReleaseDC(Wnd, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  Dummy := ShowWindow(Wnd, 1);
  Dummy := UpdateWindow(Wnd);
  Dummy := SetFocus(Wnd);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  ExitProcess(0);
END.
