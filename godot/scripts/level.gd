class_name Level
extends Node3D

signal level_completed
signal ship_crashed(crash_position: Vector3)
## Корабль остался без топлива и перестал приближаться к цели — лететь дальше
## уже не на чем. HUD показывает по этому сигналу выход: рестарт или меню.
signal stranded_changed(stranded: bool)

## Сколько корабль должен не приближаться к цели, чтобы полёт считался
## безнадёжным. Достаточно долго, чтобы не срабатывать на инерционном манёвре.
const STRANDED_NO_PROGRESS_SECONDS: float = 3.0
## Приближение меньше этого — не прогресс, а дрожание чисел.
const STRANDED_PROGRESS_EPSILON: float = 0.05

@export_group("Intro")
## Показываются по очереди: каждое сообщение ждёт "Продолжить" (или таймаут).
@export_multiline var intro_messages: Array[String] = []
@export_range(0.0, 60.0, 0.1, "or_greater") var intro_timeout_seconds: float = 0.0
@export var intro_show_continue_button: bool = true
@export var intro_continue_button_text: String = "Продолжить"

@export_group("Debug")
@export var debug_visuals_enabled: bool = false

var _debug_visualizer: DebugFlightVisualizer
var _stranded: bool = false
var _stranded_no_progress_seconds: float = 0.0
var _closest_target_distance: float = INF


func _ready() -> void:
	_init_celestial_sim()
	_connect_ship()
	_connect_targets()
	_setup_debug_visualizer()


func _process(delta: float) -> void:
	var stranded := _is_ship_stranded(delta)
	if stranded == _stranded:
		return
	_stranded = stranded
	stranded_changed.emit(stranded)


## Безнадёжен полёт или ещё нет. Два условия: топлива взять негде и корабль за
## последние STRANDED_NO_PROGRESS_SECONDS ни разу не подошёл к цели ближе, чем
## подходил раньше. Пустой бак сам по себе ничего не значит — корабль может
## как раз лететь к цели по инерции, и мешать ему подсказкой не надо.
func _is_ship_stranded(delta: float) -> bool:
	var ship := get_ship()
	var target := get_target()
	if not ship or not is_instance_valid(ship) or ship.is_crashed():
		return false
	if not target or not is_instance_valid(target):
		return false

	if _has_fuel_within_reach(ship):
		# Отсчёт идёт ровно с того момента, как лететь стало не на чем.
		_stranded_no_progress_seconds = 0.0
		_closest_target_distance = INF
		return false

	var distance := ship.global_position.distance_to(target.global_position)
	if distance < _closest_target_distance - STRANDED_PROGRESS_EPSILON:
		_closest_target_distance = distance
		_stranded_no_progress_seconds = 0.0
		return false

	_closest_target_distance = minf(_closest_target_distance, distance)
	_stranded_no_progress_seconds += delta
	return _stranded_no_progress_seconds >= STRANDED_NO_PROGRESS_SECONDS


## Топливо в баках корабля либо пикап, до которого он ещё может долететь.
func _has_fuel_within_reach(ship: Ship) -> bool:
	if Cheats.enabled:
		return true
	if ship.get_reachable_fuel() > Ship.FUEL_EPSILON:
		return true
	return not get_fuel_pickups().is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F3:
		toggle_debug_visuals()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F4:
		Cheats.toggle()
		get_viewport().set_input_as_handled()


func toggle_debug_visuals() -> void:
	debug_visuals_enabled = not debug_visuals_enabled
	if _debug_visualizer:
		_debug_visualizer.enabled = debug_visuals_enabled


func _init_celestial_sim() -> void:
	var bodies := get_celestial_bodies()

	var data: Array[CelestialBodyData] = []
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var stationary: Array[bool] = []

	for i in bodies.size():
		var body := bodies[i]
		data.append(body.body_data)
		positions.append(body.global_position)
		velocities.append(body.initial_velocity)
		stationary.append(body.stationary)
		body.sim_index = i

	CelestialSim.initialize(data, positions, velocities, stationary)


