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

	// Intro overlay settings (port of level.gd @export Intro group).
	UPROPERTY(EditAnywhere, Category = "Level|Intro", meta = (MultiLine = true))
	FText IntroMessage;

	// 0 = wait for the continue button; > 0 = auto-continue after this many seconds.
	UPROPERTY(EditAnywhere, Category = "Level|Intro", meta = (ClampMin = 0))
	float IntroTimeoutSeconds = 0.0f;

	UPROPERTY(EditAnywhere, Category = "Level|Intro")
	bool bIntroShowContinueButton = true;

	UPROPERTY(EditAnywhere, Category = "Level|Intro")
	FText IntroContinueButtonText;

	UPROPERTY(EditAnywhere, Category = "Level|Debug")
	bool bDebugVisualsEnabled = false;

	// Blueprint subclasses point this at BP_DebugFlightVisualizer.
	UPROPERTY(EditDefaultsOnly, Category = "Level|Debug")
	TSubclassOf<ADebugFlightVisualizer> VisualizerClass;

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
