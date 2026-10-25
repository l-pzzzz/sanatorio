class_name Sfx
extends RefCounted
## Reproduce un efecto de sonido de una sola vez desde res://assets/audio/.
## Si el archivo no existe, no hace nada (el juego no se rompe).


static func play(from: Node, sound: String, volume_db := -8.0) -> void:
	if Net.replaying and sound == "locked":
		return      # que no suene la cerradura en todas las PCs cuando un compañero no tiene la llave
	if Net.should_relay_sfx(from):
		Net.relay_sfx(sound, volume_db)    # sonidos de las criaturas del anfitrión: también a los demás
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	player.volume_db = volume_db
	from.get_tree().root.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
