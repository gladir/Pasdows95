#!/bin/bash
# BUILD.sh - Construit Pasdows 95 et le CD-ROM amorcable IMAGE/PASDOWS.ISO
#
#  1. compile les outils avec Free Pascal : TOOLS/WPC.PAS (Windows 95
#     Pascal Compiler) et TOOLS/MAKEISO.PAS ;
#  2. compile le systeme avec WPC :
#        WPC -CW95IO IO.PAS IO.SYS         (IO.SYS amorcable, El Torito)
#        WPC -CVMM32 VMM32.PAS VMM32.VXD   (noyau 32 bits et Win32)
#  3. compile les programmes systeme (SYSTEM/*.PAS, dont COMMAND.EXE,
#     l'interpreteur de commandes) et les exemples Win32 (EXAMPLES/*.PAS),
#     avec WPC -CW32 ;
#  4. fabrique le CD-ROM : MAKEISO PASDOWS.ISO /BOOT:IO.SYS ... avec tous
#     les fichiers de IMAGE/CDROM (AUTOEXEC.BAT, CONFIG.SYS, MSDOS.SYS,
#     LISEZMOI.TXT et les programmes Windows 95 qu'on y a deposes) ;
#  5. recopie IO.SYS, VMM32.VXD et les exemples dans IMAGE/CDROM.
#
# Variables : FPC (compilateur Free Pascal, defaut fpc), W (dossier de
# travail, defaut BUILD a la racine du depot).
# Test : qemu-system-i386 -m 64 -cdrom IMAGE/PASDOWS.ISO -boot d
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
FPC=${FPC:-fpc}
W=${W:-$ROOT/BUILD}
mkdir -p "$W/obj" "$W/cd"

echo "== Outils (Free Pascal)"
"$FPC" -O1 -FU"$W/obj" -o"$W/wpc" "$ROOT/TOOLS/WPC.PAS" > "$W/wpc.log" || { cat "$W/wpc.log"; exit 1; }
"$FPC" -FU"$W/obj" -o"$W/makeiso" "$ROOT/TOOLS/MAKEISO.PAS" > "$W/makeiso.log" || { cat "$W/makeiso.log"; exit 1; }

echo "== Contenu du CD-ROM"
rm -f "$W"/cd/*
cp "$ROOT"/IMAGE/CDROM/* "$W/cd/"

echo "== IO.SYS (WPC -CW95IO)"
"$W/wpc" -CW95IO "$HERE/IO.PAS" "$W/cd/IO.SYS"

echo "== VMM32.VXD (WPC -CVMM32)"
"$W/wpc" -CVMM32 "$HERE/VMM32.PAS" "$W/cd/VMM32.VXD"

echo "== Programmes systeme et exemples Win32 (WPC -CW32)"
for P in "$ROOT"/SYSTEM/*.PAS "$ROOT"/EXAMPLES/*.PAS; do
  N=$(basename "$P" .PAS)
  "$W/wpc" -CW32 "$P" "$W/cd/$N.EXE"
  cp "$W/cd/$N.EXE" "$ROOT/IMAGE/CDROM/$N.EXE"
done

echo "== CD-ROM amorcable"
"$W/makeiso" "$ROOT/IMAGE/PASDOWS.ISO" /BOOT:"$W/cd/IO.SYS" /LABEL:PASDOWS95 "$W/cd/*"
cp "$W/cd/IO.SYS" "$W/cd/VMM32.VXD" "$ROOT/IMAGE/CDROM/"
echo "Termine : $ROOT/IMAGE/PASDOWS.ISO"
