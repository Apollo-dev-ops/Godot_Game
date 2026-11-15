extends StaticBody3D
class_name InteractiveProp

@export var display_name := "OBJECT"
@export var interaction_kind := "furniture"
@export var open_angle_degrees := 88.0

var target: Node3D
var _opened := false
var _busy := false
var _closed_rotation := Vector3.ZERO
var _closed_scale := Vector3.ONE
var _collision_shape: CollisionShape3D

func configure(target_node: Node3D, label: String, kind: String) -> void:
	target = target_node
	display_name = label
	interaction_kind = kind
	if target:
		_closed_rotation = target.rotation
		_closed_scale = target.scale
	name = "Interactable_" + display_name.replace(" ", "_")

func interact() -> void:
	if _busy or target == null or not is_instance_valid(target):
		return
	_busy = true
	if interaction_kind == "door":
		_open_door()
	else:
		_examine_furniture()
	_busy = false

func set_collision_shape(shape_node: CollisionShape3D) -> void:
	_collision_shape = shape_node

func _open_door() -> void:
	_opened = not _opened
	var destination := _closed_rotation
	if _opened:
		destination.y += deg_to_rad(open_angle_degrees)
	if _collision_shape:
		_collision_shape.disabled = _opened
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target, "rotation", destination, 0.42)

func _examine_furniture() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(target, "scale", _closed_scale * 1.035, 0.12)
	tween.tween_property(target, "scale", _closed_scale, 0.18)
