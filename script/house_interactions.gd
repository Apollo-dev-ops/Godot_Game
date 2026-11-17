extends Node

const INTERACTIVE_SCRIPT := preload("res://script/interactive_prop.gd")
const ANIMATED_DOOR_SCRIPT := preload("res://script/doors/animated_door.gd")
const DOOR_AREA_SCRIPT := preload("res://script/doors/door_interaction_area.gd")
const DOOR_KEYWORDS := ["puerta", "door"]
const DRAWER_KEYWORDS := ["cajon", "cajones", "drawer", "gaveta"]
const FURNITURE_KEYWORDS := [
	"mesa", "sillon", "silla", "librero", "cama", "cajones", "radio", "lampara", "ventilador", "caja", "armario", "gabinete", "escritorio"
]
const MAX_FURNITURE_PROXIES := 48
const MAX_CABINET_PANEL_PROXIES := 16
const MAX_CABINET_DRAWER_PROXIES := 12

var _furniture_count := 0
var _cabinet_panel_count := 0
var _cabinet_drawer_count := 0

func _ready() -> void:
	_build_interaction_proxies(get_parent())
	call_deferred("_create_threshold_bridges")

func _create_threshold_bridges() -> void:
	await get_tree().physics_frame
	var world_root: Node = get_parent()
	if world_root == null:
		return
	var props: Array[Node] = world_root.find_children("*", "InteractiveProp", true, false)
	var player: Node = world_root.find_child("Player", true, false)
	for node in props:
		var prop: InteractiveProp = node as InteractiveProp
		if prop == null or prop.interaction_kind != "door":
			continue
		_create_threshold_bridge(prop, player)

func _create_threshold_bridge(prop: InteractiveProp, player: Node) -> void:
	if prop.target == null or not prop.target is MeshInstance3D:
		return
	var panel: MeshInstance3D = prop.target as MeshInstance3D
	if panel.mesh == null or prop.get_meta("threshold_bridge_created", false):
		return
	var bounds: AABB = panel.global_transform * panel.mesh.get_aabb()
	if bounds.size.y < 1.3 or bounds.size.y > 3.5:
		return
	var center: Vector3 = bounds.get_center()
	var normal: Vector3 = panel.global_basis.z if bounds.size.z <= bounds.size.x else panel.global_basis.x
	normal.y = 0.0
	if normal.is_zero_approx():
		normal = Vector3.FORWARD if bounds.size.z <= bounds.size.x else Vector3.RIGHT
	normal = normal.normalized()
	var excluded: Array[RID] = [prop.get_rid()]
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	var offset: float = 0.8
	var ray_start_y: float = bounds.position.y + bounds.size.y + 0.45
	var positive_floor: Dictionary = _sample_walkable_floor(center + normal * offset, ray_start_y, excluded)
	var negative_floor: Dictionary = _sample_walkable_floor(center - normal * offset, ray_start_y, excluded)
	if not positive_floor.get("found", false) or not negative_floor.get("found", false):
		return
	var positive_y: float = positive_floor["height"]
	var negative_y: float = negative_floor["height"]
	var rise: float = absf(positive_y - negative_y)
	if rise < 0.12 or rise > 1.2:
		return
	var low_point: Vector3 = center + normal * offset if positive_y < negative_y else center - normal * offset
	var high_point: Vector3 = center - normal * offset if positive_y < negative_y else center + normal * offset
	var low_y: float = minf(positive_y, negative_y)
	var high_y: float = maxf(positive_y, negative_y)
	var climb_direction: Vector3 = high_point - low_point
	climb_direction.y = 0.0
	climb_direction = climb_direction.normalized()
	var ramp_length: float = clampf(rise / tan(deg_to_rad(18.0)) + 0.25, 0.8, 1.8)
	var ramp_width: float = clampf(maxf(bounds.size.x, bounds.size.z) + 0.14, 0.9, 1.5)
	var ramp_thickness: float = 0.08
	var slope_angle: float = atan2(rise, ramp_length)
	var yaw: float = atan2(climb_direction.x, climb_direction.z)
	var ramp_basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -slope_angle)
	var ramp_center: Vector3 = Vector3(center.x, (low_y + high_y) * 0.5 - ramp_thickness * 0.5 * cos(slope_angle), center.z)
	var ramp_parent: Node3D = prop.get_parent() as Node3D
	if ramp_parent == null:
		return
	print("RAMP_TRACE_CREATE", ramp_center, ramp_length, ramp_width, ramp_parent.get_path())
	var ramp_body: StaticBody3D = StaticBody3D.new()
	ramp_body.name = "ThresholdRamp_" + panel.name
	ramp_body.collision_layer = 1
	ramp_body.collision_mask = 0
	ramp_body.add_to_group("door_threshold_bridges")
	ramp_parent.add_child(ramp_body)
	ramp_body.global_transform = Transform3D(ramp_basis, ramp_center)
	var size: Vector3 = Vector3(ramp_width, ramp_thickness, ramp_length)
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	ramp_body.add_child(shape_node)
	var visual: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = size
	visual.mesh = box_mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.23, 0.21)
	material.roughness = 0.92
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ramp_body.add_child(visual)
	prop.set_meta("threshold_bridge_created", true)

