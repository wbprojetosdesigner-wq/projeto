# Main functionality for DetailSimple

require 'json'
require 'csv'

module DetailSimple

  SETTINGS_FILE = File.join(File.dirname(__FILE__), 'settings.json')

  def self.load_settings
    if File.exist?(SETTINGS_FILE)
      begin
        data = File.read(SETTINGS_FILE)
        @settings = JSON.parse(data)
      rescue
        @settings = {}
      end
    else
      @settings = {}
    end
    @settings['output_dir'] ||= File.expand_path('..', File.dirname(__FILE__))
    @settings['cliente'] ||= ''
    @settings['endereco'] ||= ''
    @settings['observacoes'] ||= ''
    @settings
  end

  def self.save_settings
    begin
      File.open(SETTINGS_FILE, 'w') do |f|
        f.write(JSON.pretty_generate(@settings))
      end
      true
    rescue => e
      UI.messagebox("Erro ao salvar settings: #{e}")
      false
    end
  end

  def self.open_config
    load_settings
    prompts = ['Nome do cliente', 'Endereço', 'Observações (linha única)', 'Pasta de saída (CSV/PNG)']
    defaults = [@settings['cliente'], @settings['endereco'], @settings['observacoes'], @settings['output_dir']]
    input = UI.inputbox(prompts, defaults, 'Configurações - DetailSimple')
    if input
      @settings['cliente'] = input[0]
      @settings['endereco'] = input[1]
      @settings['observacoes'] = input[2]
      @settings['output_dir'] = input[3]
      save_settings
      UI.messagebox("Configurações salvas.")
    end
  end

  def self.export_csvs
    load_settings
    model = Sketchup.active_model
    unless model
      UI.messagebox('Abra um modelo antes de gerar as listas.')
      return
    end
    output = @settings['output_dir'] || File.expand_path('..', File.dirname(__FILE__))
    Dir.mkdir(output) unless File.exist?(output)

    # Materiais (MDF)
    mats = model.materials.to_a
    CSV.open(File.join(output, 'materiais.csv'), 'wb') do |csv|
      csv << ['COD', 'DESCRICAO_DE_MATERIAIS']
      mats.each_with_index do |m, i|
        code = "MDF%03d" % (i+1)
        csv << [code, m.display_name || m.name]
      end
    end

    # Varre entidades em busca de atributos Dinabox (ELETRO / ACESSORIO)
    eletros = []
    acessorios = []
    model.entities.each do |ent|
      next unless ent.attribute_dictionaries
      ent.attribute_dictionaries.each do |name, dict|
        # procura chaves padrao: DS_TYPE, DS_CODE, DS_DESC
        type = dict['DS_TYPE'] || dict['TYPE'] || dict['ds_type']
        code = dict['DS_CODE'] || dict['CODE'] || dict['ds_code']
        desc = dict['DS_DESC'] || dict['DESC'] || dict['ds_desc']
        if type
          entry = {
            'code' => code || '',
            'desc' => desc || ent.name || ent.typename,
            'model' => dict['DS_MODEL'] || dict['MODEL'] || dict['ds_model'] || '',
            'measure' => dict['DS_MEASURE'] || dict['MEASURE'] || dict['ds_measure'] || '',
            'color' => dict['DS_COLOR'] || dict['COLOR'] || dict['ds_color'] || '',
            'qty' => dict['DS_QTD'] || dict['QTD'] || dict['QTY'] || dict['ds_qtd'] || ''
          }
          if type.to_s.upcase.include?('ELET')
            eletros << entry
          elsif type.to_s.upcase.include?('ACESS') || type.to_s.upcase.include?('ACESSORIO')
            acessorios << entry
          end
        end
      end
    end

    CSV.open(File.join(output, 'eletros.csv'), 'wb') do |csv|
      csv << ['COD', 'DESCRICAO_DE_ELETROS_E_EQUIPAMENTOS']
      eletros.each do |e|
        csv << [e['code'], e['desc']]
      end
    end

    # Agregar acessórios por código/modelo/medida/cor e somar QTD (autopreenchimento)
    aggregated = {}
    acessorios.each do |a|
      key = [a['code'].to_s, a['desc'].to_s, a['model'].to_s, a['measure'].to_s, a['color'].to_s].join('||')
      qty_str = a['qty'].to_s.strip
      qty_i = qty_str == '' ? 1 : (qty_str.to_i > 0 ? qty_str.to_i : 1)
      if aggregated[key]
        aggregated[key]['qty'] = aggregated[key]['qty'].to_i + qty_i
      else
        aggregated[key] = a.dup
        aggregated[key]['qty'] = qty_i
      end
    end

    CSV.open(File.join(output, 'acessorios.csv'), 'wb') do |csv|
      csv << ['COD', 'ACESSORIOS', 'MODELO', 'MEDIDA', 'COR', 'QTD']
      aggregated.each_value do |a|
        csv << [a['code'], a['desc'], a['model'], a['measure'], a['color'], a['qty']]
      end
    end

    UI.messagebox("CSVs gerados em: #{output}")
  end

  def self.export_layout_png
    load_settings
    model = Sketchup.active_model
    unless model
      UI.messagebox('Abra um modelo antes de exportar o layout.')
      return
    end
    view = model.active_view
    output = @settings['output_dir'] || File.expand_path('..', File.dirname(__FILE__))
    Dir.mkdir(output) unless File.exist?(output)
    path = File.join(output, 'layout.png')
    begin
      # width, height, transparent
      view.write_image(path, 1920, 1080, false)
      UI.messagebox("Exportado PNG em: #{path}")
    rescue => e
      UI.messagebox("Erro ao exportar PNG: #{e}")
    end
  end

  unless @loaded
    load_settings
    begin
      menu = UI.menu('Extensions')
    rescue
      menu = UI.menu('Plugins')
    end
    submenu = menu.add_submenu('DetailSimple')
    submenu.add_item('Configurações') { open_config }
    submenu.add_item('Gerar Listas CSV') { export_csvs }
    submenu.add_item('Exportar Layout PNG') { export_layout_png }
    @loaded = true
  end

end
