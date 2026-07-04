class_name WeaponProfile
extends ModuleProfile

## Gun module profile. The gun fires whatever ammo type was picked up last:
## an instant laser beam that splits asteroids, or self-propelled rockets
## that destroy them outright (see WeaponModule).

enum AmmoType { LASER, ROCKET }

@export var dry_mass: float = 0.0

@export_group("Laser")
## Max beam reach; the beam stops at the first asteroid or celestial body.
@export var laser_range: float = 400.0
## Recoil impulse applied to the ship per shot, along the mount's thrust
## direction — firing the laser doubles as an engine burst.
@export var laser_impulse: float = 35.0
@export var laser_cooldown: float = 0.35

@export_group("Rocket")
@export var rocket_scene: PackedScene
@export var rocket_cooldown: float = 0.6
## Muzzle speed added to the ship's velocity at launch; the rocket's own
## boost acceleration does the rest (see Rocket).
@export var rocket_launch_speed: float = 3.0

@export_group("Ammo")
@export var starting_type: AmmoType = AmmoType.LASER
@export var starting_laser_charges: int = 10
@export var starting_rockets: int = 0
