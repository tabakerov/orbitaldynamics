#include "OrbitalDynamicsGameMode.h"

#include "EngineUtils.h"
#include "LevelManager.h"
#include "Ship.h"

AOrbitalDynamicsGameMode::AOrbitalDynamicsGameMode()
{
	DefaultPawnClass = AShip::StaticClass();
}

void AOrbitalDynamicsGameMode::InitGame(const FString& MapName, const FString& Options, FString& ErrorMessage)
{
	Super::InitGame(MapName, Options, ErrorMessage);

	// Every map needs exactly one level manager; spawn one for maps that
	// don't place it explicitly.
	TActorIterator<ALevelManager> It(GetWorld());
	if (!It)
	{
		GetWorld()->SpawnActor<ALevelManager>();
	}
}
