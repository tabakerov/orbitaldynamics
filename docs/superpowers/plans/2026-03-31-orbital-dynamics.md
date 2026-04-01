# Orbital Dynamics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable first level of a spaceship navigation game with modular gimbaling engines, N-body celestial simulation, and top-down camera.

**Architecture:** Hybrid physics — custom symplectic Euler integrator for celestial bodies (autoload singleton), Godot RigidBody3D + Jolt for ship. Engines apply forces at mount offsets for emergent torque. Camera rig follows ship position and Y-rotation.

**Tech Stack:** Godot 4.6, GDScript, Jolt Physics, Forward Plus renderer

---

## File Structure

```
scripts/
  celestial_body_data.gd   — Resource: per-body mass, gravity params, radius
  celestial_simulation.gd  — Autoload singleton (no class_name): N-body integrator + gravity query
  celestial_body.gd        — AnimatableBody3D: syncs visual position from sim
  engine.gd                — ShipEngine (Node3D): thrust vector, gimbal, fuel drain, visual indicators
  ship.gd                  — Ship (RigidBody3D): hold-to-activate input, per-engine gimbal, fuel, gravity
  camera_rig.gd            — CameraRig (Node3D): follows ship position + Y rotation, explicit current camera
  fuel_pickup.gd           — FuelPickup (Area3D): grants fuel on overlap
  target.gd                — Target (Area3D): emits signal on ship arrival
  level.gd                 — Level (Node3D): initializes sim from child celestial bodies
  level_select.gd          — Control: level select / pause menu with gamepad support
  hud.gd                   — Control: fuel gauge
  main.gd                  — Node3D: level loading, menu, restart, quit, win flow

scenes/
  engine.tscn              — Engine body + exhaust mesh + particles + active light
  ship.tscn                — Hull mesh, collision, 4 mount points (exhaust away from ship)
  celestial_body.tscn      — Sphere mesh + collision, driven by sim
  fuel_pickup.tscn         — Small pickup mesh + Area3D
  target.tscn              — Target marker mesh + Area3D
  camera_rig.tscn          — Node3D + Camera3D looking down (-90° X rotation)
  hud.tscn                 — CanvasLayer + fuel bar
  levels/
    level_01.tscn          — First test level

resources/
  planet_medium.tres       — CelestialBodyData for a medium planet

tests/
  test_celestial_sim.gd    — Headless test: gravity math + integration (uses preload, untyped)
```

---

### Task 1: Project Setup & Input Mapping

**Files:**
- Modify: `project.godot`
- Create directories: `scripts/`, `scenes/`, `scenes/levels/`, `resources/`, `tests/`

- [ ] **Step 1: Create project directories**

```bash
mkdir -p scripts scenes/levels resources tests
```

- [ ] **Step 2: Update project.godot with input actions and autoload**

Replace the full `project.godot` with:

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.
;
; Format:
;   [section] ; section goes between []
;   param=value ; assign values to parameters

config_version=5

[application]

config/name="OrbitalDynamics"
config/run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "Forward Plus")
config/icon="res://icon.svg"

[autoload]

CelestialSim="*res://scripts/celestial_simulation.gd"

[input]

engine_front={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":119,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":3,"pressure":0.0,"pressed":true,"script":null)
]
}
engine_rear={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":115,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":0,"pressure":0.0,"pressed":true,"script":null)
]
}
engine_left={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":2,"pressure":0.0,"pressed":true,"script":null)
]
}
engine_right={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":1,"pressure":0.0,"pressed":true,"script":null)
]
}
thrust={
"deadzone": 0.1,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":32,"key_label":0,"unicode":32,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":5,"axis_value":1.0,"script":null)
]
}
gimbal_ccw={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"location":0,"echo":false,"script":null)
]
}
gimbal_cw={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"location":0,"echo":false,"script":null)
]
}
restart={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":82,"key_label":0,"unicode":114,"location":0,"echo":false,"script":null)
, Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":6,"pressure":0.0,"pressed":true,"script":null)
]
}

[physics]

3d/physics_engine="Jolt Physics"

[rendering]

rendering_device/driver.windows="d3d12"
```

Key mappings:
| Action | Keyboard | Controller |
|--------|----------|------------|
| engine_front | W | Y (top face) |
| engine_rear | S | A (bottom face) |
| engine_left | A | X (left face) |
| engine_right | D | B (right face) |
| thrust | Space | Right Trigger (axis 5) |
| gimbal_ccw | Q | (thumbstick, handled in code) |
| gimbal_cw | E | (thumbstick, handled in code) |
| restart | R | Start (button 6) |

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "chore: project setup with input actions and autoload"
```

