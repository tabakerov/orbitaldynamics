class_name CargoModule
extends ShipModule


func get_mass() -> float:
	var cp := profile as CargoProfile
	return cp.mass if cp else 0.0
