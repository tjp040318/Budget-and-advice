# 2D art — what to generate, and exactly where it goes

> **Status:** every asset on this page has been generated and is in
> `Pantheon/Resources/Portraits/` — 11 portraits, 5 stage backdrops, 2 summon
> banners, the spark sprite, and the 10-texture painted UI kit (section 5). What follows is how to regenerate or extend
> them. The tool is `tools/genart.py`, which calls Gemini's image models and
> saves at the exact size the app expects:
>
> ```bash
> export GEMINI_API_KEY=...                 # never commit this; *.key is ignored
> python3 tools/genart.py --prompt "..." --out Pantheon/Resources/Portraits/portrait_x.png --size 1024x1024
> python3 tools/genart.py --prompt "Edit this image ..." --ref base.png --out variant.png
> ```
>
> `--ref` is the important flag. The five Anubis portraits are one generation
> plus four reference edits, which is why they are the same character in the
> same pose; five independent prompts would not have held that. The banner
> used the base portrait as its reference for the same reason.

Every file below is optional: the game runs without any of them. But the cards
currently show a **letter on a gradient**, and the battle stage is an empty
coloured void, so these are the difference between "a prototype" and "a game".

Do them in the order they appear. The portraits alone are the biggest single
change available.

---

## How to get a file into the app

Same for every asset on this page.

1. Generate the image.
2. Crop/resize to the stated pixel size. Preview on a Mac does this:
   **Tools → Adjust Size**, uncheck *Scale proportionally* if you need an exact
   crop, then **File → Export** as PNG.
3. Put it in `Pantheon/Resources/Portraits/` (all 2D art lives here regardless
   of what it is — the folder does not exist in a fresh clone, so create it the
   first time).
4. `git add`, commit, push.
5. Rebuild. Nothing to register in Xcode: the target uses a filesystem-
   synchronised group, so a file in the folder is in the app.

**The filename is a contract.** The code looks these up by name. A typo means
the fallback renders and nothing tells you why. Copy the names exactly.

> One trap, because it has already bitten this project once: resources are
> copied **flat** into the app bundle, so two files anywhere under `Pantheon/`
> that share a filename will fail the build with "Multiple commands produce".
> `tools/swiftcheck.py` checks for it.

---

## 1. Character portraits — do these first

Five files, 1024×1024 PNG:

```
portrait_anubis_ember.png
portrait_anubis_tide.png
portrait_anubis_gale.png
portrait_anubis_radiance.png
portrait_anubis_umbra.png
```

Generate **one** base image, then run four recolours of it. They are the same
character in five elements, and they should look like it — that is the genre
convention and it is also four times less work.

### Base prompt

> Mobile gacha RPG character portrait, Anubis, Egyptian jackal-headed god,
> upper body and head facing three-quarter left, black jackal head with tall
> pointed ears and gold-rimmed eyes, striped nemes headdress, broad lapis and
> gold usekh collar, bare muscular chest, gold armbands, dark background with a
> subtle radial glow behind the head, dramatic rim lighting from behind,
> painterly semi-realistic game art, rich saturated colour, centred composition,
> square

Negative / avoid:

> full body, legs, weapon, text, watermark, logo, frame, border, UI, multiple
> characters, flat lighting, photo, blurry

### The five recolours

Append **one** line to the base prompt. Keep everything else identical, and if
your tool supports it, reuse the same seed so the pose does not drift.

| File | Append | Aura hex (already in code) |
|---|---|---|
| `portrait_anubis_ember` | `molten orange and black, glowing ember cracks across the collar, warm firelight` | `#F2703C` |
| `portrait_anubis_tide` | `deep teal and turquoise, wet obsidian sheen, cool underwater light` | `#3CA8F2` |
| `portrait_anubis_gale` | `pale jade and silver, wind-torn linen, cold high-altitude light` | `#5FD98A` |
| `portrait_anubis_radiance` | `white and pale gold, luminous, haloed, bright warm light from above` | `#FFD94F` |
| `portrait_anubis_umbra` | `deep violet and black, shadow smoke curling from the shoulders, cold underlight` | `#9B5FD9` |

### Framing that matters

The card crops to a **square** and darkens the lower third for the star row and
name (`UnitCard` in `Pantheon/UI/Common/Components.swift`). So:

- Put the head in the **upper two thirds**. Anything in the bottom quarter is
  covered.
- Leave the corners quiet. A rarity frame is drawn over them.
- Dark background, not transparent. PNG alpha is not used here.

### Enemies, when you get to them

Same recipe, one file each, no element suffix:

```
portrait_shabti.png   portrait_serpopard.png   portrait_sun_scarab.png
portrait_sandstone_sentinel.png   portrait_ammit.png   portrait_apep.png
```

---

### Sekhmet — the second family

Same recipe as Anubis: one base, four `--ref` recolours, the same five suffixes.

```
portrait_sekhmet_ember.png     portrait_sekhmet_tide.png     portrait_sekhmet_gale.png
portrait_sekhmet_radiance.png  portrait_sekhmet_umbra.png
```

Base prompt:

> Mobile gacha RPG character portrait, Sekhmet, Egyptian lioness-headed goddess
> of war, upper body and head facing three-quarter right, tawny golden lioness
> head with a short broad muzzle and fierce amber eyes, a solid gold sun disc
> behind the head, broad gold and carnelian usekh collar, crimson linen bodice,
> gold armbands, dark background with a subtle radial glow behind the head,
> dramatic rim lighting from behind, painterly semi-realistic game art, rich
> saturated colour, centred composition, square

