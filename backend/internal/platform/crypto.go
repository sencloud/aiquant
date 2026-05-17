package platform

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"

	"golang.org/x/crypto/argon2"
)

// PhoneCrypto 提供手机号的 HMAC 索引 + AES-GCM 密文存储。
//
// HMAC：作为唯一索引，永不轮换。
// AES：加密存原值（admin 解密用）；密文格式 = 12B nonce || ciphertext || tag。
type PhoneCrypto struct {
	hmacKey []byte
	aesGCM  cipher.AEAD
}

func NewPhoneCrypto(hmacKeyB64, aesKeyB64 string) (*PhoneCrypto, error) {
	hkey, err := DecodeBase64Key(hmacKeyB64)
	if err != nil {
		return nil, fmt.Errorf("phone_hmac_key: %w", err)
	}
	akey, err := DecodeBase64Key(aesKeyB64)
	if err != nil {
		return nil, fmt.Errorf("phone_aes_key: %w", err)
	}
	block, err := aes.NewCipher(akey[:32])
	if err != nil {
		return nil, fmt.Errorf("aes new cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("gcm: %w", err)
	}
	return &PhoneCrypto{hmacKey: hkey, aesGCM: gcm}, nil
}

// HMAC 返回手机号的稳定哈希（hex）。
func (p *PhoneCrypto) HMAC(plain string) string {
	h := hmac.New(sha256.New, p.hmacKey)
	h.Write([]byte(plain))
	return hex.EncodeToString(h.Sum(nil))
}

// Encrypt 加密手机号（输出二进制，存到 BLOB 字段）。
func (p *PhoneCrypto) Encrypt(plain string) ([]byte, error) {
	nonce := make([]byte, p.aesGCM.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	out := p.aesGCM.Seal(nonce, nonce, []byte(plain), nil)
	return out, nil
}

// Decrypt 解密手机号。
func (p *PhoneCrypto) Decrypt(blob []byte) (string, error) {
	ns := p.aesGCM.NonceSize()
	if len(blob) < ns+16 {
		return "", errors.New("phone enc too short")
	}
	nonce := blob[:ns]
	ct := blob[ns:]
	out, err := p.aesGCM.Open(nil, nonce, ct, nil)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// HashPassword / VerifyPassword 用 argon2id（用户密码、SMS 验证码哈希）。
// 输出格式：argon2id$v=19$m=64MB,t=2,p=2$<saltB64>$<hashB64>
func HashPassword(plain string) (string, error) {
	salt := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(plain), salt, 2, 64*1024, 2, 32)
	return fmt.Sprintf(
		"argon2id$v=19$m=65536,t=2,p=2$%s$%s",
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	), nil
}

func VerifyPassword(plain, encoded string) bool {
	// 格式：argon2id$v=19$m=65536,t=2,p=2$<saltB64>$<hashB64>
	parts := strings.Split(encoded, "$")
	if len(parts) != 5 || parts[0] != "argon2id" {
		return false
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[3])
	if err != nil {
		return false
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false
	}
	got := argon2.IDKey([]byte(plain), salt, 2, 64*1024, 2, uint32(len(want)))
	return hmac.Equal(got, want)
}
