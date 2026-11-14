extends CharacterBody3D

const JUMP_VELOCITY := 4.5
const RUN_SPEED := 3.2
const WALKING_SPEED := 2.4
const ACCELERATION := 14.0
const DECELERATION := 18.0
const MIN_LOOK_ANGLE := deg_to_rad(-60.0)
const MAX_LOOK_ANGLE := deg_to_rad(70.0)
const FIRST_PERSON_HIDDEN_LAYER := 2
const INTERACTION_DISTANCE := 3.2
const ATTACK_DISTANCE := 3.2
const ATTACK_DAMAGE := 20.0
const MAX_HEALTH := 100.0
const TOUCH_LOOK_SENSITIVITY := 0.008
const UAL_LIBRARY_PATH := "res://assets/animations/UniversalAnimationLibrary/ual_mixamo_animations.tres"

@onready var flashlight_fill: OmniLight3D = $camera_mount/Camera3D/FlashlightFill
@onready var flashlight: SpotLight3D = $camera_mount/Camera3D/Flashlight
@onready var jumpscare_animation_player: AnimationPlayer = $JumpscareAnimationPlayer
@onready var jumpscare_audio: AudioStreamPlayer = $JumpscareAudio
@onready var game_over_menu: Control = $CanvasLayer/GameOverMenu
@onready var restart_button: Button = $CanvasLayer/GameOverMenu/CenterContainer/MenuPanel/MenuContent/RestartButton
@onready var camera_mount: Node3D = $camera_mount
@onready var camera: Camera3D = $camera_mount/Camera3D
@onready var key_text: Label = $CanvasLayer/BoxContainer/KeyText
@onready var fps_label: Label = $CanvasLayer/FpsLabel
@onready var animation_player: AnimationPlayer = $visuals/mixamo_base/AnimationPlayer
@onready var visuals: Node3D = $visuals

@export var sensitivity := 0.12
@export var FLASH_BY_DEFAULT: bool = false
@export_range(1.0, 100.0, 1.0) var max_health := MAX_HEALTH

var controls_enabled := true
var jumpscare_active := false
var health := MAX_HEALTH
var base_camera_position: Vector3
var bob_time := 0.0
var is_running := false
var look_pitch := 0.0
var touch_look_index := -1
var last_touch_look_position := Vector2.ZERO
var _interaction_target: Node = null
var _attack_cooldown := 0.0
var _health_bar: ProgressBar
var _health_label: Label
var _interact_button: Button
var _attack_button: Button
var _flash_button: Button
var _difficulty_button: Button
var _minimap_viewport: SubViewport
var _minimap_camera: Camera3D

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	base_camera_position = camera_mount.position
	camera.near = 0.05
	camera.cull_mask &= ~FIRST_PERSON_HIDDEN_LAYER
	_set_flashlight_visible(FLASH_BY_DEFAULT)
	_hide_from_first_person_camera(visuals)
	_install_universal_animations()
	key_text.hide()
	game_over_menu.hide()
	restart_button.pressed.connect(_on_restart_button_pressed)
	health = max_health
	_create_mobile_hud()

func _input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative * sensitivity)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventScreenTouch:
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.50:
			if event.pressed and touch_look_index == -1:
				touch_look_index = event.index
				last_touch_look_position = event.position
			elif not event.pressed and event.index == touch_look_index:
				touch_look_index = -1
	elif event is InputEventScreenDrag and event.index == touch_look_index:
			_apply_look((event.position - last_touch_look_position) * TOUCH_LOOK_SENSITIVITY / sensitivity)
			last_touch_look_position = event.position

func _apply_look(delta: Vector2) -> void:
	rotate_y(deg_to_rad(-delta.x))
	visuals.rotation.y = lerp_angle(visuals.rotation.y, deg_to_rad(delta.x), 0.35)
	look_pitch = clamp(look_pitch + deg_to_rad(-delta.y), MIN_LOOK_ANGLE, MAX_LOOK_ANGLE)
	camera_mount.rotation.x = look_pitch

