package crocmobile

import (
	"context"
	"errors"
	"io"
	"strings"
	"sync"
	"time"

	"github.com/schollz/croc/v11/src/codephrase"
	"github.com/schollz/croc/v11/src/sshshare"
)

// SSHSession is a joined shared terminal. The app pulls output and status
// with ReadOutput and NextStatus, each from its own loop.
type SSHSession struct {
	cancel context.CancelFunc
	input  *io.PipeWriter
	once   sync.Once
	out    chan []byte
	status chan string
	done   chan struct{}
}

func (s *SSHSession) emit(state, role, message string) {
	select {
	case s.status <- state + "|" + role + "|" + message:
	case <-s.done:
	}
}

type sessionWriter struct{ s *SSHSession }

func (w sessionWriter) Write(p []byte) (int, error) {
	if len(p) > 0 {
		buf := make([]byte, len(p))
		copy(buf, p)
		select {
		case w.s.out <- buf:
		case <-w.s.done:
		}
	}
	return len(p), nil
}

// ReadOutput blocks until terminal output is available. It returns nil once
// the session has ended and all output was read.
func (s *SSHSession) ReadOutput() []byte {
	select {
	case b := <-s.out:
		return b
	default:
	}
	select {
	case b := <-s.out:
		return b
	case <-s.done:
		select {
		case b := <-s.out:
			return b
		default:
			return nil
		}
	}
}

// NextStatus blocks for the next "state|role|message" update, where state is
// connecting, connected, reconnecting, ended or failed. Empty once finished.
func (s *SSHSession) NextStatus() string {
	select {
	case v := <-s.status:
		return v
	default:
	}
	select {
	case v := <-s.status:
		return v
	case <-s.done:
		select {
		case v := <-s.status:
			return v
		default:
			return ""
		}
	}
}

// ValidSSHCode reports whether text looks like a six-word SSH invitation.
func ValidSSHCode(code string) bool {
	_, err := codephrase.ParseSSH(normalizeCode(code))
	return err == nil
}

// JoinSSH joins a shared terminal with a six-word invitation. It returns at
// once; read output and status with ReadOutput and NextStatus.
func JoinSSH(code, relay, relayPassword string, cols, rows int) (*SSHSession, error) {
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
	s := &SSHSession{
		cancel: cancel, input: pw,
		out: make(chan []byte, 256), status: make(chan string, 16), done: make(chan struct{}),
	}
	out := sessionWriter{s}
	s.emit("connecting", "", "Connecting…")
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
					s.emit("connected", string(e.Role), "Connected")
				case sshshare.JoinStateReconnecting:
					s.emit("reconnecting", string(e.Role), "Connection lost. Reconnecting…")
				}
			},
		})
		switch {
		case ctx.Err() != nil, errors.Is(err, sshshare.ErrDetached):
			s.emit("ended", "", "Disconnected")
		case err == nil:
			s.emit("ended", "", "The host ended the shared terminal.")
		default:
			s.emit("failed", "", friendlySSHError(err))
		}
		_ = pr.Close()
		// Let the app drain what is queued, then signal the end.
		time.Sleep(200 * time.Millisecond)
		close(s.done)
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
