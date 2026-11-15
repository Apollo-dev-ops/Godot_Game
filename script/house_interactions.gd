extends Node

const INTERACTIVE_SCRIPT := preload("res://script/interactive_prop.gd")
const DOOR_KEYWORDS := ["puerta", "door"]
const FURNITURE_KEYWORDS := [
	"mesa", "sillon", "silla", "librero", "cama", "cajones", "radio", "lampara", "ventilador", "caja"
]
const MAX_FURNITURE_PROXIES := 48

var _furniture_count := 0

func _ready() -> void:
	_build_interaction_proxies(get_parent())

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
	var is_door := _contains_keyword(node_name, DOOR_KEYWORDS)
	var is_furniture := _contains_keyword(node_name, FURNITURE_KEYWORDS)
	if not is_door and (not is_furniture or _furniture_count >= MAX_FURNITURE_PROXIES):
		return
	if mesh.get_parent() == null:
		return
	var aabb := mesh.get_aabb()
	if aabb.size.length_squared() < 0.0001:
		return
	var proxy := StaticBody3D.new()
	proxy.set_script(INTERACTIVE_SCRIPT)
	proxy.collision_layer = 1 if is_door else 2
	proxy.collision_mask = 0
	mesh.get_parent().add_child(proxy)
	proxy.transform = mesh.transform
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	collision.shape = box
	collision.position = aabb.position + aabb.size * 0.5
	proxy.add_child(collision)
	proxy.set_collision_shape(collision)
	proxy.configure(mesh, _friendly_name(mesh.name, is_door), "door" if is_door else "furniture")
	mesh.set_meta("interaction_proxy_created", true)
	if not is_door:
		_furniture_count += 1

func _contains_keyword(value: String, keywords: Array) -> bool:
	for keyword in keywords:
		if value.contains(keyword):
			return true
	return false

func _friendly_name(raw_name: String, is_door: bool) -> String:
	if is_door:
		return "DOOR"
	return "FURNITURE"
