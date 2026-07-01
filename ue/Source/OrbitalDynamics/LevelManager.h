#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "LevelManager.generated.h"

class ACelestialBody;
class ADebugFlightVisualizer;
class AShip;

DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnLevelCompleted);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnLevelShipCrashed, FVector, CrashPosition);

// Port of godot/scripts/level.gd (sim bootstrap + wiring part; the intro/overlay
// flow arrives with the game flow pass). One per map; the game mode spawns one
// automatically if the map has none.
UCLASS()
class ORBITALDYNAMICS_API ALevelManager : public AActor
{
	GENERATED_BODY()

public:
	ALevelManager();

	UPROPERTY(BlueprintAssignable, Category = "Level")
	FOnLevelCompleted OnLevelCompleted;

	UPROPERTY(BlueprintAssignable, Category = "Level")
	FOnLevelShipCrashed OnShipCrashed;

	UPROPERTY(EditAnywhere, Category = "Level|Debug")
	bool bDebugVisualsEnabled = false;

	AShip* GetShip() const { return ShipPtr.Get(); }

	UPROPERTY()
	TArray<TObjectPtr<ACelestialBody>> CelestialBodies;

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

protected:
	UFUNCTION()
	void HandleTargetReached();

	UFUNCTION()
	void HandleShipCrashed(FVector CrashPosition);

private:
	void InitCelestialSim();
	// The player pawn spawns after level actors BeginPlay, so ship wiring
	// (crash delegate, debug visualizer) is deferred to the first ticks.
	void TryBindShip();

	TWeakObjectPtr<AShip> ShipPtr;
	TWeakObjectPtr<ADebugFlightVisualizer> Visualizer;
	bool bShipBound = false;
	bool bCompleted = false;
};
