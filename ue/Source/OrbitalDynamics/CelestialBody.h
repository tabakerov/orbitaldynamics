#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "CelestialBody.generated.h"

class UCelestialBodyData;
class USphereComponent;
class UStaticMeshComponent;

// Port of godot/scripts/celestial_body.gd. The simulation owns the motion;
// this actor is a collision shell + placeholder visual that follows its sim entry.
UCLASS()
class ORBITALDYNAMICS_API ACelestialBody : public AActor
{
	GENERATED_BODY()

public:
	ACelestialBody();

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Celestial")
	TObjectPtr<UCelestialBodyData> BodyData;

	// Godot-plane converted: gameplay velocities live in the XY plane (Z = 0).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Celestial")
	FVector InitialVelocity = FVector::ZeroVector;

	// If true, the body stays fixed in place but still exerts gravity.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Celestial")
	bool bStationary = false;

	int32 SimIndex = -1;

	float GetBodyRadius() const;

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Celestial")
	TObjectPtr<USphereComponent> Collision;

	UPROPERTY(VisibleAnywhere, Category = "Celestial")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;

	void SetupVisuals();
};
