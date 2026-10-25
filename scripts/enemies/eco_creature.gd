class_name EcoCreature
extends CharacterBody3D
## "El Eco": criatura sin ojos cuya cabeza es una bocina acústica de carne y hongos.
##
## No ve. Caza con el oído:
##  - ECOLOCALIZACIÓN: de vez en cuando se detiene, suelta un chasquido grave y
##    escucha el rebote. Si en ese instante te mueves (incluso agachado), te
##    delata. Quieto, no existe para ella.
##  - OREJA EN EL CASILLERO: si haces ruido (micrófono) estando escondido, va hasta
##    tu casillero y pega la cabeza contra la puerta. Si sigues haciendo ruido, ataca.
##  - MÍMICA: imita sonidos que oyó (bisagras, goteo, un silbido de voz), a veces
##    desde otro lugar del mapa, para confundirte.
##  - Respira con un silbido asmático constante y le crujen las articulaciones.
##
## El modelo se arma por código (cajas, esferas y conos con el shader PS1).

enum State { PATROL, ECHO, HUNT, EAR, ATTACK }

const PS1_SHADER := "res://assets/shaders/ps1.gdshader"
const TEX_DIR := "res://assets/textures/eco/"
const MIMIC_SOUNDS: Array[String] = ["mimic_creak", "mimic_drip", "mimic_whisper"]
const TORSO_Y := 1.0

@export_group("Movimiento")
@export var patrol_speed := 1.0
@export var hunt_speed_min := 2.2
@export var hunt_speed_max := 3.4
@export var turn_speed := 5.0
@export var catch_radius := 1.3
@export var wander_cells := 3                ## Cuántas celdas se aleja al patrullar
@export var idle_min := 2.5                  ## Pausa mínima escuchando al llegar (s)
@export var idle_max := 6.0
@export var arrive_radius := 1.0
@export var waypoint_radius := 0.6
@export var replan_interval := 0.4
@export var search_time := 6.0               ## Cuánto busca en el lugar de un ruido (s)

@export_group("Oído")
@export var min_hearing_radius := 7.0
@export var max_hearing_radius := 28.0
@export var hear_wall_factor := 1.5          ## El sonido se amortigua con las paredes (camino real)

@export_group("Ecolocalización")
@export var echo_interval_min := 9.0         ## Cada cuántos segundos patrulla y suelta un chasquido
@export var echo_interval_max := 16.0
@export var echo_range := 16.0               ## Alcance del chasquido (m)
@export var echo_windup := 0.9               ## Aviso antes del chasquido (levanta la cabeza)
@export var echo_window := 0.8               ## Tiempo tras el chasquido en que te delata si te mueves
@export var echo_move_speed := 0.35          ## Velocidad desde la que cuenta como "moverse"

@export_group("Casillero")
@export var ear_time := 3.5                  ## Cuánto escucha con la oreja en la puerta (s)
@export var ear_attack_delay := 0.5          ## Si oye ruido ahí, ataca tras este tiempo (s)
@export var ear_cooldown_time := 5.0         ## Tras irse, ignora el casillero este tiempo

@export_group("Mímica")
@export var mimic_interval_min := 18.0
@export var mimic_interval_max := 35.0
@export var mimic_decoy_chance := 0.5        ## Prob. de imitar desde otro lugar del mapa

@export_group("Modelo 3D")
@export_file("*.glb", "*.gltf") var model_path := "res://assets/models/eco_model.glb"   ## Si existe, se usa en vez del modelo por código
@export var model_scale := 1.6               ## Tamaño del modelo importado (frente = -Z tras girarlo)

@export_group("Animación")
@export var anim_fps := 12.0                 ## Pasos de animación por segundo (aspecto entrecortado)
@export var attack_time := 0.5

class Limb:
	var shoulder: Node3D
	var elbow: Node3D
	var rest_shoulder := Vector3.ZERO
	var rest_elbow := Vector3.ZERO
	var phase := 0.0
	var side := 1.0
	var hind := false

var state := State.PATROL
var resume_state := State.PATROL
var player: PlayerCharacter
var nav: MazeNav

var path := PackedVector3Array()
var path_index := 0
var replan_left := 0.0
var wander_target := Vector3.ZERO
var noise_target := Vector3.ZERO
var hunt_speed := 0.0
var search_left := 0.0
var arrived := false
var idle_left := 0.0
var echoed_this_hunt := false

var echo_timer := 0.0
var echo_t := 0.0
var echo_fired := false
var echo_window_left := 0.0
var has_queued_noise := false
var queued_position := Vector3.ZERO
var queued_loudness := 0.0

