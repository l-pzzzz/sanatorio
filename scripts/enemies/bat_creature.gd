extends CharacterBody3D

enum State { WANDER, HUNT }

@export var ps1_shader: Shader
@export var wander_speed := 1.2
@export var min_hunt_speed := 2.0
@export var max_hunt_speed := 3.2
@export var min_hearing_radius := 8.0 
@export var max_hearing_radius := 30.0
@export var catch_radius := 1.2
@export var wander_radius := 6.0
@export var search_time := 6.0
@export var turn_speed := 4.0
@export var animation_fps := 8.0
@export var stride_degrees := 28.0
@export var arm_hang_degrees := 10.0
@export var arm_swing_degrees := 24.0
@export var twitch_chance := 0.08
@export var vision_range := 11.0       ## Ve bien de frente: te persigue aunque estés quieto si te ve (m)
@export var flashlight_vision_multiplier := 2.0  ## Cuánto más lejos ve si el jugador tiene la linterna encendida
@export var close_sense_range := 2.8   ## A esta distancia te nota aunque no mire hacia ti (m)
@export var vision_angle := 130.0      ## Ángulo del cono de visión (grados)
@export var wander_cells := 3          ## Cuántas celdas se aleja como máximo de su zona al patrullar
@export var idle_min := 2.5            ## Pausa mínima (s) escuchando al llegar a un punto de patrulla
@export var idle_max := 6.0            ## Pausa máxima (s)
@export var hear_wall_factor := 1.5    ## Un sonido se oye si el CAMINO hasta él mide como mucho radio x este factor
@export var hide_noise_window := 2.0   ## Si haces ruido escondido, durante estos segundos puede encontrarte
@export var arrive_radius := 1.0        ## A qué distancia del destino se considera que llegó (casilleros: choca antes de su centro)
@export var waypoint_radius := 0.6     ## Qué tan cerca debe estar de un punto de la ruta para pasar al siguiente
@export var replan_interval := 0.4     ## Cada cuántos segundos recalcula la ruta mientras persigue
@export_group("Modelo 3D")
@export_file("*.glb", "*.gltf") var mesh_path := "res://assets/models/bat_model.glb"   ## Si existe, reemplaza al modelo viejo
@export var mesh_scale := 1.9          ## Tamaño del modelo (mide ~1.1 m a escala 1; frente = +Z, se gira solo)
@export var wings_hunting_open := 0.55 ## Cuánto se abren las alas al perseguir (0 = plegadas, 1 = plegadas del todo)

@onready var model: Node3D = $Model
@onready var head: Node3D = $Model/hips/torso/head
@onready var thigh_left: Node3D = $Model/hips/thigh_left
@onready var thigh_right: Node3D = $Model/hips/thigh_right
@onready var shin_left: Node3D = $Model/hips/thigh_left/shin_left
@onready var shin_right: Node3D = $Model/hips/thigh_right/shin_right
@onready var arm_left: Node3D = $Model/hips/torso/upper_arm_left
@onready var arm_right: Node3D = $Model/hips/torso/upper_arm_right
@onready var forearm_left: Node3D = $Model/hips/torso/upper_arm_left/forearm_left
@onready var forearm_right: Node3D = $Model/hips/torso/upper_arm_right/forearm_right
@onready var hand_left: Node3D = $Model/hips/torso/upper_arm_left/forearm_left/hand_left
@onready var hand_right: Node3D = $Model/hips/torso/upper_arm_right/forearm_right/hand_right

var state := State.WANDER
var player: CharacterBody3D
var nav: MazeNav
var path := PackedVector3Array()
var path_index := 0
var replan_left := 0.0
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var noise_target := Vector3.ZERO
var hunt_speed := 0.0
var search_left := 0.0
var rest := {}
var anim_time := 0.0
var idle_time := 0.0
var anim_accumulator := 0.0
var arrived := false
var idle_left := 0.0
var last_seen_time := -100.0
var hidden_noise_time := -100.0
var witnessed_hiding := false

var mesh_model: Node3D
var skeleton: Skeleton3D
var bone_ids: Dictionary = {}
var rig_euler: Dictionary = {}
var gait := 0.0
var wing_fold := 1.0                   ## 1 = alas plegadas a la espalda, 0 = abiertas


