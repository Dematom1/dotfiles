package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"os"
	"strings"
	"testing"
)

// fixtureFingerprint was computed independently with
// openssl rsa -pubout -outform DER | openssl dgst -sha256 -binary | base64.
const fixtureFingerprint = "SHA256:Aph2n+nzhkv5Xwe76Y+Lw9ce3M4pKkg4m6lyjwLc9C4="

func fixturePublicKey(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile("testdata/public-key-pkcs1.pem")
	if err != nil {
		t.Fatal(err)
	}
	block, _ := pem.Decode(data)
	if block == nil || block.Type != "RSA PUBLIC KEY" {
		t.Fatalf("fixture is not a PKCS#1 public key")
	}
	return block.Bytes
}

func TestFingerprintMatchesGitHubFormat(t *testing.T) {
	got, err := fingerprint(fixturePublicKey(t))
	if err != nil {
		t.Fatal(err)
	}
	if got != fixtureFingerprint {
		t.Errorf("fingerprint %s, want %s", got, fixtureFingerprint)
	}
}

func TestMatchKey(t *testing.T) {
	fixture := fixturePublicKey(t)
	other, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	otherDER := x509.MarshalPKCS1PublicKey(&other.PublicKey)

	got, err := matchKey([][]byte{otherDER, []byte("not a key"), fixture}, fixtureFingerprint)
	if err != nil || string(got) != string(fixture) {
		t.Errorf("matchKey(%q) = %v", fixtureFingerprint, err)
	}
	// The same key listed twice (e.g. imported twice) is still one key.
	if _, err := matchKey([][]byte{fixture, fixture}, fixtureFingerprint); err != nil {
		t.Errorf("duplicate listing: %v", err)
	}
	if _, err := matchKey([][]byte{otherDER}, fixtureFingerprint); err == nil || !strings.Contains(err.Error(), "no RSA private key") {
		t.Errorf("no match: %v", err)
	}
	if _, err := matchKey([][]byte{otherDER}, ""); err == nil {
		t.Error("an empty fingerprint must not match")
	}
}
