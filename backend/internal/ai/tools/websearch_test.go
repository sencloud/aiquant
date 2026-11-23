package tools

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/websearch"
)

func TestWebSearchToolIsRegisteredAndDispatched(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, _ *http.Request) {
			_, _ = w.Write([]byte(`{"results":[{"title":"政策发布",` +
				`"url":"https://example.com/policy","site_name":"证监会"}]}`))
		}))
	defer server.Close()

	client := websearch.New("test-key", server.URL, time.Second)
	reg := BuildAll(Deps{WebSearch: client})
	if !reg.Has("search_web") {
		t.Fatalf("search_web not registered: %v", reg.Names())
	}

	raw := reg.Dispatch(
		context.Background(),
		"search_web",
		`{"query":"周末政策","ori_question":"周末有什么政策","count":5}`,
	)
	var out struct {
		Query   string             `json:"query"`
		Count   int                `json:"count"`
		Results []websearch.Result `json:"results"`
	}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		t.Fatalf("decode result: %v (%s)", err, raw)
	}
	if out.Query != "周末政策" || out.Count != 1 || len(out.Results) != 1 {
		t.Fatalf("result = %+v", out)
	}
	if out.Results[0].SiteName != "证监会" {
		t.Fatalf("result = %+v", out.Results[0])
	}
}
