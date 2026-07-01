class_name CelestialBody
extends AnimatableBody3D

@export var body_data: CelestialBodyData
@export var initial_velocity: Vector3 = Vector3.ZERO
## If true, this body stays fixed in place but still exerts gravity.
@export var stationary: bool = false

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
