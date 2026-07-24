{
  description = "artur NixOS: niri + noctalia + hysteria + claude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
  };

  outputs = { self, nixpkgs, home-manager, noctalia, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        noctalia.nixosModules.default
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
