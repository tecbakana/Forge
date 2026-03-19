# DevAutomation — Guia de Instalação e Uso

Ferramenta de automação para gerenciar múltiplas APIs .NET entre ambientes (developer, homolog, master). Automatiza troca de branch git, aplicação de configurações, abertura do Visual Studio em virtual desktops e oferece painel web com agente de IA integrado.

---

## Estrutura de Pastas

```
DevAutomation\
├── config\
│   ├── environments.json          ← configuração central (APIs, branches, servidores, agente IA)
│   └── state.json                 ← estado atual em tempo de execução (gerado automaticamente)
├── scripts\
│   ├── Switch-Environment.ps1     ← orquestrador principal
│   ├── Apply-Configs.ps1          ← merge de configurações (JSON/XML)
│   ├── Start-DevPanel.ps1         ← servidor HTTP do painel web
│   ├── Open-Solutions.ps1         ← abre solutions no VS com virtual desktops
│   ├── Git-Operations.ps1         ← operações git (status, commit, discard)
│   ├── Server-Operations.ps1      ← pull de configs dos servidores remotos
│   └── Invoke-GeminiAgent.ps1     ← integração com Google Gemini (agente de IA)
├── batches\
│   ├── go-developer.bat           ← troca completa para developer
│   ├── go-homolog.bat             ← troca completa para homolog
│   ├── go-master.bat              ← troca completa para master
│   ├── reload-config-only.bat     ← só reaplica configs, sem git/VS
│   ├── start-panel.bat            ← inicia o painel web (localhost:8080)
│   ├── open-taas.bat              ← abre solution TaaS no VS
│   ├── open-taxenginereforma.bat  ← abre solution TaxEngineReforma no VS
│   ├── open-taxengine.bat         ← abre solution TaxEngine no VS
│   └── open-cockpit.bat           ← abre solution Cockpit no VS
├── templates\
│   └── {NomeDaAPI}\
│       ├── developer\
│       │   ├── default.json (ou .xml)
│       │   ├── pg.json
│       │   ├── gruponos.json
│       │   └── fagron.json
│       ├── homolog\
│       │   └── default.json (ou .xml)
│       └── master\
│           └── default.json (ou .xml)
├── panel\
│   └── index.html                 ← interface web do painel
└── tools\
    └── VirtualDesktop11.exe       ← utilitário para controle de virtual desktops
```

---

## Passo a Passo de Configuração

### 1. Copiar os arquivos

Copie os arquivos para o diretório desejado respeitando a estrutura acima.

### 2. Habilitar execução de scripts PowerShell (se necessário)

Execute uma vez como Administrador:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Editar `config\environments.json`

O arquivo central de configuração define todas as APIs gerenciadas, branches, servidores remotos e a chave da IA.

#### Estrutura de uma entrada de API:

```json
{
  "apis": [
    {
      "name": "NomeDaAPI",
      "configType": "json",
      "configFile": "appsettings.json",
      "projectPath": "T:\\Developer\\Projetos\\MinhaAPI\\MinhaAPI",
      "solutionPath": "T:\\Developer\\Projetos\\MinhaAPI\\MinhaAPI.sln",
      "gitRepo": "T:\\Developer\\Projetos\\MinhaAPI",
      "batchOpen": "T:\\DevAutomation\\batches\\open-minhaapi.bat",
      "desktop": 1,
      "clients": ["default", "pg", "gruponos"]
    }
  ]
}
```

