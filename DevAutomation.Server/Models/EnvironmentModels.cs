using System.Text.Json.Serialization;

namespace DevAutomation.Models;

public class EnvironmentConfig
{
    [JsonPropertyName("apis")]
    public List<ApiConfig> Apis { get; set; } = [];

    [JsonPropertyName("branches")]
    public List<string> Branches { get; set; } = [];

    [JsonPropertyName("servers")]
    public Dictionary<string, ServerConfig>? Servers { get; set; }

    [JsonPropertyName("agent")]
    public AgentConfig? Agent { get; set; }
}

public class ApiConfig
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("configType")]
    public string ConfigType { get; set; } = "json";

    [JsonPropertyName("configFile")]
    public string? ConfigFile { get; set; }

    [JsonPropertyName("gitRepo")]
    public string GitRepo { get; set; } = "";

    [JsonPropertyName("solutionPath")]
    public string? SolutionPath { get; set; }

    [JsonPropertyName("desktop")]
    public int Desktop { get; set; }

    [JsonPropertyName("batchOpen")]
    public string? BatchOpen { get; set; }

    [JsonPropertyName("clients")]
    public List<string> Clients { get; set; } = ["default"];
}

public class ServerConfig
{
    [JsonPropertyName("host")]
    public string Host { get; set; } = "";

    [JsonPropertyName("user")]
    public string User { get; set; } = "";

    [JsonPropertyName("password")]
    public string Password { get; set; } = "";

    [JsonPropertyName("apis")]
    public List<ServerApiConfig> Apis { get; set; } = [];
}

public class ServerApiConfig
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("configPath")]
    public string ConfigPath { get; set; } = "";

    [JsonPropertyName("configType")]
    public string ConfigType { get; set; } = "json";
}

public class AgentConfig
{
    [JsonPropertyName("apiKey")]
    public string ApiKey { get; set; } = "";

    [JsonPropertyName("model")]
    public string Model { get; set; } = "";

    [JsonPropertyName("url")]
    public string Url { get; set; } = "";
}
