class_name FuelPickup
extends FloatingObject

@export var fuel_amount: float = 50.0


func _on_ship_contact(ship: Ship) -> void:
	ship.fuel = minf(ship.fuel + fuel_amount, ship.max_fuel)
	ship.fuel_changed.emit(ship.fuel, ship.max_fuel)
	collected.emit(self)
	queue_free()
