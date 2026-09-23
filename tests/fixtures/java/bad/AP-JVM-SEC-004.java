import java.util.Random;

public class TokenService {
    // ruleid: slopguard.jvm.insecure-random
    public String generateSessionId() {
        Random rng = new Random();
        return Long.toHexString(rng.nextLong());
    }

    // ruleid: slopguard.jvm.insecure-random
    public double generateNonce() {
        return Math.random();
    }
}
