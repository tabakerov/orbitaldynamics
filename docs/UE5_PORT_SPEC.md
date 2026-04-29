# OrbitalDynamics — Спецификация порта на Unreal Engine 5

Документ описывает полное воссоздание игры OrbitalDynamics (оригинал: Godot 4.6, Forward+, Jolt Physics) в Unreal Engine 5. Цель — паритет по геймплею, физике, визуалу, управлению и структуре уровней.

Рекомендуемая версия: **UE 5.4+** (для удобства работы с Niagara, Enhanced Input, Data Assets, Material Graph, Volumetric). Язык логики: **C++ для систем + Blueprints для композиции/настройки/UI**.

---

## 1. Концепция и геймлуп

Аркадный симулятор орбитального полёта в 2D-плоскости (XZ-плоскость в Godot → XY-плоскость в UE5, см. §3):

- Игрок пилотирует модульный корабль с 4 независимыми двигателями (каждый со своим карданом).
- Физика построена на N-body симуляции гравитации между небесными телами + влиянии суммарной гравитации на корабль.
- Цель уровня — достичь жёлтого тора-цели (Target) при ограниченном запасе топлива.
- Условия проигрыша: столкновение с небесным телом при скорости > 15 м/с (crash) ИЛИ отсутствие топлива (мягкий проигрыш — корабль дрейфует).
- Уровни выбираются через меню, нажатие R — рестарт, Escape — пауза/меню.

---

## 2. Стек UE5 и соответствие Godot

| Godot | UE5 | Комментарий |
|---|---|---|
| `RigidBody3D` (Jolt) | `AStaticMeshActor` с `UPrimitiveComponent::SetSimulatePhysics(true)` или `APawn` с `USphereComponent`/`UBoxComponent` + physics | Для корабля — `APawn` с `UStaticMeshComponent` как root, физика включена |
| `AnimatableBody3D` | `AActor` с `SetActorLocation()` вручную каждый tick | Небесные тела управляются симуляцией, не физикой |
| `Area3D` | `AActor` + `UBoxComponent`/`USphereComponent` со `SetGenerateOverlapEvents(true)` | Target, FuelPickup |
| `Autoload` singleton | `UGameInstanceSubsystem` | Для `CelestialSim` |
| `Resource` (`.tres`) | `UDataAsset` | PlanetVisualData, CelestialBodyData |
| `PackedScene` | `TSubclassOf<AActor>` или Blueprint-класс | Для префабов двигателей, планет, пикапов |
| `GDShader` (spatial) | Material / Custom HLSL Node | Шейдеры планеты и чёрной дыры |
| `NoiseTexture3D` | `UVolumeTexture` (предгенерация) ИЛИ процедурный шум в шейдере | Рекомендую офлайн-генерацию 64³ `UVolumeTexture` |
| `GPUParticles3D` | Niagara System | Выхлоп двигателей |
| `MultiMeshInstance3D` | `UInstancedStaticMeshComponent` (ISM) / `UHierarchicalInstancedStaticMeshComponent` (HISM) | Фоновые астероиды |
| `WorldEnvironment` + `ProceduralSkyMaterial` | Sky Sphere Material + `UPostProcessComponent` | Фон сцены |
| Input Map | **Enhanced Input Subsystem** + `UInputAction` | Все действия — через IA |
| `DirectionalLight3D` | `ADirectionalLight` | Солнце (передаётся в материал планеты) |

**Плагины UE5 (включить):** Enhanced Input, Niagara, Volumetrics (опционально для облачного рендера как альтернатива), Common UI (для меню), Gameplay Debugger.

---

## 3. Система координат и единицы

Godot: X вправо, Y вверх, Z вперёд (правосторонняя). Геймплей на плоскости **X-Z**, Y=0.

UE5: X вперёд, Y вправо, Z вверх (левосторонняя). 1 UE-юнит = 1 см по умолчанию, но для игры с космическими расстояниями **рекомендую 1 UE-юнит = 1 м** (через `WorldSettings->WorldToMeters = 1.0`) — или сохранить физические параметры в сантиметрах, умножая константы на 100.

**Рекомендация:** геймплей в плоскости **X-Y** (Z=0), камера смотрит сверху вниз (−Z). При миграции:
- Godot `Vector3(x, 0, z)` → UE5 `FVector(x, z, 0)` (swap Y↔Z, обнулить Z).
- Ось вращения корабля: Godot Y-axis → UE5 Z-axis.

**Оси заморозки физики корабля:**
- Godot: `axis_lock_linear_y`, `axis_lock_angular_x`, `axis_lock_angular_z`.
- UE5: `FBodyInstance::bLockZTranslation = true`, `bLockXRotation = true`, `bLockYRotation = true` (через `Constraints` в Physics Details или `SetConstraintMode(EDOFMode::XYPlane)`).

---

## 4. Архитектура классов (C++)

### 4.1. `UCelestialSimSubsystem : public UGameInstanceSubsystem`

Заменяет Godot autoload `CelestialSim`. Симуляция N тел, симплектический Эйлер, фиксированный шаг 60 Гц.

```cpp
// CelestialSimSubsystem.h
UCLASS()
class ORBITAL_API UCelestialSimSubsystem : public UGameInstanceSubsystem, public FTickableGameObject
{
    GENERATED_BODY()
public:
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;
    virtual void Deinitialize() override;

    // FTickableGameObject
    virtual void Tick(float DeltaTime) override;
    virtual TStatId GetStatId() const override { RETURN_QUICK_DECLARE_CYCLE_STAT(UCelestialSimSubsystem, STATGROUP_Tickables); }

    UFUNCTION(BlueprintCallable)
    void InitializeBodies(const TArray<UCelestialBodyData*>& Data,
                          const TArray<FVector>& Positions,
                          const TArray<FVector>& Velocities,
                          const TArray<bool>& Stationary);

    UFUNCTION(BlueprintCallable)
    void Clear();

    UFUNCTION(BlueprintCallable)
    FVector GetGravityAt(const FVector& Pos) const;

    UFUNCTION(BlueprintCallable) FVector GetBodyPosition(int32 Index) const;
    UFUNCTION(BlueprintCallable) FVector GetBodyVelocity(int32 Index) const;
    UFUNCTION(BlueprintCallable) int32 GetBodyCount() const;

    UPROPERTY(EditAnywhere, BlueprintReadWrite)
    float GravitationalConstant = 1.0f;

private:
    void Step(float DeltaTime);

    bool bActive = false;
    TArray<FVector> Positions;
    TArray<FVector> Velocities;
    TArray<double> Masses;
    TArray<double> GravityStrengths;
    TArray<double> FalloffExponents;
    TArray<double> MaxRanges;
    TArray<double> MinRanges;
    TArray<bool>   Stationary;

    // Fixed-step accumulator
    static constexpr float FixedStep = 1.0f / 60.0f;
    float Accumulator = 0.0f;
};
```

