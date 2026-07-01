#include "EngineModule.h"

#include "Components/StaticMeshComponent.h"
#include "ModuleProfiles.h"
#include "Ship.h"
#include "UObject/ConstructorHelpers.h"

AEngineModule::AEngineModule()
{
	PrimaryActorTick.bCanEverTick = true;

	static ConstructorHelpers::FObjectFinder<UStaticMesh> CylinderMesh(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> ConeMesh(TEXT("/Engine/BasicShapes/Cone.Cone"));

	PlaceholderMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("PlaceholderMesh"));
	PlaceholderMesh->SetupAttachment(RootComponent);
	PlaceholderMesh->SetCollisionProfileName(TEXT("NoCollision"));
	if (CylinderMesh.Succeeded())
	{
		PlaceholderMesh->SetStaticMesh(CylinderMesh.Object);
	}
	// Basic cylinder is 1 m wide / 1 m tall at our 1 UU = 1 m scale; lay it along
	// local X (thrust axis is -X) and shrink to a stubby nozzle.
	PlaceholderMesh->SetRelativeRotation(FRotator(90, 0, 0));
	PlaceholderMesh->SetRelativeScale3D(FVector(0.25, 0.25, 0.5));

	ExhaustMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ExhaustMesh"));
	ExhaustMesh->SetupAttachment(RootComponent);
	ExhaustMesh->SetCollisionProfileName(TEXT("NoCollision"));
	if (ConeMesh.Succeeded())
	{
		ExhaustMesh->SetStaticMesh(ConeMesh.Object);
	}
	// Exhaust points along local -X (the thrust direction pushes the ship the other way).
	ExhaustMesh->SetRelativeLocation(FVector(-0.5, 0, 0));
	ExhaustMesh->SetRelativeRotation(FRotator(-90, 0, 0));
	ExhaustMesh->SetRelativeScale3D(FVector(0.15, 0.15, 0.4));
	ExhaustMesh->SetVisibility(false);
}

void AEngineModule::Configure()
{
	if (const UEngineProfile* EP = Cast<UEngineProfile>(Profile))
	{
		GimbalRangeRad = FMath::DegreesToRadians(EP->GimbalRangeDeg);
	}
	GimbalAngle = 0.0f;
	ApplyGimbalRotation();
}

float AEngineModule::GetMass() const
{
	const UEngineProfile* EP = Cast<UEngineProfile>(Profile);
	return EP ? EP->DryMass : 0.0f;
}

void AEngineModule::PhysicsTick(float Delta)
{
	if (ExhaustMesh)
	{
		ExhaustMesh->SetVisibility(IsThrusting());
	}
}

bool AEngineModule::IsThrusting() const
{
	return bActive && Intensity > 0.0f && HasEffectiveFuelSupply();
}

FVector AEngineModule::GetThrustVector() const
{
	if (!bActive || Intensity <= 0.0f || !HasEffectiveFuelSupply())
	{
		return FVector::ZeroVector;
	}
	const UEngineProfile* EP = Cast<UEngineProfile>(Profile);
	if (!EP)
	{
		return FVector::ZeroVector;
	}
	// Godot: -global_basis.z * max_thrust * intensity * fuel_supply_ratio.
	// UE convention: thrust pushes along -module forward.
	return -GetActorForwardVector() * EP->MaxThrust * Intensity * FuelSupplyRatio;
}

float AEngineModule::GetRequestedFuelDrain(float Delta) const
{
	if (!bActive || Intensity <= 0.0f || !Ship.IsValid())
	{
		return 0.0f;
	}
	const UEngineProfile* EP = Cast<UEngineProfile>(Profile);
	return EP ? EP->FuelConsumptionRate * Intensity * Delta : 0.0f;
}

float AEngineModule::GetFuelDrain(float Delta) const
{
	if (!HasEffectiveFuelSupply())
	{
		return 0.0f;
	}
	return GetRequestedFuelDrain(Delta) * FuelSupplyRatio;
}

void AEngineModule::ApplyGimbalDelta(float Delta)
{
	if (!bActive || Delta == 0.0f)
	{
		return;
	}
	GimbalAngle = FMath::Clamp(GimbalAngle + Delta, -GimbalRangeRad, GimbalRangeRad);
	ApplyGimbalRotation();
}

void AEngineModule::ApplyGimbalRotation()
{
	// Godot rotates around +Y (right-handed); the on-screen equivalent in UE's
	// left-handed Z-up frame is yaw with the opposite sign.
	SetActorRelativeRotation(FRotator(0, -FMath::RadiansToDegrees(GimbalAngle), 0));
}

bool AEngineModule::HasEffectiveFuelSupply() const
{
	if (!Ship.IsValid() || FuelSupplyRatio <= 0.0f)
	{
		return false;
	}
	if (FuelSupplyRatio < 1.0f)
	{
		return true; // partially fed: thrust exists but is scaled down
	}
	return Ship->Fuel > 0.0f;
}
