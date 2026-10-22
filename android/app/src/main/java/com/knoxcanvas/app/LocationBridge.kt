package com.knoxcanvas.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.webkit.WebView
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/**
 * Owns the app's GPS and feeds the web page (same job as ios/KnoxCanvas/LocationBridge.swift).
 *
 * 1. Shift tracking: while the canvasser is clocked in, collect GPS points, including with the
 *    screen locked (TrackingService keeps them coming). Points are buffered (and saved) and handed
 *    to `window.KnoxNative.onLocations` whenever the page is on screen, so the page can find the
 *    houses on the streets they walked.
 * 2. `navigator.geolocation` for the page (see BridgeScript), e.g. the "locate me" button.
 */
@SuppressLint("MissingPermission")   // every request is behind hasFine()
object LocationBridge {
    /** The activity showing the page. Null while the app is in the background. */
    interface Host {
        val webView: WebView?
        fun askForPermissions(notifications: Boolean)
    }

    var host: Host? = null
        set(value) {
            field = value
            if (value != null) onForeground() else onBackground()
        }

    private lateinit var app: Context
    private lateinit var manager: LocationManager
    private lateinit var prefs: SharedPreferences

    private var tracking = false      // clocked-in shift tracking is on
    private var geoActive = false     // the page has a pending navigator.geolocation request
    private var pageReady = false     // page said startTracking since it last loaded
    private var flushing = false
    private val buffer = mutableListOf<JSONObject>()

    // Background walking reminder
    private var bgDistance = 0f
    private var lastBgLocation: Location? = null
    private var lastNotifyAt = 0L

    private const val NOTIFY_EVERY_METERS = 250f
    private const val NOTIFY_MIN_INTERVAL_MS = 300_000L
    private const val WALK_NOTIFICATION_ID = 2
    private const val KEY_BUFFER = "knoxPendingLocations"
    private const val KEY_TRACKING = "knoxTracking"
    private const val MAX_BUFFER = 20000

    fun init(context: Context) {
        app = context.applicationContext
        manager = app.getSystemService(LocationManager::class.java)
        prefs = app.getSharedPreferences("knox", Context.MODE_PRIVATE)
        try {
            val saved = JSONArray(prefs.getString(KEY_BUFFER, "[]"))
            for (i in 0 until saved.length()) buffer.add(saved.getJSONObject(i))
        } catch (e: JSONException) {
            buffer.clear()
        }
    }

    // ── Messages from the page ─────────────────────────────

    /** Page is clocked in and ready to receive points. */
    fun pageStartedTracking() {
        pageReady = true
        if (!tracking) startTracking()
        flush()
    }

    /** Page clocked out. */
    fun pageStoppedTracking() {
        tracking = false
        prefs.edit { putBoolean(KEY_TRACKING, false) }
        buffer.clear()
        saveBuffer(force = true)
        manager.removeUpdates(trackListener)
        TrackingService.stop(app)
    }

    fun geoStart() {
        geoActive = true
        if (!ensurePermission(notifications = false)) return
        startGeoUpdates()
        val last = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { p -> runCatching { manager.getLastKnownLocation(p) }.getOrNull() }
            .maxByOrNull { it.elapsedRealtimeNanos }
        if (last != null && ageMs(last) < 15_000) deliverToGeo(last)
    }

    fun geoStop() {
        geoActive = false
        manager.removeUpdates(geoListener)
    }

    /** The web view started loading a new page; wait for it to ask again before sending points. */
    fun pageWillLoad() {
        pageReady = false
        flushing = false
    }

    /** The app was closed mid-shift: keep collecting until the page catches up. */
    fun resumeIfNeeded() {
        if (!tracking && prefs.getBoolean(KEY_TRACKING, false)) startTracking()
    }

    /** The permission dialog closed. */
    fun onPermissionResult() {
        when {
            hasFine() -> {
                if (tracking) beginTrackUpdates()
                if (geoActive) startGeoUpdates()
                sendJS("window.KnoxNative && window.KnoxNative.onTrackingOk && window.KnoxNative.onTrackingOk()")
            }
            hasCoarse() -> reportProblem(
                "Turn on \"Use precise location\" for KnoxCanvas in Settings → Apps → KnoxCanvas → Permissions → Location so houses can be matched."
            )
            tracking || geoActive -> reportProblem(
                "Location is off for KnoxCanvas. Turn it on in Settings → Apps → KnoxCanvas → Permissions → Location (Allow only while using the app)."
            )
        }
    }

    // ── Tracking ───────────────────────────────────────────

    private fun startTracking() {
        tracking = true
        prefs.edit { putBoolean(KEY_TRACKING, true) }
        if (ensurePermission(notifications = true)) beginTrackUpdates()
    }

