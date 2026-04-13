# Como: Adicionar Nova Tool ao Agente Salematic
> Projeto: Salematic | Ultima execução: 2026-04-13

## Pré-requisitos (checklist)

- [ ] Salematic rodando localmente (`dotnet run` em `Salematic.API`)
- [ ] Entender o fluxo: LLM → `AgentToolsService.ExecutarAsync` → repositório/serviço → retorno JSON
- [ ] Decidir: a tool precisa de dados do banco? De API externa? De Service Bus?

---

## Visão geral do fluxo

```
Usuário envia mensagem
    │
    ▼
ChatService.ProcessarAsync
    │
    ├── DefinirFerramentas() ← declara tools para a LLM
    │
    ▼
ILlmClient.EnviarAsync (Gemini ou Claude)
    │
    ▼  (LLM decide chamar uma tool)
AgentToolsService.ExecutarAsync(nomeFerramenta, argumentos)
    │
    ▼  (switch por nome)
XxxAsync(argumentos) ← sua implementação aqui
    │
    ▼
Retorno JSON serializado → LLM gera resposta final
```

---

## Passos

### 1. Implementar o método privado — AgentToolsService.cs

Arquivo: `T:\developer\salematic\Salematic.Application\Services\AgentToolsService.cs`

```csharp
private async Task<string> ConsultarPrazoEntregaAsync(Dictionary<string, JsonElement> args)
{
    var cep = GetArg(args, "cep").Replace("-", "").Replace(".", "").Trim();

    if (string.IsNullOrWhiteSpace(cep) || cep.Length != 8)
        return JsonSerializer.Serialize(new { erro = "CEP inválido." });

    // lógica real aqui: consultar tabela, API externa, etc.
    var prazo = await _entregas.ConsultarPrazoAsync(cep);

    return JsonSerializer.Serialize(new
    {
        cep,
        prazo_dias = prazo.Dias,
        mensagem = $"Entrega em até {prazo.Dias} dias úteis para o CEP {cep}."
    });
}
```

**Regras:**
- Sempre retornar `string` com JSON serializado via `JsonSerializer.Serialize(...)`
- Em caso de erro: `JsonSerializer.Serialize(new { erro = "mensagem" })`
- Usar `GetArg(args, "nome_parametro")` para strings — trata camelCase e snake_case automaticamente
- Usar `GetArgElement(args, "nome_parametro")` para arrays e tipos compostos

### 2. Registrar no switch — ExecutarAsync

```csharp
// AgentToolsService.cs — método ExecutarAsync
public async Task<string> ExecutarAsync(string nomeFerramenta, Dictionary<string, JsonElement> argumentos)
{
    return nomeFerramenta switch
    {
        "consultar_estoque"       => await ConsultarEstoqueAsync(argumentos),
        "registrar_pedido"        => await RegistrarPedidoAsync(argumentos),
        // ... tools existentes ...
        "consultar_prazo_entrega" => await ConsultarPrazoEntregaAsync(argumentos), // ← adicionar aqui
        _ => JsonSerializer.Serialize(new { erro = $"Ferramenta desconhecida: {nomeFerramenta}" })
    };
}
```

### 3. Declarar a tool para a LLM — ChatService.cs

Arquivo: `T:\developer\salematic\Salematic.Application\Services\ChatService.cs`

Adicionar dentro de `DefinirFerramentas()`:

```csharp
new()
{
    Nome = "consultar_prazo_entrega",
    Descricao = "Consulta o prazo estimado de entrega para um CEP. Use quando o cliente perguntar sobre entrega ou frete.",
    Parametros = new Dictionary<string, object>
    {
        ["type"] = "object",
        ["properties"] = new Dictionary<string, object>
        {
            ["cep"] = new Dictionary<string, object>
            {
                ["type"] = "string",
                ["description"] = "CEP de destino (8 dígitos, com ou sem hífen)"
            }
        }
    },
    Obrigatorios = ["cep"]
},
```

**Dica na descrição:** Explique *quando* a LLM deve usar a tool (ex: "Use quando o cliente perguntar sobre..."). Isso guia o model a acionar no momento certo.

