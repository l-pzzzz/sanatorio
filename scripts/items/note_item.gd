class_name NoteItem
extends Interactable
## Nota que cuenta la historia y da pistas. Se lee con E (se puede releer).

@export_multiline var text := ""
@export var read_seconds := 9.0

var model: Node3D
var time := 0.0


func _ready() -> void:
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	time = randf() * TAU
	model = Node3D.new()
	model.position.y = 1.0
	model.rotation.x = 0.35
	add_child(model)
	add_box(Vector3(0.3, 0.02, 0.4), Vector3.ZERO, Color(0.9, 0.86, 0.7), 0.5, model)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.9, 0.9, 0.75)
	glow.light_energy = 0.35
	glow.omni_range = 2.5
	glow.position.y = 1.0
	add_child(glow)
	add_collider(Vector3(0.8, 0.8, 0.8), Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	time += delta
	model.position.y = 1.0 + sin(time * 1.6) * 0.05


func get_prompt(_player: PlayerCharacter) -> String:
	return "[E] Leer nota"


func interact(_player: PlayerCharacter) -> void:
	Sfx.play(self, "pickup", -14.0)
	toast(text, read_seconds)
