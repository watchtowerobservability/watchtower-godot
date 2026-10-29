@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("Watchtower", "res://addons/watchtower/watchtower.gd")
	for s in ["key", "endpoint", "service", "environment", "release"]:
		if not ProjectSettings.has_setting("watchtower/" + s):
			ProjectSettings.set_setting("watchtower/" + s, "")


func _exit_tree() -> void:
	remove_autoload_singleton("Watchtower")
