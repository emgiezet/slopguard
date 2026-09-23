# AP-GO-MAINT-003 — context.Background() or TODO() used in request path

**Category:** maintainability | **Severity:** warn
**Frameworks:** [plain]

## Summary
Using `context.Background()` or `context.TODO()` inside a function that receives a request-scoped context breaks cancellation and deadline propagation. Thread the incoming `ctx` through all downstream calls.

## Do Not Write
func (s *Server) Handle(w http.ResponseWriter, r *http.Request) {
    result, _ := s.db.QueryContext(context.Background(), "SELECT …")
}

## Instead Write
func (s *Server) Handle(w http.ResponseWriter, r *http.Request) {
    result, err := s.db.QueryContext(r.Context(), "SELECT …")
}