| Campo          | Descrição                                                              |
|----------------|------------------------------------------------------------------------|
| `name`         | Identificador da API — deve ser idêntico ao nome da pasta em `templates\` |
| `configType`   | `"json"` para appsettings.json, `"xml"` para Web.config               |
| `configFile`   | Nome do arquivo de config (ex: `"appsettings.json"`, `"Web.config"`)  |
| `projectPath`  | Caminho até a pasta do projeto (onde fica o arquivo de config)        |
| `solutionPath` | Caminho até o `.sln` para abrir no VS                                 |
| `gitRepo`      | Raiz do repositório git                                               |
| `batchOpen`    | Batch que abre a solution no VS (pode ser omitido)                    |
| `desktop`      | Número do virtual desktop onde a solution será aberta (1–n)           |
| `clients`      | Lista de clientes com templates específicos (sempre inclua `"default"`) |

#### Configuração de branches:

```json
{
  "branches": {
    "developer": "developer",
    "homolog": "homolog",
    "master": "master"
  }
}
```

#### Configuração do agente de IA:

```json
{
  "agent": {
    "apiKey": "SUA_CHAVE_GEMINI_AQUI",
    "model": "gemini-2.0-flash",
    "endpoint": "https://generativelanguage.googleapis.com/v1beta/models"
  }
}
```

#### Configuração de servidores remotos (opcional):

```json
{
  "servers": {
    "developer": {
      "host": "IP_DO_SERVIDOR",
      "user": "USUARIO",
      "password": "SENHA",
      "basePath": "C$\\inetpub\\wwwroot"
    }
  }
}
```

### 4. Preencher os templates

Os templates contêm **apenas as chaves que mudam** entre ambientes — o script faz merge com o arquivo original.

#### Para APIs com `appsettings.json` (configType: json):

1. Abra o `appsettings.json` atual da API
2. Identifique as chaves que mudam entre developer / homolog / master
3. Copie **apenas essas chaves** para `templates\{NomeDaAPI}\{ambiente}\default.json`
4. Para clientes específicos (pg, gruponos, fagron), crie arquivos separados com as chaves que diferem do `default`

**Exemplo** (`templates\TaaS\developer\default.json`):
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Server=dev-server;Database=TaaS_Dev;..."
  },
  "TaxEngineUrl": "http://dev-taxengine/api"
}
```

#### Para APIs com `Web.config` (configType: xml):

1. Abra o `Web.config` atual do projeto
2. Copie as entradas de `<appSettings>` e `<connectionStrings>` que mudam
3. Cole no template XML correspondente

**Exemplo** (`templates\TaxEngineRest\developer\default.xml`):
```xml
<configuration>
  <appSettings>
    <add key="ServiceUrl" value="http://dev-server/service" />
  </appSettings>
  <connectionStrings>
    <add name="DefaultConnection" connectionString="Server=dev-server;..." />
  </connectionStrings>
</configuration>
```

O script substitui **apenas as chaves listadas** no template — o restante do Web.config fica intacto.

### 5. Testar sem risco

Antes de usar com git e VS, teste só a aplicação de configs:

```bat
powershell -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Switch-Environment.ps1" -Environment developer
```

Verifique se os arquivos de configuração foram atualizados corretamente nas APIs.

---

## Uso no Dia a Dia

### Atalhos rápidos (batch files)

| Situação                            | Arquivo a executar        |
|-------------------------------------|---------------------------|
| Iniciar o dia em developer          | `go-developer.bat`        |
| Atender chamado / testar em homolog | `go-homolog.bat`          |
| Validar em master                   | `go-master.bat`           |
| Só reaplicar configs (sem git/VS)   | `reload-config-only.bat`  |
| Abrir o painel web                  | `start-panel.bat`         |

> Coloque os `.bat` de atalho direto na área de trabalho para acesso rápido.

### Via linha de comando

**Troca completa (fechar VS → git → configs → abrir VS):**
```bat
powershell -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment homolog -CloseVisualStudio -GitPull -OpenVisualStudio
```

**Forçar troca ignorando alterações não commitadas:**
```bat
powershell -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment homolog -CloseVisualStudio -GitPull -OpenVisualStudio -Force
```

**Processar apenas APIs específicas:**
```bat
powershell -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment developer -Api "TaaS,TaxEngineRest" -GitPull
```

**Trocar para cliente específico:**
```bat
powershell -ExecutionPolicy Bypass -File "T:\DevAutomation\scripts\Switch-Environment.ps1" ^
  -Environment developer -Client pg
```

---

## Parâmetros do Switch-Environment.ps1

