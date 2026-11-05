#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// The intro sky in one pass: the canvas colour and three soft nebulas,
// each a radial fade from [alpha] at the centre to 0 at [radius], laid
// over the previous one in order. Matches the gradient circles it
// replaces, which took three full-screen passes on the TV's GPU.
uniform vec4 uNebula0; // centre x, centre y, radius, alpha
uniform vec4 uNebula1;
uniform vec4 uNebula2;
uniform vec3 uColor0;
uniform vec3 uColor1;
uniform vec3 uColor2;
uniform vec3 uBase;

out vec4 fragColor;

vec3 nebula(vec3 under, vec2 p, vec4 n, vec3 color) {
  float a = n.w * (1.0 - clamp(distance(p, n.xy) / n.z, 0.0, 1.0));
  return mix(under, color, a);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 color = uBase;
  color = nebula(color, p, uNebula0, uColor0);
  color = nebula(color, p, uNebula1, uColor1);
  color = nebula(color, p, uNebula2, uColor2);
  // Dithered like the gradients: no banding in the dark sky.
  float noise = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
  color += (noise - 0.5) / 255.0;
  fragColor = vec4(color, 1.0);
}
