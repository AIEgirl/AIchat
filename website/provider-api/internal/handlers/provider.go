package handlers

import (
	"strconv"
	"strings"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ProviderHandler struct {
	db *gorm.DB
}

func NewProviderHandler(db *gorm.DB) *ProviderHandler { return &ProviderHandler{db: db} }

// ===== 用户端 =====

// List 用户端列表
func (h *ProviderHandler) List(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "12"))
	keyword := strings.TrimSpace(c.Query("keyword"))
	catID, _ := strconv.ParseUint(c.Query("category_id"), 10, 64)
	region := c.Query("region")
	sort := c.DefaultQuery("sort", "comprehensive")
	priceMin, _ := strconv.ParseFloat(c.Query("price_min"), 64)
	priceMax, _ := strconv.ParseFloat(c.Query("price_max"), 64)

	q := h.db.Model(&models.Provider{}).Where("status = ?", 2) // 仅已通过
	if keyword != "" {
		q = q.Where("name LIKE ? OR description LIKE ? OR tags LIKE ?",
			"%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
	}
	if catID > 0 {
		q = q.Where("category_id = ?", catID)
	}
	if region != "" {
		q = q.Where("region = ?", region)
	}
	if priceMin > 0 {
		q = q.Where("price_max >= ?", priceMin)
	}
	if priceMax > 0 {
		q = q.Where("price_min <= ?", priceMax)
	}

	switch sort {
	case "rating":
		q = q.Order("rating DESC, is_featured DESC")
	case "price_asc":
		q = q.Order("price_min ASC")
	case "price_desc":
		q = q.Order("price_max DESC")
	case "popular":
		q = q.Order("view_count DESC")
	default:
		q = q.Order("is_featured DESC, sort_order DESC, rating DESC")
	}

	var total int64
	q.Count(&total)
	var providers []models.Provider
	q.Offset((page - 1) * pageSize).Limit(pageSize).Find(&providers)
	utils.OKPage(c, providers, total, page, pageSize)
}

// Detail 详情
func (h *ProviderHandler) Detail(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var p models.Provider
	if err := h.db.First(&p, id).Error; err != nil {
		utils.NotFound(c, "服务商不存在")
		return
	}
	if p.Status != 2 {
		utils.NotFound(c, "服务商未公开")
		return
	}
	// 增加浏览量
	h.db.Model(&p).Update("view_count", gorm.Expr("view_count + 1"))

	// 加载资质
	var quals []models.Qualification
	h.db.Where("provider_id = ?", p.ID).Find(&quals)

	// 加载分类
	var cat models.Category
	if p.CategoryID > 0 {
		h.db.First(&cat, p.CategoryID)
	}
	utils.OK(c, gin.H{
		"provider":      p,
		"qualifications": quals,
		"category":      cat,
	})
}

// Featured 推荐
func (h *ProviderHandler) Featured(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "6"))
	var list []models.Provider
	h.db.Where("status = ? AND is_featured = ?", 2, true).
		Order("sort_order DESC, rating DESC").Limit(limit).Find(&list)
	utils.OK(c, list)
}

// Latest 最新
func (h *ProviderHandler) Latest(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "8"))
	var list []models.Provider
	h.db.Where("status = ?", 2).Order("created_at DESC").Limit(limit).Find(&list)
	utils.OK(c, list)
}

// TopRated 评分最高
func (h *ProviderHandler) TopRated(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	var list []models.Provider
	h.db.Where("status = ?", 2).Order("rating DESC, deal_count DESC").Limit(limit).Find(&list)
	utils.OK(c, list)
}

