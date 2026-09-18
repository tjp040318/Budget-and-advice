"""The serious remake's roster (2026-09-18; the owner, 6,505 credits: "Go ahead
and work on the upgrades for the characters … I DONT want the cartoony, Chibi
Stlye. I want more serious, more detailed work"): every rigged family with the
sentence its serious concept is painted from, its palette, its clip kit and
its height, in the order the credits are spent — the five gods, then the
roster as it was made, then the awakened forms, then the bosses.

    python3 tools/batch/serious_roster.py            # writes serious_wave.txt and serious_concepts.tsv
    python3 tools/batch/serious_roster.py --print    # the table

The sentences are the ones every chibi concept was painted from
(tools/batch/concepts_*.sh: the design IS the identity; only the style
changes), "as an original cartoon character" read as "as an original
character"; the first roster's, the awakened forms' and the bosses' are
written here. A mesh made from these NEVER goes through the proportion
pass (CLAUDE.md, the serious-look rule)."""
import re, glob, os, sys, json
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

HAND = {
    # family: (sentence, palette, kit, height)
    "artemis": ("The Greek goddess of the hunt as an original character: an athletic young woman with auburn hair tied back under a silver crescent diadem, a short green hunting chiton ending above the knees, leather bracers, laced sandals with both feet a shoulder-width apart, a quiver of arrows on her back, a short recurve bow held upright in her left hand, gripped at its middle close against the outside of her left leg, its lower tip at knee height clear of the ground and its upper tip no higher than her shoulder. Palette forest green, silver, tan leather.",
               "silver, forest green, white", "archer", 1.95),
    "bastet": ("The Egyptian cat goddess as an original character: a slender athletic woman with the sleek black-furred head of a cat with gold hoop earrings, a wide gold collar, a fitted green and gold bodice, a short pleated linen kilt ending at mid-thigh, slit at the sides so both legs are fully separate and visible, gold arm bands and anklets, bare feet a shoulder-width apart with clear space between the knees, empty open hands hanging at her sides a little away from the body. Palette black, emerald green, gold.",
               "black, emerald green, gold", "blade", 1.95),
    "anubis": ("The Egyptian jackal-headed god of embalming as an original character: a tall lean man with the black-furred head of a jackal with tall pointed ears, a striped lapis-blue and gold nemes headcloth, a broad gold and obsidian collar and chest plate, a white kilt with lapis panels and a gold belt, gold arm bands and sandals, a gold crook held down at his right side flat against the thigh.",
               "black and burnished gold and lapis blue, black jackal fur, striped nemes, gold and lapis armour", "blade", 2.05),
    "sekhmet": ("The Egyptian lioness goddess of war as an original character: a tall powerful woman with the black-furred head of a lioness, a gold sun-disc crown with a rearing cobra, a broad lapis and carnelian collar, a fitted gold scale bodice, a crimson war skirt with hanging gold plates ending above the knees, gold arm bands and sandals, feet a shoulder-width apart, a short curved bronze khopesh no longer than her forearm held point-down in her right hand flat along the outside of her right thigh with its curve turned in against the leg, its tip above the knee and nothing reaching the ground.",
                "crimson and burnished gold and near-black, black lioness fur, gold sun-disc crown, lapis and carnelian inlays", "blade", 2.00),
    "thoth": ("The Egyptian ibis-headed god of wisdom as an original character: a slender scholarly man with the white-feathered head and long curved black beak of an ibis, a lunar crescent and disc on his brow, a white and turquoise pleated linen robe with a broad gold collar ending above the ankles, gold arm bands and sandals, a rolled papyrus scroll held down at his right side flat against the thigh.",
              "white, gold, lapis blue", "caster", 2.05),
    "ares": ("The Greek god of war as an original character: a towering broad-shouldered warrior with a hard bearded face and short dark hair under a bronze Corinthian helmet with a tall crimson horsehair crest, a bronze muscled cuirass engraved with a boar and crossed spears, a crimson tunic under a skirt of leather pteruges, bronze greaves and vambraces, leather sandals, a short bronze xiphos sword held down at his right side flat against the thigh, no cape and no cloak, no shield.",
             "bronze, crimson, black", "blade", 2.10),
    "heracles": ("The Greek hero of the twelve labours as an original character: a massive muscular bearded man with curly dark hair, the head and pelt of a lion worn as a hood with the pelt hanging close down his back, a short brown belted tunic, leather bracers and sandals, a heavy knotted olive-wood club held down at his right side flat against the thigh.",
                 "tawny lion pelt, bronze, olive brown", "heavy", 2.10),
    "perseus": ("The Greek hero Perseus as an original character: a lean athletic young man with short curly dark hair under a winged bronze helmet, a short white tunic under a bronze scale breastplate, winged sandals, a leather satchel at his hip, a curved bronze harpe sword held down at his right side flat against the thigh, no shield.",
                "bronze, white, sky blue", "blade", 1.90),
    "hoplite": ("A Greek hoplite soldier as an original character: a stern bearded man in a bronze Corinthian helmet with a white horsehair crest, a bronze bell cuirass over a short crimson tunic, bronze greaves, leather sandals, a short bronze sword held down at his right side flat against the thigh, no shield and no spear.",
                "bronze, crimson, white", "blade", 1.85),
    "satyr": ("A Greek satyr as an original character: a wiry goat-legged man with shaggy brown fur from the waist down and cloven hooves, short curling horns, pointed ears and a pointed beard, bare-chested with a wreath of ivy and a leather strap across the chest, a wooden pan-flute held down at his right side flat against the thigh.",
              "brown fur, tan skin, ivy green", "caster", 1.70),
    "harpy": ("A Greek harpy as an original character: a fierce woman with wild dark hair, large brown-grey feathered wings folded flat against her back, human arms with taloned hands, bird-clawed feet, a tattered grey feathered tunic ending above the knees, a bone dagger held down at her right side flat against the thigh.",
              "grey-brown feathers, bone white, dark grey", "blade", 1.75),
    "shabti": ("An Egyptian shabti figurine come to life as an original character: a stiff man-shaped figure of glazed faience with painted black hieroglyphs down the front of its body, a plain nemes headcloth, a serene painted face, a small bronze hoe held down at its right side flat against the thigh.",
               "faience blue, black, gold", "blade", 1.70),
    "ares_awakened": ("The Greek god of war in his awakened form as an original character: a towering bearded Spartan in a gold-chased Corinthian helmet with a crimson crest, an ornate gold muscled cuirass engraved with glowing crimson runes, a crimson tunic under gold-tipped leather pteruges, gold greaves and vambraces, sandals, a short gold sword held down at his right side flat against the thigh, no cape and no cloak, no shield.",
                      "burnished gold, crimson, black", "blade", 2.10),
    "sekhmet_awakened": ("The Egyptian lioness goddess of war in her awakened form as an original character: a tall powerful woman with the black-furred head of a lioness, a tall gold sun-disc crown with two rearing cobras, a broad gold collar set with carnelian, gold scale armour over a crimson war skirt with hanging gold plates ending above the knees, gold arm bands and sandals, a curved gold khopesh sword held down at her right side flat against the thigh.",
                         "burnished gold, crimson, near-black lioness fur", "blade", 2.00),
    "thoth_awakened": ("The Egyptian ibis-headed god of wisdom in his awakened form as an original character: a slender man with the white-feathered head and long curved black beak of an ibis, a gold lunar crown on his brow, a white and gold pleated robe with a lapis collar and gold hieroglyphs down the front ending above the ankles, gold arm bands and sandals, a gold-capped papyrus scroll held down at his right side flat against the thigh.",
                       "white, burnished gold, lapis blue", "caster", 2.05),
    "zeus_awakened": ("The Greek king of the gods in his awakened form as an original character: a tall powerful man with a long white beard and white hair under a gold laurel crown, ornate gold scale armour over a white himation with a gold meander border ending above the ankles, gold arm bands and sandals, a gold thunderbolt held down at his right side flat against the thigh.",
                      "white, burnished gold, storm blue", "blade", 2.15),
    "boss_colossus": ("A colossal bronze statue of a Greek warrior come to life as an original character: an enormous man-shaped figure of green-patinaed bronze plates with a stern classical face, a crested bronze helmet, a sculpted bronze cuirass and greaves, a bronze sword held down at his right side flat against the thigh.",
                      "patina green, bronze, gold", "heavy", 8.00),
    "boss_unwrapped_king": ("The unwrapped mummy of an Egyptian king as an original character: a tall gaunt dried corpse in trailing loosened linen wrappings, a cracked tarnished gold death mask over a withered face, a jewelled collar and a tattered royal kilt, a broken gold crook held down at his right side flat against the thigh.",
                            "tarnished gold, linen, dust grey", "caster", 6.00),
    "hathor": (None, "gold, turquoise, white", "caster", 1.90),
}
SKIP = {"zeus", "sandstone_sentinel", "boss_jotunn"}   # zeus_serious exists; the two are unrigged stand-ins
ORDER_FIRST = ["ares", "sekhmet", "anubis", "thoth"]


