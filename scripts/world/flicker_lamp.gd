class_name FlickerLamp
extends OmniLight3D
## Lampara de techo moribunda: parpadea y a veces se apaga un instante.
## Cuando MissionManager activa la alarma, pasa a rojo pulsante.

@export var base_energy := 0.5
@export var lamp_range := 7.5          ## Con dos pisos se acorta para que la luz no se cuele por el piso
@export var normal_color := Color(0.78, 0.9, 0.7)
@export var alarm_color := Color(1.0, 0.08, 0.04)
@export var cut_hear_range := 14.0     ## Distancia máxima a la que oyes el corte de esta lámpara (m)

var alarm := false
var blackout := 0.0
var phase := randf() * TAU
var fixture_material: StandardMaterial3D
var player: Node3D


func _ready() -> void:
	add_to_group("lamps")
	omni_range = lamp_range
	shadow_enabled = false
	light_color = normal_color
	player = get_tree().get_first_node_in_group("player") as Node3D

	fixture_material = StandardMaterial3D.new()
	fixture_material.albedo_color = Color(0.12, 0.12, 0.12)
	fixture_material.emission_enabled = true
	fixture_material.emission = normal_color
	var fixture := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.06, 0.25)
	fixture.mesh = box
	fixture.position = Vector3(0, 0.3, 0)
	fixture.material_override = fixture_material
	add_child(fixture)


func set_alarm(on: bool) -> void:
	alarm = on
	light_color = alarm_color if on else normal_color
	fixture_material.emission = light_color


## Sonido del corte: solo si la lámpara está cerca de ti y más bajo cuanto más lejos.
func _play_cut_sound() -> void:
	if player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > cut_hear_range:
		return
	Sfx.play(self, "lamp_cut", -8.0 - dist * 1.2)


func _process(delta: float) -> void:
	var energy := base_energy
	if alarm:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.007 + phase)
		energy = base_energy * (0.4 + 2.4 * pulse)
	else:
		blackout -= delta
		if blackout > 0.0:
			energy = 0.0
		else:
			if randf() < 0.12 * delta:
				blackout = randf_range(0.05, 0.35)
				_play_cut_sound()
			energy = base_energy * randf_range(0.8, 1.0)
	light_energy = energy
	fixture_material.emission_energy_multiplier = energy * 3.0
