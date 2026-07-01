#include "ShipModule.h"

#include "ModuleProfiles.h"
#include "Ship.h"

AShipModule::AShipModule()
{
	PrimaryActorTick.bCanEverTick = false;

	USceneComponent* Root = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	SetRootComponent(Root);
}

void AShipModule::Attach(AShip* InShip, UModuleProfile* InProfile)
{
	Ship = InShip;
	Profile = InProfile;
	Configure();
}
