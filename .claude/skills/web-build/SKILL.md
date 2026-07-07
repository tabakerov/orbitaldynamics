---
name: web-build
description: Собрать веб-билд игры для itch.io — headless-экспорт Godot и упаковка zip. Использовать, когда просят сделать/пересобрать веб-билд, билд для itch или web export.
---

# Веб-билд для itch.io

Экспортирует Godot-проект (`godot/`) пресетом "Web" и упаковывает результат в
`godot/orbitaldynamics-itch-web.zip`, готовый к загрузке на itch.io.

## Шаги

1. **Экспорт** (headless, ~30 сек):

   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless \
     --path /Users/az/VC/orbitaldynamics/godot \
     --export-release "Web" out/index.html
   ```

   Успех — строка `[ DONE ] savepack` в конце вывода. Пресет "Web" лежит в
   `godot/export_presets.cfg`, шаблоны версии Godot должны быть установлены
   (`~/Library/Application Support/Godot/export_templates/`).

2. **Zip** — `index.html` обязан быть в корне архива (требование itch),
   поэтому зипуем изнутри `out/`:

   ```bash
   cd /Users/az/VC/orbitaldynamics/godot
   rm -f orbitaldynamics-itch-web.zip
   cd out && zip -q ../orbitaldynamics-itch-web.zip \
     index.html index.js index.wasm index.pck index.png \
     index.icon.png index.apple-touch-icon.png \
     index.audio.worklet.js index.audio.position.worklet.js
   ```

3. **Проверка архива**: `unzip -l` — 9 файлов, свежие даты, `index.html` без
   префикса каталога.

## Локальная проверка в браузере

Сервер описан в `.claude/launch.json` (имя `web-build`, порт 8060, отдаёт
`godot/out`): запускать через preview-инструменты, страница
http://localhost:8060. После пересборки нужен жёсткий рефреш (Cmd+Shift+R) —
браузер кеширует старый wasm/pck. Визуальную проверку делает пользователь;
самому — только консоль/логи.

## Грабли

- **Новый `class_name` не виден** при headless-запусках (ошибка «Identifier
  not declared») — сначала прогнать `--import`:
  `Godot --headless --path godot --import`.
- **Веб работает на Compatibility (WebGL)**, а десктоп — на Forward+. Шейдерные
  расхождения проверять нативно: `--rendering-method gl_compatibility`.
  С 4.6 compatibility тоже reversed-Z, но в GL-конвенции (дальняя плоскость
  NDC z = −1, а не +1, и не 0 как в Forward+).
- **Настройки itch**: у файла отметить "This file will be played in the
  browser". SharedArrayBuffer/cross-origin isolation не нужны — в пресете
  `thread_support=false`.
