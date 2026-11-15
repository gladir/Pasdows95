{ NETTEST.PAS - Essai de TCP/IP sur Pasdows 95 : Winsock 1.1 (TCP et UDP
  en boucle locale, select, mode non bloquant), ICMP.DLL (ping de la
  passerelle), DNS, et HTTP vers l'hote de l'emulateur (10.0.2.2:8000).

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 NETTEST.PAS NETTEST.EXE

  Les resultats s'affichent dans la fenetre et dans le journal du noyau
  (port serie). }

Program NetTest;

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
  TSockAddr = Record
    Family, Port : Word;
    Addr : LongInt;
    Zero : Array[0..7] Of Byte;
  End;
  TFdSet = Record
    Count : LongInt;
    Socks : Array[0..63] Of LongInt;
  End;
  TTimeVal = Record
    Sec, USec : LongInt;
  End;
  PLong = ^LongInt;
  TIcmpCreate = Function : LongInt; stdcall;
  TIcmpEcho = Function(H, Ip : LongInt; Data : Pointer; Size, Opt : LongInt;
    Reply : Pointer; RSize, Ms : LongInt) : LongInt; stdcall;

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
Procedure Sleep(Ms : LongInt); stdcall;
  external 'kernel32.dll' name 'Sleep';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
Function LoadLibraryA(N : PChar) : LongInt; stdcall;
  external 'kernel32.dll' name 'LoadLibraryA';
Function GetProcAddress(H : LongInt; N : PChar) : Pointer; stdcall;
  external 'kernel32.dll' name 'GetProcAddress';
Function WSAStartup(Ver : LongInt; Data : Pointer) : LongInt; stdcall;
  external 'wsock32.dll' name 'WSAStartup';
Function WSACleanup : LongInt; stdcall;
  external 'wsock32.dll' name 'WSACleanup';
Function WSAGetLastError : LongInt; stdcall;
  external 'wsock32.dll' name 'WSAGetLastError';
