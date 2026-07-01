#include "LevelManager.h"

#include "CelestialBody.h"
#include "CelestialBodyData.h"
#include "CelestialSimSubsystem.h"
#include "DebugFlightVisualizer.h"
#include "EngineUtils.h"
#include "Ship.h"
#include "TargetZone.h"

ALevelManager::ALevelManager()
{
	PrimaryActorTick.bCanEverTick = true;
}

void ALevelManager::BeginPlay()
{
	Super::BeginPlay();

	InitCelestialSim();

	for (TActorIterator<ATargetZone> It(GetWorld()); It; ++It)
	{
		It->OnTargetReached.AddDynamic(this, &ALevelManager::HandleTargetReached);
	}
}

void ALevelManager::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (!bShipBound)
	{
		TryBindShip();
	}
}

void ALevelManager::InitCelestialSim()
{
	CelestialBodies.Reset();
	for (TActorIterator<ACelestialBody> It(GetWorld()); It; ++It)
	{
		CelestialBodies.Add(*It);
	}

	TArray<UCelestialBodyData*> Data;
	TArray<FVector> Positions;
	TArray<FVector> Velocities;
	TArray<bool> Stationary;

	for (int32 i = 0; i < CelestialBodies.Num(); ++i)
	{
		ACelestialBody* Body = CelestialBodies[i];
		Data.Add(Body->BodyData);
		Positions.Add(Body->GetActorLocation());
		Velocities.Add(Body->InitialVelocity);
		Stationary.Add(Body->bStationary);
		Body->SimIndex = i;
	}

	if (UCelestialSimSubsystem* Sim = GetGameInstance()->GetSubsystem<UCelestialSimSubsystem>())
	{
		Sim->InitializeBodies(Data, Positions, Velocities, Stationary);
	}
}

void ALevelManager::TryBindShip()
{
	TActorIterator<AShip> It(GetWorld());
	if (It)
	{
		ShipPtr = *It;
	}
	if (!ShipPtr.IsValid())
	{
		return;
	}
	bShipBound = true;

	ShipPtr->OnCrashed.AddDynamic(this, &ALevelManager::HandleShipCrashed);

	ADebugFlightVisualizer* Viz = GetWorld()->SpawnActor<ADebugFlightVisualizer>();
	Viz->Ship = ShipPtr;
	Viz->CelestialBodies = CelestialBodies;
	Viz->SetEnabled(bDebugVisualsEnabled);
	Visualizer = Viz;
}

void ALevelManager::HandleTargetReached()
{
	if (bCompleted)
	{
		return;
	}
	bCompleted = true;
	UE_LOG(LogTemp, Display, TEXT("Level completed"));
	OnLevelCompleted.Broadcast();
}

void ALevelManager::HandleShipCrashed(FVector CrashPosition)
{
	UE_LOG(LogTemp, Display, TEXT("Ship crashed at %s"), *CrashPosition.ToString());
	OnShipCrashed.Broadcast(CrashPosition);
}
