# OrbitalDynamics — Спецификация порта на Unreal Engine 5

Документ описывает воссоздание игры OrbitalDynamics (оригинал: Godot 4.6, Jolt Physics) в Unreal Engine 5 с паритетом по **геймплею, физике, управлению, UI-потокам и структуре уровней**.

**Визуальная часть (шейдеры планет, линзирование чёрной дыры, партиклы, фоновый скаттер, меши) — сознательно вне скоупа**: в UE-проекте визуал будет построен заново. В §12 перечислены геймплейные хуки, которые визуальный слой должен будет подхватить.

Рекомендуемая версия: **UE 5.4+**. Язык логики: **C++ для систем, Blueprints для композиции/настройки/UI**.

Актуально для состояния репозитория на 2026-07 (включая: модульный корабль с динамическим центром масс, станции обслуживания с экраном модификации, миникарту, off-screen индикатор цели, интро-сообщения уровней, дебаг-визуализатор полёта, тягу, масштабируемую остатком топлива).

---

## 1. Концепция и геймлуп

Аркадный симулятор орбитального полёта в 2D-плоскости (Godot: плоскость XZ, Y=0; UE5: плоскость XY, Z=0 — см. §3):

- Игрок пилотирует **модульный корабль**: корпус (hull) с 4 mount-слотами (нос/корма/левый/правый), в которые ставятся модули — двигатели, внешние топливные баки, грузовые контейнеры.
- Физика: N-body симуляция гравитации между небесными телами + суммарная гравитация действует на корабль.
- Масса корабля динамическая: сухая масса корпуса + топливо (`fuel * FUEL_UNIT_MASS`) + массы модулей. Центр масс пересчитывается каждый физический тик.
- Цель уровня — достичь цели (Target, area-триггер) при ограниченном топливе.
- **Проигрыш: любое касание небесного тела = crash** (порога скорости больше нет). Корабль замирает, играет взрыв, через 2 с показывается оверлей «вы разбились» (перезапуск / в меню).
- На уровнях есть **станции обслуживания**: в радиусе стыковки появляется подсказка, по F/LB открывается экран модификации корабля (замена модулей в слотах из ассортимента станции).
- Поток уровня: выбор в меню → интро-оверлей с сообщением → игра → completion-оверлей («следующий» / «в меню»). R — рестарт, Escape/Back — пауза/меню, F3 — дебаг-визуализация.

---

## 2. Стек UE5 и соответствие Godot

| Godot | UE5 | Комментарий |
|---|---|---|
| `RigidBody3D` (Jolt) | `APawn`, корень `UStaticMeshComponent` с `SetSimulatePhysics(true)` | Корабль |
| `AnimatableBody3D` | `AActor`, позиция выставляется вручную каждый tick | Небесные тела ведёт симуляция, не физдвижок |
| `Area3D` | `USphereComponent`/`UBoxComponent` с `SetGenerateOverlapEvents(true)` | Target, FuelPickup, Station |
| Autoload `CelestialSim` | `UGameInstanceSubsystem` | §4 |
| `Resource` (`.tres`) | `UPrimaryDataAsset` | HullData, Loadout, профили модулей, StationProfile, CelestialBodyData |
| `PackedScene` модуля | `TSubclassOf<AActor>` / Blueprint-класс | `module_scene` в профиле модуля |
| Input Map | Enhanced Input (`UInputAction` + IMC) | §6 |
| `Control`/`CanvasLayer` UI | UMG (+ Common UI для геймпад-навигации) | §8 |
| `ImmediateMesh` дебаг-линии | `DrawDebugLine` / `ULineBatchComponent` | §9 |
| Кастомный `_draw()` миникарты | `UUserWidget::NativePaint` (FSlateDrawElement) | §8.2 |

**Плагины:** Enhanced Input, Common UI. (Niagara — по желанию визуального слоя, вне скоупа.)

---

## 3. Система координат и единицы

Godot: X вправо, Y вверх, Z вперёд (правосторонняя). Геймплей на плоскости **X-Z**, Y=0.

UE5: X вперёд, Y вправо, Z вверх (левосторонняя). Рекомендация: геймплей в плоскости **X-Y** (Z=0), камера смотрит вниз (−Z). 1 UE-юнит = 1 м (`WorldSettings->WorldToMeters = 1.0`) — либо все константы ×100 в сантиметрах.

Миграция данных:
- Godot `Vector3(x, 0, z)` → UE5 `FVector(x, z, 0)` (swap Y↔Z, Z=0).
- Ось вращения корабля/гимбала: Godot Y → UE5 Z (yaw).
- «Вперёд» корабля: Godot −Z → UE5 +X (или согласованная конвенция, зафиксировать один раз).

Заморозка осей корабля (из `scenes/ship.tscn`: `axis_lock_linear_y`, `axis_lock_angular_x`, `axis_lock_angular_z`):
```cpp
Body->GetBodyInstance()->bLockZTranslation = true;
Body->GetBodyInstance()->bLockXRotation = true;
Body->GetBodyInstance()->bLockYRotation = true;
```

---

## 4. Ядро симуляции

### 4.1. `UCelestialSimSubsystem : public UGameInstanceSubsystem`

Порт autoload-а [celestial_simulation.gd](../godot/scripts/celestial_simulation.gd). Симплектический Эйлер, фиксированный шаг 60 Гц через аккумулятор, O(n²) попарная гравитация, замок плоскости.

Публичный API (полный, включая методы для дебага и миникарты):

```cpp
UCLASS()
class UCelestialSimSubsystem : public UGameInstanceSubsystem, public FTickableGameObject
{
    GENERATED_BODY()
public:
    // FTickableGameObject: аккумулятор -> Step(1/60) пока накоплено
    virtual void Tick(float DeltaTime) override;

    UFUNCTION(BlueprintCallable)
    void InitializeBodies(const TArray<UCelestialBodyData*>& Data,
                          const TArray<FVector>& Positions,
                          const TArray<FVector>& Velocities,
                          const TArray<bool>& Stationary);
    UFUNCTION(BlueprintCallable) void Clear();

    UFUNCTION(BlueprintCallable) FVector GetGravityAt(const FVector& Pos) const;
    UFUNCTION(BlueprintCallable) FVector GetBodyPosition(int32 Index) const;
    UFUNCTION(BlueprintCallable) FVector GetBodyVelocity(int32 Index) const;
    UFUNCTION(BlueprintCallable) int32   GetBodyCount() const;

    // Для дебаг-визуализатора (celestial_simulation.gd:98-136):
    UFUNCTION(BlueprintCallable) FVector GetBodyGravityAcceleration(int32 Index) const;
    UFUNCTION(BlueprintCallable) bool    IsBodyStationary(int32 Index) const;
    // Прогноз траекторий тел: semi-implicit Euler на копии состояния,
    // шаг >= 0.01, первая точка = текущая позиция.
    TArray<TArray<FVector>> PredictBodyPaths(float Seconds, float StepDelta) const;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float GravitationalConstant = 1.0f;
};
```

