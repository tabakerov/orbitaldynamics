#pragma once

#include "CoreMinimal.h"
#include "Engine/GameInstance.h"
#include "OrbitalGameInstance.generated.h"

// Level list + current index, surviving OpenLevel transitions.
// Port of the level-flow part of godot/scripts/main.gd; the overlay flow
// itself lives in AOrbitalPlayerController.
UCLASS(Config = Game)
class ORBITALDYNAMICS_API UOrbitalGameInstance : public UGameInstance
{
	GENERATED_BODY()

public:
	// Map names in play order; configured in DefaultGame.ini
	// ([/Script/OrbitalDynamics.OrbitalGameInstance] +LevelMapNames=...).
	UPROPERTY(Config)
	TArray<FString> LevelMapNames;

	int32 CurrentLevelIndex = 0;

	int32 GetLevelCount() const { return LevelMapNames.Num(); }
	bool HasNextLevel() const { return CurrentLevelIndex + 1 < LevelMapNames.Num(); }

	void LoadLevel(const UObject* WorldContext, int32 Index);
	void RestartLevel(const UObject* WorldContext);
	void LoadNextLevel(const UObject* WorldContext);
};
