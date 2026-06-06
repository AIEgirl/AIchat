package handlers

import (
	"net/http"
	"strings"
	"time"

	"github.com/aichat/relay/internal/config"
	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/services"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// AuthHandler 认证处理器
type AuthHandler struct {
	db     *gorm.DB
	cfg    *config.Config
	email  *services.EmailService
}

// NewAuthHandler 创建认证处理器
func NewAuthHandler(db *gorm.DB, cfg *config.Config, email *services.EmailService) *AuthHandler {
	return &AuthHandler{db: db, cfg: cfg, email: email}
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Username string `json:"username" binding:"required,min=3,max=32"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8,max=64"`
	Nickname string `json:"nickname"`
	Code     string `json:"code"`
}

// Register 用户注册
func (h *AuthHandler) Register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误: "+err.Error())
		return
	}

	// 检查开放注册
	var registerEnabled models.SystemConfig
	if err := h.db.Where("`key` = ?", "register_enabled").First(&registerEnabled).Error; err == nil {
		if registerEnabled.Value == "false" {
			utils.Forbidden(c, "暂不开放注册")
			return
		}
	}

	// 检查邮箱验证
	var emailVerifyRequired models.SystemConfig
	if err := h.db.Where("`key` = ?", "email_verify_required").First(&emailVerifyRequired).Error; err == nil {
		if emailVerifyRequired.Value == "true" {
			// 验证邮箱验证码
			var vc models.VerificationCode
			if err := h.db.Where("email = ? AND code = ? AND type = ? AND used = ? AND expires_at > ?",
				req.Email, req.Code, "register", false, time.Now()).First(&vc).Error; err != nil {
				utils.BadRequest(c, "验证码无效或已过期")
				return
			}
			// 标记为已使用
			h.db.Model(&vc).Update("used", true)
		}
	}

	// 检查用户名/邮箱是否已存在
	var count int64
	h.db.Model(&models.User{}).Where("username = ? OR email = ?", req.Username, req.Email).Count(&count)
	if count > 0 {
		utils.Fail(c, utils.CodeConflict, "用户名或邮箱已被注册")
		return
	}

	// 密码哈希
	passwordHash, err := database.HashPassword(req.Password)
	if err != nil {
		utils.ServerError(c, "密码处理失败")
		return
	}

	// 创建用户
	user := &models.User{
		UUID:         utils.GenerateUUID(),
		Username:     req.Username,
		Email:        req.Email,
		PasswordHash: passwordHash,
		Nickname:     req.Nickname,
		Role:         "user",
		Status:       1,
	}

	if err := h.db.Create(user).Error; err != nil {
		utils.ServerError(c, "创建用户失败")
		return
	}

	utils.SuccessWithMessage(c, "注册成功", gin.H{
		"user_id": user.ID,
		"uuid":    user.UUID,
	})
}

// LoginRequest 登录请求
type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	Code     string `json:"code"`
}

// Login 用户登录
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 查询用户
	var user models.User
	if err := h.db.Where("username = ? OR email = ?", req.Username, req.Username).First(&user).Error; err != nil {
		h.logLogin(0, req.Username, c, 0, "用户不存在")
		utils.Unauthorized(c, "用户名或密码错误")
		return
	}

	// 验证密码
	if !database.CheckPasswordHash(req.Password, user.PasswordHash) {
		h.logLogin(user.ID, req.Username, c, 0, "密码错误")
		utils.Unauthorized(c, "用户名或密码错误")
		return
	}

	// 检查状态
	if !user.IsActive() {
		h.logLogin(user.ID, req.Username, c, 0, "账户已禁用")
		utils.Forbidden(c, "账户已被禁用")
		return
	}

	// 生成Token
	token, err := utils.GenerateToken(user.ID, user.UUID, user.Username, user.Role, h.cfg.JWT.ExpireHours)
	if err != nil {
		utils.ServerError(c, "生成Token失败")
		return
	}
	refreshToken, _ := utils.GenerateRefreshToken(user.ID, user.UUID, h.cfg.JWT.RefreshExpireHours)

	// 更新登录信息
	now := time.Now()
	ip := c.ClientIP()
	h.db.Model(&user).Updates(map[string]interface{}{
		"last_login_at":  &now,
		"last_login_ip":  ip,
		"login_count":    gorm.Expr("login_count + 1"),
	})

	h.logLogin(user.ID, req.Username, c, 1, "登录成功")

	utils.Success(c, gin.H{
		"token":         token,
		"refresh_token": refreshToken,
		"expires_in":    h.cfg.JWT.ExpireHours * 3600,
		"user": gin.H{
			"id":       user.ID,
			"uuid":     user.UUID,
			"username": user.Username,
			"email":    user.Email,
			"nickname": user.Nickname,
			"avatar":   user.Avatar,
			"role":     user.Role,
			"balance":  user.Balance,
		},
	})
}

// RefreshTokenRequest 刷新token
type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// RefreshToken 刷新token
func (h *AuthHandler) RefreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	claims, err := utils.ParseToken(req.RefreshToken)
	if err != nil {
		utils.Unauthorized(c, "刷新令牌无效")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", claims.UUID).First(&user).Error; err != nil {
		utils.Unauthorized(c, "用户不存在")
		return
	}

	token, _ := utils.GenerateToken(user.ID, user.UUID, user.Username, user.Role, h.cfg.JWT.ExpireHours)
	utils.Success(c, gin.H{
		"token":      token,
		"expires_in": h.cfg.JWT.ExpireHours * 3600,
	})
}

