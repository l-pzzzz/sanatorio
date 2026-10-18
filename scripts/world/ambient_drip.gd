class_name AmbientDrip
extends Node3D
## Gotera de techo: una gota cada pocos segundos. Es el sonido que El Eco imita.

@export var min_interval := 3.0
@export var max_interval := 9.0

var audio: AudioStreamPlayer3D
var timer := 0.0


func _ready() -> void:
	var path := "res://assets/audio/drip.wav"
	if not ResourceLoader.exists(path):
		set_process(false)
		return
	audio = AudioStreamPlayer3D.new()
	audio.stream = load(path)
	audio.volume_db = -8.0
	audio.unit_size = 6.0
	audio.max_distance = 40.0
	add_child(audio)
	timer = randf_range(0.0, max_interval)


func _process(delta: float) -> void:
	timer -= delta
	if timer > 0.0:
		return
	timer = randf_range(min_interval, max_interval)
	audio.pitch_scale = randf_range(0.9, 1.15)
	audio.play()