**Шаг симуляции** (паритет `celestial_simulation.gd:63-74, 143-160`):

```cpp
void Step(float Delta)
{
    TArray<FVector> Accel = GetBodyAccelerations(Positions); // O(n^2), пропуск пар с dist < 0.001
    for (int32 i = 0; i < N; ++i)
    {
        if (Stationary[i]) continue;
        Velocities[i] += Accel[i] * Delta;   // сначала скорость
        Positions[i]  += Velocities[i] * Delta; // потом позиция
        Positions[i].Z = 0.0f;  Velocities[i].Z = 0.0f; // plane lock
    }
}
```

**Гравитация в точке** (паритет `celestial_simulation.gd:77-87`): для каждого тела — если `raw_dist > max_range`, тело не действует; иначе `dist = clamp(raw_dist, min_range, max_range)`, вклад = `normalize(offset) * gravity_strength * mass / pow(dist, falloff_exponent)`.

Важно: `GetGravityAt` использует `gravity_strength/falloff_exponent/min_range/max_range` (влияние на корабль), а межтеловая гравитация — только `G * mass / d²` без ограничений дальности. Это два разных закона — сохранить оба.

### 4.2. `UCelestialBodyData : public UPrimaryDataAsset`

Порт [celestial_body_data.gd](../godot/scripts/celestial_body_data.gd):

```cpp
UPROPERTY(EditAnywhere) float Mass;
UPROPERTY(EditAnywhere) float GravityStrength;
UPROPERTY(EditAnywhere) float FalloffExponent; // обычно 2.0
UPROPERTY(EditAnywhere) float MaxRange;
UPROPERTY(EditAnywhere) float MinRange;
UPROPERTY(EditAnywhere) float Radius;          // радиус коллизии/визуала
```

### 4.3. `ACelestialBody : public AActor`

Порт [celestial_body.gd](../godot/scripts/celestial_body.gd). Свойства: `BodyData`, `InitialVelocity`, `bStationary` (тело зафиксировано, но гравитирует), `SimIndex`.

- В `Tick`: `SetActorLocation(Sim->GetBodyPosition(SimIndex))`.
- `USphereComponent` радиусом `BodyData->Radius`, профиль `BlockAllDynamic` — корабль сталкивается, тело физикой не симулируется.
- Плейсхолдер-меш (сфера) масштабируется по радиусу; финальный визуал — вне скоупа.

### 4.4. `ABlackHole : public ACelestialBody`

Геймплейно — обычное небесное тело (гравитация и коллизия от `BodyData`). Всё линзирование/аберрация — визуальный слой, вне скоупа. Для миникарты нужен лишь признак типа (иконка «чёрная дыра»).

---

## 5. Модульный корабль

Центральное изменение относительно ранней версии: корабль собирается из **loadout-а** в рантайме, а не имеет 4 фиксированных двигателя.

### 5.1. Data Assets

Порт ресурсов [hull_data.gd](../godot/scripts/hull_data.gd), [ship_loadout.gd](../godot/scripts/ship_loadout.gd), [mount_slot.gd](../godot/scripts/mount_slot.gd), [module_profile.gd](../godot/scripts/module_profile.gd) и наследников:

```cpp
UENUM() enum class EMountBinding : uint8 { Front, Rear, Left, Right };

USTRUCT()
struct FMountSlot
{
    UPROPERTY(EditAnywhere) EMountBinding Binding;
    UPROPERTY(EditAnywhere) FTransform Transform; // позиция+ориентация слота на корпусе
};

UCLASS() class UHullData : public UPrimaryDataAsset
{
    UPROPERTY(EditAnywhere) float DryMass = 10.0f;
    UPROPERTY(EditAnywhere) float MaxInternalFuel = 200.0f;
    UPROPERTY(EditAnywhere) TArray<FMountSlot> Mounts;
    // Меш и коллизия корпуса — параметры плейсхолдера, визуал вне скоупа
    UPROPERTY(EditAnywhere) UStaticMesh* Mesh;
    UPROPERTY(EditAnywhere) FTransform CollisionTransform;
};

UCLASS() class UShipLoadout : public UPrimaryDataAsset
{
    UPROPERTY(EditAnywhere) UHullData* Hull;
    UPROPERTY(EditAnywhere) float StartingInternalFuel = 200.0f;
    UPROPERTY(EditAnywhere) UModuleProfile* FrontModule;
    UPROPERTY(EditAnywhere) UModuleProfile* RearModule;
    UPROPERTY(EditAnywhere) UModuleProfile* LeftModule;
    UPROPERTY(EditAnywhere) UModuleProfile* RightModule;
};

UCLASS(Abstract) class UModuleProfile : public UPrimaryDataAsset
{
    UPROPERTY(EditAnywhere) TSubclassOf<AShipModule> ModuleClass; // аналог module_scene
    UPROPERTY(EditAnywhere) FText DisplayName;
};

UCLASS() class UEngineProfile : public UModuleProfile
{
    UPROPERTY(EditAnywhere) float MaxThrust = 100.0f;
    UPROPERTY(EditAnywhere) float FuelConsumptionRate = 10.0f;
    UPROPERTY(EditAnywhere) float GimbalRangeDeg = 30.0f;
    UPROPERTY(EditAnywhere) float DryMass = 0.0f;
};

UCLASS() class UFuelTankProfile : public UModuleProfile
{
    UPROPERTY(EditAnywhere) float Capacity = 100.0f;
    UPROPERTY(EditAnywhere) float DryMass = 1.0f;
    UPROPERTY(EditAnywhere) float MaxPumpRate = 30.0f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float StartingFill = 1.0f;
};

UCLASS() class UCargoProfile : public UModuleProfile
{
    UPROPERTY(EditAnywhere) float Mass = 5.0f;
};
```

