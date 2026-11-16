package com.agenda.agenda

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone

/** Dados que a app grava para o widget (ver lib/home_widget_sync.dart). */
class WidgetData(val first: Long, val weeks: Int, private val days: JSONArray?) {

    fun eventsOfDay(index: Int): JSONArray =
        days?.optJSONArray(index) ?: JSONArray()

    /** Semana (posição na lista) que contém hoje. */
    fun todayWeek(): Int {
        if (weeks == 0) return 0
        return ((todayEpochDay() - first) / 7).toInt().coerceIn(0, weeks - 1)
    }

    companion object {
        private const val DAY_MS = 86_400_000L

        val MONTHS = arrayOf(
            "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho",
            "agosto", "setembro", "outubro", "novembro", "dezembro",
        )

        fun load(context: Context): WidgetData {
            val raw = context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.widget_data", null)
                ?: return WidgetData(0, 0, null)
            return try {
                val json = JSONObject(raw)
                WidgetData(json.getLong("first"), json.getInt("weeks"), json.getJSONArray("days"))
            } catch (e: Exception) {
                WidgetData(0, 0, null)
            }
        }

        /** Dias desde 1970-01-01 da data local de hoje. */
        fun todayEpochDay(): Long {
            val now = Calendar.getInstance()
            val utc = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
            utc.clear()
            utc.set(now.get(Calendar.YEAR), now.get(Calendar.MONTH), now.get(Calendar.DAY_OF_MONTH))
            return utc.timeInMillis / DAY_MS
        }

        fun dateOf(epochDay: Long): Calendar {
            val c = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
            c.timeInMillis = epochDay * DAY_MS
            return c
        }

        fun monthLabel(c: Calendar): String {
            val name = MONTHS[c.get(Calendar.MONTH)]
            return name.replaceFirstChar { it.uppercase() } + " " + c.get(Calendar.YEAR)
        }
    }
}
