import Foundation

enum PortalErrorPage {
    /// Internal scheme for the error page buttons, intercepted by the navigator.
    static let actionScheme = "connectnow"

    static func html(url: URL, reason: String) -> String {
        let link = escape(url.absoluteString)
        return """
        <!doctype html><html lang="en"><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.5 -apple-system, system-ui; margin: 0; min-height: 100vh;
               display: grid; place-items: center; background: Canvas; color: CanvasText; }
        main { max-width: 30em; padding: 32px; }
        .glyph { font-size: 40px; line-height: 1; margin-bottom: 18px; opacity: .55; }
        h1 { font-size: 20px; font-weight: 600; margin: 0 0 6px; letter-spacing: -.01em; }
        p { margin: 0 0 14px; color: color-mix(in srgb, CanvasText 70%, transparent); }
        code { display: block; font: 12px ui-monospace, Menlo; padding: 8px 10px; border-radius: 6px;
               background: color-mix(in srgb, CanvasText 7%, transparent); word-break: break-all; margin: 0 0 20px; }
        .actions { display: flex; gap: 8px; flex-wrap: wrap; }
        a.button { font-size: 13px; text-decoration: none; padding: 5px 14px; border-radius: 6px;
               background: color-mix(in srgb, CanvasText 9%, transparent); color: CanvasText; }
        a.primary { background: AccentColor; color: AccentColorText; }
        </style>
        <main>
          <div class="glyph">⚠︎</div>
          <h1>The portal isn’t responding at this address</h1>
          <p>\(escape(reason))</p>
          <code>\(link)</code>
          <p>Try another address suggested by ConnectNow, or open this one in your usual browser.</p>
          <div class="actions">
            <a class="button primary" href="\(link)">Try Again</a>
            <a class="button" href="\(actionScheme):external">Open in browser</a>
          </div>
        </main></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
