{ lib
, buildPythonApplication
, fetchPypi
, setuptools
, textual
, httpx
, ricekit
}:

# tuistore — каталог-«магазин» терминальных приложений (Gheat1/tuistore).
# В nixpkgs нет, поэтому пакуем из sdist на PyPI.
#
# ВАЖНО, ради чего он тут: его one-key-install ИМПЕРАТИВЕН — дёргает cargo/npm/go
# и ставит мимо конфига. На NixOS это против декларативного подхода и в общем
# случае просто не сработает. Используем как ВИТРИНУ для поиска новых TUI,
# а найденное добавляем в configuration.nix/home.nix руками.
buildPythonApplication rec {
  pname = "tuistore";
  version = "0.4.5";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-hiI+IODamZM1IYJR/KzNb8PnYdyp4Tw+YELBRpVjYV8=";
  };

  build-system = [ setuptools ];
  dependencies = [ textual httpx ricekit ];

  pythonImportsCheck = [ "tuistore" ];

  meta = {
    description = "TUI app store: browse, search and install terminal apps";
    homepage = "https://github.com/Gheat1/tuistore";
    license = lib.licenses.gpl3Plus;
    mainProgram = "tuistore";
    platforms = lib.platforms.linux;
  };
}
