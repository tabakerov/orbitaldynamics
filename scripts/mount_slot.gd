class_name MountSlot
extends Resource

enum Binding { FRONT, REAR, LEFT, RIGHT }

@export var binding: Binding = Binding.FRONT
@export var transform: Transform3D = Transform3D.IDENTITY


static func binding_name(b: int) -> String:
	match b:
		Binding.FRONT: return "front"
		Binding.REAR: return "rear"
		Binding.LEFT: return "left"
		Binding.RIGHT: return "right"
	return ""
