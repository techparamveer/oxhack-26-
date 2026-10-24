"""Generate Sheep/Views/Sheep/SheepVectorArt.swift from the three SVGs (run: python3 -I Tools/gen_sheepart.py)."""
import re, sys, xml.etree.ElementTree as ET
sys.path.insert(0, "/Users/paramveer/.t3/worktrees/oxhack-26-sheep/feat-sheep-animations/.build/tools")
ROOT = "/Users/paramveer/.t3/worktrees/oxhack-26-sheep/feat-sheep-animations/"
SVG = ROOT + "Sheep/Assets.xcassets/Sheep/"

def tokens(d): return re.findall(r"[MmZzLlHhVvCcSsQqTtAa]|-?\d*\.?\d+(?:e-?\d+)?", d)
def f(v): return "0" if abs(v) < 1e-9 else f"{v:.3f}".rstrip('0').rstrip('.')

def path_code(d):
    toks = tokens(d); i = 0; cmd = None
    x = y = sx = sy = 0.0; cx2 = cy2 = None; out = []
    def num():
        nonlocal i
        v = float(toks[i]); i += 1; return v
    while i < len(toks):
        if re.match(r"[A-Za-z]", toks[i]):
            cmd = toks[i]; i += 1
            if cmd in "Zz":
                out.append("p.closeSubpath()"); x, y = sx, sy; cx2 = cy2 = None; continue
        rel = cmd.islower(); c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            if rel: nx += x; ny += y
            x, y = nx, ny; sx, sy = x, y
            out.append(f"p.move(to: CGPoint(x: {f(x)}, y: {f(y)}))"); cmd = "l" if rel else "L"; cx2 = cy2 = None
        elif c == "L":
            nx, ny = num(), num()
            if rel: nx += x; ny += y
            x, y = nx, ny; out.append(f"p.addLine(to: CGPoint(x: {f(x)}, y: {f(y)}))"); cx2 = cy2 = None
        elif c == "H":
            nx = num(); x = nx + x if rel else nx; out.append(f"p.addLine(to: CGPoint(x: {f(x)}, y: {f(y)}))"); cx2 = cy2 = None
        elif c == "V":
            ny = num(); y = ny + y if rel else ny; out.append(f"p.addLine(to: CGPoint(x: {f(x)}, y: {f(y)}))"); cx2 = cy2 = None
        elif c in "CS":
            if c == "C":
                x1, y1, x2, y2, nx, ny = [num() for _ in range(6)]
                if rel: x1 += x; y1 += y; x2 += x; y2 += y; nx += x; ny += y
            else:
                x2, y2, nx, ny = [num() for _ in range(4)]
                if rel: x2 += x; y2 += y; nx += x; ny += y
                x1, y1 = (2*x - cx2, 2*y - cy2) if cx2 is not None else (x, y)
            out.append(f"p.addCurve(to: CGPoint(x: {f(nx)}, y: {f(ny)}), control1: CGPoint(x: {f(x1)}, y: {f(y1)}), control2: CGPoint(x: {f(x2)}, y: {f(y2)}))")
            cx2, cy2 = x2, y2; x, y = nx, ny
        else: raise SystemExit(f"unsupported {cmd}")
    return out

# Hand-assigned animation groups per SVG element index (document order).
GROUPS = {
  "awake": {**{i: "legs" for i in range(0, 12)}, **{i: "body" for i in range(12, 16)},
            16: "earLeft", 17: "earRight", 18: "head", **{i: "eyes" for i in range(19, 23)},
            **{i: "head" for i in range(23, 33)}},
  "focus": {0: "body", 1: "legs", 2: "legs", 3: "body", 4: "book", 5: "book", 6: "pages",
            7: "hooves", 8: "hooves", 9: "legs", 10: "legs", 11: "pages", 12: "pages",
            13: "earLeft", 14: "earRight", 15: "head", **{i: "eyes" for i in range(16, 20)}, 20: "head"},
  "rest":  {0: "ground", **{i: "legs" for i in range(1, 5)}, 5: "body", 6: "head", 7: "earLeft", 8: "earRight",
            9: "eyes", 10: "eyes", 11: "head", **{i: "legs" for i in range(12, 16)}},
}

out = ["import SwiftUI", "",
       "// GENERATED from Sheep/Assets.xcassets/Sheep/sheep-{awake,focus,rest}.imageset/*.svg by Tools/gen_sheepart.py.",
       "// Paths are in SVG viewBox units; colours are the exact SVG fills. Do not hand-edit — regenerate.",
       "",
       "enum SheepVectorArt {"]
for name in ["awake", "focus", "rest"]:
    root = ET.parse(SVG + f"sheep-{name}.imageset/sheep-{name}.svg").getroot()
    vb = [float(v) for v in root.get("viewBox").split()]
    T = name.capitalize()
    out.append(f"    enum {T} {{")
    out.append(f"        static let viewBox = CGRect(x: {f(vb[0])}, y: {f(vb[1])}, width: {f(vb[2])}, height: {f(vb[3])})")
    parts = []
    for idx, el in enumerate(root):
        tag = el.tag.split('}')[1]
        m = re.search(r"opacity:\s*([\d.]+)", el.get("style", "")); op = m.group(1) if m else "1"
        fill = el.get("fill"); stroke = el.get("stroke"); group = GROUPS[name][idx]
        if tag == "path":
            body = "\n".join("            " + l for l in path_code(el.get("d")))
            out.append(f"        private static func p{idx}() -> Path {{\n            var p = Path()\n{body}\n            return p\n        }}")
            if fill and fill != "none":
                parts.append(f"            SheepPart(group: .{group}, path: p{idx}(), fill: 0x{fill[1:]}, opacity: {op}),")
            else:
                parts.append(f"            SheepPart(group: .{group}, path: p{idx}(), stroke: 0x{stroke[1:]}, lineWidth: {el.get('stroke-width')}, opacity: {op}),")
        else:
            cx, cy = float(el.get("cx")), float(el.get("cy"))
            rx = float(el.get("rx") or el.get("r")); ry = float(el.get("ry") or el.get("r"))
            t = el.get("transform"); rot = float(re.search(r"rotate\(([-\d.]+)", t).group(1)) if t else 0.0
            parts.append(f"            SheepPart(group: .{group}, path: SheepPart.ellipse(cx: {f(cx)}, cy: {f(cy)}, rx: {f(rx)}, ry: {f(ry)}, rotation: {f(rot)}), fill: 0x{fill[1:]}, opacity: {op}),")
    out.append("        static let parts: [SheepPart] = [")
    out += parts
    out.append("        ]")
    out.append("    }")
out.append("}")
open(ROOT + "Sheep/Views/Sheep/SheepVectorArt.swift", "w").write("\n".join(out) + "\n")
print("wrote", len(out), "lines")