func _physics_process(delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_handle_interaction()
	if not controls_enabled:
		velocity = Vector3.ZERO
		return
	is_running = Input.is_action_pressed("run")
	var speed := RUN_SPEED if is_running else WALKING_SPEED
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_animation(&"ual_jump_start")
	if Input.is_action_just_pressed("flash"):
		FLASH_BY_DEFAULT = not FLASH_BY_DEFAULT
		_set_flashlight_visible(FLASH_BY_DEFAULT)
	if Input.is_action_just_pressed("attack"):
		_attack_enemy()
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, -input_dir.y)).normalized()
	if direction.length_squared() > 0.001:
		_play_movement_animation()
		visuals.look_at(global_position + direction, Vector3.UP)
		velocity.x = move_toward(velocity.x, direction.x * speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, ACCELERATION * delta)
	else:
		_play_animation(&"ual_idle")
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)
	_update_camera_bob(delta, direction)
	move_and_slide()

func take_damage(amount: float, _source: Node = null) -> void:
	if not controls_enabled or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	_update_health_hud()
	if health <= 0.0:
		_die()

func _die() -> void:
	controls_enabled = false
	velocity = Vector3.ZERO
	_play_animation(&"ual_death")
	key_text.hide()
	if _health_label:
		_health_label.text = "YOU DIED"
	game_over_menu.show()
	var caught_label := game_over_menu.get_node_or_null("CenterContainer/MenuPanel/MenuContent/CaughtLabel") as Label
	if caught_label:
		caught_label.text = " YOU DIED"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func enemy_defeated() -> void:
	controls_enabled = false
	velocity = Vector3.ZERO
	game_over_menu.show()
	var caught_label := game_over_menu.get_node_or_null("CenterContainer/MenuPanel/MenuContent/CaughtLabel") as Label
	if caught_label:
		caught_label.text = " KILLER DEFEATED"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func start_jumpscare(_enemy: Node3D) -> void:
	return

func _handle_interaction() -> void:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + (-camera.global_basis.z * INTERACTION_DISTANCE))
	query.exclude = [self]
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_interaction_target = null
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		while collider and not collider.has_method("interact"):
			collider = collider.get_parent()
		if collider:
			_interaction_target = collider
	if _interaction_target:
		key_text.text = "TAP INTERACT  •  %s" % _interaction_target.name
		key_text.show()
		_interact_button.visible = true
	else:
		key_text.hide()
		_interact_button.visible = false
	if Input.is_action_just_pressed("interact") and _interaction_target:
		_interaction_target.interact()

func _attack_enemy() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 0.45
	_play_animation(&"ual_sword_attack")
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + (-camera.global_basis.z * ATTACK_DISTANCE))
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider := hit.get("collider") as Node
	while collider and not collider.has_method("take_damage"):
		collider = collider.get_parent()
	if collider:
		collider.take_damage(ATTACK_DAMAGE, self)

func _play_movement_animation() -> void:
	_play_animation(&"ual_sprint" if is_running else &"ual_jog")

func _play_animation(animation_name: StringName) -> void:
	if animation_player.has_animation(animation_name) and animation_player.current_animation != animation_name:
		animation_player.play(animation_name)

func _install_universal_animations() -> void:
	var universal_library := load(UAL_LIBRARY_PATH) as AnimationLibrary
	if universal_library == null:
		push_warning("Universal animation library could not be loaded")
		return
	var player_library := animation_player.get_animation_library("")
	var aliases := {
		"ual_idle": "Idle",
		"ual_jog": "Jog_Fwd",
		"ual_sprint": "Sprint",
		"ual_walk": "Walk",
		"ual_jump_start": "Jump_Start",
		"ual_jump_land": "Jump_Land",
		"ual_sword_attack": "Sword_Attack",
		"ual_death": "Death01",
		"ual_interact": "Interact"
	}
	for alias in aliases:
		var source_name: StringName = aliases[alias]
		if universal_library.has_animation(source_name) and not player_library.has_animation(alias):
			player_library.add_animation(alias, universal_library.get_animation(source_name).duplicate())

func _update_camera_bob(delta: float, direction: Vector3) -> void:
	var is_moving := direction.length() > 0.1 and is_on_floor()
	if is_moving:
		bob_time += delta * (2.0 if is_running else 1.5)
		var bob_strength := 0.045 if is_running else 0.025
		camera_mount.position.y = base_camera_position.y + sin(bob_time * 8.0) * bob_strength
		camera_mount.position.x = base_camera_position.x + cos(bob_time * 4.0) * bob_strength * 0.5
	else:
		bob_time = 0.0
		camera_mount.position = camera_mount.position.lerp(base_camera_position, minf(1.0, delta * 8.0))

