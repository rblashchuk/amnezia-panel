package web

import "embed"

//go:embed assets/index.html
var IndexHTML string

//go:embed assets/static/*
var StaticFS embed.FS