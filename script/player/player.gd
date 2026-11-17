extends CharacterBody3D

const JUMP_VELOCITY := 4.5
const RUN_SPEED := 3.2
const WALKING_SPEED := 2.4
const ACCELERATION := 14.0
const DECELERATION := 18.0
const MIN_LOOK_ANGLE := deg_to_rad(-60.0)
const MAX_LOOK_ANGLE := deg_to_rad(70.0)
const FIRST_PERSON_HIDDEN_LAYER := 2
const KILLER_MINIMAP_HIDDEN_LAYER := 4
const INTERACTION_DISTANCE := 3.2
const ATTACK_DISTANCE := 3.2
const ATTACK_DAMAGE := 20.0
const MAX_HEALTH := 100.0
const TOUCH_LOOK_SENSITIVITY := 0.008
const UAL_LIBRARY_PATH := "res://assets/animations/UniversalAnimationLibrary/ual_mixamo_animations.tres"
const STANCE_TAP_WINDOW := 0.4
const CROUCH_SPEED_MULTIPLIER := 0.55
const PRONE_SPEED_MULTIPLIER := 0.25
const LOOK_JOYSTICK_YAW_SPEED := 2.8
const LOOK_JOYSTICK_PITCH_SPEED := 1.8

enum Stance {
	STAND,
	CROUCH,
	PRONE,
}

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
var stance := Stance.STAND
var _stance_taps := 0
var _stance_tap_timer := 0.0
var _sprint_toggled := false
var _flash_on := false
var _look_joystick: Node
var _hud_controls: Array[Control] = []
var _sprint_button: Button
var _stance_button: Button
var _stance_label: Label
var _inventory_button: Button
var _inventory_open_last_frame := false
var _inventory_hud_visibility: Dictionary = {}
var _touch_controls: CanvasLayer
var _touch_controls_visible_before_inventory := true

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	base_camera_position = camera_mount.position
	camera.near = 0.05
	camera.cull_mask &= ~FIRST_PERSON_HIDDEN_LAYER
	_flash_on = FLASH_BY_DEFAULT
	_set_flashlight_visible(FLASH_BY_DEFAULT)
	_hide_from_first_person_camera(visuals)
	_install_universal_animations()
	key_text.hide()
	game_over_menu.hide()
	restart_button.pressed.connect(_on_restart_button_pressed)
	health = max_health
	_create_mobile_hud()
	_find_touch_controls()

func _input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	var inventory_ui := _get_inventory_ui()
	if inventory_ui and inventory_ui.visible and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton):
		return
	if _look_joystick and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_apply_look(event.relative * sensitivity)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventScreenTouch:
		if event.pressed and _is_touch_over_hud(event.position):
			return
		if event.position.x > get_viewport().get_visible_rect().size.x * 0.50:
			if event.pressed and touch_look_index == -1:
				touch_look_index = event.index
				last_touch_look_position = event.position
			elif not event.pressed and event.index == touch_look_index:
				touch_look_index = -1
	elif event is InputEventScreenDrag and event.index == touch_look_index:
			if _is_touch_over_hud(event.position):
				return
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
	var inventory_ui := _get_inventory_ui()
	if inventory_ui and inventory_ui.visible:
		if not _inventory_open_last_frame:
			_set_inventory_hud_hidden(true)
		_inventory_open_last_frame = true
		_interaction_target = null
		key_text.hide()
		_interact_button.visible = false
		velocity = Vector3.ZERO
		return
	if _inventory_open_last_frame:
		_set_inventory_hud_hidden(false)
		_inventory_open_last_frame = false
	_handle_interaction()
	if not controls_enabled:
		velocity = Vector3.ZERO
		return
	_update_look_joystick(delta)
	is_running = Input.is_action_pressed("run") or _sprint_toggled
	var speed := (RUN_SPEED if is_running else WALKING_SPEED) * _stance_speed_multiplier()
	if not is_on_floor():
		velocity += get_gravity() * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and stance == Stance.STAND:
		velocity.y = JUMP_VELOCITY
		_play_animation(&"ual_jump_start")
	if Input.is_action_just_pressed("flash"):
		_toggle_flashlight()
	if Input.is_action_just_pressed("attack"):
		_attack_enemy()
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	# Input.get_vector returns a negative Y value for the forward action.
	# Do not negate it again: the camera/player forward direction is -Z.
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
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

