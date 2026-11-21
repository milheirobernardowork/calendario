import 'models.dart';

/// Com data primeiro (a mais próxima primeiro); depois prioridade; depois
/// título.
int compareTasks(Task a, Task b) {
  final ad = a.due, bd = b.due;
  if (ad != null && bd == null) return -1;
  if (ad == null && bd != null) return 1;
  if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
  if (a.priority != b.priority) return b.priority - a.priority;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// A tarefa está nas "Ativas"? As marcadas como ativas e todas as que têm
/// data, a não ser que estejam marcadas como futuras.
bool isActiveTask(Task t, DateTime today) {
  if (t.done || t.future) return false;
  return t.active || t.due != null;
}

/// Tarefas por fazer, arrumadas como na lista: Ativas (com ou sem data),
/// Por Fazer (sem data, mais recentes primeiro) e Futuras. Usado pela página Tarefas,
/// pelo painel do calendário e pelo widget.
List<(String, List<Task>)> taskSections(List<Task> all, DateTime today) {
  final open = all.where((t) => !t.done).toList()..sort(compareTasks);
  final active = open.where((t) => isActiveTask(t, today)).toList();
  final rest = open.where((t) => !isActiveTask(t, today)).toList();
  final noDate = rest.where((t) => !t.future && t.due == null).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final future = rest.where((t) => t.future).toList();
  return [('Ativas', active), ('Por Fazer', noDate), ('Futuras', future)];
}
