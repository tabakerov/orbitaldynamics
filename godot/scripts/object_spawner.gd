@tool
class_name ObjectSpawner
extends Node3D

## Spawns configured objects (see SpawnEntry) inside a volume at per-entry
## rates. The game plays in the XZ plane, so all volumes are flat: positions
## and velocities have Y forced to zero.

signal object_spawned(object: Node3D)

enum VolumeShape {
	BOX,
	DISC,
	RING,
	## Spawn on gravity_source's current surface (radius + source_surface_margin),
	## at a random angle. Tracks a growing/shrinking body — e.g. objects
	## erupting from a black hole.
	AROUND_SOURCE,
}

@export var entries: Array[SpawnEntry] = []

@export var spawning_enabled: bool = true

@export_group("Volume")
@export var volume_shape: VolumeShape = VolumeShape.RING:
	set(value):
		volume_shape = value
		_refresh_editor_preview()
@export var box_size: Vector3 = Vector3(60, 0, 60):
	set(value):
		box_size = value
		_refresh_editor_preview()
@export var disc_radius: float = 30.0:
	set(value):
		disc_radius = maxf(value, 0.0)
		_refresh_editor_preview()
@export var ring_inner_radius: float = 40.0:
	set(value):
		ring_inner_radius = maxf(value, 0.0)
		_refresh_editor_preview()
@export var ring_outer_radius: float = 60.0:
	set(value):
		ring_outer_radius = maxf(value, 0.0)
		_refresh_editor_preview()

@export_group("Gravity Source")
## Body used for VolumeShape.AROUND_SOURCE and SpawnEntry.RadialSpeedMode.
## TURNAROUND_AT_RANGE launches. Its current body_data.mass/radius are read
## fresh at every spawn, so growth (e.g. a black hole absorbing mass) is
## tracked automatically.
@export var gravity_source: NodePath
## Spawn clearance above gravity_source's current radius (AROUND_SOURCE).
@export var source_surface_margin: float = 3.0

@export_group("Lifecycle")
## Spawned FloatingObjects are freed this far from the spawner (0 = keep
## each scene's own despawn settings).
@export var despawn_distance: float = 0.0
## Random seed (0 = new random sequence every run).
@export var seed_value: int = 0

@export_group("Editor")
## Show the spawn volume as a wireframe in the editor.
@export var preview_volume: bool = true:
	set(value):
		preview_volume = value
		_refresh_editor_preview()

const PREVIEW_SEGMENTS: int = 64

var _rng := RandomNumberGenerator.new()
var _next_spawn: Array[float] = []
var _alive: Array[Array] = []
var _preview_mesh: MeshInstance3D
var _gravity_source_body: CelestialBody


func _ready() -> void:
	_gravity_source_body = get_node_or_null(gravity_source) as CelestialBody
	if Engine.is_editor_hint():
		_refresh_editor_preview()
		return
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_reset_state()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	tick(delta)


## Advances spawn timers and spawns due objects. Public for tests.
func tick(delta: float) -> void:
	if not spawning_enabled:
		return
	if _next_spawn.size() != entries.size():
		_reset_state()
	for i in entries.size():
		var entry := entries[i]
		if not entry or not entry.scene:
			continue
		_next_spawn[i] -= delta
		while _next_spawn[i] <= 0.0:
			_try_spawn(i, entry)
			_next_spawn[i] += entry.pick_interval(_rng)


## Uniformly samples a spawn position in the volume, local to this node.
func sample_local_position() -> Vector3:
	match volume_shape:
		VolumeShape.BOX:
			return Vector3(
				_rng.randf_range(-0.5, 0.5) * box_size.x,
				0.0,
				_rng.randf_range(-0.5, 0.5) * box_size.z,
			)
		VolumeShape.DISC:
			var angle := _rng.randf_range(0.0, TAU)
			var radius := disc_radius * sqrt(_rng.randf())
			return Vector3(cos(angle), 0.0, sin(angle)) * radius
		VolumeShape.RING:
			var angle := _rng.randf_range(0.0, TAU)
			var inner := minf(ring_inner_radius, ring_outer_radius)
			var outer := maxf(ring_inner_radius, ring_outer_radius)
			var radius := sqrt(lerpf(inner * inner, outer * outer, _rng.randf()))
			return Vector3(cos(angle), 0.0, sin(angle)) * radius
		VolumeShape.AROUND_SOURCE:
			if not _gravity_source_body or not _gravity_source_body.body_data:
				return Vector3.ZERO
			var angle := _rng.randf_range(0.0, TAU)
			var radius := _gravity_source_body.body_data.radius + source_surface_margin
			var center := to_local(_gravity_source_body.global_position)
			return center + Vector3(cos(angle), 0.0, sin(angle)) * radius
	return Vector3.ZERO


## Outermost reach of the volume from the spawner origin (used by the minimap).
func get_volume_extent() -> float:
	match volume_shape:
		VolumeShape.BOX:
			return Vector2(box_size.x, box_size.z).length() * 0.5
		VolumeShape.DISC:
			return disc_radius
		VolumeShape.RING:
			return maxf(ring_inner_radius, ring_outer_radius)
		VolumeShape.AROUND_SOURCE:
			var extent := source_surface_margin
			if _gravity_source_body and _gravity_source_body.body_data:
				extent = maxf(extent, _gravity_source_body.body_data.radius + source_surface_margin)
			for entry in entries:
				if entry and entry.radial_speed_mode == SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE:
					extent = maxf(extent, maxf(entry.turnaround_distance_min, entry.turnaround_distance_max))
			return extent
	return 0.0


