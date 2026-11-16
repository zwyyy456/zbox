import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import LookupPresentation
import SystemDictionary

struct SystemDictionaryContentView: View {
    let entries: [SystemDictionaryEntry]
    let onLookup: (String) -> Void
    @State private var height: CGFloat = 1
    @State private var resourceFailed = false
    var body: some View {
        SystemDictionaryWebView(entries: entries, onHeight: { height = $0 }, onLookup: onLookup,
            onResourceFailure: { resourceFailed = true })
            .frame(height: height)
        if resourceFailed {
            Text("A system dictionary resource could not be loaded.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct SystemDictionaryWebView: NSViewRepresentable {
    let entries: [SystemDictionaryEntry]
    let onHeight: (CGFloat) -> Void
    let onLookup: (String) -> Void
    let onResourceFailure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onLookup: onLookup) }
    func makeNSView(context: Context) -> LookupContentWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let resources = SystemDictionarySchemeHandler(roots: Dictionary(uniqueKeysWithValues:
            entries.enumerated().map { ("d\($0.offset)", $0.element.contentsURL) }), onFailure: onResourceFailure)
        configuration.setURLSchemeHandler(resources, forURLScheme: "system-dictionary")
        configuration.userContentController.add(context.coordinator, name: "systemEntry")
        let view = LookupContentWebView(frame: .zero, configuration: configuration)
        context.coordinator.embedding = LookupWebEmbedding(webView: view, onHeight: onHeight)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        let sections = entries.enumerated().map { index, entry in
            var html = entry.html
            let base = "<base href=\"system-dictionary://d\(index)/\">"
            if let head = html.range(of: "<head>", options: .caseInsensitive) { html.insert(contentsOf: base, at: head.upperBound) }
            else { html = base + html }
            // Preserve dictionary markup; route only local absolute resource paths through the owning bundle.
            if let regex = try? NSRegularExpression(pattern: #"(file://(?:localhost)?/|(?<=[\"'\(])/)(?:System|Library|Users|private)/[^\"'<>\s\)]*"#) {
                let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in matches.reversed() {
                    guard let range = Range(match.range, in: html) else { continue }
                    let original = String(html[range])
                    let path = original.hasPrefix("file:") ? URL(string: original)?.path ?? "" : original
                    let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                    html.replaceSubrange(range, with: "system-dictionary://d\(index)/__absolute__\(encoded)")
                }
            }
            html += """
            <style>html,body{min-height:0!important;height:auto!important;overflow:hidden!important}body{margin:0!important;padding:4px!important} @media(prefers-color-scheme:dark){html{color-scheme:dark}}</style>
            <script>
            function report(){let h=0;for(const e of document.body.children){if(['SCRIPT','STYLE','LINK'].includes(e.tagName))continue;h=Math.max(h,e.getBoundingClientRect().bottom+window.scrollY)}parent.postMessage({dictionaryFrame:'d\(index)',height:Math.ceil(h+8)},'*')}
            new ResizeObserver(report).observe(document.body);addEventListener('load',report);document.fonts?.ready.then(report);report();
            document.addEventListener('click',function(e){
              const a=e.target.closest('a'); if(!a)return;
              const href=a.getAttribute('href')||'';
              if(!/^(x-dictionary:[rd]:|dict:|#)/i.test(href))return;
              e.preventDefault();
              let target=null;
              try {
                const decoded=decodeURIComponent(href), pointer=decoded.match(/#xpointer\\((.*)\\)$/);
                if(pointer)target=document.evaluate(pointer[1],document,null,XPathResult.FIRST_ORDERED_NODE_TYPE,null).singleNodeValue;
                else if(href.startsWith('#'))target=document.getElementById(decoded.slice(1));
              }catch(_){}
              if(target){parent.postMessage({dictionaryFrame:'d\(index)',top:target.getBoundingClientRect().top+window.scrollY},'*');return}
              const term=a.textContent.trim();if(term)window.webkit.messageHandlers.systemEntry.postMessage(term);
            });
            </script>
            """
            return "<section><h3>\(Self.escape(entry.dictionaryName))</h3><iframe id=\"d\(index)\" srcdoc=\"\(Self.escape(html))\" style=\"border:0;width:100%;height:1px\" scrolling=\"no\"></iframe></section>"
        }.joined()
        view.loadHTMLString("""
        <!doctype html><html><head><meta name="color-scheme" content="light dark"><style>body{margin:0;font:13px -apple-system}h3{font-size:12px;color:GrayText;margin:12px 0 6px}section{margin:0 0 12px}</style></head><body>\(sections)
        <script>addEventListener('message',e=>{let f=document.getElementById(e.data.dictionaryFrame);if(!f||f.contentWindow!==e.source)return;if(Number.isFinite(e.data.height)&&e.data.height>0){let h=Math.ceil(e.data.height)+'px';if(f.style.height!==h)f.style.height=h}if(Number.isFinite(e.data.top))window.scrollTo({top:f.getBoundingClientRect().top+window.scrollY+e.data.top})})</script></body></html>
        """, baseURL: nil)
        return view
    }
    func updateNSView(_ nsView: LookupContentWebView, context: Context) { context.coordinator.onLookup = onLookup }
    static func dismantleNSView(_ view: LookupContentWebView, coordinator: Coordinator) {
        coordinator.embedding?.invalidate()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "systemEntry")
        view.stopLoading()
    }
    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var embedding: LookupWebEmbedding?
        var onLookup: (String) -> Void
        init(onLookup: @escaping (String) -> Void) { self.onLookup = onLookup }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let term = message.body as? String, !term.isEmpty, term.count <= 128 else { return }
            onLookup(term)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               ["https", "http"].contains(url.scheme) {
                NSWorkspace.shared.open(url); decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

@MainActor private final class SystemDictionarySchemeHandler: NSObject, WKURLSchemeHandler {
    let roots: [String: URL]
    let onFailure: () -> Void
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(roots: [String: URL], onFailure: @escaping () -> Void) { self.roots = roots; self.onFailure = onFailure }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        guard let url = task.request.url, let host = url.host, let root = roots[host] else {
            task.didFailWithError(URLError(.badURL)); return
        }
        tasks[id] = Task { [weak self] in
            defer { self?.tasks[id] = nil }
            do {
                let (data, mime) = try await Task.detached(priority: .userInitiated) {
                    let path = url.path.hasPrefix("/__absolute__/") ? String(url.path.dropFirst("/__absolute__".count)) : String(url.path.dropFirst())
                    guard let file = SystemDictionaryResource.resolve(path, contentsURL: root) else { throw URLError(.fileDoesNotExist) }
                    return (try Data(contentsOf: file), UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
                }.value
                guard !Task.isCancelled else { return }
                task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
                task.didReceive(data); task.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                self?.onFailure(); task.didFailWithError(error)
            }
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(task))?.cancel()
    }
}
