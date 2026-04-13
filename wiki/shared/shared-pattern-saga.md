# Padrão: SAGA Coreografada — CMSX ↔ Salematic
> Aplica-se a: CMSX (Multiplai), Salematic

## Problema que resolve

O fluxo de pedido atravessa dois sistemas independentes: o CMSX cria o pedido e precisa saber se foi confirmado ou recusado pelo Salematic (que gerencia estoque e pagamento). Sem SAGA, o CMSX ficaria aguardando resposta síncrona, acoplando os dois sistemas.

---

## Solução (diagrama ASCII)

```
CMSX (criador do pedido)
│
│  1. Cria pedido localmente (status: aguardando)
│  2. Publica evento [pedido.criado] em top-pedidos
│
▼
Azure Service Bus
│  Tópico: top-pedidos
│  Subscription: sub-pedidos-salematic
│
▼
Salematic (processador)
│
│  3. Consome [pedido.criado]
│  4. Valida estoque / processa pagamento
│  5. Publica evento de retorno em top-status-pedidos
│     - [pagamento.confirmado]
│     - [pagamento.recusado]
│     - [pedido.pendente]
│     - [pedido.timeout]
│     - [pedido.erro]
│
▼
Azure Service Bus
│  Tópico: top-status-pedidos
│  Subscription: sub-status-cmsx
│
▼
CMSX (consumidor de status)
│
│  6. Consome evento de retorno
│  7. Atualiza status do pedido
│  8. (futuro) Baixa de estoque local / notifica operador
```

---

## Implementação no CMSX

**Publicador:** `PedidosServiceBusPublisher`
- Publica no tópico `top-pedidos`
- Chamado na criação de pedido
- appsettings.json: `ServiceBus:TopicoPedidos = top-pedidos`

**Consumidor de status:** `PedidosServiceBusConsumer`
- Consome `top-status-pedidos` via `sub-status-cmsx`
- Switch por `msg.Evento`:
  ```csharp
  switch (msg.Evento)
  {
      case "pagamento.confirmado": // atualizar status + baixar estoque (TODO)
      case "pagamento.recusado":   // notificar operador
      case "pedido.pendente":      // aguardar próximo evento
      case "pedido.timeout":       // notificar operador
      case "pedido.erro":          // log + notificar operador
  }
  ```

**Modelo:** `PedidoStatusMsg`
```csharp
public class PedidoStatusMsg
{
    public string PedidoId { get; set; }
    public string Evento   { get; set; }
    // ... outros campos
}
```

**Caminho:** `T:\Developer\RepositorioTrabalho\tecbakana\cmsx`

---

## Implementação no Salematic

**Interface:** `IEventPublisher` — `Salematic.Domain/Interfaces/`
```csharp
public interface IEventPublisher
{
    Task PublishAsync(string topico, object evento);
}
```

**Implementação:** `ServiceBusPublisher` — `Salematic.Infrastructure/ServiceBus/`

**Consumidor:** `ServiceBusConsumer` (PedidoCriadoConsumer) — BackgroundService
- Consome `top-pedidos` via `sub-pedidos-salematic`

**PedidoService** — recebe `IEventPublisher` via DI, publica eventos de retorno

**DI (Program.cs):**
```csharp
builder.Services.AddSingleton<IEventPublisher, ServiceBusPublisher>();
```

**NuGet:** `Azure.Messaging.ServiceBus` no projeto Infrastructure

**Caminho:** `T:\developer\salematic`

---

## Contratos de evento

### pedido.criado (CMSX → Salematic)
```json
{
  "pedidoId": "string",
  "clienteId": "string",
  "itens": [{ "produtoId": "string", "quantidade": 0, "precoUnitario": 0 }],
  "valorTotal": 0,
  "evento": "pedido.criado"
}
```

### retorno (Salematic → CMSX)
```json
{
  "pedidoId": "string",
  "evento": "pagamento.confirmado | pagamento.recusado | pedido.pendente | pedido.timeout | pedido.erro",
  "mensagem": "string (opcional)"
}
```

---

## Configuração Azure Service Bus

| Recurso | Nome |
|---|---|
| Namespace | `sb-limpmax-dev.servicebus.windows.net` |
| Tópico (pedidos) | `top-pedidos` |
| Subscription Salematic | `sub-pedidos-salematic` |
| Tópico (status) | `top-status-pedidos` |
| Subscription CMSX | `sub-status-cmsx` |

**Secrets (não comitar):**
- CMSX: `appsettings.json` — connection string hardcoded (pendente migrar para Key Vault)
- Salematic: `dotnet user-secrets` — `ServiceBus:ConnectionString`

---

## Status de implementação

| Componente | CMSX | Salematic |
|---|---|---|
| Publicador de pedido | ✅ PedidosServiceBusPublisher | — |
| Consumidor de pedido | — | ✅ PedidoCriadoConsumer (BackgroundService) |
| Publicador de retorno | — | ✅ ServiceBusPublisher / IEventPublisher |
| Consumidor de status | ✅ PedidosServiceBusConsumer | — |
| DI registrado | ✅ | ⚠️ fix pendente (ver abaixo) |
| Teste E2E (Fase 5) | ❌ pendente | ❌ pendente |

---

## Pendente

1. **Fix DI Salematic** — `Program.cs` deve ter:
   ```csharp
   builder.Services.AddSingleton<IEventPublisher, ServiceBusPublisher>();
   ```
   Sem isso: `Unable to resolve service for type 'IEventPublisher' while activating 'PedidoService'`

2. **Teste ponta a ponta (Fase 5)** — subir ambos, criar pedido no CMSX, verificar eventos no Service Bus, confirmar status atualizado no CMSX

3. **Baixa de estoque no CMSX** quando `pagamento.confirmado`

4. **Notificação de operador** nos casos `pagamento.recusado`, `pedido.erro`, `pedido.timeout`

5. **Confirmar** se publisher está sendo chamado corretamente na criação do pedido (item A do passo 4.2 CMSX)

---

## Pitfalls

| Problema | Causa | Fix |
|---|---|---|
| DI error ao subir Salematic | `IEventPublisher` não registrado | `AddSingleton<IEventPublisher, ServiceBusPublisher>()` |
| Connection string hardcoded CMSX | Legado — pendente migrar | Não comitar. Migrar para App Service Configuration ou Key Vault |
| Dois tópicos separados | Pedido vai em `top-pedidos`; retorno em `top-status-pedidos` | Nunca misturar — each subscription filtra por tópico, não por evento |

---

## Ver também

- [shared-pattern-servicebus.md](shared-pattern-servicebus.md) — detalhes do namespace e configuração
- [salematic-howto-nova-tool.md](../salematic/salematic-howto-nova-tool.md)
- [cmsx-arch-ntier.md](../cmsx/cmsx-arch-ntier.md)
