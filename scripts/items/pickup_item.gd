class_name PickupItem
extends Interactable
## Objeto flotante que se recoge con E (llaves, fusibles, linterna).

@export var item_id := "fusible"
@export var amount := 1
@export var spin_speed := 1.4
@export var bob_height := 0.08
@export var bob_speed := 2.0

var model: Node3D
var time := 0.0
var taken := false


func _ready() -> void:
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	time = randf() * TAU
	var color := ItemInfo.color_of(item_id)

	model = Node3D.new()
	model.position.y = 1.0
	add_child(model)
	match item_id:
		"linterna":
			add_box(Vector3(0.07, 0.07, 0.34), Vector3.ZERO, Color(0.35, 0.35, 0.38), 0.0, model)
			add_box(Vector3(0.13, 0.13, 0.08), Vector3(0, 0, -0.2), color, 2.0, model)
		"pistola":
			add_box(Vector3(0.06, 0.16, 0.1), Vector3(0, -0.08, 0.1), Color(0.15, 0.15, 0.17), 0.0, model)
			add_box(Vector3(0.07, 0.09, 0.34), Vector3.ZERO, Color(0.2, 0.22, 0.25), 0.0, model)
			add_box(Vector3(0.08, 0.03, 0.08), Vector3(0, 0.05, -0.15), color, 2.0, model)
		"dardos":
			for i in 3:
				add_box(Vector3(0.025, 0.025, 0.22), Vector3((i - 1) * 0.06, 0, 0), color, 1.6, model)
				add_box(Vector3(0.05, 0.05, 0.04), Vector3((i - 1) * 0.06, 0, 0.12), Color(0.9, 0.2, 0.2), 0.0, model)
		"botella":
			add_box(Vector3(0.11, 0.2, 0.11), Vector3(0, -0.05, 0), color, 0.8, model)
			add_box(Vector3(0.05, 0.14, 0.05), Vector3(0, 0.12, 0), color, 0.8, model)
		"bengala":
			add_box(Vector3(0.05, 0.05, 0.3), Vector3.ZERO, color, 1.2, model)
			add_box(Vector3(0.06, 0.06, 0.05), Vector3(0, 0, -0.17), Color(1.0, 0.9, 0.7), 3.0, model)
		"fusible_ascensor":
			add_box(Vector3(0.14, 0.14, 0.34), Vector3.ZERO, color, 2.2, model)
			add_box(Vector3(0.17, 0.17, 0.06), Vector3(0, 0, -0.18), Color(0.7, 0.7, 0.75), 0.0, model)
			add_box(Vector3(0.17, 0.17, 0.06), Vector3(0, 0, 0.18), Color(0.7, 0.7, 0.75), 0.0, model)
		"bidon_combustible":
			add_box(Vector3(0.3, 0.42, 0.22), Vector3.ZERO, Color(0.7, 0.12, 0.08), 0.5, model)
			add_box(Vector3(0.1, 0.06, 0.08), Vector3(-0.07, 0.24, 0), Color(0.15, 0.15, 0.15), 0.0, model)
			add_box(Vector3(0.08, 0.04, 0.08), Vector3(0.08, 0.23, 0), color, 1.8, model)
		"hacha":
			add_box(Vector3(0.05, 0.05, 0.5), Vector3.ZERO, Color(0.35, 0.22, 0.12), 0.0, model)
			add_box(Vector3(0.04, 0.2, 0.2), Vector3(0, 0.08, -0.2), Color(0.55, 0.55, 0.58), 0.4, model)
			add_box(Vector3(0.045, 0.05, 0.1), Vector3(0, 0.0, -0.3), color, 1.2, model)
		"fusible":
			add_box(Vector3(0.1, 0.1, 0.26), Vector3.ZERO, color, 1.8, model)
			add_box(Vector3(0.13, 0.13, 0.05), Vector3(0, 0, -0.14), Color(0.6, 0.6, 0.62), 0.0, model)
			add_box(Vector3(0.13, 0.13, 0.05), Vector3(0, 0, 0.14), Color(0.6, 0.6, 0.62), 0.0, model)
		_:
			# llaves: argolla + cuerpo + dientes
			add_box(Vector3(0.14, 0.14, 0.03), Vector3(0, 0, -0.17), color, 1.8, model)
			add_box(Vector3(0.04, 0.04, 0.3), Vector3.ZERO, color, 1.8, model)
			add_box(Vector3(0.09, 0.04, 0.04), Vector3(0.04, 0, 0.1), color, 1.8, model)

	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.8
	glow.omni_range = 3.5
	glow.position.y = 1.0
	add_child(glow)

	add_collider(Vector3(0.8, 0.9, 0.8), Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	time += delta
	model.rotation.y += spin_speed * delta
	model.position.y = 1.0 + sin(time * bob_speed) * bob_height


func get_prompt(_player: PlayerCharacter) -> String:
	return Lang.t("[E] Recoger: %s") % ItemInfo.display_name(item_id)


func interact(player: PlayerCharacter) -> void:
	if taken:
		return
	taken = true
	if item_id in ["dardos", "botella", "bengala"]:
		amount = maxi(1, roundi(amount * float(Difficulty.get_value("supply_mul"))))
	player.add_item(item_id, amount)
	if item_id == "linterna" and player.is_remote:
		# En red la linterna es de todos: si un compañero la encuentra, tú también recibes una.
		var me := get_tree().get_first_node_in_group("player") as PlayerCharacter
		if me and not me.has_flashlight:
			me.add_item("linterna")
			var mm := mission()
			if mm:
				mm.show_toast(Lang.t("%s encontró linternas para todos. F para encender o apagar.") % Net.player_name(player.net_id), 5.0)
	Sfx.play(self, "pickup")
	if item_id == "linterna":
		toast(Lang.t("Linterna: F para encender o apagar. Cuidado: la luz también te delata."), 5.0)
	elif item_id == "pistola":
		var extra := maxi(1, roundi(2 * float(Difficulty.get_value("supply_mul"))))
		player.add_item("dardos", extra)
		toast(Lang.t("Pistola de dardos: clic izquierdo dispara y ATURDE a la criatura unos segundos. Te dejo %d dardos.") % extra, 6.0)
	elif item_id == "bidon_combustible":
		toast(Lang.t("Bidón de combustible (%d). El incinerador de la sala de la raíz necesita 2.") % player.count_item("bidon_combustible"), 5.0)
	elif item_id == "hacha":
		toast(Lang.t("Hacha oxidada: corta las raíces gruesas (puerta del túnel o del corazón). [E] sobre ellas."), 5.5)
	elif item_id == "botella":
		toast(Lang.t("Botella x%d: [G] la lanzas; el ruido distrae a la criatura.") % amount, 4.5)
	elif item_id == "bengala":
		toast(Lang.t("Bengala: [Q] ciega unos segundos al murciélago que tengas enfrente. El Eco no ve, no le afecta."), 5.5)
	elif item_id == "dardos":
		toast(Lang.t("+%d dardos") % amount, 2.5)
	else:
		toast(Lang.t("Recogiste: %s") % ItemInfo.display_name(item_id), 2.5)
	var mission_manager := mission()
	if mission_manager:
		mission_manager.report("item", item_id)
	queue_free()
