class_name WatchtowerCore
extends RefCounted
## Engine-free helpers (no scene tree), unit-tested headless.

const SDK_VERSION := "0.1.0"

static func mask_key(key: String) -> String:
	if key.is_empty():
		return ""
	return "****" if key.length() <= 8 else key.substr(0, 4) + "****"


static func scrub(s: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)(bearer\\s+[A-Za-z0-9._~+/=-]+|wt[pi]_[A-Za-z0-9_]+)")
	return re.sub(s, "[redacted]", true)


static func parse_traceparent(tp: String) -> Dictionary:
	var p := tp.split("-")
	if p.size() < 4 or p[1].length() != 32 or p[2].length() != 16:
		return {}
	if not (p[1] + p[2]).is_valid_hex_number():
		return {}
	return {"trace_id": p[1].to_lower(), "span_id": p[2].to_lower()}


static func severity_text(n: int) -> String:
	if n >= 21:
		return "FATAL"
	if n >= 17:
		return "ERROR"
	if n >= 13:
		return "WARN"
	return "INFO" if n >= 9 else "DEBUG"


static func make_record(o: Dictionary, severity: int, body: String, attrs: Dictionary, trace: Dictionary = {}) -> Dictionary:
	var a := {}
	for k in attrs:
		# the gateway stamps tenant identity; wt.* from clients is never accepted
		if not str(k).begins_with("wt."):
			a[str(k)] = scrub(str(attrs[k]))
	var r := {
		"time_ns": int(Time.get_unix_time_from_system() * 1000000000.0),
		"severity": severity,
		"body": scrub(body),
		"attrs": a,
	}
	if not trace.is_empty():
		r["trace_id"] = trace["trace_id"]
		r["span_id"] = trace["span_id"]
	return r


static func _kv(k: String, v: String) -> Dictionary:
	return {"key": k, "value": {"stringValue": v}}


## OTLP/HTTP JSON logs body.
static func build_otlp(o: Dictionary, records: Array) -> String:
	var res := [
		_kv("service.name", o.get("service", "godot-game")),
		_kv("deployment.environment.name", o.get("environment", "production")),
		_kv("telemetry.sdk.name", "watchtower-godot"),
		_kv("telemetry.sdk.language", "gdscript"),
		_kv("telemetry.sdk.version", SDK_VERSION),
	]
	if not str(o.get("release", "")).is_empty():
		res.append(_kv("service.version", o["release"]))
	var recs := []
	for r in records:
		var attrs := []
		for k in r["attrs"]:
			attrs.append(_kv(k, r["attrs"][k]))
		var rec := {
			"timeUnixNano": str(r["time_ns"]),
			"severityNumber": r["severity"],
			"severityText": severity_text(r["severity"]),
			"body": {"stringValue": r["body"]},
			"attributes": attrs,
		}
		if r.has("trace_id"):
			rec["traceId"] = r["trace_id"]
			rec["spanId"] = r["span_id"]
		recs.append(rec)
	return JSON.stringify({"resourceLogs": [{
		"resource": {"attributes": res},
		"scopeLogs": [{"scope": {"name": "watchtower-godot", "version": SDK_VERSION}, "logRecords": recs}],
	}]})


## Bounded queue: drops the oldest when full.
static func push_bounded(q: Array, r: Dictionary, max_len: int) -> void:
	q.append(r)
	while q.size() > max_len:
		q.pop_front()
