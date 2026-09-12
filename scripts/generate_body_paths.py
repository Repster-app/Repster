#!/usr/bin/env python3
"""Generate Repster/Features/Insights/Views/BodyMapPaths.swift from the body-highlighter path data.

Source: react-native-body-highlighter 3.2.0 (MIT, Copyright (c) 2022 ELABBASSI Hicham),
extracted to scripts/body-map/body-highlighter-3.2.0.json; licence in scripts/body-map/LICENSE.

Every SVG path is normalised to absolute M / L / C / Q / Z commands — relative commands,
shorthand curves and elliptical arcs (including packed arc flags such as `a5 5 0 013 4`) are
resolved here — so the app needs only a tiny parser (`BodyMapGeometry.path(from:)`).

Run from anywhere:  python3 scripts/generate_body_paths.py
"""
import json
import math
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts/body-map/body-highlighter-3.2.0.json"
LICENSE = ROOT / "scripts/body-map/LICENSE"
OUT = ROOT / "Repster/Features/Insights/Views/BodyMapPaths.swift"
TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def arc_to_cubics(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """SVG elliptical arc -> cubic Béziers (SVG 1.1 appendix F.6)."""
    if (x1, y1) == (x2, y2):
        return []
    if rx == 0 or ry == 0:
        return [("L", x2, y2)]
    rx, ry = abs(rx), abs(ry)
    cp, sp = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    coef = math.sqrt(max(0.0, num / den)) if den else 0.0
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * y1p / ry, -coef * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def angle(ux, uy, vx, vy):
        return math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    t = angle(1, 0, ux, uy)
    dt = angle(ux, uy, vx, vy)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, int(math.ceil(abs(dt) / (math.pi / 2) - 1e-9)))
    seg = dt / n
    k = 4 / 3 * math.tan(seg / 4)

    def on_ellipse(px, py):
        return cx + rx * px * cp - ry * py * sp, cy + rx * px * sp + ry * py * cp

    out = []
    for _ in range(n):
        c1, s1 = math.cos(t), math.sin(t)
        c2, s2 = math.cos(t + seg), math.sin(t + seg)
        a = on_ellipse(c1 - k * s1, s1 + k * c1)
        b = on_ellipse(c2 + k * s2, s2 - k * c2)
        e = on_ellipse(c2, s2)
        out.append(("C", a[0], a[1], b[0], b[1], e[0], e[1]))
        t += seg
    return out


def normalize(d):
    toks = TOKEN.findall(d)
    i = 0
    cmd = None
    cx = cy = sx = sy = 0.0
    last_c = last_q = None
    out = []

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flag():
        # Arc flags are single digits and may be packed against what follows ("013", "01.5").
        nonlocal i
        t = toks[i]
        if len(t) > 1 and t[0] in "01":
            toks[i] = t[1:]
            return int(t[0])
        i += 1
        return int(float(t))

    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd in "Zz":
                out.append(("Z",))
                cx, cy = sx, sy
                last_c = last_q = None
                continue
        elif cmd is None:
            raise ValueError("path data starts with a number")
        rel = cmd.islower()
        c = cmd.upper()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if c == "M":
            x, y = num() + ox, num() + oy
            out.append(("M", x, y))
            cx, cy = sx, sy = x, y
            cmd = "l" if rel else "L"
            last_c = last_q = None
        elif c == "L":
            x, y = num() + ox, num() + oy
            out.append(("L", x, y))
            cx, cy = x, y
            last_c = last_q = None
        elif c == "H":
            cx = num() + (cx if rel else 0.0)
            out.append(("L", cx, cy))
            last_c = last_q = None
        elif c == "V":
            cy = num() + (cy if rel else 0.0)
            out.append(("L", cx, cy))
            last_c = last_q = None
        elif c == "C":
            x1, y1, x2, y2, x, y = num() + ox, num() + oy, num() + ox, num() + oy, num() + ox, num() + oy
            out.append(("C", x1, y1, x2, y2, x, y))
            last_c, last_q, cx, cy = (x2, y2), None, x, y
        elif c == "S":
            x1, y1 = (2 * cx - last_c[0], 2 * cy - last_c[1]) if last_c else (cx, cy)
            x2, y2, x, y = num() + ox, num() + oy, num() + ox, num() + oy
            out.append(("C", x1, y1, x2, y2, x, y))
            last_c, last_q, cx, cy = (x2, y2), None, x, y
        elif c == "Q":
            x1, y1, x, y = num() + ox, num() + oy, num() + ox, num() + oy
            out.append(("Q", x1, y1, x, y))
            last_q, last_c, cx, cy = (x1, y1), None, x, y
        elif c == "T":
            x1, y1 = (2 * cx - last_q[0], 2 * cy - last_q[1]) if last_q else (cx, cy)
            x, y = num() + ox, num() + oy
            out.append(("Q", x1, y1, x, y))
            last_q, last_c, cx, cy = (x1, y1), None, x, y
        elif c == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = flag(), flag()
            x, y = num() + ox, num() + oy
            out.extend(arc_to_cubics(cx, cy, rx, ry, phi, large, sweep, x, y))
            cx, cy = x, y
            last_c = last_q = None
    return out


