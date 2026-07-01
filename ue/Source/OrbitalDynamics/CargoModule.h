#pragma once

#include "CoreMinimal.h"
#include "ShipModule.h"
#include "CargoModule.generated.h"

class UStaticMeshComponent;

// Port of godot/scripts/cargo_module.gd: ballast that shifts the center of mass.
UCLASS()
class ORBITALDYNAMICS_API ACargoModule : public AShipModule
{
	GENERATED_BODY()

public:
	ACargoModule();

	virtual float GetMass() const override;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Cargo")
	TObjectPtr<UStaticMeshComponent> PlaceholderMesh;
};
