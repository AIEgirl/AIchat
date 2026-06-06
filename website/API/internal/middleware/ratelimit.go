package middleware

import (
	"sync"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
)

// TokenBucket 令牌桶
type TokenBucket struct {
	capacity   int
	tokens     float64
	refillRate float64 // 每秒补充的令牌数
	lastRefill time.Time
	mu         sync.Mutex
}

// NewTokenBucket 创建令牌桶
func NewTokenBucket(capacity int, refillRate float64) *TokenBucket {
	return &TokenBucket{
		capacity:   capacity,
		tokens:     float64(capacity),
		refillRate: refillRate,
		lastRefill: time.Now(),
	}
}

// Allow 是否允许通过
func (tb *TokenBucket) Allow() bool {
	tb.mu.Lock()
	defer tb.mu.Unlock()

	now := time.Now()
	elapsed := now.Sub(tb.lastRefill).Seconds()
	tb.tokens += elapsed * tb.refillRate
	if tb.tokens > float64(tb.capacity) {
		tb.tokens = float64(tb.capacity)
	}
	tb.lastRefill = now

	if tb.tokens >= 1 {
		tb.tokens--
		return true
	}
	return false
}

// Limiter 限流器
type Limiter struct {
	cfg      *config.RateLimitConfig
	global   *TokenBucket
	ipMap    sync.Map // IP -> *TokenBucket
	userMap  sync.Map // UserID -> *TokenBucket
}

var globalLimiter *Limiter

// InitLimiter 初始化限流器
func InitLimiter(cfg *config.RateLimitConfig) {
	if !cfg.Enabled {
		return
	}
	globalLimiter = &Limiter{
		cfg:    cfg,
		global: NewTokenBucket(cfg.GlobalRPS*2, float64(cfg.GlobalRPS)),
	}
}

// RateLimit 限流中间件
func RateLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		if globalLimiter == nil || !globalLimiter.cfg.Enabled {
			c.Next()
			return
		}

		// 全局限流
		if !globalLimiter.global.Allow() {
			utils.RateLimit(c, "服务繁忙，请稍后重试")
			c.Abort()
			return
		}

		// IP限流
		ip := c.ClientIP()
		if ip != "" {
			bucket, _ := globalLimiter.ipMap.LoadOrStore(ip, NewTokenBucket(globalLimiter.cfg.Burst, float64(globalLimiter.cfg.IPRPS)))
			if !bucket.(*TokenBucket).Allow() {
				utils.RateLimit(c, "IP请求过于频繁")
				c.Abort()
				return
			}
		}

		// 用户限流（已登录）
		if userID, exists := c.Get("user_id"); exists {
			key := ""
			switch v := userID.(type) {
			case uint64:
				key = string(rune(v))
			}
			if key != "" {
				bucket, _ := globalLimiter.userMap.LoadOrStore(key, NewTokenBucket(globalLimiter.cfg.Burst, float64(globalLimiter.cfg.UserRPS)))
				if !bucket.(*TokenBucket).Allow() {
					utils.RateLimit(c, "用户请求过于频繁")
					c.Abort()
					return
				}
			}
		}

		c.Next()
	}
}
