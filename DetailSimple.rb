# DetailSimple extension loader
# Coloque este arquivo e a pasta DetailSimple no mesmo diretório antes de empacotar em .rbz

require 'sketchup.rb'
require 'extensions.rb'

module DetailSimple
  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new('DetailSimple', 'DetailSimple/main.rb')
    extension.description = 'Ferramentas de geração de listas e relatórios para projetos (v0.1)'
    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
