class_name FungusGlow
extends Node3D
## Colonia de hongos que brilla en verde: da algo de luz sin linterna.
## Local +Z mira hacia el interior de la sala (como los demás objetos de pared).

@export var base_energy := 0.7

var light: OmniLight3D
var phase := randf() * TAU


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.8, 0.32)
	material.emission_enabled = true
	material.emission = Color(0.3, 0.95, 0.3)
	material.emission_energy_multiplier = 1.6
	for i in 10:
		var blob := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var radius := randf_range(0.05, 0.17)
		sphere.radius = radius
		sphere.height = radius * 1.4
		sphere.radial_segments = 6
		sphere.rings = 3
		blob.mesh = sphere
		blob.material_override = material
		blob.position = Vector3(randf_range(-0.45, 0.45), randf_range(0.15, 1.6), randf_range(0.0, 0.12))
		add_child(blob)
	light = OmniLight3D.new()
	light.light_color = Color(0.3, 0.95, 0.35)
	light.omni_range = 6.0
	light.light_energy = base_energy
	light.position = Vector3(0.0, 1.0, 0.5)
	add_child(light)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	light.light_energy = base_energy * (0.8 + 0.2 * sin(t * 0.9 + phase))
