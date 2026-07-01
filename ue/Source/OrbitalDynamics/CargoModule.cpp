#include "CargoModule.h"

#include "Components/StaticMeshComponent.h"
#include "ModuleProfiles.h"
#include "UObject/ConstructorHelpers.h"

ACargoModule::ACargoModule()
{
	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(RootComponent);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (CubeMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(CubeMesh.Object);
	}
	PlaceholderMesh->SetRelativeScale3D(FVector(0.5, 0.5, 0.5));
}

float ACargoModule::GetMass() const
{
	const UCargoProfile* CP = Cast<UCargoProfile>(Profile);
	return CP ? CP->Mass : 0.0f;
}
