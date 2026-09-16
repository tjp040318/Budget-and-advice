import SwiftUI

/// Athena on screen: her portrait, her plate, and the caret that points at
/// the one control she is talking about.
///
/// The caret is the reason this is a preference and not a table of
/// coordinates. `FirstHourStep`'s pointer was computed from the island
/// painting's own landmark anchors, which works exactly once — on the
/// island. A guide that has to point at a tab, a button in a sheet and a
/// slot on the unit sheet cannot know where any of them are, so instead
/// every control that can be pointed at says where it is:
///
///     Button("Summon") { … }.guideAnchor("summon_button")
///
/// and the overlay reads the rect back out of the preference. A lesson
/// naming an anchor no view has registered draws its line with no caret,
/// which is the safe way for this to fail.
struct GuideAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Lets Athena's caret find this control by name.
    func guideAnchor(_ id: String) -> some View {
        anchorPreference(key: GuideAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Puts Athena over this container. Applied to the tab shell and to each
    /// sheet that is presented over it, because a sheet covers whatever is
    /// behind it and she has to be able to talk inside one.
    func guide(_ game: GameStore) -> some View {
        modifier(GuideOverlay(store: game))
    }
}

/// Her portrait and her words: a bust at the left, a cream plate beside it,
/// the line typed out rather than dropped in. A tap anywhere goes on.
struct GuidePlate: View {
    let beat: LessonBeat
    let title: String
    let isLast: Bool
    var onAdvance: () -> Void
    var onSkip: (() -> Void)?

    /// How much of the line has been typed. Reset by `.id(beat.says)` at the
    /// call site, so a new beat starts empty.
    @State private var shown = 0
    @State private var finished = false

    private var portrait: CGFloat { 168 }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: -14) {
                BundleImage(name: beat.face.imageName, renderedAt: portrait)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: portrait, height: portrait)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                    .accessibilityLabel("Athena")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("ATHENA")
                            .font(Theme.title(13))
                            .foregroundStyle(Theme.gold)
                        Text(title)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let onSkip {
                            Button("Skip", action: onSkip)
                                .font(Theme.body(10).weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .buttonStyle(.plain)
                        }
                    }
                    Text(String(beat.says.prefix(shown)))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(finished ? (isLast ? "Tap to begin" : "Tap to go on") : " ")
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.gold.opacity(finished ? 0.9 : 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 96, alignment: .top)
                .background(Theme.panel(Theme.tightCorner))
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .task(id: beat.says) {
            shown = 0
            finished = false
            for index in beat.says.indices {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
                shown = beat.says.distance(from: beat.says.startIndex, to: index) + 1
            }
            finished = true
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // A tap part way through the line finishes it rather than losing
            // it: the genre's rule, and the only one a reader ever wants.
            if finished {
                onAdvance()
            } else {
                shown = beat.says.count
                finished = true
            }
        }
    }
}

/// The gold caret and the one line under it, sitting on the control the
/// lesson named. Nothing here is tappable — the caret moves when the player
/// does the thing, which is read off the save.
struct GuideCaret: View {
    let prompt: String
    let target: CGRect
    let bounds: CGSize

    var body: some View {
        // Under the control when the whole box fits under it, over it when it
        // does not.
        let below = target.maxY + 78 < bounds.height
        let y = below ? target.maxY + 8 : target.minY - 8
        VStack(spacing: 4) {
            if !below {
                line
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Theme.gold)
            } else {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Theme.gold)
                line
            }
        }
        .frame(maxWidth: 300)
        .position(
            x: min(max(160, target.midX), bounds.width - 160),
            y: below ? y + 40 : y - 40
        )
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var line: some View {
        Text(prompt)
            .font(Theme.body(11).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.panel(Theme.tightCorner))
    }
}

/// Athena over a container: her words while she has any, then her caret
/// until the player has done the thing.
struct GuideOverlay: ViewModifier {
    @ObservedObject var store: GameStore

