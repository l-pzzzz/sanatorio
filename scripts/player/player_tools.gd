class_name PlayerTools
extends Node
## Herramientas para aturdir criaturas. Se añade solo al jugador.
##   Clic izquierdo  pistola de dardos (aturde ~6 s, hace un poco de ruido)
##   G               lanzar botella (el ruido al romperse distrae)
##   Q               bengala: ciega ~4 s al murciélago que mires de frente

@export var dart_stun := 6.0
@export var flash_stun := 4.0
@export var shot_cooldown := 1.2
@export var shot_range := 22.0
@export var shot_noise := 0.55
@export var aim_assist := 0.6          ## Tolerancia (m) alrededor de la criatura al apuntar
@export var bottle_speed := 11.0
@export var flash_range := 13.0
@export var flash_cone_dot := 0.45     ## Cuánto debe estar de frente (coseno del ángulo)

var player: PlayerCharacter
var camera: Camera3D
var cooldown := 0.0
var muzzle: OmniLight3D
var screen_flash: ColorRect
var gun: Control
var gun_kick := 0.0


func _ready() -> void:
	player = get_parent() as PlayerCharacter
	camera = player.get_node("Head/Camera3D") as Camera3D
	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(0.6, 1.0, 0.7)
	muzzle.omni_range = 7.0
	muzzle.light_energy = 0.0
	muzzle.position = Vector3(0.1, -0.1, -0.7)
	camera.add_child(muzzle)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	screen_flash = ColorRect.new()
	screen_flash.color = Color(1, 1, 1, 0)
	screen_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen_flash)
	screen_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gun = _build_gun_hud()
	layer.add_child(gun)
	gun.visible = false
	player.inventory_changed.connect(func() -> void: gun.visible = player.has_item("pistola"))


func _build_gun_hud() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.anchor_top = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = -300.0
	root.offset_top = -230.0
	root.offset_right = -40.0
	root.offset_bottom = -20.0
	var parts := [
		[Vector2(40, 60), Vector2(170, 46), Color(0.16, 0.18, 0.2)],      # cañón
		[Vector2(40, 54), Vector2(170, 8), Color(0.35, 0.4, 0.45)],       # brillo superior
		[Vector2(130, 100), Vector2(54, 110), Color(0.1, 0.1, 0.12)],     # empuñadura
		[Vector2(24, 66), Vector2(18, 20), Color(0.4, 1.0, 0.55)],        # punta con dardo
	]
	for p in parts:
		var rect := ColorRect.new()
		rect.position = p[0]
		rect.size = p[1]
		rect.color = p[2]
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rect)
	return root


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	gun_kick = move_toward(gun_kick, 0.0, delta * 6.0)
	if gun:
		gun.offset_top = -230.0 + gun_kick * 18.0
		gun.offset_bottom = -20.0 + gun_kick * 18.0
		gun.rotation = -gun_kick * 0.12
	if muzzle.light_energy > 0.0:
		muzzle.light_energy = maxf(0.0, muzzle.light_energy - delta * 60.0)
	if screen_flash.color.a > 0.0:
		screen_flash.color.a = maxf(0.0, screen_flash.color.a - delta * 1.6)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or player.is_hidden or not player.is_physics_processing():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_shoot()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_G:
			_throw_bottle()
		elif event.physical_keycode == KEY_Q:
			_flash()


func _world() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


func _toast(text: String, seconds := 2.0) -> void:
	var mm := get_tree().get_first_node_in_group("mission_manager") as MissionManager
	if mm:
		mm.show_toast(text, seconds)


# ------------------------------------------------------------------- pistola

