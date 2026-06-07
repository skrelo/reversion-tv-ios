import SwiftUI

/// Cloudflare image right-sizing (§2 Polish): rewrite delivery URLs to a
/// capped width so rails of cards don't decode full-resolution sources.
/// Anything that isn't a known Cloudflare host is returned unchanged.
enum ImageURL {
    /// Card art renders ~300–345 pt wide; request ~450 px (matches Tizen).
    static let cardWidth = 450
    /// Wordmarks ~720 px.
    static let wordmarkWidth = 720

    static func sized(_ url: String?, width: Int) -> URL? {
        guard let url, !url.isEmpty, var comps = URLComponents(string: url),
              let host = comps.host else { return url.flatMap(URL.init(string:)) }

        if host == "imagedelivery.net" {
            // Path: /<hash>/<id>/<variant> — swap the trailing variant.
            var parts = comps.path.split(separator: "/").map(String.init)
            if parts.count >= 3 {
                parts[parts.count - 1] = "w=\(width),quality=85,format=auto"
                comps.path = "/" + parts.joined(separator: "/")
                comps.query = nil
                return comps.url
            }
        } else if host.hasSuffix("cloudflarestream.com"), comps.path.contains("/thumbnails/") {
            var q = comps.queryItems ?? []
            q.removeAll { $0.name == "width" }
            q.append(URLQueryItem(name: "width", value: String(width)))
            comps.queryItems = q
            return comps.url
        }
        return URL(string: url)
    }
}

/// Remote image with a graceful placeholder; keeps the previous image until
/// the next loads where the parent drives it (used by the hero spotlight).
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure, .empty:
                Theme.surface
            @unknown default:
                Theme.surface
            }
        }
    }
}
