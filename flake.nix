{
  description = "artur NixOS: laptop + desktop, umbriel + noctalia + hysteria + claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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

    # archify — скилл для Claude Code: описание системы (или код) → валидированная
    # интерактивная HTML-диаграмма. Штатно ставится императивно, копией каталога
    # в ~/.claude/skills (`npx skills add tt-a1i/archify -g`); вместо этого пин
    # здесь, а симлинк кладёт home.nix.
    #
    # Не flake и не npm-пакет: runtime-зависимостей у скилла нет вовсе
    # (ajv/parse5/saxes/simple-icons — только devDependencies, для генераторов и
    # тестов), поэтому каталог прямо из store работает как есть, без node_modules.
    #
    # Обновление: nix flake update archify → rebuild.
    archify = {
      url = "github:tt-a1i/archify";
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

    # tuios из апстрима, а не из nixpkgs (там отстаёт на минорную версию,
    # а агентские фичи — Inbox, harness'ы — меняются от релиза к релизу).
    # Пин на релизный тег, а не main: на main (07a467c, 2026-09-28) апстрим забыл
    # обновить vendorHash, и сборка падает на hash mismatch go-modules.
    # Обновление: сменить тег → nix flake update tuios → rebuild.
    tuios = {
      url = "github:Gaurav-Gosain/tuios/v0.9.1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-index-database — готовая база nix-index, пересобирается апстримом
    # раз в неделю. Без неё nix-index требовал ручного `nix-index` (несколько
    # минут), и command-not-found в fish молчал. Заодно даёт comma:
    # `, cowsay hi` — запустить программу, не устанавливая.
    # Обновление базы: nix flake update nix-index-database → rebuild.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
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
          inputs.nix-index-database.nixosModules.nix-index
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            # Когда HM забирает под себя файл, который до этого лежал в ~/.config
            # обычным файлом, активация падает: «existing file is in the way».
            # С этим ключом HM сам отодвигает его в <имя>.hm-bak и идёт дальше.
            # Понадобилось при переносе конфига niri в git.
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
