#include "LevelSelectWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "IndexedButton.h"
#include "Styling/CoreStyle.h"

bool ULevelSelectWidget::Initialize()
{
	const bool bOk = Super::Initialize();
	if (bOk && WidgetTree && !WidgetTree->RootWidget)
	{
		SetIsFocusable(true);
		BuildTree();
	}
	return bOk;
}

void ULevelSelectWidget::BuildTree()
{
	UBorder* Background = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Background"));
	Background->SetBrushColor(FLinearColor(0.02f, 0.03f, 0.09f, 1.0f));
	Background->SetHorizontalAlignment(HAlign_Center);
	Background->SetVerticalAlignment(VAlign_Center);
	WidgetTree->RootWidget = Background;

	UVerticalBox* Panel = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("Panel"));
	Background->SetContent(Panel);

	UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Title"));
	Title->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 44));
	Title->SetText(FText::FromString(TEXT("OrbitalDynamics")));
	Title->SetJustification(ETextJustify::Center);
	if (UVerticalBoxSlot* Slot = Panel->AddChildToVerticalBox(Title))
	{
		Slot->SetPadding(FMargin(0, 0, 0, 30));
		Slot->SetHorizontalAlignment(HAlign_Center);
	}

	ButtonList = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("LevelList"));
	Panel->AddChildToVerticalBox(ButtonList);
}

UIndexedButton* ULevelSelectWidget::MakeButton(const FText& Label, TFunction<void()> Callback)
{
	UIndexedButton* Button = WidgetTree->ConstructWidget<UIndexedButton>(UIndexedButton::StaticClass());
	Button->Index = ButtonCallbacks.Add(MoveTemp(Callback));
	Button->OnIndexClicked = [this](int32 Index)
	{
		if (ButtonCallbacks.IsValidIndex(Index) && ButtonCallbacks[Index])
		{
			ButtonCallbacks[Index]();
		}
	};
	Button->BindClick();

	UTextBlock* Text = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
	Text->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 20));
	Text->SetText(Label);
	Text->SetJustification(ETextJustify::Center);
	Text->SetColorAndOpacity(FSlateColor(FLinearColor(0.05f, 0.05f, 0.08f)));
	Button->AddChild(Text);
	if (UButtonSlot* LabelSlot = Cast<UButtonSlot>(Text->Slot))
	{
		LabelSlot->SetPadding(FMargin(60, 10, 60, 10));
	}

	Buttons.Add(Button);
	if (UVerticalBoxSlot* Slot = ButtonList->AddChildToVerticalBox(Button))
	{
		Slot->SetPadding(FMargin(0, 5, 0, 5));
		Slot->SetHorizontalAlignment(HAlign_Fill);
	}
	return Button;
}

void ULevelSelectWidget::ShowMenu(int32 LevelCount, bool bHasActiveLevel)
{
	ButtonList->ClearChildren();
	Buttons.Reset();
	ButtonCallbacks.Reset();
	bCancelAllowed = bHasActiveLevel;

	for (int32 i = 0; i < LevelCount; ++i)
	{
		MakeButton(FText::Format(NSLOCTEXT("OrbitalDynamics", "LevelButton", "Level {0}"), i + 1),
		           [this, i]() { if (OnLevelSelected) { OnLevelSelected(i); } });
	}

	UIndexedButton* RestartButton = nullptr;
	if (bHasActiveLevel)
	{
		RestartButton = MakeButton(NSLOCTEXT("OrbitalDynamics", "RestartLevel", "Restart Level"),
		                           [this]() { if (OnRestartRequested) { OnRestartRequested(); } });
	}
	MakeButton(NSLOCTEXT("OrbitalDynamics", "Quit", "Quit"),
	           [this]() { if (OnQuitRequested) { OnQuitRequested(); } });

	SetVisibility(ESlateVisibility::Visible);
	// Godot: focus Restart when a level is active, else the first level button.
	if (RestartButton)
	{
		RestartButton->SetKeyboardFocus();
	}
	else if (Buttons.Num() > 0)
	{
		Buttons[0]->SetKeyboardFocus();
	}
}

FReply ULevelSelectWidget::NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (bCancelAllowed && OnCancel &&
	    (Key == EKeys::Escape || Key == EKeys::P || Key == EKeys::Gamepad_FaceButton_Right ||
	     Key == EKeys::Gamepad_Special_Left))
	{
		OnCancel();
		return FReply::Handled();
	}
	return Super::NativeOnKeyDown(InGeometry, InKeyEvent);
}