func _shoot() -> void:
	if not player.has_item("pistola") or cooldown > 0.0:
		return
	if not player.has_item("dardos"):
		_toast("Sin dardos. Busca una caja de dardos.", 2.0)
		cooldown = 0.5
		return
	cooldown = shot_cooldown
	player.remove_item("dardos")
	gun_kick = 1.0
	muzzle.light_energy = 6.0
	Sfx.play(self, "dart_shot", -4.0)
	NoiseManager.emit_noise(player.global_position, shot_noise)
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var ignore: Array[RID] = [player.get_rid()]
	for enemy: CollisionObject3D in get_tree().get_nodes_in_group("enemies"):
		ignore.append(enemy.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * shot_range, 1, ignore)
	var result := player.get_world_3d().direct_space_state.intersect_ray(query)
	var reach := shot_range
	if not result.is_empty():
		reach = from.distance_to(result["position"])
	# Apuntar con tolerancia: elige la criatura más cercana al rayo.
	var target: Node3D
	var best := aim_assist
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		for body_y in [0.4, 0.9, 1.4, 1.9]:
			var spot: Vector3 = enemy.global_position + Vector3(0, body_y, 0)
			var t := (spot - from).dot(dir)
			if t < 0.5 or t > reach + 0.4:
				continue
			var gap := (from + dir * t).distance_to(spot)
			if gap < best:
				best = gap
				target = enemy
	var end := from + dir * reach
	if target:
		end = target.global_position + Vector3(0, 0.9, 0)
		if target.has_method("stun") and target.call("stun", dart_stun, "dart", player.global_position):
			Sfx.play(self, "dart_hit", -2.0)
			_toast("¡Le diste! Está aturdida unos segundos.", 2.0)
		else:
			_toast("Ya se está recuperando: no le hace efecto.", 2.0)
	_tracer(from + dir * 0.6 + camera.global_transform.basis.x * 0.12 - camera.global_transform.basis.y * 0.1, end)


func _tracer(a: Vector3, b: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := a.distance_to(b)
	box.size = Vector3(0.02, 0.02, length)
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 1.0, 0.6)
	material.emission_enabled = true
	material.emission = Color(0.5, 1.0, 0.6)
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material
	_world().add_child(mesh)
	mesh.global_position = (a + b) / 2.0
	mesh.look_at(b, Vector3.UP)
	get_tree().create_timer(0.09).timeout.connect(mesh.queue_free)


# ------------------------------------------------------------------- botella

func _throw_bottle() -> void:
	if not player.has_item("botella"):
		return
	player.remove_item("botella")
	var bottle := RigidBody3D.new()
	bottle.collision_layer = 0
	bottle.collision_mask = 1
	bottle.mass = 0.4
	bottle.contact_monitor = true
	bottle.max_contacts_reported = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	bottle.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.06
	cyl.height = 0.26
	mesh.mesh = cyl
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.8, 0.55, 0.8)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.7, 0.45)
	material.emission_energy_multiplier = 0.5
	mesh.material_override = material
	bottle.add_child(mesh)
	_world().add_child(bottle)
	var dir := -camera.global_transform.basis.z
	bottle.global_position = camera.global_position + dir * 0.7 - Vector3(0, 0.1, 0)
	bottle.linear_velocity = dir * bottle_speed + Vector3(0, 1.5, 0)
	bottle.angular_velocity = Vector3(8, 3, 0)
	bottle.add_collision_exception_with(player)
	bottle.body_entered.connect(_bottle_hit.bind(bottle), CONNECT_ONE_SHOT)
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(bottle):
			bottle.queue_free())


func _bottle_hit(_body: Node, bottle: RigidBody3D) -> void:
	if not is_instance_valid(bottle):
		return
	var pos := bottle.global_position
	NoiseManager.emit_noise(pos, 0.9)
	Sfx.play(self, "glass_break", -2.0)
	bottle.queue_free()


# ------------------------------------------------------------------- bengala

func _flash() -> void:
	if not player.has_item("bengala"):
		return
	player.remove_item("bengala")
	Sfx.play(self, "flash_pop", -2.0)
	screen_flash.color.a = 0.85
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_energy = 14.0
	light.omni_range = 16.0
	camera.add_child(light)
	get_tree().create_timer(0.25).timeout.connect(light.queue_free)
	NoiseManager.emit_noise(player.global_position, 0.3)
	var from := camera.global_position
	var forward := -camera.global_transform.basis.z
	var affected := false
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var to_enemy := (enemy.global_position + Vector3(0, 1.0, 0)) - from
		if to_enemy.length() > flash_range or forward.dot(to_enemy.normalized()) < flash_cone_dot:
			continue
		var query := PhysicsRayQueryParameters3D.create(from, from + to_enemy, 1, [player.get_rid(), enemy.get_rid()])
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue    # una pared tapa la luz
		if enemy.has_method("stun") and enemy.call("stun", flash_stun, "flash", player.global_position):
			affected = true
	_toast("¡La luz lo cegó!" if affected else "La bengala ilumina... pero no había nada que cegar.", 2.0)
