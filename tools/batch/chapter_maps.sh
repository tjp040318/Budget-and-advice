#!/bin/bash
# The other eleven chapter maps, the way Duat 1 was painted on 2026-09-14:
# one Gemini image per chapter at 21:9 (the phone's landscape content area
# is about 2.5:1, so the fill crops 3% top and bottom), the region seen
# from a high oblique angle with ONE road unbroken from the lower left to
# the upper right past five landmarks in story order, the boss's lair last
# and largest at the upper right, so the tier chips at the top centre and
# the title plate at the top left cover sky and not a landmark.
#
# NOT RUN UNTIL THE OWNER'S WORD: Gemini is paused (CLAUDE.md), and he
# asked to judge Duat 1 on the finished screen first. Eleven images at
# about 14 cents each is about $1.60.
#
# After it runs: the medallions and chests are NOT placed by this script.
# Measure each painting with `python3 tools/mapgrid.py Pantheon/Resources/Portraits/map_<id>.jpg`
# (a ten-by-ten grid to read the landmarks off; `--dots x,y ...` to check a
# guess), and add a `ChapterMapArt` row per chapter to
# `ChapterMapArt.byChapter` in `Pantheon/UI/Campaign/CampaignMapView.swift`:
# ten `nodes` in stage order along the road (the five landmarks and the
# road between them; the tenth on the lair), three `chests` on open ground
# beside the road (by the third stage, by the boss, beyond it). A chapter
# without a row keeps the stage painting and the code road.
cd "$(dirname "$0")/../.."
OUT=Pantheon/Resources/Portraits

map() {
    { [ -s "$OUT/map_$1.png" ] || [ -s "$OUT/map_$1.jpg" ]; } && { echo "have map_$1"; return; }
    python3 tools/genart.py --prompt "Stylised painted game map of a region seen from a high oblique angle, the way a mobile RPG draws the map of one campaign area: $2. One winding $3 runs unbroken from the LOWER LEFT corner to the UPPER RIGHT corner across the whole picture, passing five distinct landmarks that are evenly spaced along it and clearly separated by open ground: first, at the lower left, $4; second, $5; third, $6; fourth, $7; fifth, at the upper right, $8, the boss's lair, the largest landmark, menacing. Painterly and richly detailed, $9, the road clearly visible the whole way, no characters, no creatures on the road, no text, no labels, no icons, no markers, no user interface, wide panoramic composition" --out "$OUT/map_$1.png" --size 2520x1080 >/dev/null 2>&1 && echo "ok map_$1" || echo "FAILED map_$1"
}

# Egypt
map duat_2 "the western road of the Egyptian underworld at night, the road of the seven gates" "sand road lit by torches" \
    "a towering pylon gate with two torches and a papyrus scroll carved over the door" \
    "a second gate half buried in a dune, its name-scroll gnawed and torn" \
    "a dark gate standing silent between two rows of guardian statues" \
    "the hall of two truths, a colonnaded hall with a great pair of scales inside" \
    "the fourth gate broken open with a beast's den behind it, bones and a crocodile-headed shadow in the dark" \
    "deep night blues and violets with torch gold, a thin band of starry sky along the top edge only"

# Greece
map olympus_1 "the foot and slopes of Mount Olympus in bright Greek morning" "white marble stair and mountain path" \
    "a marble stair rising from an olive grove with a small roadside shrine" \
    "a terrace of broken columns among cypress trees" \
    "a round temple on a ledge with a spring falling beside it" \
    "the great gate of Olympus standing open and unguarded between two colossal statues" \
    "a black cellar mouth under the mountain glowing with forge fire, a giant's chains hanging in the entrance" \
    "white marble, blue and gold, a clear sky with clouds along the top edge only"

map olympus_2 "the Aegean coast road along white cliffs above a turquoise sea" "coastal cliff road" \
    "a fishing harbour with wrecked ships thrown onto black rocks" \
    "a cape with a stone lighthouse and a shipwreck below it" \
    "a sea cave in the cliff with a beached galley outside it" \
    "a clifftop temple of the sea god with a bronze trident" \
    "a ruined temple garden crowded with stone statues of frozen sailors, a serpent shadow across its door" \
    "turquoise sea, white rock and sun-bleached gold, a hazy sky along the top edge only"

