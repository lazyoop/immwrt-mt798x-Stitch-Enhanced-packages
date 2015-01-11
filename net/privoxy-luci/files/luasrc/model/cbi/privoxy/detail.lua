--[[
LuCI - Lua Configuration Interface

Copyright 2014 Christian Schoenebeck <christian dot schoenebeck at gmail dot com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id$
]]--

local NXFS = require "nixio.fs"
local LUFS = require "luci.fs"
local SYS  = require "luci.sys"
local UTIL = require "luci.util"
local DTYP = require "luci.cbi.datatypes"
local CTRL = require "luci.controller.privoxy"	-- privoxy multiused functions

-- Bootstrap theme needs 2 or 3 additional linefeeds for tab description for better optic
local LFLF = (CTRL.get_theme() == "Bootstrap") and [[<br /><br /><br />]] or [[]]
-- Build javascript string to be displayed as version information
local VERSION = translate("Version Information")
		.. [[\n\nluci-app-privoxy]]
		.. [[\n\t]] .. translate("Version") .. [[:\t]] .. CTRL.version_luci_app
		.. [[\n\t]] .. translate("Build") .. [[:\t]] 
		.. SYS.exec([[opkg list-installed ]] .. [[luci_app_privoxy]] .. [[ | awk '{print $3}']])
		.. [[\n\nprivoxy ]] .. translate("required") .. [[:]]
		.. [[\n\t]] .. translate("Version") .. [[:\t]] .. CTRL.version_required .. [[ ]] .. translate("or greater")
		.. [[\n\nprivoxy ]] .. translate("installed") .. [[:]]
		.. [[\n\t]] .. translate("Version") .. [[:\t]] 
		.. SYS.exec([[opkg list-installed ]] .. [[privoxy]] .. [[ | awk '{print $3}']])
		.. [[\n\n]]
local HELP = [[<a href="http://www.privoxy.org/user-manual/config.html#%s" target="_blank">%s</a>]]

