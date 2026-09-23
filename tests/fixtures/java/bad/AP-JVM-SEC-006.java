import javax.net.ssl.*;
import java.security.cert.X509Certificate;

public class InsecureHttp {
    // ruleid: slopguard.jvm.trust-all-ssl
    public void disableVerification() throws Exception {
        TrustManager[] trustAll = new TrustManager[]{
            new X509TrustManager() {
                public void checkClientTrusted(X509Certificate[] c, String t) {}
                public void checkServerTrusted(X509Certificate[] c, String t) {}
                public X509Certificate[] getAcceptedIssuers() { return null; }
            }
        };
        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(null, trustAll, null);
        HttpsURLConnection.setDefaultSSLSocketFactory(ctx.getSocketFactory());
    }
}
