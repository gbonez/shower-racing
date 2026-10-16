extends RefCounted

# The crypt's look: a hand-dressed catacomb. Every room gets a regular architectural shell (skirting, cornice,
# pilasters, ribbed vaults, door surrounds, sconces) and a theme: bone-lined hallways, a columned ossuary, a chapel
# with an altar and pews, burial chambers, an embalming room and the sealed tomb. Most decoration is merged into a
# few vertex-coloured meshes per room, so a room costs a handful of nodes instead of thousands.
# Builders draw into the house node `h` (untyped: it calls the house script's helpers).

const STONE := Color(0.27, 0.29, 0.27)
const MOSS := Color(0.16, 0.26, 0.17)
const BONE := Color(0.85, 0.82, 0.7)
const WOOD := Color(0.19, 0.13, 0.09)
const IRON := Color(0.1, 0.1, 0.12)
const GHOST := Color(0.35, 1.0, 0.6)
const FLAME := Color(1.0, 0.55, 0.2)
const WARM := Color(1.0, 0.6, 0.3)
const DARK := Color(0.025, 0.022, 0.02)
const TEX := 256
const WALL_TILE := 2.4
const FLOOR_TILE := 3.2
const MAX_LIGHTS := 5

static var _mats := {}
static var _imgs := {}


# --- Merged geometry ---

# Triangle soup with vertex colours and UVs, turned into one MeshInstance3D.
class Batch:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var u := PackedVector2Array()
	var idx := PackedInt32Array()

	func quad4(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n0: Vector3, n1: Vector3, n2: Vector3,
			n3: Vector3, col: Color, uvs: Array) -> void:
		var base := v.size()
		v.append(p0)
		v.append(p1)
		v.append(p2)
		v.append(p3)
		n.append(n0)
		n.append(n1)
		n.append(n2)
		n.append(n3)
		c.append(col)
		c.append(col)
		c.append(col)
		c.append(col)
		if uvs.is_empty():
			u.append(Vector2(0, 0))
			u.append(Vector2(1, 0))
			u.append(Vector2(1, 1))
			u.append(Vector2(0, 1))
		else:
			u.append(uvs[0])
			u.append(uvs[1])
			u.append(uvs[2])
			u.append(uvs[3])
		var area := (p2 - p0).cross(p3 - p1)
		if area.dot(n0 + n1 + n2 + n3) >= 0.0:
			idx.append(base)
			idx.append(base + 2)
			idx.append(base + 1)
			idx.append(base)
			idx.append(base + 3)
			idx.append(base + 2)
		else:
			idx.append(base)
			idx.append(base + 1)
			idx.append(base + 2)
			idx.append(base)
			idx.append(base + 2)
			idx.append(base + 3)

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color, uvs: Array = []) -> void:
		quad4(p0, p1, p2, p3, nrm, nrm, nrm, nrm, col, uvs)

	func tri(p0: Vector3, p1: Vector3, p2: Vector3, nrm: Vector3, col: Color) -> void:
		var base := v.size()
		v.append(p0)
		v.append(p1)
		v.append(p2)
		for i in 3:
			n.append(nrm)
			c.append(col)
		u.append(Vector2(0, 0))
		u.append(Vector2(1, 0))
		u.append(Vector2(0, 1))
		if (p1 - p0).cross(p2 - p0).dot(nrm) >= 0.0:
			idx.append(base)
			idx.append(base + 2)
			idx.append(base + 1)
		else:
			idx.append(base)
			idx.append(base + 1)
			idx.append(base + 2)

	func box(t: Transform3D, size: Vector3, col: Color) -> void:
		var half := size * 0.5
		var ex := t.basis.x * half.x
		var ey := t.basis.y * half.y
		var ez := t.basis.z * half.z
		var o := t.origin
		var nx := t.basis.x.normalized()
		var ny := t.basis.y.normalized()
		var nz := t.basis.z.normalized()
		quad(o + ez - ex - ey, o + ez + ex - ey, o + ez + ex + ey, o + ez - ex + ey, nz, col)
		quad(o - ez + ex - ey, o - ez - ex - ey, o - ez - ex + ey, o - ez + ex + ey, -nz, col)
		quad(o + ex - ey - ez, o + ex + ey - ez, o + ex + ey + ez, o + ex - ey + ez, nx, col)
		quad(o - ex - ey + ez, o - ex + ey + ez, o - ex + ey - ez, o - ex - ey - ez, -nx, col)
		quad(o + ey - ez - ex, o + ey - ez + ex, o + ey + ez + ex, o + ey + ez - ex, ny, col)
		quad(o - ey - ez - ex, o - ey + ez - ex, o - ey + ez + ex, o - ey - ez + ex, -ny, col)

	func cyl(t: Transform3D, rt: float, rb: float, hgt: float, col: Color, segs: int, caps: bool) -> void:
		var hh := hgt * 0.5
		var slope := (rb - rt) / maxf(hgt, 0.001)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var c0 := cos(a0)
			var s0 := sin(a0)
			var c1 := cos(a1)
			var s1 := sin(a1)
			var n0 := (t.basis * Vector3(c0, slope, s0)).normalized()
			var n1 := (t.basis * Vector3(c1, slope, s1)).normalized()
			quad4(t * Vector3(rb * c0, -hh, rb * s0), t * Vector3(rb * c1, -hh, rb * s1),
					t * Vector3(rt * c1, hh, rt * s1), t * Vector3(rt * c0, hh, rt * s0), n0, n1, n1, n0, col, [])
			if caps:
				if rt > 0.001:
					tri(t * Vector3(0, hh, 0), t * Vector3(rt * c1, hh, rt * s1), t * Vector3(rt * c0, hh, rt * s0),
							t.basis * Vector3.UP, col)
				if rb > 0.001:
					tri(t * Vector3(0, -hh, 0), t * Vector3(rb * c0, -hh, rb * s0), t * Vector3(rb * c1, -hh, rb * s1),
							-(t.basis * Vector3.UP), col)

	func ball(t: Transform3D, radius: float, col: Color, segs: int, rings: int, squash: Vector3) -> void:
		for ri in rings:
			var th0 := PI * ri / rings
			var th1 := PI * (ri + 1) / rings
			for si in segs:
				var ph0 := TAU * si / segs
				var ph1 := TAU * (si + 1) / segs
				var d00 := Vector3(sin(th0) * cos(ph0), cos(th0), sin(th0) * sin(ph0))
				var d01 := Vector3(sin(th0) * cos(ph1), cos(th0), sin(th0) * sin(ph1))
				var d10 := Vector3(sin(th1) * cos(ph0), cos(th1), sin(th1) * sin(ph0))
				var d11 := Vector3(sin(th1) * cos(ph1), cos(th1), sin(th1) * sin(ph1))
				quad4(t * (d00 * radius * squash), t * (d01 * radius * squash), t * (d11 * radius * squash),
						t * (d10 * radius * squash), t.basis * d00, t.basis * d01, t.basis * d11, t.basis * d10, col, [])


# Collects batches, collision shapes, lights and labels for one room in a movable local frame `f`
# (local y is the height above the room's floor).
class Deco:
	var h
	var r
	var f := Transform3D.IDENTITY
	var batches := {}
	var shapes: Array = []
	var labels: Array = []
	var light_nodes: Array = []

	func bt(key: String) -> Batch:
		if not batches.has(key):
			batches[key] = Batch.new()
		return batches[key]

	func xf(pos: Vector3, rot := Basis.IDENTITY) -> Transform3D:
		return f * Transform3D(rot, pos)

	func box(key: String, pos: Vector3, size: Vector3, col := Color.WHITE, rot := Basis.IDENTITY) -> void:
		bt(key).box(xf(pos, rot), size, col)

	func cyl(key: String, pos: Vector3, rt: float, rb: float, hgt: float, col := Color.WHITE, segs := 8,
			rot := Basis.IDENTITY) -> void:
		bt(key).cyl(xf(pos, rot), rt, rb, hgt, col, segs, true)

	func ball(key: String, pos: Vector3, radius: float, col := Color.WHITE, squash := Vector3.ONE, segs := 7,
			rings := 4, rot := Basis.IDENTITY) -> void:
		bt(key).ball(xf(pos, rot), radius, col, segs, rings, squash)

	func quad(key: String, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col := Color.WHITE, uvs: Array = []) -> void:
		var nrm := f.basis * (p1 - p0).cross(p3 - p0).normalized()
		bt(key).quad(f * p0, f * p1, f * p2, f * p3, nrm, col, uvs)

	func tri(key: String, p0: Vector3, p1: Vector3, p2: Vector3, col: Color, nrm: Vector3) -> void:
		bt(key).tri(f * p0, f * p1, f * p2, f.basis * nrm, col)

	# A box lying between two local points.
	func seg(key: String, p0: Vector3, p1: Vector3, thick: float, width: float, col: Color) -> void:
		var dv := p1 - p0
		var length := dv.length()
		if length < 0.001:
			return
		var x := dv / length
		var z := x.cross(Vector3.UP)
		z = Vector3.BACK if z.length() < 0.01 else z.normalized()
		var y := z.cross(x)
		box(key, (p0 + p1) * 0.5, Vector3(length, thick, width), col, Basis(x, y, z))

	# Circular arch from p0 to p1 (same height), rising `rise` above them (rise <= half span).
	func arch(key: String, p0: Vector3, p1: Vector3, rise: float, thick: float, width: float, col: Color,
			steps := 10) -> void:
		var span := p1 - p0
		var hw := span.length() * 0.5
		if hw < 0.05 or rise < 0.05:
			return
		rise = minf(rise, hw)
		var rho := (hw * hw + rise * rise) / (2.0 * rise)
		var dir := span / (hw * 2.0)
		var mid := (p0 + p1) * 0.5
		var prev := p0
		for i in range(1, steps + 1):
			var t := float(i) / steps
			var x := (t - 0.5) * 2.0 * hw
			var y := sqrt(maxf(rho * rho - x * x, 0.0)) - (rho - rise)
			var p := mid + dir * x + Vector3(0, y, 0)
			seg(key, prev, p, thick, width, col)
			prev = p

	# Flat panel with an arched top: `pos` is the middle of the spring line.
	func arch_panel(key: String, pos: Vector3, hw: float, rise: float, y_bottom: float, col: Color) -> void:
		var spring := pos.y
		quad(key, Vector3(pos.x - hw, y_bottom, pos.z), Vector3(pos.x + hw, y_bottom, pos.z),
				Vector3(pos.x + hw, spring, pos.z), Vector3(pos.x - hw, spring, pos.z), col)
		rise = minf(rise, hw)
		var rho := (hw * hw + rise * rise) / (2.0 * rise)
		var prev := Vector3(pos.x - hw, spring, pos.z)
		for i in range(1, 9):
			var x := (float(i) / 8.0 - 0.5) * 2.0 * hw
			var y := sqrt(maxf(rho * rho - x * x, 0.0)) - (rho - rise)
			var p := Vector3(pos.x + x, spring + y, pos.z)
			tri(key, Vector3(pos.x, spring, pos.z), prev, p, col, Vector3.BACK)
			prev = p

	func solid_box(pos: Vector3, size: Vector3, rot := Basis.IDENTITY) -> void:
		var s := BoxShape3D.new()
		s.size = size
		shapes.append([s, xf(pos, rot)])

	func solid_cyl(pos: Vector3, radius: float, hgt: float) -> void:
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = hgt
		shapes.append([s, xf(pos)])

	func sbox(key: String, pos: Vector3, size: Vector3, col := Color.WHITE, rot := Basis.IDENTITY) -> void:
		box(key, pos, size, col, rot)
		solid_box(pos, size, rot)

	func world_rect(cx: float, cz: float, w: float, dp: float) -> Rect2:
		var a := f * Vector3(cx - w * 0.5, 0.0, cz - dp * 0.5)
		var b := f * Vector3(cx + w * 0.5, 0.0, cz + dp * 0.5)
		var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
		return Rect2(lo, hi - lo)

	# Is this local floor rectangle inside the room and clear of everything already placed?
	func fits(cx: float, cz: float, w: float, dp: float, grow := 0.0) -> bool:
		var rc := world_rect(cx, cz, w, dp)
		var inner: Rect2 = r.interior()
		if not inner.grow(0.03).encloses(rc):
			return false
		return h._free(r, rc.grow(grow))

	func reserve(cx: float, cz: float, w: float, dp: float) -> void:
		r.used.append(world_rect(cx, cz, w, dp))

	func spot(pos: Vector3) -> void:
		r.spots.append(f * pos)

	func light(pos: Vector3, col: Color, range_m: float, energy: float) -> void:
		if light_nodes.size() >= MAX_LIGHTS:
			return
		var l := OmniLight3D.new()
		l.position = f * pos
		l.light_color = col
		l.omni_range = range_m
		l.light_energy = energy
		l.light_cull_mask = 1
		light_nodes.append(l)

	func label(pos: Vector3, yaw: float, text: String, size := 0.004, col := Color(0.1, 0.09, 0.07)) -> void:
		var lb := Label3D.new()
		lb.text = text
		lb.font_size = 32
		lb.pixel_size = size
		lb.modulate = col
		lb.outline_size = 0
		lb.shaded = true
		lb.transform = xf(pos, Basis(Vector3.UP, yaw))
		labels.append(lb)

	# --- Small props ---

	func skull(pos: Vector3, sc := 1.0, yaw := 0.0, col := BONE, detail := true) -> void:
		var rot := Basis(Vector3.UP, yaw)
		ball("plain", pos, 0.085 * sc, col, Vector3(1, 1.05, 1.1), 6, 4, rot)
		for sx in [-1.0, 1.0]:
			box("plain", pos + rot * (Vector3(sx * 0.034, 0.008, 0.078) * sc), Vector3(0.03, 0.034, 0.02) * sc, DARK, rot)
		if detail:
			box("plain", pos + rot * (Vector3(0, -0.07, 0.03) * sc), Vector3(0.07, 0.04, 0.07) * sc, col.darkened(0.12), rot)

	func bone(pos: Vector3, rot: Basis, length := 0.36, col := BONE.darkened(0.08)) -> void:
		cyl("plain", pos, 0.016, 0.016, length, col, 5, rot)
		for e in [-0.5, 0.5]:
			ball("plain", pos + rot * Vector3(0, e * length, 0), 0.026, col, Vector3.ONE, 4, 3)

	func flame(pos: Vector3, sc := 1.0, key := "g_flame") -> void:
		ball(key, pos, 0.03 * sc, Color.WHITE, Vector3(0.75, 1.7, 0.75), 5, 3)

	func candle(pos: Vector3, hgt := 0.18, lit := true) -> void:
		cyl("plain", pos + Vector3(0, hgt * 0.5, 0), 0.026, 0.03, hgt, Color(0.85, 0.8, 0.62), 6)
		if lit:
			flame(pos + Vector3(0, hgt + 0.04, 0))

	func ring(key: String, centre: Vector3, radius: float, tube: float, col: Color, count := 12,
			rot := Basis.IDENTITY) -> void:
		for i in count:
			var a := TAU * i / count
			ball(key, centre + rot * Vector3(cos(a) * radius, sin(a) * radius, 0), tube, col, Vector3.ONE, 4, 3)

	func finish(mat_fn: Callable, layers: int) -> void:
		var root := Node3D.new()
		root.name = "CryptDeco"
		h.add_child(root)
		for key in batches:
			var b: Batch = batches[key]
			if b.idx.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = b.v
			arrays[Mesh.ARRAY_NORMAL] = b.n
			arrays[Mesh.ARRAY_COLOR] = b.c
			arrays[Mesh.ARRAY_TEX_UV] = b.u
			arrays[Mesh.ARRAY_INDEX] = b.idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat_fn.call(key)
			mi.layers = layers
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		if not shapes.is_empty():
			var body := StaticBody3D.new()
			for s in shapes:
				var cs := CollisionShape3D.new()
				cs.shape = s[0]
				cs.transform = s[1]
				body.add_child(cs)
			root.add_child(body)
		for lb in labels:
			root.add_child(lb)
		for l in light_nodes:
			root.add_child(l)


