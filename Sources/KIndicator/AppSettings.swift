import Foundation

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, iconAndName, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "Icon"
        case .iconAndName: "Icon and name"
        case .name: "Name"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    /// Default V6 Ultra keymap: Mac base, Mac Fn, Windows base, Windows Fn.
    static let defaultLayerNames = ["Mac", "Mac Fn", "Win", "Win Fn"]
    /// An SF Symbol name, or up to three characters drawn in a square (see `MenuBarImage.icon`).
    static let defaultLayerIcons = ["sun.max", "Fn", "W", "Fn"]
    static let pollIntervals = [100, 250, 500, 1000]

    private enum Key {
        static let layerNames = "layerNames"
        static let layerIcons = "layerIcons"
        static let connection = "connection"
        static let menuBarStyle = "menuBarStyle"
        static let pollIntervalMs = "pollIntervalMs"
        static let layerLighting = "layerLighting"
        static let layerLightingEnabled = "layerLightingEnabled"
    }

    private let defaults = UserDefaults.standard

    @Published var layerNames: [String] {
        didSet { defaults.set(layerNames, forKey: Key.layerNames) }
    }
    @Published var layerIcons: [String] {
        didSet { defaults.set(layerIcons, forKey: Key.layerIcons) }
    }
    @Published var connection: ConnectionPreference {
        didSet { defaults.set(connection.rawValue, forKey: Key.connection) }
    }
    @Published var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) }
    }
    @Published var pollIntervalMs: Int {
        didSet { defaults.set(pollIntervalMs, forKey: Key.pollIntervalMs) }
    }
    /// Lighting per layer; nil keeps the saved lighting.
    @Published var layerLighting: [LayerLighting?] {
        didSet { defaults.set(try? JSONEncoder().encode(layerLighting), forKey: Key.layerLighting) }
    }
    @Published var layerLightingEnabled: Bool {
        didSet { defaults.set(layerLightingEnabled, forKey: Key.layerLightingEnabled) }
    }

    init() {
        layerNames = defaults.stringArray(forKey: Key.layerNames) ?? Self.defaultLayerNames
        layerIcons = defaults.stringArray(forKey: Key.layerIcons) ?? Self.defaultLayerIcons
        connection = defaults.string(forKey: Key.connection).flatMap(ConnectionPreference.init) ?? .auto
        menuBarStyle = defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init) ?? .icon
        let interval = defaults.integer(forKey: Key.pollIntervalMs)
        pollIntervalMs = Self.pollIntervals.contains(interval) ? interval : 250
        layerLighting = defaults.data(forKey: Key.layerLighting)
            .flatMap { try? JSONDecoder().decode([LayerLighting?].self, from: $0) } ?? []
        layerLightingEnabled = defaults.object(forKey: Key.layerLightingEnabled) as? Bool ?? true
    }

    var hasLayerLighting: Bool { layerLighting.contains { $0 != nil } }

    func lighting(for layer: Int) -> LayerLighting? {
        layer < layerLighting.count ? layerLighting[layer] : nil
    }

    func setLighting(_ lighting: LayerLighting?, for layer: Int) {
        var list = layerLighting
        while list.count <= layer { list.append(nil) }
        list[layer] = lighting
        layerLighting = list
    }

    func name(for layer: Int) -> String {
        Self.value(at: layer, in: layerNames) ?? Self.placeholderName(for: layer)
    }

    func icon(for layer: Int) -> String {
        Self.value(at: layer, in: layerIcons) ?? Self.placeholderIcon(for: layer)
    }

    func setName(_ name: String, for layer: Int) {
        layerNames = Self.replacing(layer, with: name, in: layerNames)
    }

    func setIcon(_ icon: String, for layer: Int) {
        layerIcons = Self.replacing(layer, with: icon, in: layerIcons)
    }

    static func placeholderName(for layer: Int) -> String {
        layer < defaultLayerNames.count ? defaultLayerNames[layer] : "Layer \(layer)"
    }

    static func placeholderIcon(for layer: Int) -> String {
        layer < defaultLayerIcons.count ? defaultLayerIcons[layer] : "\(layer)"
    }

    /// The trimmed entry, or nil when it's missing or blank.
    private static func value(at index: Int, in values: [String]) -> String? {
        let value = index < values.count ? values[index].trimmingCharacters(in: .whitespaces) : ""
        return value.isEmpty ? nil : value
    }

    private static func replacing(_ index: Int, with value: String, in values: [String]) -> [String] {
        var values = values
        while values.count <= index { values.append("") }
        values[index] = value
        return values
    }
}
