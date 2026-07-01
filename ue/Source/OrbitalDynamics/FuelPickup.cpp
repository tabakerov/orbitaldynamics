#include "FuelPickup.h"

#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Ship.h"
#include "UObject/ConstructorHelpers.h"

AFuelPickup::AFuelPickup()
{
	PrimaryActorTick.bCanEverTick = false;

	Trigger = CreateDefaultSubobject<USphereComponent>(TEXT("Trigger"));
	Trigger->SetCollisionProfileName(TEXT("OverlapAllDynamic"));
	Trigger->SetGenerateOverlapEvents(true);
	Trigger->SetSphereRadius(1.0f);
	SetRootComponent(Trigger);

	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(Trigger);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (CubeMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(CubeMesh.Object);
	}
	PlaceholderMesh->SetRelativeScale3D(FVector(0.8, 0.8, 0.8));
}

void AFuelPickup::BeginPlay()
{
	Super::BeginPlay();
	Trigger->OnComponentBeginOverlap.AddDynamic(this, &AFuelPickup::OnOverlap);
}

void AFuelPickup::OnOverlap(UPrimitiveComponent*, AActor* OtherActor, UPrimitiveComponent*, int32, bool, const FHitResult&)
{
	if (AShip* Ship = Cast<AShip>(OtherActor))
	{
		Ship->AddFuel(FuelAmount);
		Destroy();
	}
}
