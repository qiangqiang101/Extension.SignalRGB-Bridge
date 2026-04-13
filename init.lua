-------------------------------------------------------------------
-- SignalRGB Bridge Extension
--
-- Bridges SignalRGB JS device scripts to the Skydimo lighting
-- engine. Thin entry point — all logic lives in lib/ modules.
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

-------------------------------------------------------------------
-- Extension callbacks
-------------------------------------------------------------------

local P = {}

function P.on_start()
    ext.log("[SRGB] SignalRGB Bridge starting")

    disabled_set = load_disabled_set()

    ext.notify_persistent("srgb-scan", "SignalRGB Bridge",
        "Scanning device scripts...")
    local results = scanner.scan_directory(scripts_dir(), function(msg)
        ext.log(msg)
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
    ext.notify("SignalRGB Bridge",
        total .. " scripts loaded, " .. matched .. " device(s) matched",
        matched > 0 and "success" or "info")
end

function P.on_stop()
    ext.log("[SRGB] SignalRGB Bridge stopping")
    device.remove_all()
    script_db = {}
    scan_results = {}
end

function P.on_scan_devices()
    ext.notify_persistent("srgb-scan", "SignalRGB Bridge", "Rescanning...")
    local results = scanner.scan_directory(scripts_dir(), function(msg)
        ext.log(msg)
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
        end
    end

    local matched = discovery.discover_and_register(script_db)
    ext.notify("SignalRGB Bridge",
        #script_db .. " scripts, " .. matched .. " new device(s)",
        matched > 0 and "success" or "info")
    emit_scripts_snapshot()
end

function P.on_devices_changed(_devices)
    -- No action needed
end

function P.on_page_message(msg)
    if type(msg) ~= "table" then return end

    local t = msg.type

    if t == "bootstrap" or t == "refresh" then
        emit_scripts_snapshot()

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

    elseif t == "rescan" then
        P.on_scan_devices()
    end
end

function P.on_device_frame(port, outputs)
    local state = device.get(port)
    if not state or not state.js_ctx then return end

    local pushed, push_err = frame.push(state.js_ctx, outputs or {}, state)
    if not pushed then
        ext.log("[SRGB] Frame push failed for " .. (state.rt_name or "?")
            .. ": " .. tostring(push_err))
        return
    end

    local ok, err = pcall(state.js_ctx.call, state.js_ctx, "Render")
    if not ok then
        ext.log("[SRGB] Render() failed for " .. (state.rt_name or "?")
            .. ": " .. tostring(err))
    end

    local synced, sync_err = device.sync_topology(state)
    if not synced then
        ext.log("[SRGB] Topology sync failed for "
            .. (state.rt_name or state.meta.name or "?") .. ": "
            .. tostring(sync_err))
    end
end

return P
