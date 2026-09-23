import java.security.SecureRandom;
import java.util.HexFormat;

public class TokenService {
    private static final SecureRandom SECURE_RNG = new SecureRandom();

    // ok: slopguard.jvm.insecure-random
    public String generateSessionId() {
        byte[] bytes = new byte[32];
        SECURE_RNG.nextBytes(bytes);
        return HexFormat.of().formatHex(bytes);
    }
}
