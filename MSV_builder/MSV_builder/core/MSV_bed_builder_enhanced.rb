# encoding: UTF-8
# Плагин: Конструктор кровати из МДФ
# Версия: 2.0.5
# Улучшения: валидация, раскрой, предпросмотр, сохранение настроек

require 'json'
require 'csv'
require 'uri'

if defined?(Sketchup)

  module MSV
    module BedBuilder
    VERSION = "2.0.5"
    MM_TO_INCH = 1.0 / 25.4
    PLUGIN_PATH = File.expand_path('..', File.dirname(__FILE__))
    CONFIG_PATH = File.join(PLUGIN_PATH, 'config')
    ICONS_PATH = File.join(PLUGIN_PATH, 'icons')
    COMPONENTS_PATH = File.join(PLUGIN_PATH, 'components')
    UI_PATH = File.join(PLUGIN_PATH, 'ui')
    SETTINGS_FILE = File.join(CONFIG_PATH, "bed_settings.json")
    ICON_CREATE_SMALL = File.join(ICONS_PATH, "create_small.png")
    ICON_CREATE_LARGE = File.join(ICONS_PATH, "create_large.png")
    ICON_EDIT_SMALL = File.join(ICONS_PATH, "edit_small.png")
    ICON_EDIT_LARGE = File.join(ICONS_PATH, "edit_large.png")
    SUPPORT_BRACKET_COMPONENT = File.join(COMPONENTS_PATH, "support_bracket_component.skp")

    # Проверка существования иконок с fallback
    ICON_CREATE_SMALL_VALID = File.exist?(ICON_CREATE_SMALL) ? ICON_CREATE_SMALL : nil
    ICON_CREATE_LARGE_VALID = File.exist?(ICON_CREATE_LARGE) ? ICON_CREATE_LARGE : nil
    ICON_EDIT_SMALL_VALID = File.exist?(ICON_EDIT_SMALL) ? ICON_EDIT_SMALL : nil
    ICON_EDIT_LARGE_VALID = File.exist?(ICON_EDIT_LARGE) ? ICON_EDIT_LARGE : nil

    # Проверка компонента уголка
    SUPPORT_BRACKET_AVAILABLE = File.exist?(SUPPORT_BRACKET_COMPONENT)

    # Предупреждения при загрузке
    missing_icons = []
    missing_icons << "create_small.png" unless ICON_CREATE_SMALL_VALID
    missing_icons << "create_large.png" unless ICON_CREATE_LARGE_VALID
    missing_icons << "edit_small.png" unless ICON_EDIT_SMALL_VALID
    missing_icons << "edit_large.png" unless ICON_EDIT_LARGE_VALID
    if missing_icons.any?
      puts "BedBuilder Warning: Missing icon files: #{missing_icons.join(', ')}"
    end
    puts "BedBuilder Info: Support bracket component #{SUPPORT_BRACKET_AVAILABLE ? 'found' : 'not found'}" 

    # Значения по умолчанию
    DEFAULT_SETTINGS = {
      version: 2,
      mw: 1600, ml: 2000, mo: 10, th: 250, tt: 16, lh: 150, mr: 50,
      st: "Центральная царга", co: "Вдоль", ch: "В уровень боковых царг", cch: 250, 
      dt: "Да", rf: "До пола",
      hb: "Да", hh: 900, ht: 16, he: 50,
      shb: "Нет", shp: "Слева", shh: 900, sht: 16, sef: 50, seb: 50,
      hbt: "Да", bo: 5, bt: 6, bs_l: 200, bs_h: 30, bs_t: 25,
      as: "Да", ms_l: 600, ms_h: 30, ms_t: 25,
      af: "Да",
      mdf_price: 0 # Для калькуляции стоимости
    }

    # ============================================================================
    # СОХРАНЕНИЕ И ЗАГРУЗКА ПОЛЬЗОВАТЕЛЬСКИХ НАСТРОЕК (Рекомендация #14)
    # ============================================================================
    
    def self.save_user_preferences(params)
      begin
        File.write(SETTINGS_FILE, JSON.pretty_generate(params))
        puts "BedBuilder: Settings saved to #{SETTINGS_FILE}"
        true
      rescue => e
        puts "BedBuilder Error: Failed to save settings - #{e.message}"
        false
      end
    end

    def self.load_user_preferences
      if File.exist?(SETTINGS_FILE)
        begin
          loaded = JSON.parse(File.read(SETTINGS_FILE), symbolize_names: true)
          # Merge with defaults to ensure all keys exist
          DEFAULT_SETTINGS.merge(loaded)
        rescue JSON::ParserError => e
          puts "BedBuilder Warning: Failed to parse settings file - #{e.message}"
          DEFAULT_SETTINGS.dup
        end
      else
        DEFAULT_SETTINGS.dup
      end
    end

    # ============================================================================
    # ВАЛИДАЦИЯ ВХОДНЫХ ДАННЫХ (Рекомендация #1, #2, #3)
    # ============================================================================
    
    def self.validate_params(params)
      errors = []
      
      # Проверка положительных значений
      [:mw, :ml, :th, :tt, :lh, :hh, :ht, :shh, :sht, :bs_l, :bs_h, :bs_t, :ms_l, :ms_h, :ms_t, :cch].each do |key|
        if params[key] && params[key] <= 0
          field_names = {
            mw: "Ширина матраса", ml: "Длина матраса", th: "Высота царг",
            tt: "Толщина МДФ", lh: "Высота ножек", hh: "Высота спинки",
            ht: "Толщина спинки", shh: "Высота боковой спинки", 
            sht: "Толщина боковой спинки", bs_l: "Длина бруска",
            bs_h: "Высота бруска для дна", bs_t: "Толщина бруска для дна",
            ms_l: "Длина опоры матраса", ms_h: "Высота опоры матраса",
            ms_t: "Толщина опоры матраса", cch: "Высота центр. царги"
          }
          errors << "#{field_names[key] || key} должно быть больше нуля"
        end
      end
      
      # Проверка минимальных размеров
      errors << "Ширина матраса слишком мала (минимум 500 мм)" if params[:mw] && params[:mw] < 500
      errors << "Длина матраса слишком мала (минимум 1000 мм)" if params[:ml] && params[:ml] < 1000
      errors << "Толщина МДФ слишком мала (минимум 6 мм)" if params[:tt] && params[:tt] < 6
      errors << "Высота царг слишком мала (минимум 100 мм)" if params[:th] && params[:th] < 100
      
      # Проверка геометрической совместимости
      if params[:mw] && params[:mo] && params[:tt]
        frame_width = params[:mw] + 2 * params[:mo] + 2 * params[:tt]
        errors << "Конструкция слишком узкая для центральной царги (минимум 600 мм)" if frame_width < 600
      end
      
      # Проверка утопления матраса
      if params[:mr] && params[:th] && params[:mr] >= params[:th]
        errors << "Утопление матраса (#{params[:mr]} мм) должно быть меньше высоты царг (#{params[:th]} мм)"
      end
      
      # Проверка наличия обязательных параметров
      [:mw, :ml, :th, :tt, :lh].each do |key|
        field_names = {
          mw: "Ширина матраса", ml: "Длина матраса", th: "Высота царг",
          tt: "Толщина МДФ", lh: "Высота ножек"
        }
        errors << "Не указано значение: #{field_names[key]}" if params[key].nil? || params[key] == 0
      end

      if params[:st] == "Центральная царга" && (params[:cch].nil? || params[:cch] <= 0)
        errors << "Высота центр. царги должна быть больше нуля"
      end
      
      errors
    end

    # ============================================================================
    # ГЕНЕРАЦИЯ HTML UI С ПРЕДПРОСМОТРОМ (Рекомендация #10)
    # ============================================================================
    
    def self.get_html_ui(is_edit, params_hash)
      template_path = File.join(UI_PATH, 'index.html')
      initial_data_json = JSON.generate(params_hash)
      submit_label = is_edit ? 'Применить' : 'Создать'
      html = File.read(template_path, encoding: 'UTF-8')
      html.gsub('%%INITIAL_DATA%%', initial_data_json)
          .gsub('%%SUBMIT_LABEL%%', submit_label)
    end

    def self.get_input(is_edit, params, &callback)
      dlg = UI::HtmlDialog.new({ dialog_title: is_edit ? "Изменить кровать" : "Создать кровать", 
                                  preferences_key: "com.msv.bed_builder", scrollable: true, 
                                  width: 700, height: 650, resizable: true })
      dlg.set_html(get_html_ui(is_edit, params))
      
      dlg.add_action_callback("ok") { |_, json_str|
        begin
          decoded = json_str.to_s
          begin
            decoded = URI.decode_www_form_component(decoded)
          rescue ArgumentError
            # HtmlDialog callbacks now pass raw JSON. Keep URI decoding only for old saved dialogs.
          end
          res = JSON.parse(decoded, symbolize_names: true)
          res[:version] = 2
          dlg.close
          callback.call(res)
        rescue JSON::ParserError => e
          UI.messagebox("Ошибка парсинга данных: #{e.message}")
        end
      }
      
      dlg.add_action_callback("cancel") { dlg.close }
      
      dlg.add_action_callback("cutting") { |_, json_str|
        begin
          decoded = json_str.to_s
          begin
            decoded = URI.decode_www_form_component(decoded)
          rescue ArgumentError
          end
          res = JSON.parse(decoded, symbolize_names: true)
          generate_cutting_list(res)
        rescue => e
          UI.messagebox("Ошибка генерации карты раскроя: #{e.message}")
        end
      }
      
      dlg.show
    end

    def self.create_bed
      # Загрузка последних настроек пользователя
      last_settings = load_user_preferences
      
      get_input(false, last_settings) { |res|
        # Валидация перед созданием
        errors = validate_params(res)
        if errors.any?
          UI.messagebox("Ошибки валидации:\n\n" + errors.join("\n"))
          return
        end
        
        model = Sketchup.active_model
        model.start_operation("Создать кровать #{res[:mw]}×#{res[:ml]}мм", true)
        
        begin
          bed = build_bed_geometry(res, model.active_entities)
          if bed && bed.valid?
            model.selection.clear
            model.selection.add(bed)
            
            # Сохранение настроек для следующего раза
            save_user_preferences(res)
          end
          model.commit_operation
          UI.messagebox("Кровать создана успешно!") if bed && bed.valid?
        rescue => e
          model.abort_operation
          UI.messagebox("Ошибка при создании кровати: #{e.message}\n\n#{e.backtrace.first(3).join("\n")}")
        end
      }
    end

    def self.safe_add_group(parent, name)
      g = parent.entities.add_group
      g.name = name
      g
    rescue => e
      puts "BedBuilder Error in safe_add_group: #{e.message}"
      nil
    end

    # ============================================================================
    # ЗАГРУЗКА КОМПОНЕНТА УГОЛКА (Рекомендация #7)
    # ============================================================================
    
    def self.load_support_bracket_component(model)
      return nil unless SUPPORT_BRACKET_AVAILABLE
      
      begin
        # Проверяем, не загружен ли уже компонент
        definition = model.definitions.find { |d| d.name == "SupportBracket" }
        
        unless definition
          # Загружаем компонент из файла
          definition = model.definitions.load(SUPPORT_BRACKET_COMPONENT)
          definition.name = "SupportBracket" if definition
          puts "BedBuilder: Support bracket component loaded"
        end
        
        definition
      rescue => e
        puts "BedBuilder Warning: Failed to load support bracket component - #{e.message}"
        nil
      end
    end

    def self.add_support_brackets(main_group, params, frame_w, frame_l, tti, c_h, lhi, actual_tt)
      return unless params[:st] == "Центральная царга"
      
      model = Sketchup.active_model
      bracket_def = load_support_bracket_component(model)
      
      unless bracket_def
        # Fallback: создаем простые геометрические уголки
        add_simple_brackets(main_group, params, frame_w, frame_l, tti, c_h, lhi, actual_tt)
        return
      end
      
      # Позиции для уголков (зависит от ориентации центральной царги)
      positions = []
      
      if params[:co] == "Вдоль"
        # Центральная царга вдоль - уголки по бокам от нее
        center_x = frame_w / 2
        positions = [
          [center_x - tti/2 - 50*MM_TO_INCH, frame_l/2, 0, 0],     # Слева от царги
          [center_x + tti/2 + 50*MM_TO_INCH, frame_l/2, 0, 180]   # Справа от царги
        ]
      else
        # Центральная царга поперек - уголки сверху и снизу от нее
        center_y = frame_l / 2
        positions = [
          [frame_w/2, center_y - tti/2 - 50*MM_TO_INCH, 0, 90],   # Сверху от царги
          [frame_w/2, center_y + tti/2 + 50*MM_TO_INCH, 0, -90]   # Снизу от царги
        ]
      end
      
      # Вычисляем Z позицию для уголков
      z_pos = if params[:ch] == "До пола"
                c_h  # На верху центральной царги
              else
                lhi + c_h  # На верху центральной царги от ножек
              end
      
      # Размещаем компоненты уголков
      positions.each_with_index do |(x, y, z, rotation), idx|
        instance = main_group.entities.add_instance(bracket_def, Geom::Transformation.new)
        
        # Позиционирование и поворот
        tr = Geom::Transformation.translation([x, y, z_pos])
        tr = tr * Geom::Transformation.rotation([x, y, z_pos], [0, 0, 1], rotation.degrees)
        
        instance.transform!(tr)
        instance.name = "Уголок #{idx + 1}"
      end
      
      puts "BedBuilder: #{positions.size} support brackets added"
    end

    def self.add_simple_brackets(main_group, params, frame_w, frame_l, tti, c_h, lhi, actual_tt)
      # Простые геометрические уголки как fallback
      bracket_size = 80 * MM_TO_INCH
      bracket_thickness = 3 * MM_TO_INCH
      
      positions = []
      if params[:co] == "Вдоль"
        center_x = frame_w / 2
        positions = [[center_x - tti/2 - bracket_size, frame_l/2], 
                     [center_x + tti/2, frame_l/2]]
      else
        center_y = frame_l / 2
        positions = [[frame_w/2, center_y - tti/2 - bracket_size], 
                     [frame_w/2, center_y + tti/2]]
      end
      
      positions.each_with_index do |pos, idx|
        bracket = safe_add_group(main_group, "Уголок #{idx + 1}")
        next unless bracket
        
        # L-образный профиль
        pts = [[0,0,0], [bracket_size,0,0], [bracket_size,bracket_thickness,0], 
               [bracket_thickness,bracket_thickness,0], [bracket_thickness,bracket_size,0], 
               [0,bracket_size,0]]
        f = bracket.entities.add_face(pts)
        f.pushpull(-bracket_thickness)
        
        bracket.transform!(Geom::Transformation.translation([pos[0], pos[1], lhi + c_h - bracket_size]))
      end
    end

    def self.sanitize_part_name(name)
      clean = name.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      clean.gsub(/[<>:"\\|?*\x00-\x1F]/, ' ').gsub(/\s+/, ' ').strip
    end

    def self.unique_component_definition_name(model, base_name)
      existing = model.definitions.map(&:name)
      return base_name unless existing.include?(base_name)

      index = 1
      index += 1 while existing.include?("#{base_name}_#{index}")
      "#{base_name}_#{index}"
    end

    def self.tag_name_for_part(name)
      case name
      when /Дно/
        'MSV_Дно'
      when /Брусок|Опора матраса|Опорный брусок/
        'MSV_Опоры'
      when /Уголок|Стяжка/
        'MSV_Фурнитура'
      when /Ножка/
        'MSV_Ножки'
      else
        'MSV_Каркас'
      end
    end

    def self.assign_part_metadata(instance, name, tag_name = nil)
      clean_name = sanitize_part_name(name)
      instance.name = clean_name
      instance.set_attribute('MSV_BedBuilder', 'part_name', clean_name)
      instance.set_attribute('MSV_BedBuilder', 'version', VERSION)
      instance.set_attribute('OpenCutList', 'part_name', clean_name)

      begin
        tag = Sketchup.active_model.layers.add(tag_name || tag_name_for_part(clean_name))
        instance.layer = tag
      rescue => e
        puts "BedBuilder Warning: failed to assign tag for #{clean_name} - #{e.message}"
      end

      instance
    end

    def self.definition_cache
      @definition_cache ||= {}
    end

    def self.add_box_group(parent, name, x, y, z, width, depth, height)
      return nil if width <= 0 || depth <= 0 || height <= 0

      model = Sketchup.active_model
      clean_name = sanitize_part_name(name)
      size_key = [clean_name, width.round(6), depth.round(6), height.round(6)].join('|')
      definition = definition_cache[size_key]

      unless definition && definition.valid?
        definition_name = unique_component_definition_name(model, clean_name)
        definition = model.definitions.add(definition_name)
        face = definition.entities.add_face([[0,0,0], [width,0,0], [width,depth,0], [0,depth,0]])
        return nil unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(height)
        definition_cache[size_key] = definition
      end

      instance = parent.entities.add_instance(definition, Geom::Transformation.translation([x, y, z]))
      assign_part_metadata(instance, clean_name)
    rescue => e
      puts "BedBuilder Error in add_box_group(#{name}): #{e.message}"
      nil
    end

    def self.add_cylinder_component(parent, name, x, y, z, radius, height)
      return nil if radius <= 0 || height <= 0

      model = Sketchup.active_model
      clean_name = sanitize_part_name(name)
      size_key = [clean_name, radius.round(6), height.round(6)].join('|')
      definition = definition_cache[size_key]

      unless definition && definition.valid?
        definition_name = unique_component_definition_name(model, clean_name)
        definition = model.definitions.add(definition_name)
        circle = definition.entities.add_circle([0, 0, 0], [0, 0, 1], radius, 24)
        face = definition.entities.add_face(circle)
        return nil unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(height)
        definition_cache[size_key] = definition
      end

      instance = parent.entities.add_instance(definition, Geom::Transformation.translation([x, y, z]))
      assign_part_metadata(instance, clean_name, 'MSV_Ножки')
    rescue => e
      puts "BedBuilder Error in add_cylinder_component(#{name}): #{e.message}"
      nil
    end

    def self.distributed_support_offsets(total_length, piece_length)
      return [] if total_length <= 0 || piece_length <= 0

      count = (total_length / piece_length).floor
      count = 1 if count < 1
      actual_length = [piece_length, total_length].min
      gap = (total_length - count * actual_length) / (count + 1)
      Array.new(count) { |i| gap + i * (actual_length + gap) }
    end

    def self.add_mattress_support_brackets(main_group, params, frame_w, frame_l, tti, thi, lhi, mri)
      # Опорные бруски матраса ставятся на внутренних гранях царг под матрас.
      support_len = (params[:ms_l] || 600) * MM_TO_INCH
      support_height = (params[:ms_h] || 30) * MM_TO_INCH
      support_thickness = (params[:ms_t] || 25) * MM_TO_INCH
      support_z = [lhi + thi - mri - support_height, 0].max

      # Продольные бруски на внутренних гранях боковых царг.
      side_start = tti
      side_total = frame_l - 2 * tti
      distributed_support_offsets(side_total, support_len).each_with_index do |offset, idx|
        y = side_start + offset
        length = [support_len, side_total].min
        add_box_group(main_group, "Опорный брусок матраса левый", tti, y, support_z, support_thickness, length, support_height)
        add_box_group(main_group, "Опорный брусок матраса правый", frame_w - tti - support_thickness, y, support_z, support_thickness, length, support_height)
      end

      # Поперечные бруски на внутренних гранях передней и задней царги.
      front_start = tti
      front_total = frame_w - 2 * tti
      distributed_support_offsets(front_total, support_len).each_with_index do |offset, idx|
        x = front_start + offset
        length = [support_len, front_total].min
        add_box_group(main_group, "Опорный брусок матраса передний", x, tti, support_z, length, support_thickness, support_height)
        add_box_group(main_group, "Опорный брусок матраса задний", x, frame_l - tti - support_thickness, support_z, length, support_thickness, support_height)
      end
    end

    def self.add_corner_tie_brackets(main_group, _params, frame_w, frame_l, tti, _thi, lhi)
      # Стяжные уголки соединяют боковые царги с передней и задней царгами.
      bracket_len = 70 * MM_TO_INCH
      bracket_depth = 16 * MM_TO_INCH
      bracket_height = 35 * MM_TO_INCH
      z = lhi + 20 * MM_TO_INCH

      corners = [
        [tti, tti, 1, 1, "передний левый"],
        [frame_w - tti, tti, -1, 1, "передний правый"],
        [tti, frame_l - tti, 1, -1, "задний левый"],
        [frame_w - tti, frame_l - tti, -1, -1, "задний правый"]
      ]

      corners.each do |cx, cy, sx, sy, label|
        x_leg_x = sx.positive? ? cx : cx - bracket_len
        x_leg_y = sy.positive? ? cy : cy - bracket_depth
        y_leg_x = sx.positive? ? cx : cx - bracket_depth
        y_leg_y = sy.positive? ? cy : cy - bracket_len
        add_box_group(main_group, "Стяжка уголок #{label} X", x_leg_x, x_leg_y, z, bracket_len, bracket_depth, bracket_height)
        add_box_group(main_group, "Стяжка уголок #{label} Y", y_leg_x, y_leg_y, z, bracket_depth, bracket_len, bracket_height)
      end
    end

    # ============================================================================
    # ГЕНЕРАЦИЯ КАРТЫ РАСКРОЯ (Рекомендация #6)
    # ============================================================================
    
    def self.generate_cutting_list(params)
      parts = []
      
      # Расчет размеров
      tti = params[:tt] * MM_TO_INCH
      moi = params[:mo] * MM_TO_INCH
      frame_w = params[:mw] + 2 * params[:mo] + 2 * params[:tt]
      frame_l = params[:ml] + 2 * params[:mo] + 2 * params[:tt]
      frame_inner_w = params[:mw] + 2 * params[:mo]
      frame_inner_l = params[:ml] + 2 * params[:mo]
      
      # Боковые царги (вдоль длины)
      if params[:dt] == "Да"
        parts << {
          name: "Царга боковая (внешняя)",
          qty: 2,
          length: params[:ml] + 2 * params[:mo],
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
        parts << {
          name: "Царга боковая (внутренняя)",
          qty: 2,
          length: params[:ml] + 2 * params[:mo],
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
      else
        parts << {
          name: "Царга боковая",
          qty: 2,
          length: params[:ml] + 2 * params[:mo],
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
      end
      
      # Передняя и задняя царги
      if params[:dt] == "Да"
        # Двойные царги
        parts << {
          name: "Царга передняя (внешняя)",
          qty: 1,
          length: frame_w,
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
        parts << {
          name: "Царга передняя (внутренняя)",
          qty: 1,
          length: frame_inner_w,
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
        
        if params[:rf] == "До пола"
          parts << {
            name: "Царга задняя (внешняя)",
            qty: 1,
            length: frame_w,
            width: params[:lh] + params[:th],
            thickness: params[:tt],
            material: "МДФ"
          }
          parts << {
            name: "Царга задняя (внутренняя)",
            qty: 1,
            length: frame_inner_w,
            width: params[:lh] + params[:th],
            thickness: params[:tt],
            material: "МДФ"
          }
        else
          parts << {
            name: "Царга задняя (внешняя)",
            qty: 1,
            length: frame_w,
            width: params[:th],
            thickness: params[:tt],
            material: "МДФ"
          }
          parts << {
            name: "Царга задняя (внутренняя)",
            qty: 1,
            length: frame_inner_w,
            width: params[:th],
            thickness: params[:tt],
            material: "МДФ"
          }
        end
      else
        # Одинарные царги
        parts << {
          name: "Царга передняя",
          qty: 1,
          length: frame_w,
          width: params[:th],
          thickness: params[:tt],
          material: "МДФ"
        }
        
        back_height = params[:rf] == "До пола" ? params[:lh] + params[:th] : params[:th]
        parts << {
          name: "Царга задняя",
          qty: 1,
          length: frame_w,
          width: back_height,
          thickness: params[:tt],
          material: "МДФ"
        }
      end
      
      # Центральная царга
      if params[:st] == "Центральная царга"
        center_height = params[:cch] || if params[:ch] == "До пола"
                         params[:lh] + params[:th]
                       else
                         params[:th]
                       end
        
        if params[:co] == "Вдоль"
          parts << {
            name: "Царга центральная",
            qty: 1,
            length: frame_inner_l,
            width: center_height,
            thickness: params[:tt],
            material: "МДФ"
          }
        else
          parts << {
            name: "Царга центральная",
            qty: 1,
            length: frame_inner_w,
            width: center_height,
            thickness: params[:tt],
            material: "МДФ"
          }
        end
      end
      
      # Изголовье
      if params[:hb] == "Да"
        parts << {
          name: "Изголовье (спинка)",
          qty: 1,
          length: frame_w + 2 * params[:he],
          width: params[:hh],
          thickness: params[:ht],
          material: "МДФ"
        }
      end
      
      # Боковая спинка
      if params[:shb] == "Да"
        parts << {
          name: "Спинка боковая",
          qty: 1,
          length: frame_l + params[:sef] + params[:seb],
          width: params[:shh],
          thickness: params[:sht],
          material: "МДФ"
        }
      end
      
      # Дно
      if params[:hbt] == "Да"
        boi = params[:bo] * MM_TO_INCH
        is_split = params[:st] == "Центральная царга"
        
        if is_split
          if params[:co] == "Вдоль"
            bw = (frame_inner_w - params[:tt]) / 2 - 2 * params[:bo]
            bl = frame_inner_l - 2 * params[:bo]
            parts << {
              name: "Дно (панель)",
              qty: 2,
              length: bl,
              width: bw,
              thickness: params[:bt],
              material: "Фанера/ДВП"
            }
          else
            bw = frame_inner_w - 2 * params[:bo]
            bl = (frame_inner_l - params[:tt]) / 2 - 2 * params[:bo]
            parts << {
              name: "Дно (панель)",
              qty: 2,
              length: bl,
              width: bw,
              thickness: params[:bt],
              material: "Фанера/ДВП"
            }
          end
        else
          bw = frame_inner_w - 2 * params[:bo]
          bl = frame_inner_l - 2 * params[:bo]
          parts << {
            name: "Дно",
            qty: 1,
            length: bl,
            width: bw,
            thickness: params[:bt],
            material: "Фанера/ДВП"
          }
        end
        
        # Бруски для дна считаются отдельно в погонных метрах.
        bottom_support_total = 2 * frame_inner_l + 2 * frame_inner_w
        bottom_support_count = (bottom_support_total / params[:bs_l]).ceil
        
        parts << {
          name: "Брусок для дна",
          qty: bottom_support_count,
          length: params[:bs_l],
          width: params[:bs_h],
          thickness: params[:bs_t],
          material: "Брус",
          linear_category: "Бруски для дна"
        }
      end

      # Опорные бруски матраса считаются отдельно в погонных метрах.
      if params[:as] == "Да"
        mattress_support_total = 2 * frame_inner_l + 2 * frame_inner_w
        mattress_support_count = (mattress_support_total / params[:ms_l]).ceil
        parts << {
          name: "Опорный брусок матраса",
          qty: mattress_support_count,
          length: params[:ms_l],
          width: params[:ms_h],
          thickness: params[:ms_t],
          material: "Брус",
          linear_category: "Опорные бруски матраса"
        }
      end
      
      # Расчет общей площади МДФ
      total_area_mdf = 0
      total_area_other = 0
      
      parts.each do |part|
        area = (part[:length] * part[:width] / 1_000_000.0) * part[:qty]
        if part[:material] == "МДФ"
          total_area_mdf += area
        else
          total_area_other += area
        end
      end

      bottom_support_m = parts.select { |part| part[:linear_category] == "Бруски для дна" }
                              .sum { |part| part[:length] * part[:qty] / 1000.0 }
      mattress_support_m = parts.select { |part| part[:linear_category] == "Опорные бруски матраса" }
                                .sum { |part| part[:length] * part[:qty] / 1000.0 }
      total_support_m = bottom_support_m + mattress_support_m
      
      # Генерация CSV
      csv_path = UI.savepanel("Сохранить карту раскроя", "", "bed_cutting_list.csv")
      return unless csv_path
      
      begin
        CSV.open(csv_path, "wb", encoding: "UTF-8") do |csv|
          csv << ["КАРТА РАСКРОЯ КРОВАТИ"]
          csv << ["Дата создания", Time.now.strftime("%d.%m.%Y %H:%M")]
          csv << []
          csv << ["Размеры кровати:", "#{frame_w.round}×#{frame_l.round}×#{(params[:lh] + params[:th]).round} мм"]
          csv << ["Размер матраса:", "#{params[:mw]}×#{params[:ml]} мм"]
          csv << []
          csv << ["Название детали", "Кол-во", "Длина (мм)", "Ширина (мм)", "Толщина (мм)", "Материал", "Площадь (м²)"]
          
          parts.each do |part|
            area = (part[:length] * part[:width] / 1_000_000.0) * part[:qty]
            csv << [
              part[:name],
              part[:qty],
              part[:length].round,
              part[:width].round,
              part[:thickness].round,
              part[:material],
              area.round(4)
            ]
          end
          
          csv << []
          csv << ["ИТОГО"]
          csv << ["Площадь МДФ (м²)", total_area_mdf.round(3)]
          csv << ["Площадь прочих материалов (м²)", total_area_other.round(3)]
          csv << ["Общая площадь (м²)", (total_area_mdf + total_area_other).round(3)]
          csv << []
          csv << ["ИТОГО ПОГОННЫЕ МЕТРЫ"]
          csv << ["Бруски для дна (п.м.)", bottom_support_m.round(3)]
          csv << ["Опорные бруски матраса (п.м.)", mattress_support_m.round(3)]
          csv << ["Бруски всего (п.м.)", total_support_m.round(3)]
          
          if params[:mdf_price] && params[:mdf_price] > 0
            csv << []
            csv << ["СТОИМОСТЬ (примерная)"]
            csv << ["Цена МДФ за м²", "#{params[:mdf_price]} руб"]
            csv << ["Стоимость МДФ", "#{(total_area_mdf * params[:mdf_price]).round(2)} руб"]
          end
        end
        
        UI.messagebox("Карта раскроя сохранена:\n#{csv_path}\n\nПлощадь МДФ: #{total_area_mdf.round(3)} м²")
        
        # Открыть файл в системном редакторе
        UI.openURL("file:///#{csv_path}")
      rescue => e
        UI.messagebox("Ошибка при сохранении карты раскроя: #{e.message}")
      end
    end

    # ============================================================================
    # ПОСТРОЕНИЕ ГЕОМЕТРИИ (С УЛУЧШЕННОЙ ПОДДЕРЖКОЙ UNDO - Рекомендация #6)
    # ============================================================================
    
    def self.build_bed_geometry(p, entities = Sketchup.active_model.active_entities)
      p = p.transform_values { |v| v.is_a?(String) && v =~ /^\d+$/ ? v.to_i : v }

      begin
        main_group = entities.add_group
        main_group.name = "Кровать #{p[:mw]}×#{p[:ml]}"
        main_group.set_attribute("BedBuilder", "version", VERSION)
        main_group.set_attribute("BedBuilder", "params_json", JSON.generate(p))

        tti = p[:tt] * MM_TO_INCH
        thi = p[:th] * MM_TO_INCH
        lhi = p[:lh] * MM_TO_INCH
        mri = p[:mr] * MM_TO_INCH

        frame_w = p[:mw] + 2 * p[:mo] + 2 * p[:tt]
        frame_l = p[:ml] + 2 * p[:mo] + 2 * p[:tt]
        frame_inner_w = p[:mw] + 2 * p[:mo]
        frame_inner_l = p[:ml] + 2 * p[:mo]

        fwi = frame_w * MM_TO_INCH
        fli = frame_l * MM_TO_INCH
        inner_wi = frame_inner_w * MM_TO_INCH
        inner_li = frame_inner_l * MM_TO_INCH

        side_depth = fli - 2 * tti
        front_back_inner_width = inner_wi
        panel_z = lhi

        # Боковые царги
        add_box_group(main_group, "Царга левая", 0, tti, panel_z, tti, side_depth, thi)
        add_box_group(main_group, "Царга правая", fwi - tti, tti, panel_z, tti, side_depth, thi)

        # Внутренние боковые царги при двойной конструкции
        if p[:dt] == "Да"
          add_box_group(main_group, "Царга левая внутренняя", tti, tti, panel_z, tti, side_depth, thi)
          add_box_group(main_group, "Царга правая внутренняя", fwi - 2 * tti, tti, panel_z, tti, side_depth, thi)
        end

        # Передняя царга
        if p[:dt] == "Да"
          add_box_group(main_group, "Царга передняя (внешняя)", 0, 0, lhi, fwi, tti, thi)
          add_box_group(main_group, "Царга передняя (внутренняя)", tti, tti, lhi, front_back_inner_width, tti, thi)
        else
          add_box_group(main_group, "Царга передняя", 0, 0, lhi, fwi, tti, thi)
        end

        # Задняя царга
        back_h = (p[:rf] == "До пола") ? lhi + thi : thi
        back_z = (p[:rf] == "До пола") ? 0 : lhi
        if p[:dt] == "Да"
          add_box_group(main_group, "Царга задняя (внешняя)", 0, fli - tti, back_z, fwi, tti, back_h)
          add_box_group(main_group, "Царга задняя (внутренняя)", tti, fli - 2 * tti, back_z, front_back_inner_width, tti, back_h)
        else
          add_box_group(main_group, "Царга задняя", 0, fli - tti, back_z, fwi, tti, back_h)
        end

        # Изголовье. Строится от пола, а не от уровня матраса/царг.
        if p[:hb] == "Да"
          hti = p[:ht] * MM_TO_INCH
          hhi = p[:hh] * MM_TO_INCH
          hei = p[:he] * MM_TO_INCH
          add_box_group(main_group, "Изголовье", -hei, fli, 0, fwi + 2 * hei, hti, hhi)
        end

        # Боковая спинка. Строится от пола.
        if p[:shb] == "Да"
          shti = p[:sht] * MM_TO_INCH
          shhi = p[:shh] * MM_TO_INCH
          sefi = p[:sef] * MM_TO_INCH
          sebi = p[:seb] * MM_TO_INCH
          x_pos = (p[:shp] == "Слева") ? -shti : fwi
          add_box_group(main_group, "Спинка боковая", x_pos, -sebi, 0, shti, fli + sefi + sebi, shhi)
        end

        # Центральная царга. "Низ центр. царги" управляет нижней отметкой,
        # "Высота центр. царги" управляет высотой самой детали.
        if p[:st] == "Центральная царга"
          center_height = (p[:cch] || (p[:ch] == "До пола" ? p[:lh] + p[:th] : p[:th])) * MM_TO_INCH
          center_z = (p[:ch] == "До пола") ? 0 : lhi

          if p[:co] == "Вдоль"
            add_box_group(
              main_group, "Центральная царга",
              (fwi - tti) / 2, tti, center_z,
              tti, fli - 2 * tti, center_height
            )
          else
            add_box_group(
              main_group, "Центральная царга",
              tti, (fli - tti) / 2, center_z,
              inner_wi, tti, center_height
            )
          end
        end

        # Опорные бруски матраса и стяжные уголки.
        add_mattress_support_brackets(main_group, p, fwi, fli, tti, thi, lhi, mri) if p[:as] == "Да"
        add_corner_tie_brackets(main_group, p, fwi, fli, tti, thi, lhi) if p[:af] == "Да"

        # Дно и опоры
        if p[:hbt] == "Да"
          boi = p[:bo] * MM_TO_INCH
          bti = p[:bt] * MM_TO_INCH
          bs_li = p[:bs_l] * MM_TO_INCH
          bs_hi = p[:bs_h] * MM_TO_INCH
          bs_ti = p[:bs_t] * MM_TO_INCH
          is_split = (p[:st] == "Центральная царга")

          if is_split
            if p[:co] == "Вдоль"
              bwi = ((frame_inner_w - p[:tt]) / 2 - 2 * p[:bo]) * MM_TO_INCH
              bli = (frame_inner_l - 2 * p[:bo]) * MM_TO_INCH
              [[tti + boi, tti + boi], [(fwi + tti) / 2 + boi, tti + boi]].each_with_index do |pos, idx|
                add_box_group(main_group, "Дно (панель #{idx + 1})", pos[0], pos[1], lhi + bs_hi, bwi, bli, bti)
              end
            else
              bwi = (frame_inner_w - 2 * p[:bo]) * MM_TO_INCH
              bli = ((frame_inner_l - p[:tt]) / 2 - 2 * p[:bo]) * MM_TO_INCH
              [[tti + boi, tti + boi], [tti + boi, (fli + tti) / 2 + boi]].each_with_index do |pos, idx|
                add_box_group(main_group, "Дно (панель #{idx + 1})", pos[0], pos[1], lhi + bs_hi, bwi, bli, bti)
              end
            end
          else
            bwi = (frame_inner_w - 2 * p[:bo]) * MM_TO_INCH
            bli = (frame_inner_l - 2 * p[:bo]) * MM_TO_INCH
            add_box_group(main_group, "Дно", tti + boi, tti + boi, lhi + bs_hi, bwi, bli, bti)
          end

          # Опорные бруски
          gap_clr = 200 * MM_TO_INCH
          [[tti, "L"], [fwi - tti - bs_ti, "R"]].each do |x, side_n|
            sects = (is_split && p[:co] == "Поперек") ? [[tti + gap_clr, (fli - tti) / 2 - gap_clr], [(fli + tti) / 2 + gap_clr, fli - tti - gap_clr]] : [[tti + gap_clr, fli - tti - gap_clr]]
            sects.each do |s1, s2|
              len = s2 - s1
              next if len < bs_li
              nb = (sects.size > 1 ? 2 : 4)
              d = 0
              loop { break if nb <= 1; d = (len - nb * bs_li) / (nb - 1); break if d >= bs_li; nb -= 1 }
              nb.times do |i|
                add_box_group(main_group, "Брусок для дна #{side_n}", x, s1 + i * (bs_li + d), lhi, bs_ti, bs_li, bs_hi)
              end
            end
          end

          coff = gap_clr + bs_ti
          [[tti, "F"], [fli - tti - bs_ti, "B"]].each do |y, side_n|
            sects = (is_split && p[:co] == "Вдоль") ? [[tti + coff, (fwi - tti) / 2 - gap_clr], [(fwi + tti) / 2 + gap_clr, fwi - tti - coff]] : [[tti + coff, fwi - tti - coff]]
            sects.each do |s1, s2|
              len = s2 - s1
              next if len < bs_li
              nb = (sects.size > 1 ? 2 : 4)
              d = 0
              loop { break if nb <= 1; d = (len - nb * bs_li) / (nb - 1); break if d >= bs_li; nb -= 1 }
              nb.times do |i|
                add_box_group(main_group, "Брусок для дна #{side_n}", s1 + i * (bs_li + d), y, lhi, bs_li, bs_ti, bs_hi)
              end
            end
          end
        end

        # Ножки
        leg_pos = [[tti, tti], [fwi - tti, tti], [tti, fli - tti], [fwi - tti, fli - tti]]
        leg_pos.each_with_index do |pos, idx|
          next if p[:dt] == "Да" && p[:rf] == "До пола" && idx >= 2
          add_cylinder_component(main_group, "Ножка #{idx + 1}", pos[0], pos[1], 0, 25 * MM_TO_INCH, lhi)
        end

        main_group
      rescue => e
        main_group.erase! if main_group && main_group.valid?
        raise e
      end
    end

    def self.edit_bed
      model = Sketchup.active_model
      sel = model.selection
      
      if sel.length != 1 || !sel[0].is_a?(Sketchup::Group)
        UI.messagebox("Выберите одну кровать (группу)!")
        return
      end
      
      bed_group = sel[0]
      json = bed_group.get_attribute("BedBuilder", "params_json")
      
      if json
        begin
          params = JSON.parse(json, symbolize_names: true)
          
          # Миграция старой версии
          unless params[:version]
            params = migrate_old_params(params)
          end
          
        rescue JSON::ParserError => e
          UI.messagebox("Ошибка чтения параметров (JSON): #{e.message}")
          return
        end
      else
        # Попытка загрузить старый формат
        old = bed_group.get_attribute("BedBuilder", "params")
        if old
          params = migrate_old_csv_params(old)
        else
          UI.messagebox("Это не кровать BedBuilder или параметры не найдены!")
          return
        end
      end
      
      orig_tr = bed_group.transformation
      
      get_input(true, params) { |res|
        begin
          # Более описательное название операции для истории
          operation_name = "Изменить кровать на #{res[:mw]}×#{res[:ml]}мм"
          model.start_operation(operation_name, true)
          
          bed_group.erase!
          new_bed = build_bed_geometry(res, model.active_entities)
          
          if new_bed && new_bed.valid?
            new_bed.transformation = orig_tr
            model.selection.clear
            model.selection.add(new_bed)
            
            # Сохранение настроек
            save_user_preferences(res)
          end
          
          model.commit_operation
        rescue => e
          UI.messagebox("Ошибка при изменении кровати: #{e.message}\n\n#{e.backtrace.first(3).join("\n")}")
          model.abort_operation rescue nil
        end
      }
    end

    # ============================================================================
    # МИГРАЦИЯ СТАРЫХ ПАРАМЕТРОВ
    # ============================================================================
    
    def self.migrate_old_params(params)
      migrated = DEFAULT_SETTINGS.merge(params)
      migrated[:version] = 2
      migrated[:cch] ||= 250
      migrated[:ms_l] ||= 600
      migrated[:ms_h] ||= 30
      migrated[:ms_t] ||= 25
      migrated
    end

    def self.migrate_old_csv_params(csv_string)
      vals = csv_string.split(',')
      params = {
        version: 2,
        mw: vals[0].to_f,
        ml: vals[1].to_f,
        th: vals[2].to_f,
        tt: vals[3].to_f,
        st: vals[4],
        hb: vals[5],
        hh: vals[6].to_f,
        ht: vals[7].to_f,
        lh: vals[8].to_f,
        mr: vals[9].to_f,
        co: vals[10],
        ch: vals[11],
        he: vals[12].to_f,
        dt: vals[13],
        rf: vals[14],
        hbt: vals[15],
        bt: vals[16].to_f,
        bs_l: vals[17].to_f,
        bs_h: vals[18].to_f,
        bs_t: vals[19].to_f,
        shb: vals[20],
        shp: vals[21],
        shh: vals[22].to_f,
        sht: vals[23].to_f,
        sef: vals[24].to_f,
        seb: vals[25].to_f,
        mo: (vals[26] || 10).to_f,
        bo: (vals[27] || 5).to_f,
        af: "Да",
        as: "Да",
        ms_l: 600,
        ms_h: 30,
        ms_t: 25,
        cch: 250
      }
      params
    end

    # ============================================================================
    # РЕГИСТРАЦИЯ UI
    # ============================================================================
    
    def self.register_ui
      @menu_loaded ||= false
      unless @menu_loaded
        m = UI.menu("Plugins").add_submenu("MSV Bed Builder #{VERSION}")
        m.add_item("Построить кровать") { create_bed }
        m.add_item("Изменить размеры") { edit_bed }
        m.add_separator
        m.add_item("О плагине") {
          UI.messagebox(
            "MSV Bed Builder v#{VERSION}\n\n" +
            "Улучшения:\n" +
            "✓ Валидация параметров с понятными ошибками на русском\n" +
            "✓ Генерация карты раскроя (CSV)\n" +
            "✓ Два визуальных предпросмотра (сверху и сбоку)\n" +
            "✓ Сохранение настроек пользователя\n" +
            "✓ Загрузка компонентов уголков\n" +
            "✓ Спинка строится от пола\n" +
            "✓ Центральная царга до пола/уровня царг\n" +
            "✓ Улучшенная поддержка Undo/Redo"
          )
        }
        m.add_separator
        m.add_item("Перезагрузить плагин") { 
          load __FILE__
          loader = File.join(File.dirname(PLUGIN_PATH), "MSV_builder_loader.rb")
          load loader if File.exist?(loader)
          UI.messagebox("Плагин перезагружен!") 
        }
        @menu_loaded = true
      end
      
      @toolbar ||= UI::Toolbar.new("MSV Bed Builder #{VERSION}")
      if @toolbar.count == 0
        c1 = UI::Command.new("Создать") { create_bed }
        c1.small_icon = ICON_CREATE_SMALL_VALID if ICON_CREATE_SMALL_VALID
        c1.large_icon = ICON_CREATE_LARGE_VALID if ICON_CREATE_LARGE_VALID
        c1.tooltip = "Создать новую кровать"
        c1.status_bar_text = "Открыть конструктор кровати для создания новой модели"
        @toolbar.add_item(c1)
        
        c2 = UI::Command.new("Изменить") { edit_bed }
        c2.small_icon = ICON_EDIT_SMALL_VALID if ICON_EDIT_SMALL_VALID
        c2.large_icon = ICON_EDIT_LARGE_VALID if ICON_EDIT_LARGE_VALID
        c2.tooltip = "Изменить параметры выбранной кровати"
        c2.status_bar_text = "Изменить размеры и конфигурацию выбранной кровати"
        @toolbar.add_item(c2)
      end
      
      @toolbar.restore
    end

    register_ui
    
    unless @bed_builder_loaded
      puts "MSV BedBuilder v#{VERSION} loaded successfully"
      @bed_builder_loaded = true
    end
    end
  end
end
