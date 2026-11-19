# Страница на CurseForge

Готовый текст для страницы проекта. В архив аддона этот файл не попадает.

## Как заполнить

1. **Name:** `Forever Plates+`
2. **Summary** (одна строка, видна в поиске, на самой странице её нет):
   `Fine-tune the default Forever nameplates without changing their look: click any part and adjust it.`
3. **Description:** включить режим Markdown и вставить всё из блока «Описание» ниже (английский сверху, русский под ним).
4. **Images:** загрузить файлы из `media/` с подписями из раздела «Скриншоты».
5. **File:** архив `ForeverPlates-<версия>.zip`, игра — **Forever** (Interface 16001). В поле Changelog — пункты нужной версии из `CHANGELOG.md`.

---

## Описание

<!-- копировать отсюда -->

# Forever Plates+

The default Forever nameplates are already good. They just need a few tweaks, and you shouldn't have to swap your whole UI for that.

Forever Plates+ keeps the game's own nameplates and their style. It switches on the useful game options, adds what the game doesn't show and lets you tune every part.

## Click a part, tune it

Each settings page has a sketch of the nameplate. Click the name, the cast bar or the debuffs, and only that part's settings stay below: on or off, size, opacity, colour, position. Parts that are off are drawn faded, so you always see what's on.

## What it adds

- **Your debuffs** above the enemy's name, with timers. Buffs you can purge get a blue border.
- **Debuffs you can dispel** on allies, as small icons.
- **Execute mark** (priest preset): a thin dark line on your target's health bar. Below it, Shadow Word: Death kills. The threshold comes from the spell's tooltip, so it grows with your spell power.
- **Cast bar:** bigger spell name, cast timer, grey while your interrupt is on cooldown.
- **Early aggro warning** in groups: a yellow glow before you pull threat. Tanks don't get it.
- **Health numbers** where they help: just the name normally, the number on mouseover, number and percent on your target.
- **Quest "!"** next to mobs and NPCs you need for quests.
- **Guild tags** under player names, if you want them.
- **Allied pets** as a small name with their owner, instead of the big floating titles.
- Enemies out of range fade to half opacity; enemy plates spread out instead of piling up.

## Unit frames (optional)

Text on the health and mana bars of your frame, your target and your target's target: current, percent, current / max, missing, or a mix. Each bar on its own; always, in combat only or out of combat only. Off by default: pick a format and it shows up right away.

## Good to know

- It works with the game's own nameplates. Turn off Plater and other nameplate addons: two of them get in each other's way.
- In dungeons and raids the game keeps addons away from allied nameplates; only the game's own options work there.
- Presets: base and priest, more classes to come. Your changes sit on top of the preset, and one button brings the preset back.
- `/fpl` opens the settings. They're also in Esc → Options → AddOns and on the minimap button.
- English and Russian.

---

# Forever Plates+ (на русском)

Стандартные неймплейты Forever и так хороши, им не хватает пары мелочей. Ради этого не нужно менять весь интерфейс.

Forever Plates+ оставляет неймплейты игры и их стиль. Он включает полезные настройки самой игры, добавляет то, чего игра не показывает, и даёт подогнать каждую часть.

## Кликнули на часть, подогнали

На каждой странице настроек есть схема неймплейта. Нажмите на имя, полосу каста или дебаффы, и под схемой останутся только настройки этой части: показывать ли, размер, прозрачность, цвет, место. Выключенные части нарисованы бледно, так что сразу видно, что включено.

## Что добавляет

- **Ваши дебаффы** над именем врага, с таймером. Баффы, которые можно снять, в синей рамке.
- **Дебаффы, которые вы можете снять,** у союзников, маленькими значками.
- **Отметка добивания** (пресет жреца): тонкая тёмная черта на полосе здоровья цели. Ниже неё «Слово Тьмы: Смерть» убивает. Порог берётся из описания заклинания, поэтому растёт вместе с силой заклинаний.
- **Полоса каста:** крупнее название заклинания, таймер каста, серая полоса, пока ваше прерывание на перезарядке.
- **Предупреждение об агро** в группе: жёлтое свечение до того, как вы сорвёте моба. Танку не показывается.
- **Цифры здоровья** там, где они нужны: обычно только имя, под курсором число, в цели число и проценты.
- **«!» задания** рядом с мобами и NPC, нужными для ваших заданий.
- **Гильдия** под именем игроков, если хотите.
- **Питомцы союзников:** мелкое имя и хозяин вместо больших подписей над головой.
- Враги вне досягаемости бледнеют, вражеские неймплейты раздвигаются, а не лезут друг на друга.

## Фреймы (по желанию)

Текст на полосах здоровья и маны вашего фрейма, цели и цели цели: текущее, проценты, текущее / максимум, сколько не хватает или вместе. Каждая полоса отдельно; всегда, только в бою или только вне боя. По умолчанию выключено: выберите формат, и он сразу появится.

## Полезно знать

- Работает с неймплейтами самой игры. Plater и другие аддоны неймплейтов отключите: два таких аддона мешают друг другу.
- В подземельях и рейдах игра не пускает аддоны к неймплейтам союзников, там работают только настройки самой игры.
- Пресеты: базовый и жреца, другие классы будут. Ваши правки лежат поверх пресета, одна кнопка возвращает пресет.
- `/fpl` открывает настройки. Ещё они в Esc → Настройки → Модификации и на кнопке у миникарты.
- Английский и русский.

<!-- копировать до сюда -->

---

## Скриншоты

| Файл | Подпись |
|---|---|
| `media/02-enemy.png` | Enemy page: click a part in the sketch, its settings appear below. / Враг: нажмите на часть схемы, под ней появятся её настройки. |
| `media/03-ally.png` | Ally page: guild tag under the name. / Союзник: гильдия под именем. |
| `media/05-frames.png` | Unit frames: text on health and mana bars, each bar on its own. / Фреймы: текст на полосах здоровья и маны, у каждой полосы свой. |
| `media/04-pet.png` | Allied pets: a name and its owner instead of the big titles. / Питомцы союзников: имя и хозяин вместо больших подписей. |
| `media/01-main.png` | Main page: preset and options for all nameplates. / Главная: пресет и настройки для всех неймплейтов. |
