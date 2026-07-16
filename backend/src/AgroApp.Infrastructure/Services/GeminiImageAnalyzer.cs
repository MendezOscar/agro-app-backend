using System.Net.Http.Json;
using System.Text.Json;
using AgroApp.Application.Common;
using Microsoft.Extensions.Options;

namespace AgroApp.Infrastructure.Services;

public class GeminiOptions
{
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = "gemini-flash-latest";
    public string BaseUrl { get; set; } = "https://generativelanguage.googleapis.com";
}

/// <summary>
/// Analiza fotos de cultivo con la API de visión de Google Gemini (nivel gratis).
/// Devuelve JSON estructurado (diagnóstico, severidad, confianza, recomendaciones)
/// usando generationConfig.responseSchema.
/// </summary>
public class GeminiImageAnalyzer : IImageAnalyzer
{
    private readonly HttpClient _http;
    private readonly GeminiOptions _opt;

    public GeminiImageAnalyzer(HttpClient http, IOptions<GeminiOptions> opt)
    {
        _opt = opt.Value;
        _http = http;
        _http.BaseAddress = new Uri(_opt.BaseUrl);
        _http.Timeout = TimeSpan.FromSeconds(45);
    }

    private const string Prompt =
        "Eres un agrónomo experto. Analiza esta foto de un cultivo e identifica plagas, " +
        "enfermedades o deficiencias visibles, y el estado general de la planta. " +
        "Responde en español.";

    // Esquema de salida estructurada de Gemini (tipos en mayúscula).
    private static readonly object Schema = new
    {
        type = "OBJECT",
        properties = new
        {
            diagnosis = new { type = "STRING", description = "Diagnóstico principal (plaga/enfermedad/estado)" },
            severity = new { type = "STRING", @enum = new[] { "none", "low", "medium", "high" } },
            confidence = new { type = "NUMBER", description = "Confianza 0.0–1.0" },
            recommendations = new { type = "STRING", description = "Recomendaciones de manejo" }
        },
        required = new[] { "diagnosis", "severity", "confidence", "recommendations" }
    };

    public async Task<ImageAnalysisResult> AnalyzeAsync(
        byte[] image, string contentType, string cropContext, CancellationToken ct = default)
    {
        var body = new
        {
            contents = new object[]
            {
                new
                {
                    parts = new object[]
                    {
                        new
                        {
                            inline_data = new
                            {
                                mime_type = string.IsNullOrWhiteSpace(contentType) ? "image/jpeg" : contentType,
                                data = Convert.ToBase64String(image)
                            }
                        },
                        new { text = $"{Prompt}\nContexto del cultivo: {cropContext}" }
                    }
                }
            },
            generationConfig = new
            {
                responseMimeType = "application/json",
                responseSchema = Schema
            }
        };

        var url = $"/v1beta/models/{_opt.Model}:generateContent?key={_opt.ApiKey}";

        // Gemini free tier devuelve 503 "high demand"/429 de forma intermitente:
        // reintentar con backoff exponencial antes de fallar.
        string payload = "";
        System.Net.HttpStatusCode status = 0;
        for (var attempt = 0; attempt < 4; attempt++)
        {
            using var resp = await _http.PostAsJsonAsync(url, body, ct);
            status = resp.StatusCode;
            payload = await resp.Content.ReadAsStringAsync(ct);
            if (resp.IsSuccessStatusCode) break;
            if (status != System.Net.HttpStatusCode.ServiceUnavailable &&
                status != System.Net.HttpStatusCode.TooManyRequests)
                throw new HttpRequestException($"Gemini {(int)status}: {payload}");
            if (attempt < 3)
                await Task.Delay(TimeSpan.FromSeconds(2 * (attempt + 1)), ct);
        }
        if (status != System.Net.HttpStatusCode.OK)
            throw new HttpRequestException($"Gemini {(int)status}: {payload}");
        using var doc = JsonDocument.Parse(payload);

        // candidates[0].content.parts[0].text contiene el JSON validado contra el esquema.
        var text = doc.RootElement.GetProperty("candidates")[0]
            .GetProperty("content").GetProperty("parts")[0]
            .GetProperty("text").GetString() ?? "{}";

        using var parsed = JsonDocument.Parse(text);
        var root = parsed.RootElement;
        return new ImageAnalysisResult(
            root.GetProperty("diagnosis").GetString() ?? "",
            root.GetProperty("severity").GetString() ?? "none",
            root.TryGetProperty("confidence", out var c) ? c.GetDouble() : 0,
            root.GetProperty("recommendations").GetString() ?? "",
            text);
    }
}