var going_to_ear := false
var ear_spot: Node3D
var ear_left := 0.0
var ear_attack_left := -1.0
var ear_cooldown := 0.0

var mimic_timer := 0.0
var attack_left := 0.0
var catch_reason := "EL ECO TE DEVORÓ"

var model: Node3D
var mesh_model: Node3D                       ## Modelo importado (null si se usa el de cajas)
var skeleton: Skeleton3D
var bone_ids: Dictionary = {}
var rig_euler: Dictionary = {}
var torso: Node3D
var head_pivot: Node3D
var head_rest := Vector3.ZERO
var jaw: Node3D
var limbs: Array[Limb] = []
var anim_acc := 0.0
var gait_phase := 0.0
var idle_time := 0.0
var last_half_cycle := 0
var breath_player: AudioStreamPlayer3D


func _ready() -> void:
	collision_mask |= 4        # capa 4: barreras que solo frenan a las criaturas (boca del túnel del corazón)
	player = get_tree().get_first_node_in_group("player") as PlayerCharacter
	nav = get_tree().get_first_node_in_group("maze_nav") as MazeNav
	floor_snap_length = 0.6
	_build_model()
	_setup_breath()
	echo_timer = randf_range(echo_interval_min, echo_interval_max)
	mimic_timer = randf_range(mimic_interval_min, mimic_interval_max)
	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_start_wander.call_deferred()
	_apply_difficulty()


# ============================================================ dificultad

var flash_used := false
var allied := false            ## Nivel 3: lo que oye el Eco se lo cuenta al murciélago
var ally_cd := 0.0
var smell_t := 0.0
var tp_helper: Node


func _apply_difficulty() -> void:
	var hm: float = Difficulty.get_value("eco_hear_mul")
	min_hearing_radius *= hm
	max_hearing_radius *= hm
	search_time = Difficulty.get_value("eco_search")
	stun_immunity = Difficulty.get_value("stun_immunity")
	if Difficulty.get_value("eco_tp") and Difficulty.get_value("tp_wait") > 0.0:
		tp_helper = FloorTeleport.new()
		tp_helper.creature = self
		tp_helper.is_bat = false
		add_child(tp_helper)


## En difícil te "huele" si estás pegado a él aunque no hagas ruido.
func _smell_check(delta: float) -> void:
	var r: float = Difficulty.get_value("eco_smell")
	if r <= 0.0 or player == null or player.is_hidden:
		return
	if state != State.PATROL and state != State.HUNT:
		return
	smell_t -= delta
	if smell_t > 0.0:
		return
	smell_t = 0.5
	if absf(player.global_position.y - global_position.y) > 1.6:
		return
	var flat := player.global_position - global_position
	flat.y = 0.0
	if flat.length() < r:
		_hunt_noise(player.global_position, 0.3)


func _on_teleported(player_pos: Vector3) -> void:
	_hunt_noise(player_pos, 0.3)


func set_allied(on: bool) -> void:
	allied = on


## El murciélago vio al jugador y chilló: el Eco corre hacia allá.
func _on_ally_alert(source: Node, pos: Vector3) -> void:
	if source == self or stun_left > 0.0 or state == State.ATTACK or state == State.ECHO:
		return
	_hunt_noise(pos, 0.7)


# ============================================================ comportamiento

func _physics_process(delta: float) -> void:
	if stun_left > 0.0:
		_stunned_tick(delta)
		return
	stun_immune = maxf(0.0, stun_immune - delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_tick_timers(delta)
	_smell_check(delta)
	var goal := global_position
	var speed := 0.0
	match state:
		State.PATROL:
			goal = wander_target
			speed = patrol_speed
			_patrol_logic(delta)
			if state != State.PATROL or _near(goal):
				speed = 0.0
		State.HUNT:
			goal = noise_target
			speed = hunt_speed
			if _near(goal):
				speed = 0.0
				_hunt_arrival(delta)
		State.ECHO:
			_echo_logic(delta)
		State.EAR:
			_ear_logic(delta)
			_face(ear_spot.global_position if ear_spot else global_position, delta)
		State.ATTACK:
			_attack_logic(delta)
			if player:
				_face(player.global_position, delta)
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var direction := _steer_direction(to_goal) if speed > 0.0 else Vector3.ZERO
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if speed > 0.0:
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta)
	move_and_slide()
	_check_touch()
	_animate(delta)


func _tick_timers(delta: float) -> void:
	ear_cooldown = maxf(0.0, ear_cooldown - delta)
	replan_left -= delta
	if state == State.PATROL:
		echo_timer -= delta
	if state == State.PATROL or state == State.HUNT:
		mimic_timer -= delta
		if mimic_timer <= 0.0:
			_do_mimic()


