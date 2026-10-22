class_name MissionManager
extends Node
## Cadena de misiones del sanatorio. Los objetos del nivel avisan con
## report(evento, id) y este nodo actualiza objetivos, HUD, alarma y final.

enum State { PLAYING, DEAD, WON }

const PROFILES := {
	"sanatorio": [
		{"kind": "flashlight", "text": "Recoge la linterna de tu habitación"},
		{"kind": "door", "arg": "llave_enfermeria", "text": "Encuentra la llave de la enfermería y abre la puerta"},
		{"kind": "item", "arg": "fusible_ascensor", "text": "Toma el fusible del ascensor (está en la enfermería)"},
		{"kind": "elevator", "text": "Repara el ascensor del ala este (panel junto a la cabina)"},
		{"kind": "floor", "text": "Sube al segundo piso (escalera o ascensor)"},
		{"kind": "door", "arg": "llave_laboratorio", "text": "Abre el laboratorio con la llave del 2.º piso"},
		{"kind": "door", "arg": "llave_maquinas", "text": "Toma la llave de máquinas y abre esa sala (ala este)"},
		{"kind": "stun", "text": "Aturde a la criatura una vez (pistola, trampa o bengala)"},
		{"kind": "fuses", "text": "Reúne los fusibles"},
		{"kind": "power", "text": "Instala los fusibles en el generador"},
		{"kind": "escape", "text": "¡Baja en el ascensor y corre a la puerta principal!"},
	],
	"raiz": [
		{"kind": "flashlight", "text": "Recoge la linterna: la tubería quedó a oscuras"},
		{"kind": "door", "arg": "llave_drenaje", "text": "Encuentra la llave del drenaje (oeste) y abre la cámara de filtros (noroeste)"},
		{"kind": "item", "arg": "hacha", "text": "Toma el hacha oxidada de la cámara de filtros"},
		{"kind": "choose", "text": "RUTA FÁCIL: corta la barrera del túnel de raíces (noreste) con el hacha y escapa"},
		{"kind": "heart", "text": "RUTA DIFÍCIL: corta las raíces del centro, baja por el túnel y destruye el CORAZÓN a hachazos"},
		{"kind": "bidons", "text": "...consigue 2 bidones de combustible (%d/2)"},
		{"kind": "burn_lit", "text": "...enciende el incinerador y ¡sal por el túnel noreste antes de que el fuego te alcance!"},
	],
	"sotano": [
		{"kind": "flashlight", "text": "Recoge la linterna que se te cayó en la escalera"},
		{"kind": "door", "arg": "llave_caldera", "text": "Encuentra la llave de las calderas y abre esa sala (norte)"},
		{"kind": "item", "arg": "fusible_ascensor", "text": "Toma el fusible del ascensor (calderas)"},
		{"kind": "elevator", "text": "Repara el ascensor (panel junto a la cabina, al suroeste)"},
		{"kind": "floor", "text": "Sube a las galerías del piso de arriba (escalera este o ascensor)"},
		{"kind": "door", "arg": "llave_camara", "text": "Abre la cámara fría con la llave de las galerías"},
		{"kind": "door", "arg": "llave_bombas", "text": "Toma la llave de bombas y abre esa sala (galerías oeste)"},
		{"kind": "stun", "text": "Aturde al espécimen una vez (pistola, trampa o botella + trampa)"},
		{"kind": "fuses", "text": "Reúne los fusibles"},
		{"kind": "power", "text": "Instala los fusibles en el panel de bombas"},
		{"kind": "escape", "text": "¡Baja y corre a la compuerta de evacuación!"},
	],
}

const INTRO_TITLE := "SANATORIO SANTA MARTA"
const INTRO_TEXT := "Despiertas en una habitación del ala oeste. No hay energía y algo vuela por los pasillos.\nSolo oye lo que haces: no hables ni camines normal (Ctrl para ir agachado). Si te persigue, escóndete en un casillero. Encuentra la forma de escapar."

@export_file("*.tscn") var next_level := ""   ## Si se indica, al escapar se pasa a este nivel
@export var intro_title := ""            ## Vacío = título por defecto
@export_multiline var intro_text := ""  ## Vacío = texto por defecto
@export var profile := "sanatorio"     ## Cadena de misiones: "sanatorio" o "sotano"
@export_file("*.tscn") var escape_scene := ""   ## Si se indica, al escapar va directo a esta cinemática
@export_file("*.tscn") var burn_scene := ""     ## Final B (incinerador)
@export var fuses_required := 3
@export var alarm_interval := 5.0
@export var alarm_loudness := 1.6      ## >1 = se oye más lejos que un grito; así llega a todo el mapa

