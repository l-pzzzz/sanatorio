class_name TouchControls
extends CanvasLayer
## Controles táctiles para celular. Solo aparecen en pantallas táctiles (o con F10 en la PC para probar).
##   - Izquierda de la pantalla: arrastra para moverte (joystick flotante).
##   - Derecha: arrastra para mirar.
##   - Botones: INTERACTUAR, SALTAR, AGACHARSE, DISPARAR, LINTERNA, BOTELLA, BENGALA, MISIONES, PAUSA.
## Los botones de disparar/botella/bengala solo salen cuando tienes ese objeto.
## Todo se traduce a las mismas acciones que usa el teclado, así el resto del juego no cambia.

const LOOK_MULT := 1.7             ## Multiplicador de la sensibilidad al arrastrar para mirar
const STICK_RADIUS := 90.0
const DESIGN_H := 648.0

static func is_wanted() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

var force_show := false
var pad: Control
var player: PlayerCharacter
var _fingers := {}                 ## índice de dedo -> "stick" | "look" | id de botón
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _held := {}                    ## id de botón -> true mientras está pulsado
var _crouch_on := false
var _last_active := false

## id, texto, centro (en fracción de pantalla + desplazamiento en px de diseño), radio, tipo
var _buttons: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("touch_controls")
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	pad = Control.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func _s() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / DESIGN_H, 0.8, 1.8)


func _layout() -> void:
	var v := get_viewport().get_visible_rect().size
	var s := _s()
	_buttons = [
		{"id": "interact", "text": "E", "label": "ACCIÓN", "pos": Vector2(v.x - 120.0 * s, v.y - 150.0 * s), "r": 70.0 * s, "kind": "tap"},
		{"id": "jump", "text": "↑", "label": "SALTAR", "pos": Vector2(v.x - 255.0 * s, v.y - 90.0 * s), "r": 50.0 * s, "kind": "hold"},
		{"id": "crouch", "text": "↓", "label": "AGACHAR", "pos": Vector2(v.x - 70.0 * s, v.y - 300.0 * s), "r": 44.0 * s, "kind": "toggle"},
		{"id": "shoot", "text": "◎", "label": "DISPARAR", "pos": Vector2(v.x - 260.0 * s, v.y - 235.0 * s), "r": 52.0 * s, "kind": "tap", "need": "pistola"},
		{"id": "flashlight", "text": "F", "label": "LINTERNA", "pos": Vector2(v.x - 385.0 * s, v.y - 80.0 * s), "r": 38.0 * s, "kind": "tap"},
		{"id": "bottle", "text": "G", "label": "BOTELLA", "pos": Vector2(v.x - 385.0 * s, v.y - 175.0 * s), "r": 36.0 * s, "kind": "tap", "need": "botella"},
		{"id": "flare", "text": "Q", "label": "BENGALA", "pos": Vector2(v.x - 385.0 * s, v.y - 265.0 * s), "r": 36.0 * s, "kind": "tap", "need": "bengala"},
		{"id": "missions", "text": "☰", "label": "MISIONES", "pos": Vector2(v.x * 0.5 - 70.0 * s, 44.0 * s), "r": 30.0 * s, "kind": "tap"},
		{"id": "pause", "text": "II", "label": "PAUSA", "pos": Vector2(v.x * 0.5 + 70.0 * s, 44.0 * s), "r": 30.0 * s, "kind": "tap"},
	]
	pad.queue_redraw()


func _button_visible(b: Dictionary) -> bool:
	if not b.has("need"):
		return true
	return player != null and player.has_item(str(b["need"]))


func _is_active() -> bool:
	if not (force_show or is_wanted()):
		return false
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as PlayerCharacter
		if player == null:
			return false
	if not player.is_physics_processing():
		return false
	var pm := get_node_or_null("/root/PauseMenu")
	if pm != null and pm.get("is_open") == true:
		return false
	return true


func _process(_delta: float) -> void:
	var active := _is_active()
	if active != _last_active:
		_last_active = active
		visible = active
		if not active:
			_release_all()
	if active:
		_apply_stick()
		pad.queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	# F10: muestra/oculta los controles en la PC (para probarlos)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		force_show = not force_show


# ------------------------------------------------------------------ entrada

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_move(d.index, d.position, d.relative)
		get_viewport().set_input_as_handled()


func _touch_down(idx: int, pos: Vector2) -> void:
	for b in _buttons:
		if not _button_visible(b):
			continue
		if pos.distance_to(b["pos"]) <= float(b["r"]) + 10.0:
			_fingers[idx] = str(b["id"])
			_press_button(b)
			return
	var v := get_viewport().get_visible_rect().size
	if pos.x < v.x * 0.45 and not _fingers.values().has("stick"):
		_fingers[idx] = "stick"
		_stick_origin = pos
		_stick_pos = pos
		_stick_vec = Vector2.ZERO
	elif not _fingers.values().has("look"):
		_fingers[idx] = "look"