func _near(goal: Vector3) -> bool:
	var flat := goal - global_position
	var height_gap := absf(flat.y)
	flat.y = 0.0
	return flat.length() < arrive_radius and height_gap < 1.6


func _face(point: Vector3, delta: float) -> void:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() > 0.05:
		rotation.y = rotate_toward(rotation.y, atan2(-dir.x, -dir.z), turn_speed * delta)


# --- Patrulla: va a una celda cercana, se queda escuchando, a veces chasquea.
func _patrol_logic(delta: float) -> void:
	if echo_timer <= 0.0:
		_begin_echo()
		return
	if _near(wander_target):
		if not arrived:
			arrived = true
			idle_left = randf_range(idle_min, idle_max)
		idle_left -= delta
		if idle_left <= 0.0:
			arrived = false
			wander_target = _random_wander_point()
			_plan_path(wander_target)


func _start_wander() -> void:
	state = State.PATROL
	arrived = false
	going_to_ear = false
	wander_target = _random_wander_point()
	_plan_path(wander_target)


func _random_wander_point() -> Vector3:
	if nav:
		return nav.random_cell_near(global_position, wander_cells)
	return global_position + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))


# --- Cazando: va al sitio del ruido; al llegar chasquea una vez para confirmar.
func _hunt_arrival(delta: float) -> void:
	if going_to_ear:
		if ear_spot and player and player.is_hidden and player.hidden_in == ear_spot:
			_begin_ear()
		else:
			going_to_ear = false
			ear_spot = null
		return
	if not echoed_this_hunt:
		echoed_this_hunt = true
		_begin_echo()
		return
	search_left -= delta
	if search_left <= 0.0:
		_start_wander()


func _hunt_noise(pos: Vector3, loudness: float) -> void:
	var new_speed := clampf(lerpf(hunt_speed_min, hunt_speed_max, loudness), hunt_speed_min, hunt_speed_max)
	hunt_speed = maxf(hunt_speed, new_speed) if state == State.HUNT else new_speed
	state = State.HUNT
	going_to_ear = false
	noise_target = pos
	search_left = search_time
	echoed_this_hunt = false
	_plan_path(pos)


# --- Ecolocalización
func _begin_echo() -> void:
	resume_state = State.HUNT if state == State.HUNT else State.PATROL
	state = State.ECHO
	echo_t = 0.0
	echo_fired = false
	echo_window_left = 0.0
	echo_timer = randf_range(echo_interval_min, echo_interval_max)


func _echo_logic(delta: float) -> void:
	echo_t += delta
	if not echo_fired:
		if echo_t >= echo_windup:
			echo_fired = true
			echo_window_left = echo_window
			_play_at("eco_click", global_position + Vector3(0.0, 1.4, 0.0), -2.0, 14.0, 70.0)
		return
	echo_window_left -= delta
	if echo_window_left > 0.0 and _echo_detects():
		_on_revealed()
		return
	if echo_window_left <= -0.25:
		_end_echo()


# El rebote te delata solo si te MUEVES justo en ese instante (aunque vayas agachado).
func _echo_detects() -> bool:
	if player == null or player.is_hidden:
		return false
	if global_position.distance_to(player.global_position) > echo_range:
		return false
	if _path_distance(player.global_position) > echo_range * hear_wall_factor:
		return false
	return Vector2(player.velocity.x, player.velocity.z).length() > echo_move_speed


func _on_revealed() -> void:
	state = State.HUNT
	going_to_ear = false
	noise_target = player.global_position
	hunt_speed = hunt_speed_max
	search_left = search_time
	echoed_this_hunt = false
	_plan_path(noise_target)
	_play_crack()


func _end_echo() -> void:
	if has_queued_noise:
		has_queued_noise = false
		_hunt_noise(queued_position, queued_loudness)
		return
	if resume_state == State.HUNT:
		state = State.HUNT
	else:
		_start_wander()


# --- Oreja contra el casillero
func _begin_ear() -> void:
	state = State.EAR
	going_to_ear = false
	ear_left = ear_time
	ear_attack_left = -1.0


func _ear_logic(delta: float) -> void:
	if player == null or not player.is_hidden:
		_begin_attack("EL ECO TE DEVORÓ")
		return
	ear_left -= delta
	if ear_attack_left >= 0.0:
		ear_attack_left -= delta
		if ear_attack_left <= 0.0:
			_begin_attack("EL ECO ESCUCHÓ TU RESPIRACIÓN")
			return
	if ear_left <= 0.0 and ear_attack_left < 0.0:
		ear_cooldown = ear_cooldown_time
		ear_spot = null
		_start_wander()