Same negative list as Anubis, and the recolour lines are the Anubis table's. She
faces the opposite way to him on purpose, so two families read apart on a team
strip.

```bash
python3 tools/genart.py --prompt "<base prompt>. molten orange and black, glowing ember cracks across the collar, warm firelight" \
    --out Pantheon/Resources/Portraits/portrait_sekhmet_ember.png
python3 tools/genart.py --prompt "Edit this image: <recolour line>" --ref Pantheon/Resources/Portraits/portrait_sekhmet_ember.png \
    --out Pantheon/Resources/Portraits/portrait_sekhmet_tide.png
```

Until these exist the five Sekhmet cards show a letter on a gradient, which is
the designed fallback and not a bug.

## 2. Stage backdrops

Five files, 2048×2048 PNG. These replace the empty coloured void behind the
fighters, and after the portraits this is the biggest change on the list.

```
duat_gate_bg.png            reed_fields_bg.png
hall_of_two_truths_bg.png   serpent_deep_bg.png
arena_of_souls_bg.png
```

Prompt shape — swap the description per stage:

> Egyptian underworld environment background for a mobile RPG battle stage,
> DESCRIPTION, wide establishing view, no characters, no foreground objects,
> painterly game art, atmospheric depth, dramatic lighting, muted saturated
> palette

| File | DESCRIPTION | Palette to match the code |
|---|---|---|
| `duat_gate_bg` | a colossal sandstone gate at dusk, torchlit, drifting sand | warm brown `#4A3A28` |
| `reed_fields_bg` | endless pale green reed marsh under a low sun, still water | green `#3C4A38` |
| `hall_of_two_truths_bg` | a vast hypostyle hall of painted columns, shafts of gold light | gold `#5A4C33` |
| `serpent_deep_bg` | a black subterranean cavern, violet bioluminescence, deep water | violet `#2A1A38` |
| `arena_of_souls_bg` | a circular sand arena ringed by statues, hot overhead light | amber `#6E5A3C` |

Keep the centre and lower half **uncluttered and darker** — the fighters stand
there and detail behind them reads as noise. Push interest to the upper corners.

---

## 3. Particle sprite

One file, 128×128 PNG:

```
spark.png
```

> A soft white radial glow on a pure black background, centred, circular,
> fading smoothly to black at the edges, no hard edge

This one file upgrades **every** effect in the game at once — `VFXLibrary`
already checks for it and swaps it in wherever it currently draws untextured
points.

---

## 4. Summon banner

One file, 1284×800 PNG:

```
banner_duat_opens.png
```

> Mobile gacha summon banner splash, Anubis rising from a sandstone gate in the
> Egyptian underworld, dramatic backlight, gold and violet, cinematic, ornate,
> no text, no logo, no UI

Leave the **lower third quiet** — the rate text and the pull buttons sit there.

---

## Which generator

Any of them work. What actually matters:

- **Consistency across the five recolours** beats absolute quality. A tool that
  supports a fixed seed or an image reference is worth more here than a tool
  that makes one prettier picture. Midjourney's `--sref` / character reference
  and Flux's img2img both do this well.
- Generate **square** for portraits. Cropping a 16:9 render to 1:1 loses the
  composition you asked for.
- Ask for "no text, no watermark, no border" every time. Generators love adding
  frames, and a baked-in frame fights the rarity frame the code draws.

---

## 5. Painted UI chrome

Ten textures, all in `Pantheon/Resources/Portraits/`, all named `@3x` so a
512px source is ~171pt logical — small enough to 9-slice onto a 60pt panel:

```
ui_frame_common@3x.png     ui_frame_uncommon@3x.png   ui_frame_rare@3x.png
ui_frame_epic@3x.png       ui_frame_legendary@3x.png  ui_frame_mythic@3x.png
ui_panel@3x.png            ui_button_gold@3x.png      ui_button_dark@3x.png
ui_ribbon@3x.png
```

`Chrome` in `Pantheon/UI/Common/Theme.swift` is the single lookup; `Theme.panel`,
`PrimaryButton`, `SectionHeader` and `UnitCard` ask it first and draw their
gradient fallback if a file is missing. Cap insets live next to the lookup and
were measured off the art.

### How they were made, and how to make more

Two anchors first — `ui_frame_legendary` and `ui_panel` — then everything else
as a **reference edit** of one of those, so the whole kit shares one ornament
language. The six frames are edits of the legendary one, which is why their
geometry is identical and one set of insets serves all six.

The prompt discipline that makes a generated image 9-sliceable:

> corners ornate; the straight edges between corners a uniform repeating band
> that looks correct stretched; the centre a flat plain dark surface with NO
> ornament, NO emblem, NO gradient; straight-on, orthographic, filling the
> image edge to edge

Frames additionally have their flat centre keyed to transparent (luminance
< 56 inside the border band, 1.2px feather) so they sit *over* the portrait
with the corner ornament overlapping the art. The one-off script for that is
in the session history; it is twelve lines of Pillow.

For a new rarity or a new button shape: reference the nearest existing
texture, describe only what changes, keep the 9-slice sentence.
