extends CanvasLayer
## Menú de pausa (autoload "PauseMenu"). ESC lo abre durante la partida.
##   REANUDAR · REINICIAR · CARGAR · GUARDAR · SALIR DEL JUEGO
## Flechas o ratón para elegir, Enter o clic para aceptar, ESC para volver/reanudar.
## Solo funciona en niveles con MissionManager y mientras se juega (no en menús,
## cinemáticas ni en la pantalla de muerte). El guardado lo hace SaveSystem.

enum Page { MAIN, SLOTS, CONFIRM, MIC }

const BLOOD := Color(0.8, 0.12, 0.1)
const BONE := Color(0.85, 0.8, 0.75)
const SELECT := Color(1.0, 0.45, 0.4)
const DIM := Color(0.85, 0.8, 0.75, 0.45)

const SCREEN_SHADER := """
shader_type canvas_item;
// El frame congelado del juego, pixelado, en rojo sangre, con viñeta, grano y líneas.
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float pixel = 4.0;

float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 cell = SCREEN_PIXEL_SIZE * pixel;
	vec2 suv = (floor(SCREEN_UV / cell) + 0.5) * cell;
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	vec3 s = texture(screen_tex, suv).rgb;
	float l = dot(s, vec3(0.3, 0.59, 0.11));
	vec3 tinted = vec3(l * 0.95, l * 0.16, l * 0.13);
	float vig = smoothstep(0.2, 0.78, distance(UV, vec2(0.5)));
	float grain = rnd(floor(FRAGCOORD.xy / pixel) + floor(TIME * 18.0)) - 0.5;
	float scan = step(0.5, fract(FRAGCOORD.y / 3.0));
	float band = 1.0 - smoothstep(0.08, 0.34, abs(UV.x - 0.5));   // detrás del menú, más oscuro
	vec3 col = tinted * (0.5 - vig * 0.42) * (1.0 - band * 0.4) + vec3(0.06, 0.0, 0.0) * vig + grain * 0.045;
	col *= 0.9 + 0.1 * scan;
	COLOR = vec4(mix(src, col, fade), 1.0);
}
"""

var page := Page.MAIN
var is_open := false
var opening := false
var closing := false
var hidden_layers: Array[CanvasLayer] = []   ## HUD del nivel, oculto mientras dura la pausa
var snapshot: Image
var slots_mode := "save"            ## "save" o "load"
var confirm_action := Callable()
var confirm_back := Page.MAIN       ## A dónde vuelve "NO"
var confirm_title := "PAUSA"

var root: Control
var screen: ColorRect
var screen_material: ShaderMaterial
var content: VBoxContainer
var title: Label
var info: Label
var main_box: VBoxContainer
var slots_box: VBoxContainer
var confirm_box: VBoxContainer
var confirm_text: Label
var confirm_yes: Button
var confirm_no: Button
var status: Label
var hint: Label
var mic_box: VBoxContainer
var mic_buttons := {}               ## id -> Button de la pantalla MICRÓFONO
var mic_value: Label
var mic_slider: HSlider
var mic_meter: MicMeter
var mic_state: Label
var buttons := {}                   ## id -> Button del menú principal
var drone: AudioStreamPlayer
var flicker_left := 0.0
var flicker_wait := 1.0
var status_left := 0.0
var empty_thumb: Texture2D


## Barra del micrófono: nivel actual, línea del umbral y marca cuando te oyen.
class MicMeter extends Control:
	const MIN_DB := -80.0
	const MAX_DB := 0.0

	func _x(db: float) -> float:
		return size.x * clampf((db - MIN_DB) / (MAX_DB - MIN_DB), 0.0, 1.0)

	func _draw() -> void:
		var nm := NoiseManager
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.01, 0.01, 0.9))
		var heard: bool = Time.get_ticks_msec() / 1000.0 - nm.heard_at < 0.35
		var over: bool = nm.level_db >= nm.threshold_db
		var fill := Color(0.85, 0.15, 0.1) if over else Color(0.85, 0.8, 0.75, 0.7)
		if not nm.mic_enabled:
			fill = Color(0.4, 0.4, 0.4, 0.4)
		draw_rect(Rect2(0, 3, _x(nm.level_db), size.y - 6), fill)
		var tx := _x(nm.threshold_db)
		draw_rect(Rect2(tx - 2, -6, 4, size.y + 12), Color(1.0, 0.2, 0.15) if not heard else Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.12, 0.1, 0.6), false, 2.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	visible = false
	_build()
	Lang.changed.connect(_refresh_texts)


