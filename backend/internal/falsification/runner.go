package falsification

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Runner 是「跑一次证伪」的上游适配器（alpha-radar）。
//
// alpha-radar 目前没有任务接口，默认用 StubRunner：只登记、不扣费，
// 状态 unsupported。alpha-radar 补齐下面这组接口后，把 config
// alpharadar.run_enabled 打开即切到 HTTPRunner：
//
//	POST {url}/api/runs/paid      X-Api-Key: {api_key}
//	     {"run_id":"<uuid>","strategy":"utbot","symbol":"P.DCE","freq":"5min"}
//	  →  202 {"job_id":"..."}
//	GET  {url}/api/runs/paid/{job_id}
//	  →  200 {"status":"queued|running|done|failed","error":"...",
//	          "result":{...一条与 /api/falsification archive 同形的条目...}}
//
// 付费任务应走单独的优先队列 / worker（现有 worker 串行且积压严重）。
type Runner interface {
	// Available 为 false 时不受理下单（不扣费）。
	Available() bool
	Submit(ctx context.Context, req RunRequest) (jobID string, err error)
	Status(ctx context.Context, jobID string) (*RunStatus, error)
}

// RunRequest 一次证伪任务。
type RunRequest struct {
	RunID    string `json:"run_id"`
	Strategy string `json:"strategy"`
	Symbol   string `json:"symbol"`
	Freq     string `json:"freq"`
}

// RunStatus 上游任务状态。
type RunStatus struct {
	Status string         `json:"status"`
	Error  string         `json:"error,omitempty"`
	Result map[string]any `json:"result,omitempty"`
}

// ErrRunnerUnsupported 上游还没有任务接口。
var ErrRunnerUnsupported = errors.New("alpha-radar run api not available")

// StubRunner 占位实现：alpha-radar 还没有任务接口。
type StubRunner struct{}

func (StubRunner) Available() bool { return false }
func (StubRunner) Submit(context.Context, RunRequest) (string, error) {
	return "", ErrRunnerUnsupported
}
func (StubRunner) Status(context.Context, string) (*RunStatus, error) {
	return nil, ErrRunnerUnsupported
}

// HTTPRunner 按上面约定的接口调用 alpha-radar。
type HTTPRunner struct {
	BaseURL string
	APIKey  string
	Client  *http.Client
}

func NewHTTPRunner(baseURL, apiKey string) *HTTPRunner {
	return &HTTPRunner{
		BaseURL: strings.TrimRight(baseURL, "/"),
		APIKey:  apiKey,
		Client:  &http.Client{Timeout: 15 * time.Second},
	}
}

func (h *HTTPRunner) Available() bool { return h != nil && h.BaseURL != "" }

func (h *HTTPRunner) Submit(ctx context.Context, req RunRequest) (string, error) {
	body, _ := json.Marshal(req)
	r, err := http.NewRequestWithContext(ctx, http.MethodPost, h.BaseURL+"/api/runs/paid", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	r.Header.Set("Content-Type", "application/json")
	if h.APIKey != "" {
		r.Header.Set("X-Api-Key", h.APIKey)
	}
	var out struct {
		JobID string `json:"job_id"`
	}
	if err := h.do(r, &out); err != nil {
		return "", err
	}
	if out.JobID == "" {
		return "", errors.New("alpha-radar: empty job_id")
	}
	return out.JobID, nil
}

func (h *HTTPRunner) Status(ctx context.Context, jobID string) (*RunStatus, error) {
	r, err := http.NewRequestWithContext(ctx, http.MethodGet,
		h.BaseURL+"/api/runs/paid/"+url.PathEscape(jobID), nil)
	if err != nil {
		return nil, err
	}
	if h.APIKey != "" {
		r.Header.Set("X-Api-Key", h.APIKey)
	}
	var out RunStatus
	if err := h.do(r, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func (h *HTTPRunner) do(r *http.Request, dst any) error {
	resp, err := h.Client.Do(r)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return fmt.Errorf("alpha-radar status %d: %s", resp.StatusCode, string(b))
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(dst)
}
