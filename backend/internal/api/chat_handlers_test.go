package api

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/sencloud/finme-backend/internal/ai/chat"
)

func TestNormalizeChatImages(t *testing.T) {
	valid := "data:image/png;base64," + base64.StdEncoding.EncodeToString([]byte("fake-image"))

	t.Run("接受合法 data URL 并丢弃空项", func(t *testing.T) {
		got, err := normalizeChatImages([]string{"  ", valid})
		if err != nil {
			t.Fatalf("unexpected err: %v", err)
		}
		if len(got) != 1 || got[0] != valid {
			t.Fatalf("got %+v", got)
		}
	})

	t.Run("拒绝非 data URL", func(t *testing.T) {
		if _, err := normalizeChatImages([]string{"aGVsbG8="}); err == nil {
			t.Fatal("期望报错，但通过了")
		}
	})

	t.Run("拒绝坏 base64", func(t *testing.T) {
		if _, err := normalizeChatImages([]string{"data:image/png;base64,!!!not-base64!!!"}); err == nil {
			t.Fatal("期望报错，但通过了")
		}
	})

	t.Run("超出张数上限", func(t *testing.T) {
		tooMany := make([]string, chat.MaxImagesPerMessage+1)
		for i := range tooMany {
			tooMany[i] = valid
		}
		if _, err := normalizeChatImages(tooMany); err == nil {
			t.Fatal("期望张数超限报错，但通过了")
		}
	})

	t.Run("超出单张体积上限", func(t *testing.T) {
		huge := "data:image/png;base64," + strings.Repeat("A", chat.MaxImageDataURLLen)
		if _, err := normalizeChatImages([]string{huge}); err == nil {
			t.Fatal("期望体积超限报错，但通过了")
		}
	})
}
