extends Node

signal noise_emitted(noise_position: Vector3, loudness: float)

@export var margin_db := 8.0
## Umbral mínimo absoluto (dB). Evita que, con un micrófono en silencio digital,
## el umbral caiga a ~-80 dB y cualquier ruido de fondo alerte al murciélago.
@export var min_threshold_db := -45.0
@export var loudness_range_db := 20.0
@export var calibration_time := 1.5
@export var smoothing := 10.0
@export var floor_adapt_per_second := 1.0
@export var cooldown := 0.3
@export var show_meter := true

var level_db := -80.0
var floor_db := -80.0
var threshold_db := 0.0
var last_loudness := 0.0
var capture: AudioEffectCapture
var cooldown_left := 0.0
var calibration_left := 0.0
var meter: Label


func _ready() -> void:
	calibration_left = calibration_time
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Microphone")
	AudioServer.set_bus_mute(bus, true)
	capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, capture)
	var microphone := AudioStreamPlayer.new()
	microphone.stream = AudioStreamMicrophone.new()
	microphone.bus = "Microphone"
	add_child(microphone)
	microphone.play()
	if show_meter:
		var layer := CanvasLayer.new()
		meter = Label.new()
		meter.position = Vector2(12.0, 12.0)
		layer.add_child(meter)
		add_child(layer)


func _process(delta: float) -> void:
	cooldown_left -= delta
	var frames := capture.get_frames_available()
	if frames > 0:
		var peak := 0.0
		for frame in capture.get_buffer(frames):
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		var instant_db := linear_to_db(peak) if peak > 0.0 else -80.0
		level_db = lerpf(level_db, instant_db, 1.0 - exp(-smoothing * delta))
		_update_floor(delta)
	_update_meter()


func _update_floor(delta: float) -> void:
	if calibration_left > 0.0:
		calibration_left -= delta
		floor_db = level_db
		threshold_db = maxf(floor_db + margin_db, min_threshold_db)
		return
	threshold_db = maxf(floor_db + margin_db, min_threshold_db)
	if level_db < floor_db:
		floor_db = level_db
	elif level_db < threshold_db:
		floor_db = move_toward(floor_db, level_db, floor_adapt_per_second * delta)
	elif cooldown_left <= 0.0:
		cooldown_left = cooldown
		last_loudness = clampf((level_db - threshold_db) / loudness_range_db, 0.0, 1.0)
		var listener := get_tree().get_first_node_in_group("player") as Node3D
		if listener:
			emit_noise(listener.global_position, last_loudness)


func _update_meter() -> void:
	if meter == null:
		return
	var status := "CALIBRATING" if calibration_left > 0.0 else ("HEARD %.0f%%" % (last_loudness * 100.0) if cooldown_left > 0.0 else "quiet")
	meter.text = "MIC %.0f dB / threshold %.0f dB  %s" % [level_db, threshold_db, status]


func emit_noise(noise_position: Vector3, loudness: float) -> void:
	noise_emitted.emit(noise_position, loudness)
