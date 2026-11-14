package com.viper.mobile

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Optional foreground service. Keeps the encrypted connection to the PC alive so alerts arrive
 * while the app is in the background, and hosts hands-free (wake word) listening. Android shows
 * a persistent notification whenever it runs, so listening is never hidden from the user.
 */
class ConnectionService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val app = application as ViperApp
        val handsFree = app.store.handsFree && app.hasMic()
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, ConnectionService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        if (intent?.action == ACTION_STOP) { app.store.stayConnected = false; app.store.handsFree = false; app.stopHandsFree(); stopSelf(); return START_NOT_STICKY }
        val n = NotificationCompat.Builder(this, ViperApp.CH_SERVICE).setSmallIcon(R.drawable.ic_stat_viper)
            .setContentTitle(if (handsFree) "VIPER is listening for \"VIPER\"" else "VIPER Mobile is connected")
            .setContentText(if (handsFree) "Audio is processed only by your paired PC." else "Receiving alerts from your PC.")
            .setContentIntent(pi).addAction(0, "Stop", stop).setOngoing(true).build()
        val type = if (Build.VERSION.SDK_INT >= 34) (if (handsFree) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0) or ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING else 0
        ServiceCompat.startForeground(this, 42, n, type)
        app.client.connect()
        if (handsFree) app.startHandsFree() else app.stopHandsFree()
        return START_STICKY
    }

    override fun onDestroy() { (application as ViperApp).stopHandsFree(); super.onDestroy() }

    companion object {
        const val ACTION_STOP = "com.viper.mobile.STOP"
        fun update(ctx: Context) {
            val app = ctx.applicationContext as ViperApp
            if (app.store.stayConnected || app.store.handsFree) ContextCompat.startForegroundService(ctx, Intent(ctx, ConnectionService::class.java))
            else ctx.stopService(Intent(ctx, ConnectionService::class.java))
        }
    }
}
