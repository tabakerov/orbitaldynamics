#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "CameraRig.generated.h"

class UCameraComponent;

// Port of godot/scripts/camera_rig.gd: follows the ship's XY position and yaw
// so the ship always points "up" on screen; the camera child holds the height.
UCLASS()
class ORBITALDYNAMICS_API ACameraRig : public AActor
{
	GENERATED_BODY()

public:
	ACameraRig();

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Camera")
	TObjectPtr<AActor> Target;

	void SetTarget(AActor* NewTarget);

	virtual void Tick(float DeltaTime) override;

protected:
	UPROPERTY(VisibleAnywhere, Category = "Camera")
	TObjectPtr<UCameraComponent> Camera;

private:
	void SnapToTarget();
	void EnsureViewTarget();
	bool bViewTargetSet = false;
};
