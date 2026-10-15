package limits

import (
	"context"
	"strings"
	"testing"
)

type fakeStore struct {
	usage map[string]float64
	spend float64
}

func newFakeStore() *fakeStore { return &fakeStore{usage: map[string]float64{}} }

func (f *fakeStore) UsageToday(_ context.Context, userID, kind string) (float64, error) {
	return f.usage[userID+"|"+kind], nil
}

func (f *fakeStore) UsageTodayByKind(_ context.Context, userID string) (map[string]float64, error) {
	out := map[string]float64{}
	prefix := userID + "|"
	for key, value := range f.usage {
		if strings.HasPrefix(key, prefix) {
			out[strings.TrimPrefix(key, prefix)] = value
		}
	}
	return out, nil
}

func (f *fakeStore) RecordUsage(_ context.Context, userID, kind string, units, cost float64) error {
	f.usage[userID+"|"+kind] += units
	f.spend += cost
	return nil
}

func (f *fakeStore) DailySpend(_ context.Context) (float64, error) { return f.spend, nil }

func testConfig() Config {
	return Config{
		Free:  Tier{Daily: map[Kind]int{KindTranscribe: 2}},
		Paid:  Tier{Daily: map[Kind]int{KindTranscribe: 100}},
		Costs: map[Kind]float64{KindTranscribe: 0.01},
	}
}

func TestCheckUserCap(t *testing.T) {
	fs := newFakeStore()
	e := &Enforcer{Store: fs, Config: testConfig(), SpendCap: 100}

	fs.usage["u|transcribe"] = 1
	d, err := e.Check(context.Background(), "u", false, KindTranscribe)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if !d.Allowed || d.Reason != ReasonOK {
		t.Fatalf("under the cap: %+v", d)
	}
	if d.Limit != 2 || d.Used != 1 || d.Cost != 0.01 {
		t.Fatalf("unexpected decision: %+v", d)
	}

	fs.usage["u|transcribe"] = 2
	d, err = e.Check(context.Background(), "u", false, KindTranscribe)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if d.Allowed || d.Reason != ReasonUserCap {
		t.Fatalf("at the cap: %+v", d)
	}
}

func TestCheckPaidTierIsHigher(t *testing.T) {
	fs := newFakeStore()
	e := &Enforcer{Store: fs, Config: testConfig(), SpendCap: 100}

	fs.usage["u|transcribe"] = 5 // over the free cap of 2
	d, err := e.Check(context.Background(), "u", true, KindTranscribe)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if !d.Allowed {
		t.Fatalf("paid user under cap 100 should be allowed: %+v", d)
	}
}

func TestCheckSpendCap(t *testing.T) {
	fs := newFakeStore()
	e := &Enforcer{Store: fs, Config: testConfig(), SpendCap: 5}

	fs.spend = 5
	d, err := e.Check(context.Background(), "u", true, KindTranscribe)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if d.Allowed || d.Reason != ReasonSpendCap {
		t.Fatalf("at the spend cap: %+v", d)
	}
}

func TestCheckZeroSpendCapDisablesCap(t *testing.T) {
	fs := newFakeStore()
	e := &Enforcer{Store: fs, Config: testConfig(), SpendCap: 0}
	fs.spend = 1000

	d, err := e.Check(context.Background(), "u", true, KindTranscribe)
	if err != nil {
		t.Fatalf("check: %v", err)
	}
	if !d.Allowed {
		t.Fatalf("spend cap 0 should disable the cap: %+v", d)
	}
}

func TestRemaining(t *testing.T) {
	fs := newFakeStore()
	cfg := Default()
	e := &Enforcer{Store: fs, Config: cfg, SpendCap: 100}
	fs.usage["u|transcribe"] = 3

	got, err := e.Remaining(context.Background(), "u", false)
	if err != nil {
		t.Fatalf("remaining: %v", err)
	}
	if len(got) != len(cfg.Free.Daily) {
		t.Fatalf("got %d kinds, want %d", len(got), len(cfg.Free.Daily))
	}
	for _, ku := range got {
		if ku.Kind == string(KindTranscribe) {
			if ku.Used != 3 || ku.Remaining != 7 || ku.Limit != 10 {
				t.Fatalf("transcribe usage = %+v, want 3 used of 10", ku)
			}
		}
	}
}

func TestSpendRemainingClampsAtZero(t *testing.T) {
	fs := newFakeStore()
	e := &Enforcer{Store: fs, Config: testConfig(), SpendCap: 5}
	fs.spend = 8

	got, err := e.SpendRemaining(context.Background())
	if err != nil {
		t.Fatalf("spend remaining: %v", err)
	}
	if got != 0 {
		t.Fatalf("remaining = %v, want 0", got)
	}
}