---

### Task 2: Celestial Body Data Resource

**Files:**
- Create: `scripts/celestial_body_data.gd`
- Create: `resources/planet_medium.tres`

- [ ] **Step 1: Create CelestialBodyData resource class**

Create `scripts/celestial_body_data.gd`:

```gdscript
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
```

- [ ] **Step 2: Create a medium planet resource**

Create `resources/planet_medium.tres`:

```
[gd_resource type="Resource" script_class="CelestialBodyData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/celestial_body_data.gd" id="1"]

[resource]
script = ExtResource("1")
mass = 1000.0
gravity_strength = 1.0
falloff_exponent = 2.0
max_range = 80.0
min_range = 2.0
radius = 3.0
```

- [ ] **Step 3: Commit**

```bash
git add scripts/celestial_body_data.gd resources/planet_medium.tres
git commit -m "feat: add CelestialBodyData resource class"
```

---

### Task 3: Celestial Simulation

**Files:**
- Create: `scripts/celestial_simulation.gd`

- [ ] **Step 1: Write the celestial simulation script**

Create `scripts/celestial_simulation.gd`:

```gdscript
class_name CelestialSim
extends Node

## Gravitational constant for inter-body attraction.
@export var gravitational_constant: float = 1.0

var active: bool = false

var _count: int = 0
var _positions: PackedVector3Array
var _velocities: PackedVector3Array
var _masses: PackedFloat64Array
var _gravity_strengths: PackedFloat64Array
var _falloff_exponents: PackedFloat64Array
var _max_ranges: PackedFloat64Array
var _min_ranges: PackedFloat64Array


func initialize(
	data: Array[CelestialBodyData],
	positions: PackedVector3Array,
	velocities: PackedVector3Array
) -> void:
	_count = data.size()
	_positions = positions.duplicate()
	_velocities = velocities.duplicate()
	_masses = PackedFloat64Array()
	_gravity_strengths = PackedFloat64Array()
	_falloff_exponents = PackedFloat64Array()
	_max_ranges = PackedFloat64Array()
	_min_ranges = PackedFloat64Array()
	for d in data:
		_masses.append(d.mass)
		_gravity_strengths.append(d.gravity_strength)
		_falloff_exponents.append(d.falloff_exponent)
		_max_ranges.append(d.max_range)
		_min_ranges.append(d.min_range)
	active = true


func clear() -> void:
	active = false
	_count = 0
	_positions = PackedVector3Array()
	_velocities = PackedVector3Array()
	_masses = PackedFloat64Array()
	_gravity_strengths = PackedFloat64Array()
	_falloff_exponents = PackedFloat64Array()
	_max_ranges = PackedFloat64Array()
	_min_ranges = PackedFloat64Array()


func _physics_process(delta: float) -> void:
	if active and _count > 0:
		step(delta)


func step(delta: float) -> void:
	# Compute inter-body gravitational accelerations
	var accels: Array[Vector3] = []
	accels.resize(_count)
	for i in _count:
		accels[i] = Vector3.ZERO

	for i in _count:
		for j in range(i + 1, _count):
			var offset := _positions[j] - _positions[i]
			var dist := offset.length()
			if dist < 0.001:
				continue
			var dir := offset / dist
			var accel_on_i := gravitational_constant * _masses[j] / (dist * dist)
			var accel_on_j := gravitational_constant * _masses[i] / (dist * dist)
			accels[i] += dir * accel_on_i
			accels[j] -= dir * accel_on_j

	# Symplectic Euler: velocity first, then position
	for i in _count:
		_velocities[i] += accels[i] * delta
		_positions[i] += _velocities[i] * delta
		# Enforce Y=0 plane constraint
		_positions[i].y = 0.0
		_velocities[i].y = 0.0


func get_gravity_at(pos: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for i in _count:
		var offset := _positions[i] - pos
		var raw_dist := offset.length()
		if raw_dist > _max_ranges[i]:
			continue
		var dist := clampf(raw_dist, _min_ranges[i], _max_ranges[i])
		var strength := _gravity_strengths[i] * _masses[i] / pow(dist, _falloff_exponents[i])
		total += offset.normalized() * strength
	return total


func get_body_position(index: int) -> Vector3:
	return _positions[index]


func get_body_velocity(index: int) -> Vector3:
	return _velocities[index]


func get_body_count() -> int:
	return _count
```

- [ ] **Step 2: Commit**