# --------------------------------------------------------------- abrir/cerrar

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or event.is_echo():
		return
	if is_open:
		get_viewport().set_input_as_handled()
		if closing or opening:
			return
		if page == Page.MAIN:
			resume()
		else:
			_sfx("click", -12.0)
			_show_page(confirm_back if page == Page.CONFIRM else Page.MAIN)
	elif _can_pause() and not opening:
		get_viewport().set_input_as_handled()
		open()


func _can_pause() -> bool:
	if get_tree().paused or get_tree().current_scene == null:
		return false
	var mm := _mission()
	return mm != null and mm.state == MissionManager.State.PLAYING


func open() -> void:
	opening = true
	_hide_hud()
	snapshot = null
	if DisplayServer.get_name() != "headless":
		# Un frame sin HUD ni menú para la miniatura del guardado.
		await RenderingServer.frame_post_draw
		snapshot = get_viewport().get_texture().get_image()
	opening = false
	if not _can_pause():
		_restore_hud()
		return
	is_open = true
	closing = false
	if not Net.is_online():
		get_tree().paused = true      # en red el mundo sigue: solo tu personaje se queda quieto
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_refresh_texts()
	_show_page(Page.MAIN)
	status.text = ""
	_sfx("lamp_cut", -8.0)
	drone.play()
	var tween := create_tween()
	screen_material.set_shader_parameter("fade", 0.0)
	content.modulate.a = 0.0
	tween.tween_method(func(v: float) -> void: screen_material.set_shader_parameter("fade", v), 0.0, 1.0, 0.25)
	tween.parallel().tween_property(content, "modulate:a", 1.0, 0.3)


func resume() -> void:
	if not is_open or closing:
		return
	closing = true
	_sfx("click", -10.0)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: screen_material.set_shader_parameter("fade", v), 1.0, 0.0, 0.15)
	tween.parallel().tween_property(content, "modulate:a", 0.0, 0.12)
	tween.tween_callback(func() -> void:
		_hide()
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Lo que se oyó por el micrófono durante la pausa no cuenta.
		if NoiseManager.capture:
			NoiseManager.capture.clear_buffer())


func _hide() -> void:
	_close_mic()
	is_open = false
	closing = false
	visible = false
	drone.stop()
	_restore_hud()


func _hide_hud() -> void:
	hidden_layers.clear()
	for owner_node: Node in [get_tree().current_scene, NoiseManager]:
		if owner_node == null:
			continue
		for layer: CanvasLayer in owner_node.find_children("*", "CanvasLayer", true, false):
			if layer.visible:
				layer.visible = false
				hidden_layers.append(layer)


func _restore_hud() -> void:
	for layer in hidden_layers:
		if is_instance_valid(layer):
			layer.visible = true
	hidden_layers.clear()


# --------------------------------------------------------------- acciones

func _on_main(id: String) -> void:
	_sfx("click", -8.0)
	match id:
		"resume":
			resume()
		"restart":
			if Net.is_client():
				_status(Lang.t("Solo el anfitrión puede reiniciar el nivel."), true)
				return
			if Net.is_online():
				_ask("REINICIAR", Lang.t("¿Reiniciar el nivel para TODOS los jugadores?"), _do_restart)
				return
			_ask("REINICIAR", Lang.t("¿Reiniciar el nivel desde el principio?\nPerderás el progreso que no hayas guardado."), _do_restart)
		"load":
			if Net.is_online():
				_status(Lang.t("Guardar y cargar no están disponibles en multijugador."), true)
				return
			slots_mode = "load"
			_show_page(Page.SLOTS)
		"save":
			var reason := SaveSystem.can_save()
			if reason != "":
				_status(Lang.t(reason), true)
				return
			slots_mode = "save"
			_show_page(Page.SLOTS)
		"mic":
			_show_page(Page.MIC)
		"quit":
			if Net.is_online():
				_ask("SALIR DE LA PARTIDA", Lang.t("¿Salir de la partida?\nVolverás al menú principal y tus compañeros seguirán sin ti.") if Net.is_client() \
					else Lang.t("¿Cerrar la partida?\nEres el anfitrión: todos volverán al menú principal."), _do_leave)
				return
			_ask("SALIR DEL JUEGO", Lang.t("¿Salir del juego?\nPerderás el progreso que no hayas guardado."), _do_quit)


