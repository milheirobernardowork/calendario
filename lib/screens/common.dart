// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';

const locale = 'pt_PT';

const eventColors = <Color>[
  Color(0xFF3F6FD9), // azul
  Color(0xFF2E9E6B), // verde
  Color(0xFFE0703A), // laranja
  Color(0xFFE0201B), // vermelho
  Color(0xFF8A56C9), // roxo
  Color(0xFF5C6B7A), // cinzento
  // Acrescentar sempre no fim: o índice é o que fica gravado no evento.
  Color(0xFF6EC6F5), // azul claro
  Color(0xFFF0B2AA), // cor de pele (rosada)
  Color(0xFF0B8043), // verde escuro
  Color(0xFF7986CB), // lilás
];

const eventColorNames = [
  'Azul',
  'Verde',
  'Laranja',
  'Vermelho',
  'Roxo',
  'Cinzento',
  'Azul claro',
  'Cor de pele',
  'Verde escuro',
  'Lilás',
];

Color eventColor(int i) => eventColors[i.clamp(0, eventColors.length - 1)];

const priorityNames = ['Nenhuma', 'Baixa', 'Média', 'Alta'];

Color? priorityColor(int p) => switch (p) {
  3 => const Color(0xFFE0201B),
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

/// Botões grandes, usados ao mexer em eventos.
final bigButton = ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(104, 52)),
  textStyle: const WidgetStatePropertyAll(
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22)),
);

/// Cor de texto legível sobre [background].
Color onColor(Color background) => background.computeLuminance() > 0.45
    ? const Color(0xFF1B2230)
    : Colors.white;

/// Bloco de um evento dentro de um dia (grelha do mês e painel da semana).
class EventChipBox extends StatelessWidget {
  const EventChipBox({
    super.key,
    required this.event,
    required this.day,
    required this.compact,
    this.highlight = false,
  });

  /// Altura ocupada por cada bloco (24 + margens).
  static const extent = 26.0;

  final Event event;
  final DateTime day;

  /// Células estreitas: letra menor e sem hora.
  final bool compact;

  /// Realça o evento (o que está a ser editado).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = eventColor(event.color);
    final showTime = !compact && !event.allDay && event.startsOn(day);
    return Container(
      height: 24,
      margin: const EdgeInsets.fromLTRB(2, 1, 2, 1),
      foregroundDecoration: highlight
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.onSurface, width: 2),
            )
          : null,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 6),
      alignment: Alignment.centerLeft,
      child: Text(
        showTime ? '${fmtTime(event.start)} ${event.title}' : event.title,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          // No telemóvel, letra mais pequena para caber mais do nome.
          fontSize: compact ? 9.5 : 13,
          letterSpacing: compact ? -0.2 : null,
          height: 1.1,
          color: onColor(color),
          decoration: TextDecoration.none,
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

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

/// Abre um ecrã com uma transição curta (aparece logo ao clicar).
Route<T> fastRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 120),
  reverseTransitionDuration: const Duration(milliseconds: 100),
  pageBuilder: (context, _, _) => builder(context),
  transitionsBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

/// Como [ListenableBuilder], mas não redesenha enquanto a página está
/// escondida (separador não visível, ou por baixo de outro ecrã). Quando
/// volta a aparecer, redesenha uma vez se algo mudou entretanto.
class StoreListener extends StatefulWidget {
  const StoreListener({
    super.key,
    required this.listenable,
    required this.builder,
  });

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<StoreListener> createState() => _StoreListenerState();
}

class _StoreListenerState extends State<StoreListener> {
  bool _stale = false;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(StoreListener old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    if (_visible && _stale) _stale = false; // o build seguinte já atualiza
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_visible) {
      setState(() {});
    } else {
      _stale = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
