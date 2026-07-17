using System.Net.Http.Json;
using System.Text.Json;
using AgroApp.Application.Common;
using Microsoft.Extensions.Options;

namespace AgroApp.Infrastructure.Services;

public class WeatherOptions
{
    public string ForecastUrl { get; set; } = "https://api.open-meteo.com/v1/forecast";
    public string ArchiveUrl { get; set; } = "https://archive-api.open-meteo.com/v1/archive";
}

/// <summary>
/// Calcula indicadores agronómicos (suelo por profundidad, balance hídrico/riego,
/// grados-día y riesgo de enfermedad) con datos gratuitos de Open-Meteo (sin API key).
/// </summary>
public class OpenMeteoAgronomyService : IAgronomyService
{
    private readonly HttpClient _http;
    private readonly WeatherOptions _opt;

    public OpenMeteoAgronomyService(HttpClient http, IOptions<WeatherOptions> opt)
    {
        _http = http;
        _opt = opt.Value;
        _http.Timeout = TimeSpan.FromSeconds(30);
    }

    // Temperatura base para GDD por cultivo (°C). Default 10.
    private static double BaseTemp(string crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        if (c.Contains("arroz") || c.Contains("rice")) return 12;
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato")) return 7;
        if (c.Contains("trigo") || c.Contains("wheat")) return 4;
        return 10; // café, maíz, frijol, tomate, etc.
    }