var state := State.PLAYING
var player: PlayerCharacter
var power_on := false
var fuses_collected := 0
var doors_opened := {}
var play_time := 0.0
var toast_id := 0
var can_restart := false
var items_taken := {}                  ## ids de objetos recogidos alguna vez
var elevator_ready := false
var reached_upper := false
var stunned_once := false
var levers_used := 0
var heart_destroyed := false
var burning := false
var bidons_ok := false
var burn_left := 0.0
const BURN_TIME := [100.0, 85.0, 70.0]
var burn_label: Label
var burn_overlay: ColorRect
var quake_t := 0.0

var objective_label: Label
var inventory_label: Label
var message_label: Label
var overlay: ColorRect
var title_label: Label
var show_missions := true   ## Tab muestra / oculta la lista de misiones
var alarm_timer: Timer


func _ready() -> void:
	add_to_group("mission_manager")
	player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	_build_hud()
	if player:
		player.inventory_changed.connect(_refresh)
		player.flashlight_toggled.connect(func(_on: bool) -> void: _refresh())
	_refresh()
	if SaveSystem.has_pending():
		overlay.color = Color(0, 0, 0, 1)   # pantalla negra mientras se restaura la partida
		SaveSystem.apply_pending(self)
	else:
		_play_intro()
	if profile == "raiz" and Difficulty.level >= 1:
		_ally_creatures.call_deferred()


func _ally_creatures() -> void:
	get_tree().call_group("enemies", "set_allied", true)


func _process(delta: float) -> void:
	if state == State.PLAYING:
		play_time += delta
		if profile == "raiz":
			_root_pulse_tick(delta)
			if heart_destroyed:
				_quake_tick(delta)
			if burning:
				_burn_tick(delta)
		if not reached_upper and player and player.global_position.y > 2.8:
			reached_upper = true
			_refresh()


## Nivel 3: la raíz late cada cierto tiempo y las criaturas notan dónde estás.
const PULSE_EVERY := [55.0, 40.0, 28.0]
var pulse_left := 30.0