func _go_listen_at_locker() -> void:
	if player == null or player.hidden_in == null:
		return
	ear_spot = player.hidden_in
	going_to_ear = true
	state = State.HUNT
	hunt_speed = lerpf(hunt_speed_min, hunt_speed_max, 0.4)
	var door_point: Vector3 = ear_spot.call("exit_position")
	noise_target = door_point
	search_left = search_time
	echoed_this_hunt = true
	_plan_path(noise_target)


# --- Ataque
func _begin_attack(reason: String) -> void:
	if state == State.ATTACK:
		return
	state = State.ATTACK
	attack_left = attack_time
	catch_reason = reason
	if player:
		player.set_physics_process(false)
		var to_me := global_position - player.global_position
		to_me.y = 0.0
		var wanted := atan2(-to_me.x, -to_me.z)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(player, "rotation:y", player.rotation.y + angle_difference(player.rotation.y, wanted), 0.2)
		tween.tween_property(player.head, "rotation:x", 0.25, 0.2)


func _attack_logic(delta: float) -> void:
	attack_left -= delta
	if attack_left <= 0.0:
		set_physics_process(false)
		var mission := get_tree().get_first_node_in_group("mission_manager") as MissionManager
		if mission:
			mission.on_player_caught(catch_reason, self)
		else:
			get_tree().call_deferred("reload_current_scene")


# Es ciega pero el contacto cuenta: si te toca, te atrapa (salvo escondido).
func _check_touch() -> void:
	if state == State.ATTACK or state == State.EAR or player == null or player.is_hidden:
		return
	if global_position.distance_to(player.global_position) < catch_radius:
		_begin_attack("EL ECO TE DEVORÓ")


# --- Oído
func _on_noise_emitted(noise_position: Vector3, loudness: float) -> void:
	if stun_left > 0.0 or state == State.ATTACK or player == null:
		return
	var radius := lerpf(min_hearing_radius, max_hearing_radius, loudness)
	if global_position.distance_to(noise_position) > radius:
		return
	if _path_distance(noise_position) > radius * hear_wall_factor:
		return
	var from_hidden_player := player.is_hidden and noise_position.distance_to(player.global_position) < 1.5
	if state == State.EAR:
		# Oreja pegada a la puerta: si vuelve a oír ruido ahí dentro, ataca.
		if from_hidden_player and ear_attack_left < 0.0:
			ear_attack_left = ear_attack_delay
		return
	if from_hidden_player:
		if ear_cooldown <= 0.0:
			_go_listen_at_locker()
		return
	if state == State.ECHO:
		has_queued_noise = true
		queued_position = noise_position
		queued_loudness = loudness
		return
	if allied and Time.get_ticks_msec() / 1000.0 - ally_cd > 6.0 and loudness > 0.3:
		ally_cd = Time.get_ticks_msec() / 1000.0
		get_tree().call_group("enemies", "_on_ally_alert", self, noise_position)
	_hunt_noise(noise_position, loudness)


# --- Mímica
func _do_mimic() -> void:
	mimic_timer = randf_range(mimic_interval_min, mimic_interval_max)
	var sound: String = MIMIC_SOUNDS.pick_random()
	var at := global_position + Vector3(0.0, 1.3, 0.0)
	if nav and player and randf() < mimic_decoy_chance:
		for i in 6:
			var cell := nav.random_cell_center(player.global_position)
			var d := cell.distance_to(player.global_position)
			if d > 6.0 and d < 24.0:
				at = cell + Vector3(0.0, 1.4, 0.0)
				break
	_play_at(sound, at, -3.0, 9.0, 50.0)


# ============================================================== navegación

func _plan_path(destination: Vector3) -> void:
	path_index = 0
	path = nav.find_path(global_position, destination) if nav else PackedVector3Array()
	if path.size() > 1:
		var here := Vector2(global_position.x, global_position.z)
		var first := Vector2(path[0].x, path[0].z)
		var second := Vector2(path[1].x, path[1].z)
		if here.distance_to(second) < first.distance_to(second):
			path_index = 1


func _steer_direction(to_target: Vector3) -> Vector3:
	while path_index < path.size():
		var to_point := path[path_index] - global_position
		to_point.y = 0.0
		if to_point.length() < waypoint_radius:
			path_index += 1
		else:
			return to_point.normalized()
	return to_target.normalized()


# Longitud real del camino (rodeando paredes) hasta un punto; INF si no hay camino.
func _path_distance(destination: Vector3) -> float:
	if nav == null:
		return global_position.distance_to(destination)
	return nav.path_length(global_position, destination)


# ================================================================== sonido

