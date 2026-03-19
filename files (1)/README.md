# DevAutomation — Guia de Instalação e Uso

## Estrutura de Pastas

Crie a seguinte estrutura em `C:\DevAutomation\`:

```
C:\DevAutomation\
├── config\
│   └── environments.json          ← configuração central (caminhos, tipos)
├── scripts\
│   ├── Switch-Environment.ps1     ← script principal
│   └── Apply-Configs.ps1          ← funções auxiliares
├── batches\
│   ├── go-developer.bat           ← atalho: vai para developer completo
│   ├── go-homolog.bat             ← atalho: vai para homolog completo
│   ├── go-master.bat              ← atalho: vai para master completo
│   └── reload-config-only.bat     ← só reaplica configs, sem git/VS
└── templates\
    ├── API1\
    │   ├── developer.json
    │   ├── homolog.json
    │   └── master.json
    ├── API2\
    │   ├── developer.json
    │   ├── homolog.json
    │   └── master.json
    ├── API3_REST\
    │   ├── developer.xml
    │   ├── homolog.xml
    │   └── master.xml
    └── API3_SOAP\
        ├── developer.xml
        ├── homolog.xml
        └── master.xml
```

---

## Passo a Passo de Configuração

### 1. Copiar os arquivos

Copie os arquivos para `C:\DevAutomation\` respeitando a estrutura acima.

### 2. Editar `config\environments.json`

Substitua todos os `<PLACEHOLDERS>` pelos valores reais:

| Placeholder            | O que colocar                                                 |
|------------------------|---------------------------------------------------------------|
| `<CAMINHO_API1>`       | Caminho da pasta raiz da API1 (sem a letra do drive `C:\\`)   |
| `<CAMINHO_API2>`       | Caminho da pasta raiz da API2                                 |
| `<CAMINHO_API3>`       | Caminho da pasta raiz da solution com REST+SOAP               |
| `<NOME_PROJETO_REST>`  | Nome da subpasta do projeto REST dentro da solution           |
| `<NOME_PROJETO_SOAP>`  | Nome da subpasta do projeto SOAP dentro da solution           |

Ajuste também o campo `"batchOpen"` de cada API para apontar para os `.bat`
que você já usa para abrir as solutions no VS.

### 3. Preencher os templates

#### Para APIs com `appsettings.json` (API1, API2):

1. Abra o `appsettings.json` atual de cada API
2. Identifique as chaves que mudam entre developer / homolog / master
3. Copie **apenas essas chaves** para o template correspondente (`developer.json`, `homolog.json`, `master.json`)
4. Preencha os valores corretos de cada ambiente

**Importante:** os templates JSON não precisam ter todas as chaves — só as que mudam.
O script faz deep merge e preserva o restante do arquivo original.

**Remova os blocos de comentário `//` dos templates JSON antes de usar**
(JSON não suporta comentários — estão lá só como guia inicial).

#### Para APIs com `Web.config` (API3_REST, API3_SOAP):

1. Abra o `Web.config` atual de cada projeto
2. Copie as entradas de `<appSettings>` e `<connectionStrings>` que mudam
3. Cole nos templates XML correspondentes, trocando os `<PLACEHOLDERS>` pelos valores reais

O script substitui **apenas as chaves listadas no template** — o resto do Web.config fica intacto.

### 4. Testar sem risco

Antes de usar com `-GitPull` e `-OpenVisualStudio`, teste só a parte de configs:

```bat
:: No PowerShell, para ver o que acontece sem commitar nada no git nem abrir VS:
powershell -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" -Environment developer
```

Verifique se os arquivos `.config` e `appsettings.json` foram atualizados corretamente.

### 5. Habilitar execução de scripts PowerShell (se necessário)

Se o Windows bloquear a execução do `.ps1`, execute uma vez como Administrador:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Uso no Dia a Dia

### Troca completa de ambiente (fechar VS → git → configs → abrir VS):

| Situação                           | Arquivo a executar      |
|------------------------------------|-------------------------|
| Iniciar o dia em developer         | `go-developer.bat`      |
| Atender chamado / testar em homolog| `go-homolog.bat`        |
| Validar em master                  | `go-master.bat`         |
| Só reaplicar configs (sem git/VS)  | `reload-config-only.bat`|

Coloque os `.bat` de atalho direto na área de trabalho para acesso rápido.

### Troca sem fechar o VS (só git + config, sem reabrir):

```bat
powershell -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment homolog -GitPull
```

### Forçar troca ignorando alterações não commitadas:

```bat
powershell -ExecutionPolicy Bypass -File "C:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment homolog -CloseVisualStudio -GitPull -OpenVisualStudio -Force
```

---

## Parâmetros do Switch-Environment.ps1

| Parâmetro            | Obrigatório | Descrição                                              |
|----------------------|-------------|--------------------------------------------------------|
| `-Environment`       | Sim         | `developer`, `homolog` ou `master`                     |
| `-CloseVisualStudio` | Não         | Fecha as instâncias do VS antes de trocar              |
| `-GitPull`           | Não         | Faz `git checkout <branch>` + `git pull` em cada repo |
| `-OpenVisualStudio`  | Não         | Abre as solutions via `.bat` ao final                  |
| `-Force`             | Não         | Ignora alterações não commitadas no git                |

---

## Solução de Problemas

**Script não executa (erro de ExecutionPolicy):**
Execute como Administrador: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**"Template não encontrado":**
Verifique se o campo `"name"` no `environments.json` é idêntico ao nome da pasta em `\templates\`.
Ex: `"name": "API3_REST"` exige que exista a pasta `templates\API3_REST\`.

**"Repositório não encontrado":**
Verifique o campo `"gitRepo"` no `environments.json`. Use barras duplas: `C:\\Projects\\MinhaAPI`.

**VS não fecha / fecha com prompt de salvamento:**
Comportamento esperado — o VS pergunta sobre arquivos não salvos.
Salve ou descarte e o script continua. Para fechar sem perguntar, altere
`$proc.CloseMainWindow()` para `$proc.Kill()` em `Apply-Configs.ps1`.

**JSON inválido no template:**
Remova os blocos de comentário `//` dos templates `.json` — JSON puro não aceita comentários.