| Parâmetro            | Obrigatório | Descrição                                              |
|----------------------|-------------|--------------------------------------------------------|
| `-Environment`       | Sim         | `developer`, `homolog` ou `master`                     |
| `-Api`               | Não         | Filtra APIs por nome separado por vírgula (ex: `"TaaS,TaxEngineRest"`) |
| `-Client`            | Não         | Template de cliente a aplicar (ex: `pg`, `gruponos`). Padrão: `default` |
| `-CloseVisualStudio` | Não         | Fecha as instâncias do VS antes de trocar              |
| `-GitPull`           | Não         | Faz `git checkout <branch>` + `git pull` em cada repo |
| `-OpenVisualStudio`  | Não         | Abre as solutions no VS ao final                       |
| `-Force`             | Não         | Ignora alterações não commitadas no git                |

---

## Painel Web

Execute `start-panel.bat` para iniciar o servidor local. Acesse em: **http://localhost:8080**

### Funcionalidades do painel

- **Status em tempo real** — ambiente atual, branch e cliente de cada API
- **Troca de ambiente** — selecione o ambiente e clique em Switch (equivale ao batch)
- **Filtro por API** — processe apenas as APIs selecionadas
- **Editor de templates** — visualize e edite os arquivos de template diretamente pelo painel
- **Operações git:**
  - Ver arquivos modificados com diff
  - Verificar se o branch está à frente/atrás do remote
  - Commit com mensagem
  - Descartar alterações
- **Pull de configs dos servidores** — busca e salva configs remotas como templates locais
- **Agente de IA** — controle a ferramenta em linguagem natural via chat (ver seção abaixo)

---

## Agente de IA (Google Gemini)

O painel inclui um chat integrado ao Google Gemini 2.0 Flash. O agente entende comandos em português e executa ações diretamente na ferramenta.

### Comandos suportados via chat

| Intenção                        | Exemplo de mensagem                        |
|---------------------------------|--------------------------------------------|
| Trocar de ambiente              | "Muda para homolog"                        |
| Trocar ambiente de uma API      | "Vai para developer só no TaaS"            |
| Ver status atual                | "Qual é o ambiente atual?"                 |
| Ver arquivos modificados        | "Tem alguma alteração no git?"             |
| Verificar sincronização         | "O branch está atualizado?"                |
| Listar branches disponíveis     | "Quais branches existem no TaxEngineRest?" |

O agente mantém histórico de conversa e usa function calling para executar as ações.

---

## Virtual Desktops

O script `Open-Solutions.ps1` usa o `VirtualDesktop11.exe` para abrir cada solution automaticamente no desktop correto. Configure o campo `"desktop"` de cada API no `environments.json`.

**Requisito:** Windows 10/11 com múltiplos virtual desktops criados previamente.

Se o `VirtualDesktop11.exe` não estiver disponível, o script abre o VS normalmente sem trocar o desktop.

---

## Pull de Configs dos Servidores Remotos

O painel web permite buscar os arquivos de configuração diretamente dos servidores (homolog, master) via UNC (`\\servidor\C$\...`) e salvá-los como templates locais.

Configure as credenciais de cada servidor na seção `"servers"` do `environments.json`.

---

## Solução de Problemas

**Script não executa (erro de ExecutionPolicy):**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"Template não encontrado":**
Verifique se o campo `"name"` no `environments.json` é idêntico ao nome da pasta em `templates\`.
Ex: `"name": "TaaS"` exige que exista `templates\TaaS\`.

**"Repositório não encontrado":**
Verifique o campo `"gitRepo"` no `environments.json`. Use barras duplas: `T:\\Developer\\Projetos\\MinhaAPI`.

**VS não fecha / fecha com prompt de salvamento:**
Comportamento esperado — o VS pergunta sobre arquivos não salvos. Salve ou descarte e o script continua.

**JSON inválido no template:**
Remova quaisquer comentários `//` dos templates `.json` — JSON puro não aceita comentários.

**Painel não abre:**
Verifique se a porta 8080 está livre. Ajuste o campo `port` no `Start-DevPanel.ps1` se necessário.

**Agente de IA não responde:**
Verifique se a `apiKey` na seção `"agent"` do `environments.json` é válida.

**Virtual desktop não troca:**
Confirme que o `VirtualDesktop11.exe` está em `tools\` e que os desktops virtuais estão criados no Windows.