def harvest():
    sentences = {}
    for sh in sorted(glob.glob(os.path.join(REPO, "tools/batch/concepts_*.sh"))):
        for m in re.finditer(r'^gen\s+(\S+)\s+"((?:[^"\\]|\\.)*)"', open(sh).read(), re.M):
            sentences[m.group(1)] = m.group(2)
    specs = {}
    for txt in ("wave3.txt", "wave4.txt", "wave5_awakened.txt", "wave5_rigfix.txt", "remake_wave.txt", "m7_wave.txt"):
        p = os.path.join(REPO, "tools/batch", txt)
        if not os.path.exists(p):
            continue
        for line in open(p):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(":")
            if len(parts) < 4:
                continue
            asset, concept, height, palette = parts[:4]
            kit = parts[4] if len(parts) > 4 else "blade"
            family = parts[5] if len(parts) > 5 else re.sub(r"_(hd|m7|v\d+)$", "", asset)
            specs[family] = dict(height=float(height), palette=palette, kit=kit)
    return sentences, specs


def serious_sentence(text):
    text = text.replace("as an original cartoon character", "as an original character")
    text = text.replace("An original cartoon ", "An original ").replace("original cartoon", "original")
    return text


def roster():
    sentences, specs = harvest()
    families = sorted(os.path.basename(f)[:-len("_idle_combat.usdz")]
                      for f in glob.glob(os.path.join(REPO, "Pantheon/Resources/Models/*_idle_combat.usdz")))
    rows = {}
    for f in families:
        if f in SKIP:
            continue
        hand = HAND.get(f)
        base = f[:-len("_awakened")] if f.endswith("_awakened") else f
        sentence = (hand[0] if hand and hand[0] else None) or sentences.get(f) or sentences.get(base)
        spec = specs.get(f) or {}
        if hand:
            spec = dict(palette=hand[1], kit=hand[2], height=hand[3]) | ({"palette": spec["palette"]} if spec.get("palette") and not hand[1] else {})
        if not sentence or not spec:
            print(f"  skipped {f}: {'no sentence' if not sentence else 'no palette/kit/height'}", file=sys.stderr)
            continue
        if f.endswith("_awakened") and not (hand and hand[0]):
            sentence = sentence.rstrip(".") + ", in an awakened form with gold-chased armour and faintly glowing accents."
        rows[f] = dict(family=f, sentence=serious_sentence(sentence), palette=spec["palette"], kit=spec["kit"], height=float(spec["height"]))
    ordered = [rows[f] for f in ORDER_FIRST if f in rows]
    ordered += [r for f, r in rows.items() if f not in ORDER_FIRST and not f.endswith("_awakened") and not f.startswith("boss_")]
    ordered += [r for f, r in rows.items() if f.endswith("_awakened") and f not in ORDER_FIRST]
    ordered += [r for f, r in rows.items() if f.startswith("boss_")]
    return ordered


def main():
    rows = roster()
    if "--print" in sys.argv:
        for r in rows:
            print(f"{r['family']:22s} {r['height']:.2f} {r['kit']:7s} {r['palette'][:36]:36s} {r['sentence'][:70]}")
        print(f"{len(rows)} families", file=sys.stderr)
        return
    with open(os.path.join(REPO, "tools/batch/serious_wave.txt"), "w") as w:
        w.write("# The serious remakes, one per line: asset:concept:height:palette:kit:family (tools/batch/serious_roster.py).\n"
                "# AI_MODEL=meshy-7 bash tools/batch/wave_run.sh tools/batch/serious_wave.txt 500\n")
        for r in rows:
            w.write(f"{r['family']}_serious:Art/Concepts/{r['family']}_serious_sw.png:{r['height']:.2f}:{r['palette']}:{r['kit']}:{r['family']}\n")
    with open(os.path.join(REPO, "tools/batch/serious_concepts.tsv"), "w") as w:
        for r in rows:
            w.write(f"{r['family']}\t{r['sentence']}\n")
    print(f"{len(rows)} families -> tools/batch/serious_wave.txt, serious_concepts.tsv")


if __name__ == "__main__":
    main()
