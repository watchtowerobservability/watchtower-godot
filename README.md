# Watchtower for Godot

Errors and logs from your Godot 4 game, sent to Watchtower over OTLP/HTTP, with an offline buffer. Pure GDScript, no native build, works on every export target.

Status: 0.x, early. APIs may change between minor versions.

## Install

Copy `addons/watchtower` into your project (or download the release zip), then enable it in Project Settings, Plugins. This registers the `Watchtower` autoload.

## Quick start

```gdscript
Watchtower.init({"key": "<publishable-key>", "endpoint": "https://<your-edge>", "service": "my-game"})
Watchtower.capture_error("save failed", get_stack_string())
Watchtower.capture_message("level loaded")
```

Or set `watchtower/key` (and `endpoint`, `service`, `environment`, `release`) in project settings, or the env vars below; it then starts by itself.
Use a publishable key in the game, never a secret ingest key (init refuses `wti_` keys).

## Integrations

| Feature | Notes |
| --- | --- |
| `capture_error`, `capture_message` | explicit, with attributes |
| `push_error`, `push_warning`, engine errors | automatic on Godot 4.5+ (`Logger`) |
| Trace link | `set_trace_context(traceparent)` |
| Offline buffer | bounded in memory, written to `user://` on exit, sent next launch |
| Native crashes | not captured (GDScript addon); use the platform crash reporter |

## Configuration

| Option | Env var | Default |
| --- | --- | --- |
| `key` | `WT_PUBLISHABLE_KEY` | none |
| `endpoint` | `WT_OTLP_ENDPOINT` | `http://localhost:4318` |
| `service` | `WT_SERVICE` | `godot-game` |
| `environment` | `WT_ENVIRONMENT` | `production` |
| `release` | `WT_RELEASE` | `application/config/version` |
| `before_send` | | Callable, return null to drop |

The key is sent as `Authorization: Bearer <key>` and masked in `describe()`.

## Provenance

Every release artifact carries a GitHub build attestation. Verify one with
`gh attestation verify <file> --repo watchtowerobservability/watchtower-godot`.

## License

Apache-2.0. Source of truth is the Watchtower monorepo; this repository is a published mirror.
