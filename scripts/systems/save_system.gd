extends Node
## Guardado y carga de partidas (autoload "SaveSystem"). 3 ranuras en user://saves/.
##
## Qué se guarda: nivel, dificultad, jugador (posición, vista, inventario, linterna),
## misiones (MissionManager.export_state), objetos que siguen en el mapa, puertas
## abiertas, ascensores, generadores y posición de las criaturas.
##
## Cómo se carga: load_slot() deja los datos en `pending` y cambia de escena. Al
## arrancar el nivel, MissionManager._ready ve que hay datos pendientes y llama a
## apply_pending(), que espera a que el laberinto y las criaturas estén listos y
## restaura todo.
##
## No se puede guardar escondido, con el ascensor en marcha, mientras algo te
## persigue o si la partida ya terminó (can_save devuelve el motivo).

const SAVE_DIR := "user://saves"
const SLOTS := 3
const VERSION := 1
const THUMB_SIZE := Vector2i(192, 108)

var pending: Dictionary = {}


# ------------------------------------------------------------------ ranuras

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func thumb_path(slot: int) -> String:
	return "%s/slot_%d.png" % [SAVE_DIR, slot]


## Datos de la ranura, o {} si está vacía o dañada.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != VERSION or not ResourceLoader.exists(str(data.get("scene", ""))):
		return {}
	return data


func read_thumbnail(slot: int) -> Texture2D:
	var path := thumb_path(slot)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


# ------------------------------------------------------------------ guardar

## "" si se puede guardar ahora; si no, el motivo (en español, sin traducir).
func can_save() -> String:
	if Net.is_online():
		return "Guardar y cargar no están disponibles en multijugador."
	var mm := _mission()
	if mm == null or mm.player == null:
		return "No hay ninguna partida en curso."
	if mm.state != MissionManager.State.PLAYING:
		return "La partida ya terminó."
	if mm.player.is_hidden:
		return "No puedes guardar dentro de un escondite."
	for elevator in _nodes_of(Elevator):
		if (elevator as Elevator).moving:
			return "Espera a que el ascensor se detenga."
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if _is_chasing(enemy):
			return "¡Algo te persigue! No puedes guardar ahora."
	return ""


## Guarda en la ranura. `thumbnail` es la captura del momento de la pausa (puede ser null).
func save_to_slot(slot: int, thumbnail: Image = null) -> bool:
	if can_save() != "":
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: no se pudo escribir %s (%s)" % [slot_path(slot), error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(capture(), "\t"))
	file.close()
	if thumbnail != null and not thumbnail.is_empty():
		var small := thumbnail.duplicate() as Image
		small.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		small.save_png(thumb_path(slot))
	elif FileAccess.file_exists(thumb_path(slot)):
		DirAccess.remove_absolute(thumb_path(slot))
	return true


func capture() -> Dictionary:
	var scene := get_tree().current_scene
	var mm := _mission()
	var player := mm.player
	var mission := mm.export_state()

	var pickups: Array = []
	for item in _nodes_of(PickupItem):
		if not (item as PickupItem).taken:
			pickups.append(str(scene.get_path_to(item)))

	var doors: Array = []
	var opened: Array = mission["doors_opened"]
	for node in _nodes_of(LockedDoor):
		var door := node as LockedDoor
		if door.is_open or (door.busy and not door.is_exit):
			doors.append(str(scene.get_path_to(door)))
			if not opened.has(door.lock_id) and door.lock_id != LockedDoor.FREE:
				opened.append(door.lock_id)    # se estaba abriendo justo al guardar

	var elevators: Array = []
	for node in _nodes_of(Elevator):
		var elevator := node as Elevator
		elevators.append({"path": str(scene.get_path_to(elevator)), "powered": elevator.powered, "at_upper": elevator.at_upper})

	var generators: Array = []
	for node in _nodes_of(PowerGenerator):
		var generator := node as PowerGenerator
		generators.append({"path": str(scene.get_path_to(generator)), "inserted": generator.inserted, "running": generator.running})

	var enemies: Array = []
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		enemies.append({"path": str(scene.get_path_to(enemy)), "pos": _v3(enemy.global_position), "yaw": enemy.rotation.y})

	return {
		"version": VERSION,
		"scene": scene.scene_file_path,
		"level_title": mm.level_title(),
		"difficulty": Difficulty.level,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"play_time": mm.play_time,
		"player": {
			"pos": _v3(player.global_position),
			"yaw": player.rotation.y,
			"pitch": player.head.rotation.x,
			"inventory": player.inventory.duplicate(),
			"has_flashlight": player.has_flashlight,
			"flashlight_on": player.flashlight_on,
		},
		"mission": mission,
		"world": {
			"pickups": pickups,
			"doors_open": doors,
			"elevators": elevators,
			"generators": generators,
			"enemies": enemies,
		},
	}


# ------------------------------------------------------------------- cargar

