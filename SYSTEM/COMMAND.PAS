{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/corail)
  @abstract(Target: Turbo Pascal 7, Free Pascal)
}

{ Interpreteur de commandes de Pasdows 95 (COMMAND.EXE).
  Adaptation du programme CMD.PAS du projet Corail : banniere et VER
  propres a Pasdows 95, option /R (reprise apres un programme externe :
  le noyau relance COMMAND.EXE /R lorsque le programme lance se
  termine). Compiler avec WPC -CW32. }

Program CMD;

{$M 8192,0,0}

Uses Crt,DOS;

Const
 CommandList:Array[0..38]of String[8]=(
  'BREAK','CALL','CD','CHCP','CHDIR','CLS','COPY','CTTY','DEL','DELETE',
  'DIR','ECHO','ERA','ERASE','EXIT','FOR','IF','LOADHIGH','MD','MKDIR',
  'PATH','PAUSE','PROMPT','RD','REM','REN','RENAME','RMDIR','SET',
  'SHIFT','TIME','TRUENAME','TYPE','VER','VERIFY','VOL','DATE',
  'TIMEOUT','GOTO'
 );
 { fichiers de traitement par lots : lignes en memoire, niveaux de CALL }
 MaxBatLevel=8;
 MaxBatLines=600;
 MaxBatArgs=20;
 BatBufSz=16384;                  { texte d'un fichier (octets) }

 MaxHistory=100;

Type
 StrPointer=^String;

Var
 Language:(_French,_English,_Germany,_Italian,_Spain);
 TmpLanguage:String;
 ShowASCII128,Pipe,PipeToCommand:Boolean;
 PipeFile:Text;
 InCmd:Byte;
 Option:(optNone,optCommand);
 History:Array[1..MaxHistory] of StrPointer;
 NumberHistory:Integer;
 Echo:Boolean;
 CommandFound,Terminated:Boolean;
 CmdStr:String;
 CurrCommand,ParamList,PipeCommand:String;
 I,J:Byte;
 { traitement par lots : niveau courant (0 : invite), lignes, ligne
   suivante, parametres (%0 a %9 apres SHIFT), ECHO a l'invite }
 BatLevel:Byte;
 BatN,BatPc,BatShift,BatArgN:Array[1..MaxBatLevel]of Integer;
 { lignes : chaines (longueur puis caracteres) dans BatBuf, tableaux a
   une dimension indexes par niveau }
 BatBuf:Array[0..MaxBatLevel*BatBufSz-1]of Char;
 BatOfs:Array[0..MaxBatLevel*MaxBatLines-1]of LongInt;
 BatArg:Array[0..MaxBatLevel*MaxBatArgs-1]of String[127];
 TopEcho:Boolean;
 ErrLevel:Integer;
 { redirections de la commande en cours : <fichier, >fichier, >>fichier ;
   PipeIn : entree venant du tuyau precedent }
 RedirIn,RedirOut,PipeIn:String;
 RedirApp:Boolean;
 PipeNum:Integer;
 { NoHist : commande de droite d'un tuyau ; PipeLeft : celle de gauche
   (pas de ligne vide apres elle) }
 NoHist,PipeLeft:Boolean;
 PipeCol:Integer;

Procedure RunCommand;Forward;
Procedure RunBatch(Name,Args:String);Forward;

Procedure PCopy(Source,Target:Byte);Begin
 {$IFNDEF FPC}
  Move(Mem[SegB800:Source*(MemW[$0040:$4A]*25*2)],
    Mem[SegB800:Target*(MemW[$0040:$4A]*25*2)],MemW[$0040:$4A]*25*2)
 {$ENDIF}
End;

Function PadRight(S:String;Space:Byte):String;
Var
 I:Byte;
Begin
 If Length(S)<Space Then For I:=Length(S)+1 to Space do S:=S+' ';
 PadRight:=S;
End;

Function PadZeroLeft(Value:Integer;Space:Byte):String;
Var
 S:String;
Begin
 Str(Value,S);
 While Length(S)<Space do S:='0'+S;
 PadZeroLeft:=S;
End;

Function TrimL(S:String):String;
Var
 I:Byte;
Begin
 For I:=1to Length(S)do Begin
  If S[I]<>' 'Then Begin
   TrimL:=Copy(S,I,255);
   Exit;
  End;
 End;
 TrimL:=S;
End;

Function TrimR(s:String):String;
Var
 i:Integer;
Begin
 i:=Length(s);
 While (i>0)and(s[i]in[#9,' '])do Dec(i);
 s[0]:=Chr(i);
 TrimR:=S;
End;

Function Trim(s:String):String;Begin
 Trim:=TrimL(TrimR(s));
End;

Function StrToUpper(S:String):String;
Var
 I:Byte;
Begin
 For I:=1 to Length(S)do Begin
  If S[I] in['a'..'z']Then S[I]:=Chr(Ord(S[I])-32);
 End;
 StrToUpper:=S;
End;

Function DuplicateString(C:Char;Num:Integer):String;
Var
 I:Byte;
 S:String;
Begin
 S:='';
 For I:=1 to Num do S:=S+C;
 DuplicateString:=S;
End;

Function GetCurrentDisk:Char;
Var
 CurrentDir:String;
Begin
 GetDir(0,CurrentDir);
 GetCurrentDisk:=CurrentDir[1];
End;

Function FileExist(Name:String):Boolean;
Var
 Rec:SearchRec;
Begin
 FindFirst(Name,AnyFile,Rec);
 FileExist:=DosError=0;
End;

Function Path2Drive(Path:String):Char;Begin
 Path:=FExpand(Path);
 Path2Drive:=Path[1];
End;

Function GetDiskLabel(Dsk:Byte):String;
Var
 Info:SearchRec;
 CurrentDir:String;
Begin
 If Dsk=0Then GetDir(0,CurrentDir)
         Else CurrentDir:=Char(Dsk+64);
 FindFirst(CurrentDir[1]+':\*.*',VolumeID,Info);
 While DosError=0do Begin
  If(Info.Attr = VolumeID)Then Begin
   GetDiskLabel:=Info.Name;
   Exit;
  End;
  FindNext(Info);
 End;
 GetDiskLabel:=''
End;

{ Environnement du processus (API Win32) : SET le modifie, les
  programmes lances en heritent }
Function SetEnvironmentVariableA(N,V:Pointer):LongInt;stdcall;
 external 'kernel32.dll' name 'SetEnvironmentVariableA';
Function GetEnvironmentVariableA(N,B:Pointer;Sz:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'GetEnvironmentVariableA';
Function GetEnvironmentStringsA:LongInt;stdcall;
 external 'kernel32.dll' name 'GetEnvironmentStringsA';

Procedure SetEnv(EnvVar,Value:String);Begin
 EnvVar:=StrToUpper(EnvVar)+#0;
 If Value=''Then SetEnvironmentVariableA(@EnvVar[1],Nil)
  Else
 Begin
  Value:=Value+#0;
  SetEnvironmentVariableA(@EnvVar[1],@Value[1]);
 End;
End;

Function EnvGet(Name:String):String;
Var
 B:Array[0..259]of Char;
 N,K:LongInt;
 R:String;
Begin
 Name:=StrToUpper(Name)+#0;
 N:=GetEnvironmentVariableA(@Name[1],@B,256);
 R:='';
 If(N>0)and(N<256)Then For K:=0 to N-1 do R:=R+B[K];
 EnvGet:=R;
End;

{ Afficher les variables (pause : une page a la fois) }
Procedure EnvList(Pause:Boolean);
Type
 PB=^Byte;
Var
 A,P:LongInt;
 S:String;
Begin
 A:=GetEnvironmentStringsA;
 If A=0Then Exit;
 P:=0;
 While PB(A)^<>0 do Begin
  S:='';
  While PB(A)^<>0 do Begin
   If Length(S)<255Then S:=S+Chr(PB(A)^);
   Inc(A);
  End;
  Inc(A);
  WriteLn(S);
  If(Pause)Then Begin
   Inc(P);
   If P=Hi(WindMax)Then Begin
    Write('Presse une touche pour continuer...');
    ReadKey;
    WriteLn;
    P:=0;
   End;
  End;
 End;
End;

Procedure Box(X1,Y1,X2,Y2,Couleur:Byte);Begin
 Window(X1,Y1,X2,Y2);
 TextBackground((Couleur shr 4)and 15);
 {$IFDEF FPC}
  If Couleur and $80=$80 Then Begin
   TextColor((Couleur and 15)+BLINK);
  End
   Else
  TextColor(Couleur and 15);
 {$ELSE}
  TextColor(Couleur and 15);
 {$ENDIF}
 ClrScr;
 Window(1,1,80,25);
End;

Procedure FrameEmpty(X1,Y1,X2,Y2,Couleur:Byte);
Var
 I:Byte;
 ChrHori,ChrVert:Char;
 Chr218,Chr192,Chr191,Chr217:Char;
Begin
 TextBackground((Couleur shr 4)and 15);
 {$IFDEF FPC}
  If Couleur and $80=$80 Then Begin
   TextColor((Couleur and 15)+BLINK);
  End
   Else
  TextColor(Couleur and 15);
 {$ELSE}
  TextColor(Couleur and 15);
 {$ENDIF}
 If(ShowASCII128)Then Begin
  ChrHori:='-';
  ChrVert:='|';
  Chr218:='+';
  Chr192:='+';
  Chr191:='+';
  Chr217:='+';
 End
  Else
 Begin
  ChrHori:=#$C4;
  ChrVert:=#$B3;
  Chr218:=#218;
  Chr192:=#192;
  Chr191:=#191;
  Chr217:=#217;
 End;
 For I:=Y1+1 to Y2-1 do Begin
  GotoXY(X1,I);
  Write(ChrVert);
  GotoXY(X2,I);
  Write(ChrVert);
 End;
 GotoXY(X1+1,Y1);
 Write(DuplicateString(ChrHori,X2-X1-1));
 GotoXY(X1+1,Y2);
 Write(DuplicateString(ChrHori,X2-X1-1));
 GotoXY(X1,Y1);
 Write(Chr218);
 GotoXY(X1,Y2);
 Write(Chr192);
 GotoXY(X2,Y1);
 Write(Chr191);
 GotoxY(X2,Y2);
 Write(Chr217);
End;

Function AddHistory(S:String):Boolean;
Var
 I:Word;
 P:StrPointer;
Begin
 If NumberHistory>=MaxHistory Then Begin
  FreeMem(History[1],Length(History[1]^)+1);
  For I:=1 to MaxHistory-1 do History[I]:=History[I+1];
  GetMem(P,Length(S)+1);
  P^:=S;
  History[MaxHistory]:=P;
  AddHistory:=True;
  Exit;
 End
  Else
 Begin
  Inc(NumberHistory);
  GetMem(P,Length(S)+1);
  P^:=S;
  History[NumberHistory]:=P;
  AddHistory:=True;
 End;
End;

Procedure FreeHistory;
Var
 I:Word;
Begin
 For I:=1 to NumberHistory do FreeMem(History[I],Length(History[I]^)+1);
 FillChar(History,SizeOf(History),0);
 NumberHistory:=0;
End;

Function CopyFile(Source,Target:String;ShowProgression:Boolean):Boolean;
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
 If(ShowProgression)Then WriteLn('. = 1000 octets de copies');
 BlockRead(SourceFile,Buffer,SizeOf(Buffer),RecordsRead);
 While RecordsRead>0 do Begin
  If(ShowProgression)Then Write('.');
  BlockWrite(TargetFile,Buffer,RecordsRead);
  BlockRead(SourceFile,Buffer,SizeOf(Buffer),RecordsRead);
 End;
 If(ShowProgression)Then WriteLn;
 Close(SourceFile);
 Close(TargetFile);
 {$I+}
 CopyFile:=True;
End;

Function GetErrorMessage(Code:Word):String;Begin
 Case Code of
  0:GetErrorMessage:='';
  2:GetErrorMessage:='Fichier introuvable';
  3:GetErrorMessage:='Chemin introuvable';
  4:GetErrorMessage:='Trop de fichiers ouvert';
  5:GetErrorMessage:='Acces refuse';
  6:GetErrorMessage:='Handle de fichier invalide';
  12:GetErrorMessage:='Mode d''acces sur disque invalide';
  15:GetErrorMessage:='NumÇro de disque invalide';
  16:GetErrorMessage:='Impossible de supprimer le rÇpertoire';
  17:GetErrorMessage:='Impossible de renommer sur plusieurs volumes';
  100:GetErrorMessage:='Erreur de lecture Ö partir du disque';
  101:GetErrorMessage:='Erreur d''ecriture sur le disque';
  102:GetErrorMessage:='Fichier non attribue';
  103:GetErrorMessage:='Le fichier n''est pas ouvert';
  104:GetErrorMessage:='Le fichier n''est pas ouvert Ö l''entree';
  105:GetErrorMessage:='Le fichier n''est pas ouvert Ö la sortie';
  106:GetErrorMessage:='Numero invalide';
  150:GetErrorMessage:='Disque protege en ecriture';
  151:GetErrorMessage:='Peripherique est inconnu';
  152:GetErrorMessage:='Disque pas pret';
  153:GetErrorMessage:='Commande inconnue';
  154:GetErrorMessage:='Echec de verification CRC';
  155:GetErrorMessage:='Disque invalide';
  156:GetErrorMessage:='Erreur de recherche sur disque';
  157:GetErrorMessage:='Type de media invalide';
  158:GetErrorMessage:='Secteur introuvable';
  159:GetErrorMessage:='L''imprimante n''a plus de papier';
  160:GetErrorMessage:='Erreur d''ecriture sur le peripherique';
  161:GetErrorMessage:='Erreur de lecture sur le peripherique';
  162:GetErrorMessage:='Defaillance materielle';
  Else GetErrorMessage:='Erreur inconnue';
 End;
End;

Procedure ExtractCommand;
Var
 I,J,K,Q:Byte;
 Internal:Boolean;
Begin
 For I:=1 to Length(CmdStr)do Begin
  If Not(CmdStr[I]in['A'..'Z','a'..'z','_','-','0'..'9'])Then Begin
   CurrCommand:=StrToUpper(Copy(CmdStr,1,I-1));
   Q:=I;
   { D:\PROG, \WINDOWS\PROG, PROG.EXE : chemin d'un programme, sauf si
     le debut est une commande interne collee (CD\, CD.., ECHO.) }
   If CmdStr[I]in[':','\','.']Then Begin
    Internal:=False;
    For K:=Low(CommandList)to High(CommandList)do
     If CommandList[K]=CurrCommand Then Internal:=True;
    If Not(Internal)Then Begin
     While(Q<=Length(CmdStr))and Not(CmdStr[Q]in[' ','/','|','>','<'])do
      Inc(Q);
     CurrCommand:=StrToUpper(Copy(CmdStr,1,Q-1));
    End;
   End;
   ParamList:=TrimL(Copy(CmdStr,Q,255));
   Exit;
  End;
 End;
 CurrCommand:=StrToUpper(CmdStr);
 ParamList:='';
End;

Function ExtractParam(Index:Byte):String;
Var
 Count:Word;
 LocalIndex:Word;
 l:Byte;
 Temp:String;
Begin
 Temp:='';Count:=1;LocalIndex:=1;l:=0;
 While Count<=Length(ParamList)do Begin
  If Not(ParamList[Count] in [' ',#9])then Begin
   If LocalIndex=Index Then Begin
    While (Count<=Length(ParamList)) and (Not(ParamList[count] in[' ',#9]))
      and (l < 256) do Begin
     Temp:=Temp+ParamList[count];
     Inc(l);
     Inc(Count);
    end;
    Temp[0]:=Char(l);
    ExtractParam:=Temp;
    Exit;
   End;
   While (Count<=Length(ParamList)) and (Not(ParamList[count] in [' ',#9]))
     do Inc(Count);
   Inc(LocalIndex);
  End;
  If Count>=Length(ParamList)Then Break;
  Inc(Count);
 End;
 ExtractParam:=Temp;
End;

Procedure HomeMessage;
Var
 Regs:Registers;
Begin
 {$IFNDEF WIN32}
  { DÇsactive le clignotement sous DOS }
 Regs.AX:=$1003;
 Regs.BL:=$0;
 Intr($10,Regs);
 {$ENDIF}
 WriteLn;
 WriteLn('Pasdows 95. [Version 4.00.950]');
 WriteLn('(C) Copyright Gladir.com 2026.');
 WriteLn;
End;

Procedure ShowPrompt;
Const Week:Array[0..6]of String[3]=('Dim','Lun','Mar','Mer','Jeu','Ven','Sam');
      Mon:Array[1..12]of String[3]=('Jan','Fev','Mar','Avr','Mai','Jui',
			            'Jul','Aou','Sep','Oct','Nov','Dec');
Var
 SP,CurrentDir:String;
 I:Byte;
 Year,Month,Day,DayOfWeek,Hour,Min,Sec,Sec100:Word;
Begin
 If Not(Echo)Then Exit;
 GetDir(0,CurrentDir);
 SP:=EnvGet('PROMPT');
 If SP=''Then SP:='$P$G';
 I:=1;
 While I<=Length(SP)do Begin
  If SP[I]='$'Then Begin
   Inc(I);
   Case SP[I] of
       'D': Begin
	     GetDate(Year,Month,Day,DayOfWeek);
	     Write(Week[DayOfWeek],'  ',Mon[Month],Day,',',Year);
	    End;
       'T': Begin
	     GetTime(Hour,Min,Sec,Sec100);
	     Write(Hour,':',Min,':',Sec);
	    End;
       'B' : Write('|');
   'e','E' : Write(#27);
   'g','G' : Write('>');
       'N' : Write(GetCurrentDisk);
   'p','P' : Begin
     GetDir(0,CurrentDir);
     Write(CurrentDir);
   End;
   '-','S' : Write(' ');
       'V' : Write(Lo(DosVersion),'.',Hi(DosVersion));
   '_','Z' : Write(#13#10);
       'z' : Write('?');
   End;
  End
   Else
  Write(SP[I]);
  Inc(I);
 End;
End;

Procedure InvalidParam(P:Byte);Begin
 WriteLn('Le parametre suivant est invalide : ',ExtractParam(P));
End;

Procedure BreakCommand;
Var
 FirstParam:String;
 X:Boolean;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Schaltet (zusÑtzliche) öberwachung fÅr STRG+C ein (ON) oder aus '+
      '(OFF).');
    WriteLn;
    WriteLn('BREAK [/?] [ON|OFF]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display, enable, or disable Ctrl-C and Ctrl-Break '+
      'checking.');
    WriteLn;
    WriteLn('Format:  BREAK [/?] [ON|OFF]');
   End;
   Else Begin
    WriteLn('BREAK   Cette commande permet de fixer ou de demander l''Çtat du '+
      'Ctrl+Break.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('BREAK [/?] [ON|OFF]');
    WriteLn;
    WriteLn('  /?    Ce paramätre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn('  OFF   Ce paramätre permet de dÇsactiver le Ctrl+C ou '+
      'Ctrl+Break.');
    WriteLn('  ON    Ce paramätre permet d''activer le Ctrl+C ou Ctrl+Break.');
   End;
  End;
 End
  Else
 If StrToUpper(ParamList)='OFF'Then SetCBreak(False) Else
 If StrToUpper(ParamList)='ON'Then SetCBreak(True)
  Else
 Begin
  GetCBreak(X);
  If(Pipe)Then Begin
   Write(PipeFile,'BREAK = ');
   If(X)Then WriteLn(PipeFile,'on')
        Else WriteLn(PipeFile,'off');
  End
   Else
  Begin
   Write('BREAK = ');
   If(X)Then WriteLn('on')
        Else WriteLn('off');
  End;
 End;
End;

{ Ligne K (1..BatN) du fichier de niveau L }
Function BatGetLine(L,K:Integer):String;
Var
 O,N,X:LongInt;
 S:String;
Begin
 O:=BatOfs[(L-1)*MaxBatLines+K-1];
 N:=Ord(BatBuf[O]);
 S:='';
 For X:=1 to N do S:=S+BatBuf[O+X];
 BatGetLine:=S;
End;

{ Parametre N du fichier de niveau L }
Function BatGetArg(L,N:Integer):String;Begin
 BatGetArg:=BatArg[(L-1)*MaxBatArgs+N];
End;

{ Premier mot de S (retire de S, espaces de tete enleves) }
Function NextWord(Var S:String):String;
Var
 P:Integer;
Begin
 S:=TrimL(S);
 P:=1;
 While(P<=Length(S))and Not(S[P]in[' ',#9])do Inc(P);
 NextWord:=Copy(S,1,P-1);
 S:=TrimL(Copy(S,P,255));
End;

{ Nom du fichier de traitement par lots d'une commande ('' sinon) }
Function BatchOf(Cmd:String):String;
Begin
 BatchOf:='';
 Cmd:=StrToUpper(Cmd);
 If Cmd=''Then Exit;
 If Copy(Cmd,Length(Cmd)-3,4)='.BAT'Then Begin
  If FileExist(Cmd)Then BatchOf:=Cmd;
 End
  Else
 If FileExist(Cmd+'.BAT')Then BatchOf:=Cmd+'.BAT';
End;

{ CALL : un fichier de traitement par lots revient ensuite a l'appelant }
Procedure CallCommand;
Var
 S,W,B:String;
Begin
 S:=ParamList;
 W:=NextWord(S);
 B:=BatchOf(W);
 If B<>''Then RunBatch(B,S)
  Else
 If W<>''Then Begin
  CmdStr:=ParamList;
  RunCommand;
 End;
End;

Procedure ChDirCommand;
Var
 Drive:Char;
 Error:Word;
 FirstParam,Dir,CurrPath:String;
Begin
 { tout le reste de la ligne : CD \Program Files\Oni ou CD "..." }
 FirstParam:=ParamList;
 While(Length(FirstParam)>0)and(FirstParam[Length(FirstParam)]in[' ',#9])do
  Dec(FirstParam[0]);
 If(Length(FirstParam)>=2)and(FirstParam[1]='"')Then Begin
  Delete(FirstParam,1,1);
  If FirstParam[Length(FirstParam)]='"'Then Dec(FirstParam[0]);
 End;
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Wechselt das aktuelle Verzeichnis oder zeigt dessen Namen an.');
    WriteLn;
    WriteLn('CD [path | -]');
    WriteLn('CHDIR [path | -]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display or change the current directory.');
    WriteLn;
    WriteLn('Format:   CD [path | -]');
    WriteLn(' ':14,'or');
    WriteLn(' ':10,'CHDIR [path | -]');
   End;
   Else Begin
    WriteLn('CHDIR   Cette commande permet de fixer ou de demander le '+
      'rÇpertoire courant.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('CD [/?] chemin');
    WriteLn('CHDIR [/?] chemin');
    WriteLn;
    WriteLn('  /?     Ce paramätre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn(' chemin  Ce paramätre permet d''indiquer le chemin du '+
      'repÇrtoire.');
   End;
  End;
 End
  Else
 If Length(FirstParam)>0Then Begin
  GetDir(0,CurrPath);
  Drive:=GetCurrentDisk;
  {$I-} ChDir(FirstParam);{$I+}
  Error:=IoResult;
  If Error<>0Then WriteLn(GetErrorMessage(Error));
  If Drive<>GetCurrentDisk Then ChDir(CurrPath);
 End
  Else
 Begin
  GetDir(0,Dir);
  WriteLn(Dir);
 End;
End;

Procedure CHCPCommand;
Var
 Err:Word;
 Regs:Registers;
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Wechselt die aktuelle Codeseite oder zeigt deren Nummer an.');
    WriteLn;
    WriteLn('CHCP [/?] [nnn]');
    WriteLn;
    WriteLn('nnn      Die Nummer einer Codeseite.');
   End;
   _English:Begin
    WriteLn('Displays or sets the active code page number.');
    WriteLn;
    WriteLn('CHCP [/?] [nnn]');
    WriteLn;
    WriteLn('nnn      Specify a code page number.');
   End;
   Else Begin
    WriteLn('CHCP   Cette commande permet de fixer ou de demander la page de '+
      'codes.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('CHCP [/?] [code]');
    WriteLn;
    WriteLn('  /?     Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn(' code    Ce parametre permet d''indiquer la page de code');
   End;
  End;
 End
  Else
 If FirstParam<>''Then Begin
  Regs.AX:=$6602;
  Val(FirstParam,Regs.BX,Err);
  If Err=0Then Begin
   Intr($21,Regs);
   If(Regs.Flags and FCarry=FCarry)Then Begin
    WriteLn('Impossible de changer le code de page actif');
   End;
  End
   Else
  WriteLn('Code de page invalide.');
 End
  Else
 Begin
  Regs.AX:=$6601;
  Intr($21,Regs);
  If(Regs.Flags and FCarry=FCarry)Then Begin
   WriteLn('Page de code active inconnnu');
  End
   Else
  WriteLn('Page de code active : ',Regs.BX);
 End;
End;

Procedure CLSCommand;
Var
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Lîscht den Bildschirminhalt.');
    WriteLn;
    WriteLn('CLS');
   End;
   _English:Begin
    WriteLn('Purpose:  Clear the video display and move the cursor to the '+
      'upper left');
    WriteLn;
    WriteLn('Format:   CLS [/?]');
   End;
   Else Begin
    WriteLn('CLS   Cette commande permet d''effacer l''Çcran.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('CLS [/?]');
    WriteLn;
    WriteLn('  /?    Ce paramätre permet d''afficher l''aide sur cette '+
      'commande');
   End;
  End;
 End
  Else
 Begin
  ClrScr;
 End;
End;

Procedure CopyCommand;
Var
 P:Byte;
 ShowProgression:Boolean;
 F:File;
 CurrParam,Source,Target:String;
Begin
 P:=0;
 ShowProgression:=False;
 Source:='';
 Target:='';
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Kopiert eine oder mehrere Dateien an eine andere Position.');
     WriteLn;
     WriteLn('COPY [/?] [/P] source target');
    End;
    _English:Begin
     WriteLn('Purpose:  Copy data between disks, directories or files.');
     WriteLn;
     WriteLn('Format:   COPY [/?] [/P] source target');
    End;
    Else Begin
     WriteLn('COPY   Cette commande permet d''effacer la copie de fichier '+
       'vers un autre emplacement.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('COPY [/?] [/P] source destination');
     WriteLn;
     WriteLn('    /?       Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn('    /P       Ce parametre permet d''afficher la progression de '+
       'la copie');
     WriteLn('source       Ce parametre permet d''indiquer le fichier source');
     WriteLn('destination  Ce parametre permet d''indiquer le fichier '+
       'destination');
     Exit;
    End;
   End;
  End
   Else
  If(CurrParam='/P')or(CurrParam='/p')Then ShowProgression:=True
   Else
  If CurrParam<>''Then
  Begin
   If Source=''Then Source:=CurrParam
               Else Target:=CurrParam;
  End;
  If P>9Then Break;
 Until CurrParam='';
 If(Source='')or(Target='')Then Begin
  WriteLn('La source et la destination sont requises');
 End
  Else
 Begin
  If CopyFile(Source,Target,ShowProgression)Then WriteLn('1 fichier copie')
                                            Else WriteLn('Echec de copie de '+
                                        'fichier');
 End;
End;

Procedure CTTYCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure DateCommand;
Var
 FirstParam:String;
 Year,Month,Day,DayOfMonth:Word;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Wechselt das eingestellte Datum oder zeigt es an.');
    WriteLn;
    WriteLn('DATE [/?]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display and optionnally change the system date.');
    WriteLn;
    WriteLn('Format:   DATE [/?]');
   End;
   Else Begin
    WriteLn('DATE   Cette commande permet de fixer ou de demander la date du '+
      'systeme d''exploitation');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('DATE [/?]');
    WriteLn;
    WriteLn('  /?    Ce paramätre permet d''afficher l''aide sur cette '+
      'commande');
   End;
  End;
 End
  Else
 Begin
  GetDate(Year,Month,Day,DayOfMonth);
  If(Pipe)Then WriteLn(PipeFile,'La date du jour est ',Year:4,'-',
    PadZeroLeft(Month,2),'-',PadZeroLeft(Day,2))
          Else WriteLn('La date du jour est ',Year:4,'-',PadZeroLeft(Month,2),
            '-',PadZeroLeft(Day,2));
 End;
End;

Procedure DeleteCommand;
Var
 P:Byte;
 Err:Word;
 F:File;
 CurrParam:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Lîscht eine oder mehrere Dateien.');
     WriteLn;
     WriteLn('DEL [/?] Datainame');
    End;
    _English:Begin
     WriteLn('Purpose:  Erase one file');
     WriteLn;
     WriteLn('Format:   DEL [/?] file');
     Exit;
    End;
    Else Begin
     WriteLn('DEL   Cette commande permet d''effectuer la suppression de '+
       'fichier sur un unitÇ de disque.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('DEL [/?] fichier');
     WriteLn;
     WriteLn('    /?    Ce paramätre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn(' fichier  Ce paramätre permet d''indiquer le nom du fichier a '+
       'supprimer.');
     Exit;
    End;
   End;
  End;
  {$I-}Assign(F,CurrParam);
  Erase(F);
  {$I+}
  Err:=IoResult;
  If Err=0Then WriteLn('1 fichier de supprime')
          Else WriteLn(GetErrorMessage(Err));
  If P>9Then Break;
 Until CurrParam='';
End;

Procedure DirCommand;
Var
 P:Byte;
 Info:SearchRec;
 T:DateTime;
 Option:Set of (Pause,Subdirectory,Lower,Brief,Description);
 Column:Set Of (ColDouble,ColWidth);
 TotalNumFiles,TotalSize:LongInt;
 CurrParam,ShowDir,CurrLabel:String;
 CurrDrive:Char;
Begin
 Option:=[];
 Column:=[];
 P:=0;
 ShowDir:='*.*';
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If Length(CurrParam)=0Then Break;
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Listet die Dateien und Unterverzeichnisse eines Verzeichnisses '+
       'auf.');
     WriteLn;
     WriteLn('Format:   DIR [/?] [/2|/W] [/B] [/P] [path]');
    End;
    _English:Begin
     WriteLn('Purpose:  Display information about files and subdirectories.');
     WriteLn;
     WriteLn('Format:   DIR [/?] [/2|/W] [/B] [/P] [path]');
     Exit;
    End;
    Else Begin
     WriteLn('DIR   Cette commande permet d''afficher le contenu d''un '+
       'repertoire dans l''unitÇ de disque.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('DIR [/?] [/2|/W] [/B] [/P] [chemin]');
     WriteLn;
     WriteLn(' /?   Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn(' /2   Ce parametre permet d''afficher sur 2 colonnes');
     WriteLn(' /B   Ce parametre enleve l''entàte et les dÇtails de la fin');
     WriteLN(' /P   Ce parametre affiche une pause apres l''affichage d''une '+
       'page pleine');
     WriteLn(' /W   Ce parametre affiche seulement les fichiers sur plein de '+
       'colonnes');
     Exit;
    End;
   End;
  End
   Else
  If CurrParam='/2'Then Include(Column,ColDouble) Else
  If(CurrParam='/B')or(CurrParam='/b')Then Include(Option,Brief) Else
  If(CurrParam='/L')or(CurrParam='/l')Then Include(Option,Lower) Else
  If(CurrParam='/P')or(CurrParam='/p')Then Include(Option,Pause) Else
  If(CurrParam='/W')or(CurrParam='/w')Then Include(Column,ColWidth)
                   Else ShowDir:=CurrParam;
  If P>99Then Break;
 Until CurrParam='';
 { Comme MS-DOS : un chemin qui designe un dossier (C:\, C:, D:\JEUX)
   liste le contenu de ce dossier. }
 If(ShowDir[Length(ShowDir)]='\')or(ShowDir[Length(ShowDir)]=':')Then
  ShowDir:=ShowDir+'*.*'
 Else If(Pos('*',ShowDir)=0)and(Pos('?',ShowDir)=0)Then Begin
  FindFirst(ShowDir,Directory,Info);
  If(DosError=0)and(Info.Attr and Directory=Directory)Then
   ShowDir:=ShowDir+'\*.*';
 End;
 CurrDrive:=Path2Drive(ShowDir);
 CurrLabel:=GetDiskLabel(Byte(CurrDrive)-64);
 P:=0;
 PipeCol:=0;
 FindFirst(ShowDir,AnyFile,Info);
 If(ColWidth)in(Column)Then Begin
  While DOSError=0 do Begin
   If(Pipe)Then Begin
    { tuyau ou fichier : 5 noms par ligne }
    Write(PipeFile,PadRight(Info.Name,16));
    Inc(PipeCol);
    If PipeCol=5Then Begin
     WriteLn(PipeFile);
     PipeCol:=0;
    End;
   End
    Else
   Write(PadRight(Info.Name,16));
   FindNext(Info);
   If(Pause)in(Option)Then Begin
    Inc(P);
    If P=Hi(WindMax)Then Begin
     Write('Presse une touche pour continuer...');
     If ReadKey=#27Then Exit;
     WriteLn;
     P:=0;
    End;
   End;
  End;
  If(Pipe)Then Begin
   If PipeCol>0Then WriteLn(PipeFile);
  End
   Else
  If WhereX>1Then WriteLn;
 End
  Else
 If(ColDouble)in(Column)Then While DOSError=0 do Begin
  If(Pipe)Then Write(PipeFile,PadRight(Info.Name,13))
          Else Write(PadRight(Info.Name,13));
  If Info.Attr and Directory=Directory Then Begin
   If(Pipe)Then Write(PipeFile,PadRight('<DIR>',9))
           Else Write(PadRight('<DIR>',9));
  End
   Else
  If(Pipe)Then Write(PipeFile,Info.Size:9)
          Else Write(Info.Size:9);
  UnpackTime(Info.Time,T);
  If(Pipe)Then Begin
   Write(PipeFile,' ',T.Year:4,'-',PadZeroLeft(T.Month,2),'-',
         PadZeroLeft(T.Day,2),' ',T.Hour:2,':',PadZeroLeft(T.Min,2),' ');
  End
   Else
  Begin
   Write(' ',T.Year:4,'-',PadZeroLeft(T.Month,2),'-',PadZeroLeft(T.Day,2),' ',
         T.Hour:2,':',PadZeroLeft(T.Min,2),' ');
  End;
  FindNext(Info);
  If(Pause)in(Option)Then Begin
   Inc(P);
   If P=Hi(WindMax)Then Begin
    Write('Presse une touche pour continuer...');
    If ReadKey=#27Then Exit;
    WriteLn;
    P:=0;
   End;
  End;
 End
  Else
 Begin
  TotalNumFiles:=0;
  TotalSize:=0;
  If Not((Brief)in(Option))Then Begin
   Inc(P,2);
   If(Pipe)Then Begin
    WriteLn(PipeFile,'Le volume de l''unite '+CurrDrive+' est '+CurrLabel);
    WriteLn(PipeFile);
   End
    Else
   Begin
    WriteLn('Le volume de l''unite '+CurrDrive+' est '+CurrLabel);
    WriteLn;
   End;
  End;
  While DOSError=0 do Begin
   If(Pipe)Then Write(PipeFile,PadRight(Info.Name,13))
           Else Write(PadRight(Info.Name,13));
   If Info.Attr and Directory=Directory Then Begin
    If(Pipe)Then Write(PipeFile,PadRight('<DIR>',15))
            Else Write(PadRight('<DIR>',15));
   End
    Else
   Begin
    If(Pipe)Then Write(PipeFile,Info.Size:15)
            Else Write(Info.Size:15);
   End;
   UnpackTime(Info.Time,T);
   If(Pipe)Then Begin
    WriteLn(PipeFile,' ',T.Year:4,'-',PadZeroLeft(T.Month,2),'-',
            PadZeroLeft(T.Day,2),' ',T.Hour:2,':',PadZeroLeft(T.Min,2));
   End
    Else
   Begin
    WriteLn(' ',T.Year:4,'-',PadZeroLeft(T.Month,2),'-',
            PadZeroLeft(T.Day,2),' ',T.Hour:2,':',PadZeroLeft(T.Min,2));
   End;
   FindNext(Info);
   If(Pause)in(Option)Then Begin
    Inc(P);
    If P=Hi(WindMax)Then Begin
     Write('Presse une touche pour continuer...');
     If ReadKey=#27Then Exit;
     WriteLn;
     P:=0;
    End;
   End;
   Inc(TotalNumFiles);
   Inc(TotalSize,Info.Size);
  End;
  If Not((Brief)in(Option))Then Begin
   If(Pipe)Then Begin
    WriteLn(PipeFile,' Les ',TotalNumFiles,' fichier(s) utilisent ',TotalSize,
      ' octet(s)');
    WriteLn(PipeFile,DiskFree(Byte(CurrDrive)-64):10,' octet(s) de libre');
   End
    Else
   Begin
    WriteLn(' Les ',TotalNumFiles,' fichier(s) utilisent ',TotalSize,
      ' octet(s)');
    WriteLn(DiskFree(Byte(CurrDrive)-64):10,' octet(s) de libre');
   End;
  End;
 End;
End;

Procedure EchoCommand;
Var
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Zeigt Meldungen an oder schaltet die Befehlsanzeige ein (ON) '+
      'oder aus (OFF).');
    WriteLn;
    WriteLn('ECHO [ON | OFF]');
    WriteLN('ECHO [Meldung]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display a message, enable or disable batch file or '+
      'command-line');
    WriteLn(' ':10,'echoing, or display the echo status.');
    WriteLn;
    WriteLn('Format:   ECHO [ON | OFF | message]');
   End;
   Else Begin
    WriteLn('ECHO   Cette commande permet d''activer ou desactiver le prompt '+
      'de commande ',
            'ou d''afficher un message sur le console du systeme d'+
              '''exploitation.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('ECHO [/?] message');
    WriteLn('ECHO [OFF|ON]');
    WriteLn;
    WriteLn('       /?  Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn('  message  Ce parametre permet d''afficher un message');
    WriteLn('      OFF  Ce parametre permet de desactiver le prompt.');
    WriteLn('       ON  Ce parametre permet d''activer le prompt.');
   End;
  End;
 End
  Else
 If(ParamList='.')and(Pipe)Then WriteLn(PipeFile)Else
 If ParamList='.'Then WriteLn Else
 If StrToUpper(ParamList)='OFF'Then Echo:=False Else
 If StrToUpper(ParamList)='ON'Then Echo:=True Else
 If(Pipe)Then WriteLn(PipeFile,ParamList)
         Else WriteLn(ParamList);
End;

Procedure EraseCommand;
Var
 P:Byte;
 Err:Word;
 F:File;
 CurrParam:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Lîscht eine oder mehrere Dateien.');
     WriteLn;
     WriteLn('ERASE Dateiname [/P]');
    End;
    _English:Begin
     WriteLn('Purpose:  Erase one file');
     WriteLn;
     WriteLn('Format:   ERASE [/?] file');
    End;
    Else Begin
     WriteLn('ERASE   Cette commande permet d''effectuer la suppression de '+
       'fichier sur un unitÇ de disque.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('ERASE [/?] fichier');
     WriteLn;
     WriteLn('      /?    Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn('  fichier   Ce parametre permet d''indiquer le nom du fichier a '+
       'supprimer.');
    End;
   End;
   Exit;
  End;
  {$I-}Assign(F,CurrParam);
  Erase(F);
  {$I+}
  Err:=IoResult;
  If Err=0Then WriteLn('1 fichier de supprime')
          Else WriteLn(GetErrorMessage(Err));
  If P>9Then Break;
 Until CurrParam='';
End;

Function ExitCommand:Boolean;
Var
 FirstParam:String;
 N,Err:Integer;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Beendet den Befehlsinterpreter COMMAND.COM.');
    WriteLn;
    WriteLn('Format:   EXIT [value]');
   End;
   _English:Begin
    WriteLn('Purpose:  Return from COMMAND.');
    WriteLn;
    WriteLn('Format:   EXIT [value]');
   End;
   Else Begin
    WriteLn('EXIT  Cette commande permet de quitter l''interpreteur de '+
      'commande.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('EXIT [/?] [CodeSortie]');
    WriteLn;
    WriteLn(' CodeSortie   Ce parametre permet d''indiquer le code de sortie '+
      'a ',
                           'retourner a l''application parent');
    WriteLn('        /?    Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
   End;
  End;
  ExitCommand:=False;
 End
  Else
 If Length(FirstParam)>0Then Begin
  Val(FirstParam,N,Err);
  Halt(N);
  ExitCommand:=True;
 End
  Else
 ExitCommand:=True;
End;

Procedure ForCommand;
Var
 PList,VarName,CurrMask,Mask,ForCmd:String;
 J,I:Byte;
Begin
 If ExtractParam(1)='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('FÅhrt einen Befehl fÅr jede einzelne Datei eines Satzes von '+
      'Dateien aus.');
    WriteLn;
    WriteLn('FOR %Variable IN (Satz) DO Befehl [Parameter]');
    WriteLn;
    WriteLn(' %Variable  Ein ersetzbarer Parameter (bestehend aus einem '+
      'einzelnen Zeichen).');
    WriteLn(' (Satz)     Ein Satz von mindestens einer Datei. Platzhalter '+
      'sind zulÑssig.');
    WriteLn(' Befehl     Befehl, der fÅr jede Datei ausgefÅhrt werden soll.');
    WriteLn(' Parameter  Parameter und Optionen fÅr den angebenen Befehl.');
   End;
   _English:Begin
    WriteLn('Run a specified command for each file in a set of files');
    WriteLn;
    WriteLn('FOR %variable IN (set) DO [command-parameters]');
    WriteLn;
    WriteLn(' %variable  Specifies a replaceable parameter.');
    WriteLn(' (set)      Specifies a set of one more files. Wildcards may be '+
      'used.');
    WriteLn(' command    Specifies the command to carry out for each file.');
    WriteLn(' command-parameters');
    WriteLn(' ':12,'Specifies parameters or switches for the specified '+
      'commad.');
   End;
   Else Begin
    WriteLn('FOR : Cette commande permet d''effectuer le traitement d''un '+
      'group de fichier');
    WriteLn;
    WriteLn('FOR %variable IN (ensemble) DO commande');
    WriteLn('FOR %%variable IN (ensemble) DO commande');
   End;
  End;
 End
  Else
 Begin
  PList:=Trim(ParamList);
  VarName:='';
  I:=1;
  If Copy(PList,1,2)='%%'Then Begin
   VarName:='%%';
   I:=3;
   While(I<=Length(PList))and(UpCase(PList[I])in['A'..'Z'])do Begin
    VarName:=VarName+PList[I];
    Inc(I);
   End;
  End
   Else
  If Copy(PList,1,1)='%'Then Begin
   VarName:='%';
   I:=2;
   While(I<=Length(PList))and(UpCase(PList[I])in['A'..'Z'])do Begin
    VarName:=VarName+PList[I];
    Inc(I);
   End;
  End
   Else
  Begin
   WriteLn('Nom de variable attendu !');
   Exit;
  End;
  While (I<=Length(PList))and(PList[I]in[#9,' '])do Inc(I);
  If StrToUpper(Copy(PList,I,3))='IN 'Then Begin
   Inc(I,3);
   While (I<=Length(PList))and(PList[I]in[#9,' '])do Inc(I);
   If PList[I]<>'('Then Begin
    WriteLn('''('' attendu !');
    Exit;
   End;
   Inc(I);
   Mask:='';
   While(I<=Length(PList))and(PList[I]<>')')do Begin
    Mask:=Mask+PList[I];
    Inc(I);
   End;
   If PList[I]<>')'Then Begin
    WriteLn(''')'' attendu !');
    Exit;
   End;
   Inc(I);
   While (I<=Length(PList))and(PList[I]in[#9,' '])do Inc(I);
   If StrToUpper(Copy(PList,I,3))='DO 'Then Begin
    Inc(I,3);
    ForCmd:=Trim(Copy(PList,I,255));
    CmdStr:='';
    CurrMask:='';
    J:=1;
    While J<=Length(Mask)do Begin
     If Mask[J]=' 'Then Begin
      If Trim(CurrMask)<>''Then Begin
       I:=1;
       While I<=Length(ForCmd)do Begin
        If Copy(ForCmd,I,Length(VarName))=VarName Then Begin
         CmdStr:=CmdStr+CurrMask;
         Inc(I,Length(VarName));
        End
         Else
        Begin
         CmdStr:=CmdStr+ForCmd[I];
         Inc(I);
        End;
       End;
       RunCommand;
       CmdStr:='';
       CurrMask:='';
      End;
     End
      Else
     CurrMask:=CurrMask+Mask[J];
     Inc(J);
    End;
    If Trim(CurrMask)<>''Then  Begin
     I:=1;
     While I<=Length(ForCmd)do Begin
      If Copy(ForCmd,I,Length(VarName))=VarName Then Begin
       CmdStr:=CmdStr+CurrMask;
       Inc(I,Length(VarName));
      End
       Else
      Begin
       CmdStr:=CmdStr+ForCmd[I];
       Inc(I);
      End;
     End;
     If CmdStr<>''Then RunCommand;
    End;
   End
    Else
   WriteLn('Mot rÇservÇ DO attendu');
  End
   Else
  WriteLn('Mot rÇservÇ IN attendu');
 End;
End;

{ IF [NOT] ERRORLEVEL n | EXIST fichier | chaine1==chaine2 commande }
Procedure IfCommand;
Var
 S,W,A,B:String;
 Neg,Cond:Boolean;
 N,E,P:Integer;
 Sr:SearchRec;
Begin
 S:=ParamList;
 Neg:=False;
 W:=StrToUpper(NextWord(S));
 If W='NOT'Then Begin
  Neg:=True;
  W:=StrToUpper(NextWord(S));
 End;
 If W='ERRORLEVEL'Then Begin
  Val(NextWord(S),N,E);
  Cond:=(E=0)and(ErrLevel>=N);
 End
  Else
 If W='EXIST'Then Begin
  A:=NextWord(S);
  FindFirst(A,AnyFile-Directory-VolumeID,Sr);
  Cond:=DosError=0;
 End
  Else
 Begin
  { chaine1==chaine2 : W peut contenir les deux, ou une partie }
  S:=ParamList;
  If Neg Then W:=NextWord(S);
  P:=Pos('==',S);
  If P=0Then Begin
   WriteLn('Erreur de syntaxe');
   Exit;
  End;
  A:=Copy(S,1,P-1);
  While(Length(A)>0)and(A[Length(A)]=' ')do Delete(A,Length(A),1);
  A:=TrimL(A);
  S:=TrimL(Copy(S,P+2,255));
  B:=NextWord(S);
  Cond:=A=B;
 End;
 If Neg Then Cond:=Not Cond;
 If Cond and(S<>'')Then Begin
  CmdStr:=S;
  RunCommand;
 End;
End;

{ GOTO etiquette (GOTO :EOF termine le fichier) }
Procedure GotoCommand;
Var
 S,L,T:String;
 K:Integer;
Begin
 If BatLevel=0Then Exit;
 S:=ParamList;
 L:=StrToUpper(NextWord(S));
 If(L<>'')and(L[1]=':')Then Delete(L,1,1);
 If L='EOF'Then Begin
  BatPc[BatLevel]:=BatN[BatLevel]+1;
  Exit;
 End;
 For K:=1 to BatN[BatLevel]do Begin
  T:=TrimL(BatGetLine(BatLevel,K));
  If(T<>'')and(T[1]=':')Then Begin
   T:=Copy(T,2,255);
   If StrToUpper(NextWord(T))=L Then Begin
    BatPc[BatLevel]:=K+1;
    Exit;
   End;
  End;
 End;
 WriteLn('Etiquette introuvable');
 BatPc[BatLevel]:=BatN[BatLevel]+1;
End;

Procedure LoadHighCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure MkDirCommand;Var
 P:Byte;
 Err:Word;
 CurrParam:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Erstellt ein Verichnis.');
     WriteLn;
     WriteLn('MKDIR [Laufwerk:]Pfad');
    End;
    _English:Begin
     WriteLn('Purpose:  Create a subdirectory.');
     WriteLn;
     WriteLn('MKDIR [/?] path');
    End;
    Else Begin
     WriteLn('MKDIR   Cette commande permet de creer un repertoire.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('MKDIR [/?] nomrepertoire');
     WriteLn;
     WriteLn('  nomrepertoire   Ce parametre permet d''indiquer le nom du '+
       'repertoire');
     WriteLn('            /?    Ce parametre permet d''afficher l''aide sur '+
       'cette commande');
    End;
   End;
   Exit;
  End;
  {$I-}MkDir(CurrParam);{$I+}
  Err:=IoResult;
  If Err<>0Then WriteLn(GetErrorMessage(Err));
  If P>9Then Break;
 Until CurrParam='';
End;

Procedure PathCommand;Begin
 WriteLn(EnvGet('PATH'));
End;

Procedure PauseCommand;
Var
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    Write('HÑlt die AusfÅhrung einer Stapelverarbeitungsdatei an und zeigh ');
    WriteLn('folgende Meldung an: ''Eine belige Taste drÅcken, um fortzsetsen'+
      '''');
    WriteLn;
    WriteLn('PAUSE [/?]');
   End;
   _English:Begin
    WriteLn('Purpose:  Suspend batch file or alias extension.');
    WriteLn;
    WriteLn('PAUSE [text]');
   End;
   Else Begin
    WriteLn('PAUSE   Cette commande permet d''afficher un message de pause et '+
      'une ',
            'attente d''une action utilisateur pour poursuivre.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('PAUSE [/?] [texte]');
    WriteLn;
    WriteLn('   /?    Ce paramätre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn(' texte   Ce paramätre permet d''indiquer le message de '+
      'remplacement.');
   End;
  End;
 End
  Else
 If FirstParam<>''Then Begin
  WriteLn(ParamList);
  ReadKey;
 End
  Else
 Begin
  Case Language of
   _Germany:WriteLn('Eine belige Taste drÅcken, um fortzsetsen');
   _English:WriteLn('Strike a key when ready...');
   Else WriteLn('Presse une touche pour continuer...');
  End;
  ReadKey;
 End;
End;

Procedure PromptCommand;Begin
 WriteLn('Cette commande n''est pas mise en oeuvre');
End;

Procedure RmDirCommand;Var
 P:Byte;
 Err:Word;
 CurrParam:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Eine belige Taste drÅcken, um fortzsetsen');
     WriteLn;
     WriteLn('RMDIR [Laufwerk:]Pfad');
    End;
    _English:Begin
     WriteLn('Purpose:  Remove one or more subdirectories.');
     WriteLn;
     WriteLn('Format:   RMDIR path');
    End;
    Else Begin
     WriteLn('RMDIR   Cette commande permet de supprimer un repertoire vide.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('RMDIR [/?] nomrepertoire');
     WriteLn;
     WriteLn('  /?           Ce parametre permet d''afficher l''aide sur '+
       'cette commande');
     WriteLn('nomrepertoire  Ce parametre permet d''indiquer le nom du '+
       'repertoire');
    End;
   End;
   Exit;
  End;
  {$I-}RmDir(CurrParam);{$I+}
  Err:=IoResult;
  If Err<>0Then WriteLn(GetErrorMessage(Err));
  If P>9Then Break;
 Until CurrParam='';
End;

Procedure RemCommand;
Var
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Leitet Kommentare in einer Stapelverarbeitungsdatei oder ',
            'in CONFIG.SYS ein.');
    WriteLn;
    WriteLn('REM [Kommentar]');
   End;
   Else Begin
    WriteLn('REM   Cette commande permet d''indiquer une remarque.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('REM [/?] commentaires');
    WriteLn;
    WriteLn('  /?           Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn('commentaires   Ce parametre permet d''indiquer une remarque');
   End;
  End;
 End;
End;

Procedure RenameCommand;
Var
 P:Byte;
 Err:Word;
 F:File;
 CurrParam,Source,Target:String;
Begin
 P:=0;
 Source:='';
 Target:='';
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    WriteLn('Paramätre requis');
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Benennt eine oder mehrere Dateien um.');
     WriteLn;
     WriteLn('REN [Laufwerk:][Pfad]Dateiname1 Dateiname2');
     WriteLn('RENAME [Laufwerk:][Pfad]Dateiname1 Dateiname2');
    End;
    _English:Begin
     WriteLn('Purpose:  Rename files.');
     WriteLn;
     WriteLn('Format:   REN old_name new_name');
    End;
    Else Begin
     WriteLn('RENAME   Cette commande permet de renommer un fichier.');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('RENAME [/?] anciennom nouveaunom');
     WriteLn;
     WriteLn(' /?         Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn('anciennom   Ce parametre permet d''indiquer l''ancien nom');
     WriteLn('nouveaunom  Ce parametre permet d''indiquer le nouveau nom');
    End;
   End;
   Exit;
  End
   Else
  If CurrParam<>''Then
  Begin
   If Source=''Then Source:=CurrParam
               Else Target:=CurrParam;
  End;
  If P>9Then Break;
 Until CurrParam='';
 If(Source='')or(Target='')Then Begin
  WriteLn('La source et la destination sont requises');
 End
  Else
 Begin
  {$I-}Assign(F,Source);
  Rename(F,Target);
  {$I+}
  Err:=IoResult;
  If Err=0Then WriteLn('1 fichier de renomme')
          Else WriteLn(GetErrorMessage(Err));
 End;
End;

Procedure SetCommand;
Var
 Pause:Boolean;
 I,P:Integer;
 FirstParam,VarName,VarValue:String;
Begin
 Pause:=False;
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Setzt oder entfernt DOS-Umgebungsvariablen oder zeigt sie an.');
    WriteLn;
    WriteLn('SET [Variable=[Zeichenfolge]]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display, create, modify, or delete environment '+
      'variables.');
    WriteLn;
    WriteLn('Format:   SET [/?] [/P]');
   End;
   Else Begin
    WriteLn('SET   Cette commande permet de fixer ou demander le contenu des ',
            'variables d''environnement du systeme d''exploitation');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('SET [Variable=[Valeur]]');
    WriteLn('SET [/?] [/P]');
    WriteLn;
    WriteLn(' /?   Ce parametre permet d''afficher l''aide sur cette commande');
    WriteLn(' /P   Ce parametre permet d''effectuer une pause entre chaque '+
      'page');
   End;
  End;
  Exit;
 End
  Else
 If Pos('=',FirstParam)>0 Then Begin
  VarName:=Copy(FirstParam,1,Pos('=',FirstParam)-1);
  VarValue:=Copy(FirstParam,Pos('=',FirstParam)+1,255);
  SetEnv(VarName,VarValue);
 End
  Else
 Begin
  If(FirstParam='/P')or(FirstParam='/p')Then Pause:=True;
  EnvList(Pause);
 End;
End;

Procedure ShiftCommand;Begin
 If BatLevel>0Then Inc(BatShift[BatLevel]);
End;

Procedure TimeCommand;
Var
 FirstParam:String;
 Hour,Minute,Second,CentSec:Word;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Stellt die Zeit ein oder zeigt sie an.');
    WriteLn;
    WriteLn('TIME [/?]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display or set the current system time.');
    WriteLn;
    WriteLn('Format:   TIME [/?]');
   End;
   Else Begin
    WriteLn('TIME   Cette commande permet de fixer ou de demander l''heure du '+
      'systeme d''exploitation');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('TIME [/?]');
    WriteLn;
    WriteLn('  /?    Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
   End;
  End;
 End
  Else
 Begin
  GetTime(Hour,Minute,Second,CentSec);
  WriteLn('L''heure actuelle est ',Hour:2,':',PadZeroLeft(Minute,2),':',
    PadZeroLeft(Second,2),',',CentSec);
 End;
End;

Procedure TimeOutCommand;
Var
 P:Byte;
 Y,I,Value:Integer;
 Err:Word;
 CurrParam:String;
 Mode:(_None,_T);
 NoBreak:Boolean;
Begin
 P:=0;
 NoBreak:=False;
 CurrParam:=ExtractParam(1);
 If CurrParam='/?'Then Begin
  WriteLn('TIMEOUT   Cette commande permet d''attendre le nombre de ',
                    'secondes specifie');
  WriteLn;
  WriteLn('Syntaxe:');
  WriteLn;
  WriteLn('TIMEOUT [/?]');
  WriteLn('TIMEOUT /T seconds');
  WriteLn;
  WriteLn(' /?      Ce parametre permet d''afficher l''aide sur cette '+
    'commande');
  WriteLn(' seconds Ce parametre permet d''indiquer le nombre de seconde d'+
    '''attente');
 End
  Else
 Begin
  Value:=-1;
  Mode:=_None;
  Repeat
   Inc(P);
   CurrParam:=ExtractParam(P);
   If CurrParam=''Then Begin
    If P=1Then Begin
     WriteLn('Vous devez entrez des paramätres !');
     Exit;
    End;
   End
    Else
   If Mode=_T Then Begin
    Val(CurrParam,Value,Err);
    If Err>0 Then Begin
     WriteLn('Valeur invalide !');
     Exit;
    End;
    Mode:=_None;
   End
    Else
   If StrToUpper(CurrParam)='/T'Then Mode:=_T Else
   If StrToUpper(CurrParam)='/NOBREAK'Then NoBreak:=True;
   If P>9Then Break;
  Until CurrParam='';
  If Value>0 Then Begin
   Y:=WhereY;
   WriteLn;
   For I:=Value downto 1 do Begin
    If Not(NoBreak)Then Begin
     If(Keypressed)Then Break;
    End;
    GotoXY(1,Y);
    If(NoBreak)Then Begin
     Write('Attendre ',I,' secondes, appuyez sur CTRL+C pour quitter...');
    End
     Else
    Begin
     Write('Attendre ',I,' secondes, appuyez sur une touche pour continuer...');
    End;
    Delay(1000);
   End;
   WriteLn;
  End;
 End;
End;

Procedure TrueNameCommand;
Var
 P:Byte;
 CurrParam:String;
 CurrDirectory:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If CurrParam=''Then Begin
   If P=1Then Begin
    GetDir(0,CurrDirectory);
    WriteLn(CurrDirectory);
   End;
   Break;
  End
   Else
  If CurrParam='/?'Then Begin
   Case Language of
    _English:Begin
     WriteLn('Purpose:  Find the full, true path and file name for a file.');
     WriteLn;
     WriteLn('Format:   TRUENAME file');
    End;
    Else Begin
     WriteLn('TRUENAME   Cette commande permet d''afficher le nom complet d'+
       '''un unite, repertoire ou d''un nom de fichier');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('TRUENAME [/?] [chemin]');
     WriteLn;
     WriteLn(' /?     Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn('chemin  Ce parametre permet d''indiquer le nom du chemin a '+
       'analyser');
    End;
   End;
   Exit;
  End;
  WriteLn(FExpand(CurrParam));
  If P>9Then Break;
 Until CurrParam='';
End;

Procedure TypeCommand;
Var
 P:Byte;
 Err:Word;
 Handle:Text;
 CurrParam,CurrLine:String;
Begin
 P:=0;
 Repeat
  Inc(P);
  CurrParam:=ExtractParam(P);
  If(Length(CurrParam)=0)and(P=1)Then Begin
   WriteLn('La syntaxe est incorrecte');
   Exit;
  End;
  If CurrParam='/?'Then Begin
   Case Language of
    _Germany:Begin
     WriteLn('Zeigt den inhalt einer Textdatei an.');
     WriteLn;
     WriteLn('TYPE [/?] [Laufwerk:][Pfad]Dateiname');
    End;
    _English:Begin
     WriteLn('Purpose:  Display the contents of the specified file(s).');
     WriteLn;
     WriteLn('TYPE [/?] [file]');
    End;
    Else Begin
     WriteLn('TYPE   Cette commande permet d''afficher le contenu d''un '+
       'fichier');
     WriteLn;
     WriteLn('Syntaxe:');
     WriteLn;
     WriteLn('TYPE [/?] [fichier]');
     WriteLn;
     WriteLn('  /?     Ce parametre permet d''afficher l''aide sur cette '+
       'commande');
     WriteLn('fichier  Ce parametre permet d''indiquer le nom du fichier a '+
       'afficher');
     Exit;
    End;
   End;
  End;
  If CurrParam<>''Then Begin
   Assign(Handle,CurrParam);
   {$I-}Reset(Handle);{$I+}
   Err:=IOResult;
   If Err<>0Then Begin
    WriteLn('Nom du fichier : "',CurrParam,'"');
    WriteLn(GetErrorMessage(Err));
    Exit;
   End;
   While NOT EOF(Handle)do Begin
    ReadLn(Handle,CurrLine);
    If(Pipe)Then WriteLn(PipeFile,CurrLine)
            Else WriteLn(CurrLine);
   End;
   Close(Handle);
  End;
  If P>9Then Break;
 Until CurrParam='';
End;

Procedure VerCommand;
Var
 Ver:Word;
 FirstParam:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Zeigh die Number der verwendeten DOS-Version an.');
    WriteLn;
    WriteLn('VER');
   End;
   _English:Begin
    WriteLn('Purpose:  Display the current command processor and operating '+
      'system');
    WriteLn(' ':10,'versions.');
    WriteLn;
    WriteLn('Format:   VER [/?]');
   End;
   Else Begin
    WriteLn('VER   Cette commande permet de demander la version du systeme d'+
      '''exploitation.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('VER [/?]');
    WriteLn;
    WriteLn(' /?    Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
   End;
  End;
 End
  Else
 Begin
  {$IFDEF WIN32}
   WriteLn;
   WriteLn('Pasdows 95. [Version 4.00.950]');
   WriteLn;
  {$ELSE}
   Ver:=DosVersion;
   WriteLn('DOS version ',Lo(Ver),'.',Hi(Ver));
  {$ENDIF}
 End;
End;

Procedure VerifyCommand;Var
 FirstParam:String;
 X:Boolean;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Legt, fest, ob DOS Åberwachen soll, da· Dateien korrekt auf '+
      'DataentrÑger ');
    WriteLn('geschrieben werben.');
    WriteLn;
    WriteLn('VERIFY [ON|OFF]');
   End;
   _English:Begin
    WriteLn('Purpose:  Enable or disable disk write verification or display '+
      'the');
    WriteLn(' ':10,'verification state.');
    WriteLn;
    WriteLn('Format:   VERIFY [ON | OFF]');
   End;
   Else Begin
    WriteLn('VERIFY   Cette commande permet de fixer ou de demander l''etat '+
      'du ',
            'drapeau de verification de lecture de secteur d''unite d'+
              '''allocation du systeme d''exploitation.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('VERIFY [/?] [OFF|ON]');
    WriteLn;
    WriteLn('  /?    Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn(' OFF    Ce parametre permet d''activer la verification');
    WriteLn(' ON     Ce parametre permet de desactiver la verification');
   End;
  End;
 End
  Else
 If StrToUpper(ParamList)='OFF'Then SetVerify(False) Else
 If StrToUpper(ParamList)='ON'Then SetVerify(True)
  Else
 Begin
  GetVerify(X);
  Write('VERIFY = ');
  If(X)Then WriteLn('on')
       Else WriteLn('off');
 End;
End;

Procedure VolCommand;
Var
 FirstParam,Volume:String;
Begin
 FirstParam:=ExtractParam(1);
 If FirstParam='/?'Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('Zeigt die Bezeichnung und Seriennummer eines DatentrÑgers an '+
      '(falls vorhanden).');
    WriteLn;
    WriteLn('VOL [Laufwerk:]');
   End;
   _English:Begin
    WriteLn('Purpose:  Display disk volume label(s).');
    WriteLn;
    WriteLn('Format:   VOL [d:] ...');
   End;
   Else Begin
    WriteLn('VOL   Cette commande permet d''afficher le nom du volume d''une '+
      'unite de disque.');
    WriteLn;
    WriteLn('Syntaxe:');
    WriteLn;
    WriteLn('VOL [/?] [unite:]');
    WriteLn;
    WriteLn(' /?      Ce parametre permet d''afficher l''aide sur cette '+
      'commande');
    WriteLn(' unite:  Ce paramtre permet d''indiquer la lettre d''unite de '+
      'disque');
   End;
  End;
 End
  Else
 If(Length(FirstParam)=2) and (FirstParam[2]=':')Then Begin
  If FirstParam[2]=':'Then Begin
   Write('Le volume de l''unite ',UpCase(FirstParam[1]));
   Volume:=GetDiskLabel(Byte(UpCase(FirstParam[1]))-64);
   If Length(Volume)=0Then WriteLn(' n''a pas d''etiquette')
                      Else WriteLn(Volume);
  End
   Else
  InvalidParam(1);
 End
  Else
 If Length(FirstParam)>0Then Begin
  InvalidParam(1);
 End
  Else
 Begin
   Write('Le volume de l''unite ',GetCurrentDisk);
   Volume:=GetDiskLabel(0);
   If Length(Volume)=0Then WriteLn(' n''a pas d''etiquette')
                      Else WriteLn(Volume);
 End;
End;

{ Programme externe avec ses entree et sortie standard dans des fichiers
  (<, >, >>, |) : CreateProcessA et STARTF_USESTDHANDLES }
Function CreateProcessA(App,Cmd:Pointer;PA,TA,Inh,Fl:LongInt;Env,Dir,SI,
 PI:Pointer):LongInt;stdcall;external 'kernel32.dll' name 'CreateProcessA';
Function CreateFileA(N:Pointer;Acc,Sh,Sa,Disp,Fl,T:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'CreateFileA';
Function SetFilePointer(H,D,P,M:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'SetFilePointer';
Function CloseHandle(H:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'CloseHandle';
Function GetStdHandle(N:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'GetStdHandle';
Function WaitForSingleObject(H,T:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'WaitForSingleObject';
Function GetExitCodeProcess(H:LongInt;P:Pointer):LongInt;stdcall;
 external 'kernel32.dll' name 'GetExitCodeProcess';
Function GetLastError:LongInt;stdcall;
 external 'kernel32.dll' name 'GetLastError';

{ Chaine S dans B en ASCIIZ }
Procedure PutZ(Var B:Array of Char;S:String);
Var
 K:Integer;
Begin
 For K:=1 to Length(S)do B[K-1]:=S[K];
 B[Length(S)]:=#0;
End;

Function RunRedir(Prog,Args,InF,OutF:String;App:Boolean):Word;
Var
 SI:Array[0..16]of LongInt;
 PI:Array[0..3]of LongInt;
 Cmd:Array[0..520]of Char;
 NB:Array[0..259]of Char;
 HIn,HOut,Code:LongInt;
 S:String;
 K,L:Integer;
Begin
 RunRedir:=0;
 HIn:=-1;HOut:=-1;
 If InF<>''Then Begin
  PutZ(NB,InF);
  HIn:=CreateFileA(@NB,LongInt($80000000),3,0,3,$80,0);
  If HIn=-1Then Begin
   RunRedir:=2;
   Exit;
  End;
 End;
 If OutF<>''Then Begin
  PutZ(NB,OutF);
  If(App)Then HOut:=CreateFileA(@NB,$40000000,1,0,4,$80,0)
         Else HOut:=CreateFileA(@NB,$40000000,1,0,2,$80,0);
  If HOut=-1Then Begin
   If HIn<>-1Then CloseHandle(HIn);
   RunRedir:=5;
   Exit;
  End;
  If(App)Then SetFilePointer(HOut,0,0,2);
 End;
 FillChar(SI,SizeOf(SI),0);
 SI[0]:=68;
 SI[11]:=$100;
 If HIn<>-1Then SI[14]:=HIn Else SI[14]:=GetStdHandle(-10);
 If HOut<>-1Then SI[15]:=HOut Else SI[15]:=GetStdHandle(-11);
 SI[16]:=SI[15];
 FillChar(PI,SizeOf(PI),0);
 { "programme" parametres }
 S:='"'+Prog+'"';
 L:=0;
 For K:=1 to Length(S)do Begin
  Cmd[L]:=S[K];
  Inc(L);
 End;
 If Args<>''Then Begin
  Cmd[L]:=' ';
  Inc(L);
  For K:=1 to Length(Args)do Begin
   Cmd[L]:=Args[K];
   Inc(L);
  End;
 End;
 Cmd[L]:=#0;
 If CreateProcessA(Nil,@Cmd,0,0,1,0,Nil,Nil,@SI,@PI)=0Then
  RunRedir:=GetLastError
 Else Begin
  WaitForSingleObject(PI[0],-1);
  Code:=0;
  GetExitCodeProcess(PI[0],@Code);
  ErrLevel:=Code;
  CloseHandle(PI[1]);
  CloseHandle(PI[0]);
 End;
 If HIn<>-1Then CloseHandle(HIn);
 If HOut<>-1Then CloseHandle(HOut);
End;

Procedure UnknownCommand;
Var
 Err:Word;
Begin
 { HELP : l'aide des commandes (FASTHELP) }
 If CurrCommand='HELP'Then CurrCommand:='FASTHELP';
 If(RedirIn<>'')or(RedirOut<>'')Then
  Err:=RunRedir(CurrCommand,ParamList,RedirIn,RedirOut,RedirApp)
 Else Begin
  Exec(CurrCommand,ParamList);
  Err:=DosError;
  If Err=0Then ErrLevel:=DosExitCode;
 End;
 Case Err of
  0:;
  2,3:If(RedirIn<>'')and Not(FileExist(RedirIn))Then
   WriteLn('Fichier introuvable : ',RedirIn)
  Else
   WriteLn('Commande ou nom de fichier non reconnu');
  Else Write(GetErrorMessage(Err));
 End;
 If(BatLevel=0)and Not(PipeLeft)Then WriteLn;
End;

{ Parametres %0 a %9, variables %NOM% et %% d'une ligne }
Function BatExpand(S:String;L:Byte):String;
Var
 R,V:String;
 K,P,N:Integer;
Begin
 R:='';
 K:=1;
 While K<=Length(S)do Begin
  If(S[K]='%')and(K<Length(S))Then Begin
   If S[K+1]='%'Then Begin
    R:=R+'%';
    Inc(K,2);
   End
    Else
   If S[K+1]in['0'..'9']Then Begin
    N:=Ord(S[K+1])-48;
    If N>0Then N:=N+BatShift[L];
    If N<BatArgN[L]Then R:=R+BatGetArg(L,N);
    Inc(K,2);
   End
    Else
   Begin
    P:=K+1;
    While(P<=Length(S))and(S[P]<>'%')do Inc(P);
    If P<=Length(S)Then Begin
     V:=Copy(S,K+1,P-K-1);
     R:=R+EnvGet(V);
     K:=P+1;
    End
     Else
    Begin
     R:=R+'%';
     Inc(K);
    End;
   End;
  End
   Else
  Begin
   R:=R+S[K];
   Inc(K);
  End;
 End;
 BatExpand:=R;
End;

{ Executer le fichier de traitement par lots Name avec ses parametres }
Procedure RunBatch(Name,Args:String);
Var
 F:Text;
 L:Byte;
 K:Integer;
 O:LongInt;
 S:String;
 Silent:Boolean;
Begin
 If BatLevel>=MaxBatLevel Then Begin
  WriteLn('Limite de ',MaxBatLevel,
          ' fichiers de traitement par lots imbriques');
  Exit;
 End;
 Assign(F,Name);
 {$I-}Reset(F);{$I+}
 If IOResult<>0Then Begin
  WriteLn('Probleme de lecture du fichier de traitement par lot');
  Exit;
 End;
 If BatLevel=0Then TopEcho:=Echo;
 Inc(BatLevel);
 L:=BatLevel;
 BatN[L]:=0;
 O:=(L-1)*BatBufSz;
 While Not EOF(F)and(BatN[L]<MaxBatLines)do Begin
  ReadLn(F,S);
  If O+Length(S)+1>L*BatBufSz Then Break;
  BatOfs[(L-1)*MaxBatLines+BatN[L]]:=O;
  Inc(BatN[L]);
  BatBuf[O]:=Chr(Length(S));
  For K:=1 to Length(S)do BatBuf[O+K]:=S[K];
  O:=O+Length(S)+1;
 End;
 Close(F);
 BatArg[(L-1)*MaxBatArgs]:=Name;
 BatArgN[L]:=1;
 While(Args<>'')and(BatArgN[L]<MaxBatArgs)do Begin
  BatArg[(L-1)*MaxBatArgs+BatArgN[L]]:=NextWord(Args);
  Inc(BatArgN[L]);
 End;
 BatShift[L]:=0;
 BatPc[L]:=1;
 While(BatPc[L]<=BatN[L])and Not(Terminated)do Begin
  S:=TrimL(BatGetLine(L,BatPc[L]));
  Inc(BatPc[L]);
  If(S='')or(S[1]=':')Then Continue;
  Silent:=S[1]='@';
  If Silent Then S:=TrimL(Copy(S,2,255));
  S:=BatExpand(S,L);
  If S=''Then Continue;
  If Echo and Not(Silent)Then WriteLn(S);
  CmdStr:=S;
  RunCommand;
 End;
 Dec(BatLevel);
 If BatLevel=0Then Echo:=TopEcho;
End;

{ Position du premier caractere C hors des guillemets (0 : absent) }
Function PosOut(C:Char;Const S:String):Integer;
Var
 K:Integer;
 Q:Boolean;
Begin
 PosOut:=0;
 Q:=False;
 For K:=1 to Length(S)do Begin
  If S[K]='"'Then Q:=Not(Q)Else
  If(S[K]=C)and Not(Q)Then Begin
   PosOut:=K;
   Exit;
  End;
 End;
End;

{ Retirer de S les redirections <fichier, >fichier et >>fichier }
Procedure Redirect(Var S:String);
Var
 K,E:Integer;
 C:Char;
 F:String;
Begin
 Repeat
  K:=PosOut('>',S);
  E:=PosOut('<',S);
  If(E>0)and((K=0)or(E<K))Then K:=E;
  If K>0Then Begin
   C:=S[K];
   E:=K+1;
   If(C='>')and(E<=Length(S))and(S[E]='>')Then Begin
    RedirApp:=True;
    Inc(E);
   End
    Else
   If C='>'Then RedirApp:=False;
   While(E<=Length(S))and(S[E]=' ')do Inc(E);
   F:='';
   While(E<=Length(S))and Not(S[E]in[' ','<','>'])do Begin
    If S[E]<>'"'Then F:=F+S[E];
    Inc(E);
   End;
   If C='<'Then RedirIn:=F Else RedirOut:=F;
   Delete(S,K,E-K);
  End;
 Until K=0;
 S:=TrimR(S);
End;

{ Fichier temporaire d'un tuyau : dans TEMP, ou ailleurs si TEMP n'est
  pas accessible en ecriture (TEMP=D:\ sur le CD-ROM) }
Function PipeName:String;
Var
 T,N,R:String;
 K:Integer;
 F:File;
Begin
 Inc(PipeNum);
 Str(PipeNum,N);
 For K:=0 to 3 do Begin
  Case K of
   0:T:=EnvGet('TEMP');
   1:T:='C:\TEMP';
   2:T:='C:\';
   Else T:=GetCurrentDisk+':\';
  End;
  If T<>''Then Begin
   If T[Length(T)]<>'\'Then T:=T+'\';
   R:=T+'PIPE'+N+'.TMP';
   Assign(F,R);
   {$I-}Rewrite(F,1);{$I+}
   If IOResult=0Then Begin
    Close(F);
    PipeName:=R;
    Exit;
   End;
  End;
 End;
 PipeName:=R;
End;

Procedure DelFile(Const N:String);
Var
 F:File;
Begin
 Assign(F,N);
 {$I-}Erase(F);{$I+}
 If IOResult<>0Then;
End;

{ Une commande sans tuyau (ses redirections dans RedirIn, RedirOut) }
Procedure RunSimple;
Var
 BatchName:String;
 Err:Word;
Begin
 ExtractCommand;
 CommandFound:=False;
 For J:=Low(CommandList) to High(CommandList) do
  If CurrCommand=CommandList[J]Then Begin
   CommandFound:=True;
   Break;
  End;
 If(CommandFound)Then Begin
  { commande interne : sortie dans PipeFile (DIR, TYPE, ECHO, DATE...) }
  If RedirOut<>''Then Begin
   Assign(PipeFile,RedirOut);
   {$I-}
   If(RedirApp)Then Begin
    Append(PipeFile);
    If IOResult<>0Then Rewrite(PipeFile);
   End
    Else
   Rewrite(PipeFile);
   {$I+}
   Err:=IOResult;
   If Err<>0Then Begin
    WriteLn(GetErrorMessage(Err));
    Exit;
   End;
   Pipe:=True;
  End;
  Case(J)of
   0:BreakCommand;
   1:CallCommand;
   2:ChDirCommand;
   3:CHCPCommand;
   4:ChDirCommand;
   5:CLSCommand;
   6:CopyCommand;
   7:CTTYCommand;
   8:DeleteCommand;
   9:DeleteCommand;
   10:DirCommand;
   11:EchoCommand;
   12:EraseCommand;
   13:EraseCommand;
   14:Terminated:=ExitCommand;
   15:ForCommand;
   16:IfCommand;
   17:LoadHighCommand;
   18:MkDirCommand;
   19:MkDirCommand;
   20:PathCommand;
   21:PauseCommand;
   22:PromptCommand;
   23:RmDirCommand;
   24:RemCommand;
   25:RenameCommand;
   26:RenameCommand;
   27:RmDirCommand;
   28:SetCommand;
   29:ShiftCommand;
   30:TimeCommand;
   31:TrueNameCommand;
   32:TypeCommand;
   33:VerCommand;
   34:VerifyCommand;
   35:VolCommand;
   36:DateCommand;
   37:TimeOutCommand;
   38:GotoCommand;
  End;
  If(Pipe)Then Begin
   Close(PipeFile);
   Pipe:=False;
  End
   Else
  If BatLevel=0Then WriteLn;
  Exit;
 End;
 { fichier de traitement par lots : NOM ou NOM.BAT (sans les
   parametres de la ligne) }
 BatchName:=BatchOf(CurrCommand);
 If CmdStr='?'Then Begin
  For I:=Low(CommandList) to High(CommandList)
    do Write(PadRight(CommandList[I],10));
  WriteLn;
  WriteLn;
 End
  Else
 If BatchName<>''Then Begin
  { sans CALL, le fichier appelant ne reprend pas }
  If BatLevel>0Then BatPc[BatLevel]:=BatN[BatLevel]+1;
  RunBatch(BatchName,ParamList);
 End
  Else
 UnknownCommand;
End;

Procedure RunCommand;
Var
 Error:Word;
 S,Rest,T,TIn:String;
 K:Integer;
Begin
 CmdStr:=TrimL(CmdStr);
 If(CmdStr<>'')and(CmdStr[1]='@')Then CmdStr:=TrimL(Copy(CmdStr,2,255));
 If CmdStr=''Then Exit;
 If(BatLevel=0)and Not(NoHist)Then AddHistory(CmdStr);
 TIn:=PipeIn;
 PipeIn:='';
  { Change d'unite de disque A:, B:, C:, D:,... }
 If(Length(CmdStr)=2)and(CmdStr[2]=':')and(CmdStr[1]in['A'..'Z',
   'a'..'z'])Then Begin
  {$I-}GetDir(Ord(UpCase(CmdStr[1]))-64,S);
  If S<>''Then ChDir(S)
          Else ChDir(CmdStr+'\');{$I+}
  Error:=IoResult;
  If Error<>0Then WriteLn(GetErrorMessage(Error));
  Exit;
 End;
 { tuyau : la commande de gauche ecrit dans un fichier temporaire, lu
   comme entree standard par la commande de droite }
 K:=PosOut('|',CmdStr);
 Rest:='';
 If K>0Then Begin
  Rest:=TrimL(Copy(CmdStr,K+1,255));
  CmdStr:=TrimR(Copy(CmdStr,1,K-1));
 End;
 RedirIn:=TIn;RedirOut:='';RedirApp:=False;
 Redirect(CmdStr);
 T:='';
 If Rest<>''Then Begin
  T:=PipeName;
  RedirOut:=T;
  RedirApp:=False;
 End;
 PipeLeft:=Rest<>'';
 RunSimple;
 PipeLeft:=False;
 If(Rest<>'')and Not(Terminated)Then Begin
  { la commande de droite ne s'ajoute pas a l'historique }
  PipeIn:=T;
  CmdStr:=Rest;
  NoHist:=True;
  RunCommand;
  NoHist:=False;
 End;
 If T<>''Then DelFile(T);
End;

Function PopupHistory:String;
Var
 K:Char;
 I:Byte;
 P,Y:LongInt;

 Procedure ShowItem;Begin
  TextColor($F);
  TextBackground($D);
  GotoXY(24,3+Y);
  Write(P,': ',PadRight(Copy(History[P]^,1,30),30));
  GotoXY(24,3+Y);
 End;

 Procedure HideItem;Begin
  TextColor($D+BLINK);
  TextBackground($7);
  GotoXY(24,3+Y);
  Write(P,': ',PadRight(Copy(History[P]^,1,30),30));
 End;

 Procedure RefreshList;
 Var
  J:Byte;
 Begin
  TextColor($D);
  TextBackground($F);
  For J:=1 to 19 do Begin
   GotoXY(24,2+J);
   Write(P,': ',PadRight(Copy(History[P-Y+J-1]^,1,30),30));
  End;
 End;

Begin
 PCopy(0,1);
 P:=1;Y:=0;
 PopupHistory:='';
 If NumberHistory<20 Then Begin
  Box(22,2,58,NumberHistory+3,$FD);
  FrameEmpty(22,2,58,NumberHistory+3,$FD);
 End
  Else
 Begin
  Box(22,2,58,22,$FD);
  FrameEmpty(22,2,58,22,$FD);
 End;
 For I:=1 to NumberHistory do Begin
  If I>=20 Then Break;
  GotoXY(24,2+I);
  Write(I,': ',History[I]^);
 End;
 ShowItem;
 Repeat
  K:=ReadKey;
  Case K of
   #0:Case ReadKey of
    #72:If P>1 Then Begin { Up }
     HideItem;
     Dec(P);
     If Y>0 Then Dec(Y)
            Else RefreshList;
     ShowItem;
    End;
    #80:If P<NumberHistory Then Begin { Down }
     HideItem;
     Inc(P);
     If Y<18 Then Inc(Y)
             Else RefreshList;
     ShowItem;
    End;
   End;
   #13:Begin
    PopupHistory:=History[P]^;
    Break;
   End;
  End;
 Until K=#27;
 If NumberHistory<20 Then Begin
  Box(22,2,58,NumberHistory+3,$07);
 End
  Else
 Box(22,2,58,22,$07);
 PCopy(1,0);
End;

Procedure ReadLine(Var S:String);
Var
 Rec:SearchRec;
 K:Char;
 X,Y,I:Byte;
 CurrHistory:Integer;
Begin
 CurrHistory:=NumberHistory;
 X:=WhereX;
 Y:=WhereY;
 S:='';
 Repeat
  GotoXY(X,Y);
  Write(S);
  ClrEol;
  K:=ReadKey;
  Case K of
   #0:Case ReadKey of
    #61:If NumberHistory>0 Then Begin { F3 }
     S:=History[NumberHistory]^;
    End;
    #72:If NumberHistory>0 Then Begin
     S:=History[CurrHistory]^; { Up }
     If CurrHistory>1 Then Dec(CurrHistory);
    End;
    #65:If NumberHistory>0 Then Begin { F7 }
     S:=PopupHistory;
    End;
    #80:If NumberHistory>0 Then Begin
     S:=History[CurrHistory]^; { Down }
     If CurrHistory<NumberHistory Then Inc(CurrHistory);
    End;
   End;
   #8:Begin
    If S<>''Then S:=Copy(S,1,Length(S)-1);
   End;
   #9:If S<>''Then Begin
    For I:=Length(S) downto 1 do Begin
     If S[I]=' 'Then Begin
      FindFirst(Copy(S,I+1,255)+'*.*',AnyFile,Rec);
      If DosError=0 Then Begin
       S:=Copy(S,1,I)+Rec.Name;
      End;
      Break;
     End;
    End;
   End;
   Else S:=S+K;
  End;
  If S[Length(S)]=#13Then Begin
   S:=Copy(S,1,Length(S)-1);
   K:=#13;
  End;
 Until K=#13;
 GotoXY(X,Y);
 WriteLn(S);
End;

BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
  {$ENDIF}
 {$ENDIF}
 Language:=_French;
 TmpLanguage:=EnvGet('LANGUAGE');
 If TmpLanguage<>''Then Begin
  If TmpLanguage[1]='"'Then TmpLanguage:=Copy(TmpLanguage,2,255);
  If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English Else
  If StrToUpper(Copy(TmpLanguage,1,2))='GR'Then Language:=_Germany Else
  If StrToUpper(Copy(TmpLanguage,1,2))='IT'Then Language:=_Italian Else
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain;
 End;
 ShowASCII128:=False;
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
  {$ELSE}
   ShowASCII128:=True;
  {$ENDIF}
 {$ENDIF}
 FillChar(History,SizeOf(History),0);
 NumberHistory:=0;
 Echo:=True;Pipe:=False;PipeToCommand:=False;
 RedirIn:='';RedirOut:='';PipeIn:='';PipeNum:=0;
 NoHist:=False;PipeLeft:=False;
 InCmd:=0;
 BatLevel:=0;ErrLevel:=0;TopEcho:=True;
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')Then Begin
  Case Language of
   _Germany:Begin
    WriteLn('CMD : Startet eine neue Kopie des Befehlsinterpreters.');
    WriteLn;
    WriteLn('CMD [/C Befehl]');
   End;
   _English:Begin
    WriteLn('CMD : Start a new copy of the Command Interpreter.');
    WriteLn;
    WriteLn('Syntax : CMD [/C command]');
   End;
   Else Begin
    WriteLn('CMD : Cette commande permet de lancer l''interpreteur de '+
      'commande.');
    WriteLn;
    WriteLn('Syntaxe : CMD [/C command]');
   End;
  End;
 End
  Else
 If ParamCount>1Then Begin
  Option:=optNone;
  For I:=1 to ParamCount do Begin
   If(Option=optCommand)Then Begin
    CmdStr:=ParamStr(I);
    RunCommand;
    Option:=optNone;
   End
    Else
   If StrToUpper(ParamStr(I))='/C'Then Option:=optCommand
    Else
   Begin
    WriteLn('Parametre non reconnu : ',ParamStr(I));
   End;
  End;
 End
  Else
 Begin
  Terminated:=False;
  If StrToUpper(ParamStr(1))<>'/R'Then HomeMessage;
  Repeat
   ShowPrompt;
   ReadLine(CmdStr);
   RunCommand;
  Until Terminated;
 End;
END.
