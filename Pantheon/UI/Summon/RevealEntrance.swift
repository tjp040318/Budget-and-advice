import SceneKit
import UIKit

// MARK: - The summoned figure's entrance (2026-09-24, Docs/FEEL.md W2.4)
//
// The genre never reveals a unit idling. Ours arrived on the beam already in
// its idle, 115 victory clips unused. Now, at the flash:
//
//   1. the scene HOLDS for 70 ms (110 ms for a 5★) under the white — every
//      clip, particle and action stopped, the classic hit-stop
//      (`SCNScene.isPaused`, the fight's own freeze, `Juice.impact`);
//   2. the figure plays its VICTORY clip once — the part of it that faces
//      the lens (`RevealEntranceCut`) — and blends back into its idle;
//   3. the camera kicks back 4% of its distance and springs home;
//   4. the shockwave flipbook lies flat under its feet, and a 5★ gets the
//      sunburst standing behind it;
//   5. the name slams on the clip's HIGH POINT, reported by the scene's own
//      clock (`SummonStageView.Coordinator.apexReached`), never on a timer.
//
// Everything the flash shows for the first time is drawn once in the stage's
// warm-up (the run-221 lesson): the clip is parsed and wrapped in its player
// in `makeUIView`, and the two flipbook planes stand in the scene at full
// strength through the warm-up's frames before they go out of sight.

/// How the reveal plays one victory clip: which seconds of it, where its
/// high point is, and how the figure stands while it plays.
///
/// MEASURED, not guessed (2026-09-24): every one of the 115 `*_victory.usdz`
/// in the bundle was read with usd-core and posed frame by frame (the hips,
/// the hands, the shoulders' line, the skinned carrier's top). The motion
/// palette (Docs/MOTION.md) dealt every family one of three presets, and
/// each preset has one length, which SceneKit reports as the clip's
/// duration (run 246's console: 1.90, 3.93 and 3.87 s):
///
/// - **298 Cheer** (34 families, 58 frames, 1.90 s): a crouch, then a hop
///   with both arms up; the hands top out at 1.11 of the height at 0.70 s
///   (0.98–1.18 across families); the chest never turns past 41°. Played
///   whole.
/// - **412 Victory** (53 families, 119 frames, 3.93 s): the arms spread
///   and rise (0.83 → 0.97 of the height by 0.4 s), then the figure turns
///   58° to its left, back, 56° to its right, back and away again. The
///   first 1.6 s — the raise, one turn and the return to the front — is
///   the entrance; the rest turns the god's back on the lens.
/// - **88 Chest Pound Taunt** (28 families, 117 frames, 3.87 s): it opens
///   in a crouch turned 55° away (0–1.1 s), turns to the front, and pounds
///   the chest at 2.1–2.9 s. The entrance is 1.1–3.35 s, the high point the
///   fists striking, at 2.25 s.
///
/// No clip moves the hips over the floor (the pipeline locks the root:
/// 0.00 m of travel on all 115), so none steps off the dais. Each preset's
/// `stance` turns the figure so the chest's facing over the played window
/// averages a few degrees TOWARD the words on the right, the subject
/// looking into its open space: +5° for the cheer, +38° for 412 (whose
/// window swings to −58° and back), −11° for the chest pound; the extremes
/// across every family stay inside −48°…+56°.
struct RevealEntranceCut: Equatable {
    /// The motion palette's name for the preset, for the console line.
    let preset: String
    /// Seconds into the clip the entrance starts from.
    let start: TimeInterval
    /// Seconds into the clip the entrance lets go: the blend back into the
    /// idle (`RevealEntrance.blendOut`) begins here.
    let end: TimeInterval
    /// Seconds into the clip of its high point: the name slams on it.
    let apex: TimeInterval
    /// The figure's yaw while it plays, in radians; positive turns it toward
    /// the words.
    let stance: Float
}

/// What the stage tells the reveal when the figure is first drawn, so the
/// name card can plan its stars to land before the name does.
struct RevealEntrancePlan: Equatable {
    /// Seconds from the figure's first drawn frame to the clip's high point:
    /// the hold, then the cut's apex. The name itself waits for the stage to
    /// report the high point (`onApex`); this only paces the stars.
    var apexDelay: TimeInterval
    /// Whether a victory clip plays.
    var plays: Bool
}

