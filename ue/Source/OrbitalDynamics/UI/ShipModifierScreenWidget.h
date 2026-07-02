#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "../ShipTypes.h"
#include "ShipModifierScreenWidget.generated.h"

class AShip;
class AStation;
class UBorder;
class UModuleProfile;
class UTextBlock;
class UVerticalBox;

// Port of godot/scripts/ship_modifier_screen.gd. Two states: pick a mount slot
// (arrow keys / d-pad select by direction), then pick a module from the
// station's list; the last list entry removes the module. Keyboard/gamepad only.
UCLASS()
class ORBITALDYNAMICS_API UShipModifierScreenWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	TFunction<void()> OnClosed;

	void Open(AStation* InStation, AShip* InShip);
	void Close();
	bool IsOpen() const { return GetVisibility() == ESlateVisibility::Visible; }

	virtual bool Initialize() override;
	virtual FReply NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent) override;

private:
	enum class EState : uint8 { PickMount, PickModule };

	void BuildTree();
	void MakeChip(EMountBinding Binding, const FVector2D& TopLeft, const FVector2D& BottomRight);

	void RefreshChips();
	FText ChipText(EMountBinding Binding) const;
	static FText ChipName(EMountBinding Binding);
	static FText ModuleDisplayName(const UModuleProfile* Profile);

	void HandlePickMountKey(const FKey& Key);
	void HandlePickModuleKey(const FKey& Key);

	void EnterModulePick();
	void ExitModulePick();
	void BuildModuleList();
	int32 FindCurrentModuleIndex() const;
	void StepModule(int32 Delta);
	void RefreshModuleHighlight();
	void ApplySelectedModule();
	void RefreshHelp();

	EState State = EState::PickMount;
	EMountBinding SelectedBinding = EMountBinding::Front;
	int32 SelectedModuleIndex = 0;

	TWeakObjectPtr<AStation> Station;
	TWeakObjectPtr<AShip> Ship;

	UPROPERTY()
	TObjectPtr<UTextBlock> SubtitleText;

	UPROPERTY()
	TObjectPtr<UTextBlock> HelpText;

	UPROPERTY()
	TObjectPtr<UBorder> ModuleListPanel;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ModuleListBox;

	UPROPERTY()
	TMap<EMountBinding, TObjectPtr<UBorder>> ChipPanels;

	UPROPERTY()
	TMap<EMountBinding, TObjectPtr<UTextBlock>> ChipLabels;

	UPROPERTY()
	TArray<TObjectPtr<UTextBlock>> ModuleItems;

	UPROPERTY()
	TArray<TObjectPtr<UModuleProfile>> ModuleItemProfiles;
};
