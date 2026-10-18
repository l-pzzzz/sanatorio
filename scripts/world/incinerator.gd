class_name Incinerator
extends Interactable
## Final B: el incinerador de la sala de la raíz. Necesita energía y 2 bidones.
## Al encenderlo carga unos segundos (el ruido atrae a las dos criaturas) y luego quema todo.

@export var bidons_needed := 2
@export var needs_power := true
@export var needs_heart := false      ## Nivel 3: antes hay que destruir el corazón de la raíz
@export var charge_time := 25.0

var charging := false
var left := 0.0
var noise_t := 0.0
var last_count := -1
var light: OmniLight3D
var glow_mat: StandardMaterial3D
var fire_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_box(Vector3(2.2, 2.2, 2.2), Vector3(0, 1.1, 0), Color(0.12, 0.12, 0.13))
	add_box(Vector3(2.3, 0.2, 2.3), Vector3(0, 2.3, 0), Color(0.2, 0.2, 0.22))
	add_box(Vector3(0.7, 1.6, 0.7), Vector3(0.6, 3.0, 0.6), Color(0.15, 0.13, 0.12))
	var door := add_box(Vector3(1.1, 0.9, 0.06), Vector3(0, 0.9, 1.12), Color(0.5, 0.08, 0.04), 0.3)
	glow_mat = door.material_override as StandardMaterial3D
	add_box(Vector3(0.5, 0.18, 0.06), Vector3(0, 1.75, 1.12), Color(1.0, 0.1, 0.08), 1.5)
	add_collider(Vector3(2.2, 2.4, 2.2), Vector3(0, 1.2, 0))
	light = OmniLight3D.new()
	light.position = Vector3(0, 1.2, 2.2)
	light.light_color = Color(1.0, 0.35, 0.12)
	light.light_energy = 0.5
	light.omni_range = 6.0
	add_child(light)


func get_prompt(player: PlayerCharacter) -> String:
	if charging:
		return ""
	var mm := mission()
	if needs_power and mm and not mm.power_on:
		return "Incinerador (sin energía)"
	if needs_heart and mm and not mm.heart_destroyed:
		return "Incinerador: la raíz sigue viva (destruye su corazón)"
	var have := player.count_item("bidon_combustible")
	if have < bidons_needed:
		return "Incinerador: faltan bidones (%d/%d)" % [have, bidons_needed]
	return "[E] ENCENDER el incinerador (quemarlo todo)"


func interact(player: PlayerCharacter) -> void:
	if charging:
		return
	var mm := mission()
	if needs_power and mm and not mm.power_on:
		toast("El incinerador no tiene energía. Instala primero los fusibles en el generador.", 4.0)
		Sfx.play(self, "locked")
		return
	if needs_heart and mm and not mm.heart_destroyed:
		toast("Las raíces son demasiado fuertes: el fuego no prende. Baja por el túnel del centro y destruye el CORAZÓN a hachazos.", 5.0)
		Sfx.play(self, "locked")
		return
	var have := player.count_item("bidon_combustible")
	if have < bidons_needed:
		toast("Necesita %d bidones de combustible (llevas %d). Hay uno en las esporas (norte) y otro en las raíces del sur." % [bidons_needed, have], 4.5)
		Sfx.play(self, "locked")
		return
	player.remove_item("bidon_combustible", bidons_needed)
	charging = true
	left = charge_time
	Sfx.play(self, "power_on", 0.0)
	Sfx.play(self, "alarm", -6.0)
	NoiseManager.emit_noise(global_position, 1.8)
	toast("¡Incinerador encendido! Aguanta %d segundos: el ruido atrae a las dos criaturas. Cuando prenda, el fuego se propaga: ¡tendrás que salir por el túnel del noreste!" % int(charge_time), 6.0)


func _process(delta: float) -> void:
	if not charging:
		return
	left -= delta
	var k := 1.0 - clampf(left / charge_time, 0.0, 1.0)
	light.light_energy = 0.8 + 3.5 * k + randf() * 0.6
	glow_mat.emission_energy_multiplier = 0.5 + 5.0 * k
	glow_mat.emission = Color(1.0, 0.4, 0.1)
	noise_t -= delta
	if noise_t <= 0.0:
		noise_t = 3.0
		NoiseManager.emit_noise(global_position, 1.8)
	var secs := ceili(left)
	if secs != last_count and secs >= 0 and secs % 5 == 0:
		last_count = secs
		toast("Incinerador: %d s…" % secs, 2.0)
	if left <= 0.0:
		charging = false
		var mm := mission()
		if mm:
			mm.report("burn_start" if needs_heart else "burn", "")
