package fishing

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"math"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/sencloud/finme-backend/internal/store"
)

// MaxPhotoBytes 渔获照片解码后最大字节数（客户端压到 ≤1280px JPEG）。
const MaxPhotoBytes = 800 << 10

var (
	ErrNotFound     = errors.New("not found")
	ErrInvalidInput = errors.New("invalid input")
	ErrNoPhoto      = errors.New("no photo")
)

// Journal 渔获日记 + 私人钓点（按用户私有）。
type Journal struct{ st *store.Store }

// NewJournal 构造。
func NewJournal(st *store.Store) *Journal { return &Journal{st: st} }

func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ── 钓点 ────────────────────────────────────────────────────────────

// Spot 私人钓点。
type Spot struct {
	UUID      string   `json:"uuid" db:"uuid"`
	Name      string   `json:"name" db:"name"`
	Lat       *float64 `json:"lat" db:"lat"`
	Lon       *float64 `json:"lon" db:"lon"`
	WaterType string   `json:"water_type" db:"water_type"`
	Note      string   `json:"note" db:"note"`
	CreatedAt int64    `json:"created_at" db:"created_at"`
	UpdatedAt int64    `json:"updated_at" db:"updated_at"`
}

// SpotInput 新建 / 修改钓点。
type SpotInput struct {
	Name      string   `json:"name"`
	Lat       *float64 `json:"lat"`
	Lon       *float64 `json:"lon"`
	WaterType string   `json:"water_type"`
	Note      string   `json:"note"`
}

func (in *SpotInput) clean() error {
	in.Name = strings.TrimSpace(in.Name)
	in.WaterType = strings.TrimSpace(in.WaterType)
	in.Note = strings.TrimSpace(in.Note)
	if in.Name == "" || utf8.RuneCountInString(in.Name) > 40 ||
		utf8.RuneCountInString(in.WaterType) > 20 || utf8.RuneCountInString(in.Note) > 500 {
		return ErrInvalidInput
	}
	if (in.Lat == nil) != (in.Lon == nil) || !validCoord(in.Lat, in.Lon) {
		return ErrInvalidInput
	}
	return nil
}

func validCoord(lat, lon *float64) bool {
	if lat == nil || lon == nil {
		return true
	}
	return !math.IsNaN(*lat) && !math.IsNaN(*lon) && *lat >= -90 && *lat <= 90 && *lon >= -180 && *lon <= 180
}

const spotCols = "uuid, name, lat, lon, COALESCE(water_type,'') AS water_type, COALESCE(note,'') AS note, created_at, updated_at"

// ListSpots 最近更新在前，最多 200 个。
func (j *Journal) ListSpots(ctx context.Context, uid int64) ([]Spot, error) {
	out := []Spot{}
	err := j.st.DB.SelectContext(ctx, &out,
		"SELECT "+spotCols+" FROM fishing_spots WHERE user_id=? ORDER BY updated_at DESC, id DESC LIMIT 200", uid)
	return out, err
}

