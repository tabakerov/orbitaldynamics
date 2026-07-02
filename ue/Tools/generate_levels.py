"""Generate the OrbitalDynamics data assets and level maps from the Godot scenes.

Data below is transcribed from godot/scenes/levels/*.tscn and godot/resources/*
with coordinates converted to the UE convention (see docs/UE5_PORT_SPEC.md §3):

    UE = (-godot.z, godot.x, 0)   for positions and velocities

Godot node scale on celestial bodies is baked into the per-instance body radius
(gravity parameters are scale-independent in the original too).

Run headless:
    UnrealEditor-Cmd OrbitalDynamics.uproject -run=pythonscript \
        -script="ue/Tools/generate_levels.py" -stdout -unattended
"""

import unreal

ASSET_TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
EAL = unreal.EditorAssetLibrary

DA_BODIES = "/Game/DataAssets/CelestialBodies"
DA_MODULES = "/Game/DataAssets/Modules"
DA_HULLS = "/Game/DataAssets/Hulls"
DA_LOADOUTS = "/Game/DataAssets/Loadouts"
DA_STATIONS = "/Game/DataAssets/Stations"
MAPS = "/Game/Maps"


def make_data_asset(name, path, cls, props):
    full = "%s/%s" % (path, name)
    if EAL.does_asset_exist(full):
        asset = EAL.load_asset(full)
    else:
        factory = unreal.DataAssetFactory()
        factory.set_editor_property("DataAssetClass", cls)
        asset = ASSET_TOOLS.create_asset(name, path, cls, factory)
    if asset is None:
        raise RuntimeError("Failed to create asset %s" % full)
    for key, value in props.items():
        asset.set_editor_property(key, value)
    EAL.save_loaded_asset(asset)
    unreal.log("DataAsset ready: %s" % full)
    return asset


