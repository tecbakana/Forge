using DevAutomation.Hubs;
using DevAutomation.Services;
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSignalR();
builder.Services.AddSingleton<ConfigService>();
builder.Services.AddHttpClient<GeminiService>();
builder.Services.AddSingleton<OrchestratorService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<OrchestratorService>());

builder.WebHost.UseUrls("http://localhost:8080");

var app = builder.Build();

// Serve o painel HTML estático da pasta original
var panelDir = builder.Configuration["DevAutomation:PanelDir"]!;
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(panelDir),
    RequestPath  = ""
});

app.MapFallback(async context =>
{
    if (!context.Request.Path.StartsWithSegments("/api") &&
        !context.Request.Path.StartsWithSegments("/hub"))
    {
        var indexPath = Path.Combine(panelDir, "index.html");
        context.Response.ContentType = "text/html; charset=utf-8";
        await context.Response.SendFileAsync(indexPath);
    }
});

app.MapControllers();
app.MapHub<OrchestratorHub>("/hub");

app.Run();
