import Foundation

/// Where a landmark on the island leads.
enum IslandDestination: String, CaseIterable, Sendable {
    case campaign
    case arena
    case summon
    case collection
    case settings
    /// The Hall of Ka: power-up, evolution and awakening (`TrainingView`).
    case training
}

/// A tappable place on the island.
///
/// The island is a painting with hotspots, not a scene: `anchor` is the centre
/// of the landmark's footprint in `island_bg.png`, normalised to 0...1 in both
/// axes, so the same data works at any screen size once the painting's
/// on-screen frame is known (`IslandView.fill`). The positions are mirrored in
/// `tools/island.py`, which paints a stone footprint under each one; move them
/// together.
struct Landmark: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var destination: IslandDestination
    var anchor: CGPoint
    /// Player level at which the landmark opens.
    var unlockLevel: Int
    /// Player levels at which the building takes its next look. Tier I is the
    /// starting state; each threshold passed adds one.
    var upgradeLevels: [Int]
    var accentHex: String

    func isUnlocked(atLevel level: Int) -> Bool { level >= unlockLevel }

    func tier(atLevel level: Int) -> Int { 1 + upgradeLevels.filter { level >= $0 }.count }
}

enum IslandDatabase {
    static let landmarks: [Landmark] = [
        Landmark(
            id: "circle",
            title: "Summoning Circle",
            subtitle: "Call a god out of the Duat",
            systemImage: "sparkles",
            destination: .summon,
            anchor: CGPoint(x: 0.44, y: 0.48),
            unlockLevel: 1,
            upgradeLevels: [8, 20],
            accentHex: "#7FE0FF"
        ),
        Landmark(
            id: "gate",
            title: "Gate of the Duat",
            subtitle: "The campaign",
            systemImage: "map.fill",
            destination: .campaign,
            anchor: CGPoint(x: 0.26, y: 0.64),
            unlockLevel: 1,
            upgradeLevels: [10, 25],
            accentHex: "#F2A03C"
        ),
        Landmark(
            id: "arena",
            title: "Arena of Souls",
            subtitle: "Other summoners' defences",
            systemImage: "trophy.fill",
            destination: .arena,
            anchor: CGPoint(x: 0.74, y: 0.63),
            unlockLevel: 1,
            upgradeLevels: [12, 30],
            accentHex: "#FF5B57"
        ),
        Landmark(
            id: "hall",
            title: "Hall of Ka",
            subtitle: "Power up, evolve, awaken",
            systemImage: "person.3.fill",
            destination: .training,
            anchor: CGPoint(x: 0.16, y: 0.36),
            unlockLevel: 1,
            upgradeLevels: [6, 15],
            accentHex: "#F5D57A"
        ),
        Landmark(
            id: "obelisk",
            title: "Obelisk",
            subtitle: "Account, sound, assets",
            systemImage: "gearshape.fill",
            destination: .settings,
            anchor: CGPoint(x: 0.89, y: 0.47),
            unlockLevel: 1,
            upgradeLevels: [],
            accentHex: "#9E97C4"
        )
    ]
}
