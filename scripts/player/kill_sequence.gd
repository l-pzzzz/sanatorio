class_name KillSequence
extends Node
# Animación de muerte: la criatura se lanza sobre el jugador y lo devora.
# Todo se mueve por tiempo (t) para que no dependa de la física congelada.

signal finished

const TOTAL := 5.2

var player: Node3D
var creature: Node3D
var is_bat := true
var t := 0.0
var cam: Camera3D
var layer: CanvasLayer
var canvas: Control
var vignette: TextureRect
var flash: ColorRect
var black: ColorRect
var splats: Array = []
var next_bite := 0.35
var bite_n := 0
var cam_base := Vector3.ZERO
var head_base_y := 1.6
var done := false
var did_tear := false
var did_gurgle := false
var rng := RandomNumberGenerator.new()
var blood: CPUParticles3D
var start_pos := Vector3.ZERO


class Splat:
	var pos: Vector2
	var radius: float
	var born: float
	var drip: float
	var sats: Array = []


class BloodCanvas extends Control:
	var seq: KillSequence
	func _draw() -> void:
		if seq == null:
			return
		for s in seq.splats:
			var age: float = seq.t - s.born
			var grow: float = clampf(age * 6.0, 0.0, 1.0)
			var col := Color(0.38, 0.0, 0.0, 0.92)
			draw_circle(s.pos, s.radius * grow, col)
			for sat in s.sats:
				draw_circle(s.pos + sat[0] * grow, sat[1] * grow, col)
			var dl: float = minf(s.drip * clampf(age * 0.35, 0.0, 1.0), 400.0)
			draw_rect(Rect2(s.pos.x - s.radius * 0.12, s.pos.y, s.radius * 0.24, dl), Color(0.3, 0.0, 0.0, 0.9))
			draw_circle(s.pos + Vector2(0, dl), s.radius * 0.17, Color(0.3, 0.0, 0.0, 0.9))


static func start(parent: Node, p: Node3D, c: Node3D, bat: bool) -> KillSequence:
	var k := KillSequence.new()
	k.player = p
	k.creature = c
	k.is_bat = bat
	parent.add_child(k)
	return k


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if "is_hidden" in player and player.is_hidden and player.has_method("leave_hiding"):
		player.leave_hiding()
	if "hands" in player and player.hands:
		player.hands.visible = false
	if "prompt_label" in player and player.prompt_label:
		player.prompt_label.visible = false
	cam = player.get_viewport().get_camera_3d()
	if cam == null:
		cam = player.find_child("Camera3D", true, false)
	head_base_y = player.head.position.y
	cam_base = cam.position
	start_pos = player.global_position

	# criatura frente al jugador, mirándolo
	var dir := creature.global_position - player.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = -player.global_transform.basis.z
	dir = dir.normalized()
	var dist := 1.0 if is_bat else 0.95
	creature.global_position = Vector3(player.global_position.x + dir.x * dist, player.global_position.y, player.global_position.z + dir.z * dist)
	creature.look_at(Vector3(player.global_position.x, creature.global_position.y, player.global_position.z), Vector3.UP)
	player.rotation.y = atan2(-dir.x, -dir.z)
	player.head.rotation.x = 0.1 if is_bat else -0.25
	player.head.rotation.z = 0.0

	# partículas de sangre desde la boca de la criatura
	blood = CPUParticles3D.new()
	blood.emitting = false
	blood.amount = 90
	blood.lifetime = 0.9
	blood.one_shot = false
	blood.explosiveness = 0.0
	blood.direction = Vector3(0, 0.3, 1)
	blood.spread = 55.0
	blood.initial_velocity_min = 1.5
	blood.initial_velocity_max = 4.0
	blood.gravity = Vector3(0, -7, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.0, 0.0)
	sm.material = mat
	blood.mesh = sm
	creature.add_child(blood)
	blood.position = Vector3(0, 1.5 if is_bat else 1.1, -0.35)
	blood.rotation = Vector3(0, PI, 0)

	# luz tenue para que se vea la criatura aunque la linterna esté apagada
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.45, 0.35)
	lamp.light_energy = 2.2
	lamp.omni_range = 5.0
	creature.add_child(lamp)
	lamp.global_position = player.global_position + Vector3(0, 1.8, 0)

	# capa 2D: viñeta + salpicaduras + fundido
	layer = CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.5, 0, 0, 0))
	grad.set_color(1, Color(0.35, 0, 0, 0.95))
	grad.set_offset(0, 0.35)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	vignette = TextureRect.new()
	vignette.texture = gt
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	layer.add_child(vignette)
	canvas = BloodCanvas.new()
	canvas.seq = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	flash = ColorRect.new()
	flash.color = Color(0.7, 0, 0, 0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	black = ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)

	Sfx.play(player, "kill_screech_bat" if is_bat else "kill_roar_eco", 3.0)
	Sfx.play(player, "player_scream", -3.0)
	flash.color.a = 0.75


