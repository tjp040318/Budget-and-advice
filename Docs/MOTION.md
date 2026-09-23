# Motion: every family its own attacks (2026-09-23)

The owner: "One thing we have to work on is how almost all of the characters
have the same pose and attacks when they should have their own." This file
holds the research, the options with their costs, the choice, the pilot that
tested it, and the assignment for the whole roster. The tool is
`tools/motion_palette.py`; the motions are `Art/Motions/preset_<id>.motion.npz`,
catalogued in `Art/Motions/palette.json`.

## 1. The fault, measured

Every family's clips were Meshy **presets** applied to its own rig by kit
(`tools/meshy.py` `DEFAULT_CLIPS`, `CLIP_SETS`). Read off the 115 serious
manifests (`Art/Models/*_serious.meshy.json`):

| attack set (basic, heavy, ultimate) | families |
|---|---|
| 219 Right-hand Sword Slash, 242 Charged Slash, 102 Sword Judgment | 46 |
| 129 Mage Spell Cast, 125 Charged Spell Cast, 126 Charged Spell Cast 1 | 42 |
| 219, 128 Heavy Hammer Swing, 127 Charged Ground Slam | 16 |
| 224 Archery Shot, 226 Archery Shot 2, 222 Draw and Shoot from Back | 6 |
| four near-copies (240 Thrust Slash as a basic, one missing clip) | 5 |
| **victory: 412 Victory** | **all 115** |
| **battle stance: 89 Combat Idle** | **all 115** |

So the whole roster fights with four bodies and poses with one. The standing
idle (`tools/stand_idle.py`) is derived from 89 for every family, so the stages
share one pose as well.

While measuring, the palette's boards turned up **four timing faults in the
presets as shipped today**. They are separate from the sameness, and they
matter as much (§5).

## 2. How the genre does it

No source reachable from here documents these studios' animation pipelines
(a web search found nothing technical, and the data sites are closed to this
environment). What follows is what the games show on screen.

- **Summoners War.** The unit of identity is the FAMILY. Every monster family
  (Valkyrja, Inugami, Vampire…) is one rig with its own idle stance, its own
  motion for each of its 3–4 skills, a hit, a death and a victory pose. The
  five elements share the family's rig and body motions and differ in texture,
  effect and skill kit. No two families swing the same way. The third skill
  plays with a short camera push and its own effect, and the body motion is
  the family's own.
- **Epic Seven.** 2D skeletal (Spine) heroes, every one with its own S1 and S2
  and a full-screen, hand-animated S3 cut-scene. It is the most expensive
  approach in the genre, and it is why E7's roster grows slowly.
- **Raid: Shadow Legends.** 3D champions on shared humanoid skeletons, each
  with its own skill animations. Bodies are shared within a skeleton type and
  motion is authored per champion, often from a studio library varied per
  character.

The common rule: **a family never shares its attack set with another family,
and its elements share it.** The game already models the second half:
`ModelSpec.assetName` is shared by a family's five elements, so one clip set
per family is exactly the genre's granularity.

## 3. What the tools can do

- **Meshy's preset library**: 678 motions (`python3 tools/meshy.py library`).
  Applying one to a rig is **3 credits a clip per rig** (Animation API,
  `rig_task_id` + `action_id`), and only while that rig task lives. **A rig
  task now expires in under five days**: the 2026-09-19 rigs (Poseidon, Sif,
  Odin) and their clip tasks answered 404 on 2026-09-23. The preset preview
  GIFs are on `cdn.meshy.ai`, which the proxy refused today, so presets were
  chosen by name and judged on our own boards after buying.
- **Meshy Text to Motion**: a clip from a sentence, 10 credits (prime) + 3 to
  apply to a rig, 2–10 s. The five gods' 15 bespoke clips were made this way
  (2026-09-15).
