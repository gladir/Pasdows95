; BOOT16.ASM - Secteur d'amorce FAT16 de Pasdows 95
;
; Ecrit par INSTALL.PAS dans le premier secteur d'une partition FAT16
; (type 0Eh). Les octets 3 a 61 (BPB FAT16) sont remplaces par ceux du
; volume formate ; seul le code est repris d'ici (octets 62 a 509).
;
; Meme principe que BOOT32.ASM : recopie en 0000:0600, recherche
; d'IO.SYS dans le repertoire racine (zone fixe apres les FAT),
; chargement du fichier entier en 07C0:0000 en suivant la FAT 16 bits,
; taille de la table d'information d'amorce mise a 0, saut avec DL.
;
; Assemblage : nasm -f bin BOOT16.ASM -o BOOT16.BIN

        bits    16
        org     0600h

        jmp     short start
        nop
        db      'PASDOWS '              ; 03 : OEM
bps     dw      512                     ; 0B
spc     db      4                       ; 0D
rsvd    dw      1                       ; 0E
nfats   db      2                       ; 10
rootent dw      512                     ; 11
        dw      0                       ; 13 : secteurs (16)
        db      0F8h                    ; 15
fatsz   dw      0                       ; 16
        dw      63, 255                 ; 18 : secteurs, tetes
hidden  dd      0                       ; 1C
        dd      0                       ; 20 : secteurs (32)
drvnum  db      80h                     ; 24
        db      0, 29h                  ; 25
        dd      0                       ; 27 : numero de serie
        db      'PASDOWS95  '           ; 2B
        db      'FAT16   '              ; 36

start:  cli                             ; 3E
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 7C00h
        sti
        cld
        mov     si, 7C00h
        mov     di, 0600h
        mov     cx, 256
        rep     movsw
        jmp     0:main

main:   mov     [drvnum], dl
        movzx   eax, word [rsvd]
        add     eax, [hidden]
        mov     [fatlba], eax
        movzx   cx, byte [nfats]
        movzx   ebx, word [fatsz]
.nf:    add     eax, ebx
        loop    .nf
        mov     [rootlba], eax
        movzx   ecx, word [rootent]
        shr     ecx, 4                  ; 16 entrees par secteur
        mov     [rootsec], cx
        add     eax, ecx
        mov     [datlba], eax
        ; repertoire racine
        mov     eax, [rootlba]
        mov     cx, [rootsec]
dirsec: push    cx
        push    eax
        mov     bx, 0800h
        xor     dx, dx
        call    read1
        mov     di, 0800h
dirent: cmp     byte [di], 0
        je      nofile
        push    di
        mov     si, ioname
        mov     cx, 11
        repe    cmpsb
        pop     di
        je      found
        add     di, 32
        cmp     di, 0A00h
        jb      dirent
        pop     eax
        inc     eax
        pop     cx
        loop    dirsec
nofile: mov     si, msgnofile
        jmp     fatal

found:  movzx   eax, word [di + 26]
        mov     word [dseg], 07C0h
ldclu:  mov     [cur], eax
        call    clulba
        movzx   cx, byte [spc]
ldsec:  push    cx
        push    eax
        xor     bx, bx
        mov     dx, [dseg]
        call    read1
        add     word [dseg], 20h
        pop     eax
        inc     eax
        pop     cx
        loop    ldsec
        mov     eax, [cur]
        call    nextcl
        cmp     eax, 0FFF8h
        jb      ldclu
        xor     eax, eax
        mov     [7C00h + 16], eax       ; taille : ne rien relire
        mov     dl, [drvnum]
        jmp     07C0h:0000h

; EAX = grappe -> EAX = premier secteur
clulba: sub     eax, 2
        movzx   ecx, byte [spc]
        mul     ecx
        add     eax, [datlba]
        ret

; EAX = grappe -> EAX = grappe suivante (FAT 16 bits)
nextcl: shl     eax, 1
        movzx   ebx, ax
        and     bx, 511
        push    bx
        shr     eax, 9
        add     eax, [fatlba]
        cmp     eax, [fatsec]
        je      .have
        mov     [fatsec], eax
        mov     bx, 0A00h
        xor     dx, dx
        call    read1
.have:  pop     bx
        movzx   eax, word [bx + 0A00h]
        ret

; lire le secteur EAX en DX:BX
read1:  mov     [dap.lba], eax
        mov     [dap.ofs], bx
        mov     [dap.seg], dx
        mov     si, dap
        mov     ah, 42h
        mov     dl, [drvnum]
        int     13h
        jnc     .ok
        mov     si, msgerr
        jmp     fatal
.ok:    ret

fatal:  lodsb
        or      al, al
        jz      .halt
        mov     ah, 0Eh
        mov     bx, 7
        int     10h
        jmp     fatal
.halt:  hlt
        jmp     .halt

ioname  db      'IO      SYS'
msgnofile db    'IO.SYS absent', 0
msgerr  db      'Erreur disque', 0
dap:    db      16, 0
        dw      1
.ofs:   dw      0
.seg:   dw      0
.lba:   dd      0, 0
fatsec  dd      0FFFFFFFFh
; variables hors du secteur (0C00h)
fatlba  equ     0C00h
datlba  equ     0C04h
cur     equ     0C08h
dseg    equ     0C0Ch
rootlba equ     0C10h
rootsec equ     0C14h

        times   510 - ($ - $$) db 0
        dw      0AA55h
