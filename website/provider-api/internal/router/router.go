package router

import (
	"net/http"
	"os"
	"path/filepath"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/handlers"
	"github.com/aichat/relay/internal/middleware"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func Setup(r *gin.Engine, db *gorm.DB, cfg *config.Config) {
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "X-Request-ID"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
	}))

	r.Use(middleware.Logger())

	if cfg.Server.StaticDir != "" {
		r.Static("/static", cfg.Server.StaticDir)
	}

	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "providerhub"})
	})

	adminH := handlers.NewAdminHandler(db)
	providerH := handlers.NewProviderHandler(db)
	catH := handlers.NewCategoryHandler(db)

	// 用户端
	userAPI := r.Group("/api/user/v1")
	{
		userAPI.GET("/providers", providerH.List)
		userAPI.GET("/providers/featured", providerH.Featured)
		userAPI.GET("/providers/latest", providerH.Latest)
		userAPI.GET("/providers/top", providerH.TopRated)
		userAPI.GET("/providers/:id", providerH.Detail)
		userAPI.POST("/providers/:id/contact", providerH.Contact)
		userAPI.GET("/categories", catH.List)
		userAPI.GET("/stats/overview", providerH.PublicOverview)
	}

	// 管理端
	adminAPI := r.Group("/api/admin/v1")
	{
		adminAPI.POST("/auth/login", adminH.Login)

		authed := adminAPI.Group("/")
		authed.Use(middleware.JWTAuth())
		{
			authed.GET("/auth/me", adminH.Me)
			authed.POST("/auth/logout", adminH.Logout)
			authed.POST("/auth/change-password", adminH.ChangePassword)

			authed.GET("/providers", providerH.AdminList)
			authed.POST("/providers", providerH.Create)
			authed.PUT("/providers/:id", providerH.Update)
			authed.DELETE("/providers/:id", providerH.Delete)
			authed.POST("/providers/batch", providerH.BatchAction)
			authed.POST("/providers/:id/status", providerH.UpdateStatus)
			authed.POST("/providers/:id/review", providerH.Review)
			authed.GET("/providers/:id/reviews", providerH.ReviewHistory)
			authed.GET("/providers/:id/qualifications", providerH.GetQualifications)
			authed.POST("/providers/:id/qualifications", providerH.AddQualification)
			authed.DELETE("/providers/:id/qualifications/:qid", providerH.DeleteQualification)

			authed.GET("/categories", catH.AdminList)
			authed.POST("/categories", catH.Create)
			authed.PUT("/categories/:id", catH.Update)
			authed.DELETE("/categories/:id", catH.Delete)

			authed.GET("/stats/analysis", providerH.Stats)
		}
	}

	// SPA fallback
	if cfg.Server.FrontendDir != "" {
		spa(r, cfg.Server.FrontendDir)
	}
}

func spa(r *gin.Engine, dir string) {
	abs, _ := filepath.Abs(dir)
	r.NoRoute(func(c *gin.Context) {
		path := abs
		// API 路径
		if len(c.Request.URL.Path) > 5 && c.Request.URL.Path[:5] == "/api/" {
			c.JSON(http.StatusNotFound, gin.H{"code": 404, "message": "API not found"})
			return
		}
		// 用户端
		if len(c.Request.URL.Path) >= 5 && c.Request.URL.Path[:5] == "/user" {
			if c.Request.URL.Path == "/user" || c.Request.URL.Path == "/user/" {
				c.File(filepath.Join(path, "user", "index.html"))
				return
			}
		}
		// 管理端
		if len(c.Request.URL.Path) >= 6 && c.Request.URL.Path[:6] == "/admin" {
			if c.Request.URL.Path == "/admin" || c.Request.URL.Path == "/admin/" {
				c.File(filepath.Join(path, "admin", "index.html"))
				return
			}
		}
		// 默认首页
		if c.Request.URL.Path == "/" {
			c.File(filepath.Join(path, "index.html"))
			return
		}
		// 静态文件
		fp := filepath.Join(path, c.Request.URL.Path)
		if info, err := os.Stat(fp); err == nil && !info.IsDir() {
			c.File(fp)
			return
		}
		c.JSON(http.StatusNotFound, gin.H{"code": utils.CodeNotFound, "message": "not found"})
	})
}
