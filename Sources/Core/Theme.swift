import SwiftUI

/// Shared brand palette. Mirrors the Tizen/Android TV look: deep navy
/// canvas, warm gold accent, off-white text.
enum Theme {
    /// Page background — deep navy (#131A24).
    static let bg = Color(red: 0x13 / 255, green: 0x1A / 255, blue: 0x24 / 255)
    /// Slightly lighter navy for surfaces/cards.
    static let surface = Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x30 / 255)
    /// Brand gold accent (#D4B033).
    static let gold = Color(red: 0xD4 / 255, green: 0xB0 / 255, blue: 0x33 / 255)
    /// Primary text — near white.
    static let text = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255)
    /// Dimmed/secondary text.
    static let textDim = Color(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xB5 / 255)
    /// Watch-progress bar (Netflix-style red).
    static let progress = Color(red: 0xE5 / 255, green: 0x2A / 255, blue: 0x2A / 255)
}
