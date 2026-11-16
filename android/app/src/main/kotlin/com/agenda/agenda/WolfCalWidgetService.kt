package com.agenda.agenda

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.util.Calendar

class WolfCalWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = WeeksFactory(applicationContext)
}

/** Uma linha por semana. */
class WeeksFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private var data = WidgetData(0, 0, null)

    private val numbers = intArrayOf(R.id.num0, R.id.num1, R.id.num2, R.id.num3, R.id.num4, R.id.num5, R.id.num6)
    private val columns = intArrayOf(R.id.ev0, R.id.ev1, R.id.ev2, R.id.ev3, R.id.ev4, R.id.ev5, R.id.ev6)

    override fun onCreate() {}

    override fun onDataSetChanged() {
        data = WidgetData.load(context)
    }

    override fun onDestroy() {}

    override fun getCount(): Int = data.weeks

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.wolfcal_widget_week)
        val today = WidgetData.todayEpochDay()
        var monthStart: Calendar? = null

        for (i in 0 until 7) {
            val epochDay = data.first + position * 7L + i
            val date = WidgetData.dateOf(epochDay)
            val dayOfMonth = date.get(Calendar.DAY_OF_MONTH)
            if (dayOfMonth == 1) monthStart = date

            val isToday = epochDay == today
            row.setTextViewText(numbers[i], dayOfMonth.toString())
            row.setTextColor(numbers[i], if (isToday) Color.WHITE else 0xFF1B2230.toInt())
            row.setInt(
                numbers[i], "setBackgroundResource",
                if (isToday) R.drawable.wolfcal_today else 0,
            )

            row.removeAllViews(columns[i])
            val events = data.eventsOfDay(position * 7 + i)
            val count = events.length()
            val shown = if (count > MAX_PER_DAY) MAX_PER_DAY - 1 else count
            for (k in 0 until shown) {
                val e = events.getJSONArray(k)
                val item = RemoteViews(context.packageName, R.layout.wolfcal_widget_event)
                item.setTextViewText(R.id.event, e.getString(0))
                item.setInt(R.id.event, "setBackgroundColor", e.getLong(1).toInt())
                item.setTextColor(R.id.event, e.getLong(2).toInt())
                row.addView(columns[i], item)
            }
            if (count > shown) {
                val more = RemoteViews(context.packageName, R.layout.wolfcal_widget_event)
                more.setTextViewText(R.id.event, "+" + (count - shown))
                more.setInt(R.id.event, "setBackgroundColor", Color.TRANSPARENT)
                more.setTextColor(R.id.event, 0xFF5C6B7A.toInt())
                row.addView(columns[i], more)
            }
        }

        // Nome do mês por cima da semana em que ele começa.
        val start = monthStart
        if (start != null) {
            row.setViewVisibility(R.id.month_label, View.VISIBLE)
            row.setTextViewText(R.id.month_label, WidgetData.monthLabel(start))
        } else {
            row.setViewVisibility(R.id.month_label, View.GONE)
        }
        // Tocar numa semana abre a app.
        row.setOnClickFillInIntent(R.id.week_root, Intent())
        return row
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    companion object {
        private const val MAX_PER_DAY = 4
    }
}
