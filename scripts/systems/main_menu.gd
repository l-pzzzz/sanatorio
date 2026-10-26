extends Control
## Menú principal: UN JUGADOR · MULTIJUGADOR (red local) · MICRÓFONO · idioma · SALIR.
## Mismo estilo que el menú de pausa (rojo sangre sobre negro, grano y viñeta).
## Flechas / ratón para elegir, Enter para aceptar, ESC para volver.

enum Page { MAIN, MP, JOIN, LOBBY, MIC }

const BLOOD := Color(0.8, 0.12, 0.1)
const BONE := Color(0.85, 0.8, 0.75)
const SELECT := Color(1.0, 0.45, 0.4)
const DIM := Color(0.85, 0.8, 0.75, 0.45)
const SINGLE_SCENE := "res://scenes/menu_dificultad.tscn"

const BG_SHADER := """
shader_type canvas_item;
// Fondo: negro rojizo con niebla que se mueve despacio, viñeta, grano y líneas.
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	float a = rnd(i), b = rnd(i + vec2(1.0, 0.0)), c = rnd(i + vec2(0.0, 1.0)), d = rnd(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
void fragment() {
	vec2 uv = UV;
	float fog = noise(uv * 3.0 + vec2(TIME * 0.03, TIME * 0.015)) * 0.6 + noise(uv * 7.0 - vec2(TIME * 0.05, 0.0)) * 0.4;
	float vig = smoothstep(0.15, 0.85, distance(uv, vec2(0.5)));
	float grain = rnd(floor(FRAGCOORD.xy / 3.0) + floor(TIME * 18.0)) - 0.5;
	float scan = step(0.5, fract(FRAGCOORD.y / 3.0));
	vec3 col = vec3(0.03, 0.0, 0.0) + vec3(0.11, 0.012, 0.01) * fog * (1.0 - vig);
	col += grain * 0.03;
	col *= 0.9 + 0.1 * scan;
	COLOR = vec4(col, 1.0);
}
"""

var page := Page.MAIN
var title: Label
var subtitle: Label
var status: Label
var hint: Label
var boxes := {}                      ## Page -> VBoxContainer
var b := {}                          ## id -> Button
var name_edit: LineEdit
var ip_edit: LineEdit
var games_box: VBoxContainer
var games_label: Label
var lobby_players: VBoxContainer
var lobby_info: Label
var lobby_ip: Label
var mic_slider: HSlider
var mic_value: Label
var mic_meter: MicMeter
var mic_state: Label
var flicker_left := 0.0
var flicker_wait := 1.2
var status_left := 0.0


## Barra del micrófono: nivel actual, línea del umbral y parpadeo cuando te oyen.
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	_build()
	Net.players_changed.connect(_on_net_changed)
	Net.lobby_changed.connect(_on_net_changed)
	Net.joined.connect(func() -> void: _show(Page.LOBBY))
	Net.session_ended.connect(_on_session_ended)
	Net.games_changed.connect(_refresh_games)
	Lang.changed.connect(_refresh_texts)
	# Si se vuelve aquí desde una partida en red (o se perdió la conexión), se cierra la sesión.
	if Net.is_online() and not Net.in_game and Net.is_host():
		_show(Page.LOBBY)
	else:
		if Net.is_online():
			Net.leave()
		_show(Page.MAIN)
	if Net.menu_message != "":
		_status(Lang.t(Net.menu_message), true)
		Net.menu_message = ""


func _exit_tree() -> void:
	Net.stop_listening()


# ----------------------------------------------------------------- páginas

func _show(p: Page) -> void:
	page = p
	for k in boxes:
		boxes[k].visible = (k == p)
	if p == Page.JOIN:
		Net.start_listening()
		_refresh_games()
	else:
		Net.stop_listening()
	_refresh_texts()
	match p:
		Page.MAIN:
			_focus(b["single"])
		Page.MP:
			_focus(b["host"])
		Page.JOIN:
			_focus(ip_edit if games_box.get_child_count() == 0 else games_box.get_child(0))
		Page.LOBBY:
			_focus(b["start"] if Net.is_host() else b["lobby_leave"])
		Page.MIC:
			_focus(mic_slider)


