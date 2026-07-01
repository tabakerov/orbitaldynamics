#pragma once

#include "CoreMinimal.h"
#include "CelestialBody.h"
#include "BlackHole.generated.h"

// Port of godot/scripts/black_hole.gd, gameplay part only.
// Gravity and collision come from ACelestialBody; the lensing visual is out of scope.
// The distinct class exists so UI (minimap) and future visuals can tell it apart.
UCLASS()
class ORBITALDYNAMICS_API ABlackHole : public ACelestialBody
{
	GENERATED_BODY()
};
