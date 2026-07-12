using System.Threading.Channels;
using AgroApp.Application.Common;

namespace AgroApp.Infrastructure.Services;

/// <summary>Cola en memoria (Channel) de observaciones pendientes de análisis IA.</summary>
public class AnalysisQueue : IAnalysisQueue
{
    private readonly Channel<Guid> _channel =
        Channel.CreateUnbounded<Guid>(new UnboundedChannelOptions { SingleReader = true });

    public void Enqueue(Guid observationId) => _channel.Writer.TryWrite(observationId);

    public IAsyncEnumerable<Guid> DequeueAllAsync(CancellationToken ct) =>
        _channel.Reader.ReadAllAsync(ct);
}