func _on_slot(slot: int) -> void:
	_sfx("click", -8.0)
	var used := not SaveSystem.read_slot(slot).is_empty()
	if slots_mode == "save":
		if used:
			_ask("GUARDAR PARTIDA", Lang.t("¿Sobrescribir la ranura %d?") % slot, _do_save.bind(slot), Page.SLOTS)
		else:
			_do_save(slot)
	elif used:
		_ask("CARGAR PARTIDA", Lang.t("¿Cargar la ranura %d?\nPerderás el progreso que no hayas guardado.") % slot, _do_load.bind(slot), Page.SLOTS)


func _do_save(slot: int) -> void:
	if SaveSystem.save_to_slot(slot, snapshot):
		_sfx("lever_clunk", -6.0)
		_show_page(Page.MAIN)
		_status(Lang.t("Partida guardada en la ranura %d.") % slot)
	else:
		var reason := SaveSystem.can_save()
		_show_page(Page.MAIN)
		_status(Lang.t(reason if reason != "" else "No se pudo guardar la partida."), true)


func _do_load(slot: int) -> void:
	_hide()
	if not SaveSystem.load_slot(slot):
		visible = true
		is_open = true
		drone.play()
		_show_page(Page.MAIN)
		_status(Lang.t("No se pudo cargar: la ranura está vacía o dañada."), true)


func _do_leave() -> void:
	_hide()
	Net.leave_to_menu()


func _do_restart() -> void:
	_hide()
	if Net.is_online():
		Net.reload_level()
		return
	SaveSystem.pending = {}
	get_tree().paused = false
	get_tree().reload_current_scene()


func _do_quit() -> void:
	get_tree().quit()


func _ask(heading: String, question: String, action: Callable, back := Page.MAIN) -> void:
	confirm_title = heading
	confirm_text.text = question
	confirm_action = action
	confirm_back = back
	_show_page(Page.CONFIRM)


func _on_confirm(yes: bool) -> void:
	_sfx("click", -8.0)
	if yes and confirm_action.is_valid():
		var action := confirm_action
		confirm_action = Callable()
		action.call()
	else:
		confirm_action = Callable()
		_show_page(confirm_back)


# --------------------------------------------------------------- páginas

func _show_page(p: Page) -> void:
	page = p
	status.text = ""
	main_box.visible = p == Page.MAIN
	slots_box.visible = p == Page.SLOTS
	confirm_box.visible = p == Page.CONFIRM
	mic_box.visible = p == Page.MIC
	NoiseManager.ui_open = p == Page.MIC     # con los ajustes abiertos, el micrófono no alerta a nadie
	match p:
		Page.MAIN:
			title.text = Lang.t("PAUSA")
			_focus(buttons["resume"])
		Page.SLOTS:
			title.text = Lang.t("GUARDAR PARTIDA") if slots_mode == "save" else Lang.t("CARGAR PARTIDA")
			_build_slots()
		Page.CONFIRM:
			title.text = Lang.t(confirm_title)
			_focus(confirm_no)
		Page.MIC:
			title.text = Lang.t("MICRÓFONO")
			_refresh_mic()
			_focus(mic_buttons["mic_toggle"])
	hint.text = Lang.t("FLECHAS / RATÓN  elegir      ENTER  aceptar      ESC  reanudar") if p == Page.MAIN \
		else Lang.t("FLECHAS / RATÓN  elegir      ENTER  aceptar      ESC  volver")


func _build_slots() -> void:
	for child in slots_box.get_children():
		slots_box.remove_child(child)
		child.queue_free()
	var first: Button
	var any_used := false
	for slot in range(1, SaveSystem.SLOTS + 1):
		var data := SaveSystem.read_slot(slot)
		var b := _make_button("", 18)
		b.custom_minimum_size = Vector2(600, 96)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.expand_icon = true
		b.add_theme_constant_override("h_separation", 18)
		b.add_theme_constant_override("icon_max_width", 150)
		if data.is_empty():
			b.text = "%s\n%s" % [Lang.t("RANURA %d") % slot, Lang.t("— vacía —")]
			b.icon = empty_thumb
			b.disabled = slots_mode == "load"
		else:
			any_used = true
			var thumb := SaveSystem.read_thumbnail(slot)
			b.icon = thumb if thumb else empty_thumb
			b.text = "%s\n%s  ·  %s  ·  %s\n%s" % [
				Lang.t("RANURA %d") % slot,
				Lang.t(str(data.get("level_title", ""))),
				Lang.t(Difficulty.NAMES[clampi(int(data.get("difficulty", 1)), 0, 2)]),
				_clock(float(data.get("play_time", 0.0))),
				_date(str(data.get("saved_at", ""))),
			]
		b.pressed.connect(_on_slot.bind(slot))
		slots_box.add_child(b)
		if first == null and not b.disabled:
			first = b
	var back := _make_button(Lang.t("VOLVER"), 22)
	back.pressed.connect(func() -> void:
		_sfx("click", -10.0)
		_show_page(Page.MAIN))
	slots_box.add_child(back)
	_wrap_focus(slots_box)
	_focus(first if first else back)
	if slots_mode == "load" and not any_used:
		_status(Lang.t("No hay partidas guardadas."), true)


