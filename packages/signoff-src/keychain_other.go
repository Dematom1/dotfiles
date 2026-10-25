//go:build !darwin || !cgo

package main

import "errors"

func keychainSigner(string, string) func([]byte) ([]byte, error) {
	return func([]byte) ([]byte, error) {
		return nil, errors.New("keychain signing requires macOS and cgo")
	}
}
