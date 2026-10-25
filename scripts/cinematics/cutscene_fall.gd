extends Node3D
## Cinemática: la puerta "de salida" del sanatorio lleva en realidad a los sótanos.
## Todo se arma por código (sin video): pasillo, puerta, escalera, caída y sótano con
## moho y hongos. Enter / Espacio / Esc la saltan. Al terminar carga `next_scene`.

@export_file("*.tscn") var next_scene := "res://scenes/nivel_2_sotano.tscn"

const SUB := [
	[0.6, 3.6, "Corriste hasta la puerta principal."],
	[3.8, 6.6, "Por fin. La calle."],
	[8.0, 10.2, "Pero detrás de la reja no había calle."],
	[14.0, 17.2, "Santa Marta nunca terminó en la superficie."],
	[17.6, 21.0, "Algo aquí abajo escucha cada paso."],
]
const TITLE_AT := 22.0
const END_AT := 26.5

var cam: Camera3D
var fade: ColorRect
var subtitle: Label
var title_label: Label
var door: Node3D
var door_light: OmniLight3D
var flicker_light: OmniLight3D
var eco: Node3D
var drip_timer := 0.0
var t := 0.0
var done := false
var sounds_played := {}
var step_clock := 0.0
const BASEMENT := Vector3(0.0, 0.0, 200.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_world()
	_build_hud()
	if NoiseManager.meter:
		NoiseManager.meter.visible = false     # sin el medidor de micrófono durante la escena


func _unhandled_input(event: InputEvent) -> void:
	if done or Net.is_client():
		return      # en red solo el anfitrión puede saltar la cinemática
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		_finish()


func _finish() -> void:
	if done:
		return
	done = true
	if NoiseManager.meter:
		NoiseManager.meter.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Net.goto_scene(next_scene)      # en red: el anfitrión lleva a todos al siguiente nivel


# ------------------------------------------------------------------ mundo

func _mat(tex_path: String, fallback: Color, uv := Vector3(0.25, 0.25, 0.25), emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	else:
		m.albedo_color = fallback
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = uv
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = fallback
		m.emission_energy_multiplier = emit
	return m


func _box(parent: Node, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi


func _light(parent: Node, pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	parent.add_child(l)
	return l


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.2, 0.24)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.03)
	env.fog_density = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
	_build_corridor()
	_build_basement()


func _build_corridor() -> void:
	var tex := "res://assets/textures/sanatorium/"
	var wall := _mat(tex + "wall_plaster.png", Color(0.45, 0.5, 0.42), Vector3(0.25, 0.33, 0.25))
	var floor_m := _mat(tex + "floor_tile.png", Color(0.35, 0.37, 0.33), Vector3(0.5, 0.5, 0.5))
	var ceil_m := _mat(tex + "ceiling.png", Color(0.3, 0.3, 0.28), Vector3(0.5, 0.5, 0.5))
	var root := Node3D.new()
	root.name = "Corridor"
	add_child(root)
	_box(root, Vector3(4.0, 0.2, 22.0), Vector3(0, -0.1, -9.0), floor_m)
	_box(root, Vector3(4.0, 0.2, 22.0), Vector3(0, 3.1, -9.0), ceil_m)
	_box(root, Vector3(0.2, 3.0, 22.0), Vector3(-2.1, 1.5, -9.0), wall)
	_box(root, Vector3(0.2, 3.0, 22.0), Vector3(2.1, 1.5, -9.0), wall)
	_box(root, Vector3(4.4, 3.0, 0.2), Vector3(0, 1.5, 2.1), wall)
	# marco y reja de la puerta (se abre hacia arriba)
	var metal := _mat(tex + "door_metal.png", Color(0.35, 0.3, 0.25), Vector3(0.25, 0.33, 0.25))
	_box(root, Vector3(0.4, 3.0, 0.5), Vector3(-1.8, 1.5, -18.0), metal)
	_box(root, Vector3(0.4, 3.0, 0.5), Vector3(1.8, 1.5, -18.0), metal)
	_box(root, Vector3(4.0, 0.4, 0.5), Vector3(0, 2.9, -18.0), metal)
	door = Node3D.new()
	door.position = Vector3(0, 0, -18.0)
	root.add_child(door)
	_box(door, Vector3(3.2, 2.7, 0.3), Vector3(0, 1.35, 0), metal)
	door_light = _light(root, Vector3(0, 2.2, -17.0), Color(1.0, 0.93, 0.75), 1.4, 6.0)
	# luces del pasillo: una parpadea
	_light(root, Vector3(0, 2.6, -5.0), Color(0.78, 0.9, 0.7), 0.8, 7.0)
	flicker_light = _light(root, Vector3(0, 2.6, -11.0), Color(0.78, 0.9, 0.7), 0.8, 7.0)
	# detrás de la puerta: escalera hacia abajo, ladrillo oscuro
	var brick := _mat("res://assets/textures/sotano/wall_brick.png", Color(0.3, 0.25, 0.2), Vector3(0.25, 0.33, 0.25))
	for i in 12:
		var top := -0.3 * (i + 1)
		_box(root, Vector3(3.6, 0.3, 0.55), Vector3(0, top - 0.15, -18.6 - 0.55 * i), brick)
	_box(root, Vector3(0.3, 8.0, 12.0), Vector3(-1.95, -3.0, -23.0), brick)
	_box(root, Vector3(0.3, 8.0, 12.0), Vector3(1.95, -3.0, -23.0), brick)
	_light(root, Vector3(0, -0.6, -22.0), Color(0.3, 0.9, 0.4), 0.35, 4.0)


func _build_basement() -> void:
	var tex := "res://assets/textures/sotano/"
	var wall := _mat(tex + "wall_brick.png", Color(0.3, 0.25, 0.2), Vector3(0.25, 0.33, 0.25))
	var floor_m := _mat(tex + "floor_wet.png", Color(0.2, 0.25, 0.2), Vector3(0.5, 0.5, 0.5))
	var ceil_m := _mat(tex + "ceiling_concrete.png", Color(0.25, 0.25, 0.25), Vector3(0.5, 0.5, 0.5))
	var pipe := _mat(tex + "pipe_rust.png", Color(0.45, 0.26, 0.14), Vector3(1, 1, 1))
	var mold := StandardMaterial3D.new()
	mold.albedo_color = Color(0.1, 0.2, 0.08)
	mold.emission_enabled = true
	mold.emission = Color(0.12, 0.35, 0.1)
	mold.emission_energy_multiplier = 0.25
	mold.roughness = 1.0
	var root := Node3D.new()
	root.name = "Basement"
	root.position = BASEMENT
	add_child(root)
	_box(root, Vector3(4.0, 0.2, 24.0), Vector3(0, -0.1, -8.0), floor_m)
	_box(root, Vector3(4.0, 0.2, 24.0), Vector3(0, 3.1, -8.0), ceil_m)
	_box(root, Vector3(0.2, 3.0, 24.0), Vector3(-2.1, 1.5, -8.0), wall)
	_box(root, Vector3(0.2, 3.0, 24.0), Vector3(2.1, 1.5, -8.0), wall)
	_box(root, Vector3(4.4, 3.0, 0.2), Vector3(0, 1.5, 4.1), wall)
	_box(root, Vector3(4.4, 3.0, 0.2), Vector3(0, 1.5, -20.1), wall)
	for z in [-3.0, -9.0, -15.0]:
		var p := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.12
		cyl.height = 4.0
		p.mesh = cyl
		p.material_override = pipe
		p.rotation.z = PI / 2.0
		p.position = Vector3(0, 2.6, z)
		root.add_child(p)
	# moho: manchas gruesas que suben por las paredes y cubren el suelo
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 70:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := rng.randf_range(-19.0, 3.5)
		var w := rng.randf_range(0.25, 0.9)
		var h := rng.randf_range(0.2, 1.1)
		_box(root, Vector3(0.04, h, w), Vector3(side * 1.97, h / 2.0 + rng.randf_range(0.0, 0.5), z), mold)
	for i in 20:
		_box(root, Vector3(rng.randf_range(0.6, 1.8), 0.03, rng.randf_range(0.6, 1.8)), Vector3(rng.randf_range(-1.6, 1.6), 0.02, rng.randf_range(-19.0, 3.0)), mold)
	# hongos que brillan (los mismos del juego), mirando hacia el pasillo
	for i in 16:
		var side2 := -1.0 if i % 2 == 0 else 1.0
		var f := FungusGlow.new()
		f.base_energy = 0.9
		f.position = Vector3(side2 * 1.9, 0.0, -1.5 - i * 1.2)
		f.rotation.y = PI / 2.0 if side2 < 0.0 else -PI / 2.0
		root.add_child(f)
	# el Eco, al fondo, a contraluz de los hongos
	var scene_path := "res://assets/models/eco_model.glb"
	if ResourceLoader.exists(scene_path):
		eco = (load(scene_path) as PackedScene).instantiate() as Node3D
		eco.scale = Vector3.ONE * 1.6
		eco.position = Vector3(0, 0, -17.0)
		root.add_child(eco)
	_light(root, Vector3(0, 1.6, -19.0), Color(0.35, 1.0, 0.45), 2.0, 9.0)
	_light(root, Vector3(0, 2.4, 0.0), Color(0.5, 0.7, 0.55), 0.35, 8.0)


# --------------------------------------------------------------------- HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	subtitle = _label(layer, 28)
	subtitle.anchor_left = 0.1
	subtitle.anchor_right = 0.9
	subtitle.anchor_top = 0.78
	subtitle.anchor_bottom = 0.95
	subtitle.offset_left = 0
	subtitle.offset_right = 0
	subtitle.offset_top = 0
	subtitle.offset_bottom = 0
	title_label = _label(layer, 54)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.modulate.a = 0.0
	title_label.text = Lang.t("NIVEL 2\nLOS SÓTANOS")
	var skip := _label(layer, 14)
	skip.autowrap_mode = TextServer.AUTOWRAP_OFF
	skip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	skip.text = Lang.t("Enter: saltar")
	skip.position = Vector2(14, 10)
	skip.modulate.a = 0.5


func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ----------------------------------------------------------------- guion

func _once(key: String, at: float, action: Callable) -> void:
	if t >= at and not sounds_played.has(key):
		sounds_played[key] = true
		action.call()


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	_animate()
	_sounds(delta)
	if t >= END_AT:
		_finish()


func _animate() -> void:
	var shake := Vector3.ZERO
	var roll := 0.0
	var alpha := 0.0
	if t < 7.6:
		# A: avanzar por el pasillo hasta la puerta
		var k := clampf(t / 6.6, 0.0, 1.0)
		cam.position = Vector3(0, 1.6 + sin(t * 2.2) * 0.02, -1.0 - 14.0 * ease(k, 0.8))
		cam.rotation = Vector3(0, 0, 0)
		alpha = 1.0 - clampf(t / 1.2, 0.0, 1.0)            # entra desde negro
		door.position.y = 3.0 * smoothstep(5.8, 7.2, t)    # la reja sube
		if t > 5.5:
			flicker_light.light_energy = 0.4 + 0.5 * randf()
	elif t < 11.4:
		# B: cruza la puerta y baja la escalera; el suelo cede
		var kb := clampf((t - 7.6) / 2.4, 0.0, 1.0)
		var z := -15.0 - 8.5 * kb
		var y := 1.6 - 1.7 * smoothstep(0.35, 1.0, kb)
		cam.position = Vector3(0, y, z)
		cam.rotation = Vector3(-0.35 * kb, 0, 0)
		if t > 10.0:
			var f := (t - 10.0)
			cam.position.y -= f * f * 3.2                  # caída
			roll = f * 0.5
			cam.rotation.x -= f * 0.5
			shake = Vector3(randf() - 0.5, randf() - 0.5, 0.0) * 0.12 * minf(f * 3.0, 1.0)
		alpha = smoothstep(10.9, 11.4, t)
	else:
		# C: sótano. Despierta en el suelo, se incorpora y mira el pasillo
		var kc := clampf((t - 12.2) / 11.0, 0.0, 1.0)
		cam.position = BASEMENT + Vector3(0.15, lerpf(0.3, 1.45, smoothstep(0.0, 0.7, kc)), 2.5 - 2.0 * kc)
		roll = lerpf(0.55, 0.0, smoothstep(0.0, 0.6, kc))
		cam.rotation = Vector3(lerpf(0.5, -0.02, smoothstep(0.0, 0.7, kc)), lerpf(0.5, 0.0, smoothstep(0.0, 0.8, kc)), 0.0)
		alpha = 1.0 - smoothstep(11.6, 13.4, t)
		if t > 17.6:                                       # el chasquido: todo tiembla un instante
			shake = Vector3(randf() - 0.5, randf() - 0.5, 0.0) * 0.05 * exp(-(t - 17.6) * 2.5)
		if eco:
			var approach := smoothstep(17.0, 21.5, t)
			eco.position = Vector3(0, 0, lerpf(-17.0, -9.5, approach))
			eco.rotation.x = sin(t * 1.4) * 0.02
		alpha = maxf(alpha, smoothstep(23.4, 24.6, t))    # se va a negro
	cam.position += shake
	cam.rotation.z = roll
	fade.color.a = alpha
	# subtítulos
	var text := ""
	for s in SUB:
		if t >= float(s[0]) and t <= float(s[1]):
			text = Lang.t(str(s[2]))
	subtitle.text = text
	title_label.modulate.a = clampf((t - TITLE_AT) / 0.8, 0.0, 1.0) * (1.0 - smoothstep(25.6, 26.4, t))


func _sounds(delta: float) -> void:
	# pasos al caminar por el pasillo y la escalera
	if t > 0.8 and t < 9.8:
		step_clock += delta
		if step_clock > 0.62:
			step_clock = 0.0
			Sfx.play(self, "step_%d" % randi_range(1, 4), -12.0)
	_once("door", 5.8, func() -> void: Sfx.play(self, "gate_slide", -3.0))
	_once("drip1", 8.4, func() -> void: Sfx.play(self, "drip", -6.0))
	_once("crack", 10.0, func() -> void: Sfx.play(self, "locked", -2.0))
	_once("fall", 10.9, func() -> void:
		Sfx.play(self, "land", 2.0)
		Sfx.play(self, "splash_2", -2.0))
	_once("breath", 12.6, func() -> void: Sfx.play(self, "eco_breath", -10.0))
	_once("drip2", 13.4, func() -> void: Sfx.play(self, "drip", -4.0))
	_once("click", 17.6, func() -> void: Sfx.play(self, "eco_click", 0.0))
	_once("click2", 20.2, func() -> void: Sfx.play(self, "eco_click", 2.0))
	_once("title", TITLE_AT, func() -> void: Sfx.play(self, "alarm", -14.0))
