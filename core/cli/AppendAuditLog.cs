using System.Security.Cryptography;
using System.Text;

// Production audit files are opened by their current name for each complete
// record. A long-lived handle must not silently continue writing an unlinked
// file after a workspace/filesystem replaces the visible path.
internal sealed class AppendAuditLog : IDisposable
{
    readonly string path;
    readonly IncrementalHash digest=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
    long writtenBytes,records,lastRecordOffset;
    internal AppendAuditLog(string path)
    {
        this.path=path;
        using var stream=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read);
    }
    internal void Append(string record,long index)
    {
        if(index!=records+1)throw new InvalidDataException("Non-sequential audit record: "+path);
        var bytes=Encoding.UTF8.GetBytes(record);
        using(var stream=new FileStream(path,FileMode.Open,FileAccess.Write,FileShare.Read))
        {
            if(stream.Length!=writtenBytes)throw new IOException($"Audit path length changed: {path}; expected {writtenBytes}, found {stream.Length}.");
            stream.Seek(0,SeekOrigin.End);stream.Write(bytes);stream.Flush();
            if(stream.Position!=writtenBytes+bytes.Length)throw new IOException("Incomplete audit append: "+path);
        }
        lastRecordOffset=writtenBytes;writtenBytes+=bytes.Length;records=index;digest.AppendData(bytes);
    }
    internal object Snapshot()
    {
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite);
        var namedBytes=stream.Length;long lastIndex=0;
        if(records>0&&namedBytes>lastRecordOffset)
        {
            stream.Position=lastRecordOffset;Span<byte> prefix=stackalloc byte[96];var count=stream.Read(prefix);
            var line=Encoding.UTF8.GetString(prefix[..count]).Split('\n')[0];
            const string marker="- receipt_index: ";
            if(line.StartsWith(marker,StringComparison.Ordinal))long.TryParse(line[marker.Length..].Trim(),out lastIndex);
        }
        if(namedBytes!=writtenBytes||lastIndex!=records)
            throw new IOException($"Audit persistence mismatch: {path}; bytes {namedBytes}/{writtenBytes}, last record {lastIndex}/{records}.");
        return new {path=Path.GetFileName(path),written_records=records,expected_bytes=writtenBytes,named_bytes=namedBytes,
            last_record_index=lastIndex,consistent=true};
    }
    internal object VerifiedCoverage()
    {
        _=Snapshot();
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite);
        var actual=SHA256.HashData(stream);var expected=digest.GetCurrentHash();
        if(!actual.AsSpan().SequenceEqual(expected))throw new IOException("Audit content no longer matches its actual append sequence: "+path);
        return new {path=Path.GetFileName(path),bytes=writtenBytes,rows=records,
            sha256=Convert.ToHexString(actual).ToLowerInvariant(),verified_against_appended_records=true};
    }
    public void Dispose()=>digest.Dispose();
}
