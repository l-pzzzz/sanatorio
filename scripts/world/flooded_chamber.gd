class_name FloodedChamber
extends Node3D
## CÁMARA INUNDADA del nivel 3 (bajo la sala de filtros).
## El nodo se coloca en el borde OESTE de la boca (a nivel del suelo): una rampa baja hacia el este
## hasta una caverna con agua profunda. Solo hay pasarelas de tablas con huecos que se saltan.
## En el agua vive el Leviatán: si caes, te devora. Hay 3 válvulas; cada una baja el agua una etapa.
## Con la tercera el agua se va, el Leviatán muere y puedes bajar por la rampa del fondo a por el hacha.
##
## Coordenadas locales: +X = este (hacia dentro), Z = ancho, Y = 0 es el suelo del mapa.

const DIRT := "res://assets/textures/rooms/dirt_floor.png"
const WALL := "res://assets/textures/rooms/cave_wall.png"
const BARK := "res://assets/textures/rooms/root_bark.png"
const WOOD := "res://assets/textures/rooms/wood.png"

@export var cell_size := 4.0
@export var ground_y := 0.0
@export var walk_y := -3.6               ## Altura de las pasarelas (relativa al suelo del mapa)
@export var floor_y := -12.0             ## Fondo de la cámara (donde está el hacha)
@export var ceil_y := -0.8
@export var water_start := -7.5
@export var slope_deg := 22.0
@export var length := 28.0
@export var width := 36.0

## Niveles del agua tras 0, 1, 2 y 3 válvulas.
var water_levels: Array[float] = []
var water_y := -7.5
var stage := 0                           ## Válvulas giradas
var x0 := 0.0                            ## Donde empieza la caverna (X local)
var leviathan: Leviathan
var valves: Array[ChamberValve] = []
var devoured := false
var drained := false
var water_mesh: MeshInstance3D
var _player: PlayerCharacter
var _ambient_t := 3.0
var _rng := RandomNumberGenerator.new()
var _dirt: StandardMaterial3D
var _rock: StandardMaterial3D
var _wood: StandardMaterial3D
var _axe: PickupItem
var _wl_tween: Tween


func _ready() -> void:
	add_to_group("flooded_chamber")
	_rng.seed = 5150
	water_levels = [water_start, water_start - 1.5, water_start - 3.0, floor_y]
	water_y = water_levels[0]
	var th := deg_to_rad(slope_deg)
	var depth := ground_y - walk_y
	var run := depth / tan(th)
	x0 = run
	_dirt = _mat(DIRT, Color(0.8, 0.72, 0.68), 0.5)
	_rock = _mat(WALL, Color(0.7, 0.68, 0.66), 0.3333)
	_wood = _mat(WOOD, Color(0.55, 0.42, 0.32), 0.6)
	_build_entry(th, depth, run)
	_build_cavern()
	_build_walkways()
	_build_water()
	_build_roots()
	_build_valves()
	_build_leviathan()
	_build_axe()
	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter


# -------------------------------------------------------------------- entrada (rampa)

func _build_entry(th: float, depth: float, run: float) -> void:
	var half := cell_size / 2.0
	var length_r := depth / sin(th)
	var ramp := StaticBody3D.new()
	ramp.name = "Rampa"
	add_child(ramp)
	var n := Vector3(sin(th), cos(th), 0.0)
	var ramp_len := length_r + 0.5
	var mid := Vector3(cos(th), -sin(th), 0.0) * (ramp_len / 2.0) - n * 0.2
	ramp.position = Vector3(0.0, ground_y, 0.0) + mid
	ramp.rotation.z = -th
	_box(ramp, Vector3(ramp_len, 0.4, cell_size), Vector3.ZERO, _dirt, true)
	var wall_len := run + 1.5
	for side in [-1.0, 1.0]:
		var w := StaticBody3D.new()
		w.name = "ParedTunel"
		add_child(w)
		var h := depth + 3.0
		_box(w, Vector3(wall_len, h, 0.4), Vector3(wall_len / 2.0, ground_y - h / 2.0 + 0.0, side * (half + 0.2)), _rock, true)
	# barrera que SOLO frena a las criaturas (capa 4): no caen por el hueco
	var barrier := StaticBody3D.new()
	barrier.name = "BarreraCriaturas"
	barrier.collision_layer = 4
	barrier.collision_mask = 0
	barrier.position = Vector3(cell_size, ground_y + 1.5, 0.0)
	var bs := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(cell_size * 2.0 - 0.1, 3.0, cell_size - 0.1)
	bs.shape = bshape
	barrier.add_child(bs)
	add_child(barrier)
	# luces del tramo de bajada
	for i in 3:
		var d := (float(i) + 0.5) / 3.0 * run
		var l := OmniLight3D.new()
		l.position = Vector3(d, ground_y - d * tan(th) + 1.8, 0.0)
		l.light_color = Color(0.55, 0.85, 1.0)
		l.light_energy = 0.55
		l.omni_range = 5.5
		add_child(l)


