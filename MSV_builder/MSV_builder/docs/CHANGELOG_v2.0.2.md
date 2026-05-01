# MSV Bed Builder v2.0.2

## Исправлено

- Кнопка **Создать** в HtmlDialog теперь вызывает Ruby callback через `sketchup.ok(json)`, а не через старый WebDialog-стиль `window.location = 'skp:ok@...'`.
- Кнопки **Отмена** и **Карта раскроя** также переведены на `sketchup.cancel()` и `sketchup.cutting(json)`.
- Убраны вложенные операции Undo: построение геометрии больше не запускает собственный `start_operation`, если его уже запускает команда создания/редактирования.
- Плагин разложен по стандартной структуре: loader, main, core, config, icons, components, docs.
- Пути к настройкам, иконкам и компоненту уголка обновлены под новую структуру.

## Структура

```text
MSV_builder_loader.rb
MSV_builder/
  main.rb
  core/MSV_bed_builder_enhanced.rb
  config/bed_settings.json
  icons/*.png
  components/support_bracket_component.skp
  docs/*.md
```

## Установка

Скопировать в папку Plugins SketchUp только:

```text
MSV_builder_loader.rb
MSV_builder/
```

Старые файлы удалить:

```text
bed_builder_loader.rb
bed_builder/
```
