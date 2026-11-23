{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2024
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2 (Windows))
}

Program JOIN;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
{$A-}

Uses
 {$IFDEF FPC}
  DOS,Windows,SysUtils;
 {$ELSE}
  DOS,Strings;
 {$ENDIF}

Type
 TCDS=Record
  Reserved1:Array[0..21] of Byte;
  CurrentDir:Array[0..64] of Char;
  Reserved2:Array[0..29] of Byte;
 End;

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
 If Regs.Flags and 1=1 Then Exit; { Si CF est fix‚ alors }
 ResolvePath:=True;
 X:=0;
 While(S[X+1]<>#0)and(X<128)do Inc(X);
 S[0]:=Chr(X);
End;

{$IFDEF FPC}
 { Pasdows (Win32) : un lecteur ne peut pas devenir un repertoire d'un
   autre lecteur (comme sous Windows 95, ou JOIN n'existe plus) ; SUBST
   fait l'inverse }
 Procedure JoinDirectory(Drive:Char;NewDir:String);
 Begin
  WriteLn('JOIN n''est pas pris en charge par Pasdows : ',Drive,': ne peut ',
          'pas devenir ',NewDir,'.');
  WriteLn('Utilisez SUBST pour associer un r'#130'pertoire '#133' une unit'#130,
          ' de disque.');
 End;

 Procedure ListJoins;
 Begin
 End;

{$ELSE}
 Procedure fGetCDS(Drive:Byte; Var CDS:TCDS);
 Var
  Regs:Registers;
  CDSList:Pointer;
 Begin
  Regs.AH:=$52;
  MsDos(Regs);
  CDSList:=Ptr(Regs.ES,Regs.BX);
  CDS:=TCDS(Pointer(Ptr(Seg(CDSList^),Ofs(CDSList^)+Drive*$44))^);
 End;

 Procedure JoinDirectory(Drive:Char;NewDir:String);
 Var
  CDSRecord:TCDS;
 Begin
  fGetCDS(Ord(UpCase(Drive))-Ord('A'),CDSRecord);
  StrPCopy(CDSRecord.CurrentDir,NewDir);
 End;
{$ENDIF}

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('JOIN : Cette commande permet de cr‚er un disque virtuel ',
                    '… partir d''un r‚pertoire.');
  WriteLn;
  WriteLn('Syntaxe : JOIN [/?]');
  WriteLn('          JOIN drive1: [drive2:]path');
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
  JoinDirectory(UpCase(CurrentDrive[1]),ParamStr(2));
 End
  Else
 Begin
  {$IFDEF FPC}
   ListJoins;
  {$ELSE}
   For C:='A' to 'Z'do Begin
    DriveName:=C;
    If(ResolvePath(DriveName))Then Writeln(C,': => ',DriveName);
   End;
  {$ENDIF}
 End;
END.