Референсные значения из `resources/`: hull `rectangular` (dry 10, fuel 200, 4 слота: front (0,0,−0.9) yaw 180°, rear (0,0,0.9) yaw 0°, left (−1,0,0) yaw 90°, right (1,0,0) yaw −90° — в Godot-координатах); двигатель `engine_standard` (thrust 100, расход 10, гимбал ±30°); баки `tank_basic`/`tank_large`; карго `crate_small`/`crate_large`; loadout-ы `default`, `extended_range`, `cargo_demo`, `tutorial_rear_only`.

### 5.2. `AShipModule` и наследники

Порт [ship_module.gd](../godot/scripts/ship_module.gd). Базовый класс (актор, аттачится к mount-компоненту корабля):

```cpp
UCLASS(Abstract) class AShipModule : public AActor
{
public:
    TWeakObjectPtr<AShip> Ship;
    UPROPERTY() UModuleProfile* Profile;
    bool  bActive = false;        // зажат mount_<binding>
    float Intensity = 0.0f;       // значение оси thrust (0..1)
    float FuelSupplyRatio = 1.0f; // выставляется кораблём (см. 5.4)

    void Attach(AShip* InShip, UModuleProfile* InProfile); // -> Configure()
    virtual void Configure() {}
    virtual float GetMass() const { return 0.0f; }
    virtual void PhysicsTick(float Dt) {}
    virtual FVector GetThrustVector() const { return FVector::ZeroVector; }
    virtual float GetRequestedFuelDrain(float Dt) const { return GetFuelDrain(Dt); }
    virtual float GetFuelDrain(float Dt) const { return 0.0f; }
    virtual float GetPotentialFuelIntake(float Dt) const { return 0.0f; }
    virtual void CommitFuelIntake(float Amount) {}
    virtual void ApplyGimbalDelta(float Delta) {}
};
```

**`AEngineModule`** (порт [engine.gd](../godot/scripts/engine.gd)):

```cpp
float GimbalAngle = 0.f;           // рад, вокруг локальной вертикали
float GimbalRangeRad;              // из профиля, deg->rad в Configure()

void ApplyGimbalDelta(float Delta) override
{
    if (!bActive || Delta == 0.f) return;         // гимбал крутится только у активного двигателя
    GimbalAngle = FMath::Clamp(GimbalAngle + Delta, -GimbalRangeRad, GimbalRangeRad);
    SetActorRelativeRotation(FRotator(0, FMath::RadiansToDegrees(GimbalAngle), 0));
}

FVector GetThrustVector() const override
{
    if (!bActive || Intensity <= 0.f || !HasEffectiveFuelSupply()) return FVector::ZeroVector;
    // Godot: -global_basis.z * max_thrust * intensity * fuel_supply_ratio
    return -GetActorForwardVector() * Profile->MaxThrust * Intensity * FuelSupplyRatio;
    // ^ тяга МАСШТАБИРУЕТСЯ остатком топлива через FuelSupplyRatio
}

float GetRequestedFuelDrain(float Dt) const override
{ return (bActive && Intensity > 0.f) ? Profile->FuelConsumptionRate * Intensity * Dt : 0.f; }

float GetFuelDrain(float Dt) const override
{ return HasEffectiveFuelSupply() ? GetRequestedFuelDrain(Dt) * FuelSupplyRatio : 0.f; }

bool HasEffectiveFuelSupply() const
{
    if (!Ship.IsValid() || FuelSupplyRatio <= 0.f) return false;
    if (FuelSupplyRatio < 1.f) return true;   // частичное питание — тяга есть, но ослаблена
    return Ship->Fuel > 0.f;                  // полное питание требует топлива в баке
}
```

Геймплейные хуки для визуального слоя (сам визуал вне скоупа): `bThrusting = bActive && Intensity > 0 && HasEffectiveFuelSupply()` — выхлоп/партиклы; `bActive` — подсветка активного модуля.

**`AExternalFuelTankModule`** (порт [external_fuel_tank_module.gd](../godot/scripts/external_fuel_tank_module.gd)): хранит `CurrentFuel` (= capacity × starting_fill при спавне).

```cpp
float GetMass() const override
{ return Profile->DryMass + CurrentFuel * AShip::FUEL_UNIT_MASS; }

// Перекачка во внутренний бак ТОЛЬКО при зажатом слоте + тяге:
float GetPotentialFuelIntake(float Dt) const override
{
    if (!bActive || Intensity <= 0.f || CurrentFuel <= 0.f) return 0.f;
    return FMath::Min(Profile->MaxPumpRate * Intensity * Dt, CurrentFuel);
}
void CommitFuelIntake(float Amount) override
{ CurrentFuel = FMath::Max(CurrentFuel - Amount, 0.f); }
```

**`ACargoModule`** (порт [cargo_module.gd](../godot/scripts/cargo_module.gd)): только `GetMass() = Profile->Mass`. Смысл — балласт, смещающий центр масс.

### 5.3. `AShip : public APawn`

Порт [ship.gd](../godot/scripts/ship.gd). Константы:

```cpp
static constexpr float FUEL_UNIT_MASS = 0.02f;          // масса единицы топлива
static constexpr float STICK_DEADZONE = 0.2f;
static constexpr float GIMBAL_KEYBOARD_SPEED = 2.0f;    // рад/с
static constexpr float GIMBAL_STICK_SENSITIVITY = 0.10f;
```

Свойства: `UShipLoadout* Loadout` (при спавне **дублировать** — рантайм-изменения не должны трогать ассет; в UE использовать `DuplicateObject` или рантайм-копию структуры), `float StartingFuelOverride = -1` (если ≥0 — заменяет `Loadout->StartingInternalFuel`).

Сборка в `BeginPlay` (порт `_build_from_loadout`):
1. Из `Hull`: `DryMass`, `MaxFuel = MaxInternalFuel`, `Fuel = clamp(start, 0, MaxFuel)`, плейсхолдер-меш и коллизия.
2. Для каждого `FMountSlot` — `USceneComponent` с трансформом слота; если в loadout-е для binding-а задан профиль с классом — заспавнить модуль, `Attach`, приаттачить к mount-компоненту, положить в `TMap<EMountBinding, AShipModule*>`.
3. `RecalculateMassProperties()`; эмит `OnFuelChanged`.

