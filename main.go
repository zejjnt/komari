package main

import (
	"log"
	"log/slog"

	"github.com/zejjnt/komari/cmd"
	"github.com/zejjnt/komari/utils"
	logutil "github.com/zejjnt/komari/utils/log"
)

func main() {
	if utils.VersionHash == "unknown" {
		logutil.SetupGlobalLogger(slog.LevelDebug)
	} else {
		logutil.SetupGlobalLogger(slog.LevelInfo)
	}

	log.Printf("Komari Monitor %s (hash: %s)", utils.CurrentVersion, utils.VersionHash)

	cmd.Execute()
}
