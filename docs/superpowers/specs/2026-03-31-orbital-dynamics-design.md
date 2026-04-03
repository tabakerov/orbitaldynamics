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
├── WorldEnvironment — procedural sky + ambient light
├── CelestialSimulation (Node) — autoload singleton
├── Level (Node3D) — loaded at runtime
│   ├── CelestialBody (AnimatableBody3D) — visual + static collision, position driven by sim
│   ├── FuelPickup (Area3D)
│   └── Target (Area3D)
├── Ship (RigidBody3D)
│   ├── Hull (MeshInstance3D + CollisionShape3D)
│   ├── MountFront (Node3D) — engine mount, rotated 180° so exhaust points forward
│   ├── MountRear (Node3D) — engine mount, no rotation, exhaust points backward
│   ├── MountLeft (Node3D) — engine mount, exhaust points left
│   └── MountRight (Node3D) — engine mount, exhaust points right
├── CameraRig (Node3D)
│   └── Camera3D
├── CanvasLayer
│   └── HUD (Control)
├── MenuLayer (CanvasLayer, process_mode=ALWAYS)
│   └── LevelSelect (Control) — level select / pause menu
└── DirectionalLight3D
```

## Ship System

### Hull
- RigidBody3D with mass and collision shape.
- Defines up to 4 mount points, each with: position offset from origin, base thrust direction, and slot name (front/rear/left/right).
- Center of mass is a hull property. Different hulls could shift it; cargo will shift it in later iterations.
- Engine mounts are oriented so exhaust points AWAY from the ship (physically correct thrust).

### Engines
- Each engine is a scene instanced at a mount point at level load.
- Class name: `ShipEngine` (avoids conflict with Godot's built-in `Engine` singleton).
- Properties (configured per engine):
  - `max_thrust`: maximum force output
  - `gimbal_range_deg`: max deflection angle in degrees
  - `fuel_consumption_rate`: fuel units per second at full thrust
- Runtime state:
  - `active`: bool — true while face button / WASD is held
  - `gimbal_angle`: float — per-engine, adjusted by stick rotation delta or Q/E
  - `thrust_magnitude`: 0.0–1.0 float — from analog trigger / Space (binary 1.0)
- Force applied per engine per tick: engine's `-global_transform.basis.z * max_thrust * thrust_magnitude`, applied at the engine's global position. Torque emerges naturally from off-center force application.
- The engine node visually rotates to match gimbal_angle (`rotation.y`).
- Levels may equip fewer than 4 engines. Some levels may have only 1.

### Engine Visual Indicators
- **Active light**: Red OmniLight3D (range 3, energy 0.5) at the mount point. On when engine is active, off when inactive.
- **Exhaust mesh**: Small orange emissive box, visible only when active AND thrusting.
- **Exhaust particles**: GPUParticles3D with billboard quads, orange-to-transparent gradient. Emits along +Z local (exhaust direction) only when active AND thrusting. Particles use `PARTICLE_BILLBOARD` mode to always face the camera.

### Fuel
- Single shared fuel tank on the ship, initialized per level.
- Each active engine drains `fuel_consumption_rate * thrust_magnitude * delta` per tick.
- At zero fuel, engines produce no thrust. Player can still drift.
- Fuel pickups (Area3D) restore fuel on overlap.

## Controls

### Controller
- **A/B/X/Y (face buttons)**: Hold to activate individual engines. Release to deactivate. Mapping: Y=front, A=rear, X=left, B=right (matches spatial position on controller).
- **Right trigger (analog)**: Thrust magnitude for all active engines (0.0–1.0).
- **Left thumbstick rotation**: Gimbal active engines. The angular velocity of the stick rotation is applied as a delta to each active engine's gimbal angle. Inactive engines keep their last angle. Releasing the stick preserves the current gimbal position.

### Keyboard
- **W/A/S/D**: Hold to activate individual engines (W=front, S=rear, A=left, D=right). Release to deactivate.
- **Space**: Thrust (binary, applies 1.0 magnitude to all active engines).
- **Q/E**: Gimbal rotation — Q rotates CCW, E rotates CW. Incremental delta applied to active engines.

### Menu Controls
- **Escape / B (gamepad)**: Toggle pause menu from gameplay.
- **Arrow keys / D-pad**: Navigate menu buttons.
- **Enter / A (gamepad)**: Confirm menu selection.
- **R / Start**: Quick restart level (bypasses menu).

## Celestial Simulation

### Integrator
- Symplectic Euler, running in `_physics_process` at Godot's fixed timestep (default 60Hz).
- Can substep internally if stability requires it for close encounters.
- Autoload singleton registered as `CelestialSim` (no `class_name` to avoid autoload naming conflict).

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
```

### Visual Representation
- Each celestial body has a corresponding AnimatableBody3D scene with MeshInstance3D (visual) and static CollisionShape3D (for crash detection).
- Position is set from the simulation each frame. These nodes have no Godot physics bodies — position is driven directly.