func _sample_walkable_floor(point: Vector3, start_y: float, excluded: Array[RID]) -> Dictionary:
	var viewport: Viewport = get_viewport()
	if viewport == null or viewport.world_3d == null:
		return {"found": false}
	var origin: Vector3 = Vector3(point.x, start_y, point.z)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * 12.0)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = excluded
	var hit: Dictionary = viewport.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"found": false}
	var normal: Vector3 = hit["normal"]
	if normal.dot(Vector3.UP) < 0.7:
		return {"found": false}
	var position: Vector3 = hit["position"]
	return {"found": true, "height": position.y}

func _build_interaction_proxies(root_node: Node) -> void:
	for child in root_node.get_children():
		if child == self:
			continue
		if child is MeshInstance3D:
			_try_make_proxy(child as MeshInstance3D)
		_build_interaction_proxies(child)

func _try_make_proxy(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null or mesh.get_meta("interaction_proxy_created", false):
		return
	var node_name := mesh.name.to_lower()
	var parent_name := mesh.get_parent().name.to_lower() if mesh.get_parent() else ""
	var is_door := _contains_keyword(node_name, DOOR_KEYWORDS)
	var is_furniture := _contains_keyword(node_name, FURNITURE_KEYWORDS)
	var is_cabinet_panel := _is_cabinet_panel(mesh)
	var is_cabinet_drawer := _is_cabinet_drawer(mesh)
	var is_named_drawer := not is_cabinet_panel and not is_cabinet_drawer and (_contains_keyword(node_name, DRAWER_KEYWORDS) or (parent_name != "cajones_puertas" and _contains_keyword(parent_name, DRAWER_KEYWORDS)))
	if is_cabinet_panel and _cabinet_panel_count >= MAX_CABINET_PANEL_PROXIES:
		return
	if is_cabinet_drawer and _cabinet_drawer_count >= MAX_CABINET_DRAWER_PROXIES:
		return
	if not is_door and not is_cabinet_panel and not is_cabinet_drawer and not is_named_drawer and (not is_furniture or _furniture_count >= MAX_FURNITURE_PROXIES):
		return
	# Only actual door leaves are openable; frames, handles and windows stay fixed.
	if is_door and not _is_door_panel(mesh):
		return
	if mesh.get_parent() == null:
		return
	var local_aabb := mesh.get_aabb()
	if local_aabb.size.length_squared() < 0.0001:
		return
	var proxy := StaticBody3D.new()
	proxy.set_script(INTERACTIVE_SCRIPT)
	proxy.collision_layer = 1 if is_door else 2
	proxy.collision_mask = 0
	mesh.get_parent().add_child(proxy)
	proxy.transform = mesh.transform
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = local_aabb.size
	collision.shape = box
	collision.position = local_aabb.position + local_aabb.size * 0.5
	proxy.add_child(collision)
	proxy.set_collision_shape(collision)
	var kind := "door" if is_door else ("cabinet_panel" if is_cabinet_panel else ("drawer" if is_cabinet_drawer or is_named_drawer else "furniture"))
	var label := "DOOR" if is_door else ("CABINET" if is_cabinet_panel else ("DRAWER" if is_cabinet_drawer or is_named_drawer else "FURNITURE"))
	proxy.configure(mesh, label, kind)
	if is_cabinet_panel:
		var hinge_data := _cabinet_hinge_data(mesh)
		proxy.configure_cabinet_panel(hinge_data["point"], hinge_data["open_sign"])
	if is_door:
		var animated := ANIMATED_DOOR_SCRIPT.new() as AnimatedDoor
		# The house root is still inside its own _ready() while proxies are built,
		# so attach the visual to the mesh's parent instead.
		mesh.get_parent().add_child(animated)
		if animated.setup_for_mesh(mesh):
			proxy.animated_door = animated
			mesh.visible = false
		else:
			animated.queue_free()
		# A separate area keeps an open doorway interactable so it can be closed.
		var area := Area3D.new()
		area.name = "DOOR"
		area.set_script(DOOR_AREA_SCRIPT)
		area.collision_layer = 2
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		var area_collision := CollisionShape3D.new()
		var area_box := BoxShape3D.new()
		area_box.size = local_aabb.size + Vector3(0.25, 0.0, 0.25)
		area_collision.shape = area_box
		area_collision.position = local_aabb.position + local_aabb.size * 0.5
		area.add_child(area_collision)
		proxy.add_child(area)
	mesh.set_meta("interaction_proxy_created", true)
	if is_cabinet_panel:
		_cabinet_panel_count += 1
	elif is_cabinet_drawer:
		_cabinet_drawer_count += 1
	elif not is_door:
		_furniture_count += 1

func _is_cabinet_panel(mesh: MeshInstance3D) -> bool:
	var parent := mesh.get_parent()
	if parent == null or not parent.name.to_lower().contains("cajones_puertas"):
		return false
	var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var width := maxf(bounds.size.x, bounds.size.z)
	var depth := minf(bounds.size.x, bounds.size.z)
	return bounds.size.y >= 0.55 and bounds.size.y <= 1.3 and width >= 0.28 and width <= 0.72 and depth <= 0.16

func _is_cabinet_drawer(mesh: MeshInstance3D) -> bool:
	var parent := mesh.get_parent()
	if parent == null or not parent.name.to_lower().contains("cajones_puertas"):
		return false
	var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	# This imported assembly loses the original drawer names. Its four short,
	# box-shaped elements sit at cabinet height and are distinct from the tall
	# hinged leaves and thin horizontal shelves.
	return bounds.size.y >= 0.12 and bounds.size.y <= 0.22 and bounds.position.y + bounds.size.y * 0.5 >= 1.8 and bounds.position.y + bounds.size.y * 0.5 <= 3.2 and bounds.size.x >= 0.35 and bounds.size.x <= 0.9 and bounds.size.z >= 0.3 and bounds.size.z <= 0.9

func _cabinet_hinge_data(mesh: MeshInstance3D) -> Dictionary:
	var bounds: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var use_x := bounds.size.x >= bounds.size.z
	var width := bounds.size.x if use_x else bounds.size.z
	var axis := Vector3.RIGHT if use_x else Vector3.BACK
	var center := bounds.get_center()
	var mate: MeshInstance3D = null
	var mate_delta := 0.0
	for sibling in mesh.get_parent().get_children():
		if sibling == mesh or not sibling is MeshInstance3D or sibling.mesh == null:
			continue
		var other := sibling as MeshInstance3D
		var other_bounds: AABB = other.global_transform * other.mesh.get_aabb()
		var other_width := maxf(other_bounds.size.x, other_bounds.size.z)
		var other_depth := minf(other_bounds.size.x, other_bounds.size.z)
		if absf(other_bounds.size.y - bounds.size.y) > 0.16 or absf(other_width - width) > 0.18 or absf(other_depth - minf(bounds.size.x, bounds.size.z)) > 0.09:
			continue
		var horizontal_delta := other_bounds.get_center() - center
		var axis_delta := horizontal_delta.x if use_x else horizontal_delta.z
		var side_delta := absf(horizontal_delta.z if use_x else horizontal_delta.x)
		if absf(axis_delta) < width * 0.72 or absf(axis_delta) > width * 1.55 or side_delta > 0.18 or absf(horizontal_delta.y) > 0.18:
			continue
		mate = other
		mate_delta = axis_delta
		break
	var edge_sign := -1.0
	var open_sign := 1.0
	if mate:
		# Paired cabinet leaves hinge on their outside edges and swing away from
		# the center seam in opposite directions.
		edge_sign = -1.0 if mate_delta > 0.0 else 1.0
		open_sign = 1.0 if mate_delta > 0.0 else -1.0
	var hinge := center + axis * (width * 0.5 * edge_sign)
	return {"point": hinge, "open_sign": open_sign}

func _is_door_panel(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null:
		return false
	var world_aabb: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var width := maxf(world_aabb.size.x, world_aabb.size.z)
	var thickness := minf(world_aabb.size.x, world_aabb.size.z)
	return world_aabb.size.y >= 1.35 and width >= 0.45 and thickness <= 0.22

func _contains_keyword(value: String, keywords: Array) -> bool:
	for keyword in keywords:
		if value.contains(keyword):
			return true
	return false
