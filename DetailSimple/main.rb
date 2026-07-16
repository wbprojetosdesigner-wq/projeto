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
    submenu.add_item('Gerar Cotação') { generate_quote }
    submenu.add_item('Gerar Detalhamento') { create_detail_scenes }
    @loaded = true
  end

end

# ---------- Geração automática de cenas de detalhamento (DS_*) ----------
def create_scene_with_camera(name, camera)
  model = Sketchup.active_model
  pages = model.pages
  page = pages.add(name)
  page.camera = camera
  page
end

def create_detail_scenes
  load_settings
  model = Sketchup.active_model
  unless model
    UI.messagebox('Abra um modelo antes de gerar o detalhamento.')
    return
  end

  output = @settings['output_dir'] || File.expand_path('..', File.dirname(__FILE__))
  Dir.mkdir(output) unless File.exist?(output)

  # esconder portas
  doors = find_by_type_keyword(['porta','door','DOOR'])
  original = hide_doors_temporarily(doors)

  begin
    # Planta baixa (top orthographic)
    view = model.active_view
    center = model.bounds.center
    cam_top = Sketchup::Camera.new([center.x, center.y, center.z + model.bounds.height * 3], center, [0,0,1])
    cam_top.perspective = false
    page_top = create_scene_with_camera('DS_PLANTA', cam_top)

    # Vistas frontais por paredes detectadas
    walls = find_by_type_keyword(['parede','wall','WALL'])
    if walls.empty?
      # criar 4 vistas ortográficas (N,E,S,W)
      b = model.bounds
      centers = [
        [b.center.x + b.width/2.0, b.center.y, b.center.z],
        [b.center.x - b.width/2.0, b.center.y, b.center.z],
        [b.center.x, b.center.y + b.depth/2.0, b.center.z],
        [b.center.x, b.center.y - b.depth/2.0, b.center.z]
      ]
      i = 1
      centers.each do |c|
        eye = [c[0], c[1], c[2] + model.bounds.height]
        cam = Sketchup::Camera.new(eye, [b.center.x, b.center.y, b.center.z], [0,0,1])
        cam.perspective = false
        create_scene_with_camera("DS_VISTA_#{i}", cam)
        i += 1
      end
    else
      walls.each_with_index do |w, idx|
        c = w.bounds.center
        dir = Geom::Vector3d.new(c.x - model.bounds.center.x, c.y - model.bounds.center.y, 0)
        dir.length = 1 rescue nil
        eye = dir ? [c.x + dir.x * model.bounds.width, c.y + dir.y * model.bounds.depth, c.z + model.bounds.height] : [c.x, c.y, c.z + model.bounds.height]
        cam = Sketchup::Camera.new(eye, c, [0,0,1])
        cam.perspective = false
        create_scene_with_camera("DS_VISTA_#{idx+1}", cam)
      end
    end

    # Cenas auxiliares: materiais, acessórios e cotação
    # materiais: foco no material list
    cam_mat = Sketchup::Camera.new([center.x, center.y, center.z + model.bounds.height*2], center, [0,0,1])
    cam_mat.perspective = false
    create_scene_with_camera('DS_MATERIAIS', cam_mat)

    cam_acc = Sketchup::Camera.new([center.x, center.y, center.z + model.bounds.height*2], center, [0,0,1])
    cam_acc.perspective = false
    create_scene_with_camera('DS_ACESSORIOS', cam_acc)

    # gerar miniaturas PNG das cenas (opcional)
    pages = model.pages
    pages.each do |p|
      next unless p.name.start_with?('DS_')
      p.restore_view
      sleep(0.2)
      view = model.active_view
      img_path = File.join(output, "#{p.name}.png")
      view.write_image(img_path, 1600, 1200, false)
    end

  ensure
    restore_doors_layers(doors, original)
  end

  UI.messagebox("Cenas DS geradas e miniaturas salvas em: #{output}")
end

# ---------- Funções de geração de pranchas (planta baixa e vistas frontais) ----------
def find_by_type_keyword(keywords)
  model = Sketchup.active_model
  return [] unless model
  found = []
  model.entities.each do |ent|
    next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
    name = (ent.definition && ent.definition.name) || ent.name || ''
    # atributos
    has_attr = false
    if ent.attribute_dictionaries
      ent.attribute_dictionaries.each do |n, dict|
        val = dict['DS_TYPE'] || dict['TYPE'] || dict['ds_type']
        if val && keywords.any? { |k| val.to_s.upcase.include?(k.upcase) }
          has_attr = true
          break
        end
      end
    end
    if has_attr || keywords.any? { |k| name.to_s.downcase.include?(k.downcase) }
      found << ent
    end
  end
  found
end

