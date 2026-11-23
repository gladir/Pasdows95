{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: Pasdows 95 (WPC -CW32), Windows 95)
}

Program PING;

{ PING : envoie des demandes d'echo ICMP a un ordinateur, comme la
  commande PING de Windows 95 (ICMP.DLL : IcmpSendEcho, WSOCK32 :
  gethostbyname). }

{$R-}

Uses DOS;

Function IcmpCreateFile:LongInt;stdcall;
 external 'icmp.dll' name 'IcmpCreateFile';
Function IcmpCloseHandle(H:LongInt):LongInt;stdcall;
 external 'icmp.dll' name 'IcmpCloseHandle';
Function IcmpSendEcho(H,Dst:LongInt;Req:Pointer;ReqSize:LongInt;
 Opts:Pointer;Reply:Pointer;ReplySize,Timeout:LongInt):LongInt;stdcall;
 external 'icmp.dll' name 'IcmpSendEcho';
Function WSAStartup(V:LongInt;D:Pointer):LongInt;stdcall;
 external 'wsock32.dll' name 'WSAStartup';
Function inet_addr(P:Pointer):LongInt;stdcall;
 external 'wsock32.dll' name 'inet_addr';
Function gethostbyname(P:Pointer):LongInt;stdcall;
 external 'wsock32.dll' name 'gethostbyname';
Procedure Sleep(Ms:LongInt);stdcall;
 external 'kernel32.dll' name 'Sleep';

Type
 PLong=^LongInt;

Var
 Language:(_French,_English,_Germany);
 TmpLanguage,Host,S:String;
 Count,Size,Timeout,I,K,Err:LongInt;
 Forever:Boolean;
 Ip,H,R,Sent,Recv,Mn,Mx,Sum,Rtt:LongInt;
 Name:Array[0..255]of Char;
 WsaData:Array[0..399]of Byte;
 Req:Array[0..1023]of Byte;
 Reply:Array[0..1499]of Byte;

Function StrToUpper(S:String):String;
Var
 J:Integer;
Begin
 For J:=1 to Length(S)do S[J]:=UpCase(S[J]);
 StrToUpper:=S;
End;

Function IpStr(V:LongInt):String;
Var
 A,B,C,D:String;
Begin
 Str(V and $FF,A);Str((V shr 8)and $FF,B);
 Str((V shr 16)and $FF,C);Str((V shr 24)and $FF,D);
 IpStr:=A+'.'+B+'.'+C+'.'+D;
End;

