class_name PlayerBody
extends Node3D
## Cuerpo completo del jugador en primera persona (modelo y animaciones de Mixamo).
## La cabeza se oculta para que la cámara no quede dentro; al mirar hacia abajo se ven
## el torso, los brazos y las botas. Con la linterna encendida el brazo derecho la sostiene.

signal swing_hit            ## Momento del hachazo en que el golpe "conecta"

const BODY_SCENE := preload("res://assets/player/body.tscn")

@export var back_offset := 0.30        ## Cuánto se retrasa el cuerpo respecto a la cámara (m)
@export var walk_ref_speed := 1.5       ## Velocidad a la que la animación de caminar se ve natural (m/s)
@export var run_ref_speed := 3.6
@export var crouch_ref_speed := 1.1
@export var swing_speed := 1.5
@export var swing_hit_time := 0.55      ## Segundo de la animación en que cae el golpe (antes de aplicar el escalado)

var player: PlayerCharacter
var body: Node3D
var skeleton: Skeleton3D
var anim: AnimationPlayer
var head_mesh: MeshInstance3D
var swinging := false
var current := ""
var axe_prop: Node3D
var light_prop: Node3D
var _hit_emitted := false
var arm_lock: ArmLock
var ready_body := false
var calib_frames := 0
var swing_time := 0.0


## Mantiene el brazo derecho (con la linterna) fijo respecto a la cabeza/cámara mientras el resto del
## cuerpo se mueve con su animación natural: el brazo no se balancea al caminar y el cuerpo no se ve tieso.
class ArmLock extends SkeletonModifier3D:
	var head_idx := -1
	var bones: Array[int] = []
	var rel: Array[Transform3D] = []
	var locked := false

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or not locked or head_idx < 0 or rel.size() != bones.size():
			return
		var head_g: Transform3D = sk.get_bone_global_pose(head_idx)
		for i in bones.size():
			sk.set_bone_global_pose(bones[i], head_g * rel[i])

	func _process_modification_with_delta(_delta: float) -> void:
		_process_modification()


func setup(p: PlayerCharacter) -> void:
	player = p
	position = Vector3(0.0, 0.0, back_offset)
	body = BODY_SCENE.instantiate()
	add_child(body)
	body.rotation.y = PI                       # el modelo mira a +Z, el jugador a -Z
	skeleton = body.get_node("Skeleton3D")
	anim = body.get_node("AnimationPlayer")
	head_mesh = body.get_node("Skeleton3D/head")
	head_mesh.visible = false                  # sin cabeza en primera persona
	anim.animation_finished.connect(_on_finished)
	_make_props()
	_start_calibration()
	ready_body = true
	print("[PlayerBody] listo: huesos=", skeleton.get_bone_count(), " clips=", anim.get_animation_list().size())


