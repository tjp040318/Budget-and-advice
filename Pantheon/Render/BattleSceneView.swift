import SwiftUI
import SceneKit
import UIKit

/// Bridges the SceneKit battle stage into SwiftUI.
///
/// The controller is created once and owned by the battle view model, not by
/// this struct — SwiftUI rebuilds `View` values constantly, and rebuilding a
/// scene graph on every layout pass would drop the battle.
struct BattleSceneView: UIViewRepresentable {

    let controller: BattleSceneController
    /// Called with the combatant a tap landed on, for target selection.
    var onTapUnit: ((UUID) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isJitteringEnabled = false
        // The camera is directed by CameraDirector; free orbit would fight it.
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onTapUnit = onTapUnit
        if view.scene !== controller.scene { view.scene = controller.scene }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapUnit: onTapUnit)
    }

    final class Coordinator: NSObject {
        var onTapUnit: ((UUID) -> Void)?
        weak var view: SCNView?

        init(onTapUnit: ((UUID) -> Void)?) {
            self.onTapUnit = onTapUnit
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view, let onTapUnit else { return }
            let point = recognizer.location(in: view)
            let hits = view.hitTest(point, options: [
                .boundingBoxOnly: true,
                .searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            // Walk up from whatever geometry was hit to the owning UnitNode.
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let unitNode = current as? UnitNode {
                        onTapUnit(unitNode.combatantID)
                        return
                    }
                    node = current.parent
                }
            }
        }
    }
}