enum RevealEntrance {
    static let cheer = RevealEntranceCut(preset: "298 Cheer", start: 0, end: 1.45, apex: 0.68, stance: 0.095)
    static let victory = RevealEntranceCut(preset: "412 Victory", start: 0, end: 1.6, apex: 0.45, stance: 0.66)
    static let chestPound = RevealEntranceCut(preset: "88 Chest Pound Taunt", start: 1.1, end: 3.35, apex: 2.25, stance: -0.2)

    /// The presets by the length SceneKit reports for their clip.
    static let presets: [(length: TimeInterval, cut: RevealEntranceCut)] = [
        (1.9, cheer),
        (3.9333, victory),
        (3.8667, chestPound),
    ]

    /// How close a clip's length must be to a preset's to be that preset:
    /// the two long ones are 0.067 s apart.
    static let lengthTolerance: TimeInterval = 0.02

    /// The cut for a victory clip of `length` seconds: its preset's, or for
    /// a clip no preset made (a bespoke victory to come), its first seconds
    /// facing as the family was rigged, the high point a third of the way.
    static func cut(forClipLength length: TimeInterval) -> RevealEntranceCut {
        for preset in presets where abs(preset.length - length) <= lengthTolerance {
            return preset.cut
        }
        return unmeasured(length)
    }

    static func unmeasured(_ length: TimeInterval) -> RevealEntranceCut {
        let end: TimeInterval = max(0.4, min(2.2, length - blendOut))
        let third: TimeInterval = length * 0.35
        let apex: TimeInterval = min(end * 0.6, max(0.3, min(0.6, third)))
        return RevealEntranceCut(preset: "unmeasured", start: 0, end: end, apex: apex, stance: 0)
    }

    /// Families whose victory the reveal never plays: none today (no clip
    /// leaves the dais and the cut keeps every one facing the lens). A
    /// family whose victory is judged wrong on the reveal's frame goes
    /// here by its clip asset's name and enters as it did before, idling.
    static let denied: Set<String> = []

    /// The clip blends in over the flash's first frames and back into the
    /// idle when its window ends.
    static let blendIn: TimeInterval = 0.18
    static let blendOut: TimeInterval = 0.45

    /// The hold at the flash: 70 ms, 110 ms for a 5★ (Vlambeer's pause on
    /// a big moment; Final Fight's six frames).
    static func hold(stars: Int) -> TimeInterval {
        stars >= 5 ? 0.11 : 0.07
    }

    /// Where the name lands when no clip plays: the flash clearing.
    static let defaultApex: TimeInterval = 0.4

    /// The camera's kick: back along its line of sight by this share of its
    /// distance, fast, then home on a spring with a small overshoot.
    static let kickShare: Float = 0.04
    static let kickOut: TimeInterval = 0.07
    static let kickBack: TimeInterval = 0.6

    /// The kick's return as an `SCNAction` timing curve: a damped spring
    /// from 0 to 1 (damping 0.66, overshooting 6% at 70% of the way) with
    /// its last 2% eased in, so it ends exactly on 1. A pure function: the
    /// renderer calls it on its own thread.
    static func kickReturn(_ progress: Float) -> Float {
        let t: Float = min(1, max(0, progress))
        let damping: Float = 0.66
        let length: Float = Float(kickBack)
        let natural: Float = 4 / (damping * length)
        let ringing: Float = natural * (1 - damping * damping).squareRoot()
        func spring(_ at: Float) -> Float {
            let seconds: Float = at * length
            let envelope: Float = exp(-damping * natural * seconds)
            let wave: Float = cos(ringing * seconds) + (damping * natural / ringing) * sin(ringing * seconds)
            return 1 - envelope * wave
        }
        let residual: Float = spring(1) - 1
        return spring(t) - residual * t * t * t
    }

    /// Keys of the entrance's player and of its clock on the figure.
    static let playerKey = "reveal_entrance"
    static let clockKey = "reveal_entrance_clock"
    static let kickKey = "reveal_kick"

