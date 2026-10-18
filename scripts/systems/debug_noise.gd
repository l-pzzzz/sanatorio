extends Node
## Seguro para la presentación: si el micrófono falla, pulsa V para
## emitir un ruido fuerte en la posición del jugador (igual que la voz).
## Bórralo o desactívalo en la versión final.

@export var key := KEY_V
@export var loudness := 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == key:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			NoiseManager.emit_noise(player.global_position, loudness)