func _refresh_texts() -> void:
	var labels := {"resume": "REANUDAR", "restart": "REINICIAR", "load": "CARGAR", "save": "GUARDAR", "mic": "MICRÓFONO", "quit": "SALIR DEL JUEGO"}
	if Net.is_online():
		labels["quit"] = "SALIR DE LA PARTIDA"
	for id in labels:
		buttons[id].text = Lang.t(labels[id])
	# En red: atenuadas las opciones que no se pueden usar (al pulsarlas se explica por qué).
	var online := Net.is_online()
	buttons["load"].modulate.a = 0.45 if online else 1.0
	buttons["save"].modulate.a = 0.45 if online else 1.0
	buttons["restart"].modulate.a = 0.45 if Net.is_client() else 1.0
	confirm_yes.text = Lang.t("SÍ")
	confirm_no.text = Lang.t("NO")
	var mm := _mission()
	if mm:
		info.text = "%s  ·  %s  ·  %s" % [Lang.t(mm.level_title()), Difficulty.level_name(), _clock(mm.play_time)]
		if Net.is_online():
			info.text += "  ·  " + (Lang.t("EN RED: %d JUGADORES") % Net.players.size())
	if is_open:
		_show_page(page)


# --------------------------------------------------------------- construcción

func _build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	screen = ColorRect.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SCREEN_SHADER
	screen_material = ShaderMaterial.new()
	screen_material.shader = shader
	screen.material = screen_material
	root.add_child(screen)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	content = VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	center.add_child(content)

	title = _make_label(56, BLOOD)
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("outline_size", 10)
	content.add_child(title)

	info = _make_label(16, DIM)
	content.add_child(info)

	var rule := ColorRect.new()
	rule.color = Color(BLOOD, 0.55)
	rule.custom_minimum_size = Vector2(420, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(rule)
	content.add_child(_spacer(8))

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 6)
	content.add_child(main_box)
	for id in ["resume", "restart", "load", "save", "mic", "quit"]:
		var b := _make_button("", 26)
		b.pressed.connect(_on_main.bind(id))
		main_box.add_child(b)
		buttons[id] = b
	_wrap_focus(main_box)

	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation", 8)
	content.add_child(slots_box)

	_build_mic_page()

	confirm_box = VBoxContainer.new()
	confirm_box.add_theme_constant_override("separation", 6)
	content.add_child(confirm_box)
	confirm_text = _make_label(22, BONE)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size = Vector2(560, 0)
	confirm_box.add_child(confirm_text)
	confirm_box.add_child(_spacer(10))
	confirm_yes = _make_button("", 26)
	confirm_yes.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_yes.pressed.connect(_on_confirm.bind(true))
	confirm_box.add_child(confirm_yes)
	confirm_no = _make_button("", 26)
	confirm_no.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	confirm_no.pressed.connect(_on_confirm.bind(false))
	confirm_box.add_child(confirm_no)
	_wrap_focus(confirm_box)

	content.add_child(_spacer(6))
	status = _make_label(18, BONE)
	status.custom_minimum_size = Vector2(0, 28)
	content.add_child(status)
	hint = _make_label(14, Color(BONE, 0.35))
	content.add_child(hint)

	var placeholder := Image.create(SaveSystem.THUMB_SIZE.x, SaveSystem.THUMB_SIZE.y, false, Image.FORMAT_RGB8)
	placeholder.fill(Color(0.07, 0.01, 0.01))
	var w := SaveSystem.THUMB_SIZE.x
	var h := SaveSystem.THUMB_SIZE.y
	for k in 3:
		placeholder.fill_rect(Rect2i(0, k, w, 1), Color(BLOOD, 0.6))
		placeholder.fill_rect(Rect2i(0, h - 1 - k, w, 1), Color(BLOOD, 0.6))
		placeholder.fill_rect(Rect2i(k, 0, 1, h), Color(BLOOD, 0.6))
		placeholder.fill_rect(Rect2i(w - 1 - k, 0, 1, h), Color(BLOOD, 0.6))
	empty_thumb = ImageTexture.create_from_image(placeholder)

	drone = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/drone_loop.wav"):
		drone.stream = load("res://assets/audio/drone_loop.wav")
	drone.volume_db = -24.0
	drone.finished.connect(func() -> void:
		if is_open:
			drone.play())
	add_child(drone)


