; NTFSBOOT.ASM - Chargeur d'amorce NTFS de Pasdows 95 ($Boot, 8 Ko)
;
; Ecrit par INSTALL.PAS dans les 16 premiers secteurs d'une partition
; NTFS (type 07h) ; les octets 3 a 83 du secteur 0 (BPB NTFS) sont
; ceux du volume formate. Le secteur 0 se recopie en 9000:0000, y lit
; les secteurs 1 a 15 puis continue :
;   - enregistrement 0 de la MFT ($MFT) : runs de son attribut $DATA ;
;   - enregistrement 5 (racine) : parcours de tout l'index $I30
;     ($INDEX_ROOT puis blocs INDX de $INDEX_ALLOCATION) a la recherche
;     de IO.SYS (sans tenir compte de la casse) ;
;   - enregistrement d'IO.SYS : ses runs $DATA sont lus en 07C0:0000 ;
;   - comme BOOT32.ASM : taille de la table d'information d'amorce
;     d'IO.SYS mise a 0, saut en 07C0:0000 avec DL = unite.
; Les enregistrements de la MFT et les blocs d'index sont proteges par
; des correctifs de secteurs (multi-sector protection) appliques ici.
;
; Assemblage : nasm -f bin NTFSBOOT.ASM -o NTFSBOOT.BIN

        bits    16
        org     0

LSEG    equ     9000h                   ; chargeur
RECBUF  equ     2000h                   ; enregistrement MFT (4 Ko max)
IDXBUF  equ     3000h                   ; bloc INDX (16 Ko max)
MFTRUN  equ     7000h                   ; runs de $MFT (12 octets)
WRKRUN  equ     8000h                   ; runs de travail
QUEUE   equ     9000h                   ; VCN des blocs INDX a parcourir

        jmp     short start
        nop
        db      'NTFS    '              ; 03
bps     dw      512                     ; 0B
spc     db      8                       ; 0D
        times   0x1C - ($ - $$) db 0
hidden  dd      0                       ; 1C
        times   0x24 - ($ - $$) db 0
drvnum  db      80h                     ; 24
        times   0x28 - ($ - $$) db 0
totsec  dd      0, 0                    ; 28
mftlcn  dd      0, 0                    ; 30
mirlcn  dd      0, 0                    ; 38
cprec   db      0F6h                    ; 40
        times   0x44 - ($ - $$) db 0
cpidx   db      1                       ; 44
        times   0x54 - ($ - $$) db 0

start:  cli
        xor     ax, ax
        mov     ss, ax
        mov     sp, 7C00h
        mov     ds, ax
        sti
        cld
        mov     ax, LSEG
        mov     es, ax
        mov     si, 7C00h
        xor     di, di
        mov     cx, 256
        rep     movsw
        mov     ds, ax
        mov     [drvnum], dl
        ; secteurs 1 a 15 en 9000:0200
        mov     eax, [hidden]
        inc     eax
        mov     [dap.lba], eax
        mov     word [dap.cnt], 15
        mov     word [dap.ofs], 200h
        mov     word [dap.seg], LSEG
        mov     si, dap
        mov     ah, 42h
        mov     dl, [drvnum]
        int     13h
        jc      diskerr0
        jmp     LSEG:main

diskerr0:
        mov     si, msgerr
fatal:  lodsb
        or      al, al
        jz      .halt
        mov     ah, 0Eh
        mov     bx, 7
        int     10h
        jmp     fatal
.halt:  hlt
        jmp     .halt

msgerr  db      'Erreur disque', 0
dap:    db      16, 0
.cnt:   dw      1
.ofs:   dw      0
.seg:   dw      0
.lba:   dd      0, 0

        times   510 - ($ - $$) db 0
        dw      0AA55h

; ------------------------------------------------------------------
; Secteurs 1 a 15
; ------------------------------------------------------------------

main:   mov     ax, LSEG
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        ; tailles : cluster, enregistrement, bloc d'index
        movzx   eax, byte [spc]
        shl     eax, 9
        mov     [cbytes], eax
        movsx   eax, byte [cprec]
        call    sizeof
        mov     [recsz], eax
        movsx   eax, byte [cpidx]
        call    sizeof
        mov     [idxsz], eax
        mov     eax, [cbytes]
        cmp     [idxsz], eax
        jae     .vu
        mov     eax, 512