func _refresh_texts() -> void:
	b["single"].text = Lang.t("UN JUGADOR")
	b["multi"].text = Lang.t("MULTIJUGADOR (RED LOCAL)")
	b["mic"].text = Lang.t("MICRÓFONO")
	b["lang"].text = Lang.t("Idioma: Español") + "   [L]"
	b["quit"].text = Lang.t("SALIR")
	b["host"].text = Lang.t("CREAR PARTIDA")
	b["join"].text = Lang.t("UNIRSE A UNA PARTIDA")
	b["mp_back"].text = Lang.t("VOLVER")
	b["connect"].text = Lang.t("CONECTAR")
	b["join_back"].text = Lang.t("VOLVER")
	b["start"].text = Lang.t("EMPEZAR PARTIDA")
	b["lobby_leave"].text = Lang.t("SALIR DE LA SALA")
	b["mic_toggle"].text = Lang.t("MICRÓFONO: ACTIVADO") if NoiseManager.mic_enabled else Lang.t("MICRÓFONO: DESACTIVADO")
	b["mic_device"].text = Lang.t("DISPOSITIVO: %s") % _device_label(NoiseManager.current_device())
	b["mic_noisy"].text = Lang.t("MODO AMBIENTE RUIDOSO (FERIA): SÍ") if NoiseManager.noisy_mode else Lang.t("MODO AMBIENTE RUIDOSO (FERIA): NO")
	b["mic_recal"].text = Lang.t("RECALIBRAR (medir el silencio)")
	b["mic_reset"].text = Lang.t("RESTABLECER")
	b["mic_back"].text = Lang.t("GUARDAR Y VOLVER")
	name_edit.placeholder_text = Lang.t("Tu nombre")
	subtitle.text = Lang.t("SANTA MARTA")
	match page:
		Page.MAIN:
			title.text = "SANATORIO"
		Page.MP:
			title.text = Lang.t("MULTIJUGADOR")
		Page.JOIN:
			title.text = Lang.t("UNIRSE")
		Page.LOBBY:
			title.text = Lang.t("SALA DE ESPERA")
		Page.MIC:
			title.text = Lang.t("MICRÓFONO")
	# Título grande solo en la portada; en las demás páginas más chico para que todo quepa.
	title.add_theme_font_size_override("font_size", 64 if page == Page.MAIN else 44)
	subtitle.visible = page == Page.MAIN
	hint.text = Lang.t("FLECHAS / RATÓN  elegir      ENTER  aceptar      ESC  volver")
	if page == Page.MAIN:
		hint.text = Lang.t("FLECHAS / RATÓN  elegir      ENTER  aceptar      L  idioma      F11  pantalla completa")
	_refresh_lobby()
	_refresh_mic_value()


# ----------------------------------------------------------------- acciones

func _on_single() -> void:
	_sfx("click", -8.0)
	get_tree().change_scene_to_file(SINGLE_SCENE)


func _on_host() -> void:
	_sfx("click", -8.0)
	Net.set_my_name(name_edit.text)
	var err := Net.host_game()
	if err != OK:
		_status(Lang.t("No se pudo crear la partida: el puerto %d está ocupado (¿otra copia del juego abierta?).") % Net.PORT, true)
		return
	_show(Page.LOBBY)


func _on_connect(ip: String) -> void:
	_sfx("click", -8.0)
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		_status(Lang.t("Escribe una IP válida, por ejemplo 192.168.1.20"), true)
		return
	Net.set_my_name(name_edit.text)
	if Net.join_game(ip) != OK:
		_status(Lang.t("No se pudo conectar con esa partida."), true)
		return
	_status(Lang.t("Conectando con %s...") % ip, false, 12.0)


func _on_session_ended(reason: String) -> void:
	_status(Lang.t(reason), true)
	if page == Page.LOBBY:
		_show(Page.MP)


func _on_leave_lobby() -> void:
	_sfx("click", -8.0)
	Net.leave()
	_show(Page.MP)


func _on_net_changed() -> void:
	if page == Page.LOBBY:
		_refresh_lobby()


func _cycle_difficulty() -> void:
	if Net.is_host():
		_sfx("click", -10.0)
		Net.set_lobby((Net.lobby_difficulty + 1) % 3, Net.lobby_level)