// SendCodeRequest 发送验证码
type SendCodeRequest struct {
	Email   string `json:"email" binding:"required,email"`
	Type    string `json:"type" binding:"required,oneof=register reset login"`
	Purpose string `json:"purpose"`
}

// SendVerificationCode 发送验证码
func (h *AuthHandler) SendVerificationCode(c *gin.Context) {
	var req SendCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 频率限制：60秒内只能发一次
	var recent models.VerificationCode
	if err := h.db.Where("email = ? AND type = ? AND created_at > ?",
		req.Email, req.Type, time.Now().Add(-60*time.Second)).First(&recent).Error; err == nil {
		utils.Fail(c, utils.CodeRateLimit, "请勿频繁请求，60秒后再试")
		return
	}

	// 注册时检查邮箱是否已存在
	if req.Type == "register" {
		var count int64
		h.db.Model(&models.User{}).Where("email = ?", req.Email).Count(&count)
		if count > 0 {
			utils.Fail(c, utils.CodeConflict, "该邮箱已注册")
			return
		}
	}

	// 重置密码时检查邮箱是否存在
	if req.Type == "reset" {
		var count int64
		h.db.Model(&models.User{}).Where("email = ?", req.Email).Count(&count)
		if count == 0 {
			utils.Fail(c, utils.CodeNotFound, "该邮箱未注册")
			return
		}
	}

	// 生成验证码
	code := utils.GenerateRandomCode(6)
	vc := &models.VerificationCode{
		Email:     req.Email,
		Code:      code,
		Type:      req.Type,
		ExpiresAt: time.Now().Add(10 * time.Minute),
		IP:        c.ClientIP(),
	}
	if err := h.db.Create(vc).Error; err != nil {
		utils.ServerError(c, "发送失败")
		return
	}

	// 发送邮件
	if err := h.email.SendVerificationCode(req.Email, code, req.Type); err != nil {
		utils.ServerError(c, "邮件发送失败")
		return
	}

	utils.SuccessWithMessage(c, "验证码已发送", gin.H{
		"expires_in": 600,
	})
}

// ResetPasswordRequest 重置密码
type ResetPasswordRequest struct {
	Email       string `json:"email" binding:"required,email"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8,max=64"`
}

// ResetPassword 重置密码
func (h *AuthHandler) ResetPassword(c *gin.Context) {
	var req ResetPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 验证验证码
	var vc models.VerificationCode
	if err := h.db.Where("email = ? AND code = ? AND type = ? AND used = ? AND expires_at > ?",
		req.Email, req.Code, "reset", false, time.Now()).First(&vc).Error; err != nil {
		utils.BadRequest(c, "验证码无效或已过期")
		return
	}

	// 查询用户
	var user models.User
	if err := h.db.Where("email = ?", req.Email).First(&user).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	// 更新密码
	passwordHash, _ := database.HashPassword(req.NewPassword)
	h.db.Model(&user).Update("password_hash", passwordHash)
	h.db.Model(&vc).Update("used", true)

	utils.SuccessWithMessage(c, "密码重置成功", nil)
}

// ChangePasswordRequest 修改密码
type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=8,max=64"`
}

// ChangePassword 修改密码（已登录）
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint64("user_id")
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	if !database.CheckPasswordHash(req.OldPassword, user.PasswordHash) {
		utils.BadRequest(c, "原密码错误")
		return
	}

	passwordHash, _ := database.HashPassword(req.NewPassword)
	h.db.Model(&user).Update("password_hash", passwordHash)
	utils.SuccessWithMessage(c, "密码修改成功", nil)
}

// Logout 登出
func (h *AuthHandler) Logout(c *gin.Context) {
	// 简单实现：客户端删除token
	// 生产环境应该使用token黑名单
	utils.SuccessWithMessage(c, "登出成功", nil)
}

// GetCurrentUser 获取当前用户信息
func (h *AuthHandler) GetCurrentUser(c *gin.Context) {
	userID := c.GetUint64("user_id")
	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}

	utils.Success(c, gin.H{
		"id":            user.ID,
		"uuid":          user.UUID,
		"username":      user.Username,
		"email":         user.Email,
		"nickname":      user.Nickname,
		"avatar":        user.Avatar,
		"phone":         user.Phone,
		"role":          user.Role,
		"status":        user.Status,
		"email_verified": user.EmailVerified,
		"balance":       user.Balance,
		"frozen_balance": user.FrozenBalance,
		"total_spent":   user.TotalSpent,
		"total_recharged": user.TotalRecharged,
		"created_at":    user.CreatedAt,
	})
}

func (h *AuthHandler) logLogin(userID uint64, username string, c *gin.Context, status int, message string) {
	log := &models.UserLoginLog{
		UserID:    userID,
		Username:  username,
		IP:        c.ClientIP(),
		UserAgent: c.Request.UserAgent(),
		Status:    status,
		Message:   message,
	}
	h.db.Create(log)
}

// 邮件测试
func (h *AuthHandler) TestEmail(c *gin.Context) {
	if !strings.Contains(c.GetHeader("Origin"), "localhost") {
		c.JSON(http.StatusOK, gin.H{"code": 0, "message": "ok"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "ok"})
}
