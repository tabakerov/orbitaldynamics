#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "Tickable.h"
#include "CelestialSimSubsystem.generated.h"

class UCelestialBodyData;

// Port of the CelestialSim autoload (godot/scripts/celestial_simulation.gd).
// N-body gravity, symplectic Euler at a fixed 60 Hz step, gameplay plane Z=0.
//
// Two distinct gravity laws, both preserved from the original:
//  - body<->body attraction: G * m / d^2, unlimited range;
//  - body->ship influence (GetGravityAt): strength * m / d^falloff,
//    with per-body min/max range.
UCLASS()
class ORBITALDYNAMICS_API UCelestialSimSubsystem : public UGameInstanceSubsystem, public FTickableGameObject
{
	GENERATED_BODY()

public:
	// FTickableGameObject
	virtual void Tick(float DeltaTime) override;
	virtual ETickableTickType GetTickableTickType() const override
	{
		return IsTemplate() ? ETickableTickType::Never : ETickableTickType::Conditional;
	}
	virtual bool IsTickable() const override { return bActive; }
	virtual TStatId GetStatId() const override
	{
		RETURN_QUICK_DECLARE_CYCLE_STAT(UCelestialSimSubsystem, STATGROUP_Tickables);
	}

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	void InitializeBodies(const TArray<UCelestialBodyData*>& Data,
	                      const TArray<FVector>& InPositions,
	                      const TArray<FVector>& InVelocities,
	                      const TArray<bool>& InStationary);

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	void Clear();

	// Advance the simulation by one explicit step (used by fixed-step Tick and by tests).
	void Step(float Delta);

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	FVector GetGravityAt(const FVector& Pos) const;

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	FVector GetBodyPosition(int32 Index) const;

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	FVector GetBodyVelocity(int32 Index) const;

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	FVector GetBodyGravityAcceleration(int32 Index) const;

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	bool IsBodyStationary(int32 Index) const;

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	int32 GetBodyCount() const { return Count; }

	UFUNCTION(BlueprintCallable, Category = "CelestialSim")
	bool IsActive() const { return bActive; }

	// Predicted future path per body (semi-implicit Euler on a copy of the state).
	// First point of each path is the current position. StepDelta is clamped to >= 0.01.
	TArray<TArray<FVector>> PredictBodyPaths(float Seconds, float StepDelta) const;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "CelestialSim")
	float GravitationalConstant = 1.0f;

	static constexpr float FixedStep = 1.0f / 60.0f;

private:
	TArray<FVector> GetBodyAccelerations(const TArray<FVector>& AtPositions) const;
	FVector GetBodyAcceleration(int32 Index, const TArray<FVector>& AtPositions) const;

	bool bActive = false;
	int32 Count = 0;
	float Accumulator = 0.0f;

	TArray<FVector> Positions;
	TArray<FVector> Velocities;
	TArray<double> Masses;
	TArray<double> GravityStrengths;
	TArray<double> FalloffExponents;
	TArray<double> MaxRanges;
	TArray<double> MinRanges;
	TArray<bool> Stationary;
};
