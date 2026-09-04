import Foundation

/// The mythologies a unit can belong to.
///
/// Pantheon is deliberately separate from `Element`: element drives the combat
/// triangle, pantheon drives leader skills, campaign realms, banner grouping and
/// set bonuses. Adding a mythology means adding a case here and a realm in
/// `StageDatabase` — nothing in the battle engine changes.
enum Pantheon: String, Codable, CaseIterable, Identifiable, Sendable {
    case greek
    case roman
    case egyptian
    case norse
    case chinese
    case japanese
    case hindu
    case mesopotamian
    case aztec
    case celtic
    case slavic
    case yoruba
    case polynesian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .greek: return "Greek"
        case .roman: return "Roman"
        case .egyptian: return "Egyptian"
        case .norse: return "Norse"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .hindu: return "Hindu"
        case .mesopotamian: return "Mesopotamian"
        case .aztec: return "Aztec"
        case .celtic: return "Celtic"
        case .slavic: return "Slavic"
        case .yoruba: return "Yoruba"
        case .polynesian: return "Polynesian"
        }
    }

    /// Name of the realm this pantheon's campaign chapters live in.
    var realmName: String {
        switch self {
        case .greek: return "Olympus"
        case .roman: return "The Seven Hills"
        case .egyptian: return "The Duat"
        case .norse: return "Yggdrasil"
        case .chinese: return "The Jade Court"
        case .japanese: return "Takamagahara"
        case .hindu: return "Svarga"
        case .mesopotamian: return "The Ziggurat"
        case .aztec: return "Mictlan"
        case .celtic: return "Tír na nÓg"
        case .slavic: return "The Rodnovery"
        case .yoruba: return "Ilé Ọ̀run"
        case .polynesian: return "Te Pō"
        }
    }

    /// Hex accent used by the UI for cards, banners and realm headers.
    var accentHex: String {
        switch self {
        case .greek: return "#E8C86A"
        case .roman: return "#C0503C"
        case .egyptian: return "#2FA8A0"
        case .norse: return "#7FA8D8"
        case .chinese: return "#D8453F"
        case .japanese: return "#E4787F"
        case .hindu: return "#E8913C"
        case .mesopotamian: return "#B08A4F"
        case .aztec: return "#4FAE6B"
        case .celtic: return "#5FA97E"
        case .slavic: return "#8C7FC0"
        case .yoruba: return "#C86BB0"
        case .polynesian: return "#3F8FC0"
        }
    }

    /// Pantheons that ship with playable content. The rest are declared so that
    /// data files, art briefs and save games can reference them before release.
    ///
    /// Egypt is first because the launch family is Egyptian. Adding the next one
    /// is a case above, a set of blueprints, and a chapter in `StageDatabase` —
    /// leader skills already scope by pantheon, so "Greek allies gain 33% ATK"
    /// is one line of data.
    static var live: [Pantheon] { [.egyptian] }
}
