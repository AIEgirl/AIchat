package handlers

import (
	"strconv"
	"time"

	"github.com/aichat/relay/internal/models"
	"github.com/aichat/relay/internal/utils"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// FinanceHandler 财务处理器
type FinanceHandler struct {
	db *gorm.DB
}

// NewFinanceHandler 创建财务处理器
func NewFinanceHandler(db *gorm.DB) *FinanceHandler {
	return &FinanceHandler{db: db}
}

// TransactionList 交易流水
func (h *FinanceHandler) TransactionList(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	query := h.db.Model(&models.Transaction{})
	if userID := c.Query("user_id"); userID != "" {
		if id, err := strconv.ParseUint(userID, 10, 64); err == nil {
			query = query.Where("user_id = ?", id)
		}
	}
	if txType := c.Query("type"); txType != "" {
		query = query.Where("type = ?", txType)
	}
	if status := c.Query("status"); status != "" {
		query = query.Where("status = ?", status)
	}
	if method := c.Query("payment_method"); method != "" {
		query = query.Where("payment_method = ?", method)
	}
	if startTime := c.Query("start_time"); startTime != "" {
		if t, err := time.Parse(time.RFC3339, startTime); err == nil {
			query = query.Where("created_at >= ?", t)
		}
	}
	if endTime := c.Query("end_time"); endTime != "" {
		if t, err := time.Parse(time.RFC3339, endTime); err == nil {
			query = query.Where("created_at <= ?", t)
		}
	}

	var total int64
	query.Count(&total)

	var transactions []models.Transaction
	if err := query.Order("id DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&transactions).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	utils.Page(c, transactions, total, page, pageSize)
}

// FinanceStats 财务统计
func (h *FinanceHandler) Stats(c *gin.Context) {
	now := time.Now()
	todayStart := now.Truncate(24 * time.Hour)
	weekStart := now.AddDate(0, 0, -int(now.Weekday()))
	monthStart := now.AddDate(0, 0, -now.Day()+1)

	stats := h.getPeriodStats(todayStart, now, "today")
	stats["week"] = h.getPeriodStats(weekStart, now, "week")
	stats["month"] = h.getPeriodStats(monthStart, now, "month")
	stats["all"] = h.getPeriodStats(time.Time{}, now, "all")

	// 每日趋势（最近30天）
	trends := h.getDailyTrends(30)
	stats["trends"] = trends

	utils.Success(c, stats)
}

func (h *FinanceHandler) getPeriodStats(start, end time.Time, label string) gin.H {
	query := h.db.Model(&models.Transaction{})
	if !start.IsZero() {
		query = query.Where("created_at >= ?", start)
	}

	// 总充值
	var totalRecharge float64
	query.Where("type = ? AND status = ?", models.OrderRecharge, models.OrderPaid).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalRecharge)

	// 总消费
	var totalConsume float64
	query.Where("type = ? AND status = ?", models.OrderConsume, models.OrderPaid).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalConsume)

	// 总退款
	var totalRefund float64
	query.Where("type = ? AND status = ?", models.OrderRefund, models.OrderRefunded).
		Select("COALESCE(SUM(amount), 0)").Scan(&totalRefund)

	// 交易笔数
	var totalCount int64
	query.Count(&totalCount)

	// 充值笔数
	var rechargeCount int64
	query.Where("type = ?", models.OrderRecharge).Count(&rechargeCount)

	return gin.H{
		"label":         label,
		"recharge":      totalRecharge,
		"consume":       totalConsume,
		"refund":        totalRefund,
		"net_income":    totalRecharge - totalConsume - totalRefund,
		"total_count":   totalCount,
		"recharge_count": rechargeCount,
	}
}

// DailyTrend 每日趋势数据
type DailyTrend struct {
	Date     string  `json:"date"`
	Recharge float64 `json:"recharge"`
	Consume  float64 `json:"consume"`
	Profit   float64 `json:"profit"`
}

func (h *FinanceHandler) getDailyTrends(days int) []DailyTrend {
	var trends []DailyTrend
	for i := days - 1; i >= 0; i-- {
		date := time.Now().AddDate(0, 0, -i)
		dayStart := date.Truncate(24 * time.Hour)
		dayEnd := dayStart.Add(24 * time.Hour)

		var recharge, consume float64
		h.db.Model(&models.Transaction{}).
			Where("type = ? AND status = ? AND created_at >= ? AND created_at < ?",
				models.OrderRecharge, models.OrderPaid, dayStart, dayEnd).
			Select("COALESCE(SUM(amount), 0)").Scan(&recharge)
		h.db.Model(&models.Transaction{}).
			Where("type = ? AND status = ? AND created_at >= ? AND created_at < ?",
				models.OrderConsume, models.OrderPaid, dayStart, dayEnd).
			Select("COALESCE(SUM(amount), 0)").Scan(&consume)

		trends = append(trends, DailyTrend{
			Date:     dayStart.Format("01-02"),
			Recharge: recharge,
			Consume:  consume,
			Profit:   recharge - consume,
		})
	}
	return trends
}

// TopUsers 高消费用户
func (h *FinanceHandler) TopUsers(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	if limit < 1 || limit > 100 {
		limit = 10
	}

	type UserStat struct {
		UserID       uint64  `json:"user_id"`
		Username     string  `json:"username"`
		Email        string  `json:"email"`
		TotalSpent   float64 `json:"total_spent"`
		TotalRecharged float64 `json:"total_recharged"`
		Balance      float64 `json:"balance"`
		CallCount    int64   `json:"call_count"`
	}

	var stats []UserStat
	h.db.Model(&models.User{}).
		Select(`users.id as user_id, users.username, users.email, users.total_spent,
			users.total_recharged, users.balance,
			COALESCE((SELECT COUNT(*) FROM api_request_logs WHERE user_id = users.id), 0) as call_count`).
		Order("total_spent DESC").
		Limit(limit).
		Scan(&stats)

	// 脱敏
	for i := range stats {
		stats[i].Email = utils.MaskEmail(stats[i].Email)
	}

	utils.Success(c, stats)
}

// ExportTransactions 导出交易记录（CSV）
func (h *FinanceHandler) ExportTransactions(c *gin.Context) {
	startTime := c.Query("start_time")
	endTime := c.Query("end_time")

	query := h.db.Model(&models.Transaction{}).Where("status = ?", models.OrderPaid)
	if startTime != "" {
		if t, err := time.Parse(time.RFC3339, startTime); err == nil {
			query = query.Where("created_at >= ?", t)
		}
	}
	if endTime != "" {
		if t, err := time.Parse(time.RFC3339, endTime); err == nil {
			query = query.Where("created_at <= ?", t)
		}
	}

	var transactions []models.Transaction
	if err := query.Order("id DESC").Limit(10000).Find(&transactions).Error; err != nil {
		utils.ServerError(c, "查询失败")
		return
	}

	// 构建CSV
	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", "attachment; filename=transactions.csv")
	c.Writer.WriteString("\xEF\xBB\xBF") // UTF-8 BOM
	c.Writer.WriteString("订单号,用户ID,类型,金额,支付方式,状态,描述,创建时间\n")
	for _, t := range transactions {
		c.Writer.WriteString(t.OrderNo + "," +
			strconv.FormatUint(t.UserID, 10) + "," +
			string(t.Type) + "," +
			strconv.FormatFloat(t.Amount, 'f', 4, 64) + "," +
			string(t.PaymentMethod) + "," +
			string(t.Status) + "," +
			t.Description + "," +
			t.CreatedAt.Format("2006-01-02 15:04:05") + "\n")
	}
}
