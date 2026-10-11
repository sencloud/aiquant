package fishing

import (
	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/store"
)

// Service 汇总喜爱钓鱼的服务端能力：出钓指数、禁渔提示、拍照识鱼、渔获日记 / 私人钓点。
type Service struct {
	Forecast *Forecaster
	Identify *Identifier
	Journal  *Journal
}

// NewService 构造。vision 为 nil 时识鱼接口返回 503。
func NewService(st *store.Store, w WeatherSource, vision Vision, l *zerolog.Logger) *Service {
	return &Service{
		Forecast: NewForecaster(w),
		Identify: NewIdentifier(st, vision, l),
		Journal:  NewJournal(st),
	}
}
