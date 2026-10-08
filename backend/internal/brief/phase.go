// Package brief 生成首页「今天想聊点什么」的快捷提问。
//
// 由 scheduler 在 A 股每个时段（盘前/早盘/午间/午后/收盘）落库一条，客户端
// 直接读最近一条；服务端不可用或尚未生成时，客户端回退到本地按行情拼装。
package brief

import "time"

// ShanghaiLoc 中国大陆交易所统一使用 Asia/Shanghai；容器缺 tzdata 时退回 +08:00。
var ShanghaiLoc = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return time.FixedZone("CST", 8*3600)
	}
	return loc
}()

// Phase 是 A 股当天的一个时段。
type Phase string

const (
	PhasePreOpen   Phase = "pre_open"  // 09:15 前
	PhaseMorning   Phase = "morning"   // 09:15–11:30
	PhaseNoon      Phase = "noon"      // 11:30–13:00（上午收盘）
	PhaseAfternoon Phase = "afternoon" // 13:00–15:00
	PhaseClosed    Phase = "closed"    // 15:00 后
)

var phaseLabels = map[Phase]string{
	PhasePreOpen:   "盘前",
	PhaseMorning:   "早盘",
	PhaseNoon:      "午间休市",
	PhaseAfternoon: "午后",
	PhaseClosed:    "收盘",
}

// Label 返回中文时段名。
func (p Phase) Label() string {
	if s, ok := phaseLabels[p]; ok {
		return s
	}
	return string(p)
}

// PhaseAt 按北京时间判断 t 属于哪个时段。
func PhaseAt(t time.Time) Phase {
	bj := t.In(ShanghaiLoc)
	m := bj.Hour()*60 + bj.Minute()
	switch {
	case m < 9*60+15:
		return PhasePreOpen
	case m < 11*60+30:
		return PhaseMorning
	case m < 13*60:
		return PhaseNoon
	case m < 15*60:
		return PhaseAfternoon
	default:
		return PhaseClosed
	}
}

// IsTradingDay 只按工作日近似判断；法定假日由「当天没有新行情」自然兜底，
// 生成出来的提问仍基于最近一个交易日的收盘数据。
func IsTradingDay(t time.Time) bool {
	wd := t.In(ShanghaiLoc).Weekday()
	return wd != time.Saturday && wd != time.Sunday
}

// SlotKey 是幂等键：同一天同一时段只生成一次。
func SlotKey(t time.Time) string {
	bj := t.In(ShanghaiLoc)
	return bj.Format("2006-01-02") + ":" + string(PhaseAt(bj))
}
