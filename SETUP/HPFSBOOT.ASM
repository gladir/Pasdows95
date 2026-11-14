; HPFSBOOT.ASM - Chargeur d'amorce HPFS de Pasdows 95 (8 Ko)
;
; Ecrit par INSTALL.PAS dans les 16 premiers secteurs d'une partition
; HPFS (type 07h), la zone d'amorce que le format HPFS reserve avant le
; superbloc (secteur 16) ; les octets 3 a 61 du secteur 0 (BPB, nom du
; volume, "HPFS    ") sont ceux du volume formate. Le secteur 0 se
; recopie en 9000:0000, y lit les secteurs 1 a 15 puis continue :
;   - superbloc (secteur 16) : fnode de la racine ;
;   - fnode de la racine : son dnode racine ;
;   - descente dans l'arbre B des dnodes (entrees triees sans tenir
;     compte de la casse) jusqu'a l'entree IO.SYS ;
;   - fnode d'IO.SYS : son arbre B+ d'allocation (extensions dans le
;     fnode, ou anodes a plusieurs niveaux) ; chaque extension est lue a
;     sa place dans le fichier en 07C0:0000 ;
;   - comme BOOT32.ASM : taille de la table d'information d'amorce
;     d'IO.SYS mise a 0, saut en 07C0:0000 avec DL = unite.
;
; Assemblage : nasm -f bin HPFSBOOT.ASM -o HPFSBOOT.BIN

        bits    16
        org     0

LSEG    equ     9000h                   ; chargeur
SBBUF   equ     2000h                   ; superbloc, puis fnodes
DNBUF   equ     2800h                   ; dnode (2 Ko)
ANBUF   equ     3000h                   ; anodes (512 octets par niveau)

        jmp     short start
        nop
        db      'PASDOWS '              ; 03
bps     dw      512                     ; 0B
spc     db      1                       ; 0D
        times   0x1C - ($ - $$) db 0
hidden  dd      0                       ; 1C
        times   0x24 - ($ - $$) db 0
drvnum  db      80h                     ; 24
        times   0x36 - ($ - $$) db 0
        db      'HPFS    '              ; 36
        times   0x3E - ($ - $$) db 0

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
        ; superbloc : fnode de la racine
        mov     eax, 16
        mov     cx, 1
        mov     di, SBBUF
        call    rdvol
        cmp     dword [SBBUF], 0F995E849h
        jne     nofile
        mov     eax, [SBBUF + 12]
        call    rdfnode
        test    byte [SBBUF + 55], 1    ; repertoire
        jz      nofile
        mov     eax, [SBBUF + 72]       ; dnode racine
        mov     byte [depth], 0

; descente dans l'arbre B : EAX = dnode
nextdn: inc     byte [depth]
        cmp     byte [depth], 32
        ja      nofile
        mov     cx, 4
        mov     di, DNBUF
        call    rdvol
        cmp     dword [DNBUF], 77E40AAEh
        jne     nofile
        mov     si, DNBUF + 20
.ent:   mov     ax, [si]                ; longueur
        cmp     ax, 32
        jb      nofile
        mov     bl, [si + 2]            ; indicateurs
        test    bl, 8                   ; entree finale
        jnz     .down
        test    bl, 1                   ; ^A^A
        jnz     .nx
        call    cmpname                 ; AL < 0, = 0, > 0 (cle - entree)
        or      al, al
        jz      found
        js      .down
.nx:    add     si, [si]
        jmp     .ent
.down:  test    byte [si + 2], 4
        jz      nofile
        mov     bx, si
        add     bx, [si]
        mov     eax, [bx - 4]
        jmp     nextdn

; IO.SYS : fnode, taille, extensions
found:  mov     eax, [si + 4]
        call    rdfnode
        mov     eax, [SBBUF + 160]      ; taille
        add     eax, 511
        shr     eax, 9
        mov     [nsec], eax
        mov     bx, SBBUF + 56          ; en-tete de l'arbre B+
        xor     bp, bp                  ; niveau
        call    tree
        xor     ax, ax
        mov     es, ax
        mov     dword [es:7C00h + 16], 0 ; taille : ne rien relire
        mov     dl, [drvnum]
        jmp     07C0h:0000h

nofile: mov     si, msgnofile
        jmp     fatal

