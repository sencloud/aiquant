package fishing

import (
	"context"
	"encoding/base64"
	"errors"
	"testing"
)

func f64(v float64) *float64 { return &v }

func TestJournalSpotsAndCatches(t *testing.T) {
	st := openStore(t)
	a, b := newUser(t, st, 0), newUser(t, st, 0)
	j := NewJournal(st)
	ctx := context.Background()

	sp, err := j.CreateSpot(ctx, a, SpotInput{Name: " 老河湾 ", Lat: f64(30.1), Lon: f64(120.2), WaterType: "野河"})
	if err != nil || sp.Name != "老河湾" {
		t.Fatalf("%+v %v", sp, err)
	}
	if _, err := j.CreateSpot(ctx, a, SpotInput{Name: "x", Lat: f64(30)}); !errors.Is(err, ErrInvalidInput) {
		t.Fatal("lat without lon")
	}
	if _, err := j.UpdateSpot(ctx, b, sp.UUID, SpotInput{Name: "偷改"}); !errors.Is(err, ErrNotFound) {
		t.Fatal("other user update")
	}
	if up, err := j.UpdateSpot(ctx, a, sp.UUID, SpotInput{Name: "老河湾2", Lat: f64(30.1), Lon: f64(120.2)}); err != nil || up.Name != "老河湾2" {
		t.Fatalf("%+v %v", up, err)
	}

	photo := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString([]byte{0xff, 0xd8, 0xff, 1, 2})
	c, err := j.CreateCatch(ctx, a, CatchInput{Species: "鲫鱼", Count: 3, SpotUUID: sp.UUID, Photo: photo, Released: true})
	if err != nil || c.SpotName != "老河湾2" || c.Lat == nil || !c.HasPhoto {
		t.Fatalf("%+v %v", c, err)
	}
	if _, err := j.CreateCatch(ctx, b, CatchInput{Species: "鲤鱼", SpotUUID: sp.UUID}); !errors.Is(err, ErrInvalidInput) {
		t.Fatal("other user's spot")
	}
	if _, err := j.CreateCatch(ctx, a, CatchInput{Species: ""}); !errors.Is(err, ErrInvalidInput) {
		t.Fatal("empty species")
	}
	if _, err := j.CreateCatch(ctx, a, CatchInput{Species: "鲤鱼", Photo: "data:image/gif;base64,AAAA"}); !errors.Is(err, ErrBadImage) {
		t.Fatal("bad photo")
	}
	if _, err := j.CreateCatch(ctx, a, CatchInput{Species: "草鱼", CaughtAt: c.CaughtAt - 1000}); err != nil {
		t.Fatal(err)
	}

	list, err := j.ListCatches(ctx, a, 0, 10)
	if err != nil || len(list) != 2 || list[0].Species != "鲫鱼" || !list[0].HasPhoto || list[1].HasPhoto {
		t.Fatalf("%+v %v", list, err)
	}
	if l, _ := j.ListCatches(ctx, b, 0, 10); len(l) != 0 {
		t.Fatal("leak to other user")
	}
	if s, _ := j.Stats(ctx, a); s.Trips != 2 || s.Fish != 4 || s.Species != 2 || s.Released != 3 {
		t.Fatalf("stats %+v", s)
	}
	bs, mime, err := j.CatchPhoto(ctx, a, c.UUID)
	if err != nil || mime != "image/jpeg" || len(bs) != 5 {
		t.Fatalf("photo %v %s %d", err, mime, len(bs))
	}
	if _, _, err := j.CatchPhoto(ctx, b, c.UUID); !errors.Is(err, ErrNotFound) {
		t.Fatal("photo leak")
	}
	if _, _, err := j.CatchPhoto(ctx, a, list[1].UUID); !errors.Is(err, ErrNoPhoto) {
		t.Fatal("no photo")
	}
	if err := j.DeleteCatch(ctx, b, c.UUID); !errors.Is(err, ErrNotFound) {
		t.Fatal("other delete")
	}
	if err := j.DeleteCatch(ctx, a, c.UUID); err != nil {
		t.Fatal(err)
	}
	if err := j.DeleteSpot(ctx, a, sp.UUID); err != nil {
		t.Fatal(err)
	}
	if l, _ := j.ListSpots(ctx, a); len(l) != 0 {
		t.Fatal("spot not deleted")
	}
}