func _reset_state() -> void:
	_next_spawn.clear()
	_alive.clear()
	for entry in entries:
		_next_spawn.append(entry.pick_interval(_rng) if entry else INF)
		_alive.append([])


func _try_spawn(index: int, entry: SpawnEntry) -> void:
	# Untyped lambda parameter: freed instances fail typed-argument conversion.
	var alive: Array = _alive[index].filter(
		func(object) -> bool: return is_instance_valid(object)
	)
	_alive[index] = alive
	if entry.max_alive > 0 and alive.size() >= entry.max_alive:
		return
	var object := spawn_from_entry(entry)
	if object:
		alive.append(object)


func spawn_from_entry(entry: SpawnEntry) -> Node3D:
	var object := entry.scene.instantiate() as Node3D
	if not object:
		push_warning("SpawnEntry scene is not a Node3D: %s" % entry.scene.resource_path)
		return null

	var spawn_position := global_transform * sample_local_position()
	spawn_position.y = 0.0

	if object is FloatingObject:
		object.initial_velocity = _sample_velocity(entry, spawn_position)
		match entry.gravity_override:
			SpawnEntry.GravityOverride.OFF:
				object.gravity_affected = false
			SpawnEntry.GravityOverride.ON:
				object.gravity_affected = true
		if despawn_distance > 0.0:
			object.despawn_distance = despawn_distance
			object.despawn_center = global_position

	add_child(object)
	object.global_position = spawn_position
	object_spawned.emit(object)
	return object


func _sample_velocity(entry: SpawnEntry, spawn_position: Vector3) -> Vector3:
	var velocity := entry.initial_velocity + Vector3(
		_rng.randf_range(-entry.velocity_jitter.x, entry.velocity_jitter.x),
		0.0,
		_rng.randf_range(-entry.velocity_jitter.z, entry.velocity_jitter.z),
	)
	velocity.y = 0.0
	if entry.velocity_frame == SpawnEntry.VelocityFrame.RADIAL:
		var outward := spawn_position - global_position
		outward.y = 0.0
		if outward.length_squared() < 0.000001:
			outward = Vector3.RIGHT
		outward = outward.normalized()
		var tangent := Vector3(outward.z, 0.0, -outward.x)
		var radial_speed := velocity.x
		if entry.radial_speed_mode == SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE:
			radial_speed = _compute_turnaround_speed(entry, spawn_position)
		velocity = outward * radial_speed + tangent * velocity.z
	return velocity


## Outward speed so a purely radial object decelerates under gravity_source's
## current gravity (mu = gravity_strength * mass) and turns around at a
## random distance in [turnaround_distance_min, turnaround_distance_max],
## derived from energy conservation for a power-law field g(r) = mu / r^n.
## Assumes gravity_source dominates the local field at the spawn point
## (true when it is the only nearby body, e.g. a lone black hole).
func _compute_turnaround_speed(entry: SpawnEntry, spawn_position: Vector3) -> float:
	if not _gravity_source_body or not _gravity_source_body.body_data:
		return 0.0
	var data := _gravity_source_body.body_data
	var mu := data.gravity_strength * data.mass
	var r0 := spawn_position.distance_to(_gravity_source_body.global_position)
	if mu <= 0.0 or r0 <= 0.0:
		return 0.0
	var r_target := _rng.randf_range(
		minf(entry.turnaround_distance_min, entry.turnaround_distance_max),
		maxf(entry.turnaround_distance_min, entry.turnaround_distance_max),
	)
	if r_target <= r0:
		return 0.0

	var n := data.falloff_exponent
	var energy_gap: float
	if absf(n - 1.0) < 0.001:
		energy_gap = mu * log(r_target / r0)
	else:
		var exponent := n - 1.0
		energy_gap = mu / exponent * (1.0 / pow(r0, exponent) - 1.0 / pow(r_target, exponent))
	return sqrt(maxf(energy_gap * 2.0, 0.0))


func _refresh_editor_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if not preview_volume:
		if _preview_mesh:
			_preview_mesh.queue_free()
			_preview_mesh = null
		return
	if not _preview_mesh:
		_preview_mesh = MeshInstance3D.new()
		_preview_mesh.name = "SpawnVolumePreview"
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.35, 0.85, 1.0, 0.9)
		_preview_mesh.material_override = material
		add_child(_preview_mesh)
	_preview_mesh.mesh = _build_preview_mesh()


func _build_preview_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	match volume_shape:
		VolumeShape.BOX:
			var hx := box_size.x * 0.5
			var hz := box_size.z * 0.5
			var corners := [
				Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz),
				Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
			]
			for i in corners.size():
				mesh.surface_add_vertex(corners[i])
				mesh.surface_add_vertex(corners[(i + 1) % corners.size()])
		VolumeShape.DISC:
			_add_preview_circle(mesh, disc_radius)
		VolumeShape.RING:
			_add_preview_circle(mesh, ring_inner_radius)
			_add_preview_circle(mesh, ring_outer_radius)
		VolumeShape.AROUND_SOURCE:
			if _gravity_source_body and _gravity_source_body.body_data:
				_add_preview_circle(mesh, _gravity_source_body.body_data.radius + source_surface_margin)
	mesh.surface_end()
	return mesh


func _add_preview_circle(mesh: ImmediateMesh, radius: float) -> void:
	for i in PREVIEW_SEGMENTS:
		var a := TAU * float(i) / PREVIEW_SEGMENTS
		var b := TAU * float(i + 1) / PREVIEW_SEGMENTS
		mesh.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)) * radius)
		mesh.surface_add_vertex(Vector3(cos(b), 0.0, sin(b)) * radius)
