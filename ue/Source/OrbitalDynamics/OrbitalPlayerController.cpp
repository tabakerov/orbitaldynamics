#include "OrbitalPlayerController.h"

#include "Blueprint/UserWidget.h"
#include "EngineUtils.h"
#include "Kismet/GameplayStatics.h"
#include "Kismet/KismetSystemLibrary.h"
#include "LevelManager.h"
#include "OrbitalGameInstance.h"
#include "Ship.h"
#include "Station.h"
#include "UI/LevelSelectWidget.h"
#include "UI/ModalOverlayWidget.h"
#include "UI/ShipHUDWidget.h"
#include "UI/ShipModifierScreenWidget.h"

AOrbitalPlayerController::AOrbitalPlayerController()
{
	// Poll menu/dock keys and manage overlays while the game is paused.
	PrimaryActorTick.bTickEvenWhenPaused = true;

	HUDWidgetClass = UShipHUDWidget::StaticClass();
	OverlayWidgetClass = UModalOverlayWidget::StaticClass();
	LevelSelectWidgetClass = ULevelSelectWidget::StaticClass();
	ModifierScreenWidgetClass = UShipModifierScreenWidget::StaticClass();
}

void AOrbitalPlayerController::BeginPlay()
{
	Super::BeginPlay();

	if (!IsLocalController())
	{
		return;
	}

	HUD = CreateWidget<UShipHUDWidget>(this, HUDWidgetClass);
	HUD->AddToViewport(0);
	HUD->SetVisibility(ESlateVisibility::SelfHitTestInvisible);

	Overlay = CreateWidget<UModalOverlayWidget>(this, OverlayWidgetClass);
	Overlay->AddToViewport(10);
	Overlay->SetVisibility(ESlateVisibility::Collapsed);

	LevelSelect = CreateWidget<ULevelSelectWidget>(this, LevelSelectWidgetClass);
	LevelSelect->AddToViewport(20);
	LevelSelect->SetVisibility(ESlateVisibility::Collapsed);
	LevelSelect->OnLevelSelected = [this](int32 Index) { RequestLoadLevel(Index); };
	LevelSelect->OnRestartRequested = [this]() { RequestRestart(); };
	LevelSelect->OnQuitRequested = [this]() { RequestQuit(); };
	LevelSelect->OnCancel = [this]() { CloseMenu(); };

	ModifierScreen = CreateWidget<UShipModifierScreenWidget>(this, ModifierScreenWidgetClass);
	ModifierScreen->AddToViewport(30);
	ModifierScreen->OnClosed = [this]() { HandleModifierClosed(); };

	TActorIterator<ALevelManager> It(GetWorld());
	if (It)
	{
		LevelManager = *It;
		LevelManager->OnLevelCompleted.AddDynamic(this, &AOrbitalPlayerController::HandleLevelCompleted);
		LevelManager->OnShipCrashed.AddDynamic(this, &AOrbitalPlayerController::HandleShipCrashed);
	}

	for (TActorIterator<AStation> StationIt(GetWorld()); StationIt; ++StationIt)
	{
		StationIt->OnShipEnteredRange.AddDynamic(this, &AOrbitalPlayerController::HandleShipEnteredStation);
		StationIt->OnShipExitedRange.AddDynamic(this, &AOrbitalPlayerController::HandleShipExitedStation);
	}

	ShowIntroIfConfigured();
}

void AOrbitalPlayerController::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (!IsLocalController())
	{
		return;
	}

	EnsureHUDSetup();

	if (UIState == EUIState::Playing)
	{
		if (WasMenuKeyJustPressed())
		{
			ShowMenu();
		}
		else if (CurrentStation.IsValid() && WasDockKeyJustPressed())
		{
			OpenModifierScreen();
		}
	}
}

void AOrbitalPlayerController::EnsureHUDSetup()
{
	if (bHUDSetup || !HUD)
	{
		return;
	}
	AShip* Ship = Cast<AShip>(GetPawn());
	if (!Ship)
	{
		return;
	}
	HUD->Setup(Ship, LevelManager.Get());
	bHUDSetup = true;
}

