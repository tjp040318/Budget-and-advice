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
share one pose as well (until 2026-09-25: §11).

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
  inside it; `ship` warns when not). `castRelease` plays the heavy clip; a
  god reads its heavy row for it, every other family the default 0.60, about
  0.08 s after the heavy's blow at 0.55 on the 1.7 s contract (older than the
  palette; the roll-out of §10 kept to it and changed no Swift). The five gods' rows (anubis, sekhmet, zeus, ares,
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
3. **Deal the roster** (done 2026-09-24, §10): `python3 tools/motion_palette.py plan --markdown` (the
   table below, from the 31 motions archived today). Adjust `POOLS`, and
   `BRUTES` or an override, where a family's character asks for a move.
4. **Ship family by family** (done 2026-09-24 with `roll`, §10), on the owner's word:
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

## 9. The assignment (as shipped, 2026-09-24)

`python3 tools/motion_palette.py plan --markdown` prints this table: the deal
(the 5-stars first, the pools, `JUMPERS`, `OVERRIDES`), then the board
judgments of §10 (`JUDGED`, `KEPT`) laid over it. `hand` is the hand the
family holds its weapon (an archer: its bow) in, `-` for none or one in each;
`mirrored` names the clips reflected to it. `own:<god>` is the god's bespoke
motion, untouched. `stand` and `half` are the guard stood fully or 70% up;
`natural` is the family's natural idle worn as its stance (§11, since
2026-09-25: the 35 sovereigns, graces and mystics the deal stood up). An
unmirrored clip on a left-handed family (`242`, `102` on Loki, Surtr,
Achilles and the Dark Elf) is a judgment of §10, not an omission. No two
families share their five clips; the robed casters, the archers and four
left-handed blades share attack triples (§10, what is left).

