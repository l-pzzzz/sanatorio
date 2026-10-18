class_name PlayerCharacter
extends CharacterBody3D

signal inventory_changed
signal flashlight_toggled(on: bool)
signal hiding_changed(hidden: bool)

@export var walk_speed := 3.0
@export var crouch_speed := 1.5
@export var acceleration := 14.0
@export var jump_velocity := 4.5
@export var stand_height := 1.8
@export var crouch_height := 1.0
@export var crouch_transition_speed := 4.0
@export var mouse_sensitivity := 0.002
@export var hands_height_ratio := 0.9
@export var bob_frequency := 9.0
@export var bob_amplitude := Vector2(6.0, 8.0)
@export var interact_range := 2.6          ## Alcance para usar objetos con E (m)
@export var flashlight_energy := 6.0       ## Intensidad de la linterna
@export var flashlight_range := 18.0       ## Alcance de la linterna (m)
@export var step_distance_walk := 1.7      ## Metros que avanzas por paso al caminar
@export var step_distance_crouch := 1.1    ## Metros por paso agachado
@export var step_loudness := 0.18          ## Ruido de cada paso que oye el murciélago (agachado: silencio)
@export var land_loudness := 0.45          ## Ruido al caer de un salto
@export var locker_loudness := 0.12        ## Ruido al entrar o salir de un casillero
@export var hide_look_yaw := 30.0          ## Cuánto puedes girar la vista dentro del escondite (grados)
@export var hide_look_pitch := 15.0        ## Cuánto puedes mirar arriba o abajo dentro del escondite

@onready var head: Node3D = $Head
@onready var collision: CollisionShape3D = $Collision
@onready var hands: TextureRect = $HandsLayer/Hands

## Cuerpo 3D completo (Mixamo). Sustituye a las manos 2D; si no carga, se usan las manos de siempre.
@export var use_body := true
@export var eye_height_crouch := 0.95   ## Altura de la cámara al agacharse (m)
var body: PlayerBody

var height := 0.0
var bob_time := 0.0
var hands_offset := Vector2.ZERO
var hands_rest := Vector2.ZERO

var inventory := {}                 # id -> cantidad
var has_flashlight := false
var flashlight_on := false
var flashlight: SpotLight3D
var interact_ray: RayCast3D
var prompt_label: Label
var is_hidden := false
var hidden_in: Node3D
var hide_overlay: Control
var flashlight_before_hide := false
var hide_yaw := 0.0
var step_accum := 0.0
var step_index := 0
var was_on_floor := true


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	collision.shape = collision.shape.duplicate()
	height = stand_height
	get_viewport().size_changed.connect(_layout_hands)
	_layout_hands()
	_setup_flashlight()
	_setup_interaction()
	floor_snap_length = 0.6       # para no "saltar" bajando las escaleras
	add_child(PlayerTools.new())
	if use_body:
		body = PlayerBody.new()
		add_child(body)
		body.setup(self)
		hands.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if is_hidden:
			var wanted_yaw: float = rotation.y - event.relative.x * mouse_sensitivity
			rotation.y = hide_yaw + clampf(angle_difference(hide_yaw, wanted_yaw), -deg_to_rad(hide_look_yaw), deg_to_rad(hide_look_yaw))
			head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity, -deg_to_rad(hide_look_pitch), deg_to_rad(hide_look_pitch))
		else:
			rotate_y(-event.relative.x * mouse_sensitivity)
			head.rotation.x = clampf(head.rotation.x - event.relative.y * mouse_sensitivity, -deg_to_rad(85.0), deg_to_rad(85.0))
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if is_hidden:
		velocity = Vector3.ZERO
		_update_prompt()
		return
	var blocked := test_move(global_transform, Vector3.UP * (stand_height - height))
	var crouching := Input.is_action_pressed("crouch") or (height < stand_height and blocked)
	height = move_toward(height, crouch_height if crouching else stand_height, crouch_transition_speed * delta)
	collision.shape.height = height
	collision.position.y = height / 2.0
	head.position.y = _eye_height()

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_velocity

	var speed := crouch_speed if crouching else walk_speed
	var move_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target := (transform.basis * Vector3(move_input.x, 0.0, move_input.y)).normalized() * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	var vertical_before := velocity.y
	move_and_slide()
	_update_footsteps(delta, crouching, vertical_before)
	_bob_hands(delta, speed)
	_update_prompt()


