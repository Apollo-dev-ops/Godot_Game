class_name AnimatedDoor
extends Node3D
## Replaces a static house door panel with the supplied animated door model.
## The FBX panel is skinned to a two-bone hinge (1 s "Open"/"Close" clips) and
## carries a 0.01 bind scale plus a 100x armature scale, so its rendered size
## has to be measured through the skin rather than from the raw mesh bounds.

const DOOR_SCENE_PATH := "res://assets/models/door/DoorAnimate.fbx"
const DOOR_TEXTURE_PATH := "res://assets/models/door/WoodDoor1.png"
const OPEN_ANIMATION := &"Armature|Open"
const CLOSE_ANIMATION := &"Armature|Close"

@export var open_duration := 0.75
@export var close_duration := 0.75
@export var hinge_on_right := false

var is_open := false
var _player: AnimationPlayer
var _door_root: Node3D
var _source_mesh: MeshInstance3D
var _ready_to_use := false

func _ready() -> void:
	set_process(false)

## Aligns the animated door with the world-space bounds of the original mesh.
## Returns true when the door model could be created.
func setup_for_mesh(mesh: MeshInstance3D) -> bool:
	_source_mesh = mesh
	var door_scene := load(DOOR_SCENE_PATH) as PackedScene
	if door_scene == null or mesh.mesh == null:
		return false
	var world_aabb: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var size := world_aabb.size
	var center := world_aabb.get_center()

	_door_root = door_scene.instantiate() as Node3D
	if _door_root == null:
		return false
	_door_root.name = "DoorModel"
	# The FBX ships with an active physical-bone simulator that lets the panel
	# collapse under gravity; the animation player drives the hinge instead.
	for simulator in _door_root.find_children("*", "PhysicalBoneSimulator3D", true, false):
		simulator.active = false
	add_child(_door_root)

	_player = _door_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _player == null:
		return false
	if _player.has_animation(OPEN_ANIMATION):
		_player.get_animation(OPEN_ANIMATION).loop_mode = Animation.LOOP_NONE
	if _player.has_animation(CLOSE_ANIMATION):
		_player.get_animation(CLOSE_ANIMATION).loop_mode = Animation.LOOP_NONE
	# Start fully closed (the Close clip ends in the closed pose), then measure
	# the panel in that pose so the scaled leaf exactly fills the doorway.
	_player.play(CLOSE_ANIMATION)
	_player.advance(_player.get_animation(CLOSE_ANIMATION).length)
	_player.pause()

	var model_aabb := _skinned_aabb(_door_root)
	var model_size := model_aabb.size
	var model_center := model_aabb.get_center()
	# Pick the door's width and thickness axes from its world bounds.
	var width_axis := 0 if size.x >= size.z else 2
	var thick_axis := 2 if width_axis == 0 else 0
	var width := maxf(size[width_axis], 0.01)
	var thickness := maxf(size[thick_axis], 0.001)
	var height := maxf(size.y, 0.01)

	var thick_dir := Vector3.ZERO
	thick_dir[thick_axis] = 1.0
	var width_dir := Vector3.ZERO
	width_dir[width_axis] = 1.0
	if hinge_on_right:
		width_dir = -width_dir
	# A right-handed basis needs thick x up = width (otherwise the panel is
	# mirrored and back-face culling hides it).
	if thick_dir.cross(Vector3.UP).dot(width_dir) < 0.0:
		thick_dir = -thick_dir
	var placement := Basis(thick_dir, Vector3.UP, width_dir)
	var scale_basis := placement * Basis.from_scale(
		Vector3(
			thickness / maxf(model_size.x, 0.001),
			height / maxf(model_size.y, 0.001),
			width / maxf(model_size.z, 0.001)
		)
	)
	var origin := center - scale_basis * model_center
	global_transform = Transform3D(scale_basis, origin)
	_apply_wood_texture(_door_root)
	_ready_to_use = true
	return true

func _skinned_aabb(root: Node3D) -> AABB:
	var inverse := root.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var xform := inverse * mesh_instance.global_transform
		if mesh_instance.skin and mesh_instance.skin.get_bind_count() > 0:
			var skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
			if skeleton:
				var bone_index := skeleton.find_bone(mesh_instance.skin.get_bind_name(0))
				if bone_index >= 0:
					xform = inverse * skeleton.global_transform * skeleton.get_bone_global_pose(bone_index) * mesh_instance.skin.get_bind_pose(0)
		var bounds := _transform_aabb(xform, mesh_instance.mesh.get_aabb())
		result = bounds if first else result.merge(bounds)
		first = false
	return result

func _transform_aabb(xform: Transform3D, aabb: AABB) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size,
	]
	var result := AABB(xform * corners[0], Vector3.ZERO)
	for corner in corners:
		result = result.expand(xform * corner)
	return result

func _apply_wood_texture(root: Node) -> void:
	var texture := load(DOOR_TEXTURE_PATH) as Texture2D
	if texture == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 0.82
	material.metallic = 0.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)

func toggle() -> void:
	if not _ready_to_use or _player == null:
		return
	is_open = not is_open
	if is_open:
		_player.play(OPEN_ANIMATION, 0.05)
		_player.speed_scale = _speed_for(OPEN_ANIMATION, open_duration)
	else:
		_player.play(CLOSE_ANIMATION, 0.05)
		_player.speed_scale = _speed_for(CLOSE_ANIMATION, close_duration)

func _speed_for(animation: StringName, duration: float) -> float:
	if not _player.has_animation(animation) or duration <= 0.01:
		return 1.0
	return maxf(_player.get_animation(animation).length / duration, 0.05)
