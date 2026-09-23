using System.Text.Json;

// ok: slopguard.cs.binary-formatter
public class DataService
{
    public MyData Load(Stream stream)
    {
        return JsonSerializer.Deserialize<MyData>(stream)!;
    }
}
