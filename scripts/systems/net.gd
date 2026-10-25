extends Node
## Multijugador cooperativo por red local (autoload "Net"). De 2 a 4 jugadores.
##
## Quién manda en qué:
##   - El ANFITRIÓN simula las criaturas (a quién persiguen, qué oyen, a quién atrapan) y
##     manda su posición y estado a los demás ~15 veces por segundo.
##   - Cada jugador mueve SU personaje y manda su posición ~20 veces por segundo; los demás
##     lo ven como un "títere" (PlayerCharacter con is_remote = true y su cuerpo 3D).
##   - Cuando alguien usa algo (tecla E), antes de hacerlo localmente se envía la acción y
##     cada pantalla la repite con el títere de ese jugador: puertas, objetos, válvulas,
##     ascensores y misiones avanzan igual en todas.
##   - El ruido de los clientes (pasos, voz, botellas) se reenvía al anfitrión.
##   - Si atrapan a alguien, ve su muerte y pasa a observar a un compañero; si atrapan a
##     todos, pierde el equipo. Solo el anfitrión reinicia o pasa de nivel.
##
## Sin red (un jugador) nada de esto se activa y el juego funciona como siempre.

signal players_changed
signal lobby_changed
signal session_ended(reason: String)
signal joined
signal games_changed

const PORT := 24680
const DISCOVERY_PORT := 24681
const MAX_PLAYERS := 4
const GAME_ID := "sanatorio-lan"
const PROTOCOL := 1
const SEND_RATE := 20.0
const ENEMY_RATE := 15.0
const MENU_SCENE := "res://scenes/menu_principal.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SPAWN_OFFSETS := [Vector3.ZERO, Vector3(1.1, 0, 0), Vector3(-1.1, 0, 0), Vector3(0, 0, 1.1)]
const LEVELS := [
	["SANATORIO SANTA MARTA", "res://scenes/sanatorio.tscn"],
	["NIVEL 2: LOS SÓTANOS", "res://scenes/nivel_2_sotano.tscn"],
	["NIVEL 3: LA RAÍZ", "res://scenes/nivel_3_raiz.tscn"],
]

var players := {}                 ## id -> {"name": String}
var my_name := "Jugador"
var in_game := false
var lobby_difficulty := 1
var lobby_level := 0
var menu_message := ""            ## Motivo a mostrar en el menú al volver (desconexión, rechazo...)

var replaying := false            ## true mientras se repite la acción de otro jugador
var local_dead := false
var dead := {}                    ## id -> true en el nivel actual
var puppets := {}                 ## id -> PlayerCharacter remoto
var level_key := ""
var mission: MissionManager

var enemy_snap := {}              ## ruta -> último estado recibido del anfitrión
var enemy_hold := {}              ## ruta -> instante hasta el que no se mueve (secuencia de muerte)
var spectate_id := 0
var spectate_layer: CanvasLayer
var spectate_label: Label

var found := {}                   ## ip -> {"name", "players", "max", "t"}
var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _disc_t := 0.0
var _send_t := 0.0
var _enemy_t := 0.0
var _target_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		my_name = str(config.get_value("net", "name", ""))
	if my_name.strip_edges() == "":
		my_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else OS.get_environment("USER")
	if my_name.strip_edges() == "":
		my_name = "Jugador"
	my_name = my_name.substr(0, 16)


# ================================================================== estado

func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func is_client() -> bool:
	return is_online() and not multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func player_name(id: int) -> String:
	return str(players.get(id, {}).get("name", "Jugador %d" % id))


## Direcciones IPv4 de esta PC en la red local (para unirse escribiendo la IP).
func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


func set_my_name(n: String) -> void:
	my_name = n.strip_edges().substr(0, 16)
	if my_name == "":
		my_name = "Jugador"
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("net", "name", my_name)
	config.save("user://settings.cfg")


# ================================================================== sesión

## Crea la partida en esta PC. Devuelve OK o el error (p. ej. el puerto ocupado).
func host_game() -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": my_name}}
	in_game = false
	_start_broadcast()
	players_changed.emit()
	return OK