# --- Textures and materials (generated once, with fixed seeds) ---

static func _noise(seed_v: int, freq: float, w: int, hgt: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_v
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 3
	return n.get_seamless_image(w, hgt).get_data()


static func _to_normal(height: Image, strength: float) -> Image:
	var nm := height.duplicate() as Image
	nm.bump_map_to_normal_map(strength)
	nm.generate_mipmaps()
	return nm


static func _carve_cracks(alb: Image, hgt: Image, rng: RandomNumberGenerator, count: int) -> void:
	var w := alb.get_width()
	for i in count:
		var p := Vector2(rng.randf() * w, rng.randf() * w)
		var ang := rng.randf() * TAU
		for s in rng.randi_range(18, 46):
			ang += rng.randf_range(-0.55, 0.55)
			p += Vector2(cos(ang), sin(ang)) * 1.5
			var x := posmod(int(p.x), w)
			var y := posmod(int(p.y), w)
			alb.set_pixel(x, y, alb.get_pixel(x, y) * 0.3)
			hgt.set_pixel(x, y, Color(0.05, 0.05, 0.05))


# Stone blocks of varied tone with mortar, bevelled edges, moss blotches and a few cracks.
static func _gen_stone() -> Array:
	var w := TEX
	var rng := RandomNumberGenerator.new()
	rng.seed = 77013
	var n_m := _noise(3, 0.022, w, w)
	var n_f := _noise(9, 0.09, w, w)
	var n_g := _noise(21, 0.011, w, w)
	var alb := Image.create(w, w, false, Image.FORMAT_RGB8)
	var hgt := Image.create(w, w, false, Image.FORMAT_L8)
	var rows := 8
	var rh := w / rows
	for row in rows:
		var js: Array[int] = []
		var base := rng.randi_range(0, 63)
		for k in 4:
			js.append(posmod(k * 64 + base + rng.randi_range(-12, 12), w))
		js.sort()
		js.append(js[0] + w)
		var tones: Array = []
		for k in 4:
			tones.append([rng.randf_range(-0.07, 0.07), rng.randf_range(-1.0, 1.0),
					1.0 if rng.randf() < 0.35 else 0.2])
		for x in w:
			var xx: int = x if x >= js[0] else x + w
			var bi := 0
			while bi < 3 and xx >= js[bi + 1]:
				bi += 1
			var dx: int = mini(xx - js[bi], js[bi + 1] - 1 - xx)
			var tone: Array = tones[bi]
			for yy in rh:
				var y := row * rh + yy
				var i := y * w + x
				var mott := float(n_m[i]) / 255.0 - 0.5
				var fine := float(n_f[i]) / 255.0 - 0.5
				var lum: float = 0.30 + float(tone[0]) + mott * 0.12 + fine * 0.05 + rng.randf_range(-0.012, 0.012)
				var warm: float = float(tone[1])
				var col := Color(lum * (0.97 + warm * 0.05), lum * 1.02, lum * (0.96 - warm * 0.05))
				var moss := clampf((float(n_g[i]) / 255.0 - 0.52) * 4.0, 0.0, 1.0) * float(tone[2])
				col = col.lerp(Color(0.12, 0.23, 0.11) * (0.85 + fine * 0.5), moss * 0.75)
				var d := mini(dx, mini(yy, rh - 1 - yy))
				var hv := 0.8 + mott * 0.25
				if d < 1:
					col = Color(0.05, 0.055, 0.05).lerp(col, 0.1)
					hv = 0.0
				elif d < 4:
					var t := float(d - 1) / 3.0
					col *= 0.6 + 0.4 * t
					hv = t * 0.8
				alb.set_pixel(x, y, col)
				hgt.set_pixel(x, y, Color(hv, hv, hv))
	_carve_cracks(alb, hgt, rng, 14)
	alb.generate_mipmaps()
	return [alb, _to_normal(hgt, 3.0)]


# Irregular flagstones with dark joints, wet patches and chips.
static func _gen_floor() -> Array:
	var w := TEX
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var n_m := _noise(31, 0.03, w, w)
	var n_f := _noise(37, 0.1, w, w)
	var n_g := _noise(41, 0.015, w, w)
	var alb := Image.create(w, w, false, Image.FORMAT_RGB8)
	var hgt := Image.create(w, w, false, Image.FORMAT_L8)
	var row_h: Array[int] = [60, 68, 60, 68]
	var y0 := 0
	for row in 4:
		var count := rng.randi_range(2, 3)
		var js: Array[int] = []
		var base := rng.randi_range(0, w - 1)
		for k in count:
			js.append(posmod(base + k * (w / count) + rng.randi_range(-18, 18), w))
		js.sort()
		js.append(js[0] + w)
		var tones: Array = []
		for k in count:
			tones.append([rng.randf_range(-0.045, 0.045), 1.0 if rng.randf() < 0.3 else 0.2])
		for x in w:
			var xx: int = x if x >= js[0] else x + w
			var bi := 0
			while bi < count - 1 and xx >= js[bi + 1]:
				bi += 1
			var dx: int = mini(xx - js[bi], js[bi + 1] - 1 - xx)
			var tone: Array = tones[bi]
			for yy in row_h[row]:
				var y := y0 + yy
				var i := y * w + x
				var mott := float(n_m[i]) / 255.0 - 0.5
				var fine := float(n_f[i]) / 255.0 - 0.5
				var lum: float = 0.17 + float(tone[0]) + mott * 0.08 + fine * 0.04 + rng.randf_range(-0.01, 0.01)
				var col := Color(lum, lum * 1.03, lum * 0.97)
				var wet := clampf((float(n_g[i]) / 255.0 - 0.55) * 4.0, 0.0, 1.0)
				col = col.lerp(Color(0.06, 0.1, 0.07), wet * float(tone[1]) * 0.7)
				var d := mini(dx, mini(yy, row_h[row] - 1 - yy))
				var hv := 0.8 + mott * 0.2
				if d < 2:
					col = Color(0.035, 0.04, 0.035)
					hv = 0.0
				elif d < 4:
					var t := float(d - 2) / 2.0
					col *= 0.7 + 0.3 * t
					hv = t * 0.8
				alb.set_pixel(x, y, col)
				hgt.set_pixel(x, y, Color(hv, hv, hv))
		y0 += row_h[row]
	_carve_cracks(alb, hgt, rng, 10)
	alb.generate_mipmaps()
	return [alb, _to_normal(hgt, 2.5)]


# Paving for the worn path down the middle of halls: a dark border and two columns of lighter slabs.
static func _gen_runner() -> Image:
	var w := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	for y in w:
		for x in w:
			var col: Color
			if x < 10 or x >= w - 10:
				col = Color(0.075, 0.08, 0.075)
			elif x == 10 or x == w - 11:
				col = Color(0.3, 0.3, 0.28)
			else:
				var cx := x - 11
				var shifted := (cx + (26 if ((y / 32) & 1) == 1 else 0)) % 52
				var d := mini(mini(shifted, 51 - shifted), mini(y % 32, 31 - y % 32))
				var lum := 0.22 + rng.randf_range(-0.018, 0.018) + 0.02 * float(((x / 26) + (y / 32) * 3) % 3)
				col = Color(lum * 1.02, lum, lum * 0.92)
				if d < 1:
					col = Color(0.05, 0.05, 0.045)
				elif d < 3:
					col *= 0.8
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return img


# Damp and moss creeping up from the floor (alpha fades out upwards, with a few long drip streaks).
static func _gen_grime() -> Image:
	var w := TEX
	var hh := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var noise := _noise(55, 0.03, w, hh)
	var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	var streaks := PackedFloat32Array()
	streaks.resize(w)
	for k in 14:
		var sx := rng.randi_range(0, w - 1)
		var sw := rng.randi_range(1, 4)
		var sl := rng.randf_range(0.2, 0.55)
		for dx in sw:
			streaks[(sx + dx) % w] = maxf(streaks[(sx + dx) % w], sl)
	for y in hh:
		var v := 1.0 - float(y) / float(hh - 1)
		for x in w:
			var nv := float(noise[y * w + x]) / 255.0
			var edge := v - 0.28 - (nv - 0.5) * 0.7
			var a := clampf(edge / 0.25, 0.0, 1.0)
			a = maxf(a, clampf((streaks[x] - (1.0 - v) * 0.8) * 3.0, 0.0, 0.6))
			var mossy := clampf((nv - 0.45) * 2.5, 0.0, 1.0)
			var col := Color(0.03, 0.045, 0.035).lerp(Color(0.1, 0.2, 0.09), mossy * (1.0 - v * 0.6))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a * 0.85))
	img.generate_mipmaps()
	return img


# A cobweb in the top-left corner of a square.
static func _gen_web() -> Image:
	var w := 128
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var spokes := 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var angs: Array[float] = []
	for k in spokes:
		angs.append(PI * 0.5 * (k + rng.randf_range(-0.2, 0.2) * 0.5) / (spokes - 1))
	for k in spokes:
		for s in 200:
			var t := float(s) / 200.0 * w * 1.2
			var x := int(cos(angs[k]) * t)
			var y := int(sin(angs[k]) * t)
			if x >= 0 and y >= 0 and x < w and y < w:
				img.set_pixel(x, y, Color(0.85, 0.87, 0.9, 0.75))
	for ringr in [14.0, 26.0, 40.0, 56.0, 76.0, 100.0]:
		for k in spokes - 1:
			for s in 40:
				var t := float(s) / 39.0
				var a: float = lerpf(angs[k], angs[k + 1], t)
				var rr: float = ringr * (1.0 - 0.14 * sin(PI * t))
				var x := int(cos(a) * rr)
				var y := int(sin(a) * rr)
				if x >= 0 and y >= 0 and x < w and y < w:
					img.set_pixel(x, y, Color(0.85, 0.87, 0.9, 0.6))
	img.generate_mipmaps()
	return img


static func _gen_wood() -> Image:
	var w := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	var grain: Array[float] = []
	for x in w:
		grain.append(rng.randf_range(-0.05, 0.05))
	for y in w:
		for x in w:
			var lum := 0.42 + grain[x] + rng.randf_range(-0.015, 0.015) + 0.03 * sin(y * 0.4 + x * 0.9)
			var col := Color(lum * 1.1, lum * 0.78, lum * 0.55)
			if y % 32 < 1:
				col *= 0.4
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return img


# Dingy wall tiles for the embalming room.
static func _gen_tile() -> Image:
	var w := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var img := Image.create(w, w, false, Image.FORMAT_RGB8)
	var tones: Array[float] = []
	for k in 16:
		tones.append(rng.randf_range(-0.05, 0.05))
	for y in w:
		for x in w:
			var lum := 0.52 + tones[(y / 16) * 4 + x / 16] + rng.randf_range(-0.012, 0.012)
			var col := Color(lum * 0.95, lum, lum * 0.88)
			if x % 16 < 1 or y % 16 < 1:
				col = Color(0.16, 0.17, 0.15)
			elif y % 16 > 13 or x % 16 > 13:
				col *= 0.85
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return img


static func _image(key: String) -> Variant:
	if not _imgs.has(key):
		match key:
			"stone":
				_imgs[key] = _gen_stone()
			"floor":
				_imgs[key] = _gen_floor()
			"runner":
				_imgs[key] = _gen_runner()
			"grime":
				_imgs[key] = _gen_grime()
			"web":
				_imgs[key] = _gen_web()
			"wood":
				_imgs[key] = _gen_wood()
			"tile":
				_imgs[key] = _gen_tile()
	return _imgs[key]


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


static func _triplanar(m: StandardMaterial3D, tile: float) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


static func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.6
	return m


