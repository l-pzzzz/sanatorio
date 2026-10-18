class_name TrapZone
extends Node3D
## Zona trampa de una celda. Una palanca (TrapLever) la activa unos segundos:
## si una criatura está dentro (o entra mientras está activa) queda aturdida.
## A ti nunca te afecta. Se ve en el piso como franjas amarillas.

@export var size := Vector3(3.4, 2.6, 3.4)

var active := false
var left := 0.0
var stun_time := 9.0
var hit := {}                 # criaturas ya aturdidas en esta activación
var bars: Array[MeshInstance3D] = []
var bar_material: StandardMaterial3D
var zap_light: OmniLight3D
var nozzle_material: StandardMaterial3D
var tick := 0.0


func _ready() -> void:
	add_to_group("trap_zones")
	bar_material = StandardMaterial3D.new()
	bar_material.albedo_color = Color(0.9, 0.7, 0.05)
	bar_material.emission_enabled = true
	bar_material.emission = Color(0.9, 0.65, 0.05)
	bar_material.emission_energy_multiplier = 0.35
	bar_material.roughness = 1.0
	var span := minf(size.x, size.z)
	for i in 5:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.22, 0.012, span * 1.15)
		bar.mesh = box
		bar.material_override = bar_material
		bar.position = Vector3((i - 2) * span * 0.2, 0.012, 0.0)
		bar.rotation.y = PI / 4.0
		add_child(bar)
		bars.append(bar)
	# Boquilla en el techo
	nozzle_material = StandardMaterial3D.new()
	nozzle_material.albedo_color = Color(0.15, 0.15, 0.17)
	nozzle_material.emission_enabled = true
	nozzle_material.emission = Color(0.2, 0.4, 1.0)
	nozzle_material.emission_energy_multiplier = 0.0
	var nozzle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.3
	cyl.height = 0.3
	nozzle.mesh = cyl
	nozzle.material_override = nozzle_material
	nozzle.position = Vector3(0.0, size.y + 0.15, 0.0)
	add_child(nozzle)
	zap_light = OmniLight3D.new()
	zap_light.light_color = Color(0.35, 0.6, 1.0)
	zap_light.light_energy = 0.0
	zap_light.omni_range = 6.0
	zap_light.position = Vector3(0.0, size.y - 0.3, 0.0)
	add_child(zap_light)


func contains(point: Vector3) -> bool:
	var local := point - global_position
	return absf(local.x) <= size.x / 2.0 and absf(local.z) <= size.z / 2.0 and local.y > -0.6 and local.y < size.y


func arm(duration: float, stun_seconds: float) -> void:
	active = true
	left = duration
	stun_time = stun_seconds
	hit.clear()
	Sfx.play(self, "zap", -6.0)


func _physics_process(delta: float) -> void:
	if not active:
		return
	left -= delta
	tick += delta
	var flicker := 0.6 + 0.4 * sin(tick * 40.0) * sin(tick * 17.0)
	zap_light.light_energy = 3.0 * flicker
	nozzle_material.emission_energy_multiplier = 6.0 * flicker
	bar_material.emission = Color(0.4, 0.7, 1.0)
	bar_material.emission_energy_multiplier = 2.0 * flicker
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var id := enemy.get_instance_id()
		if hit.has(id) or not contains((enemy as Node3D).global_position):
			continue
		hit[id] = true
		if enemy.has_method("stun") and enemy.call("stun", stun_time, "trap", global_position):
			Sfx.play(self, "zap", -2.0)
	if left <= 0.0:
		active = false
		zap_light.light_energy = 0.0
		nozzle_material.emission_energy_multiplier = 0.0
		bar_material.emission = Color(0.9, 0.65, 0.05)
		bar_material.emission_energy_multiplier = 0.35
