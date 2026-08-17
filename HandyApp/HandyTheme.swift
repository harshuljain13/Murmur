import SwiftUI

/// Handy brand palette (from handy.computer / cjpais/handy theme.css).
enum Handy {
    // Warm dark background used across the app
    static let background   = Color(red: 0x2c/255, green: 0x2b/255, blue: 0x29/255) // #2c2b29
    static let surface      = Color(red: 0x38/255, green: 0x36/255, blue: 0x34/255) // slightly lighter
    static let cream        = Color(red: 0xfb/255, green: 0xfb/255, blue: 0xfb/255) // #fbfbfb text

    // Signature pinks
    static let pink         = Color(red: 0xf2/255, green: 0x8c/255, blue: 0xbb/255) // #f28cbb logo
    static let pinkDeep     = Color(red: 0xda/255, green: 0x58/255, blue: 0x93/255) // #da5893 UI accent
    static let pinkLight    = Color(red: 0xfa/255, green: 0xa2/255, blue: 0xca/255) // #faa2ca

    static let warning      = Color(red: 0xfb/255, green: 0xbf/255, blue: 0x24/255)
    static let error        = Color(red: 0xf8/255, green: 0x71/255, blue: 0x71/255)

    static func text(_ opacity: Double = 1) -> Color { cream.opacity(opacity) }
}
