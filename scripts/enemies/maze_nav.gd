class_name MazeNav
extends Node
## Navegación sencilla para el laberinto en cuadrícula (sin NavMesh).
##
## Crea un grafo A* con un punto por celda y por piso y conecta dos celdas vecinas
## solo si NO hay una pared entre ellas (las paredes y las puertas cerradas
## están en el grupo "maze_walls"). Así las criaturas rodean las paredes.
##
## Varios pisos: cada piso tiene sus propios puntos y las ESCALERAS unen la celda
## de la escalera (piso de abajo) con la celda de salida del piso de arriba.
## Los huecos (escalera / ascensor) no tienen punto en el piso de arriba.
## El ascensor no se usa para navegar: es solo para el jugador.
##
## Si hay un LevelBuilder en la escena (grupo "level_builder"), copia de él
## el tamaño de celda, el origen, las dimensiones y los pisos: una sola fuente de verdad.

@export var grid_size := 5                          ## Celdas en X (columnas)
@export var grid_rows := 0                          ## Celdas en Z (filas); 0 = igual que grid_size
@export var cell_size := 4.0                        ## Tamaño de cada celda (m)
@export var origin := Vector3(-10.0, 0.0, -10.0)    ## Esquina (-X, -Z) del laberinto
@export var sync_with_builder := true               ## Copiar medidas del LevelBuilder

var floors := 1                                     ## Cantidad de pisos
var floor_step := 3.4                               ## Altura entre pisos (m)
var stairs: Array = []                              ## [{cell: Vector2i, dir: Vector2i}]
var blocked_upper := {}                             ## Celdas sin piso arriba (huecos): Vector2i -> true
var astar := AStar3D.new()
var built := false


func _rows() -> int:
	return grid_rows if grid_rows > 0 else grid_size


func _count() -> int:
	return grid_size * _rows()


func _id(cell: Vector2i, floor_index := 0) -> int:
	return floor_index * _count() + cell.y * grid_size + cell.x


func _is_stair(cell: Vector2i) -> bool:
	for stair: Dictionary in stairs:
		if stair["cell"] == cell:
			return true
	return false


## Centro (en coordenadas del mundo) de una celda.
func cell_center(cell: Vector2i, floor_index := 0) -> Vector3:
	return origin + Vector3((cell.x + 0.5) * cell_size, floor_index * floor_step, (cell.y + 0.5) * cell_size)


## Celda del laberinto que contiene una posición del mundo.
func world_to_cell(pos: Vector3) -> Vector2i:
	_ensure_built()
	var local := pos - origin
	return Vector2i(
		clampi(floori(local.x / cell_size), 0, grid_size - 1),
		clampi(floori(local.z / cell_size), 0, _rows() - 1))


## Piso (0, 1...) en el que está una posición del mundo.
func floor_of(pos: Vector3) -> int:
	_ensure_built()
	# Un punto pegado al techo del piso 0 (lámparas, sirena) sigue siendo del piso 0.
	return clampi(floori((pos.y - origin.y + 0.2) / floor_step), 0, floors - 1)


# Punto del grafo más cercano a una posición del mundo.
func _point_at(pos: Vector3) -> int:
	var cell := world_to_cell(pos)
	if _is_stair(cell):
		return _id(cell, 0)
	var id := _id(cell, floor_of(pos))
	if astar.has_point(id):
		return id
	return _id(cell, 0)


## ¿Existe un camino entre dos posiciones del mundo?
func is_reachable(from: Vector3, to: Vector3) -> bool:
	_ensure_built()
	return not astar.get_id_path(_point_at(from), _point_at(to)).is_empty()


## Largo (m) del camino real entre dos posiciones; INF si no hay camino.
func path_length(from: Vector3, to: Vector3) -> float:
	_ensure_built()
	var ids := astar.get_id_path(_point_at(from), _point_at(to))
	if ids.is_empty():
		return INF
	var total := 0.0
	var previous := Vector2(from.x, from.z)
	for id in ids:
		var point := astar.get_point_position(id)
		var flat := Vector2(point.x, point.z)
		total += previous.distance_to(flat)
		previous = flat
	return total + previous.distance_to(Vector2(to.x, to.z))


## Centro de una celda al azar, distinta a la que contiene `avoid_near` y
## ALCANZABLE desde ella (así no elige habitaciones aún cerradas con llave).
func random_cell_center(avoid_near: Vector3) -> Vector3:
	var start := _point_at(avoid_near)
	var current := world_to_cell(avoid_near)
	for i in 60:
		var cell := Vector2i(randi() % grid_size, randi() % _rows())
		var floor_index := randi() % floors
		var id := _id(cell, floor_index)
		if id == start or not astar.has_point(id):
			continue
		if astar.get_id_path(start, id).is_empty():
			continue
		return astar.get_point_position(id) if not (cell == current and floor_index == 0) else cell_center(cell, floor_index)
	return cell_center(current, floor_of(avoid_near))


