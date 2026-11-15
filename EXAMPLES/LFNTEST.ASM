; LFNTEST.COM : essai des noms longs de Windows 95 (INT 21h AX=71xxh)
; en mode reel (machine virtuelle 8086) puis en mode protege (DPMI 16 bits)
; nasm -f bin -o LFNTEST.COM LFNTEST.ASM
        org 100h
        cpu 386

start:  mov [fails], word 0
        mov ah, 3Ch
        xor cx, cx
        mov dx, logname
        int 21h
        jc .nolog
        mov [logh], ax
.nolog:
        mov si, mTitle
        call puts
        call tests
        ; ---- meme chose en mode protege (client DPMI 16 bits)
        mov ax, 1687h
        int 2Fh
        or ax, ax
        jnz nodpmi
        mov [dpEntry], di
        mov [dpEntry+2], es
        ; zone du serveur DPMI apres le programme
        mov ax, cs
        add ax, 1000h
        mov es, ax
        xor ax, ax                      ; client 16 bits
        call far [dpEntry]
        jc nodpmi
        mov byte [pm], 1
        mov si, mPm
        call puts
        call tests
        jmp fin
nodpmi: mov si, mNoDpmi
        call puts
fin:    mov si, mEnd
        call puts
        mov ax, [fails]
        call hex4
        call crlf
        mov bx, [logh]
        mov ah, 3Eh
        int 21h
        mov ax, 4C00h
        int 21h

; ------------------------------------------------------------------
tests:
        ; volume
        mov ax, 71A0h
        mov dx, root
        push ds
        pop es
        mov di, buf
        mov cx, 32
        stc
        int 21h
        mov si, tVol
        call check
        jc .novol
        push bx
        mov si, buf
        call puts
        mov si, mFlags
        call puts
        pop ax
        call hex4
        mov si, mMax
        call puts
        mov ax, cx
        call hex4
        call crlf
.novol:
        ; creer le repertoire au nom long et y entrer
        mov ax, 7139h
        mov dx, dname
        stc
        int 21h
        jnc .mk
        cmp ax, 5                       ; existe deja (mode protege)
        je .mk
        cmp ax, 80
        je .mk
        stc
.mk:    mov si, tMkdir
        call check
        mov ax, 713Bh
        mov dx, dname
        stc
        int 21h
        mov si, tChdir
        call check
        ; repertoire courant (nom long)
        mov ax, 7147h
        xor dl, dl
        mov si, buf
        stc
        int 21h
        mov si, tGetDir
        call check
        mov si, buf
        call puts
        call crlf
        ; creer un fichier au nom long
        mov ax, 716Ch
        mov bx, 2
        xor cx, cx
        mov dx, 12h                     ; creer ou tronquer
        mov si, fname
        stc
        int 21h
        mov si, tCreate
        call check
        jc .nocreate
        mov bx, ax
        mov [hnd], ax
        mov ah, 40h
        mov cx, txtLen
        mov dx, txt
        int 21h
        ; informations par poignee
        mov ax, 71A6h
        mov bx, [hnd]
        mov dx, info
        stc
        int 21h
        mov si, tInfo
        call check
        mov ax, [info+36]
        cmp ax, txtLen
        je .szok
        mov si, tSize
        stc
        call check
.szok:  mov ah, 3Eh
        mov bx, [hnd]
        int 21h
.nocreate:
        ; chemin court puis long
        mov ax, 7160h
        mov cx, 1
        mov si, fname
        push ds
        pop es
        mov di, buf
        stc
        int 21h
        mov si, tShort
        call check
        mov si, buf
        call puts
        call crlf
        mov ax, 7160h
        mov cx, 2
        mov si, buf
        mov di, buf2
        stc
        int 21h
        mov si, tLong
        call check
        mov si, buf2
        call puts
        call crlf
        ; ouvrir par le nom court avec la fonction DOS 3Dh
        mov ax, 3D00h
        mov dx, buf
        int 21h
        mov si, tOpen83
        call check
        jc .no83
        mov bx, ax
        mov ah, 3Eh
        int 21h
.no83:
        ; attributs et date
        mov ax, 7143h
        xor bl, bl
        mov dx, fname
        stc
        int 21h
        mov si, tAttr
        call check
        mov ax, 7143h
        mov bl, 4
        mov dx, fname
        stc
        int 21h
        mov si, tTime
        call check
        ; nom court genere
        mov ax, 71A8h
        mov si, fname
        mov di, buf
        mov dx, 0100h                   ; DH=1 : format 8.3
        stc
        int 21h
        mov si, tGen
        call check
        mov si, buf
        call puts
        call crlf
        ; renommer
        mov ax, 7156h
        mov dx, fname
        mov di, fname2
        stc
        int 21h
        mov si, tRen
        call check
        ; liste du repertoire
        mov ax, 714Eh
        mov cx, 0010h                   ; repertoires permis
        mov dx, star
        mov di, fd
        mov si, 1                       ; dates du DOS
        stc
        int 21h
        mov si, tFind
        call check
        jc .nofind
        mov [hnd], ax