func _add_splat(big := false) -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := Splat.new()
	s.pos = Vector2(rng.randf_range(0.1, 0.9) * vs.x, rng.randf_range(0.05, 0.75) * vs.y)
	s.radius = rng.randf_range(40.0, 80.0) * (1.8 if big else 1.0)
	s.born = t
	s.drip = rng.randf_range(80.0, 260.0)
	for i in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		s.sats.append([Vector2(cos(a), sin(a)) * rng.randf_range(s.radius * 0.9, s.radius * 2.0), rng.randf_range(6.0, s.radius * 0.35)])
	splats.append(s)


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	_creature_anim()
	_camera_anim()

	# mordidas
	if t >= next_bite and t < 3.6:
		bite_n += 1
		next_bite = t + rng.randf_range(0.34, 0.5)
		Sfx.play(player, "bite_crunch_%d" % rng.randi_range(1, 3), 2.0)
		_add_splat(bite_n % 3 == 0)
		flash.color.a = 0.35
		blood.restart()
		blood.emitting = true
	if t >= 2.5 and not did_tear:
		did_tear = true
		Sfx.play(player, "flesh_tear", 3.0)
		_add_splat(true)
	if t >= 3.0 and not did_gurgle:
		did_gurgle = true
		Sfx.play(player, "gurgle", 1.0)
	if t > 3.6:
		blood.emitting = false

	flash.color.a = maxf(0.0, flash.color.a - delta * 2.2)
	vignette.modulate.a = clampf(t / 2.5, 0.0, 1.0)
	canvas.queue_redraw()

	if t > 4.1:
		black.color.a = clampf((t - 4.1) / 0.9, 0.0, 1.0)
	if t >= TOTAL:
		done = true
		finished.emit()
		var tw := create_tween()
		tw.tween_property(black, "color:a", 0.0, 0.6)
		tw.tween_callback(queue_free)


func _creature_anim() -> void:
	if not is_instance_valid(creature):
		return
	var pf := Vector3(player.global_position.x, creature.global_position.y, player.global_position.z)
	var fwd := (pf - creature.global_position)
	fwd.y = 0.0
	fwd = fwd.normalized()
	# la criatura se acerca y cabecea hacia la cámara con cada mordida
	var phase := fmod(t * 2.4, 1.0)
	var chomp := absf(sin(phase * PI))
	var lunge := clampf(t / 0.25, 0.0, 1.0)
	var base := (1.0 if is_bat else 0.95) - 0.35 * lunge - 0.18 * chomp
	var dirp := (creature.global_position - player.global_position)
	dirp.y = 0.0
	dirp = dirp.normalized()
	creature.global_position = Vector3(player.global_position.x + dirp.x * base, creature.global_position.y, player.global_position.z + dirp.z * base)
	if not creature.has_method("_rig_pose"):
		return
	var open_jaw := chomp
	if is_bat:
		creature._rig_pose("head", Vector3(-0.5 + 0.9 * open_jaw, 0, 0), 0.5)
		creature._rig_pose("chest", Vector3(0.35 * open_jaw, 0, 0), 0.4)
		for s in [1.0, -1.0]:
			var sfx := "r" if s > 0 else "l"
			creature._rig_pose("arm_" + sfx, Vector3(-1.2, 0, s * 0.3), 0.3)
			creature._rig_pose("forearm_" + sfx, Vector3(-0.6, 0, 0), 0.3)
			var flap := sin(t * 18.0) * 0.18
			creature._rig_pose("wing_u_" + sfx, Vector3(0, 0, s * (0.3 + flap)), 0.5)
			creature._rig_pose("wing_o_" + sfx, Vector3(0, 0, -s * (0.2 + flap)), 0.5)
	else:
		creature._rig_pose("head", Vector3(-0.4 + 0.8 * open_jaw, 0, 0), 0.5)
		creature._rig_pose("chest", Vector3(-0.3 + 0.2 * open_jaw, 0, 0), 0.4)
		for sfx in ["r", "l"]:
			creature._rig_pose("fu_" + sfx, Vector3(-0.9 + 0.3 * chomp, 0, 0), 0.3)
			creature._rig_pose("fl_" + sfx, Vector3(-0.4, 0, 0), 0.3)


func _camera_anim() -> void:
	var h: Node3D = player.head
	# 0–2.2 s: sacudidas; después lo arrastran al suelo
	var drag := clampf((t - 2.0) / 1.6, 0.0, 1.0)
	drag = drag * drag * (3.0 - 2.0 * drag)
	var shake := (1.0 - drag * 0.6) * 0.06
	var chomp := absf(sin(fmod(t * 2.4, 1.0) * PI))
	h.position.y = lerpf(head_base_y, 0.28, drag)
	var cpos := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * shake * (0.4 + chomp)
	cam.position = cam_base + cpos
	var target_pitch := (0.1 if is_bat else -0.25)
	h.rotation.x = lerpf(target_pitch, 1.1, drag) + chomp * 0.08
	h.rotation.z = lerpf(0.0, 0.9, drag) + sin(t * 9.0) * 0.03 * (1.0 - drag)
