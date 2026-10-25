class_name Interactable
extends StaticBody3D
## Base de todo lo que el jugador puede usar con la tecla E.
## El jugador apunta con un RayCast3D que ve las capas 1 y 2.
## Los objetos interactivos viven en la capa 2; los que ademas bloquean el
## paso (puertas, generador) tambien en la capa 1.

const LAYER_SOLID := 1
const LAYER_INTERACT := 2


func get_prompt(_player: PlayerCharacter) -> String:
	return ""


func interact(_player: PlayerCharacter) -> void:
	pass


func mission() -> MissionManager:
	return get_tree().get_first_node_in_group("mission_manager") as MissionManager


func toast(text: String, seconds := 3.0) -> void:
	if Net.replaying:
		return      # acción repetida de otro jugador: el aviso es solo para quien la hizo
	var mm := mission()
	if mm:
		mm.show_toast(text, seconds)


func add_box(size: Vector3, pos: Vector3, color: Color, emission := 0.0, parent: Node = null) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	mesh_instance.material_override = material
	if parent == null:
		parent = self
	parent.add_child(mesh_instance)
	return mesh_instance


func add_collider(size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	add_child(shape)