# -------------------------------------------------------------------- caverna

func _build_cavern() -> void:
	var body := StaticBody3D.new()
	body.name = "Caverna"
	add_child(body)
	var h := ceil_y - floor_y
	var sx := length
	var sz := width
	_box(body, Vector3(sx + 0.6, 0.5, sz), Vector3(x0 + sx / 2.0 - 0.3, floor_y - 0.25, 0.0), _dirt, true)
	_box(body, Vector3(sx, 0.4, sz), Vector3(x0 + sx / 2.0, ceil_y + 0.2, 0.0), _rock, true)
	_box(body, Vector3(0.5, h, sz), Vector3(x0 + sx + 0.25, floor_y + h / 2.0, 0.0), _rock, true)
	var side_z := sz / 2.0 + 0.25
	for sgn in [-1.0, 1.0]:
		_box(body, Vector3(sx + 0.6, h, 0.5), Vector3(x0 + sx / 2.0 - 0.3, floor_y + h / 2.0, sgn * side_z), _rock, true)
		var seg := (sz - cell_size) / 2.0
		_box(body, Vector3(0.5, h, seg), Vector3(x0 - 0.05, floor_y + h / 2.0, sgn * (cell_size / 2.0 + seg / 2.0)), _rock, true)
	# bajo la boca de entrada: pared maciza hasta la altura de la pasarela
	var under := walk_y - 0.3 - floor_y
	_box(body, Vector3(0.5, under, cell_size), Vector3(x0 - 0.05, floor_y + under / 2.0, 0.0), _rock, true)
	# sobre la boca: dintel
	var top_h := ceil_y - (walk_y + 3.0)
	if top_h > 0.1:
		_box(body, Vector3(0.5, top_h, cell_size), Vector3(x0 - 0.05, ceil_y - top_h / 2.0, 0.0), _rock, true)
	# luz fría de ambiente
	for p in [Vector3(6, -2.4, -6), Vector3(15, -2.4, 6), Vector3(24, -2.4, -3), Vector3(10, -2.4, -14), Vector3(20, -2.4, 14), Vector3(20, -2.4, -14), Vector3(8, -2.4, 14)]:
		var l := OmniLight3D.new()
		l.position = Vector3(x0 + p.x, p.y, p.z)
		l.light_color = Color(0.35, 0.7, 0.9)
		l.light_energy = 0.7
		l.omni_range = 11.0
		add_child(l)


# -------------------------------------------------------------------- pasarelas

## Cada tramo: [centro_x, centro_z, largo_x, ancho_z, es_plataforma] (X relativo a la caverna).
func _plank_list() -> Array:
	return [
		[2.0, 0.0, 4.0, 5.0, true],      # A: descanso de entrada
		[6.0, 0.0, 4.0, 1.4, false],     # tablón A-B
		[10.0, 0.0, 4.0, 5.0, true],     # B: cruce
		[10.0, -4.0, 1.4, 3.0, false],   # B -> norte
		[10.5, -8.9, 5.0, 3.2, true],    # C: válvula 1 (hueco de 1,8 m antes)
		[15.5, -8.9, 5.0, 1.4, false],   # tablón C-D (con tronco)
		[22.6, -8.5, 5.6, 4.0, true],    # D: válvula 2 (hueco de 1,8 m antes)
		[10.0, 4.0, 1.4, 3.0, false],    # B -> sur
		[10.5, 8.9, 5.0, 3.2, true],     # G: descanso (hueco de 1,8 m antes)
		[15.5, 8.9, 5.0, 1.4, false],    # tablón G-E (con tronco)
		[22.6, 8.5, 5.6, 4.0, true],     # E: válvula 3 y rampa del fondo
		[23.0, -3.7, 1.4, 5.6, false],   # enlace D-E, mitad norte (con raíz baja)
		[23.0, 3.7, 1.4, 5.6, false],    # enlace D-E, mitad sur (hueco de 1,8 m entre las dos)
	]


