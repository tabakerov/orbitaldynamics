#include "ShipModifierScreenWidget.h"

#include "../ModuleProfiles.h"
#include "../Ship.h"
#include "../ShipLoadout.h"
#include "../Station.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Styling/CoreStyle.h"

namespace ModifierStyle
{
	const FLinearColor ScreenBackground(0.015f, 0.025f, 0.055f, 0.92f);
	const FLinearColor ChipBackground(0.08f, 0.08f, 0.14f, 0.92f);
	const FLinearColor ChipSelected(1.0f, 0.7f, 0.2f, 1.0f);
	const FLinearColor TextNormal(0.9f, 0.9f, 0.95f, 1.0f);
	const FLinearColor TextSelected(1.0f, 0.85f, 0.3f, 1.0f);
	const FLinearColor HullBackground(0.18f, 0.32f, 0.7f, 0.9f);
	const FLinearColor ListBackground(0.05f, 0.08f, 0.15f, 0.96f);
	const FLinearColor Accent(0.95f, 0.6f, 1.0f, 1.0f);
}

bool UShipModifierScreenWidget::Initialize()
{
	const bool bOk = Super::Initialize();
	if (bOk && WidgetTree && !WidgetTree->RootWidget)
	{
		SetIsFocusable(true);
		BuildTree();
		SetVisibility(ESlateVisibility::Collapsed);
	}
	return bOk;
}

void UShipModifierScreenWidget::BuildTree()
{
	using namespace ModifierStyle;

	UCanvasPanel* Canvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("Canvas"));
	WidgetTree->RootWidget = Canvas;

	UBorder* Background = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Background"));
	Background->SetBrushColor(ScreenBackground);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(Background))
	{
		Slot->SetAnchors(FAnchors(0, 0, 1, 1));
		Slot->SetOffsets(FMargin(0));
	}

	UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Title"));
	Title->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 36));
	Title->SetColorAndOpacity(FSlateColor(Accent));
	Title->SetJustification(ETextJustify::Center);
	Title->SetText(FText::FromString(TEXT("СТАНЦИЯ ОБСЛУЖИВАНИЯ")));
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(Title))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.0f, 0.5f, 0.0f));
		Slot->SetOffsets(FMargin(-400, 40, 400, 100));
	}

	SubtitleText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Subtitle"));
	SubtitleText->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 20));
	SubtitleText->SetColorAndOpacity(FSlateColor(FLinearColor(0.8f, 0.75f, 0.9f)));
	SubtitleText->SetJustification(ETextJustify::Center);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(SubtitleText))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.0f, 0.5f, 0.0f));
		Slot->SetOffsets(FMargin(-400, 100, 400, 140));
	}

	// Hull box in the center.
	UBorder* HullPanel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("HullPanel"));
	HullPanel->SetBrushColor(HullBackground);
	HullPanel->SetHorizontalAlignment(HAlign_Center);
	HullPanel->SetVerticalAlignment(VAlign_Center);
	UTextBlock* HullLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	HullLabel->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 20));
	HullLabel->SetText(FText::FromString(TEXT("КОРПУС")));
	HullPanel->SetContent(HullLabel);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(HullPanel))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.5f, 0.5f, 0.5f));
		Slot->SetOffsets(FMargin(-90, -90, 90, 90));
	}

	// Mount chips around the hull (godot layout).
	MakeChip(EMountBinding::Front, FVector2D(-150, -270), FVector2D(150, -160));
	MakeChip(EMountBinding::Rear, FVector2D(-150, 160), FVector2D(150, 270));
	MakeChip(EMountBinding::Left, FVector2D(-430, -55), FVector2D(-110, 55));
	MakeChip(EMountBinding::Right, FVector2D(110, -55), FVector2D(430, 55));

	// Module list panel on the right.
	ModuleListPanel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("ModuleListPanel"));
	ModuleListPanel->SetBrushColor(ListBackground);
	ModuleListPanel->SetPadding(FMargin(24));
	ModuleListPanel->SetVisibility(ESlateVisibility::Collapsed);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(ModuleListPanel))
	{
		Slot->SetAnchors(FAnchors(1.0f, 0.0f, 1.0f, 1.0f));
		Slot->SetOffsets(FMargin(-440, 180, -40, -120));
	}
	ModuleListBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("ModuleList"));
	ModuleListPanel->SetContent(ModuleListBox);

	HelpText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Help"));
	HelpText->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 16));
	HelpText->SetColorAndOpacity(FSlateColor(FLinearColor(0.7f, 0.7f, 0.78f)));
	HelpText->SetJustification(ETextJustify::Center);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(HelpText))
	{
		Slot->SetAnchors(FAnchors(0.5f, 1.0f, 0.5f, 1.0f));
		Slot->SetOffsets(FMargin(-800, -56, 800, -20));
	}
}

