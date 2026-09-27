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

// Sphère d'or liquide de l'assistant vocal.
// `rect` = boundingRect ; `temps` en secondes ; `micro` et `voix` : niveaux 0…1 ;
// `reflexion` 0…1 (l'assistant réfléchit : la matière tourne doucement) ; `mouvement` 0…1 (0 = « Réduire les animations »).
[[ stitchable ]] half4 sphereOr(float2 position, half4 couleur, float4 rect, float temps, float micro, float voix, float reflexion, float mouvement) {
    float2 taille = rect.zw;
    float cote = max(min(taille.x, taille.y), 1.0);
    float2 p = (position - rect.xy - taille * 0.5) / (cote * 0.5);
    float r = length(p);
    float angle = atan2(p.y, p.x);
    float t = temps * mouvement;

    // Rayon vivant : respiration au repos, ondulations fines avec la voix du patron,
    // pulsation ample avec la voix de l'assistant, lente rotation pendant la réflexion.
    float respiration = 0.018 * sin(t * 1.25);
    float ondes = micro * 0.085 * (0.6 * sin(angle * 5.0 + t * 4.2) + 0.4 * sin(angle * 9.0 - t * 6.3));
    float pulsation = voix * 0.10 * (0.65 + 0.35 * sin(t * 8.5));
    float lent = 0.022 * sin(angle * 3.0 + t * 0.9) + reflexion * 0.03 * sin(angle * 2.0 - t * 2.6);
    float rayon = 0.60 + respiration + ondes + pulsation + lent;

    float dedans = 1.0 - smoothstep(rayon - 0.010, rayon + 0.006, r);
    float halo = exp(-max(r - rayon, 0.0) * 6.5) * (0.22 + 0.45 * voix + 0.30 * micro) * (1.0 - dedans);

    // Pseudo-relief : normale d'une sphère, écoulement du métal en surface.
    float2 q = p / max(rayon, 0.001);
    float z = sqrt(max(1.0 - dot(q, q), 0.0));
    float3 n = normalize(float3(q.x, q.y, z + 0.0001));
    float flux = 0.5 + 0.5 * sin(q.x * 5.5 + t * 0.7 + 1.6 * sin(q.y * 3.8 - t * (0.5 + reflexion * 0.9)));
    float3 lumiere = normalize(float3(-0.45, -0.60, 0.66));
    float diffus = max(dot(n, lumiere), 0.0);
    float3 demi = normalize(lumiere + float3(0.0, 0.0, 1.0));
    float speculaire = pow(max(dot(n, demi), 0.0), 42.0);
    float fresnel = pow(1.0 - z, 2.4);

    float3 orOmbre = float3(0.30, 0.21, 0.08);
    float3 orSignature = float3(0.79, 0.65, 0.36);
    float3 orLumiere = float3(0.91, 0.83, 0.64);
    float3 c = mix(orOmbre, orSignature, clamp(diffus * 0.85 + flux * 0.2, 0.0, 1.0));
    c = mix(c, orLumiere, fresnel * 0.55);
    c += speculaire * float3(1.0, 0.95, 0.86) * 0.85;
    c *= 0.86 + 0.22 * voix;

    float3 rgb = c * dedans + orSignature * halo;
    float a = clamp(dedans + halo, 0.0, 1.0);
    return half4(half3(rgb), half(a)) * couleur.a;
}
