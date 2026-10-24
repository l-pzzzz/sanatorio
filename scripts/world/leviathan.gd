class_name Leviathan
extends Node3D
## EL LEVIATÁN DEL DRENAJE (nivel 3). Una criatura enorme que vive en el agua de la cámara inundada.
## No puede alcanzarte en las pasarelas: sale del agua, te mira, ruge y finge embestidas.
## Si caes al agua te devora. Solo muere cuando se vacía el agua (las 3 válvulas).
##
## Versión de código (cuello de esferas + cabeza). Si existe `res://assets/models/leviathan_model.glb`
## se usa ese modelo en su lugar (ver `_try_load_model`).

enum S { SUBMERGED, RISING, WATCHING, LUNGING, SINKING, DYING, DEAD, SWIMMING }

@export_file("*.glb") var model_path := "res://assets/models/leviathan_model.glb"
@export var model_scale := 1.0
@export var model_height := 8.0          ## Altura del modelo (m) de la base a la cabeza, ya con `model_scale`
@export var model_head_forward := 2.4    ## Cuánto sobresale la cabeza del modelo hacia delante (m)
@export var model_mouth := Vector3(0.0, 6.5, -2.3)   ## Dónde está la boca dentro del modelo (para devorarte)
@export var neck_segments := 26
@export var min_gap := 3.0               ## Distancia mínima a la que acerca la cabeza (nunca te toca)

var chamber: Node = null                 ## FloodedChamber (da el nivel del agua, techo y guaridas)
var state := S.SUBMERGED
var anger := 0.0
var dens: Array[Vector3] = []            ## Guaridas (x,z locales de la cámara; y = fondo)
var den := Vector3.ZERO
var head: Head
var head_goal := Vector3.ZERO
var head_pos := Vector3.ZERO
var arch := 0.85                         ## 1 = cuello arqueado hacia arriba, 0 = tumbado
var _segs: Array[MeshInstance3D] = []
var _model: Node3D = null
var _state_t := 0.0
var _next_rise := 6.0
var _lunge_t := 0.0
var _screech_t := 3.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _skin: StandardMaterial3D
var _player: Node3D
var _dead_t := 0.0
var _hidden_for_kill := false
var _tilt := 0.0                          ## Inclinación del modelo (rad); negativo = cabeza hacia delante
var _y_at_death := 0.0
var _yaw_at_death := 0.0
var _model_light: OmniLight3D
var _post_swim := false                   ## Ya nadó: la próxima vez que salga del agua es para asomarse
var _sw_c := Vector2.ZERO                 ## Centro del cuerpo mientras nada (x,z locales)
var _sw_yaw := 0.0
var _sw_target := Vector2.ZERO
var _sw_time := 0.0
var _sw_snd := 3.0
var _sw_wake := 0.0
var _watch_age := 0.0
var _sw_k := 0.0                          ## 0 = vertical, 1 = tumbado nadando


# ------------------------------------------------------------ cabeza (también se usa al devorarte)

class Head extends Node3D:
	var jaw: Node3D
	var open := 0.0

	func set_jaw(v: float) -> void:
		open = clampf(v, 0.0, 1.0)
		if jaw:
			jaw.rotation.x = open * 0.75

	## KillSequence mueve las partes con este nombre: "head" abre y cierra la mandíbula.
	func _rig_pose(part: String, rot: Vector3, _w: float) -> void:
		if part == "head":
			set_jaw(clampf((rot.x + 0.5) / 0.9, 0.0, 1.0))


## Soporte de la cabeza para KillSequence (esa animación mueve y gira este nodo).
class Pivot extends Node3D:
	var inner: Head

	func _rig_pose(part: String, rot: Vector3, w: float) -> void:
		if inner:
			inner._rig_pose(part, rot, w)