Function gethostname(Buf : PChar; N : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'gethostname';
Function gethostbyname(N : PChar) : LongInt; stdcall;
  external 'wsock32.dll' name 'gethostbyname';
Function inet_ntoa(A : LongInt) : PChar; stdcall;
  external 'wsock32.dll' name 'inet_ntoa';
Function inet_addr(S : PChar) : LongInt; stdcall;
  external 'wsock32.dll' name 'inet_addr';
Function htons(V : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'htons';
Function ntohs(V : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'ntohs';
Function socket(Af, Ty, Pr : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'socket';
Function bind(S : LongInt; Var A : TSockAddr; N : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'bind';
Function listen(S, N : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'listen';
Function ioctlsocket(S, Cmd : LongInt; Var Arg : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'ioctlsocket';
Function connect(S : LongInt; Var A : TSockAddr; N : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'connect';
Function accept(S : LongInt; Var A : TSockAddr; Var N : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'accept';
Function select(N : LongInt; R : Pointer; Var W : TFdSet; E : Pointer;
  Var T : TTimeVal) : LongInt; stdcall; external 'wsock32.dll' name 'select';
Function send(S : LongInt; Buf : Pointer; N, Fl : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'send';
Function recv(S : LongInt; Buf : Pointer; N, Fl : LongInt) : LongInt;
  stdcall; external 'wsock32.dll' name 'recv';
Function sendto(S : LongInt; Buf : Pointer; N, Fl : LongInt;
  Var A : TSockAddr; AN : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'sendto';
Function recvfrom(S : LongInt; Buf : Pointer; N, Fl : LongInt;
  Var A : TSockAddr; Var AN : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'recvfrom';
Function closesocket(S : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'closesocket';

Const
  AF_INET = 2;
  SOCK_STREAM = 1;
  SOCK_DGRAM = 2;
  FIONBIO = LongInt($8004667E);

Var
  Lines : Array[0..23] Of String[99];
  NL : LongInt;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Procedure Out(S : String);
Var T : String;
Begin
  If NL < 24 Then
  Begin
    Lines[NL] := Copy(S, 1, 99);
    Inc(NL);
  End;
  T := S + #0;
  OutputDebugStringA(@T[1]);
End;

Function WndProc(H, M, W, L : LongInt) : LongInt; stdcall;
Var P : TPaint; Dc, I : LongInt; T : String;
Begin
  WndProc := 0;
  Case M Of
    $000F :
    Begin
      Dc := BeginPaint(H, P);
      SetBkMode(Dc, 1);
      For I := 0 To NL - 1 Do
      Begin
        T := Lines[I] + #0;
        TextOutA(Dc, 8, 6 + I * 18, @T[1], Length(Lines[I]));
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

{ adresse IP (ordre reseau) -> texte }
Function IpStr(A : LongInt) : String;
Begin
  IpStr := StrPas(inet_ntoa(A));
End;

{ premiere adresse d'une structure hostent }
Function HostIp(He : LongInt) : LongInt;
Begin
  HostIp := PLong(PLong(PLong(He + 12)^)^)^;
End;

Function Ip(S : String) : LongInt;
Var T : String;
Begin
  T := S + #0;
  Ip := inet_addr(@T[1]);
End;

{ texte entre apostrophes }
Function Q(S : String) : String;
Begin
  Q := #39 + S + #39;
End;

Procedure Tests;
Var Wd : Array[0..399] Of Byte;
    Buf : Array[0..599] Of Char;
    T, Rq : String;
    A : TSockAddr;
    Ws : TFdSet;
    Tv : TTimeVal;
    N, Len, R, Srv, Cli, Con, U1, U2, He, Nb, Hi, Tot, I, Sum, T0,
      H : LongInt;
    First, Hdr : Boolean;
    Cf : TIcmpCreate;
    Se : TIcmpEcho;
Begin
  R := WSAStartup($101, @Wd[0]);
  Out('WSAStartup=' + IStr(R) + ' version ' + IStr(Wd[0]) + '.' +
      IStr(Wd[1]) + ' : ' + StrPas(@Wd[4]));
  gethostname(@Buf[0], 100);
  He := gethostbyname(@Buf[0]);
  T := 'gethostname : ' + StrPas(@Buf[0]) + ' = ';
  If He <> 0 Then T := T + IpStr(HostIp(He)) Else T := T + '?';
  Out(T);

  { TCP en boucle locale }
  Srv := socket(AF_INET, SOCK_STREAM, 0);
  FillChar(A, SizeOf(A), 0);
  A.Family := AF_INET; A.Port := htons(7000); A.Addr := Ip('127.0.0.1');
  R := bind(Srv, A, 16);
  R := R Or listen(Srv, 5);
  Cli := socket(AF_INET, SOCK_STREAM, 0);
  Nb := 1;
  ioctlsocket(Cli, FIONBIO, Nb);
  N := connect(Cli, A, 16);
  If N = -1 Then N := WSAGetLastError Else N := 0;
  Out('TCP local : bind/listen=' + IStr(R) + ' connect=' + IStr(N));
  Len := 16;
  Con := accept(Srv, A, Len);
  Ws.Count := 1; Ws.Socks[0] := Cli; Tv.Sec := 2; Tv.USec := 0;
  R := select(0, Nil, Ws, Nil, Tv);
  Out('accept=' + IStr(Ord(Con <> -1)) + ' select(ecriture)=' + IStr(R));
  T := 'Bonjour Pasdows';
  send(Cli, @T[1], 15, 0);
  N := recv(Con, @Buf[0], 100, 0);
  If N > 0 Then Buf[N] := #0 Else Buf[0] := #0;
  Out('recu par le serveur : ' + IStr(N) + ' octets ' + Q(StrPas(@Buf[0])) +
      ' de port ' + IStr(ntohs(A.Port)));
  T := 'Salut';
  send(Con, @T[1], 5, 0);
  closesocket(Con);
  Sleep(50);
  N := recv(Cli, @Buf[0], 100, 0);
  If N > 0 Then Buf[N] := #0 Else Buf[0] := #0;
  R := recv(Cli, @Buf[200], 100, 0);
  Out('recu par le client : ' + Q(StrPas(@Buf[0])) + ', puis recv=' +
      IStr(R) + ' (fin)');
  closesocket(Cli); closesocket(Srv);

  { UDP en boucle locale }
  U1 := socket(AF_INET, SOCK_DGRAM, 0); U2 := socket(AF_INET, SOCK_DGRAM, 0);
  A.Port := htons(7001); A.Addr := Ip('127.0.0.1');
  bind(U1, A, 16);
  T := 'datagramme';
  sendto(U2, @T[1], 10, 0, A, 16);
  Len := 16;
  N := recvfrom(U1, @Buf[0], 100, 0, A, Len);
  If N > 0 Then Buf[N] := #0 Else Buf[0] := #0;
  Out('UDP local : ' + IStr(N) + ' octets ' + Q(StrPas(@Buf[0])));
  closesocket(U1); closesocket(U2);

  { ICMP.DLL : ping de la passerelle }
  Hi := LoadLibraryA('ICMP.DLL');
  If Hi <> 0 Then
  Begin
    Cf := TIcmpCreate(GetProcAddress(Hi, 'IcmpCreateFile'));
    Se := TIcmpEcho(GetProcAddress(Hi, 'IcmpSendEcho'));
    If (@Cf <> Nil) And (@Se <> Nil) Then
    Begin
      H := Cf();
      T := 'abcdefgh';
      R := Se(H, Ip('10.0.2.2'), @T[1], 8, 0, @Buf[0], 600, 2000);
      If R <> 0 Then N := PLong(@Buf[8])^ Else N := 0;
      Out('IcmpSendEcho(10.0.2.2)=' + IStr(R) + ' temps=' + IStr(N) + ' ms');
    End
    Else Out('ICMP.DLL : GetProcAddress echoue');
  End;

  { DNS }
  He := gethostbyname('www.example.com');
  If He <> 0 Then Out('DNS www.example.com = ' + IpStr(HostIp(He)))
  Else Out('DNS www.example.com : erreur ' + IStr(WSAGetLastError));

  { HTTP vers l'hote (10.0.2.2:8000) }
  Cli := socket(AF_INET, SOCK_STREAM, 0);
  A.Port := htons(8000); A.Addr := Ip('10.0.2.2');
  If connect(Cli, A, 16) = 0 Then
  Begin
    Rq := 'GET /hello.txt HTTP/1.0'#13#10'Host: 10.0.2.2'#13#10#13#10;
    Tot := 0; First := True;
    send(Cli, @Rq[1], Length(Rq), 0);
    N := recv(Cli, @Buf[0], 512, 0);
    While N > 0 Do
    Begin
      If First Then
      Begin
        I := 0;
        While (I < N) And (Buf[I] <> #13) Do Inc(I);
        Buf[I] := #0;
        Out('HTTP : ' + StrPas(@Buf[0]));
        First := False;
      End;
      Tot := Tot + N;
      N := recv(Cli, @Buf[0], 512, 0);
    End;
    Out('HTTP : ' + IStr(Tot) + ' octets recus, fin=' + IStr(N));
  End
  Else Out('HTTP connect : erreur ' + IStr(WSAGetLastError));
  closesocket(Cli);
  { gros transfert : 300 000 octets, somme de controle }
  Cli := socket(AF_INET, SOCK_STREAM, 0);
  If connect(Cli, A, 16) = 0 Then
  Begin
    Rq := 'GET /big.bin HTTP/1.0'#13#10#13#10;
    Sum := 0; Tot := 0; Hdr := True; T0 := GetTickCount;
    send(Cli, @Rq[1], Length(Rq), 0);
    N := recv(Cli, @Buf[0], 512, 0);
    While N > 0 Do
    Begin
      I := 0;
      If Hdr Then
      Begin
        { sauter l'en-tete HTTP (fin : CRLFCRLF, dans le premier bloc) }
        I := 3;
        While (I < N) And Not ((Buf[I - 3] = #13) And (Buf[I - 2] = #10) And
              (Buf[I - 1] = #13) And (Buf[I] = #10)) Do Inc(I);
        Inc(I);
        Hdr := False;
      End;
      While I < N Do
      Begin
        Sum := Sum + Ord(Buf[I]); Inc(Tot); Inc(I);
      End;
      N := recv(Cli, @Buf[0], 512, 0);
    End;
    Out('big.bin : ' + IStr(Tot) + ' octets, somme ' + IStr(Sum) + ', ' +
        IStr(GetTickCount - T0) + ' ms');
  End;
  closesocket(Cli);
  WSACleanup;
  Out('Termine.');
End;

Var
  Wc : TWndClass;
  Wnd : LongInt;
  Msg : TMsg;

Begin
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.WndProc := @WndProc;
  Wc.Inst := GetModuleHandleA(0);
  Wc.Brush := 6;
  Wc.ClassName := 'NetTest';
  Wc.Cursor := LoadCursorA(0, 32512);
  RegisterClassA(Wc);
  Wnd := CreateWindowExA(0, 'NetTest', 'Essai TCP/IP', $10CF0000, 30, 30,
                         580, 330, 0, 0, Wc.Inst, 0);
  Tests;
  InvalidateRect(Wnd, 0, 1);
  While GetMessageA(Msg, 0, 0, 0) > 0 Do
  Begin
    TranslateMessage(Msg);
    DispatchMessageA(Msg);
  End;
  ExitProcess(0);
End.