def build_data_assets():
    assets = {}

    # --- Module profiles (godot/resources/engines|fuel_tanks|cargo) ---
    assets["engine_standard"] = make_data_asset(
        "DA_Engine_Standard", DA_MODULES, unreal.EngineProfile, {
            "ModuleClass": unreal.EngineModule.static_class(),
            "DisplayName": "Standard Engine",
            "MaxThrust": 100.0,
            "FuelConsumptionRate": 10.0,
            "GimbalRangeDeg": 30.0,
            "DryMass": 0.0,
        })
    assets["tank_basic"] = make_data_asset(
        "DA_Tank_Basic", DA_MODULES, unreal.FuelTankProfile, {
            "ModuleClass": unreal.FuelTankModule.static_class(),
            "DisplayName": "Basic Fuel Tank",
            "Capacity": 100.0,
            "DryMass": 1.0,
            "MaxPumpRate": 30.0,
            "StartingFill": 1.0,
        })
    assets["tank_large"] = make_data_asset(
        "DA_Tank_Large", DA_MODULES, unreal.FuelTankProfile, {
            "ModuleClass": unreal.FuelTankModule.static_class(),
            "DisplayName": "Large Fuel Tank",
            "Capacity": 250.0,
            "DryMass": 2.0,
            "MaxPumpRate": 50.0,
            "StartingFill": 1.0,
        })
    assets["crate_small"] = make_data_asset(
        "DA_Crate_Small", DA_MODULES, unreal.CargoProfile, {
            "ModuleClass": unreal.CargoModule.static_class(),
            "DisplayName": "Small Crate",
            "Mass": 5.0,
        })
    assets["crate_large"] = make_data_asset(
        "DA_Crate_Large", DA_MODULES, unreal.CargoProfile, {
            "ModuleClass": unreal.CargoModule.static_class(),
            "DisplayName": "Large Crate",
            "Mass": 20.0,
        })

    # --- Hull (C++ defaults already mirror rectangular.tres) ---
    assets["hull_rect"] = make_data_asset("DA_Hull_Rectangular", DA_HULLS, unreal.HullData, {})

    # --- Loadouts (godot/resources/loadouts) ---
    engine = assets["engine_standard"]
    hull = assets["hull_rect"]
    assets["loadout_default"] = make_data_asset(
        "DA_Loadout_Default", DA_LOADOUTS, unreal.ShipLoadout, {
            "Hull": hull, "StartingInternalFuel": 200.0,
            "FrontModule": engine, "RearModule": engine,
            "LeftModule": engine, "RightModule": engine,
        })
    assets["loadout_tutorial_rear_only"] = make_data_asset(
        "DA_Loadout_TutorialRearOnly", DA_LOADOUTS, unreal.ShipLoadout, {
            "Hull": hull, "StartingInternalFuel": 10.0,
            "RearModule": engine,
        })
    assets["loadout_cargo_demo"] = make_data_asset(
        "DA_Loadout_CargoDemo", DA_LOADOUTS, unreal.ShipLoadout, {
            "Hull": hull, "StartingInternalFuel": 200.0,
            "FrontModule": engine, "LeftModule": engine, "RightModule": engine,
            "RearModule": assets["crate_large"],
        })
    assets["loadout_extended_range"] = make_data_asset(
        "DA_Loadout_ExtendedRange", DA_LOADOUTS, unreal.ShipLoadout, {
            "Hull": hull, "StartingInternalFuel": 100.0,
            "FrontModule": engine, "RearModule": engine, "LeftModule": engine,
            "RightModule": assets["tank_basic"],
        })

    # --- Celestial body data ---
    # planet_medium.tres: mass 5000, radius 5, rest defaults.
    assets["body_planet_medium"] = make_data_asset(
        "DA_Body_PlanetMedium", DA_BODIES, unreal.CelestialBodyData,
        {"Mass": 5000.0, "Radius": 5.0})
    # level_010 inline sub-resource: mass 100, defaults otherwise.
    assets["body_l010_p1"] = make_data_asset(
        "DA_Body_L010_Planet1", DA_BODIES, unreal.CelestialBodyData,
        {"Mass": 100.0})
    # level_020 planets: node scale baked into radius.
    assets["body_l020_p1"] = make_data_asset(
        "DA_Body_L020_Planet1", DA_BODIES, unreal.CelestialBodyData,
        {"Mass": 100.0, "Radius": 4.0})   # radius 2 x node scale 2
    assets["body_l020_p2"] = make_data_asset(
        "DA_Body_L020_Planet2", DA_BODIES, unreal.CelestialBodyData,
        {"Mass": 5000.0, "Radius": 15.0})  # planet_medium x node scale 3
    assets["body_l020_p3"] = make_data_asset(
        "DA_Body_L020_Planet3", DA_BODIES, unreal.CelestialBodyData,
        {"Mass": 50.0, "Radius": 1.0})

    # --- Station profile (full_service.tres) ---
    assets["station_full"] = make_data_asset(
        "DA_Station_FullService", DA_STATIONS, unreal.StationProfile, {
            "DisplayName": "Service Station — Full",
            "AvailableModules": [
                assets["engine_standard"], assets["tank_basic"], assets["tank_large"],
                assets["crate_small"], assets["crate_large"],
            ],
            "DockRadius": 8.0,
        })

    return assets


