#pragma once

#include "CoreMinimal.h"
#include "Engine/DataAsset.h"
#include "ShipTypes.h"
#include "HullData.generated.h"

// Port of godot/scripts/hull_data.gd + resources/hulls/rectangular.tres.
// Defaults mirror the "rectangular" hull with coordinates converted to the
// UE convention (forward +X, right +Y, up +Z; mount yaw = 180 - godot yaw).
UCLASS(BlueprintType)
class ORBITALDYNAMICS_API UHullData : public UPrimaryDataAsset
{
	GENERATED_BODY()

public:
	UHullData()
	{
		FMountSlot Front;
		Front.Binding = EMountBinding::Front;
		Front.Transform = FTransform(FRotator(0, 0, 0), FVector(0.9, 0, 0));

		FMountSlot Rear;
		Rear.Binding = EMountBinding::Rear;
		Rear.Transform = FTransform(FRotator(0, 180, 0), FVector(-0.9, 0, 0));

		FMountSlot Left;
		Left.Binding = EMountBinding::Left;
		Left.Transform = FTransform(FRotator(0, 90, 0), FVector(0, -1, 0));

		FMountSlot Right;
		Right.Binding = EMountBinding::Right;
		Right.Transform = FTransform(FRotator(0, -90, 0), FVector(0, 1, 0));

		Mounts = { Front, Rear, Left, Right };
	}

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull")
	float DryMass = 10.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull")
	float MaxInternalFuel = 200.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull")
	TArray<FMountSlot> Mounts;

	// Collision box half-extents (godot box 1.5 x 0.801 x 1.5 -> UE 1.5 x 1.5 x 0.8).
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull|Collision")
	FVector CollisionBoxExtent = FVector(0.75, 0.75, 0.4);

	// godot rectangular.tres: box rotated 45 deg around up, lifted ~0.1 m.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull|Collision")
	FTransform CollisionTransform = FTransform(FRotator(0, -45, 0), FVector(0, 0, 0.0996));

	// Placeholder visual until the UE art pass; the real hull mesh is out of scope.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Hull|Visual")
	TObjectPtr<UStaticMesh> Mesh;

	const FMountSlot* GetMount(EMountBinding Binding) const
	{
		return Mounts.FindByPredicate([Binding](const FMountSlot& S) { return S.Binding == Binding; });
	}
};
