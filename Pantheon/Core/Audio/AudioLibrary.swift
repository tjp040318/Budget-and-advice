import Foundation
import AVFoundation

/// Sound effects.
///
/// A pool of `AVAudioPlayer`s per sound so overlapping hits do not cut each
/// other off, a shared session set to ambient so the player's own music keeps
/// playing, and a lookup by name that fails silently — a missing file means a
/// silent event, never a crash, which is the right failure mode for audio.
///
/// The files in `Resources/Audio` are synthesised (see `tools/sfx.py`), which is
/// how a lot of shipped indie games sound and vastly better than silence. Swap
/// any of them for a recorded sample by replacing the file; nothing else knows.
final class AudioLibrary {

    static let shared = AudioLibrary()

    /// Sound names, as filenames without extension.
    enum Sound: String, CaseIterable {
        case hitLight = "hit_light"
        case hitNormal = "hit_normal"
        case hitHeavy = "hit_heavy"
        case hitCrit = "hit_crit"
        case hitLethal = "hit_lethal"
        case whoosh
        case uiTap = "ui_tap"
        case uiConfirm = "ui_confirm"
        case summonCharge = "summon_charge"
        case summonBurst = "summon_burst"
        case starTick = "star_tick"
        case victory
        case defeat
    }

    var isMuted = false {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.muteKey) }
    }
    private static let muteKey = "audio.muted"

    /// How many simultaneous instances of one sound to allow. Multi-hit skills
    /// land three or four hits within a quarter second.
    private let voicesPerSound = 4
    private var pools: [Sound: [AVAudioPlayer]] = [:]
    private var nextVoice: [Sound: Int] = [:]
    private let lock = NSLock()

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteKey)
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

    func play(_ sound: Sound, volume: Float = 1.0) {
        guard !isMuted else { return }
        guard let players = pool(for: sound), !players.isEmpty else { return }

        lock.lock()
        let index = nextVoice[sound, default: 0]
        nextVoice[sound] = (index + 1) % players.count
        lock.unlock()

        let player = players[index]
        player.volume = volume
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
        for _ in 0..<voicesPerSound {
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players.append(player)
            }
        }
        lock.lock(); pools[sound] = players; lock.unlock()
        return players
    }
}
