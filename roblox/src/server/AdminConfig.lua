-- Server-only admin settings. This ModuleScript lives in ServerScriptService,
-- which players can never see, so the password stays secret in the live game.
--
-- Everyone (including the game's owner) has to enter this password in
-- Settings to open the admin panel. Wrong guesses are rate limited.
--
-- Note: if this repository is public on GitHub, anyone can read the password
-- here. Change it in your published place (and keep the repo private) if so.
return {
	Password = "Evan123",
}
