class_name BonusStar
extends FloatingObject

## Score bonus pickup shaped like a flat five-pointed star.

const STAR_POINTS: int = 5
const OUTER_RADIUS: float = 1.0
const INNER_RADIUS: float = 0.42

## Visual spin around Y, degrees per second.
@export var spin_speed: float = 60.0


func _ready() -> void:
	super()
	var mesh_instance := $MeshInstance3D as MeshInstance3D
	if mesh_instance and not mesh_instance.mesh:
		mesh_instance.mesh = _build_star_mesh()


func _process(delta: float) -> void:
	var mesh_instance := $MeshInstance3D as MeshInstance3D
	if mesh_instance:
		mesh_instance.rotate_y(deg_to_rad(spin_speed) * delta)


func _on_ship_contact(_ship: Ship) -> void:
	collected.emit(self)
	queue_free()


func _build_star_mesh() -> ArrayMesh:
	var rim := PackedVector3Array()
	for i in STAR_POINTS * 2:
		var radius := OUTER_RADIUS if i % 2 == 0 else INNER_RADIUS
		var angle := TAU * float(i) / float(STAR_POINTS * 2)
		rim.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))

	# Fan of triangles around the center; the material is unshaded and
	# double-sided, so winding does not matter.
	var vertices := PackedVector3Array()
	for i in rim.size():
		vertices.append(Vector3.ZERO)
		vertices.append(rim[i])
		vertices.append(rim[(i + 1) % rim.size()])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
