class_name BlackHole
extends CelestialBody

## Radius of the lensing effect mesh (visual only, not gravity).
@export var lensing_radius: float = 30.0


func _setup_visuals() -> void:
	# Collision from body_data
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = body_data.radius

	# Scale lensing plane to cover distortion area
	var lensing_mesh := $LensingMesh as MeshInstance3D
	var plane := lensing_mesh.mesh as PlaneMesh
	plane.size = Vector2(lensing_radius * 2.0, lensing_radius * 2.0)