def fmt(v):
    s = f"{v:.1f}"
    if s.endswith(".0"):
        s = s[:-2]
    return "0" if s in ("-0", "-0.0") else s


def to_d(segments):
    return " ".join(" ".join([seg[0]] + [fmt(v) for v in seg[1:]]) for seg in segments)


def bbox(segments, pad=6.0):
    xs = [v for seg in segments for v in seg[1::2]]
    ys = [v for seg in segments for v in seg[2::2]]
    return min(xs) - pad, min(ys) - pad, max(xs) - min(xs) + 2 * pad, max(ys) - min(ys) + 2 * pad


def main():
    data = json.loads(SRC.read_text())
    licence = "\n".join(("// " + line).rstrip() for line in LICENSE.read_text().strip().splitlines())
    out = [
        "// BodyMapPaths.swift",
        "// GENERATED by scripts/generate_body_paths.py — do not edit by hand.",
        "//",
        "// Body artwork: react-native-body-highlighter 3.2.0",
        "// https://github.com/HichamELBSI/react-native-body-highlighter",
        "//",
        licence,
        "//",
        "// Paths are absolute M / L / C / Q / Z commands, so `BodyMapGeometry.path(from:)` is the",
        "// whole parser. `side` is the LIBRARY's — the viewer's left, in both views. Never read it",
        "// directly: go through `BodyMapGeometry.anatomicalSide(forLibrarySide:in:)`.",
        "",
        "import CoreGraphics",
        "",
        "struct BodyMapRawPath {",
        "    let region: String",
        "    /// \"left\", \"right\" or \"common\" — the viewer's side, in both views.",
        "    let side: String",
        "    let d: String",
        "}",
        "",
        "enum BodyMapPaths {",
    ]
    for view in ("front", "back"):
        outline = normalize(data["outline"][view])
        everything = list(outline)
        for sides in data[view].values():
            for paths in sides.values():
                for d in paths:
                    everything.extend(normalize(d))
        x, y, w, h = bbox(everything)
        out.append(f"    static let {view}ViewBox = CGRect(x: {fmt(x)}, y: {fmt(y)}, width: {fmt(w)}, height: {fmt(h)})")
        out.append(f"    static let {view}Outline = \"{to_d(outline)}\"")
    for view in ("front", "back"):
        out.append("")
        out.append(f"    static let {view}: [BodyMapRawPath] = [")
        count = 0
        for region, sides in data[view].items():
            for side, paths in sides.items():
                for d in paths:
                    out.append(f"        BodyMapRawPath(region: \"{region}\", side: \"{side}\", d: \"{to_d(normalize(d))}\"),")
                    count += 1
        out.append("    ]")
        print(view, count, "paths")
    out.append("}")
    OUT.write_text("\n".join(out) + "\n")
    print("wrote", OUT.relative_to(ROOT), OUT.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