**Алгоритм шага (паритет с Godot `celestial_simulation.gd:63-90`):**

```cpp
void UCelestialSimSubsystem::Step(float DeltaTime)
{
    const int32 N = Positions.Num();
    TArray<FVector> Accel; Accel.Init(FVector::ZeroVector, N);

    // O(n^2) попарная гравитация
    for (int32 i = 0; i < N; ++i)
        for (int32 j = i + 1; j < N; ++j)
        {
            FVector off = Positions[j] - Positions[i];
            double d = off.Size();
            if (d < 0.001) continue;
            FVector dir = off / d;
            double ai = GravitationalConstant * Masses[j] / (d*d);
            double aj = GravitationalConstant * Masses[i] / (d*d);
            Accel[i] += dir * ai;
            Accel[j] -= dir * aj;
        }

    // Симплектический Эйлер: сначала скорость, потом позиция
    for (int32 i = 0; i < N; ++i)
    {
        if (Stationary[i]) continue;
        Velocities[i] += Accel[i] * DeltaTime;
        Positions[i]  += Velocities[i] * DeltaTime;
        // Z=0 plane lock (в UE5)
        Positions[i].Z = 0.0f;
        Velocities[i].Z = 0.0f;
    }
}
```

**Tick-режим:** использовать фиксированный таймстеп через аккумулятор (не `Tick(DeltaTime)` с переменным шагом), чтобы воспроизвести детерминизм Godot `_physics_process` @ 60 Гц.

```cpp
void UCelestialSimSubsystem::Tick(float DeltaTime)
{
    if (!bActive) return;
    Accumulator += DeltaTime;
    while (Accumulator >= FixedStep)
    {
        Step(FixedStep);
        Accumulator -= FixedStep;
    }
}
```

**`GetGravityAt` (паритет с `celestial_simulation.gd:93-103`):**

```cpp
FVector UCelestialSimSubsystem::GetGravityAt(const FVector& Pos) const
{
    FVector Total = FVector::ZeroVector;
    for (int32 i = 0; i < Positions.Num(); ++i)
    {
        FVector off = Positions[i] - Pos;
        double raw = off.Size();
        if (raw > MaxRanges[i]) continue;
        double d = FMath::Clamp(raw, MinRanges[i], MaxRanges[i]);
        double s = GravityStrengths[i] * Masses[i] / FMath::Pow(d, FalloffExponents[i]);
        Total += off.GetSafeNormal() * s;
    }
    return Total;
}
```

### 4.2. `UCelestialBodyData : public UDataAsset`

```cpp
UCLASS(BlueprintType)
class UCelestialBodyData : public UDataAsset
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere) float Mass = 1000.0f;
    UPROPERTY(EditAnywhere) float GravityStrength = 1.0f;
    UPROPERTY(EditAnywhere) float FalloffExponent = 2.0f;
    UPROPERTY(EditAnywhere) float MaxRange = 80.0f;
    UPROPERTY(EditAnywhere) float MinRange = 2.0f;
    UPROPERTY(EditAnywhere) float Radius = 3.0f;
};
```

### 4.3. `ACelestialBody : public AActor`

Родитель для планет и чёрных дыр. Визуальная оболочка вокруг записи в `CelestialSim`.

```cpp
UCLASS()
class ACelestialBody : public AActor
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere) UCelestialBodyData* BodyData;
    UPROPERTY(EditAnywhere) FVector InitialVelocity = FVector::ZeroVector;
    UPROPERTY(EditAnywhere) bool bStationary = false;

    int32 SimIndex = -1;

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaTime) override;

protected:
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* MeshComp;
    UPROPERTY(VisibleAnywhere) USphereComponent* Collision;

    void SetupVisuals(); // Масштабирует Mesh и Collision по BodyData->Radius
};
```

В `Tick` — `SetActorLocation(Subsystem->GetBodyPosition(SimIndex))`. Регистрация в `ALevelManager::InitCelestialSim()` (см. §4.7).

**Коллизия:** `USphereComponent` с профилем `BlockAllDynamic` (корабль сталкивается, но тело не симулируется физикой).

### 4.4. `APlanet : public ACelestialBody`

Процедурная планета с 3-слойной mesh-структурой (как в Godot `planet.tscn`):
- **Surface** (скрытый, база для коллизии).
- **Clouds** (отключён в текущей реализации, оставлен задел).
- **Atmosphere** (`UStaticMeshComponent` со сферой, материал `M_PlanetAtmosphere` — основной рендер).

```cpp
UCLASS()
class APlanet : public ACelestialBody
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere) UPlanetVisualData* VisualData;

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaTime) override;

protected:
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* AtmosphereComp;
    UPROPERTY() UMaterialInstanceDynamic* AtmoMID;
    UPROPERTY() UVolumeTexture* TerrainNoise;
    UPROPERTY() UVolumeTexture* BiomeNoise;
    UPROPERTY() UVolumeTexture* CloudNoise;

    void GenerateNoiseVolumes(int32 Seed);
    void UpdateShaderParams(); // каждый tick пушит параметры из VisualData
};
```

### 4.5. `UPlanetVisualData : public UDataAsset`

Полный порт `planet_visual_data.gd:1-113`. Все поля в том же диапазоне:

```cpp
UCLASS(BlueprintType)
class UPlanetVisualData : public UDataAsset
{
    GENERATED_BODY()
public:
    // Terrain & Water
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float SeaLevel = 0.4f;
    UPROPERTY(EditAnywhere) FLinearColor WaterColorShallow = FLinearColor(0.3,0.6,0.8);
    UPROPERTY(EditAnywhere) FLinearColor WaterColorDeep = FLinearColor(0.05,0.1,0.3);
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float WaveIntensity = 0.3f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=5)) float WaveSpeed = 0.5f;

    // Biomes (веса нормализуются в шейдере)
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float BiomeVegetation = 0.5f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float BiomeSand = 0.3f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float BiomeRock = 0.2f;
    UPROPERTY(EditAnywhere) FLinearColor ColorVegetation = FLinearColor(0.2,0.55,0.15);
    UPROPERTY(EditAnywhere) FLinearColor ColorSand = FLinearColor(0.85,0.75,0.45);
    UPROPERTY(EditAnywhere) FLinearColor ColorRock = FLinearColor(0.45,0.42,0.4);

    // Mountains
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float MountainIntensity = 0.3f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0.5, ClampMax=16)) float MountainNoiseScale = 4.0f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float SnowLevel = 0.7f;
    UPROPERTY(EditAnywhere) FLinearColor SnowColor = FLinearColor(0.95,0.95,0.98);

    // Clouds
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float CloudCoverageLower = 0.4f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float CloudCoverageUpper = 0.2f;
    UPROPERTY(EditAnywhere) FLinearColor CloudColor = FLinearColor::White;
    UPROPERTY(EditAnywhere, meta=(ClampMin=1.001, ClampMax=1.1)) float CloudLower = 1.003f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=1.005, ClampMax=1.2)) float CloudUpper = 1.02f;

    // Atmosphere
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float AtmosphereDensity = 0.5f;
    UPROPERTY(EditAnywhere) FLinearColor AtmosphereColor = FLinearColor(0.3,0.5,1.0);
    UPROPERTY(EditAnywhere, meta=(ClampMin=1.0, ClampMax=1.5)) float AtmosphereRadius = 1.15f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=5)) float AtmosphereRayleighStrength = 1.0f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=2)) float AtmosphereMieStrength = 0.3f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0.05, ClampMax=1)) float AtmosphereFalloff = 0.35f;
    UPROPERTY(EditAnywhere, meta=(ClampMin=4, ClampMax=128)) int32 AtmosphereSteps = 8;

    // AO
    UPROPERTY(EditAnywhere, meta=(ClampMin=0, ClampMax=1)) float AOStrength = 0.4f;

    // Generation
    UPROPERTY(EditAnywhere) int32 Seed = 0;
    UPROPERTY(EditAnywhere, meta=(ClampMin=0.5, ClampMax=8)) float NoiseScale = 2.0f;
};
```

