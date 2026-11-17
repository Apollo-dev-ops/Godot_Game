extends StaticBody3D
class_name WorldPickup

@export var item_id := "metal_scrap"
@export var display_name := "Metal Scrap"
@export var icon_path := "res://assets/ui/icons/scrap.svg"
@export var pickup_color := Color(0.48, 0.58, 0.62)

var _collected := false
var _bob_time := 0.0
var _visual: Node3D
var _base_height := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_build_visual()
	_base_height = position.y

func configure_pickup(id: String, label: String = "", icon: String = "", color: Color = Color(0.48, 0.58, 0.62)) -> void:
	item_id = id
	if not label.is_empty():
		display_name = label
	if not icon.is_empty():
		icon_path = icon
	pickup_color = color

func get_interaction_prompt() -> String:
	return "TAP PICK UP  •  %s" % display_name.to_upper()

func interact() -> void:
	if _collected:
		return
	_collected = true
	var icon := load(icon_path) as Texture2D if ResourceLoader.exists(icon_path) else null
	Inventory.add_item(item_id, icon, 1, display_name)
	set_collision_layer_value(2, false)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.2)
	tween.parallel().tween_property(self, "position:y", position.y + 0.22, 0.2)
	tween.tween_callback(queue_free)

func _process(delta: float) -> void:
	if _visual == null or _collected:
		return
	_bob_time += delta
	_visual.position.y = sin(_bob_time * 2.4) * 0.06
	_visual.rotation.y += delta * 0.65

func _build_visual() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var sphere := SphereShape3D.new()
		sphere.radius = 0.22
		collision.shape = sphere
		add_child(collision)
	_visual = Node3D.new()
	_visual.name = "PickupVisual"
	add_child(_visual)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "PickupMesh"
	var material := StandardMaterial3D.new()
	material.albedo_color = pickup_color
	material.metallic = 0.62 if item_id == "metal_scrap" else 0.08
	material.roughness = 0.38
	material.emission_enabled = true
	material.emission = pickup_color * 0.16
	if item_id == "first_aid_kit":
		var kit := BoxMesh.new()
		kit.size = Vector3(0.3, 0.2, 0.24)
		mesh_instance.mesh = kit
	elif item_id == "bandage":
		var box := BoxMesh.new()
		box.size = Vector3(0.24, 0.12, 0.18)
		mesh_instance.mesh = box
		mesh_instance.rotation_degrees = Vector3(15, 25, 10)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.24, 0.16, 0.2)
		mesh_instance.mesh = box
		mesh_instance.rotation_degrees = Vector3(20, 35, 12)
	mesh_instance.material_override = material
	_visual.add_child(mesh_instance)
	if item_id == "first_aid_kit":
		var cross_material := StandardMaterial3D.new()
		cross_material.albedo_color = Color(0.82, 0.12, 0.1)
		var vertical_cross := MeshInstance3D.new()
		var vertical_mesh := BoxMesh.new()
		vertical_mesh.size = Vector3(0.055, 0.13, 0.018)
		vertical_cross.mesh = vertical_mesh
		vertical_cross.material_override = cross_material
		vertical_cross.position = Vector3(0.0, 0.0, -0.13)
		_visual.add_child(vertical_cross)
		var horizontal_cross := MeshInstance3D.new()
		var horizontal_mesh := BoxMesh.new()
		horizontal_mesh.size = Vector3(0.14, 0.05, 0.018)
		horizontal_cross.mesh = horizontal_mesh
		horizontal_cross.material_override = cross_material
		horizontal_cross.position = Vector3(0.0, 0.0, -0.132)
		_visual.add_child(horizontal_cross)
	var glow := OmniLight3D.new()
	glow.name = "PickupGlow"
	glow.light_color = pickup_color
	glow.light_energy = 0.24
	glow.omni_range = 1.7
	glow.shadow_enabled = false
	_visual.add_child(glow)
