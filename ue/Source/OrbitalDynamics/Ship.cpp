#include "Ship.h"

#include "CelestialBody.h"
#include "CelestialSimSubsystem.h"
#include "Components/BoxComponent.h"
#include "Components/StaticMeshComponent.h"
#include "DebugFlightVisualizer.h"
#include "EngineModule.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "HullData.h"
#include "InputAction.h"
#include "InputActionValue.h"
#include "InputMappingContext.h"
#include "Kismet/GameplayStatics.h"
#include "ModuleProfiles.h"
#include "ShipLoadout.h"
#include "ShipModule.h"
#include "UObject/ConstructorHelpers.h"
#include "EngineUtils.h"

AShip::AShip()
{
	PrimaryActorTick.bCanEverTick = true;

	Hull = CreateDefaultSubobject<UBoxComponent>(TEXT("Hull"));
	Hull->SetBoxExtent(FVector(0.75, 0.75, 0.4));
	Hull->SetCollisionProfileName(TEXT("Pawn"));
	Hull->SetSimulatePhysics(true);
	Hull->SetEnableGravity(false);
	Hull->SetNotifyRigidBodyCollision(true);
	Hull->SetGenerateOverlapEvents(true);
	// Godot ship.tscn: axis_lock_linear_y, axis_lock_angular_x/z -> XY plane in UE.
	Hull->BodyInstance.DOFMode = EDOFMode::SixDOF;
	Hull->BodyInstance.bLockZTranslation = true;
	Hull->BodyInstance.bLockXRotation = true;
	Hull->BodyInstance.bLockYRotation = true;
	Hull->BodyInstance.LinearDamping = 0.0f;
	Hull->BodyInstance.AngularDamping = 0.0f;
	SetRootComponent(Hull);

	HullMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("HullMesh"));
	HullMesh->SetupAttachment(Hull);
	HullMesh->SetCollisionProfileName(TEXT("NoCollision"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> CubeMesh(TEXT("/Engine/BasicShapes/Cube.Cube"));
	if (CubeMesh.Succeeded())
	{
		HullMesh->SetStaticMesh(CubeMesh.Object);
	}
	// /Engine/BasicShapes/Cube is 1 m per side at our 1 UU = 1 m scale.
	HullMesh->SetRelativeScale3D(FVector(1.5, 1.5, 0.8));
}

void AShip::BeginPlay()
{
	Super::BeginPlay();

	Hull->OnComponentHit.AddDynamic(this, &AShip::OnHullHit);

	for (EMountBinding Binding : MountBinding::All)
	{
		MountPressed.Add(Binding, false);
	}

	if (!Loadout)
	{
		BuildDefaultLoadout();
	}
	else
	{
		// Never mutate the authored asset: runtime swaps work on a copy.
		Loadout = DuplicateObject<UShipLoadout>(Loadout, this);
	}
	BuildFromLoadout();
	RecalculateMassProperties();
	OnFuelChanged.Broadcast(Fuel, MaxFuel);
}

void AShip::BuildDefaultLoadout()
{
	// Mirrors godot/resources/loadouts/default.tres: rectangular hull,
	// a standard engine in every slot.
	Loadout = NewObject<UShipLoadout>(this);
	Loadout->Hull = NewObject<UHullData>(this);
	Loadout->StartingInternalFuel = 200.0f;

	for (EMountBinding Binding : MountBinding::All)
	{
		UEngineProfile* Engine = NewObject<UEngineProfile>(this);
		Engine->ModuleClass = AEngineModule::StaticClass();
		Engine->DisplayName = NSLOCTEXT("OrbitalDynamics", "StandardEngine", "Standard Engine");
		Loadout->SetModule(Binding, Engine);
	}
}

void AShip::BuildFromLoadout()
{
	const UHullData* HullData = Loadout ? Loadout->Hull.Get() : nullptr;
	if (!HullData)
	{
		UE_LOG(LogTemp, Warning, TEXT("ShipLoadout has no hull assigned."));
		return;
	}

	HullDryMass = HullData->DryMass;
	MaxFuel = HullData->MaxInternalFuel;
	const float Start = StartingFuelOverride >= 0.0f ? StartingFuelOverride : Loadout->StartingInternalFuel;
	Fuel = FMath::Clamp(Start, 0.0f, MaxFuel);

	Hull->SetBoxExtent(HullData->CollisionBoxExtent);
	if (HullData->Mesh)
	{
		HullMesh->SetStaticMesh(HullData->Mesh);
	}

	for (const FMountSlot& Slot : HullData->Mounts)
	{
		USceneComponent* MountNode = NewObject<USceneComponent>(
			this, *FString::Printf(TEXT("Mount_%s"), MountBinding::Name(Slot.Binding)));
		MountNode->AttachToComponent(Hull, FAttachmentTransformRules::KeepRelativeTransform);
		MountNode->SetRelativeTransform(Slot.Transform);
		MountNode->RegisterComponent();
		MountNodes.Add(Slot.Binding, MountNode);

		SpawnModule(Slot.Binding, Loadout->GetModule(Slot.Binding));
	}
}

void AShip::SpawnModule(EMountBinding Binding, UModuleProfile* Profile)
{
	if (!Profile || !Profile->ModuleClass)
	{
		return;
	}
	USceneComponent* MountNode = MountNodes.FindRef(Binding);
	if (!MountNode)
	{
		return;
	}

	FActorSpawnParameters Params;
	Params.Owner = this;
	Params.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
	AShipModule* Module = GetWorld()->SpawnActor<AShipModule>(Profile->ModuleClass, Params);
	if (!Module)
	{
		UE_LOG(LogTemp, Warning, TEXT("Module class did not produce a ShipModule"));
		return;
	}
	Module->AttachToComponent(MountNode, FAttachmentTransformRules::KeepRelativeTransform);
	Module->SetActorRelativeTransform(FTransform::Identity);
	Module->Attach(this, Profile);
	Modules.Add(Binding, Module);
}

void AShip::ApplyLoadoutChange(EMountBinding Binding, UModuleProfile* NewProfile)
{
	if (TObjectPtr<AShipModule>* Existing = Modules.Find(Binding))
	{
		if (*Existing)
		{
			(*Existing)->Destroy();
		}
		Modules.Remove(Binding);
	}

	SpawnModule(Binding, NewProfile);

	if (Loadout)
	{
		Loadout->SetModule(Binding, NewProfile);
	}
	RecalculateMassProperties();
}

void AShip::ResetInputState()
{
	for (EMountBinding Binding : MountBinding::All)
	{
		MountPressed.Add(Binding, false);
	}
	CurrentThrust = 0.0f;
	CurrentStick = FVector2D::ZeroVector;
	bGimbalCWPressed = false;
	bGimbalCCWPressed = false;
	bStickActive = false;
}

void AShip::AddFuel(float Amount)
{
	Fuel = FMath::Clamp(Fuel + Amount, 0.0f, MaxFuel);
	OnFuelChanged.Broadcast(Fuel, MaxFuel);
}

void AShip::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (bCrashed || DeltaTime <= 0.0f)
	{
		return;
	}

	// Same order as godot/scripts/ship.gd _physics_process.
	UpdateModuleInputs();
	UpdateGimbal(DeltaTime);
	for (const auto& Pair : Modules)
	{
		Pair.Value->PhysicsTick(DeltaTime);
	}
	PrepareFuelFlow(DeltaTime);
	ApplyEngineForces();
	ApplyFuelFlow(DeltaTime);
	ApplyGravity();
	RecalculateMassProperties();
}

