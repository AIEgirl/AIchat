package handlers

import (
	"strconv"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/services"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// APIKeyHandler API Key 处理器
type APIKeyHandler struct {
	db   *gorm.DB
	enc  *services.EncryptionService
}

// NewAPIKeyHandler 创建API Key处理器
func NewAPIKeyHandler(db *gorm.DB, enc *services.EncryptionService) *APIKeyHandler {
	return &APIKeyHandler{db: db, enc: enc}
}

// CreateKeyRequest 创建Key请求
type CreateKeyRequest struct {
	Name      string `json:"name" binding:"required,min=1,max=64"`
	Scopes    string `json:"scopes"`
	ExpiresIn int    `json:"expires_in"` // 天数，0表示永不过期
}

// Create 创建API Key
func (h *APIKeyHandler) Create(c *gin.Context) {
	var req CreateKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	userID := c.GetUint64("user_id")
	keyID, keySecret, preview := utils.GenerateAPIKey()

	// 加密存储密钥
	encryptedSecret, err := h.enc.EncryptAPIKey(keySecret)
	if err != nil {
		utils.ServerError(c, "密钥加密失败")
		return
	}

	key := &models.APIKey{
		UserID:     userID,
		Name:       req.Name,
		KeyID:      keyID,
		KeySecret:  encryptedSecret,
		KeyPreview: preview,
		Scopes:     req.Scopes,
		Status:     1,
	}
	if req.Scopes == "" {
		key.Scopes = "all"
	}
	if req.ExpiresIn > 0 {
		exp := time.Now().AddDate(0, 0, req.ExpiresIn)
		key.ExpiresAt = &exp
	}

	if err := h.db.Create(key).Error; err != nil {
		utils.ServerError(c, "创建失败")
		return
	}

	// 注意：密钥仅在创建时返回明文
	utils.Success(c, gin.H{
		"id":          key.ID,
		"name":        key.Name,
		"key_id":      key.KeyID,
		"key_secret":  keySecret,
		"key_preview": preview,
		"scopes":      key.Scopes,
		"status":      key.Status,
		"expires_at":  key.ExpiresAt,
		"created_at":  key.CreatedAt,
		"_warning":    "请妥善保存密钥，关闭页面后将无法再次查看完整密钥",
	})
}

// List 列出API Key
func (h *APIKeyHandler) List(c *gin.Context) {
	userID := c.GetUint64("user_id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.APIKey{}).Where("user_id = ?", userID)
	var total int64
	query.Count(&total)

	var keys []models.APIKey
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&keys).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, keys, total, page, pageSize)
}

// Get 获取单个
func (h *APIKeyHandler) Get(c *gin.Context) {
	userID := c.GetUint64("user_id")
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var key models.APIKey
	if err := h.db.Where("user_id = ? AND id = ?", userID, id).First(&key).Error; err != nil {
		utils.NotFound(c, "密钥不存在")
		return
	}
	utils.Success(c, key)
}

// Update 更新（重命名/修改状态）
func (h *APIKeyHandler) Update(c *gin.Context) {
	userID := c.GetUint64("user_id")
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var key models.APIKey
	if err := h.db.Where("user_id = ? AND id = ?", userID, id).First(&key).Error; err != nil {
		utils.NotFound(c, "密钥不存在")
		return
	}

	var req struct {
		Name   *string `json:"name"`
		Status *int    `json:"status"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		updates["name"] = *req.Name
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}

	if len(updates) > 0 {
		h.db.Model(&key).Updates(updates)
	}

	utils.SuccessWithMessage(c, "更新成功", nil)
}

// Delete 删除
func (h *APIKeyHandler) Delete(c *gin.Context) {
	userID := c.GetUint64("user_id")
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if err := h.db.Where("user_id = ? AND id = ?", userID, id).Delete(&models.APIKey{}).Error; err != nil {
		utils.ServerError(c, "删除失败")
		return
	}
	utils.SuccessWithMessage(c, "删除成功", nil)
}

// RotateKey 轮换密钥（生成新secret）
func (h *APIKeyHandler) RotateKey(c *gin.Context) {
	userID := c.GetUint64("user_id")
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var key models.APIKey
	if err := h.db.Where("user_id = ? AND id = ?", userID, id).First(&key).Error; err != nil {
		utils.NotFound(c, "密钥不存在")
		return
	}

	_, newSecret, preview := utils.GenerateAPIKey()
	encrypted, err := h.enc.EncryptAPIKey(newSecret)
	if err != nil {
		utils.ServerError(c, "加密失败")
		return
	}

	key.KeySecret = encrypted
	key.KeyPreview = preview
	h.db.Save(&key)

	utils.Success(c, gin.H{
		"id":          key.ID,
		"key_id":      key.KeyID,
		"key_secret":  newSecret,
		"key_preview": preview,
		"_warning":    "新密钥仅显示一次，请妥善保存",
	})
}
