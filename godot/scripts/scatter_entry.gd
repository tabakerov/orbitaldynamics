class_name ScatterEntry
extends Resource

## Mesh to scatter.
@export var mesh: Mesh

## Optional material override.
@export var material_override: Material

## Number of instances to generate.
@export var count: int = 100

## Min scale multiplier.
@export var scale_min: float = 0.5

## Max scale multiplier.
@export var scale_max: float = 1.5

## Randomize rotation on all axes.
@export var random_rotation: bool = true

## If false, only randomize Y rotation (useful for upright objects).
@export var random_rotation_y_only: bool = false