```bash
git add scripts/celestial_simulation.gd
git commit -m "feat: add N-body celestial simulation with tunable gravity"
```

---

### Task 4: Test Celestial Simulation

**Files:**
- Create: `tests/test_celestial_sim.gd`

- [ ] **Step 1: Write headless test script**

Create `tests/test_celestial_sim.gd`:

```gdscript
extends SceneTree


func _init() -> void:
	_test_single_body_gravity_direction()
	_test_single_body_gravity_magnitude()
	_test_gravity_inverse_square_falloff()
	_test_gravity_max_range_cutoff()
	_test_gravity_min_range_clamp()
	_test_two_body_orbit_bounded()
	_test_plane_constraint()
	print("All celestial simulation tests passed!")
	quit()


func _make_sim() -> CelestialSim:
	var sim := CelestialSim.new()
	sim.gravitational_constant = 1.0
	return sim


func _make_body(
	m: float = 1000.0,
	gs: float = 1.0,
	fe: float = 2.0,
	maxr: float = 80.0,
	minr: float = 0.5,
) -> CelestialBodyData:
	var d := CelestialBodyData.new()
	d.mass = m
	d.gravity_strength = gs
	d.falloff_exponent = fe
	d.max_range = maxr
	d.min_range = minr
	d.radius = 3.0
	return d


func _test_single_body_gravity_direction() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var gravity := sim.get_gravity_at(Vector3(10, 0, 0))
	assert(
		gravity.normalized().is_equal_approx(Vector3(-1, 0, 0)),
		"Gravity should point toward body. Got: %s" % str(gravity.normalized()),
	)
	print("  PASS: single body gravity direction")


func _test_single_body_gravity_magnitude() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	# gravity_strength(1) * mass(1000) / dist(10)^2 = 10.0
	var gravity := sim.get_gravity_at(Vector3(10, 0, 0))
	assert(
		absf(gravity.length() - 10.0) < 0.01,
		"Gravity magnitude should be ~10.0, got %f" % gravity.length(),
	)
	print("  PASS: single body gravity magnitude")


func _test_gravity_inverse_square_falloff() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var g_at_5 := sim.get_gravity_at(Vector3(5, 0, 0)).length()
	var g_at_10 := sim.get_gravity_at(Vector3(10, 0, 0)).length()
	var ratio := g_at_5 / g_at_10
	assert(
		absf(ratio - 4.0) < 0.01,
		"Inverse square ratio should be 4.0, got %f" % ratio,
	)
	print("  PASS: inverse square falloff")


func _test_gravity_max_range_cutoff() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body(1000.0, 1.0, 2.0, 50.0)],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var gravity := sim.get_gravity_at(Vector3(51, 0, 0))
	assert(
		gravity.is_equal_approx(Vector3.ZERO),
		"Gravity beyond max_range should be zero. Got: %s" % str(gravity),
	)
	print("  PASS: max range cutoff")


func _test_gravity_min_range_clamp() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body(1000.0, 1.0, 2.0, 80.0, 5.0)],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	# At distance 1.0 (less than min_range 5.0), distance is clamped to 5.0
	var g_at_1 := sim.get_gravity_at(Vector3(1, 0, 0)).length()
	var g_at_5 := sim.get_gravity_at(Vector3(5, 0, 0)).length()
	assert(
		absf(g_at_1 - g_at_5) < 0.01,
		"Gravity inside min_range should equal gravity at min_range. Got %f vs %f" % [g_at_1, g_at_5],
	)
	print("  PASS: min range clamp")


func _test_two_body_orbit_bounded() -> void:
	var sim := _make_sim()
	var body := _make_body(100.0)
	sim.initialize(
		[body, body],
		PackedVector3Array([Vector3(-5, 0, 0), Vector3(5, 0, 0)]),
		PackedVector3Array([Vector3(0, 0, -1), Vector3(0, 0, 1)]),
	)
	for i in 1000:
		sim.step(1.0 / 60.0)
	var dist := sim.get_body_position(0).distance_to(sim.get_body_position(1))
	assert(
		dist < 200.0,
		"Two-body system should remain bounded. Distance: %f" % dist,
	)
	print("  PASS: two body orbit bounded")


func _test_plane_constraint() -> void:
	var sim := _make_sim()
	var body := _make_body(100.0)
	# Intentionally give Y velocity — should be zeroed
	sim.initialize(
		[body],
		PackedVector3Array([Vector3(0, 5, 0)]),
		PackedVector3Array([Vector3(0, 10, 0)]),
	)
	sim.step(1.0 / 60.0)
	assert(
		absf(sim.get_body_position(0).y) < 0.001,
		"Body should be constrained to Y=0. Got Y=%f" % sim.get_body_position(0).y,
	)
	assert(
		absf(sim.get_body_velocity(0).y) < 0.001,
		"Velocity Y should be zeroed. Got %f" % sim.get_body_velocity(0).y,
	)
	print("  PASS: plane constraint enforced")
```

