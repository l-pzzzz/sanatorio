extends Node
## Pantalla completa: F11 o Alt+Enter para alternar.
## Se recuerda la elección entre partidas (user://settings.cfg).
## Nota: dentro del editor de Godot 4.4+, si el juego se ejecuta "incrustado" en
## el editor, la pantalla completa no aplica; desactiva "Embed Game" o exporta el juego.

const CONFIG_PATH := "user://settings.cfg"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK and bool(config.get_value("display", "fullscreen", false)):
		_apply(true)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var wants_toggle := key.keycode == KEY_F11 or (key.keycode == KEY_ENTER and key.alt_pressed)
	if wants_toggle:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func toggle_fullscreen() -> void:
	if _embedded_in_editor():
		_notify("Pantalla completa no disponible: el juego está incrustado en el editor.\nDesactiva \"Embed Game\" o exporta el juego (.exe).")
		return
	var enable := not is_fullscreen()
	_apply(enable)
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # conserva otros ajustes si ya existía el archivo
	config.set_value("display", "fullscreen", enable)
	config.save(CONFIG_PATH)


func _apply(enable: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enable else DisplayServer.WINDOW_MODE_WINDOWED)


# Godot 4.4+: si el juego corre dentro del editor, solo admite modo ventana.
func _embedded_in_editor() -> bool:
	return Engine.has_method("is_embedded_in_editor") and bool(Engine.call("is_embedded_in_editor"))


func _notify(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_top = -120.0
	label.offset_left = -420.0
	label.offset_right = 420.0
	layer.add_child(label)
	await get_tree().create_timer(5.0).timeout
	layer.queue_free()