func _ready() -> void:
	collision_mask |= 4        # capa 4: barreras que solo frenan a las criaturas (boca del túnel del corazón)
	player = get_tree().get_first_node_in_group("player")
	for node in [head, thigh_left, thigh_right, shin_left, shin_right]:
		rest[node] = node.rotation
	var hang := deg_to_rad(arm_hang_degrees)
	rest[arm_left] = Vector3(0.0, 0.0, -hang)
	rest[arm_right] = Vector3(0.0, 0.0, hang)
	for node in [forearm_left, forearm_right, hand_left, hand_right]:
		rest[node] = Vector3(0.15, 0.0, 0.0)
	nav = get_tree().get_first_node_in_group("maze_nav")
	floor_snap_length = 0.6
	# Diferido: espera a que toda la escena (laberinto incluido) esté lista.
	_start_wander.call_deferred()
	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	if player and player.has_signal("hiding_changed"):
		player.connect("hiding_changed", _on_player_hiding_changed)
	_setup_mesh_model()
	_apply_ps1_material()
	_apply_difficulty()


func _physics_process(delta: float) -> void:
	if stun_left > 0.0:
		_stunned_tick(delta)
		return
	stun_immune = maxf(0.0, stun_immune - delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	_sense_player(delta)
	var hunting := state == State.HUNT
	var target := noise_target if hunting else wander_target
	var speed := hunt_speed if hunting else wander_speed
	var to_target := target - global_position
	var height_gap := absf(to_target.y)
	to_target.y = 0.0
	if to_target.length() < arrive_radius and height_gap < 1.6:
		speed = 0.0
		if hunting:
			search_left -= delta
			if search_left <= 0.0:
				_start_wander()
		else:
			# Llegó a su punto de patrulla: se queda quieto escuchando antes de seguir.
			if not arrived:
				arrived = true
				idle_left = randf_range(idle_min, idle_max)
			idle_left -= delta
			if idle_left <= 0.0:
				arrived = false
				wander_target = _random_wander_point()
				_plan_path(wander_target)
	var direction := _steer_direction(to_target)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if speed > 0.0:
		rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta)
	move_and_slide()
	if hunting and player and global_position.distance_to(player.global_position) < catch_radius and _can_catch():
		_catch_player()
		return
	_animate(delta)


# Oye un ruido (voz, pasos, puertas, alarma). El sonido se amortigua con las
# paredes: no basta con estar cerca en línea recta, cuenta el camino real.
func _on_noise_emitted(noise_position: Vector3, loudness: float) -> void:
	if stun_left > 0.0:
		return
	var radius := lerpf(min_hearing_radius, max_hearing_radius, loudness)
	if global_position.distance_to(noise_position) > radius:
		return
	if _path_distance(noise_position) > radius * hear_wall_factor:
		return
	if _player_hidden() and noise_position.distance_to(player.global_position) < 1.5:
		hidden_noise_time = Time.get_ticks_msec() / 1000.0
	var new_speed := clampf(lerpf(min_hunt_speed, max_hunt_speed, loudness), min_hunt_speed, max_hunt_speed)
	hunt_speed = maxf(hunt_speed, new_speed) if state == State.HUNT else new_speed
	state = State.HUNT
	noise_target = noise_position
	search_left = search_time
	_plan_path(noise_target)


func _start_wander() -> void:
	state = State.WANDER
	arrived = false
	witnessed_hiding = false
	home = global_position
	wander_target = _random_wander_point()
	_plan_path(wander_target)


func _random_wander_point() -> Vector3:
	# Patrulla cerca de donde está (no recorre todo el mapa).
	if nav:
		return nav.random_cell_near(global_position, wander_cells)
	var angle := randf() * TAU
	return home + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.0, wander_radius)


# Revisa si el murciélago VE al jugador (poco alcance). Lo demás lo oye.
func _sense_player(delta: float) -> void:
	if player == null:
		return
	replan_left -= delta
	var to_player := player.global_position - global_position
	if not _can_see_player(to_player):
		return
	var now_t := Time.get_ticks_msec() / 1000.0
	if allied and now_t - ally_cd > 6.0 and now_t - last_seen_time > 2.0:
		ally_cd = now_t
		Sfx.play(self, "kill_screech_bat", -7.0)       # el grito le avisa al Eco
		get_tree().call_group("enemies", "_on_ally_alert", self, player.global_position)
	last_seen_time = now_t
	state = State.HUNT
	noise_target = player.global_position
	hunt_speed = max_hunt_speed
	search_left = search_time
	if replan_left <= 0.0:
		replan_left = replan_interval
		_plan_path(noise_target)


