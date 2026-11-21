{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025 (prototype), 2026 (OS/2-0, Pasdows 95)
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: FREECELL - FreeCell (solitaire) pour Pasdows 95 et
                Windows (Accessoires, Jeux).
}

Program FREECELL;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\FREECELL.PAS FREECELL.EXE   (Pasdows 95)

  Portage pour Windows 95 du FreeCell du Presentation Manager
  FREECELL.PAS du projet OS2-0 (lui-meme porte du prototype FREECELL.PAS
  du depot 7iles : Turbo Pascal et BGI). Les regles, les donnes, le
  dessin des cartes et les commandes sont inchanges ; seules les API
  d'OS/2 ont ete remplacees par celles de Windows :

  - PMWIN -> USER32 : fenetre (classe FreeCellWnd), vraie barre de menus
    (CreateMenu, AppendMenuA, CheckMenuItem), minuteur (SetTimer),
    boites de message (MessageBoxA), bip (MessageBeep), clavier
    (WM_KEYDOWN, WM_CHAR), souris (WM_LBUTTONDOWN, WM_LBUTTONDBLCLK) ;
  - PMGPI -> GDI32 : cartes en rectangles arrondis (RoundRect avec un
    pinceau et une plume de la couleur), traits (MoveToEx, LineTo),
    texte (TextOutA) dans la police OEM 8 x 16 (Terminal : symboles des
    couleurs des cartes, caracteres 3 a 6) et en 16 x 32 pour les grands
    textes (au lieu de la police du VGA lue par VioGetFont) ; dessin dans
    une image en memoire (CreateCompatibleDC) recopiee par BitBlt ; les
    coordonnees de PM (origine en bas a gauche) sont converties ;
  - DOSCALLS -> KERNEL32 : GetTickCount (graine des donnes).

  Textes en page de codes 437 (police OEM) ; les menus, le titre et les
  boites de message sont convertis en ANSI sous Windows (sous Pasdows 95,
  qui affiche les programmes de WPC avec la police de l'ecran, ils sont
  passes tels quels).

  Regles du prototype : 52 cartes en 8 colonnes (7, 7, 7, 7, 6, 6, 6,
  6), toutes visibles ; 4 cellules libres d'une carte ; 4 fondations
  montees par couleur de l'as au roi ; sur une colonne, une carte se pose
  sur une carte de valeur immediatement superieure et de l'autre couleur
  (rouge sur noir) ; toute carte va sur une colonne vide.
  Ce qui est ajoute : les donnes numerotees (les memes que celles du
  FreeCell de Windows : la donne 1 commence par le valet de carreau), le
  deplacement de plusieurs cartes a la fois (autant que les cellules et
  colonnes vides le permettent), les cartes qui montent seules aux
  fondations quand elles ne servent plus, le double clic, l'annulation
  des coups, les statistiques de la seance.

  Souris : cliquer une carte (ou une suite) puis sa destination ; double
  clic : la carte va a sa fondation ou dans une cellule libre. Clavier :
  1 a 8 (colonnes), A a D (cellules libres), H (fondations), Echap
  (annuler le choix), Retour arriere ou Ctrl+Z (annuler le coup), F2
  (nouvelle donne), F3 (rejouer la donne), F1 (regles).
  Parametres : /DEAL:n (donne numero n, 1 a 32000) ; /SEED:n ; /AUTO
  (l'ordinateur joue les coups evidents). }

Const
  WM_DESTROY = $0002; WM_SIZE = $0005; WM_PAINT = $000F; WM_CLOSE = $0010;
  WM_ERASEBKGND = $0014; WM_KEYDOWN = $0100; WM_CHAR = $0102;
  WM_COMMAND = $0111; WM_TIMER = $0113;
  WM_LBUTTONDOWN = $0201; WM_LBUTTONDBLCLK = $0203;
  WS_CAPTION = $00C00000; WS_SYSMENU = $00080000; WS_MINIMIZEBOX = $00020000;
  CS_DBLCLKS = 8; IDC_ARROW = 32512; SM_CXSCREEN = 0; SM_CYSCREEN = 1;
  MF_STRING = 0; MF_POPUP = $10; MF_SEPARATOR = $800; MF_CHECKED = 8; MF_BYCOMMAND = 0;
  MB_OK = 0; MB_YESNO = 4; MB_INFORMATION = $40; MB_QUERY = $20; MBID_YES = 6;
  VK_BACK = $08; VK_CONTROL = $11; VK_MENU = $12; VK_ESCAPE = $1B;
  VK_F1 = $70; VK_F2 = $71; VK_F3 = $72;
  SRCCOPY = $00CC0020; OPAQUE = 2; NULL_BRUSH = 5; NULL_PEN = 8; OEM_CHARSET = 255;
  CLR_WHITE = -2; CLR_BLACK = -1; CLR_BLUE = 1; CLR_RED = 2; CLR_PINK = 3; CLR_GREEN = 4; CLR_CYAN = 5;
  CLR_YELLOW = 6; CLR_DARKGRAY = 8; CLR_DARKBLUE = 9; CLR_DARKRED = 10; CLR_DARKGREEN = 12;
  CLR_DARKCYAN = 13; CLR_BROWN = 14; CLR_PALEGRAY = 15;
  CLR_NEUTRAL = 7; CLR_DARKPINK = 11;
  DRO_FILL = 1; DRO_OUTLINE = 2;
  CM_NEW = 101; CM_RESTART = 102; CM_UNDO = 103; CM_QUIT = 104; CM_NEXT = 105;
  CM_AUTOF = 201; CM_MULTI = 202;
  CM_RULES = 301; CM_ABOUT = 302;
  CardW = 68; CardH = 92;
  SX0 = 12; SDX = 76; TopY = 10; ColY = 116;
  CWant = 626; CHWant = 440;
  MaxCol = 24; SnapSz = 8 * MaxCol + 16; MaxUndo = 240;

Var
  Inst, Frame, Client, Dummy, CW, CH, Hps : LongInt;
  MemDC, MemBmp, FontS, FontL, NullBr, NullPen, OemOut : LongInt;
  Brush, Pen : Array[0..17] Of LongInt;          { couleurs CLR_ (indice + 2) }
  MenuBar : LongInt;
  MenuPop : Array[0..2] Of LongInt;
  Col : Array[0..7, 0..MaxCol - 1] Of Byte;
  ColN : Array[0..7] Of LongInt;
  FreeC : Array[0..3] Of LongInt;          { -1 : cellule vide }
  Found : Array[0..3] Of LongInt;          { cartes montees (par couleur : coeur, carreau, trefle, pique) }
  SelZ, SelI, SelK : LongInt;              { choix : 0 rien, 1 cellule, 2 colonne (SelK : premiere carte) }
  DealNo, Moves, AutoF, Multi, AutoAll, Won, Played, Wins, Streak, Pending, Seed, AutoMoves : LongInt;
  Undo0 : Array[0..MaxUndo * SnapSz - 1] Of Byte;
  NUndo : LongInt;
  Msg : String;
  NameZ, NameZ2, TxtBuf : Array[0..1023] Of Byte;
  Qmsg : Array[0..7] Of LongInt;

Type
  TWndCls = Record
    Style, Proc, ClsExtra, WndExtra, Inst, Icon, Cursor, Brush, MenuName, ClassName : LongInt;
  End;

Function GetModuleHandleA(P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Procedure ExitProcess(Code : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
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
Function PostMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'PostMessageA';
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
Function GetClientRect(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetClientRect';
Function AdjustWindowRectEx(P, Style, Menu, Ex : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'AdjustWindowRectEx';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function SetTimer(H, Id, Ms, Proc : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetTimer';
Function MessageBoxA(H, Text, Cap, Typ : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBoxA';
Function MessageBeep(T : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBeep';
Function CreateMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(M, Flags, Id, Text : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetMenu';
Function CheckMenuItem(M, Id, Flags : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CheckMenuItem';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetSystemMetrics';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function GetKeyState(K : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetKeyState';
Function FillRect(Dc, P, Br : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'FillRect';

Function CreateCompatibleDC(Dc : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleDC';
Function CreateCompatibleBitmap(Dc, W, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateCompatibleBitmap';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function CreatePen(Style, W, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreatePen';
Function GetStockObject(I : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'GetStockObject';
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
Function RoundRect(Dc, L, T, R, B, W, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'RoundRect';
Function Rectangle(Dc, L, T, R, B : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'Rectangle';
Function MoveToEx(Dc, X, Y, P : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'MoveToEx';
Function LineTo(Dc, X, Y : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'LineTo';

{ ==================================================================== }
{ Utilitaires                                                           }
{ ==================================================================== }

Type
  PByte = ^Byte;

Procedure WrB(A, V : LongInt);
Var Q : PByte;
Begin
  Q := Pointer(A);
  Q^ := V;
End;

Function RdB(A : LongInt) : LongInt;
Var Q : PByte;
Begin
  Q := Pointer(A);
  RdB := Q^;
End;

Procedure WrW(A, V : LongInt);
Begin
  WrB(A, V And 255);
  WrB(A + 1, (V Shr 8) And 255);
End;

Function RdL(A : LongInt) : LongInt;
Begin
  RdL := RdB(A) Or (RdB(A + 1) Shl 8) Or (RdB(A + 2) Shl 16) Or (RdB(A + 3) Shl 24);
End;

Procedure PutZ(A : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do WrB(A + K - 1, Ord(S[K]));
  WrB(A + Length(S), 0);
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

Function Lo16(V : LongInt) : LongInt;
Begin
  Lo16 := V And $FFFF;
End;

Function Hi16(V : LongInt) : LongInt;
Begin
  Hi16 := (V Shr 16) And $FFFF;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Function Rnd(N : LongInt) : LongInt;
Begin
  Seed := (Seed * 1103515245 + 12345) And $7FFFFFFF;
  Rnd := (Seed Shr 8) Mod N;
End;


{ couleur de PM (CLR_) -> COLORREF de Windows }
Function ClrRgb(C : LongInt) : LongInt;
Begin
  Case C Of
    CLR_WHITE : ClrRgb := $FFFFFF;
    CLR_BLACK, CLR_NEUTRAL : ClrRgb := 0;
    CLR_BLUE : ClrRgb := $FF0000;
    CLR_RED : ClrRgb := $0000FF;
    CLR_PINK : ClrRgb := $FF00FF;
    CLR_GREEN : ClrRgb := $00FF00;
    CLR_CYAN : ClrRgb := $FFFF00;
    CLR_YELLOW : ClrRgb := $00FFFF;
    CLR_DARKGRAY : ClrRgb := $808080;
    CLR_DARKBLUE : ClrRgb := $800000;
    CLR_DARKRED : ClrRgb := $000080;
    CLR_DARKPINK : ClrRgb := $800080;
    CLR_DARKGREEN : ClrRgb := $008000;
    CLR_DARKCYAN : ClrRgb := $808000;
    CLR_BROWN : ClrRgb := $008080;
    CLR_PALEGRAY : ClrRgb := $C0C0C0;
  Else
    ClrRgb := $FFFFFF;
  End;
End;

{ page 437 -> ANSI (Latin-1), pour les menus et boites de message sous
  Windows : inverse de la table ANSI -> 437 }
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

Var
  OemAnsi : Array[0..255] Of Byte;
  OemAnsiOk : Boolean;

Function Win(S : String) : String;
Var K, C : LongInt;
Begin
  If OemOut = 0 Then
  Begin
    If Not OemAnsiOk Then
    Begin
      For K := 0 To 255 Do OemAnsi[K] := K;
      For K := 128 To 159 Do OemAnsi[K] := Ord('?');
      For C := 255 DownTo 160 Do
        If AnsiOem[C] >= 128 Then OemAnsi[AnsiOem[C]] := C;
      OemAnsiOk := True;
    End;
    For K := 1 To Length(S) Do
      If Ord(S[K]) >= 128 Then S[K] := Chr(OemAnsi[Ord(S[K])]);
  End;
  Win := S;
End;

Function Ask(Text, Cap : String; Fl : LongInt) : LongInt;
Begin
  Ask := MessageBoxA(Frame, Z(Win(Text)), Z2(Win(Cap)), Fl);
End;

Function MinI(A, B : LongInt) : LongInt;
Begin
  If A < B Then MinI := A Else MinI := B;
End;

Function MaxI(A, B : LongInt) : LongInt;
Begin
  If A > B Then MaxI := A Else MaxI := B;
End;

{ --- dessin (coordonnees de PM : origine en bas a gauche, comme le
  programme d'OS/2 ; converties pour Windows, origine en haut) --- }

{ rectangle de (X1, Y1) a (X2, Y2) inclus, plein ou contour, coins
  arrondis (R : diametre des coins, comme GpiBox) }
Procedure GBox(Hps, X1, Y1, X2, Y2, C, Fl, R : LongInt);
Var I, T, B : LongInt;
Begin
  I := C + 2;
  If (I < 0) Or (I > 17) Then I := 1;
  T := CH - 1 - Y2; B := CH - Y1;
  If Fl = DRO_FILL Then Dummy := SelectObject(Hps, Brush[I]) Else Dummy := SelectObject(Hps, NullBr);
  Dummy := SelectObject(Hps, Pen[I]);
  If R > 1 Then Dummy := RoundRect(Hps, X1, T, X2 + 1, B, R, R)
  Else Dummy := Rectangle(Hps, X1, T, X2 + 1, B);
End;

Procedure GLn(Hps, X1, Y1, X2, Y2, C : LongInt);
Var I : LongInt;
Begin
  I := C + 2;
  If (I < 0) Or (I > 17) Then I := 1;
  Dummy := SelectObject(Hps, Pen[I]);
  Dummy := MoveToEx(Hps, X1, CH - 1 - Y1, 0);
  Dummy := LineTo(Hps, X2, CH - 1 - Y2);
End;

{ texte : coin bas gauche (X, Y) }
Procedure TextXY(Hps, X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Dummy := SetTextColor(Hps, ClrRgb(Fg));
  Dummy := SetBkColor(Hps, ClrRgb(Bg));
  Dummy := TextOutA(Hps, X, CH - Y - 16, LongInt(@TxtBuf), Length(S));
End;

Function Rank(C : LongInt) : LongInt;
Begin
  Rank := C Mod 13;
End;

Function Suit(C : LongInt) : LongInt;
Begin
  Suit := C Div 13;
End;

Function IsRed(C : LongInt) : Boolean;
Begin
  IsRed := Suit(C) < 2;
End;

Function RankName(R : LongInt) : String;
Begin
  Case R Of
    0 : RankName := 'A';
    10 : RankName := 'V';
    11 : RankName := 'D';
    12 : RankName := 'R';
  Else
    RankName := IStr(R + 1);
  End;
End;

{ symbole de la couleur (police : 3 coeur, 4 carreau, 5 trefle, 6 pique) }
Function SuitCh(C : LongInt) : String;
Begin
  SuitCh := Chr(3 + Suit(C));
End;

Procedure DrawBack(Hps, X, Y : LongInt);
Var K : LongInt;
Begin
  GBox(Hps, X, Y, X + CardW - 1, Y + CardH - 1, CLR_WHITE, DRO_FILL, 10);
  GBox(Hps, X, Y, X + CardW - 1, Y + CardH - 1, CLR_BLACK, DRO_OUTLINE, 10);
  GBox(Hps, X + 4, Y + 4, X + CardW - 5, Y + CardH - 5, CLR_DARKBLUE, DRO_FILL, 6);
  { treillis original : losanges bleus }
  K := 0;
  While K < CardW + CardH - 24 Do
  Begin
    GLn(Hps, X + 5 + MaxI(0, K - CardH + 10), Y + 5 + MinI(K, CardH - 10), X + 5 + MinI(K, CardW - 10),
        Y + 5 + MaxI(0, K - CardW + 10), CLR_BLUE);
    K := K + 8;
  End;
  GBox(Hps, X + CardW Div 2 - 14, Y + CardH Div 2 - 12, X + CardW Div 2 + 14, Y + CardH Div 2 + 12, CLR_YELLOW,
       DRO_FILL, 24);
  TextXY(Hps, X + CardW Div 2 - 4, Y + CardH Div 2 - 8, 'B', CLR_DARKBLUE, CLR_YELLOW);
End;

{ disposition des symboles d'une carte numerotee : colonne (G, C, D) et
  ligne (0 a 6) de chaque symbole }
Function PipLayout(N : LongInt) : String;
Begin
  Case N Of
    1 : PipLayout := 'C3';
    2 : PipLayout := 'C0C6';
    3 : PipLayout := 'C0C3C6';
    4 : PipLayout := 'G0D0G6D6';
    5 : PipLayout := 'G0D0C3G6D6';
    6 : PipLayout := 'G0D0G3D3G6D6';
    7 : PipLayout := 'G0D0C1G3D3G6D6';
    8 : PipLayout := 'G0D0C1G3D3C5G6D6';
    9 : PipLayout := 'G0D0G2D2C3G4D4G6D6';
  Else
    PipLayout := 'G0D0C1G2D2G4D4C5G6D6';
  End;
End;

Procedure DrawPips(Hps, X, Y, C : LongInt; Fg : LongInt);
Var L, S : String; K, Px, Py, Cx : LongInt;
Begin
  L := PipLayout(Rank(C) + 1);
  S := SuitCh(C);
  Cx := X + CardW Div 2 - 4;
  K := 1;
  While K < Length(L) Do
  Begin
    Case L[K] Of
      'G' : Px := Cx - 14;
      'D' : Px := Cx + 14;
    Else
      Px := Cx;
    End;
    Py := Y + CardH - 34 - ((Ord(L[K + 1]) - 48) * (CardH - 50)) Div 6;
    TextXY(Hps, Px, Py, S, Fg, CLR_WHITE);
    K := K + 2;
  End;
End;

Procedure DrawFace(Hps, X, Y, C : LongInt; Hilite : Boolean);
Var Fg, Bg : LongInt; S : String;
Begin
  If Hilite Then Bg := CLR_YELLOW Else Bg := CLR_WHITE;
  GBox(Hps, X, Y, X + CardW - 1, Y + CardH - 1, Bg, DRO_FILL, 10);
  GBox(Hps, X, Y, X + CardW - 1, Y + CardH - 1, CLR_BLACK, DRO_OUTLINE, 10);
  If IsRed(C) Then Fg := CLR_RED Else Fg := CLR_BLACK;
  S := RankName(Rank(C));
  TextXY(Hps, X + 4, Y + CardH - 20, S, Fg, Bg);
  TextXY(Hps, X + 4 + Length(S) * 8, Y + CardH - 20, SuitCh(C), Fg, Bg);
  If Rank(C) >= 10 Then
  Begin
    { figure : cadre colore, lettre et symbole }
    GBox(Hps, X + 16, Y + 22, X + CardW - 17, Y + CardH - 23, CLR_DARKBLUE, DRO_OUTLINE, 0);
    GBox(Hps, X + 17, Y + 23, X + CardW - 18, Y + CardH - 24, CLR_YELLOW, DRO_FILL, 0);
    GBox(Hps, X + 22, Y + CardH Div 2 - 2, X + CardW - 23, Y + CardH - 30, Fg, DRO_FILL, 8);
    TextXY(Hps, X + CardW Div 2 - 8, Y + CardH Div 2 - 18, S + SuitCh(C), Fg, CLR_YELLOW);
    GLn(Hps, X + 22, Y + CardH Div 2 - 2, X + CardW Div 2, Y + CardH - 30, CLR_YELLOW);
    GLn(Hps, X + CardW Div 2, Y + CardH - 30, X + CardW - 23, Y + CardH Div 2 - 2, CLR_YELLOW);
  End
  Else If Rank(C) = 0 Then
  Begin
    GBox(Hps, X + CardW Div 2 - 14, Y + CardH Div 2 - 14, X + CardW Div 2 + 14, Y + CardH Div 2 + 14, Fg,
         DRO_OUTLINE, 28);
    TextXY(Hps, X + CardW Div 2 - 4, Y + CardH Div 2 - 8, SuitCh(C), Fg, Bg);
  End
  Else DrawPips(Hps, X, Y, C, Fg);
  { indice du coin bas droit apres les symboles (leur fond ne le cache pas) }
  TextXY(Hps, X + CardW - 6 - (Length(S) + 1) * 8, Y + 4, S + SuitCh(C), Fg, Bg);
End;


{ messages de plus de 255 caracteres (limite des chaines) : texte cumule
  dans LBuf par LAdd, puis affiche par LMsgBox }
Var
  LBuf : Array[0..4095] Of Byte;
  LLen : LongInt;

Procedure LClr;
Begin
  LLen := 0;
  LBuf[0] := 0;
End;

Procedure LAdd(S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If LLen < 4094 Then
    Begin
      LBuf[LLen] := Ord(S[K]);
      Inc(LLen);
    End;
  LBuf[LLen] := 0;
End;

Function LMsgBox(Cap : String; Fl : LongInt) : LongInt;
Var K : LongInt; T : String;
Begin
  If OemOut = 0 Then
    For K := 0 To LLen - 1 Do
      If LBuf[K] >= 128 Then
      Begin
        T := Win(Chr(LBuf[K]));
        LBuf[K] := Ord(T[1]);
      End;
  LMsgBox := MessageBoxA(Frame, LongInt(@LBuf), Z2(Win(Cap)), Fl);
End;
{ ==================================================================== }

Procedure FBar(X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; I : LongInt;
Begin
  If (X2 < X1) Or (Y2 < Y1) Then Exit;
  I := C + 2;
  If (I < 0) Or (I > 17) Then I := 1;
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2 + 1; Rc[3] := Y2 + 1;
  Dummy := FillRect(Hps, LongInt(@Rc), Brush[I]);
End;

Procedure Edge(X1, Y1, X2, Y2, Lt, Dk : LongInt);
Begin
  FBar(X1, Y1, X2, Y1, Lt); FBar(X1, Y1, X1, Y2, Lt);
  FBar(X1, Y2, X2, Y2, Dk); FBar(X2, Y1, X2, Y2, Dk);
End;

Procedure OutTxt(X, Y : LongInt; S : String; Fg, Bg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Dummy := SetTextColor(Hps, ClrRgb(Fg));
  Dummy := SetBkColor(Hps, ClrRgb(Bg));
  Dummy := TextOutA(Hps, X, Y, LongInt(@TxtBuf), Length(S));
End;

{ texte agrandi deux fois : police 16 x 32 (au lieu de la police du VGA
  agrandie point par point) }
Procedure BigText(X, Y : LongInt; S : String; C, Bg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(LongInt(@TxtBuf), S);
  Dummy := SelectObject(Hps, FontL);
  Dummy := SetTextColor(Hps, ClrRgb(C));
  Dummy := SetBkColor(Hps, ClrRgb(Bg));
  Dummy := TextOutA(Hps, X, Y, LongInt(@TxtBuf), Length(S));
  Dummy := SelectObject(Hps, FontS);
End;

{ disque plein de rayon R centre en (X, Y) }
Procedure Disc(X, Y, R, C : LongInt);
Var Dy, W, Rr : LongInt;
Begin
  Rr := R * R + R;
  For Dy := -R To R Do
  Begin
    W := 0;
    While (W + 1) * (W + 1) + Dy * Dy <= Rr Do Inc(W);
    FBar(X - W, Y + Dy, X + W, Y + Dy, C);
  End;
End;



{ ==================================================================== }
{ Regles                                                                }
{ ==================================================================== }

Function RedC(C : LongInt) : Boolean;
Begin
  RedC := Suit(C) <= 1;
End;

{ C se pose-t-elle sur D dans une colonne ? }
Function Fits(C, D : LongInt) : Boolean;
Begin
  Fits := (Rank(C) + 1 = Rank(D)) And (RedC(C) <> RedC(D));
End;

Function FreeCount : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 0 To 3 Do If FreeC[K] < 0 Then Inc(N);
  FreeCount := N;
End;

Function EmptyCols : LongInt;
Var K, N : LongInt;
Begin
  N := 0;
  For K := 0 To 7 Do If ColN[K] = 0 Then Inc(N);
  EmptyCols := N;
End;

{ cartes deplacables d'un coup (cellules libres et colonnes vides) }
Function MaxMove(ToEmpty : Boolean) : LongInt;
Var E, M, K : LongInt;
Begin
  E := EmptyCols;
  If ToEmpty Then Dec(E);
  If Multi = 0 Then
  Begin
    MaxMove := 1;
    Exit;
  End;
  M := FreeCount + 1;
  For K := 1 To E Do M := M * 2;
  MaxMove := M;
End;

{ la suite de la colonne I a partir de la carte K est-elle ordonnee ? }
Function RunOk(I, K : LongInt) : Boolean;
Var J : LongInt;
Begin
  RunOk := True;
  For J := K To ColN[I] - 2 Do
    If Not Fits(Col[I, J + 1], Col[I, J]) Then RunOk := False;
End;

Function CanFound(C : LongInt) : Boolean;
Begin
  CanFound := Found[Suit(C)] = Rank(C);
End;

{ carte inutile en jeu : les fondations de l'autre couleur sont assez hautes }
Function SafeFound(C : LongInt) : Boolean;
Var R, A, B : LongInt;
Begin
  SafeFound := False;
  If Not CanFound(C) Then Exit;
  R := Rank(C) + 1;
  If R <= 2 Then
  Begin
    SafeFound := True;
    Exit;
  End;
  If RedC(C) Then Begin A := Found[2]; B := Found[3]; End Else Begin A := Found[0]; B := Found[1]; End;
  SafeFound := (A >= R - 1) And (B >= R - 1);
End;

{ ==================================================================== }
{ Donne (algorithme des donnes numerotees de Windows)                   }
{ ==================================================================== }

Procedure DealGame(N : LongInt);
Var Deck : Array[0..51] Of LongInt; I, J, C, S, R, Ms, Left : LongInt;
Begin
  For I := 0 To 51 Do Deck[I] := I;
  For I := 0 To 7 Do ColN[I] := 0;
  S := N;
  For I := 0 To 51 Do
  Begin
    S := (S * 214013 + 2531011) And $7FFFFFFF;
    R := S Shr 16;
    Left := 52 - I;
    J := R Mod Left;
    C := Deck[J]; Deck[J] := Deck[Left - 1];
    { carte de Windows : rang C div 4, couleur trefle, carreau, coeur, pique }
    Case C Mod 4 Of
      0 : Ms := 2;
      1 : Ms := 1;
      2 : Ms := 0;
    Else
      Ms := 3;
    End;
    Col[I Mod 8, ColN[I Mod 8]] := Ms * 13 + C Div 4;
    Inc(ColN[I Mod 8]);
  End;
  For I := 0 To 3 Do Begin FreeC[I] := -1; Found[I] := 0; End;
  SelZ := 0; Moves := 0; NUndo := 0; Won := 0;
End;

{ ==================================================================== }
{ Annulation (etat complet avant chaque coup)                           }
{ ==================================================================== }

Procedure SaveState(A : LongInt);
Var I, J : LongInt;
Begin
  For I := 0 To 7 Do
  Begin
    For J := 0 To MaxCol - 1 Do Undo0[A + I * MaxCol + J] := Col[I, J];
    Undo0[A + 8 * MaxCol + I] := ColN[I];
  End;
  For I := 0 To 3 Do
  Begin
    Undo0[A + 8 * MaxCol + 8 + I] := (FreeC[I] + 1) And 255;
    Undo0[A + 8 * MaxCol + 12 + I] := Found[I];
  End;
End;

Procedure LoadState(A : LongInt);
Var I, J : LongInt;
Begin
  For I := 0 To 7 Do
  Begin
    For J := 0 To MaxCol - 1 Do Col[I, J] := Undo0[A + I * MaxCol + J];
    ColN[I] := Undo0[A + 8 * MaxCol + I];
  End;
  For I := 0 To 3 Do
  Begin
    FreeC[I] := Undo0[A + 8 * MaxCol + 8 + I] - 1;
    Found[I] := Undo0[A + 8 * MaxCol + 12 + I];
  End;
End;

Procedure PushUndo;
Begin
  If NUndo >= MaxUndo Then
  Begin
    Move(Undo0[SnapSz], Undo0[0], (MaxUndo - 1) * SnapSz);
    NUndo := MaxUndo - 1;
  End;
  SaveState(NUndo * SnapSz);
  Inc(NUndo);
End;

{ ==================================================================== }
{ Dessin                                                                }
{ ==================================================================== }

Function SlotX(I : LongInt) : LongInt;
Begin
  SlotX := SX0 + I * SDX;
End;

{ ecart vertical des cartes d'une colonne (resserre si elle est longue) }
Function StepOf(I : LongInt) : LongInt;
Var Av : LongInt;
Begin
  Av := CH - 26 - ColY - CardH;
  If ColN[I] <= 1 Then StepOf := 24
  Else StepOf := MinI(24, Av Div (ColN[I] - 1));
End;

Procedure CardAt(X, Y, C : LongInt; Hilite : Boolean);
Begin
  DrawFace(Hps, X, CH - Y - CardH, C, Hilite);
End;

{ carte recouverte : seuls le haut et le coin sont visibles }
Procedure PartAt(X, Y, C : LongInt; Hilite : Boolean);
Var B, Fg, Bg : LongInt; S : String;
Begin
  B := CH - Y - CardH;
  If Hilite Then Bg := CLR_YELLOW Else Bg := CLR_WHITE;
  GBox(Hps, X, B, X + CardW - 1, B + CardH - 1, Bg, DRO_FILL, 10);
  GBox(Hps, X, B, X + CardW - 1, B + CardH - 1, CLR_BLACK, DRO_OUTLINE, 10);
  If RedC(C) Then Fg := CLR_RED Else Fg := CLR_BLACK;
  S := RankName(Rank(C));
  TextXY(Hps, X + 4, B + CardH - 20, S, Fg, Bg);
  TextXY(Hps, X + 4 + Length(S) * 8, B + CardH - 20, SuitCh(C), Fg, Bg);
  TextXY(Hps, X + CardW - 13, B + CardH - 20, SuitCh(C), Fg, Bg);
End;

{ emplacement vide (cellule libre ou fondation) }
Procedure EmptySlot(X, Y : LongInt; S : String; Hl : Boolean);
Var C : LongInt;
Begin
  If Hl Then C := CLR_YELLOW Else C := CLR_BLACK;
  FBar(X, Y, X + CardW - 1, Y + CardH - 1, CLR_DARKGREEN);
  Edge(X, Y, X + CardW - 1, Y + CardH - 1, C, CLR_GREEN);
  Edge(X + 1, Y + 1, X + CardW - 2, Y + CardH - 2, C, CLR_GREEN);
  If S <> '' Then BigText(X + (CardW - Length(S) * 16) Div 2, Y + (CardH - 32) Div 2, S, CLR_GREEN, CLR_DARKGREEN);
End;

Procedure DrawTop;
Var I : LongInt;
Begin
  For I := 0 To 3 Do
    If FreeC[I] >= 0 Then CardAt(SlotX(I), TopY, FreeC[I], (SelZ = 1) And (SelI = I))
    Else EmptySlot(SlotX(I), TopY, '', False);
  For I := 0 To 3 Do
    If Found[I] > 0 Then CardAt(SlotX(4 + I), TopY, I * 13 + Found[I] - 1, False)
    Else EmptySlot(SlotX(4 + I), TopY, Chr(3 + I), False);
  { etiquettes }
  OutTxt(SlotX(0), TopY + CardH + 2, 'Cellules libres', CLR_YELLOW, CLR_DARKGREEN);
  OutTxt(SlotX(7) + CardW - 10 * 8, TopY + CardH + 2, 'Fondations', CLR_YELLOW, CLR_DARKGREEN);
End;

Procedure DrawColumn(I : LongInt);
Var K, Y, Sp : LongInt; Hl : Boolean;
Begin
  If ColN[I] = 0 Then
  Begin
    EmptySlot(SlotX(I), ColY, '', False);
    Exit;
  End;
  Sp := StepOf(I);
  For K := 0 To ColN[I] - 1 Do
  Begin
    Y := ColY + K * Sp;
    Hl := (SelZ = 2) And (SelI = I) And (K >= SelK);
    If K < ColN[I] - 1 Then PartAt(SlotX(I), Y, Col[I, K], Hl) Else CardAt(SlotX(I), Y, Col[I, K], Hl);
  End;
End;

Procedure DrawStatus;
Var S : String;
Begin
  FBar(0, CH - 22, CW - 1, CH - 1, CLR_PALEGRAY);
  Edge(2, CH - 21, CW - 3, CH - 2, CLR_DARKGRAY, CLR_WHITE);
  OutTxt(8, CH - 19, Msg, CLR_BLACK, CLR_PALEGRAY);
  S := 'Donne ' + IStr(DealNo) + '  Coups ' + IStr(Moves);
  FBar(CW - 12 - Length(S) * 8, CH - 20, CW - 4, CH - 3, CLR_PALEGRAY);
  Edge(CW - 14 - Length(S) * 8, CH - 21, CW - 3, CH - 2, CLR_DARKGRAY, CLR_WHITE);
  OutTxt(CW - 8 - Length(S) * 8, CH - 19, S, CLR_DARKBLUE, CLR_PALEGRAY);
End;

Procedure DrawWin;
Var X, Y, W : LongInt; S : String;
Begin
  If Won = 0 Then Exit;
  W := 380; X := (CW - W) Div 2; Y := 196;
  FBar(X, Y, X + W - 1, Y + 96, CLR_PALEGRAY);
  Edge(X, Y, X + W - 1, Y + 96, CLR_WHITE, CLR_BLACK);
  Edge(X + 1, Y + 1, X + W - 2, Y + 95, CLR_PALEGRAY, CLR_DARKGRAY);
  FBar(X + 3, Y + 3, X + W - 4, Y + 21, CLR_DARKBLUE);
  OutTxt(X + 8, Y + 4, 'FreeCell', CLR_WHITE, CLR_DARKBLUE);
  BigText(X + (W - 13 * 16) Div 2, Y + 28, 'Vous gagnez !', CLR_DARKGREEN, CLR_PALEGRAY);
  S := 'Donne ' + IStr(DealNo) + ' en ' + IStr(Moves) + ' coups. F2 : nouvelle donne.';
  OutTxt(X + (W - Length(S) * 8) Div 2, Y + 68, S, CLR_BLACK, CLR_PALEGRAY);
End;

Procedure PaintAll(H : LongInt);
Var I, Dc : LongInt; Ps : Array[0..15] Of LongInt;
Begin
  Dc := BeginPaint(H, LongInt(@Ps));
  Hps := MemDC;
  FBar(0, 0, CW - 1, CH - 23, CLR_DARKGREEN);
  DrawTop;
  For I := 0 To 7 Do DrawColumn(I);
  DrawWin;
  DrawStatus;
  Dummy := BitBlt(Dc, 0, 0, CW, CH, MemDC, 0, 0, SRCCOPY);
  Dummy := EndPaint(H, LongInt(@Ps));
End;

Procedure Redraw;
Begin
  If Client <> 0 Then Dummy := InvalidateRect(Client, 0, 0);
End;

{ ==================================================================== }
{ Coups                                                                 }
{ ==================================================================== }

Procedure PlayMsg;
Begin
  Msg := 'Cliquez une carte, puis sa destination.';
End;

Procedure CheckWin;
Begin
  If (Won = 0) And (Found[0] + Found[1] + Found[2] + Found[3] = 52) Then
  Begin
    Won := 1;
    Inc(Wins); Inc(Streak);
    Msg := 'Bravo ! Parties gagn' + Chr(130) + 'es : ' + IStr(Wins) + ' sur ' + IStr(Played) + '.';
    Pending := 0;
  End;
End;

{ une carte monte seule si elle ne sert plus (une par tic de l'horloge) }
Function AutoStep : Boolean;
Var I, C : LongInt;
Begin
  AutoStep := False;
  If AutoF = 0 Then Exit;
  For I := 0 To 3 Do
    If (FreeC[I] >= 0) And SafeFound(FreeC[I]) Then
    Begin
      C := FreeC[I]; FreeC[I] := -1; Inc(Found[Suit(C)]);
      AutoStep := True;
      Exit;
    End;
  For I := 0 To 7 Do
    If ColN[I] > 0 Then
      If SafeFound(Col[I, ColN[I] - 1]) Then
      Begin
        C := Col[I, ColN[I] - 1]; Dec(ColN[I]); Inc(Found[Suit(C)]);
        AutoStep := True;
        Exit;
      End;
End;

Procedure AfterMove;
Begin
  Inc(Moves);
  SelZ := 0;
  If Moves = 1 Then Inc(Played);
  PlayMsg;
  Pending := 1;
  CheckWin;
  Redraw;
End;

{ carte (ou suite) choisie ; Count : nombre de cartes }
Procedure SelInfo(Var Top, Count : LongInt);
Begin
  If SelZ = 1 Then Begin Top := FreeC[SelI]; Count := 1; End
  Else Begin Top := Col[SelI, SelK]; Count := ColN[SelI] - SelK; End;
End;

Procedure RemoveSel;
Begin
  If SelZ = 1 Then FreeC[SelI] := -1 Else ColN[SelI] := SelK;
End;

Function ToFreeCell(I : LongInt) : Boolean;
Var Top, Cnt : LongInt;
Begin
  ToFreeCell := False;
  If SelZ = 0 Then Exit;
  SelInfo(Top, Cnt);
  If (Cnt <> 1) Or (FreeC[I] >= 0) Then Exit;
  PushUndo;
  RemoveSel;
  FreeC[I] := Top;
  ToFreeCell := True;
  AfterMove;
End;

Function ToFoundation : Boolean;
Var Top, Cnt : LongInt;
Begin
  ToFoundation := False;
  If SelZ = 0 Then Exit;
  SelInfo(Top, Cnt);
  If (SelZ = 2) And (Cnt > 1) Then
  Begin
    { la derniere carte de la suite seulement }
    SelK := ColN[SelI] - 1;
    SelInfo(Top, Cnt);
  End;
  If Not CanFound(Top) Then Exit;
  PushUndo;
  RemoveSel;
  Inc(Found[Suit(Top)]);
  ToFoundation := True;
  AfterMove;
End;

Function ToColumn(I : LongInt) : Boolean;
Var Top, Cnt, K, M : LongInt;
Begin
  ToColumn := False;
  If SelZ = 0 Then Exit;
  If (SelZ = 2) And (SelI = I) Then Exit;
  SelInfo(Top, Cnt);
  M := MaxMove(ColN[I] = 0);
  If ColN[I] = 0 Then
  Begin
    { colonne vide : la plus longue partie possible de la suite }
    If Cnt > M Then
    Begin
      If SelZ = 2 Then SelK := ColN[SelI] - M;
      SelInfo(Top, Cnt);
    End;
  End
  Else
  Begin
    { la partie de la suite qui se pose sur la carte du bas }
    If SelZ = 2 Then
    Begin
      K := SelK;
      While (K < ColN[SelI]) And Not Fits(Col[SelI, K], Col[I, ColN[I] - 1]) Do Inc(K);
      If K >= ColN[SelI] Then Exit;
      SelK := K;
      SelInfo(Top, Cnt);
    End
    Else If Not Fits(Top, Col[I, ColN[I] - 1]) Then Exit;
    If Cnt > M Then
    Begin
      Msg := 'Pas assez de cellules libres pour d' + Chr(130) + 'placer ' + IStr(Cnt) + ' cartes (au plus ' +
             IStr(M) + ').';
      Exit;
    End;
  End;
  PushUndo;
  For K := 0 To Cnt - 1 Do
  Begin
    If SelZ = 1 Then Col[I, ColN[I]] := Top Else Col[I, ColN[I]] := Col[SelI, SelK + K];
    Inc(ColN[I]);
  End;
  RemoveSel;
  ToColumn := True;
  AfterMove;
End;

{ choix d'une carte de la colonne I a partir de K (la suite doit etre ordonnee) }
Procedure SelectCol(I, K : LongInt);
Begin
  If ColN[I] = 0 Then Exit;
  If K < 0 Then K := ColN[I] - 1;
  If Not RunOk(I, K) Then
  Begin
    { la plus longue suite ordonnee qui finit en bas }
    K := ColN[I] - 1;
    While (K > 0) And Fits(Col[I, K], Col[I, K - 1]) Do Dec(K);
    Msg := 'Seule une suite ordonn' + Chr(130) + 'e (rouge sur noir, en descendant) se d' + Chr(130) + 'place.';
  End
  Else PlayMsg;
  SelZ := 2; SelI := I; SelK := K;
  Redraw;
End;

Procedure ColClick(I, K : LongInt);
Begin
  If SelZ = 0 Then SelectCol(I, K)
  Else If (SelZ = 2) And (SelI = I) Then
  Begin
    SelZ := 0;
    Redraw;
  End
  Else If Not ToColumn(I) Then
  Begin
    If Pos('Pas assez', Msg) = 0 Then
      Msg := 'Ce coup n''est pas permis : une carte va sur la carte suivante de l''autre couleur.';
    Dummy := MessageBeep(0);
    SelZ := 0;
    Redraw;
  End;
End;

Procedure FreeClick(I : LongInt);
Begin
  If SelZ = 0 Then
  Begin
    If FreeC[I] >= 0 Then
    Begin
      SelZ := 1; SelI := I;
      Redraw;
    End;
  End
  Else If (SelZ = 1) And (SelI = I) Then
  Begin
    SelZ := 0;
    Redraw;
  End
  Else If FreeC[I] >= 0 Then
  Begin
    SelZ := 1; SelI := I;
    Redraw;
  End
  Else If Not ToFreeCell(I) Then
  Begin
    Msg := 'Une cellule libre ne re' + Chr(135) + 'oit qu''une carte.';
    Dummy := MessageBeep(0);
    SelZ := 0;
    Redraw;
  End;
End;

Procedure FoundClick;
Begin
  If SelZ = 0 Then Exit;
  If Not ToFoundation Then
  Begin
    Msg := 'Les fondations montent de l''as au roi, une couleur chacune.';
    Dummy := MessageBeep(0);
    SelZ := 0;
    Redraw;
  End;
End;

{ double clic : la carte du bas va a sa fondation, sinon dans une cellule }
Procedure DoubleClick;
Var I : LongInt;
Begin
  If SelZ = 0 Then Exit;
  If SelZ = 2 Then SelK := ColN[SelI] - 1;
  If ToFoundation Then Exit;
  If SelZ = 1 Then Exit;
  For I := 0 To 3 Do
    If FreeC[I] < 0 Then
    Begin
      If ToFreeCell(I) Then Exit;
    End;
End;

Procedure UndoMove;
Begin
  If NUndo = 0 Then Exit;
  Dec(NUndo);
  LoadState(NUndo * SnapSz);
  If Moves > 0 Then Dec(Moves);
  SelZ := 0; Won := 0; Pending := 0;
  Msg := 'Coup annul' + Chr(130) + '.';
  Redraw;
End;

Procedure NewDeal(N : LongInt);
Begin
  If (Moves > 0) And (Won = 0) Then Streak := 0;
  DealNo := N;
  DealGame(N);
  AutoMoves := 0;
  PlayMsg;
  Pending := 1;
  Redraw;
End;

{ demonstration : coups simples (pas un solveur) }
Function AutoPlay : Boolean;
Var I, J, K, Best0, Bk, Sc, Bs : LongInt;
Begin
  AutoPlay := False;
  If AutoMoves > 300 Then Exit;
  { vers une fondation }
  For I := 0 To 3 Do
    If (FreeC[I] >= 0) And CanFound(FreeC[I]) Then
    Begin
      SelZ := 1; SelI := I;
      AutoPlay := ToFoundation;
      Exit;
    End;
  For I := 0 To 7 Do
    If (ColN[I] > 0) And CanFound(Col[I, ColN[I] - 1]) Then
    Begin
      SelZ := 2; SelI := I; SelK := ColN[I] - 1;
      AutoPlay := ToFoundation;
      Exit;
    End;
  { cellule vers colonne }
  For I := 0 To 3 Do
    If FreeC[I] >= 0 Then
      For J := 0 To 7 Do
        If (ColN[J] > 0) And Fits(FreeC[I], Col[J, ColN[J] - 1]) Then
        Begin
          SelZ := 1; SelI := I;
          AutoPlay := ToColumn(J);
          Exit;
        End;
  { suite vers une autre colonne (la plus longue, qui decouvre le plus) }
  Bs := 0; Best0 := -1; Bk := 0;
  For I := 0 To 7 Do
    If ColN[I] > 0 Then
    Begin
      K := ColN[I] - 1;
      While (K > 0) And Fits(Col[I, K], Col[I, K - 1]) Do Dec(K);
      If K > 0 Then
        For J := 0 To 7 Do
          If (J <> I) And (ColN[J] > 0) Then
            If Fits(Col[I, K], Col[J, ColN[J] - 1]) And (ColN[I] - K <= MaxMove(False)) Then
            Begin
              Sc := 10 + ColN[I] - K;
              If Sc > Bs Then Begin Bs := Sc; Best0 := I * 8 + J; Bk := K; End;
            End;
    End;
  If Best0 >= 0 Then
  Begin
    SelZ := 2; SelI := Best0 Div 8; SelK := Bk;
    AutoPlay := ToColumn(Best0 Mod 8);
    Exit;
  End;
  { une carte dans une cellule libre, si elle decouvre une carte utile }
  If FreeCount > 1 Then
    For I := 0 To 7 Do
      If ColN[I] > 1 Then
      Begin
        K := Col[I, ColN[I] - 2];
        Sc := 0;
        If CanFound(K) Then Sc := 1;
        For J := 0 To 7 Do
          If (J <> I) And (ColN[J] > 0) Then If Fits(K, Col[J, ColN[J] - 1]) Then Sc := 1;
        If Sc <> 0 Then
          For J := 0 To 3 Do
            If FreeC[J] < 0 Then
            Begin
              SelZ := 2; SelI := I; SelK := ColN[I] - 1;
              AutoPlay := ToFreeCell(J);
              Exit;
            End;
      End;
  SelZ := 0;
End;

Procedure TimerTick;
Begin
  If Pending <> 0 Then
  Begin
    If AutoStep Then
    Begin
      CheckWin;
      Redraw;
      Exit;
    End;
    Pending := 0;
  End;
  If (AutoAll <> 0) And (Won = 0) Then
  Begin
    If Not AutoPlay Then AutoMoves := 9999 Else Inc(AutoMoves);
  End;
End;

Procedure SetMark(Id : LongInt; On : Boolean);
Begin
  If MenuPop[1] = 0 Then Exit;
  If On Then Dummy := CheckMenuItem(MenuPop[1], Id, MF_BYCOMMAND Or MF_CHECKED)
  Else Dummy := CheckMenuItem(MenuPop[1], Id, MF_BYCOMMAND);
End;

Procedure SetMarks;
Begin
  SetMark(CM_AUTOF, AutoF <> 0); SetMark(CM_MULTI, Multi <> 0);
End;

Procedure Command(Id : LongInt);
Begin
  Case Id Of
    CM_NEW : NewDeal(1 + Rnd(32000));
    CM_NEXT : NewDeal(DealNo Mod 32000 + 1);
    CM_RESTART : NewDeal(DealNo);
    CM_UNDO : UndoMove;
    CM_QUIT : Dummy := PostMessageA(Client, WM_CLOSE, 0, 0);
    CM_AUTOF : Begin AutoF := 1 - AutoF; SetMarks; Pending := 1; End;
    CM_MULTI : Begin Multi := 1 - Multi; SetMarks; End;
    CM_RULES :
      Begin
        LClr;
        LAdd('But : monter les 52 cartes sur les quatre fondations (en haut ' + Chr(133) + ' droite), une ' +
             'couleur chacune, de l''as au roi.' + Chr(10) + Chr(10));
        LAdd('Les cartes sont toutes visibles, en huit colonnes. Sur une colonne, une carte se pose sur la ' +
             'carte de valeur imm' + Chr(130) + 'diatement sup' + Chr(130) + 'rieure et de l''autre couleur ' +
             '(un 7 rouge sur un 8 noir). Toute carte va sur une colonne vide. ');
        LAdd('Les quatre cellules libres (en haut ' + Chr(133) + ' gauche) gardent chacune une carte.' +
             Chr(10) + Chr(10));
        LAdd('Une suite ordonn' + Chr(130) + 'e se d' + Chr(130) + 'place d''un coup s''il y a assez de cellules ' +
             'libres et de colonnes vides pour le faire carte par carte. Les cartes qui ne servent plus montent ' +
             'seules aux fondations (menu Options).' + Chr(10) + Chr(10));
        LAdd('Souris : cliquer une carte puis sa destination ; double clic : vers la fondation ou une cellule. ' +
             'Clavier : 1 ' + Chr(133) + ' 8, A ' + Chr(133) + ' D, H, Echap, Retour arri' + Chr(138) + 're ' +
             '(annuler), F2, F3.');
        Dummy := LMsgBox('FreeCell - R' + Chr(138) + 'gles', MB_OK Or MB_INFORMATION);
      End;
    CM_ABOUT : Dummy := Ask('FreeCell pour Pasdows 95 et Windows, port' + Chr(130) + ' du FreeCell ' +
                            'd''OS/2-0 (lui-m' + Chr(136) + 'me port' + Chr(130) + ' du prototype FREECELL.PAS de 7iles).' +
                            Chr(10) + 'Programme ' + Chr(130) + 'crit en Pascal et compil' + Chr(130) + ' par WPC.', 'A propos de FreeCell', MB_OK Or MB_INFORMATION);
  End;
End;

{ ou est le clic ? }
Procedure Click(Mx, My : LongInt; Dbl : Boolean);
Var X, Y, I, K, Sp : LongInt;
Begin
  X := Mx; Y := My;
  If Won <> 0 Then Exit;
  I := (X - SX0) Div SDX;
  If (X < SX0) Or (I > 7) Or (X - SlotX(I) >= CardW) Then
  Begin
    SelZ := 0;
    Redraw;
    Exit;
  End;
  If (Y >= TopY) And (Y < TopY + CardH) Then
  Begin
    If I < 4 Then
    Begin
      If Dbl And (SelZ = 1) And (SelI = I) Then DoubleClick Else FreeClick(I);
    End
    Else FoundClick;
    Exit;
  End;
  If Y >= ColY Then
  Begin
    If ColN[I] = 0 Then
    Begin
      If SelZ <> 0 Then ColClick(I, 0);
      Exit;
    End;
    Sp := StepOf(I);
    K := (Y - ColY) Div Sp;
    If K >= ColN[I] Then
    Begin
      If Y - ColY - (ColN[I] - 1) * Sp < CardH Then K := ColN[I] - 1 Else
      Begin
        If SelZ <> 0 Then ColClick(I, -1);
        Exit;
      End;
    End;
    If Dbl And (SelZ = 2) And (SelI = I) Then DoubleClick
    Else If Dbl And (SelZ = 0) Then Begin SelectCol(I, -1); DoubleClick; End
    Else ColClick(I, K);
  End;
End;

{ touches (WM_KEYDOWN) : F1, F2, F3, Retour arriere, Echap, Ctrl+Z }
Function KeyDown(Vk : LongInt) : Boolean;
Begin
  KeyDown := True;
  If (GetKeyState(VK_CONTROL) < 0) And (Vk = Ord('Z')) Then Begin UndoMove; Exit; End;
  Case Vk Of
    VK_F1 : Command(CM_RULES);
    VK_F2 : Command(CM_NEW);
    VK_F3 : Command(CM_RESTART);
    VK_BACK : UndoMove;
    VK_ESCAPE : Begin SelZ := 0; Redraw; End;
  Else
    KeyDown := False;
  End;
End;

{ caracteres (WM_CHAR) : 1 a 8, A a D, H }
Function KeyChar(Ch : LongInt) : Boolean;
Var I : LongInt;
Begin
  KeyChar := True;
  If (Ch < 32) Or (GetKeyState(VK_CONTROL) < 0) Or (Won <> 0) Then
  Begin
    KeyChar := False;
    Exit;
  End;
  Case UpCase(Chr(Ch)) Of
    '1'..'8' :
      Begin
        I := Ch - Ord('1');
        If SelZ = 0 Then SelectCol(I, -1) Else ColClick(I, -1);
      End;
    'A'..'D' : FreeClick(Ord(UpCase(Chr(Ch))) - Ord('A'));
    'H' : FoundClick;
  Else
    KeyChar := False;
  End;
End;

Function MainProc(H, Msg0, WP, LP : LongInt) : LongInt; stdcall;
Var Rc : Array[0..3] Of LongInt;
Begin
  MainProc := 0;
  Case Msg0 Of
    WM_SIZE :
      Begin
        Dummy := GetClientRect(H, LongInt(@Rc));
        If (Rc[2] > 0) And (Rc[3] > 0) Then
        Begin
          CW := MinI(Rc[2], CWant); CH := MinI(Rc[3], CHWant);
        End;
      End;
    WM_PAINT : PaintAll(H);
    WM_ERASEBKGND : MainProc := 1;
    WM_TIMER : If WP = 1 Then TimerTick;
    WM_LBUTTONDOWN :
      Begin
        Dummy := SetFocus(H);
        Click(S16(LP), S16(LP Shr 16), False);
      End;
    WM_LBUTTONDBLCLK : Click(S16(LP), S16(LP Shr 16), True);
    WM_COMMAND : If LP = 0 Then Command(Lo16(WP));
    WM_KEYDOWN : If Not KeyDown(WP) Then MainProc := DefWindowProcA(H, Msg0, WP, LP);
    WM_CHAR : If Not KeyChar(WP) Then MainProc := DefWindowProcA(H, Msg0, WP, LP);
    WM_CLOSE : Dummy := DestroyWindow(H);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc := DefWindowProcA(H, Msg0, WP, LP);
  End;
End;

{ ==================================================================== }
{ Menus                                                                 }
{ ==================================================================== }

{ article : ~ (lettre soulignee de PM) devient & ; Id 0 : separateur }
Procedure MItem(M, Id : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  If Id = 0 Then Dummy := AppendMenuA(M, MF_SEPARATOR, 0, 0)
  Else Dummy := AppendMenuA(M, MF_STRING, Id, Z(Win(S)));
End;

Procedure MSub(P : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do If S[K] = '~' Then S[K] := '&';
  Dummy := AppendMenuA(MenuBar, MF_POPUP, P, Z(Win(S)));
End;

{ Pasdows 95 (ProductName du registre) affiche les programmes de WPC
  avec la police de l'ecran (page 437) : textes passes tels quels ;
  sous Windows, les menus et boites de message sont en ANSI }
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
    S := '';
    T := 0;
    While (T < 7) And (B[T] <> 0) Do Begin S := S + UpCase(Chr(B[T])); Inc(T); End;
    If S = 'PASDOWS' Then OemOut := 1;
  End;
  Dummy := RegCloseKey(K);
End;

Procedure RegClass(Name : String; Proc, Style, Cur : LongInt);
Var C : TWndCls;
Begin
  PutZ(LongInt(@NameZ2), Name);
  C.Style := Style; C.Proc := Proc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := Cur; C.Brush := 0;
  C.MenuName := 0; C.ClassName := LongInt(@NameZ2);
  Dummy := RegisterClassA(LongInt(@C));
End;

Var
  Flg, Sw, Sh, Fw, Fh, K, E, X, Y, D0, Dc : LongInt;
  Rc : Array[0..3] Of LongInt;
  S : String;

BEGIN
  Inst := GetModuleHandleA(0);
  DetectOem;
  Seed := GetTickCount And $7FFFFFFF;
  Msg := ''; AutoAll := 0; Client := 0; Frame := 0; AutoF := 1; Multi := 1; Wins := 0; Played := 0; Streak := 0;
  Pending := 0; D0 := 0; Moves := 0; MenuPop[1] := 0;
  For K := 1 To ParamCount Do
  Begin
    S := ParamStr(K);
    For E := 1 To Length(S) Do S[E] := UpCase(S[E]);
    If (Length(S) > 6) And (Copy(S, 1, 6) = '/SEED:') Then Val(Copy(S, 7, 20), Seed, E);
    If (Length(S) > 6) And (Copy(S, 1, 6) = '/DEAL:') Then Val(Copy(S, 7, 20), D0, E);
    If S = '/AUTO' Then AutoAll := 1;
  End;
  If (D0 < 1) Or (D0 > 32000) Then D0 := 1 + Rnd(32000);
  { pinceaux et plumes des couleurs de PM, polices OEM 8 x 16 et 16 x 32 }
  For K := -2 To 15 Do
  Begin
    Brush[K + 2] := CreateSolidBrush(ClrRgb(K));
    Pen[K + 2] := CreatePen(0, 1, ClrRgb(K));
  End;
  NullBr := GetStockObject(NULL_BRUSH); NullPen := GetStockObject(NULL_PEN);
  PutZ(LongInt(@NameZ2), 'Terminal');
  FontS := CreateFontA(16, 8, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  FontL := CreateFontA(32, 16, 0, 0, 400, 0, 0, 0, OEM_CHARSET, 0, 0, 0, 1, LongInt(@NameZ2));
  RegClass('FreeCellWnd', LongInt(@MainProc), CS_DBLCLKS, LoadCursorA(0, IDC_ARROW));
  Flg := WS_CAPTION Or WS_SYSMENU Or WS_MINIMIZEBOX;
  CW := CWant; CH := CHWant;
  Rc[0] := 0; Rc[1] := 0; Rc[2] := CWant; Rc[3] := CHWant;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), Flg, 1, 0);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  Sw := GetSystemMetrics(SM_CXSCREEN); Sh := GetSystemMetrics(SM_CYSCREEN);
  { petit ecran (640 x 480) : les colonnes se resserrent }
  If Fh > Sh - 28 Then
  Begin
    CH := MaxI(360, CHWant - (Fh - (Sh - 28)));
    Fh := Fh - (CHWant - CH);
  End;
  X := MaxI(0, (Sw - Fw) Div 2); Y := MaxI(0, (Sh - 28 - Fh) Div 2);
  PutZ(LongInt(@NameZ2), 'FreeCellWnd');
  Frame := CreateWindowExA(0, LongInt(@NameZ2), Z('FreeCell'), Flg, X, Y, Fw, Fh, 0, 0, Inst, 0);
  If Frame = 0 Then ExitProcess(1);
  Client := Frame;
  MenuBar := CreateMenu;
  For K := 0 To 2 Do MenuPop[K] := CreatePopupMenu;
  MItem(MenuPop[0], CM_NEW, '~Nouvelle donne' + Chr(9) + 'F2');
  MItem(MenuPop[0], CM_NEXT, 'Donne ~suivante');
  MItem(MenuPop[0], CM_RESTART, '~Rejouer la donne' + Chr(9) + 'F3');
  MItem(MenuPop[0], CM_UNDO, '~Annuler le coup' + Chr(9) + 'Ctrl+Z');
  MItem(MenuPop[0], 0, '');
  MItem(MenuPop[0], CM_QUIT, '~Quitter');
  MItem(MenuPop[1], CM_AUTOF, 'Cartes aux ~fondations automatiquement');
  MItem(MenuPop[1], CM_MULTI, '~D' + Chr(130) + 'placer plusieurs cartes ' + Chr(133) + ' la fois');
  MItem(MenuPop[2], CM_RULES, '~R' + Chr(138) + 'gles du jeu' + Chr(9) + 'F1');
  MItem(MenuPop[2], CM_ABOUT, '~A propos de FreeCell');
  MSub(MenuPop[0], '~Partie');
  MSub(MenuPop[1], '~Options');
  MSub(MenuPop[2], '~?');
  Dummy := SetMenu(Frame, MenuBar);
  { image en memoire de la zone client }
  Dc := GetDC(Client);
  MemDC := CreateCompatibleDC(Dc);
  MemBmp := CreateCompatibleBitmap(Dc, CWant, CHWant);
  Dummy := ReleaseDC(Client, Dc);
  Dummy := SelectObject(MemDC, MemBmp);
  Dummy := SelectObject(MemDC, FontS);
  Dummy := SetBkMode(MemDC, OPAQUE);
  Hps := MemDC;
  SetMarks;
  NewDeal(D0);
  Dummy := ShowWindow(Frame, 1);
  Dummy := UpdateWindow(Frame);
  If AutoAll <> 0 Then Dummy := SetTimer(Client, 1, 250, 0)
  Else Dummy := SetTimer(Client, 1, 90, 0);
  Dummy := SetFocus(Client);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  ExitProcess(0);
END.
