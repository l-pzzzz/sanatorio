class_name HeartTunnel
extends Node3D
## Túnel de bajada hasta el corazón de la raíz (nivel 3).
## El nodo se coloca en el borde OESTE de la boca (a nivel del suelo): la rampa baja hacia el este,
## los primeros metros quedan abiertos (hueco en el suelo del mapa) y después el túnel pasa bajo el piso
## hasta una caverna donde late el corazón. Todo es geometría simple con colisión real: se camina hacia abajo.

const DIRT := "res://assets/textures/rooms/dirt_floor.png"
const WALL := "res://assets/textures/rooms/cave_wall.png"
const BARK := "res://assets/textures/rooms/root_bark.png"
const FLESH := "res://assets/textures/rooms/wall_organic.png"

@export var cell_size := 4.0
@export var wall_height := 3.0
@export var floor_y := 0.0
@export var depth := 9.0                  ## Cuánto baja el túnel (m)
@export var slope_deg := 22.0
@export var cavern_size := Vector2(18.0, 18.0)
@export var cavern_height := 5.6
@export var open_length := 8.4            ## Tramo inicial sin techo propio (hueco del suelo)

var heart: Node3D
var _run := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 777
	var th := deg_to_rad(slope_deg)
	_run = depth / tan(th)
	var length := depth / sin(th)
	var half := cell_size / 2.0
	var dirt := _mat(DIRT, Color(0.9, 0.8, 0.75), 0.5)
	var rock := _mat(WALL, Color(0.9, 0.82, 0.78), 0.3333)
	var flesh := _mat(FLESH, Color(0.9, 0.6, 0.6), 0.3333)

	# Rampa: la cara de arriba pasa por (0, floor_y) y baja `depth` metros.
	var ramp := StaticBody3D.new()
	ramp.name = "Rampa"
	add_child(ramp)
	var n := Vector3(sin(th), cos(th), 0.0)
	var ramp_len := length + 0.5
	var mid := Vector3(cos(th), -sin(th), 0.0) * (ramp_len / 2.0) - n * 0.2
	ramp.position = Vector3(0.0, floor_y, 0.0) + mid
	ramp.rotation.z = -th
	_box(ramp, Vector3(ramp_len, 0.4, cell_size), Vector3.ZERO, dirt, true)

	# Paredes laterales (de la losa del suelo hasta el fondo).
	var wall_len := _run + 2.0
	for side in [-1.0, 1.0]:
		var w := StaticBody3D.new()
		w.name = "ParedTunel"
		add_child(w)
		var h := depth + 2.0
		_box(w, Vector3(wall_len, h, 0.4), Vector3(wall_len / 2.0, floor_y - h / 2.0, side * (half + 0.2)), rock, true)

	# Techo inclinado a partir del final del hueco.
	var s0 := open_length / cos(th)
	var roof_len := ramp_len - s0
	var roof := StaticBody3D.new()
	roof.name = "TechoTunel"
	add_child(roof)
	var along := Vector3(cos(th), -sin(th), 0.0)
	roof.position = Vector3(0.0, floor_y, 0.0) + along * (s0 + roof_len / 2.0) + n * 2.9
	roof.rotation.z = -th
	_box(roof, Vector3(roof_len, 0.4, cell_size + 0.8), Vector3.ZERO, rock, false)

	# Barrera que SOLO frena a las criaturas (capa 4): no caen por el hueco.
	var barrier := StaticBody3D.new()
	barrier.name = "BarreraCriaturas"
	barrier.collision_layer = 4
	barrier.collision_mask = 0
	barrier.position = Vector3(cell_size, floor_y + 1.5, 0.0)
	var bs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(cell_size * 2.0 - 0.1, 3.0, cell_size - 0.1)
	bs.shape = bshape
	barrier.add_child(bs)
	add_child(barrier)

	# Luces del túnel: bajan en cadena hacia el rojo.
	var steps := 4
	for i in steps:
		var d := (float(i) + 0.5) / float(steps) * _run
		var l := OmniLight3D.new()
		l.position = Vector3(d, floor_y - d * tan(th) + 1.6, 0.0)
		l.light_color = Color(1.0, 0.45, 0.3).lerp(Color(1.0, 0.1, 0.2), float(i) / steps)
		l.light_energy = 0.55
		l.omni_range = 5.5
		add_child(l)
		var tw := l.create_tween().set_loops()
		tw.tween_property(l, "light_energy", 0.25, _rng.randf_range(0.8, 1.6))
		tw.tween_property(l, "light_energy", 0.65, _rng.randf_range(0.8, 1.6))

	_build_cavern(dirt, rock, flesh)
	_add_tunnel_roots(th)


