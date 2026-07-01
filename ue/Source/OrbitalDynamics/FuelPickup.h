#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "FuelPickup.generated.h"

class USphereComponent;
class UStaticMeshComponent;

// Port of godot/scripts/fuel_pickup.gd: +FuelAmount to the ship, then self-destroys.
UCLASS()
class ORBITALDYNAMICS_API AFuelPickup : public AActor
{
	GENERATED_BODY()

public:
	AFuelPickup();

	UPROPERTY(EditAnywhere, Category = "Fuel")
	float FuelAmount = 50.0f;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Fuel")
	TObjectPtr<USphereComponent> Trigger;

	UPROPERTY(VisibleAnywhere, Category = "Fuel")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
	               UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
	               bool bFromSweep, const FHitResult& SweepResult);
};
