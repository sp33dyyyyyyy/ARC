package com.viper.mobile.notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.viper.mobile.MainActivity
import com.viper.mobile.R
import org.json.JSONObject

/** Builds Android notifications for VIPER notifications: channel per kind, actions and deep links. */
object Notifier {
    const val EXTRA_LINK = "viper.link"
    const val EXTRA_ACTION = "viper.action"
    const val EXTRA_NOTIFICATION_ID = "viper.notificationId"
    const val ACTION_DISMISS = "com.viper.mobile.DISMISS"

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        for ((info, high) in NotifyLogic.CHANNELS) {
            val (id, name, desc) = info
            nm.createNotificationChannel(NotificationChannel(id, name, if (high) NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT).apply { description = desc })
        }
        // Channel from v1.0–1.2; kept so users' existing settings are not lost.
        nm.createNotificationChannel(NotificationChannel("viper_alerts", "VIPER alerts (legacy)", NotificationManager.IMPORTANCE_HIGH))
    }

    fun canPost(ctx: Context) = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun openIntent(ctx: Context, n: JSONObject, action: String, req: Int): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_ACTION, action).putExtra(EXTRA_NOTIFICATION_ID, n.optString("id"))
        NotifyLogic.link(n)?.let { i.putExtra(EXTRA_LINK, it.toString()) }
        return PendingIntent.getActivity(ctx, req, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    /** Show a VIPER notification. Returns false if notifications are not permitted. */
    fun show(ctx: Context, n: JSONObject, sound: Boolean = true): Boolean {
        if (!canPost(ctx)) return false
        val sid = n.optString("id").ifBlank { "local-${System.nanoTime()}" }
        val aid = NotifyLogic.androidId(sid)
        val ch = NotifyLogic.channelFor(n.optString("kind"), n.optString("category"))
        val body = NotifyLogic.text(n)
        val b = NotificationCompat.Builder(ctx, ch).setSmallIcon(R.drawable.ic_stat_viper)
            .setContentTitle(n.optString("title", "VIPER")).setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openIntent(ctx, n, "open", aid)).setAutoCancel(true)
            .setPriority(if (NotifyLogic.isHigh(n)) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(if (ch == NotifyLogic.CH_APPROVAL || ch == NotifyLogic.CH_INPUT) NotificationCompat.CATEGORY_REMINDER else NotificationCompat.CATEGORY_STATUS)
            .setSilent(!sound).setOnlyAlertOnce(true)
        NotifyLogic.actionsFor(n).forEachIndexed { idx, (act, label) ->
            val pi = if (act == "dismiss") PendingIntent.getBroadcast(ctx, aid * 10 + idx, Intent(ctx, DismissReceiver::class.java).setAction(ACTION_DISMISS).putExtra("aid", aid), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            else openIntent(ctx, n, act, aid * 10 + idx)
            b.addAction(0, label, pi)
        }
        return try { NotificationManagerCompat.from(ctx).notify(aid, b.build()); true } catch (_: SecurityException) { false }
    }

    fun cancel(ctx: Context, serverId: String) = NotificationManagerCompat.from(ctx).cancel(NotifyLogic.androidId(serverId))
}

/** "Dismiss" removes the notification only. It never answers the request: the PC keeps waiting (or times out). */
class DismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val aid = intent.getIntExtra("aid", 0)
        if (aid != 0) NotificationManagerCompat.from(context).cancel(aid)
    }
}
