#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "DebugFlightVisualizer.generated.h"

class ACelestialBody;
class AShip;

// Port of godot/scripts/debug_flight_visualizer.gd. Draws thrust/gravity/velocity
// arrows and predicted trajectories with debug lines. Toggled with F3 (see AShip).
// This is the main tool for verifying physics parity with the Godot original.
UCLASS()
class ORBITALDYNAMICS_API ADebugFlightVisualizer : public AActor
{
	GENERATED_BODY()

public:
	ADebugFlightVisualizer();

	UPROPERTY(EditAnywhere, Category = "Debug")
	float ForceScale = 0.04f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float GravityScale = 0.45f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float VelocityScale = 0.12f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float MinArrowLength = 0.75f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float MaxArrowLength = 5.0f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float ArrowHeadLength = 0.45f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float ArrowHeadWidth = 0.22f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float VisualHeightOffset = 0.45f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float TrajectorySeconds = 4.0f;
	UPROPERTY(EditAnywhere, Category = "Debug")
	float TrajectoryStep = 0.12f;

	TWeakObjectPtr<AShip> Ship;

	UPROPERTY()
	TArray<TObjectPtr<ACelestialBody>> CelestialBodies;

	void SetEnabled(bool bInEnabled);
	bool IsEnabled() const { return bEnabled; }

	// Predicted ship path: current gravity field + current total thrust
	// held constant, semi-implicit Euler (godot get_prediction_points).
	TArray<FVector> GetPredictionPoints() const;

	virtual void Tick(float DeltaTime) override;

private:
	void DrawThrustArrows();
	void DrawGravityArrow();
	void DrawVelocityArrow();
	void DrawTrajectory();
	void DrawBodyGravityArrows();
	void DrawBodyTrajectories();

	void DrawArrow(const FVector& Origin, const FVector& Vector, float Scale, const FColor& Color);
	void DrawLine(const FVector& From, const FVector& To, const FColor& Color);
	FVector DebugPos(const FVector& Pos) const;

	UPROPERTY(EditAnywhere, Category = "Debug")
	bool bEnabled = false;
};
