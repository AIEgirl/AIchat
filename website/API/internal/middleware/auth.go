package middleware

import (
	"net/http"
	"strings"

	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
)

// JWTAuth JWT认证中间件
func JWTAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if auth == "" {
			auth = c.Query("token")
		}
		if auth == "" {
			utils.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}

		// 支持 "Bearer xxx" 格式
		parts := strings.SplitN(auth, " ", 2)
		tokenString := auth
		if len(parts) == 2 && parts[0] == "Bearer" {
			tokenString = parts[1]
		}

		claims, err := utils.ParseToken(tokenString)
		if err != nil {
			utils.Unauthorized(c, "Token无效或已过期")
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("uuid", claims.UUID)
		c.Set("username", claims.Username)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// AdminAuth 管理员权限中间件
func AdminAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			utils.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}
		if role != "admin" && role != "super_admin" {
			utils.Forbidden(c, "需要管理员权限")
			c.Abort()
			return
		}
		c.Next()
	}
}

// APIKeyAuth API密钥认证中间件
func APIKeyAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		keyID := c.GetHeader("X-API-Key-ID")
		keySecret := c.GetHeader("X-API-Key-Secret")
		auth := c.GetHeader("Authorization")

		if keyID == "" && strings.HasPrefix(auth, "Bearer ") {
			// Bearer ak_xxx:sk_xxx 格式
			parts := strings.SplitN(strings.TrimPrefix(auth, "Bearer "), ":", 2)
			if len(parts) == 2 {
				keyID = parts[0]
				keySecret = parts[1]
			}
		}

		if keyID == "" || keySecret == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"code":    40100,
				"message": "缺少API密钥",
			})
			c.Abort()
			return
		}

		// 验证API Key - 实际查询数据库
		// 这里将在处理器中完成
		c.Set("api_key_id", keyID)
		c.Set("api_key_secret", keySecret)
		c.Next()
	}
}
