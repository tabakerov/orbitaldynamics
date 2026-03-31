# Orbital Dynamics — Game Design Spec

## Overview

A spaceship navigation game built in Godot 4.6 with Jolt Physics. The player controls a modular ship with up to 4 gimbaling engines, navigating through gravitational fields created by celestial bodies in an N-body simulation. Movement is on a 2D plane in 3D space, viewed from a top-down camera that rotates with the ship.

## Architecture

Hybrid physics approach:
- **Custom celestial simulation** — N-body integrator (symplectic Euler) with tunable gravity parameters for level design flexibility.
- **Godot RigidBody3D + Jolt** — Ship physics, collisions, and force application. Gravity from the celestial sim is applied as an external force each tick.

### Scene Tree

```
Main (Node3D)
├── CelestialSimulation (Node) — autoload singleton
├── Level (Node3D)
│   ├── CelestialBody (Node3D) — visual + static collision, position driven by sim
│   ├── FuelPickup (Area3D)
│   └── Target (Area3D)
├── Ship (RigidBody3D)
│   ├── Hull (MeshInstance3D + CollisionShape3D)
│   ├── Engine_Front (Node3D) — mount point
│   ├── Engine_Rear (Node3D)
│   ├── Engine_Left (Node3D)
│   └── Engine_Right (Node3D)
└── CameraRig (Node3D)
    └── Camera3D
```

## Ship System

### Hull
- RigidBody3D with mass and collision shape.
- Defines up to 4 mount points, each with: position offset from origin, base thrust direction, and slot name (front/rear/left/right).
- Center of mass is a hull property. Different hulls could shift it; cargo will shift it in later iterations.

### Engines
- Each engine is a scene instanced at a mount point at level load.
- Properties (configured per engine):
  - `max_thrust`: maximum force output
  - `gimbal_range`: max deflection angle in degrees
  - `fuel_consumption_rate`: fuel units per second at full thrust
- Runtime state:
  - `active`: bool — toggled by face button / WASD
  - `gimbal_angle`: float — controlled by thumbstick rotation / Q/E
  - `thrust_magnitude`: 0.0–1.0 float — from analog trigger / Space (binary 1.0)
- Force applied per engine per tick: `thrust_direction.rotated(gimbal_angle) * max_thrust * thrust_magnitude`, applied at the engine's global position. Torque emerges naturally from off-center force application.
- Levels may equip fewer than 4 engines. Some levels may have only 1.

### Fuel
- Single shared fuel tank on the ship, initialized per level.
- Each active engine drains `fuel_consumption_rate * thrust_magnitude * delta` per tick.
- At zero fuel, engines produce no thrust. Player can still drift.
- Fuel pickups (Area3D) restore fuel on overlap.

## Controls

### Controller
- **A/B/X/Y (face buttons)**: Toggle individual engines on/off. Mapping: Y=front, A=rear, X=left, B=right (matches spatial position on controller: Y is top, A is bottom, X is left, B is right).
- **Right trigger (analog)**: Thrust magnitude for all active engines (0.0–1.0).
- **Left thumbstick rotation**: Gimbal all active engines simultaneously within their gimbal limits. Rotating the stick CCW rotates engines CCW, CW rotates CW.

### Keyboard
- **W/A/S/D**: Toggle individual engines on/off (W=front, S=rear, A=left, D=right).
- **Space**: Thrust (binary, applies 1.0 magnitude to all active engines).
- **Q/E**: Gimbal rotation — Q rotates CCW, E rotates CW. Incremental, not analog.

## Celestial Simulation

### Integrator
- Symplectic Euler, running in `_physics_process` at Godot's fixed timestep (default 60Hz).
- Can substep internally if stability requires it for close encounters.

### Celestial Body Properties
- `position`: Vector3 (X/Z plane, Y=0)
- `velocity`: Vector3
- `mass`: float — used for inter-body gravitational attraction
- Tunable gravity parameters (for ship/object attraction):
  - `gravity_strength`: multiplier on base gravitational pull
  - `falloff_exponent`: default 2.0 (inverse square law), tweakable per body
  - `max_range`: beyond this, body exerts no gravity on ship
  - `min_range`: clamps distance to prevent singularity

### Gravity Query
The celestial simulation provides a function to compute net gravity at any point:

```gdscript
func get_gravity_at(position: Vector3) -> Vector3:
    var total = Vector3.ZERO
    for body in celestial_bodies:
        var offset = body.position - position
        var dist = clamp(offset.length(), body.min_range, body.max_range)
        if offset.length() > body.max_range:
            continue
        var strength = body.gravity_strength * body.mass / pow(dist, body.falloff_exponent)
        total += offset.normalized() * strength
    return total
```

### Visual Representation
- Each celestial body has a corresponding Node3D scene with MeshInstance3D (visual) and static CollisionShape3D (for crash detection).
- Position is set from the simulation each frame. These nodes have no Godot physics bodies.

## Movement Plane Constraint
- All physics occur on the Y=0 plane (X/Z movement).
- Ship RigidBody3D is locked on Y axis and locked on X/Z rotation.
- Only Y-axis rotation is free (spin/yaw).

## Camera

### CameraRig (Node3D)
- Position: directly follows ship X/Z position (no smoothing initially).
- Rotation: matches ship's Y-axis rotation. Ship always appears to face "up" on screen; the world rotates around the player.
- Fully automatic — no player camera control.

### Camera3D
- Points straight down (-Y).
- Fixed height above the plane.
- Orthographic vs perspective and zoom behavior deferred to visual style pass.

## Level Structure

### Level Definition (one scene per level)
- Celestial body initial conditions: position, velocity, mass, tunable gravity params.
- Ship spawn: position, rotation, equipped engines (which slots filled), starting fuel.
- Target: Area3D at a position.
- Fuel pickups: Area3D nodes with fuel amount.
- Later iteration: cargo pickup + delivery points.

### Win Condition
- Ship overlaps Target Area3D → level complete.

### Lose Conditions
- Collide with celestial body at high velocity → crash.
- Out of fuel with no pickups remaining (soft fail — player drifts, can restart).

### Level Flow
1. Level loads → celestial sim initializes with body data → ship spawns.
2. Player has control.
3. On win → show result, advance.
4. On crash → offer restart.
5. Player can manually restart at any time.

## Out of Scope (First Iteration)
- Visual style / art direction
- Cargo pickup and delivery
- Multiple hull types
- Sound / music
- UI beyond basic HUD (fuel gauge, level indicator)
- Time warp / trajectory prediction
- Deterministic replay
