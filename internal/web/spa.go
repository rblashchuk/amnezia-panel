package web

import (
	"io/fs"
	"net/http"
)

func AppHandler() http.Handler {
	dist, err := fs.Sub(DistFS, "dist")
	if err != nil {
		panic(err)
	}

	fileServer := http.FileServer(http.FS(dist))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := dist.Open(trimPath(r.URL.Path)); err == nil {
			fileServer.ServeHTTP(w, r)
			return
		}

		r.URL.Path = "/"
		fileServer.ServeHTTP(w, r)
	})
}

func trimPath(path string) string {
	if path == "/" {
		return "index.html"
	}
	return path[1:]
}
