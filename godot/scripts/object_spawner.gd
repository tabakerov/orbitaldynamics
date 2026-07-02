@tool
class_name ObjectSpawner
extends Node3D

## Spawns configured objects (see SpawnEntry) inside a volume at per-entry
## rates. The game plays in the XZ plane, so all volumes are flat: positions
## and velocities have Y forced to zero.

signal object_spawned(object: Node3D)

enum VolumeShape { BOX, DISC, RING }

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


func _ready() -> void:
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
		velocity = outward * velocity.x + tangent * velocity.z
	return velocity


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
	mesh.surface_end()
	return mesh


func _add_preview_circle(mesh: ImmediateMesh, radius: float) -> void:
	for i in PREVIEW_SEGMENTS:
		var a := TAU * float(i) / PREVIEW_SEGMENTS
		var b := TAU * float(i + 1) / PREVIEW_SEGMENTS
		mesh.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)) * radius)
		mesh.surface_add_vertex(Vector3(cos(b), 0.0, sin(b)) * radius)
