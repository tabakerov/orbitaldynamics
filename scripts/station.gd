class_name Station
extends Area3D

@export var profile: StationProfile

signal ship_entered_range(ship: Ship)
signal ship_exited_range(ship: Ship)

@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if profile and _collision and _collision.shape is SphereShape3D:
		(_collision.shape as SphereShape3D).radius = profile.dock_radius


func _on_body_entered(body: Node) -> void:
	if body is Ship:
		ship_entered_range.emit(body)


func _on_body_exited(body: Node) -> void:
	if body is Ship:
		ship_exited_range.emit(body)


func get_available_modules() -> Array[ModuleProfile]:
	if profile:
		return profile.available_modules
	return []


func get_display_name() -> String:
	if profile:
		return profile.display_name
	return "Service Station"
