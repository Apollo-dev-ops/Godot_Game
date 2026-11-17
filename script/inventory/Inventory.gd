extends Node

signal changed

const CONSUMABLES := {
	"bandage": {"heal": 25.0, "display_name": "Bandage"},
	"first_aid_kit": {"heal": 60.0, "display_name": "First Aid Kit"},
}

var items: Array[Dictionary] = []

func add_item(item_name: String, icon: Texture2D = null, quantity: int = 1, display_name: String = "") -> bool:
	if item_name.strip_edges().is_empty() or quantity <= 0:
		return false
	var resolved_name := display_name if not display_name.strip_edges().is_empty() else _default_display_name(item_name)
	for item in items:
		if item["name"] == item_name:
			item["quantity"] = int(item.get("quantity", 1)) + quantity
			if icon != null:
				item["icon"] = icon
			if not item.has("display_name"):
				item["display_name"] = resolved_name
			changed.emit()
			return true
	items.append({
		"name": item_name,
		"display_name": resolved_name,
		"icon": icon,
		"quantity": quantity,
	})
	changed.emit()
	return true

func remove_item(item_name: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	for index in range(items.size()):
		if items[index]["name"] == item_name:
			var remaining := int(items[index].get("quantity", 1)) - quantity
			if remaining > 0:
				items[index]["quantity"] = remaining
			else:
				items.remove_at(index)
			changed.emit()
			return true
	return false

func has_item(item_name: String) -> bool:
	for item in items:
		if item["name"] == item_name and int(item.get("quantity", 1)) > 0:
			return true
	return false

func get_item_quantity(item_name: String) -> int:
	for item in items:
		if item["name"] == item_name:
			return int(item.get("quantity", 1))
	return 0

func is_consumable(item_name: String) -> bool:
	return CONSUMABLES.has(item_name)

func use_item(item_name: String) -> bool:
	if not is_consumable(item_name) or not has_item(item_name):
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("heal"):
		return false
	var effect: Dictionary = CONSUMABLES[item_name]
	var healed: float = player.heal(float(effect["heal"]))
	# Do not consume a healing item when it cannot restore any health, e.g. at
	# full health or after the player has died.
	if healed <= 0.0:
		return false
	return remove_item(item_name)

func _default_display_name(item_name: String) -> String:
	match item_name:
		"metal_scrap":
			return "Metal Scrap"
		"first_aid_kit":
			return "First Aid Kit"
		_:
			return item_name.replace("_", " ").capitalize()
