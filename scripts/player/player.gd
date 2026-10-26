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

# --- multijugador: un PlayerCharacter "remoto" es el títere de otro jugador (ver Net)
var is_remote := false
var net_id := 1
var net_label := ""
var net_has_state := false
var net_dead := false
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_hide_mismatch := 0.0
var _name_tag: Label3D


func _ready() -> void:
	if is_remote:
		_ready_remote()
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	collision.shape = collision.shape.duplicate()
	height = stand_height
	get_viewport().size_changed.connect(_layout_hands)
	_layout_hands()
	_setup_flashlight()
	_setup_interaction()
	floor_snap_length = 0.6       # para no "saltar" bajando las escaleras
	add_child(PlayerTools.new())
	if get_tree().get_first_node_in_group("touch_controls") == null:      # se muestra solo en pantallas táctiles (o con F10)
		get_parent().add_child.call_deferred(TouchControls.new())
	if use_body:
		body = PlayerBody.new()
		add_child(body)
		body.setup(self)
		hands.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if PauseMenu.is_open:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.device != InputEvent.DEVICE_ID_EMULATION:
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
	if is_remote:
		_remote_tick(delta)
		return
	if is_hidden:
		velocity = Vector3.ZERO
		_update_prompt()
		return
	var blocked := test_move(global_transform, Vector3.UP * (stand_height - height))
	var locked := PauseMenu.is_open        # en red la pausa no congela el juego: solo te quedas quieto
	var crouching := (Input.is_action_pressed("crouch") and not locked) or (height < stand_height and blocked)
	height = move_toward(height, crouch_height if crouching else stand_height, crouch_transition_speed * delta)
	collision.shape.height = height
	collision.position.y = height / 2.0
	head.position.y = _eye_height()

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif Input.is_action_just_pressed("jump") and not crouching and not locked:
		velocity.y = jump_velocity

	var speed := crouch_speed if crouching else walk_speed
	var move_input := Vector2.ZERO if locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
		if not flashlight_on and not is_remote:
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
	# Objeto del equipo gastado por un compañero (acción repetida): tú también lo pierdes.
	if is_remote and Net.replaying and Net.is_shared_item(id):
		var me := get_tree().get_first_node_in_group("player") as PlayerCharacter
		if me != null and me != self:
			me.remove_item(id, amount)


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
		prompt_label.text = Lang.t("[E] Salir del escondite   (no hagas ruido)")
		return
	var target := _current_interactable()
	prompt_label.text = str(target.call("get_prompt", self)) if target else ""


func _try_interact() -> void:
	if not is_physics_processing() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if is_hidden:
		Net.send_leave_hiding()
		leave_hiding()
		return
	var target := _current_interactable()
	if target:
		Net.send_interact(target)     # en red: los demás repiten esta acción con tu títere
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
	if hide_overlay:
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
	hands.visible = (body == null) and not is_remote
	if hide_overlay:
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


# ------------------------------------------------------------- multijugador

## Títere de otro jugador: sin cámara, sin HUD ni controles; se mueve con lo que llega por red.
func _ready_remote() -> void:
	collision.shape = collision.shape.duplicate()
	height = stand_height
	collision_layer = 1           # capa 1: así el murciélago (anfitrión) puede verlo con su rayo
	collision_mask = 0
	set_process_unhandled_input(false)
	($Head/Camera3D as Camera3D).current = false
	$HandsLayer.visible = false
	hands.visible = false
	_setup_flashlight()
	flashlight.shadow_enabled = false
	if use_body:
		body = PlayerBody.new()
		add_child(body)
		body.setup(self)
		body.head_mesh.visible = true      # a los demás sí se les ve la cabeza
	_name_tag = Label3D.new()
	_name_tag.text = net_label
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.fixed_size = true
	_name_tag.pixel_size = 0.0014
	_name_tag.font_size = 28
	_name_tag.outline_size = 8
	_name_tag.modulate = Color(0.85, 0.8, 0.75, 0.85)
	_name_tag.position = Vector3(0, stand_height + 0.35, 0)
	add_child(_name_tag)


## Estado que manda el dueño de este títere ~20 veces por segundo.
func net_apply(pos: Vector3, yaw: float, pitch: float, h: float, vel: Vector3, flash: bool, hidden: bool, dead_flag: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch
	height = h
	velocity = vel
	if flashlight and not dead_flag:
		flashlight_on = flash
		flashlight.visible = flash
	if not net_has_state:
		net_has_state = true
		global_position = pos
		rotation.y = yaw
		visible = not dead_flag
	net_set_dead(dead_flag)
	# La acción de esconderse llega aparte; esto solo corrige si quedaron desincronizados.
	if hidden != is_hidden:
		_net_hide_mismatch += 1.0 / 20.0
		if _net_hide_mismatch > 0.6:
			is_hidden = hidden
			if not hidden:
				hidden_in = null
			hiding_changed.emit(hidden)
	else:
		_net_hide_mismatch = 0.0


func net_set_dead(on: bool) -> void:
	if on == net_dead:
		return
	net_dead = on
	visible = not on
	collision_layer = 0 if on else 1
	if on and flashlight:
		flashlight_on = false
		flashlight.visible = false


func _remote_tick(delta: float) -> void:
	if not net_has_state:
		return
	var k := 1.0 - exp(-15.0 * delta)
	if global_position.distance_to(_net_pos) > 4.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, k)
	rotation.y = lerp_angle(rotation.y, _net_yaw, k)
	head.rotation.x = lerpf(head.rotation.x, _net_pitch, k)
	head.position.y = _eye_height()
	collision.shape.height = height
	collision.position.y = height / 2.0
	if _name_tag:
		_name_tag.visible = not is_hidden
		_name_tag.position.y = height + 0.35
