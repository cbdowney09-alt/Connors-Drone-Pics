import Foundation

/// JavaScript injected into the page before it loads.
///
/// It replaces `navigator.geolocation` with a version backed by the native location
/// manager, so iOS asks for location permission once (for the app) instead of also
/// asking for the website, and the "locate me" button uses the same GPS as tracking.
enum BridgeScript {
    static let source = """
    (function () {
      window.__KNOX_NATIVE__ = true;
      var post = function (m) { try { window.webkit.messageHandlers.knox.postMessage(m); } catch (e) {} };
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
    })();
    """
}