func _cycle_level() -> void:
	if Net.is_host():
		_sfx("click", -10.0)
		Net.set_lobby(Net.lobby_difficulty, (Net.lobby_level + 1) % Net.LEVELS.size())


func _refresh_lobby() -> void:
	if lobby_players == null:
		return
	for c in lobby_players.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var tags := PackedStringArray()
		if id == 1:
			tags.append(Lang.t("anfitrión"))
		if id == Net.my_id():
			tags.append(Lang.t("tú"))
		var line := _make_label(22, BONE)
		line.text = "●  " + Net.player_name(id) + ("   (" + ", ".join(tags) + ")" if not tags.is_empty() else "")
		lobby_players.add_child(line)
	for i in range(ids.size(), Net.MAX_PLAYERS):
		var empty := _make_label(20, Color(BONE, 0.25))
		empty.text = "○  " + Lang.t("libre")
		lobby_players.add_child(empty)
	var host := Net.is_host()
	b["diff"].text = Lang.t("DIFICULTAD: %s") % Lang.t(Difficulty.NAMES[Net.lobby_difficulty])
	b["level"].text = Lang.t("NIVEL: %s") % Lang.t(str(Net.LEVELS[Net.lobby_level][0]))
	b["diff"].disabled = not host
	b["level"].disabled = not host
	b["start"].visible = host
	if host:
		var ips := Net.local_ips()
		lobby_ip.text = Lang.t("Tus compañeros te verán en \"Unirse\". Si no, que escriban tu IP: %s") % (", ".join(ips) if not ips.is_empty() else "?")
		lobby_info.text = Lang.t("Puedes empezar solo o esperar a que entren (hasta %d).") % Net.MAX_PLAYERS
	else:
		lobby_ip.text = ""
		lobby_info.text = Lang.t("Esperando a que el anfitrión empiece la partida...")


func _refresh_games() -> void:
	if games_box == null:
		return
	for c in games_box.get_children():
		games_box.remove_child(c)
		c.queue_free()
	# Una misma partida puede llegar por la red y por 127.0.0.1 (misma PC): se muestra una vez.
	var shown := {}
	var ips: Array = Net.found.keys()
	ips.sort_custom(func(x: String, y: String) -> bool: return x.begins_with("127.") == false and y.begins_with("127."))
	for ip in ips:
		var info: Dictionary = Net.found[ip]
		var key := "%s/%s" % [info.get("name", ""), info.get("players", 0)]
		if shown.has(key):
			continue
		shown[key] = true
		var g := _make_button(Lang.t("Partida de %s   ·   %d/%d   ·   %s") % [info.get("name", "?"), int(info.get("players", 1)), int(info.get("max", 4)), ip], 20)
		g.custom_minimum_size = Vector2(560, 44)
		g.pressed.connect(_on_connect.bind(ip))
		games_box.add_child(g)
	games_label.text = Lang.t("PARTIDAS EN TU RED") if games_box.get_child_count() > 0 else Lang.t("Buscando partidas en tu red...")
	_wrap_focus(boxes[Page.JOIN])


# ----------------------------------------------------------------- micrófono

func _on_mic_slider(value: float) -> void:
	NoiseManager.set_sensitivity(value / 100.0)
	_refresh_mic_value()


func _refresh_mic_value() -> void:
	if mic_value == null:
		return
	mic_value.text = Lang.t("SENSIBILIDAD: %d %%") % roundi(NoiseManager.sensitivity * 100.0)


func _toggle_mic() -> void:
	_sfx("click", -8.0)
	NoiseManager.set_mic_enabled(not NoiseManager.mic_enabled)
	_refresh_texts()


func _toggle_noisy() -> void:
	_sfx("click", -8.0)
	NoiseManager.set_noisy_mode(not NoiseManager.noisy_mode)
	_refresh_texts()


func _cycle_device() -> void:
	_sfx("click", -8.0)
	var devices: PackedStringArray = NoiseManager.input_devices()
	if devices.is_empty():
		return
	var i: int = devices.find(NoiseManager.current_device())
	NoiseManager.set_device(devices[(i + 1) % devices.size()])
	_refresh_texts()


