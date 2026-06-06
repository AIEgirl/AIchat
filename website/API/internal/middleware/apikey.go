package middleware

import (
	"strings"

	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/services"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// APIKeyVerifier API Key 验证
type APIKeyVerifier struct {
	db  *gorm.DB
	enc *services.EncryptionService
}

// NewAPIKeyVerifier 创建API Key验证器
func NewAPIKeyVerifier(db *gorm.DB, enc *services.EncryptionService) *APIKeyVerifier {
	return &APIKeyVerifier{db: db, enc: enc}
}

// Authenticate API Key 认证
func (v *APIKeyVerifier) Authenticate() gin.HandlerFunc {
	return func(c *gin.Context) {
		keyID := c.GetHeader("X-API-Key-ID")
		keySecret := c.GetHeader("X-API-Key-Secret")
		auth := c.GetHeader("Authorization")

		// Bearer ak_xxx:sk_xxx 格式
		if keyID == "" && strings.HasPrefix(auth, "Bearer ") {
			parts := strings.SplitN(strings.TrimPrefix(auth, "Bearer "), ":", 2)
			if len(parts) == 2 {
				keyID = parts[0]
				keySecret = parts[1]
			}
		}

		// 也支持 ak_xxx 直接作为Authorization
		if keyID == "" && strings.HasPrefix(auth, "Bearer ak_") {
			keyID = strings.TrimPrefix(auth, "Bearer ")
		}

		if keyID == "" {
			utils.Unauthorized(c, "缺少API Key")
			c.Abort()
			return
		}

		// 查询API Key
		var apiKey models.APIKey
		if err := v.db.Where("key_id = ?", keyID).First(&apiKey).Error; err != nil {
			utils.Unauthorized(c, "API Key不存在")
			c.Abort()
			return
		}

		// 验证密钥（如果提供）
		if keySecret != "" {
			decrypted, err := v.enc.DecryptAPIKey(apiKey.KeySecret)
			if err != nil || decrypted != keySecret {
				utils.Unauthorized(c, "API Key密钥错误")
				c.Abort()
				return
			}
		}

		// 检查有效性
		if !apiKey.IsValid() {
			utils.Unauthorized(c, "API Key已禁用或过期")
			c.Abort()
			return
		}

		// 查询用户
		var user models.User
		if err := v.db.First(&user, apiKey.UserID).Error; err != nil {
			utils.Unauthorized(c, "用户不存在")
			c.Abort()
			return
		}
		if !user.IsActive() {
			utils.Forbidden(c, "账户已禁用")
			c.Abort()
			return
		}

		// 设置上下文
		c.Set("user_id", user.ID)
		c.Set("uuid", user.UUID)
		c.Set("username", user.Username)
		c.Set("role", user.Role)
		c.Set("api_key_id", apiKey.ID)
		c.Set("api_key_secret", keySecret)
		_ = database.CheckPasswordHash // 避免未使用警告

		c.Next()
	}
}
