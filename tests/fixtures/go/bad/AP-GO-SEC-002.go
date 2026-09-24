package slopguardtest

import (
	"context"
	"database/sql"
	"fmt"
)

// QueryUser constructs a query via fmt.Sprintf — gosec G201 → AP-GO-SEC-002.
// ruleid: slopguard.go.gosec.G201
func QueryUser(ctx context.Context, db *sql.DB, id string) error {
	query := fmt.Sprintf("SELECT * FROM users WHERE id = %s", id)
	_, err := db.ExecContext(ctx, query)
	return err
}