# Visión: dentro del rango, dentro del cono frontal y sin paredes en medio.
func _can_see_player(to_player: Vector3) -> bool:
	if _player_hidden():
		return false   # escondido en un casillero: no lo ve
	var seen_range := vision_range
	if player.get("flashlight_on") == true:
		seen_range *= flashlight_vision_multiplier   # la linterna lo atrae desde más lejos
	if to_player.length() > seen_range:
		return false
	var flat := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var forward := -global_transform.basis.z
	# Muy cerca (a su lado o a su espalda) lo nota igual: no hace falta que mire de frente.
	if to_player.length() > close_sense_range and forward.dot(flat) < cos(deg_to_rad(vision_angle * 0.5)):
		return false
	var from := global_position + Vector3.UP * 1.2
	var to := player.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


# Calcula la ruta (rodeando paredes) hacia un destino.
func _plan_path(destination: Vector3) -> void:
	path_index = 0
	path = nav.find_path(global_position, destination) if nav else PackedVector3Array()
	# El primer punto de la ruta es el centro de la celda actual. Si el murciélago
	# ya lo pasó (está más cerca del 2.º punto que el propio centro), empieza en el
	# 2.º punto. Sin esto, al replanificar cada pocos décimas de segundo daba media
	# vuelta hacia el centro y se quedaba oscilando en el mismo sitio.
	if path.size() > 1:
		var here := Vector2(global_position.x, global_position.z)
		var first := Vector2(path[0].x, path[0].z)
		var second := Vector2(path[1].x, path[1].z)
		if here.distance_to(second) < first.distance_to(second):
			path_index = 1


# Dirección hacia el siguiente punto de la ruta; sin ruta, va directo al destino.
func _steer_direction(to_target: Vector3) -> Vector3:
	while path_index < path.size():
		var to_point := path[path_index] - global_position
		to_point.y = 0.0
		if to_point.length() < waypoint_radius:
			path_index += 1
		else:
			return to_point.normalized()
	return to_target.normalized()


func _animate(delta: float) -> void:
	if mesh_model:
		_animate_rig(delta)
		return
	anim_accumulator += delta
	if anim_accumulator < 1.0 / animation_fps:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	anim_time += anim_accumulator * horizontal_speed * 2.2
	idle_time += anim_accumulator
	anim_accumulator = 0.0
	var walk := clampf(horizontal_speed / wander_speed, 0.0, 1.0)
	var swing := sin(anim_time) * deg_to_rad(stride_degrees) * walk
	thigh_left.rotation.x = rest[thigh_left].x + swing
	thigh_right.rotation.x = rest[thigh_right].x - swing
	shin_left.rotation.x = rest[shin_left].x - maxf(0.0, -swing) * 1.5
	shin_right.rotation.x = rest[shin_right].x - maxf(0.0, swing) * 1.5
	var arm_swing := deg_to_rad(arm_swing_degrees) * walk
	var sway := sin(idle_time * 1.3) * 0.05
	arm_left.rotation = rest[arm_left] + Vector3(-sin(anim_time) * arm_swing, 0.0, sway)
	arm_right.rotation = rest[arm_right] + Vector3(sin(anim_time) * arm_swing, 0.0, -sway)
	forearm_left.rotation = rest[forearm_left] + Vector3(-sin(anim_time - 0.9) * arm_swing, 0.0, 0.0)
	forearm_right.rotation = rest[forearm_right] + Vector3(sin(anim_time - 0.9) * arm_swing, 0.0, 0.0)
	hand_left.rotation = rest[hand_left] + Vector3(-sin(anim_time - 1.8) * arm_swing, 0.0, 0.0)
	hand_right.rotation = rest[hand_right] + Vector3(sin(anim_time - 1.8) * arm_swing, 0.0, 0.0)
	_animate_head()


# Usa el modelo importado (.glb con esqueleto) en vez del modelo viejo.
func _setup_mesh_model() -> void:
	if mesh_path.is_empty() or not ResourceLoader.exists(mesh_path):
		return
	var scene := load(mesh_path) as PackedScene
	if scene == null:
		return
	mesh_model = scene.instantiate() as Node3D
	mesh_model.name = "MeshModel"
	mesh_model.rotation.y = PI                  # el .glb mira hacia +Z; la criatura avanza hacia -Z
	mesh_model.scale = Vector3.ONE * mesh_scale
	add_child(mesh_model)
	model.visible = false                       # oculta el modelo viejo (sigue ahí por si borras el .glb)
	skeleton = mesh_model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		for i in skeleton.get_bone_count():
			bone_ids[skeleton.get_bone_name(i)] = i


