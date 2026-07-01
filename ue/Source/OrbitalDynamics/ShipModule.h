#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "ShipModule.generated.h"

class AShip;
class UModuleProfile;

// Port of godot/scripts/ship_module.gd. A module lives attached to a mount
// scene component on the ship; the ship drives its inputs every physics tick.
UCLASS(Abstract)
class ORBITALDYNAMICS_API AShipModule : public AActor
{
	GENERATED_BODY()

public:
	AShipModule();

	TWeakObjectPtr<AShip> Ship;

	UPROPERTY()
	TObjectPtr<UModuleProfile> Profile;

	// Driven by the ship each tick: mount button held / thrust axis value.
	bool bActive = false;
	float Intensity = 0.0f;
	// 1 = full fuel supply; <1 = throttled by the ship's fuel flow (see AShip).
	float FuelSupplyRatio = 1.0f;

	void Attach(AShip* InShip, UModuleProfile* InProfile);

	virtual float GetMass() const { return 0.0f; }
	virtual void PhysicsTick(float Delta) {}
	virtual FVector GetThrustVector() const { return FVector::ZeroVector; }
	virtual float GetRequestedFuelDrain(float Delta) const { return GetFuelDrain(Delta); }
	virtual float GetFuelDrain(float Delta) const { return 0.0f; }
	virtual float GetPotentialFuelIntake(float Delta) const { return 0.0f; }
	virtual void CommitFuelIntake(float Amount) {}
	virtual void ApplyGimbalDelta(float Delta) {}

protected:
	// Called from Attach once Ship and Profile are set.
	virtual void Configure() {}
};
