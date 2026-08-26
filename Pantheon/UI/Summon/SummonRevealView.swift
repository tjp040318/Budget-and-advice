import SwiftUI
import SceneKit
import UIKit

/// The reveal after a summon.
///
/// A ten-pull reveals one at a time, with the option to skip to the grid. The 5★
/// reveal gets the 3D stage and a beam; lower grades get a card flip, because
/// making every pull cinematic makes none of them feel like anything.
struct SummonRevealView: View {
    let results: [SummonResult]
    let onFinish: () -> Void

    @State private var index = 0
    @State private var showAll = false
    @State private var revealed = false

    private var current: SummonResult? {
        results.indices.contains(index) ? results[index] : nil
    }

    var body: some View {
        ZStack {
            backdrop

            if showAll {
                grid
            } else if let current {
                single(current)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(showAll ? "Done" : "Skip") {
                        if showAll { onFinish() } else { showAll = true }
                    }
                    .font(Theme.body(14).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { revealNext() }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                (current.map { tint(for: $0) } ?? Theme.gold).opacity(0.35),
                Theme.ink
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: index)
    }

    private func tint(for result: SummonResult) -> Color {
        switch result.stars {
        case 5: return Theme.gold
        case 4: return Color(hex: "#B07FE8")
        default: return Theme.info
        }
    }

    // MARK: - One at a time

    private func single(_ result: SummonResult) -> some View {
        VStack(spacing: 18) {
            Spacer()

            SummonStageView(result: result)
                .frame(height: 320)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.85)
                .animation(.spring(response: 0.55, dampingFraction: 0.7), value: revealed)

            VStack(spacing: 6) {
                StarRow(stars: result.stars, size: 20)
                Text(result.blueprint.name)
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.textPrimary)
                Text(result.blueprint.epithet)
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: 8) {
                    ElementBadge(element: result.blueprint.element)
                    Text(result.blueprint.pantheon.displayName)
                        .font(Theme.body(11).weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(result.blueprint.pantheon.color.opacity(0.18)))
                        .foregroundStyle(result.blueprint.pantheon.color)
                }
                .padding(.top, 2)

                if result.isNew {
                    Text("NEW")
                        .font(Theme.body(11).weight(.black))
                        .tracking(2)
                        .foregroundStyle(Theme.gold)
                } else {
                    Text("Duplicate — one skill levelled up")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }

                if result.fromPity {
                    Text("Guaranteed by pity")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .opacity(revealed ? 1 : 0)

            Spacer()

            Text(index + 1 < results.count ? "Tap to continue  (\(index + 1)/\(results.count))" : "Tap to finish")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 30)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
    }

    private func advance() {
        guard revealed else { return }
        if index + 1 < results.count {
            revealed = false
            index += 1
            revealNext()
        } else if results.count > 1 {
            showAll = true
        } else {
            onFinish()
        }
    }

    private func revealNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            revealed = true
        }
    }

    // MARK: - Grid

    private var grid: some View {
        VStack(spacing: 16) {
            Text("Summoned")
                .font(Theme.display(30))
                .foregroundStyle(Theme.textPrimary)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(results) { result in
                        VStack(spacing: 4) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.tightCorner)
                                    .fill(
                                        LinearGradient(
                                            colors: [tint(for: result).opacity(0.5), Theme.surface],
                                            startPoint: .top, endPoint: .bottom
                                        )
                                    )
                                Text(String(result.blueprint.name.prefix(1)))
                                    .font(Theme.display(30))
                                    .foregroundStyle(Theme.textPrimary)
                                if result.isNew {
                                    Text("NEW")
                                        .font(Theme.body(7).weight(.black))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Theme.gold))
                                        .foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                        .padding(3)
                                }
                            }
                            .frame(height: 74)
                            StarRow(stars: result.stars, size: 8)
                            Text(result.blueprint.name)
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            PrimaryButton(title: "Continue", action: onFinish)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .padding(.top, 50)
    }
}

/// A tiny SceneKit stage that drops the summoned unit in on a beam.
///
/// It reuses `ModelLibrary`, so it shows the real model the moment one exists
/// and the placeholder rig until then.
struct SummonStageView: UIViewRepresentable {
    let result: SummonResult

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true

        let node = ModelLibrary.shared.node(
            for: result.blueprint.model,
            archetype: result.blueprint.archetype,
            element: result.blueprint.element
        )
        node.position = SCNVector3(0, 0, 0)
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        node.runAction(.sequence([
            .wait(duration: 0.35),
            .fadeIn(duration: 0.5),
            .rotateBy(x: 0, y: .pi * 2, z: 0, duration: 3.2)
        ]))

        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.wantsHDR = true
        camera.bloomIntensity = 0.8
        camera.bloomThreshold = 0.7
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let height = result.blueprint.model.height
        cameraNode.position = SCNVector3(0, height * 0.6, height * 2.4)
        cameraNode.eulerAngles = SCNVector3(-0.1, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1_500
        key.color = UIColor(hex: result.blueprint.model.auraHex) ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-3, 5, 4)
        keyNode.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(keyNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 320
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        VFXLibrary.summonBeam(
            at: SCNVector3(0, 0, 0),
            in: scene,
            tint: UIColor(hex: result.blueprint.model.auraHex) ?? .white
        )

        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
