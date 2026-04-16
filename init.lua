-------------------------------------------------------------------
-- SignalRGB Script Driver Extension
--
-- QuickJS-based compatibility driver for running SignalRGB
-- device scripts in Skydimo. Thin entry point — all logic
-- lives in lib/ modules.
-------------------------------------------------------------------

local utils     = require("lib.utils")
local scanner   = require("lib.scanner")
local discovery = require("lib.discovery")
local device    = require("lib.device")
local frame     = require("lib.frame")
local endpoint  = require("lib.endpoint")

-------------------------------------------------------------------
-- State
-------------------------------------------------------------------
local script_db = {}        -- array of { meta = {…} }
local scan_results = {}     -- array of { meta?, error?, path? }
local disabled_set = {}     -- set of source_path → true
local port_stats = {}       -- port → { count, t0, render_sum, render_max, errors, fps, avg_ms, max_ms }
local last_stats_emit = os.clock()
local STATS_INTERVAL = 2.0  -- emit device stats every N seconds

local DISABLED_FILE = "disabled_scripts.json"

local function scripts_dir()
    return ext.data_dir .. "/" .. utils.SCRIPTS_SUBDIR
end

-------------------------------------------------------------------
-- Disabled-scripts persistence
-------------------------------------------------------------------
local function load_disabled_set()
    local path = ext.data_dir .. "/" .. DISABLED_FILE
    local content = utils.read_file(path)
    if not content then return {} end
    local ok, tbl = pcall(ext.json_decode, content)
    if ok and type(tbl) == "table" then
        local set = {}
        for _, v in ipairs(tbl) do
            if type(v) == "string" then set[v] = true end
        end
        return set
    end
    return {}
end

