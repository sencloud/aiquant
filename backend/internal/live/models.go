// Package live 实现 v2「AI 直播间」：每场直播是一个长会话(live_room),
// 由 1 名 host(主持人 persona) + N 名 guest(嘉宾 persona) 实时聊天产出。
//
// 与 v1 区别(已废弃):
//   v1: 每场预选 3-5 只票,每只票每个 persona 独立写一份静态 markdown 报告;
//   v2: 主持人持续决策"问谁、聊哪只票",嘉宾轮流应答,消息流式落库,
//       前端轮询拉新消息,主图 K 线随讨论焦点(focus_symbol)切换。
//
// 与 DING 区别同 v1:DING 用户付费,直播是系统服务不扣费。
package live

import (
	"database/sql"
	"time"
)

// 直播间生命周期。
const (
	RoomLive          = "live"           // 正在进行
	RoomEnded         = "ended"          // 正常结束(到达预定消息数 / 时长)
	RoomEndedAbnormal = "ended_abnormal" // 异常结束(LLM 连续失败 / runner 中断)
)

// 市场阶段(沿用 v1)。
const (
	PhasePre      = "pre"
	PhaseIntraday = "intraday"
	PhasePost     = "post"
)

// 直播间触发来源 —— 决定是否受"15 分钟硬截止"约束。
const (
	OriginAuto   = "auto"   // scheduler 在 4 个定时窗口创建
	OriginManual = "manual" // 用户 HTTP 主动触发,有 auto_end_at(默认 +15min)
)

// ManualRoomDuration 是 origin='manual' 房间的硬时长。
// liveLoop 每轮检查 now > started_at + ManualRoomDuration 则主动 host_close。
const ManualRoomDuration = 15 * time.Minute

// 消息角色 — 决定前端展示样式 + LLM prompt 注入策略。
const (
	RoleHostOpen    = "host_open"    // 主持人开场白
	RoleHostAsk     = "host_ask"     // 主持人提问/点名(focus 已选定)
	RoleHostSwitch  = "host_switch"  // 主持人主动切换焦点股票
	RoleHostClose   = "host_close"   // 主持人收尾陈词
	RoleGuestAnswer = "guest_answer" // 嘉宾正式应答 host 的提问
	RoleGuestReact  = "guest_react"  // 嘉宾自发对前一条插话/反驳
	RoleSystem      = "system"       // 系统消息(异常 / 提示)
)

// Room 是单场直播间数据库行。
type Room struct {
	ID                  int64          `db:"id"`
	UUID                string         `db:"uuid"`
	Title               string         `db:"title"`
	Phase               string         `db:"phase"`
	Status              string         `db:"status"`
	HostPersona         string         `db:"host_persona"`
	HostPersonaName     string         `db:"host_persona_name"`
	GuestPersonas       string         `db:"guest_personas"` // JSON [{"id","name"}]
	CurrentFocusSymbol  sql.NullString `db:"current_focus_symbol"`
	CurrentFocusName    sql.NullString `db:"current_focus_name"`
	MessageCount        int            `db:"message_count"`
	StartedAt           int64          `db:"started_at"`
	EndedAt             sql.NullInt64  `db:"ended_at"`
	Error               sql.NullString `db:"error"`
	CreatedAt           int64          `db:"created_at"`
	Origin              string         `db:"origin"`
	AutoEndAt           sql.NullInt64  `db:"auto_end_at"`
}

// Message 是单条聊天消息数据库行。
type Message struct {
	ID             int64          `db:"id"`
	RoomID         int64          `db:"room_id"`
	Idx            int            `db:"idx"`
	Role           string         `db:"role"`
	Persona        string         `db:"persona"`
	PersonaName    string         `db:"persona_name"`
	TargetPersona  sql.NullString `db:"target_persona"`
	FocusSymbol    sql.NullString `db:"focus_symbol"`
	FocusName      sql.NullString `db:"focus_name"`
	Content        string         `db:"content"`
	CreatedAt      int64          `db:"created_at"`
}

// PersonaRef 是 host/guest 的"轻量名片",用于 LLM prompt 描述 + 入库 JSON。
type PersonaRef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func nowMs() int64 { return time.Now().UnixMilli() }
