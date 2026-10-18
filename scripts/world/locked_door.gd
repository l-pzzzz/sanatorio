class_name LockedDoor
extends Interactable
## Reja de seguridad. Se abre con la llave `lock_id`, o con energia ("power").
## Mientras esta cerrada cuenta como pared para el murcielago (grupo
## "maze_walls"); al abrirse se avisa a MazeNav para recalcular el mapa.

signal opened

const POWER := "power"
const FREE := "free"          ## Se abre sin llave (salida al final del túnel)
const ROOT_KEYS := ["hacha"]   ## Objetos que no se gastan al usarlos

@export var lock_id := "llave_enfermeria"
@export var is_exit := false
@export var exit_label := "puerta principal"   ## Cómo se llama la salida en el aviso
@export var door_size := Vector3(4.4, 3.0, 0.4)
@export var open_time := 1.6
@export var open_noise := 0.6       ## Ruido al abrir la reja (el murciélago lo oye)

var is_open := false
var busy := false
var indicator_material: StandardMaterial3D
var indicator_lights: Array[OmniLight3D] = []


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_to_group("maze_walls")
	add_to_group("doors")

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = door_size
	mesh_instance.mesh = box
	mesh_instance.position.y = door_size.y / 2.0
	mesh_instance.material_override = _make_material()
	add_child(mesh_instance)
	add_collider(door_size, Vector3(0, door_size.y / 2.0, 0))

	# Cerradura luminosa en ambas caras: roja = bloqueada, verde = abierta.
	indicator_material = StandardMaterial3D.new()
	indicator_material.emission_enabled = true
	indicator_material.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var panel_mesh := BoxMesh.new()
		panel_mesh.size = Vector3(0.5, 0.3, 0.06)
		panel.mesh = panel_mesh
		panel.position = Vector3(0, 1.3, side * (door_size.z / 2.0 + 0.02))
		panel.material_override = indicator_material
		add_child(panel)
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.6, side * 0.7)
		light.omni_range = 3.5
		light.light_energy = 0.6
		add_child(light)
		indicator_lights.append(light)
	_set_indicator(Color(1.0, 0.1, 0.08))


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var path := "res://assets/textures/sanatorium/door_metal.png"
	if lock_id == "hacha" or lock_id == FREE:
		path = "res://assets/textures/rooms/wall_organic.png"
	if ResourceLoader.exists(path):
		material.albedo_texture = load(path)
	else:
		material.albedo_color = Color(0.35, 0.3, 0.25)
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.25, 0.3333, 0.25)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material


func _set_indicator(color: Color) -> void:
	indicator_material.albedo_color = color
	indicator_material.emission = color
	for light in indicator_lights:
		light.light_color = color


func refresh_lock_state() -> void:
	# Lo llama MissionManager cuando vuelve la energia.
	if lock_id == POWER and not is_open:
		_set_indicator(Color(0.2, 1.0, 0.3))


func _can_open(player: PlayerCharacter) -> bool:
	if lock_id == FREE:
		return true
	if lock_id == POWER:
		var mm := mission()
		return mm != null and mm.power_on
	return player.has_item(lock_id)


func get_prompt(player: PlayerCharacter) -> String:
	if is_open or busy:
		return ""
	if lock_id == "hacha":
		return "[E] Cortar las raíces con el hacha" if player.has_item(lock_id) else "Raíces gruesas bloquean el paso: necesitas un hacha"
	if _can_open(player):
		return ("[E] Abrir %s" % exit_label) if is_exit else "[E] Abrir con la llave"
	if lock_id == POWER:
		return "%s (sin energía)" % exit_label.capitalize()
	return "Puerta cerrada: falta %s" % ItemInfo.display_name(lock_id)


func interact(player: PlayerCharacter) -> void:
	if is_open or busy:
		return
	if not _can_open(player):
		Sfx.play(self, "locked")
		NoiseManager.emit_noise(global_position, 0.25)
		if lock_id == POWER:
			toast("La cerradura eléctrica no responde. Hay que restaurar la energía.", 3.5)
		else:
			toast("Está cerrada con llave. Necesitas: %s." % ItemInfo.display_name(lock_id), 3.5)
		return
	if lock_id != POWER and lock_id != FREE and not ROOT_KEYS.has(lock_id):
		player.remove_item(lock_id)
	# Las raíces se cortan de verdad: se ve el hachazo y la barrera cede en el golpe.
	if lock_id == "hacha" and player.has_method("swing_axe_wait"):
		busy = true
		await player.swing_axe_wait()
		busy = false
	open()


func open() -> void:
	busy = true
	Sfx.play(self, "flesh_tear" if lock_id == "hacha" else "door")
	NoiseManager.emit_noise(global_position, open_noise)
	_set_indicator(Color(0.2, 1.0, 0.3))
	var tween := create_tween()
	# La reja se pliega hacia el suelo (antes subía y en los niveles de dos pisos
	# atravesaba el techo y se quedaba clavada en la sala de arriba).
	tween.tween_property(self, "scale:y", 0.02, open_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_opened)


func _on_opened() -> void:
	is_open = true
	busy = false
	visible = false
	collision_layer = 0
	remove_from_group("maze_walls")
	var nav := get_tree().get_first_node_in_group("maze_nav") as MazeNav
	if nav:
		nav.rebuild()
	opened.emit()
	var mm := mission()
	if mm:
		if is_exit:
			mm.report("escape", "")
		else:
			mm.report("door", lock_id)
