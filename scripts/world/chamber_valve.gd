class_name ChamberValve
extends Interactable
## Válvula de la cámara inundada (nivel 3). Hay 3: cada una baja el nivel del agua una etapa.
## Girarla hace ruido (las criaturas lo oyen) y enfurece al Leviatán.

signal turned(valve: ChamberValve)

@export var valve_index := 1
@export var turn_time := 5.0

var is_turned := false
var busy := false
var wheel: Node3D
var lamp_mat: StandardMaterial3D
var chamber: Node = null


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	var iron := Color(0.32, 0.2, 0.14)
	# pedestal + tubo + rueda
	add_box(Vector3(0.7, 1.0, 0.7), Vector3(0, 0.5, 0), Color(0.22, 0.2, 0.2), 0.0)
	add_box(Vector3(0.22, 0.5, 0.22), Vector3(0, 1.25, 0), iron, 0.0)
	wheel = Node3D.new()
	wheel.position = Vector3(0, 1.55, 0)
	add_child(wheel)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.36
	tm.rings = 16
	tm.ring_segments = 8
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.16, 0.1)
	m.roughness = 0.8
	m.metallic = 0.4
	ring.material_override = m
	wheel.add_child(ring)
	for i in 3:
		var spoke := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.06, 0.06)
		spoke.mesh = bm
		spoke.material_override = m
		spoke.rotation.y = PI * float(i) / 3.0
		wheel.add_child(spoke)
	# piloto: rojo = cerrada, verde = ya girada
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.emission_enabled = true
	lamp_mat.emission_energy_multiplier = 2.2
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	lamp.mesh = sm
	lamp.material_override = lamp_mat
	lamp.position = Vector3(0, 1.1, 0.38)
	add_child(lamp)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0.5)
	light.omni_range = 4.0
	light.light_energy = 0.5
	light.name = "Piloto"
	add_child(light)
	_set_lamp(Color(1.0, 0.12, 0.08))
	add_collider(Vector3(0.9, 1.9, 0.9), Vector3(0, 0.95, 0))


func _set_lamp(c: Color) -> void:
	lamp_mat.albedo_color = c
	lamp_mat.emission = c
	var l := get_node_or_null("Piloto") as OmniLight3D
	if l:
		l.light_color = c


func get_prompt(_player: PlayerCharacter) -> String:
	if is_turned:
		return ""
	if busy:
		return ""
	return Lang.t("[E] Girar la válvula (%d/3)") % valve_index


func interact(_player: PlayerCharacter) -> void:
	if is_turned or busy:
		return
	busy = true
	Sfx.play(self, "valve_turn", 0.0)
	NoiseManager.emit_noise(global_position, 1.3)
	var tw := create_tween()
	tw.tween_property(wheel, "rotation:y", -TAU * 2.0, turn_time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_done)
	if chamber != null and chamber.has_method("on_valve_started"):
		chamber.on_valve_started(self)


func _done() -> void:
	is_turned = true
	busy = false
	_set_lamp(Color(0.2, 1.0, 0.35))
	turned.emit(self)


## Al cargar una partida: la válvula ya estaba girada.
func set_turned_silently() -> void:
	is_turned = true
	busy = false
	if wheel:
		wheel.rotation.y = -TAU * 2.0
	_set_lamp(Color(0.2, 1.0, 0.35))
