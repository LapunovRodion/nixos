{
  description = "artur NixOS: laptop + desktop, niri + noctalia + hysteria + claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Отдельный, всегда свежий срез nixpkgs ТОЛЬКО под claude-code.
    # Через оверлей (см. configuration.nix) им подменяется pkgs.claude-code,
    # чтобы обновлять CLI независимо от основного nixpkgs — не утаскивая весь
    # unstable (и его случайные поломки).
    # Обновление CLI: nix flake update nixpkgs-cc  →  rebuild.
    nixpkgs-cc.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia v5 — без follows на nixpkgs, иначе ломается бинарный кэш cachix.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

    # Плагины noctalia. Витрина внутри шелла ставит их императивно в
    # ~/.local/state/noctalia/plugins — на новой машине это пришлось бы
    # повторять руками. Вместо этого репозитории пиннятся здесь и
    # подключаются как источники вида kind = "path" (см. home/noctalia.nix):
    # noctalia читает файлы плагина прямо из каталога источника, а /nix/store
    # каталогом быть вполне может. Раскладка репозиториев — плоская,
    # <плагин>/plugin.toml, ровно та, которую ждёт сканер.
    # Обновление плагинов: nix flake update noctalia-official-plugins (или
    # -community-) → rebuild. Кнопка Update в витрине при этом не работает —
    # она умеет только git-источники, и это осознанный размен.
    noctalia-official-plugins = {
      url = "github:noctalia-dev/official-plugins";
      flake = false;
    };
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
    };

    # agenix — секреты в git в зашифрованном виде (age поверх ssh-ключей).
    # Расшифровка на этапе активации системы, ключом хоста.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Официальные плагины yazi. Это обычный репозиторий-монорепо, не flake
    # (отсюда flake = false) — из него берутся подкаталоги *.yazi, см. home.nix.
    yazi-plugins = {
      url = "github:yazi-rs/plugins";
      flake = false;
    };

    # Сторонние плагины yazi — каждый отдельным репозиторием, main.lua в корне,
    # поэтому в plugins подставляется сам input, без подкаталога.
    #
    # ouch — превью содержимого архивов и упаковка. Требует бинарь ouch в PATH
    # (добавлен в systemPackages).
    ouch-yazi = {
      url = "github:ndtoan96/ouch.yazi";
      flake = false;
    };

    # starship — то же приглашение, что и в fish, в шапке yazi.
    # Берёт уже существующий ~/.config/starship.toml, отдельной настройки нет.
    starship-yazi = {
      url = "github:Rolv-Apneseth/starship.yazi";
      flake = false;
    };

    # nixvim — neovim, целиком описанный на nix (декларативно, в git).
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zen-browser — нет в nixpkgs, ставится своим flake.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # natsumi — мод (CSS + JS) поверх Firefox-форков: перекрашивает интерфейс
    # и добавляет свои модули. НЕ браузер сам по себе. Zen апстрим держит в
    # списке несовместимых, а Floorp у него рекомендованный — отсюда второй
    # браузер в системе (см. home/floorp.nix).
    # Обычный репозиторий, не flake (flake = false): нужны только файлы —
    # каталог natsumi/ и natsumi-config.css. Обновление: nix flake update
    # natsumi → rebuild.
    natsumi = {
      url = "github:greeeen-dev/natsumi-browser";
      flake = false;
    };

    # fx-autoconfig — загрузчик userChrome-скриптов (штатного способа грузить
    # свой JS в интерфейс Firefox не существует). Нужен ТОЛЬКО ради JS-части
    # Natsumi («Natsumi Append»): без него из мода работает один CSS, а
    # Miniplayer, Single Toolbar, Compact Mode и страница настроек — нет.
    # Часть его файлов кладётся в каталог УСТАНОВКИ браузера, поэтому пакет
    # floorp-bin приходится override-ить, см. home/floorp.nix.
    fx-autoconfig = {
      url = "github:MrOtherGuy/fx-autoconfig";
      flake = false;
    };

    # claude-desktop (Linux) — нет в nixpkgs. Официальный .deb от Anthropic
    # (не community-стаб с заглушенными нативными модулями, как был раньше
    # у k3d3/claude-desktop-linux-flake), репакованный под Nix; апстрим сам
    # бампает version+hash ежедневной GitHub Action по apt-индексу Anthropic.
    # Несёт свой nixosModules.default (программа programs.claude-desktop,
    # см. modules/common.nix) — в т.ч. системную обвязку для Cowork
    # (VM-песочница агента): OVMF, virtiofsd, vhost_vsock, группа kvm.
    claude-desktop = {
      url = "github:nmcbride/claude-desktop-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # torlink — TUI-поиск торрентов, в nixpkgs его нет. Апстрим держит пакет сам
    # (nix/package.nix в репозитории) и, что важно, умеет собирать нативный
    # WebRTC-модуль (node-datachannel) офлайн, с пиннингом libdatachannel —
    # руками это в песочнице не собрать, там postinstall лезет в сеть за cmake-js.
    # Поэтому берём готовый пакет апстрима, а не пакуем свой.
    torlink = {
      url = "github:baairon/torlink";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, noctalia, ... }@inputs:
    let
      # Один сборщик хоста на все машины. Отличия — целиком в
      # ./hosts/<имя>, включая hardware-configuration.nix и значения
      # опций local.* (объявлены в ./modules/options.nix).
      mkHost = name: nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./modules/options.nix
          ./modules/common.nix
          ./hosts/${name}
          noctalia.nixosModules.default
          inputs.agenix.nixosModules.default
          inputs.claude-desktop.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            # Когда HM забирает под себя файл, который до этого лежал в ~/.config
            # обычным файлом, активация падает: «existing file is in the way».
            # С этим ключом HM сам отодвигает его в <имя>.hm-bak и идёт дальше.
            # Понадобилось при переносе niri/config.kdl в конфиг.
            home-manager.backupFileExtension = "hm-bak";
            home-manager.users.artur = import ./home/home.nix;
          }
        ];
      };
    in
    {
      # Сборка: sudo nixos-rebuild switch --flake ~/nixos#laptop (или #desktop).
      # Имя обязательно указывать явно — атрибута под именем хоста «nixos»
      # больше нет, а имена машин теперь laptop/desktop.
      nixosConfigurations = {
        laptop = mkHost "laptop";
        desktop = mkHost "desktop";
      };
    };
}
