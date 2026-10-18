@tool
class_name LevelBuilder
extends Node3D
## Construye el nivel a partir de un mapa de texto.
##
## Es un script @tool: paredes, piso y muebles se dibujan TAMBIÉN en el editor.
## No se guardan dentro del .tscn (no tienen "owner"); se recrean al abrir la
## escena o al cambiar el mapa. Los objetos con lógica (puertas, llaves, notas,
## generador, lámparas) solo aparecen al ejecutar el juego.
##
## LECTURA DEL MAPA (cada carácter = medio paso de celda, cell_size / 2):
##   fila PAR    -> paredes horizontales entre celdas ('#') y postes ('+')
##   fila IMPAR  -> paredes verticales ('#') y celdas (' ')
## Las posiciones (fila impar, columna impar) son el CENTRO de una celda.
##
## En modo `sanatorium` además se leen estas letras:
##   En un hueco de pared (en vez de '#'):
##     1 / 2 / 3  puerta con llave (enfermería / laboratorio / máquinas)
##     X          puerta principal de salida (necesita energía)
##   En el centro de una celda:
##     L linterna      a/b/c llaves (enfermería/laboratorio/máquinas)
##     f fusible       n nota (en orden de lectura del mapa, ver `notes`)
##     G generador     S sirena       o lámpara de techo
##     m camilla       u casillero    T mesa
##   (el jugador y el murciélago se colocan en la escena, no en el mapa)
##
## VARIOS PISOS: `layout` es la planta baja y `layout_upper` (misma medida) el
## piso de arriba. Marcadores en el centro de una celda de la planta baja:
##     > < ^ v   escalera que sube hacia +X / -X / -Z / +Z (la salida queda en la
##               celda vecina del piso de arriba; el hueco se cierra solo)
##     e         ascensor (necesita el fusible del ascensor)
##   Herramientas y trampas:
##     q pistola de dardos   r caja de dardos   j botellas   k bengala
##     F fusible del ascensor   K bidón de combustible   I incinerador (final B)
##     p palanca  z zona trampa (la n-ésima 'p' activa la n-ésima 'z', en orden
##                de lectura: planta baja primero y luego el piso de arriba)

const WALL_SCENE := preload("res://scenes/props/maze_wall.tscn")
const TEX_ROOT := "res://assets/textures/"

## Texturas por tema (carpeta dentro de assets/textures/).
const TEXTURES := {
	"sanatorium": {"wall": "wall_plaster.png", "floor": "floor_tile.png", "ceiling": "ceiling.png"},
	"sotano": {"wall": "wall_brick.png", "floor": "floor_wet.png", "ceiling": "ceiling_concrete.png"},
	"raiz": {"wall": "cave_wall.png", "floor": "dirt_floor.png", "ceiling": "cave_ceiling.png"},
}
## Carpeta de texturas cuando el tema no tiene la suya.
const TEX_FOLDER := {"raiz": "rooms"}
## Qué llave abre cada puerta ('1', '2', '3') y la salida ('X') según el tema.
const LOCKS := {
	"sanatorium": {"1": "llave_enfermeria", "2": "llave_laboratorio", "3": "llave_maquinas", "X": "power"},
	"sotano": {"1": "llave_caldera", "2": "llave_camara", "3": "llave_bombas", "X": "power"},
	"raiz": {"1": "llave_drenaje", "2": "hacha", "3": "hacha", "X": "free"},
}
## Qué objeto recoge cada letra ('a', 'b', 'c') según el tema.
const PICKUPS := {
	"sanatorium": {"L": "linterna", "a": "llave_enfermeria", "b": "llave_laboratorio", "c": "llave_maquinas", "f": "fusible"},
	"sotano": {"L": "linterna", "a": "llave_caldera", "b": "llave_camara", "c": "llave_bombas", "f": "fusible"},
	"raiz": {"L": "linterna", "a": "llave_drenaje", "b": "hacha", "c": "llave_valvulas", "f": "fusible"},
}
const EXIT_LABELS := {"sanatorium": "puerta principal", "sotano": "compuerta de evacuación", "raiz": "salida a la superficie"}
## Estilos de sala: suelo, pared, color de luz y extras (sangre, cortinas, vapor...).
const ROOM_DIR := "res://assets/textures/rooms/"
const ROOM_STYLES := {
	"enf": {"floor": "tile_white.png", "wall": "wall_tile_white.png", "light": Color(0.82, 0.95, 1.0), "mul": 1.15, "extras": ["blood", "curtain", "drip"]},
	"dorm": {"floor": "wood.png", "wall": "", "wall_tint": Color(0.85, 0.7, 0.5), "light": Color(1.0, 0.78, 0.5), "mul": 0.85, "extras": ["blood_small"]},
	"lab": {"floor": "tile_green.png", "wall": "wall_green.png", "light": Color(0.55, 1.0, 0.6), "mul": 1.0, "extras": ["glow_green", "drip"]},
	"maq": {"floor": "metal_plate.png", "wall": "wall_metal.png", "light": Color(1.0, 0.6, 0.25), "mul": 1.0, "extras": ["steam"]},
	"cocina": {"floor": "tile_kitchen.png", "wall": "wall_kitchen.png", "light": Color(1.0, 0.95, 0.6), "mul": 1.0, "extras": ["blood", "blood_small"]},
	"patio": {"floor": "../floors/grass_floor.png", "wall": "", "wall_tint": Color(0.6, 0.75, 0.6), "light": Color(0.5, 0.65, 1.0), "mul": 1.3, "extras": ["mist"]},
	"oficina": {"floor": "wood.png", "wall": "wall_wood.png", "light": Color(1.0, 0.75, 0.45), "mul": 0.8, "extras": ["blood_small"]},
	"hall": {"floor": "carpet.png", "wall": "", "wall_tint": Color(0.8, 0.55, 0.5), "light": Color(1.0, 0.65, 0.5), "mul": 0.9, "extras": []},
	"aisla": {"floor": "padded.png", "wall": "padded.png", "light": Color(0.95, 0.92, 0.85), "mul": 0.8, "extras": ["blood", "drip"]},
	"caldera": {"floor": "metal_plate.png", "wall": "wall_metal.png", "light": Color(1.0, 0.38, 0.1), "mul": 1.3, "extras": ["steam", "glow_orange"]},
	"frio": {"floor": "frost.png", "wall": "wall_frost.png", "light": Color(0.6, 0.82, 1.0), "mul": 1.1, "extras": ["mist"]},
	"agua": {"floor": "", "wall": "", "wall_tint": Color(0.55, 0.85, 0.8), "light": Color(0.5, 1.0, 0.85), "mul": 1.0, "extras": ["mist"]},
	"almacen": {"floor": "", "wall": "", "wall_tint": Color(0.8, 0.65, 0.45), "light": Color(1.0, 0.85, 0.6), "mul": 0.8, "extras": []},
	"celdas": {"floor": "metal_plate.png", "wall": "wall_metal.png", "light": Color(1.0, 0.3, 0.25), "mul": 0.9, "extras": ["blood", "drip"]},
	"raiz": {"floor": "organic.png", "wall": "wall_organic.png", "light": Color(1.0, 0.25, 0.4), "mul": 1.4, "extras": ["pulse", "glow_red"]},
	"esporas": {"floor": "organic.png", "wall": "wall_organic.png", "light": Color(0.55, 1.0, 0.45), "mul": 1.2, "extras": ["glow_green", "mist"]},
	"tunel": {"floor": "organic.png", "wall": "wall_organic.png", "light": Color(1.0, 0.45, 0.3), "mul": 1.0, "extras": ["pulse"]},
	"c_hall": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "light": Color(1.0, 0.5, 0.35), "mul": 1.0, "extras": ["pulse"]},
	"c_agua": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(0.7, 0.9, 1.0), "light": Color(0.5, 0.85, 1.0), "mul": 1.0, "extras": ["glow_green", "mist"]},
	"c_esporas": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(0.7, 1.1, 0.7), "light": Color(0.5, 1.0, 0.45), "mul": 1.2, "extras": ["glow_green", "mist"]},
	"c_filtros": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(0.75, 0.85, 1.0), "light": Color(0.6, 0.8, 1.0), "mul": 1.0, "extras": ["mist"]},
	"c_almacen": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(1.1, 0.95, 0.75), "light": Color(1.0, 0.8, 0.5), "mul": 0.9, "extras": ["blood_small"]},
	"c_osario": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(1.2, 1.15, 1.0), "light": Color(0.95, 0.9, 0.8), "mul": 0.8, "extras": ["blood", "drip"]},
	"c_corazon": {"floor": "dirt_floor.png", "tint": Color(1.25, 0.7, 0.65), "wall": "wall_organic.png", "light": Color(1.0, 0.2, 0.35), "mul": 1.4, "extras": ["pulse", "glow_red"]},
	"c_nido": {"floor": "dirt_floor.png", "wall": "cave_wall.png", "tint": Color(1.1, 0.7, 0.8), "light": Color(1.0, 0.3, 0.4), "mul": 1.1, "extras": ["pulse", "mist"]},
	"conducto": {"floor": "metal_plate.png", "wall": "wall_metal.png", "light": Color(0.95, 0.85, 0.6), "mul": 0.9, "extras": ["steam"]},
	"drenaje": {"floor": "", "wall": "", "wall_tint": Color(0.55, 0.8, 0.55), "light": Color(0.6, 1.0, 0.7), "mul": 1.0, "extras": ["mist", "blood_small"]},
}