func _touch_move(idx: int, pos: Vector2, rel: Vector2) -> void:
	var what: String = _fingers.get(idx, "")
	if what == "stick":
		_stick_pos = pos
		var off := pos - _stick_origin
		if off.length() > STICK_RADIUS * _s():
			_stick_origin = pos - off.normalized() * STICK_RADIUS * _s()    # el joystick sigue al dedo
			off = pos - _stick_origin
		_stick_vec = (off / (STICK_RADIUS * _s())).limit_length(1.0)
	elif what == "look":
		var ev := InputEventMouseMotion.new()
		ev.relative = rel * LOOK_MULT
		ev.position = pos
		Input.parse_input_event(ev)


func _touch_up(idx: int) -> void:
	var what: String = _fingers.get(idx, "")
	_fingers.erase(idx)
	if what == "stick":
		_stick_vec = Vector2.ZERO
		_apply_stick()
	elif what != "" and what != "look":
		_release_button(what)


# ----------------------------------------------------------------- acciones

func _apply_stick() -> void:
	var v := _stick_vec
	if v.length() < 0.15:
		v = Vector2.ZERO
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))
	_set_axis("move_forward", maxf(-v.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _action(name: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap_action(name: String) -> void:
	_action(name, true)
	# se suelta en el siguiente frame para que el juego alcance a ver la pulsación
	await get_tree().process_frame
	_action(name, false)


func _key(code: Key, physical: Key) -> void:
	for p in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = physical
		ev.pressed = p
		Input.parse_input_event(ev)


func _press_button(b: Dictionary) -> void:
	var id := str(b["id"])
	_held[id] = true
	match id:
		"interact":
			_tap_action("interact")
		"jump":
			_action("jump", true)
		"crouch":
			_crouch_on = not _crouch_on
			_action("crouch", _crouch_on)
		"shoot":
			for p in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = p
				ev.position = get_viewport().get_visible_rect().size / 2.0
				Input.parse_input_event(ev)
		"flashlight":
			_tap_action("flashlight")
		"bottle":
			_key(KEY_G, KEY_G)
		"flare":
			_key(KEY_Q, KEY_Q)
		"missions":
			_key(KEY_TAB, KEY_TAB)
		"pause":
			_tap_action("ui_cancel")


func _release_button(id: String) -> void:
	_held.erase(id)
	if id == "jump":
		_action("jump", false)


func _release_all() -> void:
	_fingers.clear()
	_stick_vec = Vector2.ZERO
	_apply_stick()
	for id in _held.keys():
		_release_button(str(id))
	_held.clear()
	if _crouch_on:
		_crouch_on = false
		_action("crouch", false)


# ------------------------------------------------------------------- dibujo

func _draw_pad() -> void:
	var font := ThemeDB.fallback_font
	var s := _s()
	var white := Color(1, 1, 1, 0.55)
	if _fingers.values().has("stick"):
		pad.draw_circle(_stick_origin, STICK_RADIUS * s, Color(1, 1, 1, 0.10))
		pad.draw_arc(_stick_origin, STICK_RADIUS * s, 0.0, TAU, 40, white, 3.0)
		pad.draw_circle(_stick_pos, 34.0 * s, Color(1, 1, 1, 0.35))
	else:
		var v := get_viewport().get_visible_rect().size
		var home := Vector2(v.x * 0.14, v.y - 150.0 * s)
		pad.draw_arc(home, STICK_RADIUS * s * 0.8, 0.0, TAU, 40, Color(1, 1, 1, 0.25), 3.0)
		pad.draw_string(font, home + Vector2(-40.0 * s, 8.0 * s), "MOVER", HORIZONTAL_ALIGNMENT_CENTER, 80.0 * s, int(16.0 * s), Color(1, 1, 1, 0.35))
	for b in _buttons:
		if not _button_visible(b):
			continue
		var id := str(b["id"])
		var on: bool = _held.has(id) or (id == "crouch" and _crouch_on)
		var c: Vector2 = b["pos"]
		var r: float = b["r"]
		pad.draw_circle(c, r, Color(1, 1, 1, 0.30 if on else 0.12))
		pad.draw_arc(c, r, 0.0, TAU, 32, white, 3.0)
		pad.draw_string(font, c + Vector2(-r, r * 0.2), str(b["text"]), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, int(r * 0.75), Color(1, 1, 1, 0.85))
		pad.draw_string(font, c + Vector2(-r - 10.0, r + 16.0 * s), Lang.t(str(b["label"])), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0 + 20.0, int(12.0 * s), Color(1, 1, 1, 0.55))
