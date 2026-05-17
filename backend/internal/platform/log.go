package platform

import (
	"context"
	"os"
	"strings"
	"time"

	"github.com/rs/zerolog"
)

// NewLogger 创建结构化 JSON 日志（生产）或人类可读控制台日志（dev）。
func NewLogger(level, env string) zerolog.Logger {
	lvl := zerolog.InfoLevel
	switch strings.ToLower(level) {
	case "debug":
		lvl = zerolog.DebugLevel
	case "warn":
		lvl = zerolog.WarnLevel
	case "error":
		lvl = zerolog.ErrorLevel
	}
	zerolog.TimeFieldFormat = time.RFC3339Nano

	var l zerolog.Logger
	if env == "dev" {
		l = zerolog.New(zerolog.ConsoleWriter{Out: os.Stdout, TimeFormat: time.RFC3339}).
			Level(lvl).With().Timestamp().Logger()
	} else {
		l = zerolog.New(os.Stdout).Level(lvl).With().
			Timestamp().Str("svc", "finme-backend").Logger()
	}
	return l
}

// loggerKey 是 ctx 中存放 logger 的 key 类型。
type loggerKey struct{}

func WithLogger(ctx context.Context, l *zerolog.Logger) context.Context {
	return context.WithValue(ctx, loggerKey{}, l)
}

// LoggerFrom 返回 ctx 上挂的 logger，不存在时返回 Nop logger。
// zerolog 的 level 方法均为 pointer receiver，所以这里返回指针。
func LoggerFrom(ctx context.Context) *zerolog.Logger {
	if v, ok := ctx.Value(loggerKey{}).(*zerolog.Logger); ok {
		return v
	}
	nop := zerolog.Nop()
	return &nop
}
