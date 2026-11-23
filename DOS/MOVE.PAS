{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal, Free Pascal)
}

Program Move;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
Uses DOS;

Var
 Language:(_French,_English,_Germany,_Italian,_Spain);
 TmpLanguage:String;

Function StrToUpper(S:String):String;
Var
 I:Byte; { Compteur de boucle attribue a la chaine de caracteres }
Begin
 For I:=1to Length(S)do S[I]:=UpCase(S[I]);
 StrToUpper:=S;
End;

Function SplitFileName(s:String):String;
Var
 D:DirStr;
 N:NameStr;
 E:ExtStr;
Begin
 FSplit(S,D,N,E);
 Splitfilename:=N+E;
End;

Function CopyFile(Source,Target:String):Boolean;
Var
 SourceFile,TargetFile:File;
 RecordsRead:Integer;
 Buffer:Array[1..1000]of Byte;
Begin
 CopyFile:=False;
 Assign(SourceFile,Source);
 {$I-}Reset(SourceFile,1);{$I+}
 If IOResult<>0Then Begin
  WriteLn('Fichier source introuvable ',Source);
  Exit;
 End;
 Assign(TargetFile,Target);
 {$I-}Rewrite(TargetFile,1);
 BlockRead(SourceFile,Buffer,SizeOf(Buffer),RecordsRead);
 While RecordsRead>0 do Begin
  BlockWrite(TargetFile,Buffer,RecordsRead);
  BlockRead(SourceFile,Buffer,SizeOf(Buffer),RecordsRead);
 End;
 Close(SourceFile);
 Close(TargetFile);
 {$I+}
 CopyFile:=True;
End;


{ Target est-il un repertoire existant ? }
Function IsDir(Target:String):Boolean;
Var
 Info:SearchRec;
Begin
 IsDir:=False;
 If(Length(Target)=3)and(Target[2]=':')Then Begin
  IsDir:=True;
  Exit;
 End;
 If(Target<>'')and(Target[Length(Target)]='')Then
  Target:=Copy(Target,1,Length(Target)-1);
 FindFirst(Target,AnyFile,Info);
 If DOSError=0Then IsDir:=(Info.Attr and Directory)<>0;
End;

Function MoveOne(Source,Target:String;TDir:Boolean):Boolean;
Var
 F:File;
Begin
 Source:=FExpand(Source);
 Target:=FExpand(Target);
 If(TDir)Then Begin
  If Target[Length(Target)]<>''Then Target:=Target+'';
  Target:=Target+SplitFileName(Source);
 End;
 If(Source[1]<>Target[1])and(Source[2]=':')Then Begin { Unite de disque different ?}
   { Copie le fichier }
  MoveOne:=CopyFile(Source,Target);
   { Supprime le fichier }
  {$I-}Assign(F,Source);
  Erase(F);
  {$I+}
  If IOResult<>0Then;
 End
  Else
 Begin
  {$I-}
  Assign(F,Source);
  Rename(F,Target);
  MoveOne:=IOResult=0;
  {$I+}
 End;
 WriteLn(Source,' => ',Target);
End;

{ Deplacer un ou plusieurs fichiers (jokers) vers Target }
Function MoveFile(Source,Target:String):Boolean;
Var
 Info:SearchRec;
 D:DirStr;
 N:NameStr;
 E:ExtStr;
 Ok,TDir:Boolean;
Begin
 If(Source='')or(Target='')Then Begin
  MoveFile:=False;
  Exit;
 End;
 Source:=FExpand(Source);
 If(Pos('*',Source)=0)and(Pos('?',Source)=0)Then Begin
  MoveFile:=MoveOne(Source,Target,IsDir(FExpand(Target)));
  Exit;
 End;
 FSplit(Source,D,N,E);
 TDir:=IsDir(FExpand(Target));
 If Not(TDir)Then Begin
  WriteLn('Le repertoire de destination n''existe pas : ',Target);
  MoveFile:=False;
  Exit;
 End;
 Ok:=False;
 FindFirst(Source,AnyFile and Not Directory and Not VolumeID,Info);
 While DOSError=0 do Begin
  Ok:=MoveOne(D+Info.Name,Target,TDir);
  If Not(Ok)Then Break;
  FindNext(Info);
 End;
 FindClose(Info);
 MoveFile:=Ok;
End;

BEGIN
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
    WriteLn('Verschiebt Dateien und benennt Dateien und Verzeichnisse um.');
    WriteLn;
    WriteLn('MOVE [Laufwerk:][Pfad]Dateiname[,...] Ziel');
   End;
   _English:Begin
    WriteLn('Moves files and renames files and directories.');
    WriteLn;
    WriteLn('MOVE [drive:][path]filename1[,...] destination');
   End;
   Else Begin
    WriteLn('MOVE : Cette commande permet de deplacer un fichier.');
    WriteLn;
    WriteLn('Syntaxe : MOVE source destination');
   End;
  End;
 End
  Else
 If ParamCount=2Then Begin
  If Not MoveFile(ParamStr(1),ParamStr(2))Then Begin
   WriteLn('Erreur de d‚placement du fichier.');
  End;
 End
  Else
 WriteLn('Nombre de parametre invalide');
END.
