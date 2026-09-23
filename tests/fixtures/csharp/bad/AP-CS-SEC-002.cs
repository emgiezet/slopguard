using System.Runtime.Serialization.Formatters.Binary;

// ruleid: slopguard.cs.binary-formatter
public class DataService
{
    public object Load(Stream stream)
    {
        var bf = new BinaryFormatter();
        return bf.Deserialize(stream);
    }
}