func _connect_ship() -> void:
	var ship := get_ship()
	if ship:
		ship.crashed.connect(_on_ship_crashed)


func _connect_targets() -> void:
	for child in get_children():
		if child is Target:
			child.target_reached.connect(func() -> void: level_completed.emit())


## Непустые интро-сообщения без краевых пробелов, в порядке показа.
func get_intro_messages() -> PackedStringArray:
	var result := PackedStringArray()
	for message in intro_messages:
		var text := message.strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func get_ship() -> Ship:
	for child in get_children():
		if child is Ship:
			return child
	return null


func get_target() -> Target:
	for child in get_children():
		if child is Target:
			return child
	return null


func get_celestial_bodies() -> Array[CelestialBody]:
	var result: Array[CelestialBody] = []
	for child in get_children():
		if child is CelestialBody:
			result.append(child)
	return result


func get_stations() -> Array[Station]:
	var result: Array[Station] = []
	for child in get_children():
		if child is Station:
			result.append(child)
	return result


func get_fuel_pickups() -> Array[FuelPickup]:
	var result: Array[FuelPickup] = []
	_collect_descendants(self, func(node: Node) -> bool: return node is FuelPickup, result)
	return result


## All FloatingObjects in the level, including ones nested under spawners.
func get_floating_objects() -> Array[FloatingObject]:
	var result: Array[FloatingObject] = []
	_collect_descendants(self, func(node: Node) -> bool: return node is FloatingObject, result)
	return result


func get_spawners() -> Array[ObjectSpawner]:
	var result: Array[ObjectSpawner] = []
	_collect_descendants(self, func(node: Node) -> bool: return node is ObjectSpawner, result)
	return result


func get_score_tracker() -> ScoreTracker:
	for child in get_children():
		if child is ScoreTracker:
			return child
	return null


func _collect_descendants(node: Node, predicate: Callable, result: Array) -> void:
	for child in node.get_children():
		if predicate.call(child):
			result.append(child)
		_collect_descendants(child, predicate, result)


func _setup_debug_visualizer() -> void:
	var ship := get_ship()
	if not ship:
		return
	_debug_visualizer = DebugFlightVisualizer.new()
	_debug_visualizer.name = "DebugFlightVisualizer"
	_debug_visualizer.ship = ship
	_debug_visualizer.celestial_bodies = get_celestial_bodies()
	_debug_visualizer.enabled = debug_visuals_enabled
	add_child(_debug_visualizer)


func spawn_crash_explosion(crash_position: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "CrashExplosion"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.one_shot = true
	particles.amount = 180
	particles.lifetime = 1.25
	particles.explosiveness = 0.95
	particles.randomness = 0.35
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
	particles.process_material = build_crash_particle_material()
	particles.draw_pass_1 = build_crash_particle_mesh()

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = 4.0
	light.omni_range = 10.0
	light.omni_attenuation = 1.4
	particles.add_child(light)

	add_child(particles)
	particles.global_position = crash_position
	particles.restart()
	particles.emitting = true
	_free_crash_explosion(particles)


func _on_ship_crashed(crash_position: Vector3) -> void:
	ship_crashed.emit(crash_position)


# Static and public: EffectWarmup replays the effect at boot to pre-compile
# its shaders.
static func build_crash_particle_material() -> ParticleProcessMaterial:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.55, 1.0),
		Color(1.0, 0.35, 0.08, 0.95),
		Color(0.45, 0.08, 0.03, 0.55),
		Color(0.08, 0.07, 0.07, 0.0),
	])

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.35
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 14.0
	material.gravity = Vector3.ZERO
	material.damping_min = 2.0
	material.damping_max = 5.0
	material.scale_min = 0.2
	material.scale_max = 1.2
	material.color_ramp = ramp
	return material


static func build_crash_particle_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.42, 0.42)
	return mesh


func _free_crash_explosion(particles: GPUParticles3D) -> void:
	await get_tree().create_timer(particles.lifetime + 0.5, true).timeout
	if is_instance_valid(particles):
		particles.queue_free()
