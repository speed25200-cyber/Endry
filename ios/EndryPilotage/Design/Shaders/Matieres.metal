#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Bruit pseudo-aléatoire stable par pixel.
static float bruit(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// Carte héros espresso : grain subtil + reflet lumineux qui balaie lentement en diagonale.
// `rect` = boundingRect (x, y, largeur, hauteur) ; `temps` en secondes ; `intensite` 0…1 (0 = « Réduire les animations »).
[[ stitchable ]] half4 refletEspresso(float2 position, half4 couleur, float4 rect, float temps, float intensite) {
    float2 uv = (position - rect.xy) / max(rect.zw, float2(1.0));

    // Reflet : une bande douce qui traverse la carte toutes les ~14 s.
    float bande = uv.x * 0.78 + uv.y * 0.42;
    float centre = fract(temps / 14.0) * 2.4 - 0.7;
    float distance = abs(bande - centre);
    float reflet = smoothstep(0.26, 0.0, distance) * 0.085 * intensite;
    // Lueur fixe en haut à gauche (source de lumière chaude).
    float lueur = smoothstep(0.9, 0.0, length(uv - float2(0.18, 0.0))) * 0.05;

    // Grain de papier, légèrement plus marqué dans les ombres.
    float g = (bruit(floor(position)) - 0.5) * 0.05;

    half3 teinteReflet = half3(1.0, 0.86, 0.62);
    half3 rgb = couleur.rgb + teinteReflet * half(reflet + lueur) * couleur.a + half3(half(g)) * couleur.a;
    return half4(clamp(rgb, half3(0.0), half3(couleur.a)), couleur.a);
}

// Grain seul, pour les surfaces sombres secondaires (fond de connexion).
[[ stitchable ]] half4 grain(float2 position, half4 couleur, float force) {
    float g = (bruit(floor(position)) - 0.5) * force;
    return half4(clamp(couleur.rgb + half3(half(g)) * couleur.a, half3(0.0), half3(couleur.a)), couleur.a);
}
