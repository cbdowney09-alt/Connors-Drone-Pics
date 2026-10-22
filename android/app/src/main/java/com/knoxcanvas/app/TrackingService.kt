package com.knoxcanvas.app

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that runs while the canvasser is clocked in. It does no work itself: while it
 * runs, Android keeps delivering GPS to LocationBridge with the screen locked, using only the
 * "While using the app" permission (the Android version of the iPhone's blue location pill).
 */
class TrackingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val type = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification(), type)
        } catch (e: Exception) {
            // Location permission was taken away, or Android refused the start.
            Log.w("KnoxCanvas", "Couldn't start shift tracking", e)
            stopSelf()
        }
        // Not sticky: if Android kills the app, tracking resumes the next time it's opened.
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, KnoxApp.CHANNEL_TRACKING)
            .setSmallIcon(R.drawable.ic_stat_knox)
            .setContentTitle("Recording your route")
            .setContentText("You're clocked in. KnoxCanvas is finding the houses you walk past.")
            .setOngoing(true)
            .setContentIntent(open)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        private const val NOTIFICATION_ID = 1

        /** Only call while the app is on screen; Android blocks starting it from the background. */
        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context, Intent(context, TrackingService::class.java))
            } catch (e: Exception) {
                Log.w("KnoxCanvas", "Couldn't start shift tracking", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TrackingService::class.java))
        }
    }
}
