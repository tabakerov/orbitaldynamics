#pragma once

#include "CoreMinimal.h"
#include "Components/Button.h"
#include "IndexedButton.generated.h"

// UButton::OnClicked carries no payload; this subclass forwards a stable
// index to a native callback so list-style menus can be built in C++.
UCLASS()
class ORBITALDYNAMICS_API UIndexedButton : public UButton
{
	GENERATED_BODY()

public:
	int32 Index = 0;
	TFunction<void(int32)> OnIndexClicked;

	void BindClick()
	{
		OnClicked.AddUniqueDynamic(this, &UIndexedButton::HandleClick);
	}

private:
	UFUNCTION()
	void HandleClick()
	{
		if (OnIndexClicked)
		{
			OnIndexClicked(Index);
		}
	}
};
