{ HELLO.PAS - Exemple de programme Windows 95 (Win32) pour Pasdows 95.

  Compilation avec WPC (Windows 95 Pascal Compiler) :
     WPC -CW32 HELLO.PAS HELLO.EXE

  HELLO.EXE est un vrai executable PE Win32 : il fonctionne sous
  Windows 95 et sous Pasdows 95, dont le noyau VMM32 lui fournit
  KERNEL32, USER32 et GDI32. L'unite Graph est emulee par WPC avec
  une fenetre GDI. }

Program Hello;

Uses Graph;

Var
  Gd, Gm, I : Integer;

Begin
  Gd := Detect;
  InitGraph(Gd, Gm, '');
  SetColor(14);
  For I := 0 To 20 Do Circle(320, 240, 10 + I * 10);
  SetFillStyle(1, 4);
  Bar(20, 20, 200, 100);
  SetColor(15);
  OutTextXY(30, 50, 'Bonjour Pasdows 95 !');
  Line(0, 0, 639, 479);
  ReadLn;
  CloseGraph;
End.