    private fun beginTrackUpdates() {
        TrackingService.start(app)
        manager.removeUpdates(trackListener)
        manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 5f, trackListener, Looper.getMainLooper())
        if (!manager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            reportProblem("Location is turned off on this phone. Turn it on in quick settings so your route can be recorded.")
        }
    }

    private fun startGeoUpdates() {
        manager.removeUpdates(geoListener)
        var any = false
        for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (manager.isProviderEnabled(p)) {
                manager.requestLocationUpdates(p, 1000L, 0f, geoListener, Looper.getMainLooper())
                any = true
            }
        }
        if (!any) sendJS("window.__knoxGeoError && window.__knoxGeoError(2, ${JSONObject.quote("Location is turned off on this phone. Turn it on in quick settings.")})")
    }

    /** True if we can start updates now. Otherwise asks for permission (the answer comes to onPermissionResult). */
    private fun ensurePermission(notifications: Boolean): Boolean {
        val h = host
        if (hasFine()) {
            if (notifications) h?.askForPermissions(notifications = true)   // only asks if not granted yet
            return true
        }
        if (h != null) h.askForPermissions(notifications) else onPermissionResult()
        return false
    }

    private fun hasFine() = granted(Manifest.permission.ACCESS_FINE_LOCATION)
    private fun hasCoarse() = granted(Manifest.permission.ACCESS_COARSE_LOCATION)
    private fun granted(p: String) = ContextCompat.checkSelfPermission(app, p) == PackageManager.PERMISSION_GRANTED

    private fun reportProblem(msg: String) {
        val q = JSONObject.quote(msg)
        sendJS("window.KnoxNative && window.KnoxNative.onTrackingError($q)")
        sendJS("window.__knoxGeoError && window.__knoxGeoError(1, $q)")
    }

    // ── GPS ────────────────────────────────────────────────

    // Full LocationListener objects, not lambdas: on Android 10 and older the other methods have no
    // default, and a lambda crashes when a provider is switched on or off.
    private val trackListener = object : LocationListener {
        override fun onLocationChanged(location: Location) = onTrackLocation(location)
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private val geoListener = object : LocationListener {
        override fun onLocationChanged(location: Location) { if (host != null) deliverToGeo(location) }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private fun onTrackLocation(loc: Location) {
        if (!tracking || !loc.hasAccuracy()) return
        buffer.add(point(loc))
        if (host == null) noteBackgroundWalking(loc)
        if (buffer.size > MAX_BUFFER) buffer.subList(0, buffer.size - MAX_BUFFER).clear()
        saveBuffer()
        flush()
    }

    private fun point(loc: Location) = JSONObject().apply {
        put("lat", loc.latitude)
        put("lng", loc.longitude)
        put("acc", loc.accuracy.toDouble())
        put("spd", if (loc.hasSpeed()) loc.speed.toDouble() else -1.0)
        put("t", loc.time.toDouble())
    }

    private fun ageMs(loc: Location) = (SystemClock.elapsedRealtimeNanos() - loc.elapsedRealtimeNanos) / 1_000_000

    // ── Delivering to the page ─────────────────────────────

    private fun flush() {
        val web = host?.webView ?: return
        if (!pageReady || !tracking || flushing || buffer.isEmpty()) return
        val batch = buffer.take(500)
        val json = JSONArray(batch).toString()
        flushing = true
        web.evaluateJavascript("(function(){try{window.KnoxNative.onLocations($json);return 1}catch(e){return 0}})()") { result ->
            flushing = false
            if (result != "1") return@evaluateJavascript   // page not ready; keep the points for next time
            buffer.subList(0, minOf(batch.size, buffer.size)).clear()
            saveBuffer(force = buffer.isEmpty())
            if (buffer.isNotEmpty()) flush()
        }
    }

    private fun deliverToGeo(loc: Location) {
        if (!loc.hasAccuracy()) return
        val c = point(loc).put("hdg", if (loc.hasBearing()) loc.bearing.toDouble() else -1.0)
        sendJS("window.__knoxGeoDeliver && window.__knoxGeoDeliver($c)")
    }

    private fun sendJS(js: String) {
        host?.webView?.evaluateJavascript("$js; true", null)
    }

    private var lastSave = 0L
    /** Persist pending points so they survive the app being closed. Throttled while walking. */
    private fun saveBuffer(force: Boolean = false) {
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastSave < 15_000) return
        lastSave = now
        prefs.edit { putString(KEY_BUFFER, JSONArray(buffer).toString()) }
    }

    // ── Background reminder ────────────────────────────────

    /**
     * With the phone in a pocket the page can't show its prompt, so every ~250 m of walking send
     * a quiet notification reminding them to open the app and mark houses.
     */
    private fun noteBackgroundWalking(loc: Location) {
        if (loc.accuracy > 35) return
        lastBgLocation?.let { last ->
            val d = loc.distanceTo(last)
            val dt = (loc.time - last.time) / 1000f
            if (dt > 0 && d / dt < 3.5f) bgDistance += d   // walking only, not driving
        }
        lastBgLocation = loc
        val now = SystemClock.elapsedRealtime()
        if (bgDistance < NOTIFY_EVERY_METERS || (lastNotifyAt != 0L && now - lastNotifyAt < NOTIFY_MIN_INTERVAL_MS)) return
        if (!granted(Manifest.permission.POST_NOTIFICATIONS) && android.os.Build.VERSION.SDK_INT >= 33) return
        lastNotifyAt = now
        val feet = (bgDistance * 3.281f).toInt()
        bgDistance = 0f
        val open = PendingIntent.getActivity(
            app, 0,
            Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(app, KnoxApp.CHANNEL_WALK)
            .setSmallIcon(R.drawable.ic_stat_knox)
            .setContentTitle("Mark the houses you passed")
            .setContentText("You've walked about $feet ft. Open KnoxCanvas to drop door hanger pins on that street.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setSilent(true)
            .build()
        try {
            NotificationManagerCompat.from(app).notify(WALK_NOTIFICATION_ID, n)
        } catch (e: SecurityException) {
            // Notifications are off; nothing to do.
        }
    }

    private fun onForeground() {
        bgDistance = 0f
        lastBgLocation = null
        NotificationManagerCompat.from(app).cancel(WALK_NOTIFICATION_ID)
        if (geoActive && hasFine()) startGeoUpdates()
        flush()
    }

    private fun onBackground() {
        manager.removeUpdates(geoListener)   // "locate me" only matters on screen; tracking keeps running
        saveBuffer(force = true)
    }
}
