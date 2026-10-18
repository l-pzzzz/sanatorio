class_name PowerGenerator
extends Interactable
## Generador de la sala de maquinas. Hay que instalarle los fusibles.

@export var fuses_needed := 3

var inserted := 0
var running := false
var indicators: Array[StandardMaterial3D] = []


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_box(Vector3(1.8, 1.4, 0.9), Vector3(0, 0.7, 0), Color(0.16, 0.18, 0.17))
	add_box(Vector3(1.6, 0.12, 0.7), Vector3(0, 1.46, 0), Color(0.3, 0.3, 0.28))
	add_box(Vector3(1.3, 0.5, 0.04), Vector3(0, 0.9, 0.46), Color(0.07, 0.07, 0.08))
	for i in fuses_needed:
		var x := (i - (fuses_needed - 1) / 2.0) * 0.45
		var lamp := add_box(Vector3(0.22, 0.22, 0.05), Vector3(x, 0.9, 0.49), Color(1.0, 0.1, 0.08), 1.5)
		indicators.append(lamp.material_override as StandardMaterial3D)
	add_collider(Vector3(1.8, 1.5, 0.9), Vector3(0, 0.75, 0))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.4, 1.0)
	light.light_color = Color(1.0, 0.3, 0.2)
	light.light_energy = 0.7
	light.omni_range = 4.0
	add_child(light)


func _update_indicators() -> void:
	for i in indicators.size():
		var color := Color(0.2, 1.0, 0.3) if i < inserted else Color(1.0, 0.1, 0.08)
		indicators[i].albedo_color = color
		indicators[i].emission = color


func get_prompt(_player: PlayerCharacter) -> String:
	if running:
		return ""
	return "[E] Instalar fusibles (%d/%d)" % [inserted, fuses_needed]


func interact(player: PlayerCharacter) -> void:
	if running:
		return
	var have := player.count_item("fusible")
	if have <= 0:
		toast("El generador necesita %d fusibles. Instalados: %d/%d." % [fuses_needed, inserted, fuses_needed], 4.0)
		return
	var amount := mini(have, fuses_needed - inserted)
	player.remove_item("fusible", amount)
	inserted += amount
	_update_indicators()
	Sfx.play(self, "pickup")
	NoiseManager.emit_noise(global_position, 0.4)
	if inserted >= fuses_needed:
		running = true
		Sfx.play(self, "power_on", -4.0)
		var mm := mission()
		if mm:
			mm.report("power", "")
	else:
		toast("Fusibles instalados: %d/%d. Faltan %d." % [inserted, fuses_needed, fuses_needed - inserted], 3.5)
