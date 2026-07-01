#pragma once

#include "CoreMinimal.h"
#include "ShipModule.h"
#include "EngineModule.generated.h"

class UStaticMeshComponent;

// Port of godot/scripts/engine.gd. Thrust pushes along -forward and is scaled
// by the ship-assigned FuelSupplyRatio, so engines fade out as fuel runs dry.
UCLASS()
class ORBITALDYNAMICS_API AEngineModule : public AShipModule
{
	GENERATED_BODY()

public:
	AEngineModule();

	// Gimbal angle in radians around the ship's up axis (Godot math kept verbatim;
	// the sign is flipped once when applied as UE yaw — see ApplyGimbalDelta).
	float GimbalAngle = 0.0f;

	virtual float GetMass() const override;
	virtual void PhysicsTick(float Delta) override;
	virtual FVector GetThrustVector() const override;
	virtual float GetRequestedFuelDrain(float Delta) const override;
	virtual float GetFuelDrain(float Delta) const override;
	virtual void ApplyGimbalDelta(float Delta) override;

	// Visual-layer hook (exhaust/particles are out of scope for now).
	bool IsThrusting() const;

protected:
	virtual void Configure() override;

	UPROPERTY(VisibleAnywhere, Category = "Engine")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;

	UPROPERTY(VisibleAnywhere, Category = "Engine")
	TObjectPtr<UStaticMeshComponent> ExhaustMesh;

private:
	bool HasEffectiveFuelSupply() const;
	void ApplyGimbalRotation();

	float GimbalRangeRad = FMath::DegreesToRadians(30.0f);
};
