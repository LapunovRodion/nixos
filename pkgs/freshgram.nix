{ lib, appimageTools, fetchurl }:

# freshGram — форк Telegram Desktop (materialgram-вид + фичи AyuGram).
# В nixpkgs его нет. Бинарник собран как официальный tdesktop: почти всё
# (X11, Wayland, GL, звук) грузит через dlopen, поэтому берём AppImage —
# FHS-окружение appimageTools подкладывает эти библиотеки само.
let
  pname = "freshgram";
  version = "7.5.0";

  src = fetchurl {
    url = "https://github.com/Snowy-Fluffy/freshGram/releases/download/v${version}/freshGram.AppImage";
    hash = "sha256-TlkSJzckzKOzwEZkciPevXO/ee3Ps1Tuaw6joi+lVOg=";
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    mv $out/bin/${pname} $out/bin/freshGram
    install -Dm444 ${contents}/io.github.snowyfluffy.freshgram.desktop -t $out/share/applications
    cp -r ${contents}/usr/share/icons $out/share/
    # DBusActivatable требует dbus-сервис с путём /usr/bin — запускаем через Exec.
    sed -i '/^DBusActivatable=/d' $out/share/applications/*.desktop
  '';

  meta = {
    description = "Telegram Desktop fork: materialgram look + AyuGram features";
    homepage = "https://github.com/Snowy-Fluffy/freshGram";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "freshGram";
  };
}