| family | grade | kind | hand | basic | heavy | ultimate | stance | victory | mirrored |
|---|---|---|---|---|---|---|---|---|---|
| ares | 5★ | blade | R | own:ares | own:ares | own:ares | 89 | 412 |  |
| ares_awakened | 5★ | blade | R | own:ares | own:ares | own:ares | 89 | 412 |  |
| horus | 5★ | blade | - | 219 | 242 | 102 | half | 412 |  |
| horus_awakened | 5★ | blade | R | 219 | 242 | 102 | half | 412 |  |
| loki | 5★ | blade | L | 220 | 242 | 102 | 89 | 88 | basic |
| mars | 5★ | blade | R | 220 | 238 | 91 | 89 | 412 |  |
| mars_awakened | 5★ | blade | R | 220 | 238 | 91 | 89 | 412 |  |
| sekhmet | 5★ | blade | R | own:sekhmet | own:sekhmet | own:sekhmet | half | 298 |  |
| sekhmet_awakened | 5★ | blade | R | own:sekhmet | own:sekhmet | own:sekhmet | half | 298 |  |
| surtr | 5★ | blade | L | 220 | 242 | 102 | stand | 88 | basic |
| baldr | 5★ | caster | R | 129 | 130 | 126 | natural | 412 |  |
| boss_unwrapped_king | 5★ | caster | R | 136 | 125 | 130 | half | 298 |  |
| hades | 5★ | caster | R | 133 | 136 | 125 | natural | 412 |  |
| hades_awakened | 5★ | caster | R | 133 | 136 | 125 | natural | 412 |  |
| minerva | 5★ | caster | - | 129 | 133 | 125 | half | 298 |  |
| odin | 5★ | caster | R | 136 | 133 | 126 | natural | 88 |  |
| odin_awakened | 5★ | caster | R | 136 | 133 | 126 | natural | 88 |  |
| ra | 5★ | caster | R | 133 | 125 | 126 | half | 412 |  |
| ra_awakened | 5★ | caster | R | 133 | 125 | 126 | half | 412 |  |
| zeus | 5★ | caster | R | own:zeus | own:zeus | own:zeus | natural | 412 |  |
| zeus_awakened | 5★ | caster | R | own:zeus | own:zeus | own:zeus | natural | 412 |  |
| boss_colossus | 5★ | heavy | - | 128 | 237 | 127 | 85 | 88 |  |
| thor | 5★ | heavy | R | 219 | 128 | 238 | 89 | 412 |  |
| thor_awakened | 5★ | heavy | R | 219 | 128 | 238 | 89 | 412 |  |
| athena | 5★ | polearm | R | 219 | 242 | 105 | natural | 412 |  |
| athena_awakened | 5★ | polearm | R | 219 | 242 | 105 | natural | 412 |  |
| poseidon | 5★ | polearm | R | 97 | 242 | 102 | half | 298 |  |
| poseidon_awakened | 5★ | polearm | R | 97 | 242 | 102 | half | 298 |  |
| sun_wukong | 5★ | polearm | - | 220 | 238 | 86 | stand | 412 |  |
| freya | 5★ | robed | R | 136 | 133 | 126 | natural | 412 |  |
| freya_awakened | 5★ | robed | R | 136 | 133 | 126 | natural | 412 |  |
| frigg | 5★ | robed | R | 129 | 136 | 126 | natural | 298 |  |
| hera | 5★ | robed | R | 133 | 125 | 126 | natural | 412 |  |
| hera_awakened | 5★ | robed | R | 133 | 125 | 126 | natural | 412 |  |
| isis | 5★ | robed | R | 136 | 133 | 126 | natural | 298 |  |
| isis_awakened | 5★ | robed | R | 136 | 133 | 126 | natural | 298 |  |
| osiris | 5★ | robed | R | 129 | 136 | 126 | natural | 412 |  |
| osiris_awakened | 5★ | robed | R | 129 | 136 | 126 | natural | 412 |  |
| thoth | 5★ | robed | R | own:thoth | own:thoth | own:thoth | natural | 298 |  |
| thoth_awakened | 5★ | robed | R | own:thoth | own:thoth | own:thoth | natural | 298 |  |
| artemis | 4★ | archer | L | 224 | 224 | 222 | 89 | 298 |  |
| diana | 4★ | archer | - | 224 | 224 | 222 | stand | 412 |  |
| skadi | 4★ | archer | R | 224 | 224 | 222 | 226 | 412 | basic, heavy, ult, stance |
| ullr | 4★ | archer | L | 224 | 224 | 222 | half | 412 |  |
| achilles | 4★ | blade | L | 219 | 242 | 102 | 89 | 412 | basic |
| anhur | 4★ | blade | R | 97 | 242 | 91 | half | 298 |  |
| anubis | 4★ | blade | R | own:anubis | own:anubis | own:anubis | natural | 88 |  |
| heimdall | 4★ | blade | R | 206 | 238 | 105 | 89 | 412 |  |
| mercury | 4★ | blade | L | 220 | 105 | 86 | half | 298 | basic, heavy, ult |
| nike | 4★ | blade | R | 97 | 238 | 102 | stand | 88 |  |
| njord | 4★ | blade | L | 220 | 242 | 105 | 89 | 412 | basic, heavy, ult |
| perseus | 4★ | blade | R | 219 | 105 | 91 | half | 298 |  |
| set | 4★ | blade | R | 206 | 221 | 91 | stand | 88 |  |
| sif | 4★ | blade | R | 220 | 221 | 102 | 89 | 412 |  |
| apollo | 4★ | caster | R | 129 | 136 | 130 | half | 298 |  |
| bragi | 4★ | caster | R | 136 | 130 | 126 | natural | 88 |  |
| demeter | 4★ | caster | R | 133 | 125 | 130 | half | 412 |  |
| dionysus | 4★ | caster | R | 129 | 130 | 125 | stand | 412 |  |
| hermes | 4★ | caster | R | 136 | 133 | 130 | half | 298 |  |
| bellona | 4★ | heavy | L | 219 | 221 | 102 | half | 88 | heavy, ult |
| guan_yu | 4★ | heavy | R | 128 | 242 | 238 | 85 | 88 |  |
| hephaestus | 4★ | heavy | R | 97 | 128 | 127 | 85 | 412 |  |
| heracles | 4★ | heavy | R | 219 | 237 | 102 | 89 | 298 |  |
| khnum | 4★ | heavy | R | 219 | 242 | 127 | half | 88 |  |
| neptune | 4★ | polearm | R | 219 | 242 | 91 | 89 | 412 |  |
| nezha | 4★ | polearm | L | 97 | 221 | 91 | half | 298 | basic, heavy |
| sobek | 4★ | polearm | R | 219 | 238 | 102 | stand | 88 |  |
| taweret | 4★ | polearm | R | 220 | 242 | 105 | 89 | 88 |  |
| vidar | 4★ | polearm | R | 97 | 238 | 105 | half | 412 |  |
| aphrodite | 4★ | robed | R | 133 | 136 | 126 | natural | 298 |  |
| chang_e | 4★ | robed | R | 136 | 125 | 126 | natural | 412 |  |
| hathor | 4★ | robed | R | 129 | 133 | 126 | natural | 88 |  |
| hel | 4★ | robed | - | 129 | 125 | 126 | natural | 298 |  |
| idunn | 4★ | robed | - | 129 | 136 | 126 | half | 412 |  |
| maat | 4★ | robed | R | 129 | 133 | 126 | natural | 298 |  |
| nephthys | 4★ | robed | - | 136 | 133 | 125 | natural | 412 |  |
| nuwa | 4★ | robed | R | 133 | 125 | 126 | natural | 298 |  |
| pluto | 4★ | robed | R | 129 | 136 | 126 | natural | 88 |  |
| ptah | 4★ | robed | R | 136 | 125 | 126 | natural | 298 |  |
| bastet | 4★ | unarmed | - | 97 | 238 | 86 | 89 | 298 |  |
| fenrir | 4★ | unarmed | - | 206 | 221 | 91 | half | 88 |  |
| serqet | 4★ | unarmed | - | 219 | 242 | 105 | 89 | 412 |  |
| tyr | 4★ | unarmed | R | 97 | 221 | 105 | half | 298 |  |
| atalanta | 3★ | archer | L | 224 | 224 | 222 | 89 | 412 |  |
| medjay | 3★ | archer | L | 224 | 224 | 222 | half | 298 |  |
| bes | 3★ | blade | R | 219 | 242 | 105 | half | 88 |  |
| centurion | 3★ | blade | L | 97 | 238 | 105 | stand | 88 | basic, heavy, ult |
| dark_elf | 3★ | blade | L | 220 | 242 | 102 | 89 | 412 | basic |
| harpy | 3★ | blade | L | 220 | 242 | 102 | half | 88 | basic, heavy |
| hoplite | 3★ | blade | - | 219 | 221 | 102 | stand | 88 |  |
| jackal_warrior | 3★ | blade | R | 97 | 105 | 102 | 89 | 412 |  |
| shield_maiden | 3★ | blade | R | 220 | 238 | 86 | half | 298 |  |
| light_elf | 3★ | caster | R | 133 | 136 | 126 | half | 412 |  |
| medusa | 3★ | caster | - | 136 | 130 | 126 | natural | 412 |  |
| nymph | 3★ | caster | R | 129 | 125 | 130 | natural | 412 |  |
| satyr | 3★ | caster | R | 133 | 130 | 125 | half | 298 |  |
| siren | 3★ | caster | R | 129 | 133 | 126 | natural | 412 |  |
| amazon | 3★ | heavy | L | 97 | 237 | 238 | 89 | 412 | basic, heavy, ult |
| berserker | 3★ | heavy | - | 128 | 221 | 102 | half | 298 |  |
| cyclops | 3★ | heavy | R | 128 | 242 | 127 | 85 | 88 |  |
| draugr | 3★ | heavy | R | 219 | 128 | 102 | 89 | 412 |  |
| dwarf_smith | 3★ | heavy | R | 97 | 221 | 238 | half | 88 |  |
| einherjar | 3★ | heavy | R | 128 | 237 | 238 | 85 | 88 |  |
| frost_troll | 3★ | heavy | - | 219 | 128 | 127 | 89 | 412 |  |
| minotaur | 3★ | heavy | R | 128 | 242 | 102 | half | 298 |  |
| scarab_knight | 3★ | heavy | R | 97 | 221 | 127 | 85 | 88 |  |
| terracotta_soldier | 3★ | polearm | R | 220 | 221 | 102 | stand | 298 |  |
| valkyrie | 3★ | polearm | R | 219 | 221 | 86 | 89 | 298 |  |
| cobra_priestess | 3★ | robed | R | 129 | 133 | 126 | half | 88 |  |
| fox_spirit | 3★ | robed | R | 129 | 136 | 126 | half | 298 |  |
| vestal | 3★ | robed | R | 129 | 125 | 126 | natural | 412 |  |
| gladiator | 3★ | unarmed | R | 206 | 242 | 86 | 89 | 88 |  |
| jiangshi | 3★ | unarmed | - | 219 | 238 | 102 | half | 412 |  |
| mummy | 3★ | unarmed | - | 97 | 242 | 91 | 89 | 412 |  |
| shabti | 3★ | unarmed | R | 206 | 238 | 105 | half | 88 |  |

