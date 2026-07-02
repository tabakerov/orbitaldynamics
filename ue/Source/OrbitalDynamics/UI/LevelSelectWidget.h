#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "LevelSelectWidget.generated.h"

class UIndexedButton;
class UVerticalBox;

// Port of godot/scripts/level_select.gd: "Level N" buttons + Restart + Quit.
UCLASS()
class ORBITALDYNAMICS_API ULevelSelectWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	TFunction<void(int32)> OnLevelSelected;
	TFunction<void()> OnRestartRequested;
	TFunction<void()> OnQuitRequested;
	// Escape / gamepad B while a level is active: close the menu.
	TFunction<void()> OnCancel;

	void ShowMenu(int32 LevelCount, bool bHasActiveLevel);

	virtual bool Initialize() override;
	virtual FReply NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;

private:
	void BuildTree();
	UIndexedButton* MakeButton(const FText& Label, TFunction<void()> Callback);

	UPROPERTY()
	TObjectPtr<UVerticalBox> ButtonList;

	UPROPERTY()
	TArray<TObjectPtr<UIndexedButton>> Buttons;

	TArray<TFunction<void()>> ButtonCallbacks;
	bool bCancelAllowed = false;
};
