#include "ModalOverlayWidget.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/BorderSlot.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "IndexedButton.h"
#include "Styling/CoreStyle.h"

bool UModalOverlayWidget::Initialize()
{
	const bool bOk = Super::Initialize();
	if (bOk && WidgetTree && !WidgetTree->RootWidget)
	{
		SetIsFocusable(true);
		BuildTree();
	}
	return bOk;
}

void UModalOverlayWidget::BuildTree()
{
	Background = WidgetTree->ConstructWidget<UBorder>(UBorder::StaticClass(), TEXT("Background"));
	Background->SetHorizontalAlignment(HAlign_Center);
	Background->SetVerticalAlignment(VAlign_Center);
	WidgetTree->RootWidget = Background;

	UVerticalBox* Panel = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("Panel"));
	Background->SetContent(Panel);

	TitleText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Title"));
	TitleText->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 40));
	TitleText->SetJustification(ETextJustify::Center);
	TitleText->SetColorAndOpacity(FSlateColor(FLinearColor::White));
	if (UVerticalBoxSlot* Slot = Panel->AddChildToVerticalBox(TitleText))
	{
		Slot->SetPadding(FMargin(24, 0, 24, 16));
		Slot->SetHorizontalAlignment(HAlign_Center);
	}

	MessageText = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("Message"));
	MessageText->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 22));
	MessageText->SetJustification(ETextJustify::Center);
	MessageText->SetColorAndOpacity(FSlateColor(FLinearColor(0.9f, 0.9f, 0.95f)));
	MessageText->SetAutoWrapText(true);
	if (UVerticalBoxSlot* Slot = Panel->AddChildToVerticalBox(MessageText))
	{
		Slot->SetPadding(FMargin(24, 0, 24, 20));
		Slot->SetHorizontalAlignment(HAlign_Center);
	}

	ButtonBox = WidgetTree->ConstructWidget<UVerticalBox>(UVerticalBox::StaticClass(), TEXT("Buttons"));
	if (UVerticalBoxSlot* Slot = Panel->AddChildToVerticalBox(ButtonBox))
	{
		Slot->SetPadding(FMargin(24, 0, 24, 0));
		Slot->SetHorizontalAlignment(HAlign_Center);
	}
}

void UModalOverlayWidget::Configure(const FLinearColor& BackgroundColor, const FText& Title, const FText& Message,
                                    const TArray<FButtonSpec>& InButtons, int32 FocusButtonIndex)
{
	Background->SetBrushColor(BackgroundColor);
	Background->SetPadding(FMargin(0));

	TitleText->SetText(Title);
	TitleText->SetVisibility(Title.IsEmpty() ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);
	MessageText->SetText(Message);
	MessageText->SetVisibility(Message.IsEmpty() ? ESlateVisibility::Collapsed : ESlateVisibility::HitTestInvisible);

	ButtonBox->ClearChildren();
	Buttons.Reset();
	ButtonCallbacks.Reset();
	DefaultFocusIndex = FocusButtonIndex;

	for (int32 i = 0; i < InButtons.Num(); ++i)
	{
		const FButtonSpec& Spec = InButtons[i];

		UIndexedButton* Button = WidgetTree->ConstructWidget<UIndexedButton>(UIndexedButton::StaticClass());
		Button->Index = i;
		Button->SetIsEnabled(Spec.bEnabled);
		ButtonCallbacks.Add(Spec.OnClicked);
		Button->OnIndexClicked = [this](int32 Index)
		{
			if (ButtonCallbacks.IsValidIndex(Index) && ButtonCallbacks[Index])
			{
				ButtonCallbacks[Index]();
			}
		};
		Button->BindClick();

		UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass());
		Label->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 20));
		Label->SetText(Spec.Label);
		Label->SetJustification(ETextJustify::Center);
		Label->SetColorAndOpacity(FSlateColor(FLinearColor(0.05f, 0.05f, 0.08f)));
		Button->AddChild(Label);
		if (UButtonSlot* LabelSlot = Cast<UButtonSlot>(Label->Slot))
		{
			LabelSlot->SetPadding(FMargin(40, 10, 40, 10));
		}

		Buttons.Add(Button);
		if (UVerticalBoxSlot* Slot = ButtonBox->AddChildToVerticalBox(Button))
		{
			Slot->SetPadding(FMargin(0, 5, 0, 5));
			Slot->SetHorizontalAlignment(HAlign_Fill);
		}
	}

	AutoContinueRemaining = 0.0f;
	AutoContinueCallback = nullptr;
}

void UModalOverlayWidget::SetAutoContinue(float Seconds, TFunction<void()> Callback)
{
	AutoContinueRemaining = Seconds;
	AutoContinueCallback = MoveTemp(Callback);
}

void UModalOverlayWidget::FocusDefaultButton()
{
	if (Buttons.IsValidIndex(DefaultFocusIndex) && Buttons[DefaultFocusIndex]->GetIsEnabled())
	{
		Buttons[DefaultFocusIndex]->SetKeyboardFocus();
		return;
	}
	for (UIndexedButton* Button : Buttons)
	{
		if (Button->GetIsEnabled())
		{
			Button->SetKeyboardFocus();
			return;
		}
	}
	SetKeyboardFocus();
}

void UModalOverlayWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	// Slate ticks with real time even while the game is paused, which is what
	// the godot intro timer (process_always) relied on.
	if (AutoContinueRemaining > 0.0f && AutoContinueCallback)
	{
		AutoContinueRemaining -= InDeltaTime;
		if (AutoContinueRemaining <= 0.0f)
		{
			TFunction<void()> Callback = MoveTemp(AutoContinueCallback);
			AutoContinueCallback = nullptr;
			Callback();
		}
	}
}

FReply UModalOverlayWidget::NativeOnKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	const FKey Key = InKeyEvent.GetKey();
	if (ExtraKeyHandler && ExtraKeyHandler(Key))
	{
		return FReply::Handled();
	}
	if (OnCancel && (Key == EKeys::Escape || Key == EKeys::Gamepad_FaceButton_Right))
	{
		OnCancel();
		return FReply::Handled();
	}
	return Super::NativeOnKeyDown(InGeometry, InKeyEvent);
}
