import javax.net.ssl.SSLContext;
import java.net.http.HttpClient;

public class SecureHttp {
    // ok: slopguard.jvm.trust-all-ssl
    // Use the default trust store; add custom CA certs via truststore if needed
    public HttpClient buildClient() {
        return HttpClient.newBuilder()
            .sslContext(SSLContext.getDefault())
            .build();
    }
}
