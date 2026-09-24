import Foundation
import AVFoundation

/// Sound effects.
///
/// A pool of `AVAudioPlayer`s per sound so overlapping hits do not cut each
/// other off, a shared session set to ambient so the player's own music keeps
/// playing, and a lookup by name that fails silently — a missing file means a
/// silent event, never a crash, which is the right failure mode for audio.
///
/// The files in `Resources/Audio` are built by `tools/sfx.py`: synthesised, and
/// since the fight got its own sounds (W1.4) some layered from CC0 orchestral
/// recordings (VSCO 2 Community Edition). Swap any of them for another
/// recording by replacing the file; nothing else knows.
final class AudioLibrary {

    static let shared = AudioLibrary()

    /// Sound names, as filenames without extension.
    enum Sound: String, CaseIterable {
        case hitLight = "hit_light"
        case hitNormal = "hit_normal"
        case hitHeavy = "hit_heavy"
        case hitCrit = "hit_crit"
        case hitLethal = "hit_lethal"
        // By kind, for a caller that knows what struck: steel, wood or a
        // spell. Nothing picks these yet; the files exist so something can.
        case hitBlade = "hit_blade"
        case hitBlunt = "hit_blunt"
        case hitMagic = "hit_magic"
        // One per element, named to match `impact_<element>` in VFXLibrary, so
        // a skill with no effect of its own can sound in its caster's element
        // the way it already looks in it.
        case impactEmber = "impact_ember"
        case impactTide = "impact_tide"
        case impactGale = "impact_gale"
        case impactRadiance = "impact_radiance"
        case impactUmbra = "impact_umbra"
        case block
        case dodge
        case whoosh
        case thunder
        case uiTap = "ui_tap"
        case uiConfirm = "ui_confirm"
        case summonCharge = "summon_charge"
        case summonBurst = "summon_burst"
        case starTick = "star_tick"
        case victory
        case defeat
        // The fight's own events (FEEL.md W1.4, 2026-09-24), built by
        // `tools/sfx.py` `build_status()` and `build_flow()`. A status that
        // lands picks its cue through `status(_:)`, a wave its realm's horn
        // through `waveCall(for:)`, so each hook is one line.
        case heal
        case statusShield = "status_shield"
        case statusBuff = "status_buff"
        case statusDebuff = "status_debuff"
        case statusStun = "status_stun"
        case statusFreeze = "status_freeze"
        case statusBurn = "status_burn"
        case statusProvoke = "status_provoke"
        case statusBomb = "status_bomb"
        case counter
        case extraTurn = "extra_turn"
        case revive
        case death
        case waveEgypt = "wave_egypt"
        case waveGreece = "wave_greece"
        case waveNorse = "wave_norse"
        case waveRome = "wave_rome"
        case waveJade = "wave_jade"
        case bossArrival = "boss_arrival"
        case turnChime = "turn_chime"
        // The player's level-up fanfare (W1.6).
        case levelUp = "level_up"

        /// The cue for a status landing on a unit. The barriers ring as
        /// crystal, the five that change how a fight plays have their own,
        /// every other buff chimes up and every other debuff falls. No
        /// `default`, on purpose: a new status does not compile until it is
        /// given a sound.
        static func status(_ kind: StatusKind) -> Sound {
            switch kind {
            case .shield, .invincible, .immunity, .reflect:
                return .statusShield
            case .attackUp, .defenseUp, .speedUp, .critRateUp, .recovery, .counterStance, .endure:
                return .statusBuff
            case .stun:
                return .statusStun
            case .freeze:
                return .statusFreeze
            case .burn:
                return .statusBurn
            case .provoke:
                return .statusProvoke
            case .bomb:
                return .statusBomb
            case .attackDown, .defenseDown, .speedDown, .glancing, .brand, .sleep, .silence, .unrecoverable:
                return .statusDebuff
            }
        }

        /// The horn a realm sounds when a new wave takes the field: the five
        /// realms with chapters have their own call, and the others borrow
        /// the Greek salpinx until they have chapters of their own.
        static func waveCall(for pantheon: Pantheon) -> Sound {
            switch pantheon {
            case .egyptian: return .waveEgypt
            case .greek: return .waveGreece
            case .norse: return .waveNorse
            case .roman: return .waveRome
            case .chinese: return .waveJade
            case .japanese, .hindu, .mesopotamian, .aztec, .celtic, .slavic, .yoruba, .polynesian:
                return .waveGreece
            }
        }

        /// The loudest this sound may play, whatever the caller asks. The
        /// turn chime rings on every one of the player's turns, so it stays
        /// a murmur under the fight (FEEL.md W1.4). Nil lets the caller's
        /// volume stand, as it always has.
        var volumeCap: Float? {
            switch self {
            case .turnChime: return 0.35
            default: return nil
            }
        }

