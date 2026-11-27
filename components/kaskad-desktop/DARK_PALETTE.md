# Тёмная палитра Kaskad DE

В alpha.83 фоновые значения взяты из [Titanium.json](https://github.com/ilyamiro/serpantinum/blob/320fece13b69451e8e46e2285c1574dd2c0ad1de/src/assets/themes/Titanium.json). Это точные значения данного пресета, а не оценка по изображению. Какой пресет использован в видео, не установлено.

| Роль Kaskad | Роль Titanium | Цвет |
| --- | --- | --- |
| `background` | `crust` | `#08090a` |
| `backgroundText` | `text` | `#f0f2f5` |
| `surface` | `base` | `#141619` |
| `surfaceText` | `text` | `#f0f2f5` |
| `surfaceVariant` | `surface2` | `#434a54` |
| `surfaceVariantText` | `subtext0` | `#b3b9c2` |
| `outline` | `overlay0` | `#636c7a` |
| `outlineVariant` | `surface2` | `#434a54` |
| `surfaceContainerLowest` | `crust` | `#08090a` |
| `surfaceContainerLow` | `mantle` | `#0e0f11` |
| `surfaceContainer` | `base` | `#141619` |
| `surfaceContainerHigh` | `surface0` | `#22262b` |
| `surfaceContainerHighest` | `surface1` | `#32373e` |
| `surfaceBright` | `surface2` | `#434a54` |
| `surfaceDim` | `crust` | `#08090a` |

Обычная подложка виджетов (`sch`) в тёмном режиме — `Qt.darker(surface0, 1.15)`, как в `src/components/BarModule.qml` Serpantinum. Прозрачность применяется отдельно существующими настройками Kaskad.

Общие роли используются панелью, доком, лаунчером, настройками, меню, рамкой рабочего стола и декорациями окон. Акцентные роли остаются из выбранной темы Kaskad; цвет акцента Titanium не переносится. Светлый режим и явно заданные пользовательские цвета сохранены.

Alpha.81 и alpha.82 использовали приближённые цвета. Alpha.83 заменяет их значениями исходного пресета.