func _build_walkways() -> void:
	var body := StaticBody3D.new()
	body.name = "Pasarelas"
	add_child(body)
	var posts := StaticBody3D.new()
	posts.name = "Pilotes"
	posts.collision_layer = 0
	posts.collision_mask = 0
	add_child(posts)
	var post_mat := _mat(BARK, Color(0.45, 0.35, 0.3), 0.6)
	for e: Array in _plank_list():
		var cx := x0 + float(e[0])
		var cz := float(e[1])
		var sx := float(e[2])
		var sz := float(e[3])
		_box(body, Vector3(sx, 0.25, sz), Vector3(cx, walk_y - 0.125, cz), _wood, true)
		# pilotes visibles hasta el fondo (sin colisión)
		for ix in [-1.0, 1.0]:
			for iz in [-1.0, 1.0]:
				var cyl := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.14
				cm.bottom_radius = 0.18
				cm.height = walk_y - floor_y
				cm.radial_segments = 6
				cm.rings = 1
				cyl.mesh = cm
				cyl.material_override = post_mat
				cyl.position = Vector3(cx + ix * (sx / 2.0 - 0.2), floor_y + (walk_y - floor_y) / 2.0 - 0.1, cz + iz * (sz / 2.0 - 0.2))
				posts.add_child(cyl)
		if bool(e[4]):
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(cx, walk_y + 1.7, cz)
			lamp.light_color = Color(1.0, 0.6, 0.3)
			lamp.light_energy = 0.9
			lamp.omni_range = 7.0
			add_child(lamp)
			var tw := lamp.create_tween().set_loops()
			tw.tween_property(lamp, "light_energy", 0.55, _rng.randf_range(0.5, 1.2))
			tw.tween_property(lamp, "light_energy", 1.0, _rng.randf_range(0.5, 1.2))
			var lantern := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.18, 0.26, 0.18)
			lantern.mesh = lm
			var lmat := StandardMaterial3D.new()
			lmat.albedo_color = Color(1.0, 0.65, 0.3)
			lmat.emission_enabled = true
			lmat.emission = Color(1.0, 0.55, 0.2)
			lmat.emission_energy_multiplier = 2.5
			lantern.material_override = lmat
			lantern.position = Vector3(cx, walk_y + 1.7, cz)
			add_child(lantern)
	# troncos bajos que hay que SALTAR (tablones largos)
	_log(body, Vector3(x0 + 15.5, walk_y, -8.9))
	_log(body, Vector3(x0 + 15.5, walk_y, 8.9))
	# raíz colgante que hay que pasar AGACHADO (Ctrl), en el enlace este
	var beam := Vector3(x0 + 23.0, walk_y + 1.55, -3.7)
	_box(body, Vector3(1.9, 0.7, 0.6), beam, _mat(BARK, Color(0.7, 0.55, 0.5), 0.6), true)
	# barandas rotas laterales solo decorativas en las plataformas con válvula
	# rampa del fondo (de la plataforma E hacia abajo, junto a la pared este)
	var ramp_drop := walk_y - floor_y
	var ang := deg_to_rad(28.0)
	var ramp_run := ramp_drop / tan(ang)
	var ramp_len := ramp_drop / sin(ang)
	var rb := StaticBody3D.new()
	rb.name = "RampaFondo"
	add_child(rb)
	# parte alta pegada a la plataforma E (z = 10.5), baja hacia el norte
	var top := Vector3(x0 + 26.5, walk_y, 10.5)
	var bottom := Vector3(x0 + 26.5, floor_y, 10.5 - ramp_run)
	rb.position = (top + bottom) / 2.0 - Vector3(0, 0.2 / cos(ang), 0)
	rb.rotation.x = -ang      # baja hacia -Z
	_box(rb, Vector3(2.8, 0.4, ramp_len + 0.4), Vector3.ZERO, _wood, true)


func _log(parent: StaticBody3D, p: Vector3) -> void:
	var m := _mat(BARK, Color(0.6, 0.45, 0.4), 0.6)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.28
	cm.height = 1.6
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.position = p + Vector3(0, 0.28, 0)
	mi.rotation.x = PI / 2.0
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 1.5)
	cs.shape = shape
	cs.position = p + Vector3(0, 0.25, 0)
	parent.add_child(cs)