Физика корпуса (из `ship.tscn`): масса 10 (перекрывается динамикой ниже), gravity off, contact events on, damping = 0, блокировки осей — §3.

**Порядок физического тика** (паритет `ship.gd:110-121`, важен):

```cpp
void AShip::PhysicsTick(float Dt) // вызывать из Tick при фиксированном шаге
{
    if (bCrashed) return;
    UpdateModuleInputs();      // active = mount-кнопка, intensity = ось thrust (для всех модулей)
    UpdateGimbal(Dt);          // клавиатура E/Q + относительное управление стиком
    for (Module : Modules) Module->PhysicsTick(Dt);
    PrepareFuelFlow(Dt);       // раздать FuelSupplyRatio
    ApplyEngineForces();       // AddForceAtLocation(F, Module->GetActorLocation())
    ApplyFuelFlow(Dt);         // списать расход + перекачать из внешних баков
    ApplyGravity();            // AddForce(Sim->GetGravityAt(pos) * Mass)
    RecalculateMassProperties(); // масса и центр масс от текущего топлива
}
```

**Гимбал** (порт `ship.gd:133-157`): дельта = клавиатура (`gimbal_cw` E: +2·dt рад; `gimbal_ccw` Q: −2·dt рад) + стик. Стик — **относительное** управление: угол стика `atan2(x, −y)` (верх = 0, по часовой +); дельта = разница с прошлым кадром, свёрнутая в [−π, π], × 0.10; активируется при |stick| > 0.2, при отпускании состояние сбрасывается. Дельта рассылается всем модулям (`ApplyGimbalDelta`); не-двигатели её игнорируют.

**Топливный флоу — двухфазный** (порт `ship.gd:194-243`):

Фаза 1, `PrepareFuelFlow`: всем модулям `FuelSupplyRatio = 1`; `Requested = Σ GetRequestedFuelDrain(Dt)`; `DrainRatio = Requested > 0 ? min(Fuel / Requested, 1) : 1`; модулям с запросом > 0 выставить `FuelSupplyRatio = DrainRatio`. Так при нехватке топлива тяга и расход всех двигателей пропорционально ослабевают, вместо резкого отключения.

Фаза 2, `ApplyFuelFlow` (после применения сил):
```cpp
float Drain = Σ Module->GetFuelDrain(Dt);                  // фактический расход
float FuelAfterDrain = max(Fuel - Drain, 0);
// Перекачка из внешних баков, пропорционально их потенциалу:
float TotalPotential = Σ Module->GetPotentialFuelIntake(Dt);
float Room = MaxFuel - FuelAfterDrain;
float TotalIntake = min(TotalPotential, Room);
float Ratio = TotalPotential > 0 ? TotalIntake / TotalPotential : 0;
for (по модулям с potential > 0) Module->CommitFuelIntake(Potential * Ratio);
Fuel = FuelAfterDrain + TotalIntake;
if (изменилось) OnFuelChanged.Broadcast(Fuel, MaxFuel);
```

**Масса и центр масс** (порт `ship.gd:251-265`, каждый тик):

```cpp
float Total = HullDryMass + Fuel * FUEL_UNIT_MASS;
FVector Weighted = FVector::ZeroVector;
for ((Binding, Module) : Modules)
{
    float M = Module->GetMass();
    if (M > 0)
    {
        FVector LocalPos = MountTransform.TransformPosition(Module->RelativeLocation);
        Total += M;  Weighted += M * LocalPos;
    }
}
Body->SetMassOverrideInKg(NAME_None, Total, true);
Body->GetBodyInstance()->COMNudge = Weighted / Total; // кастомный CoM (пересчитать в конвенцию UE)
Body->GetBodyInstance()->UpdateMassProperties();
```

**Краш** (порт `ship.gd:268-315`): по `OnComponentHit` с `ACelestialBody` — **безусловно** (порога скорости нет):
- флаг `bCrashed`; всем модулям `bActive=false, Intensity=0`;
- обнулить скорости, заморозить физику (`SetSimulatePhysics(false)` или constraint-freeze), отключить тик;
- вычислить точку краша: проекция позиции корабля на поверхность тела (`BodyPos + normalize(ShipPos−BodyPos) * Radius`, радиус из коллизии с учётом скейла, фолбэк `BodyData->Radius`);
- `OnCrashed.Broadcast(CrashPosition)`.

**Замена модуля в рантайме** — `ApplyLoadoutChange(EMountBinding, UModuleProfile*)` (порт `ship.gd:35-59`): уничтожить старый модуль, заспавнить новый (или ничего, если профиль null — «снять модуль»), обновить копию loadout-а, пересчитать массу. Вызывается экраном модификации (§8.3).

**Дебаг-геттеры** (нужны визуализатору, §9): `GetDebugThrustForceSamples()` — список `{модуль, точка приложения, вектор силы}` по модулям с ненулевой тягой; `GetDebugTotalThrustForce()`; `GetDebugGravityAcceleration()`.

---

## 6. Управление (Enhanced Input)

Актуальный Input Map из [project.godot](../godot/project.godot):

| Input Action | Тип | Клавиатура | Геймпад |
|---|---|---|---|
| `IA_MountFront` | Digital (hold) | W | Y (Face Top) |
| `IA_MountRear` | Digital (hold) | S | A (Face Bottom) |
| `IA_MountLeft` | Digital (hold) | A | X (Face Left) |
| `IA_MountRight` | Digital (hold) | D | B (Face Right) |
| `IA_Thrust` | Axis1D 0..1 | Space (=1.0) | Right Trigger (deadzone 0.1) |
| `IA_GimbalCW` | Digital | E | — |
| `IA_GimbalCCW` | Digital | Q | — |
| `IA_GimbalStick` | Axis2D | — | Left Thumbstick (deadzone 0.2 в коде корабля) |
| `IA_Restart` | Digital | R | Start |
| `IA_StationDock` | Digital | F | Left Shoulder (LB), deadzone 0.5 |
| `IA_MenuAccept` | Digital | Enter (ui_accept) | A |
| `IA_MenuCancel` | Digital | Escape (ui_cancel) | B |
| `IA_PauseMenu` | Digital | Escape | Back/Select |
| `IA_DebugToggle` | Digital | F3 | — |