### 4.6. `AShip : public APawn`

Корабль — Pawn с физикой. Корень: `UStaticMeshComponent` (box 1×0.3×2 м, blue) с `SetSimulatePhysics(true)`, gravity disabled. 4 `USceneComponent` mount-точки как children.

```cpp
UCLASS()
class AShip : public APawn
{
    GENERATED_BODY()
public:
    AShip();

    UPROPERTY(EditAnywhere) TSubclassOf<AShipEngine> FrontEngineClass;
    UPROPERTY(EditAnywhere) TSubclassOf<AShipEngine> RearEngineClass;
    UPROPERTY(EditAnywhere) TSubclassOf<AShipEngine> LeftEngineClass;
    UPROPERTY(EditAnywhere) TSubclassOf<AShipEngine> RightEngineClass;

    UPROPERTY(EditAnywhere) float StartingFuel = 200.0f;
    UPROPERTY(EditAnywhere) float CrashVelocity = 15.0f;

    UPROPERTY(BlueprintAssignable) FOnFuelChanged OnFuelChanged;  // (float Current, float Max)
    UPROPERTY(BlueprintAssignable) FOnShipCrashed OnCrashed;

    float Fuel = 0.f;
    float MaxFuel = 0.f;

    // Engine slots
    UPROPERTY() AShipEngine* EngineFront;
    UPROPERTY() AShipEngine* EngineRear;
    UPROPERTY() AShipEngine* EngineLeft;
    UPROPERTY() AShipEngine* EngineRight;

    // Gimbal stick state
    float PrevStickAngle = 0.f;
    bool  bStickActive = false;

    virtual void BeginPlay() override;
    virtual void Tick(float DeltaTime) override;
    virtual void SetupPlayerInputComponent(UInputComponent* Input) override;

protected:
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* Body;
    UPROPERTY(VisibleAnywhere) USceneComponent* MountFront;
    UPROPERTY(VisibleAnywhere) USceneComponent* MountRear;
    UPROPERTY(VisibleAnywhere) USceneComponent* MountLeft;
    UPROPERTY(VisibleAnywhere) USceneComponent* MountRight;

    void ApplyGravity();
    void ApplyEngineForces();
    void DrainFuel(float DeltaTime);
    void UpdateGimbal(float DeltaTime);

    UFUNCTION() void OnHit(UPrimitiveComponent* HitComp, AActor* Other,
                           UPrimitiveComponent* OtherComp, FVector Normal,
                           const FHitResult& Hit);
};
```

**Константы** (из `ship.gd:21-23`):
```cpp
static constexpr float STICK_DEADZONE = 0.2f;
static constexpr float GIMBAL_KEYBOARD_SPEED = 2.0f;      // rad/s
static constexpr float GIMBAL_STICK_SENSITIVITY = 0.10f;
```

**Настройка физики корабля:**
```cpp
Body->SetSimulatePhysics(true);
Body->SetEnableGravity(false);
Body->GetBodyInstance()->bLockZTranslation = true; // плоскость XY
Body->GetBodyInstance()->bLockXRotation = true;
Body->GetBodyInstance()->bLockYRotation = true;
Body->SetMassOverrideInKg(NAME_None, 10.0f, true);
Body->SetNotifyRigidBodyCollision(true);
Body->OnComponentHit.AddDynamic(this, &AShip::OnHit);
```

**Позиции точек крепления** (из `scenes/ship.tscn`, swap Y↔Z для UE5, в метрах):
- MountFront: `(0, 0, -0.9)` Godot → `(0, -0.9, 0)` UE5, ротация: yaw 180°.
- MountRear:  `(0, 0, 0.9)` → `(0, 0.9, 0)`, yaw 0°.
- MountLeft:  `(-0.5, 0, 0.3)` → `(-0.5, 0.3, 0)`, yaw 90°.
- MountRight: `(0.5, 0, 0.3)` → `(0.5, 0.3, 0)`, yaw −90°.

Правило: локальная ось **-Y** mount-точки (в UE5) — направление выхлопа → вектор тяги = -Y * thrust.

**Tick-логика** (паритет `ship.gd:50-56`):

```cpp
void AShip::Tick(float dt)
{
    Super::Tick(dt);
    UpdateGimbal(dt);     // thrust / engine_active / gimbal_angle уже выставлены Enhanced Input колбэками
    ApplyGravity();
    ApplyEngineForces();
    DrainFuel(dt);
}

void AShip::ApplyGravity()
{
    auto* Sim = GetGameInstance()->GetSubsystem<UCelestialSimSubsystem>();
    FVector G = Sim->GetGravityAt(GetActorLocation());
    Body->AddForce(G * Body->GetMass(), NAME_None, /*bAccelChange*/false);
}

void AShip::ApplyEngineForces()
{
    if (Fuel <= 0.f) return;
    auto TryApply = [&](AShipEngine* E)
    {
        if (!E) return;
        FVector F = E->GetThrustVector();
        if (F.SizeSquared() <= 0.f) return;
        // Аналог Godot apply_force(force, offset) — сила в точке engine.global_position
        Body->AddForceAtLocation(F, E->GetActorLocation());
    };
    TryApply(EngineFront); TryApply(EngineRear);
    TryApply(EngineLeft);  TryApply(EngineRight);
}

void AShip::DrainFuel(float dt)
{
    if (Fuel <= 0.f) return;
    float drain = 0.f;
    auto Add = [&](AShipEngine* E){ if(E) drain += E->GetFuelDrain(dt); };
    Add(EngineFront); Add(EngineRear); Add(EngineLeft); Add(EngineRight);
    if (drain > 0.f) { Fuel = FMath::Max(Fuel - drain, 0.f); OnFuelChanged.Broadcast(Fuel, MaxFuel); }
}

void AShip::OnHit(UPrimitiveComponent*, AActor* Other, UPrimitiveComponent*, FVector, const FHitResult&)
{
    if (Cast<ACelestialBody>(Other))
        if (Body->GetPhysicsLinearVelocity().Size() > CrashVelocity)
            OnCrashed.Broadcast();
}
```

