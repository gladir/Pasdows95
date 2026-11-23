{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: Turbo Pascal 7, Free Pascal 3.2)
  @description: Fabrique COMMAND.PAK, l'archive des commandes MS-DOS de
                Pasdows 95 (DOS/*.PAS compilees par WPC). L'installation
                copie ce seul fichier dans C:\WINDOWS ; au premier
                demarrage, VMM32 le deballe dans C:\WINDOWS\COMMAND.
}

Program MAKEPAK;

{ Syntaxe : MAKEPAK archive.pak fichier [fichier ...]

  Format : pour chaque fichier, un en-tete de 16 octets (nom 8.3 en
  majuscules complete par des zeros sur 12 octets, taille sur 4 octets
  en ordre Intel) suivi des donnees. }

{$IFDEF FPC}
  {$MODE TP}
{$ENDIF}

Uses Dos;

Var
  Pak, F : File;
  Hdr : Array[0..15] Of Byte;
  Buf : Array[0..8191] Of Byte;
  I, K, N, Count : Integer;
  Size, Total : LongInt;
  Arg, Dir, Nm : String;
  SR : SearchRec;

Function UpStr(S : String) : String;
Var J : Integer;
Begin
  For J := 1 To Length(S) Do S[J] := UpCase(S[J]);
  UpStr := S;
End;

Procedure AddFile(Const Path, Name : String);
Begin
  Assign(F, Path);
  {$I-} Reset(F, 1); {$I+}
  If IOResult <> 0 Then
  Begin
    WriteLn('MAKEPAK: fichier introuvable : ', Path);
    Halt(1);
  End;
  Size := FileSize(F);
  FillChar(Hdr, SizeOf(Hdr), 0);
  Nm := UpStr(Name);
  For K := 1 To Length(Nm) Do
    If K <= 12 Then Hdr[K - 1] := Ord(Nm[K]);
  Hdr[12] := Size And $FF; Hdr[13] := (Size Shr 8) And $FF;
  Hdr[14] := (Size Shr 16) And $FF; Hdr[15] := (Size Shr 24) And $FF;
  BlockWrite(Pak, Hdr, 16);
  Repeat
    BlockRead(F, Buf, SizeOf(Buf), N);
    If N > 0 Then BlockWrite(Pak, Buf, N);
  Until N = 0;
  Close(F);
  Inc(Count);
  Total := Total + Size;
End;

BEGIN
  If ParamCount < 2 Then
  Begin
    WriteLn('Syntaxe : MAKEPAK archive.pak fichier [fichier ...]');
    Halt(1);
  End;
  Assign(Pak, ParamStr(1));
  {$I-} Rewrite(Pak, 1); {$I+}
  If IOResult <> 0 Then
  Begin
    WriteLn('MAKEPAK: impossible de creer ', ParamStr(1));
    Halt(1);
  End;
  Count := 0; Total := 0;
  For I := 2 To ParamCount Do
  Begin
    Arg := ParamStr(I);
    Dir := Arg;
    While (Length(Dir) > 0) And Not (Dir[Length(Dir)] In ['\', '/', ':']) Do
      Delete(Dir, Length(Dir), 1);
    If (Pos('*', Arg) > 0) Or (Pos('?', Arg) > 0) Then
    Begin
      FindFirst(Arg, ReadOnly Or Archive, SR);
      While DosError = 0 Do
      Begin
        AddFile(Dir + SR.Name, SR.Name);
        FindNext(SR);
      End;
    End
    Else AddFile(Arg, Copy(Arg, Length(Dir) + 1, 255));
  End;
  Close(Pak);
  WriteLn('MAKEPAK: ', ParamStr(1), ' : ', Count, ' fichier(s), ', Total,
          ' octets');
END.
