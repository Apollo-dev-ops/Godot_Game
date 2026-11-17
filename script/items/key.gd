extends StaticBody3D

const KEY_ICON := preload("res://assets/Icons/key.png")
var _collected := false

func get_interaction_prompt() -> String:
	return "TAP PICK UP  •  KEY"

func interact() -> void:
	if _collected:
		return
	_collected = true
	Inventory.add_item("key", KEY_ICON)
	set_collision_layer_value(2, false)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", scale * 0.05, 0.2)
	tween.tween_callback(queue_free)
