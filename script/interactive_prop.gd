extends StaticBody3D
class_name InteractiveProp

const PICKUP_SCENE := preload("res://scenes/pickup_item.tscn")

@export var display_name := "OBJECT"
@export var interaction_kind := "furniture"
@export var open_angle_degrees := 88.0
@export var drawer_slide_distance := 0.42

var target: Node3D
var animated_door: AnimatedDoor
var _opened := false
var _busy := false
var _closed_rotation := Vector3.ZERO
var _closed_scale := Vector3.ONE
var _closed_position := Vector3.ZERO
var _collision_shape: CollisionShape3D
var _cabinet_pivot: Node3D
var _hinge_point := Vector3.ZERO
var _open_sign := 1.0
var _interactor: Node3D
var _loot_spawned := false
var _action_tween: Tween

func configure(target_node: Node3D, label: String, kind: String) -> void:
	target = target_node
	display_name = label
	interaction_kind = kind
	if target:
		_closed_rotation = target.rotation
		_closed_scale = target.scale
		_closed_position = target.position
	name = "Interactable_" + display_name.replace(" ", "_")

func configure_cabinet_panel(hinge_point: Vector3, open_sign: float) -> void:
	_hinge_point = hinge_point
	_open_sign = signf(open_sign) if not is_zero_approx(open_sign) else 1.0

func set_interactor(actor: Node3D) -> void:
	_interactor = actor

func get_interaction_prompt() -> String:
	match interaction_kind:
		"door":
			return "TAP OPEN / CLOSE  •  DOOR"
		"cabinet_panel":
			return "TAP OPEN / CLOSE  •  CABINET"
		"drawer":
			return "TAP OPEN / CLOSE  •  DRAWER"
		_:
			return "TAP SEARCH  •  %s" % display_name.to_upper()

func interact() -> void:
	if _busy or target == null or not is_instance_valid(target):
		return
	_busy = true
	match interaction_kind:
		"door":
			_toggle_door()
		"cabinet_panel":
			_toggle_cabinet_panel()
		"drawer":
			_toggle_named_drawer()
		_:
			_examine_furniture()
	_busy = false

func set_collision_shape(shape_node: CollisionShape3D) -> void:
	_collision_shape = shape_node

func _toggle_door() -> void:
	if animated_door and is_instance_valid(animated_door):
		animated_door.toggle()
		if _collision_shape:
			_collision_shape.set_deferred("disabled", animated_door.is_open)
		return
	# Fallback for door panels without the supplied animated rig: hinge on the
	# panel's vertical edge rather than tipping the mesh flat.
	_opened = not _opened
	if _collision_shape:
		_collision_shape.set_deferred("disabled", _opened)
	var mesh := target as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return
	var world_aabb: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var hinge := world_aabb.get_center()
	if world_aabb.size.x >= world_aabb.size.z:
		hinge.z -= world_aabb.size.z * 0.5
	else:
		hinge.x -= world_aabb.size.x * 0.5
	var pivot := Node3D.new()
	pivot.name = "DoorHinge"
	mesh.get_parent().add_child(pivot)
	pivot.global_transform = Transform3D(Basis.IDENTITY, hinge)
	mesh.reparent(pivot, true)
	var angle := deg_to_rad(open_angle_degrees) * (-1.0 if _opened else 0.0)
	_kill_tween()
	_action_tween = create_tween()
	_action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(pivot, "rotation:y", angle, 0.62)

func _toggle_cabinet_panel() -> void:
	_opened = not _opened
	if _cabinet_pivot == null:
		var pivot_parent := get_tree().current_scene
		if pivot_parent == null:
			pivot_parent = target.get_parent()
		if pivot_parent == null:
			return
		_cabinet_pivot = Node3D.new()
		_cabinet_pivot.name = "CabinetHinge"
		pivot_parent.add_child(_cabinet_pivot)
		_cabinet_pivot.global_transform = Transform3D(Basis.IDENTITY, _hinge_point)
		target.reparent(_cabinet_pivot, true)
	if _collision_shape:
		_collision_shape.set_deferred("disabled", _opened)
	_kill_tween()
	_action_tween = create_tween()
	_action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var end_angle := deg_to_rad(open_angle_degrees) * _open_sign if _opened else 0.0
	_action_tween.tween_property(_cabinet_pivot, "rotation:y", end_angle, 0.62)
	if _opened and not _loot_spawned:
		_loot_spawned = true
		_spawn_drawer_loot()

func _toggle_named_drawer() -> void:
	_opened = not _opened
	if _collision_shape:
		_collision_shape.set_deferred("disabled", _opened)
	var world_direction := target.global_basis.z.normalized()
	world_direction.y = 0.0
	if _interactor and target.get_parent():
		var toward_player := _interactor.global_position - target.global_position
		toward_player.y = 0.0
		if toward_player.length_squared() > 0.001:
			world_direction = toward_player.normalized()
	var parent_node := target.get_parent() as Node3D
	var local_slide: Vector3 = parent_node.global_basis.inverse() * world_direction * drawer_slide_distance if parent_node else world_direction * drawer_slide_distance
	var destination: Vector3 = _closed_position + local_slide if _opened else _closed_position
	_kill_tween()
	_action_tween = create_tween()
	_action_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(target, "position", destination, 0.48)
	if _opened and not _loot_spawned:
		_loot_spawned = true
		_spawn_drawer_loot()

func _spawn_drawer_loot() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var loot_index := int(scene_root.get_meta("storage_loot_sequence", 0))
	scene_root.set_meta("storage_loot_sequence", loot_index + 1)
	var loot_id := "metal_scrap"
	var loot_name := "Metal Scrap"
	var loot_icon := "res://assets/ui/icons/scrap.svg"
	var loot_color := Color(0.5, 0.72, 0.78)
	match loot_index % 4:
		1:
			loot_id = "bandage"
			loot_name = "Bandage"
			loot_icon = "res://assets/ui/icons/bandage.svg"
			loot_color = Color(0.86, 0.75, 0.62)
		3:
			loot_id = "first_aid_kit"
			loot_name = "First Aid Kit"
			loot_icon = "res://assets/ui/icons/first_aid_kit.svg"
			loot_color = Color(0.9, 0.9, 0.84)
	var pickup := PICKUP_SCENE.instantiate() as WorldPickup
	pickup.configure_pickup(loot_id, loot_name, loot_icon, loot_color)
	scene_root.add_child(pickup)
	var origin := target.global_position
	var direction := Vector3.FORWARD
	if _interactor:
		direction = _interactor.global_position - origin
		direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = target.global_basis.z
	direction.y = 0.0
	direction = direction.normalized()
	pickup.global_position = origin + direction * 0.68 + Vector3.UP * 0.1

func _examine_furniture() -> void:
	_kill_tween()
	_action_tween = create_tween()
	_action_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_action_tween.tween_property(target, "scale", _closed_scale * 1.035, 0.12)
	_action_tween.tween_property(target, "scale", _closed_scale, 0.18)

func _kill_tween() -> void:
	if _action_tween and _action_tween.is_running():
		_action_tween.kill()
