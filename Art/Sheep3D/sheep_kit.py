"""Procedural 3D sheep matching the Paper "Sheep App" hero art.

Run inside Blender (MCP execute_code, or `Blender -b -P build_all.py`).
Poses: awake (standing, no mode), focus (sitting, reading), rest (lying, asleep),
play (sitting, holding a controller). Every pose has a 96-frame looping idle.
"""
import bpy, bmesh, math, random
from mathutils import Vector, Matrix, Euler

LOOP = 96          # frames per loop (24 fps → 4 s)
END = LOOP + 1     # last key == first key so the loop is seamless

PALETTE = {
    "wool": "#F6F5F3", "face": "#E6E3E1", "ear": "#CCC7C2", "leg": "#DEDBD9",
    "hoof": "#E9AB22", "eye": "#272727", "shine": "#FFFFFF", "nose": "#D96411",
    "cover": "#8F9C89", "page": "#F0E9D6", "pad": "#3A3A3C", "padkey": "#5B5B5E",
    "btn_a": "#E9AB22", "btn_b": "#D96411", "btn_c": "#7D8A78", "btn_d": "#4A5BD4",
    "fog": "#ECEDEB", "zzz": "#B8B4B2",
}


def lin(hexc):
    h = hexc.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    f = lambda x: x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (*[f(x) for x in c], 1.0)


def mat(key, rough=0.85, emit=0.0, sheen=0.0):
    name = "Sheep_" + key
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    col = lin(PALETTE[key])
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    for k, v in (("Specular IOR Level", 0.25), ("Sheen Weight", sheen)):
        try:
            b.inputs[k].default_value = v
        except Exception:
            pass
    if emit:
        b.inputs["Emission Color"].default_value = col
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = col
    return m


def R(rot):
    return Euler([math.radians(a) for a in rot]).to_matrix().to_4x4()


