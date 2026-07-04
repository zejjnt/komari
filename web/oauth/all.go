package oauth

import (
	_ "github.com/zejjnt/komari/web/oauth/cloudflare"
	_ "github.com/zejjnt/komari/web/oauth/factory"
	_ "github.com/zejjnt/komari/web/oauth/generic"
	_ "github.com/zejjnt/komari/web/oauth/github"
	_ "github.com/zejjnt/komari/web/oauth/qq"
)

func All() {
	//empty function to ensure all OIDC providers are registered
}
