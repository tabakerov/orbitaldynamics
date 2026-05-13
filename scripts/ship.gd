class_name Ship
extends RigidBody3D

const FUEL_UNIT_MASS: float = 0.02
const STICK_DEADZONE: float = 0.2
const GIMBAL_KEYBOARD_SPEED: float = 2.0
const GIMBAL_STICK_SENSITIVITY: float = 0.10

@export var loadout: ShipLoadout
@export var starting_fuel_override: float = -1.0

signal fuel_changed(current: float, maximum: float)
signal crashed(crash_position: Vector3)

var fuel: float
var max_fuel: float

var _modules: Dictionary = {}
var _mount_nodes: Dictionary = {}
var _hull_dry_mass: float = 10.0
var _prev_stick_angle: float = 0.0
var _stick_active: bool = false
var _crashed: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if loadout:
		_build_from_loadout()
	_recalculate_mass_properties()
	fuel_changed.emit(fuel, max_fuel)


func _build_from_loadout() -> void:
	var hull := loadout.hull
	if not hull:
		push_warning("ShipLoadout has no hull assigned.")
		return
	_hull_dry_mass = hull.dry_mass
	max_fuel = hull.max_internal_fuel
	var start := starting_fuel_override if starting_fuel_override >= 0.0 else loadout.starting_internal_fuel
	fuel = clampf(start, 0.0, max_fuel)

	_spawn_hull_visuals(hull)
	_spawn_mounts_and_modules(hull)


func _spawn_hull_visuals(hull: HullData) -> void:
	if hull.mesh:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "HullMesh"
		mesh_inst.mesh = hull.mesh
		add_child(mesh_inst)
	if hull.collision_shape:
		var col := CollisionShape3D.new()
		col.name = "HullCollision"
		col.shape = hull.collision_shape
		col.transform = hull.collision_transform
		add_child(col)


func _spawn_mounts_and_modules(hull: HullData) -> void:
	for slot: MountSlot in hull.mounts:
		var mount_node := Node3D.new()
		mount_node.name = "Mount_" + MountSlot.binding_name(slot.binding).capitalize()
		mount_node.transform = slot.transform
		add_child(mount_node)
		_mount_nodes[slot.binding] = mount_node

		var profile := loadout.get_module(slot.binding)
		if not profile or not profile.module_scene:
			continue
		var module := profile.module_scene.instantiate() as ShipModule
		if not module:
			push_warning("Module scene did not produce a ShipModule")
			continue
		module.attach(self, profile)
		mount_node.add_child(module)
		_modules[slot.binding] = module


func _physics_process(delta: float) -> void:
	if _crashed:
		return
	_update_module_inputs()
	_update_gimbal(delta)
	for module: ShipModule in _modules.values():
		module.physics_tick(delta)
	_apply_engine_forces()
	_apply_fuel_flow(delta)
	_apply_gravity()
	_recalculate_mass_properties()


func _update_module_inputs() -> void:
	var intensity := Input.get_action_strength("thrust")
	for binding: int in _modules:
		var module: ShipModule = _modules[binding]
		var action_name := "mount_" + MountSlot.binding_name(binding)
		module.active = Input.is_action_pressed(action_name)
		module.intensity = intensity


func _update_gimbal(delta: float) -> void:
	var gimbal_delta := 0.0

	if Input.is_action_pressed("gimbal_cw"):
		gimbal_delta += GIMBAL_KEYBOARD_SPEED * delta
	if Input.is_action_pressed("gimbal_ccw"):
		gimbal_delta -= GIMBAL_KEYBOARD_SPEED * delta

	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_LEFT_Y),
	)
	if stick.length() > STICK_DEADZONE:
		var stick_angle := atan2(stick.x, -stick.y)
		if _stick_active:
			var angle_delta := stick_angle - _prev_stick_angle
			angle_delta = fposmod(angle_delta + PI, TAU) - PI
			gimbal_delta += angle_delta * GIMBAL_STICK_SENSITIVITY
		_prev_stick_angle = stick_angle
		_stick_active = true
	else:
		_stick_active = false

	for module: ShipModule in _modules.values():
		module.apply_gimbal_delta(gimbal_delta)


func _apply_engine_forces() -> void:
	for module: ShipModule in _modules.values():
		var force := module.get_thrust_vector()
		if force.length_squared() > 0.0:
			var offset := module.global_position - global_position
			apply_force(force, offset)


func _apply_fuel_flow(delta: float) -> void:
	var drain := 0.0
	for module: ShipModule in _modules.values():
		drain += module.get_fuel_drain(delta)

	var total_potential := 0.0
	var per_module_potential: Array = []
	for module: ShipModule in _modules.values():
		var p := module.get_potential_fuel_intake(delta)
		if p > 0.0:
			per_module_potential.append([module, p])
			total_potential += p

	var fuel_after_drain := maxf(fuel - drain, 0.0)
	var room := max_fuel - fuel_after_drain
	var total_intake := minf(total_potential, room)

	var ratio := 0.0
	if total_potential > 0.0:
		ratio = total_intake / total_potential

	for entry in per_module_potential:
		var module: ShipModule = entry[0]
		var p: float = entry[1]
		module.commit_fuel_intake(p * ratio)

	var new_fuel := fuel_after_drain + total_intake
	if not is_equal_approx(new_fuel, fuel):
		fuel = new_fuel
		fuel_changed.emit(fuel, max_fuel)


func _apply_gravity() -> void:
	var gravity := CelestialSim.get_gravity_at(global_position)
	apply_central_force(gravity * mass)


func _recalculate_mass_properties() -> void:
	var total := _hull_dry_mass + fuel * FUEL_UNIT_MASS
	var weighted := Vector3.ZERO
	for binding: int in _modules:
		var module: ShipModule = _modules[binding]
		var mount: Node3D = _mount_nodes[binding]
		var m := module.get_mass()
		if m > 0.0:
			var local_pos: Vector3 = mount.position + mount.basis * module.position
			total += m
			weighted += m * local_pos
	if total > 0.0:
		mass = total
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = weighted / total


func _on_body_entered(body: Node) -> void:
	if body is CelestialBody:
		_crash(body)


func _crash(body: CelestialBody) -> void:
	if _crashed:
		return
	_crashed = true
	_stop_modules()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = true
	set_physics_process(false)
	crashed.emit(_get_crash_position(body))


func _stop_modules() -> void:
	for module: ShipModule in _modules.values():
		module.active = false
		module.intensity = 0.0


func _get_crash_position(body: CelestialBody) -> Vector3:
	var offset := global_position - body.global_position
	if offset.length_squared() <= 0.0001:
		return global_position

	var radius := _get_body_radius(body)
	if radius <= 0.0:
		return global_position

	return body.global_position + offset.normalized() * radius


func _get_body_radius(body: CelestialBody) -> float:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not collision:
		return body.body_data.radius if body.body_data else 0.0

	var sphere_shape := collision.shape as SphereShape3D
	if not sphere_shape:
		return body.body_data.radius if body.body_data else 0.0

	var basis := body.global_transform.basis
	var scale := maxf(basis.x.length(), maxf(basis.y.length(), basis.z.length()))
	return sphere_shape.radius * scale
