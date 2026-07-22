{ inputs, pkgs, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];

  home.stateVersion = "26.05";

  programs.noctalia = {
    enable = true;
    systemd.enable = true;   # автозапуск как user-сервис
    settings = {
      theme = { mode = "dark"; source = "builtin"; builtin = "Catppuccin"; };
      # приложения из шелла — как systemd-юниты, иначе умирают при рестарте сервиса
      launch_apps_as_systemd_services = true;
    };
  };
}
