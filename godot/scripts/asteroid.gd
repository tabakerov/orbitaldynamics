class_name Asteroid
extends FloatingObject

## Small hazard rock: tumbles visually, falls with gravity when enabled,
## and destroys the ship on contact.

## If true, contact destroys the ship.
@export var lethal: bool = true

## Max visual tumble speed, radians per second.
@export var tumble_speed_max: float = 1.2

## Random uniform scale spread (0.35 = ±35%).
@export var scale_variation: float = 0.35

var _spin_axis := Vector3.UP
var _spin_speed := 0.0


func _ready() -> void:
	super()
	_spin_axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
	if _spin_axis.length_squared() < 0.001:
		_spin_axis = Vector3.UP
	_spin_axis = _spin_axis.normalized()
	_spin_speed = randf_range(tumble_speed_max * 0.25, tumble_speed_max)
	if scale_variation > 0.0:
		scale = Vector3.ONE * (1.0 + randf_range(-scale_variation, scale_variation))


func _process(delta: float) -> void:
	var mesh_instance := $MeshInstance3D as MeshInstance3D
	if mesh_instance:
		mesh_instance.rotate(_spin_axis, _spin_speed * delta)


func _on_ship_contact(ship: Ship) -> void:
	if lethal:
		ship.crash_at(ship.global_position)
