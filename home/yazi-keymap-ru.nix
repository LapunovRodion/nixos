# Зеркала ШТАТНЫХ биндингов yazi в кириллице — сгенерированный файл.
#
# yazi ловит одиночные клавиши, поэтому раскладка ломает ему всё управление,
# а xkb тут бессилен (см. home/keyboard-ru.nix). Собственные бинды из
# home/home.nix зеркалятся там же на месте, а здесь лежит то, что заводит
# сам yazi, — руками такой список не держат.
#
# desc намеренно нет: без него запись не попадает в справку по `~`, и та
# не раздувается вдвое. Клавиши, которых нет в таблице раскладки (<C-c>,
# <Esc>, стрелки), пропущены — им зеркало не нужно.
#
# Режимы input и cmp НЕ зеркалятся сознательно: это ввод текста, там
# кириллица должна оставаться кириллицей.
#
# Как обновить (после заметного апгрейда yazi):
#   curl -sfL https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/keymap-default.toml
# и прогнать через генератор из истории коммита, добавившего этот файл.

{
  mgr = [
    { on = "й"; run = "quit"; }
    { on = "Й"; run = "quit --no-cwd-file"; }
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
    { on = [ "п" "п" ]; run = "arrow top"; }
    { on = "П"; run = "arrow bot"; }
    { on = "р"; run = "leave"; }
    { on = "д"; run = "enter"; }
    { on = "Р"; run = "back"; }
    { on = "Д"; run = "forward"; }
    { on = "м"; run = "visual_mode"; }
    { on = "М"; run = "visual_mode --unset"; }
    { on = "Л"; run = "seek -5"; }
    { on = "О"; run = "seek 5"; }
    { on = "щ"; run = "open"; }
    { on = "Щ"; run = "open --interactive"; }
    { on = "н"; run = "yank"; }
    { on = "ч"; run = "yank --cut"; }
    { on = "з"; run = "paste"; }
    { on = "З"; run = "paste --force"; }
    { on = "Н"; run = "unyank"; }
    { on = "Ч"; run = "unyank"; }
    { on = "в"; run = "remove"; }
    { on = "В"; run = "remove --permanently"; }
    { on = "ф"; run = "create"; }
    { on = "Ф"; run = "bulk_create"; }
    { on = "к"; run = "rename --cursor=before_ext"; }
    { on = "ж"; run = "shell --interactive"; }
    { on = "Ж"; run = "shell --block --interactive"; }
    { on = "ю"; run = "hidden toggle"; }
    { on = "ы"; run = "search --via=fd"; }
    { on = "Ы"; run = "search --via=rg"; }
    { on = "я"; run = "plugin fzf"; }
    { on = "Я"; run = "plugin zoxide"; }
    { on = [ "ь" "ы" ]; run = "linemode size"; }
    { on = [ "ь" "з" ]; run = "linemode permissions"; }
    { on = [ "ь" "и" ]; run = "linemode btime"; }
    { on = [ "ь" "ь" ]; run = "linemode mtime"; }
    { on = [ "ь" "щ" ]; run = "linemode owner"; }
    { on = [ "ь" "т" ]; run = "linemode none"; }
    { on = [ "с" "с" ]; run = "copy path"; }
    { on = [ "с" "С" ]; run = "copy url"; }
    { on = [ "с" "в" ]; run = "copy dirpath"; }
    { on = [ "с" "В" ]; run = "copy dirurl"; }
    { on = [ "с" "а" ]; run = "copy filename"; }
    { on = [ "с" "т" ]; run = "copy name_without_ext"; }
    { on = "а"; run = "filter --smart"; }
    { on = "т"; run = "find_arrow"; }
    { on = "Т"; run = "find_arrow --previous"; }
    { on = [ "б" "ь" ]; run = [ "sort mtime --reverse=no" "linemode mtime" ]; }
    { on = [ "б" "Ь" ]; run = [ "sort mtime --reverse=yes" "linemode mtime" ]; }
    { on = [ "б" "и" ]; run = [ "sort btime --reverse=no" "linemode btime" ]; }
    { on = [ "б" "И" ]; run = [ "sort btime --reverse=yes" "linemode btime" ]; }
    { on = [ "б" "у" ]; run = "sort extension --reverse=no"; }
    { on = [ "б" "У" ]; run = "sort extension --reverse=yes"; }
    { on = [ "б" "ф" ]; run = "sort alphabetical --reverse=no"; }
    { on = [ "б" "Ф" ]; run = "sort alphabetical --reverse=yes"; }
    { on = [ "б" "т" ]; run = "sort natural --reverse=no"; }
    { on = [ "б" "Т" ]; run = "sort natural --reverse=yes"; }
    { on = [ "б" "ы" ]; run = [ "sort size --reverse=no" "linemode size" ]; }
    { on = [ "б" "Ы" ]; run = [ "sort size --reverse=yes" "linemode size" ]; }
    { on = [ "б" "к" ]; run = "sort random --reverse=no"; }
    { on = [ "п" "р" ]; run = "cd ~"; }
    { on = [ "п" "с" ]; run = "cd ~/.config"; }
    { on = [ "п" "в" ]; run = "cd ~/Downloads"; }
    { on = [ "п" "е" ]; run = "plugin trash"; }
    { on = [ "п" "а" ]; run = "follow"; }
    { on = [ "е" "е" ]; run = "tab_create --current"; }
    { on = [ "е" "к" ]; run = "tab_rename --interactive"; }
    { on = "х"; run = "tab_switch -1 --relative"; }
    { on = "ъ"; run = "tab_switch 1 --relative"; }
    { on = "Х"; run = "tab_swap -1"; }
    { on = "Ъ"; run = "tab_swap 1"; }
    { on = "ц"; run = "tasks:show"; }
    { on = "Ё"; run = "help"; }
  ];

  tasks = [
    { on = "ц"; run = "close"; }
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
    { on = "ч"; run = "cancel"; }
    { on = "Ё"; run = "help"; }
  ];

  spot = [
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
    { on = "р"; run = "swipe prev"; }
    { on = "д"; run = "swipe next"; }
    { on = [ "с" "с" ]; run = "copy cell"; }
    { on = "Ё"; run = "help"; }
  ];

  pick = [
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
    { on = "Ё"; run = "help"; }
  ];

  confirm = [
    { on = "т"; run = "close"; }
    { on = "н"; run = "close --submit"; }
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
    { on = "Ё"; run = "help"; }
  ];

  help = [
    { on = "л"; run = "arrow prev"; }
    { on = "о"; run = "arrow next"; }
  ];

}
