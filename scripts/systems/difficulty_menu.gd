extends Control
## Menú de dificultad antes de empezar. Flechas o ratón + Enter.

@export_file("*.tscn") var next_scene := "res://scenes/prueba.tscn"

const DESCS := [
	"El murciélago ve menos, es más lento y se rinde pronto. Más dardos, botellas y bengalas. No te persigue a otros pisos.",
	"La experiencia normal. El murciélago te sigue entre pisos tras unos segundos.",
	"Ve desde lejos, corre más y no te olvida. Revisa casilleros. El Eco te huele de cerca. Pocos recursos.",
]

var index := 1
var buttons: Array[Button] = []
var desc: Label
var title: Label
var lang_button: Button


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(620, 0)
	box.position = Vector2(-310, -190)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	title = Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.8, 0.12, 0.1))
	box.add_child(title)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 52)
		b.add_theme_font_size_override("font_size", 24)
		b.mouse_entered.connect(_select.bind(i))
		b.pressed.connect(_confirm.bind(i))
		box.add_child(b)
		buttons.append(b)
	desc = Label.new()
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(620, 90)
	desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.75))
	box.add_child(desc)
	lang_button = Button.new()
	lang_button.custom_minimum_size = Vector2(0, 40)
	lang_button.add_theme_font_size_override("font_size", 18)
	lang_button.focus_mode = Control.FOCUS_NONE   # así Enter sigue confirmando la dificultad
	lang_button.pressed.connect(_toggle_language)
	box.add_child(lang_button)
	index = Difficulty.level
	_refresh_texts()
	_select(index)


func _refresh_texts() -> void:
	title.text = Lang.t("ELIGE LA DIFICULTAD")
	for i in buttons.size():
		buttons[i].text = Lang.t(Difficulty.NAMES[i])
	lang_button.text = Lang.t("Idioma: Español") + "   [L]"


func _toggle_language() -> void:
	Lang.toggle()
	_refresh_texts()
	_select(index)


func _select(i: int) -> void:
	index = i
	desc.text = Lang.t(DESCS[i])
	for k in buttons.size():
		buttons[k].modulate = Color(1, 0.45, 0.4) if k == i else Color(1, 1, 1, 0.75)
	buttons[i].grab_focus()


func _confirm(i: int) -> void:
	Difficulty.level = i
	get_tree().change_scene_to_file(next_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_toggle_language()
	elif event.is_action_pressed("ui_down"):
		_select(mini(index + 1, 2))
	elif event.is_action_pressed("ui_up"):
		_select(maxi(index - 1, 0))
	elif event.is_action_pressed("ui_accept"):
		_confirm(index)