-- cbi-map -- ##################################################################
local m	= Map("privoxy")
m.title	= [[</a><a href="javascript:alert(']] 
	.. VERSION 
	.. [[')">]] 
	.. translate("Privoxy WEB proxy")
m.description = translate("Privoxy is a non-caching web proxy with advanced filtering "
		.. "capabilities for enhancing privacy, modifying web page data and HTTP headers, "
		.. "controlling access, and removing ads and other obnoxious Internet junk.")
		.. [[<br /><strong>]]
		.. translate("For help use link at the relevant option")
		.. [[</strong>]]
function m.commit_handler(self)
	if self.changed then	-- changes ?
		os.execute("/etc/init.d/privoxy reload &")	-- reload configuration
	end
end

-- cbi-section -- ##############################################################
local ns = m:section( NamedSection, "privoxy", "privoxy")

ns:tab("local",
	translate("Local Set-up"),
	translate("If you intend to operate Privoxy for more users than just yourself, "
		.. "it might be a good idea to let them know how to reach you, what you block "
		.. "and why you do that, your policies, etc.")
		.. LFLF )
local function err_tab_local(self, msg)
	return string.format(translate("Local Set-up") .. " - %s: %s", self.title_base, msg )
end

ns:tab("filter",
	translate("Files and Directories"),
	translate("Privoxy can (and normally does) use a number of other files "
		.. "for additional configuration, help and logging. This section of "
		.. "the configuration file tells Privoxy where to find those other files.")
		.. LFLF )
local function err_tab_filter(self, msg)
	return string.format(translate("Files and Directories") .. " - %s: %s", self.title_base, msg )
end

ns:tab("access", 
	translate("Access Control"), 
	translate("This tab controls the security-relevant aspects of Privoxy's configuration.") 
		.. LFLF )
local function err_tab_access(self, msg)
	return string.format(translate("Access Control") .. " - %s: %s", self.title_base, msg )
end

ns:tab("forward",
	translate("Forwarding"),
	translate("Configure here the routing of HTTP requests through a chain of multiple proxies. "
		.. "Note that parent proxies can severely decrease your privacy level. "
		.. "Also specified here are SOCKS proxies.")
		.. LFLF )

ns:tab("misc",
	translate("Miscellaneous"),
	nil)
local function err_tab_misc(self, msg)
	return string.format(translate("Miscellaneous") .. " - %s: %s", self.title_base, msg )
end

ns:tab("debug", 
	translate("Logging"),
	nil )

ns:tab("logview",
	translate("Log File Viewer"),
	nil )

-- tab: local -- ###############################################################

-- start/stop button -----------------------------------------------------------
local btn	= ns:taboption("local", Button, "_startstop")
btn.title	= translate("Start / Stop")
btn.description	= translate("Start/Stop Privoxy WEB Proxy")
btn.template	= "privoxy/detail_startstop"
function btn.cfgvalue(self, section)
	local pid = CTRL.get_pid(true)
	if pid > 0 then
		btn.inputtitle	= "PID: " .. pid
		btn.inputstyle	= "reset"
		btn.disabled	= false
	else
		btn.inputtitle	= translate("Start")
		btn.inputstyle	= "apply"
		btn.disabled	= false
	end
	return true
end

-- enabled ---------------------------------------------------------------------
local ena	= ns:taboption("local", Flag, "_enabled")
ena.title       = translate("Enabled")
ena.description = translate("Enable/Disable autostart of Privoxy on system startup and interface events")
ena.orientation = "horizontal" -- put description under the checkbox
ena.rmempty	= false
function ena.cfgvalue(self, section)
	return (SYS.init.enabled("privoxy")) and "1" or "0"
end
function ena.validate(self, value)
	error("Validate " .. value)
end
function ena.write(self, section, value)
	--error("Write " .. value)
	if value == "1" then
		return SYS.init.enable("privoxy")
	else
		return SYS.init.disable("privoxy")
	end
end

-- hostname --------------------------------------------------------------------
local hn	= ns:taboption("local", Value, "hostname")
hn.title	= string.format(HELP, "HOSTNAME", "Hostname" )
hn.description	= translate("The hostname shown on the CGI pages.")
hn.placeholder	= SYS.hostname()
hn.optional	= true
hn.rmempty	= true

-- user-manual -----------------------------------------------------------------
local um	= ns:taboption("local", Value, "user_manual")
um.title	= string.format(HELP, "USER-MANUAL", "User Manual" )
um.description	= translate("Location of the Privoxy User Manual.")
um.placeholder	= "http://www.privoxy.org/user-manual/"
um.optional	= true
um.rmempty	= true

-- admin-address ---------------------------------------------------------------
local aa	= ns:taboption("local", Value, "admin_address")
aa.title_base	= "Admin Email"
aa.title	= string.format(HELP, "ADMIN-ADDRESS", aa.title_base )
aa.description	= translate("An email address to reach the Privoxy administrator.")
aa.placeholder	= "privoxy.admin@example.com"
aa.optional	= true
aa.rmempty	= true
function aa.validate(self, value)
	if not value or #value == 0 then
		return ""
	end
	if not (value:match("[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?")) then
		return nil, err_tab_local(self, translate("Invalid email address") )
	end
	return value
end

-- proxy-info-url --------------------------------------------------------------
local piu	= ns:taboption("local", Value, "proxy_info_url")
piu.title	= string.format(HELP, "PROXY-INFO-URL", "Proxy Info URL" )
piu.description	= translate("A URL to documentation about the local Privoxy setup, configuration or policies.")
piu.optional	= true
piu.rmempty	= true

-- trust-info-url --------------------------------------------------------------
local tiu	= ns:taboption("local", DynamicList, "trust_info_url")
tiu.title	= string.format(HELP, "TRUST-INFO-URL", "Trust Info URLs" )
tiu.description	= translate("A URL to be displayed in the error page that users will see if access to an untrusted page is denied.")
		.. [[<br /><strong>]]
		.. translate("The value of this option only matters if the experimental trust mechanism has been activated.")
		.. [[</strong>]]
tiu.optional	= true
tiu.rmepty	= true

-- tab: filter -- ##############################################################

-- logdir ----------------------------------------------------------------------
local ld	= ns:taboption("filter", Value, "logdir")
ld.title_base	= "Log Directory"
ld.title	= string.format(HELP, "LOGDIR", ld.title_base )
ld.description	= translate("The directory where all logging takes place (i.e. where the logfile is located).")
		.. [[<br />]]
		.. translate("No trailing '/', please.")
ld.default	= "/var/log"
ld.rmempty	= false
function ld.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_filter(self, translate("Mandatory Input: No Directory given!") )
	elseif not LUFS.isdirectory(value) then
		return nil, err_tab_filter(self, translate("Directory does not exist!") )
	else
		return value
	end
end

-- logfile ---------------------------------------------------------------------
local lf	= ns:taboption("filter", Value, "logfile")
lf.title_base	= "Log File"
lf.title	= string.format(HELP, "LOGFILE", lf.title_base )
lf.description	= translate("The log file to use. File name, relative to log directory.")
lf.default	= "privoxy.log"
lf.rmempty	= false
function lf.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_filter(self, translate("Mandatory Input: No File given!") )
	else
		return value
	end
end

-- confdir ---------------------------------------------------------------------
local cd	= ns:taboption("filter", Value, "confdir")
cd.title	= string.format(HELP, "CONFDIR", "Configuration Directory" )
cd.description	= translate("The directory where the other configuration files are located.")
		.. [[<br />]]
		.. translate("No trailing '/', please.")
cd.default	= "/etc/privoxy"
cd.rmempty	= false
function cd.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_filter(self, translate("Mandatory Input: No Directory given!") )
	elseif not LUFS.isdirectory(value) then
		return nil, err_tab_filter(self, translate("Directory does not exist!") )
	else
		return value
	end
end

-- templdir --------------------------------------------------------------------
local td	= ns:taboption("filter", Value, "templdir")
td.title_base	= "Template Directory"
td.title	= string.format(HELP, "TEMPLDIR", td.title_base )
td.description	= translate("An alternative directory where the templates are loaded from.")
		.. [[<br />]]
		.. translate("No trailing '/', please.")
td.placeholder	= "/etc/privoxy/templates"
td.rmempty	= true
function td.validate(self, value)
	if not LUFS.isdirectory(value) then
		return nil, err_tab_filter(self, translate("Directory does not exist!") )
	else
		return value
	end
end

-- actionsfile -----------------------------------------------------------------
local af	= ns:taboption("filter", DynamicList, "actionsfile")
af.title_base	= "Action Files"
af.title	= string.format(HELP, "ACTIONSFILE", af.title_base)
af.description	= translate("The actions file(s) to use. Multiple actionsfile lines are permitted, and are in fact recommended!")
		.. [[<br /><strong>match-all.action := </strong>]]
		.. translate("Actions that are applied to all sites and maybe overruled later on.")
		.. [[<br /><strong>default.action := </strong>]]
		.. translate("Main actions file")
		.. [[<br /><strong>user.action := </strong>]]
		.. translate("User customizations")
af.rmempty	= false
function af.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_access(self, translate("Mandatory Input: No files given!") )
	end
	local confdir = cd:formvalue(ns.section)
	local err     = false
	local file    = ""
	if type(value) == "table" then
		local x
		for _, x in ipairs(value) do
			if x and #x > 0 then
				if not LUFS.isfile(confdir .."/".. x) then
					err  = true
					file = x
					break	-- break/leave for on error
				end
			end
		end
	else
		if not LUFS.isfile(confdir .."/".. value) then
			err  = true
			file = value
		end
	end
	if err then
		return nil, string.format(err_tab_filter(self, translate("File '%s' not found inside Configuration Directory") ), file)
	end
	return value	
end

-- filterfile ------------------------------------------------------------------
local ff	= ns:taboption("filter", DynamicList, "filterfile")
ff.title_base	= "Filter files"
ff.title	= string.format(HELP, "FILTERFILE", ff.title_base )
ff.description	= translate("The filter files contain content modification rules that use regular expressions.")
ff.rmempty	= false
function ff.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_access(self, translate("Mandatory Input: No files given!") )
	end
	local confdir = cd:formvalue(ns.section)
	local err     = false
	local file    = ""
	if type(value) == "table" then
		local x
		for _, x in ipairs(value) do
			if x and #x > 0 then
				if not LUFS.isfile(confdir .."/".. x) then
					err  = true
					file = x
					break	-- break/leave for on error
				end
			end
		end
	else
		if not LUFS.isfile(confdir .."/".. value) then
			err  = true
			file = value
		end
	end
	if err then
		return nil, string.format(err_tab_filter(self, translate("File '%s' not found inside Configuration Directory") ), file )
	end
	return value	
end

-- trustfile -------------------------------------------------------------------
local tf	= ns:taboption("filter", Value, "trustfile")
tf.title_base	= "Trust file"
tf.title	= string.format(HELP, "TRUSTFILE", tf.title_base )
tf.description	= translate("The trust mechanism is an experimental feature for building white-lists "
		.."and should be used with care.")
		.. [[<br /><strong>]]
		.. translate("It is NOT recommended for the casual user.")
		.. [[</strong>]]
tf.placeholder	= "sites.trust"
tf.rmempty	= true
function tf.validate(self, value)
	local confdir = cd:formvalue(ns.section)
	local err     = false
	local file    = ""
	if type(value) == "table" then
		local x
		for _, x in ipairs(value) do
			if x and #x > 0 then
				if not LUFS.isfile(confdir .."/".. x) then
					err  = true
					file = x
					break	-- break/leave for on error
				end
			end
		end
	else
		if not LUFS.isfile(confdir .."/".. value) then
			err  = true
			file = value
		end
	end
	if err then
		return nil, string.format(err_tab_filter(self, translate("File '%s' not found inside Configuration Directory") ), file )
	end
	return value	
end

-- tab: access -- ##############################################################

-- listen-address --------------------------------------------------------------
local la	= ns:taboption("access", DynamicList, "listen_address")
la.title_base	= "Listen addresses"
la.title	= string.format(HELP, "LISTEN-ADDRESS", la.title_base )
la.description	= translate("The address and TCP port on which Privoxy will listen for client requests.")
		.. [[<br />]]
		.. translate("Syntax: ")
		.. "IPv4:Port / [IPv6]:Port / Host:Port"
la.default	= "127.0.0.1:8118"
la.rmempty	= false
function la.validate(self, value)
	if not value or #value == 0 then
		return nil, err_tab_access(self, translate("Mandatory Input: No Data given!") )
	end

	local function check_value(v)
		local _ret = UTIL.split(v, "]:")
		local _ip
		if _ret[2] then	-- ip6 with port
			_ip   = string.gsub(_ret[1], "%[", "")	-- remove "[" at beginning
			if not DTYP.ip6addr(_ip) then
				return translate("Mandatory Input: No valid IPv6 address given!")
			elseif not DTYP.port(_ret[2]) then
				return translate("Mandatory Input: No valid Port given!")
			else
				return nil
			end
		end
		_ret = UTIL.split(v, ":")
		if not _ret[2] then
			return translate("Mandatory Input: No Port given!")
		end
		if #_ret[1] > 0 and not DTYP.host(_ret[1]) then	-- :8118 is valid address
			return translate("Mandatory Input: No valid IPv4 address or host given!")
		elseif not DTYP.port(_ret[2]) then
			return translate("Mandatory Input: No valid Port given!")
		else
			return nil
		end
	end

	local err   = ""
	local entry = ""
	if type(value) == "table" then
		local x
		for _, x in ipairs(value) do
			if x and #x > 0 then
				err = check_value(x)
				if err then
					entry = x
					break
				end
			end
		end
	else
		err = check_value(value)
		entry = value
	end
	if err then
		return nil, string.format(err_tab_access(self, err .. " - %s"), entry )
	end
	return value
end

-- permit-access ---------------------------------------------------------------
local pa	= ns:taboption("access", DynamicList, "permit_access")
pa.title	= string.format(HELP, "ACLS", "Permit access" )
pa.description	= translate("Who can access what.")
		.. [[<br /><strong>]]
		.. translate("Please read Privoxy manual for details!")
		.. [[</strong>]]
pa.rmempty	= true

-- deny-access -----------------------------------------------------------------
local da	= ns:taboption("access", DynamicList, "deny_access")
da.title	= string.format(HELP, "ACLS", "Deny Access" )
da.description	= translate("Who can access what.")
		.. [[<br /><strong>]]
		.. translate("Please read Privoxy manual for details!")
		.. [[</strong>]]
da.rmempty	= true

-- buffer-limit ----------------------------------------------------------------
local bl	= ns:taboption("access", Value, "buffer_limit")
bl.title_base	= "Buffer Limit"
bl.title	= string.format(HELP, "BUFFER-LIMIT", bl.title_base )
bl.description	= translate("Maximum size (in KB) of the buffer for content filtering.")
		.. [[<br />]]
		.. translate("Value range 1 to 4096, no entry defaults to 4096")
bl.default	= 4096
bl.rmempty	= true
function bl.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_access(self, translate("Value is not a number") )
	elseif v < 1 or v > 4096 then
		return nil, err_tab_access(self, translate("Value not between 1 and 4096") )
	elseif v == self.default then
		return ""	-- dont need to save default
	end
	return value
end

-- toggle ----------------------------------------------------------------------
local tgl	= ns:taboption("access", Flag, "toggle")
tgl.title	= string.format(HELP, "TOGGLE", "Toggle Status" )
tgl.description	= translate("Enable/Disable filtering when Privoxy starts.")
		.. [[<br />]]
		.. translate("Disabled == Transparent Proxy Mode")
tgl.orientation	= "horizontal"
tgl.default	= "1"
tgl.rmempty	= false
function tgl.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- enable-remote-toggle --------------------------------------------------------
local ert	= ns:taboption("access", Flag, "enable_remote_toggle")
ert.title	= string.format(HELP, "ENABLE-REMOTE-TOGGLE", "Enable remote toggle" )
ert.description	= translate("Whether or not the web-based toggle feature may be used.")
ert.orientation	= "horizontal"
ert.rmempty	= true
function ert.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- enable-remote-http-toggle ---------------------------------------------------
local eht	= ns:taboption("access", Flag, "enable_remote_http_toggle")
eht.title	= string.format(HELP, "ENABLE-REMOTE-HTTP-TOGGLE", "Enable remote toggle via HTTP" )
eht.description	= translate("Whether or not Privoxy recognizes special HTTP headers to change its behaviour.")
		.. [[<br /><strong>]]
		.. translate("This option will be removed in future releases as it has been obsoleted by the more general header taggers.")
		.. [[</strong>]]
eht.orientation	= "horizontal"
eht.rmempty	= true
function eht.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- enable-edit-actions ---------------------------------------------------------
local eea	= ns:taboption("access", Flag, "enable_edit_actions")
eea.title	= string.format(HELP, "ENABLE-EDIT-ACTIONS", "Enable action file editor" )
eea.description	= translate("Whether or not the web-based actions file editor may be used.")
eea.orientation	= "horizontal"
eea.rmempty	= true
function eea.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- enforce-blocks --------------------------------------------------------------
local eb	= ns:taboption("access", Flag, "enforce_blocks")
eb.title	= string.format(HELP, "ENFORCE-BLOCKS", "Enforce page blocking" )
eb.description	= translate("If enabled, Privoxy hides the 'go there anyway' link. "
		.. "The user obviously should not be able to bypass any blocks.")
eb.orientation	= "horizontal"
eb.rmempty	= true
function eb.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- tab: forward -- #############################################################

-- enable-proxy-authentication-forwarding --------------------------------------
local paf	= ns:taboption("forward", Flag, "enable_proxy_authentication_forwarding")
paf.title	= string.format(HELP, "ENABLE-PROXY-AUTHENTICATION-FORWARDING", 
		translate("Enable proxy authentication forwarding") )
paf.description	= translate("Whether or not proxy authentication through Privoxy should work.")
		.. [[<br /><strong>]]
		.. translate("Enabling this option is NOT recommended if there is no parent proxy that requires authentication!")
		.. [[</strong>]]
--paf.orientation	= "horizontal"
paf.rmempty	= true
function paf.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- forward ---------------------------------------------------------------------
local fwd	= ns:taboption("forward", DynamicList, "forward")
fwd.title	= string.format(HELP, "FORWARD", "Forward HTTP" )
fwd.description	= translate("To which parent HTTP proxy specific requests should be routed.")
		.. [[<br />]]
		.. translate("Syntax: target_pattern http_parent[:port]")
fwd.rmempty	= true

-- forward-socks4 --------------------------------------------------------------
local fs4	= ns:taboption("forward", DynamicList, "forward_socks4")
fs4.title	= string.format(HELP, "SOCKS", "Forward SOCKS 4" )
fs4.description	= translate("Through which SOCKS proxy (and optionally to which parent HTTP proxy) specific requests should be routed.")
		.. [[<br />]]
		.. translate("Syntax: target_pattern socks_proxy[:port] http_parent[:port]")
fs4.rmempty	= true

-- forward-socks4a -------------------------------------------------------------
local f4a	= ns:taboption("forward", DynamicList, "forward_socks4a")
f4a.title	= string.format(HELP, "SOCKS", "Forward SOCKS 4A" )
f4a.description = fs4.description
f4a.rmempty	= true

-- forward-socks5 --------------------------------------------------------------
local fs5	= ns:taboption("forward", DynamicList, "forward_socks5")
fs5.title	= string.format(HELP, "SOCKS", "Forward SOCKS 5" )
fs5.description = fs4.description
fs5.rmempty	= true

-- forward-socks5t -------------------------------------------------------------
local f5t	= ns:taboption("forward", DynamicList, "forward_socks5t")
f5t.title	= string.format(HELP, "SOCKS", "Forward SOCKS 5t" )
f5t.description = fs4.description
f5t.rmempty	= true

-- tab: misc -- ################################################################

-- accept-intercepted-requests -------------------------------------------------
local air	= ns:taboption("misc", Flag, "accept_intercepted_requests")
air.title	= string.format(HELP, "ACCEPT-INTERCEPTED-REQUESTS", "Accept intercepted requests" )
air.description	= translate("Whether intercepted requests should be treated as valid.")
air.orientation	= "horizontal"
air.rmempty	= true
function air.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- allow-cgi-request-crunching -------------------------------------------------
local crc	= ns:taboption("misc", Flag, "allow_cgi_request_crunching")
crc.title	= string.format(HELP, "ALLOW-CGI-REQUEST-CRUNCHING", "Allow CGI request crunching" )
crc.description	= translate("Whether requests to Privoxy's CGI pages can be blocked or redirected.")
crc.orientation	= "horizontal"
crc.rmempty	= true
function crc.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- split-large-forms -----------------------------------------------------------
local slf	= ns:taboption("misc", Flag, "split_large_forms")
slf.title	= string.format(HELP, "SPLIT-LARGE-FORMS", "Split large forms" )
slf.description	= translate("Whether the CGI interface should stay compatible with broken HTTP clients.")
slf.orientation	= "horizontal"
slf.rmempty	= true
function slf.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- keep-alive-timeout ----------------------------------------------------------
local kat	= ns:taboption("misc", Value, "keep_alive_timeout")
kat.title_base	= "Keep-alive timeout"
kat.title	= string.format(HELP, "KEEP-ALIVE-TIMEOUT", kat.title_base)
kat.description	= translate("Number of seconds after which an open connection will no longer be reused.")
kat.rmempty	= true
function kat.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_misc(self, translate("Value is not a number") )
	elseif v < 1 then
		return nil, err_tab_misc(self, translate("Value not greater 0 or empty") )
	end
	return value
end

-- tolerate-pipelining ---------------------------------------------------------
local tp	= ns:taboption("misc", Flag, "tolerate_pipelining")
tp.title	= string.format(HELP, "TOLERATE-PIPELINING", "Tolerate pipelining" )
tp.description	= translate("Whether or not pipelined requests should be served.")
tp.orientation	= "horizontal"
tp.rmempty	= true
function tp.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- default-server-timeout ------------------------------------------------------
local dst	= ns:taboption("misc", Value, "default_server_timeout")
dst.title_base	= "Default server timeout"
dst.title	= string.format(HELP, "DEFAULT-SERVER-TIMEOUT", dst.title_base)
dst.description	= translate("Assumed server-side keep-alive timeout (in seconds) if not specified by the server.")
dst.rmempty	= true
function dst.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_misc(self, translate("Value is not a number") )
	elseif v < 1 then
		return nil, err_tab_misc(self, translate("Value not greater 0 or empty") )
	end
	return value
end

-- connection-sharing ----------------------------------------------------------
local cs	= ns:taboption("misc", Flag, "connection_sharing")
cs.title	= string.format(HELP, "CONNECTION-SHARING", "Connection sharing" )
cs.description	= translate("Whether or not outgoing connections that have been kept alive should be shared between different incoming connections.")
cs.orientation	= "horizontal"
cs.rmempty	= true
function cs.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- socket-timeout --------------------------------------------------------------
local st	= ns:taboption("misc", Value, "socket_timeout")
st.title_base	= "Socket timeout"
st.title	= string.format(HELP, "SOCKET-TIMEOUT", st.title_base )
st.description	= translate("Number of seconds after which a socket times out if no data is received.")
st.default	= 300
st.rmempty	= true
function st.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_misc(self, translate("Value is not a number") )
	elseif v < 1 then
		return nil, err_tab_misc(self, translate("Value not greater 0 or empty") )
	elseif v == self.default then
		return ""	-- dont need to save default
	end
	return value
end

-- max-client-connections ------------------------------------------------------
local mcc	= ns:taboption("misc", Value, "max_client_connections")
mcc.title_base	= "Max. client connections"
mcc.title	= string.format(HELP, "MAX-CLIENT-CONNECTIONS", mcc.title_base )
mcc.description	= translate("Maximum number of client connections that will be served.")
mcc.default	= 128
mcc.rmempty	= true
function mcc.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_misc(self, translate("Value is not a number") )
	elseif v < 1 then
		return nil, err_tab_misc(self, translate("Value not greater 0 or empty") )
	elseif v == self.default then
		return ""	-- dont need to save default
	end
	return value
end

-- handle-as-empty-doc-returns-ok ----------------------------------------------
local her	= ns:taboption("misc", Flag, "handle_as_empty_doc_returns_ok")
her.title	= string.format(HELP, "HANDLE-AS-EMPTY-DOC-RETURNS-OK", "Handle as empty doc returns ok" )
her.description	= translate("The status code Privoxy returns for pages blocked with +handle-as-empty-document.")
her.orientation	= "horizontal"
her.rmempty	= true
function her.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- enable-compression ----------------------------------------------------------
local ec	= ns:taboption("misc", Flag, "enable_compression")
ec.title	= string.format(HELP, "ENABLE-COMPRESSION", "Enable compression" )
ec.description	= translate("Whether or not buffered content is compressed before delivery.")
ec.orientation	= "horizontal"
ec.rmempty	= true
function ec.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- compression-level -----------------------------------------------------------
local cl	= ns:taboption("misc", Value, "compression_level")
cl.title_base	= "Compression level"
cl.title	= string.format(HELP, "COMPRESSION-LEVEL", cl.title_base )
cl.description	= translate("The compression level that is passed to the zlib library when compressing buffered content.")
cl.default	= 1
cl.rmempty	= true
function cl.validate(self, value)
	local v = tonumber(value)
	if not v then
		return nil, err_tab_misc(self, translate("Value is not a number") )
	elseif v < 0 or v > 9 then
		return nil, err_tab_misc(self, translate("Value not between 0 and 9") )
	elseif v == self.default then
		return ""	-- don't need to save default
	end
	return value
end

-- client-header-order ---------------------------------------------------------
local cho	= ns:taboption("misc", Value, "client_header_order")
cho.title	= string.format(HELP, "CLIENT-HEADER-ORDER", "Client header order" )
cho.description	= translate("The order in which client headers are sorted before forwarding them.")
		.. [[<br />]]
		.. translate("Syntax: Client header names delimited by spaces.")
cho.rmempty	= true

-- "debug"-tab definition -- ###################################################

-- single-threaded -------------------------------------------------------------
local st	= ns:taboption("debug", Flag, "single_threaded")
st.title	= string.format(HELP, "SINGLE-THREADED", "Single Threaded" )
st.description	= translate("Whether to run only one server thread.")
		.. [[<br /><strong>]]
		.. translate("This option is only there for debugging purposes. It will drastically reduce performance.")
		.. [[</strong>]]
st.rmempty	= true
function st.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d1	= ns:taboption("debug", Flag, "debug_1")
d1.title	= string.format(HELP, "DEBUG", "Debug 1" )
d1.description	= translate("Log the destination for each request Privoxy let through. See also 'Debug 1024'.")
d1.rmempty	= true
function d1.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d2	= ns:taboption("debug", Flag, "debug_2")
d2.title	= string.format(HELP, "DEBUG", "Debug 2" )
d2.description	= translate("Show each connection status")
d2.rmempty	= true
function d2.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d3	= ns:taboption("debug", Flag, "debug_4")
d3.title	= string.format(HELP, "DEBUG", "Debug 4" )
d3.description	= translate("Show I/O status")
d3.rmempty	= true
function d3.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d4	= ns:taboption("debug", Flag, "debug_8")
d4.title	= string.format(HELP, "DEBUG", "Debug 8" )
d4.description	= translate("Show header parsing")
d4.rmempty	= true
function d4.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d5	= ns:taboption("debug", Flag, "debug_16")
d5.title	= string.format(HELP, "DEBUG", "Debug 16" )
d5.description	= translate("Log all data written to the network")
d5.rmempty	= true
function d5.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d6	= ns:taboption("debug", Flag, "debug_32")
d6.title	= string.format(HELP, "DEBUG", "Debug 32" )
d6.description	= translate("Debug force feature")
d6.rmempty	= true
function d6.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d7	= ns:taboption("debug", Flag, "debug_64")
d7.title	= string.format(HELP, "DEBUG", "Debug 64" )
d7.description	= translate("Debug regular expression filters")
d7.rmempty	= true
function d7.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d8	= ns:taboption("debug", Flag, "debug_128")
d8.title	= string.format(HELP, "DEBUG", "Debug 128" )
d8.description	= translate("Debug redirects")
d8.rmempty	= true
function d8.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d9	= ns:taboption("debug", Flag, "debug_256")
d9.title	= string.format(HELP, "DEBUG", "Debug 256" )
d9.description	= translate("Debug GIF de-animation")
d9.rmempty	= true
function d9.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d10	= ns:taboption("debug", Flag, "debug_512")
d10.title	= string.format(HELP, "DEBUG", "Debug 512" )
d10.description	= translate("Common Log Format")
d10.rmempty	= true
function d10.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d11	= ns:taboption("debug", Flag, "debug_1024")
d11.title	= string.format(HELP, "DEBUG", "Debug 1024" )
d11.description	= translate("Log the destination for requests Privoxy didn't let through, and the reason why.")
d11.rmempty	= true
function d11.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d12	= ns:taboption("debug", Flag, "debug_2048")
d12.title	= string.format(HELP, "DEBUG", "Debug 2048" )
d12.description	= translate("CGI user interface")
d12.rmempty	= true
function d12.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d13	= ns:taboption("debug", Flag, "debug_4096")
d13.title	= string.format(HELP, "DEBUG", "Debug 4096" )
d13.description	= translate("Startup banner and warnings.")
d13.rmempty	= true
function d13.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d14	= ns:taboption("debug", Flag, "debug_8192")
d14.title	= string.format(HELP, "DEBUG", "Debug 8192" )
d14.description	= translate("Non-fatal errors - *we highly recommended enabling this*")
d14.rmempty	= true
function d14.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d15	= ns:taboption("debug", Flag, "debug_32768")
d15.title	= string.format(HELP, "DEBUG", "Debug 32768" )
d15.description	= translate("Log all data read from the network")
d15.rmempty	= true
function d15.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- debug -----------------------------------------------------------------------
local d16	= ns:taboption("debug", Flag, "debug_65536")
d16.title	= string.format(HELP, "DEBUG", "Debug 65536" )
d16.description	= translate("Log the applying actions")
d16.rmempty	= true
function d16.parse(self, section)
	CTRL.flag_parse(self, section)
end

-- tab: logview -- #############################################################

local lv	= ns:taboption("logview", DummyValue, "_logview")
lv.template	= "privoxy/detail_logview"
lv.inputtitle	= translate("Read / Reread log file")
lv.rows		= 50
function lv.cfgvalue(self, section)
	local lfile=self.map:get(ns.section, "logdir") .. "/" .. self.map:get(ns.section, "logfile")
	if NXFS.access(lfile) then
		return lfile .. "\n" .. translate("Please press [Read] button")
	end
	return lfile .. "\n" .. translate("File not found or empty")
end

return m