static func _material(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match key:
		"stone":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex((_image("stone") as Array)[0])
			m.albedo_color = Color(1.45, 1.45, 1.4)
			m.vertex_color_use_as_albedo = true
			_triplanar(m, WALL_TILE)
			m.roughness = 0.95
		"plain":
			m = StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.85
		"iron":
			m = StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.albedo_color = Color(1.4, 1.4, 1.5)
			m.roughness = 0.5
			m.metallic = 0.35
		"wood":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex(_image("wood"))
			m.vertex_color_use_as_albedo = true
			_triplanar(m, 0.9)
			m.roughness = 0.9
		"tile":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex(_image("tile"))
			m.vertex_color_use_as_albedo = true
			_triplanar(m, 0.8)
			m.roughness = 0.45
		"runner":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex(_image("runner"))
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m.roughness = 0.9
		"puddle":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.012, 0.02, 0.025)
			m.roughness = 0.04
			m.metallic_specular = 0.9
		"grime":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex(_image("grime"))
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		"web":
			m = StandardMaterial3D.new()
			m.albedo_texture = _tex(_image("web"))
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 1.0
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		"g_flame":
			m = _glow(FLAME, 3.0)
		"g_ghost":
			m = _glow(GHOST, 1.8)
		"g_amber":
			m = _glow(Color(0.95, 0.65, 0.2), 1.3)
		"g_blue":
			m = _glow(Color(0.25, 0.45, 1.0), 1.7)
		"g_violet":
			m = _glow(Color(0.6, 0.22, 0.95), 1.6)
		"g_teal":
			m = _glow(Color(0.12, 0.8, 0.62), 1.6)
		"g_red":
			m = _glow(Color(0.9, 0.2, 0.22), 1.4)
		_:
			m = StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m


static func wall_material() -> StandardMaterial3D:
	if _mats.has("wall"):
		return _mats["wall"]
	var parts: Array = _image("stone")
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(parts[0])
	m.normal_enabled = true
	m.normal_texture = _tex(parts[1])
	m.normal_scale = 1.0
	_triplanar(m, WALL_TILE)
	m.roughness = 0.95
	_mats["wall"] = m
	return m


static func floor_material(_size: Vector2) -> StandardMaterial3D:
	if _mats.has("floor"):
		return _mats["floor"]
	var parts: Array = _image("floor")
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(parts[0])
	m.normal_enabled = true
	m.normal_texture = _tex(parts[1])
	_triplanar(m, FLOOR_TILE)
	m.roughness = 0.8
	_mats["floor"] = m
	return m


# --- Wall geometry helpers ---

# Frame sitting on a wall's inner face at coordinate `a` along the wall: local +z points into the room,
# local y is the height above the floor.
static func _wt(r, side: int, a: float) -> Transform3D:
	var inner: Rect2 = r.interior()
	var y0: float = r.y0
	var nrm: Vector3
	var p: Vector3
	match side:
		0:
			nrm = Vector3(0, 0, -1)
			p = Vector3(a, y0, inner.end.y)
		1:
			nrm = Vector3(0, 0, 1)
			p = Vector3(a, y0, inner.position.y)
		2:
			nrm = Vector3(-1, 0, 0)
			p = Vector3(inner.end.x, y0, a)
		_:
			nrm = Vector3(1, 0, 0)
			p = Vector3(inner.position.x, y0, a)
	return Transform3D(Basis(Vector3.UP.cross(nrm), Vector3.UP, nrm), p)


static func _wt0(r) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, r.y0, 0))


# Frame at the room centre whose local x runs along the room's long axis.
static func _axis_frame(r, along_x: bool) -> Transform3D:
	var c: Vector2 = r.interior().get_center()
	return Transform3D(Basis(Vector3.UP, 0.0 if along_x else -PI / 2.0), Vector3(c.x, r.y0, c.y))


static func _side_range(r, side: int) -> Vector2:
	var inner: Rect2 = r.interior()
	return Vector2(inner.position.x, inner.end.x) if side < 2 else Vector2(inner.position.y, inner.end.y)


# Free stretches of a wall (absolute coordinates along it), leaving `margin` around every opening.
static func _segments(r, side: int, margin: float, only_open := false) -> Array[Vector2]:
	var rng := _side_range(r, side)
	var cuts: Array[Vector2] = []
	for o in r.openings:
		if o["side"] != side or (only_open and o["kind"] != "open"):
			continue
		cuts.append(Vector2(float(o["lo"]) - margin, float(o["hi"]) + margin))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var segs: Array[Vector2] = []
	var cur := rng.x
	for cu in cuts:
		if cu.x > cur + 0.05:
			segs.append(Vector2(cur, minf(cu.x, rng.y)))
		cur = maxf(cur, cu.y)
	if cur < rng.y - 0.05:
		segs.append(Vector2(cur, rng.y))
	return segs


static func _blocked(r, side: int, a0: float, a1: float, margin: float) -> bool:
	for o in r.openings:
		if o["side"] == side and float(o["lo"]) - margin < a1 and float(o["hi"]) + margin > a0:
			return true
	return false


static func _jit(c: Color, amt := 0.1) -> Color:
	var k := 1.0 - amt + randf() * amt * 2.0
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func _flat(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, PI / 2.0)


# --- Entry point ---

static func furnish(h, r) -> void:
	var d := Deco.new()
	d.h = h
	d.r = r
	d.f = _wt0(r)
	_shell(d, h, r)
	match r.type:
		"hallway":
			_catacomb(d, h, r)
		"great_hall":
			_ossuary(d, h, r)
		"throne_room":
			_chapel(d, h, r)
		"bedroom":
			_burial_chamber(d, h, r)
		"kitchen":
			_embalming_room(d, h, r)
		"closet":
			_bone_room(d, h, r)
		"tomb":
			_tomb(d, h, r)
		_:
			_catacomb(d, h, r)
	_doors(d, h, r)
	_decay(d, r)
	d.finish(_material, int(h.main.mesh_layers))


# --- Shell: skirting, cornice, floor border, damp and soot ---

