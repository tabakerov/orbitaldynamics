#include "ShipHUDWidget.h"

#include "../BlackHole.h"
#include "../CelestialBody.h"
#include "../FuelPickup.h"
#include "../LevelManager.h"
#include "../Ship.h"
#include "../Station.h"
#include "../TargetZone.h"
#include "Blueprint/WidgetTree.h"
#include "Components/CanvasPanel.h"
#include "Components/CanvasPanelSlot.h"
#include "Components/ProgressBar.h"
#include "Components/TextBlock.h"
#include "EngineUtils.h"
#include "Styling/CoreStyle.h"

namespace MinimapStyle
{
	constexpr float MapSize = 184.0f;
	constexpr float MapMargin = 18.0f;
	constexpr float MapPadding = 18.0f;
	constexpr float WorldPadding = 35.0f;
	constexpr float MinWorldExtent = 80.0f;

	const FLinearColor Background(0.015f, 0.025f, 0.055f, 0.72f);
	const FLinearColor Border(0.55f, 0.72f, 0.95f, 0.42f);
	const FLinearColor Grid(0.55f, 0.72f, 0.95f, 0.13f);
	const FLinearColor ShipColor(0.72f, 0.96f, 1.0f, 1.0f);
	const FLinearColor TargetColor(1.0f, 0.82f, 0.16f, 1.0f);
	const FLinearColor BodyColor(0.34f, 0.62f, 1.0f, 0.9f);
	const FLinearColor BlackHoleColor(0.02f, 0.015f, 0.05f, 0.96f);
	const FLinearColor BlackHoleRing(0.82f, 0.45f, 1.0f, 0.92f);
	const FLinearColor StationColor(0.95f, 0.45f, 1.0f, 0.95f);
	const FLinearColor FuelColor(0.25f, 1.0f, 0.45f, 0.95f);
}

namespace IndicatorStyle
{
	constexpr float EdgePadding = 36.0f;
	constexpr float DirectionEpsilon = 0.001f;
	const FLinearColor Fill(1.0f, 0.82f, 0.16f, 0.95f);
}

namespace
{
	void DrawPolyline(FSlateWindowElementList& OutDrawElements, int32 LayerId, const FGeometry& Geometry,
	                  const TArray<FVector2D>& Points, const FLinearColor& Color, float Thickness)
	{
		TArray<FVector2f> Converted;
		Converted.Reserve(Points.Num());
		for (const FVector2D& P : Points)
		{
			Converted.Add(FVector2f(P));
		}
		FSlateDrawElement::MakeLines(OutDrawElements, LayerId, Geometry.ToPaintGeometry(),
		                             Converted, ESlateDrawEffect::None, Color, true, Thickness);
	}

	void DrawCircle(FSlateWindowElementList& OutDrawElements, int32 LayerId, const FGeometry& Geometry,
	                const FVector2D& Center, float Radius, const FLinearColor& Color, float Thickness,
	                int32 Segments = 28)
	{
		TArray<FVector2D> Points;
		Points.Reserve(Segments + 1);
		for (int32 i = 0; i <= Segments; ++i)
		{
			const float Angle = 2.0f * PI * float(i) / float(Segments);
			Points.Add(Center + FVector2D(FMath::Cos(Angle), FMath::Sin(Angle)) * Radius);
		}
		DrawPolyline(OutDrawElements, LayerId, Geometry, Points, Color, Thickness);
	}

	void DrawFilledRect(FSlateWindowElementList& OutDrawElements, int32 LayerId, const FGeometry& Geometry,
	                    const FVector2D& Position, const FVector2D& Size, const FLinearColor& Color)
	{
		FSlateDrawElement::MakeBox(OutDrawElements, LayerId,
		                           Geometry.ToPaintGeometry(FVector2f(Size), FSlateLayoutTransform(FVector2f(Position))),
		                           FCoreStyle::Get().GetBrush("WhiteBrush"), ESlateDrawEffect::None, Color);
	}
}

bool UShipHUDWidget::Initialize()
{
	const bool bOk = Super::Initialize();
	if (bOk && WidgetTree && !WidgetTree->RootWidget)
	{
		BuildTree();
	}
	return bOk;
}

