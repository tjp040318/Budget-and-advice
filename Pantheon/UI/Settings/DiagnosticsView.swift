import SwiftUI
import UIKit

/// The console, on the phone.
///
/// Everything `DiagnosticsLog` captured since launch — the `[ModelLibrary]`
/// block above all, which is what decides whether a model loaded — with Copy
/// and Share, so the block can go straight from the device into a chat
/// without Xcode in between.
///
/// The chrome is `GameScreen`'s one 34-point strip. Refresh, Copy and Share
/// ride in it — the navigation bar is hidden, so the old toolbar refresh had
/// to move there, and the two full-width buttons that used to sit above the
/// log were costing it sixty points of a landscape frame. The log now gets
/// everything below the strip.
struct DiagnosticsView: View {
    /// This screen is pushed from More, and `GameScreen` hides the navigation
    /// bar with its back button; the strip's chevron is the way back.
    @Environment(\.dismiss) private var dismiss
    @State private var text = DiagnosticsLog.shared.text
    @State private var copied = false

    var body: some View {
        GameScreen(
            "Diagnostics",
            subtitle: "What the app has printed since launch",
            dismiss: { dismiss() }
        ) {
            BarCount(value: "\(DiagnosticsLog.shared.count) lines", systemImage: "text.alignleft")
            BarButton(title: "Refresh", systemImage: "arrow.clockwise") {
                text = DiagnosticsLog.shared.text
                copied = false
            }
            BarButton(
                title: copied ? "Copied" : "Copy",
                systemImage: copied ? "checkmark" : "doc.on.doc.fill",
                tint: copied ? Theme.success : Theme.gold
            ) {
                UIPasteboard.general.string = text
                copied = true
            }
            shareControl
        } content: {
            if text.isEmpty {
                EmptyState(
                    icon: "terminal",
                    title: "Nothing yet",
                    message: "Open a battle or a summon first, then come back and refresh."
                )
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .panelBackground()
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            text = DiagnosticsLog.shared.text
        }
    }

    /// `ShareLink` is a view of its own, not an action, so it cannot be a
    /// `BarButton`; this wears `ScreenChrome`'s measurements so it reads as
    /// one beside Copy.
    private var shareControl: some View {
        ShareLink(item: text.isEmpty ? "Pantheon diagnostics: nothing logged yet." : text) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .black))
                Text("Share")
                    .font(Theme.body(11).weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.gold)
            .padding(.horizontal, 9)
            .frame(minWidth: ScreenChrome.control, minHeight: ScreenChrome.control)
            .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
            .overlay(ScreenChrome.controlShape.strokeBorder(Theme.gold.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share")
    }
}