- [ ] **Step 2: Run tests**

```bash
godot --headless --script tests/test_celestial_sim.gd
```

Expected output:
```
  PASS: single body gravity direction
  PASS: single body gravity magnitude
  PASS: inverse square falloff
  PASS: max range cutoff
  PASS: min range clamp
  PASS: two body orbit bounded
  PASS: plane constraint enforced
All celestial simulation tests passed!
```

If any assertion fails, fix the issue in `celestial_simulation.gd` and re-run.

- [ ] **Step 3: Commit**

```bash
git add tests/test_celestial_sim.gd
git commit -m "test: add headless tests for celestial simulation"
```

---

### Task 5: Engine Component

**Files:**
- Create: `scripts/engine.gd`
- Create: `scenes/engine.tscn`

- [ ] **Step 1: Create engine script**

Create `scripts/engine.gd`:

```gdscript
class_name Engine
extends Node3D

@export var max_thrust: float = 100.0
@export var gimbal_range_deg: float = 30.0
@export var fuel_consumption_rate: float = 10.0

var active: bool = false
var gimbal_angle: float = 0.0
var thrust_magnitude: float = 0.0

var _gimbal_range_rad: float

@onready var _exhaust: MeshInstance3D = $Exhaust


func _ready() -> void:
	_gimbal_range_rad = deg_to_rad(gimbal_range_deg)


func _process(_delta: float) -> void:
	_exhaust.visible = active and thrust_magnitude > 0.0


func set_gimbal_target(target: float) -> void:
	gimbal_angle = clampf(target, -_gimbal_range_rad, _gimbal_range_rad)


func get_thrust_vector() -> Vector3:
	if not active or thrust_magnitude <= 0.0:
		return Vector3.ZERO
	var local_dir := Vector3(0, 0, -1).rotated(Vector3.UP, gimbal_angle)
	return global_transform.basis * local_dir * max_thrust * thrust_magnitude


func get_fuel_drain(delta: float) -> float:
	if not active or thrust_magnitude <= 0.0:
		return 0.0
	return fuel_consumption_rate * thrust_magnitude * delta
```

- [ ] **Step 2: Create engine scene**

Create `scenes/engine.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/engine.gd" id="1"]

[sub_resource type="BoxMesh" id="SubResource_1"]
size = Vector3(0.15, 0.1, 0.3)

[sub_resource type="StandardMaterial3D" id="SubResource_2"]
albedo_color = Color(0.5, 0.5, 0.6, 1)

[sub_resource type="BoxMesh" id="SubResource_3"]
size = Vector3(0.1, 0.08, 0.15)

[sub_resource type="StandardMaterial3D" id="SubResource_4"]
albedo_color = Color(1, 0.6, 0.1, 1)
emission_enabled = true
emission = Color(1, 0.4, 0, 1)
emission_energy_multiplier = 2.0

[node name="Engine" type="Node3D"]
script = ExtResource("1")

[node name="Body" type="MeshInstance3D" parent="."]
mesh = SubResource("SubResource_1")
material_override = SubResource("SubResource_2")

[node name="Exhaust" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0.2)
visible = false
mesh = SubResource("SubResource_3")
material_override = SubResource("SubResource_4")
```

