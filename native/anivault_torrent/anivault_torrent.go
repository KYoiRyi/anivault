package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"unsafe"

	g "github.com/anacrolix/generics"
	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/storage"
)

type task struct {
	ID     string
	Magnet string
	T      *torrent.Torrent
	Paused bool
	Error  string
}

type manager struct {
	mu          sync.Mutex
	client      *torrent.Client
	downloadDir string
	tasks       map[string]*task
}

var mgr manager

type response struct {
	OK    bool        `json:"ok"`
	Error string      `json:"error,omitempty"`
	Data  interface{} `json:"data,omitempty"`
}

type taskState struct {
	ID              string      `json:"id"`
	Magnet          string      `json:"magnet"`
	Name            string      `json:"name"`
	DownloadDir     string      `json:"downloadDir"`
	DownloadedBytes int64       `json:"downloadedBytes"`
	TotalBytes      int64       `json:"totalBytes"`
	Progress        float64     `json:"progress"`
	Complete        bool        `json:"complete"`
	Paused          bool        `json:"paused"`
	GotInfo         bool        `json:"gotInfo"`
	Files           []fileState `json:"files"`
	Error           string      `json:"error,omitempty"`
	Diagnostics     string      `json:"diagnostics,omitempty"`
}

type fileState struct {
	Path            string `json:"path"`
	DisplayPath     string `json:"displayPath"`
	Length          int64  `json:"length"`
	DownloadedBytes int64  `json:"downloadedBytes"`
}

func main() {}

//export anivault_torrent_init
func anivault_torrent_init(downloadDir *C.char) *C.char {
	return cJSON(func() response {
		dir := C.GoString(downloadDir)
		if strings.TrimSpace(dir) == "" {
			return errResp("download directory is empty")
		}
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return errResp(err.Error())
		}

		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		if mgr.client != nil && mgr.downloadDir == dir {
			return okResp(map[string]string{"downloadDir": dir})
		}
		if mgr.client != nil {
			mgr.client.Close()
		}
		cfg := torrent.NewDefaultClientConfig()
		cfg.DataDir = dir
		cfg.ListenPort = 0
		cfg.Seed = false
		cfg.DisableWebtorrent = true
		cfg.DefaultStorage = storage.NewFileOpts(storage.NewFileClientOpts{
			ClientBaseDir: dir,
			UsePartFiles:  g.Some(false),
		})
		client, err := torrent.NewClient(cfg)
		if err != nil {
			mgr.client = nil
			mgr.tasks = nil
			return errResp(err.Error())
		}
		mgr.client = client
		mgr.downloadDir = dir
		mgr.tasks = map[string]*task{}
		return okResp(map[string]string{"downloadDir": dir})
	})
}

//export anivault_torrent_add_magnet
func anivault_torrent_add_magnet(magnet *C.char) *C.char {
	return cJSON(func() response {
		uri := strings.TrimSpace(C.GoString(magnet))
		if uri == "" {
			return errResp("magnet link is empty")
		}
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		if mgr.client == nil {
			return errResp("torrent client is not initialized")
		}
		spec, err := torrent.TorrentSpecFromMagnetUri(uri)
		if err != nil {
			return errResp(err.Error())
		}
		if infoBytes, ok := loadMetainfoBytes(dirForMetadata(), tInfoHashHex(spec)); ok {
			spec.InfoBytes = infoBytes
		}
		t, _, err := mgr.client.AddTorrentSpec(spec)
		if err != nil {
			return errResp(err.Error())
		}
		id := t.InfoHash().HexString()
		mgr.tasks[id] = &task{ID: id, Magnet: uri, T: t}
		t.AllowDataDownload()
		startDownloadWhenReady(id, t)
		return okResp(stateLocked(mgr.tasks[id]))
	})
}

//export anivault_torrent_resume
func anivault_torrent_resume(id *C.char) *C.char {
	return cJSON(func() response {
		return updateTask(C.GoString(id), func(tsk *task) {
			tsk.Paused = false
			tsk.Error = ""
			tsk.T.AllowDataDownload()
			startDownloadWhenReady(tsk.ID, tsk.T)
		})
	})
}

//export anivault_torrent_pause
func anivault_torrent_pause(id *C.char) *C.char {
	return cJSON(func() response {
		return updateTask(C.GoString(id), func(tsk *task) {
			tsk.Paused = true
			tsk.T.DisallowDataDownload()
		})
	})
}

//export anivault_torrent_remove
func anivault_torrent_remove(id *C.char, dropData C.int) *C.char {
	return cJSON(func() response {
		taskID := C.GoString(id)
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		tsk := mgr.tasks[taskID]
		if tsk == nil {
			return errResp("torrent task not found")
		}
		if dropData != 0 {
			removeTorrentFiles(tsk)
		}
		tsk.T.Drop()
		delete(mgr.tasks, taskID)
		return okResp(map[string]string{"id": taskID})
	})
}

//export anivault_torrent_status
func anivault_torrent_status() *C.char {
	return cJSON(func() response {
		mgr.mu.Lock()
		defer mgr.mu.Unlock()
		states := make([]taskState, 0, len(mgr.tasks))
		for _, tsk := range mgr.tasks {
			states = append(states, stateLocked(tsk))
		}
		sort.Slice(states, func(i, j int) bool {
			return states[i].Name < states[j].Name
		})
		return okResp(states)
	})
}

//export anivault_torrent_free
func anivault_torrent_free(value *C.char) {
	C.free(unsafe.Pointer(value))
}

