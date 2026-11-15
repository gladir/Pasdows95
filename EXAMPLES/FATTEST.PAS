{ FATTEST.PAS - Essai du systeme de fichiers de Pasdows 95 (FAT32, et
  aussi NTFS ou HPFS) : volume, espace libre, recherche, noms longs,
  lecture, ecriture, ajout, troncature, deplacement, suppression.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 FATTEST.PAS FATTEST.EXE

  Les fichiers lus (C:\JEUX, C:\Mes Documents...) sont ceux de l'image
  de disque d'essai ; les resultats s'affichent dans la fenetre et dans
  le journal du noyau (port serie). }

Program FatTest;

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
  TPaint = Record
    Hdc, Erase : LongInt;
    Rc : Array[0..3] Of LongInt;
    Rest : Array[0..39] Of Byte;
  End;
  TFind = Record
    Attr : LongInt;
    Times : Array[0..5] Of LongInt;
    SizeHi, SizeLo, R0, R1 : LongInt;
    Name : Array[0..259] Of Char;
    Alt : Array[0..13] Of Char;
  End;
  TBig = Array[0..299999] Of Byte;
  TQuad = Record
    Lo, Hi : LongInt;
  End;

Function RegisterClassA(Var C : TWndClass) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex : LongInt; Cls, Title : PChar; Style, X, Y, W,
  H, Parent, Menu, Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
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
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function BeginPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H : LongInt; Var P : TPaint) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function InvalidateRect(H, R, E : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'InvalidateRect';
Function LoadCursorA(I, C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function SetBkMode(Dc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
Function TextOutA(Dc, X, Y : LongInt; S : PChar; N : LongInt) : LongInt;
  stdcall; external 'gdi32.dll' name 'TextOutA';
Function GetModuleHandleA(N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Procedure OutputDebugStringA(S : PChar); stdcall;
  external 'kernel32.dll' name 'OutputDebugStringA';
Procedure ExitProcess(C : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GetVolumeInformationA(Root, Vol : PChar; VolN : LongInt;
  Var Ser, MaxC, Fl : LongInt; Fs : PChar; FsN : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetVolumeInformationA';
Function GetDiskFreeSpaceA(Root : PChar; Var Spc, Bps, Fr, Tot : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'GetDiskFreeSpaceA';
Function GetDiskFreeSpaceExA(Root : PChar; Var A, B, C : TQuad) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetDiskFreeSpaceExA';
Function GetLogicalDriveStringsA(N : LongInt; Buf : PChar) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetLogicalDriveStringsA';
Function FindFirstFileA(Pat : PChar; Var F : TFind) : LongInt; stdcall;
  external 'kernel32.dll' name 'FindFirstFileA';
Function FindNextFileA(H : LongInt; Var F : TFind) : LongInt; stdcall;
  external 'kernel32.dll' name 'FindNextFileA';
Function FindClose(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'FindClose';
Function CreateFileA(N : PChar; Acc, Sh, Sec, Disp, Fl, T : LongInt)
  : LongInt; stdcall; external 'kernel32.dll' name 'CreateFileA';
Function ReadFile(H : LongInt; Buf : Pointer; N : LongInt; Var Got : LongInt;
  Ov : LongInt) : LongInt; stdcall; external 'kernel32.dll' name 'ReadFile';
Function WriteFile(H : LongInt; Buf : Pointer; N : LongInt;
  Var Got : LongInt; Ov : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'WriteFile';
Function CloseHandle(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CloseHandle';
Function GetFileSize(H, Hi : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetFileSize';
Function SetFilePointer(H, D, Hi, M : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'SetFilePointer';
Function SetEndOfFile(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'SetEndOfFile';
Function CreateDirectoryA(N : PChar; Sec : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateDirectoryA';
Function RemoveDirectoryA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'RemoveDirectoryA';
Function MoveFileA(A, B : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'MoveFileA';
Function DeleteFileA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'DeleteFileA';
Function GetFileAttributesA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetFileAttributesA';

Const
  GENERIC_READ = LongInt($80000000);
  GENERIC_WRITE = $40000000;
  CREATE_ALWAYS = 2;
  OPEN_EXISTING = 3;
  OPEN_ALWAYS = 4;

Var
  Lines : Array[0..25] Of String[99];
  NL : LongInt;
  Big : ^TBig;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function HStr(V, N : LongInt) : String;
Const D : String[16] = '0123456789ABCDEF';
Var S : String; I : LongInt;
Begin
  S := '';
  For I := N - 1 DownTo 0 Do S := S + D[((V Shr (I * 4)) And 15) + 1];
  HStr := S;
End;

Procedure Out(S : String);
Var Z : String;
Begin
  If NL < 26 Then
  Begin
    Lines[NL] := Copy(S, 1, 99);
    Inc(NL);
  End;
  Z := S + #0;
  OutputDebugStringA(@Z[1]);
End;

Function WndProc(H, M, W, L : LongInt) : LongInt; stdcall;
Var P : TPaint; Dc, I : LongInt; Z : String;
Begin
  WndProc := 0;
  Case M Of
    $000F :
    Begin
      Dc := BeginPaint(H, P);
      SetBkMode(Dc, 1);
      For I := 0 To NL - 1 Do
      Begin
        Z := Lines[I] + #0;
        TextOutA(Dc, 8, 4 + I * 16, @Z[1], Length(Lines[I]));
      End;
      EndPaint(H, P);
    End;
    $0100 :
      If W = $1B Then DestroyWindow(H)
      Else WndProc := DefWindowProcA(H, M, W, L);
    $0002 : PostQuitMessage(0);
  Else
    WndProc := DefWindowProcA(H, M, W, L);
  End;
End;

Function Sum(Ofs, N : LongInt) : LongInt;
Var S, I : LongInt;
Begin
  S := 0;
  For I := 0 To N - 1 Do S := S + Big^[Ofs + I];
  Sum := S;
End;

{ chaine C (PChar) a l'adresse P }
Function CStr(P : Pointer) : String;
Begin
  CStr := StrPas(P);
End;

Function Z(S : String) : String;
Begin
  Z := S + #0;
End;

Procedure Tests;
Var T, Nm : String;
    Vol : Array[0..63] Of Char; Fs : Array[0..15] Of Char;
    Buf : Array[0..599] Of Char;
    Ser, Mc, Fl, Spc, Bps, Fr, Tot, N, I, H, F, Cnt : LongInt;
    A, B, C : TQuad;
    Fd : TFind;
    Q : Double;
Begin
  Nm := Z('C:\');
  GetVolumeInformationA(@Nm[1], @Vol[0], 64, Ser, Mc, Fl, @Fs[0], 16);
  Out('C: = ' + CStr(@Vol[0]) + ', ' + CStr(@Fs[0]) + ', serie ' +
      HStr(Ser, 8) + ', noms de ' + IStr(Mc) + ' car.');
  GetDiskFreeSpaceA(@Nm[1], Spc, Bps, Fr, Tot);
  GetDiskFreeSpaceExA(@Nm[1], A, B, C);
  Q := A.Hi * 4294967296.0 + A.Lo;
  If A.Lo < 0 Then Q := Q + 4294967296.0;
  Out('clusters ' + IStr(Spc) + ' x ' + IStr(Bps) + ' o : ' + IStr(Fr) +
      ' libres / ' + IStr(Tot) + ' ; Ex : ' + IStr(Trunc(Q / 1024)) +
      ' Ko libres');
  N := GetLogicalDriveStringsA(600, @Buf[0]);
  For I := 0 To N - 1 Do
    If Buf[I] = #0 Then Buf[I] := ' ';
  Buf[N] := #0;
  Out('lecteurs : ' + CStr(@Buf[0]));

  { liste de la racine }
  T := ''; Cnt := 0;
  Nm := Z('C:\*.*');
  H := FindFirstFileA(@Nm[1], Fd);
  If H <> -1 Then
  Begin
    Repeat
      If Length(T) < 200 Then
      Begin
        T := T + CStr(@Fd.Name[0]);
        If (Fd.Attr And 16) <> 0 Then T := T + '\ ' Else T := T + ' ';
      End;
      Inc(Cnt);
    Until FindNextFileA(H, Fd) = 0;
    FindClose(H);
  End;
  Out('C:\ :'); Out(T);
  Cnt := 0;
  Nm := Z('C:\JEUX\*.txt');
  H := FindFirstFileA(@Nm[1], Fd);
  If H <> -1 Then
  Begin
    Repeat
      Inc(Cnt);
    Until FindNextFileA(H, Fd) = 0;
    FindClose(H);
  End;
  Out('C:\JEUX\*.txt : ' + IStr(Cnt) + ' fichiers');

  { lecture d'un nom long }
  Nm := Z('C:\Mes Documents\Lettre a Marie.txt');
  F := CreateFileA(@Nm[1], GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  N := 0; ReadFile(F, @Buf[0], 100, N, 0); CloseHandle(F);
  Buf[N] := #0;
  For I := 0 To N - 1 Do
    If Buf[I] < ' ' Then Buf[I] := #0;
  Out('Lettre a Marie.txt : ''' + CStr(@Buf[0]) + '''');
  Nm := Z('C:\JEUX\Donnees du jeu.bin');
  F := CreateFileA(@Nm[1], GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  N := 0; ReadFile(F, @Big^[0], 300000, N, 0);
  Out('Donnees du jeu.bin : ' + IStr(N) + ' octets, taille ' +
      IStr(GetFileSize(F, 0)) + ', somme ' + IStr(Sum(0, N)));
  SetFilePointer(F, 100000, 0, 0); ReadFile(F, @Buf[0], 4, N, 0);
  Out('a 100000 : ' + HStr(Ord(Buf[0]), 2) + ' ' + HStr(Ord(Buf[1]), 2) +
      ' ' + HStr(Ord(Buf[2]), 2) + ' ' + HStr(Ord(Buf[3]), 2));
  CloseHandle(F);

  { ecriture }
  Nm := Z('C:\Nouveau dossier');
  Out('CreateDirectory(Nouveau dossier) = ' +
      IStr(CreateDirectoryA(@Nm[1], 0)));
  For I := 0 To 199999 Do Big^[I] := (I * 7 + I Div 1000) And 255;
  Nm := Z('C:\Nouveau dossier\Un fichier ecrit par Pasdows.dat');
  F := CreateFileA(@Nm[1], GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  WriteFile(F, @Big^[0], 150000, N, 0);
  WriteFile(F, @Big^[150000], 50000, N, 0);
  CloseHandle(F);
  Nm := Z('C:\NOUVEAU DOSSIER\un fichier ECRIT par pasdows.dat');
  F := CreateFileA(@Nm[1], GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  N := 0; ReadFile(F, @Big^[200000], 100000, N, 0);
  Out('relu (autre casse) : ' + IStr(N) + ' / ' + IStr(GetFileSize(F, 0)) +
      ' octets, somme ' + IStr(Sum(200000, 100000)) + ' = ' +
      IStr(Sum(0, 100000)));
  CloseHandle(F);
  Nm := Z('C:\ajout.txt');
  F := CreateFileA(@Nm[1], GENERIC_WRITE, 0, 0, OPEN_ALWAYS, 0, 0);
  SetFilePointer(F, 0, 0, 2);
  T := 'ligne 1'#13#10; WriteFile(F, @T[1], 9, N, 0); CloseHandle(F);
  F := CreateFileA(@Nm[1], GENERIC_WRITE, 0, 0, OPEN_ALWAYS, 0, 0);
  SetFilePointer(F, 0, 0, 2);
  T := 'ligne 2'#13#10; WriteFile(F, @T[1], 9, N, 0); CloseHandle(F);
  Nm := Z('C:\tronque.bin');
  F := CreateFileA(@Nm[1], GENERIC_WRITE, 0, 0, CREATE_ALWAYS, 0, 0);
  WriteFile(F, @Big^[0], 100000, N, 0);
  SetFilePointer(F, 1000, 0, 0); SetEndOfFile(F); CloseHandle(F);
  F := CreateFileA(@Nm[1], GENERIC_READ, 0, 0, OPEN_EXISTING, 0, 0);
  Out('tronque.bin : ' + IStr(GetFileSize(F, 0)) + ' octets');
  CloseHandle(F);
  T := Z('C:\JEUX\fichier numero 1.txt');
  Nm := Z('C:\Mes Documents\Renomme et deplace.txt');
  I := MoveFileA(@T[1], @Nm[1]);
  T := 'MoveFile = ' + IStr(I);
  Nm := Z('C:\JEUX\fichier numero 2.txt');
  T := T + ', DeleteFile = ' + IStr(DeleteFileA(@Nm[1]));
  Nm := Z('C:\Mes Documents\Sous dossier');
  T := T + ', RemoveDirectory = ' + IStr(RemoveDirectoryA(@Nm[1]));
  Out(T);
  Nm := Z('C:\Vide');
  CreateDirectoryA(@Nm[1], 0);
  I := RemoveDirectoryA(@Nm[1]);
  Nm := Z('C:\WINDOWS');
  Out('RemoveDirectory(Vide) = ' + IStr(I) + ' ; attributs C:\WINDOWS = ' +
      HStr(GetFileAttributesA(@Nm[1]), 2));
  Nm := Z('C:\');
  GetDiskFreeSpaceA(@Nm[1], Spc, Bps, Fr, Tot);
  Out('clusters libres : ' + IStr(Fr));
  Out('Termine.');
End;

Var
  Wc : TWndClass;
  Wnd : LongInt;
  Msg : TMsg;

Begin
  New(Big);
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.WndProc := @WndProc;
  Wc.Inst := GetModuleHandleA(0);
  Wc.Brush := 6;
  Wc.ClassName := 'FatTest';
  Wc.Cursor := LoadCursorA(0, 32512);
  RegisterClassA(Wc);
  Wnd := CreateWindowExA(0, 'FatTest', 'Essai FAT32', $10CF0000, 10, 10,
                         620, 440, 0, 0, Wc.Inst, 0);
  Tests;
  InvalidateRect(Wnd, 0, 1);
  While GetMessageA(Msg, 0, 0, 0) > 0 Do
  Begin
    TranslateMessage(Msg);
    DispatchMessageA(Msg);
  End;
  ExitProcess(0);
End.