static func build_head(skin: Material, scale_m := 1.0) -> Head:
	var h := Head.new()
	h.name = "Cabeza"
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.05, 0.05)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.08, 0.05)
	eye_mat.emission_energy_multiplier = 4.0
	var tooth_mat := StandardMaterial3D.new()
	tooth_mat.albedo_color = Color(0.85, 0.82, 0.7)
	tooth_mat.roughness = 0.6
	var maw_mat := StandardMaterial3D.new()
	maw_mat.albedo_color = Color(0.45, 0.04, 0.05)
	maw_mat.roughness = 0.5
	# cráneo (cara hacia -Z)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 8
	skull.mesh = sm
	skull.material_override = skin
	skull.scale = Vector3(1.0, 0.8, 1.9)
	skull.position = Vector3(0, 0.1, -0.3)
	h.add_child(skull)
	# hocico
	var snout := MeshInstance3D.new()
	var sn := SphereMesh.new()
	sn.radius = 0.4
	sn.height = 0.8
	sn.radial_segments = 12
	sn.rings = 6
	snout.mesh = sn
	snout.material_override = skin
	snout.scale = Vector3(0.9, 0.55, 1.5)
	snout.position = Vector3(0, 0.0, -1.05)
	h.add_child(snout)
	# mandíbula (pivote en la bisagra)
	var jaw := Node3D.new()
	jaw.position = Vector3(0, -0.22, -0.1)
	h.add_child(jaw)
	var jm := MeshInstance3D.new()
	var jb := SphereMesh.new()
	jb.radius = 0.4
	jb.height = 0.8
	jb.radial_segments = 12
	jb.rings = 6
	jm.mesh = jb
	jm.material_override = skin
	jm.scale = Vector3(0.85, 0.3, 1.9)
	jm.position = Vector3(0, -0.05, -0.75)
	jaw.add_child(jm)
	var tongue := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.5, 0.05, 1.2)
	tongue.mesh = tb
	tongue.material_override = maw_mat
	tongue.position = Vector3(0, 0.1, -0.7)
	jaw.add_child(tongue)
	h.jaw = jaw
	# dientes
	for i in 9:
		for upper in [true, false]:
			var tooth := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.03
			cm.height = 0.2 if (i % 3 == 0) else 0.13
			cm.radial_segments = 5
			cm.rings = 1
			tooth.mesh = cm
			tooth.material_override = tooth_mat
			var zz := -0.35 - float(i) * 0.19
			var xx := 0.27 - 0.02 * float(i) * 0.4
			for sgn in [-1.0, 1.0]:
				var t2 := tooth.duplicate() as MeshInstance3D
				t2.position = Vector3(sgn * xx, -0.18 if upper else 0.02, zz)
				t2.rotation.x = 0.0 if upper else PI
				if upper:
					h.add_child(t2)
				else:
					jaw.add_child(t2)
			tooth.free()
	# ojos rojos
	for sgn in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.11
		es.height = 0.22
		es.radial_segments = 10
		es.rings = 5
		eye.mesh = es
		eye.material_override = eye_mat
		eye.position = Vector3(sgn * 0.42, 0.28, -0.85)
		h.add_child(eye)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.1, 0.08)
	glow.light_energy = 1.4
	glow.omni_range = 7.0
	glow.position = Vector3(0, 0.3, -1.2)
	glow.name = "LuzOjos"
	h.add_child(glow)
	h.scale = Vector3.ONE * scale_m
	return h


static func make_skin() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.1, 0.08)
	m.roughness = 0.3
	m.metallic = 0.1
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	if ResourceLoader.exists("res://assets/textures/rooms/wall_organic.png"):
		m.albedo_texture = load("res://assets/textures/rooms/wall_organic.png")
		m.albedo_color = Color(0.22, 0.4, 0.3)
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.7, 0.7, 0.7)
	return m


# ------------------------------------------------------------------------------ ciclo