- **`tools/retarget.py`** (2026-09-18): carries a motion from any Meshy rig to
  any other, offline and free, as a world-space rotation delta per joint (the
  rigs share Meshy's 24 joint names). **Measured today against Meshy's own
  application of the same preset** (`motion_palette.py compare 219
  tyr_serious`, and the same on `vidar_serious`): joint rotations within a
  median **1.3–1.5°** (90th percentile 4.0–6.7°), hands within **3.6–3.8 cm**
  of Meshy's relative to the hips, feet 2.8–3.1 cm, head 1.0 cm. The only
  larger gap is an ~8 cm offset of the whole root, which `mesh.py`'s root lock
  and grounding remove at shipping. For practical purposes, our retarget IS
  Meshy's application.
- The consequence: **a preset (or a bespoke motion) has to be bought only
  once, on any live rig**, archived as a `.motion.npz`, and put on every family
  for nothing, whether or not the family's own rig is still alive at Meshy.

## 4. The options and the choice

| option | what | credits | result |
|---|---|---|---|
| **A. Preset palette** (chosen) | buy each preset once on one live donor rig (3), archive it, retarget a distinct combination onto every family (free) | 45 spent for the first 15. The recommended expansion is 36 more presets, **108**. Roll-out 0 | every family its own five clips from a 31→67-motion library; timing faults fixed on the way |
| A′. Per-family preset application | the old way: 3 per clip per rig | 5 × 3 × 115 = **1,725**, and only for rigs under five days old (40 of the 280 rig tasks on record today) | the same motions as A, measured equal |
| **B. Signature 5★ ultimates** (recommended next) | Text to Motion, one sentence per 5★ family, applied to the donor and retargeted free to the base AND the awakened form | 19 5★ families without one × 13 = **247** | a genre-level signature move where the owner looks most |
| C. Full bespoke | basic, heavy and ultimate from sentences for every family | 94 × 3 × 13 = **3,666** (awakened forms reuse); with stance and victory, 94 × 5 × 13 = **6,110** | Summoners War's standard; needs a credit purchase (balance 549, floor 500) |
| (free multiplier) | a mirrored cast (left/right swapped), for casters and the unarmed only (a weapon hand cannot mirror) | 0 | not built; worth adding to `prepare` if the caster pool stays thin |

**The choice: A now, B next, C only for the gods the owner names.** A turns a
roster of four bodies into 113 distinct sets for 45 credits. With the 108-credit
expansion no two families in a kind share more than one attack. B puts a bespoke
signature on the 5★ ultimates, the moves the genre films with a camera push.
C costs 15× A+B for a gain the owner would see mostly on the families he plays.

A also changes what a NEW family costs. Every clip a battle needs (stance,
three attacks, hit 178, death 8, victory, walk 30) is now in the archive, so
a remake needs only its mesh and rig (30 + 5 = 35 credits) instead of 68. The
eight preset clips `wave_run.sh` buys per family are no longer needed. (Not
changed yet: `tools/meshy.py` still buys them. That is a one-line change to
`BATTLE_CLIPS` on the owner's word.)

## 5. Four timing faults in the shipped presets

The game fires the damage, the flash and the hit-stop at
`BattleSceneController.contactFraction`. The five gods have rows of their own;
every other family uses 0.42 / 0.55 / 0.62 of the clip after `UnitNode.play`
retimes it to its contract (1.3 / 1.7 / 2.4 s, clamped to 0.6–2×). Read frame
by frame off the donor (`boards/blow_check.jpg`):

1. **102 Sword Judgment**, the ultimate of 46 blade families: the blade lands
   at f36–38 of 131 (**0.28**). The game fires at 0.62, **about 0.8 s after
   the slam**, while the figure is already rising from its knee.
2. **128 Heavy Hammer Swing**, the heavy of 16 heavy families: the hammer lands
   at f44–45 of 55 (**0.80**). The game fires at 0.55, **about 0.45 s early,
   with the hammer still overhead**. The clip also ends bent double with no
   recovery, so the figure snaps back to its stance in the 0.16 s fade.
3. **226 Archery Shot 2**, the heavy of all 6 archers: a **static aim that
   never looses** (the hands hold 0.82 m apart and the string hand 21 cm from
   the head for all 3.8 s). The heavy attack shows no shot.
4. **224 / 222**, the archers' basic and ultimate: 5.0 s and 7.9 s, over the
   2× clamp. The arrow leaves at 0.78 and 0.87 of the clip, **about 1.4 s and
   1.9 s after the damage lands**.

The palette fixes all four with no Swift change. `prepare()` trims each preset
to its window and warps its time piecewise-linearly so the blow lands at the
slot's default fraction (the halves' speeds held within 0.5–2×). 128 gets a
synthesized 20-frame recovery to its first pose. 226 is reclassed as an
archer's stance.

## 6. The pilot (2026-09-23): what was built and what it showed

**Bought** on `shield_maiden_serious` (rig of 2026-09-23 21:12, a
human-proportioned serious family with a sword in the right hand): 15 presets,
**45 credits, balance 594 → 549**. **Re-fetched free** from live families'
own clip tasks: 16 more (every preset the roster already uses, plus hit, death
and walk). 240 Thrust Slash could not be recovered because its only task, from
09-19, has expired.

| id | preset | kind | how bought | length | cut (frames at 30 fps) | blow | what it is |
|---|---|---|---|---|---|---|---|
| 86 | Jump Attack | blade | bought on shield_maiden_serious | 5.933 s | 24–120 | f76 | a gather, a leap, the landing strike |
| 91 | Double Blade Spin | blade | bought on shield_maiden_serious | 5.7 s | 0–84 | f46 | a spinning cut into a low finish |
| 97 | Left Slash | blade | bought on shield_maiden_serious | 3.2 s | 0–66 | f21 | a wide backhand across the body |
| 102 | Sword Judgment | blade | free from shield_maiden_serious | 4.4 s | whole | f38 | a leap and a slam to one knee |
| 105 | Triple Combo Attack | blade | bought on shield_maiden_serious | 4.367 s | 0–100 | f74 | three cuts, the last the heaviest |
| 219 | Right-hand Sword Slash | blade | free from shield_maiden_serious | 1.533 s | whole | f15 | one clean forehand cut |
| 221 | Charged Upward Slash | blade | bought on shield_maiden_serious | 3.233 s | 0–66 | f31 | a crouch and a rising cut |
| 242 | Charged Slash | blade | free from shield_maiden_serious | 2.267 s | whole | f36 | a wind-up and a two-handed cut |
| 127 | Charged Ground Slam | heavy | free from boss_colossus_serious | 3.033 s | whole | f50 | overhead, slammed to the floor |
| 128 | Heavy Hammer Swing | heavy | free from boss_colossus_serious | 1.867 s | whole, +20 recovery | f45 | overhead and down; ends bent double, so a recovery is added |
| 237 | Charged Axe Chop | heavy | bought on shield_maiden_serious | 7.7 s | 96–176 | f132 | rises from the kneel, one chop |
| 238 | Axe Spin Attack | heavy | bought on shield_maiden_serious | 2.533 s | whole | f27 | a turning swing |
| 206 | Spartan Kick | unarmed | bought on shield_maiden_serious | 1.467 s | whole | f16 | a front push-kick |
| 220 | Shield Push Left | off hand | bought on shield_maiden_serious | 2.433 s | 4–62 | f32 | the off hand shoved forward |
| 125 | Charged Spell Cast | cast | free from hera_awakened_serious | 2.7 s | whole | f57 | arms up, a crouch, up again |
| 126 | Charged Spell Cast 1 | cast | free from hera_awakened_serious | 4.333 s | whole | f74 | the long gather and release |
| 129 | Mage Spell Cast | cast | free from hera_awakened_serious | 2.3 s | whole | f29 | one arm raised, thrown forward |
| 130 | Mage Spell Cast 1 | cast | bought on shield_maiden_serious | 3.567 s | 0–80 | f41 | both arms flung wide |
| 133 | Mage Spell Cast 4 | cast | bought on shield_maiden_serious | 2.267 s | whole | f29 | overhead, then a lunging thrust |
| 136 | Mage Spell Cast 7 | cast | bought on shield_maiden_serious | 2.733 s | 0–64 | f35 | a two-handed push |
| 222 | Draw and Shoot from Back | archery | free from ullr_serious | 7.867 s | 110–230 | f205 | the long draw and the loose at f205 (of 236) |
| 224 | Archery Shot | archery | free from ullr_serious | 5.033 s | 50–140 | f117 | an arrow from the quiver, a full draw, the loose at f117 |
| 226 | Archery Shot 2 | archery | free from ullr_serious | 3.8 s | whole, looped | – | a STATIC aim at full draw, never loosed (hands fixed 3.8 s) - a stance, not a shot |
| 85 | Axe Stance | stance | bought on shield_maiden_serious | 6.133 s | 140–183, looped | – | its calm tail (after the kneel and the raise), closed into a loop |
| 89 | Combat Idle | stance | free from shield_maiden_serious | 1.7 s | whole, looped | – | the crouched guard |
| 88 | Chest Pound Taunt | victory | bought on shield_maiden_serious | 4.867 s | 0–116 | – | fists to the chest, a roar |
| 298 | Cheer with Both Hands Up | victory | bought on shield_maiden_serious | 1.933 s | whole | – | a hop with both arms up |
| 412 | Victory | victory | free from shield_maiden_serious | 8.6 s | 40–158 | – | arms spread, then raised again and again |
| 178 | Hit Reaction | hit | free from shield_maiden_serious | 1.667 s | whole | – |  |
| 8 | Dead | death | free from shield_maiden_serious | 3.0 s | whole | – |  |
| 30 | Casual Walk | walk | free from shield_maiden_serious | 4.233 s | whole | – |  |

Each preset was boarded on the donor at eight frames (`motion_palette.py
board-archive`), and its cut is read off that board (`PRESET_CUTS` in the
tool). Meshy authors most presets with a long lead-in or settle. Charged Axe
Chop kneels with its weapon through the floor for three seconds before it
rises. Axe Stance is a kneel-to-stance transition, not a loop. Double Blade
Spin and Jump Attack end in four-second crouches. So the cut is not optional.

### The six pilot families (scratch bundle only; nothing under `Pantheon/`)

`motion_palette.py ship <asset> <family> <clip>=<preset> … --bundle <scratch> --with-base`,
then `board`. Every file passed `mesh.py`'s verification (bind pose, joint
list, grounding). Every clip plays inside the 0.6–2× clamp, with its blow
within 0.04 of the game's default fraction.

