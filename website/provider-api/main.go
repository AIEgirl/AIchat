package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/router"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
)

func main() {
	cfgPath := "config/config.yaml"
	if len(os.Args) > 2 && os.Args[1] == "-config" {
		cfgPath = os.Args[2]
	}

	cfg, err := config.Load(cfgPath)
	if err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	gin.SetMode(cfg.Server.Mode)
	utils.InitJWT(cfg.JWT.Secret)

	// 数据库
	dbPath := cfg.Database.Path
	if !filepath.IsAbs(dbPath) {
		wd, _ := os.Getwd()
		dbPath = filepath.Join(wd, dbPath)
	}
	db, err := database.Init(cfg.Database.Driver, dbPath)
	if err != nil {
		log.Fatalf("数据库初始化失败: %v", err)
	}

	// 前端目录
	frontendDir := cfg.Server.FrontendDir
	if frontendDir != "" && !filepath.IsAbs(frontendDir) {
		wd, _ := os.Getwd()
		frontendDir = filepath.Join(wd, frontendDir)
		cfg.Server.FrontendDir = frontendDir
	}

	// 引擎
	r := gin.New()
	r.Use(gin.Recovery())
	router.Setup(r, db, cfg)

	srv := &http.Server{
		Addr:         ":" + itoa(cfg.Server.Port),
		Handler:      r,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	go func() {
		log.Printf("============================================")
		log.Printf("  ProviderHub 服务商管理系统")
		log.Printf("  端口: %d", cfg.Server.Port)
		log.Printf("  数据库: %s", dbPath)
		log.Printf("  前端目录: %s", frontendDir)
		log.Printf("  时间: %s", time.Now().Format("2006-01-02 15:04:05"))
		log.Printf("============================================")
		log.Printf("  默认管理员: admin / Admin@123")
		log.Printf("  用户端: http://localhost:%d/user/", cfg.Server.Port)
		log.Printf("  管理端: http://localhost:%d/admin/", cfg.Server.Port)
		log.Printf("============================================")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("服务启动失败: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("正在关闭服务...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func itoa(n int) string {
	if n == 0 {
		return "8080"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	buf := [20]byte{}
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