const PROP_MARKERS := {"m": "bed", "u": "locker", "T": "table", "B": "barrel"}
## Modelos 3D (Rodin) como decoración: letra del mapa -> archivo, escala y si cuelga del techo.
## `scale` convierte el tamaño del modelo (todos miden ~1.9) a metros reales.
const MODEL_PROPS := {
	"C": {"file": "camilla", "scale": 1.0},
	"W": {"file": "silla_ruedas", "scale": 0.5},
	"R": {"file": "carrito_medico", "scale": 0.5},
	"M": {"file": "mesa_laboratorio", "scale": 0.6},
	"N": {"file": "tanque_liquido", "scale": 0.9},
	"D": {"file": "caldera", "scale": 1.15},
	"J": {"file": "jaula", "scale": 0.65},
	"A": {"file": "armario_medicinas", "scale": 0.95},
	"H": {"file": "ganchos_carne", "scale": 1.3, "hang": true},
	"Y": {"file": "caja_madera", "scale": 0.65},
	"E": {"file": "cama_correas", "scale": 1.05},
	"P": {"file": "bomba_oxidada", "scale": 0.85},
}
const PROPS_DIR := "res://assets/props/"
const HEART_TUNNEL := preload("res://scripts/world/heart_tunnel.gd")
const PROP_VIEW_DISTANCE := 20.0
var _prop_cache := {}
## Objetos que valen igual en todos los temas: letra -> [id, cantidad].
const COMMON_PICKUPS := {"q": ["pistola", 1], "r": ["dardos", 3], "j": ["botella", 2], "k": ["bengala", 1], "F": ["fusible_ascensor", 1], "K": ["bidon_combustible", 1]}
const STAIR_DIRS := {">": Vector2i(1, 0), "<": Vector2i(-1, 0), "^": Vector2i(0, -1), "v": Vector2i(0, 1)}
const SLAB := 0.4

## Tamaño de cada celda (m).
@export var cell_size := 4.0:
	set(value):
		cell_size = value
		_rebuild_in_editor()

## Esquina (-X, -Z) del mapa.
@export var origin := Vector3(-10.0, 0.0, -10.0):
	set(value):
		origin = value
		_rebuild_in_editor()

## Activa piso, techo, texturas, puertas, objetos y muebles (nivel del sanatorio).
@export var sanatorium := false:
	set(value):
		sanatorium = value
		_rebuild_in_editor()

## Tema visual y de objetos: "sanatorium" (nivel 1) o "sotano" (nivel 2).
@export var theme := "sanatorium":
	set(value):
		theme = value
		_rebuild_in_editor()

## Altura de las paredes (m); el techo se coloca a esta altura.
@export var wall_height := 3.0

## Intensidad de las lámparas de techo (letra 'o'). Más bajo = más oscuro.
@export var lamp_energy := 0.5

## Textos de las notas, en el orden en que aparecen al leer el mapa
## (de arriba a abajo y de izquierda a derecha).
## Decoración con modelos: "piso,x,y,letra" (ver MODEL_PROPS).
@export var decor: PackedStringArray = PackedStringArray()
## Estilo de cada sala: "piso,x,y,estilo" (ver ROOM_STYLES).
@export var rooms: PackedStringArray = PackedStringArray()
@export var notes: Array[String] = [
	"Diario del paciente 12:\n\"Me trajeron de noche. Dicen que es por mi descanso, pero oigo aletear detrás de las paredes. Nunca duermen.\"",
	"Nota pegada al generador:\n\"Si lo enciende, la alarma del ala oeste sonará y ESO la atraerá hacia allá. Aproveche para correr a la puerta principal.\"",
	"Nota de la enfermera jefe:\n\"Guardé la llave del laboratorio en el botiquín. Y recuerde: el generador necesita TRES fusibles, ni uno menos.\"",
	"Informe del Dr. Vega:\n\"La criatura responde al sonido. Hablar, caminar normal, incluso respirar fuerte la atrae. Muévase agachado y, si lo persigue, escóndase en un casillero: pero adentro ni respire. La llave de máquinas está en el laboratorio.\"",
	"Aviso para el personal:\n\"La llave de la enfermería se quedó en la sala de pacientes. No entre solo a esa ala. Al Dr. Vega lo oímos gritar.\"",
]

## Mapa. Edítalo y todo se actualiza solo en el editor.
@export_multiline var layout := """+#+#+#+#+#+
#         #
+ +#+#+#+ +
#       # #
+ +#+#+ + +
#         #
+#+ + + +#+
#         #
+ + +#+#+ +
# #       #
+#+#+#+#+#+""":
	set(value):
		layout = value
		_rebuild_in_editor()

## Piso de arriba (misma medida que `layout`). Vacío = un solo piso.
@export_multiline var layout_upper := "":
	set(value):
		layout_upper = value
		_rebuild_in_editor()

var _wall_material: StandardMaterial3D
var _floor_material: StandardMaterial3D
var _ceiling_material: StandardMaterial3D
var _fy := 0.0                       # altura del piso que se está construyendo
var _stairs: Array = []              # [{cell, dir}]
var _openings: Array[Vector2i] = []  # celdas sin suelo arriba (escalera / ascensor)
var _levers: Array = []
var _grids: Array = []               # mapas por piso (con las paredes forzadas)
var _room_map := {}                  # Vector3i(piso, x, y) -> estilo
var _style_mats := {}                # cache de materiales de pared por estilo
var _fi := 0                         # índice del piso que se está construyendo
var _zones: Array = []


func _ready() -> void:
	add_to_group("level_builder")
	build()


## Número de celdas (columnas, filas) que tiene el mapa.
@warning_ignore("integer_division")
func grid_cells() -> Vector2i:
	var rows := _layout_rows()
	var width := 0
	for row in rows:
		width = maxi(width, row.length())
	return Vector2i(maxi(0, width - 1) / 2, maxi(0, rows.size() - 1) / 2)


func _layout_rows() -> PackedStringArray:
	return layout.replace("\r", "").strip_edges().split("\n")


func _upper_rows() -> PackedStringArray:
	return layout_upper.replace("\r", "").strip_edges().split("\n")


func floor_count() -> int:
	return 2 if layout_upper.strip_edges() != "" else 1


func floor_step() -> float:
	return wall_height + SLAB


func stair_cells() -> Array:
	return _stairs


func opening_cells() -> Array[Vector2i]:
	return _openings