    private async Task<JsonElement?> GetJsonAsync(string url, CancellationToken ct)
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            using var resp = await _http.GetAsync(url, ct);
            if (resp.IsSuccessStatusCode)
            {
                var payload = await resp.Content.ReadAsStringAsync(ct);
                return JsonDocument.Parse(payload).RootElement.Clone();
            }
            var transient = resp.StatusCode == System.Net.HttpStatusCode.ServiceUnavailable ||
                            resp.StatusCode == System.Net.HttpStatusCode.TooManyRequests;
            if (!transient || attempt == 2) return null;
            await Task.Delay(TimeSpan.FromSeconds(2 * (attempt + 1)), ct);
        }
        return null;
    }

    public async Task<AgronomyResult> GetAsync(
        double lat, double lng, DateOnly? cycleStart, string crop, CancellationToken ct = default)
    {
        var soil = new List<SoilLayer>();
        WaterBalance? water = null;
        DiseaseRisk? disease = null;
        GddResult? gdd = null;

        // --- Pronóstico: suelo actual, balance hídrico (7+7) y riesgo de enfermedad ---
        try
        {
            var url = $"{_opt.ForecastUrl}?latitude={lat}&longitude={lng}" +
                "&hourly=soil_temperature_0cm,soil_temperature_6cm,soil_temperature_18cm,soil_temperature_54cm," +
                "soil_moisture_0_1cm,soil_moisture_1_3cm,soil_moisture_3_9cm,soil_moisture_9_27cm," +
                "relative_humidity_2m,temperature_2m" +
                "&daily=et0_fao_evapotranspiration,precipitation_sum" +
                "&past_days=7&forecast_days=7&timezone=auto";
            var root = await GetJsonAsync(url, ct);
            if (root is JsonElement fc)
            {
                if (fc.TryGetProperty("hourly", out var h))
                {
                    var idx = LastValidIndex(h, "temperature_2m");
                    soil.Add(new SoilLayer("0 cm", HourAt(h, "soil_temperature_0cm", idx), Pct(HourAt(h, "soil_moisture_0_1cm", idx))));
                    soil.Add(new SoilLayer("6 cm", HourAt(h, "soil_temperature_6cm", idx), Pct(HourAt(h, "soil_moisture_1_3cm", idx))));
                    soil.Add(new SoilLayer("18 cm", HourAt(h, "soil_temperature_18cm", idx), Pct(HourAt(h, "soil_moisture_3_9cm", idx))));
                    soil.Add(new SoilLayer("54 cm", HourAt(h, "soil_temperature_54cm", idx), Pct(HourAt(h, "soil_moisture_9_27cm", idx))));

                    // Riesgo de enfermedad: horas (últimas ~48h) con RH>=85% y 15-28°C.
                    var rh = Doubles(h, "relative_humidity_2m");
                    var temp = Doubles(h, "temperature_2m");
                    var n = Math.Min(rh.Count, temp.Count);
                    var from = Math.Max(0, n - 48);
                    var favorable = 0;
                    for (var i = from; i < n; i++)
                        if (rh[i].HasValue && temp[i].HasValue &&
                            rh[i]! >= 85 && temp[i]! >= 15 && temp[i]! <= 28) favorable++;
                    var level = favorable >= 18 ? "high" : favorable >= 8 ? "medium" : favorable >= 3 ? "low" : "none";
                    disease = new DiseaseRisk(level,
                        $"{favorable} h con humedad ≥85% y 15–28 °C en las últimas 48 h (favorable a hongos).");
                }
                if (fc.TryGetProperty("daily", out var d))
                {
                    var et0 = Doubles(d, "et0_fao_evapotranspiration");
                    var pr = Doubles(d, "precipitation_sum");
                    var et0Sum = et0.Where(x => x.HasValue).Sum(x => x!.Value);
                    var prSum = pr.Where(x => x.HasValue).Sum(x => x!.Value);
                    var deficit = Math.Max(0, et0Sum - prSum);
                    water = new WaterBalance(
                        Math.Round(et0Sum, 1), Math.Round(prSum, 1), Math.Round(deficit, 1),
                        deficit > 15, Math.Round(deficit, 0));
                }
            }
        }
        catch { /* bloque de pronóstico opcional */ }

        // --- Histórico: grados-día acumulados desde el inicio del ciclo ---
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        if (cycleStart is DateOnly start && start < today)
        {
            try
            {
                var baseT = BaseTemp(crop);
                var url = $"{_opt.ArchiveUrl}?latitude={lat}&longitude={lng}" +
                    $"&start_date={start:yyyy-MM-dd}&end_date={today.AddDays(-1):yyyy-MM-dd}" +
                    "&daily=temperature_2m_max,temperature_2m_min&timezone=auto";
                var root = await GetJsonAsync(url, ct);
                if (root is JsonElement arc && arc.TryGetProperty("daily", out var d))
                {
                    var tmax = Doubles(d, "temperature_2m_max");
                    var tmin = Doubles(d, "temperature_2m_min");
                    var n = Math.Min(tmax.Count, tmin.Count);
                    double acc = 0; var days = 0;
                    for (var i = 0; i < n; i++)
                    {
                        if (!tmax[i].HasValue || !tmin[i].HasValue) continue;
                        acc += Math.Max(0, (tmax[i]!.Value + tmin[i]!.Value) / 2 - baseT);
                        days++;
                    }
                    gdd = new GddResult(baseT, Math.Round(acc, 0), days);
                }
            }
            catch { /* bloque histórico opcional */ }
        }

        return new AgronomyResult(soil, water, gdd, disease, "Open-Meteo", null);
    }

    // Helpers de parseo del arreglo hourly/daily.
    private static List<double?> Doubles(JsonElement obj, string prop)
    {
        var list = new List<double?>();
        if (obj.TryGetProperty(prop, out var arr) && arr.ValueKind == JsonValueKind.Array)
            foreach (var e in arr.EnumerateArray())
                list.Add(e.ValueKind == JsonValueKind.Number ? e.GetDouble() : (double?)null);
        return list;
    }

    private static int LastValidIndex(JsonElement hourly, string prop)
    {
        var vals = Doubles(hourly, prop);
        for (var i = vals.Count - 1; i >= 0; i--)
            if (vals[i].HasValue) return i;
        return -1;
    }

    private static double? HourAt(JsonElement hourly, string prop, int idx)
    {
        if (idx < 0) return null;
        var vals = Doubles(hourly, prop);
        return idx < vals.Count ? vals[idx] : null;
    }

    // Open-Meteo entrega humedad de suelo como fracción (m³/m³); a %.
    private static double? Pct(double? frac) => frac.HasValue ? Math.Round(frac.Value * 100, 1) : null;
}
