#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "TargetZone.generated.h"

class USphereComponent;
class UStaticMeshComponent;

DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnTargetReached);

// Port of godot/scripts/target.gd: the level goal, an overlap trigger.
UCLASS()
class ORBITALDYNAMICS_API ATargetZone : public AActor
{
	GENERATED_BODY()

public:
	ATargetZone();

	UPROPERTY(BlueprintAssignable, Category = "Target")
	FOnTargetReached OnTargetReached;

	UPROPERTY(EditAnywhere, Category = "Target")
	float TriggerRadius = 2.0f;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Target")
	TObjectPtr<USphereComponent> Trigger;

	UPROPERTY(VisibleAnywhere, Category = "Target")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;

	UFUNCTION()
	void OnOverlap(UPrimitiveComponent* OverlappedComp, AActor* OtherActor,
	               UPrimitiveComponent* OtherComp, int32 OtherBodyIndex,
	               bool bFromSweep, const FHitResult& SweepResult);
};