static func _shell(d: Deco, _h, r) -> void:
	var ht: float = r.y1 - r.y0
	var trim := Color(0.62, 0.62, 0.6)
	for side in 4:
		for seg in _segments(r, side, 0.25):
			var length := seg.y - seg.x
			d.f = _wt(r, side, (seg.x + seg.y) * 0.5)
			d.box("stone", Vector3(0, 0.13, 0.06), Vector3(length, 0.26, 0.12), trim)
			d.box("stone", Vector3(0, 0.285, 0.08), Vector3(length, 0.06, 0.16), trim * 1.15)
			d.box("stone", Vector3(0, 0.008, 0.24), Vector3(length, 0.016, 0.48), Color(0.28, 0.28, 0.27))
			d.box("stone", Vector3(0, 0.009, 0.5), Vector3(length, 0.018, 0.035), Color(0.55, 0.55, 0.52))
		for seg in _segments(r, side, 0.0, true):
			var length := seg.y - seg.x
			d.f = _wt(r, side, (seg.x + seg.y) * 0.5)
			d.box("stone", Vector3(0, ht - 0.09, 0.08), Vector3(length, 0.18, 0.16), trim * 1.05)
			d.box("stone", Vector3(0, ht - 0.21, 0.05), Vector3(length, 0.07, 0.1), trim)
		# Damp creeping up from the floor and soot under the ceiling.
		var sgn: float = d.f.basis.x.dot(Vector3.RIGHT if side < 2 else Vector3.BACK)
		d.f = _wt(r, side, 0.0)
		for seg in _segments(r, side, 0.25):
			var a := seg.x
			while a < seg.y - 0.1:
				var b := minf(a + randf_range(1.8, 2.8), seg.y)
				var gh := randf_range(0.9, 1.7)
				var uo := randf()
				var u1 := uo + (b - a) / 2.4
				var col := Color(1, 1, 1, randf_range(0.65, 1.0))
				d.quad("grime", Vector3(sgn * a, 0.27, 0.012), Vector3(sgn * b, 0.27, 0.012),
						Vector3(sgn * b, 0.27 + gh, 0.012), Vector3(sgn * a, 0.27 + gh, 0.012), col,
						[Vector2(uo, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(uo, 0)])
				a = b
			if randf() < 0.8:
				var cs := randf_range(seg.x, maxf(seg.x, seg.y - 2.0))
				var ce := minf(cs + randf_range(1.6, 2.6), seg.y)
				d.quad("grime", Vector3(sgn * cs, ht - 1.1, 0.012), Vector3(sgn * ce, ht - 1.1, 0.012),
						Vector3(sgn * ce, ht - 0.25, 0.012), Vector3(sgn * cs, ht - 0.25, 0.012), Color(0.35, 0.3, 0.3, 0.55),
						[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


# --- Wall pieces ---

# A burial niche (loculus) set into the wall: dark recess, stone frame and something inside.
static func _niche(d: Deco, x: float, yb: float, w: float, hgt: float) -> void:
	var tr := _jit(Color(0.62, 0.62, 0.6), 0.1)
	d.box("plain", Vector3(x, yb + hgt * 0.5, 0.025), Vector3(w, hgt, 0.04), DARK)
	d.box("stone", Vector3(x, yb - 0.04, 0.07), Vector3(w + 0.2, 0.08, 0.14), tr)
	d.box("stone", Vector3(x, yb + hgt + 0.05, 0.07), Vector3(w + 0.2, 0.1, 0.14), tr)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(x + sx * (w * 0.5 + 0.05), yb + hgt * 0.5, 0.06), Vector3(0.1, hgt, 0.12), tr)
	var roll := randf()
	if roll < 0.36:
		d.skull(Vector3(x + randf_range(-0.12, 0.12), yb + 0.1, 0.1), 1.0, randf_range(-0.4, 0.4), BONE.darkened(randf() * 0.2), false)
		d.bone(Vector3(x + randf_range(-0.15, 0.15), yb + 0.03, 0.1), _flat(randf_range(-0.3, 0.3)), minf(w - 0.1, 0.42))
	elif roll < 0.58:
		d.box("stone", Vector3(x, yb + hgt * 0.5, 0.075), Vector3(w, hgt, 0.05), tr * 1.1)
		d.box("plain", Vector3(x, yb + hgt * 0.55, 0.102), Vector3(0.05, hgt * 0.55, 0.01), DARK)
		d.box("plain", Vector3(x, yb + hgt * 0.62, 0.102), Vector3(0.24, 0.05, 0.01), DARK)
	elif roll < 0.8:
		for i in 4:
			d.bone(Vector3(x + randf_range(-0.2, 0.2), yb + 0.03 + i * 0.03, 0.09 + randf() * 0.04),
					_flat(randf_range(-0.6, 0.6)), 0.4)
		d.skull(Vector3(x + 0.2, yb + 0.17, 0.1), 0.9, -0.5, BONE.darkened(0.15), false)
	elif roll < 0.9:
		d.bone(Vector3(x, yb + 0.03, 0.1), _flat(0.2), 0.34)
	else:
		d.skull(Vector3(x - 0.12, yb + 0.1, 0.1), 0.95, 0.3, BONE, false)
		d.candle(Vector3(x + 0.16, yb, 0.1), 0.13)


# Niches in tidy rows and tiers between two pilasters.
static func _loculi_bay(d: Deco, r, side: int, b0: float, b1: float, y_start: float, y_max: float) -> void:
	if _blocked(r, side, b0 - 0.1, b1 + 0.1, 0.5):
		return
	var clear := (b1 - b0) - 0.9
	if clear < 0.7:
		return
	var cols := maxi(1, floori(clear / 1.15))
	var cw := clear / cols
	var tiers := clampi(floori((y_max - y_start + 0.2) / 0.74), 0, 3)
	for ci in cols:
		d.f = _wt(r, side, b0 + 0.45 + cw * (ci + 0.5))
		for ti in tiers:
			_niche(d, 0.0, y_start + ti * 0.74, cw - 0.24, 0.5)


static func _pilaster(d: Deco, r, side: int, a: float, spring: float) -> bool:
	if _blocked(r, side, a - 0.4, a + 0.4, 0.5):
		return false
	d.f = _wt(r, side, a)
	if not d.fits(0, 0.17, 0.72, 0.34):
		return false
	d.reserve(0, 0.17, 0.72, 0.34)
	var c := _jit(Color(0.66, 0.66, 0.63), 0.06)
	d.box("stone", Vector3(0, 0.17, 0.17), Vector3(0.7, 0.34, 0.34), c * 0.9)
	d.box("stone", Vector3(0, (spring + 0.34) * 0.5 - 0.1, 0.13), Vector3(0.5, spring - 0.34 - 0.2, 0.26), c)
	d.box("stone", Vector3(0, spring - 0.12, 0.16), Vector3(0.68, 0.24, 0.32), c * 1.1)
	return true


# Ribs across the room at the given boundaries (absolute coordinates along the axis), each springing from a
# pilaster on both long walls.
static func _vault(d: Deco, r, along_x: bool, bounds: Array, rise: float) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var spring := ht - rise
	var side_a := 1 if along_x else 3
	var side_b := 0 if along_x else 2
	for b in bounds:
		var ok_a := _pilaster(d, r, side_a, b, spring)
		var ok_b := _pilaster(d, r, side_b, b, spring)
		if not (ok_a and ok_b):
			continue
		d.f = _wt0(r)
		var p0: Vector3
		var p1: Vector3
		if along_x:
			p0 = Vector3(b, spring, inner.position.y - 0.05)
			p1 = Vector3(b, spring, inner.end.y + 0.05)
		else:
			p0 = Vector3(inner.position.x - 0.05, spring, b)
			p1 = Vector3(inner.end.x + 0.05, spring, b)
		d.arch("stone", p0, p1, rise - 0.04, 0.24, 0.34, Color(0.7, 0.7, 0.67))
		d.box("stone", (p0 + p1) * 0.5 + Vector3(0, rise - 0.12, 0), Vector3(0.3, 0.14, 0.3) if not along_x else Vector3(0.3, 0.14, 0.3),
				Color(0.8, 0.8, 0.76))


static func _lantern(d: Deco, pos: Vector3, ht: float, drop: float) -> void:
	var top := ht
	d.cyl("iron", Vector3(pos.x, top - drop * 0.5, pos.z), 0.012, 0.012, drop, IRON, 4)
	var y := top - drop - 0.22
	d.box("iron", Vector3(pos.x, y + 0.21, pos.z), Vector3(0.3, 0.035, 0.3), IRON)
	d.box("iron", Vector3(pos.x, y - 0.21, pos.z), Vector3(0.26, 0.035, 0.26), IRON)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			d.box("iron", Vector3(pos.x + sx * 0.12, y, pos.z + sz * 0.12), Vector3(0.025, 0.4, 0.025), IRON)
	d.box("g_flame", Vector3(pos.x, y, pos.z), Vector3(0.18, 0.28, 0.18))
	d.cyl("iron", Vector3(pos.x, y + 0.3, pos.z), 0.02, 0.24, 0.16, IRON, 4, Basis(Vector3.UP, PI / 4.0))


static func _sconce(d: Deco, x: float, y: float, key: String) -> void:
	d.box("iron", Vector3(x, y, 0.02), Vector3(0.1, 0.3, 0.03), IRON)
	d.box("iron", Vector3(x, y - 0.12, 0.1), Vector3(0.04, 0.04, 0.2), IRON)
	d.cyl("iron", Vector3(x, y - 0.08, 0.2), 0.08, 0.045, 0.12, IRON, 6)
	d.flame(Vector3(x, y + 0.03, 0.2), 1.3, key)


static func _brazier(d: Deco, x: float, z: float, light_range := 8.0, energy := 0.9, key := "g_flame") -> bool:
	if not d.fits(x, z, 0.9, 0.9):
		return false
	d.reserve(x, z, 0.9, 0.9)
	var iron := Color(0.22, 0.22, 0.25)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		d.cyl("iron", Vector3(x + cos(a) * 0.17, 0.4, z + sin(a) * 0.17), 0.025, 0.04, 0.8, iron, 5)
	d.cyl("iron", Vector3(x, 0.9, z), 0.3, 0.14, 0.22, iron, 10)
	d.ball(key, Vector3(x, 1.0, z), 0.2, Color.WHITE, Vector3(1, 1.7, 1), 6, 4)
	d.solid_cyl(Vector3(x, 0.5, z), 0.3, 1.0)
	if energy > 0.0:
		d.light(Vector3(x, 1.7, z), WARM if key == "g_flame" else GHOST, light_range, energy)
	return true


static func _bone_pile(d: Deco, r, wx: float, wz: float, rad := 0.5) -> bool:
	var saved := d.f
	d.f = _wt0(r)
	if not d.fits(wx, wz, rad * 2.2, rad * 2.2, 0.1):
		d.f = saved
		return false
	d.reserve(wx, wz, rad * 2.2, rad * 2.2)
	d.ball("plain", Vector3(wx, 0.02, wz), rad, Color(0.5, 0.47, 0.38), Vector3(1, 0.28, 1), 8, 3)
	for i in 8:
		var a := randf() * TAU
		var rr := randf() * rad * 0.7
		d.bone(Vector3(wx + cos(a) * rr, 0.07 + i * 0.012, wz + sin(a) * rr), _flat(randf() * PI), 0.4)
	for i in randi_range(1, 3):
		var a := randf() * TAU
		d.skull(Vector3(wx + cos(a) * rad * 0.4, 0.14, wz + sin(a) * rad * 0.4), 1.0, randf() * TAU, BONE.darkened(randf() * 0.2))
	d.spot(Vector3(wx, 0.07 + rad * 0.14 + 0.11, wz))
	d.f = saved
	return true


# A tall pointed alcove with a ledge for candles and a cross: the hallways' wayside shrine.
static func _shrine(d: Deco, r, side: int, a: float, lit: bool) -> bool:
	d.f = _wt(r, side, a)
	if not d.fits(0, 0.25, 1.5, 0.5):
		return false
	d.reserve(0, 0.25, 1.5, 0.5)
	var tr := Color(0.7, 0.7, 0.67)
	d.arch_panel("plain", Vector3(0, 1.9, 0.03), 0.62, 0.5, 0.2, DARK)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(sx * 0.7, 1.05, 0.08), Vector3(0.16, 2.1, 0.16), tr)
	d.arch("stone", Vector3(-0.7, 2.1, 0.08), Vector3(0.7, 2.1, 0.08), 0.55, 0.16, 0.16, tr)
	d.box("stone", Vector3(0, 0.95, 0.2), Vector3(1.4, 0.1, 0.4), tr * 1.1)
	d.box("stone", Vector3(0, 0.82, 0.14), Vector3(1.1, 0.16, 0.28), tr * 0.9)
	d.box("iron", Vector3(0, 1.72, 0.06), Vector3(0.07, 0.62, 0.03), IRON * 1.5)
	d.box("iron", Vector3(0, 1.84, 0.06), Vector3(0.36, 0.07, 0.03), IRON * 1.5)
	d.skull(Vector3(0.28, 1.04, 0.16), 1.0, -0.3)
	d.candle(Vector3(-0.5, 1.0, 0.18), 0.2)
	d.candle(Vector3(0.52, 1.0, 0.2), 0.14)
	d.spot(Vector3(-0.12, 1.11, 0.2))
	if lit:
		d.light(Vector3(0, 1.6, 0.6), WARM, 5.0, 0.8)
	return true


# --- Door surrounds and sconces ---

static func _doors(d: Deco, h, r) -> void:
	var ht: float = r.y1 - r.y0
	var door_h: float = h.door_h
	var tr := Color(0.66, 0.66, 0.63)
	for o in r.openings:
		if o["kind"] == "open":
			continue
		var side: int = o["side"]
		var lo: float = o["lo"]
		var hi: float = o["hi"]
		var half := (hi - lo) * 0.5
		d.f = _wt(r, side, (lo + hi) * 0.5)
		var spring := door_h + 0.3
		for sx in [-1.0, 1.0]:
			d.box("stone", Vector3(sx * (half + 0.32), spring * 0.5, 0.05), Vector3(0.2, spring, 0.1), tr)
		var rise := minf(half + 0.4, ht - spring - 0.15)
		if rise > 0.25:
			d.arch("stone", Vector3(-half - 0.32, spring, 0.05), Vector3(half + 0.32, spring, 0.05), rise, 0.2, 0.1, tr)
			d.box("stone", Vector3(0, spring + rise - 0.06, 0.06), Vector3(0.24, 0.3, 0.12), tr * 1.15)
		else:
			d.box("stone", Vector3(0, spring + 0.1, 0.05), Vector3(half * 2.0 + 0.84, 0.2, 0.1), tr)
		var ghostly: bool = r.type == "tomb"
		for c in h.conns:
			if c.get("b") != null and c["b"].type == "tomb" and c["a"] == r and c["side"] == side \
					and absf(float(c["lo"]) - lo) < 0.01:
				ghostly = true
		for sx in [-1.0, 1.0]:
			_sconce(d, sx * (half + 0.72), 1.75, "g_ghost" if ghostly else "g_flame")


# --- Decay: webs, roots, drips, puddles and rubble ---

static func _decay(d: Deco, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	# Cobwebs in the upper corners (one wall of each corner, so they never float in mid-air).
	for k in 4:
		var side: int = [0, 1, 2, 3][k]
		var rng := _side_range(r, side)
		for end_hi in [false, true]:
			if randf() < 0.45:
				continue
			var a: float = rng.y if end_hi else rng.x
			var other := a - 1.0 if end_hi else a + 1.0
			if _blocked(r, side, minf(a, other), maxf(a, other), 0.3):
				continue
			var sgn: float = _wt(r, side, 0.0).basis.x.dot(Vector3.RIGHT if side < 2 else Vector3.BACK)
			d.f = _wt(r, side, 0.0)
			var sz := randf_range(0.8, 1.2)
			var far := a - sz if end_hi else a + sz
			d.quad("web", Vector3(sgn * a, ht - 0.05, 0.02), Vector3(sgn * far, ht - 0.05, 0.02),
					Vector3(sgn * far, ht - 0.05 - sz, 0.02), Vector3(sgn * a, ht - 0.05 - sz, 0.02), Color(1, 1, 1, 0.9),
					[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	d.f = _wt0(r)
	# A crack in the ceiling with roots poking through.
	for k in (1 if (inner.size.x * inner.size.y) < 40.0 else 2):
		var p := Vector3(randf_range(inner.position.x + 0.8, inner.end.x - 0.8), ht - 0.045,
				randf_range(inner.position.y + 0.8, inner.end.y - 0.8))
		var yaw := randf() * PI
		var cur := p
		for i in 4:
			var nxt := cur + Vector3(cos(yaw), 0, sin(yaw)) * randf_range(0.25, 0.45)
			d.seg("plain", cur, nxt, 0.01, randf_range(0.04, 0.08), Color(0.01, 0.01, 0.01))
			if i > 0 and randf() < 0.8:
				var len_root := randf_range(0.35, 1.3)
				var tilt := Basis.from_euler(Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)))
				d.cyl("plain", cur + Vector3(0, -len_root * 0.5, 0), 0.03, 0.006, len_root, Color(0.2, 0.14, 0.09), 5, tilt)
			cur = nxt
			yaw += randf_range(-0.8, 0.8)
	# Dark water streaks down the wall with a puddle at their foot.
	for k in randi_range(1, 3):
		var side := randi_range(0, 3)
		var rng := _side_range(r, side)
		var a := randf_range(rng.x + 1.0, rng.y - 1.0)
		if _blocked(r, side, a - 0.6, a + 0.6, 0.3):
			continue
		d.f = _wt(r, side, a)
		var gh := minf(ht - 0.4, randf_range(1.8, 2.6))
		d.quad("grime", Vector3(-0.35, 0.3, 0.014), Vector3(0.35, 0.3, 0.014), Vector3(0.35, 0.3 + gh, 0.014),
				Vector3(-0.35, 0.3 + gh, 0.014), Color(0.4, 0.45, 0.45, 0.9),
				[Vector2(0.2, 0.9), Vector2(0.5, 0.9), Vector2(0.5, 0.0), Vector2(0.2, 0.0)])
		if d.fits(0, 0.7, 1.2, 1.0):
			d.cyl("puddle", Vector3(0, 0.01, 0.65), 0.55, 0.55, 0.012, Color.WHITE, 12, Basis.IDENTITY)
	# Puddles along the walls.
	for k in randi_range(1, 3):
		var side := randi_range(0, 3)
		var rng := _side_range(r, side)
		var a := randf_range(rng.x + 0.8, rng.y - 0.8)
		d.f = _wt(r, side, a)
		var rad := randf_range(0.3, 0.6)
		if d.fits(0, 0.8 + rad, rad * 2.0, rad * 2.0):
			d.ball("puddle", Vector3(0, 0.004, 0.8 + rad), rad, Color.WHITE, Vector3(1.3, 0.02, 1.0), 12, 2)
	# Rubble that has slid down along the walls.
	for k in clampi(int(inner.size.x * inner.size.y / 30.0), 1, 4):
		var side := randi_range(0, 3)
		var rng := _side_range(r, side)
		var a := randf_range(rng.x + 0.8, rng.y - 0.8)
		if _blocked(r, side, a - 0.7, a + 0.7, 0.3):
			continue
		d.f = _wt(r, side, a)
		if not d.fits(0, 0.4, 1.1, 0.8):
			continue
		d.reserve(0, 0.4, 1.0, 0.8)
		var sc := Color(0.3, 0.31, 0.29)
		d.box("stone", Vector3(0, 0.05, 0.4), Vector3(0.6, 0.1, 0.5), sc, Basis(Vector3.UP, randf_range(-0.4, 0.4)))
		for i in randi_range(5, 8):
			var s := randf_range(0.07, 0.2)
			d.box("stone", Vector3(randf_range(-0.45, 0.45), s * 0.4, randf_range(0.15, 0.7)), Vector3(s, s * 0.8, s * 1.2),
					_jit(sc, 0.2), Basis.from_euler(Vector3(randf(), randf() * TAU, randf())))
		d.spot(Vector3(0.05, 0.21, 0.4))


# --- Themed rooms ---

# Bone-lined catacomb hallway: even bays of niches between pilasters, ribs overhead, hanging lanterns.
static func _catacomb(d: Deco, h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var along_x := inner.size.x >= inner.size.y
	var length := inner.size.x if along_x else inner.size.y
	var width := inner.size.y if along_x else inner.size.x
	var lo := inner.position.x if along_x else inner.position.y
	var n := maxi(2, roundi(length / 3.2))
	var pitch := length / n
	var rise := minf(width * 0.22, ht * 0.3)
	var spring := ht - rise
	var bounds: Array = []
	for i in range(1, n):
		bounds.append(lo + pitch * i)
	_vault(d, r, along_x, bounds, rise)
	var long_sides: Array = [1, 0] if along_x else [3, 2]
	var mid := n / 2
	for side in long_sides:
		for i in n:
			var b0 := lo + pitch * i
			var b1 := b0 + pitch
			var bay_mid := (b0 + b1) * 0.5
			var is_shrine := i == mid
			var is_bench := (i == 1 or i == n - 2) and n >= 4 and i != mid
			if is_shrine and _shrine(d, r, side, bay_mid, side == long_sides[0]):
				continue
			var y_start := 0.5
			if is_bench and not _blocked(r, side, b0, b1, 0.5):
				d.f = _wt(r, side, bay_mid)
				if d.fits(0, 0.3, 1.9, 0.6):
					d.reserve(0, 0.3, 1.9, 0.6)
					d.sbox("stone", Vector3(0, 0.22, 0.3), Vector3(1.8, 0.44, 0.5), Color(0.55, 0.55, 0.53))
					d.box("stone", Vector3(0, 0.46, 0.3), Vector3(1.9, 0.06, 0.56), Color(0.7, 0.7, 0.67))
					d.spot(Vector3(0.3, 0.57, 0.3))
					y_start = 1.05
			_loculi_bay(d, r, side, b0, b1, y_start, spring - 0.1)
	# Hanging lanterns down the middle, lit in alternate bays.
	d.f = _wt0(r)
	var c := inner.get_center()
	for i in n:
		var t := lo + pitch * (i + 0.5)
		var pos := Vector3(t, 0, c.y) if along_x else Vector3(c.x, 0, t)
		_lantern(d, pos, ht - 0.04, 0.55)
		if i == roundi(n * 0.25) or i == roundi(n * 0.75) - 1:
			d.light(Vector3(pos.x, ht - 1.0, pos.z), WARM, 7.0, 0.75)
	# The short end walls get a memorial plaque.
	for side in ([2, 3] if along_x else [0, 1]):
		var rng := _side_range(r, side)
		var a := (rng.x + rng.y) * 0.5
		if _blocked(r, side, a - 1.2, a + 1.2, 0.8):
			continue
		d.f = _wt(r, side, a)
		d.box("stone", Vector3(0, 1.75, 0.04), Vector3(1.5, 0.95, 0.08), Color(0.72, 0.72, 0.68))
		d.box("stone", Vector3(0, 1.75, 0.09), Vector3(1.64, 0.1, 0.06), Color(0.55, 0.55, 0.52))
		d.label(Vector3(0, 1.78, 0.1), 0.0, "MEMENTO MORI\nWHAT YOU ARE\nWE WERE", 0.0042)
		d.skull(Vector3(0, 2.45, 0.1), 1.2)
	# Bone piles tucked against the pilasters.
	for k in 2:
		var side: int = long_sides[randi() % 2]
		var a := lo + pitch * float(randi_range(1, n - 1))
		var t := _wt(r, side, a)
		var wp := t * Vector3(0.9, 0, 0.55)
		_bone_pile(d, r, wp.x, wp.z, 0.4)


# --- Shared furniture ---

const NAMES := ["SIR OSRIC\nTHE DAMP", "LADY MAUDE\nBELOVED OF WORMS", "BROTHER ALDRIC\nHE SOAKED IN LIFE",
		"THE UNCLEAN KING", "OLD GRIMBALD\nKEEPER OF KEYS", "ABBESS ROSAMUND", "WILHELM\nTHE WET",
		"HERE LIES A\nVERY CLEAN MAN", "MARGERY BLACKSOAP", "THE LAST BATHER"]


static func _name_plate() -> String:
	return "%s\n%d - %d" % [NAMES[randi() % NAMES.size()], randi_range(900, 1100), randi_range(1120, 1300)]


# A stone sarcophagus in `frame` (long axis local x). `face` is the side (+1/-1 along local z) that carries the plaque.
static func _sarcophagus(d: Deco, frame: Transform3D, ajar: bool, face: float) -> bool:
	var saved := d.f
	d.f = frame
	if not d.fits(0, 0, 2.7, 1.4, 0.15):
		d.f = saved
		return false
	d.reserve(0, 0, 2.6, 1.3)
	var sc := _jit(Color(0.62, 0.62, 0.6), 0.08)
	d.box("stone", Vector3(0, 0.06, 0), Vector3(2.5, 0.12, 1.2), sc * 0.8)
	d.box("stone", Vector3(0, 0.45, 0), Vector3(2.3, 0.66, 1.0), sc)
	for sz in [-1.0, 1.0]:
		d.box("stone", Vector3(0, 0.45, sz * 0.505), Vector3(1.9, 0.4, 0.02), sc * 0.78)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(sx * 1.155, 0.45, 0), Vector3(0.02, 0.4, 0.6), sc * 0.78)
	var off := 0.3 if ajar else 0.0
	d.box("stone", Vector3(off, 0.85, 0), Vector3(2.4, 0.14, 1.1), sc * 1.1, Basis(Vector3.UP, 0.07 if ajar else 0.0))
	d.box("stone", Vector3(off, 0.93, 0), Vector3(2.0, 0.04, 0.72), sc * 1.15)
	d.box("plain", Vector3(off, 0.953, 0), Vector3(1.3, 0.01, 0.07), DARK)
	d.box("plain", Vector3(off + 0.3, 0.953, 0), Vector3(0.07, 0.01, 0.4), DARK)
	d.box("stone", Vector3(0, 0.46, face * 0.51), Vector3(0.9, 0.3, 0.025), sc * 1.25)
	d.label(Vector3(0, 0.46, face * 0.525), 0.0 if face > 0.0 else PI, _name_plate(), 0.0028)
	d.solid_box(Vector3(0, 0.475, 0), Vector3(2.4, 0.95, 1.1))
	d.spot(Vector3(-0.5, 1.06, 0))
	d.f = saved
	return true


# A plain wooden coffin on two stone trestles.
static func _coffin(d: Deco, frame: Transform3D, face: float) -> bool:
	var saved := d.f
	d.f = frame
	if not d.fits(0, 0, 2.4, 1.1, 0.15):
		d.f = saved
		return false
	d.reserve(0, 0, 2.3, 1.0)
	for sx in [-0.75, 0.75]:
		d.box("stone", Vector3(sx, 0.18, 0), Vector3(0.22, 0.36, 0.8), Color(0.5, 0.5, 0.48))
	var wd := Color(0.8, 0.8, 0.8)
	d.box("wood", Vector3(-0.35, 0.56, 0), Vector3(1.15, 0.4, 0.84), wd)
	d.box("wood", Vector3(0.65, 0.56, 0), Vector3(0.9, 0.4, 0.58), wd * 0.9)
	d.box("wood", Vector3(0.0, 0.8, 0.03), Vector3(2.15, 0.06, 0.9), wd * 1.1, Basis(Vector3.UP, 0.06))
	d.box("iron", Vector3(0, 0.835, 0.03), Vector3(0.08, 0.012, 0.6), IRON * 2.0)
	d.box("iron", Vector3(-0.3, 0.835, 0.03), Vector3(0.5, 0.012, 0.08), IRON * 2.0)
	d.label(Vector3(-0.35, 0.56, face * 0.43), 0.0 if face > 0.0 else PI, "R.I.P.\n" + NAMES[randi() % NAMES.size()].split("\n")[0],
			0.0026, Color(0.85, 0.8, 0.65))
	d.solid_box(Vector3(0, 0.6, 0), Vector3(2.2, 0.5, 0.9))
	d.spot(Vector3(-0.35, 0.95, 0))
	d.f = saved
	return true


static func _pew(d: Deco, frame: Transform3D, broken: bool) -> bool:
	var saved := d.f
	d.f = frame
	if not d.fits(0, 0, 2.9, 0.9, 0.05):
		d.f = saved
		return false
	d.reserve(0, 0, 2.8, 0.8)
	var wd := Color(0.85, 0.85, 0.85)
	if broken:
		d.box("wood", Vector3(-0.5, 0.12, 0), Vector3(1.5, 0.08, 0.45), wd, Basis.from_euler(Vector3(0.05, 0.1, 0.1)))
		d.box("wood", Vector3(0.7, 0.35, 0.1), Vector3(1.3, 0.06, 0.45), wd * 0.9, Basis.from_euler(Vector3(0.0, -0.2, 0.55)))
		d.box("wood", Vector3(-0.2, 0.2, 0.2), Vector3(1.2, 0.45, 0.06), wd * 0.8, Basis.from_euler(Vector3(1.2, 0.2, 0.1)))
		d.solid_box(Vector3(0, 0.3, 0), Vector3(2.6, 0.6, 0.6))
		d.f = saved
		return true
	d.box("wood", Vector3(0, 0.46, 0), Vector3(2.8, 0.08, 0.46), wd)
	d.box("wood", Vector3(0, 0.8, 0.25), Vector3(2.8, 0.55, 0.06), wd * 0.9)
	d.box("wood", Vector3(0, 0.12, -0.5), Vector3(2.6, 0.12, 0.3), wd * 0.8)
	for sx in [-1.35, 1.35]:
		d.box("wood", Vector3(sx, 0.5, 0.0), Vector3(0.1, 1.0, 0.62), wd * 0.75)
		d.box("wood", Vector3(sx, 1.03, 0.0), Vector3(0.14, 0.06, 0.66), wd * 0.65)
	d.solid_box(Vector3(0, 0.45, 0.02), Vector3(2.8, 0.9, 0.62))
	d.spot(Vector3(randf_range(-0.9, 0.9), 0.62, 0.0))
	d.f = saved
	return true


# Marble-ish slab table with a drainage channel; `body` lays a shrouded corpse on it.
static func _slab(d: Deco, frame: Transform3D, body: bool) -> bool:
	var saved := d.f
	d.f = frame
	if not d.fits(0, 0, 2.5, 1.1, 0.15):
		d.f = saved
		return false
	d.reserve(0, 0, 2.4, 1.0)
	for sx in [-0.9, 0.9]:
		d.box("stone", Vector3(sx, 0.4, 0), Vector3(0.22, 0.8, 0.72), Color(0.5, 0.5, 0.48))
	d.box("stone", Vector3(0, 0.89, 0), Vector3(2.3, 0.14, 0.95), Color(0.78, 0.78, 0.74))
	for sz in [-1.0, 1.0]:
		d.box("stone", Vector3(0, 0.975, sz * 0.43), Vector3(2.3, 0.03, 0.07), Color(0.7, 0.7, 0.66))
	d.box("plain", Vector3(0, 0.963, 0), Vector3(1.9, 0.01, 0.09), Color(0.1, 0.05, 0.05))
	d.solid_box(Vector3(0, 0.45, 0), Vector3(2.3, 0.9, 0.95))
	if body:
		var cloth := Color(0.72, 0.7, 0.6)
		d.box("plain", Vector3(0.1, 1.04, 0), Vector3(1.7, 0.14, 0.5), cloth, Basis(Vector3.UP, 0.02))
		d.ball("plain", Vector3(-0.78, 1.1, 0), 0.14, cloth * 1.05, Vector3(1.1, 0.9, 0.9), 6, 4)
		d.box("plain", Vector3(0.95, 1.07, 0), Vector3(0.3, 0.1, 0.3), cloth * 0.95)
		d.box("plain", Vector3(-0.2, 1.1, 0), Vector3(0.9, 0.06, 0.34), Color(0.45, 0.4, 0.3))
	else:
		d.spot(Vector3(0.6, 1.07, 0.1))
		d.box("iron", Vector3(-0.4, 0.99, -0.15), Vector3(0.3, 0.02, 0.06), IRON * 2.5, Basis(Vector3.UP, 0.4))
		d.box("iron", Vector3(-0.6, 0.99, 0.15), Vector3(0.2, 0.02, 0.05), IRON * 2.5, Basis(Vector3.UP, -0.3))
	d.f = saved
	return true


static func _column(d: Deco, x: float, z: float, ht_col: float) -> void:
	var c := _jit(Color(0.66, 0.66, 0.63), 0.06)
	d.box("stone", Vector3(x, 0.15, z), Vector3(1.05, 0.3, 1.05), c * 0.85)
	d.cyl("stone", Vector3(x, 0.4, z), 0.42, 0.5, 0.3, c * 0.95, 8)
	d.cyl("stone", Vector3(x, ht_col * 0.5 + 0.05, z), 0.36, 0.38, ht_col - 1.0, c, 10)
	d.cyl("stone", Vector3(x, ht_col - 0.3, z), 0.52, 0.36, 0.3, c * 1.05, 8)
	d.box("stone", Vector3(x, ht_col - 0.1, z), Vector3(1.0, 0.2, 1.0), c * 1.1)
	for row in 2:
		for k in 8:
			var a := TAU * (k + row * 0.5) / 8.0
			d.skull(Vector3(x + cos(a) * 0.4, 1.2 + row * 0.38, z + sin(a) * 0.4), 0.85, atan2(cos(a), sin(a)),
					BONE.darkened(0.1 + randf() * 0.15), false)
	d.solid_cyl(Vector3(x, ht_col * 0.5, z), 0.45, ht_col)


# A wall of stacked leg bones with a skull cross, framed in stone: the ossuary's showpiece.
static func _skull_wall(d: Deco, r, side: int, a: float, width: float, hgt: float) -> void:
	d.f = _wt(r, side, a)
	d.reserve(0, 0.3, width + 0.8, 0.6)
	var yb := 0.3
	var yt := yb + hgt
	var tr := Color(0.62, 0.62, 0.6)
	d.box("plain", Vector3(0, (yb + yt) * 0.5, 0.04), Vector3(width, hgt, 0.08), DARK)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(sx * (width * 0.5 + 0.15), (yb + yt) * 0.5 + 0.15, 0.17), Vector3(0.3, hgt + 0.4, 0.34), tr)
	d.box("stone", Vector3(0, yt + 0.15, 0.18), Vector3(width + 0.9, 0.3, 0.36), tr * 1.1)
	d.box("stone", Vector3(0, yb - 0.1, 0.2), Vector3(width + 0.7, 0.2, 0.4), tr * 0.9)
	var ry := yb + 0.06
	var row := 0
	while ry < yt - 0.05:
		var x := -width * 0.5 + 0.02
		while x < width * 0.5 - 0.1:
			var length := minf(randf_range(0.55, 0.85), width * 0.5 - x)
			d.cyl("plain", Vector3(x + length * 0.5, ry, 0.09 + randf() * 0.03), 0.03, 0.03, length,
					BONE.darkened(0.15 + 0.12 * float(row % 2) + randf() * 0.1), 5, Basis(Vector3.BACK, PI / 2.0))
			x += length + 0.01
		ry += 0.085
		row += 1
	var zs := 0.2
	for yy in range(0, int((hgt - 0.5) / 0.26) + 1):
		d.skull(Vector3(0, yb + 0.28 + yy * 0.26, zs), 1.0, 0.0, BONE, false)
	var arm_y := yb + hgt * 0.64
	for xi in range(-3, 4):
		if xi != 0:
			d.skull(Vector3(xi * 0.26, arm_y, zs), 1.0, 0.0, BONE, false)
	for xi in range(-int(width * 0.5 / 0.27) + 1, int(width * 0.5 / 0.27)):
		d.skull(Vector3(xi * 0.27, yb + 0.14, zs), 0.9, 0.0, BONE.darkened(0.12), false)
		d.skull(Vector3(xi * 0.27, yt - 0.14, zs), 0.9, 0.0, BONE.darkened(0.12), false)
	d.skull(Vector3(0, arm_y, zs + 0.03), 1.5, 0.0, BONE.lightened(0.05))
	for sx in [-1.0, 1.0]:
		d.ball("g_ghost", Vector3(sx * 0.05, arm_y + 0.02, zs + 0.17), 0.026, Color.WHITE, Vector3.ONE, 5, 3)
	d.light(Vector3(0, arm_y, 1.3), GHOST, 5.5, 0.55)


static func _chandelier(d: Deco, x: float, z: float, ht: float, key := "g_flame") -> void:
	var y := ht - 1.5
	d.cyl("iron", Vector3(x, ht - 0.75, z), 0.012, 0.012, 1.5, IRON, 4)
	d.ball("iron", Vector3(x, y, z), 0.12, IRON * 2.0, Vector3.ONE, 6, 4)
	var rad := 0.6
	for k in 10:
		var a := TAU * k / 10.0
		var p := Vector3(x + cos(a) * rad, y - 0.08, z + sin(a) * rad)
		d.bone(p, _flat(PI / 2.0 - a), 0.4)
		if k % 2 == 0:
			d.candle(p + Vector3(0, 0.02, 0), 0.16)
		else:
			d.skull(p + Vector3(0, -0.12, 0), 0.7, atan2(cos(a), sin(a)))
	for k in 4:
		var a := TAU * k / 4.0
		d.seg("iron", Vector3(x, y, z), Vector3(x + cos(a) * rad, y - 0.08, z + sin(a) * rad), 0.03, 0.03, IRON * 2.0)
	d.flame(Vector3(x, y + 0.2, z), 2.0, key)


static func _urn(d: Deco, x: float, z: float) -> bool:
	if not d.fits(x, z, 0.7, 0.7, 0.1):
		return false
	d.reserve(x, z, 0.6, 0.6)
	var sc := Color(0.6, 0.6, 0.58)
	d.sbox("stone", Vector3(x, 0.4, z), Vector3(0.5, 0.8, 0.5), sc)
	d.box("stone", Vector3(x, 0.82, z), Vector3(0.6, 0.06, 0.6), sc * 1.15)
	var clay := Color(0.42, 0.22, 0.14)
	d.ball("plain", Vector3(x, 1.08, z), 0.22, clay, Vector3(1, 1.15, 1), 8, 5)
	d.cyl("plain", Vector3(x, 1.38, z), 0.13, 0.09, 0.14, clay * 1.1, 8)
	d.box("plain", Vector3(x, 1.08, z + 0.2), Vector3(0.3, 0.05, 0.03), Color(0.75, 0.6, 0.3))
	return true


static func _wreath(d: Deco, x: float, y: float) -> void:
	d.ring("plain", Vector3(x, y, 0.06), 0.28, 0.055, Color(0.1, 0.26, 0.1), 14)
	for k in 5:
		var a := TAU * (k + 0.5) / 5.0
		d.ball("plain", Vector3(x + cos(a) * 0.28, y + sin(a) * 0.28, 0.1), 0.03, Color(0.6, 0.08, 0.1), Vector3.ONE, 4, 3)
	d.box("plain", Vector3(x, y - 0.3, 0.06), Vector3(0.1, 0.24, 0.02), Color(0.45, 0.05, 0.08))


# Stone guardian with a greatsword planted at its feet, in the current frame.
static func _guardian(d: Deco, x: float, z: float) -> void:
	var sc := Color(0.74, 0.74, 0.72)
	d.sbox("stone", Vector3(x, 0.22, z), Vector3(0.85, 0.44, 0.85), sc * 0.8)
	d.cyl("stone", Vector3(x, 1.0, z), 0.2, 0.3, 1.1, sc, 9)
	d.box("stone", Vector3(x, 1.62, z), Vector3(0.62, 0.16, 0.32), sc * 1.05)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(x + sx * 0.31, 1.34, z + 0.1), Vector3(0.12, 0.55, 0.14), sc, Basis.from_euler(Vector3(-0.3, 0, -sx * 0.1)))
	d.ball("stone", Vector3(x, 1.86, z), 0.14, sc * 1.05, Vector3(1, 1.1, 1), 7, 4)
	d.cyl("stone", Vector3(x, 2.07, z), 0.02, 0.15, 0.26, sc * 0.95, 8)
	d.box("plain", Vector3(x, 1.88, z + 0.13), Vector3(0.18, 0.025, 0.03), DARK)
	d.box("stone", Vector3(x, 1.12, z + 0.27), Vector3(0.07, 1.25, 0.025), sc * 0.55)
	d.box("stone", Vector3(x, 1.68, z + 0.27), Vector3(0.38, 0.06, 0.05), sc * 0.55)
	d.ball("stone", Vector3(x, 1.76, z + 0.27), 0.05, sc * 0.6, Vector3.ONE, 5, 3)
	d.solid_cyl(Vector3(x, 1.1, z), 0.42, 2.2)