func _reset_mic() -> void:
	_sfx("click", -8.0)
	NoiseManager.set_sensitivity(NoiseManager.DEFAULT_SENSITIVITY)
	NoiseManager.set_mic_enabled(true)
	NoiseManager.set_noisy_mode(false)
	NoiseManager.set_device("Default")
	mic_slider.set_value_no_signal(NoiseManager.sensitivity * 100.0)
	_refresh_texts()


func _leave_mic() -> void:
	_sfx("click", -8.0)
	NoiseManager.save_settings()
	_show(Page.MAIN)
	_status(Lang.t("Ajustes del micrófono guardados."))


func _device_label(device: String) -> String:
	if device == "Default" or device == "":
		return Lang.t("predeterminado")
	return device.substr(0, 34) + ("…" if device.length() > 34 else "")


# ----------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L \
			and page == Page.MAIN and not (get_viewport().gui_get_focus_owner() is LineEdit):
		Lang.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		match page:
			Page.MP:
				_show(Page.MAIN)
			Page.JOIN:
				if Net.is_online():
					Net.leave()
				_show(Page.MP)
			Page.LOBBY:
				_on_leave_lobby()
			Page.MIC:
				_leave_mic()


func _process(delta: float) -> void:
	if flicker_left > 0.0:
		flicker_left -= delta
		title.modulate.a = 0.3
	else:
		title.modulate.a = 1.0
		flicker_wait -= delta
		if flicker_wait <= 0.0:
			flicker_left = randf_range(0.04, 0.12)
			flicker_wait = randf_range(0.8, 4.0)
	if status_left > 0.0:
		status_left -= delta
		if status_left <= 0.0:
			status.text = ""
	if page == Page.MIC:
		mic_meter.queue_redraw()
		var nm := NoiseManager
		if not nm.mic_enabled:
			mic_state.text = Lang.t("Micrófono desactivado: las criaturas solo oirán tus pasos y objetos.")
			mic_state.add_theme_color_override("font_color", DIM)
		elif nm.calibration_left > 0.0:
			mic_state.text = Lang.t("CALIBRANDO... quédate en silencio")
			mic_state.add_theme_color_override("font_color", DIM)
		elif Time.get_ticks_msec() / 1000.0 - nm.heard_at < 0.5:
			mic_state.text = Lang.t("¡TE OYEN!   (%.0f dB · umbral %.0f dB)") % [nm.level_db, nm.threshold_db]
			mic_state.add_theme_color_override("font_color", SELECT)
		else:
			mic_state.text = Lang.t("silencio   (%.0f dB · umbral %.0f dB)") % [nm.level_db, nm.threshold_db]
			mic_state.add_theme_color_override("font_color", DIM)


