package httpapi

import (
	"context"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

// fakeStore is an in-memory Store for handler tests. It is deliberately simple:
// just enough behaviour to exercise the HTTP layer without a database.
type fakeStore struct {
	users         map[string]store.User // install id -> user
	signups       map[string]int        // ip hash -> count
	entitlements  map[string]store.Entitlement
	events        map[string]bool
	usage         map[string]float64 // userID + "|" + kind
	spend         float64
	signupErr     error
	createErr     error
	nextIDCounter int
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		users:        map[string]store.User{},
		signups:      map[string]int{},
		entitlements: map[string]store.Entitlement{},
		events:       map[string]bool{},
		usage:        map[string]float64{},
	}
}

func (f *fakeStore) UserByInstallID(_ context.Context, installID string) (store.User, error) {
	if u, ok := f.users[installID]; ok {
		return u, nil
	}
	return store.User{}, store.ErrNotFound
}

func (f *fakeStore) UserByID(_ context.Context, id string) (store.User, error) {
	for _, u := range f.users {
		if u.ID == id {
			return u, nil
		}
	}
	return store.User{}, store.ErrNotFound
}

func (f *fakeStore) CreateOrGetUser(_ context.Context, installID string) (store.User, bool, error) {
	if f.createErr != nil {
		return store.User{}, false, f.createErr
	}
	if u, ok := f.users[installID]; ok {
		return u, false, nil
	}
	f.nextIDCounter++
	u := store.User{ID: "user-" + installID, InstallID: installID, CreatedAt: time.Now()}
	f.users[installID] = u
	return u, true, nil
}

func (f *fakeStore) RegisterSignup(_ context.Context, ipHash string, cap int) (bool, error) {
	if f.signupErr != nil {
		return false, f.signupErr
	}
	f.signups[ipHash]++
	return f.signups[ipHash] <= cap, nil
}

func (f *fakeStore) Entitlement(_ context.Context, userID string) (store.Entitlement, error) {
	if e, ok := f.entitlements[userID]; ok {
		return e, nil
	}
	return store.Entitlement{}, store.ErrNotFound
}

func (f *fakeStore) UpsertEntitlement(_ context.Context, e store.Entitlement) error {
	f.entitlements[e.UserID] = e
	return nil
}

func (f *fakeStore) RecordRevenueCatEvent(_ context.Context, eventID string, _ []byte) (bool, error) {
	if f.events[eventID] {
		return false, nil
	}
	f.events[eventID] = true
	return true, nil
}

func (f *fakeStore) UsageToday(_ context.Context, userID, kind string) (float64, error) {
	return f.usage[userID+"|"+kind], nil
}

func (f *fakeStore) RecordUsage(_ context.Context, userID, kind string, units, cost float64) error {
	f.usage[userID+"|"+kind] += units
	f.spend += cost
	return nil
}

func (f *fakeStore) DailySpend(_ context.Context) (float64, error) {
	return f.spend, nil
}
