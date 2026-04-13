using System.Text.Json;
using System.Text.RegularExpressions;
using DevAutomation.Models;

namespace DevAutomation.Services;

public class ConfigService
{
    private readonly string _configFile;
    private readonly string _stateFile;
    private static readonly JsonSerializerOptions _jsonOpts = new() { WriteIndented = true };

    public ConfigService(IConfiguration config)
    {
        _configFile = config["DevAutomation:ConfigFile"]!;
        _stateFile  = config["DevAutomation:StateFile"]!;
    }

    public EnvironmentConfig LoadConfig()
    {
        var raw   = File.ReadAllText(_configFile);
        var clean = Regex.Replace(raw, @"(?m)^\s*//.*$", ""); // remove comentários
        return JsonSerializer.Deserialize<EnvironmentConfig>(clean) ?? new();
    }

    public Dictionary<string, string> LoadState()
    {
        if (!File.Exists(_stateFile)) return [];
        var raw = File.ReadAllText(_stateFile);
        return JsonSerializer.Deserialize<Dictionary<string, string>>(raw) ?? [];
    }

    public void SaveState(Dictionary<string, string> state)
    {
        File.WriteAllText(_stateFile, JsonSerializer.Serialize(state, _jsonOpts));
    }

    public void SetState(string key, string value)
    {
        var state = LoadState();
        state[key] = value;
        SaveState(state);
    }
}
