import SwiftUI

public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

public enum Theme {
    public static let background = Color(hex: 0x201E1B)
    public static let clay = Color(hex: 0xD97757)
    public static let clayDim = Color(hex: 0xA8664D)
    public static let clayDimmer = Color(hex: 0x7A5040)
    public static let amber = Color(hex: 0xE0B25C)
    public static let textBright = Color(hex: 0xF5EFE6)
    public static let textPrimary = Color(hex: 0xEDE6DC)
    public static let textSecondary = Color(hex: 0xC9BFB2)
    public static let textMuted = Color(hex: 0x8A837A)
    public static let textDim = Color(hex: 0x6E675E)
    public static let track = Color(hex: 0x33302C)
    public static let barQuiet = Color(hex: 0x3A3733)
    public static let barDim = Color(hex: 0x5A4A40)
    public static let tipBackground = Color(hex: 0x2A2723)
}
