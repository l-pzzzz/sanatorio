extends Node
## Escucha el micrófono y avisa a las criaturas cuando haces ruido (autoload "NoiseManager").
## También reparte los ruidos del juego (pasos, puertas, botellas...) con emit_noise().
##
## Ajustes del micrófono (pantalla MICRÓFONO del menú principal, en user://settings.cfg):
##   sensibilidad 0..1  (0.5 = el comportamiento original: margen 8 dB, umbral mínimo -45 dB)
##   activado / desactivado, y qué micrófono usar.
## En red, los ruidos de un cliente se reenvían al anfitrión, que es quien mueve a las criaturas.

signal noise_emitted(noise_position: Vector3, loudness: float)

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_SENSITIVITY := 0.5

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

var sensitivity := DEFAULT_SENSITIVITY
var mic_enabled := true
var heard_at := -100.0            ## Última vez (s) que el micrófono superó el umbral
var microphone: AudioStreamPlayer


func _ready() -> void:
	_load_settings()
	calibration_left = calibration_time
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Microphone")
	AudioServer.set_bus_mute(bus, true)
	capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, capture)
	microphone = AudioStreamPlayer.new()
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
		heard_at = Time.get_ticks_msec() / 1000.0
		if not mic_enabled or Net.local_dead:
			return
		var listener := get_tree().get_first_node_in_group("player") as Node3D
		if listener:
			emit_noise(listener.global_position, last_loudness)


func _update_meter() -> void:
	if meter == null:
		return
	if not mic_enabled:
		meter.text = "MIC off"
		return
	var status := "CALIBRATING" if calibration_left > 0.0 else ("HEARD %.0f%%" % (last_loudness * 100.0) if cooldown_left > 0.0 else "quiet")
	meter.text = "MIC %.0f dB / threshold %.0f dB  %s" % [level_db, threshold_db, status]


func emit_noise(noise_position: Vector3, loudness: float) -> void:
	noise_emitted.emit(noise_position, loudness)
	Net.relay_noise(noise_position, loudness)     # cliente en red: también lo oye el anfitrión


## Ruido que llegó de otro jugador por red (no se vuelve a reenviar).
func emit_noise_from_network(noise_position: Vector3, loudness: float) -> void:
	noise_emitted.emit(noise_position, loudness)


# ------------------------------------------------------------------ ajustes

## 0 = solo te oye si gritas, 1 = te oye hasta respirando. 0.5 = valores originales.
func set_sensitivity(value: float) -> void:
	sensitivity = clampf(value, 0.0, 1.0)
	var k := DEFAULT_SENSITIVITY - sensitivity
	margin_db = maxf(1.5, 8.0 + k * 20.0)            # 18 dB (poco sensible) ... 1.5 dB (muy sensible)
	min_threshold_db = -45.0 + k * 40.0              # -25 dB ... -65 dB
	threshold_db = maxf(floor_db + margin_db, min_threshold_db)


func set_mic_enabled(on: bool) -> void:
	mic_enabled = on


func input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func current_device() -> String:
	return AudioServer.input_device


func set_device(device: String) -> void:
	if device == "" or not (device in AudioServer.get_input_device_list()):
		device = "Default"
	AudioServer.input_device = device
	if microphone:
		microphone.stop()
		microphone.play()
	recalibrate()


## Vuelve a medir el ruido de fondo de la habitación.
func recalibrate() -> void:
	calibration_left = calibration_time


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)          # conserva idioma, pantalla completa, nombre...
	config.set_value("mic", "sensitivity", sensitivity)
	config.set_value("mic", "enabled", mic_enabled)
	config.set_value("mic", "device", AudioServer.input_device)
	config.save(CONFIG_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		set_sensitivity(DEFAULT_SENSITIVITY)
		return
	set_sensitivity(float(config.get_value("mic", "sensitivity", DEFAULT_SENSITIVITY)))
	mic_enabled = bool(config.get_value("mic", "enabled", true))
	var device := str(config.get_value("mic", "device", "Default"))
	if device != "Default" and device in AudioServer.get_input_device_list():
		AudioServer.input_device = device