        /// Fewer voices than the usual four, for a sound that never overlaps
        /// itself much: a horn call, a boss's arrival or the level-up plays
        /// once, and every voice keeps its own copy of the file ready. Two
        /// where a second can start while the first still rings (an extra
        /// turn brings the chime round again inside a second), because a
        /// voice restarted mid-ring clicks. Nil is the usual four.
        var voices: Int? {
            switch self {
            case .waveEgypt, .waveGreece, .waveNorse, .waveRome, .waveJade, .bossArrival, .levelUp:
                return 1
            case .revive, .death, .extraTurn, .counter, .turnChime:
                return 2
            default:
                return nil
            }
        }
    }

    var isMuted = false {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.muteKey) }
    }
    private static let muteKey = "audio.muted"

    // MARK: - Music

    /// Loop names, as filenames without extension. Synthesised by
    /// `tools/music.py`; a recording of the same name replaces one silently.
    enum Music: String {
        case island = "music_island"
        case battle = "music_battle"
    }

    var isMusicMuted = false {
        didSet {
            UserDefaults.standard.set(isMusicMuted, forKey: Self.musicMuteKey)
            if isMusicMuted {
                current?.player.pause()
            } else if let player = current?.player {
                player.volume = musicVolume
                player.play()
            }
        }
    }
    private static let musicMuteKey = "audio.music.muted"
    private var current: (music: Music, player: AVAudioPlayer)?
    /// Music sits under the effects, not level with them.
    private let musicVolume: Float = 0.32

    /// Starts a loop, crossfading out whatever was playing. Asking for the
    /// loop that is already playing does nothing, so every screen can ask for
    /// its music on appear without restarting the track.
    func playMusic(_ music: Music, fade: TimeInterval = 1.2) {
        if current?.music == music { return }
        guard let url = Bundle.main.url(forResource: music.rawValue, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: music.rawValue, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        if let old = current?.player {
            old.setVolume(0, fadeDuration: fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { old.stop() }
        }
        current = (music, player)
        guard !isMusicMuted else { return }
        player.play()
        player.setVolume(musicVolume, fadeDuration: fade)
    }

    func stopMusic(fade: TimeInterval = 0.8) {
        guard let old = current?.player else { return }
        current = nil
        old.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { old.stop() }
    }

    /// An ambient-category player is paused when the app leaves the
    /// foreground and does not restart itself; call this on return.
    func resumeMusic() {
        guard !isMusicMuted, let player = current?.player, !player.isPlaying else { return }
        player.play()
    }

    /// How many simultaneous instances of one sound to allow. Multi-hit skills
    /// land three or four hits within a quarter second. A sound that never
    /// overlaps itself much asks for fewer (`Sound.voices`).
    private let voicesPerSound = 4
    private var pools: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]
    private let lock = NSLock()

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteKey)
        isMusicMuted = UserDefaults.standard.bool(forKey: Self.musicMuteKey)
        // Ambient: mixes with whatever the player is listening to and respects
        // the silent switch, which is what a game is expected to do.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Decodes every sound once, off the main thread, so the first hit of the
    /// first battle does not stutter.
    func preload() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for sound in Sound.allCases { _ = self.pool(for: sound) }
        }
    }

    /// `delay` exists for layering: a hit plays its weight now and the sound
    /// of what struck a frame or two later, quieter, so the two arrive as one
    /// event rather than as two sounds fired together.
    func play(_ sound: Sound, volume: Float = 1.0, delay: TimeInterval = 0) {
        guard !isMuted else { return }
        guard delay <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.play(sound, volume: volume)
            }
            return
        }
        guard let players = pool(for: sound), !players.isEmpty else { return }

        lock.lock()
        let index = nextVoice[sound, default: 0]
        nextVoice[sound] = (index + 1) % players.count
        lock.unlock()

        // The index is taken modulo THIS pool's size: the launch preload and
        // a first play can each build a pool for the same sound, and an index
        // advanced on a larger one must not run past a smaller (2026-09-24).
        let player = players[index % players.count]
        player.volume = sound.volumeCap.map { min(volume, $0) } ?? volume
        player.currentTime = 0
        player.play()
    }

    private func pool(for sound: Sound) -> [AVAudioPlayer]? {
        lock.lock()
        if let existing = pools[sound] { lock.unlock(); return existing }
        lock.unlock()

        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
            lock.lock(); pools[sound] = []; lock.unlock()
            return []
        }
        var players: [AVAudioPlayer] = []
        for _ in 0..<(sound.voices ?? voicesPerSound) {
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players.append(player)
            }
        }
        // Check, then store: when another thread built this sound's pool
        // while this one was, the first stored wins and this one is dropped.
        lock.lock(); defer { lock.unlock() }
        if let existing = pools[sound] { return existing }
        pools[sound] = players
        return players
    }
}
