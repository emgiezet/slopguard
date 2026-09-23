# AP-GO-SEC-003 — HTTP server without timeouts

**Category:** security | **Severity:** error | **CWE:** CWE-400
**Frameworks:** [plain, gin, echo]

## Summary
An HTTP server without explicit timeouts can be held open indefinitely by slow clients, exhausting goroutines and file descriptors. Set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, and `IdleTimeout` on every server.

## Do Not Write
http.ListenAndServe(":8080", mux)

## Instead Write
srv := &http.Server{Addr: ":8080", Handler: mux,
    ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second,
    WriteTimeout: 30 * time.Second, IdleTimeout: 120 * time.Second}
srv.ListenAndServe()

## References
- https://cwe.mitre.org/data/definitions/400.html