## Movement Plane Constraint
- All physics occur on the Y=0 plane (X/Z movement).
- Ship RigidBody3D is locked on Y axis and locked on X/Z rotation.
- Only Y-axis rotation is free (spin/yaw).

## Camera

### CameraRig (Node3D)
- Position: follows ship X/Z position. Snaps immediately on level load via `set_target()`.
- Rotation: matches ship's Y-axis rotation. Ship always appears to face "up" on screen; the world rotates around the player.
- Fully automatic — no player camera control.

### Camera3D
- Points straight down (-Y), rotated -90° around X axis.
- Fixed height above the plane (60 units).
- Perspective projection, fov configurable (default ~78°).
- Explicitly set as `current` in `_ready()`.

## Level Structure

### Level Definition (one scene per level)
- Celestial body initial conditions: position, velocity, mass, tunable gravity params.
- Black holes: same gravity as planets, with gravitational lensing visual effect.
- Ship spawn: position, rotation, equipped engines (which slots filled), starting fuel.
- Target: Area3D at a position.
- Fuel pickups: Area3D nodes with fuel amount.
- BackgroundScatter: procedural background decoration (rocks, stars, debris).
- Later iteration: cargo pickup + delivery points.

### Win Condition
- Ship overlaps Target Area3D → level complete.

### Lose Conditions
- Collide with celestial body at high velocity → crash → level auto-restarts.
- Out of fuel with no pickups remaining (soft fail — player drifts, can restart).

### Level Flow
1. Player selects level from menu → level loads → celestial sim initializes → ship spawns.
2. Player has control.
3. On win → advance to next level, or return to menu if last level.
4. On crash → level auto-restarts.
5. Player can manually restart at any time (R / Start, or via pause menu).

## Main Menu / Level Select

- Shown on game launch and when pressing Escape during gameplay.
- Dark background with title "ORBITAL DYNAMICS" and subtitle.
- Level buttons generated dynamically from the `levels` array ("Level 1", "Level 2", etc.).
- **Restart Level** button appears when a level is active (auto-focused).
- **Quit** button exits the game.
- Game is paused while menu is visible. MenuLayer uses `process_mode=ALWAYS` to handle input during pause.
- Gamepad navigation supported via focus system. A button / Enter confirms selection via explicit `_process` input check (Godot's built-in `ui_accept` doesn't fire for joypad when custom actions use the same button).

## Black Holes

Black holes extend CelestialBody — identical gravity behavior, different visuals.

### Visual Effect
- PlaneMesh at the black hole position with a spatial shader (`black_hole.gdshader`).
- Shader samples `hint_screen_texture` and applies radial UV distortion (gravitational lensing).
- Chromatic aberration: RGB channels displaced differently near center.
- Dark event horizon at center.
- Glowing accretion ring (configurable color, intensity, size).
- Edge fade for seamless blending with surroundings.

### Configurable Parameters (ShaderMaterial)
- `distortion`: lensing strength
- `horizon_size`: event horizon radius
- `ring_size`, `ring_color`, `ring_intensity`: accretion disk appearance
- `edge_fade_start`: where the effect begins to fade

### Scene Structure
```
BlackHole (AnimatableBody3D)
├── CollisionShape3D (SphereShape3D)
└── LensingMesh (MeshInstance3D + PlaneMesh + lensing shader)
```

## Background Scatter

Procedural background decoration system using MultiMeshInstance3D for performance.

### BackgroundScatter (Node3D)
- `entries: Array[ScatterEntry]` — list of object types to scatter
- `volume_size: Vector3` — scatter volume (centered on node)
- `volume_offset: Vector3` — offset the volume center
- `seed_value: int` — RNG seed for reproducibility (0 = hash of node name)

### ScatterEntry (Resource)
- `mesh: Mesh` — mesh to scatter
- `material_override: Material` — optional material
- `count: int` — number of instances
- `scale_min / scale_max: float` — random scale range
- `random_rotation: bool` — randomize orientation
- `random_rotation_y_only: bool` — only rotate around Y axis

Shadows disabled on scatter instances for performance.

## Environment

- WorldEnvironment with ProceduralSkyMaterial for background.
- Ambient light (energy 0.5, color 0.3/0.3/0.35) for base visibility.
- DirectionalLight3D pointing down (energy 1.5) for main illumination.

## Tools

### Orbit Planner (`tools/orbit-planner.html`)
- Browser-based interactive tool for testing celestial body configurations.
- Same symplectic Euler integrator as the game.
- Drag bodies to reposition, Shift+drag to set velocity vectors.
- Orbital path preview with configurable steps/dt.
- Ship spawn marker showing gravity drift.
- Export to Godot scene snippet format.

## Out of Scope (First Iteration)
- Cargo pickup and delivery
- Multiple hull types
- Sound / music
- Time warp / trajectory prediction
- Deterministic replay