## Se conecta a la partida de `ip`. El resultado llega por las señales joined / session_ended.
func join_game(ip: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


## Cierra la conexión (sin cambiar de escena).
func leave() -> void:
	_stop_broadcast()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	_reset_level_state()


## Sale de la partida y vuelve al menú principal.
func leave_to_menu(reason := "") -> void:
	leave()
	menu_message = reason
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_connected_to_server() -> void:
	_register.rpc_id(1, my_name, PROTOCOL)


func _on_connection_failed() -> void:
	leave()
	session_ended.emit("No se pudo conectar con esa partida.")


func _on_server_disconnected() -> void:
	var was_in_game := in_game
	leave()
	if was_in_game:
		leave_to_menu("Se perdió la conexión con el anfitrión.")
	else:
		session_ended.emit("El anfitrión cerró la partida.")


func _on_peer_connected(_id: int) -> void:
	pass   # se registra con _register


func _on_peer_disconnected(id: int) -> void:
	var name_left := player_name(id)
	players.erase(id)
	if puppets.has(id):
		if is_instance_valid(puppets[id]):
			puppets[id].queue_free()
		puppets.erase(id)
	if spectate_id == id:
		_spectate_next()
	if is_host():
		_set_players.rpc(players)
		if in_game:
			_check_team_wipe("TODOS FUERON ATRAPADOS")
	players_changed.emit()
	_toast(Lang.t("%s se desconectó.") % name_left)


@rpc("any_peer", "reliable")
func _register(player_label: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL:
		reason = "Versión distinta del juego: actualicen todos a la misma."
	elif in_game:
		reason = "La partida ya empezó."
	elif players.size() >= MAX_PLAYERS:
		reason = "La partida está llena."
	if reason != "":
		_rejected.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))
		return
	players[id] = {"name": player_label.strip_edges().substr(0, 16) if player_label.strip_edges() != "" else "Jugador %d" % players.size()}
	_set_players.rpc(players)
	_set_lobby.rpc_id(id, lobby_difficulty, lobby_level)
	players_changed.emit()


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave()
	session_ended.emit(reason)


@rpc("authority", "reliable")
func _set_players(p: Dictionary) -> void:
	var first := players.is_empty()
	players = p
	players_changed.emit()
	if first and is_client():
		joined.emit()


## El anfitrión cambia dificultad o nivel en el lobby.
func set_lobby(difficulty: int, level: int) -> void:
	lobby_difficulty = clampi(difficulty, 0, 2)
	lobby_level = clampi(level, 0, LEVELS.size() - 1)
	if is_host():
		_set_lobby.rpc(lobby_difficulty, lobby_level)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _set_lobby(difficulty: int, level: int) -> void:
	lobby_difficulty = difficulty
	lobby_level = level
	lobby_changed.emit()


## El anfitrión empieza: todos cargan el nivel elegido con la misma dificultad.
func start_game() -> void:
	if not is_host():
		return
	_stop_broadcast()
	_begin.rpc(lobby_difficulty, str(LEVELS[lobby_level][1]))


@rpc("authority", "call_local", "reliable")
func _begin(difficulty: int, scene_path: String) -> void:
	Difficulty.level = difficulty
	in_game = true
	_goto_local(scene_path)


# ================================================================== escenas

## Cambia de escena. En red solo el anfitrión puede, y arrastra a todos.
## Devuelve false si este jugador debe esperar al anfitrión.
func goto_scene(scene_path: String) -> bool:
	if not is_online():
		get_tree().paused = false
		get_tree().change_scene_to_file(scene_path)
		return true
	if not is_host():
		return false
	_remote_goto.rpc(scene_path)
	return true


func reload_level() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return goto_scene(scene.scene_file_path)


@rpc("authority", "call_local", "reliable")
func _remote_goto(scene_path: String) -> void:
	_goto_local(scene_path)


func _goto_local(scene_path: String) -> void:
	_reset_level_state()
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)


func _reset_level_state() -> void:
	puppets.clear()
	dead.clear()
	enemy_snap.clear()
	enemy_hold.clear()
	local_dead = false
	spectate_id = 0
	mission = null
	level_key = ""
	spectate_layer = null
	spectate_label = null


# ================================================================== nivel

## La llama MissionManager._ready al cargar un nivel.
func on_level_ready(mm: MissionManager) -> void:
	if not is_online() or not in_game:
		return
	# Diferido: mientras el nivel arma sus hijos no se le pueden agregar nodos.
	_setup_level.call_deferred(mm)


