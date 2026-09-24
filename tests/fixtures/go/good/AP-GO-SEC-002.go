package slopguardtest

import (
	"context"
	"database/sql"
)

// QueryUser uses a parameterised query — no gosec G201.
// ok: slopguard.go.gosec.G201
func QueryUser(ctx context.Context, db *sql.DB, id string) error {
	_, err := db.ExecContext(ctx, "SELECT * FROM users WHERE id = ?", id)
	return err
}
