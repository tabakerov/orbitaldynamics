#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "ShipTypes.h"
#include "ShipLoadout.generated.h"

class UHullData;
class UModuleProfile;

// Port of godot/scripts/ship_loadout.gd. The ship duplicates this asset at
// spawn so runtime module swaps never mutate the authored data.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UShipLoadout : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	TObjectPtr<UHullData> Hull;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	float StartingInternalFuel = 200.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	TObjectPtr<UModuleProfile> FrontModule;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	TObjectPtr<UModuleProfile> RearModule;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	TObjectPtr<UModuleProfile> LeftModule;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Loadout")
	TObjectPtr<UModuleProfile> RightModule;

	UModuleProfile* GetModule(EMountBinding Binding) const
	{
		switch (Binding)
		{
		case EMountBinding::Front: return FrontModule;
		case EMountBinding::Rear: return RearModule;
		case EMountBinding::Left: return LeftModule;
		case EMountBinding::Right: return RightModule;
		}
		return nullptr;
	}

	void SetModule(EMountBinding Binding, UModuleProfile* Profile)
	{
		switch (Binding)
		{
		case EMountBinding::Front: FrontModule = Profile; break;
		case EMountBinding::Rear: RearModule = Profile; break;
		case EMountBinding::Left: LeftModule = Profile; break;
		case EMountBinding::Right: RightModule = Profile; break;
		}
	}
};