func _ready() -> void:
	add_to_group("leviathan")
	_rng.seed = 90210
	_skin = make_skin()
	if not _try_load_model():
		_build_neck()
	head = build_head(_skin, 1.0 if _model == null else 0.01)
	add_child(head)
	if _model != null:
		head.visible = false
	if dens.is_empty():
		dens.append(Vector3.ZERO)
	den = dens[0]
	head_pos = _hidden_goal()
	head_goal = head_pos
	_next_rise = 5.0
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _try_load_model() -> bool:
	if not ResourceLoader.exists(model_path):
		return false
	var res: Resource = load(model_path)
	if not (res is PackedScene):
		return false
	_model = (res as PackedScene).instantiate() as Node3D
	if _model == null:
		return false
	_model.name = "Modelo"
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)
	# luz roja en la cara, para que se vea aunque la cámara esté oscura
	_model_light = OmniLight3D.new()
	_model_light.light_color = Color(1.0, 0.4, 0.35)
	_model_light.light_energy = 1.5
	_model_light.omni_range = 10.0
	_model_light.position = Vector3(0.0, model_height - 1.0, -model_head_forward)
	_model.add_child(_model_light)
	return true


func _build_neck() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	for i in neck_segments:
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _skin
		add_child(mi)
		_segs.append(mi)


func _floor_y() -> float:
	return float(chamber.get("floor_y")) if chamber != null else -12.0


func _water_y() -> float:
	return float(chamber.get("water_y")) if chamber != null else -7.5


func _ceil_y() -> float:
	return float(chamber.get("ceil_y")) if chamber != null else -0.8


func _hidden_goal() -> Vector3:
	return Vector3(den.x, minf(_water_y() - 1.6, _floor_y() + 4.0), den.z)


func _rise_goal() -> Vector3:
	var low := _floor_y() + (model_height if _model != null else 0.0)    # el modelo no se hunde bajo el fondo
	var y := minf(maxf(_water_y() + 5.4, low), _ceil_y() - 1.0)
	return Vector3(den.x, y, den.z)


func is_alive() -> bool:
	return state != S.DYING and state != S.DEAD


func set_state(s: S) -> void:
	state = s
	_state_t = 0.0


## El jugador acaba de empezar a girar una válvula: el Leviatán se enfurece y sale.
func provoke() -> void:
	if not is_alive():
		return
	anger = minf(anger + 0.34, 1.2)
	if state == S.SUBMERGED or state == S.SINKING or state == S.SWIMMING:
		_post_swim = false
		_pick_den()
		_begin_rise(true)


func _pick_den() -> void:
	if _player == null or chamber == null or dens.size() < 2:
		return
	var local := to_local(_player.global_position)
	var best := den
	var best_d := INF
	for d in dens:
		var dd := Vector2(d.x - local.x, d.z - local.z).length()
		# la guarida más cercana que no quede justo debajo de ti
		if dd > 5.0 and dd < best_d:
			best_d = dd
			best = d
	den = best


func _begin_rise(angry := false) -> void:
	set_state(S.RISING)
	head_pos = _hidden_goal()
	var surf := Vector3(den.x, _water_y(), den.z)
	_splash(surf, 1.0)
	Sfx.play(self, "leviathan_emerge", 2.0 if angry else -1.0)
	Sfx.play(self, "splash_%d" % _rng.randi_range(1, 4), 4.0)
	NoiseManager.emit_noise(to_global(Vector3(den.x, 0.0, den.z)), 1.4 if angry else 1.0)
	_shake(0.7 if angry else 0.45, 0.035)


func die() -> void:
	if not is_alive():
		return
	set_state(S.DYING)
	if _model != null:
		_y_at_death = _model.position.y
		_yaw_at_death = _model.rotation.y
	Sfx.play(self, "leviathan_death", 4.0)
	_shake(2.2, 0.06)
	NoiseManager.emit_noise(to_global(Vector3(den.x, 0.0, den.z)), 1.8)


## Para guardar/cargar: si el agua ya se vació, el Leviatán aparece muerto.
func set_dead_instantly() -> void:
	state = S.DEAD
	arch = 0.0
	den = dens[0] if not dens.is_empty() else den
	head_pos = Vector3(den.x + 3.2, _floor_y() + 0.7, den.z + 1.2)
	head_goal = head_pos
	if _model_light:
		_model_light.visible = false
	if head:
		head.set_jaw(0.7)
		var l := head.get_node_or_null("LuzOjos") as OmniLight3D
		if l:
			l.visible = false


