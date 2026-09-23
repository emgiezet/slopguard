public class CommandRunner {
    // ruleid: slopguard.jvm.runtime-exec-concat
    public String runCommand(String userInput) throws Exception {
        Process p = Runtime.getRuntime().exec("grep " + userInput + " /var/log/app.log");
        return new String(p.getInputStream().readAllBytes());
    }
}
