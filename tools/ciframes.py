#!/usr/bin/env python3
"""
Fetches the screenshots the CI job took of the app and lays them out on one
sheet, so a session that cannot run the simulator can look at the game.

    python3 tools/ciframes.py                 # -> /tmp/ci_frames/ and ci_sheet.jpg beside it
    python3 tools/ciframes.py --out my.jpg
    python3 tools/ciframes.py --log-lines 200 # more of each step's console

The job also publishes each step's console (<step>-console.txt: the app's
stdout and stderr, with the frameworks' os_log lines mirrored in) and the
simulator's log for the process (system-log.txt). This prints the lines that
matter from each — the [ModelLibrary] block, anything that says error or
shader, and each launch's frame pacing ([Frames], Docs/FEEL.md W2.26) — and
leaves the files in frames/.

The job (.github/workflows/build.yml) launches the app in a simulator once per
screen with `-tour -tour-step N`, photographs it, and force-pushes small JPEGs
of the frames to the orphan branch `ci/screens`, which this fetches. The
artifact store keeps the full-size PNGs, but it lives on a host the session's
network policy refuses; the branch does not.

The simulator captures a landscape-only app in a portrait framebuffer, so a
frame taller than it is wide is stood up here.

The last step, the skill reel (2026-09-25, Docs/PLAN.md "Skills that look
like themselves"), is RECORDED: the job publishes skill_reel.mp4 (or, when
no MP4 could be made, the simulator's own skill_reel.mov) beside the frames,
and skill_reel.txt saying how it was made. This prints the video's path, size,
length and frame size and every cast the reel made, and lays the video out as
a contact sheet, reel_sheet.jpg beside the frames' sheet, a frame every
--reel-every seconds (OpenCV when it is installed, else the ffmpeg that
imageio-ffmpeg ships; --no-reel-sheet skips it).

    python3 tools/ciframes.py --reel-every 1.5   # a denser reel sheet
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The skill reel's video as the job publishes it: the MP4 first, the raw
# recording when no MP4 could be made.
REEL_VIDEOS = ("skill_reel.mp4", "skill_reel.mov")


def crash_summary(path):
    """The lines of a crash report that name the death. An .ips is a JSON
    header line and a JSON body: the exception, the termination, the
    application-specific lines (an assertion's text) and the crashed thread's
    frames. A legacy .crash text is printed as it is."""
    lines = open(path, errors="replace").read().splitlines()
    body = None
    for i in range(min(3, len(lines))):
        try:
            body = json.loads("\n".join(lines[i + 1:]))
            break
        except ValueError:
            continue
    if not isinstance(body, dict):
        return lines[:80]
    out = []
    if body.get("procLaunch") or body.get("captureTime"):
        out.append(f"launched {body.get('procLaunch', '?')}, crashed {body.get('captureTime', '?')}")
    exc = body.get("exception") or {}
    out.append(" ".join(str(exc.get(k, "")) for k in ("type", "signal", "subtype") if exc.get(k)) or "exception ?")
    term = body.get("termination") or {}
    if term:
        out.append("termination " + " ".join(str(term.get(k, "")) for k in ("indicator", "namespace", "code", "byProc") if term.get(k)))
    for lib, msgs in (body.get("asi") or {}).items():
        for m in (msgs if isinstance(msgs, list) else [msgs]):
            out.append(f"{lib}: {m}")
    images = body.get("usedImages") or []
    threads = body.get("threads") or []
    faulting = body.get("faultingThread", 0)
    if faulting < len(threads):
        t = threads[faulting]
        out.append(f"thread {faulting} {t.get('name') or t.get('queue') or ''} crashed:")
        for j, f in enumerate((t.get("frames") or [])[:32]):
            k = f.get("imageIndex", -1)
            img = images[k].get("name", "?") if 0 <= k < len(images) else "?"
            out.append(f"  {j:2d} {str(img):28s} {f.get('symbol', '')} +{f.get('symbolLocation', f.get('imageOffset', 0))}")
    return out


def frames_summary(lines, hitches=8):
    """The [Frames] lines worth printing from one console: per launch and
    stage, the latest summary — the step's first launch and each relaunch the
    workflow's `again` appended under "==== relaunched with: <args>", which
    labels its lines — and the first `hitches` hitch lines."""
    latest, order, hitch_lines = {}, [], []
    label = ""
    for l in lines:
        if l.startswith("==== relaunched with:"):
            label = l.split(":", 1)[1].strip()
            continue
        if "[Frames]" not in l:
            continue
        m = re.search(r"\[Frames\] (\S+) (.*)", l)
        if not m:
            continue
        text = l[l.index("[Frames]") + 9:].strip()
        if m.group(2).startswith("hitch"):
            hitch_lines.append((label, text))
            continue
        key = (label, m.group(1))
        if key not in latest:
            order.append(key)
        latest[key] = text
    out = []
    for key in order:
        out.append("FRAMES " + (f"({key[0]}) " if key[0] else "") + latest[key])
    for launch, text in hitch_lines[:hitches]:
        out.append("FRAMES " + (f"({launch}) " if launch else "") + text)
    if len(hitch_lines) > hitches:
        out.append(f"FRAMES … {len(hitch_lines) - hitches} more hitch lines")
    return out


def reel_frames(path, every, limit=64):
    """(seconds, PIL image) pairs from the skill reel's video, one every
    `every` seconds, and the video's length in seconds. OpenCV reads it
    front to back when it is installed (a seek lands on the keyframe before
    the time asked for, and the reel's keyframes are two seconds apart);
    otherwise the ffmpeg imageio-ffmpeg ships writes the frames out. Nothing,
    and a length of 0, when neither is here."""
    try:
        import cv2
    except ImportError:
        cv2 = None
    if cv2 is not None:
        capture = cv2.VideoCapture(path)
        if capture.isOpened():
            rate = capture.get(cv2.CAP_PROP_FPS) or 30.0
            picked, index, due = [], 0, 0.0
            while len(picked) < limit:
                ok, frame = capture.read()
                if not ok:
                    break
                seconds = index / rate
                if seconds + 1e-6 >= due:
                    picked.append((seconds, Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))))
                    due += every
                index += 1
            # The length from the frames read, not the container's count,
            # which a variable-rate recording gets wrong.
            while True:
                ok = capture.grab()
                if not ok:
                    break
                index += 1
            capture.release()
            return picked, index / rate
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return [], 0.0
    # The length off ffmpeg's own reading of the file ("Duration: 00:01:14.53").
    probe = subprocess.run([ffmpeg, "-hide_banner", "-i", path], capture_output=True, text=True).stderr
    found = re.search(r"Duration: (\d+):(\d+):([\d.]+)", probe)
    length = int(found.group(1)) * 3600 + int(found.group(2)) * 60 + float(found.group(3)) if found else 0.0
    work = tempfile.mkdtemp(prefix="reel_")
    try:
        subprocess.run([ffmpeg, "-loglevel", "error", "-i", path, "-vf", f"fps=1/{every}",
                        "-frames:v", str(limit), os.path.join(work, "f%04d.png")], check=False)
        shots = sorted(glob.glob(os.path.join(work, "f*.png")))
        picked = [(k * every, Image.open(f).convert("RGB")) for k, f in enumerate(shots)]
        return picked, length or len(shots) * every
    finally:
        shutil.rmtree(work, ignore_errors=True)


def reel_sheet(picked, out, width=480, cols=4):
    """The reel's frames on one sheet, each with its second on the video's
    clock; a portrait frame (the recording as the simulator wrote it) is
    stood up as the stills are."""
    thumbs = []
    for seconds, im in picked:
        if im.height > im.width:
            im = im.rotate(90, expand=True)
        thumbs.append((seconds, im))
    h = int(thumbs[0][1].height * width / thumbs[0][1].width)
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * width, rows * (h + 18)), (10, 10, 16))
    draw = ImageDraw.Draw(sheet)
    for i, (seconds, im) in enumerate(thumbs):
        x, y = (i % cols) * width, (i // cols) * (h + 18)
        sheet.paste(im.resize((width, h)), (x, y + 18))
        draw.text((x + 4, y + 3), f"{seconds:5.1f} s", fill=(255, 230, 120))
    sheet.save(out, quality=82)
    return sheet.size


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="/tmp/ci_frames/ci_sheet.jpg")
    ap.add_argument("--width", type=int, default=640, help="width of one frame on the sheet")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--log-lines", type=int, default=40, help="console lines of interest to print per step")
    ap.add_argument("--reel-every", type=float, default=2.5,
                    help="seconds between the skill reel's frames on its contact sheet")
    ap.add_argument("--no-reel-sheet", action="store_true", help="skip the skill reel's contact sheet")
    a = ap.parse_args()

    out_dir = os.path.dirname(os.path.abspath(a.out))
    frames_dir = os.path.join(out_dir, "frames")
    os.makedirs(frames_dir, exist_ok=True)
    for f in glob.glob(os.path.join(frames_dir, "*")):
        os.remove(f)

    subprocess.run(["git", "-C", REPO, "fetch", "-q", "origin", "ci/screens"], check=True)
    names = subprocess.run(["git", "-C", REPO, "ls-tree", "--name-only", "origin/ci/screens"],
                           capture_output=True, text=True, check=True).stdout.split()
    for n in names:
        data = subprocess.run(["git", "-C", REPO, "show", f"origin/ci/screens:{n}"], capture_output=True, check=True).stdout
        with open(os.path.join(frames_dir, n), "wb") as fh:
            fh.write(data)
    source = os.path.join(frames_dir, "SOURCE.txt")
    if os.path.exists(source):
        print(open(source).read().strip())

    # A red build, first and in full. The GitHub log API serves only the TAIL
    # of a job and a compiler error sits near its top, so reading one used to
    # mean fetching the whole tail — three times over on 2026-09-16. The job
    # publishes the error lines here instead, and they are four lines.
    for name, title in (("build-errors.txt", "BUILD"), ("test-errors.txt", "TESTS")):
        path = os.path.join(frames_dir, name)
        if not os.path.exists(path):
            continue
        body = open(path, errors="replace").read().strip()
        if not body or body == "no compiler errors":
            continue
        print(f"\n== {title} ==")
        for line in body.splitlines()[:40]:
            print("   " + line[:220])
        print()

    # The memory curve (2026-09-24): memory.txt holds every [Mem]/[Crash]
    # line of the tour, prefixed with its step. Printed: the app dying in the
    # stress, every line of the stress step (step 53: thirty singles, three
    # ten-pulls, six auto-repeat runs, a footprint after each), any memory
    # warning or [Crash] line anywhere, and the ten launches that peaked
    # highest — so a climb that never comes back down reads in one screen.
    # A wait that ran out is not a death: a slow simulator stalls every
    # reveal, and the relaunch after it kills the app either way.
    deaths = os.path.join(frames_dir, "stress-deaths.txt")
    if os.path.exists(deaths) and open(deaths, errors="replace").read().strip():
        found = open(deaths, errors="replace").read().splitlines()
        died = [l for l in found if "no stress-done" not in l]
        slow = [l for l in found if "no stress-done" in l]
        if died:
            print("\n== STRESS: THE APP DIED ==")
            for line in died:
                print("   " + line[:220])
        if slow:
            print("\n== STRESS: TIMED OUT (the app was still running) ==")
            for line in slow:
                print("   " + line[:220])
    memory = os.path.join(frames_dir, "memory.txt")
    if os.path.exists(memory):
        lines = open(memory, errors="replace").read().splitlines()
        stress = [l for l in lines if l.split(":", 1)[0].startswith("53-")]
        alarms = [l for l in lines if not l.split(":", 1)[0].startswith("53-")
                  and ("[Crash]" in l or "memory warning" in l or "memory critical" in l)
                  and "[Crash] armed" not in l]
        peaks = {}
        for l in lines:
            m = re.search(r"^(.*?): \[Mem\] .*? footprint (\d+) MB", l)
            if m:
                peaks[m.group(1)] = max(peaks.get(m.group(1), 0), int(m.group(2)))
        print(f"\n== MEMORY ({len(lines)} lines in {memory}) ==")
        for l in alarms[:30]:
            print("   " + l[:220])
        if peaks:
            print("   highest launches: " + ", ".join(f"{k} {v} MB" for k, v in
                                                     sorted(peaks.items(), key=lambda kv: -kv[1])[:10]))
        for l in stress[:160]:
            print("   " + l[:220])
        if len(stress) > 160:
            print(f"   … {len(stress) - 160} more stress lines in {memory}")
        print()

    # When the frames whose moment matters were asked for and landed
    # (build.yml's shoot_timed, 2026-09-24): run 245's victory beats were
    # each photographed a beat late, because a screenshot of a live fight
    # took six to nine seconds to come back.
    times = os.path.join(frames_dir, "shot-times.txt")
    if os.path.exists(times) and open(times, errors="replace").read().strip():
        print("\n== SHOT TIMES ==")
        for line in open(times, errors="replace").read().splitlines()[:40]:
            print("   " + line[:220])
        print()

    # The skill reel (step 54, 2026-09-25): the video's path, size, length
    # and frame size, what the job said making it (skill_reel.txt), and
    # every cast the reel made — each family's name, the skill, the clip it
    # asked for and the clip that played when the family ships no file for
    # it — from the step's console. Its contact sheet is made below.
    reel = next((os.path.join(frames_dir, n) for n in REEL_VIDEOS
                 if os.path.exists(os.path.join(frames_dir, n))), None)
    notes = os.path.join(frames_dir, "skill_reel.txt")
    reel_console = sorted(glob.glob(os.path.join(frames_dir, "*-skill_reel-console.txt")))
    picked, length = [], 0.0
    if reel or os.path.exists(notes) or reel_console:
        print("\n== SKILL REEL ==")
        if reel:
            megabytes = os.path.getsize(reel) / 1_048_576
            if not a.no_reel_sheet:
                picked, length = reel_frames(reel, max(0.2, a.reel_every))
            shape = f", {length:.1f} s, {picked[0][1].width}x{picked[0][1].height}" if picked else ""
            print(f"   {reel}  {megabytes:.1f} MB{shape}")
        else:
            print("   no video on ci/screens")
        if os.path.exists(notes):
            for line in open(notes, errors="replace").read().splitlines()[:30]:
                print("   " + line[:220])
        for log in reel_console:
            for line in open(log, errors="replace").read().splitlines():
                if "[Tour] reel" in line or "[TourCue] reel" in line:
                    print("   " + line[:220])
        print()

    # The job also publishes what the app printed during each step. The lines
    # that decide anything are the loader's and the frameworks' complaints;
    # the rest is there in the file for when they are not enough.
    for log in sorted(glob.glob(os.path.join(frames_dir, "*-console.txt"))):
        lines = open(log, errors="replace").read().splitlines()
        wanted = [l for l in lines if "[ModelLibrary]" in l or "[Diagnostics]" in l
                  or any(k in l for k in ("rror", "SCNMetal", "shader", "Shader", "compile", "fatal", "Fatal"))]
        # The pose lab's yaw lines and verdict ([PoseLab], step 3's
        # -tour-pose-lab relaunches) and the island's restarted idles
        # ("[Idle] … restarted", step 0's -tour-island-rebuild), every one,
        # ahead of the capped list, which the loader's lines fill long before
        # a relaunch. The other [Idle] lines (a loop handed over) stay in the
        # console file: a battle prints a dozen a launch.
        # The gaze's line ([Gaze], steps 3 and 21's -tour-gaze relaunches and
        # every figure stage: the turn its block laid on) likewise.
        lab = [l for l in lines if "[PoseLab]" in l or "[Gaze]" in l or ("[Idle]" in l and "restarted" in l)]
        print(f"-- {os.path.basename(log)}: {len(lines)} lines, {len(wanted)} of interest")
        # The step's frame pacing beside it (Docs/FEEL.md W2.26): each
        # stage's latest [Frames] line — the governor prints one every three
        # seconds of drawing under the tour and one as a stage goes, so the
        # last before a relaunch is the nearest to its photographs — and
        # every hitch line, a single frame over 100 ms with when it came.
        for l in frames_summary(lines):
            print("   " + l[:220])
        for l in lab:
            print("   " + l[:220])
        for l in wanted[:a.log_lines]:
            print("   " + l[:220])
        if len(wanted) > a.log_lines:
            print(f"   … {len(wanted) - a.log_lines} more in {log}")
    # A crash report is the one file that says why a step's frames are the
    # home screen; the job copies every one written during the tour.
    for crash in sorted(glob.glob(os.path.join(frames_dir, "crash-*.txt"))):
        print(f"-- {os.path.basename(crash)}")
        for l in crash_summary(crash):
            print("   " + l[:220])

    # The reel's contact sheet, beside the frames' sheet: a video cannot be
    # looked at in this session, and a still of a cast cannot show whether
    # the body struck as many times as the numbers landed.
    if picked:
        reel_out = os.path.join(out_dir, "reel_sheet.jpg")
        size = reel_sheet(picked, reel_out)
        print(f"{len(picked)} reel frames, one every {a.reel_every:g} s -> {reel_out}  {size[0]}x{size[1]}")
    elif reel and not a.no_reel_sheet:
        print("no reel sheet: neither OpenCV nor an ffmpeg could read the video "
              "(pip install opencv-python-headless, or imageio-ffmpeg)")

    files = sorted(f for f in glob.glob(os.path.join(frames_dir, "*")) if f.lower().endswith((".jpg", ".png")))
    if not files:
        # A build that never produced an app publishes its errors and nothing
        # else, which is not a failure of this tool: they are printed above.
        print("no frames on ci/screens — the build did not produce an app")
        return 0
    thumbs = []
    for f in files:
        im = Image.open(f).convert("RGB")
        if im.height > im.width:
            im = im.rotate(90, expand=True)
        thumbs.append((os.path.basename(f), im))
    w = a.width
    h = int(thumbs[0][1].height * w / thumbs[0][1].width)
    rows = (len(thumbs) + a.cols - 1) // a.cols
    sheet = Image.new("RGB", (a.cols * w, rows * (h + 18)), (10, 10, 16))
    draw = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(thumbs):
        x, y = (i % a.cols) * w, (i // a.cols) * (h + 18)
        sheet.paste(im.resize((w, h)), (x, y + 18))
        draw.text((x + 4, y + 3), name, fill=(255, 230, 120))
    sheet.save(a.out, quality=80)
    print(f"{len(thumbs)} frames -> {a.out}  {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