| family | kind | basic | heavy | ultimate | stance | victory |
|---|---|---|---|---|---|---|
| Minotaur | heavy (hand axe) | 128 Heavy Hammer Swing (+recovery) | 237 Charged Axe Chop | 127 Charged Ground Slam | 85 Axe Stance (looped tail) | 88 Chest Pound Taunt |
| Centurion | blade + stick | 220 Shield Push Left (a shove with the vine stick) | 242 Charged Slash | 105 Triple Combo Attack | 89 | 412 Victory |
| Hoplite | blade, Greek | 206 Spartan Kick | 221 Charged Upward Slash | 102 Sword Judgment | 89 | 298 Cheer |
| Bastet | unarmed (empty hands) | 97 Left Slash (reads as a claw swipe) | 238 Axe Spin Attack (a spinning kick) | 86 Jump Attack (a pounce, feet 2.29 m up) | 89 | 298 Cheer |
| Hathor | robed caster | 136 Spell Cast 7 (push) | 133 Spell Cast 4 (lunge) | 125 Charged Spell Cast | the guard stood up | 412 Victory |
| Artemis | archer | 224 cut short (70–135) | 224 (50–140) | 222 (110–230) | 89 | 298 Cheer |

### The verdict

**The retarget reads.** Feet stay on the floor in every frame of every clip,
except where a clip means them to leave it: Bastet's pounce, and the weapon
driven into the floor in the ground slam. No wrist or elbow breaks. The weapon
hand swings the weapon: the Minotaur's axe, the Centurion's gladius, the
Hoplite's sword. The Centurion's stick-hand shove and the Hoplite's kick read
at a glance. **Artemis's draw works**: bow arm out, string hand at the cheek,
a quiver reach in 224 and a draw from the back in 222. And the palette's 127
on the Minotaur reproduces his shipped 127 frame for frame. Distinctness is
the point, and the pilot sheet shows six bodies fighting six different ways.

