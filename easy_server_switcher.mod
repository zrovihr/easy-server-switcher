return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`easy_server_switcher` encountered an error loading the Darktide Mod Framework.")

		new_mod("easy_server_switcher", {
			mod_script       = "easy_server_switcher/scripts/mods/easy_server_switcher/easy_server_switcher",
			mod_data         = "easy_server_switcher/scripts/mods/easy_server_switcher/easy_server_switcher_data",
			mod_localization = "easy_server_switcher/scripts/mods/easy_server_switcher/easy_server_switcher_localization",
		})
	end,
	packages = {},
}