The exhaust mesh is offset behind the engine body (+Z = backward from the engine's nozzle direction) and starts hidden. It becomes visible when the engine fires.

- [ ] **Step 3: Commit**

```bash
git add scripts/engine.gd scenes/engine.tscn
git commit -m "feat: add engine component with gimbal and exhaust indicator"
```

---

### Task 6: Ship Scene

**Files:**
- Create: `scripts/ship.gd`
- Create: `scenes/ship.tscn`

- [ ] **Step 1: Create ship script**

Create `scripts/ship.gd`:

```gdscript
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
	var engine := scene.instantiate() as Engine
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
	_try_toggle("engine_front", "front")
	_try_toggle("engine_rear", "rear")
	_try_toggle("engine_left", "left")
	_try_toggle("engine_right", "right")


func _try_toggle(action: String, slot: String) -> void:
	if Input.is_action_just_pressed(action) and slot in _engines:
		_engines[slot].active = not _engines[slot].active


func _update_thrust() -> void:
	var magnitude := Input.get_action_strength("thrust")
	for engine: Engine in _engines.values():
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

	for engine: Engine in _engines.values():
		engine.set_gimbal_target(target)


func _apply_gravity() -> void:
	var gravity := CelestialSim.get_gravity_at(global_position)
	apply_central_force(gravity * mass)


func _apply_engine_forces() -> void:
	if fuel <= 0.0:
		return
	for engine: Engine in _engines.values():
		var force := engine.get_thrust_vector()
		if force.length_squared() > 0.0:
			var offset := engine.global_position - global_position
			apply_force(force, offset)


func _drain_fuel(delta: float) -> void:
	if fuel <= 0.0:
		return
	var drain := 0.0
	for engine: Engine in _engines.values():
		drain += engine.get_fuel_drain(delta)
	if drain > 0.0:
		fuel = maxf(fuel - drain, 0.0)
		fuel_changed.emit(fuel, max_fuel)


func _on_body_entered(body: Node) -> void:
	if body is CelestialBody:
		if linear_velocity.length() > crash_velocity:
			crashed.emit()
```

- [ ] **Step 2: Create ship scene**

Create `scenes/ship.tscn`:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/ship.gd" id="1"]

[sub_resource type="BoxShape3D" id="SubResource_1"]
size = Vector3(1, 0.3, 2)

[sub_resource type="BoxMesh" id="SubResource_2"]
size = Vector3(1, 0.3, 2)

[sub_resource type="StandardMaterial3D" id="SubResource_3"]
albedo_color = Color(0.3, 0.4, 0.7, 1)

[node name="Ship" type="RigidBody3D"]
mass = 10.0
gravity_scale = 0.0
axis_lock_linear_y = true
axis_lock_angular_x = true
axis_lock_angular_z = true
contact_monitor = true
max_contacts_reported = 4
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("SubResource_1")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
mesh = SubResource("SubResource_2")
material_override = SubResource("SubResource_3")

[node name="MountFront" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -0.9)

[node name="MountRear" type="Node3D" parent="."]
transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0.9)

[node name="MountLeft" type="Node3D" parent="."]
transform = Transform3D(0, 0, -1, 0, 1, 0, 1, 0, 0, -0.5, 0, 0.3)

[node name="MountRight" type="Node3D" parent="."]
transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 0.5, 0, 0.3)
```

Mount orientations (each engine's local -Z becomes the thrust direction):
- **MountFront** (0, 0, -0.9): no rotation — thrust = forward (-Z)
- **MountRear** (0, 0, 0.9): 180 deg Y — thrust = backward (+Z)
- **MountLeft** (-0.5, 0, 0.3): 90 deg Y — thrust = left (-X). Positioned behind CoM for torque.
- **MountRight** (0.5, 0, 0.3): -90 deg Y — thrust = right (+X). Positioned behind CoM for torque.

- [ ] **Step 3: Commit**

```bash
git add scripts/ship.gd scenes/ship.tscn
git commit -m "feat: add ship with modular engine mounts and input handling"
```

---

### Task 7: Camera Rig

**Files:**
- Create: `scripts/camera_rig.gd`
- Create: `scenes/camera_rig.tscn`

- [ ] **Step 1: Create camera rig script**

Create `scripts/camera_rig.gd`:

```gdscript
class_name CameraRig
extends Node3D

var target: Node3D


func _physics_process(_delta: float) -> void:
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y
```

- [ ] **Step 2: Create camera rig scene**

Create `scenes/camera_rig.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/camera_rig.gd" id="1"]

[node name="CameraRig" type="Node3D"]
script = ExtResource("1")

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 60, 0)
fov = 60.0
near = 0.1
far = 200.0
```

Camera is positioned 60 units above the rig, rotated -90 degrees around X to look straight down. The rig's Y-rotation matches the ship, so the ship always appears to face "up" on screen.

- [ ] **Step 3: Commit**

```bash
git add scripts/camera_rig.gd scenes/camera_rig.tscn
git commit -m "feat: add camera rig that follows ship position and rotation"
```

---

### Task 8: Celestial Body Visual

**Files:**
- Create: `scripts/celestial_body.gd`
- Create: `scenes/celestial_body.tscn`

- [ ] **Step 1: Create celestial body script**

Create `scripts/celestial_body.gd`:

```gdscript
class_name CelestialBody
extends AnimatableBody3D

@export var body_data: CelestialBodyData
@export var initial_velocity: Vector3 = Vector3.ZERO