func _setup_breath() -> void:
	var path_wav := "res://assets/audio/eco_breath.wav"
	if not ResourceLoader.exists(path_wav):
		return
	breath_player = AudioStreamPlayer3D.new()
	breath_player.stream = load(path_wav)
	breath_player.volume_db = -9.0
	breath_player.unit_size = 4.0
	breath_player.max_distance = 35.0
	breath_player.position = Vector3(0.0, 1.3, -0.4)
	add_child(breath_player)
	breath_player.finished.connect(breath_player.play)
	breath_player.play()


func _play_at(sound: String, at: Vector3, volume_db := -4.0, unit_size := 10.0, max_distance := 60.0) -> void:
	if Net.relay_creature_sound(self, sound, at, volume_db, unit_size, max_distance):
		return      # cliente: los chasquidos los decide el anfitrión
	var wav := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(wav):
		return
	var sfx := AudioStreamPlayer3D.new()
	sfx.stream = load(wav)
	sfx.volume_db = volume_db
	sfx.unit_size = unit_size
	sfx.max_distance = max_distance
	get_tree().root.add_child(sfx)
	sfx.global_position = at
	sfx.finished.connect(sfx.queue_free)
	sfx.play()


func _play_crack() -> void:
	_play_at("eco_crack_%d" % randi_range(1, 3), global_position + Vector3(0.0, 0.8, 0.0), -7.0, 5.0, 25.0)


# ================================================================== modelo

func _make_mat(file: String) -> Material:
	var tex_path := TEX_DIR + file
	var texture: Texture2D = null
	if ResourceLoader.exists(tex_path):
		texture = load(tex_path) as Texture2D
	if texture and ResourceLoader.exists(PS1_SHADER):
		var shader_material := ShaderMaterial.new()
		shader_material.shader = load(PS1_SHADER) as Shader
		shader_material.set_shader_parameter("albedo_texture", texture)
		return shader_material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.4, 0.45, 0.35)
	fallback.roughness = 1.0
	if texture:
		fallback.albedo_texture = texture
		fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return fallback


func _box(x: float, y: float, z: float) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(x, y, z)
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	return mesh


func _cone(radius: float, height: float, top_radius := 0.0) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1
	return mesh


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = pos
	instance.rotation_degrees = rot_deg
	parent.add_child(instance)
	return instance


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	if _build_mesh_model():
		return
	var skin := _make_mat("eco_skin.png")
	var head_mat := _make_mat("eco_head.png")
	var bone := _make_mat("eco_bone.png")
	var claw := _make_mat("eco_claw.png")
	var mouth_mat := _make_mat("eco_mouth.png")

	# Torso encorvado: hombros altos, cadera más baja, espinas óseas en el lomo.
	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0.0, TORSO_Y, 0.15)
	torso.rotation_degrees.x = 10.0
	model.add_child(torso)
	_part(torso, _box(0.5, 0.42, 1.0), skin, Vector3.ZERO)
	_part(torso, _box(0.64, 0.5, 0.46), skin, Vector3(0.0, 0.03, -0.38))
	_part(torso, _box(0.46, 0.4, 0.4), skin, Vector3(0.0, -0.02, 0.42))
	for i in 7:
		var spike_h := 0.17 - absf(i - 3.0) * 0.018
		_part(torso, _cone(0.04, spike_h), bone, Vector3(0.0, 0.26 + spike_h * 0.5, -0.55 + i * 0.19), Vector3(14.0, 0.0, 0.0))

	# Cabeza: bocina acústica porosa (panal) con un cuerno curvo hacia delante.
	head_pivot = Node3D.new()
	head_pivot.name = "Head"
	head_pivot.position = Vector3(0.0, 0.12, -0.62)
	torso.add_child(head_pivot)
	head_rest = head_pivot.position
	_part(head_pivot, _box(0.22, 0.22, 0.4), skin, Vector3(0.0, 0.03, -0.1), Vector3(-10.0, 0.0, 0.0))
	var bulb := _part(head_pivot, _sphere(0.36), head_mat, Vector3(0.0, 0.3, -0.3))
	bulb.scale = Vector3(0.85, 1.0, 1.25)
	var angles: Array[float] = [-70.0, -55.0, -35.0, -15.0]
	var radii: Array[float] = [0.19, 0.14, 0.095, 0.055, 0.006]
	var heights: Array[float] = [0.4, 0.4, 0.38, 0.36]
	var horn_pos := Vector3(0.0, 0.5, -0.5)
	for i in angles.size():
		var a := deg_to_rad(angles[i])
		var dir := Vector3(0.0, cos(a), sin(a))
		var segment_mat: Material = head_mat if i < 3 else bone
		_part(head_pivot, _cone(radii[i], heights[i], radii[i + 1]), segment_mat, horn_pos + dir * heights[i] * 0.5, Vector3(angles[i], 0.0, 0.0))
		horn_pos += dir * heights[i]
	# Boca al frente-abajo: interior oscuro, dientes arriba y mandíbula móvil.
	_part(head_pivot, _box(0.34, 0.2, 0.12), mouth_mat, Vector3(0.0, 0.1, -0.7))
	for k in 5:
		_part(head_pivot, _cone(0.018, 0.1), bone, Vector3((k - 2) * 0.06, 0.0, -0.76), Vector3(180.0, 0.0, 0.0))
	jaw = Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0.0, -0.02, -0.52)
	head_pivot.add_child(jaw)
	_part(jaw, _box(0.3, 0.07, 0.3), skin, Vector3(0.0, -0.02, -0.14))
	for k in 5:
		_part(jaw, _cone(0.016, 0.08), bone, Vector3((k - 2) * 0.055, 0.04, -0.27))

	# Extremidades delgadas y mal articuladas (codos y rodillas en ángulos antinaturales).
	for side: float in [1.0, -1.0]:
		var front_phase := 0.0 if side > 0.0 else PI
		var hind_phase := PI if side > 0.0 else 0.0
		_make_limb(Vector3(0.36, -0.05, -0.40), side, false, front_phase, skin, claw)
		_make_limb(Vector3(0.30, -0.08, 0.44), side, true, hind_phase, skin, claw)


