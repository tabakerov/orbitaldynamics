#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "ModuleProfiles.generated.h"

class AShipModule;

// Port of godot/scripts/module_profile.gd and its subclasses.
UCLASS(Abstract, BlueprintType)
class ORBITALDYNAMICS_API UModuleProfile : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	// Actor class spawned into the mount slot (analog of Godot module_scene).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Module")
	TSubclassOf<AShipModule> ModuleClass;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Module")
	FText DisplayName;
};

// godot/resources/engines/engine_standard.tres: thrust 100, drain 10, gimbal 30, dry 0.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UEngineProfile : public UModuleProfile
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Engine")
	float MaxThrust = 100.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Engine")
	float FuelConsumptionRate = 10.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Engine")
	float GimbalRangeDeg = 30.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Engine")
	float DryMass = 0.0f;
};

// godot/resources/fuel_tanks/*.tres.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UFuelTankProfile : public UModuleProfile
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "FuelTank")
	float Capacity = 100.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "FuelTank")
	float DryMass = 1.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "FuelTank")
	float MaxPumpRate = 30.0f;

	// Fraction of capacity filled at spawn, 0..1.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "FuelTank", meta = (ClampMin = 0, ClampMax = 1))
	float StartingFill = 1.0f;
};

// godot/resources/cargo/*.tres. Pure ballast that shifts the center of mass.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UCargoProfile : public UModuleProfile
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Cargo")
	float Mass = 5.0f;
};
