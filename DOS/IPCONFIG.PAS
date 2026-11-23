{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: Pasdows 95 (WPC -CW32), Windows)
}

Program IPCONFIG;

{ IPCONFIG : affiche la configuration TCP/IP de l'ordinateur, comme la
  commande IPCONFIG de Windows (IPHLPAPI : GetAdaptersInfo et
  GetNetworkParams). Options : /ALL (details), /? (aide). }

{$R-}

Uses DOS;

Function GetAdaptersInfo(P:Pointer;Sz:Pointer):LongInt;stdcall;
 external 'iphlpapi.dll' name 'GetAdaptersInfo';
Function GetNetworkParams(P:Pointer;Sz:Pointer):LongInt;stdcall;
 external 'iphlpapi.dll' name 'GetNetworkParams';

Type
 PLong=^LongInt;

Var
 Language:(_French,_English);
 TmpLanguage,S:String;
 All:Boolean;
 Ad:Array[0..639]of Byte;
 Np:Array[0..583]of Byte;
 Sz,R,I:LongInt;

Function StrToUpper(S:String):String;
Var
 J:Integer;
Begin
 For J:=1 to Length(S)do S[J]:=UpCase(S[J]);
 StrToUpper:=S;
End;

{ Chaine ASCIIZ de B a partir de O (au plus N caracteres) }
Function CStr(Var B:Array of Byte;O,N:Integer):String;
Var
 T:String;
 K:Integer;
Begin
 T:='';K:=0;
 While(K<N)and(B[O+K]<>0)do Begin
  T:=T+Chr(B[O+K]);
  Inc(K);
 End;
 CStr:=T;
End;

Function Hex2(V:Byte):String;
Const
 H:String[16]='0123456789ABCDEF';
Begin
 Hex2:=H[(V shr 4)+1]+H[(V and 15)+1];
End;

{ Ligne "    Libelle . . . . . . . : valeur" comme Windows }
Procedure Row(Const Lbl,V:String);
Var
 T:String;
Begin
 T:='   '+Lbl+' ';
 While Length(T)<39 do T:=T+'. ';
 T:=Copy(T,1,39)+': ';
 WriteLn(T,V);
End;

Function L(Const Fr,En:String):String;Begin
 If Language=_English Then L:=En Else L:=Fr;
End;

BEGIN
 Language:=_French;
 TmpLanguage:=GetEnv('LANGUAGE');
 If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English;
 All:=False;
 For I:=1 to ParamCount do Begin
  S:=StrToUpper(ParamStr(I));
  If(S='/?')or(S='-?')Then Begin
   WriteLn(L('IPCONFIG : Cette commande affiche la configuration IP de '+
             'l''ordinateur.',
             'IPCONFIG : Displays the IP configuration of the computer.'));
   WriteLn;
   WriteLn(L('Syntaxe : IPCONFIG [/ALL]','Usage: IPCONFIG [/ALL]'));
   WriteLn;
   WriteLn(L(' /ALL   Affiche tous les d'#130'tails de la configuration.',
             ' /ALL   Display full configuration information.'));
   Halt(0);
  End
   Else
  If(S='/ALL')or(S='-ALL')Then All:=True;
 End;
 WriteLn;
 WriteLn(L('Configuration IP de Pasdows 95','Pasdows 95 IP Configuration'));
 WriteLn;
 FillChar(Np,SizeOf(Np),0);
 Sz:=SizeOf(Np);
 If(All)and(GetNetworkParams(@Np,@Sz)=0)Then Begin
  Row(L('Nom de l''h'#147'te','Host Name'),CStr(Np,0,132));
  Row(L('Serveurs DNS','DNS Servers'),CStr(Np,272,16));
  Row(L('Type de noeud','Node Type'),L('Diffusion','Broadcast'));
  Row(L('Routage IP activ'#130,'IP Routing Enabled'),L('Non','No'));
  WriteLn;
 End;
 FillChar(Ad,SizeOf(Ad),0);
 Sz:=SizeOf(Ad);
 R:=GetAdaptersInfo(@Ad,@Sz);
 If R<>0Then Begin
  WriteLn(L('Aucune carte r'#130'seau : TCP/IP fonctionne seulement en '+
            'boucle locale (127.0.0.1).',
            'No network adapter: TCP/IP only works on the loopback '+
            'address (127.0.0.1).'));
  Halt(1);
 End;
 WriteLn(L('Carte Ethernet ','Ethernet adapter '),CStr(Ad,8,260),' :');
 WriteLn;
 If(All)Then Begin
  Row(L('Description','Description'),CStr(Ad,268,132));
  S:='';
  For I:=0 to PLong(@Ad[400])^-1 do Begin
   If I>0Then S:=S+'-';
   S:=S+Hex2(Ad[404+I]);
  End;
  Row(L('Adresse physique','Physical Address'),S);
  If PLong(@Ad[420])^<>0Then Row(L('DHCP activ'#130,'DHCP Enabled'),
                                  L('Oui','Yes'))
                         Else Row(L('DHCP activ'#130,'DHCP Enabled'),
                                  L('Non','No'));
 End;
 Row(L('Adresse IP','IP Address'),CStr(Ad,432,16));
 Row(L('Masque de sous-r'#130'seau','Subnet Mask'),CStr(Ad,448,16));
 Row(L('Passerelle par d'#130'faut','Default Gateway'),CStr(Ad,472,16));
 If(All)Then Begin
  Row(L('Serveur DHCP','DHCP Server'),CStr(Ad,512,16));
  Row(L('Serveurs DNS','DNS Servers'),CStr(Np,272,16));
 End;
END.
