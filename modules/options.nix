{ lib, ... }:

# =============================================================
# Опции local.* — всё, чем машины отличаются друг от друга.
#
# Объявлены на СИСТЕМНОМ уровне, а не в home-manager, хотя читает их
# в основном home-модуль noctalia. Причина: home-manager подключён как
# модуль NixOS, поэтому каждый home-модуль получает аргумент osConfig —
# полный конфиг системы. Значит достаточно объявить опцию один раз
# здесь, а в hosts/<имя>/default.nix задать значение; в home.nix и
# noctalia.nix оно читается как osConfig.local.<опция>, без всякого
# протаскивания через extraSpecialArgs.
#
# Правило простое: если значение зависит от железа (имена выходов,
# разрешение, наличие батареи) — ему сюда, а не в общий модуль.
# =============================================================

{
  options.local = {
    flakeAttr = lib.mkOption {
      type = lib.types.str;
      description = ''
        Имя хоста во флейке: nixos-rebuild switch --flake .#<flakeAttr>.
        Нужно там, где команду ребилда надо собрать строкой — например
        в кнопке Update плагина nix-monitor.
      '';
    };

    primaryOutput = lib.mkOption {
      type = lib.types.str;
      example = "eDP-1";
      description = ''
        Выход, на котором висят виджеты рабочего стола (часы, погода,
        sysmon, орб). Имя — из `niri msg outputs`.
      '';
    };

    outputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "DP-1" "DP-2" "HDMI-A-1" ];
      description = ''
        Все выходы машины. Виджеты локскрина раскладываются по каждому:
        форма ввода пароля должна быть на том мониторе, куда смотришь.
      '';
    };

    screen = {
      width = lib.mkOption {
        type = lib.types.int;
        description = "Логическая ширина primaryOutput (пиксели ПОСЛЕ scale).";
      };
      height = lib.mkOption {
        type = lib.types.int;
        description = "Логическая высота primaryOutput (пиксели ПОСЛЕ scale).";
      };
    };

    # Масштабы разведены на две опции намеренно: на ноуте они разные
    # (уведомления крупнее OSD), одним множителем это не описывается.
    notificationScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = ''
        Множитель размера уведомлений. На hidpi-панели заводской размер
        великоват, на обычном 1080p — в самый раз.
      '';
    };

    osdScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Множитель размера OSD (громкость, яркость).";
    };

    hasBattery = lib.mkOption {
      type = lib.types.bool;
      description = "Есть ли батарея: от этого зависит виджет battery в баре.";
    };

    niriOutputs = lib.mkOption {
      type = lib.types.path;
      description = ''
        Файл с блоками output {} для niri. Кладётся в
        ~/.config/niri/outputs.kdl, оттуда его подхватывает include
        в config.kdl. Разрешения и раскладка мониторов — единственное,
        что в конфиге композитора зависит от машины.
      '';
    };

    wayvncConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Конфиг wayvnc (~/.config/wayvnc/config): address/port/enable_auth.
        null там, где VNC не нужен. Какой ВЫХОД захватывать — не сюда,
        это только CLI-флаг -o в spawn-at-startup (см. outputs.kdl),
        в конфиг-файле wayvnc такого ключа нет.
      '';
    };
  };
}
