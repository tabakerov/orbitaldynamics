class_name BackgroundLayer
extends Node3D

## Splits rendering into a background and a foreground pass so that
## screen-space effects on the background (the black hole's gravitational
## lensing) can never distort or paint over gameplay objects.
##
## Everything on RENDER_LAYER_MASK (BackgroundScatter instances and the
## black hole's LensingMesh) is rendered by a mirror camera into a
## SubViewport sharing the main World3D; the lens therefore warps only the
## scatter and the sky. That frame is then drawn behind the gameplay scene
## as a fullscreen far-plane quad, and the gameplay camera stops rendering
## the background layer entirely.

## VisualInstance3D layer reserved for background-only objects (layer 2).
const RENDER_LAYER_MASK: int = 1 << 1

const COMPOSITE_SHADER = preload("res://resources/shaders/background_composite.gdshader")

@export var camera_rig_path: NodePath

var _viewport: SubViewport
var _background_camera: Camera3D
var _game_camera: Camera3D


func _ready() -> void:
	var rig := get_node_or_null(camera_rig_path) as CameraRig
	if rig:
		_game_camera = rig.get_camera()
	if not _game_camera:
		push_warning("BackgroundLayer: no game camera found, background layer disabled.")
		return

	_game_camera.cull_mask &= ~RENDER_LAYER_MASK

	_viewport = SubViewport.new()
	_viewport.name = "BackgroundViewport"
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = get_viewport().msaa_3d
	add_child(_viewport)

	_background_camera = Camera3D.new()
	_background_camera.cull_mask = RENDER_LAYER_MASK
	# The SubViewport doesn't draw the shared world's sky, and the main
	# environment sources its ambient light from that sky — without this
	# override the background renders pitch black (unlit rocks on black).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Same dark navy as the boot splash / menu palette.
	env.background_color = Color(0.0196078, 0.027451, 0.0588235)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.35)
	env.ambient_light_energy = 0.5
	var world_env := _game_camera.get_world_3d().environment
	if world_env:
		env.ambient_light_color = world_env.ambient_light_color
		env.ambient_light_energy = world_env.ambient_light_energy
	_background_camera.environment = env
	_viewport.add_child(_background_camera)

	var material := ShaderMaterial.new()
	material.shader = COMPOSITE_SHADER
	material.set_shader_parameter("background_texture", _viewport.get_texture())
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		material.set_shader_parameter("far_clip_z", 0.999999)

	var quad := MeshInstance3D.new()
	quad.name = "BackgroundComposite"
	var mesh := QuadMesh.new()
	mesh.material = material
	quad.mesh = mesh
	# The vertex shader pins the quad to the whole screen at the far plane;
	# an effectively infinite AABB keeps frustum culling from dropping it.
	quad.custom_aabb = AABB(Vector3(-1e9, -1e9, -1e9), Vector3(2e9, 2e9, 2e9))
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)

	_sync_with_game_camera()


func _process(_delta: float) -> void:
	if _background_camera:
		_sync_with_game_camera()


func _sync_with_game_camera() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if _viewport.size != size and size.x > 0 and size.y > 0:
		_viewport.size = size
	_background_camera.global_transform = _game_camera.global_transform
	_background_camera.projection = _game_camera.projection
	_background_camera.keep_aspect = _game_camera.keep_aspect
	_background_camera.fov = _game_camera.fov
	_background_camera.near = _game_camera.near
	_background_camera.far = _game_camera.far