**Гимбал со стика** (порт `ship.gd:77-104`):
```cpp
void AShip::UpdateGimbal(float dt)
{
    float GimbalDelta = 0.f;

    // Keyboard Q/E обрабатывается через IA_GimbalCW/CCW — они пишут в накопительные флаги
    if (bGimbalCWPressed)  GimbalDelta += GIMBAL_KEYBOARD_SPEED * dt;
    if (bGimbalCCWPressed) GimbalDelta -= GIMBAL_KEYBOARD_SPEED * dt;

    // Stick — берём из последнего IA_GimbalStick (Vector2)
    if (CurrentStick.Size() > STICK_DEADZONE)
    {
        // Важно: atan2(x, -y) как в Godot — верх стика = 0, по часовой +
        float StickAngle = FMath::Atan2(CurrentStick.X, -CurrentStick.Y);
        if (bStickActive)
        {
            float d = StickAngle - PrevStickAngle;
            // wrap в [-PI, PI]
            d = FMath::Fmod(d + PI, 2.0f * PI) - PI;
            GimbalDelta += d * GIMBAL_STICK_SENSITIVITY;
        }
        PrevStickAngle = StickAngle;
        bStickActive = true;
    }
    else bStickActive = false;

    auto Apply = [&](AShipEngine* E){ if(E) E->ApplyGimbalDelta(GimbalDelta); };
    Apply(EngineFront); Apply(EngineRear); Apply(EngineLeft); Apply(EngineRight);
}
```

### 4.7. `AShipEngine : public AActor`

Модульный двигатель. Порт `engine.gd:1-47`.

```cpp
UCLASS()
class AShipEngine : public AActor
{
    GENERATED_BODY()
public:
    UPROPERTY(EditAnywhere) float MaxThrust = 100.0f;
    UPROPERTY(EditAnywhere) float GimbalRangeDeg = 30.0f;
    UPROPERTY(EditAnywhere) float FuelConsumptionRate = 10.0f;

    bool  bActive = false;
    float GimbalAngle = 0.f;     // radians
    float ThrustMagnitude = 0.f; // 0..1

    virtual void BeginPlay() override;
    virtual void Tick(float dt) override;

    void ApplyGimbalDelta(float Delta);
    FVector GetThrustVector() const;
    float GetFuelDrain(float dt) const;

protected:
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* MeshComp;
    UPROPERTY(VisibleAnywhere) UStaticMeshComponent* Exhaust;
    UPROPERTY(VisibleAnywhere) UPointLightComponent* ActiveLight; // red, intensity ~3m range
    UPROPERTY(VisibleAnywhere) UNiagaraComponent* Particles;      // выхлоп

    float GimbalRangeRad = 0.f;
};

FVector AShipEngine::GetThrustVector() const
{
    if (!bActive || ThrustMagnitude <= 0.f) return FVector::ZeroVector;
    // Локальная -Y — направление выхлопа (см. §4.6)
    return -GetActorRightVector() * MaxThrust * ThrustMagnitude;
    // Если mount-точки задают -Z как выхлоп (как в Godot), использовать -GetActorForwardVector()
    // при условии соответствующего ремаппинга осей mount-точек
}

void AShipEngine::ApplyGimbalDelta(float Delta)
{
    if (!bActive || Delta == 0.f) return;
    GimbalAngle = FMath::Clamp(GimbalAngle + Delta, -GimbalRangeRad, GimbalRangeRad);
    SetActorRelativeRotation(FRotator(0.f, FMath::RadiansToDegrees(GimbalAngle), 0.f));
    // Godot вращает по Y (up), в UE5 это Yaw по Z.
}

float AShipEngine::GetFuelDrain(float dt) const
{
    if (!bActive || ThrustMagnitude <= 0.f) return 0.f;
    return FuelConsumptionRate * ThrustMagnitude * dt;
}
```

**Визуал Tick:**
```cpp
bool bThrusting = bActive && ThrustMagnitude > 0.f;
Exhaust->SetVisibility(bThrusting);
ActiveLight->SetVisibility(bActive);
if (Particles->IsActive() != bThrusting) bThrusting ? Particles->Activate() : Particles->Deactivate();
```

### 4.8. `ALevelManager : public AActor`

Порт `level.gd`. Кладётся на каждую карту уровня, в `BeginPlay`:
1. Собирает всех `ACelestialBody` на карте.
2. Вызывает `Subsystem->InitializeBodies(data, pos, vel, stationary)`.
3. Находит `AShip` (один на уровень), подписывается на `OnCrashed`.
4. Находит все `ATarget`, подписывается на `OnTargetReached`.
5. Эмитит `OnLevelCompleted` / `OnLevelFailed` в `AGameFlow`.

### 4.9. `AGameFlow : public AGameModeBase`

Порт `main.gd`:
- `TArray<TSoftObjectPtr<UWorld>> Levels` — список уровней.
- `LoadLevel(int32 Index)` через `UGameplayStatics::OpenLevel`.
- Обработка `R` — перезагрузка текущего, `Escape` — показ меню `WBP_LevelSelect`.
- `OnLevelCompleted` → следующий уровень или меню.
- `OnShipCrashed` → перезагрузка уровня.

### 4.10. Интерактивные объекты

**`ATarget : public AActor`** (порт `target.gd`):
- `USphereComponent` или `UBoxComponent` (тор визуально), `GenerateOverlapEvents = true`.
- `OnComponentBeginOverlap` → если `Other` это `AShip` → `OnTargetReached.Broadcast()`.

**`AFuelPickup : public AActor`** (порт `fuel_pickup.gd`):
```cpp
UPROPERTY(EditAnywhere) float FuelAmount = 50.f;

void OnOverlap(..., AShip* Ship)
{
    Ship->Fuel = FMath::Min(Ship->Fuel + FuelAmount, Ship->MaxFuel);
    Ship->OnFuelChanged.Broadcast(Ship->Fuel, Ship->MaxFuel);
    Destroy();
}
```

**`ABlackHole : public ACelestialBody`** — наследует гравитацию, визуал — `UStaticMeshComponent` (плоскость) с материалом лензинга (см. §6.2).

### 4.11. `ACameraRig : public AActor`

Порт `camera_rig.gd`. Ship всегда появляется «вертикально» на экране — камера повторяет XY-позицию и yaw корабля.

