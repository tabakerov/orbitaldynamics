class_name WeaponModule
extends ShipModule

## Gun module, fired exactly like an engine burn: hold the mount key and
## apply thrust. Shoots along the module's local +Z — the direction an
## engine's exhaust would leave — so on the front mount it fires forward.
## Laser: instant beam that splits asteroids and recoils the ship like an
## engine impulse. Rocket: spawns a Rocket projectile that boosts briefly,
## then falls along gravity like an asteroid.

signal ammo_changed(current_type: int, laser_charges: int, rocket_charges: int)

## Beam re-cast cap for passing through non-blocking objects (pickups, stars).
const MAX_BEAM_PIERCE_ATTEMPTS: int = 12
const BEAM_VISIBLE_SECONDS: float = 0.08
const ROCKET_DESPAWN_DISTANCE: float = 320.0

var current_type: WeaponProfile.AmmoType = WeaponProfile.AmmoType.LASER
var laser_charges: int = 0
var rocket_charges: int = 0

var _cooldown: float = 0.0
var _beam_time_left: float = 0.0

@onready var _muzzle: Node3D = $Muzzle
@onready var _beam: MeshInstance3D = $Beam
@onready var _active_light: OmniLight3D = $ActiveLight


func _configure() -> void:
	var wp := profile as WeaponProfile
	if wp:
		current_type = wp.starting_type
		laser_charges = wp.starting_laser_charges
		rocket_charges = wp.starting_rockets


func _ready() -> void:
	_beam.visible = false
	_active_light.visible = false


func _process(delta: float) -> void:
	_active_light.visible = active
	if _beam_time_left > 0.0:
		_beam_time_left -= delta
		if _beam_time_left <= 0.0:
			_beam.visible = false


func get_mass() -> float:
	var wp := profile as WeaponProfile
	return wp.dry_mass if wp else 0.0


func physics_tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if active and intensity > 0.0 and _cooldown <= 0.0:
		_try_fire()


## Switches the gun to the given ammo type and adds charges to it (picking
## up lasers arms the laser, picking up rockets arms rockets).
func add_ammo(type: WeaponProfile.AmmoType, amount: int) -> void:
	current_type = type
	match type:
		WeaponProfile.AmmoType.LASER:
			laser_charges += amount
		WeaponProfile.AmmoType.ROCKET:
			rocket_charges += amount
	ammo_changed.emit(current_type, laser_charges, rocket_charges)


func _try_fire() -> void:
	var wp := profile as WeaponProfile
	if not wp or not ship:
		return
	match current_type:
		WeaponProfile.AmmoType.LASER:
			if laser_charges <= 0:
				return
			_fire_laser(wp)
			if not Cheats.enabled:
				laser_charges -= 1
			_cooldown = wp.laser_cooldown
		WeaponProfile.AmmoType.ROCKET:
			if rocket_charges <= 0 or not wp.rocket_scene:
				return
			_fire_rocket(wp)
			if not Cheats.enabled:
				rocket_charges -= 1
			_cooldown = wp.rocket_cooldown
	ammo_changed.emit(current_type, laser_charges, rocket_charges)


func _fire_laser(wp: WeaponProfile) -> void:
	var origin := _muzzle.global_position
	var direction := global_transform.basis.z.normalized()
	var beam_end := origin + direction * wp.laser_range
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [(ship as RigidBody3D).get_rid()]
	for i in MAX_BEAM_PIERCE_ATTEMPTS:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * wp.laser_range)
		query.collide_with_areas = true
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		if collider is Asteroid:
			beam_end = hit["position"]
			(collider as Asteroid).hit_by_laser(direction)
			break
		if collider is PhysicsBody3D:
			# Planets, black holes, stations block the beam.
			beam_end = hit["position"]
			break
		# Pickups, stars, rockets: the beam passes through.
		exclude.append(hit["rid"])
	_show_beam(origin, beam_end)
	var recoil := -direction * wp.laser_impulse
	(ship as RigidBody3D).apply_impulse(recoil, global_position - (ship as RigidBody3D).global_position)


func _fire_rocket(wp: WeaponProfile) -> void:
	var rocket := wp.rocket_scene.instantiate() as Rocket
	if not rocket:
		push_warning("WeaponProfile.rocket_scene did not produce a Rocket")
		return
	var direction := global_transform.basis.z.normalized()
	var body := ship as RigidBody3D
	rocket.initial_velocity = body.linear_velocity + direction * wp.rocket_launch_speed
	rocket.boost_direction = direction
	rocket.despawn_distance = ROCKET_DESPAWN_DISTANCE
	rocket.despawn_center = body.global_position
	_get_projectile_parent().add_child(rocket)
	rocket.global_position = _muzzle.global_position
	rocket.look_at(rocket.global_position + direction, Vector3.UP)


## Rockets must fly in world space: not under the moving ship, and not as
## direct level children (the minimap treats those as bounds-defining), so
## they go into a shared holder node under the level.
func _get_projectile_parent() -> Node:
	var level := ship.get_parent()
	if not level:
		return ship
	var holder := level.get_node_or_null("Projectiles")
	if not holder:
		holder = Node3D.new()
		holder.name = "Projectiles"
		level.add_child(holder)
	return holder


func _show_beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if not _beam or length < 0.05:
		return
	var direction := (to - from) / length
	var basis := Basis.looking_at(direction, Vector3.UP)
	basis = Basis(basis.x, basis.y, basis.z * length)
	_beam.global_transform = Transform3D(basis, (from + to) * 0.5)
	_beam.visible = true
	_beam_time_left = BEAM_VISIBLE_SECONDS
