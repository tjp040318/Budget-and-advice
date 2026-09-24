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

    /// The pieces, three to a row, resting on whole rows (`RestingList`):
    /// run 221 cut the grid flat at the panel's foot on a ten-point sliver of
    /// its third row. A tile that would show as a sliver is not drawn, the
    /// foot fades, and the chevron there says the catalogue goes on.
    private var catalogue: some View {
        RestingList {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(IslandDatabase.decorations) { piece in
                    tile(piece)
                        .restingRow()
                }
            }
            .padding(2)
            .padding(.bottom, 20)
        }
    }

    private func tile(_ piece: IslandDecoration) -> some View {
        let player = store.player
        let owned = IslandDecorService.owns(piece.id, player: player)
        // A piece already owned is never locked, whatever the level: run
        // 217's tour player (level 1) owned the sphinx and it wore a padlock
        // over its thumbnail beside its "Owned" chip.
        let locked = !owned && player.level < piece.unlockLevel
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
                    // A piece out of reach is the piece dimmed, with the
                    // lock on a dark badge in the corner — the Lessons'
                    // locked socket. A white padlock stood over the middle
                    // of the Doric and Lotus columns until run 221.
                    thumbnail(piece, size: 78)
                        .padding(5)
                        .saturation(locked ? 0.6 : 1)
                        .opacity(locked ? 0.55 : 1)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.onGlass)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.ink.opacity(0.85)))
                            .overlay(Circle().strokeBorder(Theme.bronze, lineWidth: 1))
                            .padding(5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
                // Two lines rather than an ellipsis: "Statue of the
                // Thunderer" is wider than a tile.
                Text(piece.title)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                priceLine(piece, owned: owned, locked: locked)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(picked ? Theme.surfaceHigh : Theme.surfaceRaised)
            )
        }
        // A piece of the catalogue's scrolling grid: quiet, its tap kept in
        // the action, on a finished tap (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet))
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

    /// Every thumbnail is one 240-pixel render, and most fill it; the
    /// sphinx, crouched and seen head on, fills 30% of its width and 41% of
    /// its height, and sat small in its tile beside the rest (run 221). A
    /// render like that is drawn larger from its foot, the way
    /// `PortraitPainting` zooms a full-figure card to its bust, and fills
    /// three quarters of its tile's height as the tripod does. A render
    /// framed tight by `tools/decor_thumbs.py` is the sharper cure, and this
    /// stops applying the moment a piece leaves the table.
    private static let thumbnailZoom: [String: CGFloat] = ["sphinx": 1.8]
    /// Where a render's pieces stand: its ground line, 97% down.
    private static let thumbnailFoot = UnitPoint(x: 0.5, y: 0.965)

    @ViewBuilder
    private func thumbnail(_ piece: IslandDecoration, size: CGFloat) -> some View {
        if BundleImage.exists(piece.thumbnail) {
            BundleImage(name: piece.thumbnail, renderedAt: size)
                .aspectRatio(contentMode: .fit)
                .scaleEffect(Self.thumbnailZoom[piece.id] ?? 1, anchor: Self.thumbnailFoot)
        } else {
            Image(systemName: piece.glyph)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(Theme.gold)
        }
    }

    // MARK: - The piece and the patches

    /// The piece picked over the six sand patches, the height of the content
    /// and no taller: the patches are one-line rows in a scroll that ends
    /// above the home indicator. Run 217 drew them as two-line rows under a
    /// 96-point thumbnail in a panel that did not scroll, so "Eastern shore"
    /// was cut by the screen's foot and "By the grove" could not be reached.
    /// At rest the six fit (a 72-point head, 28 a row round the 28-point
    /// plates, six between the parts); a long piece's name wraps its row and
    /// the list scrolls rather than cut anything.
    private var panel: some View {
        let piece = IslandDatabase.decoration(selected) ?? IslandDatabase.decorations[0]
        let player = store.player
        let owned = IslandDecorService.owns(piece.id, player: player)
        let locked = !owned && player.level < piece.unlockLevel
        let affordable = player.wallet.drachma >= piece.price
        let figures = piece.height / IslandSceneView.figureHeight

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail(piece, size: 72)
                    .padding(5)
                    .frame(width: 72, height: 72)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.stonePlate))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(piece.title)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(piece.blurb)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(format: "Stands %.1f× a figure's height", figures))
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if owned {
                SectionHeader(title: "Where it stands")
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(IslandDatabase.decorSlots) { slot in
                            slotRow(slot, piece: piece)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else if locked {
                PrimaryButton(title: "Reach level \(piece.unlockLevel)", systemImage: "lock.fill", isEnabled: false) {}
                Spacer(minLength: 0)
            } else {
                PrimaryButton(title: "Buy · \(piece.price.formatted())", systemImage: "circle.hexagongrid.fill", isEnabled: affordable) {
                    if store.buyDecoration(piece.id) {
                        Juice.notify(.success)
                    }
                }
                if !affordable {
                    Text("Not enough drachma — the campaign and the Night Market pay it.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(PanelBackground())
    }

    /// One sand patch on one line: its name, what stands there, and Place,
    /// Swap or Take in for the piece picked. The dashed ring is an empty
    /// patch, the gold pin the piece picked standing there.
    private func slotRow(_ slot: DecorSlot, piece: IslandDecoration) -> some View {
        let standingID = store.player.islandDecor?[slot.id]
        let standing = standingID.flatMap { IslandDatabase.decoration($0) }
        let isHere = standingID == piece.id
        let standingName = standing?.title ?? "Empty"

        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: isHere ? "mappin.circle.fill" : "circle.dashed")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHere ? Theme.gold : Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(slot.title)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                // What stands there wraps under itself rather than cut:
                // "Statue of the Thunderer" is longer than the row.
                Text("· \(standingName)")
                    .font(Theme.body(11))
                    .foregroundStyle(isHere ? Theme.goldDim : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if isHere {
                pill("Take in", gold: false) {
                    store.clearDecoration(in: slot.id)
                }
            } else {
                pill(standing == nil ? "Place" : "Swap", gold: true) {
                    store.placeDecoration(piece.id, in: slot.id)
                }
            }
        }
        .frame(minHeight: 28)
    }

    /// A patch's act on a plate of one size, 84 by 28 (TAKE IN, the widest,
    /// is 60 points of Cinzel): PLACE and SWAP in `PrimaryButton`'s gold,
    /// lit from above, with ink words; TAKE IN in bronze with cream words, a
    /// quieter act but one that can be done. Run 221 had khaki 22-point
    /// pills of three widths, and TAKE IN in the pale taupe of a disabled
    /// control.
    private func pill(_ title: String, gold: Bool, action: @escaping () -> Void) -> some View {
        // The colours picked before the chain, so its modifiers type-check
        // without a ternary among them.
        let ink: Color = gold ? Theme.ink : Theme.onGlass
        let rim: Color = gold ? Color(hex: "#FFE9A8").opacity(0.55) : Theme.goldDeep.opacity(0.7)
        return Button {
            // The press ticks and taps on touch-down; the confirm is the
            // "done" (2026-09-24).
            AudioLibrary.shared.play(.uiConfirm, volume: 0.6)
            action()
        } label: {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(0.8)
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(minWidth: 84, minHeight: 28)
                .background(pillPlate(gold: gold))
                .overlay(
                    Capsule().strokeBorder(rim, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 2, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(GamePressStyle(.plate))
    }

    /// The pill's metal: `PrimaryButton`'s four gold stops with its gloss, or
    /// bronze falling to the deep gold, glossed less. A switch between two
    /// fills, never a ternary between two gradients' worth of views.
    @ViewBuilder
    private func pillPlate(gold: Bool) -> some View {
        if gold {
            Capsule()
                .fill(LinearGradient(
                    colors: [Color(hex: "#FFE9A8"), Color(hex: "#E2BF62"), Theme.gold, Color(hex: "#7A5B1C")],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                                  startPoint: .top, endPoint: .center))
                )
        } else {
            Capsule()
                .fill(LinearGradient(
                    colors: [Theme.bronze, Color(hex: "#7A5F30"), Theme.goldDeep],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                                  startPoint: .top, endPoint: .center))
                )
        }
    }
}
