// Package ding 实现 DING 定时任务 + 通知聚合的全部业务逻辑。
//
// schedule 字符串与客户端 lib/models/ding.dart 的 DingScheduleCodec 完全一致：
//   - "daily:HH:mm"          每天 HH:mm
//   - "weekly:N:HH:mm"       每周第 N 天（1=周一 ... 7=周日）
//   - "interval:M"           每 M 分钟
package ding

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

var ErrInvalidSchedule = errors.New("invalid schedule expression")

// NextFireTime 计算 schedule 在 from 之后（严格大于）的下一次触发时间。
func NextFireTime(schedule string, from time.Time) (time.Time, error) {
	parts := strings.Split(schedule, ":")
	if len(parts) == 0 {
		return time.Time{}, ErrInvalidSchedule
	}
	switch parts[0] {
	case "daily":
		if len(parts) < 3 {
			return time.Time{}, fmt.Errorf("%w: daily needs HH:mm", ErrInvalidSchedule)
		}
		h, err := atoi(parts[1])
		if err != nil {
			return time.Time{}, err
		}
		m, err := atoi(parts[2])
		if err != nil {
			return time.Time{}, err
		}
		if !validHM(h, m) {
			return time.Time{}, fmt.Errorf("%w: invalid HH:mm", ErrInvalidSchedule)
		}
		t := time.Date(from.Year(), from.Month(), from.Day(), h, m, 0, 0, from.Location())
		if !t.After(from) {
			t = t.AddDate(0, 0, 1)
		}
		return t, nil
	case "weekly":
		if len(parts) < 4 {
			return time.Time{}, fmt.Errorf("%w: weekly needs N:HH:mm", ErrInvalidSchedule)
		}
		wd, err := atoi(parts[1])
		if err != nil {
			return time.Time{}, err
		}
		if wd < 1 || wd > 7 {
			return time.Time{}, fmt.Errorf("%w: weekly N must be 1..7", ErrInvalidSchedule)
		}
		h, err := atoi(parts[2])
		if err != nil {
			return time.Time{}, err
		}
		m, err := atoi(parts[3])
		if err != nil {
			return time.Time{}, err
		}
		if !validHM(h, m) {
			return time.Time{}, fmt.Errorf("%w: invalid HH:mm", ErrInvalidSchedule)
		}
		t := time.Date(from.Year(), from.Month(), from.Day(), h, m, 0, 0, from.Location())
		// time.Weekday: Sun=0..Sat=6；客户端约定 1=Mon..7=Sun
		current := int(t.Weekday())
		if current == 0 {
			current = 7
		}
		diff := (wd - current) % 7
		if diff < 0 {
			diff += 7
		}
		t = t.AddDate(0, 0, diff)
		if !t.After(from) {
			t = t.AddDate(0, 0, 7)
		}
		return t, nil
	case "interval":
		if len(parts) < 2 {
			return time.Time{}, fmt.Errorf("%w: interval needs minutes", ErrInvalidSchedule)
		}
		mins, err := atoi(parts[1])
		if err != nil {
			return time.Time{}, err
		}
		if mins < 5 {
			return time.Time{}, fmt.Errorf("%w: interval must be >= 5min", ErrInvalidSchedule)
		}
		return from.Add(time.Duration(mins) * time.Minute), nil
	default:
		return time.Time{}, fmt.Errorf("%w: unknown kind %q", ErrInvalidSchedule, parts[0])
	}
}

// ValidateSchedule 仅校验语法是否合法，不计算时间。
func ValidateSchedule(schedule string) error {
	_, err := NextFireTime(schedule, time.Now())
	return err
}

func atoi(s string) (int, error) {
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("%w: not int %q", ErrInvalidSchedule, s)
	}
	return n, nil
}

func validHM(h, m int) bool { return h >= 0 && h < 24 && m >= 0 && m < 60 }
