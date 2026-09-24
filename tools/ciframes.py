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
matter from each — the [ModelLibrary] block and anything that says error or
shader — and leaves the files in frames/.

The job (.github/workflows/build.yml) launches the app in a simulator once per
screen with `-tour -tour-step N`, photographs it, and force-pushes small JPEGs
of the frames to the orphan branch `ci/screens`, which this fetches. The
artifact store keeps the full-size PNGs, but it lives on a host the session's
network policy refuses; the branch does not.

The simulator captures a landscape-only app in a portrait framebuffer, so a
frame taller than it is wide is stood up here.
"""
import argparse, glob, json, os, re, subprocess, sys

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="/tmp/ci_frames/ci_sheet.jpg")
    ap.add_argument("--width", type=int, default=640, help="width of one frame on the sheet")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--log-lines", type=int, default=40, help="console lines of interest to print per step")
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

    # The job also publishes what the app printed during each step. The lines
    # that decide anything are the loader's and the frameworks' complaints;
    # the rest is there in the file for when they are not enough.
    for log in sorted(glob.glob(os.path.join(frames_dir, "*-console.txt"))):
        lines = open(log, errors="replace").read().splitlines()
        wanted = [l for l in lines if "[ModelLibrary]" in l or "[Diagnostics]" in l
                  or any(k in l for k in ("rror", "SCNMetal", "shader", "Shader", "compile", "fatal", "Fatal"))]
        print(f"-- {os.path.basename(log)}: {len(lines)} lines, {len(wanted)} of interest")
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