func _rig_pose(bone: String, target: Vector3, k: float) -> void:
	if skeleton == null or not bone_ids.has(bone):
		return
	var current: Vector3 = rig_euler.get(bone, Vector3.ZERO)
	current = current.lerp(target, k)
	rig_euler[bone] = current
	skeleton.set_bone_pose_rotation(bone_ids[bone], Quaternion.from_euler(current))


# Animación del modelo con esqueleto: camina con piernas y brazos opuestos, mueve la
# cabeza hacia el ruido y mantiene las alas plegadas (se entreabren al perseguir).
func _animate_rig(delta: float) -> void:
	idle_time += delta
	var speed := Vector2(velocity.x, velocity.z).length()
	var walk := clampf(speed / wander_speed, 0.0, 1.6)
	if speed > 0.1:
		gait += delta * clampf(speed * 3.9, 0.0, 16.0)
	var k := 1.0 - exp(-12.0 * delta)
	var hunting := state == State.HUNT
	# cabeza
	var look := sin(idle_time * 0.7) * 0.5
	if hunting:
		var to_noise := noise_target - global_position
		look = clampf(angle_difference(rotation.y, atan2(-to_noise.x, -to_noise.z)), -1.3, 1.3)
	var twitch := randf_range(-0.4, 0.4) if randf() < twitch_chance * delta * 8.0 else 0.0
	_rig_pose("head", Vector3(sin(idle_time * 0.9) * 0.05, look, twitch), k)
	# tronco
	_rig_pose("root", Vector3(0.0, sin(gait) * 0.08 * walk, 0.0), k)
	_rig_pose("chest", Vector3(sin(idle_time * 1.6) * 0.02, 0.0, sin(gait) * 0.04 * walk), k)
	# piernas y brazos opuestos
	var arm_raise := -0.5 if hunting else 0.0
	for side: String in ["l", "r"]:
		var p := gait if side == "l" else gait + PI
		var forward := sin(p)
		var lift := maxf(0.0, cos(p))
		_rig_pose("thigh_" + side, Vector3(-forward * 0.55 * walk, 0.0, 0.0), k)
		_rig_pose("shin_" + side, Vector3(lift * 0.8 * walk, 0.0, 0.0), k)
		_rig_pose("foot_" + side, Vector3(-lift * 0.25 * walk, 0.0, 0.0), k)
		_rig_pose("arm_" + side, Vector3(forward * 0.35 * walk + arm_raise, 0.0, 0.0), k)
		_rig_pose("forearm_" + side, Vector3(-0.25 - absf(forward) * 0.15 * walk + arm_raise * 0.5, 0.0, 0.0), k)
	# alas: plegadas a la espalda; al perseguir se entreabren y vibran
	var fold_target := 1.0 - (1.0 - wings_hunting_open) * (1.0 if hunting else 0.0)
	wing_fold = lerpf(wing_fold, fold_target, 1.0 - exp(-3.0 * delta))
	var flutter := sin(idle_time * (9.0 if hunting else 1.2)) * (0.07 if hunting else 0.025)
	for side: String in ["l", "r"]:
		var s := 1.0 if side == "r" else -1.0
		_rig_pose("wing_u_" + side, Vector3(0.0, 0.0, s * (0.9 * wing_fold + flutter)), k)
		_rig_pose("wing_o_" + side, Vector3(0.0, 0.0, -s * (1.75 * wing_fold + flutter * 0.5)), k)
	mesh_model.position.y = absf(sin(gait)) * 0.03 * walk * mesh_scale
	if stun_left > 0.0:      # aturdido: se encorva, cabeza caída, alas flojas y temblor
		mesh_model.rotation.x = lerpf(mesh_model.rotation.x, 0.35, 1.0 - exp(-6.0 * delta))
		_rig_pose("head", Vector3(0.7, sin(idle_time * 30.0) * 0.12, 0.3), k)
		_rig_pose("arm_l", Vector3(0.0, 0.0, 0.0), k)
		_rig_pose("arm_r", Vector3(0.0, 0.0, 0.0), k)
		mesh_model.position.y = -0.04 * mesh_scale
	else:
		mesh_model.rotation.x = lerpf(mesh_model.rotation.x, 0.0, 1.0 - exp(-8.0 * delta))


func _animate_head() -> void:
	var look := sin(idle_time * 0.7) * 0.5
	if state == State.HUNT:
		var to_noise := noise_target - global_position
		look = clampf(angle_difference(rotation.y, atan2(-to_noise.x, -to_noise.z)), -1.3, 1.3)
	var twitch := randf_range(-0.4, 0.4) if randf() < twitch_chance else 0.0
	head.rotation = rest[head] + Vector3(0.0, look, twitch)


