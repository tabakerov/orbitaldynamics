#pragma once

#include "CoreMinimal.h"
#include "ShipTypes.generated.h"

// Port of godot/scripts/mount_slot.gd.
UENUM(BlueprintType)
enum class EMountBinding : uint8
{
	Front,
	Rear,
	Left,
	Right,
};

USTRUCT(BlueprintType)
struct FMountSlot
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mount")
	EMountBinding Binding = EMountBinding::Front;

	// Ship-local transform of the slot. Convention (see UE5_PORT_SPEC §3):
	// ship forward = +X, right = +Y, up = +Z; module thrust = -module forward.
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Mount")
	FTransform Transform = FTransform::Identity;
};

namespace MountBinding
{
	inline const TCHAR* Name(EMountBinding Binding)
	{
		switch (Binding)
		{
		case EMountBinding::Front: return TEXT("Front");
		case EMountBinding::Rear: return TEXT("Rear");
		case EMountBinding::Left: return TEXT("Left");
		case EMountBinding::Right: return TEXT("Right");
		}
		return TEXT("Unknown");
	}

	inline constexpr EMountBinding All[] = {
		EMountBinding::Front, EMountBinding::Rear, EMountBinding::Left, EMountBinding::Right,
	};
}