local function save_disabled_set()
    local arr = {}
    for path_key in pairs(disabled_set) do
        arr[#arr + 1] = path_key
    end
    table.sort(arr)
    local json = ext.json_encode(arr)
    local path = ext.data_dir .. "/" .. DISABLED_FILE
    local fh = io.open(path, "w")
    if fh then
        fh:write(json)
        fh:close()
    end
end

-------------------------------------------------------------------
-- Script filtering helpers
-------------------------------------------------------------------

--- Build an active script_db (excluding disabled) from scan_results.
local function active_script_db()
    local active = {}
    for _, r in ipairs(scan_results) do
        if r.meta and not disabled_set[r.meta.source_path] then
            active[#active + 1] = r
        end
    end
    return active
end

--- Build a page-friendly snapshot of all scan results.
local function build_scripts_snapshot()
    local items = {}
    for _, r in ipairs(scan_results) do
        if r.meta then
            local source = r.meta.source_path or ""
            local has_devices = false
            for _, state in pairs(device.all()) do
                if state.meta and state.meta.source_path == source then
                    has_devices = true
                    break
                end
            end
            items[#items + 1] = {
                name = r.meta.name,
                path = source,
                vid = r.meta.vid,
                pids = r.meta.pids,
                device_type = r.meta.device_type,
                publisher = r.meta.publisher,
                status = "ok",
                disabled = disabled_set[source] == true,
                has_devices = has_devices,
            }
        else
            items[#items + 1] = {
                path = r.error and r.error:match("^(.-):%s") or "?",
                error_message = r.error or "Unknown error",
                status = "error",
                disabled = false,
                has_devices = false,
            }
        end
    end
    return items
end

--- Remove all devices associated with a given script source_path.
local function remove_devices_for_script(source_path)
    local ports_to_remove = {}
    for port, state in pairs(device.all()) do
        if state.meta and state.meta.source_path == source_path then
            ports_to_remove[#ports_to_remove + 1] = port
        end
    end
    for _, port in ipairs(ports_to_remove) do
        ext.log("[SRGB] Removing device for disabled script: " .. port)
        device.remove(port)
        port_stats[port] = nil
    end
    return #ports_to_remove
end

--- Emit the scripts snapshot to the page.
local function emit_scripts_snapshot()
    ext.page_emit({
        type = "scripts_snapshot",
        scripts = build_scripts_snapshot(),
    })
end

local function format_hex16(value)
    local num = tonumber(value)
    if not num then return nil end
    return string.format("0x%04X", math.max(0, math.floor(num)))
end

local function classify_perf_state(stats)
    if not stats or not stats.fps or stats.fps <= 0 then
        return "idle"
    end
    if stats.fps >= 45 then
        return "running"
    end
    if stats.fps >= 15 then
        return "slow"
    end
    return "blocked"
end

--- Build a page-friendly snapshot of devices registered by this plugin.
local function build_devices_snapshot()
    local result = {}
    for port, state in pairs(device.all()) do
        local s = port_stats[port]
        local outputs = state.registered and state.registered.outputs or {}
        local total_leds = 0
        for _, output in ipairs(outputs) do
            total_leds = total_leds + math.max(0, math.floor(tonumber(output.leds_count) or 0))
        end

        local fps = s and s.fps or 0
        local render_ms = s and s.avg_ms or 0
        local max_render_ms = s and s.max_ms or 0
        local errors = s and s.errors_snapshot or 0

        result[#result + 1] = {
            port = port,
            name = state.rt_name or (state.meta and state.meta.name) or "?",
            script_name = state.meta and state.meta.name or "?",
            script_path = state.meta and state.meta.source_path or "",
            device_path = state.hid_info and state.hid_info.path or "",
            publisher = state.meta and state.meta.publisher or nil,
            vid = format_hex16(state.hid_info and state.hid_info.vid or (state.meta and state.meta.vid)),
            pid = format_hex16(state.hid_info and state.hid_info.pid),
            device_type = state.meta and state.meta.device_type or nil,
            output_count = #outputs,
            total_leds = total_leds,
            fps = math.floor(fps * 10 + 0.5) / 10,
            render_ms = math.floor(render_ms * 10 + 0.5) / 10,
            max_render_ms = math.floor(max_render_ms * 10 + 0.5) / 10,
            errors = errors,
            perf_state = classify_perf_state({
                fps = fps,
            }),
        }
    end

    table.sort(result, function(lhs, rhs)
        local perf_rank = {
            running = 0,
            slow = 1,
            blocked = 2,
            idle = 3,
        }

        local left_rank = perf_rank[lhs.perf_state] or 9
        local right_rank = perf_rank[rhs.perf_state] or 9
        if left_rank ~= right_rank then
            return left_rank < right_rank
        end

        local left_name = tostring(lhs.name or ""):lower()
        local right_name = tostring(rhs.name or ""):lower()
        if left_name ~= right_name then
            return left_name < right_name
        end

        return tostring(lhs.port or "") < tostring(rhs.port or "")
    end)

    return result
end

--- Emit plugin-owned device state to the page.
local function emit_devices_snapshot()
    ext.page_emit({
        type = "devices_snapshot",
        devices = build_devices_snapshot(),
    })
end

device.set_change_listener(function(kind, state)
    if kind == "removed" and state and state.controller_port then
        port_stats[state.controller_port] = nil
    end
    emit_devices_snapshot()
end)

--- Emit periodic device performance stats to the page.
local function emit_device_stats_tick()
    local devices = build_devices_snapshot()
    if #devices == 0 then
        return
    end

    emit_devices_snapshot()
end

-------------------------------------------------------------------
-- Extension callbacks
-------------------------------------------------------------------

local P = {}

function P.on_start()
    ext.log("[SRGB] SignalRGB Script Driver (beta) starting")

    disabled_set = load_disabled_set()

    ext.notify_persistent("srgb-scan", "SignalRGB Script Driver (beta)",
        "Scanning device scripts...")
    local results = scanner.scan_directory(scripts_dir(), function(msg)
        ext.debug(msg)
    end, function(current, total)
        ext.notify_persistent("srgb-scan", "SignalRGB Script Driver (beta)",
            "Scanning device scripts... (" .. current .. "/" .. total .. ")")
    end)
    ext.dismiss_persistent("srgb-scan")

    scan_results = results
    script_db = {}
    local total, errors, skipped = 0, 0, 0
    for _, r in ipairs(results) do
        if r.meta then
            if disabled_set[r.meta.source_path] then
                skipped = skipped + 1
            else
                script_db[#script_db + 1] = r
            end
            total = total + 1
        else
            errors = errors + 1
        end
    end

    ext.log("[SRGB] Scanned " .. total .. " script(s), "
        .. errors .. " error(s), " .. skipped .. " disabled")

    local matched = discovery.discover_and_register(script_db)
    ext.notify("SignalRGB Script Driver (beta)",
        total .. " scripts loaded, " .. matched .. " device(s) matched",
        matched > 0 and "success" or "info")
    emit_scripts_snapshot()
    emit_devices_snapshot()
end

function P.on_stop()
    ext.log("[SRGB] SignalRGB Script Driver (beta) stopping")
    device.remove_all()
    script_db = {}
    scan_results = {}
    port_stats = {}
    emit_scripts_snapshot()
    emit_devices_snapshot()
end

function P.on_scan_devices()
    ext.notify_persistent("srgb-scan", "SignalRGB Script Driver (beta)", "Rescanning...")
    local results = scanner.scan_directory(scripts_dir(), function(msg)
        ext.debug(msg)
    end, function(current, total)
        ext.notify_persistent("srgb-scan", "SignalRGB Script Driver (beta)",
            "Rescanning... (" .. current .. "/" .. total .. ")")
    end)
    ext.dismiss_persistent("srgb-scan")

    scan_results = results
    script_db = {}
    for _, r in ipairs(results) do
        if r.meta and not disabled_set[r.meta.source_path] then
            script_db[#script_db + 1] = r
        end
    end

    -- Remove stale devices whose HID path is no longer present
    local ok_enum, curr_hid = pcall(ext.hid_enumerate, nil, nil)
    if ok_enum then
        local curr_groups = {}
        for _, hid in ipairs(curr_hid) do
            curr_groups[endpoint.normalize_path(hid.path)] = true
        end
        local stale = {}
        for port, state in pairs(device.all()) do
            if not curr_groups[endpoint.normalize_path(state.hid_info.path)] then
                stale[#stale + 1] = port
            end
        end
        for _, port in ipairs(stale) do
            ext.log("[SRGB] Removing stale: " .. port)
            device.remove(port)
            port_stats[port] = nil
        end
    end

    local matched = discovery.discover_and_register(script_db)
    ext.notify("SignalRGB Script Driver (beta)",
        #script_db .. " scripts, " .. matched .. " new device(s)",
        matched > 0 and "success" or "info")
    emit_scripts_snapshot()
    emit_devices_snapshot()
end

function P.on_devices_changed(_devices)
    -- No action needed
end

function P.on_page_message(msg)
    if type(msg) ~= "table" then return end

    local t = msg.type

    if t == "bootstrap" or t == "refresh" then
        emit_scripts_snapshot()
        emit_devices_snapshot()

    elseif t == "toggle_script" then
        local path = msg.path
        if type(path) ~= "string" or path == "" then return end

        if msg.disabled then
            -- Disable script
            disabled_set[path] = true
            save_disabled_set()
            local removed = remove_devices_for_script(path)
            -- Rebuild active script_db
            script_db = active_script_db()
            ext.log("[SRGB] Disabled script: " .. path
                .. " (removed " .. removed .. " device(s))")
        else
            -- Enable script
            disabled_set[path] = nil
            save_disabled_set()
            -- Re-add to active db and discover devices for it
            script_db = active_script_db()
            local matched = discovery.discover_and_register(script_db)
            ext.log("[SRGB] Enabled script: " .. path
                .. " (matched " .. matched .. " device(s))")
        end
        emit_scripts_snapshot()
        emit_devices_snapshot()

    elseif t == "rescan" then
        P.on_scan_devices()
    end
end

function P.on_device_frame(port, outputs)
    local state = device.get(port)
    if not state or not state.js_ctx then return end

    local t_start = os.clock()

    local pushed, push_err = frame.push(state.js_ctx, outputs or {}, state)
    if not pushed then
        ext.log("[SRGB] Frame push failed for " .. (state.rt_name or "?")
            .. ": " .. tostring(push_err))
        return
    end

    local render_ok = true
    local ok, err = pcall(state.js_ctx.call, state.js_ctx, "Render")
    if not ok then
        render_ok = false
        ext.log("[SRGB] Render() failed for " .. (state.rt_name or "?")
            .. ": " .. tostring(err))
    end

    local synced, sync_err = device.sync_topology(state)
    if not synced then
        ext.log("[SRGB] Topology sync failed for "
            .. (state.rt_name or state.meta.name or "?") .. ": "
            .. tostring(sync_err))
    end

    -- ── Frame stats tracking ──────────────────────────────
    local render_ms = (os.clock() - t_start) * 1000
    local s = port_stats[port]
    if not s then
        s = { count = 0, t0 = os.clock(), render_sum = 0, render_max = 0,
              errors = 0, errors_snapshot = 0, fps = 0, avg_ms = 0, max_ms = 0 }
        port_stats[port] = s
    end
    s.count = s.count + 1
    s.render_sum = s.render_sum + render_ms
    if render_ms > s.render_max then s.render_max = render_ms end
    if not render_ok then s.errors = s.errors + 1 end

    local now = os.clock()
    if now - last_stats_emit >= STATS_INTERVAL then
        for _, ps in pairs(port_stats) do
            local elapsed = now - ps.t0
            if elapsed > 0 and ps.count > 0 then
                ps.fps = ps.count / elapsed
                ps.avg_ms = ps.render_sum / ps.count
                ps.max_ms = ps.render_max
            end
            ps.errors_snapshot = ps.errors
            ps.count = 0
            ps.t0 = now
            ps.render_sum = 0
            ps.render_max = 0
            ps.errors = 0
        end
        emit_device_stats_tick()
        last_stats_emit = now
    end
end

return P