    /// The flat ring under the feet, in figure heights across, and how long
    /// its sixteen frames take.
    static let ringSide: CGFloat = 1.9
    static let ringLife: TimeInterval = 0.8
    /// A 5★'s sunburst behind the figure: its size and centre in figure
    /// heights, how far behind the figure it stands, and its frames' pace.
    static let burstSide: CGFloat = 2.2
    static let burstCentre: Float = 0.55
    static let burstDepth: Float = -0.9
    static let burstDelay: TimeInterval = 0.03
    static let burstLife: TimeInterval = 0.95

    /// `-tour-reveal-hold apex` (DEBUG, the CI's frame of the entrance):
    /// the scene stops on the clip's high point and stays there, the name
    /// card finishing over it, so a screenshot that lands seconds late
    /// still shows the pose the name slams on.
    static var tourHoldsAtApex: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal-hold"), at + 1 < args.count else { return false }
        return args[at + 1] == "apex"
        #else
        return false
        #endif
    }

    /// Under the CI tour: the entrance says where it is on the console
    /// (`[TourCue] reveal-apex`).
    static var touring: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-tour")
        #else
        return false
        #endif
    }
}

/// A victory clip wrapped for the entrance in `makeUIView`, so the flash
/// only adds and plays it: parsed (from the model cache, which the summon
/// room's warm pass has usually filled), copied, and given its window.
final class RevealEntranceClip {
    let cut: RevealEntranceCut
    let length: TimeInterval
    let player: SCNAnimationPlayer

    init(clip: CAAnimation) {
        let copy: CAAnimation = (clip.copy() as? CAAnimation) ?? clip
        let length: TimeInterval = copy.duration
        let cut: RevealEntranceCut = RevealEntrance.cut(forClipLength: length)
        let animation = SCNAnimation(caAnimation: copy)
        animation.usesSceneTimeBase = false
        animation.repeatCount = 1
        animation.isRemovedOnCompletion = false
        // Holds its last frame should a blend run past the clip's end.
        animation.fillsForward = true
        animation.blendInDuration = RevealEntrance.blendIn
        animation.blendOutDuration = RevealEntrance.blendOut
        animation.timeOffset = cut.start
        self.cut = cut
        self.length = length
        self.player = SCNAnimationPlayer(animation: animation)
    }

    /// Seconds from the clip's start (the hold's release) to its high point,
    /// and to the moment it lets go.
    var apexIn: TimeInterval { max(0, cut.apex - cut.start) }
    var endIn: TimeInterval {
        let played: TimeInterval = min(cut.end, length - 0.05) - cut.start
        return max(apexIn, played)
    }
}

// MARK: - The flipbooks on the dais

/// The painted sheets the entrance plays — `vfx_shockwave_sheet` flat under
/// the feet and `vfx_sunburst_sheet` standing behind a 5★ — cut once per
/// launch into sixteen premultiplied frames (about 4 MB a sheet, kept like
/// `LightningArt`'s), on a background queue when the summon room appears.
///
/// Planes, not particles, as the fight's ground ring is
/// (`VFXLibrary.groundFlipbook`): a plane can lie flat and can be faded into
/// the floor by what it is multiplied by. No shader modifier on either (the
/// run-235 rule): the floor fade is BAKED into the standing sheet's
/// `multiply`, as `VFXLibrary.standingFlipbook` bakes it. Both add light and
/// write no alpha (`colorBufferWriteMask` red, green, blue), because this
/// stage's view is transparent and an additive quad that writes its alpha
/// prints its own rectangle over the dusk behind (`makeUIView`'s note).
enum RevealFlipbook {
    static let ring = "shockwave"
    static let burst = "sunburst"

    private static let lock = NSLock()
    private static var cut: [String: [CGImage]] = [:]
    private static var cutting: Set<String> = []

    /// The cut is a cache that can be rebuilt, so it hears the memory
    /// warnings every other one does (`MemoryRelief`): dropped on one, and
    /// cut again for the next reveal. A stage already built keeps its own
    /// frames. Registered once, the first time the cut is asked for.
    private static let relief: Void = {
        MemoryRelief.observe { RevealFlipbook.purge() }
    }()

