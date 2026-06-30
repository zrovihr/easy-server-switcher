return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`easy_server_changer` encountered an error loading the Darktide Mod Framework.")

		new_mod("easy_server_changer", {
			mod_script       = "easy_server_changer/scripts/mods/easy_server_changer/easy_server_changer",
			mod_data         = "easy_server_changer/scripts/mods/easy_server_changer/easy_server_changer_data",
			mod_localization = "easy_server_changer/scripts/mods/easy_server_changer/easy_server_changer_localization",
		})
	end,
	packages = {},
}
