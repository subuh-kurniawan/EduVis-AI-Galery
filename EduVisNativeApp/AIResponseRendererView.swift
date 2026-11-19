//
//  AIResponseRendererView.swift
//  EduVis Native AI
//
//  Komponen NSViewRepresentable pembungkus WKWebView transparan ultra-cepat.
//  Mengintegrasikan seluruh pustaka JS rendering AI lokal:
//  - marked.min.js (Markdown)
//  - katex.min.js & auto-render.min.js (Rumus matematika LaTeX)
//  - mermaid.min.js & ai-mermaid-controls.js (Diagram alir & sequence + Ekspor PNG/SVG native)
//  - chart.min.js & chart-config-normalizer.js (Grafik interaktif)
//  - highlight.min.js (Pewarnaan sintaks kode)
//  - table-png-export.js (Ekspor tabel Markdown ke gambar PNG)
//  - ai-response-engine.js & eduvis-liquid-engine.js
//  - Mendukung blok <think>...</think> collapsible & sinkronisasi ukuran font dinamis (--chat-font-size)
//

import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

final class PassthroughWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Teruskan scroll wheel & trackpad gesture ke parent SwiftUI NSScrollView
        nextResponder?.scrollWheel(with: event)
    }
}

@MainActor
final class AIResponseWebCoordinator: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var onHeightChange: ((CGFloat) -> Void)?
    var lastHash: String = ""
    var lastFontSize: Double = -1

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "sizeNotifier", let height = message.body as? CGFloat {
            DispatchQueue.main.async {
                self.onHeightChange?(max(30, height + 8))
            }
            return
        }
        if message.name == "savePng" {
            DispatchQueue.main.async { self.handlePngSave(message.body) }
            return
        }
        if message.name == "saveSvg" {
            DispatchQueue.main.async { self.handleSvgSave(message.body) }
            return
        }
    }

    private func handlePngSave(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              let filename = payload["filename"] as? String,
              let base64 = payload["base64"] as? String,
              let data = Data(base64Encoded: base64) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let dest = panel.url else {
                self.report(fn: "__nativePngSaveComplete", reqID: requestID, status: "cancelled")
                return
            }
            do {
                try data.write(to: dest, options: .atomic)
                self.report(fn: "__nativePngSaveComplete", reqID: requestID, status: "saved")
            } catch {
                self.report(fn: "__nativePngSaveComplete", reqID: requestID, status: "error", detail: error.localizedDescription)
            }
        }
    }

    private func handleSvgSave(_ body: Any) {
        guard let payload = body as? [String: Any],
              let requestID = payload["requestID"] as? String,
              let filename = payload["filename"] as? String,
              let markup = payload["markup"] as? String,
              let data = markup.data(using: .utf8) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = URL(fileURLWithPath: filename).lastPathComponent
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let dest = panel.url else {
                self.report(fn: "__nativeSvgSaveComplete", reqID: requestID, status: "cancelled")
                return
            }
            do {
                try data.write(to: dest, options: .atomic)
                self.report(fn: "__nativeSvgSaveComplete", reqID: requestID, status: "saved")
            } catch {
                self.report(fn: "__nativeSvgSaveComplete", reqID: requestID, status: "error", detail: error.localizedDescription)
            }
        }
    }

    private func report(fn: String, reqID: String, status: String, detail: String? = nil) {
        var args = [reqID, status]
        if let detail { args.append(detail) }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: args, options: [.fragmentsAllowed]),
              let encoded = String(data: jsonData, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.\(fn)?.(...\(encoded));", completionHandler: nil)
    }
}

struct AIResponseRendererView: NSViewRepresentable {
    let content: String
    let isStreaming: Bool
    let activePort: Int
    @Binding var dynamicHeight: CGFloat
    var fontSize: Double = 15.0

    func makeCoordinator() -> AIResponseWebCoordinator {
        let coord = AIResponseWebCoordinator()
        coord.onHeightChange = { newHeight in
            if abs(self.dynamicHeight - newHeight) > 2 {
                self.dynamicHeight = newHeight
            }
        }
        return coord
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "sizeNotifier")
        controller.add(context.coordinator, name: "savePng")
        controller.add(context.coordinator, name: "saveSvg")
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = PassthroughWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        let htmlString = buildHTMLTemplate(activePort: activePort, initialFontSize: Int(fontSize))
        let baseURL = URL(string: "http://127.0.0.1:\(activePort)/")!
        webView.loadHTMLString(htmlString, baseURL: baseURL)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        let px = Int(max(11, min(32, fontSize)))
        let currentHash = "\(isStreaming)-\(px)-\(content.hashValue)"

