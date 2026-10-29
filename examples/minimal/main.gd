extends Node


func _ready() -> void:
	Watchtower.init({"key": "<publishable-key>", "endpoint": "https://<your-edge>", "service": "my-game"})
	Watchtower.capture_message("hello from godot")
	Watchtower.capture_error("test error", "main.gd:6")
	push_error("engine-level error, captured on Godot 4.5+")
