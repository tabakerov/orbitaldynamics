class_name CelestialBodyData
extends Resource

## Mass used for inter-body gravitational attraction.
@export var mass: float = 1000.0

## Multiplier on gravitational pull exerted on the ship.
@export var gravity_strength: float = 1.0

## Exponent for distance falloff (2.0 = inverse square law).
@export var falloff_exponent: float = 2.0

## Ship receives no gravity beyond this distance.
@export var max_range: float = 80.0

## Clamps distance to prevent singularity near the surface.
@export var min_range: float = 2.0

## Visual and collision radius of the body.
@export var radius: float = 3.0
