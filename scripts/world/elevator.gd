class_name Elevator
extends Node3D
## Ascensor de dos pisos. Necesita el "fusible_ascensor". La cabina es una
## plataforma móvil; en el piso de arriba una reja tapa el hueco cuando la cabina no está.
## Las criaturas NO lo usan, pero oyen el ruido que hace al moverse.

@export var cell_size := 4.0
@export var rise := 3.4
@export var travel_time := 4.5

var entry_low := Vector3.BACK
var entry_high := Vector3.BACK
var powered := false
var at_upper := false
var moving := false
var cab: AnimatableBody3D
var gate: StaticBody3D
var gate_shape: CollisionShape3D
var noise_left := 0.0


func _ready() -> void:
	add_to_group("elevators")
	cab = AnimatableBody3D.new()
	cab.sync_to_physics = true
	cab.collision_layer = 1
	cab.collision_mask = 0
	add_child(cab)
	var size := Vector3(cell_size - 0.5, 0.2, cell_size - 0.5)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(Color(0.22, 0.23, 0.25))
	mesh.position.y = -0.1
	cab.add_child(mesh)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(cell_size - 0.3, 0.2, cell_size - 0.3)
	shape.shape = bs
	shape.position.y = -0.1
	cab.add_child(shape)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.3, 0)
	light.light_color = Color(1.0, 0.85, 0.6)
	light.light_energy = 0.7
	light.omni_range = 5.0
	cab.add_child(light)

	# Panel dentro de la cabina, en un lado que no sea ninguna entrada.
	var panel_dir := Vector3.FORWARD
	for dir: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		if dir.distance_to(entry_low) > 0.1 and dir.distance_to(entry_high) > 0.1:
			panel_dir = dir
			break
	var inside := ElevatorPanel.new()
	inside.elevator = self
	inside.call_floor = -1
	inside.position = panel_dir * (cell_size / 2.0 - 0.55)
	inside.rotation.y = atan2(-panel_dir.x, -panel_dir.z)
	cab.add_child(inside)

	_add_call_panel(entry_low, 0, 0.0)
	_add_call_panel(entry_high, 1, rise)

	# Reja del piso de arriba
	gate = StaticBody3D.new()
	gate.collision_layer = 1
	gate.collision_mask = 0
	gate.position = entry_high * (cell_size / 2.0 - 0.1) + Vector3(0, rise, 0)
	gate.rotation.y = atan2(entry_high.x, entry_high.z)
	add_child(gate)
	for i in 9:
		var bar := MeshInstance3D.new()
		var bar_box := BoxMesh.new()
		bar_box.size = Vector3(0.07, 2.6, 0.07)
		bar.mesh = bar_box
		bar.material_override = _material(Color(0.3, 0.3, 0.32))
		bar.position = Vector3(-1.6 + i * 0.4, 1.3, 0)
		gate.add_child(bar)
	for y in [0.4, 1.3, 2.4]:
		var rail := MeshInstance3D.new()
		var rail_box := BoxMesh.new()
		rail_box.size = Vector3(3.6, 0.07, 0.07)
		rail.mesh = rail_box
		rail.material_override = _material(Color(0.3, 0.3, 0.32))
		rail.position = Vector3(0, y, 0)
		gate.add_child(rail)
	gate_shape = CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(3.8, 2.6, 0.2)
	gate_shape.shape = gs
	gate_shape.position.y = 1.3
	gate.add_child(gate_shape)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _add_call_panel(entry: Vector3, floor_index: int, height: float) -> void:
	var panel := ElevatorPanel.new()
	panel.elevator = self
	panel.call_floor = floor_index
	var side := entry.cross(Vector3.UP)
	panel.position = entry * (cell_size / 2.0 + 0.55) + side * 1.5 + Vector3(0, height, 0)
	panel.rotation.y = atan2(entry.x, entry.z)
	add_child(panel)


func use_panel(player: PlayerCharacter, call_floor: int) -> void:
	var mm := get_tree().get_first_node_in_group("mission_manager") as MissionManager
	if moving:
		return
	if not powered:
		if player.has_item("fusible_ascensor"):
			player.remove_item("fusible_ascensor")
			powered = true
			Sfx.play(self, "elevator_ding")
			if mm:
				mm.show_toast(Lang.t("Fusible instalado. El ascensor tiene energía otra vez."), 3.5)
				mm.report("elevator", "powered")
		elif mm:
			mm.show_toast(Lang.t("Sin energía. Falta el fusible del ascensor (búscalo por el edificio)."), 4.0)
		return
	var target := call_floor if call_floor >= 0 else (0 if at_upper else 1)
	if (target == 1) == at_upper:
		if mm:
			mm.show_toast(Lang.t("El ascensor ya está aquí."), 1.8)
		return
	_travel(target)


func _travel(target: int) -> void:
	moving = true
	if at_upper:
		_set_gate(false)
	Sfx.play(self, "gate_slide", -4.0)
	Sfx.play(self, "elevator_hum", -6.0)
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(cab, "position:y", rise if target == 1 else 0.0, travel_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(_arrived.bind(target))


func _arrived(target: int) -> void:
	moving = false
	at_upper = (target == 1)
	if at_upper:
		_set_gate(true)
	Sfx.play(self, "elevator_ding")
	var mm := get_tree().get_first_node_in_group("mission_manager") as MissionManager
	if mm:
		mm.report("elevator", "arrived_%d" % target)


func _set_gate(open: bool) -> void:
	var tween := create_tween()
	tween.tween_property(gate, "position:y", rise + (2.8 if open else 0.0), 0.8)
	gate_shape.set_deferred("disabled", open)
	if open:
		Sfx.play(self, "gate_slide", -6.0)


func _physics_process(delta: float) -> void:
	if not moving:
		return
	noise_left -= delta
	if noise_left <= 0.0:
		noise_left = 1.2
		NoiseManager.emit_noise(cab.global_position, 0.5)
