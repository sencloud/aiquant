package realtime

import (
	"sync"
	"time"
)

// ttlCache 是带「短期 TTL + 单飞(singleflight)」的泛型缓存。
//
// 两类典型复用：
//   - 行情快照：TTL 十几秒，吸收同一标的的高频重复请求（多直播间 / 多轮对话同时问同一支股票）；
//   - secid 解析：TTL 数小时，符号 → 东财 secid 基本不变，避免每次都打 suggest 接口。
//
// 单飞语义：同一 key 的并发加载只会真正执行一次网络请求，其余并发调用复用同一结果，
// 把「短时间内的重复调用」从源头压成一次出网。
type ttlCache[V any] struct {
	ttl      time.Duration
	mu       sync.Mutex
	items    map[string]cacheEntry[V]
	inflight map[string]*cacheCall[V]
}

type cacheEntry[V any] struct {
	val    V
	expire time.Time
}

type cacheCall[V any] struct {
	done chan struct{}
	val  V
	err  error
}

func newTTLCache[V any](ttl time.Duration) *ttlCache[V] {
	return &ttlCache[V]{
		ttl:      ttl,
		items:    make(map[string]cacheEntry[V]),
		inflight: make(map[string]*cacheCall[V]),
	}
}

// Do 返回 key 对应的值：
//   - 命中未过期缓存 → 直接返回；
//   - 已有同 key 在途加载 → 等待并复用其结果；
//   - 否则发起一次 load，成功才写入缓存（失败不缓存，下次重试）。
func (c *ttlCache[V]) Do(key string, load func() (V, error)) (V, error) {
	c.mu.Lock()
	if e, ok := c.items[key]; ok && time.Now().Before(e.expire) {
		c.mu.Unlock()
		return e.val, nil
	}
	if call, ok := c.inflight[key]; ok {
		c.mu.Unlock()
		<-call.done
		return call.val, call.err
	}
	call := &cacheCall[V]{done: make(chan struct{})}
	c.inflight[key] = call
	c.mu.Unlock()

	call.val, call.err = load()

	c.mu.Lock()
	if call.err == nil {
		c.items[key] = cacheEntry[V]{val: call.val, expire: time.Now().Add(c.ttl)}
	}
	delete(c.inflight, key)
	c.mu.Unlock()
	close(call.done)
	return call.val, call.err
}
