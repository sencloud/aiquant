package platform

import (
	"errors"
	"net/http"
)

// APIError 是面向客户端的统一错误形态。
type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
	// Internal 仅写入服务端日志，不会下发给客户端。
	Internal error `json:"-"`
}

func (e *APIError) Error() string {
	if e.Internal != nil {
		return e.Code + ": " + e.Message + " (" + e.Internal.Error() + ")"
	}
	return e.Code + ": " + e.Message
}

func (e *APIError) Unwrap() error { return e.Internal }

func NewAPIError(status int, code, message string, internal error) *APIError {
	return &APIError{Status: status, Code: code, Message: message, Internal: internal}
}

// 常见错误工厂 — 所有 code 形如 "MODULE.REASON"，前端按 code 做 i18n。
func ErrBadRequest(code, msg string, err error) *APIError {
	return NewAPIError(http.StatusBadRequest, code, msg, err)
}
func ErrUnauthorized(code, msg string) *APIError {
	return NewAPIError(http.StatusUnauthorized, code, msg, nil)
}
func ErrForbidden(code, msg string) *APIError {
	return NewAPIError(http.StatusForbidden, code, msg, nil)
}
func ErrNotFound(code, msg string) *APIError {
	return NewAPIError(http.StatusNotFound, code, msg, nil)
}
func ErrConflict(code, msg string) *APIError {
	return NewAPIError(http.StatusConflict, code, msg, nil)
}
func ErrTooManyRequests(code, msg string) *APIError {
	return NewAPIError(http.StatusTooManyRequests, code, msg, nil)
}
func ErrInternal(code string, err error) *APIError {
	return NewAPIError(http.StatusInternalServerError, code, "internal error", err)
}

// AsAPIError 把任意 error 归一成 APIError。
func AsAPIError(err error) *APIError {
	if err == nil {
		return nil
	}
	var apiErr *APIError
	if errors.As(err, &apiErr) {
		return apiErr
	}
	return ErrInternal("INTERNAL", err)
}
