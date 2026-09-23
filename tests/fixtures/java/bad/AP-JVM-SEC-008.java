import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.servlet.http.HttpServletRequest;

public class LoginController {
    private static final Logger log = LoggerFactory.getLogger(LoginController.class);

    // ruleid: slopguard.jvm.log-injection
    public void login(HttpServletRequest req) {
        String username = req.getParameter("username");
        log.info("Login attempt by: " + username); // newlines in username corrupt logs
    }
}