// Contact 提交联系咨询
func (h *ProviderHandler) Contact(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req struct {
		Name    string `json:"name" binding:"required"`
		Phone   string `json:"phone" binding:"required"`
		Email   string `json:"email"`
		Message string `json:"message"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "请填写完整信息")
		return
	}
	rec := &models.ContactRecord{
		ProviderID: id, Name: req.Name, Phone: req.Phone,
		Email: req.Email, Message: req.Message, IP: c.ClientIP(),
	}
	h.db.Create(rec)
	utils.OK(c, gin.H{"id": rec.ID})
}

// ===== 管理端 =====

// AdminList 管理端列表
func (h *ProviderHandler) AdminList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")
	statusStr := c.Query("status")
	catID, _ := strconv.ParseUint(c.Query("category_id"), 10, 64)

	q := h.db.Model(&models.Provider{})
	if keyword != "" {
		q = q.Where("name LIKE ? OR contact_name LIKE ?", "%"+keyword+"%", "%"+keyword+"%")
	}
	if statusStr != "" {
		if s, err := strconv.Atoi(statusStr); err == nil {
			q = q.Where("status = ?", s)
		}
	}
	if catID > 0 {
		q = q.Where("category_id = ?", catID)
	}

	var total int64
	q.Count(&total)
	var providers []models.Provider
	q.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&providers)
	utils.OKPage(c, providers, total, page, pageSize)
}

type CreateProviderReq struct {
	Name            string  `json:"name" binding:"required"`
	CreditCode      string  `json:"credit_code"`
	Logo            string  `json:"logo"`
	Description     string  `json:"description"`
	Website         string  `json:"website"`
	ContactName     string  `json:"contact_name"`
	ContactPhone    string  `json:"contact_phone"`
	ContactEmail    string  `json:"contact_email"`
	Address         string  `json:"address"`
	Region          string  `json:"region"`
	CategoryID      uint64  `json:"category_id"`
	ServiceScope    string  `json:"service_scope"`
	PriceMin        float64 `json:"price_min"`
	PriceMax        float64 `json:"price_max"`
	CooperationMode string  `json:"cooperation_mode"`
	Tags            string  `json:"tags"`
	IsFeatured      bool    `json:"is_featured"`
	SortOrder       int     `json:"sort_order"`
	Status          int     `json:"status"`
}

func genUUID() string {
	return time.Now().Format("20060102150405") + "-" + randomHex(8)
}

func randomHex(n int) string {
	const chars = "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		b[i] = chars[time.Now().UnixNano()%int64(len(chars))]
		time.Sleep(time.Microsecond)
	}
	return string(b)
}

// Create 创建
func (h *ProviderHandler) Create(c *gin.Context) {
	var req CreateProviderReq
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误: "+err.Error())
		return
	}
	p := &models.Provider{
		UUID: genUUID(), Name: req.Name, CreditCode: req.CreditCode,
		Logo: req.Logo, Description: req.Description, Website: req.Website,
		ContactName: req.ContactName, ContactPhone: req.ContactPhone,
		ContactEmail: req.ContactEmail, Address: req.Address, Region: req.Region,
		CategoryID: req.CategoryID, ServiceScope: req.ServiceScope,
		PriceMin: req.PriceMin, PriceMax: req.PriceMax,
		CooperationMode: req.CooperationMode, Tags: req.Tags,
		IsFeatured: req.IsFeatured, SortOrder: req.SortOrder, Status: models.ProviderStatus(req.Status),
	}
	if p.Status == 0 {
		p.Status = 2
	}
	if p.Status == 2 {
		now := time.Now()
		p.ApprovedTime = &now
		uid := c.GetUint64("admin_id")
		p.ApprovedBy = &uid
	}
	if err := h.db.Create(p).Error; err != nil {
		utils.ServerError(c, "创建失败")
		return
	}
	utils.OK(c, p)
}

// Update 更新
func (h *ProviderHandler) Update(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var p models.Provider
	if err := h.db.First(&p, id).Error; err != nil {
		utils.NotFound(c, "服务商不存在")
		return
	}
	var req CreateProviderReq
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	p.Name = req.Name
	p.CreditCode = req.CreditCode
	p.Logo = req.Logo
	p.Description = req.Description
	p.Website = req.Website
	p.ContactName = req.ContactName
	p.ContactPhone = req.ContactPhone
	p.ContactEmail = req.ContactEmail
	p.Address = req.Address
	p.Region = req.Region
	p.CategoryID = req.CategoryID
	p.ServiceScope = req.ServiceScope
	p.PriceMin = req.PriceMin
	p.PriceMax = req.PriceMax
	p.CooperationMode = req.CooperationMode
	p.Tags = req.Tags
	p.IsFeatured = req.IsFeatured
	p.SortOrder = req.SortOrder
	if req.Status > 0 {
		p.Status = models.ProviderStatus(req.Status)
	}
	h.db.Save(&p)
	utils.OK(c, p)
}

// Delete 删除
func (h *ProviderHandler) Delete(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	if err := h.db.Delete(&models.Provider{}, id).Error; err != nil {
		utils.ServerError(c, "删除失败")
		return
	}
	h.db.Where("provider_id = ?", id).Delete(&models.Qualification{})
	utils.OK(c, nil)
}

// UpdateStatus 修改状态
func (h *ProviderHandler) UpdateStatus(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req struct {
		Status int    `json:"status" binding:"required"`
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	var p models.Provider
	if err := h.db.First(&p, id).Error; err != nil {
		utils.NotFound(c, "服务商不存在")
		return
	}
	from := p.Status
	p.Status = models.ProviderStatus(req.Status)
	if req.Status == 2 {
		now := time.Now()
		p.ApprovedTime = &now
		uid := c.GetUint64("admin_id")
		p.ApprovedBy = &uid
		p.RejectReason = ""
	} else if req.Status == 4 {
		p.RejectReason = req.Reason
	}
	h.db.Save(&p)

	// 记录审核日志
	uid := c.GetUint64("admin_id")
	uname, _ := c.Get("username")
	h.db.Create(&models.ReviewLog{
		ProviderID: p.ID, ReviewerID: uid, ReviewerName: uname.(string),
		Action: "status_change", FromStatus: int(from), ToStatus: req.Status, Comment: req.Reason,
	})
	utils.OK(c, p)
}

// Review 审核操作
func (h *ProviderHandler) Review(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req struct {
		Action  string `json:"action" binding:"required,oneof=approve reject start_review"`
		Comment string `json:"comment"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	var p models.Provider
	if err := h.db.First(&p, id).Error; err != nil {
		utils.NotFound(c, "服务商不存在")
		return
	}
	from := p.Status
	uid := c.GetUint64("admin_id")
	uname, _ := c.Get("username")

	switch req.Action {
	case "start_review":
		p.Status = 1
	case "approve":
		p.Status = 2
		now := time.Now()
		p.ApprovedTime = &now
		p.ApprovedBy = &uid
		p.RejectReason = ""
	case "reject":
		p.Status = 4
		p.RejectReason = req.Comment
	}
	h.db.Save(&p)

	h.db.Create(&models.ReviewLog{
		ProviderID: p.ID, ReviewerID: uid, ReviewerName: uname.(string),
		Action: req.Action, FromStatus: int(from), ToStatus: int(p.Status), Comment: req.Comment,
	})
	utils.OK(c, p)
}

// ReviewHistory 审核历史
func (h *ProviderHandler) ReviewHistory(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var logs []models.ReviewLog
	h.db.Where("provider_id = ?", id).Order("id DESC").Find(&logs)
	utils.OK(c, logs)
}

// BatchAction 批量操作
func (h *ProviderHandler) BatchAction(c *gin.Context) {
	var req struct {
		IDs    []uint64 `json:"ids" binding:"required"`
		Action string   `json:"action" binding:"required,oneof=enable disable delete approve reject"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	switch req.Action {
	case "delete":
		h.db.Where("id IN ?", req.IDs).Delete(&models.Provider{})
	case "enable":
		h.db.Model(&models.Provider{}).Where("id IN ?", req.IDs).Update("status", 2)
	case "disable":
		h.db.Model(&models.Provider{}).Where("id IN ?", req.IDs).Update("status", 3)
	case "approve":
		now := time.Now()
		uid := c.GetUint64("admin_id")
		h.db.Model(&models.Provider{}).Where("id IN ?", req.IDs).Updates(map[string]interface{}{
			"status": 2, "approved_time": &now, "approved_by": &uid,
		})
	case "reject":
		h.db.Model(&models.Provider{}).Where("id IN ?", req.IDs).Update("status", 4)
	}
	utils.OK(c, nil)
}

// GetQualifications 获取资质
func (h *ProviderHandler) GetQualifications(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var qs []models.Qualification
	h.db.Where("provider_id = ?", id).Find(&qs)
	utils.OK(c, qs)
}

// AddQualification 添加资质
func (h *ProviderHandler) AddQualification(c *gin.Context) {
	id, _ := strconv.ParseUint(c.Param("id"), 10, 64)
	var req struct {
		Type       string `json:"type"`
		Name       string `json:"name" binding:"required"`
		FileURL    string `json:"file_url"`
		FileType   string `json:"file_type"`
		ExpireDate string `json:"expire_date"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.BadRequest(c, "参数错误")
		return
	}
	q := &models.Qualification{
		ProviderID: id, Type: req.Type, Name: req.Name,
		FileURL: req.FileURL, FileType: req.FileType,
	}
	if req.ExpireDate != "" {
		if t, err := time.Parse("2006-01-02", req.ExpireDate); err == nil {
			q.ExpireDate = &t
		}
	}
	h.db.Create(q)
	utils.OK(c, q)
}

// DeleteQualification 删除资质
func (h *ProviderHandler) DeleteQualification(c *gin.Context) {
	qid, _ := strconv.ParseUint(c.Param("qid"), 10, 64)
	h.db.Delete(&models.Qualification{}, qid)
	utils.OK(c, nil)
}

// Stats 统计分析
func (h *ProviderHandler) Stats(c *gin.Context) {
	now := time.Now()
	today := now.Truncate(24 * time.Hour)
	weekStart := now.AddDate(0, 0, -int(now.Weekday()))
	monthStart := now.AddDate(0, 0, -now.Day()+1)

	// 总数
	var total int64
	h.db.Model(&models.Provider{}).Count(&total)
	// 各状态
	var statusCount []struct {
		Status int   `json:"status"`
		Count  int64 `json:"count"`
	}
	h.db.Model(&models.Provider{}).Select("status, COUNT(*) as count").Group("status").Scan(&statusCount)
	// 今日新增
	var todayNew, weekNew, monthNew int64
	h.db.Model(&models.Provider{}).Where("created_at >= ?", today).Count(&todayNew)
	h.db.Model(&models.Provider{}).Where("created_at >= ?", weekStart).Count(&weekNew)
	h.db.Model(&models.Provider{}).Where("created_at >= ?", monthStart).Count(&monthNew)
	// 待审核
	var pending, reviewing int64
	h.db.Model(&models.Provider{}).Where("status = ?", 0).Count(&pending)
	h.db.Model(&models.Provider{}).Where("status = ?", 1).Count(&reviewing)

	// 分类分布
	var catDist []struct {
		CategoryID uint64 `json:"category_id"`
		Count      int64  `json:"count"`
	}
	h.db.Model(&models.Provider{}).Select("category_id, COUNT(*) as count").
		Where("status = ?", 2).Group("category_id").Scan(&catDist)

	// 地区分布
	var regionDist []struct {
		Region string `json:"region"`
		Count  int64  `json:"count"`
	}
	h.db.Model(&models.Provider{}).Select("region, COUNT(*) as count").
		Where("status = ?", 2).Group("region").Order("count DESC").Limit(10).Scan(&regionDist)

	// 30天趋势
	type Trend struct {
		Date  string `json:"date"`
		Count int64  `json:"count"`
	}
	var trends []Trend
	for i := 29; i >= 0; i-- {
		d := now.AddDate(0, 0, -i)
		ds := d.Truncate(24 * time.Hour)
		de := ds.Add(24 * time.Hour)
		var c int64
		h.db.Model(&models.Provider{}).Where("created_at >= ? AND created_at < ?", ds, de).Count(&c)
		trends = append(trends, Trend{Date: ds.Format("01-02"), Count: c})
	}

	// TOP 10
	var top []models.Provider
	h.db.Where("status = ?", 2).Order("rating DESC, deal_count DESC").Limit(10).Find(&top)

	// 总浏览量
	var totalViews int64
	h.db.Model(&models.Provider{}).Select("COALESCE(SUM(view_count), 0)").Scan(&totalViews)
	var totalDeals int64
	h.db.Model(&models.Provider{}).Select("COALESCE(SUM(deal_count), 0)").Scan(&totalDeals)

	utils.OK(c, gin.H{
		"total":       total,
		"today_new":   todayNew,
		"week_new":    weekNew,
		"month_new":   monthNew,
		"pending":     pending,
		"reviewing":   reviewing,
		"by_status":   statusCount,
		"by_category": catDist,
		"by_region":   regionDist,
		"trends":      trends,
		"top":         top,
		"total_views": totalViews,
		"total_deals": totalDeals,
	})
}

// PublicOverview 公开统计（用户端）
func (h *ProviderHandler) PublicOverview(c *gin.Context) {
	var totalProviders int64
	h.db.Model(&models.Provider{}).Where("status = ?", 2).Count(&totalProviders)
	var totalDeals int64
	h.db.Model(&models.Provider{}).Where("status = ?", 2).Select("COALESCE(SUM(deal_count), 0)").Scan(&totalDeals)
	var totalCategories int64
	h.db.Model(&models.Category{}).Where("status = ?", 1).Count(&totalCategories)
	utils.OK(c, gin.H{
		"providers":  totalProviders,
		"deals":      totalDeals,
		"categories": totalCategories,
	})
}
