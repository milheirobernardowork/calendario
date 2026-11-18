package com.agenda.agenda

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/** Tarefas gravadas pela app (ver lib/home_widget_sync.dart). */
class TasksData(private val sections: JSONArray) {

    /** Linhas da lista: cabeçalhos de secção e tarefas. */
    val rows: List<Pair<String?, JSONArray?>> by lazy {
        val out = mutableListOf<Pair<String?, JSONArray?>>()
        for (i in 0 until sections.length()) {
            val section = sections.getJSONArray(i)
            val items = section.getJSONArray(1)
            out.add(Pair(section.getString(0) + " · " + items.length(), null))
            for (k in 0 until items.length()) out.add(Pair(null, items.getJSONArray(k)))
        }
        out
    }

    val openCount: Int
        get() = rows.count { it.second != null }

    companion object {
        fun load(context: Context): TasksData {
            val raw = context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.widget_tasks", null)
            return try {
                TasksData(if (raw == null) JSONArray() else JSONArray(raw))
            } catch (e: Exception) {
                TasksData(JSONArray())
            }
        }
    }
}

class WolfCalTasksWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = TasksFactory(applicationContext)
}

class TasksFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

    private var rows: List<Pair<String?, JSONArray?>> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        rows = TasksData.load(context).rows
    }

    override fun onDestroy() {}

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val (header, task) = rows[position]
        if (header != null) {
            val v = RemoteViews(context.packageName, R.layout.wolfcal_tasks_header)
            v.setTextViewText(R.id.section, header)
            return v
        }
        val t = task!!
        val v = RemoteViews(context.packageName, R.layout.wolfcal_tasks_item)
        v.setTextViewText(R.id.task_title, t.getString(0))
        val date = t.getString(1)
        if (date.isEmpty()) {
            v.setViewVisibility(R.id.task_date, View.GONE)
        } else {
            v.setViewVisibility(R.id.task_date, View.VISIBLE)
            v.setTextViewText(R.id.task_date, date)
            v.setTextColor(R.id.task_date, if (t.getInt(3) == 1) 0xFFFF8A80.toInt() else 0xFF9AA3B2.toInt())
        }
        // Círculo com a cor da prioridade (cinzento se não tiver).
        val priority = t.getLong(2).toInt()
        v.setTextColor(R.id.task_dot, if (priority != 0) priority else 0xFF9AA3B2.toInt())
        v.setOnClickFillInIntent(R.id.task_root, Intent())
        return v
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