### 4. Injetar dependência (se a tool usa novo serviço/repositório)

Se a tool usa uma dependência nova (ex: `IEntregaRepository`):

**4a.** Adicionar campo e parâmetro no construtor de `AgentToolsService`:

```csharp
// AgentToolsService.cs
private readonly IEntregaRepository _entregas;

public AgentToolsService(
    IProdutoRepository produtos,
    IPedidoRepository pedidos,
    IClienteRepository clientes,
    IPagamentoService pagamento,
    IEntregaRepository entregas,  // ← novo
    bool isDevelopment,
    string devRequestsPath)
{
    // ...
    _entregas = entregas;
}
```

**4b.** Registrar no `Program.cs` do `Salematic.API`:

```csharp
// Salematic.API/Program.cs
builder.Services.AddScoped<IEntregaRepository, EntregaRepository>();
```

**4c.** Atualizar a instanciação de `AgentToolsService` em `Program.cs`:

```csharp
var agentTools = new AgentToolsService(
    app.Services.GetRequiredService<IProdutoRepository>(),
    app.Services.GetRequiredService<IPedidoRepository>(),
    app.Services.GetRequiredService<IClienteRepository>(),
    app.Services.GetRequiredService<IPagamentoService>(),
    app.Services.GetRequiredService<IEntregaRepository>(), // ← novo
    app.Environment.IsDevelopment(),
    devRequestsPath
);
```

---

## Checklist de conclusão

- [ ] Método `XxxAsync` implementado em `AgentToolsService.cs`
- [ ] Case adicionado no switch `ExecutarAsync`
- [ ] Tool declarada em `ChatService.DefinirFerramentas()`
- [ ] Se nova dependência: interface criada em `Salematic.Domain/Interfaces/`
- [ ] Se nova dependência: implementação em `Salematic.Infrastructure/Repositories/`
- [ ] Se nova dependência: registrada em `Program.cs` e passada no construtor
- [ ] Build sem erros: `dotnet build Salematic.sln`
- [ ] Teste manual: enviar mensagem que aciona a tool via chat

---

## Erros comuns

| Erro | Causa | Fix |
|---|---|---|
| `Ferramenta desconhecida: xyz` | Nome no switch diferente do declarado em `DefinirFerramentas()` | Garantir que o `Nome` da `LlmFerramenta` é idêntico ao case no switch |
| LLM nunca chama a tool | Descrição vaga ou sem gatilho explícito | Adicionar "Use quando..." na `Descricao` |
| Parâmetro sempre vazio | LLM envia camelCase, código espera snake_case | Usar `GetArg()` — já trata os dois formatos |
| `NullReferenceException` no construtor | Nova dependência não passada na instanciação | Atualizar `new AgentToolsService(...)` em `Program.cs` |
| Tool funciona em dev mas não em prod | `_isDevelopment` guard | Verificar se a tool tem `if (!_isDevelopment) return ...` desnecessário |

---

## Tools existentes (referência rápida)

| Tool | O que faz |
|---|---|
| `consultar_estoque` | Busca produtos por nome (aceita array de termos) |
| `registrar_pedido` | Cria pedido para cliente com lista de itens |
| `consultar_pedidos` | Lista pedidos de um cliente por ID |
| `cancelar_pedido` | Cancela pedido por ID |
| `cadastrar_cliente` | Cria cliente (nome + documento obrigatórios) |
| `consultar_cliente` | Retorna dados completos do cliente |
| `atualizar_cliente` | Atualiza campos cadastrais (só os informados) |
| `atualizar_endereco` | Atualiza endereço consultando ViaCEP |
| `gerar_cobranca` | Processa pagamento via Asaas (PIX/Boleto/Cartão) |
| `solicitar_desenvolvimento` | Grava dev-request em `T:\devautomation\dev-requests\` |

---

## Ver também

- [shared-pattern-saga.md](../shared/shared-pattern-saga.md) — se a tool publicar eventos Service Bus
- [shared-ref-linq-csharp.md](../shared/shared-ref-linq-csharp.md) — queries LINQ nas implementações
