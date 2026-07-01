#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "CelestialBodyData.generated.h"

// Port of godot/scripts/celestial_body_data.gd. Units: meters (1 UU = 1 m), kg.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UCelestialBodyData : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float Mass = 1000.0f;

	// Multiplier for the gravity this body exerts on the ship (not on other bodies).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float GravityStrength = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float FalloffExponent = 2.0f;

	// Beyond this distance the body exerts no gravity on the ship.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float MaxRange = 80.0f;

	// Distance is clamped to this minimum when computing ship gravity.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float MinRange = 2.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Body")
	float Radius = 3.0f;
};
