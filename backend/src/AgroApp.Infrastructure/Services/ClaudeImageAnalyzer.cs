using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using AgroApp.Application.Common;
using Microsoft.Extensions.Options;

namespace AgroApp.Infrastructure.Services;

public class AnthropicOptions
{
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = "claude-opus-4-8";
    public string BaseUrl { get; set; } = "https://api.anthropic.com";
}

/// <summary>
/// Analiza fotos de cultivo con la API de visión de Claude. Devuelve JSON estructurado
/// (diagnóstico, severidad, confianza, recomendaciones) usando output_config.format.
/// </summary>
public class ClaudeImageAnalyzer : IImageAnalyzer
{
    private readonly HttpClient _http;
    private readonly AnthropicOptions _opt;

    public ClaudeImageAnalyzer(HttpClient http, IOptions<AnthropicOptions> opt)
    {
        _opt = opt.Value;
        _http = http;
        _http.BaseAddress = new Uri(_opt.BaseUrl);
        _http.DefaultRequestHeaders.Add("x-api-key", _opt.ApiKey);
        _http.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");
        _http.Timeout = TimeSpan.FromSeconds(120);
    }

    private const string Prompt =
        "Eres un agrónomo experto. Analiza esta foto de un cultivo e identifica plagas, " +
        "enfermedades o deficiencias visibles, y el estado general de la planta. " +
        "Responde en español.";

    // Esquema de salida estructurada — garantiza JSON parseable.
    private static readonly object Schema = new
    {
        type = "object",
        properties = new
        {
            diagnosis = new { type = "string", description = "Diagnóstico principal (plaga/enfermedad/estado)" },
            severity = new { type = "string", @enum = new[] { "none", "low", "medium", "high" } },
            confidence = new { type = "number", description = "Confianza 0.0–1.0" },
            recommendations = new { type = "string", description = "Recomendaciones de manejo" }
        },
        required = new[] { "diagnosis", "severity", "confidence", "recommendations" },
        additionalProperties = false
    };

    public async Task<ImageAnalysisResult> AnalyzeAsync(
        byte[] image, string contentType, string cropContext, CancellationToken ct = default)
    {
        var body = new
        {
            model = _opt.Model,
            max_tokens = 1024,
            output_config = new { format = new { type = "json_schema", schema = Schema } },
            messages = new object[]
            {
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new
                        {
                            type = "image",
                            source = new
                            {
                                type = "base64",
                                media_type = string.IsNullOrWhiteSpace(contentType) ? "image/jpeg" : contentType,
                                data = Convert.ToBase64String(image)
                            }
                        },
                        new { type = "text", text = $"{Prompt}\nContexto del cultivo: {cropContext}" }
                    }
                }
            }
        };

        using var resp = await _http.PostAsJsonAsync("/v1/messages", body, ct);
        resp.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(ct));

        // El primer bloque de texto contiene el JSON validado contra el esquema.
        var text = doc.RootElement.GetProperty("content")
            .EnumerateArray()
            .First(b => b.GetProperty("type").GetString() == "text")
            .GetProperty("text").GetString() ?? "{}";

        using var parsed = JsonDocument.Parse(text);
        var root = parsed.RootElement;
        return new ImageAnalysisResult(
            root.GetProperty("diagnosis").GetString() ?? "",
            root.GetProperty("severity").GetString() ?? "none",
            root.GetProperty("confidence").GetDouble(),
            root.GetProperty("recommendations").GetString() ?? "",
            text);
    }
}
