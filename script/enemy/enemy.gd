extends CharacterBody3D

## The three behaviours available to the enemy.
enum EnemyState {
	PATROL,
	CHASE,
	SEARCH,
}

const KILLER_MINIMAP_HIDDEN_LAYER := 4
const ZOMBIE_ANIM_PATH := "res://assets/animations/enemy/zombie_animations.tres"

@export_group("References")
@export var player_path: NodePath

@export_group("Movement")
@export var walking_speed := 1.5
@export var chasing_speed := 2.2
@export var turn_speed := 8.0
@export var arrival_distance := 0.8
@export var model_faces_positive_z := true

@export_group("Patrol")
@export var patrol_wait_time := 1.5

@export_group("Vision")
@export var vision_distance := 18.0
@export_range(1.0, 179.0, 1.0) var vision_angle_degrees := 75.0
@export var eye_height := 1.6
@export var automatic_detection_distance := 1.5
@export var lose_sight_delay := 2.5
@export_flags_3d_physics var vision_collision_mask := 1

@export_group("Search")
@export var search_duration := 10.0
@export var search_point_wait_time := 1.0
@export var search_radius := 8.0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

var player: Node3D
var current_state := EnemyState.PATROL
var patrol_points: Array[Node3D] = []
var current_destination := Vector3.ZERO
var last_known_player_position := Vector3.ZERO
var time_without_seeing_player := 0.0
var state_timer := 0.0
var wait_timer := 0.0
var last_patrol_point: Node3D
var random := RandomNumberGenerator.new()

@export_group("Jumpscare")
@export var catch_distance := 1.35
@export_group("Combat")
@export_range(1.0, 500.0, 1.0) var max_health := 150.0
@export var chainsaw_damage := 12.0
@export var attack_range := 1.8
@export var attack_cooldown := 1.0
@export_file("*.fbx", "*.glb") var replacement_body_path := "res://assets/models/enemy/uploaded/SkeletonzombieTAvelange.fbx"
@export var fallback_body_path := "res://assets/models/enemy/victor_gideon_in_resident_evil_requiem_mutated.glb"
@export var replacement_body_scale := 1.0
@export var chainsaw_scale := 0.025
@export var chainsaw_position := Vector3(0.03, 0.03, -0.08)
@export var chainsaw_rotation_degrees := Vector3(0.0, 0.0, -90.0)

@export_group("Procedural Killer Motion")
@export var procedural_motion_enabled := false
@export var idle_breath_height := 0.012
@export var movement_bob_height := 0.035
@export var movement_sway_degrees := 2.0
@export var attack_lunge_distance := 0.10

@onready var imported_animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var jumpscare_animation_player: AnimationPlayer = $JumpscareAnimationPlayer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


var has_caught_player := false
var health := 150.0
var attack_timer := 0.0
var dead := false
var _health_bar: ProgressBar
var _body_asset: Node3D
var _chainsaw_asset: Node3D
var _chainsaw_mount: Node3D
var _attack_animation_index := 1
var _body_base_position := Vector3.ZERO
var _body_base_rotation_degrees := Vector3.ZERO
var _body_motion_time := 0.0
var _body_attack_offset := Vector3.ZERO
var _body_attack_rotation_offset := Vector3.ZERO
var _chainsaw_attack_offset := Vector3.ZERO
var _body_attack_tween: Tween
var _chainsaw_attack_tween: Tween
var _body_anim_player: AnimationPlayer
var _body_anim_current := ""
var _body_attacking := false
var _body_attack_generation := 0





