#include "CelestialBody.h"

#include "CelestialBodyData.h"
#include "CelestialSimSubsystem.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	// /Engine/BasicShapes/Sphere is 100 UU in diameter.
	constexpr float BasicSphereRadius = 50.0f;
}

ACelestialBody::ACelestialBody()
{
	PrimaryActorTick.bCanEverTick = true;

	Collision = CreateDefaultSubobject<USphereComponent>(TEXT("Collision"));
	Collision->SetCollisionProfileName(TEXT("BlockAllDynamic"));
	Collision->SetMobility(EComponentMobility::Movable);
	SetRootComponent(Collision);

	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(Collision);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereMesh(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	if (SphereMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(SphereMesh.Object);
	}
}

float ACelestialBody::GetBodyRadius() const
{
	if (Collision)
	{
		return Collision->GetScaledSphereRadius();
	}
	return BodyData ? BodyData->Radius : 0.0f;
}

void ACelestialBody::BeginPlay()
{
	Super::BeginPlay();
	if (BodyData)
	{
		SetupVisuals();
	}
}

void ACelestialBody::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (SimIndex < 0)
	{
		return;
	}
	if (const UGameInstance* GI = GetGameInstance())
	{
		if (const UCelestialSimSubsystem* Sim = GI->GetSubsystem<UCelestialSimSubsystem>())
		{
			if (Sim->IsActive())
			{
				SetActorLocation(Sim->GetBodyPosition(SimIndex));
			}
		}
	}
}

void ACelestialBody::SetupVisuals()
{
	Collision->SetSphereRadius(BodyData->Radius);
	if (PlaceholderMesh->GetStaticMesh())
	{
		PlaceholderMesh->SetWorldScale3D(FVector(BodyData->Radius / BasicSphereRadius));
	}
}