# Usa el modelo 3D importado (.glb). Devuelve false si no existe y se usa el de cajas.
func _build_mesh_model() -> bool:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return false
	var scene := load(model_path) as PackedScene
	if scene == null:
		return false
	torso = Node3D.new()
	torso.name = "Torso"
	model.add_child(torso)
	mesh_model = scene.instantiate() as Node3D
	mesh_model.name = "Mesh"
	mesh_model.rotation.y = PI                  # el .glb mira hacia +Z; la criatura avanza hacia -Z
	mesh_model.scale = Vector3.ONE * model_scale
	torso.add_child(mesh_model)
	skeleton = mesh_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		for i in skeleton.get_bone_count():
			bone_ids[skeleton.get_bone_name(i)] = i
	# Nodos vacíos para que el resto del código no falle.
	head_pivot = Node3D.new()
	torso.add_child(head_pivot)
	jaw = Node3D.new()
	head_pivot.add_child(jaw)
	return true


func _make_limb(attach: Vector3, side: float, hind: bool, phase: float, skin: Material, claw: Material) -> void:
	var limb := Limb.new()
	limb.side = side
	limb.hind = hind
	limb.phase = phase
	var upper_len := 0.6 if hind else 0.55
	var lower_len := 0.66 if hind else 0.62
	var thick := 0.12 if hind else 0.11
	limb.shoulder = Node3D.new()
	limb.shoulder.position = Vector3(attach.x * side, attach.y, attach.z)
	torso.add_child(limb.shoulder)
	if hind:
		limb.rest_shoulder = Vector3(deg_to_rad(52.0), 0.0, side * deg_to_rad(22.0))
		limb.rest_elbow = Vector3(deg_to_rad(-100.0), 0.0, -side * deg_to_rad(8.0))
	else:
		limb.rest_shoulder = Vector3(deg_to_rad(-18.0), 0.0, side * deg_to_rad(38.0))
		limb.rest_elbow = Vector3(0.0, 0.0, -side * deg_to_rad(52.0))
	limb.shoulder.rotation = limb.rest_shoulder
	_part(limb.shoulder, _sphere(0.1), skin, Vector3.ZERO)
	_part(limb.shoulder, _box(thick, upper_len, thick), skin, Vector3(0.0, -upper_len * 0.5, 0.0))
	limb.elbow = Node3D.new()
	limb.elbow.position = Vector3(0.0, -upper_len, 0.0)
	limb.elbow.rotation = limb.rest_elbow
	limb.shoulder.add_child(limb.elbow)
	_part(limb.elbow, _sphere(0.075), skin, Vector3.ZERO)
	_part(limb.elbow, _box(thick * 0.8, lower_len, thick * 0.8), skin, Vector3(0.0, -lower_len * 0.5, 0.0))
	var foot := Node3D.new()
	foot.position = Vector3(0.0, -lower_len, 0.0)
	limb.elbow.add_child(foot)
	_part(foot, _box(0.13, 0.05, 0.18), skin, Vector3(0.0, 0.0, -0.05))
	for k in 3:
		_part(foot, _cone(0.014, 0.17), claw, Vector3((k - 1) * 0.045, -0.01, -0.17), Vector3(-105.0, 0.0, 0.0))
	limbs.append(limb)


# ============================================================== animación