.flp:   mov si, mItem
        call puts
        mov si, fd+44
        call puts
        cmp byte [fd+304], 0
        je .noalt
        mov si, mAlt
        call puts
        mov si, fd+304
        call puts
        mov al, ')'
        call putc
.noalt: call crlf
        mov ax, 714Fh
        mov bx, [hnd]
        mov di, fd
        mov si, 1
        int 21h
        jnc .flp
        mov ax, 71A1h
        mov bx, [hnd]
        stc
        int 21h
        mov si, tFClose
        call check
.nofind:
        ; supprimer, sortir, supprimer le repertoire
        mov ax, 7141h
        mov dx, fname2
        xor si, si
        stc
        int 21h
        mov si, tDel
        call check
        mov ax, 713Bh
        mov dx, up
        stc
        int 21h
        mov si, tUp
        call check
        mov ax, 713Ah
        mov dx, dname
        stc
        int 21h
        mov si, tRmdir
        call check
        ; fonction inconnue : AX=7100h, CF=1
        mov ax, 71FFh
        clc
        int 21h
        jnc .bad
        cmp ax, 7100h
        jne .bad
        clc
        jmp .unk
.bad:   stc
.unk:   mov si, tUnk
        call check
        ret

; ------------------------------------------------------------------
; check : SI = libelle ; CF = echec
check:  pushf
        push ax
        push si
        call puts
        pop si
        pop ax
        popf
        jc .ko
        push ax
        push si
        mov si, mOk
        call puts
        pop si
        pop ax
        clc
        ret
.ko:    push ax
        mov si, mKo
        call puts
        pop ax
        push ax
        call hex4
        call crlf
        pop ax
        inc word [fails]
        stc
        ret

puts:   lodsb
        or al, al
        jz .e
        call putc
        jmp puts
.e:     ret

putc:   push ax
        push bx
        push cx
        push dx
        mov dl, al
        mov [chbuf], al
        mov ah, 2
        int 21h
        mov bx, [logh]
        or bx, bx
        jz .nl
        mov ah, 40h
        mov cx, 1
        mov dx, chbuf
        int 21h
.nl:    pop dx
        pop cx
        pop bx
        pop ax
        ret

crlf:   mov al, 13
        call putc
        mov al, 10
        jmp putc

hex4:   push ax
        mov al, ah
        call hex2
        pop ax
hex2:   push ax
        shr al, 4
        call hex1
        pop ax
hex1:   and al, 15
        add al, '0'
        cmp al, '9'
        jbe .p
        add al, 7
.p:     jmp putc

mTitle  db 'LFNTEST : noms longs (INT 21h AX=71xxh)', 13, 10, 0
mPm     db 13, 10, '--- mode protege (DPMI) ---', 13, 10, 0
mNoDpmi db 'Pas de DPMI', 13, 10, 0
mEnd    db 'LFNTEST : echecs = ', 0
mOk     db ' : OK', 13, 10, 0
mKo     db ' : ECHEC ', 0
mFlags  db ' indicateurs ', 0
mMax    db ' nom max ', 0
mItem   db '  ', 0
mAlt    db '  (', 0
tVol    db '71A0 volume ', 0
tMkdir  db '7139 mkdir', 0
tChdir  db '713B chdir', 0
tGetDir db '7147 repertoire courant', 0
tCreate db '716C creer', 0
tInfo   db '71A6 infos par poignee', 0
tSize   db '71A6 taille', 0
tShort  db '7160 chemin court', 0
tLong   db '7160 chemin long', 0
tOpen83 db '3D00 ouverture par le nom court', 0
tAttr   db '7143 attributs', 0
tTime   db '7143 date', 0
tGen    db '71A8 nom court genere', 0
tRen    db '7156 renommer', 0
tFind   db '714E/714F recherche', 0
tFClose db '71A1 fin de recherche', 0
tDel    db '7141 supprimer', 0
tUp     db '713B ..', 0
tRmdir  db '713A rmdir', 0
tUnk    db '71FF inconnue -> 7100h', 0
root    db 'C:\', 0
dname   db 'C:\Dossier de test aux noms longs', 0
fname   db 'Un fichier au nom tres long.txt', 0
fname2  db 'Nom long renomme par LFNTEST.txt', 0
star    db '*', 0
up      db '..', 0
txt     db 'Bonjour des noms longs', 13, 10
txtLen  equ $ - txt
pm      db 0
logname db 'C:\LFNTEST.LOG', 0
logh    dw 0
chbuf   db 0
fails   dw 0
hnd     dw 0
dpEntry dd 0
info    times 52 db 0
buf     times 300 db 0
buf2    times 300 db 0
fd      times 320 db 0