.vu:    mov     [vcnsz], eax
        ; enregistrement 0 lu directement a mftlcn
        mov     eax, [mftlcn]
        mov     [MFTRUN], dword 0
        mov     [MFTRUN + 4], eax
        mov     [MFTRUN + 8], dword 0FFFFh
        mov     [mftn], word 1
        xor     eax, eax
        call    readrec
        mov     eax, 80h
        call    findattr                ; SI = attribut $DATA sans nom
        jc      nofile
        mov     di, MFTRUN
        call    decruns
        mov     [mftn], cx
        ; racine
        mov     eax, 5
        call    readrec
        ; runs de $INDEX_ALLOCATION (s'il existe)
        mov     word [wrkn], 0
        mov     eax, 0A0h
        call    findattr
        jc      .noia
        mov     di, WRKRUN
        call    decruns
        mov     [wrkn], cx
.noia:  mov     word [qhead], 0
        mov     word [qtail], 0
        mov     eax, 90h
        call    findattr
        jc      nofile
        mov     bx, si
        add     bx, [si + 14h]          ; valeur de $INDEX_ROOT
        add     bx, 10h                 ; en-tete d'index
        call    scannode
        jnc     found
nextq:  mov     bx, [qhead]
        cmp     bx, [qtail]
        jae     nofile
        add     word [qhead], 4
        mov     eax, [QUEUE + bx]
        mul     dword [vcnsz]           ; octet dans $INDEX_ALLOCATION
        mov     ecx, [idxsz]
        mov     di, IDXBUF
        mov     si, WRKRUN
        mov     dx, [wrkn]
        call    readstream
        mov     si, IDXBUF
        mov     ecx, [idxsz]
        call    unfix
        mov     bx, IDXBUF + 18h
        call    scannode
        jc      nextq

; EAX = numero de l'enregistrement d'IO.SYS
found:  call    readrec
        mov     eax, 80h
        call    findattr
        jc      nofile
        cmp     byte [si + 8], 0
        je      nofile                  ; donnees residentes : non prevu
        mov     eax, [si + 30h]         ; taille
        mov     [fsize], eax
        mov     di, WRKRUN
        call    decruns
        mov     [wrkn], cx
        ; lecture cluster par cluster en 07C0:0000
        mov     word [dst], 07C0h
        xor     ebx, ebx                ; VCN
.ld:    mov     eax, ebx
        mul     dword [cbytes]
        cmp     eax, [fsize]
        jae     .done
        mov     eax, ebx
        mov     si, WRKRUN
        mov     dx, [wrkn]
        call    vcnlcn
        jc      nofile
        movzx   ecx, byte [spc]
        mul     ecx
        add     eax, [hidden]
        mov     [dap.lba], eax
        mov     [dap.cnt], cx
        mov     word [dap.ofs], 0
        mov     ax, [dst]
        mov     [dap.seg], ax
        call    rdsec
        movzx   ax, byte [spc]
        shl     ax, 5
        add     [dst], ax
        inc     ebx
        jmp     .ld
.done:  xor     ax, ax
        mov     es, ax
        mov     dword [es:7C00h + 16], 0 ; taille : ne rien relire
        mov     dl, [drvnum]
        jmp     07C0h:0000h

nofile: mov     si, msgnofile
        jmp     fatal

; EAX = valeur de BPB (clusters, ou -n : 2^n octets) -> EAX octets
sizeof: or      eax, eax
        js      .neg
        mul     dword [cbytes]
        ret
.neg:   neg     eax
        mov     cl, al
        mov     eax, 1
        shl     eax, cl
        ret

; lire DAP (secteurs) ; arrete en cas d'erreur
rdsec:  pushad
        mov     si, dap
        mov     ah, 42h
        mov     dl, [drvnum]
        int     13h
        popad
        jc      diskerr0
        ret

; SI = runs (12 octets), DX = nombre, EAX = VCN -> EAX = LCN (CF erreur)
vcnlcn: push    si
        push    dx
.l:     or      dx, dx
        jz      .no
        cmp     eax, [si]
        jb      .nx
        mov     ecx, [si]
        add     ecx, [si + 8]
        cmp     eax, ecx
        jae     .nx
        sub     eax, [si]
        add     eax, [si + 4]
        pop     dx
        pop     si
        clc
        ret
.nx:    add     si, 12
        dec     dx
        jmp     .l
.no:    pop     dx
        pop     si
        stc
        ret

; lire ECX octets a l'octet EAX d'un flux (runs SI, DX) en DS:DI
; (par secteurs de 512 octets)
readstream:
        mov     [rsoff], eax
        mov     [rslen], ecx
        mov     [rsrun], si
        mov     [rsn], dx
        mov     [rsdst], di
.l:     cmp     dword [rslen], 0
        je      .ok
        mov     eax, [rsoff]
        xor     edx, edx
        div     dword [cbytes]          ; EAX = VCN, EDX = octet
        shr     edx, 9
        mov     [rssec], edx            ; secteur dans le cluster
        mov     si, [rsrun]
        mov     dx, [rsn]
        call    vcnlcn
        jc      nofile
        movzx   ecx, byte [spc]
        mul     ecx
        add     eax, [rssec]
        add     eax, [hidden]
        mov     [dap.lba], eax
        mov     word [dap.cnt], 1
        mov     ax, [rsdst]
        mov     [dap.ofs], ax
        mov     word [dap.seg], LSEG
        call    rdsec
        add     word [rsdst], 512
        add     dword [rsoff], 512
        sub     dword [rslen], 512
        ja      .l
.ok:    ret

; correctifs : SI = tampon, ECX = taille
unfix:  mov     bx, [si + 4]
        add     bx, si                  ; tableau
        mov     dx, [bx]                ; numero de sequence
        mov     di, si
        add     di, 510
        mov     cx, [si + 6]
        dec     cx
.l:     or      cx, cx
        jz      .ok
        add     bx, 2
        mov     ax, [bx]
        mov     [di], ax
        add     di, 512
        dec     cx
        jmp     .l
.ok:    ret

; lire l'enregistrement EAX de la MFT en RECBUF
readrec:
        mul     dword [recsz]
        mov     ecx, [recsz]
        mov     di, RECBUF
        mov     si, MFTRUN
        mov     dx, [mftn]
        call    readstream
        mov     si, RECBUF
        call    unfix
        ret

; attribut de type EAX sans nom ou nomme $I30 dans RECBUF -> SI (CF absent)
findattr:
        mov     si, RECBUF
        add     si, [RECBUF + 14h]
.l:     mov     ecx, [si]
        cmp     ecx, 0FFFFFFFFh
        je      .no
        cmp     ecx, eax
        jne     .nx
        cmp     byte [si + 9], 0
        je      .ok
        cmp     byte [si + 9], 4        ; $I30
        je      .ok
.nx:    add     si, [si + 4]
        jmp     .l
.ok:    clc
        ret
.no:    stc
        ret

; decoder les runs de l'attribut SI en DI ; CX = nombre de runs
decruns:
        push    si
        mov     bx, si
        add     si, [si + 20h]
        xor     ebp, ebp                ; VCN
        xor     edx, edx                ; LCN
        xor     cx, cx
.l:     mov     al, [si]
        or      al, al
        jz      .ok
        inc     si
        mov     ah, al
        and     al, 0Fh                 ; octets de longueur
        shr     ah, 4                   ; octets de decalage
        push    ax
        movzx   cx, al
        call    getnum                  ; EAX = longueur
        mov     [di], ebp
        mov     [di + 8], eax
        add     ebp, eax
        pop     ax
        movzx   cx, ah
        or      cx, cx
        jz      .sparse
        call    getnum                  ; CX = octets du decalage
        ; extension de signe
        cmp     cx, 4
        jae     .add
        shl     cl, 3
        push    ebx
        mov     ebx, eax
        mov     al, 32
        sub     al, cl
        mov     cl, al
        shl     ebx, cl
        sar     ebx, cl
        mov     eax, ebx
        pop     ebx
.add:   add     edx, eax
        mov     [di + 4], edx
        jmp     .nx
.sparse:
        mov     dword [di + 4], 0FFFFFFFFh
.nx:    add     di, 12
        inc     word [nruns]
        mov     cx, [nruns]
        jmp     .l
.ok:    mov     cx, [nruns]
        mov     word [nruns], 0
        pop     si
        ret

; lire CX octets (petit-boutiste) en SI -> EAX ; SI avance
getnum: xor     eax, eax
        push    cx
        add     si, cx
.l:     or      cx, cx
        jz      .ok
        dec     si
        shl     eax, 8
        mov     al, [si]
        dec     cx
        jmp     .l
.ok:    pop     cx
        add     si, cx
        ret

; entrees d'un noeud (BX = en-tete d'index) : IO.SYS -> EAX, CF = 0 ;
; sinon les VCN des sous-noeuds sont ajoutes a la file, CF = 1
scannode:
        mov     si, bx
        add     si, [bx]                ; premiere entree
