class_name CameraRig
extends Node3D

var target: Node3D

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.current = true


func set_target(node: Node3D) -> void:
	target = node
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y


func _physics_process(_delta: float) -> void:
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y
