#include "DebugFlightVisualizer.h"

#include "CelestialBody.h"
#include "CelestialSimSubsystem.h"
#include "Components/PrimitiveComponent.h"
#include "DrawDebugHelpers.h"
#include "Ship.h"

namespace
{
	const FColor ThrustColor(51, 255, 89);
	const FColor GravityColor(64, 191, 255);
	const FColor TrajectoryColor(255, 209, 51);
	const FColor VelocityColor(255, 255, 255, 140);
	const FColor BodyGravityColor(255, 89, 242);
	const FColor BodyTrajectoryColor(255, 115, 38, 184);
}

ADebugFlightVisualizer::ADebugFlightVisualizer()
{
	PrimaryActorTick.bCanEverTick = true;
}

void ADebugFlightVisualizer::SetEnabled(bool bInEnabled)
{
	bEnabled = bInEnabled;
}

void ADebugFlightVisualizer::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (!bEnabled)
	{
		return;
	}

	if (Ship.IsValid())
	{
		DrawThrustArrows();
		DrawGravityArrow();
		DrawVelocityArrow();
		DrawTrajectory();
	}
	DrawBodyGravityArrows();
	DrawBodyTrajectories();
}

TArray<FVector> ADebugFlightVisualizer::GetPredictionPoints() const
{
	TArray<FVector> Points;
	if (!Ship.IsValid())
	{
		return Points;
	}
	const UCelestialSimSubsystem* Sim =
		GetGameInstance() ? GetGameInstance()->GetSubsystem<UCelestialSimSubsystem>() : nullptr;
	if (!Sim)
	{
		return Points;
	}

	const float Step = FMath::Max(TrajectoryStep, 0.01f);
	const int32 TotalSteps = FMath::Max(1, FMath::CeilToInt32(FMath::Max(TrajectorySeconds, Step) / Step));

	FVector Pos = Ship->GetActorLocation();
	FVector Vel = FVector::ZeroVector;
	FVector ThrustAccel = FVector::ZeroVector;
	if (const UPrimitiveComponent* Root = Cast<UPrimitiveComponent>(Ship->GetRootComponent()))
	{
		Vel = Root->GetPhysicsLinearVelocity();
		const float Mass = Root->GetMass();
		if (Mass > 0.0f)
		{
			ThrustAccel = Ship->GetDebugTotalThrustForce() / Mass;
		}
	}

	const double PlaneZ = Pos.Z;
	Points.Add(DebugPos(Pos));
	for (int32 i = 0; i < TotalSteps; ++i)
	{
		const FVector Accel = Sim->GetGravityAt(Pos) + ThrustAccel;
		Vel += Accel * Step;
		Pos += Vel * Step;
		Pos.Z = PlaneZ;
		Vel.Z = 0.0;
		Points.Add(DebugPos(Pos));
	}
	return Points;
}

void ADebugFlightVisualizer::DrawThrustArrows()
{
	for (const FThrustSample& Sample : Ship->GetDebugThrustForceSamples())
	{
		DrawArrow(DebugPos(Sample.Origin), Sample.Force, ForceScale, ThrustColor);
	}
}

void ADebugFlightVisualizer::DrawGravityArrow()
{
	DrawArrow(DebugPos(Ship->GetActorLocation()), Ship->GetDebugGravityAcceleration(), GravityScale, GravityColor);
}

void ADebugFlightVisualizer::DrawVelocityArrow()
{
	FVector Velocity = FVector::ZeroVector;
	if (const UPrimitiveComponent* Root = Cast<UPrimitiveComponent>(Ship->GetRootComponent()))
	{
		Velocity = Root->GetPhysicsLinearVelocity();
	}
	DrawArrow(DebugPos(Ship->GetActorLocation()), Velocity, VelocityScale, VelocityColor);
}

void ADebugFlightVisualizer::DrawTrajectory()
{
	const TArray<FVector> Points = GetPredictionPoints();
	for (int32 i = 0; i + 1 < Points.Num(); ++i)
	{
		DrawLine(Points[i], Points[i + 1], TrajectoryColor);
	}
}

void ADebugFlightVisualizer::DrawBodyGravityArrows()
{
	const UCelestialSimSubsystem* Sim =
		GetGameInstance() ? GetGameInstance()->GetSubsystem<UCelestialSimSubsystem>() : nullptr;
	if (!Sim)
	{
		return;
	}
	for (const ACelestialBody* Body : CelestialBodies)
	{
		if (!IsValid(Body) || Body->SimIndex < 0 || Sim->IsBodyStationary(Body->SimIndex))
		{
			continue;
		}
		DrawArrow(DebugPos(Body->GetActorLocation()),
		          Sim->GetBodyGravityAcceleration(Body->SimIndex), GravityScale, BodyGravityColor);
	}
}

void ADebugFlightVisualizer::DrawBodyTrajectories()
{
	const UCelestialSimSubsystem* Sim =
		GetGameInstance() ? GetGameInstance()->GetSubsystem<UCelestialSimSubsystem>() : nullptr;
	if (!Sim)
	{
		return;
	}
	const TArray<TArray<FVector>> BodyPaths = Sim->PredictBodyPaths(TrajectorySeconds, TrajectoryStep);
	for (const ACelestialBody* Body : CelestialBodies)
	{
		if (!IsValid(Body) || Body->SimIndex < 0 || Sim->IsBodyStationary(Body->SimIndex))
		{
			continue;
		}
		if (Body->SimIndex >= BodyPaths.Num())
		{
			continue;
		}
		const TArray<FVector>& Points = BodyPaths[Body->SimIndex];
		for (int32 i = 0; i + 1 < Points.Num(); ++i)
		{
			DrawLine(DebugPos(Points[i]), DebugPos(Points[i + 1]), BodyTrajectoryColor);
		}
	}
}

void ADebugFlightVisualizer::DrawArrow(const FVector& Origin, const FVector& Vector, float Scale, const FColor& Color)
{
	FVector Flat = Vector;
	Flat.Z = 0.0;
	if (Flat.SizeSquared() <= 0.000001)
	{
		return;
	}

	const FVector Direction = Flat.GetSafeNormal();
	const float Length = FMath::Clamp(Flat.Size() * Scale, MinArrowLength, MaxArrowLength);
	const FVector End = Origin + Direction * Length;
	// Perpendicular in the gameplay plane.
	const FVector Side(-Direction.Y, Direction.X, 0.0);
	const FVector HeadBase = End - Direction * FMath::Min(ArrowHeadLength, Length * 0.45f);

	DrawLine(Origin, End, Color);
	DrawLine(End, HeadBase + Side * ArrowHeadWidth, Color);
	DrawLine(End, HeadBase - Side * ArrowHeadWidth, Color);
}

void ADebugFlightVisualizer::DrawLine(const FVector& From, const FVector& To, const FColor& Color)
{
	DrawDebugLine(GetWorld(), From, To, Color, false, -1.0f, SDPG_Foreground, 0.03f);
}

FVector ADebugFlightVisualizer::DebugPos(const FVector& Pos) const
{
	return FVector(Pos.X, Pos.Y, Pos.Z + VisualHeightOffset);
}
