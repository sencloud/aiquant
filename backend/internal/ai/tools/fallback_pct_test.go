package tools

import "testing"

func TestFuturesPctChg(t *testing.T) {
	if got := futuresPctChg(79, 9564); got != 0.83 {
		t.Fatalf("pct = %v, want 0.83", got)
	}
	if got := futuresPctChg(10, 0); got != 0 {
		t.Fatalf("pct with no pre_settle = %v", got)
	}
}

func TestHasDeliveryMonth(t *testing.T) {
	for code, want := range map[string]bool{
		"P2601.DCE": true, "RB2510.SHF": true, "SR601.ZCE": true,
		"P.DCE": false, "P_L.DCE": false, "RB.SHF": false, "": false,
	} {
		if got := hasDeliveryMonth(code); got != want {
			t.Errorf("hasDeliveryMonth(%q) = %v, want %v", code, got, want)
		}
	}
}
