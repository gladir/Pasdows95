{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2025
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program UNDELETE;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
Uses Crt,DOS;

Const
 SECTOR_SIZE=512;
 MAX_PATH=64;
 DELETED_MARKER=$E5;

Type
 TSector=Array[0..SECTOR_SIZE-1] of Byte;
 TFatEntry=Word;

 TDirEntry=Record
  Name:Array[0..7] of Char;
  Ext:Array[0..2] of Char;
  Attr:Byte;
  Reserved:Array[0..9] of Byte;
  Time:Word;
  Date:Word;
  StartCluster:Word;
  Size:LongInt;
 End;

Var
 DiskFile:File;
 BootSector:TSector;
 FATSector:Array[0..9] of TSector; { Maximum de 10 secteurs par FAT }
 RootDir:Array[0..32] of TSector;  { Maximum de 32 secteurs de rÇpertoire racine }
 SectorsPerCluster:Byte;
 ReservedSectors:Word;
 NumberOfFATs:Byte;
 RootEntries:Word;
 SectorsPerFAT:Word;
 FirstDataSector:Word;

{$IFDEF WINDOWS}
{ Pasdows (Win32) : secteurs de l'unite courante par le volume \\.\X:
  (lecture seule : le noyau refuse l'ecriture directe) }
Function CreateFileA(N:Pointer;Acc,Sh,Sa,Disp,Fl,T:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'CreateFileA';
Function SetFilePointer(H,D,P,M:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'SetFilePointer';
Function ReadFile(H:LongInt;B:Pointer;N:LongInt;R:Pointer;
 O:LongInt):LongInt;stdcall;external 'kernel32.dll' name 'ReadFile';
Function CloseHandle(H:LongInt):LongInt;stdcall;
 external 'kernel32.dll' name 'CloseHandle';

Function ReadSector(Drive:Byte;Sector:Word;Var Buffer:TSector):Boolean;
Var
 N:Array[0..7]of Char;
 D:String;
 H,Got:LongInt;
Begin
 ReadSector:=False;
 GetDir(0,D);
 N[0]:='\';N[1]:='\';N[2]:='.';N[3]:='\';N[4]:=UpCase(D[1]);
 N[5]:=':';N[6]:=#0;
 H:=CreateFileA(@N,LongInt($80000000),3,0,3,0,0);
 If H=-1Then Exit;
 SetFilePointer(H,LongInt(Sector)*SECTOR_SIZE,0,0);
 Got:=0;
 If ReadFile(H,@Buffer,SECTOR_SIZE,@Got,0)<>0Then
  ReadSector:=Got=SECTOR_SIZE;
 CloseHandle(H);
End;

Function WriteSector(Drive:Byte;Sector:Word;Var Buffer:TSector):Boolean;
Begin
 WriteLn('L''',#130,'criture directe sur le disque n''est pas permise ',
         'sous Pasdows.');
 WriteSector:=False;
End;
{$ELSE}
Function ReadSector(Drive:Byte;Sector:Word;Var Buffer:TSector):Boolean;
Var
 Regs:Registers;
Begin
 Regs.AH:=$02;  { Lecture de secteurs }
 Regs.AL:=1;    { Nombre de secteurs }
 Regs.CH:=Sector shr 8;   { Piste }
 Regs.CL:=(Sector and $FF) + 1;  { Secteur }
 Regs.DH:=0;    { Tàte }
 Regs.DL:=Drive;{ UnitÇ de disque }
 Regs.ES:=Seg(Buffer);
 Regs.BX:=Ofs(Buffer);
 Intr($13,Regs);
 ReadSector:=(Regs.Flags and 1)=0;
End;

Function WriteSector(Drive:Byte;Sector:Word;Var Buffer:TSector):Boolean;
Var
 Regs:Registers;
Begin
 Regs.AH:=$03;  { êcriture de secteurs }
 Regs.AL:=1;    { Nombre de secteurs }
 Regs.CH:=Sector shr 8;   { Piste }
 Regs.CL:=(Sector and $FF) + 1;  { Secteur }
 Regs.DH:=0;    { Tàte }
 Regs.DL:=Drive;{ UnitÇ de disque }
 Regs.ES:=Seg(Buffer);
 Regs.BX:=Ofs(Buffer);
 Intr($13,Regs);
 WriteSector:=(Regs.Flags and 1) = 0;
End;

{$ENDIF}

Function ReadBootSector(Drive:Byte):Boolean;Begin
 ReadBootSector:=False;
 If ReadSector(Drive,0,BootSector)Then Begin
  SectorsPerCluster:=BootSector[13];
  ReservedSectors:=BootSector[14] + (BootSector[15] shl 8);
  NumberOfFATs:=BootSector[16];
  RootEntries:=BootSector[17] + (BootSector[18] shl 8);
  { FAT32, NTFS, HPFS : pas de repertoire racine fixe }
  If(RootEntries=0)or(SectorsPerCluster=0)Then Begin
   WriteLn('UNDELETE ne prend en charge que les volumes FAT12 et FAT16.');
   Exit;
  End;
  SectorsPerFAT:=BootSector[22] + (BootSector[23] shl 8);
  FirstDataSector:=ReservedSectors + (NumberOfFATs * SectorsPerFAT) +
                    ((RootEntries * 32 + SECTOR_SIZE - 1) div SECTOR_SIZE);
  ReadBootSector:=True;
 End;
End;

Function FindDeletedFile(Const Mask:String;Var Entry:TDirEntry;Var Sector,Offset:Word):Boolean;
Var
 i,j:Word;
 DirSector:TSector;
Begin
 FindDeletedFile:=False;
 For i:=0 to (RootEntries*32 div SECTOR_SIZE)-1 do Begin
  If Not ReadSector(0,ReservedSectors+(NumberOfFATs*SectorsPerFAT)+i,DirSector)Then Exit;
  For j:=0 to (SECTOR_SIZE div SizeOf(TDirEntry))-1 do Begin
   Move(DirSector[j * SizeOf(TDirEntry)],Entry,SizeOf(TDirEntry));
   If Entry.Name[0]=Chr(DELETED_MARKER)Then Begin
     { VÇrifier si le fichier correspond au masque }
    If(Mask='*.*')or(Mask=Entry.Name)Then Begin
     Sector:=i;
     Offset:=j*SizeOf(TDirEntry);
     FindDeletedFile:=True;
     Exit;
    End;
   End;
  End;
 End;
End;

Function RestoreFile(Var Entry:TDirEntry;Sector,Offset:Word):Boolean;
Var
 DirSector:TSector;
 FirstChar:Char;
Begin
 RestoreFile:=False;

 Write('Remplace la premiäre lettre ''',Chr(DELETED_MARKER),
        ''' dans ''',Entry.Name,''' par quel lettre ? ');
 ReadLn(FirstChar);
 if FirstChar = #13 then Exit;

  { Lire le secteur contenant l'entrÇe }
 If Not ReadSector(0,ReservedSectors+(NumberOfFATs*SectorsPerFAT)+Sector,DirSector)Then
  Exit;

  { Restaurer le premier caractäre du nom }
 If Entry.Name[0]=Chr(DELETED_MARKER)Then Entry.Name[0]:=FirstChar;

  { êcrire l'entrÇe mise Ö jour }
 Move(Entry, DirSector[Offset], SizeOf(TDirEntry));
 RestoreFile:=WriteSector(0,ReservedSectors+(NumberOfFATs*SectorsPerFAT)+Sector,DirSector);
End;

Var
 FileName:String;
 Entry:TDirEntry;
 Sector,Offset:Word;

BEGIN
 If(ParamStr(1)='/?')or(ParamStr(1)='--help')or(ParamStr(1)='-h')or
   (ParamStr(1)='/h')or(ParamStr(1)='/H')Then Begin
  WriteLn('UNDELETE : Cette commande permet de rÇcupÇrer des fichiers supprimÇs');
  WriteLn;
  WriteLn('Syntaxe : UNDELETE [drive:][path]filename');
  WriteLn('          UNDELETE [drive:][path]*.*');
  Halt;
 End;
 FileName:=ParamStr(1);
 If Not ReadBootSector(0)Then Begin
  WriteLn('Erreur de lecture du secteur de dÇmarrage');
  Exit;
 End;
 While FindDeletedFile(FileName,Entry,Sector,Offset)do Begin
  Write('Restaure ', Entry.Name, '.', Entry.Ext, '? (O/N) ');
  If UpCase(ReadKey)in['O','Y']Then Begin
   WriteLn;
   If RestoreFile(Entry, Sector, Offset)Then
    WriteLn('Fichier restaurÇ avec succäs')
   Else
    WriteLn('Erreur de restauration de fichier');
  End;
  WriteLn;
 End;
END.
