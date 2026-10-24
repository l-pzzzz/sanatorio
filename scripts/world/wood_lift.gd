class_name WoodLift
extends Node3D
## Ascensor de madera hacia el corazón (nivel 3): una plataforma de tablas colgada de cuerdas.
## El nodo se coloca en el borde OESTE del pozo, a nivel del suelo; el pozo mide `shaft_size` y baja `depth` m.
## Se maneja con una manivela sobre la plataforma (y una de llamada arriba y otra abajo).
## Chirría y hace ruido al moverse: las criaturas lo oyen y se juntan arriba.

const WOOD := "res://assets/textures/rooms/wood.png"
const BARK := "res://assets/textures/rooms/root_bark.png"

@export var depth := 9.0
@export var shaft_size := 4.0
@export var travel_time := 14.0
@export var noise_every := 1.6
@export var noise_loudness := 0.9

var platform: AnimatableBody3D
var at_bottom := false
var moving := false
var _noise_t := 0.0
var _creak_t := 0.0
var _beam_y := 2.8
var _ropes: Array[Node3D] = []
var _rope_tops: Array[Vector3] = []
var _rope_feet: Array[Vector3] = []
var _tween: Tween


func _ready() -> void:
	add_to_group("wood_lifts")
	var wood := _mat(WOOD, Color(0.62, 0.48, 0.36), 0.6)
	var bark := _mat(BARK, Color(0.5, 0.4, 0.35), 0.6)
	var cx := shaft_size / 2.0
	var s := shaft_size - 0.2

	# plataforma de tablas (nivel del suelo arriba)
	platform = AnimatableBody3D.new()
	platform.name = "Plataforma"
	platform.sync_to_physics = true
	platform.collision_layer = 1
	platform.collision_mask = 0
	platform.position = Vector3(cx, 0.0, 0.0)
	add_child(platform)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(s, 0.25, s)
	deck.mesh = dm
	deck.material_override = wood
	deck.position.y = -0.125
	platform.add_child(deck)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(s, 0.25, s)
	cs.shape = shape
	cs.position.y = -0.125
	platform.add_child(cs)
	# vigas cruzadas debajo y barandas bajas (solo visuales)
	for sgn in [-1.0, 1.0]:
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(s, 0.14, 0.16)
		beam.mesh = bm
		beam.material_override = bark
		beam.position = Vector3(0, -0.32, sgn * s * 0.3)
		platform.add_child(beam)
	for sgn in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, 0.9, 0.12)
		post.mesh = pm
		post.material_override = bark
		post.position = Vector3(-s / 2.0 + 0.1, 0.45, sgn * (s / 2.0 - 0.1))
		platform.add_child(post)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.9, 0)
	lamp.light_color = Color(1.0, 0.6, 0.3)
	lamp.light_energy = 0.9
	lamp.omni_range = 7.0
	platform.add_child(lamp)

	# manivela sobre la plataforma
	var crank := LiftCrank.new()
	crank.name = "ManivelaPlataforma"
	crank.lift = self
	crank.mode = LiftCrank.ON_BOARD
	crank.position = Vector3(-s / 2.0 + 0.55, 0.0, 0.0)
	platform.add_child(crank)
	# manivela de llamada arriba (en la sala, junto al borde oeste) y abajo (en el túnel)
	var top_call := LiftCrank.new()
	top_call.name = "LlamadaArriba"
	top_call.lift = self
	top_call.mode = LiftCrank.CALL_TOP
	top_call.position = Vector3(-1.1, 0.0, shaft_size / 2.0 - 0.5)
	add_child(top_call)
	var bottom_call := LiftCrank.new()
	bottom_call.name = "LlamadaAbajo"
	bottom_call.lift = self
	bottom_call.mode = LiftCrank.CALL_BOTTOM
	bottom_call.position = Vector3(shaft_size + 1.0, -depth, shaft_size / 2.0 - 0.5)
	add_child(bottom_call)

	# armazón del torno arriba: dos postes, viga, tambor y cuatro cuerdas
	for sgn in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		var pm2 := BoxMesh.new()
		pm2.size = Vector3(0.25, _beam_y + 0.2, 0.25)
		p.mesh = pm2
		p.material_override = bark
		p.position = Vector3(cx, (_beam_y - 0.2) / 2.0, sgn * (shaft_size / 2.0 + 0.5))
		add_child(p)
	var cross := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.22, 0.22, shaft_size + 1.4)
	cross.mesh = cm
	cross.material_override = bark
	cross.position = Vector3(cx, _beam_y, 0.0)
	add_child(cross)
	var drum := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 0.3
	dc.bottom_radius = 0.3
	dc.height = 1.4
	dc.radial_segments = 10
	drum.mesh = dc
	drum.material_override = wood
	drum.rotation.x = PI / 2.0
	drum.position = Vector3(cx, _beam_y + 0.3, 0.0)
	add_child(drum)
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.45, 0.36, 0.22)
	rope_mat.roughness = 1.0
	for rz in [-1.0, 1.0]:
		for rx in [-1.0, 1.0]:
			var rope := Node3D.new()
			var rm := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.035
			cyl.bottom_radius = 0.035
			cyl.height = 1.0
			cyl.radial_segments = 5
			cyl.rings = 1
			rm.mesh = cyl
			rm.material_override = rope_mat
			rm.rotation.x = PI / 2.0
			rope.add_child(rm)
			add_child(rope)
			_ropes.append(rope)
			_rope_tops.append(Vector3(cx, _beam_y, rz * 1.0))
			_rope_feet.append(Vector3(cx + rx * (s / 2.0 - 0.15), 0.0, rz * (s / 2.0 - 0.15)))
	_update_ropes()


func _update_ropes() -> void:
	var py := platform.position.y
	for i in _ropes.size():
		var a := _rope_tops[i]
		var b := Vector3(_rope_feet[i].x, py + 0.5, _rope_feet[i].z)
		var rope := _ropes[i]
		rope.position = (a + b) / 2.0
		var dir := b - a
		if dir.length() > 0.01:
			rope.look_at_from_position((a + b) / 2.0, b, Vector3.RIGHT)
			rope.scale = Vector3(1, 1, dir.length())


## `want_bottom`: true = bajar, false = subir. Si ya está ahí no hace nada.
func go_to(want_bottom: bool) -> void:
	if moving or want_bottom == at_bottom:
		return
	moving = true
	_noise_t = 0.0
	_creak_t = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(platform, "position:y", -depth if want_bottom else 0.0, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_arrived.bind(want_bottom))
	Sfx.play(self, "lift_start", 0.0)


func _arrived(bottom: bool) -> void:
	moving = false
	at_bottom = bottom
	Sfx.play(self, "lift_stop", 0.0)
	NoiseManager.emit_noise(platform.global_position, noise_loudness)


## Para cargar partida: coloca la plataforma sin animación.
func set_position_instantly(bottom: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	moving = false
	at_bottom = bottom
	platform.position.y = -depth if bottom else 0.0
	_update_ropes()


func _physics_process(delta: float) -> void:
	_update_ropes()
	if not moving:
		return
	_noise_t -= delta
	_creak_t -= delta
	if _noise_t <= 0.0:
		_noise_t = noise_every
		# el ruido sale de arriba: así las criaturas se juntan en la boca del pozo
		NoiseManager.emit_noise(global_position + Vector3(shaft_size / 2.0, 0.0, 0.0), noise_loudness)
	if _creak_t <= 0.0:
		_creak_t = 2.4
		Sfx.play(self, "lift_creak", -4.0)


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