**What the pilot cannot fix, because it is in the rigs rather than the motion
(all four present in the shipped game today, checked on the shipped files):**

1. **Hathor's dress is welded to her hands.** Every arm movement drags it into
   wings, in the shipped 125/126 as much as in the pilot's clips. This is the
   robe problem PLAN.md already names (*The robe ring's verdict*). For robed
   casters the pools prefer the close-handed casts (136, 133), which helps
   but does not cure it. The cure is a remake.
2. **The Hoplite's tunic panels** are skinned to his hands and rise with his
   arms in the cheer and Sword Judgment (the skirt pass; he is not in
   `SKIRT_FAMILIES`). The Centurion's mail sleeve does the same.
3. **The Minotaur's axe** stretches a strand to his belt whenever his right
   arm rises. He is not in `WEAPON_FAMILIES`, and he should be judged for it
   (`tools/weapon_pass.py`).
4. Bigger motions make these faults more visible. The owner will see more of
   them once families stop standing in the same guard.

**Two things to judge on the phone, not here.** Jump Attack's 2.3 m leap may
leave the top of the battle frame (the hips' lift can be scaled in `prepare`
if so). The half-guard stance (below) should read as a different pose from
89 at battle distance.

## 7. The Swift side: no code change

- A figure's clip is the file `<assetName>_<clip>.usdz`
  (`ModelLibrary.animation(_:for:)`, layout A). The asset whose clips play is
  `ModelLibrary.clipAsset(for:awakened:)`, the family's own. So a retargeted
  file per family drops in under the same name and nothing in Swift changes.
  `UnitNode.restingIdle` prefers `<asset>_idle.usdz`, which `ship idle=stand`
  derives.
- **`contactFraction` needs no new row.** `prepare()` puts every palette
  clip's blow at the slot's default (0.42 / 0.55 / 0.62), and `UnitNode.play`
  retimes a one-shot to its contract inside the 0.6–2× clamp (every cut is
  inside it; `ship` warns when not). `castRelease` plays the heavy clip and
  reads the heavy row. The five gods' rows (anubis, sekhmet, zeus, ares,
  thoth) stay because their bespoke clips stay. **If a god's attack clips
  are ever replaced from the palette, its row must be deleted**, or its old
  fractions will apply to the new clips.