; arbre B+ d'en-tete BX (niveau BP) : lire les extensions du fichier
tree:   movzx   cx, byte [bx + 5]       ; noeuds utilises
        test    byte [bx], 80h
        jnz     .int
        lea     si, [bx + 8]
.leaf:  jcxz    .ret
        push    cx
        push    si
        call    extent
        pop     si
        pop     cx
        add     si, 12
        dec     cx
        jmp     .leaf
.int:   cmp     bp, 6
        jae     nofile
        lea     si, [bx + 8]
.il:    jcxz    .ret
        push    cx
        push    si
        push    bx
        mov     eax, [si + 4]           ; anode
        mov     di, bp
        shl     di, 9
        add     di, ANBUF
        push    di
        mov     cx, 1
        call    rdvol
        pop     di
        cmp     dword [di], 37E40AAEh
        jne     nofile
        lea     bx, [di + 12]
        inc     bp
        call    tree
        dec     bp
        pop     bx
        pop     si
        pop     cx
        add     si, 8
        dec     cx
        jmp     .il
.ret:   ret

; extension SI : secteur du fichier, longueur, secteur du volume ;
; lue en 07C0:0000 + secteur * 512, sans depasser la taille
extent: mov     eax, [si]               ; secteur du fichier
        mov     ecx, [si + 4]           ; longueur
        mov     edx, [si + 8]           ; secteur du volume
.l:     or      ecx, ecx
        jz      .ret
        cmp     eax, [nsec]
        jae     .ret
        mov     ebx, [nsec]
        sub     ebx, eax                ; secteurs encore utiles
        cmp     ebx, ecx
        jbe     .c1
        mov     ebx, ecx
.c1:    cmp     ebx, 64
        jbe     .c2
        mov     ebx, 64
.c2:    push    eax
        push    ecx
        push    edx
        push    ebx
        mov     edi, eax
        shl     edi, 5                  ; paragraphes
        add     edi, 07C0h
        mov     [dap.seg], di
        mov     word [dap.ofs], 0
        mov     [dap.cnt], bx
        mov     eax, edx
        add     eax, [hidden]
        mov     [dap.lba], eax
        call    rdsec
        pop     ebx
        pop     edx
        pop     ecx
        pop     eax
        add     eax, ebx
        add     edx, ebx
        sub     ecx, ebx
        jmp     .l
.ret:   ret

; fnode EAX en SBBUF (signature verifiee)
rdfnode:
        mov     cx, 1
        mov     di, SBBUF
        call    rdvol
        cmp     dword [SBBUF], 0F7E40AAEh
        jne     nofile
        ret

; lire CX secteurs du volume a partir de EAX en DS:DI
rdvol:  add     eax, [hidden]
        mov     [dap.lba], eax
        mov     [dap.cnt], cx
        mov     [dap.ofs], di
        mov     word [dap.seg], LSEG
        ; (repli)

; lire DAP ; arrete en cas d'erreur
rdsec:  pushad
        mov     si, dap
        mov     ah, 42h
        mov     dl, [drvnum]
        int     13h
        popad
        jc      diskerr0
        ret

; comparer 'IO.SYS' au nom de l'entree SI (sans tenir compte de la casse)
; -> AL = -1 si la cle precede, 0 si egale, 1 si elle suit
cmpname:
        push    si
        push    bx
        movzx   cx, byte [si + 30]      ; longueur du nom
        lea     di, [si + 31]
        mov     bx, ioname
        mov     dx, 6                   ; longueur de la cle
.l:     or      dx, dx
        jz      .kend
        jcxz    .after                  ; nom plus court : la cle suit
        mov     al, [di]
        cmp     al, 'a'
        jb      .u
        cmp     al, 'z'
        ja      .u
        sub     al, 32
.u:     cmp     [bx], al
        jb      .before
        ja      .after
        inc     di
        inc     bx
        dec     cx
        dec     dx
        jmp     .l
.kend:  jcxz    .equal
.before:
        mov     al, -1
        jmp     .ret
.after: mov     al, 1
        jmp     .ret
.equal: xor     al, al
.ret:   pop     bx
        pop     si
        ret

ioname  db      'IO.SYS'
msgnofile db    'IO.SYS absent', 0
nsec    dd      0
depth   db      0

        times   8192 - ($ - $$) db 0
