#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "OrbitalDynamicsGameMode.generated.h"

UCLASS()
class ORBITALDYNAMICS_API AOrbitalDynamicsGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AOrbitalDynamicsGameMode();

	virtual void InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage) override;
};
