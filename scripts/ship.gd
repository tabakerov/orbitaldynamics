class_name Ship
extends RigidBody3D

@export var front_engine_scene: PackedScene
@export var rear_engine_scene: PackedScene
@export var left_engine_scene: PackedScene
@export var right_engine_scene: PackedScene
@export var starting_fuel: float = 200.0
@export var crash_velocity: float = 15.0

signal fuel_changed(current: float, maximum: float)
signal crashed

var fuel: float
var max_fuel: float

var _engines: Dictionary = {}
var _keyboard_gimbal: float = 0.0

const STICK_DEADZONE: float = 0.2
const GIMBAL_KEYBOARD_SPEED: float = 2.0

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
	var target: float

	# Controller thumbstick: absolute angle from stick position
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_LEFT_Y),
	)
	if stick.length() > STICK_DEADZONE:
		target = atan2(stick.x, -stick.y)
	else:
		# Keyboard Q/E: incremental, holds position
		if Input.is_action_pressed("gimbal_cw"):
			_keyboard_gimbal += GIMBAL_KEYBOARD_SPEED * delta
		if Input.is_action_pressed("gimbal_ccw"):
			_keyboard_gimbal -= GIMBAL_KEYBOARD_SPEED * delta
		target = _keyboard_gimbal

	for engine: ShipEngine in _engines.values():
		engine.set_gimbal_target(target)


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
		if linear_velocity.length() > crash_velocity:
			crashed.emit()
