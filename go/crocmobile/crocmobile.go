// Package crocmobile is a small, gomobile-friendly wrapper around the croc
// file-transfer library so it can be called from Swift on iOS.
//
// gomobile can only bind exported functions that use basic types (string,
// bool, int, error), so all croc structs stay behind this boundary.
//
// The options below deliberately mirror what the croc command-line client
// sets, so that this app and other croc clients (CLI, web) can talk to each
// other: same PAKE curve, same hash, same default relay password and, most
// importantly, the same way of choosing a relay.
package crocmobile

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/schollz/croc/v11/src/codephrase"
	"github.com/schollz/croc/v11/src/croc"
	"github.com/schollz/croc/v11/src/publicrelay"
)

const (
	// DefaultRelayPassword is the password the public croc relays expect; the
	// croc CLI sends it unless told otherwise. An empty password is rejected
	// by a relay with "bad password".
	DefaultRelayPassword = "pass123"

	// defaultPorts matches the croc CLI's default relay ports.
	defaultPorts = "9009,9010,9011,9012,9013"

	defaultRelayPort = "9009"
	multicastAddress = "239.255.255.250"
)

// receiveMu serialises receives: Receive changes the process working
// directory to choose where files land.
var receiveMu sync.Mutex

// GenerateCode returns a new random code phrase for a send.
func GenerateCode() (string, error) {
	return codephrase.Generate()
}

// RelayFor reports which relay a transfer with this code and relay setting
// would use. An empty relay (or the old default, croc.schollz.com) means
// "public relay mode": like the croc CLI, the relay is derived from a hash of
// the code, so both sides land on the same one without any coordination.
func RelayFor(code, relay string) (string, error) {
	addr, _, err := resolveRelay(normalizeCode(code), relay)
	return addr, err
}

// Send offers the files listed in paths (newline-separated absolute paths)
// to a receiver that uses the same code, and blocks until the transfer ends.
func Send(paths, code, relay, relayPassword string) error {
	list := splitPaths(paths)
	if len(list) == 0 {
		return errors.New("no files selected")
	}
	code = normalizeCode(code)
	if code == "" {
		return errors.New("a code phrase is required")
	}

	opts, err := makeOptions(true, code, relay, relayPassword)
	if err != nil {
		return err
	}

	for attempt := 0; ; attempt++ {
		infos, emptyFolders, folderCount, err := croc.GetFilesInfo(list, false, false, nil)
		if err != nil {
			return err
		}
		c, err := croc.New(opts)
		if err != nil {
			return err
		}
		err = c.Send(infos, emptyFolders, folderCount)
		if retry, final := shouldRetry(err, attempt); retry {
			time.Sleep(retryDelay)
			continue
		} else {
			return final
		}
	}
}

// Receive waits for a sender that uses the same code and saves the incoming
// files into destDir. It blocks until the transfer ends.
func Receive(code, relay, relayPassword, destDir string) error {
	code = normalizeCode(code)
	if code == "" {
		return errors.New("a code phrase is required")
	}
	opts, err := makeOptions(false, code, relay, relayPassword)
	if err != nil {
		return err
	}

	receiveMu.Lock()
	defer receiveMu.Unlock()

	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return err
	}
	previous, err := os.Getwd()
	if err != nil {
		return err
	}
	if err := os.Chdir(destDir); err != nil {
		return err
	}
	defer func() { _ = os.Chdir(previous) }()

	for attempt := 0; ; attempt++ {
		c, err := croc.New(opts)
		if err != nil {
			return err
		}
		err = c.Receive()
		if retry, final := shouldRetry(err, attempt); retry {
			time.Sleep(retryDelay)
			continue
		} else {
			return final
		}
	}
}

