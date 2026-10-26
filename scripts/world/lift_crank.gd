class_name LiftCrank
extends Interactable
## Manivela del ascensor de madera. ON_BOARD va sobre la plataforma (sube o baja según dónde esté);
## CALL_TOP / CALL_BOTTOM llaman a la plataforma desde arriba o desde abajo.

const ON_BOARD := 0
const CALL_TOP := 1
const CALL_BOTTOM := 2

var lift: WoodLift
var mode := ON_BOARD
var handle: Node3D


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	add_box(Vector3(0.14, 1.0, 0.14), Vector3(0, 0.5, 0), Color(0.3, 0.2, 0.13))
	add_box(Vector3(0.5, 0.1, 0.1), Vector3(0, 1.0, 0), Color(0.3, 0.2, 0.13))
	handle = Node3D.new()
	handle.position = Vector3(0, 1.0, 0.16)
	add_child(handle)
	add_box(Vector3(0.05, 0.45, 0.05), Vector3(0, 0.2, 0), Color(0.45, 0.12, 0.08), 0.0, handle)
	add_box(Vector3(0.18, 0.06, 0.06), Vector3(0, 0.43, 0), Color(0.55, 0.3, 0.1), 0.6, handle)
	add_collider(Vector3(0.9, 1.4, 0.7), Vector3(0, 0.7, 0))


func get_prompt(_player: PlayerCharacter) -> String:
	if lift == null or lift.moving:
		return ""
	match mode:
		ON_BOARD:
			return Lang.t("[E] Girar la manivela: SUBIR") if lift.at_bottom else Lang.t("[E] Girar la manivela: BAJAR")
		CALL_TOP:
			return "" if not lift.at_bottom else Lang.t("[E] Llamar al ascensor")
		_:
			return "" if lift.at_bottom else Lang.t("[E] Llamar al ascensor")


func interact(_player: PlayerCharacter) -> void:
	if lift == null or lift.moving:
		return
	var tw := create_tween()
	tw.tween_property(handle, "rotation:z", TAU * 2.0, 0.7)
	tw.tween_callback(func() -> void: handle.rotation.z = 0.0)
	match mode:
		ON_BOARD:
			lift.go_to(not lift.at_bottom)
		CALL_TOP:
			lift.go_to(false)
		_:
			lift.go_to(true)
	var mm := mission()
	if mm and mode == ON_BOARD and not lift.at_bottom and not Net.replaying:
		mm.show_toast(Lang.t("El ascensor chirría y baja... todo lo que se acerca lo oye."), 4.0)
