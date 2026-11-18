import 'models.dart';

/// Data mais próxima primeiro; depois prioridade; depois título.
int compareTasks(Task a, Task b) {
  final ad = a.due, bd = b.due;
  if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
  if (a.priority != b.priority) return b.priority - a.priority;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Tarefas por fazer, arrumadas como na lista: Ativas, Esta semana (hoje,
/// os próximos 7 dias e as atrasadas), Sem data (mais recentes primeiro) e
/// Futuras. Usado pela página Tarefas e pelo widget.
List<(String, List<Task>)> taskSections(List<Task> all, DateTime today) {
  final open = all.where((t) => !t.done).toList()..sort(compareTasks);
  final weekEnd = DateTime(today.year, today.month, today.day + 7);
  final active = open.where((t) => t.active).toList();
  final rest = open.where((t) => !t.active).toList();
  bool isFuture(Task t) =>
      t.future || (t.due != null && t.due!.isAfter(weekEnd));
  final thisWeek = rest.where((t) => !isFuture(t) && t.due != null).toList();
  final noDate = rest.where((t) => !isFuture(t) && t.due == null).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final future = rest.where(isFuture).toList();
  return [
    ('Ativas', active),
    ('Esta semana', thisWeek),
    ('Sem data', noDate),
    ('Futuras', future),
  ];
}