void UShipHUDWidget::BuildTree()
{
	UCanvasPanel* Canvas = WidgetTree->ConstructWidget<UCanvasPanel>(UCanvasPanel::StaticClass(), TEXT("Canvas"));
	WidgetTree->RootWidget = Canvas;

	// Fuel bar bottom-left (godot hud.tscn anchors 0.02..0.25 / 0.92..0.96).
	FuelBar = WidgetTree->ConstructWidget<UProgressBar>(UProgressBar::StaticClass(), TEXT("FuelBar"));
	FuelBar->SetFillColorAndOpacity(FLinearColor(0.3f, 0.8f, 1.0f));
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(FuelBar))
	{
		Slot->SetAnchors(FAnchors(0.02f, 0.92f, 0.25f, 0.96f));
		Slot->SetOffsets(FMargin(0));
	}

	FuelLabel = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("FuelLabel"));
	FuelLabel->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 16));
	FuelLabel->SetColorAndOpacity(FSlateColor(FLinearColor::White));
	FuelLabel->SetText(NSLOCTEXT("OrbitalDynamics", "FuelInit", "Fuel: 100%"));
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(FuelLabel))
	{
		Slot->SetAnchors(FAnchors(0.02f, 0.92f, 0.25f, 0.92f));
		Slot->SetOffsets(FMargin(0, -26, 0, 22));
	}

	DockPrompt = WidgetTree->ConstructWidget<UTextBlock>(UTextBlock::StaticClass(), TEXT("DockPrompt"));
	DockPrompt->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 22));
	DockPrompt->SetColorAndOpacity(FSlateColor(FLinearColor(0.95f, 0.6f, 1.0f)));
	DockPrompt->SetJustification(ETextJustify::Center);
	DockPrompt->SetVisibility(ESlateVisibility::Collapsed);
	if (UCanvasPanelSlot* Slot = Canvas->AddChildToCanvas(DockPrompt))
	{
		Slot->SetAnchors(FAnchors(0.5f, 0.0f, 0.5f, 0.0f));
		Slot->SetOffsets(FMargin(-260, 32, 260, 88));
		Slot->SetAlignment(FVector2D(0.5f, 0.0f));
		Slot->SetAutoSize(true);
	}
}

void UShipHUDWidget::Setup(AShip* InShip, ALevelManager* InLevelManager)
{
	Ship = InShip;
	LevelManager = InLevelManager;
	if (InShip)
	{
		InShip->OnFuelChanged.AddUniqueDynamic(this, &UShipHUDWidget::HandleFuelChanged);
		HandleFuelChanged(InShip->Fuel, InShip->MaxFuel);
	}
}

void UShipHUDWidget::ShowDockPrompt(const FText& StationName)
{
	if (DockPrompt)
	{
		// Godot: "F · LB — стыковка с %s".
		DockPrompt->SetText(FText::Format(
			NSLOCTEXT("OrbitalDynamics", "DockPrompt", "F · LB — стыковка с {0}"), StationName));
		DockPrompt->SetVisibility(ESlateVisibility::HitTestInvisible);
	}
}

void UShipHUDWidget::HideDockPrompt()
{
	if (DockPrompt)
	{
		DockPrompt->SetVisibility(ESlateVisibility::Collapsed);
	}
}

void UShipHUDWidget::HandleFuelChanged(float Current, float Maximum)
{
	if (FuelBar)
	{
		FuelBar->SetPercent(Maximum > 0.0f ? Current / Maximum : 0.0f);
	}
	if (FuelLabel)
	{
		FuelLabel->SetText(FText::Format(
			NSLOCTEXT("OrbitalDynamics", "FuelLabel", "Fuel: {0}%"),
			FText::AsNumber(FMath::RoundToInt(Maximum > 0.0f ? Current / Maximum * 100.0f : 0.0f))));
	}
}

void UShipHUDWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	if (!Target.IsValid())
	{
		TActorIterator<ATargetZone> It(GetWorld());
		if (It)
		{
			Target = *It;
		}
	}
}

int32 UShipHUDWidget::NativePaint(const FPaintArgs& Args, const FGeometry& AllottedGeometry,
                                  const FSlateRect& MyCullingRect, FSlateWindowElementList& OutDrawElements,
                                  int32 LayerId, const FWidgetStyle& InWidgetStyle, bool bParentEnabled) const
{
	int32 MaxLayer = Super::NativePaint(Args, AllottedGeometry, MyCullingRect, OutDrawElements,
	                                    LayerId, InWidgetStyle, bParentEnabled);
	MaxLayer = PaintMinimap(AllottedGeometry, OutDrawElements, MaxLayer + 1);
	MaxLayer = PaintTargetIndicator(AllottedGeometry, OutDrawElements, MaxLayer + 1);
	return MaxLayer;
}

