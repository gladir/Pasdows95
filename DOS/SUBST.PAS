{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2022
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program SUBST;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
Uses DOS;

Var
 CurrentDrive:String;
 DriveName:String;
 C:Char;

Function ResolvePath(Var S:String):Boolean;
Var
 Regs:Registers;
 X:Byte;
Begin
 ResolvePath:=False;
 S:=S+#0;
 Regs.DS:=Seg(S);
 Regs.SI:=Word(Ofs(S))+1;
 Regs.ES:=Seg(S);
 Regs.DI:=Word(Ofs(S))+1;
 Regs.AH:=$60;
 Intr($21,Regs);
 If Regs.Flags and 1 = 1 Then Exit; { Si CF est fix‚ alors }
 ResolvePath:=True;
 X:=0;
 While(S[X+1]<>#0)and(X<128)do Inc(X);
 S[0]:=Chr(X);
End;

Procedure SubstituteDrive(Drive:Char;Path:String);
Var
 Regs:Registers;
 DriveNum:Byte;
Begin
 Path:=Path+#0;
 DriveNum:=Ord(UpCase(Drive))-Ord('A');
 Regs.AX:=$71AA;
 Regs.BX:=DriveNum;
 Regs.DS:=Seg(Path[1]);
 Regs.SI:=Ofs(Path[1]);
 Regs.CX:=Length(Path);
 Regs.DL:=0;
 Intr($21,Regs);
 If Regs.Flags and FCarry<>0Then WriteLn('Erreur lors de la substitution de lecteur.')
                            Else WriteLn('Substitution de l''unit‚ de disque r‚ussie : ',Drive,' -> ',Path);
End;

{$IFDEF WINDOWS}
{ Pasdows (Win32) : DefineDosDeviceA et QueryDosDeviceA du noyau }
Function DefineDosDeviceA(F:LongInt;D,T:Pointer):LongInt;stdcall;
 external 'kernel32.dll' name 'DefineDosDeviceA';
Function QueryDosDeviceA(D,B:Pointer;N:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'QueryDosDeviceA';

Procedure WinSubst(Drive:Char;Path:String;Remove:Boolean);
Var
 D:Array[0..2]of Char;
 T:Array[0..255]of Char;
 K:Integer;
 Info:SearchRec;
Begin
 D[0]:=UpCase(Drive);D[1]:=':';D[2]:=#0;
 If Not(Remove)Then Begin
  Path:=FExpand(Path);
  If(Length(Path)>3)and(Path[Length(Path)]='\')Then
   Delete(Path,Length(Path),1);
  If Length(Path)>3Then Begin
   FindFirst(Path,Directory,Info);
   If(DosError<>0)or((Info.Attr and Directory)=0)Then Begin
    WriteLn('Chemin introuvable - ',Path);
    Halt(1);
   End;
   FindClose(Info);
  End;
 End;
 For K:=1 to Length(Path)do T[K-1]:=Path[K];
 T[Length(Path)]:=#0;
 If Remove Then K:=DefineDosDeviceA(2,@D,Nil)
           Else K:=DefineDosDeviceA(0,@D,@T);
 If K=0Then WriteLn('Erreur lors de la substitution de lecteur.');
End;

Procedure WinList;
Var
 L:Array[0..127]of Char;
 T:Array[0..255]of Char;
 D:Array[0..2]of Char;
 I,K:Integer;
 S:String;
Begin
 If QueryDosDeviceA(Nil,@L,128)=0Then Exit;
 I:=0;
 While(I<120)and(L[I]<>#0)do Begin
  D[0]:=L[I];D[1]:=':';D[2]:=#0;
  If QueryDosDeviceA(@D,@T,256)>0Then Begin
   S:='';K:=4;
   While(K<255)and(T[K]<>#0)do Begin S:=S+T[K];Inc(K);End;
   WriteLn(L[I],':\: => ',S);
  End;
  Inc(I,3);
 End;
End;
{$ENDIF}

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('SUBST : Cette commande permet de cr‚er un disque virtuel ',
                    '… partir d''un r‚pertoire.');
  WriteLn;
  WriteLn('Syntaxe : SUBST [/?]');
  WriteLn('          SUBST drive1: [drive2:]path');
  WriteLn('          SUBST drive1: /D');
  WriteLn;
  WriteLn('  /?            Affiche l''aide sur cette commande.');
  WriteLn(' drive1:        Unit‚ de disque … associ‚');
  WriteLn(' drive2:[path]  Chemin … associ‚');
 End
  Else
 If ParamCount=2 Then Begin
  CurrentDrive:=ParamStr(1);
  If(Length(CurrentDrive)>2)or(Copy(CurrentDrive,2,1)<>':')Then Begin
   WriteLn('Unit‚ de disque de format invalide !');
   Halt(1);
  End;
  {$IFDEF WINDOWS}
   WinSubst(UpCase(CurrentDrive[1]),ParamStr(2),
            (ParamStr(2)='/D')or(ParamStr(2)='/d'));
  {$ELSE}
  SubstituteDrive(UpCase(CurrentDrive[1]),ParamStr(2));
  {$ENDIF}
 End
  Else
 Begin
  {$IFDEF WINDOWS}
   WinList;
  {$ELSE}
  For C:='A' to 'Z'do Begin
   DriveName:=C;
   If(ResolvePath(DriveName))Then Writeln(C,': => ',DriveName);
  End;
  {$ENDIF}
 End;
END.