func _setup_level(mm: MissionManager) -> void:
	if not is_instance_valid(mm) or not mm.is_inside_tree():
		return
	_reset_level_state()
	mission = mm
	level_key = get_tree().current_scene.scene_file_path
	var ids: Array = players.keys()
	ids.sort()
	var me := my_id()
	var p := mm.player
	if p:
		var spawn := p.global_transform
		p.net_id = me
		p.global_position += spawn.basis * SPAWN_OFFSETS[maxi(ids.find(me), 0) % SPAWN_OFFSETS.size()]
		p.inventory_changed.connect(_send_inventory)
		for id in ids:
			if id != me:
				_spawn_puppet(int(id), spawn)
	if is_client():
		for enemy in get_tree().get_nodes_in_group("enemies"):
			_make_enemy_puppet(enemy)
	_build_spectate_hud()


func _spawn_puppet(id: int, spawn: Transform3D) -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	var pup := packed.instantiate() as PlayerCharacter
	pup.is_remote = true
	pup.net_id = id
	pup.name = "NetPlayer_%d" % id
	pup.remove_from_group("player")
	pup.add_to_group("remote_players")
	pup.net_label = player_name(id)
	get_tree().current_scene.add_child(pup)
	pup.global_transform = spawn
	pup.visible = false            # hasta recibir su primera posición
	puppets[id] = pup
	# Si la criatura persigue a este jugador, que note cuando se esconde.
	pup.hiding_changed.connect(func(h: bool) -> void:
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.get("player") == pup and enemy.has_method("_on_player_hiding_changed"):
				enemy.call("_on_player_hiding_changed", h))


## En los clientes las criaturas no piensan: solo copian lo que manda el anfitrión.
func _make_enemy_puppet(enemy: Node) -> void:
	enemy.set_physics_process(false)
	for child in enemy.get_children():
		if child is FloorTeleport:
			child.set_physics_process(false)
	if enemy.has_method("_on_noise_emitted") and NoiseManager.noise_emitted.is_connected(Callable(enemy, "_on_noise_emitted")):
		NoiseManager.noise_emitted.disconnect(Callable(enemy, "_on_noise_emitted"))


func _physics_process(delta: float) -> void:
	if not is_online() or not in_game or mission == null or not is_instance_valid(mission):
		return
	var p := mission.player
	_send_t -= delta
	if _send_t <= 0.0 and p and is_instance_valid(p):
		_send_t = 1.0 / SEND_RATE
		_player_state.rpc(level_key, p.global_position, p.rotation.y, p.head.rotation.x, p.height,
			p.velocity, p.flashlight_on, p.is_hidden, local_dead)
	if is_host():
		_target_t -= delta
		if _target_t <= 0.0:
			_target_t = 0.2
			_pick_targets()
		_enemy_t -= delta
		if _enemy_t <= 0.0:
			_enemy_t = 1.0 / ENEMY_RATE
			_send_enemies()
	else:
		_drive_enemies(delta)


# ------------------------------------------------------------ jugadores

@rpc("any_peer", "unreliable_ordered")
func _player_state(key: String, pos: Vector3, yaw: float, pitch: float, h: float, vel: Vector3,
		flash: bool, hidden: bool, is_dead: bool) -> void:
	if key != level_key:
		return
	var pup := puppets.get(multiplayer.get_remote_sender_id()) as PlayerCharacter
	if pup and is_instance_valid(pup):
		pup.net_apply(pos, yaw, pitch, h, vel, flash, hidden, is_dead or dead.has(pup.net_id))


func _send_inventory() -> void:
	if is_online() and in_game and mission and mission.player:
		_player_inventory.rpc(level_key, mission.player.inventory, mission.player.has_flashlight)


@rpc("any_peer", "reliable")
func _player_inventory(key: String, inventory: Dictionary, has_flashlight: bool) -> void:
	if key != level_key:
		return
	var pup := puppets.get(multiplayer.get_remote_sender_id()) as PlayerCharacter
	if pup and is_instance_valid(pup):
		pup.inventory = inventory.duplicate()
		pup.has_flashlight = has_flashlight


# ------------------------------------------------------------ acciones (tecla E)

