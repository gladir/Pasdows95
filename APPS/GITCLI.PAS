{ @author: Sylvain Maltais (support@gladir.com)
  @created: 2026
  @website(https://www.gladir.com/pasdows95)
  @abstract(Target: WPC -CW32)
  @description: GITCLI - Client GitHub de Pasdows 95 (Win32), dans le
  genre de GitHub Desktop, avec l'apparence de Windows 95.
}

Program GitCli;

{$APPTYPE GUI}
{$R-,S-,I-}

{ Compilation : WPC -CW32 APPS\GITCLI.PAS GITCLI.EXE

  Demarrer, Programmes, Accessoires, Outils Internet, Client GitHub.
  - Git ecrit entierement en Pascal : SHA-1, zlib (inflate, deflate
    LZ77 + Huffman fixe), objets libres, packs et index v2 (deltas
    OFS_DELTA et REF_DELTA), index du dossier de travail (DIRC v2, cache
    taille/date), arbres, commits, references (libres et packed-refs),
    config, .gitignore, statut, validation, extraction, branches, fusion
    a trois voies ligne par ligne (marqueurs de conflit, MERGE_HEAD),
    diff (patience + plus longue sous-suite commune), historique.
  - Protocoles : HTTP et HTTPS « intelligents » (WININET, authentification
    Basic, proxy) et git:// (Winsock, port 9418) ; clonage, recuperation
    (fetch), tirage (pull = fetch + fusion), envoi (push, report-status).
  - API de GitHub.com (jeton d'acces personnel) : compte, liste des
    depots pour le clonage, publication d'un depot.
  - Fenetre de GitHub Desktop : boutons Depot actuel, Branche actuelle et
    Recuperer/Pousser/Tirer origin, onglets Modifications (cases a
    cocher, resume et description du commit) et Historique (commits,
    fichiers modifies), vue des differences en couleurs, menus Fichier,
    Edition, Affichage, Depot, Branche et Aide, raccourcis clavier.
  Le reseau tourne dans une tache (CreateThread) ; un verrou (section
  critique) protege les chaines temporaires du runtime de WPC : la tache
  le libere pendant les appels bloquants et la progression. }

Uses Dos;

Const
  PS = '\';
  AllFiles = '*.*';
{ ==================================================================== }
{ Noyau Git : utilitaires, tampons d'octets                             }
{ ==================================================================== }

Type
  TByteArr = Array[0..$7FFFFFF] Of Byte;
  PBytes = ^TByteArr;
  TSha = Array[0..19] Of Byte;
  { tampon d'octets extensible }
  TBuf = Record
    P : PBytes;
    N, Cap : LongInt;
  End;

Type
  TLongArr4 = Array[0..$3FFFFFF] Of LongInt;

Var
  GitErr : String;                     { derniere erreur (texte) }
  ShaZero : TSha;

{ progression d'une operation longue (definie par le programme) }
Procedure GitProgress(Const What : String; Done, Total : LongInt); Forward;

Procedure BufInit(Var B : TBuf);
Begin
  B.P := Nil; B.N := 0; B.Cap := 0;
End;

Procedure BufFree(Var B : TBuf);
Begin
  If B.P <> Nil Then FreeMem(B.P, B.Cap);
  B.P := Nil; B.N := 0; B.Cap := 0;
End;

{ capacite d'au moins N octets (contenu garde) }
Procedure BufNeed(Var B : TBuf; N : LongInt);
Var Q : PBytes; C : LongInt;
Begin
  If N <= B.Cap Then Exit;
  C := B.Cap * 2;
  If C < 256 Then C := 256;
  While C < N Do C := C * 2;
  GetMem(Q, C);
  If B.N > 0 Then Move(B.P^[0], Q^[0], B.N);
  If B.P <> Nil Then FreeMem(B.P, B.Cap);
  B.P := Q; B.Cap := C;
End;

Procedure BufByte(Var B : TBuf; V : LongInt);
Begin
  If B.N >= B.Cap Then BufNeed(B, B.N + 1);
  B.P^[B.N] := V And 255;
  Inc(B.N);
End;

Procedure BufStr(Var B : TBuf; Const S : String);
Var I : LongInt;
Begin
  BufNeed(B, B.N + Length(S));
  For I := 1 To Length(S) Do
  Begin
    B.P^[B.N] := Ord(S[I]);
    Inc(B.N);
  End;
End;

Procedure BufMem(Var B : TBuf; Const Src; N : LongInt);
Begin
  If N <= 0 Then Exit;
  BufNeed(B, B.N + N);
  Move(Src, B.P^[B.N], N);
  B.N := B.N + N;
End;

Procedure BufAppend(Var B : TBuf; Var S : TBuf; Ofs, N : LongInt);
Begin
  If N <= 0 Then Exit;
  BufNeed(B, B.N + N);
  Move(S.P^[Ofs], B.P^[B.N], N);
  B.N := B.N + N;
End;

Procedure BufCopy(Var D : TBuf; Var S : TBuf);
Begin
  D.N := 0;
  BufAppend(D, S, 0, S.N);
End;

{ chaine depuis le tampon (au plus 250 caracteres) }
Function BufStrAt(Var B : TBuf; Ofs, N : LongInt) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  If N > 250 Then N := 250;
  For I := 0 To N - 1 Do
    If Ofs + I < B.N Then S := S + Chr(B.P^[Ofs + I]);
  BufStrAt := S;
End;

Function IStr(V : LongInt) : String;
Var S : String;
Begin
  Str(V, S);
  IStr := S;
End;

Function MinL(A, B : LongInt) : LongInt;
Begin
  If A < B Then MinL := A Else MinL := B;
End;

Function MaxL(A, B : LongInt) : LongInt;
Begin
  If A > B Then MaxL := A Else MaxL := B;
End;

Function UpStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do S[I] := UpCase(S[I]);
  UpStr := S;
End;

Function LowStr(S : String) : String;
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do
    If (S[I] >= 'A') And (S[I] <= 'Z') Then S[I] := Chr(Ord(S[I]) + 32);
  LowStr := S;
End;

Function TrimS(S : String) : String;
Begin
  While (S <> '') And ((S[1] = ' ') Or (S[1] = #9)) Do Delete(S, 1, 1);
  While (S <> '') And ((S[Length(S)] = ' ') Or (S[Length(S)] = #9) Or
        (S[Length(S)] = #13) Or (S[Length(S)] = #10)) Do
    Delete(S, Length(S), 1);
  TrimS := S;
End;

Const
  HexD : String[16] = '0123456789abcdef';

Function HexB(V : LongInt) : String;
Begin
  HexB := HexD[((V Shr 4) And 15) + 1] + HexD[(V And 15) + 1];
End;

Function Hex8(V : LongInt) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 0 To 7 Do
  Begin
    S := HexD[(V And 15) + 1] + S;
    V := V Shr 4;
  End;
  Hex8 := S;
End;

Function ShaHex(Const H : TSha) : String;
Var S : String; I : LongInt;
Begin
  S := '';
  For I := 0 To 19 Do S := S + HexB(H[I]);
  ShaHex := S;
End;

Function HexVal(C : Char) : LongInt;
Begin
  Case C Of
    '0'..'9' : HexVal := Ord(C) - 48;
    'a'..'f' : HexVal := Ord(C) - 87;
    'A'..'F' : HexVal := Ord(C) - 55;
  Else
    HexVal := -1;
  End;
End;

{ 40 chiffres hexadecimaux -> empreinte ; faux si invalide }
Function ShaParse(Const S : String; Var H : TSha) : Boolean;
Var I, A, B : LongInt;
Begin
  ShaParse := False;
  If Length(S) < 40 Then Exit;
  For I := 0 To 19 Do
  Begin
    A := HexVal(S[I * 2 + 1]); B := HexVal(S[I * 2 + 2]);
    If (A < 0) Or (B < 0) Then Exit;
    H[I] := A * 16 + B;
  End;
  ShaParse := True;
End;

Function ShaEq(Const A, B : TSha) : Boolean;
Var I : LongInt;
Begin
  ShaEq := False;
  For I := 0 To 19 Do If A[I] <> B[I] Then Exit;
  ShaEq := True;
End;

Function ShaIsZero(Const A : TSha) : Boolean;
Begin
  ShaIsZero := ShaEq(A, ShaZero);
End;

{ comparaison (ordre des octets) : -1, 0, 1 }
Function ShaCmp(Const A, B : TSha) : LongInt;
Var I : LongInt;
Begin
  ShaCmp := 0;
  For I := 0 To 19 Do
    If A[I] <> B[I] Then
    Begin
      If A[I] < B[I] Then ShaCmp := -1 Else ShaCmp := 1;
      Exit;
    End;
End;

Procedure ShaFrom(Var B : TBuf; Ofs : LongInt; Var H : TSha);
Var I : LongInt;
Begin
  For I := 0 To 19 Do H[I] := B.P^[Ofs + I];
End;

{ ==================================================================== }
{ SHA-1, CRC-32, Adler-32                                               }
{ ==================================================================== }

Type
  TSha1 = Record
    H0, H1, H2, H3, H4 : LongInt;
    W : Array[0..79] Of LongInt;
    Blk : Array[0..63] Of Byte;
    BN : LongInt;
    Len : LongInt;                     { octets (moins de 512 Mo) }
  End;

Function Rol(X, N : LongInt) : LongInt;
Begin
  Rol := (X Shl N) Or (X Shr (32 - N));
End;

Procedure Sha1Init(Var C : TSha1);
Begin
  C.H0 := $67452301; C.H1 := LongInt($EFCDAB89); C.H2 := LongInt($98BADCFE);
  C.H3 := $10325476; C.H4 := LongInt($C3D2E1F0);
  C.BN := 0; C.Len := 0;
End;

Procedure Sha1Block(Var C : TSha1);
Var I, A, B, Cc, D, E, F, K, T : LongInt;
Begin
  For I := 0 To 15 Do
    C.W[I] := (C.Blk[I * 4] Shl 24) Or (C.Blk[I * 4 + 1] Shl 16) Or
              (C.Blk[I * 4 + 2] Shl 8) Or C.Blk[I * 4 + 3];
  For I := 16 To 79 Do
    C.W[I] := Rol(C.W[I - 3] Xor C.W[I - 8] Xor C.W[I - 14] Xor C.W[I - 16], 1);
  A := C.H0; B := C.H1; Cc := C.H2; D := C.H3; E := C.H4;
  For I := 0 To 79 Do
  Begin
    If I < 20 Then
    Begin
      F := (B And Cc) Or ((Not B) And D); K := $5A827999;
    End
    Else If I < 40 Then
    Begin
      F := B Xor Cc Xor D; K := $6ED9EBA1;
    End
    Else If I < 60 Then
    Begin
      F := (B And Cc) Or (B And D) Or (Cc And D); K := LongInt($8F1BBCDC);
    End
    Else
    Begin
      F := B Xor Cc Xor D; K := LongInt($CA62C1D6);
    End;
    T := Rol(A, 5) + F + E + K + C.W[I];
    E := D; D := Cc; Cc := Rol(B, 30); B := A; A := T;
  End;
  C.H0 := C.H0 + A; C.H1 := C.H1 + B; C.H2 := C.H2 + Cc;
  C.H3 := C.H3 + D; C.H4 := C.H4 + E;
End;

Procedure Sha1Byte(Var C : TSha1; V : LongInt);
Begin
  C.Blk[C.BN] := V;
  Inc(C.BN); Inc(C.Len);
  If C.BN = 64 Then
  Begin
    Sha1Block(C);
    C.BN := 0;
  End;
End;

Procedure Sha1Mem(Var C : TSha1; Var B : TBuf; Ofs, N : LongInt);
Var I : LongInt;
Begin
  For I := Ofs To Ofs + N - 1 Do
  Begin
    C.Blk[C.BN] := B.P^[I];
    Inc(C.BN);
    If C.BN = 64 Then
    Begin
      Sha1Block(C);
      C.BN := 0;
    End;
  End;
  C.Len := C.Len + N;
End;

Procedure Sha1Str(Var C : TSha1; Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do Sha1Byte(C, Ord(S[I]));
End;

Procedure Sha1Final(Var C : TSha1; Var H : TSha);
Var L, I : LongInt;

  Procedure Put(V, At : LongInt);
  Begin
    H[At] := (V Shr 24) And 255; H[At + 1] := (V Shr 16) And 255;
    H[At + 2] := (V Shr 8) And 255; H[At + 3] := V And 255;
  End;

Begin
  L := C.Len;
  Sha1Byte(C, $80);
  While C.BN <> 56 Do Sha1Byte(C, 0);
  { longueur en bits sur 64 bits (moins de 512 Mo) }
  For I := 0 To 2 Do Sha1Byte(C, 0);
  Sha1Byte(C, (L Shr 29) And 7);
  Sha1Byte(C, (L Shr 21) And 255);
  Sha1Byte(C, (L Shr 13) And 255);
  Sha1Byte(C, (L Shr 5) And 255);
  Sha1Byte(C, (L Shl 3) And 255);
  Put(C.H0, 0); Put(C.H1, 4); Put(C.H2, 8); Put(C.H3, 12); Put(C.H4, 16);
End;

Var
  CrcTab : Array[0..255] Of LongInt;
  CrcReady : Boolean;

Procedure CrcInit;
Var I, J, C : LongInt;
Begin
  For I := 0 To 255 Do
  Begin
    C := I;
    For J := 0 To 7 Do
      If (C And 1) <> 0 Then C := LongInt($EDB88320) Xor (C Shr 1)
      Else C := C Shr 1;
    CrcTab[I] := C;
  End;
  CrcReady := True;
End;

Function Crc32(Var B : TBuf; Ofs, N : LongInt) : LongInt;
Var C, I : LongInt;
Begin
  If Not CrcReady Then CrcInit;
  C := LongInt($FFFFFFFF);
  For I := Ofs To Ofs + N - 1 Do
    C := CrcTab[(C Xor B.P^[I]) And 255] Xor (C Shr 8);
  Crc32 := Not C;
End;

Function Adler32(Var B : TBuf; Ofs, N : LongInt) : LongInt;
Var A, S, I : LongInt;
Begin
  A := 1; S := 0;
  For I := Ofs To Ofs + N - 1 Do
  Begin
    A := A + B.P^[I];
    If A >= 65521 Then A := A - 65521;
    S := S + A;
    If S >= 65521 Then S := S - 65521;
  End;
  Adler32 := (S Shl 16) Or A;
End;

{ ==================================================================== }
{ zlib : inflate (blocs stockes, Huffman fixe et dynamique) et deflate  }
{ (blocs stockes)                                                       }
{ ==================================================================== }

Type
  THuff = Record
    Cnt : Array[0..15] Of LongInt;
    Sym : Array[0..287] Of LongInt;
  End;

Var
  ZIn : PBytes;                        { entree de l'inflate }
  ZPos, ZEnd, ZBit, ZBitN : LongInt;
  ZErr : Boolean;
  ZLitW, ZDst, ZFixL, ZFixD : THuff;
  ZFixOk : Boolean;

Const
  LenBase : Array[0..28] Of LongInt = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17,
    19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LenExtra : Array[0..28] Of LongInt = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
    2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DistBase : Array[0..29] Of LongInt = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33,
    49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
    6145, 8193, 12289, 16385, 24577);
  DistExtra : Array[0..29] Of LongInt = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4,
    5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);
  ClOrder : Array[0..18] Of LongInt = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11,
    4, 12, 3, 13, 2, 14, 1, 15);

Function ZBits(N : LongInt) : LongInt;
Var V : LongInt;
Begin
  While ZBitN < N Do
  Begin
    If ZPos >= ZEnd Then
    Begin
      ZErr := True;
      ZBits := 0;
      Exit;
    End;
    ZBit := ZBit Or (ZIn^[ZPos] Shl ZBitN);
    Inc(ZPos);
    ZBitN := ZBitN + 8;
  End;
  V := ZBit And ((1 Shl N) - 1);
  ZBit := ZBit Shr N;
  ZBitN := ZBitN - N;
  ZBits := V;
End;

Procedure HuffBuild(Var H : THuff; Var Lens : Array Of LongInt; N : LongInt);
Var Offs : Array[0..15] Of LongInt; I : LongInt;
Begin
  For I := 0 To 15 Do H.Cnt[I] := 0;
  For I := 0 To N - 1 Do Inc(H.Cnt[Lens[I]]);
  H.Cnt[0] := 0;
  Offs[1] := 0;
  For I := 1 To 14 Do Offs[I + 1] := Offs[I] + H.Cnt[I];
  For I := 0 To N - 1 Do
    If Lens[I] <> 0 Then
    Begin
      H.Sym[Offs[Lens[I]]] := I;
      Inc(Offs[Lens[I]]);
    End;
End;

Function HuffDecode(Var H : THuff) : LongInt;
Var Code, First, Index, Len, C : LongInt;
Begin
  Code := 0; First := 0; Index := 0;
  For Len := 1 To 15 Do
  Begin
    Code := Code Or ZBits(1);
    If ZErr Then Begin HuffDecode := -1; Exit; End;
    C := H.Cnt[Len];
    If Code - C < First Then
    Begin
      HuffDecode := H.Sym[Index + (Code - First)];
      Exit;
    End;
    Index := Index + C;
    First := (First + C) Shl 1;
    Code := Code Shl 1;
  End;
  ZErr := True;
  HuffDecode := -1;
End;

Procedure ZFixed;
Var L : Array[0..287] Of LongInt; I : LongInt;
Begin
  For I := 0 To 143 Do L[I] := 8;
  For I := 144 To 255 Do L[I] := 9;
  For I := 256 To 279 Do L[I] := 7;
  For I := 280 To 287 Do L[I] := 8;
  HuffBuild(ZFixL, L, 288);
  For I := 0 To 29 Do L[I] := 5;
  HuffBuild(ZFixD, L, 30);
  ZFixOk := True;
End;

Function ZCodes(Var Lit, Dst : THuff; Var O : TBuf) : Boolean;
Var S, Len, D, I, K : LongInt;
Begin
  ZCodes := False;
  Repeat
    S := HuffDecode(Lit);
    If S < 0 Then Exit;
    If S < 256 Then
    Begin
      If O.N >= O.Cap Then BufNeed(O, O.N + 1);
      O.P^[O.N] := S; Inc(O.N);
    End
    Else If S > 256 Then
    Begin
      S := S - 257;
      If S > 28 Then Exit;
      Len := LenBase[S] + ZBits(LenExtra[S]);
      D := HuffDecode(Dst);
      If (D < 0) Or (D > 29) Then Exit;
      D := DistBase[D] + ZBits(DistExtra[D]);
      If ZErr Or (D > O.N) Then Exit;
      BufNeed(O, O.N + Len);
      K := O.N - D;
      For I := 0 To Len - 1 Do O.P^[O.N + I] := O.P^[K + I];
      O.N := O.N + Len;
    End;
  Until S = 256;
  ZCodes := Not ZErr;
End;

Function ZDynamic : Boolean;
Var L : Array[0..319] Of LongInt; NL, ND, NC, I, S, Prev, R : LongInt;
    CL : THuff;
Begin
  ZDynamic := False;
  NL := ZBits(5) + 257; ND := ZBits(5) + 1; NC := ZBits(4) + 4;
  For I := 0 To 18 Do L[I] := 0;
  For I := 0 To NC - 1 Do L[ClOrder[I]] := ZBits(3);
  HuffBuild(CL, L, 19);
  I := 0;
  While I < NL + ND Do
  Begin
    S := HuffDecode(CL);
    If S < 0 Then Exit;
    If S < 16 Then
    Begin
      L[I] := S; Inc(I);
    End
    Else
    Begin
      Prev := 0;
      If S = 16 Then
      Begin
        If I = 0 Then Exit;
        Prev := L[I - 1];
        R := 3 + ZBits(2);
      End
      Else If S = 17 Then R := 3 + ZBits(3)
      Else R := 11 + ZBits(7);
      If I + R > NL + ND Then Exit;
      While R > 0 Do
      Begin
        L[I] := Prev; Inc(I); Dec(R);
      End;
    End;
  End;
  If ZErr Then Exit;
  HuffBuild(ZLitW, L, NL);
  For I := 0 To ND - 1 Do L[I] := L[NL + I];
  HuffBuild(ZDst, L, ND);
  ZDynamic := True;
End;

{ flux zlib (en-tete, blocs, Adler-32) de Src a partir de Ofs -> O
  (ajoute) ; Used : octets consommes ; faux si le flux est invalide }
Function ZInflate(Var Src : TBuf; Ofs, Lim : LongInt; Var O : TBuf;
  Var Used : LongInt) : Boolean;
Var Fin, Typ, Len, NLen : LongInt; Ok : Boolean;
Begin
  ZInflate := False;
  Used := 0;
  ZIn := Src.P; ZPos := Ofs; ZEnd := Ofs + Lim; ZBit := 0; ZBitN := 0;
  ZErr := False;
  If Lim < 6 Then Exit;
  If (ZIn^[ZPos] And 15) <> 8 Then Exit;
  ZPos := ZPos + 2;
  If Not ZFixOk Then ZFixed;
  Repeat
    Fin := ZBits(1);
    Typ := ZBits(2);
    If ZErr Then Exit;
    Case Typ Of
      0 :
        Begin
          ZBit := 0; ZBitN := 0;
          If ZPos + 4 > ZEnd Then Exit;
          Len := ZIn^[ZPos] Or (ZIn^[ZPos + 1] Shl 8);
          NLen := ZIn^[ZPos + 2] Or (ZIn^[ZPos + 3] Shl 8);
          ZPos := ZPos + 4;
          If ((Len Xor NLen) And $FFFF) <> $FFFF Then Exit;
          If ZPos + Len > ZEnd Then Exit;
          BufAppend(O, Src, ZPos, Len);
          ZPos := ZPos + Len;
        End;
      1 : If Not ZCodes(ZFixL, ZFixD, O) Then Exit;
      2 :
        Begin
          If Not ZDynamic Then Exit;
          Ok := ZCodes(ZLitW, ZDst, O);
          If Not Ok Then Exit;
        End;
    Else
      Exit;
    End;
  Until Fin = 1;
  { octets entiers restants dans le tampon de bits : rendus }
  ZPos := ZPos - (ZBitN Div 8);
  ZPos := ZPos + 4;                     { Adler-32 }
  If ZPos > ZEnd Then ZPos := ZEnd;
  Used := ZPos - Ofs;
  ZInflate := True;
End;

{ flux zlib de N octets de Src (blocs stockes) -> O (ajoute) }
{ compression : LZ77 (chaines de hachage) + codes de Huffman fixes }
Var
  ZoBuf, ZoCnt : LongInt;
  ZHead : ^TLongArr4;
  ZPrev : ^TLongArr4;

Procedure ZPut(Var O : TBuf; V, N : LongInt);
Begin
  ZoBuf := ZoBuf Or (V Shl ZoCnt);
  Inc(ZoCnt, N);
  While ZoCnt >= 8 Do
  Begin
    BufByte(O, ZoBuf And 255);
    ZoBuf := ZoBuf Shr 8;
    Dec(ZoCnt, 8);
  End;
End;

{ code de Huffman (bits de poids fort d'abord) }
Procedure ZPutRev(Var O : TBuf; Code, N : LongInt);
Var R, I : LongInt;
Begin
  R := 0;
  For I := 1 To N Do
  Begin
    R := (R Shl 1) Or (Code And 1);
    Code := Code Shr 1;
  End;
  ZPut(O, R, N);
End;

Procedure ZEmit(Var O : TBuf; V : LongInt);
Begin
  If V < 144 Then ZPutRev(O, $30 + V, 8)
  Else If V < 256 Then ZPutRev(O, $190 + V - 144, 9)
  Else If V < 280 Then ZPutRev(O, V - 256, 7)
  Else ZPutRev(O, $C0 + V - 280, 8);
End;

Procedure ZMatch(Var O : TBuf; L, D : LongInt);
Var K : LongInt;
Begin
  K := 28;
  While LenBase[K] > L Do Dec(K);
  ZEmit(O, 257 + K);
  If LenExtra[K] > 0 Then ZPut(O, L - LenBase[K], LenExtra[K]);
  K := 29;
  While DistBase[K] > D Do Dec(K);
  ZPutRev(O, K, 5);
  If DistExtra[K] > 0 Then ZPut(O, D - DistBase[K], DistExtra[K]);
End;

Procedure ZDeflate(Var Src : TBuf; Ofs, N : LongInt; Var O : TBuf);
Const HSize = 32768; Win = 32768; MaxChain = 48;
Var I, J, H, A, Best, BestD, L, C, Lim, E : LongInt; P : PBytes;
Begin
  BufByte(O, $78); BufByte(O, $9C);
  If ZHead = Nil Then
  Begin
    GetMem(ZHead, HSize * 4); GetMem(ZPrev, Win * 4);
  End;
  For I := 0 To HSize - 1 Do ZHead^[I] := -1;
  ZoBuf := 0; ZoCnt := 0;
  ZPut(O, 1, 1); ZPut(O, 1, 2);        { bloc final, Huffman fixe }
  P := Src.P;
  E := Ofs + N;
  I := Ofs;
  While I < E Do
  Begin
    Best := 0; BestD := 0;
    If I + 2 < E Then
    Begin
      H := ((P^[I] Shl 10) Xor (P^[I + 1] Shl 5) Xor P^[I + 2]) And
        (HSize - 1);
      J := ZHead^[H];
      C := 0;
      Lim := MinL(258, E - I);
      While (J >= 0) And (I - J <= Win - 1) And (C < MaxChain) Do
      Begin
        If (P^[J + Best] = P^[I + Best]) And (P^[J] = P^[I]) Then
        Begin
          L := 0;
          While (L < Lim) And (P^[J + L] = P^[I + L]) Do Inc(L);
          If L > Best Then
          Begin
            Best := L; BestD := I - J;
            If L >= Lim Then Break;
          End;
        End;
        J := ZPrev^[J And (Win - 1)];
        Inc(C);
      End;
      ZPrev^[I And (Win - 1)] := ZHead^[H];
      ZHead^[H] := I;
    End;
    If Best >= 3 Then
    Begin
      ZMatch(O, Best, BestD);
      { insere les positions couvertes dans les chaines }
      For J := I + 1 To I + Best - 1 Do
        If J + 2 < E Then
        Begin
          H := ((P^[J] Shl 10) Xor (P^[J + 1] Shl 5) Xor P^[J + 2]) And
            (HSize - 1);
          ZPrev^[J And (Win - 1)] := ZHead^[H];
          ZHead^[H] := J;
        End;
      Inc(I, Best);
    End
    Else
    Begin
      ZEmit(O, P^[I]);
      Inc(I);
    End;
  End;
  ZEmit(O, 256);
  If ZoCnt > 0 Then ZPut(O, 0, 8 - ZoCnt);
  A := Adler32(Src, Ofs, N);
  BufByte(O, (A Shr 24) And 255); BufByte(O, (A Shr 16) And 255);
  BufByte(O, (A Shr 8) And 255); BufByte(O, A And 255);
End;
{ ==================================================================== }
{ Fichiers                                                              }
{ ==================================================================== }

Function FileLoad(Const Path : String; Var B : TBuf) : Boolean;
Var F : File; N, R : LongInt;
Begin
  FileLoad := False;
  B.N := 0;
  Assign(F, Path);
  FileMode := 0;
  {$I-} Reset(F, 1); {$I+}
  If IOResult <> 0 Then Exit;
  N := FileSize(F);
  BufNeed(B, N + 1);
  R := 0;
  If N > 0 Then BlockRead(F, B.P^[0], N, R);
  Close(F);
  FileMode := 2;
  B.N := R;
  FileLoad := R = N;
End;

Function FileSave(Const Path : String; Var B : TBuf; Ofs, N : LongInt)
  : Boolean;
Var F : File; W : LongInt;
Begin
  FileSave := False;
  Assign(F, Path);
  {$I-} Rewrite(F, 1); {$I+}
  If IOResult <> 0 Then Exit;
  W := 0;
  If N > 0 Then BlockWrite(F, B.P^[Ofs], N, W);
  Close(F);
  FileSave := (IOResult = 0) And (W = N);
End;

Function FileSaveStr(Const Path, S : String) : Boolean;
Var B : TBuf;
Begin
  BufInit(B);
  BufStr(B, S);
  FileSaveStr := FileSave(Path, B, 0, B.N);
  BufFree(B);
End;

Function FileExist(Const Path : String) : Boolean;
Var F : File;
Begin
  Assign(F, Path);
  FileMode := 0;
  {$I-} Reset(F, 1); {$I+}
  FileExist := IOResult = 0;
  {$I-} Close(F); {$I+}
  If IOResult = 0 Then ;
  FileMode := 2;
End;

Function DirExist(Const Path : String) : Boolean;
Var SR : SearchRec;
Begin
  FindFirst(Path, AnyFile, SR);
  DirExist := (DosError = 0) And ((SR.Attr And Directory) <> 0);
  If DosError = 0 Then FindClose(SR);
End;

Procedure FileDel(Const Path : String);
Var F : File;
Begin
  Assign(F, Path);
  {$I-} Erase(F); {$I+}
  If IOResult = 0 Then ;
End;

Function FileRen(Const A, B : String) : Boolean;
Var F : File;
Begin
  FileDel(B);
  Assign(F, A);
  {$I-} Rename(F, B); {$I+}
  FileRen := IOResult = 0;
End;

Function ParentOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> PS) Do Dec(K);
  ParentOf := Copy(P, 1, K - 1);
End;

Function NameOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> PS) And (P[K] <> '/') Do Dec(K);
  NameOf := Copy(P, K + 1, 255);
End;

{ cree le dossier et ses parents }
Procedure MkDirs(Const P : String);
Begin
  If (P = '') Or DirExist(P) Then Exit;
  If (Length(P) <= 3) And (Pos(':', P) > 0) Then Exit;
  MkDirs(ParentOf(P));
  {$I-} MkDir(P); {$I+}
  If IOResult = 0 Then ;
End;

{ chemin Git (a/b/c) -> chemin du systeme }
Function OsPath(Const S : String) : String;
Var T : String; I : LongInt;
Begin
  T := S;
  For I := 1 To Length(T) Do If T[I] = '/' Then T[I] := PS;
  OsPath := T;
End;

{ heure de modification d'un fichier (format DOS) et taille }
Function FileStat(Const Path : String; Var Size, Tm : LongInt) : Boolean;
Var F : File;
Begin
  FileStat := False;
  Size := 0; Tm := 0;
  Assign(F, Path);
  FileMode := 0;
  {$I-} Reset(F, 1); {$I+}
  FileMode := 2;
  If IOResult <> 0 Then Exit;
  Size := FileSize(F);
  GetFTime(F, Tm);
  Close(F);
  FileStat := True;
End;

{ ==================================================================== }
{ Objets Git : libres (objects/xx/...) et packs (objects/pack)          }
{ ==================================================================== }

Const
  OtCommit = 1; OtTree = 2; OtBlob = 3; OtTag = 4; OtOfsDelta = 6;
  OtRefDelta = 7;
  MaxPack = 100;

Type
  TPack = Record
    Name : String;                     { chemin sans extension }
    Idx, Data : TBuf;                  { .idx et .pack charges }
    N : LongInt;                       { objets }
    Loaded : Boolean;
  End;

Var
  GitDir, WorkDir : String;            { .git et dossier de travail }
  Packs : Array[0..MaxPack - 1] Of TPack;
  PackN : LongInt;
  PacksRead : Boolean;

Function TypeName(T : LongInt) : String;
Begin
  Case T Of
    OtCommit : TypeName := 'commit';
    OtTree : TypeName := 'tree';
    OtBlob : TypeName := 'blob';
    OtTag : TypeName := 'tag';
  Else
    TypeName := '?';
  End;
End;

Function TypeOfName(Const S : String) : LongInt;
Begin
  If S = 'commit' Then TypeOfName := OtCommit
  Else If S = 'tree' Then TypeOfName := OtTree
  Else If S = 'blob' Then TypeOfName := OtBlob
  Else If S = 'tag' Then TypeOfName := OtTag
  Else TypeOfName := 0;
End;

Function ObjPath(Const H : TSha) : String;
Var S : String;
Begin
  S := ShaHex(H);
  ObjPath := GitDir + PS + 'objects' + PS + Copy(S, 1, 2) + PS +
             Copy(S, 3, 38);
End;

{ empreinte d'un objet (en-tete "type taille\0" puis contenu) }
Procedure ObjHash(T : LongInt; Var D : TBuf; Ofs, N : LongInt; Var H : TSha);
Var C : TSha1;
Begin
  Sha1Init(C);
  Sha1Str(C, TypeName(T) + ' ' + IStr(N));
  Sha1Byte(C, 0);
  Sha1Mem(C, D, Ofs, N);
  Sha1Final(C, H);
End;

Procedure PackFree(K : LongInt);
Begin
  BufFree(Packs[K].Idx);
  BufFree(Packs[K].Data);
  Packs[K].Loaded := False;
End;

{ liste des packs (objects/pack/*.idx), relue apres un fetch }
Procedure PacksScan;
Var SR : SearchRec; D : String; K : LongInt;
Begin
  For K := 0 To PackN - 1 Do PackFree(K);
  PackN := 0;
  PacksRead := True;
  D := GitDir + PS + 'objects' + PS + 'pack' + PS;
  FindFirst(D + '*.idx', AnyFile, SR);
  While (DosError = 0) And (PackN < MaxPack) Do
  Begin
    Packs[PackN].Name := D + Copy(SR.Name, 1, Length(SR.Name) - 4);
    BufInit(Packs[PackN].Idx); BufInit(Packs[PackN].Data);
    Packs[PackN].Loaded := False;
    Inc(PackN);
    FindNext(SR);
  End;
  FindClose(SR);
End;

Function BE32(Var B : TBuf; O : LongInt) : LongInt;
Begin
  BE32 := (B.P^[O] Shl 24) Or (B.P^[O + 1] Shl 16) Or (B.P^[O + 2] Shl 8) Or
          B.P^[O + 3];
End;

Procedure PutBE32(Var B : TBuf; V : LongInt);
Begin
  BufByte(B, V Shr 24); BufByte(B, V Shr 16); BufByte(B, V Shr 8);
  BufByte(B, V);
End;

Function PackLoad(K : LongInt) : Boolean;
Begin
  PackLoad := False;
  If Packs[K].Loaded Then Begin PackLoad := True; Exit; End;
  If Not FileLoad(Packs[K].Name + '.idx', Packs[K].Idx) Then Exit;
  If Not FileLoad(Packs[K].Name + '.pack', Packs[K].Data) Then Exit;
  If (Packs[K].Idx.N < 1072) Or (BE32(Packs[K].Idx, 0) <> LongInt($FF744F63))
     Or (BE32(Packs[K].Idx, 4) <> 2) Then
  Begin
    GitErr := 'index de pack non pris en charge : ' + Packs[K].Name;
    Exit;
  End;
  Packs[K].N := BE32(Packs[K].Idx, 8 + 255 * 4);
  Packs[K].Loaded := True;
  PackLoad := True;
End;

{ position de l'objet H dans le pack K (-1 : absent) }
Function PackFind(K : LongInt; Const H : TSha) : LongInt;
Var Lo, Hi, M, C, J : LongInt; T : TSha;
Begin
  PackFind := -1;
  If Not PackLoad(K) Then Exit;
  If H[0] = 0 Then Lo := 0 Else Lo := BE32(Packs[K].Idx, 8 + (H[0] - 1) * 4);
  Hi := BE32(Packs[K].Idx, 8 + H[0] * 4) - 1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    ShaFrom(Packs[K].Idx, 1032 + M * 20, T);
    C := ShaCmp(T, H);
    If C = 0 Then
    Begin
      J := 1032 + Packs[K].N * 24 + M * 4;
      PackFind := BE32(Packs[K].Idx, J);
      Exit;
    End;
    If C < 0 Then Lo := M + 1 Else Hi := M - 1;
  End;
End;

{ delta Git : base + instructions -> O }
Function DeltaApply(Var Base, Dl : TBuf; Var O : TBuf) : Boolean;
Var P, Sz, Sh, C, Ofs, Len : LongInt;

  Function Vint : LongInt;
  Var V, S, B : LongInt;
  Begin
    V := 0; S := 0;
    Repeat
      B := Dl.P^[P]; Inc(P);
      V := V Or ((B And 127) Shl S);
      S := S + 7;
    Until ((B And 128) = 0) Or (P >= Dl.N);
    Vint := V;
  End;

Begin
  DeltaApply := False;
  O.N := 0;
  P := 0;
  Sz := Vint;
  If Sz <> Base.N Then Exit;
  Sz := Vint;
  BufNeed(O, Sz);
  While P < Dl.N Do
  Begin
    C := Dl.P^[P]; Inc(P);
    If (C And 128) <> 0 Then
    Begin
      Ofs := 0; Len := 0;
      For Sh := 0 To 3 Do
        If (C And (1 Shl Sh)) <> 0 Then
        Begin
          Ofs := Ofs Or (Dl.P^[P] Shl (Sh * 8)); Inc(P);
        End;
      For Sh := 0 To 2 Do
        If (C And (16 Shl Sh)) <> 0 Then
        Begin
          Len := Len Or (Dl.P^[P] Shl (Sh * 8)); Inc(P);
        End;
      If Len = 0 Then Len := $10000;
      If (Ofs < 0) Or (Ofs + Len > Base.N) Then Exit;
      BufAppend(O, Base, Ofs, Len);
    End
    Else If C > 0 Then
    Begin
      If P + C > Dl.N Then Exit;
      BufAppend(O, Dl, P, C);
      P := P + C;
    End
    Else Exit;
  End;
  DeltaApply := O.N = Sz;
End;

Function ReadObject(Const H : TSha; Var T : LongInt; Var D : TBuf)
  : Boolean; Forward;

{ en-tete d'un objet de pack a la position Ofs : type, taille, debut
  des donnees ; base d'un delta (OfsBase : position ; RefBase) }
Procedure PackHdr(Var P : TBuf; Ofs : LongInt; Var T, Sz, DataAt,
  OfsBase : LongInt; Var RefBase : TSha);
Var C, Sh, V : LongInt;
Begin
  C := P.P^[Ofs]; Inc(Ofs);
  T := (C Shr 4) And 7;
  Sz := C And 15;
  Sh := 4;
  While (C And 128) <> 0 Do
  Begin
    C := P.P^[Ofs]; Inc(Ofs);
    Sz := Sz Or ((C And 127) Shl Sh);
    Sh := Sh + 7;
  End;
  OfsBase := -1;
  If T = OtOfsDelta Then
  Begin
    C := P.P^[Ofs]; Inc(Ofs);
    V := C And 127;
    While (C And 128) <> 0 Do
    Begin
      C := P.P^[Ofs]; Inc(Ofs);
      V := ((V + 1) Shl 7) Or (C And 127);
    End;
    OfsBase := V;
  End
  Else If T = OtRefDelta Then
  Begin
    ShaFrom(P, Ofs, RefBase);
    Ofs := Ofs + 20;
  End;
  DataAt := Ofs;
End;

Var
  PackRefHookOn : Boolean;             { bases REF_DELTA du pack en cours }

Function IxRefHook(Const H : TSha; Var T : LongInt; Var D : TBuf)
  : Boolean; Forward;

{ objet a la position Ofs du pack P (en memoire), deltas resolus ;
  Raw : longueur des donnees compressees (-1 : inconnue) }
{ cache des objets resolus (bases des chaines de deltas) }
Const
  DcN = 48;
  DcMax = 262144;

Var
  DcKey, DcOfs, DcT : Array[0..DcN - 1] Of LongInt;
  DcBuf : Array[0..DcN - 1] Of TBuf;
  DcNext : LongInt;

Procedure DcClear;
Var I : LongInt;
Begin
  For I := 0 To DcN - 1 Do
  Begin
    DcKey[I] := 0; DcOfs[I] := -1;
    BufFree(DcBuf[I]);
  End;
End;

Function DcGet(Key, Ofs : LongInt; Var T : LongInt; Var D : TBuf) : Boolean;
Var I : LongInt;
Begin
  DcGet := False;
  For I := 0 To DcN - 1 Do
    If (DcOfs[I] = Ofs) And (DcKey[I] = Key) Then
    Begin
      D.N := 0;
      BufAppend(D, DcBuf[I], 0, DcBuf[I].N);
      T := DcT[I];
      DcGet := True;
      Exit;
    End;
End;

Procedure DcPut(Key, Ofs, T : LongInt; Var D : TBuf);
Var I : LongInt;
Begin
  If D.N > DcMax Then Exit;
  I := DcNext;
  DcNext := (DcNext + 1) Mod DcN;
  DcBuf[I].N := 0;
  BufAppend(DcBuf[I], D, 0, D.N);
  DcKey[I] := Key; DcOfs[I] := Ofs; DcT[I] := T;
End;

Function PackObj(Var P : TBuf; Ofs : LongInt; Var T : LongInt; Var D : TBuf;
  Depth : LongInt) : Boolean;
Var Sz, At, OB, U, BT, Key : LongInt; RB : TSha; Dl, Base : TBuf;
    Ok : Boolean;
Begin
  PackObj := False;
  If (Ofs < 12) Or (Ofs >= P.N) Or (Depth > 60) Then Exit;
  Key := P.N Xor (P.P^[P.N - 1] Shl 24) Xor (P.P^[P.N - 2] Shl 16) Xor
    (P.P^[P.N - 3] Shl 8) Xor P.P^[P.N - 4];
  If DcGet(Key, Ofs, T, D) Then
  Begin
    PackObj := True; Exit;
  End;
  PackHdr(P, Ofs, T, Sz, At, OB, RB);
  If (T >= OtCommit) And (T <= OtTag) Then
  Begin
    D.N := 0;
    BufNeed(D, Sz + 1);
    If Not ZInflate(P, At, P.N - At, D, U) Then Exit;
    PackObj := D.N = Sz;
    If (D.N = Sz) And (Depth > 0) Then DcPut(Key, Ofs, T, D);
    Exit;
  End;
  If (T <> OtOfsDelta) And (T <> OtRefDelta) Then Exit;
  BufInit(Dl); BufInit(Base);
  Ok := ZInflate(P, At, P.N - At, Dl, U);
  If Ok Then
  Begin
    If T = OtOfsDelta Then Ok := PackObj(P, Ofs - OB, BT, Base, Depth + 1)
    Else
    Begin
      Ok := False;
      If PackRefHookOn Then Ok := IxRefHook(RB, BT, Base);
      If Not Ok Then Ok := ReadObject(RB, BT, Base);
    End;
  End;
  If Ok Then Ok := DeltaApply(Base, Dl, D);
  T := BT;
  BufFree(Dl); BufFree(Base);
  If Ok And (Depth > 0) Then DcPut(Key, Ofs, T, D);
  PackObj := Ok;
End;

{ lit un objet (libre ou dans un pack) : type et contenu }
Function ReadObject(Const H : TSha; Var T : LongInt; Var D : TBuf) : Boolean;
Var Z, R : TBuf; U, I, K, Sz : LongInt; S : String;
Begin
  ReadObject := False;
  T := 0;
  BufInit(Z);
  If FileLoad(ObjPath(H), Z) Then
  Begin
    BufInit(R);
    If ZInflate(Z, 0, Z.N, R, U) Then
    Begin
      I := 0;
      While (I < R.N) And (R.P^[I] <> 0) Do Inc(I);
      S := BufStrAt(R, 0, I);
      K := Pos(' ', S);
      T := TypeOfName(Copy(S, 1, K - 1));
      Val(Copy(S, K + 1, 20), Sz, K);
      D.N := 0;
      BufAppend(D, R, I + 1, R.N - I - 1);
      ReadObject := (T > 0) And (D.N = Sz);
    End;
    BufFree(R); BufFree(Z);
    Exit;
  End;
  BufFree(Z);
  If Not PacksRead Then PacksScan;
  For K := 0 To PackN - 1 Do
  Begin
    I := PackFind(K, H);
    If I >= 0 Then
    Begin
      ReadObject := PackObj(Packs[K].Data, I, T, D, 0);
      Exit;
    End;
  End;
  GitErr := 'objet introuvable : ' + ShaHex(H);
End;

Function HasObject(Const H : TSha) : Boolean;
Var K : LongInt;
Begin
  HasObject := True;
  If FileExist(ObjPath(H)) Then Exit;
  If Not PacksRead Then PacksScan;
  For K := 0 To PackN - 1 Do
    If PackFind(K, H) >= 0 Then Exit;
  HasObject := False;
End;

{ ecrit un objet libre (s'il n'existe pas) ; H : son empreinte }
Function WriteObject(T : LongInt; Var D : TBuf; Var H : TSha) : Boolean;
Var R, Z : TBuf; P : String;
Begin
  WriteObject := False;
  ObjHash(T, D, 0, D.N, H);
  If HasObject(H) Then Begin WriteObject := True; Exit; End;
  BufInit(R); BufInit(Z);
  BufStr(R, TypeName(T) + ' ' + IStr(D.N));
  BufByte(R, 0);
  BufAppend(R, D, 0, D.N);
  ZDeflate(R, 0, R.N, Z);
  P := ObjPath(H);
  MkDirs(ParentOf(P));
  WriteObject := FileSave(P, Z, 0, Z.N);
  If Not FileExist(P) Then GitErr := ''#233'criture impossible : ' + P;
  BufFree(R); BufFree(Z);
End;

{ ------------------------------------------------------------------ }
{ Pack recu (clone, fetch) : verification, empreintes, fichier .idx    }
{ ------------------------------------------------------------------ }

Type
  TLongArr = Array[0..$3FFFFFF] Of LongInt;
  TPEnt = Record
    Sha : TSha;
    Ofs, Len, Crc, Typ : LongInt;
    Done : Boolean;
  End;
  TPEntArr = Array[0..$3FFFFF] Of TPEnt;
  PPEntArr = ^TPEntArr;

Var
  IxE : PPEntArr;                      { objets du pack en cours d'indexation }
  IxN : LongInt;
  IxP : ^TBuf;
  IxSort : ^TLongArr;

{ base REF_DELTA cherchee parmi les objets deja calcules du pack }
Function IxRefHook(Const H : TSha; Var T : LongInt; Var D : TBuf) : Boolean;
Var I : LongInt;
Begin
  IxRefHook := False;
  For I := 0 To IxN - 1 Do
    If IxE^[I].Done And ShaEq(IxE^[I].Sha, H) Then
    Begin
      IxRefHook := PackObj(IxP^, IxE^[I].Ofs, T, D, 0);
      Exit;
    End;
End;

Procedure IxSortRange(L, R : LongInt);
Var I, J, T : LongInt; P : TSha;
Begin
  I := L; J := R;
  P := IxE^[IxSort^[(L + R) Div 2]].Sha;
  Repeat
    While ShaCmp(IxE^[IxSort^[I]].Sha, P) < 0 Do Inc(I);
    While ShaCmp(IxE^[IxSort^[J]].Sha, P) > 0 Do Dec(J);
    If I <= J Then
    Begin
      T := IxSort^[I]; IxSort^[I] := IxSort^[J]; IxSort^[J] := T;
      Inc(I); Dec(J);
    End;
  Until I > J;
  If L < J Then IxSortRange(L, J);
  If I < R Then IxSortRange(I, R);
End;

{ verifie le pack P, calcule l'empreinte de chaque objet et l'enregistre
  (objects/pack/pack-X.pack et .idx v2) ; Progress : appele avec le
  nombre d'objets traites }
Function IndexPack(Var P : TBuf) : Boolean;
Var Cnt, I, Ofs, T, Sz, At, OB, U, Left, Pass, K : LongInt; RB, H : TSha;
    D, Tmp, X : TBuf; C : TSha1; Prog : Boolean; Nm : String;
Begin
  IndexPack := False;
  If (P.N < 32) Or (BufStrAt(P, 0, 4) <> 'PACK') Then
  Begin
    GitErr := 'pack invalide'; Exit;
  End;
  { somme de controle du pack }
  Sha1Init(C);
  Sha1Mem(C, P, 0, P.N - 20);
  Sha1Final(C, H);
  For I := 0 To 19 Do
    If H[I] <> P.P^[P.N - 20 + I] Then
    Begin
      GitErr := 'somme de contr'#244'le du pack incorrecte'; Exit;
    End;
  Cnt := BE32(P, 8);
  GetMem(IxE, (Cnt + 1) * SizeOf(TPEnt));
  IxN := Cnt; IxP := @P;
  BufInit(D); BufInit(Tmp); BufInit(X);
  { positions et longueurs }
  Ofs := 12;
  For I := 0 To Cnt - 1 Do
  Begin
    PackHdr(P, Ofs, T, Sz, At, OB, RB);
    Tmp.N := 0;
    If Not ZInflate(P, At, P.N - 20 - At, Tmp, U) Then
    Begin
      GitErr := 'objet compress'#233' invalide dans le pack (' + IStr(I) + ')';
      FreeMem(IxE, (Cnt + 1) * SizeOf(TPEnt));
      BufFree(D); BufFree(Tmp); BufFree(X);
      Exit;
    End;
    IxE^[I].Ofs := Ofs;
    IxE^[I].Len := At + U - Ofs;
    IxE^[I].Crc := Crc32(P, Ofs, IxE^[I].Len);
    IxE^[I].Done := False;
    Ofs := At + U;
  End;
  { empreintes (les bases REF_DELTA peuvent venir plus loin : passes) }
  PackRefHookOn := True;
  Left := Cnt; Pass := 0;
  Repeat
    K := Left;
    For I := 0 To Cnt - 1 Do
      If Not IxE^[I].Done Then
        If PackObj(P, IxE^[I].Ofs, T, D, 0) Then
        Begin
          ObjHash(T, D, 0, D.N, IxE^[I].Sha);
          IxE^[I].Typ := T;
          IxE^[I].Done := True;
          Dec(Left);
          If (Left Mod 64) = 0 Then
            GitProgress('Indexation des objets', Cnt - Left, Cnt);
        End;
    Inc(Pass);
  Until (Left = 0) Or (Left = K);
  PackRefHookOn := False;
  If Left > 0 Then
  Begin
    GitErr := IStr(Left) + ' objet(s) du pack sans base';
    FreeMem(IxE, (Cnt + 1) * SizeOf(TPEnt));
    BufFree(D); BufFree(Tmp); BufFree(X);
    Exit;
  End;
  { .idx version 2 }
  GetMem(IxSort, (Cnt + 1) * 4);
  For I := 0 To Cnt - 1 Do IxSort^[I] := I;
  If Cnt > 1 Then IxSortRange(0, Cnt - 1);
  X.N := 0;
  PutBE32(X, LongInt($FF744F63)); PutBE32(X, 2);
  K := 0;
  For I := 0 To 255 Do
  Begin
    While (K < Cnt) And (IxE^[IxSort^[K]].Sha[0] <= I) Do Inc(K);
    PutBE32(X, K);
  End;
  For I := 0 To Cnt - 1 Do BufMem(X, IxE^[IxSort^[I]].Sha, 20);
  For I := 0 To Cnt - 1 Do PutBE32(X, IxE^[IxSort^[I]].Crc);
  For I := 0 To Cnt - 1 Do PutBE32(X, IxE^[IxSort^[I]].Ofs);
  BufAppend(X, P, P.N - 20, 20);
  Sha1Init(C);
  Sha1Mem(C, X, 0, X.N);
  Sha1Final(C, RB);
  BufMem(X, RB, 20);
  Nm := GitDir + PS + 'objects' + PS + 'pack';
  MkDirs(Nm);
  Nm := Nm + PS + 'pack-' + ShaHex(H);
  Prog := FileSave(Nm + '.pack', P, 0, P.N) And FileSave(Nm + '.idx', X, 0, X.N);
  If Not Prog Then GitErr := ''#233'criture du pack impossible';
  FreeMem(IxE, (Cnt + 1) * SizeOf(TPEnt));
  FreeMem(IxSort, (Cnt + 1) * 4);
  BufFree(D); BufFree(Tmp); BufFree(X);
  PacksRead := False;
  IndexPack := Prog;
End;

{ ------------------------------------------------------------------ }
{ Pack a envoyer (push) : objets non deltifies                         }
{ ------------------------------------------------------------------ }

Procedure PackBegin(Var P : TBuf; Cnt : LongInt);
Begin
  P.N := 0;
  BufStr(P, 'PACK');
  PutBE32(P, 2);
  PutBE32(P, Cnt);
End;

Procedure PackAdd(Var P : TBuf; T : LongInt; Var D : TBuf);
Var Sz, C : LongInt;
Begin
  Sz := D.N;
  C := (T Shl 4) Or (Sz And 15);
  Sz := Sz Shr 4;
  While Sz > 0 Do
  Begin
    BufByte(P, C Or 128);
    C := Sz And 127;
    Sz := Sz Shr 7;
  End;
  BufByte(P, C);
  ZDeflate(D, 0, D.N, P);
End;

Procedure PackEnd(Var P : TBuf);
Var C : TSha1; H : TSha;
Begin
  Sha1Init(C);
  Sha1Mem(C, P, 0, P.N);
  Sha1Final(C, H);
  BufMem(P, H, 20);
End;
{ ==================================================================== }
{ Listes de fichiers (arbres aplatis, index, dossier de travail)        }
{ ==================================================================== }

Type
  TFlatE = Record
    Path : String;
    Sha, Old : TSha;
    Mode, Size, MTime, Flag : LongInt;
  End;
  TFlatArr = Array[0..$FFFFF] Of TFlatE;
  PFlatArr = ^TFlatArr;
  TFlat = Record
    E : PFlatArr;
    N, Cap : LongInt;
  End;

Procedure FlatInit(Var F : TFlat);
Begin
  F.E := Nil; F.N := 0; F.Cap := 0;
End;

Procedure FlatFree(Var F : TFlat);
Begin
  If F.E <> Nil Then FreeMem(F.E, F.Cap * SizeOf(TFlatE));
  FlatInit(F);
End;

Function FlatAdd(Var F : TFlat; Const P : String) : LongInt;
Var Q : PFlatArr; C : LongInt;
Begin
  If F.N >= F.Cap Then
  Begin
    C := F.Cap * 2;
    If C < 64 Then C := 64;
    GetMem(Q, C * SizeOf(TFlatE));
    If F.N > 0 Then Move(F.E^[0], Q^[0], F.N * SizeOf(TFlatE));
    If F.E <> Nil Then FreeMem(F.E, F.Cap * SizeOf(TFlatE));
    F.E := Q; F.Cap := C;
  End;
  F.E^[F.N].Path := P;
  F.E^[F.N].Sha := ShaZero; F.E^[F.N].Old := ShaZero;
  F.E^[F.N].Mode := $81A4;             { 100644 }
  F.E^[F.N].Size := 0; F.E^[F.N].MTime := 0; F.E^[F.N].Flag := 0;
  FlatAdd := F.N;
  Inc(F.N);
End;

Procedure FlatSortR(Var F : TFlat; L, R : LongInt);
Var I, J : LongInt; P : String; T : TFlatE;
Begin
  I := L; J := R;
  P := F.E^[(L + R) Div 2].Path;
  Repeat
    While F.E^[I].Path < P Do Inc(I);
    While F.E^[J].Path > P Do Dec(J);
    If I <= J Then
    Begin
      T := F.E^[I]; F.E^[I] := F.E^[J]; F.E^[J] := T;
      Inc(I); Dec(J);
    End;
  Until I > J;
  If L < J Then FlatSortR(F, L, J);
  If I < R Then FlatSortR(F, I, R);
End;

Procedure FlatSort(Var F : TFlat);
Begin
  If F.N > 1 Then FlatSortR(F, 0, F.N - 1);
End;

{ position du chemin P (liste triee), -1 si absent }
Function FlatLower(Var F : TFlat; Const P : String) : LongInt;
Var Lo, Hi, M : LongInt;
Begin
  Lo := 0; Hi := F.N;
  While Lo < Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    If F.E^[M].Path < P Then Lo := M + 1 Else Hi := M;
  End;
  FlatLower := Lo;
End;

Function FlatFind(Var F : TFlat; Const P : String) : LongInt;
Var Lo, Hi, M : LongInt;
Begin
  FlatFind := -1;
  Lo := 0; Hi := F.N - 1;
  While Lo <= Hi Do
  Begin
    M := (Lo + Hi) Div 2;
    If F.E^[M].Path = P Then
    Begin
      FlatFind := M; Exit;
    End;
    If F.E^[M].Path < P Then Lo := M + 1 Else Hi := M - 1;
  End;
End;

Procedure FlatCopy(Var D, S : TFlat);
Var I, K : LongInt;
Begin
  D.N := 0;
  For I := 0 To S.N - 1 Do
  Begin
    K := FlatAdd(D, S.E^[I].Path);
    D.E^[K] := S.E^[I];
  End;
End;

{ ==================================================================== }
{ References (HEAD, refs/heads, refs/remotes, packed-refs) et config    }
{ ==================================================================== }

Function GitPath(Const Rel : String) : String;
Begin
  GitPath := GitDir + PS + OsPath(Rel);
End;

Function FirstLine(Var B : TBuf) : String;
Var I : LongInt;
Begin
  I := 0;
  While (I < B.N) And (B.P^[I] <> 10) And (B.P^[I] <> 13) Do Inc(I);
  FirstLine := BufStrAt(B, 0, I);
End;

{ ligne K (0...) d'un tampon de texte ; faux apres la derniere }
Function BufLine(Var B : TBuf; Var Pos : LongInt; Var S : String) : Boolean;
Var I : LongInt;
Begin
  BufLine := False;
  If Pos >= B.N Then Exit;
  I := Pos;
  While (I < B.N) And (B.P^[I] <> 10) Do Inc(I);
  S := BufStrAt(B, Pos, I - Pos);
  If (S <> '') And (S[Length(S)] = #13) Then Delete(S, Length(S), 1);
  Pos := I + 1;
  BufLine := True;
End;

Function PackedRef(Const Name : String; Var H : TSha) : Boolean;
Var B : TBuf; P : LongInt; S : String;
Begin
  PackedRef := False;
  BufInit(B);
  If FileLoad(GitPath('packed-refs'), B) Then
  Begin
    P := 0;
    While BufLine(B, P, S) Do
      If (Length(S) > 41) And (S[1] <> '#') And (S[1] <> '^') And
         (Copy(S, 42, 255) = Name) Then
      Begin
        PackedRef := ShaParse(S, H);
        Break;
      End;
  End;
  BufFree(B);
End;

{ empreinte d'une reference (suit les references symboliques) }
Function RefRead(Name : String; Var H : TSha) : Boolean;
Var B : TBuf; S : String; K : LongInt;
Begin
  RefRead := False;
  BufInit(B);
  For K := 1 To 5 Do
  Begin
    If FileLoad(GitPath(Name), B) Then
    Begin
      S := TrimS(FirstLine(B));
      If Copy(S, 1, 5) = 'ref: ' Then
      Begin
        Name := TrimS(Copy(S, 6, 255));
        Continue;
      End;
      RefRead := ShaParse(S, H);
    End
    Else RefRead := PackedRef(Name, H);
    Break;
  End;
  BufFree(B);
End;

{ branche de HEAD ('' : HEAD detachee) }
Function HeadRef : String;
Var B : TBuf; S : String;
Begin
  HeadRef := '';
  BufInit(B);
  If FileLoad(GitPath('HEAD'), B) Then
  Begin
    S := TrimS(FirstLine(B));
    If Copy(S, 1, 5) = 'ref: ' Then HeadRef := TrimS(Copy(S, 6, 255));
  End;
  BufFree(B);
End;

Function HeadBranch : String;
Var S : String;
Begin
  S := HeadRef;
  If Copy(S, 1, 11) = 'refs/heads/' Then Delete(S, 1, 11);
  HeadBranch := S;
End;

Function RefWrite(Const Name : String; Const H : TSha) : Boolean;
Var P : String;
Begin
  P := GitPath(Name);
  MkDirs(ParentOf(P));
  RefWrite := FileSaveStr(P, ShaHex(H) + #10);
End;

Procedure SetHead(Const Ref : String);
Begin
  If FileSaveStr(GitPath('HEAD'), 'ref: ' + Ref + #10) Then ;
End;

{ supprime une reference (fichier et ligne de packed-refs) }
Procedure RefDelete(Const Name : String);
Var B, O : TBuf; P : LongInt; S : String; Skip : Boolean;
Begin
  FileDel(GitPath(Name));
  BufInit(B); BufInit(O);
  If FileLoad(GitPath('packed-refs'), B) Then
  Begin
    P := 0; Skip := False;
    While BufLine(B, P, S) Do
    Begin
      If (S <> '') And (S[1] = '^') And Skip Then Continue;
      Skip := (Length(S) > 41) And (Copy(S, 42, 255) = Name);
      If Not Skip Then
      Begin
        BufStr(O, S); BufByte(O, 10);
      End;
    End;
    If FileSave(GitPath('packed-refs'), O, 0, O.N) Then ;
  End;
  BufFree(B); BufFree(O);
End;

Const
  MaxRefs = 400;

Type
  TRefs = Record
    N : LongInt;
    Name : Array[0..MaxRefs - 1] Of String[120];
    Sha : Array[0..MaxRefs - 1] Of TSha;
  End;
  PRefs = ^TRefs;

Procedure RefsAdd(Var R : TRefs; Const Nm : String; Const H : TSha);
Var I : LongInt;
Begin
  For I := 0 To R.N - 1 Do
    If R.Name[I] = Nm Then
    Begin
      R.Sha[I] := H; Exit;
    End;
  If R.N >= MaxRefs Then Exit;
  R.Name[R.N] := Nm; R.Sha[R.N] := H;
  Inc(R.N);
End;

Procedure RefsScanDir(Var R : TRefs; Const Rel : String);
Var SR : SearchRec; B : TBuf; H : TSha; L : TFlat; K, J : LongInt;
Begin
  FlatInit(L);
  FindFirst(GitPath(Rel) + PS + AllFiles, AnyFile, SR);
  While DosError = 0 Do
  Begin
    If (SR.Name <> '.') And (SR.Name <> '..') Then
    Begin
      K := FlatAdd(L, SR.Name);
      L.E^[K].Mode := Ord((SR.Attr And Directory) <> 0);
    End;
    FindNext(SR);
  End;
  FindClose(SR);
  BufInit(B);
  For J := 0 To L.N - 1 Do
    If L.E^[J].Mode <> 0 Then RefsScanDir(R, Rel + '/' + L.E^[J].Path)
    Else If FileLoad(GitPath(Rel + '/' + L.E^[J].Path), B) Then
      If ShaParse(TrimS(FirstLine(B)), H) Then
        RefsAdd(R, Rel + '/' + L.E^[J].Path, H);
  BufFree(B);
  FlatFree(L);
End;

{ references sous Prefix (refs/heads, refs/remotes/origin, refs/tags) }
Procedure RefsList(Var R : TRefs; Const Prefix : String);
Var B : TBuf; P : LongInt; S : String; H : TSha; I, J : LongInt; T : String;
    TH : TSha;
Begin
  R.N := 0;
  BufInit(B);
  If FileLoad(GitPath('packed-refs'), B) Then
  Begin
    P := 0;
    While BufLine(B, P, S) Do
      If (Length(S) > 41) And (S[1] <> '#') And (S[1] <> '^') And
         (Copy(S, 42, Length(Prefix)) = Prefix) Then
        If ShaParse(S, H) Then RefsAdd(R, Copy(S, 42, 255), H);
  End;
  BufFree(B);
  T := Prefix;
  If (T <> '') And (T[Length(T)] = '/') Then Delete(T, Length(T), 1);
  If DirExist(GitPath(T)) Then RefsScanDir(R, T);
  { tri par nom }
  For I := 0 To R.N - 2 Do
    For J := I + 1 To R.N - 1 Do
      If R.Name[J] < R.Name[I] Then
      Begin
        T := R.Name[I]; R.Name[I] := R.Name[J]; R.Name[J] := T;
        TH := R.Sha[I]; R.Sha[I] := R.Sha[J]; R.Sha[J] := TH;
      End;
End;

{ config : [Sect "Sub"] Key = Value }
{ (WPC : le resultat d'une fonction String vit dans un anneau de tampons
  temporaires ; il est affecte une seule fois, a la fin) }
Function CfgGet(Const Sect, Sub, Key : String) : String;
Var B : TBuf; P, K : LongInt; S, Cur, W, R : String;
Begin
  R := '';
  BufInit(B);
  If FileLoad(GitPath('config'), B) Then
  Begin
    P := 0; Cur := '';
    W := LowStr(Sect);
    If Sub <> '' Then W := W + ' "' + Sub + '"';
    While BufLine(B, P, S) Do
    Begin
      S := TrimS(S);
      If (S <> '') And (S[1] = '[') Then
      Begin
        Cur := Copy(S, 2, Length(S) - 2);
        K := Pos(' ', Cur);
        If K = 0 Then Cur := LowStr(Cur)
        Else Cur := LowStr(Copy(Cur, 1, K - 1)) + Copy(Cur, K, 255);
      End
      Else If Cur = W Then
      Begin
        K := Pos('=', S);
        If (K > 0) And (LowStr(TrimS(Copy(S, 1, K - 1))) = LowStr(Key)) Then
          R := TrimS(Copy(S, K + 1, 255));
      End;
    End;
  End;
  BufFree(B);
  CfgGet := R;
End;

Procedure CfgSet(Const Sect, Sub, Key, Value : String);
Var B, O : TBuf; P, K : LongInt; S, Cur, W, T : String; Done, InS : Boolean;
Begin
  BufInit(B); BufInit(O);
  If FileLoad(GitPath('config'), B) Then ;
  P := 0; Cur := ''; Done := False; InS := False;
  W := LowStr(Sect);
  If Sub <> '' Then W := W + ' "' + Sub + '"';
  While BufLine(B, P, S) Do
  Begin
    T := TrimS(S);
    If (T <> '') And (T[1] = '[') Then
    Begin
      If InS And Not Done Then
      Begin
        BufStr(O, #9 + Key + ' = ' + Value + #10); Done := True;
      End;
      Cur := Copy(T, 2, Length(T) - 2);
      K := Pos(' ', Cur);
      If K = 0 Then Cur := LowStr(Cur)
      Else Cur := LowStr(Copy(Cur, 1, K - 1)) + Copy(Cur, K, 255);
      InS := Cur = W;
    End
    Else If InS And Not Done Then
    Begin
      K := Pos('=', T);
      If (K > 0) And (LowStr(TrimS(Copy(T, 1, K - 1))) = LowStr(Key)) Then
      Begin
        S := #9 + Key + ' = ' + Value; Done := True;
      End;
    End;
    BufStr(O, S + #10);
  End;
  If Not Done Then
  Begin
    If Not InS Then
      If Sub = '' Then BufStr(O, '[' + Sect + ']' + #10)
      Else BufStr(O, '[' + Sect + ' "' + Sub + '"]' + #10);
    BufStr(O, #9 + Key + ' = ' + Value + #10);
  End;
  If FileSave(GitPath('config'), O, 0, O.N) Then ;
  BufFree(B); BufFree(O);
End;

{ ==================================================================== }
{ Index (.git/index, version 2)                                         }
{ ==================================================================== }

Function IndexRead(Var F : TFlat) : Boolean;
Var B : TBuf; N, I, O, L, K, Ver : LongInt;
Begin
  IndexRead := False;
  F.N := 0;
  BufInit(B);
  If Not FileLoad(GitPath('index'), B) Then
  Begin
    BufFree(B);
    IndexRead := True;                 { pas d'index : vide }
    Exit;
  End;
  If (B.N < 32) Or (BufStrAt(B, 0, 4) <> 'DIRC') Then
  Begin
    GitErr := 'index invalide'; BufFree(B); Exit;
  End;
  Ver := BE32(B, 4);
  If (Ver < 2) Or (Ver > 3) Then
  Begin
    GitErr := 'index version ' + IStr(Ver) + ' non prise en charge';
    BufFree(B); Exit;
  End;
  N := BE32(B, 8);
  O := 12;
  For I := 0 To N - 1 Do
  Begin
    If O + 62 > B.N Then Break;
    L := (B.P^[O + 60] Shl 8) Or B.P^[O + 61];
    K := L And $FFF;
    If (Ver = 3) And ((L And $4000) <> 0) Then
    Begin
      K := FlatAdd(F, BufStrAt(B, O + 64, K));
      L := 64;
    End
    Else
    Begin
      K := FlatAdd(F, BufStrAt(B, O + 62, K));
      L := 62;
    End;
    F.E^[K].MTime := BE32(B, O + 8);
    F.E^[K].Mode := BE32(B, O + 24);
    F.E^[K].Size := BE32(B, O + 36);
    ShaFrom(B, O + 40, F.E^[K].Sha);
    { longueur : multiple de 8 avec au moins un octet nul }
    L := L + Length(F.E^[K].Path);
    O := O + ((L + 8) Div 8) * 8;
  End;
  BufFree(B);
  FlatSort(F);
  IndexRead := True;
End;

Function IndexWrite(Var F : TFlat) : Boolean;
Var B : TBuf; I, J, L : LongInt; C : TSha1; H : TSha;
Begin
  BufInit(B);
  BufStr(B, 'DIRC');
  PutBE32(B, 2);
  PutBE32(B, F.N);
  For I := 0 To F.N - 1 Do
  Begin
    PutBE32(B, F.E^[I].MTime); PutBE32(B, 0);     { ctime }
    PutBE32(B, F.E^[I].MTime); PutBE32(B, 0);     { mtime }
    PutBE32(B, 0); PutBE32(B, 0);                 { dev, ino }
    PutBE32(B, F.E^[I].Mode);
    PutBE32(B, 0); PutBE32(B, 0);                 { uid, gid }
    PutBE32(B, F.E^[I].Size);
    BufMem(B, F.E^[I].Sha, 20);
    L := MinL(Length(F.E^[I].Path), $FFF);
    BufByte(B, L Shr 8); BufByte(B, L And 255);
    BufStr(B, F.E^[I].Path);
    L := 62 + Length(F.E^[I].Path);
    For J := 1 To ((L + 8) Div 8) * 8 - L Do BufByte(B, 0);
  End;
  Sha1Init(C);
  Sha1Mem(C, B, 0, B.N);
  Sha1Final(C, H);
  BufMem(B, H, 20);
  IndexWrite := FileSave(GitPath('index'), B, 0, B.N);
  BufFree(B);
End;

{ ==================================================================== }
{ Arbres et commits                                                     }
{ ==================================================================== }

Function OctVal(Const S : String) : LongInt;
Var V, I : LongInt;
Begin
  V := 0;
  For I := 1 To Length(S) Do V := V * 8 + Ord(S[I]) - 48;
  OctVal := V;
End;

Function OctStr(V : LongInt) : String;
Var S : String;
Begin
  S := '';
  Repeat
    S := Chr(48 + (V And 7)) + S;
    V := V Shr 3;
  Until V = 0;
  OctStr := S;
End;

{ arbre H aplati (fichiers seulement, chemins Prefix + nom) -> F }
Function TreeFlat(Const H : TSha; Const Prefix : String; Var F : TFlat)
  : Boolean;
Var D : TBuf; T, P, Q, M, K : LongInt; Nm, Md : String; S : TSha;
Begin
  TreeFlat := False;
  BufInit(D);
  If Not ReadObject(H, T, D) Or (T <> OtTree) Then
  Begin
    BufFree(D); Exit;
  End;
  P := 0;
  While P < D.N Do
  Begin
    Q := P;
    While (Q < D.N) And (D.P^[Q] <> 32) Do Inc(Q);
    Md := BufStrAt(D, P, Q - P);
    P := Q + 1; Q := P;
    While (Q < D.N) And (D.P^[Q] <> 0) Do Inc(Q);
    Nm := BufStrAt(D, P, Q - P);
    ShaFrom(D, Q + 1, S);
    P := Q + 21;
    M := OctVal(Md);
    If M = $4000 Then
    Begin
      If Not TreeFlat(S, Prefix + Nm + '/', F) Then
      Begin
        BufFree(D); Exit;
      End;
    End
    Else
    Begin
      K := FlatAdd(F, Prefix + Nm);
      F.E^[K].Sha := S; F.E^[K].Mode := M;
    End;
  End;
  BufFree(D);
  TreeFlat := True;
End;

{ ecrit les arbres de la liste triee F (a partir de I, sous Prefix) }
Function TreeBuild(Var F : TFlat; Var I : LongInt; Const Prefix : String;
  Var H : TSha) : Boolean;
Var D : TBuf; R, Dir : String; K : LongInt; Sub : TSha;
Begin
  TreeBuild := False;
  BufInit(D);
  While (I < F.N) And (Copy(F.E^[I].Path, 1, Length(Prefix)) = Prefix) Do
  Begin
    R := Copy(F.E^[I].Path, Length(Prefix) + 1, 255);
    K := Pos('/', R);
    If K > 0 Then
    Begin
      Dir := Copy(R, 1, K - 1);
      If Not TreeBuild(F, I, Prefix + Dir + '/', Sub) Then
      Begin
        BufFree(D); Exit;
      End;
      BufStr(D, '40000 ' + Dir);
      BufByte(D, 0);
      BufMem(D, Sub, 20);
    End
    Else
    Begin
      BufStr(D, OctStr(F.E^[I].Mode) + ' ' + R);
      BufByte(D, 0);
      BufMem(D, F.E^[I].Sha, 20);
      Inc(I);
    End;
  End;
  TreeBuild := WriteObject(OtTree, D, H);
  BufFree(D);
End;

Function TreeFromFlat(Var F : TFlat; Var H : TSha) : Boolean;
Var I : LongInt;
Begin
  I := 0;
  TreeFromFlat := TreeBuild(F, I, '', H);
End;

Const
  MaxParents = 8;

Type
  TCommit = Record
    Tree : TSha;
    Parent : Array[0..MaxParents - 1] Of TSha;
    PN : LongInt;
    Author, Committer : String;        { Nom <courriel> }
    ATime, CTime : LongInt;            { secondes Unix }
    Summary : String;                  { premiere ligne du message }
  End;

Function ParseIdent(Const S : String; Var Who : String; Var Tm : LongInt)
  : Boolean;
Var K, E : LongInt; R : String;
Begin
  K := Pos('>', S);
  Who := Copy(S, 1, K);
  R := TrimS(Copy(S, K + 1, 255));
  K := Pos(' ', R);
  If K > 0 Then R := Copy(R, 1, K - 1);
  Val(R, Tm, E);
  ParseIdent := E = 0;
End;

{ commit H : en-tete et resume ; Msg (si non Nil) recoit le message }
Function CommitRead(Const H : TSha; Var C : TCommit; Msg : Pointer)
  : Boolean;
Var D : TBuf; T, P : LongInt; S : String; M : ^TBuf;
Begin
  CommitRead := False;
  C.PN := 0; C.Author := ''; C.Committer := ''; C.Summary := '';
  C.ATime := 0; C.CTime := 0;
  BufInit(D);
  If Not ReadObject(H, T, D) Or (T <> OtCommit) Then
  Begin
    BufFree(D); Exit;
  End;
  P := 0;
  While BufLine(D, P, S) Do
  Begin
    If S = '' Then Break;
    If Copy(S, 1, 5) = 'tree ' Then
    Begin
      If ShaParse(Copy(S, 6, 40), C.Tree) Then ;
    End
    Else If Copy(S, 1, 7) = 'parent ' Then
    Begin
      If C.PN < MaxParents Then
      Begin
        If ShaParse(Copy(S, 8, 40), C.Parent[C.PN]) Then Inc(C.PN);
      End;
    End
    Else If Copy(S, 1, 7) = 'author ' Then
    Begin
      If ParseIdent(Copy(S, 8, 255), C.Author, C.ATime) Then ;
    End
    Else If Copy(S, 1, 10) = 'committer ' Then
    Begin
      If ParseIdent(Copy(S, 11, 255), C.Committer, C.CTime) Then ;
    End;
  End;
  If Msg <> Nil Then
  Begin
    M := Msg;
    M^.N := 0;
    BufAppend(M^, D, P, D.N - P);
  End;
  While BufLine(D, P, S) Do
    If TrimS(S) <> '' Then
    Begin
      C.Summary := S; Break;
    End;
  BufFree(D);
  CommitRead := True;
End;

Function NowUnix : LongInt; Forward;

Var
  UserName, UserEmail : String;        { auteur des commits }

{ ecrit un commit ; Parents : 0, 1 ou 2 }
Function CommitWrite(Const Tree : TSha; Var Par : Array Of TSha;
  PN : LongInt; Var Msg : TBuf; Var H : TSha) : Boolean;
Var D : TBuf; I : LongInt; Id : String;
Begin
  BufInit(D);
  BufStr(D, 'tree ' + ShaHex(Tree) + #10);
  For I := 0 To PN - 1 Do BufStr(D, 'parent ' + ShaHex(Par[I]) + #10);
  Id := UserName + ' <' + UserEmail + '> ' + IStr(NowUnix) + ' +0000';
  BufStr(D, 'author ' + Id + #10);
  BufStr(D, 'committer ' + Id + #10#10);
  BufAppend(D, Msg, 0, Msg.N);
  If (Msg.N = 0) Or (Msg.P^[Msg.N - 1] <> 10) Then BufByte(D, 10);
  CommitWrite := WriteObject(OtCommit, D, H);
  BufFree(D);
End;

{ arbre aplati d'un commit (vide si H est nul) }
Function CommitFlat(Const H : TSha; Var F : TFlat) : Boolean;
Var C : TCommit;
Begin
  F.N := 0;
  CommitFlat := True;
  If ShaIsZero(H) Then Exit;
  CommitFlat := False;
  If Not CommitRead(H, C, Nil) Then Exit;
  If Not TreeFlat(C.Tree, '', F) Then Exit;
  FlatSort(F);
  CommitFlat := True;
End;

{ ==================================================================== }
{ Ensembles d'empreintes (table de hachage)                             }
{ ==================================================================== }

Type
  TShaSetArr = Array[0..$3FFFFF] Of TSha;
  TShaSet = Record
    H : ^TShaSetArr;
    Cap, N : LongInt;
  End;

Procedure SetInit(Var S : TShaSet; Cap : LongInt);
Var I : LongInt;
Begin
  S.Cap := 1024;
  While S.Cap < Cap * 2 Do S.Cap := S.Cap * 2;
  GetMem(S.H, S.Cap * 20);
  For I := 0 To S.Cap - 1 Do S.H^[I] := ShaZero;
  S.N := 0;
End;

Procedure SetFree(Var S : TShaSet);
Begin
  If S.H <> Nil Then FreeMem(S.H, S.Cap * 20);
  S.H := Nil; S.N := 0;
End;

Function SetSlot(Var S : TShaSet; Const K : TSha) : LongInt;
Var I : LongInt;
Begin
  I := ((K[0] Shl 16) Or (K[1] Shl 8) Or K[2]) And (S.Cap - 1);
  While Not ShaIsZero(S.H^[I]) And Not ShaEq(S.H^[I], K) Do
    I := (I + 1) And (S.Cap - 1);
  SetSlot := I;
End;

Function SetHas(Var S : TShaSet; Const K : TSha) : Boolean;
Begin
  SetHas := ShaEq(S.H^[SetSlot(S, K)], K);
End;

{ ajoute ; faux s'il y etait deja }
Function SetAdd(Var S : TShaSet; Const K : TSha) : Boolean;
Var I, J : LongInt; Old : ^TShaSetArr; OC : LongInt;
Begin
  SetAdd := False;
  I := SetSlot(S, K);
  If ShaEq(S.H^[I], K) Then Exit;
  S.H^[I] := K;
  Inc(S.N);
  SetAdd := True;
  If S.N * 2 > S.Cap Then
  Begin
    Old := S.H; OC := S.Cap;
    S.Cap := S.Cap * 2;
    GetMem(S.H, S.Cap * 20);
    For J := 0 To S.Cap - 1 Do S.H^[J] := ShaZero;
    For J := 0 To OC - 1 Do
      If Not ShaIsZero(Old^[J]) Then S.H^[SetSlot(S, Old^[J])] := Old^[J];
    FreeMem(Old, OC * 20);
  End;
End;

{ ancetres de H (commits) dans S }
Procedure Ancestors(Const H : TSha; Var S : TShaSet);
Var Q : ^TShaSetArr; QN, QCap, I : LongInt; C : TCommit; X : TSha;
    NQ : ^TShaSetArr;
Begin
  If ShaIsZero(H) Then Exit;
  QCap := 256;
  GetMem(Q, QCap * 20);
  QN := 1; Q^[0] := H;
  While QN > 0 Do
  Begin
    Dec(QN);
    X := Q^[QN];
    If Not SetAdd(S, X) Then Continue;
    If Not CommitRead(X, C, Nil) Then Continue;
    For I := 0 To C.PN - 1 Do
    Begin
      If QN >= QCap Then
      Begin
        GetMem(NQ, QCap * 40);
        Move(Q^[0], NQ^[0], QCap * 20);
        FreeMem(Q, QCap * 20);
        Q := NQ; QCap := QCap * 2;
      End;
      Q^[QN] := C.Parent[I]; Inc(QN);
    End;
  End;
  FreeMem(Q, QCap * 20);
End;

{ base de fusion de A et B (premier ancetre commun trouve en largeur
  depuis B) ; faux s'il n'y en a pas }
Function MergeBase(Const A, B : TSha; Var Base : TSha) : Boolean;
Var SA, Seen : TShaSet; Q : ^TShaSetArr; QH, QT, QCap, I : LongInt;
    C : TCommit; X : TSha; NQ : ^TShaSetArr;
Begin
  MergeBase := False;
  SetInit(SA, 1024); SetInit(Seen, 1024);
  Ancestors(A, SA);
  QCap := 4096;
  GetMem(Q, QCap * 20);
  QH := 0; QT := 1; Q^[0] := B;
  While QH < QT Do
  Begin
    X := Q^[QH]; Inc(QH);
    If SetHas(SA, X) Then
    Begin
      Base := X; MergeBase := True; Break;
    End;
    If Not SetAdd(Seen, X) Then Continue;
    If CommitRead(X, C, Nil) Then
      For I := 0 To C.PN - 1 Do
      Begin
        If QT >= QCap Then
        Begin
          GetMem(NQ, QCap * 40);
          Move(Q^[0], NQ^[0], QCap * 20);
          FreeMem(Q, QCap * 20);
          Q := NQ; QCap := QCap * 2;
        End;
        Q^[QT] := C.Parent[I]; Inc(QT);
      End;
  End;
  FreeMem(Q, QCap * 20);
  SetFree(SA); SetFree(Seen);
End;
Type
  PLongArr = ^TLongArr;

{ ==================================================================== }
{ Dates                                                                 }
{ ==================================================================== }

Function CivilToUnix(Y, Mo, D, H, Mi, S : LongInt) : LongInt;
Var Era, Yoe, Doy, Doe : LongInt;
Begin
  If Mo <= 2 Then Dec(Y);
  If Y >= 0 Then Era := Y Div 400 Else Era := (Y - 399) Div 400;
  Yoe := Y - Era * 400;
  If Mo > 2 Then Doy := (153 * (Mo - 3) + 2) Div 5 + D - 1
  Else Doy := (153 * (Mo + 9) + 2) Div 5 + D - 1;
  Doe := Yoe * 365 + Yoe Div 4 - Yoe Div 100 + Doy;
  CivilToUnix := (Era * 146097 + Doe - 719468) * 86400 + H * 3600 +
    Mi * 60 + S;
End;

Function NowUnix : LongInt;
Var Y, Mo, D, W, H, Mi, S, C : Word;
Begin
  GetDate(Y, Mo, D, W);
  GetTime(H, Mi, S, C);
  NowUnix := CivilToUnix(Y, Mo, D, H, Mi, S);
End;

Function Pad2(V : LongInt) : String;
Begin
  If V < 10 Then Pad2 := '0' + IStr(V) Else Pad2 := IStr(V);
End;

{ AAAA-MM-JJ HH:MM }
Function UnixToStr(T : LongInt) : String;
Var Z, Era, Doe, Yoe, Y, Doy, Mp, D, M, Sec : LongInt;
Begin
  Sec := T Mod 86400;
  Z := T Div 86400;
  If Sec < 0 Then
  Begin
    Inc(Sec, 86400); Dec(Z);
  End;
  Z := Z + 719468;
  If Z >= 0 Then Era := Z Div 146097 Else Era := (Z - 146096) Div 146097;
  Doe := Z - Era * 146097;
  Yoe := (Doe - Doe Div 1460 + Doe Div 36524 - Doe Div 146096) Div 365;
  Y := Yoe + Era * 400;
  Doy := Doe - (365 * Yoe + Yoe Div 4 - Yoe Div 100);
  Mp := (5 * Doy + 2) Div 153;
  D := Doy - (153 * Mp + 2) Div 5 + 1;
  If Mp < 10 Then M := Mp + 3 Else M := Mp - 9;
  If M <= 2 Then Inc(Y);
  UnixToStr := IStr(Y) + '-' + Pad2(M) + '-' + Pad2(D) + ' ' +
    Pad2(Sec Div 3600) + ':' + Pad2((Sec Div 60) Mod 60);
End;

{ ==================================================================== }
{ .gitignore                                                            }
{ ==================================================================== }

Const
  MaxIgn = 300;

Var
  IgnN : LongInt;
  IgnBase : Array[0..MaxIgn - 1] Of String[80];
  IgnPat : Array[0..MaxIgn - 1] Of String[80];
  IgnFl : Array[0..MaxIgn - 1] Of Byte;  { 1 negation 2 dossier 4 ancre }

Function Glob(Const P : String; PI : LongInt; Const S : String;
  SI : LongInt) : Boolean;
Var K : LongInt; Ok, Neg : Boolean;
Begin
  Glob := False;
  While PI <= Length(P) Do
  Begin
    If P[PI] = '*' Then
    Begin
      If (PI < Length(P)) And (P[PI + 1] = '*') Then
      Begin
        Inc(PI, 2);
        If (PI <= Length(P)) And (P[PI] = '/') Then Inc(PI);
        For K := SI To Length(S) + 1 Do
          If (K = SI) Or (S[K - 1] = '/') Or (PI > Length(P)) Then
            If Glob(P, PI, S, K) Then
            Begin
              Glob := True; Exit;
            End;
        Exit;
      End;
      Inc(PI);
      For K := SI To Length(S) + 1 Do
      Begin
        If Glob(P, PI, S, K) Then
        Begin
          Glob := True; Exit;
        End;
        If (K <= Length(S)) And (S[K] = '/') Then Exit;
      End;
      Exit;
    End;
    If SI > Length(S) Then Exit;
    If P[PI] = '?' Then
    Begin
      If S[SI] = '/' Then Exit;
    End
    Else If P[PI] = '[' Then
    Begin
      Inc(PI);
      Neg := (PI <= Length(P)) And ((P[PI] = '!') Or (P[PI] = '^'));
      If Neg Then Inc(PI);
      Ok := False;
      While (PI <= Length(P)) And (P[PI] <> ']') Do
      Begin
        If (PI + 2 <= Length(P)) And (P[PI + 1] = '-') And
           (P[PI + 2] <> ']') Then
        Begin
          If (S[SI] >= P[PI]) And (S[SI] <= P[PI + 2]) Then Ok := True;
          Inc(PI, 3);
        End
        Else
        Begin
          If S[SI] = P[PI] Then Ok := True;
          Inc(PI);
        End;
      End;
      If Ok = Neg Then Exit;
    End
    Else
    Begin
      If P[PI] = '\' Then Inc(PI);
      If (PI > Length(P)) Or (P[PI] <> S[SI]) Then Exit;
    End;
    Inc(PI); Inc(SI);
  End;
  Glob := SI > Length(S);
End;

Procedure IgnAdd(Const Base : String; S : String);
Var F : Byte;
Begin
  S := TrimS(S);
  If (S = '') Or (S[1] = '#') Or (IgnN >= MaxIgn) Then Exit;
  F := 0;
  If S[1] = '!' Then
  Begin
    F := 1; Delete(S, 1, 1);
  End;
  If (S <> '') And (S[Length(S)] = '/') Then
  Begin
    F := F Or 2; Delete(S, Length(S), 1);
  End;
  If Pos('/', S) > 0 Then F := F Or 4;
  If (S <> '') And (S[1] = '/') Then Delete(S, 1, 1);
  If S = '' Then Exit;
  IgnBase[IgnN] := Base; IgnPat[IgnN] := S; IgnFl[IgnN] := F;
  Inc(IgnN);
End;

Procedure IgnLoad(Const Path, Base : String);
Var B : TBuf; P : LongInt; S : String;
Begin
  BufInit(B);
  If FileLoad(Path, B) Then
  Begin
    P := 0;
    While BufLine(B, P, S) Do IgnAdd(Base, S);
  End;
  BufFree(B);
End;

Function Ignored(Const Path : String; IsDir : Boolean) : Boolean;
Var I : LongInt; R : String; Res : Boolean;
Begin
  Res := False;
  For I := 0 To IgnN - 1 Do
  Begin
    If Copy(Path, 1, Length(IgnBase[I])) <> IgnBase[I] Then Continue;
    If ((IgnFl[I] And 2) <> 0) And Not IsDir Then Continue;
    If ((IgnFl[I] And 1) <> 0) = Res Then
    Begin
      R := Copy(Path, Length(IgnBase[I]) + 1, 255);
      If (IgnFl[I] And 4) = 0 Then R := NameOf(R);
      If Glob(IgnPat[I], 1, R, 1) Then Res := Not Res;
    End;
  End;
  Ignored := Res;
End;

{ ==================================================================== }
{ Etat du depot                                                         }
{ ==================================================================== }

Const
  StNew = 1;
  StMod = 2;
  StDel = 3;
  StConf = 4;
  FlSel = $100;                        { fichier coche }

Var
  HeadSha : TSha;
  HeadF, IdxF, WorkF, Chg : TFlat;
  InMerge : Boolean;

{ UTF-8 (Git) <-> ANSI (fenetres) }
Function Utf8ToAnsi(Const S : String) : String;
Var I, C, V : LongInt; R : String;
Begin
  R := '';
  I := 1;
  While I <= Length(S) Do
  Begin
    C := Ord(S[I]);
    If C < 128 Then R := R + Chr(C)
    Else If (C >= $C0) And (C < $E0) And (I < Length(S)) Then
    Begin
      V := ((C And 31) Shl 6) Or (Ord(S[I + 1]) And 63);
      Inc(I);
      If V < 256 Then R := R + Chr(V) Else R := R + '?';
    End
    Else If (C >= $E0) And (C < $F0) And (I + 1 < Length(S)) Then
    Begin
      V := ((C And 15) Shl 12) Or ((Ord(S[I + 1]) And 63) Shl 6) Or
        (Ord(S[I + 2]) And 63);
      Inc(I, 2);
      Case V Of
        $2018, $2019 : R := R + '''';
        $201C, $201D : R := R + '"';
        $2013, $2014 : R := R + '-';
        $2026 : R := R + '...';
        $20AC : R := R + #128;
        Else R := R + '?';
      End;
    End
    Else If C >= $F0 Then
    Begin
      Inc(I, 3); R := R + '?';
    End
    Else R := R + Chr(C);              { octet isole : Latin-1 }
    Inc(I);
  End;
  Utf8ToAnsi := R;
End;

Function AnsiToUtf8(Const S : String) : String;
Var I, C : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do
  Begin
    C := Ord(S[I]);
    If C < 128 Then R := R + S[I]
    Else If C = 128 Then R := R + #226#130#172
    Else R := R + Chr($C0 Or (C Shr 6)) + Chr($80 Or (C And 63));
  End;
  AnsiToUtf8 := R;
End;

Var
  FsAnsi : Boolean;                    { noms de fichiers ANSI (Windows) }

Function WorkPath(Const Rel : String) : String;
Begin
  If FsAnsi Then WorkPath := WorkDir + PS + OsPath(Utf8ToAnsi(Rel))
  Else WorkPath := WorkDir + PS + OsPath(Rel);
End;

Function FsName(Const S : String) : String;
Begin
  If FsAnsi Then FsName := AnsiToUtf8(S) Else FsName := S;
End;

{ vrai si un fichier suivi est sous le dossier Rel/ }
Function TrackedUnder(Const Rel : String) : Boolean;
Var K : LongInt;
Begin
  K := FlatLower(HeadF, Rel + '/');
  TrackedUnder := (K < HeadF.N) And
    (Copy(HeadF.E^[K].Path, 1, Length(Rel) + 1) = Rel + '/');
End;

{ la recherche (FindFirst) n'est pas reentrante sous WPC : le dossier est
  lu en entier avant de descendre dans ses sous-dossiers }
Procedure ScanDir(Const Rel : String; Ign : Boolean);
Var SR : SearchRec; P, D : String; K, J : LongInt; I : Boolean; L : TFlat;
Begin
  If Rel = '' Then D := WorkDir Else D := WorkPath(Rel);
  If Not Ign And (Rel <> '') Then IgnLoad(D + PS + '.gitignore', Rel + '/');
  FlatInit(L);
  FindFirst(D + PS + AllFiles, AnyFile, SR);
  While DosError = 0 Do
  Begin
    If (SR.Name <> '.') And (SR.Name <> '..') And
       ((Rel <> '') Or (SR.Name <> '.git')) And
       ((SR.Attr And VolumeID) = 0) Then
    Begin
      K := FlatAdd(L, SR.Name);
      L.E^[K].Mode := Ord((SR.Attr And Directory) <> 0);
      L.E^[K].Size := SR.Size;
      L.E^[K].MTime := SR.Time;
    End;
    FindNext(SR);
  End;
  FindClose(SR);
  For J := 0 To L.N - 1 Do
  Begin
    If Rel = '' Then P := FsName(L.E^[J].Path)
    Else P := Rel + '/' + FsName(L.E^[J].Path);
    If L.E^[J].Mode <> 0 Then
    Begin
      I := Ign Or Ignored(P, True);
      If Not I Or TrackedUnder(P) Then ScanDir(P, I);
    End
    Else
    Begin
      I := Ign Or Ignored(P, False);
      If Not I Or (FlatFind(HeadF, P) >= 0) Then
      Begin
        K := FlatAdd(WorkF, P);
        WorkF.E^[K].Size := L.E^[J].Size;
        WorkF.E^[K].MTime := L.E^[J].MTime;
      End;
    End;
  End;
  FlatFree(L);
End;

Function BlobOfFile(Const Rel : String; Var H : TSha) : Boolean;
Var B : TBuf;
Begin
  BufInit(B);
  BlobOfFile := FileLoad(WorkPath(Rel), B);
  ObjHash(OtBlob, B, 0, B.N, H);
  BufFree(B);
End;

Function HasConflictMark(Const Rel : String) : Boolean;
Var B : TBuf; P : LongInt; S : String;
Begin
  HasConflictMark := False;
  BufInit(B);
  If FileLoad(WorkPath(Rel), B) Then
  Begin
    P := 0;
    While BufLine(B, P, S) Do
      If Copy(S, 1, 8) = '<<<<<<< ' Then
      Begin
        HasConflictMark := True; Break;
      End;
  End;
  BufFree(B);
End;

{ index = arbre F, avec les informations de fichier quand le contenu du
  dossier de travail correspond }
Function IndexFrom(Var F : TFlat) : Boolean;
Var X : TFlat; I, K : LongInt;
Begin
  FlatInit(X);
  FlatCopy(X, F);
  For I := 0 To X.N - 1 Do
  Begin
    X.E^[I].Size := 0; X.E^[I].MTime := 0;
    K := FlatFind(WorkF, X.E^[I].Path);
    If (K >= 0) And ShaEq(WorkF.E^[K].Sha, X.E^[I].Sha) Then
    Begin
      X.E^[I].Size := WorkF.E^[K].Size;
      X.E^[I].MTime := WorkF.E^[K].MTime;
    End;
  End;
  IndexFrom := IndexWrite(X);
  FlatFree(X);
End;

Procedure ChgAdd(Const P : String; St : LongInt; Const Old, New : TSha;
  Mode : LongInt);
Var K : LongInt;
Begin
  K := FlatAdd(Chg, P);
  Chg.E^[K].Flag := St Or FlSel;
  Chg.E^[K].Old := Old; Chg.E^[K].Sha := New;
  Chg.E^[K].Mode := Mode;
End;

{ calcule HeadF, IdxF, WorkF et Chg (modifications par rapport a HEAD) }
Function RepoStatus : Boolean;
Var I, K, Hashed : LongInt; Same : Boolean; T : TSha;
Begin
  RepoStatus := False;
  PacksScan;
  If Not RefRead('HEAD', HeadSha) Then HeadSha := ShaZero;
  If Not CommitFlat(HeadSha, HeadF) Then
  Begin
    GitErr := 'commit HEAD illisible'; Exit;
  End;
  If Not IndexRead(IdxF) Then IdxF.N := 0;
  Same := IdxF.N = HeadF.N;
  If Same Then
    For I := 0 To HeadF.N - 1 Do
      If (IdxF.E^[I].Path <> HeadF.E^[I].Path) Or
         Not ShaEq(IdxF.E^[I].Sha, HeadF.E^[I].Sha) Then
      Begin
        Same := False; Break;
      End;
  IgnN := 0;
  IgnLoad(WorkDir + PS + '.gitignore', '');
  IgnLoad(GitPath('info/exclude'), '');
  WorkF.N := 0;
  ScanDir('', False);
  FlatSort(WorkF);
  InMerge := FileExist(GitPath('MERGE_HEAD'));
  Chg.N := 0;
  Hashed := 0;
  For I := 0 To WorkF.N - 1 Do
  Begin
    K := FlatFind(IdxF, WorkF.E^[I].Path);
    If (K >= 0) And (IdxF.E^[K].MTime <> 0) And
       (IdxF.E^[K].MTime = WorkF.E^[I].MTime) And
       (IdxF.E^[K].Size = WorkF.E^[I].Size) Then
      WorkF.E^[I].Sha := IdxF.E^[K].Sha
    Else
    Begin
      If (Hashed And 15) = 0 Then
        GitProgress('Analyse des fichiers', I, WorkF.N);
      If BlobOfFile(WorkF.E^[I].Path, T) Then WorkF.E^[I].Sha := T;
      Inc(Hashed);
    End;
    K := FlatFind(HeadF, WorkF.E^[I].Path);
    If K < 0 Then
      ChgAdd(WorkF.E^[I].Path, StNew, ShaZero, WorkF.E^[I].Sha, $81A4)
    Else If Not ShaEq(HeadF.E^[K].Sha, WorkF.E^[I].Sha) Then
    Begin
      If InMerge And HasConflictMark(WorkF.E^[I].Path) Then
        ChgAdd(WorkF.E^[I].Path, StConf, HeadF.E^[K].Sha,
          WorkF.E^[I].Sha, HeadF.E^[K].Mode)
      Else
        ChgAdd(WorkF.E^[I].Path, StMod, HeadF.E^[K].Sha,
          WorkF.E^[I].Sha, HeadF.E^[K].Mode);
    End;
  End;
  For I := 0 To HeadF.N - 1 Do
    If (HeadF.E^[I].Mode <> $E000) And
       (FlatFind(WorkF, HeadF.E^[I].Path) < 0) Then
      ChgAdd(HeadF.E^[I].Path, StDel, HeadF.E^[I].Sha, ShaZero,
        HeadF.E^[I].Mode);
  FlatSort(Chg);
  { met a jour le cache de l'index s'il ne contient rien d'indexe }
  If Same And (Hashed > 0) Then
  Begin
    If IndexFrom(HeadF) Then ;
  End;
  RepoStatus := True;
End;

{ blob du fichier de travail Rel (ecrit dans la base d'objets) }
Function StoreFile(Const Rel : String; Var H : TSha) : Boolean;
Var B : TBuf;
Begin
  BufInit(B);
  StoreFile := FileLoad(WorkPath(Rel), B) And WriteObject(OtBlob, B, H);
  BufFree(B);
End;

Procedure ClearMerge;
Begin
  FileDel(GitPath('MERGE_HEAD'));
  FileDel(GitPath('MERGE_MSG'));
  FileDel(GitPath('MERGE_MODE'));
End;

{ met a jour la branche courante (ou HEAD detachee) }
Function HeadSet(Const H : TSha) : Boolean;
Var R : String;
Begin
  R := HeadRef;
  If R = '' Then R := 'HEAD';
  HeadSet := RefWrite(R, H);
  HeadSha := H;
End;

{ valide les modifications cochees de Chg (apres RepoStatus) }
Function DoCommit(Var Msg : TBuf; Var NewSha : TSha) : Boolean;
Var N : TFlat; I, K, St, PN : LongInt; Tree, H : TSha;
    Par : Array[0..1] Of TSha; B : TBuf; Any : Boolean;
Begin
  DoCommit := False;
  FlatInit(N);
  FlatCopy(N, HeadF);
  Any := False;
  For I := 0 To Chg.N - 1 Do
  Begin
    If (Chg.E^[I].Flag And FlSel) = 0 Then Continue;
    Any := True;
    St := Chg.E^[I].Flag And $FF;
    K := FlatFind(N, Chg.E^[I].Path);
    If St = StDel Then
    Begin
      If K >= 0 Then N.E^[K].Path := '';
    End
    Else
    Begin
      If Not StoreFile(Chg.E^[I].Path, H) Then
      Begin
        GitErr := 'lecture impossible : ' + Chg.E^[I].Path;
        FlatFree(N); Exit;
      End;
      If K < 0 Then
      Begin
        K := FlatAdd(N, Chg.E^[I].Path);
        N.E^[K].Mode := $81A4;
      End;
      N.E^[K].Sha := H;
    End;
  End;
  If Not Any And Not InMerge Then
  Begin
    GitErr := 'aucune modification coch'#233'e'; FlatFree(N); Exit;
  End;
  { retire les chemins effaces }
  K := 0;
  For I := 0 To N.N - 1 Do
    If N.E^[I].Path <> '' Then
    Begin
      N.E^[K] := N.E^[I]; Inc(K);
    End;
  N.N := K;
  FlatSort(N);
  If Not TreeFromFlat(N, Tree) Then
  Begin
    FlatFree(N); Exit;
  End;
  PN := 0;
  If Not ShaIsZero(HeadSha) Then
  Begin
    Par[0] := HeadSha; PN := 1;
  End;
  If InMerge Then
  Begin
    BufInit(B);
    If FileLoad(GitPath('MERGE_HEAD'), B) Then
      If ShaParse(FirstLine(B), Par[PN]) Then Inc(PN);
    BufFree(B);
  End;
  If Not CommitWrite(Tree, Par, PN, Msg, NewSha) Then
  Begin
    FlatFree(N); Exit;
  End;
  If Not HeadSet(NewSha) Then
  Begin
    GitErr := 'mise '#224' jour de la branche impossible'; FlatFree(N); Exit;
  End;
  ClearMerge;
  InMerge := False;
  { contenu de travail des fichiers valides = blob ecrit }
  For I := 0 To N.N - 1 Do
  Begin
    K := FlatFind(WorkF, N.E^[I].Path);
    If K >= 0 Then
    Begin
      St := FlatFind(Chg, N.E^[I].Path);
      If (St >= 0) And ((Chg.E^[St].Flag And FlSel) <> 0) Then
        WorkF.E^[K].Sha := N.E^[I].Sha;
    End;
  End;
  If IndexFrom(N) Then ;
  FlatFree(N);
  DoCommit := True;
End;

Procedure RmEmptyDirs(Rel : String);
Var K : LongInt;
Begin
  Repeat
    K := Length(Rel);
    While (K > 0) And (Rel[K] <> '/') Do Dec(K);
    If K = 0 Then Exit;
    Rel := Copy(Rel, 1, K - 1);
    {$I-} RmDir(WorkPath(Rel)); {$I+}
    If IOResult <> 0 Then Exit;
  Until False;
End;

Function WriteWorkFile(Const Rel : String; Const H : TSha; Mode : LongInt)
  : Boolean;
Var B : TBuf; T : LongInt; P : String;
Begin
  WriteWorkFile := False;
  P := WorkPath(Rel);
  MkDirs(ParentOf(P));
  If Mode = $E000 Then
  Begin
    MkDirs(P); WriteWorkFile := True; Exit;
  End;
  BufInit(B);
  If ReadObject(H, T, B) And (T = OtBlob) Then
    WriteWorkFile := FileSave(P, B, 0, B.N)
  Else GitErr := 'objet manquant ' + ShaHex(H);
  BufFree(B);
End;

{ fait passer le dossier de travail de Cur a Tgt et reecrit l'index }
Function WorkUpdate(Var Cur, Tgt : TFlat) : Boolean;
Var I, K, Sz, Tm : LongInt;
Begin
  WorkUpdate := False;
  For I := 0 To Cur.N - 1 Do
    If FlatFind(Tgt, Cur.E^[I].Path) < 0 Then
    Begin
      FileDel(WorkPath(Cur.E^[I].Path));
      RmEmptyDirs(Cur.E^[I].Path);
    End;
  For I := 0 To Tgt.N - 1 Do
  Begin
    K := FlatFind(Cur, Tgt.E^[I].Path);
    If (K < 0) Or Not ShaEq(Cur.E^[K].Sha, Tgt.E^[I].Sha) Or
       Not FileExist(WorkPath(Tgt.E^[I].Path)) Then
    Begin
      If (I And 7) = 0 Then
        GitProgress('Extraction des fichiers', I, Tgt.N);
      If Not WriteWorkFile(Tgt.E^[I].Path, Tgt.E^[I].Sha, Tgt.E^[I].Mode)
      Then Exit;
    End;
  End;
  { index avec informations de fichier }
  WorkF.N := 0;
  For I := 0 To Tgt.N - 1 Do
  Begin
    K := FlatAdd(WorkF, Tgt.E^[I].Path);
    WorkF.E^[K].Sha := Tgt.E^[I].Sha;
    If FileStat(WorkPath(Tgt.E^[I].Path), Sz, Tm) Then
    Begin
      WorkF.E^[K].Size := Sz; WorkF.E^[K].MTime := Tm;
    End;
  End;
  WorkUpdate := IndexFrom(Tgt);
End;

{ change de commit (branche deja choisie par l'appelant) ; exige un
  dossier de travail propre }
Function CheckoutTo(Const H : TSha) : Boolean;
Var T : TFlat; I : LongInt;
Begin
  CheckoutTo := False;
  For I := 0 To Chg.N - 1 Do
    If (Chg.E^[I].Flag And $FF) <> StNew Then
    Begin
      GitErr := 'des modifications ne sont pas valid'#233'es'; Exit;
    End;
  FlatInit(T);
  If Not CommitFlat(H, T) Then
  Begin
    GitErr := 'commit illisible'; FlatFree(T); Exit;
  End;
  For I := 0 To Chg.N - 1 Do
    If FlatFind(T, Chg.E^[I].Path) >= 0 Then
    Begin
      GitErr := 'le fichier non suivi ' + Chg.E^[I].Path +
        ' serait '#233'cras'#233;
      FlatFree(T); Exit;
    End;
  CheckoutTo := WorkUpdate(HeadF, T);
  FlatCopy(HeadF, T);
  HeadSha := H;
  FlatFree(T);
End;

Function SwitchBranch(Const Name : String) : Boolean;
Var H : TSha;
Begin
  SwitchBranch := False;
  If Not RefRead('refs/heads/' + Name, H) Then
  Begin
    GitErr := 'branche inconnue : ' + Name; Exit;
  End;
  If Not CheckoutTo(H) Then Exit;
  SetHead('refs/heads/' + Name);
  SwitchBranch := True;
End;

{ annule les modifications cochees (retour au contenu de HEAD) }
Function DiscardSel : Boolean;
Var I, St : LongInt;
Begin
  DiscardSel := True;
  For I := 0 To Chg.N - 1 Do
  Begin
    If (Chg.E^[I].Flag And FlSel) = 0 Then Continue;
    St := Chg.E^[I].Flag And $FF;
    If St = StNew Then
    Begin
      FileDel(WorkPath(Chg.E^[I].Path));
      RmEmptyDirs(Chg.E^[I].Path);
    End
    Else If Not WriteWorkFile(Chg.E^[I].Path, Chg.E^[I].Old,
      Chg.E^[I].Mode) Then DiscardSel := False;
  End;
End;

{ ==================================================================== }
{ Comparaison de lignes                                                 }
{ ==================================================================== }

Type
  TLines = Record
    N : LongInt;
    St : ^TLongArr;                    { N + 1 debuts de ligne }
    Hs : ^TLongArr;
  End;

Procedure LinesFree(Var L : TLines);
Begin
  If L.St <> Nil Then FreeMem(L.St, (L.N + 1) * 4);
  If L.Hs <> Nil Then FreeMem(L.Hs, (L.N + 1) * 4);
  L.St := Nil; L.Hs := Nil; L.N := 0;
End;

Procedure LinesOf(Var B : TBuf; Var L : TLines);
Var I, K, H : LongInt;
Begin
  L.N := 0;
  For I := 0 To B.N - 1 Do
    If B.P^[I] = 10 Then Inc(L.N);
  If (B.N > 0) And (B.P^[B.N - 1] <> 10) Then Inc(L.N);
  GetMem(L.St, (L.N + 1) * 4);
  GetMem(L.Hs, (L.N + 1) * 4);
  K := 0; H := 5381;
  L.St^[0] := 0;
  For I := 0 To B.N - 1 Do
  Begin
    If B.P^[I] = 10 Then
    Begin
      L.Hs^[K] := H; Inc(K);
      L.St^[K] := I + 1;
      H := 5381;
    End
    Else If B.P^[I] <> 13 Then H := (H * 33) Xor B.P^[I];
  End;
  If K < L.N Then
  Begin
    L.Hs^[K] := H; L.St^[L.N] := B.N;
  End;
End;

Function LineEq(Var A : TBuf; Var LA : TLines; I : LongInt; Var B : TBuf;
  Var LB : TLines; J : LongInt) : Boolean;
Var N, M, K : LongInt;
Begin
  LineEq := False;
  If LA.Hs^[I] <> LB.Hs^[J] Then Exit;
  N := LA.St^[I + 1] - LA.St^[I];
  M := LB.St^[J + 1] - LB.St^[J];
  { ignore la difference CR/LF de fin de ligne }
  If (N > 1) And (A.P^[LA.St^[I] + N - 2] = 13) Then Dec(N);
  If (M > 1) And (B.P^[LB.St^[J] + M - 2] = 13) Then Dec(M);
  If N <> M Then Exit;
  For K := 0 To N - 2 Do
    If A.P^[LA.St^[I] + K] <> B.P^[LB.St^[J] + K] Then Exit;
  LineEq := True;
End;

Function LineText(Var B : TBuf; Var L : TLines; I : LongInt) : String;
Var N : LongInt;
Begin
  N := L.St^[I + 1] - L.St^[I];
  While (N > 0) And ((B.P^[L.St^[I] + N - 1] = 10) Or
    (B.P^[L.St^[I] + N - 1] = 13)) Do Dec(N);
  LineText := BufStrAt(B, L.St^[I], MinL(N, 250));
End;

Function IsBinary(Var B : TBuf) : Boolean;
Var I : LongInt;
Begin
  IsBinary := False;
  For I := 0 To MinL(B.N, 8000) - 1 Do
    If B.P^[I] = 0 Then
    Begin
      IsBinary := True; Exit;
    End;
End;

Const
  MaxCells = 2000000;

{ correspondance par plus longue sous-suite commune sur [A0,A1) x [B0,B1) }
Procedure MatchDP(Var A : TBuf; Var LA : TLines; Var B : TBuf;
  Var LB : TLines; A0, A1, B0, B1 : LongInt; M : PLongArr);
Type TW = Array[0..$3FFFFFF] Of Word;
Var T : ^TW; N, W, I, J, X, Y : LongInt;
Begin
  N := A1 - A0; W := B1 - B0;
  If (N = 0) Or (W = 0) Then Exit;
  GetMem(T, (N + 1) * (W + 1) * 2);
  { T[i, j] = LCS des suffixes A[A0 + i..], B[B0 + j..] }
  For I := N DownTo 0 Do
    For J := W DownTo 0 Do
      If (I = N) Or (J = W) Then T^[I * (W + 1) + J] := 0
      Else If LineEq(A, LA, A0 + I, B, LB, B0 + J) Then
        T^[I * (W + 1) + J] := T^[(I + 1) * (W + 1) + J + 1] + 1
      Else
      Begin
        X := T^[(I + 1) * (W + 1) + J];
        Y := T^[I * (W + 1) + J + 1];
        If X >= Y Then T^[I * (W + 1) + J] := X
        Else T^[I * (W + 1) + J] := Y;
      End;
  I := 0; J := 0;
  While (I < N) And (J < W) Do
    If LineEq(A, LA, A0 + I, B, LB, B0 + J) Then
    Begin
      M^[A0 + I] := B0 + J; Inc(I); Inc(J);
    End
    Else If T^[(I + 1) * (W + 1) + J] >= T^[I * (W + 1) + J + 1] Then Inc(I)
    Else Inc(J);
  FreeMem(T, (N + 1) * (W + 1) * 2);
End;

{ lignes uniques dans les deux plages, reliees par plus longue suite
  croissante (algorithme de patience), puis comparaison des intervalles }
Procedure MatchRange(Var A : TBuf; Var LA : TLines; Var B : TBuf;
  Var LB : TLines; A0, A1, B0, B1 : LongInt; M : PLongArr; Depth : LongInt);
Var PA, PB, Tl, Pv : ^TLongArr; I, J, K, Cnt, Na, Lo, Hi, Md, Len,
    CA, CB : LongInt;
Begin
  { prefixe et suffixe communs }
  While (A0 < A1) And (B0 < B1) And LineEq(A, LA, A0, B, LB, B0) Do
  Begin
    M^[A0] := B0; Inc(A0); Inc(B0);
  End;
  While (A0 < A1) And (B0 < B1) And LineEq(A, LA, A1 - 1, B, LB, B1 - 1) Do
  Begin
    Dec(A1); Dec(B1); M^[A1] := B1;
  End;
  If (A0 = A1) Or (B0 = B1) Then Exit;
  If (A1 - A0) * (B1 - B0) <= MaxCells Then
  Begin
    MatchDP(A, LA, B, LB, A0, A1, B0, B1, M); Exit;
  End;
  If Depth > 8 Then Exit;
  { couples de lignes uniques (recherche quadratique bornee) }
  Na := A1 - A0;
  GetMem(PA, Na * 4); GetMem(PB, Na * 4);
  Cnt := 0;
  For I := A0 To A1 - 1 Do
  Begin
    CA := 0; CB := 0; K := -1;
    For J := A0 To A1 - 1 Do
      If (LA.Hs^[J] = LA.Hs^[I]) Then Inc(CA);
    If CA <> 1 Then Continue;
    For J := B0 To B1 - 1 Do
      If (LB.Hs^[J] = LA.Hs^[I]) Then
      Begin
        Inc(CB); K := J;
      End;
    If (CB = 1) And LineEq(A, LA, I, B, LB, K) Then
    Begin
      PA^[Cnt] := I; PB^[Cnt] := K; Inc(Cnt);
    End;
  End;
  If Cnt = 0 Then
  Begin
    FreeMem(PA, Na * 4); FreeMem(PB, Na * 4); Exit;
  End;
  { plus longue suite croissante sur PB }
  GetMem(Tl, Cnt * 4); GetMem(Pv, Cnt * 4);
  Len := 0;
  For I := 0 To Cnt - 1 Do
  Begin
    Lo := 0; Hi := Len;
    While Lo < Hi Do
    Begin
      Md := (Lo + Hi) Div 2;
      If PB^[Tl^[Md]] < PB^[I] Then Lo := Md + 1 Else Hi := Md;
    End;
    If Lo > 0 Then Pv^[I] := Tl^[Lo - 1] Else Pv^[I] := -1;
    Tl^[Lo] := I;
    If Lo = Len Then Inc(Len);
  End;
  { remonte la suite dans Tl (ordre croissant) }
  K := Tl^[Len - 1];
  For I := Len - 1 DownTo 0 Do
  Begin
    Tl^[I] := K; K := Pv^[K];
  End;
  CA := A0; CB := B0;
  For I := 0 To Len - 1 Do
  Begin
    J := Tl^[I];
    MatchRange(A, LA, B, LB, CA, PA^[J], CB, PB^[J], M, Depth + 1);
    M^[PA^[J]] := PB^[J];
    CA := PA^[J] + 1; CB := PB^[J] + 1;
  End;
  MatchRange(A, LA, B, LB, CA, A1, CB, B1, M, Depth + 1);
  FreeMem(Tl, Cnt * 4); FreeMem(Pv, Cnt * 4);
  FreeMem(PA, Na * 4); FreeMem(PB, Na * 4);
End;

{ M^[i] = ligne de B correspondant a la ligne i de A, ou -1 }
Procedure LineMatch(Var A : TBuf; Var LA : TLines; Var B : TBuf;
  Var LB : TLines; Var M : PLongArr);
Var I : LongInt;
Begin
  GetMem(M, (LA.N + 1) * 4);
  For I := 0 To LA.N Do M^[I] := -1;
  MatchRange(A, LA, B, LB, 0, LA.N, 0, LB.N, M, 0);
End;

{ Diff affichable : lignes de contexte, ajouts, suppressions, en-tetes }
Const
  DkCtx = 0;
  DkAdd = 1;
  DkDel = 2;
  DkHunk = 3;

Type
  TDiffL = Record
    K : Byte;
    LA, LB : LongInt;                  { numeros de ligne (0...) }
    CA, CB : LongInt;                  { en-tete : nombres de lignes }
  End;
  TDiffArr = Array[0..$FFFFF] Of TDiffL;

Var
  DfA, DfB : TBuf;                     { ancien et nouveau contenu }
  DfLA, DfLB : TLines;
  Df : ^TDiffArr;
  DfN, DfCap : LongInt;
  DfBin : Boolean;
  DfAdd, DfDel : LongInt;

Procedure DfPush(K : Byte; LA, LB : LongInt);
Var Q : ^TDiffArr; C : LongInt;
Begin
  If DfN >= DfCap Then
  Begin
    C := DfCap * 2;
    If C < 256 Then C := 256;
    GetMem(Q, C * SizeOf(TDiffL));
    If DfN > 0 Then Move(Df^[0], Q^[0], DfN * SizeOf(TDiffL));
    If Df <> Nil Then FreeMem(Df, DfCap * SizeOf(TDiffL));
    Df := Q; DfCap := C;
  End;
  Df^[DfN].K := K; Df^[DfN].LA := LA; Df^[DfN].LB := LB;
  Df^[DfN].CA := 0; Df^[DfN].CB := 0;
  Inc(DfN);
End;

{ calcule le diff de DfA vers DfB (a remplir par l'appelant) }
Procedure DiffBuild;
Type TOp = Array[0..$FFFFFF] Of Byte;
Var M, MB : PLongArr; Ops : ^TOp; OI, OJ : ^TLongArr; N, I, J, K, S,
    E, H, Last : LongInt;
Begin
  DfN := 0; DfAdd := 0; DfDel := 0;
  LinesFree(DfLA); LinesFree(DfLB);
  DfBin := IsBinary(DfA) Or IsBinary(DfB);
  If DfBin Then Exit;
  LinesOf(DfA, DfLA); LinesOf(DfB, DfLB);
  LineMatch(DfA, DfLA, DfB, DfLB, M);
  GetMem(MB, (DfLB.N + 1) * 4);
  For J := 0 To DfLB.N Do MB^[J] := -1;
  For I := 0 To DfLA.N - 1 Do
    If M^[I] >= 0 Then MB^[M^[I]] := I;
  { suite d'operations }
  N := DfLA.N + DfLB.N;
  GetMem(Ops, N + 1); GetMem(OI, (N + 1) * 4); GetMem(OJ, (N + 1) * 4);
  I := 0; J := 0; K := 0;
  While (I < DfLA.N) Or (J < DfLB.N) Do
  Begin
    If (I < DfLA.N) And (J < DfLB.N) And (M^[I] = J) Then
    Begin
      Ops^[K] := DkCtx; OI^[K] := I; OJ^[K] := J; Inc(I); Inc(J);
    End
    Else If (I < DfLA.N) And (M^[I] < 0) Then
    Begin
      Ops^[K] := DkDel; OI^[K] := I; OJ^[K] := J; Inc(I); Inc(DfDel);
    End
    Else
    Begin
      Ops^[K] := DkAdd; OI^[K] := I; OJ^[K] := J; Inc(J); Inc(DfAdd);
    End;
    Inc(K);
  End;
  N := K;
  { blocs avec 3 lignes de contexte }
  I := 0; Last := 0;
  While I < N Do
  Begin
    If Ops^[I] = DkCtx Then
    Begin
      Inc(I); Continue;
    End;
    S := MaxL(I - 3, Last);
    E := I;
    { etend tant que deux changements sont separes de <= 6 lignes }
    Repeat
      While (E < N) And (Ops^[E] <> DkCtx) Do Inc(E);
      J := E;
      While (J < N) And (Ops^[J] = DkCtx) And (J - E < 7) Do Inc(J);
      If (J < N) And (Ops^[J] <> DkCtx) Then E := J Else Break;
    Until False;
    E := MinL(E + 3, N);
    H := DfN;
    DfPush(DkHunk, OI^[S], OJ^[S]);
    For J := S To E - 1 Do
    Begin
      DfPush(Ops^[J], OI^[J], OJ^[J]);
      If Ops^[J] <> DkAdd Then Inc(Df^[H].CA);
      If Ops^[J] <> DkDel Then Inc(Df^[H].CB);
    End;
    I := E; Last := E;
  End;
  FreeMem(Ops, DfLA.N + DfLB.N + 1);
  FreeMem(OI, (DfLA.N + DfLB.N + 1) * 4);
  FreeMem(OJ, (DfLA.N + DfLB.N + 1) * 4);
  FreeMem(M, (DfLA.N + 1) * 4);
  FreeMem(MB, (DfLB.N + 1) * 4);
End;

Function DiffText(I : LongInt) : String;
Var S : String;
Begin
  Case Df^[I].K Of
    DkHunk :
    Begin
      If Df^[I].CA = 0 Then S := '@@ -' + IStr(Df^[I].LA)
      Else S := '@@ -' + IStr(Df^[I].LA + 1);
      If Df^[I].CA <> 1 Then S := S + ',' + IStr(Df^[I].CA);
      If Df^[I].CB = 0 Then S := S + ' +' + IStr(Df^[I].LB)
      Else S := S + ' +' + IStr(Df^[I].LB + 1);
      If Df^[I].CB <> 1 Then S := S + ',' + IStr(Df^[I].CB);
      DiffText := S + ' @@';
    End;
    DkDel : DiffText := LineText(DfA, DfLA, Df^[I].LA);
    Else DiffText := LineText(DfB, DfLB, Df^[I].LB);
  End;
End;

{ ==================================================================== }
{ Fusion                                                                }
{ ==================================================================== }

Procedure PutLines(Var O, B : TBuf; Var L : TLines; I0, I1 : LongInt);
Var K : LongInt;
Begin
  If I1 <= I0 Then Exit;
  K := L.St^[I1] - L.St^[I0];
  BufAppend(O, B, L.St^[I0], K);
  If (L.St^[I1] = B.N) And (B.N > 0) And (B.P^[B.N - 1] <> 10) Then
    BufByte(O, 10);
End;

Function RangeEq(Var A : TBuf; Var LA : TLines; A0, A1 : LongInt;
  Var B : TBuf; Var LB : TLines; B0, B1 : LongInt) : Boolean;
Var I : LongInt;
Begin
  RangeEq := False;
  If A1 - A0 <> B1 - B0 Then Exit;
  For I := 0 To A1 - A0 - 1 Do
    If Not LineEq(A, LA, A0 + I, B, LB, B0 + I) Then Exit;
  RangeEq := True;
End;

{ fusion a trois voies ligne par ligne ; faux s'il y a des conflits (R
  recoit alors le texte avec marqueurs) }
Function Merge3(Var Bs, Ou, Th, R : TBuf; Const NameT : String) : Boolean;
Var LB, LO, LT : TLines; MO, MT : PLongArr; I, O, T, J, OE, TE : LongInt;
    Clean : Boolean;
Begin
  R.N := 0;
  LinesOf(Bs, LB); LinesOf(Ou, LO); LinesOf(Th, LT);
  LineMatch(Bs, LB, Ou, LO, MO);
  LineMatch(Bs, LB, Th, LT, MT);
  Clean := True;
  I := 0; O := 0; T := 0;
  While (I < LB.N) Or (O < LO.N) Or (T < LT.N) Do
  Begin
    If (I < LB.N) And (MO^[I] = O) And (MT^[I] = T) Then
    Begin
      PutLines(R, Bs, LB, I, I + 1);
      Inc(I); Inc(O); Inc(T); Continue;
    End;
    { prochain point de synchronisation : ligne de base commune aux
      trois versions }
    J := I;
    While (J < LB.N) And ((MO^[J] < 0) Or (MT^[J] < 0)) Do Inc(J);
    If J < LB.N Then
    Begin
      OE := MO^[J]; TE := MT^[J];
    End
    Else
    Begin
      OE := LO.N; TE := LT.N;
    End;
    If RangeEq(Bs, LB, I, J, Ou, LO, O, OE) Then
      PutLines(R, Th, LT, T, TE)
    Else If RangeEq(Bs, LB, I, J, Th, LT, T, TE) Or
      RangeEq(Ou, LO, O, OE, Th, LT, T, TE) Then
      PutLines(R, Ou, LO, O, OE)
    Else
    Begin
      Clean := False;
      BufStr(R, '<<<<<<< HEAD' + #10);
      PutLines(R, Ou, LO, O, OE);
      BufStr(R, '=======' + #10);
      PutLines(R, Th, LT, T, TE);
      BufStr(R, '>>>>>>> ' + NameT + #10);
    End;
    I := J; O := OE; T := TE;
  End;
  FreeMem(MO, (LB.N + 1) * 4); FreeMem(MT, (LB.N + 1) * 4);
  LinesFree(LB); LinesFree(LO); LinesFree(LT);
  Merge3 := Clean;
End;

Var
  MergeConf : LongInt;                 { nombre de conflits }

Function BlobLoad(Const H : TSha; Var B : TBuf) : Boolean;
Var T : LongInt;
Begin
  B.N := 0;
  If ShaIsZero(H) Then
  Begin
    BlobLoad := True; Exit;
  End;
  BlobLoad := ReadObject(H, T, B) And (T = OtBlob);
End;

{ fusionne le commit Th dans HEAD ; 0 erreur, 1 deja a jour, 2 avance
  rapide, 3 commit de fusion, 4 conflits }
Function DoMerge(Const Th : TSha; Const Name : String) : LongInt;
Var Base, H : TSha; BF, TF, U, RF : TFlat; I, K, KB, KO, KT : LongInt;
    SB, SO, ST : TSha; MB, MOu, MT : LongInt; XB, XO, XT, R : TBuf;
    Par : Array[0..1] Of TSha; Msg : TBuf; Tree : TSha; Fail : Boolean;
Begin
  DoMerge := 0;
  MergeConf := 0;
  For I := 0 To Chg.N - 1 Do
    If (Chg.E^[I].Flag And $FF) <> StNew Then
    Begin
      GitErr := 'validez ou annulez d''abord vos modifications'; Exit;
    End;
  If ShaEq(Th, HeadSha) Then
  Begin
    DoMerge := 1; Exit;
  End;
  If ShaIsZero(HeadSha) Then Base := ShaZero
  Else If Not MergeBase(HeadSha, Th, Base) Then Base := ShaZero;
  If ShaEq(Base, Th) Then
  Begin
    DoMerge := 1; Exit;
  End;
  FlatInit(TF);
  If Not CommitFlat(Th, TF) Then
  Begin
    GitErr := 'commit illisible'; FlatFree(TF); Exit;
  End;
  If ShaEq(Base, HeadSha) Then
  Begin
    { avance rapide }
    If WorkUpdate(HeadF, TF) And HeadSet(Th) Then DoMerge := 2;
    FlatCopy(HeadF, TF);
    FlatFree(TF); Exit;
  End;
  FlatInit(BF); FlatInit(U); FlatInit(RF);
  If Not CommitFlat(Base, BF) Then BF.N := 0;
  { union des chemins }
  For I := 0 To HeadF.N - 1 Do K := FlatAdd(U, HeadF.E^[I].Path);
  For I := 0 To BF.N - 1 Do
    If FlatFind(HeadF, BF.E^[I].Path) < 0 Then K := FlatAdd(U, BF.E^[I].Path);
  FlatSort(U);
  For I := 0 To TF.N - 1 Do
    If (FlatFind(U, TF.E^[I].Path) < 0) Then K := FlatAdd(U, TF.E^[I].Path);
  FlatSort(U);
  BufInit(XB); BufInit(XO); BufInit(XT); BufInit(R);
  Fail := False;
  For I := 0 To U.N - 1 Do
  Begin
    KB := FlatFind(BF, U.E^[I].Path);
    KO := FlatFind(HeadF, U.E^[I].Path);
    KT := FlatFind(TF, U.E^[I].Path);
    SB := ShaZero; SO := ShaZero; ST := ShaZero;
    MB := $81A4; MOu := $81A4; MT := $81A4;
    If KB >= 0 Then Begin SB := BF.E^[KB].Sha; MB := BF.E^[KB].Mode; End;
    If KO >= 0 Then Begin SO := HeadF.E^[KO].Sha; MOu := HeadF.E^[KO].Mode;
      End;
    If KT >= 0 Then Begin ST := TF.E^[KT].Sha; MT := TF.E^[KT].Mode; End;
    If ShaEq(SO, ST) Or ShaEq(ST, SB) Then
    Begin
      { garde la version locale }
      If KO >= 0 Then
      Begin
        K := FlatAdd(RF, U.E^[I].Path);
        RF.E^[K].Sha := SO; RF.E^[K].Mode := MOu;
      End;
    End
    Else If ShaEq(SO, SB) Then
    Begin
      { prend la version de l'autre branche }
      If KT >= 0 Then
      Begin
        K := FlatAdd(RF, U.E^[I].Path);
        RF.E^[K].Sha := ST; RF.E^[K].Mode := MT;
        If Not WriteWorkFile(U.E^[I].Path, ST, MT) Then
        Begin
          Fail := True; Break;
        End;
      End
      Else
      Begin
        FileDel(WorkPath(U.E^[I].Path));
        RmEmptyDirs(U.E^[I].Path);
      End;
    End
    Else
    Begin
      { modifie des deux cotes }

      If BlobLoad(SB, XB) And BlobLoad(SO, XO) And BlobLoad(ST, XT) Then
      Begin
        If (KO < 0) Or (KT < 0) Then
        Begin
          { supprime d'un cote, modifie de l'autre : conflit }
          Inc(MergeConf);
          If KO < 0 Then BufCopy(R, XT) Else BufCopy(R, XO);
        End
        Else If IsBinary(XO) Or IsBinary(XT) Then
        Begin
          Inc(MergeConf);
          BufCopy(R, XO);
        End
        Else If Not Merge3(XB, XO, XT, R, Name) Then Inc(MergeConf);
        If Not WriteObject(OtBlob, R, H) Then
        Begin
          Fail := True; Break;
        End;
        K := FlatAdd(RF, U.E^[I].Path);
        RF.E^[K].Sha := H; RF.E^[K].Mode := MOu;
        If KO < 0 Then RF.E^[K].Mode := MT;
        If Not FileSave(WorkPath(U.E^[I].Path), R, 0, R.N) Then
        Begin
          MkDirs(ParentOf(WorkPath(U.E^[I].Path)));
          If FileSave(WorkPath(U.E^[I].Path), R, 0, R.N) Then ;
        End;
      End
      Else
      Begin
        Fail := True; Break;
      End;
    End;
  End;
  If Fail Then
  Begin
    GitErr := 'fusion interrompue : ' + U.E^[I].Path;
  End
  Else
  Begin
    BufInit(Msg);
    BufStr(Msg, 'Merge ' + Name + #10);
    FlatSort(RF);
    If MergeConf > 0 Then
    Begin
      If FileSaveStr(GitPath('MERGE_HEAD'), ShaHex(Th) + #10) Then ;
      If FileSave(GitPath('MERGE_MSG'), Msg, 0, Msg.N) Then ;
      If FileSaveStr(GitPath('MERGE_MODE'), '') Then ;
      InMerge := True;
      DoMerge := 4;
    End
    Else If TreeFromFlat(RF, Tree) Then
    Begin
      Par[0] := HeadSha; Par[1] := Th;
      If CommitWrite(Tree, Par, 2, Msg, H) And HeadSet(H) Then
      Begin
        WorkF.N := 0;
        For I := 0 To RF.N - 1 Do
        Begin
          K := FlatAdd(WorkF, RF.E^[I].Path);
          WorkF.E^[K].Sha := RF.E^[I].Sha;
          If FileStat(WorkPath(RF.E^[I].Path), MB, MT) Then
          Begin
            WorkF.E^[K].Size := MB; WorkF.E^[K].MTime := MT;
          End;
        End;
        If IndexFrom(RF) Then ;
        FlatCopy(HeadF, RF);
        DoMerge := 3;
      End;
    End;
    BufFree(Msg);
  End;
  BufFree(XB); BufFree(XO); BufFree(XT); BufFree(R);
  FlatFree(BF); FlatFree(TF); FlatFree(U); FlatFree(RF);
End;

{ ==================================================================== }
{ Historique                                                            }
{ ==================================================================== }

Type
  THist = Record
    Sha : TSha;
    Summary : String[120];
    Author : String[60];
    Time : LongInt;
  End;
  THistArr = Array[0..20000] Of THist;

Var
  Hist : ^THistArr;
  HistN, HistCap : LongInt;

Procedure HistLoad(Const Start : TSha; Max : LongInt);
Var Q : ^TShaSetArr; QT : ^TLongArr; QN, QCap, I, B : LongInt;
    Seen : TShaSet; C : TCommit; X : TSha; K : LongInt;
Begin
  If Hist <> Nil Then FreeMem(Hist, HistCap * SizeOf(THist));
  HistCap := Max;
  GetMem(Hist, HistCap * SizeOf(THist));
  HistN := 0;
  If ShaIsZero(Start) Then Exit;
  QCap := 1024;
  GetMem(Q, QCap * 20); GetMem(QT, QCap * 4);
  SetInit(Seen, 1024);
  QN := 1; Q^[0] := Start; QT^[0] := 0;
  If SetAdd(Seen, Start) Then ;
  While (QN > 0) And (HistN < Max) Do
  Begin
    { le plus recent d'abord }
    B := 0;
    For I := 1 To QN - 1 Do
      If QT^[I] > QT^[B] Then B := I;
    X := Q^[B];
    Dec(QN);
    Q^[B] := Q^[QN]; QT^[B] := QT^[QN];
    If Not CommitRead(X, C, Nil) Then Continue;
    Hist^[HistN].Sha := X;
    Hist^[HistN].Summary := Copy(C.Summary, 1, 120);
    K := Pos(' <', C.Author);
    If K > 0 Then Hist^[HistN].Author := Copy(C.Author, 1, MinL(K - 1, 60))
    Else Hist^[HistN].Author := Copy(C.Author, 1, 60);
    Hist^[HistN].Time := C.CTime;
    Inc(HistN);
    For I := 0 To C.PN - 1 Do
      If SetAdd(Seen, C.Parent[I]) And (QN < QCap) Then
      Begin
        Q^[QN] := C.Parent[I];
        QT^[QN] := C.CTime;            { approximation : date de l'enfant }
        Inc(QN);
      End;
  End;
  FreeMem(Q, QCap * 20); FreeMem(QT, QCap * 4);
  SetFree(Seen);
End;

{ fichiers modifies par le commit H (par rapport a son premier parent) }
Function CommitChanges(Const H : TSha; Var Out : TFlat) : Boolean;
Var C : TCommit; A, B : TFlat; I, K : LongInt;
Begin
  CommitChanges := False;
  Out.N := 0;
  If Not CommitRead(H, C, Nil) Then Exit;
  FlatInit(A); FlatInit(B);
  If C.PN > 0 Then
    If Not CommitFlat(C.Parent[0], A) Then A.N := 0;
  If Not TreeFlat(C.Tree, '', B) Then B.N := 0;
  FlatSort(B);
  For I := 0 To B.N - 1 Do
  Begin
    K := FlatFind(A, B.E^[I].Path);
    If K < 0 Then
    Begin
      K := FlatAdd(Out, B.E^[I].Path);
      Out.E^[K].Flag := StNew; Out.E^[K].Sha := B.E^[I].Sha;
    End
    Else If Not ShaEq(A.E^[K].Sha, B.E^[I].Sha) Then
    Begin
      K := FlatAdd(Out, B.E^[I].Path);
      Out.E^[K].Flag := StMod; Out.E^[K].Sha := B.E^[I].Sha;
      Out.E^[K].Old := A.E^[FlatFind(A, B.E^[I].Path)].Sha;
    End;
  End;
  For I := 0 To A.N - 1 Do
    If FlatFind(B, A.E^[I].Path) < 0 Then
    Begin
      K := FlatAdd(Out, A.E^[I].Path);
      Out.E^[K].Flag := StDel; Out.E^[K].Old := A.E^[I].Sha;
    End;
  FlatSort(Out);
  FlatFree(A); FlatFree(B);
  CommitChanges := True;
End;
{ ==================================================================== }
{ Transport (implante par la plate-forme)                               }
{ ==================================================================== }

{ requete HTTP(S) ; Hdr : en-tetes supplementaires separes par #13#10 }
Function HttpReq(Const Method, Url, Hdr : String; Var Body, Resp : TBuf;
  Var Status : LongInt) : Boolean; Forward;
Function TcpOpen(Const Host : String; Port : LongInt) : LongInt; Forward;
Function TcpSend(H : LongInt; Var B : TBuf; Ofs, N : LongInt) : Boolean;
  Forward;
{ ajoute a B ce qui est recu ; 0 : connexion fermee, -1 : erreur }
Function TcpRecv(H : LongInt; Var B : TBuf) : LongInt; Forward;
Procedure TcpClose(H : LongInt); Forward;

{ ==================================================================== }
{ Base64, URL, pkt-line                                                 }
{ ==================================================================== }

Const
  B64 : String[64] =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

Function Base64(Const S : String) : String;
Var I, V, N : LongInt; R : String;
Begin
  R := '';
  I := 1;
  While I <= Length(S) Do
  Begin
    N := MinL(3, Length(S) - I + 1);
    V := Ord(S[I]) Shl 16;
    If N > 1 Then V := V Or (Ord(S[I + 1]) Shl 8);
    If N > 2 Then V := V Or Ord(S[I + 2]);
    R := R + B64[(V Shr 18) + 1] + B64[((V Shr 12) And 63) + 1];
    If N > 1 Then R := R + B64[((V Shr 6) And 63) + 1] Else R := R + '=';
    If N > 2 Then R := R + B64[(V And 63) + 1] Else R := R + '=';
    Inc(I, 3);
  End;
  Base64 := R;
End;

Var
  UrlScheme, UrlHost, UrlPath : String;
  UrlPort : LongInt;

{ decoupe http[s]://hote[:port]/chemin ou git://hote[:port]/chemin }
Function UrlSplit(U : String) : Boolean;
Var K, E : LongInt;
Begin
  UrlSplit := False;
  K := Pos('://', U);
  If K = 0 Then Exit;
  UrlScheme := LowStr(Copy(U, 1, K - 1));
  Delete(U, 1, K + 2);
  K := Pos('@', U);
  If (K > 0) And (K < Pos('/', U)) Then Delete(U, 1, K);
  K := Pos('/', U);
  If K = 0 Then
  Begin
    UrlHost := U; UrlPath := '/';
  End
  Else
  Begin
    UrlHost := Copy(U, 1, K - 1); UrlPath := Copy(U, K, 255);
  End;
  If UrlScheme = 'https' Then UrlPort := 443
  Else If UrlScheme = 'git' Then UrlPort := 9418
  Else UrlPort := 80;
  K := Pos(':', UrlHost);
  If K > 0 Then
  Begin
    Val(Copy(UrlHost, K + 1, 10), UrlPort, E);
    UrlHost := Copy(UrlHost, 1, K - 1);
  End;
  UrlSplit := (UrlHost <> '') And ((UrlScheme = 'http') Or
    (UrlScheme = 'https') Or (UrlScheme = 'git'));
End;

Procedure PktStr(Var B : TBuf; Const S : String);
Var L : LongInt;
Begin
  L := Length(S) + 4;
  BufStr(B, HexB(L Shr 8) + HexB(L And 255));
  BufStr(B, S);
End;

{ ligne pkt « A NUL C » (WPC perd #0 dans les concatenations) ;
  Nul2 : NUL final }
Procedure PktStr0(Var B : TBuf; Const A, C : String; Nul2 : Boolean);
Var L : LongInt;
Begin
  L := Length(A) + 1 + Length(C) + 4;
  If Nul2 Then Inc(L);
  BufStr(B, HexB(L Shr 8) + HexB(L And 255));
  BufStr(B, A);
  BufByte(B, 0);
  BufStr(B, C);
  If Nul2 Then BufByte(B, 0);
End;

Procedure PktFlush(Var B : TBuf);
Begin
  BufStr(B, '0000');
End;

{ ligne pkt a Pp : Ofs/Len du contenu (Len = -1 : vidage) ; faux si
  la ligne est incomplete }
Function PktNext(Var B : TBuf; Var Pp, Ofs, Len : LongInt) : Boolean;
Var I, V : LongInt;
Begin
  PktNext := False;
  If Pp + 4 > B.N Then Exit;
  V := 0;
  For I := 0 To 3 Do V := V * 16 + HexVal(Chr(B.P^[Pp + I]));
  If V < 4 Then
  Begin
    Ofs := Pp + 4; Len := -1; Inc(Pp, 4);
    PktNext := True; Exit;
  End;
  If Pp + V > B.N Then Exit;
  Ofs := Pp + 4; Len := V - 4;
  Inc(Pp, V);
  { retire le saut de ligne final }
  If (Len > 0) And (B.P^[Ofs + Len - 1] = 10) Then Dec(Len);
  PktNext := True;
End;

Function BufFind(Var B : TBuf; Ofs, N : LongInt; Const S : String)
  : LongInt;
Var I, J : LongInt; Ok : Boolean;
Begin
  BufFind := -1;
  For I := Ofs To Ofs + N - Length(S) Do
  Begin
    Ok := True;
    For J := 1 To Length(S) Do
      If B.P^[I + J - 1] <> Ord(S[J]) Then
      Begin
        Ok := False; Break;
      End;
    If Ok Then
    Begin
      BufFind := I; Exit;
    End;
  End;
End;

{ ==================================================================== }
{ Session distante                                                      }
{ ==================================================================== }

Var
  RemUrl : String;                     { URL du depot distant }
  RemUser, RemPass : String;           { authentification HTTP }
  RemRefs : TRefs;                     { references annoncees }
  RemHead : String;                    { branche par defaut distante }
  RemSock : LongInt;
  RemCaps : String;                    { capacites utiles }
  AgentName : String;
  LocRefs : TRefs;

Function AuthHdr : String;
Begin
  If (RemUser = '') And (RemPass = '') Then AuthHdr := ''
  Else AuthHdr := 'Authorization: Basic ' + Base64(RemUser + ':' + RemPass)
    + #13#10;
End;

Function HttpErr(St : LongInt) : String;
Begin
  Case St Of
    401 : HttpErr := 'authentification requise ou refus'#233'e (401)';
    403 : HttpErr := 'acc'#232's refus'#233' (403)';
    404 : HttpErr := 'd'#233'p'#244't introuvable (404)';
    Else HttpErr := 'erreur HTTP ' + IStr(St);
  End;
End;

{ analyse l'annonce des references a partir de Pp }
Function ParseAdvert(Var B : TBuf; Pp : LongInt) : Boolean;
Var Ofs, Len, K, E : LongInt; H : TSha; Nm : String; First : Boolean;
Begin
  ParseAdvert := False;
  RemRefs.N := 0; RemHead := ''; RemCaps := '';
  First := True;
  While PktNext(B, Pp, Ofs, Len) Do
  Begin
    If Len < 0 Then
    Begin
      ParseAdvert := True; Exit;
    End;
    If (Len >= 4) And (BufStrAt(B, Ofs, 4) = 'ERR ') Then
    Begin
      GitErr := 'serveur : ' + BufStrAt(B, Ofs + 4, MinL(Len - 4, 200));
      Exit;
    End;
    If Len < 41 Then Continue;
    If Not ShaParse(BufStrAt(B, Ofs, 40), H) Then Continue;
    E := Ofs + Len;
    K := Ofs + 41;
    While (K < E) And (B.P^[K] <> 0) Do Inc(K);
    Nm := BufStrAt(B, Ofs + 41, MinL(K - Ofs - 41, 200));
    If First Then
    Begin
      First := False;
      If K < E Then
      Begin
        If BufFind(B, K, E - K, ' ofs-delta') >= 0 Then
          RemCaps := RemCaps + ' ofs-delta';
        If BufFind(B, K, E - K, 'report-status') >= 0 Then
          RemCaps := RemCaps + ' report-status';
        Len := BufFind(B, K, E - K, 'symref=HEAD:');
        If Len >= 0 Then
        Begin
          Len := Len + 12;
          Ofs := Len;
          While (Ofs < E) And (B.P^[Ofs] <> 32) Do Inc(Ofs);
          RemHead := BufStrAt(B, Len, Ofs - Len);
        End;
      End;
      If Nm = 'capabilities^{}' Then Continue;
    End;
    If (Copy(Nm, 1, 11) = 'refs/heads/') Or
       ((Copy(Nm, 1, 10) = 'refs/tags/') And (Pos('^{}', Nm) = 0)) Then
      RefsAdd(RemRefs, Nm, H)
    Else If (Nm = 'HEAD') And (RemHead = '') Then
      RefsAdd(RemRefs, Nm, H);
  End;
  GitErr := 'annonce des r'#233'f'#233'rences tronqu'#233'e';
End;

Procedure RemClose;
Begin
  If RemSock > 0 Then TcpClose(RemSock);
  RemSock := 0;
End;

{ lit sur la socket jusqu'a un paquet de vidage (annonce) }
Function SockAdvert(Var B : TBuf) : Boolean;
Var P, O, L, R : LongInt; Done : Boolean;
Begin
  SockAdvert := False;
  B.N := 0;
  Repeat
    P := 0; Done := False;
    While PktNext(B, P, O, L) Do
      If L < 0 Then
      Begin
        Done := True; Break;
      End;
    If Done Then Break;
    R := TcpRecv(RemSock, B);
    If R <= 0 Then
    Begin
      If B.N = 0 Then GitErr := 'le serveur a ferm'#233' la connexion'
      Else Done := True;
      If Not Done Then Exit;
      Break;
    End;
  Until False;
  SockAdvert := True;
End;

{ decouvre les references ; Service = git-upload-pack ou
  git-receive-pack ; garde la connexion git:// ouverte }
Function RemDiscover(Const Service : String) : Boolean;
Var B, E : TBuf; St, Pp, Ofs, Len : LongInt; U : String;
Begin
  RemDiscover := False;
  RemClose;
  If Not UrlSplit(RemUrl) Then
  Begin
    GitErr := 'URL non prise en charge : ' + RemUrl; Exit;
  End;
  BufInit(B); BufInit(E);
  If UrlScheme = 'git' Then
  Begin
    GitProgress('Connexion '#224' ' + UrlHost, 0, 0);
    RemSock := TcpOpen(UrlHost, UrlPort);
    If RemSock <= 0 Then
    Begin
      RemSock := 0;
      GitErr := 'connexion impossible '#224' ' + UrlHost; BufFree(B); Exit;
    End;
    E.N := 0;
    PktStr0(E, Service + ' ' + UrlPath, 'host=' + UrlHost, True);
    If Not TcpSend(RemSock, E, 0, E.N) Or Not SockAdvert(B) Then
    Begin
      If GitErr = '' Then GitErr := ''#233'chec de l''envoi';
      RemClose; BufFree(B); BufFree(E); Exit;
    End;
    RemDiscover := ParseAdvert(B, 0);
  End
  Else
  Begin
    U := RemUrl;
    If (U <> '') And (U[Length(U)] = '/') Then Delete(U, Length(U), 1);
    GitProgress('Connexion '#224' ' + UrlHost, 0, 0);
    If Not HttpReq('GET', U + '/info/refs?service=' + Service,
      AuthHdr, E, B, St) Then
    Begin
      If GitErr = '' Then GitErr := 'connexion impossible '#224' ' + UrlHost;
      BufFree(B); BufFree(E); Exit;
    End;
    If St <> 200 Then
    Begin
      GitErr := HttpErr(St); BufFree(B); BufFree(E); Exit;
    End;
    Pp := 0;
    If Not PktNext(B, Pp, Ofs, Len) Or (Len < 0) Or
       (BufFind(B, Ofs, Len, '# service=') <> Ofs) Then
    Begin
      GitErr := 'le serveur ne parle pas le protocole Git intelligent';
      BufFree(B); BufFree(E); Exit;
    End;
    { vidage apres la ligne de service }
    Len := -1;
    If Not PktNext(B, Pp, Ofs, Len) Then Pp := B.N;
    If Len >= 0 Then Pp := Ofs - 4;
    RemDiscover := ParseAdvert(B, Pp);
  End;
  BufFree(B); BufFree(E);
End;

{ envoie la requete Req et recoit toute la reponse }
Function RemRpc(Const Service : String; Var Req, Resp : TBuf) : Boolean;
Var St, R, Last : LongInt; U : String; E : TBuf;
Begin
  RemRpc := False;
  Resp.N := 0;
  If UrlScheme = 'git' Then
  Begin
    If Not TcpSend(RemSock, Req, 0, Req.N) Then
    Begin
      GitErr := ''#233'chec de l''envoi'; RemClose; Exit;
    End;
    Last := 0;
    Repeat
      R := TcpRecv(RemSock, Resp);
      If Resp.N - Last >= 65536 Then
      Begin
        GitProgress('Reception des objets', Resp.N, 0);
        Last := Resp.N;
      End;
    Until R <= 0;
    RemClose;
    RemRpc := R = 0;
    If R < 0 Then GitErr := 'erreur de r'#233'ception';
  End
  Else
  Begin
    U := RemUrl;
    If (U <> '') And (U[Length(U)] = '/') Then Delete(U, Length(U), 1);
    If Not HttpReq('POST', U + '/' + Service, AuthHdr +
      'Content-Type: application/x-' + Service + '-request' + #13#10 +
      'Accept: application/x-' + Service + '-result' + #13#10,
      Req, Resp, St) Then
    Begin
      If GitErr = '' Then GitErr := 'connexion impossible';
      Exit;
    End;
    If St <> 200 Then
    Begin
      GitErr := HttpErr(St); Exit;
    End;
    RemRpc := True;
  End;
End;

{ ==================================================================== }
{ Recuperation (fetch / clone)                                          }
{ ==================================================================== }

{ ajoute les commits recents de H (au plus Max) a la liste des « have » }
Procedure AddHaves(Var Req : TBuf; Const H : TSha; Var Seen : TShaSet;
  Var Cnt : LongInt; Max : LongInt);
Var C : TCommit; X : TSha; Q : Array[0..63] Of TSha; QN, I : LongInt;
Begin
  QN := 1; Q[0] := H;
  While (QN > 0) And (Cnt < Max) Do
  Begin
    Dec(QN);
    X := Q[QN];
    If ShaIsZero(X) Or Not SetAdd(Seen, X) Then Continue;
    If Not HasObject(X) Then Continue;
    PktStr(Req, 'have ' + ShaHex(X) + #10);
    Inc(Cnt);
    If CommitRead(X, C, Nil) Then
      For I := C.PN - 1 DownTo 0 Do
        If QN < 64 Then
        Begin
          Q[QN] := C.Parent[I]; Inc(QN);
        End;
  End;
End;

{ recupere les branches distantes dans refs/remotes/<Remote>/ }
Function DoFetch(Const Remote : String) : Boolean;
Var Req, Resp : TBuf; I, Pp, Ofs, Len, Cnt, Wants : LongInt;
    Seen : TShaSet; Nm : String; First : Boolean;
Begin
  DoFetch := False;
  If Not RemDiscover('git-upload-pack') Then Exit;
  BufInit(Req); BufInit(Resp);
  First := True; Wants := 0;
  SetInit(Seen, 256);
  For I := 0 To RemRefs.N - 1 Do
    If (RemRefs.Name[I] <> 'HEAD') And Not HasObject(RemRefs.Sha[I]) And
       SetAdd(Seen, RemRefs.Sha[I]) Then
    Begin
      If First Then
      Begin
        PktStr(Req, 'want ' + ShaHex(RemRefs.Sha[I]) + Copy(RemCaps,
          Pos(' ofs', RemCaps), 10) + ' agent=' + AgentName + #10);
        First := False;
      End
      Else PktStr(Req, 'want ' + ShaHex(RemRefs.Sha[I]) + #10);
      Inc(Wants);
    End;
  SetFree(Seen);
  If Wants > 0 Then
  Begin
    PktFlush(Req);
    { « have » : branches locales et distantes connues }
    SetInit(Seen, 1024);
    Cnt := 0;
    RefsList(LocRefs, 'refs/');
    For I := 0 To LocRefs.N - 1 Do
      AddHaves(Req, LocRefs.Sha[I], Seen, Cnt, 256);
    SetFree(Seen);
    PktStr(Req, 'done' + #10);
    GitProgress('Negociation', 0, 0);
    If Not RemRpc('git-upload-pack', Req, Resp) Then
    Begin
      BufFree(Req); BufFree(Resp); Exit;
    End;
    { ACK / NAK puis le pack }
    Pp := 0;
    While (Pp + 4 <= Resp.N) And (BufStrAt(Resp, Pp, 4) <> 'PACK') Do
    Begin
      If Not PktNext(Resp, Pp, Ofs, Len) Then Break;
      If (Len >= 4) And (BufStrAt(Resp, Ofs, 4) = 'ERR ') Then
      Begin
        GitErr := 'serveur : ' + BufStrAt(Resp, Ofs + 4, MinL(Len - 4, 200));
        BufFree(Req); BufFree(Resp); Exit;
      End;
    End;
    If (Pp + 4 > Resp.N) Or (BufStrAt(Resp, Pp, 4) <> 'PACK') Then
    Begin
      GitErr := 'pas de pack dans la r'#233'ponse du serveur';
      BufFree(Req); BufFree(Resp); Exit;
    End;
    If Pp > 0 Then
    Begin
      Move(Resp.P^[Pp], Resp.P^[0], Resp.N - Pp);
      Dec(Resp.N, Pp);
    End;
    If Not IndexPack(Resp) Then
    Begin
      BufFree(Req); BufFree(Resp); Exit;
    End;
  End;
  { met a jour les references de suivi }
  For I := 0 To RemRefs.N - 1 Do
  Begin
    Nm := RemRefs.Name[I];
    If Copy(Nm, 1, 11) = 'refs/heads/' Then
    Begin
      If Not RefWrite('refs/remotes/' + Remote + '/' + Copy(Nm, 12, 255),
        RemRefs.Sha[I]) Then ;
    End
    Else If (Copy(Nm, 1, 10) = 'refs/tags/') And HasObject(RemRefs.Sha[I])
    Then
      If Not FileExist(GitPath(Nm)) Then
        If RefWrite(Nm, RemRefs.Sha[I]) Then ;
  End;
  { branches distantes supprimees }
  RefsList(LocRefs, 'refs/remotes/' + Remote + '/');
  For I := 0 To LocRefs.N - 1 Do
  Begin
    Nm := 'refs/heads/' + Copy(LocRefs.Name[I], Length(Remote) + 15, 255);
    If Nm = 'refs/heads/HEAD' Then Continue;
    First := False;
    For Cnt := 0 To RemRefs.N - 1 Do
      If RemRefs.Name[Cnt] = Nm Then First := True;
    If Not First Then RefDelete(LocRefs.Name[I]);
  End;
  If RemHead <> '' Then
    If FileSaveStr(GitPath('refs/remotes/' + Remote + '/HEAD'),
      'ref: refs/remotes/' + Remote + '/' + Copy(RemHead, 12, 255) + #10)
    Then ;
  BufFree(Req); BufFree(Resp);
  PacksScan;
  DoFetch := True;
End;

{ ==================================================================== }
{ Envoi (push)                                                          }
{ ==================================================================== }

Type
  TShaList = Record
    H : ^TShaSetArr;
    N, Cap : LongInt;
  End;

Procedure ListAdd(Var L : TShaList; Const H : TSha);
Var Q : ^TShaSetArr; C : LongInt;
Begin
  If L.N >= L.Cap Then
  Begin
    C := L.Cap * 2;
    If C < 256 Then C := 256;
    GetMem(Q, C * 20);
    If L.N > 0 Then Move(L.H^[0], Q^[0], L.N * 20);
    If L.H <> Nil Then FreeMem(L.H, L.Cap * 20);
    L.H := Q; L.Cap := C;
  End;
  L.H^[L.N] := H;
  Inc(L.N);
End;

Procedure ListFree(Var L : TShaList);
Begin
  If L.H <> Nil Then FreeMem(L.H, L.Cap * 20);
  L.H := Nil; L.N := 0; L.Cap := 0;
End;

{ objets de l'arbre H : dans Excl (Add = Faux) ou a envoyer (Add = Vrai)
  s'ils ne sont ni exclus ni deja ajoutes }
Procedure TreeObjs(Const H : TSha; Var Excl, Added : TShaSet;
  Var L : TShaList; Add : Boolean);
Var D : TBuf; T, P, Q : LongInt; S : TSha; Md : String;
Begin
  If Add Then
  Begin
    If SetHas(Excl, H) Or Not SetAdd(Added, H) Then Exit;
    ListAdd(L, H);
  End
  Else If Not SetAdd(Excl, H) Then Exit;
  BufInit(D);
  If ReadObject(H, T, D) And (T = OtTree) Then
  Begin
    P := 0;
    While P < D.N Do
    Begin
      Q := P;
      While (Q < D.N) And (D.P^[Q] <> 32) Do Inc(Q);
      Md := BufStrAt(D, P, Q - P);
      While (Q < D.N) And (D.P^[Q] <> 0) Do Inc(Q);
      ShaFrom(D, Q + 1, S);
      P := Q + 21;
      If Md = '160000' Then Continue;
      If Md = '40000' Then TreeObjs(S, Excl, Added, L, Add)
      Else If Add Then
      Begin
        If Not SetHas(Excl, S) And SetAdd(Added, S) Then ListAdd(L, S);
      End
      Else If SetAdd(Excl, S) Then ;
    End;
  End;
  BufFree(D);
End;

Var
  PushMsg : String;                    { compte rendu du serveur }

{ envoie la branche locale Branch vers Remote ; Force : sans verifier
  l'avance rapide }
Function DoPush(Const Remote, Branch : String; Force : Boolean) : Boolean;
Var Local, Old, X : TSha; Known, Excl, Added : TShaSet; L : TShaList;
    Q : TShaList; I, J, T, Pp, Ofs, Len : LongInt; C : TCommit;
    Req, Resp, D, Pk : TBuf; Ref, S : String; Ok : Boolean;
Begin
  DoPush := False;
  PushMsg := '';
  Ref := 'refs/heads/' + Branch;
  If Not RefRead(Ref, Local) Then
  Begin
    GitErr := 'la branche ' + Branch + ' n''a aucun commit'; Exit;
  End;
  If Not RemDiscover('git-receive-pack') Then Exit;
  Old := ShaZero;
  For I := 0 To RemRefs.N - 1 Do
    If RemRefs.Name[I] = Ref Then Old := RemRefs.Sha[I];
  If ShaEq(Old, Local) Then
  Begin
    RemClose;
    PushMsg := 'deja a jour';
    DoPush := True; Exit;
  End;
  SetInit(Known, 4096);
  For I := 0 To RemRefs.N - 1 Do
    If HasObject(RemRefs.Sha[I]) Then Ancestors(RemRefs.Sha[I], Known);
  If Not ShaIsZero(Old) And Not Force Then
  Begin
    If Not HasObject(Old) Or Not SetHas(Known, Old) Then
    Begin
      GitErr := 'le d'#233'p'#244't distant contient des commits absents : ' +
        'tirez (pull) d''abord';
      SetFree(Known); RemClose; Exit;
    End;
    SetInit(Excl, 1024);
    Ancestors(Local, Excl);
    Ok := SetHas(Excl, Old);
    SetFree(Excl);
    If Not Ok Then
    Begin
      GitErr := 'envoi refus'#233' : ce n''est pas une avance rapide, ' +
        'tirez (pull) d''abord';
      SetFree(Known); RemClose; Exit;
    End;
  End;
  { nouveaux commits et frontiere }
  SetInit(Excl, 4096); SetInit(Added, 4096);
  FillChar(L, SizeOf(L), 0); FillChar(Q, SizeOf(Q), 0);
  ListAdd(Q, Local);
  I := 0;
  While I < Q.N Do
  Begin
    X := Q.H^[I]; Inc(I);
    If SetHas(Known, X) Or Not SetAdd(Added, X) Then Continue;
    ListAdd(L, X);
    If CommitRead(X, C, Nil) Then
      For J := 0 To C.PN - 1 Do
        If SetHas(Known, C.Parent[J]) Then
        Begin
          If CommitRead(C.Parent[J], C, Nil) Then
            TreeObjs(C.Tree, Excl, Added, L, False);
          If CommitRead(X, C, Nil) Then ;
        End
        Else ListAdd(Q, C.Parent[J]);
  End;
  { arbres et fichiers des nouveaux commits }
  J := L.N;
  For I := 0 To J - 1 Do
    If CommitRead(L.H^[I], C, Nil) Then
      TreeObjs(C.Tree, Excl, Added, L, True);
  SetFree(Known); SetFree(Excl); SetFree(Added); ListFree(Q);
  { pack }
  BufInit(Req); BufInit(Resp); BufInit(D); BufInit(Pk);
  PackBegin(Pk, L.N);
  Ok := True;
  For I := 0 To L.N - 1 Do
  Begin
    If (I And 15) = 0 Then GitProgress('Compression des objets', I, L.N);
    If Not ReadObject(L.H^[I], T, D) Then
    Begin
      GitErr := 'objet manquant ' + ShaHex(L.H^[I]); Ok := False; Break;
    End;
    PackAdd(Pk, T, D);
  End;
  ListFree(L);
  If Ok Then
  Begin
    PackEnd(Pk);
    PktStr0(Req, ShaHex(Old) + ' ' + ShaHex(Local) + ' ' + Ref,
      'report-status agent=' + AgentName + #10, False);
    PktFlush(Req);
    BufAppend(Req, Pk, 0, Pk.N);
    GitProgress('Envoi des objets', 0, 0);
    Ok := RemRpc('git-receive-pack', Req, Resp);
  End;
  If Ok Then
  Begin
    Ok := False;
    Pp := 0;
    While PktNext(Resp, Pp, Ofs, Len) Do
    Begin
      If Len < 0 Then Break;
      S := BufStrAt(Resp, Ofs, MinL(Len, 200));
      If S = 'unpack ok' Then Continue;
      If Copy(S, 1, 7) = 'unpack ' Then PushMsg := S
      Else If Copy(S, 1, 3) = 'ok ' Then Ok := True
      Else If Copy(S, 1, 3) = 'ng ' Then
        PushMsg := Copy(S, 4 + Length(Ref) + 1, 200)
      Else If Copy(S, 1, 4) = 'ERR ' Then PushMsg := Copy(S, 5, 200);
    End;
    If Not Ok Then
    Begin
      If PushMsg = '' Then PushMsg := 'reponse du serveur invalide';
      GitErr := 'refus du serveur : ' + PushMsg;
    End
    Else If RefWrite('refs/remotes/' + Remote + '/' + Branch, Local) Then ;
  End;
  BufFree(Req); BufFree(Resp); BufFree(D); BufFree(Pk);
  RemClose;
  DoPush := Ok;
End;

{ ==================================================================== }
{ Creation, clonage                                                     }
{ ==================================================================== }

Function SetRepo(Const Dir : String) : Boolean;
Begin
  WorkDir := Dir;
  If (WorkDir <> '') And (WorkDir[Length(WorkDir)] = PS) Then
    Delete(WorkDir, Length(WorkDir), 1);
  GitDir := WorkDir + PS + '.git';
  PacksRead := False;
  PackN := 0;
  SetRepo := DirExist(GitDir) And FileExist(GitPath('HEAD'));
End;

Function InitRepo(Const Dir, Branch : String) : Boolean;
Begin
  InitRepo := False;
  MkDirs(Dir);
  If SetRepo(Dir) Then
  Begin
    GitErr := 'ce dossier contient d'#233'j'#224' un d'#233'p'#244't Git'; Exit;
  End;
  MkDirs(GitPath('objects/pack'));
  MkDirs(GitPath('objects/info'));
  MkDirs(GitPath('refs/heads'));
  MkDirs(GitPath('refs/tags'));
  MkDirs(GitPath('info'));
  If Not FileSaveStr(GitPath('config'), '[core]' + #10 +
    #9'repositoryformatversion = 0' + #10 + #9'filemode = false' + #10 +
    #9'bare = false' + #10 + #9'logallrefupdates = true' + #10 +
    #9'symlinks = false' + #10 + #9'ignorecase = true' + #10) Then
  Begin
    GitErr := ''#233'criture impossible dans ' + Dir; Exit;
  End;
  If FileSaveStr(GitPath('description'), 'Unnamed repository' + #10) Then;
  SetHead('refs/heads/' + Branch);
  InitRepo := True;
End;

Procedure SetRemote(Const Name, Url : String);
Begin
  CfgSet('remote', Name, 'url', Url);
  CfgSet('remote', Name, 'fetch', '+refs/heads/*:refs/remotes/' + Name +
    '/*');
End;

Procedure SetUpstream(Const Branch, Remote : String);
Begin
  CfgSet('branch', Branch, 'remote', Remote);
  CfgSet('branch', Branch, 'merge', 'refs/heads/' + Branch);
End;

Function DoClone(Const Url, Dir : String) : Boolean;
Var B : String; H : TSha; I : LongInt; T : TFlat;
Begin
  DoClone := False;
  If Not InitRepo(Dir, 'main') Then Exit;
  SetRemote('origin', Url);
  RemUrl := Url;
  If Not DoFetch('origin') Then Exit;
  B := RemHead;
  If B = '' Then
    For I := 0 To RemRefs.N - 1 Do
      If (RemRefs.Name[I] = 'refs/heads/main') Or
         ((B = '') And (RemRefs.Name[I] = 'refs/heads/master')) Then
        B := RemRefs.Name[I];
  If B = '' Then
    For I := 0 To RemRefs.N - 1 Do
      If (B = '') And (Copy(RemRefs.Name[I], 1, 11) = 'refs/heads/') Then
        B := RemRefs.Name[I];
  If B = '' Then
  Begin
    { depot distant vide }
    DoClone := True; Exit;
  End;
  Delete(B, 1, 11);
  SetHead('refs/heads/' + B);
  If Not RefRead('refs/remotes/origin/' + B, H) Then
  Begin
    GitErr := 'branche distante introuvable'; Exit;
  End;
  If Not RefWrite('refs/heads/' + B, H) Then Exit;
  SetUpstream(B, 'origin');
  HeadSha := H;
  FlatInit(T);
  HeadF.N := 0; Chg.N := 0;
  If CommitFlat(H, T) Then DoClone := WorkUpdate(HeadF, T);
  FlatCopy(HeadF, T);
  FlatFree(T);
End;

{ ==================================================================== }
{ API GitHub (JSON)                                                     }
{ ==================================================================== }

Const
  JkStr = 1;
  JkLit = 2;
  JkSym = 3;

{ jeton JSON suivant : chaine (decodee), litteral ou symbole }
Function JsonNext(Var B : TBuf; Var P : LongInt; Var S : String) : LongInt;
Var C, K, V : LongInt;
Begin
  JsonNext := 0;
  S := '';
  While (P < B.N) And (B.P^[P] <= 32) Do Inc(P);
  If P >= B.N Then Exit;
  C := B.P^[P];
  If C = 34 Then
  Begin
    Inc(P);
    While (P < B.N) And (B.P^[P] <> 34) Do
    Begin
      C := B.P^[P];
      If (C = 92) And (P + 1 < B.N) Then
      Begin
        Inc(P);
        C := B.P^[P];
        Case Chr(C) Of
          'n' : C := 32;
          't' : C := 32;
          'r' : C := 32;
          'b', 'f' : C := 32;
          'u' :
          Begin
            V := 0;
            For K := 1 To 4 Do
              If P + K < B.N Then V := V * 16 + HexVal(Chr(B.P^[P + K]));
            Inc(P, 4);
            Case V Of
              $E9 : C := 130; $E8 : C := 138; $EA : C := 136;
              $E0 : C := 133; $E7 : C := 135; $F4 : C := 147;
              $EE : C := 140; $FB : C := 150; $F9 : C := 151;
              $C9 : C := 144;
              Else If V < 128 Then C := V Else C := Ord('?');
            End;
          End;
        End;
      End
      Else If C >= 128 Then
      Begin
        { UTF-8 : lettres accentuees courantes }
        If (C = $C3) And (P + 1 < B.N) Then
        Begin
          Inc(P);
          Case B.P^[P] Of
            $A9 : C := 130; $A8 : C := 138; $AA : C := 136; $A0 : C := 133;
            $A7 : C := 135; $B4 : C := 147; $AE : C := 140; $BB : C := 150;
            $B9 : C := 151; $89 : C := 144;
            Else C := Ord('?');
          End;
        End
        Else
        Begin
          While (P + 1 < B.N) And (B.P^[P + 1] >= 128) And
            (B.P^[P + 1] < 192) Do Inc(P);
          C := Ord('?');
        End;
      End;
      If Length(S) < 250 Then S := S + Chr(C);
      Inc(P);
    End;
    Inc(P);
    JsonNext := JkStr;
  End
  Else If Chr(C) In ['{', '}', '[', ']', ':', ','] Then
  Begin
    S := Chr(C); Inc(P);
    JsonNext := JkSym;
  End
  Else
  Begin
    While (P < B.N) And Not (Chr(B.P^[P]) In [',', '}', ']', ' ', #10, #13,
      #9]) Do
    Begin
      If Length(S) < 250 Then S := S + Chr(B.P^[P]);
      Inc(P);
    End;
    JsonNext := JkLit;
  End;
End;

{ premiere valeur de Key a la profondeur Depth (1 : objet racine) ;
  resultat affecte une seule fois (anneau de chaines de WPC) }
Function JsonGet(Var B : TBuf; Const Key : String; Depth : LongInt)
  : String;
Var P, K, D : LongInt; S, R : String; IsKey, Done : Boolean;
Begin
  R := '';
  P := 0; D := 0; Done := False;
  Repeat
    K := JsonNext(B, P, S);
    If K = 0 Then Done := True
    Else If K = JkSym Then
    Begin
      If (S = '{') Or (S = '[') Then Inc(D)
      Else If (S = '}') Or (S = ']') Then Dec(D);
    End
    Else
    Begin
      { une chaine suivie de ':' est une cle }
      While (P < B.N) And (B.P^[P] <= 32) Do Inc(P);
      IsKey := (K = JkStr) And (P < B.N) And (B.P^[P] = Ord(':'));
      If IsKey Then
      Begin
        Inc(P);
        If (D = Depth) And (S = Key) Then
        Begin
          K := JsonNext(B, P, S);
          If K <> JkSym Then R := S;
          Done := True;
        End;
      End;
    End;
  Until Done;
  JsonGet := R;
End;

Const
  MaxGh = 300;

Var
  GhLogin, GhToken : String;
  GhN : LongInt;
  GhName : Array[0..MaxGh - 1] Of String[100];
  GhUrl : Array[0..MaxGh - 1] Of String[160];
  GhPriv : Array[0..MaxGh - 1] Of Boolean;
  GhDesc : Array[0..MaxGh - 1] Of String[100];

Function GhApi(Const Method, Path : String; Var Body, Resp : TBuf;
  Var St : LongInt) : Boolean;
Var H : String;
Begin
  H := 'Accept: application/vnd.github+json' + #13#10;
  If GhToken <> '' Then H := H + 'Authorization: token ' + GhToken + #13#10;
  If Body.N > 0 Then H := H + 'Content-Type: application/json' + #13#10;
  GhApi := HttpReq(Method, 'https://api.github.com' + Path, H, Body, Resp,
    St);
End;

{ repertorie les depots de l'utilisateur (objets du tableau racine) }
Procedure GhParseRepos(Var B : TBuf);
Var P, K, D : LongInt; S, Key : String;
Begin
  P := 0; D := 0;
  Repeat
    K := JsonNext(B, P, S);
    If K = 0 Then Exit;
    If K = JkSym Then
    Begin
      If (S = '{') Or (S = '[') Then
      Begin
        Inc(D);
        If (D = 2) And (S = '{') And (GhN < MaxGh) Then
        Begin
          GhName[GhN] := ''; GhUrl[GhN] := ''; GhPriv[GhN] := False;
          GhDesc[GhN] := '';
        End;
      End
      Else If (S = '}') Or (S = ']') Then
      Begin
        If (D = 2) And (S = '}') And (GhN < MaxGh) And (GhName[GhN] <> '')
        Then Inc(GhN);
        Dec(D);
      End;
      Continue;
    End;
    While (P < B.N) And (B.P^[P] <= 32) Do Inc(P);
    If (K = JkStr) And (P < B.N) And (B.P^[P] = Ord(':')) Then
    Begin
      Inc(P);
      If (D <> 2) Or (GhN >= MaxGh) Then Continue;
      Key := S;
      K := JsonNext(B, P, S);
      If K = JkSym Then
      Begin
        If (S = '{') Or (S = '[') Then Inc(D);
        Continue;
      End;
      If Key = 'full_name' Then GhName[GhN] := Copy(S, 1, 100)
      Else If Key = 'clone_url' Then GhUrl[GhN] := Copy(S, 1, 160)
      Else If Key = 'private' Then GhPriv[GhN] := S = 'true'
      Else If (Key = 'description') And (K = JkStr) Then
        GhDesc[GhN] := Copy(S, 1, 100);
    End;
  Until False;
End;

{ ouvre une session GitHub : verifie le jeton et lit l'identifiant }
Function GhSignIn : Boolean;
Var B, R : TBuf; St : LongInt;
Begin
  GhSignIn := False;
  BufInit(B); BufInit(R);
  If GhApi('GET', '/user', B, R, St) Then
  Begin
    If St = 200 Then
    Begin
      GhLogin := JsonGet(R, 'login', 1);
      GhSignIn := GhLogin <> '';
    End
    Else GitErr := HttpErr(St);
  End
  Else If GitErr = '' Then GitErr := 'connexion impossible '#224' api.github.com';
  BufFree(B); BufFree(R);
End;

Function GhListRepos : Boolean;
Var B, R : TBuf; St, Pg : LongInt; Old : LongInt;
Begin
  GhListRepos := False;
  GhN := 0;
  BufInit(B); BufInit(R);
  For Pg := 1 To 3 Do
  Begin
    Old := GhN;
    If Not GhApi('GET', '/user/repos?per_page=100&sort=updated&page=' +
      IStr(Pg), B, R, St) Then Break;
    If St <> 200 Then
    Begin
      GitErr := HttpErr(St); Break;
    End;
    GhParseRepos(R);
    GhListRepos := True;
    If GhN - Old < 100 Then Break;
  End;
  BufFree(B); BufFree(R);
End;

Function JsonQuote(Const S : String) : String;
Var I : LongInt; R : String;
Begin
  R := '"';
  For I := 1 To Length(S) Do
    If (S[I] = '"') Or (S[I] = '\') Then R := R + '\' + S[I]
    Else If S[I] >= ' ' Then R := R + S[I];
  JsonQuote := R + '"';
End;

{ cree un depot GitHub ; Url recoit l'adresse de clonage }
Function GhCreate(Const Name, Desc : String; Priv : Boolean;
  Var Url : String) : Boolean;
Var B, R : TBuf; St : LongInt; S : String;
Begin
  GhCreate := False;
  BufInit(B); BufInit(R);
  If Priv Then S := 'true' Else S := 'false';
  BufStr(B, '{"name":' + JsonQuote(Name) + ',"description":' +
    JsonQuote(Desc) + ',"private":' + S + '}');
  If GhApi('POST', '/user/repos', B, R, St) Then
  Begin
    If St = 201 Then
    Begin
      Url := JsonGet(R, 'clone_url', 1);
      GhCreate := Url <> '';
    End
    Else
    Begin
      S := JsonGet(R, 'message', 1);
      If S <> '' Then GitErr := 'GitHub : ' + S Else GitErr := HttpErr(St);
    End;
  End;
  BufFree(B); BufFree(R);
End;
{ ==================================================================== }
{ API Win32                                                             }
{ ==================================================================== }

Function InternetOpenA(A, T, P, B, F : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetOpenA';
Function InternetConnectA(H, S, P, U, W, Sv, F, C : LongInt) : LongInt;
  stdcall; external 'wininet.dll' name 'InternetConnectA';
Function HttpOpenRequestA(H, V, O, Vr, R, A, F, C : LongInt) : LongInt;
  stdcall; external 'wininet.dll' name 'HttpOpenRequestA';
Function HttpSendRequestA(H, Hd, Hl, O, Ol : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'HttpSendRequestA';
Function HttpQueryInfoA(H, I, B, L, X : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'HttpQueryInfoA';
Function InternetReadFile(H, B, N, R : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetReadFile';
Function InternetCloseHandle(H : LongInt) : LongInt; stdcall;
  external 'wininet.dll' name 'InternetCloseHandle';
Function WSAStartup(V, P : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'WSAStartup';
Function socket(Af, Typ, Pr : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'socket';
Function connect(S, A, L : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'connect';
Function send(S, B, N, F : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'send';
Function recv(S, B, N, F : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'recv';
Function closesocket(S : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'closesocket';
Function shutdown(S, How : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'shutdown';
Function gethostbyname(N : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'gethostbyname';
Function inet_addr(N : LongInt) : LongInt; stdcall;
  external 'wsock32.dll' name 'inet_addr';
Function CreateThread(A, S, F, P, Fl, Id : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'CreateThread';
Procedure InitializeCriticalSection(P : LongInt); stdcall;
  external 'kernel32.dll' name 'InitializeCriticalSection';
Procedure EnterCriticalSection(P : LongInt); stdcall;
  external 'kernel32.dll' name 'EnterCriticalSection';
Procedure LeaveCriticalSection(P : LongInt); stdcall;
  external 'kernel32.dll' name 'LeaveCriticalSection';
Function GetCurrentThreadId : LongInt; stdcall;
  external 'kernel32.dll' name 'GetCurrentThreadId';
Procedure Sleep(Ms : LongInt); stdcall;
  external 'kernel32.dll' name 'Sleep';
Procedure GetSystemTime(P : LongInt); stdcall;
  external 'kernel32.dll' name 'GetSystemTime';
Function GetTickCount : LongInt; stdcall;
  external 'kernel32.dll' name 'GetTickCount';
{ ==================================================================== }
{ Transport Win32 : WININET (http, https) et Winsock (git://)           }
{ ==================================================================== }

Var
  Lock : Array[0..7] Of LongInt;       { CRITICAL_SECTION }
  LockOn : Boolean;
  LockDepth : LongInt;
  NetReady : Boolean;
  InetH : LongInt;
  InetPx : String;
  ProxyStr : String;                   { hote:port ou '' }
  NetZ : Array[0..1023] Of Byte;
  NetAbort : Boolean;

Procedure BigLock;
Begin
  If Not LockOn Then Exit;
  EnterCriticalSection(LongInt(@Lock[0]));
  Inc(LockDepth);
End;

Procedure BigUnlock;
Begin
  If Not LockOn Then Exit;
  Dec(LockDepth);
  LeaveCriticalSection(LongInt(@Lock[0]));
End;

Procedure PutZ(Var Z : Array Of Byte; Const S : String);
Var I : LongInt;
Begin
  For I := 1 To Length(S) Do Z[I - 1] := Ord(S[I]);
  Z[Length(S)] := 0;
End;

Function MemL4(A : LongInt) : LongInt;
Var P : ^LongInt;
Begin
  P := Pointer(A);
  MemL4 := P^;
End;

Function HttpReq(Const Method, Url, Hdr : String; Var Body, Resp : TBuf;
  Var Status : LongInt) : Boolean;
Var C, R, N, Fl, L, Last : LongInt; Ab, Hb, Vb, Ob, Xb : Array[0..299] Of
    Byte; Sb : Array[0..31] Of Byte; Pb : Array[0..99] Of Byte;
    BP : LongInt; Yb : Array[0..99] Of Byte;
Begin
  HttpReq := False;
  Status := 0;
  Resp.N := 0;
  If Not UrlSplit(Url) Then
  Begin
    GitErr := 'URL non valable : ' + Url; Exit;
  End;
  If (InetH = 0) Or (InetPx <> ProxyStr) Then
  Begin
    If InetH <> 0 Then InternetCloseHandle(InetH);
    PutZ(Ab, AgentName);
    PutZ(Pb, ProxyStr);
    { reseau local et prive : sans proxy (liste de contournement) }
    PutZ(Yb, '<local>;localhost;127.*;10.*;192.168.*');
    If ProxyStr <> '' Then
      InetH := InternetOpenA(LongInt(@Ab), 3, LongInt(@Pb), LongInt(@Yb), 0)
    Else InetH := InternetOpenA(LongInt(@Ab), 0, 0, 0, 0);
    InetPx := ProxyStr;
  End;
  If InetH = 0 Then
  Begin
    GitErr := 'r'#233'seau indisponible (WININET)'; Exit;
  End;
  PutZ(Hb, UrlHost);
  C := InternetConnectA(InetH, LongInt(@Hb), UrlPort, 0, 0, 3, 0, 0);
  If C = 0 Then
  Begin
    GitErr := 'connexion impossible '#224' ' + UrlHost; Exit;
  End;
  PutZ(Vb, Method);
  PutZ(Ob, UrlPath);
  Fl := LongInt($84000000);            { RELOAD, NO_CACHE_WRITE }
  If UrlScheme = 'https' Then Fl := Fl Or $00800000;
  R := HttpOpenRequestA(C, LongInt(@Vb), LongInt(@Ob), 0, 0, 0, Fl, 0);
  If R = 0 Then
  Begin
    GitErr := 'requete impossible vers ' + UrlHost;
    InternetCloseHandle(C); Exit;
  End;
  PutZ(Xb, Hdr);
  If Body.N > 0 Then BP := LongInt(@Body.P^[0]) Else BP := 0;
  BigUnlock;
  N := HttpSendRequestA(R, LongInt(@Xb), Length(Hdr), BP, Body.N);
  BigLock;
  If N = 0 Then
  Begin
    If UrlScheme = 'https' Then
      GitErr := 'connexion s'#233'curis'#233'e impossible '#224' ' + UrlHost +
        ' (TLS 1.2)'
    Else GitErr := 'connexion impossible '#224' ' + UrlHost + ':' +
      IStr(UrlPort);
    InternetCloseHandle(R); InternetCloseHandle(C); Exit;
  End;
  L := 30;
  Sb[0] := 0;
  If HttpQueryInfoA(R, 19, LongInt(@Sb), LongInt(@L), 0) <> 0 Then
  Begin
    N := 0;
    While (N < L) And (Sb[N] >= 48) And (Sb[N] <= 57) Do
    Begin
      Status := Status * 10 + Sb[N] - 48; Inc(N);
    End;
  End;
  Last := 0;
  Repeat
    If NetAbort Then
    Begin
      GitErr := 'op'#233'ration annul'#233'e'; Status := 0; Break;
    End;
    BufNeed(Resp, Resp.N + 65536);
    N := 0;
    BigUnlock;
    If InternetReadFile(R, LongInt(@Resp.P^[Resp.N]), 65536,
      LongInt(@N)) = 0 Then N := 0;
    BigLock;
    If N <= 0 Then Break;
    Inc(Resp.N, N);
    If Resp.N - Last >= 65536 Then
    Begin
      GitProgress('Reception', Resp.N, 0);
      Last := Resp.N;
    End;
  Until False;
  InternetCloseHandle(R);
  InternetCloseHandle(C);
  HttpReq := Status > 0;
End;

Function TcpOpen(Const Host : String; Port : LongInt) : LongInt;
Var A : Array[0..15] Of Byte; S, IP, H, I, R : LongInt;
    W : Array[0..511] Of Byte;
Begin
  TcpOpen := -1;
  If Not NetReady Then
  Begin
    WSAStartup($101, LongInt(@W[0]));
    NetReady := True;
  End;
  PutZ(NetZ, Host);
  IP := inet_addr(LongInt(@NetZ[0]));
  If (IP = -1) Or (IP = 0) Then
  Begin
    BigUnlock;
    H := gethostbyname(LongInt(@NetZ[0]));
    BigLock;
    If H = 0 Then
    Begin
      GitErr := 'ordinateur introuvable : ' + Host; Exit;
    End;
    IP := MemL4(MemL4(MemL4(H + 12)));
  End;
  S := socket(2, 1, 6);
  If S = -1 Then Exit;
  For I := 0 To 15 Do A[I] := 0;
  A[0] := 2; A[2] := (Port Shr 8) And 255; A[3] := Port And 255;
  A[4] := IP And 255; A[5] := (IP Shr 8) And 255;
  A[6] := (IP Shr 16) And 255; A[7] := (IP Shr 24) And 255;
  BigUnlock;
  R := connect(S, LongInt(@A[0]), 16);
  BigLock;
  If R <> 0 Then
  Begin
    GitErr := 'connexion refusee : ' + Host + ':' + IStr(Port);
    closesocket(S); Exit;
  End;
  TcpOpen := S;
End;

Function TcpSend(H : LongInt; Var B : TBuf; Ofs, N : LongInt) : Boolean;
Var R : LongInt;
Begin
  TcpSend := False;
  While N > 0 Do
  Begin
    BigUnlock;
    R := send(H, LongInt(@B.P^[Ofs]), MinL(N, 16384), 0);
    BigLock;
    If R <= 0 Then Exit;
    Inc(Ofs, R); Dec(N, R);
  End;
  TcpSend := True;
End;

Function TcpRecv(H : LongInt; Var B : TBuf) : LongInt;
Var R : LongInt;
Begin
  If NetAbort Then
  Begin
    GitErr := 'op'#233'ration annul'#233'e'; TcpRecv := -1; Exit;
  End;
  BufNeed(B, B.N + 65536);
  BigUnlock;
  R := recv(H, LongInt(@B.P^[B.N]), 65536, 0);
  BigLock;
  If R > 0 Then Inc(B.N, R);
  TcpRecv := R;
End;

Procedure TcpClose(H : LongInt);
Begin
  shutdown(H, 2);
  closesocket(H);
End;
{ ==================================================================== }
{ Constantes et API Win32                                               }
{ ==================================================================== }

Const
  WM_CREATE = $0001; WM_DESTROY = $0002; WM_SIZE = $0005;
  WM_SETFOCUS = $0007; WM_KILLFOCUS = $0008; WM_PAINT = $000F;
  WM_CLOSE = $0010; WM_ERASEBKGND = $0014; WM_SETFONT = $0030;
  WM_GETMINMAXINFO = $0024; WM_SETCURSOR = $0020;
  WM_KEYDOWN = $0100; WM_CHAR = $0102; WM_SYSKEYDOWN = $0104;
  WM_COMMAND = $0111; WM_TIMER = $0113;
  WM_HSCROLL = $0114; WM_VSCROLL = $0115;
  WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201; WM_LBUTTONUP = $0202;
  WM_LBUTTONDBLCLK = $0203; WM_RBUTTONDOWN = $0204; WM_RBUTTONUP = $0205;
  WM_MOUSEWHEEL = $020A; WM_USER = $0400;
  WM_GITDONE = WM_USER + 10;           { operation reseau terminee }
  WM_GITPROG = WM_USER + 11;           { progression }
  WS_POPUP = LongInt($80000000); WS_CHILD = $40000000;
  WS_VISIBLE = $10000000; WS_DISABLED = $08000000;
  WS_CLIPCHILDREN = $02000000; WS_CAPTION = $00C00000;
  WS_BORDER = $00800000; WS_VSCROLL = $00200000; WS_HSCROLL = $00100000;
  WS_SYSMENU = $00080000; WS_THICKFRAME = $00040000;
  WS_TABSTOP = $00010000; WS_GROUP = $00020000;
  WS_OVERLAPPEDWINDOW = $00CF0000; WS_EX_DLGMODALFRAME = 1;
  WS_EX_CLIENTEDGE = $200;
  ES_AUTOHSCROLL = $0080; ES_MULTILINE = $0004; ES_AUTOVSCROLL = $0040;
  ES_READONLY = $0800; ES_WANTRETURN = $1000; ES_PASSWORD = $0020;
  BS_PUSHBUTTON = 0; BS_DEFPUSHBUTTON = 1; BS_AUTOCHECKBOX = 3;
  BS_GROUPBOX = 7;
  BM_GETCHECK = $00F0; BM_SETCHECK = $00F1; BN_CLICKED = 0;
  LBS_NOTIFY = 1; LB_ADDSTRING = $0180; LB_RESETCONTENT = $0184;
  LB_SETCURSEL = $0186; LB_GETCURSEL = $0188; LB_GETCOUNT = $018B;
  LBN_SELCHANGE = 1; LBN_DBLCLK = 2; EN_CHANGE = $0300;
  EM_SETSEL = $00B1;
  SB_CTL = 2; SBS_HORZ = 0; SBS_VERT = 1;
  SB_LINEUP = 0; SB_LINEDOWN = 1; SB_PAGEUP = 2; SB_PAGEDOWN = 3;
  SB_THUMBPOSITION = 4; SB_THUMBTRACK = 5; SB_TOP = 6; SB_BOTTOM = 7;
  CS_DBLCLKS = 8; IDC_ARROW = 32512; IDC_WAIT = 32514;
  SM_CXSCREEN = 0; SM_CYSCREEN = 1;
  MF_STRING = 0; MF_GRAYED = 1; MF_POPUP = $10; MF_SEPARATOR = $800;
  MF_CHECKED = 8; MF_ENABLED = 0;
  TPM_RETURNCMD = $100;
  MB_OK = 0; MB_OKCANCEL = 1; MB_YESNO = 4; MB_ICONERROR = $10;
  MB_ICONQUESTION = $20; MB_ICONWARNING = $30; MB_ICONINFO = $40;
  IDOK = 1; IDCANCEL = 2; IDYES = 6; IDNO = 7;
  VK_BACK = $08; VK_TAB = $09; VK_RETURN = $0D; VK_SHIFT = $10;
  VK_CONTROL = $11; VK_ESCAPE = $1B; VK_SPACE = $20; VK_PRIOR = $21;
  VK_NEXT = $22; VK_END = $23; VK_HOME = $24; VK_LEFT = $25; VK_UP = $26;
  VK_RIGHT = $27; VK_DOWN = $28; VK_DELETE = $2E; VK_F5 = $74;
  TRANSPARENT = 1;
  ClrFace = $C0C0C0; ClrShadow = $808080; ClrHi = $FFFFFF; ClrDark = 0;
  ClrWin = $FFFFFF; ClrBlack = 0; ClrNavy = $800000; ClrGray = $808080;
  ClrGreen = $008000; ClrRed = $0000C0; ClrMaroon = $000080;
  ClrAddBg = $EDFFE6; ClrDelBg = $F0EEFF; ClrAddG = $D8FFCD;
  ClrDelG = $E0DCFF; ClrHunk = $FFF8F1; ClrHunkT = $A06030;
  ClrAddI = $289A2C; ClrModI = $0088C0; ClrDelI = $2020C8;
  ClrConfI = $0060E0; ClrLight = $E0E0E0;

Type
  TWndCls = Record
    Style, Proc, ClsExtra, WndExtra, Inst, Icon, Cursor, Brush, MenuName,
    ClassName : LongInt;
  End;
  PByt = ^Byte;

{ ---- KERNEL32 ---- }
Function GetModuleHandleA(P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleHandleA';
Function GetDriveTypeA(P : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetDriveTypeA';
Function GetModuleFileNameA(H, P, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GetModuleFileNameA';
Procedure ExitProcess(Code : LongInt); stdcall;
  external 'kernel32.dll' name 'ExitProcess';
Function GlobalAlloc(F, N : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalAlloc';
Function GlobalLock(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalLock';
Function GlobalUnlock(H : LongInt) : LongInt; stdcall;
  external 'kernel32.dll' name 'GlobalUnlock';
Function GetPrivateProfileStringA(A, K, D, B, N, F : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'GetPrivateProfileStringA';
Function WritePrivateProfileStringA(A, K, V, F : LongInt) : LongInt;
  stdcall; external 'kernel32.dll' name 'WritePrivateProfileStringA';
Function RegOpenKeyExA(K, Sub, Opt, Sam, PRes : LongInt) : LongInt;
  stdcall; external 'advapi32.dll' name 'RegOpenKeyExA';
Function RegQueryValueExA(K, Name, Res, PTyp, Data, PLen : LongInt)
  : LongInt; stdcall; external 'advapi32.dll' name 'RegQueryValueExA';
Function RegCloseKey(K : LongInt) : LongInt; stdcall;
  external 'advapi32.dll' name 'RegCloseKey';
{ ---- USER32 ---- }
Function RegisterClassA(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'RegisterClassA';
Function CreateWindowExA(Ex, Cls, Title, Style, X, Y, W, H, Par, Menu,
  Inst, Param : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CreateWindowExA';
Function DestroyWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyWindow';
Function ShowWindow(H, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ShowWindow';
Function UpdateWindow(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'UpdateWindow';
Function MoveWindow(H, X, Y, W, Hh, R : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MoveWindow';
Function DefWindowProcA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DefWindowProcA';
Function GetMessageA(P, H, F, L : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetMessageA';
Function TranslateMessage(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'TranslateMessage';
Function DispatchMessageA(P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DispatchMessageA';
Procedure PostQuitMessage(Code : LongInt); stdcall;
  external 'user32.dll' name 'PostQuitMessage';
Function PostMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'PostMessageA';
Function SendMessageA(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SendMessageA';
Function BeginPaint(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'BeginPaint';
Function EndPaint(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EndPaint';
Function InvalidateRect(H, P, Erase : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'InvalidateRect';
Function GetClientRect(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetClientRect';
Function AdjustWindowRectEx(P, Style, Menu, Ex : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'AdjustWindowRectEx';
Function SetWindowTextA(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetWindowTextA';
Function GetWindowTextA(H, P, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetWindowTextA';
Function SetFocus(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetFocus';
Function GetFocus : LongInt; stdcall;
  external 'user32.dll' name 'GetFocus';
Function EnableWindow(H, On : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnableWindow';
Function SetTimer(H, Id, Ms, Proc : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetTimer';
Function MessageBoxA(H, Text, Cap, Typ : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBoxA';
Function CreateMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreateMenu';
Function CreatePopupMenu : LongInt; stdcall;
  external 'user32.dll' name 'CreatePopupMenu';
Function AppendMenuA(M, Flags, Id, Text : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'AppendMenuA';
Function SetMenu(H, M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetMenu';
Function DestroyMenu(M : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'DestroyMenu';
Function EnableMenuItem(M, Id, Flags : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'EnableMenuItem';
Function CheckMenuItem(M, Id, Flags : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'CheckMenuItem';
Function TrackPopupMenu(M, Flags, X, Y, R, H, Rc : LongInt) : LongInt;
  stdcall; external 'user32.dll' name 'TrackPopupMenu';
Function ClientToScreen(H, P : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'ClientToScreen';
Function GetSystemMetrics(I : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetSystemMetrics';
Function LoadCursorA(I, N : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'LoadCursorA';
Function SetCursor(C : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCursor';
Function SetCapture(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetCapture';
Function ReleaseCapture : LongInt; stdcall;
  external 'user32.dll' name 'ReleaseCapture';
Function GetKeyState(K : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'GetKeyState';
Function FillRect(Dc, P, Br : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'FillRect';
Function SetScrollRange(H, Bar, A, B, R : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetScrollRange';
Function SetScrollPos(H, Bar, P, R : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetScrollPos';
Function OpenClipboard(H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'OpenClipboard';
Function EmptyClipboard : LongInt; stdcall;
  external 'user32.dll' name 'EmptyClipboard';
Function SetClipboardData(F, H : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'SetClipboardData';
Function CloseClipboard : LongInt; stdcall;
  external 'user32.dll' name 'CloseClipboard';
Function MessageBeep(T : LongInt) : LongInt; stdcall;
  external 'user32.dll' name 'MessageBeep';
{ ---- GDI32 ---- }
Function CreateSolidBrush(C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateSolidBrush';
Function DeleteObject(H : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'DeleteObject';
Function CreateFontA(H, W, Esc, Ori, Wt, It, Un, St, Cs, Op, Cp, Q, Pf,
  Face : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'CreateFontA';
Function SelectObject(Dc, Obj : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SelectObject';
Function TextOutA(Dc, X, Y, P, N : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'TextOutA';
Function SetTextColor(Dc, C : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetTextColor';
Function SetBkMode(Dc, M : LongInt) : LongInt; stdcall;
  external 'gdi32.dll' name 'SetBkMode';
{ ---- SHELL32 ---- }
Function ShellExecuteA(H, Op, F, Prm, D, Show : LongInt) : LongInt;
  stdcall; external 'shell32.dll' name 'ShellExecuteA';
Function SHBrowseForFolderA(P : LongInt) : LongInt; stdcall;
  external 'shell32.dll' name 'SHBrowseForFolderA';
Function SHGetPathFromIDListA(Pidl, Buf : LongInt) : LongInt; stdcall;
  external 'shell32.dll' name 'SHGetPathFromIDListA';
{ ==================================================================== }
{ Utilitaires de l'interface                                            }
{ ==================================================================== }

Const
  CW = 6;                              { police 6x13 de Pasdows }

Var
  Inst, MainWnd, Dummy, OemOut, Fnt : LongInt;
  NameZ, NameZ2, TxtBuf : Array[0..1023] Of Byte;
  Qmsg : Array[0..7] Of LongInt;
  AppDir, IniFile : String;

Function LockDepthRelease : LongInt;
Var D, I : LongInt;
Begin
  D := LockDepth;
  For I := 1 To D Do BigUnlock;
  LockDepthRelease := D;
End;

Procedure LockDepthRestore(D : LongInt);
Var I : LongInt;
Begin
  For I := 1 To D Do BigLock;
End;

Function Z(Const S : String) : LongInt;
Begin
  PutZ(NameZ, S);
  Z := LongInt(@NameZ);
End;

Function Z2(Const S : String) : LongInt;
Begin
  PutZ(NameZ2, S);
  Z2 := LongInt(@NameZ2);
End;

Function GetZ(A : LongInt) : String;
Var S : String; P : PByt;
Begin
  S := '';
  P := PByt(A);
  While (P^ <> 0) And (Length(S) < 255) Do
  Begin
    S := S + Chr(P^);
    P := PByt(LongInt(P) + 1);
  End;
  GetZ := S;
End;

{ ANSI (1252) -> page 437 de la police de l'ecran de Pasdows }
Const
  AnsiOem : Array[128..255] Of Byte = (
    69, 63, 44, 102, 34, 46, 197, 206, 94, 63, 83, 60, 79, 63, 90, 63, 63,
    39, 39, 34, 34, 249, 45, 45, 126, 159, 115, 62, 111, 63, 122, 89, 255,
    173, 155, 156, 63, 157, 124, 21, 34, 169, 166, 174, 170, 45, 158, 196,
    248, 241, 253, 51, 39, 230, 20, 250, 44, 49, 167, 175, 172, 171, 63,
    168, 65, 65, 65, 65, 142, 143, 146, 128, 69, 144, 69, 69, 73, 73, 73,
    73, 68, 165, 79, 79, 79, 79, 153, 120, 79, 85, 85, 85, 154, 89, 63, 225,
    133, 160, 131, 97, 132, 134, 145, 135, 138, 130, 136, 137, 141, 161, 140,
    139, 63, 164, 149, 162, 147, 111, 148, 246, 111, 151, 163, 150, 129, 121,
    63, 152);

Function Disp(S : String) : String;
Var K : LongInt;
Begin
  If OemOut <> 0 Then
    For K := 1 To Length(S) Do
      If Ord(S[K]) >= 128 Then S[K] := Chr(AnsiOem[Ord(S[K])]);
  Disp := S;
End;

Function UnDisp(S : String) : String;
Var K, C : LongInt;
Begin
  If OemOut <> 0 Then
    For K := 1 To Length(S) Do
      If Ord(S[K]) >= 128 Then
        For C := 160 To 255 Do
          If AnsiOem[C] = Ord(S[K]) Then
          Begin
            S[K] := Chr(C);
            Break;
          End;
  UnDisp := S;
End;

Procedure DetectOem;
Var K, T, N : LongInt; B : Array[0..63] Of Byte; S : String;
Begin
  OemOut := 0;
  K := 0;
  If RegOpenKeyExA(LongInt($80000002),
    Z('Software\Microsoft\Windows\CurrentVersion'), 0, $20019,
    LongInt(@K)) <> 0 Then Exit;
  N := 63; T := 0; B[0] := 0;
  If RegQueryValueExA(K, Z('ProductName'), 0, LongInt(@T), LongInt(@B),
    LongInt(@N)) = 0 Then
  Begin
    B[63] := 0;
    S := ''; T := 0;
    While (T < 7) And (B[T] <> 0) Do
    Begin
      S := S + UpCase(Chr(B[T])); Inc(T);
    End;
    If S = 'PASDOWS' Then OemOut := 1;
  End;
  Dummy := RegCloseKey(K);
End;

Function Ask(Const Text, Cap : String; Fl : LongInt) : LongInt;
Var D : LongInt; A, B : Array[0..511] Of Byte;
Begin
  PutZ(A, Disp(Text)); PutZ(B, Disp(Cap));
  D := LockDepthRelease;
  Ask := MessageBoxA(MainWnd, LongInt(@A[0]), LongInt(@B[0]), Fl);
  LockDepthRestore(D);
End;

Procedure ErrBox(Const S : String);
Begin
  Dummy := Ask(S, 'Client GitHub', MB_OK Or MB_ICONERROR);
End;

Procedure Bar(Dc, X1, Y1, X2, Y2, C : LongInt);
Var Rc : Array[0..3] Of LongInt; B : LongInt;
Begin
  If (X2 <= X1) Or (Y2 <= Y1) Then Exit;
  Rc[0] := X1; Rc[1] := Y1; Rc[2] := X2; Rc[3] := Y2;
  B := CreateSolidBrush(C);
  Dummy := FillRect(Dc, LongInt(@Rc), B);
  Dummy := DeleteObject(B);
End;

Procedure Txt(Dc, X, Y : LongInt; Const S : String; Fg : LongInt);
Begin
  If S = '' Then Exit;
  PutZ(TxtBuf, Disp(S));
  Dummy := SetBkMode(Dc, TRANSPARENT);
  Dummy := SetTextColor(Dc, Fg);
  Dummy := TextOutA(Dc, X, Y, LongInt(@TxtBuf), Length(S));
End;

Function Fit(S : String; W : LongInt) : String;
Var N : LongInt;
Begin
  N := W Div CW;
  If N < 1 Then
  Begin
    Fit := ''; Exit;
  End;
  If Length(S) > N Then
  Begin
    If N > 3 Then S := Copy(S, 1, N - 3) + '...' Else S := Copy(S, 1, N);
  End;
  Fit := S;
End;

Procedure Bevel(Dc, X1, Y1, X2, Y2 : LongInt; Up : Boolean);
Var L, D : LongInt;
Begin
  If Up Then
  Begin
    L := ClrHi; D := ClrDark;
  End
  Else
  Begin
    L := ClrShadow; D := ClrHi;
  End;
  Bar(Dc, X1, Y1, X2, Y1 + 1, L); Bar(Dc, X1, Y1, X1 + 1, Y2, L);
  Bar(Dc, X1, Y2 - 1, X2, Y2, D); Bar(Dc, X2 - 1, Y1, X2, Y2, D);
  If Up Then
  Begin
    Bar(Dc, X1 + 1, Y2 - 2, X2 - 1, Y2 - 1, ClrShadow);
    Bar(Dc, X2 - 2, Y1 + 1, X2 - 1, Y2 - 1, ClrShadow);
  End
  Else
  Begin
    Bar(Dc, X1 + 1, Y1 + 1, X2 - 1, Y1 + 2, ClrDark);
    Bar(Dc, X1 + 1, Y1 + 1, X1 + 2, Y2 - 1, ClrDark);
  End;
End;

Procedure Thin(Dc, X1, Y1, X2, Y2 : LongInt; Up : Boolean);
Var L, D : LongInt;
Begin
  If Up Then
  Begin
    L := ClrHi; D := ClrShadow;
  End
  Else
  Begin
    L := ClrShadow; D := ClrHi;
  End;
  Bar(Dc, X1, Y1, X2, Y1 + 1, L); Bar(Dc, X1, Y1, X1 + 1, Y2, L);
  Bar(Dc, X1, Y2 - 1, X2, Y2, D); Bar(Dc, X2 - 1, Y1, X2, Y2, D);
End;

Procedure RegClass(Const Name : String; Proc, Style : LongInt);
Var C : TWndCls;
Begin
  PutZ(NameZ2, Name);
  C.Style := Style; C.Proc := Proc; C.ClsExtra := 0; C.WndExtra := 0;
  C.Inst := Inst; C.Icon := 0; C.Cursor := LoadCursorA(0, IDC_ARROW);
  C.Brush := 0; C.MenuName := 0; C.ClassName := LongInt(@NameZ2);
  Dummy := RegisterClassA(LongInt(@C));
End;

Function Ctl(P : LongInt; Const Cls, T : String; Style, X, Y, W, H,
  Id : LongInt) : LongInt;
Var R : LongInt;
Begin
  R := CreateWindowExA(0, Z2(Cls), Z(Disp(T)), WS_CHILD Or WS_VISIBLE Or
    Style, X, Y, W, H, P, Id, Inst, 0);
  If R <> 0 Then Dummy := SendMessageA(R, WM_SETFONT, Fnt, 0);
  Ctl := R;
End;

Function CtlText(H : LongInt) : String;
Begin
  TxtBuf[0] := 0;
  Dummy := GetWindowTextA(H, LongInt(@TxtBuf), 255);
  CtlText := UnDisp(GetZ(LongInt(@TxtBuf)));
End;

Procedure SetText(H : LongInt; Const S : String);
Begin
  Dummy := SetWindowTextA(H, Z(Disp(S)));
End;

Function Checked(H : LongInt) : Boolean;
Begin
  Checked := SendMessageA(H, BM_GETCHECK, 0, 0) <> 0;
End;

Procedure SetCheck(H : LongInt; On : Boolean);
Begin
  Dummy := SendMessageA(H, BM_SETCHECK, Ord(On), 0);
End;

Procedure Show(H : LongInt; On : Boolean);
Begin
  If H = 0 Then Exit;
  If On Then Dummy := ShowWindow(H, 5) Else Dummy := ShowWindow(H, 0);
End;

Procedure Place(H, X, Y, W, Hh : LongInt);
Begin
  If H <> 0 Then Dummy := MoveWindow(H, X, Y, MaxL(W, 1), MaxL(Hh, 1), 1);
End;

{ menus : ~ (lettre soulignee) -> & ; Id 0 : separateur }
Procedure MItem(M, Id : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If S[K] = '~' Then S[K] := '&';
  If Id = 0 Then Dummy := AppendMenuA(M, MF_SEPARATOR, 0, 0)
  Else Dummy := AppendMenuA(M, MF_STRING, Id, Z(Disp(S)));
End;

Procedure MSub(Bar0, P : LongInt; S : String);
Var K : LongInt;
Begin
  For K := 1 To Length(S) Do
    If S[K] = '~' Then S[K] := '&';
  Dummy := AppendMenuA(Bar0, MF_POPUP, P, Z(Disp(S)));
End;

Procedure MEnable(M, Id : LongInt; On : Boolean);
Begin
  If On Then Dummy := EnableMenuItem(M, Id, MF_ENABLED)
  Else Dummy := EnableMenuItem(M, Id, MF_GRAYED);
End;

Function KeyDown(V : LongInt) : Boolean;
Begin
  KeyDown := (GetKeyState(V) And $8000) <> 0;
End;

Function S16(V : LongInt) : LongInt;
Begin
  V := V And $FFFF;
  If V >= $8000 Then V := V - $10000;
  S16 := V;
End;

Procedure CopyToClip(Const S : String);
Var H, P, I : LongInt;
Begin
  H := GlobalAlloc($42, Length(S) + 1);
  If H = 0 Then Exit;
  P := GlobalLock(H);
  For I := 1 To Length(S) Do PByt(P + I - 1)^ := Ord(S[I]);
  PByt(P + Length(S))^ := 0;
  Dummy := GlobalUnlock(H);
  If OpenClipboard(MainWnd) <> 0 Then
  Begin
    Dummy := EmptyClipboard;
    Dummy := SetClipboardData(1, H);
    Dummy := CloseClipboard;
  End;
End;

{ choix d'un dossier (SHBrowseForFolderA) }
Function BrowseFolder(Const Title : String; Var Dir : String) : Boolean;
Var Bi : Array[0..7] Of LongInt; Nm, Tb, Pb : Array[0..299] Of Byte;
    P, D : LongInt;
Begin
  BrowseFolder := False;
  PutZ(Tb, Disp(Title));
  Bi[0] := MainWnd; Bi[1] := 0; Bi[2] := LongInt(@Nm); Bi[3] := LongInt(@Tb);
  Bi[4] := 1; Bi[5] := 0; Bi[6] := 0; Bi[7] := 0;
  D := LockDepthRelease;
  P := SHBrowseForFolderA(LongInt(@Bi));
  LockDepthRestore(D);
  If P = 0 Then Exit;
  Pb[0] := 0;
  If SHGetPathFromIDListA(P, LongInt(@Pb)) = 0 Then Exit;
  Dir := GetZ(LongInt(@Pb));
  BrowseFolder := Dir <> '';
End;

{ ---- reglages (GITCLI.INI) ---- }

Function IniGet(Const Sect, Key, Def : String) : String;
Var B : Array[0..299] Of Byte; A, K, D, F : Array[0..99] Of Byte;
Begin
  PutZ(A, Sect); PutZ(K, Key); PutZ(D, Def); PutZ(F, IniFile);
  B[0] := 0;
  Dummy := GetPrivateProfileStringA(LongInt(@A), LongInt(@K), LongInt(@D),
    LongInt(@B), 290, LongInt(@F));
  IniGet := GetZ(LongInt(@B));
End;

Procedure IniSet(Const Sect, Key, V : String);
Var A, K : Array[0..99] Of Byte; B : Array[0..299] Of Byte;
    F : Array[0..99] Of Byte;
Begin
  PutZ(A, Sect); PutZ(K, Key); PutZ(B, V); PutZ(F, IniFile);
  Dummy := WritePrivateProfileStringA(LongInt(@A), LongInt(@K),
    LongInt(@B), LongInt(@F));
End;

Procedure FindAppDir;
Var N : LongInt;
Begin
  N := GetModuleFileNameA(0, LongInt(@TxtBuf), 255);
  If N <= 0 Then AppDir := 'C:\'
  Else
  Begin
    TxtBuf[N] := 0;
    AppDir := GetZ(LongInt(@TxtBuf));
    N := Length(AppDir);
    While (N > 0) And (AppDir[N] <> '\') Do Dec(N);
    AppDir := Copy(AppDir, 1, N);
    If GetDriveTypeA(Z(Copy(AppDir, 1, 3))) = 5 Then
      If GetDriveTypeA(Z('C:\')) = 3 Then AppDir := 'C:\';
  End;
  IniFile := AppDir + 'GITCLI.INI';
End;
{ ==================================================================== }
{ Etat de l'application, depots, operations en arriere-plan             }
{ ==================================================================== }

Const
  MaxRepo = 30;
  OpNone = 0; OpClone = 1; OpFetch = 2; OpPull = 3; OpPush = 4;
  OpGhList = 5; OpPublish = 6; OpSignIn = 7;
  VwChanges = 0; VwHistory = 1;

Var
  RepoN, RepoCur : LongInt;
  RepoPath : Array[0..MaxRepo - 1] Of String[200];
  CloneRoot, DefName, DefEmail : String;
  View : LongInt;
  ChgSel, HistSel, FileSel : LongInt;
  HFiles : TFlat;
  HCommit : TCommit;
  HMsg : TBuf;
  Ahead, Behind : LongInt;
  HasUpstream, HasRemote : Boolean;
  CurBranch : String;
  LastFetch : LongInt;
  Busy : Boolean;
  Op : LongInt;
  OpOk : Boolean;
  OpRes : LongInt;
  OpUrl, OpDir, OpBranch, OpName, OpDesc : String;
  OpPriv : Boolean;
  WorkTid, ProgTick : LongInt;
  ProgTxt : String;
  ProgDone, ProgTotal : LongInt;
  StatusTxt : String;
  CredHost, CredUser, CredPass : String;
  DiffTitle : String;
  DiffMode : LongInt;                  { 0 vide, 1 texte, 2 binaire,
                                         3 trop grand, 4 bienvenue }

Procedure InvalidateStatus; Forward;
Procedure PaintNow; Forward;

Function SizeTxt(V : LongInt) : String;
Begin
  If V < 1024 Then SizeTxt := IStr(V) + ' o'
  Else If V < 1048576 Then SizeTxt := IStr(V Div 1024) + ' Ko'
  Else SizeTxt := IStr(V Div 1048576) + ',' + IStr((V Mod 1048576) * 10 Div
    1048576) + ' Mo';
End;

Procedure GitProgress(Const What : String; Done, Total : LongInt);
Var T : LongInt;
Begin
  ProgTxt := What; ProgDone := Done; ProgTotal := Total;
  T := GetTickCount;
  If (WorkTid <> 0) And (GetCurrentThreadId = WorkTid) Then
  Begin
    If T - ProgTick > 150 Then
    Begin
      ProgTick := T;
      Dummy := PostMessageA(MainWnd, WM_GITPROG, 0, 0);
    End;
    BigUnlock;
    Sleep(0);
    BigLock;
  End
  Else If T - ProgTick > 250 Then
  Begin
    ProgTick := T;
    PaintNow;
  End;
End;

Function ProgLine : String;
Var S : String;
Begin
  S := ProgTxt;
  If ProgTotal > 0 Then
    S := S + ' : ' + IStr((ProgDone * 100) Div MaxL(ProgTotal, 1)) + ' % (' +
      IStr(ProgDone) + '/' + IStr(ProgTotal) + ')'
  Else If ProgDone > 0 Then S := S + ' : ' + SizeTxt(ProgDone);
  ProgLine := S + '...';
End;

{ ---- liste des depots ---- }

Procedure ReposSave;
Var I : LongInt;
Begin
  IniSet('Depots', 'Nombre', IStr(RepoN));
  For I := 0 To RepoN - 1 Do IniSet('Depots', 'D' + IStr(I), RepoPath[I]);
  IniSet('Depots', 'Courant', IStr(RepoCur));
End;

Procedure ReposLoad;
Var I, E : LongInt; S : String;
Begin
  Val(IniGet('Depots', 'Nombre', '0'), RepoN, E);
  If (E <> 0) Or (RepoN < 0) Then RepoN := 0;
  If RepoN > MaxRepo Then RepoN := MaxRepo;
  For I := 0 To RepoN - 1 Do RepoPath[I] := IniGet('Depots', 'D' + IStr(I),
    '');
  Val(IniGet('Depots', 'Courant', '-1'), RepoCur, E);
  If (E <> 0) Or (RepoCur >= RepoN) Then RepoCur := -1;
  S := '';
  If S = '' Then ;
End;

Function RepoIndex(Const P : String) : LongInt;
Var I : LongInt;
Begin
  RepoIndex := -1;
  For I := 0 To RepoN - 1 Do
    If UpStr(RepoPath[I]) = UpStr(P) Then RepoIndex := I;
End;

Function RepoAdd(P : String) : LongInt;
Var K : LongInt;
Begin
  If (Length(P) > 3) And (P[Length(P)] = '\') Then Delete(P, Length(P), 1);
  K := RepoIndex(P);
  If K < 0 Then
  Begin
    If RepoN >= MaxRepo Then
    Begin
      Move(RepoPath[1], RepoPath[0], (MaxRepo - 1) * SizeOf(RepoPath[0]));
      Dec(RepoN);
    End;
    RepoPath[RepoN] := P;
    K := RepoN;
    Inc(RepoN);
  End;
  RepoAdd := K;
End;

Procedure RepoRemove(K : LongInt);
Var I : LongInt;
Begin
  If (K < 0) Or (K >= RepoN) Then Exit;
  For I := K To RepoN - 2 Do RepoPath[I] := RepoPath[I + 1];
  Dec(RepoN);
  If RepoCur = K Then RepoCur := -1
  Else If RepoCur > K Then Dec(RepoCur);
End;

Function RepoTitle(K : LongInt) : String;
Begin
  If (K < 0) Or (K >= RepoN) Then RepoTitle := ''
  Else RepoTitle := NameOf(RepoPath[K]);
End;

{ supprime un dossier et son contenu (clonage echoue) }
Procedure RmTree(Const D : String; Depth : LongInt);
Var SR : SearchRec; L : TFlat; K, J : LongInt;
Begin
  If (Depth > 30) Or (Length(D) <= 3) Then Exit;
  FlatInit(L);
  FindFirst(D + '\*.*', AnyFile, SR);
  While DosError = 0 Do
  Begin
    If (SR.Name <> '.') And (SR.Name <> '..') Then
    Begin
      K := FlatAdd(L, SR.Name);
      L.E^[K].Mode := Ord((SR.Attr And Directory) <> 0);
    End;
    FindNext(SR);
  End;
  FindClose(SR);
  For J := 0 To L.N - 1 Do
    If L.E^[J].Mode <> 0 Then RmTree(D + '\' + L.E^[J].Path, Depth + 1)
    Else FileDel(D + '\' + L.E^[J].Path);
  FlatFree(L);
  {$I-} RmDir(D); {$I+}
  If IOResult <> 0 Then ;
End;

{ ---- identifiants ---- }

Procedure SetCreds(Const Url : String);
Begin
  RemUser := ''; RemPass := '';
  If Not UrlSplit(Url) Then Exit;
  If (LowStr(UrlHost) = 'github.com') And (GhToken <> '') Then
  Begin
    If GhLogin <> '' Then RemUser := GhLogin Else RemUser := 'git';
    RemPass := GhToken;
  End
  Else If (CredHost <> '') And (LowStr(UrlHost) = CredHost) Then
  Begin
    RemUser := CredUser; RemPass := CredPass;
  End;
End;

Procedure LoadIdentity;
Var S : String;
Begin
  S := CfgGet('user', '', 'name');
  If S <> '' Then UserName := S Else UserName := AnsiToUtf8(DefName);
  S := CfgGet('user', '', 'email');
  If S <> '' Then UserEmail := S Else UserEmail := DefEmail;
  If UserName = '' Then UserName := 'Utilisateur Pasdows';
  If UserEmail = '' Then UserEmail := 'utilisateur@pasdows.local';
End;

{ ---- avance et retard sur la branche distante ---- }

Procedure AncLim(Const H : TSha; Var S : TShaSet; Max : LongInt);
Var Q : TShaList; I, J : LongInt; C : TCommit; X : TSha;
Begin
  If ShaIsZero(H) Then Exit;
  FillChar(Q, SizeOf(Q), 0);
  ListAdd(Q, H);
  I := 0;
  While (I < Q.N) And (S.N < Max) Do
  Begin
    X := Q.H^[I]; Inc(I);
    If Not SetAdd(S, X) Then Continue;
    If CommitRead(X, C, Nil) Then
      For J := 0 To C.PN - 1 Do ListAdd(Q, C.Parent[J]);
  End;
  ListFree(Q);
End;

Procedure CountAB;
Var U : TSha; A, B : TShaSet; I : LongInt;
Begin
  Ahead := 0; Behind := 0;
  HasRemote := CfgGet('remote', 'origin', 'url') <> '';
  HasUpstream := (CurBranch <> '') And
    RefRead('refs/remotes/origin/' + CurBranch, U);
  If Not HasUpstream Or ShaIsZero(HeadSha) Then Exit;
  If ShaEq(U, HeadSha) Then Exit;
  SetInit(A, 1024); SetInit(B, 1024);
  AncLim(HeadSha, A, 600);
  AncLim(U, B, 600);
  For I := 0 To A.Cap - 1 Do
    If Not ShaIsZero(A.H^[I]) And Not SetHas(B, A.H^[I]) Then Inc(Ahead);
  For I := 0 To B.Cap - 1 Do
    If Not ShaIsZero(B.H^[I]) And Not SetHas(A, B.H^[I]) Then Inc(Behind);
  SetFree(A); SetFree(B);
End;

{ ---- operations reseau (tache de travail) ---- }

Function DoOp : Boolean;
Var H : TSha; Ok : Boolean; U : String;
Begin
  DoOp := False;
  GitErr := ''; OpRes := 0;
  Case Op Of
    OpClone :
    Begin
      SetCreds(OpUrl);
      DoOp := DoClone(OpUrl, OpDir);
    End;
    OpFetch, OpPull :
    Begin
      If Not SetRepo(RepoPath[RepoCur]) Then
      Begin
        GitErr := 'd'#233'p'#244't introuvable'; Exit;
      End;
      RemUrl := CfgGet('remote', 'origin', 'url');
      If RemUrl = '' Then
      Begin
        GitErr := 'aucun d'#233'p'#244't distant (origin) n''est d'#233'fini';
        Exit;
      End;
      SetCreds(RemUrl);
      Ok := DoFetch('origin');
      If Ok Then LastFetch := GetTickCount;
      If Ok And (Op = OpPull) Then
      Begin
        Ok := False;
        If Not RepoStatus Then Exit;
        If RefRead('refs/remotes/origin/' + OpBranch, H) Then
        Begin
          OpRes := DoMerge(H, 'branch ''' + OpBranch + ''' of ' + RemUrl);
          Ok := OpRes > 0;
        End
        Else GitErr := 'la branche ' + OpBranch +
          ' n''existe pas sur le d'#233'p'#244't distant';
      End;
      DoOp := Ok;
    End;
    OpPush, OpPublish :
    Begin
      If Not SetRepo(RepoPath[RepoCur]) Then
      Begin
        GitErr := 'd'#233'p'#244't introuvable'; Exit;
      End;
      If Op = OpPublish Then
      Begin
        If Not GhCreate(OpName, OpDesc, OpPriv, U) Then Exit;
        SetRemote('origin', U);
      End;
      RemUrl := CfgGet('remote', 'origin', 'url');
      If RemUrl = '' Then
      Begin
        GitErr := 'aucun d'#233'p'#244't distant (origin) : publiez d''abord ' +
          'le d'#233'p'#244't';
        Exit;
      End;
      SetCreds(RemUrl);
      Ok := DoPush('origin', OpBranch, False);
      If Ok And (CfgGet('branch', OpBranch, 'remote') = '') Then
        SetUpstream(OpBranch, 'origin');
      DoOp := Ok;
    End;
    OpSignIn : DoOp := GhSignIn;
    OpGhList :
    Begin
      Ok := True;
      If GhLogin = '' Then Ok := GhSignIn;
      If Ok Then Ok := GhListRepos;
      DoOp := Ok;
    End;
  End;
End;

Function WorkProc(P : LongInt) : LongInt; stdcall;
Begin
  WorkTid := GetCurrentThreadId;
  BigLock;
  NetAbort := False;
  OpOk := DoOp;
  RemClose;
  BigUnlock;
  Dummy := PostMessageA(MainWnd, WM_GITDONE, 0, 0);
  WorkProc := 0;
End;

Procedure StartOp(K : LongInt);
Var Th : LongInt;
Begin
  If Busy Then Exit;
  Op := K;
  Busy := True;
  ProgTxt := 'Connexion'; ProgDone := 0; ProgTotal := 0;
  WorkTid := -1;
  Th := CreateThread(0, 0, LongInt(@WorkProc), 0, 0, LongInt(@WorkTid));
  If Th = 0 Then
  Begin
    { pas de tache : execution directe }
    WorkTid := 0;
    OpOk := DoOp;
    RemClose;
    Dummy := PostMessageA(MainWnd, WM_GITDONE, 0, 0);
  End;
  InvalidateStatus;
End;
{ ==================================================================== }
{ Listes (modifications, historique, fichiers d'un commit) et diff      }
{ ==================================================================== }

Const
  LvChg = 0; LvHist = 1; LvFiles = 2;
  SbW = 16;
  DRowH = 14;
  DHeadH = 24;

Type
  TLv = Record
    H, Sb : LongInt;
    Top, RowH, W, Hh : LongInt;
  End;

Var
  Lv : Array[0..2] Of TLv;
  DiffWnd, DSbV, DSbH : LongInt;
  DTop, DLeft, DW, DH : LongInt;
  PaintS : Array[0..15] Of LongInt;

Procedure SelectChange(I : LongInt); Forward;
Procedure SelectCommit(I : LongInt); Forward;
Procedure SelectFile(I : LongInt); Forward;
Procedure ChangesMenu(X, Y : LongInt); Forward;
Procedure CheckedChanged; Forward;

Function LvCount(K : LongInt) : LongInt;
Begin
  Case K Of
    LvChg : LvCount := Chg.N;
    LvHist : LvCount := HistN;
    Else LvCount := HFiles.N;
  End;
End;

Function LvCur(K : LongInt) : LongInt;
Begin
  Case K Of
    LvChg : LvCur := ChgSel;
    LvHist : LvCur := HistSel;
    Else LvCur := FileSel;
  End;
End;

Function LvRows(K : LongInt) : LongInt;
Begin
  LvRows := MaxL(1, Lv[K].Hh Div Lv[K].RowH);
End;

Procedure LvSync(K : LongInt);
Var M : LongInt;
Begin
  M := MaxL(0, LvCount(K) - LvRows(K));
  If Lv[K].Top > M Then Lv[K].Top := M;
  If Lv[K].Top < 0 Then Lv[K].Top := 0;
  Dummy := SetScrollRange(Lv[K].Sb, SB_CTL, 0, MaxL(M, 1), 0);
  Dummy := SetScrollPos(Lv[K].Sb, SB_CTL, Lv[K].Top, 1);
  Dummy := EnableWindow(Lv[K].Sb, Ord(M > 0));
End;

Procedure LvRepaint(K : LongInt);
Begin
  If Lv[K].H <> 0 Then Dummy := InvalidateRect(Lv[K].H, 0, 0);
End;

Procedure LvVisible(K : LongInt);
Var C : LongInt;
Begin
  C := LvCur(K);
  If C < 0 Then Exit;
  If C < Lv[K].Top Then Lv[K].Top := C;
  If C >= Lv[K].Top + LvRows(K) Then Lv[K].Top := C - LvRows(K) + 1;
  LvSync(K);
End;

{ icone d'etat d'un fichier (carre de 12 points) }
Procedure StIcon(Dc, X, Y, St : LongInt);
Var C : LongInt;
Begin
  Case St Of
    StNew : C := ClrAddI;
    StDel : C := ClrDelI;
    StConf : C := ClrConfI;
    Else C := ClrModI;
  End;
  Bar(Dc, X, Y, X + 12, Y + 12, C);
  Bar(Dc, X + 1, Y + 1, X + 11, Y + 11, ClrWin);
  Case St Of
    StNew :
    Begin
      Bar(Dc, X + 3, Y + 5, X + 9, Y + 7, C);
      Bar(Dc, X + 5, Y + 3, X + 7, Y + 9, C);
    End;
    StDel : Bar(Dc, X + 3, Y + 5, X + 9, Y + 7, C);
    StConf :
    Begin
      Bar(Dc, X + 5, Y + 2, X + 7, Y + 7, C);
      Bar(Dc, X + 5, Y + 8, X + 7, Y + 10, C);
    End;
    Else Bar(Dc, X + 4, Y + 4, X + 8, Y + 8, C);
  End;
End;

{ case a cocher de Windows 95 (13 points) }
Procedure CheckBox(Dc, X, Y : LongInt; On, Gray : Boolean);
Var I, C : LongInt;
Begin
  Bevel(Dc, X, Y, X + 13, Y + 13, False);
  If Gray Then Bar(Dc, X + 2, Y + 2, X + 11, Y + 11, ClrFace)
  Else Bar(Dc, X + 2, Y + 2, X + 11, Y + 11, ClrWin);
  If Not On Then Exit;
  C := ClrBlack;
  If Gray Then C := ClrGray;
  For I := 0 To 2 Do Bar(Dc, X + 3 + I, Y + 5 + I, X + 4 + I, Y + 8 + I, C);
  For I := 0 To 3 Do Bar(Dc, X + 6 + I, Y + 6 - I, X + 7 + I, Y + 9 - I, C);
End;

Function DirOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  DirOf := Copy(P, 1, K);
End;

Function FileOf(Const P : String) : String;
Var K : LongInt;
Begin
  K := Length(P);
  While (K > 0) And (P[K] <> '/') Do Dec(K);
  FileOf := Copy(P, K + 1, 255);
End;

Procedure LvPaint(K, H : LongInt);
Var Dc, R, Y, N, I, Fg, Fg2, Bg, X, St : LongInt; S, D : String;
    Sel : Boolean;
Begin
  Dc := BeginPaint(H, LongInt(@PaintS));
  Dummy := SelectObject(Dc, Fnt);
  N := LvCount(K);
  For R := 0 To LvRows(K) Do
  Begin
    I := Lv[K].Top + R;
    Y := R * Lv[K].RowH;
    Sel := (I < N) And (I = LvCur(K));
    If Sel Then
    Begin
      Bg := ClrNavy; Fg := ClrWin; Fg2 := ClrLight;
    End
    Else
    Begin
      Bg := ClrWin; Fg := ClrBlack; Fg2 := ClrGray;
    End;
    Bar(Dc, 0, Y, Lv[K].W, Y + Lv[K].RowH, Bg);
    If I >= N Then Continue;
    Case K Of
      LvChg :
      Begin
        St := Chg.E^[I].Flag And $FF;
        CheckBox(Dc, 4, Y + 3, (Chg.E^[I].Flag And FlSel) <> 0, False);
        D := Utf8ToAnsi(DirOf(Chg.E^[I].Path));
        S := Utf8ToAnsi(FileOf(Chg.E^[I].Path));
        X := 24;
        If D <> '' Then
        Begin
          D := Fit(D, MaxL(30, Lv[K].W - 48 - Length(S) * CW));
          Txt(Dc, X, Y + 3, D, Fg2);
          X := X + Length(D) * CW;
        End;
        Txt(Dc, X, Y + 3, Fit(S, Lv[K].W - X - 22), Fg);
        StIcon(Dc, Lv[K].W - 17, Y + 4, St);
      End;
      LvHist :
      Begin
        Txt(Dc, 8, Y + 3, Fit(Utf8ToAnsi(Hist^[I].Summary), Lv[K].W - 14),
          Fg);
        Txt(Dc, 8, Y + 18, Fit(Utf8ToAnsi(Hist^[I].Author) + ' '#149' ' +
          UnixToStr(Hist^[I].Time), Lv[K].W - 14), Fg2);
        If Not Sel Then Bar(Dc, 0, Y + Lv[K].RowH - 1, Lv[K].W,
          Y + Lv[K].RowH, ClrLight);
      End;
      Else
      Begin
        St := HFiles.E^[I].Flag And $FF;
        D := Utf8ToAnsi(DirOf(HFiles.E^[I].Path));
        S := Utf8ToAnsi(FileOf(HFiles.E^[I].Path));
        X := 8;
        If D <> '' Then
        Begin
          D := Fit(D, MaxL(30, Lv[K].W - 30 - Length(S) * CW));
          Txt(Dc, X, Y + 2, D, Fg2);
          X := X + Length(D) * CW;
        End;
        Txt(Dc, X, Y + 2, Fit(S, Lv[K].W - X - 22), Fg);
        StIcon(Dc, Lv[K].W - 17, Y + 3, St);
      End;
    End;
  End;
  If N = 0 Then
  Begin
    If K = LvChg Then S := 'Aucune modification'
    Else If K = LvHist Then S := 'Aucun commit'
    Else S := '';
    Txt(Dc, MaxL(4, (Lv[K].W - Length(S) * CW) Div 2), 20, S, ClrGray);
  End;
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

Procedure LvSelect(K, I : LongInt);
Begin
  If (I < 0) Or (I >= LvCount(K)) Then Exit;
  Case K Of
    LvChg : SelectChange(I);
    LvHist : SelectCommit(I);
    Else SelectFile(I);
  End;
  LvVisible(K);
  LvRepaint(K);
End;

Procedure LvKey(K, VK : LongInt);
Var C, N : LongInt;
Begin
  C := LvCur(K); N := LvCount(K);
  If N = 0 Then Exit;
  Case VK Of
    VK_UP : LvSelect(K, MaxL(0, C - 1));
    VK_DOWN : LvSelect(K, MinL(N - 1, C + 1));
    VK_PRIOR : LvSelect(K, MaxL(0, C - LvRows(K) + 1));
    VK_NEXT : LvSelect(K, MinL(N - 1, C + LvRows(K) - 1));
    VK_HOME : LvSelect(K, 0);
    VK_END : LvSelect(K, N - 1);
    VK_SPACE :
      If (K = LvChg) And (C >= 0) Then
      Begin
        Chg.E^[C].Flag := Chg.E^[C].Flag Xor FlSel;
        LvRepaint(K);
        CheckedChanged;
      End;
  End;
End;

Function LvOf(H : LongInt) : LongInt;
Var K : LongInt;
Begin
  LvOf := -1;
  For K := 0 To 2 Do
    If Lv[K].H = H Then LvOf := K;
End;

Procedure LvScroll(K, Code, Pos : LongInt);
Begin
  Case Code Of
    SB_LINEUP : Dec(Lv[K].Top);
    SB_LINEDOWN : Inc(Lv[K].Top);
    SB_PAGEUP : Dec(Lv[K].Top, LvRows(K) - 1);
    SB_PAGEDOWN : Inc(Lv[K].Top, LvRows(K) - 1);
    SB_THUMBTRACK, SB_THUMBPOSITION : Lv[K].Top := Pos;
    SB_TOP : Lv[K].Top := 0;
    SB_BOTTOM : Lv[K].Top := LvCount(K);
  End;
  LvSync(K);
  LvRepaint(K);
End;

Function LvProc0(H, Msg, WP, LP : LongInt) : LongInt;
Var K, X, Y, I : LongInt;
Begin
  LvProc0 := 0;
  K := LvOf(H);
  If K < 0 Then
  Begin
    LvProc0 := DefWindowProcA(H, Msg, WP, LP); Exit;
  End;
  Case Msg Of
    WM_PAINT : LvPaint(K, H);
    WM_ERASEBKGND : LvProc0 := 1;
    WM_SIZE :
    Begin
      Lv[K].W := (LP And $FFFF) - SbW; Lv[K].Hh := (LP Shr 16) And $FFFF;
      Place(Lv[K].Sb, Lv[K].W, 0, SbW, Lv[K].Hh);
      LvSync(K);
    End;
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK, WM_RBUTTONDOWN :
    Begin
      Dummy := SetFocus(H);
      If Busy Then Exit;
      X := S16(LP); Y := S16(LP Shr 16);
      I := Lv[K].Top + Y Div Lv[K].RowH;
      If (I >= 0) And (I < LvCount(K)) Then
      Begin
        If (K = LvChg) And (X < 22) And (Msg <> WM_RBUTTONDOWN) Then
        Begin
          Chg.E^[I].Flag := Chg.E^[I].Flag Xor FlSel;
          LvRepaint(K);
          CheckedChanged;
        End;
        If I <> LvCur(K) Then LvSelect(K, I);
        If (K = LvChg) And (Msg = WM_RBUTTONDOWN) Then ChangesMenu(X, Y);
      End;
    End;
    WM_KEYDOWN : If Not Busy Then LvKey(K, WP);
    WM_VSCROLL : LvScroll(K, WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_MOUSEWHEEL :
    Begin
      If S16(WP Shr 16) > 0 Then Dec(Lv[K].Top, 3) Else Inc(Lv[K].Top, 3);
      LvSync(K);
      LvRepaint(K);
    End;
  Else
    LvProc0 := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function LvProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  BigLock;
  LvProc := LvProc0(H, Msg, WP, LP);
  BigUnlock;
End;

{ ---- vue des differences ---- }

Function ExpandTabs(Const S : String) : String;
Var I, K : LongInt; R : String;
Begin
  R := '';
  For I := 1 To Length(S) Do
    If S[I] = #9 Then
    Begin
      K := 4 - (Length(R) Mod 4);
      While (K > 0) And (Length(R) < 250) Do
      Begin
        R := R + ' '; Dec(K);
      End;
    End
    Else If Length(R) < 250 Then R := R + S[I];
  ExpandTabs := R;
End;

Function DRows : LongInt;
Begin
  DRows := MaxL(1, (DH - DHeadH) Div DRowH);
End;

Function DCols : LongInt;
Begin
  DCols := MaxL(1, (DW - 90) Div CW);
End;

Procedure DiffSync;
Var M : LongInt;
Begin
  M := 0;
  If DiffMode = 1 Then M := MaxL(0, DfN - DRows);
  If DTop > M Then DTop := M;
  If DTop < 0 Then DTop := 0;
  Dummy := SetScrollRange(DSbV, SB_CTL, 0, MaxL(M, 1), 0);
  Dummy := SetScrollPos(DSbV, SB_CTL, DTop, 1);
  Dummy := EnableWindow(DSbV, Ord(M > 0));
  M := MaxL(0, 250 - DCols);
  If DLeft > M Then DLeft := M;
  If DLeft < 0 Then DLeft := 0;
  Dummy := SetScrollRange(DSbH, SB_CTL, 0, MaxL(M, 1), 0);
  Dummy := SetScrollPos(DSbH, SB_CTL, DLeft, 1);
  Dummy := EnableWindow(DSbH, Ord((M > 0) And (DiffMode = 1)));
End;

Procedure DiffRepaint;
Begin
  If DiffWnd <> 0 Then Dummy := InvalidateRect(DiffWnd, 0, 0);
End;

Procedure DiffReset;
Begin
  DTop := 0; DLeft := 0;
  DiffSync;
  DiffRepaint;
End;

Procedure CenterTxt(Dc, Y : LongInt; Const S : String; C : LongInt);
Begin
  Txt(Dc, MaxL(4, (DW - Length(S) * CW) Div 2), Y, S, C);
End;

Procedure DiffPaint(H : LongInt);
Var Dc, R, I, Y, Bg, Gb, Fg, X : LongInt; S, A, B : String;
Begin
  Dc := BeginPaint(H, LongInt(@PaintS));
  Dummy := SelectObject(Dc, Fnt);
  { en-tete : chemin du fichier }
  Bar(Dc, 0, 0, DW, DHeadH, ClrFace);
  Thin(Dc, 0, 0, DW, DHeadH, True);
  If DiffTitle <> '' Then
  Begin
    S := '';
    If DiffMode = 1 Then
      S := '  +' + IStr(DfAdd) + ' -' + IStr(DfDel);
    Txt(Dc, 8, 5, Fit(Utf8ToAnsi(DiffTitle), DW - 16 - Length(S) * CW),
      ClrBlack);
    If S <> '' Then
    Begin
      X := DW - 8 - Length(S) * CW;
      Txt(Dc, X, 5, '  +' + IStr(DfAdd), ClrGreen);
      Txt(Dc, X + (Length(IStr(DfAdd)) + 4) * CW, 5, '-' + IStr(DfDel),
        ClrRed);
    End;
  End;
  Bar(Dc, 0, DHeadH, DW, DH, ClrWin);
  Case DiffMode Of
    0 :
    Begin
      If (RepoCur >= 0) And (View = VwChanges) And (Chg.N = 0) Then
      Begin
        CenterTxt(Dc, DHeadH + 60, 'Aucune modification locale', ClrBlack);
        CenterTxt(Dc, DHeadH + 84, 'Il n''y a aucune modification non ' +
          'valid'#233'e dans ce d'#233'p'#244't.', ClrGray);
        If Ahead > 0 Then
          CenterTxt(Dc, DHeadH + 108, IStr(Ahead) + ' commit(s) local(aux) '
            + #224' pousser vers origin (Ctrl+P).', ClrNavy)
        Else If Behind > 0 Then
          CenterTxt(Dc, DHeadH + 108, IStr(Behind) + ' commit(s) '#224' ' +
            'tirer depuis origin (Ctrl+Maj+P).', ClrNavy)
        Else
          CenterTxt(Dc, DHeadH + 108, 'Ouvrez le d'#233'p'#244't dans ' +
            'l''Explorateur (Ctrl+Maj+F) pour le modifier.', ClrGray);
      End;
    End;
    2 : CenterTxt(Dc, DHeadH + 60, 'Fichier binaire : diff'#233'rences non ' +
          'affich'#233'es.', ClrGray);
    3 : CenterTxt(Dc, DHeadH + 60, 'Fichier trop volumineux pour afficher ' +
          'les diff'#233'rences.', ClrGray);
    1 :
    Begin
      If DfN = 0 Then
        CenterTxt(Dc, DHeadH + 60, 'Aucune diff'#233'rence de contenu (fichier '
          + 'vide ou mode modifi'#233').', ClrGray);
      For R := 0 To DRows Do
      Begin
        I := DTop + R;
        If I >= DfN Then Break;
        Y := DHeadH + R * DRowH;
        A := ''; B := '';
        Case Df^[I].K Of
          DkAdd :
          Begin
            Bg := ClrAddBg; Gb := ClrAddG; Fg := ClrBlack;
            B := IStr(Df^[I].LB + 1);
          End;
          DkDel :
          Begin
            Bg := ClrDelBg; Gb := ClrDelG; Fg := ClrBlack;
            A := IStr(Df^[I].LA + 1);
          End;
          DkHunk :
          Begin
            Bg := ClrHunk; Gb := ClrHunk; Fg := ClrHunkT;
          End;
          Else
          Begin
            Bg := ClrWin; Gb := ClrWin; Fg := ClrBlack;
            A := IStr(Df^[I].LA + 1); B := IStr(Df^[I].LB + 1);
          End;
        End;
        Bar(Dc, 0, Y, 76, Y + DRowH, Gb);
        Bar(Dc, 76, Y, DW, Y + DRowH, Bg);
        Bar(Dc, 76, Y, 77, Y + DRowH, ClrLight);
        If A <> '' Then Txt(Dc, 34 - Length(A) * CW, Y + 1, A, ClrGray);
        If B <> '' Then Txt(Dc, 70 - Length(B) * CW, Y + 1, B, ClrGray);
        Case Df^[I].K Of
          DkAdd : Txt(Dc, 80, Y + 1, '+', ClrGreen);
          DkDel : Txt(Dc, 80, Y + 1, '-', ClrRed);
        End;
        S := ExpandTabs(Utf8ToAnsi(DiffText(I)));
        If Df^[I].K = DkHunk Then
          Txt(Dc, 88, Y + 1, Copy(S, 1, DCols), Fg)
        Else Txt(Dc, 88, Y + 1, Copy(S, DLeft + 1, DCols), Fg);
      End;
    End;
  End;
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

Procedure DiffScroll(Vert : Boolean; Code, Pos : LongInt);
Var V, Pg : LongInt;
Begin
  If Vert Then
  Begin
    V := DTop; Pg := DRows - 1;
  End
  Else
  Begin
    V := DLeft; Pg := DCols - 4;
  End;
  Case Code Of
    SB_LINEUP : Dec(V);
    SB_LINEDOWN : Inc(V);
    SB_PAGEUP : Dec(V, Pg);
    SB_PAGEDOWN : Inc(V, Pg);
    SB_THUMBTRACK, SB_THUMBPOSITION : V := Pos;
    SB_TOP : V := 0;
    SB_BOTTOM : V := 1000000;
  End;
  If Vert Then DTop := V Else DLeft := V;
  DiffSync;
  DiffRepaint;
End;

Function DiffProc0(H, Msg, WP, LP : LongInt) : LongInt;
Begin
  DiffProc0 := 0;
  Case Msg Of
    WM_PAINT : DiffPaint(H);
    WM_ERASEBKGND : DiffProc0 := 1;
    WM_SIZE :
    Begin
      DW := (LP And $FFFF) - SbW; DH := ((LP Shr 16) And $FFFF) - SbW;
      Place(DSbV, DW, DHeadH, SbW, DH - DHeadH);
      Place(DSbH, 0, DH, DW, SbW);
      DiffSync;
    End;
    WM_LBUTTONDOWN : Dummy := SetFocus(H);
    WM_VSCROLL : DiffScroll(True, WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_HSCROLL : DiffScroll(False, WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_MOUSEWHEEL :
    Begin
      If S16(WP Shr 16) > 0 Then Dec(DTop, 3) Else Inc(DTop, 3);
      DiffSync;
      DiffRepaint;
    End;
    WM_KEYDOWN :
      Case WP Of
        VK_UP : DiffScroll(True, SB_LINEUP, 0);
        VK_DOWN : DiffScroll(True, SB_LINEDOWN, 0);
        VK_PRIOR : DiffScroll(True, SB_PAGEUP, 0);
        VK_NEXT : DiffScroll(True, SB_PAGEDOWN, 0);
        VK_HOME : DiffScroll(True, SB_TOP, 0);
        VK_END : DiffScroll(True, SB_BOTTOM, 0);
        VK_LEFT : DiffScroll(False, SB_LINEUP, 0);
        VK_RIGHT : DiffScroll(False, SB_LINEDOWN, 0);
      End;
  Else
    DiffProc0 := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function DiffProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  BigLock;
  DiffProc := DiffProc0(H, Msg, WP, LP);
  BigUnlock;
End;

{ charge les deux versions et calcule le diff }
Procedure DiffLoad(Const OldSha, NewSha : TSha; FromWork : Boolean;
  Const Path : String; St : LongInt);
Begin
  DiffTitle := Path;
  DfA.N := 0; DfB.N := 0;
  DiffMode := 1;
  If Not ShaIsZero(OldSha) Then
    If Not BlobLoad(OldSha, DfA) Then DfA.N := 0;
  If St <> StDel Then
  Begin
    If FromWork Then
    Begin
      If Not FileLoad(WorkPath(Path), DfB) Then DfB.N := 0;
    End
    Else If Not BlobLoad(NewSha, DfB) Then DfB.N := 0;
  End;
  If DfA.N + DfB.N > 3000000 Then
  Begin
    DiffMode := 3; DfN := 0;
  End
  Else
  Begin
    DiffBuild;
    If DfBin Then DiffMode := 2;
  End;
  DiffReset;
End;

Procedure DiffClear;
Begin
  DiffTitle := '';
  DiffMode := 0;
  DfN := 0;
  DiffReset;
End;
{ ==================================================================== }
{ Boites de dialogue                                                    }
{ ==================================================================== }

Const
  DgInput = 1; DgClone = 2; DgNew = 3; DgAdd = 4; DgOptions = 5;
  DgPublish = 6; DgMerge = 7; DgCred = 8; DgRepoSet = 9;
  IdInput = 120;
  IdList = 201; IdRefresh = 202; IdUrl = 203; IdPath = 204; IdBrowse = 205;
  IdName = 206; IdDesc = 207; IdReadme = 208; IdPriv = 209; IdToken = 210;
  IdSignIn = 211; IdSignOut = 212; IdUName = 213; IdUMail = 214;
  IdProxy = 215; IdRoot = 216; IdLogin = 217; IdUser = 218; IdPass = 219;
  IdInfo = 220;

Var
  DlgWnd, DlgKind, DlgRes : LongInt;
  DlgDone : Boolean;
  DlgText : String;
  InpEdit : LongInt;
  DC : Array[200..230] Of LongInt;
  PathEdited, DlgSync : Boolean;
  MergeRefs : Array[0..199] Of String[120];
  MergeN : LongInt;
  DlgOut : Array[0..7] Of String;

Procedure RefreshRepo(Keep : Boolean); Forward;

Procedure ModalLoop;
Var D : LongInt;
Begin
  Dummy := EnableWindow(MainWnd, 0);
  While Not DlgDone Do
  Begin
    D := LockDepthRelease;
    If GetMessageA(LongInt(@Qmsg), 0, 0, 0) <= 0 Then
    Begin
      LockDepthRestore(D);
      Break;
    End;
    LockDepthRestore(D);
    Dummy := TranslateMessage(LongInt(@Qmsg));
    Dummy := DispatchMessageA(LongInt(@Qmsg));
  End;
  Dummy := EnableWindow(MainWnd, 1);
  If DlgWnd <> 0 Then Dummy := DestroyWindow(DlgWnd);
  DlgWnd := 0;
  Dummy := SetFocus(MainWnd);
End;

Function DlgCreate(Const Title : String; W, H : LongInt) : LongInt;
Var Rc : Array[0..3] Of LongInt; Fw, Fh, St, I : LongInt;
Begin
  For I := 200 To 230 Do DC[I] := 0;
  St := WS_POPUP Or WS_CAPTION Or WS_SYSMENU;
  Rc[0] := 0; Rc[1] := 0; Rc[2] := W; Rc[3] := H;
  Dummy := AdjustWindowRectEx(LongInt(@Rc), St, 0, WS_EX_DLGMODALFRAME);
  Fw := Rc[2] - Rc[0]; Fh := Rc[3] - Rc[1];
  DlgDone := False; DlgRes := IDCANCEL;
  DlgWnd := CreateWindowExA(WS_EX_DLGMODALFRAME, Z2('GCDLG'), Z(Disp(Title)),
    St, MaxL(0, (GetSystemMetrics(SM_CXSCREEN) - Fw) Div 2),
    MaxL(0, (GetSystemMetrics(SM_CYSCREEN) - 28 - Fh) Div 2), Fw, Fh,
    MainWnd, 0, Inst, 0);
  DlgCreate := DlgWnd;
End;

Procedure Lbl(P : LongInt; Const S : String; X, Y, W : LongInt);
Begin
  Dummy := Ctl(P, 'STATIC', S, 0, X, Y, W, 14, 0);
End;

Function DEdit(Id, X, Y, W : LongInt; Const S : String; Pw : Boolean)
  : LongInt;
Var St : LongInt;
Begin
  St := WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP;
  If Pw Then St := St Or ES_PASSWORD;
  DC[Id] := Ctl(DlgWnd, 'EDIT', S, St, X, Y, W, 20, Id);
  DEdit := DC[Id];
End;

Procedure DButtons(W, H : LongInt; Const OkTxt : String);
Var Bw : LongInt;
Begin
  Bw := MaxL(84, Length(OkTxt) * CW + 20);
  Dummy := Ctl(DlgWnd, 'BUTTON', OkTxt, BS_DEFPUSHBUTTON Or WS_TABSTOP,
    W - Bw - 96, H - 34, Bw, 24, IDOK);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Annuler', WS_TABSTOP, W - 88, H - 34, 76,
    24, IDCANCEL);
End;

Function DText(Id : LongInt) : String;
Begin
  If DC[Id] = 0 Then DText := '' Else DText := TrimS(CtlText(DC[Id]));
End;

Function InputBox(Const Title, Prompt : String; Var S : String) : Boolean;
Var W : LongInt;
Begin
  InputBox := False;
  DlgKind := DgInput;
  W := MaxL(320, Length(Prompt) * CW + 24);
  If W > 560 Then W := 560;
  If DlgCreate(Title, W, 100) = 0 Then Exit;
  Lbl(DlgWnd, Prompt, 12, 10, W - 24);
  InpEdit := Ctl(DlgWnd, 'EDIT', S, WS_BORDER Or ES_AUTOHSCROLL Or
    WS_TABSTOP, 12, 30, W - 24, 20, IdInput);
  DButtons(W, 100, 'OK');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(InpEdit);
  Dummy := SendMessageA(InpEdit, EM_SETSEL, 0, -1);
  ModalLoop;
  If DlgRes = IDOK Then
  Begin
    S := TrimS(DlgText);
    InputBox := True;
  End;
End;

{ nom du depot d'apres une URL (.../nom.git) }
Function UrlRepoName(S : String) : String;
Var K : LongInt;
Begin
  While (S <> '') And (S[Length(S)] = '/') Do Delete(S, Length(S), 1);
  K := Length(S);
  While (K > 0) And (S[K] <> '/') And (S[K] <> ':') Do Dec(K);
  S := Copy(S, K + 1, 255);
  If LowStr(Copy(S, Length(S) - 3, 4)) = '.git' Then
    Delete(S, Length(S) - 3, 4);
  UrlRepoName := S;
End;

{ « utilisateur/depot » -> https://github.com/utilisateur/depot.git }
Function NormUrl(S : String) : String;
Begin
  S := TrimS(S);
  If (S <> '') And (Pos('://', S) = 0) And (Pos('/', S) > 0) And
     (Pos(' ', S) = 0) Then
  Begin
    If LowStr(Copy(S, 1, 11)) = 'github.com/' Then S := 'https://' + S
    Else S := 'https://github.com/' + S;
    If LowStr(Copy(S, Length(S) - 3, 4)) <> '.git' Then S := S + '.git';
  End;
  NormUrl := S;
End;

Function JoinDir(Const D, N : String) : String;
Begin
  If (D <> '') And (D[Length(D)] = '\') Then JoinDir := D + N
  Else JoinDir := D + '\' + N;
End;

Function DirEmpty(Const D : String) : Boolean;
Var SR : SearchRec; N : LongInt;
Begin
  N := 0;
  FindFirst(D + '\*.*', AnyFile, SR);
  While DosError = 0 Do
  Begin
    If (SR.Name <> '.') And (SR.Name <> '..') Then Inc(N);
    FindNext(SR);
  End;
  FindClose(SR);
  DirEmpty := N = 0;
End;

Procedure CloneFill;
Var I : LongInt;
Begin
  If DC[IdList] = 0 Then Exit;
  Dummy := SendMessageA(DC[IdList], LB_RESETCONTENT, 0, 0);
  For I := 0 To GhN - 1 Do
    If GhPriv[I] Then
      Dummy := SendMessageA(DC[IdList], LB_ADDSTRING, 0,
        Z(Disp(Utf8ToAnsi(GhName[I]) + '  (priv'#233')')))
    Else Dummy := SendMessageA(DC[IdList], LB_ADDSTRING, 0,
      Z(Disp(Utf8ToAnsi(GhName[I]))));
  If GhLogin <> '' Then
    SetText(DC[IdInfo], 'D'#233'p'#244'ts GitHub de ' + GhLogin + ' (' +
      IStr(GhN) + ') :')
  Else SetText(DC[IdInfo], 'D'#233'p'#244'ts GitHub : connectez-vous dans ' +
    'Fichier > Options.');
End;

Procedure CloneRefreshList;
Begin
  If GhToken = '' Then
  Begin
    ErrBox('Pour lister vos d'#233'p'#244'ts GitHub, entrez d''abord un jeton '
      + 'd''acc'#232's personnel dans Fichier > Options.');
    Exit;
  End;
  Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
  If GhLogin = '' Then
    If Not GhSignIn Then
    Begin
      ErrBox('Connexion '#224' GitHub impossible : ' + GitErr);
      Exit;
    End;
  If Not GhListRepos Then ErrBox('Liste des d'#233'p'#244'ts : ' + GitErr);
  CloneFill;
  Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
End;

Procedure ClonePathFromUrl;
Var N : String;
Begin
  If PathEdited Then Exit;
  N := UrlRepoName(NormUrl(DText(IdUrl)));
  DlgSync := True;
  If N <> '' Then SetText(DC[IdPath], JoinDir(CloneRoot, N))
  Else SetText(DC[IdPath], CloneRoot);
  DlgSync := False;
End;

Function CloneDialog : Boolean;
Const W = 470; H = 340;
Begin
  CloneDialog := False;
  DlgKind := DgClone;
  PathEdited := False; DlgSync := False;
  If DlgCreate('Cloner un d'#233'p'#244't', W, H) = 0 Then Exit;
  DC[IdInfo] := Ctl(DlgWnd, 'STATIC', '', 0, 12, 10, W - 150, 14, IdInfo);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Actualiser la liste', WS_TABSTOP,
    W - 132, 6, 120, 22, IdRefresh);
  DC[IdList] := Ctl(DlgWnd, 'LISTBOX', '', WS_BORDER Or WS_VSCROLL Or
    LBS_NOTIFY Or WS_TABSTOP, 12, 32, W - 24, 126, IdList);
  Lbl(DlgWnd, 'URL ou nom d''utilisateur/d'#233'p'#244't (http, https, ' +
    'git://) :', 12, 168, W - 24);
  Dummy := DEdit(IdUrl, 12, 186, W - 24, '', False);
  Lbl(DlgWnd, 'Chemin local :', 12, 218, W - 24);
  Dummy := DEdit(IdPath, 12, 236, W - 120, CloneRoot, False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Parcourir...', WS_TABSTOP, W - 100, 235,
    88, 22, IdBrowse);
  Lbl(DlgWnd, 'Exemple : octocat/Hello-World ou https://serveur/projet.git',
    12, 266, W - 24);
  DButtons(W, H, 'Cloner');
  CloneFill;
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdUrl]);
  ModalLoop;
  If DlgRes = IDOK Then
  Begin
    OpUrl := DlgOut[0]; OpDir := DlgOut[1];
    CloneDialog := True;
  End;
End;

Procedure CloneCommand(Id, Code : LongInt);
Var I : LongInt; S, P : String;
Begin
  Case Id Of
    IdRefresh : CloneRefreshList;
    IdList :
      If (Code = LBN_SELCHANGE) Or (Code = LBN_DBLCLK) Then
      Begin
        I := SendMessageA(DC[IdList], LB_GETCURSEL, 0, 0);
        If (I >= 0) And (I < GhN) Then
        Begin
          PathEdited := False;
          SetText(DC[IdUrl], GhUrl[I]);
          ClonePathFromUrl;
        End;
      End;
    IdUrl : If Code = EN_CHANGE Then ClonePathFromUrl;
    IdPath : If (Code = EN_CHANGE) And Not DlgSync Then PathEdited := True;
    IdBrowse :
    Begin
      S := CloneRoot;
      If BrowseFolder('Dossier o'#249' cloner le d'#233'p'#244't', S) Then
      Begin
        P := UrlRepoName(NormUrl(DText(IdUrl)));
        If P <> '' Then S := JoinDir(S, P);
        DlgSync := True;
        SetText(DC[IdPath], S);
        DlgSync := False;
        PathEdited := True;
      End;
    End;
    IDOK :
    Begin
      S := NormUrl(DText(IdUrl));
      P := DText(IdPath);
      If Not UrlSplit(S) Then
      Begin
        ErrBox('Entrez une URL de d'#233'p'#244't valable (https://..., ' +
          'http://..., git://...) ou un nom utilisateur/d'#233'p'#244't.');
        Exit;
      End;
      If (P = '') Or (Pos(':', P) = 0) Then
      Begin
        ErrBox('Entrez un chemin local complet (par exemple C:\Mes ' +
          'documents\GitHub\projet).');
        Exit;
      End;
      If DirExist(P) And Not DirEmpty(P) Then
      Begin
        ErrBox('Le dossier ' + P + ' existe d'#233'j'#224' et n''est pas ' +
          'vide.');
        Exit;
      End;
      DlgOut[0] := S; DlgOut[1] := P;
      DlgRes := IDOK; DlgDone := True;
    End;
    IDCANCEL :
    Begin
      DlgRes := IDCANCEL; DlgDone := True;
    End;
  End;
End;

{ ---- nouveau depot ---- }

Function NewRepoDialog : Boolean;
Const W = 430; H = 268;
Begin
  NewRepoDialog := False;
  DlgKind := DgNew;
  If DlgCreate('Cr'#233'er un nouveau d'#233'p'#244't', W, H) = 0 Then Exit;
  Lbl(DlgWnd, 'Nom :', 12, 12, 120);
  Dummy := DEdit(IdName, 12, 30, W - 24, '', False);
  Lbl(DlgWnd, 'Description :', 12, 60, 200);
  Dummy := DEdit(IdDesc, 12, 78, W - 24, '', False);
  Lbl(DlgWnd, 'Chemin local (le dossier du d'#233'p'#244't y sera cr'#233
    + #233') :', 12, 108, W - 24);
  Dummy := DEdit(IdPath, 12, 126, W - 120, CloneRoot, False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Parcourir...', WS_TABSTOP, W - 100, 125,
    88, 22, IdBrowse);
  DC[IdReadme] := Ctl(DlgWnd, 'BUTTON', 'Initialiser ce d'#233'p'#244't ' +
    'avec un fichier README', BS_AUTOCHECKBOX Or WS_TABSTOP, 12, 160,
    W - 24, 18, IdReadme);
  SetCheck(DC[IdReadme], True);
  DC[IdPriv] := Ctl(DlgWnd, 'BUTTON', 'Ajouter un fichier .gitignore ' +
    '(*.EXE, *.OBJ, *.TMP, *.BAK)', BS_AUTOCHECKBOX Or WS_TABSTOP, 12, 184,
    W - 24, 18, IdPriv);
  DButtons(W, H, 'Cr'#233'er le d'#233'p'#244't');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdName]);
  ModalLoop;
  NewRepoDialog := DlgRes = IDOK;
End;

{ ---- ajouter un depot local ---- }

Function AddLocalDialog : Boolean;
Const W = 430; H = 120;
Begin
  AddLocalDialog := False;
  DlgKind := DgAdd;
  If DlgCreate('Ajouter un d'#233'p'#244't local', W, H) = 0 Then Exit;
  Lbl(DlgWnd, 'Chemin local du d'#233'p'#244't :', 12, 12, W - 24);
  Dummy := DEdit(IdPath, 12, 30, W - 120, CloneRoot, False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Parcourir...', WS_TABSTOP, W - 100, 29,
    88, 22, IdBrowse);
  DButtons(W, H, 'Ajouter le d'#233'p'#244't');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdPath]);
  Dummy := SendMessageA(DC[IdPath], EM_SETSEL, 0, -1);
  ModalLoop;
  AddLocalDialog := DlgRes = IDOK;
End;

{ ---- options ---- }

Procedure OptShowLogin;
Begin
  If GhLogin <> '' Then SetText(DC[IdLogin], 'Connect'#233' '#224' GitHub : '
    + GhLogin)
  Else If GhToken <> '' Then SetText(DC[IdLogin], 'Jeton enregistr'#233' ' +
    '(non v'#233'rifi'#233')')
  Else SetText(DC[IdLogin], 'Non connect'#233' '#224' GitHub.com');
End;

Function OptionsDialog : Boolean;
Const W = 460; H = 372;
Begin
  OptionsDialog := False;
  DlgKind := DgOptions;
  If DlgCreate('Options', W, H) = 0 Then Exit;
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Compte GitHub.com', BS_GROUPBOX, 8, 6,
    W - 16, 118, 0);
  DC[IdLogin] := Ctl(DlgWnd, 'STATIC', '', 0, 20, 26, W - 40, 14, IdLogin);
  Lbl(DlgWnd, 'Jeton d''acc'#232's personnel (github.com > Settings > ' +
    'Developer settings) :', 20, 46, W - 40);
  Dummy := DEdit(IdToken, 20, 64, W - 40, GhToken, True);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Se connecter', WS_TABSTOP, 20, 92, 110,
    22, IdSignIn);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Se d'#233'connecter', WS_TABSTOP, 138, 92,
    110, 22, IdSignOut);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Identit'#233' Git (auteur des commits)',
    BS_GROUPBOX, 8, 132, W - 16, 78, 0);
  Lbl(DlgWnd, 'Nom :', 20, 154, 70);
  Dummy := DEdit(IdUName, 100, 150, W - 120, DefName, False);
  Lbl(DlgWnd, 'Courriel :', 20, 180, 70);
  Dummy := DEdit(IdUMail, 100, 176, W - 120, DefEmail, False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Avanc'#233, BS_GROUPBOX, 8, 218, W - 16,
    108, 0);
  Lbl(DlgWnd, 'Proxy HTTP (h'#244'te:port, vide = connexion directe) :', 20,
    238, W - 40);
  Dummy := DEdit(IdProxy, 20, 254, W - 40, ProxyStr, False);
  Lbl(DlgWnd, 'Dossier de clonage par d'#233'faut :', 20, 280, W - 40);
  Dummy := DEdit(IdRoot, 20, 296, W - 128, CloneRoot, False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Parcourir...', WS_TABSTOP, W - 100, 295,
    80, 22, IdBrowse);
  DButtons(W, H, 'Enregistrer');
  OptShowLogin;
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdToken]);
  ModalLoop;
  OptionsDialog := DlgRes = IDOK;
End;

Procedure OptionsCommand(Id, Code : LongInt);
Var S : String;
Begin
  Case Id Of
    IdSignIn :
    Begin
      GhToken := DText(IdToken);
      ProxyStr := DText(IdProxy);
      GhLogin := '';
      If GhToken = '' Then
      Begin
        ErrBox('Entrez votre jeton d''acc'#232's personnel GitHub.');
        Exit;
      End;
      Dummy := SetCursor(LoadCursorA(0, IDC_WAIT));
      If Not GhSignIn Then ErrBox('Connexion '#224' GitHub impossible : ' +
        GitErr)
      Else IniSet('Compte', 'Login', GhLogin);
      Dummy := SetCursor(LoadCursorA(0, IDC_ARROW));
      OptShowLogin;
    End;
    IdSignOut :
    Begin
      GhToken := ''; GhLogin := ''; GhN := 0;
      SetText(DC[IdToken], '');
      IniSet('Compte', 'Jeton', '');
      IniSet('Compte', 'Login', '');
      OptShowLogin;
    End;
    IdBrowse :
    Begin
      S := DText(IdRoot);
      If BrowseFolder('Dossier de clonage par d'#233'faut', S) Then
        SetText(DC[IdRoot], S);
    End;
    IDOK :
    Begin
      If DText(IdToken) <> GhToken Then GhLogin := '';
      GhToken := DText(IdToken);
      DefName := DText(IdUName); DefEmail := DText(IdUMail);
      ProxyStr := DText(IdProxy);
      S := DText(IdRoot);
      If S <> '' Then CloneRoot := S;
      IniSet('Compte', 'Jeton', GhToken);
      IniSet('Compte', 'Login', GhLogin);
      IniSet('Identite', 'Nom', DefName);
      IniSet('Identite', 'Courriel', DefEmail);
      IniSet('Options', 'Proxy', ProxyStr);
      IniSet('Options', 'Dossier', CloneRoot);
      DlgRes := IDOK; DlgDone := True;
    End;
    IDCANCEL :
    Begin
      DlgRes := IDCANCEL; DlgDone := True;
    End;
  End;
End;

{ ---- publier sur GitHub ---- }

Function PublishDialog : Boolean;
Const W = 400; H = 196;
Begin
  PublishDialog := False;
  DlgKind := DgPublish;
  If DlgCreate('Publier le d'#233'p'#244't sur GitHub.com', W, H) = 0 Then
    Exit;
  Lbl(DlgWnd, 'Nom :', 12, 12, 100);
  Dummy := DEdit(IdName, 12, 30, W - 24, RepoTitle(RepoCur), False);
  Lbl(DlgWnd, 'Description :', 12, 60, 200);
  Dummy := DEdit(IdDesc, 12, 78, W - 24, '', False);
  DC[IdPriv] := Ctl(DlgWnd, 'BUTTON', 'Garder ce code priv'#233,
    BS_AUTOCHECKBOX Or WS_TABSTOP, 12, 110, W - 24, 18, IdPriv);
  SetCheck(DC[IdPriv], True);
  Lbl(DlgWnd, 'Compte : ' + GhLogin, 12, 136, W - 24);
  DButtons(W, H, 'Publier le d'#233'p'#244't');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdName]);
  ModalLoop;
  If DlgRes = IDOK Then
  Begin
    OpName := DlgOut[0]; OpDesc := DlgOut[1];
    OpPriv := DlgOut[2] = '1';
    PublishDialog := True;
  End;
End;

{ ---- fusionner ---- }

Function MergeDialog(Var Ref : String) : Boolean;
Const W = 360; H = 300;
Var I : LongInt;
Begin
  MergeDialog := False;
  DlgKind := DgMerge;
  MergeN := 0;
  RefsList(LocRefs, 'refs/heads/');
  For I := 0 To LocRefs.N - 1 Do
    If (LocRefs.Name[I] <> 'refs/heads/' + CurBranch) And (MergeN < 200) Then
    Begin
      MergeRefs[MergeN] := LocRefs.Name[I]; Inc(MergeN);
    End;
  RefsList(LocRefs, 'refs/remotes/');
  For I := 0 To LocRefs.N - 1 Do
    If (Copy(LocRefs.Name[I], Length(LocRefs.Name[I]) - 4, 5) <> '/HEAD')
       And (MergeN < 200) Then
    Begin
      MergeRefs[MergeN] := LocRefs.Name[I]; Inc(MergeN);
    End;
  If MergeN = 0 Then
  Begin
    ErrBox('Il n''y a aucune autre branche '#224' fusionner.');
    Exit;
  End;
  If DlgCreate('Fusionner dans ' + CurBranch, W, H) = 0 Then Exit;
  Lbl(DlgWnd, 'Choisissez la branche '#224' fusionner dans ' + CurBranch +
    ' :', 12, 10, W - 24);
  DC[IdList] := Ctl(DlgWnd, 'LISTBOX', '', WS_BORDER Or WS_VSCROLL Or
    LBS_NOTIFY Or WS_TABSTOP, 12, 30, W - 24, H - 76, IdList);
  For I := 0 To MergeN - 1 Do
    If Copy(MergeRefs[I], 1, 11) = 'refs/heads/' Then
      Dummy := SendMessageA(DC[IdList], LB_ADDSTRING, 0,
        Z(Disp(Utf8ToAnsi(Copy(MergeRefs[I], 12, 120)))))
    Else Dummy := SendMessageA(DC[IdList], LB_ADDSTRING, 0,
        Z(Disp(Utf8ToAnsi(Copy(MergeRefs[I], 14, 120)))));
  Dummy := SendMessageA(DC[IdList], LB_SETCURSEL, 0, 0);
  DButtons(W, H, 'Fusionner');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdList]);
  ModalLoop;
  If DlgRes = IDOK Then
  Begin
    Ref := DlgOut[0];
    MergeDialog := True;
  End;
End;

{ ---- identifiants HTTP ---- }

Function CredDialog(Const Host : String) : Boolean;
Const W = 360; H = 170;
Begin
  CredDialog := False;
  DlgKind := DgCred;
  If DlgCreate('Authentification', W, H) = 0 Then Exit;
  Lbl(DlgWnd, 'Le serveur ' + Host + ' demande une identification.', 12,
    10, W - 24);
  Lbl(DlgWnd, 'Utilisateur :', 12, 40, 100);
  Dummy := DEdit(IdUser, 120, 36, W - 132, CredUser, False);
  Lbl(DlgWnd, 'Mot de passe :', 12, 70, 100);
  Dummy := DEdit(IdPass, 120, 66, W - 132, '', True);
  Lbl(DlgWnd, '(pour GitHub : jeton d''acc'#232's personnel)', 120, 92,
    W - 132);
  DButtons(W, H, 'OK');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdUser]);
  ModalLoop;
  If DlgRes = IDOK Then
  Begin
    CredHost := LowStr(Host);
    CredUser := DlgOut[0]; CredPass := DlgOut[1];
    CredDialog := True;
  End;
End;

{ ---- parametres du depot ---- }

Function RepoSetDialog : Boolean;
Const W = 460; H = 210;
Begin
  RepoSetDialog := False;
  DlgKind := DgRepoSet;
  If DlgCreate('Param'#232'tres du d'#233'p'#244't', W, H) = 0 Then Exit;
  Lbl(DlgWnd, 'D'#233'p'#244't distant principal (origin) :', 12, 12, W - 24);
  Dummy := DEdit(IdUrl, 12, 30, W - 24, CfgGet('remote', 'origin', 'url'),
    False);
  Dummy := Ctl(DlgWnd, 'BUTTON', 'Identit'#233' pour ce d'#233'p'#244't ' +
    '(vide : identit'#233' des Options)', BS_GROUPBOX, 8, 62, W - 16, 86, 0);
  Lbl(DlgWnd, 'Nom :', 20, 86, 70);
  Dummy := DEdit(IdUName, 100, 82, W - 120,
    Utf8ToAnsi(CfgGet('user', '', 'name')), False);
  Lbl(DlgWnd, 'Courriel :', 20, 114, 70);
  Dummy := DEdit(IdUMail, 100, 110, W - 120, CfgGet('user', '', 'email'),
    False);
  DButtons(W, H, 'Enregistrer');
  Dummy := ShowWindow(DlgWnd, 1);
  Dummy := SetFocus(DC[IdUrl]);
  ModalLoop;
  RepoSetDialog := DlgRes = IDOK;
End;

Procedure DlgCommand(Id, Code : LongInt);
Var S : String; I : LongInt;
Begin
  If DlgKind = DgClone Then
  Begin
    CloneCommand(Id, Code); Exit;
  End;
  If DlgKind = DgOptions Then
  Begin
    OptionsCommand(Id, Code); Exit;
  End;
  Case Id Of
    IdBrowse :
    Begin
      S := DText(IdPath);
      If BrowseFolder('Choisissez un dossier', S) Then SetText(DC[IdPath], S);
    End;
    IdList :
      If (Code = LBN_DBLCLK) And (DlgKind = DgMerge) Then
        DlgCommand(IDOK, 0);
    IDOK :
    Begin
      Case DlgKind Of
        DgInput : DlgText := CtlText(InpEdit);
        DgNew :
        Begin
          If (DText(IdName) = '') Or (Pos('\', DText(IdName)) > 0) Or
             (Pos(':', DText(IdName)) > 0) Then
          Begin
            ErrBox('Entrez un nom de d'#233'p'#244't valable (sans \ ni :).');
            Exit;
          End;
          DlgOut[0] := DText(IdName); DlgOut[1] := DText(IdDesc);
          DlgOut[2] := DText(IdPath);
          DlgOut[3] := '0'; DlgOut[4] := '0';
          If Checked(DC[IdReadme]) Then DlgOut[3] := '1';
          If Checked(DC[IdPriv]) Then DlgOut[4] := '1';
        End;
        DgAdd : DlgOut[0] := DText(IdPath);
        DgPublish :
        Begin
          If DText(IdName) = '' Then
          Begin
            ErrBox('Entrez le nom du d'#233'p'#244't GitHub.'); Exit;
          End;
          DlgOut[0] := DText(IdName); DlgOut[1] := DText(IdDesc);
          If Checked(DC[IdPriv]) Then DlgOut[2] := '1' Else DlgOut[2] := '0';
        End;
        DgMerge :
        Begin
          I := SendMessageA(DC[IdList], LB_GETCURSEL, 0, 0);
          If (I < 0) Or (I >= MergeN) Then Exit;
          DlgOut[0] := MergeRefs[I];
        End;
        DgCred :
        Begin
          DlgOut[0] := DText(IdUser); DlgOut[1] := CtlText(DC[IdPass]);
        End;
        DgRepoSet :
        Begin
          S := NormUrl(DText(IdUrl));
          If S <> '' Then SetRemote('origin', S)
          Else If CfgGet('remote', 'origin', 'url') <> '' Then
            CfgSet('remote', 'origin', 'url', '');
          If (DText(IdUName) <> '') Or (CfgGet('user', '', 'name') <> '') Then
            CfgSet('user', '', 'name', AnsiToUtf8(DText(IdUName)));
          If (DText(IdUMail) <> '') Or (CfgGet('user', '', 'email') <> '')
          Then CfgSet('user', '', 'email', DText(IdUMail));
        End;
      End;
      DlgRes := IDOK; DlgDone := True;
    End;
    IDCANCEL :
    Begin
      DlgRes := IDCANCEL; DlgDone := True;
    End;
  End;
End;

Function DlgProc0(H, Msg, WP, LP : LongInt) : LongInt;
Begin
  DlgProc0 := 0;
  Case Msg Of
    WM_ERASEBKGND :
    Begin
      Bar(WP, 0, 0, 2000, 2000, ClrFace);
      DlgProc0 := 1;
    End;
    WM_COMMAND : DlgCommand(WP And $FFFF, (WP Shr 16) And $FFFF);
    WM_CLOSE :
    Begin
      DlgRes := IDCANCEL; DlgDone := True;
    End;
  Else
    DlgProc0 := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function DlgProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  BigLock;
  DlgProc := DlgProc0(H, Msg, WP, LP);
  BigUnlock;
End;
{ ==================================================================== }
{ Fenetre principale                                                    }
{ ==================================================================== }

Const
  TbH = 50; StH = 20; TabH = 26; ChkH = 24; ComH = 160; HdrH = 72;
  FilesH = 126;
  IdSum = 20; IdDescE = 21; IdCommit = 22;
  IdWClone = 23; IdWNew = 24; IdWAdd = 25;
  CmNewRepo = 101; CmAddRepo = 102; CmClone = 103; CmOptions = 104;
  CmExit = 105;
  CmCheckAll = 111; CmUncheckAll = 112; CmDiscardAll = 113;
  CmCopyPath = 114; CmIgnore = 115; CmDiscardOne = 116; CmOpenFile = 117;
  CmViewChg = 121; CmViewHist = 122; CmRepoList = 123; CmBranchList = 124;
  CmRefresh = 125;
  CmPush = 131; CmPull = 132; CmFetch = 133; CmExplorer = 134;
  CmDos = 135; CmRepoSet = 136; CmRemoveRepo = 137; CmPublish = 138;
  CmViewGh = 139;
  CmNewBranch = 141; CmRenBranch = 142; CmDelBranch = 143; CmMerge = 144;
  CmAbout = 151; CmGhHelp = 152;
  CmBrLocal = 1000; CmBrRemote = 1400; CmRepo = 2000;

Var
  MainMenu, MFile, MEdit, MView, MRepo, MBranch, MHelp : LongInt;
  ESum, EDesc, BCommit, BWClone, BWNew, BWAdd : LongInt;
  CW0, CH0, LX, CY0, CY1 : LongInt;
  TbDown : LongInt;
  Unchk : Array[0..199] Of String[120];
  UnchkN : LongInt;
  BrList : Array[0..299] Of String[120];
  BrN, BrRemN : LongInt;
  Refreshing : Boolean;
  LastRefresh : LongInt;
  WaitCur, ArrowCur : LongInt;

Procedure Layout; Forward;

Var
  FrN : LongInt;
  Fr : Array[0..3, 0..3] Of LongInt;   { cadres creux des vues }

{ place une vue dans un cadre creux de Windows 95 (2 points) }
Procedure PlaceF(H, X, Y, W, Hh : LongInt);
Begin
  Place(H, X + 2, Y + 2, W - 4, Hh - 4);
  If FrN < 4 Then
  Begin
    Fr[FrN, 0] := X; Fr[FrN, 1] := Y; Fr[FrN, 2] := X + W;
    Fr[FrN, 3] := Y + Hh;
    Inc(FrN);
  End;
End;

Procedure InvalidateStatus;
Var Rc : Array[0..3] Of LongInt;
Begin
  Rc[0] := 0; Rc[1] := CH0 - StH; Rc[2] := CW0; Rc[3] := CH0;
  Dummy := InvalidateRect(MainWnd, LongInt(@Rc), 0);
  Rc[0] := 0; Rc[1] := 0; Rc[2] := CW0; Rc[3] := TbH;
  Dummy := InvalidateRect(MainWnd, LongInt(@Rc), 0);
End;

Procedure PaintNow;
Begin
  InvalidateStatus;
  Dummy := UpdateWindow(MainWnd);
End;

Procedure SetStatus(Const S : String);
Begin
  StatusTxt := S;
  InvalidateStatus;
End;

Procedure Redraw;
Begin
  Dummy := InvalidateRect(MainWnd, 0, 0);
  LvRepaint(LvChg); LvRepaint(LvHist); LvRepaint(LvFiles);
  DiffRepaint;
End;

Function CheckedCount : LongInt;
Var I, N : LongInt;
Begin
  N := 0;
  For I := 0 To Chg.N - 1 Do
    If (Chg.E^[I].Flag And FlSel) <> 0 Then Inc(N);
  CheckedCount := N;
End;

Procedure UpdateCommitBtn;
Var S : String;
Begin
  If CurBranch <> '' Then S := 'Valider dans ' + CurBranch
  Else S := 'Valider';
  If InMerge Then S := 'Valider la fusion';
  SetText(BCommit, Fit(S, LX - 30));
  Dummy := EnableWindow(BCommit, Ord(((CheckedCount > 0) Or InMerge) And
    (CtlText(ESum) <> '') And Not Busy));
End;

Procedure CheckedChanged;
Var Rc : Array[0..3] Of LongInt;
Begin
  Rc[0] := 0; Rc[1] := CY0 + TabH; Rc[2] := LX; Rc[3] := CY0 + TabH + ChkH;
  Dummy := InvalidateRect(MainWnd, LongInt(@Rc), 0);
  UpdateCommitBtn;
End;

Procedure UpdateTitle;
Begin
  If RepoCur >= 0 Then
    Dummy := SetWindowTextA(MainWnd, Z(Disp('Client GitHub - ' +
      RepoTitle(RepoCur))))
  Else Dummy := SetWindowTextA(MainWnd, Z('Client GitHub'));
End;

{ ---- selection ---- }

Procedure SelectChange(I : LongInt);
Begin
  ChgSel := I;
  If (I < 0) Or (I >= Chg.N) Then
  Begin
    DiffClear; Exit;
  End;
  DiffLoad(Chg.E^[I].Old, ShaZero, True, Chg.E^[I].Path,
    Chg.E^[I].Flag And $FF);
End;

Procedure SelectFile(I : LongInt);
Begin
  FileSel := I;
  If (I < 0) Or (I >= HFiles.N) Then
  Begin
    DiffClear; Exit;
  End;
  DiffLoad(HFiles.E^[I].Old, HFiles.E^[I].Sha, False, HFiles.E^[I].Path,
    HFiles.E^[I].Flag And $FF);
End;

Procedure SelectCommit(I : LongInt);
Var Rc : Array[0..3] Of LongInt;
Begin
  HistSel := I;
  HFiles.N := 0; FileSel := -1;
  If (I >= 0) And (I < HistN) Then
  Begin
    If Not CommitRead(Hist^[I].Sha, HCommit, @HMsg) Then HMsg.N := 0;
    If CommitChanges(Hist^[I].Sha, HFiles) Then ;
  End;
  Lv[LvFiles].Top := 0;
  LvSync(LvFiles);
  LvRepaint(LvFiles);
  If HFiles.N > 0 Then SelectFile(0) Else DiffClear;
  Rc[0] := LX; Rc[1] := CY0; Rc[2] := CW0; Rc[3] := CY0 + HdrH;
  Dummy := InvalidateRect(MainWnd, LongInt(@Rc), 0);
End;

{ ---- actualisation du depot ---- }

Procedure RefreshRepo(Keep : Boolean);
Var I, K : LongInt; OldPath : String;
Begin
  If Refreshing Or Busy Then Exit;
  Refreshing := True;
  LastRefresh := GetTickCount;
  OldPath := '';
  If Keep And (ChgSel >= 0) And (ChgSel < Chg.N) Then
    OldPath := Chg.E^[ChgSel].Path;
  UnchkN := 0;
  If Keep Then
    For I := 0 To Chg.N - 1 Do
      If ((Chg.E^[I].Flag And FlSel) = 0) And (UnchkN < 200) Then
      Begin
        Unchk[UnchkN] := Chg.E^[I].Path; Inc(UnchkN);
      End;
  Chg.N := 0; HistN := 0; HFiles.N := 0;
  CurBranch := ''; Ahead := 0; Behind := 0;
  HasRemote := False; HasUpstream := False; InMerge := False;
  ChgSel := -1; HistSel := -1; FileSel := -1;
  If RepoCur >= 0 Then
  Begin
    If Not SetRepo(RepoPath[RepoCur]) Then
    Begin
      ErrBox('Le d'#233'p'#244't ' + RepoPath[RepoCur] + ' est introuvable ' +
        '(dossier .git absent). Il est retir'#233' de la liste.');
      RepoRemove(RepoCur);
      ReposSave;
    End
    Else
    Begin
      Dummy := SetCursor(WaitCur);
      LoadIdentity;
      SetStatus('Analyse du d'#233'p'#244't...');
      If Not RepoStatus Then ErrBox('Lecture du d'#233'p'#244't : ' + GitErr);
      CurBranch := HeadBranch;
      CountAB;
      HistLoad(HeadSha, 400);
      For I := 0 To Chg.N - 1 Do
        For K := 0 To UnchkN - 1 Do
          If Chg.E^[I].Path = Unchk[K] Then
            Chg.E^[I].Flag := Chg.E^[I].Flag And Not FlSel;
      If Chg.N > 0 Then
      Begin
        ChgSel := 0;
        If OldPath <> '' Then
        Begin
          K := FlatFind(Chg, OldPath);
          If K >= 0 Then ChgSel := K;
        End;
      End;
      Dummy := SetCursor(ArrowCur);
      If InMerge Then SetStatus('Fusion en cours : r'#233'solvez les ' +
        'conflits puis validez.')
      Else SetStatus(IStr(Chg.N) + ' fichier(s) modifi'#233'(s), ' +
        IStr(HistN) + ' commit(s) affich'#233'(s)');
    End;
  End
  Else SetStatus('Aucun d'#233'p'#244't ouvert');
  If View = VwChanges Then SelectChange(ChgSel)
  Else If HistN > 0 Then SelectCommit(0)
  Else DiffClear;
  For I := 0 To 2 Do LvSync(I);
  If ChgSel >= 0 Then LvVisible(LvChg);
  Layout;
  UpdateTitle;
  UpdateCommitBtn;
  Redraw;
  Refreshing := False;
End;

Procedure OpenRepo(K : LongInt);
Begin
  RepoCur := K;
  ReposSave;
  View := VwChanges;
  RefreshRepo(False);
End;

Procedure SetView(V : LongInt);
Begin
  If RepoCur < 0 Then Exit;
  View := V;
  If V = VwChanges Then SelectChange(ChgSel)
  Else If (HistSel < 0) And (HistN > 0) Then SelectCommit(0)
  Else SelectCommit(HistSel);
  Layout;
  Redraw;
End;

{ ---- disposition ---- }

Procedure Layout;
Var Has, Chgv : Boolean; Y, Ri, Rw : LongInt;
Begin
  If ESum = 0 Then Exit;
  Has := RepoCur >= 0;
  Chgv := Has And (View = VwChanges);
  LX := MinL(320, MaxL(220, CW0 Div 3));
  CY0 := TbH; CY1 := CH0 - StH;
  Ri := LX + 3; Rw := CW0 - Ri;
  FrN := 0;
  Show(Lv[LvChg].H, Chgv);
  Show(ESum, Chgv); Show(EDesc, Chgv); Show(BCommit, Chgv);
  Show(Lv[LvHist].H, Has And Not Chgv);
  Show(Lv[LvFiles].H, Has And Not Chgv);
  Show(DiffWnd, Has);
  Show(BWClone, Not Has); Show(BWNew, Not Has); Show(BWAdd, Not Has);
  If Chgv Then
  Begin
    Y := CY1 - ComH;
    PlaceF(Lv[LvChg].H, 0, CY0 + TabH + ChkH, LX, Y - CY0 - TabH - ChkH);
    Place(ESum, 8, Y + 10, LX - 16, 22);
    Place(EDesc, 8, Y + 38, LX - 16, 78);
    Place(BCommit, 8, Y + 124, LX - 16, 28);
    PlaceF(DiffWnd, Ri, CY0, Rw, CY1 - CY0);
  End
  Else If Has Then
  Begin
    PlaceF(Lv[LvHist].H, 0, CY0 + TabH, LX, CY1 - CY0 - TabH);
    PlaceF(Lv[LvFiles].H, Ri, CY0 + HdrH, Rw, FilesH);
    PlaceF(DiffWnd, Ri, CY0 + HdrH + FilesH + 3, Rw,
      CY1 - CY0 - HdrH - FilesH - 3);
  End
  Else
  Begin
    Y := CY0 + 150;
    Place(BWClone, CW0 Div 2 - 150, Y, 300, 30);
    Place(BWNew, CW0 Div 2 - 150, Y + 40, 300, 30);
    Place(BWAdd, CW0 Div 2 - 150, Y + 80, 300, 30);
  End;
End;

{ ---- dessin ---- }

Function TbX(I : LongInt) : LongInt;
Begin
  Case I Of
    0 : TbX := 0;
    1 : TbX := 230;
    2 : TbX := 460;
    Else TbX := MaxL(700, CW0);
  End;
End;

Procedure IconRepo(Dc, X, Y : LongInt);
Begin
  Bar(Dc, X, Y, X + 14, Y + 18, ClrBlack);
  Bar(Dc, X + 1, Y + 1, X + 13, Y + 15, ClrWin);
  Bar(Dc, X + 3, Y + 1, X + 4, Y + 15, ClrBlack);
  Bar(Dc, X + 6, Y + 4, X + 11, Y + 5, ClrGray);
  Bar(Dc, X + 6, Y + 7, X + 11, Y + 8, ClrGray);
  Bar(Dc, X + 3, Y + 15, X + 7, Y + 20, ClrRed);
End;

Procedure IconBranch(Dc, X, Y : LongInt);
Begin
  Bar(Dc, X + 2, Y, X + 4, Y + 20, ClrBlack);
  Bar(Dc, X, Y, X + 6, Y + 4, ClrNavy);
  Bar(Dc, X, Y + 16, X + 6, Y + 20, ClrNavy);
  Bar(Dc, X + 10, Y + 2, X + 12, Y + 9, ClrBlack);
  Bar(Dc, X + 8, Y, X + 14, Y + 4, ClrNavy);
  Bar(Dc, X + 4, Y + 9, X + 12, Y + 11, ClrBlack);
End;

Procedure IconSync(Dc, X, Y, Kind : LongInt);
Var I : LongInt;
Begin
  { fleche vers le haut (pousser), le bas (tirer) ou les deux }
  If Kind <> 2 Then
  Begin
    Bar(Dc, X + 3, Y + 4, X + 5, Y + 18, ClrBlack);
    For I := 0 To 3 Do Bar(Dc, X + 3 - I, Y + 4 + I, X + 5 + I, Y + 5 + I,
      ClrBlack);
  End;
  If Kind <> 1 Then
  Begin
    Bar(Dc, X + 11, Y + 2, X + 13, Y + 16, ClrBlack);
    For I := 0 To 3 Do Bar(Dc, X + 11 - I, Y + 16 - I, X + 13 + I,
      Y + 17 - I, ClrBlack);
  End;
End;

Function AgoTxt(T : LongInt) : String;
Var M : LongInt;
Begin
  If T = 0 Then
  Begin
    AgoTxt := 'jamais'; Exit;
  End;
  M := (GetTickCount - T) Div 60000;
  If M < 1 Then AgoTxt := 'il y a moins d''une minute'
  Else If M < 60 Then AgoTxt := 'il y a ' + IStr(M) + ' min'
  Else AgoTxt := 'il y a ' + IStr(M Div 60) + ' h';
End;

{ libelles du troisieme bouton : action de synchronisation }
Function SyncKind : LongInt;
Begin
  If Not HasRemote Then SyncKind := 1
  Else If Not HasUpstream Then SyncKind := 2
  Else If Behind > 0 Then SyncKind := 3
  Else If Ahead > 0 Then SyncKind := 4
  Else SyncKind := 5;
End;

Procedure PaintTb(Dc : LongInt);
Var I, X, X2, K : LongInt; A, B : String;
Begin
  Bar(Dc, 0, 0, CW0, TbH - 2, ClrFace);
  Bar(Dc, 0, TbH - 2, CW0, TbH - 1, ClrShadow);
  Bar(Dc, 0, TbH - 1, CW0, TbH, ClrHi);
  For I := 0 To 2 Do
  Begin
    If (I = 2) And (RepoCur < 0) Then Break;
    X := TbX(I); X2 := TbX(I + 1) - 2;
    If I = 2 Then X2 := MinL(CW0 - 4, X + 260);
    If TbDown = I Then Bevel(Dc, X + 2, 3, X2, TbH - 5, False)
    Else Thin(Dc, X + 2, 3, X2, TbH - 5, True);
    Case I Of
      0 :
      Begin
        IconRepo(Dc, X + 12, 12);
        A := 'D'#233'p'#244't actuel';
        If RepoCur >= 0 Then B := RepoTitle(RepoCur) Else B := 'Aucun d'#233
          + 'p'#244't';
      End;
      1 :
      Begin
        IconBranch(Dc, X + 12, 12);
        A := 'Branche actuelle';
        If RepoCur < 0 Then B := '-'
        Else If CurBranch = '' Then B := '(HEAD d'#233'tach'#233'e)'
        Else B := Utf8ToAnsi(CurBranch);
      End;
      Else
      Begin
        K := SyncKind;
        If Busy Then
        Begin
          IconSync(Dc, X + 12, 13, 0);
          Case Op Of
            OpPush : A := 'Envoi vers origin';
            OpPull : A := 'Tirage depuis origin';
            OpPublish : A := 'Publication';
            OpClone : A := 'Clonage';
            Else A := 'R'#233'cup'#233'ration depuis origin';
          End;
          B := Copy(ProgTxt, 1, 34);
        End
        Else
          Case K Of
            1 :
            Begin
              IconSync(Dc, X + 12, 13, 1);
              A := 'Publier le d'#233'p'#244't';
              B := 'Le publier sur GitHub.com';
            End;
            2 :
            Begin
              IconSync(Dc, X + 12, 13, 1);
              A := 'Publier la branche';
              B := 'Cr'#233'er la branche sur origin';
            End;
            3 :
            Begin
              IconSync(Dc, X + 12, 13, 2);
              A := 'Tirer origin  ' + #25 + IStr(Behind);
              If Ahead > 0 Then A := A + ' ' + #24 + IStr(Ahead);
              B := 'R'#233'cup'#233'r'#233' ' + AgoTxt(LastFetch);
            End;
            4 :
            Begin
              IconSync(Dc, X + 12, 13, 1);
              A := 'Pousser origin  ' + #24 + IStr(Ahead);
              B := 'R'#233'cup'#233'r'#233' ' + AgoTxt(LastFetch);
            End;
            Else
            Begin
              IconSync(Dc, X + 12, 13, 0);
              A := 'R'#233'cup'#233'rer origin';
              B := 'Derni'#232're r'#233'cup'#233'ration : ' + AgoTxt(LastFetch);
            End;
          End;
      End;
    End;
    Txt(Dc, X + 36, 9, Fit(A, X2 - X - 56), ClrGray);
    Txt(Dc, X + 36, 25, Fit(B, X2 - X - 56), ClrBlack);
    If I < 2 Then Txt(Dc, X2 - 16, 17, #31, ClrBlack);
  End;
End;

Procedure PaintTabs(Dc : LongInt);
Var I, X, W, Y : LongInt; S : String;
Begin
  Bar(Dc, 0, CY0, LX, CY0 + TabH, ClrFace);
  W := (LX - 8) Div 2;
  For I := 0 To 1 Do
  Begin
    X := 4 + I * W;
    If I = 0 Then S := 'Modifications (' + IStr(Chg.N) + ')'
    Else S := 'Historique';
    If I = View Then Y := CY0 + 3 Else Y := CY0 + 6;
    Bar(Dc, X, Y, X + W - 1, Y + 1, ClrHi);
    Bar(Dc, X, Y, X + 1, CY0 + TabH, ClrHi);
    Bar(Dc, X + W - 2, Y + 1, X + W - 1, CY0 + TabH, ClrShadow);
    Bar(Dc, X + W - 1, Y + 2, X + W, CY0 + TabH, ClrDark);
    Txt(Dc, X + (W - Length(S) * CW) Div 2, Y + 5, S, ClrBlack);
  End;
  Bar(Dc, 0, CY0 + TabH - 1, LX, CY0 + TabH, ClrHi);
  X := 4 + View * W;
  Bar(Dc, X + 1, CY0 + TabH - 1, X + W - 2, CY0 + TabH, ClrFace);
End;

Procedure PaintCommitHdr(Dc : LongInt);
Var S : String; I : LongInt;
Begin
  Bar(Dc, LX + 3, CY0, CW0, CY0 + HdrH, ClrFace);
  If (HistSel < 0) Or (HistSel >= HistN) Then Exit;
  Txt(Dc, LX + 12, CY0 + 8, Fit(Utf8ToAnsi(HCommit.Summary), CW0 - LX - 24),
    ClrBlack);
  { nom de l'auteur (sans le courriel, comme GitHub Desktop) }
  S := Utf8ToAnsi(HCommit.Author);
  I := Pos(' <', S);
  If I > 0 Then S := Copy(S, 1, I - 1);
  Txt(Dc, LX + 12, CY0 + 28, Fit(S + '   ' + UnixToStr(HCommit.ATime) +
    ' UTC', CW0 - LX - 24), ClrNavy);
  S := 'Commit ' + Copy(ShaHex(Hist^[HistSel].Sha), 1, 10);
  If HCommit.PN > 1 Then S := S + '   (fusion de ' + IStr(HCommit.PN) +
    ' parents)';
  S := S + '   ' + IStr(HFiles.N) + ' fichier(s) modifi'#233'(s)';
  Txt(Dc, LX + 12, CY0 + 48, Fit(S, CW0 - LX - 24), ClrGray);
End;

Procedure PaintWelcome(Dc : LongInt);
Var Y : LongInt;
Begin
  Bar(Dc, 0, CY0, CW0, CY1, ClrFace);
  Y := CY0 + 40;
  IconRepo(Dc, CW0 Div 2 - 7, Y);
  Txt(Dc, MaxL(4, CW0 Div 2 - 13 * CW Div 2), Y + 34, 'Bienvenue !',
    ClrBlack);
  Txt(Dc, MaxL(4, CW0 Div 2 - 64 * CW Div 2), Y + 62, 'Clonez un d'#233'p'#244
    + 't de GitHub.com, cr'#233'ez-en un nouveau ou ajoutez-en un', ClrGray);
  Txt(Dc, MaxL(4, CW0 Div 2 - 36 * CW Div 2), Y + 78, 'qui existe d'#233'j'#224
    + ' sur votre ordinateur.', ClrGray);
End;

Procedure MainPaint(H : LongInt);
Var Dc, N, Y, I : LongInt; S : String;
Begin
  Dc := BeginPaint(H, LongInt(@PaintS));
  Dummy := SelectObject(Dc, Fnt);
  { cadres creux des vues (leur interieur est dessine par les vues : sous
    Pasdows, le parent ne decoupe pas ses enfants) }
  If RepoCur >= 0 Then
    For I := 0 To FrN - 1 Do
      Bevel(Dc, Fr[I, 0], Fr[I, 1], Fr[I, 2], Fr[I, 3], False);
  PaintTb(Dc);
  If RepoCur < 0 Then PaintWelcome(Dc)
  Else
  Begin
    PaintTabs(Dc);
    Bar(Dc, LX, CY0, LX + 3, CY1, ClrFace);
    If View = VwChanges Then
    Begin
      Y := CY0 + TabH;
      Bar(Dc, 0, Y, LX, Y + ChkH, ClrFace);
      N := CheckedCount;
      CheckBox(Dc, 5, Y + 5, N > 0, (N > 0) And (N < Chg.N));
      S := IStr(Chg.N) + ' fichier(s) modifi'#233'(s)';
      If (N <> Chg.N) Then S := S + ', ' + IStr(N) + ' coch'#233'(s)';
      Txt(Dc, 24, Y + 5, Fit(S, LX - 30), ClrBlack);
      Bar(Dc, 0, CY1 - ComH, LX, CY1, ClrFace);
      Bar(Dc, 0, CY1 - ComH, LX, CY1 - ComH + 1, ClrShadow);
    End
    Else
    Begin
      PaintCommitHdr(Dc);
      Bar(Dc, LX + 3, CY0 + HdrH + FilesH, CW0, CY0 + HdrH + FilesH + 3,
        ClrFace);
    End;
  End;
  { barre d'etat }
  Bar(Dc, 0, CH0 - StH, CW0, CH0, ClrFace);
  Thin(Dc, 2, CH0 - StH + 2, CW0 - 2, CH0 - 1, False);
  If Busy Then S := ProgLine Else S := StatusTxt;
  Txt(Dc, 6, CH0 - StH + 4, Fit(S, CW0 - 12), ClrBlack);
  Dummy := EndPaint(H, LongInt(@PaintS));
End;

{ ---- menus ---- }

Procedure BuildMenus;
Begin
  MainMenu := CreateMenu;
  MFile := CreatePopupMenu;
  MItem(MFile, CmNewRepo, '~Nouveau d'#233'p'#244't...'#9'Ctrl+N');
  MItem(MFile, CmAddRepo, '~Ajouter un d'#233'p'#244't local...'#9'Ctrl+O');
  MItem(MFile, CmClone, '~Cloner un d'#233'p'#244't...'#9'Ctrl+Maj+O');
  MItem(MFile, 0, '');
  MItem(MFile, CmOptions, '~Options...'#9'Ctrl+,');
  MItem(MFile, 0, '');
  MItem(MFile, CmExit, '~Quitter'#9'Alt+F4');
  MSub(MainMenu, MFile, '~Fichier');
  MEdit := CreatePopupMenu;
  MItem(MEdit, CmCheckAll, '~Cocher tous les fichiers'#9'Ctrl+A');
  MItem(MEdit, CmUncheckAll, '~D'#233'cocher tous les fichiers');
  MItem(MEdit, 0, '');
  MItem(MEdit, CmCopyPath, 'Copier le ~chemin du fichier');
  MItem(MEdit, CmOpenFile, '~Ouvrir le fichier');
  MItem(MEdit, CmIgnore, 'Ajouter le fichier '#224' .~gitignore');
  MItem(MEdit, 0, '');
  MItem(MEdit, CmDiscardOne, '~Annuler les modifications du fichier...');
  MItem(MEdit, CmDiscardAll, 'Annuler ~toutes les modifications...'#9 +
    'Ctrl+Maj+Suppr');
  MSub(MainMenu, MEdit, '~Edition');
  MView := CreatePopupMenu;
  MItem(MView, CmViewChg, '~Modifications'#9'Ctrl+1');
  MItem(MView, CmViewHist, '~Historique'#9'Ctrl+2');
  MItem(MView, 0, '');
  MItem(MView, CmRepoList, 'Liste des ~d'#233'p'#244'ts'#9'Ctrl+T');
  MItem(MView, CmBranchList, 'Liste des ~branches'#9'Ctrl+B');
  MItem(MView, 0, '');
  MItem(MView, CmRefresh, '~Actualiser'#9'F5');
  MSub(MainMenu, MView, '~Affichage');
  MRepo := CreatePopupMenu;
  MItem(MRepo, CmPush, '~Pousser'#9'Ctrl+P');
  MItem(MRepo, CmPull, '~Tirer'#9'Ctrl+Maj+P');
  MItem(MRepo, CmFetch, '~R'#233'cup'#233'rer'#9'Ctrl+Maj+T');
  MItem(MRepo, CmPublish, 'P~ublier sur GitHub.com...');
  MItem(MRepo, 0, '');
  MItem(MRepo, CmViewGh, '~Voir sur GitHub'#9'Ctrl+Maj+G');
  MItem(MRepo, CmExplorer, 'Ouvrir dans l''~Explorateur'#9'Ctrl+Maj+F');
  MItem(MRepo, CmDos, 'Ouvrir dans l''~invite MS-DOS');
  MItem(MRepo, 0, '');
  MItem(MRepo, CmRepoSet, 'P~aram'#232'tres du d'#233'p'#244't...');
  MItem(MRepo, CmRemoveRepo, 'Retirer de la ~liste');
  MSub(MainMenu, MRepo, '~D'#233'p'#244't');
  MBranch := CreatePopupMenu;
  MItem(MBranch, CmNewBranch, '~Nouvelle branche...'#9'Ctrl+Maj+N');
  MItem(MBranch, CmRenBranch, '~Renommer...');
  MItem(MBranch, CmDelBranch, '~Supprimer...');
  MItem(MBranch, 0, '');
  MItem(MBranch, CmMerge, '~Fusionner dans la branche actuelle...'#9 +
    'Ctrl+Maj+M');
  MSub(MainMenu, MBranch, '~Branche');
  MHelp := CreatePopupMenu;
  MItem(MHelp, CmGhHelp, '~Raccourcis clavier');
  MItem(MHelp, 0, '');
  MItem(MHelp, CmAbout, '~A propos du Client GitHub...');
  MSub(MainMenu, MHelp, '~Aide');
  Dummy := SetMenu(MainWnd, MainMenu);
End;

Procedure MenuState;
Var Has, Free : Boolean; I : LongInt;
Begin
  Has := RepoCur >= 0;
  Free := Not Busy;
  For I := CmCheckAll To CmOpenFile Do MEnable(MEdit, I, Has And Free);
  MEnable(MView, CmViewChg, Has); MEnable(MView, CmViewHist, Has);
  MEnable(MView, CmBranchList, Has And Free);
  For I := CmPush To CmViewGh Do MEnable(MRepo, I, Has And Free);
  For I := CmNewBranch To CmMerge Do MEnable(MBranch, I, Has And Free);
  MEnable(MFile, CmNewRepo, Free); MEnable(MFile, CmAddRepo, Free);
  MEnable(MFile, CmClone, Free);
End;

{ ---- commandes ---- }

Function ValidBranch(Const S : String) : Boolean;
Var I : LongInt;
Begin
  ValidBranch := False;
  If (S = '') Or (S[1] = '-') Or (S[1] = '/') Or (S[Length(S)] = '/') Or
     (Pos('..', S) > 0) Or (S = 'HEAD') Or
     (LowStr(Copy(S, Length(S) - 4, 5)) = '.lock') Then Exit;
  For I := 1 To Length(S) Do
    If (S[I] <= ' ') Or (S[I] In ['~', '^', ':', '?', '*', '[', '\']) Then
      Exit;
  ValidBranch := True;
End;

Function Clean : Boolean;
Var I : LongInt;
Begin
  Clean := True;
  For I := 0 To Chg.N - 1 Do
    If (Chg.E^[I].Flag And $FF) <> StNew Then Clean := False;
End;

Procedure DoCommitCmd;
Var M : TBuf; S, D : String; H : TSha; I, N : LongInt;
    Big : Array[0..4095] Of Byte;
Begin
  If Busy Or (RepoCur < 0) Then Exit;
  S := TrimS(CtlText(ESum));
  If S = '' Then
  Begin
    ErrBox('Entrez un r'#233'sum'#233' pour ce commit.'); Exit;
  End;
  If (CheckedCount = 0) And Not InMerge Then
  Begin
    ErrBox('Cochez au moins un fichier '#224' valider.'); Exit;
  End;
  BufInit(M);
  BufStr(M, AnsiToUtf8(S));
  N := GetWindowTextA(EDesc, LongInt(@Big), 4000);
  If N > 0 Then
  Begin
    BufStr(M, #10#10);
    D := '';
    For I := 0 To N - 1 Do
      If Big[I] <> 13 Then
      Begin
        D := D + Chr(Big[I]);
        If Length(D) >= 120 Then
        Begin
          BufStr(M, AnsiToUtf8(UnDisp(D))); D := '';
        End;
      End;
    BufStr(M, AnsiToUtf8(UnDisp(D)));
  End;
  Dummy := SetCursor(WaitCur);
  If DoCommit(M, H) Then
  Begin
    SetText(ESum, ''); SetText(EDesc, '');
    Dummy := SetFocus(Lv[LvChg].H);
    RefreshRepo(False);
    SetStatus('Commit ' + Copy(ShaHex(H), 1, 7) + ' cr'#233#233' dans ' +
      CurBranch + ' : ' + S);
  End
  Else ErrBox('Validation impossible : ' + GitErr);
  Dummy := SetCursor(ArrowCur);
  BufFree(M);
End;

Procedure CheckoutCmd(Const Name : String; FromRemote : Boolean);
Var H : TSha;
Begin
  If Not Clean Then
  Begin
    ErrBox('Vous avez des modifications non valid'#233'es. Validez-les ou ' +
      'annulez-les avant de changer de branche.');
    Exit;
  End;
  If FromRemote Then
  Begin
    { cree la branche locale qui suit origin/Name }
    If Not RefRead('refs/remotes/origin/' + Name, H) Then Exit;
    If Not RefWrite('refs/heads/' + Name, H) Then
    Begin
      ErrBox('Cr'#233'ation de la branche impossible.'); Exit;
    End;
    SetUpstream(Name, 'origin');
  End;
  Dummy := SetCursor(WaitCur);
  If SwitchBranch(Name) Then SetStatus('Branche ' + Utf8ToAnsi(Name) +
    ' extraite')
  Else ErrBox('Changement de branche impossible : ' + GitErr);
  Dummy := SetCursor(ArrowCur);
  RefreshRepo(False);
End;

Procedure NewBranchCmd;
Var S : String;
Begin
  S := '';
  If Not InputBox('Cr'#233'er une branche', 'Nom de la nouvelle branche ' +
    '(cr'#233#233'e '#224' partir de ' + CurBranch + ') :', S) Then Exit;
  S := AnsiToUtf8(S);
  While Pos(' ', S) > 0 Do S[Pos(' ', S)] := '-';
  If Not ValidBranch(S) Then
  Begin
    ErrBox('Nom de branche non valable : ' + S); Exit;
  End;
  If FileExist(GitPath('refs/heads/' + S)) Then
  Begin
    ErrBox('La branche ' + S + ' existe d'#233'j'#224'.'); Exit;
  End;
  If Not ShaIsZero(HeadSha) Then
    If Not RefWrite('refs/heads/' + S, HeadSha) Then
    Begin
      ErrBox('Cr'#233'ation de la branche impossible.'); Exit;
    End;
  SetHead('refs/heads/' + S);
  RefreshRepo(True);
  SetStatus('Branche ' + Utf8ToAnsi(S) + ' cr'#233#233'e et extraite');
End;

Procedure RenameBranchCmd;
Var S, Old : String; H : TSha;
Begin
  If CurBranch = '' Then Exit;
  Old := CurBranch;
  S := Utf8ToAnsi(Old);
  If Not InputBox('Renommer la branche', 'Nouveau nom de la branche ' +
    Utf8ToAnsi(Old) + ' :', S) Then Exit;
  S := AnsiToUtf8(S);
  If (S = Old) Then Exit;
  If Not ValidBranch(S) Or FileExist(GitPath('refs/heads/' + S)) Then
  Begin
    ErrBox('Nom de branche non valable ou d'#233'j'#224' utilis'#233' : ' + S);
    Exit;
  End;
  If RefRead('refs/heads/' + Old, H) Then
  Begin
    If Not RefWrite('refs/heads/' + S, H) Then Exit;
    RefDelete('refs/heads/' + Old);
  End;
  SetHead('refs/heads/' + S);
  RefreshRepo(True);
End;

Function PickBranch(Const Title : String; Var Ref : String) : Boolean;
Begin
  PickBranch := MergeDialog(Ref);
  If Title = '' Then ;
End;

Procedure DeleteBranchCmd;
Var Ref, Nm : String;
Begin
  If Not MergeDialog(Ref) Then Exit;
  If Copy(Ref, 1, 11) <> 'refs/heads/' Then
  Begin
    ErrBox('Choisissez une branche locale '#224' supprimer.'); Exit;
  End;
  Nm := Copy(Ref, 12, 120);
  If Ask('Supprimer la branche locale ' + Utf8ToAnsi(Nm) + ' ?'#13#10 +
    'Les commits qui ne sont dans aucune autre branche seront perdus.',
    'Supprimer la branche', MB_YESNO Or MB_ICONWARNING) <> IDYES Then Exit;
  RefDelete(Ref);
  RefreshRepo(True);
  SetStatus('Branche ' + Utf8ToAnsi(Nm) + ' supprim'#233'e');
End;

Procedure ReportMerge(R : LongInt; Const What : String);
Var I : LongInt; S : String;
Begin
  Case R Of
    0 : ErrBox(What + ' impossible : ' + GitErr);
    1 : SetStatus('D'#233'j'#224' '#224' jour');
    2 : SetStatus(What + ' : avance rapide');
    3 : SetStatus(What + ' : commit de fusion cr'#233#233);
    4 :
    Begin
      RefreshRepo(False);
      S := '';
      For I := 0 To Chg.N - 1 Do
        If ((Chg.E^[I].Flag And $FF) = StConf) And (Length(S) < 180) Then
          S := S + #13#10'  ' + Utf8ToAnsi(Chg.E^[I].Path);
      ErrBox(What + ' : ' + IStr(MergeConf) + ' conflit(s). Corrigez les ' +
        'fichiers marqu'#233's (<<<<<<< ======= >>>>>>>) puis validez la ' +
        'fusion.' + S);
    End;
  End;
End;

Procedure MergeCmd;
Var Ref : String; H : TSha; R : LongInt;
Begin
  If Not MergeDialog(Ref) Then Exit;
  If Not RefRead(Ref, H) Then Exit;
  Dummy := SetCursor(WaitCur);
  If Copy(Ref, 1, 11) = 'refs/heads/' Then
    R := DoMerge(H, 'branch ''' + Copy(Ref, 12, 120) + '''')
  Else R := DoMerge(H, 'remote-tracking branch ''' + Copy(Ref, 14, 120) +
    '''');
  Dummy := SetCursor(ArrowCur);
  RefreshRepo(False);
  ReportMerge(R, 'Fusion');
End;

Procedure DiscardCmd(One : Boolean);
Var I : LongInt; Q : String;
Begin
  If Chg.N = 0 Then Exit;
  If One Then
  Begin
    If (ChgSel < 0) Or (ChgSel >= Chg.N) Then Exit;
    Q := 'Annuler les modifications de ' + Utf8ToAnsi(Chg.E^[ChgSel].Path) +
      ' ?';
  End
  Else Q := 'Annuler toutes les modifications (' + IStr(Chg.N) +
    ' fichier(s)) ?';
  If Ask(Q + #13#10'Cette op'#233'ration est irr'#233'versible.',
    'Annuler les modifications', MB_YESNO Or MB_ICONWARNING) <> IDYES Then
    Exit;
  For I := 0 To Chg.N - 1 Do
    If One And (I <> ChgSel) Then
      Chg.E^[I].Flag := Chg.E^[I].Flag And Not FlSel
    Else Chg.E^[I].Flag := Chg.E^[I].Flag Or FlSel;
  If Not DiscardSel Then ErrBox('Certaines modifications n''ont pas pu ' +
    'etre annul'#233'es : ' + GitErr);
  RefreshRepo(False);
End;

Procedure IgnoreCmd;
Var B : TBuf; P : String;
Begin
  If (ChgSel < 0) Or (ChgSel >= Chg.N) Then Exit;
  BufInit(B);
  If FileLoad(WorkDir + PS + '.gitignore', B) Then ;
  If (B.N > 0) And (B.P^[B.N - 1] <> 10) Then BufByte(B, 10);
  P := Chg.E^[ChgSel].Path;
  BufStr(B, '/' + P + #10);
  If Not FileSave(WorkDir + PS + '.gitignore', B, 0, B.N) Then
    ErrBox('Ecriture de .gitignore impossible.');
  BufFree(B);
  RefreshRepo(True);
End;

Procedure Shell(Const F, Prm : String);
Var A, B, C : Array[0..299] Of Byte;
Begin
  PutZ(A, F); PutZ(B, Prm); PutZ(C, WorkDir);
  If Prm = '' Then
    Dummy := ShellExecuteA(MainWnd, Z2('open'), LongInt(@A), 0, LongInt(@C),
      1)
  Else Dummy := ShellExecuteA(MainWnd, Z2('open'), LongInt(@A), LongInt(@B),
    LongInt(@C), 1);
End;

Function GitHubPage : String;
Var U : String; K : LongInt;
Begin
  GitHubPage := '';
  U := CfgGet('remote', 'origin', 'url');
  K := Pos('github.com/', LowStr(U));
  If K = 0 Then
  Begin
    K := Pos('github.com:', LowStr(U));
    If K = 0 Then Exit;
  End;
  U := Copy(U, K + 11, 255);
  If LowStr(Copy(U, Length(U) - 3, 4)) = '.git' Then
    Delete(U, Length(U) - 3, 4);
  GitHubPage := 'https://github.com/' + U;
End;

Procedure SyncCmd(K : LongInt);
Begin
  If Busy Or (RepoCur < 0) Then Exit;
  If (K = OpPush) Or (K = OpPull) Then
    If CurBranch = '' Then
    Begin
      ErrBox('HEAD est d'#233'tach'#233'e : cr'#233'ez ou extrayez une ' +
        'branche.');
      Exit;
    End;
  If (K = OpPull) And Not Clean Then
  Begin
    ErrBox('Validez ou annulez vos modifications avant de tirer.'); Exit;
  End;
  If (K = OpPush) And ShaIsZero(HeadSha) Then
  Begin
    ErrBox('Aucun commit '#224' pousser : validez d''abord.'); Exit;
  End;
  If (K <> OpFetch) And (CfgGet('remote', 'origin', 'url') = '') Then
  Begin
    If GhToken <> '' Then
    Begin
      If Not PublishDialog Then Exit;
      OpBranch := CurBranch;
      StartOp(OpPublish);
    End
    Else ErrBox('Ce d'#233'p'#244't n''a pas de d'#233'p'#244't distant. ' +
      'D'#233'finissez origin dans D'#233'p'#244't > Param'#232'tres, ou ' +
      'connectez-vous '#224' GitHub (Fichier > Options) pour le publier.');
    Exit;
  End;
  OpBranch := CurBranch;
  StartOp(K);
End;

Procedure NewRepoCmd;
Var P, Nm : String; B : TBuf; H : TSha; K : LongInt;
Begin
  If Not NewRepoDialog Then Exit;
  Nm := DlgOut[0];
  While Pos(' ', Nm) > 0 Do Nm[Pos(' ', Nm)] := '-';
  P := JoinDir(DlgOut[2], Nm);
  If DirExist(P + '\.git') Then
  Begin
    ErrBox('Le dossier ' + P + ' contient d'#233'j'#224' un d'#233'p'#244't.');
    Exit;
  End;
  If Not InitRepo(P, 'main') Then
  Begin
    ErrBox('Cr'#233'ation impossible : ' + GitErr); Exit;
  End;
  BufInit(B);
  If DlgOut[3] = '1' Then
  Begin
    BufStr(B, '# ' + AnsiToUtf8(Nm) + #10);
    If DlgOut[1] <> '' Then BufStr(B, #10 + AnsiToUtf8(DlgOut[1]) + #10);
    If FileSave(P + '\README.md', B, 0, B.N) Then ;
  End;
  If DlgOut[4] = '1' Then
    If FileSaveStr(P + '\.gitignore', '*.EXE'#10'*.OBJ'#10'*.TMP'#10 +
      '*.BAK'#10'*.~*'#10) Then ;
  K := RepoAdd(P);
  RepoCur := K;
  ReposSave;
  LoadIdentity;
  If RepoStatus And (Chg.N > 0) Then
  Begin
    B.N := 0;
    BufStr(B, 'Initial commit'#10);
    If Not DoCommit(B, H) Then ErrBox('Commit initial : ' + GitErr);
  End;
  BufFree(B);
  OpenRepo(K);
  SetStatus('D'#233'p'#244't ' + Nm + ' cr'#233#233' dans ' + P);
End;

Procedure AddRepoCmd;
Var P : String; K : LongInt;
Begin
  If Not AddLocalDialog Then Exit;
  P := DlgOut[0];
  If (Length(P) > 3) And (P[Length(P)] = '\') Then Delete(P, Length(P), 1);
  If Not DirExist(P) Then
  Begin
    ErrBox('Le dossier ' + P + ' n''existe pas.'); Exit;
  End;
  If Not SetRepo(P) Then
  Begin
    If Ask('Le dossier ' + P + ' n''est pas un d'#233'p'#244't Git.'#13#10 +
      'Voulez-vous en cr'#233'er un dans ce dossier ?', 'Ajouter un d'#233'p'
      + #244't local', MB_YESNO Or MB_ICONQUESTION) <> IDYES Then Exit;
    If Not InitRepo(P, 'main') Then
    Begin
      ErrBox('Cr'#233'ation impossible : ' + GitErr); Exit;
    End;
  End;
  K := RepoAdd(P);
  OpenRepo(K);
End;

Procedure RepoListMenu(X, Y : LongInt);
Var M, I, R : LongInt; P : Array[0..1] Of LongInt;
Begin
  M := CreatePopupMenu;
  For I := 0 To RepoN - 1 Do
  Begin
    MItem(M, CmRepo + I, RepoTitle(I) + '   (' + RepoPath[I] + ')');
    If I = RepoCur Then Dummy := CheckMenuItem(M, CmRepo + I, MF_CHECKED);
  End;
  If RepoN > 0 Then MItem(M, 0, '');
  MItem(M, CmClone, '~Cloner un d'#233'p'#244't...');
  MItem(M, CmNewRepo, '~Nouveau d'#233'p'#244't...');
  MItem(M, CmAddRepo, '~Ajouter un d'#233'p'#244't local...');
  P[0] := X; P[1] := Y;
  Dummy := ClientToScreen(MainWnd, LongInt(@P));
  R := TrackPopupMenu(M, TPM_RETURNCMD, P[0], P[1], 0, MainWnd, 0);
  Dummy := DestroyMenu(M);
  If R > 0 Then Dummy := PostMessageA(MainWnd, WM_COMMAND, R, 0);
End;

Procedure BranchListMenu(X, Y : LongInt);
Var M, I, K, R : LongInt; P : Array[0..1] Of LongInt; Nm : String;
    Dup : Boolean;
Begin
  If RepoCur < 0 Then Exit;
  M := CreatePopupMenu;
  BrN := 0;
  RefsList(LocRefs, 'refs/heads/');
  For I := 0 To LocRefs.N - 1 Do
    If BrN < 300 Then
    Begin
      BrList[BrN] := Copy(LocRefs.Name[I], 12, 120);
      If BrN < 200 Then MItem(M, CmBrLocal + BrN, Utf8ToAnsi(BrList[BrN]));
      If BrList[BrN] = CurBranch Then
        Dummy := CheckMenuItem(M, CmBrLocal + BrN, MF_CHECKED);
      Inc(BrN);
    End;
  BrRemN := 0;
  RefsList(LocRefs, 'refs/remotes/origin/');
  For I := 0 To LocRefs.N - 1 Do
  Begin
    Nm := Copy(LocRefs.Name[I], 21, 120);
    If Nm = 'HEAD' Then Continue;
    Dup := False;
    For K := 0 To BrN - 1 Do
      If BrList[K] = Nm Then Dup := True;
    If Dup Or (BrN + BrRemN >= 300) Or (BrRemN >= 200) Then Continue;
    If BrRemN = 0 Then MItem(M, 0, '');
    BrList[BrN + BrRemN] := Nm;
    MItem(M, CmBrRemote + BrRemN, 'origin/' + Utf8ToAnsi(Nm));
    Inc(BrRemN);
  End;
  MItem(M, 0, '');
  MItem(M, CmNewBranch, '~Nouvelle branche...');
  MItem(M, CmMerge, '~Fusionner dans ' + Utf8ToAnsi(CurBranch) + '...');
  P[0] := X; P[1] := Y;
  Dummy := ClientToScreen(MainWnd, LongInt(@P));
  R := TrackPopupMenu(M, TPM_RETURNCMD, P[0], P[1], 0, MainWnd, 0);
  Dummy := DestroyMenu(M);
  If R > 0 Then Dummy := PostMessageA(MainWnd, WM_COMMAND, R, 0);
End;

Procedure ChangesMenu(X, Y : LongInt);
Var M, R : LongInt; P : Array[0..1] Of LongInt;
Begin
  M := CreatePopupMenu;
  MItem(M, CmDiscardOne, '~Annuler les modifications...');
  MItem(M, CmIgnore, 'Ajouter '#224' .~gitignore');
  MItem(M, 0, '');
  MItem(M, CmCopyPath, 'Copier le ~chemin');
  MItem(M, CmOpenFile, '~Ouvrir le fichier');
  P[0] := X; P[1] := Y;
  Dummy := ClientToScreen(Lv[LvChg].H, LongInt(@P));
  R := TrackPopupMenu(M, TPM_RETURNCMD, P[0], P[1], 0, MainWnd, 0);
  Dummy := DestroyMenu(M);
  If R > 0 Then Dummy := PostMessageA(MainWnd, WM_COMMAND, R, 0);
End;

Procedure AboutBox;
Begin
  Dummy := Ask('Client GitHub pour Pasdows 95'#13#10'Version 1.0'#13#10 +
    #13#10'Auteur : Sylvain Maltais'#13#10'Licence : MIT'#13#10#13#10 +
    'Protocole Git (HTTP/HTTPS intelligent et git://), packs, deltas, ' +
    'fusion '#224' trois voies, API de GitHub.com.'#13#10 +
    'Compil'#233' avec le Windows 95 Pascal Compiler (WPC).',
    'A propos du Client GitHub', MB_OK Or MB_ICONINFO);
End;

Procedure KeysBox;
Begin
  Dummy := Ask('Ctrl+1 / Ctrl+2'#9'Modifications / Historique'#13#10 +
    'Ctrl+T / Ctrl+B'#9'Liste des d'#233'p'#244'ts / des branches'#13#10 +
    'Ctrl+N / Ctrl+O'#9'Nouveau d'#233'p'#244't / Ajouter un d'#233'p'#244't'
    + #13#10'Ctrl+Maj+O'#9'Cloner un d'#233'p'#244't'#13#10 +
    'Ctrl+P / Ctrl+Maj+P'#9'Pousser / Tirer'#13#10 +
    'Ctrl+Maj+T'#9'R'#233'cup'#233'rer'#13#10 +
    'Ctrl+Maj+N'#9'Nouvelle branche'#13#10 +
    'Ctrl+Maj+M'#9'Fusionner dans la branche actuelle'#13#10 +
    'Ctrl+Entr'#233'e'#9'Valider'#13#10'F5'#9'Actualiser'#13#10 +
    'Espace'#9'Cocher ou d'#233'cocher le fichier', 'Raccourcis clavier',
    MB_OK Or MB_ICONINFO);
End;

Procedure DoMenu(Cmd : LongInt);
Var I : LongInt; S : String;
Begin
  If Busy And (Cmd <> CmExit) And (Cmd <> CmAbout) And (Cmd <> CmGhHelp) And
     (Cmd <> CmViewChg) And (Cmd <> CmViewHist) Then
  Begin
    Dummy := MessageBeep(0); Exit;
  End;
  If (Cmd >= CmRepo) And (Cmd < CmRepo + MaxRepo) Then
  Begin
    OpenRepo(Cmd - CmRepo); Exit;
  End;
  If (Cmd >= CmBrLocal) And (Cmd < CmBrRemote + 300) And (RepoCur >= 0) Then
  Begin
    If (Cmd < CmBrRemote) Then
    Begin
      I := Cmd - CmBrLocal;
      If (I < BrN) And (BrList[I] <> CurBranch) Then
        CheckoutCmd(BrList[I], False);
    End
    Else
    Begin
      I := Cmd - CmBrRemote;
      If I < BrRemN Then CheckoutCmd(BrList[BrN + I], True);
    End;
    Exit;
  End;
  Case Cmd Of
    CmNewRepo : NewRepoCmd;
    CmAddRepo : AddRepoCmd;
    CmClone : If CloneDialog Then StartOp(OpClone);
    CmOptions : If OptionsDialog Then RefreshRepo(True);
    CmExit : Dummy := DestroyWindow(MainWnd);
    CmCheckAll, CmUncheckAll :
    Begin
      For I := 0 To Chg.N - 1 Do
        If Cmd = CmCheckAll Then Chg.E^[I].Flag := Chg.E^[I].Flag Or FlSel
        Else Chg.E^[I].Flag := Chg.E^[I].Flag And Not FlSel;
      LvRepaint(LvChg);
      CheckedChanged;
    End;
    CmDiscardAll : DiscardCmd(False);
    CmDiscardOne : DiscardCmd(True);
    CmCopyPath :
      If (View = VwChanges) And (ChgSel >= 0) Then
        CopyToClip(WorkPath(Chg.E^[ChgSel].Path))
      Else If (View = VwHistory) And (FileSel >= 0) Then
        CopyToClip(WorkPath(HFiles.E^[FileSel].Path));
    CmOpenFile :
      If (View = VwChanges) And (ChgSel >= 0) Then
        Shell(WorkPath(Chg.E^[ChgSel].Path), '');
    CmIgnore : IgnoreCmd;
    CmViewChg : SetView(VwChanges);
    CmViewHist : SetView(VwHistory);
    CmRepoList : RepoListMenu(TbX(0) + 4, TbH - 4);
    CmBranchList : BranchListMenu(TbX(1) + 4, TbH - 4);
    CmRefresh : RefreshRepo(True);
    CmPush : SyncCmd(OpPush);
    CmPull : SyncCmd(OpPull);
    CmFetch : SyncCmd(OpFetch);
    CmPublish :
      If GhToken = '' Then ErrBox('Connectez-vous d''abord '#224' GitHub ' +
        '(Fichier > Options, jeton d''acc'#232's personnel).')
      Else If CfgGet('remote', 'origin', 'url') <> '' Then
        ErrBox('Ce d'#233'p'#244't a d'#233'j'#224' un d'#233'p'#244't distant ' +
          '(origin).')
      Else If PublishDialog Then
      Begin
        OpBranch := CurBranch;
        StartOp(OpPublish);
      End;
    CmViewGh :
    Begin
      S := GitHubPage;
      If S = '' Then ErrBox('Le d'#233'p'#244't distant n''est pas sur ' +
        'GitHub.com.')
      Else Shell(S, '');
    End;
    CmExplorer : Shell(WorkDir, '');
    CmDos : Shell('COMMAND.COM', '');
    CmRepoSet : If RepoSetDialog Then RefreshRepo(True);
    CmRemoveRepo :
      If Ask('Retirer ' + RepoTitle(RepoCur) + ' de la liste ?'#13#10 +
        '(Les fichiers ne sont pas supprim'#233's.)', 'Retirer le d'#233'p'#244
        + 't', MB_YESNO Or MB_ICONQUESTION) = IDYES Then
      Begin
        RepoRemove(RepoCur);
        If RepoN > 0 Then RepoCur := 0;
        ReposSave;
        RefreshRepo(False);
      End;
    CmNewBranch : NewBranchCmd;
    CmRenBranch : RenameBranchCmd;
    CmDelBranch : DeleteBranchCmd;
    CmMerge : MergeCmd;
    CmAbout : AboutBox;
    CmGhHelp : KeysBox;
  End;
End;

{ fin d'une operation reseau }
Procedure OpDone;
Var K, R : LongInt; Retry : Boolean;
Begin
  Busy := False;
  WorkTid := 0;
  Retry := False;
  If Not OpOk And (Pos('(401)', GitErr) > 0) And (Op <> OpPublish) And
     (Op <> OpGhList) And (Op <> OpSignIn) Then
  Begin
    If (Op = OpClone) And UrlSplit(OpUrl) Then Retry := CredDialog(UrlHost)
    Else If (RepoCur >= 0) And UrlSplit(CfgGet('remote', 'origin', 'url'))
    Then Retry := CredDialog(UrlHost);
  End;
  If Retry Then
  Begin
    { recommence dans un dossier vide }
    If Op = OpClone Then RmTree(OpDir, 0);
    StartOp(Op);
    Exit;
  End;
  Case Op Of
    OpClone :
      If OpOk Then
      Begin
        K := RepoAdd(OpDir);
        OpenRepo(K);
        SetStatus('Clonage termin'#233' : ' + OpDir);
      End
      Else
      Begin
        RmTree(OpDir, 0);
        ErrBox('Clonage impossible : ' + GitErr);
        RefreshRepo(True);
      End;
    OpFetch :
    Begin
      RefreshRepo(True);
      If OpOk Then SetStatus('R'#233'cup'#233'ration termin'#233'e')
      Else ErrBox('R'#233'cup'#233'ration impossible : ' + GitErr);
    End;
    OpPull :
    Begin
      R := OpRes;
      RefreshRepo(False);
      If OpOk Or (R = 0) Then ReportMerge(R, 'Tirage');
    End;
    OpPush, OpPublish :
    Begin
      RefreshRepo(True);
      If OpOk Then
      Begin
        If PushMsg = 'deja a jour' Then SetStatus('D'#233'j'#224' '#224' jour')
        Else SetStatus('Branche ' + OpBranch + ' pouss'#233'e vers origin');
      End
      Else If Op = OpPublish Then ErrBox('Publication impossible : ' + GitErr)
      Else ErrBox('Envoi impossible : ' + GitErr);
    End;
  End;
  Redraw;
End;

Procedure TbClick(X, Y : LongInt);
Var I : LongInt;
Begin
  If Y >= TbH Then Exit;
  For I := 0 To 2 Do
    If (X >= TbX(I)) And (X < TbX(I) + 228) Then
    Begin
      If (I = 2) And (RepoCur < 0) Then Exit;
      TbDown := I;
      InvalidateStatus;
      Dummy := UpdateWindow(MainWnd);
      Case I Of
        0 : If Not Busy Then RepoListMenu(TbX(0) + 4, TbH - 4);
        1 : If Not Busy Then BranchListMenu(TbX(1) + 4, TbH - 4);
        2 :
          If Busy Then
          Begin
            If Ask('Annuler l''op'#233'ration en cours ?', 'Client GitHub',
              MB_YESNO Or MB_ICONQUESTION) = IDYES Then NetAbort := True;
          End
          Else
            Case SyncKind Of
              1 : DoMenu(CmPublish);
              2, 4 : SyncCmd(OpPush);
              3 : SyncCmd(OpPull);
              Else SyncCmd(OpFetch);
            End;
      End;
      TbDown := -1;
      InvalidateStatus;
      Exit;
    End;
End;

Procedure TabClick(X, Y : LongInt);
Var N : LongInt;
Begin
  If (RepoCur < 0) Or (X >= LX) Then Exit;
  If (Y >= CY0) And (Y < CY0 + TabH) Then
  Begin
    If X < LX Div 2 Then SetView(VwChanges) Else SetView(VwHistory);
  End
  Else If (View = VwChanges) And (Y >= CY0 + TabH) And
     (Y < CY0 + TabH + ChkH) And (X < 24) And Not Busy Then
  Begin
    N := CheckedCount;
    If N = Chg.N Then DoMenu(CmUncheckAll) Else DoMenu(CmCheckAll);
  End;
End;

{ raccourcis clavier (avant la distribution du message) }
Function Accel(VK : LongInt) : Boolean;
Var C, Sh : Boolean; Cmd : LongInt;
Begin
  Accel := False;
  C := KeyDown(VK_CONTROL); Sh := KeyDown(VK_SHIFT);
  Cmd := 0;
  If VK = VK_F5 Then Cmd := CmRefresh
  Else If C Then
    Case VK Of
      Ord('1') : Cmd := CmViewChg;
      Ord('2') : Cmd := CmViewHist;
      Ord('T') : If Sh Then Cmd := CmFetch Else Cmd := CmRepoList;
      Ord('B') : Cmd := CmBranchList;
      Ord('N') : If Sh Then Cmd := CmNewBranch Else Cmd := CmNewRepo;
      Ord('O') : If Sh Then Cmd := CmClone Else Cmd := CmAddRepo;
      Ord('P') : If Sh Then Cmd := CmPull Else Cmd := CmPush;
      Ord('M') : If Sh Then Cmd := CmMerge;
      Ord('G') : If Sh Then Cmd := CmViewGh;
      Ord('F') : If Sh Then Cmd := CmExplorer;
      $BC : Cmd := CmOptions;
      VK_DELETE : If Sh Then Cmd := CmDiscardAll;
      VK_RETURN : If View = VwChanges Then
                  Begin
                    DoCommitCmd; Accel := True; Exit;
                  End;
      Ord('A') : If (GetFocus <> ESum) And (GetFocus <> EDesc) Then
                   Cmd := CmCheckAll;
    End;
  If Cmd = 0 Then Exit;
  If (RepoCur < 0) And (Cmd <> CmNewRepo) And (Cmd <> CmAddRepo) And
     (Cmd <> CmClone) And (Cmd <> CmOptions) Then Exit;
  DoMenu(Cmd);
  Accel := True;
End;

Procedure MakeChildren(H : LongInt);
Var K : LongInt;
Begin
  For K := 0 To 2 Do
  Begin
    Lv[K].H := CreateWindowExA(0, Z2('GCLIST'), 0, WS_CHILD
      Or WS_TABSTOP, 0, 0, 100, 100, H, 40 + K, Inst, 0);
    Lv[K].Sb := CreateWindowExA(0, Z2('SCROLLBAR'), 0, WS_CHILD Or
      WS_VISIBLE Or SBS_VERT, 0, 0, SbW, 100, Lv[K].H, 50 + K, Inst, 0);
  End;
  Lv[LvChg].RowH := 20; Lv[LvHist].RowH := 36; Lv[LvFiles].RowH := 18;
  DiffWnd := CreateWindowExA(0, Z2('GCDIFF'), 0, WS_CHILD Or
    WS_TABSTOP, 0, 0, 100, 100, H, 60, Inst, 0);
  DSbV := CreateWindowExA(0, Z2('SCROLLBAR'), 0, WS_CHILD Or WS_VISIBLE Or
    SBS_VERT, 0, 0, SbW, 100, DiffWnd, 61, Inst, 0);
  DSbH := CreateWindowExA(0, Z2('SCROLLBAR'), 0, WS_CHILD Or WS_VISIBLE Or
    SBS_HORZ, 0, 0, 100, SbW, DiffWnd, 62, Inst, 0);
  ESum := Ctl(H, 'EDIT', '', WS_BORDER Or ES_AUTOHSCROLL Or WS_TABSTOP, 0,
    0, 10, 10, IdSum);
  EDesc := Ctl(H, 'EDIT', '', WS_BORDER Or ES_MULTILINE Or ES_AUTOVSCROLL Or
    ES_WANTRETURN Or WS_TABSTOP, 0, 0, 10, 10, IdDescE);
  BCommit := Ctl(H, 'BUTTON', 'Valider', BS_DEFPUSHBUTTON Or WS_TABSTOP, 0,
    0, 10, 10, IdCommit);
  BWClone := Ctl(H, 'BUTTON', 'Cloner un d'#233'p'#244't depuis Internet...',
    WS_TABSTOP, 0, 0, 10, 10, IdWClone);
  BWNew := Ctl(H, 'BUTTON', 'Cr'#233'er un nouveau d'#233'p'#244't sur votre ' +
    'disque...', WS_TABSTOP, 0, 0, 10, 10, IdWNew);
  BWAdd := Ctl(H, 'BUTTON', 'Ajouter un d'#233'p'#244't existant...',
    WS_TABSTOP, 0, 0, 10, 10, IdWAdd);
End;

Function MainProc0(H, Msg, WP, LP : LongInt) : LongInt;
Var Id, Code : LongInt;
Begin
  MainProc0 := 0;
  Case Msg Of
    WM_SIZE :
    Begin
      CW0 := LP And $FFFF; CH0 := (LP Shr 16) And $FFFF;
      Layout;
      Dummy := InvalidateRect(H, 0, 0);
    End;
    WM_PAINT : MainPaint(H);
    WM_ERASEBKGND : MainProc0 := 1;
    WM_LBUTTONDOWN :
    Begin
      If S16(LP Shr 16) < TbH Then TbClick(S16(LP), S16(LP Shr 16))
      Else TabClick(S16(LP), S16(LP Shr 16));
    End;
    WM_COMMAND :
    Begin
      Id := WP And $FFFF; Code := (WP Shr 16) And $FFFF;
      Case Id Of
        IdSum : If Code = EN_CHANGE Then UpdateCommitBtn;
        IdCommit : DoCommitCmd;
        IdWClone : DoMenu(CmClone);
        IdWNew : DoMenu(CmNewRepo);
        IdWAdd : DoMenu(CmAddRepo);
        Else If (Id > 100) And (LP = 0) Then
        Begin
          MenuState;
          DoMenu(Id);
        End
        Else If Id > 100 Then DoMenu(Id);
      End;
    End;
    WM_GITPROG : InvalidateStatus;
    WM_GITDONE : OpDone;
    WM_TIMER : If Busy Then InvalidateStatus;
    $0006 :
      If ((WP And $FFFF) <> 0) And (RepoCur >= 0) And Not Busy And
         Not DlgDone And (DlgWnd = 0) And
         (GetTickCount - LastRefresh > 5000) Then
        Dummy := PostMessageA(H, WM_COMMAND, CmRefresh, 1);
    WM_CLOSE :
      If Busy Then
      Begin
        If Ask('Une op'#233'ration r'#233'seau est en cours. Quitter quand ' +
          'm'#234'me ?', 'Client GitHub', MB_YESNO Or MB_ICONWARNING) = IDYES
        Then
        Begin
          NetAbort := True;
          Dummy := DestroyWindow(H);
        End;
      End
      Else Dummy := DestroyWindow(H);
    WM_DESTROY : PostQuitMessage(0);
  Else
    MainProc0 := DefWindowProcA(H, Msg, WP, LP);
  End;
End;

Function MainProc(H, Msg, WP, LP : LongInt) : LongInt; stdcall;
Begin
  BigLock;
  MainProc := MainProc0(H, Msg, WP, LP);
  BigUnlock;
End;

{ ==================================================================== }
{ Programme principal                                                   }
{ ==================================================================== }

Var
  Sw, Shh, Ww, Wh : LongInt;
  Handled : Boolean;

Begin
  Inst := GetModuleHandleA(0);
  DetectOem;
  FsAnsi := True;
  FindAppDir;
  InitializeCriticalSection(LongInt(@Lock[0]));
  LockOn := True;
  AgentName := 'git/2.0 (Pasdows 95; Client GitHub 1.0)';
  FlatInit(HFiles); BufInit(HMsg);
  BufInit(DfA); BufInit(DfB);
  TbDown := -1; ChgSel := -1; HistSel := -1; FileSel := -1;
  WaitCur := LoadCursorA(0, IDC_WAIT); ArrowCur := LoadCursorA(0, IDC_ARROW);
  Fnt := CreateFontA(13, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0,
    Z('MS Sans Serif'));
  RegClass('GCMAIN', LongInt(@MainProc), 0);
  RegClass('GCLIST', LongInt(@LvProc), CS_DBLCLKS);
  RegClass('GCDIFF', LongInt(@DiffProc), 0);
  RegClass('GCDLG', LongInt(@DlgProc), 0);
  BigLock;
  GhToken := IniGet('Compte', 'Jeton', '');
  GhLogin := IniGet('Compte', 'Login', '');
  DefName := IniGet('Identite', 'Nom', '');
  DefEmail := IniGet('Identite', 'Courriel', '');
  ProxyStr := IniGet('Options', 'Proxy', '');
  CloneRoot := IniGet('Options', 'Dossier', 'C:\Mes documents\GitHub');
  ReposLoad;
  If (RepoCur < 0) And (RepoN > 0) Then RepoCur := 0;
  StatusTxt := 'Pr'#234't';
  BigUnlock;
  Sw := GetSystemMetrics(SM_CXSCREEN); Shh := GetSystemMetrics(SM_CYSCREEN);
  Ww := MinL(Sw, 860); Wh := MinL(Shh - 28, 620);
  MainWnd := CreateWindowExA(0, Z2('GCMAIN'), Z('Client GitHub'),
    WS_OVERLAPPEDWINDOW Or WS_CLIPCHILDREN, (Sw - Ww) Div 2,
    MaxL(0, (Shh - 28 - Wh) Div 2), Ww, Wh, 0, 0, Inst, 0);
  BigLock;
  MakeChildren(MainWnd);
  BuildMenus;
  BigUnlock;
  If Sw <= 800 Then Dummy := ShowWindow(MainWnd, 3)
  Else Dummy := ShowWindow(MainWnd, 1);
  Dummy := UpdateWindow(MainWnd);
  BigLock;
  Layout;
  RefreshRepo(False);
  BigUnlock;
  Dummy := SetTimer(MainWnd, 1, 1000, 0);
  While GetMessageA(LongInt(@Qmsg), 0, 0, 0) > 0 Do
  Begin
    Handled := False;
    If (Qmsg[1] = WM_KEYDOWN) And (DlgWnd = 0) Then
    Begin
      BigLock;
      Handled := Accel(Qmsg[2]);
      BigUnlock;
    End;
    If Not Handled Then
    Begin
      Dummy := TranslateMessage(LongInt(@Qmsg));
      Dummy := DispatchMessageA(LongInt(@Qmsg));
    End;
  End;
  NetAbort := True;
  Sleep(200);
  ExitProcess(0);
End.
