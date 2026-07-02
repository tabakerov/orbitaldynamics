#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "ShipTypes.h"
#include "Ship.generated.h"

class AShipModule;
class UBoxComponent;
class UInputAction;
class UInputMappingContext;
class UModuleProfile;
class UShipLoadout;
class UStaticMeshComponent;
struct FInputActionValue;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_TwoParams(FOnFuelChanged, float, Current, float, Maximum);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnShipCrashed, FVector, CrashPosition);

USTRUCT()
struct FThrustSample
{
	GENERATED_BODY()

	UPROPERTY()
	TObjectPtr<AShipModule> Module;

	FVector Origin = FVector::ZeroVector;
	FVector Force = FVector::ZeroVector;
};

// Port of godot/scripts/ship.gd: a physics pawn assembled at runtime from a
// ShipLoadout (hull + up to 4 modules), with dynamic mass / center of mass,
// two-phase fuel flow and per-engine gimbals.
UCLASS()
class ORBITALDYNAMICS_API AShip : public APawn
{
	GENERATED_BODY()

public:
	AShip();

	static constexpr float FuelUnitMass = 0.02f;
	static constexpr float StickDeadzone = 0.2f;
	static constexpr float GimbalKeyboardSpeed = 2.0f;      // rad/s
	static constexpr float GimbalStickSensitivity = 0.10f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ship")
	TObjectPtr<UShipLoadout> Loadout;

	// If >= 0, overrides Loadout->StartingInternalFuel.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Ship")
	float StartingFuelOverride = -1.0f;

	UPROPERTY(BlueprintAssignable, Category = "Ship")
	FOnFuelChanged OnFuelChanged;

	UPROPERTY(BlueprintAssignable, Category = "Ship")
	FOnShipCrashed OnCrashed;

	float Fuel = 0.0f;
	float MaxFuel = 0.0f;

	// Runtime module swap from the station modifier screen (nullptr = remove).
	void ApplyLoadoutChange(EMountBinding Binding, UModuleProfile* NewProfile);

	void AddFuel(float Amount);

	// Clears polled input state (mounts, thrust, gimbal, stick). Called when the
	// game unpauses so release events missed by a modal UI can't leave a key stuck.
	void ResetInputState();

	bool HasCrashed() const { return bCrashed; }

	// Debug getters used by the flight visualizer.
	TArray<FThrustSample> GetDebugThrustForceSamples() const;
	FVector GetDebugTotalThrustForce() const;
	FVector GetDebugGravityAcceleration() const;

	virtual void Tick(float DeltaTime) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;

protected:
	virtual void BeginPlay() override;

	UPROPERTY(VisibleAnywhere, Category = "Ship")
	TObjectPtr<UBoxComponent> Hull;

	UPROPERTY(VisibleAnywhere, Category = "Ship")
	TObjectPtr<UStaticMeshComponent> HullMesh;

	UFUNCTION()
	void OnHullHit(UPrimitiveComponent* HitComp, AActor* OtherActor,
	               UPrimitiveComponent* OtherComp, FVector NormalImpulse, const FHitResult& Hit);

private:
	void BuildDefaultLoadout();
	void BuildFromLoadout();
	void SpawnModule(EMountBinding Binding, UModuleProfile* Profile);

	void UpdateModuleInputs();
	void UpdateGimbal(float Delta);
	void PrepareFuelFlow(float Delta);
	void ApplyEngineForces();
	void ApplyFuelFlow(float Delta);
	void ApplyGravity();
	void RecalculateMassProperties();

	void Crash(class ACelestialBody* Body);
	FVector GetCrashPosition(const ACelestialBody* Body) const;

	void HandleRestart(const FInputActionValue& Value);
	void HandleDebugToggle(const FInputActionValue& Value);

	UPROPERTY()
	TMap<EMountBinding, TObjectPtr<AShipModule>> Modules;

	UPROPERTY()
	TMap<EMountBinding, TObjectPtr<USceneComponent>> MountNodes;

	// Input state polled by the physics tick (Godot polls the input map directly;
	// with Enhanced Input we keep it updated from action callbacks instead).
	TMap<EMountBinding, bool> MountPressed;
	float CurrentThrust = 0.0f;
	FVector2D CurrentStick = FVector2D::ZeroVector;
	bool bGimbalCWPressed = false;
	bool bGimbalCCWPressed = false;

	// Programmatically-built Enhanced Input (no editor assets needed yet).
	UPROPERTY()
	TObjectPtr<UInputMappingContext> InputContext;

	UPROPERTY()
	TMap<EMountBinding, TObjectPtr<UInputAction>> MountActions;

	UPROPERTY()
	TObjectPtr<UInputAction> ThrustAction;
	UPROPERTY()
	TObjectPtr<UInputAction> GimbalCWAction;
	UPROPERTY()
	TObjectPtr<UInputAction> GimbalCCWAction;
	UPROPERTY()
	TObjectPtr<UInputAction> GimbalStickAction;
	UPROPERTY()
	TObjectPtr<UInputAction> RestartAction;
	UPROPERTY()
	TObjectPtr<UInputAction> DebugToggleAction;

	float HullDryMass = 10.0f;
	float PrevStickAngle = 0.0f;
	bool bStickActive = false;
	bool bCrashed = false;
};