int32 UShipHUDWidget::PaintMinimap(const FGeometry& Geometry, FSlateWindowElementList& OutDrawElements,
                                   int32 LayerId) const
{
	using namespace MinimapStyle;

	const FVector2D LocalSize = Geometry.GetLocalSize();
	const FVector2D MapOrigin(LocalSize.X - MapSize - MapMargin, MapMargin);

	DrawFilledRect(OutDrawElements, LayerId, Geometry, MapOrigin, FVector2D(MapSize, MapSize), Background);

	// Grid 4x4.
	for (int32 i = 1; i < 4; ++i)
	{
		const float Offset = MapSize * float(i) / 4.0f;
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { MapOrigin + FVector2D(Offset, 0), MapOrigin + FVector2D(Offset, MapSize) }, Grid, 1.0f);
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { MapOrigin + FVector2D(0, Offset), MapOrigin + FVector2D(MapSize, Offset) }, Grid, 1.0f);
	}
	DrawPolyline(OutDrawElements, LayerId, Geometry,
	             { MapOrigin, MapOrigin + FVector2D(MapSize, 0), MapOrigin + FVector2D(MapSize, MapSize),
	               MapOrigin + FVector2D(0, MapSize), MapOrigin }, Border, 1.5f);

	if (!Ship.IsValid() || !LevelManager.IsValid())
	{
		return LayerId;
	}

	// Auto-framing bounds over every point of interest (godot _calculate_world_bounds).
	TArray<FVector2D> Points;
	Points.Add(WorldToPlane(Ship->GetActorLocation()));
	if (Target.IsValid())
	{
		Points.Add(WorldToPlane(Target->GetActorLocation()));
	}
	for (const ACelestialBody* Body : LevelManager->CelestialBodies)
	{
		if (IsValid(Body))
		{
			Points.Add(WorldToPlane(Body->GetActorLocation()));
		}
	}
	TArray<const AStation*> Stations;
	for (TActorIterator<AStation> It(GetWorld()); It; ++It)
	{
		Stations.Add(*It);
		Points.Add(WorldToPlane(It->GetActorLocation()));
	}
	TArray<const AFuelPickup*> Pickups;
	for (TActorIterator<AFuelPickup> It(GetWorld()); It; ++It)
	{
		Pickups.Add(*It);
		Points.Add(WorldToPlane(It->GetActorLocation()));
	}

	FVector2D Min = Points[0];
	FVector2D Max = Points[0];
	for (const FVector2D& P : Points)
	{
		Min = FVector2D(FMath::Min(Min.X, P.X), FMath::Min(Min.Y, P.Y));
		Max = FVector2D(FMath::Max(Max.X, P.X), FMath::Max(Max.Y, P.Y));
	}
	const FVector2D WorldCenter = (Min + Max) * 0.5;
	FVector2D Extents = Max - Min;
	Extents.X = FMath::Max(Extents.X + WorldPadding * 2.0f, MinWorldExtent);
	Extents.Y = FMath::Max(Extents.Y + WorldPadding * 2.0f, MinWorldExtent);

	const float DrawableSize = MapSize - MapPadding * 2.0f;
	const float Scale = FMath::Min(DrawableSize / FMath::Max(Extents.X, 1.0),
	                               DrawableSize / FMath::Max(Extents.Y, 1.0));
	const FVector2D ScreenCenter = MapOrigin + FVector2D(MapSize, MapSize) * 0.5;

	auto ToMap = [&](const FVector& World) -> FVector2D
	{
		return ScreenCenter + (WorldToPlane(World) - WorldCenter) * Scale;
	};

	// Celestial bodies (black holes get a dark disc + bright ring).
	for (const ACelestialBody* Body : LevelManager->CelestialBodies)
	{
		if (!IsValid(Body))
		{
			continue;
		}
		const FVector2D Pos = ToMap(Body->GetActorLocation());
		const float Radius = FMath::Clamp(Body->GetBodyRadius() * Scale, 4.0f, 18.0f);
		if (Body->IsA<ABlackHole>())
		{
			DrawCircle(OutDrawElements, LayerId, Geometry, Pos, Radius, BlackHoleColor, 3.0f);
			DrawCircle(OutDrawElements, LayerId, Geometry, Pos, Radius + 2.0f, BlackHoleRing, 2.0f);
		}
		else
		{
			DrawCircle(OutDrawElements, LayerId, Geometry, Pos, Radius, BodyColor, 2.5f);
			DrawCircle(OutDrawElements, LayerId, Geometry, Pos, Radius + 1.0f,
			           FLinearColor(BodyColor.R, BodyColor.G, BodyColor.B, 0.45f), 1.5f);
		}
	}

	// Stations: square with a cross.
	for (const AStation* Station : Stations)
	{
		const FVector2D Pos = ToMap(Station->GetActorLocation());
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { Pos + FVector2D(-4.5, -4.5), Pos + FVector2D(4.5, -4.5), Pos + FVector2D(4.5, 4.5),
		               Pos + FVector2D(-4.5, 4.5), Pos + FVector2D(-4.5, -4.5) }, StationColor, 2.0f);
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { Pos + FVector2D(-6, 0), Pos + FVector2D(6, 0) }, StationColor, 1.5f);
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { Pos + FVector2D(0, -6), Pos + FVector2D(0, 6) }, StationColor, 1.5f);
	}

	for (const AFuelPickup* Pickup : Pickups)
	{
		DrawCircle(OutDrawElements, LayerId, Geometry, ToMap(Pickup->GetActorLocation()), 3.5f, FuelColor, 2.5f, 12);
	}

	// Target: diamond.
	if (Target.IsValid())
	{
		const FVector2D Pos = ToMap(Target->GetActorLocation());
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { Pos + FVector2D(0, -7), Pos + FVector2D(7, 0), Pos + FVector2D(0, 7),
		               Pos + FVector2D(-7, 0), Pos + FVector2D(0, -7) }, TargetColor, 2.5f);
	}

	// Ship: yaw-oriented triangle.
	{
		const FVector Forward3D = Ship->GetActorForwardVector();
		FVector2D Forward(Forward3D.Y, -Forward3D.X);
		if (Forward.SizeSquared() <= 0.0001)
		{
			Forward = FVector2D(0, -1);
		}
		Forward.Normalize();
		const FVector2D Right(-Forward.Y, Forward.X);
		const FVector2D Pos = ToMap(Ship->GetActorLocation());
		DrawPolyline(OutDrawElements, LayerId, Geometry,
		             { Pos + Forward * 10.0, Pos - Forward * 7.0 + Right * 5.5, Pos - Forward * 4.0,
		               Pos - Forward * 7.0 - Right * 5.5, Pos + Forward * 10.0 }, ShipColor, 2.0f);
	}

	return LayerId;
}

