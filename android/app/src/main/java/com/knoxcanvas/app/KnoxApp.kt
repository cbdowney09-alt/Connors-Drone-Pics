package com.knoxcanvas.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager

class KnoxApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_TRACKING, "Shift tracking", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while you're clocked in and your route is being recorded."
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_WALK, "Walking reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Reminds you to mark the houses you walked past."
                setSound(null, null)
            }
        )
        LocationBridge.init(this)
    }

    companion object {
        const val CHANNEL_TRACKING = "tracking"
        const val CHANNEL_WALK = "walk"
    }
}