def hide_doors_temporarily(doors)
  return {} if doors.empty?
  model = Sketchup.active_model
  ds_layer = model.layers.add('DS_TEMP_DOORS') rescue model.layers.add('DS_TEMP_DOORS')
  ds_layer.visible = false
  original = {}
  doors.each do |d|
    begin
      original[d.persistent_id] = d.layer.name if d.respond_to?(:layer) && d.layer
      d.layer = ds_layer if d.respond_to?(:layer=)
    rescue
      next
    end
  end
  original
end

def restore_doors_layers(doors, original)
  return if doors.empty?
  model = Sketchup.active_model
  doors.each do |d|
    begin
      if original[d.persistent_id]
        layer_name = original[d.persistent_id]
        layer = model.layers[layer_name] || model.layers.add(layer_name)
        d.layer = layer if d.respond_to?(:layer=)
      end
    rescue
      next
    end
  end
  # remove temp layer if exists
  if model.layers['DS_TEMP_DOORS']
    begin
      model.layers.remove(model.layers['DS_TEMP_DOORS'])
    rescue
    end
  end
end

def export_top_view(output_dir, scale_label)
  model = Sketchup.active_model
  view = model.active_view
  center = model.bounds.center
  cam = Sketchup::Camera.new([center.x, center.y, center.z + model.bounds.height * 3], center, [0,0,1])
  cam.perspective = false
  view.camera = cam
  view.zoom_extents
  path = File.join(output_dir, "planta_baixa_#{scale_label}.png")
  view.write_image(path, 3000, 2000, false)
  path
end

def export_front_views(output_dir, scale_label)
  model = Sketchup.active_model
  view = model.active_view
  walls = find_by_type_keyword(['parede','wall','WALL'])
  exported = []
  if walls.empty?
    # fallback: use bounding box sides (generate 4 facings)
    b = model.bounds
    centers = [
      [b.center.x + b.width/2.0, b.center.y, b.center.z],
      [b.center.x - b.width/2.0, b.center.y, b.center.z],
      [b.center.x, b.center.y + b.depth/2.0, b.center.z],
      [b.center.x, b.center.y - b.depth/2.0, b.center.z]
    ]
    i = 1
    centers.each do |c|
      cam = Sketchup::Camera.new([c[0], c[1], c[2]+model.bounds.height], [b.center.x, b.center.y, b.center.z], [0,0,1])
      cam.perspective = false
      view.camera = cam
      view.zoom_extents
      path = File.join(output_dir, "vista_frontal_#{i}_#{scale_label}.png")
      view.write_image(path, 1600, 1200, false)
      exported << path
      i += 1
    end
  else
    walls.each_with_index do |w, idx|
      c = w.bounds.center
      # approximate normal: vector from model center to wall center
      dir = Geom::Vector3d.new(c.x - model.bounds.center.x, c.y - model.bounds.center.y, 0)
      dir.length = 1
      eye = [c.x + dir.x * (model.bounds.width), c.y + dir.y * (model.bounds.depth), c.z + model.bounds.height]
      cam = Sketchup::Camera.new(eye, c, [0,0,1])
      cam.perspective = false
      view.camera = cam
      view.zoom_extents
      path = File.join(output_dir, "vista_frontal_#{idx+1}_#{scale_label}.png")
      view.write_image(path, 1600, 1200, false)
      exported << path
    end
  end
  exported
end

def generate_sheets(scale = '1_20')
  load_settings
  model = Sketchup.active_model
  output = @settings['output_dir'] || File.expand_path('..', File.dirname(__FILE__))
  # find doors and hide
  doors = find_by_type_keyword(['porta','door','DOOR'])
  original = hide_doors_temporarily(doors)
  begin
    top = export_top_view(output, scale)
    fronts = export_front_views(output, scale)
  ensure
    restore_doors_layers(doors, original)
  end
  UI.messagebox("Pranchas geradas:\n#{top}\n#{fronts.join('\n')}")
end

# ---------- Barra de ferramentas ----------
def create_toolbar
  toolbar = UI::Toolbar.new 'DetailSimple'

  cmd_sheets = UI::Command.new('Gerar Pranchas') { generate_sheets('1_20') }
  cmd_sheets.small_icon = File.join(File.dirname(__FILE__), 'icons', 'sheets_small.png') rescue nil
  cmd_sheets.large_icon = File.join(File.dirname(__FILE__), 'icons', 'sheets_large.png') rescue nil
  cmd_sheets.tooltip = 'Gerar pranchas: planta baixa e vistas frontais (1:20)'
  toolbar.add_item cmd_sheets

  cmd_csv = UI::Command.new('Gerar Listas CSV') { export_csvs }
  cmd_csv.tooltip = 'Gerar listas CSV (Materiais, Eletros, Acessorios)'
  toolbar.add_item cmd_csv

  cmd_quote = UI::Command.new('Gerar Cotação') { generate_quote }
  cmd_quote.tooltip = 'Gerar cotação a partir das listas'
  toolbar.add_item cmd_quote

  toolbar.show
end

create_toolbar

