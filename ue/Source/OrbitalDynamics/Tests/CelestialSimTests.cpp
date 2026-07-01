// Port of godot/tests/test_celestial_sim.gd.

#include "../CelestialBodyData.h"
#include "../CelestialSimSubsystem.h"
#include "Engine/GameInstance.h"
#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace
{
	UCelestialBodyData* MakeBody(float Mass = 1000.0f, float GravityStrength = 1.0f,
	                             float FalloffExponent = 2.0f, float MaxRange = 80.0f,
	                             float MinRange = 0.5f)
	{
		UCelestialBodyData* Data = NewObject<UCelestialBodyData>();
		Data->Mass = Mass;
		Data->GravityStrength = GravityStrength;
		Data->FalloffExponent = FalloffExponent;
		Data->MaxRange = MaxRange;
		Data->MinRange = MinRange;
		Data->Radius = 3.0f;
		return Data;
	}

	UCelestialSimSubsystem* MakeSim()
	{
		// The subsystem's ClassWithin is UGameInstance, so give it one as outer.
		UGameInstance* GameInstance = NewObject<UGameInstance>();
		UCelestialSimSubsystem* Sim = NewObject<UCelestialSimSubsystem>(GameInstance);
		Sim->GravitationalConstant = 1.0f;
		return Sim;
	}

	constexpr EAutomationTestFlags TestFlags =
		EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext |
		EAutomationTestFlags::CommandletContext | EAutomationTestFlags::ProductFilter;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_GravityDirection,
	"OrbitalDynamics.CelestialSim.SingleBodyGravityDirection", TestFlags)
bool FCelestialSim_GravityDirection::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	Sim->InitializeBodies({ MakeBody() }, { FVector::ZeroVector }, { FVector::ZeroVector }, {});
	const FVector Gravity = Sim->GetGravityAt(FVector(10, 0, 0));
	TestTrue(TEXT("Gravity points toward the body"),
	         Gravity.GetSafeNormal().Equals(FVector(-1, 0, 0), 0.001));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_GravityMagnitude,
	"OrbitalDynamics.CelestialSim.SingleBodyGravityMagnitude", TestFlags)
bool FCelestialSim_GravityMagnitude::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	Sim->InitializeBodies({ MakeBody() }, { FVector::ZeroVector }, { FVector::ZeroVector }, {});
	// gravity_strength(1) * mass(1000) / dist(10)^2 = 10.0
	const FVector Gravity = Sim->GetGravityAt(FVector(10, 0, 0));
	TestNearlyEqual(TEXT("Gravity magnitude"), (float)Gravity.Size(), 10.0f, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_InverseSquareFalloff,
	"OrbitalDynamics.CelestialSim.InverseSquareFalloff", TestFlags)
bool FCelestialSim_InverseSquareFalloff::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	Sim->InitializeBodies({ MakeBody() }, { FVector::ZeroVector }, { FVector::ZeroVector }, {});
	const double GAt5 = Sim->GetGravityAt(FVector(5, 0, 0)).Size();
	const double GAt10 = Sim->GetGravityAt(FVector(10, 0, 0)).Size();
	TestNearlyEqual(TEXT("Inverse square ratio"), (float)(GAt5 / GAt10), 4.0f, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_MaxRangeCutoff,
	"OrbitalDynamics.CelestialSim.MaxRangeCutoff", TestFlags)
bool FCelestialSim_MaxRangeCutoff::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	Sim->InitializeBodies({ MakeBody(1000.0f, 1.0f, 2.0f, 50.0f) },
	                      { FVector::ZeroVector }, { FVector::ZeroVector }, {});
	const FVector Gravity = Sim->GetGravityAt(FVector(51, 0, 0));
	TestTrue(TEXT("Gravity beyond max range is zero"), Gravity.IsNearlyZero(0.0001));
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_MinRangeClamp,
	"OrbitalDynamics.CelestialSim.MinRangeClamp", TestFlags)
bool FCelestialSim_MinRangeClamp::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	Sim->InitializeBodies({ MakeBody(1000.0f, 1.0f, 2.0f, 80.0f, 5.0f) },
	                      { FVector::ZeroVector }, { FVector::ZeroVector }, {});
	// At distance 1.0 (< min_range 5.0) the distance is clamped to 5.0.
	const double GAt1 = Sim->GetGravityAt(FVector(1, 0, 0)).Size();
	const double GAt5 = Sim->GetGravityAt(FVector(5, 0, 0)).Size();
	TestNearlyEqual(TEXT("Gravity inside min range equals gravity at min range"),
	                (float)GAt1, (float)GAt5, 0.01f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_TwoBodyOrbitBounded,
	"OrbitalDynamics.CelestialSim.TwoBodyOrbitBounded", TestFlags)
bool FCelestialSim_TwoBodyOrbitBounded::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	UCelestialBodyData* Body = MakeBody(100.0f);
	// Godot test plane XZ -> UE plane XY: Vector3(0,0,±1) -> FVector(0,±1,0).
	Sim->InitializeBodies({ Body, Body },
	                      { FVector(-5, 0, 0), FVector(5, 0, 0) },
	                      { FVector(0, -1, 0), FVector(0, 1, 0) }, {});
	for (int32 i = 0; i < 1000; ++i)
	{
		Sim->Step(1.0f / 60.0f);
	}
	const double Dist = FVector::Dist(Sim->GetBodyPosition(0), Sim->GetBodyPosition(1));
	TestTrue(FString::Printf(TEXT("Two-body system stays bounded (dist %f)"), Dist), Dist < 200.0);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_PlaneConstraint,
	"OrbitalDynamics.CelestialSim.PlaneConstraint", TestFlags)
bool FCelestialSim_PlaneConstraint::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	// Intentionally give out-of-plane position and velocity — both must be zeroed.
	Sim->InitializeBodies({ MakeBody(100.0f) }, { FVector(0, 0, 5) }, { FVector(0, 0, 10) }, {});
	Sim->Step(1.0f / 60.0f);
	TestNearlyEqual(TEXT("Position Z constrained to 0"), (float)Sim->GetBodyPosition(0).Z, 0.0f, 0.001f);
	TestNearlyEqual(TEXT("Velocity Z zeroed"), (float)Sim->GetBodyVelocity(0).Z, 0.0f, 0.001f);
	return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_PredictBodyPaths,
	"OrbitalDynamics.CelestialSim.PredictBodyPaths", TestFlags)
bool FCelestialSim_PredictBodyPaths::RunTest(const FString&)
{
	UCelestialSimSubsystem* Sim = MakeSim();
	UCelestialBodyData* Body = MakeBody(100.0f);
	Sim->InitializeBodies({ Body, Body },
	                      { FVector(-5, 0, 0), FVector(5, 0, 0) },
	                      { FVector(0, -1, 0), FVector(0, 1, 0) }, {});

	// 1 second at 0.5 s steps -> start point + 2 predicted points.
	const TArray<TArray<FVector>> Paths = Sim->PredictBodyPaths(1.0f, 0.5f);
	TestEqual(TEXT("One path per body"), Paths.Num(), 2);
	TestEqual(TEXT("Start + 2 steps"), Paths[0].Num(), 3);
	TestTrue(TEXT("First point is the current position"),
	         Paths[0][0].Equals(Sim->GetBodyPosition(0), 0.001));
	// Prediction must not mutate the live simulation state.
	TestTrue(TEXT("Sim state untouched by prediction"),
	         Sim->GetBodyPosition(0).Equals(FVector(-5, 0, 0), 0.001));
	return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
