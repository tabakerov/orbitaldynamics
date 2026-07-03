extends Node

## Lightweight gravity registry for FloatingObjects that attract others (see
## FloatingObject.attracts_others). Kept separate from CelestialSim, whose
## packed arrays represent a fixed set of bodies sized once at level load —
## floating objects spawn and despawn continuously, so a plain array with
## direct O(n) iteration fits better (n stays small: entries cap max_alive).

var _sources: Array[FloatingObject] = []


func register(source: FloatingObject) -> void:
	if not _sources.has(source):
		_sources.append(source)


func unregister(source: FloatingObject) -> void:
	_sources.erase(source)


func has_sources() -> bool:
	return not _sources.is_empty()


## Sums gravity from every registered source at pos. Pass exclude (e.g. a
## FloatingObject querying its own pull) to skip one source.
##
## This runs once per attracting object per physics tick, i.e. O(n^2) across
## the whole population — cheap at dozens of objects, but attraction_range is
## normally small next to a level's scale, so most pairs are out of range.
## The length_squared() check below skips those before paying for a sqrt or
## a pow() call, which matters once the object count climbs into the
## several-dozen range (see the level's per-entry max_alive caps).
func get_gravity_at(pos: Vector3, exclude: FloatingObject = null) -> Vector3:
	var total := Vector3.ZERO
	for source in _sources:
		if source == exclude or not is_instance_valid(source):
			continue
		var offset := source.global_position - pos
		var range_sq := source.attraction_range * source.attraction_range
		var raw_dist_sq := offset.length_squared()
		if raw_dist_sq > range_sq or raw_dist_sq < 0.00000001:
			continue
		var raw_dist := sqrt(raw_dist_sq)
		var dist := maxf(raw_dist, source.attraction_min_range)
		var strength: float
		if is_equal_approx(source.attraction_falloff_exponent, 2.0):
			strength = source.attraction_strength * source.mass / (dist * dist)
		else:
			strength = source.attraction_strength * source.mass / pow(dist, source.attraction_falloff_exponent)
		total += (offset / raw_dist) * strength
	return total


func clear() -> void:
	_sources.clear()
