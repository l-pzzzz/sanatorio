class_name RootHeart
extends Interactable
## El corazón de la raíz (nivel 3). Se destruye a hachazos: cada golpe le quita vida, el corazón se
## encoge, late más débil y la barra "CORAZÓN" baja. Al llegar a 0 la estructura se debilita
## (el nivel avisa a MissionManager con report("heart", "destroyed")) y ya se puede quemar todo.

signal destroyed

const HITS_BY_DIFFICULTY := [7, 9, 11]
const FLESH := "res://assets/textures/rooms/wall_organic.png"

@export var room_height := 5.6
@export var hit_noise := 1.0
@export_file("*.glb") var model_path := "res://assets/models/heart_model.glb"   ## Si existe, reemplaza al corazón de bolas
@export var model_scale := 2.1

var max_health := 100.0
var health := 100.0
var is_dead := false
var busy := false
var body: Node3D
var light: OmniLight3D
var mat: StandardMaterial3D
var pulse_t := 0.0
var bar_layer: CanvasLayer
var bar_fill: ColorRect
var bar_ghost: ColorRect
var bar_label: Label
var _player: PlayerCharacter
var _flash: ColorRect


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_to_group("root_heart")
	body = Node3D.new()
	body.position = Vector3(0, 2.2, 0)
	add_child(body)
	mat = StandardMaterial3D.new()
	if ResourceLoader.exists(FLESH):
		mat.albedo_texture = load(FLESH)
	mat.albedo_color = Color(0.5, 0.17, 0.2)
	mat.roughness = 0.45
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.02, 0.05)
	mat.emission_energy_multiplier = 0.6
	if not _build_model():
		# sin modelo 3D: masa principal + lóbulos para que no parezca una bola
		_blob(Vector3.ZERO, Vector3(1.7, 1.9, 1.6))
		_blob(Vector3(-0.9, 0.5, 0.3), Vector3(1.0, 1.1, 1.0))
		_blob(Vector3(0.8, 0.7, -0.2), Vector3(0.9, 1.0, 0.9))
		_blob(Vector3(0.2, -0.9, 0.5), Vector3(0.9, 0.9, 1.0))
		_blob(Vector3(0.1, 1.5, -0.1), Vector3(0.55, 0.9, 0.55))
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.9
	shape.shape = sph
	shape.position = Vector3(0, 2.2, 0)
	add_child(shape)
	light = OmniLight3D.new()
	light.position = Vector3(0, 4.2, 0)
	light.light_color = Color(1.0, 0.12, 0.2)
	light.light_energy = 1.6
	light.omni_range = 12.0
	add_child(light)
	var hits: int = HITS_BY_DIFFICULTY[clampi(Difficulty.level, 0, 2)]
	hit_damage = max_health / float(hits)
	_build_bar()
	_player = get_tree().get_first_node_in_group("player") as PlayerCharacter


var hit_damage := 12.0


## Carga el corazón realista (glb). Devuelve false si no existe y se usa el de bolas.
func _build_model() -> bool:
	if not ResourceLoader.exists(model_path):
		return false
	var scene := load(model_path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE * model_scale
	model.position = Vector3(0, -0.95 * model_scale, 0)   # el centro del modelo queda en el centro del cuerpo
	body.add_child(model)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var base := mi.get_active_material(0) as StandardMaterial3D
		if base == null:
			continue
		mat = base.duplicate() as StandardMaterial3D
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission = Color(1.0, 0.25, 0.25)
		mat.emission_energy_multiplier = 0.6
		mi.material_override = mat
	return true


func _blob(pos: Vector3, scl: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 8
	mi.mesh = sm
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	body.add_child(mi)


func get_prompt(player: PlayerCharacter) -> String:
	if is_dead or busy:
		return ""
	if player.has_item("hacha"):
		return Lang.t("[E] Golpear el corazón con el hacha")
	return Lang.t("El corazón de la raíz late... necesitas un hacha")


func interact(player: PlayerCharacter) -> void:
	if is_dead or busy:
		return
	if not player.has_item("hacha"):
		Sfx.play(self, "locked")
		toast(Lang.t("Con las manos no vas a lograr nada. Necesitas el hacha."), 3.0)
		return
	busy = true
	# TEMPORAL: cuando exista el cuerpo del jugador aquí vuelve: await player.swing_axe_wait()
	await get_tree().create_timer(0.45).timeout
	if is_dead:
		return
	_hit()
	busy = false


func _hit() -> void:
	health = maxf(0.0, health - hit_damage)
	Sfx.play(self, "flesh_tear", 2.0)
	Sfx.play(self, "land", -2.0)
	NoiseManager.emit_noise(global_position, hit_noise)
	# golpe visual: el corazón se hincha y se pone rojo brillante un instante
	var tw := create_tween()
	tw.tween_property(body, "scale", body.scale * 1.18, 0.07)
	tw.tween_property(body, "scale", _target_scale(), 0.25)
	mat.emission_energy_multiplier = 3.0
	light.light_energy = 4.0
	_spray()
	_screen_flash(0.28)
	_update_bar()
	if health <= 0.0:
		_die()
	else:
		var left := int(ceilf(health / hit_damage))
		if left == int(ceilf(0.5 * max_health / hit_damage)):
			toast(Lang.t("El suelo vibra... la raíz se retuerce. Sigue golpeando."), 3.0)


func _target_scale() -> Vector3:
	return Vector3.ONE * (0.45 + 0.55 * (health / max_health))


func _spray() -> void:
	var p := CPUParticles3D.new()
	p.position = Vector3(0, 2.2, 0)
	p.emitting = false
	p.one_shot = true
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -9.0, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.02, 0.05)
	m.emission_enabled = true
	m.emission = Color(0.8, 0.05, 0.08)
	p.material_override = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _screen_flash(alpha: float) -> void:
	if _flash == null:
		return
	_flash.color.a = alpha
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.35)


