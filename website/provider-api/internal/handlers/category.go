package handlers

import (
	"strconv"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type CategoryHandler struct {
	db *gorm.DB
}

func NewCategoryHandler(db *gorm.DB) *CategoryHandler { return &CategoryHandler{db: db} }

// List 分类列表（用户端用）
func (h *CategoryHandler) List(c *gin.Context) {
	var cats []models.Category
	q := h.db.Model(&models.Category{}).Where("status = ?", 1)
	if c.Query("with_count") == "true" {
		// 简单实现，统计每个分类下的服务商数
	}
	q.Order("sort_order ASC, id ASC").Find(&cats)

	// 统计服务商数量
	type CatCount struct {
		ID    uint64 `json:"id"`
		Count int64  `json:"count"`
	}
	var counts []CatCount
	h.db.Model(&models.Provider{}).Select("category_id as id, COUNT(*) as count").
		Where("status = ?", 2).Group("category_id").Scan(&counts)
	cm := make(map[uint64]int64)
	for _, cc := range counts {
		cm[cc.ID] = cc.Count
	}
	for i := range cats {
		cats[i].ID = cats[i].ID
	}
	utils.OK(c, gin.H{"list": cats, "counts": cm})
}

// AdminList 管理端
func (h *CategoryHandler) AdminList(c *gin.Context) {
	var cats []models.Category
	h.db.Order("sort_order ASC, id ASC").Find(&cats)
	utils.OK(c, cats)
}

type CatReq struct {
	Name      string `json:"name" binding:"required"`
	Icon      string `json:"icon"`
	Color     string `json:"color"`
	ParentID  uint64 `json:"parent_id"`
	SortOrder int    `json:"sort_order"`
	Status    int    `json:"status"`
}

func (h *CategoryHandler) Create(c *gin.Context) {
	var req CatReq
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	cat := &models.Category{
		Name: req.Name, Icon: req.Icon, Color: req.Color,
		ParentID: req.ParentID, SortOrder: req.SortOrder, Status: req.Status,
	}
	if cat.Status == 0 {
		cat.Status = 1
	}
	h.db.Create(cat)
	utils.OK(c, cat)
}

func (h *CategoryHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var cat models.Category
	if err := h.db.First(&cat, id).Error; err != nil {
		utils.NotFound(c, "分类不存在")
		return
	}
	var req CatReq
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	cat.Name = req.Name
	cat.Icon = req.Icon
	cat.Color = req.Color
	cat.ParentID = req.ParentID
	cat.SortOrder = req.SortOrder
	if req.Status > 0 {
		cat.Status = req.Status
	}
	h.db.Save(&cat)
	utils.OK(c, cat)
}

func (h *CategoryHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	// 检查是否有服务商
	var count int64
	h.db.Model(&models.Provider{}).Where("category_id = ?", id).Count(&count)
	if count > 0 {
		utils.Fail(c, 40000, "该分类下还有服务商，无法删除")
		return
	}
	h.db.Delete(&models.Category{}, id)
	utils.OK(c, nil)
}
