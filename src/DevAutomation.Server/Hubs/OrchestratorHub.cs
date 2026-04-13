using Microsoft.AspNetCore.SignalR;

namespace DevAutomation.Hubs;

public class OrchestratorHub : Hub
{
    // Clientes se conectam e recebem eventos em tempo real.
    // Notificações são enviadas pelo OrchestratorService via IHubContext.
}