func _die() -> void:
	is_dead = true
	busy = true
	collision_layer = 0
	Sfx.play(self, "explosion", 0.0)
	Sfx.play(self, "kill_roar_eco", -4.0)
	NoiseManager.emit_noise(global_position, 2.0)
	_screen_flash(0.6)
	_shake(2.2)
	var tw := create_tween()
	tw.tween_property(body, "scale", Vector3.ONE * 0.25, 1.4)
	tw.parallel().tween_property(mat, "emission_energy_multiplier", 0.0, 1.4)
	tw.parallel().tween_property(mat, "albedo_color", Color(0.12, 0.1, 0.1), 1.4)
	tw.parallel().tween_property(light, "light_energy", 0.0, 1.4)
	_spray()
	bar_layer.visible = false
	destroyed.emit()
	var mm := mission()
	if mm:
		mm.report("heart", "destroyed")


func _shake(seconds: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t := 0.0
	while t < seconds:
		var k := 1.0 - t / seconds
		cam.h_offset = randf_range(-0.12, 0.12) * k
		cam.v_offset = randf_range(-0.1, 0.1) * k
		await get_tree().process_frame
		t += get_process_delta_time()
	cam.h_offset = 0.0
	cam.v_offset = 0.0


func _process(delta: float) -> void:
	if is_dead:
		return
	pulse_t += delta * (1.6 + 1.4 * (1.0 - health / max_health))
	var beat := pow(maxf(0.0, sin(pulse_t * 3.0)), 6.0)
	body.scale = body.scale.lerp(_target_scale() * (1.0 + 0.05 * beat), minf(delta * 12.0, 1.0))
	mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, 0.45 + 0.9 * beat * (health / max_health + 0.3), minf(delta * 8.0, 1.0))
	light.light_energy = lerpf(light.light_energy, (1.0 + 1.2 * beat) * (0.4 + 0.6 * health / max_health), minf(delta * 8.0, 1.0))
	if _player != null and bar_layer != null:
		bar_layer.visible = _player.global_position.y < global_position.y + 3.5 and _player.global_position.distance_to(global_position) < 22.0
	if bar_ghost != null:
		bar_ghost.size.x = move_toward(bar_ghost.size.x, bar_fill.size.x, delta * 260.0)


func _build_bar() -> void:
	bar_layer = CanvasLayer.new()
	bar_layer.layer = 9
	bar_layer.visible = false
	add_child(bar_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_layer.add_child(root)
	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.0, 0.05, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	var width := 520.0
	var frame := ColorRect.new()
	frame.color = Color(0.0, 0.0, 0.0, 0.75)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.offset_left = -width / 2.0 - 4.0
	frame.offset_right = width / 2.0 + 4.0
	frame.anchor_top = 0.945
	frame.anchor_bottom = 0.945
	frame.offset_top = -4.0
	frame.offset_bottom = 26.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	bar_ghost = ColorRect.new()
	bar_ghost.color = Color(0.95, 0.85, 0.85, 0.9)
	bar_ghost.position = Vector2(4, 4)
	bar_ghost.size = Vector2(width, 22)
	bar_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bar_ghost)
	bar_fill = ColorRect.new()
	bar_fill.color = Color(0.9, 0.12, 0.12)
	bar_fill.position = Vector2(4, 4)
	bar_fill.size = Vector2(width, 22)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bar_fill)
	bar_label = Label.new()
	bar_label.text = Lang.t("CORAZÓN")
	bar_label.add_theme_font_size_override("font_size", 20)
	bar_label.add_theme_color_override("font_outline_color", Color.BLACK)
	bar_label.add_theme_constant_override("outline_size", 6)
	bar_label.anchor_left = 0.5
	bar_label.anchor_right = 0.5
	bar_label.offset_left = -width / 2.0
	bar_label.offset_right = width / 2.0
	bar_label.anchor_top = 0.945
	bar_label.anchor_bottom = 0.945
	bar_label.offset_top = -34.0
	bar_label.offset_bottom = -6.0
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_label)


func _update_bar() -> void:
	bar_fill.size.x = 520.0 * (health / max_health)
