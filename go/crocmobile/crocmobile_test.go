package crocmobile

import (
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/schollz/croc/v11/src/codephrase"
	"github.com/schollz/croc/v11/src/publicrelay"
	"github.com/schollz/croc/v11/src/tcp"
)

const testRelay = "127.0.0.1:9009"

var relayOnce sync.Once

// startRelay runs a private croc relay on 127.0.0.1:9009-9013.
func startRelay(t *testing.T) {
	t.Helper()
	relayOnce.Do(func() {
		ports := strings.Split(defaultPorts, ",")
		for _, p := range ports[1:] {
			go func(p string) { _ = tcp.Run("error", "127.0.0.1", p, DefaultRelayPassword) }(p)
		}
		go func() {
			_ = tcp.Run("error", "127.0.0.1", ports[0], DefaultRelayPassword, strings.Join(ports[1:], ","))
		}()
	})
	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		if c, err := net.Dial("tcp", testRelay); err == nil {
			c.Close()
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("test relay did not start")
}

func writeRandomFile(t *testing.T, dir, name string) (string, []byte) {
	t.Helper()
	data := make([]byte, 3<<20)
	if _, err := rand.Read(data); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return p, data
}

func waitErr(t *testing.T, ch chan error, what string) {
	t.Helper()
	select {
	case err := <-ch:
		if err != nil {
			t.Fatalf("%s: %v", what, err)
		}
	case <-time.After(90 * time.Second):
		t.Fatalf("%s: timed out", what)
	}
}

func checkFile(t *testing.T, dir, name string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatalf("received file missing: %v", err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("received file differs (%d bytes, want %d)", len(got), len(want))
	}
}

// App sends, app receives, through a private relay.
func TestLoopback(t *testing.T) {
	startRelay(t)
	src, dst := t.TempDir(), t.TempDir()
	file, data := writeRandomFile(t, src, "loop.bin")
	code, err := GenerateCode()
	if err != nil {
		t.Fatal(err)
	}

	sendErr := make(chan error, 1)
	go func() { sendErr <- Send(file, code, testRelay, "") }()
	time.Sleep(2 * time.Second)

	recvErr := make(chan error, 1)
	go func() { recvErr <- Receive(code, testRelay, "", dst) }()
	waitErr(t, recvErr, "receive")
	waitErr(t, sendErr, "send")
	checkFile(t, dst, "loop.bin", data)
}

// The relay must follow the code, like the croc CLI in public relay mode.
func TestRelayMapping(t *testing.T) {
	pool := publicrelay.Relays()
	if len(pool) == 0 {
		t.Fatal("empty public relay pool")
	}
	code := "mouth-ripen-baker"
	want, err := codephrase.RelayIndex(code, len(pool))
	if err != nil {
		t.Fatal(err)
	}
	for _, setting := range []string{"", "auto", "croc.schollz.com:9009", "  "} {
		got, err := RelayFor(code, setting)
		if err != nil {
			t.Fatal(err)
		}
		if got != pool[want] {
			t.Fatalf("setting %q: got %s, want %s", setting, got, pool[want])
		}
	}
	if got, _ := RelayFor(code, "my.relay.example"); got != "my.relay.example:9009" {
		t.Fatalf("custom relay: got %s", got)
	}
	if normalizeCode(" mouth ripen  baker ") != code {
		t.Fatal("normalizeCode did not join words")
	}
}

func TestDeclinedMapping(t *testing.T) {
	for _, in := range []string{"refusing files", "peer error: refusing files", "refused files"} {
		if got := mapError(errors.New(in)); got == nil || got.Error() != declinedMessage {
			t.Fatalf("%q mapped to %v", in, got)
		}
	}
	other := errors.New("relay connection failed")
	if mapError(other) != other {
		t.Fatal("unrelated errors must pass through")
	}
	if mapError(nil) != nil {
		t.Fatal("nil must stay nil")
	}
}

func TestSecureChannelRetry(t *testing.T) {
	for _, in := range []string{"could not secure channel", "room (secure channel) not ready, maybe peer disconnected"} {
		retry, final := shouldRetry(errors.New(in), 0)
		if !retry || final != nil {
			t.Fatalf("%q should be retried silently", in)
		}
		retry, final = shouldRetry(errors.New(in), maxSecureRetries)
		if retry || final == nil || strings.Contains(strings.ToLower(final.Error()), "secure channel") {
			t.Fatalf("after the cap the error must be generic, got %v", final)
		}
	}
	if retry, _ := shouldRetry(errors.New("password mismatch"), 0); retry {
		t.Fatal("a wrong code must not be retried")
	}
	if retry, final := shouldRetry(nil, 0); retry || final != nil {
		t.Fatal("success must pass through")
	}
	if _, final := shouldRetry(errors.New("refusing files"), 0); final == nil || final.Error() != declinedMessage {
		t.Fatal("declined must still be mapped")
	}
}

func cliPath(t *testing.T) string {
	t.Helper()
	p, err := exec.LookPath("croc")
	if err != nil {
		t.Skip("croc CLI not installed")
	}
	return p
}

// App sends, the real croc CLI receives.
func TestCLIReceivesFromApp(t *testing.T) {
	cli := cliPath(t)
	startRelay(t)
	src, dst := t.TempDir(), t.TempDir()
	file, data := writeRandomFile(t, src, "to-cli.bin")
	code, _ := GenerateCode()

	sendErr := make(chan error, 1)
	go func() { sendErr <- Send(file, code, testRelay, "") }()
	time.Sleep(2 * time.Second)

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, cli, "--relay", testRelay, "--pass", DefaultRelayPassword, "--yes")
	cmd.Dir = dst
	cmd.Env = append(os.Environ(), "CROC_SECRET="+code)
	out, err := cmd.CombinedOutput()
	t.Logf("croc CLI output:\n%s", out)
	if err != nil {
		t.Fatalf("croc CLI receive failed: %v", err)
	}
	waitErr(t, sendErr, "send")
	checkFile(t, dst, "to-cli.bin", data)
}

// The real croc CLI sends, the app receives.
func TestCLISendsToApp(t *testing.T) {
	cli := cliPath(t)
	startRelay(t)
	src, dst := t.TempDir(), t.TempDir()
	file, data := writeRandomFile(t, src, "from-cli.bin")
	code, _ := GenerateCode()

	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, cli, "--relay", testRelay, "--pass", DefaultRelayPassword, "--yes", "send", "--no-local", file)
	cmd.Env = append(os.Environ(), "CROC_SECRET="+code)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	time.Sleep(3 * time.Second)

	recvErr := make(chan error, 1)
	go func() { recvErr <- Receive(code, testRelay, "", dst) }()
	waitErr(t, recvErr, "receive")
	select {
	case <-done:
	case <-time.After(30 * time.Second):
	}
	t.Logf("croc CLI output:\n%s", out.String())
	checkFile(t, dst, "from-cli.bin", data)
}
