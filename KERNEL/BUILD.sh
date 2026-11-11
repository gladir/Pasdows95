#!/bin/bash
# BUILD.sh - Construit Pasdows 95 et le CD-ROM amorcable IMAGE/PASDOWS.ISO
#
#  1. compile les outils avec Free Pascal : TOOLS/WPC.PAS (Windows 95
#     Pascal Compiler) et TOOLS/MAKEISO.PAS ;
#  2. compile le noyau avec WPC :
#        WPC -CW95IO IO.PAS IO.SYS   (IO.SYS amorcable, El Torito)
#  3. fabrique le CD-ROM : MAKEISO PASDOWS.ISO /BOOT:IO.SYS ... avec les
#     fichiers de IMAGE/CDROM (AUTOEXEC.BAT, CONFIG.SYS, MSDOS.SYS,
#     LISEZMOI.TXT) ;
#  4. recopie IO.SYS dans IMAGE/CDROM.
#
# Variables : FPC (compilateur Free Pascal, defaut fpc), W (dossier de
# travail, defaut BUILD a la racine du depot).
# Test : qemu-system-i386 -m 32 -cdrom IMAGE/PASDOWS.ISO -boot d
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
FPC=${FPC:-fpc}
W=${W:-$ROOT/BUILD}
mkdir -p "$W/obj" "$W/cd"

echo "== Outils (Free Pascal)"
"$FPC" -O1 -FU"$W/obj" -o"$W/wpc" "$ROOT/TOOLS/WPC.PAS" > "$W/wpc.log" || { cat "$W/wpc.log"; exit 1; }
"$FPC" -FU"$W/obj" -o"$W/makeiso" "$ROOT/TOOLS/MAKEISO.PAS" > "$W/makeiso.log" || { cat "$W/makeiso.log"; exit 1; }

echo "== Noyau IO.SYS (WPC -CW95IO)"
rm -f "$W"/cd/*
"$W/wpc" -CW95IO "$HERE/IO.PAS" "$W/cd/IO.SYS"

echo "== CD-ROM amorcable"
for F in AUTOEXEC.BAT CONFIG.SYS MSDOS.SYS LISEZMOI.TXT; do
  cp "$ROOT/IMAGE/CDROM/$F" "$W/cd/$F"
done
"$W/makeiso" "$ROOT/IMAGE/PASDOWS.ISO" /BOOT:"$W/cd/IO.SYS" /LABEL:PASDOWS95 "$W/cd/*"
cp "$W/cd/IO.SYS" "$ROOT/IMAGE/CDROM/IO.SYS"
echo "Termine : $ROOT/IMAGE/PASDOWS.ISO"
