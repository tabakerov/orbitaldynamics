#include "FuelTankModule.h"

#include "Components/StaticMeshComponent.h"
#include "ModuleProfiles.h"
#include "Ship.h"
#include "UObject/ConstructorHelpers.h"

AFuelTankModule::AFuelTankModule()
{
	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(RootComponent);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereMesh(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	if (SphereMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(SphereMesh.Object);
	}
	PlaceholderMesh->SetRelativeScale3D(FVector(0.4, 0.4, 0.4));
}

void AFuelTankModule::Configure()
{
	if (const UFuelTankProfile* FP = Cast<UFuelTankProfile>(Profile))
	{
		CurrentFuel = FP->Capacity * FMath::Clamp(FP->StartingFill, 0.0f, 1.0f);
	}
}

float AFuelTankModule::GetMass() const
{
	const UFuelTankProfile* FP = Cast<UFuelTankProfile>(Profile);
	if (!FP)
	{
		return 0.0f;
	}
	return FP->DryMass + CurrentFuel * AShip::FuelUnitMass;
}

float AFuelTankModule::GetPotentialFuelIntake(float Delta) const
{
	if (!bActive || Intensity <= 0.0f || CurrentFuel <= 0.0f)
	{
		return 0.0f;
	}
	const UFuelTankProfile* FP = Cast<UFuelTankProfile>(Profile);
	if (!FP)
	{
		return 0.0f;
	}
	return FMath::Min(FP->MaxPumpRate * Intensity * Delta, CurrentFuel);
}

void AFuelTankModule::CommitFuelIntake(float Amount)
{
	CurrentFuel = FMath::Max(CurrentFuel - Amount, 0.0f);
}