func heal(amount: float) -> float:
	if amount <= 0.0 or health <= 0.0 or not controls_enabled:
		return 0.0
	var restored := minf(amount, max_health - health)
	if restored <= 0.0:
		return 0.0
	health = minf(max_health, health + restored)
	_update_health_hud()
	return restored

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
		if _interaction_target.has_method("get_interaction_prompt"):
			key_text.text = _interaction_target.get_interaction_prompt()
		else:
			key_text.text = "TAP INTERACT  •  %s" % _interaction_target.name
		key_text.show()
		_interact_button.visible = true
	else:
		key_text.hide()
		_interact_button.visible = false
	if Input.is_action_just_pressed("interact") and _interaction_target:
		_play_animation(&"ual_interact")
		_interact_with_target(_interaction_target)

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
	var eye_height := _eye_height()
	if is_moving:
		bob_time += delta * (2.0 if is_running else 1.5)
		var bob_strength := 0.045 if is_running else 0.025
		camera_mount.position.y = eye_height + sin(bob_time * 8.0) * bob_strength
		camera_mount.position.x = base_camera_position.x + cos(bob_time * 4.0) * bob_strength * 0.5
	else:
		bob_time = 0.0
		var target := Vector3(base_camera_position.x, eye_height, base_camera_position.z)
		camera_mount.position = camera_mount.position.lerp(target, minf(1.0, delta * 8.0))

func _create_mobile_hud() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.name = "PlayerHealthBar"
	_health_bar.position = Vector2(18, 48)
	_health_bar.size = Vector2(230, 28)
	_health_bar.max_value = max_health
	_health_bar.value = health
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.z_index = 10
	$CanvasLayer.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.position = Vector2(26, 49)
	_health_label.text = "HEALTH 100"
	_health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_label.z_index = 11
	_health_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.86))
	$CanvasLayer.add_child(_health_label)
	# Right-thumb cluster: attack to the left of the look stick, with the
	# stance / flashlight / sprint row along the stick's upper edge.
	_attack_button = _make_icon_button(
	"res://assets/ui/icons/attack.svg", Vector2(124, 124), Vector2(-420, -180), _attack_enemy
	)
	_sprint_button = _make_icon_button(
	"res://assets/ui/icons/run.svg", Vector2(72, 72), Vector2(-330, -336), _on_sprint_pressed
	)
	_flash_button = _make_icon_button(
	"res://assets/ui/icons/flashlight.svg", Vector2(72, 72), Vector2(-246, -336), _on_flash_pressed
	)
	_stance_button = _make_icon_button(
	"res://assets/ui/icons/crouch.svg", Vector2(72, 72), Vector2(-162, -336), _on_stance_pressed
	)
	_stance_label = Label.new()
	_stance_label.text = "STAND"
	_stance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stance_label.anchor_left = 1.0
	_stance_label.anchor_top = 1.0
	_stance_label.anchor_right = 1.0
	_stance_label.anchor_bottom = 1.0
	_stance_label.offset_left = -162.0
	_stance_label.offset_top = -260.0
	_stance_label.offset_right = -90.0
	_stance_label.offset_bottom = -244.0
	_stance_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stance_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stance_label.add_theme_font_size_override("font_size", 12)
	_stance_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_stance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stance_label.z_index = 20
	$CanvasLayer.add_child(_stance_label)
	_hud_controls.append(_stance_label)
	_interact_button = _make_icon_button(
	"res://assets/ui/icons/interact.svg", Vector2(96, 96), Vector2(-552, -166), _on_interact_pressed
	)
	_interact_button.visible = false
	var difficulty := get_node_or_null("/root/Difficulty")
	_difficulty_button = _make_top_left_button(
	"DIFFICULTY: %s" % (difficulty.display_name() if difficulty else "NORMAL"),
	Vector2(18, 84), Vector2(210, 44)
	)
	_difficulty_button.pressed.connect(_cycle_difficulty)
	_inventory_button = _make_top_left_icon_button(
		"res://assets/ui/icons/inventory.svg", Vector2(18, 140), Vector2(58, 58), _toggle_inventory
	)
	_create_minimap()
	_update_flash_button_visual()

