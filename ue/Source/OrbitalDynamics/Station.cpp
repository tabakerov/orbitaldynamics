#include "Station.h"

#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "ModuleProfiles.h"
#include "Ship.h"
#include "StationProfile.h"
#include "UObject/ConstructorHelpers.h"

AStation::AStation()
{
	PrimaryActorTick.bCanEverTick = false;

	DockZone = CreateDefaultSubobject<USphereComponent>(TEXT("DockZone"));
	DockZone->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
	DockZone->SetGenerateOverlapEvents(true);
	DockZone->SetSphereRadius(8.0f);
	SetRootComponent(DockZone);

	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(DockZone);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	if (CylinderMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(CylinderMesh.Object);
	}
	PlaceholderMesh->SetRelativeScale3D(FVector(3.0, 3.0, 1.0));
}

void AStation::BeginPlay()
{
	Super::BeginPlay();
	if (Profile)
	{
		DockZone->SetSphereRadius(Profile->DockRadius);
	}
	DockZone->OnComponentBeginOverlap.AddDynamic(this, &AStation::OnZoneBeginOverlap);
	DockZone->OnComponentEndOverlap.AddDynamic(this, &AStation::OnZoneEndOverlap);
}

FText AStation::GetDisplayName() const
{
	if (Profile && !Profile->DisplayName.IsEmpty())
	{
		return Profile->DisplayName;
	}
	return NSLOCTEXT("OrbitalDynamics", "ServiceStation", "Service Station");
}

TArray<UModuleProfile*> AStation::GetAvailableModules() const
{
	TArray<UModuleProfile*> Result;
	if (Profile)
	{
		for (const TObjectPtr<UModuleProfile>& Module : Profile->AvailableModules)
		{
			Result.Add(Module);
		}
	}
	return Result;
}

void AStation::OnZoneBeginOverlap(UPrimitiveComponent*, AActor* OtherActor, UPrimitiveComponent*, int32, bool, const FHitResult&)
{
	if (AShip* Ship = Cast<AShip>(OtherActor))
	{
		OnShipEnteredRange.Broadcast(Ship, this);
	}
}

void AStation::OnZoneEndOverlap(UPrimitiveComponent*, AActor* OtherActor, UPrimitiveComponent*, int32)
{
	if (AShip* Ship = Cast<AShip>(OtherActor))
	{
		OnShipExitedRange.Broadcast(Ship, this);
	}
}
