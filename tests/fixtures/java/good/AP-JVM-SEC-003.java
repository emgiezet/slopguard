import com.fasterxml.jackson.databind.ObjectMapper;

public class DataLoader {
    private final ObjectMapper mapper = new ObjectMapper();

    // ok: slopguard.jvm.object-deserialize
    public MyData load(InputStream inputStream) throws Exception {
        // Type-safe JSON deserialization — no gadget-chain risk
        return mapper.readValue(inputStream, MyData.class);
    }
}