## Centro de una celda al azar, ALCANZABLE y a como mucho `max_steps` celdas de
## camino de `from_pos`. Sirve para que la criatura patrulle cerca de su zona
## en vez de recorrer todo el mapa.
func random_cell_near(from_pos: Vector3, max_steps: int) -> Vector3:
	var start := _point_at(from_pos)
	var current := world_to_cell(from_pos)
	var current_floor := floor_of(from_pos)
	for i in 60:
		var cell := current + Vector2i(randi_range(-max_steps, max_steps), randi_range(-max_steps, max_steps))
		if cell.x < 0 or cell.y < 0 or cell.x >= grid_size or cell.y >= _rows():
			continue
		var floor_index := current_floor
		if floors > 1 and randf() < 0.25:
			floor_index = randi() % floors      # a veces patrulla por la escalera al otro piso
		var id := _id(cell, floor_index)
		if id == start or not astar.has_point(id):
			continue
		var ids := astar.get_id_path(start, id)
		if ids.is_empty() or ids.size() - 1 > max_steps:
			continue
		return astar.get_point_position(id)
	return cell_center(current, current_floor)


## Ruta de puntos (centros de celda) desde `from` hasta `to`.
## El último punto es el destino exacto. Si no hay camino devuelve una lista vacía.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	_ensure_built()
	var result := PackedVector3Array()
	var ids := astar.get_id_path(_point_at(from), _point_at(to))
	if ids.is_empty():
		return result
	for id in ids:
		result.append(astar.get_point_position(id))
	result.append(Vector3(to.x, to.y, to.z))
	return result


## Vuelve a construir el grafo (se llama cuando se abre una puerta).
func rebuild() -> void:
	astar.clear()
	built = false
	_ensure_built()


func _sync_from_builder() -> void:
	var builder := get_tree().get_first_node_in_group("level_builder")
	if builder == null:
		return
	cell_size = float(builder.get("cell_size"))
	origin = builder.get("origin")
	var cells: Vector2i = builder.call("grid_cells")
	grid_size = cells.x
	grid_rows = cells.y
	floors = int(builder.call("floor_count"))
	floor_step = float(builder.call("floor_step"))
	stairs = builder.call("stair_cells")
	blocked_upper.clear()
	for cell: Vector2i in builder.call("opening_cells"):
		blocked_upper[cell] = true


# El grafo se construye la primera vez que se pide una ruta,
# cuando todas las paredes ya están en la escena.
func _ensure_built() -> void:
	if built:
		return
	built = true
	if sync_with_builder:
		_sync_from_builder()
	var rows := _rows()
	var walls := get_tree().get_nodes_in_group("maze_walls")
	for f in floors:
		for x in grid_size:
			for y in rows:
				var cell := Vector2i(x, y)
				if f > 0 and blocked_upper.has(cell):
					continue
				var center := cell_center(cell, f)
				if f == 0 and _is_stair(cell):
					center.y += floor_step * 0.5         # punto a media altura de la rampa
				astar.add_point(_id(cell, f), center)
	for f in floors:
		for x in grid_size:
			for y in rows:
				var cell := Vector2i(x, y)
				if not astar.has_point(_id(cell, f)):
					continue
				for neighbour: Vector2i in [cell + Vector2i.RIGHT, cell + Vector2i.DOWN]:
					if neighbour.x >= grid_size or neighbour.y >= rows:
						continue
					if not astar.has_point(_id(neighbour, f)):
						continue
					if not _wall_between(walls, cell, neighbour, f):
						astar.connect_points(_id(cell, f), _id(neighbour, f))
	# Escaleras: celda de la rampa (piso 0) <-> celda de salida del piso de arriba.
	for stair: Dictionary in stairs:
		var cell: Vector2i = stair["cell"]
		var top: Vector2i = cell + (stair["dir"] as Vector2i)
		if floors > 1 and astar.has_point(_id(top, 1)):
			astar.connect_points(_id(cell, 0), _id(top, 1))


# Hay pared entre dos celdas si alguna pared de ese piso está justo en el punto medio.
func _wall_between(walls: Array[Node], a: Vector2i, b: Vector2i, floor_index: int) -> bool:
	var middle := (cell_center(a, floor_index) + cell_center(b, floor_index)) / 2.0
	for wall: Node3D in walls:
		var offset := wall.global_position - middle
		if absf(offset.y) > 1.2:
			continue
		offset.y = 0.0
		if offset.length() < 0.5:
			return true
	return false
