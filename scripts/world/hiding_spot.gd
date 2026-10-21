class_name HidingSpot
extends Interactable
## Escondite donde el jugador puede meterse (E para entrar y para salir):
## "locker" = casillero de hospital, "barrel" = tanque de aceite vacío.
## Mientras estás dentro el murciélago no te ve y El Eco solo te encuentra si
## hace falta ruido tuyo. Tampoco te ve nadie si no te vio entrar.

const WIDTH := 0.9
const DEPTH := 0.55
const HEIGHT := 1.9

@export var kind := "locker"

var depth := DEPTH
var details: Array[Node3D] = []   ## Rendijas y manija: se ocultan cuando estás adentro


func _ready() -> void:
	collision_layer = LAYER_SOLID | LAYER_INTERACT
	collision_mask = 0
	if kind == "barrel":
		_build_barrel()
	else:
		_build_locker()


func _build_locker() -> void:
	add_box(Vector3(WIDTH, HEIGHT, DEPTH), Vector3(0, HEIGHT / 2.0, 0), Color(0.2, 0.27, 0.27))
	for i in 5:   # rendijas de ventilación en la puerta
		details.append(add_box(Vector3(0.6, 0.025, 0.02), Vector3(0, 1.45 + i * 0.07, DEPTH / 2.0 + 0.005), Color(0.02, 0.02, 0.02)))
	details.append(add_box(Vector3(0.04, 0.4, 0.03), Vector3(0.3, 0.95, DEPTH / 2.0 + 0.01), Color(0.06, 0.06, 0.06)))
	add_collider(Vector3(WIDTH, HEIGHT, DEPTH), Vector3(0, HEIGHT / 2.0, 0))


func _build_barrel() -> void:
	depth = 1.1
	var body_color := Color(0.2, 0.22, 0.17)
	_add_drum(0.52, 1.5, Vector3(0, 0.75, 0), body_color)
	_add_drum(0.55, 0.07, Vector3(0, 0.35, 0), Color(0.12, 0.12, 0.1))
	_add_drum(0.55, 0.07, Vector3(0, 1.15, 0), Color(0.12, 0.12, 0.1))
	add_box(Vector3(0.5, 0.75, 0.04), Vector3(0, 0.75, 0.5), Color(0.04, 0.04, 0.04))   # escotilla
	add_collider(Vector3(1.05, 1.5, 1.05), Vector3(0, 0.75, 0))


func _add_drum(radius: float, height: float, pos: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	instance.mesh = mesh
	instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	instance.material_override = material
	add_child(instance)


func _spot_name() -> String:
	return Lang.t("el tanque") if kind == "barrel" else Lang.t("el casillero")


func get_prompt(player: PlayerCharacter) -> String:
	if player.hidden_in == self:
		return Lang.t("[E] Salir de %s") % _spot_name()
	return Lang.t("[E] Esconderte en %s") % _spot_name()


func interact(player: PlayerCharacter) -> void:
	if player.hidden_in == self:
		player.leave_hiding()
	else:
		player.enter_hiding(self)


## Dónde se coloca el jugador al esconderse (centro del escondite, a nivel del piso).
func hide_position() -> Vector3:
	return global_position


## Dónde aparece el jugador al salir (delante de la puerta).
func exit_position() -> Vector3:
	return global_position + global_transform.basis.z * (depth / 2.0 + 0.7)


## Giro del jugador para mirar hacia afuera por la puerta.
func facing_yaw() -> float:
	return global_rotation.y + PI


## Lo llama el jugador al entrar o salir: oculta los detalles de la puerta que estorban la vista.
func set_inside(inside: bool) -> void:
	for detail in details:
		detail.visible = not inside