void AShip::UpdateModuleInputs()
{
	for (const auto& Pair : Modules)
	{
		Pair.Value->bActive = MountPressed.FindRef(Pair.Key);
		Pair.Value->Intensity = CurrentThrust;
	}
}

void AShip::UpdateGimbal(float Delta)
{
	float GimbalDelta = 0.0f;

	if (bGimbalCWPressed)
	{
		GimbalDelta += GimbalKeyboardSpeed * Delta;
	}
	if (bGimbalCCWPressed)
	{
		GimbalDelta -= GimbalKeyboardSpeed * Delta;
	}

	// Relative stick control: the gimbal follows the stick's angular velocity.
	// Godot reads Y with up = -1; UE gamepad Y has up = +1, so atan2(x, -y_godot)
	// becomes atan2(x, y_ue). Stick up = 0, clockwise positive.
	if (CurrentStick.Size() > StickDeadzone)
	{
		const float StickAngle = FMath::Atan2(CurrentStick.X, CurrentStick.Y);
		if (bStickActive)
		{
			float AngleDelta = StickAngle - PrevStickAngle;
			AngleDelta = FMath::Fmod(FMath::Fmod(AngleDelta + PI, 2.0f * PI) + 2.0f * PI, 2.0f * PI) - PI;
			GimbalDelta += AngleDelta * GimbalStickSensitivity;
		}
		PrevStickAngle = StickAngle;
		bStickActive = true;
	}
	else
	{
		bStickActive = false;
	}

	for (const auto& Pair : Modules)
	{
		Pair.Value->ApplyGimbalDelta(GimbalDelta);
	}
}