# A weeping stone angel on a plinth; the broken one has lost its head and half a wing.
static func _angel(d: Deco, x: float, z: float, broken: bool) -> bool:
	if not d.fits(x, z, 1.2, 1.2, 0.1):
		return false
	d.reserve(x, z, 1.2, 1.2)
	var sc := Color(0.76, 0.77, 0.76)
	d.sbox("stone", Vector3(x, 0.5, z), Vector3(0.95, 1.0, 0.95), sc * 0.75)
	d.box("stone", Vector3(x, 1.02, z), Vector3(1.05, 0.08, 1.05), sc * 0.9)
	d.cyl("stone", Vector3(x, 1.8, z), 0.2, 0.34, 1.5, sc, 9)
	d.box("stone", Vector3(x, 2.5, z), Vector3(0.52, 0.14, 0.28), sc * 1.05)
	d.box("stone", Vector3(x, 2.05, z + 0.2), Vector3(0.16, 0.36, 0.1), sc * 0.95, Basis.from_euler(Vector3(-0.3, 0, 0)))
	for sx in [-1.0, 1.0]:
		var wing_len := 0.7 if (broken and sx > 0.0) else 1.5
		d.box("stone", Vector3(x + sx * 0.32, 2.45 + (0.0 if broken and sx > 0.0 else 0.0), z - 0.28), Vector3(0.07, wing_len, 0.55) ,
				sc * 0.95, Basis.from_euler(Vector3(-0.15, 0, -sx * 0.45)))
	if broken:
		d.ball("stone", Vector3(x + 0.7, 0.1, z + 0.6), 0.14, sc, Vector3(1, 1.1, 1), 7, 4)
		d.box("stone", Vector3(x + 0.25, 0.06, z + 0.55), Vector3(0.3, 0.12, 0.2), sc * 0.8, Basis(Vector3.UP, 0.5))
		d.box("plain", Vector3(x, 1.9, z + 0.32), Vector3(0.02, 0.7, 0.01), DARK, Basis.from_euler(Vector3(0, 0, 0.35)))
	else:
		d.ball("stone", Vector3(x, 2.72, z), 0.14, sc * 1.05, Vector3(1, 1.1, 1), 7, 4)
		d.ring("g_ghost", Vector3(x, 2.98, z), 0.2, 0.012, Color.WHITE, 14, Basis(Vector3.RIGHT, PI / 2.0))
	d.solid_cyl(Vector3(x, 1.5, z), 0.5, 3.0)
	return true