func _shake(seconds: float, amount: float) -> void:
	var mm := get_tree().get_first_node_in_group("mission_manager")
	if mm != null and mm.has_method("_shake_camera") and _player != null:
		# solo si estás dentro de la cámara
		mm.call("_shake_camera", seconds, amount)


func _splash(pos_local: Vector3, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = int(60 * size)
	p.lifetime = 1.1
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 28.0
	p.initial_velocity_min = 2.0 * size
	p.initial_velocity_max = 5.5 * size
	p.gravity = Vector3(0, -9.0, 0)
	var m := SphereMesh.new()
	m.radius = 0.06
	m.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.8, 0.85, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	m.material = mat
	p.mesh = m
	p.position = pos_local
	add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _process(delta: float) -> void:
	if _hidden_for_kill:
		return
	_t += delta
	_state_t += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D
	_update_state(delta)
	var k := 1.0 - exp(-delta * _follow_speed())
	head_pos = head_pos.lerp(head_goal, k)
	_pose(delta)


func _follow_speed() -> float:
	match state:
		S.LUNGING:
			return 9.0
		S.RISING:
			return 2.6
		S.SINKING:
			return 2.0
		S.DYING:
			return 1.3
		_:
			return 3.2


func _player_local() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	return to_local(_player.global_position)


func _player_inside() -> bool:
	if chamber != null and chamber.has_method("player_in_chamber"):
		return chamber.player_in_chamber()
	return true


func _update_state(delta: float) -> void:
	match state:
		S.SUBMERGED:
			arch = 0.85
			head_goal = _hidden_goal()
			if _player_inside():
				_next_rise -= delta * (1.0 + anger)
				if _next_rise <= 0.0:
					if _post_swim:
						_post_swim = false
						_pick_den()
						_begin_rise()
					else:
						_begin_swim()
			# burbujeo ocasional
			if _rng.randf() < delta * 0.25 and _player_inside():
				Sfx.play(self, "gurgle", -12.0)
		S.SWIMMING:
			head_goal = _hidden_goal()
			_update_swim(delta)
		S.RISING:
			head_goal = _rise_goal()
			if _state_t > 2.2:
				set_state(S.WATCHING)
				_watch_age = 0.0
				_lunge_t = _rng.randf_range(1.6, 2.8) / (1.0 + anger)
				Sfx.play(self, "leviathan_roar", 5.0)
				head.set_jaw(1.0)
		S.WATCHING:
			_watch(delta)
			_watch_age += delta
			if _watch_age > _watch_time():
				set_state(S.SINKING)
				Sfx.play(self, "leviathan_submerge", 0.0)
		S.LUNGING:
			_watch_age += delta
			if _state_t > 0.55:
				_splash(Vector3(head_pos.x, _water_y(), head_pos.z), 0.8)
				set_state(S.WATCHING)
				_state_t = 0.0
				_lunge_t = _rng.randf_range(2.0, 3.5) / (1.0 + anger)
		S.SINKING:
			head_goal = _hidden_goal()
			head.set_jaw(0.0)
			if _state_t > 2.4:
				_splash(Vector3(den.x, _water_y(), den.z), 0.6)
				set_state(S.SUBMERGED)
				_next_rise = _rng.randf_range(2.0, 4.0)
		S.DYING:
			arch = lerpf(arch, 0.0, 0.8 * delta)
			head_goal = Vector3(den.x + 3.2, _floor_y() + 0.7, den.z + 1.2)
			head.set_jaw(0.5 + 0.5 * sin(_t * 3.0) * clampf(1.0 - _state_t / 5.0, 0.0, 1.0))
			if _state_t > 6.0:
				set_state(S.DEAD)
				if _model_light:
					_model_light.visible = false
				var l := head.get_node_or_null("LuzOjos") as OmniLight3D
				if l:
					l.visible = false
		S.DEAD:
			arch = 0.0
			head.set_jaw(0.7)


func _swim_bounds() -> Rect2:
	var x0 := float(chamber.get("x0")) if chamber != null else 0.0
	var w := float(chamber.get("width")) if chamber != null else 30.0
	var zl := w / 2.0 - 6.0
	return Rect2(Vector2(x0 + 8.0, -zl), Vector2(14.0, zl * 2.0))


func _begin_swim() -> void:
	set_state(S.SWIMMING)
	var b := _swim_bounds()
	_sw_c = Vector2(clampf(den.x, b.position.x, b.end.x), clampf(den.z, b.position.y, b.end.y))
	_sw_yaw = _rng.randf() * TAU
	_pick_swim_target()
	_sw_time = _rng.randf_range(11.0, 16.0) / (1.0 + anger * 0.5)
	_sw_snd = _rng.randf_range(1.5, 3.0)
	_sw_wake = 0.0
	Sfx.play(self, "splash_%d" % _rng.randi_range(1, 4), 2.0)
	_splash(Vector3(_sw_c.x, _water_y(), _sw_c.y), 1.0)
	NoiseManager.emit_noise(to_global(Vector3(_sw_c.x, 0.0, _sw_c.y)), 0.7)


func _pick_swim_target() -> void:
	var b := _swim_bounds()
	# se dirige a un punto lejano, preferiblemente cerca de donde estás para que lo veas pasar
	var pl := _player_local()
	for i in 6:
		var t := Vector2(_rng.randf_range(b.position.x, b.end.x), _rng.randf_range(b.position.y, b.end.y))
		_sw_target = t
		if t.distance_to(_sw_c) > 9.0 and (i > 2 or t.distance_to(Vector2(pl.x, pl.z)) < 14.0):
			return


func _update_swim(delta: float) -> void:
	_sw_time -= delta
	var to_t := _sw_target - _sw_c
	if to_t.length() < 2.5:
		_pick_swim_target()
		to_t = _sw_target - _sw_c
	var want := atan2(-to_t.x, -to_t.y)
	_sw_yaw = rotate_toward(_sw_yaw, want, 0.7 * delta)
	var f := Vector2(-sin(_sw_yaw), -cos(_sw_yaw))
	_sw_c += f * 3.4 * delta
	var b := _swim_bounds()
	_sw_c = Vector2(clampf(_sw_c.x, b.position.x, b.end.x), clampf(_sw_c.y, b.position.y, b.end.y))
	# rastro de olas
	_sw_wake -= delta
	if _sw_wake <= 0.0:
		_sw_wake = 1.1
		var head_xz := _sw_c + f * (model_height * 0.5)
		_splash(Vector3(head_xz.x, _water_y(), head_xz.y), 0.5)
	# gritos y chapoteos mientras nada
	_sw_snd -= delta
	if _sw_snd <= 0.0:
		_sw_snd = _rng.randf_range(4.0, 8.0)
		var r := _rng.randf()
		if r < 0.4:
			Sfx.play(self, "leviathan_call", 0.0)
		elif r < 0.75:
			Sfx.play(self, "leviathan_screech", 1.0)
		else:
			Sfx.play(self, "leviathan_roar", 2.0)
		Sfx.play(self, "splash_%d" % _rng.randi_range(1, 4), -2.0)
		NoiseManager.emit_noise(to_global(Vector3(_sw_c.x, 0.0, _sw_c.y)), 0.8)
		_shake(0.35, 0.015)
	if _sw_time <= 0.0:
		_post_swim = true
		_splash(Vector3(_sw_c.x, _water_y(), _sw_c.y), 1.0)
		Sfx.play(self, "leviathan_submerge", 0.0)
		set_state(S.SUBMERGED)
		_next_rise = _rng.randf_range(1.5, 2.5)


func _watch_time() -> float:
	return 7.0 + 3.0 * anger


func _watch(delta: float) -> void:
	var rg := _rise_goal()
	var p := _player_local()
	var to_p := Vector3(p.x - den.x, 0.0, p.z - den.z)
	var dist := to_p.length()
	var dir := to_p.normalized() if dist > 0.01 else Vector3.RIGHT
	# se asoma hacia ti, pero siempre deja `min_gap` de distancia
	var reach := clampf(dist - (min_gap + 1.2), 0.0, 5.5)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var sway := side * sin(_t * 0.9) * 0.9
	head_goal = rg + dir * reach + sway + Vector3(0.0, sin(_t * 1.3) * 0.35, 0.0)
	_lunge_t -= delta
	_screech_t -= delta
	if _screech_t <= 0.0:
		_screech_t = _rng.randf_range(3.0, 6.0) / (1.0 + anger * 0.6)
		Sfx.play(self, "leviathan_screech" if _rng.randf() < 0.5 else "leviathan_call", 3.0)
		head.set_jaw(1.0)
		NoiseManager.emit_noise(to_global(Vector3(head_pos.x, 0.0, head_pos.z)), 1.2)
	else:
		head.set_jaw(lerpf(head.open, 0.25 + 0.15 * sin(_t * 2.0), 1.0 - exp(-delta * 4.0)))
	if _lunge_t <= 0.0 and dist > min_gap + 0.5:
		# embestida falsa: la cabeza baja hacia ti y se queda a `min_gap` m
		set_state(S.LUNGING)
		var stop := minf(dist - min_gap, 8.0)
		head_goal = Vector3(den.x, 0.0, den.z) + dir * maxf(stop, 0.0)
		head_goal.y = maxf(p.y + 0.9, _water_y() + 1.0)
		head.set_jaw(1.0)
		Sfx.play(self, "leviathan_lunge", 4.0)
		NoiseManager.emit_noise(_player.global_position if _player else global_position, 0.9)
		_shake(0.45, 0.03)


func _pose(delta: float) -> void:
	var base := Vector3(den.x, _floor_y(), den.z)
	# cabeza: mira hacia donde apunta el cuello, pero busca tus ojos
	var look := _player_local() + Vector3(0, 1.4, 0)
	if state == S.SUBMERGED or state == S.SINKING or state == S.DEAD or state == S.DYING:
		look = head_pos + Vector3(1.0, -0.2, 0.0) if state == S.DEAD else head_pos + Vector3(0, 1.0, 0)
	head.position = head_pos
	var dir_to := look - head_pos
	if dir_to.length() > 0.1 and not (state == S.DEAD):
		var dn := dir_to.normalized()
		var up_v := Vector3.UP if absf(dn.y) < 0.98 else Vector3.RIGHT
		var target_basis := Basis.looking_at(dn, up_v)
		head.basis = head.basis.orthonormalized().slerp(target_basis, 1.0 - exp(-delta * 6.0)).scaled(head.scale)
	elif state == S.DEAD:
		head.rotation = Vector3(0.0, -2.2, 0.3)
	if _model != null:
		_pose_model(base)
		return
	# cuello: curva de Bézier base → cabeza, saliendo primero hacia arriba
	var up_pull := (head_pos.y - base.y) * arch
	var p0 := base
	var p1 := base + Vector3(0, maxf(up_pull, 0.5), 0)
	var p2 := head_pos + head.basis.z.normalized() * 0.45     # justo detrás del cráneo
	var n := _segs.size()
	for i in n:
		var t := float(i) / float(n - 1)
		var a := p0.lerp(p1, t)
		var b := p1.lerp(p2, t)
		var pt := a.lerp(b, t)
		var r := lerpf(1.15, 0.5, pow(t, 0.7))
		var wobble := sin(_t * 1.4 + t * 5.0) * 0.07 * t
		pt.x += wobble
		var seg := _segs[i]
		seg.position = pt
		seg.scale = Vector3.ONE * (r * 2.0)
		seg.visible = true


func _pose_model(base: Vector3) -> void:
	# El modelo es una pieza rígida: sube y baja, gira hacia ti y se inclina para las embestidas.
	var hidden_y := _hidden_goal().y
	var rise := clampf(inverse_lerp(hidden_y, _rise_goal().y, head_pos.y), 0.0, 1.0)
	var top_y := lerpf(_water_y() - 1.5, _rise_goal().y, rise)
	var pos := Vector3(base.x, top_y - model_height, base.z)
	var yaw := _model.rotation.y
	var tilt_target := 0.0
	if state == S.DYING or state == S.DEAD:
		# se desploma hacia adelante y queda tumbado, mirando al oeste (hacia la entrada)
		var k := 1.0 if state == S.DEAD else clampf(_state_t / 5.5, 0.0, 1.0)
		k = k * k
		var lie_y := _floor_y() + 3.0
		pos = Vector3(base.x, lerpf(_y_at_death, lie_y, k), base.z)
		yaw = lerp_angle(_yaw_at_death, PI / 2.0, k)
		_tilt = lerpf(0.0, -1.45, k)
		_model.position = pos
		_model.rotation = Vector3(_tilt, yaw, 0.0)
		return
	if _player != null and state != S.SUBMERGED and state != S.SWIMMING:
		var d := _player_local() - Vector3(base.x, 0.0, base.z)
		d.y = 0.0
		if d.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 1.0 - exp(-get_process_delta_time() * 3.0))
			# se acerca a ti con el cuello, pero la cabeza nunca pasa de `min_gap`
			var shift := maxf(0.0, Vector2(head_pos.x - base.x, head_pos.z - base.z).length() - 2.0)
			var dir := d.normalized()
			pos.x += dir.x * shift
			pos.z += dir.z * shift
	if state == S.LUNGING:
		tilt_target = -0.3
	_tilt = lerpf(_tilt, tilt_target, 1.0 - exp(-get_process_delta_time() * (9.0 if state == S.LUNGING else 3.0)))
	var dt := get_process_delta_time()
	_sw_k = move_toward(_sw_k, 1.0 if state == S.SWIMMING else 0.0, dt * (1.6 if state == S.SWIMMING else 0.9))
	if _sw_k > 0.001:
		# nadando: el cuerpo va tumbado a ras del agua, con la espalda asomando
		var f := Vector2(-sin(_sw_yaw), -cos(_sw_yaw))
		var half := model_height * 0.5
		var sy := maxf(_water_y() - 0.5 + sin(_t * 1.3) * 0.25, _floor_y() + 1.8)
		var swim_pos := Vector3(_sw_c.x - f.x * half, sy, _sw_c.y - f.y * half)
		var swim_tilt := -1.45 + sin(_t * 2.1) * 0.07
		var k := smoothstep(0.0, 1.0, _sw_k)
		pos = pos.lerp(swim_pos, k)
		_tilt = lerpf(_tilt, swim_tilt, k)
		yaw = lerp_angle(yaw, _sw_yaw, k)
		_model.position = pos
		_model.rotation = Vector3(_tilt, yaw, sin(_t * 1.6) * 0.06 * k)
		return
	_model.position = pos
	_model.rotation = Vector3(_tilt, yaw, 0.0)


# ------------------------------------------------------------------ muerte del jugador

## Cabeza gigante lista para la animación de devorarte (ver KillSequence). Oculta al monstruo normal.
func make_kill_head() -> Node3D:
	var pivot := Pivot.new()
	pivot.name = "CabezaDevoradora"
	if _model != null and ResourceLoader.exists(model_path):
		# cabeza del modelo real: la boca queda justo delante de la cámara
		var kh := (load(model_path) as PackedScene).instantiate() as Node3D
		var ks := 0.8 * model_scale
		kh.scale = Vector3.ONE * ks
		kh.position = Vector3(0.0, 1.3, -0.5) - model_mouth * ks
		pivot.add_child(kh)
	else:
		var kh2 := build_head(_skin, 1.7)
		kh2.position = Vector3(0.0, 1.1, 2.3)     # el morro queda justo delante de la cámara
		pivot.add_child(kh2)
		pivot.inner = kh2
	get_parent().add_child(pivot)
	_hidden_for_kill = true
	visible = false
	return pivot
