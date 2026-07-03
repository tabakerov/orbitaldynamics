class_name SpawnEntry
extends Resource

## One spawnable object type for ObjectSpawner: what to spawn, how often,
## and with what initial velocity.

enum VelocityFrame {
	## Velocity components are world axes.
	GLOBAL,
	## X = outward from the spawner center, Z = tangential
	## (counter-clockwise when viewed from above).
	RADIAL,
}

enum GravityOverride { KEEP, OFF, ON }

enum RadialSpeedMode {
	## Radial speed is initial_velocity.x (± velocity_jitter.x), as normal.
	FIXED,
	## Only valid with velocity_frame == RADIAL. Ignores initial_velocity.x;
	## the spawner instead computes the exact outward speed so the object
	## decelerates under gravity_source's current gravity and turns around
	## at a random distance in [turnaround_distance_min, turnaround_distance_max],
	## then falls back. Recomputed per spawn, so it tracks a growing body.
	TURNAROUND_AT_RANGE,
}

## Scene to spawn. A FloatingObject root gets velocity/gravity/despawn
## applied; any other Node3D is just placed.
@export var scene: PackedScene

## Mean seconds between spawns.
@export_range(0.05, 120.0, 0.05, "or_greater") var interval: float = 5.0

## Random ± seconds added to each interval (0 = perfectly even).
@export_range(0.0, 60.0, 0.05, "or_greater") var interval_jitter: float = 0.0

## Base initial velocity of spawned objects (Y is ignored).
@export var initial_velocity: Vector3 = Vector3.ZERO

## Random ± spread per component added to the initial velocity.
@export var velocity_jitter: Vector3 = Vector3.ZERO

## Interpretation of the velocity vectors.
@export var velocity_frame: VelocityFrame = VelocityFrame.GLOBAL

## Max objects from this entry alive at once (0 = unlimited).
@export_range(0, 200, 1, "or_greater") var max_alive: int = 0

## Override gravity_affected on spawned FloatingObjects.
@export var gravity_override: GravityOverride = GravityOverride.KEEP

@export_group("Turnaround Launch")
@export var radial_speed_mode: RadialSpeedMode = RadialSpeedMode.FIXED
## Minimum distance from gravity_source at which the object turns around.
@export var turnaround_distance_min: float = 70.0
## Maximum distance from gravity_source at which the object turns around.
@export var turnaround_distance_max: float = 140.0


func pick_interval(rng: RandomNumberGenerator) -> float:
	var jitter := 0.0
	if interval_jitter > 0.0:
		jitter = rng.randf_range(-interval_jitter, interval_jitter)
	return maxf(interval + jitter, 0.05)
