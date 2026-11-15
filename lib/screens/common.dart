// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const locale = 'pt_PT';

const eventColors = <Color>[
  Color(0xFF3F6FD9), // azul
  Color(0xFF2E9E6B), // verde
  Color(0xFFE0703A), // laranja
  Color(0xFFD64562), // vermelho
  Color(0xFF8A56C9), // roxo
  Color(0xFF5C6B7A), // cinzento
];

const eventColorNames = [
  'Azul',
  'Verde',
  'Laranja',
  'Vermelho',
  'Roxo',
  'Cinzento',
];

Color eventColor(int i) => eventColors[i.clamp(0, eventColors.length - 1)];

const priorityNames = ['Nenhuma', 'Baixa', 'Média', 'Alta'];

Color? priorityColor(int p) => switch (p) {
  3 => const Color(0xFFD64562),
  2 => const Color(0xFFE0703A),
  1 => const Color(0xFF3F6FD9),
  _ => null,
};

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String fmtTime(DateTime d) => DateFormat.Hm(locale).format(d);
String fmtDate(DateTime d) =>
    _cap(DateFormat('EEE, d MMM y', locale).format(d));
String fmtDateShort(DateTime d) => DateFormat('d MMM', locale).format(d);
String fmtMonth(DateTime d) =>
    _cap(DateFormat("MMMM 'de' y", locale).format(d));
String fmtWeekday(DateTime d) =>
    DateFormat.E(locale).format(d).substring(0, 3).toLowerCase();
String fmtDayLong(DateTime d) =>
    _cap(DateFormat("EEEE, d 'de' MMMM", locale).format(d));

/// Centra o conteúdo e limita a largura em ecrãs grandes (Windows).
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Eliminar $what?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok == true;
}
