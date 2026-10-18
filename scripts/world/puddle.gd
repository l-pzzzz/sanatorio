class_name Puddle
extends Area3D
## Charco: pisarlo hace ruido de chapoteo que oye la criatura, incluso agachado
## (agachado suena menos). Rodéalo o cruza muy despacio.

@export var size := Vector2(2.6, 2.6)
@export var walk_loudness := 0.5
@export var crouch_loudness := 0.3
@export var stride := 1.1                 ## Metros por chapoteo

var player: PlayerCharacter
var accum := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.6, size.y)
	shape.shape = box
	shape.position.y = 0.3
	add_child(shape)

	var water := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.01, size.y)
	water.mesh = mesh
	water.position.y = 0.02
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.03, 0.07, 0.06, 0.82)
	material.roughness = 0.05
	material.metallic = 0.2
	material.emission_enabled = true
	material.emission = Color(0.02, 0.06, 0.04)
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerCharacter:
		player = body as PlayerCharacter
		accum = stride          # chapoteo inmediato al entrar


func _on_body_exited(body: Node3D) -> void:
	if body == player:
		player = null


func _physics_process(_delta: float) -> void:
	if player == null or player.is_hidden:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if speed < 0.5:
		return
	accum += speed * get_physics_process_delta_time()
	if accum < stride:
		return
	accum -= stride
	var crouching := speed < 2.2
	if crouching:
		Sfx.play(self, "splash_soft_%d" % randi_range(1, 2), -12.0)
	else:
		Sfx.play(self, "splash_%d" % randi_range(1, 4), -8.0)
	NoiseManager.emit_noise(player.global_position, crouch_loudness if crouching else walk_loudness)