## Crea (o recrea) todo el nivel.
@warning_ignore("integer_division")
func build() -> void:
	# free() inmediato (no queue_free) para poder reutilizar los mismos nombres.
	for child in get_children():
		remove_child(child)
		child.free()
	_stairs.clear()
	_openings.clear()
	_pits.clear()
	_levers.clear()
	_zones.clear()
	var runtime := not Engine.is_editor_hint()
	var floors := floor_count()
	_grids = [_to_grid(_layout_rows())]
	if floors > 1:
		_grids.append(_to_grid(_upper_rows()))
	_scan_openings()
	_scan_pits()
	_parse_rooms()
	if sanatorium:
		_build_shell()
	var note_index := 0
	for fi in floors:
		_fi = fi
		_fy = fi * floor_step()
		var frows := _from_grid(_grids[fi])
		note_index = _build_floor(frows, runtime, note_index)
		if sanatorium:
			_build_decor(frows)
			_build_room_style(frows)
			_build_cave(frows)
	_fi = 0
	_fy = 0.0
	_link_traps()


func _build_floor(rows: PackedStringArray, runtime: bool, note_index: int) -> int:
	for r in rows.size():
		var row := rows[r]
		for c in row.length():
			var ch := row[c]
			var is_slot := (r + c) % 2 == 1
			if ch == "#":
				_add_wall(r, c)
			elif not sanatorium:
				continue
			elif is_slot and _locks().has(ch):
				if runtime:
					_add_door(r, c, ch)
				else:
					_add_wall(r, c)
			elif r % 2 == 1 and c % 2 == 1:
				var cell := Vector2i((c - 1) / 2, (r - 1) / 2)
				if _fi > 0 and _openings.has(cell):
					continue    # arriba de la escalera / ascensor no hay nada
				note_index = _add_marker(ch, cell, rows, runtime, note_index)
	return note_index


func _build_decor(rows: PackedStringArray) -> void:
	if theme == "raiz":
		return
	for entry in decor:
		var p := entry.split(",")
		if p.size() < 4 or int(p[0]) != _fi:
			continue
		var cell := Vector2i(int(p[1]), int(p[2]))
		if _fi > 0 and _openings.has(cell):
			continue
		if MODEL_PROPS.has(p[3]):
			_add_model_prop(p[3], cell, rows)


# ------------------------------------------------------------- pisos y escaleras

func _to_grid(rows: PackedStringArray) -> Array:
	var grid := []
	for row in rows:
		var chars := []
		for i in row.length():
			chars.append(row[i])
		grid.append(chars)
	return grid


