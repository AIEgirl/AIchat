package middleware

import (
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
)

func JWTAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		t := c.GetHeader("Authorization")
		if t == "" {
			t = c.Query("token")
		}
		if len(t) > 7 && t[:7] == "Bearer " {
			t = t[7:]
		}
		if t == "" {
			utils.Unauthorized(c, "请先登录")
			c.Abort()
			return
		}
		claims, err := utils.ParseToken(t)
		if err != nil {
			utils.Unauthorized(c, "Token无效")
			c.Abort()
			return
		}
		c.Set("admin_id", claims.AdminID)
		c.Set("username", claims.Username)
		c.Set("role", claims.Role)
		c.Next()
	}
}

// SuperAdmin 超级管理员
func SuperAdmin() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get("role")
		if role != "super_admin" {
			utils.Forbidden(c, "需要超级管理员权限")
			c.Abort()
			return
		}
		c.Next()
	}
}