var sim_index: int = -1


func _ready() -> void:
	if body_data:
		_setup_visuals()


func _physics_process(_delta: float) -> void:
	if sim_index >= 0:
		global_position = CelestialSim.get_body_position(sim_index)


func _setup_visuals() -> void:
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = body_data.radius

	var mesh_instance := $MeshInstance3D as MeshInstance3D
	var sphere_mesh := mesh_instance.mesh as SphereMesh
	sphere_mesh.radius = body_data.radius
	sphere_mesh.height = body_data.radius * 2.0
```

- [ ] **Step 2: Create celestial body scene**

Create `scenes/celestial_body.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/celestial_body.gd" id="1"]

[sub_resource type="SphereShape3D" id="SubResource_1"]
radius = 3.0

[sub_resource type="SphereMesh" id="SubResource_2"]
radius = 3.0
height = 6.0

[sub_resource type="StandardMaterial3D" id="SubResource_3"]
albedo_color = Color(0.6, 0.4, 0.2, 1)

[node name="CelestialBody" type="AnimatableBody3D"]
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("SubResource_1")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
mesh = SubResource("SubResource_2")
material_override = SubResource("SubResource_3")
```

- [ ] **Step 3: Commit**

```bash
git add scripts/celestial_body.gd scenes/celestial_body.tscn
git commit -m "feat: add celestial body visual synced from simulation"
```

---

### Task 9: Fuel Pickup & Target

**Files:**
- Create: `scripts/fuel_pickup.gd`, `scripts/target.gd`
- Create: `scenes/fuel_pickup.tscn`, `scenes/target.tscn`

- [ ] **Step 1: Create fuel pickup script**

Create `scripts/fuel_pickup.gd`:

```gdscript
class_name FuelPickup
extends Area3D

@export var fuel_amount: float = 50.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Ship:
		body.fuel = minf(body.fuel + fuel_amount, body.max_fuel)
		body.fuel_changed.emit(body.fuel, body.max_fuel)
		queue_free()
```

- [ ] **Step 2: Create fuel pickup scene**

Create `scenes/fuel_pickup.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/fuel_pickup.gd" id="1"]

[sub_resource type="SphereShape3D" id="SubResource_1"]
radius = 1.0

[sub_resource type="BoxMesh" id="SubResource_2"]
size = Vector3(0.8, 0.8, 0.8)

[sub_resource type="StandardMaterial3D" id="SubResource_3"]
albedo_color = Color(0.2, 0.8, 0.2, 1)
emission_enabled = true
emission = Color(0.1, 0.5, 0.1, 1)
emission_energy_multiplier = 1.5

[node name="FuelPickup" type="Area3D"]
monitoring = true
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("SubResource_1")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
mesh = SubResource("SubResource_2")
material_override = SubResource("SubResource_3")
```

- [ ] **Step 3: Create target script**

Create `scripts/target.gd`:

```gdscript
class_name Target
extends Area3D

signal target_reached


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Ship:
		target_reached.emit()
```

- [ ] **Step 4: Create target scene**

Create `scenes/target.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/target.gd" id="1"]

[sub_resource type="SphereShape3D" id="SubResource_1"]
radius = 2.0

[sub_resource type="TorusMesh" id="SubResource_2"]
inner_radius = 1.0
outer_radius = 2.0

[sub_resource type="StandardMaterial3D" id="SubResource_3"]
albedo_color = Color(0.9, 0.8, 0.1, 1)
emission_enabled = true
emission = Color(0.8, 0.7, 0, 1)
emission_energy_multiplier = 2.0

[node name="Target" type="Area3D"]
monitoring = true
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("SubResource_1")

[node name="MeshInstance3D" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 0, 0)
mesh = SubResource("SubResource_2")
material_override = SubResource("SubResource_3")
```

The torus mesh is rotated to lie flat on the X/Z plane so it's visible from the top-down camera.

- [ ] **Step 5: Commit**

```bash
git add scripts/fuel_pickup.gd scripts/target.gd scenes/fuel_pickup.tscn scenes/target.tscn
git commit -m "feat: add fuel pickup and target with collision detection"
```

---

### Task 10: HUD

**Files:**
- Create: `scripts/hud.gd`
- Create: `scenes/hud.tscn`

- [ ] **Step 1: Create HUD script**

Create `scripts/hud.gd`:

```gdscript
extends Control

@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _fuel_label: Label = %FuelLabel


func setup(ship: Ship) -> void:
	ship.fuel_changed.connect(_on_fuel_changed)
	_on_fuel_changed(ship.fuel, ship.max_fuel)


