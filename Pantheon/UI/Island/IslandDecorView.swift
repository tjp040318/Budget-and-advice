import SwiftUI

/// The island's decorations: the catalogue of pieces on the left, the piece
/// picked and the six sand patches on the right. A piece is bought once with
/// drachma and kept for good; standing it in a patch, moving it or taking
/// it in is free; a patch holds one. Summoners War's decoration shop and
/// its edit mode on one screen (`Docs/PLAN.md`, *The home island as
/// Summoners War's*). Every piece is a prop already in the bundle, drawn
/// here from its rendered thumbnail (`decor_<id>`, `tools/decor_thumbs.py`).
struct IslandDecorView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = IslandDatabase.decorations.first?.id ?? ""

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        GameScreen("Decorate the island", subtitle: "Pieces of stone for the sand, kept for good", dismiss: { dismiss() }) {
            BarWallet(wallet: store.player.wallet, shows: [.drachma])
        } content: {
            HStack(alignment: .top, spacing: 10) {
                catalogue
                panel
                    .frame(width: 300)
            }
            .padding(10)
        }
    }

    // MARK: - The catalogue

    private var catalogue: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(IslandDatabase.decorations) { piece in
                    tile(piece)
                }
            }
            .padding(2)
        }
    }

    private func tile(_ piece: IslandDecoration) -> some View {
        let player = store.player
        let owned = IslandDecorService.owns(piece.id, player: player)
        let locked = player.level < piece.unlockLevel
        let standing = player.islandDecor?.values.contains(piece.id) ?? false
        let picked = selected == piece.id

        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selected = piece.id
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.stonePlate)
                    thumbnail(piece, size: 78)
                        .padding(5)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Theme.surfaceHigh)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                    if standing {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.gold)
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(picked ? Theme.gold : Theme.stroke, lineWidth: picked ? 2 : 1)
                )
                Text(piece.title)
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                priceLine(piece, owned: owned, locked: locked)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(picked ? Theme.surfaceHigh : Theme.surfaceRaised)
            )
        }
        .buttonStyle(PlateButtonStyle())
        .opacity(locked ? 0.8 : 1)
    }

    private func priceLine(_ piece: IslandDecoration, owned: Bool, locked: Bool) -> some View {
        Group {
            if owned {
                Chip(text: "Owned", systemImage: "checkmark", tint: Theme.success, filled: true)
            } else if locked {
                Chip(text: "Level \(piece.unlockLevel)", systemImage: "lock.fill", tint: Theme.textSecondary)
            } else {
                Chip(text: piece.price.formatted(), systemImage: "circle.hexagongrid.fill", tint: Theme.gold)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ piece: IslandDecoration, size: CGFloat) -> some View {
        if BundleImage.exists(piece.thumbnail) {
            BundleImage(name: piece.thumbnail, renderedAt: size)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: piece.glyph)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.gold)
        }
    }

    // MARK: - The piece and the patches

    private var panel: some View {
        let piece = IslandDatabase.decoration(selected) ?? IslandDatabase.decorations[0]
        let player = store.player
        let owned = IslandDecorService.owns(piece.id, player: player)
        let locked = player.level < piece.unlockLevel
        let affordable = player.wallet.drachma >= piece.price
        let figures = piece.height / IslandSceneView.figureHeight

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail(piece, size: 96)
                    .padding(6)
                    .frame(width: 96, height: 96)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.stonePlate))
                VStack(alignment: .leading, spacing: 4) {
                    Text(piece.title)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(piece.blurb)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: "Stands %.1f× a figure's height", figures))
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if owned {
                SectionHeader(title: "Where it stands")
                VStack(spacing: 2) {
                    ForEach(IslandDatabase.decorSlots) { slot in
                        slotRow(slot, piece: piece)
                    }
                }
            } else if locked {
                PrimaryButton(title: "Reach level \(piece.unlockLevel)", systemImage: "lock.fill", isEnabled: false) {}
            } else {
                PrimaryButton(title: "Buy · \(piece.price.formatted())", systemImage: "circle.hexagongrid.fill", isEnabled: affordable) {
                    if store.buyDecoration(piece.id) {
                        Juice.notify(.success)
                    }
                }
                if !affordable {
                    Text("Not enough drachma — the campaign and the Night Market pay it.")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .modifier(PanelBackground())
    }

    /// One sand patch: what stands there, and Place, Swap or Clear for the
    /// piece picked.
    private func slotRow(_ slot: DecorSlot, piece: IslandDecoration) -> some View {
        let standingID = store.player.islandDecor?[slot.id]
        let standing = standingID.flatMap { IslandDatabase.decoration($0) }
        let isHere = standingID == piece.id

        return HStack(spacing: 8) {
            Image(systemName: isHere ? "mappin.circle.fill" : "circle.dashed")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHere ? Theme.gold : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.title)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(standing?.title ?? "Empty")
                    .font(Theme.body(9))
                    .foregroundStyle(isHere ? Theme.gold : Theme.textSecondary)
            }
            Spacer()
            if isHere {
                pill("Take in", tint: Theme.stroke) {
                    store.clearDecoration(in: slot.id)
                }
            } else {
                pill(standing == nil ? "Place" : "Swap", tint: Theme.gold) {
                    store.placeDecoration(piece.id, in: slot.id)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func pill(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiConfirm, volume: 0.6)
            action()
        } label: {
            Text(title.uppercased())
                .font(Theme.title(12))
                .tracking(0.8)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(tint))
                .overlay(Capsule().strokeBorder(Theme.goldDeep.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PlateButtonStyle())
    }
}
