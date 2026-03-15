import Foundation

enum OverlayDisplayMode: String, CaseIterable, Identifiable {
    case classic
    case island

    static let userDefaultsKey = "overlay_display_mode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .island: return "Island"
        }
    }

    static var stored: OverlayDisplayMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey)
        return OverlayDisplayMode(rawValue: raw ?? "") ?? .classic
    }
}