## Prepara la carga y cambia al nivel guardado. Devuelve false si la ranura no sirve.
func load_slot(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	pending = data
	Difficulty.level = clampi(int(data.get("difficulty", 1)), 0, 2)
	get_tree().paused = false
	get_tree().change_scene_to_file(str(data["scene"]))
	return true


func has_pending() -> bool:
	return not pending.is_empty()


## La llama MissionManager._ready del nivel recién cargado.
func apply_pending(mm: MissionManager) -> void:
	var data := pending
	pending = {}
	# Las criaturas arrancan su patrulla con call_deferred y el laberinto se arma en _ready:
	# esperamos un par de frames de física para no pisarles la inicialización.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(mm):
		return
	_apply(data, mm)
	mm.finish_load()


func _apply(data: Dictionary, mm: MissionManager) -> void:
	var scene := get_tree().current_scene
	var world: Dictionary = data.get("world", {})

	# Objetos: quita los que ya se habían recogido.
	var keep := {}
	for p in world.get("pickups", []):
		keep[str(p)] = true
	for item in _nodes_of(PickupItem):
		if not keep.has(str(scene.get_path_to(item))):
			item.queue_free()

	# Puertas abiertas: se dejan abiertas al instante, sin animación ni avisos.
	var doors_open := {}
	for p in world.get("doors_open", []):
		doors_open[str(p)] = true
	for node in _nodes_of(LockedDoor):
		var door := node as LockedDoor
		if doors_open.has(str(scene.get_path_to(door))):
			door.is_open = true
			door.busy = false
			door.visible = false
			door.collision_layer = 0
			door.remove_from_group("maze_walls")
			door._set_indicator(Color(0.2, 1.0, 0.3))
	var nav := get_tree().get_first_node_in_group("maze_nav") as MazeNav
	if nav:
		nav.rebuild()

	for e: Dictionary in world.get("elevators", []):
		var elevator := scene.get_node_or_null(NodePath(str(e["path"]))) as Elevator
		if elevator == null:
			continue
		elevator.powered = bool(e["powered"])
		elevator.at_upper = bool(e["at_upper"])
		elevator.cab.position.y = elevator.rise if elevator.at_upper else 0.0
		elevator.gate.position.y = elevator.rise + (2.8 if elevator.at_upper else 0.0)
		elevator.gate_shape.disabled = elevator.at_upper

	for g: Dictionary in world.get("generators", []):
		var generator := scene.get_node_or_null(NodePath(str(g["path"]))) as PowerGenerator
		if generator == null:
			continue
		generator.inserted = int(g["inserted"])
		generator.running = bool(g["running"])
		generator._update_indicators()

	# Jugador
	var player := mm.player
	var pd: Dictionary = data.get("player", {})
	if player and not pd.is_empty():
		player.velocity = Vector3.ZERO
		player.global_position = _to_v3(pd["pos"])
		player.rotation.y = float(pd["yaw"])
		player.head.rotation.x = float(pd["pitch"])
		player.inventory.clear()
		var inventory: Dictionary = pd.get("inventory", {})
		for id in inventory:
			player.inventory[str(id)] = int(inventory[id])
		player.has_flashlight = bool(pd.get("has_flashlight", false))
		player.flashlight_on = player.has_flashlight and bool(pd.get("flashlight_on", false))
		player.flashlight.visible = player.flashlight_on
		player.inventory_changed.emit()

	# Criaturas: vuelven a su sitio y empiezan a patrullar desde ahí (sin perseguirte).
	for e: Dictionary in world.get("enemies", []):
		var enemy := scene.get_node_or_null(NodePath(str(e["path"]))) as CharacterBody3D
		if enemy == null:
			continue
		enemy.velocity = Vector3.ZERO
		enemy.global_position = _to_v3(e["pos"])
		enemy.rotation.y = float(e["yaw"])
		if enemy.has_method("_start_wander"):
			enemy.call("_start_wander")

	mm.import_state(data.get("mission", {}))


# ------------------------------------------------------------------ ayudas

func _mission() -> MissionManager:
	return get_tree().get_first_node_in_group("mission_manager") as MissionManager


## Todos los nodos de la escena actual cuyo script es (o hereda de) `type`.
func _nodes_of(type: Variant) -> Array[Node]:
	var out: Array[Node] = []
	var scene := get_tree().current_scene
	if scene == null:
		return out
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if is_instance_of(node, type) and not node.is_queued_for_deletion():
			out.append(node)
		stack.append_array(node.get_children())
	return out


func _is_chasing(enemy: Node) -> bool:
	if enemy is EcoCreature:
		var eco := enemy as EcoCreature
		return eco.state == EcoCreature.State.HUNT or eco.state == EcoCreature.State.ATTACK
	# Murciélago: está cazando y te vio hace poco.
	if "last_seen_time" in enemy and "state" in enemy:
		return int(enemy.get("state")) == 1 and Time.get_ticks_msec() / 1000.0 - float(enemy.get("last_seen_time")) < 6.0
	return false


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _to_v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