func _create_mobile_hud() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.name = "PlayerHealthBar"
	_health_bar.position = Vector2(18, 48)
	_health_bar.size = Vector2(230, 28)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.show_percentage = false
	$CanvasLayer.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.position = Vector2(26, 49)
	_health_label.text = "HEALTH 100"
	_health_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.86))
	$CanvasLayer.add_child(_health_label)
	_interact_button = _make_button("INTERACT", Vector2(-205, -360), Vector2(180, 70))
	_interact_button.pressed.connect(_on_interact_pressed)
	_interact_button.visible = false
	_attack_button = _make_button("ATTACK", Vector2(-205, -280), Vector2(180, 70))
	_attack_button.pressed.connect(_attack_enemy)
	var difficulty := get_node_or_null("/root/Difficulty")
	_difficulty_button = _make_button("DIFFICULTY: %s" % (difficulty.display_name() if difficulty else "NORMAL"), Vector2(18, 84), Vector2(220, 48))
	_difficulty_button.pressed.connect(_cycle_difficulty)
	_flash_button = _make_top_left_button("FLASHLIGHT", Vector2(18, 142), Vector2(220, 52))
	_flash_button.pressed.connect(_toggle_flashlight)
	_create_minimap()

func _make_button(label: String, offset: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offset.x
	button.offset_top = offset.y
	button.offset_right = offset.x + button_size.x
	button.offset_bottom = offset.y + button_size.y
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.z_index = 20
	button.add_theme_font_size_override("font_size", 20)
	$CanvasLayer.add_child(button)
	return button

func _make_top_left_button(label: String, position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.position = position
	button.size = button_size
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.z_index = 20
	button.add_theme_font_size_override("font_size", 18)
	$CanvasLayer.add_child(button)
	return button

func _toggle_flashlight() -> void:
	FLASH_BY_DEFAULT = not FLASH_BY_DEFAULT
	_set_flashlight_visible(FLASH_BY_DEFAULT)

func _on_interact_pressed() -> void:
	if _interaction_target and is_instance_valid(_interaction_target):
		_interaction_target.interact()

func _cycle_difficulty() -> void:
	var difficulty := get_node_or_null("/root/Difficulty")
	if difficulty == null:
		return
	difficulty.cycle()
	_difficulty_button.text = "DIFFICULTY: %s" % difficulty.display_name()

func _update_health_hud() -> void:
	if _health_bar:
		_health_bar.value = health
	if _health_label:
		_health_label.text = "HEALTH %d" % roundi(health)

func _create_minimap() -> void:
	_minimap_viewport = SubViewport.new()
	_minimap_viewport.name = "MinimapViewport"
	_minimap_viewport.size = Vector2i(180, 180)
	_minimap_viewport.transparent_bg = false
	_minimap_viewport.world_3d = get_viewport().world_3d
	$CanvasLayer.add_child(_minimap_viewport)
	_minimap_camera = Camera3D.new()
	_minimap_camera.position = Vector3(0, 22, 0)
	_minimap_camera.rotation_degrees = Vector3(-90, 0, 0)
	_minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_minimap_camera.size = 32.0
	_minimap_camera.current = true
	_minimap_viewport.add_child(_minimap_camera)
	var map := TextureRect.new()
	map.name = "Minimap"
	map.texture = _minimap_viewport.get_texture()
	map.position = Vector2(-198, -198)
	map.size = Vector2(180, 180)
	map.anchor_left = 1.0
	map.anchor_top = 1.0
	map.anchor_right = 1.0
	map.anchor_bottom = 1.0
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer.add_child(map)

func _process(_delta: float) -> void:
	if _minimap_camera:
		_minimap_camera.global_position = global_position + Vector3.UP * 22.0
		_minimap_camera.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)

func _hide_from_first_person_camera(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = FIRST_PERSON_HIDDEN_LAYER
	for child in node.get_children():
		_hide_from_first_person_camera(child)

func _set_flashlight_visible(visible: bool) -> void:
	flashlight.visible = visible

func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()
