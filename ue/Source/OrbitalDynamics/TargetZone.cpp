#include "TargetZone.h"

#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Ship.h"
#include "UObject/ConstructorHelpers.h"

ATargetZone::ATargetZone()
{
	PrimaryActorTick.bCanEverTick = false;

	Trigger = CreateDefaultSubobject<USphereComponent>(TEXT("Trigger"));
	Trigger->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
	Trigger->SetGenerateOverlapEvents(true);
	Trigger->SetSphereRadius(TriggerRadius);
	SetRootComponent(Trigger);

	// Placeholder for the yellow goal torus: a flattened cylinder ring.
	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(Trigger);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	if (CylinderMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(CylinderMesh.Object);
	}
	PlaceholderMesh->SetRelativeScale3D(FVector(4.0, 4.0, 0.2));
}

void ATargetZone::BeginPlay()
{
	Super::BeginPlay();
	Trigger->SetSphereRadius(TriggerRadius);
	Trigger->OnComponentBeginOverlap.AddDynamic(this, &ATargetZone::OnOverlap);
}

void ATargetZone::OnOverlap(UPrimitiveComponent*, AActor* OtherActor, UPrimitiveComponent*, int32, bool, const FHitResult&)
{
	if (Cast<AShip>(OtherActor))
	{
		OnTargetReached.Broadcast();
	}
}