func _ready() -> void:
	random.randomize()
	health = max_health
	_try_add_replacement_body()
	_create_enemy_health_bar()

	player = get_node_or_null(player_path) as Node3D
	if player == null:
		push_error("Enemy could not find the player. Check player_path in the Inspector.")
		set_physics_process(false)
		return

	_collect_patrol_points()
	if patrol_points.is_empty():
		push_warning("No enemy patrol points were found. Add Marker3D nodes to the enemy_patrol_points group.")

	# Navigation maps synchronize after nodes enter the scene tree.
	# Waiting one physics frame prevents the first path request from happening too early.
	await get_tree().physics_frame
	_change_state(EnemyState.PATROL)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_update_procedural_body_motion(delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	_apply_gravity(delta)
	if _try_attack_player():
		_update_body_locomotion_animation()
		return

	_update_player_detection(delta)

	match current_state:
		EnemyState.PATROL:
			_update_patrol(delta)
		EnemyState.CHASE:
			_update_chase()
		EnemyState.SEARCH:
			_update_search(delta)

	move_and_slide()
	_update_body_locomotion_animation()


func _try_attack_player() -> bool:
	if player == null:
		return false

	var flat_offset := player.global_position - global_position
	flat_offset.y = 0.0

	if flat_offset.length() > attack_range:
		return false
	_stop_horizontal_movement()
	_turn_toward_direction(flat_offset.normalized(), get_physics_process_delta_time())
	if attack_timer <= 0.0 and player.has_method("take_damage"):
		var multiplier := 1.0
		var difficulty := get_node_or_null("/root/Difficulty")
		if difficulty:
			multiplier = difficulty.damage_multiplier()
		player.take_damage(chainsaw_damage * multiplier, self)
		attack_timer = difficulty.attack_interval() if difficulty else attack_cooldown
		_play_attack_animation()
	return true

func take_damage(amount: float, _source: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	if _health_bar:
		_health_bar.value = health
	if health <= 0.0:
		_die()

func _die() -> void:
	dead = true
	velocity = Vector3.ZERO
	set_physics_process(false)
	navigation_agent.target_position = global_position
	if _health_bar:
		_health_bar.visible = false
	_play_body_animation("death", 0.15)
	if player and player.has_method("enemy_defeated"):
		player.enemy_defeated()

func _play_attack_animation() -> void:
	if _body_anim_player == null:
		return
	_body_attacking = true
	_body_attack_generation += 1
	var generation := _body_attack_generation
	_play_body_animation("attack", 0.12)
	var length := 1.2
	if _body_anim_player.has_animation("attack"):
		length = _body_anim_player.get_animation("attack").length
	get_tree().create_timer(maxf(length - 0.12, 0.4)).timeout.connect(
		_finish_body_attack.bind(generation)
	)

func _finish_body_attack(generation: int) -> void:
	if generation == _body_attack_generation and not dead:
		_body_attacking = false

func _setup_body_animation() -> void:
	var library := load(ZOMBIE_ANIM_PATH) as AnimationLibrary
	if library == null:
		push_warning("Retargeted zombie animations could not be loaded: " + ZOMBIE_ANIM_PATH)
		return
	_body_anim_player = AnimationPlayer.new()
	_body_anim_player.name = "BodyAnimationPlayer"
	_body_asset.add_child(_body_anim_player)
	_body_anim_player.add_animation_library("", library)
	_body_anim_player.playback_default_blend_time = 0.25
	_play_body_animation("idle", 0.0)

func _play_body_animation(animation_name: StringName, blend := 0.25, speed := 1.0) -> void:
	if _body_anim_player == null or not _body_anim_player.has_animation(animation_name):
		return
	_body_anim_player.speed_scale = speed
	if _body_anim_current == animation_name and _body_anim_player.is_playing():
		return
	_body_anim_current = animation_name
	_body_anim_player.play(animation_name, blend)

func _update_body_locomotion_animation() -> void:
	if _body_anim_player == null or _body_attacking or dead:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var animation_name: StringName = &"idle"
	var playback := 1.0
	if speed > 0.12:
		if speed > 2.6:
			animation_name = &"sprint"
			playback = clampf(speed / 3.6, 0.85, 1.35)
		elif speed > 1.7:
			animation_name = &"jog"
			playback = clampf(speed / 2.4, 0.8, 1.35)
		else:
			animation_name = &"walk"
			playback = clampf(speed / 1.35, 0.7, 1.4)
	_play_body_animation(animation_name, 0.25, playback)

func _update_procedural_body_motion(delta: float) -> void:
	if not procedural_motion_enabled or _body_asset == null:
		return
	_body_motion_time += delta
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var movement_ratio := clampf(horizontal_speed / maxf(chasing_speed, 0.1), 0.0, 1.0)
	var gait_frequency := lerpf(1.8, 5.5, movement_ratio)
	var gait_phase := _body_motion_time * gait_frequency * TAU
	var breath := sin(_body_motion_time * 2.2) * idle_breath_height
	var bob := sin(gait_phase) * movement_bob_height * movement_ratio
	var sway := cos(gait_phase * 0.5) * movement_sway_degrees * movement_ratio
	var target_position := _body_base_position + Vector3(0.0, breath + bob, 0.0) + _body_attack_offset
	var target_rotation := _body_base_rotation_degrees + Vector3(sin(gait_phase) * movement_sway_degrees * 0.35 * movement_ratio, sway, cos(gait_phase) * movement_sway_degrees * 0.25 * movement_ratio) + _body_attack_rotation_offset
	_body_asset.position = _body_asset.position.lerp(target_position, clampf(delta * 12.0, 0.0, 1.0))
	_body_asset.rotation_degrees = _body_asset.rotation_degrees.lerp(target_rotation, clampf(delta * 12.0, 0.0, 1.0))

func _try_add_replacement_body() -> void:
	var killer_visuals := Node3D.new()
	killer_visuals.name = "KillerReplacementVisuals"
	add_child(killer_visuals)
	var body_scene := load(replacement_body_path) as PackedScene
	if body_scene == null:
		body_scene = load(fallback_body_path) as PackedScene
	if body_scene:
		_body_asset = body_scene.instantiate() as Node3D
		_body_asset.name = "KillerReplacementBody"
		_body_asset.scale = Vector3.ONE * replacement_body_scale
		_body_asset.position.y = 0.0
		killer_visuals.add_child(_body_asset)
		_set_visual_layer(_body_asset, KILLER_MINIMAP_HIDDEN_LAYER)
		_body_base_position = _body_asset.position
		_body_base_rotation_degrees = _body_asset.rotation_degrees
		_setup_body_animation()
		for legacy_path in ["Skeleton3D/body2_model0_smd", "Skeleton3D/full"]:
			var legacy_mesh := get_node_or_null(legacy_path) as VisualInstance3D
			if legacy_mesh:
				legacy_mesh.visible = false
	else:
		push_warning("No replacement killer body could be loaded; keeping the original enemy body visible")
		return

	var chainsaw_scene := load("res://assets/models/enemy/chainsaw/scene.gltf") as PackedScene
	if chainsaw_scene:
		_chainsaw_asset = chainsaw_scene.instantiate() as Node3D
		_chainsaw_asset.name = "RE4RChainsaw"
		_chainsaw_asset.position = chainsaw_position
		_chainsaw_asset.rotation_degrees = chainsaw_rotation_degrees
		_chainsaw_asset.scale = Vector3.ONE * chainsaw_scale
		_chainsaw_mount = _find_right_hand_mount(_body_asset)
		(_chainsaw_mount if _chainsaw_mount else killer_visuals).add_child(_chainsaw_asset)
		# The asset ships a bloody and a clean duplicate plus physics-bone
		# simulators; keep one prop and let the hand drive it.
		var clean_variant := _chainsaw_asset.find_child("Armature_2", true, false)
		if clean_variant:
			clean_variant.visible = false
		for simulator in _chainsaw_asset.find_children("*", "PhysicalBoneSimulator3D", true, false):
			simulator.active = false
		_set_visual_layer(_chainsaw_asset, KILLER_MINIMAP_HIDDEN_LAYER)
	else:
		push_warning("Chainsaw glTF could not be loaded from res://assets/models/enemy/chainsaw/scene.gltf")

func _find_right_hand_mount(body: Node3D) -> Node3D:
	var skeleton := body.get_node_or_null("Skeleton3D") as Skeleton3D
	if skeleton == null or skeleton.find_bone("mixamorig_RightHand") < 0:
		return body
	var attachment := BoneAttachment3D.new()
	attachment.name = "ChainsawRightHandAttachment"
	attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(attachment)
	return attachment

func _set_visual_layer(node: Node, layer: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1 << (layer - 1)
	for child in node.get_children():
		_set_visual_layer(child, layer)

func _create_enemy_health_bar() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.name = "EnemyHealthBar"
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.show_percentage = false
	_health_bar.size = Vector2(180, 16)
	_health_bar.position = Vector2(-90, -110)
	_health_bar.visible = false
	add_child(_health_bar)



func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0


func _update_player_detection(delta: float) -> void:
	if _can_see_player():
		last_known_player_position = player.global_position
		time_without_seeing_player = 0.0

		if current_state != EnemyState.CHASE:
			_change_state(EnemyState.CHASE)
		return

	if current_state == EnemyState.CHASE:
		time_without_seeing_player += delta
		if time_without_seeing_player >= lose_sight_delay:
			_change_state(EnemyState.SEARCH)


func _can_see_player() -> bool:
	if player == null:
		return false

	var to_player := player.global_position - global_position
	var distance_to_player := to_player.length()

	if distance_to_player > vision_distance:
		return false

	# Very close players are detected even if they stand slightly behind the enemy.
	if distance_to_player <= automatic_detection_distance:
		return _has_clear_line_to_player()

	var flat_direction := Vector3(to_player.x, 0.0, to_player.z).normalized()
	var enemy_forward := global_basis.z if model_faces_positive_z else -global_basis.z
	enemy_forward.y = 0.0
	enemy_forward = enemy_forward.normalized()

	var minimum_dot := cos(deg_to_rad(vision_angle_degrees * 0.5))
	if enemy_forward.dot(flat_direction) < minimum_dot:
		return false

	return _has_clear_line_to_player()


func _has_clear_line_to_player() -> bool:
	var ray_start := global_position + Vector3.UP * eye_height
	var ray_end := player.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		vision_collision_mask
	)
	query.exclude = [self]
	query.collide_with_areas = false

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	# An empty result means no wall blocked the ray before it reached the player.
	if hit.is_empty():
		return true

	var collider := hit.get("collider") as Node
	return collider == player or (collider != null and player.is_ancestor_of(collider))


func _change_state(new_state: EnemyState) -> void:
	if current_state == new_state and new_state != EnemyState.PATROL:
		return

	current_state = new_state
	wait_timer = 0.0

	match current_state:
		EnemyState.PATROL:
			time_without_seeing_player = 0.0
			_choose_random_patrol_point()

		EnemyState.CHASE:
			time_without_seeing_player = 0.0
			last_known_player_position = player.global_position
			navigation_agent.target_position = last_known_player_position

		EnemyState.SEARCH:
			state_timer = search_duration
			_set_destination(last_known_player_position)

	print("Enemy state changed to: ", EnemyState.keys()[current_state])


func _update_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		_stop_horizontal_movement()
		return

	if _has_reached_destination():
		_stop_horizontal_movement()
		wait_timer += delta

		if wait_timer >= patrol_wait_time:
			wait_timer = 0.0
			_choose_random_patrol_point()
		return

	_move_along_navigation_path(_difficulty_speed(walking_speed), delta)


func _update_chase() -> void:
	# Update the destination every frame while the player is visible or during
	# the short lose_sight_delay memory period.
	current_destination = last_known_player_position
	navigation_agent.target_position = last_known_player_position
	_move_along_navigation_path(_difficulty_speed(chasing_speed), get_physics_process_delta_time())


func _update_search(delta: float) -> void:
	state_timer -= delta

	if state_timer <= 0.0:
		_change_state(EnemyState.PATROL)
		return

	if _has_reached_destination():
		_stop_horizontal_movement()
		wait_timer += delta

		if wait_timer >= search_point_wait_time:
			wait_timer = 0.0
			_choose_nearby_search_point()
		return

	_move_along_navigation_path(_difficulty_speed(walking_speed), delta)


func _move_along_navigation_path(speed: float, delta: float) -> void:
	if navigation_agent.is_navigation_finished():
		_stop_horizontal_movement()
		return

	var next_path_position := navigation_agent.get_next_path_position()
	var direction := next_path_position - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.0001:
		_stop_horizontal_movement()
		return

	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_turn_toward_direction(direction, delta)


func _turn_toward_direction(direction: Vector3, delta: float) -> void:
	var target_yaw := (
		atan2(direction.x, direction.z)
		if model_faces_positive_z
		else atan2(-direction.x, -direction.z)
	)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)


func _stop_horizontal_movement() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func _difficulty_speed(base_speed: float) -> float:
	var difficulty := get_node_or_null("/root/Difficulty")
	if difficulty:
		return base_speed * difficulty.speed_multiplier()
	return base_speed


func _set_destination(destination: Vector3) -> void:
	current_destination = destination
	navigation_agent.target_position = destination


func _has_reached_destination() -> bool:
	var flat_offset := current_destination - global_position
	flat_offset.y = 0.0
	return (
		flat_offset.length() <= arrival_distance
		or navigation_agent.is_navigation_finished()
	)


func _collect_patrol_points() -> void:
	patrol_points.clear()

	for node in get_tree().get_nodes_in_group("enemy_patrol_points"):
		if node is Node3D:
			patrol_points.append(node as Node3D)


func _choose_random_patrol_point() -> void:
	if patrol_points.is_empty():
		return

	var candidates := patrol_points.duplicate()
	if last_patrol_point != null and candidates.size() > 1:
		candidates.erase(last_patrol_point)

	var chosen_point: Node3D = candidates[random.randi_range(0, candidates.size() - 1)]
	last_patrol_point = chosen_point
	_set_destination(chosen_point.global_position)


func _choose_nearby_search_point() -> void:
	var nearby_points: Array[Node3D] = []

	for point in patrol_points:
		if point.global_position.distance_to(last_known_player_position) <= search_radius:
			nearby_points.append(point)

	if nearby_points.is_empty():
		# If there are no markers nearby, check the last known position again.
		_set_destination(last_known_player_position)
		return

	var chosen_point: Node3D = nearby_points[random.randi_range(0, nearby_points.size() - 1)]
	_set_destination(chosen_point.global_position)


## Future noise-system hook. Calling this currently does nothing.
func hear_noise(_noise_position: Vector3, _loudness := 1.0) -> void:
	pass


## Future hook for noises caused by a door or interactive object.
func hear_interaction_noise(_noise_position: Vector3) -> void:
	pass