void AOrbitalPlayerController::ShowIntroIfConfigured()
{
	if (bIntroShown || !LevelManager.IsValid() || LevelManager->IntroMessage.IsEmpty())
	{
		return;
	}
	bIntroShown = true;
	UIState = EUIState::Intro;

	const float Timeout = FMath::Max(LevelManager->IntroTimeoutSeconds, 0.0f);
	const bool bShowButton = LevelManager->bIntroShowContinueButton || FMath::IsNearlyZero(Timeout);
	FText ButtonText = LevelManager->IntroContinueButtonText;
	if (ButtonText.IsEmpty())
	{
		ButtonText = FText::FromString(TEXT("Продолжить"));
	}

	TArray<UModalOverlayWidget::FButtonSpec> Buttons;
	if (bShowButton)
	{
		UModalOverlayWidget::FButtonSpec Continue;
		Continue.Label = ButtonText;
		Continue.OnClicked = [this]() { ContinueFromIntro(); };
		Buttons.Add(Continue);
	}

	HUD->SetVisibility(ESlateVisibility::Collapsed);
	Overlay->Configure(FLinearColor(0.015f, 0.025f, 0.055f, 0.82f), FText::GetEmpty(),
	                   LevelManager->IntroMessage, Buttons);
	Overlay->OnCancel = [this]() { ShowMenu(); };
	Overlay->ExtraKeyHandler = nullptr;
	if (Timeout > 0.0f)
	{
		Overlay->SetAutoContinue(Timeout, [this]() { ContinueFromIntro(); });
	}
	Overlay->SetVisibility(ESlateVisibility::Visible);
	Overlay->FocusDefaultButton();
	SetPausedWithUI(true);
}

void AOrbitalPlayerController::ContinueFromIntro()
{
	if (UIState != EUIState::Intro)
	{
		return;
	}
	ResumePlaying();
}

void AOrbitalPlayerController::HandleLevelCompleted()
{
	// Same guards as main.gd: ignore while another overlay is up.
	if (UIState != EUIState::Playing)
	{
		return;
	}
	ShowCompletionOverlay();
}

void AOrbitalPlayerController::HandleShipCrashed(FVector CrashPosition)
{
	if (UIState != EUIState::Playing)
	{
		return;
	}
	// Visual-layer hook: the crash explosion would spawn at CrashPosition here.
	HUD->SetVisibility(ESlateVisibility::Collapsed);
	GetWorldTimerManager().SetTimer(CrashOverlayTimer, this, &AOrbitalPlayerController::ShowCrashOverlay,
	                                CrashOverlayDelaySeconds, false);
}

void AOrbitalPlayerController::ShowCrashOverlay()
{
	if (UIState != EUIState::Playing)
	{
		return;
	}
	UIState = EUIState::Crash;

	TArray<UModalOverlayWidget::FButtonSpec> Buttons;
	UModalOverlayWidget::FButtonSpec Restart;
	Restart.Label = FText::FromString(TEXT("Перезапустить уровень"));
	Restart.OnClicked = [this]() { RequestRestart(); };
	Buttons.Add(Restart);
	UModalOverlayWidget::FButtonSpec Menu;
	Menu.Label = FText::FromString(TEXT("В главное меню"));
	Menu.OnClicked = [this]() { ShowMenu(); };
	Buttons.Add(Menu);

	Overlay->Configure(FLinearColor(0.03f, 0.01f, 0.01f, 0.78f),
	                   FText::FromString(TEXT("вы разбились")),
	                   FText::FromString(TEXT("Перезапустить уровень или выйти в главное меню?")), Buttons);
	Overlay->OnCancel = [this]() { ShowMenu(); };
	Overlay->ExtraKeyHandler = [this](const FKey& Key)
	{
		if (Key == EKeys::R || Key == EKeys::Gamepad_Special_Right)
		{
			RequestRestart();
			return true;
		}
		return false;
	};
	Overlay->SetVisibility(ESlateVisibility::Visible);
	Overlay->FocusDefaultButton();
	SetPausedWithUI(true);
}

void AOrbitalPlayerController::ShowCompletionOverlay()
{
	UIState = EUIState::Completion;

	UOrbitalGameInstance* GI = GetGameInstance<UOrbitalGameInstance>();
	const bool bHasNext = GI && GI->HasNextLevel();

	TArray<UModalOverlayWidget::FButtonSpec> Buttons;
	UModalOverlayWidget::FButtonSpec Next;
	Next.Label = FText::FromString(TEXT("следующий"));
	Next.bEnabled = bHasNext;
	Next.OnClicked = [this]() { RequestNextLevel(); };
	Buttons.Add(Next);
	UModalOverlayWidget::FButtonSpec Menu;
	Menu.Label = FText::FromString(TEXT("в меню"));
	Menu.OnClicked = [this]() { ShowMenu(); };
	Buttons.Add(Menu);

	HUD->SetVisibility(ESlateVisibility::Collapsed);
	Overlay->Configure(FLinearColor(0.01f, 0.04f, 0.05f, 0.82f),
	                   FText::FromString(TEXT("уровень завершён")), FText::GetEmpty(),
	                   Buttons, bHasNext ? 0 : 1);
	Overlay->OnCancel = [this]() { ShowMenu(); };
	Overlay->ExtraKeyHandler = nullptr;
	Overlay->SetVisibility(ESlateVisibility::Visible);
	Overlay->FocusDefaultButton();
	SetPausedWithUI(true);
}

