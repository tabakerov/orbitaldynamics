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

## If two asteroids collide with a closing speed at or below this, they
## merge into one (combined mass and size) instead of bouncing apart —
## see AsteroidCollisions.
@export var merge_speed_threshold: float = 1.5

var _spin_axis := Vector3.UP
var _spin_speed := 0.0

## World-space collision radius, cached after scale_variation is applied
## (see AsteroidCollisions, which resolves asteroid-vs-asteroid impacts).
var collision_radius: float = 0.0

## Unscaled radius of the collision/mesh shape, cached once — the reference
## point apply_merged_radius() scales from.
var _base_radius: float = 1.0


func _ready() -> void:
	super()
	_spin_axis = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
	if _spin_axis.length_squared() < 0.001:
		_spin_axis = Vector3.UP
	_spin_axis = _spin_axis.normalized()
	_spin_speed = randf_range(tumble_speed_max * 0.25, tumble_speed_max)
	if scale_variation > 0.0:
		scale = Vector3.ONE * (1.0 + randf_range(-scale_variation, scale_variation))

	var collision := $CollisionShape3D as CollisionShape3D
	var sphere := collision.shape as SphereShape3D if collision else null
	_base_radius = sphere.radius if sphere else 1.0
	collision_radius = _base_radius * scale.x
	AsteroidCollisions.register(self)


func _exit_tree() -> void:
	super()
	AsteroidCollisions.unregister(self)


func _process(delta: float) -> void:
	var mesh_instance := $MeshInstance3D as MeshInstance3D
	if mesh_instance:
		mesh_instance.rotate(_spin_axis, _spin_speed * delta)


func _on_ship_contact(ship: Ship) -> void:
	if lethal:
		ship.crash_at(ship.global_position)


## Resizes this asteroid to a new world-space collision radius (see
## AsteroidCollisions._merge — the new radius comes from combining the
## volumes of the two merged rocks) and updates the mesh/collision to match.
func apply_merged_radius(new_radius: float) -> void:
	if _base_radius <= 0.0:
		return
	scale = Vector3.ONE * (new_radius / _base_radius)
	collision_radius = new_radius
