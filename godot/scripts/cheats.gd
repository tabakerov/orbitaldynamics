extends Node

## Global cheat toggle: while enabled, Ship.crash_at() is a no-op (invulnerable)
## and fuel is pegged to max every tick (infinite fuel). Persists across level
## restarts/menu returns like a debug flag, not per-level simulation state.

signal changed(cheats_enabled: bool)

var enabled: bool = false:
	set(value):
		if enabled == value:
			return
		enabled = value
		changed.emit(enabled)


func toggle() -> void:
	enabled = not enabled