.l:     test    byte [si + 12], 1
        jz      .nosub
        mov     di, si
        add     di, [si + 8]
        mov     eax, [di - 8]
        mov     di, [qtail]
        cmp     di, 1000h - 4
        jae     .nosub
        mov     [QUEUE + di], eax
        add     word [qtail], 4
.nosub: test    byte [si + 12], 2
        jnz     .no
        cmp     byte [si + 16 + 40h], 6 ; longueur du nom
        jne     .nx
        push    si
        lea     di, [si + 16 + 42h]
        mov     bx, ioname
        mov     cx, 6
.c:     mov     ax, [di]
        cmp     ax, 'a'
        jb      .u
        cmp     ax, 'z'
        ja      .u
        sub     ax, 32
.u:     cmp     al, [bx]
        jne     .ne
        or      ah, ah
        jnz     .ne
        add     di, 2
        inc     bx
        loop    .c
        pop     si
        mov     eax, [si]               ; reference (48 bits bas)
        clc
        ret
.ne:    pop     si
.nx:    add     si, [si + 8]
        jmp     .l
.no:    stc
        ret

ioname  db      'IO.SYS'
msgnofile db    'IO.SYS absent', 0
cbytes  dd      0
recsz   dd      0
idxsz   dd      0
vcnsz   dd      0
fsize   dd      0
mftn    dw      0
wrkn    dw      0
nruns   dw      0
qhead   dw      0
qtail   dw      0
dst     dw      0
rsoff   dd      0
rslen   dd      0
rsrun   dw      0
rsn     dw      0
rsdst   dw      0
rssec   dd      0

        times   8192 - ($ - $$) db 0
