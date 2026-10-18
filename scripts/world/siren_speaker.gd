class_name SirenSpeaker
extends Node3D
## Sirena del ala oeste. MissionManager la activa cuando vuelve la energia y
## usa su posicion como origen del ruido que atrae al murcielago.

var light: OmniLight3D
var lens_material: StandardMaterial3D
var audio: AudioStreamPlayer3D
var active := false


func _ready() -> void:
	add_to_group("siren")
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 0.35)
	body.mesh = box
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.2, 0.2, 0.2)
	body.material_override = body_material
	add_child(body)

	lens_material = StandardMaterial3D.new()
	lens_material.albedo_color = Color(0.4, 0.05, 0.05)
	lens_material.emission_enabled = true
	lens_material.emission = Color(1.0, 0.05, 0.02)
	lens_material.emission_energy_multiplier = 0.2
	var lens := MeshInstance3D.new()
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.3, 0.12, 0.3)
	lens.mesh = lens_mesh
	lens.position = Vector3(0, -0.2, 0)
	lens.material_override = lens_material
	add_child(lens)

	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.1, 0.05)
	light.light_energy = 0.0
	light.omni_range = 9.0
	light.position = Vector3(0, -0.4, 0)
	add_child(light)

	var path := "res://assets/audio/alarm.wav"
	if ResourceLoader.exists(path):
		audio = AudioStreamPlayer3D.new()
		audio.stream = load(path)
		audio.volume_db = -6.0
		audio.unit_size = 10.0
		audio.max_distance = 80.0
		audio.finished.connect(audio.play)
		add_child(audio)


func activate() -> void:
	active = true
	if audio:
		audio.play()


func _process(_delta: float) -> void:
	if not active:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	light.light_energy = 0.5 + 2.5 * pulse
	lens_material.emission_energy_multiplier = 0.5 + 3.0 * pulse
