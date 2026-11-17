extends Node3D

## Adds missing collision to the neighborhood ground, protects the entire map
## with a hidden catch floor, and surrounds the measured footprint with an island.
@export var map_center := Vector2(27.0015, -0.768402)
@export var terrain_catch_radius := 416.0
@export var terrain_catch_y := -2.85
@export var boundary_radius := 407.0
@export var cliff_bottom_radius := 430.0
@export var coast_top_y := -0.42
@export var coast_bottom_y := -9.0
@export var sea_level := -7.8
@export_range(64, 512, 1) var boundary_segments := 256

const TERRAIN_MESH_NAMES: Array[String] = ["Plane_067", "Plane_069", "Carretera", "Carretera_001", "Carretera_002"]
const LAND_RING_INNER_RADIUS := 389.0
const WALL_HEIGHT := 15.6
const WALL_CENTER_Y := 4.45

const WATER_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform vec3 water_color : source_color = vec3(0.012, 0.047, 0.065);
uniform float wave_height = 0.055;
uniform float wave_speed = 0.42;
varying vec3 world_pos;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float swell = sin(world_pos.x * 0.035 + TIME * wave_speed)
        + cos(world_pos.z * 0.031 - TIME * wave_speed * 0.73);
    VERTEX.y += swell * wave_height * 0.5;
}
void fragment() {
    float a = sin(world_pos.x * 0.028 + TIME * wave_speed);
    float b = cos(world_pos.z * 0.024 - TIME * wave_speed * 0.8);
    ALBEDO = water_color + vec3(0.008, 0.023, 0.027) * (a + b);
    METALLIC = 0.14;
    ROUGHNESS = 0.24;
    NORMAL = normalize(vec3(a * 0.035, 1.0, b * 0.035));
}
"""


func _ready() -> void:
	_solidify_existing_ground_meshes()
	_create_terrain_catch_floor()
	_create_shore_rim()
	_create_cliff_face()
	_create_water()
	_create_boundary_barrier()


func _solidify_existing_ground_meshes() -> void:
	var scene_root := get_parent()
	if scene_root == null:
		return
	var region := scene_root.find_child("NavigationRegion3D", true, false)
	if region == null:
		return
	for candidate in region.find_children("*", "MeshInstance3D", true, false):
		var ground := candidate as MeshInstance3D
		if ground == null or not TERRAIN_MESH_NAMES.has(ground.name):
			continue
		if ground.mesh == null or ground.get_meta("island_collision_created", false):
			continue
		var shape := ground.mesh.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = true
		var parent := ground.get_parent() as Node3D
		if parent == null:
			continue
		var body := StaticBody3D.new()
		body.name = "IslandGround_" + ground.name
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("solidified_map_ground")
		parent.add_child(body)
		body.global_transform = ground.global_transform
		var collision := CollisionShape3D.new()
		collision.name = "GroundMeshCollision"
		collision.shape = shape
		body.add_child(collision)
		ground.set_meta("island_collision_created", true)


func _create_terrain_catch_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Island_TerrainSafetyFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("solidified_map_ground")
	add_child(body)
	body.position = Vector3(map_center.x, 0.0, map_center.y)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CatchFloorCollision"
	var shape := CylinderShape3D.new()
	shape.radius = terrain_catch_radius
	shape.height = 0.28
	shape_node.shape = shape
	shape_node.position.y = terrain_catch_y
	body.add_child(shape_node)


func _create_shore_rim() -> void:
	var mesh := _build_horizontal_ring(LAND_RING_INNER_RADIUS, boundary_radius, coast_top_y)
	var visual := MeshInstance3D.new()
	visual.name = "Island_GrassShoreRim"
	visual.mesh = mesh
	visual.material_override = _land_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Island_ShoreWalkableRim"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("solidified_map_ground")
	add_child(body)
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)


func _create_cliff_face() -> void:
	var cliff := MeshInstance3D.new()
	cliff.name = "Island_RockyCoast"
	cliff.mesh = _build_cliff_mesh()
	cliff.material_override = _cliff_material()
	add_child(cliff)


func _create_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Island_Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400.0, 1400.0)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	water.mesh = plane
	water.position = Vector3(map_center.x, sea_level, map_center.y)
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.add_to_group("island_water_visual")
	add_child(water)


func _create_boundary_barrier() -> void:
	var body := StaticBody3D.new()
	body.name = "Island_NoWaterBoundary"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("island_water_boundary")
	add_child(body)
	body.position = Vector3(map_center.x, 0.0, map_center.y)
	var segment_angle := TAU / float(boundary_segments)
	var segment_length := 2.0 * boundary_radius * tan(segment_angle * 0.5) + 0.7
	var wall_bottom := terrain_catch_y - 0.3
	var wall_top := 12.25
	var wall_height := wall_top - wall_bottom
	var wall_center := (wall_top + wall_bottom) * 0.5
	for i in range(boundary_segments):
		var angle := segment_angle * float(i)
		var collision := CollisionShape3D.new()
		collision.name = "ShoreBarrier_%03d" % i
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, wall_height, segment_length)
		collision.shape = box
		collision.position = Vector3(cos(angle) * boundary_radius, wall_center, sin(angle) * boundary_radius)
		collision.rotation.y = angle
		body.add_child(collision)


func _build_horizontal_ring(inner_radius: float, outer_radius: float, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segment_count := 256
	for i in range(segment_count):
		var a0 := TAU * float(i) / float(segment_count)
		var a1 := TAU * float(i + 1) / float(segment_count)
		var inner_a := _ring_point(inner_radius, a0, height)
		var inner_b := _ring_point(inner_radius, a1, height)
		var outer_a := _ring_point(outer_radius, a0, height)
		var outer_b := _ring_point(outer_radius, a1, height)
		_add_vertex(surface, inner_a, Vector3.UP, Vector2(cos(a0) * inner_radius, sin(a0) * inner_radius) / 24.0, Color(0.16, 0.20, 0.15))
		_add_vertex(surface, inner_b, Vector3.UP, Vector2(cos(a1) * inner_radius, sin(a1) * inner_radius) / 24.0, Color(0.16, 0.20, 0.15))
		_add_vertex(surface, outer_a, Vector3.UP, Vector2(cos(a0) * outer_radius, sin(a0) * outer_radius) / 24.0, Color(0.16, 0.20, 0.15))
		_add_vertex(surface, inner_b, Vector3.UP, Vector2(cos(a1) * inner_radius, sin(a1) * inner_radius) / 24.0, Color(0.16, 0.20, 0.15))
		_add_vertex(surface, outer_b, Vector3.UP, Vector2(cos(a1) * outer_radius, sin(a1) * outer_radius) / 24.0, Color(0.16, 0.20, 0.15))
		_add_vertex(surface, outer_a, Vector3.UP, Vector2(cos(a0) * outer_radius, sin(a0) * outer_radius) / 24.0, Color(0.16, 0.20, 0.15))
	return surface.commit()


func _build_cliff_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segment_count := 256
	for i in range(segment_count):
		var a0 := TAU * float(i) / float(segment_count)
		var a1 := TAU * float(i + 1) / float(segment_count)
		var top_a := _ring_point(boundary_radius, a0, coast_top_y)
		var top_b := _ring_point(boundary_radius, a1, coast_top_y)
		var bottom_a := _ring_point(cliff_bottom_radius, a0, coast_bottom_y)
		var bottom_b := _ring_point(cliff_bottom_radius, a1, coast_bottom_y)
		var normal_a := Vector3(cos(a0), 0.45, sin(a0)).normalized()
		var normal_b := Vector3(cos(a1), 0.45, sin(a1)).normalized()
		var tone := 0.72 + 0.08 * sin(float(i) * 0.67) + 0.035 * cos(float(i) * 0.19)
		var color_a := Color(0.12, 0.15, 0.15) * tone
		var color_b := Color(0.12, 0.15, 0.15) * tone
		_add_vertex(surface, top_a, normal_a, Vector2(float(i) / 16.0, 0.0), color_a)
		_add_vertex(surface, top_b, normal_b, Vector2(float(i + 1) / 16.0, 0.0), color_b)
		_add_vertex(surface, bottom_a, normal_a, Vector2(float(i) / 16.0, 1.0), color_a)
		_add_vertex(surface, top_b, normal_b, Vector2(float(i + 1) / 16.0, 0.0), color_b)
		_add_vertex(surface, bottom_b, normal_b, Vector2(float(i + 1) / 16.0, 1.0), color_b)
		_add_vertex(surface, bottom_a, normal_a, Vector2(float(i) / 16.0, 1.0), color_a)
	return surface.commit()


func _ring_point(radius: float, angle: float, height: float) -> Vector3:
	return Vector3(map_center.x + cos(angle) * radius, height, map_center.y + sin(angle) * radius)


func _add_vertex(surface: SurfaceTool, point: Vector3, normal: Vector3, uv: Vector2, color: Color) -> void:
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.set_color(color)
	surface.add_vertex(point)


func _land_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.70, 0.74, 0.62)
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.98
	material.uv1_scale = Vector3(0.4, 0.4, 1.0)
	return material


func _cliff_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0)
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_scale = Vector3(0.7, 0.25, 1.0)
	return material
