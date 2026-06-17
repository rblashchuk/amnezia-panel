package web

import "net/http"

func RequireBearerToken(token string, next http.HandlerFunc) http.HandlerFunc {
	if token == "" {
		return next
	}

	return func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+token {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}