        if abs(coord.lastFontSize - fontSize) > 0.1 {
            coord.lastFontSize = fontSize
            let fontJS = """
            document.documentElement.style.setProperty('--chat-font-size', '\(px)px');
            document.body.style.fontSize = '\(px)px';
            if (typeof notifyHeight === 'function') { setTimeout(notifyHeight, 40); }
            """
            webView.evaluateJavaScript(fontJS, completionHandler: nil)
        }

        if coord.lastHash != currentHash {
            coord.lastHash = currentHash
            guard let jsonData = try? JSONSerialization.data(withJSONObject: [content]),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }
            let js = "if (window.renderContent) { window.renderContent(\(jsonString)[0], \(isStreaming)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func buildHTMLTemplate(activePort: Int, initialFontSize: Int) -> String {
        return """
        <!DOCTYPE html>
        <html lang="id">
        <head>
          <meta charset="utf-8">
          <link rel="stylesheet" href="http://127.0.0.1:\(activePort)/nano_asset/assets/css/katex.min.css">
          <link rel="stylesheet" href="http://127.0.0.1:\(activePort)/nano_asset/assets/css/ai-renderers.css">
          <link rel="stylesheet" href="http://127.0.0.1:\(activePort)/nano_asset/assets/css/github-dark.min.css">
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/marked.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/katex.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/auto-render.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/highlight.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/mermaid.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/ai-mermaid-controls.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/chart.min.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/table-png-export.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/ai-response-engine.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/chat-font-size.js"></script>
          <script src="http://127.0.0.1:\(activePort)/nano_asset/assets/js/eduvis-liquid-engine.js"></script>
          <style>
            .gemma-font-widget, #gfc-pill {
              display: none !important;
            }
            :root {
              color-scheme: light dark;
              --chat-font-size: \(initialFontSize)px;
            }
            html, body {
              overflow: hidden !important;
            }
            body {
              margin: 0;
              padding: 4px 6px;
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Helvetica, Arial, sans-serif;
              font-size: var(--chat-font-size, \(initialFontSize)px);
              line-height: 1.65;
              background: transparent !important;
            }
            p, li, td, th, blockquote {
              font-size: var(--chat-font-size, \(initialFontSize)px);
            }
            @media (prefers-color-scheme: light) {
              body, p, li, span, h1, h2, h3, h4, h5, h6, strong, em {
                color: #0f172a !important;
              }
              pre {
                background: #f1f5f9 !important;
                border: 1px solid #cbd5e1 !important;
                color: #0f172a !important;
              }
              code {
                color: #0f172a !important;
                background: rgba(0,0,0,0.05);
                padding: 1px 4px;
                border-radius: 4px;
              }
              pre code {
                background: transparent;
                padding: 0;
              }
              table { border-collapse: collapse; }
              th, td {
                border: 1px solid #cbd5e1 !important;
                color: #0f172a !important;
              }
              th {
                background: #e2e8f0 !important;
                font-weight: 600;
              }
              .thinking-details {
                background: rgba(241, 245, 249, 0.85);
                border: 1px solid rgba(15, 23, 42, 0.12);
              }
            }
            @media (prefers-color-scheme: dark) {
              body, p, li, span, h1, h2, h3, h4, h5, h6, strong, em {
                color: #f8fafc !important;
              }
              pre {
                background: rgba(0, 0, 0, 0.45) !important;
                border: 1px solid rgba(255, 255, 255, 0.15) !important;
                color: #f8fafc !important;
              }
              code {
                color: #f8fafc !important;
                background: rgba(255,255,255,0.1);
                padding: 1px 4px;
                border-radius: 4px;
              }
              pre code {
                background: transparent;
                padding: 0;
              }
              table { border-collapse: collapse; }
              th, td {
                border: 1px solid rgba(255, 255, 255, 0.18) !important;
                color: #f8fafc !important;
              }
              th {
                background: rgba(255, 255, 255, 0.08) !important;
                font-weight: 600;
              }
              .thinking-details {
                background: rgba(255, 255, 255, 0.05);
                border: 1px solid rgba(255, 255, 255, 0.14);
              }
            }
            p { margin: 0.5em 0; }
            ul, ol { padding-left: 20px; margin: 0.5em 0; }
            li { margin: 0.25em 0; }
            pre {
              border-radius: 10px;
              padding: 10px 12px;
              overflow-x: auto;
            }
            code {
              font-family: "SF Mono", Menlo, Consolas, monospace;
              font-size: max(12px, calc(var(--chat-font-size, \(initialFontSize)px) * 0.88));
            }
            table { width: 100%; margin: 0.7em 0; }
            th, td { padding: 7px 11px; text-align: left; }
            .katex { font-size: 1.05em; }
            .katex-display {
              margin: 0.6em 0;
              overflow-x: auto;
              overflow-y: hidden;
            }
            .thinking-details {
              border-radius: 12px;
              padding: 8px 12px;
              margin-bottom: 10px;
              backdrop-filter: blur(18px);
              -webkit-backdrop-filter: blur(18px);
            }
            .thinking-details summary {
              cursor: pointer;
              font-size: 12px;
              font-weight: 600;
              opacity: 0.85;
              user-select: none;
            }
            .thinking-body {
              margin-top: 8px;
              font-size: 12.5px;
              opacity: 0.82;
              white-space: pre-wrap;
              border-top: 1px solid rgba(148,163,184,0.2);
              padding-top: 6px;
            }
          </style>
        </head>
        <body>
          <div id="content"></div>
          <script>
            if (window.mermaid) {
              try {
                mermaid.initialize({
                  startOnLoad: false,
                  theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default'
                });
              } catch(e) {}
            }

            function notifyHeight() {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.sizeNotifier) {
                var h = document.body.scrollHeight || document.documentElement.scrollHeight;
                window.webkit.messageHandlers.sizeNotifier.postMessage(h);
              }
            }

            function extractThinkingBlock(rawText) {
              if (!rawText) return { thinking: '', answer: '' };
              var openTag = '<think>';
              var closeTag = '</think>';
              var start = rawText.indexOf(openTag);
              if (start === -1) return { thinking: '', answer: rawText };
              var end = rawText.indexOf(closeTag, start + openTag.length);
              if (end === -1) {
                return {
                  thinking: rawText.slice(start + openTag.length),
                  answer: rawText.slice(0, start)
                };
              }
              return {
                thinking: rawText.slice(start + openTag.length, end),
                answer: (rawText.slice(0, start) + rawText.slice(end + closeTag.length)).trim()
              };
            }

            function escapeHtmlText(str) {
              return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;');
            }

            window.renderContent = function(rawText, isStreaming) {
              var target = document.getElementById('content');
              if (!target) return;

              var parsedThink = extractThinkingBlock(rawText || '');
              var thinkingHTML = '';
              if (parsedThink.thinking && parsedThink.thinking.trim().length > 0) {
                var isOpen = isStreaming ? ' open' : '';
                thinkingHTML = '<details class="thinking-details"' + isOpen + '>' +
                  '<summary>🧠 Proses Penalaran AI (' + (isStreaming ? 'Sedang berpikir…' : 'Klik untuk lihat') + ')</summary>' +
                  '<div class="thinking-body">' + escapeHtmlText(parsedThink.thinking.trim()) + '</div>' +
                  '</details>';
              }

              var bodyText = parsedThink.answer || '';
              var bodyHTML = '';
              if (window.AIResponseEngine && typeof window.AIResponseEngine.render === 'function') {
                bodyHTML = window.AIResponseEngine.render(bodyText);
              } else if (window.marked) {
                bodyHTML = marked.parse(bodyText);
              } else {
                bodyHTML = '<p>' + escapeHtmlText(bodyText) + '</p>';
              }

              target.innerHTML = thinkingHTML + bodyHTML;

              if (window.renderMathInElement && !(window.AIResponseEngine && typeof window.AIResponseEngine.render === 'function')) {
                try {
                  renderMathInElement(target, {
                    delimiters: [
                      {left: '$$', right: '$$', display: true},
                      {left: '$', right: '$', display: false},
                      {left: '\\\\[', right: '\\\\]', display: true},
                      {left: '\\\\(', right: '\\\\)', display: false}
                    ],
                    throwOnError: false
                  });
                } catch(e) {}
              }

              if (window.hljs) {
                target.querySelectorAll('pre code').forEach(function(el) {
                  try { hljs.highlightElement(el); } catch(e) {}
                });
              }

              if (window.mermaid) {
                try { mermaid.init(undefined, target.querySelectorAll('.mermaid')); } catch(e) {}
              }

              target.querySelectorAll('details.thinking-details').forEach(function(d) {
                d.addEventListener('toggle', function() { setTimeout(notifyHeight, 30); });
              });

              notifyHeight();
              setTimeout(notifyHeight, 60);
              setTimeout(notifyHeight, 200);
            };

            window.addEventListener('load', notifyHeight);
            window.addEventListener('resize', notifyHeight);
          </script>
        </body>
        </html>
        """
    }
}
