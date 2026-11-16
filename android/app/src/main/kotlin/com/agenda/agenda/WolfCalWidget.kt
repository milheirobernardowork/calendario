package com.agenda.agenda

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * Widget do ecrã principal: semanas seguidas (a atual no topo), com scroll
 * para cima e para baixo, o mês atual no cabeçalho e um botão "Hoje".
 */
class WolfCalWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        // Atualiza também os dias (a marca de "hoje" muda à meia-noite).
        manager.notifyAppWidgetViewDataChanged(ids, R.id.weeks)
        for (id in ids) update(context, manager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TODAY || intent.action == ACTION_REFRESH) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, WolfCalWidget::class.java))
            manager.notifyAppWidgetViewDataChanged(ids, R.id.weeks)
            for (id in ids) update(context, manager, id)
        }
    }

    companion object {
        const val ACTION_TODAY = "com.agenda.agenda.WIDGET_TODAY"
        const val ACTION_REFRESH = "com.agenda.agenda.WIDGET_REFRESH"

        fun refreshAll(context: Context) {
            context.sendBroadcast(
                Intent(context, WolfCalWidget::class.java).setAction(ACTION_REFRESH),
            )
        }

        @Suppress("DEPRECATION")
        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val views = RemoteViews(context.packageName, R.layout.wolfcal_widget)

            val service = Intent(context, WolfCalWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.weeks, service)
            views.setEmptyView(R.id.weeks, R.id.empty)

            val today = WidgetData.dateOf(WidgetData.todayEpochDay())
            views.setTextViewText(R.id.month, WidgetData.monthLabel(today))

            val todayIntent = PendingIntent.getBroadcast(
                context, 0,
                Intent(context, WolfCalWidget::class.java).setAction(ACTION_TODAY),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.today, todayIntent)

            val open = PendingIntent.getActivity(
                context, 1, Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.month, open)
            views.setPendingIntentTemplate(
                R.id.weeks,
                PendingIntent.getActivity(
                    context, 2, Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )

            // A semana atual fica no topo.
            views.setScrollPosition(R.id.weeks, WidgetData.load(context).todayWeek())
            manager.updateAppWidget(id, views)
        }
    }
}
