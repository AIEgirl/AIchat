package middleware

import (
	"bytes"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/models"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// responseWriter 包装ResponseWriter以捕获响应
type responseWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (w *responseWriter) Write(b []byte) (int, error) {
	w.body.Write(b)
	return w.ResponseWriter.Write(b)
}

func (w *responseWriter) WriteString(s string) (int, error) {
	w.body.WriteString(s)
	return w.ResponseWriter.WriteString(s)
}

// LoggerConfig 日志配置
type LoggerConfig struct {
	DB            *gorm.DB
	LogBody       bool
	MaxBodySize   int
	SkipPaths     []string
	LogToFile     bool
	LogFilePath   string
}

// InitLogger 初始化日志
func InitLogger(cfg *config.LogConfig) {
	if cfg.File != "" {
		dir := filepath.Dir(cfg.File)
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			os.MkdirAll(dir, 0755)
		}
		logFile, err := os.OpenFile(cfg.File, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
		if err == nil {
			log.SetOutput(logFile)
		}
	}
	log.SetFlags(log.LstdFlags | log.Lmicroseconds | log.Lshortfile)
}

// Logger 日志中间件
func Logger(db *gorm.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 跳过路径
		skipPaths := []string{"/health", "/metrics", "/favicon.ico"}
		for _, p := range skipPaths {
			if c.Request.URL.Path == p {
				c.Next()
				return
			}
		}

		start := time.Now()
		traceID := c.GetHeader("X-Request-ID")
		if traceID == "" {
			traceID = uuid.New().String()
		}
		c.Set("trace_id", traceID)
		c.Writer.Header().Set("X-Request-ID", traceID)

		// 读取请求体
		var bodyBytes []byte
		if c.Request.Body != nil {
			bodyBytes, _ = io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewBuffer(bodyBytes))
		}

		// 包装ResponseWriter
		rw := &responseWriter{ResponseWriter: c.Writer, body: &bytes.Buffer{}}
		c.Writer = rw

		c.Next()

		duration := time.Since(start)

		// 异步保存日志
		go func() {
			userID, _ := c.Get("user_id")
			uid, _ := userID.(uint64)
			username, _ := c.Get("username")
			uname, _ := username.(string)

			// 控制台日志
			log.Printf("[%s] %s %s %d %v IP=%s UserID=%d",
				traceID, c.Request.Method, c.Request.URL.Path,
				c.Writer.Status(), duration, c.ClientIP(), uid)

			// 操作日志（仅API路径）
			if shouldLog(c.Request.URL.Path) && db != nil {
				logEntry := &models.OperationLog{
					UserID:     uid,
					Username:   uname,
					Module:     getModule(c.Request.URL.Path),
					Action:     c.Request.Method,
					Resource:   c.Request.URL.Path,
					IP:         c.ClientIP(),
					UserAgent:  c.Request.UserAgent(),
					Method:     c.Request.Method,
					Path:       c.Request.URL.Path,
					StatusCode: c.Writer.Status(),
					Request:    string(bodyBytes),
					Duration:   duration.Milliseconds(),
					CreatedAt:  time.Now(),
				}
				if len(logEntry.Request) > 2000 {
					logEntry.Request = logEntry.Request[:2000]
				}
				if rw.body.Len() > 0 && len(rw.body.String()) <= 2000 {
					logEntry.Response = rw.body.String()
				}
				db.Create(logEntry)
			}
		}()
	}
}

func shouldLog(path string) bool {
	// 仅记录API和管理操作
	return len(path) > 4 && (path[:5] == "/api/" || path[:5] == "/adm/")
}

func getModule(path string) string {
	parts := splitPath(path)
	if len(parts) > 2 {
		return parts[2]
	}
	return "default"
}

func splitPath(path string) []string {
	var parts []string
	start := 0
	for i, c := range path {
		if c == '/' {
			if i > start {
				parts = append(parts, path[start:i])
			}
			start = i + 1
		}
	}
	if start < len(path) {
		parts = append(parts, path[start:])
	}
	return parts
}
