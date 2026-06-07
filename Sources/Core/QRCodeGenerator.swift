import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Generates crisp QR images on-device (no network, no dependency).
/// Used for: pairing (encode the raw code), phone-compose note companion
/// (encode `scan_url`), and "scan to open" link QRs in the player (§12).
enum QRCodeGenerator {
    private static let context = CIContext()

    /// Returns a navy-on-white QR `UIImage` for `string`, scaled to roughly
    /// `size` points. Returns nil if generation fails.
    static func image(from string: String, size: CGFloat = 760) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = max(1, size / output.extent.width)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Recolor: dark = navy (#131A24), light = white.
        let colored = scaled.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0x13 / 255, green: 0x1A / 255, blue: 0x24 / 255),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1),
        ])

        guard let cg = context.createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
