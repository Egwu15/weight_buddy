package ai

import (
	"encoding/json"
	"fmt"
	"time"
)

// ParseSystemPrompt returns the meal/exercise parsing system prompt with the
// server's local time. Prefer ParseSystemPromptText with the user's device
// time, which is what actually determines breakfast vs dinner.
func ParseSystemPrompt(now time.Time) string {
	return ParseSystemPromptText(now.Format("15:04"))
}

// ParseSystemPromptText returns the parsing system prompt for a caller-supplied
// local wall clock (HH:MM), so meal classification uses the user's timezone
// rather than the server's.
func ParseSystemPromptText(hhmm string) string {
	return fmt.Sprintf(
		"The current local time is %s. Use it to classify each food "+
			"entry as breakfast, lunch, dinner or snack (a snack is something "+
			"small eaten between meals). Exercises have no meal type (null). %s",
		hhmm, parseSystemPromptBody)
}

const parseSystemPromptBody = `
You turn spoken meal and exercise descriptions into a structured log.
For meals, break the food into individual items with estimated portion
sizes, calories and macros (protein, carbs, fat in grams). Estimate
reasonably when the speaker does not give amounts.
For exercises, list every distinct activity the speaker mentions as its
own entry in the exercises array, each with its sets and reps (when the
speaker gives reps) and its duration in minutes (when the speaker gives
a time). Never merge exercises together and never drop one — if the person
says "5 knee press-ups and 5 dips", both exercises belong in the array.
Never estimate calories: the app computes the burn itself from the sets,
reps and duration, so always set estimated_calories_burned to null.
Be accurate about the spirit of what was said; do not invent items that
were not mentioned. Use the schema exactly. Return JSON only.`

// ParseSchema is the strict JSON Schema for a parsed meal or exercise log.
var ParseSchema = json.RawMessage(`{
  "type": "object",
  "additionalProperties": false,
  "required": ["entry_type","summary","meal_type","items","total_calories","total_protein_g","total_carbs_g","total_fat_g","activity","duration_minutes","estimated_calories_burned","exercises"],
  "properties": {
    "entry_type": {"enum": ["meal", "exercise"], "type": "string"},
    "summary": {"type": "string"},
    "meal_type": {"type": ["string","null"], "enum": ["breakfast","lunch","dinner","snack",null]},
    "items": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name","quantity","calories","protein_g","carbs_g","fat_g"],
        "properties": {
          "name": {"type": "string"},
          "quantity": {"type": "string"},
          "calories": {"type": "number"},
          "protein_g": {"type": "number"},
          "carbs_g": {"type": "number"},
          "fat_g": {"type": "number"}
        }
      }
    },
    "total_calories": {"type": "number"},
    "total_protein_g": {"type": "number"},
    "total_carbs_g": {"type": "number"},
    "total_fat_g": {"type": "number"},
    "activity": {"type": ["string","null"]},
    "duration_minutes": {"type": ["number","null"]},
    "estimated_calories_burned": {"type": ["number","null"]},
    "exercises": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name","sets","reps","duration_minutes","estimated_calories_burned"],
        "properties": {
          "name": {"type": "string"},
          "sets": {"type": ["integer","null"]},
          "reps": {"type": ["integer","null"]},
          "duration_minutes": {"type": ["number","null"]},
          "estimated_calories_burned": {"type": ["number","null"]}
        }
      }
    }
  }
}`)

// MemorySystemPrompt reviews a coaching exchange and distils durable facts.
const MemorySystemPrompt = `
You review coaching conversations and distil what is worth remembering
about this person into short, stable facts that will help future
conversations. A "topic" is a stable identifier for one fact (for example
"training_goal" or "workout_preference"). Keep content to one clear
sentence. Only output "create" for genuinely new facts, "update" when the
conversation changes an existing fact, and "remove" when the person clearly
says an old fact is no longer true. Do not invent facts that were not said.
Use the schema exactly. Return JSON only.`

// MemorySchema is the strict schema for distilled memories.
var MemorySchema = json.RawMessage(`{
  "type": "object",
  "additionalProperties": false,
  "required": ["memories"],
  "properties": {
    "memories": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["topic","content","category","action"],
        "properties": {
          "topic": {"type": "string"},
          "content": {"type": "string"},
          "category": {"enum": ["goal","preference","pattern","fact","note"], "type": "string"},
          "action": {"enum": ["create","update","remove"], "type": "string"}
        }
      }
    }
  }
}`)

// ExerciseSystemPrompt scans a coaching exchange for actionable exercises.
const ExerciseSystemPrompt = `
You scan coaching conversations for concrete exercise recommendations the
coach gave. Only extract exercises that are specific enough to act on
(named, with at least one of sets, reps, rest or duration). Extract routine
groupings into plan_name when the coach presents a named plan (for example
"Leg Day A"). Set has_exercise_advice to false when the conversation is not
about exercises. Use the schema exactly. Return JSON only.`

// ExerciseSchema is the strict schema for extracted recommendations.
var ExerciseSchema = json.RawMessage(`{
  "type": "object",
  "additionalProperties": false,
  "required": ["has_exercise_advice","recommendations"],
  "properties": {
    "has_exercise_advice": {"type": "boolean"},
    "recommendations": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name","description","muscle_groups","difficulty","plan_name","sets","reps","rest_seconds","duration_minutes"],
        "properties": {
          "name": {"type": "string"},
          "description": {"type": "string"},
          "muscle_groups": {"type": "array", "items": {"type": "string"}},
          "difficulty": {"enum": ["beginner","intermediate","advanced"], "type": "string"},
          "plan_name": {"type": "string"},
          "sets": {"type": ["integer","null"]},
          "reps": {"type": ["integer","null"]},
          "rest_seconds": {"type": ["integer","null"]},
          "duration_minutes": {"type": ["integer","null"]}
        }
      }
    }
  }
}`)