- `ModelSpec.melee` decides dash-or-projectile. The pools keep ranged families
  (casters, archers) on casts and shots, because a ranged caster's projectile
  is launched to land at the contact frame.
- Only the battle stance (`idle_combat`) loops. `stand` and `half` are the
  guard stood fully and 70% of the way up by `stand_idle.py`, shipped as
  `idle_combat`.

## 8. The roll-out, in order

1. **Judge this pilot**: `boards/SHEET_pilot.jpg`, `boards/SHEET_palette.jpg`,
   and the per-family boards. They are in the session scratchpad; regenerate
   with `motion_palette.py board`.
2. **Decide the expansion** (needs the owner's word: the balance is 549 and
   the floor is 500). The recommended 36 presets, 108 credits, bought on any
   rig under four days old (`shield_maiden_serious` lives until about
   2026-09-27):
   - archery 225, 227, 223, 229, 236: 15 credits. Today all six archers
     share one triple.
   - blade and unarmed 240 (re-buy; its archive expired), 199, 202, 241,
     92, 90, 4, 99, 239, 212, 214, 216: 36 credits.
   - casts 131, 132, 134, 135, 137: 15 credits (the robed pool has 12 triples
     for 19 families).
   - stances 377, 335, 336, 87, 2, 0: 18 credits.
   - victories and idles 59, 403, 49, 41, 255, 306, 11, 12: 24 credits.

   Then `python3 tools/motion_palette.py buy shield_maiden_serious <ids> --floor <floor> --cap <n>`,
   then `archive`, then `board-archive <ids>`. Write each new preset's cut
   into `PRESET_CUTS` and add it to `POOLS`.