void AOrbitalPlayerController::ShowMenu()
{
	GetWorldTimerManager().ClearTimer(CrashOverlayTimer);
	UIState = EUIState::Menu;

	Overlay->SetVisibility(ESlateVisibility::Collapsed);
	HUD->SetVisibility(ESlateVisibility::Collapsed);
	if (ModifierScreen->IsOpen())
	{
		ModifierScreen->SetVisibility(ESlateVisibility::Collapsed);
	}

	const UOrbitalGameInstance* GI = GetGameInstance<UOrbitalGameInstance>();
	LevelSelect->ShowMenu(GI ? GI->GetLevelCount() : 0, /*bHasActiveLevel*/ true);
	SetPausedWithUI(true);
}

void AOrbitalPlayerController::CloseMenu()
{
	if (UIState != EUIState::Menu)
	{
		return;
	}
	LevelSelect->SetVisibility(ESlateVisibility::Collapsed);
	ResumePlaying();
}

void AOrbitalPlayerController::OpenModifierScreen()
{
	AShip* Ship = Cast<AShip>(GetPawn());
	if (!Ship || !CurrentStation.IsValid())
	{
		return;
	}
	UIState = EUIState::Modifier;
	HUD->HideDockPrompt();
	ModifierScreen->Open(CurrentStation.Get(), Ship);
	SetPausedWithUI(true);
}

void AOrbitalPlayerController::HandleModifierClosed()
{
	if (UIState != EUIState::Modifier)
	{
		return;
	}
	ResumePlaying();
	if (CurrentStation.IsValid())
	{
		HUD->ShowDockPrompt(CurrentStation->GetDisplayName());
	}
}

void AOrbitalPlayerController::ResumePlaying()
{
	UIState = EUIState::Playing;
	Overlay->SetVisibility(ESlateVisibility::Collapsed);
	LevelSelect->SetVisibility(ESlateVisibility::Collapsed);
	HUD->SetVisibility(ESlateVisibility::SelfHitTestInvisible);
	SetPausedWithUI(false);
	if (AShip* Ship = Cast<AShip>(GetPawn()))
	{
		Ship->ResetInputState();
	}
}

void AOrbitalPlayerController::SetPausedWithUI(bool bPaused)
{
	UGameplayStatics::SetGamePaused(this, bPaused);
	bShowMouseCursor = bPaused;
	if (bPaused)
	{
		SetInputMode(FInputModeGameAndUI().SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock));
	}
	else
	{
		SetInputMode(FInputModeGameOnly());
	}
}

void AOrbitalPlayerController::HandleShipEnteredStation(AShip*, AStation* Station)
{
	if (ModifierScreen && ModifierScreen->IsOpen())
	{
		return;
	}
	CurrentStation = Station;
	if (HUD && Station)
	{
		HUD->ShowDockPrompt(Station->GetDisplayName());
	}
}

void AOrbitalPlayerController::HandleShipExitedStation(AShip*, AStation* Station)
{
	if (Station != CurrentStation.Get())
	{
		return;
	}
	if (ModifierScreen && ModifierScreen->IsOpen())
	{
		return;
	}
	CurrentStation = nullptr;
	if (HUD)
	{
		HUD->HideDockPrompt();
	}
}

void AOrbitalPlayerController::RequestRestart()
{
	if (UOrbitalGameInstance* GI = GetGameInstance<UOrbitalGameInstance>())
	{
		GI->RestartLevel(this);
	}
}

void AOrbitalPlayerController::RequestLoadLevel(int32 Index)
{
	if (UOrbitalGameInstance* GI = GetGameInstance<UOrbitalGameInstance>())
	{
		GI->LoadLevel(this, Index);
	}
}

void AOrbitalPlayerController::RequestNextLevel()
{
	if (UOrbitalGameInstance* GI = GetGameInstance<UOrbitalGameInstance>())
	{
		GI->LoadNextLevel(this);
	}
}

void AOrbitalPlayerController::RequestQuit()
{
	UKismetSystemLibrary::QuitGame(this, this, EQuitPreference::Quit, false);
}

bool AOrbitalPlayerController::WasMenuKeyJustPressed() const
{
	return WasInputKeyJustPressed(EKeys::Escape) || WasInputKeyJustPressed(EKeys::P) ||
	       WasInputKeyJustPressed(EKeys::Gamepad_Special_Left);
}

bool AOrbitalPlayerController::WasDockKeyJustPressed() const
{
	return WasInputKeyJustPressed(EKeys::F) || WasInputKeyJustPressed(EKeys::Gamepad_LeftShoulder);
}
