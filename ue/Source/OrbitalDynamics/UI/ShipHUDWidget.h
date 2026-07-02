#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "ShipHUDWidget.generated.h"

class ALevelManager;
class AShip;
class ATargetZone;
class UProgressBar;
class UTextBlock;

// Port of godot/scripts/hud.gd: fuel bar + label, dock prompt, off-screen
// target indicator and the auto-framing minimap (both drawn in NativePaint).
UCLASS()
class ORBITALDYNAMICS_API UShipHUDWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void Setup(AShip* InShip, ALevelManager* InLevelManager);

	void ShowDockPrompt(const FText& StationName);
	void HideDockPrompt();

	virtual bool Initialize() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;
	virtual int32 NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry,
	                          const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
	                          int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const override;

private:
	UFUNCTION()
	void HandleFuelChanged(float Current, float Maximum);

	void BuildTree();

	int32 PaintMinimap(const FGeometry& Geometry, FSlateWindowElementList& OutDrawElements, int32 LayerId) const;
	int32 PaintTargetIndicator(const FGeometry& Geometry, FSlateWindowElementList& OutDrawElements, int32 LayerId) const;

	// Gameplay plane -> minimap plane: godot drew (x_godot, z_godot); with our
	// coordinate mapping that is (UE Y, -UE X), which keeps ship-forward = map-up.
	static FVector2D WorldToPlane(const FVector& World) { return FVector2D(World.Y, -World.X); }

	UPROPERTY()
	TObjectPtr<UProgressBar> FuelBar;

	UPROPERTY()
	TObjectPtr<UTextBlock> FuelLabel;

	UPROPERTY()
	TObjectPtr<UTextBlock> DockPrompt;

	TWeakObjectPtr<AShip> Ship;
	TWeakObjectPtr<ALevelManager> LevelManager;
	TWeakObjectPtr<ATargetZone> Target;
};
