package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"unsafe"

	"github.com/anacrolix/torrent"
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
		t, err := mgr.client.AddMagnet(uri)
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
	if gotInfo {
		for _, f := range t.Files() {
			files = append(files, fileState{
				Path:            filepath.Join(mgr.downloadDir, filepath.FromSlash(f.Path())),
				DisplayPath:     f.DisplayPath(),
				Length:          f.Length(),
				DownloadedBytes: f.BytesCompleted(),
			})
		}
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
		Error:           tsk.Error,
	}
}

func removeTorrentFiles(tsk *task) {
	st := stateLocked(tsk)
	for _, file := range st.Files {
		_ = os.Remove(file.Path)
	}
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
