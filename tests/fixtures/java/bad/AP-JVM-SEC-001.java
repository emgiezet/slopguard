import java.sql.*;

public class UserRepository {
    private Connection conn;

    // ruleid: slopguard.jvm.jdbc-string-concat
    public ResultSet findByEmail(String email) throws SQLException {
        String sql = "SELECT * FROM users WHERE email = '" + email + "'";
        return conn.createStatement().executeQuery(sql);
    }

    // ruleid: slopguard.jvm.jdbc-string-concat
    public void deleteUser(String userId) throws SQLException {
        Statement stmt = conn.createStatement();
        stmt.execute("DELETE FROM users WHERE id = " + userId);
    }
}