def load_prices_file
  prices_file = File.join(File.dirname(__FILE__), 'prices.json')
  if File.exist?(prices_file)
    begin
      data = File.read(prices_file)
      return JSON.parse(data)
    rescue => e
      UI.messagebox("Erro ao ler prices.json: #{e}")
      return {}
    end
  end
  {}
end

def parse_csv_rows(path)
  rows = []
  return rows unless File.exist?(path)
  CSV.foreach(path, headers: true) do |r|
    rows << r.to_hash
  end
  rows
end

def generate_quote
  load_settings
  prices = load_prices_file
  prompts = ['Margem de lucro (%)', 'Impostos (%)', 'Valor hora mão de obra', 'Horas de mão de obra', 'Moeda']
  defaults = ['20', '12', '50', '8', 'BRL']
  input = UI.inputbox(prompts, defaults, 'Parâmetros de cotação - DetailSimple')
  return unless input
  margem = input[0].to_f
  impostos = input[1].to_f
  valor_hora = input[2].to_f
  horas = input[3].to_f
  moeda = input[4]

  output = @settings['output_dir'] || File.expand_path('..', File.dirname(__FILE__))
  materiais_csv = File.join(output, 'materiais.csv')
  eletros_csv = File.join(output, 'eletros.csv')
  acessorios_csv = File.join(output, 'acessorios.csv')

  materiais = parse_csv_rows(materiais_csv)
  eletros = parse_csv_rows(eletros_csv)
  acessorios = parse_csv_rows(acessorios_csv)

  unless materiais.any? || eletros.any? || acessorios.any?
    UI.messagebox('Nenhum CSV encontrado em Pasta de saída. Gere as listas antes de cotar.')
    return
  end

  lines = []
  subtotal = 0.0

  materiais.each do |m|
    code = (m['COD'] || m['Code'] || m['cod'] || '').strip
    desc = (m['DESCRICAO_DE_MATERIAIS'] || m['DESCRICAO'] || m['DESCRICAO_DE_MATERIAIS'] || m.values[1]).to_s
    unit = prices[code] || prices[desc] || 0.0
    qty = (m['QTD'] || m['QTY'] || '1').to_f
    line = unit * qty
    lines << ['Material', code, desc, unit, qty, line]
    subtotal += line
  end

  eletros.each do |e|
    code = (e['COD'] || e['Code'] || '').strip
    desc = (e['DESCRICAO_DE_ELETROS_E_EQUIPAMENTOS'] || e['DESCRICAO'] || e.values[1]).to_s
    unit = prices[code] || prices[desc] || 0.0
    qty = (e['QTD'] || e['QTY'] || '1').to_f
    line = unit * qty
    lines << ['Eletro', code, desc, unit, qty, line]
    subtotal += line
  end

  acessorios.each do |a|
    code = (a['COD'] || '').strip
    desc = (a['ACESSORIOS'] || a['ACESSORIO'] || a['ACESSORIOS'] || a.values[1]).to_s
    unit = prices[code] || prices[desc] || 0.0
    qty = (a['QTD'] || a['QTY'] || '1').to_f
    line = unit * qty
    lines << ['Acessório', code, desc, unit, qty, line]
    subtotal += line
  end

  custo_mao_obra = valor_hora * horas
  subtotal += custo_mao_obra

  total_com_margem = subtotal * (1 + margem/100.0)
  total_com_impostos = total_com_margem * (1 + impostos/100.0)

  proposal_csv = File.join(output, 'proposta_items.csv')
  CSV.open(proposal_csv, 'wb') do |csv|
    csv << ['Categoria', 'COD', 'Descricao', 'PrecoUnitario', 'Qtde', 'TotalLinha']
    lines.each do |l|
      csv << l
    end
    csv << []
    csv << ['Mao de Obra', '', '', valor_hora, horas, custo_mao_obra]
    csv << []
    csv << ['Subtotal', '', '', '', '', subtotal]
    csv << ['Total com margem ('+margem.to_s+'%)', '', '', '', '', total_com_margem]
    csv << ['Total com impostos ('+impostos.to_s+'%)', '', '', '', '', total_com_impostos]
  end

  summary = File.join(output, 'proposta_resumo.txt')
  File.open(summary, 'w') do |f|
    f.puts "Proposta gerada: #{Time.now}"
    f.puts "Cliente: #{@settings['cliente']}"
    f.puts "Moeda: #{moeda}"
    f.puts "Subtotal: #{'%.2f' % subtotal}"
    f.puts "Mão de obra: #{'%.2f' % custo_mao_obra} (#{horas} h @ #{valor_hora})"
    f.puts "Total com margem: #{'%.2f' % total_com_margem}"
    f.puts "Total com impostos: #{'%.2f' % total_com_impostos}"
    f.puts "Arquivos: #{proposal_csv}, #{summary}"
  end

  UI.messagebox("Cotação gerada em: #{output}\nArquivo de itens: proposta_items.csv\nResumo: proposta_resumo.txt")
end
