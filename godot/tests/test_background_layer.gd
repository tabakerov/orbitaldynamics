extends Node

const MainScene = preload("res://scenes/main.tscn")
const BlackHoleScene = preload("res://scenes/black_hole.tscn")
const BackgroundScatterScene = preload("res://scenes/background_scatter.tscn")


func _ready() -> void:
	await _test_main_splits_render_layers()
	await _test_lensing_and_scatter_are_background_only()
	print("All background layer tests passed!")
	get_tree().quit()


func _test_main_splits_render_layers() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame

	var layer := main.get_node("BackgroundLayer") as BackgroundLayer
	assert(layer != null, "Main scene should have a BackgroundLayer.")

	var viewport := layer.get_node_or_null("BackgroundViewport") as SubViewport
	assert(viewport != null, "BackgroundLayer should create its SubViewport.")

	var background_camera: Camera3D = null
	for child in viewport.get_children():
		if child is Camera3D:
			background_camera = child
	assert(background_camera != null, "Background viewport should have a camera.")
	assert(
		background_camera.cull_mask == BackgroundLayer.RENDER_LAYER_MASK,
		"The background camera should render only the background layer.",
	)

	var game_camera := (main.get_node("CameraRig") as CameraRig).get_camera()
	assert(
		game_camera.cull_mask & BackgroundLayer.RENDER_LAYER_MASK == 0,
		"The gameplay camera should not render the background layer.",
	)

	assert(
		layer.get_node_or_null("BackgroundComposite") != null,
		"BackgroundLayer should create the fullscreen composite quad.",
	)
	print("  PASS: main scene splits background and gameplay rendering")

	get_tree().paused = false
	main.queue_free()
	await main.tree_exited


func _test_lensing_and_scatter_are_background_only() -> void:
	var hole := BlackHoleScene.instantiate()
	hole.body_data = CelestialBodyData.new()
	add_child(hole)
	var lensing := hole.get_node("LensingMesh") as MeshInstance3D
	assert(
		lensing.layers == BackgroundLayer.RENDER_LAYER_MASK,
		"The lensing plane should live on the background layer only.",
	)

	var scatter := BackgroundScatterScene.instantiate() as BackgroundScatter
	add_child(scatter)
	await get_tree().process_frame

	var generated: Array[MultiMeshInstance3D] = []
	for child in scatter.get_children(true):
		if child is MultiMeshInstance3D:
			generated.append(child)
	assert(generated.size() > 0, "BackgroundScatter should generate instances.")
	for mmi in generated:
		assert(
			mmi.layers == BackgroundLayer.RENDER_LAYER_MASK,
			"Scatter instances should live on the background layer only.",
		)
	print("  PASS: lensing plane and scatter render on the background layer")

	hole.queue_free()
	scatter.queue_free()
	await get_tree().process_frame