# Movimiento del modelo importado: tiene un esqueleto de 11 huesos (cuerpo, cabeza y
# 4 patas de 2 huesos). Las poses se calculan aquí cada fotograma, con suavizado:
# patas en marcha diagonal al caminar, respiración y cabeza según el estado.
func _animate_rig(delta: float) -> void:
	idle_time += delta
	var moving := Vector2(velocity.x, velocity.z).length()
	var w := clampf(moving / 1.2, 0.0, 1.5)
	if moving > 0.1:
		gait_phase += delta * clampf(moving * 8.0, 0.0, 24.0)
		var half := int(floorf(gait_phase / PI))
		if half != last_half_cycle:
			last_half_cycle = half
			if randf() < 0.55:
				_play_crack()
	var lunge := 0.0
	var head_t := Vector3(sin(idle_time * 0.55) * 0.06, sin(idle_time * 0.8) * 0.12, 0.0)
	var chest_t := Vector3(sin(idle_time * 2.2) * 0.02, sin(gait_phase) * 0.06 * w, sin(gait_phase) * 0.05 * w)
	var reach := 0.0
	match state:
		State.ECHO:
			head_t = Vector3(-0.5, 0.0, 0.0)               # nariz arriba: escucha el rebote
			chest_t.x = -0.12
			reach = 0.12
		State.HUNT:
			head_t = Vector3(0.18, sin(idle_time * 7.0) * 0.22, 0.0)
		State.EAR:
			head_t = Vector3(0.1, 0.3, 0.7)                # ladea la cabeza contra la puerta
		State.ATTACK:
			lunge = 1.0 - clampf(attack_left / attack_time, 0.0, 1.0)
			head_t = Vector3(0.25 * lunge, 0.0, 0.0)
			chest_t.x = 0.2 * lunge
			reach = -0.9 * lunge
	var k := 1.0 - exp(-14.0 * delta)
	_rig_pose("head", head_t, k)
	_rig_pose("chest", chest_t, k)
	_rig_pose("root", Vector3(0.0, -sin(gait_phase) * 0.04 * w, 0.0), k)
	for side: String in ["r", "l"]:
		var front_ph := gait_phase + (0.0 if side == "r" else PI)   # marcha diagonal
		var hind_ph := front_ph + PI
		var fs := sin(front_ph)
		var fl := maxf(0.0, cos(front_ph))
		var hs := sin(hind_ph)
		var hl := maxf(0.0, cos(hind_ph))
		_rig_pose("fu_" + side, Vector3(-fs * 0.32 * w + reach, 0.0, 0.0), k)
		_rig_pose("fl_" + side, Vector3(-fl * 0.55 * w - reach * 0.35, 0.0, 0.0), k)
		_rig_pose("hu_" + side, Vector3(-hs * 0.32 * w, 0.0, 0.0), k)
		_rig_pose("hl_" + side, Vector3(hl * 0.55 * w, 0.0, 0.0), k)
	torso.position = Vector3(0.0, sin(gait_phase * 2.0) * 0.03 * w, -0.8 * lunge)
	if stun_left > 0.0:      # aturdido: cabeza al suelo, patas flojas, temblor
		_rig_pose("head", Vector3(0.75, 0.0, 0.5 + sin(idle_time * 28.0) * 0.1), k)
		_rig_pose("chest", Vector3(0.18, 0.0, 0.0), k)
		torso.position = Vector3(0.0, -0.12, 0.0)


func _rig_pose(bone: String, target: Vector3, k: float) -> void:
	if skeleton == null or not bone_ids.has(bone):
		return
	var current: Vector3 = rig_euler.get(bone, Vector3.ZERO)
	current = current.lerp(target, k)
	rig_euler[bone] = current
	skeleton.set_bone_pose_rotation(bone_ids[bone], Quaternion.from_euler(current))


