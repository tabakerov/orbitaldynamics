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
}

void AOrbitalDynamicsGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);

	// Every map needs exactly one level manager and one camera rig; spawn
	// them for maps that don't place them explicitly.
	TActorIterator<ALevelManager> It(GetWorld());
	if (!It)
	{
		GetWorld()->SpawnActor<ALevelManager>();
	}
	TActorIterator<ACameraRig> CameraIt(GetWorld());
	if (!CameraIt)
	{
		GetWorld()->SpawnActor<ACameraRig>();
	}
}
