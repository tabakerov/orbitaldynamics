class_name ShipLoadout
extends Resource

@export var hull: HullData
@export var starting_internal_fuel: float = 200.0
@export var front_module: ModuleProfile
@export var rear_module: ModuleProfile
@export var left_module: ModuleProfile
@export var right_module: ModuleProfile


func get_module(binding: int) -> ModuleProfile:
	match binding:
		MountSlot.Binding.FRONT: return front_module
		MountSlot.Binding.REAR: return rear_module
		MountSlot.Binding.LEFT: return left_module
		MountSlot.Binding.RIGHT: return right_module
	return null
