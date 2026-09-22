"""The skirt pass over SHIPPED families (2026-09-22): cloth that hangs from
the waist and that Meshy's auto-rig bound to a hand or a forearm — Anhur's
tunic panel swung up with his khopesh — is given back to the hips and the
legs (character.reweight_skirt), in the shipped base and its LOD, in place;
the clip carriers keep their skinning, which the game never reads.

    python3 tools/skirt_pass.py --survey               # every shipped base: what would move
    python3 tools/skirt_pass.py anhur ptah             # re-weight these (base + _lod), in place
    python3 tools/skirt_pass.py --all                  # every family the survey flags

Judge a family on tools/base_plus_clip.py afterwards (the standing idle and
an attack), never on the count alone."""
import argparse, shutil, sys, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import character  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "Pantheon" / "Resources" / "Models"
CLIPS = ("attack_basic", "attack_heavy", "ultimate", "idle", "idle_combat", "death", "hit_react", "victory", "walk", "lod")


def families():
    out = []
    for p in sorted(BUNDLE.glob("*.usdz")):
        stem = p.stem
        if any(stem.endswith("_" + c) for c in CLIPS) or stem.startswith(("prop_", "boss_", "enemy_")):
            continue
        out.append(stem)
    return out


def count(name):
    char = character.read_usdz(BUNDLE / f"{name}.usdz")
    return character.reweight_skirt(char), len(char.points)


def apply(name):
    moved = 0
    for suffix in ("", "_lod"):
        src = BUNDLE / f"{name}{suffix}.usdz"
        if not src.exists():
            continue
        char = character.read_usdz(src)
        n = character.reweight_skirt(char)
        if n == 0:
            print(f"  {src.name}: nothing to move")
            continue
        tmp = Path(tempfile.mkdtemp()) / src.name
        character.write_usdz(char, tmp)
        shutil.move(str(tmp), str(src))
        print(f"  {src.name}: {n:,} vertices re-bound, written")
        moved += n
    return moved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("--survey", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()
    if args.survey or args.all:
        flagged = []
        for name in families():
            try:
                n, total = count(name)
            except Exception as exc:  # noqa: BLE001
                print(f"{name}: unreadable ({exc})")
                continue
            if n:
                flagged.append(name)
                print(f"{name}: {n:,} of {total:,} ({100 * n / total:.1f}%) hand-held waist cloth")
            sys.stdout.flush()
        print(f"\n{len(flagged)} flagged: {' '.join(flagged)}")
        if args.all:
            for name in flagged:
                print(f"== {name}")
                apply(name)
        return
    for name in args.names:
        print(f"== {name}")
        apply(name)


if __name__ == "__main__":
    main()
