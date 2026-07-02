#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Station.generated.h"

class AShip;
class UModuleProfile;
class USphereComponent;
class UStaticMeshComponent;
class UStationProfile;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FOnShipRangeChanged, AShip*, Ship, AStation*, Station);

// Port of godot/scripts/station.gd: a dock-radius trigger around a service
// station where the player can open the ship modifier screen.
UCLASS()
class ORBITALDYNAMICS_API AStation : public AActor
{
	GENERATED_BODY()

public:
	AStation();

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Station")
	TObjectPtr<UStationProfile> Profile;

	UPROPERTY(BlueprintAssignable, Category = "Station")
	FOnShipRangeChanged OnShipEnteredRange;

	UPROPERTY(BlueprintAssignable, Category = "Station")
	FOnShipRangeChanged OnShipExitedRange;

	FText GetDisplayName() const;
	TArray<UModuleProfile*> GetAvailableModules() const;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<USphereComponent> DockZone;

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;

	UFUNCTION()
	void OnZoneBeginOverlap(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
	                        UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
	                        bool bFromSweep, const FHitResult& SweepResult);

	UFUNCTION()
	void OnZoneEndOverlap(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
	                      UPrimitiveComponent* OtherComp, int32 OtherBodyIndex);
};