func updateTask(id string, fn func(*task)) response {
	mgr.mu.Lock()
	defer mgr.mu.Unlock()
	tsk := mgr.tasks[id]
	if tsk == nil {
		return errResp("torrent task not found")
	}
	fn(tsk)
	return okResp(stateLocked(tsk))
}

func startDownloadWhenReady(id string, t *torrent.Torrent) {
	if t.Info() != nil {
		t.DownloadAll()
		return
	}
	go func() {
		<-t.GotInfo()
		mgr.mu.Lock()
		tsk := mgr.tasks[id]
		shouldDownload := tsk != nil && !tsk.Paused
		mgr.mu.Unlock()
		if shouldDownload {
			t.DownloadAll()
		}
	}()
}

func stateLocked(tsk *task) taskState {
	t := tsk.T
	name := t.Name()
	gotInfo := t.Info() != nil
	total := t.Length()
	done := t.BytesCompleted()
	files := []fileState{}
	diskDone := int64(0)
	diskAllComplete := gotInfo
	if gotInfo {
		saveMetainfo(t)
		for _, f := range t.Files() {
			path := filepath.Join(mgr.downloadDir, filepath.FromSlash(f.Path()))
			path = finalizeLegacyPartFile(path, f.Length())
			fileDone := f.BytesCompleted()
			if fileDone < f.Length() {
				diskAllComplete = false
			}
			diskDone += fileDone
			files = append(files, fileState{
				Path:            path,
				DisplayPath:     f.DisplayPath(),
				Length:          f.Length(),
				DownloadedBytes: fileDone,
			})
		}
	}
	if diskDone > done {
		done = diskDone
	}
	if t.Complete().Bool() && diskAllComplete && total > 0 {
		t.DisallowDataDownload()
	}
	stats := t.Stats()
	diagnostics := fmt.Sprintf(
		"peers total=%d active=%d pending=%d halfOpen=%d seeders=%d piecesComplete=%d hashed=%d",
		stats.TotalPeers,
		stats.ActivePeers,
		stats.PendingPeers,
		stats.HalfOpenPeers,
		stats.ConnectedSeeders,
		stats.PiecesComplete,
		stats.BytesHashed.Int64(),
	)
	errorText := tsk.Error
	if gotInfo && total > 0 && done == 0 && !diskAllComplete {
		errorText = diagnostics
	}
	progress := 0.0
	if total > 0 {
		progress = float64(done) / float64(total)
	}
	return taskState{
		ID:              tsk.ID,
		Magnet:          tsk.Magnet,
		Name:            name,
		DownloadDir:     mgr.downloadDir,
		DownloadedBytes: done,
		TotalBytes:      total,
		Progress:        progress,
		Complete:        t.Complete().Bool(),
		Paused:          tsk.Paused,
		GotInfo:         gotInfo,
		Files:           files,
		Error:           errorText,
		Diagnostics:     diagnostics,
	}
}

func saveMetainfo(t *torrent.Torrent) {
	mi := t.Metainfo()
	if len(mi.InfoBytes) == 0 {
		return
	}
	path := metainfoPath(t.InfoHash().HexString())
	if _, err := os.Stat(path); err == nil {
		return
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	tmp := path + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return
	}
	err = mi.Write(f)
	closeErr := f.Close()
	if err != nil || closeErr != nil {
		_ = os.Remove(tmp)
		return
	}
	_ = os.Rename(tmp, path)
}

func loadMetainfoBytes(dir, infoHash string) ([]byte, bool) {
	path := filepath.Join(dir, ".metadata", infoHash+".torrent")
	f, err := os.Open(path)
	if err != nil {
		return nil, false
	}
	defer f.Close()
	mi, err := metainfo.Load(f)
	if err != nil || len(mi.InfoBytes) == 0 {
		return nil, false
	}
	return mi.InfoBytes, true
}

func tInfoHashHex(spec *torrent.TorrentSpec) string {
	if !spec.InfoHash.IsZero() {
		return spec.InfoHash.HexString()
	}
	if spec.InfoHashV2.Ok {
		return spec.InfoHashV2.Value.HexString()
	}
	return ""
}

func dirForMetadata() string {
	return mgr.downloadDir
}

func metainfoPath(infoHash string) string {
	return filepath.Join(mgr.downloadDir, ".metadata", infoHash+".torrent")
}

func removeTorrentFiles(tsk *task) {
	st := stateLocked(tsk)
	for _, file := range st.Files {
		_ = os.Remove(file.Path)
	}
}

func finalizeLegacyPartFile(path string, length int64) string {
	partPath := path + ".part"
	if !fileHasLength(partPath, length) {
		return path
	}
	if err := os.Rename(partPath, path); err == nil || fileHasLength(path, length) {
		return path
	}
	if err := copyFile(partPath, path); err == nil && fileHasLength(path, length) {
		_ = os.Remove(partPath)
		return path
	}
	return path
}

func fileHasLength(path string, length int64) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Size() >= length
}

func copyFile(from, to string) error {
	if err := os.MkdirAll(filepath.Dir(to), 0o755); err != nil {
		return err
	}
	in, err := os.Open(from)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(to, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		_ = os.Remove(to)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(to)
		return closeErr
	}
	return nil
}

func cJSON(fn func() response) *C.char {
	resp := fn()
	data, err := json.Marshal(resp)
	if err != nil {
		data, _ = json.Marshal(errResp(err.Error()))
	}
	return C.CString(string(data))
}

func okResp(data interface{}) response {
	return response{OK: true, Data: data}
}

func errResp(message string) response {
	return response{OK: false, Error: message}
}
