#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "ModalOverlayWidget.generated.h"

class UIndexedButton;
class UTextBlock;
class UVerticalBox;

// Generic full-screen modal: dimmed background, optional title, message and a
// column of buttons. Backs the intro / crash / completion overlays that
// godot/scripts/main.gd built in code.
UCLASS()
class ORBITALDYNAMICS_API UModalOverlayWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	struct FButtonSpec
	{
		FText Label;
		TFunction<void()> OnClicked;
		bool bEnabled = true;
	};

	void Configure(const FLinearColor& BackgroundColor, const FText& Title, const FText& Message,
	               const TArray<FButtonSpec>& Buttons, int32 FocusButtonIndex = 0);

	// Escape / gamepad B.
	TFunction<void()> OnCancel;
	// Extra keys (e.g. R on the crash overlay). Return true if handled.
	TFunction<bool(const FKey&)> ExtraKeyHandler;
	// Auto-close: invokes the callback after Seconds of real time (ticks while paused).
	void SetAutoContinue(float Seconds, TFunction<void()> Callback);

	void FocusDefaultButton();

	virtual bool Initialize() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;
	virtual FReply NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;

private:
	void BuildTree();

	UPROPERTY()
	TObjectPtr<class UBorder> Background;

	UPROPERTY()
	TObjectPtr<UTextBlock> TitleText;

	UPROPERTY()
	TObjectPtr<UTextBlock> MessageText;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ButtonBox;

	UPROPERTY()
	TArray<TObjectPtr<UIndexedButton>> Buttons;

	TArray<TFunction<void()>> ButtonCallbacks;
	int32 DefaultFocusIndex = 0;

	float AutoContinueRemaining = 0.0f;
	TFunction<void()> AutoContinueCallback;
};