```cpp
void ACameraRig::Tick(float dt)
{
    if (!Target) return;
    FVector P = Target->GetActorLocation();
    FRotator R = Target->GetActorRotation();
    SetActorLocation(FVector(P.X, P.Y, 60.f));       // +60 м над плоскостью
    SetActorRotation(FRotator(-90.f, R.Yaw, 0.f));   // смотрит вниз, повторяя yaw
}
```

`UCameraComponent` — child, без локального смещения, проекция `Perspective` (или `Orthographic` если в Godot ортогональ — проверить).

### 4.12. `ABackgroundScatter : public AActor`

Порт `background_scatter.gd`. На `BeginPlay` — заполнить `UInstancedStaticMeshComponent` случайными трансформами в объёме `VolumeSize` (детерминированно по `Seed`).

```cpp
UPROPERTY(EditAnywhere) TArray<FScatterEntry> Entries;
UPROPERTY(EditAnywhere) FVector VolumeSize = FVector(200, 200, 50);
UPROPERTY(EditAnywhere) FVector VolumeOffset = FVector::ZeroVector;
UPROPERTY(EditAnywhere) int32 Seed = 0;

USTRUCT()
struct FScatterEntry
{
    UPROPERTY(EditAnywhere) UStaticMesh* Mesh;
    UPROPERTY(EditAnywhere) UMaterialInterface* MaterialOverride;
    UPROPERTY(EditAnywhere) int32 Count = 100;
    UPROPERTY(EditAnywhere) float ScaleMin = 0.5f;
    UPROPERTY(EditAnywhere) float ScaleMax = 1.5f;
    UPROPERTY(EditAnywhere) bool bRandomRotation = true;
    UPROPERTY(EditAnywhere) bool bYawOnly = false;
};
```

На каждую запись — один `HISMComponent`, в `BeginPlay` добавляем `Count` инстансов с ГПСЧ-инициализацией (`FRandomStream(Seed)`), тени отключены для производительности.

---

## 5. Управление (Enhanced Input)

Создать `Input Actions`:

| Input Action | Value Type | Описание |
|---|---|---|
| `IA_EngineFront` | Digital (bool) | Hold — активен передний двигатель |
| `IA_EngineRear`  | Digital (bool) | Hold — активен задний двигатель |
| `IA_EngineLeft`  | Digital (bool) | Hold — активен левый |
| `IA_EngineRight` | Digital (bool) | Hold — активен правый |
| `IA_Thrust`      | Axis1D (0..1)  | Величина тяги |
| `IA_GimbalCW`    | Digital        | Q / (на геймпаде не привязан) |
| `IA_GimbalCCW`   | Digital        | E |
| `IA_GimbalStick` | Axis2D         | Левый стик (для вращательного управления) |
| `IA_Restart`     | Digital (Trigger Pressed) | R / Start |
| `IA_Pause`       | Digital | Escape |

`Input Mapping Context` (IMC_Ship):

| Action | Key/Axis |
|---|---|
| IA_EngineFront | W, Gamepad Face Button Top (Y) |
| IA_EngineRear | S, Gamepad Face Button Bottom (A) |
| IA_EngineLeft | A, Gamepad Face Button Left (X) |
| IA_EngineRight | D, Gamepad Face Button Right (B) |
| IA_Thrust | SpaceBar (Value=1), Gamepad Right Trigger (Axis) |
| IA_GimbalCW | Q |
| IA_GimbalCCW | E |
| IA_GimbalStick | Gamepad Left Thumbstick 2D-Axis |
| IA_Restart | R, Gamepad Special Right |
| IA_Pause | Escape, Gamepad Special Left |

**Deadzone для стика:** 0.2 (в самом `AShip::UpdateGimbal`, см. §4.6).

В `AShip::SetupPlayerInputComponent` биндить:
- `Started` + `Completed` для `IA_EngineX` → `bActive` на соответствующем `AShipEngine`.
- `Triggered` для `IA_Thrust` → `ThrustMagnitude` на всех двигателях.
- `Triggered`/`Completed` для `IA_GimbalCW/CCW` → флаги в `AShip`.
- `Triggered` для `IA_GimbalStick` → `CurrentStick` (`FVector2D`).
- `IA_Restart`, `IA_Pause` — в `APlayerController` / `AGameFlow`.

---

## 6. Рендеринг и материалы

### 6.1. Материал `M_PlanetAtmosphere`

Наиболее сложный визуал — объединённый волюметрик-шейдер (terrain raymarch + clouds + atmosphere). Прямой порт `resources/shaders/planet_atmosphere.gdshader:1-272`.

**Подход в UE5:**
1. Создать `M_PlanetAtmosphere` со следующими параметрами:
   - `Blend Mode`: Translucent
   - `Shading Model`: Unlit
   - `Two Sided`: false (cull back)
   - `Disable Depth Test`: true
   - `Depth Write`: false
2. Основной вычислительный блок — `Custom HLSL Expression` node. В него целиком переносится логика шейдера: `ray_sphere`, `rayleigh_phase`, `mie_phase`, `get_terrain_radius`, `intersect_terrain`, `compute_surface`, и fragment.
3. **Входы Custom node:**
   - `WorldPos` = `AbsoluteWorldPosition` (пересчитать в локальное пространство планеты).
   - `CameraPos` = `CameraPosition` (тоже в локальное пространство через `InverseTransform`).
   - `SunDirection` — `MPC_Sun.Direction` (см. ниже).
   - `TerrainNoise`, `BiomeNoise`, `CloudNoise` — `Texture3D` (`Volume Texture` сэмплеры).
   - Все uniform'ы из Godot → скалярные/векторные параметры материала.

**Маппинг uniform → Material Parameter:**

| Godot uniform | UE5 Material Parameter | Тип |
|---|---|---|
| `planet_radius` | `PlanetRadius` | Scalar |
| `atmosphere_radius` | `AtmosphereRadius` | Scalar |
| `atmosphere_density` | `AtmosphereDensity` | Scalar |
| `atmosphere_color` | `AtmosphereColor` | Vector |
| `rayleigh_strength` | `RayleighStrength` | Scalar |
| `mie_strength` | `MieStrength` | Scalar |
| `atmosphere_falloff` | `AtmosphereFalloff` | Scalar |
| `atmosphere_steps` | `AtmosphereSteps` | Scalar (static int в HLSL loop) |
| `sun_direction` | `SunDirection` | Vector (из MPC) |
| `cloud_noise` | `CloudNoise` | Volume Texture param |
| `cloud_coverage_lower/upper` | `CloudCoverageLower/Upper` | Scalar |
| `cloud_noise_scale` | `CloudNoiseScale` | Scalar |
| `cloud_lower_radius/upper_radius` | `CloudLowerRadius/UpperRadius` | Scalar |
| `cloud_color` | `CloudColor` | Vector |
| `terrain_noise`, `biome_noise` | `TerrainNoise`, `BiomeNoise` | Volume Texture |
| `sea_level` | `SeaLevel` | Scalar |
| `water_color_shallow/deep` | `WaterColorShallow/Deep` | Vector |
| `wave_intensity`, `wave_speed` | `WaveIntensity`, `WaveSpeed` | Scalar |
| `biome_vegetation/sand/rock` | `BiomeVegetation/Sand/Rock` | Scalar |
| `color_vegetation/sand/rock` | `ColorVegetation/Sand/Rock` | Vector |
| `mountain_intensity`, `mountain_noise_scale` | `MountainIntensity`, `MountainNoiseScale` | Scalar |
| `snow_level`, `snow_color` | `SnowLevel`, `SnowColor` | Scalar + Vector |
| `noise_scale`, `max_displacement` | `NoiseScale`, `MaxDisplacement` | Scalar |
| `ao_strength` | `AOStrength` | Scalar |

