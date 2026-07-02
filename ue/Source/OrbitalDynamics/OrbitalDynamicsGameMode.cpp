#include "OrbitalDynamicsGameMode.h"

#include "CameraRig.h"
#include "EngineUtils.h"
#include "LevelManager.h"
#include "OrbitalPlayerController.h"
#include "Ship.h"

AOrbitalDynamicsGameMode::AOrbitalDynamicsGameMode()
{
	DefaultPawnClass = AShip::StaticClass();
	PlayerControllerClass = AOrbitalPlayerController::StaticClass();
	LevelManagerClass = ALevelManager::StaticClass();
	CameraRigClass = ACameraRig::StaticClass();
}

void AOrbitalDynamicsGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);

	// Every map needs exactly one level manager and one camera rig; spawn
	// them for maps that don't place them explicitly.
	TActorIterator<ALevelManager> It(GetWorld());
	if (!It && LevelManagerClass)
	{
		GetWorld()->SpawnActor<ALevelManager>(LevelManagerClass);
	}
	TActorIterator<ACameraRig> CameraIt(GetWorld());
	if (!CameraIt && CameraRigClass)
	{
		GetWorld()->SpawnActor<ACameraRig>(CameraRigClass);
	}
}

APawn* AOrbitalDynamicsGameMode::SpawnDefaultPawnAtTransform_Implementation(AController* NewPlayer,
                                                                            const FTransform& SpawnTransform)
{
	for (TActorIterator<AShip> It(GetWorld()); It; ++It)
	{
		if (!It->GetController())
		{
			return *It;
		}
	}
	return Super::SpawnDefaultPawnAtTransform_Implementation(NewPlayer, SpawnTransform);
}
