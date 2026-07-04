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

## Below this world-space collision radius a laser hit vaporizes the rock
## instead of splitting it further.
@export var min_split_radius: float = 0.6

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


## Each laser-split fragment keeps half the parent's volume: r * 2^(-1/3).
const SPLIT_RADIUS_FACTOR: float = 0.7937
## Fragment speed across the beam. The pair separates at twice this, which
## must beat merge_speed_threshold or touching fragments would fuse back.
const SPLIT_SEPARATION_SPEED: float = 3.0


## Laser hit: split into two half-volume fragments flying apart across the
## beam, or vanish in a dust puff when already too small to split.
func hit_by_laser(beam_direction: Vector3) -> void:
	if is_queued_for_deletion():
		return
	AsteroidCollisions.spawn_impact_effect(global_position, get_parent())
	if collision_radius >= min_split_radius:
		_split(beam_direction)
	queue_free()


func _split(beam_direction: Vector3) -> void:
	var fragment_radius := collision_radius * SPLIT_RADIUS_FACTOR
	var axis := beam_direction.cross(Vector3.UP)
	if axis.length_squared() < 0.0001:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	for side: float in [-1.0, 1.0]:
		# duplicate() re-runs _ready (random spin/scale, collision registry);
		# size, mass and motion are then overridden to the fragment's share.
		var fragment := duplicate() as Asteroid
		get_parent().add_child(fragment)
		fragment.global_position = global_position + axis * (side * (fragment_radius + 0.05))
		fragment.global_position.y = 0.0
		fragment.apply_merged_radius(fragment_radius)
		fragment.mass = mass * 0.5
		fragment.velocity = velocity + axis * (side * SPLIT_SEPARATION_SPEED)
		fragment.gravity_affected = gravity_affected
		fragment.despawn_distance = despawn_distance
		fragment.despawn_center = despawn_center