func _from_grid(grid: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for chars: Array in grid:
		rows.append("".join(PackedStringArray(chars)))
	return rows


func _set_slot(floor_index: int, r: int, c: int, ch: String) -> void:
	var grid: Array = _grids[floor_index]
	if r < 0 or r >= grid.size() or c < 0 or c >= (grid[r] as Array).size():
		return
	var current: String = grid[r][c]
	if ch == "#" or current == "#":     # solo cambia paredes, nunca puertas
		grid[r][c] = ch


## Busca escaleras y ascensores en la planta baja y fuerza sus paredes.
func _scan_openings() -> void:
	if _grids.size() < 2:
		return
	var ground: Array = _grids[0]
	for r in range(1, ground.size(), 2):
		var row: Array = ground[r]
		for c in range(1, row.size(), 2):
			var ch: String = row[c]
			var cell := Vector2i((c - 1) / 2, (r - 1) / 2)
			if STAIR_DIRS.has(ch):
				var dir: Vector2i = STAIR_DIRS[ch]
				_stairs.append({"cell": cell, "dir": dir})
				_openings.append(cell)
				for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var rr := r + side.y
					var cc := c + side.x
					_set_slot(0, rr, cc, " " if side == -dir else "#")
					_set_slot(1, rr, cc, " " if side == dir else "#")
			elif ch == "e":
				_openings.append(cell)


## Marca 'V': boca del túnel que baja al corazón. Hueco de 2 celdas hacia el este.
func _scan_pits() -> void:
	if theme != "raiz":
		return
	var cells := grid_cells()
	var rows := _layout_rows()
	for cy in cells.y:
		for cx in cells.x:
			if _char_at(rows, cy * 2 + 1, cx * 2 + 1) == "V":
				_pits.append(Vector2i(cx, cy))
				_pits.append(Vector2i(cx + 1, cy))


func _is_opening_slot(r: int, c: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var rr := r + d.y
		var cc := c + d.x
		if rr % 2 == 1 and cc % 2 == 1 and _openings.has(Vector2i((cc - 1) / 2, (rr - 1) / 2)):
			return true
	return false


## Dirección (en el mapa) del primer lado SIN pared de una celda.
func _open_dir(rows: PackedStringArray, cell: Vector2i) -> Vector3:
	var r := cell.y * 2 + 1
	var c := cell.x * 2 + 1
	for side: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if _char_at(rows, r + side.y, c + side.x) != "#":
			return Vector3(side.x, 0.0, side.y)
	return Vector3.BACK


func _add_stair(cell: Vector2i, dir: Vector2i) -> void:
	var rise := floor_step()
	var body := StaticBody3D.new()
	body.name = "Stair_%d_%d" % [cell.x, cell.y]
	body.position = _cell_center(cell)
	if dir == Vector2i(-1, 0):
		body.rotation.y = PI
	elif dir == Vector2i(0, 1):
		body.rotation.y = -PI / 2.0
	elif dir == Vector2i(0, -1):
		body.rotation.y = PI / 2.0
	add_child(body)
	var half := cell_size / 2.0
	var width := cell_size - 0.4
	# Cuña sólida: nada se puede meter debajo de la escalera.
	var wedge := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for z in [-width / 2.0, width / 2.0]:
		pts.append(Vector3(-half, 0.0, z))
		pts.append(Vector3(half, 0.0, z))
		pts.append(Vector3(half, rise, z))
		pts.append(Vector3(-half, -0.3, z))
	wedge.points = pts
	var shape := CollisionShape3D.new()
	shape.shape = wedge
	body.add_child(shape)
	# Escalones solo visuales (sin colisión), siempre por debajo de la rampa.
	var count := 17
	var run := cell_size / count
	for i in count:
		var top := rise * (i + 0.5) / count
		var step_mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(run + 0.001, top, width)
		step_mesh.mesh = box
		step_mesh.material_override = _floor_material
		step_mesh.position = Vector3(-half + run * (i + 0.5), top / 2.0, 0.0)
		body.add_child(step_mesh)


func _add_filler(r: int, c: int) -> void:
	# Tapa la rendija de 0.4 m entre la pared de abajo y la de arriba en el hueco.
	var filler := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.4, SLAB + 0.02, 0.4)
	filler.mesh = box
	filler.material_override = _wall_material
	filler.position = _slot_position(r, c) + Vector3(0.0, wall_height + SLAB / 2.0, 0.0)
	if r % 2 == 1:
		filler.rotation.y = PI / 2.0
	add_child(filler)


## Unir cada palanca con su zona trampa (la n-ésima con la n-ésima).
func _link_traps() -> void:
	for i in _levers.size():
		var lever: Node = _levers[i]
		if i < _zones.size():
			lever.set("zone", _zones[i])
		else:
			push_warning("LevelBuilder: la palanca %d no tiene zona 'z'" % (i + 1))


# ------------------------------------------------------------ paredes y puertas

func _slot_position(r: int, c: int) -> Vector3:
	return origin + Vector3(c * cell_size / 2.0, _fy, r * cell_size / 2.0)


func _cell_center(cell: Vector2i) -> Vector3:
	return origin + Vector3((cell.x + 0.5) * cell_size, _fy, (cell.y + 0.5) * cell_size)


func _add_wall(r: int, c: int) -> void:
	var wall := WALL_SCENE.instantiate() as StaticBody3D
	wall.name = "Wall_%d_%d_%d" % [_fi, r, c]
	wall.position = _slot_position(r, c)
	if r % 2 == 1:   # fila impar = pared vertical (gira 90 grados)
		wall.rotation.y = PI / 2.0
	wall.add_to_group("maze_walls")
	add_child(wall)   # sin owner: se ve en el editor pero no se guarda
	if sanatorium and _wall_material:
		var wall_mesh := wall.get_node("Mesh") as MeshInstance3D
		wall_mesh.material_override = _wall_material_for(r, c)
		if _fi == 0 and floor_count() > 1 and _is_opening_slot(r, c):
			_add_filler(r, c)


func _add_door(r: int, c: int, ch: String) -> void:
	var door := LockedDoor.new()
	door.name = "Door_%d_%d_%d" % [_fi, r, c]
	door.lock_id = _locks()[ch]
	door.exit_label = str(EXIT_LABELS.get(theme, "puerta principal"))
	door.is_exit = (ch == "X")
	door.position = _slot_position(r, c)
	if r % 2 == 1:
		door.rotation.y = PI / 2.0
	add_child(door)


# ------------------------------------------------------------------- marcadores

func _add_marker(ch: String, cell: Vector2i, rows: PackedStringArray, runtime: bool, note_index: int) -> int:
	var center := _cell_center(cell)
	if theme == "raiz" and (PROP_MARKERS.has(ch) or MODEL_PROPS.has(ch)):
		return note_index        # en la raíz no hay camillas, barriles ni muebles de los otros niveles
	if ch == "V":
		if runtime and theme == "raiz":
			var tunnel := Node3D.new()
			tunnel.set_script(HEART_TUNNEL)
			tunnel.name = "HeartTunnel"
			tunnel.position = center + Vector3(-cell_size / 2.0, 0.0, 0.0)
			tunnel.set("floor_y", 0.0)
			tunnel.set("wall_height", wall_height)
			tunnel.set("cell_size", cell_size)
			add_child(tunnel)
		return note_index
	if COMMON_PICKUPS.has(ch):
		if runtime:
			var common := PickupItem.new()
			common.name = "Item_%s_%d_%d_%d" % [ch, _fi, cell.x, cell.y]
			common.item_id = str(COMMON_PICKUPS[ch][0])
			common.amount = int(COMMON_PICKUPS[ch][1])
			common.position = center
			add_child(common)
	elif _pickups().has(ch):
		if runtime:
			var item := PickupItem.new()
			item.name = "Item_%s_%d_%d_%d" % [ch, _fi, cell.x, cell.y]
			item.item_id = _pickups()[ch]
			item.position = center
			add_child(item)
	elif ch == "p":
		if runtime:
			var lever := TrapLever.new()
			lever.name = "Lever_%d_%d_%d" % [_fi, cell.x, cell.y]
			var lever_spot := _wall_placement(cell, rows, 0.3)
			if lever_spot.is_empty():
				lever.position = center
			else:
				lever.position = lever_spot["position"]
				lever.rotation.y = lever_spot["rotation"]
			add_child(lever)
			_levers.append(lever)
	elif ch == "z":
		if runtime:
			var zone := TrapZone.new()
			zone.name = "TrapZone_%d_%d_%d" % [_fi, cell.x, cell.y]
			zone.size = Vector3(cell_size - 0.6, wall_height - 0.4, cell_size - 0.6)
			zone.position = center
			add_child(zone)
			_zones.append(zone)
	elif ch == "e":
		if runtime and _fi == 0:
			var elevator := Elevator.new()
			elevator.name = "Elevator"
			elevator.position = center
			elevator.cell_size = cell_size
			elevator.rise = floor_step()
			elevator.entry_low = _open_dir(_from_grid(_grids[0]), cell)
			elevator.entry_high = _open_dir(_from_grid(_grids[1]), cell) if _grids.size() > 1 else Vector3.BACK
			add_child(elevator)
	elif ch == "n":
		if runtime:
			var note := NoteItem.new()
			note.name = "Note_%d" % note_index
			note.text = notes[note_index] if note_index < notes.size() else "(nota sin texto)"
			note.position = center
			add_child(note)
		return note_index + 1
	elif ch == "G":
		if runtime:
			var generator := PowerGenerator.new()
			generator.name = "Generator"
			var placement := _wall_placement(cell, rows, 0.9)
			if placement.is_empty():
				generator.position = center
			else:
				generator.position = placement["position"]
				generator.rotation.y = placement["rotation"]
			add_child(generator)
	elif ch == "I":
		if runtime:
			var incinerator := Incinerator.new()
			incinerator.name = "Incinerator"
			incinerator.needs_power = (theme != "raiz")
			incinerator.needs_heart = (theme == "raiz")
			incinerator.position = center
			add_child(incinerator)
	elif ch == "S":
		if runtime:
			var siren := SirenSpeaker.new()
			siren.name = "Siren"
			siren.position = center + Vector3(0.0, wall_height - 0.25, 0.0)
			add_child(siren)
	elif ch == "o":
		if runtime:
			var lamp := FlickerLamp.new()
			lamp.name = "Lamp_%d_%d_%d" % [_fi, cell.x, cell.y]
			lamp.position = center + Vector3(0.0, wall_height - 0.35, 0.0)
			lamp.base_energy = lamp_energy
			var lst := _style_of(cell)
			if lst != "":
				lamp.base_energy = lamp_energy * float(ROOM_STYLES[lst]["mul"])
				lamp.normal_color = ROOM_STYLES[lst]["light"]
			if floor_count() > 1:
				lamp.lamp_range = 5.4
			add_child(lamp)
	elif ch == "w":
		if runtime:
			var puddle := Puddle.new()
			puddle.name = "Puddle_%d_%d_%d" % [_fi, cell.x, cell.y]
			puddle.position = center
			add_child(puddle)
	elif ch == "d":
		if runtime:
			var drip := AmbientDrip.new()
			drip.name = "Drip_%d_%d_%d" % [_fi, cell.x, cell.y]
			drip.position = center + Vector3(0.0, wall_height - 0.3, 0.0)
			add_child(drip)
	elif ch == "h":
		if runtime:
			var fungus := FungusGlow.new()
			fungus.name = "Fungus_%d_%d_%d" % [_fi, cell.x, cell.y]
			var spot := _wall_placement(cell, rows, 0.05)
			if spot.is_empty():
				fungus.position = center
			else:
				fungus.position = spot["position"]
				fungus.rotation.y = spot["rotation"]
			add_child(fungus)
	elif PROP_MARKERS.has(ch):
		_add_prop(PROP_MARKERS[ch], cell, rows)
	elif MODEL_PROPS.has(ch):
		_add_model_prop(ch, cell, rows)
	return note_index


## Decoración con modelo 3D: va pegada a una pared libre (o colgada del techo) y
## gira para que su lado largo quede a lo largo de la pared. Con colisión simple.
func _add_model_prop(ch: String, cell: Vector2i, rows: PackedStringArray) -> void:
	var info: Dictionary = MODEL_PROPS[ch]
	var path := PROPS_DIR + str(info["file"]) + ".glb"
	if not ResourceLoader.exists(path):
		return
	if not _prop_cache.has(path):
		_prop_cache[path] = load(path)
	var packed := _prop_cache[path] as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	var k: float = float(info["scale"])
	var box := _model_aabb(model)
	var size := box.size * k
	var hang: bool = info.get("hang", false)
	# menor lado contra la pared: si el modelo es más ancho en Z que en X, se gira 90 grados
	var yaw := 0.0
	var turn := size.x < size.z
	if turn:
		yaw = PI / 2.0 if (cell.x + cell.y) % 2 == 0 else -PI / 2.0
	var width := maxf(size.x, size.z) if turn else size.x
	var depth := size.x if turn else size.z
	var body := StaticBody3D.new()
	body.name = "Prop_%s_%d_%d_%d" % [info["file"], _fi, cell.x, cell.y]
	if hang:
		body.position = _cell_center(cell) + Vector3(0.0, wall_height - size.y - 0.02, 0.0)
		body.rotation.y = 0.0 if (cell.x + cell.y) % 2 == 0 else PI / 2.0
		yaw = 0.0
	else:
		var placement := _wall_placement(cell, rows, depth)
		if placement.is_empty():
			model.free()
			return
		body.position = placement["position"]
		body.rotation.y = placement["rotation"]
	add_child(body)
	var pivot := Node3D.new()
	pivot.rotation.y = yaw
	body.add_child(pivot)
	model.scale = Vector3.ONE * k
	var c := box.get_center() * k
	model.position = Vector3(-c.x, -box.position.y * k, -c.z)
	pivot.add_child(model)
	_limit_view_distance(model)
	if not hang:
		var half := Vector3(size.x, size.y, size.z)
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(half.x * 0.9, size.y, half.z * 0.9)
		shape.shape = bs
		shape.position = Vector3(0.0, size.y / 2.0, 0.0)
		shape.rotation.y = yaw
		body.add_child(shape)


func _model_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m := n as MeshInstance3D
			var a := m.get_aabb()
			var t := m.transform if m.get_parent() == root else Transform3D.IDENTITY
			a = t * a
			result = a if first else result.merge(a)
			first = false
		for child in n.get_children():
			stack.append(child)
	return result


func _limit_view_distance(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).visibility_range_end = PROP_VIEW_DISTANCE
			(n as GeometryInstance3D).visibility_range_end_margin = 3.0
			(n as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for child in n.get_children():
			stack.append(child)


func _char_at(rows: PackedStringArray, r: int, c: int) -> String:
	if r < 0 or r >= rows.size() or c < 0 or c >= rows[r].length():
		return ""
	return rows[r][c]


## Posición y giro para pegar un objeto de profundidad `depth` contra una pared
## libre de la celda (así nunca estorba el camino entre centros de celda).
## Devuelve {} si la celda no tiene ninguna pared libre.
func _wall_placement(cell: Vector2i, rows: PackedStringArray, depth: float) -> Dictionary:
	var r := cell.y * 2 + 1
	var c := cell.x * 2 + 1
	var sides := [
		{"dir": Vector3(0, 0, 1), "dr": 1, "dc": 0},
		{"dir": Vector3(0, 0, -1), "dr": -1, "dc": 0},
		{"dir": Vector3(1, 0, 0), "dr": 0, "dc": 1},
		{"dir": Vector3(-1, 0, 0), "dr": 0, "dc": -1},
	]
	var start := (cell.x + cell.y * 3) % 4
	for i in 4:
		var side: Dictionary = sides[(start + i) % 4]
		if _char_at(rows, r + int(side["dr"]), c + int(side["dc"])) != "#":
			continue
		var dir: Vector3 = side["dir"]
		var inner := cell_size / 2.0 - 0.2   # cara interior de la pared (grosor 0.4)
		return {
			"position": _cell_center(cell) + dir * (inner - depth / 2.0),
			"rotation": atan2(-dir.x, -dir.z),
		}
	return {}


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _collider(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	parent.add_child(shape)


func _add_prop(kind: String, cell: Vector2i, rows: PackedStringArray) -> void:
	var depth := 0.9
	match kind:
		"locker":
			depth = 0.55
		"table":
			depth = 0.85
		"barrel":
			depth = 1.1
	var placement := _wall_placement(cell, rows, depth)
	if placement.is_empty():
		return
	if (kind == "locker" or kind == "barrel") and not Engine.is_editor_hint():
		var spot := HidingSpot.new()   # escondite donde el jugador puede meterse
		spot.kind = kind
		spot.name = "%s_%d_%d" % [kind.capitalize(), cell.x, cell.y]
		spot.position = placement["position"]
		spot.rotation.y = placement["rotation"]
		add_child(spot)
		return
	var body := StaticBody3D.new()
	body.name = "%s_%d_%d" % [kind, cell.x, cell.y]
	body.position = placement["position"]
	body.rotation.y = placement["rotation"]
	add_child(body)
	match kind:
		"bed":
			_box(body, Vector3(2.0, 0.45, 0.9), Vector3(0, 0.225, 0), Color(0.16, 0.18, 0.18))
			_box(body, Vector3(1.9, 0.14, 0.82), Vector3(0, 0.52, 0), Color(0.55, 0.53, 0.44))
			_box(body, Vector3(0.45, 0.1, 0.6), Vector3(-0.7, 0.64, 0), Color(0.62, 0.6, 0.55))
			_collider(body, Vector3(2.0, 0.65, 0.9), Vector3(0, 0.325, 0))
		"locker":
			_box(body, Vector3(0.9, 1.9, 0.55), Vector3(0, 0.95, 0), Color(0.2, 0.27, 0.27))
			_box(body, Vector3(0.04, 0.5, 0.03), Vector3(0.1, 1.0, 0.29), Color(0.05, 0.05, 0.05))
			_collider(body, Vector3(0.9, 1.9, 0.55), Vector3(0, 0.95, 0))
		"barrel":
			_box(body, Vector3(1.0, 1.5, 1.0), Vector3(0, 0.75, 0), Color(0.2, 0.22, 0.17))
			_collider(body, Vector3(1.0, 1.5, 1.0), Vector3(0, 0.75, 0))
		"table":
			_box(body, Vector3(1.6, 0.08, 0.85), Vector3(0, 0.78, 0), Color(0.25, 0.2, 0.15))
			_box(body, Vector3(0.08, 0.74, 0.8), Vector3(-0.7, 0.37, 0), Color(0.12, 0.12, 0.12))
			_box(body, Vector3(0.08, 0.74, 0.8), Vector3(0.7, 0.37, 0), Color(0.12, 0.12, 0.12))
			_collider(body, Vector3(1.6, 0.82, 0.85), Vector3(0, 0.41, 0))


# ------------------------------------------------------------------ piso y techo

func _tex(file: String) -> Texture2D:
	var path := TEX_ROOT + str(TEX_FOLDER.get(theme, theme)) + "/" + file
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _make_material(file: String, fallback: Color, uv_scale: Vector3) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var texture := _tex(file)
	if texture:
		material.albedo_texture = texture
	else:
		material.albedo_color = fallback
	material.roughness = 1.0
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = uv_scale
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return material


func _build_shell() -> void:
	var cells := grid_cells()
	var size := Vector2(cells.x, cells.y) * cell_size
	var center := origin + Vector3(size.x, 0.0, size.y) / 2.0
	var floors := floor_count()

	_wall_material = _make_material(_tex_file("wall"), Color(0.45, 0.5, 0.42), Vector3(0.25, 0.3333, 0.25))
	_floor_material = _make_material(_tex_file("floor"), Color(0.35, 0.37, 0.33), Vector3(0.5, 0.5, 0.5))
	_ceiling_material = _make_material(_tex_file("ceiling"), Color(0.3, 0.3, 0.28), Vector3(0.5, 0.5, 0.5))

	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = center
	add_child(floor_body)
	if _pits.is_empty():
		var floor_mesh := MeshInstance3D.new()
		var floor_plane := PlaneMesh.new()
		floor_plane.size = size
		floor_mesh.mesh = floor_plane
		floor_mesh.material_override = _floor_material
		floor_body.add_child(floor_mesh)
		_collider(floor_body, Vector3(size.x + 8.0, 0.4, size.y + 8.0), Vector3(0, -0.2, 0))
	else:
		_build_floor_with_pits(floor_body, cells, size, center)

	# Techo del último piso (un solo plano; el hueco de la escalera queda abierto debajo).
	var ceiling := MeshInstance3D.new()
	ceiling.name = "Ceiling"
	var ceiling_plane := PlaneMesh.new()
	ceiling_plane.size = size
	ceiling.mesh = ceiling_plane
	ceiling.material_override = _ceiling_material
	ceiling.position = center + Vector3(0.0, (floors - 1) * floor_step() + wall_height, 0.0)
	ceiling.rotation.x = PI   # el plano mira hacia abajo
	add_child(ceiling)

	if floors > 1:
		_add_slabs(cells)
		for stair: Dictionary in _stairs:
			_add_stair(stair["cell"], stair["dir"])

	if theme == "sotano":
		_add_pipes(center, size)


## Suelo en tiras por fila, dejando sin suelo las celdas de `_pits` (boca del túnel).
func _build_floor_with_pits(floor_body: StaticBody3D, cells: Vector2i, size: Vector2, center: Vector3) -> void:
	for y in cells.y:
		var x := 0
		while x < cells.x:
			if _pits.has(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < cells.x and not _pits.has(Vector2i(x, y)):
				x += 1
			var length := (x - start) * cell_size
			var mid := origin + Vector3(start * cell_size + length / 2.0, 0.0, (y + 0.5) * cell_size)
			var mi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(length, cell_size)
			mi.mesh = plane
			mi.material_override = _floor_material
			mi.position = mid - center
			floor_body.add_child(mi)
			var ext_l := 4.0 if start == 0 else 0.0
			var ext_r := 4.0 if x >= cells.x else 0.0
			_collider(floor_body, Vector3(length + ext_l + ext_r, 0.4, cell_size), mid - center + Vector3((ext_r - ext_l) / 2.0, -0.2, 0))
	# margen exterior (arriba y abajo del mapa)
	_collider(floor_body, Vector3(size.x + 8.0, 0.4, 4.0), Vector3(0, -0.2, -size.y / 2.0 - 2.0))
	_collider(floor_body, Vector3(size.x + 8.0, 0.4, 4.0), Vector3(0, -0.2, size.y / 2.0 + 2.0))


# Losa entre pisos: una caja por tramo de celdas seguidas (sin las celdas con hueco).
func _add_slabs(cells: Vector2i) -> void:
	var slabs := StaticBody3D.new()
	slabs.name = "Slabs"
	add_child(slabs)
	for y in cells.y:
		var x := 0
		while x < cells.x:
			if _openings.has(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < cells.x and not _openings.has(Vector2i(x, y)):
				x += 1
			var length := (x - start) * cell_size
			var mid := origin + Vector3((start * cell_size) + length / 2.0, 0.0, (y + 0.5) * cell_size)
			var box_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(length, SLAB, cell_size)
			box_mesh.mesh = box
			box_mesh.material_override = _ceiling_material
			box_mesh.position = mid + Vector3(0.0, wall_height + SLAB / 2.0, 0.0)
			slabs.add_child(box_mesh)
			var top := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(length, cell_size)
			top.mesh = plane
			top.material_override = _floor_material
			top.position = mid + Vector3(0.0, floor_step() + 0.003, 0.0)
			slabs.add_child(top)
			_collider(slabs, Vector3(length, SLAB, cell_size), mid + Vector3(0.0, wall_height + SLAB / 2.0, 0.0))


func _locks() -> Dictionary:
	return LOCKS.get(theme, LOCKS["sanatorium"])


func _pickups() -> Dictionary:
	return PICKUPS.get(theme, PICKUPS["sanatorium"])


func _tex_file(kind: String) -> String:
	var files: Dictionary = TEXTURES.get(theme, TEXTURES["sanatorium"])
	return str(files[kind])


# Tuberías oxidadas a lo largo del techo (solo decoración, no estorban el paso).
func _add_pipes(center: Vector3, size: Vector2) -> void:
	var material := _make_material("pipe_rust.png", Color(0.45, 0.26, 0.14), Vector3(1.0, 1.0, 1.0))
	var rows := int(size.y / cell_size)
	for r in range(1, rows, 3):
		var blocked := false
		for opening in _openings:
			if opening.y == r:
				blocked = true
		if blocked:
			continue
		for height: float in [wall_height - 0.3, wall_height - 0.62]:
			var pipe := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.1
			cylinder.bottom_radius = 0.1
			cylinder.height = size.x
			cylinder.radial_segments = 8
			cylinder.rings = 1
			pipe.mesh = cylinder
			pipe.material_override = material
			pipe.rotation.z = PI / 2.0
			pipe.position = Vector3(center.x, height, origin.z + r * cell_size + (0.45 if height > wall_height - 0.4 else 0.75))
			add_child(pipe)


# Solo en el editor y cuando el nodo ya está listo: al cambiar una propiedad
# del inspector se redibuja el nivel.
func _rebuild_in_editor() -> void:
	if Engine.is_editor_hint() and is_node_ready():
		build()


# ------------------------------------------------------------- estilos de sala

func _parse_rooms() -> void:
	_room_map.clear()
	_style_mats.clear()
	for entry in rooms:
		var p := entry.split(",")
		if p.size() >= 4 and ROOM_STYLES.has(p[3]):
			_room_map[Vector3i(int(p[0]), int(p[1]), int(p[2]))] = p[3]


func _style_of(cell: Vector2i) -> String:
	return str(_room_map.get(Vector3i(_fi, cell.x, cell.y), ""))


func _load_room_tex(file: String) -> Texture2D:
	if file == "":
		return null
	var path := ROOM_DIR + file
	if file.begins_with("../"):
		path = TEX_ROOT + file.substr(3)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _style_material(style: String, kind: String) -> StandardMaterial3D:
	var key := style + "/" + kind
	if _style_mats.has(key):
		return _style_mats[key]
	var info: Dictionary = ROOM_STYLES[style]
	var tex := _load_room_tex(str(info.get(kind, "")))
	var mat: StandardMaterial3D
	if kind == "wall":
		if tex == null:
			mat = _wall_material
			if info.has("wall_tint") and _wall_material:
				mat = _wall_material.duplicate() as StandardMaterial3D
				mat.albedo_color = info["wall_tint"]
		else:
			mat = _make_material("", Color.WHITE, Vector3(0.25, 0.3333, 0.25))
			mat.albedo_texture = tex
			mat.albedo_color = info.get("tint", Color.WHITE)
	else:
		if tex == null:
			mat = _floor_material.duplicate() as StandardMaterial3D if _floor_material else null
		else:
			mat = _make_material("", Color.WHITE, Vector3(0.5, 0.5, 0.5))
			mat.albedo_texture = tex
			mat.albedo_color = info.get("tint", Color.WHITE)
	_style_mats[key] = mat
	return mat


## Material de una pared según el estilo de la sala a la que mira (la primera con estilo).
func _wall_material_for(r: int, c: int) -> Material:
	var a: Vector2i
	var b: Vector2i
	if r % 2 == 0:
		a = Vector2i((c - 1) / 2, r / 2 - 1)
		b = Vector2i((c - 1) / 2, r / 2)
	else:
		a = Vector2i(c / 2 - 1, (r - 1) / 2)
		b = Vector2i(c / 2, (r - 1) / 2)
	var st := _style_of(a)
	if st == "":
		st = _style_of(b)
	if st == "":
		return _wall_material
	var m := _style_material(st, "wall")
	return m if m else _wall_material


func _build_room_style(rows: PackedStringArray) -> void:
	if _room_map.is_empty() or not _floor_material:
		return
	# 1) suelo: un quad por celda con estilo (agrupado por estilo en una sola malla)
	var by_style := {}
	for key: Vector3i in _room_map:
		if key.x != _fi:
			continue
		var cell := Vector2i(key.y, key.z)
		if _openings.has(cell) or _pits.has(cell):
			continue
		var st: String = _room_map[key]
		if not by_style.has(st):
			by_style[st] = []
		by_style[st].append(cell)
	for st: String in by_style:
		var mat := _style_material(st, "floor")
		if mat == null:
			continue
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector2i in by_style[st]:
			var c0 := _cell_center(cell) - Vector3(cell_size / 2.0, -0.012, cell_size / 2.0)
			var a := c0
			var b := c0 + Vector3(cell_size, 0, 0)
			var c := c0 + Vector3(cell_size, 0, cell_size)
			var d := c0 + Vector3(0, 0, cell_size)
			for v: Vector3 in [a, c, b, a, d, c]:
				tool.set_normal(Vector3.UP)
				tool.add_vertex(v)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "RoomFloor_%d_%s" % [_fi, st]
		mesh_instance.mesh = tool.commit()
		mesh_instance.material_override = mat
		add_child(mesh_instance)
	# 2) extras por celda
	for key: Vector3i in _room_map:
		if key.x != _fi:
			continue
		var cell := Vector2i(key.y, key.z)
		if _openings.has(cell) or _pits.has(cell):
			continue
		var st: String = _room_map[key]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(_fi, cell.x, cell.y))
		for extra in ROOM_STYLES[st]["extras"]:
			_add_room_extra(str(extra), cell, rows, rng)


func _decal(file: String, size: Vector2, pos: Vector3, rot: Vector3) -> void:
	var tex := _load_room_tex(file)
	if tex == null:
		return
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.material_override = mat
	node.position = pos
	node.rotation = rot
	node.visibility_range_end = 22.0
	add_child(node)


func _add_room_extra(kind: String, cell: Vector2i, rows: PackedStringArray, rng: RandomNumberGenerator) -> void:
	var center := _cell_center(cell)
	match kind:
		"blood", "blood_small":
			if kind == "blood" and rng.randf() < 0.55 or kind == "blood_small" and rng.randf() < 0.3:
				var off := Vector3(rng.randf_range(-1.3, 1.3), 0.02, rng.randf_range(-1.3, 1.3))
				var sz := rng.randf_range(0.9, 1.7)
				var f := "blood_splat.png" if rng.randf() < 0.6 else "blood_drag.png"
				_decal(f, Vector2(sz, sz), center + off, Vector3(-PI / 2.0, rng.randf() * TAU, 0.0))
		"drip":
			if rng.randf() < 0.35:
				var pl := _wall_placement(cell, rows, 0.04)
				if not pl.is_empty():
					var p: Vector3 = pl["position"]
					_decal("blood_drip.png", Vector2(1.2, 1.4), p + Vector3(rng.randf_range(-0.8, 0.8), 1.5, 0), Vector3(0, pl["rotation"], 0))
		"curtain":
			if rng.randf() < 0.5:
				var pl := _wall_placement(cell, rows, 1.6)
				if not pl.is_empty():
					_add_curtain(pl["position"], pl["rotation"])
		"steam":
			if rng.randf() < 0.45:
				var pl := _wall_placement(cell, rows, 0.6)
				if not pl.is_empty() and not Engine.is_editor_hint():
					_add_steam(pl["position"] + Vector3(0, 0.3, 0))
		"mist":
			rng.randf()   # niebla del patio quitada (se veía rara)
		"glow_green", "glow_orange", "glow_red", "pulse":
			if rng.randf() < 0.6 and not Engine.is_editor_hint():
				var col := Color(0.3, 1.0, 0.4)
				if kind == "glow_orange":
					col = Color(1.0, 0.45, 0.1)
				elif kind == "glow_red" or kind == "pulse":
					col = Color(1.0, 0.12, 0.2)
				var light := OmniLight3D.new()
				light.light_color = col
				light.light_energy = 0.45
				light.omni_range = 4.5
				light.position = center + Vector3(rng.randf_range(-1.2, 1.2), 1.4, rng.randf_range(-1.2, 1.2))
				add_child(light)
				var tw := light.create_tween().set_loops()
				tw.tween_property(light, "light_energy", 0.15, rng.randf_range(0.7, 1.6))
				tw.tween_property(light, "light_energy", 0.55, rng.randf_range(0.7, 1.6))


func _add_curtain(pos: Vector3, yaw: float) -> void:
	var body := Node3D.new()
	body.position = pos
	body.rotation.y = yaw
	add_child(body)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.8, 0.75, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	var cloth := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.9)
	cloth.mesh = quad
	cloth.material_override = mat
	cloth.position = Vector3(0, 1.0, 0)
	body.add_child(cloth)
	# mancha de sangre sobre la tela
	var tex := _load_room_tex("blood_drip.png")
	if tex:
		var m2 := StandardMaterial3D.new()
		m2.albedo_texture = tex
		m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m2.cull_mode = BaseMaterial3D.CULL_DISABLED
		var smear := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(1.4, 1.4)
		smear.mesh = q2
		smear.material_override = m2
		smear.position = Vector3(0.2, 1.1, 0.01)
		body.add_child(smear)
	_box(body, Vector3(2.5, 0.04, 0.04), Vector3(0, 2.0, 0), Color(0.35, 0.35, 0.35))


var _puff_tex: GradientTexture2D


## Bolita suave (círculo que se difumina) para el vapor y la niebla.
func _soft_puff() -> GradientTexture2D:
	if _puff_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		_puff_tex = GradientTexture2D.new()
		_puff_tex.gradient = grad
		_puff_tex.fill = GradientTexture2D.FILL_RADIAL
		_puff_tex.fill_from = Vector2(0.5, 0.5)
		_puff_tex.fill_to = Vector2(1.0, 0.5)
		_puff_tex.width = 64
		_puff_tex.height = 64
	return _puff_tex


func _add_steam(pos: Vector3, slow := false) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 10
	p.lifetime = 3.5 if not slow else 6.0
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.25 if not slow else 0.05
	p.initial_velocity_max = 0.6 if not slow else 0.15
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.8
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85, 0.2 if not slow else 0.13)
	mat.albedo_texture = _soft_puff()      # sin textura se veían como cuadrados grises
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	p.mesh = quad
	add_child(p)


# ------------------------------------------------------------- cueva (nivel 3)

func _wall_dirs(cell: Vector2i, rows: PackedStringArray) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var r := cell.y * 2 + 1
	var c := cell.x * 2 + 1
	for side in [[Vector3(0, 0, 1), 1, 0], [Vector3(0, 0, -1), -1, 0], [Vector3(1, 0, 0), 0, 1], [Vector3(-1, 0, 0), 0, -1]]:
		if _char_at(rows, r + int(side[1]), c + int(side[2])) == "#":
			out.append(side[0])
	return out


func _cave_mat(texture: String, tint: Color, emission: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := _load_room_tex(texture)
	if tex:
		m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.6, 0.6, 0.6)
	if emission.a > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 0.5
	return m


func _add_multimesh(node_name: String, mesh: Mesh, material: Material, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = "%s_%d" % [node_name, _fi]
	inst.multimesh = mm
	inst.material_override = material
	add_child(inst)


var _pits: Array[Vector2i] = []      ## Celdas sin suelo (boca del túnel hacia el corazón)
var _root_variants_wall: Array = []
var _root_variants_floor: Array = []


## Tubo curvo con grosor variable (para raíces).
func _tube(st: SurfaceTool, pts: Array, radii: Array, v0 := 0.0) -> void:
	var sides := 6
	var rings: Array = []
	for i in pts.size():
		var tangent: Vector3
		if i == 0:
			tangent = pts[1] - pts[0]
		elif i == pts.size() - 1:
			tangent = pts[i] - pts[i - 1]
		else:
			tangent = pts[i + 1] - pts[i - 1]
		tangent = tangent.normalized()
		var ref := Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT
		var n1 := tangent.cross(ref).normalized()
		var n2 := tangent.cross(n1).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			var dir := n1 * cos(a) + n2 * sin(a)
			ring.append([pts[i] + dir * float(radii[i]), dir])
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			var corners := [[rings[i][k], k, i], [rings[i][k2], k + 1, i], [rings[i + 1][k2], k + 1, i + 1], [rings[i + 1][k], k, i + 1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var cn: Array = corners[idx]
				var vert: Array = cn[0]
				st.set_normal(vert[1])
				st.set_uv(Vector2(float(cn[1]) / sides * 1.5, v0 + float(cn[2]) * 0.35))
				st.add_vertex(vert[0])


func _curve(rng: RandomNumberGenerator, start: Vector3, step: Vector3, count: int, wiggle: float, drift: Vector3 = Vector3.ZERO) -> Array:
	var pts: Array = []
	var p := start
	var phase := rng.randf() * TAU
	for i in count:
		pts.append(p + Vector3(sin(i * 0.8 + phase) * wiggle, 0.0, cos(i * 0.6 + phase) * wiggle * 0.5) + drift * i)
		p += step
	return pts


## Raíz pegada a la pared (ejes locales: x a lo largo de la pared, y arriba, z hacia la sala).
func _make_wall_root(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth := rng.randf_range(1.3, wall_height)
	var reaches_floor := rng.randf() < 0.45
	if reaches_floor:
		depth = wall_height
	var n := 9
	var step := depth / float(n - 1)
	var r0 := rng.randf_range(0.11, 0.2)
	var trunk: Array = _curve(rng, Vector3(0, wall_height + 0.1, 0.07), Vector3(0, -step, 0), n, 0.14)
	for i in trunk.size():
		var bump := rng.randf_range(0.0, 0.07)
		trunk[i] = (trunk[i] as Vector3) + Vector3(0, 0, bump)
	var radii: Array = []
	for i in n:
		radii.append(lerpf(r0, 0.035, float(i) / float(n - 1)) * rng.randf_range(0.85, 1.15))
	if reaches_floor:
		# el tronco se dobla hacia fuera y se hunde en el suelo
		var last: Vector3 = trunk[n - 1]
		for j in 1 + 4:
			var q := last + Vector3(rng.randf_range(-0.1, 0.1) * j, 0.0, 0.0)
			q.y = maxf(0.03, last.y - 0.04 * j)
			q.z = last.z + 0.28 * j
			trunk.append(q)
			radii.append(maxf(0.03, float(radii[radii.size() - 1]) * 0.85))
	_tube(st, trunk, radii)
	for b in rng.randi_range(2, 4):
		var at := rng.randi_range(1, n - 3)
		var origin: Vector3 = trunk[at]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var len := rng.randf_range(0.7, 1.6)
		var count := 6
		var bstep := Vector3(side * len / float(count), -rng.randf_range(0.05, 0.22), rng.randf_range(-0.01, 0.03))
		var bpts: Array = _curve(rng, origin + Vector3(0, 0, 0.02), bstep, count, 0.06)
		var brad: Array = []
		var rb := float(radii[at]) * 0.55
		for i in count:
			brad.append(lerpf(rb, 0.012, float(i) / float(count - 1)))
		_tube(st, bpts, brad, 1.0)
	var mesh := st.commit()
	return mesh


## Raíz que sale de la base de la pared y se arrastra por el suelo hasta hundirse.
func _make_floor_root(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := rng.randf_range(1.0, 2.4)
	var n := 8
	var pts: Array = []
	var radii: Array = []
	var phase := rng.randf() * TAU
	var x_drift := rng.randf_range(-0.5, 0.5)
	for i in n:
		var t := float(i) / float(n - 1)
		var y := 0.1 + sin(t * 5.0 + phase) * 0.06 - t * 0.12
		pts.append(Vector3(x_drift * t + sin(t * 4.0 + phase) * 0.12, maxf(y, -0.03), 0.02 + t * length))
		radii.append(lerpf(0.14, 0.03, t))
	_tube(st, pts, radii, 2.0)
	for b in rng.randi_range(1, 2):
		var at := rng.randi_range(1, 4)
		var origin: Vector3 = pts[at]
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var bpts: Array = []
		var brad: Array = []
		for i in 5:
			var t2 := float(i) / 4.0
			bpts.append(origin + Vector3(side * t2 * 0.9, -t2 * 0.1, t2 * 0.5 + sin(t2 * 6.0) * 0.05))
			brad.append(lerpf(0.06, 0.012, t2))
		_tube(st, bpts, brad, 3.0)
	return st.commit()


## Ambiente de cueva: raíces pegadas a las paredes (algunas llegan al suelo y se arrastran por él),
## bultos de roca, estalagmitas y columnas de raíz. Todo en MultiMesh (pocas llamadas de dibujo).
func _build_cave(rows: PackedStringArray) -> void:
	if theme != "raiz":
		return
	if _root_variants_wall.is_empty():
		var vr := RandomNumberGenerator.new()
		vr.seed = 4242
		for i in 7:
			_root_variants_wall.append(_make_wall_root(vr))
		for i in 4:
			_root_variants_floor.append(_make_floor_root(vr))
	var cells := grid_cells()
	var wall_t: Array = []
	var floor_t: Array = []
	for i in _root_variants_wall.size():
		wall_t.append([])
	for i in _root_variants_floor.size():
		floor_t.append([])
	var bumps: Array = []
	var cones_up: Array = []
	var cones_down: Array = []
	var inner := cell_size / 2.0 - 0.2
	for cy in cells.y:
		for cx in cells.x:
			var cell := Vector2i(cx, cy)
			if (_fi > 0 and _openings.has(cell)) or _pits.has(cell):
				continue
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(31 + _fi, cx, cy))
			var c := _cell_center(cell)
			if rng.randf() < 0.2:
				var q := c + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
				var h := rng.randf_range(0.5, 1.3)
				cones_up.append(Transform3D(Basis.from_scale(Vector3(rng.randf_range(0.5, 1.0), h, rng.randf_range(0.5, 1.0))), q + Vector3(0, h / 2.0, 0)))
			if rng.randf() < 0.14:
				var q2 := c + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
				var h2 := rng.randf_range(0.5, 1.3)
				cones_down.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(rng.randf_range(0.5, 1.0), h2, rng.randf_range(0.5, 1.0))), q2 + Vector3(0, wall_height - h2 / 2.0, 0)))
			var dirs := _wall_dirs(cell, rows)
			for dir in dirs:
				var yaw := atan2(-dir.x, -dir.z)
				var basis := Basis(Vector3.UP, yaw)
				var base := c + dir * (inner - 0.01)
				for i in rng.randi_range(0, 2):
					var off := rng.randf_range(-1.7, 1.7)
					var hh := rng.randf_range(0.4, 2.8)
					bumps.append(Transform3D(basis * Basis.from_scale(Vector3(rng.randf_range(0.5, 1.2), rng.randf_range(0.4, 1.0), rng.randf_range(0.28, 0.5))),
						base + basis.x * off + Vector3(0, hh, 0)))
				if rng.randf() < 0.5:
					var vi := rng.randi_range(0, _root_variants_wall.size() - 1)
					var s := rng.randf_range(0.85, 1.25)
					(wall_t[vi] as Array).append(Transform3D(basis * Basis.from_scale(Vector3(s, 1.0, s)), base + basis.x * rng.randf_range(-1.6, 1.6)))
				if rng.randf() < 0.22:
					var fi2 := rng.randi_range(0, _root_variants_floor.size() - 1)
					var s2 := rng.randf_range(0.8, 1.2)
					(floor_t[fi2] as Array).append(Transform3D(basis * Basis.from_scale(Vector3(s2, s2, s2)), base + basis.x * rng.randf_range(-1.5, 1.5)))
			# columna de raíz en esquinas de las salas (con colisión)
			if dirs.size() >= 2 and rng.randf() < 0.3 and _style_of(cell) != "" and _style_of(cell) != "c_hall":
				var a: Vector3 = dirs[0]
				var b: Vector3 = dirs[1]
				if absf(a.dot(b)) < 0.5:
					_add_root_column(c + (a + b) * (inner - 0.55))
	var root_mat := _cave_mat("root_bark.png", Color(0.9, 0.8, 0.75), Color(0, 0, 0, 0))
	root_mat.uv1_triplanar = false
	root_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rock_mat := _cave_mat("cave_wall.png", Color(1.0, 0.95, 0.9), Color(0, 0, 0, 0))
	var bump_mesh := SphereMesh.new()
	bump_mesh.radius = 0.5
	bump_mesh.height = 1.0
	bump_mesh.radial_segments = 8
	bump_mesh.rings = 4
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.3
	cone_mesh.height = 1.0
	cone_mesh.radial_segments = 6
	cone_mesh.rings = 1
	for i in _root_variants_wall.size():
		_add_multimesh("CaveWallRoot%d" % i, _root_variants_wall[i], root_mat, wall_t[i])
	for i in _root_variants_floor.size():
		_add_multimesh("CaveFloorRoot%d" % i, _root_variants_floor[i], root_mat, floor_t[i])
	_add_multimesh("CaveBumps", bump_mesh, rock_mat, bumps)
	_add_multimesh("CaveStalagmites", cone_mesh, rock_mat, cones_up)
	_add_multimesh("CaveStalactites", cone_mesh, rock_mat, cones_down)


func _add_root_column(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "RootColumn"
	body.position = Vector3(pos.x, pos.y, pos.z)
	add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.5
	cyl.height = wall_height
	cyl.radial_segments = 8
	cyl.rings = 2
	mesh_instance.mesh = cyl
	mesh_instance.material_override = _cave_mat("organic.png", Color(0.8, 0.5, 0.45), Color(0.35, 0.03, 0.06, 1.0))
	mesh_instance.position = Vector3(0, wall_height / 2.0, 0)
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = 0.5
	cs.height = wall_height
	shape.shape = cs
	shape.position = Vector3(0, wall_height / 2.0, 0)
	body.add_child(shape)
