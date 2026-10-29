extends Node
## Autoload "Watchtower". Reads project settings `watchtower/*` or WT_* env vars, or call init().

var options := {}
var _queue: Array = []
var _lock := Mutex.new()
var _trace := {}
var _http: HTTPRequest
var _busy := false
var _batch: Array = []
const PENDING := "user://watchtower-pending.json"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var key := _setting("key", "WT_PUBLISHABLE_KEY", "")
	if not key.is_empty():
		init({"key": key})


func _setting(name: String, env: String, dflt: String) -> String:
	var e := OS.get_environment(env)
	if not e.is_empty():
		return e
	return str(ProjectSettings.get_setting("watchtower/" + name, dflt))


func init(o: Dictionary) -> void:
	if _http != null:
		return
	var key: String = o.get("key", "")
	if key.is_empty():
		push_warning("[watchtower] no key set; capture disabled")
		return
	if key.begins_with("wti_"):
		push_error("[watchtower] refusing a secret ingest key in a game build; use a publishable key")
		return
	options = {
		"key": key,
		"endpoint": o.get("endpoint", _setting("endpoint", "WT_OTLP_ENDPOINT", "http://localhost:4318")),
		"service": o.get("service", _setting("service", "WT_SERVICE", "godot-game")),
		"environment": o.get("environment", _setting("environment", "WT_ENVIRONMENT", "production")),
		"release": o.get("release", _setting("release", "WT_RELEASE", str(ProjectSettings.get_setting("application/config/version", "")))),
		"max_buffered": o.get("max_buffered", 500),
		"before_send": o.get("before_send", Callable()),
	}
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var t := Timer.new()
	t.wait_time = 5.0
	t.timeout.connect(flush)
	add_child(t)
	t.start()
	# Logger is Godot 4.5+; older engines still get capture_* calls.
	if ClassDB.class_exists("Logger"):
		OS.add_logger(load("res://addons/watchtower/logger.gd").new(self))
	_send_pending()


## Same text as options, key masked.
func describe() -> String:
	return "Watchtower(key=%s, endpoint=%s, service=%s)" % [WatchtowerCore.mask_key(options.get("key", "")), options.get("endpoint", ""), options.get("service", "")]


func set_trace_context(traceparent: String) -> void:
	_trace = WatchtowerCore.parse_traceparent(traceparent)


func capture_message(msg: String, severity := 9, attrs := {}) -> void:
	_add(severity, msg, attrs)


## Explicit error capture, e.g. from your own result handling.
func capture_error(msg: String, stack := "", attrs := {}) -> void:
	var a := attrs.duplicate()
	a["exception.message"] = msg
	a["exception.stacktrace"] = stack
	_add(17, msg, a)


func _add(severity: int, body: String, attrs: Dictionary) -> void:
	if options.is_empty():
		return
	var r := WatchtowerCore.make_record(options, severity, body, attrs, _trace)
	var cb: Callable = options["before_send"]
	if cb.is_valid():
		r = cb.call(r)
		if r == null:
			return
	_lock.lock()
	WatchtowerCore.push_bounded(_queue, r, options["max_buffered"])
	_lock.unlock()


func flush() -> void:
	if _busy or options.is_empty():
		return
	_lock.lock()
	_batch = _queue.slice(0, 100)
	_queue = _queue.slice(_batch.size())
	_lock.unlock()
	if _batch.is_empty():
		return
	_post(WatchtowerCore.build_otlp(options, _batch))


func _post(body: String) -> void:
	_busy = true
	var h := ["Content-Type: application/json", "Authorization: Bearer " + options["key"]]
	if _http.request(str(options["endpoint"]).rstrip("/") + "/v1/logs", h, HTTPClient.METHOD_POST, body) != OK:
		_on_done(HTTPRequest.RESULT_CANT_CONNECT, 0, [], PackedByteArray())


func _on_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_busy = false
	if (result != HTTPRequest.RESULT_SUCCESS or code >= 500 or code == 429) and not _batch.is_empty():
		_lock.lock()
		_queue = _batch + _queue
		while _queue.size() > options["max_buffered"]:
			_queue.pop_front()
		_lock.unlock()
	_batch = []


# Offline buffer: unsent records are written on exit and sent on the next launch.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if options.is_empty() or _queue.is_empty():
			return
		var f := FileAccess.open(PENDING, FileAccess.WRITE)
		if f:
			f.store_string(WatchtowerCore.build_otlp(options, _queue))
			_queue = []


func _send_pending() -> void:
	if not FileAccess.file_exists(PENDING):
		return
	var body := FileAccess.get_file_as_string(PENDING)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING))
	if not body.is_empty():
		_post(body)