Семантика: зажатая mount-кнопка активирует модуль в слоте (любой — двигатель даёт тягу, внешний бак перекачивает топливо), `IA_Thrust` — общая интенсивность для всех активных модулей. Обратить внимание: **E = по часовой (cw), Q = против (ccw)** — в ранней версии спеки было наоборот.

Меню-действия (`MenuAccept/MenuCancel/PauseMenu`) в Godot обрабатываются поллингом поверх фокуса UI; в UE отдать это Common UI (см. §8), оставив те же биндинги.

---

## 7. Геймплейная обвязка

### 7.1. `ACameraRig` (порт [camera_rig.gd](../godot/scripts/camera_rig.gd) + `camera_rig.tscn`)

Каждый физический тик копирует **X/Y-позицию** (без высоты) и **yaw** корабля — корабль на экране всегда «носом вверх». При `SetTarget` — мгновенный снап. Камера-child: высота ≈ 47 м над плоскостью, продольный сдвиг ≈ −7.26 м, перспектива, FOV 77.7°, near 0.1, far 200, смотрит вертикально вниз. `SetTarget(nullptr)` — камера остаётся на месте (меню).

### 7.2. `ATarget` (порт [target.gd](../godot/scripts/target.gd))

Area-триггер: overlap с кораблём → `OnTargetReached`. Один на уровень.

### 7.3. `AFuelPickup` (порт [fuel_pickup.gd](../godot/scripts/fuel_pickup.gd))

Area-триггер: overlap с кораблём → `Ship->Fuel = min(Fuel + FuelAmount, MaxFuel)` (по умолчанию +50), эмит `OnFuelChanged`, самоуничтожение.

### 7.4. `AStation` (порт [station.gd](../godot/scripts/station.gd), [station_profile.gd](../godot/scripts/station_profile.gd))

Area-триггер (сфера радиусом `Profile->DockRadius`, по умолчанию 8). События `OnShipEnteredRange/OnShipExitedRange`. `UStationProfile : UPrimaryDataAsset`: `DisplayName`, `TArray<UModuleProfile*> AvailableModules`, `DockRadius`. Референс: `full_service.tres`.

### 7.5. Уровень (порт [level.gd](../godot/scripts/level.gd))

На каждый уровень — `ALevelManager` (или Level Blueprint + C++ актор):

- Поля интро: `IntroMessage` (multiline), `IntroTimeoutSeconds` (0 = только кнопка), `bIntroShowContinueButton`, `IntroContinueButtonText`.
- `bDebugVisualsEnabled` + тоггл по F3.
- `BeginPlay`: собрать все `ACelestialBody` уровня → `Sim->InitializeBodies(...)` (позиции из размещения на карте, скорости из `InitialVelocity`), проставить `SimIndex`; найти корабль, подписаться на `OnCrashed`; подписаться на `OnTargetReached` всех целей → `OnLevelCompleted`; создать `ADebugFlightVisualizer` (§9).
- Геттеры для HUD/миникарты: корабль, цель, тела, станции, пикапы.
- `SpawnCrashExplosion(Position)` — заглушка-хук (эффект — визуальный слой, вне скоупа), вызывается game flow при краше.

Уровни оригинала: `level_001, level_002, level_010, level_015, level_020` (5 карт).

### 7.6. Game flow (порт [main.gd](../godot/scripts/main.gd))

В Godot main-сцена персистентна: камера, HUD и слой меню живут всегда, уровень инстанцируется/уничтожается как ребёнок, пауза — глобальная. В UE рекомендуемый эквивалент:

- **Один персистентный .umap** (камера-риг, GameMode, UI) + уровни как **Level Instances / streamed sublevels**, загружаемые-выгружаемые `AGameFlow`-ом. Это точнее воспроизводит потоки пауз/оверлеев, чем `OpenLevel` на каждую карту, и не рвёт `UGameInstanceSubsystem`.
- Альтернатива (проще, допустимо): по .umap на уровень + `OpenLevel`; тогда оверлеи и HUD создаёт GameMode каждой карты. Кросс-уровневой персистентности нет (loadout живёт в пределах уровня), так что оба варианта корректны.

Логика `AGameFlow` (состояния и переходы — прямой порт):

- `Levels: TArray<...>` — список уровней; меню выбора генерирует кнопки «Level N».
- **Меню** (`ShowMenu`): скрыть все оверлеи, показать LevelSelect (+ кнопка «Restart Level» только если уровень загружен), спрятать HUD, пауза.
- **Загрузка уровня**: защита от реентерабельности (`bLoading`), закрыть экран модификации, сбросить состояние станции, выгрузить старый уровень (дождаться), загрузить новый, привязать камеру и HUD (`Setup(ship, camera, target, level)`), подписаться на станции, показать **интро-оверлей**.
- **Интро-оверлей**: затемнение + текст + кнопка «Продолжить» (текст настраивается); если `IntroTimeoutSeconds > 0` — автозакрытие по таймеру (с sequence-счётчиком против гонок при перезагрузке); пауза, пока открыт. Escape/B из интро — в меню.
- **Краш**: заглушить событие, если открыт любой оверлей или идёт загрузка; заспавнить взрыв, скрыть HUD, подождать 2.0 с (`CRASH_OVERLAY_DELAY_SECONDS`, с проверкой sequence/уровня после таймера) → оверлей «вы разбились»: «Перезапустить уровень» / «В главное меню»; также R = рестарт, Escape/B = меню; пауза.
- **Завершение уровня**: игнорировать, если открыт интро/completion; оверлей «уровень завершён»: «следующий» (disabled на последнем уровне) / «в меню»; пауза.
- **Станции**: вход в радиус → HUD-подсказка «F · LB — стыковка с {имя}»; `IA_StationDock` при активной станции → открыть экран модификации; закрытие экрана → вернуть подсказку, если корабль ещё в радиусе; выход из радиуса убирает подсказку (если экран не открыт — иначе состояние сохраняется).
- **Ввод вне оверлеев**: R — перезагрузка текущего уровня (не в меню); Escape/Back — открыть/закрыть меню.
- **Возврат в меню**: выгрузка уровня, `CameraRig->SetTarget(nullptr)`, `Sim->Clear()`, показать меню.

