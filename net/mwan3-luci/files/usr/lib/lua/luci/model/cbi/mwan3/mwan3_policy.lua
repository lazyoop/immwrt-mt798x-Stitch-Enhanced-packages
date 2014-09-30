-- ------ extra functions ------ --

function policy_check() -- check to see if any policy names exceed the maximum of 15 characters
	uci.cursor():foreach("mwan3", "policy",
		function (section)
			if string.len(section[".name"]) > 15 then
				toolong = 1
				err_name_list = err_name_list .. section[".name"] .. " "
			end
		end
	)
end

function policy_warn() -- display status and warning messages at the top of the page
	if toolong == 1 then
		return "<font color=\"ff0000\"><strong>WARNING: Some policies have names exceeding the maximum of 15 characters!</strong></font>"
	else
		return ""
	end
end

-- ------ policy configuration ------ --

ds = require "luci.dispatcher"
sys = require "luci.sys"

toolong = 0
err_name_list = " "
policy_check()


m5 = Map("mwan3", translate("MWAN3 Multi-WAN Policy Configuration"),
	translate(policy_warn()))
	m5:append(Template("mwan3/mwan3_config_css"))


mwan_policy = m5:section(TypedSection, "policy", translate("Policies"),
	translate("Policies are profiles grouping one or more members controlling how MWAN3 distributes traffic<br />" ..
	"Member interfaces with lower metrics are used first. Interfaces with the same metric load-balance<br />" ..
	"Load-balanced member interfaces distribute more traffic out those with higher weights<br />" ..
	"Names may contain characters A-Z, a-z, 0-9, _ and no spaces. Names must be 15 characters or less<br />" ..
	"Policies may not share the same name as configured interfaces, members or rules"))
	mwan_policy.addremove = true
	mwan_policy.dynamic = false
	mwan_policy.sectionhead = "Policy"
	mwan_policy.sortable = true
	mwan_policy.template = "cbi/tblsection"
	mwan_policy.extedit = ds.build_url("admin", "network", "mwan3", "configuration", "policy", "%s")
	function mwan_policy.create(self, section)
		TypedSection.create(self, section)
		m5.uci:save("mwan3")
		luci.http.redirect(ds.build_url("admin", "network", "mwan3", "configuration", "policy", section))
	end


use_member = mwan_policy:option(DummyValue, "use_member", translate("Members assigned"))
	use_member.rawhtml = true
	function use_member.cfgvalue(self, s)
		local tab, str = self.map:get(s, "use_member"), ""
		if tab then
			for k,v in pairs(tab) do
				str = str .. v .. "<br />"
			end
			return str
		else
			return "&#8212;"
		end
		
	end

last_resort = mwan_policy:option(DummyValue, "last_resort", translate("Last resort"))
	last_resort.rawhtml = true
	function last_resort.cfgvalue(self, s)
		local str = self.map:get(s, "last_resort")
		if str == "unreachable" or str == "" or str == null then
			return "unreachable (reject)"
		elseif str == "blackhole" then
			return "blackhole (drop)"
		elseif str == "main" then
			return "main (use main routing table)"
		end
	end

errors = mwan_policy:option(DummyValue, "errors", translate("Errors"))
	errors.rawhtml = true
	function errors.cfgvalue(self, s)
		if not string.find(err_name_list, " " .. s .. " ") then
			return ""
		else
			return "<span title=\"Name exceeds 15 characters\"><img src=\"/luci-static/resources/cbi/reset.gif\" alt=\"error\"></img></span>"
		end
	end


return m5
