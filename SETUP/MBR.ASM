; MBR.ASM - Secteur de partition (MBR) de Pasdows 95
;
; Ecrit par INSTALL.PAS dans le premier secteur du disque dur (octets
; 0 a 439 ; la signature du disque, la table des partitions et 55AAh
; sont ajoutees par le programme d'installation).
;
; Le BIOS charge ce secteur en 0000:7C00. Il se recopie en 0000:0600,
; cherche la partition active, en lit le premier secteur en 0000:7C00
; (INT 13h etendue, sinon CHS) et lui passe la main avec DL = unite et
; DS:SI = entree de la partition, comme le MBR de MS-DOS.
;
; Assemblage : nasm -f bin MBR.ASM -o MBR.BIN

        bits    16
        org     0600h

start:  cli
        xor     ax, ax
        mov     ss, ax
        mov     sp, 7C00h
        mov     ds, ax
        mov     es, ax
        sti
        cld
        mov     si, 7C00h
        mov     di, 0600h
        mov     cx, 256
        rep     movsw
        jmp     0:main

main:   mov     [drive], dl
        mov     si, 07BEh               ; table des partitions
        mov     cx, 4
.find:  test    byte [si], 80h
        jnz     found
        add     si, 16
        loop    .find
        mov     si, msgnopart
        jmp     fatal

found:  mov     [part], si
        mov     ah, 41h                 ; extensions INT 13h ?
        mov     bx, 55AAh
        mov     dl, [drive]
        int     13h
        jc      chs
        cmp     bx, 0AA55h
        jne     chs
        mov     si, [part]
        mov     ax, [si + 8]
        mov     [dap.lba], ax
        mov     ax, [si + 10]
        mov     [dap.lba + 2], ax
        mov     si, dap
        mov     ah, 42h
        mov     dl, [drive]
        int     13h
        jnc     check
chs:    mov     si, [part]
        mov     dh, [si + 1]
        mov     cx, [si + 2]
        mov     bx, 7C00h
        mov     ax, 0201h
        mov     dl, [drive]
        int     13h
        jnc     check
        mov     si, msgerr
        jmp     fatal

check:  cmp     word [7DFEh], 0AA55h
        mov     si, msgnosys
        jne     fatal
        mov     si, [part]
        mov     dl, [drive]
        jmp     0:7C00h

fatal:  lodsb
        or      al, al
        jz      .halt
        mov     ah, 0Eh
        mov     bx, 7
        int     10h
        jmp     fatal
.halt:  hlt
        jmp     .halt

drive   db      80h
part    dw      0
dap:    db      16, 0
        dw      1                       ; un secteur
        dw      7C00h, 0                ; vers 0000:7C00
.lba:   dd      0, 0
msgnopart db    'Pasdows : aucune partition active', 0
msgerr  db      'Pasdows : erreur de lecture du disque', 0
msgnosys db     'Pasdows : partition non amorcable', 0

        times   440 - ($ - $$) db 0