Все таймеры оверлеев должны тикать при паузе (в Godot — `PROCESS_MODE_ALWAYS` / таймеры с `process_always`; в UE — `bTickEvenWhenPaused`, `SetTimer` с `bLooping=false` на не-паузируемом объекте).

---

## 8. UI (UMG + Common UI)

Вся навигация в Godot-оригинале — фокус + поллинг `menu_accept`/`menu_cancel` (это был источник багов с геймпадом, чинившихся отдельными коммитами). В UE **не воспроизводить поллинг** — использовать Common UI (`UCommonButtonBase`, `UCommonActivatableWidget`, Input Routing), которая даёт геймпад-навигацию и «A = нажать сфокусированное» из коробки. Паритет нужен по поведению, не по реализации.

### 8.1. `WBP_HUD` (порт [hud.gd](../godot/scripts/hud.gd))

- **Fuel bar** + label «Fuel: N%» (bottom-left), подписка на `OnFuelChanged`.
- **Dock prompt** (top-center): «F · LB — стыковка с {станция}», show/hide из game flow.
- **Off-screen индикатор цели**: если цель в кадре — скрыт; иначе — стрелка на краю экрана (padding 36 px от края), направленная от центра экрана к спроецированной позиции цели (если цель за камерой — направление инвертировать), позиция — пересечение направления с прямоугольником экрана. Реализация: `ProjectWorldLocationToScreen` + расчёт в `NativeTick`, отрисовка — повёрнутый Image или NativePaint.
- **Minimap** (top-right, 184×184): см. 8.2.
- `Setup(Ship, Camera, Target, Level)` вызывается game flow-ом после загрузки уровня.

### 8.2. Миникарта

Порт вложенного класса `Minimap` из `hud.gd`. Кастомная отрисовка (в UE — `UUserWidget::NativePaint` с `FSlateDrawElement::MakeLines/MakeBox`), каждый кадр:

- **Авто-фрейминг**: собрать XZ(→XY)-позиции корабля, цели, всех тел, станций, пикапов; bounding box + world padding 35, минимальный охват 80×80; равномерный масштаб с внутренним отступом 18 px.
- Фон, рамка, сетка 4×4.
- Иконки: небесное тело — круг радиусом `clamp(Radius*scale, 4, 18)` с внешним кольцом; чёрная дыра — тёмный круг + яркое кольцо; станция — квадрат с крестом; пикап — точка; цель — ромб; корабль — треугольник, ориентированный по yaw.

### 8.3. `WBP_ShipModifierScreen` (порт [ship_modifier_screen.gd](../godot/scripts/ship_modifier_screen.gd))

Полноэкранный модальный экран (пауза при открытии). Два состояния:

1. **PICK_MOUNT**: схема корабля — центр «КОРПУС», вокруг 4 чипа слотов (НОС/КОРМА/ЛЕВЫЙ/ПРАВЫЙ) с именем установленного модуля или «(пусто)». Навигация: стрелки/D-pad выбирают слот по направлению (вверх=нос, вниз=корма, влево/вправо); Accept — к выбору модуля; Cancel или `IA_StationDock` — закрыть.
2. **PICK_MODULE**: панель списка — все `AvailableModules` станции + последний пункт «(снять модуль)» (= профиль null); курсор стартует на текущем модуле слота; вверх/вниз с циклом; Accept — применить (`ApplyLoadoutChange`) и вернуться в PICK_MOUNT; Cancel — назад без изменений.

Подсказки по управлению внизу экрана (два варианта текста по состоянию). Нюанс оригинала: 2-кадровый кулдаун после открытия, чтобы «проглотить» нажатие, открывшее экран, — в UE решается корректным потреблением input-события при активации виджета (Common UI Input Routing).

### 8.4. `WBP_LevelSelect` (порт [level_select.gd](../godot/scripts/level_select.gd))

Полноэкранное меню: кнопки «Level 1..N», «Restart Level» (видна только при загруженном уровне; фокус по умолчанию на ней, иначе — на первом уровне), «Quit». Клавиатура + геймпад.

### 8.5. Оверлеи интро / краша / завершения

Три однотипных полноэкранных оверлея (затемнение + центральная панель + кнопки), описаны в §7.6. Каждый — `UCommonActivatableWidget` с фокусом по умолчанию на главной кнопке. Работают при паузе.

---

## 9. Дебаг-визуализация полёта

Порт [debug_flight_visualizer.gd](../godot/scripts/debug_flight_visualizer.gd). Тоггл F3 (сохранить — основной инструмент проверки паритета физики с Godot-версией). Реализация в UE: `DrawDebugLine`/`ULineBatchComponent`, всё приподнято над плоскостью на `VisualHeightOffset = 0.45`.

Рисует каждый физический тик:
- **Стрелки тяги** (зелёные) — по одной на модуль с ненулевой тягой, из точки модуля, длина `clamp(|F|*0.04, 0.75, 5.0)`.
- **Гравитация корабля** (голубая, scale 0.45) и **скорость** (белая, scale 0.12).
- **Прогноз траектории корабля** (жёлтая, 4 с шагом 0.12): semi-implicit Euler от текущих позиции/скорости; ускорение = `Sim->GetGravityAt(pos)` + текущее тяговое ускорение (константа на весь прогноз), plane-lock на каждом шаге.
- Для нестационарных тел: **стрелка гравитационного ускорения** (пурпурная, `GetBodyGravityAcceleration`) и **прогноз пути** (оранжевый, `PredictBodyPaths(4.0, 0.12)`).

Параметры (scales, длины стрелок, seconds/step) — `UPROPERTY(EditAnywhere)` с дефолтами из оригинала.

---

## 10. Фиксированный шаг и детерминизм

