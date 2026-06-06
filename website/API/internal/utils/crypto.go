package utils

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
)

// AES加密
type AES struct {
	key []byte
}

// NewAES 创建AES实例
func NewAES(key string) (*AES, error) {
	keyBytes := []byte(key)
	if len(keyBytes) != 32 {
		// 补足或截断到32字节
		k := make([]byte, 32)
		copy(k, keyBytes)
		keyBytes = k
	}
	return &AES{key: keyBytes}, nil
}

// Encrypt AES-GCM加密
func (a *AES) Encrypt(plaintext string) (string, error) {
	block, err := aes.NewCipher(a.key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ciphertext := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

// Decrypt AES-GCM解密
func (a *AES) Decrypt(ciphertext string) (string, error) {
	data, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(a.key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize {
		return "", errors.New("密文过短")
	}
	nonce, ciphertextBytes := data[:nonceSize], data[nonceSize:]
	plaintext, err := gcm.Open(nil, nonce, ciphertextBytes, nil)
	if err != nil {
		return "", err
	}
	return string(plaintext), nil
}

// GenerateAPIKey 生成API密钥
func GenerateAPIKey() (keyID, keySecret, preview string) {
	// 生成ak_xxx格式
	idBytes := make([]byte, 16)
	rand.Read(idBytes)
	keyID = "ak_" + hex.EncodeToString(idBytes)

	// 生成sk_xxx格式
	secretBytes := make([]byte, 32)
	rand.Read(secretBytes)
	keySecret = "sk_" + hex.EncodeToString(secretBytes)

	// 预览
	preview = keySecret[:8] + "***" + keySecret[len(keySecret)-4:]
	return
}

// HashSHA256 SHA256哈希
func HashSHA256(data string) string {
	hash := sha256.Sum256([]byte(data))
	return hex.EncodeToString(hash[:])
}

// HMACSign HMAC-SHA256签名
func HMACSign(message, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(message))
	return hex.EncodeToString(h.Sum(nil))
}

// HMACVerify HMAC验证
func HMACVerify(message, secret, signature string) bool {
	expected := HMACSign(message, secret)
	return hmac.Equal([]byte(expected), []byte(signature))
}

// GenerateSignature 生成请求签名
// 签名内容: METHOD + "\n" + PATH + "\n" + TIMESTAMP + "\n" + NONCE + "\n" + BODY_HASH
func GenerateSignature(method, path, timestamp, nonce, body string) string {
	bodyHash := HashSHA256(body)
	message := strings.ToUpper(method) + "\n" + path + "\n" + timestamp + "\n" + nonce + "\n" + bodyHash
	return message // HMAC在外部使用密钥签名
}

// GenerateOrderNo 生成订单号
func GenerateOrderNo() string {
	bytes := make([]byte, 8)
	rand.Read(bytes)
	return fmt.Sprintf("ORD%s%s", GetTimeString(), hex.EncodeToString(bytes))
}

// GetTimeString 获取时间字符串 YYYYMMDDHHMMSS
func GetTimeString() string {
	return strings.ReplaceAll(strings.ReplaceAll(strings.ReplaceAll(
		TimeNow().Format("2006-01-02T15:04:05.000Z07:00"), "-", ""), ":", ""), "T", "")[:14]
}
