package handlers

import (
	"strconv"
	"strings"
	"time"

	"github.com/aichat/relay/internal/database"
	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AdminHandler struct {
	db *gorm.DB
}

func NewAdminHandler(db *gorm.DB) *AdminHandler { return &AdminHandler{db: db} }

type LoginReq struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func (h *AdminHandler) Login(c *gin.Context) {
	var req LoginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	var admin models.Admin
	if err := h.db.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		utils.Unauthorized(c, "账号或密码错误")
		return
	}
	if !database.CheckPassword(req.Password, admin.PasswordHash) {
		utils.Unauthorized(c, "账号或密码错误")
		return
	}
	if admin.Status != 1 {
		utils.Forbidden(c, "账号已禁用")
		return
	}
	now := time.Now()
	ip := c.ClientIP()
	h.db.Model(&admin).Updates(map[string]interface{}{
		"last_login_at": &now, "last_login_ip": ip,
	})

	token, _ := utils.GenerateToken(admin.ID, admin.Username, admin.Role, 24)
	utils.OK(c, gin.H{
		"token": token, "expires_in": 86400,
		"user": gin.H{
			"id": admin.ID, "username": admin.Username,
			"nickname": admin.Nickname, "role": admin.Role, "avatar": admin.Avatar,
		},
	})
}

func (h *AdminHandler) Me(c *gin.Context) {
	uid := c.GetUint64("admin_id")
	var admin models.Admin
	if err := h.db.First(&admin, uid).Error; err != nil {
		utils.NotFound(c, "用户不存在")
		return
	}
	utils.OK(c, admin)
}

func (h *AdminHandler) Logout(c *gin.Context) {
	utils.OK(c, nil)
}

func (h *AdminHandler) ChangePassword(c *gin.Context) {
	uid := c.GetUint64("admin_id")
	var req struct {
		Old string `json:"old_password" binding:"required"`
		New string `json:"new_password" binding:"required,min=8"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	var admin models.Admin
	h.db.First(&admin, uid)
	if !database.CheckPassword(req.Old, admin.PasswordHash) {
		utils.BadRequest(c, "原密码错误")
		return
	}
	hash, _ := database.HashPassword(req.New)
	h.db.Model(&admin).Update("password_hash", hash)
	utils.OK(c, nil)
}
