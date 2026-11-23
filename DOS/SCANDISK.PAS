{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/msdos0)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
}

Program SCANDISK;


{$R-}  { comme Turbo Pascal (WPC verifie les bornes par defaut) }
{$A-}
{$M 65520,0, 655200}

Uses DOS,Crt;

Const
 MapWidth = 41;
 MapHeight = 15;

Type
 { Structure du secteur de boot (Boot Sector) - Premier secteur d'un disque/partition FAT }
 TBootSector = Record
  JumpCode: Array[0..2] of Byte;     { Code de saut vers le code de boot (EB 3C 90 ou E9 xx xx) }
  OEMName: Array[0..7] of Char;      { Nom du systäme ayant formaÇ le disque (ex: "MSDOS5.0") }
  BytesPerSector: Word;              { Octets par secteur (gÇnÇralement 512) }
  SectorsPerCluster: Byte;           { Secteurs par unitÇ d'allocation (1, 2, 4, 8, 16, 32, 64, 128) }
  ReservedSectors: Word;             { Secteurs rÇservÇs avant la premiäre FAT (gÇÇnralement 1) }
  NumberOfFATs: Byte;                { Nombre de tables FAT (gÇnÇralement 2 pour redondance) }
  RootEntries: Word;                 { Nombre d'entrÇes dans le rÇpertoire racine (FAT12/16 uniquement) }
  TotalSectors: Word;                { Nombre total de secteurs (si < 65536, sinon 0 et utiliser TotalSectorsBig) }
  MediaDescriptor: Byte;             { Descripteur de mÇdia ($F0=disquette, $F8=disque dur, etc.) }
  SectorsPerFAT: Word;               { Secteurs par table FAT }
  SectorsPerTrack: Word;             { Secteurs par piste (gÇomÇtrie physique) }
  NumberOfHeads: Word;               { Nombre de tàtes (gÇomÇtrie physique) }
  HiddenSectors: LongInt;            { Secteurs cachÇs avant la partition (MBR) }
  TotalSectorsBig: LongInt;          { Nombre total de secteurs si TotalSectors = 0 }
 End;

  { EntrÇe de partition dans la table de partition MBR (16 octets) }
 TPartitionEntry = Record
  Status: Byte;                     { êtat: $80 = partition active (bootable), $00 = inactive }
  StartHead: Byte;                  { Tàte de dÇbut (gÇomÇtrie CHS - obsoläte) }
  StartSector: Byte;                { Secteur+cylindre de dÇbut: bits 0-5=secteur (1-63), bits 6-7=cylindre high }
  StartCylinder: Byte;              { Cylindre de dÇbut (bits bas, combinÇ avec StartSector bits 6-7) }
  PartitionType: Byte;              { Type: $01=FAT12, $04=FAT16<32M, $06=FAT16>32M, $0B=FAT32,... }
  EndHead: Byte;                    { Tàte de fin (gÇomÇtrie CHS - obsoläte) }
  EndSector: Byte;                  { Secteur+cylindre de fin: bits 0-5=secteur, bits 6-7=cylindre high }
  EndCylinder: Byte;                { Cylindre de fin (bits bas) }
  RelativeSectors: LongInt;         { Secteur de dÇbut absolu (LBA) de la partition }
  TotalSectors: LongInt;            { Taille de la partition en secteurs }
 End;

  { Master Boot Record (MBR) - Premier secteur d'un disque dur (secteur 0) }
 TMBR = Record
  BootCode: Array[0..445] of Byte;  { Code de boot et donnÇes (446 octets) }
  PartitionTable: Array[0..3] of TPartitionEntry; { Table des 4 partitions primaires (64 octets) }
  Signature: Word;                  { Signature MBR: doit àtre $AA55 (2 octets) }
 End;

 { EntrÇe de rÇpertoire FAT (32 octets) - Structure d'un fichier/dossier }
 TDirEntry = Record
  Name: Array[0..7] of Char;        { Nom du fichier (8 caractäres, complÇtÇ par des espaces) }
  Ext: Array[0..2] of Char;         { Extension (3 caractäres, complÇtÇ par des espaces) }
  Attr: Byte;                       { Attributs:
                                       bit 0=Lecture seule,
                                           1=CachÇ,
                                           2=Systäme,
                                           3=êtiquette de volume,
                                           4=RÇpertoire,
                                           5=Archive }
  Reserved: Array[0..9] of Byte;    { RÇservÇ (NT, temps de crÇation, date d'accäs, cluster high pour FAT32) }
  Time: Word;                       { Heure de modification: bits 15-11=heures, 10-5=minutes, 4-0=secondes/2 }
  Date: Word;                       { Date de modification: bits 15-9=annÇe-1980, 8-5=mois, 4-0=jour }
  StartCluster: Word;               { Cluster de dÇbut du fichier (0 = fichier vide) }
  Size: LongInt;                    { Taille du fichier en octets (0 pour les rÇpertoires) }
 End;

 TErrorType = (etNone, etBadSector, etCrossLinked, etLostChain, etBadFAT, etBadDir);
 TCheckItem = (ciMedia, ciFAT, ciDirectory, ciFileSystem, ciFreeSpace, ciSurface);
 TFATType = (ftFAT12, ftFAT16);

Type
 { Fragments pour Çviter la limite de 65520 octets de Turbo Pascal }
 PFATFragment = ^TFATFragment;
 TFATFragment = Array[0..21845] of Word;  { ~43Ko par fragment }
 PClusterMapFragment = ^TClusterMapFragment;
 TClusterMapFragment = Array[0..32767] of Byte;  { ~32Ko par fragment }

Var
 Language:(_French,_English,_Germany,_Italian,_Spain,_Albanian,_Portuguese,_Swedish,_Danish,_Japanese);
 TmpLanguage, DrivePath, FileName: String;
 BootSector: TBootSector;
 MBR: TMBR;
 PartitionOffset: LongInt;  { DÇcalage en secteurs pour la partition active }
 HasPartition: Boolean;     { Indique si le fichier contient une table de partition }
 { Fragments FAT - 3 fragments de ~43KB chacun }
 FatA, FatB, FatC: PFATFragment;
 RootDir: Array[0..511] of TDirEntry;
 SectorBuffer: Array[0..511] of Byte;
 TotalSectors, BadSectors, LostClusters, CrossLinkedFiles: LongInt;
 { Fragments ClusterMap - 2 fragments de ~32KB chacun }
 ClusterMapA, ClusterMapB: PClusterMapFragment;
 FATType: TFATType;
 MaxClusters: Word;
 FileHandle: File;
 IsImageFile: Boolean;
 AutoFix, CheckOnly, DoSurfaceScan: Boolean;
 DriveNum: Byte;
 DrvSpt, DrvHeads: Word;
 ErrorsFound: Integer;
 CheckStatus: Array[TCheckItem] of Boolean;

Type
 TFsKind = (fsFAT12, fsFAT16, fsFAT32, fsNTFS, fsHPFS);

Var
 FsType: TFsKind;

{$IFDEF WINDOWS}
Procedure W32Debug(P: Pointer); stdcall;
 external 'kernel32.dll' name 'OutputDebugStringA';
{$ENDIF}

{ Trace dans le journal du noyau (port serie COM1 de Pasdows) : etapes,
  touches recues, avancement, pour diagnostiquer un blocage }
Procedure Trace(Const S: String);
{$IFDEF WINDOWS}
Var
 Z: Array[0..255] of Char;
 K: Integer;
Begin
 Z[0] := 'S'; Z[1] := 'D'; Z[2] := ':'; Z[3] := ' ';
 For K := 1 to Length(S) do If K < 250 Then Z[K + 3] := S[K];
 If Length(S) < 250 Then Z[Length(S) + 4] := #0 Else Z[253] := #0;
 W32Debug(@Z);
End;
{$ELSE}
Begin
End;
{$ENDIF}

Function NumS(V: LongInt): String;
Var
 T: String;
Begin
 Str(V, T);
 NumS := T;
End;

{ Texte francais ou anglais (les autres langues prennent l'anglais) }
Function TL(Const Fr, En: String): String;Begin
 If Language = _French Then TL := Fr Else TL := En;
End;

{ Libelles des verifications de NTFS et HPFS ('' : ceux de FAT) }
Function FsItem(I: TCheckItem): String;Begin
 FsItem := '';
 If FsType = fsNTFS Then Begin
  Case I of
   ciMedia: FsItem := TL('Secteur d''amorce', 'Boot sector');
   ciFAT: FsItem := TL('Table des fichiers (MFT)', 'Master file table (MFT)');
   ciDirectory: FsItem := TL('Index des r'#130'pertoires', 'Directory indexes');
   ciFileSystem: FsItem := TL('Bitmap de la MFT', 'MFT bitmap');
   ciFreeSpace: FsItem := TL('Espace libre ($Bitmap)', 'Free space ($Bitmap)');
  End;
 End
  Else
 If FsType = fsHPFS Then Begin
  Case I of
   ciMedia: FsItem := TL('Superbloc et bloc de r'#130'serve', 'Super block and spare block');
   ciFAT: FsItem := TL('Bitmaps d''allocation', 'Allocation bitmaps');
   ciDirectory: FsItem := TL('R'#130'pertoires, fnodes et fichiers', 'Directories, fnodes and files');
   ciFileSystem: FsItem := TL('Bande des r'#130'pertoires', 'Directory band');
   ciFreeSpace: FsItem := TL('Espace libre (bitmaps)', 'Free space (bitmaps)');
  End;
 End;
End;

{$IFNDEF FPC}
 Procedure CursorOff;
 Var
  Regs:Registers;
 Begin
  Regs.AH:=1;
  Regs.CH:=32;
  Regs.CL:=0;
  Intr($10,Regs);
 End;

 Procedure CursorOn;
 Var
  Regs:Registers;
 Begin
  Regs.AX:=$0100;
  Regs.CX:=(7 shl 8)+9;
  Intr($10,Regs);
 End;
{$ENDIF}

Function StrToUpper(S: String): String;
Var
 I: Byte;
Begin
 For I := 1 to Length(S) do Begin
  If S[I] in ['a'..'z'] Then S[I] := Chr(Ord(S[I]) - 32);
 End;
 StrToUpper := S;
End;

{ Fonctions d'accäs transparentes pour les tableaux fragmentÇs }
Function GetFAT(Index: Word): Word;Begin
 If Index <= 21845 Then Begin
  If FatA <> nil Then GetFAT := FatA^[Index] Else GetFAT := 0;
 End Else If Index <= 43691 Then Begin
  If FatB <> nil Then GetFAT := FatB^[Index - 21846] Else GetFAT := 0;
 End Else Begin
  If FatC <> nil Then GetFAT := FatC^[Index - 43692] Else GetFAT := 0;
 End;
End;

Procedure SetFAT(Index: Word; Value: Word);Begin
 If Index <= 21845 Then Begin
  If FatA <> nil Then FatA^[Index] := Value;
 End
  Else
 If Index <= 43691 Then Begin
  If FatB <> nil Then FatB^[Index - 21846] := Value;
 End
  Else
 Begin
  If FatC <> nil Then FatC^[Index - 43692] := Value;
 End;
End;

Function GetClusterMap(Index: Word): Byte;Begin
 If Index <= 32767 Then Begin
  If ClusterMapA <> nil Then GetClusterMap := ClusterMapA^[Index] Else GetClusterMap := 0;
 End
  Else
 Begin
  If ClusterMapB <> nil Then GetClusterMap := ClusterMapB^[Index - 32768] Else GetClusterMap := 0;
 End;
End;

Procedure SetClusterMap(Index: Word; Value: Byte);Begin
 If Index <= 32767 Then Begin
  If ClusterMapA <> nil Then ClusterMapA^[Index] := Value;
 End Else Begin
  If ClusterMapB <> nil Then ClusterMapB^[Index - 32768] := Value;
 End;
End;

{ Fonctions d'accäs pour FAT2 temporaire }
Function GetFAT2(Index: Word; Fat2A, Fat2B, Fat2C: PFATFragment): Word;Begin
 If Index <= 21845 Then Begin
  If Fat2A <> nil Then GetFAT2 := Fat2A^[Index] Else GetFAT2 := 0;
 End Else If Index <= 43691 Then Begin
  If Fat2B <> nil Then GetFAT2 := Fat2B^[Index - 21846] Else GetFAT2 := 0;
 End Else Begin
  If Fat2C <> nil Then GetFAT2 := Fat2C^[Index - 43692] Else GetFAT2 := 0;
 End;
End;

Procedure SetFAT2(Index: Word; Value: Word; Fat2A, Fat2B, Fat2C: PFATFragment);Begin
 If Index <= 21845 Then Begin
  If Fat2A <> nil Then Fat2A^[Index] := Value;
 End Else If Index <= 43691 Then Begin
  If Fat2B <> nil Then Fat2B^[Index - 21846] := Value;
 End Else Begin
  If Fat2C <> nil Then Fat2C^[Index - 43692] := Value;
 End;
End;

Function Min(A, B: Integer): Integer;Begin
 If A < B Then Min := A Else Min := B;
End;

Function IntToStr(Value: Integer): String;
Var
 S: String;
Begin
 Str(Value, S);
 IntToStr := S;
End;

Function IntToHex(Value: Integer; Digits: Integer): String;
Const
 HexDigits: String[16] = '0123456789ABCDEF';
Var
 S: String;
 i: Integer;
Begin
 S := '';
 If Value = 0 Then Begin
  IntToHex := '0';
  Exit;
 End;
 While Value > 0 do Begin
  S := HexDigits[(Value mod 16) + 1] + S;
  Value := Value div 16;
 End;
  { Ajouter des zÇros Ö gauche si nÇcessaire }
 While Length(S) < Digits do S := '0' + S;
 IntToHex := S;
End;

Procedure AllocateMemory;Begin
  { Allouer la mÇmoire pour les fragments FAT }
 GetMem(FatA, SizeOf(TFATFragment));
 GetMem(FatB, SizeOf(TFATFragment));
 GetMem(FatC, SizeOf(TFATFragment));
  { Allouer la m√©moire pour les fragments ClusterMap }
 GetMem(ClusterMapA, SizeOf(TClusterMapFragment));
 GetMem(ClusterMapB, SizeOf(TClusterMapFragment));
  { VÇrifier les allocations }
 If (FatA = nil) or (FatB = nil) or (FatC = nil) or
    (ClusterMapA = nil) or (ClusterMapB = nil) Then Begin
  Case(Language)of
   _English:Begin
    WriteLn('Error: Not enough memory to allocate FAT tables');
    WriteLn('Required: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bytes');
   End;
   _Germany:Begin
    WriteLn('Fehler: Nicht genug Speicher fÅr FAT-Tabellen');
    WriteLn('Ben√∂tigt: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' Bytes');
   End;
   _Italian:Begin
    WriteLn('Errore: Memoria insufficiente per allocare tabelle FAT');
    WriteLn('Richiesto: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' byte');
   End;
   _Spain:Begin
    WriteLn('Error: Memoria insuficiente para asignar tablas FAT');
    WriteLn('Requerido: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bytes');
   End;
   _Albanian:Begin
    WriteLn('Gabim: Memorje e pamjaftueshme pâr tâ alokuar tabelat FAT');
    WriteLn('E nevojshme: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bajte');
   End;
   _Portuguese:Begin
    WriteLn('Erro: Mem¢ria insuficiente para alocar tabelas FAT');
    WriteLn('Necess√°rio: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bytes');
   End;
   _Swedish:Begin
    WriteLn('Fel: OtillrÑckligt minne fîr att allokera FAT-tabeller');
    WriteLn('KrÑvs: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bytes');
   End;
   _Danish:Begin
    WriteLn('Fejl: Utilstraekkelig hukommelse til at allokere FAT-tabeller');
    WriteLn('Kraevet: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' bytes');
   End;
   _Japanese:Begin
    WriteLn('Erra: FAT teburu no wariate ni juubun na memori ga arimasen');
    WriteLn('Hitsuyou: ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' baito');
   End;
   Else Begin
    WriteLn('Erreur : MÇmoire insuffisante pour allouer les tables FAT');
    WriteLn('Requis : ', (SizeOf(TFATFragment) * 3) + (SizeOf(TClusterMapFragment) * 2), ' octets');
   End;
  End;
  Halt(1);
 End;
  { Initialiser Ö zÇro }
 FillChar(FatA^, SizeOf(TFATFragment), 0);
 FillChar(FatB^, SizeOf(TFATFragment), 0);
 FillChar(FatC^, SizeOf(TFATFragment), 0);
 FillChar(ClusterMapA^, SizeOf(TClusterMapFragment), 0);
 FillChar(ClusterMapB^, SizeOf(TClusterMapFragment), 0);
End;

Procedure FreeMemory;Begin
  { LibÇrer la mÇmoire allouÇe pour FAT }
 If FatA <> nil Then FreeMem(FatA, SizeOf(TFATFragment));
 If FatB <> nil Then FreeMem(FatB, SizeOf(TFATFragment));
 If FatC <> nil Then FreeMem(FatC, SizeOf(TFATFragment));
  { LibÇrer la mÇmoire allouÇe pour ClusterMap }
 If ClusterMapA <> nil Then FreeMem(ClusterMapA, SizeOf(TClusterMapFragment));
 If ClusterMapB <> nil Then FreeMem(ClusterMapB, SizeOf(TClusterMapFragment));
End;

Function DetectFATType: TFATType;
Var
 DataSectors, Clusters: LongInt;
Begin
  { Calculer le nombre de secteurs de donnÇes }
 DataSectors := TotalSectors - (BootSector.ReservedSectors +
                (BootSector.NumberOfFATs * BootSector.SectorsPerFAT) +
                ((BootSector.RootEntries * 32 + 511) div 512));
  { Calculer le nombre de clusters }
 Clusters := DataSectors div BootSector.SectorsPerCluster;
  { DÇterminer le type FAT selon le nombre de clusters }
 If Clusters < 4085 Then Begin
  DetectFATType := ftFAT12;
  MaxClusters := Clusters;
 End
  Else
 Begin
  DetectFATType := ftFAT16;
  If Clusters > 65524 Then Clusters := 65524;
  MaxClusters := Clusters;
 End;
End;

Procedure SetupColors;Begin
 TextBackground(Blue);
 TextColor(White);
 ClrScr;
End;

Procedure ShowButton(Button:String;Selected:Boolean);
Var
 CurrAttr:Byte;
Begin
 CurrAttr:=TextAttr;
 TextBackground(DarkGray);
 TextColor(LightGray);
 If(Selected)Then Write(#17,' ',Button,' ',#16)
             Else Write('< ',Button,' >');
 TextAttr:=CurrAttr;
End;

Procedure DrawBox(X1, Y1, X2, Y2: Byte);
Var
 i: Byte;
Begin
 GotoXY(X1, Y1);
 Write(#218);
 For i := X1 + 1 to X2 - 1 do Write(#196);
 Write(#191);
 For i := Y1 + 1 to Y2 - 1 do Begin
  GotoXY(X1, i); Write(#179);
  GotoXY(X2, i); Write(#179);
 End;
 GotoXY(X1,Y2-2);
 Write(#195);
 For i := X1 + 1 to X2 - 1 do Write(#196);
 Write(#180);
 GotoXY(X1,Y2);
 Write(#192);
 For i := X1 + 1 to X2 - 1 do Write(#196);
 Write(#217);
End;

Procedure DrawBoxWithShadow(X1, Y1, X2, Y2: Byte);
Var
 i: Byte;
Begin
  { Dessiner la boåte principale }
 TextColor(White);
 TextBackground(LightGray);
 DrawBox(X1, Y1, X2, Y2);
 { Dessiner l'ombre d'abord (en bas et Ö droite) }
 TextColor(Blue);
 TextBackground(Black);
  { Ombre en bas }
 GotoXY(X1 + 1, Y2 + 1);
 For i := X1 + 1 to X2 + 1 do Write(' ');
  { Ombre Ö droite }
 For i := Y1 + 1 to Y2 + 1 do Begin
  GotoXY(X2 + 1, i);
  Write('  ');
 End;
 TextColor(Black);
 TextBackground(LightGray);
End;

Procedure ShowTitle;
Var
 i: Byte;
Begin
 { Titre principal }
 GotoXY(1, 1);
 TextColor(Yellow);
 Write('ScanDisk');
 TextColor(White);
  { Barre cyan en dessous du titre }
 TextColor(Cyan);
 GotoXY(1, 2);
 For i := 1 to 80 do Write(#196);
  { Barre cyan en bas }
 TextColor(Cyan);
 GotoXY(1, 23);
 For i := 1 to 80 do Write(#196);
 TextColor(White);
End;

Procedure ShowMainButtons;Begin
 { Afficher les trois boutons principaux }
 GotoXY(2, 22);
 ShowButton('Pause', True);
 Write('  ');
 Case(Language)of
  _English:ShowButton('More Info', False);
  _Germany:ShowButton('Mehr Info', False);
  _Italian:ShowButton('Pió Info', False);
  _Spain:ShowButton('M†s Info', False);
  _Albanian:ShowButton('Mâ Shumâ Info', False);
  _Portuguese:ShowButton('Mais Info', False);
  _Swedish:ShowButton('Mer Info', False);
  _Danish:ShowButton('Mere Info', False);
  _Japanese:ShowButton('Motto Joho', False);
  Else ShowButton('Plus Info',False);
 End;
 Write('  ');
 Case(Language)of
  _English:ShowButton('Exit',False);
  _Germany:ShowButton('Beenden',False);
  _Italian:ShowButton('Uscita',False);
  _Spain:ShowButton('Salir',False);
  _Albanian:ShowButton('Dalje',False);
  _Portuguese:ShowButton('Sair',False);
  _Swedish:ShowButton('Avsluta',False);
  _Danish:ShowButton('Afslut',False);
  _Japanese:ShowButton('Shuuryou',False);
  Else ShowButton('Quitter',False);
 End;
End;

Procedure ShowCheckList;
Var
 i: TCheckItem;
 CheckMark: Char;
Begin
 GotoXY(1, 4);
 If IsImageFile and (Copy(FileName, 1, 4) <> '\\.\') Then Begin
  Case(Language)of
   _English:Write('ScanDisk is now checking the following areas of file ', FileName, ':');
   _Germany:Write('ScanDisk ÅberprÅft nun die folgenden Bereiche der Datei ', FileName, ':');
   _Italian:Write('ScanDisk sta controllando le seguenti aree del file ', FileName, ':');
   _Spain:Write('ScanDisk est† verificando las siguientes †reas del archivo ', FileName, ':');
   _Albanian:Write('ScanDisk po kontrollon zonat e mâposhtme tâ skedarit ', FileName, ':');
   _Portuguese:Write('ScanDisk est† verificando as seguintes †reas do arquivo ', FileName, ':');
   _Swedish:Write('ScanDisk kontrollerar nu fîljande omrÜden av filen ', FileName, ':');
   _Danish:Write('ScanDisk kontrollerer nu folgende omrÜder af filen ', FileName, ':');
   _Japanese:Write('ScanDisk wa ima fairu ', FileName, ' no tsugi no ryouiki wo chekku shiteimasu:');
   Else Write('ScanDisk vÇrifie maintenant les zones suivantes du fichier ', FileName, ' :');
  End;
 End
  Else
 Begin
  Case(Language)of
   _English:Write('ScanDisk is now checking the following areas of drive ', DrivePath, ':');
   _Germany:Write('ScanDisk ÅberprÅft nun die folgenden Bereiche von Laufwerk ', DrivePath, ':');
   _Italian:Write('ScanDisk sta controllando le seguenti aree dell''unitÖ ', DrivePath, ':');
   _Spain:Write('ScanDisk est† verificando las siguientes †reas de la unidad ', DrivePath, ':');
   _Albanian:Write('ScanDisk po kontrollon zonat e mâposhtme tâ diskut ', DrivePath, ':');
   _Portuguese:Write('ScanDisk est† verificando as seguintes †reas da unidade ', DrivePath, ':');
   _Swedish:Write('ScanDisk kontrollerar nu fîljande omrÜden av enheten ', DrivePath, ':');
   _Danish:Write('ScanDisk kontrollerer nu folgende omrÜder af drevet ', DrivePath, ':');
   _Japanese:Write('ScanDisk wa ima doraibu ', DrivePath, ' no tsugi no ryouiki wo chekku shiteimasu:');
   Else Write('ScanDisk vÇrifie maintenant les zones suivantes du lecteur ', DrivePath, ' :');
  End;
 End;
  { Effacer le reste de la ligne }
 ClrEol;
 For i := ciMedia to ciSurface do Begin
  If CheckStatus[i] Then CheckMark := #251
                    Else CheckMark := #175;
  Case i of
   ciMedia: Begin
    GotoXY(1, 6);
    Write('   ', CheckMark,'    ');
    If FsItem(ciMedia) <> '' Then Write(FsItem(ciMedia)) Else
    Case(Language)of
     _English:Write('Media descriptor');
     _Germany:Write('Medien-Deskriptor');
     _Italian:Write('Descrittore supporto');
     _Spain:Write('Descriptor de medios');
     _Albanian:Write('Pârshkruesi i medias');
     _Portuguese:Write('Descritor de m°dia');
     _Swedish:Write('Mediabeskrivare');
     _Danish:Write('Mediebeskriver');
     _Japanese:Write('Media kishutsuji');
     Else Write('Descripteur de mÇdia');
    End;
    ClrEol;
   End;
   ciFAT: Begin
    GotoXY(1, 7);
    Write('   ', CheckMark, '    ');
    If FsItem(ciFAT) <> '' Then Write(FsItem(ciFAT)) Else
    Case(Language)of
     _English:Write('File allocation tables');
     _Germany:Write('Dateizuordnungstabellen');
     _Italian:Write('Tabelle di allocazione file');
     _Spain:Write('Tablas de asignaci¢n de archivos');
     _Albanian:Write('Tabelat e alokimit tâ skedarâve');
     _Portuguese:Write('Tabelas de alocaáao de arquivos');
     _Swedish:Write('Filallokeringstabeller');
     _Danish:Write('Filallokeringstabeller');
     _Japanese:Write('Fairu wariate teburu');
     Else Write('Table d''allocation de fichiers');
    End;
    ClrEol;
   End;
   ciDirectory: Begin
    GotoXY(1, 8);
    Write('   ', CheckMark, '    ');
    If FsItem(ciDirectory) <> '' Then Write(FsItem(ciDirectory)) Else
    Case(Language)of
     _English:Write('Directory structure');
     _Germany:Write('Verzeichnisstruktur');
     _Italian:Write('Struttura directory');
     _Spain:Write('Estructura de directorios');
     _Albanian:Write('Struktura e drejtorive');
     _Portuguese:Write('Estrutura de diret¢rios');
     _Swedish:Write('Katalogstruktur');
     _Danish:Write('Mappestruktur');
     _Japanese:Write('Direkutori kouzou');
     Else Write('Structure de rÇpertoire');
    End;
    ClrEol;
   End;
   ciFileSystem: Begin
    GotoXY(1, 9);
    Write('   ', CheckMark, '    ');
    If FsItem(ciFileSystem) <> '' Then Write(FsItem(ciFileSystem)) Else
    Case(Language)of
     _English:Write('File system');
     _Germany:Write('Dateisystem');
     _Italian:Write('Sistema file');
     _Spain:Write('Sistema de archivos');
     _Albanian:Write('Sistemi i skedarâve');
     _Portuguese:Write('Sistema de arquivos');
     _Swedish:Write('Filsystem');
     _Danish:Write('Filsystem');
     _Japanese:Write('Fairu shisutemu');
     Else Write('Systäme de fichiers');
    End;
    ClrEol;
   End;
   ciFreeSpace: Begin
    GotoXY(1, 10);
    Write('   ', CheckMark, '    ');
    If FsItem(ciFreeSpace) <> '' Then Write(FsItem(ciFreeSpace)) Else
    Case(Language)of
     _English:Write('Free space');
     _Germany:Write('Freier Speicherplatz');
     _Italian:Write('Spazio libero');
     _Spain:Write('Espacio libre');
     _Albanian:Write('Hapâsirâ e lirâ');
     _Portuguese:Write('Espacio livre');
     _Swedish:Write('Ledigt utrymme');
     _Danish:Write('Ledig plads');
     _Japanese:Write('Kuu ryouiki');
     Else Write('Espace libre');
    End;
    ClrEol;
   End;
   ciSurface: Begin
    GotoXY(1, 11);
    Write('   ');
    If CheckStatus[ciSurface] Then Write(#251)
    Else If DoSurfaceScan Then Write(#16)
    Else Write(' ');
    Case(Language)of
     _English:Write('    Surface scan');
     _Germany:Write('    OberflÑchenscan');
     _Italian:Write('    Scansione superficie');
     _Spain:Write('    Exploraci¢n de superficie');
     _Albanian:Write('    Skanimi i sipârfaqes');
     _Portuguese:Write('    Varredura de superf°cie');
     _Swedish:Write('    Ytskanning');
     _Danish:Write('    Overfladeskanning');
     _Japanese:Write('    Hyoumen sukyan');
     Else Write('    Balayage de surface');
    End;
    ClrEol;
   End;
  End;
 End;
  { Afficher les boutons principaux }
 ShowMainButtons;
End;

{ Boutons Oui et Non de ShowDialog (Sel : Oui choisi) }
Procedure DrawYesNo(X, Y: Byte; Sel: Boolean);Begin
 GotoXY(X, Y);
 Case(Language)of
  _English:Begin
   ShowButton('Yes',Sel);
   Write('  ');
   ShowButton('No',Not Sel);
  End;
  _Germany:Begin
   ShowButton('Ja',Sel);
   Write('  ');
   ShowButton('Nein',Not Sel);
  End;
  _Italian:Begin
   ShowButton('Sç',Sel);
   Write('  ');
   ShowButton('No',Not Sel);
  End;
  _Spain:Begin
   ShowButton('S°',Sel);
   Write('  ');
   ShowButton('No',Not Sel);
  End;
  _Albanian:Begin
   ShowButton('Po',Sel);
   Write('  ');
   ShowButton('Jo',Not Sel);
  End;
  _Portuguese:Begin
   ShowButton('Sim',Sel);
   Write('  ');
   ShowButton('Nao',Not Sel);
  End;
  _Swedish:Begin
   ShowButton('Ja',Sel);
   Write('  ');
   ShowButton('Nej',Not Sel);
  End;
  _Danish:Begin
   ShowButton('Ja',Sel);
   Write('  ');
   ShowButton('Nej',Not Sel);
  End;
  _Japanese:Begin
   ShowButton('Hai',Sel);
   Write('  ');
   ShowButton('Iie',Not Sel);
  End;
  Else Begin
   ShowButton('Oui',Sel);
   Write('  ');
   ShowButton('Non',Not Sel);
  End;
 End;
End;

Function ShowDialog(Title,Message:String;ShowYesNo:Boolean):Boolean;
Var
 Key: Char;
 Sel: Boolean;
 BoxWidth, BoxHeight, X1, Y1, i, j: Byte;
 Lines: Array[0..10] of String;
 LineCount, CurrentLine, MaxLineLen: Byte;
Begin
 BoxWidth := 60;
 BoxHeight := 8;
 X1 := (80 - BoxWidth) div 2;
 Y1 := (25 - BoxHeight) div 2;
  { DÇcouper le message en lignes }
 LineCount := 0;
 CurrentLine := 1;
 MaxLineLen := BoxWidth - 4; { Marge de 2 caractäres de chaque cìtÇ }
 While (CurrentLine <= Length(Message)) and (LineCount < 10) do Begin
  If (CurrentLine + MaxLineLen - 1) <= Length(Message) Then Begin
    { Chercher un espace pour couper proprement }
   j := CurrentLine + MaxLineLen - 1;
   While (j > CurrentLine) and (Message[j] <> ' ') do Dec(j);
   If j = CurrentLine Then j := CurrentLine + MaxLineLen - 1; { Pas d'espace trouvÇ, couper au max }
   Lines[LineCount] := Copy(Message, CurrentLine, j - CurrentLine + 1);
   CurrentLine := j + 1;
   { (CurrentLine := j + 1 passe deja l'espace) }
  End
   Else
  Begin
   Lines[LineCount] := Copy(Message, CurrentLine, Length(Message) - CurrentLine + 1);
   CurrentLine := Length(Message) + 1;
  End;
  Inc(LineCount);
 End;
  { Ajuster la hauteur de la boåte selon le nombre de lignes }
 BoxHeight := 5 + LineCount;
 Y1 := (25 - BoxHeight) div 2;
 { Sauvegarder et changer les couleurs }
 TextBackground(LightGray);
 TextColor(Black);
 { Remplir la boåte avec l'arriäre-plan }
 For i := Y1 to Y1 + BoxHeight do Begin
  GotoXY(X1, i);
  For j := X1 to X1 + BoxWidth do Write(' ');
 End;
 { Dessiner le cadre avec ombre }
 DrawBoxWithShadow(X1, Y1, X1 + BoxWidth, Y1 + BoxHeight);
 { Afficher le titre }
 GotoXY(X1 + 2, Y1 + 1);
 Write(Title);
 { Afficher le message ligne par ligne }
 For i := 0 to LineCount - 1 do Begin
  GotoXY(X1 + 2, Y1 + 3 + i);
  Write(Lines[i]);
 End;
 { Afficher les boutons }
 If ShowYesNo Then Begin
  DrawYesNo(X1 + 23, Y1 + BoxHeight - 1, True);
 End
  Else
 Begin
  GotoXY(X1 + 25, Y1 + BoxHeight - 1);
  ShowButton('OK',True);
 End;
  { Attendre la rÇponse }
 { Entree : bouton choisi ; fleches et Tab : changer de bouton ;
   Echap : Non (ou fermer) ; O, Y et N directement }
 Sel := True;
 Trace('boite "' + Title + '" affichee');
 Repeat
  Key := ReadKey;
  Trace('touche ' + Chr(48 + Ord(Key) div 100) + Chr(48 + (Ord(Key) div 10) mod 10) +
        Chr(48 + Ord(Key) mod 10));
  If Key = #0 Then Begin
   Key := ReadKey;
   Trace('touche etendue ' + Chr(48 + Ord(Key) div 100) +
         Chr(48 + (Ord(Key) div 10) mod 10) + Chr(48 + Ord(Key) mod 10));
   If ShowYesNo and (Key in [#15, #72, #75, #77, #80]) Then Begin
    Sel := Not Sel;
    DrawYesNo(X1 + 23, Y1 + BoxHeight - 1, Sel);
   End;
  End
   Else
  If Key = #9 Then Begin
   If ShowYesNo Then Begin
    Sel := Not Sel;
    DrawYesNo(X1 + 23, Y1 + BoxHeight - 1, Sel);
   End;
  End
   Else
  If Key = #13 Then Begin
   ShowDialog := Sel or Not ShowYesNo;
   Break;
  End
   Else
  If Key = #27 Then Begin
   ShowDialog := Not ShowYesNo;
   Break;
  End
   Else
  If ShowYesNo and (UpCase(Key) = 'N') Then Begin
   ShowDialog := False;
   Break;
  End
   Else
  If ShowYesNo and (UpCase(Key) in ['Y','O'])Then Begin
   ShowDialog := True;
   Break;
  End;
 Until False;
  { Restaurer les couleurs et redessiner l'Çcran }
 SetupColors;
 ShowTitle;
 ShowCheckList;
 GotoXY(1, 24);
 Case(Language)of
  _English:Write('examining drive ', DrivePath, '...');
  _Germany:Write('ÅberprÅfe Laufwerk ', DrivePath, '...');
  _Italian:Write('esame unitÖ ', DrivePath, '...');
  _Spain:Write('examinando unidad ', DrivePath, '...');
  _Albanian:Write('duke kontrolluar diskun ', DrivePath, '...');
  _Portuguese:Write('examinando unidade ', DrivePath, '...');
  _Swedish:Write('undersîker enhet ', DrivePath, '...');
  _Danish:Write('undersoger drev ', DrivePath, '...');
  _Japanese:Write('doraibu ', DrivePath, ' wo kensa chuu...');
  Else Write('examen du lecteur ', DrivePath, '...');
 End;
 ClrEol;
End;

Var
 BlockState: Array[0..MapWidth * MapHeight - 1] of Byte;
 MapDrawn: LongInt;

{ Etat de chaque case de la carte : 0 libre, 1 partiellement utilise,
  2 utilise, 3 defectueux, 255 sans objet (au-dela de la fin du disque) }
{$IFDEF FPC}
Function SecState32(Sec: LongInt; Var Step: LongInt): Integer; Forward;
{$ENDIF}

Procedure ComputeBlockMap;
Var
 Blk: Integer;
 SPB, S, E, Sec, FirstData, Cl: LongInt;
 Used, Cnt, Step: LongInt;
 Bad: Boolean;
 BadMark: Word;
Begin
 SPB := (TotalSectors + (MapWidth * MapHeight - 1)) div (MapWidth * MapHeight);
 If SPB < 1 Then SPB := 1;
 FirstData := BootSector.ReservedSectors +
              BootSector.NumberOfFATs * BootSector.SectorsPerFAT +
              (BootSector.RootEntries * 32 + 511) div 512;
 If FATType = ftFAT12 Then BadMark := $FF7 Else BadMark := $FFF7;
 For Blk := 0 to MapWidth * MapHeight - 1 do Begin
  S := Blk * SPB;
  If S >= TotalSectors Then BlockState[Blk] := 255
  Else Begin
   E := S + SPB;
   If E > TotalSectors Then E := TotalSectors;
   Used := 0;
   Cnt := 0;
   Bad := False;
   Sec := S;
   While Sec < E do Begin
    Step := 1;
    Inc(Cnt);
    {$IFDEF FPC}
    Case SecState32(Sec, Step) of
     1: Inc(Used);
     2: Bad := True;
    End;
    {$ELSE}
    If Sec < FirstData Then Inc(Used)
    Else Begin
     Cl := (Sec - FirstData) div BootSector.SectorsPerCluster + 2;
     If Cl <= MaxClusters + 1 Then Begin
      If GetFAT(Cl) = BadMark Then Bad := True
      Else If GetFAT(Cl) <> 0 Then Inc(Used);
     End;
     Step := BootSector.SectorsPerCluster;
    End;
    {$ENDIF}
    Inc(Sec, Step);
   End;
   If Bad Then BlockState[Blk] := 3
   Else If Used = 0 Then BlockState[Blk] := 0
   Else If Used >= Cnt Then BlockState[Blk] := 2
   Else BlockState[Blk] := 1;
  End;
 End;
End;

{ Dessine une case de la carte ; Lit = False : teinte eteinte (pas encore
  balayee), True : couleur de la legende }
Procedure DrawBlock(Blk: Integer; Lit: Boolean);
Begin
 If BlockState[Blk] = 255 Then Exit;
 GotoXY(5 + 2 + (Blk mod MapWidth), 3 + 1 + (Blk div MapWidth));
 TextBackground(LightGray);
 Case BlockState[Blk] of
  0:Begin
   If Lit Then TextColor(Cyan) Else TextColor(DarkGray);
   Write(#176);
  End;
  1:Begin
   If Lit Then TextColor(Brown) Else TextColor(DarkGray);
   Write(#177);
  End;
  2:Begin
   If Lit Then TextColor(Yellow) Else TextColor(DarkGray);
   Write(#254);
  End;
 Else
  TextColor(Red);
  Write('B');
 End;
End;

Procedure ShowSurfaceScanScreen;
Var
 SectorsPerBlock: LongInt;
 X, Y, BlockNum: Integer;
 CurrentSector: LongInt;
 i, j: Byte;
 DialogX1, DialogY1, DialogX2, DialogY2: Byte;
Begin
  { Dimensions de la boåte de dialogue centrÇe - PLUS PETITE }
 DialogX1 := 5;
 DialogY1 := 3;
 DialogX2 := 75;
 DialogY2 := 21;
 { Sauvegarder les couleurs actuelles et crÇer le fond gris de la boåte }
 TextBackground(LightGray);
 TextColor(Black);
 { Remplir la boåte avec l'arriäre-plan gris }
 For i := DialogY1 to DialogY2 do Begin
  GotoXY(DialogX1, i);
  For j := DialogX1 to DialogX2 do Write(' ');
 End;
 { Dessiner le cadre noir de la boåte de dialogue avec ombre }
 DrawBoxWithShadow(DialogX1, DialogY1, DialogX2, DialogY2);
 { RÇtablir les couleurs pour le contenu de la boåte }
 TextColor(Black);
 TextBackground(LightGray);
 { Titre du surface scan centrÇ }
 GotoXY(DialogX1 + 30, DialogY1);
 TextColor(White);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write('Surface Scan');
  _Germany:Write('OberflÑchenscan');
  _Italian:Write('Scansione Superficie');
  _Spain:Write('Exploraci¢n Superficie');
  _Albanian:Write('Skanim Sipârfaqe');
  _Portuguese:Write('Varredura Superf°cie');
  _Swedish:Write('Ytskanning');
  _Danish:Write('Overfladeskanning');
  _Japanese:Write('Hyoumen Sukyan');
  Else Write('Balayage Surface');
 End;
 { Calculer les secteurs par bloc selon la taille totale }
 SectorsPerBlock := (TotalSectors + (MapWidth * MapHeight - 1)) div (MapWidth * MapHeight);
 If SectorsPerBlock < 1 Then SectorsPerBlock := 1;
  { Carte REELLE d'utilisation du disque (d'apres la FAT), grisee : elle
    s'allume au fur et a mesure du balayage }
 ComputeBlockMap;
 MapDrawn := 0;
 For BlockNum := 0 to MapWidth * MapHeight - 1 do DrawBlock(BlockNum, False);
 TextColor(Black);
 TextBackground(LightGray);
 { Informations du fichier/lecteur - position relative }
 GotoXY(DialogX1 + 47, DialogY1 + 2);
 If IsImageFile and (Copy(FileName, 1, 4) <> '\\.\') Then Begin
  Case(Language)of
   _English:Write('File: ', FileName);
   _Germany:Write('Datei: ', FileName);
   _Italian:Write('File: ', FileName);
   _Spain:Write('Archivo: ', FileName);
   _Albanian:Write('Skedari: ', FileName);
   _Portuguese:Write('Arquivo: ', FileName);
   _Swedish:Write('Fil: ', FileName);
   _Danish:Write('Fil: ', FileName);
   _Japanese:Write('Fairu: ', FileName);
   Else Write('Fichier : ', FileName);
  End;
 End
  Else
 Begin
  Case(Language)of
   _English:Write('Drive ', DrivePath);
   _Germany:Write('Laufwerk ', DrivePath, ':');
   _Italian:Write('UnitÖ ', DrivePath, ':');
   _Spain:Write('Unidad ', DrivePath, ':');
   _Albanian:Write('Disku ', DrivePath, ':');
   _Portuguese:Write('Unidade ', DrivePath, ':');
   _Swedish:Write('Enhet ', DrivePath, ':');
   _Danish:Write('Drev ', DrivePath, ':');
   _Japanese:Write('Doraibu ', DrivePath, ':');
   Else Write('Lecteur ', DrivePath);
  End;
 End;
 { Statistiques - position relative Ö droite de la boåte }
 GotoXY(DialogX1 + 47, DialogY1 + 5);
 Case(Language)of
  _English:Write(TotalSectors, ' sectors');
  Else Write(TotalSectors, ' secteurs');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 6);
 Case(Language)of
  _English:Write('0 examined');
  Else Write('0 examinÇs');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 7);
 Case(Language)of
  _English:Write('0 found bad');
  Else Write('0 dÇfectueux');
 End;
  { LÇgende avec la proportion correcte - position relative }
 GotoXY(DialogX1 + 47, DialogY1 + 8);
 TextColor(Cyan);
 TextBackground(Black);
 Write(#176);
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(' = ', SectorsPerBlock, ' sectors');
  Else Write(' = ', SectorsPerBlock, ' secteurs');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 10);
 TextColor(Cyan);
 TextBackground(Black);
 Write(#176);
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(' unused sectors');
  Else Write(' secteurs libres');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 11);
 TextColor(Brown);
 TextBackground(Black);
 Write(#177);
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(' some used sectors');
  Else Begin
   { texte long : sur deux lignes pour rester dans la boite }
   Write(' secteurs en partie');
   GotoXY(DialogX1 + 49, DialogY1 + 12);
   Write('utilisÇs');
  End;
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 13);
 TextColor(Yellow);
 TextBackground(Black);
 Write(#254);
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(' used sectors');
  Else Write(' secteurs utilisÇs');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 14);
 TextColor(Red);
 TextBackground(Black);
 Write('B');
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(' some bad sectors');
  Else Write(' secteurs dÇfectueux');
 End;
 GotoXY(DialogX1 + 20, DialogY1 + 17);
 Case(Language)of
  _English:Begin
   ShowButton('More Info',True);
   Write('   ');
   ShowButton('Exit',False);
  End;
  Else Begin
   ShowButton('Plus Info',True);
   Write('   ');
   ShowButton('Quitter',False);
  End;
 End;
End;

Procedure UpdateSurfaceProgress(SectorsChecked: LongInt; BadFound: LongInt);
Var
 Percentage: Integer;
 i: Integer;
 SectorsPerBlock, Lit: LongInt;
 DialogX1, DialogY1: Byte;
Begin
 { Positions de la bo√Æte de dialogue }
 DialogX1 := 5;
 DialogY1 := 3;
  { Calculer les secteurs reprÇsentÇs par chaque bloc }
 SectorsPerBlock := (TotalSectors + (MapWidth * MapHeight - 1)) div (MapWidth * MapHeight);
 If SectorsPerBlock < 1 Then SectorsPerBlock := 1;
 { Mettre Ö jour les statistiques - position relative }
 GotoXY(DialogX1 + 47, DialogY1 + 6);
 TextColor(Black);
 TextBackground(LightGray);
 Case(Language)of
  _English:Write(SectorsChecked, ' examined     ');
  Else Write(SectorsChecked, ' examinÇs     ');
 End;
 GotoXY(DialogX1 + 47, DialogY1 + 7);
 Case(Language)of
  _English:Write(BadFound, ' found bad     ');
  Else Write(BadFound, ' dÇfectueux     ');
 End;
 { Allumer les blocs dont le balayage a commence }
 Lit := (SectorsChecked + SectorsPerBlock - 1) div SectorsPerBlock;
 If Lit > MapWidth * MapHeight Then Lit := MapWidth * MapHeight;
 While MapDrawn < Lit do Begin
  DrawBlock(MapDrawn, True);
  Inc(MapDrawn);
 End;
 TextColor(Black);
 TextBackground(LightGray);
 TextBackground(Blue);
 TextColor(White);
 Percentage := (SectorsChecked * 100) div TotalSectors;
 If Percentage > 100 Then Percentage := 100;
 GotoXY(1, 24);
 ClrEol;
 Write('     ');
 Case(Language)of
  _English:Write(Percentage, '% complete   ');
  Else Write(Percentage, '% terminÇ   ');
 End;
  { Barre de progression graphique }
 For i := 20 to 66 do Begin
  GotoXY(i, 24);
  If i < (20 + (Percentage * 47 div 100)) Then Begin
   TextColor(Yellow);
   TextBackground(Blue);
   Write(#219)
  End
   Else
  Begin
   TextColor(LightGray);
   TextBackground(Blue);
   Write(#177);
  End;
 End;
End;

{$IFDEF FPC}
{ ==================================================================== }
{ Lecture des secteurs en 32 bits (FPC et WPC) : volume \\.\C: de       }
{ Pasdows ou fichier image, position sur 64 bits (volumes de plus de    }
{ 2 Go)                                                                 }
{ ==================================================================== }

Type
 PB = ^TBA;
 TBA = Array[0..$3FFFFFFF] of Byte;
 PLA = ^TLA;
 TLA = Array[0..$0FFFFFFF] of LongInt;

{$IFDEF WINDOWS}
Function W32Create(N: Pointer; Acc, Shm, Sec, Disp, Fl, Tm: LongInt): LongInt;
 stdcall; external 'kernel32.dll' name 'CreateFileA';
Function W32Seek(H, Lo: LongInt; Hi: Pointer; M: LongInt): LongInt;
 stdcall; external 'kernel32.dll' name 'SetFilePointer';
Function W32Read(H: LongInt; B: Pointer; N: LongInt; Got: Pointer;
 Ov: LongInt): LongInt; stdcall; external 'kernel32.dll' name 'ReadFile';
Function W32Write(H: LongInt; B: Pointer; N: LongInt; Got: Pointer;
 Ov: LongInt): LongInt; stdcall; external 'kernel32.dll' name 'WriteFile';
Function W32Close(H: LongInt): LongInt;
 stdcall; external 'kernel32.dll' name 'CloseHandle';
Function W32Drives: LongInt;
 stdcall; external 'kernel32.dll' name 'GetLogicalDrives';
Function W32DriveType(P: Pointer): LongInt;
 stdcall; external 'kernel32.dll' name 'GetDriveTypeA';
{$ENDIF}

Var
 RawH: LongInt;
 Big, Big2: PB;              { tampons de travail de 64 Ko }
 NonInteractive: Boolean;

Function RawOpen(Const N: String; Wr: Boolean): Boolean;
{$IFDEF WINDOWS}
Var
 Z: Array[0..259] of Char;
 K, Acc: LongInt;
Begin
 For K := 1 to Length(N) do Z[K - 1] := N[K];
 Z[Length(N)] := #0;
 Acc := -2147483647 - 1;
 If Wr Then Acc := Acc or $40000000;
 RawH := W32Create(@Z, Acc, 3, 0, 3, 0, 0);
 RawOpen := RawH <> -1;
End;
{$ELSE}
Begin
 RawH := 0;
 RawOpen := True;
End;
{$ENDIF}

Procedure RawClose;Begin
 {$IFDEF WINDOWS}
 If (RawH <> 0) and (RawH <> -1) Then W32Close(RawH);
 {$ENDIF}
 RawH := 0;
End;

{ Lire N secteurs a partir du secteur Sec (relatif a la partition) }
Function RawRead(Sec, N: LongInt; P: Pointer): Boolean;
Var
 A, Hi, Got: LongInt;
Begin
 A := Sec + PartitionOffset;
 Got := 0;
 {$IFDEF WINDOWS}
 Hi := A shr 23;
 W32Seek(RawH, A shl 9, @Hi, 0);
 RawRead := (W32Read(RawH, P, N * 512, @Got, 0) <> 0) and (Got = N * 512);
 {$ELSE}
 Hi := 0;
 {$I-} Seek(FileHandle, Int64(A) * 512); {$I+}
 If IOResult <> 0 Then Begin
  RawRead := False;
  Exit;
 End;
 {$I-} BlockRead(FileHandle, P^, N * 512, Got); {$I+}
 RawRead := (IOResult = 0) and (Got = N * 512) and (Hi = 0);
 {$ENDIF}
End;

{ Ecrire N secteurs (fichiers images seulement : un volume en service
  n'est jamais ecrit directement) }
Function RawWrite(Sec, N: LongInt; P: Pointer): Boolean;
Var
 A, Hi, Got: LongInt;
Begin
 RawWrite := False;
 If Copy(FileName, 1, 4) = '\\.\' Then Exit;
 A := Sec + PartitionOffset;
 Got := 0;
 {$IFDEF WINDOWS}
 Hi := A shr 23;
 W32Seek(RawH, A shl 9, @Hi, 0);
 RawWrite := (W32Write(RawH, P, N * 512, @Got, 0) <> 0) and (Got = N * 512);
 {$ELSE}
 Hi := 0;
 {$I-} Seek(FileHandle, Int64(A) * 512); {$I+}
 If IOResult <> 0 Then Exit;
 {$I-} BlockWrite(FileHandle, P^, N * 512, Got); {$I+}
 RawWrite := (IOResult = 0) and (Got = N * 512) and (Hi = 0);
 {$ENDIF}
End;
{$ENDIF}

Function DriveExists(Drive: Char): Boolean;
{$IFDEF Windows}
Var
 Z: Array[0..3] of Char;
 T: LongInt;
Begin
 If ((W32Drives shr (Ord(UpCase(Drive)) - 65)) and 1) = 0 Then Begin
  DriveExists := False;
  Exit;
 End;
 Z[0] := UpCase(Drive); Z[1] := ':'; Z[2] := '\'; Z[3] := #0;
 T := W32DriveType(@Z);
 DriveExists := (T = 2) or (T = 3);
End;
{$IFDEF SCANDISK_ANCIEN}
Var
 F: File;
 TestFile: String;
Begin
 TestFile := Drive + ':\$$$TEST.$$$';
 {$I-}Assign(F, TestFile);
 Reset(F); {$I+}
 If IOResult = 0 Then Begin
  Close(F);
  DriveExists := True;
 End
  Else
 Begin
  { Essayer de crÇer un fichier test }
  {$I-}Assign(F, TestFile);
  Rewrite(F);{$I+}
  If IOResult = 0 Then Begin
   Close(F);
   Erase(F);
   DriveExists := True;
  End
   Else
  Begin
   DriveExists := False;
  End;
 End;
End;
{$ENDIF}
{$ELSE}
{$IFDEF FPC}
Begin
 DriveExists := False;
End;
{$ELSE}
Var
 Regs: Registers;
 OldDrive: Byte;
Begin
  { Sauvegarder le lecteur actuel }
 Regs.AH := $19;
 Intr($21, Regs);
 OldDrive := Regs.AL;
  { Essayer de changer vers le lecteur }
 Regs.AH := $0E;
 Regs.DL := Ord(UpCase(Drive)) - Ord('A');
 Intr($21, Regs);
  { VÇrifier si le changement a rÇussi }
 Regs.AH := $19;
 Intr($21, Regs);
 DriveExists := Regs.AL = (Ord(UpCase(Drive)) - Ord('A'));
  { Restaurer le lecteur original }
 Regs.AH := $0E;
 Regs.DL := OldDrive;
 Intr($21, Regs);
End;
{$ENDIF}
{$ENDIF}

Function SelectDrive: String;
Var
 Key: Char;
 SelectedDrive: Integer;
 DriveAvailable: Array[0..3] of Boolean;
 DriveCount: Integer;
 i: Integer;
Begin
  { VÇrifier quels lecteurs sont disponibles }
 DriveAvailable[0] := DriveExists('A'); { A: }
 DriveAvailable[1] := DriveExists('B'); { B: }
 DriveAvailable[2] := DriveExists('C'); { C: }
 DriveAvailable[3] := DriveExists('D'); { D: }
 DriveCount := 0;
 For i := 0 to 3 do If DriveAvailable[i] Then Inc(DriveCount);
 If DriveCount = 0 Then Begin
  Case(Language)of
   _English:ShowDialog('Error', 'No drives available', False);
   Else ShowDialog('Erreur', 'Aucun lecteur disponible', False);
  End;
  SelectDrive := '';
  Exit;
 End;
 SelectedDrive := 2; { Commencer avec C: par dÇfaut }
 While Not DriveAvailable[SelectedDrive] do
  SelectedDrive := (SelectedDrive + 1) mod 4;
 Repeat
  ClrScr;
  ShowTitle;
  GotoXY(1, 4);
  Case Language of
   _English: Write('Select the drive you want to check:');
   Else Write('SÇlectionnez le lecteur que vous voulez vÇrifier :');
  End;
   { Afficher les lecteurs disponibles }
  For i := 0 to 3 do Begin
   If DriveAvailable[i] Then Begin
    GotoXY(5, 7 + i);
    If i = SelectedDrive Then Begin
     TextColor(Black);
     TextBackground(White);
     Write('> ');
    End
     Else
    Begin
     TextColor(White);
     TextBackground(Blue);
     Write('  ');
    End;
    Write(Chr(Ord('A') + i), ':');
    If i = SelectedDrive Then Begin
     Write(' <');
     TextColor(White);
     TextBackground(Blue);
    End;
    ClrEol;
   End;
  End;
  GotoXY(1, 15);
  Case Language of
   _English: Begin
    Write('Use ',#24,#25,' arrows to select, Enter to continue, Esc to exit');
   End;
   Else Begin
    Write('Utilisez les fläches ',#24,#25,' pour sÇlectionner, EntrÇe pour continuer, êchap pour quitter');
   End;
  End;
  Key := ReadKey;
  Case Key of
   #0: Begin { Touche Çtendue }
    Key := ReadKey;
    Case Key of
     #72: Begin { Fläche haut }
      Repeat
       SelectedDrive := (SelectedDrive + 3) mod 4;
      Until DriveAvailable[SelectedDrive];
     End;
     #80: Begin { Fläche bas }
      Repeat
       SelectedDrive := (SelectedDrive + 1) mod 4;
      Until DriveAvailable[SelectedDrive];
     End;
    End;
   End;
   #13: Begin { Enter }
    SelectDrive := Chr(Ord('A') + SelectedDrive) + ':';
    Exit;
   End;
   #27: Begin { Escape }
    SelectDrive := '';
    Exit;
   End;
  End;
 Until False;
End;

{$IFDEF FPC}
Procedure DriveGeometry;Begin
 DrvSpt := 0;
 DrvHeads := 0;
End;

Function BiosSector(Fn: Byte; SectorNum: LongInt): Boolean;Begin
 BiosSector := False;
End;
{$ELSE}
{ Geometrie du lecteur (INT 13h fonction 08h) ; disquette 1,44 Mo par defaut }
Procedure DriveGeometry;
Var Regs: Registers;
Begin
 DrvSpt := 18;
 DrvHeads := 2;
 Regs.AH := $08;
 Regs.DL := DriveNum;
 Intr($13, Regs);
 If ((Regs.Flags and 1) = 0) and ((Regs.CL and $3F) <> 0) Then Begin
  DrvSpt := Regs.CL and $3F;
  DrvHeads := Word(Regs.DH) + 1;
 End;
End;

{ Lecture (Fn=02h) ou ecriture (Fn=03h) d'un secteur relatif a la partition
  par le BIOS, en CHS d'apres la geometrie reelle du disque }
Function BiosSector(Fn: Byte; SectorNum: LongInt): Boolean;
Var
 Regs: Registers;
 Abs, Tk: LongInt;
 Sec, Hd, Cyl: Word;
 Tries: Integer;
Begin
 BiosSector := False;
 If (DrvSpt = 0) or (DrvHeads = 0) Then Exit;
 Abs := SectorNum + PartitionOffset;
 Sec := Word(Abs mod DrvSpt) + 1;
 Tk := Abs div DrvSpt;
 Hd := Word(Tk mod DrvHeads);
 Cyl := Word(Tk div DrvHeads);
 For Tries := 1 to 3 do Begin
  Regs.AH := Fn;
  Regs.AL := 1;
  Regs.CH := Byte(Cyl and $FF);
  Regs.CL := Byte(Sec or ((Cyl shr 2) and $C0));
  Regs.DH := Byte(Hd);
  Regs.DL := DriveNum;
  Regs.ES := Seg(SectorBuffer);
  Regs.BX := Ofs(SectorBuffer);
  Intr($13, Regs);
  If (Regs.Flags and 1) = 0 Then Begin
   BiosSector := True;
   Exit;
  End;
  Regs.AH := 0;
  Regs.DL := DriveNum;
  Intr($13, Regs);
 End;
End;

{$ENDIF}

{$IFDEF FPC}
Function ReadSector(SectorNum: LongInt): Boolean;Begin
 ReadSector := RawRead(SectorNum, 1, @SectorBuffer);
End;

Function WriteSector(SectorNum: LongInt): Boolean;Begin
 WriteSector := RawWrite(SectorNum, 1, @SectorBuffer);
End;
{$ELSE}
Function ReadSector(SectorNum: LongInt): Boolean;
{$IFDEF Windows}
Begin
 If IsImageFile Then Begin
   { Appliquer le dÇplacement de partition si nÇcessaire }
  Seek(FileHandle, (SectorNum + PartitionOffset) * 512);
  BlockRead(FileHandle, SectorBuffer, 512);
  ReadSector := IOResult = 0;
 End
  Else
 Begin
  WriteLn('Accäs disque direct non supportÇ sous Windows');
  ReadSector := False;
 End;
End;
{$ELSE}
Begin
 If IsImageFile Then Begin
   { Appliquer le dÇplacement de partition si nÇcessaire }
  Seek(FileHandle, (SectorNum + PartitionOffset) * 512);
  BlockRead(FileHandle, SectorBuffer, 512);
  ReadSector := IOResult = 0;
 End
  Else
 ReadSector := BiosSector($02, SectorNum);
End;
{$ENDIF}

Function WriteSector(SectorNum: LongInt): Boolean;
{$IFDEF Windows}
Begin
 If IsImageFile Then Begin
  { Appliquer le dÇplacement de partition si nÇcessaire }
  Seek(FileHandle, (SectorNum + PartitionOffset) * 512);
  BlockWrite(FileHandle, SectorBuffer, 512);
  WriteSector := IOResult = 0;
 End Else Begin
  WriteLn('Accäs disque direct non supportÇ sous Windows');
  WriteSector := False;
 End;
End;
{$ELSE}
Begin
 If IsImageFile Then Begin
  { Appliquer le dÇplacement de partition si nÇcessaire }
  Seek(FileHandle, (SectorNum + PartitionOffset) * 512);
  BlockWrite(FileHandle, SectorBuffer, 512);
  WriteSector := IOResult = 0;
 End
  Else
 WriteSector := BiosSector($03, SectorNum);
End;
{$ENDIF}

{$ENDIF}

Function DetectPartition: Boolean;
Var
 i: Integer;
 PartitionFound: Boolean;
 FileSize: LongInt;
Begin
 HasPartition := False;
 PartitionOffset := 0;
 DetectPartition := True;
 {$IFDEF Windows}
  { volume \\.\X: de Pasdows : il commence au secteur d'amorce }
  If Copy(FileName, 1, 4) = '\\.\' Then Exit;
 {$ENDIF}
 If Not IsImageFile Then Begin
  { Pour les vrais lecteurs, pas de partition Ö dÇtecter }
  DetectPartition := True;
  Exit;
 End;
  { Obtenir la taille du fichier image }
 FileSize := System.FileSize(FileHandle);
 If IOResult <> 0 Then Begin
  DetectPartition := False;
  Exit;
 End;
  { Si le fichier fait moins de 4 Mo, c'est probablement une disquette }
  { Les disquettes n'ont pas de table de partition MBR }
 { (en 32 bits, le secteur d'amorce est reconnu plus bas : une image de
   plus de 2 Go donnerait ici une taille fausse) }
 If (FileSize < (4 * 1024 * 1024)) {$IFDEF FPC} and False {$ENDIF} Then Begin
  Case(Language)of
   _English:Begin
    GotoXY(1, 3);
    Write('Small disk image (', FileSize div 1024, 'KB) - assuming floppy disk format');
    ClrEol;
   End;
   _Germany:Begin
    GotoXY(1, 3);
    Write('Kleines Disk-Image (', FileSize div 1024, 'KB) - Disketten-Format angenommen');
    ClrEol;
   End;
   _Italian:Begin
    GotoXY(1, 3);
    Write('Immagine disco piccola (', FileSize div 1024, 'KB) - formato dischetto assunto');
    ClrEol;
   End;
   _Spain:Begin
    GotoXY(1, 3);
    Write('Imagen de disco peque§a (', FileSize div 1024, 'KB) - formato disquete asumido');
    ClrEol;
   End;
   _Albanian:Begin
    GotoXY(1, 3);
    Write('Imazh disku i vogâl (', FileSize div 1024, 'KB) - format diskete supozohet');
    ClrEol;
   End;
   _Portuguese:Begin
    GotoXY(1, 3);
    Write('Imagem de disco pequena (', FileSize div 1024, 'KB) - formato disquete assumido');
    ClrEol;
   End;
   _Swedish:Begin
    GotoXY(1, 3);
    Write('Liten diskavbild (', FileSize div 1024, 'KB) - diskett-format antas');
    ClrEol;
   End;
   _Danish:Begin
    GotoXY(1, 3);
    Write('Lille disk-image (', FileSize div 1024, 'KB) - diskette-format antaget');
    ClrEol;
   End;
   _Japanese:Begin
    GotoXY(1, 3);
    Write('Chiisana disuku imeeji (', FileSize div 1024, 'KB) - furopii disuku keishiki to suitei');
    ClrEol;
   End;
   Else Begin
    GotoXY(1, 3);
    Write('Petite image disque (', FileSize div 1024, 'Ko) - format disquette assumÇ');
    ClrEol;
   End;
  End;
  DetectPartition := True;
  Exit;
 End;
  { Lire le secteur 0 pour vÇrifier s'il y a une table de partition }
 Seek(FileHandle, 0);
 BlockRead(FileHandle, MBR, SizeOf(TMBR));
 If IOResult <> 0 Then Begin
  DetectPartition := False;
  Exit;
 End;
  { VÇrifier la signature MBR }
 If MBR.Signature <> $AA55 Then Begin
  Case(Language)of
   _English:Begin
    GotoXY(1, 3);
    Write('No MBR signature found - assuming direct FAT format');
    ClrEol;
   End;
   Else Begin
    GotoXY(1, 3);
    Write('Signature MBR introuvable - format FAT direct assum√©');
    ClrEol;
   End;
  End;
  DetectPartition := True;
  Exit;
 End;
  { secteur d'amorce d'un volume sans table de partition (EBh ou E9h,
   512 octets par secteur) }
 If ((MBR.BootCode[0] = $EB) or (MBR.BootCode[0] = $E9)) and
    (MBR.BootCode[11] = 0) and (MBR.BootCode[12] = 2) Then Begin
  DetectPartition := True;
  Exit;
 End;
 { Afficher info sur la dÇtection de MBR }
 Case(Language)of
  _English:Begin
   GotoXY(1, 3);
   Write('MBR detected - analyzing partition table...');
   ClrEol;
  End;
   Else
  Begin
   GotoXY(1, 3);
   Write('MBR dÇtectÇ - analyse de la table de partition...');
   ClrEol;
  End;
 End;
  { Chercher une partition active ou la premiäre partition FAT }
 PartitionFound := False;
  { D'abord, chercher une partition active }
 For i := 0 to 3 do Begin
  With MBR.PartitionTable[i] do Begin
   If (Status = $80) and (PartitionType in [$01, $04, $06, $07, $0B, $0C, $0E, $0F]) and (TotalSectors > 0) Then Begin
    PartitionOffset := RelativeSectors;
    HasPartition := True;
    PartitionFound := True;
    Case(Language)of
     _English:Begin
      GotoXY(1, 3);
      Write('Active partition found at sector ', RelativeSectors, ' (Type: $',
            IntToHex(PartitionType, 2), ')');
      ClrEol;
     End;
     Else Begin
      GotoXY(1, 3);
      Write('Partition active trouvÇe au secteur ', RelativeSectors, ' (Type: $',
            IntToHex(PartitionType, 2), ')');
      ClrEol;
     End;
    End;
    Break;
   End;
  End;
 End;
  { Si pas de partition active, chercher la premiäre partition FAT }
 If Not PartitionFound Then Begin
  For i := 0 to 3 do Begin
   With MBR.PartitionTable[i] do Begin
    { Debug : afficher toutes les partitions trouvÇes }
    If TotalSectors > 0 Then Begin
     Case(Language)of
      _English:Begin
       GotoXY(1, 5 + i);
       Write('Partition ', i, ': Type=$', IntToHex(PartitionType, 2),
             ' Status=$', IntToHex(Status, 2), ' Sectors=', TotalSectors);
       ClrEol;
      End;
      Else Begin
       GotoXY(1, 5 + i);
       Write('Partition ', i, ': Type=$', IntToHex(PartitionType, 2),
             ' Status=$', IntToHex(Status, 2), ' Secteurs=', TotalSectors);
       ClrEol;
      End;
     End;
    End;
    If (PartitionType in [$01, $04, $06, $07, $0B, $0C, $0E, $0F]) and (TotalSectors > 0) Then Begin
     PartitionOffset := RelativeSectors;
     HasPartition := True;
     PartitionFound := True;
     Case(Language)of
      _English:Begin
       GotoXY(1, 3);
       Write('FAT partition found at sector ', RelativeSectors, ' (Type: $',
             IntToHex(PartitionType, 2), ')');
       ClrEol;
      End;
      Else Begin
       GotoXY(1, 3);
       Write('Partition FAT trouvÇe au secteur ', RelativeSectors, ' (Type: $',
             IntToHex(PartitionType, 2), ')');
       ClrEol;
      End;
     End;
     Break;
    End;
   End;
  End;
 End;
 If Not PartitionFound Then Begin
  Case(Language)of
   _English:ShowDialog('Error', 'No valid FAT partition found in disk image', False);
   Else ShowDialog('Erreur', 'Aucune partition FAT valide trouvÇe dans l''image disque', False);
  End;
  DetectPartition := False;
  Exit;
 End;
 DetectPartition := True;
End;

{ Disque dur reel : decalage de la partition FAT (partition active d'abord) }
Procedure DetectDrivePartition;
Var
 i, Pass: Integer;
 Found: Boolean;
Begin
 HasPartition := False;
 PartitionOffset := 0;
 If DriveNum < $80 Then Exit;
 If Not ReadSector(0) Then Exit;
 Move(SectorBuffer, MBR, SizeOf(TMBR));
 If (MBR.Signature <> $AA55) or (SectorBuffer[0] = $EB) or
    (SectorBuffer[0] = $E9) Then Exit;
 Found := False;
 For Pass := 0 to 1 do Begin
  For i := 0 to 3 do Begin
   With MBR.PartitionTable[i] do Begin
    If (Not Found) and (TotalSectors > 0) and
       ((Pass = 1) or (Status = $80)) and
       (PartitionType in [$01, $04, $06, $07, $0B, $0C, $0E, $0F]) Then Begin
     PartitionOffset := RelativeSectors;
     HasPartition := True;
     Found := True;
    End;
   End;
  End;
 End;
End;

Function ReadBootSector:Boolean;Begin
 If ReadSector(0) Then Begin
  Move(SectorBuffer, BootSector, SizeOf(BootSector));
  TotalSectors := BootSector.TotalSectors;
  If TotalSectors = 0 Then TotalSectors := BootSector.TotalSectorsBig;
   { Initialiser le type de FAT et les limites }
  FATType := DetectFATType;
   { VÇrifications de sanitÇ }
  If (BootSector.SectorsPerFAT = 0) or (BootSector.SectorsPerFAT > 512) Then Begin
   Case(Language)of
    _English:ShowDialog('Error', 'Invalid sectors per FAT: ' + IntToStr(BootSector.SectorsPerFAT), False);
    Else ShowDialog('Erreur', 'Secteurs par FAT invalide : ' + IntToStr(BootSector.SectorsPerFAT), False);
   End;
   ReadBootSector := False;
   Exit;
  End;
  If (BootSector.BytesPerSector <> 512) Then Begin
   Case(Language)of
    _English:ShowDialog('Error', 'Unsupported sector size: ' + IntToStr(BootSector.BytesPerSector), False);
    Else ShowDialog('Erreur', 'Taille de secteur non supportÇe : ' + IntToStr(BootSector.BytesPerSector), False);
   End;
   ReadBootSector := False;
   Exit;
  End;
   { Afficher le type de FAT dÇtectÇ pour information }
  Case(Language)of
   _English:Begin
    If FATType = ftFAT12 Then Begin
     GotoXY(1, 3);
     Write('Detected file system: FAT12 (', MaxClusters, ' clusters max)');
     ClrEol;
    End
     Else
    Begin
     GotoXY(1, 3);
     Write('Detected file system: FAT16 (', MaxClusters, ' clusters max)');
     ClrEol;
    End;
   End;
   Else Begin
    If FATType = ftFAT12 Then Begin
     GotoXY(1, 3);
     Write('Systäme de fichiers dÇtectÇ : FAT12 (', MaxClusters, ' clusters max)');
     ClrEol;
    End
     Else
    Begin
     GotoXY(1, 3);
     Write('Systäme de fichiers dÇtectÇ : FAT16 (', MaxClusters, ' clusters max)');
     ClrEol;
    End;
   End;
  End;
  ReadBootSector := True;
 End
  Else
 ReadBootSector := False;
End;

Var
 CacheSec: LongInt;
 CacheBuf: Array[0..511] of Byte;
 FatReadErr: Boolean;

{ Octet d'offset O dans la premiere copie de la FAT (secteur en cache) }
Function FatByte(O: LongInt): Byte;
Var
 Sec: LongInt;
Begin
 Sec := O div 512;
 If Sec <> CacheSec Then Begin
  If (Sec >= BootSector.SectorsPerFAT) Then Begin
   FatByte := 0;
   Exit;
  End;
  If ReadSector(BootSector.ReservedSectors + Sec) Then Begin
   Move(SectorBuffer, CacheBuf, 512);
   CacheSec := Sec;
  End
   Else
  Begin
   FatReadErr := True;
   FatByte := 0;
   Exit;
  End;
 End;
 FatByte := CacheBuf[O mod 512];
End;

Var
 LastPct: Integer;

{ Barre de progression en bas de l'ecran pendant les verifications }
Procedure ShowProgress(Pct: Integer);
Var
 Attr: Byte;
 i: Integer;
Begin
 If Pct > 100 Then Pct := 100;
 If Pct < 0 Then Pct := 0;
 If Pct = LastPct Then Exit;
 LastPct := Pct;
 Attr := TextAttr;
 TextBackground(Blue);
 TextColor(White);
 GotoXY(1, 24);
 Write('     ');
 Case(Language)of
  _English:Write(Pct, '% complete   ');
  _Germany:Write(Pct, '% fertig     ');
  _Italian:Write(Pct, '% completato ');
  _Spain:Write(Pct, '% completado');
  Else Write(Pct, '% termin' + #130 + '  ');
 End;
 GotoXY(20, 24);
 For i := 0 to 46 do Begin
  If i < (Pct * 47 div 100) Then Begin
   TextColor(Yellow);
   Write(#219);
  End
   Else
  Begin
   TextColor(LightGray);
   Write(#177);
  End;
 End;
 TextAttr := Attr;
End;

{ Progression de Done/Total ramenee a l'intervalle [Lo, Hi] pour cent }
Procedure ProgressStep(Done, Total: LongInt; Lo, Hi: Integer);
Begin
 If Total < 1 Then Total := 1;
 ShowProgress(Lo + Integer((Done * (Hi - Lo)) div Total));
End;

Procedure ReadFAT;
Var
 i, j, FATIndex: Integer;
 MaxFATEntries, MaxSectors: Integer;
 FATValue: Word;
 FatOfs, Idx, MaxEnt, MaxSec16: LongInt;
 B0, B1: Byte;
Begin
 CheckStatus[ciFAT] := False;
  { DÇtecter le type de FAT }
 FATType := DetectFATType;
  { Initialiser la FAT - dÇjÖ fait dans AllocateMemory }
 If FATType = ftFAT12 Then Begin
  MaxFATEntries := MaxClusters + 2;
  CacheSec := -1;
  FatReadErr := False;
  { 2 entrees de 12 bits pour 3 octets ; une entree peut chevaucher
    deux secteurs de la FAT }
  For FATIndex := 0 to MaxFATEntries - 1 do Begin
   FatOfs := (LongInt(FATIndex) * 3) div 2;
   B0 := FatByte(FatOfs);
   B1 := FatByte(FatOfs + 1);
   If FatReadErr Then Exit;
   If (FATIndex and 63) = 0 Then
    ProgressStep(FATIndex, MaxFATEntries, 0, 25);
   If (FATIndex and 1) = 0 Then
    FATValue := Word(B0) + (Word(B1 and $0F) shl 8)
   Else
    FATValue := (Word(B0) shr 4) + (Word(B1) shl 4);
   SetFAT(FATIndex, FATValue and $0FFF);
  End;
 End
 Else
 Begin { FAT16 }
  { MaxClusters + 2 peut depasser 32767 : calculs en LongInt }
  MaxEnt := LongInt(MaxClusters) + 2;
  MaxSec16 := (MaxEnt * 2 + 511) div 512;
  For i := 0 to Min(BootSector.SectorsPerFAT - 1, MaxSec16 - 1) do Begin
   ProgressStep(i, MaxSec16, 0, 25);
   If ReadSector(BootSector.ReservedSectors + i) Then Begin
    { Lire les entrees FAT16 (2 octets par entree) }
    For j := 0 to 255 do Begin
     Idx := LongInt(i) * 256 + j;
     If Idx >= MaxEnt Then Break;
     SetFAT(Word(Idx), Word(SectorBuffer[j * 2]) +
            (Word(SectorBuffer[j * 2 + 1]) shl 8));
    End;
   End
    Else
   Begin
    Exit;
   End;
  End;
 End;
 CheckStatus[ciFAT] := True;
End;

Procedure CheckFATConsistency;
Var
 i, j, FATEntry, NextCluster: LongInt;
 CmpBuf: Array[0..511] of Byte;
 MaxFATEntries, MaxSectors: LongInt;
 FATMismatch: Boolean;
 EndOfChainMark, BadClusterMark: Word;
 ByteOffset: Word;
 FATValue: Word;
Begin
 CheckStatus[ciMedia] := False;
  { DÇfinir les marqueurs selon le type FAT }
 If FATType = ftFAT12 Then Begin
  EndOfChainMark := $FF8;
  BadClusterMark := $FF7;
 End
  Else
 Begin { FAT16 }
  EndOfChainMark := $FFF8;
  BadClusterMark := $FFF7;
 End;
  { VÇrifier d'abord le descripteur de mÇdia }
 If BootSector.MediaDescriptor <> $F0 Then Begin { $F0 = disquette HD, $F8 = disque dur }
  If BootSector.MediaDescriptor <> $F8 Then Begin
   Inc(ErrorsFound);
   If Not CheckOnly Then Begin
    Case(Language)of
     _English:ShowDialog('Media Error', 'Invalid media descriptor: $' +
                IntToStr(BootSector.MediaDescriptor), False);
     Else ShowDialog('Erreur mÇdia', 'Descripteur de mÇdia invalide : $' +
                IntToStr(BootSector.MediaDescriptor), False);
    End;
   End;
  End;
 End;
  { VÇrifier que les deux copies de la FAT sont identiques }
 If BootSector.NumberOfFATs >= 2 Then Begin
  FATMismatch := False;
  MaxFATEntries := MaxClusters + 2;
  If FATType = ftFAT12 Then Begin
   MaxSectors := (MaxFATEntries * 3 div 2 + 511) div 512;
  End Else Begin
   MaxSectors := (MaxFATEntries * 2 + 511) div 512;
  End;
   { Comparer les deux copies de la FAT secteur par secteur (sans memoire) }
  For i := 0 to Min(BootSector.SectorsPerFAT - 1, MaxSectors - 1) do Begin
   ProgressStep(i, MaxSectors, 25, 32);
   If Not ReadSector(BootSector.ReservedSectors + i) Then Begin
    Inc(ErrorsFound);
    Exit;
   End;
   Move(SectorBuffer, CmpBuf, 512);
   If Not ReadSector(BootSector.ReservedSectors +
                     BootSector.SectorsPerFAT + i) Then Begin
    Inc(ErrorsFound);
    Exit;
   End;
   For j := 0 to 511 do
    If SectorBuffer[j] <> CmpBuf[j] Then FATMismatch := True;
   If FATMismatch Then Begin
    Inc(ErrorsFound);
    Break;
   End;
  End;
   If FATMismatch Then Begin
   If AutoFix Then Begin
    { RÇparer en copiant la premiäre FAT sur la deuxiäme - Ö implÇmenter }
   End
    Else
   Begin
    Case(Language)of
     _English:ShowDialog('FAT Error', 'FAT copies are inconsistent. Use /AUTOFIX to repair.', False);
     Else ShowDialog('Erreur FAT', 'Les copies de FAT sont incoh√©rentes. Utilisez /AUTOFIX pour r√©parer.', False);
    End;
   End;
  End;
 End;
  { VÇrifier les entrÇes spÇciales de la FAT }
 If MaxFATEntries >= 2 Then Begin
  { Les deux premiäres entrÇes doivent avoir des valeurs spÇciales }
  If FATType = ftFAT12 Then Begin
   If (GetFAT(0) and $0FFF) <> ($0F00 or BootSector.MediaDescriptor) Then Begin
    Inc(ErrorsFound);
    If AutoFix Then Begin
     SetFAT(0, $0F00 or BootSector.MediaDescriptor);
    End
     Else
    Begin
     Case(Language)of
      _English:ShowDialog('FAT Error', 'Invalid FAT[0] entry', False);
      Else ShowDialog('Erreur FAT', 'Entr√©e FAT[0] invalide', False);
     End;
    End;
   End;
   If (GetFAT(1) and $0FFF) <> $0FFF Then Begin
    Inc(ErrorsFound);
    If AutoFix Then Begin
     SetFAT(1, $0FFF);
    End Else Begin
     Case(Language)of
      _English:ShowDialog('FAT Error', 'Invalid FAT[1] entry', False);
      Else ShowDialog('Erreur FAT', 'EntrÇe FAT[1] invalide', False);
     End;
    End;
   End;
  End Else Begin { FAT16 }
   If (GetFAT(0) and $FFFF) <> ($FF00 or BootSector.MediaDescriptor) Then Begin
    Inc(ErrorsFound);
    If AutoFix Then Begin
     SetFAT(0, $FF00 or BootSector.MediaDescriptor);
    End Else Begin
     Case(Language)of
      _English:ShowDialog('FAT Error', 'Invalid FAT[0] entry', False);
      Else ShowDialog('Erreur FAT', 'EntrÇe FAT[0] invalide', False);
     End;
    End;
   End;
   If (GetFAT(1) and $FFFF) <> $FFFF Then Begin
    Inc(ErrorsFound);
    If AutoFix Then Begin
     SetFAT(1, $FFFF);
    End Else Begin
     Case(Language)of
      _English:ShowDialog('FAT Error', 'Invalid FAT[1] entry', False);
      Else ShowDialog('Erreur FAT', 'Entr√©e FAT[1] invalide', False);
     End;
    End;
   End;
  End;
 End;
  { VÇrifier les chaånes de clusters pour dÇtecter les boucles infinies }
 For i := 2 to MaxClusters + 1 do Begin
  If (i and 255) = 0 Then ProgressStep(i, MaxClusters, 32, 40);
  If (GetFAT(i) <> 0) and (GetFAT(i) < EndOfChainMark) Then Begin
   NextCluster := GetFAT(i);
   j := 0;
   While (NextCluster < EndOfChainMark) and (NextCluster <> 0) and
         (j < 65530) do Begin
    If NextCluster > MaxClusters + 1 Then Begin
     Inc(ErrorsFound);
     Case(Language)of
      _English:ShowDialog('FAT Error', 'Invalid cluster chain at cluster ' + IntToStr(i), False);
      Else ShowDialog('Erreur FAT', 'Chaåne de cluster invalide au cluster ' + IntToStr(i), False);
     End;
     Break;
    End;
    NextCluster := GetFAT(NextCluster);
    Inc(j);
   End;
   If j >= 65530 Then Begin
    Inc(ErrorsFound);
    Case(Language)of
     _English:ShowDialog('FAT Error', 'Infinite loop detected in cluster chain starting at cluster ' + IntToStr(i), False);
     Else ShowDialog('Erreur FAT', 'Boucle infinie dÇtectÇe dans '+
             'la chaåne de cluster commenáant au cluster ' + IntToStr(i), False);
    End;
   End;
  End;
 End;
 CheckStatus[ciMedia] := True;
End;

Procedure CheckDirectoryStructure;
Var
 i, j: Integer;
 RootSectors: Integer;
 FirstDataSector: Integer;
Begin
 CheckStatus[ciDirectory] := False;
 RootSectors := (BootSector.RootEntries * 32 + 511) div 512;
 FirstDataSector := BootSector.ReservedSectors + (BootSector.NumberOfFATs * BootSector.SectorsPerFAT);
 For i := 0 to RootSectors - 1 do Begin
  ProgressStep(i, RootSectors, 40, 55);
  If ReadSector(FirstDataSector + i) Then Begin
   For j := 0 to 15 do Begin { 16 entr√©es par secteur }
    If (i * 16 + j) <= High(RootDir) Then Begin
     Move(SectorBuffer[j * 32], RootDir[i * 16 + j], 32);
      { VÇrifier l'entrÇe }
     If RootDir[i * 16 + j].Name[0] <> #0 Then Begin
      { Marquer les clusters utilisÇs }
      If (RootDir[i * 16 + j].StartCluster > 0) and
         (RootDir[i * 16 + j].StartCluster <= 65535) Then Begin
       SetClusterMap(RootDir[i * 16 + j].StartCluster, 1);
      End;
     End;
    End;
   End;
  End
   Else
  Begin
   Exit;
  End;
 End;
 CheckStatus[ciDirectory] := True;
End;

Procedure CheckFileAllocation;
Var
 i, NextCluster: LongInt;
 Chain: Array[0..1023] of Word;
 ChainLength: Integer;
 EndOfChainMark: Word;
Begin
 CheckStatus[ciFileSystem] := False;
  { DÇfinir le marqueur de fin selon le type FAT }
 If FATType = ftFAT12 Then Begin
  EndOfChainMark := $FF8;
 End
  Else
 Begin { FAT16 }
  EndOfChainMark := $FFF8;
 End;
 For i := 2 to MaxClusters + 1 do Begin
  If (i and 255) = 0 Then ProgressStep(i, MaxClusters, 55, 80);
  If (GetFAT(i) <> 0) and (GetFAT(i) < EndOfChainMark) Then Begin
   { Suivre la chaåne de clusters }
   NextCluster := i;
   ChainLength := 0;
   FillChar(Chain, SizeOf(Chain), 0);
   Repeat
    If ChainLength < High(Chain) Then Begin
     Chain[ChainLength] := NextCluster;
     Inc(ChainLength);
    End;
    If NextCluster <= MaxClusters + 1 Then Begin
     If GetClusterMap(NextCluster) = 1 Then
      SetClusterMap(NextCluster, 1)
     Else If GetClusterMap(NextCluster) = 0 Then
      SetClusterMap(NextCluster, 1)
     Else Begin
      Inc(CrossLinkedFiles);
      SetClusterMap(NextCluster, 3);
     End;
    End;
    If NextCluster <= MaxClusters + 1 Then NextCluster := GetFAT(NextCluster)
                                      Else Break;
    If ChainLength > 1000 Then Break; { Protection contre les boucles infinies }
   Until (NextCluster >= EndOfChainMark) or (NextCluster = 0);
  End;
 End;
 CheckStatus[ciFileSystem] := True;
End;

Procedure CheckLostClusters;
Var
 i: LongInt;
Begin
 CheckStatus[ciFreeSpace] := False;
 For i := 2 to MaxClusters + 1 do Begin
  If (i and 255) = 0 Then ProgressStep(i, MaxClusters, 80, 100);
  If (i <= MaxClusters + 1) and (GetFAT(i) <> 0) and (GetClusterMap(i) = 0) Then Begin
   Inc(LostClusters);
   Inc(ErrorsFound);
  End;
 End;
 CheckStatus[ciFreeSpace] := True;
End;

{$IFDEF FPC}
Var
 SurfBlk: LongInt;
 SurfOk: Boolean;

{ Lecture du secteur I par blocs de 64 secteurs (un bloc illisible est
  relu secteur par secteur) }
Function SurfRead(I: LongInt): Boolean;
Var
 N: LongInt;
Begin
 If (SurfBlk < 0) or (I < SurfBlk) or (I >= SurfBlk + 64) Then Begin
  SurfBlk := I;
  N := 64;
  If I + N > TotalSectors Then N := TotalSectors - I;
  SurfOk := RawRead(I, N, Big);
 End;
 If SurfOk Then SurfRead := True Else SurfRead := ReadSector(I);
End;
{$ENDIF}

Procedure SurfaceScan;
Var
 i: LongInt;
 BadSectorFound: Boolean;
 SectorsExamined, SectorsPerBlockScan: LongInt;
 BlockNo: Integer;
 DialogX1, DialogY1: Byte;
Begin
 If Not DoSurfaceScan Then Exit;
 SectorsPerBlockScan := (TotalSectors + (MapWidth * MapHeight - 1)) div
                        (MapWidth * MapHeight);
 If SectorsPerBlockScan < 1 Then SectorsPerBlockScan := 1;
  { Positions de la boåte de dialogue }
 DialogX1 := 5;
 DialogY1 := 3;
  { Initialiser les variables }
 CheckStatus[ciSurface] := False;
 BadSectors := 0;
 SectorsExamined := 0;
  { Afficher l'Çcran de surface scan - êCRAN FIXE }
 ShowSurfaceScanScreen;
 {$IFDEF FPC}
 SurfBlk := -1;
 Trace('balayage de surface : ' + NumS(TotalSectors) + ' secteurs');
 {$ENDIF}
 { Initialiser le gÇnÇrateur de nombres alÇatoires pour la simulation }
 Randomize;
 For i := 0 to TotalSectors - 1 do Begin
  Inc(SectorsExamined);
  {$IFDEF FPC}
  If (TotalSectors >= 10) and (i mod (TotalSectors div 10) = 0) Then
   Trace('balayage ' + NumS(i) + ' / ' + NumS(TotalSectors));
  BadSectorFound := Not SurfRead(i);
  {$ELSE}
  BadSectorFound := Not ReadSector(i);
  {$ENDIF}
  If BadSectorFound Then Begin
   Inc(BadSectors);
   BlockNo := i div SectorsPerBlockScan;
   If BlockNo < MapWidth * MapHeight Then Begin
    BlockState[BlockNo] := 3;
    DrawBlock(BlockNo, True);
   End;
   If AutoFix {$IFDEF FPC} and False {$ENDIF} Then Begin
     { Marquer le cluster correspondant comme dÇfectueux }
    If i >= (BootSector.ReservedSectors + BootSector.NumberOfFATs * BootSector.SectorsPerFAT) Then Begin
     If FATType = ftFAT12 Then Begin
      SetFAT((i - (BootSector.ReservedSectors + BootSector.NumberOfFATs * BootSector.SectorsPerFAT))
            div BootSector.SectorsPerCluster + 2, $FF7);
     End Else Begin { FAT16 }
      SetFAT((i - (BootSector.ReservedSectors + BootSector.NumberOfFATs * BootSector.SectorsPerFAT))
            div BootSector.SectorsPerCluster + 2, $FFF7);
     End;
    End;
   End;
  End;
   { Mettre Ö jour l'affichage selon la taille du disque pour Çviter de ralentir }
  If (HasPartition) Then Begin
   { Pour les gros disques, mise Ö jour moins frÇquente }
   If (i mod (TotalSectors div 100 + 1)) = 0 Then Begin
    UpdateSurfaceProgress(SectorsExamined, BadSectors);
   End;
  End
   Else
  If (TotalSectors < 100) or ((i mod (TotalSectors div 200 + 1)) = 0) Then Begin
   UpdateSurfaceProgress(SectorsExamined, BadSectors);
  End;
   { VÇrifier si l'utilisateur appuie sur une touche }
  If ((i and 255) = 0) and KeyPressed Then Begin
   Case ReadKey of
    #27, 'e', 'E': Begin { ESC ou Exit }
     Break;
    End;
   End;
  End;
   { DÇlai proportionnel Ö la taille du disque - pas de dÇlai pour les gros disques }
  If TotalSectors < 1000 Then Delay(20) Else
  If TotalSectors < 10000 Then Delay(2) Else
  If HasPartition Then { Pas de dÇlai pour les disques avec partitions }
                       { Pas de dÇlai du tout }
                  Else {$IFNDEF FPC} Delay(1) {$ENDIF};
 End;
  { Mettre Ö jour l'affichage final }
 UpdateSurfaceProgress(SectorsExamined, BadSectors);
 CheckStatus[ciSurface] := True;
  { Attendre que l'utilisateur appuie sur une touche - EN BAS DE L'√âCRAN }
 TextBackground(Blue);
 TextColor(White);
 GotoXY(20, 24);
 Case(Language)of
  _English:Write('Press any key to continue...');
  Else Write('Appuyez sur une touche pour continuer...');
 End;
 ReadKey;
End;

{$IFDEF FPC}
{ ==================================================================== }
{ Verification en 32 bits : FAT12, FAT16, FAT32, NTFS et HPFS          }
{ (Pasdows 95 et Free Pascal). Les erreurs sont notees dans un journal }
{ affiche a la fin (et ecrit dans SCANDISK.LOG) ; aucune ecriture n'est }
{ faite sur le disque.                                                 }
{ ==================================================================== }

Const
 MaxLog = 400;
 MaxRuns = 512;

Type
 TRunList = Record
  N: LongInt;
  V, L, C: Array[0..MaxRuns - 1] of LongInt;  { VCN, longueur, LCN (-1 : creux) }
 End;

Var
 LogMsg: Array[0..MaxLog - 1] of String[78];
 LogErr: Array[0..MaxLog - 1] of Boolean;
 LogN, NoteN: LongInt;
 PopT: Array[0..255] of Byte;
 { statistiques }
 UnitBytes, TotUnits, FreeUnits, BadUnits, FileUnits, DirUnits: LongInt;
 NFiles, NDirs, LostChains: LongInt;
 FsName: String[12];
 { FAT }
 FSpc, FRsvd, FNFat, FRootEnt, FFatSz, FRootSec, FRootSecs, FFirstData,
 FNClus, FMax, FRootClus, FEoc, FBadV, FResV, FClusB, FMedia, FFsInfo,
 FExtFlags, FBkBoot, FTotSec: LongInt;
 FatT: PLA;
 RefC: PB;
 { NTFS }
 NSpc, NCB, NTotC, NMftLcn, NMirrLcn, NRecSz, NIdxSz, NRecs: LongInt;
 MftRL, BmpRL, IdxRL: TRunList;
 BmpDataSize: LongInt;
 InUseB, IsDirB, MftBmp, CMap: PB;
 SeqA, ParRec, ParSeq: PLA;
 NIdxQ: Array[0..1023] of LongInt;
 { HPFS }
 HTot, HRoot, HList, HListN, HNB, HDirS, HDirE, HDirBmp, HNDn: LongInt;
 SMap, HBmp, DnSeen: PB;
 HDBm: Array[0..2047] of Byte;
 SB, SP: Array[0..511] of Byte;

Function LStr(V: LongInt): String;
Var
 S: String;
Begin
 Str(V, S);
 LStr := S;
End;

{ Nombre avec separateurs de milliers (espaces) }
Function NStr(V: LongInt): String;
Var
 S, R: String;
 K: LongInt;
Begin
 Str(V, S);
 R := '';
 K := 0;
 While Length(S) > 0 do Begin
  If (K > 0) and (K mod 3 = 0) and (S[Length(S)] <> '-') Then R := ' ' + R;
  R := S[Length(S)] + R;
  Delete(S, Length(S), 1);
  Inc(K);
 End;
 NStr := R;
End;

Procedure AddLog(Const S: String; Err: Boolean);Begin
 If Err Then Inc(ErrorsFound) Else Inc(NoteN);
 If LogN < MaxLog Then Begin
  LogMsg[LogN] := Copy(S, 1, 78);
  LogErr[LogN] := Err;
  Inc(LogN);
 End;
End;

Procedure AddErr(Const S: String);Begin
 AddLog(S, True);
End;

Procedure AddNote(Const S: String);Begin
 AddLog(S, False);
End;

Function RdW(P: PB; O: LongInt): LongInt;Begin
 RdW := LongInt(P^[O]) or (LongInt(P^[O + 1]) shl 8);
End;

Function RdL(P: PB; O: LongInt): LongInt;Begin
 RdL := LongInt(P^[O]) or (LongInt(P^[O + 1]) shl 8) or
        (LongInt(P^[O + 2]) shl 16) or (LongInt(P^[O + 3]) shl 24);
End;

Function BitOn(P: PB; I: LongInt): Boolean;Begin
 BitOn := ((P^[I shr 3] shr (I and 7)) and 1) <> 0;
End;

Procedure BitSet(P: PB; I: LongInt);Begin
 P^[I shr 3] := P^[I shr 3] or (1 shl (I and 7));
End;

Function NewBuf(Size: LongInt): PB;
Var
 P: PB;
Begin
 If Size < 16 Then Size := 16;
 GetMem(P, Size);
 If P <> Nil Then FillChar(P^, Size, 0);
 NewBuf := P;
End;

Function ReadErrMsg(Sec: LongInt): String;Begin
 ReadErrMsg := TL('Erreur de lecture au secteur ', 'Read error at sector ') +
               LStr(Sec);
End;

Procedure ShowFsLine(Const S: String);Begin
 GotoXY(1, 3);
 Write(S);
 ClrEol;
End;

Function TotSecOf: LongInt;
Var
 T: LongInt;
Begin
 T := BootSector.TotalSectors;
 If T = 0 Then T := BootSector.TotalSectorsBig;
 TotSecOf := T;
End;

{ -------------------------------------------------------------------- }
{ Detection du systeme de fichiers d'apres le secteur d'amorce          }
{ -------------------------------------------------------------------- }

Function DetectFs: Boolean;
Var
 P: PB;
 Oem: String;
 K, V: LongInt;
Begin
 DetectFs := False;
 For K := 0 to 255 do Begin
  V := K;
  PopT[K] := 0;
  While V <> 0 do Begin
   PopT[K] := PopT[K] + (V and 1);
   V := V shr 1;
  End;
 End;
 If Not ReadSector(0) Then Exit;
 Move(SectorBuffer, BootSector, SizeOf(BootSector));
 P := @SectorBuffer;
 Oem := '';
 For K := 3 to 10 do Oem := Oem + Chr(P^[K]);
 If Oem = 'NTFS    ' Then FsType := fsNTFS
  Else
 Begin
  FsType := fsFAT16;
  { HPFS : superbloc au secteur 16 }
  If ReadSector(16) and (RdL(@SectorBuffer, 0) = LongInt($F995E849)) and
     (RdL(@SectorBuffer, 4) = LongInt($FA53E9C5)) Then FsType := fsHPFS
  Else Begin
   If Not ReadSector(0) Then Exit;
   P := @SectorBuffer;
   If (RdW(P, 22) = 0) and (RdL(P, 36) <> 0) Then FsType := fsFAT32;
  End;
 End;
 If Not ReadSector(0) Then Exit;
 P := @SectorBuffer;
 If RdW(P, 11) <> 512 Then Begin
  ShowDialog(TL('Erreur', 'Error'),
             TL('Taille de secteur non prise en charge : ',
                'Unsupported sector size: ') + LStr(RdW(P, 11)), False);
  Exit;
 End;
 Case FsType of
  fsNTFS: Begin
   FsName := 'NTFS';
   NSpc := P^[13];
   If NSpc > 128 Then NSpc := 1 shl (256 - NSpc);
   TotalSectors := RdL(P, $28);
   NMftLcn := RdL(P, $30);
   NMirrLcn := RdL(P, $38);
   V := ShortInt(P^[$40]);
   If V > 0 Then NRecSz := V * NSpc * 512 Else NRecSz := 1 shl (-V);
   V := ShortInt(P^[$44]);
   If V > 0 Then NIdxSz := V * NSpc * 512 Else NIdxSz := 1 shl (-V);
   NCB := NSpc * 512;
   If NSpc = 0 Then NTotC := 0 Else NTotC := TotalSectors div NSpc;
   UnitBytes := NCB;
   TotUnits := NTotC;
  End;
  fsHPFS: Begin
   FsName := 'HPFS';
   If Not ReadSector(16) Then Exit;
   Move(SectorBuffer, SB, 512);
   If Not ReadSector(17) Then Exit;
   Move(SectorBuffer, SP, 512);
   HTot := RdL(@SB, 16);
   TotalSectors := HTot;
   UnitBytes := 512;
   TotUnits := HTot;
  End;
  Else Begin
   FSpc := P^[13];
   FRsvd := RdW(P, 14);
   FNFat := P^[16];
   FRootEnt := RdW(P, 17);
   FTotSec := RdW(P, 19);
   If FTotSec = 0 Then FTotSec := RdL(P, 32);
   FMedia := P^[21];
   FFatSz := RdW(P, 22);
   If FFatSz = 0 Then FFatSz := RdL(P, 36);
   FExtFlags := RdW(P, 40);
   FRootClus := RdL(P, 44);
   FFsInfo := RdW(P, 48);
   FBkBoot := RdW(P, 50);
   TotalSectors := FTotSec;
   If (FSpc = 0) or (FNFat = 0) or (FFatSz = 0) or (FTotSec = 0) Then Begin
    ShowDialog(TL('Erreur', 'Error'),
               TL('Secteur d''amorce invalide : syst'#138'me de fichiers '+
                  'inconnu.', 'Invalid boot sector: unknown file system.'),
               False);
    Exit;
   End;
   FRootSec := FRsvd + FNFat * FFatSz;
   FRootSecs := (FRootEnt * 32 + 511) div 512;
   FFirstData := FRootSec + FRootSecs;
   FNClus := (FTotSec - FFirstData) div FSpc;
   FMax := FNClus + 1;
   FClusB := FSpc * 512;
   If FsType <> fsFAT32 Then Begin
    If FNClus < 4085 Then FsType := fsFAT12 Else FsType := fsFAT16;
   End;
   Case FsType of
    fsFAT12: Begin
     FsName := 'FAT12'; FEoc := $FF8; FBadV := $FF7; FResV := $FF0;
    End;
    fsFAT16: Begin
     FsName := 'FAT16'; FEoc := $FFF8; FBadV := $FFF7; FResV := $FFF0;
    End;
    Else Begin
     FsName := 'FAT32'; FEoc := $0FFFFFF8; FBadV := $0FFFFFF7;
     FResV := $0FFFFFF0;
    End;
   End;
   UnitBytes := FClusB;
   TotUnits := FNClus;
  End;
 End;
 Trace('systeme de fichiers ' + FsName + ', ' + LStr(TotUnits) + ' unites');
 ShowFsLine(TL('Syst'#138'me de fichiers d'#130'tect'#130' : ',
               'Detected file system: ') + FsName + ' (' + NStr(TotUnits) +
            TL(' unit'#130's de ', ' units of ') + NStr(UnitBytes) +
            TL(' octets)', ' bytes)'));
 GetMem(Big, 65536);
 GetMem(Big2, 65536);
 DetectFs := True;
End;

{ ==================================================================== }
{ FAT12, FAT16 et FAT32                                                }
{ ==================================================================== }

Function FClusSec(C: LongInt): LongInt;Begin
 FClusSec := FFirstData + (C - 2) * FSpc;
End;

Function FNeedBytes: LongInt;Begin
 Case FsType of
  fsFAT12: FNeedBytes := ((FMax + 1) * 3) div 2 + 2;
  fsFAT16: FNeedBytes := (FMax + 1) * 2;
  Else FNeedBytes := (FMax + 1) * 4;
 End;
End;

Procedure FatBoot;
Var
 P: PB;
 K: LongInt;
 Same: Boolean;
Begin
 P := @SectorBuffer;
 If Not ReadSector(0) Then Begin
  AddErr(ReadErrMsg(0));
  Exit;
 End;
 If RdW(P, 510) <> $AA55 Then
  AddErr(TL('Signature AA55h absente du secteur d''amorce',
            'Boot sector signature AA55h missing'));
 If Not ((FMedia = $F0) or (FMedia >= $F8)) Then
  AddErr(TL('Descripteur de m'#130'dia invalide : ', 'Invalid media descriptor: ') +
         IntToHex(FMedia, 2) + 'h');
 If (FSpc and (FSpc - 1)) <> 0 Then
  AddErr(TL('Secteurs par unit'#130' invalide : ', 'Invalid sectors per cluster: ') +
         LStr(FSpc));
 If FNClus < 1 Then AddErr(TL('Volume sans unit'#130' d''allocation',
                              'Volume has no data clusters'));
 If (FsType = fsFAT32) and (FBkBoot <> 0) and (FBkBoot < FRsvd) Then Begin
  Move(SectorBuffer, Big^, 512);
  If ReadSector(FBkBoot) Then Begin
   Same := True;
   For K := 0 to 89 do
    If Big^[K] <> SectorBuffer[K] Then Same := False;
   If Not Same Then
    AddErr(TL('La copie du secteur d''amorce (secteur ', 'Backup boot sector (sector ') +
           LStr(FBkBoot) + TL(') diff'#138're de l''original', ') differs from the original'));
  End Else AddErr(ReadErrMsg(FBkBoot));
 End;
 If (FsType = fsFAT32) and (FFsInfo <> 0) and (FFsInfo < FRsvd) Then Begin
  If ReadSector(FFsInfo) Then Begin
   If (RdL(P, 0) <> $41615252) or (RdL(P, 484) <> $61417272) Then
    AddErr(TL('Secteur FSInfo invalide (signatures)', 'Invalid FSInfo sector (signatures)'));
  End Else AddErr(ReadErrMsg(FFsInfo));
 End;
 If FsType = fsFAT32 Then Begin
  If (FRootClus < 2) or (FRootClus > FMax) Then
   AddErr(TL('Cluster du r'#130'pertoire racine invalide : ', 'Invalid root directory cluster: ') +
          LStr(FRootClus));
 End;
End;

{ Lecture de la premiere FAT et comparaison avec les copies }
Function FatLoad: Boolean;
Var
 NSec, S, N, K, I, E, O, Diff, Ent: LongInt;
 Whole: PB;
Begin
 FatLoad := False;
 FatT := Nil;
 RefC := Nil;
 GetMem(FatT, (FMax + 2) * 4);
 RefC := NewBuf(FMax + 2);
 If (FatT = Nil) or (RefC = Nil) Then Begin
  AddErr(TL('M'#130'moire insuffisante pour la FAT', 'Not enough memory for the FAT'));
  Exit;
 End;
 FillChar(FatT^, (FMax + 2) * 4, 0);
 NSec := (FNeedBytes + 511) div 512;
 If NSec > FFatSz Then Begin
  AddErr(TL('La FAT est trop petite pour le nombre d''unit'#130's du volume',
            'The FAT is too small for the number of clusters'));
  NSec := FFatSz;
 End;
 Ent := FMax + 1;
 If FsType = fsFAT12 Then Begin
  Whole := NewBuf(NSec * 512 + 4);
  S := 0;
  While S < NSec do Begin
   N := NSec - S;
   If N > 64 Then N := 64;
   If Not RawRead(FRsvd + S, N, @Whole^[S * 512]) Then Begin
    AddErr(ReadErrMsg(FRsvd + S));
    FreeMem(Whole, NSec * 512 + 4);
    Exit;
   End;
   S := S + N;
  End;
  For I := 0 to Ent do Begin
   O := (I * 3) div 2;
   If O + 1 >= NSec * 512 Then Break;
   If (I and 1) = 0 Then E := RdW(Whole, O) and $FFF
                    Else E := RdW(Whole, O) shr 4;
   FatT^[I] := E;
  End;
  FreeMem(Whole, NSec * 512 + 4);
 End
  Else
 Begin
  S := 0;
  While S < NSec do Begin
   N := NSec - S;
   If N > 128 Then N := 128;
   ProgressStep(S, NSec, 2, 15);
   If Not RawRead(FRsvd + S, N, Big) Then Begin
    AddErr(ReadErrMsg(FRsvd + S));
    Exit;
   End;
   If FsType = fsFAT16 Then Begin
    For K := 0 to N * 256 - 1 do Begin
     I := S * 256 + K;
     If I > Ent Then Break;
     FatT^[I] := RdW(Big, K * 2);
    End;
   End
    Else
   Begin
    For K := 0 to N * 128 - 1 do Begin
     I := S * 128 + K;
     If I > Ent Then Break;
     FatT^[I] := RdL(Big, K * 4) and $0FFFFFFF;
    End;
   End;
   S := S + N;
  End;
 End;
 FatLoad := True;
 If (FatT^[0] and $FF) <> FMedia Then
  AddErr(TL('La premi'#138're entr'#130'e de la FAT ne contient pas le descripteur de m'#130'dia',
            'First FAT entry does not hold the media descriptor'));
 { comparer les copies (sauf FAT32 sans miroir) }
 If (FsType = fsFAT32) and ((FExtFlags and $80) <> 0) Then Exit;
 For K := 1 to FNFat - 1 do Begin
  S := 0;
  Diff := -1;
  While (S < NSec) and (Diff < 0) do Begin
   N := NSec - S;
   If N > 128 Then N := 128;
   ProgressStep(S, NSec, 15, 25);
   If Not RawRead(FRsvd + S, N, Big) Then Break;
   If Not RawRead(FRsvd + K * FFatSz + S, N, Big2) Then Begin
    AddErr(ReadErrMsg(FRsvd + K * FFatSz + S));
    Break;
   End;
   For I := 0 to N * 512 - 1 do
    If Big^[I] <> Big2^[I] Then Begin
     Diff := S + I div 512;
     Break;
    End;
   S := S + N;
  End;
  If Diff >= 0 Then
   AddErr(TL('La copie ', 'FAT copy ') + LStr(K + 1) +
          TL(' de la FAT diff'#138're de la premi'#138're (secteur ',
             ' differs from the first one (sector ') + LStr(Diff) + TL(' de la FAT)', ' of the FAT)'));
 End;
End;

{ Suivre la chaine qui commence en Start et marquer ses unites ;
  renvoie le nombre d'unites }
Function FMark(Start: LongInt; Const Nm: String): LongInt;
Var
 C, Nx, Cnt: LongInt;
Begin
 C := Start;
 Cnt := 0;
 While (C >= 2) and (C <= FMax) do Begin
  If RefC^[C] <> 0 Then Begin
   Inc(CrossLinkedFiles);
   AddErr(Nm + TL(' : lien crois'#130' ou boucle au cluster ', ': cross-link or loop at cluster ') +
          LStr(C));
   Break;
  End;
  RefC^[C] := 1;
  Inc(Cnt);
  Nx := FatT^[C];
  If Nx >= FEoc Then Break;
  If Nx = 0 Then Begin
   AddErr(Nm + TL(' : cha'#140'ne interrompue (cluster libre apr'#138's ',
                  ': broken chain (free cluster after ') + LStr(C) + ')');
   Break;
  End;
  If Nx = FBadV Then Begin
   AddErr(Nm + TL(' : la cha'#140'ne contient un cluster d'#130'fectueux',
                  ': chain contains a bad cluster'));
   Break;
  End;
  If (Nx < 2) or (Nx > FMax) Then Begin
   AddErr(Nm + TL(' : cluster suivant invalide (', ': invalid next cluster (') +
          LStr(Nx) + TL(') apr'#138's ', ') after ') + LStr(C));
   Break;
  End;
  C := Nx;
 End;
 FMark := Cnt;
End;

{ Nom 8.3 d'une entree de repertoire }
Function FEntName(P: PB; O: LongInt): String;
Var
 S, E: String;
 K: LongInt;
Begin
 S := '';
 For K := 0 to 7 do S := S + Chr(P^[O + K]);
 While (Length(S) > 0) and (S[Length(S)] = ' ') do Delete(S, Length(S), 1);
 If (Length(S) > 0) and (S[1] = #5) Then S[1] := #229;
 E := '';
 For K := 8 to 10 do E := E + Chr(P^[O + K]);
 While (Length(E) > 0) and (E[Length(E)] = ' ') do Delete(E, Length(E), 1);
 If E <> '' Then S := S + '.' + E;
 FEntName := S;
End;

Function FIsRoot(C: LongInt): Boolean;Begin
 FIsRoot := (C = 0) or ((FsType = fsFAT32) and (C = FRootClus));
End;

Var
 FDirsDone: LongInt;

Procedure FScanDir(Clus, Parent: LongInt; Path: String; Depth: LongInt);
Var
 P: PB;
 BlkSz, C, Nx, K, O, Cnt, Start, Size, Chain, Need, Exp, Lp: LongInt;
 A: Byte;
 Nm: String;
 Fin, Ok: Boolean;
Begin
 If Depth > 60 Then Begin
  AddErr(Path + TL(' : r'#130'pertoires trop imbriqu'#130's', ': directories nested too deep'));
  Exit;
 End;
 Inc(FDirsDone);
 If NDirs > 0 Then ProgressStep(FDirsDone, NDirs + 1, 30, 60);
 If Clus = 0 Then BlkSz := FRootSecs * 512 Else BlkSz := FClusB;
 If BlkSz <= 0 Then Exit;
 P := NewBuf(BlkSz);
 C := Clus;
 Fin := False;
 Cnt := 0;
 Lp := 0;
 Repeat
  If Clus = 0 Then Ok := RawRead(FRootSec, FRootSecs, P)
              Else Ok := RawRead(FClusSec(C), FSpc, P);
  If Not Ok Then Begin
   AddErr(Path + ' : ' + ReadErrMsg(FClusSec(C)));
   Break;
  End;
  For K := 0 to BlkSz div 32 - 1 do Begin
   O := K * 32;
   If P^[O] = 0 Then Begin
    Fin := True;
    Break;
   End;
   A := P^[O + 11];
   If (P^[O] <> $E5) and (A <> $0F) and ((A and 8) = 0) Then Begin
    Nm := FEntName(P, O);
    Start := RdW(P, O + 26);
    If FsType = fsFAT32 Then Start := Start or (RdW(P, O + 20) shl 16);
    Size := RdL(P, O + 28);
    If P^[O] = Ord('.') Then Begin
     If FIsRoot(Clus) Then
      AddErr(Path + TL(' : entr'#130'e "', ': entry "') + Nm +
             TL('" dans le r'#130'pertoire racine', '" in the root directory'))
     Else If Nm = '.' Then Begin
      If Start <> Clus Then
       AddErr(Path + TL(' : entr'#130'e "." invalide', ': invalid "." entry'));
     End
      Else
     Begin
      If FIsRoot(Parent) Then Exp := 0 Else Exp := Parent;
      If Start <> Exp Then
       AddErr(Path + TL(' : entr'#130'e ".." invalide', ': invalid ".." entry'));
     End;
    End
     Else
    If (A and $10) <> 0 Then Begin
     Inc(NDirs);
     If (Start < 2) or (Start > FMax) Then
      AddErr(Path + Nm + TL(' : cluster de d'#130'part invalide (', ': invalid start cluster (') +
             LStr(Start) + ')')
     Else If RefC^[Start] <> 0 Then Begin
      Inc(CrossLinkedFiles);
      AddErr(Path + Nm + TL(' : r'#130'pertoire en lien crois'#130,
                            ': cross-linked directory'));
     End
      Else
     Begin
      Chain := FMark(Start, Path + Nm);
      DirUnits := DirUnits + Chain;
      FScanDir(Start, Clus, Path + Nm + '\', Depth + 1);
     End;
    End
     Else
    Begin
     Inc(NFiles);
     If Size = 0 Then Begin
      If Start <> 0 Then Begin
       If (Start >= 2) and (Start <= FMax) and (RefC^[Start] = 0) Then
        FileUnits := FileUnits + FMark(Start, Path + Nm);
       AddErr(Path + Nm + TL(' : fichier vide avec des clusters',
                             ': empty file with clusters allocated'));
      End;
     End
      Else
     If (Start < 2) or (Start > FMax) Then
      AddErr(Path + Nm + TL(' : cluster de d'#130'part invalide (', ': invalid start cluster (') +
             LStr(Start) + ')')
     Else Begin
      Chain := FMark(Start, Path + Nm);
      FileUnits := FileUnits + Chain;
      Need := ((((Size - 1) shr 9) + 1) + FSpc - 1) div FSpc;
      If Chain <> Need Then
       AddErr(Path + Nm + TL(' : la taille (', ': size (') + NStr(Size) +
              TL(' octets) ne correspond pas '#133' la cha'#140'ne (',
                 ' bytes) does not match the chain (') + LStr(Chain) +
              TL(' clusters)', ' clusters)'));
     End;
    End;
   End;
  End;
  If Fin or (Clus = 0) Then Break;
  Nx := FatT^[C];
  If (Nx >= FEoc) or (Nx < 2) or (Nx > FMax) Then Break;
  Inc(Cnt);
  If Cnt > FNClus Then Break;
  C := Nx;
  Inc(Lp);
 Until False;
 FreeMem(P, BlkSz);
End;

Procedure FatDirs;Begin
 FDirsDone := 0;
 If FsType = fsFAT32 Then Begin
  If (FRootClus >= 2) and (FRootClus <= FMax) Then Begin
   DirUnits := DirUnits + FMark(FRootClus, DrivePath + '\');
   FScanDir(FRootClus, FRootClus, DrivePath + '\', 0);
  End;
 End
  Else
 FScanDir(0, 0, DrivePath + '\', 0);
End;

{ Valeurs de la FAT : pointeurs hors du volume, vers un cluster libre... }
Procedure FatChains;
Var
 I, V, Bad, Out, ToFree, Res: LongInt;
Begin
 Bad := 0; Out := 0; ToFree := 0; Res := 0;
 For I := 2 to FMax do Begin
  If (I and 4095) = 0 Then ProgressStep(I, FMax, 60, 80);
  V := FatT^[I];
  If V = 0 Then Continue;
  If V = FBadV Then Inc(Bad)
  Else If V >= FEoc Then
  Else If V >= FResV Then Begin
   Inc(Res);
   If Res <= 3 Then AddErr(TL('Valeur r'#130'serv'#130'e dans la FAT au cluster ',
                              'Reserved FAT value at cluster ') + LStr(I));
  End
  Else If (V < 2) or (V > FMax) Then Begin
   Inc(Out);
   If Out <= 5 Then AddErr(TL('Le cluster ', 'Cluster ') + LStr(I) +
                           TL(' pointe hors du volume (', ' points outside the volume (') +
                           LStr(V) + ')');
  End
  Else If FatT^[V] = 0 Then Begin
   Inc(ToFree);
   If ToFree <= 5 Then AddErr(TL('Le cluster ', 'Cluster ') + LStr(I) +
                              TL(' pointe vers le cluster libre ', ' points to free cluster ') +
                              LStr(V));
  End;
 End;
 If Out > 5 Then AddErr(LStr(Out) + TL(' pointeurs hors du volume en tout',
                                        ' pointers outside the volume in all'));
 If ToFree > 5 Then AddErr(LStr(ToFree) + TL(' pointeurs vers des clusters libres en tout',
                                              ' pointers to free clusters in all'));
 BadUnits := Bad;
End;

{ Unites perdues (allouees dans la FAT mais d'aucun fichier) }
Procedure FatLost;
Var
 I, V, Lost, Free: LongInt;
 P: PB;
Begin
 Lost := 0;
 Free := 0;
 For I := 2 to FMax do Begin
  If (I and 4095) = 0 Then ProgressStep(I, FMax, 80, 90);
  V := FatT^[I];
  If V = 0 Then Inc(Free)
  Else If (V <> FBadV) and (RefC^[I] = 0) Then Begin
   Inc(Lost);
   RefC^[I] := 3;
  End;
 End;
 LostChains := 0;
 If Lost > 0 Then Begin
  For I := 2 to FMax do
   If RefC^[I] >= 3 Then Begin
    V := FatT^[I];
    If (V >= 2) and (V <= FMax) and (RefC^[V] >= 3) Then RefC^[V] := 4;
   End;
  For I := 2 to FMax do If RefC^[I] = 3 Then Inc(LostChains);
  LostClusters := Lost;
  AddErr(NStr(Lost) + TL(' unit'#130's d''allocation perdues dans ', ' lost allocation units in ') +
         LStr(LostChains) + TL(' cha'#140'ne(s)', ' chain(s)'));
 End;
 FreeUnits := Free;
 If (FsType = fsFAT32) and (FFsInfo <> 0) and (FFsInfo < FRsvd) and
    ReadSector(FFsInfo) Then Begin
  P := @SectorBuffer;
  V := RdL(P, 488);
  If (RdL(P, 0) = $41615252) and (V <> -1) and (V <> Free) Then
   AddNote(TL('Remarque : FSInfo indique ', 'Note: FSInfo reports ') + NStr(V) +
           TL(' clusters libres au lieu de ', ' free clusters instead of ') + NStr(Free));
 End;
End;

{ ==================================================================== }
{ NTFS                                                                 }
{ ==================================================================== }

{ LCN du VCN Vcn d'un attribut (Cnt : clusters restants dans l'extension) ;
  -1 pour un creux, -2 si le VCN n'est pas decrit }
Function RunLcn(Var R: TRunList; Vcn: LongInt; Var Cnt: LongInt): LongInt;
Var
 K: LongInt;
Begin
 RunLcn := -2;
 Cnt := 0;
 For K := 0 to R.N - 1 do
  If (Vcn >= R.V[K]) and (Vcn < R.V[K] + R.L[K]) Then Begin
   Cnt := R.V[K] + R.L[K] - Vcn;
   If R.C[K] < 0 Then RunLcn := -1 Else RunLcn := R.C[K] + (Vcn - R.V[K]);
   Exit;
  End;
End;

{ Lire Len octets (multiple de 512) d'un attribut non resident a partir
  de l'octet Off (multiple de 512) }
Function StreamRead(Var R: TRunList; Off, Len: LongInt; P: PB): Boolean;
Var
 Vcn, Within, Lcn, Cnt, Avail, N, Pos: LongInt;
Begin
 StreamRead := False;
 Pos := 0;
 While Len > 0 do Begin
  Vcn := Off div NCB;
  Within := Off mod NCB;
  Lcn := RunLcn(R, Vcn, Cnt);
  If Lcn = -2 Then Exit;
  Avail := Cnt * NCB - Within;
  N := Len;
  If N > Avail Then N := Avail;
  If Lcn = -1 Then FillChar(P^[Pos], N, 0)
  Else If Not RawRead(Lcn * NSpc + Within div 512, N div 512, @P^[Pos]) Then Exit;
  Pos := Pos + N;
  Off := Off + N;
  Len := Len - N;
 End;
 StreamRead := True;
End;

{ Correctifs de fin de secteur (USA) d'un enregistrement FILE ou INDX }
Function Fixup(P: PB; B, Size: LongInt): Boolean;
Var
 UOfs, UCnt, Usn, K: LongInt;
Begin
 Fixup := False;
 UOfs := RdW(P, B + 4);
 UCnt := RdW(P, B + 6);
 If (UCnt < 2) or (UOfs + UCnt * 2 > Size) or ((UCnt - 1) * 512 > Size) Then Exit;
 Usn := RdW(P, B + UOfs);
 For K := 1 to UCnt - 1 do Begin
  If RdW(P, B + K * 512 - 2) <> Usn Then Exit;
  P^[B + K * 512 - 2] := P^[B + UOfs + K * 2];
  P^[B + K * 512 - 1] := P^[B + UOfs + K * 2 + 1];
 End;
 Fixup := True;
End;

{ Liste des extensions (mapping pairs) de l'attribut non resident en A }
Function ParseRuns(P: PB; A: LongInt; Var R: TRunList): Boolean;
Var
 O, AEnd, H, LB, OB, K, Len, Delta, Lcn, Vcn: LongInt;
Begin
 ParseRuns := False;
 R.N := 0;
 Vcn := RdL(P, A + 16);
 Lcn := 0;
 O := A + RdW(P, A + 32);
 AEnd := A + RdL(P, A + 4);
 While (O < AEnd) and (P^[O] <> 0) do Begin
  H := P^[O];
  LB := H and 15;
  OB := H shr 4;
  If (LB = 0) or (LB > 8) or (OB > 8) or (O + 1 + LB + OB > AEnd) Then Exit;
  Len := 0;
  For K := LB - 1 downto 0 do
   If K < 4 Then Len := (Len shl 8) or P^[O + 1 + K];
  Delta := 0;
  If OB > 0 Then Begin
   For K := OB - 1 downto 0 do
    If K < 4 Then Delta := (Delta shl 8) or P^[O + 1 + LB + K];
   If (OB < 4) and ((P^[O + LB + OB] and $80) <> 0) Then
    Delta := Delta - (LongInt(1) shl (8 * OB));
  End;
  O := O + 1 + LB + OB;
  If R.N < MaxRuns Then Begin
   R.V[R.N] := Vcn;
   R.L[R.N] := Len;
   If OB = 0 Then R.C[R.N] := -1
   Else Begin
    Lcn := Lcn + Delta;
    R.C[R.N] := Lcn;
   End;
   Inc(R.N);
  End
   Else
  Begin
   If OB > 0 Then Lcn := Lcn + Delta;
  End;
  Vcn := Vcn + Len;
 End;
 ParseRuns := True;
End;

{ Premier attribut de type T dans l'enregistrement en B (-1 s'il manque) ;
  Named : False pour l'attribut sans nom }
Function FindAttr(P: PB; B, T: LongInt; NoName: Boolean): LongInt;
Var
 A, L, Used, K: LongInt;
Begin
 FindAttr := -1;
 A := RdW(P, B + 20);
 Used := RdL(P, B + 24);
 K := 0;
 While (A + 16 <= Used) and (K < 200) do Begin
  If RdL(P, B + A) = -1 Then Exit;
  L := RdL(P, B + A + 4);
  If (L < 16) or (A + L > Used) Then Exit;
  If (RdL(P, B + A) = T) and ((Not NoName) or (P^[B + A + 9] = 0)) Then Begin
   FindAttr := B + A;
   Exit;
  End;
  A := A + L;
  Inc(K);
 End;
End;

Function NtfsBoot: Boolean;
Var
 P: PB;
 K: LongInt;
 Same: Boolean;
Begin
 NtfsBoot := False;
 P := @SectorBuffer;
 If Not ReadSector(0) Then Begin
  AddErr(ReadErrMsg(0));
  Exit;
 End;
 If RdW(P, 510) <> $AA55 Then
  AddErr(TL('Signature AA55h absente du secteur d''amorce', 'Boot sector signature AA55h missing'));
 If (NSpc = 0) or ((NSpc and (NSpc - 1)) <> 0) Then Begin
  AddErr(TL('Secteurs par cluster invalide', 'Invalid sectors per cluster'));
  Exit;
 End;
 If (NRecSz < 512) or (NRecSz > 4096) Then Begin
  AddErr(TL('Taille des enregistrements de la MFT invalide : ', 'Invalid MFT record size: ') +
         LStr(NRecSz));
  Exit;
 End;
 If (NIdxSz < 512) or (NIdxSz > 65536) Then
  AddErr(TL('Taille des blocs d''index invalide : ', 'Invalid index block size: ') + LStr(NIdxSz));
 If (NMftLcn <= 0) or (NMftLcn >= NTotC) Then Begin
  AddErr(TL('Position de la MFT invalide', 'Invalid MFT location'));
  Exit;
 End;
 If (NMirrLcn <= 0) or (NMirrLcn >= NTotC) Then
  AddErr(TL('Position de $MFTMirr invalide', 'Invalid $MFTMirr location'));
 { copie du secteur d'amorce au dernier secteur }
 Move(SectorBuffer, Big^, 512);
 If ReadSector(TotalSectors) Then Begin
  Same := True;
  For K := 0 to 511 do If Big^[K] <> SectorBuffer[K] Then Same := False;
  If Not Same Then
   AddErr(TL('La copie du secteur d''amorce (dernier secteur) diff'#138're de l''original',
             'Backup boot sector (last sector) differs from the original'));
 End;
 NtfsBoot := True;
End;

Procedure MarkRuns(Var R: TRunList; Rec: LongInt);
Var
 K, C, Dup, Out: LongInt;
Begin
 Dup := 0;
 Out := 0;
 For K := 0 to R.N - 1 do
  If R.C[K] >= 0 Then Begin
   C := R.C[K];
   While C < R.C[K] + R.L[K] do Begin
    If (C < 0) or (C >= NTotC) Then Inc(Out)
    Else If BitOn(CMap, C) Then Inc(Dup)
    Else BitSet(CMap, C);
    Inc(C);
   End;
  End;
 If Out > 0 Then
  AddErr(TL('Enregistrement ', 'Record ') + LStr(Rec) + ' : ' + LStr(Out) +
         TL(' clusters hors du volume', ' clusters outside the volume'));
 If Dup > 0 Then Begin
  Inc(CrossLinkedFiles);
  AddErr(TL('Enregistrement ', 'Record ') + LStr(Rec) + ' : ' + LStr(Dup) +
         TL(' clusters d'#130'j'#133' utilis'#130's (liens crois'#130's)',
            ' clusters already in use (cross-links)'));
 End;
End;

Function RunTotal(Var R: TRunList): LongInt;
Var
 K, T: LongInt;
Begin
 T := 0;
 For K := 0 to R.N - 1 do If R.C[K] >= 0 Then T := T + R.L[K];
 RunTotal := T;
End;

{ Enregistrement 0 ($MFT), $MFTMirr, puis parcours de toute la MFT }
Function NtfsMft: Boolean;
Var
 A, K, R, R0, Cnt, B, Flags, Used, FirstA, T, L, VO, Base, NBad, NHdr,
 NFix, AttrN, MirrN, Sz: LongInt;
 Same, IsBase: Boolean;
 RL: TRunList;
Begin
 NtfsMft := False;
 { $MFT : enregistrement 0 lu directement }
 If Not RawRead(NMftLcn * NSpc, NRecSz div 512, Big) Then Begin
  AddErr(ReadErrMsg(NMftLcn * NSpc));
  Exit;
 End;
 If (RdL(Big, 0) <> $454C4946) or Not Fixup(Big, 0, NRecSz) Then Begin
  AddErr(TL('Enregistrement 0 de la MFT ($MFT) illisible', 'MFT record 0 ($MFT) is unreadable'));
  Exit;
 End;
 A := FindAttr(Big, 0, $80, True);
 If (A < 0) or (Big^[A + 8] = 0) or Not ParseRuns(Big, A, MftRL) Then Begin
  AddErr(TL('Attribut $DATA de $MFT absent ou invalide', '$MFT $DATA attribute missing or invalid'));
  Exit;
 End;
 NRecs := RdL(Big, A + 48) div NRecSz;
 If (RdL(Big, A + 52) <> 0) or (NRecs <= 16) Then Begin
  AddErr(TL('Taille de la MFT invalide', 'Invalid MFT size'));
  Exit;
 End;
 If MftRL.C[0] <> NMftLcn Then
  AddErr(TL('La MFT ne commence pas au cluster indiqu'#130' par le secteur d''amorce',
            'The MFT does not start at the cluster given by the boot sector'));
 { bitmap de la MFT }
 Sz := ((NRecs + 7) div 8 + 511) and not 511;
 MftBmp := NewBuf(Sz + 512);
 A := FindAttr(Big, 0, $B0, True);
 If A < 0 Then AddErr(TL('Attribut $BITMAP de $MFT absent', '$MFT $BITMAP attribute missing'))
 Else If Big^[A + 8] = 0 Then Begin
  L := RdL(Big, A + 16);
  If L > Sz Then L := Sz;
  Move(Big^[A + RdW(Big, A + 20)], MftBmp^, L);
 End
  Else
 Begin
  If ParseRuns(Big, A, RL) Then Begin
   L := (RdL(Big, A + 40) + 511) and not 511;
   If L > Sz Then L := Sz;
   If Not StreamRead(RL, 0, L, MftBmp) Then
    AddErr(TL('Lecture du bitmap de la MFT impossible', 'Cannot read the MFT bitmap'));
  End;
 End;
 { $MFTMirr : les 4 premiers enregistrements }
 MirrN := 4;
 If MirrN * NRecSz > 65536 Then MirrN := 65536 div NRecSz;
 If StreamRead(MftRL, 0, MirrN * NRecSz, Big) and
    RawRead(NMirrLcn * NSpc, MirrN * NRecSz div 512, Big2) Then Begin
  Same := True;
  For K := 0 to MirrN * NRecSz - 1 do If Big^[K] <> Big2^[K] Then Same := False;
  If Not Same Then
   AddErr(TL('$MFTMirr ne correspond pas aux premiers enregistrements de la MFT',
             '$MFTMirr does not match the first MFT records'));
 End
  Else
 AddErr(TL('Lecture de $MFTMirr impossible', 'Cannot read $MFTMirr'));
 { tableaux par enregistrement et carte des clusters }
 InUseB := NewBuf(NRecs div 8 + 8);
 IsDirB := NewBuf(NRecs div 8 + 8);
 GetMem(SeqA, NRecs * 4 + 8);
 GetMem(ParRec, NRecs * 4 + 8);
 GetMem(ParSeq, NRecs * 4 + 8);
 CMap := NewBuf(NTotC div 8 + 8);
 If (SeqA = Nil) or (ParRec = Nil) or (ParSeq = Nil) or (CMap = Nil) Then Begin
  AddErr(TL('M'#130'moire insuffisante', 'Not enough memory'));
  Exit;
 End;
 For R := 0 to NRecs - 1 do Begin
  SeqA^[R] := 0;
  ParRec^[R] := -1;
  ParSeq^[R] := 0;
 End;
 NBad := 0; NHdr := 0; NFix := 0; AttrN := 0;
 BmpRL.N := 0;
 BmpDataSize := 0;
 R0 := 0;
 While R0 < NRecs do Begin
  Cnt := 65536 div NRecSz;
  If R0 + Cnt > NRecs Then Cnt := NRecs - R0;
  ProgressStep(R0, NRecs, 5, 30);
  If Not StreamRead(MftRL, R0 * NRecSz, Cnt * NRecSz, Big) Then Begin
   AddErr(TL('Lecture de la MFT impossible '#133' l''enregistrement ',
             'Cannot read the MFT at record ') + LStr(R0));
   Exit;
  End;
  For K := 0 to Cnt - 1 do Begin
   R := R0 + K;
   B := K * NRecSz;
   T := RdL(Big, B);
   If T = $44414142 Then Begin
    Inc(NBad);
    If NBad <= 5 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                             TL(' marqu'#130' d'#130'fectueux (BAAD)', ' marked bad (BAAD)'));
    Continue;
   End;
   If T <> $454C4946 Then Continue;
   Flags := RdW(Big, B + 22);
   If (Flags and 1) = 0 Then Continue;
   If Not Fixup(Big, B, NRecSz) Then Begin
    Inc(NFix);
    If NFix <= 5 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                             TL(' : correctifs de secteurs incorrects ('#130'criture interrompue)',
                                ': bad update sequence (torn write)'));
    Continue;
   End;
   Used := RdL(Big, B + 24);
   FirstA := RdW(Big, B + 20);
   If (RdL(Big, B + 28) <> NRecSz) or (Used > NRecSz) or (FirstA < 42) or
      (FirstA >= Used) Then Begin
    Inc(NHdr);
    If NHdr <= 5 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                             TL(' : en-t'#136'te invalide', ': invalid header'));
    Continue;
   End;
   BitSet(InUseB, R);
   If (Flags and 2) <> 0 Then BitSet(IsDirB, R);
   SeqA^[R] := RdW(Big, B + 16);
   Base := RdL(Big, B + 32);
   IsBase := (Base = 0) and (RdW(Big, B + 36) = 0);
   If IsBase and (R >= 16) Then Begin
    If (Flags and 2) <> 0 Then Inc(NDirs) Else Inc(NFiles);
   End;
   { attributs }
   A := FirstA;
   L := 0;
   While A + 16 <= Used do Begin
    T := RdL(Big, B + A);
    If T = -1 Then Break;
    L := RdL(Big, B + A + 4);
    If (L < 16) or (A + L > Used) or ((L and 7) <> 0) Then Begin
     Inc(AttrN);
     If AttrN <= 5 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                               TL(' : attribut de longueur invalide', ': attribute with invalid length'));
     Break;
    End;
    If (T = $30) and (Big^[B + A + 8] = 0) and IsBase and (ParRec^[R] = -1) Then Begin
     VO := RdW(Big, B + A + 20);
     ParRec^[R] := RdL(Big, B + A + VO);
     If RdW(Big, B + A + VO + 4) <> 0 Then ParRec^[R] := -2;
     ParSeq^[R] := RdW(Big, B + A + VO + 6);
    End;
    If Big^[B + A + 8] <> 0 Then Begin
     If ParseRuns(Big, B + A, RL) Then Begin
      MarkRuns(RL, R);
      If (R = 8) and (T = $80) and (Big^[B + A + 9] <> 0) Then
       BadUnits := BadUnits + RunTotal(RL);
      If (R = 6) and (T = $80) and (Big^[B + A + 9] = 0) Then Begin
       BmpRL := RL;
       BmpDataSize := RdL(Big, B + A + 48);
      End;
      If IsBase and (R >= 16) Then Begin
       If (Flags and 2) <> 0 Then DirUnits := DirUnits + RunTotal(RL)
                             Else FileUnits := FileUnits + RunTotal(RL);
      End;
     End
      Else
     Begin
      Inc(AttrN);
      If AttrN <= 5 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                                TL(' : liste d''extensions invalide', ': invalid run list'));
     End;
    End;
    A := A + L;
   End;
  End;
  R0 := R0 + Cnt;
 End;
 If NBad > 5 Then AddErr(LStr(NBad) + TL(' enregistrements BAAD en tout', ' BAAD records in all'));
 If NFix > 5 Then AddErr(LStr(NFix) + TL(' enregistrements interrompus en tout', ' torn records in all'));
 If NHdr > 5 Then AddErr(LStr(NHdr) + TL(' en-t'#136'tes invalides en tout', ' invalid headers in all'));
 If AttrN > 5 Then AddErr(LStr(AttrN) + TL(' attributs invalides en tout', ' invalid attributes in all'));
 For R := 0 to 11 do
  If Not BitOn(InUseB, R) Then
   AddErr(TL('Fichier syst'#138'me absent : enregistrement ', 'Missing system file: record ') +
          LStr(R));
 If Not BitOn(IsDirB, 5) Then
  AddErr(TL('L''enregistrement 5 (racine) n''est pas un r'#130'pertoire',
            'Record 5 (root) is not a directory'));
 NtfsMft := True;
End;

{ Entrees d'index de P^[S..E[ du repertoire Dir ; les sous-noeuds vont
  dans la file NIdxQ }
Var
 NQT, NIdxBad: LongInt;

Procedure NtfsEntries(P: PB; S, E, Dir: LongInt);
Var
 Ref, RSeq, ELen, EFl, K: LongInt;
Begin
 K := 0;
 While (S + 16 <= E) and (K < 2000) do Begin
  Ref := RdL(P, S);
  RSeq := RdW(P, S + 6);
  ELen := RdW(P, S + 8);
  EFl := RdW(P, S + 12);
  If (ELen < 16) or (S + ELen > E) Then Begin
   Inc(NIdxBad);
   If NIdxBad <= 10 Then AddErr(TL('Index du r'#130'pertoire ', 'Index of directory ') +
                                LStr(Dir) + TL(' : entr'#130'e de longueur invalide',
                                               ': entry with invalid length'));
   Exit;
  End;
  If (EFl and 1) <> 0 Then Begin
   If NQT <= High(NIdxQ) Then Begin
    NIdxQ[NQT] := RdL(P, S + ELen - 8);
    Inc(NQT);
   End;
  End;
  If (EFl and 2) <> 0 Then Exit;
  If (RdW(P, S + 4) <> 0) or (Ref < 0) or (Ref >= NRecs) or Not BitOn(InUseB, Ref) Then Begin
   Inc(NIdxBad);
   If NIdxBad <= 10 Then AddErr(TL('Index du r'#130'pertoire ', 'Index of directory ') +
                                LStr(Dir) + TL(' : entr'#130'e vers un enregistrement libre (',
                                               ': entry to a free record (') + LStr(Ref) + ')');
  End
   Else
  If SeqA^[Ref] <> RSeq Then Begin
   Inc(NIdxBad);
   If NIdxBad <= 10 Then AddErr(TL('Index du r'#130'pertoire ', 'Index of directory ') +
                                LStr(Dir) + TL(' : num'#130'ro de s'#130'quence incorrect pour ',
                                               ': wrong sequence number for ') + LStr(Ref));
  End;
  S := S + ELen;
  Inc(K);
 End;
End;

{ Parents des enregistrements et index des repertoires }
Procedure NtfsDirs;
Var
 R, Pr, A, IR, QH, Off, VUnit, Done, Total, MaxBlk, NPar, ESt: LongInt;
 Rec, IB: PB;
 HasAlloc: Boolean;
Begin
 NPar := 0;
 For R := 0 to NRecs - 1 do
  If BitOn(InUseB, R) and (ParRec^[R] <> -1) and (R <> 5) Then Begin
   Pr := ParRec^[R];
   If (Pr < 0) or (Pr >= NRecs) or Not BitOn(InUseB, Pr) or Not BitOn(IsDirB, Pr) Then Begin
    Inc(NPar);
    If NPar <= 10 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                              TL(' : r'#130'pertoire parent invalide (', ': invalid parent directory (') +
                              LStr(Pr) + ')');
   End
    Else
   If SeqA^[Pr] <> ParSeq^[R] Then Begin
    Inc(NPar);
    If NPar <= 10 Then AddErr(TL('Enregistrement ', 'Record ') + LStr(R) +
                              TL(' : parent ', ': parent ') + LStr(Pr) +
                              TL(' d''une autre s'#130'quence (fichier orphelin)',
                                 ' of another sequence (orphan file)'));
   End;
  End;
 If NPar > 10 Then AddErr(LStr(NPar) + TL(' fichiers orphelins en tout', ' orphan files in all'));
 { index $I30 de chaque repertoire }
 Rec := NewBuf(NRecSz);
 IB := NewBuf(NIdxSz);
 If NIdxSz >= NCB Then VUnit := NCB Else VUnit := 512;
 NIdxBad := 0;
 Total := 0;
 For R := 0 to NRecs - 1 do If BitOn(IsDirB, R) Then Inc(Total);
 Done := 0;
 For R := 0 to NRecs - 1 do Begin
  If Not BitOn(IsDirB, R) Then Continue;
  Inc(Done);
  If (Done and 15) = 0 Then ProgressStep(Done, Total, 30, 60);
  If Not StreamRead(MftRL, R * NRecSz, NRecSz, Rec) or Not Fixup(Rec, 0, NRecSz) Then Continue;
  A := FindAttr(Rec, 0, $90, False);
  If A < 0 Then Begin
   If FindAttr(Rec, 0, $20, False) < 0 Then
    AddErr(TL('R'#130'pertoire ', 'Directory ') + LStr(R) +
           TL(' sans racine d''index ($INDEX_ROOT)', ' without index root ($INDEX_ROOT)'));
   Continue;
  End;
  IR := A + RdW(Rec, A + 20);
  NQT := 0;
  ESt := IR + 16 + RdL(Rec, IR + 16);
  NtfsEntries(Rec, ESt, IR + 16 + RdL(Rec, IR + 20), R);
  If NQT = 0 Then Continue;
  A := FindAttr(Rec, 0, $A0, False);
  HasAlloc := (A >= 0) and (Rec^[A + 8] <> 0) and ParseRuns(Rec, A, IdxRL);
  If Not HasAlloc Then Begin
   If FindAttr(Rec, 0, $20, False) < 0 Then
    AddErr(TL('R'#130'pertoire ', 'Directory ') + LStr(R) +
           TL(' : $INDEX_ALLOCATION absent', ': $INDEX_ALLOCATION missing'));
   Continue;
  End;
  MaxBlk := RdL(Rec, A + 40) div NIdxSz + 1;
  QH := 0;
  While (QH < NQT) and (QH < MaxBlk) do Begin
   Off := NIdxQ[QH] * VUnit;
   Inc(QH);
   If Not StreamRead(IdxRL, Off, NIdxSz, IB) Then Begin
    AddErr(TL('R'#130'pertoire ', 'Directory ') + LStr(R) +
           TL(' : bloc d''index illisible', ': unreadable index block'));
    Continue;
   End;
   If (RdL(IB, 0) <> $58444E49) or Not Fixup(IB, 0, NIdxSz) Then Begin
    AddErr(TL('R'#130'pertoire ', 'Directory ') + LStr(R) +
           TL(' : bloc d''index INDX invalide', ': invalid INDX index block'));
    Continue;
   End;
   NtfsEntries(IB, $18 + RdL(IB, $18), $18 + RdL(IB, $1C), R);
  End;
  If NQT > MaxBlk Then
   AddErr(TL('R'#130'pertoire ', 'Directory ') + LStr(R) +
          TL(' : boucle dans l''arbre d''index', ': loop in the index tree'));
 End;
 If NIdxBad > 10 Then AddErr(LStr(NIdxBad) + TL(' entr'#130'es d''index invalides en tout',
                                                 ' invalid index entries in all'));
 FreeMem(Rec, NRecSz);
 FreeMem(IB, NIdxSz);
End;

{ Bitmap de la MFT et enregistrements en service }
Procedure NtfsMftBitmap;
Var
 R, Miss, Lost: LongInt;
Begin
 Miss := 0;
 Lost := 0;
 For R := 0 to NRecs - 1 do Begin
  If (R and 4095) = 0 Then ProgressStep(R, NRecs, 60, 80);
  If BitOn(InUseB, R) and Not BitOn(MftBmp, R) Then Inc(Miss)
  Else If (R >= 24) and BitOn(MftBmp, R) and Not BitOn(InUseB, R) Then Inc(Lost);
 End;
 If Miss > 0 Then
  AddErr(LStr(Miss) + TL(' enregistrement(s) en service marqu'#130'(s) libre(s) dans le bitmap de la MFT',
                          ' record(s) in use marked free in the MFT bitmap'));
 If Lost > 0 Then
  AddErr(LStr(Lost) + TL(' enregistrement(s) libre(s) marqu'#130'(s) utilis'#130'(s) dans le bitmap de la MFT',
                          ' free record(s) marked in use in the MFT bitmap'));
End;

{ $Bitmap du volume contre les clusters des fichiers }
Procedure NtfsFree;
Var
 Sz, K, Last, U, B, UsedFree, Lost, Free: LongInt;
 VB: PB;
Begin
 If BmpRL.N = 0 Then Begin
  AddErr(TL('$Bitmap (enregistrement 6) introuvable', '$Bitmap (record 6) not found'));
  Exit;
 End;
 Sz := ((NTotC + 7) div 8 + 511) and not 511;
 VB := NewBuf(Sz);
 If Not StreamRead(BmpRL, 0, Sz, VB) Then Begin
  AddErr(TL('Lecture de $Bitmap impossible', 'Cannot read $Bitmap'));
  FreeMem(VB, Sz);
  Exit;
 End;
 UsedFree := 0; Lost := 0; Free := 0;
 Last := NTotC div 8;
 For K := 0 to Last do Begin
  If (K and 65535) = 0 Then ProgressStep(K, Last + 1, 80, 100);
  U := CMap^[K];
  B := VB^[K];
  If K = Last Then Begin
   U := U and ((1 shl (NTotC and 7)) - 1);
   B := B and ((1 shl (NTotC and 7)) - 1);
   Free := Free + PopT[(not B) and ((1 shl (NTotC and 7)) - 1)];
  End
   Else
  Free := Free + PopT[(not B) and $FF];
  If U <> B Then Begin
   UsedFree := UsedFree + PopT[U and (not B) and $FF];
   Lost := Lost + PopT[B and (not U) and $FF];
  End;
 End;
 FreeMem(VB, Sz);
 FreeUnits := Free;
 If UsedFree > 0 Then
  AddErr(NStr(UsedFree) + TL(' clusters utilis'#130's sont marqu'#130's libres dans $Bitmap',
                              ' clusters in use are marked free in $Bitmap'));
 If Lost > 0 Then Begin
  LostClusters := Lost;
  AddErr(NStr(Lost) + TL(' clusters marqu'#130's utilis'#130's n''appartiennent '#133' aucun fichier',
                          ' clusters marked in use belong to no file'));
 End;
End;

{ ==================================================================== }
{ HPFS                                                                 }
{ ==================================================================== }

Var
 HDup, HOut: LongInt;

{ Secteurs du systeme (sans controle de liens croises) }
Procedure HSys(L, N: LongInt);
Var
 K: LongInt;
Begin
 For K := L to L + N - 1 do
  If (K >= 0) and (K < HTot) Then BitSet(SMap, K);
End;

{ Secteurs d'un fichier ou d'une structure : hors du volume ou deja
  utilises (lien croise) }
Function HMark(L, N: LongInt; Const Nm: String): Boolean;
Var
 K, Dup: LongInt;
Begin
 HMark := False;
 If (L < 0) or (N < 0) or (L + N > HTot) or (L + N < L) Then Begin
  Inc(HOut);
  If HOut <= 10 Then AddErr(Nm + TL(' : secteurs hors du volume (', ': sectors outside the volume (') +
                            LStr(L) + ')');
  Exit;
 End;
 Dup := 0;
 For K := L to L + N - 1 do
  If BitOn(SMap, K) Then Inc(Dup) Else BitSet(SMap, K);
 If Dup > 0 Then Begin
  Inc(HDup);
  Inc(CrossLinkedFiles);
  If HDup <= 10 Then AddErr(Nm + TL(' : lien crois'#130' (secteur ', ': cross-link (sector ') +
                            LStr(L) + ')');
  Exit;
 End;
 HMark := True;
End;

Function HpfsBoot: Boolean;
Var
 V: LongInt;
Begin
 HpfsBoot := False;
 If RdL(@SB, 4) <> LongInt($FA53E9C5) Then
  AddErr(TL('Signature du superbloc incorrecte', 'Bad super block signature'));
 If Not (SB[8] in [2, 3]) Then
  AddErr(TL('Version HPFS inconnue : ', 'Unknown HPFS version: ') + LStr(SB[8]));
 V := TotSecOf;
 If (V <> 0) and (HTot > V) Then
  AddErr(TL('Le superbloc d'#130'clare plus de secteurs que la partition',
            'The super block declares more sectors than the partition'));
 HRoot := RdL(@SB, 12);
 HList := RdL(@SB, 24);
 HDirS := RdL(@SB, 52);
 HDirE := RdL(@SB, 56);
 HDirBmp := RdL(@SB, 60);
 If (HTot < 64) Then Begin
  AddErr(TL('Taille du volume invalide', 'Invalid volume size'));
  Exit;
 End;
 If (HRoot <= 17) or (HRoot >= HTot) Then Begin
  AddErr(TL('Fnode de la racine invalide', 'Invalid root fnode'));
  Exit;
 End;
 If (HList <= 17) or (HList >= HTot) Then Begin
  AddErr(TL('Liste des bitmaps invalide', 'Invalid bitmap list'));
  Exit;
 End;
 If (RdL(@SP, 0) <> LongInt($F9911849)) or (RdL(@SP, 4) <> LongInt($FA5229C5)) Then
  AddErr(TL('Signature du bloc de r'#130'serve incorrecte', 'Bad spare block signature'));
 If (SP[8] and 1) <> 0 Then
  AddErr(TL('Le volume est marqu'#130' "sale" (non d'#130'mont'#130' proprement)',
            'The volume is marked dirty (not unmounted cleanly)'));
 If RdL(@SP, 16) > 0 Then
  AddNote(TL('Remarque : ', 'Note: ') + LStr(RdL(@SP, 16)) +
          TL(' secteur(s) remplac'#130'(s) (hotfix)', ' sector(s) hot-fixed'));
 If (HDirS > 0) and ((HDirE < HDirS) or (HDirE >= HTot)) Then
  AddErr(TL('Bande des r'#130'pertoires invalide', 'Invalid directory band'));
 HpfsBoot := True;
End;

{ Bitmaps des bandes et structures du systeme }
Function HpfsBitmaps: Boolean;
Var
 B, L, K, N, Next, Guard: LongInt;
 LB: PB;
Begin
 HpfsBitmaps := False;
 HNB := (HTot + 16383) div 16384;
 HListN := ((HNB * 4 + 2047) div 2048) * 4;
 SMap := NewBuf(HTot div 8 + 8);
 HBmp := NewBuf(HNB * 2048 + 8);
 LB := NewBuf(HListN * 512);
 If (SMap = Nil) or (HBmp = Nil) or (LB = Nil) Then Begin
  AddErr(TL('M'#130'moire insuffisante', 'Not enough memory'));
  Exit;
 End;
 If Not RawRead(HList, HListN, LB) Then Begin
  AddErr(ReadErrMsg(HList));
  Exit;
 End;
 HSys(0, 18);
 HSys(HList, HListN);
 For B := 0 to HNB - 1 do Begin
  ProgressStep(B, HNB, 5, 30);
  L := RdL(LB, B * 4);
  If (L <= 17) or (L + 4 > HTot) Then Begin
   AddErr(TL('Bitmap de la bande ', 'Bitmap of band ') + LStr(B) + TL(' invalide', ' is invalid'));
   Continue;
  End;
  If Not RawRead(L, 4, @HBmp^[B * 2048]) Then AddErr(ReadErrMsg(L));
  HSys(L, 4);
 End;
 FreeMem(LB, HListN * 512);
 { secteurs defectueux (liste chainee de blocs de 4 secteurs) }
 L := RdL(@SB, 32);
 Guard := 0;
 While (L > 0) and (L + 4 <= HTot) and (Guard < 1000) do Begin
  HSys(L, 4);
  If Not ReadSector(L) Then Break;
  L := RdL(@SectorBuffer, 0);
  Inc(Guard);
 End;
 { table de remplacement (hotfix) et secteurs de remplacement }
 L := RdL(@SP, 12);
 If (L > 0) and (L + 4 <= HTot) Then Begin
  HSys(L, 4);
  N := RdL(@SP, 20);
  If (N > 0) and (N <= 256) and RawRead(L, 4, Big) Then
   For K := 0 to N - 1 do HSys(RdL(Big, (N + K) * 4), 1);
 End;
 { pages de codes }
 L := RdL(@SP, 32);
 If (L > 0) and (L < HTot) Then Begin
  HSys(L, 1);
  If ReadSector(L) Then Begin
   N := RdL(@SectorBuffer, 4);
   If N > 24 Then N := 24;
   For K := 0 to N - 1 do Begin
    Next := RdL(@SectorBuffer, 16 + K * 20 + 8);
    If (Next > 0) and (Next < HTot) Then HSys(Next, 1);
   End;
  End;
 End;
 { dnodes de reserve }
 N := RdL(@SP, 28);
 If N > 100 Then N := 100;
 For K := 0 to N - 1 do Begin
  L := RdL(@SP, 108 + K * 4);
  If L > 0 Then HSys(L, 4);
 End;
 { table des identificateurs }
 L := RdL(@SB, 96);
 If (L > 0) and (L + 8 <= HTot) Then HSys(L, 8);
 { bande des repertoires et sa bitmap }
 FillChar(HDBm, SizeOf(HDBm), 0);
 HNDn := 0;
 If (HDirS > 0) and (HDirE >= HDirS) and (HDirE < HTot) Then Begin
  HSys(HDirS, HDirE - HDirS + 1);
  HNDn := (HDirE - HDirS + 1) div 4;
  If HNDn > 16384 Then HNDn := 16384;
  If (HDirBmp > 0) and (HDirBmp + 4 <= HTot) Then Begin
   HSys(HDirBmp, 4);
   If Not RawRead(HDirBmp, 4, @HDBm) Then AddErr(ReadErrMsg(HDirBmp));
  End;
 End;
 DnSeen := NewBuf(HNDn div 8 + 8);
 HpfsBitmaps := True;
End;

Var
 HTreeOut: LongInt;

{ Arbre B+ d'allocation (fnode : en-tete en 56, noeuds en 64 ; anode :
  en-tete en 12, noeuds en 20) ; renvoie le nombre de secteurs }
Function HTree(P: PB; Hd, Nd, Cap: LongInt; Const Nm: String; Depth: LongInt): LongInt;
Var
 Fl, NU, K, Tot, Dn, Len, Dsk: LongInt;
 A: PB;
Begin
 HTree := 0;
 If Depth > 10 Then Exit;
 Fl := P^[Hd];
 NU := P^[Hd + 5];
 Tot := 0;
 If (Fl and $80) <> 0 Then Begin
  If NU > (Cap * 3) div 2 Then Begin
   AddErr(Nm + TL(' : arbre d''allocation invalide', ': invalid allocation tree'));
   Exit;
  End;
  For K := 0 to NU - 1 do Begin
   Dn := RdL(P, Nd + K * 8 + 4);
   If Not HMark(Dn, 1, Nm) Then Continue;
   A := NewBuf(512);
   If RawRead(Dn, 1, A) and (RdL(A, 0) = $37E40AAE) and (RdL(A, 4) = Dn) Then
    Tot := Tot + HTree(A, 12, 20, 40, Nm, Depth + 1)
   Else AddErr(Nm + TL(' : anode invalide (secteur ', ': invalid anode (sector ') + LStr(Dn) + ')');
   FreeMem(A, 512);
  End;
 End
  Else
 Begin
  If NU > Cap Then Begin
   AddErr(Nm + TL(' : arbre d''allocation invalide', ': invalid allocation tree'));
   Exit;
  End;
  For K := 0 to NU - 1 do Begin
   Len := RdL(P, Nd + K * 12 + 4);
   Dsk := RdL(P, Nd + K * 12 + 8);
   If HMark(Dsk, Len, Nm) Then Tot := Tot + Len;
  End;
 End;
 HTree := Tot;
End;

{ Attributs etendus (EA) et liste d'acces (ACL) hors du fnode }
Procedure HExtra(F: PB; Const Nm: String);
Var
 L, S: LongInt;
 A: PB;
Begin
 L := RdL(F, 44);
 S := RdL(F, 48);
 If (L > 0) and (S > 0) Then Begin
  If (F^[54] and 1) = 0 Then HMark(S, (L + 511) div 512, Nm + ' (EA)')
  Else If HMark(S, 1, Nm + ' (EA)') Then Begin
   A := NewBuf(512);
   If RawRead(S, 1, A) and (RdL(A, 0) = $37E40AAE) Then HTree(A, 12, 20, 40, Nm + ' (EA)', 1);
   FreeMem(A, 512);
  End;
 End;
 L := RdL(F, 32);
 S := RdL(F, 36);
 If (L > 0) and (S > 0) Then Begin
  If F^[42] = 0 Then HMark(S, (L + 511) div 512, Nm + ' (ACL)')
  Else If HMark(S, 1, Nm + ' (ACL)') Then Begin
   A := NewBuf(512);
   If RawRead(S, 1, A) and (RdL(A, 0) = $37E40AAE) Then HTree(A, 12, 20, 40, Nm + ' (ACL)', 1);
   FreeMem(A, 512);
  End;
 End;
End;

Procedure HScanDir(Fn, Up: LongInt; Path: String; Depth: LongInt); Forward;

{ Arbre de dnodes du repertoire de fnode DirFn }
Procedure HWalkDn(Dn, UpDn, DirFn: LongInt; Const Path: String; Depth, DDepth: LongInt);
Var
 D, F: PB;
 E, FF, Len, Fl, FnL, Size, NL, K, Idx, Need, Tot: LongInt;
 Nm: String;
 Attr: Byte;
Begin
 If DDepth > 30 Then Begin
  AddErr(Path + TL(' : arbre de dnodes trop profond', ': dnode tree too deep'));
  Exit;
 End;
 If (HDirS > 0) and (Dn >= HDirS) and (Dn <= HDirE) Then Begin
  Idx := (Dn - HDirS) div 4;
  If ((Dn - HDirS) mod 4 <> 0) or (Idx >= HNDn) Then Begin
   AddErr(Path + TL(' : dnode mal align'#130, ': misaligned dnode'));
   Exit;
  End;
  If BitOn(DnSeen, Idx) Then Begin
   Inc(CrossLinkedFiles);
   AddErr(Path + TL(' : dnode utilis'#130' deux fois (', ': dnode used twice (') + LStr(Dn) + ')');
   Exit;
  End;
  BitSet(DnSeen, Idx);
  If BitOn(@HDBm, Idx) Then
   AddErr(Path + TL(' : dnode marqu'#130' libre dans la bande (', ': dnode marked free in the band (') +
          LStr(Dn) + ')');
 End
  Else
 If Not HMark(Dn, 4, Path + ' (dnode)') Then Exit;
 D := NewBuf(2048);
 If Not RawRead(Dn, 4, D) Then Begin
  AddErr(Path + ' : ' + ReadErrMsg(Dn));
  FreeMem(D, 2048);
  Exit;
 End;
 If (RdL(D, 0) <> $77E40AAE) or (RdL(D, 16) <> Dn) Then Begin
  AddErr(Path + TL(' : dnode invalide (secteur ', ': invalid dnode (sector ') + LStr(Dn) + ')');
  FreeMem(D, 2048);
  Exit;
 End;
 If RdL(D, 12) <> UpDn Then
  AddErr(Path + TL(' : lien vers le parent incorrect dans le dnode ', ': wrong parent link in dnode ') +
         LStr(Dn));
 FF := RdL(D, 4);
 If (FF < 20) or (FF > 2048) Then Begin
  AddErr(Path + TL(' : dnode ', ': dnode ') + LStr(Dn) + TL(' mal rempli', ' badly filled'));
  FreeMem(D, 2048);
  Exit;
 End;
 E := 20;
 While E + 32 <= FF do Begin
  Len := RdW(D, E);
  Fl := D^[E + 2];
  If (Len < 32) or (E + Len > FF) or ((Len and 3) <> 0) Then Begin
   AddErr(Path + TL(' : entr'#130'e de r'#130'pertoire invalide (dnode ', ': invalid directory entry (dnode ') +
          LStr(Dn) + ')');
   Break;
  End;
  If (Fl and 4) <> 0 Then
   HWalkDn(RdL(D, E + Len - 4), Dn, DirFn, Path, Depth, DDepth + 1);
  If (Fl and 8) <> 0 Then Break;
  If (Fl and 1) = 0 Then Begin
   Attr := D^[E + 3];
   FnL := RdL(D, E + 4);
   Size := RdL(D, E + 12);
   NL := D^[E + 30];
   If 31 + NL > Len Then Begin
    AddErr(Path + TL(' : nom trop long (dnode ', ': name too long (dnode ') + LStr(Dn) + ')');
    Break;
   End;
   Nm := '';
   For K := 0 to NL - 1 do If K < 200 Then Nm := Nm + Chr(D^[E + 31 + K]);
   If (Attr and $10) <> 0 Then Begin
    Inc(NDirs);
    HScanDir(FnL, DirFn, Path + Nm + '\', Depth + 1);
   End
    Else
   Begin
    Inc(NFiles);
    If NFiles and 63 = 0 Then ShowProgress(30 + Integer(NFiles mod 30));
    If HMark(FnL, 1, Path + Nm) Then Begin
     F := NewBuf(512);
     If Not RawRead(FnL, 1, F) or (RdL(F, 0) <> LongInt($F7E40AAE)) Then
      AddErr(Path + Nm + TL(' : fnode invalide (secteur ', ': invalid fnode (sector ') + LStr(FnL) + ')')
     Else Begin
      If RdL(F, 28) <> DirFn Then
       AddErr(Path + Nm + TL(' : le fnode ne pointe pas vers son r'#130'pertoire',
                             ': fnode does not point to its directory'));
      If (F^[55] and 1) <> 0 Then
       AddErr(Path + Nm + TL(' : fichier marqu'#130' r'#130'pertoire dans son fnode',
                             ': file marked as directory in its fnode'));
      Tot := HTree(F, 56, 64, 8, Path + Nm, 0);
      FileUnits := FileUnits + Tot + 1;
      Need := (((RdL(F, 160) - 1) shr 9) + 1);
      If RdL(F, 160) = 0 Then Need := 0;
      If Tot < Need Then
       AddErr(Path + Nm + TL(' : allocation plus petite que la taille du fichier',
                             ': allocation smaller than the file size'));
      If RdL(F, 160) <> Size Then
       AddErr(Path + Nm + TL(' : taille diff'#130'rente dans le r'#130'pertoire et le fnode',
                             ': size differs between directory and fnode'));
      HExtra(F, Path + Nm);
     End;
     FreeMem(F, 512);
    End;
   End;
  End;
  E := E + Len;
 End;
 FreeMem(D, 2048);
End;

Procedure HScanDir(Fn, Up: LongInt; Path: String; Depth: LongInt);
Var
 F: PB;
 Dn: LongInt;
Begin
 If Depth > 60 Then Begin
  AddErr(Path + TL(' : r'#130'pertoires trop imbriqu'#130's', ': directories nested too deep'));
  Exit;
 End;
 If Not HMark(Fn, 1, Path) Then Exit;
 DirUnits := DirUnits + 1;
 F := NewBuf(512);
 If Not RawRead(Fn, 1, F) or (RdL(F, 0) <> LongInt($F7E40AAE)) Then Begin
  AddErr(Path + TL(' : fnode invalide (secteur ', ': invalid fnode (sector ') + LStr(Fn) + ')');
  FreeMem(F, 512);
  Exit;
 End;
 If (F^[55] and 1) = 0 Then
  AddErr(Path + TL(' : fnode sans l''indicateur de r'#130'pertoire', ': fnode without the directory flag'));
 If RdL(F, 28) <> Up Then
  AddErr(Path + TL(' : le fnode ne pointe pas vers son parent', ': fnode does not point to its parent'));
 HExtra(F, Path);
 If F^[61] < 1 Then
  AddErr(Path + TL(' : r'#130'pertoire sans dnode', ': directory without dnode'))
 Else Begin
  Dn := RdL(F, 72);
  FreeMem(F, 512);
  F := Nil;
  HWalkDn(Dn, Fn, Fn, Path, Depth, 0);
 End;
 If F <> Nil Then FreeMem(F, 512);
End;

{ dnodes de la bande marques utilises mais d'aucun repertoire }
Procedure HpfsBand;
Var
 K, Lost: LongInt;
Begin
 Lost := 0;
 For K := 0 to HNDn - 1 do
  If Not BitOn(@HDBm, K) and Not BitOn(DnSeen, K) Then Inc(Lost);
 If Lost > 0 Then
  AddErr(LStr(Lost) + TL(' dnode(s) de la bande marqu'#130'(s) utilis'#130'(s) sans r'#130'pertoire',
                          ' band dnode(s) marked in use without a directory'));
End;

Procedure HpfsFree;
Var
 K, Last, U, B, M, UsedFree, Lost, Free, FirstLost: LongInt;
Begin
 UsedFree := 0; Lost := 0; Free := 0; FirstLost := -1;
 Last := (HTot - 1) div 8;
 For K := 0 to Last do Begin
  If (K and 65535) = 0 Then ProgressStep(K, Last + 1, 80, 100);
  M := $FF;
  If (K = Last) and ((HTot and 7) <> 0) Then M := (1 shl (HTot and 7)) - 1;
  U := SMap^[K] and M;
  B := HBmp^[K] and M;       { 1 = libre }
  Free := Free + PopT[B];
  UsedFree := UsedFree + PopT[U and B];
  If (FirstLost < 0) and (((not U) and (not B) and M) <> 0) Then Begin
   FirstLost := K * 8;
   While BitOn(SMap, FirstLost) or BitOn(HBmp, FirstLost) do Inc(FirstLost);
  End;
  Lost := Lost + PopT[(not U) and (not B) and M];
 End;
 FreeUnits := Free;
 If UsedFree > 0 Then
  AddErr(NStr(UsedFree) + TL(' secteurs utilis'#130's sont marqu'#130's libres dans les bitmaps',
                              ' sectors in use are marked free in the bitmaps'));
 If Lost > 0 Then Begin
  LostClusters := Lost;
  AddErr(NStr(Lost) + TL(' secteurs marqu'#130's utilis'#130's n''appartiennent '#133' aucun fichier (',
                          ' sectors marked in use belong to no file (') +
         TL('premier : ', 'first: ') + LStr(FirstLost) + ')');
 End;
End;


{ Etat du secteur Sec pour la carte du balayage : 0 libre, 1 utilise,
  2 defectueux ; Step : secteurs de meme etat a partir de Sec }
Function SecState32(Sec: LongInt; Var Step: LongInt): Integer;
Var
 C: LongInt;
Begin
 SecState32 := 0;
 Step := 1;
 Case FsType of
  fsNTFS: Begin
   If NSpc <= 0 Then Exit;
   Step := NSpc - Sec mod NSpc;
   C := Sec div NSpc;
   If (CMap <> Nil) and (C < NTotC) and BitOn(CMap, C) Then SecState32 := 1;
  End;
  fsHPFS: Begin
   If (SMap <> Nil) and (Sec < HTot) and
      (BitOn(SMap, Sec) or Not BitOn(HBmp, Sec)) Then SecState32 := 1;
  End;
  Else Begin
   If Sec < FFirstData Then SecState32 := 1
   Else If (FatT <> Nil) and (FSpc > 0) Then Begin
    C := (Sec - FFirstData) div FSpc + 2;
    Step := FSpc - (Sec - FFirstData) mod FSpc;
    If C <= FMax Then Begin
     If FatT^[C] = FBadV Then SecState32 := 2
     Else If FatT^[C] <> 0 Then SecState32 := 1;
    End;
   End;
  End;
 End;
End;

{ ==================================================================== }
{ Deroulement et resume                                                }
{ ==================================================================== }

Procedure PhaseDone(I: TCheckItem; Pct: Integer);Begin
 Trace('etape ' + LStr(Ord(I) + 1) + ' terminee, ' + LStr(ErrorsFound) + ' erreur(s)');
 CheckStatus[I] := True;
 ShowProgress(Pct);
 ShowCheckList;
End;

Procedure PerformChecks32;
Var
 Ok: Boolean;
Begin
 ClrScr;
 ShowTitle;
 ShowFsLine(TL('Syst'#138'me de fichiers : ', 'File system: ') + FsName);
 ShowCheckList;
 LastPct := -1;
 ShowProgress(0);
 Case FsType of
  fsNTFS: Begin
   Ok := NtfsBoot;
   PhaseDone(ciMedia, 5);
   If Ok Then Ok := NtfsMft;
   PhaseDone(ciFAT, 30);
   If Ok Then NtfsDirs;
   PhaseDone(ciDirectory, 60);
   If Ok Then NtfsMftBitmap;
   PhaseDone(ciFileSystem, 80);
   If Ok Then NtfsFree;
   PhaseDone(ciFreeSpace, 100);
  End;
  fsHPFS: Begin
   Ok := HpfsBoot;
   PhaseDone(ciMedia, 5);
   If Ok Then Ok := HpfsBitmaps;
   PhaseDone(ciFAT, 30);
   If Ok Then HScanDir(HRoot, HRoot, DrivePath + '\', 0);
   PhaseDone(ciDirectory, 60);
   If Ok Then HpfsBand;
   PhaseDone(ciFileSystem, 80);
   If Ok Then HpfsFree;
   PhaseDone(ciFreeSpace, 100);
  End;
  Else Begin
   FatBoot;
   PhaseDone(ciMedia, 2);
   Ok := FatLoad;
   PhaseDone(ciFAT, 30);
   If Ok Then FatDirs;
   PhaseDone(ciDirectory, 60);
   If Ok Then FatChains;
   PhaseDone(ciFileSystem, 80);
   If Ok Then FatLost;
   PhaseDone(ciFreeSpace, 100);
  End;
 End;
 If DoSurfaceScan Then SurfaceScan
 Else If Not NonInteractive Then Begin
  If ShowDialog(TL('Balayage de surface', 'Surface Scan'),
                TL('ScanDisk a termin'#130' les tests de structure de fichiers. Voulez-vous '+
                   'effectuer un test de surface maintenant ?',
                   'ScanDisk has finished testing the file structure. Do you want to '+
                   'perform a surface scan now?'), True) Then Begin
   DoSurfaceScan := True;
   SurfaceScan;
  End;
 End;
End;

{ Taille en Ko de N unites }
Function UKb(N: LongInt): String;Begin
 If UnitBytes >= 1024 Then UKb := NStr(N * (UnitBytes div 1024))
                      Else UKb := NStr(N div (1024 div UnitBytes));
End;

Procedure ShowSummary32;
Var
 K, Shown: LongInt;
 F: Text;
 LogName: String;
Begin
 TextBackground(Black);
 TextColor(LightGray);
 ClrScr;
 WriteLn(TL('ScanDisk a v'#130'rifi'#130' ', 'ScanDisk checked ') + DrivePath + ' (' + FsName + ').');
 WriteLn;
 WriteLn(UKb(TotUnits): 14, TL(' Ko d''espace disque total', ' KB total disk space'));
 WriteLn(UKb(FileUnits): 14, TL(' Ko dans ', ' KB in ') + NStr(NFiles) + TL(' fichier(s)', ' file(s)'));
 WriteLn(UKb(DirUnits): 14, TL(' Ko dans ', ' KB in ') + NStr(NDirs) + TL(' r'#130'pertoire(s)', ' director(ies)'));
 If BadUnits > 0 Then
  WriteLn(UKb(BadUnits): 14, TL(' Ko dans des secteurs d'#130'fectueux', ' KB in bad sectors'));
 WriteLn(UKb(FreeUnits): 14, TL(' Ko disponibles', ' KB available'));
 WriteLn;
 WriteLn(NStr(UnitBytes): 14, TL(' octets dans chaque unit'#130' d''allocation', ' bytes in each allocation unit'));
 WriteLn(NStr(TotUnits): 14, TL(' unit'#130's d''allocation au total', ' total allocation units'));
 WriteLn(NStr(FreeUnits): 14, TL(' unit'#130's d''allocation disponibles', ' available allocation units'));
 If BadSectors > 0 Then
  WriteLn(NStr(BadSectors): 14, TL(' secteurs illisibles (balayage de surface)', ' unreadable sectors (surface scan)'));
 WriteLn;
 If ErrorsFound = 0 Then
  WriteLn(TL('Aucune erreur trouv'#130'e : le disque est en bon '#130'tat.',
             'No errors found: the disk is in good condition.'))
 Else
  WriteLn(LStr(ErrorsFound) + TL(' erreur(s) trouv'#130'e(s) :', ' error(s) found:'));
 Shown := 0;
 For K := 0 to LogN - 1 do
  If Shown < 6 Then Begin
   If LogErr[K] Then Write(' - ') Else Write('   ');
   WriteLn(Copy(LogMsg[K], 1, 76));
   Inc(Shown);
  End;
 If LogN > 0 Then Begin
  LogName := GetEnv('TEMP');
  If LogName <> '' Then Begin
   If LogName[Length(LogName)] <> '\' Then LogName := LogName + '\';
  End;
  LogName := LogName + 'SCANDISK.LOG';
  {$I-} Assign(F, LogName); Rewrite(F); {$I+}
  If IOResult = 0 Then Begin
   WriteLn(F, 'ScanDisk - ', DrivePath, ' (', FsName, ')');
   For K := 0 to LogN - 1 do Begin
    If LogErr[K] Then Write(F, '- ') Else Write(F, '  ');
    WriteLn(F, LogMsg[K]);
   End;
   If LogN >= MaxLog Then WriteLn(F, '...');
   Close(F);
   If LogN > Shown Then
    WriteLn(TL('Liste compl'#138'te dans ', 'Full list in ') + LogName);
  End;
  If ErrorsFound > 0 Then
   WriteLn(TL('Aucune r'#130'paration n''est faite sur un disque en service.',
              'No repair is made on a disk in use.'));
 End;
End;
{$ENDIF}

Procedure PerformChecks;
Var
 CheckDelay: Integer;
Begin
 ClrScr;
 ShowTitle;
 ShowCheckList;
 LastPct := -1;
 ShowProgress(0);
  { DÇterminer le dÇlai selon la taille du disque }
 If HasPartition or (TotalSectors > 10000) Then CheckDelay := 10 Else
 If TotalSectors > 2000 Then CheckDelay := 50
                        Else CheckDelay := 100;
  { Effectuer les vÇrifications une par une avec mise Ö jour en place }
 CheckStatus[ciMedia] := False;
 { la FAT doit etre lue avant sa verification }
 ReadFAT;
 CheckFATConsistency;
 ShowCheckList;
 Delay(CheckDelay);
 CheckStatus[ciFAT] := False;
 CheckStatus[ciFAT] := True;
 ShowProgress(40);
 ShowCheckList;
 Delay(CheckDelay);
 CheckStatus[ciDirectory] := False;
 CheckDirectoryStructure;
 ShowProgress(55);
 ShowCheckList;
 Delay(CheckDelay);
 CheckStatus[ciFileSystem] := False;
 CheckFileAllocation;
 ShowProgress(80);
 ShowCheckList;
 Delay(CheckDelay);
 CheckStatus[ciFreeSpace] := False;
 CheckLostClusters;
 ShowProgress(100);
 ShowCheckList;
 Delay(CheckDelay);
 { Demander pour le surface scan }
 Case(Language)of
  _English:Begin
   If ShowDialog('ScanDisk', 'ScanDisk has finished testing the file structure. Do you want to '+
                             'perform a surface scan now?', True)Then Begin
    DoSurfaceScan:=True;
    SurfaceScan;
   End;
  End;
  Else Begin
   If ShowDialog('Balayage de surface', 'ScanDisk a terminÇ les tests de structure de fichiers. Voulez-vous '+
                 'effectuer un test de surface maintenant ?', True)Then Begin
    DoSurfaceScan:=True;
    SurfaceScan;
   End;
  End;
 End;
End;

Procedure ShowSummary;Begin
 TextBackground(Black);
 TextColor(LightGray);
 ClrScr;
 GotoXY(1, 5);
 Write('=== RêSUMê DE LA VêRIFICATION ===');
 GotoXY(1, 6);
 Write('Secteurs totaux: ', TotalSectors);
 GotoXY(1, 7);
 Write('Secteurs dÇfectueux: ', BadSectors);
 GotoXY(1, 8);
 Write('UnitÇs d''allocations perdus: ', LostClusters);
 GotoXY(1, 9);
 Write('Fichiers avec liens croisÇs: ', CrossLinkedFiles);
 GotoXY(1, 10);
 Write('Erreurs totales: ', ErrorsFound);
 GotoXY(1, 12);
 If ErrorsFound = 0 Then Write('Aucune erreur trouvÇe. Le disque est en bon Çtat.')
  Else
 Begin
  Write('Des erreurs ont ÇtÇ dÇtectÇes.');
  GotoXY(1, 13);
  If CheckOnly Then Write('Mode vÇrification seulement - aucune rÇparation effectuÇe.') Else
  If AutoFix Then Write('RÇparations automatiques effectuÇes.')
             Else Write('Utilisez /AUTOFIX pour rÇparer automatiquement les erreurs.');
 End;
End;

BEGIN
 {$IFDEF FPC}
  {$IFDEF WINDOWS}
   SetUseACP(False);
  {$ENDIF}
 {$ENDIF}
  { Initialisation }
 Language := _French;
 TmpLanguage := GetEnv('LANGUAGE');
 If TmpLanguage<>''Then Begin
  If TmpLanguage[1]='"'Then TmpLanguage:=Copy(TmpLanguage,2,255);
  If StrToUpper(Copy(TmpLanguage,1,2))='EN'Then Language:=_English Else
  If StrToUpper(Copy(TmpLanguage,1,2))='GR'Then Language:=_Germany Else
  If StrToUpper(Copy(TmpLanguage,1,2))='IT'Then Language:=_Italian Else
  If StrToUpper(Copy(TmpLanguage,1,2))='SP'Then Language:=_Spain Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SQ')or
    (StrToUpper(Copy(TmpLanguage,1,3))='ALB')Then Language:=_Albanian Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='PT')or
    (StrToUpper(Copy(TmpLanguage,1,3))='PRT')Then Language:=_Portuguese Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='SE')or
    (StrToUpper(Copy(TmpLanguage,1,3))='SWE')Then Language:=_Swedish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='DK')or
    (StrToUpper(Copy(TmpLanguage,1,3))='DNK')Then Language:=_Danish Else
  If(StrToUpper(Copy(TmpLanguage,1,2))='JP')or
    (StrToUpper(Copy(TmpLanguage,1,3))='JPN')Then Language:=_Japanese;
 End;
  { VÇrification des paramätres d'aide }
 If (ParamStr(1) = '/?') or (ParamStr(1) = '--help') or (ParamStr(1) = '-h') or
    (ParamStr(1) = '/h') or (ParamStr(1) = '/H') Then Begin
  Case Language of
   _English: Begin
    WriteLn('SCANDISK - Disk diagnostic and repair utility');
    WriteLn;
    WriteLn('Usage: SCANDISK [drive: | filename] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  drive:     Drive to check (A:, C:, etc.)');
    WriteLn('  filename   Disk image file to check');
    WriteLn('  /AUTOFIX   Automatically fix errors');
    WriteLn('  /CHECKONLY Check only, do not fix');
    WriteLn('  /SURFACE   Perform surface scan');
    WriteLn('  /N         No questions (summary at the end)');
    WriteLn;
    WriteLn('File systems: FAT12, FAT16, FAT32, NTFS and HPFS.');
   End;
   _Germany: Begin
    WriteLn('SCANDISK - Festplatten-Diagnose- und Reparaturprogramm');
    WriteLn;
    WriteLn('Verwendung: SCANDISK [Laufwerk: | Dateiname] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  Laufwerk:  Zu prÅfendes Laufwerk (A:, C:, usw.)');
    WriteLn('  Dateiname  Zu prÅfende Festplatten-Image-Datei');
    WriteLn('  /AUTOFIX   Fehler automatisch beheben');
    WriteLn('  /CHECKONLY Nur prÅfen, nicht reparieren');
    WriteLn('  /SURFACE   OberflÑchenscan durchfÅhren');
   End;
   _Italian: Begin
    WriteLn('SCANDISK - UtilitÖ di diagnosi e riparazione disco');
    WriteLn;
    WriteLn('Utilizzo: SCANDISK [unitÖ: | nomefile] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  unitÖ:     UnitÖ da controllare (A:, C:, ecc.)');
    WriteLn('  nomefile   File immagine disco da controllare');
    WriteLn('  /AUTOFIX   Ripara automaticamente gli errori');
    WriteLn('  /CHECKONLY Solo controllo, non riparare');
    WriteLn('  /SURFACE   Esegui scansione superficie');
   End;
   _Spain: Begin
    WriteLn('SCANDISK - Utilidad de diagn¢stico y reparaci¢n de disco');
    WriteLn;
    WriteLn('Uso: SCANDISK [unidad: | archivo] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  unidad:    Unidad a verificar (A:, C:, etc.)');
    WriteLn('  archivo    Archivo de imagen de disco a verificar');
    WriteLn('  /AUTOFIX   Reparar autom†ticamente los errores');
    WriteLn('  /CHECKONLY Solo verificar, no reparar');
    WriteLn('  /SURFACE   Realizar exploraci¢n de superficie');
   End;
   _Albanian: Begin
    WriteLn('SCANDISK - Utilitar diagnostik dhe riparim disku');
    WriteLn;
    WriteLn('Pârdorimi: SCANDISK [disku: | skedari] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  disku:     Disku pâr tâ kontrolluar (A:, C:, etj.)');
    WriteLn('  skedari    Skedari imazh disku pâr tâ kontrolluar');
    WriteLn('  /AUTOFIX   Riparo automatikisht gabimet');
    WriteLn('  /CHECKONLY Vetâm kontrollo, mos riparo');
    WriteLn('  /SURFACE   Kryej skanim sipârfaqe');
   End;
   _Portuguese: Begin
    WriteLn('SCANDISK - Utilit†rio de diagn¢stico e reparo de disco');
    WriteLn;
    WriteLn('Uso: SCANDISK [unidade: | arquivo] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  unidade:   Unidade a verificar (A:, C:, etc.)');
    WriteLn('  arquivo    Arquivo de imagem de disco a verificar');
    WriteLn('  /AUTOFIX   Reparar automaticamente os erros');
    WriteLn('  /CHECKONLY Apenas verificar, nao reparar');
    WriteLn('  /SURFACE   Realizar varredura de superf°cie');
   End;
   _Swedish: Begin
    WriteLn('SCANDISK - Disk diagnos- och reparationsverktyg');
    WriteLn;
    WriteLn('AnvÑndning: SCANDISK [enhet: | filnamn] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  enhet:     Enhet att kontrollera (A:, C:, osv.)');
    WriteLn('  filnamn    Diskavbildningsfil att kontrollera');
    WriteLn('  /AUTOFIX   AtgÑrda fel automatiskt');
    WriteLn('  /CHECKONLY Bara kontrollera, reparera inte');
    WriteLn('  /SURFACE   Utfîr ytskanning');
   End;
   _Danish: Begin
    WriteLn('SCANDISK - Disk diagnose- og reparationsvaerktoj');
    WriteLn;
    WriteLn('Brug: SCANDISK [drev: | filnavn] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  drev:      Drev at kontrollere (A:, C:, osv.)');
    WriteLn('  filnavn    Disk-image-fil at kontrollere');
    WriteLn('  /AUTOFIX   Reparer fejl automatisk');
    WriteLn('  /CHECKONLY Kun kontroller, reparer ikke');
    WriteLn('  /SURFACE   Udfor overfladeskanning');
   End;
   _Japanese: Begin
    WriteLn('SCANDISK - Disuku shindan oyobi shuuri yuutiriti');
    WriteLn;
    WriteLn('Tsukaikata: SCANDISK [doraibu: | fairu mei] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  doraibu:   Chekku suru doraibu (A:, C:, nado)');
    WriteLn('  fairu mei  Chekku suru disuku imeeji fairu');
    WriteLn('  /AUTOFIX   Jidouteki ni eraa wo shuuri suru');
    WriteLn('  /CHECKONLY Chekku nomi, shuuri shinai');
    WriteLn('  /SURFACE   Hyoumen sukyan wo jikkou suru');
   End;
   Else Begin
    WriteLn('SCANDISK - Cette commande permet de lancer l''utilitaire ',
                        'de diagnostic et rÇparation de disque.');
    WriteLn;
    WriteLn('Syntaxe : SCANDISK [lecteur: | fichier] [/AUTOFIX] [/CHECKONLY] [/SURFACE]');
    WriteLn;
    WriteLn('  lecteur:   Lecteur Ö vÇrifier (A:, C:, etc.)');
    WriteLn('  fichier    Fichier image disque Ö vÇrifier');
    WriteLn('  /AUTOFIX   RÇparer automatiquement les erreurs');
    WriteLn('  /CHECKONLY VÇrification seulement, pas de rÇparation');
    WriteLn('  /SURFACE   Effectuer un scan de surface');
    WriteLn('  /N         Sans question (r'#130'sum'#130' '#133' la fin)');
    WriteLn;
    WriteLn('Syst'#138'mes de fichiers : FAT12, FAT16, FAT32, NTFS et HPFS.');
   End;
  End;
  Halt;
 End;
  { Ajustement de l'interface graphique }
 CursorOff;
 SetupColors;
  { Allouer la mÇmoire pour les tableaux FAT et ClusterMap }
 AllocateMemory;
  { Si aucun param√®tre, permettre la sÇlection d'un lecteur }
 If ParamCount = 0 Then Begin
  DrivePath := SelectDrive;
  If DrivePath = '' Then Begin
   FreeMemory;
   CursorOn;
   Halt(0);
  End;
 End
  Else
 Begin
  { Analyse des paramätres }
  DrivePath := StrToUpper(ParamStr(1));
 End;
  { Initialisation des variables }
 AutoFix := False;
 CheckOnly := False;
 DoSurfaceScan := False;
 IsImageFile := False;
 BadSectors := 0;
 LostClusters := 0;
 CrossLinkedFiles := 0;
 ErrorsFound := 0;
 HasPartition := False;
 PartitionOffset := 0;
  { ClusterMap est maintenant initialis√© dans AllocateMemory }
 FillChar(CheckStatus, SizeOf(CheckStatus), 0);
  { DÇterminer le type de cible (lecteur ou fichier image) }
 {$IFDEF Windows}
  { Pasdows (Win32) : un lecteur se lit par son volume \\.\X: comme un
    fichier image }
  If (Length(DrivePath) = 2) and (DrivePath[2] = ':') Then
   DrivePath := '\\.\' + DrivePath;
 {$ENDIF}
 If (Length(DrivePath) = 2) and (DrivePath[2] = ':') Then Begin
  { C'est un lecteur }
  IsImageFile := False;
  Case DrivePath[1] of
   'A': DriveNum := 0;
   'B': DriveNum := 1;
   'C': DriveNum := $80;
   'D': DriveNum := $81;
   Else Begin
    Case(Language)of
     _English:ShowDialog('Error', 'Unsupported drive: ' + DrivePath, False);
     Else ShowDialog('Erreur', 'Lecteur non supportÇ : ' + DrivePath, False);
    End;
    FreeMemory;
    Halt(1);
   End;
  End;
 End
  Else
 Begin
  { C'est un fichier image }
  IsImageFile := True;
  FileName := DrivePath;
  {$IFDEF FPC}
  If Copy(FileName, 1, 4) = '\\.\' Then DrivePath := Copy(FileName, 5, 2)
                                   Else DrivePath := FileName;
  {$ELSE}
  DrivePath := 'file';
  {$ENDIF}
  {$I-} Assign(FileHandle, FileName);
  Reset(FileHandle, 1);
  {$I+}
  If IOResult <> 0 Then Begin
   Case(Language)of
    _English:ShowDialog('Error', 'Cannot open file: ' + FileName, False);
    Else ShowDialog('Erreur', 'Impossible d''ouvrir le fichier : ' + FileName, False);
   End;
   FreeMemory;
   Halt(1);
  End;
  {$IFDEF FPC}
  If Not RawOpen(FileName, False) Then Begin
   ShowDialog(TL('Erreur', 'Error'), TL('Impossible d''ouvrir ', 'Cannot open ') +
              FileName, False);
   FreeMemory;
   Halt(1);
  End;
  {$ENDIF}
 End;
  { Traitement des options }
 If ParamCount > 1 Then Begin
  For ErrorsFound := 2 to ParamCount do Begin
   If StrToUpper(ParamStr(ErrorsFound)) = '/AUTOFIX' Then AutoFix := True;
   If StrToUpper(ParamStr(ErrorsFound)) = '/CHECKONLY' Then CheckOnly := True;
   If StrToUpper(ParamStr(ErrorsFound)) = '/SURFACE' Then DoSurfaceScan := True;
   {$IFDEF FPC}
   If StrToUpper(ParamStr(ErrorsFound)) = '/N' Then NonInteractive := True;
   {$ENDIF}
  End;
 End;
 ErrorsFound := 0;
  { DÇtecter les partitions pour les fichiers images }
 If IsImageFile Then Begin
  If Not DetectPartition Then Begin
   If IsImageFile Then Close(FileHandle);
   FreeMemory;
   Halt(1);
  End;
 End;
  { Disque reel : geometrie et partition }
 If Not IsImageFile Then Begin
  DriveGeometry;
  DetectDrivePartition;
 End;
  { Lecture du secteur de boot }
 {$IFDEF FPC}
 If Not DetectFs Then Begin
 {$ELSE}
 If Not ReadBootSector Then Begin
 {$ENDIF}
  Case(Language)of
   _English:ShowDialog('Error', 'Cannot read boot sector', False);
   Else ShowDialog('Erreur', 'Impossible de lire le secteur de boot', False);
  End;
  If IsImageFile Then Close(FileHandle);
  FreeMemory;
  Halt(1);
 End;
  { Effectuer les vÇrifications avec interface graphique }
 {$IFDEF FPC}
 PerformChecks32;
 {$ELSE}
 PerformChecks;
 {$ENDIF}
  { Sauvegarde si des modifications ont ÇtÇ faites }
 If AutoFix and (ErrorsFound > 0) and Not CheckOnly Then Begin
  { RÇÇcrire la FAT si nÇcessaire }
 End;
  { Nettoyage }
 If IsImageFile Then Close(FileHandle);
  { LibÇrer la mÇmoire allouÇe }
 FreeMemory;
 { Affichage du rÇsumÇ }
 {$IFDEF FPC}
 Trace('fin, ' + LStr(ErrorsFound) + ' erreur(s)');
 RawClose;
 ShowSummary32;
 {$ELSE}
 ShowSummary;
 {$ENDIF}
 CursorOn;
  { Code de sortie }
 If ErrorsFound > 0 Then Halt(1) Else Halt(0);
END.