func _root_pulse_tick(delta: float) -> void:
	if player == null:
		return
	pulse_left -= delta
	if pulse_left > 0.0:
		return
	pulse_left = PULSE_EVERY[clampi(Difficulty.level, 0, 2)]
	Sfx.play(self, "gurgle", -2.0)
	Sfx.play(self, "land", -8.0)
	NoiseManager.emit_noise(player.global_position, 1.15)
	show_toast(Lang.t("La raíz late... las criaturas saben dónde estás."), 3.0)
	var flash := ColorRect.new()
	flash.color = Color(0.55, 0.0, 0.08, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.get_parent().add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "color:a", 0.35, 0.15)
	tw.tween_property(flash, "color:a", 0.0, 0.9)
	tw.tween_callback(flash.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		show_missions = not show_missions
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if state != State.PLAYING and can_restart and event.is_action_pressed("ui_accept"):
		if state == State.WON and next_level != "":
			get_tree().change_scene_to_file(next_level)
		else:
			get_tree().reload_current_scene()


# ---------------------------------------------------------------- eventos

func report(event: String, id: String) -> void:
	match event:
		"item":
			items_taken[id] = true
			if id == "fusible":
				fuses_collected += 1
		"elevator":
			if id == "powered":
				elevator_ready = true
		"stun":
			stunned_once = true
		"door":
			doors_opened[id] = true
		"power":
			_on_power_restored()
		"escape":
			_on_escape()
		"burn":
			_on_burn()
		"heart":
			_on_heart_destroyed()
		"burn_start":
			_on_burn_start()
	_refresh()


func _on_power_restored() -> void:
	power_on = true
	get_tree().call_group("lamps", "set_alarm", true)
	get_tree().call_group("siren", "activate")
	get_tree().call_group("doors", "refresh_lock_state")
	if profile == "raiz":
		show_toast(Lang.t("¡Energía restaurada! La alarma las atrae. Ahora decide: ESCAPAR por el conducto del sur, o conseguir 2 bidones y quemarlo todo en el incinerador de la raíz."), 9.0)
	else:
		show_toast(Lang.t("¡Energía restaurada! Sonó la alarma y la criatura corre hacia allá. ¡Baja y corre a la salida!"), 7.0)
	_start_alarm()


func _start_alarm() -> void:
	if alarm_timer:
		return
	alarm_timer = Timer.new()
	alarm_timer.wait_time = alarm_interval
	alarm_timer.timeout.connect(_alarm_pulse)
	add_child(alarm_timer)
	alarm_timer.start()
	_alarm_pulse()


func _alarm_pulse() -> void:
	if state != State.PLAYING:
		return
	var source := player.global_position
	var siren := get_tree().get_first_node_in_group("siren") as Node3D
	if siren:
		source = siren.global_position
	NoiseManager.emit_noise(source, alarm_loudness)


func on_player_caught(message := "EL MURCIÉLAGO TE ATRAPÓ", killer: Node3D = null) -> void:
	if state != State.PLAYING:
		return
	state = State.DEAD
	message = Lang.t(message)
	if killer != null and player != null:
		_freeze_world(false)
		for c in title_label.get_parent().get_children():
			if c != overlay and c != title_label and c is CanvasItem:
				c.visible = false
		var bat := not (killer is EcoCreature)
		var seq := KillSequence.start(get_parent(), player, killer, bat)
		seq.finished.connect(func() -> void:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_end_screen(message, Color(0.3, 0.0, 0.0)))
		return
	_freeze_world()
	Sfx.play(self, "caught", -2.0)
	_end_screen(message, Color(0.35, 0.0, 0.0))


## El corazón cae: la estructura queda débil (temblores) y ya se puede quemar todo.
func _on_heart_destroyed() -> void:
	heart_destroyed = true
	quake_t = 6.0
	show_toast(Lang.t("¡El corazón cae! La raíz se resquebraja y toda la estructura tiembla... Ahora el fuego sí prenderá: lleva 2 bidones al incinerador (centro)."), 9.0)


func _quake_tick(delta: float) -> void:
	quake_t -= delta
	if quake_t > 0.0:
		return
	quake_t = randf_range(10.0, 18.0)
	Sfx.play(self, "land", -4.0)
	Sfx.play(self, "thunder", -10.0)
	NoiseManager.emit_noise(player.global_position, 0.8)
	_shake_camera(0.9, 0.05)


func _shake_camera(seconds: float, amount: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t := 0.0
	while t < seconds and is_inside_tree():
		var k := 1.0 - t / seconds
		cam.h_offset = randf_range(-amount, amount) * k
		cam.v_offset = randf_range(-amount, amount) * k
		await get_tree().process_frame
		t += get_process_delta_time()
	cam.h_offset = 0.0
	cam.v_offset = 0.0


## El incinerador prendió: el fuego se propaga y hay que llegar a la salida antes de que se acabe el tiempo.
func _on_burn_start() -> void:
	if burning or state != State.PLAYING:
		return
	burning = true
	burn_left = BURN_TIME[clampi(Difficulty.level, 0, 2)]
	get_tree().call_group("lamps", "set_alarm", true)
	Sfx.play(self, "explosion", -2.0)
	Sfx.play(self, "fire_loop", -4.0)
	NoiseManager.emit_noise(player.global_position, 2.0)
	show_toast(Lang.t("¡LA RAÍZ ARDE! El fuego se propaga por todo el nivel. ¡CORRE al túnel del noreste y sal antes de que te alcance!"), 8.0)
	var layer := overlay.get_parent()
	burn_overlay = ColorRect.new()
	burn_overlay.color = Color(1.0, 0.35, 0.05, 0.0)
	burn_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	burn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(burn_overlay)
	layer.move_child(burn_overlay, 0)
	burn_label = _make_label(layer, 34)
	burn_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	burn_label.offset_top = 14.0
	burn_label.offset_left = -200.0
	burn_label.offset_right = 200.0
	burn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	burn_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.15))
	var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we and we.environment:
		var tw := create_tween()
		tw.tween_property(we.environment, "fog_light_color", Color(0.5, 0.15, 0.03), 4.0)
		tw.parallel().tween_property(we.environment, "ambient_light_color", Color(0.7, 0.28, 0.1), 4.0)
		tw.parallel().tween_property(we.environment, "ambient_light_energy", 0.7, 4.0)


func _burn_tick(delta: float) -> void:
	burn_left -= delta
	var flicker := 0.12 + 0.08 * sin(play_time * 9.0) + 0.1 * (1.0 - clampf(burn_left / BURN_TIME[clampi(Difficulty.level, 0, 2)], 0.0, 1.0))
	if burn_overlay:
		burn_overlay.color.a = flicker
	if burn_label:
		burn_label.text = Lang.t("¡SAL! %02d:%02d") % [floori(maxf(burn_left, 0.0) / 60.0), int(maxf(burn_left, 0.0)) % 60]
	quake_t -= delta
	if quake_t <= 0.0:
		quake_t = randf_range(4.0, 7.0)
		Sfx.play(self, "thunder", -8.0)
		NoiseManager.emit_noise(player.global_position, 0.9)
		_shake_camera(0.6, 0.04)
	if burn_left <= 0.0:
		on_player_caught("EL FUEGO TE ALCANZÓ")


