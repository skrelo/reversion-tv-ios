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
}