const (
	// retryDelay is a short pause so a failing relay is not hammered in a tight loop.
	retryDelay = 250 * time.Millisecond
	// maxSecureRetries bounds the silent retries of "could not secure channel".
	maxSecureRetries = 10
	// connectFailedMessage is shown if the silent retries all fail.
	connectFailedMessage = "Couldn't connect to the other device. Check the code and try again."
)

// isSecureChannelError matches croc's "could not secure channel" family. These
// happen when a connection drops before the key exchange finishes (a stray or
// half-open connection), and succeed on an immediate retry. A wrong code is a
// different error ("password mismatch") and is not matched here.
func isSecureChannelError(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "secure channel")
}

// shouldRetry decides what to do with the result of one attempt: retry quietly
// for secure-channel errors, otherwise return the (mapped) final result.
func shouldRetry(err error, attempt int) (retry bool, final error) {
	if isSecureChannelError(err) {
		if attempt < maxSecureRetries {
			return true, nil
		}
		return false, errors.New(connectFailedMessage)
	}
	return false, mapError(err)
}

// declinedMessage is the stable text the app looks for to tell "the receiver
// said no" apart from a real failure.
const declinedMessage = "transfer declined by the receiver"

// mapError turns croc's refusal errors into declinedMessage.
func mapError(err error) error {
	if err == nil {
		return nil
	}
	text := err.Error()
	if strings.Contains(text, "refusing files") || strings.Contains(text, "refused files") {
		return errors.New(declinedMessage)
	}
	return err
}

// resolveRelay returns the relay address to use and whether it came from the
// public relay pool.
func resolveRelay(code, relay string) (addr string, public bool, err error) {
	if isAutomaticRelay(relay) {
		pool := publicrelay.Relays()
		idx, err := codephrase.RelayIndex(code, len(pool))
		if err != nil {
			return "", false, fmt.Errorf("could not choose a public relay: %w", err)
		}
		return pool[idx], true, nil
	}
	addr = strings.TrimSpace(relay)
	if !strings.Contains(addr, ":") {
		addr += ":" + defaultRelayPort
	}
	return addr, false, nil
}

// isAutomaticRelay is true for an empty setting and for the old built-in
// default that earlier versions of the app saved.
func isAutomaticRelay(relay string) bool {
	switch strings.ToLower(strings.TrimSpace(relay)) {
	case "", "auto", "automatic", "croc.schollz.com", "croc.schollz.com:9009":
		return true
	}
	return false
}

// makeOptions builds croc options suited to a non-interactive mobile app:
// no prompts, no stdin, no terminal output, no clipboard, and no LAN
// discovery (which would need extra iOS local-network permissions).
func makeOptions(isSender bool, code, relay, relayPassword string) (croc.Options, error) {
	addr, public, err := resolveRelay(code, relay)
	if err != nil {
		return croc.Options{}, err
	}
	if relayPassword == "" {
		relayPassword = DefaultRelayPassword
	}
	return croc.Options{
		IsSender:         isSender,
		SharedSecret:     code,
		RelayAddress:     addr,
		RelayAddress6:    "",
		PublicRelay:      public,
		RelayPorts:       strings.Split(defaultPorts, ","),
		RelayPassword:    relayPassword,
		Curve:            "p256",
		HashAlgorithm:    "xxhash",
		MulticastAddress: multicastAddress,
		Transport:        croc.TransportAuto,
		NoPrompt:         true,
		IgnoreStdin:      true,
		Quiet:            true,
		DisableLocal:     true,
		DisableClipboard: true,
		ShowQrCode:       false,
		Overwrite:        false,
		Rename:           true,
	}, nil
}

// normalizeCode trims the code and joins words typed with spaces, as the croc
// CLI does when a code is given as several arguments.
func normalizeCode(code string) string {
	return strings.Join(strings.Fields(code), "-")
}

func splitPaths(paths string) []string {
	var out []string
	for _, line := range strings.Split(paths, "\n") {
		if p := strings.TrimSpace(line); p != "" {
			out = append(out, p)
		}
	}
	return out
}
