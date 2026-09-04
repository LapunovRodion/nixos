{ inputs, pkgs, ... }:

# =============================================================
# Floorp + Natsumi.
#
# Единственный браузер в системе.
#
# Natsumi — не браузер, а мод поверх Firefox-форков: свой CSS на весь
# интерфейс плюс модули на JS. Выбор Floorp — следствие мода: у апстрима
# Natsumi он помечен рекомендованным, а стоявший здесь раньше Zen — в
# списке НЕсовместимых. Какое-то время браузера было два; Zen убран
# (2026-09-04), профиль ~/.config/zen на диске остался, конфиг его больше
# не трогает.
#
# Пакет называется floorp-bin, не floorp: сборка из исходников в
# nixpkgs выброшена начиная с 12.x («has become unfeasible»), осталась
# репаковка официального бинарника.
#
# Мод ставится ПОЛНОСТЬЮ, вместе с JS-частью («Natsumi Append»). Разница
# принципиальная: без JS не работают Miniplayer, Single Toolbar, Compact
# Mode, кастомные темы, свои шорткаты и, главное, страница настроек —
# то есть настраивать мод пришлось бы правкой CSS.
#
# Обновление мода: nix flake update natsumi (или fx-autoconfig) → rebuild.
# =============================================================

let
  # Имя каталога профиля. Профиль заводит home-manager, и имя задаём мы,
  # без рандомного префикса, — путь одинаков на всех машинах.
  profile = "default";
  chrome = ".floorp/${profile}/chrome";

  # utils/ от fx-autoconfig подключается ПОФАЙЛОВО, а не каталогом:
  # chrome.manifest в этом же каталоге должен быть наш (см. ниже), а
  # симлинк на каталог целиком места под свой файл не оставляет.
  fxUtils = [
    "boot.sys.mjs"
    "fs.sys.mjs"
    # В инструкции Natsumi этот файл не упомянут, но без него модули мода
    # видны в списке скриптов и не загружаются (README, примечание к шагу 1).
    "module_loader.mjs"
    "uc_api.sys.mjs"
    "utils.sys.mjs"
  ];
