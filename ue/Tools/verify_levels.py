"""Sanity-check generated maps: load each and dump the gameplay actors."""

import unreal

MAPS = ["L_001", "L_002", "L_010", "L_015", "L_020"]
CLASSES = [
    unreal.LevelManager, unreal.Ship, unreal.TargetZone, unreal.CelestialBody,
    unreal.FuelPickup, unreal.Station, unreal.CameraRig,
]

level_subsystem = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
actor_subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)

for map_name in MAPS:
    path = "/Game/Maps/%s" % map_name
    if not level_subsystem.load_level(path):
        unreal.log_error("VERIFY %s: failed to load" % map_name)
        continue
    class_names = sorted({a.get_class().get_name() for a in actor_subsystem.get_all_level_actors()})
    unreal.log("VERIFY %s: classes: %s" % (map_name, ", ".join(class_names)))
    counts = []
    for cls in CLASSES:
        actors = [a for a in actor_subsystem.get_all_level_actors() if isinstance(a, cls)]
        if cls is unreal.CelestialBody:
            for a in actors:
                data = a.get_editor_property("BodyData")
                unreal.log("VERIFY %s: body at %s vel=%s data=%s (mass=%s radius=%s)" % (
                    map_name, a.get_actor_location(), a.get_editor_property("InitialVelocity"),
                    data.get_name() if data else None,
                    data.get_editor_property("Mass") if data else "-",
                    data.get_editor_property("Radius") if data else "-"))
        if cls is unreal.Ship:
            for a in actors:
                loadout = a.get_editor_property("Loadout")
                unreal.log("VERIFY %s: ship at %s loadout=%s fuel_override=%s" % (
                    map_name, a.get_actor_location(),
                    loadout.get_name() if loadout else None,
                    a.get_editor_property("StartingFuelOverride")))
        counts.append("%s=%d" % (cls.__name__, len(actors)))
    unreal.log("VERIFY %s: %s" % (map_name, ", ".join(counts)))

unreal.log("VERIFY done")
