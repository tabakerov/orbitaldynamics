class_name EngineProfile
extends ModuleProfile

@export var max_thrust: float = 100.0
@export var fuel_consumption_rate: float = 10.0
@export var dry_mass: float = 0.0
## How long the engine takes to answer the trigger, as the time constant of an
## exponential approach: after `spool_up_time` seconds it has covered 63% of
## the gap, after three times that it is there. A time constant rather than a
## fixed rate on purpose — the lag is then the same whether the pilot asks for
## a nudge or for full power, so small corrections feel as heavy as big ones.
## Spooling down is quicker than spooling up, the way a throttled engine
## behaves.
@export var spool_up_time: float = 0.4
@export var spool_down_time: float = 0.28