В `APlanet::BeginPlay` создать `UMaterialInstanceDynamic` от `M_PlanetAtmosphere` и сетать параметры из `PlanetVisualData`. В `Tick` — пушить динамику (TIME уже есть в UE автоматически).

**HLSL-функция (упрощённый скелет для Custom node):**

```hlsl
// Входы: WorldPos (vec3), CameraPos (vec3) — уже в локальных координатах планеты,
// SunDir (vec3), TerrainTex/BiomeTex/CloudTex (Texture3D), и все параметры.
// Возвращаем float4(emissive.rgb, alpha) — маппится на Emissive+Opacity.

float2 RaySphere(float3 ro, float3 rd, float r)
{
    float b = dot(ro, rd);
    float c = dot(ro, ro) - r*r;
    float disc = b*b - c;
    if (disc < 0) return float2(-1, -1);
    float sq = sqrt(disc);
    return float2(-b - sq, -b + sq);
}
// ... (перенести ray_sphere, rayleigh_phase, mie_phase, get_terrain_radius,
//      intersect_terrain, compute_surface, и основной fragment — почти 1:1 с GLSL)
```

**Важные различия Godot GLSL ↔ UE5 HLSL:**
- `sampler3D` → `Texture3D` + `SamplerState` (`Tex.Sample(Sampler, uvw)`).
- `texture(tex, uv).r` → `Tex.Sample(TexSampler, uv).r`.
- `TIME` → подавать как параметр материала `float Time = View.GameTime` (или использовать `Time` node).
- `mix` → `lerp`.
- `fract` → `frac`.
- `mat4 inverse(MODEL_MATRIX)` → в UE5 получаем через `WorldToLocal` (Material Node) или передаём матрицу планеты как параметр.
- Godot векторы — правосторонние Y-up. При порте внутренней математики можно сохранить «локальную» (сферическую вокруг центра планеты) систему без изменений.

### 6.2. Материал `M_BlackHole`

Порт `resources/shaders/black_hole.gdshader`.
- Blend: Translucent, Unlit, two-sided = false, применяется к плоскости.
- Использует `SceneTexture:PostProcessInput0` (эквивалент `hint_screen_texture`). Необходимо включить `Custom Depth` / использовать `Scene Color` lookup — в UE5 реализуется через **Post Process Material** либо через translucent material с включённым `Scene Color` (в Project Settings: Enable `Translucency can sample scene color`).
- Параметры: `Distortion` (0..0.15), `HorizonSize` (0..0.4), `RingSize` (0..0.4), `RingColor`, `RingIntensity`, `EdgeFadeStart` (0.2..0.5).
- Логика:
  1. Радиальный offset UV от центра плоскости.
  2. Warp = `Distortion / (dist² + 0.005)`.
  3. Сэмпл `SceneColor` с 3 разными смещениями для RGB (хроматическая аберрация).
  4. Event horizon: `smoothstep` затемнение.
  5. Ring: гауссово свечение вокруг `RingSize`.

### 6.3. Солнце и направление света

В Godot `planet.gd` ищет `DirectionalLight3D` в сцене и передаёт его направление в шейдер. В UE5:
- Создать `MaterialParameterCollection` `MPC_Sun` с `Vector` параметром `Direction`.
- В Level Blueprint / `AGameFlow::BeginPlay` — найти `ADirectionalLight`, в Tick писать `GetForwardVector()` в `MPC_Sun.Direction`.
- Все материалы планет и вспомогательные ссылаются на `MPC_Sun.Direction`.

### 6.4. Процедурные текстуры шума (замена `NoiseTexture3D`)

Godot использует `NoiseTexture3D` с `FastNoiseLite` 64×64×64 (по умолчанию), разные seed'ы для terrain/biome/cloud.

**Опции в UE5:**

**Вариант А (рекомендую) — офлайн генерация `UVolumeTexture`:**
1. Editor Utility Widget / commandlet: сгенерировать 64³ texture (FastNoise2 plugin или ручная Perlin/Simplex реализация на C++).
2. Сохранить как `UVolumeTexture` ассет в `/Game/Textures/Noise/`.
3. Для каждого уровня/seed — свой набор трёх ассетов.
4. Альтернативно — динамически создавать через `UVolumeTexture::UpdateSourceFromSourceTextures` в Editor, но runtime-генерацию лучше избегать.

**Вариант Б — процедурный Perlin/Simplex прямо в шейдере (HLSL):** устраняет ассеты, но увеличивает стоимость per-pixel. Подходит если 64³ texture не вписывается в бюджет памяти.

**Плагин FastNoise2** для UE5 упрощает Вариант А.

### 6.5. Небо и фон

- Godot: `WorldEnvironment` + `ProceduralSkyMaterial`.
- UE5: `BP_Sky_Sphere` + материал «звёздное небо». Либо `USkyAtmosphereComponent` + `USkyLightComponent` для ambient. Либо Exponential Height Fog отключён, а фон даёт только `ABackgroundScatter` + sky sphere с дальними звёздами.

### 6.6. Niagara: выхлоп двигателя

Порт `GPUParticles3D` из `engine.tscn`. Создать `NS_EngineExhaust`:
- Emitter: GPU Sprite, emission rate ~50/s, привязан к конусу выхлопа.
- Cone emission: локальная -Y direction, угол 5°.
- Lifetime: 0.3s, начальная скорость 2 м/с.
- Color: ярко-синее/белое пламя, затухающее к оранжевому.
- Параметры Size 0.1 → 0.
- `SetNiagaraVariableFloat("ThrustMagnitude")` из `AShipEngine::Tick` для модуляции rate и размера.

---

## 7. UI

Использовать **UMG** (Common UI опционально).

### 7.1. `WBP_HUD`

Порт `scenes/hud.tscn + hud.gd`:
- Anchored bottom-left (0.02, 0.92, 0.25, 0.96).
- `UProgressBar` — fuel bar.
- `UTextBlock` — «Fuel: X%».
- В `NativeConstruct` подписаться на `AShip::OnFuelChanged`.

### 7.2. `WBP_LevelSelect`

