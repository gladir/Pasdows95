{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: Pasdows 95 (WPC -CW32), Windows)
}

Program CURL;

{ CURL : transfere une URL (http:// ou https://), comme la commande curl
  de Windows 10, avec WININET (TLS 1.2 du noyau de Pasdows).

  Options : -o fichier, -O (nom distant), -I (en-tetes seulement, HEAD),
  -i (en-tetes et contenu), -X methode, -d donnees (POST), -H en-tete,
  -A agent, -L (suivre les redirections), -s (silencieux), -v (details),
  -f (echec silencieux sur une erreur HTTP), --version, -h. }

{$R-}

Uses DOS;

Function InternetOpenA(Agent:PChar;Access:LongInt;Proxy,Bypass:PChar;
 Flags:LongInt):LongInt;stdcall;external 'wininet.dll' name 'InternetOpenA';
Function InternetConnectA(H:LongInt;Srv:PChar;Port:LongInt;User,Pwd:PChar;
 Svc,Flags,Ctx:LongInt):LongInt;stdcall;
 external 'wininet.dll' name 'InternetConnectA';
Function HttpOpenRequestA(H:LongInt;Verb,Obj,Ver,Ref:PChar;Acc:Pointer;
 Flags,Ctx:LongInt):LongInt;stdcall;
 external 'wininet.dll' name 'HttpOpenRequestA';
Function HttpSendRequestA(H:LongInt;Hdr:PChar;HdrLen:LongInt;Opt:Pointer;
 OptLen:LongInt):LongInt;stdcall;
 external 'wininet.dll' name 'HttpSendRequestA';
Function HttpQueryInfoA(H,Info:LongInt;Buf:Pointer;Var Len:LongInt;
 Idx:Pointer):LongInt;stdcall;external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetReadFile(H:LongInt;Buf:Pointer;N:LongInt;
 Var Got:LongInt):LongInt;stdcall;
 external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H:LongInt):LongInt;stdcall;
 external 'wininet.dll' name 'InternetCloseHandle';
Function GetLastError:LongInt;stdcall;
 external 'kernel32.dll' name 'GetLastError';

Const
 HTTP_QUERY_STATUS_CODE=19;
 HTTP_QUERY_RAW_HEADERS_CRLF=22;
 HTTP_QUERY_FLAG_NUMBER=$20000000;
 FLAG_RELOAD=LongInt($80000000);
 FLAG_SECURE=$00800000;
 FLAG_NO_REDIRECT=$00200000;
 FLAG_NO_COOKIES=$00080000;

Var
 Url,OutName,Method,Data,Agent,Hdrs,S,P:String;
 Scheme,Host,Path:String;
 Port,I,K,Err:Integer;
 HeadOnly,Include,Follow,Silent,Verbose,Fail,RemoteName,ToFile:Boolean;
 Net,Con,Req,Flags,Status,Len,Got,Total:LongInt;
 ZHost,ZVerb,ZPath,ZAgent:Array[0..255]of Char;
 ZHdr:Array[0..1023]of Char;
 ZData:Array[0..255]of Char;
 Buf:Array[0..16383]of Byte;
 HBuf:Array[0..8191]of Char;
 F:File;

Procedure PutZ(Var Z:Array of Char;Const T:String);
Var
 J:Integer;
Begin
 For J:=1 to Length(T)do Z[J-1]:=T[J];
 Z[Length(T)]:=#0;
End;

Procedure ShowHelp;Begin
 WriteLn('Syntaxe : CURL [options...] url');
 WriteLn;
 WriteLn(' -A agent        Nom du client (User-Agent)');
 WriteLn(' -d donnees      Envoie des donnees (POST)');
 WriteLn(' -f              Echoue sans afficher le contenu sur une erreur HTTP');
 WriteLn(' -H en-tete      Ajoute un en-tete a la requete');
 WriteLn(' -i              Affiche les en-tetes de la reponse');
 WriteLn(' -I              En-tetes seulement (methode HEAD)');
 WriteLn(' -L              Suit les redirections');
 WriteLn(' -o fichier      Ecrit le contenu dans un fichier');
 WriteLn(' -O              Ecrit dans un fichier au nom du fichier distant');
 WriteLn(' -s              Silencieux');
 WriteLn(' -v              Affiche les details de la requete');
 WriteLn(' -X methode      Methode HTTP (GET, POST, PUT, DELETE...)');
 WriteLn(' --version       Affiche la version');
