class_name CameraRig
extends Node3D

var target: Node3D

var _active_index: int = 0

@onready var _cameras: Array[Camera3D] = [$Camera3D, $ChaseCamera]


func _ready() -> void:
	_cameras[_active_index].current = true


func set_target(node: Node3D) -> void:
	target = node
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y


func get_camera() -> Camera3D:
	return _cameras[_active_index]


func get_cameras() -> Array[Camera3D]:
	return _cameras


func toggle_camera() -> void:
	_active_index = (_active_index + 1) % _cameras.size()
	_cameras[_active_index].current = true


func _physics_process(_delta: float) -> void:
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y
