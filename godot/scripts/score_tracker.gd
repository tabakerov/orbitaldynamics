class_name ScoreTracker
extends Node

## Accumulates score from collected FloatingObjects and survival time.
## Place as a direct child of a Level; it wires itself to the level's
## spawners and pre-placed pickups.

signal score_changed(score: int)

## Points per second while the ship is alive.
@export var points_per_second: float = 0.0

var _score: float = 0.0
var _counting_time: bool = true


func _ready() -> void:
	var level := get_parent() as Level
	if level:
		_connect_level.call_deferred(level)


func _physics_process(delta: float) -> void:
	if _counting_time and points_per_second > 0.0:
		add_points(points_per_second * delta)


func get_score() -> int:
	return int(_score)


func add_points(points: float) -> void:
	var before := get_score()
	_score += points
	if get_score() != before:
		score_changed.emit(get_score())


func _connect_level(level: Level) -> void:
	for spawner in level.get_spawners():
		spawner.object_spawned.connect(_on_object_spawned)
	for object in level.get_floating_objects():
		_register(object)
	var ship := level.get_ship()
	if ship:
		ship.crashed.connect(_on_ship_crashed)


func _on_object_spawned(object: Node3D) -> void:
	if object is FloatingObject:
		_register(object)


func _register(object: FloatingObject) -> void:
	if not object.collected.is_connected(_on_collected):
		object.collected.connect(_on_collected)


func _on_collected(object: FloatingObject) -> void:
	add_points(object.score_value)


func _on_ship_crashed(_crash_position: Vector3) -> void:
	_counting_time = false