Порт `level_select.gd`:
- Full-screen `ColorRect` (тёмно-синий).
- `UVerticalBox` с кнопками:
  - Для каждого уровня из `AGameFlow::Levels` — кнопка.
  - «Restart Level» (виден только если уровень загружен).
  - «Quit».
- Поддержка навигации с клавиатуры (стрелки) и геймпада (D-pad / Left stick) — через `SetKeyboardFocus` и `FocusRule::Keep`.
- По `IA_Pause` — открыть меню, поставить игру на паузу: `UGameplayStatics::SetGamePaused(true)`. Widget должен работать при `bPauseWhenGameIsPaused = false`.

### 7.3. Entry flow

- `AGameFlow::BeginPlay` → показать `WBP_LevelSelect` → выбор уровня → `UGameplayStatics::OpenLevel(LevelName)` → после загрузки `ALevelManager::BeginPlay` стартует симуляцию и спавнит корабль.

---

## 8. Структура уровней и ассетов

**Папки проекта:**

```
/Content/
├── Blueprints/
│   ├── BP_Ship.uasset
│   ├── BP_EngineFront.uasset, BP_EngineRear.uasset, BP_EngineLeft.uasset, BP_EngineRight.uasset
│   ├── BP_Planet.uasset
│   ├── BP_BlackHole.uasset
│   ├── BP_Target.uasset
│   ├── BP_FuelPickup.uasset
│   ├── BP_BackgroundScatter.uasset
│   ├── BP_CameraRig.uasset
│   └── BP_LevelManager.uasset
├── DataAssets/
│   ├── CelestialBodies/ (DA_PlanetMedium, DA_BlackHoleMassive, ...)
│   └── PlanetVisuals/ (DA_PlanetEarth, DA_PlanetDesert, ...)
├── Input/
│   ├── IMC_Ship.uasset
│   ├── IA_EngineFront/Rear/Left/Right, IA_Thrust, IA_Gimbal*, IA_Restart, IA_Pause
├── Materials/
│   ├── M_PlanetAtmosphere.uasset
│   ├── M_BlackHole.uasset (Post-Process Translucent)
│   └── Functions/
│       └── MF_RaymarchAtmosphere.uasset (custom HLSL node embedded)
├── Textures/
│   └── Noise/
│       ├── VT_Terrain_Seed0.uasset (UVolumeTexture 64³)
│       ├── VT_Biome_Seed0.uasset
│       └── VT_Cloud_Seed0.uasset
├── Niagara/
│   └── NS_EngineExhaust.uasset
├── Meshes/
│   ├── SM_ShipHull.uasset
│   ├── SM_EngineBody.uasset
│   ├── SM_PlanetSphere.uasset (высокополигональная сфера, subdivide_depth=64)
│   ├── SM_TargetTorus.uasset
│   ├── SM_FuelCube.uasset
│   └── Asteroids/ (SM_Asteroid_01..N для scatter)
├── Maps/
│   ├── MainMenu.umap
│   ├── Level_01.umap
│   ├── Level_02.umap
│   └── TestSandbox.umap
└── UI/
    ├── WBP_HUD.uasset
    ├── WBP_LevelSelect.uasset
    └── WBP_PauseMenu.uasset
```

**Level (на примере Level_01):**
- `Directional Light` (солнце).
- `Sky Atmosphere` + `Sky Light` + `Exponential Height Fog` (опционально).
- `BP_CameraRig`.
- 2× `BP_Planet` (с привязанными `DA_PlanetEarth`, `DA_PlanetDesert` + соответствующими `DA_PlanetMedium` / `DA_PlanetMassive`).
- 1× `BP_Ship` (+ 4 engine class overrides).
- 1× `BP_Target`.
- 1..N× `BP_FuelPickup`.
- 1× `BP_BlackHole`.
- 1× `BP_BackgroundScatter`.
- 1× `BP_LevelManager` (одиночка).

---

## 9. Фиксированный шаг физики и детерминизм

Godot `_physics_process` стабильно работает @ 60 Гц.

В UE5:
- `Project Settings → Engine → General → Max Physics Delta Time` = 0.0167 (60 Гц).
- `Substepping` = true, `Max Substep Delta Time` = 0.0167, `Max Substeps` = 6.
- `UCelestialSimSubsystem` использует собственный аккумулятор (см. §4.1) — **не** зависит от физического таймстепа, но значения берутся из реального `DeltaTime`.
- Корабль: силы применяются в `Tick` (а не в `AsyncPhysicsTick`), чтобы видеть последний `CurrentStick` из Enhanced Input. Это приемлемо для 2D-аркадной точности; если нужен bit-exact детерминизм — перенести в `Async Physics Tick`.

---

## 10. Тесты

Порт `tests/test_celestial_sim.gd`. Использовать **Automation Testing Framework** UE5:

```cpp
// Tests/OrbitalDynamicsTests.cpp
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCelestialSim_InverseSquareFalloff,
    "OrbitalDynamics.CelestialSim.InverseSquareFalloff",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCelestialSim_InverseSquareFalloff::RunTest(const FString&)
{
    UCelestialSimSubsystem* Sim = NewObject<UCelestialSimSubsystem>();
    UCelestialBodyData* D = NewObject<UCelestialBodyData>();
    D->Mass = 100; D->GravityStrength = 1; D->FalloffExponent = 2;
    D->MaxRange = 1000; D->MinRange = 0.1f;
    Sim->InitializeBodies({D}, {FVector::ZeroVector}, {FVector::ZeroVector}, {true});

    FVector g1 = Sim->GetGravityAt(FVector(10,0,0));
    FVector g2 = Sim->GetGravityAt(FVector(20,0,0));
    TestNearlyEqual("4× falloff", g1.Size() / g2.Size(), 4.0f, 0.01f);
    return true;
}
```

Покрыть все 7 тестов Godot (см. оригинал, §11 обзора): направление, величина, inverse-square, max range cutoff, min range clamp, bounded two-body orbit за 1000 шагов, Z=0 plane constraint.

---

## 11. Инструменты (Orbit Planner)

Godot-инструмент `tools/orbit-planner.html` — автономный HTML/JS планировщик. Может быть:
- Оставлен как есть (HTML/JS), использоваться отдельно, конфиг экспортируется и вручную вставляется в карту UE5.
- Либо переписан как **Editor Utility Widget** внутри UE5 — 2D preview орбит с тем же Symplectic Euler в Blueprint/C++, и функцией «применить на текущий уровень» (расставить `BP_Planet` актёры с нужными positions/velocities).

Рекомендую второй подход для целостности workflow, но это отдельная задача.

---

## 12. Этапы реализации (рекомендуемый порядок)

