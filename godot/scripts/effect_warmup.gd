class_name EffectWarmup
extends Node

## Plays every gameplay effect once behind the boot menu so their shaders
## compile before the first real use. A material's first draw otherwise
## stalls the frame while the driver compiles its program — a noticeable
## freeze, seconds-long on WebGL (first engine burn, first asteroid impact).
##
## The effects must actually be rasterized for the compile to happen —
## anything outside a camera frustum is culled and compiles nothing — so
## they play in a tiny off-screen SubViewport with its own world and camera
## rather than "somewhere behind the screen edge". Frees itself when done.

const ENGINE_SCENE := preload("res://scenes/engine.tscn")
const ROCKET_SCENE := preload("res://scenes/rocket.tscn")
const WEAPON_SCENE := preload("res://scenes/weapon.tscn")
const BLACK_HOLE_SCENE := preload("res://scenes/black_hole.tscn")

## Extra frames the viewport keeps rendering after the last effect is added,
## so every system has emitted and been drawn at least once.
const TRAILING_FRAMES: int = 10

var _viewport: SubViewport
var _pending: Array[Node3D] = []
var _trailing: int = TRAILING_FRAMES


func _ready() -> void:
	# The boot menu pauses the tree; warm-up must keep processing so the
	# particle systems actually emit and render.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_viewport = SubViewport.new()
	_viewport.name = "WarmupViewport"
	_viewport.size = Vector2i(64, 64)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 30.0)
	_viewport.add_child(camera)

	# The compatibility renderer picks shader variants per light type in the
	# scene, so mirror gameplay lighting: a sun (main.tscn) plus omni lights
	# (engine glow, explosion flashes — added below as part of the effects).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	sun.light_energy = 1.5
	_viewport.add_child(sun)

	_pending = _build_effects()


func _process(_delta: float) -> void:
	# One effect per frame: each first draw compiles its shaders
	# synchronously, so spreading them out avoids one long boot stall.
	if not _pending.is_empty():
		_viewport.add_child(_pending.pop_back())
		return
	_trailing -= 1
	if _trailing <= 0:
		queue_free()


func _build_effects() -> Array[Node3D]:
	var effects: Array[Node3D] = []

	var engine_exhaust: GPUParticles3D = _detach(ENGINE_SCENE, "ExhaustParticles")
	engine_exhaust.emitting = true
	effects.append(engine_exhaust)

	# Flame mesh and glow light are hidden until the first burn — first-use
	# hitches of their own (emission material variant, omni-lit variants).
	var engine_flame: MeshInstance3D = _detach(ENGINE_SCENE, "Exhaust")
	engine_flame.visible = true
	effects.append(engine_flame)

	var engine_light: OmniLight3D = _detach(ENGINE_SCENE, "ActiveLight")
	engine_light.visible = true
	effects.append(engine_light)

	var rocket_exhaust: GPUParticles3D = _detach(ROCKET_SCENE, "ExhaustParticles")
	rocket_exhaust.emitting = true
	effects.append(rocket_exhaust)

	var beam: MeshInstance3D = _detach(WEAPON_SCENE, "Beam")
	beam.visible = true
	effects.append(beam)

	effects.append(_make_particles(
		Rocket.build_explosion_material(), Rocket.build_explosion_mesh()))
	effects.append(_make_particles(
		AsteroidCollisions.build_impact_material(), AsteroidCollisions.build_impact_mesh()))
	effects.append(_make_particles(
		Level.build_crash_particle_material(), Level.build_crash_particle_mesh()))

	# Horizon and ring particles (the ring runs a custom particle shader)
	# plus the lensing screen-texture shader.
	var hole: BlackHole = BLACK_HOLE_SCENE.instantiate()
	hole.body_data = CelestialBodyData.new()
	effects.append(hole)

	return effects


## Instantiates the scene without entering the tree (no _ready, no physics)
## and pulls out one node — the cheap way to warm an effect that lives
## inside a gameplay scene without running the gameplay around it.
func _detach(scene: PackedScene, node_name: String) -> Node3D:
	var root := scene.instantiate()
	var node := root.get_node(node_name) as Node3D
	root.remove_child(node)
	root.free()
	return node


func _make_particles(material: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	# Shader code only depends on the materials, not on amount/lifetime —
	# keep the warm-up copies tiny. Full explosiveness so the burst is
	# on screen the very first processed frame.
	particles.amount = 8
	particles.lifetime = 0.5
	particles.explosiveness = 1.0
	particles.emitting = true
	particles.process_material = material
	particles.draw_pass_1 = mesh
	return particles