3. **Deal the roster**: `python3 tools/motion_palette.py plan --markdown` (the
   table below, from the 31 motions archived today). Adjust `POOLS`, and
   `BRUTES` or an override, where a family's character asks for a move.
4. **Ship family by family**, on the owner's word:
   `python3 tools/motion_palette.py ship <asset>_serious <family> attack_basic=… attack_heavy=… ultimate=… idle_combat=… victory=… idle=stand --bundle Pantheon/Resources/Models --real`
   (clips only; about 25 s a family; 113 families take about 50 minutes at
   two at a time; each family's cut report goes to `Art/Motions/shipped/<family>.json`,
   never into the app bundle). An awakened form takes its family's set onto its own rig.
   Then board each family, run `swiftcheck` and `balance.py` (no numbers
   change), push, and read the CI frames before the next batch.
5. **Option B** (247 credits, on the owner's word): one sentence per 5★
   ultimate. `meshy.py motion` on the donor, archived, then retargeted onto
   the base and the awakened rig, with its blow read on the board and cut
   into `PRESET_CUTS`-style windows.

## 9. The assignment (first deal, from the 31 archived motions)

`python3 tools/motion_palette.py plan --markdown`. The 5-stars are dealt first,
and no two families share a five-clip set (0 identical among 98 base
families). Within a kind no two share more than one attack, except the
archers (one triple until step 2's purchase) and the robed casters (12
triples for 19 until step 2). `own:<god>` is the god's bespoke motion. An
awakened form wears its family's set. `stand` and `half` are the guard stood
fully or 70% up. The pilot's hand-picked sets differ from this deal where
character called for it (the Minotaur's chest pound). Treat this as the
starting point to judge on boards, not the answer.

| family | grade | kind | basic | heavy | ultimate | stance | victory |
|---|---|---|---|---|---|---|---|
| ares | 5★ | blade | own:ares | own:ares | own:ares | 89 | 412 |
| ares_awakened | 5★ | blade | own:ares | own:ares | own:ares | 89 | 412 |
| horus | 5★ | blade | 219 | 242 | 102 | half | 298 |
| horus_awakened | 5★ | blade | 219 | 242 | 102 | half | 298 |
| loki | 5★ | blade | 97 | 221 | 105 | stand | 88 |
| mars | 5★ | blade | 220 | 238 | 91 | 89 | 412 |
| mars_awakened | 5★ | blade | 220 | 238 | 91 | 89 | 412 |
| sekhmet | 5★ | blade | own:sekhmet | own:sekhmet | own:sekhmet | half | 298 |
| sekhmet_awakened | 5★ | blade | own:sekhmet | own:sekhmet | own:sekhmet | half | 298 |
| surtr | 5★ | blade | 206 | 105 | 86 | stand | 88 |
| baldr | 5★ | caster | 129 | 130 | 126 | stand | 412 |
| boss_unwrapped_king | 5★ | caster | 136 | 125 | 130 | half | 298 |
| hades | 5★ | caster | 133 | 136 | 125 | stand | 412 |
| hades_awakened | 5★ | caster | 133 | 136 | 125 | stand | 412 |
| minerva | 5★ | caster | 129 | 133 | 125 | half | 298 |
| odin | 5★ | caster | 136 | 133 | 126 | stand | 298 |
| odin_awakened | 5★ | caster | 136 | 133 | 126 | stand | 298 |
| ra | 5★ | caster | 133 | 125 | 126 | half | 412 |
| ra_awakened | 5★ | caster | 133 | 125 | 126 | half | 412 |
| boss_colossus | 5★ | heavy | 128 | 237 | 127 | 85 | 88 |
| thor | 5★ | heavy | 219 | 128 | 238 | 89 | 412 |
| thor_awakened | 5★ | heavy | 219 | 128 | 238 | 89 | 412 |
| athena | 5★ | polearm | 219 | 221 | 105 | 89 | 412 |
| athena_awakened | 5★ | polearm | 219 | 221 | 105 | 89 | 412 |
| poseidon | 5★ | polearm | 97 | 242 | 102 | half | 298 |
| poseidon_awakened | 5★ | polearm | 97 | 242 | 102 | half | 298 |
| sun_wukong | 5★ | polearm | 220 | 238 | 91 | stand | 88 |
| freya | 5★ | robed | 136 | 133 | 126 | stand | 412 |
| freya_awakened | 5★ | robed | 136 | 133 | 126 | stand | 412 |
| frigg | 5★ | robed | 129 | 136 | 125 | stand | 298 |
| hera | 5★ | robed | 133 | 125 | 126 | stand | 412 |
| hera_awakened | 5★ | robed | 133 | 125 | 126 | stand | 412 |
| isis | 5★ | robed | 136 | 133 | 125 | stand | 298 |
| isis_awakened | 5★ | robed | 136 | 133 | 125 | stand | 298 |
| osiris | 5★ | robed | 129 | 136 | 126 | stand | 412 |
| osiris_awakened | 5★ | robed | 129 | 136 | 126 | stand | 412 |
| thoth | 5★ | robed | own:thoth | own:thoth | own:thoth | stand | 298 |
| thoth_awakened | 5★ | robed | own:thoth | own:thoth | own:thoth | stand | 298 |
| artemis | 4★ | archer | 224 | 224 | 222 | 89 | 298 |
| diana | 4★ | archer | 224 | 224 | 222 | 226 | 412 |
| skadi | 4★ | archer | 224 | 224 | 222 | half | 298 |
| ullr | 4★ | archer | 224 | 224 | 222 | 89 | 412 |
| achilles | 4★ | blade | 219 | 221 | 91 | 89 | 412 |
| anhur | 4★ | blade | 97 | 238 | 102 | half | 298 |
| anubis | 4★ | blade | own:anubis | own:anubis | own:anubis | stand | 88 |
| heimdall | 4★ | blade | 220 | 242 | 105 | 89 | 412 |
| mercury | 4★ | blade | 97 | 242 | 86 | half | 298 |
| nike | 4★ | blade | 206 | 221 | 102 | stand | 88 |
| njord | 4★ | blade | 219 | 238 | 105 | 89 | 412 |
| perseus | 4★ | blade | 220 | 105 | 102 | half | 298 |
| set | 4★ | blade | 206 | 242 | 91 | stand | 88 |
| sif | 4★ | blade | 97 | 105 | 91 | 89 | 412 |
| apollo | 4★ | caster | 129 | 136 | 130 | stand | 412 |
| bragi | 4★ | caster | 136 | 130 | 125 | half | 298 |
| demeter | 4★ | caster | 133 | 125 | 130 | stand | 412 |
| dionysus | 4★ | caster | 129 | 130 | 125 | half | 298 |
| hermes | 4★ | caster | 136 | 133 | 130 | stand | 412 |
| bellona | 4★ | heavy | 97 | 221 | 102 | half | 298 |
| guan_yu | 4★ | heavy | 128 | 242 | 238 | 85 | 88 |
| hephaestus | 4★ | heavy | 219 | 237 | 102 | 89 | 412 |
| heracles | 4★ | heavy | 97 | 128 | 127 | half | 298 |
| khnum | 4★ | heavy | 219 | 242 | 127 | 85 | 88 |
| neptune | 4★ | polearm | 219 | 242 | 86 | 89 | 412 |
| nezha | 4★ | polearm | 97 | 221 | 91 | half | 298 |
| sobek | 4★ | polearm | 219 | 238 | 102 | stand | 88 |
| taweret | 4★ | polearm | 220 | 242 | 105 | 89 | 88 |
| vidar | 4★ | polearm | 220 | 221 | 86 | half | 412 |
| aphrodite | 4★ | robed | 133 | 136 | 125 | stand | 298 |
| chang_e | 4★ | robed | 136 | 125 | 126 | stand | 412 |
| hathor | 4★ | robed | 129 | 133 | 125 | stand | 412 |
| hel | 4★ | robed | 129 | 125 | 126 | stand | 298 |
| idunn | 4★ | robed | 133 | 136 | 126 | stand | 412 |
| maat | 4★ | robed | 129 | 133 | 126 | stand | 298 |
| nephthys | 4★ | robed | 136 | 133 | 125 | stand | 412 |
| nuwa | 4★ | robed | 133 | 125 | 126 | stand | 298 |
| pluto | 4★ | robed | 129 | 136 | 125 | stand | 412 |
| ptah | 4★ | robed | 136 | 125 | 126 | stand | 298 |
| bastet | 4★ | unarmed | 97 | 238 | 86 | 89 | 298 |
| fenrir | 4★ | unarmed | 206 | 221 | 91 | half | 88 |
| serqet | 4★ | unarmed | 219 | 242 | 105 | 89 | 412 |
| tyr | 4★ | unarmed | 97 | 221 | 105 | half | 298 |
| atalanta | 3★ | archer | 224 | 224 | 222 | 226 | 298 |
| medjay | 3★ | archer | 224 | 224 | 222 | half | 412 |
| bes | 3★ | blade | 220 | 221 | 86 | half | 298 |
| centurion | 3★ | blade | 219 | 238 | 86 | stand | 88 |
| dark_elf | 3★ | blade | 206 | 242 | 105 | 89 | 412 |
| harpy | 3★ | blade | 219 | 105 | 102 | half | 298 |
| hoplite | 3★ | blade | 97 | 221 | 91 | stand | 88 |
| jackal_warrior | 3★ | blade | 220 | 238 | 105 | 89 | 412 |
| shield_maiden | 3★ | blade | 219 | 105 | 86 | half | 298 |
| light_elf | 3★ | caster | 133 | 136 | 126 | half | 298 |
| medusa | 3★ | caster | 129 | 125 | 126 | stand | 412 |
| nymph | 3★ | caster | 133 | 130 | 125 | half | 298 |
| satyr | 3★ | caster | 129 | 133 | 130 | stand | 412 |
| siren | 3★ | caster | 136 | 130 | 126 | half | 298 |
| amazon | 3★ | heavy | 97 | 237 | 238 | 89 | 412 |
| berserker | 3★ | heavy | 128 | 221 | 102 | half | 298 |
| cyclops | 3★ | heavy | 128 | 242 | 127 | 85 | 88 |
| draugr | 3★ | heavy | 219 | 128 | 102 | 89 | 412 |
| dwarf_smith | 3★ | heavy | 97 | 221 | 238 | half | 298 |
| einherjar | 3★ | heavy | 128 | 237 | 238 | 85 | 88 |
| frost_troll | 3★ | heavy | 219 | 128 | 127 | 89 | 412 |
| minotaur | 3★ | heavy | 128 | 242 | 102 | half | 298 |
| scarab_knight | 3★ | heavy | 97 | 221 | 127 | 85 | 88 |
| terracotta_soldier | 3★ | polearm | 97 | 238 | 105 | stand | 298 |
| valkyrie | 3★ | polearm | 219 | 221 | 102 | 89 | 412 |
| cobra_priestess | 3★ | robed | 129 | 133 | 125 | stand | 298 |
| fox_spirit | 3★ | robed | 133 | 136 | 126 | stand | 298 |
| vestal | 3★ | robed | 129 | 133 | 126 | stand | 412 |
| gladiator | 3★ | unarmed | 206 | 242 | 86 | 89 | 88 |
| jiangshi | 3★ | unarmed | 219 | 238 | 91 | half | 412 |
| mummy | 3★ | unarmed | 97 | 242 | 91 | 89 | 298 |
| shabti | 3★ | unarmed | 206 | 238 | 105 | half | 88 |
