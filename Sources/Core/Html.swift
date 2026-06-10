import Foundation

enum Html {
    /// Strip tags and decode the handful of entities that show up in
    /// descriptions, collapsing whitespace. TV can't render rich text (§12).
    static func strip(_ html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        var text = html
        // Block tags → newlines so paragraphs don't run together.
        for tag in ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
                        "&#39;": "'", "&rsquo;": "’", "&lsquo;": "‘",
                        "&ldquo;": "“", "&rdquo;": "”", "&nbsp;": " ", "&mdash;": "—"]
        for (k, v) in entities { text = text.replacingOccurrences(of: k, with: v) }
        let lines = text.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Pull the first openable http(s) link out of a TipTap HTML body
    /// (§9.6/§9.8). Prefers an explicit `<a href>`, normalizes scheme-less
    /// hrefs to https, then falls back to a bare URL or `www.` form. Returns
    /// nil when there's no web link. Used for the "Scan to open" QR.
    static func firstLink(_ input: String?) -> String? {
        guard let input, !input.isEmpty else { return nil }

        // Explicit <a href="…"> first.
        if let re = try? NSRegularExpression(pattern: "<a[^>]+href\\s*=\\s*[\"']([^\"']+)[\"']",
                                             options: [.caseInsensitive]) {
            let range = NSRange(input.startIndex..., in: input)
            for match in re.matches(in: input, range: range) {
                guard let r = Range(match.range(at: 1), in: input) else { continue }
                let href = input[r].trimmingCharacters(in: .whitespaces)
                if href.isEmpty { continue }
                if href.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil {
                    return href
                }
                // Scheme-less ("example.com") → https; skip mailto:/tel:.
                if !href.contains(":") {
                    return "https://" + href.replacingOccurrences(of: "^/+", with: "", options: .regularExpression)
                }
            }
        }

        if let r = input.range(of: "https?://[^\\s<>\"')]+", options: [.regularExpression, .caseInsensitive]) {
            return String(input[r])
        }
        if let r = input.range(of: "www\\.[^\\s<>\"')]+", options: [.regularExpression, .caseInsensitive]) {
            return "https://" + input[r]
        }
        return nil
    }

    /// Every `<img src>` URL in an HTML body, in document order (§9.6/§9.8).
    /// Image-vs-link is decided by the **tag**, so callers collect these and
    /// strip them before pulling a webpage link (never sniff the URL string).
    static func imageSources(_ input: String?) -> [String] {
        guard let input, !input.isEmpty else { return [] }
        guard let re = try? NSRegularExpression(pattern: "<img[^>]+src\\s*=\\s*[\"']([^\"']+)[\"']",
                                                options: [.caseInsensitive]) else { return [] }
        let range = NSRange(input.startIndex..., in: input)
        var out: [String] = []
        for match in re.matches(in: input, range: range) {
            guard let r = Range(match.range(at: 1), in: input) else { continue }
            let src = input[r].trimmingCharacters(in: .whitespaces)
            if !src.isEmpty { out.append(String(src)) }
        }
        return out
    }

    /// `firstLink` with `<img>` tags removed first, so an image's `src` is never
    /// mistaken for a webpage link (§9.6/§9.8 — decide by the tag, not the URL).
    static func firstWebLink(_ input: String?) -> String? {
        guard let input else { return nil }
        let noImg = input.replacingOccurrences(
            of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        return firstLink(noImg)
    }

    /// `H:MM:SS` / `M:SS` timecode for a second count (§9.16).
    static func timecode(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
