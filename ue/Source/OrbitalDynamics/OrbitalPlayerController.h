#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "OrbitalPlayerController.generated.h"

class ALevelManager;
class AShip;
class AStation;
class ULevelSelectWidget;
class UModalOverlayWidget;
class UShipHUDWidget;
class UShipModifierScreenWidget;

// Port of the UI/flow half of godot/scripts/main.gd: HUD lifetime, the
// intro/crash/completion overlays, pause menu with level select, and the
// station dock -> ship modifier screen loop.
//
// Note: Escape is intercepted by PIE in the editor; P and gamepad Back
// open the menu as well.
UCLASS()
class ORBITALDYNAMICS_API AOrbitalPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	AOrbitalPlayerController();

	virtual void BeginPlay() override;
	virtual void Tick(float DeltaTime) override;

protected:
	UFUNCTION()
	void HandleLevelCompleted();

	UFUNCTION()
	void HandleShipCrashed(FVector CrashPosition);

	UFUNCTION()
	void HandleShipEnteredStation(AShip* Ship, AStation* Station);

	UFUNCTION()
	void HandleShipExitedStation(AShip* Ship, AStation* Station);

private:
	enum class EUIState : uint8 { Playing, Intro, Crash, Completion, Menu, Modifier };

	static constexpr float CrashOverlayDelaySeconds = 2.0f;

	void EnsureHUDSetup();

	void ShowIntroIfConfigured();
	void ContinueFromIntro();
	void ShowCrashOverlay();
	void ShowCompletionOverlay();
	void ShowMenu();
	void CloseMenu();
	void OpenModifierScreen();
	void HandleModifierClosed();

	void ResumePlaying();
	void SetPausedWithUI(bool bPaused);

	void RequestRestart();
	void RequestLoadLevel(int32 Index);
	void RequestNextLevel();
	void RequestQuit();

	bool WasMenuKeyJustPressed() const;
	bool WasDockKeyJustPressed() const;

	EUIState UIState = EUIState::Playing;

	UPROPERTY()
	TObjectPtr<UShipHUDWidget> HUD;

	UPROPERTY()
	TObjectPtr<UModalOverlayWidget> Overlay;

	UPROPERTY()
	TObjectPtr<ULevelSelectWidget> LevelSelect;

	UPROPERTY()
	TObjectPtr<UShipModifierScreenWidget> ModifierScreen;

	TWeakObjectPtr<ALevelManager> LevelManager;
	TWeakObjectPtr<AStation> CurrentStation;

	FTimerHandle CrashOverlayTimer;
	bool bHUDSetup = false;
	bool bIntroShown = false;
};
