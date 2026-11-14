{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW95IO)
  @description: INSTALL - programme d'installation de Pasdows 95 sur un
                disque dur, en mode graphique (CD-ROM d'installation).
}

Program INSTALL;

{ Compilation : WPC -CW95IO INSTALL.PAS INSTALL.SYS

  INSTALL.SYS est l'image d'amorce du CD-ROM d'installation de
  Pasdows 95 (IMAGE/INSTALL.ISO), comme le CD de Windows 95 : le BIOS
  le charge (El Torito, sans emulation) et il s'execute seul, sans DOS
  ni unite, avec le BIOS (video, disques, horloge) et le materiel (VGA,
  controleur clavier 8042, souris PS/2). Il n'est pas sur le CD-ROM de
  demonstration (IMAGE/PASDOWS.ISO).

  Au demarrage, si le disque dur a deja une partition active, le
  programme propose de demarrer depuis le CD-ROM (touche) et, sinon,
  demarre le disque dur (Pasdows installe). L'assistant, en VGA
  640x480 16 couleurs (souris et clavier), demande :

    - la langue (francais par defaut, anglais, allemand, italien,
      espagnol) : l'assistant change de langue immediatement et
      AUTOEXEC.BAT recoit SET LANGUAGE= ;
    - le disque dur et sa partition : nouvelle partition principale
      (taille en Mo, le disque est efface) ou formatage de la partition
      existante, en FAT16, FAT32 (par defaut) ou NTFS ;
    - le fuseau horaire et l'heure d'ete (CMOS 79h, lu par VMM32) ;
    - le mode d'affichage (CMOS 7Ah-7Dh, lu par IO.SYS) ;
    - les composants (programmes d'exemple, son de demarrage, Lisez-moi).

  Puis il ecrit la table des partitions et le MBR (SETUP/MBR.ASM),
  formate la partition (FAT16 : SETUP/BOOT16.ASM ; FAT32 : SETUP/
  BOOT32.ASM, FSInfo ; NTFS 3.1 : chargeur SETUP/NTFSBOOT.ASM, MFT,
  $LogFile, $Bitmap, $UpCase, $Secure, $Extend...) et copie les
  fichiers du CD-ROM :

    C:\IO.SYS, C:\MSDOS.SYS (caches, systeme), C:\CONFIG.SYS,
    C:\AUTOEXEC.BAT, C:\COMMAND.EXE et C:\WINDOWS (VMM32.VXD, ...).

  Le secteur d'amorce charge C:\IO.SYS, qui lit alors ses fichiers sur
  le disque dur (FAT32) et demarre VMM32 avec C:\WINDOWS comme dossier
  systeme.

  Carte memoire (mode reel) :
    00000h-07BFFh  vecteurs, BIOS, pile (0000:7C00 vers le bas)
    07C00h-....    INSTALL.SYS (code, puis donnees et BSS)
    50000h-5FFFFh  NTFS : les 64 enregistrements de la MFT
    60000h-67FFFh  tampon de copie (32 Ko)
    70000h-77FFFh  secteurs de FAT et de repertoires (32 Ko)
    80000h-807FFh  tampon d'un secteur du CD-ROM
    81000h-811FFh  secteur du disque dur (MBR, secteur d'amorce)
    81400h-81BFFh  NTFS : valeur d'attribut en construction          }

{$S-,R-,I-}

Const
  ScrW      = 640;
  ScrH      = 480;
  VSeg      = $A000;
  CopySeg   = $6000;
  FatBufSeg = $7000;
  CdSeg     = $8000;
  SecSeg    = $8100;
  ValSeg    = $8140;
  MftSeg    = $5000;
  CdMax     = 48;
  MinMb     = 40;                    { FAT32 : au moins 65525 grappes }
  { systemes de fichiers : FAT16, FAT32 (defaut), NTFS ; taille
    minimale et maximale (Mo) }
  FsCount   = 3;
  FsMinMb : Array[0..2] Of LongInt = (16, 40, 32);
  FsMaxMb : Array[0..2] Of LongInt = (2047, 1000000, 1000000);

  { Palette de Windows 95 (16 couleurs) }
  cBlack   = 0;  cMaroon  = 1;  cGreen   = 2;  cOlive   = 3;
  cNavy    = 4;  cPurple  = 5;  cTeal    = 6;  cSilver  = 7;
  cGray    = 8;  cRed     = 9;  cLime    = 10; cYellow  = 11;
  cBlue    = 12; cFuchsia = 13; cAqua    = 14; cWhite   = 15;
  PalR : Array[0..15] Of Byte = (0, 32, 0, 32, 0, 32, 0, 48,
                                 32, 63, 0, 63, 0, 63, 0, 63);
  PalG : Array[0..15] Of Byte = (0, 0, 32, 32, 0, 0, 32, 48,
                                 32, 0, 63, 63, 0, 0, 63, 63);
  PalB : Array[0..15] Of Byte = (0, 0, 0, 0, 32, 32, 32, 48,
                                 32, 0, 0, 0, 63, 63, 63, 63);

  { Icones (memes dessins qu'IO.SYS) }
  icComputer = 1;  icRecycle  = 2;  icDos      = 3;  icNotepad  = 4;
  icCalc     = 5;  icText     = 6;  icFolder   = 7;  icCdrom    = 8;
  icFloppy   = 9;  icControl  = 10; icDisplay  = 11; icRegional = 12;
  icSystem   = 13; icClock    = 14; icHelp     = 15; icRun      = 16;
  icShutdown = 17; icPaint    = 18; icInfo     = 19; icWarn     = 20;
  icError    = 21; icPrograms = 22; icDocs     = 23; icSettings = 24;
  icApp      = 25; icHardDisk = 26; icLogo     = 27; icExplorer = 28;

  { Evenements }
  evKey  = 1;
  evDown = 2;
  evUp   = 3;

  { Curseur de la souris (fleche) : X = noir, W = blanc }
  CurH = 19;
  CurShape : Array[0..18] Of String[12] = (
    'X           ', 'XX          ', 'XWX         ', 'XWWX        ',
    'XWWWX       ', 'XWWWWX      ', 'XWWWWWX     ', 'XWWWWWWX    ',
    'XWWWWWWWX   ', 'XWWWWWWWWX  ', 'XWWWWWWWWWX ', 'XWWWWWWXXXXX',
    'XWWWXWWX    ', 'XWWXXWWX    ', 'XWX  XWWX   ', 'XX   XWWX   ',
    'X     XWWX  ', '      XWWX  ', '       XX   ');

  { Touches (champ Sc des evenements clavier) }
  scEsc = $01; scBack = $0E; scTab = $0F; scEnter = $1C;
  scHome = $47; scUp = $48; scPgUp = $49; scLeft = $4B;
  scRight = $4D; scEnd = $4F; scDown = $50; scPgDn = $51;

  { Pages de l'assistant }
  pgLang = 0; pgDisk = 1; pgTz = 2; pgDisp = 3; pgComp = 4;
  pgReady = 5; pgCopy = 6; pgDone = 7;
  PageMax = 7;

  { Fuseaux horaires (memes que Date/Heure de VMM32) : minutes }
  TzCount = 18;
  TzOfs : Array[0..TzCount - 1] Of Integer = (
    -600, -540, -480, -420, -360, -300, -240, -210, -180, -60, 0, 60,
    120, 180, 330, 480, 540, 600);

  { Modes d'affichage proposes : largeur, hauteur, bits par point }
  DispCount = 6;
  DispW : Array[0..DispCount - 1] Of Integer = (640, 800, 1024, 800,
                                                 1024, 640);
  DispH : Array[0..DispCount - 1] Of Integer = (480, 600, 768, 600,
                                                 768, 480);
  DispB : Array[0..DispCount - 1] Of Integer = (8, 8, 8, 16, 16, 4);

  { Dialogue de l'assistant }
  DX1 = 150; DY1 = 66; DX2 = 628; DY2 = 452;
  CX1 = 272; CX2 = 616; CY1 = 96;
  BtnY1 = 418; BtnY2 = 440;

  { Code d'amorce (SETUP/MBR.ASM : octets 0 a 439 du MBR ;
    SETUP/BOOT32.ASM : octets 90 a 509 du secteur d'amorce FAT32),
    assembles avec NASM }
  MbrCode : Array[0..439] Of Byte = (
    $FA, $31, $C0, $8E, $D0, $BC, $00, $7C, $8E, $D8, $8E, $C0, $FB, $FC,
    $BE, $00, $7C, $BF, $00, $06, $B9, $00, $01, $F3, $A5, $EA, $1E, $06,
    $00, $00, $88, $16, $B1, $06, $BE, $BE, $07, $B9, $04, $00, $F6, $04,
    $80, $75, $0A, $83, $C6, $10, $E2, $F6, $BE, $C4, $06, $EB, $69, $89,
    $36, $B2, $06, $B4, $41, $BB, $AA, $55, $8A, $16, $B1, $06, $CD, $13,
    $72, $23, $81, $FB, $55, $AA, $75, $1D, $8B, $36, $B2, $06, $8B, $44,
    $08, $A3, $BC, $06, $8B, $44, $0A, $A3, $BE, $06, $BE, $B4, $06, $B4,
    $42, $8A, $16, $B1, $06, $CD, $13, $73, $1D, $8B, $36, $B2, $06, $8A,
    $74, $01, $8B, $4C, $02, $BB, $00, $7C, $B8, $01, $02, $8A, $16, $B1,
    $06, $CD, $13, $73, $05, $BE, $E6, $06, $EB, $18, $81, $3E, $FE, $7D,
    $55, $AA, $BE, $0C, $07, $75, $0D, $8B, $36, $B2, $06, $8A, $16, $B1,
    $06, $EA, $00, $7C, $00, $00, $AC, $08, $C0, $74, $09, $B4, $0E, $BB,
    $07, $00, $CD, $10, $EB, $F2, $F4, $EB, $FD, $80, $00, $00, $10, $00,
    $01, $00, $00, $7C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $50, $61, $73, $64, $6F, $77, $73, $20, $3A, $20, $61, $75, $63, $75,
    $6E, $65, $20, $70, $61, $72, $74, $69, $74, $69, $6F, $6E, $20, $61,
    $63, $74, $69, $76, $65, $00, $50, $61, $73, $64, $6F, $77, $73, $20,
    $3A, $20, $65, $72, $72, $65, $75, $72, $20, $64, $65, $20, $6C, $65,
    $63, $74, $75, $72, $65, $20, $64, $75, $20, $64, $69, $73, $71, $75,
    $65, $00, $50, $61, $73, $64, $6F, $77, $73, $20, $3A, $20, $70, $61,
    $72, $74, $69, $74, $69, $6F, $6E, $20, $6E, $6F, $6E, $20, $61, $6D,
    $6F, $72, $63, $61, $62, $6C, $65, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00);
  VbrCode : Array[0..419] Of Byte = (
    $FA, $31, $C0, $8E, $D8, $8E, $C0, $8E, $D0, $BC, $00, $7C, $FB, $FC,
    $BE, $00, $7C, $BF, $00, $06, $B9, $00, $01, $F3, $A5, $EA, $78, $06,
    $00, $00, $88, $16, $40, $06, $66, $0F, $B7, $06, $0E, $06, $66, $03,
    $06, $1C, $06, $66, $A3, $00, $0C, $0F, $B6, $0E, $10, $06, $66, $03,
    $06, $24, $06, $E2, $F9, $66, $A3, $04, $0C, $66, $A1, $2C, $06, $66,
    $A3, $08, $0C, $E8, $9C, $00, $0F, $B6, $0E, $0D, $06, $51, $66, $50,
    $BB, $00, $08, $31, $D2, $E8, $D5, $00, $BF, $00, $08, $80, $3D, $00,
    $74, $2B, $57, $BE, $BB, $07, $B9, $0B, $00, $F3, $A6, $5F, $74, $25,
    $83, $C7, $20, $81, $FF, $00, $0A, $72, $E6, $66, $58, $66, $40, $59,
    $E2, $D1, $66, $A1, $08, $0C, $E8, $74, $00, $66, $3D, $F8, $FF, $FF,
    $0F, $72, $B6, $BE, $C6, $07, $E9, $BB, $00, $8B, $45, $14, $66, $C1,
    $E0, $10, $8B, $45, $1A, $C7, $06, $0C, $0C, $C0, $07, $66, $A3, $08,
    $0C, $E8, $3C, $00, $0F, $B6, $0E, $0D, $06, $51, $66, $50, $31, $DB,
    $8B, $16, $0C, $0C, $E8, $74, $00, $83, $06, $0C, $0C, $20, $66, $58,
    $66, $40, $59, $E2, $E8, $66, $A1, $08, $0C, $E8, $2B, $00, $66, $3D,
    $F8, $FF, $FF, $0F, $72, $CD, $66, $31, $C0, $66, $A3, $10, $7C, $8A,
    $16, $40, $06, $EA, $00, $00, $C0, $07, $66, $83, $E8, $02, $66, $0F,
    $B6, $0E, $0D, $06, $66, $F7, $E1, $66, $03, $06, $04, $0C, $C3, $66,
    $C1, $E0, $02, $66, $0F, $B7, $D8, $81, $E3, $FF, $01, $53, $66, $C1,
    $E8, $09, $66, $03, $06, $00, $0C, $66, $3B, $06, $F2, $07, $74, $0C,
    $66, $A3, $F2, $07, $BB, $00, $0A, $31, $D2, $E8, $0D, $00, $5B, $66,
    $8B, $87, $00, $0A, $66, $25, $FF, $FF, $FF, $0F, $C3, $66, $A3, $EA,
    $07, $89, $1E, $E6, $07, $89, $16, $E8, $07, $BE, $E2, $07, $B4, $42,
    $8A, $16, $40, $06, $CD, $13, $73, $05, $BE, $D4, $07, $EB, $01, $C3,
    $AC, $08, $C0, $74, $09, $B4, $0E, $BB, $07, $00, $CD, $10, $EB, $F2,
    $F4, $EB, $FD, $49, $4F, $20, $20, $20, $20, $20, $20, $53, $59, $53,
    $49, $4F, $2E, $53, $59, $53, $20, $61, $62, $73, $65, $6E, $74, $00,
    $45, $72, $72, $65, $75, $72, $20, $64, $69, $73, $71, $75, $65, $00,
    $10, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00);
  { secteur d'amorce FAT16 (SETUP/BOOT16.ASM, octets 62 a 509) }
  Vbr16Code : Array[0..447] Of Byte = (
    $FA, $31, $C0, $8E, $D8, $8E, $C0, $8E, $D0, $BC, $00, $7C, $FB, $FC,
    $BE, $00, $7C, $BF, $00, $06, $B9, $00, $01, $F3, $A5, $EA, $5C, $06,
    $00, $00, $88, $16, $24, $06, $66, $0F, $B7, $06, $0E, $06, $66, $03,
    $06, $1C, $06, $66, $A3, $00, $0C, $0F, $B6, $0E, $10, $06, $66, $0F,
    $B7, $1E, $16, $06, $66, $01, $D8, $E2, $FB, $66, $A3, $10, $0C, $66,
    $0F, $B7, $0E, $11, $06, $66, $C1, $E9, $04, $89, $0E, $14, $0C, $66,
    $01, $C8, $66, $A3, $04, $0C, $66, $A1, $10, $0C, $8B, $0E, $14, $0C,
    $51, $66, $50, $BB, $00, $08, $31, $D2, $E8, $BB, $00, $BF, $00, $08,
    $80, $3D, $00, $74, $1C, $57, $BE, $96, $07, $B9, $0B, $00, $F3, $A6,
    $5F, $74, $16, $83, $C7, $20, $81, $FF, $00, $0A, $72, $E6, $66, $58,
    $66, $40, $59, $E2, $D1, $BE, $A1, $07, $E9, $B0, $00, $66, $0F, $B7,
    $45, $1A, $C7, $06, $0C, $0C, $C0, $07, $66, $A3, $08, $0C, $E8, $3C,
    $00, $0F, $B6, $0E, $0D, $06, $51, $66, $50, $31, $DB, $8B, $16, $0C,
    $0C, $E8, $6E, $00, $83, $06, $0C, $0C, $20, $66, $58, $66, $40, $59,
    $E2, $E8, $66, $A1, $08, $0C, $E8, $2B, $00, $66, $3D, $F8, $FF, $00,
    $00, $72, $CD, $66, $31, $C0, $66, $A3, $10, $7C, $8A, $16, $24, $06,
    $EA, $00, $00, $C0, $07, $66, $83, $E8, $02, $66, $0F, $B6, $0E, $0D,
    $06, $66, $F7, $E1, $66, $03, $06, $04, $0C, $C3, $66, $D1, $E0, $66,
    $0F, $B7, $D8, $81, $E3, $FF, $01, $53, $66, $C1, $E8, $09, $66, $03,
    $06, $00, $0C, $66, $3B, $06, $CD, $07, $74, $0C, $66, $A3, $CD, $07,
    $BB, $00, $0A, $31, $D2, $E8, $08, $00, $5B, $66, $0F, $B7, $87, $00,
    $0A, $C3, $66, $A3, $C5, $07, $89, $1E, $C1, $07, $89, $16, $C3, $07,
    $BE, $BD, $07, $B4, $42, $8A, $16, $24, $06, $CD, $13, $73, $05, $BE,
    $AF, $07, $EB, $01, $C3, $AC, $08, $C0, $74, $09, $B4, $0E, $BB, $07,
    $00, $CD, $10, $EB, $F2, $F4, $EB, $FD, $49, $4F, $20, $20, $20, $20,
    $20, $20, $53, $59, $53, $49, $4F, $2E, $53, $59, $53, $20, $61, $62,
    $73, $65, $6E, $74, $00, $45, $72, $72, $65, $75, $72, $20, $64, $69,
    $73, $71, $75, $65, $00, $10, $00, $01, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { chargeur NTFS (SETUP/NTFSBOOT.ASM, octets 84 a 1555) }
  NtBootCode : Array[0..1471] Of Byte = (
    $FA, $31, $C0, $8E, $D0, $BC, $00, $7C, $8E, $D8, $FB, $FC, $B8, $00,
    $90, $8E, $C0, $BE, $00, $7C, $31, $FF, $B9, $00, $01, $F3, $A5, $8E,
    $D8, $88, $16, $24, $00, $66, $A1, $1C, $00, $66, $40, $66, $A3, $CD,
    $00, $C7, $06, $C7, $00, $0F, $00, $C7, $06, $C9, $00, $00, $02, $C7,
    $06, $CB, $00, $00, $90, $BE, $C5, $00, $B4, $42, $8A, $16, $24, $00,
    $CD, $13, $72, $05, $EA, $00, $02, $00, $90, $BE, $B7, $00, $AC, $08,
    $C0, $74, $09, $B4, $0E, $BB, $07, $00, $CD, $10, $EB, $F2, $F4, $EB,
    $FD, $45, $72, $72, $65, $75, $72, $20, $64, $69, $73, $71, $75, $65,
    $00, $10, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $55, $AA, $B8, $00, $90, $8E, $D8, $8E,
    $C0, $8E, $D0, $BC, $F0, $FF, $66, $0F, $B6, $06, $0D, $00, $66, $C1,
    $E0, $09, $66, $A3, $15, $06, $66, $0F, $BE, $06, $40, $00, $E8, $90,
    $01, $66, $A3, $19, $06, $66, $0F, $BE, $06, $44, $00, $E8, $83, $01,
    $66, $A3, $1D, $06, $66, $A1, $15, $06, $66, $39, $06, $1D, $06, $73,
    $06, $66, $B8, $00, $02, $00, $00, $66, $A3, $21, $06, $66, $A1, $30,
    $00, $66, $C7, $06, $00, $70, $00, $00, $00, $00, $66, $A3, $04, $70,
    $66, $C7, $06, $08, $70, $FF, $FF, $00, $00, $C7, $06, $29, $06, $01,
    $00, $66, $31, $C0, $E8, $4A, $02, $66, $B8, $80, $00, $00, $00, $E8,
    $5F, $02, $0F, $82, $31, $01, $BF, $00, $70, $E8, $7F, $02, $89, $0E,
    $29, $06, $66, $B8, $05, $00, $00, $00, $E8, $2A, $02, $C7, $06, $2B,
    $06, $00, $00, $66, $B8, $A0, $00, $00, $00, $E8, $39, $02, $72, $0A,
    $BF, $00, $80, $E8, $5B, $02, $89, $0E, $2B, $06, $C7, $06, $2F, $06,
    $00, $00, $C7, $06, $31, $06, $00, $00, $66, $B8, $90, $00, $00, $00,
    $E8, $18, $02, $0F, $82, $EA, $00, $89, $F3, $03, $5C, $14, $83, $C3,
    $10, $E8, $CB, $02, $73, $40, $8B, $1E, $2F, $06, $3B, $1E, $31, $06,
    $0F, $83, $D1, $00, $83, $06, $2F, $06, $04, $66, $8B, $87, $00, $90,
    $66, $F7, $26, $21, $06, $66, $8B, $0E, $1D, $06, $BF, $00, $30, $BE,
    $00, $80, $8B, $16, $2B, $06, $E8, $10, $01, $BE, $00, $30, $66, $8B,
    $0E, $1D, $06, $E8, $8D, $01, $BB, $18, $30, $E8, $8B, $02, $72, $C0,
    $E8, $A6, $01, $66, $B8, $80, $00, $00, $00, $E8, $BB, $01, $0F, $82,
    $8D, $00, $80, $7C, $08, $00, $0F, $84, $85, $00, $66, $8B, $44, $30,
    $66, $A3, $25, $06, $BF, $00, $80, $E8, $CB, $01, $89, $0E, $2B, $06,
    $C7, $06, $33, $06, $C0, $07, $66, $31, $DB, $66, $89, $D8, $66, $F7,
    $26, $15, $06, $66, $3B, $06, $25, $06, $73, $44, $66, $89, $D8, $BE,
    $00, $80, $8B, $16, $2B, $06, $E8, $82, $00, $72, $4C, $66, $0F, $B6,
    $0E, $0D, $00, $66, $F7, $E1, $66, $03, $06, $1C, $00, $66, $A3, $CD,
    $00, $89, $0E, $C7, $00, $C7, $06, $C9, $00, $00, $00, $A1, $33, $06,
    $A3, $CB, $00, $E8, $47, $00, $0F, $B6, $06, $0D, $00, $C1, $E0, $05,
    $01, $06, $33, $06, $66, $43, $EB, $AD, $31, $C0, $8E, $C0, $26, $66,
    $C7, $06, $10, $7C, $00, $00, $00, $00, $8A, $16, $24, $00, $EA, $00,
    $00, $C0, $07, $BE, $07, $06, $E9, $F3, $FC, $66, $09, $C0, $78, $06,
    $66, $F7, $26, $15, $06, $C3, $66, $F7, $D8, $88, $C1, $66, $B8, $01,
    $00, $00, $00, $66, $D3, $E0, $C3, $66, $60, $BE, $C5, $00, $B4, $42,
    $8A, $16, $24, $00, $CD, $13, $66, $61, $0F, $82, $C3, $FC, $C3, $56,
    $52, $09, $D2, $74, $22, $66, $3B, $04, $72, $17, $66, $8B, $0C, $66,
    $03, $4C, $08, $66, $39, $C8, $73, $0B, $66, $2B, $04, $66, $03, $44,
    $04, $5A, $5E, $F8, $C3, $83, $C6, $0C, $4A, $EB, $DA, $5A, $5E, $F9,
    $C3, $66, $A3, $35, $06, $66, $89, $0E, $39, $06, $89, $36, $3D, $06,
    $89, $16, $3F, $06, $89, $3E, $41, $06, $66, $83, $3E, $39, $06, $00,
    $74, $6A, $66, $A1, $35, $06, $66, $31, $D2, $66, $F7, $36, $15, $06,
    $66, $C1, $EA, $09, $66, $89, $16, $43, $06, $8B, $36, $3D, $06, $8B,
    $16, $3F, $06, $E8, $97, $FF, $0F, $82, $5F, $FF, $66, $0F, $B6, $0E,
    $0D, $00, $66, $F7, $E1, $66, $03, $06, $43, $06, $66, $03, $06, $1C,
    $00, $66, $A3, $CD, $00, $C7, $06, $C7, $00, $01, $00, $A1, $41, $06,
    $A3, $C9, $00, $C7, $06, $CB, $00, $00, $90, $E8, $53, $FF, $81, $06,
    $41, $06, $00, $02, $66, $81, $06, $35, $06, $00, $02, $00, $00, $66,
    $81, $2E, $39, $06, $00, $02, $00, $00, $77, $8E, $C3, $8B, $5C, $04,
    $01, $F3, $8B, $17, $89, $F7, $81, $C7, $FE, $01, $8B, $4C, $06, $49,
    $09, $C9, $74, $0E, $83, $C3, $02, $8B, $07, $89, $05, $81, $C7, $00,
    $02, $49, $EB, $EE, $C3, $66, $F7, $26, $19, $06, $66, $8B, $0E, $19,
    $06, $BF, $00, $20, $BE, $00, $70, $8B, $16, $29, $06, $E8, $3D, $FF,
    $BE, $00, $20, $E8, $BF, $FF, $C3, $BE, $00, $20, $03, $36, $14, $20,
    $66, $8B, $0C, $66, $83, $F9, $FF, $74, $18, $66, $39, $C1, $75, $0C,
    $80, $7C, $09, $00, $74, $0B, $80, $7C, $09, $04, $74, $05, $03, $74,
    $04, $EB, $E1, $F8, $C3, $F9, $C3, $56, $89, $F3, $03, $74, $20, $66,
    $31, $ED, $66, $31, $D2, $31, $C9, $8A, $04, $08, $C0, $74, $60, $46,
    $88, $C4, $24, $0F, $C0, $EC, $04, $50, $0F, $B6, $C8, $E8, $5D, $00,
    $66, $89, $2D, $66, $89, $45, $08, $66, $01, $C5, $58, $0F, $B6, $CC,
    $09, $C9, $74, $2A, $E8, $48, $00, $83, $F9, $04, $73, $19, $C0, $E1,
    $03, $66, $53, $66, $89, $C3, $B0, $20, $28, $C8, $88, $C1, $66, $D3,
    $E3, $66, $D3, $FB, $66, $89, $D8, $66, $5B, $66, $01, $C2, $66, $89,
    $55, $04, $EB, $08, $66, $C7, $45, $04, $FF, $FF, $FF, $FF, $83, $C7,
    $0C, $FF, $06, $2D, $06, $8B, $0E, $2D, $06, $EB, $9A, $8B, $0E, $2D,
    $06, $C7, $06, $2D, $06, $00, $00, $5E, $C3, $66, $31, $C0, $51, $01,
    $CE, $09, $C9, $74, $0A, $4E, $66, $C1, $E0, $08, $8A, $04, $49, $EB,
    $F2, $59, $01, $CE, $C3, $89, $DE, $03, $37, $F6, $44, $0C, $01, $74,
    $1D, $89, $F7, $03, $7C, $08, $66, $8B, $45, $F8, $8B, $3E, $31, $06,
    $81, $FF, $FC, $0F, $73, $0A, $66, $89, $85, $00, $90, $83, $06, $31,
    $06, $04, $F6, $44, $0C, $02, $75, $39, $80, $7C, $50, $06, $75, $2E,
    $56, $8D, $7C, $52, $BB, $01, $06, $B9, $06, $00, $8B, $05, $83, $F8,
    $61, $72, $08, $83, $F8, $7A, $77, $03, $83, $E8, $20, $3A, $07, $75,
    $10, $08, $E4, $75, $0C, $83, $C7, $02, $43, $E2, $E3, $5E, $66, $8B,
    $04, $F8, $C3, $5E, $03, $74, $08, $EB, $9E, $F9, $C3, $49, $4F, $2E,
    $53, $59, $53, $49, $4F, $2E, $53, $59, $53, $20, $61, $62, $73, $65,
    $6E, $74);
  { table $UpCase : plages (debut, nombre, decalage, pas) }
  UpRuns : Array[0..535] Of LongInt = (
    97, 26, -32, 1, 224, 23, -32, 1, 248, 7, -32, 1, 255, 1, 121, 1, 257, 24,
    -1, 2, 307, 3, -1, 2, 314, 8, -1, 2, 331, 23, -1, 2, 378, 3, -1, 2, 384,
    1, 195, 1, 387, 2, -1, 2, 392, 1, -1, 1, 396, 1, -1, 1, 402, 1, -1, 1,
    405, 1, 97, 1, 409, 1, -1, 1, 410, 1, 163, 1, 414, 1, 130, 1, 417, 3, -1,
    2, 424, 1, -1, 1, 429, 1, -1, 1, 432, 1, -1, 1, 436, 2, -1, 2, 441, 1,
    -1, 1, 445, 1, -1, 1, 447, 1, 56, 1, 454, 1, -2, 1, 457, 1, -2, 1, 460,
    1, -2, 1, 462, 8, -1, 2, 477, 1, -79, 1, 479, 9, -1, 2, 499, 1, -2, 1,
    501, 1, -1, 1, 505, 20, -1, 2, 547, 9, -1, 2, 572, 1, -1, 1, 578, 1, -1,
    1, 583, 5, -1, 2, 592, 1, 10783, 1, 593, 1, 10780, 1, 595, 1, -210, 1,
    596, 1, -206, 1, 598, 2, -205, 1, 601, 1, -202, 1, 603, 1, -203, 1, 608,
    1, -205, 1, 611, 1, -207, 1, 616, 1, -209, 1, 617, 1, -211, 1, 619, 1,
    10743, 1, 623, 1, -211, 1, 625, 1, 10749, 1, 626, 1, -213, 1, 629, 1,
    -214, 1, 637, 1, 10727, 1, 640, 1, -218, 1, 643, 1, -218, 1, 648, 1,
    -218, 1, 649, 1, -69, 1, 650, 2, -217, 1, 652, 1, -71, 1, 658, 1, -219,
    1, 881, 2, -1, 2, 887, 1, -1, 1, 891, 3, 130, 1, 940, 1, -38, 1, 941, 3,
    -37, 1, 945, 17, -32, 1, 963, 9, -32, 1, 972, 1, -64, 1, 973, 2, -63, 1,
    983, 1, -8, 1, 985, 12, -1, 2, 1010, 1, 7, 1, 1016, 1, -1, 1, 1019, 1,
    -1, 1, 1072, 32, -32, 1, 1104, 16, -80, 1, 1121, 17, -1, 2, 1163, 27, -1,
    2, 1218, 7, -1, 2, 1231, 1, -15, 1, 1233, 42, -1, 2, 1377, 38, -48, 1,
    7545, 1, 35332, 1, 7549, 1, 3814, 1, 7681, 75, -1, 2, 7841, 48, -1, 2,
    7936, 8, 8, 1, 7952, 6, 8, 1, 7968, 8, 8, 1, 7984, 8, 8, 1, 8000, 6, 8,
    1, 8017, 4, 8, 2, 8032, 8, 8, 1, 8048, 2, 74, 1, 8050, 4, 86, 1, 8054, 2,
    100, 1, 8056, 2, 128, 1, 8058, 2, 112, 1, 8060, 2, 126, 1, 8064, 8, 8, 1,
    8080, 8, 8, 1, 8096, 8, 8, 1, 8112, 2, 8, 1, 8115, 1, 9, 1, 8131, 1, 9,
    1, 8144, 2, 8, 1, 8160, 2, 8, 1, 8165, 1, 7, 1, 8179, 1, 9, 1, 8526, 1,
    -28, 1, 8560, 16, -16, 1, 8580, 1, -1, 1, 9424, 26, -26, 1, 11312, 47,
    -48, 1, 11361, 1, -1, 1, 11365, 1, -10795, 1, 11366, 1, -10792, 1, 11368,
    3, -1, 2, 11379, 1, -1, 1, 11382, 1, -1, 1, 11393, 50, -1, 2, 11520, 38,
    -7264, 1, 42561, 16, -1, 2, 42595, 6, -1, 2, 42625, 12, -1, 2, 42787, 7,
    -1, 2, 42803, 31, -1, 2, 42874, 2, -1, 2, 42879, 5, -1, 2, 42892, 1, -1,
    1, 65345, 26, -32, 1);
  { $Secure : descripteurs ($SDS) et index $SDH, $SII (comme mkntfs) }
  NtSds : Array[0..255] Of Byte = (
    $F0, $12, $03, $F8, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $7C, $00, $00, $00, $01, $00, $04, $80, $48, $00, $00, $00,
    $58, $00, $00, $00, $00, $00, $00, $00, $14, $00, $00, $00, $02, $00,
    $34, $00, $02, $00, $00, $00, $00, $00, $14, $00, $89, $00, $12, $00,
    $01, $01, $00, $00, $00, $00, $00, $05, $12, $00, $00, $00, $00, $00,
    $18, $00, $89, $00, $12, $00, $01, $02, $00, $00, $00, $00, $00, $05,
    $20, $00, $00, $00, $20, $02, $00, $00, $01, $02, $00, $00, $00, $00,
    $00, $05, $20, $00, $00, $00, $20, $02, $00, $00, $01, $02, $00, $00,
    $00, $00, $00, $05, $20, $00, $00, $00, $20, $02, $00, $00, $00, $00,
    $00, $00, $51, $24, $B3, $00, $01, $01, $00, $00, $80, $00, $00, $00,
    $00, $00, $00, $00, $7C, $00, $00, $00, $01, $00, $04, $80, $48, $00,
    $00, $00, $58, $00, $00, $00, $00, $00, $00, $00, $14, $00, $00, $00,
    $02, $00, $34, $00, $02, $00, $00, $00, $00, $00, $14, $00, $9F, $01,
    $12, $00, $01, $01, $00, $00, $00, $00, $00, $05, $12, $00, $00, $00,
    $00, $00, $18, $00, $9F, $01, $12, $00, $01, $02, $00, $00, $00, $00,
    $00, $05, $20, $00, $00, $00, $20, $02, $00, $00, $01, $02, $00, $00,
    $00, $00, $00, $05, $20, $00, $00, $00, $20, $02, $00, $00, $01, $02,
    $00, $00, $00, $00, $00, $05, $20, $00, $00, $00, $20, $02, $00, $00,
    $00, $00, $00, $00);
  NtSdh : Array[0..143] Of Byte = (
    $00, $00, $00, $00, $12, $00, $00, $00, $00, $10, $00, $00, $01, $00,
    $00, $00, $10, $00, $00, $00, $80, $00, $00, $00, $80, $00, $00, $00,
    $00, $00, $00, $00, $18, $00, $14, $00, $00, $00, $00, $00, $30, $00,
    $08, $00, $00, $00, $00, $00, $51, $24, $B3, $00, $01, $01, $00, $00,
    $51, $24, $B3, $00, $01, $01, $00, $00, $80, $00, $00, $00, $00, $00,
    $00, $00, $7C, $00, $00, $00, $49, $00, $49, $00, $18, $00, $14, $00,
    $00, $00, $00, $00, $30, $00, $08, $00, $00, $00, $00, $00, $F0, $12,
    $03, $F8, $00, $01, $00, $00, $F0, $12, $03, $F8, $00, $01, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $7C, $00, $00, $00, $49, $00,
    $49, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $00,
    $02, $00, $00, $00);
  NtSii : Array[0..127] Of Byte = (
    $00, $00, $00, $00, $10, $00, $00, $00, $00, $10, $00, $00, $01, $00,
    $00, $00, $10, $00, $00, $00, $70, $00, $00, $00, $70, $00, $00, $00,
    $00, $00, $00, $00, $14, $00, $14, $00, $00, $00, $00, $00, $28, $00,
    $04, $00, $00, $00, $00, $00, $00, $01, $00, $00, $F0, $12, $03, $F8,
    $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $7C, $00,
    $00, $00, $14, $00, $14, $00, $00, $00, $00, $00, $28, $00, $04, $00,
    $00, $00, $00, $00, $01, $01, $00, $00, $51, $24, $B3, $00, $01, $01,
    $00, $00, $80, $00, $00, $00, $00, $00, $00, $00, $7C, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $00, $02, $00,
    $00, $00);
  { $Quota ($O, $Q) et index vides ($ObjId:$O, $Reparse:$R) }
  NtQo : Array[0..87] Of Byte = (
    $00, $00, $00, $00, $11, $00, $00, $00, $00, $10, $00, $00, $01, $00,
    $00, $00, $10, $00, $00, $00, $48, $00, $00, $00, $48, $00, $00, $00,
    $00, $00, $00, $00, $20, $00, $04, $00, $00, $00, $00, $00, $28, $00,
    $10, $00, $00, $00, $00, $00, $01, $02, $00, $00, $00, $00, $00, $05,
    $20, $00, $00, $00, $20, $02, $00, $00, $00, $01, $00, $00, $20, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $00, $00, $00,
    $02, $00, $00, $00);
  NtQq : Array[0..207] Of Byte = (
    $00, $00, $00, $00, $10, $00, $00, $00, $00, $10, $00, $00, $01, $00,
    $00, $00, $10, $00, $00, $00, $C0, $00, $00, $00, $C0, $00, $00, $00,
    $00, $00, $00, $00, $14, $00, $30, $00, $00, $00, $00, $00, $48, $00,
    $04, $00, $00, $00, $00, $00, $01, $00, $00, $00, $02, $00, $00, $00,
    $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $6B,
    $6A, $AB, $7C, $73, $DD, $01, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
    $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $14, $00, $40, $00, $00, $00, $00, $00,
    $58, $00, $04, $00, $00, $00, $00, $00, $00, $01, $00, $00, $02, $00,
    $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $6B, $6A, $AB, $7C, $73, $DD, $01, $FF, $FF, $FF, $FF, $FF, $FF,
    $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00,
    $00, $00, $00, $00, $01, $02, $00, $00, $00, $00, $00, $05, $20, $00,
    $00, $00, $20, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
    $00, $00, $00, $00, $10, $00, $00, $00, $02, $00, $00, $00);
  NtEmptyIx : Array[0..47] Of Byte = (
    $00, $00, $00, $00, $13, $00, $00, $00, $00, $10, $00, $00, $01, $00,
    $00, $00, $10, $00, $00, $00, $20, $00, $00, $00, $20, $00, $00, $00,
    $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $00,
    $00, $00, $02, $00, $00, $00);
Type
  TLanguage = (_French, _English, _Germany, _Italian, _Spain);

  TCdFile = Record
    Name : String[12];
    Size, Lba : LongInt;
    Dir : Boolean;
    Yr, Mo, Dy, Hr, Mi : Byte;
  End;

  TEvent = Record
    Kind : Byte;
    Ch : Char;
    Sc : Byte;
    Shift, Ctrl, Alt : Boolean;
    X, Y : Integer;
    Btn : Byte;
  End;

  TDap = Record
    Size   : Byte;
    Res    : Byte;
    Count  : Word;
    BufOfs : Word;
    BufSg  : Word;
    LbaLo  : LongInt;
    LbaHi  : LongInt;
  End;

  { Entree de repertoire a ecrire (8.3) }
  TDirEnt = Record
    Name : String[11];
    Attr : Byte;
    Clus, Size : LongInt;
  End;

Var
  Language    : TLanguage;
  BootDrive   : Byte;
  FontSeg     : Word;
  FontOfs     : Word;
  GuiOn       : Boolean;
  { Decoupage }
  ClipX1, ClipY1, ClipX2, ClipY2 : Integer;
  AreaX1, AreaY1, AreaX2, AreaY2 : Integer;
  { Souris }
  MouseX, MouseY : Integer;
  MouseBtn    : Byte;
  MouseOk     : Boolean;
  MPhase      : Integer;
  MPack       : Array[0..2] Of Byte;
  CurShown    : Boolean;
  CurX, CurY  : Integer;
  CurSave     : Array[0..3, 0..18, 0..2] Of Byte;
  LastMX, LastMY : Integer;
  { Clavier }
  KExt, KShift, KCtrl, KAlt, KCaps : Boolean;
  KeyLo, KeyHi : String[60];
  { File d'evenements }
  EvQ         : Array[0..31] Of TEvent;
  EvHead, EvTail : Integer;
  { CD-ROM }
  Dap         : TDap;
  RootLba, RootSize : LongInt;
  VolLabel    : String[32];
  CdFiles     : Array[0..CdMax - 1] Of TCdFile;
  CdCount     : Integer;
  CdOk        : Boolean;
  { Assistant }
  Page        : Integer;
  PressBtn    : Integer;               { bouton enfonce (0..2), -1 }
  { Disques durs (BIOS 80h...) }
  DiskCnt     : Integer;
  DiskSel     : Integer;
  DiskSecs    : Array[0..3] Of LongInt;
  DiskHeads, DiskSpt : Array[0..3] Of Integer;
  DiskExt     : Array[0..3] Of Boolean;
  { Table des partitions du disque choisi }
  PType       : Array[0..3] Of Byte;
  PBoot       : Array[0..3] Of Byte;
  PStart, PSize : Array[0..3] Of LongInt;
  MbrOk       : Boolean;
  { Choix : 0 nouvelle partition, 1 formater la partition PExist }
  PartMode    : Integer;
  PExist      : Integer;
  PartMb, MaxMb : LongInt;
  TzSel, TzTop : Integer;
  TzDst       : Boolean;
  DispSel     : Integer;
  CompEx, CompSnd, CompDoc : Boolean;
  { Installation }
  Drv         : Byte;
  PartLba, PartSecs : LongInt;
  Spc         : Integer;
  FatSz, FatLba, DataLba, NextClus, TotClus : LongInt;
  EndClus     : Array[0..63] Of LongInt;
  EndCnt      : Integer;
  RootEnt, WinEnt : Array[0..23] Of TDirEnt;
  RootN, WinN : Integer;
  DosDate, DosTime : Word;
  DoneBytes, TotalBytes : LongInt;
  StatusText  : String;
  InstErr     : String;
  { Texte produit (MSDOS.SYS, AUTOEXEC.BAT, CONFIG.SYS) }
  GenLen      : Word;
  { Systeme de fichiers choisi (0 FAT16, 1 FAT32, 2 NTFS) ; FAT16 :
    racine fixe }
  FsKind      : Integer;
  Fat16       : Boolean;
  Root16Lba   : LongInt;
  { NTFS : mise en page (LCN), date, enregistrement en construction,
    entrees de repertoire, fichiers copies }
  NtC, NtNext, NtMftL, NtMBmpL, NtLogL, NtLogN, NtAdL, NtUpL, NtSdsL,
  NtSdsN, NtBmpL, NtBmpN, NtBmpLen, NtRootIx, NtWinIx, NtMirr : LongInt;
  NtFT        : Array[0..3] Of Word;
  RBase, RPos, RId : Word;
  KN          : Integer;
  KRec, KSeq, KPar, KPSeq, KAll, KSiz, KFl : Array[0..39] Of LongInt;
  KNm         : Array[0..39] Of String[12];
  NfN         : Integer;
  NfName      : Array[0..31] Of String[12];
  NfRoot      : Array[0..31] Of Boolean;
  NfRec, NfLcn, NfClus, NfSize, NfFl : Array[0..31] Of LongInt;

{ ================================================================== }
{ Utilitaires (repris d'IO.SYS)                                      }
{ ================================================================== }

Procedure InitKeyTables;
Begin
  KeyLo := #0#27'1234567890-='#8#9'qwertyuiop[]'#13#0 +
           'asdfghjkl;''`'#0'\zxcvbnm,./'#0'*'#0' ';
  KeyHi := #0#27'!@#$%^&*()_+'#8#9'QWERTYUIOP{}'#13#0 +
           'ASDFGHJKL:"~'#0'|ZXCVBNM<>?'#0'*'#0' ';
End;

Function IntToStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IntToStr := S;
End;

Function HexByte(B : Byte) : String;
Const HX : String[16] = '0123456789ABCDEF';
Begin
  HexByte := HX[(B Shr 4) + 1] + HX[(B And 15) + 1];
End;

Function Pad2(V : Integer) : String;
Var S : String;
Begin
  Str(V, S);
  If Length(S) < 2 Then S := '0' + S;
  Pad2 := S;
End;

Function UpStr(S : String) : String;
Var I : Integer;
Begin
  For I := 1 To Length(S) Do
    If (S[I] >= 'a') And (S[I] <= 'z') Then S[I] := Chr(Ord(S[I]) - 32);
  UpStr := S;
End;

Function Trim(S : String) : String;
Begin
  While (Length(S) > 0) And ((S[1] = ' ') Or (S[1] = #9)) Do
    Delete(S, 1, 1);
  While (Length(S) > 0) And ((S[Length(S)] = ' ') Or
        (S[Length(S)] = #9)) Do
    Delete(S, Length(S), 1);
  Trim := S;
End;

Function Min(A, B : Integer) : Integer;
Begin
  If A < B Then Min := A Else Min := B;
End;

Function Max(A, B : Integer) : Integer;
Begin
  If A > B Then Max := A Else Max := B;
End;

Function InRect(PX, PY, X1, Y1, X2, Y2 : Integer) : Boolean;
Begin
  InRect := (PX >= X1) And (PX <= X2) And (PY >= Y1) And (PY <= Y2);
End;

{ Compteur de l'horloge du BIOS (18,2 tops par seconde) }
Function Ticks : Word;
Begin
  Ticks := MemW[$0040:$006C];
End;

Procedure WaitTicks(N : Word);
Var T : Word;
Begin
  T := Ticks;
  While Word(Ticks - T) < N Do;
End;

{ ================================================================== }
{ Langue                                                             }
{ ================================================================== }

{ Choisir le texte selon la langue : francais, anglais, allemand,
  italien, espagnol }
Function L(Const F, E, G, I, S : String) : String;
Begin
  Case Language Of
    _English : L := E;
    _Germany : L := G;
    _Italian : L := I;
    _Spain   : L := S;
  Else
    L := F;
  End;
End;

Function LangCode : String;
Begin
  LangCode := L('FR', 'EN', 'GR', 'IT', 'SP');
End;

{ Separateur des milliers selon la langue }
Function FmtNum(V : LongInt) : String;
Var S, R : String; N : Integer; Sep : Char;
Begin
  Str(V, S);
  Case Language Of
    _English : Sep := ',';
    _French  : Sep := ' ';
  Else
    Sep := '.';
  End;
  R := ''; N := 0;
  While Length(S) > 0 Do
  Begin
    If (N > 0) And (N Mod 3 = 0) And (S[Length(S)] <> '-') Then
      R := Sep + R;
    R := S[Length(S)] + R;
    Delete(S, Length(S), 1);
    Inc(N);
  End;
  FmtNum := R;
End;

Function Bcd(B : Byte) : Integer;
Begin
  Bcd := (B Shr 4) * 10 + (B And 15);
End;

Procedure RtcTime(Var H, M, S : Integer);
Var VHr, VMn, VSc : Byte;
Begin
  asm
    mov ah,02h
    int 1Ah
    mov VHr,ch
    mov VMn,cl
    mov VSc,dh
  end;
  H := Bcd(VHr); M := Bcd(VMn); S := Bcd(VSc);
End;

Procedure RtcDate(Var Y, M, D : Integer);
Var VCe, VYr, VMo, VDy : Byte;
Begin
  asm
    mov ah,04h
    int 1Ah
    mov VCe,ch
    mov VYr,cl
    mov VMo,dh
    mov VDy,dl
  end;
  Y := Bcd(VCe) * 100 + Bcd(VYr);
  M := Bcd(VMo); D := Bcd(VDy);
  If Y < 1980 Then Y := 2026;
  If (M < 1) Or (M > 12) Then M := 1;
  If (D < 1) Or (D > 31) Then D := 1;
End;

{ ================================================================== }
{ CD-ROM ISO 9660 (INT 13h etendue)                                  }
{ ================================================================== }

Function CdRead(Lba : LongInt; BSeg : Word) : Boolean;
Var Drv, Err, Tries : Byte;
Begin
  Tries := 0;
  Repeat
    Dap.Size := 16; Dap.Res := 0; Dap.Count := 1;
    Dap.BufOfs := 0; Dap.BufSg := BSeg;
    Dap.LbaLo := Lba; Dap.LbaHi := 0;
    Drv := BootDrive;
    asm
      push si
      mov ah,42h
      mov dl,Drv
      lea si,Dap
      int 13h
      mov al,0
      adc al,0
      mov Err,al
      pop si
    end;
    If Err = 0 Then
    Begin
      CdRead := True;
      Exit;
    End;
    asm
      xor ah,ah
      mov dl,Drv
      int 13h
    end;
    Inc(Tries);
  Until Tries >= 3;
  CdRead := False;
End;

Function GetD(Seg, Ofs : Word) : LongInt;
Begin
  GetD := LongInt(MemW[Seg:Ofs]) + LongInt(MemW[Seg:Ofs + 2]) * 65536;
End;

{ Lire le descripteur de volume et le repertoire racine }
Procedure CdScan;
Var Sector, NSect : LongInt; Ofs, RecLen, NLen, K : Word;
    Name : String; C : Char;
Begin
  CdOk := False; CdCount := 0; VolLabel := '';
  If Not CdRead(16, CdSeg) Then Exit;
  If (Mem[CdSeg:0] <> 1) Or (Mem[CdSeg:1] <> Ord('C')) Then Exit;
  RootLba := GetD(CdSeg, 156 + 2);
  RootSize := GetD(CdSeg, 156 + 10);
  For K := 0 To 31 Do VolLabel := VolLabel + Chr(Mem[CdSeg:40 + K]);
  VolLabel := Trim(VolLabel);
  CdOk := True;
  NSect := (RootSize + 2047) Div 2048;
  Sector := 0;
  While (Sector < NSect) And (CdCount < CdMax) Do
  Begin
    If Not CdRead(RootLba + Sector, CdSeg) Then Exit;
    Ofs := 0;
    While Ofs < 2048 Do
    Begin
      RecLen := Mem[CdSeg:Ofs];
      If RecLen = 0 Then Ofs := 2048
      Else
      Begin
        NLen := Mem[CdSeg:Ofs + 32];
        If (NLen > 1) Or (Mem[CdSeg:Ofs + 33] > 1) Then
        Begin
          Name := '';
          K := 0;
          While K < NLen Do
          Begin
            C := Chr(Mem[CdSeg:Ofs + 33 + K]);
            If C = ';' Then K := NLen
            Else Name := Name + UpCase(C);
            Inc(K);
          End;
          If (Length(Name) > 0) And (Name[Length(Name)] = '.') Then
            Delete(Name, Length(Name), 1);
          If CdCount < CdMax Then
          Begin
            CdFiles[CdCount].Name := Copy(Name, 1, 12);
            CdFiles[CdCount].Lba := GetD(CdSeg, Ofs + 2);
            CdFiles[CdCount].Size := GetD(CdSeg, Ofs + 10);
            CdFiles[CdCount].Yr := Mem[CdSeg:Ofs + 18];
            CdFiles[CdCount].Mo := Mem[CdSeg:Ofs + 19];
            CdFiles[CdCount].Dy := Mem[CdSeg:Ofs + 20];
            CdFiles[CdCount].Hr := Mem[CdSeg:Ofs + 21];
            CdFiles[CdCount].Mi := Mem[CdSeg:Ofs + 22];
            CdFiles[CdCount].Dir := (Mem[CdSeg:Ofs + 25] And 2) <> 0;
            Inc(CdCount);
          End;
        End;
        Ofs := Ofs + RecLen;
      End;
    End;
    Inc(Sector);
  End;
End;

Function CdFind(Name : String) : Integer;
Var I : Integer;
Begin
  CdFind := -1;
  Name := UpStr(Name);
  For I := 0 To CdCount - 1 Do
    If CdFiles[I].Name = Name Then
    Begin
      CdFind := I;
      Exit;
    End;
End;

Function CmosRead(R : Byte) : Byte;
Begin
  Port[$70] := R;
  CmosRead := Port[$71];
End;

Procedure CmosWrite(R, V : Byte);
Begin
  Port[$70] := R;
  Port[$71] := V;
End;

Procedure Reboot;
Begin
  WaitTicks(2);
  Port[$64] := $FE;
  WaitTicks(9);
  asm
    int 19h
  end;
End;

{ ================================================================== }
{ Graphisme VGA 640x480 16 couleurs (repris d'IO.SYS)                }
{ ================================================================== }

Procedure GcSet(Idx, Val : Byte);
Begin
  Port[$3CE] := Idx;
  Port[$3CF] := Val;
End;

Procedure SeqSet(Idx, Val : Byte);
Begin
  Port[$3C4] := Idx;
  Port[$3C5] := Val;
End;

{ Etat normal des registres : mode d'ecriture 2, remplacement }
Procedure VgaNormal;
Begin
  GcSet(1, 0);
  GcSet(3, 0);
  GcSet(5, 2);
  GcSet(8, $FF);
  SeqSet(2, $0F);
End;

Procedure SetPalette;
Var I : Integer; R, G, B : Byte; Idx : Byte;
Begin
  For I := 0 To 15 Do
  Begin
    Idx := I;
    asm
      mov ax,1000h
      mov bl,Idx
      mov bh,Idx
      int 10h
    end;
    R := PalR[I]; G := PalG[I]; B := PalB[I];
    asm
      mov ax,1010h
      mov bl,Idx
      xor bh,bh
      mov dh,R
      mov ch,G
      mov cl,B
      int 10h
    end;
  End;
End;

Procedure GraphMode;
Var FSg, FOf : Word;
Begin
  asm
    mov ax,0012h
    int 10h
    push bp
    push es
    mov ax,1130h
    mov bh,6
    int 10h
    mov ax,es
    mov dx,bp
    pop es
    pop bp
    mov FSg,ax
    mov FOf,dx
  end;
  FontSeg := FSg; FontOfs := FOf;
  SetPalette;
  VgaNormal;
  GuiOn := True;
End;

Procedure TextMode;
Begin
  asm
    mov ax,0003h
    int 10h
  end;
  GuiOn := False;
End;

Procedure FullClip;
Begin
  ClipX1 := 0; ClipY1 := 0; ClipX2 := ScrW - 1; ClipY2 := ScrH - 1;
End;

{ Decoupage = zone a redessiner inter (X1,Y1)-(X2,Y2) }
Procedure SetClip(X1, Y1, X2, Y2 : Integer);
Begin
  ClipX1 := Max(X1, AreaX1); ClipY1 := Max(Y1, AreaY1);
  ClipX2 := Min(X2, AreaX2); ClipY2 := Min(Y2, AreaY2);
End;

Procedure SetArea(X1, Y1, X2, Y2 : Integer);
Begin
  AreaX1 := Max(X1, 0); AreaY1 := Max(Y1, 0);
  AreaX2 := Min(X2, ScrW - 1); AreaY2 := Min(Y2, ScrH - 1);
  ClipX1 := AreaX1; ClipY1 := AreaY1;
  ClipX2 := AreaX2; ClipY2 := AreaY2;
End;

Function ClipEmpty : Boolean;
Begin
  ClipEmpty := (ClipX1 > ClipX2) Or (ClipY1 > ClipY2);
End;

{ Rectangle plein, decoupe }
Procedure Bar(X1, Y1, X2, Y2 : Integer; C : Byte);
Var L, R, Y, N : Integer; O : Word; LM, RM, D : Byte;
Begin
  If X1 < ClipX1 Then X1 := ClipX1;
  If Y1 < ClipY1 Then Y1 := ClipY1;
  If X2 > ClipX2 Then X2 := ClipX2;
  If Y2 > ClipY2 Then Y2 := ClipY2;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  L := X1 Shr 3; R := X2 Shr 3;
  LM := $FF Shr (X1 And 7);
  RM := Byte($FF Shl (7 - (X2 And 7)));
  If L = R Then
  Begin
    GcSet(8, LM And RM);
    O := Word(Y1) * 80 + Word(L);
    For Y := Y1 To Y2 Do
    Begin
      D := Mem[VSeg:O]; Mem[VSeg:O] := C;
      O := O + 80;
    End;
    GcSet(8, $FF);
    Exit;
  End;
  GcSet(8, LM);
  O := Word(Y1) * 80 + Word(L);
  For Y := Y1 To Y2 Do
  Begin
    D := Mem[VSeg:O]; Mem[VSeg:O] := C;
    O := O + 80;
  End;
  GcSet(8, RM);
  O := Word(Y1) * 80 + Word(R);
  For Y := Y1 To Y2 Do
  Begin
    D := Mem[VSeg:O]; Mem[VSeg:O] := C;
    O := O + 80;
  End;
  GcSet(8, $FF);
  N := R - L - 1;
  If N > 0 Then
  Begin
    O := Word(Y1) * 80 + Word(L + 1);
    For Y := Y1 To Y2 Do
    Begin
      asm
        push es
        push di
        mov ax,0A000h
        mov es,ax
        mov di,O
        mov cx,N
        mov al,C
        cld
        rep stosb
        pop di
        pop es
      end;
      O := O + 80;
    End;
  End;
End;

Procedure HLine(X1, X2, Y : Integer; C : Byte);
Begin
  Bar(X1, Y, X2, Y, C);
End;

Procedure VLine(X, Y1, Y2 : Integer; C : Byte);
Begin
  Bar(X, Y1, X, Y2, C);
End;

Procedure Pix(X, Y : Integer; C : Byte);
Var O : Word; D : Byte;
Begin
  If (X < ClipX1) Or (X > ClipX2) Or (Y < ClipY1) Or (Y > ClipY2) Then
    Exit;
  O := Word(Y) * 80 + Word(X) Shr 3;
  GcSet(8, $80 Shr (X And 7));
  D := Mem[VSeg:O]; Mem[VSeg:O] := C;
End;

Procedure Box(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  HLine(X1, X2, Y1, C); HLine(X1, X2, Y2, C);
  VLine(X1, Y1, Y2, C); VLine(X2, Y1, Y2, C);
End;

Procedure Line(X1, Y1, X2, Y2 : Integer; C : Byte);
Var DX, DY, SX, SY, E, E2 : Integer;
Begin
  If Y1 = Y2 Then
  Begin
    If X1 <= X2 Then HLine(X1, X2, Y1, C) Else HLine(X2, X1, Y1, C);
    Exit;
  End;
  If X1 = X2 Then
  Begin
    If Y1 <= Y2 Then VLine(X1, Y1, Y2, C) Else VLine(X1, Y2, Y1, C);
    Exit;
  End;
  DX := Abs(X2 - X1); DY := -Abs(Y2 - Y1);
  If X1 < X2 Then SX := 1 Else SX := -1;
  If Y1 < Y2 Then SY := 1 Else SY := -1;
  E := DX + DY;
  While True Do
  Begin
    Pix(X1, Y1, C);
    If (X1 = X2) And (Y1 = Y2) Then Exit;
    E2 := 2 * E;
    If E2 >= DY Then Begin E := E + DY; X1 := X1 + SX End;
    If E2 <= DX Then Begin E := E + DX; Y1 := Y1 + SY End;
  End;
End;

Function ISqrt(V : LongInt) : Integer;
Var R : LongInt;
Begin
  R := 0;
  While (R + 1) * (R + 1) <= V Do Inc(R);
  ISqrt := R;
End;

Procedure Disc(CX, CY, R : Integer; C : Byte);
Var DY, DX : Integer;
Begin
  For DY := -R To R Do
  Begin
    DX := ISqrt(LongInt(R) * R - LongInt(DY) * DY);
    HLine(CX - DX, CX + DX, CY + DY, C);
  End;
End;

Procedure Circle(CX, CY, R : Integer; C : Byte);
Var DY, DX, PX : Integer;
Begin
  PX := R;
  For DY := 0 To R Do
  Begin
    DX := ISqrt(LongInt(R) * R - LongInt(DY) * DY);
    HLine(CX + DX, CX + PX, CY + DY, C);
    HLine(CX - PX, CX - DX, CY + DY, C);
    HLine(CX + DX, CX + PX, CY - DY, C);
    HLine(CX - PX, CX - DX, CY - DY, C);
    PX := DX;
    If PX < 1 Then PX := 1;
  End;
End;

{ Tramage : couleur C sur un point sur deux (Phase 0 ou 1) }
Procedure Dither(X1, Y1, X2, Y2 : Integer; C : Byte; Phase : Integer);
Var Y, X : Integer; O : Word; D, M : Byte;
Begin
  If X1 < ClipX1 Then X1 := ClipX1;
  If Y1 < ClipY1 Then Y1 := ClipY1;
  If X2 > ClipX2 Then X2 := ClipX2;
  If Y2 > ClipY2 Then Y2 := ClipY2;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  For Y := Y1 To Y2 Do
  Begin
    If Odd(Y + Phase) Then M := $AA Else M := $55;
    X := X1;
    While X <= X2 Do
    Begin
      D := $FF Shr (X And 7);
      If (X Or 7) > X2 Then D := D And Byte($FF Shl (7 - (X2 And 7)));
      GcSet(8, D And M);
      O := Word(Y) * 80 + Word(X) Shr 3;
      D := Mem[VSeg:O]; Mem[VSeg:O] := C;
      X := (X Or 7) + 1;
    End;
  End;
  GcSet(8, $FF);
End;

{ Ligne en OU exclusif (contour de deplacement des fenetres) }
Procedure XorBar(X1, Y1, X2, Y2 : Integer);
Var Y, X : Integer; O : Word; D : Byte;
Begin
  If X1 < 0 Then X1 := 0;
  If Y1 < 0 Then Y1 := 0;
  If X2 > ScrW - 1 Then X2 := ScrW - 1;
  If Y2 > ScrH - 1 Then Y2 := ScrH - 1;
  If (X1 > X2) Or (Y1 > Y2) Then Exit;
  GcSet(3, $18);
  For Y := Y1 To Y2 Do
  Begin
    X := X1;
    While X <= X2 Do
    Begin
      D := $FF Shr (X And 7);
      If (X Or 7) > X2 Then D := D And Byte($FF Shl (7 - (X2 And 7)));
      GcSet(8, D);
      O := Word(Y) * 80 + Word(X) Shr 3;
      D := Mem[VSeg:O]; Mem[VSeg:O] := 15;
      X := (X Or 7) + 1;
    End;
  End;
  GcSet(3, 0);
  GcSet(8, $FF);
End;

Procedure XorFrame(X1, Y1, X2, Y2 : Integer);
Begin
  XorBar(X1, Y1, X2, Y1 + 2);
  XorBar(X1, Y2 - 2, X2, Y2);
  XorBar(X1, Y1 + 3, X1 + 2, Y2 - 3);
  XorBar(X2 - 2, Y1 + 3, X2, Y2 - 3);
End;

{ ------------------------------------------------------------------ }
{ Texte (police 8x16 du BIOS video)                                  }
{ ------------------------------------------------------------------ }

Procedure DrawChar(X, Y : Integer; Ch : Char; C : Byte);
Var R, Sh, CX : Integer; O, F : Word; B, M, D : Byte;
Begin
  If (X > ClipX2) Or (X + 7 < ClipX1) Or (Y > ClipY2) Or
     (Y + 15 < ClipY1) Then Exit;
  F := FontOfs + Word(Ord(Ch)) * 16;
  If (X >= ClipX1) And (X + 7 <= ClipX2) And (Y >= ClipY1) And
     (Y + 15 <= ClipY2) Then
  Begin
    O := Word(Y) * 80 + Word(X) Shr 3; Sh := X And 7;
    For R := 0 To 15 Do
    Begin
      B := Mem[FontSeg:F + R];
      If B <> 0 Then
      Begin
        M := B Shr Sh;
        If M <> 0 Then
        Begin
          GcSet(8, M); D := Mem[VSeg:O]; Mem[VSeg:O] := C;
        End;
        If Sh <> 0 Then
        Begin
          M := Byte(B Shl (8 - Sh));
          If M <> 0 Then
          Begin
            GcSet(8, M); D := Mem[VSeg:O + 1]; Mem[VSeg:O + 1] := C;
          End;
        End;
      End;
      O := O + 80;
    End;
    GcSet(8, $FF);
    Exit;
  End;
  For R := 0 To 15 Do
  Begin
    B := Mem[FontSeg:F + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then Pix(X + CX, Y + R, C);
  End;
  GcSet(8, $FF);
End;

Procedure OutText(X, Y : Integer; Const S : String; C : Byte);
Var K : Integer;
Begin
  For K := 1 To Length(S) Do
  Begin
    If S[K] <> ' ' Then DrawChar(X, Y, S[K], C);
    X := X + 8;
  End;
End;

Procedure OutBold(X, Y : Integer; Const S : String; C : Byte);
Begin
  OutText(X, Y, S, C);
  OutText(X + 1, Y, S, C);
End;

Function TextW(Const S : String) : Integer;
Begin
  TextW := Length(S) * 8;
End;

{ Texte centre entre X1 et X2 }
Procedure OutCenter(X1, X2, Y : Integer; Const S : String; C : Byte);
Begin
  OutText(X1 + (X2 - X1 + 1 - TextW(S)) Div 2, Y, S, C);
End;

{ Texte tronque a MaxW pixels (avec ...) }
Function Fit(Const S : String; MaxW : Integer) : String;
Var N : Integer;
Begin
  N := MaxW Div 8;
  If N < 0 Then N := 0;
  If Length(S) <= N Then Fit := S
  Else If N > 3 Then Fit := Copy(S, 1, N - 3) + '...'
  Else Fit := Copy(S, 1, N);
End;

{ Caractere agrandi (Scale x Scale par point) }
Procedure BigChar(X, Y : Integer; Ch : Char; C : Byte; Sc : Integer);
Var R, CX : Integer; B : Byte;
Begin
  For R := 0 To 15 Do
  Begin
    B := Mem[FontSeg:FontOfs + Word(Ord(Ch)) * 16 + R];
    For CX := 0 To 7 Do
      If (B And ($80 Shr CX)) <> 0 Then
        Bar(X + CX * Sc, Y + R * Sc, X + CX * Sc + Sc - 1,
            Y + R * Sc + Sc - 1, C);
  End;
End;

Procedure BigText(X, Y : Integer; Const S : String; C : Byte;
                  Sc : Integer);
Var K : Integer;
Begin
  For K := 1 To Length(S) Do
    BigChar(X + (K - 1) * 8 * Sc, Y, S[K], C, Sc);
End;

{ Texte avec retour a la ligne automatique ; retourne le nombre de
  lignes. Draw = False : seulement compter }
Function WrapText(X, Y, W : Integer; Const S : String; C : Byte;
                  Draw : Boolean) : Integer;
Var Cols, I, N, Last : Integer; Line, Word0 : String;
Begin
  Cols := W Div 8;
  N := 0; Line := ''; Word0 := '';
  I := 1;
  While I <= Length(S) + 1 Do
  Begin
    If (I > Length(S)) Or (S[I] = ' ') Or (S[I] = '|') Then
    Begin
      If Length(Line) + Length(Word0) + 1 > Cols Then
      Begin
        If Line <> '' Then
        Begin
          If Draw Then OutText(X, Y + N * 16, Line, C);
          Inc(N);
        End;
        Line := Word0;
      End
      Else If Line = '' Then Line := Word0
      Else Line := Line + ' ' + Word0;
      Word0 := '';
      If (I <= Length(S)) And (S[I] = '|') Then
      Begin
        If Draw Then OutText(X, Y + N * 16, Line, C);
        Inc(N);
        Line := '';
      End;
    End
    Else
      Word0 := Word0 + S[I];
    Inc(I);
  End;
  If Line <> '' Then
  Begin
    If Draw Then OutText(X, Y + N * 16, Line, C);
    Inc(N);
  End;
  Last := N;
  WrapText := Last;
End;

{ ------------------------------------------------------------------ }
{ Reliefs de Windows 95                                              }
{ ------------------------------------------------------------------ }

Procedure Edge(X1, Y1, X2, Y2 : Integer; TL, BR : Byte);
Begin
  HLine(X1, X2 - 1, Y1, TL);
  VLine(X1, Y1, Y2 - 1, TL);
  HLine(X1, X2, Y2, BR);
  VLine(X2, Y1, Y2, BR);
End;

{ Bouton en relief (ou enfonce) }
Procedure Raised(X1, Y1, X2, Y2 : Integer; Pressed : Boolean);
Begin
  Bar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, cSilver);
  If Pressed Then
  Begin
    Edge(X1, Y1, X2, Y2, cBlack, cWhite);
    Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cGray, cSilver);
  End
  Else
  Begin
    Edge(X1, Y1, X2, Y2, cWhite, cBlack);
    Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cSilver, cGray);
  End;
End;

{ Champ en creux (zone de saisie, liste) }
Procedure Sunken(X1, Y1, X2, Y2 : Integer; Fill : Byte);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cBlack, cSilver);
  Bar(X1 + 2, Y1 + 2, X2 - 2, Y2 - 2, Fill);
End;

{ Cadre grave (groupe d'options) }
Procedure GroupBox(X1, Y1, X2, Y2 : Integer; Const Title : String);
Begin
  Edge(X1, Y1, X2, Y2, cGray, cWhite);
  Edge(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, cWhite, cGray);
  If Title <> '' Then
  Begin
    Bar(X1 + 6, Y1 - 7, X1 + 9 + TextW(Title), Y1 + 8, cSilver);
    OutText(X1 + 8, Y1 - 7, Title, cBlack);
  End;
End;

Procedure PushButton(X1, Y1, X2, Y2 : Integer; Const S : String;
                     Pressed, Def : Boolean);
Var D : Integer;
Begin
  If Def Then
  Begin
    Box(X1, Y1, X2, Y2, cBlack);
    Raised(X1 + 1, Y1 + 1, X2 - 1, Y2 - 1, Pressed);
  End
  Else
    Raised(X1, Y1, X2, Y2, Pressed);
  If Pressed Then D := 1 Else D := 0;
  OutCenter(X1 + D, X2 + D, (Y1 + Y2 - 15) Div 2 + D, S, cBlack);
End;

Procedure RadioButton(X, Y : Integer; Const S : String; On : Boolean);
Begin
  Circle(X + 6, Y + 7, 6, cGray);
  Disc(X + 6, Y + 7, 4, cWhite);
  HLine(X + 3, X + 9, Y + 13, cWhite);
  VLine(X + 12, Y + 4, Y + 10, cWhite);
  If On Then Disc(X + 6, Y + 7, 2, cBlack);
  OutText(X + 18, Y, S, cBlack);
End;

{ Petit triangle (fleche) : Dir 0 droite, 1 bas, 2 haut }
Procedure Arrow(X, Y, Dir : Integer; C : Byte);
Var I : Integer;
Begin
  For I := 0 To 3 Do
    Case Dir Of
      0 : VLine(X + I, Y + I, Y + 6 - I, C);
      1 : HLine(X + I, X + 6 - I, Y + I, C);
    Else
      HLine(X + 3 - I, X + 3 + I, Y + I, C);
    End;
End;

Procedure HideCursor;
Var P, R, B, BX : Integer; O : Word;
Begin
  If Not CurShown Then Exit;
  CurShown := False;
  GcSet(5, 0); GcSet(8, $FF);
  BX := CurX Shr 3;
  For P := 0 To 3 Do
  Begin
    SeqSet(2, 1 Shl P);
    For R := 0 To CurH - 1 Do
      If CurY + R < ScrH Then
      Begin
        O := Word(CurY + R) * 80 + Word(BX);
        For B := 0 To 2 Do
          If BX + B < 80 Then Mem[VSeg:O + B] := CurSave[P, R, B];
      End;
  End;
  VgaNormal;
End;

Procedure ShowCursor;
Var P, R, B, BX, I : Integer; O : Word;
    SX1, SY1, SX2, SY2 : Integer; Ch : Char;
Begin
  If CurShown Or Not GuiOn Then Exit;
  CurX := MouseX; CurY := MouseY;
  BX := CurX Shr 3;
  For P := 0 To 3 Do
  Begin
    GcSet(4, P);
    For R := 0 To CurH - 1 Do
      If CurY + R < ScrH Then
      Begin
        O := Word(CurY + R) * 80 + Word(BX);
        For B := 0 To 2 Do
          If BX + B < 80 Then CurSave[P, R, B] := Mem[VSeg:O + B];
      End;
  End;
  SX1 := ClipX1; SY1 := ClipY1; SX2 := ClipX2; SY2 := ClipY2;
  FullClip;
  For R := 0 To CurH - 1 Do
    For I := 1 To 12 Do
    Begin
      Ch := CurShape[R][I];
      If Ch = 'X' Then Pix(CurX + I - 1, CurY + R, cBlack)
      Else If Ch = 'W' Then Pix(CurX + I - 1, CurY + R, cWhite);
    End;
  GcSet(8, $FF);
  ClipX1 := SX1; ClipY1 := SY1; ClipX2 := SX2; ClipY2 := SY2;
  CurShown := True;
End;

{ ------------------------------------------------------------------ }
{ Icones (dessinees dans une grille de 32x32, mises a l'echelle S)   }
{ ------------------------------------------------------------------ }

Var
  IcX, IcY, IcS : Integer;

Function IcP(V : Integer) : Integer;
Begin
  IcP := V * IcS Div 32;
End;

Procedure QR(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  Bar(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2 + 1) - 1,
      IcY + IcP(Y2 + 1) - 1, C);
End;

Procedure QB(X1, Y1, X2, Y2 : Integer; C : Byte);
Var A, B, CC, D : Integer;
Begin
  A := IcX + IcP(X1); B := IcY + IcP(Y1);
  CC := IcX + IcP(X2 + 1) - 1; D := IcY + IcP(Y2 + 1) - 1;
  Box(A, B, CC, D, C);
End;

Procedure QL(X1, Y1, X2, Y2 : Integer; C : Byte);
Begin
  Line(IcX + IcP(X1), IcY + IcP(Y1), IcX + IcP(X2), IcY + IcP(Y2), C);
End;

Procedure QD(CX, CY, R : Integer; C : Byte);
Begin
  Disc(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

Procedure QC(CX, CY, R : Integer; C : Byte);
Begin
  Circle(IcX + IcP(CX), IcY + IcP(CY), IcP(R), C);
End;

{ Boite en relief (fond F, contour noir) }
Procedure IFrame(X1, Y1, X2, Y2 : Integer; F : Byte);
Begin
  QR(X1, Y1, X2, Y2, F);
  QB(X1, Y1, X2, Y2, cBlack);
End;

Procedure IconMonitor(Screen : Byte);
Begin
  IFrame(4, 2, 27, 21, cSilver);
  QR(5, 3, 26, 3, cWhite);
  IFrame(7, 5, 24, 17, Screen);
  IFrame(11, 22, 20, 24, cSilver);
End;

Procedure IconFolder(C : Byte);
Begin
  IFrame(3, 6, 13, 10, C);
  IFrame(3, 9, 28, 27, C);
  QR(4, 10, 27, 10, cWhite);
End;

Procedure IconPage;
Begin
  IFrame(6, 2, 25, 29, cWhite);
  QR(20, 2, 25, 7, cSilver);
  QL(20, 2, 25, 7, cBlack);
End;

Procedure DrawIcon(Id, X, Y, S : Integer);
Var I : Integer;
Begin
  IcX := X; IcY := Y; IcS := S;
  Case Id Of
    icComputer, icSystem :
    Begin
      IconMonitor(cTeal);
      IFrame(2, 25, 29, 29, cSilver);
      QR(5, 27, 26, 27, cGray);
      If Id = icSystem Then
      Begin
        QR(14, 7, 17, 8, cWhite);
        QR(14, 10, 17, 15, cWhite);
      End;
    End;
    icDisplay :
    Begin
      IconMonitor(cBlue);
      QR(8, 12, 23, 16, cGreen);
      QD(19, 9, 3, cYellow);
    End;
    icRecycle :
    Begin
      IFrame(7, 9, 24, 29, cSilver);
      QR(8, 10, 9, 28, cWhite);
      IFrame(5, 5, 26, 8, cSilver);
      QR(13, 3, 18, 5, cGray);
      For I := 0 To 2 Do QR(12 + I * 4, 12, 12 + I * 4, 26, cGray);
    End;
    icDos :
    Begin
      IFrame(2, 4, 29, 27, cSilver);
      QR(3, 5, 28, 9, cNavy);
      QR(3, 10, 28, 26, cBlack);
      QR(6, 13, 9, 14, cSilver);
      QR(11, 13, 14, 14, cSilver);
      QR(6, 18, 12, 19, cSilver);
      QR(14, 18, 16, 19, cWhite);
    End;
    icNotepad, icText :
    Begin
      IconPage;
      For I := 0 To 4 Do QR(9, 10 + I * 4, 22, 10 + I * 4, cGray);
      If Id = icNotepad Then
      Begin
        QR(6, 2, 25, 5, cNavy);
        For I := 0 To 4 Do QR(8 + I * 4, 1, 8 + I * 4, 4, cSilver);
      End;
    End;
    icCalc :
    Begin
      IFrame(7, 2, 24, 29, cSilver);
      IFrame(9, 4, 22, 9, cWhite);
      For I := 0 To 11 Do
        QR(10 + (I Mod 3) * 4, 12 + (I Div 3) * 4,
           11 + (I Mod 3) * 4, 13 + (I Div 3) * 4, cBlack);
      QR(23 - 2, 12, 22, 25, cRed);
    End;
    icFolder : IconFolder(cYellow);
    icPrograms :
    Begin
      IconFolder(cYellow);
      IFrame(10, 13, 22, 23, cWhite);
      QR(11, 14, 21, 15, cNavy);
    End;
    icDocs :
    Begin
      IconFolder(cYellow);
      IFrame(12, 11, 22, 25, cWhite);
      QR(14, 15, 20, 15, cGray); QR(14, 18, 20, 18, cGray);
    End;
    icSettings, icControl :
    Begin
      IconFolder(cYellow);
      IFrame(9, 14, 17, 22, cSilver);
      QR(11, 16, 15, 20, cTeal);
      QD(22, 19, 4, cRed);
      QC(22, 19, 4, cBlack);
    End;
    icCdrom :
    Begin
      IFrame(3, 14, 28, 25, cSilver);
      QR(6, 20, 25, 21, cBlack);
      QR(22, 16, 25, 17, cLime);
      QD(16, 8, 7, cSilver);
      QC(16, 8, 7, cGray);
      QD(16, 8, 2, cWhite);
      QL(12, 4, 15, 7, cAqua);
    End;
    icFloppy, icHardDisk :
    Begin
      IFrame(3, 12, 28, 23, cSilver);
      QR(4, 13, 27, 13, cWhite);
      If Id = icFloppy Then QR(8, 17, 23, 18, cBlack)
      Else QR(6, 19, 12, 20, cGray);
      QR(23, 20, 25, 21, cLime);
    End;
    icRegional :
    Begin
      QD(16, 16, 13, cBlue);
      QR(9, 9, 15, 15, cGreen);
      QR(17, 17, 24, 23, cGreen);
      QR(12, 19, 15, 25, cGreen);
      QC(16, 16, 13, cNavy);
    End;
    icClock :
    Begin
      QD(16, 16, 13, cWhite);
      QC(16, 16, 13, cBlack);
      QL(16, 16, 16, 7, cBlack);
      QL(16, 16, 23, 16, cBlack);
      For I := 0 To 3 Do
        QR(15 + (I Mod 2) * 0, 4, 16, 5, cBlack);
      QR(26, 15, 27, 16, cBlack);
      QR(15, 26, 16, 27, cBlack);
      QR(4, 15, 5, 16, cBlack);
    End;
    icHelp :
    Begin
      IFrame(5, 3, 26, 28, cNavy);
      QR(7, 5, 24, 26, cBlue);
      QR(23, 4, 25, 27, cWhite);
      QR(12, 9, 18, 10, cYellow);
      QR(18, 10, 19, 14, cYellow);
      QR(14, 15, 18, 16, cYellow);
      QR(14, 17, 15, 19, cYellow);
      QR(14, 22, 15, 23, cYellow);
    End;
    icRun :
    Begin
      IFrame(2, 6, 25, 27, cSilver);
      QR(3, 7, 24, 10, cNavy);
      QR(3, 11, 24, 26, cWhite);
      QL(14, 18, 29, 3, cBlack);
      QL(15, 18, 30, 3, cBlack);
      QR(24, 2, 30, 3, cBlack);
      QR(29, 2, 30, 8, cBlack);
    End;
    icShutdown :
    Begin
      IconMonitor(cBlack);
      IFrame(2, 25, 29, 29, cSilver);
      QC(16, 11, 4, cRed);
      QR(15, 5, 16, 11, cRed);
    End;
    icPaint :
    Begin
      QD(16, 17, 13, cSilver);
      QC(16, 17, 13, cBlack);
      QD(10, 12, 3, cRed);
      QD(18, 9, 3, cYellow);
      QD(24, 15, 3, cBlue);
      QD(22, 23, 3, cLime);
      QD(11, 21, 3, cWhite);
      QL(4, 30, 15, 17, cMaroon);
      QL(5, 30, 16, 17, cMaroon);
    End;
    icInfo :
    Begin
      QD(16, 15, 13, cWhite);
      QC(16, 15, 13, cBlack);
      QR(14, 7, 17, 10, cBlue);
      QR(14, 13, 17, 24, cBlue);
      QR(12, 23, 19, 24, cBlue);
    End;
    icWarn :
    Begin
      For I := 0 To 25 Do
        QR(16 - I Div 2, 3 + I, 16 + I Div 2, 3 + I, cYellow);
      QL(16, 3, 3, 28, cBlack);
      QL(16, 3, 29, 28, cBlack);
      QR(3, 28, 29, 28, cBlack);
      QR(15, 10, 17, 20, cBlack);
      QR(15, 23, 17, 25, cBlack);
    End;
    icError :
    Begin
      QD(16, 16, 13, cRed);
      QC(16, 16, 13, cMaroon);
      QL(11, 11, 21, 21, cWhite); QL(12, 11, 22, 21, cWhite);
      QL(21, 11, 11, 21, cWhite); QL(22, 11, 12, 21, cWhite);
    End;
    icApp :
    Begin
      IFrame(3, 6, 28, 26, cSilver);
      QR(4, 7, 27, 10, cNavy);
      QR(4, 11, 27, 25, cWhite);
    End;
    icExplorer :
    Begin
      IconFolder(cYellow);
      QD(19, 18, 6, cAqua);
      QC(19, 18, 6, cNavy);
      QL(14, 23, 9, 28, cBlack);
      QL(15, 23, 10, 28, cBlack);
    End;
    icLogo :
    Begin
      QR(2, 4, 29, 27, cNavy);
      QR(5, 7, 26, 10, cRed);
      QR(5, 12, 26, 15, cYellow);
      QR(5, 17, 26, 20, cLime);
      QR(5, 22, 26, 25, cAqua);
    End;
  End;
End;

{ ================================================================== }
{ Gestionnaire de fenetres                                           }
{ ================================================================== }

{ ================================================================== }
{ Clavier et souris PS/2 (controleur 8042, repris d'IO.SYS)          }
{ ================================================================== }

Procedure KbcWaitIn;
Var I : Integer;
Begin
  For I := 1 To 30000 Do
    If (Port[$64] And 2) = 0 Then Exit;
End;

Function KbcRead : Integer;
Var I : Integer;
Begin
  KbcRead := -1;
  For I := 1 To 30000 Do
    If (Port[$64] And 1) <> 0 Then
    Begin
      KbcRead := Port[$60];
      Exit;
    End;
End;

Procedure KbcCmd(B : Byte);
Begin
  KbcWaitIn;
  Port[$64] := B;
End;

Procedure KbcData(B : Byte);
Begin
  KbcWaitIn;
  Port[$60] := B;
End;

Function MouseCmd(B : Byte) : Boolean;
Begin
  KbcCmd($D4);
  KbcData(B);
  MouseCmd := KbcRead = $FA;
End;

Procedure InitInput;
Var I, CB : Integer;
Begin
  asm
    cli
  end;
  Port[$21] := Port[$21] Or $02;
  Port[$A1] := Port[$A1] Or $10;
  asm
    sti
  end;
  For I := 1 To 32 Do
    If (Port[$64] And 1) <> 0 Then CB := Port[$60];
  KbcCmd($A8);
  KbcCmd($20);
  CB := KbcRead;
  If CB < 0 Then CB := $45;
  CB := CB And $DC;
  KbcCmd($60);
  KbcData(CB);
  MouseOk := MouseCmd($F6);
  If MouseOk Then MouseOk := MouseCmd($F4);
  MPhase := 0;
  MouseX := ScrW Div 2; MouseY := ScrH Div 2;
  LastMX := MouseX; LastMY := MouseY;
  MouseBtn := 0;
  KExt := False; KShift := False; KCtrl := False; KAlt := False;
  KCaps := False;
  EvHead := 0; EvTail := 0;
End;

Procedure PushEvent(Var E : TEvent);
Var N : Integer;
Begin
  N := (EvTail + 1) Mod 32;
  If N = EvHead Then Exit;
  EvQ[EvTail] := E;
  EvTail := N;
End;

Procedure KeyByte(B : Byte);
Var Sc : Byte; Rel : Boolean; E : TEvent; C : Char;
Begin
  If B = $E0 Then
  Begin
    KExt := True;
    Exit;
  End;
  Rel := (B And $80) <> 0;
  Sc := B And $7F;
  Case Sc Of
    $2A, $36 : If Not KExt Then KShift := Not Rel;
    $1D : KCtrl := Not Rel;
    $38 : KAlt := Not Rel;
    $3A : If Not Rel Then KCaps := Not KCaps;
  Else
    If Not Rel Then
    Begin
      C := #0;
      If KExt Then
      Begin
        If Sc = $1C Then C := #13
        Else If Sc = $35 Then C := '/';
      End
      Else If (Sc <= $39) And ((Sc < $47) Or (Sc > $53)) Then
      Begin
        If KShift Then C := KeyHi[Sc + 1] Else C := KeyLo[Sc + 1];
        If KCaps And (UpCase(C) >= 'A') And (UpCase(C) <= 'Z') Then
        Begin
          If KShift Then C := KeyLo[Sc + 1] Else C := KeyHi[Sc + 1];
        End;
      End
      Else If Sc = $4A Then C := '-'
      Else If Sc = $4E Then C := '+';
      If KCtrl And (C >= ' ') Then C := #0;
      E.Kind := evKey; E.Ch := C; E.Sc := Sc;
      E.Shift := KShift; E.Ctrl := KCtrl; E.Alt := KAlt;
      E.X := MouseX; E.Y := MouseY; E.Btn := 0;
      PushEvent(E);
    End;
  End;
  KExt := False;
End;

Procedure MouseByte(B : Byte);
Var DX, DY, I : Integer; NB : Byte; E : TEvent;
Begin
  If (MPhase = 0) And ((B And 8) = 0) Then Exit;
  MPack[MPhase] := B;
  Inc(MPhase);
  If MPhase < 3 Then Exit;
  MPhase := 0;
  DX := MPack[1];
  If (MPack[0] And $10) <> 0 Then DX := DX - 256;
  DY := MPack[2];
  If (MPack[0] And $20) <> 0 Then DY := DY - 256;
  If (MPack[0] And $C0) <> 0 Then
  Begin
    DX := 0; DY := 0;
  End;
  MouseX := MouseX + DX;
  MouseY := MouseY - DY;
  If MouseX < 0 Then MouseX := 0;
  If MouseY < 0 Then MouseY := 0;
  If MouseX > ScrW - 1 Then MouseX := ScrW - 1;
  If MouseY > ScrH - 1 Then MouseY := ScrH - 1;
  NB := MPack[0] And 3;
  For I := 0 To 1 Do
    If ((NB Xor MouseBtn) And (1 Shl I)) <> 0 Then
    Begin
      If (NB And (1 Shl I)) <> 0 Then E.Kind := evDown Else E.Kind := evUp;
      E.Btn := I + 1;
      E.X := MouseX; E.Y := MouseY;
      E.Ch := #0; E.Sc := 0;
      E.Shift := KShift; E.Ctrl := KCtrl; E.Alt := KAlt;
      PushEvent(E);
    End;
  MouseBtn := NB;
End;

Procedure PollInput;
Var St, B : Byte;
Begin
  St := Port[$64];
  While (St And 1) <> 0 Do
  Begin
    B := Port[$60];
    If (St And $20) <> 0 Then MouseByte(B) Else KeyByte(B);
    St := Port[$64];
  End;
End;

{ ================================================================== }
{ Textes                                                             }
{ ================================================================== }

Function LangName(I : Integer) : String;
Begin
  Case I Of
    0 : LangName := 'Fran'#135'ais';
    1 : LangName := 'English';
    2 : LangName := 'Deutsch';
    3 : LangName := 'Italiano';
  Else
    LangName := 'Espa'#164'ol';
  End;
End;

Function LangIndex : Integer;
Begin
  Case Language Of
    _English : LangIndex := 1;
    _Germany : LangIndex := 2;
    _Italian : LangIndex := 3;
    _Spain   : LangIndex := 4;
  Else
    LangIndex := 0;
  End;
End;

Procedure SetLang(I : Integer);
Begin
  Case I Of
    1 : Language := _English;
    2 : Language := _Germany;
    3 : Language := _Italian;
    4 : Language := _Spain;
  Else
    Language := _French;
  End;
End;

Function TxtSetup : String;
Begin
  TxtSetup := L('Installation de Pasdows 95', 'Pasdows 95 Setup',
                'Pasdows 95 Setup', 'Installazione di Pasdows 95',
                'Instalaci'#162'n de Pasdows 95');
End;

Function PageName(I : Integer) : String;
Begin
  Case I Of
    pgLang : PageName := L('Langue', 'Language', 'Sprache', 'Lingua',
                           'Idioma');
    pgDisk : PageName := L('Disque dur', 'Hard disk', 'Festplatte',
                           'Disco rigido', 'Disco duro');
    pgTz : PageName := L('Fuseau horaire', 'Time zone', 'Zeitzone',
                         'Fuso orario', 'Zona horaria');
    pgDisp : PageName := L('Affichage', 'Display', 'Anzeige', 'Schermo',
                           'Pantalla');
    pgComp : PageName := L('Composants', 'Components', 'Komponenten',
                           'Componenti', 'Componentes');
    pgReady : PageName := L('R'#130'sum'#130, 'Summary', 'Zusammenfassung',
                            'Riepilogo', 'Resumen');
    pgCopy : PageName := L('Copie', 'Copying', 'Kopieren', 'Copia',
                           'Copia');
  Else
    PageName := L('Red'#130'marrage', 'Restart', 'Neustart', 'Riavvio',
                  'Reinicio');
  End;
End;

Function TxtYes : String;
Begin
  TxtYes := L('Oui', 'Yes', 'Ja', 'S'#141, 'S'#161);
End;

Function TxtNo : String;
Begin
  TxtNo := L('Non', 'No', 'Nein', 'No', 'No');
End;

Function TxtMb : String;
Begin
  TxtMb := L(' Mo', ' MB', ' MB', ' MB', ' MB');
End;

Function TzName(I : Integer) : String;
Var O, A : Integer; S : String;
Begin
  O := TzOfs[I];
  If O < 0 Then S := '(GMT-' Else S := '(GMT+';
  A := Abs(O);
  S := S + Pad2(A Div 60) + ':' + Pad2(A Mod 60) + ') ';
  Case I Of
    0 : S := S + L('Hawa'#139, 'Hawaii', 'Hawaii', 'Hawaii', 'Hawai');
    1 : S := S + 'Alaska';
    2 : S := S + L('Pacifique (EU et Canada)', 'Pacific (US & Canada)',
                   'Pazifik (USA, Kanada)', 'Pacifico (USA e Canada)',
                   'Pac'#161'fico (EE.UU. y Canad'#160')');
    3 : S := S + L('Rocheuses (EU et Canada)', 'Mountain (US & Canada)',
                   'Mountain (USA, Kanada)', 'Montagne (USA e Canada)',
                   'Monta'#164'a (EE.UU. y Canad'#160')');
    4 : S := S + L('Centre (EU et Canada)', 'Central (US & Canada)',
                   'Central (USA, Kanada)', 'Centrale (USA e Canada)',
                   'Centro (EE.UU. y Canad'#160')');
    5 : S := S + L('Est (EU et Canada)', 'Eastern (US & Canada)',
                   'Eastern (USA, Kanada)', 'Orientale (USA e Canada)',
                   'Este (EE.UU. y Canad'#160')');
    6 : S := S + L('Atlantique (Canada)', 'Atlantic (Canada)',
                   'Atlantik (Kanada)', 'Atlantico (Canada)',
                   'Atl'#160'ntico (Canad'#160')');
    7 : S := S + L('Terre-Neuve', 'Newfoundland', 'Neufundland',
                   'Terranova', 'Terranova');
    8 : S := S + 'Brasilia, Buenos Aires';
    9 : S := S + L('A'#135'ores', 'Azores', 'Azoren', 'Azzorre', 'Azores');
    10 : S := S + L('Greenwich : Londres, Lisbonne',
                    'Greenwich: London, Lisbon', 'London, Lissabon',
                    'Londra, Lisbona', 'Londres, Lisboa');
    11 : S := S + L('Paris, Madrid, Rome, Berlin',
                    'Paris, Madrid, Rome, Berlin', 'Berlin, Paris, Rom',
                    'Roma, Parigi, Berlino', 'Madrid, Par'#161's, Roma');
    12 : S := S + L('Ath'#138'nes, Le Caire', 'Athens, Cairo',
                    'Athen, Kairo', 'Atene, Il Cairo', 'Atenas, El Cairo');
    13 : S := S + L('Moscou', 'Moscow', 'Moskau', 'Mosca', 'Mosc'#163);
    14 : S := S + 'Bombay, New Delhi';
    15 : S := S + L('P'#130'kin, Hong Kong', 'Beijing, Hong Kong',
                    'Peking, Hongkong', 'Pechino, Hong Kong',
                    'Pek'#161'n, Hong Kong');
    16 : S := S + 'Tokyo, Osaka';
  Else
    S := S + L('Sydney, Melbourne', 'Sydney, Melbourne', 'Sydney',
               'Sydney', 'Sidney');
  End;
  TzName := S;
End;

Function FsName(I : Integer) : String;
Begin
  Case I Of
    0 : FsName := 'FAT16';
    1 : FsName := 'FAT32';
  Else
    FsName := 'NTFS';
  End;
End;

Function DispName(I : Integer) : String;
Var S : String;
Begin
  S := IntToStr(DispW[I]) + ' x ' + IntToStr(DispH[I]) + ', ';
  Case DispB[I] Of
    4 : S := S + L('16 couleurs (VGA)', '16 colors (VGA)', '16 Farben (VGA)',
                   '16 colori (VGA)', '16 colores (VGA)');
    8 : S := S + L('256 couleurs', '256 colors', '256 Farben', '256 colori',
                   '256 colores');
  Else
    S := S + L('65 536 couleurs', '65,536 colors', '65.536 Farben',
               '65.536 colori', '65.536 colores');
  End;
  If I = 0 Then S := S + L(' (d'#130'faut)', ' (default)', ' (Standard)',
                           ' (predefinito)', ' (predeterminado)');
  DispName := S;
End;

Function PartTypeName(T : Byte) : String;
Begin
  Case T Of
    $01 : PartTypeName := 'FAT12';
    $04, $06, $0E : PartTypeName := 'FAT16';
    $05, $0F : PartTypeName := L('Etendue', 'Extended', 'Erweitert',
                                 'Estesa', 'Extendida');
    $07 : PartTypeName := 'NTFS';
    $0B, $0C : PartTypeName := 'FAT32';
    $82 : PartTypeName := 'Linux swap';
    $83 : PartTypeName := 'Linux';
  Else
    PartTypeName := L('Type ', 'Type ', 'Typ ', 'Tipo ', 'Tipo ') +
                    HexByte(T) + 'h';
  End;
End;

{ ================================================================== }
{ Disques durs (INT 13h etendue)                                     }
{ ================================================================== }

Function HdIo(D : Byte; Wr : Boolean; Lba : LongInt; BSeg : Word;
              N : Integer) : Boolean;
Var Err, Tries, Fn : Byte;
Begin
  If Wr Then Fn := $43 Else Fn := $42;
  Tries := 0;
  Repeat
    Dap.Size := 16; Dap.Res := 0; Dap.Count := N;
    Dap.BufOfs := 0; Dap.BufSg := BSeg;
    Dap.LbaLo := Lba; Dap.LbaHi := 0;
    asm
      push si
      mov ah,Fn
      mov al,0
      mov dl,D
      lea si,Dap
      int 13h
      mov al,0
      adc al,0
      mov Err,al
      pop si
    end;
    If Err = 0 Then
    Begin
      HdIo := True;
      Exit;
    End;
    asm
      xor ah,ah
      mov dl,D
      int 13h
    end;
    Inc(Tries);
  Until Tries >= 3;
  HdIo := False;
End;

{ Lire N secteurs de 2 Ko du CD-ROM en Seg:0000 }
Function CdReadN(Lba : LongInt; BSeg : Word; N : Integer) : Boolean;
Var Err, D : Byte; Tries : Integer;
Begin
  Tries := 0;
  Repeat
    Dap.Size := 16; Dap.Res := 0; Dap.Count := N;
    Dap.BufOfs := 0; Dap.BufSg := BSeg;
    Dap.LbaLo := Lba; Dap.LbaHi := 0;
    D := BootDrive;
    asm
      push si
      mov ah,42h
      mov dl,D
      lea si,Dap
      int 13h
      mov al,0
      adc al,0
      mov Err,al
      pop si
    end;
    If Err = 0 Then
    Begin
      CdReadN := True;
      Exit;
    End;
    Inc(Tries);
  Until Tries >= 3;
  CdReadN := False;
End;

{ Disques durs du BIOS : nombre, taille, geometrie, extensions }
Procedure DetectDisks;
Var I, N, H, S : Integer; D, Ok : Byte; BxV : Word; Sec : LongInt;
Begin
  { nombre de disques : BDA 0040:0075, ou INT 13h AH=08h (DL) }
  N := Mem[$0040:$0075];
  Ok := 0;
  asm
    mov ah,08h
    mov dl,80h
    push es
    int 13h
    pop es
    jc @nod
    mov Ok,dl
  @nod:
  end;
  If Ok > N Then N := Ok;
  If N > 4 Then N := 4;
  DiskCnt := 0;
  For I := 0 To N - 1 Do
  Begin
    D := $80 + I;
    Ok := 0; BxV := 0;
    asm
      mov ah,41h
      mov bx,55AAh
      mov dl,D
      int 13h
      jc @no
      mov BxV,bx
      mov Ok,1
    @no:
    end;
    DiskExt[I] := (Ok = 1) And (BxV = $AA55);
    { geometrie (CHS) }
    H := 255; S := 63; Ok := 0;
    asm
      mov ah,08h
      mov dl,D
      push es
      int 13h
      pop es
      jc @nog
      mov Ok,1
      mov al,dh
      xor ah,ah
      inc ax
      mov H,ax
      mov al,cl
      and ax,3Fh
      mov S,ax
    @nog:
    end;
    If (Ok = 0) Or (S = 0) Then
    Begin
      H := 255; S := 63;
    End;
    DiskHeads[I] := H; DiskSpt[I] := S;
    { taille : INT 13h AH=48h (tampon en SecSeg) }
    Sec := 0;
    If DiskExt[I] Then
    Begin
      MemW[SecSeg:0] := 26;
      For BxV := 2 To 25 Do Mem[SecSeg:BxV] := 0;
      Ok := 0;
      asm
        push si
        push ds
        mov ah,48h
        mov dl,D
        mov si,8100h
        mov ds,si
        xor si,si
        int 13h
        pop ds
        pop si
        jc @nos
        mov Ok,1
      @nos:
      end;
      If Ok = 1 Then
      Begin
        Sec := GetD(SecSeg, 16);
        If (GetD(SecSeg, 20) <> 0) Or (Sec < 0) Then Sec := $7FFFFFFF;
      End;
    End;
    DiskSecs[I] := Sec;
    Inc(DiskCnt);
  End;
End;

{ Lire la table des partitions du disque DiskSel }
Procedure ReadPartitions;
Var I, Ofs : Integer;
Begin
  MbrOk := False;
  For I := 0 To 3 Do
  Begin
    PType[I] := 0; PBoot[I] := 0; PStart[I] := 0; PSize[I] := 0;
  End;
  PExist := -1;
  If (DiskSel < 0) Or Not DiskExt[DiskSel] Then Exit;
  If Not HdIo($80 + DiskSel, False, 0, SecSeg, 1) Then Exit;
  If MemW[SecSeg:510] <> $AA55 Then Exit;
  MbrOk := True;
  For I := 0 To 3 Do
  Begin
    Ofs := 446 + I * 16;
    PBoot[I] := Mem[SecSeg:Ofs];
    PType[I] := Mem[SecSeg:Ofs + 4];
    PStart[I] := GetD(SecSeg, Ofs + 8);
    PSize[I] := GetD(SecSeg, Ofs + 12);
    If (PExist < 0) And (PType[I] <> 0) And (PType[I] <> $05) And
       (PType[I] <> $0F) And (PSize[I] Div 2048 >= MinMb) Then
      PExist := I;
  End;
End;

Procedure ChooseDisk(I : Integer);
Begin
  DiskSel := I;
  MaxMb := 0;
  If (I >= 0) And DiskExt[I] And (DiskSecs[I] > 2048) Then
    MaxMb := (DiskSecs[I] - 2048) Div 2048;
  If MaxMb > 1000000 Then MaxMb := 1000000;
  PartMb := MaxMb;
  If PartMb > FsMaxMb[FsKind] Then PartMb := FsMaxMb[FsKind];
  ReadPartitions;
  PartMode := 0;
End;

Function DiskUsable : Boolean;
Begin
  DiskUsable := False;
  If DiskSel < 0 Then Exit;
  If Not DiskExt[DiskSel] Then Exit;
  If PartMode = 0 Then DiskUsable := MaxMb >= FsMinMb[FsKind]
  Else DiskUsable := PExist >= 0;
End;

Function DiskText(I : Integer) : String;
Begin
  DiskText := L('Disque ', 'Disk ', 'Festplatte ', 'Disco ', 'Disco ') +
              IntToStr(I + 1) + ' (' + HexByte($80 + I) + 'h) : ' +
              FmtNum(DiskSecs[I] Div 2048) + TxtMb;
End;
{ ================================================================== }
{ Dessin de l'assistant                                              }
{ ================================================================== }

{ Liste des fuseaux horaires (zone et lignes visibles) }
Procedure TzBox(Var X1, Y1, X2, Y2, Rows : Integer);
Begin
  X1 := CX1; Y1 := CY1 + 56; X2 := CX2; Y2 := Y1 + 4 + 10 * 18;
  Rows := 10;
End;

{ Bouton I (0 Precedent, 1 Suivant, 2 Annuler) ; False s'il est cache }
Function NavBtn(I : Integer; Var X1, Y1, X2, Y2 : Integer) : Boolean;
Begin
  Y1 := BtnY1; Y2 := BtnY2;
  Case I Of
    0 : Begin X1 := CX2 - 306; X2 := CX2 - 208; End;
    1 : Begin X1 := CX2 - 206; X2 := CX2 - 108; End;
  Else
    Begin X1 := CX2 - 96; X2 := CX2; End;
  End;
  NavBtn := True;
  If (Page = pgCopy) Then NavBtn := False;
  If (Page = pgDone) And (I <> 1) Then NavBtn := False;
  If (Page = pgLang) And (I = 0) Then NavBtn := False;
End;

Function NavText(I : Integer) : String;
Begin
  Case I Of
    0 : NavText := L('< Pr'#130'c'#130'dent', '< Back', '< Zur'#129'ck',
                     '< Indietro', '< Atr'#160's');
    1 :
      If Page = pgReady Then
        NavText := L('Installer', 'Install', 'Installieren', 'Installa',
                     'Instalar')
      Else If Page = pgDone Then
        NavText := L('Red'#130'marrer', 'Restart', 'Neu starten', 'Riavvia',
                     'Reiniciar')
      Else
        NavText := L('Suivant >', 'Next >', 'Weiter >', 'Avanti >',
                     'Siguiente >');
  Else
    NavText := L('Annuler', 'Cancel', 'Abbrechen', 'Annulla', 'Cancelar');
  End;
End;

Function NavEnabled(I : Integer) : Boolean;
Begin
  NavEnabled := True;
  If (I = 1) And (Page = pgDisk) And Not DiskUsable Then
    NavEnabled := False;
End;

Procedure DrawNav;
Var I, X1, Y1, X2, Y2 : Integer;
Begin
  For I := 0 To 2 Do
    If NavBtn(I, X1, Y1, X2, Y2) Then
    Begin
      PushButton(X1, Y1, X2, Y2, NavText(I), PressBtn = I, I = 1);
      If Not NavEnabled(I) Then
      Begin
        Bar(X1 + 4, Y1 + 4, X2 - 4, Y2 - 4, cSilver);
        OutCenter(X1 + 1, X2 + 1, (Y1 + Y2 - 15) Div 2 + 1, NavText(I),
                  cWhite);
        OutCenter(X1, X2, (Y1 + Y2 - 15) Div 2, NavText(I), cGray);
      End;
    End;
End;

Procedure CheckBox(X, Y : Integer; Const S : String; On : Boolean);
Begin
  Sunken(X, Y + 1, X + 12, Y + 13, cWhite);
  If On Then
  Begin
    Line(X + 3, Y + 6, X + 5, Y + 8, cBlack);
    Line(X + 3, Y + 7, X + 5, Y + 9, cBlack);
    Line(X + 5, Y + 8, X + 9, Y + 4, cBlack);
    Line(X + 5, Y + 9, X + 9, Y + 5, cBlack);
  End;
  OutText(X + 18, Y, S, cBlack);
End;

{ Petit bouton carre avec un texte (+, -, fleches) }
Procedure SmallBtn(X1, Y1, X2, Y2 : Integer; Const S : String);
Begin
  Raised(X1, Y1, X2, Y2, False);
  OutCenter(X1, X2, (Y1 + Y2 - 15) Div 2, S, cBlack);
End;

Procedure ProgressBar(Pct : Integer);
Var X1, X2, I, N : Integer;
Begin
  X1 := CX1; X2 := CX2;
  Sunken(X1, CY1 + 150, X2, CY1 + 172, cWhite);
  N := ((X2 - X1 - 6) Div 10) * Pct Div 100;
  For I := 0 To N - 1 Do
    Bar(X1 + 4 + I * 10, CY1 + 154, X1 + 11 + I * 10, CY1 + 168, cNavy);
  Bar(CX1, CY1 + 176, CX2, CY1 + 192, cSilver);
  OutCenter(CX1, CX2, CY1 + 176, IntToStr(Pct) + ' %', cBlack);
End;

Procedure DrawStatus;
Var Pct : LongInt;
Begin
  HideCursor;
  Bar(CX1, CY1 + 120, CX2, CY1 + 140, cSilver);
  OutText(CX1, CY1 + 122, Fit(StatusText, CX2 - CX1), cBlack);
  If TotalBytes > 0 Then
    Pct := DoneBytes Div (TotalBytes Div 100 + 1)
  Else Pct := 0;
  If Pct > 100 Then Pct := 100;
  ProgressBar(Pct);
  ShowCursor;
End;

Function SizeOfCd(Const N : String) : LongInt;
Var I : Integer;
Begin
  SizeOfCd := 0;
  I := CdFind(N);
  If I >= 0 Then SizeOfCd := CdFiles[I].Size;
End;

{ Le fichier N du CD-ROM est-il installe (selon les composants) ? }
Function WantFile(Const N : String) : Boolean;
Var E : String;
Begin
  WantFile := False;
  If (N = 'INSTALL.SYS') Or (N = 'MSDOS.SYS') Or (N = 'CONFIG.SYS') Or
     (N = 'AUTOEXEC.BAT') Then Exit;
  E := Copy(N, Length(N) - 3, 4);
  If (N = 'PASDOWS.WAV') And Not CompSnd Then Exit;
  If (N = 'LISEZMOI.TXT') And Not CompDoc Then Exit;
  { COMMAND.EXE et Paint (accessoire) sont toujours installes }
  If (E = '.EXE') And (N <> 'COMMAND.EXE') And (N <> 'PAINT.EXE') And
     Not CompEx Then Exit;
  WantFile := True;
End;

Function NeedMb : LongInt;
Var I : Integer; T : LongInt;
Begin
  T := 0;
  For I := 0 To CdCount - 1 Do
    If Not CdFiles[I].Dir And WantFile(CdFiles[I].Name) Then
      T := T + CdFiles[I].Size;
  NeedMb := T Div 1048576 + 1;
End;

Procedure DrawPageLang;
Var I, N : Integer;
Begin
  N := WrapText(CX1, CY1, CX2 - CX1, L('Bienvenue dans l''installation de ' +
    'Pasdows 95. Ce programme installe Pasdows 95 sur le disque dur de ' +
    'votre ordinateur : il peut cr'#130'er une partition, la formater ' +
    '(FAT16, FAT32 ou NTFS) et copier les fichiers du syst'#138'me.',
    'Welcome to Pasdows 95 Setup. This program installs Pasdows 95 on ' +
    'the hard disk of your computer: it can create a partition, format ' +
    'it with FAT32 and copy the system files.',
    'Willkommen bei Pasdows 95 Setup. Dieses Programm installiert ' +
    'Pasdows 95 auf der Festplatte: es kann eine Partition erstellen, ' +
    'sie mit FAT32 formatieren und die Systemdateien kopieren.',
    'Benvenuti nell''installazione di Pasdows 95. Questo programma ' +
    'installa Pasdows 95 sul disco rigido: pu'#149' creare una partizione, ' +
    'formattarla in FAT32 e copiare i file di sistema.',
    'Bienvenido a la instalaci'#162'n de Pasdows 95. Este programa ' +
    'instala Pasdows 95 en el disco duro: puede crear una partici'#162'n, ' +
    'formatearla en FAT32 y copiar los archivos del sistema.'),
    cBlack, True);
  GroupBox(CX1, CY1 + N * 16 + 20, CX2, CY1 + N * 16 + 30 + 5 * 24,
           L('Langue', 'Language', 'Sprache', 'Lingua', 'Idioma'));
  For I := 0 To 4 Do
    RadioButton(CX1 + 14, CY1 + N * 16 + 34 + I * 24, LangName(I),
                I = LangIndex);
End;

Function LangRadioY(I : Integer) : Integer;
Var N : Integer;
Begin
  N := WrapText(CX1, CY1, CX2 - CX1, L('Bienvenue dans l''installation de ' +
    'Pasdows 95. Ce programme installe Pasdows 95 sur le disque dur de ' +
    'votre ordinateur : il peut cr'#130'er une partition, la formater ' +
    '(FAT16, FAT32 ou NTFS) et copier les fichiers du syst'#138'me.',
    'Welcome to Pasdows 95 Setup. This program installs Pasdows 95 on ' +
    'the hard disk of your computer: it can create a partition, format ' +
    'it with FAT32 and copy the system files.',
    'Willkommen bei Pasdows 95 Setup. Dieses Programm installiert ' +
    'Pasdows 95 auf der Festplatte: es kann eine Partition erstellen, ' +
    'sie mit FAT32 formatieren und die Systemdateien kopieren.',
    'Benvenuti nell''installazione di Pasdows 95. Questo programma ' +
    'installa Pasdows 95 sul disco rigido: pu'#149' creare una partizione, ' +
    'formattarla in FAT32 e copiare i file di sistema.',
    'Bienvenido a la instalaci'#162'n de Pasdows 95. Este programa ' +
    'instala Pasdows 95 en el disco duro: puede crear una partici'#162'n, ' +
    'formatearla en FAT32 y copiar los archivos del sistema.'),
    cBlack, False);
  LangRadioY := CY1 + N * 16 + 34 + I * 24;
End;

Procedure DrawPageDisk;
Var I, Y : Integer; S : String;
Begin
  If DiskCnt = 0 Then
  Begin
    WrapText(CX1, CY1, CX2 - CX1, L('Aucun disque dur n''a '#130't'#130' ' +
      'trouv'#130'. Pasdows 95 ne peut pas '#136'tre install'#130'.',
      'No hard disk was found. Pasdows 95 cannot be installed.',
      'Keine Festplatte gefunden. Pasdows 95 kann nicht installiert ' +
      'werden.', 'Nessun disco rigido trovato. Impossibile installare ' +
      'Pasdows 95.', 'No se encontr'#162' ning'#163'n disco duro. No se ' +
      'puede instalar Pasdows 95.'), cBlack, True);
    Exit;
  End;
  OutText(CX1, CY1, L('Disque :', 'Disk:', 'Festplatte:', 'Disco:',
          'Disco:'), cBlack);
  For I := 0 To DiskCnt - 1 Do
    RadioButton(CX1 + 4, CY1 + 20 + I * 20, DiskText(I), I = DiskSel);
  Y := CY1 + 28 + DiskCnt * 20;
  { table des partitions actuelle }
  OutText(CX1, Y, L('Partitions actuelles :', 'Current partitions:',
          'Vorhandene Partitionen:', 'Partizioni attuali:',
          'Particiones actuales:'), cBlack);
  Sunken(CX1, Y + 18, CX2, Y + 18 + 4 * 16 + 6, cWhite);
  If Not DiskExt[DiskSel] Then
    OutText(CX1 + 6, Y + 21, Fit(L('Extensions INT 13h absentes.',
            'No INT 13h extensions.', 'Keine INT-13h-Erweiterungen.',
            'Estensioni INT 13h assenti.', 'Sin extensiones INT 13h.'),
            CX2 - CX1 - 12), cRed)
  Else If Not MbrOk Or ((PType[0] = 0) And (PType[1] = 0) And
          (PType[2] = 0) And (PType[3] = 0)) Then
    OutText(CX1 + 6, Y + 21, L('(disque vide)', '(empty disk)',
            '(leere Festplatte)', '(disco vuoto)', '(disco vac'#161'o)'),
            cGray)
  Else
    For I := 0 To 3 Do
      If PType[I] <> 0 Then
      Begin
        S := IntToStr(I + 1) + '  ' + PartTypeName(PType[I]);
        While Length(S) < 16 Do S := S + ' ';
        S := S + FmtNum(PSize[I] Div 2048) + TxtMb;
        If PBoot[I] = $80 Then
          S := S + L(' (active)', ' (active)', ' (aktiv)', ' (attiva)',
                     ' (activa)');
        OutText(CX1 + 6, Y + 21 + I * 16, Fit(S, CX2 - CX1 - 12), cBlack);
      End;
  Y := Y + 100;
  RadioButton(CX1, Y, L('Cr'#130'er une nouvelle partition',
              'Create a new partition', 'Neue Partition erstellen',
              'Creare una nuova partizione', 'Crear una partici'#162'n nueva'),
              PartMode = 0);
  OutText(CX1 + 18, Y + 22, L('Taille :', 'Size:', 'Gr'#148#225'e:',
          'Dimensione:', 'Tama'#164'o:'), cBlack);
  Sunken(CX1 + 112, Y + 18, CX1 + 200, Y + 40, cWhite);
  OutText(CX1 + 118, Y + 21, IntToStr(PartMb), cBlack);
  SmallBtn(CX1 + 204, Y + 18, CX1 + 226, Y + 40, '-');
  SmallBtn(CX1 + 228, Y + 18, CX1 + 250, Y + 40, '+');
  OutText(CX1 + 256, Y + 22, L('Mo', 'MB', 'MB', 'MB', 'MB') + ' / ' +
          IntToStr(MaxMb), cBlack);
  S := L('(efface tout le disque)', '(erases the whole disk)',
         '(l'#148'scht die ganze Festplatte)', '(cancella tutto il disco)',
         '(borra todo el disco)');
  OutText(CX1 + 18, Y + 42, S, cMaroon);
  If PExist >= 0 Then
    RadioButton(CX1, Y + 64, Fit(L('Formater la partition ',
                'Format partition ', 'Partition formatieren: ',
                'Formatta la partizione ', 'Formatear la partici'#162'n ') +
                IntToStr(PExist + 1) + ' (' + FmtNum(PSize[PExist] Div 2048)
                + TxtMb + ')', CX2 - CX1 - 20), PartMode = 1);
  OutText(CX1, Y + 86, L('Syst'#138'me de fichiers :', 'File system:',
          'Dateisystem:', 'File system:', 'Sistema de archivos:'), cBlack);
  For I := 0 To FsCount - 1 Do
    RadioButton(CX1 + 18 + I * 90, Y + 106, FsName(I), I = FsKind);
  If MaxMb < FsMinMb[FsKind] Then
    OutText(CX1, Y + 126, L('Disque trop petit pour ', 'Disk too small for ',
            'Festplatte zu klein: ', 'Disco troppo piccolo: ',
            'Disco demasiado peque'#164'o: ') + FsName(FsKind) + '.', cRed);
End;

Function DiskOptY : Integer;
Begin
  DiskOptY := CY1 + 28 + DiskCnt * 20 + 100;
End;

Procedure DrawTzList;
Var X1, Y1, X2, Y2, Rows, I, Y, Fg : Integer;
Begin
  TzBox(X1, Y1, X2, Y2, Rows);
  Sunken(X1, Y1, X2, Y2, cWhite);
  For I := TzTop To TzTop + Rows - 1 Do
    If I < TzCount Then
    Begin
      Y := Y1 + 3 + (I - TzTop) * 18;
      Fg := cBlack;
      If I = TzSel Then
      Begin
        Bar(X1 + 3, Y, X2 - 20, Y + 16, cNavy);
        Fg := cWhite;
      End;
      OutText(X1 + 5, Y, Fit(TzName(I), X2 - X1 - 28), Fg);
    End;
  Bar(X2 - 18, Y1 + 2, X2 - 2, Y2 - 2, cSilver);
  SmallBtn(X2 - 18, Y1 + 2, X2 - 2, Y1 + 18, '');
  Arrow(X2 - 13, Y1 + 8, 2, cBlack);
  SmallBtn(X2 - 18, Y2 - 18, X2 - 2, Y2 - 2, '');
  Arrow(X2 - 13, Y2 - 12, 1, cBlack);
  Y := Y1 + 20 + (TzTop * (Y2 - Y1 - 56)) Div (TzCount - Rows);
  Raised(X2 - 18, Y, X2 - 2, Y + 16, False);
End;

Procedure DrawPageTz;
Var X1, Y1, X2, Y2, Rows, H, M, S, Yr, Mo, D : Integer;
Begin
  WrapText(CX1, CY1, CX2 - CX1, L('Choisissez le fuseau horaire de ' +
    'votre r'#130'gion :', 'Select the time zone of your region:',
    'W'#132'hlen Sie Ihre Zeitzone:', 'Scegliere il fuso orario:',
    'Seleccione su zona horaria:'), cBlack, True);
  RtcTime(H, M, S); RtcDate(Yr, Mo, D);
  OutText(CX1, CY1 + 34, L('Date et heure : ', 'Date and time: ',
          'Datum und Uhrzeit: ', 'Data e ora: ', 'Fecha y hora: ') +
          Pad2(D) + '/' + Pad2(Mo) + '/' + IntToStr(Yr) + ' ' + Pad2(H) +
          ':' + Pad2(M), cBlack);
  DrawTzList;
  TzBox(X1, Y1, X2, Y2, Rows);
  CheckBox(CX1, Y2 + 10, Fit(L('Ajuster l''horloge pour l''heure ' +
           'd'''#130't'#130, 'Adjust the clock for daylight saving',
           'Uhr auf Sommerzeit umstellen',
           'Regola automaticamente l''ora legale',
           'Ajustar el reloj al horario de verano'), CX2 - CX1 - 20),
           TzDst);
End;

Procedure DrawPageDisp;
Var I : Integer;
Begin
  WrapText(CX1, CY1, CX2 - CX1, L('Choisissez la zone d'''#130'cran et le ' +
    'nombre de couleurs. Si la carte graphique ne permet pas ce mode, ' +
    'Pasdows utilisera 640 x 480 en 256 couleurs.',
    'Select the screen area and the number of colors. If the video card ' +
    'does not support it, Pasdows uses 640 x 480 with 256 colors.',
    'W'#132'hlen Sie Aufl'#148'sung und Farben. Ohne Unterst'#129'tzung der ' +
    'Grafikkarte verwendet Pasdows 640 x 480 mit 256 Farben.',
    'Scegliere risoluzione e colori. Se la scheda video non li supporta, ' +
    'Pasdows usa 640 x 480 a 256 colori.',
    'Seleccione resoluci'#162'n y colores. Si la tarjeta de v'#161'deo no ' +
    'lo admite, Pasdows usa 640 x 480 con 256 colores.'), cBlack, True);
  GroupBox(CX1, CY1 + 84, CX2, CY1 + 94 + DispCount * 24,
           PageName(pgDisp));
  For I := 0 To DispCount - 1 Do
    RadioButton(CX1 + 14, CY1 + 98 + I * 24, DispName(I), I = DispSel);
End;

Procedure DrawPageComp;
Var Y : Integer;
Begin
  WrapText(CX1, CY1, CX2 - CX1, L('Choisissez les composants '#133' ' +
    'installer :', 'Select the components to install:',
    'W'#132'hlen Sie die zu installierenden Komponenten:',
    'Scegliere i componenti da installare:',
    'Seleccione los componentes que desea instalar:'), cBlack, True);
  Y := CY1 + 30;
  CheckBox(CX1, Y, L('Programmes d''exemple', 'Sample programs',
           'Beispielprogramme', 'Programmi di esempio',
           'Programas de ejemplo'), CompEx);
  OutText(CX1 + 18, Y + 18, '(HELLO, DDTEST, FATTEST, NETTEST)', cGray);
  CheckBox(CX1, Y + 44, L('Son de d'#130'marrage', 'Startup sound',
           'Startklang', 'Suono di avvio', 'Sonido de inicio') +
           ' (PASDOWS.WAV)', CompSnd);
  CheckBox(CX1, Y + 72, L('Lisez-moi', 'Read Me', 'Liesmich', 'Leggimi',
           'L'#130'ame') + ' (LISEZMOI.TXT)', CompDoc);
  GroupBox(CX1, Y + 110, CX2, Y + 170, L('Espace disque', 'Disk space',
           'Speicherplatz', 'Spazio su disco', 'Espacio en disco'));
  OutText(CX1 + 12, Y + 124, L('N'#130'cessaire : ', 'Required: ',
          'Erforderlich: ', 'Necessario: ', 'Necesario: ') +
          IntToStr(NeedMb) + TxtMb, cBlack);
  If PartMode = 0 Then
    OutText(CX1 + 12, Y + 144, L('Disponible : ', 'Available: ',
            'Verf'#129'gbar: ', 'Disponibile: ', 'Disponible: ') +
            FmtNum(PartMb) + TxtMb, cBlack)
  Else
    OutText(CX1 + 12, Y + 144, L('Disponible : ', 'Available: ',
            'Verf'#129'gbar: ', 'Disponibile: ', 'Disponible: ') +
            FmtNum(PSize[PExist] Div 2048) + TxtMb, cBlack);
End;

Procedure SumLine(Var Y : Integer; Const A, B : String);
Begin
  OutBold(CX1, Y, A, cBlack);
  Y := Y + 16;
  OutText(CX1 + 16, Y, Fit(B, CX2 - CX1 - 16), cBlack);
  Y := Y + 22;
End;

Procedure DrawPageReady;
Var Y : Integer; S : String;
Begin
  OutText(CX1, CY1, Fit(L('Pasdows 95 va '#136'tre install'#130' :',
          'Pasdows 95 will be installed:', 'Pasdows 95 wird installiert:',
          'Pasdows 95 verr'#133' installato:', 'Se instalar'#160' ' +
          'Pasdows 95:'), CX2 - CX1), cBlack);
  Y := CY1 + 26;
  SumLine(Y, PageName(pgLang), LangName(LangIndex));
  If PartMode = 0 Then
    S := L('Nouvelle partition ', 'New ', 'Neue ', 'Nuova partizione ',
           'Nueva partici'#162'n ') + FsName(FsKind) +
         L(' de ', ' partition, ', '-Partition, ', ' di ', ' de ') +
         FmtNum(PartMb) + TxtMb
  Else
    S := L('Formater la partition ', 'Format partition ',
           'Partition formatieren: ', 'Formattare la partizione ',
           'Formatear la partici'#162'n ') + IntToStr(PExist + 1) +
         ' (' + FsName(FsKind) + ')';
  SumLine(Y, DiskText(DiskSel), S);
  SumLine(Y, L('Dossier', 'Folder', 'Ordner', 'Cartella', 'Carpeta'),
          'C:\WINDOWS');
  S := TzName(TzSel);
  SumLine(Y, PageName(pgTz), S);
  SumLine(Y, PageName(pgDisp), DispName(DispSel));
  WrapText(CX1, Y, CX2 - CX1, L('Attention : les donn'#130'es de la ' +
    'partition seront effac'#130'es. Cliquez sur Installer pour commencer.',
    'Warning: the data of the partition will be erased. Click Install ' +
    'to begin.', 'Achtung: die Daten der Partition werden gel'#148'scht. ' +
    'Klicken Sie auf Installieren.', 'Attenzione: i dati della ' +
    'partizione saranno cancellati. Fare clic su Installa.',
    'Atenci'#162'n: se borrar'#160'n los datos de la partici'#162'n. Haga ' +
    'clic en Instalar.'), cMaroon, True);
End;

Procedure DrawPageCopy;
Begin
  WrapText(CX1, CY1, CX2 - CX1, L('Pasdows 95 est en cours ' +
    'd''installation. Cette op'#130'ration peut prendre quelques minutes.',
    'Pasdows 95 is being installed. This may take a few minutes.',
    'Pasdows 95 wird installiert. Dies kann einige Minuten dauern.',
    'Installazione di Pasdows 95 in corso. Potrebbe richiedere alcuni ' +
    'minuti.', 'Se est'#160' instalando Pasdows 95. Esto puede tardar ' +
    'unos minutos.'), cBlack, True);
  DrawIcon(icHardDisk, CX1, CY1 + 60, 32);
  DrawIcon(icCdrom, CX1 + 48, CY1 + 60, 32);
  OutText(CX1, CY1 + 122, Fit(StatusText, CX2 - CX1), cBlack);
  ProgressBar(0);
End;

Procedure DrawPageDone;
Begin
  If InstErr <> '' Then
  Begin
    WrapText(CX1, CY1, CX2 - CX1, L('L''installation a '#130'chou'#130' :',
      'Setup failed:', 'Installation fehlgeschlagen:',
      'Installazione non riuscita:', 'La instalaci'#162'n ha fallado:') +
      '|' + InstErr, cRed, True);
    Exit;
  End;
  WrapText(CX1, CY1, CX2 - CX1, L('Pasdows 95 est install'#130' sur le ' +
    'disque dur.|Retirez le CD-ROM du lecteur, puis cliquez sur ' +
    'Red'#130'marrer. Si le CD-ROM reste dans le lecteur, ne touchez ' +
    'aucune touche au d'#130'marrage : le disque dur d'#130'marrera.',
    'Pasdows 95 is installed on the hard disk.|Remove the CD-ROM from ' +
    'the drive, then click Restart. If the CD-ROM stays in the drive, ' +
    'do not press any key at startup: the hard disk will start.',
    'Pasdows 95 ist installiert.|Entfernen Sie die CD-ROM und klicken ' +
    'Sie auf Neu starten. Bleibt die CD-ROM im Laufwerk, keine Taste ' +
    'dr'#129'cken: die Festplatte startet.',
    'Pasdows 95 '#138' installato.|Rimuovere il CD-ROM e fare clic su ' +
    'Riavvia. Se il CD-ROM resta nell''unit'#133', non premere alcun ' +
    'tasto all''avvio: si avvier'#133' il disco rigido.',
    'Pasdows 95 est'#160' instalado.|Retire el CD-ROM y haga clic en ' +
    'Reiniciar. Si el CD-ROM queda en la unidad, no pulse ninguna ' +
    'tecla al iniciar: arrancar'#160' el disco duro.'), cBlack, True);
End;

Function PageTitle : String;
Begin
  Case Page Of
    pgLang : PageTitle := L('Bienvenue', 'Welcome', 'Willkommen',
                            'Benvenuti', 'Bienvenido');
    pgDone :
      If InstErr <> '' Then PageTitle := TxtSetup
      Else PageTitle := L('Installation termin'#130'e',
        'Setup is complete', 'Installation abgeschlossen',
        'Installazione completata', 'Instalaci'#162'n completada');
  Else
    PageTitle := PageName(Page);
  End;
End;

Procedure DrawBackground;
Var I, Y, C : Integer;
Begin
  { degrade bleu (tramage) }
  Bar(0, 0, ScrW - 1, ScrH - 1, cNavy);
  For I := 0 To 7 Do
  Begin
    Y := I * 6;
    Dither(0, Y, ScrW - 1, Y + 5, cBlue, I);
  End;
  BigText(22, 14, 'Pasdows 95', cBlack, 3);
  BigText(18, 10, 'Pasdows 95', cWhite, 3);
  OutBold(300, 30, TxtSetup, cYellow);
  { etapes }
  For I := 0 To PageMax Do
  Begin
    Y := 110 + I * 28;
    If I < Page Then C := cSilver
    Else If I = Page Then C := cYellow
    Else C := cGray;
    If I = Page Then
    Begin
      Arrow(8, Y + 4, 0, cYellow);
      OutBold(18, Y, Fit(PageName(I), 124), C);
    End
    Else OutText(18, Y, Fit(PageName(I), 124), C);
  End;
  OutText(8, ScrH - 22, 'Pasdows 95 - ' + L('version ', 'version ',
          'Version ', 'versione ', 'versi'#162'n ') + '4.00.950', cGray);
End;

Procedure DrawPage;
Begin
  Bar(CX1 - 2, CY1 - 2, CX2 + 2, BtnY1 - 12, cSilver);
  Case Page Of
    pgLang : DrawPageLang;
    pgDisk : DrawPageDisk;
    pgTz : DrawPageTz;
    pgDisp : DrawPageDisp;
    pgComp : DrawPageComp;
    pgReady : DrawPageReady;
    pgCopy : DrawPageCopy;
  Else
    DrawPageDone;
  End;
  Bar(CX1 - 120, BtnY1 - 2, CX2 + 2, BtnY2 + 2, cSilver);
  DrawNav;
End;

Procedure DrawWizard;
Begin
  { fenetre }
  Bar(DX1 + 4, DY1 + 4, DX2 + 4, DY2 + 4, cBlack);
  Raised(DX1, DY1, DX2, DY2, False);
  Bar(DX1 + 3, DY1 + 3, DX2 - 3, DY1 + 20, cNavy);
  DrawIcon(icComputer, DX1 + 5, DY1 + 4, 16);
  OutBold(DX1 + 26, DY1 + 4, Fit(TxtSetup + ' - ' + PageTitle,
          DX2 - DX1 - 40), cWhite);
  { image a gauche }
  Sunken(DX1 + 10, DY1 + 30, CX1 - 14, BtnY1 - 14, cTeal);
  DrawIcon(icComputer, DX1 + 26, DY1 + 70, 64);
  DrawIcon(icCdrom, DX1 + 34, DY1 + 190, 48);
  HLine(DX1 + 10, DX2 - 10, BtnY1 - 9, cGray);
  HLine(DX1 + 10, DX2 - 10, BtnY1 - 8, cWhite);
  DrawPage;
End;

Procedure RedrawAll;
Begin
  HideCursor;
  FullClip;
  DrawBackground;
  DrawWizard;
  ShowCursor;
End;

Procedure RedrawPage;
Begin
  HideCursor;
  FullClip;
  DrawPage;
  ShowCursor;
End;
{ ================================================================== }
{ Evenements                                                         }
{ ================================================================== }

Function NextEvent(Var E : TEvent) : Boolean;
Begin
  PollInput;
  If (MouseX <> LastMX) Or (MouseY <> LastMY) Then
  Begin
    HideCursor;
    ShowCursor;
    LastMX := MouseX; LastMY := MouseY;
  End;
  If EvHead = EvTail Then NextEvent := False
  Else
  Begin
    E := EvQ[EvHead];
    EvHead := (EvHead + 1) Mod 32;
    NextEvent := True;
  End;
End;

{ Boite de message modale ; YesNo : boutons Oui et Non (sinon OK).
  Retourne True pour OK ou Oui }
Function MsgBox(Const Title, Text : String; YesNo, Warn : Boolean)
  : Boolean;
Var X1, Y1, X2, Y2, N, I, BX, Hit, Pr : Integer; E : TEvent;
    T : String;
Begin
  X1 := 130; X2 := 510;
  N := WrapText(0, 0, X2 - X1 - 76, Text, cBlack, False);
  Y1 := 170 - N * 8; Y2 := Y1 + 92 + N * 16;
  HideCursor;
  FullClip;
  Bar(X1 + 4, Y1 + 4, X2 + 4, Y2 + 4, cBlack);
  Raised(X1, Y1, X2, Y2, False);
  Bar(X1 + 3, Y1 + 3, X2 - 3, Y1 + 20, cNavy);
  OutBold(X1 + 8, Y1 + 4, Fit(Title, X2 - X1 - 16), cWhite);
  If Warn Then DrawIcon(icWarn, X1 + 14, Y1 + 32, 32)
  Else DrawIcon(icInfo, X1 + 14, Y1 + 32, 32);
  WrapText(X1 + 60, Y1 + 34, X2 - X1 - 76, Text, cBlack, True);
  Pr := -1;
  Repeat
    For I := 0 To Ord(YesNo) Do
    Begin
      If YesNo Then BX := (X1 + X2) Div 2 - 92 + I * 100
      Else BX := (X1 + X2) Div 2 - 42;
      If Not YesNo Then T := 'OK'
      Else If I = 0 Then T := TxtYes
      Else T := TxtNo;
      PushButton(BX, Y2 - 32, BX + 84, Y2 - 10, T, Pr = I, I = 0);
    End;
    ShowCursor;
    Hit := -2;
    Repeat
      If NextEvent(E) Then
      Begin
        If E.Kind = evKey Then
        Begin
          If E.Sc = scEnter Then Hit := 0
          Else If (E.Sc = scEsc) And YesNo Then Hit := 1
          Else If E.Sc = scEsc Then Hit := 0;
        End
        Else If (E.Kind = evDown) Or (E.Kind = evUp) Then
        Begin
          For I := 0 To Ord(YesNo) Do
          Begin
            If YesNo Then BX := (X1 + X2) Div 2 - 92 + I * 100
            Else BX := (X1 + X2) Div 2 - 42;
            If InRect(E.X, E.Y, BX, Y2 - 32, BX + 84, Y2 - 10) Then
            Begin
              If E.Kind = evDown Then
              Begin
                Pr := I;
                Hit := -1;
              End
              Else If Pr = I Then Hit := I;
            End;
          End;
          If (E.Kind = evUp) And (Hit = -2) And (Pr >= 0) Then
          Begin
            Pr := -1;
            Hit := -1;
          End;
        End;
      End;
    Until Hit <> -2;
    HideCursor;
  Until Hit >= 0;
  MsgBox := Hit = 0;
  RedrawAll;
End;

{ ================================================================== }
{ Installation : partition, formatage FAT32, copie des fichiers      }
{ ================================================================== }

Procedure SetStatus(Const S : String);
Begin
  StatusText := S;
  DrawStatus;
End;

Procedure PutW(Sg, Ofs, V : Word);
Begin
  MemW[Sg:Ofs] := V;
End;

Procedure PutL(Sg, Ofs : Word; V : LongInt);
Begin
  MemW[Sg:Ofs] := Word(V And $FFFF);
  MemW[Sg:Ofs + 2] := Word((V Shr 16) And $FFFF);
End;

Procedure ZeroSeg(Sg : Word; N : Word);
Var I : Word;
Begin
  For I := 0 To N Div 2 - 1 Do MemW[Sg:I * 2] := 0;
End;

{ Adresse CHS d'un secteur (FE FF FF au-dela de 1024 cylindres) }
Procedure PutChs(Ofs : Word; Lba : LongInt);
Var H, S, C : LongInt;
Begin
  H := DiskHeads[DiskSel]; S := DiskSpt[DiskSel];
  C := Lba Div (H * S);
  If C > 1023 Then
  Begin
    Mem[SecSeg:Ofs] := $FE; Mem[SecSeg:Ofs + 1] := $FF;
    Mem[SecSeg:Ofs + 2] := $FF;
    Exit;
  End;
  Mem[SecSeg:Ofs] := (Lba Mod (H * S)) Div S;
  Mem[SecSeg:Ofs + 1] := ((Lba Mod S) + 1) Or ((C Shr 2) And $C0);
  Mem[SecSeg:Ofs + 2] := C And $FF;
End;

Function PartType : Byte;
Begin
  Case FsKind Of
    0 : PartType := $0E;                         { FAT16 (LBA) }
    1 : PartType := $0C;                         { FAT32 (LBA) }
  Else
    PartType := $07;                             { NTFS }
  End;
End;

{ MBR : code de Pasdows et table des partitions }
Function WriteMbr : Boolean;
Var I : Integer; Ofs : Word; T : Word;
Begin
  WriteMbr := False;
  If PartMode = 0 Then
  Begin
    ZeroSeg(SecSeg, 512);
    PartLba := 2048;
    PartSecs := PartMb * 2048;
    If PartLba + PartSecs > DiskSecs[DiskSel] Then
      PartSecs := DiskSecs[DiskSel] - PartLba;
    T := Ticks;
    MemW[SecSeg:440] := T; MemW[SecSeg:442] := T Xor $5A95;
    Ofs := 446;
    Mem[SecSeg:Ofs] := $80;
    PutChs(Ofs + 1, PartLba);
    Mem[SecSeg:Ofs + 4] := PartType;
    PutChs(Ofs + 5, PartLba + PartSecs - 1);
    PutL(SecSeg, Ofs + 8, PartLba);
    PutL(SecSeg, Ofs + 12, PartSecs);
  End
  Else
  Begin
    If Not HdIo(Drv, False, 0, SecSeg, 1) Then Exit;
    For I := 0 To 3 Do
    Begin
      Ofs := 446 + I * 16;
      If I = PExist Then
      Begin
        Mem[SecSeg:Ofs] := $80;
        Mem[SecSeg:Ofs + 4] := PartType;
        PartLba := GetD(SecSeg, Ofs + 8);
        PartSecs := GetD(SecSeg, Ofs + 12);
      End
      Else Mem[SecSeg:Ofs] := 0;
    End;
  End;
  For I := 0 To 439 Do Mem[SecSeg:I] := MbrCode[I];
  MemW[SecSeg:510] := $AA55;
  WriteMbr := HdIo(Drv, True, 0, SecSeg, 1);
End;

Function ClusLba(C : LongInt) : LongInt;
Begin
  ClusLba := DataLba + (C - 2) * Spc;
End;

{ Reserver N octets de grappes contigues ; premiere grappe (0 si vide) }
Function AllocBytes(N : LongInt) : LongInt;
Var K : LongInt;
Begin
  If N <= 0 Then
  Begin
    AllocBytes := 0;
    Exit;
  End;
  K := (N + LongInt(Spc) * 512 - 1) Div (LongInt(Spc) * 512);
  AllocBytes := NextClus;
  NextClus := NextClus + K;
  If EndCnt < 64 Then
  Begin
    EndClus[EndCnt] := NextClus - 1;
    Inc(EndCnt);
  End;
End;

Procedure FsInfo(Free0, Next0 : LongInt);
Begin
  ZeroSeg(SecSeg, 512);
  PutL(SecSeg, 0, $41615252);
  PutL(SecSeg, 484, $61417272);
  PutL(SecSeg, 488, Free0);
  PutL(SecSeg, 492, Next0);
  PutL(SecSeg, 508, $AA550000);
End;

{ Formater la partition en FAT32 (formatage rapide) }
{ Formatage FAT16 : 1 secteur reserve, 512 entrees de racine (32
  secteurs), deux FAT 16 bits }
Function FormatFat16 : Boolean;
Var Mb, T1, T2, S, N, Tot : LongInt; I : Integer; T : Word; Tx : String;
Begin
  FormatFat16 := False;
  Mb := PartSecs Div 2048;
  If Mb <= 16 Then Spc := 2
  Else If Mb <= 128 Then Spc := 4
  Else If Mb <= 256 Then Spc := 8
  Else If Mb <= 512 Then Spc := 16
  Else If Mb <= 1024 Then Spc := 32
  Else Spc := 64;
  T1 := PartSecs - 33;
  T2 := 256 * LongInt(Spc) + 2;
  FatSz := (T1 + T2 - 1) Div T2;
  FatLba := PartLba + 1;
  Root16Lba := FatLba + 2 * FatSz;
  DataLba := Root16Lba + 32;
  TotClus := (PartSecs - 33 - 2 * FatSz) Div Spc;
  If (TotClus < 4085) Or (TotClus > 65524) Then
  Begin
    InstErr := L('Taille de partition non permise pour FAT16.',
                 'Partition size not allowed for FAT16.',
                 'Partitionsgr'#148#225'e f'#129'r FAT16 nicht erlaubt.',
                 'Dimensione non consentita per FAT16.',
                 'Tama'#164'o no permitido para FAT16.');
    Exit;
  End;
  ZeroSeg(SecSeg, 512);
  Mem[SecSeg:0] := $EB; Mem[SecSeg:1] := $3C; Mem[SecSeg:2] := $90;
  Tx := 'PASDOWS ';
  For I := 1 To 8 Do Mem[SecSeg:2 + I] := Ord(Tx[I]);
  PutW(SecSeg, 11, 512);
  Mem[SecSeg:13] := Spc;
  PutW(SecSeg, 14, 1);
  Mem[SecSeg:16] := 2;
  PutW(SecSeg, 17, 512);
  Tot := PartSecs;
  If Tot < 65536 Then PutW(SecSeg, 19, Tot) Else PutL(SecSeg, 32, Tot);
  Mem[SecSeg:21] := $F8;
  PutW(SecSeg, 22, FatSz);
  PutW(SecSeg, 24, DiskSpt[DiskSel]);
  PutW(SecSeg, 26, DiskHeads[DiskSel]);
  PutL(SecSeg, 28, PartLba);
  Mem[SecSeg:36] := $80;
  Mem[SecSeg:38] := $29;
  T := Ticks;
  PutW(SecSeg, 39, T); PutW(SecSeg, 41, DosDate);
  Tx := 'PASDOWS95  ';
  For I := 1 To 11 Do Mem[SecSeg:42 + I] := Ord(Tx[I]);
  Tx := 'FAT16   ';
  For I := 1 To 8 Do Mem[SecSeg:53 + I] := Ord(Tx[I]);
  For I := 0 To 447 Do Mem[SecSeg:62 + I] := Vbr16Code[I];
  MemW[SecSeg:510] := $AA55;
  If Not HdIo(Drv, True, PartLba, SecSeg, 1) Then Exit;
  { FAT et racine : zeros }
  ZeroSeg(FatBufSeg, 32768);
  S := 0;
  While S < 2 * FatSz + 32 Do
  Begin
    N := 2 * FatSz + 32 - S;
    If N > 64 Then N := 64;
    If Not HdIo(Drv, True, FatLba + S, FatBufSeg, N) Then Exit;
    S := S + N;
    DoneBytes := DoneBytes + N * 64;
    DrawStatus;
  End;
  NextClus := 2; EndCnt := 0;
  FormatFat16 := True;
End;

Function FormatFat32 : Boolean;
Var Mb, T1, T2, S, N : LongInt; I : Integer; T : Word; Tx : String;
Begin
  FormatFat32 := False;
  Mb := PartSecs Div 2048;
  If Mb <= 260 Then Spc := 1
  Else If Mb <= 8192 Then Spc := 8
  Else If Mb <= 16384 Then Spc := 16
  Else If Mb <= 32768 Then Spc := 32
  Else Spc := 64;
  T1 := PartSecs - 32;
  T2 := (256 * LongInt(Spc) + 2) Div 2;
  FatSz := (T1 + T2 - 1) Div T2;
  FatLba := PartLba + 32;
  DataLba := FatLba + 2 * FatSz;
  TotClus := (PartSecs - 32 - 2 * FatSz) Div Spc;
  If TotClus < 65525 Then
  Begin
    InstErr := L('Partition trop petite pour FAT32.',
                 'Partition too small for FAT32.',
                 'Partition zu klein f'#129'r FAT32.',
                 'Partizione troppo piccola per FAT32.',
                 'Partici'#162'n demasiado peque'#164'a para FAT32.');
    Exit;
  End;
  { secteur d'amorce }
  ZeroSeg(SecSeg, 512);
  Mem[SecSeg:0] := $EB; Mem[SecSeg:1] := $58; Mem[SecSeg:2] := $90;
  Tx := 'PASDOWS ';
  For I := 1 To 8 Do Mem[SecSeg:2 + I] := Ord(Tx[I]);
  PutW(SecSeg, 11, 512);
  Mem[SecSeg:13] := Spc;
  PutW(SecSeg, 14, 32);
  Mem[SecSeg:16] := 2;
  Mem[SecSeg:21] := $F8;
  PutW(SecSeg, 24, DiskSpt[DiskSel]);
  PutW(SecSeg, 26, DiskHeads[DiskSel]);
  PutL(SecSeg, 28, PartLba);
  PutL(SecSeg, 32, PartSecs);
  PutL(SecSeg, 36, FatSz);
  PutL(SecSeg, 44, 2);
  PutW(SecSeg, 48, 1);
  PutW(SecSeg, 50, 6);
  Mem[SecSeg:64] := $80;
  Mem[SecSeg:66] := $29;
  T := Ticks;
  PutW(SecSeg, 67, T); PutW(SecSeg, 69, DosDate);
  Tx := 'PASDOWS95  ';
  For I := 1 To 11 Do Mem[SecSeg:70 + I] := Ord(Tx[I]);
  Tx := 'FAT32   ';
  For I := 1 To 8 Do Mem[SecSeg:81 + I] := Ord(Tx[I]);
  For I := 0 To 419 Do Mem[SecSeg:90 + I] := VbrCode[I];
  MemW[SecSeg:510] := $AA55;
  If Not HdIo(Drv, True, PartLba, SecSeg, 1) Then Exit;
  If Not HdIo(Drv, True, PartLba + 6, SecSeg, 1) Then Exit;
  FsInfo(-1, 2);
  If Not HdIo(Drv, True, PartLba + 1, SecSeg, 1) Then Exit;
  If Not HdIo(Drv, True, PartLba + 7, SecSeg, 1) Then Exit;
  { autres secteurs reserves et les deux FAT : zeros }
  ZeroSeg(FatBufSeg, 32768);
  For I := 2 To 31 Do
    If (I <> 6) And (I <> 7) Then
      If Not HdIo(Drv, True, PartLba + I, FatBufSeg, 1) Then Exit;
  S := 0;
  While S < 2 * FatSz Do
  Begin
    N := 2 * FatSz - S;
    If N > 64 Then N := 64;
    If Not HdIo(Drv, True, FatLba + S, FatBufSeg, N) Then Exit;
    S := S + N;
    DoneBytes := DoneBytes + N * 64;
    If (S And 1023) = 0 Then DrawStatus;
  End;
  NextClus := 2; EndCnt := 0;
  FormatFat32 := True;
End;

{ Nom 8.3 sur 11 caracteres ('VMM32.VXD' -> 'VMM32   VXD') }
Function Name83(Const N : String) : String;
Var P : Integer; B, E : String;
Begin
  P := Pos('.', N);
  If P > 0 Then
  Begin
    B := Copy(N, 1, P - 1); E := Copy(N, P + 1, 3);
  End
  Else
  Begin
    B := N; E := '';
  End;
  B := Copy(B, 1, 8);
  While Length(B) < 8 Do B := B + ' ';
  While Length(E) < 3 Do E := E + ' ';
  Name83 := B + E;
End;

Procedure AddEnt(InRoot : Boolean; Const N : String; A : Byte;
                 C, Sz : LongInt);
Begin
  If InRoot Then
  Begin
    If RootN > 23 Then Exit;
    RootEnt[RootN].Name := Name83(N); RootEnt[RootN].Attr := A;
    RootEnt[RootN].Clus := C; RootEnt[RootN].Size := Sz;
    Inc(RootN);
  End
  Else
  Begin
    If WinN > 23 Then Exit;
    WinEnt[WinN].Name := Name83(N); WinEnt[WinN].Attr := A;
    WinEnt[WinN].Clus := C; WinEnt[WinN].Size := Sz;
    Inc(WinN);
  End;
End;

{ Ecrire Bytes octets de CopySeg (ou du CD) a partir de la grappe C }
Function WriteBuf(Lba : LongInt; Bytes : Word) : Boolean;
Var I, Secs : Word;
Begin
  Secs := (Bytes + 511) Div 512;
  For I := Bytes To Secs * 512 - 1 Do Mem[CopySeg:I] := 0;
  WriteBuf := HdIo(Drv, True, Lba, CopySeg, Secs);
End;

{ Copier le fichier Idx du CD-ROM vers C:\ (InRoot) ou C:\WINDOWS }
Function CopyCdFile(Idx : Integer; InRoot : Boolean; A : Byte) : Boolean;
Var C, Lba, Rem, K, Bytes : LongInt; N : Integer;
Begin
  CopyCdFile := False;
  SetStatus(L('Copie de ', 'Copying ', 'Kopieren: ', 'Copia di ',
              'Copiando ') + CdFiles[Idx].Name + '...');
  Rem := CdFiles[Idx].Size;
  C := AllocBytes(Rem);
  Lba := ClusLba(C);
  K := 0;
  While Rem > 0 Do
  Begin
    N := 16;
    If Rem < 32768 Then N := (Rem + 2047) Div 2048;
    If Not CdReadN(CdFiles[Idx].Lba + K, CopySeg, N) Then
    Begin
      InstErr := L('Erreur de lecture du CD-ROM : ', 'CD-ROM read error: ',
                   'CD-ROM-Lesefehler: ', 'Errore di lettura del CD-ROM: ',
                   'Error de lectura del CD-ROM: ') + CdFiles[Idx].Name;
      Exit;
    End;
    Bytes := LongInt(N) * 2048;
    If Bytes > Rem Then Bytes := Rem;
    If Not WriteBuf(Lba, Bytes) Then Exit;
    Lba := Lba + (Bytes + 511) Div 512;
    K := K + N;
    Rem := Rem - Bytes;
    DoneBytes := DoneBytes + Bytes;
    DrawStatus;
  End;
  AddEnt(InRoot, CdFiles[Idx].Name, A, C, CdFiles[Idx].Size);
  CopyCdFile := True;
End;

{ Texte produit dans CopySeg }
Procedure GenLine(Const S : String);
Var I : Integer;
Begin
  For I := 1 To Length(S) Do
  Begin
    Mem[CopySeg:GenLen] := Ord(S[I]);
    Inc(GenLen);
  End;
  Mem[CopySeg:GenLen] := 13; Mem[CopySeg:GenLen + 1] := 10;
  GenLen := GenLen + 2;
End;

Function WriteGen(Const N : String; A : Byte) : Boolean;
Var C : LongInt;
Begin
  SetStatus(L('Cr'#130'ation de ', 'Creating ', 'Erstellen: ',
              'Creazione di ', 'Creando ') + 'C:\' + N + '...');
  C := AllocBytes(GenLen);
  WriteGen := WriteBuf(ClusLba(C), GenLen);
  AddEnt(True, N, A, C, GenLen);
End;

Procedure GenMsdosSys;
Begin
  GenLen := 0;
  GenLine(';MSDOS.SYS de Pasdows 95 (lu par IO.SYS au demarrage)');
  GenLine(';BootMenu=1  : afficher le menu de demarrage (sinon touche F8)');
  GenLine(';BootGUI=0   : demarrer en mode invite de commandes seulement');
  GenLine(';Logo=0      : ne pas afficher l''ecran d''accueil');
  GenLine(';BootDelay=n : secondes d''attente de la touche F8');
  GenLine('[Paths]');
  GenLine('WinDir=C:\WINDOWS');
  GenLine('WinBootDir=C:\WINDOWS');
  GenLine('HostWinBootDrv=C');
  GenLine('');
  GenLine('[Options]');
  GenLine('BootMenu=0');
  GenLine('BootGUI=1');
  GenLine('Logo=1');
  GenLine('BootDelay=2');
End;

Procedure GenConfigSys;
Begin
  GenLen := 0;
  GenLine('REM CONFIG.SYS de Pasdows 95 (installe sur le disque dur)');
  GenLine('FILES=40');
  GenLine('BUFFERS=30');
  GenLine('LASTDRIVE=Z');
End;

Procedure GenAutoexec;
Begin
  GenLen := 0;
  GenLine('@ECHO OFF');
  GenLine('REM AUTOEXEC.BAT de Pasdows 95 (installe sur le disque dur)');
  GenLine('REM Langue de l''interface : FR (francais), EN (anglais),');
  GenLine('REM GR (allemand), IT (italien) ou SP (espagnol).');
  GenLine('SET LANGUAGE=' + LangCode);
  GenLine('SET PATH=C:\WINDOWS;C:\');
  GenLine('SET TEMP=C:\WINDOWS\TEMP');
  GenLine('SET PROMPT=$P$G');
End;

Procedure PutDirEnt(Sg, Ofs : Word; Const N : String; A : Byte;
                    C, Sz : LongInt);
Var I : Integer;
Begin
  For I := 1 To 11 Do Mem[Sg:Ofs + I - 1] := Ord(N[I]);
  Mem[Sg:Ofs + 11] := A;
  PutW(Sg, Ofs + 14, DosTime); PutW(Sg, Ofs + 16, DosDate);
  PutW(Sg, Ofs + 18, DosDate);
  PutW(Sg, Ofs + 20, Word((C Shr 16) And $FFFF));
  PutW(Sg, Ofs + 22, DosTime); PutW(Sg, Ofs + 24, DosDate);
  PutW(Sg, Ofs + 26, Word(C And $FFFF));
  PutL(Sg, Ofs + 28, Sz);
End;

{ Ecrire les repertoires (racine en grappe 2, WINDOWS en grappe RC + 1) }
Function WriteDirs(RootC, RootK, WinC, WinK : LongInt) : Boolean;
Var I : Integer; Ofs : Word;
Begin
  WriteDirs := False;
  ZeroSeg(FatBufSeg, 32768);
  PutDirEnt(FatBufSeg, 0, 'PASDOWS95  ', $08, 0, 0);
  For I := 0 To RootN - 1 Do
    PutDirEnt(FatBufSeg, (I + 1) * 32, RootEnt[I].Name, RootEnt[I].Attr,
              RootEnt[I].Clus, RootEnt[I].Size);
  If Fat16 Then
  Begin
    If Not HdIo(Drv, True, Root16Lba, FatBufSeg, 32) Then Exit;
  End
  Else If Not HdIo(Drv, True, ClusLba(RootC), FatBufSeg, RootK * Spc) Then
    Exit;
  ZeroSeg(FatBufSeg, 32768);
  PutDirEnt(FatBufSeg, 0, '.          ', $10, WinC, 0);
  PutDirEnt(FatBufSeg, 32, '..         ', $10, 0, 0);
  For I := 0 To WinN - 1 Do
  Begin
    Ofs := (I + 2) * 32;
    PutDirEnt(FatBufSeg, Ofs, WinEnt[I].Name, WinEnt[I].Attr,
              WinEnt[I].Clus, WinEnt[I].Size);
  End;
  WriteDirs := HdIo(Drv, True, ClusLba(WinC), FatBufSeg, WinK * Spc);
End;

{ Les deux FAT : chaines contigues des grappes 2 a NextClus - 1 }
Function WriteFats16 : Boolean;
Var S, NSec, E, V : LongInt; J, K, Chunk : Integer;
Begin
  WriteFats16 := False;
  NSec := (NextClus * 2 + 511) Div 512;
  S := 0; K := 0;
  While S < NSec Do
  Begin
    Chunk := 64;
    If NSec - S < 64 Then Chunk := NSec - S;
    For J := 0 To Chunk * 256 - 1 Do
    Begin
      E := S * 256 + J;
      If E = 0 Then V := $FFF8
      Else If E = 1 Then V := $FFFF
      Else If E >= NextClus Then V := 0
      Else
      Begin
        While (K < EndCnt) And (EndClus[K] < E) Do Inc(K);
        If (K < EndCnt) And (EndClus[K] = E) Then V := $FFFF
        Else V := E + 1;
      End;
      MemW[FatBufSeg:J * 2] := Word(V);
    End;
    If Not HdIo(Drv, True, FatLba + S, FatBufSeg, Chunk) Then Exit;
    If Not HdIo(Drv, True, FatLba + FatSz + S, FatBufSeg, Chunk) Then Exit;
    S := S + Chunk;
  End;
  WriteFats16 := True;
End;

Function WriteFats : Boolean;
Var S, NSec, E, V : LongInt; J, K, Chunk : Integer;
Begin
  WriteFats := False;
  If Fat16 Then
  Begin
    WriteFats := WriteFats16;
    Exit;
  End;
  NSec := (NextClus * 4 + 511) Div 512;
  S := 0; K := 0;
  While S < NSec Do
  Begin
    Chunk := 64;
    If NSec - S < 64 Then Chunk := NSec - S;
    For J := 0 To Chunk * 128 - 1 Do
    Begin
      E := S * 128 + J;
      If E = 0 Then V := $0FFFFFF8
      Else If E = 1 Then V := $0FFFFFFF
      Else If E >= NextClus Then V := 0
      Else
      Begin
        While (K < EndCnt) And (EndClus[K] < E) Do Inc(K);
        If (K < EndCnt) And (EndClus[K] = E) Then V := $0FFFFFFF
        Else V := E + 1;
      End;
      PutL(FatBufSeg, J * 4, V);
    End;
    If Not HdIo(Drv, True, FatLba + S, FatBufSeg, Chunk) Then Exit;
    If Not HdIo(Drv, True, FatLba + FatSz + S, FatBufSeg, Chunk) Then Exit;
    S := S + Chunk;
  End;
  WriteFats := True;
End;

Procedure SaveCmos;
Var V : Byte;
Begin
  V := TzSel + 1;
  If Not TzDst Then V := V Or $80;
  CmosWrite($79, V);
  CmosWrite($7A, DispB[DispSel]);
  CmosWrite($7C, DispW[DispSel] Div 8);
  CmosWrite($7D, DispH[DispSel] Div 8);
  CmosWrite($7B, $5A);
End;

Function DiskErr : String;
Begin
  DiskErr := L('Erreur d'''#130'criture sur le disque dur.',
               'Hard disk write error.', 'Schreibfehler auf der Festplatte.',
               'Errore di scrittura sul disco rigido.',
               'Error de escritura en el disco duro.');
End;

{ ================================================================== }
{ Formatage NTFS 3.1 et copie des fichiers                           }
{ ================================================================== }

{ Clusters de 4 Ko, enregistrements de 1 Ko, blocs d'index de 4 Ko.
  Disposition : $Boot (clusters 0-1), $MFT (64 enregistrements), bitmap
  de la MFT, $LogFile (rempli de FFh), $AttrDef, $UpCase, $Secure:$SDS,
  $Bitmap, blocs d'index de la racine et de C:\WINDOWS, fichiers ;
  $MFTMirr au milieu du volume, copie du secteur d'amorce au dernier
  secteur. Les 64 enregistrements sont construits en MftSeg puis ecrits
  en une fois (avec les correctifs de secteurs). }

{ FILETIME (4 mots) = A * M + C }
Procedure Ft64Mul(M : Word; C : LongInt);
Var I : Integer; T : LongInt;
Begin
  For I := 0 To 3 Do
  Begin
    T := LongInt(NtFT[I]) * M + (C And $FFFF);
    C := (C Shr 16) + (T Shr 16);
    NtFT[I] := T And $FFFF;
  End;
End;

{ Date et heure de l'horloge en FILETIME (centaines de ns depuis 1601) }
Procedure NtNow;
Const Cum : Array[1..12] Of Integer = (0, 31, 59, 90, 120, 151, 181, 212,
                                       243, 273, 304, 334);
Var H, M, S, Y, Mo, D : Integer; Y1, Days : LongInt; I : Integer;
Begin
  RtcTime(H, M, S); RtcDate(Y, Mo, D);
  Y1 := Y - 1601;
  Days := Y1 * 365 + Y1 Div 4 - Y1 Div 100 + Y1 Div 400 + Cum[Mo] + D - 1;
  If (Mo > 2) And ((Y Mod 4 = 0) And ((Y Mod 100 <> 0) Or (Y Mod 400 = 0)))
  Then Inc(Days);
  For I := 0 To 3 Do NtFT[I] := 0;
  NtFT[0] := Days And $FFFF; NtFT[1] := Days Shr 16;
  Ft64Mul(1350, 0); Ft64Mul(64, LongInt(H) * 3600 + M * 60 + S);
  Ft64Mul(10000, 0); Ft64Mul(1000, 0);
End;

Procedure PutFt(Sg, Ofs : Word);
Var I : Integer;
Begin
  For I := 0 To 3 Do MemW[Sg:Ofs + I * 2] := NtFT[I];
End;

Function SigBytes(V : LongInt) : Integer;
Begin
  If (V >= -128) And (V < 128) Then SigBytes := 1
  Else If (V >= -32768) And (V < 32768) Then SigBytes := 2
  Else If (V >= -8388608) And (V < 8388608) Then SigBytes := 3
  Else SigBytes := 4;
End;

{ ----- construction des enregistrements (en MftSeg) ----- }

Procedure RInit(N : LongInt; Seq, Flags, Links : Word);
Var I : Word;
Begin
  RBase := Word(N) * 1024;
  For I := 0 To 511 Do MemW[MftSeg:RBase + I * 2] := 0;
  PutL(MftSeg, RBase, $454C4946);
  PutW(MftSeg, RBase + 4, $30); PutW(MftSeg, RBase + 6, 3);
  PutW(MftSeg, RBase + $10, Seq); PutW(MftSeg, RBase + $12, Links);
  PutW(MftSeg, RBase + $14, $38); PutW(MftSeg, RBase + $16, Flags);
  PutL(MftSeg, RBase + $1C, 1024);
  PutL(MftSeg, RBase + $2C, N);
  RPos := $38; RId := 0;
End;

Procedure RHdr(Typ : LongInt; Const Nm : String; Len : Word;
               NonRes : Boolean; HdrLen : Word);
Var I : Integer; P : Word;
Begin
  P := RBase + RPos;
  PutL(MftSeg, P, Typ); PutL(MftSeg, P + 4, Len);
  Mem[MftSeg:P + 8] := Ord(NonRes);
  Mem[MftSeg:P + 9] := Length(Nm);
  PutW(MftSeg, P + 10, HdrLen);
  PutW(MftSeg, P + 14, RId);
  For I := 1 To Length(Nm) Do
    PutW(MftSeg, P + HdrLen + (I - 1) * 2, Ord(Nm[I]));
End;

{ Attribut resident : valeur en ValSeg:0000 (VLen octets) }
Procedure RRes(Typ : LongInt; Const Nm : String; VLen : Word; Ix : Byte);
Var VO, Len, I : Word; P : Word;
Begin
  VO := (($18 + Length(Nm) * 2) + 7) And $FFF8;
  Len := (VO + VLen + 7) And $FFF8;
  RHdr(Typ, Nm, Len, False, $18);
  P := RBase + RPos;
  PutL(MftSeg, P + $10, VLen); PutW(MftSeg, P + $14, VO);
  Mem[MftSeg:P + $16] := Ix;
  { (VLen = 0 : pas de copie ; VLen - 1 deborderait en Word) }
  If VLen > 0 Then
    For I := 0 To VLen - 1 Do Mem[MftSeg:P + VO + I] := Mem[ValSeg:I];
  RPos := RPos + Len; Inc(RId);
End;

{ Attribut non resident a un run (Lcn < 0 : creux) ; tailles en octets
  (Hi : poids forts) }
Procedure RNonRes(Typ : LongInt; Const Nm : String; Lcn, Clus : LongInt;
                  AllocLo, AllocHi, SizeLo, SizeHi : LongInt);
Var RO, Len, P, Q : Word; NL, NO, K : Integer;
Begin
  RO := (($40 + Length(Nm) * 2) + 7) And $FFF8;
  NL := SigBytes(Clus);
  If Lcn < 0 Then NO := 0 Else NO := SigBytes(Lcn);
  Len := (RO + 1 + NL + NO + 1 + 7) And $FFF8;
  RHdr(Typ, Nm, Len, True, $40);
  P := RBase + RPos;
  PutL(MftSeg, P + $18, Clus - 1);
  PutW(MftSeg, P + $20, RO);
  PutL(MftSeg, P + $28, AllocLo); PutL(MftSeg, P + $2C, AllocHi);
  PutL(MftSeg, P + $30, SizeLo); PutL(MftSeg, P + $34, SizeHi);
  PutL(MftSeg, P + $38, SizeLo); PutL(MftSeg, P + $3C, SizeHi);
  Q := P + RO;
  Mem[MftSeg:Q] := NL Or (NO Shl 4);
  For K := 0 To NL - 1 Do Mem[MftSeg:Q + 1 + K] := (Clus Shr (8 * K)) And $FF;
  For K := 0 To NO - 1 Do
    Mem[MftSeg:Q + 1 + NL + K] := (Lcn Shr (8 * K)) And $FF;
  RPos := RPos + Len; Inc(RId);
End;

Procedure RDone;
Begin
  PutL(MftSeg, RBase + RPos, -1); PutL(MftSeg, RBase + RPos + 4, 0);
  PutL(MftSeg, RBase + $18, RPos + 8);
  PutW(MftSeg, RBase + $28, RId);
End;

{ $STANDARD_INFORMATION en ValSeg ; longueur }
Function VSi(Fl, SecId : LongInt; Long : Boolean) : Word;
Var I : Integer;
Begin
  For I := 0 To 35 Do MemW[ValSeg:I * 2] := 0;
  For I := 0 To 3 Do PutFt(ValSeg, I * 8);
  PutL(ValSeg, $20, Fl);
  PutL(ValSeg, $34, SecId);
  If Long Then VSi := 72 Else VSi := 48;
End;

{ $FILE_NAME (aussi cle d'index) en Sg:Ofs ; longueur }
Function VFn(Sg, Ofs : Word; Parent : LongInt; PSeq : Word;
             AllocLo, SizeLo, Fl : LongInt; Const Nm : String;
             Ns : Byte) : Word;
Var I : Integer;
Begin
  For I := 0 To 32 + Length(Nm) Do MemW[Sg:Ofs + I * 2] := 0;
  PutL(Sg, Ofs, Parent); PutW(Sg, Ofs + 6, PSeq);
  For I := 0 To 3 Do PutFt(Sg, Ofs + 8 + I * 8);
  PutL(Sg, Ofs + $28, AllocLo); PutL(Sg, Ofs + $30, SizeLo);
  PutL(Sg, Ofs + $38, Fl);
  Mem[Sg:Ofs + $40] := Length(Nm); Mem[Sg:Ofs + $41] := Ns;
  For I := 1 To Length(Nm) Do PutW(Sg, Ofs + $42 + (I - 1) * 2, Ord(Nm[I]));
  VFn := $42 + Length(Nm) * 2;
End;

{ ----- entrees des repertoires ----- }

Procedure KAdd(Rec, Seq, Parent, PSeq, AllocLo, SizeLo, Fl : LongInt;
               Const Nm : String);
Begin
  If KN > 39 Then Exit;
  KRec[KN] := Rec; KSeq[KN] := Seq; KPar[KN] := Parent; KPSeq[KN] := PSeq;
  KAll[KN] := AllocLo; KSiz[KN] := SizeLo; KFl[KN] := Fl; KNm[KN] := Nm;
  Inc(KN);
End;

{ Ordre $I30 : majuscules puis longueur puis casse exacte }
Function KLess(A, B : Integer) : Boolean;
Var I, N : Integer; CA, CB : Char;
Begin
  N := Length(KNm[A]);
  If Length(KNm[B]) < N Then N := Length(KNm[B]);
  For I := 1 To N Do
  Begin
    CA := UpCase(KNm[A][I]); CB := UpCase(KNm[B][I]);
    If CA <> CB Then
    Begin
      KLess := CA < CB;
      Exit;
    End;
  End;
  If Length(KNm[A]) <> Length(KNm[B]) Then
  Begin
    KLess := Length(KNm[A]) < Length(KNm[B]);
    Exit;
  End;
  KLess := KNm[A] < KNm[B];
End;

Function NsOf(Const Nm : String) : Byte;
Begin
  If UpStr(Nm) = Nm Then NsOf := 3 Else NsOf := 1;
End;

{ Entrees triees de K* en Sg:Ofs (avec l'entree de fin) ; longueur }
Function KPut(Sg, Ofs : Word) : Word;
Var Ord0 : Array[0..39] Of Integer; I, J, T, K : Integer; P, KL, L : Word;
Begin
  For I := 0 To KN - 1 Do Ord0[I] := I;
  For I := 1 To KN - 1 Do
  Begin
    J := I;
    While (J > 0) And KLess(Ord0[J], Ord0[J - 1]) Do
    Begin
      T := Ord0[J]; Ord0[J] := Ord0[J - 1]; Ord0[J - 1] := T;
      Dec(J);
    End;
  End;
  P := Ofs;
  For I := 0 To KN - 1 Do
  Begin
    K := Ord0[I];
    KL := VFn(Sg, P + 16, KPar[K], KPSeq[K], KAll[K], KSiz[K], KFl[K],
              KNm[K], NsOf(KNm[K]));
    L := (16 + KL + 7) And $FFF8;
    PutL(Sg, P, KRec[K]); PutW(Sg, P + 4, 0); PutW(Sg, P + 6, KSeq[K]);
    PutW(Sg, P + 8, L); PutW(Sg, P + 10, KL); PutL(Sg, P + 12, 0);
    P := P + L;
  End;
  For I := 0 To 7 Do MemW[Sg:P + I * 2] := 0;
  PutW(Sg, P + 8, 16); PutL(Sg, P + 12, 2);
  KPut := P + 16 - Ofs;
End;

{ $INDEX_ROOT d'un grand index (entree de fin -> bloc 0) en ValSeg }
Function VBigRoot : Word;
Var I : Integer;
Begin
  For I := 0 To 27 Do MemW[ValSeg:I * 2] := 0;
  PutL(ValSeg, 0, $30); PutL(ValSeg, 4, 1); PutL(ValSeg, 8, 4096);
  Mem[ValSeg:12] := 1;
  PutL(ValSeg, $10, $10); PutL(ValSeg, $14, $28); PutL(ValSeg, $18, $28);
  Mem[ValSeg:$1C] := 1;
  PutW(ValSeg, $28, 24); PutL(ValSeg, $2C, 3); PutL(ValSeg, $30, 0);
  VBigRoot := $38;
End;

{ Correctifs de secteurs du bloc Sg:Ofs de Size octets }
Procedure Protect(Sg, Ofs, Size : Word);
Var UO, I : Word;
Begin
  UO := Ofs + MemW[Sg:Ofs + 4];
  PutW(Sg, UO, 1);
  For I := 1 To Size Div 512 Do
  Begin
    PutW(Sg, UO + I * 2, MemW[Sg:Ofs + I * 512 - 2]);
    PutW(Sg, Ofs + I * 512 - 2, 1);
  End;
End;

{ Bloc INDX (VCN 0) des entrees K* en FatBufSeg, ecrit au cluster Lcn }
Function WriteIndx(Lcn : LongInt) : Boolean;
Var I : Integer; L : Word;
Begin
  For I := 0 To 2047 Do MemW[FatBufSeg:I * 2] := 0;
  PutL(FatBufSeg, 0, $58444E49);
  PutW(FatBufSeg, 4, $28); PutW(FatBufSeg, 6, 9);
  L := KPut(FatBufSeg, $40);
  PutL(FatBufSeg, $18, $28); PutL(FatBufSeg, $1C, $28 + L);
  PutL(FatBufSeg, $20, 4096 - $18);
  Protect(FatBufSeg, 0, 4096);
  WriteIndx := HdIo(Drv, True, PartLba + Lcn * 8, FatBufSeg, 8);
End;

{ ----- donnees ----- }

Function NtAlloc(Clus : LongInt) : LongInt;
Begin
  NtAlloc := NtNext;
  NtNext := NtNext + Clus;
End;

{ Ecrire Clus clusters remplis de B a partir de Lcn }
Function NtFill(Lcn, Clus : LongInt; B : Byte) : Boolean;
Var N : LongInt; I : Word;
Begin
  NtFill := False;
  For I := 0 To 32767 Do Mem[CopySeg:I] := B;
  While Clus > 0 Do
  Begin
    N := Clus;
    If N > 8 Then N := 8;
    If Not HdIo(Drv, True, PartLba + Lcn * 8, CopySeg, N * 8) Then Exit;
    Lcn := Lcn + N; Clus := Clus - N;
    DoneBytes := DoneBytes + N * 512;
    DrawStatus;
  End;
  NtFill := True;
End;

{ $AttrDef (2560 octets) en CopySeg }
Procedure GenAttrDef;
Var I, K : Integer; P : Word; Nm : String; T, Fl, Mn, Mx : LongInt;
Begin
  For I := 0 To 2047 Do MemW[CopySeg:I * 2] := 0;
  For K := 0 To 14 Do
  Begin
    Case K Of
      0 : Begin Nm := '$STANDARD_INFORMATION'; T := $10; Fl := $40;
                Mn := 48; Mx := 72; End;
      1 : Begin Nm := '$ATTRIBUTE_LIST'; T := $20; Fl := $80; Mn := 0;
                Mx := -1; End;
      2 : Begin Nm := '$FILE_NAME'; T := $30; Fl := $42; Mn := 68;
                Mx := 578; End;
      3 : Begin Nm := '$OBJECT_ID'; T := $40; Fl := $40; Mn := 0;
                Mx := 256; End;
      4 : Begin Nm := '$SECURITY_DESCRIPTOR'; T := $50; Fl := $80; Mn := 0;
                Mx := -1; End;
      5 : Begin Nm := '$VOLUME_NAME'; T := $60; Fl := $40; Mn := 2;
                Mx := 256; End;
      6 : Begin Nm := '$VOLUME_INFORMATION'; T := $70; Fl := $40; Mn := 12;
                Mx := 12; End;
      7 : Begin Nm := '$DATA'; T := $80; Fl := 0; Mn := 0; Mx := -1; End;
      8 : Begin Nm := '$INDEX_ROOT'; T := $90; Fl := $40; Mn := 0;
                Mx := -1; End;
      9 : Begin Nm := '$INDEX_ALLOCATION'; T := $A0; Fl := $80; Mn := 0;
                Mx := -1; End;
      10 : Begin Nm := '$BITMAP'; T := $B0; Fl := $80; Mn := 0; Mx := -1; End;
      11 : Begin Nm := '$REPARSE_POINT'; T := $C0; Fl := $80; Mn := 0;
                 Mx := 16384; End;
      12 : Begin Nm := '$EA_INFORMATION'; T := $D0; Fl := $40; Mn := 8;
                 Mx := 8; End;
      13 : Begin Nm := '$EA'; T := $E0; Fl := 0; Mn := 0; Mx := 65536; End;
    Else
      Begin Nm := '$LOGGED_UTILITY_STREAM'; T := $100; Fl := $80; Mn := 0;
            Mx := 65536; End;
    End;
    P := K * 160;
    For I := 1 To Length(Nm) Do PutW(CopySeg, P + (I - 1) * 2, Ord(Nm[I]));
    PutL(CopySeg, P + 128, T); PutL(CopySeg, P + 140, Fl);
    PutL(CopySeg, P + 144, Mn); PutL(CopySeg, P + 152, Mx);
    If Mx = -1 Then PutL(CopySeg, P + 156, -1);
  End;
End;

{ $UpCase : 128 Ko, ecrits par blocs de 32 Ko (16384 caracteres) }
Function WriteUpCase(Lcn : LongInt) : Boolean;
Var B, I, R, K : Integer; C0, C, V : LongInt;
Begin
  WriteUpCase := False;
  For B := 0 To 3 Do
  Begin
    C0 := LongInt(B) * 16384;
    For I := 0 To 16383 Do MemW[CopySeg:I * 2] := Word(C0 + I);
    For R := 0 To 133 Do
      For K := 0 To UpRuns[R * 4 + 1] - 1 Do
      Begin
        C := UpRuns[R * 4] + LongInt(K) * UpRuns[R * 4 + 3];
        If (C >= C0) And (C < C0 + 16384) Then
        Begin
          V := (C + UpRuns[R * 4 + 2]) And $FFFF;
          MemW[CopySeg:Word(C - C0) * 2] := Word(V);
        End;
      End;
    If Not HdIo(Drv, True, PartLba + (Lcn + B * 8) * 8, CopySeg, 64) Then
      Exit;
  End;
  WriteUpCase := True;
End;

{ $Bitmap : clusters 0..NtNext-1, $MFTMirr et ceux au-dela du volume }
Function WriteNtBitmap : Boolean;
Var Ch, I : LongInt; C0, C : LongInt; N : Integer;
Begin
  WriteNtBitmap := False;
  For Ch := 0 To (NtBmpN + 7) Div 8 - 1 Do
  Begin
    For I := 0 To 16383 Do MemW[CopySeg:Word(I) * 2] := 0;
    C0 := Ch * 262144;                         { 32 Ko = 262144 bits }
    For I := 0 To 32767 Do
    Begin
      C := C0 + I * 8;
      If C + 8 <= NtNext Then Mem[CopySeg:Word(I)] := $FF
      Else If C >= NtC Then Mem[CopySeg:Word(I)] := $FF
      Else
        For N := 0 To 7 Do
          If (C + N < NtNext) Or (C + N = NtMirr) Or (C + N >= NtC) Then
            Mem[CopySeg:Word(I)] := Mem[CopySeg:Word(I)] Or (1 Shl N);
      If (C <= NtMirr) And (NtMirr < C + 8) Then
        Mem[CopySeg:Word(I)] := Mem[CopySeg:Word(I)] Or
                                (1 Shl (NtMirr - C));
    End;
    N := 8;
    If NtBmpN - Ch * 8 < 8 Then N := NtBmpN - Ch * 8;
    If Not HdIo(Drv, True, PartLba + (NtBmpL + Ch * 8) * 8, CopySeg, N * 8)
    Then Exit;
  End;
  WriteNtBitmap := True;
End;

{ Copier un fichier du CD-ROM (ou le texte produit si Idx < 0, GenLen
  octets en CopySeg) dans les clusters suivants }
Function NtCopy(Idx : Integer; Const Nm : String; InRoot : Boolean;
                Fl : LongInt) : Boolean;
Var Lcn, Clus, Size, Rem, K, Bytes : LongInt; N : Integer;
Begin
  NtCopy := False;
  If NfN > 31 Then Exit;
  If Idx >= 0 Then Size := CdFiles[Idx].Size Else Size := GenLen;
  Clus := (Size + 4095) Div 4096;
  Lcn := NtAlloc(Clus);
  If Idx < 0 Then
  Begin
    SetStatus(L('Cr'#130'ation de ', 'Creating ', 'Erstellen: ',
                'Creazione di ', 'Creando ') + Nm + '...');
    If Size > 0 Then
      If Not WriteBuf(PartLba + Lcn * 8, Size) Then Exit;
  End
  Else
  Begin
    SetStatus(L('Copie de ', 'Copying ', 'Kopieren: ', 'Copia di ',
                'Copiando ') + Nm + '...');
    Rem := Size; K := 0;
    While Rem > 0 Do
    Begin
      N := 16;
      If Rem < 32768 Then N := (Rem + 2047) Div 2048;
      If Not CdReadN(CdFiles[Idx].Lba + K, CopySeg, N) Then
      Begin
        InstErr := L('Erreur de lecture du CD-ROM : ', 'CD-ROM read error: ',
                     'CD-ROM-Lesefehler: ', 'Errore di lettura del CD-ROM: ',
                     'Error de lectura del CD-ROM: ') + Nm;
        Exit;
      End;
      Bytes := LongInt(N) * 2048;
      If Bytes > Rem Then Bytes := Rem;
      If Not WriteBuf(PartLba + Lcn * 8 + K * 4, Bytes) Then Exit;
      K := K + N; Rem := Rem - Bytes;
      DoneBytes := DoneBytes + Bytes;
      DrawStatus;
    End;
  End;
  NfName[NfN] := Nm; NfRoot[NfN] := InRoot; NfRec[NfN] := 28 + NfN;
  NfLcn[NfN] := Lcn; NfClus[NfN] := Clus; NfSize[NfN] := Size;
  NfFl[NfN] := Fl;
  Inc(NfN);
  NtCopy := True;
End;

{ Mise en page du volume et donnees fixes (avant la copie) }
Function NtFormat : Boolean;
Var I : Integer;
Begin
  NtFormat := False;
  NtC := (PartSecs - 1) Div 8;
  If NtC < 4096 Then
  Begin
    InstErr := L('Partition trop petite pour NTFS.',
                 'Partition too small for NTFS.',
                 'Partition zu klein f'#129'r NTFS.',
                 'Partizione troppo piccola per NTFS.',
                 'Partici'#162'n demasiado peque'#164'a para NTFS.');
    Exit;
  End;
  NtNow;
  NtNext := 2;
  NtMftL := NtAlloc(16); NtMBmpL := NtAlloc(1);
  If PartSecs Div 2048 <= 1024 Then NtLogN := 512 Else NtLogN := 1024;
  NtLogL := NtAlloc(NtLogN);
  NtAdL := NtAlloc(1); NtUpL := NtAlloc(32);
  NtSdsN := (262144 + 256 + 4095) Div 4096; NtSdsL := NtAlloc(NtSdsN);
  NtBmpLen := ((NtC + 7) Div 8 + 7) And Not 7;
  NtBmpN := (NtBmpLen + 4095) Div 4096; NtBmpL := NtAlloc(NtBmpN);
  NtRootIx := NtAlloc(1); NtWinIx := NtAlloc(1);
  NtMirr := NtC Div 2;
  NfN := 0;
  SetStatus(L('Formatage de C: (NTFS)...', 'Formatting C: (NTFS)...',
              'C: wird formatiert (NTFS)...', 'Formattazione di C: ' +
              '(NTFS)...', 'Formateando C: (NTFS)...'));
  If Not NtFill(NtLogL, NtLogN, $FF) Then Exit;
  GenAttrDef;
  If Not HdIo(Drv, True, PartLba + NtAdL * 8, CopySeg, 8) Then Exit;
  If Not WriteUpCase(NtUpL) Then Exit;
  { $SDS : descripteurs, puis leur copie 256 Ko plus loin }
  If Not NtFill(NtSdsL, NtSdsN, 0) Then Exit;
  For I := 0 To 255 Do Mem[CopySeg:I] := NtSds[I];
  If Not HdIo(Drv, True, PartLba + NtSdsL * 8, CopySeg, 1) Then Exit;
  If Not HdIo(Drv, True, PartLba + (NtSdsL + 64) * 8, CopySeg, 1) Then Exit;
  NtFormat := True;
End;

{ Enregistrement d'un fichier systeme de la racine (parent 5) }
Procedure SysRec(N : LongInt; Seq : Word; Const Nm : String; Fl : LongInt;
                 SecId : LongInt; Flags : Word; AllocLo, SizeLo : LongInt);
Var Ln : Word;
Begin
  RInit(N, Seq, Flags, 1);
  RRes($10, '', VSi(Fl, SecId, True), 0);
  If (Flags And 2) <> 0 Then Fl := Fl Or $10000000;
  Ln := VFn(ValSeg, 0, 5, 5, AllocLo, SizeLo, Fl, Nm, 3);
  RRes($30, '', Ln, 1);
  KAdd(N, Seq, 5, 5, AllocLo, SizeLo, Fl, Nm);
End;

{ Construire et ecrire la MFT, le miroir, les index, le bitmap et le
  secteur d'amorce }
Function NtFinish : Boolean;
Var I, K : Integer; Ln : Word; N, BadLo, BadHi : LongInt; Tx : String;
Begin
  NtFinish := False;
  SetStatus(L(''#144'criture de la MFT et des index...',
              'Writing the MFT and indexes...',
              'MFT und Indizes werden geschrieben...',
              'Scrittura della MFT e degli indici...',
              'Escribiendo la MFT y los '#161'ndices...'));
  { index de $Extend : $ObjId, $Quota, $Reparse (petit index), prepare
    en CopySeg avant la liste de la racine }
  KN := 0;
  KAdd(25, 1, 11, 11, 0, 0, $20000026, '$ObjId');
  KAdd(24, 1, 11, 11, 0, 0, $20000026, '$Quota');
  KAdd(26, 1, 11, 11, 0, 0, $20000026, '$Reparse');
  For I := 0 To 7 Do MemW[CopySeg:I * 2] := 0;
  PutL(CopySeg, 0, $30); PutL(CopySeg, 4, 1); PutL(CopySeg, 8, 4096);
  Mem[CopySeg:12] := 1;
  Ln := KPut(CopySeg, $20);
  PutL(CopySeg, $10, $10); PutL(CopySeg, $14, $10 + Ln);
  PutL(CopySeg, $18, $10 + Ln); Mem[CopySeg:$1C] := 0;
  K := $20 + Ln;
  KN := 0;
  SysRec(0, 1, '$MFT', 6, $100, 1, 65536, 65536);
  RNonRes($80, '', NtMftL, 16, 65536, 0, 65536, 0);
  RNonRes($B0, '', NtMBmpL, 1, 4096, 0, 8, 0);
  RDone;
  SysRec(1, 1, '$MFTMirr', 6, $100, 1, 4096, 4096);
  RNonRes($80, '', NtMirr, 1, 4096, 0, 4096, 0);
  RDone;
  SysRec(2, 2, '$LogFile', 6, $100, 1, NtLogN * 4096, NtLogN * 4096);
  RNonRes($80, '', NtLogL, NtLogN, NtLogN * 4096, 0, NtLogN * 4096, 0);
  RDone;
  SysRec(3, 3, '$Volume', 6, $100, 1, 0, 0);
  Tx := 'PASDOWS95';
  For I := 1 To 9 Do PutW(ValSeg, (I - 1) * 2, Ord(Tx[I]));
  RRes($60, '', 18, 0);
  For I := 0 To 5 Do MemW[ValSeg:I * 2] := 0;
  Mem[ValSeg:8] := 3; Mem[ValSeg:9] := 1;
  RRes($70, '', 12, 0);
  RRes($80, '', 0, 0);
  RDone;
  SysRec(4, 4, '$AttrDef', 6, $100, 1, 4096, 2560);
  RNonRes($80, '', NtAdL, 1, 4096, 0, 2560, 0);
  RDone;
  SysRec(6, 6, '$Bitmap', 6, $100, 1, NtBmpN * 4096, NtBmpLen);
  RNonRes($80, '', NtBmpL, NtBmpN, NtBmpN * 4096, 0, NtBmpLen, 0);
  RDone;
  SysRec(7, 7, '$Boot', 6, $100, 1, 8192, 8192);
  RNonRes($80, '', 0, 2, 8192, 0, 8192, 0);
  RDone;
  SysRec(8, 8, '$BadClus', 6, $100, 1, 0, 0);
  RRes($80, '', 0, 0);
  BadLo := NtC Shl 12; BadHi := NtC Shr 20;
  RNonRes($80, '$Bad', -1, NtC, BadLo, BadHi, BadLo, BadHi);
  RDone;
  SysRec(9, 9, '$Secure', $20000006, $101, 9, 0, 0);
  RNonRes($80, '$SDS', NtSdsL, NtSdsN, NtSdsN * 4096, 0, 262144 + 256, 0);
  For I := 0 To 143 Do Mem[ValSeg:I] := NtSdh[I];
  RRes($90, '$SDH', 144, 0);
  For I := 0 To 127 Do Mem[ValSeg:I] := NtSii[I];
  RRes($90, '$SII', 128, 0);
  RDone;
  SysRec(10, 10, '$UpCase', 6, $100, 1, 131072, 131072);
  RNonRes($80, '', NtUpL, 32, 131072, 0, 131072, 0);
  RDone;
  SysRec(11, 11, '$Extend', 6, $101, 3, 0, 0);
  For I := 0 To K - 1 Do Mem[ValSeg:I] := Mem[CopySeg:I];
  RRes($90, '$I30', K, 0);
  RDone;
  For N := 12 To 15 Do
  Begin
    RInit(N, N, 1, 0);
    RRes($10, '', VSi(6, $100, True), 0);
    RRes($80, '', 0, 0);
    RDone;
  End;
  For N := 16 To 23 Do
  Begin
    RInit(N, N, 0, 0);
    RRes($10, '', VSi(0, 0, False), 0);
    RDone;
  End;
  { fichiers de $Extend }
  For N := 24 To 26 Do
  Begin
    RInit(N, 1, 13, 1);
    RRes($10, '', VSi($20000026, $101, True), 0);
    If N = 24 Then
      Ln := VFn(ValSeg, 0, 11, 11, 0, 0, $20000026, '$Quota', 3)
    Else If N = 25 Then
      Ln := VFn(ValSeg, 0, 11, 11, 0, 0, $20000026, '$ObjId', 3)
    Else Ln := VFn(ValSeg, 0, 11, 11, 0, 0, $20000026, '$Reparse', 3);
    RRes($30, '', Ln, 1);
    If N = 24 Then
    Begin
      For I := 0 To 87 Do Mem[ValSeg:I] := NtQo[I];
      RRes($90, '$O', 88, 0);
      For I := 0 To 207 Do Mem[ValSeg:I] := NtQq[I];
      RRes($90, '$Q', 208, 0);
    End
    Else
    Begin
      For I := 0 To 47 Do Mem[ValSeg:I] := NtEmptyIx[I];
      If N = 25 Then RRes($90, '$O', 48, 0) Else RRes($90, '$R', 48, 0);
    End;
    RDone;
  End;
  { racine (5) : '.' et ses entrees }
  KAdd(5, 5, 5, 5, 0, 0, $10000026, '.');
  KAdd(27, 1, 5, 5, 0, 0, $10000000, 'WINDOWS');
  For I := 0 To NfN - 1 Do
    If NfRoot[I] Then
      KAdd(NfRec[I], 1, 5, 5, NfClus[I] * 4096, NfSize[I], NfFl[I],
           NfName[I]);
  If Not WriteIndx(NtRootIx) Then Exit;
  RInit(5, 5, 3, 1);
  RRes($10, '', VSi($26, $101, True), 0);
  RRes($30, '', VFn(ValSeg, 0, 5, 5, 0, 0, $10000026, '.', 3), 1);
  RRes($90, '$I30', VBigRoot, 0);
  RNonRes($A0, '$I30', NtRootIx, 1, 4096, 0, 4096, 0);
  For I := 0 To 3 Do MemW[ValSeg:I * 2] := 0;
  Mem[ValSeg:0] := 1;
  RRes($B0, '$I30', 8, 0);
  RDone;
  { C:\WINDOWS (27) }
  KN := 0;
  For I := 0 To NfN - 1 Do
    If Not NfRoot[I] Then
      KAdd(NfRec[I], 1, 27, 1, NfClus[I] * 4096, NfSize[I], NfFl[I],
           NfName[I]);
  If Not WriteIndx(NtWinIx) Then Exit;
  RInit(27, 1, 3, 1);
  RRes($10, '', VSi(0, 0, False), 0);
  RRes($30, '', VFn(ValSeg, 0, 5, 5, 0, 0, $10000000, 'WINDOWS', 3), 1);
  RRes($90, '$I30', VBigRoot, 0);
  RNonRes($A0, '$I30', NtWinIx, 1, 4096, 0, 4096, 0);
  For I := 0 To 3 Do MemW[ValSeg:I * 2] := 0;
  Mem[ValSeg:0] := 1;
  RRes($B0, '$I30', 8, 0);
  RDone;
  { fichiers }
  For I := 0 To NfN - 1 Do
  Begin
    RInit(NfRec[I], 1, 1, 1);
    RRes($10, '', VSi(NfFl[I], 0, False), 0);
    If NfRoot[I] Then
      Ln := VFn(ValSeg, 0, 5, 5, NfClus[I] * 4096, NfSize[I], NfFl[I],
               NfName[I], NsOf(NfName[I]))
    Else
      Ln := VFn(ValSeg, 0, 27, 1, NfClus[I] * 4096, NfSize[I], NfFl[I],
               NfName[I], NsOf(NfName[I]));
    RRes($30, '', Ln, 1);
    If NfClus[I] > 0 Then
      RNonRes($80, '', NfLcn[I], NfClus[I], NfClus[I] * 4096, 0, NfSize[I], 0)
    Else RRes($80, '', 0, 0);
    RDone;
  End;
  { enregistrements libres }
  For N := 28 + NfN To 63 Do
  Begin
    RInit(N, 1, 0, 0);
    RDone;
  End;
  { correctifs et ecriture : MFT (64 Ko) et miroir (4 enregistrements) }
  For N := 0 To 63 Do Protect(MftSeg, Word(N) * 1024, 1024);
  If Not HdIo(Drv, True, PartLba + NtMftL * 8, MftSeg, 64) Then Exit;
  If Not HdIo(Drv, True, PartLba + NtMftL * 8 + 64, MftSeg + $800, 64)
  Then Exit;
  If Not HdIo(Drv, True, PartLba + NtMirr * 8, MftSeg, 8) Then Exit;
  { bitmap de la MFT : 0-15, 24 et suivants }
  For I := 0 To 2047 Do MemW[CopySeg:I * 2] := 0;
  For N := 0 To 27 + NfN Do
    If (N < 16) Or (N >= 24) Then
      Mem[CopySeg:Word(N) Shr 3] := Mem[CopySeg:Word(N) Shr 3] Or
                                    (1 Shl (N And 7));
  If Not HdIo(Drv, True, PartLba + NtMBmpL * 8, CopySeg, 8) Then Exit;
  If Not WriteNtBitmap Then Exit;
  { secteur d'amorce, chargeur (secteurs 1-15) et copie }
  For I := 0 To 4095 Do MemW[CopySeg:I * 2] := 0;
  Mem[CopySeg:0] := $EB; Mem[CopySeg:1] := $52; Mem[CopySeg:2] := $90;
  Tx := 'NTFS    ';
  For I := 1 To 8 Do Mem[CopySeg:2 + I] := Ord(Tx[I]);
  PutW(CopySeg, 11, 512); Mem[CopySeg:13] := 8;
  Mem[CopySeg:$15] := $F8;
  PutW(CopySeg, $18, DiskSpt[DiskSel]); PutW(CopySeg, $1A, DiskHeads[DiskSel]);
  PutL(CopySeg, $1C, PartLba);
  Mem[CopySeg:$24] := $80; Mem[CopySeg:$26] := $80;
  PutL(CopySeg, $28, PartSecs - 1);
  PutL(CopySeg, $30, NtMftL); PutL(CopySeg, $38, NtMirr);
  Mem[CopySeg:$40] := $F6; Mem[CopySeg:$44] := 1;
  PutW(CopySeg, $48, Ticks); PutW(CopySeg, $4A, DosDate);
  PutW(CopySeg, $4C, DosTime); PutW(CopySeg, $4E, $5095);
  For I := 0 To 1555 - 84 Do Mem[CopySeg:84 + I] := NtBootCode[I];
  MemW[CopySeg:510] := $AA55;
  If Not HdIo(Drv, True, PartLba, CopySeg, 16) Then Exit;
  If Not HdIo(Drv, True, PartLba + PartSecs - 1, CopySeg, 1) Then Exit;
  NtFinish := True;
End;

{ Installation sur NTFS : formatage, fichiers, puis MFT et index }
Procedure DoInstallNtfs;
Var I, Ix : Integer; N : String;
Begin
  If Not NtFormat Then
  Begin
    If InstErr = '' Then InstErr := DiskErr;
    Exit;
  End;
  If Not NtCopy(CdFind('IO.SYS'), 'IO.SYS', True, $27) Then
  Begin
    If InstErr = '' Then InstErr := DiskErr;
    Exit;
  End;
  GenMsdosSys;
  If Not NtCopy(-1, 'MSDOS.SYS', True, $27) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  GenConfigSys;
  If Not NtCopy(-1, 'CONFIG.SYS', True, $20) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  GenAutoexec;
  If Not NtCopy(-1, 'AUTOEXEC.BAT', True, $20) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  Ix := CdFind('COMMAND.EXE');
  If Ix >= 0 Then
    If Not NtCopy(Ix, 'COMMAND.EXE', True, $20) Then
    Begin
      If InstErr = '' Then InstErr := DiskErr;
      Exit;
    End;
  For I := 0 To CdCount - 1 Do
  Begin
    N := CdFiles[I].Name;
    If Not CdFiles[I].Dir And WantFile(N) And (N <> 'IO.SYS') And
       (N <> 'COMMAND.EXE') Then
      If Not NtCopy(I, N, False, $20) Then
      Begin
        If InstErr = '' Then InstErr := DiskErr;
        Exit;
      End;
  End;
  If NtNext >= NtMirr Then
  Begin
    InstErr := L('Partition trop petite.', 'Partition too small.',
                 'Partition zu klein.', 'Partizione troppo piccola.',
                 'Partici'#162'n demasiado peque'#164'a.');
    Exit;
  End;
  If Not NtFinish Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  SaveCmos;
  DoneBytes := TotalBytes;
  SetStatus(L('Installation termin'#130'e.', 'Setup is complete.',
              'Installation abgeschlossen.', 'Installazione completata.',
              'Instalaci'#162'n completada.'));
End;

Procedure DoInstall;
Var I, Ix : Integer; RootC, WinC, RootK, WinK, Free0 : LongInt;
    H, M, S, Y, Mo, D : Integer; N : String;
Begin
  InstErr := '';
  Drv := $80 + DiskSel;
  RtcTime(H, M, S); RtcDate(Y, Mo, D);
  DosDate := ((Y - 1980) Shl 9) Or (Mo Shl 5) Or D;
  DosTime := (H Shl 11) Or (M Shl 5) Or (S Div 2);
  DoneBytes := 0;
  TotalBytes := LongInt(NeedMb) * 1048576 + 65536;
  If Not CdOk Or (CdFind('IO.SYS') < 0) Or (CdFind('VMM32.VXD') < 0) Then
  Begin
    InstErr := L('Fichiers de Pasdows introuvables sur le CD-ROM.',
                 'Pasdows files not found on the CD-ROM.',
                 'Pasdows-Dateien nicht auf der CD-ROM.',
                 'File di Pasdows non trovati sul CD-ROM.',
                 'Archivos de Pasdows no encontrados en el CD-ROM.');
    Exit;
  End;
  SetStatus(L('Cr'#130'ation de la partition...', 'Creating the ' +
              'partition...', 'Partition wird erstellt...',
              'Creazione della partizione...', 'Creando la ' +
              'partici'#162'n...'));
  If Not WriteMbr Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  If FsKind = 2 Then
  Begin
    DoInstallNtfs;
    Exit;
  End;
  Fat16 := FsKind = 0;
  SetStatus(L('Formatage de C: (', 'Formatting C: (', 'C: wird formatiert (',
              'Formattazione di C: (', 'Formateando C: (') + FsName(FsKind) +
            ')...');
  If Fat16 Then
  Begin
    If Not FormatFat16 Then
    Begin
      If InstErr = '' Then InstErr := DiskErr;
      Exit;
    End;
  End
  Else If Not FormatFat32 Then
  Begin
    If InstErr = '' Then InstErr := DiskErr;
    Exit;
  End;
  { repertoires : racine (2 Ko ; FAT16 : zone fixe) et C:\WINDOWS (4 Ko) }
  RootK := (2048 + LongInt(Spc) * 512 - 1) Div (LongInt(Spc) * 512);
  WinK := (4096 + LongInt(Spc) * 512 - 1) Div (LongInt(Spc) * 512);
  If Fat16 Then RootC := 0
  Else RootC := AllocBytes(RootK * Spc * 512);
  WinC := AllocBytes(WinK * Spc * 512);
  RootN := 0; WinN := 0;
  { IO.SYS en premier (cache, systeme, lecture seule) }
  If Not CopyCdFile(CdFind('IO.SYS'), True, $07) Then
  Begin
    If InstErr = '' Then InstErr := DiskErr;
    Exit;
  End;
  GenMsdosSys;
  If Not WriteGen('MSDOS.SYS', $07) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  GenConfigSys;
  If Not WriteGen('CONFIG.SYS', $20) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  GenAutoexec;
  If Not WriteGen('AUTOEXEC.BAT', $20) Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  Ix := CdFind('COMMAND.EXE');
  If Ix >= 0 Then
    If Not CopyCdFile(Ix, True, $20) Then
    Begin
      If InstErr = '' Then InstErr := DiskErr;
      Exit;
    End;
  AddEnt(True, 'WINDOWS', $10, WinC, 0);
  For I := 0 To CdCount - 1 Do
  Begin
    N := CdFiles[I].Name;
    If Not CdFiles[I].Dir And WantFile(N) And (N <> 'IO.SYS') And
       (N <> 'COMMAND.EXE') Then
      If Not CopyCdFile(I, False, $20) Then
      Begin
        If InstErr = '' Then InstErr := DiskErr;
        Exit;
      End;
  End;
  SetStatus(L(''#144'criture des r'#130'pertoires et de la FAT...',
              'Writing directories and FAT...',
              'Verzeichnisse und FAT werden geschrieben...',
              'Scrittura di directory e FAT...',
              'Escribiendo directorios y FAT...'));
  If Not WriteDirs(RootC, RootK, WinC, WinK) Or Not WriteFats Then
  Begin
    InstErr := DiskErr;
    Exit;
  End;
  Free0 := TotClus - (NextClus - 2);
  FsInfo(Free0, NextClus);
  If Not Fat16 Then
    If Not HdIo(Drv, True, PartLba + 1, SecSeg, 1) Or
       Not HdIo(Drv, True, PartLba + 7, SecSeg, 1) Then
    Begin
      InstErr := DiskErr;
      Exit;
    End;
  SaveCmos;
  DoneBytes := TotalBytes;
  SetStatus(L('Installation termin'#130'e.', 'Setup is complete.',
              'Installation abgeschlossen.', 'Installazione completata.',
              'Instalaci'#162'n completada.'));
End;

{ ================================================================== }
{ Navigation                                                         }
{ ================================================================== }

Procedure Quit;
Begin
  If MsgBox(TxtSetup, L('Pasdows 95 n''est pas install'#130'. Voulez-vous ' +
    'quitter l''installation et red'#130'marrer l''ordinateur ?',
    'Pasdows 95 is not installed. Do you want to exit Setup and restart ' +
    'the computer?', 'Pasdows 95 ist nicht installiert. Setup beenden ' +
    'und den Computer neu starten?', 'Pasdows 95 non '#138' installato. ' +
    'Uscire dall''installazione e riavviare il computer?',
    'Pasdows 95 no est'#160' instalado. '#168'Desea salir de la ' +
    'instalaci'#162'n y reiniciar el equipo?'), True, True) Then
    Reboot;
End;

Procedure GoPage(P : Integer);
Begin
  Page := P;
  PressBtn := -1;
  RedrawAll;
End;

Procedure GoNext;
Var Avail : LongInt;
Begin
  Case Page Of
    pgDisk :
    Begin
      If Not DiskUsable Then Exit;
      If (PartMode = 0) And (PartMb < FsMinMb[FsKind]) Then
      Begin
        MsgBox(PageName(pgDisk), L('La partition doit avoir au moins ',
          'The partition must be at least ', 'Die Partition muss ' +
          'mindestens ', 'La partizione deve essere di almeno ',
          'La partici'#162'n debe tener al menos ') +
          IntToStr(FsMinMb[FsKind]) + TxtMb + '.', False, True);
        Exit;
      End;
      If (PartMode = 1) And ((PSize[PExist] Div 2048 > FsMaxMb[FsKind]) Or
         (PSize[PExist] Div 2048 < FsMinMb[FsKind])) Then
      Begin
        MsgBox(PageName(pgDisk), FsName(FsKind) + L(' : taille de ' +
          'partition non permise (FAT16 : 2 Go au plus).', ': partition ' +
          'size not allowed (FAT16: 2 GB at most).',
          ': Partitionsgr'#148#225'e ' +
          'nicht erlaubt (FAT16: max. 2 GB).', ': dimensione non ' +
          'consentita (FAT16: max 2 GB).', ': tama'#164'o no permitido ' +
          '(FAT16: 2 GB m'#160'x.).'), False, True);
        Exit;
      End;
      GoPage(pgTz);
    End;
    pgComp :
    Begin
      If PartMode = 0 Then Avail := PartMb
      Else Avail := PSize[PExist] Div 2048;
      If NeedMb + 2 > Avail Then
      Begin
        MsgBox(PageName(pgComp), L('Espace disque insuffisant.',
          'Not enough disk space.', 'Nicht genug Speicherplatz.',
          'Spazio su disco insufficiente.',
          'Espacio en disco insuficiente.'), False, True);
        Exit;
      End;
      GoPage(pgReady);
    End;
    pgReady :
    Begin
      If Not MsgBox(TxtSetup, L('Toutes les donn'#130'es de la partition ' +
        'choisie (ou du disque, pour une nouvelle partition) seront ' +
        'effac'#130'es. Voulez-vous continuer ?', 'All data on the ' +
        'selected partition (or the whole disk, for a new partition) will ' +
        'be erased. Do you want to continue?', 'Alle Daten der Partition ' +
        '(oder der Festplatte) werden gel'#148'scht. Fortfahren?',
        'Tutti i dati della partizione (o del disco) saranno cancellati. ' +
        'Continuare?', 'Se borrar'#160'n todos los datos de la ' +
        'partici'#162'n (o del disco). '#168'Desea continuar?'), True, True)
      Then Exit;
      GoPage(pgCopy);
      DoInstall;
      GoPage(pgDone);
    End;
    pgDone : Reboot;
  Else
    GoPage(Page + 1);
  End;
End;

Procedure GoBack;
Begin
  If (Page > pgLang) And (Page <= pgReady) Then GoPage(Page - 1);
End;

Procedure NavAction(I : Integer);
Begin
  Case I Of
    0 : GoBack;
    1 : If NavEnabled(1) Then GoNext;
  Else
    Quit;
  End;
End;

Procedure SizeStep(D : LongInt);
Begin
  PartMb := PartMb + D;
  If PartMb > MaxMb Then PartMb := MaxMb;
  If PartMb > FsMaxMb[FsKind] Then PartMb := FsMaxMb[FsKind];
  If PartMb < FsMinMb[FsKind] Then PartMb := FsMinMb[FsKind];
  If PartMb > MaxMb Then PartMb := MaxMb;
  PartMode := 0;
  RedrawPage;
End;

Procedure TzShow;
Var X1, Y1, X2, Y2, Rows : Integer;
Begin
  TzBox(X1, Y1, X2, Y2, Rows);
  If TzSel < TzTop Then TzTop := TzSel;
  If TzSel >= TzTop + Rows Then TzTop := TzSel - Rows + 1;
End;

{ Clic dans la page }
Procedure PageClick(X, Y : Integer);
Var I, Yo, X1, Y1, X2, Y2, Rows : Integer;
Begin
  Case Page Of
    pgLang :
      For I := 0 To 4 Do
        If InRect(X, Y, CX1 + 14, LangRadioY(I), CX2, LangRadioY(I) + 16)
        Then
        Begin
          SetLang(I);
          RedrawAll;
          Exit;
        End;
    pgDisk :
    Begin
      If DiskCnt = 0 Then Exit;
      For I := 0 To DiskCnt - 1 Do
        If InRect(X, Y, CX1 + 4, CY1 + 20 + I * 20, CX2, CY1 + 36 + I * 20)
        Then
        Begin
          ChooseDisk(I);
          RedrawAll;
          Exit;
        End;
      Yo := DiskOptY;
      If InRect(X, Y, CX1 + 204, Yo + 18, CX1 + 226, Yo + 40) Then
        SizeStep(-10)
      Else If InRect(X, Y, CX1 + 228, Yo + 18, CX1 + 250, Yo + 40) Then
        SizeStep(10)
      Else If InRect(X, Y, CX1, Yo, CX2, Yo + 16) Then
      Begin
        PartMode := 0;
        RedrawAll;
      End
      Else If (PExist >= 0) And InRect(X, Y, CX1, Yo + 64, CX2, Yo + 80)
      Then
      Begin
        PartMode := 1;
        RedrawAll;
      End
      Else
        For I := 0 To FsCount - 1 Do
          If InRect(X, Y, CX1 + 18 + I * 90, Yo + 106, CX1 + 100 + I * 90,
                    Yo + 122) Then
          Begin
            FsKind := I;
            If PartMb > FsMaxMb[I] Then PartMb := FsMaxMb[I];
            If PartMb > MaxMb Then PartMb := MaxMb;
            RedrawAll;
          End;
    End;
    pgTz :
    Begin
      TzBox(X1, Y1, X2, Y2, Rows);
      If InRect(X, Y, X2 - 18, Y1, X2, Y1 + 18) Then
      Begin
        If TzTop > 0 Then Dec(TzTop);
      End
      Else If InRect(X, Y, X2 - 18, Y2 - 18, X2, Y2) Then
      Begin
        If TzTop < TzCount - Rows Then Inc(TzTop);
      End
      Else If InRect(X, Y, X2 - 18, Y1, X2, Y2) Then
      Begin
        If Y < (Y1 + Y2) Div 2 Then TzTop := 0
        Else TzTop := TzCount - Rows;
      End
      Else If InRect(X, Y, X1, Y1, X2, Y2) Then
      Begin
        I := TzTop + (Y - Y1 - 3) Div 18;
        If (I >= 0) And (I < TzCount) Then TzSel := I;
      End
      Else If InRect(X, Y, CX1, Y2 + 10, CX2, Y2 + 26) Then
        TzDst := Not TzDst
      Else Exit;
      RedrawPage;
    End;
    pgDisp :
      For I := 0 To DispCount - 1 Do
        If InRect(X, Y, CX1 + 14, CY1 + 98 + I * 24, CX2,
                  CY1 + 114 + I * 24) Then
        Begin
          DispSel := I;
          RedrawPage;
          Exit;
        End;
    pgComp :
    Begin
      If InRect(X, Y, CX1, CY1 + 30, CX2, CY1 + 46) Then CompEx := Not CompEx
      Else If InRect(X, Y, CX1, CY1 + 74, CX2, CY1 + 90) Then
        CompSnd := Not CompSnd
      Else If InRect(X, Y, CX1, CY1 + 102, CX2, CY1 + 118) Then
        CompDoc := Not CompDoc
      Else Exit;
      RedrawPage;
    End;
  End;
End;

Procedure PageKey(Sc : Byte; Ch : Char);
Var D : Integer;
Begin
  D := 0;
  If Sc = scUp Then D := -1 Else If Sc = scDown Then D := 1;
  Case Page Of
    pgLang :
      If D <> 0 Then
      Begin
        SetLang((LangIndex + D + 5) Mod 5);
        RedrawAll;
      End;
    pgDisk :
      If (Ch = '+') Or (Sc = scRight) Then SizeStep(10)
      Else If (Ch = '-') Or (Sc = scLeft) Then SizeStep(-10)
      Else If Sc = scPgUp Then SizeStep(100)
      Else If Sc = scPgDn Then SizeStep(-100)
      Else If (D <> 0) And (PExist >= 0) Then
      Begin
        PartMode := 1 - PartMode;
        RedrawAll;
      End;
    pgTz :
      If D <> 0 Then
      Begin
        TzSel := (TzSel + D + TzCount) Mod TzCount;
        TzShow;
        RedrawPage;
      End;
    pgDisp :
      If D <> 0 Then
      Begin
        DispSel := (DispSel + D + DispCount) Mod DispCount;
        RedrawPage;
      End;
  End;
End;

Procedure Loop;
Var E : TEvent; I, X1, Y1, X2, Y2 : Integer;
Begin
  Repeat
    If NextEvent(E) Then
    Begin
      If E.Kind = evKey Then
      Begin
        If E.Sc = scEnter Then NavAction(1)
        Else If E.Sc = scEsc Then
        Begin
          If Page <> pgDone Then NavAction(2);
        End
        Else If (E.Sc = scBack) And (Page <> pgDone) Then NavAction(0)
        Else PageKey(E.Sc, E.Ch);
      End
      Else If (E.Kind = evDown) And (E.Btn = 1) Then
      Begin
        PressBtn := -1;
        For I := 0 To 2 Do
          If NavBtn(I, X1, Y1, X2, Y2) Then
            If InRect(E.X, E.Y, X1, Y1, X2, Y2) And NavEnabled(I) Then
              PressBtn := I;
        If PressBtn >= 0 Then
        Begin
          HideCursor;
          DrawNav;
          ShowCursor;
        End
        Else PageClick(E.X, E.Y);
      End
      Else If (E.Kind = evUp) And (E.Btn = 1) And (PressBtn >= 0) Then
      Begin
        I := PressBtn;
        PressBtn := -1;
        HideCursor;
        DrawNav;
        ShowCursor;
        If NavBtn(I, X1, Y1, X2, Y2) Then
          If InRect(E.X, E.Y, X1, Y1, X2, Y2) Then NavAction(I);
      End;
    End;
  Until False;
End;

{ ================================================================== }
{ Demarrage : disque dur deja amorcable ?                            }
{ ================================================================== }

Const
  { 0000:0600 : relire le MBR du disque 80h en 0000:7C00 et y sauter }
  Tramp : Array[0..31] Of Byte = (
    $FA, $31, $C0, $8E, $D8, $8E, $C0, $8E, $D0, $BC, $00, $7C, $FB,
    $B8, $01, $02, $B9, $01, $00, $BA, $80, $00, $BB, $00, $7C, $CD,
    $13, $EA, $00, $7C, $00, $00);

Procedure BiosPrint(Const S : String);
Var I : Integer; C : Byte;
Begin
  For I := 1 To Length(S) Do
  Begin
    C := Ord(S[I]);
    asm
      mov ah,0Eh
      mov al,C
      mov bx,7
      int 10h
    end;
  End;
End;

Function BiosKeyHit : Boolean;
Var Z : Byte;
Begin
  asm
    mov ah,1
    int 16h
    mov al,0
    jz @none
    mov al,1
  @none:
    mov Z,al
  end;
  BiosKeyHit := Z = 1;
End;

Procedure BiosReadKey;
Begin
  asm
    xor ah,ah
    int 16h
  end;
End;

{ Si le disque dur a une partition active : appuyer sur une touche pour
  installer depuis le CD-ROM, sinon demarrer le disque dur }
Procedure BootPrompt;
Var I, Ofs : Integer; Act : Boolean; T, T0 : Word;
Begin
  If Not HdIo($80, False, 0, SecSeg, 1) Then Exit;
  If MemW[SecSeg:510] <> $AA55 Then Exit;
  Act := False;
  For I := 0 To 3 Do
  Begin
    Ofs := 446 + I * 16;
    If (Mem[SecSeg:Ofs] = $80) And (Mem[SecSeg:Ofs + 4] <> 0) Then
      Act := True;
  End;
  If Not Act Then Exit;
  BiosPrint(#13#10'Appuyez sur une touche pour d'#130'marrer depuis le ' +
            'CD-ROM (installation de Pasdows 95)');
  T0 := Ticks;
  Repeat
    T := Word(Ticks - T0);
    If (T Mod 18) = 0 Then
    Begin
      BiosPrint('.');
      While Word(Ticks - T0) = T Do;
    End;
    If BiosKeyHit Then
    Begin
      BiosReadKey;
      Exit;
    End;
  Until Word(Ticks - T0) > 5 * 18;
  BiosPrint(#13#10);
  For I := 0 To 31 Do Mem[0:$0600 + I] := Tramp[I];
  asm
    db 0EAh
    dw 0600h
    dw 0000h
  end;
End;

{ ================================================================== }
{ Programme principal                                                }
{ ================================================================== }

BEGIN
  BootDrive := Lo(PrefixSeg);
  InitKeyTables;
  Language := _French;
  BootPrompt;
  CdScan;
  DetectDisks;
  DiskSel := -1; MaxMb := 0; PartMb := 0; PExist := -1; PartMode := 0;
  MbrOk := False;
  FsKind := 1;
  If DiskCnt > 0 Then ChooseDisk(0);
  TzSel := 5; TzTop := 0; TzDst := True;
  DispSel := 0;
  CompEx := True; CompSnd := True; CompDoc := True;
  FsKind := 1;
  Page := pgLang; PressBtn := -1;
  InstErr := ''; StatusText := '';
  CurShown := False;
  InitInput;
  GraphMode;
  SetArea(0, 0, ScrW - 1, ScrH - 1);
  LastMX := MouseX; LastMY := MouseY;
  RedrawAll;
  Loop;
END.