func _on_burn() -> void:
	if state != State.PLAYING or burn_scene == "":
		return
	state = State.WON
	_freeze_world(false)
	var tw := create_tween()
	tw.tween_property(overlay, "color", Color(1.0, 0.5, 0.1, 1.0), 0.5)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(burn_scene))


func _on_escape() -> void:
	if state != State.PLAYING:
		return
	state = State.WON
	if burning and burn_scene != "":        # escapaste con el nivel en llamas: final del fuego
		_freeze_world(false)
		Sfx.play(self, "gate_slide", -2.0)
		var tb := create_tween()
		tb.tween_property(overlay, "color", Color(1.0, 0.45, 0.1, 1.0), 1.2)
		tb.tween_callback(func() -> void: get_tree().change_scene_to_file(burn_scene))
		return
	if escape_scene != "":
		_freeze_world(false)
		Sfx.play(self, "gate_slide", -2.0)
		var tw := create_tween()
		tw.tween_property(overlay, "color", Color(0, 0, 0, 1.0), 1.4)
		tw.tween_callback(func() -> void: get_tree().change_scene_to_file(escape_scene))
		return
	_freeze_world()
	var minutes := floori(play_time / 60.0)
	var seconds := int(play_time) % 60
	_end_screen(Lang.t("¡ESCAPASTE!\nTiempo: %02d:%02d") % [minutes, seconds], Color(0.0, 0.0, 0.0),
		Lang.t("Enter para continuar") if next_level != "" else Lang.t("Enter para volver a empezar"))