End;

Procedure Die(Code:Integer;Const Msg:String);Begin
 If Not(Silent)Then WriteLn('curl: (',Code,') ',Msg);
 Halt(Code);
End;

{ Ecrit Got octets de Buf sur la sortie standard }
Procedure OutBuf(N:LongInt);
Var
 T:String;
 J,Q:LongInt;
Begin
 J:=0;
 While J<N do Begin
  Q:=N-J;
  If Q>200Then Q:=200;
  T:='';
  For K:=0 to Q-1 do T:=T+Chr(Buf[J+K]);
  Write(T);
  J:=J+Q;
 End;
End;

BEGIN
 Url:='';OutName:='';Method:='';Data:='';Agent:='curl/8.4.0 (Pasdows 95)';
 Hdrs:='';HeadOnly:=False;Include:=False;Follow:=False;Silent:=False;
 Verbose:=False;Fail:=False;RemoteName:=False;
 I:=1;
 While I<=ParamCount do Begin
  S:=ParamStr(I);
  If(S='-h')or(S='--help')or(S='/?')Then Begin
   ShowHelp;
   Halt(0);
  End
   Else
  If S='--version'Then Begin
   WriteLn('curl 8.4.0 (Pasdows 95) WININET/TLS 1.2');
   WriteLn('Protocols: http https');
   Halt(0);
  End
   Else
  If(S='-o')and(I<ParamCount)Then Begin Inc(I);OutName:=ParamStr(I);End Else
  If S='-O'Then RemoteName:=True Else
  If S='-I'Then HeadOnly:=True Else
  If S='-i'Then Include:=True Else
  If S='-L'Then Follow:=True Else
  If S='-s'Then Silent:=True Else
  If S='-v'Then Verbose:=True Else
  If S='-f'Then Fail:=True Else
  If(S='-X')and(I<ParamCount)Then Begin Inc(I);Method:=ParamStr(I);End Else
  If(S='-d')and(I<ParamCount)Then Begin Inc(I);Data:=ParamStr(I);End Else
  If(S='-A')and(I<ParamCount)Then Begin Inc(I);Agent:=ParamStr(I);End Else
  If(S='-H')and(I<ParamCount)Then Begin
   Inc(I);
   Hdrs:=Hdrs+ParamStr(I)+#13#10;
  End
   Else
  If(Length(S)>1)and(S[1]='-')Then Die(2,'option '+S+' inconnue')
   Else
  Url:=S;
  Inc(I);
 End;
 If Url=''Then Begin
  WriteLn('curl: aucune URL indiquee');
  WriteLn('curl: essayez ''curl -h'' pour plus d''information');
  Halt(2);
 End;
  { schema://hote[:port]/chemin }
 K:=Pos('://',Url);
 If K>0Then Begin
  Scheme:=Copy(Url,1,K-1);
  S:=Copy(Url,K+3,255);
 End
  Else
 Begin
  Scheme:='http';
  S:=Url;
 End;
 For K:=1 to Length(Scheme)do Scheme[K]:=UpCase(Scheme[K]);
 If(Scheme<>'HTTP')and(Scheme<>'HTTPS')Then
  Die(1,'Protocole "'+Scheme+'" non pris en charge');
 K:=Pos('/',S);
 If K>0Then Begin
  Host:=Copy(S,1,K-1);
  Path:=Copy(S,K,255);
 End
  Else
 Begin
  Host:=S;
  Path:='/';
 End;
 If Scheme='HTTPS'Then Port:=443 Else Port:=80;
 K:=Pos(':',Host);
 If K>0Then Begin
  Val(Copy(Host,K+1,10),Port,Err);
  Host:=Copy(Host,1,K-1);
 End;
 If(RemoteName)and(OutName='')Then Begin
  OutName:=Path;
  K:=Pos('?',OutName);
  If K>0Then OutName:=Copy(OutName,1,K-1);
  While Pos('/',OutName)>0 do Delete(OutName,1,Pos('/',OutName));
  If OutName=''Then OutName:='index.html';
 End;
 If Method=''Then Begin
  If(HeadOnly)Then Method:='HEAD' Else
  If Data<>''Then Method:='POST'
             Else Method:='GET';
 End;
 If(Data<>'')and(Pos('Content-Type',Hdrs)=0)Then
  Hdrs:=Hdrs+'Content-Type: application/x-www-form-urlencoded'#13#10;
 PutZ(ZAgent,Agent);
 Net:=InternetOpenA(@ZAgent,0,Nil,Nil,0);
 If Net=0Then Die(2,'WININET indisponible');
 PutZ(ZHost,Host);
 If(Verbose)Then WriteLn('*   Trying ',Host,':',Port,'...');
 Con:=InternetConnectA(Net,@ZHost,Port,Nil,Nil,3,0,0);
 If Con=0Then Die(6,'Impossible de resoudre l''hote : '+Host);
 Flags:=FLAG_RELOAD or FLAG_NO_COOKIES;
 If Scheme='HTTPS'Then Flags:=Flags or FLAG_SECURE;
 If Not(Follow)Then Flags:=Flags or FLAG_NO_REDIRECT;
 PutZ(ZVerb,Method);
 PutZ(ZPath,Path);
 Req:=HttpOpenRequestA(Con,@ZVerb,@ZPath,Nil,Nil,Nil,Flags,0);
 If Req=0Then Die(7,'Impossible d''ouvrir la requete');
 If(Verbose)Then Begin
  WriteLn('> ',Method,' ',Path,' HTTP/1.1');
  WriteLn('> Host: ',Host);
  WriteLn('> User-Agent: ',Agent);
  WriteLn('>');
 End;
 PutZ(ZHdr,Hdrs);
 PutZ(ZData,Data);
 If Data<>''Then K:=HttpSendRequestA(Req,@ZHdr,Length(Hdrs),@ZData,
                                       Length(Data))
            Else K:=HttpSendRequestA(Req,@ZHdr,Length(Hdrs),Nil,0);
 If K=0Then Die(7,'Echec de connexion a '+Host+' port '+
                  Chr(48+(Port div 100)mod 10)+Chr(48+(Port div 10)mod 10)+
                  Chr(48+Port mod 10)+' (erreur WININET)');
 Status:=0;Len:=4;
 HttpQueryInfoA(Req,HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
                @Status,Len,Nil);
 If(Include)or(HeadOnly)or(Verbose)Then Begin
  Len:=SizeOf(HBuf)-1;
  FillChar(HBuf,SizeOf(HBuf),0);
  If HttpQueryInfoA(Req,HTTP_QUERY_RAW_HEADERS_CRLF,@HBuf,Len,Nil)<>0Then Begin
   S:='';
   For K:=0 to Len-1 do Begin
    If HBuf[K]=#10Then Begin
     If(Verbose)and Not(Include or HeadOnly)Then WriteLn('< ',S)
                                         Else WriteLn(S);
     S:='';
    End
     Else
    If(HBuf[K]<>#13)and(HBuf[K]<>#0)Then S:=S+HBuf[K];
   End;
   If S<>''Then WriteLn(S);
  End;
 End;
 If(Fail)and(Status>=400)Then Begin
  InternetCloseHandle(Req);
  Die(22,'The requested URL returned error: '+Chr(48+Status div 100)+
         Chr(48+(Status div 10)mod 10)+Chr(48+Status mod 10));
 End;
 ToFile:=OutName<>'';
 If(ToFile)Then Begin
  Assign(F,OutName);
  {$I-}Rewrite(F,1);{$I+}
  If IOResult<>0Then Die(23,'Impossible d''ecrire '+OutName);
 End;
 Total:=0;
 If Not(HeadOnly)Then Repeat
  Got:=0;
  If InternetReadFile(Req,@Buf,SizeOf(Buf),Got)=0Then Break;
  If Got>0Then Begin
   If(ToFile)Then BlockWrite(F,Buf,Got)Else OutBuf(Got);
   Total:=Total+Got;
  End;
 Until Got=0;
 If(ToFile)Then Begin
  Close(F);
  If Not(Silent)Then
   WriteLn(Total,' octets recus dans ',OutName,' (HTTP ',Status,')');
 End;
 InternetCloseHandle(Req);
 InternetCloseHandle(Con);
 InternetCloseHandle(Net);
END.
