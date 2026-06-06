package middleware

import (
	"crypto/subtle"
	"strconv"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

var signatureCfg *config.SignatureConfig

// InitSignature 初始化签名配置
func InitSignature(cfg *config.SignatureConfig) {
	signatureCfg = cfg
}

// Signature 签名验证中间件
// 客户端需要传递以下Header:
//   X-Timestamp: 请求时间戳（秒）
//   X-Nonce: 随机字符串
//   X-Signature: HMAC-SHA256签名
// 签名内容: METHOD\nPATH\nTIMESTAMP\nNONCE\nBODY_HASH
func Signature() gin.HandlerFunc {
	return func(c *gin.Context) {
		if signatureCfg == nil || !signatureCfg.Enabled {
			c.Next()
			return
		}

		// 跳过公开接口
		skipPaths := []string{
			"/api/v1/auth/login", "/api/v1/auth/register",
			"/api/v1/auth/verify", "/api/v1/auth/reset",
			"/api/v1/payment/notify", "/health",
		}
		for _, p := range skipPaths {
			if c.Request.URL.Path == p {
				c.Next()
				return
			}
		}

		timestamp := c.GetHeader("X-Timestamp")
		nonce := c.GetHeader("X-Nonce")
		signature := c.GetHeader("X-Signature")

		if timestamp == "" || nonce == "" || signature == "" {
			signatureFail(c, nil, "missing_signature", "缺少签名参数")
			return
		}

		// 检查时间戳
		ts, err := strconv.ParseInt(timestamp, 10, 64)
		if err != nil {
			signatureFail(c, nil, "invalid_timestamp", "时间戳格式错误")
			return
		}
		tsTime := time.Unix(ts, 0)
		if time.Since(tsTime).Abs() > time.Duration(signatureCfg.ExpireSeconds)*time.Second {
			signatureFail(c, nil, "expired_signature", "签名已过期")
			return
		}

		// 重新计算签名
		body, _ := c.GetRawData()
		bodyHash := utils.HashSHA256(string(body))
		message := c.Request.Method + "\n" + c.Request.URL.Path + "\n" + timestamp + "\n" + nonce + "\n" + bodyHash

		// 从上下文中获取密钥（已认证的API Key）
		keySecret, _ := c.Get("api_key_secret")
		secret, _ := keySecret.(string)
		if secret == "" {
			signatureFail(c, nil, "no_key", "未找到密钥")
			return
		}

		expected := utils.HMACSign(message, secret)
		if subtle.ConstantTimeCompare([]byte(expected), []byte(signature)) != 1 {
			signatureFail(c, nil, "invalid_signature", "签名验证失败")
			return
		}

		c.Next()
	}
}

func signatureFail(c *gin.Context, db *gorm.DB, reason, message string) {
	utils.FailWithStatus(c, 401, 40101, message)

	// 记录异常
	if db != nil {
		uid, _ := c.Get("user_id")
		userID, _ := uid.(uint64)
		anomaly := &models.AnomalyDetection{
			Type:    "signature",
			IP:      c.ClientIP(),
			UserID:  &userID,
			Path:    c.Request.URL.Path,
			Reason:  reason + ": " + message,
			Level:   "warn",
			Blocked: false,
		}
		db.Create(anomaly)
	}
	c.Abort()
}
