{ HTTPGET.PAS - Telecharge une URL (http:// ou https://) avec WININET.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 HTTPGET.PAS HTTPGET.EXE

  Utilisation, dans l'Invite MS-DOS de Pasdows 95 (ou sous Windows) :
     HTTPGET https://serveur/chemin/fichier.bin C:\FICHIER.BIN
     HTTPGET http://serveur/page.html            (affiche la page)

  Sous Pasdows 95, WININET.DLL est fournie par le noyau VMM32 : client
  HTTP/1.1 (redirections, Content-Length, chunked) et TLS 1.2 ecrits en
  Pascal (ECDHE x25519, AES-128-GCM, SHA-256). }

Program HttpGet;

Function InternetOpenA(Agent : PChar; Access : LongInt; Proxy,
  Bypass : PChar; Flags : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetOpenA';
Function InternetOpenUrlA(H : LongInt; Url, Hdr : PChar; HdrLen, Flags,
  Ctx : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetOpenUrlA';
Function InternetReadFile(H : LongInt; Buf : Pointer; N : LongInt;
  Var Got : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetReadFile';
Function HttpQueryInfoA(H, Info : LongInt; Buf : Pointer; Var Len : LongInt;
  Idx : Pointer) : LongInt; stdcall;
  external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetCloseHandle(H : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetCloseHandle';
Function GetLastError : LongInt; stdcall;
  external 'kernel32.dll' name 'GetLastError';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';

Const
  HTTP_QUERY_STATUS_CODE = 19;
  HTTP_QUERY_CONTENT_LENGTH = 5;
  HTTP_QUERY_FLAG_NUMBER = $20000000;
  INTERNET_FLAG_RELOAD = LongInt($80000000);

Var
  Url, Dest : String;
  Net, Req, Got, Status, Size, Len, Total, T0, T, I : LongInt;
  Buf : Array[0..16383] Of Byte;
  F : File;
  ToFile : Boolean;

Begin
  If ParamCount < 1 Then
  Begin
    WriteLn('HTTPGET url [fichier]');
    WriteLn('  telecharge url (http:// ou https://) dans fichier,');
    WriteLn('  ou l''affiche si aucun fichier n''est donne.');
    Halt(1);
  End;
  Url := ParamStr(1) + #0;
  ToFile := ParamCount >= 2;
  Net := InternetOpenA('HTTPGET/1.0', 0, Nil, Nil, 0);
  If Net = 0 Then
  Begin
    WriteLn('InternetOpen a echoue (', GetLastError, ')'); Halt(2);
  End;
  T0 := GetTickCount;
  Req := InternetOpenUrlA(Net, @Url[1], Nil, 0, INTERNET_FLAG_RELOAD, 0);
  If Req = 0 Then
  Begin
    WriteLn('Connexion impossible (erreur ', GetLastError, ')');
    InternetCloseHandle(Net);
    Halt(3);
  End;
  Len := 4; Status := 0;
  HttpQueryInfoA(Req, HTTP_QUERY_STATUS_CODE Or HTTP_QUERY_FLAG_NUMBER,
                 @Status, Len, Nil);
  Len := 4; Size := -1;
  If HttpQueryInfoA(Req, HTTP_QUERY_CONTENT_LENGTH Or
                    HTTP_QUERY_FLAG_NUMBER, @Size, Len, Nil) = 0 Then
    Size := -1;
  If ToFile Then
  Begin
    WriteLn('HTTP ', Status, ', taille ', Size, ' octets');
    Dest := ParamStr(2);
    Assign(F, Dest);
    {$I-} Rewrite(F, 1); {$I+}
    If IOResult <> 0 Then
    Begin
      WriteLn('Impossible de creer ', Dest); Halt(4);
    End;
  End;
  Total := 0;
  Repeat
    Got := 0;
    If InternetReadFile(Req, @Buf[0], SizeOf(Buf), Got) = 0 Then Got := 0;
    If Got > 0 Then
    Begin
      If ToFile Then
      Begin
        BlockWrite(F, Buf[0], Got);
        If (Total Div 262144) <> ((Total + Got) Div 262144) Then
          Write(#13, (Total + Got) Div 1024, ' Ko');
      End
      Else
        For I := 0 To Got - 1 Do Write(Chr(Buf[I]));
      Total := Total + Got;
    End;
  Until Got = 0;
  InternetCloseHandle(Req);
  InternetCloseHandle(Net);
  If ToFile Then
  Begin
    Close(F);
    T := GetTickCount - T0;
    If T <= 0 Then T := 1;
    WriteLn(#13, Total, ' octets en ', T Div 1000, ',',
            (T Mod 1000) Div 100, ' s (', (Total Div T), ' Ko/s)');
  End;
End.
