package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/middleware"
	"github.com/aichat/relay/internal/router"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
)

func main() {
	// 解析命令行参数
	configPath := flag.String("config", "config/config.yaml", "配置文件路径")
	flag.Parse()

	// 加载配置
	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	// 设置Gin模式
	gin.SetMode(cfg.Server.Mode)

	// 初始化JWT
	utils.InitJWT(&cfg.JWT)

	// 初始化数据库
	db, err := database.Init(&cfg.Database)
	if err != nil {
		log.Fatalf("初始化数据库失败: %v", err)
	}

	// 初始化日志
	middleware.InitLogger(&cfg.Log)

	// 创建Gin引擎
	r := gin.New()
	r.Use(middleware.Recovery())
	r.Use(middleware.CORS())
	r.Use(middleware.Logger(db))
	r.Use(middleware.RateLimit())
	r.Use(middleware.AntiDDoS())

	// 静态资源
	workDir, _ := os.Getwd()
	uploadDir := filepath.Join(workDir, "uploads")
	os.MkdirAll(uploadDir, 0755)

	// 设置路由
	router.Setup(r, db, cfg)

	// 创建HTTP服务器
	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      r,
		ReadTimeout:  time.Duration(cfg.Server.ReadTimeout) * time.Second,
		WriteTimeout: time.Duration(cfg.Server.WriteTimeout) * time.Second,
	}

	// 启动服务器
	go func() {
		log.Printf("===========================================")
		log.Printf("  AI中转服务平台启动")
		log.Printf("  端口: %d", cfg.Server.Port)
		log.Printf("  模式: %s", cfg.Server.Mode)
		log.Printf("  数据库: %s", cfg.Database.Driver)
		log.Printf("  时间: %s", time.Now().Format("2006-01-02 15:04:05"))
		log.Printf("===========================================")
		log.Printf("  管理员账户: admin / Admin@123")
		log.Printf("  API文档: http://localhost:%d/health", cfg.Server.Port)
		log.Printf("===========================================")

		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("服务器启动失败: %v", err)
		}
	}()

	// 等待中断信号
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("正在关闭服务器...")

	// 优雅关闭
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("服务器强制关闭: %v", err)
	}

	log.Println("服务器已退出")
}
