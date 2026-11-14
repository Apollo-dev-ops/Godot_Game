extends Node

const LEVELS := ["WIMPY KID", "NORMAL", "MY GOOD LORD"]
var current_level := 1

func cycle() -> void:
	current_level = (current_level + 1) % LEVELS.size()

func display_name() -> String:
	return LEVELS[current_level]

func speed_multiplier() -> float:
	return [0.55, 1.0, 1.35][current_level]

func damage_multiplier() -> float:
	return [0.35, 1.0, 1.8][current_level]

func attack_interval() -> float:
	# Keep the hardest swing interval at the killer's 0.8s animation recovery time.
	# This prevents attack animations from restarting before the previous cut finishes.
	return [1.5, 1.0, 0.8][current_level]