# -------------------------------------------------------------------- agua

func _build_water() -> void:
	water_mesh = MeshInstance3D.new()
	water_mesh.name = "Agua"
	var pm := PlaneMesh.new()
	pm.size = Vector2(length + 0.4, width)
	water_mesh.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.02, 0.09, 0.11, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.0, 0.08, 0.1)
	m.emission_energy_multiplier = 0.6
	water_mesh.material_override = m
	water_mesh.position = Vector3(x0 + length / 2.0, water_y, 0.0)
	add_child(water_mesh)
	# fondo lodoso por debajo (se ve a través del agua)
	var mud := MeshInstance3D.new()
	mud.name = "AguaProfunda"
	var bm := BoxMesh.new()
	bm.size = Vector3(length, 0.05, width)
	mud.mesh = bm
	mud.material_override = _dirt
	mud.position = Vector3(x0 + length / 2.0, floor_y + 0.03, 0.0)
	add_child(mud)


func _build_roots() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 22:
		var top := Vector3(x0 + _rng.randf_range(1.0, length - 1.0), ceil_y, _rng.randf_range(-width / 2.0 + 0.6, width / 2.0 - 0.6))
		var low := top + Vector3(_rng.randf_range(-1.0, 1.0), -_rng.randf_range(1.5, 3.2), _rng.randf_range(-1.0, 1.0))
		_root(st, top, low, _rng.randf_range(0.07, 0.2), 7)
	var mi := MeshInstance3D.new()
	mi.name = "RaicesCamara"
	mi.mesh = st.commit()
	var bark := _mat(BARK, Color(0.9, 0.78, 0.72), 0.6)
	bark.uv1_triplanar = false
	bark.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = bark
	add_child(mi)


