import SwiftUI

/// Murmur brand palette.
enum Murmur {
    // Neutral dark background used across the app
    static let background   = Color(red: 0x1a/255, green: 0x1a/255, blue: 0x1f/255) // #1a1a1f
    static let surface      = Color(red: 0x26/255, green: 0x26/255, blue: 0x2d/255) // slightly lighter
    static let cream        = Color(red: 0xf6/255, green: 0xf6/255, blue: 0xf9/255) // #f6f6f9 text

    // Signature violets
    static let accent       = Color(red: 0xa3/255, green: 0x93/255, blue: 0xf7/255) // #a393f7 logo
    static let accentDeep   = Color(red: 0x7c/255, green: 0x67/255, blue: 0xea/255) // #7c67ea UI accent
    static let accentSoft   = Color(red: 0xc3/255, green: 0xb7/255, blue: 0xfb/255) // #c3b7fb

    static let warning      = Color(red: 0xfb/255, green: 0xbf/255, blue: 0x24/255)
    static let error        = Color(red: 0xf8/255, green: 0x71/255, blue: 0x71/255)

    static func text(_ opacity: Double = 1) -> Color { cream.opacity(opacity) }
}