## 10. As rolled out (2026-09-24)

On the owner's word ("go ahead with the motion roll-out"); no credits spent
(balance 549 before and after; the 108-credit expansion was not bought).

### What shipped

**115 families**, each its own five clips and a standing idle: the 98 base
families of the serious wave, **Zeus** (the serious Zeus shipped as the test
before `serious_wave.txt` existed; `EXTRA_ROWS`), and the **16 awakened
forms**, which wear their family's set on their own rigs. The five gods keep
their bespoke attack clips untouched (so `contactFraction` keeps their rows);
they were dealt a stance and a victory only. Every carrier the roll-out wrote
(663: five clips and the standing idle, the gods' three attacks aside) binds
exactly as its family's shipped base does, and every standing idle is newer
than the stance it came from. The cut report of every family is in
`Art/Motions/shipped/<family>.json` (preset, window, blow, rate, mirror,
fixes). **Left on their old clips:** the Jötunn and the sandstone sentinel,
which are not in the serious roster (chibi-era rigs through the proportion
pass; the deal has no row for them), and the smith's basic (below).

`python3 tools/motion_palette.py roll --bundle Pantheon/Resources/Models --real --jobs 2`
ships the whole plan (about 17 s a family; 115 in about 18 minutes);
`roll <families>` ships a few and `--skip-done` resumes. Two faults of the
first run are guarded against now: the rig was canonicalised at `mesh.py`'s
1.9 m default instead of the height the family shipped at (the wave's third
field), which put 90 families' carriers 3-7% short of their bases — `plan`
carries the shipped height and `ship` refuses any carrier whose bind is more
than 1 mm off the shipped base's — and a full disk failed 26 families in
`mkdtemp` (re-shipped).

### Which hand swings

The presets carry their weapon in one hand, and so do the families.
`PRESET_SIDE` is measured on the donor in the chest's frame (the hand whose
path and reach lead into the blow): the blade and heavy presets are
right-handed, the Shield Push shoves with the LEFT (its weapon hand is the
right), the archery presets hold the bow in the left. **128, the Heavy Hammer
Swing, is not lateral** — both hands go overhead, and on the boards the
Minotaur's axe and Thor's hammer go up and down UNmirrored and read worse
mirrored. `WEAPON_HAND` is measured on each shipped base: the mass the
forearm and hand own outside the arm's own layer, its elongation and reach,
every uncertain family looked at on a front render. Fifteen hold theirs in the
LEFT: Achilles, the Amazon, Bellona (sword; the whip is in the right), the
Centurion (the vine stick), the Dark Elf, the Harpy, Loki, Mercury (the
caduceus), Nezha, Njord, Surtr, and the archers Artemis, Atalanta, the Medjay
and Ullr (bow in the left, as the presets'); Skadi's bow is in her RIGHT.
Diana (her bow is slung), the Berserker, the Frost Troll, Serqet (a weapon in
each hand) and the empty-handed hold no side.

A clip whose preset swings the other hand from the family's weapon is
**mirrored on the donor before the retarget** (`mirror_motion`: clip_fix's
"delta" reflection, each joint taking its partner's turn since rest), so the
retarget and `mesh.py`'s grounding treat it like any preset. The carrier
mirror clip_fix used on the 23rd ("pose" mode) put the Minotaur's hooves 27 cm
through the floor (a foot 0.32 m off its reflection: his rest pose is
asymmetric), so it is kept for exactly one judged case, `POSE_MIRROR`:
**Hephaestus's heavy is the Heavy Hammer Swing mirrored on the carrier**, as
judged on the 23rd — his hammer arm rests bent across his chest, and every
swing retargeted from the donor's hanging arm stayed at his shoulder — with
the Axe Stance, so his five clips stay his own.

Mirrored as shipped: the Amazon, the Centurion, Mercury and Njord (all three
attacks), Nezha and the Harpy (basic and heavy), Bellona (heavy and ultimate;
her basic is the right hand's whip crack), Loki, Surtr, Achilles and the Dark
Elf (the basic only: see the judgments), Skadi (the three attacks and her
full-draw stance, her bow hand's wrist bent 65-78° after so the bow stands at
the loose), and Hephaestus's heavy on the carrier.

The other fixes of the 23rd are made by `ship` now, so a re-ship keeps them:
Sobek's snout is lifted to 75° off his torso's line on every attack (the
basic's closest was 60°, the heavy's 56°, the ultimate's 45°); Skadi's bow
wrist (`BOW_WRIST`). `clip_fix.FIXES` no longer names Hephaestus's mirror,
Skadi's mirror or Sobek's snout (a second run over the palette's clips would
undo them); its markers record what was applied on the 23rd.

### What each kit fights with

- **Blade** (23): 219, 97, 220, 206 / 242, 221, 238, 105 / 102, 105, 91, 86,
  the guard, half or stood, and 412, 298 or 88. The Jump Attack's leap only
  for the fliers and leapers (`JUMPERS`: Bastet, Mercury, Perseus, Achilles,
  Vidar, the Gladiator, the Shield Maiden, Sun Wukong, Fenrir, the Harpy, the
  Valkyrie, Nike); Sun Wukong's ultimate is the leap by override.
- **Polearm** (10): the blade moves with the spear-like 221 and 105 first.
- **Heavy** (16): 128 (with its synthesized recovery), 237, 127, 238, the Axe
  Stance, the chest pound.
- **Unarmed** (8): the claw swipe (97), the kick (206), the spinning kick
  (238), the pounce.
- **Caster** (17) and **robed** (19): the six casts; a robed caster never
  gets 125 as an ultimate now (it lifts a robe with both arms).
- **Archer** (6): the draw from the quiver (224, the basic cut after the
  reach), 222's draw from the back, the full-draw stance (226, mirrored for
  Skadi); a stance that is not at rest gives the stages the guard stood up.

### The re-measure, and the judgments

Every clip was measured on its family's shipped base and LOD against the one
it replaced (edges stretched past 3x over 32 frames). Totals over the 115
families (five clips on the base, three attacks on the LOD): **413,805 before,
422,176 as rolled out (+2.0%), 391,784 as judged (−5.3%)**; 25 families are
better by more than a tenth, 73 within it, 17 worse by more than a tenth
(small counts; the largest, Mars, Sun Wukong, Perseus and Poseidon, were
boarded and show no tear a frame shows).

The 24 clips whose count rose by half again and 100 more, and then 11 more
whose count rose by a quarter and 250 (the second tier), were boarded old
beside new at each version's worst frame. Where the new clip visibly tore the
model more, candidates from the same kit were shipped into scratch, measured,
and the one that tore least while keeping the family's five clips its own
replaced it (`JUDGED`, laid over the deal so no other family's deal moves);
where none measured at or under the old clip, the old file stayed (`KEPT`).
Kept as rolled out after the board: the Terracotta Soldier's victory (the
one flagged clip that tears no more than before to the eye), and, boarded as
checks, Nezha's basic, ultimate and victory (his cloth survey rose), Mercury's
victory (its cape's own strip), Mars's ultimate, Sun Wukong's basic, Perseus's
victory and Poseidon's ultimate.

| family | clip | as rolled out | as judged | edges past 3x: before | rolled out | judged |
|---|---|---|---|---|---|---|
| achilles | heavy | 221 mirrored | 242 unmirrored | 433 | 759 | 453 |
| achilles | ultimate | 86 mirrored | 102 unmirrored | 526 | 930 | 549 |
| aphrodite | ultimate | 125 | 126 | 2221 | 2902 | 1709 |
| atalanta | heavy | 224 | 224 from f70 (after the quiver reach) | 884 | 1177 | 933 |
| athena | heavy | 221 | 242 | 476 | 925 | 422 |
| athena | stance | 89 | guard stood | 358 | 309 | 310 |
| athena awakened | heavy | 221 | 242 | 10 | 13 | 16 |
| athena awakened | stance | 89 | guard stood | - | - | - |
| bellona | basic | 97 mirrored | 219 unmirrored | 1512 | 2226 | 1532 |
| bellona | victory | 298 | 88 | 1685 | 2294 | 1420 |
| bes | victory | 298 | 88 | 1419 | 1740 | 696 |
| bragi | ultimate | 125 | 126 | 2896 | 4128 | 2957 |
| bragi | victory | 412 | 88 | 3019 | 3108 | 2217 |
| cobra priestess | stance | guard stood | guard half stood | 18 | 15 | 15 |
| cobra priestess | ultimate | 125 | 126 | 173 | 393 | 181 |
| cobra priestess | victory | 298 | 88 | 304 | 355 | 106 |
| dark elf | basic | 206 mirrored | 220 mirrored | 709 | 725 | 701 |
| dark elf | heavy | 105 mirrored | 242 unmirrored | 788 | 1030 | 794 |
| dark elf | ultimate | 91 | 102 unmirrored | 914 | 1015 | 915 |
| demeter | victory | 298 | 412 | 671 | 1217 | 703 |
| dwarf smith | victory | 298 | 88 | 994 | 1788 | 710 |
| dwarf smith | basic | 97 | kept (Meshy's own 219) | 891 | 1560 | 891 |
| fox spirit | basic | 133 | 129 | 333 | 592 | 314 |
| fox spirit | stance | guard stood | guard half stood | 221 | 208 | 254 |
| frigg | ultimate | 125 | 126 | 2454 | 3407 | 2535 |
| harpy | basic | 206 mirrored | 220 mirrored | 337 | 500 | 251 |
| harpy | ultimate | 86 mirrored | 102 unmirrored | 493 | 795 | 494 |
| harpy | victory | 298 | 88 | 616 | 714 | 188 |
| hathor | ultimate | 125 | 126 | 1074 | 1971 | 1029 |
| hathor | victory | 412 | 88 | 1668 | 1665 | 686 |
| horus | victory | 298 | 412 | 185 | 593 | 254 |
| horus awakened | victory | 298 | 412 | 158 | 525 | 195 |
| idunn | basic | 133 | 129 | 1059 | 1569 | 1050 |
| idunn | stance | guard stood | guard half stood | 364 | 36 | 219 |
| isis | ultimate | 125 | 126 | 1194 | 1954 | 1175 |
| isis awakened | ultimate | 125 | 126 | 221 | 463 | 212 |
| jiangshi | ultimate | 91 | 102 | 484 | 817 | 439 |
| loki | basic | 97 mirrored | 220 mirrored | 560 | 1478 | 420 |
| loki | heavy | 221 mirrored | 242 unmirrored | 775 | 1409 | 705 |
| loki | stance | guard stood | 89 | 578 | 636 | 530 |
| loki | ultimate | 105 mirrored | 102 unmirrored | 857 | 1643 | 804 |
| medusa | victory | 298 | 412 | 20 | 235 | 45 |
| mummy | victory | 298 | 412 | 84 | 229 | 92 |
| odin | victory | 298 | 88 | 1360 | 2384 | 939 |
| odin awakened | victory | 298 | 88 | 602 | 1055 | 584 |
| pluto | ultimate | 125 | 126 | 1362 | 2172 | 1439 |
| pluto | victory | 412 | 88 | 1568 | 1599 | 683 |
| skadi | victory | 298 | 412 | 269 | 429 | 267 |
| sun wukong | victory | 88 | 412 | 111 | 299 | 113 |
| surtr | basic | 206 mirrored | 220 mirrored | 148 | 394 | 130 |
| surtr | heavy | 105 mirrored | 242 unmirrored | 254 | 604 | 220 |
| surtr | ultimate | 102 mirrored | 102 unmirrored | 302 | 504 | 272 |

What the table says: **125 as an ultimate lifted every robe** (it tore these
same robes as their HEAVY before the roll-out); **298's crouch before its hop**
stretches a kilt, a skirt or a cloak between the legs; and on **Loki, Surtr,
Achilles and the Dark Elf every mirrored swing drags the cloth or the blade
welded to the weapon arm's side** into a sheet — only the unmirrored motion
kept to the old count, so their heavy and ultimate swing as the donor does,
and their basic is the Shield Push mirrored (the free right hand shoves while
the weapon arm stays back), which tore least of all.

**The passes, re-measured on the final bundle** (`weapon_pass.py --survey`,
`--welds --survey`, `cloth_opt.py --survey` and a re-solve; before → after):
the thirty `WEAPON_FAMILIES` are all clean except Bes 4.9 → 3.8x and Serqet
4.0 → 3.9x (the Vestal's 2.0 → 1.0); the weld families Hel 15.8 → 11.2x, the
Hoplite 3.9 → 3.3x, Sif 20.1 → 20.1x, the rest clean. On the mirrored and
reworked families: Achilles's sword 15.4 → 15.7x (a held piece the pass
refused on its board on the 23rd), Surtr's 8.2 → 5.1x; welds Achilles 16.0 →
16.2, the Centurion 28.5 → 23.4, the Dark Elf 33.0 → 33.7, the Harpy 14.5 →
12.3, Loki 20.0 → 11.1, Njord 25.7 → 23.8, Skadi 17.0 → 16.8, Surtr 9.4 →
5.4, Hephaestus 5.1 → 5.2, Heracles 31.1 → 30.8. The weld pass re-run on the
Dark Elf (40x as rolled out) made its own measure worse (40.3 → 42.7) and was
not applied; the judged clips put him back at 33.7. The cloth optimiser
re-solved its six against the new clips: the Hoplite, Hades, Ptah, Mercury
and Nezha are refused by its guard (energy 225 → 226, 219 → 220, 173 → 171,
893 → 703, 2,178 → 1,695: nothing to gain that clears 75%), and Osiris's
solve (264 → 171) shows nothing on its board and he measures better than
before, so it was not applied. Its survey: the Hoplite 12.2 → 9.5x, Osiris
55 → 54x, Hades 19 → 18x, Ptah 7.0 → 7.2x, Mercury 97 → 105x (fewer free
points), Nezha 103 → 133x (the flagged Nezha clips show no tear on their
boards).

### What is left for a human

1. **Variety where the palette runs out.** The robed casters have 9 distinct
   attack triples for 19 (every robed ultimate is 126 or the three 125s that
   did not tear; the most shared by five); the archers one triple for six; and
   four left-handed blades (Loki, Surtr, the Dark Elf, the Harpy) share 220 /
   242 / 102, told apart by stance and victory. The expansion's five casts
   (131, 132, 134, 135, 137) and five archery presets (225, 227, 223, 229, 236)
   are 30 credits of the 108 in §8 step 2.
2. **Weapons that do not lead.** On Loki, Surtr, Achilles and the Dark Elf the
   heavy and the ultimate are swung by the empty right hand, and on Bellona
   the basic by the whip hand, because the weapon arm drags cloth or a blade
   welded to the thigh. The fix is in the mesh — a remake (§4), or a
   weapon/cloth pass that frees the piece (Achilles's sword was refused on its
   board on the 23rd; Loki's dagger is sewn to his coat).
3. **The smith's basic** is Meshy's own 219, unwarped: its blow is at 0.33 of
   the clip and the game fires at 0.42, about 0.12 s late.
4. **Found, older than this work:** the bespoke attack carriers of Ares, the
   awakened Ares, Thoth, the awakened Thoth, the awakened Zeus and the
   awakened Sekhmet bind their `head_end` (the awakened Sekhmet's `Head`)
   0.10-0.25 m off their shipped bases.
5. **On the phone**: the Jump Attack's leap in the battle frame, the half
   guard at battle distance, and every blow's timing (CI frames).
6. Osiris's cloth re-solve is available (`cloth_opt.py osiris --out DIR
   --board B`, about 3.5 minutes) if the owner wants its small gain.

Boards (session scratchpad, `rollout/boards/`): one per kit from the final
bundle and one before/after sheet of every judged clip; the judgments'
old-beside-new boards are in `rollout/judge/`.

## 11. The stage idle (2026-09-25)

The owner: "can we make the 3D characters have more of a fluid design and
poses, instead of all the same static, frozen style poses? Something more
natural" — then "Go ahead". The study, the options and the choice are in
`Docs/PLAN.md`, *Natural poses*; this is what the stages play now and how it
is made. The battle's stance is §9's, except where it says `natural`.

### What each stage plays

Every family's `<family>_idle.usdz` — the idle the island, the reveal, the
Hall of Ka's altar, the collection's Stage and the unit sheet's well play — is
`tools/natural_idle.py`'s for **115 of the 117 rigs**. It is built from the
rig's OWN BIND POSE, not from the combat guard: the concepts were painted
with the arms hanging 22° out and a soft elbow for the rigger (the median of
117 binds), so a pose made from there brings the arms down without dragging
the cloth welded to them. Until this day it was `tools/stand_idle.py`'s sum
of Meshy's 89 Combat Idle stood up, the same near-A-pose on every figure: the
guard's arms kept at 85% (51° and 39° out, the left hand a quarter of the
height in front of the hips in 106 of 117 — an invisible shield), level hips,
the weight centred, and a 1.27 s pant, 47 breaths a minute.

- **The 35 calm families** — the sovereigns, graces and mystics among the 45
  whose deal stood the guard up for battle — wear the SAME file as their
  `<family>_idle_combat.usdz` (`motion_palette.CALM`; the plan's stance reads
  `natural`). The genre's casters and kings stand calm in battle. Their
  stances tore 9,994 edges past 3x as the stood guard and 198 now. The other
  ten `stand` families (Surtr, Sun Wukong, Diana, Nike, Set, Dionysus, Sobek,
  the Centurion, the Hoplite, the Terracotta Soldier) and every `half` and
  preset stance keep theirs until the ready stances (PLAN.md step 4).
- **Two families are held on today's idle** (`OVERRIDES`' `hold`): Bastet and
  Serqet. The beast row's crouch turned a slim goddess into a squat that
  reads as sitting on nothing, and the scorpion queen's into the combat guard
  the owner objected to (the judge of 2026-09-25). Their `retry` is the row's
  own plain values as the whole style; if either still reads crouched, it
  moves to `grace` (Bastet) or `champion` (Serqet) in `ARCHETYPE`.

### How a family's idle is made

- **An archetype per family** (`motion_palette.ARCHETYPE`, an awakened form
  taking its family's): sovereign 27 rigs, champion 18, brute 14, grace 14,
  trickster 10, mystic 9, soldier 7, construct 7, hunter 6, beast 5. Each is a
  row of `STYLES`, ranges over `BASE`, and every number a family takes is
  drawn inside its row's range from a hash of its key, so no two stand alike.
- **Contrapposto:** the weight on the leg opposite the weapon hand
  (`WEAPON_HAND`, Polykleitos's chiasm), the pelvis over that foot (0.64 of
  the way between the feet at the median), rolled up over it and turned, the
  standing foot drawn toward the midline, the spine counter-rolled so the
  shoulders tilt against the hips, the head turned toward the standing side.
  Both legs are tried; the chiastic one is kept unless the other tears less
  (23 of 115 stand on the other, Vidar by `OVERRIDES`' `side` so that he does
  not stand as Tyr does).
- **The feet** are planted by two-bone IK on their bind spots, each knee on
  its bind's pole (never inward), the free foot a little ahead and turned
  out; a leg the bind holds bent (a hoof, a paw) is never straightened. No
  root lock: the loop is written straight onto the family's carrier, so the
  hips sway (1.2 cm at the median) and the feet stay put.
- **The arms** start at the bind's hang, take the row's swing (a mystic's
  hands low before the waist, a brute's held off the body), a bind wider than
  26° is brought partly down, and they follow the chest a quarter of a second
  late. The standing side's arm swings out as far as its hip comes out under
  it, and an arm the guard finds in the body swings out 3° at a time.
- **The motion:** a breath with the inhale 40% of it, a lateral and a
  fore-aft sway, the head's slow survey and quicker glances, and the row's
  own (a brute's neck roll, a trickster's off-beat hitch of the hip, a
  construct's settle and stiff twitch, a beast's head bob; a giant breathes
  slower by the square root of its size). Every one is a whole number of
  cycles in the loop, which is written as F+1 keys with the last equal to the
  first — SceneKit's loop is its last key's time long, so the old F-key loops
  skipped a frame at every wrap.
- **The flourishes** (the full weight shift, the drawn-in stance, the soft
  knees, the arms' swing, the row's extras) are tried together; where that
  tears more than the plain stance (the bind's arms, near-straight legs) by
  more than five edges, they are added to it one at a time, whole or at half,
  while the tear stays in that slack. 82 families keep their whole style, 33
  keep part of it, and each survey line names what was held back.
- **The bolder sovereign:** a sovereign whose pick tears nothing tries the
  `BOLD` row (the pelvis rolled 4.0–5.5°, the weight 0.66–0.72 of the way
  over) and keeps it only if it still tears nothing and pushes no more of
  the arm or the held piece into the body. 14 of the 27 took it; Athena,
  the awakened Horus and Osiris did not.
- **The joints are found by where they sit, never by name** (`Rig`): the
  pelvis is the root most joints hang from, the legs its two chains to the
  floor, the chest the first spine joint two arms leave, and the head the
  joint the SKULL's vertices are skinned to. On the eleven rigs that call the
  joint over the hips `neck`, that is the joint named Head1 or Spine1 (Zeus's
  `Head` is an end marker holding no vertex; his `Head1` holds all 1,689 of
  his skull's); on Hephaestus, Fenrir and Ullr it is the one named `neck`.
  A gaze or a collider must turn the joint that carries the skull.

### The guards

A file is refused, and the family keeps what it had, when:

- a foot joint drifts more than a millimetre over the loop, or a foot's
  lowest point rises more than a millimetre off its bind height or sinks more
  than 5 mm into the floor (scaled up for a giant; the Jötunn's heels, a third
  on the shins, are allowed 25 mm on a 4.5 m figure);
- the carrier binds off the shipped base (`bind_against_base`);
- it tears more (`clip_fix.clip_stretch`, edges stretched past 3x on the
  shipped base over 24 frames) than the file it replaces — measured BEFORE
  anything is written, since a ship into the app's bundle overwrites it, and
  for a calm family against its stance as well;
- a forearm or a hand lies inside the thigh or the trunk below the armpits
  more than 1.2% of the height deeper than it lay in the bind, at more than
  12 vertices;
- the loop does not close, or its seam steps more than 1.5 times its own
  step.

Every file is made in a work folder, re-read by `character.verify`, and
copied into the bundle only when all of that passes. During the search only
the whole style is held to the replaced file (else the flourishes go one at a
time); the plain stance and the trials are steps, not files, and holding them
to it made a re-ship over a natural idle impossible (Hera's plain stance
tears 18 under her robe against the 7 shipped). Re-derived over the shipped
bundle, the survey reproduces all 150 files key for key and refuses none.

### Measured, as shipped

On the shipped bases, the 117 standing idles before and after (the two held
counted as they are):

| | the stood guard | as shipped |
|---|---|---|
| edges past 3x | 22,202 | 599 (512 on the 115, 87 on the two held) |
| families with none | 21 of 117 | 69 of the 115 |
| the median family's worst stretch | 6.8x | 2.3x |
| families that tear more | — | none |
| the loop | 1.27 s (1.03–1.67) | 8.05 s (6.6–14.2), 14.9 breaths a minute (8.5–18.2) |
| the upper arms from straight down | 51° / 39° | 18.5° |
| hips tilted over 3° | 1 of 117 | 79 of 115 (4.0° at the median, against the bind) |
| the hips' sway | 0.0 cm (the root lock) | 1.2 cm |
| the feet | slide 1.3 cm | planted: 0.001 mm, 0.9 mm off the floor at most |

By archetype, edges past 3x before and after: sovereign 5,788 → 224, grace
4,908 → 52, champion 2,629 → 22, trickster 2,297 → 59, soldier 2,049 → 9,
brute 2,024 → 39, mystic 894 → 17, hunter 868 → 32, beast 441 → 108 (86 of
them Serqet's held idle), construct 304 → 37. Freya 1,719 → 28, Frigg 1,359
→ 4, Heracles 1,095 → 20, Hera 957 → 7, Achilles 385 → 0, Ares 275 → 0. The
worst left are Horus and the awakened Hera at 75 each, a kilt or a skirt
skinned to both thighs.

**The files are written at 20 keys a second** (`FPS`, `--fps`), not the
clips' 30: at 30 the 115 idles and the 35 stances added 22.8 MB to the bundle
against the plan's 16, and nothing in a loop needs more — a 4 s breath gets 80
keys a cycle, and the construct's 0.07 s twitch still lands on a key. 133–285
keys a file, 224–510 KB; the bundle grew 13.8 MB. 15 is the fallback if the
CI's `[Mem]` climbs.

### The Swift that plays it

No stage needed a change to pick the file up (`restingIdle`, `startLoop`),
but four faults were mended in the same push (lane S, 2026-09-25):
`UnitNode.restartIdle()` plays `restingIdle` (it played `.idleCombat`, so a
team changed while the island was up crouched every figure until its first
hop); `play(_:)` takes the previous LOOP off over `loopBlendOut` 0.25 s when a
different loop starts (`handOver(to:)`, `currentLoop`: an island figure that
had strolled evaluated `idle_combat`, `walk` and `idle` every frame); `revive`
hands back to `idleAfterClip`, the fight's stance, not the stage's idle; and
`SCNNode.startLoop` starts every stage's loop at a random `timeOffset`.
`ClothChain`'s chest collider is found by position (`Cloth.chestKey`: Spine01
on 106 rigs, Spine02 on the 11), so the awakened Hera's cape has its eighth
sphere. The tour photographs `0-island-rebuild` (`-tour-island-rebuild`: the
team changed under a live island, whose figures must stand as in `0-island`;
the console's `[Idle] … restarted in idle` line) and the pose lab,
`3-training-pose-constraint` and `3-training-pose-write`
(`-tour-pose-lab constraint|write`: a 20° head turn laid over the playing
idle by a transform constraint, or by writing the joint after the
animations; the `[PoseLab]` lines say whether the presentation turned, the
frames whether the mesh followed). The lab turns the joint `Head` hangs from,
which carries the skull on every rig.

### The commands, and the places that make the idle

```
python3 tools/natural_idle.py survey [families] --bundle DIR --calm-stances --json F   # measure (and write to scratch)
python3 tools/natural_idle.py board horus vidar --out DIR [--bundle DIR]              # today's idle, then 0/25/50/75%
python3 tools/natural_idle.py sheet sovereign --out F [--bundle DIR]                  # one archetype at one instant
python3 tools/natural_idle.py gif zeus --out DIR                                     # today's beside the new, moving
python3 tools/natural_idle.py ship --all --bundle Pantheon/Resources/Models --calm-stances   # as shipped
```

So that no re-ship can put the stood guard back:
- `motion_palette.py ship` takes `idle=natural` (the idle made after the
  clips, on the carrier just shipped) and `idle_combat=natural` (the same
  file as the stance; the guard is retargeted only as the carrier), and
  `roll` passes both; `idle=stand` is kept for the record.
- `tools/batch/build_asset.sh` and `tools/batch/proportions.sh` run
  `natural_idle.py ship <family> --calm-stances` after the ship, because a
  re-shipped base can change the bind. Where it refuses a family (no
  `ARCHETYPE` row, a guard) they stand the guard up instead and say
  `NATURAL IDLE REFUSED`, so the stages still have an idle that binds.
- `clip_fix.py --rearm` no longer re-derives the standing idle from the
  fixed combat idle (the natural idle does not come from it).
- `stand_idle.py` stays for the stances still made from the guard (`stand`,
  `half`), for the held families, and as that fallback. A held family's idle
  is kept by `ship` while it binds, and made again from its combat idle when
  a re-shipped base has left it binding off.

### What is left

1. **A weapon held level.** The bind's grip is kept, so on eleven families the
   blade or the pole lies level at the hip instead of hanging by the thigh:
   Athena (the spear at the lens), Hades, Poseidon, Neptune, Guan Yu, Baldr
   (the spear slung up through the cloak), the awakened Ares, Mars and the
   awakened Mars, Anhur, and the Jötunn's axe across the belly. The judge's
   fix is a pitch at the weapon wrist — a blade 30–50° tip down, a pole
   raised to 60–75° like Pluto's and Frigg's — with the tip 5% of the height
   off the floor and inside the arm-through check.
2. **The breath is quiet** on purpose (1.0–2.4°); every board's four
   instants look alike. Raise it to 1.5–2.5° if the CI's `[StageDoctor]`
   Hips and Hand lines read still (they were 7 mm and 3 cm in five seconds
   before).
3. **Bastet and Serqet's re-run** (their `retry`), then a board each.
4. **Stances that barely changed:** Horus and the awakened Hera (the weight
   held back by a kilt or a skirt on both thighs), the awakened Ra, Diana
   (her arms came in only 2° — further tore her), and Sun Wukong, whose whole
   trickster style failed its guards; the Jiangshi's arms stop at 30°
   (forward), which reads as a shamble.
5. **At the arm-through limit** with nothing on the board: Hel and Taweret
   at 12 of 12, Hermes and Bragi at 11.
6. **Gestures and variety** belong to the runtime layer and the palette
   (PLAN.md steps 5–8): the weight shift between two variants, the gaze, the
   idle breaks, a hand on the hip.
7. **Apollo's third arm** (the audit's fault) shows plainly with the arms
   hanging: a remake, not an idle.
