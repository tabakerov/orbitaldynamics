"""Create Blueprint wrappers for the C++ gameplay classes and wire the game
to use them: BP actors for maps, WBP widgets for the player controller,
BP module classes in the module profiles, BP_GameMode as project default.

C++ stays the behavior layer; the Blueprints are thin subclasses that the
game references, so designers can extend/tune them without touching code.

Run headless:
    UnrealEditor-Cmd OrbitalDynamics.uproject -run=pythonscript \
        -script="ue/Tools/generate_blueprints.py" -stdout -unattended
"""

import unreal

ASSET_TOOLS = unreal.AssetToolsHelpers.get_asset_tools()
EAL = unreal.EditorAssetLibrary

BP_DIR = "/Game/Blueprints"
UI_DIR = "/Game/UI"


def make_blueprint(name, path, parent_class, factory):
    full = "%s/%s" % (path, name)
    if EAL.does_asset_exist(full):
        bp = EAL.load_asset(full)
    else:
        factory.set_editor_property("ParentClass", parent_class)
        bp = ASSET_TOOLS.create_asset(name, path, None, factory)
    if bp is None:
        raise RuntimeError("Failed to create blueprint %s" % full)
    return bp


def make_actor_bp(name, parent_class):
    return make_blueprint(name, BP_DIR, parent_class, unreal.BlueprintFactory())


def make_widget_bp(name, parent_class):
    return make_blueprint(name, UI_DIR, parent_class, unreal.WidgetBlueprintFactory())


def finalize(bp):
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    EAL.save_loaded_asset(bp)
    unreal.log("Blueprint ready: %s" % bp.get_path_name())


def generated_class(bp):
    return unreal.BlueprintEditorLibrary.generated_class(bp)


def set_defaults(bp, props):
    cdo = unreal.get_default_object(generated_class(bp))
    for key, value in props.items():
        cdo.set_editor_property(key, value)


def main():
    # --- Gameplay actor blueprints ---
    bps = {}
    actor_parents = {
        "BP_Ship": unreal.Ship,
        "BP_CelestialBody": unreal.CelestialBody,
        "BP_BlackHole": unreal.BlackHole,
        "BP_TargetZone": unreal.TargetZone,
        "BP_FuelPickup": unreal.FuelPickup,
        "BP_Station": unreal.Station,
        "BP_CameraRig": unreal.CameraRig,
        "BP_LevelManager": unreal.LevelManager,
        "BP_DebugFlightVisualizer": unreal.DebugFlightVisualizer,
        "BP_EngineModule": unreal.EngineModule,
        "BP_FuelTankModule": unreal.FuelTankModule,
        "BP_CargoModule": unreal.CargoModule,
        "BP_PlayerController": unreal.OrbitalPlayerController,
        "BP_GameMode": unreal.OrbitalDynamicsGameMode,
    }
    for name, parent in actor_parents.items():
        bps[name] = make_actor_bp(name, parent)

    # --- Widget blueprints ---
    widget_parents = {
        "WBP_HUD": unreal.ShipHUDWidget,
        "WBP_ModalOverlay": unreal.ModalOverlayWidget,
        "WBP_LevelSelect": unreal.LevelSelectWidget,
        "WBP_ShipModifierScreen": unreal.ShipModifierScreenWidget,
    }
    for name, parent in widget_parents.items():
        bps[name] = make_widget_bp(name, parent)
    for name in widget_parents:
        finalize(bps[name])

    # --- Wire class defaults ---
    set_defaults(bps["BP_LevelManager"], {
        "VisualizerClass": generated_class(bps["BP_DebugFlightVisualizer"]),
    })
    set_defaults(bps["BP_PlayerController"], {
        "HUDWidgetClass": generated_class(bps["WBP_HUD"]),
        "OverlayWidgetClass": generated_class(bps["WBP_ModalOverlay"]),
        "LevelSelectWidgetClass": generated_class(bps["WBP_LevelSelect"]),
        "ModifierScreenWidgetClass": generated_class(bps["WBP_ShipModifierScreen"]),
    })
    set_defaults(bps["BP_GameMode"], {
        "DefaultPawnClass": generated_class(bps["BP_Ship"]),
        "PlayerControllerClass": generated_class(bps["BP_PlayerController"]),
        "LevelManagerClass": generated_class(bps["BP_LevelManager"]),
        "CameraRigClass": generated_class(bps["BP_CameraRig"]),
    })

    for name in actor_parents:
        finalize(bps[name])

    # --- Point the module profiles at the BP module classes ---
    module_class_by_profile = {
        "/Game/DataAssets/Modules/DA_Engine_Standard": "BP_EngineModule",
        "/Game/DataAssets/Modules/DA_Tank_Basic": "BP_FuelTankModule",
        "/Game/DataAssets/Modules/DA_Tank_Large": "BP_FuelTankModule",
        "/Game/DataAssets/Modules/DA_Crate_Small": "BP_CargoModule",
        "/Game/DataAssets/Modules/DA_Crate_Large": "BP_CargoModule",
    }
    for asset_path, bp_name in module_class_by_profile.items():
        profile = EAL.load_asset(asset_path)
        if profile is None:
            raise RuntimeError("Missing module profile %s" % asset_path)
        profile.set_editor_property("ModuleClass", generated_class(bps[bp_name]))
        EAL.save_loaded_asset(profile)
        unreal.log("Profile rewired: %s -> %s" % (asset_path, bp_name))

    unreal.log("All blueprints generated and wired.")


main()
