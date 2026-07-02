#include "OrbitalGameInstance.h"

#include "Kismet/GameplayStatics.h"

void UOrbitalGameInstance::LoadLevel(const UObject* WorldContext, int32 Index)
{
	if (!LevelMapNames.IsValidIndex(Index))
	{
		return;
	}
	CurrentLevelIndex = Index;
	UGameplayStatics::SetGamePaused(WorldContext, false);
	UGameplayStatics::OpenLevel(WorldContext, FName(*LevelMapNames[Index]));
}

void UOrbitalGameInstance::RestartLevel(const UObject* WorldContext)
{
	UGameplayStatics::SetGamePaused(WorldContext, false);
	UGameplayStatics::OpenLevel(WorldContext, FName(*UGameplayStatics::GetCurrentLevelName(WorldContext)));
}

void UOrbitalGameInstance::LoadNextLevel(const UObject* WorldContext)
{
	if (HasNextLevel())
	{
		LoadLevel(WorldContext, CurrentLevelIndex + 1);
	}
}
