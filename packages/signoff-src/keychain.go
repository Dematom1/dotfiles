package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"fmt"
)

// fingerprint returns GitHub's App private key fingerprint for a PKCS#1 RSA
// public key: "SHA256:" and the base64 SHA-256 of its SubjectPublicKeyInfo DER.
func fingerprint(pkcs1 []byte) (string, error) {
	pub, err := x509.ParsePKCS1PublicKey(pkcs1)
	if err != nil {
		return "", err
	}
	spki, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(spki)
	return "SHA256:" + base64.StdEncoding.EncodeToString(sum[:]), nil
}

// matchKey returns the one distinct public key whose fingerprint is want.
func matchKey(publicKeys [][]byte, want string) ([]byte, error) {
	var match []byte
	for _, der := range publicKeys {
		fp, err := fingerprint(der)
		if err != nil || fp != want {
			continue
		}
		if match != nil && !bytes.Equal(match, der) {
			return nil, fmt.Errorf("two different keys match fingerprint %s", want)
		}
		match = der
	}
	if match == nil {
		return nil, fmt.Errorf("no RSA private key in the keychain matches fingerprint %s", want)
	}
	return match, nil
}
