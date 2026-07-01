class_name ExternalFuelTankModule
extends ShipModule

var current_fuel: float = 0.0

@onready var _active_light: OmniLight3D = $ActiveLight


func _configure() -> void:
	var fp := profile as FuelTankProfile
	if fp:
		current_fuel = fp.capacity * clampf(fp.starting_fill, 0.0, 1.0)


func _ready() -> void:
	if _active_light:
		_active_light.visible = false


func _process(_delta: float) -> void:
	if not _active_light:
		return
	_active_light.visible = active
	var pumping: bool = active and intensity > 0.0 and current_fuel > 0.0
	_active_light.light_energy = 0.3 + (0.9 * intensity if pumping else 0.0)


func get_mass() -> float:
	var fp := profile as FuelTankProfile
	if not fp:
		return 0.0
	return fp.dry_mass + current_fuel * Ship.FUEL_UNIT_MASS


func get_potential_fuel_intake(delta: float) -> float:
	if not active or intensity <= 0.0:
		return 0.0
	if current_fuel <= 0.0:
		return 0.0
	var fp := profile as FuelTankProfile
	if not fp:
		return 0.0
	return minf(fp.max_pump_rate * intensity * delta, current_fuel)


func commit_fuel_intake(amount: float) -> void:
	current_fuel = maxf(current_fuel - amount, 0.0)
