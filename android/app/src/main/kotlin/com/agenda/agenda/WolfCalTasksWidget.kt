package com.agenda.agenda

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/** Widget com as tarefas por fazer, arrumadas como na app. */
class WolfCalTasksWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.notifyAppWidgetViewDataChanged(ids, R.id.tasks)
        for (id in ids) update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WolfCalTasksWidget::class.java))
            manager.notifyAppWidgetViewDataChanged(ids, R.id.tasks)
            for (id in ids) update(context, manager, id)
        }
    }

    companion object {
        const val ACTION_REFRESH = "com.agenda.agenda.TASKS_WIDGET_REFRESH"

        fun refreshAll(context: Context) {
            context.sendBroadcast(
                Intent(context, WolfCalTasksWidget::class.java).setAction(ACTION_REFRESH),
            )
        }

        private fun openTasks(context: Context): Intent =
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_TAB, "tasks")
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)

        @Suppress("DEPRECATION")
        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.wolfcal_tasks_widget)
            val service = Intent(context, WolfCalTasksWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.tasks, service)
            views.setEmptyView(R.id.tasks, R.id.tasks_empty)

            val count = TasksData.load(context).openCount
            views.setTextViewText(R.id.tasks_count, if (count > 0) count.toString() else "")

            // Tocar no cabeçalho, no "+" ou numa tarefa abre a página Tarefas.
            val open = PendingIntent.getActivity(
                context, 10, openTasks(context),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.tasks_title, open)
            views.setOnClickPendingIntent(R.id.tasks_add, open)
            views.setPendingIntentTemplate(
                R.id.tasks,
                PendingIntent.getActivity(
                    context, 11, openTasks(context),
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            manager.updateAppWidget(id, views)
        }
    }
}
