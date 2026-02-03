package com.example.healing_hi

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONException
import kotlin.random.Random

class QuoteWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val WIDGET_REFRESH_ACTION = "com.example.healing_hi.WIDGET_REFRESH"
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val QUOTE_DATA_KEY = "quote_data"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // 각 위젯 인스턴스마다 업데이트
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        // 위젯 새로고침 액션 처리
        if (intent.action == WIDGET_REFRESH_ACTION) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(
                android.content.ComponentName(context, QuoteWidgetProvider::class.java)
            )
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        Log.d("QuoteWidget", "updateAppWidget 호출됨")

        // RemoteViews 생성
        val views = RemoteViews(context.packageName, R.layout.quote_widget_layout)

        // SharedPreferences에서 명언 데이터 읽기
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val quoteDataJson = prefs.getString(QUOTE_DATA_KEY, null)

        Log.d("QuoteWidget", "SharedPreferences 키: $QUOTE_DATA_KEY")
        Log.d("QuoteWidget", "읽은 데이터: ${quoteDataJson?.take(100)}")

        var hasData = false

        if (quoteDataJson != null && quoteDataJson.isNotEmpty()) {
            try {
                // JSON 파싱
                val quotesArray = JSONArray(quoteDataJson)

                if (quotesArray.length() > 0) {
                    hasData = true
                    Log.d("QuoteWidget", "명언 개수: ${quotesArray.length()}")

                    // 랜덤으로 명언 선택
                    val randomIndex = Random.nextInt(quotesArray.length())
                    val quoteObject = quotesArray.getJSONObject(randomIndex)

                    // 명언 텍스트와 저자 추출
                    val quoteText = quoteObject.optString("text_kr", "명언을 불러올 수 없습니다")
                    val authorName = quoteObject.optString("resoner_kr", "알 수 없음")

                    Log.d("QuoteWidget", "선택된 명언: $quoteText - $authorName")

                    // 위젯에 텍스트 설정
                    views.setTextViewText(R.id.quote_text, quoteText)
                    views.setTextViewText(R.id.author_name, authorName)
                } else {
                    // 명언 데이터가 비어있는 경우
                    Log.d("QuoteWidget", "명언 배열이 비어있음")
                    setEmptyMessage(views)
                }
            } catch (e: JSONException) {
                // JSON 파싱 오류
                Log.e("QuoteWidget", "JSON 파싱 오류: ${e.message}")
                e.printStackTrace()
                setEmptyMessage(views)
            }
        } else {
            // 캐시된 데이터가 없는 경우
            Log.d("QuoteWidget", "캐시된 데이터 없음 (quoteDataJson is null or empty)")
            setEmptyMessage(views)
        }

        // 위젯 탭 시 동작 설정
        val pendingIntent = if (hasData) {
            // 데이터가 있으면 새로고침
            val refreshIntent = Intent(context, QuoteWidgetProvider::class.java).apply {
                action = WIDGET_REFRESH_ACTION
            }
            PendingIntent.getBroadcast(
                context,
                0,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            // 데이터가 없으면 앱 열기
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        views.setOnClickPendingIntent(R.id.quote_text, pendingIntent)

        // 위젯 업데이트
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun setEmptyMessage(views: RemoteViews) {
        views.setTextViewText(R.id.quote_text, "앱을 열어 명언을 불러오세요")
        views.setTextViewText(R.id.author_name, "")
    }
}
