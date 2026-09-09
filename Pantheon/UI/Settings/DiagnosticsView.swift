import SwiftUI
import UIKit

/// The console, on the phone.
///
/// Everything `DiagnosticsLog` captured since launch — the `[ModelLibrary]`
/// block above all, which is what decides whether a model loaded — with Copy
/// and Share, so the block can go straight from the device into a chat
/// without Xcode in between.
struct DiagnosticsView: View {
    @State private var text = DiagnosticsLog.shared.text
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What the app has printed since launch. Copy it or share it straight into a chat. "
                     + "Open a battle or a summon first if the block you want is not here yet, then come back.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    PrimaryButton(title: copied ? "Copied" : "Copy all", systemImage: "doc.on.doc.fill") {
                        UIPasteboard.general.string = text
                        copied = true
                    }
                    ShareLink(item: text.isEmpty ? "Pantheon diagnostics: nothing logged yet." : text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(Theme.body(14).weight(.semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Theme.gold, lineWidth: 1)
                            )
                    }
                }

                Text("\(DiagnosticsLog.shared.count) lines")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textSecondary)

                Text(text.isEmpty ? "Nothing yet." : text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .panelBackground()
            }
            .padding(12)
        }
        .screen("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    text = DiagnosticsLog.shared.text
                    copied = false
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            text = DiagnosticsLog.shared.text
        }
    }
}
