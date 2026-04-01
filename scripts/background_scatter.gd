class_name BackgroundScatter
extends Node3D

## Scatter entries — each defines a mesh type and its distribution params.
@export var entries: Array[ScatterEntry] = []

## Size of the scatter volume (centered on this node).
@export var volume_size: Vector3 = Vector3(200, 50, 200)

## Random seed. Same seed + same params = same result.
@export var seed_value: int = 0

## Offset the volume center relative to this node.
@export var volume_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(name)

	for entry in entries:
		if entry == null or entry.mesh == null:
			continue
		_create_multimesh(entry, rng)


func _create_multimesh(entry: ScatterEntry, rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = entry.mesh
	mm.instance_count = entry.count

	var half := volume_size * 0.5

	for i in entry.count:
		var pos := Vector3(
			rng.randf_range(-half.x, half.x),
			rng.randf_range(-half.y, half.y),
			rng.randf_range(-half.z, half.z),
		) + volume_offset

		var scl := rng.randf_range(entry.scale_min, entry.scale_max)

		var basis := Basis.IDENTITY
		if entry.random_rotation:
			if entry.random_rotation_y_only:
				basis = Basis(Vector3.UP, rng.randf_range(0, TAU))
			else:
				basis = Basis(
					Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
					rng.randf_range(0, TAU),
				)
		basis = basis.scaled(Vector3(scl, scl, scl))

		mm.set_instance_transform(i, Transform3D(basis, pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if entry.material_override:
		mmi.material_override = entry.material_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
