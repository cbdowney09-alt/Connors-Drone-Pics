package com.knoxcanvas.app

/**
 * JavaScript injected into the page before it loads (same job as ios/KnoxCanvas/BridgeScript.swift).
 *
 * app.html detects the native app through the iOS handler `window.webkit.messageHandlers.knox`,
 * so this defines that handler on top of the Android bridge object `knoxAndroid`. The page runs
 * unchanged. It also replaces `navigator.geolocation` with the native GPS, so Android asks for
 * location once (for the app) and the "locate me" button uses the same GPS as shift tracking.
 */
object BridgeScript {
    val SOURCE = """
    (function () {
      if (window.__KNOX_NATIVE__) return;
      window.__KNOX_NATIVE__ = true;
      window.__KNOX_ANDROID__ = true;
      var post = function (m) { try { window.knoxAndroid.postMessage(JSON.stringify(m)); } catch (e) {} };
      window.webkit = window.webkit || {};
      window.webkit.messageHandlers = window.webkit.messageHandlers || {};
      window.webkit.messageHandlers.knox = { postMessage: post };

      var g = { watchers: {}, once: [], next: 1 };
      var active = function () { return g.once.length > 0 || Object.keys(g.watchers).length > 0; };
      window.__knoxGeoDeliver = function (c) {
        var pos = {
          coords: {
            latitude: c.lat, longitude: c.lng, accuracy: c.acc,
            altitude: null, altitudeAccuracy: null,
            heading: c.hdg >= 0 ? c.hdg : null, speed: c.spd >= 0 ? c.spd : null
          },
          timestamp: c.t
        };
        g.once.splice(0).forEach(function (cb) { try { cb.ok(pos); } catch (e) {} });
        Object.keys(g.watchers).forEach(function (k) { try { g.watchers[k].ok(pos); } catch (e) {} });
        if (!active()) post({ cmd: 'geoStop' });
      };
      window.__knoxGeoError = function (code, message) {
        var err = { code: code, message: message, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 };
        g.once.splice(0).forEach(function (cb) { if (cb.err) try { cb.err(err); } catch (e) {} });
        Object.keys(g.watchers).forEach(function (k) { var w = g.watchers[k]; if (w.err) try { w.err(err); } catch (e) {} });
        if (!active()) post({ cmd: 'geoStop' });
      };
      var geo = {
        getCurrentPosition: function (ok, err) { g.once.push({ ok: ok, err: err }); post({ cmd: 'geoStart' }); },
        watchPosition: function (ok, err) { var id = g.next++; g.watchers[id] = { ok: ok, err: err }; post({ cmd: 'geoStart' }); return id; },
        clearWatch: function (id) { delete g.watchers[id]; if (!active()) post({ cmd: 'geoStop' }); }
      };
      try { Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true }); } catch (e) {}

      // Native Google sign-in hands its token here. Importing the same Firebase URLs the page uses
      // returns the page's own module instances, so this signs in the page's Firebase app and its
      // onAuthStateChanged fires. Keep the version in sync with app.html (10.12.0).
      window.__knoxGoogleCredential = function (idToken, accessToken) {
        var base = 'https://www.gstatic.com/firebasejs/10.12.0/';
        Promise.all([import(base + 'firebase-app.js'), import(base + 'firebase-auth.js')])
          .then(function (m) {
            var a = m[1];
            return a.signInWithCredential(a.getAuth(m[0].getApp()), a.GoogleAuthProvider.credential(idToken, accessToken || null));
          })
          .catch(function (e) { post({ cmd: 'googleFailed', message: String((e && (e.code || e.message)) || e) }); });
      };
    })();
    """.trimIndent()
}