Procedure ShowHelp;Begin
 Case Language of
  _English:Begin
   WriteLn('Usage: PING [-t] [-n count] [-l size] [-w timeout] host');
   WriteLn;
   WriteLn(' -t          Ping the specified host until stopped (Ctrl+C).');
   WriteLn(' -n count    Number of echo requests to send (4).');
   WriteLn(' -l size     Send buffer size (32 bytes).');
   WriteLn(' -w timeout  Timeout in milliseconds to wait for each reply.');
  End;
  Else Begin
   WriteLn('PING : Cette commande permet de v',#130,'rifier qu''un ordinateur ',
           'r',#130,'pond sur le r',#130,'seau.');
   WriteLn;
   WriteLn('Syntaxe : PING [-t] [-n nombre] [-l taille] [-w d',#130,'lai] h',
           #147,'te');
   WriteLn;
   WriteLn(' -t          Envoie des requ',#136,'tes jusqu''',#133,' Ctrl+C.');
   WriteLn(' -n nombre   Nombre de requ',#136,'tes d''',#130,'cho (4).');
   WriteLn(' -l taille   Taille des donn',#130,'es (32 octets).');
   WriteLn(' -w d',#130,'lai     D',#130,'lai d''attente de chaque r',#130,
           'ponse (ms).');
  End;
 End;
End;

Function Resolve(Const N:String):LongInt;
Var
 P:LongInt;
Begin
 For K:=1 to Length(N)do Name[K-1]:=N[K];
 Name[Length(N)]:=#0;
 P:=inet_addr(@Name);
 If(P<>-1)or(N='255.255.255.255')Then Begin
  Resolve:=P;
  Exit;
 End;
 P:=gethostbyname(@Name);
 If P=0Then Begin
  Resolve:=0;
  Exit;
 End;
 { hostent : h_addr_list en +12 }
 P:=PLong(P+12)^;
 P:=PLong(P)^;
 Resolve:=PLong(P)^;
End;

BEGIN
 Language:=_French;
 TmpLanguage:=GetEnv('LANGUAGE');
 If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English;
 Count:=4;Size:=32;Timeout:=4000;Forever:=False;Host:='';
 I:=1;
 While I<=ParamCount do Begin
  S:=StrToUpper(ParamStr(I));
  If(S='/?')or(S='-?')or(S='/H')Then Begin
   ShowHelp;
   Halt(0);
  End
   Else
  If(S='-T')or(S='/T')Then Forever:=True Else
  If((S='-N')or(S='/N'))and(I<ParamCount)Then Begin
   Inc(I);Val(ParamStr(I),Count,Err);
  End
   Else
  If((S='-L')or(S='/L'))and(I<ParamCount)Then Begin
   Inc(I);Val(ParamStr(I),Size,Err);
   If(Size<0)or(Size>1024)Then Size:=32;
  End
   Else
  If((S='-W')or(S='/W'))and(I<ParamCount)Then Begin
   Inc(I);Val(ParamStr(I),Timeout,Err);
  End
   Else
  Host:=ParamStr(I);
  Inc(I);
 End;
 If Host=''Then Begin
  ShowHelp;
  Halt(1);
 End;
 WSAStartup($101,@WsaData);
 Ip:=Resolve(Host);
 If Ip=0Then Begin
  Case Language of
   _English:WriteLn('Unknown host ',Host,'.');
   Else WriteLn('H',#147,'te inconnu ',Host,'.');
  End;
  Halt(1);
 End;
 For K:=0 to Size-1 do Req[K]:=Ord('a')+(K mod 23);
 WriteLn;
 Case Language of
  _English:WriteLn('Pinging ',Host,' [',IpStr(Ip),'] with ',Size,
                   ' bytes of data:');
  Else WriteLn('Envoi d''une requ',#136,'te ''Ping''  ',Host,' [',IpStr(Ip),
               '] avec ',Size,' octets de donn',#130,'es :');
 End;
 WriteLn;
 H:=IcmpCreateFile;
 Sent:=0;Recv:=0;Mn:=MaxLongInt;Mx:=0;Sum:=0;
 While Forever or(Sent<Count)do Begin
  Inc(Sent);
  FillChar(Reply,SizeOf(Reply),0);
  R:=IcmpSendEcho(H,Ip,@Req,Size,Nil,@Reply,SizeOf(Reply),Timeout);
  If R<>0Then Begin
   Inc(Recv);
   Rtt:=PLong(@Reply[8])^;
   If Rtt<Mn Then Mn:=Rtt;
   If Rtt>Mx Then Mx:=Rtt;
   Sum:=Sum+Rtt;
   Case Language of
    _English:Write('Reply from ',IpStr(PLong(@Reply[0])^),': bytes=',Size);
    Else Write('R',#130,'ponse de ',IpStr(PLong(@Reply[0])^),' : octets=',
               Size);
   End;
   If Rtt<1Then Begin
    Case Language of
     _English:Write(' time<1ms');
     Else Write(' temps<1 ms');
    End;
   End
    Else
   Begin
    Case Language of
     _English:Write(' time=',Rtt,'ms');
     Else Write(' temps=',Rtt,' ms');
    End;
   End;
   WriteLn(' TTL=',Reply[20]);
   If Forever or(Sent<Count)Then Sleep(1000);
  End
   Else
  Case Language of
   _English:WriteLn('Request timed out.');
   Else WriteLn('D',#130,'lai d''attente de la demande d',#130,'pass',#130,'.');
  End;
 End;
 IcmpCloseHandle(H);
 WriteLn;
 Case Language of
  _English:Begin
   WriteLn('Ping statistics for ',IpStr(Ip),':');
   WriteLn('    Packets: Sent = ',Sent,', Received = ',Recv,', Lost = ',
           Sent-Recv,' (',((Sent-Recv)*100)div Sent,'% loss),');
  End;
  Else Begin
   WriteLn('Statistiques Ping pour ',IpStr(Ip),' :');
   WriteLn('    Paquets : envoy',#130,'s = ',Sent,', re',#135,'us = ',Recv,
           ', perdus = ',Sent-Recv,' (perte ',((Sent-Recv)*100)div Sent,'%),');
  End;
 End;
 If Recv>0Then Begin
  Case Language of
   _English:Begin
    WriteLn('Approximate round trip times in milli-seconds:');
    WriteLn('    Minimum = ',Mn,'ms, Maximum = ',Mx,'ms, Average = ',
            Sum div Recv,'ms');
   End;
   Else Begin
    WriteLn('Dur',#130,'e approximative des boucles en millisecondes :');
    WriteLn('    Minimum = ',Mn,' ms, Maximum = ',Mx,' ms, Moyenne = ',
            Sum div Recv,' ms');
   End;
  End;
 End;
 If Recv=0Then Halt(1);
END.
