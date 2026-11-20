-- Adds the port_goto action. Load this file from your Rex init.lua with dofile.

local home = os.getenv("HOME") or ""

local function tilde(path)
	if path == nil then
		return nil
	end
	if home ~= "" and path:sub(1, #home) == home then
		return "~" .. path:sub(#home + 1)
	end
	return path
end

local function basename(path)
	return path and path:match("([^/]+)$") or path
end

local function process_name(p)
	if p == nil then
		return nil
	end
	return basename(p.argv0) or p.name
end

-- Returns every port a terminal in any session listens on, sorted by port,
-- with one entry per terminal and port even when it listens on several
-- addresses.
local function listening_ports()
	local listed, err = rex.call("session.list")
	if listed == nil then
		error(err, 0)
	end

	local found, seen = {}, {}
	for _, s in ipairs(listed.sessions or {}) do
		local blocks = rex.call("session.list_blocks", { session_id = s.session_id })
		for _, b in ipairs(blocks and blocks.blocks or {}) do
			if b.creator_name == "com.superlogical.terminal" and b.placement == "placed" then
				local r = rex.call("block.method", {
					session_id = s.session_id,
					block_id = b.block_id,
					method = "ports",
				})
				if r ~= nil and r.ports ~= nil then
					local procs = {}
					for _, p in ipairs(r.processes or {}) do
						procs[p.pid] = p
					end
					for _, p in ipairs(r.ports) do
						local key = b.block_id .. "|" .. p.port
						if not seen[key] then
							seen[key] = true
							table.insert(found, {
								port = p.port,
								address = p.address,
								session_id = s.session_id,
								session_label = s.label,
								block_id = b.block_id,
								block_label = b.label,
								window_id = b.window_id,
								process = procs[p.pid],
							})
						end
					end
				end
			end
		end
	end

	table.sort(found, function(a, b)
		if a.port ~= b.port then
			return a.port < b.port
		end
		return a.session_label < b.session_label
	end)
	return found
end

local function go_to(ctx, entry)
	local _, err = rex.call("session.focus_block", {
		session_id = entry.session_id,
		block_id = entry.block_id,
	})
	if err ~= nil then
		error(err, 0)
	end
	if ctx.client_id ~= nil then
		rex.client.queue("session.select", {
			session_id = entry.session_id,
			window_id = entry.window_id,
		})
	end
	return {
		port = entry.port,
		session_id = entry.session_id,
		block_id = entry.block_id,
	}
end

rex.action({
	name = "port_goto",
	title = "Go to Port…",
	category = "Ports",
	description = "List the TCP ports that programs in your terminals listen on, and focus the pane that owns the one you choose. With port, goes straight to that port's pane.",
	keywords = "port ports listen localhost server focus pane find",
	args = { port = "integer?" },
	run = function(ctx, args)
		local entries = listening_ports()

		if args.port ~= nil then
			for _, e in ipairs(entries) do
				if e.port == args.port then
					return go_to(ctx, e)
				end
			end
			error("no terminal is listening on port " .. args.port, 0)
		end

		if #entries == 0 then
			error("no terminal is listening on a port", 0)
		end

		local items = {}
		for i, e in ipairs(entries) do
			local where = { e.session_label }
			if e.block_label ~= nil and e.block_label ~= "" then
				table.insert(where, e.block_label)
			end
			local cwd = e.process and tilde(e.process.cwd)
			if cwd ~= nil then
				table.insert(where, cwd)
			end
			table.insert(items, {
				id = tostring(i),
				title = ":" .. e.port .. "  " .. (process_name(e.process) or "?"),
				subtitle = table.concat(where, " · "),
				icon = "server",
				detail = e.address,
			})
		end

		local id, why, detail = rex.ui.pick({
			title = "Go to port",
			placeholder = "Filter by port, program, session or directory",
			items = items,
		})
		if id == nil then
			if why ~= "cancelled" then
				error(detail or ("couldn't ask: " .. tostring(why)), 0)
			end
			return
		end
		return go_to(ctx, entries[tonumber(id)])
	end,
})
