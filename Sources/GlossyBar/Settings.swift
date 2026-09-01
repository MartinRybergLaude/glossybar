import AppKit

final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("GlossyBarSettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let tone = "tone"
        static let heightAdjustment = "heightAdjustment"
    }

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.tone: Tone.auto.rawValue,
            Key.heightAdjustment: 0.0,
        ])
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled); post() }
    }

    /// Points added to the menu bar height. Not in the menu — the system's own
    /// answer moves around a little, so this is the escape hatch.
    var heightAdjustment: Double {
        defaults.double(forKey: Key.heightAdjustment)
    }

    /// Which variant to use. Auto follows the menu bar's own appearance.
    enum Tone: String, CaseIterable {
        case auto, light, dark

        var name: String {
            switch self {
            case .auto: return "Automatic"
            case .light: return "Light Bar"
            case .dark: return "Dark Bar"
            }
        }
    }

    var tone: Tone {
        get { Tone(rawValue: defaults.string(forKey: Key.tone) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.tone); post() }
    }

    /// Resolves the tone, falling back to what the menu bar actually looks like.
    func polarity(measured: BarPolarity) -> BarPolarity {
        switch tone {
        case .auto: return measured
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func post() {
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }
}