# --------------------------------------------------------------- micrófono

func _build_mic_page() -> void:
	mic_box = VBoxContainer.new()
	mic_box.add_theme_constant_override("separation", 6)
	content.add_child(mic_box)
	for id in ["mic_toggle", "mic_noisy"]:
		var b := _make_button("", 20)
		b.pressed.connect(_on_mic.bind(id))
		mic_box.add_child(b)
		mic_buttons[id] = b
	mic_value = _make_label(20, BONE)
	mic_box.add_child(mic_value)
	mic_slider = _make_slider()
	mic_slider.value_changed.connect(func(v: float) -> void:
		NoiseManager.set_sensitivity(v / 100.0)
		_refresh_mic())
	mic_box.add_child(mic_slider)
	var scale_row := HBoxContainer.new()
	scale_row.custom_minimum_size = Vector2(420, 0)
	scale_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for side in ["lo", "hi"]:
		var l := _make_label(13, Color(BONE, 0.35))
		l.name = "Escala_" + side
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == "lo" else HORIZONTAL_ALIGNMENT_RIGHT
		scale_row.add_child(l)
	mic_box.add_child(scale_row)
	mic_box.add_child(_spacer(6))
	mic_meter = MicMeter.new()
	mic_meter.custom_minimum_size = Vector2(420, 22)
	mic_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mic_box.add_child(mic_meter)
	mic_state = _make_label(16, DIM)
	mic_box.add_child(mic_state)
	for id in ["mic_recal", "mic_back"]:
		var b2 := _make_button("", 20)
		b2.pressed.connect(_on_mic.bind(id))
		mic_box.add_child(b2)
		mic_buttons[id] = b2
	_wrap_focus(mic_box)


func _on_mic(id: String) -> void:
	_sfx("click", -8.0)
	match id:
		"mic_toggle":
			NoiseManager.set_mic_enabled(not NoiseManager.mic_enabled)
		"mic_noisy":
			NoiseManager.set_noisy_mode(not NoiseManager.noisy_mode)
		"mic_recal":
			NoiseManager.recalibrate()
		"mic_back":
			_show_page(Page.MAIN)
			return
	_refresh_mic()


func _refresh_mic() -> void:
	mic_buttons["mic_toggle"].text = Lang.t("MICRÓFONO: ACTIVADO") if NoiseManager.mic_enabled else Lang.t("MICRÓFONO: DESACTIVADO")
	mic_buttons["mic_noisy"].text = Lang.t("MODO AMBIENTE RUIDOSO (FERIA): SÍ") if NoiseManager.noisy_mode else Lang.t("MODO AMBIENTE RUIDOSO (FERIA): NO")
	mic_buttons["mic_recal"].text = Lang.t("RECALIBRAR (medir el silencio)")
	mic_buttons["mic_back"].text = Lang.t("VOLVER")
	mic_value.text = Lang.t("SENSIBILIDAD: %d %%") % roundi(NoiseManager.sensitivity * 100.0)
	mic_slider.set_value_no_signal(NoiseManager.sensitivity * 100.0)
	(mic_box.find_child("Escala_lo", true, false) as Label).text = Lang.t("solo si gritas")
	(mic_box.find_child("Escala_hi", true, false) as Label).text = Lang.t("hasta si respiras")


