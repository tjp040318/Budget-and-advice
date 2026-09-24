import XCTest
import SceneKit
@testable import Pantheon

/// The settings side (`Docs/SETTINGS.md`): the graphics defaults are the
/// stages' own look, the render governor applies a choice to a live scene
/// and puts it back, the game's Reduce Motion counts, and the App Store
/// paperwork — the privacy manifest in the bundle, the export-compliance
/// key in the Info.plist, the legal links — is where App Store Connect will
/// look for it.
final class SettingsTests: XCTestCase {
    /// Every key these tests write, put back as it was afterwards.
    private let keys = [
        GraphicsSettings.frameRateKey, GraphicsSettings.effectsKey, GraphicsSettings.shadowsKey,
        MotionComfort.key, CameraDirector.cinematicKey,
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - Graphics

    /// Nothing chosen is the game as it was: the fight and the reveal at 60,
    /// the island at its deliberate 30, full effects, shadows on.
    @MainActor
    func testTheDefaultsAreTheStagesOwnLook() {
        XCTAssertEqual(GraphicsSettings.frameRate, .standard)
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .battle), 60)
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .island), 30)
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .reveal), 60, "SceneKit's own default, which the reveal always drew at")
        XCTAssertEqual(GraphicsSettings.effects, .full)
        XCTAssertTrue(GraphicsSettings.shadows)
        XCTAssertEqual(GraphicsChoice.current, GraphicsChoice.asBuilt)
    }

    func testEachFrameRateChoiceReachesEveryStage() {
        for stage in [RenderStage.battle, .island, .reveal] {
            XCTAssertEqual(GraphicsSettings.framesPerSecond(for: stage, choice: .battery), 30, "30 caps every stage")
        }
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .battle, choice: .promotion), 120)
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .reveal, choice: .promotion), 120)
        XCTAssertEqual(GraphicsSettings.framesPerSecond(for: .island, choice: .promotion), 30, "the island stays ambient")
    }

    /// A stored 120 on a screen that cannot draw it reads as 60, and 120 is
    /// only offered where it can be drawn.
    @MainActor
    func testOneTwentyIsOnlyOfferedWhereItCanBeDrawn() {
        UserDefaults.standard.set(FrameRateChoice.promotion.rawValue, forKey: GraphicsSettings.frameRateKey)
        let offered = GraphicsSettings.offeredFrameRates
        if GraphicsSettings.supportsPromotion {
            XCTAssertEqual(GraphicsSettings.frameRate, .promotion)
            XCTAssertTrue(offered.contains(.promotion))
        } else {
            XCTAssertEqual(GraphicsSettings.frameRate, .standard)
            XCTAssertEqual(offered, [.battery, .standard])
        }
    }

    /// The governor on a real scene, driven as SceneKit drives it: at the
    /// defaults it changes nothing; Reduced and no shadows reach the scene
    /// within ten frames — bloom off, a burst of sixty at half, a painted
    /// sheet untouched, the key light quiet, and a burst that arrives later
    /// thinned in its first frame — and Full puts every value back.
    @MainActor
    func testTheGovernorAppliesAChoiceAndPutsItBack() {
        let scene = SCNScene()
        let burst = SCNParticleSystem()
        burst.emissionDuration = 0.12
        burst.birthRate = 500
        let sheet = SCNParticleSystem()
        sheet.emissionDuration = 0.01
        sheet.birthRate = 100
        let host = SCNNode()
        host.addParticleSystem(burst)
        host.addParticleSystem(sheet)
        scene.rootNode.addChildNode(host)
        let light = SCNLight()
        light.type = .directional
        light.castsShadow = true
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.bloomIntensity = 0.22
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.pointOfView = cameraNode
        let governor = StageRenderGovernor(stage: .battle, inner: nil)

        func frames(_ count: Int) {
            for _ in 0..<count {
                governor.renderer(view, updateAtTime: 0)
                governor.renderer(view, willRenderScene: scene, atTime: 0)
            }
        }
        let bloom: CGFloat = 0.22
        let halfBurst: CGFloat = 500 * StageRenderGovernor.thinning

        frames(12)
        XCTAssertEqual(burst.birthRate, 500, "the defaults change nothing")
        XCTAssertTrue(light.castsShadow)
        XCTAssertEqual(camera.bloomIntensity, bloom, accuracy: 0.000_1)

        UserDefaults.standard.set(EffectsQuality.reduced.rawValue, forKey: GraphicsSettings.effectsKey)
        UserDefaults.standard.set(false, forKey: GraphicsSettings.shadowsKey)
        frames(10)
        XCTAssertEqual(burst.birthRate, halfBurst, "a burst of sixty emits half")
        XCTAssertEqual(sheet.birthRate, 100, "a painted sheet — one particle — is never thinned")
        XCTAssertFalse(light.castsShadow)
        XCTAssertEqual(camera.bloomIntensity, 0, accuracy: 0.000_1)

        let late = SCNParticleSystem()
        late.emissionDuration = 0.4
        late.birthRate = 200
        let lateHost = SCNNode()
        lateHost.addParticleSystem(late)
        scene.rootNode.addChildNode(lateHost)
        frames(1)
        let halfLate: CGFloat = 200 * StageRenderGovernor.thinning
        XCTAssertEqual(late.birthRate, halfLate, "an effect spawned mid-fight is thinned in its first frame")

        UserDefaults.standard.set(EffectsQuality.full.rawValue, forKey: GraphicsSettings.effectsKey)
        UserDefaults.standard.set(true, forKey: GraphicsSettings.shadowsKey)
        frames(10)
        XCTAssertEqual(burst.birthRate, 500, "Full puts every value back")
        XCTAssertEqual(late.birthRate, 200)
        XCTAssertTrue(light.castsShadow)
        XCTAssertEqual(camera.bloomIntensity, bloom, accuracy: 0.000_1)
    }

    // MARK: - The battle's speed (Docs/FEEL.md W1.1)

    /// The control steps ×1 → ×2 → ×3 → ×1 — never ×4, where the juice
    /// turned itself off — and the device remembers a speed only as one of
    /// those three. A suite of its own, so the player's choice is untouched.
    func testTheBattleSpeedStepsOneTwoThreeAndRemembersOnlyThose() throws {
        let second: Double = BattleSpeed.next(after: 1)
        let third: Double = BattleSpeed.next(after: second)
        let wrapped: Double = BattleSpeed.next(after: third)
        let fromTheOldTop: Double = BattleSpeed.next(after: 4)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(third, 3)
        XCTAssertEqual(wrapped, 1, "×3 steps back round to ×1")
        XCTAssertEqual(fromTheOldTop, 1, "a ×4 from before W1.1 reads as the top, and steps round")
        XCTAssertEqual(BattleSpeed.top, 3, "the stress tour runs its fights at the top")

        let suite = "PantheonTests.battleSpeed"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let unset: Double = BattleSpeed.remembered(in: defaults)
        XCTAssertEqual(unset, 1, "a device that never chose watches at ×1")
        BattleSpeed.remember(2, in: defaults)
        let kept: Double = BattleSpeed.remembered(in: defaults)
        XCTAssertEqual(kept, 2, "the next fight opens at the speed the last was left at")
        defaults.set(4.0, forKey: BattleSpeed.key)
        let old: Double = BattleSpeed.remembered(in: defaults)
        XCTAssertEqual(old, 3, "a stored ×4 comes back as ×3")
        defaults.set(0.5, forKey: BattleSpeed.key)
        let low: Double = BattleSpeed.remembered(in: defaults)
        XCTAssertEqual(low, 1)
    }

    // MARK: - Comfort

    func testTheGamesOwnReduceMotionHoldsTheCameraStill() {
        UserDefaults.standard.set(true, forKey: CameraDirector.cinematicKey)
        UserDefaults.standard.set(true, forKey: MotionComfort.key)
        XCTAssertTrue(MotionComfort.isReduced)
        XCTAssertFalse(CameraDirector.isCinematic, "cuts, leans and orbits are held off under Reduce Motion")
        XCTAssertLessThan(MotionComfort.zoomReach, 1, "the skill zoom travels a share of its way")
        XCTAssertGreaterThan(MotionComfort.zoomEase, 1, "and eases more slowly")
    }

    // MARK: - The paperwork

    func testThePrivacyManifestShipsAtTheBundlesRoot() throws {
        let bundle = Bundle(for: AccountService.self)
        let url = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                                "the synchronized group must copy the privacy manifest into the app bundle")
        let data = try Data(contentsOf: url)
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let apis = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        XCTAssertTrue(apis.contains("NSPrivacyAccessedAPICategoryUserDefaults"), "UserDefaults needs its reason, CA92.1")
        let collected = (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        XCTAssertTrue(collected.contains("NSPrivacyCollectedDataTypeUserID"))
        XCTAssertTrue(collected.contains("NSPrivacyCollectedDataTypeGameplayContent"))
    }

    func testExportComplianceIsAnsweredInTheInfoPlist() {
        let value = Bundle(for: AccountService.self).object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption")
        let answeredNo: Bool = (value as? Bool) == false || (value as? String)?.uppercased() == "NO"
        XCTAssertTrue(answeredNo, "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO on the app target")
    }

    func testLegalLinksAreHTTPSOrHidden() {
        XCTAssertNil(LegalLinks.link(""), "an empty value hides its row")
        XCTAssertNil(LegalLinks.link("   "))
        XCTAssertNil(LegalLinks.link("http://pantheon.example/privacy"), "never over plain http")
        XCTAssertNil(LegalLinks.link("privacy"))
        XCTAssertEqual(LegalLinks.link(" https://pantheon.example/privacy \n")?.absoluteString, "https://pantheon.example/privacy")
        let links = LegalLinks.from(dictionary: ["PrivacyPolicyURL": "https://pantheon.example/privacy", "TermsOfUseURL": ""])
        XCTAssertNotNil(links.privacyPolicy)
        XCTAssertNil(links.terms)
        XCTAssertNotNil(Bundle(for: AccountService.self).url(forResource: LegalLinks.filename, withExtension: "plist"),
                        "LegalLinks.plist ships, so the owner has one place to put the addresses")
    }
}
