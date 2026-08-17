{ lib
, buildPythonApplication
, fetchPypi
, hatchling
, typer
, click
, rich
, platformdirs
, readchar
, pyyaml
, packaging
, pathspec
, json5
}:

# specify-cli (GitHub Spec Kit) — бутстрап Spec-Driven Development.
# В nixpkgs его нет, пакуем из sdist на PyPI.
buildPythonApplication rec {
  pname = "specify-cli";
  version = "0.16.4";
  pyproject = true;

  src = fetchPypi {
    # Имя sdist на PyPI — с подчёркиванием, в отличие от pname пакета.
    pname = "specify_cli";
    inherit version;
    hash = "sha256-G3EYEyhp3OjZEWMibMgJAGJTvxzDuBrNm+a/y0EXheQ=";
  };

  build-system = [ hatchling ];
  dependencies = [
    typer click rich platformdirs readchar pyyaml packaging pathspec json5
  ];

  pythonImportsCheck = [ "specify_cli" ];

  meta = {
    description = "CLI to bootstrap projects for Spec-Driven Development (Spec Kit)";
    homepage = "https://github.com/github/spec-kit";
    license = lib.licenses.mit;
    mainProgram = "specify";
    platforms = lib.platforms.all;
  };
}
