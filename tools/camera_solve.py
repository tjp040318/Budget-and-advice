#!/usr/bin/env python3
"""The battle camera's solve, ported from `CameraDirector.solve(for:)`, so a
change to the framing is measured before a CI run is spent on it.

    python3 tools/camera_solve.py                  # the shipped constants
    python3 tools/camera_solve.py pitch=20 fov=30  # try other numbers

For each line-up it prints where the camera stands, where the team's and the
enemies' feet land (fractions of the frame's HEIGHT from the top), how tall a
figure stands (fraction of the height), how far across the rows spread
(fraction of the WIDTH), and where the floor's far edge lands; the last
eighteen lines are boss fights (every boss from the Unwrapped King's 6 m to
the Colossus's 8 m behind a three-, four- and five-a-side team) with the
boss's rim and head, which must land 7–17% down, under the boss bar.

The owner's Summoners War arena frame (2026-09-24), measured: pitch 19°,
yaw 0, a 24–30° lens, the team's feet 0.84–0.87 down and its figures about
0.30 of the height, the enemies' feet 0.36–0.38 down and about 0.18, a
four-a-side across 0.23–0.77 of the width and the enemies across 0.30–0.70,
the far wall 23–25% down. The shipped constants give 0.82–0.86 / 0.30–0.31
and 0.35–0.38 / 0.17–0.18 from 1v1 to 3v3 with the far edge 0.23–0.24 down;
the team's row is held inside 0.24–0.76 of the width (`twidth`, clear of
the skill squares and the controls), which steps the camera back a percent
for a four-a-side (0.29 tall, far edge 0.25) and a tenth for a five, whose
marks are 2.0 m apart (`tsp5`; 0.27 tall, far edge 0.27). A boss fight is
not held to the band: backing off drops the boss's head down the frame.

KEEP IN STEP with CameraDirector.swift (`lensFieldOfView`, `homePitch`,
`homeYaw`, `nearFeetLine`, `farFeetLine`, `fieldTopLine`, `bossPitch`,
`bossYaw`, `bossFeetLine`, `bossTopLine`, `minDistance`, `shoulderRoom`,
`teamWidthMargin`), BattleSceneController.position(for:teamSize:) (spacing,
the five-wide team's spacing, and stagger), StageBuilder+Arena.swift
(`arenaCentre`, `arenaRowDepth`) and StageBuilder.battleFloorFarEdge.
"""
import sys

import numpy as np

ASPECT = 2.17  # 852 x 393 points, a landscape iPhone

C = dict(
    fov=28, pitch=19, yaw=0, feet=0.72, farline=0.26, top=0.80,
    bpitch=9, byaw=0, bfeet=0.92, btop=0.88,
    centre=1.8, rowdepth=5.2, tsp=2.4, tsp5=2.0, esp=3.2, tstag=0.5, estag=1.0,
    edge=-11.0, sink=0.32, mind=8, maxd=40, width=0.98, twidth=0.64, shoulder=0.9,
)


def basis(pitch, yaw, fov):
    p, y = np.radians(pitch), np.radians(yaw)
    fw = np.array([np.sin(y) * np.cos(p), -np.sin(p), -np.cos(y) * np.cos(p)])
    rt = np.array([np.cos(y), 0.0, np.sin(y)])
    up = np.cross(rt, fw)
    tv = np.tan(np.radians(fov) / 2)
    return fw, rt, up, tv, tv * ASPECT


def solve(points, boss):
    """points: (position, topLine, isBoss). The same passes as the Swift."""
    pitch, yaw = (C["bpitch"], C["byaw"]) if boss else (C["pitch"], C["yaw"])
    feet = C["bfeet"] if boss else C["feet"]
    fw, rt, up, tv, th = basis(pitch, yaw, C["fov"])
    aim = np.array([np.mean([q[0][0] for q in points]), 1.0, np.mean([q[0][2] for q in points])])
    gap_depth = None
    near_z = 0.0
    if not boss:
        feet_z = [q[0][2] for q in points if q[0][1] < 0.01]
        # The enemy's own marks only, as `CameraDirector.solve` (2026-09-24):
        # a dash's landing spot in front of the row never joins the mean.
        far = [z for z in feet_z if z <= C["centre"] - C["rowdepth"] + 0.01]
        if feet_z and far:
            near = max(feet_z)
            gap = near - sum(far) / len(far)
            below, above = np.arctan(feet * tv), np.arctan(C["farline"] * tv)
            e1, e2 = np.radians(pitch) + below, np.radians(pitch) - above
            if gap > 0 and e2 > 0 and np.tan(e1) > np.tan(e2):
                behind = np.tan(e2) * gap / (np.tan(e1) - np.tan(e2))
                gap_depth = behind / np.cos(e1) * np.cos(below)
                near_z = near
    d = 16.0
    for _ in range(8):
        req = C["mind"]
        if gap_depth is not None:
            req = max(req, gap_depth - (np.array([0, 0, near_z]) - aim) @ fw)
        for q, tl, _b in points:
            o = q - aim
            a, v, dp = o @ rt, o @ up, o @ fw
            req = max(req, abs(a) / (C["width"] * th) - dp)
            # The team's feet inside `teamWidthMargin`, ordinary fights only.
            if not boss and q[1] < 0.01 and q[2] > C["centre"]:
                req = max(req, abs(a) / (C["twidth"] * th) - dp)
            if v > 0:
                req = max(req, v / (tl * tv) - dp)
            elif gap_depth is None:
                req = max(req, -v / (feet * tv) - dp)
        d = min(C["maxd"], req)
        left, right, low, boss_across = 1.0, -1.0, 1.0, None
        for q, _tl, b in points:
            o = q - aim
            dd = o @ fw + d
            across = (o @ rt) / (dd * th)
            left, right = min(left, across), max(right, across)
            low = min(low, (o @ up) / (dd * tv))
            if b:
                boss_across = across
        shift = (boss_across if boss_across is not None else (left + right) / 2) * d * th
        aim = aim + rt * shift + up * ((low + feet) * d * tv)
    return aim - fw * d, aim, (fw, rt, up, tv, th)