    /// Drops the cut frames.
    static func purge() {
        lock.lock()
        cut.removeAll()
        lock.unlock()
    }

    /// Cuts both sheets off the main thread, once: when the summon room
    /// appears (`RuneLinesArt.prepare`) and again when a reveal does.
    static func prepare() {
        _ = relief
        for name in [ring, burst] {
            lock.lock()
            let begin: Bool = cut[name] == nil && !cutting.contains(name)
            if begin { cutting.insert(name) }
            lock.unlock()
            guard begin else { continue }
            DispatchQueue.global(qos: .utility).async {
                let fresh: [CGImage] = cutSheet(name)
                lock.lock()
                if cut[name] == nil { cut[name] = fresh }
                cutting.remove(name)
                lock.unlock()
            }
        }
    }

    /// A sheet's frames: from the cut, or cut here and now when the stage is
    /// built before the background cut has finished. Empty when the sheet
    /// has not shipped, and then no plane is built.
    static func frames(_ name: String) -> [CGImage] {
        _ = relief
        lock.lock()
        let hit: [CGImage]? = cut[name]
        lock.unlock()
        if let hit { return hit }
        let fresh: [CGImage] = cutSheet(name)
        lock.lock()
        if cut[name] == nil { cut[name] = fresh }
        let kept: [CGImage] = cut[name] ?? fresh
        lock.unlock()
        return kept
    }

    private static func cutSheet(_ name: String) -> [CGImage] {
        guard let sheet = BundleArt.uncachedImage("vfx_\(name)_sheet")?.cgImage else { return [] }
        let side: Int = min(sheet.width, sheet.height) / 4
        guard side > 0 else { return [] }
        var cells: [CGImage] = []
        for row in 0..<4 {
            for column in 0..<4 {
                let cell = CGRect(x: column * side, y: row * side, width: side, height: side)
                guard let cropped = sheet.cropping(to: cell),
                      let drawn = premultiplied(cropped, side: side) else { continue }
                cells.append(drawn)
            }
        }
        return cells.count == 16 ? cells : []
    }

    /// A cell drawn over clear into a premultiplied bitmap of its own. The
    /// sheets ship unpremultiplied, and a plane drawn `.add` adds a pixel's
    /// colour whatever its alpha (`VFXLibrary.premultiplied`, run 236's white
    /// rectangle).
    private static func premultiplied(_ cell: CGImage, side: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cell, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    /// The shockwave, flat on the dais under the feet, a hair over the
    /// contact shadow. Built at full strength for the warm-up.
    static func groundRing(height: Float, tint: UIColor) -> (node: SCNNode, frames: [CGImage])? {
        let cells: [CGImage] = frames(ring)
        guard let first = cells.first else { return nil }
        let side: CGFloat = CGFloat(height) * RevealEntrance.ringSide
        let plane = SCNPlane(width: side, height: side)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = first
        material.multiply.contents = tint
        material.blendMode = .add
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.name = "reveal_ground_ring"
        // An SCNPlane faces +Z; a quarter turn back about X lays it face up.
        node.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        node.position = SCNVector3(0, 0.02, 0)
        node.renderingOrder = 6
        node.castsShadow = false
        return (node, cells)
    }

    /// A 5★'s sunburst, standing behind the figure and facing the lens,
    /// faded to nothing before the floor so the dais never cuts it with a
    /// line. Behind, so the figure's silhouette stays whole in front of it
    /// and the depth test keeps the body solid.
    static func standingBurst(height: Float, tint: UIColor) -> (node: SCNNode, frames: [CGImage])? {
        let cells: [CGImage] = frames(burst)
        guard let first = cells.first else { return nil }
        let side: Float = height * Float(RevealEntrance.burstSide)
        let centre: Float = height * RevealEntrance.burstCentre
        guard let mask = floorFade(tint: tint, side: side, centre: centre) else { return nil }
        let plane = SCNPlane(width: CGFloat(side), height: CGFloat(side))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = first
        material.multiply.contents = mask
        material.blendMode = .add
        material.colorBufferWriteMask = [.red, .green, .blue]
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.isDoubleSided = true
        plane.firstMaterial = material
        let node = SCNNode(geometry: plane)
        node.name = "reveal_sunburst"
        node.position = SCNVector3(0, centre, RevealEntrance.burstDepth)
        node.renderingOrder = 4
        node.castsShadow = false
        return (node, cells)
    }

    /// How far above the dais the standing sheet reaches full strength.
    static let floorFadeHeight: Float = 0.35

    /// The standing sheet's mask: one column of 64 rows, its top row the
    /// sheet's top, each the tint (its alpha folded into the colour) scaled
    /// by how far that row stands above the floor — nothing at the floor,
    /// all of it `floorFadeHeight` up, smoothstepped between. The reveal's
    /// camera looks very slightly UP at the figure, so the sheet stands
    /// square to it and a row's height is its place on the sheet.
    private static func floorFade(tint: UIColor, side: Float, centre: Float) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        tint.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let rows = 64
        var pixels = [UInt8](repeating: 255, count: rows * 4)
        for row in 0..<rows {
            let down: Float = (Float(row) + 0.5) / Float(rows)
            let height: Float = centre + (0.5 - down) * side
            let ramp: Float = min(1, max(0, height / floorFadeHeight))
            let smooth: Float = ramp * ramp * (3 - 2 * ramp)
            let strength: CGFloat = alpha * CGFloat(smooth) * 255
            let at = row * 4
            pixels[at] = UInt8(clamping: Int((red * strength).rounded()))
            pixels[at + 1] = UInt8(clamping: Int((green * strength).rounded()))
            pixels[at + 2] = UInt8(clamping: Int((blue * strength).rounded()))
            pixels[at + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: rows, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: space, bitmapInfo: info) else { return nil }
            return context.makeImage()
        }
    }
}