func _freeze_world(show_mouse := true) -> void:
	if alarm_timer:
		alarm_timer.stop()
	if player:
		player.set_physics_process(false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	if show_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _end_screen(title: String, tint: Color, hint := "") -> void:
	if hint == "":
		hint = Lang.t("Enter para volver a empezar")
	title_label.text = title + "\n\n(" + hint + ")"
	title_label.modulate.a = 0.0
	overlay.color = Color(tint.r, tint.g, tint.b, 0.0)
	var tween := create_tween()
	tween.tween_property(overlay, "color:a", 0.88, 1.0)
	tween.tween_property(title_label, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func() -> void: can_restart = true)


# -------------------------------------------------------------------- HUD

func show_toast(text: String, seconds := 3.0) -> void:
	toast_id += 1
	var my_id := toast_id
	message_label.text = text
	message_label.visible = true
	await get_tree().create_timer(seconds).timeout
	if my_id == toast_id:
		message_label.visible = false


func _steps() -> Array:
	return PROFILES.get(profile, PROFILES["sanatorio"])


func _is_done(step: Dictionary) -> bool:
	match str(step["kind"]):
		"flashlight":
			return player != null and player.has_flashlight
		"door":
			return doors_opened.has(str(step["arg"]))
		"fuses":
			return fuses_collected >= fuses_required
		"item":
			return items_taken.has(str(step["arg"]))
		"elevator":
			return elevator_ready
		"floor":
			return reached_upper
		"stun":
			return stunned_once
		"power":
			return power_on
		"escape", "choose":
			return state == State.WON and not burning
		"heart":
			return heart_destroyed
		"bidons":
			if player != null and player.count_item("bidon_combustible") >= 2:
				bidons_ok = true
			return burning or bidons_ok
		"burn_lit":
			return burning and state == State.WON
	return false


func _step_text(step: Dictionary) -> String:
	if str(step["kind"]) == "fuses":
		return Lang.t("Reúne los %d fusibles (%d/%d)") % [fuses_required, mini(fuses_collected, fuses_required), fuses_required]
	if "%d" in str(step["text"]) and player != null:
		return Lang.t(str(step["text"])) % mini(player.count_item("bidon_combustible"), 2)
	return Lang.t(str(step["text"]))


func _inventory_text() -> String:
	if player == null:
		return ""
	var parts := PackedStringArray()
	if player.has_flashlight:
		parts.append(Lang.t("Linterna [F]: %s") % (Lang.t("ENCENDIDA") if player.flashlight_on else Lang.t("apagada")))
	for id in player.inventory:
		if id == "linterna":
			continue
		var count := int(player.inventory[id])
		var label := ItemInfo.display_name(id)
		if count > 1:
			label = "%s x%d" % [label, count]
		if ItemInfo.HINTS.has(id):
			label += "  " + Lang.t(str(ItemInfo.HINTS[id]))
		parts.append(label)
	return "\n".join(parts)


func _refresh() -> void:
	var lines := PackedStringArray()
	var current_found := false
	for step: Dictionary in _steps():
		var mark := "[x]"
		if not _is_done(step):
			mark = "[ ]" if current_found else "[>]"
			current_found = true
		lines.append("%s %s" % [mark, _step_text(step)])
	objective_label.text = "\n".join(lines) if show_missions else Lang.t("[Tab] Mostrar misiones")
	inventory_label.text = _inventory_text()


func _make_label(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	objective_label = _make_label(layer, 17)
	objective_label.position = Vector2(12, 44)

	inventory_label = _make_label(layer, 17)
	inventory_label.anchor_left = 1.0
	inventory_label.anchor_right = 1.0
	inventory_label.offset_left = -320.0
	inventory_label.offset_right = -12.0
	inventory_label.offset_top = 12.0
	inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	message_label = _make_label(layer, 24)
	message_label.visible = false
	message_label.anchor_left = 0.12
	message_label.anchor_right = 0.88
	message_label.anchor_top = 0.74
	message_label.anchor_bottom = 0.94
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	title_label = _make_label(layer, 40)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.modulate.a = 0.0


func _play_intro() -> void:
	overlay.color = Color(0, 0, 0, 1)
	title_label.text = Lang.t(intro_title if intro_title != "" else INTRO_TITLE)
	title_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(2.2)
	tween.tween_property(title_label, "modulate:a", 0.0, 1.0)
	tween.parallel().tween_property(overlay, "color:a", 0.0, 1.4)
	tween.tween_callback(show_toast.bind(Lang.t(intro_text if intro_text != "" else INTRO_TEXT), 9.0))


# ------------------------------------------------------------ guardar / cargar

## Título del nivel (en español; se traduce al mostrarlo con Lang.t).
func level_title() -> String:
	return intro_title if intro_title != "" else INTRO_TITLE


## Estado de las misiones para el archivo de guardado (lo usa SaveSystem).
func export_state() -> Dictionary:
	return {
		"power_on": power_on,
		"fuses_collected": fuses_collected,
		"doors_opened": doors_opened.keys(),
		"items_taken": items_taken.keys(),
		"elevator_ready": elevator_ready,
		"reached_upper": reached_upper,
		"stunned_once": stunned_once,
		"levers_used": levers_used,
		"heart_destroyed": heart_destroyed,
		"burning": burning,
		"bidons_ok": bidons_ok,
		"burn_left": burn_left,
		"play_time": play_time,
		"pulse_left": pulse_left,
		"show_missions": show_missions,
	}


## Restaura el estado guardado sin repetir avisos ni la intro.
func import_state(d: Dictionary) -> void:
	power_on = bool(d.get("power_on", false))
	fuses_collected = int(d.get("fuses_collected", 0))
	doors_opened.clear()
	for id in d.get("doors_opened", []):
		doors_opened[str(id)] = true
	items_taken.clear()
	for id in d.get("items_taken", []):
		items_taken[str(id)] = true
	elevator_ready = bool(d.get("elevator_ready", false))
	reached_upper = bool(d.get("reached_upper", false))
	stunned_once = bool(d.get("stunned_once", false))
	levers_used = int(d.get("levers_used", 0))
	heart_destroyed = bool(d.get("heart_destroyed", false))
	bidons_ok = bool(d.get("bidons_ok", false))
	play_time = float(d.get("play_time", 0.0))
	pulse_left = float(d.get("pulse_left", pulse_left))
	show_missions = bool(d.get("show_missions", true))
	if power_on:
		get_tree().call_group("lamps", "set_alarm", true)
		get_tree().call_group("siren", "activate")
		get_tree().call_group("doors", "refresh_lock_state")
		_start_alarm()
	if bool(d.get("burning", false)):
		_on_burn_start()
		burn_left = float(d.get("burn_left", burn_left))
	_refresh()


## Quita la pantalla negra tras cargar y avisa al jugador.
func finish_load() -> void:
	title_label.text = Lang.t(level_title())
	title_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_property(title_label, "modulate:a", 0.0, 0.8)
	tween.parallel().tween_property(overlay, "color:a", 0.0, 1.0)
	show_toast(Lang.t("Partida cargada."), 2.5)
