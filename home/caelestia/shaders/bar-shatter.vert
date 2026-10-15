#version 440
// Бар рассыпается на клетки, они перелетают на другой край и собираются там
// в новый бар (BarShatter.qml). Сетка GridMesh вдвое гуще клеток: чётные
// квадраты — клетки, нечётные — щели нулевой ширины между ними; у каждой
// вершины своя клетка, так что в полёте клетки расходятся, а растянутые
// щели отбрасывает фрагментный шейдер.

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;

layout(location = 0) out vec2 fromUv;
layout(location = 1) out vec2 toUv;
layout(location = 2) out vec2 cell;
layout(location = 3) out float morph;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 fromRect;
    vec4 toRect;
    vec2 grid;      // клеток вдоль бара, поперёк
    float fromSide; // 0 — слева, 1 — сверху, 2 — снизу
    float toSide;
    float progress;
    vec4 background;
};

// Точка бара: s — доля вдоль, t — поперёк от края экрана; uv в его текстуре.
vec2 uvOn(float side, vec2 st) {
    if (side < 0.5)
        return vec2(st.y, st.x);
    if (side < 1.5)
        return st;
    return vec2(st.x, 1.0 - st.y);
}

vec2 place(vec4 r, float side, vec2 st) {
    return r.xy + uvOn(side, st) * r.zw;
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 idx = floor(qt_MultiTexCoord0 * grid * 2.0 + 0.5);
    vec2 c = min(floor(idx / 2.0), grid - 1.0);
    vec2 st = (c + clamp(idx - 2.0 * c, 0.0, 1.0)) / grid;
    vec2 mid = (c + 0.5) / grid;

    // Волна вдоль бара с разбросом: клетка летит свою долю общего времени.
    float h = hash(c);
    float delay = 0.4 * (0.7 * mid.x + 0.3 * h);
    float l = clamp((progress - delay) / 0.6, 0.0, 1.0);
    float e = l * l * (3.0 - 2.0 * l);
    float lift = sin(3.14159265 * e);

    // Центр клетки — по дуге со случайным выносом.
    vec2 a = place(fromRect, fromSide, mid);
    vec2 b = place(toRect, toSide, mid);
    vec2 bend = (vec2(hash(c + 7.0), hash(c + 13.0)) - 0.5) * 360.0;
    vec2 ctrl = mix(a, b, 0.5) + bend;
    vec2 centre = mix(mix(a, ctrl, e), mix(ctrl, b, e), e);

    // Форма клетки — из старой в новую (ориентации разные — клетка
    // переворачивается, как карта), в полёте кувырок и уменьшение.
    vec2 off = mix(place(fromRect, fromSide, st) - a, place(toRect, toSide, st) - b, e);
    float spin = (h - 0.5) * 6.28318531 * lift;
    off = mat2(cos(spin), sin(spin), -sin(spin), cos(spin)) * off * (1.0 - 0.45 * lift);

    fromUv = uvOn(fromSide, st);
    toUv = uvOn(toSide, st);
    cell = c;
    morph = e;
    gl_Position = qt_Matrix * vec4(centre + off, 0.0, 1.0);
}