# ----------------------------------------------------------------- construcción

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = BG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	bg.material = mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	center.add_child(content)

	title = _make_label(64, BLOOD)
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("outline_size", 10)
	content.add_child(title)
	subtitle = _make_label(16, DIM)
	content.add_child(subtitle)
	var rule := ColorRect.new()
	rule.color = Color(BLOOD, 0.55)
	rule.custom_minimum_size = Vector2(460, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(rule)
	content.add_child(_spacer(8))

	# --- principal
	var main := _page(content, Page.MAIN)
	_add(main, "single", _on_single)
	_add(main, "multi", func() -> void:
		_sfx("click", -8.0)
		_show(Page.MP))
	_add(main, "mic", func() -> void:
		_sfx("click", -8.0)
		mic_slider.set_value_no_signal(NoiseManager.sensitivity * 100.0)
		NoiseManager.recalibrate()
		_show(Page.MIC))
	_add(main, "lang", func() -> void:
		_sfx("click", -10.0)
		Lang.toggle(), 20)
	_add(main, "quit", func() -> void: get_tree().quit())

	# --- multijugador
	var mp := _page(content, Page.MP)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_label := _make_label(20, DIM)
	name_label.text = Lang.t("TU NOMBRE:")
	name_row.add_child(name_label)
	name_edit = _make_edit(Net.my_name, 260)
	name_edit.max_length = 16
	name_row.add_child(name_edit)
	mp.add_child(name_row)
	mp.add_child(_spacer(6))
	_add(mp, "host", _on_host)
	_add(mp, "join", func() -> void:
		_sfx("click", -8.0)
		Net.set_my_name(name_edit.text)
		_show(Page.JOIN))
	_add(mp, "mp_back", func() -> void:
		_sfx("click", -10.0)
		_show(Page.MAIN))
	var mp_note := _make_label(14, Color(BONE, 0.35))
	mp_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_note.custom_minimum_size = Vector2(560, 0)
	mp_note.text = Lang.t("Cooperativo de 2 a 4 jugadores en la misma red (Wi-Fi o cable). Todos deben tener la misma versión del juego. La primera vez, Windows puede pedir permiso en el firewall: acéptalo.")
	mp.add_child(_spacer(4))
	mp.add_child(mp_note)

	# --- unirse
	var join := _page(content, Page.JOIN)
	games_label = _make_label(18, DIM)
	join.add_child(games_label)
	games_box = VBoxContainer.new()
	games_box.add_theme_constant_override("separation", 6)
	join.add_child(games_box)
	join.add_child(_spacer(6))
	var ip_row := HBoxContainer.new()
	ip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ip_row.add_theme_constant_override("separation", 10)
	ip_edit = _make_edit("", 260)
	ip_edit.placeholder_text = "192.168.1.20"
	ip_edit.text_submitted.connect(func(t: String) -> void: _on_connect(t))
	ip_row.add_child(ip_edit)
	var connect_b := _make_button("", 20)
	connect_b.custom_minimum_size = Vector2(170, 44)
	connect_b.pressed.connect(func() -> void: _on_connect(ip_edit.text))
	ip_row.add_child(connect_b)
	b["connect"] = connect_b
	join.add_child(ip_row)
	_add(join, "join_back", func() -> void:
		_sfx("click", -10.0)
		if Net.is_online():
			Net.leave()
		_show(Page.MP))

	# --- sala de espera
	var lobby := _page(content, Page.LOBBY)
	lobby_players = VBoxContainer.new()
	lobby_players.add_theme_constant_override("separation", 2)
	lobby.add_child(lobby_players)
	lobby.add_child(_spacer(6))
	_add(lobby, "diff", _cycle_difficulty, 22)
	_add(lobby, "level", _cycle_level, 22)
	lobby_info = _make_label(16, DIM)
	lobby.add_child(lobby_info)
	_add(lobby, "start", func() -> void:
		_sfx("lever_clunk", -6.0)
		Net.start_game())
	_add(lobby, "lobby_leave", _on_leave_lobby)
	lobby_ip = _make_label(14, Color(BONE, 0.4))
	lobby_ip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_ip.custom_minimum_size = Vector2(560, 0)
	lobby.add_child(lobby_ip)

	# --- micrófono
	var mic := _page(content, Page.MIC)
	_add(mic, "mic_toggle", _toggle_mic, 22).custom_minimum_size.y = 40
	_add(mic, "mic_noisy", _toggle_noisy, 18).custom_minimum_size.y = 38
	_add(mic, "mic_device", _cycle_device, 18).custom_minimum_size.y = 38
	mic.add_child(_spacer(4))
	mic_value = _make_label(22, BONE)
	mic.add_child(mic_value)
	mic_slider = _make_slider()
	mic_slider.value_changed.connect(_on_mic_slider)
	mic.add_child(mic_slider)
	var scale_row := HBoxContainer.new()
	scale_row.custom_minimum_size = Vector2(480, 0)
	scale_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var lo := _make_label(13, Color(BONE, 0.35))
	lo.text = Lang.t("solo si gritas")
	lo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lo.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var hi := _make_label(13, Color(BONE, 0.35))
	hi.text = Lang.t("hasta si respiras")
	hi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hi.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_row.add_child(lo)
	scale_row.add_child(hi)
	mic.add_child(scale_row)
	mic.add_child(_spacer(10))
	mic_meter = MicMeter.new()
	mic_meter.custom_minimum_size = Vector2(480, 22)
	mic_meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mic_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mic.add_child(mic_meter)
	mic_state = _make_label(18, DIM)
	mic.add_child(mic_state)
	var how := _make_label(14, Color(BONE, 0.4))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(560, 0)
	how.text = Lang.t("Habla, aplaude o respira cerca del micrófono. Si la barra cruza la línea roja, las criaturas te oyen. Más sensibilidad = te oyen con menos ruido.") \
		+ "\n" + Lang.t("¿Hay mucho ruido alrededor? Activa el MODO AMBIENTE RUIDOSO, baja la sensibilidad y pulsa RECALIBRAR.")
	mic.add_child(how)
	mic.add_child(_spacer(4))
	_add(mic, "mic_recal", func() -> void:
		_sfx("click", -8.0)
		NoiseManager.recalibrate(), 18).custom_minimum_size.y = 38
	_add(mic, "mic_reset", _reset_mic, 18).custom_minimum_size.y = 38
	_add(mic, "mic_back", _leave_mic, 24)

	for k in boxes:
		_wrap_focus(boxes[k])

	content.add_child(_spacer(6))
	status = _make_label(18, BONE)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(560, 28)
	content.add_child(status)
	hint = _make_label(14, Color(BONE, 0.35))
	content.add_child(hint)


func _page(parent: Container, p: Page) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	parent.add_child(box)
	boxes[p] = box
	return box


func _add(box: Container, id: String, action: Callable, font_size := 26) -> Button:
	var button := _make_button("", font_size)
	button.pressed.connect(action)
	box.add_child(button)
	b[id] = button
	return button


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
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(460, 46)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", Color(BONE, 0.75))
	button.add_theme_color_override("font_hover_color", SELECT)
	button.add_theme_color_override("font_focus_color", SELECT)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(BONE, 0.55))
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 6)
	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(0, 0, 0, 0)
	idle.content_margin_left = 16
	idle.content_margin_right = 16
	idle.content_margin_top = 5
	idle.content_margin_bottom = 5
	var lit := idle.duplicate() as StyleBoxFlat
	lit.bg_color = Color(0.4, 0.02, 0.02, 0.4)
	lit.border_width_left = 4
	lit.border_width_right = 4
	lit.border_color = BLOOD
	var pressed := lit.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.6, 0.05, 0.04, 0.55)
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("disabled", idle)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("focus", lit)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("pressed", pressed)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			button.grab_focus())
	button.focus_entered.connect(func() -> void: _sfx("click", -20.0))
	return button


