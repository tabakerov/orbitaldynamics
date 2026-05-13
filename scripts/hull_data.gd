class_name HullData
extends Resource

@export var dry_mass: float = 10.0
@export var max_internal_fuel: float = 200.0
@export var mesh: Mesh
@export var collision_shape: Shape3D
@export var collision_transform: Transform3D = Transform3D.IDENTITY
@export var mounts: Array[MountSlot] = []


func get_mount(binding: int) -> MountSlot:
	for slot in mounts:
		if slot.binding == binding:
			return slot
	return null