## Altura de los ojos: de pie (alto-0.2) y agachado (eye_height_crouch), interpolada con la altura actual.
func _eye_height() -> float:
	var t := clampf((height - crouch_height) / maxf(stand_height - crouch_height, 0.01), 0.0, 1.0)
	return lerpf(eye_height_crouch, stand_height - 0.2, t)


## Golpe de hacha con el cuerpo 3D. Devuelve true si empezó el golpe.
func swing_axe() -> bool:
	return body != null and body.swing_axe()


## Hachazo y espera al momento del impacto. Nunca se cuelga: si no hay cuerpo o la animación no
## llega al golpe, continúa solo tras un tiempo máximo.
func swing_axe_wait() -> void:
	if body == null or not body.swing_axe():
		await get_tree().create_timer(0.6).timeout
		return
	var state := {"hit": false}
	body.swing_hit.connect(func() -> void: state["hit"] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not state["hit"] and waited < 1.4:
		await get_tree().process_frame
		waited += get_process_delta_time()


# ------------------------------------------------------------------ inventario

func add_item(id: String, amount := 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + amount
	if id == "linterna":
		has_flashlight = true
		if not flashlight_on:
			toggle_flashlight()
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return int(inventory.get(id, 0)) > 0


func count_item(id: String) -> int:
	return int(inventory.get(id, 0))


func remove_item(id: String, amount := 1) -> void:
	var left := int(inventory.get(id, 0)) - amount
	if left <= 0:
		inventory.erase(id)
	else:
		inventory[id] = left
	inventory_changed.emit()


# -------------------------------------------------------------------- linterna

func _setup_flashlight() -> void:
	flashlight = SpotLight3D.new()
	flashlight.spot_range = flashlight_range
	flashlight.spot_angle = 32.0
	flashlight.light_energy = flashlight_energy
	flashlight.light_color = Color(1.0, 0.95, 0.8)
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.12, -0.1, 0.0)
	flashlight.visible = false
	head.add_child(flashlight)


func toggle_flashlight() -> void:
	if not has_flashlight:
		return
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on
	Sfx.play(self, "click", -10.0)
	flashlight_toggled.emit(flashlight_on)


# ----------------------------------------------------------------- interaccion

func _setup_interaction() -> void:
	interact_ray = RayCast3D.new()
	interact_ray.target_position = Vector3(0.0, 0.0, -interact_range)
	interact_ray.collision_mask = 3          # capa 1 (paredes) + capa 2 (interactivos)
	interact_ray.add_exception(self)
	head.add_child(interact_ray)

	var layer: Node = $HandsLayer
	_build_hide_overlay(layer)
	prompt_label = Label.new()
	prompt_label.anchor_left = 0.0
	prompt_label.anchor_right = 1.0
	prompt_label.anchor_top = 0.58
	prompt_label.anchor_bottom = 0.66
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 6)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(prompt_label)

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.45)
	dot.anchor_left = 0.5
	dot.anchor_right = 0.5
	dot.anchor_top = 0.5
	dot.anchor_bottom = 0.5
	dot.offset_left = -2.0
	dot.offset_right = 2.0
	dot.offset_top = -2.0
	dot.offset_bottom = 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dot)


func _current_interactable() -> Node:
	if interact_ray == null or not interact_ray.is_colliding():
		return null
	var collider := interact_ray.get_collider() as Node
	if collider != null and collider.has_method("interact"):
		return collider
	return null


func _update_prompt() -> void:
	if is_hidden:
		prompt_label.text = "[E] Salir del escondite   (no hagas ruido)"
		return
	var target := _current_interactable()
	prompt_label.text = str(target.call("get_prompt", self)) if target else ""


func _try_interact() -> void:
	if not is_physics_processing() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if is_hidden:
		leave_hiding()
		return
	var target := _current_interactable()
	if target:
		target.call("interact", self)


# ----------------------------------------------------------------------- manos

