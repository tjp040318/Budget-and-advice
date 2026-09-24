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
        // The summon that climbs with the grade (FEEL.md W2.7), built by
        // `tools/sfx.py` `build_summon()`. The circle catching light at the
        // summon button; the charge's three stems on the ladder's rungs —
        // the base under every pull, the rise from the violet rung (a 4★ or
        // better), the tell from the gold one (a 5★ alone) — and the Light &
        // Dark scroll's own layer; the burst by grade at the flash; the
        // stars' climb up a glockenspiel scale, one note a star.
        case summonIgnite = "summon_ignite"
        case summonChargeBase = "summon_charge_base"
        case summonChargeRise = "summon_charge_rise"
        case summonChargeTell = "summon_charge_tell"
        case summonChargeLightDark = "summon_charge_lightdark"
        case summonBurst3 = "summon_burst_3"
        case summonBurst4 = "summon_burst_4"
        case summonBurst5 = "summon_burst_5"
        case star1 = "star_1"
        case star2 = "star_2"
        case star3 = "star_3"
        case star4 = "star_4"
        case star5 = "star_5"
        case star6 = "star_6"
        // The three rites that reused the summon's burst: an awakening, an
        // evolution and a relic's awakening each sound as themselves.
        case riteAwaken = "rite_awaken"
        case riteEvolve = "rite_evolve"
        case riteRelicAwaken = "rite_relic_awaken"
        // The reward box by rarity (FEEL.md W2.2), built by `tools/sfx.py`
        // `build_spoils()`: the chest's three rattles, each harder; its lid's
        // creak, its thud on the hinge and the beam's shimmer, as one file in
        // step with the lid; a crystal clink for each tile, one step up a
        // pentatonic scale a tile, so a big haul plays a melody; a legend's
        // rising three notes; and the relic power-up's short drum roll and
        // its anvil ring or dull crack.
        case chestRattle1 = "chest_rattle_1"
        case chestRattle2 = "chest_rattle_2"
        case chestRattle3 = "chest_rattle_3"
        case chestOpen = "chest_open"
        case spoil1 = "spoil_1"
        case spoil2 = "spoil_2"
        case spoil3 = "spoil_3"
        case spoil4 = "spoil_4"
        case spoil5 = "spoil_5"
        case spoil6 = "spoil_6"
        case spoil7 = "spoil_7"
        case spoil8 = "spoil_8"
        case spoil9 = "spoil_9"
        case spoil10 = "spoil_10"
        case spoil11 = "spoil_11"
        case spoil12 = "spoil_12"
        case spoilLegend = "spoil_legend"
        case relicRoll = "relic_roll"
        case relicRing = "relic_ring"
        case relicCrack = "relic_crack"

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

        /// The flash's burst for a pull of `stars` (FEEL.md W2.7): a chime
        /// for a 3★ or less, a brass stab for a 4★, a gong under a choir for
        /// a 5★ or better. Read off the pull's stars at the flash, when the
        /// grade is already on the screen. An awakening's reveal is a reveal
        /// like any other: its rite (`riteAwaken`) sounds at the altar's
        /// pillar before it, so it is not sounded twice.
        static func burst(forStars stars: Int) -> Sound {
            if stars >= 5 { return .summonBurst5 }
            if stars == 4 { return .summonBurst4 }
            return .summonBurst3
        }

        /// The note star `index` (from 0) lands on: the scale climbs one
        /// step a star, and a sixth star rings the octave.
        static func star(_ index: Int) -> Sound {
            switch min(5, max(0, index)) {
            case 0: return .star1
            case 1: return .star2
            case 2: return .star3
            case 3: return .star4
            case 4: return .star5
            default: return .star6
            }
        }

        /// How long the relic power-up's drum roll runs before its verdict —
        /// the ring or the crack — lands (`relic_roll` is built to it).
        static let rollLead: TimeInterval = 0.26

        /// The chest's rattle `index` (from 0): each harder than the last.
        static func rattle(_ index: Int) -> Sound {
            switch min(2, max(0, index)) {
            case 0: return .chestRattle1
            case 1: return .chestRattle2
            default: return .chestRattle3
            }
        }

        /// The note tile `index` (from 0) lands on: the pentatonic scale
        /// climbs one step a tile, twelve steps, and a longer haul keeps
        /// ringing the top note.
        static func spoil(_ index: Int) -> Sound {
            switch min(11, max(0, index)) {
            case 0: return .spoil1
            case 1: return .spoil2
            case 2: return .spoil3
            case 3: return .spoil4
            case 4: return .spoil5
            case 5: return .spoil6
            case 6: return .spoil7
            case 7: return .spoil8
            case 8: return .spoil9
            case 9: return .spoil10
            case 10: return .spoil11
            default: return .spoil12
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
            case .waveEgypt, .waveGreece, .waveNorse, .waveRome, .waveJade, .bossArrival, .levelUp,
                 .riteAwaken, .riteEvolve, .riteRelicAwaken,
                 .chestRattle1, .chestRattle2, .chestRattle3, .chestOpen,
                 .spoil1, .spoil2, .spoil3, .spoil4, .spoil5, .spoil6, .spoil7, .spoil8, .spoil9, .spoil10,
                 .spoil11, .spoil12, .spoilLegend:
                return 1
            case .relicRoll, .relicRing, .relicCrack:
                return 2
            case .revive, .death, .extraTurn, .counter, .turnChime,
                 .summonIgnite, .summonChargeBase, .summonChargeRise, .summonChargeTell, .summonChargeLightDark,
                 .summonBurst3, .summonBurst4, .summonBurst5,
                 .star1, .star2, .star3, .star4, .star5, .star6:
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
                player.volume = musicVolume * duckLevel
                player.play()
            }
        }
    }
    private static let musicMuteKey = "audio.music.muted"
    private var current: (music: Music, player: AVAudioPlayer)?
    /// Music sits under the effects, not level with them.
    private let musicVolume: Float = 0.32
    /// The share of `musicVolume` the music plays at: 1, or less while a
    /// rite has it stepped back (`duck(to:fade:)`). Main thread.
    private var duckLevel: Float = 1

    /// The latest duck's number (`duck(to:fade:)`). Main thread.
    private var duckToken = 0

    /// Steps the music back under a moment that has its own sound — the
    /// summon's reveal (FEEL.md W2.7) — to `level` of its own volume over
    /// `fade` seconds. A loop that starts while ducked starts ducked.
    /// `AVAudioPlayer` changes a player's volume only, so this is a volume,
    /// never a filter. Returns the duck's number for `unduck(_:fade:)`.
    /// Main thread.
    @discardableResult
    func duck(to level: Float, fade: TimeInterval = 0.4) -> Int {
        duckToken += 1
        setDuck(level, fade: fade)
        return duckToken
    }

    /// The music back at its own level. Given a duck's number, only while
    /// that duck is the latest: a reveal replaced by the next one (the
    /// cover's content changed under it) leaves AFTER the new one has
    /// ducked, and must not bring the music back up under it.
    func unduck(_ token: Int? = nil, fade: TimeInterval = 1.0) {
        if let token, token != duckToken { return }
        setDuck(1, fade: fade)
    }

    private func setDuck(_ level: Float, fade: TimeInterval) {
        duckLevel = min(1, max(0, level))
        guard !isMusicMuted, let player = current?.player else { return }
        player.setVolume(musicVolume * duckLevel, fadeDuration: fade)
    }

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
        player.setVolume(musicVolume * duckLevel, fadeDuration: fade)
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
        guard let player = takeVoice(for: sound) else { return }
        setStartVolume(player, sound.volumeCap.map { min(volume, $0) } ?? volume)
        player.currentTime = 0
        player.play()
    }

    /// Plays `sound` `lead` seconds from now on the audio device's own clock
    /// (`AVAudioPlayer.play(atTime:)`), not on a main-thread timer: the
    /// summon's burst (FEEL.md W2.7) sounds a set 40 ms after the flash,
    /// once the charge's stems have given way to it, however busy the main
    /// thread is drawing that flash. A voice still ringing is stopped where
    /// it stands first. Main thread.
    func schedule(_ sound: Sound, volume: Float = 1.0, in lead: TimeInterval) {
        guard !isMuted else { return }
        guard let player = takeVoice(for: sound) else { return }
        if player.isPlaying { player.pause() }
        setStartVolume(player, sound.volumeCap.map { min(volume, $0) } ?? volume)
        player.currentTime = 0
        let start: TimeInterval = player.deviceCurrentTime + max(0, lead)
        if lead <= 0 || !player.play(atTime: start) {
            player.play()
        }
    }

    /// Fades out every voice of `sounds` that is sounding, over `fade`
    /// seconds: the summon's charge giving way to its burst at the flash,
    /// or to the next pull (FEEL.md W2.7). A phone's mixer sums its players
    /// with nothing after it to catch a sum over full scale, so the stems
    /// step aside rather than play under the burst (`summon_mix_check` in
    /// `tools/sfx.py`). A voice `play` starts again is at its own volume
    /// again. Main thread.
    func fadeOut(_ sounds: [Sound], over fade: TimeInterval) {
        for sound in sounds {
            lock.lock()
            let players: [AVAudioPlayer] = pools[sound] ?? []
            lock.unlock()
            for player in players where player.isPlaying {
                lock.lock()
                fadedVoices.insert(ObjectIdentifier(player))
                lock.unlock()
                player.setVolume(0, fadeDuration: max(0.01, fade))
            }
        }
    }

    /// Voices `fadeOut` has turned down. The next start of one sets its
    /// volume with a ramp of nothing (`setVolume(_:fadeDuration: 0)`), so
    /// neither a fade still running nor the ramp it set can carry into the
    /// new sound's attack; every other start sets `volume` as it always has.
    private var fadedVoices: Set<ObjectIdentifier> = []

    private func setStartVolume(_ player: AVAudioPlayer, _ volume: Float) {
        lock.lock()
        let faded: Bool = fadedVoices.remove(ObjectIdentifier(player)) != nil
        lock.unlock()
        if faded {
            player.setVolume(volume, fadeDuration: 0)
        } else {
            player.volume = volume
        }
    }

    /// The next voice of `sound`'s pool, round the pool in turn. The index
    /// is taken modulo THIS pool's size: the launch preload and a first
    /// play can each build a pool for the same sound, and an index advanced
    /// on a larger one must not run past a smaller (2026-09-24).
    private func takeVoice(for sound: Sound) -> AVAudioPlayer? {
        guard let players = pool(for: sound), !players.isEmpty else { return nil }
        lock.lock()
        let index = nextVoice[sound, default: 0]
        nextVoice[sound] = (index + 1) % players.count
        lock.unlock()
        return players[index % players.count]
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
