package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config 全局配置
type Config struct {
	Server      ServerConfig      `mapstructure:"server"`
	Database    DatabaseConfig    `mapstructure:"database"`
	JWT         JWTConfig         `mapstructure:"jwt"`
	Encryption  EncryptionConfig  `mapstructure:"encryption"`
	SMTP        SMTPConfig        `mapstructure:"smtp"`
	Payment     PaymentConfig     `mapstructure:"payment"`
	RateLimit   RateLimitConfig   `mapstructure:"ratelimit"`
	Signature   SignatureConfig   `mapstructure:"signature"`
	Log         LogConfig         `mapstructure:"log"`
}

type ServerConfig struct {
	Port         int           `mapstructure:"port"`
	Mode         string        `mapstructure:"mode"`
	ReadTimeout  time.Duration `mapstructure:"read_timeout"`
	WriteTimeout time.Duration `mapstructure:"write_timeout"`
}

type DatabaseConfig struct {
	Driver      string `mapstructure:"driver"`
	Host        string `mapstructure:"host"`
	Port        int    `mapstructure:"port"`
	Username    string `mapstructure:"username"`
	Password    string `mapstructure:"password"`
	DBName      string `mapstructure:"dbname"`
	Charset     string `mapstructure:"charset"`
	MaxOpenConns int   `mapstructure:"max_open_conns"`
	MaxIdleConns int   `mapstructure:"max_idle_conns"`
	LogLevel    string `mapstructure:"log_level"`
}

type JWTConfig struct {
	Secret             string `mapstructure:"secret"`
	ExpireHours        int    `mapstructure:"expire_hours"`
	RefreshExpireHours int    `mapstructure:"refresh_expire_hours"`
}

type EncryptionConfig struct {
	AESKey      string `mapstructure:"aes_key"`
	APIKeySalt  string `mapstructure:"api_key_salt"`
}

type SMTPConfig struct {
	Host     string `mapstructure:"host"`
	Port     int    `mapstructure:"port"`
	Username string `mapstructure:"username"`
	Password string `mapstructure:"password"`
	From     string `mapstructure:"from"`
	Enabled  bool   `mapstructure:"enabled"`
}

type PaymentConfig struct {
	Alipay AlipayConfig   `mapstructure:"alipay"`
	Wechat WechatConfig   `mapstructure:"wechat"`
	Stripe StripeConfig   `mapstructure:"stripe"`
}

type AlipayConfig struct {
	Enabled    bool   `mapstructure:"enabled"`
	AppID      string `mapstructure:"app_id"`
	PrivateKey string `mapstructure:"private_key"`
	PublicKey  string `mapstructure:"public_key"`
	NotifyURL  string `mapstructure:"notify_url"`
	Gateway    string `mapstructure:"gateway"`
}

type WechatConfig struct {
	Enabled   bool   `mapstructure:"enabled"`
	AppID     string `mapstructure:"app_id"`
	MchID     string `mapstructure:"mch_id"`
	APIKey    string `mapstructure:"api_key"`
	NotifyURL string `mapstructure:"notify_url"`
}

type StripeConfig struct {
	Enabled        bool   `mapstructure:"enabled"`
	SecretKey      string `mapstructure:"secret_key"`
	PublishableKey string `mapstructure:"publishable_key"`
	WebhookSecret  string `mapstructure:"webhook_secret"`
}

type RateLimitConfig struct {
	Enabled   bool    `mapstructure:"enabled"`
	GlobalRPS int     `mapstructure:"global_rps"`
	UserRPS   int     `mapstructure:"user_rps"`
	IPRPS     int     `mapstructure:"ip_rps"`
	Burst     int     `mapstructure:"burst"`
}

type SignatureConfig struct {
	Enabled       bool `mapstructure:"enabled"`
	ExpireSeconds int  `mapstructure:"expire_seconds"`
}

type LogConfig struct {
	Level  string `mapstructure:"level"`
	Format string `mapstructure:"format"`
	Output string `mapstructure:"output"`
	File   string `mapstructure:"file"`
}

var AppConfig *Config

// Load 加载配置
func Load(configPath string) (*Config, error) {
	v := viper.New()
	v.SetConfigFile(configPath)
	v.SetConfigType("yaml")

	// 支持环境变量覆盖
	v.SetEnvPrefix("AIRELAY")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("读取配置文件失败: %w", err)
	}

	cfg := &Config{}
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("解析配置失败: %w", err)
	}

	AppConfig = cfg
	return cfg, nil
}
