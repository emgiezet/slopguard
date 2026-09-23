import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.servlet.http.HttpServletRequest;

public class LoginController {
    private static final Logger log = LoggerFactory.getLogger(LoginController.class);

    // ok: slopguard.jvm.log-injection
    public void login(HttpServletRequest req) {
        String username = req.getParameter("username");
        // Use structured logging — value is in a field, not concatenated into message
        log.info("Login attempt by user", username); // SLF4J structured arg
        // Or strip control characters
        String sanitized = username != null ? username.replaceAll("[\r\n\t]", "_") : "";
        log.info("Login attempt by: {}", sanitized);
    }
}
