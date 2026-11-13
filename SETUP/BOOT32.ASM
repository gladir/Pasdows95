; BOOT32.ASM - Secteur d'amorce FAT32 de Pasdows 95
;
; Ecrit par INSTALL.PAS dans le premier secteur de la partition (et
; dans sa copie, secteur 6). Les octets 3 a 89 (BPB FAT32) sont
; remplaces par ceux du volume formate ; seul le code est repris d'ici.
;
; Le MBR charge ce secteur en 0000:7C00. Il se recopie en 0000:0600,
; cherche IO.SYS dans le repertoire racine, charge le fichier entier
; en 07C0:0000 en suivant la chaine de la FAT, puis lui passe la main
; avec DL = unite. IO.SYS commence par l'amorce El Torito ajoutee par
; WPC -CW95IO, qui relit le reste du fichier depuis le CD-ROM d'apres
; la table d'information d'amorce (+16 : taille) : la taille est mise
; a 0 pour qu'elle ne relise rien, le fichier etant deja en memoire.
;
; Assemblage : nasm -f bin BOOT32.ASM -o BOOT32.BIN

        bits    16
        org     0600h

        jmp     short start
        nop
        db      'PASDOWS '              ; 03 : OEM
bps     dw      512                     ; 0B
spc     db      1                       ; 0D
rsvd    dw      32                      ; 0E
nfats   db      2                       ; 10
        dw      0, 0                    ; 11 : racine, secteurs (16)
        db      0F8h                    ; 15
        dw      0, 63, 255              ; 16 : FAT16, secteurs, tetes
hidden  dd      0                       ; 1C
        dd      0                       ; 20 : secteurs (32)
fatsz   dd      0                       ; 24
        dw      0, 0                    ; 28 : drapeaux, version
rootcl  dd      2                       ; 2C
        dw      1, 6                    ; 30 : FSInfo, copie
        times   12 db 0                 ; 34
drvnum  db      80h                     ; 40
        db      0, 29h                  ; 41
        dd      0                       ; 43 : numero de serie
        db      'PASDOWS95  '           ; 47
        db      'FAT32   '              ; 52

start:  cli                             ; 5A
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
.nf:    add     eax, [fatsz]
        loop    .nf
        mov     [datlba], eax
        ; repertoire racine : chercher IO      SYS
        mov     eax, [rootcl]
dirclu: mov     [cur], eax
        call    clulba
        movzx   cx, byte [spc]
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
        mov     eax, [cur]
        call    nextcl
        cmp     eax, 0FFFFFF8h
        jb      dirclu
nofile: mov     si, msgnofile
        jmp     fatal

found:  mov     ax, [di + 20]
        shl     eax, 16
        mov     ax, [di + 26]
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
        cmp     eax, 0FFFFFF8h
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

; EAX = grappe -> EAX = grappe suivante (FAT)
nextcl: shl     eax, 2
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
        mov     eax, [bx + 0A00h]
        and     eax, 0FFFFFFFh
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

        times   510 - ($ - $$) db 0
        dw      0AA55h
