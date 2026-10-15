#version 440
// Пара к bar-shatter.vert: щели между клетками (номер клетки меняется
// внутри треугольника) — прочь; клетка — старый бар, к концу полёта новый,
// поверх фона бара (снимки бара фона не содержат — его рисует рамка).

layout(location = 0) in vec2 fromUv;
layout(location = 1) in vec2 toUv;
layout(location = 2) in vec2 cell;
layout(location = 3) in float morph;

layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 fromRect;
    vec4 toRect;
    vec2 grid;
    float fromSide;
    float toSide;
    float progress;
    vec4 background;
};

layout(binding = 1) uniform sampler2D fromSource;
layout(binding = 2) uniform sampler2D toSource;

void main() {
    if (any(greaterThan(fwidth(cell), vec2(0.001))))
        discard;

    vec4 content = mix(texture(fromSource, fromUv), texture(toSource, toUv), smoothstep(0.35, 0.65, morph));
    vec4 bg = vec4(background.rgb * background.a, background.a);
    fragColor = (content + bg * (1.0 - content.a)) * qt_Opacity;
}
