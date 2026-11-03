package realtime

import (
	"testing"
	"time"
)

func TestParseTencentTimeUsesChinaStandardTime(t *testing.T) {
	got := parseTencentTime("20261103113823")
	want := time.Date(
		2026, 11, 3, 11, 38, 23, 0,
		time.FixedZone("CST", 8*60*60),
	).Unix()
	if got != want {
		t.Fatalf("parseTencentTime = %d, want %d", got, want)
	}
	if parseTencentTime("bad") != 0 {
		t.Fatal("invalid timestamp should return zero")
	}
}