func _make_edit(text: String, width: float) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = text
	edit.custom_minimum_size = Vector2(width, 42)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 20)
	edit.add_theme_color_override("font_color", BONE)
	edit.add_theme_color_override("font_placeholder_color", Color(BONE, 0.3))
	edit.add_theme_color_override("caret_color", SELECT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.01, 0.01, 0.85)
	box.border_width_bottom = 2
	box.border_color = Color(BLOOD, 0.7)
	box.content_margin_left = 10
	box.content_margin_right = 10
	var focus := box.duplicate() as StyleBoxFlat
	focus.border_width_bottom = 3
	focus.border_color = SELECT
	edit.add_theme_stylebox_override("normal", box)
	edit.add_theme_stylebox_override("focus", focus)
	return edit


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.custom_minimum_size = Vector2(480, 28)
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
	slider.focus_entered.connect(func() -> void: _sfx("click", -20.0))
	return slider


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Flecha abajo en el último elemento vuelve al primero y viceversa.
func _wrap_focus(box: Container) -> void:
	var list: Array[Control] = []
	_collect_focusable(box, list)
	for i in list.size():
		list[i].focus_neighbor_top = list[(i - 1 + list.size()) % list.size()].get_path()
		list[i].focus_neighbor_bottom = list[(i + 1) % list.size()].get_path()


func _collect_focusable(node: Node, out: Array[Control]) -> void:
	for c in node.get_children():
		if (c is Button or c is LineEdit or c is HSlider) and c.is_inside_tree():
			out.append(c)
		elif c is Container:
			_collect_focusable(c, out)


func _focus(c: Control) -> void:
	if c:
		c.grab_focus.call_deferred()


func _status(text: String, warn := false, seconds := 4.0) -> void:
	status.text = text
	status.add_theme_color_override("font_color", SELECT if warn else BONE)
	status_left = seconds
	if warn:
		_sfx("locked", -10.0)


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
