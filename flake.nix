{
  description = "artur NixOS: niri + noctalia + hysteria + claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Отдельный, всегда свежий срез nixpkgs ТОЛЬКО под claude-code.
    # Через оверлей (см. configuration.nix) им подменяется pkgs.claude-code,
    # чтобы обновлять CLI независимо от основного nixpkgs — не утаскивая весь
    # unstable (и его случайные поломки, напр. сборку ollama-cuda).
    # Обновление CLI: nix flake update nixpkgs-cc  →  rebuild.
    nixpkgs-cc.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia v5 — без follows на nixpkgs, иначе ломается бинарный кэш cachix.
    noctalia.url = "github:noctalia-dev/noctalia/cachix";

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

    # claude-desktop (Linux) — нет в nixpkgs, community-flake.
    # Пиним его nixpkgs на СТАБИЛЬНЫЙ 25.05: в свежем unstable убрали весь набор
    # nodePackages (flake на него завязан, нужен asar). follows не спасал —
    # flake сам просит nixos-unstable и дедуплицировался с корневым. Явный url
    # на 25.05 создаёт отдельный узел, где nodePackages ещё есть.
    claude-desktop = {
      url = "github:k3d3/claude-desktop-linux-flake";
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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

    # hermes-agent — харнесс локального ИИ (управление системой) + память QMD.
    # Официальный flake на uv2nix + готовый nixosModules.default.
    # БЕЗ follows на nixpkgs: у него свой пиннинг под uv2nix, перебивать ломает сборку.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = { self, nixpkgs, home-manager, noctalia, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        noctalia.nixosModules.default
        inputs.hermes-agent.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
          home-manager.users.artur = import ./home.nix;
        }
      ];
    };
  };
}
