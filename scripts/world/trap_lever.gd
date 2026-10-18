class_name TrapLever
extends Interactable
## Palanca que activa una zona trampa (TrapZone) unos segundos.
## Después tarda `cooldown` segundos en poder usarse otra vez.

@export var cooldown := 25.0
@export var active_time := 8.0
@export var stun_time := 9.0

var zone: Node3D
var ready_at := 0.0
var arm_pivot: Node3D
var light_material: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	add_box(Vector3(0.5, 0.8, 0.12), Vector3(0, 1.3, 0.06), Color(0.16, 0.17, 0.18))
	light_material = StandardMaterial3D.new()
	light_material.albedo_color = Color(0.1, 1.0, 0.3)
	light_material.emission_enabled = true
	light_material.emission = Color(0.1, 1.0, 0.3)
	light_material.emission_energy_multiplier = 2.0
	var lamp := add_box(Vector3(0.1, 0.1, 0.04), Vector3(0, 1.58, 0.14), Color.WHITE)
	lamp.material_override = light_material
	arm_pivot = Node3D.new()
	arm_pivot.position = Vector3(0, 1.2, 0.14)
	arm_pivot.rotation.x = deg_to_rad(-35.0)
	add_child(arm_pivot)
	add_box(Vector3(0.06, 0.4, 0.06), Vector3(0, 0.2, 0), Color(0.7, 0.7, 0.72), 0.0, arm_pivot)
	add_box(Vector3(0.14, 0.12, 0.14), Vector3(0, 0.42, 0), Color(0.9, 0.15, 0.1), 0.6, arm_pivot)
	add_collider(Vector3(0.7, 1.0, 0.6), Vector3(0, 1.3, 0.2))


func _left() -> float:
	return ready_at - Time.get_ticks_msec() / 1000.0


func get_prompt(_player: PlayerCharacter) -> String:
	if _left() > 0.0:
		return "Palanca de trampa (se recarga: %d s)" % ceili(_left())
	return "[E] Accionar palanca (activa una trampa cercana)"


func interact(_player: PlayerCharacter) -> void:
	if _left() > 0.0:
		toast("La palanca todavía se está recargando.", 2.0)
		return
	if zone == null:
		toast("La palanca no responde (no tiene trampa conectada).", 2.5)
		return
	ready_at = Time.get_ticks_msec() / 1000.0 + cooldown
	Sfx.play(self, "lever_clunk")
	NoiseManager.emit_noise(global_position, 0.35)
	zone.call("arm", active_time, stun_time)
	toast("¡Trampa activada! Cualquier criatura que pise la zona de franjas quedará aturdida.", 4.0)
	var tween := create_tween()
	tween.tween_property(arm_pivot, "rotation:x", deg_to_rad(35.0), 0.25)
	light_material.albedo_color = Color(1.0, 0.1, 0.05)
	light_material.emission = Color(1.0, 0.1, 0.05)
	tween.tween_interval(cooldown)
	tween.tween_callback(_recharged)
	var mm := mission()
	if mm:
		mm.report("lever", name)


func _recharged() -> void:
	light_material.albedo_color = Color(0.1, 1.0, 0.3)
	light_material.emission = Color(0.1, 1.0, 0.3)
	var tween := create_tween()
	tween.tween_property(arm_pivot, "rotation:x", deg_to_rad(-35.0), 0.25)
