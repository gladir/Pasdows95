{ WINHLP32.PAS - Aide de Windows (visionneuse WinHelp) de Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 WINHLP32.PAS WINHLP32.EXE

  Lit et affiche les fichiers d'aide de Windows (.HLP) des versions 3.1
  et 4.0, ceux des programmes de Windows 95 et d'Office 97, comme
  WINHLP32.EXE de Windows 95 :

  - conteneur WinHelp : en-tete, repertoire des fichiers internes en
    arbre B, |SYSTEM (titre, rubrique de sommaire, compression) ;
  - |TOPIC : blocs de 4 Ko compresses en LZ77, enregistrements
    TOPICLINK (en-tetes de rubrique, paragraphes, tableaux), textes
    compresses par phrases (|Phrases de WinHelp 3.1, ou |PhrIndex et
    |PhrImage de WinHelp 4) ;
  - mise en forme : polices de |FONT (taille, gras, souligne, couleur),
    retraits, espacements, tabulations, alignement, tableaux, zone non
    defilante, images |bmN (SHG et MRB : DIB et DDB, RLE et LZ77) avec
    leurs zones sensibles ;
  - liens : sauts et fenetres contextuelles (|CONTEXT), liens vers
    d'autres fichiers, macros JumpId, PopupId, JumpContext,
    JumpKeyword, KLink, ALink, Contents, Finder, Back, ExecFile... ;
  - Rubriques d'aide : Sommaire (fichier .CNT, livres ouverts ou
    fermes), Index (|KWBTREE et |KWDATA) et Rechercher (recherche du
    texte dans toutes les rubriques) ;
  - boutons Rubriques d'aide, Precedent, << et >> (sequences de
    lecture), menus Fichier, Edition (Copier), Options (taille du
    texte) ;
  - ligne de commande : WINHLP32 [-k motcle | -n numero | -i contexte |
    -p numero] [chemin\]fichier.hlp ; un fichier sans chemin est
    cherche dans le dossier courant, dans C:\WINDOWS\HELP, C:\WINDOWS,
    C:\WINDOWS\SYSTEM et dans la cle du registre
    HKLM\Software\Microsoft\Windows\Help (dossiers des fichiers d'aide
    des programmes installes). -p affiche seulement la fenetre
    contextuelle de la rubrique (aide "Qu'est-ce que c'est ?").

  Le format est celui documente par M. Winterhoff (helpfile.txt) ; la
  visionneuse DEVENV.PAS de DEV-COOLS, qui lit le format de HC.PAS, en
  a donne l'organisation (chargement, decompression, table des
  rubriques, historique). L'interface suit la variable d'environnement
  LANGUAGE (FR, EN, GR, IT, SP). }

