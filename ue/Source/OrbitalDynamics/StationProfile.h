#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "StationProfile.generated.h"

class UModuleProfile;

// Port of godot/scripts/station_profile.gd + resources/stations/full_service.tres.
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UStationProfile : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Station")
	FText DisplayName = NSLOCTEXT("OrbitalDynamics", "ServiceStation", "Service Station");

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Station")
	TArray<TObjectPtr<UModuleProfile>> AvailableModules;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Station")
	float DockRadius = 8.0f;
};
