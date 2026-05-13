class_name FuelTankProfile
extends ModuleProfile

@export var capacity: float = 100.0
@export var dry_mass: float = 1.0
@export var max_pump_rate: float = 30.0
@export var starting_fill: float = 1.0  # 0..1 fraction of capacity at spawn
