using AgroApp.Domain;

namespace AgroApp.Api;

/// <summary>Tareas técnicas recomendadas para cada etapa del ciclo. Son el guion de trabajo
/// del agrónomo: una base común a cualquier cultivo más los añadidos propios del cultivo
/// del ciclo. El usuario decide cuáles convierte en tareas reales.</summary>
public static class StageGuide
{
    public record Item(string Title, string Description);

    public static IReadOnlyList<Item> For(StageKind kind, string? crop)
    {
        var items = new List<Item>(Base(kind));
        items.AddRange(ByCrop(kind, crop));
        return items;
    }

    private static IEnumerable<Item> Base(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Analizar suelo y agua", "Diagnosticar pH, textura, materia orgánica y disponibilidad de nutrientes para armar el programa nutricional."),
            new("Seleccionar variedad o híbrido", "Elegir semilla de calidad adaptada al clima local y con resistencia a las plagas y enfermedades de la zona."),
            new("Definir la ventana de siembra", "Revisar el pronóstico de lluvias y temperaturas para elegir la fecha óptima."),
            new("Presupuestar insumos y mano de obra", "Proyectar el costo del ciclo y asegurar que los insumos lleguen a tiempo."),
        ],
        StageKind.SoilPrep =>
        [
            new("Elegir la labranza según la textura", "Subsolar si hay capas compactadas o arar suave; evitar sobre-trabajar el suelo para no erosionarlo."),
            new("Aplicar encalado o enmiendas", "Cal agrícola o yeso si el análisis mostró pH muy ácido o deficiencia de calcio."),
            new("Nivelar y trazar el drenaje", "Evitar encharcamientos que causen asfixia radicular y enfermedades fúngicas."),
            new("Incorporar materia orgánica", "Compost o estiércol maduro para mejorar la estructura y la retención de humedad."),
        ],
        StageKind.Sowing =>
        [
            new("Calibrar el trazado y la profundidad", "Ajustar la profundidad al tamaño de la semilla y la distancia entre plantas y surcos."),
            new("Tratar la semilla", "Proteger con fungicida, insecticida preventivo o inoculante biológico."),
            new("Aplicar fertilización de arranque", "Fuente de fósforo cerca de la semilla para estimular el crecimiento de la raíz."),
            new("Verificar la humedad del suelo", "Sembrar con el suelo a capacidad de campo."),
        ],
        StageKind.CropManagement =>
        [
            new("Ejecutar el plan de fertilización", "Aplicar nitrógeno, potasio y micronutrientes fraccionados según la etapa fenológica."),
            new("Ajustar el riego", "Calcular lámina y frecuencia según la evapotranspiración y el estado del cultivo."),
            new("Controlar malezas", "Deshierbe oportuno para evitar la competencia por luz, agua y nutrientes."),
            new("Podar o tutorar", "Mantener la arquitectura de la planta para favorecer la aireación y la entrada de luz."),
        ],
        StageKind.Monitoring =>
        [
            new("Hacer muestreo MIP", "Recorridos periódicos para detectar plagas antes de que superen el umbral económico de daño."),
            new("Evaluar estrés hídrico y nutricional", "Revisar la sintomatología foliar y medir la humedad del suelo."),
            new("Estimar el rendimiento", "Contar frutos o espigas por planta para proyectar el volumen de cosecha."),
        ],
        StageKind.Harvest =>
        [
            new("Determinar el punto óptimo de madurez", "Medir grados Brix, firmeza, humedad del grano o coloración."),
            new("Organizar cuadrilla y maquinaria", "Capacitar en el manejo cuidadoso del fruto para evitar daños mecánicos."),
            new("Cosechar en las horas frescas", "Madrugada o mañana, para reducir el estrés térmico del producto."),
        ],
        StageKind.PostHarvest =>
        [
            new("Limpiar y seleccionar", "Clasificar por tamaño, peso o calidad y descartar el producto dañado o enfermo."),
            new("Enfriar y empacar", "Bajar la temperatura si el cultivo lo requiere y usar recipientes ventilados y limpios."),
            new("Controlar el almacenamiento", "Mantener la temperatura y la humedad relativa que alargan la vida útil."),
        ],
        StageKind.Evaluation =>
        [
            new("Analizar la rentabilidad", "Comparar el costo ejecutado por etapa contra el rendimiento final y el precio de venta."),
            new("Revisar el balance de nutrientes", "Evaluar el agotamiento del suelo para planificar la rotación o el siguiente ciclo."),
            new("Revisar los registros del ciclo", "Identificar qué prácticas funcionaron, qué plagas costaron más y qué corregir la próxima temporada."),
        ],
        _ => [],
    };

    private static bool IsCoffee(string? crop)
    {
        var c = (crop ?? "").ToLowerInvariant();
        return c.Contains("café") || c.Contains("cafe") || c.Contains("coffee");
    }

    private static IEnumerable<Item> ByCrop(StageKind kind, string? crop)
    {
        if (!IsCoffee(crop)) return [];
        return kind switch
        {
            StageKind.Planning =>
            [
                new("Programar el vivero", "Encargar o producir las chapolas con cuatro a seis meses de anticipación."),
            ],
            StageKind.SoilPrep =>
            [
                new("Definir la sombra", "Elegir el porcentaje de sombra y la especie (guama, banano) antes de establecer el cafetal."),
            ],
            StageKind.Sowing =>
            [
                new("Definir la densidad de siembra", "A 1.5 x 1.0 m caben unas 6.600 plantas por hectárea; ajustar según variedad y pendiente."),
            ],
            StageKind.CropManagement =>
            [
                new("Deschuponar", "Eliminar los chupones para concentrar el crecimiento en los ejes productivos."),
                new("Programar la poda o recepa", "Renovar los lotes con más de cinco cosechas para sostener el rendimiento."),
            ],
            StageKind.Monitoring =>
            [
                new("Muestrear broca", "Revisar 30 árboles al azar: por encima del 5 % de frutos perforados hay que controlar."),
                new("Revisar roya", "Contar hojas con lesiones; a partir del 10 % de incidencia iniciar el control."),
            ],
            StageKind.Harvest =>
            [
                new("Recolectar solo fruto maduro", "Pasar por el lote cada 12 a 15 días; el grano verde castiga la calidad en taza."),
            ],
            StageKind.PostHarvest =>
            [
                new("Verificar la humedad del pergamino", "Secar hasta 11-12 %: por encima aparece moho y por debajo el grano se quiebra en la trilla."),
            ],
            StageKind.Evaluation =>
            [
                new("Registrar el perfil de taza", "Anotar el puntaje SCA y los defectos para relacionarlos con el manejo del ciclo."),
            ],
            _ => [],
        };
    }
}
