{ APPWIZ.PAS - Ajout/Suppression de programmes de Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 APPWIZ.PAS APPWIZ.EXE

  Comme la page Installation/Desinstallation de l'applet Ajout/
  Suppression de programmes du Panneau de configuration de Windows 95 :

  - le bouton Installer... cherche un programme d'installation
    (SETUP.EXE ou INSTALL.EXE) sur la disquette (A:) puis sur les
    CD-ROM (D: a H:) et le lance ;
  - la liste montre les logiciels que Windows sait supprimer : les
    sous-cles de HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\
    CurrentVersion\Uninstall qui ont les valeurs DisplayName et
    UninstallString (ecrites par les programmes d'installation) ;
  - le bouton Ajouter/Supprimer... (ou un double-clic) lance la commande
    UninstallString du logiciel choisi.

  La liste est relue toutes les deux secondes : un logiciel installe ou
  supprime y apparait ou en disparait des que son programme
  d'installation a mis a jour le registre.

  L'interface suit la variable d'environnement LANGUAGE (FR, EN, GR,
  IT, SP). }

Program AppWiz;

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
  TStartup = Record
    Cb : LongInt;
    Rest : Array[0..16] Of LongInt;
  End;
  TProcInfo = Record
    HProc, HThread, Pid, Tid : LongInt;
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
Function IsDialogMessageA(H : LongInt; Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'IsDialogMessageA';
Function TranslateMessage(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(Var M : TMsg) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(C : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function SendMessageA(H, M, W, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SendMessageA';
Function MessageBoxA(H : LongInt; T, C : PChar; F : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'MessageBoxA';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function AdjustWindowRect(Var R : TRect; Style, Menu : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'AdjustWindowRect';
Function EnableWindow(H, E : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnableWindow';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function SetTimer(H, Id, Ms, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetTimer';
Function KillTimer(H, Id : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'KillTimer';
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function CreateFontA(H, W, E, O, Wt, It, Un, So, Cs, Op, Cp, Q, Pf : LongInt;
  F : PChar) : LongInt; stdcall; external 'gdi32.dll' name 'CreateFontA';
Function GetModuleHandleA(P : Pointer) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetEnvironmentVariableA(N : PChar; B : Pointer; Sz : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetEnvironmentVariableA';
Function GetFileAttributesA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetFileAttributesA';
Function CreateProcessA(A, C : PChar; PA, TA : Pointer; I, F : LongInt;
  E, D : Pointer; Var SI : TStartup; Var PI : TProcInfo) : LongInt;
  stdcall; external 'kernel32.dll' name 'CreateProcessA';
Function GetExitCodeProcess(H : LongInt; Var C : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetExitCodeProcess';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function RegOpenKeyExA(K : LongInt; S : PChar; O, Sam : LongInt;
  Var R : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegEnumKeyA(K, N : LongInt; B : Pointer; L : LongInt) : LongInt;
  stdcall; external 'advapi32.dll' name 'RegEnumKeyA';
Function RegQueryValueExA(K : LongInt; N : PChar; R : Pointer;
  Var T : LongInt; D : Pointer; Var L : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';

Const
  WM_CREATE = 1; WM_DESTROY = 2; WM_CLOSE = $10; WM_SETFONT = $30;
  WM_COMMAND = $111; WM_TIMER = $113;
  WS_CHILD = $40000000; WS_VISIBLE = $10000000; WS_TABSTOP = $10000;
  WS_BORDER = $800000; WS_VSCROLL = $200000; WS_GROUP = $20000;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1; BS_GROUPBOX = 7;
  LBS_NOTIFY = 1; LBS_NOINTEGRALHEIGHT = $100;
  LB_ADDSTRING = $180; LB_RESETCONTENT = $184; LB_SETCURSEL = $186;
  LB_GETCURSEL = $188;
  LBN_SELCHANGE = 1; LBN_DBLCLK = 2;
  MB_OK = 0; MB_YESNO = 4; MB_ICONSTOP = $10; MB_ICONQUESTION = $20;
  MB_ICONINFO = $40; IDYES = 6;
  HKLM = LongInt($80000002);
  KEY_READ = $20019;
  STILL_ACTIVE = 259;
  cFace = $C0C0C0;
  { controles }
  idInstall = 10; idList = 11; idRemove = 12; idClose = 13;
  { zone client }
  CliW = 420; CliH = 372;
  MaxApp = 64;

Var
  Inst, Wnd, Lang, Font : LongInt;
  BtnInstall, LstApps, BtnRemove : LongInt;
  NApp : LongInt;
  AppName : Array[0..MaxApp - 1] Of String[80];
  AppCmd : Array[0..MaxApp - 1] Of String;
  Child : LongInt;                 { processus lance (0 si aucun) }
  Sig : String;                    { liste affichee (pour la relecture) }
  TmpZ, TmpZ2 : String;

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

{ Texte ANSI (registre, ecrit par les programmes Windows) -> page de
  codes 437, celle des programmes de Pasdows }
Function AnsiToOem(S : String) : String;
Const
  Hi : Array[192..255] Of Byte = (
    65, 65, 65, 65, 142, 143, 146, 128, 69, 144, 69, 69, 73, 73, 73, 73,
    68, 165, 79, 79, 79, 79, 153, 120, 79, 85, 85, 85, 154, 89, 80, 225,
    133, 160, 131, 97, 132, 134, 145, 135, 138, 130, 136, 137, 141, 161,
    140, 139, 100, 164, 149, 162, 147, 111, 148, 246, 111, 151, 163, 150,
    129, 121, 112, 152);
Var I, B : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do
  Begin
    B := Ord(S[I]);
    If B >= 192 Then B := Hi[B]
    Else If B = $AE Then B := $9E          { (R) }
    Else If B = $99 Then B := $9F          { (TM) }
    Else If B = $A9 Then B := $A9          { (C) }
    Else If B = $A0 Then B := 32
    Else If B >= 128 Then B := Ord('?');
    R := R + Chr(B);
  End;
  AnsiToOem := R;
End;

Function UpStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := UpCase(S[I]);
  UpStr := S;
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

Function Msg(T : String; F : LongInt) : LongInt;
Var C : String;
Begin
  C := L('Ajout/Suppression de programmes', 'Add/Remove Programs',
         'Software', 'Installazione applicazioni',
         'Agregar o quitar programas') + #0;
  TmpZ := T + #0;
  Msg := MessageBoxA(Wnd, @TmpZ[1], @C[1], F);
End;

{ ------------------------------------------------ lecture du registre }

Function RegStr(K : LongInt; N : String) : String;
Var B : Array[0..259] Of Char; T, Ln : LongInt; Nz : String;
Begin
  RegStr := '';
  Nz := N + #0;
  Ln := 256; T := 0;
  B[0] := #0;
  If RegQueryValueExA(K, @Nz[1], Nil, T, @B, Ln) <> 0 Then Exit;
  If (T <> 1) And (T <> 2) Then Exit;
  B[256] := #0;
  RegStr := CStr(LongInt(@B));
End;

{ Lire la cle Uninstall : NApp logiciels tries par nom }
Procedure ReadApps;
Var K, S, I, J : LongInt; B : Array[0..259] Of Char; Sub, N, C : String;
Begin
  NApp := 0;
  If RegOpenKeyExA(HKLM, Z('Software\Microsoft\Windows\CurrentVersion\' +
                   'Uninstall'), 0, KEY_READ, K) <> 0 Then Exit;
  I := 0;
  While (NApp < MaxApp) And (RegEnumKeyA(K, I, @B, 256) = 0) Do
  Begin
    Inc(I);
    Sub := CStr(LongInt(@B)) + #0;
    If RegOpenKeyExA(K, @Sub[1], 0, KEY_READ, S) = 0 Then
    Begin
      N := AnsiToOem(RegStr(S, 'DisplayName'));
      C := RegStr(S, 'UninstallString');
      RegCloseKey(S);
      If (N <> '') And (C <> '') Then
      Begin
        { insertion triee (sans tenir compte de la casse) }
        J := NApp;
        While (J > 0) And (UpStr(AppName[J - 1]) > UpStr(N)) Do
        Begin
          AppName[J] := AppName[J - 1];
          AppCmd[J] := AppCmd[J - 1];
          Dec(J);
        End;
        AppName[J] := Copy(N, 1, 80);
        AppCmd[J] := C;
        Inc(NApp);
      End;
    End;
  End;
  RegCloseKey(K);
End;

Procedure UpdButtons;
Begin
  EnableWindow(BtnRemove,
               Ord(SendMessageA(LstApps, LB_GETCURSEL, 0, 0) >= 0));
End;

{ Remplir la liste ; garder le logiciel choisi s'il y est encore }
Procedure FillList(Force : Boolean);
Var I, Sel : LongInt; S, Old : String;
Begin
  ReadApps;
  S := '';
  For I := 0 To NApp - 1 Do S := Copy(S + AppName[I] + '|', 1, 255);
  S := Copy(S + Chr(NApp), 1, 255);
  If Not Force And (S = Sig) Then Exit;
  Sig := S;
  Old := '';
  Sel := SendMessageA(LstApps, LB_GETCURSEL, 0, 0);
  If (Sel >= 0) And (Sel < MaxApp) Then Old := AppName[Sel];
  SendMessageA(LstApps, LB_RESETCONTENT, 0, 0);
  Sel := -1;
  For I := 0 To NApp - 1 Do
  Begin
    SendMessageA(LstApps, LB_ADDSTRING, 0, LongInt(Z(AppName[I])));
    If (Old <> '') And (AppName[I] = Old) Then Sel := I;
  End;
  SendMessageA(LstApps, LB_SETCURSEL, Sel, 0);
  UpdButtons;
End;

{ ----------------------------------------------------------- actions }

Function Launch(Cmd : String) : Boolean;
Var SI : TStartup; PI : TProcInfo; I : LongInt;
Begin
  SI.Cb := 68;
  For I := 0 To 16 Do SI.Rest[I] := 0;
  PI.HProc := 0;
  Launch := CreateProcessA(Nil, Z(Cmd), Nil, Nil, 0, 0, Nil, Nil, SI,
                           PI) <> 0;
  If PI.HProc <> 0 Then
  Begin
    If Child <> 0 Then CloseHandle(Child);
    Child := PI.HProc;
    If PI.HThread <> 0 Then CloseHandle(PI.HThread);
  End;
End;

Function Exists(F : String) : Boolean;
Var A : LongInt;
Begin
  A := GetFileAttributesA(Z2(F));
  Exists := (A <> -1) And ((A And $10) = 0);
End;

{ Installer... : programme d'installation de la disquette ou du CD-ROM }
Procedure DoInstall;
Var D : Char; F : String;
Begin
  F := '';
  For D := 'A' To 'H' Do
    If (F = '') And (D <> 'B') And (D <> 'C') Then
    Begin
      If Exists(D + ':\SETUP.EXE') Then F := D + ':\SETUP.EXE'
      Else If Exists(D + ':\INSTALL.EXE') Then F := D + ':\INSTALL.EXE';
    End;
  If F = '' Then
  Begin
    Msg(L('Aucun programme d''installation n''a '#130't'#130' trouv'#130 +
          ' sur la disquette ou le CD-ROM.'#13#10#13#10'Ins'#130'rez la ' +
          'premi'#138're disquette ou le CD-ROM du logiciel, puis ' +
          'cliquez de nouveau sur Installer.',
          'Windows was unable to locate an installation program on the ' +
          'floppy disk or CD-ROM.'#13#10#13#10'Insert the product''s first ' +
          'installation floppy disk or CD-ROM, and then click Install ' +
          'again.',
          'Es wurde kein Installationsprogramm auf der Diskette oder ' +
          'der CD-ROM gefunden.',
          'Impossibile trovare un programma di installazione sul ' +
          'disco floppy o sul CD-ROM.',
          'No se ha encontrado un programa de instalaci'#162'n en el ' +
          'disquete o en el CD-ROM.'), MB_OK Or MB_ICONINFO);
    Exit;
  End;
  If Msg(L('Pasdows ex'#130'cutera le programme d''installation ' +
           'suivant :', 'Windows will run the following installation ' +
           'program:', 'Pasdows f'#129'hrt folgendes ' +
           'Installationsprogramm aus:', 'Pasdows eseguir'#133' il ' +
           'seguente programma di installazione:', 'Pasdows ejecutar'#160 +
           ' el siguiente programa de instalaci'#162'n:') + #13#10#13#10 + F +
           #13#10#13#10 + L('Voulez-vous continuer ?', 'Do you want to ' +
           'continue?', 'Fortfahren?', 'Continuare?', ''#168'Desea ' +
           'continuar?'), MB_YESNO Or MB_ICONQUESTION) <> IDYES Then Exit;
  If Not Launch(F) Then
    Msg(L('Impossible de lancer ', 'Cannot run ', 'Kann nicht ' +
          'ausgef'#129'hrt werden: ', 'Impossibile eseguire ',
          'No se puede ejecutar ') + F, MB_OK Or MB_ICONSTOP);
End;

{ Ajouter/Supprimer... : programme de desinstallation du logiciel }
Procedure DoRemove;
Var I : LongInt;
Begin
  I := SendMessageA(LstApps, LB_GETCURSEL, 0, 0);
  If (I < 0) Or (I >= NApp) Then Exit;
  If Not Launch(AppCmd[I]) Then
    Msg(L('Impossible de lancer le programme de d'#130'sinstallation de ',
          'Unable to run the uninstall program of ', 'Das ' +
          'Deinstallationsprogramm kann nicht ausgef'#129'hrt werden: ',
          'Impossibile eseguire il programma di disinstallazione di ',
          'No se puede ejecutar el programa de desinstalaci'#162'n de ') +
        AppName[I] + '.'#13#10#13#10 + AppCmd[I], MB_OK Or MB_ICONSTOP);
End;

{ ------------------------------------------------------------ fenetre }

Function Ctl(Cls, Txt : String; Style, X, Y, W, H, Id : LongInt) : LongInt;
Var C : LongInt;
Begin
  TmpZ2 := Cls + #0;
  C := CreateWindowExA(0, @TmpZ2[1], Z(Txt), WS_CHILD Or WS_VISIBLE Or
                       Style, X, Y, W, H, Wnd, Id, Inst, 0);
  SendMessageA(C, WM_SETFONT, Font, 0);
  Ctl := C;
End;

Procedure MakeControls;
Var Ex : LongInt;
Begin
  Ctl('BUTTON', L('Installation/D'#130'sinstallation', 'Install/' +
      'Uninstall', 'Installieren/Deinstallieren', 'Installa/' +
      'Rimuovi', 'Instalar o desinstalar'), BS_GROUPBOX, 8, 6,
      CliW - 16, CliH - 52, 0);
  Ctl('STATIC', L('Pour installer un nouveau programme '#133' partir ' +
      'd''une disquette ou d''un CD-ROM, cliquez sur Installer.',
      'To install a new program from a floppy disk or CD-ROM drive, ' +
      'click Install.', 'Klicken Sie auf "Installieren", um ein neues ' +
      'Programm von Diskette oder CD-ROM zu installieren.', 'Per ' +
      'installare un nuovo programma da disco floppy o CD-ROM, ' +
      'scegliere Installa.', 'Para instalar un programa nuevo desde ' +
      'un disquete o CD-ROM, haga clic en Instalar.'), 0, 20, 28,
      CliW - 40, 30, 0);
  BtnInstall := Ctl('BUTTON', L('&Installer...', '&Install...',
      '&Installieren...', '&Installa...', '&Instalar...'),
      WS_TABSTOP Or WS_GROUP Or BS_PUSHBUTTON, CliW - 120, 64, 96, 23,
      idInstall);
  Ctl('STATIC', L('Les logiciels suivants peuvent '#136'tre supprim'#130 +
      's automatiquement par Pasdows. Pour supprimer un programme ou ' +
      'modifier ses composants install'#130's, s'#130'lectionnez-le ' +
      'dans la liste et cliquez sur Ajouter/Supprimer.',
      'The following software can be automatically removed by ' +
      'Windows. To remove a program or to modify its installed ' +
      'components, select it from the list and click Add/Remove.',
      'Folgende Software kann automatisch entfernt werden. W'#132'hlen ' +
      'Sie ein Programm aus und klicken Sie auf Hinzuf'#129'gen/' +
      'Entfernen.', 'Il seguente software pu'#149' essere rimosso ' +
      'automaticamente. Selezionare un programma e scegliere ' +
      'Aggiungi/Rimuovi.', 'Pasdows puede quitar autom'#160'ticamente ' +
      'el software siguiente. Seleccione un programa y haga clic en ' +
      'Agregar o quitar.'), 0, 20, 96, CliW - 40, 52, 0);
  Ex := $200;                                  { WS_EX_CLIENTEDGE }
  TmpZ2 := 'LISTBOX'#0;
  LstApps := CreateWindowExA(Ex, @TmpZ2[1], Z(''), WS_CHILD Or WS_VISIBLE
                             Or WS_TABSTOP Or WS_GROUP Or WS_BORDER Or
                             WS_VSCROLL Or LBS_NOTIFY Or
                             LBS_NOINTEGRALHEIGHT, 20, 150, CliW - 40,
                             128, Wnd, idList, Inst, 0);
  SendMessageA(LstApps, WM_SETFONT, Font, 0);
  BtnRemove := Ctl('BUTTON', L('Ajouter/&Supprimer...', 'Add/&Remove...',
      'Hinzuf'#129'gen/&Entfernen...', 'Aggiungi/&Rimuovi...',
      'Agregar o &quitar...'), WS_TABSTOP Or WS_GROUP Or BS_PUSHBUTTON,
      CliW - 144, 286, 120, 23, idRemove);
  Ctl('BUTTON', L('Fermer', 'Close', 'Schlie'#225'en', 'Chiudi',
      'Cerrar'), WS_TABSTOP Or WS_GROUP Or BS_DEFPUSHBUTTON, CliW - 92,
      CliH - 34, 84, 23, idClose);
End;

Function WndProc(H, M, W, LP : LongInt) : LongInt; stdcall;
Var C : LongInt;
Begin
  WndProc := 0;
  Case M Of
    WM_COMMAND :
      Case W And $FFFF Of
        idInstall : DoInstall;
        idRemove : DoRemove;
        idClose, 2 : DestroyWindow(H);
        idList :
          Case (W Shr 16) And $FFFF Of
            LBN_SELCHANGE : UpdButtons;
            LBN_DBLCLK : DoRemove;
          End;
      End;
    WM_TIMER :
      Begin
        { programme lance termine : relire la liste aussitot }
        If Child <> 0 Then
        Begin
          C := 0;
          If (GetExitCodeProcess(Child, C) = 0) Or (C <> STILL_ACTIVE) Then
          Begin
            CloseHandle(Child);
            Child := 0;
          End;
        End;
        FillList(False);
      End;
    WM_DESTROY :
      Begin
        KillTimer(H, 1);
        PostQuitMessage(0);
      End;
  Else
    WndProc := DefWindowProcA(H, M, W, LP);
  End;
End;

Var
  C : TWndClass;
  M : TMsg;
  R : TRect;
  Cls, Ttl, Fn : String;
  Style : LongInt;

Begin
  LangInit;
  Inst := GetModuleHandleA(Nil);
  Child := 0; Sig := '';
  Fn := 'MS Sans Serif'#0;
  Font := CreateFontA(-11, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0, @Fn[1]);
  Cls := 'PasdowsAppWiz'#0;
  C.Style := 0; C.WndProc := @WndProc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, 32512);
  C.Brush := CreateSolidBrush(cFace); C.MenuName := Nil;
  C.ClassName := @Cls[1];
  RegisterClassA(C);
  Ttl := L('Propri'#130't'#130's de Ajout/Suppression de programmes',
           'Add/Remove Programs Properties', 'Eigenschaften von Software',
           'Propriet'#133' - Installazione applicazioni',
           'Propiedades de Agregar o quitar programas') + #0;
  { fenetre de taille fixe : titre et menu systeme }
  Style := $00C80000 Or $10000000;
  R.L := 0; R.T := 0; R.R := CliW; R.B := CliH;
  AdjustWindowRect(R, Style, 0);
  Wnd := CreateWindowExA(0, @Cls[1], @Ttl[1], Style, 120, 24, R.R - R.L,
                         R.B - R.T, 0, 0, Inst, 0);
  MakeControls;
  FillList(True);
  SetTimer(Wnd, 1, 2000, 0);
  ShowWindow(Wnd, 1);
  UpdateWindow(Wnd);
  SetFocus(LstApps);
  While GetMessageA(M, 0, 0, 0) <> 0 Do
    If IsDialogMessageA(Wnd, M) = 0 Then
    Begin
      TranslateMessage(M);
      DispatchMessageA(M);
    End;
  ExitProcess(0);
End.
