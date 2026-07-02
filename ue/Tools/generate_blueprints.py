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
INPUT_DIR = "/Game/Input"


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


def make_key(key_name):
    key = unreal.Key()
    key.set_editor_property("KeyName", key_name)
    return key


def make_input_action(name, value_type):
    full = "%s/%s" % (INPUT_DIR, name)
    if EAL.does_asset_exist(full):
        action = EAL.load_asset(full)
    else:
        # UInputAction is a UDataAsset, so the plain data-asset factory works.
        factory = unreal.DataAssetFactory()
        factory.set_editor_property("DataAssetClass", unreal.InputAction)
        action = ASSET_TOOLS.create_asset(name, INPUT_DIR, unreal.InputAction, factory)
    action.set_editor_property("ValueType", value_type)
    EAL.save_loaded_asset(action)
    unreal.log("InputAction ready: %s" % full)
    return action


def build_input_assets():
    """IA_*/IMC_Ship assets mirroring the Godot input map (project.godot)."""
    bool_type = unreal.InputActionValueType.BOOLEAN
    axis1 = unreal.InputActionValueType.AXIS1D
    axis2 = unreal.InputActionValueType.AXIS2D

    # name -> (value type, keys)
    spec = {
        "IA_MountFront": (bool_type, ["W", "Gamepad_FaceButton_Top"]),
        "IA_MountRear": (bool_type, ["S", "Gamepad_FaceButton_Bottom"]),
        "IA_MountLeft": (bool_type, ["A", "Gamepad_FaceButton_Left"]),
        "IA_MountRight": (bool_type, ["D", "Gamepad_FaceButton_Right"]),
        "IA_Thrust": (axis1, ["SpaceBar", "Gamepad_RightTriggerAxis"]),
        "IA_GimbalCW": (bool_type, ["E"]),
        "IA_GimbalCCW": (bool_type, ["Q"]),
        "IA_GimbalStick": (axis2, ["Gamepad_Left2D"]),
        "IA_Restart": (bool_type, ["R", "Gamepad_Special_Right"]),
        "IA_DebugToggle": (bool_type, ["F3"]),
    }

    actions = {}
    mappings = []
    for name, (value_type, keys) in spec.items():
        action = make_input_action(name, value_type)
        actions[name] = action
        for key_name in keys:
            mapping = unreal.EnhancedActionKeyMapping()
            mapping.set_editor_property("Action", action)
            mapping.set_editor_property("Key", make_key(key_name))
            mappings.append(mapping)

    imc_path = "%s/IMC_Ship" % INPUT_DIR
    if EAL.does_asset_exist(imc_path):
        imc = EAL.load_asset(imc_path)
    else:
        factory = unreal.DataAssetFactory()
        factory.set_editor_property("DataAssetClass", unreal.InputMappingContext)
        imc = ASSET_TOOLS.create_asset("IMC_Ship", INPUT_DIR, unreal.InputMappingContext, factory)
    imc.set_editor_property("Mappings", mappings)
    EAL.save_loaded_asset(imc)
    unreal.log("InputMappingContext ready: %s" % imc_path)

    actions["IMC_Ship"] = imc
    return actions


def main():
    input_assets = build_input_assets()

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
    set_defaults(bps["BP_Ship"], {
        "InputMapping": input_assets["IMC_Ship"],
        "MountFrontAction": input_assets["IA_MountFront"],
        "MountRearAction": input_assets["IA_MountRear"],
        "MountLeftAction": input_assets["IA_MountLeft"],
        "MountRightAction": input_assets["IA_MountRight"],
        "ThrustAction": input_assets["IA_Thrust"],
        "GimbalCWAction": input_assets["IA_GimbalCW"],
        "GimbalCCWAction": input_assets["IA_GimbalCCW"],
        "GimbalStickAction": input_assets["IA_GimbalStick"],
        "RestartAction": input_assets["IA_Restart"],
        "DebugToggleAction": input_assets["IA_DebugToggle"],
    })
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
