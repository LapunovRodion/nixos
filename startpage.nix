{ lib, ... }:

# =============================================================
# Стартовая страница браузера — статичный HTML, собранный из nix.
#
# Открывается по file:// (см. browser.startup.homepage в home.nix),
# поэтому внутри НЕ ДОЛЖНО быть ни одного внешнего запроса: ни шрифтов
# с CDN, ни фавиконок с сайтов. Шрифты берутся системные, иконки —
# инлайновые svg (пути из simple-icons, лицензия CC0).
#
# Интерактивного редактора тут нет сознательно: на file:// у каждого
# файла свой origin, localStorage ненадёжен вплоть до SecurityError,
# так что «добавить плитку мышкой» потребовало бы поднимать локальный
# http-сервер. Вместо этого правится список links ниже + rebuild.
# =============================================================

let
  # ---- Ссылки. Единственное место, которое надо трогать. ----
  # icon = null → на плитке будет первая буква названия в кружке.
  links = [
    { name = "GitHub";      url = "https://github.com";                    icon = "github"; }
    { name = "Почта";       url = "https://mail.google.com";               icon = "gmail"; }
    { name = "YouTube";     url = "https://youtube.com";                   icon = "youtube"; }

    # Сервер. Схемы разные не по недосмотру: то, что проброшено через
    # tailscale serve, живёт на https с настоящим сертификатом, остальное
    # отдаётся контейнерами по голому http (см. docker-compose на сервере).
    { name = "Dashboard";   url = "http://server:3001";                    icon = null; }
    { name = "Vaultwarden"; url = "https://server.taila27ec6.ts.net";      icon = "bitwarden"; }
    { name = "Actual";      url = "https://server.taila27ec6.ts.net:8443"; icon = "actualbudget"; }
    { name = "LibreChat";   url = "https://server.taila27ec6.ts.net:8444"; icon = null; }
    { name = "Navidrome";   url = "http://server:4533";                    icon = null; }
    { name = "Grimmory";    url = "http://server:6060";                    icon = null; }
    { name = "Beszel";      url = "http://server:8090";                    icon = null; }
    { name = "Twenty";      url = "http://server:3000";                    icon = "twenty"; }
  ];

  # ---- Иконки ----
  # Только контур пути; все simple-icons нарисованы в viewBox 0 0 24 24
  # и красятся currentColor. Navidrome, Beszel, LibreChat и Grimmory в
  # наборе отсутствуют — у них icon = null и буква вместо логотипа.
  iconPaths = {
    github = "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12";
    gmail = "M24 5.457v13.909c0 .904-.732 1.636-1.636 1.636h-3.819V11.73L12 16.64l-6.545-4.91v9.273H1.636A1.636 1.636 0 0 1 0 19.366V5.457c0-2.023 2.309-3.178 3.927-1.964L5.455 4.64 12 9.548l6.545-4.91 1.528-1.145C21.69 2.28 24 3.434 24 5.457z";
    youtube = "M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z";
    bitwarden = "M21.722.296A.964.964 0 0 0 21.018 0H2.982a.959.959 0 0 0-.703.296.96.96 0 0 0-.297.702v12c0 .895.174 1.783.523 2.665.349.88.783 1.66 1.3 2.345.517.68 1.132 1.346 1.848 1.993a21.807 21.807 0 0 0 1.98 1.609c.605.427 1.235.83 1.893 1.212.657.381 1.125.638 1.4.772.276.134.5.241.664.311a.916.916 0 0 0 .814 0c.168-.073.389-.177.667-.311.275-.134.743-.394 1.401-.772a25.305 25.305 0 0 0 1.894-1.212A21.891 21.891 0 0 0 18.348 20c.716-.647 1.33-1.31 1.847-1.993s.949-1.463 1.3-2.345c.35-.879.524-1.767.524-2.665V1.001a.95.95 0 0 0-.297-.705zm-2.325 12.815c0 4.344-7.397 8.087-7.397 8.087V2.57h7.397v10.54z";
    actualbudget = "m17.442 10.779.737 2.01-16.758 6.145a.253.253 0 0 1-.324-.15l-.563-1.536a.253.253 0 0 1 .15-.324zM1.13 23.309 12.036.145A.253.253 0 0 1 12.265 0h.478c.097 0 .185.055.227.142l7.036 14.455 2.206-.848c.13-.05.277.015.327.145l.587 1.526a.253.253 0 0 1-.145.327l-2.034.783 2.51 5.156a.253.253 0 0 1-.117.338l-1.47.716a.253.253 0 0 1-.339-.117l-2.59-5.322-17.37 6.682a.253.253 0 0 1-.328-.145c0-.001 0-.003-.002-.004l-.12-.33a.252.252 0 0 1 .009-.195zM12.528 4.127 4.854 20.425 18 15.369z";
    twenty = "M20.97 0H3.03A3.03 3.03 0 0 0 0 3.03v17.94A3.03 3.03 0 0 0 3.03 24h17.94A3.03 3.03 0 0 0 24 20.97V3.03A3.03 3.03 0 0 0 20.97 0ZM4.813 8.936a2.376 2.376 0 0 1 2.374-2.375h4.573c.067 0 .129.04.157.103a.172.172 0 0 1-.03.185l-1.002 1.088a.924.924 0 0 1-.678.299H7.2a.713.713 0 0 0-.713.713v1.796a.418.418 0 0 1-.418.419h-.836a.418.418 0 0 1-.419-.419V8.936zm14.224 6.128a2.376 2.376 0 0 1-2.374 2.375h-1.944a2.376 2.376 0 0 1-2.375-2.375v-3.401c0-.231.087-.454.243-.625l1.134-1.23a.172.172 0 0 1 .298.115v5.13c0 .393.32.713.713.713h1.92c.393 0 .713-.32.713-.713V8.949a.713.713 0 0 0-.713-.713h-2.233c-.255 0-.499.108-.674.295l-6.658 7.235h4c.232 0 .419.187.419.418v.837a.418.418 0 0 1-.419.418h-5.39a.886.886 0 0 1-.886-.886v-.443c0-.223.083-.436.234-.6l7.465-8.109a2.603 2.603 0 0 1 1.916-.84h2.235a2.376 2.376 0 0 1 2.375 2.375v6.128z";
  };

  renderIcon = link:
    if link.icon == null
    then ''<span class="letter">${lib.substring 0 1 link.name}</span>''
    else ''<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${iconPaths.${link.icon}}"/></svg>'';

  renderLink = link: ''
        <a class="tile" href="${link.url}">
          ${renderIcon link}
          <span class="name">${link.name}</span>
        </a>
  '';

  html = ''
    <!doctype html>
    <html lang="ru">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Старт</title>
      <style>
        /* Цвета вынесены в переменные: если когда-нибудь захочется гонять
           палитру за обоями, тут появится шаблон matugen, а разметку
           трогать не придётся. Пока значения зашиты. */
        :root {
          --bg: #161616;
          --surface: #1e1e1e;
          --surface-hover: #2a2a2a;
          --text: #e6e6e6;
          --muted: #7d7d7d;
          --accent: #78a9ff;
          --radius: 14px;
        }

        * { box-sizing: border-box; }

        body {
          margin: 0;
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 2.5rem;
          padding: 3rem 1.5rem;
          background: var(--bg);
          color: var(--text);
          font-family: "IBM Plex Sans", system-ui, sans-serif;
        }

        .clock {
          font-family: "LythMonoTerm Nerd Font", monospace;
          font-size: clamp(3rem, 12vw, 6rem);
          line-height: 1;
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.02em;
        }

        .date {
          margin-top: 0.6rem;
          text-align: center;
          color: var(--muted);
          font-size: 1rem;
        }

        .search { width: min(560px, 100%); }

        .search input {
          width: 100%;
          padding: 0.9rem 1.2rem;
          border: 1px solid transparent;
          border-radius: var(--radius);
          background: var(--surface);
          color: var(--text);
          font: inherit;
          font-size: 1.05rem;
          outline: none;
          transition: border-color 0.15s, background 0.15s;
        }

        .search input::placeholder { color: var(--muted); }

        .search input:focus {
          border-color: var(--accent);
          background: var(--surface-hover);
        }

        .tiles {
          width: min(880px, 100%);
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(110px, 1fr));
          gap: 0.75rem;
        }

        .tile {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.6rem;
          padding: 1.1rem 0.5rem;
          border-radius: var(--radius);
          background: var(--surface);
          color: var(--text);
          text-decoration: none;
          transition: background 0.15s, transform 0.15s, color 0.15s;
        }

        .tile:hover {
          background: var(--surface-hover);
          color: var(--accent);
          transform: translateY(-2px);
        }

        .icon {
          width: 26px;
          height: 26px;
          fill: currentColor;
        }

        /* Заглушка для сервисов, которых нет в simple-icons. */
        .letter {
          width: 26px;
          height: 26px;
          display: grid;
          place-items: center;
          border-radius: 50%;
          border: 1.5px solid currentColor;
          font-size: 0.85rem;
          font-weight: 600;
        }

        .name {
          font-size: 0.85rem;
          color: var(--muted);
        }

        .tile:hover .name { color: inherit; }
      </style>
    </head>
    <body>
      <header>
        <div class="clock" id="clock">--:--</div>
        <div class="date" id="date"></div>
      </header>

      <form class="search" action="https://duckduckgo.com/" method="get">
        <input type="text" name="q" placeholder="Поиск" autofocus autocomplete="off" spellcheck="false">
      </form>

      <nav class="tiles">
    ${lib.concatMapStrings renderLink links}  </nav>

      <script>
        // Шаблонные литералы тут не используются намеренно: файл собирается
        // из nix-строки, где $ + фигурная скобка означали бы интерполяцию.
        function tick() {
          var now = new Date();
          document.getElementById("clock").textContent =
            now.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
          document.getElementById("date").textContent =
            now.toLocaleDateString("ru-RU", { weekday: "long", day: "numeric", month: "long" });
        }
        tick();
        setInterval(tick, 1000);
      </script>
    </body>
    </html>
  '';
in
{
  # Путь стабильный и вне /nix/store: адрес домашней страницы в user.js
  # не должен меняться при каждом ребилде. Сам файл — read-only симлинк
  # в store, как и все остальные home.file.
  home.file.".local/share/startpage/index.html".text = html;
}
