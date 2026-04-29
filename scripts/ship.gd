class_name Ship
extends RigidBody3D

@export var front_engine_scene: PackedScene
@export var rear_engine_scene: PackedScene
@export var left_engine_scene: PackedScene
@export var right_engine_scene: PackedScene
@export var starting_fuel: float = 200.0

signal fuel_changed(current: float, maximum: float)
signal crashed(crash_position: Vector3)

var fuel: float
var max_fuel: float

var _engines: Dictionary = {}
var _prev_stick_angle: float = 0.0
var _stick_active: bool = false
var _crashed: bool = false

const STICK_DEADZONE: float = 0.2
const GIMBAL_KEYBOARD_SPEED: float = 2.0
const GIMBAL_STICK_SENSITIVITY: float = 0.10

@onready var _mount_front: Node3D = $MountFront
@onready var _mount_rear: Node3D = $MountRear
@onready var _mount_left: Node3D = $MountLeft
@onready var _mount_right: Node3D = $MountRight


func _ready() -> void:
	max_fuel = starting_fuel
	fuel = starting_fuel
	body_entered.connect(_on_body_entered)
	_setup_engine("front", front_engine_scene, _mount_front)
	_setup_engine("rear", rear_engine_scene, _mount_rear)
	_setup_engine("left", left_engine_scene, _mount_left)
	_setup_engine("right", right_engine_scene, _mount_right)
	fuel_changed.emit(fuel, max_fuel)


func _setup_engine(slot: String, scene: PackedScene, mount: Node3D) -> void:
	if scene == null:
		return
	var engine := scene.instantiate() as ShipEngine
	mount.add_child(engine)
	_engines[slot] = engine


func _physics_process(delta: float) -> void:
	if _crashed:
		return
	_handle_engine_toggles()
	_update_thrust()
	_update_gimbal(delta)
	_apply_gravity()
	_apply_engine_forces()
	_drain_fuel(delta)


func _handle_engine_toggles() -> void:
	_set_engine_active("engine_front", "front")
	_set_engine_active("engine_rear", "rear")
	_set_engine_active("engine_left", "left")
	_set_engine_active("engine_right", "right")


func _set_engine_active(action: String, slot: String) -> void:
	if slot in _engines:
		_engines[slot].active = Input.is_action_pressed(action)


func _update_thrust() -> void:
	var magnitude := Input.get_action_strength("thrust")
	for engine: ShipEngine in _engines.values():
		engine.thrust_magnitude = magnitude


func _update_gimbal(delta: float) -> void:
	var gimbal_delta := 0.0

	# Keyboard Q/E: incremental
	if Input.is_action_pressed("gimbal_cw"):
		gimbal_delta += GIMBAL_KEYBOARD_SPEED * delta
	if Input.is_action_pressed("gimbal_ccw"):
		gimbal_delta -= GIMBAL_KEYBOARD_SPEED * delta

	# Controller thumbstick: angular velocity of stick rotation
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_LEFT_Y),
	)
	if stick.length() > STICK_DEADZONE:
		var stick_angle := atan2(stick.x, -stick.y)
		if _stick_active:
			var angle_delta := stick_angle - _prev_stick_angle
			# Wrap to [-PI, PI] to handle crossing ±180°
			angle_delta = fposmod(angle_delta + PI, TAU) - PI
			gimbal_delta += angle_delta * GIMBAL_STICK_SENSITIVITY
		_prev_stick_angle = stick_angle
		_stick_active = true
	else:
		_stick_active = false

	for engine: ShipEngine in _engines.values():
		engine.apply_gimbal_delta(gimbal_delta)


func _apply_gravity() -> void:
	var gravity := CelestialSim.get_gravity_at(global_position)
	apply_central_force(gravity * mass)


func _apply_engine_forces() -> void:
	if fuel <= 0.0:
		return
	for engine: ShipEngine in _engines.values():
		var force := engine.get_thrust_vector()
		if force.length_squared() > 0.0:
			var offset := engine.global_position - global_position
			apply_force(force, offset)


func _drain_fuel(delta: float) -> void:
	if fuel <= 0.0:
		return
	var drain := 0.0
	for engine: ShipEngine in _engines.values():
		drain += engine.get_fuel_drain(delta)
	if drain > 0.0:
		fuel = maxf(fuel - drain, 0.0)
		fuel_changed.emit(fuel, max_fuel)


func _on_body_entered(body: Node) -> void:
	if body is CelestialBody:
		_crash(body)


func _crash(body: CelestialBody) -> void:
	if _crashed:
		return
	_crashed = true
	_stop_engines()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	sleeping = true
	set_physics_process(false)
	crashed.emit(_get_crash_position(body))


func _stop_engines() -> void:
	for engine: ShipEngine in _engines.values():
		engine.active = false
		engine.thrust_magnitude = 0.0


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
