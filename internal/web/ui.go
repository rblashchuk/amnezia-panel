package web

import "embed"

//go:embed assets/index.html
var indexHTML string

//go:embed assets/static/*
var staticFS embed.FS