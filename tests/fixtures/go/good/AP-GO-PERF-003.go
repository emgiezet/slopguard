package main

import "golang.org/x/sync/errgroup"

func processItems(items []string) error {
	// ok: slopguard.go.goroutine-per-item-unbounded
	eg := new(errgroup.Group)
	eg.SetLimit(8) // bounded concurrency

	for _, item := range items {
		item := item
		eg.Go(func() error {
			return process(item)
		})
	}
	return eg.Wait()
}

func process(s string) error { _ = s; return nil }
