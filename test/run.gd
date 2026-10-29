extends SceneTree
## Headless tests: godot --headless --path . -s test/run.gd  (exit code 1 on failure)

var failed := 0


func check(cond: bool, name: String) -> void:
	if not cond:
		failed += 1
		printerr("FAIL: ", name)


func _init() -> void:
	var o := {"service": "g", "environment": "dev", "release": "1.0"}

	check(WatchtowerCore.mask_key("wtp_abcdefgh") == "wtp_****", "mask")
	check(WatchtowerCore.mask_key("") == "", "mask empty")

	var s := WatchtowerCore.scrub("Authorization: Bearer abc.def key wtp_zzz")
	check(not s.contains("abc.def") and not s.contains("wtp_zzz"), "scrub")

	var tp := WatchtowerCore.parse_traceparent("00-" + "A".repeat(32) + "-" + "b".repeat(16) + "-01")
	check(tp.get("trace_id", "") == "a".repeat(32), "traceparent ok")
	check(WatchtowerCore.parse_traceparent("nope").is_empty(), "traceparent bad")

	var r := WatchtowerCore.make_record(o, 17, "boom \"x\"\n", {"wt.tenant": "evil", "k": "v"}, tp)
	check(not r["attrs"].has("wt.tenant"), "wt.* dropped")
	var j := WatchtowerCore.build_otlp(o, [r])
	var parsed = JSON.parse_string(j)
	check(parsed != null, "valid json")
	var rec = parsed["resourceLogs"][0]["scopeLogs"][0]["logRecords"][0]
	check(rec["body"]["stringValue"] == "boom \"x\"\n", "body round trip")
	check(rec["traceId"] == "a".repeat(32), "trace id")
	check(rec["severityText"] == "ERROR", "severity")
	check(not j.contains("wt.tenant"), "no wt attr in payload")

	var q := []
	for i in 3:
		WatchtowerCore.push_bounded(q, {"i": i}, 2)
	check(q.size() == 2 and q[0]["i"] == 1, "bounded drops oldest")

	quit(1 if failed > 0 else 0)
