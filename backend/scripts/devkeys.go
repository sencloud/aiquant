// Build tag 排除主构建。运行：
//   go run ./scripts/devkeys.go
//
// 输出三段 base64 32 字节随机密钥，复制粘贴到 config.toml 的 [security] 段。

//go:build ignore

package main

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
)

func main() {
	for _, name := range []string{"jwt_secret", "phone_hmac_key", "phone_aes_key"} {
		b := make([]byte, 32)
		_, _ = rand.Read(b)
		fmt.Printf("%s = \"%s\"\n", name, base64.StdEncoding.EncodeToString(b))
	}
}
