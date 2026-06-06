package handlers

import (
	"strconv"
	"strings"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// SystemHandler 系统配置处理器
type SystemHandler struct {
	db *gorm.DB
}

// NewSystemHandler 创建系统处理器
func NewSystemHandler(db *gorm.DB) *SystemHandler {
	return &SystemHandler{db: db}
}

// GetConfigs 获取配置（按分组）
func (h *SystemHandler) GetConfigs(c *gin.Context) {
	group := c.Query("group")
	isAdmin := c.GetString("role") == "admin" || c.GetString("role") == "super_admin"

	query := h.db.Model(&models.SystemConfig{})
	if !isAdmin {
		query = query.Where("is_public = ?", true)
	}
	if group != "" {
		query = query.Where("`group` = ?", group)
	}

	var configs []models.SystemConfig
	if err := query.Order("id ASC").Find(&configs).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	// 转为map
	result := make(map[string]interface{})
	for _, cfg := range configs {
		result[cfg.Key] = h.parseValue(cfg.Value, cfg.Type)
	}

	utils.Success(c, gin.H{
		"group":   group,
		"configs": result,
		"list":    configs,
	})
}

func (h *SystemHandler) parseValue(value, typ string) interface{} {
	switch typ {
	case "number":
		if f, err := strconv.ParseFloat(value, 64); err == nil {
			return f
		}
	case "bool":
		return value == "true" || value == "1"
	case "json":
		// 简化处理
	}
	return value
}

// GetAllConfigs 管理员获取所有配置
func (h *SystemHandler) GetAllConfigs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))

	query := h.db.Model(&models.SystemConfig{})
	if group := c.Query("group"); group != "" {
		query = query.Where("`group` = ?", group)
	}
	if keyword := c.Query("keyword"); keyword != "" {
		query = query.Where("`key` LIKE ? OR label LIKE ?", "%"+keyword+"%", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var configs []models.SystemConfig
	if err := query.Order("id ASC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&configs).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, configs, total, page, pageSize)
}

// UpdateConfigRequest 更新配置
type UpdateConfigRequest struct {
	Key   string `json:"key" binding:"required"`
	Value string `json:"value"`
	Type  string `json:"type"`
	Label string `json:"label"`
	Remark string `json:"remark"`
	IsPublic bool `json:"is_public"`
}

// UpdateConfig 更新配置
func (h *SystemHandler) UpdateConfig(c *gin.Context) {
	var req UpdateConfigRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	updates := map[string]interface{}{
		"value": req.Value,
	}
	if req.Type != "" {
		updates["type"] = req.Type
	}
	if req.Label != "" {
		updates["label"] = req.Label
	}
	if req.Remark != "" {
		updates["remark"] = req.Remark
	}
	updates["is_public"] = req.IsPublic

	if err := h.db.Model(&models.SystemConfig{}).Where("`key` = ?", req.Key).Updates(updates).Error; err != nil {
		utils.ServerError(c, "更新失败")
		return
	}

	utils.SuccessWithMessage(c, "更新成功", nil)
}

// BatchUpdateConfig 批量更新
func (h *SystemHandler) BatchUpdateConfig(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	for key, value := range req {
		h.db.Model(&models.SystemConfig{}).Where("`key` = ?", key).Update("value", value)
	}

	utils.SuccessWithMessage(c, "更新成功", nil)
}

// CreateConfig 创建配置
func (h *SystemHandler) CreateConfig(c *gin.Context) {
	var req struct {
		Key      string `json:"key" binding:"required"`
		Value    string `json:"value"`
		Type     string `json:"type"`
		Group    string `json:"group" binding:"required"`
		Label    string `json:"label"`
		Remark   string `json:"remark"`
		IsPublic bool   `json:"is_public"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	// 检查是否已存在
	var count int64
	h.db.Model(&models.SystemConfig{}).Where("`key` = ?", req.Key).Count(&count)
	if count > 0 {
		utils.Fail(c, utils.CodeConflict, "配置已存在")
		return
	}

	cfg := &models.SystemConfig{
		Key:      req.Key,
		Value:    req.Value,
		Type:     req.Type,
		Group:    req.Group,
		Label:    req.Label,
		Remark:   req.Remark,
		IsPublic: req.IsPublic,
	}
	if cfg.Type == "" {
		cfg.Type = "string"
	}

	if err := h.db.Create(cfg).Error; err != nil {
		utils.ServerError(c, "创建失败")
		return
	}

	utils.SuccessWithMessage(c, "创建成功", cfg)
}

// DeleteConfig 删除配置
func (h *SystemHandler) DeleteConfig(c *gin.Context) {
	key := c.Param("key")
	if err := h.db.Where("`key` = ?", key).Delete(&models.SystemConfig{}).Error; err != nil {
		utils.ServerError(c, "删除失败")
		return
	}
	utils.SuccessWithMessage(c, "删除成功", nil)
}

// GetSMTPConfig 获取SMTP配置（管理员）
func (h *SystemHandler) GetSMTPConfig(c *gin.Context) {
	keys := []string{"smtp_host", "smtp_port", "smtp_username", "smtp_password", "smtp_from", "smtp_enabled"}
	var configs []models.SystemConfig
	h.db.Where("`key` IN ?", keys).Find(&configs)

	result := make(map[string]string)
	for _, cfg := range configs {
		result[cfg.Key] = cfg.Value
	}
	utils.Success(c, result)
}

// UpdateSMTPConfig 更新SMTP配置
func (h *SystemHandler) UpdateSMTPConfig(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	for key, value := range req {
		h.db.Model(&models.SystemConfig{}).Where("`key` = ?", key).Update("value", value)
		// 如果不存在则创建
		var count int64
		h.db.Model(&models.SystemConfig{}).Where("`key` = ?", key).Count(&count)
		if count == 0 {
			h.db.Create(&models.SystemConfig{
				Key:   key,
				Value: value,
				Type:  "string",
				Group: "smtp",
				Label: key,
			})
		}
	}

	utils.SuccessWithMessage(c, "SMTP配置已更新", nil)
}

// GetRateLimitConfig 获取限流配置
func (h *SystemHandler) GetRateLimitConfig(c *gin.Context) {
	keys := []string{"rate_limit_global", "rate_limit_user", "rate_limit_ip", "rate_limit_burst"}
	var configs []models.SystemConfig
	h.db.Where("`key` IN ?", keys).Find(&configs)

	result := make(map[string]interface{})
	for _, cfg := range configs {
		result[cfg.Key] = h.parseValue(cfg.Value, cfg.Type)
	}
	utils.Success(c, result)
}

// UpdateRateLimitConfig 更新限流配置
func (h *SystemHandler) UpdateRateLimitConfig(c *gin.Context) {
	var req map[string]interface{}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	for key, value := range req {
		valStr := toString(value)
		h.db.Model(&models.SystemConfig{}).Where("`key` = ?", key).Update("value", valStr)
	}
	utils.SuccessWithMessage(c, "限流配置已更新", nil)
}

func toString(v interface{}) string {
	switch val := v.(type) {
	case string:
		return val
	case bool:
		if val {
			return "true"
		}
		return "false"
	case float64:
		return strconv.FormatFloat(val, 'f', -1, 64)
	case int:
		return strconv.Itoa(val)
	}
	return ""
}

// GetPaymentConfig 获取支付配置
func (h *SystemHandler) GetPaymentConfig(c *gin.Context) {
	keys := []string{
		"alipay_enabled", "alipay_app_id", "alipay_private_key", "alipay_public_key",
		"wechat_enabled", "wechat_app_id", "wechat_mch_id", "wechat_api_key",
		"stripe_enabled", "stripe_secret_key", "stripe_publishable_key",
	}
	var configs []models.SystemConfig
	h.db.Where("`key` IN ?", keys).Find(&configs)

	result := make(map[string]string)
	for _, cfg := range configs {
		// 隐藏敏感信息
		isSensitive := containsSensitive(cfg.Key)
		if isSensitive {
			if cfg.Value != "" {
				result[cfg.Key] = "******"
			}
		} else {
			result[cfg.Key] = cfg.Value
		}
	}
	utils.Success(c, result)
}

// UpdatePaymentConfig 更新支付配置
func (h *SystemHandler) UpdatePaymentConfig(c *gin.Context) {
	var req map[string]string
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}

	for key, value := range req {
		if value == "******" {
			continue // 跳过未修改的敏感字段
		}
		h.db.Model(&models.SystemConfig{}).Where("`key` = ?", key).Update("value", value)
	}
	utils.SuccessWithMessage(c, "支付配置已更新", nil)
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// containsSensitive 检查键名是否包含敏感字段
func containsSensitive(key string) bool {
	lower := strings.ToLower(key)
	return strings.Contains(lower, "key") || strings.Contains(lower, "secret") || strings.Contains(lower, "password")
}
