@tool
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

## Show generated scatter in the editor without running the game.
@export var preview_in_editor: bool = true

const GENERATED_META: StringName = &"background_scatter_generated"

var _last_preview_signature: String = ""


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		call_deferred("_rebuild_preview_if_needed", true)


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild_preview_if_needed(true)
		return
	_rebuild_scatter(false)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		_clear_generated_scatter()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_preview_if_needed()


func _rebuild_preview_if_needed(force: bool = false) -> void:
	var signature := _get_preview_signature()
	if not force and signature == _last_preview_signature:
		return
	_last_preview_signature = signature
	_clear_generated_scatter()
	if preview_in_editor:
		_rebuild_scatter(true)


func _rebuild_scatter(editor_preview: bool) -> void:
	_clear_generated_scatter()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(name)

	for entry in entries:
		if entry == null or entry.mesh == null:
			continue
		_create_multimesh(entry, rng, editor_preview)


func _create_multimesh(entry: ScatterEntry, rng: RandomNumberGenerator, editor_preview: bool) -> void:
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
	mmi.name = "GeneratedScatter"
	mmi.set_meta(GENERATED_META, true)
	mmi.multimesh = mm
	# Background-only layer: rendered by BackgroundLayer's camera and warped
	# by the black hole's lensing; the gameplay camera doesn't see it.
	mmi.layers = BackgroundLayer.RENDER_LAYER_MASK
	if entry.material_override:
		mmi.material_override = entry.material_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if editor_preview:
		add_child(mmi, false, Node.INTERNAL_MODE_BACK)
	else:
		add_child(mmi)


func _clear_generated_scatter() -> void:
	for child in get_children(true):
		if child.get_meta(GENERATED_META, false):
			remove_child(child)
			child.queue_free()


func _get_preview_signature() -> String:
	var parts := PackedStringArray()
	parts.append(str(preview_in_editor))
	parts.append(str(volume_size))
	parts.append(str(seed_value))
	parts.append(str(volume_offset))
	parts.append(str(entries.size()))

	for entry in entries:
		if entry == null:
			parts.append("null")
			continue
		parts.append(str(entry.mesh.get_instance_id() if entry.mesh else 0))
		parts.append(str(entry.material_override.get_instance_id() if entry.material_override else 0))
		parts.append(str(entry.count))
		parts.append(str(entry.scale_min))
		parts.append(str(entry.scale_max))
		parts.append(str(entry.random_rotation))
		parts.append(str(entry.random_rotation_y_only))

	return "|".join(parts)
