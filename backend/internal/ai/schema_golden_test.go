package ai

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"testing"
)

// TestSchemaKeysMatchGolden pins the AI JSON schemas to the shared golden file
// that the Dart client also reads, so renaming a schema property cannot drift
// silently from the parser on the app side.
func TestSchemaKeysMatchGolden(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("testdata", "schema_keys.json"))
	if err != nil {
		t.Fatalf("read golden: %v", err)
	}
	var golden map[string][]string
	if err := json.Unmarshal(raw, &golden); err != nil {
		t.Fatalf("decode golden: %v", err)
	}

	cases := []struct {
		name   string
		schema json.RawMessage
		path   []string
	}{
		{"parse", ParseSchema, nil},
		{"parse_item", ParseSchema, []string{"properties", "items", "items"}},
		{"parse_exercise_item", ParseSchema, []string{"properties", "exercises", "items"}},
		{"memory", MemorySchema, nil},
		{"memory_item", MemorySchema, []string{"properties", "memories", "items"}},
		{"exercise", ExerciseSchema, nil},
		{"exercise_item", ExerciseSchema, []string{"properties", "recommendations", "items"}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := propertyNames(t, tc.schema, tc.path)
			want := append([]string(nil), golden[tc.name]...)
			if len(want) == 0 {
				t.Fatalf("golden has no keys for %q", tc.name)
			}
			sort.Strings(got)
			sort.Strings(want)
			if len(got) != len(want) {
				t.Fatalf("property count = %d (%v), golden = %d (%v)", len(got), got, len(want), want)
			}
			for i := range got {
				if got[i] != want[i] {
					t.Fatalf("property %d = %q, golden = %q", i, got[i], want[i])
				}
			}
		})
	}
}

// propertyNames walks to a nested schema node and returns its property names.
func propertyNames(t *testing.T, schema json.RawMessage, path []string) []string {
	t.Helper()
	var node map[string]any
	if err := json.Unmarshal(schema, &node); err != nil {
		t.Fatalf("decode schema: %v", err)
	}
	for _, key := range path {
		children, ok := node[key].(map[string]any)
		if !ok {
			t.Fatalf("schema has no object at path %v", path)
		}
		node = children
	}
	props, ok := node["properties"].(map[string]any)
	if !ok {
		t.Fatalf("schema node at %v has no properties", path)
	}
	names := make([]string, 0, len(props))
	for name := range props {
		names = append(names, name)
	}
	return names
}