int32 UShipHUDWidget::PaintTargetIndicator(const FGeometry& Geometry, FSlateWindowElementList& OutDrawElements,
                                           int32 LayerId) const
{
	using namespace IndicatorStyle;

	if (!Target.IsValid())
	{
		return LayerId;
	}
	const APlayerController* PC = GetOwningPlayer();
	if (!PC)
	{
		return LayerId;
	}

	const FVector2D LocalSize = Geometry.GetLocalSize();
	if (LocalSize.X <= 0.0 || LocalSize.Y <= 0.0)
	{
		return LayerId;
	}

	FVector2D ScreenPosition;
	// bPlayerViewportRelative gives viewport pixels; convert to widget-local units.
	const bool bProjected = PC->ProjectWorldLocationToScreen(Target->GetActorLocation(), ScreenPosition, true);
	const float Scale = Geometry.Scale > 0.0f ? Geometry.Scale : 1.0f;
	ScreenPosition /= Scale;

	// "Behind the camera" for a top-down view: projection failed.
	const bool bBehind = !bProjected;
	const bool bOnScreen = !bBehind &&
		ScreenPosition.X >= 0.0 && ScreenPosition.X <= LocalSize.X &&
		ScreenPosition.Y >= 0.0 && ScreenPosition.Y <= LocalSize.Y;
	if (bOnScreen)
	{
		return LayerId;
	}

	const FVector2D ScreenCenter = LocalSize * 0.5;
	FVector2D Direction = ScreenPosition - ScreenCenter;
	if (bBehind)
	{
		Direction = -Direction;
	}
	if (Direction.SizeSquared() <= DirectionEpsilon)
	{
		Direction = FVector2D(0, -1);
	}

	const FVector2D EdgeExtent = ScreenCenter - FVector2D(EdgePadding, EdgePadding);
	float ScaleX = 1000000.0f;
	float ScaleY = 1000000.0f;
	if (FMath::Abs(Direction.X) > DirectionEpsilon)
	{
		ScaleX = EdgeExtent.X / FMath::Abs(Direction.X);
	}
	if (FMath::Abs(Direction.Y) > DirectionEpsilon)
	{
		ScaleY = EdgeExtent.Y / FMath::Abs(Direction.Y);
	}
	const FVector2D EdgePosition = ScreenCenter + Direction * FMath::Min(ScaleX, ScaleY);

	// Arrow polygon from godot TargetIndicator::_draw, rotated toward the target.
	const float Angle = FMath::Atan2(Direction.Y, Direction.X);
	const float Cos = FMath::Cos(Angle);
	const float Sin = FMath::Sin(Angle);
	auto Rotated = [&](const FVector2D& P) -> FVector2D
	{
		return EdgePosition + FVector2D(P.X * Cos - P.Y * Sin, P.X * Sin + P.Y * Cos);
	};
	DrawPolyline(OutDrawElements, LayerId, Geometry,
	             { Rotated({ 13, 0 }), Rotated({ -8, -8.5 }), Rotated({ -4, 0 }),
	               Rotated({ -8, 8.5 }), Rotated({ 13, 0 }) }, Fill, 3.0f);

	return LayerId;
}
