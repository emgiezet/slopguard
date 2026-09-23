package main

import (
	"fmt"
	"net/http"
)

func fetchData(url string) ([]byte, error) {
	// ruleid: slopguard.go.http-client-without-timeout
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	fmt.Println(resp.Status)
	return nil, nil
}

func fetchWithClient(url string) (*http.Response, error) {
	// ruleid: slopguard.go.http-client-without-timeout
	client := &http.Client{}
	return client.Get(url)
}
