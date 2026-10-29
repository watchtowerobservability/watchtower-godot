extends Logger
## Captures engine errors and push_error/push_warning (Godot 4.5+). Callbacks may run on any thread.

var _wt: Node


func _init(wt: Node) -> void:
	_wt = wt


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
	var stack := ""
	for b in script_backtraces:
		stack += str(b) + "\n"
	var sev := 13 if error_type == ERROR_TYPE_WARNING else 17
	var msg := rationale if not rationale.is_empty() else code
	_wt.call_deferred("capture_message", msg, sev, {
		"code.function": function, "code.filepath": file, "code.lineno": str(line),
		"exception.stacktrace": stack,
	})