func _layout_hands() -> void:
	var view := get_viewport().get_visible_rect().size
	hands.size = hands.texture.get_size() * maxf(1.0, floorf(view.y * hands_height_ratio / hands.texture.get_height()))
	hands_rest = Vector2((view.x - hands.size.x) / 2.0, view.y - hands.size.y + bob_amplitude.y)


func _bob_hands(delta: float, max_speed: float) -> void:
	var weight := clampf(Vector2(velocity.x, velocity.z).length() / max_speed, 0.0, 1.0)
	if is_on_floor():
		bob_time += delta * bob_frequency * weight
	var target := Vector2(sin(bob_time), -absf(cos(bob_time))) * bob_amplitude * weight
	hands_offset = hands_offset.lerp(target, minf(delta * 10.0, 1.0))
	hands.position = (hands_rest + hands_offset).round()


# ---------------------------------------------------------------------- pasos

# Cada paso suena (más fuerte al caminar, casi nada agachado). Solo los pasos al
# caminar y los aterrizajes los oye el murciélago; agachado eres silencioso.
func _update_footsteps(delta: float, crouching: bool, vertical_before: float) -> void:
	var on_floor_now := is_on_floor()
	if on_floor_now and not was_on_floor and vertical_before < -3.5:
		Sfx.play(self, "land", -6.0)
		NoiseManager.emit_noise(global_position, land_loudness)
	was_on_floor = on_floor_now
	if not on_floor_now:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.6:
		step_accum = 0.0
		return
	step_accum += horizontal_speed * delta
	var stride := step_distance_crouch if crouching else step_distance_walk
	if step_accum < stride:
		return
	step_accum -= stride
	step_index += 1
	if crouching:
		Sfx.play(self, "step_soft_%d" % (step_index % 2 + 1), -20.0)
	else:
		Sfx.play(self, "step_%d" % (step_index % 4 + 1), -10.0)
		NoiseManager.emit_noise(global_position, step_loudness)


# ------------------------------------------------------------------ esconderse

func enter_hiding(spot: Node3D) -> void:
	if is_hidden:
		return
	hidden_in = spot
	is_hidden = true
	flashlight_before_hide = flashlight_on
	if flashlight_on:
		toggle_flashlight()
	velocity = Vector3.ZERO
	step_accum = 0.0
	collision.set_deferred("disabled", true)
	global_position = spot.call("hide_position")
	rotation.y = float(spot.call("facing_yaw"))
	hide_yaw = rotation.y
	if spot.has_method("set_inside"):
		spot.call("set_inside", true)
	head.rotation.x = 0.0
	height = stand_height
	head.position.y = height - 0.2
	hands.visible = false
	hide_overlay.visible = true
	Sfx.play(self, "locker_open", -8.0)
	NoiseManager.emit_noise(global_position, locker_loudness)
	hiding_changed.emit(true)


func leave_hiding() -> void:
	if not is_hidden:
		return
	var spot := hidden_in
	is_hidden = false
	hidden_in = null
	if spot:
		global_position = spot.call("exit_position")
	if spot and spot.has_method("set_inside"):
		spot.call("set_inside", false)
	collision.set_deferred("disabled", false)
	hands.visible = (body == null)
	hide_overlay.visible = false
	if flashlight_before_hide and not flashlight_on:
		toggle_flashlight()
	Sfx.play(self, "locker_close", -8.0)
	NoiseManager.emit_noise(global_position, locker_loudness)
	hiding_changed.emit(false)


# Vista desde dentro del casillero: todo oscuro salvo unas rendijas.
func _build_hide_overlay(layer: Node) -> void:
	hide_overlay = Control.new()
	hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide_overlay.visible = false
	layer.add_child(hide_overlay)
	hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bars := [[0.0, 0.30], [0.325, 0.40], [0.425, 0.50], [0.525, 0.60], [0.625, 0.70], [0.725, 1.0]]
	for bar in bars:
		var rect := ColorRect.new()
		rect.color = Color(0.02, 0.02, 0.02, 1.0)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.anchor_left = 0.0
		rect.anchor_right = 1.0
		rect.anchor_top = bar[0]
		rect.anchor_bottom = bar[1]
		hide_overlay.add_child(rect)