LEVELS = [
    {
        "name": "L_001",
        "intro": "WASD выбирает двигатели корабля. Пробел - включает выбранные двигатели.\n"
                 "Доберитесь до жёлтой цели; если она за экраном, следуйте указателю у края.",
        "ship": {"pos": (0, 0, 0), "loadout": "loadout_tutorial_rear_only"},
        "target": (100, 0, 0),
        "bodies": [],
        "pickups": [],
        "stations": [],
    },
    {
        "name": "L_002",
        "intro": "Q/E - поворачивают выбранные двигатели",
        "ship": {"pos": (0, 0, 0), "loadout": "loadout_default", "fuel_override": 30.0},
        "target": (35.967472, 35.08354, 0),
        "bodies": [],
        "pickups": [],
        "stations": [],
    },
    {
        "name": "L_010",
        "intro": "Не врезайся в планеты!",
        "ship": {"pos": (-0.22027588, 1.1688194, 0), "loadout": "loadout_default"},
        "target": (112.87228, 0.22620964, 0),
        "bodies": [
            {"pos": (73.466354, -56.63118, 0), "vel": (-9.5, 0, 0), "data": "body_l010_p1"},
            {"pos": (74.26636, 1.3688202, 0), "vel": (0.1, 0, 0), "data": "body_planet_medium"},
        ],
        "pickups": [],
        "stations": [],
    },
    {
        "name": "L_015",
        "intro": "У корабля груз в кормовом слоте вместо двигателя. Залети в фиолетовую станцию "
                 "справа и нажми F (LB на геймпаде) — там можно поменять модули. Дотащи корабль до цели.",
        "ship": {"pos": (0, 0, 0), "loadout": "loadout_cargo_demo"},
        "target": (65, -8, 0),
        "bodies": [],
        "pickups": [],
        "stations": [{"pos": (-4, 14, 0), "profile": "station_full"}],
    },
    {
        "name": "L_020",
        "intro": "",
        "ship": {"pos": (-0.22027588, 1.1688194, 0), "loadout": "loadout_default"},
        "target": (112.87228, 0.22620964, 0),
        "bodies": [
            {"pos": (187.6, -46.6, 0), "vel": (-9.5, 0, 0), "data": "body_l020_p1"},
            {"pos": (162.8, 30.2, 0), "vel": (0.1, 0, 0), "data": "body_l020_p2"},
            {"pos": (162.4, 109.8, 0), "vel": (7, 0, 0), "data": "body_l020_p3"},
        ],
        "pickups": [(71.91403, -19.112026, 0)],
        "stations": [],
    },
]


def vec(t):
    return unreal.Vector(t[0], t[1], t[2])


def build_level(level, assets):
    level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

    asset_path = "%s/%s" % (MAPS, level["name"])
    if EAL.does_asset_exist(asset_path):
        EAL.delete_asset(asset_path)
    if not level_subsystem.new_level(asset_path):
        raise RuntimeError("Failed to create level %s" % asset_path)

    rot0 = unreal.Rotator(0, 0, 0)

    manager = actor_subsystem.spawn_actor_from_class(unreal.LevelManager, vec((0, 0, 0)), rot0)
    if level["intro"]:
        manager.set_editor_property("IntroMessage", level["intro"])

    ship = actor_subsystem.spawn_actor_from_class(unreal.Ship, vec(level["ship"]["pos"]), rot0)
    ship.set_editor_property("Loadout", assets[level["ship"]["loadout"]])
    if "fuel_override" in level["ship"]:
        ship.set_editor_property("StartingFuelOverride", level["ship"]["fuel_override"])

    actor_subsystem.spawn_actor_from_class(unreal.TargetZone, vec(level["target"]), rot0)
    actor_subsystem.spawn_actor_from_class(unreal.CameraRig, vec(level["ship"]["pos"]), rot0)

    for body in level["bodies"]:
        actor = actor_subsystem.spawn_actor_from_class(unreal.CelestialBody, vec(body["pos"]), rot0)
        actor.set_editor_property("BodyData", assets[body["data"]])
        actor.set_editor_property("InitialVelocity", vec(body["vel"]))

    for pos in level["pickups"]:
        actor_subsystem.spawn_actor_from_class(unreal.FuelPickup, vec(pos), rot0)

    for station in level["stations"]:
        actor = actor_subsystem.spawn_actor_from_class(unreal.Station, vec(station["pos"]), rot0)
        actor.set_editor_property("Profile", assets[station["profile"]])

    # Placeholder lighting; the real visual pass is out of scope.
    light = actor_subsystem.spawn_actor_from_class(
        unreal.DirectionalLight, unreal.Vector(0, 0, 100), unreal.Rotator(0, -55, 0))
    light.get_component_by_class(unreal.DirectionalLightComponent).set_editor_property("intensity", 4.0)
    actor_subsystem.spawn_actor_from_class(unreal.SkyLight, unreal.Vector(0, 0, 100), rot0)

    if not level_subsystem.save_current_level():
        raise RuntimeError("Failed to save level %s" % asset_path)
    unreal.log("Level ready: %s" % asset_path)


def main():
    assets = build_data_assets()
    for level in LEVELS:
        build_level(level, assets)
    unreal.log("All levels generated.")


main()
