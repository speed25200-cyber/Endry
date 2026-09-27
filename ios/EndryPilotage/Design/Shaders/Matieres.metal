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

// MARK: - Assistant vocal

static float hachage(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Bruit de valeur lissé.
static float bruitDoux(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hachage(i);
    float b = hachage(i + float2(1.0, 0.0));
    float c = hachage(i + float2(0.0, 1.0));
    float d = hachage(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Bruit fractal, 4 octaves tournées (pas d'alignement visible).
static float fractal(float2 p) {
    float v = 0.0;
    float a = 0.5;
    const float2x2 rotation = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 4; i++) {
        v += a * bruitDoux(p);
        p = rotation * p * 2.02 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// Sphère de verre fumé où coule de l'or liquide.
// `horloge` : secondes (respiration, ondes) ; `flux` : phase d'écoulement accumulée côté Swift ;
// `micro`, `voix`, `reflexion` : 0…1 lissés ; `mouvement` : 1, ou 0.3 si « Réduire les animations ».
[[ stitchable ]] half4 orbeEndry(float2 position, half4 couleur, float4 rect, float horloge, float flux, float micro, float voix, float reflexion, float mouvement) {
    float2 taille = rect.zw;
    float cote = max(min(taille.x, taille.y), 1.0);
    float2 p = (position - rect.xy - taille * 0.5) / (cote * 0.5);
    float r = length(p);
    float angle = atan2(p.y, p.x);

    // Silhouette toujours parfaitement ronde : seule l'échelle respire.
    float R = 0.58 * (1.0 + 0.012 * sin(horloge * 1.1) * mouvement + 0.06 * voix + 0.03 * micro);
    float px = 1.2 / (cote * 0.5);
    float dedans = 1.0 - smoothstep(R - px, R + px, r);

    float3 profond = float3(0.055, 0.038, 0.022);
    float3 bronze = float3(0.62, 0.45, 0.16);
    float3 orClair = float3(0.98, 0.86, 0.64);
    float3 blancChaud = float3(1.0, 0.96, 0.89);

    // Halo qui suit la voix, anneau qui tourne pendant la réflexion.
    float ecart = max(r - R, 0.0);
    float energie = 0.14 + 0.55 * voix + 0.40 * micro + 0.16 * reflexion;
    float halo = exp(-ecart * 7.5) * energie;
    float bande = (r - R * 1.15) / 0.010;
    float anneau = exp(-bande * bande) * reflexion * (0.25 + 0.75 * pow(0.5 + 0.5 * sin(angle - horloge * 2.6), 4.0));
    float3 dehors = orClair * (halo * 0.85 + anneau);
    float aDehors = clamp(halo + anneau, 0.0, 1.0);

    if (dedans <= 0.0) {
        return half4(half3(dehors), half(aDehors)) * couleur.a;
    }

    // Relief : normale de la sphère ; la matière se tasse vers le bord (effet de lentille).
    float2 q = p / R;
    float z = sqrt(max(1.0 - dot(q, q), 0.0));
    float3 n = float3(q, z);
    float2 w = q / (0.42 + 0.58 * z) * 1.3;

    // Or liquide : double déformation de domaine.
    float2 d1 = float2(fractal(w + float2(0.0, flux)), fractal(w + float2(5.2, 1.3) - flux * 0.8));
    float2 d2 = float2(fractal(w + 2.6 * d1 + float2(1.7, 9.2) + flux * 0.5),
                       fractal(w + 2.6 * d1 + float2(8.3, 2.8) - flux * 0.35));
    float f = fractal(w + 2.8 * d2 + micro * 0.25 * float2(sin(horloge * 3.1), cos(horloge * 2.7)));
    // Filaments de soie dorée.
    float soie = pow(0.5 + 0.5 * sin((f * 5.5 + length(d2) * 3.5) * 3.14159), 7.0);

    float3 c = mix(profond, bronze, smoothstep(0.28, 0.64, f));
    c = mix(c, orClair, smoothstep(0.60, 0.92, f) * (0.5 + 0.5 * voix));
    c += orClair * soie * (0.10 + 0.30 * voix + 0.12 * micro + 0.10 * reflexion);

    // Verre fumé : absorption vers le bord, rebord lumineux (Fresnel), deux reflets.
    c *= mix(0.40, 1.0, pow(z, 0.55));
    float3 lumiere = normalize(float3(-0.5, -0.66, 0.56));
    float3 demi = normalize(lumiere + float3(0.0, 0.0, 1.0));
    float nh = max(dot(n, demi), 0.0);
    float speculaire = pow(nh, 140.0) * 0.9 + pow(nh, 16.0) * 0.08;
    float fresnel = pow(1.0 - z, 3.0);
    float frisson = 1.0 + micro * 0.9 * sin(angle * 7.0 - horloge * 6.0);
    c += orClair * fresnel * (0.45 + 0.4 * voix + 0.2 * micro) * frisson;
    c += blancChaud * speculaire;
    // Lumière de rebond en bas, comme sur une bille posée.
    c += bronze * smoothstep(0.25, 1.0, q.y) * pow(1.0 - z, 1.3) * 0.3;

    float3 rgb = c * dedans + dehors * (1.0 - dedans);
    float a = dedans + aDehors * (1.0 - dedans);
    return half4(half3(rgb), half(a)) * couleur.a;
}

// Lueur dorée sur le bord de l'écran (façon Siri). `intensite` 0…1, `rayon` : coins de l'écran en points.
[[ stitchable ]] half4 lueurBord(float2 position, half4 couleur, float4 rect, float horloge, float intensite, float rayon) {
    float2 moitie = rect.zw * 0.5;
    float2 p = position - rect.xy - moitie;
    float2 q = abs(p) - moitie + rayon;
    float sdf = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - rayon;
    float d = max(-sdf, 0.0);

    float largeur = 5.0 + 30.0 * intensite;
    float lueur = exp(-d / largeur) * intensite;
    float filet = exp(-d / 1.4) * intensite;

    float angle = atan2(p.y, p.x);
    float v1 = 0.5 + 0.5 * sin(angle * 2.0 + horloge * 1.3);
    float v2 = 0.5 + 0.5 * sin(angle * 3.0 - horloge * 0.9 + 1.7);
    float3 bronze = float3(0.62, 0.45, 0.16);
    float3 ambre = float3(0.86, 0.56, 0.22);
    float3 orClair = float3(0.98, 0.86, 0.64);
    float3 creme = float3(1.0, 0.95, 0.86);
    float3 teinte = mix(mix(bronze, ambre, v1), mix(orClair, creme, v2), 0.35 + 0.5 * v2);

    float a = clamp(lueur * 0.8 + filet * 0.9, 0.0, 1.0);
    return half4(half3(teinte * a), half(a)) * couleur.a;
}
