extends Control

@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _fuel_label: Label = %FuelLabel


func setup(ship: Ship) -> void:
	ship.fuel_changed.connect(_on_fuel_changed)
	_on_fuel_changed(ship.fuel, ship.max_fuel)


func _on_fuel_changed(current: float, maximum: float) -> void:
	_fuel_bar.max_value = maximum
	_fuel_bar.value = current
	_fuel_label.text = "Fuel: %d%%" % roundi(current / maximum * 100.0)
