import Foundation

/// A modifier key held while scrolling.
package enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case command, option, control

    /// `NSEvent.ModifierFlags` / `CGEventFlags` bit.
    package var flag: UInt64 {
        switch self {
        case .command: 1 << 20
        case .option: 1 << 19
        case .control: 1 << 18
        }
    }

    package var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        }
    }

    /// From a Mac key code of either side's key.
    package init?(keyCode: Int) {
        switch keyCode {
        case 55, 54: self = .command
        case 58, 61: self = .option
        case 59, 62: self = .control
        default: return nil
        }
    }
}

/// An app, by bundle ID, with what's needed to show it.
package struct AppRef: Codable, Hashable, Identifiable, Sendable {
    package var bundleID: String
    package var name: String
    package var path: String?

    package init(bundleID: String, name: String, path: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }

    package var id: String { bundleID }
}

/// Smooth scrolling for mouse wheels. Trackpads and other devices that scroll smoothly
/// themselves are left alone.
package struct SmoothScrolling: Codable, Equatable, Sendable {
    package var enabled = false
    /// Pixels a notch scrolls while the wheel turns slowly.
    package var distance = 144.0
    /// Seconds until a notch's glide is 95% done.
    package var glide = 0.64
    /// How much farther notches go while the wheel spins fast: 0 not at all, up to 2.
    package var acceleration = 1.0
    package var reverseVertical = false
    package var reverseHorizontal = false
    /// Held for notches that go `fasterBoost` times as far.
    package var fasterKey: ModifierKey? = .option
    /// Held to scroll as the wheel does by itself, e.g. so ⌘-scroll zooms as usual.
    package var plainKey: ModifierKey? = .command
    /// Apps that get the wheel's own scrolling.
    package var excludedApps: [AppRef] = []

    package static let distances = 20.0...400.0
    package static let glides = 0.1...1.5
    package static let accelerations = 0.0...2.0
    package static let fasterBoost = 5.0

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, distance, glide, acceleration, reverseVertical, reverseHorizontal, fasterKey, plainKey, excludedApps
    }

    /// Fields missing from older settings keep their defaults.
    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SmoothScrolling()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? defaults.distance
        glide = try container.decodeIfPresent(Double.self, forKey: .glide) ?? defaults.glide
        acceleration = try container.decodeIfPresent(Double.self, forKey: .acceleration) ?? defaults.acceleration
        reverseVertical = try container.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? defaults.reverseVertical
        reverseHorizontal = try container.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? defaults.reverseHorizontal
        // A key set to none is stored as null, which must stay none.
        fasterKey = container.contains(.fasterKey)
            ? try container.decodeIfPresent(ModifierKey.self, forKey: .fasterKey) : defaults.fasterKey
        plainKey = container.contains(.plainKey)
            ? try container.decodeIfPresent(ModifierKey.self, forKey: .plainKey) : defaults.plainKey
        excludedApps = try container.decodeIfPresent([AppRef].self, forKey: .excludedApps) ?? defaults.excludedApps
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(distance, forKey: .distance)
        try container.encode(glide, forKey: .glide)
        try container.encode(acceleration, forKey: .acceleration)
        try container.encode(reverseVertical, forKey: .reverseVertical)
        try container.encode(reverseHorizontal, forKey: .reverseHorizontal)
        try container.encode(fasterKey, forKey: .fasterKey)
        try container.encode(plainKey, forKey: .plainKey)
        try container.encode(excludedApps, forKey: .excludedApps)
    }

    package func excludes(_ bundleID: String?) -> Bool {
        bundleID.map { id in excludedApps.contains { $0.bundleID == id } } ?? false
    }
}
