package database

import (
	"fmt"
	"log"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/models"
	"github.com/glebarez/sqlite"
	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Init 初始化数据库
func Init(cfg *config.DatabaseConfig) (*gorm.DB, error) {
	gormLogger := logger.New(
		log.New(log.Writer(), "\r\n", log.LstdFlags),
		logger.Config{
			SlowThreshold:             200 * time.Millisecond,
			LogLevel:                  getLogLevel(cfg.LogLevel),
			IgnoreRecordNotFoundError: true,
			Colorful:                  false,
		},
	)

	var dialector gorm.Dialector
	var dsn string

	switch cfg.Driver {
	case "mysql":
		dsn = fmt.Sprintf(
			"%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=True&loc=Local",
			cfg.Username, cfg.Password, cfg.Host, cfg.Port, cfg.DBName, cfg.Charset,
		)
		dialector = mysql.Open(dsn)
	case "postgres":
		dsn = fmt.Sprintf(
			"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable TimeZone=Asia/Shanghai",
			cfg.Host, cfg.Port, cfg.Username, cfg.Password, cfg.DBName,
		)
		dialector = postgres.Open(dsn)
	case "sqlite":
		dsn = "ai_relay.db"
		dialector = sqlite.Open(dsn)
	default:
		return nil, fmt.Errorf("不支持的数据库驱动: %s", cfg.Driver)
	}

	db, err := gorm.Open(dialector, &gorm.Config{
		Logger:                                   gormLogger,
		DisableForeignKeyConstraintWhenMigrating: true,
	})
	if err != nil {
		return nil, fmt.Errorf("连接数据库失败: %w", err)
	}

	sqlDB, err := db.DB()
	if err != nil {
		return nil, err
	}

	sqlDB.SetMaxOpenConns(cfg.MaxOpenConns)
	sqlDB.SetMaxIdleConns(cfg.MaxIdleConns)
	sqlDB.SetConnMaxLifetime(time.Hour)

	// 自动迁移
	if err := models.AutoMigrate(db); err != nil {
		return nil, fmt.Errorf("数据库迁移失败: %w", err)
	}

	// 初始化种子数据
	if err := seedData(db); err != nil {
		log.Printf("初始化种子数据失败: %v", err)
	}

	return db, nil
}

func getLogLevel(level string) logger.LogLevel {
	switch level {
	case "silent":
		return logger.Silent
	case "error":
		return logger.Error
	case "warn":
		return logger.Warn
	case "info":
		return logger.Info
	default:
		return logger.Warn
	}
}

// seedData 种子数据
func seedData(db *gorm.DB) error {
	// 默认管理员账户
	var count int64
	db.Model(&models.User{}).Where("username = ?", "admin").Count(&count)
	if count == 0 {
		// 密码: Admin@123
		passwordHash, _ := HashPassword("Admin@123")
		admin := &models.User{
			UUID:          "admin-uuid-0000-0000-0000-000000000000",
			Username:      "admin",
			Email:         "admin@aichat.com",
			PasswordHash:  passwordHash,
			Nickname:      "系统管理员",
			Role:          "super_admin",
			Status:        1,
			EmailVerified: true,
			Balance:       10000,
		}
		if err := db.Create(admin).Error; err != nil {
			return err
		}
	}

	// 默认充值套餐
	db.Model(&models.RechargePackage{}).Count(&count)
	if count == 0 {
		packages := []models.RechargePackage{
			{Name: "体验套餐", Amount: 10, Balance: 10, Description: "首次体验优惠", SortOrder: 1, Status: 1},
			{Name: "基础套餐", Amount: 50, Balance: 55, Bonus: 5, Description: "赠送5元", SortOrder: 2, Status: 1},
			{Name: "标准套餐", Amount: 100, Balance: 120, Bonus: 20, Description: "赠送20元", SortOrder: 3, Status: 1},
			{Name: "高级套餐", Amount: 500, Balance: 600, Bonus: 100, Description: "赠送100元", SortOrder: 4, Status: 1},
			{Name: "企业套餐", Amount: 1000, Balance: 1300, Bonus: 300, Description: "赠送300元", SortOrder: 5, Status: 1},
			{Name: "豪华套餐", Amount: 5000, Balance: 7000, Bonus: 2000, Description: "赠送2000元", SortOrder: 6, Status: 1},
		}
		if err := db.Create(&packages).Error; err != nil {
			return err
		}
	}

	// 默认AI服务
	db.Model(&models.AIService{}).Count(&count)
	if count == 0 {
		services := []models.AIService{
			{
				UUID: "service-gpt35-uuid", Code: "gpt-3.5-turbo", Name: "GPT-3.5 Turbo",
				Provider: "openai", Description: "OpenAI GPT-3.5 Turbo 模型，适合一般对话与生成任务",
				Tags: "chat,fast,cheap", Endpoint: "https://api.openai.com/v1/chat/completions",
				Method: "POST", BillingMode: models.BillingPerToken,
				PricePerInputToken: 0.0015, PricePerOutputToken: 0.002,
				MaxQPS: 60, Status: 1, IsPublic: true, SortOrder: 1,
			},
			{
				UUID: "service-gpt4-uuid", Code: "gpt-4", Name: "GPT-4",
				Provider: "openai", Description: "OpenAI GPT-4 模型，强大的推理与理解能力",
				Tags: "chat,reasoning,powerful", Endpoint: "https://api.openai.com/v1/chat/completions",
				Method: "POST", BillingMode: models.BillingPerToken,
				PricePerInputToken: 0.03, PricePerOutputToken: 0.06,
				MaxQPS: 20, Status: 1, IsPublic: true, SortOrder: 2,
			},
			{
				UUID: "service-claude-uuid", Code: "claude-3-sonnet", Name: "Claude 3 Sonnet",
				Provider: "anthropic", Description: "Anthropic Claude 3 Sonnet 模型，平衡性能与成本",
				Tags: "chat,analysis", Endpoint: "https://api.anthropic.com/v1/messages",
				Method: "POST", BillingMode: models.BillingPerToken,
				PricePerInputToken: 0.003, PricePerOutputToken: 0.015,
				MaxQPS: 30, Status: 1, IsPublic: true, SortOrder: 3,
			},
			{
				UUID: "service-image-uuid", Code: "dall-e-3", Name: "DALL-E 3",
				Provider: "openai", Description: "OpenAI 图像生成模型",
				Tags: "image,generation", Endpoint: "https://api.openai.com/v1/images/generations",
				Method: "POST", BillingMode: models.BillingPerRequest,
				PricePerRequest: 0.04,
				MaxQPS: 10, Status: 1, IsPublic: true, SortOrder: 4,
			},
		}
		if err := db.Create(&services).Error; err != nil {
			return err
		}
	}

	// 默认系统配置
	db.Model(&models.SystemConfig{}).Count(&count)
	if count == 0 {
		configs := []models.SystemConfig{
			{Key: "site_name", Value: "AI中转服务平台", Type: "string", Group: "site", Label: "站点名称", IsPublic: true},
			{Key: "site_description", Value: "一站式AI模型调用服务", Type: "string", Group: "site", Label: "站点描述", IsPublic: true},
			{Key: "site_logo", Value: "", Type: "string", Group: "site", Label: "站点Logo", IsPublic: true},
			{Key: "register_enabled", Value: "true", Type: "bool", Group: "auth", Label: "开放注册", IsPublic: true},
			{Key: "email_verify_required", Value: "false", Type: "bool", Group: "auth", Label: "需要邮箱验证", IsPublic: false},
			{Key: "min_recharge_amount", Value: "1", Type: "number", Group: "payment", Label: "最小充值金额", IsPublic: true},
			{Key: "max_recharge_amount", Value: "100000", Type: "number", Group: "payment", Label: "最大充值金额", IsPublic: true},
			{Key: "default_user_balance", Value: "0", Type: "number", Group: "user", Label: "新用户默认余额", IsPublic: false},
		}
		if err := db.Create(&configs).Error; err != nil {
			return err
		}
	}

	return nil
}

// HashPassword 密码哈希（使用bcrypt）
func HashPassword(password string) (string, error) {
	// 这里使用简单的bcrypt，引用golang.org/x/crypto/bcrypt
	return hashPasswordBcrypt(password)
}