| Этап | Задача | Готовность |
|---|---|---|
| 1 | Создать UE5 проект, включить плагины, настроить WorldToMeters, Max Physics Δt, профили коллизий | — |
| 2 | `UCelestialSimSubsystem` + `UCelestialBodyData` + автотесты | Порт §4.1-4.2, §10 |
| 3 | `ACelestialBody` + `APlanet` (без шейдера — просто сфера) | §4.3, §4.4 |
| 4 | `AShipEngine` + `AShip` + Enhanced Input (без визуала) | §4.6-4.7, §5 |
| 5 | `ACameraRig` | §4.11 |
| 6 | `ATarget` + `AFuelPickup` + `ALevelManager` + `AGameFlow` | §4.8-4.10 |
| 7 | UMG HUD + Level Select + Pause | §7 |
| 8 | Первый уровень `Level_01` — геймплей end-to-end | §8 |
| 9 | `M_PlanetAtmosphere` — перенос HLSL (объём работы эквивалентен остальной игре вместе взятой) | §6.1 |
| 10 | Генерация `UVolumeTexture` шумов | §6.4 |
| 11 | `M_BlackHole` post-process | §6.2 |
| 12 | Niagara `NS_EngineExhaust` | §6.6 |
| 13 | `ABackgroundScatter` (HISM) | §4.12 |
| 14 | Второй уровень, балансировка | §8 |
| 15 | Editor Utility Widget «Orbit Planner» (опционально) | §11 |

**Оценка:** 4–6 недель для solo-разработчика с опытом UE5 C++; ~2 недели ядро геймплея + 2 недели шейдер планеты + неделя полировки/UI.

---

## 13. Чек-лист паритета с оригиналом

- [ ] Симплектический Эйлер, 60 Гц, O(n²), Z=0 plane lock.
- [ ] N-body через Data Asset, разные falloff_exponent допустимы.
- [ ] Корабль: 4 модульных двигателя, каждый с собственным ±30° гимбалом.
- [ ] Thrust — аналоговый (0..1), общий на все активные.
- [ ] Гимбал от keyboard Q/E (инкрементально) и от стика (по угловой скорости).
- [ ] Топливо расходуется только активными двигателями пропорционально `thrust_magnitude`.
- [ ] Crash при `|v| > 15`.
- [ ] Target — Area; победа при overlap.
- [ ] FuelPickup — Area; +50 топлива, self-destroy.
- [ ] Камера над кораблём на +60 м, повторяет yaw.
- [ ] Планета: 3-слойная геометрия, но рендер через один Custom HLSL материал (terrain + clouds + atmo).
- [ ] Параметры: sea_level, biome_*, mountain_*, snow_*, cloud_*, atmosphere_* — полный список §4.5.
- [ ] Черная дыра: lensing + chromatic aberration + accretion ring.
- [ ] BackgroundScatter на HISM.
- [ ] Меню с выбором уровня + Restart + Quit + пауза.
- [ ] R — рестарт, Escape — меню/пауза.
- [ ] Гемпад: Y/A/X/B = двигатели, RT = тяга, Left Stick = гимбал, Start = restart.

---

## 14. Известные отличия UE5 vs Godot, которые нужно учесть при разработке

1. **Левосторонняя система координат UE5 vs правосторонняя Godot.** Особенно критично для HLSL-порта — при использовании `WorldToLocal` проверять ориентацию нормалей и знак sun_direction.
2. **`TIME` в Godot** всегда в секундах с момента старта уровня; в UE5 Material — `Time` node даёт `View.GameTime`, что может включать паузы. Для wave animation корректнее использовать `Absolute World Time` или передавать `float CurrentTime` через MID.
3. **Godot `apply_force(force, offset)`** применяет силу в точке относительно центра масс. UE5 `AddForceAtLocation(Force, WorldLocation)` принимает мировые координаты — разница в том, что offset нужно передавать как `EngineActor->GetActorLocation()`, не как local-offset.
4. **Godot RigidBody mass в 10 кг** vs default UE5 автоматически рассчитывает массу от mesh-объёма. Обязательно `SetMassOverrideInKg(10.0f, true)`.
5. **Enhanced Input** поставляет значения только когда кто-то «читает» их — следить, что `IA_Thrust` → `Triggered` сработает каждый кадр при удерживании.
6. **Сфера 64-subdivision** в UE5 можно получить через `Engine/BasicShapes/Sphere` + Tessellation ИЛИ сгенерировать высокодетализированную через `UProceduralMeshComponent`. Для raymarch-атмосферы геометрия важна только для bounding bounds шейдера, субдивайд избыточен — достаточно 32-сегментной сферы.
7. **Godot Jolt** и **UE5 Chaos** — разные движки. Результаты столкновений (напр., bounce при касании планеты) будут ощущаться по-разному; при необходимости настроить `Restitution` и `Friction` на материалах физики.

---

## 15. Источники в исходной кодовой базе

Документ основан на анализе:

- [scripts/celestial_simulation.gd](scripts/celestial_simulation.gd:1) — ядро физики.
- [scripts/ship.gd](scripts/ship.gd:1), [scripts/engine.gd](scripts/engine.gd:1) — корабль и двигатели.
- [scripts/celestial_body.gd](scripts/celestial_body.gd:1), [scripts/planet.gd](scripts/planet.gd:1), [scripts/black_hole.gd](scripts/black_hole.gd:1) — небесные тела.
- [scripts/celestial_body_data.gd](scripts/celestial_body_data.gd:1), [scripts/planet_visual_data.gd](scripts/planet_visual_data.gd:1) — Data Assets.
- [scripts/camera_rig.gd](scripts/camera_rig.gd:1), [scripts/level.gd](scripts/level.gd:1), [scripts/main.gd](scripts/main.gd:1), [scripts/level_select.gd](scripts/level_select.gd:1), [scripts/hud.gd](scripts/hud.gd:1) — уровневая инфраструктура.
- [scripts/background_scatter.gd](scripts/background_scatter.gd:1), [scripts/fuel_pickup.gd](scripts/fuel_pickup.gd:1), [scripts/target.gd](scripts/target.gd:1) — вспомогательные объекты.
- [resources/shaders/planet_atmosphere.gdshader](resources/shaders/planet_atmosphere.gdshader:1) — ключевой шейдер (272 строки).
- [resources/shaders/black_hole.gdshader](resources/shaders/black_hole.gdshader:1), [resources/shaders/planet_surface.gdshader](resources/shaders/planet_surface.gdshader:1), [resources/shaders/planet_clouds.gdshader](resources/shaders/planet_clouds.gdshader:1).
- [project.godot](project.godot:1) — input map, autoload, rendering settings.
- [tests/test_celestial_sim.gd](tests/test_celestial_sim.gd:1) — референс для автотестов.
- [docs/superpowers/specs/2026-03-31-orbital-dynamics-design.md](docs/superpowers/specs/2026-03-31-orbital-dynamics-design.md:1), [docs/superpowers/specs/2026-04-03-procedural-planet-shader-design.md](docs/superpowers/specs/2026-04-03-procedural-planet-shader-design.md:1) — оригинальные дизайн-документы.