func _make_icon_button(icon_path: String, button_size: Vector2, offset: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.icon = load(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", int(button_size.x * 0.52))
	button.custom_minimum_size = button_size
	button.size = button_size
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
	var radius := int(button_size.x * 0.5)
	button.add_theme_stylebox_override("normal", _circle_style(Color(0.02, 0.02, 0.03, 0.55), Color(1, 1, 1, 0.28), radius))
	button.add_theme_stylebox_override("hover", _circle_style(Color(0.08, 0.08, 0.1, 0.7), Color(1, 1, 1, 0.5), radius))
	button.add_theme_stylebox_override("pressed", _circle_style(Color(0.15, 0.13, 0.2, 0.8), Color(0.8, 0.75, 1, 0.8), radius))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	$CanvasLayer.add_child(button)
	_hud_controls.append(button)
	return button

func _circle_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style

func _make_top_left_button(label: String, position: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.text = label
	button.position = position
	button.size = button_size
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.z_index = 20
	button.add_theme_font_size_override("font_size", 16)
	$CanvasLayer.add_child(button)
	_hud_controls.append(button)
	return button

func _make_top_left_icon_button(icon_path: String, position: Vector2, button_size: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.icon = load(icon_path)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", int(button_size.x * 0.52))
	button.position = position
	button.custom_minimum_size = button_size
	button.size = button_size
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = "Inventory"
	button.z_index = 20
	var radius := int(button_size.x * 0.5)
	button.add_theme_stylebox_override("normal", _circle_style(Color(0.02, 0.02, 0.03, 0.55), Color(1, 1, 1, 0.28), radius))
	button.add_theme_stylebox_override("hover", _circle_style(Color(0.08, 0.08, 0.1, 0.7), Color(1, 1, 1, 0.5), radius))
	button.add_theme_stylebox_override("pressed", _circle_style(Color(0.15, 0.13, 0.2, 0.8), Color(0.8, 0.75, 1, 0.8), radius))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	$CanvasLayer.add_child(button)
	_hud_controls.append(button)
	return button

func _get_inventory_ui() -> CanvasLayer:
	return get_tree().get_first_node_in_group("inventory_ui") as CanvasLayer

func _toggle_inventory() -> void:
	var inventory_ui := _get_inventory_ui()
	if inventory_ui and inventory_ui.has_method("toggle_inventory"):
		inventory_ui.toggle_inventory()

func _set_inventory_hud_hidden(hidden: bool) -> void:
	if hidden:
		_inventory_hud_visibility.clear()
		for control in _hud_controls:
			if control == _inventory_button:
				continue
			_inventory_hud_visibility[control] = control.visible
			control.visible = false
		if _touch_controls:
			_touch_controls_visible_before_inventory = _touch_controls.visible
			_touch_controls.visible = false
	else:
		for control in _inventory_hud_visibility:
			if is_instance_valid(control):
				control.visible = bool(_inventory_hud_visibility[control])
		_inventory_hud_visibility.clear()
		if _touch_controls:
			_touch_controls.visible = _touch_controls_visible_before_inventory

func _toggle_flashlight() -> void:
	_flash_on = not _flash_on
	FLASH_BY_DEFAULT = _flash_on
	_set_flashlight_visible(_flash_on)
	_update_flash_button_visual()

func _update_flash_button_visual() -> void:
	if _flash_button:
		_flash_button.modulate = Color(1.0, 0.95, 0.55) if _flash_on else Color.WHITE

func _on_flash_pressed() -> void:
	_toggle_flashlight()

func _on_sprint_pressed() -> void:
	_sprint_toggled = not _sprint_toggled
	if _sprint_button:
		_sprint_button.modulate = Color(0.55, 1.0, 0.6) if _sprint_toggled else Color.WHITE

func _on_stance_pressed() -> void:
	_stance_taps += 1
	_stance_tap_timer = STANCE_TAP_WINDOW

func _resolve_stance_taps() -> void:
	var taps := _stance_taps
	_stance_taps = 0
	if taps >= 3:
		_set_stance(Stance.STAND)
	elif taps == 2:
		_set_stance(Stance.PRONE)
	else:
		_set_stance(Stance.CROUCH)

func _set_stance(new_stance: Stance) -> void:
	stance = new_stance
	if _stance_button:
		match stance:
			Stance.PRONE:
				_stance_button.icon = load("res://assets/ui/icons/prone.svg")
				_stance_button.modulate = Color(0.6, 0.8, 1.0)
			Stance.CROUCH:
				_stance_button.icon = load("res://assets/ui/icons/crouch.svg")
				_stance_button.modulate = Color(1.0, 0.85, 0.5)
			_:
				_stance_button.icon = load("res://assets/ui/icons/crouch.svg")
				_stance_button.modulate = Color.WHITE
	if _stance_label:
		_stance_label.text = ["STAND", "CROUCH", "PRONE"][stance]

func _eye_height() -> float:
	match stance:
		Stance.CROUCH:
			return base_camera_position.y * 0.62
		Stance.PRONE:
			return base_camera_position.y * 0.30
		_:
			return base_camera_position.y

func _stance_speed_multiplier() -> float:
	match stance:
		Stance.CROUCH:
			return CROUCH_SPEED_MULTIPLIER
		Stance.PRONE:
			return PRONE_SPEED_MULTIPLIER
		_:
			return 1.0

func _find_touch_controls() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var touch := scene.find_child("TouchControllers", true, false)
	if touch == null:
		return
	_touch_controls = touch as CanvasLayer
	_look_joystick = touch.find_child("LookJoystick", true, false)

func _update_look_joystick(delta: float) -> void:
	if _look_joystick == null:
		return
	var output: Vector2 = _look_joystick.output
	if output.length_squared() < 0.01:
		return
	rotate_y(-output.x * LOOK_JOYSTICK_YAW_SPEED * delta)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, deg_to_rad(output.x * 8.0), 0.35)
	look_pitch = clampf(look_pitch - output.y * LOOK_JOYSTICK_PITCH_SPEED * delta, MIN_LOOK_ANGLE, MAX_LOOK_ANGLE)
	camera_mount.rotation.x = look_pitch

func _on_interact_pressed() -> void:
	if _interaction_target and is_instance_valid(_interaction_target):
		_play_animation(&"ual_interact")
		_interact_with_target(_interaction_target)

func _interact_with_target(target_node: Node) -> void:
	if target_node.has_method("set_interactor"):
		target_node.set_interactor(self)
	if target_node.has_method("interact"):
		target_node.interact()

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
	_minimap_camera.cull_mask = 0xFFFFFFFF ^ (1 << (KILLER_MINIMAP_HIDDEN_LAYER - 1))
	_minimap_camera.current = true
	_minimap_viewport.add_child(_minimap_camera)
	var map := TextureRect.new()
	map.name = "Minimap"
	map.texture = _minimap_viewport.get_texture()
	map.anchor_left = 1.0
	map.anchor_top = 0.0
	map.anchor_right = 1.0
	map.anchor_bottom = 0.0
	map.offset_left = -198.0
	map.offset_top = 18.0
	map.offset_right = -18.0
	map.offset_bottom = 198.0
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.z_index = 10
	$CanvasLayer.add_child(map)
	_hud_controls.append(map)

func _is_touch_over_hud(position: Vector2) -> bool:
	for control in _hud_controls:
		if control and control.visible and control.get_global_rect().has_point(position):
			return true
	return false

func _process(delta: float) -> void:
	if _minimap_camera:
		_minimap_camera.global_position = global_position + Vector3.UP * 22.0
		_minimap_camera.global_rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	if _stance_tap_timer > 0.0:
		_stance_tap_timer -= delta
		if _stance_tap_timer <= 0.0:
			_resolve_stance_taps()

func _hide_from_first_person_camera(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = FIRST_PERSON_HIDDEN_LAYER
	for child in node.get_children():
		_hide_from_first_person_camera(child)

func _set_flashlight_visible(visible: bool) -> void:
	flashlight.visible = visible
	flashlight_fill.visible = visible

func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()