def project(xs, pos, frame):
    fw, rt, up, tv, th = frame
    o = np.asarray(xs, float) - pos
    z = o @ fw
    return 0.5 + (o @ rt) / z / (2 * th), 0.5 - (o @ up) / z / (2 * tv)


def marks(n, side):
    player = side > 0
    sp = (C["tsp5"] if n >= 5 else C["tsp"]) if player else C["esp"]
    st = C["tstag"] if player else C["estag"]
    out = []
    for i in range(n):
        depth = C["rowdepth"] + (st if i % 2 else 0)
        out.append(((i - (n - 1) / 2) * sp, C["centre"] + side * depth))
    return out


def run(n_team, n_enemy, h=2.0, eh=2.0, boss_height=None):
    team, enemies = marks(n_team, 1), marks(n_enemy, -1)
    pts = []
    for (x, z), height in [(m, h) for m in team] + [(m, eh) for m in enemies]:
        for dx in (-C["shoulder"], C["shoulder"]):
            pts.append((np.array([x + dx, 0.0, z]), C["top"], False))
        pts.append((np.array([x, max(1.6, height), z]), C["top"], False))
    for x in (-3.0, 3.0):
        for z in (C["centre"] - C["rowdepth"], C["centre"] + C["rowdepth"]):
            pts.append((np.array([x, 0.0, z]), C["top"], False))
            pts.append((np.array([x, 1.9, z]), C["top"], False))
    head = None
    if boss_height:
        for dx in (-C["shoulder"], C["shoulder"]):
            pts.append((np.array([dx, 0.0, C["edge"]]), C["top"], False))
        head = boss_height * (1 - C["sink"])
        pts.append((np.array([0.0, head, C["edge"]]), C["btop"], True))
    pos, aim, frame = solve(pts, boss_height is not None)
    T = np.array([[x, 0, z] for x, z in team])
    E = np.array([[x, 0, z] for x, z in enemies])
    tx, ty = project(T, pos, frame)
    _, thy = project(T + [0, h, 0], pos, frame)
    ex, ey = project(E, pos, frame)
    _, ehy = project(E + [0, eh, 0], pos, frame)
    edge = project([[0, 0, C["edge"]]], pos, frame)[1][0]
    line = (f"{n_team}v{n_enemy} {h}/{eh} m: camera ({pos[0]:.1f}, {pos[1]:.1f}, {pos[2]:.1f}) "
            f"aim {np.linalg.norm(aim - pos):.1f} m | team feet {ty.min():.2f}-{ty.max():.2f} "
            f"fig {np.mean(ty - thy):.2f} across {tx.min():.2f}-{tx.max():.2f} | enemy feet "
            f"{ey.min():.2f}-{ey.max():.2f} fig {np.mean(ey - ehy):.2f} across {ex.min():.2f}-{ex.max():.2f} "
            f"| far edge {edge:.2f}")
    if head is not None:
        _, by = project([[0, 0, C["edge"]], [0, head, C["edge"]]], pos, frame)
        line += f" | boss {boss_height} m rim {by[0]:.2f} head {by[1]:.2f}"
    print(line)


def main():
    for arg in sys.argv[1:]:
        key, value = arg.split("=")
        if key not in C:
            sys.exit(f"unknown constant {key}; one of {', '.join(C)}")
        C[key] = float(value)
    for n in [(1, 1), (2, 2), (3, 3), (4, 4), (4, 5), (5, 5)]:
        run(*n)
    run(3, 3, 1.9, 2.6)
    run(5, 5, 2.0, 3.0)
    run(3, 3, 2.6, 2.0)
    # Boss fights: the Unwrapped King 6.0, the Longmen dragon 6.6, the Hydra
    # 7.0, Apep 7.2, the Jotunn 7.5, the Colossus 8.0, each behind a three-,
    # four- and five-a-side team.
    for height in (6.0, 6.6, 7.0, 7.2, 7.5, 8.0):
        for n in (3, 4, 5):
            run(n, 2, boss_height=height)


if __name__ == "__main__":
    main()
