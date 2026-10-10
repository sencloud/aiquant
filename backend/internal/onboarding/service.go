// Package onboarding 给首次登录的用户发送初始喜点 + 演示 DING + 欢迎通知，
// 让 App Store 审核员（用任意 sandbox Apple ID 登录）能立刻看到非空内容。
package onboarding

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/shell"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

const (
	// defaultSignupCredits 是 config credits.signup_gift 未配置时的兜底。
	defaultSignupCredits = 60
	bonusReason        = billing.ReasonSignupGift
	demoTaskTitle      = "今日 A 股复盘"
	demoTaskPrompt     = "请围绕沪深 300 / 中证 500 / 创业板指三大指数的最新走势做一段日终复盘，覆盖 1) 当日涨跌幅与成交量同比；2) 北向资金流向；3) 受关注的行业板块；4) 明日值得关注的事件。"
	demoTaskPersonaID  = "trader_assist"
	demoTaskSchedule   = "daily@18:00"
	demoTaskCost       = 5
	welcomeTopic       = "system.welcome"
	welcomeTitle       = "欢迎使用喜宽"
)

// Service 把 onboarding 工作打包成一个接口给 auth handler 调用。
//
// 内部依赖三个 repo：
//   - billing.LedgerRepo 写赠送流水（uq_ledger_idem 索引天然幂等）
//   - ding.TaskRepo 写演示任务（用 ListByUser 检测幂等）
//   - ding.NotificationRepo 写欢迎通知（同样按用户检测幂等）
type Service struct {
	st           *store.Store
	ledger       *billing.LedgerRepo
	tasks        *ding.TaskRepo
	notifs       *ding.NotificationRepo
	shells       *shell.Repo
	signupShells int64
	opts         Options
}

// Options 是赠送数额与对外文案里用到的价格（来自 config）。
type Options struct {
	SignupCredits int64 // 注册赠送喜点
	ChatCredits   int64 // 一轮对话
	DeepBonus     int64 // 深度模式额外
}

func New(
	st *store.Store,
	ledger *billing.LedgerRepo,
	tasks *ding.TaskRepo,
	notifs *ding.NotificationRepo,
	shells *shell.Repo,
	signupShells int64,
	opts Options,
) *Service {
	if opts.SignupCredits <= 0 {
		opts.SignupCredits = defaultSignupCredits
	}
	if opts.ChatCredits <= 0 {
		opts.ChatCredits = 1
	}
	return &Service{
		st: st, ledger: ledger, tasks: tasks, notifs: notifs,
		shells: shells, signupShells: signupShells, opts: opts,
	}
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
	if err := s.ensureSignupShells(ctx, user); err != nil {
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
		Delta:   s.opts.SignupCredits,
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

// ensureSignupShells 鹦鹉螺预测市场的初始螺壳(与喜点独立)。
//
// 螺壳已冻结（config nautilus.shells_frozen）时不发：鹦鹉螺在客户端隐藏，
// 新用户拿到一笔看不见、用不了的螺壳没有意义。
func (s *Service) ensureSignupShells(ctx context.Context, user *users.User) error {
	if s.shells == nil || s.signupShells <= 0 || shell.Frozen() {
		return nil
	}
	_, err := s.shells.Apply(ctx, shell.ApplyParams{
		UserID:  user.ID,
		Delta:   s.signupShells,
		Reason:  shell.ReasonSignupGift,
		RefType: "user",
		RefID:   user.UUID,
		Remark:  "首次登录赠送",
	})
	if err == nil || errors.Is(err, shell.ErrDuplicate) {
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
		BodyBrief: s.welcomeBrief(),
		Payload:   s.welcomePayload(),
	})
	return err
}

func (s *Service) welcomeBrief() string {
	return fmt.Sprintf("已为你赠送 %d 喜点。去「策略」看证伪档案，或在「对话」里直接提问", s.opts.SignupCredits)
}

func (s *Service) welcomePayload() string {
	deep := ""
	if s.opts.DeepBonus > 0 {
		deep = fmt.Sprintf("（深度模式另加 **%d 喜点**）", s.opts.DeepBonus)
	}
	return fmt.Sprintf(`# 欢迎使用喜爱

我是你的 AI 投研助理，可以帮你：

- 查 A 股 / ETF / 指数 / 期货的实时行情、财报、资金流和新闻
- 在「策略」里看每条策略的证伪档案：它过了哪几道闸门、死在哪一关
- 在「发现 → 定时提醒」里让 AI 按点帮你盯盘、复盘

我们已经为你送上 **%d 喜点**：

- 每轮对话消耗 **%d 喜点**%s
- 解锁一条证伪档案的分年盈亏、失效原因和复现命令按条计费，解锁后永久可看

试试在「对话」里问一句"今日大盘怎么样？"，或者打开「策略」看看哪些策略被证伪了。`,
		s.opts.SignupCredits, s.opts.ChatCredits, deep)
}