## Al salir de la pantalla del micrófono se guardan los ajustes y se descarta lo captado durante la pausa.
func _close_mic() -> void:
	if not NoiseManager.ui_open:
		return
	NoiseManager.ui_open = false
	NoiseManager.save_settings()
	if NoiseManager.capture:
		NoiseManager.capture.clear_buffer()


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.custom_minimum_size = Vector2(420, 28)
	slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.02, 0.02)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(BLOOD, 0.85)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = SELECT
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	var knob := Image.create(14, 26, false, Image.FORMAT_RGBA8)
	knob.fill(BONE)
	var knob_hi := Image.create(14, 26, false, Image.FORMAT_RGBA8)
	knob_hi.fill(Color.WHITE)
	slider.add_theme_icon_override("grabber", ImageTexture.create_from_image(knob))
	slider.add_theme_icon_override("grabber_highlight", ImageTexture.create_from_image(knob_hi))
	return slider


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 48)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(BONE, 0.75))
	b.add_theme_color_override("font_hover_color", SELECT)
	b.add_theme_color_override("font_focus_color", SELECT)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(BONE, 0.25))
	b.add_theme_color_override("font_outline_color", Color.BLACK)
	b.add_theme_constant_override("outline_size", 6)
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.content_margin_left = 16
	idle.content_margin_right = 16
	idle.content_margin_top = 6
	idle.content_margin_bottom = 6
	var lit := idle.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.4, 0.02, 0.02, 0.4)
	lit.border_width_left = 4
	lit.border_width_right = 4
	lit.border_color = BLOOD
	var pressed := lit.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.6, 0.05, 0.04, 0.55)
	b.add_theme_stylebox_override("normal", idle)
	b.add_theme_stylebox_override("disabled", idle)
	b.add_theme_stylebox_override("hover", lit)
	b.add_theme_stylebox_override("focus", lit)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("pressed", pressed)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func() -> void: _sfx("click", -20.0))
	return b


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Flecha abajo en el último vuelve al primero y viceversa.
func _wrap_focus(box: Container) -> void:
	var list: Array[Button] = []
	for c in box.get_children():
		if c is Button:
			list.append(c)
	for i in list.size():
		list[i].focus_neighbor_top = list[(i - 1 + list.size()) % list.size()].get_path()
		list[i].focus_neighbor_bottom = list[(i + 1) % list.size()].get_path()


func _focus(b: Button) -> void:
	if b:
		b.grab_focus.call_deferred()


# --------------------------------------------------------------- efectos

func _process(delta: float) -> void:
	if not is_open:
		return
	if page == Page.MIC:
		mic_meter.queue_redraw()
		var nm := NoiseManager
		if not nm.mic_enabled:
			mic_state.text = Lang.t("Micrófono desactivado: las criaturas solo oirán tus pasos y objetos.")
		elif nm.calibration_left > 0.0:
			mic_state.text = Lang.t("CALIBRANDO... quédate en silencio")
		elif Time.get_ticks_msec() / 1000.0 - nm.heard_at < 0.5:
			mic_state.text = Lang.t("¡TE OYEN!   (%.0f dB · umbral %.0f dB)") % [nm.level_db, nm.threshold_db]
		else:
			mic_state.text = Lang.t("silencio   (%.0f dB · umbral %.0f dB)") % [nm.level_db, nm.threshold_db]
	# El título parpadea como las lámparas del sanatorio.
	if flicker_left > 0.0:
		flicker_left -= delta
		title.modulate.a = 0.3
	else:
		title.modulate.a = 1.0
		flicker_wait -= delta
		if flicker_wait <= 0.0:
			flicker_left = randf_range(0.04, 0.12)
			flicker_wait = randf_range(0.6, 3.5)
	if status_left > 0.0:
		status_left -= delta
		if status_left <= 0.0:
			status.text = ""


func _status(text: String, warn := false) -> void:
	status.text = text
	status.add_theme_color_override("font_color", SELECT if warn else BONE)
	status_left = 3.5
	if warn:
		_sfx("locked", -10.0)


## Sonido del menú. No usa Sfx porque esos sonidos se quedan en pausa con el juego.
func _sfx(sound: String, volume_db := -8.0) -> void:
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


# --------------------------------------------------------------- ayudas

func _mission() -> MissionManager:
	return get_tree().get_first_node_in_group("mission_manager") as MissionManager


func _clock(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]


## "2026-10-21 20:47:12" -> "21/10/2026  20:47"
func _date(stamp: String) -> String:
	var parts := stamp.split(" ")
	if parts.size() < 2:
		return stamp
	var d := parts[0].split("-")
	if d.size() < 3:
		return stamp
	return "%s/%s/%s  %s" % [d[2], d[1], d[0], parts[1].substr(0, 5)]
