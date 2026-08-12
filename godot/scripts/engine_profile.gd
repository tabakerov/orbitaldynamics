class_name EngineProfile
extends ModuleProfile

@export var max_thrust: float = 100.0
@export var fuel_consumption_rate: float = 10.0
@export var dry_mass: float = 0.0
## How quickly the engine follows the trigger, in fractions of full thrust per
## second: 1.6 means idle → full takes 0.63 s. Spooling down is quicker than
## spooling up, the way a throttled engine behaves — the trigger sets the
## thrust the pilot wants, not the thrust the engine has.
@export var spool_up_rate: float = 1.6
@export var spool_down_rate: float = 2.6