- Godot-логика живёт в `_physics_process` @ 60 Гц. В UE: `Max Physics Delta Time = 0.0167`, Substepping on.
- `UCelestialSimSubsystem` — собственный аккумулятор с шагом 1/60 (не зависит от физического таймстепа движка).
- Тик корабля (силы, топливо, масса) выполнять с тем же фиксированным шагом; Enhanced Input читается в игровом тике — для аркадной точности достаточно; bit-exact детерминизм не требуется.
- Damping корабля = 0 (в Godot damp mode «Replace» без значения).
- Chaos ≠ Jolt: отклик столкновений будет отличаться, но т.к. **любое касание тела = краш**, окно расхождений маленькое; настроить restitution/friction только для касаний Target/Station (это overlap-ы, физики нет).

---

## 11. Тесты

Godot-тесты в `tests/` портировать на **Automation Testing Framework** (чисто-логические — `IMPLEMENT_SIMPLE_AUTOMATION_TEST`; сценарные — Functional Tests на тестовой карте):

| Godot-тест | Что проверяет | UE-форма |
|---|---|---|
| `test_celestial_sim.gd` (7 кейсов) | направление/величина гравитации, inverse-square, max-range cutoff, min-range clamp, ограниченность двухтеловой орбиты за 1000 шагов, plane constraint | Simple automation |
| `test_loadout_spawn.gd` | сборка корабля из loadout-а: модули по слотам, масса, топливо | Functional/automation с миром |
| `test_crash_flow.gd` | краш по контакту, позиция краша, заморозка, сигнал | Functional |
| `test_station_flow.gd` | вход/выход из радиуса станции, сигналы | Functional |
| `test_ship_modifier_screen.gd` | навигация экрана модификации, применение/снятие модуля | Functional + Slate-автоматизация |
| `test_debug_flight_visualizer.gd` | thrust-сэмплы, размер прогноза траектории | Simple automation |
| `test_level_select_input.gd` | активация кнопок меню с геймпада | покрывается Common UI, smoke-тест |

---

## 12. Вне скоупа: визуальный слой и его геймплейные хуки

Не портируются (визуал в UE будет другим): шейдеры планет (`planet_atmosphere/surface/clouds.gdshader`), `PlanetVisualData` и генерация 3D-шумов, линзирование чёрной дыры (`black_hole.gdshader`), партиклы выхлопа и взрыва, `background_scatter` (фоновые астероиды), меши/бленды, sky/environment, boot splash.

Геймплейный код обязан предоставить визуальному слою события/состояния:

| Хук | Источник | Для чего |
|---|---|---|
| `bThrusting` / `Intensity` на двигателе | `AEngineModule` | выхлоп, свет |
| `bActive` на модуле | `AShipModule` | подсветка активного слота (у бака — интенсивность перекачки) |
| `OnCrashed(Position)` → `SpawnCrashExplosion` | `AShip` / game flow | эффект взрыва в точке на поверхности тела |
| `BodyData->Radius` | `ACelestialBody` | масштаб любого будущего визуала тела |
| Тип тела (планета/чёрная дыра) | класс актора | иконка миникарты уже сейчас, визуал потом |
| `OnFuelChanged` | `AShip` | HUD и любые индикаторы |

---

## 13. Структура Content/

```
/Content/
├── Blueprints/
│   ├── BP_Ship, BP_CameraRig, BP_LevelManager, BP_GameFlow
│   ├── Modules/ (BP_EngineStandard, BP_TankBasic, BP_TankLarge, BP_CrateSmall, BP_CrateLarge)
│   └── BP_Planet, BP_BlackHole, BP_Target, BP_FuelPickup, BP_Station
├── DataAssets/
│   ├── CelestialBodies/  (DA_PlanetMedium, ...)
│   ├── Hulls/            (DA_Hull_Rectangular)
│   ├── Modules/          (DA_Engine_Standard, DA_Tank_Basic, DA_Tank_Large, DA_Crate_Small, DA_Crate_Large)
│   ├── Loadouts/         (DA_Loadout_Default, _ExtendedRange, _CargoDemo, _TutorialRearOnly)
│   └── Stations/         (DA_Station_FullService)
├── Input/   (IMC_Ship, IMC_Menu, IA_* из §6)
├── Maps/    (Persistent.umap + L_001, L_002, L_010, L_015, L_020)
└── UI/      (WBP_HUD, WBP_Minimap, WBP_LevelSelect, WBP_ShipModifierScreen,
              WBP_IntroOverlay, WBP_CrashOverlay, WBP_CompletionOverlay)
```

Состав уровня: N× `BP_Planet`/`BP_BlackHole` (+ Data Assets), 1× `BP_Ship` (+ loadout), 1× `BP_Target`, 0..N× `BP_FuelPickup`, 0..N× `BP_Station`, 1× `BP_LevelManager`, плейсхолдер-освещение.

---

## 14. Этапы реализации

| Этап | Задача | Раздел |
|---|---|---|
| 1 | Проект UE, плагины, WorldToMeters, коллизионные профили, конвенция осей | §3 |
| 2 | `UCelestialSimSubsystem` + `UCelestialBodyData` + `PredictBodyPaths` + автотесты | §4, §11 |
| 3 | `ACelestialBody`/`ABlackHole` (плейсхолдер-сферы) | §4.3-4.4 |
| 4 | Дебаг-визуализатор (сразу — главный инструмент проверки паритета) | §9 |
| 5 | Data Assets модульной системы + `AShipModule`-иерархия | §5.1-5.2 |
| 6 | `AShip`: сборка из loadout-а, тик, топливный флоу, масса/CoM, гимбал, краш + Enhanced Input | §5.3, §6 |
| 7 | `ACameraRig`, `ATarget`, `AFuelPickup`, `AStation`, `ALevelManager` | §7 |
| 8 | `AGameFlow` + оверлеи (интро/краш/завершение) + LevelSelect | §7.6, §8.4-8.5 |
| 9 | HUD: fuel, dock prompt, off-screen индикатор, миникарта | §8.1-8.2 |
| 10 | Экран модификации корабля (Common UI) | §8.3 |
| 11 | Пересборка 5 уровней, functional-тесты, баланс касаний | §11, §13 |

**Оценка:** 3–5 недель solo-разработчику с опытом UE C++ (шейдерная часть, ранее оценивавшаяся как половина объёма, исключена; добавилась модульная система и UI-экраны).

---

## 15. Чек-лист паритета

