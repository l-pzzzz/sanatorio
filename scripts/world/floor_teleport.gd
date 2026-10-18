class_name FloorTeleport
extends Node
## Si el jugador pasa un rato en otro piso, la criatura aparece por una escalera de ese piso
## (lejos y sin verte), con un aviso sonoro antes. Solo en dificultad media y difícil.

var creature: CharacterBody3D
var is_bat := true
var nav: MazeNav
var player: Node3D

var away_time := 0.0
var cooldown := 0.0
var warning_left := -1.0
var check_t := 0.0
var last_noise := -100.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	nav = get_tree().get_first_node_in_group("maze_nav")
	NoiseManager.noise_emitted.connect(_on_noise)
	cooldown = 10.0   # no aparece nada más empezar


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_noise(pos: Vector3, loudness: float) -> void:
	if nav and player and nav.floor_of(pos) == nav.floor_of(player.global_position) and loudness > 0.15:
		last_noise = _now()


func _physics_process(delta: float) -> void:
	if nav == null or player == null or not is_instance_valid(creature):
		return
	cooldown = maxf(0.0, cooldown - delta)
	if creature.get("stun_left") != null and creature.stun_left > 0.0:
		away_time = 0.0
		warning_left = -1.0
		return
	if warning_left >= 0.0:
		warning_left -= delta
		if warning_left < 0.0:
			_do_teleport()
		return
	var pf: int = nav.floor_of(player.global_position)
	var cf: int = nav.floor_of(creature.global_position)
	if pf == cf or cooldown > 0.0:
		away_time = 0.0
		return
	var chasing := false
	if is_bat:
		chasing = creature.state == creature.State.HUNT and _now() - creature.last_seen_time < 4.0
	else:
		chasing = _now() - last_noise > 3.0   # el Eco solo reacciona si haces ruido arriba
	if chasing:
		away_time = 0.0
		return
	away_time += delta
	if away_time >= float(Difficulty.get_value("tp_wait")):
		away_time = 0.0
		warning_left = 2.5
		# aviso: algo se mueve por la escalera
		Sfx.play(self, "kill_screech_bat" if is_bat else "kill_roar_eco", -16.0)


func _candidates(pf: int) -> Array:
	var out: Array = []
	for st in nav.stairs:
		for k in [-1, 0, 1, 2]:
			var cell: Vector2i = st["cell"] + st["dir"] * k
			var pos: Vector3 = nav.cell_center(cell, pf)
			if nav.floor_of(pos) != pf:
				continue
			var d: float = nav.path_length(pos, player.global_position)
			if d == INF or d < 12.0:
				continue
			out.append([pos, d])
	return out


func _do_teleport() -> void:
	var pf: int = nav.floor_of(player.global_position)
	if nav.floor_of(creature.global_position) == pf:
		return
	var cands := _candidates(pf)
	if cands.is_empty():
		cooldown = 5.0
		return
	# preferir los que el jugador NO ve
	var space := creature.get_world_3d().direct_space_state
	var hidden_ones: Array = []
	for c in cands:
		var q := PhysicsRayQueryParameters3D.create(c[0] + Vector3.UP * 1.4, player.global_position + Vector3.UP * 1.4, 1)
		if not space.intersect_ray(q).is_empty():
			hidden_ones.append(c)
	var pool := hidden_ones if not hidden_ones.is_empty() else cands
	var pick: Array = pool[randi() % pool.size()]
	creature.global_position = pick[0] + Vector3.UP * 0.3
	creature.velocity = Vector3.ZERO
	cooldown = float(Difficulty.get_value("tp_cooldown"))
	creature.call("_on_teleported", player.global_position)
	Sfx.play(self, "kill_screech_bat" if is_bat else "kill_roar_eco", -10.0)
