// Package onboarding 给首次登录的用户发送初始喜点 + 演示 DING + 欢迎通知，
// 让 App Store 审核员（用任意 sandbox Apple ID 登录）能立刻看到非空内容。
package onboarding

import (
	"context"
	"database/sql"
	"errors"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

const (
	signupBonusCredits = 100
	bonusReason        = billing.ReasonSignupGift
	demoTaskTitle      = "今日 A 股复盘"
	demoTaskPrompt     = "请围绕沪深 300 / 中证 500 / 创业板指三大指数的最新走势做一段日终复盘，覆盖 1) 当日涨跌幅与成交量同比；2) 北向资金流向；3) 受关注的行业板块；4) 明日值得关注的事件。"
	demoTaskPersonaID  = "trader_assist"
	demoTaskSchedule   = "daily@18:00"
	demoTaskCost       = 5
	welcomeTopic       = "system.welcome"
	welcomeTitle       = "欢迎使用喜宽"
	welcomeBrief       = "已为你赠送 10 喜点。点开 DING 看一个示例任务，或在「助理」里直接提问"
)

// Service 把 onboarding 工作打包成一个接口给 auth handler 调用。
//
// 内部依赖三个 repo：
//   - billing.LedgerRepo 写赠送流水（uq_ledger_idem 索引天然幂等）
//   - ding.TaskRepo 写演示任务（用 ListByUser 检测幂等）
//   - ding.NotificationRepo 写欢迎通知（同样按用户检测幂等）
type Service struct {
	st       *store.Store
	ledger   *billing.LedgerRepo
	tasks    *ding.TaskRepo
	notifs   *ding.NotificationRepo
}

func New(
	st *store.Store,
	ledger *billing.LedgerRepo,
	tasks *ding.TaskRepo,
	notifs *ding.NotificationRepo,
) *Service {
	return &Service{st: st, ledger: ledger, tasks: tasks, notifs: notifs}
}

// OnboardIfNeeded 在首次登录后调用。所有步骤都是幂等的，重复调用安全。
//
// 错误处理策略：任一步骤失败不影响登录流程，只记日志返回 nil 以外的 error
// 由调用方决定是否打 warn——因为登录已经成功，初始数据失败不应阻塞用户进 App。
func (s *Service) OnboardIfNeeded(ctx context.Context, user *users.User) error {
	if user == nil || user.Status != string(users.StatusActive) {
		return nil
	}
	if err := s.ensureSignupBonus(ctx, user); err != nil {
		return err
	}
	if err := s.ensureDemoTask(ctx, user.ID); err != nil {
		return err
	}
	if err := s.ensureWelcomeNotification(ctx, user.ID); err != nil {
		return err
	}
	return nil
}

func (s *Service) ensureSignupBonus(ctx context.Context, user *users.User) error {
	_, err := s.ledger.Apply(ctx, billing.ApplyParams{
		UserID:  user.ID,
		Delta:   signupBonusCredits,
		Reason:  bonusReason,
		RefType: "user",
		RefID:   user.UUID,
		Remark:  "首次登录赠送",
	})
	if err == nil {
		return nil
	}
	if errors.Is(err, billing.ErrLedgerDuplicate) {
		return nil
	}
	return err
}

func (s *Service) ensureDemoTask(ctx context.Context, userID int64) error {
	var exists int
	err := s.st.DB.GetContext(ctx, &exists,
		"SELECT 1 FROM ding_tasks WHERE user_id=? LIMIT 1", userID)
	if err == nil {
		return nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	_, err = s.tasks.Create(ctx, ding.CreateTaskInput{
		UserID:            userID,
		Title:             demoTaskTitle,
		Prompt:            demoTaskPrompt,
		PersonaID:         demoTaskPersonaID,
		Schedule:          demoTaskSchedule,
		Enabled:           false,
		CostCreditsPerRun: demoTaskCost,
	})
	return err
}

func (s *Service) ensureWelcomeNotification(ctx context.Context, userID int64) error {
	var exists int
	err := s.st.DB.GetContext(ctx, &exists,
		"SELECT 1 FROM notifications WHERE user_id=? AND topic=? LIMIT 1",
		userID, welcomeTopic)
	if err == nil {
		return nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	_, err = s.notifs.Create(ctx, ding.CreateNotifInput{
		UserID:    userID,
		Topic:     welcomeTopic,
		Title:     welcomeTitle,
		BodyBrief: welcomeBrief,
		Payload: `# 欢迎使用喜宽

我是你的 AI 投资助手，可以帮你：

- 查 A 股 / ETF / 指数 / 期货的实时行情
- 看财报、估值、资金流等数据，帮你做研究
- 在「DING」里设个定时任务，每天/每周自动给你发研究报告

我们已经为你送上 **10 喜点**：

- 每次回答消耗 **0.6 喜点**
- 含行情查询，则按次再加 **0.1 喜点**

试试在「助理」里问一句"今日大盘怎么样？"，或者打开「DING」体验示例任务。`,
	})
	return err
}
