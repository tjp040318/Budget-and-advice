export const meta = {
  name: 'signature-judge',
  description: 'Judge each archived signature motion on its donor board: does it match its sentence, where does each strike land, keep or re-roll',
  phases: [{ title: 'Judge', detail: 'one agent per batch of motions reads their boards' }],
}

const BATCHES = args.batches
const VERDICT = {
  type: 'object',
  properties: {
    motions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          key: { type: 'string' },
          verdict: { type: 'string', enum: ['keep', 'aim', 'reroll'] },
          contact_frames: { type: 'array', items: { type: 'integer' }, description: 'the frame of each strike (a rite or a cast: its release), in order' },
          frames: { type: 'integer', description: 'the motion frame count shown on its board title' },
          reason: { type: 'string', description: 'for a reroll: exactly what is wrong (wrong count, travels away, turns its back, arms through the body, nothing happens, ...)' },
          new_sentence: { type: 'string', description: 'for a reroll: a corrected single-action sentence under 70 words that keeps the family idea and fixes the fault (same style and rules as the original)' },
          notes: { type: 'string' },
        },
        required: ['key', 'verdict', 'contact_frames', 'frames', 'reason', 'new_sentence', 'notes'],
      },
    },
  },
  required: ['motions'],
}

const results = await parallel(BATCHES.map((batch, i) => () => agent(
  `You judge archived signature attack motions for a Summoners War-style battler. Work in /home/user/Budget-and-advice. ` +
  `The manifest Art/Motions/skills.json holds each key's sentence ("prompt"), its seconds and its role; the motion is Art/Motions/<key>.motion.npz ` +
  `on a donor rig (a sword-and-shield maiden - ignore that she holds a sword and shield: judge the BODY's motion against the sentence).\n\n` +
  `For each key in [${batch.join(', ')}]:\n` +
  `1. Render: python3 tools/skill_moves.py board <key> --every 3 --size 230 --views front,side --wrap 8 --out /tmp/judge_${i}_<key>.jpg ` +
  `(each cell is labelled f<frame>/<last>; the blue curve under it is the hands' speed, red lines the automatic peaks - only hints). Read the image.\n` +
  `2. Decide: KEEP if the body does what the sentence says as ONE clean readable action (the right number of blows for a basic: one, or two when the ` +
  `sentence says two; an ultimate's wind-up then its one release; a style_*_area key: ONE wide blow, slam or cast that plainly reaches the whole enemy line in front, released once), facing the target in front, staying roughly in place, ending near its stance. ` +
  `AIM (not reroll) if the ONLY fault is direction: the blow or throw lands off to one side of a target in front, or the body is turned side-on while it strikes - ` +
  `the ship turns every clip so its blows land on the target, so a good action pointed the wrong way is kept. Travel is never a fault either: the game holds the hips on the spot. ` +
  `REROLL only for faults a turn cannot fix: the wrong number of blows for a basic, a spin or a turn that shows the back to the target for more than about half a second, ` +
  `an arm through the body, a broken or folded head, collapsing to the floor, barely moving (no clear fast blow or release), starting part-way through the action, or the wrong hand leading (say which).\n` +
  `3. Give contact_frames: the frame each blow lands (the weapon hand at full extension through where a target at chest height stands), or the frame a ` +
  `cast or rite releases. Be exact; re-render a stretch with --every 1 if needed.\n` +
  `4. For a reroll, write new_sentence: the same idea, fixed (one action, the right hand for a one-handed weapon, start and end in the stance, "In place.").\n` +
  `Do not modify any repository file. Do not run git.`,
  { label: `judge:${i + 1}`, phase: 'Judge', schema: VERDICT }
)))
return { motions: results.filter(Boolean).flatMap(r => r.motions) }
