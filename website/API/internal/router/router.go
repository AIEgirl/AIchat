package router

import (
	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/handlers"
	"github.com/aichat/relay/internal/middleware"
	"github.com/aichat/relay/internal/services"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// Setup 设置路由
func Setup(r *gin.Engine, db *gorm.DB, cfg *config.Config) {
	// 初始化服务
	emailSvc := services.NewEmailService(&cfg.SMTP)
	paymentSvc := services.NewPaymentService(&cfg.Payment)
	encSvc, _ := services.NewEncryptionService(cfg.Encryption.AESKey)
	proxySvc := services.NewAIProxyService()

	// 初始化中间件
	middleware.InitLimiter(&cfg.RateLimit)
	middleware.InitSignature(&cfg.Signature)
	middleware.InitAntiDDoS(db, middleware.AntiDDoSConfig{
		WindowSeconds: 10,
		MaxRequests:   200,
		BanSeconds:    600,
		Enabled:       true,
	})

	// 创建处理器
	authH := handlers.NewAuthHandler(db, cfg, emailSvc)
	userH := handlers.NewUserHandler(db)
	aiSvcH := handlers.NewAIServiceHandler(db)
	apiKeyH := handlers.NewAPIKeyHandler(db, encSvc)
	apiCallH := handlers.NewAPICallHandler(db, proxySvc, encSvc)
	payH := handlers.NewPaymentHandler(db, &cfg.Payment, paymentSvc)
	adminH := handlers.NewAdminHandler(db)
	finH := handlers.NewFinanceHandler(db)
	sysH := handlers.NewSystemHandler(db)

	// API Key验证器
	apiKeyVerifier := middleware.NewAPIKeyVerifier(db, encSvc)

	// 公开接口
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "service": "ai-relay", "version": "1.0.0"})
	})

	api := r.Group("/api/v1")
	api.GET("/site/info", sysH.GetConfigs)

	// 认证
	auth := api.Group("/auth")
	{
		auth.POST("/register", authH.Register)
		auth.POST("/login", authH.Login)
		auth.POST("/refresh", authH.RefreshToken)
		auth.POST("/send-code", authH.SendVerificationCode)
		auth.POST("/reset-password", authH.ResetPassword)
	}

	// 公开的AI服务
	api.GET("/services", aiSvcH.List)
	api.GET("/services/:code", aiSvcH.GetByCode)
	api.POST("/services/:code/estimate", aiSvcH.EstimateCost)

	// 公开的充值套餐
	api.GET("/recharge/packages", userH.GetRechargePackages)

	// 支付回调（公开）
	payGroup := api.Group("/payment")
	{
		payGroup.POST("/notify/alipay", payH.AlipayNotify)
		payGroup.POST("/notify/wechat", payH.WechatNotify)
	}

	// 需要登录的接口
	authed := api.Group("/")
	authed.Use(middleware.JWTAuth())
	{
		// 用户
		authed.GET("/user/me", authH.GetCurrentUser)
		authed.PUT("/user/profile", userH.UpdateProfile)
		authed.POST("/user/change-password", authH.ChangePassword)
		authed.POST("/user/logout", authH.Logout)

		// 账户
		authed.GET("/account/balance", userH.GetBalance)
		authed.GET("/account/transactions", userH.GetTransactions)
		authed.GET("/account/stats", userH.GetUsageStats)
		authed.GET("/account/status", userH.CheckAuthStatus)

		// 充值
		authed.POST("/recharge/create", payH.CreateRecharge)
		authed.GET("/recharge/order/:order_no", payH.QueryOrder)
		authed.POST("/recharge/cancel/:order_no", payH.CancelOrder)

		// API Key管理
		keys := authed.Group("/keys")
		{
			keys.GET("", apiKeyH.List)
			keys.POST("", apiKeyH.Create)
			keys.GET("/:id", apiKeyH.Get)
			keys.PUT("/:id", apiKeyH.Update)
			keys.DELETE("/:id", apiKeyH.Delete)
			keys.POST("/:id/rotate", apiKeyH.RotateKey)
		}

		// 调用日志
		authed.GET("/call/logs", apiCallH.GetCallLogs)
		authed.GET("/call/logs/:id", apiCallH.Replay)
	}

	// 公开AI服务调用（使用API Key认证）
	apiV1Call := api.Group("/v1")
	apiV1Call.Use(apiKeyVerifier.Authenticate())
	{
		// 兼容OpenAI风格的接口
		apiV1Call.POST("/chat/completions", apiCallH.ChatCompletion)

		// 通用AI服务调用
		apiV1Call.POST("/services/:code/call", apiCallH.Call)
		apiV1Call.POST("/services/:code/stream", apiCallH.ChatStream)
	}

	// 管理员接口
	admin := r.Group("/api/v1/admin")
	admin.Use(middleware.JWTAuth(), middleware.AdminAuth())
	{
		// 仪表盘
		admin.GET("/dashboard", adminH.DashboardStats)

		// 用户管理
		admin.GET("/users", adminH.UserList)
		admin.GET("/users/:id", adminH.GetUser)
		admin.PUT("/users/:id", adminH.UpdateUser)
		admin.POST("/users/:id/reset-password", adminH.ResetUserPassword)
		admin.DELETE("/users/:id", adminH.DeleteUser)
		admin.GET("/users/:id/transactions", adminH.UserTransactions)

		// AI服务管理
		admin.GET("/services", aiSvcH.AdminList)
		admin.POST("/services", aiSvcH.Create)
		admin.PUT("/services/:id", aiSvcH.Update)
		admin.DELETE("/services/:id", aiSvcH.Delete)
		admin.POST("/services/:id/toggle", aiSvcH.ToggleStatus)

		// 充值
		admin.POST("/recharge", payH.AdminRecharge)

		// 财务管理
		finance := admin.Group("/finance")
		{
			finance.GET("/transactions", finH.TransactionList)
			finance.GET("/stats", finH.Stats)
			finance.GET("/top-users", finH.TopUsers)
			finance.GET("/export", finH.ExportTransactions)
		}

		// 日志
		admin.GET("/logs/operation", adminH.OperationLogs)
		admin.GET("/logs/anomaly", adminH.AnomalyLogs)
		admin.GET("/anomaly/stats", adminH.AnomalyStats)

		// IP黑名单
		admin.GET("/blacklist", adminH.ListBlacklist)
		admin.POST("/blacklist", adminH.AddBlacklist)
		admin.DELETE("/blacklist/:id", adminH.RemoveBlacklist)

		// 系统配置
		configs := admin.Group("/configs")
		{
			configs.GET("", sysH.GetAllConfigs)
			configs.PUT("", sysH.UpdateConfig)
			configs.POST("", sysH.CreateConfig)
			configs.DELETE("/:key", sysH.DeleteConfig)
			configs.POST("/batch", sysH.BatchUpdateConfig)
			configs.GET("/smtp", sysH.GetSMTPConfig)
			configs.PUT("/smtp", sysH.UpdateSMTPConfig)
			configs.GET("/rate-limit", sysH.GetRateLimitConfig)
			configs.PUT("/rate-limit", sysH.UpdateRateLimitConfig)
			configs.GET("/payment", sysH.GetPaymentConfig)
			configs.PUT("/payment", sysH.UpdatePaymentConfig)
		}
	}
}
