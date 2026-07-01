#include "CelestialSimSubsystem.h"

#include "CelestialBodyData.h"
#include "Engine/World.h"

void UCelestialSimSubsystem::Tick(float DeltaTime)
{
	if (!bActive || Count <= 0)
	{
		return;
	}
	if (const UWorld* World = GetGameInstance() ? GetGameInstance()->GetWorld() : nullptr)
	{
		if (World->IsPaused())
		{
			return;
		}
	}

	// Fixed-step accumulator; cap to avoid a death spiral after a long hitch.
	Accumulator += FMath::Min(DeltaTime, 0.25f);
	while (Accumulator >= FixedStep)
	{
		Step(FixedStep);
		Accumulator -= FixedStep;
	}
}

void UCelestialSimSubsystem::InitializeBodies(const TArray<UCelestialBodyData*>& Data,
                                              const TArray<FVector>& InPositions,
                                              const TArray<FVector>& InVelocities,
                                              const TArray<bool>& InStationary)
{
	Count = Data.Num();
	Positions = InPositions;
	Velocities = InVelocities;
	Masses.Reset();
	GravityStrengths.Reset();
	FalloffExponents.Reset();
	MaxRanges.Reset();
	MinRanges.Reset();
	Stationary.Reset();

	for (int32 i = 0; i < Count; ++i)
	{
		const UCelestialBodyData* D = Data[i];
		Masses.Add(D ? D->Mass : 0.0);
		GravityStrengths.Add(D ? D->GravityStrength : 0.0);
		FalloffExponents.Add(D ? D->FalloffExponent : 2.0);
		MaxRanges.Add(D ? D->MaxRange : 0.0);
		MinRanges.Add(D ? D->MinRange : 0.0);
		Stationary.Add(InStationary.IsValidIndex(i) ? InStationary[i] : false);
	}

	Accumulator = 0.0f;
	bActive = true;
}

void UCelestialSimSubsystem::Clear()
{
	bActive = false;
	Count = 0;
	Accumulator = 0.0f;
	Positions.Reset();
	Velocities.Reset();
	Masses.Reset();
	GravityStrengths.Reset();
	FalloffExponents.Reset();
	MaxRanges.Reset();
	MinRanges.Reset();
	Stationary.Reset();
}

void UCelestialSimSubsystem::Step(float Delta)
{
	const TArray<FVector> Accels = GetBodyAccelerations(Positions);

	// Symplectic Euler: velocity first, then position.
	for (int32 i = 0; i < Count; ++i)
	{
		if (Stationary[i])
		{
			continue;
		}
		Velocities[i] += Accels[i] * Delta;
		Positions[i] += Velocities[i] * Delta;
		// Enforce the Z=0 gameplay plane (Y=0 in Godot).
		Positions[i].Z = 0.0;
		Velocities[i].Z = 0.0;
	}
}

FVector UCelestialSimSubsystem::GetGravityAt(const FVector& Pos) const
{
	FVector Total = FVector::ZeroVector;
	for (int32 i = 0; i < Count; ++i)
	{
		const FVector Offset = Positions[i] - Pos;
		const double RawDist = Offset.Size();
		if (RawDist > MaxRanges[i])
		{
			continue;
		}
		const double Dist = FMath::Clamp(RawDist, MinRanges[i], MaxRanges[i]);
		const double Strength = GravityStrengths[i] * Masses[i] / FMath::Pow(Dist, FalloffExponents[i]);
		Total += Offset.GetSafeNormal() * Strength;
	}
	return Total;
}

FVector UCelestialSimSubsystem::GetBodyPosition(int32 Index) const
{
	return Positions.IsValidIndex(Index) ? Positions[Index] : FVector::ZeroVector;
}

FVector UCelestialSimSubsystem::GetBodyVelocity(int32 Index) const
{
	return Velocities.IsValidIndex(Index) ? Velocities[Index] : FVector::ZeroVector;
}

FVector UCelestialSimSubsystem::GetBodyGravityAcceleration(int32 Index) const
{
	if (Index < 0 || Index >= Count)
	{
		return FVector::ZeroVector;
	}
	return GetBodyAcceleration(Index, Positions);
}

bool UCelestialSimSubsystem::IsBodyStationary(int32 Index) const
{
	if (Index < 0 || Index >= Count)
	{
		return true;
	}
	return Stationary[Index];
}

TArray<TArray<FVector>> UCelestialSimSubsystem::PredictBodyPaths(float Seconds, float StepDelta) const
{
	TArray<TArray<FVector>> Paths;
	Paths.SetNum(Count);
	for (int32 i = 0; i < Count; ++i)
	{
		Paths[i].Add(Positions[i]);
	}
	if (Count <= 0)
	{
		return Paths;
	}

	const float Step = FMath::Max(StepDelta, 0.01f);
	const int32 TotalSteps = FMath::Max(1, FMath::CeilToInt32(FMath::Max(Seconds, Step) / Step));

	TArray<FVector> SimPositions = Positions;
	TArray<FVector> SimVelocities = Velocities;

	for (int32 StepIdx = 0; StepIdx < TotalSteps; ++StepIdx)
	{
		const TArray<FVector> Accels = GetBodyAccelerations(SimPositions);
		for (int32 i = 0; i < Count; ++i)
		{
			if (!Stationary[i])
			{
				SimVelocities[i] += Accels[i] * Step;
				SimPositions[i] += SimVelocities[i] * Step;
				SimPositions[i].Z = 0.0;
				SimVelocities[i].Z = 0.0;
			}
			Paths[i].Add(SimPositions[i]);
		}
	}
	return Paths;
}

TArray<FVector> UCelestialSimSubsystem::GetBodyAccelerations(const TArray<FVector>& AtPositions) const
{
	TArray<FVector> Accels;
	Accels.Init(FVector::ZeroVector, Count);

	for (int32 i = 0; i < Count; ++i)
	{
		for (int32 j = i + 1; j < Count; ++j)
		{
			const FVector Offset = AtPositions[j] - AtPositions[i];
			const double Dist = Offset.Size();
			if (Dist < 0.001)
			{
				continue;
			}
			const FVector Dir = Offset / Dist;
			const double AccelOnI = GravitationalConstant * Masses[j] / (Dist * Dist);
			const double AccelOnJ = GravitationalConstant * Masses[i] / (Dist * Dist);
			Accels[i] += Dir * AccelOnI;
			Accels[j] -= Dir * AccelOnJ;
		}
	}
	return Accels;
}

FVector UCelestialSimSubsystem::GetBodyAcceleration(int32 Index, const TArray<FVector>& AtPositions) const
{
	FVector Accel = FVector::ZeroVector;
	for (int32 i = 0; i < Count; ++i)
	{
		if (i == Index)
		{
			continue;
		}
		const FVector Offset = AtPositions[i] - AtPositions[Index];
		const double Dist = Offset.Size();
		if (Dist < 0.001)
		{
			continue;
		}
		Accel += Offset.GetSafeNormal() * (GravitationalConstant * Masses[i] / (Dist * Dist));
	}
	return Accel;
}
