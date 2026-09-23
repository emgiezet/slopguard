public class CommandRunner {
    // ok: slopguard.jvm.runtime-exec-concat
    public String runCommand(String pattern) throws Exception {
        // Validate pattern against allowlist first
        if (!pattern.matches("[a-zA-Z0-9._-]+")) {
            throw new IllegalArgumentException("Invalid pattern");
        }
        ProcessBuilder pb = new ProcessBuilder("grep", pattern, "/var/log/app.log");
        pb.redirectErrorStream(true);
        Process p = pb.start();
        return new String(p.getInputStream().readAllBytes());
    }
}