## La llama el jugador local justo ANTES de usar algo: las demás pantallas lo repiten.
func send_interact(target: Node) -> void:
	if is_online() and in_game and target:
		_remote_interact.rpc(level_key, encode_path(target))


func send_leave_hiding() -> void:
	if is_online() and in_game:
		_remote_leave_hiding.rpc(level_key)


@rpc("any_peer", "reliable")
func _remote_interact(key: String, path: String) -> void:
	if key != level_key:
		return
	var actor := puppets.get(multiplayer.get_remote_sender_id()) as PlayerCharacter
	var target := decode_path(path)
	if actor == null or target == null or not target.has_method("interact"):
		return
	replaying = true
	target.call("interact", actor)
	replaying = false


@rpc("any_peer", "reliable")
func _remote_leave_hiding(key: String) -> void:
	if key != level_key:
		return
	var actor := puppets.get(multiplayer.get_remote_sender_id()) as PlayerCharacter
	if actor and actor.is_hidden:
		replaying = true
		actor.leave_hiding()
		replaying = false


## Ruta de un nodo dentro del nivel, estable entre PCs. Los nodos creados por código sin
## nombre ("@StaticBody3D@123") se identifican por su clase y su orden entre hermanos.
func encode_path(node: Node) -> String:
	var root := get_tree().current_scene
	var segs := PackedStringArray()
	var n := node
	while n != null and n != root:
		var nm := str(n.name)
		if nm.begins_with("@"):
			var k := 0
			for s in n.get_parent().get_children():
				if s == n:
					break
				if str(s.name).begins_with("@") and s.get_class() == n.get_class():
					k += 1
			nm = "@%s#%d" % [n.get_class(), k]
		segs.insert(0, nm)
		n = n.get_parent()
	return "/".join(segs)


func decode_path(path: String) -> Node:
	var n: Node = get_tree().current_scene
	if n == null:
		return null
	for seg in path.split("/", false):
		if seg.begins_with("@"):
			var parts := seg.substr(1).split("#")
			var want := int(parts[1])
			var k := 0
			var hit: Node = null
			for s in n.get_children():
				if str(s.name).begins_with("@") and s.get_class() == parts[0]:
					if k == want:
						hit = s
						break
					k += 1
			n = hit
		else:
			n = n.get_node_or_null(NodePath(seg))
		if n == null:
			return null
	return n


# ------------------------------------------------------------ ruido y sonido

## El ruido de un cliente se le reenvía al anfitrión (sus criaturas son las que oyen).
func relay_noise(pos: Vector3, loudness: float) -> void:
	if is_client() and in_game:
		_remote_noise.rpc_id(1, level_key, pos, loudness)


@rpc("any_peer", "unreliable")
func _remote_noise(key: String, pos: Vector3, loudness: float) -> void:
	if key == level_key and is_host():
		NoiseManager.emit_noise_from_network(pos, loudness)


## Sonidos que hacen las criaturas en el anfitrión (chillidos, aturdimiento...).
func should_relay_sfx(from: Node) -> bool:
	if not is_host() or not in_game or from == null:
		return false
	var n := from
	while n != null:
		if n.is_in_group("enemies"):
			return true
		n = n.get_parent()
	return false


func relay_sfx(sound: String, volume_db: float) -> void:
	_remote_sfx.rpc(level_key, sound, volume_db)


@rpc("authority", "unreliable")
func _remote_sfx(key: String, sound: String, volume_db: float) -> void:
	if key == level_key and get_tree().current_scene:
		Sfx.play(get_tree().current_scene, sound, volume_db)


## Sonido 3D de una criatura (chasquidos y mímica del Eco). Devuelve true si este jugador
## NO debe reproducirlo por su cuenta (cliente: lo manda el anfitrión).
func relay_creature_sound(enemy: Node, sound: String, at: Vector3, volume_db: float, unit_size: float, max_distance: float) -> bool:
	if not is_online() or not in_game:
		return false
	if is_host():
		_remote_sound3d.rpc(level_key, encode_path(enemy), sound, at, volume_db, unit_size, max_distance)
		return false
	return not replaying


