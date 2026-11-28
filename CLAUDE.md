# Pasdows 95 - notes pour les sessions de travail

Clone de Windows 95 en Pascal, compile par WPC (TOOLS/WPC.PAS). Toujours
repondre en francais.

## Regles du projet

- Turbo Pascal / Free Pascal, sans programmation objet, aucune unite
  ajoutee, aucun fichier d'inclusion ($I).
- Lignes de 80 caracteres au plus dans KERNEL/VMM32.PAS, KERNEL/IO.PAS et
  SETUP/INSTALL.PAS ; accents en codes #nnn (page de code 437/850).
- Le noyau VMM32.VXD doit garder SizeOfImage <= 3145728 octets.
- Construction complete : `W=/tmp/claude-0/pt/B bash KERNEL/BUILD.sh`
  (valider aussi IMAGE/CDROM, les ISO, les captures et le README).
- Ne jamais valider de binaires de tiers ; aucune demande de fusion (PR)
  sans demande explicite.

## Lecon : toujours donner signe de vie

Histoire vraie (SCANDISK, novembre 2026) : un balayage de surface de 12
minutes sous VirtualBox laissait l'ecran, la souris et le clavier figes ;
l'utilisateur a cru a un plantage (« ca plante ! »), plusieurs fois. Ce
n'en etait pas un : le programme passait presque tout son temps dans le
noyau (lectures de disque), ou l'horloge ne le preemptait pas. Ce qui a
permis de comprendre et de rassurer :

1. des traces horodatees (journal du noyau sur COM1, `SCANDISK /DEBUG`) ;
2. Ctrl+Alt+Suppr puis le Gestionnaire des taches : « 100 % de l'UC,
   le systeme n'est pas plante, c'est une tache gourmande ».

Donc, en developpant un OS :

- une tache longue montre ce qu'elle fait (progression, activite,
  compteurs) ;
- le noyau ne laisse jamais un programme affamer l'interface (cession du
  processeur dans les appels systeme longs, ex. ReadFile/WriteFile) ;
- il reste toujours un moyen independant de voir que le systeme vit :
  Ctrl+Alt+Suppr, Gestionnaire des taches, journal COM1, options de
  diagnostic des programmes ;
- avant de conclure a un plantage, mesurer (traces horodatees) plutot
  que deviner.