# Mide, con la animación de "linterna en la mano", dónde queda el brazo derecho respecto a la cabeza.
# Se hace en _process (sin await) para que un fallo aquí nunca impida que las animaciones se reproduzcan.
func _start_calibration() -> void:
	arm_lock = ArmLock.new()
	skeleton.add_child(arm_lock)
	arm_lock.head_idx = skeleton.find_bone("mixamorig_Head")
	for bone_name in ["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]:
		arm_lock.bones.append(skeleton.find_bone(bone_name))
	anim.play("idle_l")
	anim.seek(0.0, true)
	calib_frames = 3


func _finish_calibration() -> void:
	skeleton.force_update_all_bone_transforms()
	var head_g: Transform3D = skeleton.get_bone_global_pose(arm_lock.head_idx)
	for b in arm_lock.bones:
		arm_lock.rel.append(head_g.affine_inverse() * skeleton.get_bone_global_pose(b))
	current = ""
	anim.play("idle", 0.0)
	current = "idle"


# Linterna en la mano derecha y hacha (solo visible al golpear).
func _make_props() -> void:
	var hand := BoneAttachment3D.new()
	hand.bone_name = "mixamorig_RightHand"
	skeleton.add_child(hand)
	hand.set_use_external_skeleton(false)
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * 0.01           # el esqueleto (con la escala x100 del cuerpo) deja este contenedor en metros
	hand.add_child(holder)

	light_prop = Node3D.new()
	holder.add_child(light_prop)
	light_prop.visible = false
	_prop_cylinder(light_prop, 0.026, 0.15, Vector3(0.0, 0.06, 0.0), Color(0.12, 0.12, 0.13), 0.5, 0.0)
	_prop_cylinder(light_prop, 0.033, 0.045, Vector3(0.0, 0.15, 0.0), Color(0.2, 0.2, 0.22), 0.6, 0.0)
	_prop_cylinder(light_prop, 0.028, 0.01, Vector3(0.0, 0.176, 0.0), Color(1.0, 0.95, 0.8), 0.0, 3.0)

	axe_prop = Node3D.new()
	holder.add_child(axe_prop)
	axe_prop.visible = false
	_prop_box(axe_prop, Vector3(0.04, 0.62, 0.04), Vector3(0.0, 0.14, 0.0), Color(0.33, 0.21, 0.12), 0.0)
	_prop_box(axe_prop, Vector3(0.05, 0.14, 0.2), Vector3(0.0, 0.42, -0.08), Color(0.58, 0.58, 0.62), 0.0)
	_prop_box(axe_prop, Vector3(0.055, 0.1, 0.05), Vector3(0.0, 0.42, 0.0), Color(0.25, 0.25, 0.27), 0.0)


func _prop_cylinder(parent: Node3D, radius: float, length: float, pos: Vector3, color: Color, rough: float, glow: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	mi.mesh = cm
	mi.position = pos                           # el contenedor (holder) ya está en metros
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough if rough > 0.0 else 0.8
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _prop_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, _glow: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mi.material_override = mat
	parent.add_child(mi)


func _process(delta: float) -> void:
	if player == null or not ready_body:
		return
	if calib_frames > 0:
		calib_frames -= 1
		if calib_frames == 0:
			_finish_calibration()
		return
	visible = not player.is_hidden
	if not visible:
		return
	_follow_camera(delta)
	light_prop.visible = player.flashlight_on and not swinging
	arm_lock.locked = player.flashlight_on and not swinging and arm_lock.rel.size() == arm_lock.bones.size()
	if swinging:
		swing_time += delta
		if swing_time > 2.4:      # seguro: si la animación nunca termina, se sale del golpe
			_on_finished(&"slash")
			return
		var t := anim.current_animation_position
		if not _hit_emitted and t >= swing_hit_time:
			_hit_emitted = true
			swing_hit.emit()
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var crouching := player.height < player.stand_height - 0.25
	var clip := "idle"
	var spd := 1.0
	if speed > 0.4 and player.is_on_floor():
		if crouching:
			clip = "crouch_walk"
			spd = clampf(speed / crouch_ref_speed, 0.4, 1.6)
		elif speed > 2.2:
			clip = "run"
			spd = clampf(speed / run_ref_speed, 0.5, 1.5)
		else:
			clip = "walk"
			spd = clampf(speed / walk_ref_speed, 0.4, 1.6)
	elif crouching:
		clip = "crouch_idle"
	if player.flashlight_on:
		clip += "_l"
	anim.speed_scale = spd
	if clip != current:
		_play(clip, 0.22)


# Mantiene la cabeza del modelo siempre justo detrás de la cámara (también agachado, cuando el torso
# se inclina hacia delante): así los hombros no se cruzan en la pantalla y no tapan la vista.
func _follow_camera(delta: float) -> void:
	var head_idx := skeleton.find_bone("mixamorig_Head")
	if head_idx < 0:
		return
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head_idx).origin
	var head_local := player.to_local(head_world)
	var eye_y := player.head.position.y
	var want := Vector3(-head_local.x, clampf(eye_y - 0.1 - head_local.y, -0.12, 0.12), back_offset - head_local.z)
	# Solo se corrige el desfase lento (por ejemplo al agacharse); el vaivén de cada paso NO se compensa,
	# porque si no todo el cuerpo se balancea de lado a lado bajo la cámara.
	var err := want.length()
	var speed := 1.2 if err < 0.1 else 8.0
	position += want * (1.0 - exp(-speed * delta))


func _play(clip: String, blend: float) -> void:
	current = clip
	anim.play(clip, blend)


## Golpe de hacha (mismo gesto para raíces, barreras y el corazón). Devuelve false si ya está golpeando.
func swing_axe() -> bool:
	if swinging:
		return false
	swinging = true
	swing_time = 0.0
	_hit_emitted = false
	axe_prop.visible = true
	light_prop.visible = false
	anim.speed_scale = swing_speed
	current = "slash"
	anim.play("slash", 0.12)
	return true


func _on_finished(anim_name: StringName) -> void:
	if anim_name == &"slash":
		swinging = false
		axe_prop.visible = false
		current = ""
