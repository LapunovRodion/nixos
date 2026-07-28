# Lyth Mono — кастомная сборка поверх Iosevka.
# https://github.com/why-trv/LythMono
#
# В nixpkgs его нет, поэтому берём готовый релизный zip: сборка из
# исходников потянула бы полный тулчейн Iosevka (node + ttfautohint,
# десятки минут на каждое обновление), а на выходе получились бы
# ровно те же ttf.
#
# variant выбирает начертание:
#   LythMonoTermNerdFont       — базовое, узкие стрелки и геометрия под терминал
#   LythMonoNerdFont           — то же, но стрелки обычной ширины (для GUI)
#   LythMono{Round,Square}...  — более круглые / прямоугольные o, c, e
# Полный список — в ассетах релиза. Меняя variant, обязательно меняй
# и hash: он считается от конкретного архива.
{ lib
, stdenvNoCC
, fetchurl
, unzip
, variant ? "LythMonoTermNerdFont"
, hash ? "sha256-KMXjZXYEFBpeEKHv0W9MeRFju2dpmPuSelRFSIRI/5c="
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "lyth-mono";
  version = "0.10.0";

  src = fetchurl {
    url = "https://github.com/why-trv/LythMono/releases/download/v${finalAttrs.version}/${variant}.zip";
    inherit hash;
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  # В архиве два каталога: TTF и TTF-Unhinted. Берём хинтованный —
  # экран ноутбука не HiDPI настолько, чтобы хинтинг стал лишним.
  installPhase = ''
    runHook preInstall
    install -Dm444 ${variant}/TTF/*.ttf -t $out/share/fonts/truetype
    runHook postInstall
  '';

  meta = {
    description = "Monospace programming font built on Iosevka (${variant})";
    homepage = "https://github.com/why-trv/LythMono";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
})