void AShip::PrepareFuelFlow(float Delta)
{
	float RequestedDrain = 0.0f;
	for (const auto& Pair : Modules)
	{
		Pair.Value->FuelSupplyRatio = 1.0f;
		RequestedDrain += Pair.Value->GetRequestedFuelDrain(Delta);
	}

	const float DrainRatio = RequestedDrain > 0.0f ? FMath::Min(Fuel / RequestedDrain, 1.0f) : 1.0f;

	for (const auto& Pair : Modules)
	{
		if (Pair.Value->GetRequestedFuelDrain(Delta) > 0.0f)
		{
			Pair.Value->FuelSupplyRatio = DrainRatio;
		}
	}
}

void AShip::ApplyEngineForces()
{
	for (const FThrustSample& Sample : GetDebugThrustForceSamples())
	{
		// Godot apply_force(force, offset-from-COM); UE takes a world location.
		Hull->AddForceAtLocation(Sample.Force, Sample.Origin);
	}
}

void AShip::ApplyFuelFlow(float Delta)
{
	float Drain = 0.0f;
	for (const auto& Pair : Modules)
	{
		Drain += Pair.Value->GetFuelDrain(Delta);
	}

	// Intake from external tanks, distributed proportionally to each tank's
	// potential and limited by the free room in the internal tank.
	float TotalPotential = 0.0f;
	TArray<TPair<AShipModule*, float>> PerModulePotential;
	for (const auto& Pair : Modules)
	{
		const float Potential = Pair.Value->GetPotentialFuelIntake(Delta);
		if (Potential > 0.0f)
		{
			PerModulePotential.Emplace(Pair.Value, Potential);
			TotalPotential += Potential;
		}
	}

	const float FuelAfterDrain = FMath::Max(Fuel - Drain, 0.0f);
	const float Room = MaxFuel - FuelAfterDrain;
	const float TotalIntake = FMath::Min(TotalPotential, Room);
	const float Ratio = TotalPotential > 0.0f ? TotalIntake / TotalPotential : 0.0f;

	for (const auto& Entry : PerModulePotential)
	{
		Entry.Key->CommitFuelIntake(Entry.Value * Ratio);
	}

	const float NewFuel = FuelAfterDrain + TotalIntake;
	if (!FMath::IsNearlyEqual(NewFuel, Fuel))
	{
		Fuel = NewFuel;
		OnFuelChanged.Broadcast(Fuel, MaxFuel);
	}
}

void AShip::ApplyGravity()
{
	Hull->AddForce(GetDebugGravityAcceleration() * Hull->GetMass());
}

void AShip::RecalculateMassProperties()
{
	float Total = HullDryMass + Fuel * FuelUnitMass;
	FVector Weighted = FVector::ZeroVector;

	for (const auto& Pair : Modules)
	{
		const USceneComponent* MountNode = MountNodes.FindRef(Pair.Key);
		const float ModuleMass = Pair.Value->GetMass();
		if (ModuleMass > 0.0f && MountNode)
		{
			const FVector LocalPos = MountNode->GetRelativeTransform().TransformPosition(
				Pair.Value->GetRootComponent()->GetRelativeLocation());
			Total += ModuleMass;
			Weighted += ModuleMass * LocalPos;
		}
	}

	if (Total > 0.0f && Hull->IsSimulatingPhysics())
	{
		// The physics COM of the centered box is the actor origin, so the nudge
		// equals the weighted module/fuel offset directly.
		Hull->BodyInstance.COMNudge = Weighted / Total;
		Hull->SetMassOverrideInKg(NAME_None, Total, true);
	}
}

