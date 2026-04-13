# Padrão: Azure Service Bus — Namespace e Configuração
> Aplica-se a: CMSX (Multiplai), Salematic

## Namespace

```
sb-limpmax-dev.servicebus.windows.net
```

---

## Tópicos e subscriptions

| Tópico | Subscription | Consumidor | Direção |
|---|---|---|---|
| `top-pedidos` | `sub-pedidos-salematic` | Salematic | CMSX → Salematic |
| `top-status-pedidos` | `sub-status-cmsx` | CMSX | Salematic → CMSX |

**Regra:** cada tópico tem uma única direção. Nunca reutilizar o mesmo tópico para mensagens no sentido inverso.

---

## Configuração por projeto

### CMSX

`appsettings.json`:
```json
{
  "ServiceBus": {
    "ConnectionString": "Endpoint=sb://sb-limpmax-dev.servicebus.windows.net/;...",
    "TopicoPedidos": "top-pedidos",
    "SubscriptionStatus": "sub-status-cmsx",
    "TopicoStatus": "top-status-pedidos"
  }
}
```

> **Atenção:** Connection string ainda hardcoded no appsettings.json — pendente migrar para App Service Configuration ou Key Vault.

### Salematic

Via `dotnet user-secrets` (nunca no appsettings.json):
```bash
dotnet user-secrets set "ServiceBus:ConnectionString" "Endpoint=sb://sb-limpmax-dev.servicebus.windows.net/;..."
```

`appsettings.json` (somente nomes de tópicos, sem secrets):
```json
{
  "ServiceBus": {
    "TopicoPedidos": "top-pedidos",
    "SubscriptionPedidos": "sub-pedidos-salematic",
    "TopicoStatus": "top-status-pedidos"
  }
}
```

---

## NuGet

```
Azure.Messaging.ServiceBus
```

Instalar no projeto Infrastructure de cada solução:
```bash
dotnet add Salematic.Infrastructure package Azure.Messaging.ServiceBus
```

---

## Padrão de publicação (Salematic)

```csharp
// Salematic.Infrastructure/ServiceBus/ServiceBusPublisher.cs
using Azure.Messaging.ServiceBus;
using Salematic.Domain.Interfaces;
using System.Text.Json;

public class ServiceBusPublisher : IEventPublisher
{
    private readonly ServiceBusClient _client;
    private readonly string _topico;

    public ServiceBusPublisher(IConfiguration config)
    {
        _client = new ServiceBusClient(config["ServiceBus:ConnectionString"]);
        _topico = config["ServiceBus:TopicoStatus"]!; // publica status de volta para CMSX
    }

    public async Task PublishAsync(string topico, object evento)
    {
        var sender = _client.CreateSender(topico);
        var json = JsonSerializer.Serialize(evento);
        var msg = new ServiceBusMessage(json);
        await sender.SendMessageAsync(msg);
    }
}
```

**DI (Program.cs do Salematic.API):**
```csharp
builder.Services.AddSingleton<IEventPublisher, ServiceBusPublisher>();
```

---

## Padrão de consumo como BackgroundService (Salematic)

```csharp
// Salematic.Infrastructure/ServiceBus/ServiceBusConsumer.cs
using Azure.Messaging.ServiceBus;
using Microsoft.Extensions.Hosting;

public class PedidoCriadoConsumer : BackgroundService
{
    private readonly ServiceBusClient _client;
    private readonly string _topico;
    private readonly string _subscription;

    public PedidoCriadoConsumer(IConfiguration config)
    {
        _client       = new ServiceBusClient(config["ServiceBus:ConnectionString"]);
        _topico       = config["ServiceBus:TopicoPedidos"]!;       // top-pedidos
        _subscription = config["ServiceBus:SubscriptionPedidos"]!; // sub-pedidos-salematic
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var processor = _client.CreateProcessor(_topico, _subscription);

        processor.ProcessMessageAsync += async args =>
        {
            var body = args.Message.Body.ToString();
            // deserializar e processar
            await args.CompleteMessageAsync(args.Message);
        };

        processor.ProcessErrorAsync += args =>
        {
            // log do erro
            return Task.CompletedTask;
        };

        await processor.StartProcessingAsync(stoppingToken);
        await Task.Delay(Timeout.Infinite, stoppingToken);
    }
}
```

**DI (Program.cs):**
```csharp
builder.Services.AddHostedService<PedidoCriadoConsumer>();
```

---

## Pitfalls

| Problema | Causa | Fix |
|---|---|---|
| `UnauthorizedException` ao conectar | Connection string incorreta ou expirada | Verificar user-secrets / appsettings |
| Mensagem consumida mas não completada | `CompleteMessageAsync` não chamado | Chamar `await args.CompleteMessageAsync(args.Message)` após processar |
| Connection string no git | Commit acidental do appsettings | CMSX: mover para App Service Config. Salematic: sempre user-secrets |
| Dois tópicos confundidos | `top-pedidos` e `top-status-pedidos` têm nomes parecidos | Sempre referenciar via configuração (`config["ServiceBus:TopicoPedidos"]`), nunca string literal |
| BackgroundService não inicia | Não registrado como `AddHostedService` | Registrar em `Program.cs` |

---

## Ver também

- [shared-pattern-saga.md](shared-pattern-saga.md) — fluxo completo CMSX ↔ Salematic usando esses tópicos
- [cmsx-arch-ntier.md](../cmsx/cmsx-arch-ntier.md) — onde os publishers/consumers ficam nas camadas CMSX
