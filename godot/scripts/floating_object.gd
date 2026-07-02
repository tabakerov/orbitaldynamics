class_name FloatingObject
extends Area3D

## Base class for free-floating items (fuel, bonuses, small asteroids).
## They drift with a velocity, optionally fall along the celestial gravity
## field, get absorbed by black holes and burn up on planets. Subclasses
## define what happens on contact with the ship.

signal collected(object: FloatingObject)

## Mass fed to BlackHole.absorb() when this object falls into a black hole.
@export var mass: float = 1.0

## If true, velocity follows the celestial gravity field each physics tick.
@export var gravity_affected: bool = false

## Points granted when the ship collects this object (see ScoreTracker).
@export var score_value: int = 0

## Velocity at spawn; spawners set this before adding the object to the tree.
@export var initial_velocity: Vector3 = Vector3.ZERO

## Freed when farther than this from despawn_center (0 = never).
@export var despawn_distance: float = 0.0

var velocity: Vector3 = Vector3.ZERO
var despawn_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	velocity = initial_velocity
	velocity.y = 0.0
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if gravity_affected and CelestialSim.active:
		velocity += CelestialSim.get_gravity_at(global_position) * delta
		velocity.y = 0.0
	global_position += velocity * delta
	global_position.y = 0.0
	if despawn_distance > 0.0 and global_position.distance_to(despawn_center) > despawn_distance:
		queue_free()


func _on_body_entered(body: Node) -> void:
	# Area callbacks arrive while the physics server is flushing queries;
	# reactions mutate physics state (freeing, resizing shapes, freezing
	# the ship), so they must run deferred.
	_handle_contact.call_deferred(body)


func _handle_contact(body: Node) -> void:
	if is_queued_for_deletion() or not is_inside_tree() or not is_instance_valid(body):
		return
	if body is BlackHole:
		body.absorb(mass)
		queue_free()
	elif body is CelestialBody:
		_on_celestial_contact(body)
	elif body is Ship:
		_on_ship_contact(body)


## Contact with a planet or other celestial body: burn up by default.
func _on_celestial_contact(_body: CelestialBody) -> void:
	queue_free()


## Contact with the ship: no-op by default, subclasses override.
func _on_ship_contact(_ship: Ship) -> void:
	pass
