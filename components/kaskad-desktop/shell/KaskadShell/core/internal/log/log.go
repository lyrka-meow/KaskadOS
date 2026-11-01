package log

import (
	kaskadlog "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/log"
)

type Logger = kaskadlog.Logger

func init() {
	kaskadlog.SetEnvPrefix("Kaskad")
}

func GetLogger() *Logger { return kaskadlog.GetLogger() }

func GetQtLoggingRules() string { return kaskadlog.GetQtLoggingRules() }

func SetLevel(level string) { kaskadlog.SetLevel(level) }

func SetLogFile(path string) error { return kaskadlog.SetLogFile(path) }

func ApplyEnvOverrides() { kaskadlog.ApplyEnvOverrides() }

func Debug(msg any, keyvals ...any)  { kaskadlog.Debug(msg, keyvals...) }
func Debugf(format string, v ...any) { kaskadlog.Debugf(format, v...) }
func Info(msg any, keyvals ...any)   { kaskadlog.Info(msg, keyvals...) }
func Infof(format string, v ...any)  { kaskadlog.Infof(format, v...) }
func Warn(msg any, keyvals ...any)   { kaskadlog.Warn(msg, keyvals...) }
func Warnf(format string, v ...any)  { kaskadlog.Warnf(format, v...) }
func Error(msg any, keyvals ...any)  { kaskadlog.Error(msg, keyvals...) }
func Errorf(format string, v ...any) { kaskadlog.Errorf(format, v...) }
func Fatal(msg any, keyvals ...any)  { kaskadlog.Fatal(msg, keyvals...) }
func Fatalf(format string, v ...any) { kaskadlog.Fatalf(format, v...) }
