# Сокращения, накиданные на ходу командой mkabbr.
#
# Файл ПИШЕТСЯ РУКАМИ И СКРИПТОМ — это единственное место в конфиге, где так
# можно. В ~/.config/fish/conf.d он попадает не копией в /nix/store, а
# симлинком прямо сюда (mkOutOfStoreSymlink в home/home.nix), поэтому правка
# действует в следующем же терминале, без nixos-rebuild.
#
# Лежит в git, значит уезжает на вторую машину вместе с остальным конфигом.
#
# Постоянные, обдуманные сокращения по-прежнему живут в programs.fish.shellAbbrs
# в home/home.nix. При совпадении имён выигрывает ИМЕННО ОНО: fish читает
# conf.d раньше config.fish, и определение из config.fish перекрывает здешнее.
#
# Добавить:  mkabbr nrs sudo nixos-rebuild switch --flake ~/nixos#desktop
# Убрать:    rmabbr nrs
abbr -a -- nrs 'sudo nixos-rebuild switch --flake /home/artur/nixos#desktop'
abbr -a -- ccf 'claude nixos/'