class MB:
    """Accumulates primitives into one mesh with per-part materials."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def _tag(self, before, m, smooth=True):
        if m not in self.mats:
            self.mats.append(m)
        i = self.mats.index(m)
        for f in self.bm.faces:
            if f not in before:
                f.material_index = i
                f.smooth = smooth

    def sphere(self, c, r, m, rot=(0, 0, 0), segs=28, rings=16):
        before = set(self.bm.faces)
        r = r if hasattr(r, "__len__") else (r, r, r)
        M = Matrix.Translation(c) @ R(rot) @ Matrix.Diagonal((*r, 1))
        bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1, matrix=M)
        self._tag(before, m)

    def box(self, c, size, m, rot=(0, 0, 0)):
        before = set(self.bm.faces)
        M = Matrix.Translation(c) @ R(rot) @ Matrix.Diagonal((*size, 1))
        bmesh.ops.create_cube(self.bm, size=1, matrix=M)
        self._tag(before, m, smooth=False)

    def arc(self, c, radius, thick, a0, a1, m, segs=16, ring=10):
        """Tube along an arc in the XZ plane (closed / happy eyes)."""
        before = set(self.bm.faces)
        c = Vector(c)
        rings = []
        for i in range(segs + 1):
            t = math.radians(a0 + (a1 - a0) * i / segs)
            n1 = Vector((math.cos(t), 0, math.sin(t)))
            n2 = Vector((0, 1, 0))
            ctr = c + n1 * radius
            rings.append([self.bm.verts.new(ctr + thick * (math.cos(2 * math.pi * j / ring) * n1 +
                                                             math.sin(2 * math.pi * j / ring) * n2))
                          for j in range(ring)])
        for a, b in zip(rings, rings[1:]):
            for j in range(ring):
                self.bm.faces.new((a[j], a[(j + 1) % ring], b[(j + 1) % ring], b[j]))
        self._tag(before, m)
        for t in (a0, a1):  # rounded caps
            t = math.radians(t)
            self.sphere(c + Vector((math.cos(t), 0, math.sin(t))) * radius, thick, m, segs=10, rings=6)

    def build(self, name, coll, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        o = bpy.data.objects.new(name, me)
        coll.objects.link(o)
        o.parent = parent
        o.location = loc
        o.rotation_euler = [math.radians(a) for a in rot]
        return o


def empty(name, coll, parent=None, loc=(0, 0, 0), rot=(0, 0, 0), size=0.08):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = "PLAIN_AXES"
    o.empty_display_size = size
    coll.objects.link(o)
    o.parent = parent
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    return o


# ---------------------------------------------------------------- poses
POSES = {
    #             body loc            body rot     head loc (in body)   head rot
    "awake": dict(body=(0, 0.12, 0.66), brot=(0, 0, 0), head=(0, -0.66, 0.36), hrot=(0, 0, 0), eyes="open"),
    "focus": dict(body=(0, 0.10, 0.80), brot=(-72, 0, 0), head=(0, -0.80, 0.05), hrot=(72 + 12, 0, 0), eyes="open"),
    "rest":  dict(body=(0, 0.12, 0.52), brot=(0, 0, 0), head=(0, -0.60, 0.12), hrot=(10, 0, 0), eyes="closed"),
    "play":  dict(body=(0, 0.10, 0.80), brot=(-72, 0, 0), head=(0, -0.80, 0.05), hrot=(72 + 4, 0, 0), eyes="happy"),
}

STAND_LEGS = [((-0.22, -0.30, 0.34), (0, 0, 0)), ((0.22, -0.30, 0.34), (0, 0, 0)),
              ((-0.22, 0.44, 0.34), (0, 0, 0)), ((0.22, 0.44, 0.34), (0, 0, 0))]
SIT_LEGS = [((-0.24, -0.20, 0.22), (-84, 0, 6)), ((0.24, -0.20, 0.22), (-84, 0, -6)),     # feet out front
            ((-0.30, -0.36, 1.00), (-62, 0, -22)), ((0.30, -0.36, 1.00), (-62, 0, 22))]   # arms
LIE_LEGS = [((-0.22, -0.34, 0.20), (-90, 0, 4)), ((0.22, -0.34, 0.20), (-90, 0, -4)),
            ((-0.24, 0.40, 0.18), (-90, 0, 10)), ((0.24, 0.40, 0.18), (-90, 0, -10))]


def wool_body(mb, m, seed):
    rnd = random.Random(seed)
    mb.sphere((0, 0, 0), (0.50, 0.60, 0.40), m)
    n = 48
    for i in range(n):
        z = 1 - 2 * (i + 0.5) / n
        rr = math.sqrt(1 - z * z)
        phi = i * 2.399963
        p = Vector((math.cos(phi) * rr, math.sin(phi) * rr, z))
        if p.z < -0.6:
            continue
        mb.sphere((p.x * 0.47, p.y * 0.57, p.z * 0.37), rnd.uniform(0.17, 0.23), m, segs=20, rings=12)
    mb.sphere((0, 0.74, 0.14), 0.12, m, segs=18, rings=10)  # tail


def build_sheep(pose, x=0.0):
    P = POSES[pose]
    name = pose.capitalize()
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    W, F, E, L, H = mat("wool", 0.95), mat("face"), mat("ear"), mat("leg"), mat("hoof", 0.6)
    D, S, N = mat("eye", 0.35), mat("shine", 0.2, emit=2.0), mat("nose", 0.5)

    root = empty(name, coll, loc=(x, 0, 0), size=0.25)
    body = empty(f"{name}_BodyPivot", coll, root, P["body"], P["brot"])
    mb = MB(); wool_body(mb, W, seed=7); mb.build(f"{name}_Wool", coll, body)

    head = empty(f"{name}_HeadPivot", coll, body, P["head"], P["hrot"])
    mb = MB()
    mb.sphere((0, 0, 0), (0.33, 0.27, 0.28), F)
    for (hx, hy, hz, hr) in [(-0.18, 0.03, 0.20, 0.13), (0, -0.02, 0.25, 0.15), (0.18, 0.03, 0.20, 0.13),
                             (-0.09, 0.11, 0.27, 0.13), (0.09, 0.11, 0.27, 0.13), (0, 0.14, 0.17, 0.15),
                             (-0.25, 0.08, 0.10, 0.10), (0.25, 0.08, 0.10, 0.10)]:
        mb.sphere((hx, hy, hz), hr, W, segs=20, rings=12)
    mb.sphere((0, -0.272, -0.085), (0.05, 0.03, 0.032), N)
    mb.sphere((0, -0.266, -0.118), (0.014, 0.014, 0.03), N, segs=12, rings=8)
    mb.build(f"{name}_Head", coll, head)

    for side in (-1, 1):
        ear = empty(f"{name}_Ear{'L' if side < 0 else 'R'}", coll, head, (side * 0.29, 0.03, 0.09), (0, side * -58, side * -12))
        mb = MB(); mb.sphere((0, 0, -0.14), (0.085, 0.05, 0.17), E)
        mb.build(f"{name}_EarMesh{'L' if side < 0 else 'R'}", coll, ear)

    eyes = empty(f"{name}_Eyes", coll, head, (0, -0.245, 0.03))
    mb = MB()
    for side in (-1, 1):
        ex = side * 0.13
        if P["eyes"] == "open":
            mb.sphere((ex, 0, 0), (0.055, 0.04, 0.065), D)
            mb.sphere((ex - 0.02, -0.036, 0.022), 0.018, S, segs=12, rings=8)
        elif P["eyes"] == "closed":
            mb.arc((ex, -0.012, 0.02), 0.05, 0.011, 200, 340, D)
        else:
            mb.arc((ex, -0.012, -0.03), 0.05, 0.012, 25, 155, D)
    mb.build(f"{name}_EyeMesh", coll, eyes)

    legs = {"awake": STAND_LEGS, "focus": SIT_LEGS, "play": SIT_LEGS, "rest": LIE_LEGS}[pose]
    for i, (loc, rot) in enumerate(legs):
        leg = empty(f"{name}_Leg{i}", coll, root, loc, rot)
        mb = MB()
        mb.sphere((0, 0, -0.13), (0.085, 0.085, 0.16), L)
        mb.sphere((0, -0.01, -0.27), (0.105, 0.115, 0.072), H)
        mb.build(f"{name}_LegMesh{i}", coll, leg)

    if pose == "focus":
        build_book(name, coll, root)
    if pose == "play":
        build_controller(name, coll, root)
    if pose == "rest":
        build_zzz(name, coll, root)
    return root


def build_book(name, coll, root):
    C, Pg = mat("cover", 0.7), mat("page", 0.9)
    book = empty(f"{name}_Book", coll, root, (0, -0.86, 0.80), (-28, 0, 0), size=0.15)
    for side, ang in ((-1, -28), (1, 28)):
        hinge = empty(f"{name}_BookHinge{'L' if side < 0 else 'R'}", coll, book, (0, 0, 0), (0, 0, ang))
        mb = MB()
        mb.box((side * 0.15, 0, 0), (0.30, 0.018, 0.38), C)
        mb.box((side * 0.142, 0.022, 0), (0.27, 0.03, 0.35), Pg)
        mb.build(f"{name}_BookHalf{'L' if side < 0 else 'R'}", coll, hinge)
    flip = empty(f"{name}_PageFlip", coll, book, (0, 0, 0), (0, 0, 28))
    mb = MB(); mb.box((0.135, 0.040, 0), (0.265, 0.006, 0.345), Pg)
    mb.build(f"{name}_Page", coll, flip)


def build_controller(name, coll, root):
    Pd, K = mat("pad", 0.5), mat("padkey", 0.5)
    pad = empty(f"{name}_Controller", coll, root, (0, -0.86, 0.78), (-55, 0, 0), size=0.15)
    mb = MB()
    mb.sphere((0, 0, 0), (0.17, 0.06, 0.085), Pd)
    for s in (-1, 1):
        mb.sphere((s * 0.15, 0.0, -0.035), (0.085, 0.065, 0.1), Pd, rot=(0, s * 20, 0))
    mb.box((-0.13, -0.06, 0.01), (0.07, 0.02, 0.022), K)
    mb.box((-0.13, -0.06, 0.01), (0.022, 0.02, 0.07), K)
    for (bx, bz, key) in ((0.13, 0.04, "btn_a"), (0.165, 0.005, "btn_b"), (0.13, -0.03, "btn_c"), (0.095, 0.005, "btn_d")):
        mb.sphere((bx, -0.058, bz), (0.018, 0.012, 0.018), mat(key, 0.4), segs=12, rings=8)
    mb.build(f"{name}_ControllerMesh", coll, pad)


def build_zzz(name, coll, root):
    Z = mat("zzz", 0.6)
    for i in range(3):
        cu = bpy.data.curves.new(f"{name}_Ztext{i}", "FONT")
        cu.body = "z"
        cu.extrude = 0.015
        cu.size = 0.22
        cu.align_x = "CENTER"
        tmp = bpy.data.objects.new("tmp", cu)
        coll.objects.link(tmp)
        bpy.context.view_layer.update()
        me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
        bpy.data.objects.remove(tmp)
        bpy.data.curves.remove(cu)
        me.materials.append(Z)
        o = bpy.data.objects.new(f"{name}_Z{i}", me)
        coll.objects.link(o)
        o.parent = root
        o.rotation_euler = (math.radians(90), 0, 0)


# ---------------------------------------------------------------- animation
def key(o, path, idx, pairs):
    for f, v in pairs:
        getattr(o, path)[idx] = v
        o.keyframe_insert(path, index=idx, frame=f)


def keyv(o, path, pairs):
    for f, v in pairs:
        setattr(o, path, v)
        o.keyframe_insert(path, frame=f)


def deg(base, d):
    return base + math.radians(d)


def blink(eyes, frames):
    pairs = [(1, 1.0)]
    for f in frames:
        pairs += [(f, 1.0), (f + 2, 0.1), (f + 4, 1.0)]
    key(eyes, "scale", 2, pairs + [(END, 1.0)])


def obj(n):
    return bpy.data.objects[n]


def animate(pose):
    n = pose.capitalize()
    root, body, head, eyes = obj(n), obj(f"{n}_BodyPivot"), obj(f"{n}_HeadPivot"), obj(f"{n}_Eyes")
    earL, earR = obj(f"{n}_EarL"), obj(f"{n}_EarR")
    hx, hz = head.rotation_euler[0], head.rotation_euler[2]
    eL, eR = earL.rotation_euler[1], earR.rotation_euler[1]

    if pose == "awake":
        for i, s in enumerate((1.02, 1.02, 1.04)):
            key(body, "scale", i, [(1, 1), (25, s), (49, 1), (73, s), (END, 1)])
        key(head, "rotation_euler", 2, [(1, hz), (25, deg(hz, 9)), (49, hz), (73, deg(hz, -9)), (END, hz)])
        key(head, "rotation_euler", 1, [(1, 0), (25, math.radians(-5)), (49, 0), (73, math.radians(5)), (END, 0)])
        key(root, "location", 2, [(1, 0), (76, 0), (81, 0.16), (86, 0), (END, 0)])
        key(body, "scale", 2, [(86, 1), (89, 0.93), (93, 1.0)])
        key(earL, "rotation_euler", 1, [(1, eL), (58, eL), (61, deg(eL, 18)), (64, eL), (82, deg(eL, 14)), (88, eL), (END, eL)])
        key(earR, "rotation_euler", 1, [(1, eR), (58, eR), (61, deg(eR, -18)), (64, eR), (82, deg(eR, -14)), (88, eR), (END, eR)])
        blink(eyes, (38, 66))

    elif pose == "focus":
        for i, s in enumerate((1.015, 1.015, 1.03)):
            key(body, "scale", i, [(1, 1), (48, s), (END, 1)])
        # read a line left → right, twice, nodding slightly
        key(head, "rotation_euler", 2, [(1, deg(hz, 7)), (20, deg(hz, -7)), (24, deg(hz, 7)), (44, deg(hz, -7)),
                                        (60, deg(hz, 0)), (80, deg(hz, 7)), (END, deg(hz, 7))])
        key(head, "rotation_euler", 0, [(1, hx), (20, deg(hx, 3)), (44, deg(hx, 4)), (60, deg(hx, -3)), (END, hx)])
        flip = obj(f"{n}_PageFlip")
        key(flip, "rotation_euler", 2, [(1, math.radians(28)), (50, math.radians(28)), (64, math.radians(152)),
                                        (LOOP, math.radians(152)), (END, math.radians(28))])
        book = obj(f"{n}_Book")
        bx = book.rotation_euler[0]
        key(book, "rotation_euler", 0, [(1, bx), (48, deg(bx, 3)), (END, bx)])
        blink(eyes, (30, 74))

    elif pose == "rest":
        for i, s in enumerate((1.03, 1.03, 1.06)):
            key(body, "scale", i, [(1, 1), (24, s), (48, 1), (72, s), (END, 1)])
        key(head, "rotation_euler", 0, [(1, hx), (24, deg(hx, -3)), (48, hx), (72, deg(hx, -3)), (END, hx)])
        key(earL, "rotation_euler", 1, [(1, deg(eL, 8)), (END, deg(eL, 8))])
        key(earR, "rotation_euler", 1, [(1, deg(eR, -8)), (END, deg(eR, -8))])
        hw = Vector((0, -0.48, 0.70))  # world-ish head position (relative to root)
        life = 64
        for i in range(3):
            z = obj(f"{n}_Z{i}")
            start = 1 + 32 * i
            for f in range(1, END + 1, 4):
                ph = ((f - start) % LOOP) / life
                vis = 0 <= ph <= 1
                p = ph if vis else 0
                s = math.sin(math.pi * p) * (0.6 + 0.4 * p) if vis else 0.0
                loc = hw + Vector((0.32 + 0.22 * p + 0.04 * math.sin(p * 9), 0, 0.25 + 0.55 * p))
                keyv(z, "location", [(f, loc)])
                keyv(z, "scale", [(f, (s, s, s))])

    elif pose == "play":
        hop = [(1, 0)]
        sq = [(1, 1.0)]
        for b in range(6):  # six happy bounces
            f0 = 1 + b * 16
            hop += [(f0 + 8, 0.12), (f0 + 16, 0)]
            sq += [(f0 + 3, 1.03), (f0 + 14, 1.0), (f0 + 16, 0.95)]
        sq[-1] = (END, 1.0)
        key(root, "location", 2, hop)
        key(body, "scale", 2, sq)
        pad = obj(f"{n}_Controller")
        py = pad.rotation_euler[1]
        key(pad, "rotation_euler", 1, [(1, py), (12, deg(py, 10)), (24, deg(py, -10)), (36, deg(py, 10)),
                                       (48, py), (60, deg(py, -12)), (72, deg(py, 12)), (84, deg(py, -8)), (END, py)])
        key(head, "rotation_euler", 1, [(1, 0), (24, math.radians(8)), (48, 0), (72, math.radians(-8)), (END, 0)])
        key(earL, "rotation_euler", 1, [(f, deg(eL, 14 if (f // 8) % 2 else 0)) for f in range(1, END + 1, 8)] + [(END, eL)])
        key(earR, "rotation_euler", 1, [(f, deg(eR, -14 if (f // 8) % 2 else 0)) for f in range(1, END + 1, 8)] + [(END, eR)])


# ---------------------------------------------------------------- scene
def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.actions):
        for b in list(blocks):
            blocks.remove(b)


def setup_stage():
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = 1, LOOP
    sc.render.fps = 24
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    w = sc.world or bpy.data.worlds.new("World")
    sc.world = w
    try:
        w.use_nodes = True
    except Exception:
        pass
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = lin(PALETTE["fog"])
    bg.inputs["Strength"].default_value = 0.55
    try:
        sc.view_settings.view_transform = "Standard"
    except TypeError:
        pass

    stage = bpy.data.collections.new("Stage")
    sc.collection.children.link(stage)
    me = bpy.data.meshes.new("Ground")
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30); bm.to_mesh(me); bm.free()
    me.materials.append(mat("fog", 1.0))
    g = bpy.data.objects.new("Ground", me); stage.objects.link(g)

    sun = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    sun.data.energy = 1.4
    sun.data.angle = math.radians(25)
    sun.rotation_euler = (math.radians(40), math.radians(-18), math.radians(-35))
    stage.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
    fill.data.energy = 60
    fill.data.size = 6
    fill.location = (0, -6, 4)
    fill.rotation_euler = (math.radians(55), 0, 0)
    stage.objects.link(fill)

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 50
    stage.objects.link(cam)
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
    return cam


def aim(cam, target, offset):
    cam.location = Vector(target) + Vector(offset)
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


SPACING = {"awake": -3.3, "focus": -1.1, "rest": 1.1, "play": 3.3}
