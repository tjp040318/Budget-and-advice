import SwiftUI
import UIKit

// The beats the battle view draws over the field when the scene tells it to
// (`BattleSceneController.onFieldCue`, Docs/FEEL.md Wave 2): an ultimate's
// splash (W2.1), a wave's stamp (W2.10) and a boss's ribbon (W2.11). None of
// them takes a tap. Their numbers are FieldBeats.swift's, shared with the
// scene and the tests.

// MARK: - The ultimate's splash (W2.1)

/// An ultimate owning the screen over the held world: the field darkened
/// 55%, a band 60% of the screen tall wiping across at 12° with a knife edge
/// (`SplashBand`), carrying the caster's CARD at the band's full height —
/// upright, the band cutting it — streaks of the element racing along it,
/// the caster's name small in its colour and the skill's name carved in gold
/// at 34 points, landing at a third of the way with the sting. ×2 plays it
/// in half the time; ×3 flashes the name alone on a dark strip. Under Reduce
/// Motion the band fades where it would wipe and the name does not spring.
/// The card was drawn at 64 points while the fight played under the band;
/// the best art in the game now fills it (Epic Seven's and Star Rail's
/// ultimates own the screen the same way).
struct UltimateSplashView: View {
    let cue: UltimateSplashCue
    @State private var began = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed: TimeInterval = timeline.date.timeIntervalSince(began)
            let clock: TimeInterval = FieldClock.time(elapsed: elapsed, holdAt: cue.duration * 0.5, frozenFor: cue.frozenFor)
            let progress: Double = min(1, max(0, clock / max(0.01, cue.duration)))
            GeometryReader { geometry in
                splash(progress: progress, seconds: clock, size: geometry.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(cue.unitName), \(cue.skillName)")
    }

    private func splash(progress: Double, seconds: TimeInterval, size: CGSize) -> some View {
        let accent = Color(hex: cue.accentHex)
        let shade: Double = UltimateSplash.shade(at: progress, form: cue.form)
        return ZStack {
            Color.black.opacity(shade)
            Group {
                if cue.form == .flash {
                    nameFlash(progress: progress, accent: accent)
                } else {
                    band(progress: progress, seconds: seconds, size: size, accent: accent)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// The band: laid out level and wide enough to cross the screen when it
    /// is leaned, masked by its wipe, then leaned 12° as one.
    private func band(progress: Double, seconds: TimeInterval, size: CGSize, accent: Color) -> some View {
        let calm: Bool = Motion.isCalm
        let height: CGFloat = size.height * UltimateSplash.bandShare
        let width: CGFloat = size.width * 1.4
        let sweep: Double = calm ? 1 : UltimateSplash.sweep(at: progress)
        let shown: Double = calm ? UltimateSplash.envelope(at: progress, rise: 0.15, fall: 0.15) : 1
        let card: Double = UltimateSplash.cardIn(at: progress)
        let landing: Double = UltimateSplash.nameIn(at: progress)
        let cardSlide: CGFloat = calm ? 0 : CGFloat(1 - card) * -70
        let nameScale: CGFloat = calm ? 1 : 1 + 0.35 * CGFloat(1 - landing)
        return ZStack {
            LinearGradient(
                colors: [accent.opacity(0.5), Theme.ink.opacity(0.94), Theme.ink.opacity(0.97)],
                startPoint: .leading, endPoint: .trailing
            )
            SplashStreaks(seconds: seconds, tint: accent)
            if BundleImage.exists(cue.portrait) {
                PortraitPainting(name: cue.portrait, size: height)
                    .frame(width: height, height: height)
                    .clipped()
                    .mask {
                        LinearGradient(colors: [.black, .black, .black.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .rotationEffect(.degrees(UltimateSplash.bandLeanDegrees))
                    .offset(x: -size.width * 0.3 + cardSlide)
                    .opacity(card)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cue.unitName.uppercased())
                    .font(Theme.body(12).weight(.heavy))
                    .tracking(2.4)
                    .foregroundStyle(accent)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .lineLimit(1)
                Text(cue.skillName.uppercased())
                    .font(Theme.display(UltimateSplash.nameSize))
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .carved()
                    .scaleEffect(nameScale, anchor: .leading)
                    .opacity(landing)
            }
            .frame(width: size.width * 0.52, alignment: .leading)
            .offset(x: size.width * 0.12)
            .opacity(calm ? landing : 1)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(accent)
                    .frame(height: 3)
                    .shadow(color: accent.opacity(0.9), radius: 6)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(accent)
                    .frame(height: 3)
                    .shadow(color: accent.opacity(0.9), radius: 6)
            }
        }
        .frame(width: width, height: height)
        .mask {
            SplashBand(progress: sweep, slant: height * 0.24)
        }
        .rotationEffect(.degrees(-UltimateSplash.bandLeanDegrees))
        .opacity(shown)
    }

    /// ×3: the skill's name alone, on a dark strip, in and gone.
    private func nameFlash(progress: Double, accent: Color) -> some View {
        let shown: Double = UltimateSplash.envelope(at: progress, rise: 0.15, fall: 0.3)
        let rule = LinearGradient(colors: [accent.opacity(0), accent, accent.opacity(0)],
                                  startPoint: .leading, endPoint: .trailing)
        return Text(cue.skillName.uppercased())
            .font(Theme.display(30))
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .carved()
            .padding(.horizontal, 60)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(StampBand(rule: rule, shade: 0.85))
            .opacity(shown)
    }
}

/// The splash band's shape: a parallelogram with a knife edge at each end —
/// the top a `slant` further on than the foot — wiping in from the left as
/// `progress` goes 0 → 1 and away to the right as it goes 1 → 2. The band
/// is drawn level and leaned by the view.
struct SplashBand: Shape {
    var progress: Double
    var slant: CGFloat

    func path(in rect: CGRect) -> Path {
        let span: CGFloat = rect.width + slant * 2
        let lead: CGFloat = rect.minX - slant + span * CGFloat(min(1, max(0, progress)))
        let trail: CGFloat = rect.minX - slant + span * CGFloat(min(1, max(0, progress - 1)))
        var path = Path()
        path.move(to: CGPoint(x: trail + slant, y: rect.minY))
        path.addLine(to: CGPoint(x: lead + slant, y: rect.minY))
        path.addLine(to: CGPoint(x: lead, y: rect.maxY))
        path.addLine(to: CGPoint(x: trail, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The streaks racing along the band in the element's colour: thin, of
/// every length, each at its own speed on its own lane, added over the dark.
/// Placed by a hash of their index, so nothing is random from frame to frame.
struct SplashStreaks: View {
    let seconds: TimeInterval
    let tint: Color

    static let count = 22

    var body: some View {
        Canvas { context, size in
            for index in 0..<SplashStreaks.count {
                let lane: CGFloat = SplashStreaks.hash(index, 1)
                let length: CGFloat = 50 + 170 * SplashStreaks.hash(index, 2)
                let speed: CGFloat = 900 + 700 * SplashStreaks.hash(index, 3)
                let thickness: CGFloat = 1 + 2.2 * SplashStreaks.hash(index, 4)
                let travel: CGFloat = size.width + length
                let run: CGFloat = CGFloat(seconds) * speed + travel * SplashStreaks.hash(index, 5)
                let x: CGFloat = run.truncatingRemainder(dividingBy: travel) - length
                let y: CGFloat = size.height * (0.06 + 0.88 * lane)
                let streak = CGRect(x: x, y: y - thickness / 2, width: length, height: thickness)
                context.fill(
                    Path(roundedRect: streak, cornerRadius: thickness / 2),
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0), tint.opacity(0.8)]),
                        startPoint: CGPoint(x: streak.minX, y: y),
                        endPoint: CGPoint(x: streak.maxX, y: y)
                    )
                )
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// A fixed fraction in 0..<1 for an index and a salt.
    static func hash(_ index: Int, _ salt: Int) -> CGFloat {
        let value: Double = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43_758.5453
        return CGFloat(value - value.rounded(.down))
    }
}

// MARK: - A wave's stamp (W2.10)

/// WAVE 2, or FINAL WAVE: carved gold on the stamps' dark band — gold rules,
/// wine for the last wave — sweeping in from the right, landing with the
/// drum, drifting, and away to the left while the arrivals walk on. Under
/// Reduce Motion it fades up where it lands.
struct WaveStampView: View {
    let cue: WaveStampCue
    @State private var began = Date()

    private static let goldRule = LinearGradient(
        colors: [Color(hex: "#EDCB6C").opacity(0), Color(hex: "#FFF3C8"), Color(hex: "#EDCB6C").opacity(0)],
        startPoint: .leading, endPoint: .trailing
    )
    private static let wineRule = LinearGradient(
        colors: [Theme.wine.opacity(0), Color(hex: "#B8405A"), Theme.wine.opacity(0)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed: TimeInterval = timeline.date.timeIntervalSince(began)
            let holdAt: TimeInterval = cue.duration * (WaveStamp.landsAt + 0.12)
            let clock: TimeInterval = FieldClock.time(elapsed: elapsed, holdAt: holdAt, frozenFor: cue.frozenFor)
            let progress: Double = min(1, max(0, clock / max(0.01, cue.duration)))
            GeometryReader { geometry in
                stamp(progress: progress, width: geometry.size.width)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cue.isFinal ? "Final wave" : "Wave \(cue.wave)")
    }

    private func stamp(progress: Double, width: CGFloat) -> some View {
        let calm: Bool = Motion.isCalm
        let travel: CGFloat = calm ? 0 : CGFloat(WaveStamp.travel(at: progress)) * width
        let shown: Double = WaveStamp.opacity(at: progress)
        return ZStack {
            StampBand(rule: cue.isFinal ? WaveStampView.wineRule : WaveStampView.goldRule, shade: 0.78)
            Text(cue.word)
                .font(Theme.display(46))
                .tracking(8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .carved()
                .offset(x: travel)
        }
        .frame(height: 72)
        .opacity(shown)
        .frame(maxWidth: .infinity)
        .padding(.top, 76)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - A boss's ribbon (W2.11)

/// The words on a boss's entrance ribbon (`BattleViewModel.entranceCard`).
struct BossEntranceCard: Equatable {
    let name: String
    let epithet: String
    /// The stage's line, when this boss is its speaker: a giant says it here
    /// rather than in a band of its own.
    let line: String?
    /// A Titan's weakness at this moment.
    let weakness: Element?
}

/// A wine ribbon under the boss's bar as it roars: BOSS, its name carved in
/// gold, its epithet, its line, and a Titan's weakness in that element's
/// colour — slammed in on a pop (a fade under Reduce Motion). Souls-like
/// bosses and Raid's own name the thing before the fight; ours arrived as a
/// quiet fade (`18-dungeon_battle-c`).
struct BossRibbonView: View {
    let card: BossEntranceCard
    @State private var landed = false

    private static let wineRule = LinearGradient(
        colors: [Theme.wine.opacity(0), Color(hex: "#E58A9C"), Theme.wine.opacity(0)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        let settled: Bool = landed || Motion.isCalm
        VStack(spacing: 3) {
            Text("BOSS")
                .font(Theme.body(12).weight(.black))
                .tracking(5)
                .foregroundStyle(Theme.onGlassDanger)
            Text(card.name.uppercased())
                .font(Theme.display(40))
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .carved()
            if !card.epithet.isEmpty {
                Text(card.epithet)
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let line = card.line {
                Text("“\(line)”")
                    .font(Theme.body(12.5).italic())
                    .foregroundStyle(Theme.onGlass.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let weakness = card.weakness {
                HStack(spacing: 5) {
                    Image(systemName: weakness.glyph)
                        .font(.system(size: 11, weight: .bold))
                    Text("Open to \(weakness.displayName)")
                        .font(Theme.body(11).weight(.bold))
                }
                .foregroundStyle(weakness.color)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(weakness.color.opacity(0.8), lineWidth: 1))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(StampBand(rule: BossRibbonView.wineRule, shade: 0.84))
        .scaleEffect(settled ? 1 : 1.18)
        .opacity(landed ? 1 : 0)
        .padding(.top, 64)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(Motion.pop) { landed = true }
        }
    }
}
