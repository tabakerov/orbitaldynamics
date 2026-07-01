class_name FuelPickup
extends Area3D

@export var fuel_amount: float = 50.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Ship:
		body.fuel = minf(body.fuel + fuel_amount, body.max_fuel)
		body.fuel_changed.emit(body.fuel, body.max_fuel)
		queue_free()