@rpc("authority", "unreliable")
func _remote_sound3d(key: String, path: String, sound: String, at: Vector3, volume_db: float, unit_size: float, max_distance: float) -> void:
	if key != level_key:
		return
	var enemy := decode_path(path)
	if enemy and enemy.has_method("_play_at"):
		replaying = true
		enemy.call("_play_at", sound, at, volume_db, unit_size, max_distance)
		replaying = false


# ------------------------------------------------------------ misiones

## Eventos que solo ocurren en el anfitrión (aturdir a una criatura) se copian a todos.
func relay_report(event: String, id: String) -> void:
	if is_host() and in_game:
		_remote_report.rpc(level_key, event, id)


@rpc("authority", "reliable")
func _remote_report(key: String, event: String, id: String) -> void:
	if key == level_key and mission:
		mission.report(event, id)


# ------------------------------------------------------------ criaturas

## Cada criatura persigue al jugador vivo más cercano (en su mismo piso si puede).
func _pick_targets() -> void:
	var candidates: Array[PlayerCharacter] = []
	if mission.player and not local_dead:
		candidates.append(mission.player)
	for id in puppets:
		var pup := puppets[id] as PlayerCharacter
		if is_instance_valid(pup) and pup.net_has_state and not dead.has(id):
			candidates.append(pup)
	if candidates.is_empty():
		return
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_physics_processing():
			continue      # devorando: no cambia de víctima a mitad
		if enemy is EcoCreature and (enemy.state == EcoCreature.State.ATTACK or enemy.state == EcoCreature.State.EAR):
			continue      # atacando o con la oreja en un casillero: sigue con el mismo
		var best: PlayerCharacter = null
		var best_d := INF
		for c in candidates:
			var d := enemy.global_position.distance_to(c.global_position) + absf(enemy.global_position.y - c.global_position.y) * 4.0
			if d < best_d:
				best_d = d
				best = c
		if best and enemy.get("player") != best:
			enemy.set("player", best)


func _send_enemies() -> void:
	var data: Array = []
	for enemy: Node3D in get_tree().get_nodes_in_group("enemies"):
		var e := enemy as CharacterBody3D
		data.append([encode_path(e), e.global_position, e.rotation.y, e.velocity, int(e.get("state")),
			float(e.get("stun_left")), str(e.get("stun_kind")), e.get("noise_target") if e.get("noise_target") != null else Vector3.ZERO,
			float(e.get("attack_left")) if e.get("attack_left") != null else 0.0])
	if not data.is_empty():
		_enemy_state.rpc(level_key, data)


@rpc("authority", "unreliable_ordered")
func _enemy_state(key: String, data: Array) -> void:
	if key != level_key:
		return
	for row in data:
		enemy_snap[row[0]] = row