# Se actualiza a pocos fotogramas por segundo: movimientos entrecortados y torpes.
func _animate(delta: float) -> void:
	if mesh_model:
		_animate_rig(delta)
		return
	anim_acc += delta
	var step := 1.0 / anim_fps
	if anim_acc < step:
		return
	var dt := anim_acc
	anim_acc = 0.0
	idle_time += dt
	var moving := Vector2(velocity.x, velocity.z).length()
	var w := clampf(moving / 1.2, 0.0, 1.5)
	if moving > 0.1:
		gait_phase += dt * clampf(moving * 9.0, 0.0, 26.0)
		var half := int(floorf(gait_phase / PI))
		if half != last_half_cycle:
			last_half_cycle = half
			if randf() < 0.55:
				_play_crack()
	for limb in limbs:
		var ph := gait_phase + limb.phase
		var swing := sin(ph) * deg_to_rad(20.0 if limb.hind else 24.0) * w
		var lift := maxf(0.0, cos(ph)) * deg_to_rad(35.0) * w
		limb.shoulder.rotation = limb.rest_shoulder + Vector3(swing, 0.0, 0.0)
		if limb.hind:
			limb.elbow.rotation = limb.rest_elbow + Vector3(-lift, 0.0, 0.0)
		else:
			limb.elbow.rotation = limb.rest_elbow + Vector3(0.0, 0.0, -limb.side * lift)
	torso.position.y = TORSO_Y + sin(gait_phase * 2.0) * 0.03 * w + sin(idle_time * 2.2) * 0.012
	var head_target := Vector3(sin(idle_time * 0.8) * 0.08, sin(idle_time * 0.55) * 0.4, 0.0)
	var jaw_open := 0.1 + (0.5 + 0.5 * sin(idle_time * 2.4)) * 0.08
	var lunge := 0.0
	match state:
		State.ECHO:
			head_target = Vector3(0.45, 0.0, 0.0)
			jaw_open = 0.75
		State.HUNT:
			head_target = Vector3(0.15, sin(idle_time * 7.0) * 0.25, 0.0)
			jaw_open = 0.3
		State.EAR:
			head_target = Vector3(0.1, 0.0, 1.25)
			jaw_open = 0.05
		State.ATTACK:
			head_target = Vector3(-0.2, 0.0, 0.0)
			jaw_open = 1.0
			lunge = 1.0 - clampf(attack_left / attack_time, 0.0, 1.0)
	head_pivot.rotation = head_pivot.rotation.lerp(head_target, 0.45)
	head_pivot.position = head_rest + Vector3(0.0, -0.1 * lunge, -0.7 * lunge)
	jaw.rotation.x = lerpf(jaw.rotation.x, -jaw_open, 0.5)


# ============================================================== aturdimiento

const STUN_COLORS := {"dart": Color(0.35, 1.0, 0.5), "trap": Color(0.35, 0.6, 1.0), "flash": Color(1.0, 0.95, 0.85)}
@export_group("Aturdimiento")
@export var stun_immunity := 5.5       ## Tras despertar no se le puede aturdir otra vez durante estos segundos

var stun_left := 0.0
var stun_kind := ""
var stun_source := Vector3.ZERO
var stun_immune := 0.0
var stun_light: OmniLight3D


## Aturde a la criatura `duration` segundos. Devuelve false si no le afecta
## (todavía inmune tras despertar ni a la luz de bengala: el Eco es ciego).
func stun(duration: float, kind := "dart", source_pos := Vector3.ZERO) -> bool:
	if Net.is_client():
		return false      # en red solo el anfitrión aturde (los clientes lo piden con Net.try_stun)
	if kind == "flash":
		return false
	if stun_immune > 0.0:
		return false
	duration *= Difficulty.get_value("stun_mul")
	var fresh := stun_left <= 0.0
	stun_left = maxf(stun_left, duration)
	stun_kind = kind
	stun_source = source_pos
	if fresh:
		_on_stunned()
		var mm := get_tree().get_first_node_in_group("mission_manager")
		if mm:
			mm.report("stun", "")
	if stun_light == null:
		stun_light = OmniLight3D.new()
		stun_light.omni_range = 4.5
		stun_light.position = Vector3(0.0, 1.4, 0.0)
		add_child(stun_light)
	stun_light.light_color = STUN_COLORS.get(kind, Color.WHITE)
	stun_light.light_energy = 1.6
	stun_light.visible = true
	Sfx.play(self, "zap" if kind != "flash" else "flash_pop", -8.0)
	var mm := get_tree().get_first_node_in_group("mission_manager")
	if mm:
		mm.call("report", "stun", kind)
	return true


func is_stunned() -> bool:
	return stun_left > 0.0


func _stunned_tick(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	stun_left -= delta
	if stun_light:
		stun_light.light_energy = 1.2 + sin(Time.get_ticks_msec() / 1000.0 * 22.0) * 0.5
	_animate(delta)
	if stun_left <= 0.0:
		stun_left = 0.0
		stun_immune = stun_immunity
		if stun_light:
			stun_light.visible = false
		_on_woke()


func _on_stunned() -> void:
	going_to_ear = false
	has_queued_noise = false
	ear_attack_left = -1.0
	attack_left = 0.0
	if state == State.ATTACK or state == State.ECHO or state == State.EAR:
		state = State.PATROL
	path = PackedVector3Array()


func _on_woke() -> void:
	if stun_kind == "dart" and stun_source != Vector3.ZERO:
		_hunt_noise(stun_source, 0.4)
	else:
		_start_wander()
