# projeto

Este repositório contém um esqueleto para a extensão SketchUp `DetailSimple`.

Como gerar o arquivo .rbz (extensão SketchUp):

1. Verifique que os arquivos `DetailSimple.rb` e a pasta `DetailSimple/` estão na raiz do diretório do projeto.
2. Torne o script de empacotamento executável:

```bash
chmod +x generate_rbz.sh
```

3. Execute o script para criar `DetailSimple.rbz`:

```bash
./generate_rbz.sh
```

4. Instale o `DetailSimple.rbz` no SketchUp via `Extension Manager` > `Install Extension...`.

Observações:
- O código atual é um placeholder que adiciona o menu `DetailSimple` > `Configurações` com um `inputbox` para o nome do cliente.
- Depois de instalar, abra o SketchUp e acesse o menu `Extensions` (ou `Plugins`) para usar a extensão.
Novas funcionalidades:

- `Gerar Listas CSV`: varre o modelo e gera três arquivos CSV em `Pasta de saída` (materiais.csv, eletros.csv, acessorios.csv).
- `Gerar Listas CSV`: varre o modelo e gera três arquivos CSV em `Pasta de saída` (materiais.csv, eletros.csv, acessorios.csv).

Nota: o arquivo `acessorios.csv` agora contém as colunas: `COD`, `ACESSORIOS`, `MODELO`, `MEDIDA`, `COR`, `QTD`.
- `Exportar Layout PNG`: exporta uma imagem `layout.png` do ponto de vista ativo do SketchUp.
- `Configurações`: agora inclui campos para `Nome do cliente`, `Endereço`, `Observações` e `Pasta de saída`.

Os arquivos de configuração são salvos em `DetailSimple/settings.json` dentro da pasta da extensão.