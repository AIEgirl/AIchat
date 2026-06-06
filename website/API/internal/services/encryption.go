package services

import (
	"github.com/aichat/relay/internal/utils"
)

// EncryptionService 加密服务
type EncryptionService struct {
	aes *utils.AES
}

// NewEncryptionService 创建加密服务
func NewEncryptionService(aesKey string) (*EncryptionService, error) {
	aes, err := utils.NewAES(aesKey)
	if err != nil {
		return nil, err
	}
	return &EncryptionService{aes: aes}, nil
}

// Encrypt 加密
func (s *EncryptionService) Encrypt(plaintext string) (string, error) {
	return s.aes.Encrypt(plaintext)
}

// Decrypt 解密
func (s *EncryptionService) Decrypt(ciphertext string) (string, error) {
	return s.aes.Decrypt(ciphertext)
}

// EncryptAPIKey 加密API Key
func (s *EncryptionService) EncryptAPIKey(key string) (string, error) {
	return s.aes.Encrypt(key)
}

// DecryptAPIKey 解密API Key
func (s *EncryptionService) DecryptAPIKey(encrypted string) (string, error) {
	return s.aes.Decrypt(encrypted)
}