- [ ] Симплектический Эйлер, 60 Гц, O(n²), plane lock; два разных закона гравитации (межтеловая vs влияние на корабль).
- [ ] `PredictBodyPaths` идентичен Godot (первая точка = текущая позиция, шаг ≥ 0.01).
- [ ] Корабль собирается из loadout-а; loadout дублируется при спавне.
- [ ] Масса = hull + топливо×0.02 + модули; кастомный CoM каждый тик.
- [ ] Тяга = `−forward × MaxThrust × Intensity × FuelSupplyRatio`; при нехватке топлива тяга ослабевает пропорционально, при нуле — исчезает.
- [ ] Двухфазный топливный флоу; внешний бак качает только при active+thrust, пропорционально потенциалу, с учётом свободного места.
- [ ] Гимбал ±30° (из профиля), клавиатура E(cw)/Q(ccw) 2 рад/с, стик — относительный, deadzone 0.2, чувствительность 0.10, только у активных двигателей.
- [ ] **Краш при любом контакте** с небесным телом; заморозка; точка краша на поверхности; оверлей через 2 с.
- [ ] Target/FuelPickup(+50)/Station — overlap-триггеры; станция по профилю (радиус 8, список модулей).
- [ ] Экран модификации: 2 состояния, выбор слота стрелками по направлению, список модулей станции + «(снять модуль)», пауза.
- [ ] Камера: следует X/Y и yaw, высота ≈47 м, FOV 77.7.
- [ ] HUD: fuel bar, dock prompt, off-screen стрелка цели (padding 36), миникарта с авто-фреймингом (padding 35, min 80).
- [ ] Интро-оверлей (текст/таймаут/кнопка настраиваются per-level), краш- и completion-оверлеи; «следующий» disabled на последнем уровне.
- [ ] Ввод: WASD-слоты (Y/A/X/B), Space/RT тяга, R/Start рестарт, F/LB стыковка, Esc/Back меню, F3 дебаг.
- [ ] Дебаг-визуализатор: тяга/гравитация/скорость/траектория корабля + гравитация и пути нестационарных тел.
- [ ] 5 уровней; тесты §11 зелёные.

---

## 16. Известные отличия UE5 vs Godot, которые нужно учесть

1. **Координаты**: правосторонняя Y-up → левосторонняя Z-up; фиксировать конвенцию «вперёд» и направление yaw один раз и проверить знаки гимбала/стика.
2. **`apply_force(force, offset)`** (offset от центра масс) → `AddForceAtLocation(Force, WorldLocation)` (мировая точка). Передавать `Module->GetActorLocation()`.
3. **Динамическая масса/CoM**: `SetMassOverrideInKg` + `COMNudge` + `UpdateMassProperties` каждый тик — проверить стоимость в Chaos; при проблемах обновлять только при изменении топлива на заметную дельту.
4. **Enhanced Input** событийный, Godot-код — поллинговый. Держать состояние (`bActive`, `Intensity`, стик) в полях корабля, обновляемых колбэками, и читать его в фиксированном тике.
5. **UI-навигация**: не воспроизводить Godot-поллинг; Common UI решает геймпад-фокус и «проглатывание» открывшего экран нажатия.
6. **Пауза**: Godot `PROCESS_MODE_ALWAYS` → UE `bTickEvenWhenPaused` / `bIsPausable=false` для game flow, оверлеев и их таймеров.
7. **Chaos vs Jolt**: различия смягчены тем, что любой контакт = краш; следить только за ложными срабатываниями overlap/hit на спавне (спавнить корабль вне коллизий).
8. **Loadout-ассет**: в Godot ресурс дублируется при спавне — в UE не мутировать `UPrimaryDataAsset` напрямую, работать с рантайм-копией.

---

## 17. Источники в исходной кодовой базе

- [scripts/celestial_simulation.gd](../godot/scripts/celestial_simulation.gd) — ядро физики, прогноз путей.
- [scripts/ship.gd](../godot/scripts/ship.gd) — корабль: сборка из loadout, топливный флоу, масса/CoM, гимбал, краш.
- [scripts/ship_module.gd](../godot/scripts/ship_module.gd), [scripts/engine.gd](../godot/scripts/engine.gd), [scripts/external_fuel_tank_module.gd](../godot/scripts/external_fuel_tank_module.gd), [scripts/cargo_module.gd](../godot/scripts/cargo_module.gd) — модули.
- [scripts/hull_data.gd](../godot/scripts/hull_data.gd), [scripts/ship_loadout.gd](../godot/scripts/ship_loadout.gd), [scripts/mount_slot.gd](../godot/scripts/mount_slot.gd), [scripts/module_profile.gd](../godot/scripts/module_profile.gd), [scripts/engine_profile.gd](../godot/scripts/engine_profile.gd), [scripts/fuel_tank_profile.gd](../godot/scripts/fuel_tank_profile.gd), [scripts/cargo_profile.gd](../godot/scripts/cargo_profile.gd) — данные модульной системы.
- [scripts/celestial_body.gd](../godot/scripts/celestial_body.gd), [scripts/celestial_body_data.gd](../godot/scripts/celestial_body_data.gd), [scripts/black_hole.gd](../godot/scripts/black_hole.gd) — небесные тела.
- [scripts/station.gd](../godot/scripts/station.gd), [scripts/station_profile.gd](../godot/scripts/station_profile.gd), [scripts/ship_modifier_screen.gd](../godot/scripts/ship_modifier_screen.gd) — станции и экран модификации.
- [scripts/camera_rig.gd](../godot/scripts/camera_rig.gd), [scripts/level.gd](../godot/scripts/level.gd), [scripts/main.gd](../godot/scripts/main.gd), [scripts/level_select.gd](../godot/scripts/level_select.gd) — камера, уровень, game flow, меню.
- [scripts/hud.gd](../godot/scripts/hud.gd) — HUD: топливо, миникарта, индикатор цели, dock prompt.
- [scripts/debug_flight_visualizer.gd](../godot/scripts/debug_flight_visualizer.gd) — дебаг-визуализация.
- [scripts/target.gd](../godot/scripts/target.gd), [scripts/fuel_pickup.gd](../godot/scripts/fuel_pickup.gd) — триггеры.
- [project.godot](../godot/project.godot) — input map, autoload, физика.
- [resources/](../godot/resources/) — референсные значения hulls/engines/fuel_tanks/cargo/loadouts/stations.
- [tests/](../godot/tests/) — референс для автотестов.