func _on_fuel_changed(current: float, maximum: float) -> void:
	_fuel_bar.max_value = maximum
	_fuel_bar.value = current
	_fuel_label.text = "Fuel: %d%%" % roundi(current / maximum * 100.0)
```

- [ ] **Step 2: Create HUD scene**

Create `scenes/hud.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/hud.gd" id="1"]

[node name="HUD" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1")

[node name="FuelBar" type="ProgressBar" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = -1
anchor_left = 0.02
anchor_top = 0.92
anchor_right = 0.25
anchor_bottom = 0.96
max_value = 200.0
value = 200.0
show_percentage = false

[node name="FuelLabel" type="Label" parent="."]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = -1
anchor_left = 0.02
anchor_top = 0.88
anchor_right = 0.25
anchor_bottom = 0.92
text = "Fuel: 100%"
```

- [ ] **Step 3: Commit**

```bash
git add scripts/hud.gd scenes/hud.tscn
git commit -m "feat: add basic HUD with fuel gauge"
```

---

### Task 11: Level Scene

**Files:**
- Create: `scripts/level.gd`
- Create: `scenes/levels/level_01.tscn`

- [ ] **Step 1: Create level script**

Create `scripts/level.gd`:

```gdscript
class_name Level
extends Node3D

signal level_completed
signal ship_crashed


func _ready() -> void:
	_init_celestial_sim()
	_connect_ship()
	_connect_targets()


func _init_celestial_sim() -> void:
	var bodies: Array[CelestialBody] = []
	for child in get_children():
		if child is CelestialBody:
			bodies.append(child)

	var data: Array[CelestialBodyData] = []
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()

	for i in bodies.size():
		var body := bodies[i]
		data.append(body.body_data)
		positions.append(body.global_position)
		velocities.append(body.initial_velocity)
		body.sim_index = i

	CelestialSim.initialize(data, positions, velocities)


func _connect_ship() -> void:
	var ship := get_ship()
	if ship:
		ship.crashed.connect(func() -> void: ship_crashed.emit())


func _connect_targets() -> void:
	for child in get_children():
		if child is Target:
			child.target_reached.connect(func() -> void: level_completed.emit())


func get_ship() -> Ship:
	for child in get_children():
		if child is Ship:
			return child
	return null
```

- [ ] **Step 2: Create level_01 scene**

Create `scenes/levels/level_01.tscn`:

```
[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://scripts/level.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/celestial_body.tscn" id="2"]
[ext_resource type="Resource" path="res://resources/planet_medium.tres" id="3"]
[ext_resource type="PackedScene" path="res://scenes/ship.tscn" id="4"]
[ext_resource type="PackedScene" path="res://scenes/engine.tscn" id="5"]
[ext_resource type="PackedScene" path="res://scenes/target.tscn" id="6"]
[ext_resource type="PackedScene" path="res://scenes/fuel_pickup.tscn" id="7"]

[node name="Level01" type="Node3D"]
script = ExtResource("1")

[node name="Planet" parent="." instance=ExtResource("2")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
body_data = ExtResource("3")
initial_velocity = Vector3(0, 0, 0)

[node name="Ship" parent="." instance=ExtResource("4")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 30, 0, 0)
front_engine_scene = ExtResource("5")
rear_engine_scene = ExtResource("5")
left_engine_scene = ExtResource("5")
right_engine_scene = ExtResource("5")
starting_fuel = 200.0

[node name="Target" parent="." instance=ExtResource("6")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -30, 0, 0)

[node name="FuelPickup" parent="." instance=ExtResource("7")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 20)
fuel_amount = 50.0
```

Layout: Planet at origin, ship 30 units to the right, target 30 units to the left, fuel pickup 20 units behind the planet.

- [ ] **Step 3: Commit**

```bash
git add scripts/level.gd scenes/levels/level_01.tscn
git commit -m "feat: add level system and first test level"
```

---

### Task 12: Main Scene & Level Flow

**Files:**
- Create: `scripts/main.gd`
- Create: `scenes/main.tscn`

- [ ] **Step 1: Create main script**

Create `scripts/main.gd`:

```gdscript
extends Node3D

@export var levels: Array[PackedScene] = []

var _current_level: Level
var _level_index: int = 0

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _hud: Control = $CanvasLayer/HUD


func _ready() -> void:
	_load_level(0)


func _load_level(index: int) -> void:
	if _current_level:
		_current_level.queue_free()
		await _current_level.tree_exited

	_level_index = clampi(index, 0, levels.size() - 1)
	_current_level = levels[_level_index].instantiate() as Level
	add_child(_current_level)

	_current_level.level_completed.connect(_on_level_completed)
	_current_level.ship_crashed.connect(_on_ship_crashed)

	var ship := _current_level.get_ship()
	if ship:
		_camera_rig.target = ship
		_hud.setup(ship)


func _on_level_completed() -> void:
	if _level_index + 1 < levels.size():
		_load_level(_level_index + 1)
	else:
		print("All levels complete!")


func _on_ship_crashed() -> void:
	_load_level(_level_index)


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("restart"):
		_load_level(_level_index)
```

- [ ] **Step 2: Create main scene**

Create `scenes/main.tscn`:

```
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1"]
[ext_resource type="PackedScene" path="res://scenes/camera_rig.tscn" id="2"]
[ext_resource type="Script" path="res://scripts/hud.gd" id="3"]
[ext_resource type="PackedScene" path="res://scenes/levels/level_01.tscn" id="4"]

[node name="Main" type="Node3D"]
script = ExtResource("1")
levels = [ExtResource("4")]

[node name="CameraRig" parent="." instance=ExtResource("2")]

[node name="CanvasLayer" type="CanvasLayer" parent="."]

[node name="HUD" type="Control" parent="CanvasLayer"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("3")

[node name="FuelBar" type="ProgressBar" parent="CanvasLayer/HUD"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = -1
anchor_left = 0.02
anchor_top = 0.92
anchor_right = 0.25
anchor_bottom = 0.96
max_value = 200.0
value = 200.0
show_percentage = false

[node name="FuelLabel" type="Label" parent="CanvasLayer/HUD"]
unique_name_in_owner = true
layout_mode = 1
anchors_preset = -1
anchor_left = 0.02
anchor_top = 0.88
anchor_right = 0.25
anchor_bottom = 0.92
text = "Fuel: 100%"

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 0, -1, 0, 1, 0, 0, 50, 0)
```

The HUD is inlined in the main scene (rather than instanced from `scenes/hud.tscn`) to avoid ext_resource complexity. A DirectionalLight3D points downward so the 3D objects are visible.

- [ ] **Step 3: Run the game and verify**

```bash
godot --path . scenes/main.tscn
```

**Verify:**
1. Scene loads without errors in the console
2. Top-down camera shows the planet (brown sphere) at center, ship (blue box) to the right, target (yellow torus) to the left, fuel pickup (green box) behind the planet
3. Press W → front engine toggles on (no visible change yet until thrust)
4. Hold Space → thrust applies, exhaust meshes appear on active engines
5. Ship moves in the direction of the active engine's thrust
6. Activate left or right engine → ship gains angular momentum (spins)
7. Camera rotates with the ship
8. Ship drifts toward the planet over time (gravity)
9. Q/E adjusts gimbal (engine exhaust meshes may visually shift)
10. Flying into the planet at speed → crash → level restarts
11. Flying into the target → "All levels complete!" printed (only one level)
12. Flying through the fuel pickup → pickup disappears, fuel bar increases
13. R key restarts the level
14. Fuel bar decreases while thrusting, engines stop when fuel reaches zero

- [ ] **Step 4: Commit**

```bash
git add scripts/main.gd scenes/main.tscn
git commit -m "feat: add main scene with level loading, camera, HUD, and restart"
```

---

## Tuning Notes

These values are starting points — adjust in the editor after playtesting:

| Parameter | Location | Default | Effect |
|-----------|----------|---------|--------|
| Planet mass | `resources/planet_medium.tres` | 1000 | Stronger gravity pull |
| gravity_strength | `resources/planet_medium.tres` | 1.0 | Multiplier on ship gravity |
| max_range | `resources/planet_medium.tres` | 80.0 | Planet's gravity reach |
| Engine max_thrust | `scenes/engine.tscn` | 100.0 | How powerful engines are |
| Engine gimbal_range_deg | `scenes/engine.tscn` | 30.0 | How far engines can deflect |
| fuel_consumption_rate | `scenes/engine.tscn` | 10.0 | Fuel burn speed |
| Ship starting_fuel | level scene | 200.0 | Starting fuel amount |
| Ship crash_velocity | `scenes/ship.tscn` | 15.0 | Speed threshold for crash |
| Camera height | `scenes/camera_rig.tscn` | 60 | Zoom level |
| Side engine Z offset | `scenes/ship.tscn` MountLeft/MountRight | 0.3 | Torque from side engines |