func _build_cavern(dirt: Material, rock: Material, flesh: Material) -> void:
	var fy := floor_y - depth
	var x0 := _run
	var sx := cavern_size.x
	var sz := cavern_size.y
	var body := StaticBody3D.new()
	body.name = "Caverna"
	add_child(body)
	_box(body, Vector3(sx + 0.6, 0.5, sz), Vector3(x0 + sx / 2.0 - 0.3, fy - 0.25, 0.0), dirt, true)
	_box(body, Vector3(sx, 0.4, sz), Vector3(x0 + sx / 2.0, fy + cavern_height + 0.2, 0.0), rock, true)
	_box(body, Vector3(0.5, cavern_height, sz), Vector3(x0 + sx + 0.25, fy + cavern_height / 2.0, 0.0), rock, true)
	var side_z := sz / 2.0 + 0.25
	for sgn in [-1.0, 1.0]:
		_box(body, Vector3(sx + 0.6, cavern_height, 0.5), Vector3(x0 + sx / 2.0 - 0.3, fy + cavern_height / 2.0, sgn * side_z), rock, true)
		# pared oeste con la boca de 4 m
		var seg := (sz - cell_size) / 2.0
		_box(body, Vector3(0.5, cavern_height, seg), Vector3(x0 - 0.05, fy + cavern_height / 2.0, sgn * (cell_size / 2.0 + seg / 2.0)), rock, true)
	var lintel := cavern_height - 3.4
	_box(body, Vector3(0.5, lintel, cell_size), Vector3(x0 - 0.05, fy + cavern_height - lintel / 2.0, 0.0), rock, true)

	# Corazón en el centro.
	var hx := x0 + sx * 0.62
	var script: GDScript = load("res://scripts/world/root_heart.gd")
	heart = script.new()
	heart.name = "CorazonRaiz"
	heart.position = Vector3(hx, fy, 0.0)
	heart.set("room_height", cavern_height)
	add_child(heart)

	# Raíces gruesas del techo al corazón y del corazón a las paredes.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 14:
		var ang := TAU * float(i) / 14.0 + _rng.randf() * 0.4
		var r := _rng.randf_range(1.0, 5.5)
		var top := Vector3(hx + cos(ang) * r, fy + cavern_height, sin(ang) * r)
		var low := Vector3(hx + cos(ang) * _rng.randf_range(0.3, 1.2), fy + 2.6, sin(ang) * _rng.randf_range(0.3, 1.2))
		_root(st, top, low, _rng.randf_range(0.12, 0.3), 9)
	for i in 10:
		var ang2 := TAU * float(i) / 10.0 + _rng.randf() * 0.5
		var start := Vector3(hx + cos(ang2) * 1.2, fy + 0.15, sin(ang2) * 1.2)
		var finish := Vector3(hx + cos(ang2) * _rng.randf_range(5.0, 8.5), fy + 0.5, sin(ang2) * _rng.randf_range(5.0, 8.5))
		finish.z = clampf(finish.z, -sz / 2.0 + 0.5, sz / 2.0 - 0.5)
		finish.x = clampf(finish.x, x0 + 1.0, x0 + sx - 0.5)
		_root(st, start, finish, _rng.randf_range(0.14, 0.32), 10)
	var mi := MeshInstance3D.new()
	mi.name = "RaicesCaverna"
	mi.mesh = st.commit()
	var bark := _mat(BARK, Color(0.95, 0.8, 0.75), 0.6)
	bark.uv1_triplanar = false
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = bark
	add_child(mi)

	for i in 3:
		var l := OmniLight3D.new()
		l.position = Vector3(hx + _rng.randf_range(-4.0, 4.0), fy + 3.4, _rng.randf_range(-5.0, 5.0))
		l.light_color = Color(1.0, 0.15, 0.25)
		l.light_energy = 0.9
		l.omni_range = 9.0
		add_child(l)


func _add_tunnel_roots(th: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := cell_size / 2.0
	for i in 16:
		var d := _rng.randf_range(0.5, _run - 1.0)
		var base := Vector3(d, floor_y - d * tan(th), 0.0)
		var sgn := -1.0 if i % 2 == 0 else 1.0
		var a := base + Vector3(0.0, 0.2, sgn * (half - 0.12))
		var b := base + Vector3(_rng.randf_range(1.5, 3.0), -_rng.randf_range(0.3, 0.8) - 1.5 * tan(th) , sgn * (half - 0.12)) + Vector3(0.0, _rng.randf_range(1.4, 2.4), 0.0)
		_root(st, a, b, _rng.randf_range(0.06, 0.14), 8)
	var mi := MeshInstance3D.new()
	mi.name = "RaicesTunel"
	mi.mesh = st.commit()
	var m := _mat(BARK, Color(0.95, 0.8, 0.75), 0.6)
	m.uv1_triplanar = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)


## Raíz curva de a→b, más gruesa en el extremo `a`.
func _root(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, count: int) -> void:
	var pts: Array = []
	var radii: Array = []
	var phase := _rng.randf() * TAU
	var side := (b - a).cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	for i in count:
		var t := float(i) / float(count - 1)
		pts.append(a.lerp(b, t) + side * sin(t * 5.0 + phase) * 0.3 * sin(t * PI) + Vector3(0, cos(t * 4.0 + phase) * 0.12 * sin(t * PI), 0))
		radii.append(radius * (1.0 - 0.55 * t) * (1.0 + 0.25 * sin(t * 9.0 + phase)))
	_tube(st, pts, radii)


func _tube(st: SurfaceTool, pts: Array, radii: Array) -> void:
	var sides := 6
	var rings: Array = []
	for i in pts.size():
		var tangent: Vector3
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == pts.size() - 1:
			tangent = pts[i] - pts[i - 1]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		tangent = tangent.normalized()
		var ref := Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT
		var n1 := tangent.cross(ref).normalized()
		var n2 := tangent.cross(n1).normalized()
		var ring: Array = []
		for k in sides:
			var ang := TAU * k / sides
			var dir := n1 * cos(ang) + n2 * sin(ang)
			ring.append([pts[i] + dir * float(radii[i]), dir])
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var corners := [[rings[i][k], k, i], [rings[i][k2], k + 1, i], [rings[i + 1][k2], k + 1, i + 1], [rings[i + 1][k], k, i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var cn: Array = corners[idx]
				var vert: Array = cn[0]
				st.set_normal(vert[1])
				st.set_uv(Vector2(float(cn[1]) / sides * 1.5, float(cn[2]) * 0.35))
				st.add_vertex(vert[0])


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		parent.add_child(cs)


func _mat(path: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	return m
