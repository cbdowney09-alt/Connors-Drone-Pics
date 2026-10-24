package com.knoxcanvas.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.GeolocationPermissions
import android.webkit.JavascriptInterface
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.File
import java.io.IOException

/** Full-screen WebView that runs KnoxCanvas and wires up the native bridge (same job as ios/KnoxCanvas/WebView.swift). */
class MainActivity : AppCompatActivity(), LocationBridge.Host {
    override var webView: WebView? = null

    private var injectOnPageStart = true   // older WebViews without document-start scripts
    private var triedCache = false
    private var mainLoadFailed = false
    private var asking = false

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        asking = false
        LocationBridge.onPermissionResult()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            isAppearanceLightNavigationBars = false
        }

        val root = FrameLayout(this).apply { setBackgroundColor(AppConfig.BACKGROUND) }
        root.addView(buildWebView(), ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        setContentView(root)
        // Keep the page clear of the status bar, navigation bar, notch and keyboard.
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val ime = insets.getInsets(WindowInsetsCompat.Type.ime())
            v.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            WindowInsetsCompat.CONSUMED
        }

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                val w = webView
                // Leave the app running in the background (a shift may be recording) instead of closing it.
                if (w != null && w.canGoBack()) w.goBack() else moveTaskToBack(true)
            }
        })

        webView?.loadUrl(AppConfig.APP_URL)
    }

    override fun onStart() {
        super.onStart()
        LocationBridge.host = this
        LocationBridge.resumeIfNeeded()
    }

    override fun onStop() {
        if (LocationBridge.host === this) LocationBridge.host = null
        super.onStop()
    }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun buildWebView(): WebView {
        val web = WebView(this)
        web.setBackgroundColor(AppConfig.BACKGROUND)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true             // localStorage: clock-in state, trail, basemap
            cacheMode = WebSettings.LOAD_DEFAULT
            setSupportMultipleWindows(false)     // target="_blank" links come through shouldOverrideUrlLoading
            userAgentString = "$userAgentString KnoxCanvasAndroid"
        }
        CookieManager.getInstance().setAcceptCookie(true)
        WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG)   // chrome://inspect on the PC
        installBridge(web)
        web.webViewClient = Client()
        web.webChromeClient = Chrome()
        webView = web
        return web
    }

    /** `knoxAndroid.postMessage(json)` for the page, plus BridgeScript at document start. */
    private fun installBridge(web: WebView) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(web, "knoxAndroid", AppConfig.APP_ORIGINS) { _, message, _, isMainFrame, _ ->
                if (isMainFrame) message.data?.let(::onPageMessage)
            }
        } else {
            web.addJavascriptInterface(LegacyBridge(), "knoxAndroid")
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(web, BridgeScript.SOURCE, AppConfig.APP_ORIGINS)
            injectOnPageStart = false
        }
    }

    private inner class LegacyBridge {
        @JavascriptInterface
        fun postMessage(json: String) {
            runOnUiThread { if (isAppPage(webView?.url)) onPageMessage(json) }
        }
    }

    // Messages from app.html: window.webkit.messageHandlers.knox.postMessage({ cmd: ... })
    private fun onPageMessage(json: String) {
        val body = try { JSONObject(json) } catch (e: JSONException) { return }
        when (body.optString("cmd")) {
            "startTracking" -> LocationBridge.pageStartedTracking()
            "stopTracking" -> LocationBridge.pageStoppedTracking()
            "geoStart" -> LocationBridge.geoStart()
            "geoStop" -> LocationBridge.geoStop()
            "googleSignIn" -> startGoogleSignIn()
            "googleFailed" -> showMessage(
                "Google sign-in didn't finish (${body.optString("message", "unknown error")}). Try again, or use email and password."
            )
            "haptic" -> webView?.performHapticFeedback(
                if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
            )
            "share" -> shareFile(body.optString("filename", "knoxcanvas.csv"), body.optString("text"))
        }
    }

    // ── Permissions ────────────────────────────────────────

    override fun askForPermissions(notifications: Boolean) {
        if (asking) return
        val wanted = mutableListOf<String>()
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
            wanted += Manifest.permission.ACCESS_FINE_LOCATION
            wanted += Manifest.permission.ACCESS_COARSE_LOCATION
        }
        if (notifications && Build.VERSION.SDK_INT >= 33 && !granted(Manifest.permission.POST_NOTIFICATIONS)) {
            wanted += Manifest.permission.POST_NOTIFICATIONS
        }
        if (wanted.isEmpty()) return
        asking = true
        permissionLauncher.launch(wanted.toTypedArray())
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    // ── Google sign-in ─────────────────────────────────────

    private fun startGoogleSignIn() {
        lifecycleScope.launch {
            try {
                val idToken = GoogleSignIn.signIn(this@MainActivity) ?: return@launch
                // Signs in to the page's Firebase instance (see BridgeScript), so any page version works.
                callPage("window.__knoxGoogleCredential", idToken, "")
            } catch (e: GoogleSignIn.SignInException) {
                showMessage(e.message ?: "Google sign-in failed.")
            }
        }
    }

    private fun showMessage(text: String) {
        if (isFinishing) return
        AlertDialog.Builder(this).setTitle("Google sign-in").setMessage(text).setPositiveButton("OK", null).show()
    }

    // ── Helpers ────────────────────────────────────────────

    /** Calls a page function with string arguments, safely JSON-encoded. */
    private fun callPage(fn: String, vararg args: String) {
        val json = JSONArray(args.toList()).toString()
        webView?.evaluateJavascript("$fn && $fn.apply(null, $json); true", null)
    }

    private fun shareFile(name: String, text: String) {
        val dir = File(cacheDir, "share").apply { mkdirs() }
        val file = File(dir, name.replace('/', '-'))
        try { file.writeText(text) } catch (e: IOException) { return }
        val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
        val send = Intent(Intent.ACTION_SEND)
            .setType(if (name.endsWith(".csv")) "text/csv" else "text/plain")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, name))
    }

    private fun openExternally(uri: Uri) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
        } catch (e: ActivityNotFoundException) {
            // No app for this link (e.g. sms: on a tablet); ignore.
        }
    }

    private fun bareHost(h: String?): String {
        val host = (h ?: "").lowercase()
        return if (host.startsWith("www.")) host.removePrefix("www.") else host
    }

    /** Our own site and Firebase auth stay inside the app; everything else (Zillow, etc.) opens in the browser. */
    private fun isInternal(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: ""
        return AppConfig.APP_ORIGINS.any { bareHost(Uri.parse(it).host) == bareHost(host) }
            || host.endsWith(".vercel.app")
            || host.endsWith(".firebaseapp.com") || host.endsWith(".web.app")
    }

    private fun isAppPage(url: String?): Boolean {
        val uri = Uri.parse(url ?: return false)
        return uri.scheme == "https" && AppConfig.APP_ORIGINS.any { bareHost(Uri.parse(it).host) == bareHost(uri.host) }
    }

    /** Firebase's Google sign-in pages (popup or redirect) and Google's own login page. */
    private fun isGoogleAuth(uri: Uri): Boolean {
        val host = uri.host?.lowercase() ?: ""
        return host == "accounts.google.com"
            || ((host.endsWith(".firebaseapp.com") || host.endsWith(".web.app")) && (uri.path ?: "").startsWith("/__/auth/"))
    }

    private fun showOfflinePage(view: WebView) {
        val html = """
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{background:#0f1117;color:#f0f2ff;font-family:system-ui,sans-serif;display:flex;flex-direction:column;
            align-items:center;justify-content:center;height:100vh;margin:0;padding:24px;box-sizing:border-box;text-align:center}
            button{margin-top:20px;background:#4f6ef7;color:#fff;border:none;border-radius:12px;padding:14px 28px;font-size:16px;font-weight:600}
            p{color:#8b90b0}</style></head><body>
            <h2>No connection</h2><p>KnoxCanvas needs a signal to open the first time. Your saved work is safe on this phone.</p>
            <button onclick="location.href='${AppConfig.APP_URL}'">Try again</button></body></html>
        """.trimIndent()
        view.loadDataWithBaseURL(null, html, "text/html", "utf-8", null)
    }

    // ── WebViewClient ──────────────────────────────────────

    private inner class Client : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            if (!request.isForMainFrame) return false
            val url = request.url
            // The web page's own Google flow (popup → redirect) can't work in an app; do it natively.
            if (isGoogleAuth(url)) { startGoogleSignIn(); return true }
            return when (url.scheme?.lowercase()) {
                "http", "https" -> if (isInternal(url)) false else { openExternally(url); true }
                "about", "data", "blob", "javascript" -> false
                else -> { openExternally(url); true }   // tel:, mailto:, sms:, geo:, market:
            }
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            mainLoadFailed = false
            LocationBridge.pageWillLoad()
            if (injectOnPageStart && isAppPage(url)) view.evaluateJavascript(BridgeScript.SOURCE, null)
        }

        override fun onPageFinished(view: WebView, url: String?) {
            if (!mainLoadFailed) {
                triedCache = false
                view.settings.cacheMode = WebSettings.LOAD_DEFAULT
            }
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (!request.isForMainFrame) return
            mainLoadFailed = true
            // No signal: try the last copy of the page we have cached.
            if (!triedCache) {
                triedCache = true
                view.settings.cacheMode = WebSettings.LOAD_CACHE_ELSE_NETWORK
                view.loadUrl(AppConfig.APP_URL)
            } else {
                showOfflinePage(view)
            }
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            // Android killed the page in the background; bring it back.
            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
            webView = null
            recreate()
            return true
        }
    }

    // ── alert() / confirm() / prompt() ─────────────────────

    private inner class Chrome : WebChromeClient() {
        override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            if (isFinishing) { result.cancel(); return true }
            AlertDialog.Builder(this@MainActivity)
                .setMessage(message)
                .setPositiveButton("OK") { _, _ -> result.confirm() }
                .setOnCancelListener { result.confirm() }
                .show()
            return true
        }

        override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
            if (isFinishing) { result.cancel(); return true }
            AlertDialog.Builder(this@MainActivity)
                .setMessage(message)
                .setNegativeButton("Cancel") { _, _ -> result.cancel() }
                .setPositiveButton("OK") { _, _ -> result.confirm() }
                .setOnCancelListener { result.cancel() }
                .show()
            return true
        }

        override fun onJsPrompt(view: WebView, url: String?, message: String?, defaultValue: String?, result: JsPromptResult): Boolean {
            if (isFinishing) { result.cancel(); return true }
            val input = EditText(this@MainActivity).apply {
                setText(defaultValue)
                setSingleLine()
            }
            val box = FrameLayout(this@MainActivity).apply {
                val pad = (20 * resources.displayMetrics.density).toInt()
                setPadding(pad, 0, pad, 0)
                addView(input)
            }
            AlertDialog.Builder(this@MainActivity)
                .setMessage(message)
                .setView(box)
                .setNegativeButton("Cancel") { _, _ -> result.cancel() }
                .setPositiveButton("OK") { _, _ -> result.confirm(input.text.toString()) }
                .setOnCancelListener { result.cancel() }
                .show()
            return true
        }

        // BridgeScript replaces navigator.geolocation, so this only runs if that injection failed.
        override fun onGeolocationPermissionsShowPrompt(origin: String?, callback: GeolocationPermissions.Callback) {
            callback.invoke(origin, origin != null && isInternal(Uri.parse(origin)), false)
        }
    }
}
