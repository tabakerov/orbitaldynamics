class_name CameraRig
extends Node3D

var target: Node3D


func _physics_process(_delta: float) -> void:
	if target:
		global_position.x = target.global_position.x
		global_position.z = target.global_position.z
		rotation.y = target.rotation.y
