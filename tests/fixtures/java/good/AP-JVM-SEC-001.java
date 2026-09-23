import java.sql.*;

public class UserRepository {
    private Connection conn;

    // ok: slopguard.jvm.jdbc-string-concat
    public ResultSet findByEmail(String email) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(
            "SELECT * FROM users WHERE email = ?"
        );
        ps.setString(1, email);
        return ps.executeQuery();
    }

    // ok: slopguard.jvm.jdbc-string-concat
    public void deleteUser(long userId) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(
            "DELETE FROM users WHERE id = ?"
        );
        ps.setLong(1, userId);
        ps.execute();
    }
}
