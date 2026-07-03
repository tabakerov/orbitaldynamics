shader_type particles;

// ParticleProcessMaterial's orbit_velocity rotates each particle continuously
// around the origin, which reads as a slow uniform wheel rather than fast
// racing embers. This custom particle shader instead spawns each particle at
// a random point on the ring with velocity tangent to the circle there, and
// relies on a short lifetime (see ring_particle_lifetime) so particles streak
// a short arc and vanish rather than needing continuous curvature.

uniform float ring_inner_radius = 4.0;
uniform float ring_outer_radius = 5.5;
uniform float speed_min = 15.0;
uniform float speed_max = 28.0;
uniform float scale_min = 0.12;
uniform float scale_max = 0.35;
uniform vec4 particle_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);

// Self-contained integer hash (no dependency on shading-language RNG builtins,
// which aren't available inside particle start()/process()) — turns
// RANDOM_SEED (varies each time a particle slot restarts) into four
// independent floats in [0, 1).
float hash_seed(uint s) {
	s = (s ^ 61u) ^ (s >> 16u);
	s *= 9u;
	s = s ^ (s >> 4u);
	s *= 0x27d4eb2du;
	s = s ^ (s >> 15u);
	return float(s) / 4294967295.0;
}

void start() {
	// RANDOM_SEED alone is the emitter's seed, identical for every particle —
	// mix in NUMBER (unique per emitted particle) or the whole ring collapses
	// into a single jet of particles sharing one angle.
	uint seed = RANDOM_SEED + NUMBER * 2654435769u;
	float a = hash_seed(seed);
	float b = hash_seed(seed ^ 0x9e3779b9u);
	float c = hash_seed(seed ^ 0x85ebca6bu);
	float d = hash_seed(seed ^ 0xc2b2ae35u);

	float angle = a * TAU;
	float radius = mix(ring_inner_radius, ring_outer_radius, b);
	vec3 tangent = vec3(-sin(angle), cos(angle), 0.0);
	float speed = mix(speed_min, speed_max, c);
	float scale = mix(scale_min, scale_max, d);

	TRANSFORM[3].xyz = vec3(cos(angle), sin(angle), 0.0) * radius;
	TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
	VELOCITY = tangent * speed;
	COLOR = particle_color;
	CUSTOM.x = 0.0;
}

void process() {
	TRANSFORM[3].xyz += VELOCITY * DELTA;
	CUSTOM.x += DELTA;
	float life_ratio = clamp(CUSTOM.x / LIFETIME, 0.0, 1.0);
	COLOR.a = particle_color.a * (1.0 - life_ratio);
}