# A stained-glass lancet window: stone surround, glowing pane and iron bars.
static func _window(d: Deco, x: float, y_bottom: float, y_spring: float, hw: float, key: String) -> void:
	var tr := Color(0.7, 0.7, 0.67)
	d.arch_panel(key, Vector3(x, y_spring, 0.025), hw, 0.55, y_bottom, Color.WHITE)
	for sx in [-1.0, 1.0]:
		d.box("stone", Vector3(x + sx * (hw + 0.07), (y_bottom + y_spring) * 0.5, 0.07), Vector3(0.14, y_spring - y_bottom, 0.14), tr)
	d.arch("stone", Vector3(x - hw - 0.07, y_spring, 0.07), Vector3(x + hw + 0.07, y_spring, 0.07), 0.6, 0.14, 0.14, tr)
	d.box("stone", Vector3(x, y_bottom - 0.05, 0.1), Vector3(hw * 2.0 + 0.4, 0.1, 0.2), tr * 1.1)
	d.box("iron", Vector3(x, (y_bottom + y_spring) * 0.5 + 0.3, 0.05), Vector3(0.04, y_spring - y_bottom + 0.9, 0.03), IRON * 2.0)
	for k in 3:
		d.box("iron", Vector3(x, y_bottom + 0.5 + k * 0.6, 0.05), Vector3(hw * 2.0, 0.035, 0.03), IRON * 2.0)


# Finds room on a wall for a freestanding wall piece, trying the centre first, then shifting along the wall.
# Leaves `d.f` on the wall frame at the item's centre and reserves the footprint.
static func _slot(d: Deco, r, side: int, width: float, depth: float) -> bool:
	var rng := _side_range(r, side)
	var mid := (rng.x + rng.y) * 0.5
	var reach := (rng.y - rng.x) * 0.5 - width * 0.5 - 0.5
	if reach < 0.0:
		return false
	var offs: Array[float] = [0.0]
	var o := 0.8
	while o <= reach:
		offs.append(o)
		offs.append(-o)
		o += 0.8
	for off in offs:
		var a: float = mid + off
		if _blocked(r, side, a - width * 0.5 - 0.3, a + width * 0.5 + 0.3, 0.3):
			continue
		d.f = _wt(r, side, a)
		if d.fits(0, depth * 0.5, width, depth, 0.1):
			d.reserve(0, depth * 0.5, width, depth)
			return true
	return false


static func _runner(d: Deco, x0: float, x1: float, z: float, width: float) -> void:
	var tile := width
	d.quad("runner", Vector3(x0, 0.017, z - width * 0.5), Vector3(x1, 0.017, z - width * 0.5),
			Vector3(x1, 0.017, z + width * 0.5), Vector3(x0, 0.017, z + width * 0.5), Color.WHITE,
			[Vector2(0, 0), Vector2(0, (x1 - x0) / tile), Vector2(1, (x1 - x0) / tile), Vector2(1, 0)])


static func _rune_ring(d: Deco, radius: float, count: int, y: float) -> void:
	for k in count:
		var a := TAU * k / count
		var p0 := Vector3(cos(a) * radius, y, sin(a) * radius)
		var p1 := Vector3(cos(a + TAU / count) * radius, y, sin(a + TAU / count) * radius)
		d.seg("g_ghost", p0, p1, 0.012, 0.05, Color.WHITE)


# --- Rooms ---