in
{
  programs.floorp = {
    enable = true;

    # ---------------------------------------------------------------
    # Пакет: fx-autoconfig в каталоге УСТАНОВКИ браузера.
    #
    # Загрузчик скриптов состоит из двух половин, и одна из них кладётся
    # не в профиль, а рядом с бинарником — в NixOS это /nix/store, куда
    # инструкция «скопируйте файлы» неприменима. Чинится это не костылём,
    # а штатными ручками обёртки wrapFirefox, которой обёрнут floorp-bin:
    # она и так пишет автоконфиг, надо лишь дополнить его.
    #
    # Что обёртка делает сама (pkgs/applications/networking/browsers/
    # firefox/wrapper.nix:566-583):
    #   defaults/pref/autoconfig.js  ← general.config.filename = mozilla.cfg
    #                                  general.config.obscure_value = 0
    #   mozilla.cfg                  ← комментарий в первой строке, дальше
    #                                  extraPrefsFiles и extraPrefs
    # То есть mozilla.cfg — это ровно тот файл, который у fx-autoconfig
    # называется config.js, и первая строка (её парсер автоконфига всегда
    # пропускает) уже занята комментарием. Значит тело config.js
    # дописывается как есть, а из трёх префов config-prefs.js не хватает
    # одного — про песочницу.
    # ---------------------------------------------------------------
    package = pkgs.floorp-bin.override {
      extraAutoConfig = ''
        pref("general.config.sandbox_enabled", false);
      '';
      extraPrefs = builtins.readFile "${inputs.fx-autoconfig}/program/config.js";
    };

    profiles.${profile} = {
      id = 0;
      isDefault = true;

      # userChrome.css и userContent.css у Natsumi — загрузчики в одну
      # строку, поэтому не таскаем файлы, а пишем строку. Заодно модуль
      # сам включает toolkit.legacyUserProfileCustomizations.stylesheets,
      # без которого браузер эти файлы просто не читает.
      userChrome = ''
        @import "natsumi/natsumi.css";
      '';
      userContent = ''
        @import "natsumi/natsumi-pages.css";
      '';

      # ВНИМАНИЕ: отсюда получается user.js, а он применяется при КАЖДОМ
      # старте браузера. Всё, что здесь перечислено, руками в about:config
      # поменять НЕЛЬЗЯ — откатится на следующем запуске. Поэтому префов
      # natsumi.* тут нет: их правит страница настроек мода, и это её дело.
      settings = {
        # Без него не работает страница настроек Natsumi (README, шаг 3).
        "userChromeJS.persistent_domcontent_callback" = true;

        # Моноширинный на страницах: <pre>, <code>, любой листинг. Раздельно
        # для латиницы и кириллицы: Firefox держит настройку на каждую систему
        # письма, и на русских страницах работает x-cyrillic.
        "font.name.monospace.x-western" = "LythMonoTerm Nerd Font";
        "font.name.monospace.x-cyrillic" = "LythMonoTerm Nerd Font";

        # Стартовой страницы больше нет. Здесь стояла своя, на сервере
        # (/opt/startpage, tailscale serve на :8445): без поднятого tailscale
        # вместо «домой» и новых окон прилетала ошибка сети. Сервис на сервере
        # жив, просто браузер к нему не привязан.
        #
        # Именно about:home, а не «убрать строку»: настройки уезжают в user.js,
        # а он лишь дописывает префы поверх prefs.js. Удали строку — и в
        # профиле останется лежать прошлый адрес, потому что стирать его
        # некому. Явное значение перетирает.
        "browser.startup.homepage" = "about:home";
      };
    };
  };

  # ---------------------------------------------------------------
  # Файлы профиля, которых нет в опциях модуля.
  #
  # Всё это симлинки в /nix/store, то есть read-only. Плата за то, что
  # мод обновляется одним nix flake update, а не git pull в профиле.
  # Если понадобится править natsumi-config.css руками — переводить его
  # на config.lib.file.mkOutOfStoreSymlink, как сделано с abbrs.fish.
  # ---------------------------------------------------------------
  home.file = {
    "${chrome}/natsumi".source = "${inputs.natsumi}/natsumi";

    # Обязателен: natsumi/natsumi.css первым делом импортирует его как
    # ../natsumi-config.css, и без файла не подхватится весь остальной мод.
    "${chrome}/natsumi-config.css".source = "${inputs.natsumi}/natsumi-config.css";

    # Каталоги, на которые ссылается манифест ниже. Сами по себе не нужны,
    # но пусть строки манифеста указывают на существующее.
    "${chrome}/resources".source = "${inputs.fx-autoconfig}/profile/chrome/resources";
    "${chrome}/CSS".source = "${inputs.fx-autoconfig}/profile/chrome/CSS";

    # Манифест, который читает config.js при старте. Отличается от штатного
    # у fx-autoconfig двумя вещами: userscripts смотрит в скрипты Natsumi
    # (а не в chrome/JS), и добавлены две строки под его ресурсы и иконки.
    # Взят из README Natsumi, шаг 2 установки Natsumi Append.
    "${chrome}/utils/chrome.manifest".text = ''
      content userchromejs ./
      content userscripts ../natsumi/scripts/
      skin userstyles classic/1.0 ../CSS/
      content userchrome ../resources/
      content natsumi ../natsumi/
      content natsumi-icons ../natsumi/icons/
    '';
  }
  # Сам загрузчик — пофайлово, см. fxUtils в let выше.
  // builtins.listToAttrs (map
    (f: {
      name = "${chrome}/utils/${f}";
      value.source = "${inputs.fx-autoconfig}/profile/chrome/utils/${f}";
    })
    fxUtils);
}
