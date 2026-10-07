import SwiftUI

/// Murmur brand palette.
enum Murmur {
    // Neutral dark background used across the app
    static let background   = Color(red: 0x1a/255, green: 0x1a/255, blue: 0x1f/255) // #1a1a1f
    static let surface      = Color(red: 0x26/255, green: 0x26/255, blue: 0x2d/255) // slightly lighter
    static let cream        = Color(red: 0xf6/255, green: 0xf6/255, blue: 0xf9/255) // #f6f6f9 text

    // Signature mints — drawn from the logo gradient (#7ef0dd → #2dd4bf)
    static let accent       = Color(red: 0x5e/255, green: 0xea/255, blue: 0xd4/255) // #5eead4 foreground on dark
    static let accentDeep   = Color(red: 0x0f/255, green: 0x76/255, blue: 0x6e/255) // #0f766e fills, carries white text
    static let accentSoft   = Color(red: 0xa7/255, green: 0xf3/255, blue: 0xe4/255) // #a7f3e4 tinted chips

    static let warning      = Color(red: 0xfb/255, green: 0xbf/255, blue: 0x24/255)
    static let error        = Color(red: 0xf8/255, green: 0x71/255, blue: 0x71/255)

    static func text(_ opacity: Double = 1) -> Color { cream.opacity(opacity) }
}