# Columned ossuary: two rows of thick bone-banded columns under ribbed vaults, niche-lined walls, a skull wall.
static func _ossuary(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var along_x := inner.size.x >= inner.size.y
	var length := inner.size.x if along_x else inner.size.y
	var width := inner.size.y if along_x else inner.size.x
	var ax := _axis_frame(r, along_x)
	var zc := clampf(width * 0.5 - 2.3, 1.9, 2.8)
	var n := maxi(2, roundi((length - 2.6) / 3.4) + 1)
	var sp := (length - 2.6) / (n - 1)
	var spring := ht - 1.2
	var xs: Array[float] = []
	for i in n:
		xs.append(-(length - 2.6) * 0.5 + i * sp)
	var wall_sides: Array = [1, 0] if along_x else [3, 2]
	var stone := Color(0.7, 0.7, 0.67)
	var placed := {}
	d.f = ax
	for i in n:
		for sgn in [-1.0, 1.0]:
			if d.fits(xs[i], sgn * zc, 1.1, 1.1, 0.05):
				d.reserve(xs[i], sgn * zc, 1.1, 1.1)
				_column(d, xs[i], sgn * zc, spring)
				placed[[i, sgn]] = true
	for i in n:
		if placed.has([i, -1.0]) and placed.has([i, 1.0]):
			d.arch("stone", Vector3(xs[i], spring, -zc), Vector3(xs[i], spring, zc), 1.1, 0.26, 0.4, stone)
		for sgn in [-1.0, 1.0]:
			if placed.has([i, sgn]) and i + 1 < n and placed.has([i + 1, sgn]):
				d.arch("stone", Vector3(xs[i], spring, sgn * zc), Vector3(xs[i + 1], spring, sgn * zc), 1.0, 0.26, 0.4, stone)
			if placed.has([i, sgn]):
				var ab := ax * Vector3(xs[i], 0, 0)
				var wall_side: int = wall_sides[0] if sgn < 0.0 else wall_sides[1]
				if _pilaster(d, r, wall_side, ab.x if along_x else ab.z, spring):
					d.f = ax
					d.arch("stone", Vector3(xs[i], spring, sgn * zc), Vector3(xs[i], spring, sgn * (width * 0.5 + 0.05)),
							0.9, 0.26, 0.4, stone)
				d.f = ax
	# Niche tiers above a skull shelf (or a sarcophagus) in every bay of both long walls.
	var sar_bays: Array = [0, n - 2] if n > 2 else [0]
	for si in 2:
		var side: int = wall_sides[si]
		for i in n - 1:
			var ab0 := ax * Vector3(xs[i], 0, 0)
			var ab1 := ax * Vector3(xs[i + 1], 0, 0)
			var b0: float = ab0.x if along_x else ab0.z
			var b1: float = ab1.x if along_x else ab1.z
			if b0 > b1:
				var tmp := b0
				b0 = b1
				b1 = tmp
			_loculi_bay(d, r, side, b0, b1, 1.4, spring - 0.1)
			var xm := (xs[i] + xs[i + 1]) * 0.5
			var zz := (width * 0.5 - 1.0) * (-1.0 if si == 0 else 1.0)
			var done := false
			if i in sar_bays:
				var fr := ax * Transform3D(Basis.IDENTITY, Vector3(xm, 0, zz))
				done = _sarcophagus(d, fr, i == 0 and randf() < 0.5, 1.0 if si == 0 else -1.0)
			if not done and not _blocked(r, side, b0, b1, 0.5):
				d.f = _wt(r, side, (b0 + b1) * 0.5)
				if d.fits(0, 0.2, 2.0, 0.4):
					d.reserve(0, 0.2, 2.0, 0.4)
					d.box("stone", Vector3(0, 0.5, 0.17), Vector3(2.0, 0.08, 0.34), Color(0.6, 0.6, 0.58))
					d.box("stone", Vector3(0, 0.25, 0.1), Vector3(1.8, 0.5, 0.2), Color(0.45, 0.45, 0.43))
					for k in 5:
						if k != 2:
							d.skull(Vector3(-0.8 + k * 0.4, 0.6, 0.2), 1.0, randf_range(-0.3, 0.3))
					d.spot(Vector3(0, 0.61, 0.2))
	# The skull wall faces the entrance end; braziers flank it.
	var end_sides: Array = [2, 3] if along_x else [0, 1]
	end_sides.shuffle()
	var sw_w := minf(width - 1.8, 7.0)
	for side in end_sides:
		var rng := _side_range(r, side)
		var a := (rng.x + rng.y) * 0.5
		if _blocked(r, side, a - sw_w * 0.5 - 1.6, a + sw_w * 0.5 + 1.6, 0.3):
			continue
		d.f = _wt(r, side, a)
		if not d.fits(0, 0.3, sw_w + 0.8, 0.6):
			continue
		_skull_wall(d, r, side, a, sw_w, minf(3.4, ht - 1.3))
		d.f = _wt(r, side, a)
		for sx in [-1.0, 1.0]:
			_brazier(d, sx * (sw_w * 0.5 + 0.95), 0.9, 7.5, 0.9)
		break
	d.f = ax
	_runner(d, -length * 0.5 + 0.5, length * 0.5 - 0.5, 0.0, 2.2)
	for sgn in [-1.0, 1.0]:
		_chandelier(d, sgn * length * 0.25, 0.0, ht - 0.04)
		d.light(Vector3(sgn * length * 0.25, ht - 2.0, 0.0), WARM, 8.0, 0.8)
	for k in 3:
		var cs: float = 1.0 if randf() < 0.5 else -1.0
		var zs: float = 1.0 if randf() < 0.5 else -1.0
		var wp := ax * Vector3(cs * (length * 0.5 - 0.9), 0, zs * (width * 0.5 - 0.9))
		_bone_pile(d, r, wp.x, wp.z, 0.45)


static func _chapel(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var sides: Array = [0, 1, 2, 3]
	sides.shuffle()
	var aside := -1
	for s in sides:
		var rg := _side_range(r, s)
		var c := (rg.x + rg.y) * 0.5
		if not _blocked(r, s, c - 4.3, c + 4.3, 0.5):
			aside = s
			break
	var altar_ok := aside >= 0
	if not altar_ok:
		aside = sides[0]
	var rg2 := _side_range(r, aside)
	var af := _wt(r, aside, (rg2.x + rg2.y) * 0.5)
	var depth := inner.size.y if aside < 2 else inner.size.x
	var wd := inner.size.x if aside < 2 else inner.size.y
	var along_x := aside >= 2
	var lat_sides: Array = [1, 0] if along_x else [3, 2]
	var nb := maxi(3, roundi(depth / 3.6))
	var pitch := depth / nb
	var rise := minf(wd * 0.15, 1.9)
	var spring := ht - rise
	var edges: Array[float] = []
	for k in range(0, nb + 1):
		var p := af.origin + af.basis.z * (pitch * k)
		edges.append(p.x if along_x else p.z)
	var bounds: Array = []
	for k in range(1, nb):
		bounds.append(edges[k])
	_vault(d, r, along_x, bounds, rise)
	var keys := ["g_blue", "g_violet", "g_teal", "g_blue"]
	for side in lat_sides:
		for k in nb:
			var b0 := minf(edges[k], edges[k + 1])
			var b1 := maxf(edges[k], edges[k + 1])
			if _blocked(r, side, b0, b1, 0.5):
				continue
			d.f = _wt(r, side, (b0 + b1) * 0.5)
			_window(d, 0.0, 1.9, spring - 0.9, 0.5, keys[randi() % keys.size()])
	d.f = af
	if altar_ok and d.fits(0, 1.7, 7.4, 3.4):
		d.reserve(0, 1.7, 7.4, 3.4)
		var st := Color(0.55, 0.55, 0.53)
		d.sbox("stone", Vector3(0, 0.04, 1.7), Vector3(7.2, 0.08, 3.4), st * 0.85)
		d.sbox("stone", Vector3(0, 0.08, 1.4), Vector3(6.4, 0.16, 2.8), st * 0.95)
		d.sbox("stone", Vector3(0, 0.12, 1.1), Vector3(5.6, 0.24, 2.2), st)
		d.sbox("stone", Vector3(0, 0.69, 1.0), Vector3(2.8, 0.9, 1.0), Color(0.64, 0.64, 0.62))
		d.box("stone", Vector3(0, 1.2, 1.0), Vector3(3.0, 0.12, 1.2), Color(0.72, 0.72, 0.7))
		d.box("plain", Vector3(0, 1.266, 1.0), Vector3(2.5, 0.012, 0.85), Color(0.35, 0.04, 0.06))
		d.box("stone", Vector3(0, 0.72, 1.52), Vector3(2.2, 0.55, 0.03), Color(0.5, 0.5, 0.48))
		d.box("g_ghost", Vector3(0, 0.72, 1.54), Vector3(0.08, 0.4, 0.01))
		d.box("g_ghost", Vector3(0, 0.78, 1.54), Vector3(0.34, 0.07, 0.01))
		d.box("plain", Vector3(0, 1.29, 1.0), Vector3(0.5, 0.04, 0.34), Color(0.65, 0.6, 0.45), Basis(Vector3.UP, 0.15))
		for sx in [-1.0, 1.0]:
			d.cyl("iron", Vector3(sx * 1.2, 1.5, 1.0), 0.03, 0.05, 0.5, IRON * 2.0, 6)
			d.box("iron", Vector3(sx * 1.2, 1.76, 1.0), Vector3(0.4, 0.03, 0.05), IRON * 2.0)
			for k in 3:
				d.candle(Vector3(sx * 1.2 - 0.15 + k * 0.15, 1.77, 1.0), 0.14 + 0.05 * (k % 2))
		d.spot(Vector3(-0.6, 1.38, 1.0))
		d.spot(Vector3(0.6, 1.38, 1.0))
		d.spot(Vector3(-3.0, 0.19, 3.1))
		d.spot(Vector3(3.0, 0.19, 3.1))
		for sx in [-1.0, 1.0]:
			d.candle(Vector3(sx * 3.35, 0.08, 3.15), 0.2)
			d.candle(Vector3(sx * 3.15, 0.08, 3.3), 0.12)
		# Wall behind the altar: cross, red drapes, a rose window and two lancets.
		d.box("iron", Vector3(0, 2.4, 0.05), Vector3(0.14, 1.5, 0.06), IRON * 1.6)
		d.box("iron", Vector3(0, 2.8, 0.05), Vector3(0.8, 0.14, 0.06), IRON * 1.6)
		for sx in [-1.0, 1.0]:
			d.box("plain", Vector3(sx * 1.5, 2.3, 0.04), Vector3(0.7, 2.7, 0.04), Color(0.38, 0.05, 0.08))
			d.box("iron", Vector3(sx * 1.5, 3.68, 0.05), Vector3(0.8, 0.05, 0.06), IRON * 2.0)
		var rc := Vector3(0, 4.15, 0.03)
		var rose := ["g_blue", "g_violet", "g_teal", "g_violet"]
		for k in 12:
			var a0 := TAU * k / 12.0
			var a1 := TAU * (k + 1) / 12.0
			d.quad(rose[k % 4], rc + Vector3(cos(a0) * 0.16, sin(a0) * 0.16, 0), rc + Vector3(cos(a1) * 0.16, sin(a1) * 0.16, 0),
					rc + Vector3(cos(a1) * 0.88, sin(a1) * 0.88, 0), rc + Vector3(cos(a0) * 0.88, sin(a0) * 0.88, 0))
			d.seg("stone", rc + Vector3(cos(a0) * 0.16, sin(a0) * 0.16, 0.03), rc + Vector3(cos(a0) * 0.9, sin(a0) * 0.9, 0.03),
					0.05, 0.07, Color(0.7, 0.7, 0.67))
		d.cyl("g_amber", rc + Vector3(0, 0, 0.01), 0.17, 0.17, 0.02, Color.WHITE, 10, Basis(Vector3.RIGHT, PI / 2.0))
		for k in 24:
			var a0 := TAU * k / 24.0
			var a1 := TAU * (k + 1) / 24.0
			d.seg("stone", rc + Vector3(cos(a0) * 1.0, sin(a0) * 1.0, 0.05), rc + Vector3(cos(a1) * 1.0, sin(a1) * 1.0, 0.05),
					0.14, 0.12, Color(0.72, 0.72, 0.69))
		for sx in [-1.0, 1.0]:
			_window(d, sx * 3.1, 2.1, 3.9, 0.5, "g_blue")
		d.light(Vector3(0, 3.6, 2.2), Color(0.45, 0.6, 1.0), 9.0, 0.7)
		d.light(Vector3(0, 2.2, 1.4), WARM, 6.0, 0.9)
		_angel(d, -(wd * 0.5 - 1.0), 0.9, false)
		_angel(d, wd * 0.5 - 1.0, 0.9, true)
	# Pews flanking a central aisle, with the odd broken one.
	var z := 5.0
	while z < depth - 3.0:
		for sx in [-1.0, 1.0]:
			var fr := af * Transform3D(Basis.IDENTITY, Vector3(sx * 2.5, 0, z))
			_pew(d, fr, randf() < 0.1)
		z += 1.5
	# Aisle runner and braziers at the foot of the steps, lanterns over the pews.
	d.f = af
	d.quad("runner", Vector3(-1.0, 0.017, 3.6), Vector3(-1.0, 0.017, depth - 0.8), Vector3(1.0, 0.017, depth - 0.8),
			Vector3(1.0, 0.017, 3.6), Color.WHITE, [Vector2(0, 0), Vector2((depth - 4.4) / 2.0, 0), Vector2((depth - 4.4) / 2.0, 1), Vector2(0, 1)])
	if altar_ok:
		for sx in [-1.0, 1.0]:
			_brazier(d, sx * 1.9, 4.0, 8.5, 0.95)
	for lz in [6.2, 9.2]:
		if lz < depth - 1.5:
			for sx in [-1.0, 1.0]:
				_lantern(d, Vector3(sx * 2.5, 0, lz), ht - 0.04, 1.8)
	for k in 2:
		var cs: float = 1.0 if randf() < 0.5 else -1.0
		var wp := af * Vector3(cs * (wd * 0.5 - 0.8), 0, depth - 0.9)
		_bone_pile(d, r, wp.x, wp.z, 0.42)


static func _burial_chamber(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var ds := 0 if r.openings.is_empty() else int(r.openings[0]["side"])
	var far := ds ^ 1
	var rg := _side_range(r, far)
	var c := (rg.x + rg.y) * 0.5
	var wf := _wt(r, far, c)
	var depth := inner.size.y if far < 2 else inner.size.x
	var wd := inner.size.x if far < 2 else inner.size.y
	var along_x := far >= 2
	var rise := minf(wd * 0.2, ht * 0.3)
	var p_mid := wf.origin + wf.basis.z * (depth * 0.5)
	var mid_b := p_mid.x if along_x else p_mid.z
	_vault(d, r, along_x, [mid_b], rise)
	var lat: Array = [1, 0] if along_x else [3, 2]
	var e0 := wf.origin + wf.basis.z * 0.0
	var e1 := wf.origin + wf.basis.z * depth
	var a0 := minf(e0.x if along_x else e0.z, e1.x if along_x else e1.z)
	var a1 := maxf(e0.x if along_x else e0.z, e1.x if along_x else e1.z)
	for side in lat:
		_loculi_bay(d, r, side, a0, mid_b if a0 < mid_b else a1, 0.5, ht - rise - 0.1)
		_loculi_bay(d, r, side, mid_b if a0 < mid_b else a0, a1 if a0 < mid_b else mid_b, 0.5, ht - rise - 0.1)
	_shrine(d, r, far, c, true)
	d.f = wf
	var stone_first := randf() < 0.65
	for k in 2:
		var sx := -1.45 if k == 0 else 1.45
		var fr := wf * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(sx, 0, 2.4))
		var face := 1.0 if sx < 0.0 else -1.0
		if k == 0 or stone_first:
			_sarcophagus(d, fr, k == 1, face)
		else:
			_coffin(d, fr, face)
	d.f = wf
	for sx in [-1.0, 1.0]:
		_urn(d, sx * (wd * 0.5 - 0.55), 0.6)
		_wreath(d, sx * 1.55, 1.9)
	d.quad("runner", Vector3(-0.55, 0.017, 0.7), Vector3(0.55, 0.017, 0.7), Vector3(0.55, 0.017, depth - 1.3),
			Vector3(-0.55, 0.017, depth - 1.3), Color.WHITE, [Vector2(0, 0), Vector2(1, 0), Vector2(1, (depth - 2.0) / 1.1), Vector2(0, (depth - 2.0) / 1.1)])
	_lantern(d, Vector3(0, 0, depth * 0.5 + 0.3), ht - 0.04, 0.6)
	d.ball("g_ghost", Vector3(-1.45, 1.5, 2.4), 0.07, Color.WHITE, Vector3(1, 1.4, 1), 6, 4)
	d.ball("g_ghost", Vector3(-1.35, 1.3, 2.7), 0.035, Color.WHITE, Vector3.ONE, 5, 3)
	d.light(Vector3(-1.45, 1.6, 2.4), GHOST, 4.2, 0.55)


static func _embalming_room(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var along_x := inner.size.x >= inner.size.y
	var length := inner.size.x if along_x else inner.size.y
	var width := inner.size.y if along_x else inner.size.x
	var ax := _axis_frame(r, along_x)
	var lo := inner.position.x if along_x else inner.position.y
	var tile_trim := Color(0.62, 0.62, 0.6)
	for side in 4:
		for seg in _segments(r, side, 0.25):
			d.f = _wt(r, side, (seg.x + seg.y) * 0.5)
			d.box("tile", Vector3(0, 0.82, 0.02), Vector3(seg.y - seg.x, 1.06, 0.04), Color.WHITE)
			d.box("stone", Vector3(0, 1.38, 0.04), Vector3(seg.y - seg.x, 0.06, 0.08), tile_trim)
	var n := maxi(2, roundi(length / 3.2))
	var bounds: Array = []
	for i in range(1, n):
		bounds.append(lo + length / n * i)
	_vault(d, r, along_x, bounds, minf(width * 0.18, ht * 0.28))
	d.f = ax
	var tz: Array = [-1.5, 1.5] if width >= 6.0 else [-1.2]
	var first := true
	for z in tz:
		var fr := ax * Transform3D(Basis.IDENTITY, Vector3(0, 0, z))
		var ok := _slab(d, fr, first)
		first = false
		d.f = ax
		if ok:
			_lantern(d, Vector3(0, 0, z), ht - 0.04, 0.9, )
			d.light(Vector3(0, ht - 1.4, z), Color(0.7, 1.0, 0.85), 6.5, 0.7)
		var bx := 1.55
		if d.fits(bx, z + 0.15, 0.5, 0.5):
			d.reserve(bx, z + 0.15, 0.5, 0.5)
			d.cyl("iron", Vector3(bx, 0.16, z + 0.15), 0.2, 0.16, 0.32, IRON * 2.2, 8)
			d.ball("puddle", Vector3(bx, 0.3, z + 0.15), 0.18, Color.WHITE, Vector3(1, 0.1, 1), 8, 2)
	# Drain between the tables.
	d.cyl("iron", Vector3(0, 0.012, 0.0), 0.28, 0.28, 0.02, IRON * 2.0, 12)
	for k in 4:
		d.box("plain", Vector3(0, 0.024, 0), Vector3(0.5, 0.01, 0.04), DARK, Basis(Vector3.UP, PI * k / 4.0))
	d.ball("puddle", Vector3(0.1, 0.004, 0.0), 0.7, Color.WHITE, Vector3(1.2, 0.02, 1.0), 12, 2)
	# Shelves of jars, a tool rack and a stone trough along the walls.
	var sides: Array = [0, 1, 2, 3]
	sides.shuffle()
	var used_shelf := false
	var used_rack := false
	var used_trough := false
	for side in sides:
		if not used_shelf and _slot(d, r, side, 2.4, 0.55):
			used_shelf = true
			d.solid_box(Vector3(0, 1.0, 0.27), Vector3(2.4, 2.0, 0.5))
			for post in [-1.15, 1.15]:
				d.box("wood", Vector3(post, 1.0, 0.27), Vector3(0.08, 2.0, 0.5), Color(0.8, 0.8, 0.8))
			for k in 3:
				var sy := 0.5 + k * 0.58
				d.box("wood", Vector3(0, sy, 0.27), Vector3(2.4, 0.05, 0.5), Color(0.9, 0.9, 0.9))
				for j in 6:
					var jx := -0.95 + j * 0.38
					var key: String = ["g_ghost", "g_amber", "plain", "g_teal"][(j + k) % 4]
					d.cyl(key, Vector3(jx, sy + 0.17, 0.27), 0.09, 0.09, 0.28, Color(0.85, 0.8, 0.65) if key == "plain" else Color.WHITE, 8)
					d.cyl("iron", Vector3(jx, sy + 0.33, 0.27), 0.1, 0.1, 0.04, IRON * 2.0, 8)
			d.spot(Vector3(0.38, 0.65, 0.27))
			d.light(Vector3(0, 1.7, 0.7), GHOST, 3.5, 0.4)
		elif not used_trough and _slot(d, r, side, 1.7, 0.7):
			used_trough = true
			d.sbox("stone", Vector3(0, 0.42, 0.35), Vector3(1.6, 0.84, 0.62), Color(0.62, 0.62, 0.6))
			d.box("puddle", Vector3(0, 0.845, 0.35), Vector3(1.3, 0.02, 0.4))
			d.cyl("iron", Vector3(0.5, 1.15, 0.1), 0.03, 0.03, 0.5, IRON * 2.2, 6)
			d.box("iron", Vector3(0.5, 1.38, 0.2), Vector3(0.05, 0.05, 0.22), IRON * 2.2)
			d.spot(Vector3(-0.55, 0.96, 0.35))
		elif not used_rack and _slot(d, r, side, 2.0, 0.15):
			used_rack = true
			d.box("wood", Vector3(0, 1.7, 0.04), Vector3(2.0, 0.9, 0.05), Color(0.8, 0.8, 0.8))
			for k in 6:
				var tx := -0.8 + k * 0.32
				d.cyl("iron", Vector3(tx, 1.9, 0.09), 0.012, 0.012, 0.1, IRON * 2.5, 4, Basis(Vector3.RIGHT, PI / 2.0))
				d.box("iron", Vector3(tx, 1.62 + 0.06 * (k % 3), 0.1), Vector3(0.05, 0.42 - 0.04 * (k % 3), 0.015), IRON * 3.0)
				d.box("iron", Vector3(tx, 1.38 + 0.06 * (k % 3), 0.1), Vector3(0.12, 0.06, 0.02), IRON * 3.0, Basis(Vector3.BACK, 0.3 * (k % 2)))
	d.f = ax
	for k in 2:
		var cs: float = 1.0 if randf() < 0.5 else -1.0
		var zs: float = 1.0 if randf() < 0.5 else -1.0
		var wp := ax * Vector3(cs * (length * 0.5 - 0.9), 0, zs * (width * 0.5 - 0.9))
		_bone_pile(d, r, wp.x, wp.z, 0.4)


static func _bone_room(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var ds := 0 if r.openings.is_empty() else int(r.openings[0]["side"])
	var far := ds ^ 1
	if not _slot(d, r, far, minf((inner.size.x if far < 2 else inner.size.y) - 0.6, 2.2), 0.5):
		return
	var wd := minf((inner.size.x if far < 2 else inner.size.y) - 0.6, 2.2)
	d.solid_box(Vector3(0, 0.9, 0.25), Vector3(wd, 1.8, 0.5))
	for sx in [-1.0, 1.0]:
		d.box("wood", Vector3(sx * (wd * 0.5 - 0.04), 0.95, 0.25), Vector3(0.08, 1.9, 0.5), Color(0.8, 0.8, 0.8))
	for k in 4:
		var sy := 0.35 + k * 0.5
		d.box("wood", Vector3(0, sy, 0.25), Vector3(wd, 0.05, 0.5), Color(0.9, 0.9, 0.9))
		var count := int(wd / 0.3)
		for j in count:
			var sxp := -wd * 0.5 + 0.25 + j * ((wd - 0.5) / maxf(count - 1, 1))
			if k == 0 and j == count / 2:
				d.spot(Vector3(sxp, sy + 0.14, 0.25))
				continue
			if (j + k) % 3 == 0:
				d.bone(Vector3(sxp, sy + 0.05, 0.25), _flat(PI / 2.0), 0.4)
			else:
				d.skull(Vector3(sxp, sy + 0.12, 0.28), 1.0, randf_range(-0.3, 0.3))
	d.f = _wt0(r)
	var c := inner.get_center()
	_lantern(d, Vector3(c.x, 0, c.y), ht - 0.04, 0.5, )
	d.light(Vector3(c.x, ht - 0.9, c.y), GHOST, 4.0, 0.5)
	var wp := _wt(r, far, 0.0)
	if wp == Transform3D.IDENTITY:
		return
	for k in 2:
		_bone_pile(d, r, inner.position.x + 0.6 + randf() * (inner.size.x - 1.2), inner.position.y + 0.6 + randf() * (inner.size.y - 1.2), 0.35)


# The sealed tomb: a grand sarcophagus on a stepped dais inside a glowing rune ring, four braziers, guardians in
# alcoves and a cross-vault of ribs. The crypt's locked-away bottle and the crown rest on the lid.
static func _tomb(d: Deco, _h, r) -> void:
	var inner: Rect2 = r.interior()
	var ht: float = r.y1 - r.y0
	var c := inner.get_center()
	var tr := Color(0.66, 0.66, 0.63)
	var spring := ht - 1.0
	# Corner buttresses and the diagonal ribs of the vault.
	d.f = _wt0(r)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cp := Vector2(inner.position.x + 0.3 if sx < 0.0 else inner.end.x - 0.3,
					inner.position.y + 0.3 if sy < 0.0 else inner.end.y - 0.3)
			var side_x := 3 if sx < 0.0 else 2
			var side_y := 1 if sy < 0.0 else 0
			var rngx := _side_range(r, side_y)
			var rngy := _side_range(r, side_x)
			if _blocked(r, side_y, cp.x - 0.5, cp.x + 0.5, 0.3) or _blocked(r, side_x, cp.y - 0.5, cp.y + 0.5, 0.3):
				continue
			d.box("stone", Vector3(cp.x, spring * 0.5, cp.y), Vector3(0.6, spring, 0.6), tr)
			d.box("stone", Vector3(cp.x, 0.15, cp.y), Vector3(0.76, 0.3, 0.76), tr * 0.85)
			d.box("stone", Vector3(cp.x, spring - 0.1, cp.y), Vector3(0.74, 0.22, 0.74), tr * 1.1)
			var prev := Vector3(cp.x, spring, cp.y)
			for i in range(1, 9):
				var t := float(i) / 8.0
				var xz := Vector2(cp.x, cp.y).lerp(c, t)
				var p := Vector3(xz.x, spring + (ht - 0.12 - spring) * sin(t * PI / 2.0), xz.y)
				d.seg("stone", prev, p, 0.22, 0.28, tr * 1.05)
				prev = p
			if rngx.x > rngx.y or rngy.x > rngy.y:
				return
	d.ball("stone", Vector3(c.x, ht - 0.12, c.y), 0.26, tr * 1.1, Vector3(1, 0.7, 1), 8, 4)
	d.cyl("g_ghost", Vector3(c.x, ht - 0.05, c.y), 0.42, 0.42, 0.02, Color.WHITE, 12)
	d.cyl("iron", Vector3(c.x, ht - 0.55, c.y), 0.012, 0.012, 0.8, IRON, 4)
	d.ball("g_ghost", Vector3(c.x, ht - 1.0, c.y), 0.13, Color.WHITE, Vector3(1, 1.3, 1), 7, 4)
	d.light(Vector3(c.x, ht - 1.1, c.y), GHOST, 6.5, 1.0)
	# Dais, sarcophagus and rune ring around the centre.
	d.f = Transform3D(Basis.IDENTITY, Vector3(c.x, r.y0, c.y))
	r.used.append(Rect2(c - Vector2(2.4, 1.8), Vector2(4.8, 3.6)))
	d.sbox("stone", Vector3(0, 0.035, 0), Vector3(4.6, 0.07, 3.4), Color(0.45, 0.45, 0.43))
	d.sbox("stone", Vector3(0, 0.105, 0), Vector3(4.0, 0.07, 2.8), Color(0.55, 0.55, 0.53))
	var sc := Color(0.6, 0.6, 0.58)
	d.sbox("stone", Vector3(0, 0.52, 0), Vector3(2.6, 0.76, 1.3), sc)
	for sz in [-1.0, 1.0]:
		d.box("stone", Vector3(0, 0.55, sz * 0.655), Vector3(2.1, 0.5, 0.03), sc * 0.75)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			d.cyl("stone", Vector3(sx * 1.3, 0.52, sz * 0.65), 0.1, 0.1, 0.8, sc * 1.1, 6)
	d.sbox("stone", Vector3(0.3, 1.0, 0), Vector3(2.8, 0.2, 1.45), sc * 1.12)
	for sz in [-1.0, 1.0]:
		d.box("plain", Vector3(0.3, 1.1, sz * 0.62), Vector3(2.6, 0.012, 0.04), DARK)
	for sx in [-1.0, 1.0]:
		d.box("plain", Vector3(0.3 + sx * 1.3, 1.1, 0), Vector3(0.04, 0.012, 1.2), DARK)
	d.box("g_ghost", Vector3(0.0, 1.108, 0), Vector3(0.08, 0.012, 0.6))
	d.box("g_ghost", Vector3(0.0, 1.108, 0), Vector3(0.4, 0.012, 0.08))
	d.label(Vector3(0, 0.55, 0.665), 0.0, "THE FIRST KEEPER\nWHO SEALED THE BATH", 0.0032, Color(0.55, 1.0, 0.7))
	_rune_ring(d, 2.75, 56, 0.016)
	_rune_ring(d, 2.9, 60, 0.016)
	for k in 24:
		var a := TAU * k / 24.0
		d.box("g_ghost", Vector3(cos(a) * 3.02, 0.016, sin(a) * 3.02), Vector3(0.05, 0.012, 0.18), Color.WHITE, Basis(Vector3.UP, -a))
	r.spots.append(Vector3(c.x - 0.7, r.y0 + 1.22, c.y))
	d.spot(Vector3(-1.9, 0.18, 1.2))
	d.spot(Vector3(1.9, 0.18, -1.2))
	# Braziers at the corners (two of them cast light) and guardians in the wall alcoves.
	d.f = _wt0(r)
	var bi := 0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var bp := Vector2(c.x + sx * (inner.size.x * 0.5 - 1.1), c.y + sy * (inner.size.y * 0.5 - 1.1))
			_brazier(d, bp.x, bp.y, 7.0, 0.8 if bi % 3 == 0 else 0.0, "g_ghost")
			bi += 1
	for side in 4:
		var rng := _side_range(r, side)
		var a := (rng.x + rng.y) * 0.5
		if _blocked(r, side, a - 1.2, a + 1.2, 0.6):
			continue
		d.f = _wt(r, side, a)
		if not d.fits(0, 0.55, 1.5, 1.1):
			continue
		d.reserve(0, 0.55, 1.5, 1.1)
		d.arch_panel("plain", Vector3(0, 2.35, 0.03), 0.8, 0.5, 0.0, DARK)
		for sx in [-1.0, 1.0]:
			d.box("stone", Vector3(sx * 0.9, 1.2, 0.1), Vector3(0.22, 2.4, 0.2), tr)
		d.arch("stone", Vector3(-0.9, 2.35, 0.1), Vector3(0.9, 2.35, 0.1), 0.62, 0.2, 0.2, tr)
		_guardian(d, 0.0, 0.55)
	# A frieze of skulls on a ledge high on the walls.
	for side in 4:
		for seg in _segments(r, side, 0.9):
			var len_s := seg.y - seg.x - 1.4
			if len_s < 0.5:
				continue
			d.f = _wt(r, side, (seg.x + seg.y) * 0.5)
			d.box("stone", Vector3(0, 3.0, 0.1), Vector3(len_s, 0.07, 0.22), tr * 0.9)
			var cnt := int(len_s / 0.5)
			for k in cnt:
				d.skull(Vector3(-len_s * 0.5 + 0.25 + k * (len_s - 0.5) / maxf(cnt - 1, 1), 3.1, 0.1), 0.9, 0.0, BONE.darkened(0.1), false)