func _root(st: SurfaceTool, a: Vector3, b: Vector3, radius: float, count: int) -> void:
	var pts: Array = []
	var radii: Array = []
	var phase := _rng.randf() * TAU
	for i in count:
		var t := float(i) / float(count - 1)
		pts.append(a.lerp(b, t) + Vector3(sin(t * 5.0 + phase) * 0.25 * sin(t * PI), 0.0, cos(t * 4.0 + phase) * 0.2 * sin(t * PI)))
		radii.append(radius * (1.0 - 0.7 * t))
	var sides := 6
	var rings: Array = []
	for i in count:
		var tangent: Vector3 = (pts[mini(i + 1, count - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var ref := Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.FORWARD
		var n1 := tangent.cross(ref).normalized()
		var n2 := tangent.cross(n1).normalized()
		var ring: Array = []
		for k in sides:
			var ang := TAU * k / sides
			var dir := n1 * cos(ang) + n2 * sin(ang)
			ring.append([pts[i] + dir * float(radii[i]), dir])
		rings.append(ring)
	for i in count - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var corners := [[rings[i][k], k, i], [rings[i][k2], k + 1, i], [rings[i + 1][k2], k + 1, i + 1], [rings[i + 1][k], k, i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var cn: Array = corners[idx]
				var vert: Array = cn[0]
				st.set_normal(vert[1])
				st.set_uv(Vector2(float(cn[1]) / sides * 1.5, float(cn[2]) * 0.35))
				st.add_vertex(vert[0])


# -------------------------------------------------------------------- válvulas, monstruo, hacha

func _build_valves() -> void:
	# (x, z, giro) relativo a la caverna; miran hacia el centro de la cámara
	var spots := [
		[Vector3(10.5, walk_y, -9.6), 0.0],
		[Vector3(23.5, walk_y, -9.4), 0.0],
		[Vector3(23.5, walk_y, 9.4), PI],
	]
	for i in 3:
		var v := ChamberValve.new()
		v.name = "Valvula_%d" % (i + 1)
		v.valve_index = i + 1
		v.chamber = self
		v.position = Vector3(x0 + (spots[i][0] as Vector3).x, walk_y, (spots[i][0] as Vector3).z)
		v.rotation.y = float(spots[i][1])
		v.turned.connect(_on_valve_turned)
		add_child(v)
		valves.append(v)


func _build_leviathan() -> void:
	leviathan = Leviathan.new()
	leviathan.name = "Leviatan"
	leviathan.chamber = self
	var dens: Array[Vector3] = [
		Vector3(x0 + 16.0, floor_y, 0.0),
		Vector3(x0 + 17.5, floor_y, -4.5),
		Vector3(x0 + 17.5, floor_y, 4.5),
	]
	leviathan.dens = dens
	add_child(leviathan)


func _build_axe() -> void:
	_axe = PickupItem.new()
	_axe.name = "Hacha"
	_axe.item_id = "hacha"
	_axe.position = Vector3(x0 + 19.5, floor_y + 0.05, -1.5)
	add_child(_axe)


# -------------------------------------------------------------------- lógica

func player_in_chamber() -> bool:
	if _player == null:
		return false
	var p := to_local(_player.global_position)
	return p.x > x0 - 1.5 and absf(p.z) < width / 2.0 + 1.0 and p.y < ceil_y


func on_valve_started(_valve: ChamberValve) -> void:
	if leviathan != null:
		leviathan.provoke()
	var mm := _mission()
	if mm:
		mm.show_toast(Lang.t("¡Algo enorme se agita bajo el agua!"), 3.0)


func _on_valve_turned(valve: ChamberValve) -> void:
	stage += 1
	_drain_to(stage, 12.0)
	var mm := _mission()
	if mm:
		mm.report("valve", str(valve.valve_index))
		if stage < 3:
			mm.show_toast(Lang.t("El agua baja... pero el Leviatán sigue ahí. Faltan %d válvulas.") % (3 - stage), 5.0)
	if stage >= 3:
		_finish_drain()


func _drain_to(s: int, seconds: float) -> void:
	if _wl_tween != null and _wl_tween.is_valid():
		_wl_tween.kill()
	_wl_tween = create_tween()
	_wl_tween.tween_property(self, "water_y", water_levels[clampi(s, 0, 3)], seconds).set_trans(Tween.TRANS_SINE)
	Sfx.play(self, "drain_water", 2.0)
	NoiseManager.emit_noise(to_global(Vector3(x0 + 10.0, 0.0, 0.0)), 1.0)


func _finish_drain() -> void:
	drained = true
	if leviathan != null:
		leviathan.die()
	var mm := _mission()
	if mm:
		mm.show_toast(Lang.t("¡El Leviatán se desploma! Cuando el agua baje del todo, usa la rampa del fondo (este) y recoge el hacha."), 9.0)


## Al cargar una partida: deja las válvulas indicadas ya giradas y el agua en su nivel.
func restore_valves(ids: Array) -> void:
	var count := 0
	for v in valves:
		if ids.has(str(v.valve_index)) or ids.has(v.valve_index):
			v.set_turned_silently()
			count += 1
	stage = count
	water_y = water_levels[clampi(count, 0, 3)]
	if count >= 3:
		drained = true
		if leviathan != null:
			leviathan.set_dead_instantly()
	elif count > 0 and leviathan != null:
		leviathan.anger = 0.34 * count


func _mission() -> MissionManager:
	return get_tree().get_first_node_in_group("mission_manager") as MissionManager


## PRUEBAS: F9 te lleva a la plataforma de entrada de la cámara. Borrar antes de publicar.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		if _player == null:
			_player = get_tree().get_first_node_in_group("player") as PlayerCharacter
		if _player != null:
			_player.global_position = to_global(Vector3(x0 + 2.0, walk_y + 0.4, 0.0))
			_player.velocity = Vector3.ZERO
			_player.rotation.y = -PI / 2.0   # mira al este, hacia las pasarelas
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if water_mesh != null:
		water_mesh.position.y = water_y + sin(Time.get_ticks_msec() * 0.0014) * 0.03
		water_mesh.visible = water_y > floor_y + 0.08
	_ambient_t -= delta
	if _ambient_t <= 0.0 and player_in_chamber():
		_ambient_t = _rng.randf_range(4.0, 9.0)
		Sfx.play(self, "water_lap" if _rng.randf() < 0.5 else "drip", -12.0)
	if devoured or drained or _player == null:
		return
	var p := to_local(_player.global_position)
	if p.x > x0 - 0.5 and absf(p.z) < width / 2.0 + 0.5 and p.y < water_y + 1.1:
		_devour()


func _devour() -> void:
	devoured = true
	Sfx.play(self, "splash_%d" % _rng.randi_range(1, 4), 5.0)
	var mm := _mission()
	if mm == null or leviathan == null:
		return
	var kill_head := leviathan.make_kill_head()
	mm.on_player_caught("EL LEVIATÁN TE DEVORÓ", kill_head)


# -------------------------------------------------------------------- utilidades

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
