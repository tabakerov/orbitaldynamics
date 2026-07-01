#include "CameraRig.h"

#include "Camera/CameraComponent.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "Ship.h"

ACameraRig::ACameraRig()
{
	PrimaryActorTick.bCanEverTick = true;

	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);

	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(Root);
	// godot camera_rig.tscn: height ~47 m, ~7.26 m ahead along ship forward,
	// looking straight down with screen-up = ship forward.
	Camera->SetRelativeLocation(FVector(7.256, 0, 47.049));
	Camera->SetRelativeRotation(FRotator(-90, 0, 0));
	// Godot fov 77.7 is vertical; UE FieldOfView is horizontal (~110 at 16:9).
	Camera->SetFieldOfView(110.0f);
}

void ACameraRig::SetTarget(AActor* NewTarget)
{
	Target = NewTarget;
	if (Target)
	{
		SnapToTarget();
	}
}

void ACameraRig::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);

	if (!Target)
	{
		// Standalone-map convenience: latch onto the first ship around.
		TActorIterator<AShip> It(GetWorld());
		if (It)
		{
			SetTarget(*It);
		}
	}
	if (Target)
	{
		SnapToTarget();
		EnsureViewTarget();
	}
}

void ACameraRig::SnapToTarget()
{
	const FVector TargetLocation = Target->GetActorLocation();
	SetActorLocation(FVector(TargetLocation.X, TargetLocation.Y, 0.0));
	SetActorRotation(FRotator(0, Target->GetActorRotation().Yaw, 0));
}

void ACameraRig::EnsureViewTarget()
{
	if (bViewTargetSet)
	{
		return;
	}
	if (APlayerController* PC = UGameplayStatics::GetPlayerController(this, 0))
	{
		PC->SetViewTarget(this);
		bViewTargetSet = true;
	}
}
