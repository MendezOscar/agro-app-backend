using AgroApp.Application.Common;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;

namespace AgroApp.Infrastructure.Services;

public class StorageOptions
{
    public string Endpoint { get; set; } = "http://localhost:9000";
    public string AccessKey { get; set; } = string.Empty;
    public string SecretKey { get; set; } = string.Empty;
    public string Bucket { get; set; } = "agroapp-images";
    public string Region { get; set; } = "us-east-1";
}

public class StorageService : IStorageService
{
    private readonly IAmazonS3 _s3;
    private readonly StorageOptions _opt;

    public StorageService(IOptions<StorageOptions> opt)
    {
        _opt = opt.Value;
        // Config para MinIO: endpoint propio + path-style.
        _s3 = new AmazonS3Client(_opt.AccessKey, _opt.SecretKey, new AmazonS3Config
        {
            ServiceURL = _opt.Endpoint,
            ForcePathStyle = true,
            AuthenticationRegion = _opt.Region
        });
    }

    public async Task<string> UploadAsync(Stream content, string key, string contentType, CancellationToken ct = default)
    {
        // Buffer a MemoryStream: la firma SigV4 sobre http requiere un stream seekable.
        using var buffer = new MemoryStream();
        await content.CopyToAsync(buffer, ct);
        buffer.Position = 0;

        await _s3.PutObjectAsync(new PutObjectRequest
        {
            BucketName = _opt.Bucket,
            Key = key,
            InputStream = buffer,
            ContentType = contentType
        }, ct);
        return key;
    }

    public async Task<byte[]> DownloadAsync(string key, CancellationToken ct = default)
    {
        using var response = await _s3.GetObjectAsync(_opt.Bucket, key, ct);
        using var ms = new MemoryStream();
        await response.ResponseStream.CopyToAsync(ms, ct);
        return ms.ToArray();
    }

    public string GetPresignedUrl(string key, TimeSpan expiry) =>
        _s3.GetPreSignedURL(new GetPreSignedUrlRequest
        {
            BucketName = _opt.Bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(expiry)
        });
}