TArray<FThrustSample> AShip::GetDebugThrustForceSamples() const
{
	TArray<FThrustSample> Samples;
	for (const auto& Pair : Modules)
	{
		const FVector Force = Pair.Value->GetThrustVector();
		if (Force.SizeSquared() > 0.0f)
		{
			FThrustSample Sample;
			Sample.Module = Pair.Value;
			Sample.Origin = Pair.Value->GetActorLocation();
			Sample.Force = Force;
			Samples.Add(Sample);
		}
	}
	return Samples;
}

FVector AShip::GetDebugTotalThrustForce() const
{
	FVector Total = FVector::ZeroVector;
	for (const FThrustSample& Sample : GetDebugThrustForceSamples())
	{
		Total += Sample.Force;
	}
	return Total;
}

FVector AShip::GetDebugGravityAcceleration() const
{
	if (const UGameInstance* GI = GetGameInstance())
	{
		if (const UCelestialSimSubsystem* Sim = GI->GetSubsystem<UCelestialSimSubsystem>())
		{
			return Sim->GetGravityAt(GetActorLocation());
		}
	}
	return FVector::ZeroVector;
}

void AShip::OnHullHit(UPrimitiveComponent*, AActor* OtherActor, UPrimitiveComponent*, FVector, const FHitResult&)
{
	// Any contact with a celestial body is a crash (no velocity threshold).
	if (ACelestialBody* Body = Cast<ACelestialBody>(OtherActor))
	{
		Crash(Body);
	}
}

void AShip::Crash(ACelestialBody* Body)
{
	if (bCrashed)
	{
		return;
	}
	bCrashed = true;

	for (const auto& Pair : Modules)
	{
		Pair.Value->bActive = false;
		Pair.Value->Intensity = 0.0f;
	}

	Hull->SetPhysicsLinearVelocity(FVector::ZeroVector);
	Hull->SetPhysicsAngularVelocityInRadians(FVector::ZeroVector);
	Hull->SetSimulatePhysics(false);

	OnCrashed.Broadcast(GetCrashPosition(Body));
}

FVector AShip::GetCrashPosition(const ACelestialBody* Body) const
{
	const FVector Offset = GetActorLocation() - Body->GetActorLocation();
	if (Offset.SizeSquared() <= 0.0001)
	{
		return GetActorLocation();
	}
	const float Radius = Body->GetBodyRadius();
	if (Radius <= 0.0f)
	{
		return GetActorLocation();
	}
	return Body->GetActorLocation() + Offset.GetSafeNormal() * Radius;
}

