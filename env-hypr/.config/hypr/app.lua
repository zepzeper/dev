-- App-specific tweaks.
-- Order matters: rules are evaluated top to bottom and the last match wins.
--
-- Note: the `-default-opacity` tag removals below are carried over verbatim from
-- the old config. Nothing in this config ever adds `+default-opacity`, so they
-- are currently no-ops (that tag came from the upstream Omarchy defaults).

require("apps.bitwarden")
require("apps.browser")
require("apps.localsend")
require("apps.steam")
require("apps.gfx")
require("apps.system")
require("apps.terminals")
