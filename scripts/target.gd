class_name Target
extends Area3D

signal target_reached


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Ship:
		target_reached.emit()