map olympus_3 "the marsh of Lerna, a drowned green wetland under a sickly sky" "wooden causeway through the marsh" \
    "a village on stilts with its boats sunk" \
    "a drowned shrine with its columns standing in black water" \
    "a grove of dead trees standing in the water with rope bridges" \
    "a great mound of old bones beside a burnt tree" \
    "a vast fog-filled pool ringed with reeds where many serpent necks rise coiled together" \
    "black water, marsh green and sulphur yellow, mist, a dull sky along the top edge only"

# Norse
map yggdrasil_1 "a Norse fjord road between pine forest and grey water under snow peaks" "stony fjord road" \
    "a longship harbour with beached ships and a smoking pyre" \
    "a rune stone on a headland above the water" \
    "a stave church with a dragon-carved roof in the pines" \
    "a burial mound ringed with standing stones and raven flags" \
    "a great mead hall hung with a bear-skin banner and axes, its doors thrown open, blood on the snow" \
    "cold blue water, dark pine green and snow, a grey sky along the top edge only"

map yggdrasil_2 "the underworld beneath the world tree, a cavern among colossal glowing roots" "path among the roots" \
    "a cave mouth under a knot of huge roots with a stair going down" \
    "a stone well under the roots with a glow rising from it" \
    "a barrow field of open graves and leaning stones in the dark" \
    "a bridge made of a single root spanning a black chasm" \
    "a cavern where a giant serpent's coils gnaw the roots, an ice-crusted troll's den in the roots above" \
    "deep earth browns and root-glow teal, cold light from below, a dark rocky ceiling along the top edge only"

map yggdrasil_3 "the frozen kingdom of the giants, ice fields and glacier walls under an aurora" "ice road" \
    "a frozen pass between pillars of blue ice" \
    "a giant's abandoned camp with a fire pit the size of a house" \
    "a frozen waterfall with a hall carved behind it" \
    "a bridge of ice over a chasm hung with icicles" \
    "an enormous ice hall with a throne of frozen bones and a hammer-shaped scar in its door, torches burning green" \
    "white and glacier blue with green aurora light, the aurora along the top edge only"

# Rome
map rome_1 "the city of Rome at midnight seen from above, the Forum under a full moon" "paved Roman street" \
    "a triumphal arch at the city gate lit by two torches" \
    "a round temple with a cold dead hearth and smoke still rising" \
    "a long colonnaded basilica with its doors broken" \
    "the speakers' platform in the Forum with empty standard-holders where the eagles stood" \
    "the Capitol hill with a legion's camp of tents and torches around its temple, rows of spears in the moonlight" \
    "moonlit white marble, blue-violet night and torch orange, a starry sky along the top edge only"

map rome_2 "the amphitheatre district of Rome in hot afternoon sun" "paved street between the arena's buildings" \
    "a gladiator school's courtyard with wooden training posts" \
    "the beast pens with cages and a drinking trough" \
    "a market of weapon stalls under striped awnings" \
    "the great arched gate of the amphitheatre hung with red banners" \
    "the arena floor itself seen from above, raked sand with a colossal bronze giant standing in its centre, the crowd's tiers around it" \
    "hot ochre stone, red awnings and bronze, a hard blue sky along the top edge only"

# The Jade Court
map jade_1 "a celestial peach orchard on terraces among the clouds at dawn" "stone garden path" \
    "a round moon gate in a white wall with a red lacquered door" \
    "a jade pavilion with an upturned roof beside a lotus pond" \
    "terraces of gnarled peach trees in pink blossom" \
    "an arched stone bridge over a ravine filled with mist" \
    "a fox shrine among red lanterns and stone foxes, its peach trees stripped bare, nine tails of mist rising from it" \
    "pink blossom, jade green and gold, soft rose light, a cloud sea along the top edge only"

map jade_2 "the river falls of Longmen descending into the dragon king's sea kingdom" "river road that becomes a path along the sea floor" \
    "the falls of Longmen with carp leaping the cascade" \
    "a sunken temple with its roof above the waves" \
    "a coral forest on the sea floor with a wrecked junk" \
    "a pearl grotto lit from within" \
    "the great crystal gate of the dragon king's palace with a colossal dragon lying coiled across it, jade pillars and red lacquer" \
    "river blue into deep sea green, jade and coral red, shafts of light, the sky and the falls' spray along the top edge only"

echo chapter-maps-done
# The paintings ship as JPEG (tools/shrink_art.py); genart.py writes PNG.
python3 tools/shrink_art.py