// CreateSpot 新建钓点。
func (j *Journal) CreateSpot(ctx context.Context, uid int64, in SpotInput) (*Spot, error) {
	if err := in.clean(); err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	s := &Spot{UUID: newUUID(), Name: in.Name, Lat: in.Lat, Lon: in.Lon, WaterType: in.WaterType, Note: in.Note, CreatedAt: now, UpdatedAt: now}
	_, err := j.st.DB.ExecContext(ctx, `
		INSERT INTO fishing_spots(uuid, user_id, name, lat, lon, water_type, note, created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		s.UUID, uid, s.Name, s.Lat, s.Lon, s.WaterType, s.Note, now, now)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// UpdateSpot 整体覆盖钓点字段。
func (j *Journal) UpdateSpot(ctx context.Context, uid int64, id string, in SpotInput) (*Spot, error) {
	if err := in.clean(); err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	res, err := j.st.DB.ExecContext(ctx, `
		UPDATE fishing_spots SET name=?, lat=?, lon=?, water_type=?, note=?, updated_at=?
		WHERE uuid=? AND user_id=?`, in.Name, in.Lat, in.Lon, in.WaterType, in.Note, now, id, uid)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, ErrNotFound
	}
	var s Spot
	err = j.st.DB.GetContext(ctx, &s, "SELECT "+spotCols+" FROM fishing_spots WHERE uuid=? AND user_id=?", id, uid)
	return &s, err
}

// DeleteSpot 删除钓点（渔获里冗余存的 spot_name 保留）。
func (j *Journal) DeleteSpot(ctx context.Context, uid int64, id string) error {
	res, err := j.st.DB.ExecContext(ctx, "DELETE FROM fishing_spots WHERE uuid=? AND user_id=?", id, uid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ── 渔获 ────────────────────────────────────────────────────────────

// Catch 一条渔获记录（不含照片字节）。
type Catch struct {
	UUID     string   `json:"uuid" db:"uuid"`
	CaughtAt int64    `json:"caught_at" db:"caught_at"`
	Species  string   `json:"species" db:"species"`
	Count    int      `json:"count" db:"count"`
	WeightG  *int64   `json:"weight_g" db:"weight_g"`
	LengthCM *float64 `json:"length_cm" db:"length_cm"`
	SpotUUID string   `json:"spot_uuid" db:"spot_uuid"`
	SpotName string   `json:"spot_name" db:"spot_name"`
	Lat      *float64 `json:"lat" db:"lat"`
	Lon      *float64 `json:"lon" db:"lon"`
	Method   string   `json:"method" db:"method"`
	Bait     string   `json:"bait" db:"bait"`
	Weather  string   `json:"weather" db:"weather"`
	Note     string   `json:"note" db:"note"`
	Released bool     `json:"released" db:"released"`
	HasPhoto bool     `json:"has_photo" db:"has_photo"`
	// CreatedAt / UpdatedAt 毫秒。
	CreatedAt int64 `json:"created_at" db:"created_at"`
	UpdatedAt int64 `json:"updated_at" db:"updated_at"`
}

// CatchInput 新建渔获。Photo 为可选 data URL（data:image/jpeg;base64,...）。
type CatchInput struct {
	CaughtAt int64    `json:"caught_at"`
	Species  string   `json:"species"`
	Count    int      `json:"count"`
	WeightG  *int64   `json:"weight_g"`
	LengthCM *float64 `json:"length_cm"`
	SpotUUID string   `json:"spot_uuid"`
	SpotName string   `json:"spot_name"`
	Lat      *float64 `json:"lat"`
	Lon      *float64 `json:"lon"`
	Method   string   `json:"method"`
	Bait     string   `json:"bait"`
	Weather  string   `json:"weather"`
	Note     string   `json:"note"`
	Released bool     `json:"released"`
	Photo    string   `json:"photo"`
}

const catchCols = `uuid, caught_at, species, count, weight_g, length_cm,
	COALESCE(spot_uuid,'') AS spot_uuid, COALESCE(spot_name,'') AS spot_name, lat, lon,
	COALESCE(method,'') AS method, COALESCE(bait,'') AS bait, COALESCE(weather,'') AS weather,
	COALESCE(note,'') AS note, released, (photo IS NOT NULL) AS has_photo, created_at, updated_at`

// ListCatches 按出钓时间倒序分页：before=0 从最新开始。
func (j *Journal) ListCatches(ctx context.Context, uid int64, before int64, limit int) ([]Catch, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	if before <= 0 {
		before = math.MaxInt64
	}
	out := []Catch{}
	err := j.st.DB.SelectContext(ctx, &out,
		"SELECT "+catchCols+" FROM fishing_catches WHERE user_id=? AND caught_at<? ORDER BY caught_at DESC, id DESC LIMIT ?",
		uid, before, limit)
	return out, err
}

// CatchStats 渔获汇总。
type CatchStats struct {
	Trips    int `json:"trips" db:"trips"`
	Fish     int `json:"fish" db:"fish"`
	Species  int `json:"species" db:"species"`
	Released int `json:"released" db:"released"`
}

// Stats 全量汇总（条数、鱼数、鱼种数、放流条数）。
func (j *Journal) Stats(ctx context.Context, uid int64) (CatchStats, error) {
	var s CatchStats
	err := j.st.DB.GetContext(ctx, &s, `
		SELECT COUNT(*) AS trips, COALESCE(SUM(count),0) AS fish, COUNT(DISTINCT species) AS species,
		       COALESCE(SUM(CASE WHEN released=1 THEN count ELSE 0 END),0) AS released
		FROM fishing_catches WHERE user_id=?`, uid)
	return s, err
}

// CreateCatch 新建渔获。
func (j *Journal) CreateCatch(ctx context.Context, uid int64, in CatchInput) (*Catch, error) {
	in.Species = strings.TrimSpace(in.Species)
	in.SpotName = strings.TrimSpace(in.SpotName)
	if in.Species == "" || utf8.RuneCountInString(in.Species) > 30 ||
		utf8.RuneCountInString(in.SpotName) > 40 || utf8.RuneCountInString(in.Method) > 20 ||
		utf8.RuneCountInString(in.Bait) > 60 || utf8.RuneCountInString(in.Weather) > 120 ||
		utf8.RuneCountInString(in.Note) > 1000 {
		return nil, ErrInvalidInput
	}
	if in.Count <= 0 {
		in.Count = 1
	}
	if in.Count > 9999 || (in.WeightG != nil && (*in.WeightG < 0 || *in.WeightG > 1_000_000)) ||
		(in.LengthCM != nil && (*in.LengthCM < 0 || *in.LengthCM > 500)) ||
		(in.Lat == nil) != (in.Lon == nil) || !validCoord(in.Lat, in.Lon) {
		return nil, ErrInvalidInput
	}
	now := time.Now().UnixMilli()
	if in.CaughtAt <= 0 {
		in.CaughtAt = now
	}
	if in.CaughtAt > now+24*3600*1000 {
		return nil, ErrInvalidInput
	}
	var photo []byte
	var mime string
	if in.Photo != "" {
		var err error
		photo, mime, err = decodePhoto(in.Photo)
		if err != nil {
			return nil, err
		}
	}
	// 关联钓点：只接受自己的钓点；名字以钓点为准。
	if in.SpotUUID != "" {
		var sp Spot
		err := j.st.DB.GetContext(ctx, &sp, "SELECT "+spotCols+" FROM fishing_spots WHERE uuid=? AND user_id=?", in.SpotUUID, uid)
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrInvalidInput
		}
		if err != nil {
			return nil, err
		}
		in.SpotName = sp.Name
		if in.Lat == nil {
			in.Lat, in.Lon = sp.Lat, sp.Lon
		}
	}
	c := &Catch{
		UUID: newUUID(), CaughtAt: in.CaughtAt, Species: in.Species, Count: in.Count,
		WeightG: in.WeightG, LengthCM: in.LengthCM, SpotUUID: in.SpotUUID, SpotName: in.SpotName,
		Lat: in.Lat, Lon: in.Lon, Method: strings.TrimSpace(in.Method), Bait: strings.TrimSpace(in.Bait),
		Weather: strings.TrimSpace(in.Weather), Note: strings.TrimSpace(in.Note), Released: in.Released,
		HasPhoto: photo != nil, CreatedAt: now, UpdatedAt: now,
	}
	_, err := j.st.DB.ExecContext(ctx, `
		INSERT INTO fishing_catches(uuid, user_id, caught_at, species, count, weight_g, length_cm,
			spot_uuid, spot_name, lat, lon, method, bait, weather, note, released, photo, photo_mime,
			created_at, updated_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		c.UUID, uid, c.CaughtAt, c.Species, c.Count, c.WeightG, c.LengthCM,
		nullIfEmpty(c.SpotUUID), nullIfEmpty(c.SpotName), c.Lat, c.Lon, c.Method, c.Bait, c.Weather, c.Note,
		c.Released, photo, nullIfEmpty(mime), now, now)
	if err != nil {
		return nil, err
	}
	return c, nil
}

// DeleteCatch 删除渔获（连同照片）。
func (j *Journal) DeleteCatch(ctx context.Context, uid int64, id string) error {
	res, err := j.st.DB.ExecContext(ctx, "DELETE FROM fishing_catches WHERE uuid=? AND user_id=?", id, uid)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// CatchPhoto 读渔获照片字节。
func (j *Journal) CatchPhoto(ctx context.Context, uid int64, id string) ([]byte, string, error) {
	var row struct {
		Photo []byte         `db:"photo"`
		Mime  sql.NullString `db:"photo_mime"`
	}
	err := j.st.DB.GetContext(ctx, &row, "SELECT photo, photo_mime FROM fishing_catches WHERE uuid=? AND user_id=?", id, uid)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, "", ErrNotFound
	}
	if err != nil {
		return nil, "", err
	}
	if len(row.Photo) == 0 {
		return nil, "", ErrNoPhoto
	}
	mime := row.Mime.String
	if mime == "" {
		mime = "image/jpeg"
	}
	return row.Photo, mime, nil
}

func decodePhoto(dataURL string) ([]byte, string, error) {
	m := imageDataURLPrefixRe.FindStringSubmatch(dataURL)
	if m == nil {
		return nil, "", ErrBadImage
	}
	raw, err := base64.StdEncoding.DecodeString(dataURL[len(m[0]):])
	if err != nil || len(raw) == 0 || len(raw) > MaxPhotoBytes {
		return nil, "", ErrBadImage
	}
	sub := m[1]
	if sub == "jpg" {
		sub = "jpeg"
	}
	return raw, "image/" + sub, nil
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