func _drive_enemies(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for path in enemy_snap:
		if float(enemy_hold.get(path, 0.0)) > now:
			continue
		var e := decode_path(path) as CharacterBody3D
		if e == null:
			continue
		var row: Array = enemy_snap[path]
		var target: Vector3 = row[1]
		if e.global_position.distance_to(target) > 6.0:
			e.global_position = target                 # teletransporte (cambio de piso)
		else:
			e.global_position = e.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
		e.rotation.y = lerp_angle(e.rotation.y, float(row[2]), 1.0 - exp(-12.0 * delta))
		e.velocity = row[3]
		e.set("state", int(row[4]))
		var stun_left := float(row[5])
		e.set("stun_left", stun_left)
		e.set("noise_target", row[7])
		if e.get("attack_left") != null:
			e.set("attack_left", float(row[8]))
		_stun_light(e, stun_left, str(row[6]))
		if e.has_method("_animate"):
			e.call("_animate", delta)


func _stun_light(e: Node3D, stun_left: float, kind: String) -> void:
	var light := e.get("stun_light") as OmniLight3D
	if stun_left > 0.0:
		if light == null:
			light = OmniLight3D.new()
			light.omni_range = 4.5
			light.position = Vector3(0.0, 1.4, 0.0)
			e.add_child(light)
			e.set("stun_light", light)
		var colors: Dictionary = e.get("STUN_COLORS") if e.get("STUN_COLORS") != null else {}
		light.light_color = colors.get(kind, Color.WHITE)
		light.light_energy = 1.2 + sin(Time.get_ticks_msec() / 1000.0 * 22.0) * 0.5
		light.visible = true
	elif light:
		light.visible = false


## Aturdir desde un cliente: se le pide al anfitrión. Devuelve 1 si funcionó, 0 si no,
## -1 si la respuesta llega después (cliente).
func try_stun(enemy: Node, duration: float, kind: String, source_pos: Vector3) -> int:
	if not enemy.has_method("stun"):
		return 0
	if not is_client() or not in_game:
		return 1 if enemy.call("stun", duration, kind, source_pos) else 0
	_request_stun.rpc_id(1, level_key, encode_path(enemy), duration, kind, source_pos)
	return -1


@rpc("any_peer", "reliable")
func _request_stun(key: String, path: String, duration: float, kind: String, source_pos: Vector3) -> void:
	if key != level_key or not is_host():
		return
	var enemy := decode_path(path)
	var ok := enemy != null and enemy.has_method("stun") and bool(enemy.call("stun", duration, kind, source_pos))
	_stun_result.rpc_id(multiplayer.get_remote_sender_id(), kind, ok)


@rpc("authority", "reliable")
func _stun_result(kind: String, ok: bool) -> void:
	if kind == "flash":
		_toast(Lang.t("¡La luz lo cegó!") if ok else Lang.t("La bengala ilumina... pero no había nada que cegar."), 2.0)
	elif ok:
		Sfx.play(get_tree().current_scene, "dart_hit", -2.0)
		_toast(Lang.t("¡Le diste! Está aturdida unos segundos."), 2.0)
	else:
		_toast(Lang.t("Ya se está recuperando: no le hace efecto."), 2.0)


# ------------------------------------------------------------ muerte y espectador

## MissionManager.on_player_caught en red: decide de quién es la muerte.
func handle_caught(mm: MissionManager, message: String, killer: Node3D) -> void:
	var victim: Node = null
	if killer != null and killer.is_in_group("enemies"):
		victim = killer.get("player")
	if victim == null or not is_instance_valid(victim):
		victim = mm.player
	if is_host() and killer != null and killer.is_in_group("enemies"):
		_resume_enemy_later(killer)
	if victim is PlayerCharacter and (victim as PlayerCharacter).is_remote:
		var pup := victim as PlayerCharacter
		_you_were_caught.rpc_id(pup.net_id, level_key, message, encode_path(killer) if killer else "")
		return
	_local_death(message, killer)


@rpc("authority", "reliable")
func _you_were_caught(key: String, message: String, killer_path: String) -> void:
	if key != level_key or mission == null:
		return
	var killer := decode_path(killer_path) as Node3D if killer_path != "" else null
	if killer_path != "":
		enemy_hold[killer_path] = Time.get_ticks_msec() / 1000.0 + KillSequence.TOTAL + 1.0
	_local_death(message, killer)


func _local_death(message: String, killer: Node3D) -> void:
	if local_dead or mission == null:
		return
	local_dead = true
	_peer_died.rpc(level_key, my_id(), message)
	mission.net_local_death(message, killer)


@rpc("any_peer", "call_local", "reliable")
func _peer_died(key: String, id: int, message: String) -> void:
	if key != level_key:
		return
	dead[id] = true
	if id != my_id():
		var pup := puppets.get(id) as PlayerCharacter
		if pup and is_instance_valid(pup):
			pup.net_set_dead(true)
		_toast(Lang.t("¡%s fue atrapado!") % player_name(id), 3.5)
		if spectate_id == id:
			_spectate_next()
	if is_host():
		_check_team_wipe(message)


func _check_team_wipe(message: String) -> void:
	for id in players:
		if not dead.has(id):
			return
	# Que el último vea su muerte completa antes de la pantalla de derrota.
	var key := level_key
	get_tree().create_timer(KillSequence.TOTAL + 0.3).timeout.connect(func() -> void:
		if key == level_key and is_host():
			_team_lost.rpc(level_key, message))


@rpc("authority", "call_local", "reliable")
func _team_lost(key: String, message: String) -> void:
	if key != level_key or mission == null:
		return
	if spectate_label:
		spectate_label.visible = false
	mission.net_team_lost(message)


func _resume_enemy_later(enemy: Node) -> void:
	get_tree().create_timer(KillSequence.TOTAL + 0.8).timeout.connect(func() -> void:
		if not is_instance_valid(enemy) or mission == null or mission.state != MissionManager.State.PLAYING:
			return
		enemy.set_physics_process(true)
		if enemy.has_method("_start_wander"):
			enemy.call("_start_wander"))


## Tras la secuencia de muerte: la cámara pasa a un compañero vivo.
func start_spectating() -> void:
	if spectate_label:
		spectate_label.visible = true
	_spectate_next()


func _spectate_next() -> void:
	if not local_dead:
		return
	var ids: Array = puppets.keys()
	ids.sort()
	var start := ids.find(spectate_id)
	var prev := puppets.get(spectate_id) as PlayerCharacter
	if prev and is_instance_valid(prev) and prev.body and prev.body.head_mesh:
		prev.body.head_mesh.visible = true
	spectate_id = 0
	for k in ids.size():
		var id: int = ids[(start + 1 + k) % ids.size()]
		var pup := puppets[id] as PlayerCharacter
		if is_instance_valid(pup) and not dead.has(id):
			spectate_id = id
			(pup.get_node("Head/Camera3D") as Camera3D).make_current()
			if pup.body and pup.body.head_mesh:
				pup.body.head_mesh.visible = false
			break
	if spectate_label:
		spectate_label.text = Lang.t("TE ATRAPARON") + "\n" + (Lang.t("Observando a %s   ·   [Clic] cambiar") % player_name(spectate_id) if spectate_id != 0 else Lang.t("Esperando..."))


func _unhandled_input(event: InputEvent) -> void:
	if local_dead and in_game and event is InputEventMouseButton and event.pressed and not PauseMenu.is_open:
		_spectate_next()


func _build_spectate_hud() -> void:
	spectate_layer = CanvasLayer.new()
	spectate_layer.layer = 12
	get_tree().current_scene.add_child(spectate_layer)
	spectate_label = Label.new()
	spectate_label.visible = false
	spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectate_label.add_theme_font_size_override("font_size", 22)
	spectate_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
	spectate_label.add_theme_color_override("font_outline_color", Color.BLACK)
	spectate_label.add_theme_constant_override("outline_size", 6)
	spectate_label.anchor_left = 0.2
	spectate_label.anchor_right = 0.8
	spectate_label.anchor_top = 0.6
	spectate_label.anchor_bottom = 0.72
	spectate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spectate_layer.add_child(spectate_label)


func _toast(text: String, seconds := 3.0) -> void:
	if mission and is_instance_valid(mission):
		mission.show_toast(text, seconds)


# ================================================================== descubrimiento LAN

## El anfitrión avisa cada segundo "aquí hay una partida" por difusión UDP.
func _start_broadcast() -> void:
	_stop_broadcast()
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_disc_t = 0.0


func _stop_broadcast() -> void:
	if _broadcaster:
		_broadcaster.close()
	_broadcaster = null


## La pantalla de "Unirse" escucha esos avisos.
func start_listening() -> void:
	stop_listening()
	found.clear()
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		push_warning("Net: no se pudo escuchar el puerto %d (¿otra copia del juego abierta en esta PC?)" % DISCOVERY_PORT)
		_listener = null


func stop_listening() -> void:
	if _listener:
		_listener.close()
	_listener = null


func _process(delta: float) -> void:
	if _broadcaster and is_host() and not in_game:
		_disc_t -= delta
		if _disc_t <= 0.0:
			_disc_t = 1.0
			var msg := JSON.stringify({"game": GAME_ID, "v": PROTOCOL, "name": my_name, "players": players.size(), "max": MAX_PLAYERS}).to_utf8_buffer()
			for dest in ["255.255.255.255", "127.0.0.1"]:
				_broadcaster.set_dest_address(dest, DISCOVERY_PORT)
				_broadcaster.put_packet(msg)
	if _listener:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var info: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if info is Dictionary and info.get("game") == GAME_ID and int(info.get("v", 0)) == PROTOCOL:
				info["t"] = Time.get_ticks_msec() / 1000.0
				changed = changed or not found.has(ip) or int(found[ip].get("players", 0)) != int(info.get("players", 0))
				found[ip] = info
		var now := Time.get_ticks_msec() / 1000.0
		for ip in found.keys():
			if now - float(found[ip]["t"]) > 3.5:
				found.erase(ip)
				changed = true
		if changed:
			games_changed.emit()
