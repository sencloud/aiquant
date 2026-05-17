package scheduler

import "encoding/json"

func jsonMarshalSafe(v any) ([]byte, error) { return json.Marshal(v) }
