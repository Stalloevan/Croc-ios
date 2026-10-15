// Package crocmobile is a small, gomobile-friendly wrapper around the croc
// file-transfer library so it can be called from Swift on iOS.
//
// gomobile can only bind exported functions that use basic types (string,
// bool, int, error), so all croc structs stay behind this boundary.
package crocmobile

import (
	"errors"
	"os"
	"strings"
	"sync"

	"github.com/schollz/croc/v11/src/codephrase"
	"github.com/schollz/croc/v11/src/croc"
)

const (
	// DefaultRelay is the public croc relay used when none is configured.
	DefaultRelay = "croc.schollz.com:9009"

	// DefaultRelayPassword is the password the public croc relay expects; the
	// croc CLI sends it unless told otherwise. An empty password is rejected
	// by the relay with "bad password".
	DefaultRelayPassword = "pass123"

	// defaultPorts matches the croc CLI's default relay ports.
	defaultPorts = "9009,9010,9011,9012,9013"
)

// transferMu serialises transfers. Receive changes the process working
// directory to choose where files land, so only one transfer may run at once.
var transferMu sync.Mutex

// GenerateCode returns a new random code phrase for a send.
func GenerateCode() (string, error) {
	return codephrase.Generate()
}

// Send offers the files listed in paths (newline-separated absolute paths)
// to a receiver that uses the same code, and blocks until the transfer ends.
func Send(paths, code, relay, relayPassword string) error {
	transferMu.Lock()
	defer transferMu.Unlock()

	list := splitPaths(paths)
	if len(list) == 0 {
		return errors.New("no files selected")
	}
	if strings.TrimSpace(code) == "" {
		return errors.New("a code phrase is required")
	}

	infos, emptyFolders, folderCount, err := croc.GetFilesInfo(list, false, false, nil)
	if err != nil {
		return err
	}

	c, err := croc.New(makeOptions(true, code, relay, relayPassword))
	if err != nil {
		return err
	}
	return c.Send(infos, emptyFolders, folderCount)
}

// Receive waits for a sender that uses the same code and saves the incoming
// files into destDir. It blocks until the transfer ends.
func Receive(code, relay, relayPassword, destDir string) error {
	transferMu.Lock()
	defer transferMu.Unlock()

	if strings.TrimSpace(code) == "" {
		return errors.New("a code phrase is required")
	}
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

	c, err := croc.New(makeOptions(false, code, relay, relayPassword))
	if err != nil {
		return err
	}
	return c.Receive()
}

// makeOptions builds croc options suited to a non-interactive mobile app:
// no prompts, no stdin, no terminal output, no clipboard, and no LAN
// discovery (which would need extra iOS local-network permissions).
func makeOptions(isSender bool, code, relay, relayPassword string) croc.Options {
	if strings.TrimSpace(relay) == "" {
		relay = DefaultRelay
	}
	if relayPassword == "" {
		relayPassword = DefaultRelayPassword
	}
	return croc.Options{
		IsSender:         isSender,
		SharedSecret:     strings.TrimSpace(code),
		RelayAddress:     relay,
		RelayPorts:       strings.Split(defaultPorts, ","),
		RelayPassword:    relayPassword,
		NoPrompt:         true,
		IgnoreStdin:      true,
		Quiet:            true,
		DisableLocal:     true,
		DisableClipboard: true,
		ShowQrCode:       false,
		Overwrite:        false,
		Rename:           true,
	}
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
