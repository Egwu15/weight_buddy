package httpapi

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/tedif/weight-buddy-backend/internal/store"
)

// fakeStore is an in-memory Store for handler tests. It is deliberately simple:
// just enough behaviour to exercise the HTTP layer without a database.
type fakeStore struct {
	users         map[string]store.User // install id -> user
	googleSubs    map[string]string     // google sub -> user id
	signups       map[string]int        // ip hash -> count
	entitlements  map[string]store.Entitlement
	events        map[string]bool
	usage         map[string]float64 // userID + "|" + kind
	spend         float64
	createErr     error
	nextIDCounter int
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		users:        map[string]store.User{},
		googleSubs:   map[string]string{},
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

func (f *fakeStore) CreateUserIfAllowed(_ context.Context, installID, ipHash string, cap int) (store.User, bool, bool, error) {
	if f.createErr != nil {
		return store.User{}, false, false, f.createErr
	}
	if u, ok := f.users[installID]; ok {
		// Known device: sign in without touching the cap.
		return u, false, true, nil
	}
	f.signups[ipHash]++
	if f.signups[ipHash] > cap {
		// Mirror the real transaction rollback: no user, no counter bump.
		f.signups[ipHash]--
		return store.User{}, false, false, nil
	}
	f.nextIDCounter++
	u := store.User{ID: "user-" + installID, InstallID: installID, CreatedAt: time.Now()}
	f.users[installID] = u
	return u, true, true, nil
}

// GoogleSignIn mirrors the store's precedence: returning subject, then link,
// then create. It is deterministic (handler tests do not need concurrency); the
// real atomicity is exercised against Postgres in the store package.
func (f *fakeStore) GoogleSignIn(_ context.Context, sub, installID, linkUserID string) (store.User, bool, error) {
	if f.createErr != nil {
		return store.User{}, false, f.createErr
	}
	if id, ok := f.googleSubs[sub]; ok {
		if u, found := f.userByID(id); found {
			return u, false, nil
		}
	}
	if linkUserID != "" {
		for key, u := range f.users {
			if u.ID == linkUserID && u.GoogleSub == nil {
				linked := sub
				u.GoogleSub = &linked
				f.users[key] = u
				f.googleSubs[sub] = u.ID
				return u, true, nil
			}
		}
	}
	if existing, ok := f.users[installID]; ok {
		if existing.GoogleSub != nil {
			return store.User{}, false, fmt.Errorf("google sign-in conflict")
		}
		linked := sub
		existing.GoogleSub = &linked
		f.users[installID] = existing
		f.googleSubs[sub] = existing.ID
		return existing, true, nil
	}
	f.nextIDCounter++
	linked := sub
	u := store.User{ID: "user-" + installID, InstallID: installID, GoogleSub: &linked, CreatedAt: time.Now()}
	f.users[installID] = u
	f.googleSubs[sub] = u.ID
	return u, false, nil
}

func (f *fakeStore) userByID(id string) (store.User, bool) {
	for _, u := range f.users {
		if u.ID == id {
			return u, true
		}
	}
	return store.User{}, false
}

func (f *fakeStore) Entitlement(_ context.Context, userID string) (store.Entitlement, error) {
	if e, ok := f.entitlements[userID]; ok {
		return e, nil
	}
	return store.Entitlement{}, store.ErrNotFound
}

func (f *fakeStore) RecordRevenueCatEvent(_ context.Context, eventID string, _ []byte) (bool, error) {
	if f.events[eventID] {
		return false, nil
	}
	f.events[eventID] = true
	return true, nil
}

func (f *fakeStore) ApplyEntitlementEvent(_ context.Context, eventID string, _ []byte, e store.Entitlement) (bool, error) {
	if f.events[eventID] {
		return false, nil
	}
	f.events[eventID] = true
	f.entitlements[e.UserID] = e
	return true, nil
}

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

func (f *fakeStore) DailySpend(_ context.Context) (float64, error) {
	return f.spend, nil
}
