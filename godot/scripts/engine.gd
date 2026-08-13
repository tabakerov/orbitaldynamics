class_name EngineModule
extends ShipModule

## Closer than this to the commanded thrust and the engine is simply there.
const SPOOL_SETTLE_EPSILON: float = 0.001

## Set by the ship when the engine's bumper is held: thrust leaves the nozzle
## the other way, so the ship is pushed in the opposite direction.
var reversed: bool = false

## Thrust level the trigger asks for, 0…1. The engine does not jump to it —
## `intensity`, the thrust actually leaving the nozzle, chases this value at
## the profile's spool rates, so a stab at the trigger takes a moment to
## become acceleration and releasing it leaves a fading tail of thrust.
var throttle: float = 0.0

@onready var _exhaust: MeshInstance3D = $Exhaust
@onready var _active_light: OmniLight3D = $ActiveLight
@onready var _particles: GPUParticles3D = $ExhaustParticles

## Nozzle-side visuals with their forward-facing rest transforms, swapped to
## the other side of the mount while the engine runs in reverse.
var _nozzle_visuals: Array = []
var _visuals_reversed: bool = false


func _ready() -> void:
	if _active_light:
		_active_light.visible = false
	for node: Node3D in [_exhaust, _active_light, _particles]:
		if node:
			_nozzle_visuals.append([node, node.transform])


func _process(_delta: float) -> void:
	if not _exhaust:
		return
	_sync_nozzle_direction()
	var has_fuel := _has_effective_fuel_supply()
	var thrusting: bool = active and intensity > 0.0 and has_fuel
	_exhaust.visible = thrusting
	_active_light.visible = active
	_particles.emitting = thrusting


func get_mass() -> float:
	var ep := profile as EngineProfile
	return ep.dry_mass if ep else 0.0


func physics_tick(delta: float) -> void:
	var ep := profile as EngineProfile
	var spool_time := 0.0
	if ep:
		spool_time = ep.spool_up_time if throttle > intensity else ep.spool_down_time
	if spool_time <= 0.0 or delta <= 0.0:
		intensity = throttle
		return
	# Exponential approach: the engine covers the same fraction of whatever
	# gap is left every tick, so it drags its feet just as much on a 5% nudge
	# as on a stab to full power.
	intensity = lerpf(intensity, throttle, 1.0 - exp(-delta / spool_time))
	# The tail is asymptotic; without this the engine would idle forever a
	# hair away from the commanded thrust and never read as settled.
	if absf(throttle - intensity) < SPOOL_SETTLE_EPSILON:
		intensity = throttle


func stop() -> void:
	super()
	throttle = 0.0


## Fraction of rated thrust actually leaving the nozzle this frame — what the
## HUD needle points at. Fuel starvation counts: a dry tank reads zero even
## while the engine is spun up.
func get_thrust_ratio() -> float:
	if not active or intensity <= 0.0 or not _has_effective_fuel_supply():
		return 0.0
	return intensity * fuel_supply_ratio


func _sync_nozzle_direction() -> void:
	if reversed == _visuals_reversed:
		return
	_visuals_reversed = reversed
	var flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	for entry: Array in _nozzle_visuals:
		var node: Node3D = entry[0]
		var rest: Transform3D = entry[1]
		node.transform = flip * rest if reversed else rest


func get_thrust_vector() -> Vector3:
	if not active or intensity <= 0.0:
		return Vector3.ZERO
	if not _has_effective_fuel_supply():
		return Vector3.ZERO
	var ep := profile as EngineProfile
	if not ep:
		return Vector3.ZERO
	# Exhaust leaves along local +Z, so thrust pushes along -Z — and the other
	# way round in reverse.
	var nozzle := global_transform.basis.z
	var direction := nozzle if reversed else -nozzle
	return direction * ep.max_thrust * intensity * fuel_supply_ratio


func get_requested_fuel_drain(delta: float) -> float:
	if not active or intensity <= 0.0:
		return 0.0
	if not ship:
		return 0.0
	var ep := profile as EngineProfile
	if not ep:
		return 0.0
	return ep.fuel_consumption_rate * intensity * delta


func get_fuel_drain(delta: float) -> float:
	if not _has_effective_fuel_supply():
		return 0.0
	return get_requested_fuel_drain(delta) * fuel_supply_ratio


func _has_effective_fuel_supply() -> bool:
	if not ship or fuel_supply_ratio <= 0.0:
		return false
	return ship.fuel > 0.0
