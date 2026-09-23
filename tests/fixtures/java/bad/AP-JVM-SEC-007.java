import javax.xml.parsers.*;
import org.xml.sax.InputSource;
import java.io.InputStream;

public class XmlParser {
    // ruleid: slopguard.jvm.xml-external-entity
    public void parse(InputStream xml) throws Exception {
        DocumentBuilderFactory dbf = DocumentBuilderFactory.newInstance();
        DocumentBuilder db = dbf.newDocumentBuilder();
        db.parse(xml); // external entities enabled by default
    }
}
