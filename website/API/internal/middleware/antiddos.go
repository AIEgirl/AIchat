package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// AntiDDoSConfig 防DDoS配置
type AntiDDoSConfig struct {
	WindowSeconds    int     // 检测窗口
	MaxRequests      int     // 窗口内最大请求数
	BanSeconds       int     // 封禁时长
	Enabled          bool
}

// DDoSProtector DDoS防护器
type DDoSProtector struct {
	cfg     AntiDDoSConfig
	db      *gorm.DB
	mu      sync.RWMutex
	records map[string]*ipRecord
}

type ipRecord struct {
	count     int
	firstSeen time.Time
	banned    bool
	banUntil  time.Time
}

var ddosProtector *DDoSProtector

// InitAntiDDoS 初始化防DDoS
func InitAntiDDoS(db *gorm.DB, cfg AntiDDoSConfig) {
	if !cfg.Enabled {
		return
	}
	ddosProtector = &DDoSProtector{
		cfg:     cfg,
		db:      db,
		records: make(map[string]*ipRecord),
	}
	go ddosProtector.cleanupLoop()
}

// AntiDDoS 防DDoS中间件
func AntiDDoS() gin.HandlerFunc {
	return func(c *gin.Context) {
		if ddosProtector == nil {
			c.Next()
			return
		}

		ip := c.ClientIP()
		if ip == "" {
			c.Next()
			return
		}

		// 检查黑名单
		if ddosProtector.isBanned(ip) {
			c.JSON(http.StatusForbidden, gin.H{
				"code":    40300,
				"message": "IP已被封禁",
			})
			c.Abort()
			return
		}

		// 记录请求
		ddosProtector.record(ip, c)
		c.Next()
	}
}

func (d *DDoSProtector) record(ip string, c *gin.Context) {
	d.mu.Lock()
	defer d.mu.Unlock()

	now := time.Now()
	rec, exists := d.records[ip]
	if !exists {
		d.records[ip] = &ipRecord{count: 1, firstSeen: now}
		return
	}

	// 窗口过期，重置
	if now.Sub(rec.firstSeen) > time.Duration(d.cfg.WindowSeconds)*time.Second {
		rec.count = 1
		rec.firstSeen = now
		return
	}

	rec.count++
	if rec.count > d.cfg.MaxRequests {
		rec.banned = true
		rec.banUntil = now.Add(time.Duration(d.cfg.BanSeconds) * time.Second)

		// 写入黑名单
		banUntil := rec.banUntil
		go func() {
			d.db.Create(&models.IPBlacklist{
				IP:        ip,
				Reason:    "DDoS detection",
				ExpiresAt: &banUntil,
			})
			d.db.Create(&models.AnomalyDetection{
				Type:    "ddos",
				IP:      ip,
				Path:    c.Request.URL.Path,
				Reason:  "触发DDoS防护",
				Level:   "error",
				Blocked: true,
			})
		}()
	}
}

func (d *DDoSProtector) isBanned(ip string) bool {
	d.mu.RLock()
	rec, exists := d.records[ip]
	d.mu.RUnlock()
	if !exists {
		return false
	}
	if rec.banned && time.Now().After(rec.banUntil) {
		d.mu.Lock()
		rec.banned = false
		d.mu.Unlock()
		return false
	}
	return rec.banned
}

func (d *DDoSProtector) cleanupLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	for range ticker.C {
		d.mu.Lock()
		now := time.Now()
		for ip, rec := range d.records {
			if rec.banned && now.After(rec.banUntil) {
				delete(d.records, ip)
			} else if !rec.banned && now.Sub(rec.firstSeen) > 30*time.Minute {
				delete(d.records, ip)
			}
		}
		d.mu.Unlock()
	}
}
