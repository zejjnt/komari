package messageSender

import (
	_ "github.com/zejjnt/komari/utils/messageSender/bark"
	_ "github.com/zejjnt/komari/utils/messageSender/email"
	_ "github.com/zejjnt/komari/utils/messageSender/empty"
	_ "github.com/zejjnt/komari/utils/messageSender/javascript"
	_ "github.com/zejjnt/komari/utils/messageSender/serverchan3"
	_ "github.com/zejjnt/komari/utils/messageSender/serverchanturbo"
	_ "github.com/zejjnt/komari/utils/messageSender/telegram"
	_ "github.com/zejjnt/komari/utils/messageSender/webhook"
)

func All() {
}
