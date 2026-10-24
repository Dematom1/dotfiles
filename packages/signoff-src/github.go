package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

// apiBase is compiled in: a verdict is only as trustworthy as the API it was read from.
const apiBase = "https://api.github.com"

type api struct {
	base string
	auth string // full Authorization header value
}

type httpError struct {
	status  int
	request string
	body    string
}

func (e *httpError) Error() string {
	return fmt.Sprintf("%s: HTTP %d: %s", e.request, e.status, e.body)
}

func (a *api) do(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		data, err := json.Marshal(in)
		if err != nil {
			return err
		}
		body = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, a.base+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", a.auth)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 10<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		return &httpError{resp.StatusCode, method + " " + path, string(truncate(data, 500))}
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(data, out)
}

func (a *api) graphql(ctx context.Context, query string, vars map[string]any, out any) error {
	var resp struct {
		Data   json.RawMessage
		Errors []struct{ Message string }
	}
	if err := a.do(ctx, http.MethodPost, "/graphql", map[string]any{"query": query, "variables": vars}, &resp); err != nil {
		return err
	}
	if len(resp.Errors) > 0 {
		return fmt.Errorf("graphql: %s", resp.Errors[0].Message)
	}
	return json.Unmarshal(resp.Data, out)
}

// appJWT builds a GitHub App JWT. sign returns the RS256 (PKCS#1 v1.5, SHA-256)
// signature of its input; the private key never leaves the signing backend.
func appJWT(appID int64, sign func([]byte) ([]byte, error), now time.Time) (string, error) {
	enc := base64.RawURLEncoding
	claims, err := json.Marshal(map[string]any{
		"iat": now.Add(-time.Minute).Unix(),
		"exp": now.Add(9 * time.Minute).Unix(),
		"iss": strconv.FormatInt(appID, 10),
	})
	if err != nil {
		return "", err
	}
	signing := enc.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`)) + "." + enc.EncodeToString(claims)
	sig, err := sign([]byte(signing))
	if err != nil {
		return "", fmt.Errorf("sign app JWT: %w", err)
	}
	return signing + "." + enc.EncodeToString(sig), nil
}

func truncate(b []byte, n int) []byte {
	if len(b) <= n {
		return b
	}
	return b[:n]
}
