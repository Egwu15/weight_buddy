// Package limits enforces per-user, per-kind daily quotas and the global daily
// spend cap.
package limits

import (
	"context"
	"sort"
)

// Kind is a metered AI feature. The string values are the stable identifiers
// used in the usage table, config and API responses.
type Kind string

const (
	KindTranscribe       Kind = "transcribe"
	KindParse            Kind = "parse"
	KindParseMeal        Kind = "parse_meal"
	KindParseExercise    Kind = "parse_exercise"
	KindChat             Kind = "chat"
	KindDistillMemories  Kind = "distill_memories"
	KindExtractExercises Kind = "extract_exercises"
)

// Tier is the daily allowance per kind for one subscription tier.
type Tier struct {
	Daily map[Kind]int
}

// Config is the full limits configuration: what each tier gets each day, and
// the estimated unit cost of each kind used for the global spend cap. It lives
// in code/config, never in the database.
type Config struct {
	Free  Tier
	Paid  Tier
	Costs map[Kind]float64
}

// Default returns the built-in limits used when no override is configured.
func Default() Config {
	return Config{
		Free: Tier{Daily: map[Kind]int{
			KindTranscribe:       10,
			KindParse:            20,
			KindParseMeal:        20,
			KindParseExercise:    20,
			KindChat:             20,
			KindDistillMemories:  20,
			KindExtractExercises: 20,
		}},
		Paid: Tier{Daily: map[Kind]int{
			KindTranscribe:       300,
			KindParse:            1000,
			KindParseMeal:        1000,
			KindParseExercise:    1000,
			KindChat:             1000,
			KindDistillMemories:  500,
			KindExtractExercises: 500,
		}},
		Costs: map[Kind]float64{
			KindTranscribe:       0.006,
			KindParse:            0.002,
			KindParseMeal:        0.002,
			KindParseExercise:    0.002,
			KindChat:             0.003,
			KindDistillMemories:  0.002,
			KindExtractExercises: 0.002,
		},
	}
}

// For returns the tier for a paid or free user.
func (c Config) For(paid bool) Tier {
	if paid {
		return c.Paid
	}
	return c.Free
}

// Limit returns the daily allowance for a kind, or 0 when the kind is unknown.
func (t Tier) Limit(kind Kind) int {
	return t.Daily[kind]
}

// Cost returns the estimated unit cost for a kind.
func (c Config) Cost(kind Kind) float64 {
	return c.Costs[kind]
}

// KindUsage is the per-kind remaining-allowance view returned by /v1/me.
type KindUsage struct {
	Kind      string `json:"kind"`
	Limit     int    `json:"limit"`
	Used      int    `json:"used"`
	Remaining int    `json:"remaining"`
}

// Store is the persistence the enforcer needs: today's usage per kind, a way
// to record usage, and the global daily spend.
type Store interface {
	UsageToday(ctx context.Context, userID, kind string) (float64, error)
	RecordUsage(ctx context.Context, userID, kind string, units, cost float64) error
	DailySpend(ctx context.Context) (float64, error)
}

// Enforcer applies the tier limits and the global spend cap.
type Enforcer struct {
	Store    Store
	Config   Config
	SpendCap float64
}

// Reason explains why a check allowed or refused a request.
type Reason string

const (
	ReasonOK       Reason = "ok"
	ReasonUserCap  Reason = "user_limit"
	ReasonSpendCap Reason = "spend_cap"
)

// Decision is the outcome of a limit check.
type Decision struct {
	Allowed bool
	Reason  Reason
	Limit   int
	Used    int
	Cost    float64
}

// Check reports whether a user may make one more call of the given kind. It is
// read-only; a successful call must be recorded separately with RecordUsage.
func (e *Enforcer) Check(ctx context.Context, userID string, paid bool, kind Kind) (Decision, error) {
	limit := e.Config.For(paid).Limit(kind)
	used, err := e.Store.UsageToday(ctx, userID, string(kind))
	if err != nil {
		return Decision{}, err
	}

	decision := Decision{Limit: limit, Used: int(used), Cost: e.Config.Cost(kind)}
	if limit > 0 && used >= float64(limit) {
		decision.Reason = ReasonUserCap
		return decision, nil
	}

	if e.SpendCap > 0 {
		spend, err := e.Store.DailySpend(ctx)
		if err != nil {
			return Decision{}, err
		}
		if spend >= e.SpendCap {
			decision.Reason = ReasonSpendCap
			return decision, nil
		}
	}

	decision.Allowed = true
	decision.Reason = ReasonOK
	return decision, nil
}

// RecordUsage logs one call of the given kind and its estimated cost.
func (e *Enforcer) RecordUsage(ctx context.Context, userID string, kind Kind, cost float64) error {
	return e.Store.RecordUsage(ctx, userID, string(kind), 1, cost)
}

// Remaining builds the per-kind remaining-allowance list for a user, for the
// /v1/me response.
func (e *Enforcer) Remaining(ctx context.Context, userID string, paid bool) ([]KindUsage, error) {
	tier := e.Config.For(paid)
	kinds := make([]Kind, 0, len(tier.Daily))
	for k := range tier.Daily {
		kinds = append(kinds, k)
	}
	sort.Slice(kinds, func(i, j int) bool { return kinds[i] < kinds[j] })

	out := make([]KindUsage, 0, len(kinds))
	for _, k := range kinds {
		limit := tier.Limit(k)
		used, err := e.Store.UsageToday(ctx, userID, string(k))
		if err != nil {
			return nil, err
		}
		remaining := limit - int(used)
		if remaining < 0 {
			remaining = 0
		}
		out = append(out, KindUsage{
			Kind:      string(k),
			Limit:     limit,
			Used:      int(used),
			Remaining: remaining,
		})
	}
	return out, nil
}

// SpendRemaining returns how much of the global daily cap is left, clamped at
// zero. It never reads negative.
func (e *Enforcer) SpendRemaining(ctx context.Context) (float64, error) {
	spend, err := e.Store.DailySpend(ctx)
	if err != nil {
		return 0, err
	}
	remaining := e.SpendCap - spend
	if remaining < 0 {
		remaining = 0
	}
	return remaining, nil
}