void UShipModifierScreenWidget::MakeChip(EMountBinding Binding, const FVector2D& TopLeft, const FVector2D& BottomRight)
{
	using namespace ModifierStyle;

	UCanvasPanel* Canvas = Cast<UCanvasPanel>(WidgetTree->RootWidget);

	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass());
	Panel->SetBrushColor(ChipBackground);
	Panel->SetHorizontalAlignment(HAlign_Center);
	Panel->SetVerticalAlignment(VAlign_Center);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(Panel))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.5f, 0.5f, 0.5f));
		Slot->SetOffsets(FMargin(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y));
	}

	UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Label->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 17));
	Label->SetColorAndOpacity(FSlateColor(TextNormal));
	Label->SetJustification(ETextJustify::Center);
	Panel->SetContent(Label);

	ChipPanels.Add(Binding, Panel);
	ChipLabels.Add(Binding, Label);
}

void UShipModifierScreenWidget::Open(AStation* InStation, AShip* InShip)
{
	Station = InStation;
	Ship = InShip;
	State = EState::PickMount;
	SelectedBinding = EMountBinding::Front;
	SubtitleText->SetText(InStation ? InStation->GetDisplayName() : FText::GetEmpty());
	RefreshChips();
	ModuleListPanel->SetVisibility(ESlateVisibility::Collapsed);
	RefreshHelp();
	SetVisibility(ESlateVisibility::Visible);
	SetKeyboardFocus();
}

void UShipModifierScreenWidget::Close()
{
	SetVisibility(ESlateVisibility::Collapsed);
	if (OnClosed)
	{
		OnClosed();
	}
}

FText UShipModifierScreenWidget::ChipName(EMountBinding Binding)
{
	switch (Binding)
	{
	case EMountBinding::Front: return FText::FromString(TEXT("НОС"));
	case EMountBinding::Rear: return FText::FromString(TEXT("КОРМА"));
	case EMountBinding::Left: return FText::FromString(TEXT("ЛЕВЫЙ"));
	case EMountBinding::Right: return FText::FromString(TEXT("ПРАВЫЙ"));
	}
	return FText::FromString(TEXT("?"));
}

FText UShipModifierScreenWidget::ModuleDisplayName(const UModuleProfile* Profile)
{
	if (!Profile)
	{
		return FText::FromString(TEXT("(пусто)"));
	}
	if (!Profile->DisplayName.IsEmpty())
	{
		return Profile->DisplayName;
	}
	return FText::FromString(Profile->GetName());
}

FText UShipModifierScreenWidget::ChipText(EMountBinding Binding) const
{
	const UModuleProfile* Profile = nullptr;
	if (Ship.IsValid() && Ship->Loadout)
	{
		Profile = Ship->Loadout->GetModule(Binding);
	}
	return FText::Format(FText::FromString(TEXT("{0}\n{1}")), ChipName(Binding), ModuleDisplayName(Profile));
}

void UShipModifierScreenWidget::RefreshChips()
{
	using namespace ModifierStyle;
	for (const auto& Pair : ChipLabels)
	{
		const bool bSelected = Pair.Key == SelectedBinding && State == EState::PickMount;
		Pair.Value->SetText(ChipText(Pair.Key));
		Pair.Value->SetColorAndOpacity(FSlateColor(bSelected ? TextSelected : TextNormal));
		if (UBorder* Panel = ChipPanels.FindRef(Pair.Key))
		{
			Panel->SetBrushColor(bSelected ? FLinearColor(0.16f, 0.12f, 0.08f, 0.95f) : ChipBackground);
		}
	}
}

FReply UShipModifierScreenWidget::NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (State == EState::PickMount)
	{
		HandlePickMountKey(Key);
	}
	else
	{
		HandlePickModuleKey(Key);
	}
	return FReply::Handled();
}

void UShipModifierScreenWidget::HandlePickMountKey(const FKey& Key)
{
	if (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right ||
	    Key == EKeys::F || Key == EKeys::Gamepad_LeftShoulder)
	{
		Close();
	}
	else if (Key == EKeys::Enter || Key == EKeys::SpaceBar || Key == EKeys::Gamepad_FaceButton_Bottom)
	{
		EnterModulePick();
	}
	else if (Key == EKeys::Up || Key == EKeys::Gamepad_DPad_Up)
	{
		SelectedBinding = EMountBinding::Front;
		RefreshChips();
	}
	else if (Key == EKeys::Down || Key == EKeys::Gamepad_DPad_Down)
	{
		SelectedBinding = EMountBinding::Rear;
		RefreshChips();
	}
	else if (Key == EKeys::Left || Key == EKeys::Gamepad_DPad_Left)
	{
		SelectedBinding = EMountBinding::Left;
		RefreshChips();
	}
	else if (Key == EKeys::Right || Key == EKeys::Gamepad_DPad_Right)
	{
		SelectedBinding = EMountBinding::Right;
		RefreshChips();
	}
}

