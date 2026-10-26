extends Node
## Escucha el micrófono y avisa a las criaturas cuando haces ruido (autoload "NoiseManager").
## También reparte los ruidos del juego (pasos, puertas, botellas...) con emit_noise().
##
## Ajustes del micrófono (pantalla MICRÓFONO del menú principal, en user://settings.cfg):
##   sensibilidad 0..1  (0.5 = el comportamiento original: margen 8 dB, umbral mínimo -45 dB)
##   activado / desactivado, y qué micrófono usar.
##   MODO AMBIENTE RUIDOSO (ferias, aulas llenas): exige más margen sobre el ruido de fondo, que la voz
##   dure unos instantes y trata un ruido que no para como ambiente (sube el "suelo") en vez de voz.
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
var noisy_mode := false           ## Modo ambiente ruidoso (feria)
var ui_open := false              ## Con un panel de ajustes abierto el micrófono no alerta a nadie
var above_time := 0.0             ## Cuánto lleva seguido el sonido por encima del umbral
var _calib_samples := PackedFloat32Array()


func _ready() -> void:
	_load_settings()
	recalibrate()
	_request_android_permission()
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


## Umbral para un nivel de ruido de fondo dado (en modo ruidoso pide 4 dB más de margen).
func _threshold_for(floor_level: float) -> float:
	return maxf(floor_level + margin_db + (4.0 if noisy_mode else 0.0), min_threshold_db)


func _percentile(samples: PackedFloat32Array, p: float) -> float:
	if samples.is_empty():
		return -80.0
	var sorted := samples.duplicate()
	sorted.sort()
	return sorted[clampi(int(p * float(sorted.size() - 1)), 0, sorted.size() - 1)]


func _update_floor(delta: float) -> void:
	if calibration_left > 0.0:
		calibration_left -= delta
		_calib_samples.append(level_db)
		floor_db = level_db
		threshold_db = _threshold_for(floor_db)
		if calibration_left <= 0.0:
			if noisy_mode:
				# Con ruido de feria el último instante puede ser un hueco: se usa el percentil 90.
				floor_db = _percentile(_calib_samples, 0.9)
				threshold_db = _threshold_for(floor_db)
			_calib_samples = PackedFloat32Array()
		return
	threshold_db = _threshold_for(floor_db)
	if level_db < floor_db:
		floor_db = level_db
		above_time = 0.0
	elif level_db < threshold_db:
		floor_db = move_toward(floor_db, level_db, floor_adapt_per_second * (4.0 if noisy_mode else 1.0) * delta)
		above_time = 0.0
	else:
		above_time += delta
		if noisy_mode and above_time > 1.5:
			floor_db += 3.0 * delta      # un ruido que no para es ambiente, no voz
		if cooldown_left > 0.0 or above_time < (0.18 if noisy_mode else 0.0):
			return
		cooldown_left = cooldown * (1.7 if noisy_mode else 1.0)
		last_loudness = clampf((level_db - threshold_db) / loudness_range_db, 0.0, 1.0)
		heard_at = Time.get_ticks_msec() / 1000.0
		if not mic_enabled or Net.local_dead or ui_open:
			return
		var listener := get_tree().get_first_node_in_group("player") as Node3D
		if listener:
			emit_noise(listener.global_position, last_loudness)


## En Android el micrófono se pide en tiempo de ejecución. Cuando el jugador acepta se reinicia la captura.
func _request_android_permission() -> void:
	if OS.get_name() != "Android":
		return
	if "RECORD_AUDIO" in OS.get_granted_permissions():
		return
	get_tree().on_request_permissions_result.connect(_on_permission_result)
	OS.request_permission("RECORD_AUDIO")


func _on_permission_result(permission: String, granted: bool) -> void:
	if permission.ends_with("RECORD_AUDIO") and granted and microphone:
		microphone.stop()
		microphone.play()
		recalibrate()


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


## Ruido de un objeto del mundo que TODOS los jugadores repiten (válvulas, ascensores, puertas...).
## En red solo lo emite el anfitrión: sus criaturas son las únicas que oyen y así no se duplica.
func emit_world_noise(noise_position: Vector3, loudness: float) -> void:
	if Net.is_client() and Net.in_game:
		return
	noise_emitted.emit(noise_position, loudness)


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


func set_noisy_mode(on: bool) -> void:
	noisy_mode = on
	recalibrate()


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
	calibration_left = calibration_time * (2.0 if noisy_mode else 1.0)
	_calib_samples = PackedFloat32Array()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)          # conserva idioma, pantalla completa, nombre...
	config.set_value("mic", "sensitivity", sensitivity)
	config.set_value("mic", "enabled", mic_enabled)
	config.set_value("mic", "noisy_mode", noisy_mode)
	config.set_value("mic", "device", AudioServer.input_device)
	config.save(CONFIG_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		set_sensitivity(DEFAULT_SENSITIVITY)
		return
	set_sensitivity(float(config.get_value("mic", "sensitivity", DEFAULT_SENSITIVITY)))
	mic_enabled = bool(config.get_value("mic", "enabled", true))
	noisy_mode = bool(config.get_value("mic", "noisy_mode", false))
	var device := str(config.get_value("mic", "device", "Default"))
	if device != "Default" and device in AudioServer.get_input_device_list():
		AudioServer.input_device = device
