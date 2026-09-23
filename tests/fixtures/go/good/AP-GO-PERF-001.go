package main

import (
	"context"
	"net/http"
	"time"
)

func fetchData(ctx context.Context, url string) (*http.Response, error) {
	// ok: slopguard.go.http-client-without-timeout
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: 10 * time.Second}
	return client.Do(req)
}

// ok: slopguard.go.http-client-without-timeout
var httpClient = &http.Client{
	Timeout: 30 * time.Second,
}
