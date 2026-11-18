#version 460 core
// v1.7.3 底栏液态玻璃：单次 ImageFilter.shader 完成「模糊 + 边缘折射 +
// 色散」。模糊放在 shader 内做（不叠 ImageFilter.blur），这样滤镜输入
// 就是药丸自身边界，几何坐标不会被模糊外扩的 padding 带偏。
// 引擎约定：第一个 uniform 为 vec2（输入尺寸，自动注入），第一个
// sampler2D 自动绑定输入；其后的 float 由 Dart 侧 setFloat 赋值（从 2 开始）。
#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;      // 输入纹理尺寸（px）
uniform float u_strength; // 边缘向心折射位移（px）
uniform float u_blur;     // 模糊采样半径（px）
uniform float u_chroma;   // 边缘色散位移（px）
uniform float u_edge;     // 折射生效的边缘带宽（px）

uniform sampler2D u_texture;

out vec4 frag_color;

vec3 tap(vec2 uv) {
  return texture(u_texture, clamp(uv, 0.0, 1.0)).rgb;
}

// 9 抽样高斯近似：中心 4 权重，轴向 2，对角 1。
vec3 blur9(vec2 uv, vec2 stepUv) {
  vec3 c = tap(uv) * 4.0;
  c += tap(uv + vec2(stepUv.x, 0.0)) * 2.0;
  c += tap(uv - vec2(stepUv.x, 0.0)) * 2.0;
  c += tap(uv + vec2(0.0, stepUv.y)) * 2.0;
  c += tap(uv - vec2(0.0, stepUv.y)) * 2.0;
  c += tap(uv + stepUv);
  c += tap(uv - stepUv);
  c += tap(uv + vec2(stepUv.x, -stepUv.y));
  c += tap(uv + vec2(-stepUv.x, stepUv.y));
  return c / 16.0;
}

void main() {
  vec2 size = u_size;
  vec2 frag = FlutterFragCoord().xy;

  // 以药丸中心为原点的像素坐标（左右两端半圆，SDF 按胶囊算）。
  vec2 pc = frag - size * 0.5;
  float halfW = size.x * 0.5;
  float radius = size.y * 0.5;

  // 胶囊 SDF：内部为负，边缘为 0。
  vec2 q = abs(pc) - vec2(halfW - radius, 0.0);
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;

  // t：贴边为 1，向里 u_edge 像素内衰减到 0，平方后过渡更柔。
  float t = clamp(1.0 + d / max(u_edge, 1.0), 0.0, 1.0);
  t *= t;

  // 采样点向中心收，形成凸透镜压缩；边缘最强。
  vec2 dir = pc / vec2(max(halfW, 1.0), max(radius, 1.0));
  vec2 uv = (pc - dir * t * u_strength) / size + 0.5;
  vec2 ca = dir * t * u_chroma / size;

  // Impeller 的 GLES 后端 y 轴翻转。
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  ca.y = -ca.y;
#endif

  vec3 col = blur9(uv, vec2(u_blur) / size);

  // 边缘轻微色散：R/B 反向偏移，只混入一半，避免彩边过重。
  float r = tap(uv + ca).r;
  float b = tap(uv - ca).b;
  col.r = mix(col.r, r, 0.5);
  col.b = mix(col.b, b, 0.5);

  // 边缘收光：折射带内侧略提亮。
  col += t * 0.05;

  frag_color = vec4(col, 1.0);
}
