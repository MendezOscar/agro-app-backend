using System.Globalization;
using System.Text;
using AgroApp.Domain;

namespace AgroApp.Api;

/// <summary>Tareas técnicas recomendadas para cada etapa del ciclo. Son el guion de trabajo
/// del agrónomo: una base común a cualquier cultivo más los añadidos propios del cultivo del
/// ciclo (café, maíz, frijol, arroz, papa y tomate). Un cultivo sin guion propio recibe solo
/// la base. El usuario decide cuáles convierte en tareas reales.</summary>
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

    /// <summary>Normaliza el nombre del cultivo a una clave interna: minúsculas, sin acentos y
    /// tolerando el nombre en inglés, para que "Maíz", "maiz" y "corn" caigan en el mismo guion.</summary>
    private static string CropKeyOf(string? crop)
    {
        var c = new string((crop ?? "").Normalize(NormalizationForm.FormD)
            .Where(ch => CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
            .ToArray()).ToLowerInvariant();

        if (c.Contains("cafe") || c.Contains("coffee")) return "cafe";
        if (c.Contains("maiz") || c.Contains("corn")) return "maiz";
        if (c.Contains("frijol") || c.Contains("bean")) return "frijol";
        if (c.Contains("arroz") || c.Contains("rice")) return "arroz";
        if (c.Contains("papa") || c.Contains("patata") || c.Contains("potato")) return "papa";
        if (c.Contains("tomate") || c.Contains("tomato") || c.Contains("hortaliza")) return "tomate";
        return "";
    }

    private static IEnumerable<Item> ByCrop(StageKind kind, string? crop) => CropKeyOf(crop) switch
    {
        "cafe" => Coffee(kind),
        "maiz" => Maize(kind),
        "frijol" => Bean(kind),
        "arroz" => Rice(kind),
        "papa" => Potato(kind),
        "tomate" => Tomato(kind),
        _ => [],
    };

    private static IEnumerable<Item> Coffee(StageKind kind) => kind switch
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

    private static IEnumerable<Item> Maize(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Elegir el híbrido por duración", "Decidir entre un híbrido precoz o tardío según cuánto dure la época lluviosa en la zona."),
        ],
        StageKind.SoilPrep =>
        [
            new("Revisar la compactación", "El maíz sufre con el piso de arado: subsolar si la raíz no pasa de 20 cm."),
        ],
        StageKind.Sowing =>
        [
            new("Ajustar la densidad", "De 55.000 a 65.000 plantas por hectárea; con surcos a 0.80 m son unas cuatro semillas por metro lineal."),
        ],
        StageKind.CropManagement =>
        [
            new("Fertilizar al aporque", "La mayor demanda de nitrógeno llega entre V6 y V8, de 30 a 35 días después de la siembra."),
        ],
        StageKind.Monitoring =>
        [
            new("Muestrear cogollero", "Revisar 20 plantas por sitio: por encima del 20 % de cogollos dañados hay que controlar."),
            new("Vigilar el elotero en floración", "El daño en mazorca ocurre desde la emisión de estigmas."),
        ],
        StageKind.Harvest =>
        [
            new("Medir la humedad del grano", "Entre 20 y 25 % para trilla mecánica; por debajo de 14 % si se cosecha para almacenar."),
        ],
        StageKind.PostHarvest =>
        [
            new("Secar hasta 13-14 %", "Por encima de esa humedad aparecen hongos y riesgo de aflatoxinas en el almacén."),
        ],
        StageKind.Evaluation =>
        [
            new("Comparar el rendimiento por híbrido", "Registrar qué material respondió mejor para decidir el del próximo ciclo."),
        ],
        _ => [],
    };

    private static IEnumerable<Item> Bean(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Elegir variedad por tolerancia", "Priorizar tolerancia al mosaico dorado y a la sequía intermedia de la canícula."),
        ],
        StageKind.SoilPrep =>
        [
            new("Asegurar el drenaje", "El frijol no tolera encharcamiento: usar camas o surcos altos si el suelo es pesado."),
        ],
        StageKind.Sowing =>
        [
            new("Inocular la semilla", "Aplicar Rhizobium antes de sembrar para aprovechar la fijación de nitrógeno."),
        ],
        StageKind.CropManagement =>
        [
            new("Moderar el nitrógeno", "El frijol fija su propio N: el exceso produce follaje y poca vaina."),
        ],
        StageKind.Monitoring =>
        [
            new("Vigilar mosca blanca", "Es el vector del mosaico dorado: revisar el envés de las hojas desde la emergencia."),
        ],
        StageKind.Harvest =>
        [
            new("Arrancar con el 90 % de vainas secas", "Esperar más abre las vainas y se pierde grano en el campo."),
        ],
        StageKind.PostHarvest =>
        [
            new("Secar a 12-13 % y proteger del gorgojo", "Almacenar en recipiente hermético o con control de gorgojo."),
        ],
        StageKind.Evaluation =>
        [
            new("Aprovechar el nitrógeno fijado", "Considerar el aporte del frijol al planificar el cultivo que siga en la rotación."),
        ],
        _ => [],
    };

    private static IEnumerable<Item> Rice(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Definir el sistema de producción", "Secano o riego cambia la variedad, la densidad y todo el calendario."),
        ],
        StageKind.SoilPrep =>
        [
            new("Nivelar el terreno", "Una nivelación pareja es lo que decide el control de malezas y el consumo de agua."),
        ],
        StageKind.Sowing =>
        [
            new("Ajustar la dosis de semilla", "De 80 a 120 kg por hectárea según el sistema y la variedad."),
        ],
        StageKind.CropManagement =>
        [
            new("Manejar la lámina de agua", "Mantenerla en macollamiento y drenar antes de la maduración."),
        ],
        StageKind.Monitoring =>
        [
            new("Vigilar sogata y añublo", "Revisar en macollamiento y en floración, que es cuando más daño causan."),
        ],
        StageKind.Harvest =>
        [
            new("Cosechar entre 20 y 24 % de humedad", "Más seco quiebra el grano en la trilla y baja el rendimiento de pilada."),
        ],
        StageKind.PostHarvest =>
        [
            new("Secar sin golpe térmico", "Bajar gradualmente a 13-14 %: el secado brusco quiebra el grano."),
        ],
        StageKind.Evaluation =>
        [
            new("Medir el rendimiento de pilada", "El grano entero define el precio, no solo el peso cosechado."),
        ],
        _ => [],
    };

    private static IEnumerable<Item> Potato(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Conseguir semilla certificada", "La semilla sana es la principal defensa contra tizón y virosis."),
        ],
        StageKind.SoilPrep =>
        [
            new("Preparar suelo suelto y profundo", "El tubérculo necesita al menos 30 cm sin compactación."),
        ],
        StageKind.Sowing =>
        [
            new("Definir distancia y aporques", "0.30 m entre tubérculos con surcos de 0.90 m, y dejar programados dos aporques."),
        ],
        StageKind.CropManagement =>
        [
            new("Programar el control de tizón", "Con humedad alta y noches frescas el tizón tardío avanza en días."),
        ],
        StageKind.Monitoring =>
        [
            new("Revisar follaje tras cada lluvia", "Es cuando aparecen los primeros focos de tizón y de polilla."),
        ],
        StageKind.Harvest =>
        [
            new("Esperar la madurez de la piel", "Cosechar cuando la piel no se desprenda al frotar, dos o tres semanas tras secarse el follaje."),
        ],
        StageKind.PostHarvest =>
        [
            new("Curar antes de almacenar", "De 7 a 10 días en oscuridad y con ventilación para que cicatricen las heridas."),
        ],
        StageKind.Evaluation =>
        [
            new("Registrar la distribución por calibre", "El precio depende del calibre, no solo del peso total."),
        ],
        _ => [],
    };

    private static IEnumerable<Item> Tomato(StageKind kind) => kind switch
    {
        StageKind.Planning =>
        [
            new("Planificar el semillero", "Producir o encargar la plántula de cuatro a seis semanas antes del trasplante."),
        ],
        StageKind.SoilPrep =>
        [
            new("Bajar la presión del suelo", "Solarizar o rotar para reducir nematodos y fusarium antes de trasplantar."),
        ],
        StageKind.Sowing =>
        [
            new("Trasplantar y dejar el tutorado listo", "Trasplantar con cuatro o cinco hojas verdaderas y tener el tutor puesto."),
        ],
        StageKind.CropManagement =>
        [
            new("Podar y deshijar", "Mantener uno o dos ejes y quitar los brotes axilares para airear la planta."),
        ],
        StageKind.Monitoring =>
        [
            new("Vigilar mosca blanca y tuta", "Usar trampas amarillas y de feromona para seguir la población."),
        ],
        StageKind.Harvest =>
        [
            new("Cortar en el punto de color del destino", "Mercado local más maduro; transporte largo, más pintón."),
        ],
        StageKind.PostHarvest =>
        [
            new("Enfriar rápido y empacar ventilado", "Quitar el calor de campo cuanto antes y evitar apilar en exceso."),
        ],
        StageKind.Evaluation =>
        [
            new("Registrar el descarte", "Anotar el porcentaje de fruto descartado y su causa."),
        ],
        _ => [],
    };
}