void UShipModifierScreenWidget::HandlePickModuleKey(const FKey& Key)
{
	if (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right)
	{
		ExitModulePick();
	}
	else if (Key == EKeys::Enter || Key == EKeys::SpaceBar || Key == EKeys::Gamepad_FaceButton_Bottom)
	{
		ApplySelectedModule();
	}
	else if (Key == EKeys::Up || Key == EKeys::Gamepad_DPad_Up)
	{
		StepModule(-1);
	}
	else if (Key == EKeys::Down || Key == EKeys::Gamepad_DPad_Down)
	{
		StepModule(1);
	}
}

void UShipModifierScreenWidget::EnterModulePick()
{
	State = EState::PickModule;
	BuildModuleList();
	SelectedModuleIndex = FindCurrentModuleIndex();
	RefreshModuleHighlight();
	ModuleListPanel->SetVisibility(ESlateVisibility::Visible);
	RefreshChips();
	RefreshHelp();
}

void UShipModifierScreenWidget::ExitModulePick()
{
	State = EState::PickMount;
	ModuleListPanel->SetVisibility(ESlateVisibility::Collapsed);
	RefreshChips();
	RefreshHelp();
}

void UShipModifierScreenWidget::BuildModuleList()
{
	using namespace ModifierStyle;

	ModuleListBox->ClearChildren();
	ModuleItems.Reset();
	ModuleItemProfiles.Reset();

	UTextBlock* Header = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Header->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 20));
	Header->SetColorAndOpacity(FSlateColor(Accent));
	Header->SetText(FText::Format(FText::FromString(TEXT("В {0} поставить:")), ChipName(SelectedBinding)));
	if (UVerticalBoxSlot* Slot = ModuleListBox->AddChildToVerticalBox(Header))
	{
		Slot->SetPadding(FMargin(0, 0, 0, 12));
	}

	TArray<UModuleProfile*> Available;
	if (Station.IsValid())
	{
		Available = Station->GetAvailableModules();
	}
	auto AddItem = [this](UModuleProfile* Profile)
	{
		UTextBlock* Item = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Item->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 18));
		Item->SetColorAndOpacity(FSlateColor(ModifierStyle::TextNormal));
		Item->SetText(Profile
			? FText::Format(FText::FromString(TEXT("  {0}")), ModuleDisplayName(Profile))
			: FText::FromString(TEXT("  (снять модуль)")));
		ModuleItems.Add(Item);
		ModuleItemProfiles.Add(Profile);
		if (UVerticalBoxSlot* Slot = ModuleListBox->AddChildToVerticalBox(Item))
		{
			Slot->SetPadding(FMargin(0, 4, 0, 4));
		}
	};
	for (UModuleProfile* Profile : Available)
	{
		AddItem(Profile);
	}
	AddItem(nullptr); // "(снять модуль)"
}

int32 UShipModifierScreenWidget::FindCurrentModuleIndex() const
{
	if (!Ship.IsValid() || !Ship->Loadout)
	{
		return 0;
	}
	const UModuleProfile* Current = Ship->Loadout->GetModule(SelectedBinding);
	if (!Current)
	{
		return ModuleItemProfiles.Num() - 1; // "(снять модуль)"
	}
	for (int32 i = 0; i < ModuleItemProfiles.Num(); ++i)
	{
		if (ModuleItemProfiles[i] == Current)
		{
			return i;
		}
	}
	return ModuleItemProfiles.Num() - 1;
}

void UShipModifierScreenWidget::StepModule(int32 Delta)
{
	const int32 Count = ModuleItems.Num();
	if (Count <= 0)
	{
		return;
	}
	SelectedModuleIndex = (SelectedModuleIndex + Delta + Count) % Count;
	RefreshModuleHighlight();
}

void UShipModifierScreenWidget::RefreshModuleHighlight()
{
	using namespace ModifierStyle;
	for (int32 i = 0; i < ModuleItems.Num(); ++i)
	{
		ModuleItems[i]->SetColorAndOpacity(FSlateColor(i == SelectedModuleIndex ? TextSelected : TextNormal));
	}
}

void UShipModifierScreenWidget::ApplySelectedModule()
{
	if (Ship.IsValid() && ModuleItemProfiles.IsValidIndex(SelectedModuleIndex))
	{
		Ship->ApplyLoadoutChange(SelectedBinding, ModuleItemProfiles[SelectedModuleIndex]);
	}
	RefreshChips();
	ExitModulePick();
}

void UShipModifierScreenWidget::RefreshHelp()
{
	HelpText->SetText(State == EState::PickMount
		? FText::FromString(TEXT("↑↓←→ — выбор слота · A/Enter — поменять модуль · LB/B/Esc — закрыть"))
		: FText::FromString(TEXT("↑↓ — выбор модуля · A/Enter — установить · B/Esc — назад")));
}
