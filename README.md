# DevAutomation — Automação de Ambientes de Desenvolvimento com IA

Ferramenta para automatizar o gerenciamento de múltiplas APIs .NET entre diferentes ambientes (developer, homolog, produção), incluindo operações de configuração, git e execução — com suporte a controle via interface web e agente de IA.

## 🚀 O que este projeto resolve

Ambientes com múltiplas APIs e configurações exigem operações repetitivas e propensas a erro, como:

- troca manual de branches  
- atualização de configurações por ambiente  
- abertura de múltiplas soluções  
- sincronização com servidores  

👉 O DevAutomation automatiza esse fluxo de ponta a ponta.

## ⚙️ Principais funcionalidades

- Troca completa de ambiente (developer / homolog / master) com um comando  
- Automação de operações git (checkout, pull, status)  
- Aplicação automática de configurações (JSON e XML) por ambiente  
- Abertura automatizada de soluções no Visual Studio (com suporte a virtual desktops)  
- Painel web local para controle visual da operação  
- Integração com agente de IA para execução de comandos via linguagem natural  

## 🧠 IA integrada (diferencial)

O sistema inclui um agente baseado em LLM que permite controlar a ferramenta via linguagem natural:

**Exemplos:**
- “Muda para homolog”  
- “Tem alteração no git?”  
- “Abre só o TaaS em developer”  

👉 O agente interpreta a intenção e executa comandos reais no sistema (function calling).

## 💡 Exemplo de uso

Um único comando executa:

- troca de branch  
- pull do repositório  
- aplicação de configurações  
- abertura das soluções no Visual Studio  

## 🧱 Arquitetura

- Scripts PowerShell para orquestração  
- Templates de configuração por ambiente  
- Interface web local (painel de controle)  
- Integração com LLM (Google Gemini) via function calling  

## 🔧 Tecnologias

- PowerShell  
- .NET / C#  
- JSON / XML  
- Google Gemini (LLM)  
- Automação de ambiente Windows  

## 🖥️ Painel Web

Interface local para:

- visualizar status das APIs  
- trocar ambiente  
- executar operações git  
- editar templates  
- interagir com o agente de IA  

## 📌 Diferenciais

- Automação completa do ciclo de desenvolvimento local  
- Redução de erros manuais em configuração de ambientes  
- Uso de IA como interface operacional (não apenas assistente)  
- Integração com múltiplos repositórios e projetos simultaneamente  

## ▶️ Como executar

(Consulte a documentação detalhada no projeto para setup completo)
