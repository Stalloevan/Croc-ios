package crocmobile

import (
	"context"
	"errors"
	"io"
	"strings"
	"sync"

	"github.com/schollz/croc/v11/src/codephrase"
	"github.com/schollz/croc/v11/src/sshshare"
)

// TerminalSink receives the output of a shared SSH terminal. It is implemented
// in Swift.
type TerminalSink interface {
	// Write delivers raw terminal output (escape sequences included).
	Write(data []byte)
	// Status reports connection changes. state is one of "connecting",
	// "connected", "reconnecting", "ended" or "failed"; role is
	// "read-write" or "read-only" once known; message is a short sentence.
	Status(state, role, message string)
}

// SSHSession is a joined shared terminal.
type SSHSession struct {
	cancel context.CancelFunc
	input  *io.PipeWriter
	once   sync.Once
}

type sinkWriter struct{ sink TerminalSink }

func (w sinkWriter) Write(p []byte) (int, error) {
	if len(p) > 0 {
		buf := make([]byte, len(p))
		copy(buf, p)
		w.sink.Write(buf)
	}
	return len(p), nil
}

// ValidSSHCode reports whether text looks like a six-word SSH invitation.
func ValidSSHCode(code string) bool {
	_, err := codephrase.ParseSSH(normalizeCode(code))
	return err == nil
}

// JoinSSH joins a shared terminal with a six-word invitation. It returns at
// once; output and status arrive through the sink.
func JoinSSH(code, relay, relayPassword string, cols, rows int, sink TerminalSink) (*SSHSession, error) {
	code = normalizeCode(code)
	if code == "" {
		return nil, errors.New("an SSH code is required")
	}
	if _, err := codephrase.ParseSSH(code); err != nil {
		return nil, errors.New("that doesn't look like a valid SSH code")
	}
	if relayPassword == "" {
		relayPassword = DefaultRelayPassword
	}
	addr := ""
	if !isAutomaticRelay(relay) {
		addr, _, _ = resolveRelay(code, relay)
	}
	ctx, cancel := context.WithCancel(context.Background())
	pr, pw := io.Pipe()
	s := &SSHSession{cancel: cancel, input: pw}
	out := sinkWriter{sink}
	sink.Status("connecting", "", "Connecting…")
	go func() {
		err := sshshare.Join(ctx, sshshare.ClientConfig{
			Code:          code,
			RelayAddress:  addr,
			RelayPassword: relayPassword,
			Curve:         "p256",
			Input:         pr,
			Output:        out,
			ErrorOutput:   out,
			InitialSize:   sshshare.WindowSize{Width: cols, Height: rows},
			Reconnect:     true,
			TransportMode: sshshare.TransportModeRelay,
			OnEvent: func(e sshshare.JoinEvent) {
				switch e.State {
				case sshshare.JoinStateConnected:
					sink.Status("connected", string(e.Role), "Connected")
				case sshshare.JoinStateReconnecting:
					sink.Status("reconnecting", string(e.Role), "Connection lost. Reconnecting…")
				}
			},
		})
		switch {
		case ctx.Err() != nil, errors.Is(err, sshshare.ErrDetached):
			sink.Status("ended", "", "Disconnected")
		case err == nil:
			sink.Status("ended", "", "The host ended the shared terminal.")
		default:
			sink.Status("failed", "", friendlySSHError(err))
		}
		_ = pr.Close()
	}()
	return s, nil
}

func friendlySSHError(err error) string {
	text := strings.ToLower(err.Error())
	if strings.Contains(text, "secure channel") || strings.Contains(text, "pake") {
		return "Couldn't connect to the host. Check the code and try again."
	}
	return err.Error()
}

// SendInput types data into the shared terminal (ignored for read-only access).
func (s *SSHSession) SendInput(data []byte) {
	if s == nil || len(data) == 0 {
		return
	}
	_, _ = s.input.Write(data)
}

// Close leaves the shared terminal.
func (s *SSHSession) Close() {
	if s == nil {
		return
	}
	s.once.Do(func() {
		s.cancel()
		_ = s.input.Close()
	})
}
