# DevAutomation

Ferramenta de automação de ambiente de desenvolvimento para Windows 11, construída com PowerShell e uma interface web local chamada **DevPanel**.

Criada para resolver um problema real: gerenciar múltiplas solutions, APIs encadeadas e branches Git em ambientes de desenvolvimento complexos — sem depender de cliques manuais repetitivos.

---

## O problema que resolve

Ambientes de desenvolvimento com múltiplas solutions interdependentes exigem uma sequência repetitiva de ações a cada troca de contexto: trocar branch em vários repositórios, garantir que as APIs estão rodando na ordem certa, verificar se há divergência com o remoto.

DevAutomation automatiza esse fluxo e centraliza tudo em um painel local acessível pelo browser.

---

## Funcionalidades

### DevPanel — interface web local
- Painel HTML servido localmente via PowerShell
- Controle visual de múltiplos repositórios e solutions
- Acesso rápido às operações mais comuns do dia a dia

### Gerenciamento Git
- Indicadores de ahead/behind por repositório
- Visualização de diff
- Commit por repositório individual
- Listagem de branches locais com checkout

### Automação de ambiente
- Troca de branch coordenada entre múltiplos repositórios
- Controle de inicialização de solutions e APIs encadeadas
- Detecção e resolução de conflitos de porta
- Templates de configuração por projeto

### Integração com Visual Studio 2022
- Abertura programática de solutions
- Suporte a múltiplas instâncias via virtual desktops

---

## Stack

| Camada | Tecnologia |
|---|---|
| Automação | PowerShell 5.1 / 7 |
| Interface | HTML + JavaScript (DevPanel) |
| Integração VS | COM / EnvDTE (Windows PowerShell 5.1) |
| Configuração | JSON por projeto |
| Scripts auxiliares | Batchfile |

> **Nota:** Algumas integrações com o Visual Studio 2022 requerem Windows PowerShell 5.1 por incompatibilidade do EnvDTE com PowerShell 7.

---

## Estrutura

```
DevAutomation/
├── batches/        # Scripts batch auxiliares
├── config/         # Configurações por projeto/ambiente
├── panel/          # DevPanel — interface web local
├── scripts/        # Scripts PowerShell principais
├── templates/      # Templates de projeto (ex: API1)
└── tools/          # Utilitários de suporte
```

---

## Como usar

1. Clone o repositório
2. Configure seus repositórios e solutions em `/config`
3. Execute o script principal via PowerShell
4. Acesse o DevPanel no browser (`localhost:<porta>`)

---

## Roadmap

- [ ] Criação de branches via DevPanel
- [ ] Launch de sessão de debug no VS 2022 via COM/EnvDTE
- [ ] Listagem completa de branches locais com checkout visual

---

## Contexto

Desenvolvido para uso pessoal em um ambiente com múltiplas solutions C# / .NET organizadas em virtual desktops, com APIs encadeadas que precisam subir em ordem. A ferramenta elimina o overhead manual de coordenar esse ambiente e serve como laboratório para automação de fluxos de desenvolvimento.

---

## Licença

MIT
