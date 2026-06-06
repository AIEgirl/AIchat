package utils

import "time"

// TimeNow 当前时间
func TimeNow() time.Time {
	return time.Now()
}

// ParseTime 解析时间
func ParseTime(s string) (time.Time, error) {
	return time.Parse(time.RFC3339, s)
}

// TimeFormat 时间格式化
func TimeFormat(t time.Time) string {
	return t.Format("2006-01-02 15:04:05")
}

// TimeFormatPtr 时间格式化（指针）
func TimeFormatPtr(t *time.Time) string {
	if t == nil {
		return ""
	}
	return t.Format("2006-01-02 15:04:05")
}
