{ lib
, buildPythonPackage
, fetchPypi
, setuptools
, textual
}:

# ricekit — библиотека виджетов/тем для Textual, от того же автора, что tuistore.
# Нужна только как зависимость tuistore, в nixpkgs её нет.
buildPythonPackage rec {
  pname = "ricekit";
  version = "0.3.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-QZ07pHAIPMaL2t2J5tgTjH9CBnx0tCqskDhClmfk8eY=";
  };

  build-system = [ setuptools ];
  dependencies = [ textual ];

  # Тестов в sdist нет; проверяем хотя бы то, что модуль импортируется.
  pythonImportsCheck = [ "ricekit" ];

  meta = {
    description = "TUI suite for Textual: themes, widgets, modals, icons";
    homepage = "https://github.com/Gheat1/ricekit";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
