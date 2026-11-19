# Страница на CurseForge

Готовый текст для страницы проекта. В архив аддона этот файл не попадает.

## Как заполнить

1. **Name:** `ForeverPlates`
2. **Summary** (одна строка, видна в поиске, на самой странице её нет), на двух языках:
   `The default Forever nameplates in the game's own style, with customization the built-in settings can't offer. / Стандартные неймплейты Forever в родном стиле игры — с настройками, которых нет в стандартном меню.`
   Если форма не примет такую длину — только английская половина.
3. **Avatar:** `media/logo.png` (1024×1024).
4. **Description:** включить режим Markdown и вставить всё из блока «Описание» ниже (английский сверху, русский под ним).
5. **Images:** скриншоты из таблицы «Скриншоты» ниже, с их подписями.
6. **File:** архив `ForeverPlates-<версия>.zip`, игра — **Forever** (Interface 16001). В поле Changelog — пункты нужной версии из `CHANGELOG.md`.

---

## Описание

<!-- копировать отсюда -->

# ForeverPlates

**The default Forever nameplates in the game's own style, with customization the built-in settings can't offer.**

ForeverPlates doesn't replace or reskin the nameplates. It works with the game's own: it turns on the useful game options and adds the settings and elements the game menu doesn't have.

## How the settings work

Each page shows a sketch of a nameplate: enemy, friendly player, friendly pet. Click a part (name, cast bar, debuffs and so on) and only that part's settings stay below it: show or hide, size, opacity, position, and color where it applies. Parts that are off are drawn faded.

## What the game menu can't do

- Size, opacity and position of every part; color for names and guild tags.
- Health numbers per situation: normally, on mouseover, on your target.
- The name above the bar or inside it.
- **Personal debuffs** above the enemy's name, with timers. **Purgeable buffs** in a blue border.
- **Dispellable debuffs** on friendly players.
- **Execute mark** (priest preset): a thin line on your target's health bar. Below it, Shadow Word: Death kills. The threshold comes from the spell tooltip.
- **Cast bar:** timer, gray while your interrupt is on cooldown.
- **Early aggro warning** in groups. Not shown to tanks.
- **Quest "!"** next to mobs and NPCs you need for quests.
- Guild tags under player names. Friendly pets as a small name with their owner instead of the big floating titles.
- Enemies out of range or other than your target can fade.

## Unit frames (optional)

Text on the health and power bars of your frame, your target and your target's target: current, percent, current / max, missing, or a combination. Each bar on its own; always, in combat only or out of combat only. Off by default.

## Good to know

- Turn off other nameplate addons such as Plater: two of them get in each other's way.
- In dungeons and raids the game keeps addons away from friendly nameplates; only the game's own options work there.
- Presets: base and priest. Your changes sit on top of the preset; one button brings the preset back.
- Settings: `/fpl`, Esc → Options → AddOns, or the minimap button.
- English and Russian: the addon follows your game client's language.

---

# ForeverPlates (на русском)

**Стандартные неймплейты Forever в родном стиле игры — с настройками, которых нет в стандартном меню.**

ForeverPlates не заменяет и не перерисовывает неймплейты. Он работает с неймплейтами самой игры: включает полезные настройки игры и добавляет настройки и элементы, которых нет в её меню.

## Как устроены настройки

На каждой странице — схема неймплейта: враг, союзный игрок, питомец союзника. Нажмите на часть (имя, полосу каста, дебаффы и т.д.), и под схемой останутся только её настройки: показывать ли, размер, прозрачность, место и цвет, где он есть. Выключенные части нарисованы бледно.

## Чего не умеет меню игры

- Размер, прозрачность и место каждой части; цвет имён и гильдии.
- Цифры здоровья по ситуации: обычно, под курсором, в цели.
- Имя над полосой или внутри неё.
- **Ваши дебаффы** над именем врага, с таймером. **Баффы, которые можно снять,** в синей рамке.
- **Дебаффы, которые вы можете рассеять,** у союзников.
- **Отметка добивания** (пресет жреца): тонкая черта на полосе здоровья цели. Ниже неё «Слово Тьмы: Смерть» убивает. Порог берётся из описания заклинания.
- **Полоса каста:** таймер, серая полоса, пока ваше прерывание на перезарядке.
- **Предупреждение об агро** в группе. Танку не показывается.
- **«!» задания** рядом с мобами и NPC, нужными для ваших заданий.
- Гильдия под именем игроков. Питомцы союзников — мелкое имя и хозяин вместо больших подписей над головой.
- Враги вне досягаемости или не в цели могут бледнеть.

## Фреймы (по желанию)

Текст на полосах здоровья и ресурса вашего фрейма, цели и цели цели: текущее, проценты, текущее / максимум, сколько не хватает или вместе. Каждая полоса отдельно; всегда, только в бою или только вне боя. По умолчанию выключено.

## Полезно знать

- Отключите другие аддоны неймплейтов, например Plater: два таких аддона мешают друг другу.
- В подземельях и рейдах игра не пускает аддоны к неймплейтам союзников, там работают только настройки самой игры.
- Пресеты: базовый и жреца. Ваши правки лежат поверх пресета, одна кнопка возвращает пресет.
- Настройки: `/fpl`, Esc → Настройки → Модификации или кнопка у миникарты.
- Английский и русский: язык аддона — как у клиента игры.

---

Source code and issues / Исходный код и баг-репорты: [github.com/SGUTFREE/ForeverPlates](https://github.com/SGUTFREE/ForeverPlates)

<!-- копировать до сюда -->

---

## Скриншоты

| Файл | Подпись |
|---|---|
| `media/02-enemy.png` | Enemy page: click a part in the sketch, its settings appear below. / Враг: нажмите на часть схемы, под ней появятся её настройки. |
| `media/03-ally.png` | Friendly page: guild tag under the name. / Союзник: гильдия под именем. |
| `media/05-frames.png` | Unit frames: text on health and mana bars, each bar on its own. / Фреймы: текст на полосах здоровья и маны, у каждой полосы свой. |
| `media/04-pet.png` | Friendly pets: a name and its owner instead of the big titles. / Питомцы союзников: имя и хозяин вместо больших подписей. |
| `media/01-main.png` | Main page: preset and options for all nameplates. / Главная: пресет и настройки для всех неймплейтов. |
