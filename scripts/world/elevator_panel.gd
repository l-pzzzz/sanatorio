class_name ElevatorPanel
extends Interactable
## Botonera del ascensor. `call_floor` = -1: panel dentro de la cabina (cambia de piso);
## 0 o 1: botón de llamada en ese piso.

var elevator: Elevator
var call_floor := -1


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_box(Vector3(0.45, 1.1, 0.3), Vector3(0, 0.55, 0), Color(0.18, 0.19, 0.2))
	add_box(Vector3(0.3, 0.16, 0.03), Vector3(0, 0.95, 0.16), Color(0.3, 1.0, 0.4), 1.8)
	add_box(Vector3(0.12, 0.12, 0.04), Vector3(0, 0.7, 0.16), Color(1.0, 0.8, 0.2), 1.5)
	add_collider(Vector3(0.6, 1.1, 0.5), Vector3(0, 0.55, 0.05))


func get_prompt(_player: PlayerCharacter) -> String:
	if elevator == null:
		return ""
	if not elevator.powered:
		return Lang.t("[E] Panel del ascensor (sin energía)")
	if elevator.moving:
		return Lang.t("Ascensor en movimiento...")
	return Lang.t("[E] Llamar al ascensor") if call_floor >= 0 else Lang.t("[E] Usar el ascensor")


func interact(player: PlayerCharacter) -> void:
	if elevator:
		elevator.use_panel(player, call_floor)
