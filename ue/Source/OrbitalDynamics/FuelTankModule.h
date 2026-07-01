#pragma once

#include "CoreMinimal.h"
#include "ShipModule.h"
#include "FuelTankModule.generated.h"

class UStaticMeshComponent;

// Port of godot/scripts/external_fuel_tank_module.gd. Pumps fuel into the
// ship's internal tank only while its mount button is held with thrust applied.
UCLASS()
class ORBITALDYNAMICS_API AFuelTankModule : public AShipModule
{
	GENERATED_BODY()

public:
	AFuelTankModule();

	float CurrentFuel = 0.0f;

	virtual float GetMass() const override;
	virtual float GetPotentialFuelIntake(float Delta) const override;
	virtual void CommitFuelIntake(float Amount) override;

protected:
	virtual void Configure() override;

	UPROPERTY(VisibleAnywhere, Category = "FuelTank")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;
};