/// Steps the entrance's flipbook planes through their frames from the main
/// thread, as the fight's ground ring is stepped (never inside an
/// `SCNAction`: the arena's crash of 2026-09-15), on a `FrameTicker`. A
/// plane is at full strength while it plays — the pipeline the warm-up
/// compiled — and out of sight before and after.
final class RevealFlipbookPlayer {
    struct Track {
        let node: SCNNode
        let frames: [CGImage]
        let delay: CFTimeInterval
        let life: CFTimeInterval
    }

    private let tracks: [Track]
    private var shown: [Int]
    private var visible: [Bool]
    private var ticker: FrameTicker?
    private var began: CFTimeInterval = 0
    private(set) var hasStarted = false

    init(tracks: [Track]) {
        self.tracks = tracks
        self.shown = Array(repeating: 0, count: tracks.count)
        self.visible = Array(repeating: true, count: tracks.count)
    }

    /// Every plane out of sight (the warm-up is over, or the stage is going).
    func hideAll() {
        for index in tracks.indices where visible[index] {
            visible[index] = false
            tracks[index].node.opacity = 0
        }
    }

    func start() {
        guard !hasStarted, !tracks.isEmpty else { return }
        hasStarted = true
        began = CACurrentMediaTime()
        ticker = FrameTicker { [weak self] in
            self?.step() ?? false
        }
        _ = step()
    }

    /// One frame of every plane; false once all have played, which stops
    /// the tick.
    private func step() -> Bool {
        let elapsed: CFTimeInterval = CACurrentMediaTime() - began
        var playing = false
        for index in tracks.indices {
            let track = tracks[index]
            let local: CFTimeInterval = elapsed - track.delay
            let live: Bool = local >= 0 && local < track.life
            if live {
                playing = true
                let count: Int = track.frames.count
                let at: Int = min(count - 1, max(0, Int(local / track.life * Double(count))))
                if shown[index] != at {
                    shown[index] = at
                    track.node.geometry?.firstMaterial?.diffuse.contents = track.frames[at]
                }
            } else if local < 0 {
                playing = true
            }
            if visible[index] != live {
                visible[index] = live
                track.node.opacity = live ? 1 : 0
            }
        }
        return playing
    }

    /// Stops the frames where they stand (the CI's hold on the high point).
    func freeze() {
        ticker?.stop()
        ticker = nil
    }

    /// Stops the frames and puts every plane out of sight.
    func stop() {
        ticker?.stop()
        ticker = nil
        hideAll()
    }
}
