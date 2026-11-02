"""Screenshots of the demo build on many watches, plus the sheets for the README.

    python tools/screens.py                  one watch per screen size (default)
    python tools/screens.py --fonts          one watch per screen size + font set
    python tools/screens.py --all            every watch in manifest.xml
    python tools/screens.py fr55 fr965       just these
    python tools/screens.py --sheet-only     rebuild the sheets from the last captures

Writes docs/screens/v<APP_VERSION>/:
    devices.png     one row per watch, one column per screen (dark background)
    watches.png     main screen on every watch, side by side (transparent)
    all.png         every screen on the FR955, plus 1_prestart.png ... 9_done.png (transparent)

Only the screen is grabbed from the simulator; it's then put into the watch picture
that ships with the SDK (Devices/<id>/, named in simulator.json), so every shot is the whole watch
with strap, clean edges and no window behind it.
Raw screen captures are kept in bin/screens/<device>/ so the sheets can be rebuilt.
The demo picks its step from the wall clock (see demo/DemoApp.mc), so each
screen is captured in the middle of its 4 s slot. Windows only (PrintWindow).
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CIQ = Path(os.environ["APPDATA"]) / "Garmin" / "ConnectIQ"
SDK = sorted((CIQ / "Sdks").iterdir())[-1]
DEVICES = CIQ / "Devices"
KEY = Path(os.environ["USERPROFILE"]) / ".garmin-keys" / "developer_key.der"
RAW = ROOT / "bin" / "screens"
MAIN_DEVICE = "fr955"

STEP_SECONDS, STEPS = 4, 9
# demo step -> file name, in the order they appear in all.png
SCREENS = {0: "prestart", 1: "main", 2: "body", 3: "splits", 4: "split_popup",
           8: "race_menu_undo", 7: "finish_leg", 5: "paused", 6: "done"}
# columns of devices.png (own screens only, no system menu)
SHEET = [(0, "Start"), (1, "Leg"), (2, "Body"), (3, "Splits"), (4, "Punch"), (5, "Paused"), (6, "Done")]

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
user32.SetProcessDPIAware()


# --- devices ---

def manifest_devices():
    return re.findall(r'<iq:product id="([^"]+)"', (ROOT / "manifest.xml").read_text(encoding="utf8"))


def device_info(dev):
    c = json.loads((DEVICES / dev / "compiler.json").read_text(encoding="utf8"))
    s = json.loads((DEVICES / dev / "simulator.json").read_text(encoding="utf8"))
    fonts = next(f["fonts"] for f in s["fonts"] if f["fontSet"] == "ww")
    return {
        "id": dev,
        "name": c["displayName"].replace("®", "").replace("™", ""),
        "size": c["resolution"]["width"],
        "bpp": c["bitsPerPixel"],
        "fonts": tuple((f.get("filename"), round(f.get("size", 0), 1)) for f in fonts),
        "loc": s["display"]["location"],
        "image": DEVICES / dev / s.get("image", f"{dev}.png"),  # newer devices: device.png
    }


def pick(devices, by_fonts):
    """One device per group; the FR955 always represents its own group."""
    groups = {}
    for d in devices:
        i = device_info(d)
        key = (i["size"], i["bpp"]) + ((i["fonts"],) if by_fonts else ())
        groups.setdefault(key, []).append(d)
    out = []
    for members in groups.values():
        lead = MAIN_DEVICE if MAIN_DEVICE in members else members[0]
        out.append((lead, [m for m in members if m != lead]))
    out.sort(key=lambda g: (device_info(g[0])["size"], g[0]))
    return out


# --- build + simulator ---

def version():
    m = re.search(r'APP_VERSION\s*=\s*"([^"]+)"', (ROOT / "source" / "Version.mc").read_text(encoding="utf8"))
    return m.group(1)


def build(dev):
    prg = ROOT / "bin" / f"Demo_{dev}.prg"
    r = subprocess.run([str(SDK / "bin" / "monkeyc.bat"), "-f", "demo.jungle", "-o", str(prg), "-y", str(KEY),
                        "-d", dev, "-w", "-l", "2"], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"build failed for {dev}:\n{r.stdout}{r.stderr}")
    return prg


def simulator_window():
    found = []
    proto = ctypes.WINFUNCTYPE(ctypes.c_bool, wt.HWND, wt.LPARAM)

    def cb(h, _):
        n = user32.GetWindowTextLengthW(h)
        buf = ctypes.create_unicode_buffer(n + 1)
        user32.GetWindowTextW(h, buf, n + 1)
        if buf.value.startswith("CIQ Simulator") and user32.IsWindowVisible(h):
            found.append((h, buf.value))
        return True

    user32.EnumWindows(proto(cb), 0)
    return found[0] if found else (None, "")


def ensure_simulator():
    if simulator_window()[0]:
        return
    subprocess.Popen([str(SDK / "bin" / "simulator.exe")], creationflags=subprocess.DETACHED_PROCESS)
    for _ in range(40):
        time.sleep(0.5)
        if simulator_window()[0]:
            time.sleep(2)
            return
    sys.exit("simulator did not start")


def launch(dev, prg):
    subprocess.Popen([str(SDK / "bin" / "monkeydo.bat"), str(prg), dev], cwd=ROOT,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     creationflags=subprocess.CREATE_NO_WINDOW)


class RECT(ctypes.Structure):
    _fields_ = [("l", ctypes.c_long), ("t", ctypes.c_long), ("r", ctypes.c_long), ("b", ctypes.c_long)]


def grab(h):
    """Whole simulator window via PrintWindow (works when it's behind other windows)."""
    if user32.IsIconic(h):
        user32.ShowWindow(h, 4)  # restore without activating
        time.sleep(1)
    rc = RECT()
    user32.GetWindowRect(h, ctypes.byref(rc))
    w, hgt = rc.r - rc.l, rc.b - rc.t
    wdc = user32.GetWindowDC(h)
    mdc = gdi32.CreateCompatibleDC(wdc)
    bmp = gdi32.CreateCompatibleBitmap(wdc, w, hgt)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(h, mdc, 2)
    buf = ctypes.create_string_buffer(w * hgt * 4)
    gdi32.GetBitmapBits(bmp, len(buf), buf)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(h, wdc)
    img = Image.frombuffer("RGBA", (w, hgt), buf, "raw", "BGRA", 0, 1).convert("RGB")
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(h, ctypes.byref(pt))
    return img, (pt.x - rc.l, pt.y - rc.t)  # image + client origin inside it


def device_origin(dev, img, client):
    """Where the device picture sits in the window: match its top strip near the client origin."""
    ref = np.asarray(Image.open(device_info(dev)["image"]).convert("RGB"), dtype=np.int16)[:80]
    a = np.asarray(img, dtype=np.int16)
    rh, rw = ref.shape[:2]
    best = None
    for dy in range(max(0, client[1] - 40), client[1] + 20):
        for dx in range(max(0, client[0] - 20), client[0] + 20):
            sub = a[dy:dy + rh, dx:dx + rw]
            if sub.shape[:2] != (rh, rw):
                continue
            e = np.abs(sub - ref).mean()
            if best is None or e < best[0]:
                best = (e, dx, dy)
    return (best[1], best[2]) if best else client


def screen_box(info, origin, pad=0.0):
    loc = info["loc"]
    ox, oy = origin
    px, py = int(loc["width"] * pad), int(loc["height"] * pad)
    return (ox + loc["x"] - px, oy + loc["y"] - py, ox + loc["x"] + loc["width"] + px, oy + loc["y"] + loc["height"] + py)


def app_running(h, info):
    img, origin = grab(h)
    scr = img.crop(screen_box(info, origin))
    return scr.convert("L").getextrema()[1] > 60  # something bright drawn on the screen


def capture(dev):
    info = device_info(dev)
    prg = build(dev)
    ensure_simulator()
    for attempt in range(3):  # the first launch after a simulator start often stalls
        launch(dev, prg)
        deadline = time.time() + 30
        while time.time() < deadline:
            time.sleep(1)
            h, title = simulator_window()
            if h and info["name"].split(" / ")[0] in title.replace("®", "").replace("™", "") and app_running(h, info):
                break
        else:
            print(f"  {dev}: no app on screen, retrying")
            continue
        break
    else:
        sys.exit(f"{dev}: app never showed up in the simulator")

    out = RAW / dev
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    time.sleep(1)
    img, client = grab(simulator_window()[0])
    origin = device_origin(dev, img, client)
    done = set()
    slot = int(time.time() // STEP_SECONDS) + 1
    give_up = slot + 3 * STEPS
    while len(done) < STEPS and slot < give_up:
        time.sleep(max(0, slot * STEP_SECONDS + STEP_SECONDS / 2 - time.time()))  # middle of the slot
        slot = int(time.time() // STEP_SECONDS)  # the step that is really on screen now
        step = slot % STEPS
        if step not in done:
            img, _ = grab(simulator_window()[0])
            img.crop(screen_box(info, origin)).save(out / f"screen_{step}.png")
            done.add(step)
        slot += 1
    if len(done) < STEPS:
        sys.exit(f"{dev}: missed steps {sorted(set(range(STEPS)) - done)}")
    print(f"  {dev}: ok")


# --- watch images ---

def watch_image(dev, screen_png):
    """The screen capture inside Garmin's own picture of the watch, background cut out (RGBA)."""
    info = device_info(dev)
    body = Image.open(info["image"]).convert("RGBA")
    loc = info["loc"]
    comp = Image.new("RGBA", body.size, (0, 0, 0, 255))
    scr = Image.open(screen_png).convert("RGB").resize((loc["width"], loc["height"]), Image.LANCZOS)
    comp.paste(scr, (loc["x"], loc["y"]))
    comp.alpha_composite(body)

    # the device pictures sit on opaque white: flood it from the corners and make it transparent
    before = comp.convert("RGB")
    probe = before.copy()
    key = (255, 0, 254)
    w, h = probe.size
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if probe.getpixel(seed) != key:
            ImageDraw.floodfill(probe, seed, key, thresh=40)
    bg = np.any(np.asarray(probe) != np.asarray(before), axis=2)  # what the fill touched, not the app's magenta
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))  # no white fringe
    comp.putalpha(alpha)
    return comp.crop(comp.getbbox())


def with_shadow(img, blur=10, offset=6, strength=110):
    pad = blur * 3
    out = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad + offset), (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 255))
    shadow.putalpha(img.getchannel("A").point(lambda v: v * strength // 255))
    out.alpha_composite(shadow, (pad, pad + offset))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(img, (pad, pad))
    return out


def fit(img, height):
    return img.resize((round(img.width * height / img.height), height), Image.LANCZOS)


# --- sheets ---

def font(size, bold=False):
    for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def devices_sheet(groups, dest, watch_h=330):
    """One row per watch, the whole watch for each screen. Same height for every watch so rows line up."""
    gap, label_w, head_h = 8, 300, 52
    bg, fg, dim = (24, 24, 27), (235, 235, 235), (140, 140, 148)
    rows = []
    for lead, others in groups:
        tiles = [with_shadow(fit(watch_image(lead, RAW / lead / f"screen_{s}.png"), watch_h), blur=8, offset=5)
                 for s, _ in SHEET]
        rows.append((lead, others, tiles))
    col_w = max(t.width for _, _, ts in rows for t in ts)
    row_h = max(t.height for _, _, ts in rows for t in ts)
    sheet = Image.new("RGBA", (label_w + len(SHEET) * (col_w + gap) + gap, head_h + len(rows) * row_h + gap), bg)
    d = ImageDraw.Draw(sheet)
    for c, (_, title) in enumerate(SHEET):
        d.text((label_w + c * (col_w + gap) + col_w // 2, head_h // 2 + 6), title, font=font(22, True), fill=dim, anchor="mm")
    for r, (lead, others, tiles) in enumerate(rows):
        info = device_info(lead)
        y = head_h + r * row_h
        cy = y + row_h // 2
        name, f = info["name"].split(" / ")[0], font(23, True)
        while d.textlength(name, font=f) > label_w - 40:  # keep it out of the first column
            name = name[:-2].rstrip() + "…"
        d.text((28, cy - 28), name, font=f, fill=fg, anchor="lm")
        sub = f"{info['size']}×{info['size']}" + ("  ·  8 colours" if info["bpp"] <= 4 else "")
        d.text((28, cy + 2), sub, font=font(18), fill=dim, anchor="lm")
        if others:
            d.text((28, cy + 28), f"+ {len(others)} similar", font=font(18), fill=dim, anchor="lm")
        for c, t in enumerate(tiles):
            sheet.alpha_composite(t, (label_w + c * (col_w + gap) + (col_w - t.width) // 2, y + (row_h - t.height) // 2))
    sheet.convert("RGB").save(dest, optimize=True)


def main_sheet(dest_dir):
    """Every screen on the main watch: 1_prestart.png ... and all.png, transparent so they suit light and dark pages."""
    src = RAW / MAIN_DEVICE
    if not all((src / f"screen_{s}.png").exists() for s in SCREENS):
        print(f"no full {MAIN_DEVICE} captures, skipping all.png")
        return
    files = []
    for n, (step, name) in enumerate(SCREENS.items(), 1):
        img = watch_image(MAIN_DEVICE, src / f"screen_{step}.png")
        img.save(dest_dir / f"{n}_{name}.png", optimize=True)
        files.append(with_shadow(img))
    tw, th = files[0].size
    cols = 5
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * tw, rows * th), (0, 0, 0, 0))
    for i, img in enumerate(files):
        r, c = divmod(i, cols)
        left = (cols - min(cols, len(files) - r * cols)) * tw // 2  # centre a short last row
        sheet.alpha_composite(img, (left + c * tw, r * th))
    sheet.save(dest_dir / "all.png", optimize=True)


def lineup_sheet(groups, dest, step=1, watch_h=380, per_row=9):
    """One screen on every watch, side by side with the name underneath. Transparent, grey text
    so it reads on light and dark pages."""
    dim = (128, 128, 136)
    tiles = []
    for lead, _ in groups:
        info = device_info(lead)
        img = with_shadow(fit(watch_image(lead, RAW / lead / f"screen_{step}.png"), watch_h), blur=8, offset=5)
        name = info["name"].split(" / ")[0].replace("Forerunner", "FR")
        tiles.append((img, name, f"{info['size']} px"))
    col_w = max(t.width for t, _, _ in tiles)
    tile_h = max(t.height for t, _, _ in tiles)
    row_h = tile_h + 64
    cols = min(per_row, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * col_w, rows * row_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for i, (img, name, sub) in enumerate(tiles):
        r, c = divmod(i, cols)
        left = (cols - min(cols, len(tiles) - r * cols)) * col_w // 2
        x, y = left + c * col_w, r * row_h
        sheet.alpha_composite(img, (x + (col_w - img.width) // 2, y + tile_h - img.height))
        d.text((x + col_w // 2, y + tile_h + 8), name, font=font(24, True), fill=dim, anchor="mt")
        d.text((x + col_w // 2, y + tile_h + 38), sub, font=font(20), fill=dim, anchor="mt")
    sheet.save(dest, optimize=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("devices", nargs="*")
    ap.add_argument("--all", action="store_true", help="every watch in manifest.xml")
    ap.add_argument("--fonts", action="store_true", help="group by screen size and font set")
    ap.add_argument("--sheet-only", action="store_true", help="don't capture, rebuild sheets")
    a = ap.parse_args()

    known = manifest_devices()
    if a.devices:
        bad = [d for d in a.devices if d not in known]
        if bad:
            sys.exit(f"not in manifest.xml: {' '.join(bad)}")
        groups = [(d, []) for d in a.devices]
    elif a.all:
        groups = [(d, []) for d in known]
    else:
        groups = pick(known, a.fonts)

    if not a.sheet_only:
        print(f"capturing {len(groups)} watches (~1 min each)")
        for lead, _ in groups:
            capture(lead)

    dest = ROOT / "docs" / "screens" / f"v{version()}"
    dest.mkdir(parents=True, exist_ok=True)
    captured = [g for g in groups if all((RAW / g[0] / f"screen_{s}.png").exists() for s in range(STEPS))]
    devices_sheet(captured, dest / "devices.png")
    lineup_sheet(captured, dest / "watches.png")
    main_sheet(dest)
    print(f"sheets in {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
