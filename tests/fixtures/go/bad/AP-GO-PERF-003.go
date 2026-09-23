package main

import "sync"

func processItems(items []string) {
	var wg sync.WaitGroup
	// ruleid: slopguard.go.goroutine-per-item-unbounded
	for _, item := range items {
		wg.Add(1)
		go func(i string) {
			defer wg.Done()
			process(i)
		}(item)
	}
	wg.Wait()
}

func process(s string) { _ = s }
