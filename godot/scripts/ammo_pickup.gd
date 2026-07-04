class_name AmmoPickup
extends FloatingObject

## Weapon ammo crate. Collecting it switches the ship's gun to this ammo
## type and adds charges to it (see WeaponModule.add_ammo). A ship without
## a gun leaves the crate floating.

@export var ammo_type: WeaponProfile.AmmoType = WeaponProfile.AmmoType.LASER
@export var amount: int = 5


func _on_ship_contact(ship: Ship) -> void:
	if not ship.add_weapon_ammo(ammo_type, amount):
		return
	collected.emit(self)
	queue_free()
