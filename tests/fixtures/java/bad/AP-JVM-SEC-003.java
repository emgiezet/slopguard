import java.io.*;

public class DataLoader {
    // ruleid: slopguard.jvm.object-deserialize
    public Object load(InputStream inputStream) throws Exception {
        ObjectInputStream ois = new ObjectInputStream(inputStream);
        return ois.readObject(); // arbitrary gadget chain possible
    }
}