Program WinHlp32;

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
  TRect = Record
    L, T, R, B : LongInt;
  End;
  TPaint = Record
    Hdc, Erase : LongInt;
    Rc : TRect;
    Rest : Array[0..39] Of Byte;
  End;
  TPoint = Record
    X, Y : LongInt;
  End;
  PByt = ^Byte;
  PWrd = ^Word;
  PLng = ^LongInt;
  TLongArr = Array[0..$3FFFFFF] Of LongInt;
  PLongArr = ^TLongArr;

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
Function TranslateMessage(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function PostMessageA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'PostMessageA';
Function SendMessageA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SendMessageA';
Function BeginPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function InvalidateRect(H : LongInt; R : Pointer; E : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'InvalidateRect';
Function MessageBoxA(H : LongInt; T, C : PChar; F : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'MessageBoxA';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function SetCursor(C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCursor';
Function FillRect(Hdc : LongInt; Var R : TRect; Br : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'FillRect';
Function GetClientRect(H : LongInt; Var R : TRect) : LongInt; stdcall;
  external 'user32.dll' name 'GetClientRect';
Function MoveWindow(H, X, Y, W, Hh, Rp : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MoveWindow';
Function SetWindowTextA(H : LongInt; S : PChar) : LongInt; stdcall;
  external 'user32.dll' name 'SetWindowTextA';
Function GetWindowTextA(H : LongInt; B : Pointer; N : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'GetWindowTextA';
Function EnableWindow(H, E : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnableWindow';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function GetCursorPos(Var P : TPoint) : LongInt; stdcall;
  external 'user32.dll' name 'GetCursorPos';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetSystemMetrics';
Function SetScrollRange(H, Bar, Mn, Mx, Rd : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetScrollRange';
Function SetScrollPos(H, Bar, P, Rd : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetScrollPos';
Function CreateMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(H, F, Id : LongInt; S : PChar) : LongInt; stdcall;
  external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetMenu';
Function CheckMenuItem(H, Id, F : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CheckMenuItem';
Function OpenClipboard(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'OpenClipboard';
Function CloseClipboard : LongInt; stdcall;
  external 'user32.dll' name 'CloseClipboard';
Function EmptyClipboard : LongInt; stdcall;
  external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetClipboardData';
Function IsWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'IsWindow';
Function GetKeyState(K : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetKeyState';
Function SetCapture(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseCapture';
Function GetOpenFileNameA(P : Pointer) : LongInt; stdcall;
  external 'comdlg32.dll' name 'GetOpenFileNameA';
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
Function SelectObject(Hdc, H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function DeleteObject(H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
Function MoveToEx(Hdc, X, Y : LongInt; P : Pointer) : LongInt; stdcall;
  external 'gdi32.dll' name 'MoveToEx';
Function GdiLineTo(Hdc, X, Y : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'LineTo';
Function CreateFontA(H, W, E, O, Wt, It, Un, So, Cs, Op, Cp, Q, Pf : LongInt;
  F : PChar) : LongInt; stdcall; external 'gdi32.dll' name 'CreateFontA';
Function SetDIBitsToDevice(Hdc, X, Y, W, H, SX, SY, S0, N : LongInt;
  Bits, Bmi : Pointer; U : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetDIBitsToDevice';
Function GetModuleHandleA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetCommandLineA : LongInt; stdcall;
  external 'kernel32.dll' name 'GetCommandLineA';
Function GetEnvironmentVariableA(N : PChar; B : Pointer; Sz : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalAlloc';
Function GlobalFree(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalFree';
Function CreateFileA(N : PChar; A, S : LongInt; Sc : Pointer; D, F,
  T : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileA';
Function ReadFile(H : LongInt; B : Pointer; N : LongInt; Var R : LongInt;
  O : Pointer) : LongInt; stdcall; external 'kernel32.dll' name 'ReadFile';
Function GetFileSize(H : LongInt; P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetFileSize';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Function GetFileAttributesA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetFileAttributesA';
Function WinExec(C : PChar; S : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'WinExec';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function RegOpenKeyExA(K : LongInt; S : PChar; O, Sam : LongInt;
  Var R : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(K : LongInt; N : PChar; R : Pointer;
  Var T : LongInt; D : Pointer; Var L : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';

Const
  WM_CREATE = 1; WM_DESTROY = 2; WM_SIZE = 5; WM_ACTIVATE = 6;
  WM_SETFOCUS = 7; WM_PAINT = $F; WM_CLOSE = $10; WM_SETFONT = $30;
  WM_KEYDOWN = $100; WM_CHAR = $102; WM_COMMAND = $111; WM_TIMER = $113;
  WM_VSCROLL = $115; WM_MOUSEMOVE = $200; WM_LBUTTONDOWN = $201;
  WM_LBUTTONUP = $202; WM_LBUTTONDBLCLK = $203; WM_RBUTTONDOWN = $204;
  WM_MOUSEWHEEL = $20A; WM_SETCURSOR = $20;
  WS_CHILD = $40000000; WS_VISIBLE = $10000000; WS_TABSTOP = $10000;
  WS_BORDER = $800000; WS_POPUP = LongInt($80000000);
  WS_OVERLAPPEDWINDOW = $CF0000; WS_CAPTION = $C00000;
  WS_SYSMENU = $80000; WS_CLIPCHILDREN = $2000000;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1;
  SBS_VERT = 1; SB_CTL = 2;
  SB_LINEUP = 0; SB_LINEDOWN = 1; SB_PAGEUP = 2; SB_PAGEDOWN = 3;
  SB_THUMBPOSITION = 4; SB_THUMBTRACK = 5; SB_TOP = 6; SB_BOTTOM = 7;
  EN_CHANGE = $300;
  MF_STRING = 0; MF_GRAYED = 1; MF_CHECKED = 8; MF_POPUP = $10;
  MF_SEPARATOR = $800;
  MB_OK = 0; MB_ICONSTOP = $10; MB_ICONINFO = $40;
  HKLM = LongInt($80000002); KEY_READ = $20019;
  cWhite = $FFFFFF; cBlack = 0; cFace = $C0C0C0; cGray = $808080;
  cNavy = $800000; cGreen = $008000; cPopBg = $E1FFFF;
  { identifiants }
  idBtnTopics = 10; idBtnBack = 11; idBtnPrev = 12; idBtnNext = 13;
  idBtnOptions = 14; idScroll = 20;
  idOpen = 100; idExit = 101; idCopy = 102; idTopics = 103;
  idFontS = 104; idFontN = 105; idFontL = 106; idAbout = 107;
  idPrevMenu = 108;
  idTabCnt = 200; idTabIdx = 201; idTabFind = 202; idTEdit = 210;
  idTShow = 211; idTCancel = 212; idTFind = 213; idTScroll = 214;
  { tailles }
  MaxTop = 30000;          { rubriques (|TTLBTREE) }
  MaxKw = 30000;           { mots-cles de l'index }
  MaxItem = 8000;          { elements affiches }
  PoolMax = 262144;        { textes des elements }
  MaxCnt = 4000;           { lignes du sommaire (.CNT) }
  MaxHist = 64;            { historique (Precedent) }
  NSlot = 8;               { blocs |TOPIC decompresses gardes }
  MaxImg = 96;             { images decodees gardees }
  MaxHot = 512;            { zones sensibles des images }
  RecMax = 262144;         { taille maximale d'un enregistrement }
  BtnH = 26;               { hauteur de la barre de boutons }
  Margin = 8;
  ScrW = 16;

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
  Inst, Wnd, Lang, Dummy : LongInt;
  { fichier .HLP en memoire }
  FBuf, FLen : LongInt;
  HlpPath, HlpDir, HlpName : String;
  Minor, SysFlags, DirBase : LongInt;
  HlpTitle, HlpCopy : String;
  ContentsOff : LongInt;
  { |TOPIC }
  TopBase, TopLen, BlkSz, NBlk : LongInt;
  Comp : Boolean;
  SlotBlk, SlotLen, SlotBuf, SlotAge : Array[0..NSlot - 1] Of LongInt;
  AgeCnt : LongInt;
  { phrases }
  PhrN, PhrOfs, PhrData : LongInt;
  Hall : Boolean;
  { polices }
  FntN : LongInt;
  FntAttr, FntHp, FntColor : Array[0..1023] Of LongInt;
  HFnt : Array[0..3] Of LongInt;
  FontBias : LongInt;                  { Options, taille du texte }
  { rubriques, contextes, mots-cles }
  NTop : LongInt;
  TopOff, TopTtl : PLongArr;
  CtxBase, CtxoBase, CtxoN : LongInt;
  NKw, KwData : LongInt;
  KwStr, KwCnt, KwOfs : PLongArr;
  { enregistrement courant }
  RecBuf, L2Buf : LongInt;
  RBs, RDl2, RPrev, RNext, RDl1, RType, L1, L1Len, L2Len : LongInt;
  { elements affiches : texte (0), image (1) }
  NItem : LongInt;
  ItKind, ItX, ItY, ItW, ItH, ItFnt, ItTxt, ItLen, ItLink, ItVal, ItRgn,
    ItAux : Array[0..MaxItem - 1] Of LongInt;
  Pool, PoolN : LongInt;
  { rubrique affichee }
  CurOff, CurTp, CurBck, CurFor : LongInt;
  CurTitle : String;
  ScrollY, DocH, NsH, ViewH, ViewW : LongInt;
  AnchorY : LongInt;
  HistOff, HistY : Array[0..MaxHist - 1] Of LongInt;
  HistFile : Array[0..MaxHist - 1] Of String[79];
  NHist : LongInt;
  { fenetre contextuelle }
  PopWnd, PopW, PopH, PopFirst : LongInt;
  PopOnly : Boolean;
  { images }
  ImgNum, ImgW, ImgH, ImgBits, ImgHot0, ImgHotN : Array[0..MaxImg - 1]
    Of LongInt;
  NImg : LongInt;
  HotX, HotY, HotW, HotH, HotKind, HotVal : Array[0..MaxHot - 1] Of LongInt;
  NHot : LongInt;
  Bmi : Array[0..9] Of LongInt;
  { controles }
  BtnTopics, BtnBack, BtnPrev, BtnNext, ScrollBar : LongInt;
  BrWhite, BrFace, BrPop, BrNavy, PenGreen, PenGray, PenBlack, PenWhite : LongInt;
  CurArrow, CurHand, CurWait : LongInt;
  TmpZ, TmpZ2 : String;
  { sommaire (.CNT) }
  NCnt : LongInt;
  CntLvl, CntBook, CntOpen, CntTxt, CntCtx, CntFile : Array[0..MaxCnt - 1]
    Of LongInt;
  CntPool, CntPoolN : LongInt;
  CntTitle, CntBase : String;
  { liste des rubriques trouvees (index, recherche) }
  NFound : LongInt;
  FoundOff : PLongArr;
  { fenetre Rubriques d'aide }
  TopWnd, TopTab, TEdit, TShow, TCancel, TFind, TScroll : LongInt;
  LstN, LstTop, LstSel, LstMode : LongInt;
  LstMap : PLongArr;
  LstX, LstY, LstWd, LstHt : LongInt;
  FoundMode : Boolean;
  MenuOpt : LongInt;

{ ------------------------------------------------------- utilitaires }

Function CStr(A : LongInt) : String;
Var S : String; C : LongInt;
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

Function IntStr(N : LongInt) : String;
Var S : String;
Begin
  Str(N, S);
  IntStr := S;
End;

Function UpStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := UpCase(S[I]);
  UpStr := S;
End;

Function Min(A, B : LongInt) : LongInt;
Begin
  If A < B Then Min := A Else Min := B;
End;

Function Max(A, B : LongInt) : LongInt;
Begin
  If A > B Then Max := A Else Max := B;
End;

{ coordonnees signees d'un message de souris }
Function LoS(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= 32768 Then V := V - 65536;
  LoS := V;
End;

Function HiS(V : LongInt) : LongInt;
Begin
  HiS := LoS((V Shr 16) And $FFFF);
End;

{ mot de 16 bits signe }
Function SW(A : LongInt) : LongInt;
Var V : LongInt;
Begin
  V := PWrd(A)^;
  If V >= 32768 Then V := V - 65536;
  SW := V;
End;

Function Z(S : String) : PChar;
Begin
  TmpZ := S + #0;
  Z := @TmpZ[1];
End;

Function Z2(S : String) : PChar;
Begin
  TmpZ2 := S + #0;
  Z2 := @TmpZ2[1];
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
  S := UpStr(Copy(S, 1, 2));
  If S = 'EN' Then Lang := 1
  Else If (S = 'GR') Or (S = 'DE') Then Lang := 2
  Else If S = 'IT' Then Lang := 3
  Else If (S = 'SP') Or (S = 'ES') Then Lang := 4;
End;

{ Texte dans la langue courante (page de codes 437) }
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

Function AppTitle : String;
Begin
  AppTitle := L('Aide de Windows', 'Windows Help', 'Windows-Hilfe',
                'Guida di Windows', 'Ayuda de Windows');
End;

Procedure Msg(S : String; F : LongInt);
Begin
  MessageBoxA(Wnd, Z(S), Z2(AppTitle), F);
End;

{ caractere ANSI -> page de codes 437 (police de l'ecran) }
Function Oem(C : LongInt) : LongInt;
Begin
  If C >= 128 Then C := AnsiOem[C];
  Oem := C;
End;

Function OemStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := Chr(Oem(Ord(S[I])));
  OemStr := S;
End;

{ majuscule sans accent (comparaisons de l'index, page 437) }
Function Fold(C : LongInt) : LongInt;
Begin
  Case C Of
    97..122 : C := C - 32;
    128, 135 : C := 67;
    129, 150, 151, 154, 163 : C := 85;
    130, 136, 137, 138, 144 : C := 69;
    131, 132, 133, 134, 142, 143, 160 : C := 65;
    139, 140, 141, 161 : C := 73;
    147, 148, 149, 153, 162 : C := 79;
    152 : C := 89;
    164, 165 : C := 78;
  End;
  Fold := C;
End;

Function FoldStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := Chr(Fold(Ord(S[I])));
  FoldStr := S;
End;

{ ------------------------------------------------------- fichiers }

Function FileExists(S : String) : Boolean;
Var A : LongInt;
Begin
  A := GetFileAttributesA(Z(S));
  FileExists := (A <> -1) And ((A And $10) = 0);
End;

{ Fichier entier dans un bloc de memoire (0 si impossible) }
Function LoadFile(S : String; Var N : LongInt) : LongInt;
Var H, A, R : LongInt;
Begin
  LoadFile := 0;
  N := 0;
  H := CreateFileA(Z(S), LongInt($80000000), 1, Nil, 3, $80, 0);
  If H = -1 Then Exit;
  N := GetFileSize(H, Nil);
  If (N <= 0) Or (N > 64000000) Then
  Begin
    CloseHandle(H);
    Exit;
  End;
  A := GlobalAlloc(0, N + 16);
  If A <> 0 Then
  Begin
    R := 0;
    ReadFile(H, Pointer(A), N, R, Nil);
    FillChar(Pointer(A + N)^, 16, 0);
    N := R;
  End;
  CloseHandle(H);
  LoadFile := A;
End;

Function DirOf(S : String) : String;
Var I : LongInt;
Begin
  I := Length(S);
  While (I > 0) And (S[I] <> '\') And (S[I] <> ':') Do Dec(I);
  DirOf := Copy(S, 1, I);
End;

Function BaseOf(S : String) : String;
Begin
  BaseOf := Copy(S, Length(DirOf(S)) + 1, 255);
End;

{ Valeur texte du registre (cle de HKLM) }
Function RegStr(Key, Name : String) : String;
Var K, T, Ln : LongInt; B : Array[0..259] Of Char;
Begin
  RegStr := '';
  If RegOpenKeyExA(HKLM, Z(Key), 0, KEY_READ, K) <> 0 Then Exit;
  Ln := 256; T := 0; B[0] := #0;
  If RegQueryValueExA(K, Z2(Name), Nil, T, @B, Ln) = 0 Then
  Begin
    B[256] := #0;
    RegStr := CStr(LongInt(@B));
  End;
  RegCloseKey(K);
End;

{ Chemin complet d'un fichier d'aide, comme WinHelp : chemin donne,
  dossier du fichier courant, C:\WINDOWS\HELP, C:\WINDOWS,
  C:\WINDOWS\SYSTEM, puis la cle Help du registre }
Function FindHelp(S : String) : String;
Var D : String;
Begin
  FindHelp := S;
  If FileExists(S) Then Exit;
  S := BaseOf(S);
  If (HlpDir <> '') And FileExists(HlpDir + S) Then
  Begin
    FindHelp := HlpDir + S;
    Exit;
  End;
  If FileExists('C:\WINDOWS\HELP\' + S) Then
  Begin
    FindHelp := 'C:\WINDOWS\HELP\' + S;
    Exit;
  End;
  If FileExists('C:\WINDOWS\' + S) Then
  Begin
    FindHelp := 'C:\WINDOWS\' + S;
    Exit;
  End;
  If FileExists('C:\WINDOWS\SYSTEM\' + S) Then
  Begin
    FindHelp := 'C:\WINDOWS\SYSTEM\' + S;
    Exit;
  End;
  D := RegStr('Software\Microsoft\Windows\Help', S);
  If D = '' Then D := RegStr('Software\Microsoft\Windows\Help', UpStr(S));
  If D <> '' Then
  Begin
    If D[Length(D)] <> '\' Then D := D + '\';
    If FileExists(D + S) Then FindHelp := D + S;
  End;
End;

{ -------------------------------------------- conteneur WinHelp }

{ Premiere feuille d'un arbre B (adresse de la page ; 0 si vide) }
Function BtFirst(B : LongInt) : LongInt;
Var P, N, I, PS : LongInt;
Begin
  BtFirst := 0;
  If PWrd(B)^ <> $293B Then Exit;
  PS := PWrd(B + 4)^;
  P := SW(B + 26);
  N := PWrd(B + 32)^;
  For I := 2 To N Do P := SW(B + 38 + P * PS + 4);
  If P < 0 Then Exit;
  BtFirst := B + 38 + P * PS;
End;

{ Feuille suivante (0 a la fin) }
Function BtNext(B, Pg : LongInt) : LongInt;
Var P : LongInt;
Begin
  P := SW(Pg + 6);
  If P < 0 Then BtNext := 0
  Else BtNext := B + 38 + P * PWrd(B + 4)^;
End;

Function ZLen(A : LongInt) : LongInt;
Var N : LongInt;
Begin
  N := 0;
  While PByt(A + N)^ <> 0 Do Inc(N);
  ZLen := N;
End;

{ Fichier interne : adresse et taille de ses donnees }
Function IntFile(Name : String; Var A, N : LongInt) : Boolean;
Var Pg, K, E, O : LongInt;
Begin
  IntFile := False;
  A := 0; N := 0;
  Pg := BtFirst(DirBase);
  While Pg <> 0 Do
  Begin
    E := PWrd(Pg + 2)^;
    O := Pg + 8;
    For K := 1 To E Do
    Begin
      If CStr(O) = Name Then
      Begin
        O := FBuf + PLng(O + ZLen(O) + 1)^;
        If (O < FBuf) Or (O + 9 > FBuf + FLen) Then Exit;
        N := PLng(O + 4)^;
        A := O + 9;
        If A + N > FBuf + FLen Then N := FBuf + FLen - A;
        IntFile := True;
        Exit;
      End;
      O := O + ZLen(O) + 1 + 4;
    End;
    Pg := BtNext(DirBase, Pg);
  End;
End;

{ Decompression LZ77 de WinHelp ; nombre d'octets produits }
Function LzDecomp(Src, SLen, Dst, DMax : LongInt) : LongInt;
Var I, O, Bits, K, W, Ln, Ps : LongInt;
Begin
  I := 0; O := 0;
  While (I < SLen) And (O < DMax) Do
  Begin
    Bits := PByt(Src + I)^;
    Inc(I);
    For K := 0 To 7 Do
    Begin
      If (I >= SLen) Or (O >= DMax) Then Break;
      If (Bits And 1) <> 0 Then
      Begin
        If I + 1 >= SLen Then
        Begin
          I := SLen;
          Break;
        End;
        W := PWrd(Src + I)^;
        I := I + 2;
        Ln := (W Shr 12) + 3;
        Ps := (W And $FFF) + 1;
        While (Ln > 0) And (O < DMax) Do
        Begin
          If Ps <= O Then PByt(Dst + O)^ := PByt(Dst + O - Ps)^
          Else PByt(Dst + O)^ := 32;
          Inc(O);
          Dec(Ln);
        End;
      End
      Else
      Begin
        PByt(Dst + O)^ := PByt(Src + I)^;
        Inc(I);
        Inc(O);
      End;
      Bits := Bits Shr 1;
    End;
  End;
  LzDecomp := O;
End;

{ ------------------------------------------------------- phrases }

Var
  GbAddr, GbEnd, GbVal, GbMask : LongInt;

Function GetBit : Boolean;
Begin
  GbMask := GbMask Shl 1;
  If GbMask = 0 Then
  Begin
    If GbAddr + 4 <= GbEnd Then GbVal := PLng(GbAddr)^ Else GbVal := 0;
    GbAddr := GbAddr + 4;
    GbMask := 1;
  End;
  GetBit := (GbVal And GbMask) <> 0;
End;

Procedure LoadPhrases;
Var A, N, B, BN, I, K, Ln, Bits, Sz, Cs, Off, D : LongInt;
Begin
  PhrN := 0; Hall := False;
  If IntFile('|PhrIndex', A, N) And IntFile('|PhrImage', B, BN) Then
  Begin
    { compression de Hall (WinHelp 4) }
    K := PLng(A + 4)^;
    Bits := PWrd(A + 24)^ And 15;
    Sz := PLng(A + 12)^;
    Cs := PLng(A + 16)^;
    If (K <= 0) Or (K > 200000) Or (Sz <= 0) Then Exit;
    PhrOfs := GlobalAlloc(0, (K + 1) * 4);
    PhrData := GlobalAlloc(0, Sz + 16);
    If (PhrOfs = 0) Or (PhrData = 0) Then Exit;
    If Sz = Cs Then Move(Pointer(B)^, Pointer(PhrData)^, Min(Sz, BN))
    Else Sz := LzDecomp(B, BN, PhrData, Sz);
    GbAddr := A + 28; GbEnd := A + N; GbMask := 0; GbVal := 0;
    Off := 0;
    For I := 0 To K - 1 Do
    Begin
      Ln := 1;
      While GetBit Do Ln := Ln + (1 Shl Bits);
      If GetBit Then Ln := Ln + 1;
      If (Bits > 1) And GetBit Then Ln := Ln + 2;
      If (Bits > 2) And GetBit Then Ln := Ln + 4;
      If (Bits > 3) And GetBit Then Ln := Ln + 8;
      If (Bits > 4) And GetBit Then Ln := Ln + 16;
      PLng(PhrOfs + I * 4)^ := Off;
      Off := Off + Ln;
    End;
    PLng(PhrOfs + K * 4)^ := Off;
    PhrN := K;
    Hall := True;
  End
  Else If IntFile('|Phrases', A, N) Then
  Begin
    { WinHelp 3.1 : table des positions, textes compresses en LZ77 }
    K := PWrd(A)^;
    If (K = 0) Or (Minor <= 16) Then Exit;
    Sz := PLng(A + 4)^;
    PhrOfs := GlobalAlloc(0, (K + 1) * 4);
    PhrData := GlobalAlloc(0, Sz + 16);
    If (PhrOfs = 0) Or (PhrData = 0) Then Exit;
    D := PWrd(A + 8)^;
    For I := 0 To K Do
      PLng(PhrOfs + I * 4)^ := PWrd(A + 8 + I * 2)^ - D;
    B := A + 8 + (K + 1) * 2;
    If (SysFlags And 4) <> 0 Then
      LzDecomp(B, N - (B - A), PhrData, Sz)
    Else Move(Pointer(B)^, Pointer(PhrData)^, Min(Sz, N - (B - A)));
    PhrN := K;
  End;
End;

{ Ajoute la phrase I a Dst (O : position, M : maximum) }
Procedure PutPhrase(I, Dst : LongInt; Var O : LongInt; M : LongInt);
Var A, B : LongInt;
Begin
  If (I < 0) Or (I >= PhrN) Then Exit;
  A := PLng(PhrOfs + I * 4)^;
  B := PLng(PhrOfs + I * 4 + 4)^;
  While (A < B) And (O < M) Do
  Begin
    PByt(Dst + O)^ := PByt(PhrData + A)^;
    Inc(A);
    Inc(O);
  End;
End;

{ Texte compresse par phrases -> Dst ; nombre d'octets produits }
Function Unphrase(Src, SLen, Dst, M : LongInt) : LongInt;
Var I, O, C, N, K : LongInt;
Begin
  I := 0; O := 0;
  While (I < SLen) And (O < M) Do
  Begin
    C := PByt(Src + I)^;
    Inc(I);
    If Hall Then
    Begin
      If (C And 1) = 0 Then PutPhrase(C Shr 1, Dst, O, M)
      Else If (C And 2) = 0 Then
      Begin
        PutPhrase(128 + (C Shr 2) * 256 + PByt(Src + I)^, Dst, O, M);
        Inc(I);
      End
      Else If (C And 4) = 0 Then
      Begin
        N := (C Shr 3) + 1;
        For K := 1 To N Do
          If O < M Then
          Begin
            PByt(Dst + O)^ := PByt(Src + I)^;
            Inc(I);
            Inc(O);
          End;
      End
      Else
      Begin
        N := (C Shr 4) + 1;
        For K := 1 To N Do
          If O < M Then
          Begin
            If (C And 8) = 0 Then PByt(Dst + O)^ := 32
            Else PByt(Dst + O)^ := 0;
            Inc(O);
          End;
      End;
    End
    Else If (C > 0) And (C < 10) And (PhrN > 0) Then
    Begin
      N := 256 * (C - 1) + PByt(Src + I)^;
      Inc(I);
      PutPhrase(N Shr 1, Dst, O, M);
      If ((N And 1) <> 0) And (O < M) Then
      Begin
        PByt(Dst + O)^ := 32;
        Inc(O);
      End;
    End
    Else
    Begin
      PByt(Dst + O)^ := C;
      Inc(O);
    End;
  End;
  Unphrase := O;
End;

{ ---------------------------------------------------------- |TOPIC }

{ Bloc decompresse BN : numero de case du cache (-1 si absent) }
Function GetBlk(BN : LongInt) : LongInt;
Var I, S, Src, N : LongInt;
Begin
  GetBlk := -1;
  If (BN < 0) Or (BN >= NBlk) Then Exit;
  Inc(AgeCnt);
  For I := 0 To NSlot - 1 Do
    If SlotBlk[I] = BN Then
    Begin
      SlotAge[I] := AgeCnt;
      GetBlk := I;
      Exit;
    End;
  S := 0;
  For I := 1 To NSlot - 1 Do
    If SlotAge[I] < SlotAge[S] Then S := I;
  Src := TopBase + BN * BlkSz + 12;
  N := Min(BlkSz, TopLen - BN * BlkSz) - 12;
  If N < 0 Then N := 0;
  If Comp Then SlotLen[S] := LzDecomp(Src, N, SlotBuf[S], 16384)
  Else
  Begin
    Move(Pointer(Src)^, Pointer(SlotBuf[S])^, N);
    SlotLen[S] := N;
  End;
  SlotBlk[S] := BN;
  SlotAge[S] := AgeCnt;
  GetBlk := S;
End;

{ Champ K (0 : dernier lien, 1 : premier lien, 2 : dernier en-tete)
  de l'en-tete du bloc BN }
Function BlkHdr(BN, K : LongInt) : LongInt;
Begin
  If (BN < 0) Or (BN >= NBlk) Then BlkHdr := -1
  Else BlkHdr := PLng(TopBase + BN * BlkSz + K * 4)^;
End;

{ N octets a partir de la position TP (TOPICPOS) ; False si hors du
  fichier }
Function CopyTopic(TP, N, Dst : LongInt) : Boolean;
Var BN, Off, S, T : LongInt;
Begin
  CopyTopic := False;
  BN := TP Shr 14;
  Off := (TP And $3FFF) - 12;
  If Off < 0 Then Exit;
  While N > 0 Do
  Begin
    S := GetBlk(BN);
    If S < 0 Then
    Begin
      FillChar(Pointer(Dst)^, N, 0);
      Exit;
    End;
    T := SlotLen[S] - Off;
    If T > 0 Then
    Begin
      If T > N Then T := N;
      Move(Pointer(SlotBuf[S] + Off)^, Pointer(Dst)^, T);
      N := N - T;
      Dst := Dst + T;
    End;
    Inc(BN);
    Off := 0;
  End;
  CopyTopic := True;
End;

{ Lit l'enregistrement TOPICLINK en TP ; LinkData2 decompresse dans
  L2Buf (L2Len octets) }
Function ReadRec(TP : LongInt) : Boolean;
Var N : LongInt;
Begin
  ReadRec := False;
  If (TP <= 0) Or Not CopyTopic(TP, 21, RecBuf) Then Exit;
  RBs := PLng(RecBuf)^; RDl2 := PLng(RecBuf + 4)^;
  RPrev := PLng(RecBuf + 8)^; RNext := PLng(RecBuf + 12)^;
  RDl1 := PLng(RecBuf + 16)^; RType := PByt(RecBuf + 20)^;
  If (RBs < 21) Or (RBs > RecMax) Or (RDl1 < 21) Or (RDl1 > RBs) Then Exit;
  If Not CopyTopic(TP, RBs, RecBuf) Then Exit;
  FillChar(Pointer(RecBuf + RBs)^, 16, 0);
  L1 := RecBuf + 21;
  L1Len := RDl1 - 21;
  N := RBs - RDl1;
  If RDl2 > RecMax - 16 Then RDl2 := RecMax - 16;
  If (RDl2 > N) And ((PhrN > 0) Or Hall) Then
    L2Len := Unphrase(RecBuf + RDl1, N, L2Buf, RDl2)
  Else
  Begin
    L2Len := Min(N, RecMax - 16);
    Move(Pointer(RecBuf + RDl1)^, Pointer(L2Buf)^, L2Len);
  End;
  FillChar(Pointer(L2Buf + L2Len)^, 16, 0);
  ReadRec := True;
End;

{ entiers compresses de LinkData1 }
Function ScanW(Var P : LongInt) : LongInt;
Begin
  If (PByt(P)^ And 1) <> 0 Then
  Begin
    ScanW := PWrd(P)^ Shr 1;
    P := P + 2;
  End
  Else
  Begin
    ScanW := PByt(P)^ Shr 1;
    Inc(P);
  End;
End;

Function ScanI(Var P : LongInt) : LongInt;
Begin
  If (PByt(P)^ And 1) <> 0 Then
  Begin
    ScanI := (PWrd(P)^ Shr 1) - $4000;
    P := P + 2;
  End
  Else
  Begin
    ScanI := (PByt(P)^ Shr 1) - $40;
    Inc(P);
  End;
End;

Function ScanL(Var P : LongInt) : LongInt;
Begin
  If (PByt(P)^ And 1) <> 0 Then
  Begin
    ScanL := (PLng(P)^ Shr 1) - $40000000;
    P := P + 4;
  End
  Else
  Begin
    ScanL := (PWrd(P)^ Shr 1) - $4000;
    P := P + 2;
  End;
End;

{ Nombre de caracteres (TopicLength) d'un enregistrement d'affichage }
Function RecChars : LongInt;
Var P : LongInt;
Begin
  RecChars := 0;
  If (RType <> $20) And (RType <> $23) Then Exit;
  P := L1;
  ScanL(P);
  RecChars := ScanW(P);
End;

{ -------------------------------------------- rubriques et contextes }

{ Rubrique (index dans TopOff) qui contient TOPICOFFSET Off }
Function TopicIdx(Off : LongInt) : LongInt;
Var A, B, M : LongInt;
Begin
  TopicIdx := -1;
  If NTop = 0 Then Exit;
  A := 0; B := NTop - 1;
  If Off < TopOff^[0] Then
  Begin
    TopicIdx := 0;
    Exit;
  End;
  While A < B Do
  Begin
    M := (A + B + 1) Div 2;
    If TopOff^[M] <= Off Then A := M Else B := M - 1;
  End;
  TopicIdx := A;
End;

{ TOPICPOS de l'en-tete de la rubrique qui commence en TOPICOFFSET
  Off : le compteur de caracteres repart de zero a chaque bloc }
Function HeaderPos(Off : LongInt) : LongInt;
Var BN, C, CC, TP, N : LongInt;
Begin
  HeaderPos := -1;
  BN := Off Shr 15;
  C := Off And $7FFF;
  TP := BlkHdr(BN, 1);
  CC := 0; N := 0;
  While (TP > 0) And ((TP Shr 14) = BN) And (N < 20000) Do
  Begin
    If Not ReadRec(TP) Then Exit;
    If RType = 2 Then
    Begin
      If CC = C Then
      Begin
        HeaderPos := TP;
        Exit;
      End;
      If CC > C Then Exit;
    End
    Else CC := CC + RecChars;
    TP := RNext;
    Inc(N);
  End;
End;

{ Contexte (valeur de hachage) -> TOPICOFFSET (-1 si absent) }
Function CtxLookup(Hash : LongInt) : LongInt;
Var Pg, E, K, O : LongInt;
Begin
  CtxLookup := -1;
  If CtxBase = 0 Then Exit;
  Pg := BtFirst(CtxBase);
  While Pg <> 0 Do
  Begin
    E := PWrd(Pg + 2)^;
    O := Pg + 8;
    For K := 1 To E Do
    Begin
      If PLng(O)^ = Hash Then
      Begin
        CtxLookup := PLng(O + 4)^;
        Exit;
      End;
      O := O + 8;
    End;
    Pg := BtNext(CtxBase, Pg);
  End;
End;

{ Valeur de hachage d'un nom de contexte (comme le compilateur) }
Function HashCtx(S : String) : LongInt;
Var H, I, C, V : LongInt;
Begin
  H := 0;
  If S = '' Then
  Begin
    HashCtx := 1;
    Exit;
  End;
  For I := 1 To Length(S) Do
  Begin
    C := Ord(S[I]);
    Case C Of
      49..57 : V := C - 48;
      48 : V := 10;
      65..90 : V := C - 65 + $11;
      97..122 : V := C - 97 + $11;
      46 : V := $0C;
      95 : V := $0D;
    Else
      V := C;
    End;
    H := H * 43 + V;
  End;
  HashCtx := H;
End;

{ Numero de |CTXOMAP (HELP_CONTEXT) -> TOPICOFFSET }
Function MapLookup(N : LongInt) : LongInt;
Var I : LongInt;
Begin
  MapLookup := -1;
  For I := 0 To CtxoN - 1 Do
    If PLng(CtxoBase + I * 8)^ = N Then
    Begin
      MapLookup := PLng(CtxoBase + I * 8 + 4)^;
      Exit;
    End;
End;

{ Titre de la rubrique I }
Function TopicTitle(I : LongInt) : String;
Begin
  If (I < 0) Or (I >= NTop) Then TopicTitle := ''
  Else TopicTitle := OemStr(CStr(TopTtl^[I]));
End;

{ ------------------------------------------------------- polices }

Procedure LoadFonts;
Var A, N, NF, ND, FO, DO_, I, O : LongInt;
Begin
  FntN := 0;
  If Not IntFile('|FONT', A, N) Then Exit;
  NF := PWrd(A)^; ND := PWrd(A + 2)^;
  FO := PWrd(A + 4)^; DO_ := PWrd(A + 6)^;
  If ND > 1024 Then ND := 1024;
  For I := 0 To ND - 1 Do
  Begin
    O := A + DO_ + I * 11;
    If O + 11 > A + N Then Break;
    FntAttr[I] := PByt(O)^;
    FntHp[I] := PByt(O + 1)^;
    FntColor[I] := PByt(O + 5)^ Or (PByt(O + 6)^ Shl 8) Or
                   (PByt(O + 7)^ Shl 16);
    { couleur 01 01 00 : couleur par defaut }
    If (FntColor[I] = $000101) Or (FntColor[I] = $010100) Then
      FntColor[I] := 0;
    FntN := I + 1;
  End;
End;

{ classe de taille (0 : 6x13, 1 : 8x16, 2 : 12x24, 3 : 16x32) }
Function FntCls(F : LongInt) : LongInt;
Var Px, C : LongInt;
Begin
  If (F < 0) Or (F >= FntN) Then Px := 12 Else Px := FntHp[F] * 2 Div 3;
  If Px <= 14 Then C := 0
  Else If Px <= 20 Then C := 1
  Else If Px <= 28 Then C := 2
  Else C := 3;
  C := C + FontBias;
  If C < 0 Then C := 0;
  If C > 3 Then C := 3;
  FntCls := C;
End;

Function ClsW(C : LongInt) : LongInt;
Begin
  Case C Of
    0 : ClsW := 6;
    1 : ClsW := 8;
    2 : ClsW := 12;
  Else
    ClsW := 16;
  End;
End;

Function ClsH(C : LongInt) : LongInt;
Begin
  Case C Of
    0 : ClsH := 13;
    1 : ClsH := 16;
    2 : ClsH := 24;
  Else
    ClsH := 32;
  End;
End;

{ ------------------------------------------- chargement du fichier }

Procedure FreeHelp;
Var I : LongInt;
Begin
  If FBuf <> 0 Then GlobalFree(FBuf);
  If PhrOfs <> 0 Then GlobalFree(PhrOfs);
  If PhrData <> 0 Then GlobalFree(PhrData);
  For I := 0 To NImg - 1 Do
    If ImgBits[I] <> 0 Then GlobalFree(ImgBits[I]);
  FBuf := 0; FLen := 0; PhrOfs := 0; PhrData := 0; PhrN := 0;
  NImg := 0; NHot := 0; NTop := 0; NKw := 0; CtxBase := 0; CtxoN := 0;
  NCnt := 0; KwData := 0;
  For I := 0 To NSlot - 1 Do
  Begin
    SlotBlk[I] := -1;
    SlotAge[I] := 0;
  End;
End;

Procedure LoadSystem;
Var A, N, O, T, Sz : LongInt;
Begin
  Minor := 0; SysFlags := 0; HlpTitle := ''; HlpCopy := '';
  ContentsOff := -1;
  If Not IntFile('|SYSTEM', A, N) Then Exit;
  Minor := PWrd(A + 2)^;
  SysFlags := PWrd(A + 10)^;
  If Minor <= 16 Then
  Begin
    HlpTitle := CStr(A + 12);
    Exit;
  End;
  O := A + 12;
  While O + 4 <= A + N Do
  Begin
    T := PWrd(O)^; Sz := PWrd(O + 2)^;
    Case T Of
      1 : HlpTitle := CStr(O + 4);
      2 : HlpCopy := CStr(O + 4);
      3 : ContentsOff := PLng(O + 4)^;
    End;
    O := O + 4 + Sz;
  End;
  HlpTitle := OemStr(HlpTitle);
  HlpCopy := OemStr(HlpCopy);
End;

Procedure LoadTitles;
Var A, N, Pg, E, K, O : LongInt;
Begin
  NTop := 0;
  If Not IntFile('|TTLBTREE', A, N) Then Exit;
  Pg := BtFirst(A);
  While (Pg <> 0) And (NTop < MaxTop) Do
  Begin
    E := PWrd(Pg + 2)^;
    O := Pg + 8;
    For K := 1 To E Do
    Begin
      If NTop >= MaxTop Then Break;
      TopOff^[NTop] := PLng(O)^;
      TopTtl^[NTop] := O + 4;
      Inc(NTop);
      O := O + 4 + ZLen(O + 4) + 1;
    End;
    Pg := BtNext(A, Pg);
  End;
End;

Procedure LoadKeywords;
Var A, N, Pg, E, K, O : LongInt;
Begin
  NKw := 0; KwData := 0;
  If Not IntFile('|KWDATA', KwData, N) Then KwData := 0;
  If Not IntFile('|KWBTREE', A, N) Then Exit;
  Pg := BtFirst(A);
  While (Pg <> 0) And (NKw < MaxKw) Do
  Begin
    E := PWrd(Pg + 2)^;
    O := Pg + 8;
    For K := 1 To E Do
    Begin
      If NKw >= MaxKw Then Break;
      KwStr^[NKw] := O;
      O := O + ZLen(O) + 1;
      KwCnt^[NKw] := PWrd(O)^;
      KwOfs^[NKw] := PLng(O + 2)^;
      O := O + 6;
      Inc(NKw);
    End;
    Pg := BtNext(A, Pg);
  End;
End;

Procedure LoadCnt; Forward;

{ Ouvre un fichier d'aide ; False (avec un message) si impossible }
Function OpenHelp(S : String) : Boolean;
Var A, N, I : LongInt;
Begin
  OpenHelp := False;
  S := FindHelp(S);
  If UpStr(S) = UpStr(HlpPath) Then
  Begin
    OpenHelp := FBuf <> 0;
    If FBuf <> 0 Then Exit;
  End;
  FreeHelp;
  FBuf := LoadFile(S, FLen);
  If (FBuf = 0) Or (FLen < 16) Or (PLng(FBuf)^ <> $35F3F) Then
  Begin
    If FBuf <> 0 Then GlobalFree(FBuf);
    FBuf := 0;
    Msg(L('Impossible d''ouvrir le fichier d''aide ', 'Cannot open the ' +
          'help file ', 'Die Hilfedatei kann nicht ge'#148'ffnet werden: ',
          'Impossibile aprire il file della Guida ', 'No se puede abrir ' +
          'el archivo de ayuda ') + S + '.', MB_OK Or MB_ICONSTOP);
    HlpPath := '';
    Exit;
  End;
  HlpPath := S;
  HlpDir := DirOf(S);
  HlpName := BaseOf(S);
  DirBase := FBuf + PLng(FBuf + 4)^ + 9;
  LoadSystem;
  If Minor <= 16 Then
  Begin
    Msg(L('Ce fichier d''aide est au format de Windows 3.0, qui ' +
          'n''est pas pris en charge.', 'This help file uses the ' +
          'Windows 3.0 format, which is not supported.', 'Format von ' +
          'Windows 3.0 wird nicht unterst'#129'tzt.', 'Formato di ' +
          'Windows 3.0 non supportato.', 'El formato de Windows 3.0 no ' +
          'es compatible.'), MB_OK Or MB_ICONSTOP);
    FreeHelp;
    HlpPath := '';
    Exit;
  End;
  If SysFlags = 8 Then
  Begin
    BlkSz := 2048; Comp := True;
  End
  Else
  Begin
    BlkSz := 4096; Comp := SysFlags = 4;
  End;
  If Not IntFile('|TOPIC', TopBase, TopLen) Then TopLen := 0;
  NBlk := (TopLen + BlkSz - 1) Div BlkSz;
  LoadPhrases;
  LoadFonts;
  LoadTitles;
  LoadKeywords;
  If Not IntFile('|CONTEXT', CtxBase, N) Then CtxBase := 0;
  CtxoN := 0;
  If IntFile('|CTXOMAP', A, N) Then
  Begin
    CtxoN := PWrd(A)^;
    CtxoBase := A + 2;
    If CtxoN * 8 + 2 > N Then CtxoN := (N - 2) Div 8;
  End;
  LoadCnt;
  OpenHelp := True;
End;

{ ------------------------------------------------- images (|bmN) }

{ entiers compresses non signes des images }
Function CD(Var P : LongInt) : LongInt;
Begin
  If (PByt(P)^ And 1) <> 0 Then
  Begin
    CD := PLng(P)^ Shr 1;
    P := P + 4;
  End
  Else
  Begin
    CD := PWrd(P)^ Shr 1;
    P := P + 2;
  End;
End;

{ RLE des images de WinHelp ; nombre d'octets produits }
Function UnRle(Src, SLen, Dst, M : LongInt) : LongInt;
Var I, O, C, K : LongInt;
Begin
  I := 0; O := 0;
  While (I < SLen) And (O < M) Do
  Begin
    C := PByt(Src + I)^;
    Inc(I);
    If (C And $80) <> 0 Then
    Begin
      For K := 1 To C And $7F Do
        If (O < M) And (I < SLen) Then
        Begin
          PByt(Dst + O)^ := PByt(Src + I)^;
          Inc(O);
          Inc(I);
        End;
    End
    Else
    Begin
      For K := 1 To C Do
        If O < M Then
        Begin
          PByt(Dst + O)^ := PByt(Src + I)^;
          Inc(O);
        End;
      Inc(I);
    End;
  End;
  UnRle := O;
End;

{ couleur des 16 couleurs de base (pour les images sans palette) }
Function Vga16(I : LongInt) : LongInt;
Begin
  Case I And 15 Of
    0 : Vga16 := $000000; 1 : Vga16 := $800000; 2 : Vga16 := $008000;
    3 : Vga16 := $808000; 4 : Vga16 := $000080; 5 : Vga16 := $800080;
    6 : Vga16 := $008080; 7 : Vga16 := $C0C0C0; 8 : Vga16 := $808080;
    9 : Vga16 := $FF0000; 10 : Vga16 := $00FF00; 11 : Vga16 := $FFFF00;
    12 : Vga16 := $0000FF; 13 : Vga16 := $FF00FF; 14 : Vga16 := $00FFFF;
  Else
    Vga16 := $FFFFFF;
  End;
End;

{ Image numero Num : index dans le cache (-1 si illisible) }
Function DecodeImg(Num : LongInt) : LongInt;
Var A, N, NP, I, PO, T, Pack, P, Planes, Bc, W, H, Cu, CSize, HSize,
    COff, HOff, Pal, NPal, Src, Buf, Buf2, Stride, Need, X, Y, V, Row,
    Out, Px, HA, NH, E, Id, S1 : LongInt;
Begin
  DecodeImg := -1;
  For I := 0 To NImg - 1 Do
    If ImgNum[I] = Num Then
    Begin
      DecodeImg := I;
      Exit;
    End;
  If NImg >= MaxImg Then Exit;
  If Not IntFile('|bm' + IntStr(Num), A, N) Then Exit;
  If (PWrd(A)^ <> $506C) And (PWrd(A)^ <> $706C) Then Exit;
  NP := PWrd(A + 2)^;
  PO := 0;
  For I := 0 To NP - 1 Do
  Begin
    T := PByt(A + PLng(A + 4 + I * 4)^)^;
    If (T = 5) Or (T = 6) Then
    Begin
      PO := A + PLng(A + 4 + I * 4)^;
      Break;
    End;
  End;
  If PO = 0 Then Exit;
  T := PByt(PO)^; Pack := PByt(PO + 1)^;
  P := PO + 2;
  CD(P); CD(P);
  Planes := ScanW(P); Bc := ScanW(P);
  W := CD(P); H := CD(P);
  Cu := CD(P); CD(P);
  CSize := CD(P); HSize := CD(P);
  COff := PLng(P)^; HOff := PLng(P + 4)^;
  P := P + 8;
  If Planes > 1 Then Bc := Bc * Planes;
  If (W <= 0) Or (H <= 0) Or (W > 2000) Or (H > 2000) Then Exit;
  If (Bc <> 1) And (Bc <> 4) And (Bc <> 8) And (Bc <> 24) Then Exit;
  Pal := 0; NPal := 0;
  If (T = 6) And (Bc <= 8) Then
  Begin
    NPal := Cu;
    If NPal = 0 Then NPal := 1 Shl Bc;
    Pal := P;
  End;
  If T = 6 Then Stride := ((W * Bc + 31) Div 32) * 4
  Else Stride := ((W * Bc + 15) Div 16) * 2;
  Need := Stride * H;
  Src := PO + COff;
  Buf := GlobalAlloc(0, Need + 64);
  Buf2 := 0;
  If Buf = 0 Then Exit;
  FillChar(Pointer(Buf)^, Need + 64, 0);
  Case Pack Of
    0 : Move(Pointer(Src)^, Pointer(Buf)^, Min(Need, CSize));
    1 : UnRle(Src, CSize, Buf, Need);
    2 : LzDecomp(Src, CSize, Buf, Need);
    3 :
    Begin
      Buf2 := GlobalAlloc(0, CSize * 10 + Need + 64);
      If Buf2 <> 0 Then
        UnRle(Buf2, LzDecomp(Src, CSize, Buf2, CSize * 10 + Need), Buf,
              Need);
    End;
  End;
  If Buf2 <> 0 Then GlobalFree(Buf2);
  { image 32 bits de bas en haut }
  Out := GlobalAlloc(0, W * H * 4 + 16);
  If Out = 0 Then
  Begin
    GlobalFree(Buf);
    Exit;
  End;
  For Y := 0 To H - 1 Do
  Begin
    If T = 6 Then Row := Buf + Y * Stride
    Else Row := Buf + (H - 1 - Y) * Stride;
    For X := 0 To W - 1 Do
    Begin
      Case Bc Of
        1 : V := (PByt(Row + X Shr 3)^ Shr (7 - (X And 7))) And 1;
        4 : V := (PByt(Row + X Shr 1)^ Shr (4 * (1 - (X And 1)))) And 15;
        8 : V := PByt(Row + X)^;
      Else
        V := 0;
      End;
      If Bc = 24 Then
        Px := PByt(Row + X * 3)^ Or (PByt(Row + X * 3 + 1)^ Shl 8) Or
              (PByt(Row + X * 3 + 2)^ Shl 16)
      Else If (Pal <> 0) And (V < NPal) Then
        Px := PLng(Pal + V * 4)^ And $FFFFFF
      Else If Bc = 1 Then
      Begin
        If V <> 0 Then Px := $FFFFFF Else Px := 0;
      End
      Else
      Begin
        { sans palette : 16 couleurs de base (RGB -> BGR) }
        Px := Vga16(V);
        Px := ((Px And $FF) Shl 16) Or (Px And $FF00) Or
              ((Px Shr 16) And $FF);
      End;
      PLng(Out + (Y * W + X) * 4)^ := Px;
    End;
  End;
  GlobalFree(Buf);
  I := NImg;
  ImgNum[I] := Num; ImgW[I] := W; ImgH[I] := H; ImgBits[I] := Out;
  ImgHot0[I] := NHot; ImgHotN[I] := 0;
  { zones sensibles (images SHG) }
  If (HSize > 0) And (HOff > 0) Then
  Begin
    HA := PO + HOff;
    NH := PWrd(HA + 1)^;
    S1 := HA + 7 + NH * 15 + PLng(HA + 3)^;
    For E := 0 To NH - 1 Do
    Begin
      If NHot >= MaxHot Then Break;
      P := HA + 7 + E * 15;
      Id := PByt(P)^;
      HotX[NHot] := PWrd(P + 3)^; HotY[NHot] := PWrd(P + 5)^;
      HotW[NHot] := PWrd(P + 7)^; HotH[NHot] := PWrd(P + 9)^;
      HotVal[NHot] := PLng(P + 11)^;
      { second texte de la paire nom / contexte (ou macro) }
      S1 := S1 + ZLen(S1) + 1;
      Case Id Of
        $E2, $E6 : HotKind[NHot] := 2;
        $E3, $E7 : HotKind[NHot] := 1;
        $C8, $CC :
        Begin
          HotKind[NHot] := 3;
          HotVal[NHot] := S1;
        End;
        $EA, $EE, $EB, $EF :
        Begin
          HotKind[NHot] := 8;
          HotVal[NHot] := S1;
        End;
      Else
        HotKind[NHot] := 0;
      End;
      S1 := S1 + ZLen(S1) + 1;
      Inc(NHot);
      Inc(ImgHotN[I]);
    End;
  End;
  Inc(NImg);
  DecodeImg := I;
End;

{ ---------------------------------------------------- mise en page }

Var
  LayRgn, LayLeft, LayRight, CurX, CurY, LineStart, LineH, LineX0 : LongInt;
  CurFont, CurLink, CurLinkVal, CurLinkAux : LongInt;
  CurLinkVis : Boolean;
  PLeft, PFirst, PRight, PAbove, PBelow, PAlign, PNTabs : LongInt;
  PTabs : Array[0..31] Of LongInt;

Function Px(V : LongInt) : LongInt;
Begin
  Px := (V * 2) Div 3;
End;

{ Termine la ligne : alignement, hauteur, position verticale }
Procedure FlushLine(Force : Boolean);
Var I, R, D, H : LongInt;
Begin
  If NItem > LineStart Then
  Begin
    R := 0;
    For I := LineStart To NItem - 1 Do R := Max(R, ItX[I] + ItW[I]);
    D := 0;
    If PAlign = 1 Then D := (LayRight - R) Div 2
    Else If PAlign = 2 Then D := LayRight - R;
    If D < 0 Then D := 0;
    For I := LineStart To NItem - 1 Do
    Begin
      ItX[I] := ItX[I] + D;
      ItY[I] := CurY + LineH - ItH[I];
    End;
    CurY := CurY + LineH;
  End
  Else If Force Then
  Begin
    H := ClsH(FntCls(CurFont));
    If LineH > H Then H := LineH;
    CurY := CurY + H;
  End;
  LineStart := NItem;
  LineH := 0;
  LineX0 := LayLeft + Px(PLeft);
  CurX := LineX0;
End;

Function NewItem(K, W, H : LongInt) : LongInt;
Begin
  NewItem := -1;
  If NItem >= MaxItem Then Exit;
  ItKind[NItem] := K; ItX[NItem] := CurX; ItY[NItem] := CurY;
  ItW[NItem] := W; ItH[NItem] := H; ItFnt[NItem] := CurFont;
  ItTxt[NItem] := 0; ItLen[NItem] := 0; ItRgn[NItem] := LayRgn;
  ItLink[NItem] := CurLink; ItVal[NItem] := CurLinkVal;
  ItAux[NItem] := CurLinkAux;
  If CurLink <> 0 Then
  Begin
    If Not CurLinkVis Then ItAux[NItem] := ItAux[NItem] Or $40000000;
  End;
  NewItem := NItem;
  Inc(NItem);
  If H > LineH Then LineH := H;
End;

{ Copie un texte (N octets ; ASCIIZ si N < 0) dans la reserve des
  textes : les liens le gardent apres la lecture d'autres
  enregistrements ; adresse de la copie (0 si plein) }
Function PoolStr(A, N : LongInt) : LongInt;
Begin
  PoolStr := 0;
  If N < 0 Then N := ZLen(A);
  If PoolN + N + 2 > PoolMax Then Exit;
  Move(Pointer(A)^, Pointer(Pool + PoolN)^, N);
  PByt(Pool + PoolN + N)^ := 0;
  PoolStr := Pool + PoolN;
  PoolN := PoolN + N + 1;
End;

{ Ajoute N caracteres (page 437) d'un mot a la ligne courante }
Procedure AddRun(A, N : LongInt);
Var I, K, Cw, Ch : LongInt;
Begin
  If (N <= 0) Or (PoolN + N + 1 > PoolMax) Then Exit;
  K := FntCls(CurFont);
  Cw := ClsW(K); Ch := ClsH(K);
  I := NItem - 1;
  If (I >= LineStart) And (I >= 0) And (ItKind[I] = 0) And
     (ItFnt[I] = CurFont) And (ItLink[I] = CurLink) And
     (ItVal[I] = CurLinkVal) And (ItX[I] + ItW[I] = CurX) And
     (ItTxt[I] + ItLen[I] = PoolN) And (ItLen[I] + N < 250) Then
  Begin
    Move(Pointer(A)^, Pointer(Pool + PoolN)^, N);
    PoolN := PoolN + N;
    ItLen[I] := ItLen[I] + N;
    ItW[I] := ItW[I] + N * Cw;
  End
  Else
  Begin
    I := NewItem(0, N * Cw, Ch);
    If I < 0 Then Exit;
    ItTxt[I] := PoolN; ItLen[I] := N;
    Move(Pointer(A)^, Pointer(Pool + PoolN)^, N);
    PoolN := PoolN + N;
  End;
  CurX := CurX + N * Cw;
End;

{ Texte ANSI (A, N octets) : coupe en mots, retour a la ligne }
Procedure AddText(A, N : LongInt);
Var I, J, K, Cw, WW : LongInt; Buf : Array[0..255] Of Byte;
Begin
  Cw := ClsW(FntCls(CurFont));
  I := 0;
  While I < N Do
  Begin
    { mot (sans espace) puis ses espaces }
    J := I;
    While (J < N) And (PByt(A + J)^ <> 32) And (J - I < 200) Do Inc(J);
    WW := (J - I) * Cw;
    While (J < N) And (PByt(A + J)^ = 32) And (J - I < 240) Do Inc(J);
    If (CurX + WW > LayRight) And (CurX > LineX0) Then
    Begin
      FlushLine(False);
      { pas d'espaces au debut d'une ligne coupee }
      While (I < J) And (PByt(A + I)^ = 32) Do Inc(I);
    End;
    For K := I To J - 1 Do Buf[K - I] := Oem(PByt(A + K)^);
    AddRun(LongInt(@Buf), J - I);
    I := J;
  End;
End;

Procedure AddImage(Num : LongInt);
Var K, I : LongInt;
Begin
  K := DecodeImg(Num);
  If K < 0 Then Exit;
  If (CurX + ImgW[K] > LayRight) And (CurX > LineX0) Then
    FlushLine(False);
  I := NewItem(1, ImgW[K], ImgH[K]);
  If I < 0 Then Exit;
  ItTxt[I] := K;
  If (CurLink = 0) And (ImgHotN[K] > 0) Then ItLink[I] := 6;
  CurX := CurX + ImgW[K];
End;

{ Tabulation : taquet suivant (sinon tous les 48 points) }
Procedure DoTab;
Var I, T, X : LongInt;
Begin
  X := CurX - LayLeft;
  If X < Px(PLeft) - 1 Then
  Begin
    CurX := LayLeft + Px(PLeft);
    Exit;
  End;
  For I := 0 To PNTabs - 1 Do
  Begin
    T := Px(PTabs[I]);
    If T > X + 1 Then
    Begin
      CurX := LayLeft + T;
      Exit;
    End;
  End;
  CurX := LayLeft + ((X + 8) Div 48 + 1) * 48;
  If CurX > LayRight Then FlushLine(False);
End;

{ Debut d'un paragraphe : lit ses attributs dans LinkData1 }
Procedure ParaInfo(Var P : LongInt);
Var Bits, N, K, T : LongInt;
Begin
  P := P + 4;
  Bits := PWrd(P)^;
  P := P + 2;
  If (Bits And 1) <> 0 Then ScanL(P);
  PAbove := 0; PBelow := 0; PLeft := 0; PRight := 0; PFirst := 0;
  If (Bits And 2) <> 0 Then PAbove := ScanI(P);
  If (Bits And 4) <> 0 Then PBelow := ScanI(P);
  If (Bits And 8) <> 0 Then ScanI(P);
  If (Bits And $10) <> 0 Then PLeft := ScanI(P);
  If (Bits And $20) <> 0 Then PRight := ScanI(P);
  If (Bits And $40) <> 0 Then PFirst := ScanI(P);
  If (Bits And $100) <> 0 Then P := P + 3;
  PNTabs := 0;
  If (Bits And $200) <> 0 Then
  Begin
    N := ScanI(P);
    For K := 1 To N Do
    Begin
      T := ScanW(P);
      If (T And $4000) <> 0 Then ScanW(P);
      If PNTabs < 32 Then
      Begin
        PTabs[PNTabs] := T And $3FFF;
        Inc(PNTabs);
      End;
    End;
  End;
  PAlign := 0;
  If (Bits And $400) <> 0 Then PAlign := 2;
  If (Bits And $800) <> 0 Then PAlign := 1;
End;

Procedure StartPara;
Begin
  CurY := CurY + Px(PAbove);
  LineStart := NItem;
  LineH := 0;
  LineX0 := LayLeft + Px(PLeft) + Px(PFirst);
  If LineX0 < LayLeft Then LineX0 := LayLeft;
  CurX := LineX0;
End;

{ Commandes de mise en forme et textes d'un paragraphe ; False en fin
  d'enregistrement anormale }
Function DoCommands(Var P, T2 : LongInt; PEnd, T2End : LongInt) : Boolean;
Var C, N, D, Ty, Sz, Pn : LongInt; Sp : Byte;
Begin
  DoCommands := False;
  Repeat
    { texte qui precede la commande }
    If T2 < T2End Then
    Begin
      N := ZLen(T2);
      If T2 + N > T2End Then N := T2End - T2;
      AddText(T2, N);
      T2 := T2 + N + 1;
    End;
    If P >= PEnd Then Exit;
    C := PByt(P)^;
    Inc(P);
    Case C Of
      $FF : Begin
              DoCommands := True;
              Exit;
            End;
      $20 : P := P + 4;
      $21 : P := P + 2;
      $80 :
      Begin
        CurFont := PWrd(P)^;
        P := P + 2;
      End;
      $81 : FlushLine(True);
      $82 :
      Begin
        FlushLine(True);
        CurY := CurY + Px(PBelow);
        StartPara;
      End;
      $83 : DoTab;
      $86, $87, $88 :
      Begin
        Ty := PByt(P)^;
        Inc(P);
        Sz := ScanL(P);
        If Ty = $22 Then ScanW(P);
        If ((Ty = $22) Or (Ty = 3)) And (PWrd(P)^ = 0) Then
        Begin
          Pn := PWrd(P + 2)^;
          AddImage(Pn);
        End;
        P := P + Sz;
      End;
      $89 :
      Begin
        CurLink := 0; CurLinkVal := 0; CurLinkAux := 0;
      End;
      $8B :
      Begin
        Sp := 32;
        AddRun(LongInt(@Sp), 1);
      End;
      $8C :
      Begin
        Sp := 45;
        AddRun(LongInt(@Sp), 1);
      End;
      $C8, $CC :
      Begin
        N := PWrd(P)^;
        CurLink := 3;
        CurLinkVal := PoolStr(P + 2, -1);
        CurLinkAux := 0;
        CurLinkVis := C = $C8;
        P := P + 2 + N;
      End;
      $E0, $E1 :
      Begin
        CurLink := 7;
        CurLinkVal := PLng(P)^;
        CurLinkAux := 0;
        CurLinkVis := True;
        P := P + 4;
      End;
      $E2, $E3, $E6, $E7 :
      Begin
        If (C = $E2) Or (C = $E6) Then CurLink := 2 Else CurLink := 1;
        CurLinkVal := PLng(P)^;
        CurLinkAux := 0;
        CurLinkVis := C < $E6;
        P := P + 4;
      End;
      $EA, $EB, $EE, $EF :
      Begin
        N := PWrd(P)^;
        D := P + 2;
        If (C = $EA) Or (C = $EE) Then CurLink := 5 Else CurLink := 4;
        CurLinkVal := PLng(D + 1)^;
        CurLinkAux := 0;
        Ty := PByt(D)^;
        If Ty = 4 Then CurLinkAux := PoolStr(D + 5, -1)
        Else If Ty = 6 Then CurLinkAux := PoolStr(D + 5 + ZLen(D + 5) + 1, -1);
        CurLinkVis := C < $EE;
        P := P + 2 + N;
      End;
    Else
      Exit;
    End;
  Until False;
End;

{ Met en page l'enregistrement d'affichage lu (L1, L2Buf) }
Procedure LayoutRecord;
Var P, PEnd, T2, T2End, NCol, TType, I, Tot, Avail, Col, RowTop, RowBot,
    L0, R0, X : LongInt;
    CA, CB, CX : Array[0..31] Of LongInt;
Begin
  P := L1;
  PEnd := L1 + L1Len;
  T2 := L2Buf;
  T2End := L2Buf + L2Len;
  ScanL(P);
  ScanW(P);
  If RType = $23 Then
  Begin
    NCol := PByt(P)^; TType := PByt(P + 1)^;
    P := P + 2;
    If (TType = 0) Or (TType = 2) Then P := P + 2;
    If NCol > 32 Then NCol := 32;
    Tot := 0;
    For I := 0 To NCol - 1 Do
    Begin
      CA[I] := Max(0, SW(P)); CB[I] := Max(0, SW(P + 2));
      Tot := Tot + Px(CA[I] + CB[I]);
      P := P + 4;
    End;
    L0 := LayLeft; R0 := LayRight;
    Avail := R0 - L0;
    X := L0;
    For I := 0 To NCol - 1 Do
    Begin
      CX[I] := X;
      If (Tot > Avail) Or (TType = 0) Or (TType = 2) Then
        X := X + (Px(CA[I] + CB[I]) * Avail) Div Max(Tot, 1)
      Else X := X + Px(CA[I] + CB[I]);
    End;
    RowTop := CurY; RowBot := CurY;
    Repeat
      If P + 2 > PEnd Then Break;
      Col := SW(P);
      P := P + 2;
      If Col = -1 Then Break;
      P := P + 3;
      If (Col < 0) Or (Col >= NCol) Then Break;
      LayLeft := CX[Col];
      If Col + 1 < NCol Then LayRight := CX[Col + 1] - 6
      Else LayRight := R0;
      CurY := RowTop;
      ParaInfo(P);
      StartPara;
      If Not DoCommands(P, T2, PEnd, T2End) Then
      Begin
        FlushLine(False);
        RowBot := Max(RowBot, CurY);
        Break;
      End;
      FlushLine(False);
      CurY := CurY + Px(PBelow);
      RowBot := Max(RowBot, CurY);
    Until False;
    LayLeft := L0; LayRight := R0;
    CurY := RowBot;
  End
  Else
  Begin
    ParaInfo(P);
    StartPara;
    DoCommands(P, T2, PEnd, T2End);
    FlushLine(False);
  End;
  CurLink := 0;
End;

{ Met en page la rubrique qui contient TOPICOFFSET Off dans la zone
  Rgn (0/1 : fenetre principale, 2 : fenetre contextuelle), sur la
  largeur W. Rend la hauteur ; False si la rubrique est introuvable. }
Function LayoutTopic(Off, Rgn, W : LongInt; Var H : LongInt) : Boolean;
Var Ti, TP, NonScroll, Scroll, N, BN, CC, Cur, RecOff : LongInt;
    InNs : Boolean;
Begin
  LayoutTopic := False;
  H := 0;
  Ti := TopicIdx(Off);
  If Ti < 0 Then Exit;
  TP := HeaderPos(TopOff^[Ti]);
  If TP < 0 Then TP := HeaderPos(Off);
  If (TP < 0) Or Not ReadRec(TP) Or (RType <> 2) Then Exit;
  If Rgn <> 2 Then
  Begin
    CurOff := TopOff^[Ti];
    CurTp := TP;
    CurTitle := OemStr(CStr(L2Buf));
    If CurTitle = '' Then CurTitle := TopicTitle(Ti);
    CurBck := PLng(L1 + 4)^;
    CurFor := PLng(L1 + 8)^;
  End;
  NonScroll := PLng(L1 + 16)^;
  Scroll := PLng(L1 + 20)^;
  InNs := (Rgn <> 2) And (NonScroll <> -1) And (Scroll <> -1);
  If InNs Then LayRgn := 1 Else LayRgn := Rgn;
  LayLeft := Margin;
  LayRight := W - Margin;
  CurY := 6;
  CurFont := 0; CurLink := 0; CurLinkVal := 0; CurLinkAux := 0;
  PAlign := 0; PLeft := 0; PFirst := 0; PNTabs := 0;
  LineStart := NItem; LineH := 0;
  BN := TP Shr 14; CC := 0; Cur := BN;
  CC := TopOff^[Ti] And $7FFF;
  TP := RNext;
  N := 0;
  AnchorY := -1;
  While (TP > 0) And (N < 5000) Do
  Begin
    If Not ReadRec(TP) Then Break;
    If RType = 2 Then Break;
    If InNs And (TP = Scroll) Then
    Begin
      InNs := False;
      NsH := CurY + 6;
      LayRgn := 0;
      CurY := 6;
    End;
    BN := TP Shr 14;
    If BN <> Cur Then
    Begin
      Cur := BN;
      CC := 0;
    End;
    RecOff := (BN Shl 15) + CC;
    If (Rgn <> 2) And (AnchorY < 0) And (RecOff >= Off) And
       (Off > TopOff^[Ti]) And (LayRgn = 0) Then AnchorY := CurY;
    If (RType = $20) Or (RType = $23) Then
    Begin
      CC := CC + RecChars;
      LayoutRecord;
    End;
    TP := RNext;
    Inc(N);
  End;
  If InNs Then
  Begin
    NsH := CurY + 6;
    CurY := 6;
  End;
  H := CurY + 8;
  LayoutTopic := True;
End;

{ ---------------------------------------------------------- dessin }

Function ItColor(I : LongInt) : LongInt;
Var F : LongInt;
Begin
  F := ItFnt[I];
  If (ItLink[I] <> 0) And (ItLink[I] <> 6) And
     ((ItAux[I] And $40000000) = 0) Then ItColor := cGreen
  Else If (F >= 0) And (F < FntN) Then ItColor := FntColor[F]
  Else ItColor := cBlack;
End;

{ Dessine les elements de la zone Rgn decales de (DX, DY), entre les
  ordonnees Y1 et Y2 de la fenetre }
Procedure DrawItems(Hdc, Rgn, DX, DY, Y1, Y2 : LongInt);
Var I, X, Y, K, C, A, F, Pn, J, Bot : LongInt;
Begin
  SetBkMode(Hdc, 1);
  For I := 0 To NItem - 1 Do
  Begin
    If ItRgn[I] <> Rgn Then Continue;
    X := ItX[I] + DX;
    Y := ItY[I] + DY;
    If (Y + ItH[I] < Y1) Or (Y > Y2) Then Continue;
    If ItKind[I] = 1 Then
    Begin
      K := ItTxt[I];
      If (K < 0) Or (K >= NImg) Then Continue;
      If (Y < Y1) Or (Y + ImgH[K] > Y2 + 1) Then Continue;
      Bmi[0] := 40; Bmi[1] := ImgW[K]; Bmi[2] := ImgH[K];
      Bmi[3] := 1 Or (32 Shl 16); Bmi[4] := 0;
      Bmi[5] := ImgW[K] * ImgH[K] * 4;
      Bmi[6] := 0; Bmi[7] := 0; Bmi[8] := 0; Bmi[9] := 0;
      SetDIBitsToDevice(Hdc, X, Y, ImgW[K], ImgH[K], 0, 0, 0, ImgH[K],
                        Pointer(ImgBits[K]), @Bmi, 0);
      Continue;
    End;
    If (Y < Y1) Or (Y + ItH[I] > Y2 + 1) Then Continue;
    F := ItFnt[I];
    If (F >= 0) And (F < FntN) Then A := FntAttr[F] Else A := 0;
    SelectObject(Hdc, HFnt[FntCls(F)]);
    C := ItColor(I);
    SetTextColor(Hdc, C);
    TextOutA(Hdc, X, Y, PChar(Pool + ItTxt[I]), ItLen[I]);
    { gras : le texte une seconde fois, decale d'un point }
    If (A And 1) <> 0 Then
      TextOutA(Hdc, X + 1, Y, PChar(Pool + ItTxt[I]), ItLen[I]);
    { souligne (attribut, saut) ou pointille (fenetre contextuelle) }
    Bot := Y + ItH[I] - 1;
    If C = cGreen Then SelectObject(Hdc, PenGreen)
    Else SelectObject(Hdc, PenBlack);
    If (C = cGreen) And ((ItLink[I] = 2) Or (ItLink[I] = 5)) Then
    Begin
      J := X;
      While J < X + ItW[I] - 1 Do
      Begin
        MoveToEx(Hdc, J, Bot, Nil);
        GdiLineTo(Hdc, J + 1, Bot);
        J := J + 2;
      End;
    End
    Else If (C = cGreen) Or ((A And 4) <> 0) Or ((A And 16) <> 0) Then
    Begin
      MoveToEx(Hdc, X, Bot, Nil);
      GdiLineTo(Hdc, X + ItW[I], Bot);
    End;
  End;
End;

{ ---------------------------------------- fenetre principale : vue }

Procedure Layout; Forward;
Procedure ShowPopup(Off : LongInt); Forward;
Procedure OpenTopics(Tab : LongInt); Forward;
Procedure ShowFound(Title : String); Forward;

Function ViewTop : LongInt;
Begin
  ViewTop := BtnH + NsH;
End;

Procedure UpdScroll;
Var M : LongInt;
Begin
  M := DocH - ViewH;
  If M < 0 Then M := 0;
  If ScrollY > M Then ScrollY := M;
  If ScrollY < 0 Then ScrollY := 0;
  SetScrollRange(ScrollBar, SB_CTL, 0, Max(M, 1), 0);
  SetScrollPos(ScrollBar, SB_CTL, ScrollY, 1);
  EnableWindow(ScrollBar, Ord(M > 0));
End;

Procedure ScrollTo(Y : LongInt);
Begin
  ScrollY := Y;
  UpdScroll;
  InvalidateRect(Wnd, Nil, 0);
End;

{ Affiche la rubrique qui contient TOPICOFFSET Off }
Function ShowTopic(Off : LongInt) : Boolean;
Var H, I : LongInt; R : TRect;
Begin
  ShowTopic := False;
  If FBuf = 0 Then Exit;
  If NImg > MaxImg Div 2 Then
  Begin
    For I := 0 To NImg - 1 Do
      If ImgBits[I] <> 0 Then GlobalFree(ImgBits[I]);
    NImg := 0; NHot := 0;
  End;
  GetClientRect(Wnd, R);
  ViewW := R.R - ScrW;
  NItem := 0; PoolN := 0; NsH := 0;
  If Not LayoutTopic(Off, 0, ViewW, H) Then
  Begin
    Msg(L('Cette rubrique n''existe pas.', 'This topic does not exist.',
          'Dieses Thema existiert nicht.', 'Argomento inesistente.',
          'Este tema no existe.'), MB_OK Or MB_ICONINFO);
    Exit;
  End;
  DocH := H;
  ViewH := R.B - ViewTop;
  If AnchorY >= 0 Then ScrollY := AnchorY Else ScrollY := 0;
  If HlpTitle <> '' Then SetWindowTextA(Wnd, Z(HlpTitle))
  Else If CntTitle <> '' Then SetWindowTextA(Wnd, Z(CntTitle))
  Else SetWindowTextA(Wnd, Z(AppTitle));
  EnableWindow(BtnBack, Ord(NHist > 0));
  EnableWindow(BtnPrev, Ord((CurBck <> -1) And (CurBck <> 0)));
  EnableWindow(BtnNext, Ord((CurFor <> -1) And (CurFor <> 0)));
  Layout;
  UpdScroll;
  InvalidateRect(Wnd, Nil, 1);
  ShowTopic := True;
End;

{ Remise en page (largeur changee) en gardant la position }
Procedure Relayout;
Var Y : LongInt;
Begin
  If (FBuf = 0) Or (NItem = 0) Then Exit;
  Y := ScrollY;
  If ShowTopic(CurOff) Then ScrollTo(Y);
End;

Procedure PushHist;
Var I : LongInt;
Begin
  If FBuf = 0 Then Exit;
  If NHist >= MaxHist Then
  Begin
    For I := 1 To MaxHist - 1 Do
    Begin
      HistOff[I - 1] := HistOff[I]; HistY[I - 1] := HistY[I];
      HistFile[I - 1] := HistFile[I];
    End;
    NHist := MaxHist - 1;
  End;
  HistOff[NHist] := CurOff;
  HistY[NHist] := ScrollY;
  HistFile[NHist] := Copy(HlpPath, 1, 79);
  Inc(NHist);
End;

Procedure GoBack;
Var Y : LongInt;
Begin
  If NHist = 0 Then Exit;
  Dec(NHist);
  If UpStr(HistFile[NHist]) <> UpStr(HlpPath) Then
    If Not OpenHelp(HistFile[NHist]) Then Exit;
  Y := HistY[NHist];
  If ShowTopic(HistOff[NHist]) Then ScrollTo(Y);
End;

{ Saut vers TOPICOFFSET Off (avec historique) }
Procedure JumpOff(Off : LongInt);
Begin
  If Off < 0 Then
  Begin
    Msg(L('Rubrique introuvable dans ce fichier d''aide.',
          'Topic not found in this help file.',
          'Thema nicht gefunden.', 'Argomento non trovato.',
          'No se encuentra el tema.'), MB_OK Or MB_ICONINFO);
    Exit;
  End;
  If NItem > 0 Then PushHist;
  ShowTopic(Off);
End;

{ Fichier d'un lien ("fichier.hlp>fenetre") ; True si on peut y aller }
Function GoFile(F : String) : Boolean;
Var I : LongInt;
Begin
  GoFile := True;
  I := Pos('>', F);
  If I > 0 Then F := Copy(F, 1, I - 1);
  While (F <> '') And (F[1] = ' ') Do Delete(F, 1, 1);
  If F = '' Then Exit;
  If UpStr(BaseOf(F)) = UpStr(HlpName) Then Exit;
  If NItem > 0 Then PushHist;
  NItem := 0;
  GoFile := OpenHelp(F);
End;

{ -------------------------------------------------------- mots-cles }

{ Ajoute les rubriques du mot-cle K (tableau Data) a la liste trouvee }
Procedure AddFound(Off : LongInt);
Var I : LongInt;
Begin
  For I := 0 To NFound - 1 Do
    If FoundOff^[I] = Off Then Exit;
  If NFound < MaxTop Then
  Begin
    FoundOff^[NFound] := Off;
    Inc(NFound);
  End;
End;

Procedure KwTopicsOf(K : LongInt);
Var I : LongInt;
Begin
  If (K < 0) Or (K >= NKw) Or (KwData = 0) Then Exit;
  For I := 0 To KwCnt^[K] - 1 Do
    AddFound(PLng(KwData + KwOfs^[K] + I * 4)^);
End;

{ Cherche un mot-cle (sans tenir compte de la casse) dans |KWBTREE ou
  |AWBTREE et ajoute ses rubriques }
Procedure FindKeyword(BtName, DataName, Kw : String);
Var A, N, D, DN, Pg, E, K, O, C, Ofs : LongInt; U : String;
Begin
  If Not IntFile(BtName, A, N) Then Exit;
  If Not IntFile(DataName, D, DN) Then Exit;
  U := FoldStr(OemStr(Kw));
  Pg := BtFirst(A);
  While Pg <> 0 Do
  Begin
    E := PWrd(Pg + 2)^;
    O := Pg + 8;
    For K := 1 To E Do
    Begin
      If FoldStr(OemStr(CStr(O))) = U Then
      Begin
        O := O + ZLen(O) + 1;
        C := PWrd(O)^; Ofs := PLng(O + 2)^;
        For N := 0 To C - 1 Do AddFound(PLng(D + Ofs + N * 4)^);
        Exit;
      End;
      O := O + ZLen(O) + 1 + 6;
    End;
    Pg := BtNext(A, Pg);
  End;
End;

{ Resultat d'une recherche : une rubrique -> saut ; plusieurs -> liste }
Procedure ShowFoundOrJump(Title : String);
Begin
  If NFound = 1 Then JumpOff(FoundOff^[0])
  Else If NFound > 1 Then ShowFound(Title)
  Else Msg(L('Aucune rubrique ne correspond.', 'No topics were found.',
             'Keine Themen gefunden.', 'Nessun argomento trovato.',
             'No se encontraron temas.'), MB_OK Or MB_ICONINFO);
End;

{ ------------------------------------------------------------ macros }

Var
  MacArg : Array[0..7] Of String;
  MacN : LongInt;

{ Une macro "Nom(arg, `arg', "arg")" : nom en majuscules, arguments }
Function ParseMacro(Var P : LongInt; E : LongInt) : String;
Var Nm, A : String; C, Q, D : LongInt;
Begin
  Nm := '';
  MacN := 0;
  While (P < E) And (PByt(P)^ = 32) Do Inc(P);
  While (P < E) And (Chr(PByt(P)^) In ['A'..'Z', 'a'..'z', '0'..'9', '_'])
  Do
  Begin
    Nm := Nm + UpCase(Chr(PByt(P)^));
    Inc(P);
  End;
  While (P < E) And (PByt(P)^ = 32) Do Inc(P);
  If (P < E) And (PByt(P)^ = Ord('(')) Then
  Begin
    Inc(P);
    A := ''; D := 0;
    While P < E Do
    Begin
      C := PByt(P)^;
      Inc(P);
      If (C = Ord('`')) Or (C = Ord('"')) Then
      Begin
        If C = Ord('`') Then Q := Ord('''') Else Q := Ord('"');
        While (P < E) And (PByt(P)^ <> Q) Do
        Begin
          If Length(A) < 250 Then A := A + Chr(PByt(P)^);
          Inc(P);
        End;
        Inc(P);
      End
      Else If C = Ord('(') Then
      Begin
        Inc(D);
        A := A + '(';
      End
      Else If (C = Ord(')')) And (D > 0) Then
      Begin
        Dec(D);
        A := A + ')';
      End
      Else If (C = Ord(',')) Or (C = Ord(')')) Then
      Begin
        While (A <> '') And (A[Length(A)] = ' ') Do Delete(A, Length(A), 1);
        If MacN < 8 Then MacArg[MacN] := A;
        Inc(MacN);
        A := '';
        If C = Ord(')') Then Break;
      End
      Else If (C <> 32) Or (A <> '') Then
        If Length(A) < 250 Then A := A + Chr(C);
    End;
  End;
  { separateur ':' ou ';' }
  While (P < E) And (Chr(PByt(P)^) In [' ', ':', ';']) Do Inc(P);
  ParseMacro := Nm;
End;

Function Arg(I : LongInt) : String;
Begin
  If I < Min(MacN, 8) Then Arg := MacArg[I] Else Arg := '';
End;

Function StrInt(S : String) : LongInt;
Var V, I, C : LongInt;
Begin
  Val(S, V, C);
  If C <> 0 Then
  Begin
    V := 0;
    For I := 1 To Length(S) Do
      If S[I] In ['0'..'9'] Then V := V * 10 + Ord(S[I]) - 48;
  End;
  StrInt := V;
End;

Procedure KLinks(Kws : String; ALinks : Boolean; Topic : String);
Var I : LongInt; W : String;
Begin
  NFound := 0;
  Kws := Kws + ';';
  W := '';
  For I := 1 To Length(Kws) Do
    If Kws[I] = ';' Then
    Begin
      While (W <> '') And (W[1] = ' ') Do Delete(W, 1, 1);
      If W <> '' Then
        If ALinks Then FindKeyword('|AWBTREE', '|AWDATA', W)
        Else FindKeyword('|KWBTREE', '|KWDATA', W);
      W := '';
    End
    Else W := W + Kws[I];
  If (NFound = 0) And (Topic <> '') Then
  Begin
    JumpOff(CtxLookup(HashCtx(Topic)));
    Exit;
  End;
  ShowFoundOrJump(L('Rubriques connexes', 'Topics Found', 'Gefundene ' +
                    'Themen', 'Argomenti trovati', 'Temas encontrados'));
End;

{ Execute les macros de l'adresse A (texte ASCIIZ) }
Procedure RunMacros(A : LongInt);
Var P, E, N : LongInt; Nm, S : String;
Begin
  P := A;
  E := A + ZLen(A);
  N := 0;
  While (P < E) And (N < 16) Do
  Begin
    Inc(N);
    Nm := ParseMacro(P, E);
    If (Nm = 'JUMPID') Or (Nm = 'JI') Then
    Begin
      If GoFile(Arg(0)) Then JumpOff(CtxLookup(HashCtx(Arg(1))));
    End
    Else If (Nm = 'POPUPID') Or (Nm = 'PI') Then
    Begin
      If GoFile(Arg(0)) Then ShowPopup(CtxLookup(HashCtx(Arg(1))));
    End
    Else If (Nm = 'JUMPCONTEXT') Or (Nm = 'JC') Then
    Begin
      If GoFile(Arg(0)) Then JumpOff(MapLookup(StrInt(Arg(1))));
    End
    Else If (Nm = 'POPUPCONTEXT') Or (Nm = 'PC') Then
    Begin
      If GoFile(Arg(0)) Then ShowPopup(MapLookup(StrInt(Arg(1))));
    End
    Else If (Nm = 'JUMPHASH') Or (Nm = 'JH') Then
    Begin
      If GoFile(Arg(0)) Then JumpOff(CtxLookup(StrInt(Arg(1))));
    End
    Else If (Nm = 'POPUPHASH') Or (Nm = 'PH') Then
    Begin
      If GoFile(Arg(0)) Then ShowPopup(CtxLookup(StrInt(Arg(1))));
    End
    Else If (Nm = 'JUMPKEYWORD') Or (Nm = 'JK') Then
    Begin
      If GoFile(Arg(0)) Then
      Begin
        NFound := 0;
        FindKeyword('|KWBTREE', '|KWDATA', Arg(1));
        ShowFoundOrJump(L('Rubriques trouv'#130'es', 'Topics Found',
                          'Gefundene Themen', 'Argomenti trovati',
                          'Temas encontrados'));
      End;
    End
    Else If (Nm = 'KLINK') Or (Nm = 'KL') Then KLinks(Arg(0), False, Arg(2))
    Else If (Nm = 'ALINK') Or (Nm = 'AL') Then KLinks(Arg(0), True, Arg(2))
    Else If (Nm = 'CONTENTS') Then
    Begin
      If ContentsOff >= 0 Then JumpOff(ContentsOff)
      Else If NTop > 0 Then JumpOff(TopOff^[0]);
    End
    Else If (Nm = 'FINDER') Or (Nm = 'FD') Or (Nm = 'SEARCH') Or
            (Nm = 'HELPTOPICS') Then OpenTopics(-1)
    Else If Nm = 'BACK' Then GoBack
    Else If (Nm = 'EXIT') Or (Nm = 'CLOSEWINDOW') Then
      PostMessageA(Wnd, WM_CLOSE, 0, 0)
    Else If (Nm = 'NEXT') And (CurFor <> -1) Then JumpOff(CurFor)
    Else If (Nm = 'PREV') And (CurBck <> -1) Then JumpOff(CurBck)
    Else If (Nm = 'EXECFILE') Or (Nm = 'EF') Or (Nm = 'EXECPROGRAM') Or
            (Nm = 'EP') Then
    Begin
      S := Arg(0);
      If (Nm = 'EXECFILE') Or (Nm = 'EF') Then S := S + ' ' + Arg(1);
      WinExec(Z(S), 1);
    End;
  End;
End;

{ ------------------------------------------------------------ liens }

Procedure FollowLink(K, V, Aux : LongInt);
Var F : String;
Begin
  Aux := Aux And $3FFFFFFF;
  Case K Of
    1 : JumpOff(CtxLookup(V));
    2 : ShowPopup(CtxLookup(V));
    3 : RunMacros(V);
    4, 5 :
    Begin
      F := '';
      If Aux <> 0 Then F := CStr(Aux);
      If GoFile(F) Then
        If K = 5 Then ShowPopup(CtxLookup(V)) Else JumpOff(CtxLookup(V));
    End;
    7 : JumpOff(V);
  End;
End;

{ Zone sensible d'une image (X, Y dans l'image) }
Procedure FollowHot(Img, X, Y : LongInt);
Var I, H : LongInt; S, F : String;
Begin
  For I := 0 To ImgHotN[Img] - 1 Do
  Begin
    H := ImgHot0[Img] + I;
    If (X >= HotX[H]) And (Y >= HotY[H]) And (X < HotX[H] + HotW[H]) And
       (Y < HotY[H] + HotH[H]) Then
    Begin
      Case HotKind[H] Of
        1 : JumpOff(CtxLookup(HotVal[H]));
        2 : ShowPopup(CtxLookup(HotVal[H]));
        3 : RunMacros(HotVal[H]);
        8 :
        Begin
          { "contexte>fenetre@fichier" }
          S := CStr(HotVal[H]);
          F := '';
          If Pos('@', S) > 0 Then
          Begin
            F := Copy(S, Pos('@', S) + 1, 255);
            S := Copy(S, 1, Pos('@', S) - 1);
          End;
          If Pos('>', S) > 0 Then S := Copy(S, 1, Pos('>', S) - 1);
          If GoFile(F) Then JumpOff(CtxLookup(HashCtx(S)));
        End;
      End;
      Exit;
    End;
  End;
End;

{ Element sous le point (X, Y) de la zone Rgn ; -1 si aucun lien }
Function HitItem(Rgn, X, Y : LongInt) : LongInt;
Var I : LongInt;
Begin
  HitItem := -1;
  For I := NItem - 1 DownTo 0 Do
    If (ItRgn[I] = Rgn) And (ItLink[I] <> 0) And (X >= ItX[I]) And
       (X < ItX[I] + ItW[I]) And (Y >= ItY[I]) And (Y < ItY[I] + ItH[I])
    Then
    Begin
      HitItem := I;
      Exit;
    End;
End;

Procedure ClickItem(I, X, Y : LongInt);
Begin
  If I < 0 Then Exit;
  If ItLink[I] = 6 Then FollowHot(ItTxt[I], X - ItX[I], Y - ItY[I])
  Else FollowLink(ItLink[I], ItVal[I], ItAux[I]);
End;

{ ------------------------------------------- fenetre contextuelle }

Procedure ClosePopup;
Var I, N : LongInt;
Begin
  If PopWnd = 0 Then Exit;
  DestroyWindow(PopWnd);
  PopWnd := 0;
  { retire les elements de la fenetre contextuelle }
  N := 0;
  For I := 0 To NItem - 1 Do
    If ItRgn[I] <> 2 Then
    Begin
      ItKind[N] := ItKind[I]; ItX[N] := ItX[I]; ItY[N] := ItY[I];
      ItW[N] := ItW[I]; ItH[N] := ItH[I]; ItFnt[N] := ItFnt[I];
      ItTxt[N] := ItTxt[I]; ItLen[N] := ItLen[I]; ItLink[N] := ItLink[I];
      ItVal[N] := ItVal[I]; ItRgn[N] := ItRgn[I]; ItAux[N] := ItAux[I];
      Inc(N);
    End;
  NItem := N;
  If PopOnly Then PostMessageA(Wnd, WM_CLOSE, 0, 0);
End;

Procedure ShowPopup(Off : LongInt);
Var H, W, SX, SY, I, X, Y, Ti, TP : LongInt; Pt : TPoint;
    S0, S1, S2, S3, S4, S5 : LongInt;
Begin
  ClosePopup;
  If Off < 0 Then
  Begin
    JumpOff(-1);
    Exit;
  End;
  { la mise en page de la fenetre contextuelle garde la rubrique
    principale (titre, sequence) }
  S0 := CurOff; S1 := CurTp; S2 := CurBck; S3 := CurFor; S4 := NsH;
  S5 := AnchorY;
  W := 340;
  PopFirst := NItem;
  If Not LayoutTopic(Off, 2, W, H) Then
  Begin
    NItem := PopFirst;
    Exit;
  End;
  CurOff := S0; CurTp := S1; CurBck := S2; CurFor := S3; NsH := S4;
  AnchorY := S5;
  { largeur utile }
  X := 0;
  For I := PopFirst To NItem - 1 Do X := Max(X, ItX[I] + ItW[I]);
  PopW := Min(W, X + Margin + 2);
  If PopW < 80 Then PopW := 80;
  PopH := H;
  GetCursorPos(Pt);
  SX := GetSystemMetrics(0); SY := GetSystemMetrics(1);
  X := Pt.X - PopW Div 2;
  Y := Pt.Y + 12;
  If X + PopW > SX - 4 Then X := SX - 4 - PopW;
  If X < 4 Then X := 4;
  If Y + PopH > SY - 32 Then Y := Pt.Y - 12 - PopH;
  If Y < 4 Then Y := 4;
  PopWnd := CreateWindowExA(0, Z('WinHlpPopup'), Z2(''), WS_POPUP Or
                            WS_BORDER Or WS_VISIBLE, X, Y, PopW, PopH,
                            Wnd, 0, Inst, 0);
  SetCapture(PopWnd);
End;

Function PopProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var P : TPaint; Hdc, I, X, Y : LongInt; R : TRect;
Begin
  PopProc := 0;
  Case M Of
    WM_PAINT :
    Begin
      Hdc := BeginPaint(H, P);
      GetClientRect(H, R);
      FillRect(Hdc, R, BrPop);
      DrawItems(Hdc, 2, 0, 0, 0, R.B);
      EndPaint(H, P);
    End;
    WM_LBUTTONDOWN :
    Begin
      ReleaseCapture;
      X := LoS(LP); Y := HiS(LP);
      GetClientRect(H, R);
      I := -1;
      If (X >= 0) And (Y >= 0) And (X < R.R) And (Y < R.B) Then
        I := HitItem(2, X, Y);
      If I >= 0 Then
      Begin
        W := ItLink[I]; X := ItVal[I]; Y := ItAux[I];
        PopOnly := False;
        ClosePopup;
        ShowWindow(Wnd, 1);
        FollowLink(W, X, Y);
      End
      Else ClosePopup;
    End;
    WM_KEYDOWN, WM_RBUTTONDOWN :
    Begin
      ReleaseCapture;
      ClosePopup;
    End;
  Else
    PopProc := DefWindowProcA(H, M, W, LP);
  End;
End;

{ ------------------------------------------------- sommaire (.CNT) }

Function CntAdd(S : String) : LongInt;
Var I : LongInt;
Begin
  CntAdd := CntPoolN;
  If CntPoolN + Length(S) + 2 > 262144 Then
  Begin
    CntAdd := 0;
    Exit;
  End;
  For I := 1 To Length(S) Do PByt(CntPool + CntPoolN + I - 1)^ := Ord(S[I]);
  PByt(CntPool + CntPoolN + Length(S))^ := 0;
  CntPoolN := CntPoolN + Length(S) + 1;
End;

Procedure LoadCntFile(F : String; Depth : LongInt);
Var A, N, I, J, Lv : LongInt; Ln, T, C, Fl : String;
Begin
  A := LoadFile(F, N);
  If A = 0 Then Exit;
  I := 0;
  While (I < N) And (NCnt < MaxCnt) Do
  Begin
    Ln := '';
    While (I < N) And (PByt(A + I)^ <> 10) Do
    Begin
      If (PByt(A + I)^ <> 13) And (Length(Ln) < 250) Then
        Ln := Ln + Chr(PByt(A + I)^);
      Inc(I);
    End;
    Inc(I);
    While (Ln <> '') And (Ln[1] In [' ', #9]) Do Delete(Ln, 1, 1);
    If Ln = '' Then Continue;
    If Ln[1] = ':' Then
    Begin
      T := UpStr(Copy(Ln, 1, 8));
      If Copy(T, 1, 5) = ':BASE' Then CntBase := Copy(Ln, 7, 255)
      Else If Copy(T, 1, 6) = ':TITLE' Then CntTitle := OemStr(Copy(Ln, 8, 255))
      Else If (Copy(T, 1, 8) = ':INCLUDE') And (Depth < 2) Then
        LoadCntFile(DirOf(F) + Copy(Ln, 10, 255), Depth + 1);
      Continue;
    End;
    If Not (Ln[1] In ['1'..'9']) Then Continue;
    Lv := Ord(Ln[1]) - 48;
    J := 2;
    While (J <= Length(Ln)) And (Ln[J] In [' ', #9]) Do Inc(J);
    Ln := Copy(Ln, J, 255);
    CntLvl[NCnt] := Lv;
    CntOpen[NCnt] := 0;
    J := Pos('=', Ln);
    If J = 0 Then
    Begin
      CntBook[NCnt] := 1;
      CntTxt[NCnt] := CntAdd(OemStr(Ln));
      CntCtx[NCnt] := -1; CntFile[NCnt] := -1;
    End
    Else
    Begin
      CntBook[NCnt] := 0;
      CntTxt[NCnt] := CntAdd(OemStr(Copy(Ln, 1, J - 1)));
      C := Copy(Ln, J + 1, 255);
      Fl := '';
      If Pos('>', C) > 0 Then C := Copy(C, 1, Pos('>', C) - 1);
      If Pos('@', C) > 0 Then
      Begin
        Fl := Copy(C, Pos('@', C) + 1, 255);
        C := Copy(C, 1, Pos('@', C) - 1);
      End;
      While (C <> '') And (C[Length(C)] = ' ') Do Delete(C, Length(C), 1);
      CntCtx[NCnt] := CntAdd(C);
      If Fl <> '' Then CntFile[NCnt] := CntAdd(Fl) Else CntFile[NCnt] := -1;
    End;
    Inc(NCnt);
  End;
  GlobalFree(A);
End;

Procedure LoadCnt;
Var F : String;
Begin
  NCnt := 0; CntPoolN := 1; CntTitle := ''; CntBase := '';
  F := Copy(HlpPath, 1, Length(HlpPath) - 4) + '.CNT';
  If FileExists(F) Then LoadCntFile(F, 0);
End;

{ ---------------------------------------- fenetre Rubriques d'aide }

Const
  LstRowH = 16;

Procedure LstBuild;
Var I, Hide : LongInt;
Begin
  LstN := 0;
  Case LstMode Of
    0 :
    Begin
      Hide := 99;
      For I := 0 To NCnt - 1 Do
      Begin
        If CntLvl[I] > Hide Then Continue;
        Hide := 99;
        LstMap^[LstN] := I;
        Inc(LstN);
        If (CntBook[I] = 1) And (CntOpen[I] = 0) Then Hide := CntLvl[I];
      End;
    End;
    1 :
      For I := 0 To NKw - 1 Do
      Begin
        LstMap^[LstN] := I;
        Inc(LstN);
      End;
    2 :
      For I := 0 To NFound - 1 Do
      Begin
        LstMap^[LstN] := I;
        Inc(LstN);
      End;
  End;
  If LstSel >= LstN Then LstSel := LstN - 1;
End;

Function LstRows : LongInt;
Begin
  LstRows := Max(1, (LstHt - 4) Div LstRowH);
End;

Procedure LstUpd;
Var M : LongInt;
Begin
  M := LstN - LstRows;
  If M < 0 Then M := 0;
  If LstTop > M Then LstTop := M;
  If LstTop < 0 Then LstTop := 0;
  SetScrollRange(TScroll, SB_CTL, 0, Max(M, 1), 0);
  SetScrollPos(TScroll, SB_CTL, LstTop, 1);
  EnableWindow(TScroll, Ord(M > 0));
End;

Procedure LstShowSel;
Begin
  If LstSel < LstTop Then LstTop := LstSel;
  If LstSel >= LstTop + LstRows Then LstTop := LstSel - LstRows + 1;
  LstUpd;
  InvalidateRect(TopWnd, Nil, 0);
End;

Function LstText(R : LongInt) : String;
Var K : LongInt;
Begin
  LstText := '';
  If (R < 0) Or (R >= LstN) Then Exit;
  K := LstMap^[R];
  Case LstMode Of
    0 : LstText := CStr(CntPool + CntTxt[K]);
    1 : LstText := OemStr(CStr(KwStr^[K]));
    2 : LstText := TopicTitle(TopicIdx(FoundOff^[K]));
  End;
End;

{ petit livre (ferme ou ouvert) ou page, comme le Sommaire de Windows }
Procedure DrawCntIcon(Hdc, X, Y, Book, Op : LongInt);
Var R : TRect; B : LongInt;
Begin
  If Book = 0 Then
  Begin
    SelectObject(Hdc, PenBlack);
    R.L := X + 2; R.T := Y + 1; R.R := X + 12; R.B := Y + 14;
    FillRect(Hdc, R, BrWhite);
    MoveToEx(Hdc, X + 2, Y + 1, Nil); GdiLineTo(Hdc, X + 11, Y + 1);
    GdiLineTo(Hdc, X + 11, Y + 14); GdiLineTo(Hdc, X + 2, Y + 14);
    GdiLineTo(Hdc, X + 2, Y + 1);
    SelectObject(Hdc, PenGray);
    For B := 0 To 3 Do
    Begin
      MoveToEx(Hdc, X + 4, Y + 4 + B * 2, Nil);
      GdiLineTo(Hdc, X + 10, Y + 4 + B * 2);
    End;
    Exit;
  End;
  B := CreateSolidBrush($00A0A0 + Op * $500000);
  If Op = 0 Then
  Begin
    R.L := X + 1; R.T := Y + 2; R.R := X + 13; R.B := Y + 14;
    FillRect(Hdc, R, B);
    SelectObject(Hdc, PenBlack);
    MoveToEx(Hdc, X + 1, Y + 2, Nil); GdiLineTo(Hdc, X + 12, Y + 2);
    GdiLineTo(Hdc, X + 12, Y + 13); GdiLineTo(Hdc, X + 1, Y + 13);
    GdiLineTo(Hdc, X + 1, Y + 2);
    MoveToEx(Hdc, X + 3, Y + 2, Nil); GdiLineTo(Hdc, X + 3, Y + 13);
  End
  Else
  Begin
    R.L := X; R.T := Y + 4; R.R := X + 7; R.B := Y + 13;
    FillRect(Hdc, R, BrWhite);
    R.L := X + 7; R.R := X + 14;
    FillRect(Hdc, R, BrWhite);
    SelectObject(Hdc, PenBlack);
    MoveToEx(Hdc, X, Y + 4, Nil); GdiLineTo(Hdc, X + 6, Y + 5);
    GdiLineTo(Hdc, X + 13, Y + 4); GdiLineTo(Hdc, X + 13, Y + 12);
    GdiLineTo(Hdc, X + 6, Y + 13); GdiLineTo(Hdc, X, Y + 12);
    GdiLineTo(Hdc, X, Y + 4);
    MoveToEx(Hdc, X + 6, Y + 5, Nil); GdiLineTo(Hdc, X + 6, Y + 13);
  End;
  DeleteObject(B);
End;

Procedure LstPaint(Hdc : LongInt);
Var R : TRect; I, Y, X, K : LongInt; S : String;
Begin
  R.L := LstX; R.T := LstY; R.R := LstX + LstWd; R.B := LstY + LstHt;
  FillRect(Hdc, R, BrWhite);
  SelectObject(Hdc, PenGray);
  MoveToEx(Hdc, R.L - 1, R.B, Nil); GdiLineTo(Hdc, R.L - 1, R.T - 1);
  GdiLineTo(Hdc, R.R + ScrW, R.T - 1);
  SelectObject(Hdc, PenWhite);
  MoveToEx(Hdc, R.L - 1, R.B, Nil); GdiLineTo(Hdc, R.R + ScrW, R.B);
  SelectObject(Hdc, HFnt[0]);
  SetBkMode(Hdc, 1);
  For I := 0 To LstRows - 1 Do
  Begin
    K := LstTop + I;
    If K >= LstN Then Break;
    Y := LstY + 2 + I * LstRowH;
    X := LstX + 3;
    If LstMode = 0 Then
    Begin
      X := X + (CntLvl[LstMap^[K]] - 1) * 18;
      DrawCntIcon(Hdc, X, Y, CntBook[LstMap^[K]], CntOpen[LstMap^[K]]);
      X := X + 18;
    End;
    S := LstText(K);
    If K = LstSel Then
    Begin
      R.L := X - 1; R.T := Y; R.R := Min(X + Length(S) * 6 + 2, LstX + LstWd);
      R.B := Y + LstRowH - 1;
      FillRect(Hdc, R, BrNavy);
      SetTextColor(Hdc, cWhite);
    End
    Else SetTextColor(Hdc, cBlack);
    TextOutA(Hdc, X, Y + 1, Z(S), Min(Length(S), (LstX + LstWd - X) Div 6));
  End;
End;

Function TopicsCaption : String;
Var T : String;
Begin
  T := CntTitle;
  If T = '' Then T := HlpTitle;
  If FoundMode Then
    TopicsCaption := L('Rubriques trouv'#130'es', 'Topics Found',
                       'Gefundene Themen', 'Argomenti trovati',
                       'Temas encontrados')
  Else
    TopicsCaption := L('Rubriques d''aide : ', 'Help Topics: ',
                       'Hilfethemen: ', 'Argomenti della Guida: ',
                       'Temas de Ayuda: ') + T;
End;

Procedure TopicsLayout;
Var R : TRect; Y : LongInt;
Begin
  GetClientRect(TopWnd, R);
  If FoundMode Then Y := 36
  Else If TopTab = 0 Then Y := 72
  Else Y := 104;
  LstX := 16; LstY := Y; LstWd := R.R - 32 - ScrW; LstHt := R.B - 44 - Y;
  MoveWindow(TScroll, LstX + LstWd, LstY, ScrW, LstHt, 1);
  MoveWindow(TEdit, 16, 66, R.R - 32 - 96 * Ord(TopTab = 2), 22, 1);
  MoveWindow(TFind, R.R - 104, 65, 88, 24, 1);
  MoveWindow(TShow, R.R - 196, R.B - 34, 88, 24, 1);
  MoveWindow(TCancel, R.R - 104, R.B - 34, 88, 24, 1);
  ShowWindow(TEdit, Ord((TopTab > 0) And Not FoundMode));
  ShowWindow(TFind, Ord((TopTab = 2) And Not FoundMode));
  LstUpd;
End;

Procedure SetTab(T : LongInt);
Begin
  TopTab := T;
  LstMode := T;
  If T = 2 Then LstMode := 2;
  If T = 2 Then NFound := 0;
  LstSel := 0; LstTop := 0;
  LstBuild;
  If (LstMode = 0) Or FoundMode Then
    SetWindowTextA(TShow, Z(L('&Afficher', '&Display', '&Anzeigen',
                              '&Visualizza', '&Mostrar')))
  Else SetWindowTextA(TShow, Z(L('&Afficher', '&Display', '&Anzeigen',
                                 '&Visualizza', '&Mostrar')));
  SetWindowTextA(TEdit, Z(''));
  TopicsLayout;
  InvalidateRect(TopWnd, Nil, 1);
  If TopTab > 0 Then SetFocus(TEdit);
End;

Procedure OpenTopics(Tab : LongInt);
Begin
  If FBuf = 0 Then Exit;
  If Tab < 0 Then
  Begin
    If NCnt > 0 Then Tab := 0 Else Tab := 1;
  End;
  If (Tab = 0) And (NCnt = 0) Then Tab := 1;
  FoundMode := False;
  If TopWnd = 0 Then
    TopWnd := CreateWindowExA(0, Z('WinHlpTopics'), Z2(TopicsCaption),
                              WS_CAPTION Or WS_SYSMENU Or WS_VISIBLE Or
                              WS_CLIPCHILDREN, 150, 40, 440, 400, Wnd, 0,
                              Inst, 0)
  Else SetWindowTextA(TopWnd, Z(TopicsCaption));
  SetTab(Tab);
  ShowWindow(TopWnd, 1);
End;

Procedure ShowFound(Title : String);
Begin
  If TopWnd <> 0 Then DestroyWindow(TopWnd);
  TopWnd := 0;
  FoundMode := True;
  TopWnd := CreateWindowExA(0, Z('WinHlpTopics'), Z2(Title), WS_CAPTION Or
                            WS_SYSMENU Or WS_VISIBLE Or WS_CLIPCHILDREN,
                            170, 90, 400, 300, Wnd, 0, Inst, 0);
  SetWindowTextA(TopWnd, Z(Title));
  TopTab := 0; LstMode := 2; LstSel := 0; LstTop := 0;
  LstBuild;
  TopicsLayout;
  InvalidateRect(TopWnd, Nil, 1);
End;

Procedure CloseTopics;
Begin
  If TopWnd <> 0 Then DestroyWindow(TopWnd);
  TopWnd := 0;
End;

{ Ouvre la ligne R du sommaire (livre : ouvre ou ferme) }
Procedure CntActivate(K : LongInt);
Var F : String; Off : LongInt;
Begin
  If CntBook[K] = 1 Then
  Begin
    CntOpen[K] := 1 - CntOpen[K];
    LstBuild;
    LstUpd;
    InvalidateRect(TopWnd, Nil, 0);
    Exit;
  End;
  F := '';
  If CntFile[K] >= 0 Then F := CStr(CntPool + CntFile[K])
  Else If CntBase <> '' Then F := CntBase;
  CloseTopics;
  If GoFile(F) Then
  Begin
    Off := CtxLookup(HashCtx(CStr(CntPool + CntCtx[K])));
    JumpOff(Off);
  End;
  ShowWindow(Wnd, 1);
End;

{ Recherche du texte (page 437, sans accents) dans toutes les rubriques }
Procedure FullSearch(W : String);
Var TP, N, Cur, I, J, K, M : LongInt; U : String; Hit : Boolean;
    Buf : Array[0..255] Of Char;
Begin
  NFound := 0;
  U := FoldStr(W);
  M := Length(U);
  If (M = 0) Or (NBlk = 0) Then Exit;
  SetCursor(CurWait);
  TP := BlkHdr(0, 1);
  Cur := -1; N := 0; Hit := False;
  While (TP > 0) And (N < 400000) Do
  Begin
    If Not ReadRec(TP) Then Break;
    If RType = 2 Then
    Begin
      Inc(Cur);
      Hit := False;
    End
    Else If ((RType = $20) Or (RType = $23)) And Not Hit And
            (Cur >= 0) And (Cur < NTop) Then
    Begin
      J := 0;
      For I := 0 To L2Len - 1 Do
      Begin
        K := Fold(Oem(PByt(L2Buf + I)^));
        If K = Ord(U[J + 1]) Then
        Begin
          Inc(J);
          If J = M Then
          Begin
            AddFound(TopOff^[Cur]);
            Hit := True;
            Break;
          End;
        End
        Else If K = Ord(U[1]) Then J := 1
        Else J := 0;
      End;
    End;
    TP := RNext;
    Inc(N);
  End;
  SetCursor(CurArrow);
End;

Procedure TopicsActivate;
Var K : LongInt; T : String;
Begin
  If (LstSel < 0) Or (LstSel >= LstN) Then Exit;
  K := LstMap^[LstSel];
  If FoundMode Or (LstMode = 2) Then
  Begin
    K := FoundOff^[K];
    CloseTopics;
    JumpOff(K);
    ShowWindow(Wnd, 1);
  End
  Else If LstMode = 0 Then CntActivate(K)
  Else
  Begin
    NFound := 0;
    KwTopicsOf(K);
    T := LstText(LstSel);
    CloseTopics;
    ShowFoundOrJump(L('Rubriques trouv'#130'es', 'Topics Found',
                      'Gefundene Themen', 'Argomenti trovati',
                      'Temas encontrados'));
    ShowWindow(Wnd, 1);
  End;
End;

{ Index : premiere entree qui commence par le texte tape }
Procedure IndexSeek;
Var B : Array[0..255] Of Char; S : String; I : LongInt;
Begin
  B[0] := #0;
  GetWindowTextA(TEdit, @B, 250);
  S := FoldStr(CStr(LongInt(@B)));
  If S = '' Then Exit;
  For I := 0 To LstN - 1 Do
    If Copy(FoldStr(LstText(I)), 1, Length(S)) = S Then
    Begin
      LstSel := I;
      LstTop := I;
      LstShowSel;
      Exit;
    End;
End;

Procedure TabPaint(Hdc : LongInt);
Var I, X, W : LongInt; R : TRect; S : String;
Begin
  SelectObject(Hdc, HFnt[0]);
  SetBkMode(Hdc, 1);
  SetTextColor(Hdc, cBlack);
  If FoundMode Then
  Begin
    S := L('Cliquez sur une rubrique, puis sur Afficher.', 'Click a ' +
           'topic, then click Display.', 'Klicken Sie auf ein Thema und ' +
           'dann auf Anzeigen.', 'Scegliere un argomento, quindi ' +
           'Visualizza.', 'Haga clic en un tema y luego en Mostrar.');
    TextOutA(Hdc, 16, 14, Z(S), Length(S));
    Exit;
  End;
  X := 8;
  For I := 0 To 2 Do
  Begin
    Case I Of
      0 : S := L('Sommaire', 'Contents', 'Inhalt', 'Sommario', 'Contenido');
      1 : S := 'Index';
    Else
      S := L('Rechercher', 'Find', 'Suchen', 'Trova', 'Buscar');
    End;
    W := Length(S) * 6 + 20;
    R.L := X; R.T := 8 + 2 * Ord(I <> TopTab); R.R := X + W; R.B := 30;
    If I = TopTab Then R.B := 31;
    SelectObject(Hdc, PenWhite);
    MoveToEx(Hdc, R.L, R.B, Nil); GdiLineTo(Hdc, R.L, R.T);
    GdiLineTo(Hdc, R.R, R.T);
    SelectObject(Hdc, PenBlack);
    GdiLineTo(Hdc, R.R, R.B);
    TextOutA(Hdc, X + 10, R.T + 4, Z(S), Length(S));
    X := X + W + 2;
  End;
  SelectObject(Hdc, PenWhite);
  MoveToEx(Hdc, 4, 31, Nil); GdiLineTo(Hdc, 8, 31);
  SelectObject(Hdc, PenBlack);
  Case TopTab Of
    0 : S := L('Cliquez sur un livre, puis sur Afficher, ou sur une ' +
               'rubrique.', 'Click a book, and then click Open. Or click ' +
               'a topic.', 'Klicken Sie auf ein Buch oder ein Thema.',
               'Scegliere un libro o un argomento.', 'Haga clic en un ' +
               'libro o en un tema.');
    1 : S := L('1  Tapez les premi'#138'res lettres du mot recherch'#130'.',
               '1  Type the first few letters of the word.', '1  Geben ' +
               'Sie die ersten Buchstaben ein.', '1  Digitare le prime ' +
               'lettere della parola.', '1  Escriba las primeras letras.');
  Else
    S := L('1  Tapez le ou les mots '#133' rechercher.', '1  Type the ' +
           'word(s) you want to find.', '1  Geben Sie das Suchwort ein.',
           '1  Digitare la parola da cercare.', '1  Escriba la palabra ' +
           'que desea buscar.');
  End;
  TextOutA(Hdc, 16, 44, Z(S), Length(S));
  If TopTab > 0 Then
  Begin
    S := L('2  Cliquez sur l''entr'#130'e voulue, puis sur Afficher.',
           '2  Click the entry you want, and then click Display.',
           '2  Klicken Sie auf den Eintrag und dann auf Anzeigen.',
           '2  Scegliere la voce, quindi Visualizza.', '2  Haga clic ' +
           'en la entrada y luego en Mostrar.');
    TextOutA(Hdc, 16, 92, Z(S), Length(S));
  End;
End;

Function TopProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var P : TPaint; Hdc, X, Y, I, Wd : LongInt; R : TRect; B : Array[0..255]
    Of Char;
Begin
  TopProc := 0;
  Case M Of
    WM_CREATE :
    Begin
      TopWnd := H;
      TEdit := CreateWindowExA($200, Z('EDIT'), Z2(''), WS_CHILD Or
                               WS_VISIBLE Or WS_TABSTOP Or WS_BORDER,
                               16, 66, 300, 22, H, idTEdit, Inst, 0);
      TFind := CreateWindowExA(0, Z('BUTTON'), Z2(L('&Rechercher', '&Find',
                               '&Suchen', '&Trova', '&Buscar')), WS_CHILD Or
                               WS_TABSTOP, 0, 0, 88, 24, H, idTFind, Inst, 0);
      TShow := CreateWindowExA(0, Z('BUTTON'), Z2(L('&Afficher', '&Display',
                               '&Anzeigen', '&Visualizza', '&Mostrar')),
                               WS_CHILD Or WS_VISIBLE Or WS_TABSTOP Or
                               BS_DEFPUSHBUTTON, 0, 0, 88, 24, H, idTShow,
                               Inst, 0);
      TCancel := CreateWindowExA(0, Z('BUTTON'), Z2(L('Annuler', 'Cancel',
                                 'Abbrechen', 'Annulla', 'Cancelar')),
                                 WS_CHILD Or WS_VISIBLE Or WS_TABSTOP, 0, 0,
                                 88, 24, H, idTCancel, Inst, 0);
      TScroll := CreateWindowExA(0, Z('SCROLLBAR'), Z2(''), WS_CHILD Or
                                 WS_VISIBLE Or SBS_VERT, 0, 0, ScrW, 100, H,
                                 idTScroll, Inst, 0);
      SendMessageA(TEdit, WM_SETFONT, HFnt[0], 0);
      SendMessageA(TFind, WM_SETFONT, HFnt[0], 0);
      SendMessageA(TShow, WM_SETFONT, HFnt[0], 0);
      SendMessageA(TCancel, WM_SETFONT, HFnt[0], 0);
    End;
    WM_PAINT :
    Begin
      Hdc := BeginPaint(H, P);
      TabPaint(Hdc);
      LstPaint(Hdc);
      EndPaint(H, P);
    End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK :
    Begin
      X := LoS(LP); Y := HiS(LP);
      If Not FoundMode And (Y >= 8) And (Y < 31) Then
      Begin
        Wd := 8;
        For I := 0 To 2 Do
        Begin
          Case I Of
            0 : B[0] := Chr(Length(L('Sommaire', 'Contents', 'Inhalt',
                                     'Sommario', 'Contenido')));
            1 : B[0] := #5;
          Else
            B[0] := Chr(Length(L('Rechercher', 'Find', 'Suchen', 'Trova',
                                 'Buscar')));
          End;
          If (X >= Wd) And (X < Wd + Ord(B[0]) * 6 + 20) Then
          Begin
            If (I <> 0) Or (NCnt > 0) Then SetTab(I);
            Exit;
          End;
          Wd := Wd + Ord(B[0]) * 6 + 22;
        End;
        Exit;
      End;
      If (X >= LstX) And (X < LstX + LstWd) And (Y >= LstY + 2) And
         (Y < LstY + LstHt) Then
      Begin
        I := LstTop + (Y - LstY - 2) Div LstRowH;
        If I < LstN Then
        Begin
          LstSel := I;
          InvalidateRect(H, Nil, 0);
          If M = WM_LBUTTONDBLCLK Then TopicsActivate;
        End;
      End;
    End;
    WM_KEYDOWN :
    Begin
      Case W Of
        $26 : If LstSel > 0 Then Dec(LstSel);
        $28 : If LstSel < LstN - 1 Then Inc(LstSel);
        $21 : LstSel := Max(0, LstSel - LstRows);
        $22 : LstSel := Min(LstN - 1, LstSel + LstRows);
        $0D : TopicsActivate;
        $1B : CloseTopics;
      End;
      If TopWnd <> 0 Then LstShowSel;
    End;
    WM_VSCROLL :
    Begin
      Case W And $FFFF Of
        SB_LINEUP : Dec(LstTop);
        SB_LINEDOWN : Inc(LstTop);
        SB_PAGEUP : LstTop := LstTop - LstRows;
        SB_PAGEDOWN : LstTop := LstTop + LstRows;
        SB_THUMBTRACK, SB_THUMBPOSITION : LstTop := (W Shr 16) And $FFFF;
      End;
      LstUpd;
      InvalidateRect(H, Nil, 0);
    End;
    WM_COMMAND :
      Case W And $FFFF Of
        idTShow : TopicsActivate;
        idTCancel, 2 : CloseTopics;
        idTFind :
        Begin
          B[0] := #0;
          GetWindowTextA(TEdit, @B, 250);
          FullSearch(CStr(LongInt(@B)));
          LstMode := 2; LstSel := 0; LstTop := 0;
          LstBuild;
          LstUpd;
          InvalidateRect(H, Nil, 1);
        End;
        idTEdit :
          If ((W Shr 16) = EN_CHANGE) And (TopTab = 1) Then IndexSeek;
      End;
    WM_CLOSE : CloseTopics;
    WM_DESTROY : If TopWnd = H Then TopWnd := 0;
  Else
    TopProc := DefWindowProcA(H, M, W, LP);
  End;
End;

{ ------------------------------------------- fenetre principale }

Procedure Layout;
Var R : TRect;
Begin
  GetClientRect(Wnd, R);
  MoveWindow(BtnTopics, 4, 2, 112, BtnH - 4, 1);
  MoveWindow(BtnBack, 120, 2, 84, BtnH - 4, 1);
  MoveWindow(BtnPrev, 208, 2, 34, BtnH - 4, 1);
  MoveWindow(BtnNext, 246, 2, 34, BtnH - 4, 1);
  ViewH := R.B - ViewTop;
  MoveWindow(ScrollBar, R.R - ScrW, ViewTop, ScrW, Max(ViewH, 8), 1);
End;

{ Copie le texte de la rubrique dans le presse-papiers }
Procedure CopyToClip;
Var I, N, A, Y, K : LongInt;
Begin
  N := 0;
  For I := 0 To NItem - 1 Do N := N + ItLen[I] + 2;
  A := GlobalAlloc(2, N + Length(CurTitle) + 8);
  If A = 0 Then Exit;
  K := 0; Y := -1;
  For I := 0 To NItem - 1 Do
  Begin
    If (ItRgn[I] = 2) Or (ItKind[I] <> 0) Then Continue;
    If (Y >= 0) And (ItY[I] + ItRgn[I] * 100000 <> Y) Then
    Begin
      PByt(A + K)^ := 13; PByt(A + K + 1)^ := 10;
      K := K + 2;
    End;
    Y := ItY[I] + ItRgn[I] * 100000;
    Move(Pointer(Pool + ItTxt[I])^, Pointer(A + K)^, ItLen[I]);
    K := K + ItLen[I];
  End;
  PByt(A + K)^ := 0;
  If OpenClipboard(Wnd) <> 0 Then
  Begin
    EmptyClipboard;
    SetClipboardData(1, A);
    CloseClipboard;
  End;
End;

Procedure DoOpen;
Var Ofn : Array[0..21] Of LongInt; Buf : Array[0..259] Of Char;
    Flt : String;
Begin
  FillChar(Ofn, SizeOf(Ofn), 0);
  Buf[0] := #0;
  Flt := L('Fichiers d''aide (*.hlp)', 'Help Files (*.hlp)',
           'Hilfedateien (*.hlp)', 'File della Guida (*.hlp)',
           'Archivos de ayuda (*.hlp)') + #0'*.hlp'#0#0;
  Ofn[0] := 76; Ofn[1] := Wnd; Ofn[3] := LongInt(@Flt[1]);
  Ofn[7] := LongInt(@Buf); Ofn[8] := 260; Ofn[13] := $1000;
  If GetOpenFileNameA(@Ofn) = 0 Then Exit;
  NHist := 0;
  If OpenHelp(CStr(LongInt(@Buf))) Then
  Begin
    NItem := 0;
    If ContentsOff >= 0 Then ShowTopic(ContentsOff)
    Else If NTop > 0 Then ShowTopic(TopOff^[0]);
    If NCnt > 0 Then OpenTopics(0);
  End;
End;

Procedure SetFontBias(B : LongInt);
Var M : LongInt;
Begin
  FontBias := B;
  M := MenuOpt;
  CheckMenuItem(M, idFontS, MF_CHECKED * Ord(B < 0));
  CheckMenuItem(M, idFontN, MF_CHECKED * Ord(B = 0));
  CheckMenuItem(M, idFontL, MF_CHECKED * Ord(B > 0));
  Relayout;
End;

Procedure AddItem(M, Id : LongInt; S : String; F : LongInt);
Begin
  AppendMenuA(M, F, Id, Z(S));
End;

Procedure BuildMenus;
Var Bar, F, E, O, H : LongInt;
Begin
  Bar := CreateMenu;
  F := CreatePopupMenu;
  AddItem(F, idOpen, L('&Ouvrir...', '&Open...', '&'#153'ffnen...',
          '&Apri...', '&Abrir...'), 0);
  AddItem(F, 0, '', MF_SEPARATOR);
  AddItem(F, idExit, L('&Quitter', 'E&xit', '&Beenden', '&Esci', '&Salir'),
          0);
  E := CreatePopupMenu;
  AddItem(E, idCopy, L('&Copier'#9'Ctrl+C', '&Copy'#9'Ctrl+C',
          '&Kopieren'#9'Strg+C', '&Copia'#9'Ctrl+C', '&Copiar'#9'Ctrl+C'), 0);
  O := CreatePopupMenu;
  MenuOpt := O;
  AddItem(O, idTopics, L('&Rubriques d''aide', 'Help &Topics',
          '&Hilfethemen', '&Argomenti della Guida', '&Temas de Ayuda'), 0);
  AddItem(O, idPrevMenu, L('&Pr'#130'c'#130'dent', '&Back', '&Zur'#129'ck',
          '&Indietro', '&Atr'#160's'), 0);
  AddItem(O, 0, '', MF_SEPARATOR);
  AddItem(O, idFontS, L('Texte &petit', '&Small Font', '&Kleine Schrift',
          'Carattere &piccolo', 'Fuente &peque'#164'a'), 0);
  AddItem(O, idFontN, L('Texte &normal', '&Normal Font', '&Normale ' +
          'Schrift', 'Carattere &normale', 'Fuente &normal'), MF_CHECKED);
  AddItem(O, idFontL, L('Texte &grand', '&Large Font', '&Gro'#225'e ' +
          'Schrift', 'Carattere &grande', 'Fuente &grande'), 0);
  H := CreatePopupMenu;
  AddItem(H, idAbout, L(''#183' &propos de l''Aide...', '&About Help...',
          '&Info...', '&Informazioni...', '&Acerca de Ayuda...'), 0);
  AppendMenuA(Bar, MF_POPUP, F, Z(L('&Fichier', '&File', '&Datei', '&File',
              '&Archivo')));
  AppendMenuA(Bar, MF_POPUP, E, Z(L('&Edition', '&Edit', '&Bearbeiten',
              '&Modifica', '&Edici'#162'n')));
  AppendMenuA(Bar, MF_POPUP, O, Z(L('&Options', '&Options', '&Optionen',
              '&Opzioni', '&Opciones')));
  AppendMenuA(Bar, MF_POPUP, H, Z('&?'));
  SetMenu(Wnd, Bar);
End;

Function WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var P : TPaint; Hdc, X, Y, I, T : LongInt; R : TRect;
Begin
  WndProc := 0;
  Case M Of
    WM_CREATE :
    Begin
      Wnd := H;
      BtnTopics := CreateWindowExA(0, Z('BUTTON'), Z2(L('Rubriques d''aide',
        'Help Topics', 'Hilfethemen', 'Argomenti', 'Temas de Ayuda')),
        WS_CHILD Or WS_VISIBLE, 0, 0, 10, 10, H, idBtnTopics, Inst, 0);
      BtnBack := CreateWindowExA(0, Z('BUTTON'), Z2(L('Pr'#130'c'#130'dent',
        'Back', 'Zur'#129'ck', 'Indietro', 'Atr'#160's')), WS_CHILD Or
        WS_VISIBLE, 0, 0, 10, 10, H, idBtnBack, Inst, 0);
      BtnPrev := CreateWindowExA(0, Z('BUTTON'), Z2('<<'), WS_CHILD Or
        WS_VISIBLE, 0, 0, 10, 10, H, idBtnPrev, Inst, 0);
      BtnNext := CreateWindowExA(0, Z('BUTTON'), Z2('>>'), WS_CHILD Or
        WS_VISIBLE, 0, 0, 10, 10, H, idBtnNext, Inst, 0);
      ScrollBar := CreateWindowExA(0, Z('SCROLLBAR'), Z2(''), WS_CHILD Or
        WS_VISIBLE Or SBS_VERT, 0, 0, ScrW, 10, H, idScroll, Inst, 0);
      SendMessageA(BtnTopics, WM_SETFONT, HFnt[0], 0);
      SendMessageA(BtnBack, WM_SETFONT, HFnt[0], 0);
      SendMessageA(BtnPrev, WM_SETFONT, HFnt[0], 0);
      SendMessageA(BtnNext, WM_SETFONT, HFnt[0], 0);
      EnableWindow(BtnBack, 0);
      EnableWindow(BtnPrev, 0);
      EnableWindow(BtnNext, 0);
    End;
    WM_SIZE :
    Begin
      Layout;
      Relayout;
    End;
    WM_PAINT :
    Begin
      Hdc := BeginPaint(H, P);
      GetClientRect(H, R);
      { barre des boutons }
      R.B := BtnH;
      FillRect(Hdc, R, BrFace);
      SelectObject(Hdc, PenGray);
      MoveToEx(Hdc, 0, BtnH - 1, Nil); GdiLineTo(Hdc, R.R, BtnH - 1);
      { zone defilante, puis zone non defilante par-dessus }
      GetClientRect(H, R);
      R.T := ViewTop; R.R := R.R - ScrW;
      FillRect(Hdc, R, BrWhite);
      DrawItems(Hdc, 0, 0, ViewTop - ScrollY, ViewTop, R.B);
      If NsH > 0 Then
      Begin
        R.T := BtnH; R.B := BtnH + NsH;
        FillRect(Hdc, R, BrWhite);
        DrawItems(Hdc, 1, 0, BtnH, BtnH, BtnH + NsH);
        SelectObject(Hdc, PenGray);
        MoveToEx(Hdc, 0, BtnH + NsH - 1, Nil);
        GdiLineTo(Hdc, R.R + ScrW, BtnH + NsH - 1);
      End;
      EndPaint(H, P);
    End;
    WM_VSCROLL :
    Begin
      T := ScrollY;
      Case W And $FFFF Of
        SB_LINEUP : T := T - 16;
        SB_LINEDOWN : T := T + 16;
        SB_PAGEUP : T := T - ViewH + 16;
        SB_PAGEDOWN : T := T + ViewH - 16;
        SB_THUMBTRACK, SB_THUMBPOSITION : T := (W Shr 16) And $FFFF;
        SB_TOP : T := 0;
        SB_BOTTOM : T := DocH;
      End;
      ScrollTo(T);
    End;
    WM_MOUSEWHEEL :
    Begin
      If HiS(W) > 0 Then ScrollTo(ScrollY - 48) Else ScrollTo(ScrollY + 48);
    End;
    WM_MOUSEMOVE :
    Begin
      X := LoS(LP); Y := HiS(LP);
      I := -1;
      If (NsH > 0) And (Y >= BtnH) And (Y < BtnH + NsH) Then
        I := HitItem(1, X, Y - BtnH)
      Else If Y >= ViewTop Then I := HitItem(0, X, Y - ViewTop + ScrollY);
      If I >= 0 Then SetCursor(CurHand) Else SetCursor(CurArrow);
    End;
    WM_LBUTTONDOWN :
    Begin
      ClosePopup;
      X := LoS(LP); Y := HiS(LP);
      If (NsH > 0) And (Y >= BtnH) And (Y < BtnH + NsH) Then
        ClickItem(HitItem(1, X, Y - BtnH), X, Y - BtnH)
      Else If Y >= ViewTop Then
      Begin
        Y := Y - ViewTop + ScrollY;
        ClickItem(HitItem(0, X, Y), X, Y);
      End;
    End;
    WM_KEYDOWN :
      Case W Of
        $26 : ScrollTo(ScrollY - 16);
        $28 : ScrollTo(ScrollY + 16);
        $21 : ScrollTo(ScrollY - ViewH + 16);
        $22 : ScrollTo(ScrollY + ViewH - 16);
        $24 : ScrollTo(0);
        $23 : ScrollTo(DocH);
        $08 : GoBack;
        $43 : If (GetKeyState($11) And $8000) <> 0 Then CopyToClip;
      End;
    WM_COMMAND :
      Case W And $FFFF Of
        idBtnTopics, idTopics : OpenTopics(-1);
        idBtnBack, idPrevMenu : GoBack;
        idBtnPrev : If CurBck <> -1 Then JumpOff(CurBck);
        idBtnNext : If CurFor <> -1 Then JumpOff(CurFor);
        idOpen : DoOpen;
        idExit : PostMessageA(H, WM_CLOSE, 0, 0);
        idCopy : CopyToClip;
        idFontS : SetFontBias(-1);
        idFontN : SetFontBias(0);
        idFontL : SetFontBias(1);
        idAbout :
          MessageBoxA(H, Z(AppTitle + #13#10'Pasdows 95'#13#10#13#10 +
                      HlpTitle + #13#10 + HlpCopy), Z2(AppTitle),
                      MB_OK Or MB_ICONINFO);
      End;
    WM_DESTROY : PostQuitMessage(0);
  Else
    WndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

{ -------------------------------------------------------- programme }

Var
  WC : TWndClass;
  M : TMsg;
  Cmd, Arg1, FileArg, Opt, OptVal : String;
  I, Off : LongInt;
  Started : Boolean;
  ClsMain, ClsPop, ClsTop : String;

{ mot suivant de la ligne de commande (guillemets acceptes) }
Function NextWord(Var S : String) : String;
Var R : String;
Begin
  While (S <> '') And (S[1] = ' ') Do Delete(S, 1, 1);
  R := '';
  If (S <> '') And (S[1] = '"') Then
  Begin
    Delete(S, 1, 1);
    While (S <> '') And (S[1] <> '"') Do
    Begin
      R := R + S[1];
      Delete(S, 1, 1);
    End;
    If S <> '' Then Delete(S, 1, 1);
  End
  Else
    While (S <> '') And (S[1] <> ' ') Do
    Begin
      R := R + S[1];
      Delete(S, 1, 1);
    End;
  NextWord := R;
End;

Begin
  LangInit;
  Inst := GetModuleHandleA(Nil);
  TopOff := PLongArr(GlobalAlloc(0, MaxTop * 4));
  TopTtl := PLongArr(GlobalAlloc(0, MaxTop * 4));
  KwStr := PLongArr(GlobalAlloc(0, MaxKw * 4));
  KwCnt := PLongArr(GlobalAlloc(0, MaxKw * 4));
  KwOfs := PLongArr(GlobalAlloc(0, MaxKw * 4));
  FoundOff := PLongArr(GlobalAlloc(0, MaxTop * 4));
  LstMap := PLongArr(GlobalAlloc(0, (MaxKw + MaxTop) * 4));
  RecBuf := GlobalAlloc(0, RecMax + 64);
  L2Buf := GlobalAlloc(0, RecMax + 64);
  Pool := GlobalAlloc(0, PoolMax + 16);
  CntPool := GlobalAlloc(0, 262144 + 16);
  For I := 0 To NSlot - 1 Do
  Begin
    SlotBuf[I] := GlobalAlloc(0, 16384 + 64);
    SlotBlk[I] := -1;
  End;
  HFnt[0] := CreateFontA(-13, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0,
                         Z('MS Sans Serif'));
  HFnt[1] := CreateFontA(-16, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0,
                         Z('Arial'));
  HFnt[2] := CreateFontA(-24, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0,
                         Z('Arial'));
  HFnt[3] := CreateFontA(-32, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0,
                         Z('Arial'));
  BrWhite := CreateSolidBrush(cWhite);
  BrFace := CreateSolidBrush(cFace);
  BrPop := CreateSolidBrush(cPopBg);
  BrNavy := CreateSolidBrush(cNavy);
  PenGreen := CreatePen(0, 1, cGreen);
  PenGray := CreatePen(0, 1, cGray);
  PenBlack := CreatePen(0, 1, cBlack);
  PenWhite := CreatePen(0, 1, cWhite);
  CurArrow := LoadCursorA(0, 32512);
  CurWait := LoadCursorA(0, 32514);
  CurHand := LoadCursorA(0, 32649);
  If CurHand = 0 Then CurHand := LoadCursorA(0, 32515);

  { ligne de commande : [-k mot | -n num | -i ctx | -p num] fichier }
  Cmd := '';
  For I := 1 To ParamCount Do
  Begin
    Arg1 := ParamStr(I);
    If Pos(' ', Arg1) > 0 Then Arg1 := '"' + Arg1 + '"';
    If Cmd <> '' Then Cmd := Cmd + ' ';
    Cmd := Cmd + Arg1;
  End;
  Opt := ''; OptVal := ''; FileArg := '';
  Repeat
    Arg1 := NextWord(Cmd);
    If Arg1 = '' Then Break;
    If (Length(Arg1) = 2) And (Arg1[1] In ['-', '/']) And
       (UpCase(Arg1[2]) In ['K', 'N', 'I', 'P']) Then
    Begin
      Opt := UpCase(Arg1[2]);
      If Opt = 'K' Then
      Begin
        { le mot-cle peut contenir des espaces : jusqu'au fichier .HLP }
        OptVal := '';
        While Cmd <> '' Do
        Begin
          Arg1 := NextWord(Cmd);
          If (Pos('.HLP', UpStr(Arg1)) > 0) And (Cmd = '') Then
          Begin
            FileArg := Arg1;
            Break;
          End;
          If OptVal <> '' Then OptVal := OptVal + ' ';
          OptVal := OptVal + Arg1;
        End;
      End
      Else OptVal := NextWord(Cmd);
    End
    Else
    Begin
      If FileArg <> '' Then FileArg := FileArg + ' ';
      FileArg := FileArg + Arg1;
    End;
  Until False;
  { fichier.hlp>fenetre }
  If Pos('>', FileArg) > 0 Then FileArg := Copy(FileArg, 1, Pos('>', FileArg) - 1);
  PopOnly := Opt = 'P';

  WC.Style := 8; WC.WndProc := @WndProc; WC.ClsExtra := 0;
  WC.WndExtra := 0; WC.Inst := Inst; WC.Icon := 0; WC.Cursor := 0;
  ClsMain := 'MS_WINHELP'#0; ClsPop := 'WinHlpPopup'#0;
  ClsTop := 'WinHlpTopics'#0;
  WC.Brush := 0; WC.MenuName := Nil; WC.ClassName := @ClsMain[1];
  RegisterClassA(WC);
  WC.WndProc := @PopProc; WC.ClassName := @ClsPop[1];
  WC.Cursor := CurArrow;
  RegisterClassA(WC);
  WC.WndProc := @TopProc; WC.ClassName := @ClsTop[1];
  WC.Brush := BrFace;
  RegisterClassA(WC);

  Wnd := CreateWindowExA(0, @ClsMain[1], Z2(AppTitle),
                         WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, 120, 24,
                         480, 420, 0, 0, Inst, 0);
  BuildMenus;
  Layout;
  If Not PopOnly Then
  Begin
    ShowWindow(Wnd, 1);
    UpdateWindow(Wnd);
  End;

  Started := False;
  If FileArg = '' Then DoOpen
  Else If OpenHelp(FileArg) Then
  Begin
    Off := -1;
    If Opt = 'K' Then
    Begin
      NFound := 0;
      FindKeyword('|KWBTREE', '|KWDATA', OptVal);
      If NFound = 1 Then Off := FoundOff^[0]
      Else If NFound > 1 Then
      Begin
        If ContentsOff >= 0 Then ShowTopic(ContentsOff)
        Else If NTop > 0 Then ShowTopic(TopOff^[0]);
        ShowFound(L('Rubriques trouv'#130'es', 'Topics Found',
                    'Gefundene Themen', 'Argomenti trovati',
                    'Temas encontrados'));
        Started := True;
      End
      Else
      Begin
        If ContentsOff >= 0 Then ShowTopic(ContentsOff)
        Else If NTop > 0 Then ShowTopic(TopOff^[0]);
        OpenTopics(1);
        SetWindowTextA(TEdit, Z(OemStr(OptVal)));
        Started := True;
      End;
    End
    Else If (Opt = 'N') Or (Opt = 'P') Then Off := MapLookup(StrInt(OptVal))
    Else If Opt = 'I' Then Off := CtxLookup(HashCtx(OptVal));
    If PopOnly Then
    Begin
      If Off >= 0 Then ShowPopup(Off) Else PostMessageA(Wnd, WM_CLOSE, 0, 0);
      Started := True;
    End;
    If Not Started Then
    Begin
      If Off >= 0 Then ShowTopic(Off)
      Else
      Begin
        If ContentsOff >= 0 Then ShowTopic(ContentsOff)
        Else If NTop > 0 Then ShowTopic(TopOff^[0]);
        If (NCnt > 0) And (Opt = '') Then OpenTopics(0);
      End;
    End;
  End;
  While GetMessageA(M, 0, 0, 0) <> 0 Do
  Begin
    TranslateMessage(M);
    DispatchMessageA(M);
  End;
  ExitProcess(0);
End.