    /// Which beat of the current lesson is showing. Kept here rather than in
    /// the save: a lesson half read is not worth a write, and the lesson is
    /// resumed from its first beat if the app dies mid-sentence.
    @State private var beat = 0
    @State private var speaking: String?

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(GuideAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let lesson = store.currentLesson {
                        layer(lesson, anchors: anchors, proxy: proxy)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
    }

    @ViewBuilder
    private func layer(
        _ lesson: Lesson,
        anchors: [String: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        let talking = speaking == lesson.id && beat < lesson.beats.count
        ZStack {
            if talking {
                // While she is speaking she owns the taps, so a stray press
                // on the screen behind her cannot start something in the
                // middle of a sentence.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { advance(lesson) }
                GuidePlate(
                    beat: lesson.beats[beat],
                    title: lesson.title,
                    isLast: beat == lesson.beats.count - 1,
                    onAdvance: { advance(lesson) },
                    onSkip: lesson.topic == .opening ? { store.silenceOpening() } : nil
                )
                .id(lesson.id)
            } else if let prompt = lesson.prompt, lesson.isStep {
                if let name = lesson.anchor, let anchor = anchors[name] {
                    GuideCaret(prompt: prompt, target: proxy[anchor], bounds: proxy.size)
                } else {
                    // No view on this screen registered that anchor: the line
                    // still tells the player where to go.
                    GuideCaret(
                        prompt: prompt,
                        target: CGRect(x: proxy.size.width / 2, y: proxy.size.height - 96, width: 0, height: 0),
                        bounds: proxy.size
                    )
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: talking)
        .onAppear { open(lesson) }
        .onChange(of: lesson.id) { _ in open(lesson) }
    }

    /// A lesson whose words have not been read starts talking; one already
    /// read goes straight to its caret.
    private func open(_ lesson: Lesson) {
        guard speaking != lesson.id else { return }
        if store.hasReadLesson(lesson.id) {
            speaking = nil
        } else {
            speaking = lesson.id
            beat = 0
        }
    }

    private func advance(_ lesson: Lesson) {
        if beat + 1 < lesson.beats.count {
            beat += 1
        } else {
            store.markLessonRead(lesson.id)
            speaking = nil
            beat = 0
        }
    }
}

// MARK: - The library

/// Everything Athena has ever said, kept.
///
/// The owner, on the opening being skippable and replayable: "That would be
/// a good idea, let's expand on that." This is the expansion — the tutorial
/// stops being eight minutes that are spent once and becomes the manual. A
/// lesson she has given can be read again for ever; one she has not is
/// listed by name and greyed, so a player can see what the game still holds.
struct LessonsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var replaying: Lesson?

    var body: some View {
        GameScreen {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(LessonTopic.allCases) { topic in
                            let lessons = LessonBook.all.filter { $0.topic == topic }
                            if !lessons.isEmpty {
                                section(topic, lessons)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .overlay { if let replaying { card(replaying) } }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            .buttonStyle(.plain)
            BundleImage(name: GuideFace.calm.imageName, renderedAt: 34)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("ATHENA'S COUNSEL")
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.gold)
                Text("\(read) of \(LessonBook.all.count) lessons given")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.surfaceRaised)
    }

    private var read: Int {
        LessonBook.all.filter { store.hasReadLesson($0.id) }.count
    }

    private func section(_ topic: LessonTopic, _ lessons: [Lesson]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.title.uppercased())
                .font(Theme.title(12))
                .foregroundStyle(Theme.goldDeep)
            ForEach(lessons) { lesson in
                row(lesson)
            }
        }
    }

    private func row(_ lesson: Lesson) -> some View {
        let given = store.hasReadLesson(lesson.id)
        return Button {
            guard given else { return }
            withAnimation { replaying = lesson }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: given ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(given ? Theme.gold : Theme.textSecondary.opacity(0.6))
                Text(lesson.title)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(given ? Theme.textPrimary : Theme.textSecondary.opacity(0.7))
                Spacer(minLength: 0)
                if given {
                    Text("Read again")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(Theme.panel(Theme.tightCorner))
        }
        .buttonStyle(.plain)
        .disabled(!given)
    }

    /// A replay is a CARD, not a pointer: the player may be standing on the
    /// island reading the lesson about a relic slot, and a caret aimed at a
    /// control that is not on this screen would be a caret that lies.
    private func card(_ lesson: Lesson) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { replaying = nil } }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    BundleImage(name: GuideFace.calm.imageName, renderedAt: 54)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                    Text(lesson.title)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.gold)
                    Spacer(minLength: 0)
                }
                ForEach(Array(lesson.beats.enumerated()), id: \.offset) { _, said in
                    Text(said.says)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let prompt = lesson.prompt {
                    Text(prompt)
                        .font(Theme.body(11).weight(.semibold))
                        .foregroundStyle(Theme.goldDeep)
                        .padding(.top, 2)
                }
                Text("Tap to close")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: 420)
            .background(Theme.panel(Theme.tightCorner))
            .onTapGesture { withAnimation { replaying = nil } }
        }
    }
}
