{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2021
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program DELTREE;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
Uses Crt,DOS;

Var
 Language:(_French,_English,_Germany,_Italian,_Spain);
 TmpLanguage:String;
 Question:Boolean;
 F0:File;
 I:Integer;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Procedure DeleteFile(FileName:String);
Var
 F:File;
Begin
 {$I-}Assign(F,FileName);
 Erase(F);
 {$I+}
End;

Procedure DeleteTree(Dir:String);
Var
 Info:SearchRec;
Begin
 FindFirst(Dir+'\*.*',AnyFile,Info);
 While DOSError=0do Begin
  If Info.Attr and Directory=Directory Then Begin
   If(Info.Name<>'.')and(Info.Name<>'..')Then DeleteTree(Dir+'\'+Info.Name);
  End
   Else
  Begin
   {$I-}Assign(F0,Dir+'\'+Info.Name);SetFAttr(F0,0);{$I+}
   If IOResult<>0Then;
   DeleteFile(Dir+'\'+Info.Name);
  End;
  FindNext(Info);
 End;
 FindClose(Info);
 {$I-}RmDir(Dir);{$I+}
 If IOResult<>0Then;
End;

{ Comme MS-DOS : une confirmation par repertoire, sauf avec /Y }
Procedure AskDeleteTree(Dir:String);
Var
 C:Char;
Begin
 If(Question)Then Begin
  Write('Supprimer le r'#130'pertoire "',Dir,'" et tout ce qu''il contient ',
        '[O/N] ? ');
  C:=ReadKey;
  WriteLn(C);
  If Not(C in['O','o','Y','y'])Then Exit;
 End;
 DeleteTree(Dir);
 WriteLn('Suppression de ',Dir,'...');
End;

BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
   SetUseACP(False);
  {$ENDIF}
 {$ENDIF}
 Language:=_French;
 TmpLanguage:=GetEnv('LANGUAGE');
 If TmpLanguage<>''Then Begin
  If TmpLanguage[1]='"'Then TmpLanguage:=Copy(TmpLanguage,2,255);
  If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English Else
  If StrToUpper(Copy(TmpLanguage,1,2))='GR'Then Language:=_Germany Else
  If StrToUpper(Copy(TmpLanguage,1,2))='IT'Then Language:=_Italian Else
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain;
 End;
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('L”scht eine oder mehrere Dateien und Verzeichnisse');
    WriteLn;
    WriteLn('DELTREE [/Y] [Laufwerk:]Pfad');
    WriteLn;
    WriteLn('/Y   Unterdrckt die Anzeige der Best„tigung, ween ein ');
    WriteLn('Unterverzeichnis gel”scht wird.');
   End;
   Else Begin
    Write('DELTREE : Cette commande permet de supprimer un repertoire ',
          'avec ses fichiers et repertoire.');
    WriteLn;
    WriteLn('Syntaxe : DELTREE repertoire [/Y]');
   End;
  End;
 End
  Else
 If ParamCount>0Then Begin
  Question:=True;
  For I:=1 to ParamCount do Begin
   If(ParamStr(I)='/Y')or(ParamStr(I)='/y')Then Question:=False;
  End;
  For I:=1 to ParamCount do Begin
   If Not((ParamStr(I)='/Y')or(ParamStr(I)='/y'))Then
    AskDeleteTree(ParamStr(I));
  End;
 End
  Else
 WriteLn('Parametre requis !');
END.
