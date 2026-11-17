extends Area3D
## Keeps a doorway interactable while the door's physical blocker is disabled.

func interact() -> void:
	var parent := get_parent()
	if parent and parent.has_method("interact"):
		parent.interact()