func _apply_ps1_material() -> void:
	if ps1_shader == null:
		return
	var material := ShaderMaterial.new()
	material.shader = ps1_shader
	for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var source := mesh_instance.get_active_material(0) as BaseMaterial3D
		if source and source.albedo_texture:
			material.set_shader_parameter("albedo_texture", source.albedo_texture)
		mesh_instance.material_override = material


# Atrapado: si el nivel tiene MissionManager muestra la pantalla de derrota;
# si no (nivel de prueba antiguo), reinicia la escena como antes.
func _catch_player() -> void:
	set_physics_process(false)
	var mission := get_tree().get_first_node_in_group("mission_manager") as MissionManager
	if mission:
		mission.on_player_caught("EL MURCIÉLAGO TE DEVORÓ", self)
	else:
		get_tree().call_deferred("reload_current_scene")


func _player_hidden() -> bool:
	return player != null and player.get("is_hidden") == true


# Escondido, solo lo atrapa si lo vio entrar o si hizo ruido hace un instante.
func _can_catch() -> bool:
	if not _player_hidden():
		return true
	if witnessed_hiding or locker_checks:
		return true
	return Time.get_ticks_msec() / 1000.0 - hidden_noise_time < hide_noise_window


func _on_player_hiding_changed(hidden: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	locker_checks = hidden and randf() < float(Difficulty.get_value("bat_locker"))
	if not Difficulty.get_value("bat_see_hide"):
		witnessed_hiding = false
		return
	witnessed_hiding = hidden and state == State.HUNT and now - last_seen_time < 1.0 \
		and global_position.distance_to(player.global_position) < 9.0


# Longitud real del camino (rodeando paredes) hasta un punto; INF si no hay camino.
func _path_distance(destination: Vector3) -> float:
	if nav == null:
		return global_position.distance_to(destination)
	return nav.path_length(global_position, destination)

# ============================================================== dificultad

var allied := false            ## Nivel 3: el grito del murciélago avisa al Eco
var ally_cd := 0.0
var locker_checks := false     ## En difícil: a veces abre el casillero donde te escondes
var flash_used := false
var tp_helper: Node


func _apply_difficulty() -> void:
	vision_range = Difficulty.get_value("bat_vision")
	vision_angle = Difficulty.get_value("bat_angle")
	flashlight_vision_multiplier = Difficulty.get_value("bat_flash_mul")
	var sp: float = Difficulty.get_value("bat_speed_mul")
	min_hunt_speed *= sp
	max_hunt_speed *= sp
	search_time = Difficulty.get_value("bat_forget")
	stun_immunity = Difficulty.get_value("stun_immunity")
	if Difficulty.get_value("tp_wait") > 0.0:
		tp_helper = FloorTeleport.new()
		tp_helper.creature = self
		tp_helper.is_bat = true
		add_child(tp_helper)


func set_allied(on: bool) -> void:
	allied = on


## El Eco oyó algo: el murciélago va hacia allá.
func _on_ally_alert(source: Node, pos: Vector3) -> void:
	if source == self or stun_left > 0.0 or (state == State.HUNT and last_seen_time > Time.get_ticks_msec() / 1000.0 - 3.0):
		return
	state = State.HUNT
	noise_target = pos
	hunt_speed = maxf(hunt_speed, min_hunt_speed)
	search_left = search_time
	_plan_path(pos)


## Llamado por FloorTeleport al aparecer en el piso del jugador: busca donde lo vio por última vez.
func _on_teleported(player_pos: Vector3) -> void:
	state = State.HUNT
	noise_target = player_pos
	hunt_speed = min_hunt_speed
	search_left = search_time
	_plan_path(noise_target)


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
## (todavía inmune tras despertar).
func stun(duration: float, kind := "dart", source_pos := Vector3.ZERO) -> bool:
	if stun_immune > 0.0:
		return false
	if kind == "flash" and Difficulty.get_value("flash_dodge") and flash_used:
		return false
	if kind == "flash":
		flash_used = true
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
	path = PackedVector3Array()
	speed_reset()


func speed_reset() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _on_woke() -> void:
	if mesh_model:
		mesh_model.rotation.x = 0.0
	if stun_kind == "dart" and stun_source != Vector3.ZERO:
		state = State.HUNT
		noise_target = stun_source
		hunt_speed = min_hunt_speed
		search_left = search_time
		_plan_path(noise_target)
	else:
		_start_wander()
