#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "OrbitalDynamicsGameMode.generated.h"

class ACameraRig;
class ALevelManager;

UCLASS()
class ORBITALDYNAMICS_API AOrbitalDynamicsGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AOrbitalDynamicsGameMode();

	// Classes used for the per-map auto-spawn; Blueprint subclasses of the
	// game mode point these at BP_LevelManager / BP_CameraRig.
	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Classes")
	TSubclassOf<ALevelManager> LevelManagerClass;

	UPROPERTY(EditDefaultsOnly, BlueprintReadOnly, Category = "Classes")
	TSubclassOf<ACameraRig> CameraRigClass;

	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;

	// Maps generated from the godot scenes place a fully-configured AShip
	// (loadout, starting fuel, spawn transform); possess it instead of
	// spawning a fresh default pawn.
	virtual APawn* SpawnDefaultPawnAtTransform_Implementation(AController* NewPlayer,
	                                                          const FTransform& SpawnTransform) override;
};
