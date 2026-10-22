package com.knoxcanvas.app

object AppConfig {
    /** Where the app loads KnoxCanvas from. Change this if you host app.html somewhere else. */
    const val APP_URL = "https://connorsdronepics.com/app.html"

    /** Origins allowed to talk to the native code (GPS, Google sign-in, share). */
    val APP_ORIGINS = setOf("https://connorsdronepics.com", "https://www.connorsdronepics.com")

    /**
     * The Firebase project's *Web* client ID, used by native Google sign-in. Firebase console →
     * Authentication → Sign-in method → Google → Web SDK configuration → Web client ID.
     * Looks like "526600169975-xxxx.apps.googleusercontent.com". See android/README.md.
     */
    const val GOOGLE_WEB_CLIENT_ID = "PASTE_WEB_CLIENT_ID.apps.googleusercontent.com"

    /** Background shown before the page paints (matches --bg in app.html). */
    const val BACKGROUND = 0xFF0F1117.toInt()
}