void AShip::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	UEnhancedInputComponent* Input = Cast<UEnhancedInputComponent>(PlayerInputComponent);
	if (!Input)
	{
		return;
	}

	if (!InputMapping)
	{
		BuildFallbackInputAssets();
	}

	struct FMountAction
	{
		UInputAction* Action;
		EMountBinding Binding;
	};
	const FMountAction MountBindings[] = {
		{ MountFrontAction, EMountBinding::Front },
		{ MountRearAction, EMountBinding::Rear },
		{ MountLeftAction, EMountBinding::Left },
		{ MountRightAction, EMountBinding::Right },
	};
	for (const FMountAction& Entry : MountBindings)
	{
		if (!Entry.Action)
		{
			continue;
		}
		const EMountBinding Binding = Entry.Binding;
		Input->BindActionValueLambda(Entry.Action, ETriggerEvent::Started,
			[this, Binding](const FInputActionValue&) { MountPressed.Add(Binding, true); });
		Input->BindActionValueLambda(Entry.Action, ETriggerEvent::Completed,
			[this, Binding](const FInputActionValue&) { MountPressed.Add(Binding, false); });
	}

	if (ThrustAction)
	{
		Input->BindActionValueLambda(ThrustAction, ETriggerEvent::Triggered,
			[this](const FInputActionValue& Value) { CurrentThrust = Value.Get<float>(); });
		Input->BindActionValueLambda(ThrustAction, ETriggerEvent::Completed,
			[this](const FInputActionValue&) { CurrentThrust = 0.0f; });
	}
	if (GimbalCWAction)
	{
		Input->BindActionValueLambda(GimbalCWAction, ETriggerEvent::Started,
			[this](const FInputActionValue&) { bGimbalCWPressed = true; });
		Input->BindActionValueLambda(GimbalCWAction, ETriggerEvent::Completed,
			[this](const FInputActionValue&) { bGimbalCWPressed = false; });
	}
	if (GimbalCCWAction)
	{
		Input->BindActionValueLambda(GimbalCCWAction, ETriggerEvent::Started,
			[this](const FInputActionValue&) { bGimbalCCWPressed = true; });
		Input->BindActionValueLambda(GimbalCCWAction, ETriggerEvent::Completed,
			[this](const FInputActionValue&) { bGimbalCCWPressed = false; });
	}
	if (GimbalStickAction)
	{
		Input->BindActionValueLambda(GimbalStickAction, ETriggerEvent::Triggered,
			[this](const FInputActionValue& Value) { CurrentStick = Value.Get<FVector2D>(); });
		Input->BindActionValueLambda(GimbalStickAction, ETriggerEvent::Completed,
			[this](const FInputActionValue&) { CurrentStick = FVector2D::ZeroVector; });
	}
	if (RestartAction)
	{
		Input->BindAction(RestartAction, ETriggerEvent::Started, this, &AShip::HandleRestart);
	}
	if (DebugToggleAction)
	{
		Input->BindAction(DebugToggleAction, ETriggerEvent::Started, this, &AShip::HandleDebugToggle);
	}

	if (const APlayerController* PC = Cast<APlayerController>(GetController()))
	{
		if (UEnhancedInputLocalPlayerSubsystem* Subsystem =
			ULocalPlayer::GetSubsystem<UEnhancedInputLocalPlayerSubsystem>(PC->GetLocalPlayer()))
		{
			Subsystem->AddMappingContext(InputMapping, 0);
		}
	}
}

void AShip::BuildFallbackInputAssets()
{
	InputMapping = NewObject<UInputMappingContext>(this);

	auto MakeAction = [this](EInputActionValueType ValueType, std::initializer_list<FKey> Keys) -> UInputAction*
	{
		UInputAction* Action = NewObject<UInputAction>(this);
		Action->ValueType = ValueType;
		for (const FKey& Key : Keys)
		{
			InputMapping->MapKey(Action, Key);
		}
		return Action;
	};

	// Same bindings as godot project.godot (and the /Game/Input assets):
	// W/S/A/D + Y/A/X/B face buttons for mounts, Space/RT thrust,
	// E/Q gimbal, left stick, R/Start restart, F3 debug.
	MountFrontAction = MakeAction(EInputActionValueType::Boolean, { EKeys::W, EKeys::Gamepad_FaceButton_Top });
	MountRearAction = MakeAction(EInputActionValueType::Boolean, { EKeys::S, EKeys::Gamepad_FaceButton_Bottom });
	MountLeftAction = MakeAction(EInputActionValueType::Boolean, { EKeys::A, EKeys::Gamepad_FaceButton_Left });
	MountRightAction = MakeAction(EInputActionValueType::Boolean, { EKeys::D, EKeys::Gamepad_FaceButton_Right });
	ThrustAction = MakeAction(EInputActionValueType::Axis1D, { EKeys::SpaceBar, EKeys::Gamepad_RightTriggerAxis });
	GimbalCWAction = MakeAction(EInputActionValueType::Boolean, { EKeys::E });
	GimbalCCWAction = MakeAction(EInputActionValueType::Boolean, { EKeys::Q });
	GimbalStickAction = MakeAction(EInputActionValueType::Axis2D, { EKeys::Gamepad_Left2D });
	RestartAction = MakeAction(EInputActionValueType::Boolean, { EKeys::R, EKeys::Gamepad_Special_Right });
	DebugToggleAction = MakeAction(EInputActionValueType::Boolean, { EKeys::F3 });
}

void AShip::HandleRestart(const FInputActionValue&)
{
	UGameplayStatics::OpenLevel(this, FName(*UGameplayStatics::GetCurrentLevelName(this)));
}

void AShip::HandleDebugToggle(const FInputActionValue&)
{
	for (TActorIterator<ADebugFlightVisualizer> It(GetWorld()); It; ++It)
	{
		It->SetEnabled(!It->IsEnabled());
	}
}
