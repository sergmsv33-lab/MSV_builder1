# encoding: UTF-8
# Загрузчик плагина MSV Bed Builder для SketchUp

require 'sketchup.rb'
require 'extensions.rb'

module MSV
  module BedBuilder
    unless file_loaded?(__FILE__)
      extension_file = File.join('MSV_builder', 'main')
      version_file = File.join(
        File.dirname(__FILE__),
        'MSV_builder',
        'core',
        'MSV_bed_builder_enhanced.rb'
      )

      version = '2.0.3'
      if File.exist?(version_file)
        source = File.read(version_file, encoding: 'UTF-8')
        version = source[/VERSION\s*=\s*["']([^"']+)["']/, 1] || version
      end

      extension = SketchupExtension.new('MSV Bed Builder', extension_file)
      extension.description = 'Конструктор кроватей из МДФ с настройкой параметров.'
      extension.version     = version
      extension.creator     = 'MSV'

      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
