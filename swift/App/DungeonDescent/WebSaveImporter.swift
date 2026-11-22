import WebKit

/// Reads the web version's save data off this phone.
///
/// The Capacitor app kept everything in IndexedDB ("dd_game_db", table "kv")
/// for the page at capacitor://localhost, with a backup of some keys in
/// localStorage. That storage belongs to this app (same bundle ID), so a hidden
/// web view loading a tiny page at the same address can open it and hand the
/// keys to Swift. Nothing is changed or deleted on the web side.
@MainActor
final class WebSaveImporter: NSObject, WKScriptMessageHandler, WKURLSchemeHandler {
    private var webView: WKWebView?
    private var completion: (([String: String]) -> Void)?
    private var timeout: DispatchWorkItem?

    /// Calls back with every "dd_" key found (empty if there's no web save).
    func read(_ done: @escaping ([String: String]) -> Void) {
        completion = done
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(self, forURLScheme: "capacitor")
        config.userContentController.add(self, name: "ddImport")
        let view = WKWebView(frame: .zero, configuration: config)
        webView = view
        view.load(URLRequest(url: URL(string: "capacitor://localhost/swift-import.html")!))
        let t = DispatchWorkItem { [weak self] in self?.finish([:]) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: t)
    }

    private func finish(_ data: [String: String]) {
        timeout?.cancel()
        timeout = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ddImport")
        webView = nil
        let done = completion
        completion = nil
        done?(data)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        var data: [String: String] = [:]
        if let dict = message.body as? [String: Any] {
            for (k, v) in dict {
                if let s = v as? String { data[k] = s } else { data[k] = "\(v)" }
            }
        }
        finish(data)
    }

    // MARK: WKURLSchemeHandler

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let html = Data(Self.page.utf8)
        let response = URLResponse(url: task.request.url!, mimeType: "text/html",
                                   expectedContentLength: html.count, textEncodingName: "utf-8")
        task.didReceive(response)
        task.didReceive(html)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Copies localStorage backups first, then IndexedDB on top (IndexedDB is the real store).
    private static let page = """
    <!doctype html><meta charset="utf-8"><script>
    (function () {
      var out = {};
      function send() { window.webkit.messageHandlers.ddImport.postMessage(out); }
      try {
        Object.keys(localStorage).forEach(function (k) {
          if (k.indexOf('dd_backup_') === 0) out[k.slice(10)] = localStorage.getItem(k);
          else if (k.indexOf('dd_') === 0 && !(k in out)) out[k] = localStorage.getItem(k);
        });
      } catch (e) {}
      if (!window.indexedDB) { send(); return; }
      var req;
      try { req = indexedDB.open('dd_game_db'); } catch (e) { send(); return; }
      // If the database doesn't exist, opening it would create an empty one,
      // which would break the web version if it's ever installed again. Cancel that.
      req.onupgradeneeded = function () { try { req.transaction.abort(); } catch (e) {} };
      req.onerror = send;
      req.onsuccess = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains('kv')) { db.close(); send(); return; }
        var cur = db.transaction('kv', 'readonly').objectStore('kv').openCursor();
        cur.onerror = send;
        cur.onsuccess = function () {
          var c = cur.result;
          if (c) { out[String(c.key)] = String(c.value); c.continue(); }
          else { db.close(); send(); }
        };
      };
    })();
    </script>
    """
}
