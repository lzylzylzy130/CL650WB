--[[
    CL650 Weight & Balance - (flightmodel/weight + flightmodel2/misc)

    Author:     lzylzylzy130
    Created:    2026-01-09

    Datarefs used:
        Weights:
            sim/flightmodel/weight/m_fixed            (kg) payload total
            sim/flightmodel/weight/m_stations[9]      (kg) payload per station
            sim/flightmodel/weight/m_total            (kg) total weight
            sim/flightmodel/weight/m_fuel[9]          (kg) fuel per tank (9 tanks)
            sim/flightmodel/weight/m_fuel1/2/3        (kg) convenience fuel tank weights
            sim/flightmodel/weight/m_jettison         (kg) jettison
            sim/flightmodel/weight/m_fuel_total       (kg) fuel total

        CG outputs:
            sim/flightmodel2/misc/cg_offset_z         (m) longitudinal CG (per X-Plane doc string)
            sim/flightmodel2/misc/cg_offset_x         (m) lateral CG
            sim/flightmodel2/misc/cg_offset_z_mac     (%MAC) longitudinal CG in %MAC

    Features:
        - Unit selector kg / lbs (display only)
        - Auto ZFW = m_total - fuel_used
        - Manual override (what-if only; no write-back)
        - Auto value shown before each input
        - Main report + collapsed debug block
        - Fuel source selector for calculations:
            F123     -> m_fuel1+m_fuel2+m_fuel3   (listed first)
            TOTAL    -> m_fuel_total
            ARRAYSUM -> sum(m_fuel[0..8])

    --]]

-----------------------------------------
-- 1) GLOBALS & LIMITS (kg)
-----------------------------------------
local my_window   = nil
local show_window = false

local LIMIT_OEW_KG  = 12556.0
local LIMIT_MZFW_KG = 14515.0
local LIMIT_MTOW_KG = 21863.0

-----------------------------------------
-- 2) UNITS
-----------------------------------------
local KG_TO_LB = 2.2046226218
local display_unit = "kg" -- "kg" or "lbs"

local function to_disp_mass(kg)
    if display_unit == "lbs" then return kg * KG_TO_LB end
    return kg
end

local function from_disp_mass(v)
    if display_unit == "lbs" then return v / KG_TO_LB end
    return v
end

local function mass_unit()
    return (display_unit == "lbs") and "lbs" or "kg"
end

local function fmt_mass(kg, d)
    d = d or 1
    return string.format("%." .. d .. "f %s", to_disp_mass(kg), mass_unit())
end

local function fmt_m(x, d)
    d = d or 3
    return string.format("%." .. d .. "f m", x)
end

local function fmt_mac(x, d)
    d = d or 2
    return string.format("%." .. d .. "f %%MAC", x)
end

-----------------------------------------
-- 3) SAFE DATAREF BINDING
-----------------------------------------
local function safe_dataref(varname, path, mode)
    mode = mode or "readonly"
    local dr = XPLMFindDataRef(path)
    if dr ~= nil then
        dataref(varname, path, mode)
        return true
    else
        return false
    end
end

local function nz(x) return x or 0.0 end

-----------------------------------------
-- 4) DATAREFS
-----------------------------------------
local HAS_m_fixed      = safe_dataref("m_fixed",      "sim/flightmodel/weight/m_fixed",      "readonly")
local HAS_m_total      = safe_dataref("m_total",      "sim/flightmodel/weight/m_total",      "readonly")
local HAS_m_jettison   = safe_dataref("m_jettison",   "sim/flightmodel/weight/m_jettison",   "readonly")
local HAS_m_fuel_total = safe_dataref("m_fuel_total", "sim/flightmodel/weight/m_fuel_total", "readonly")

local HAS_m_fuel1 = safe_dataref("m_fuel1", "sim/flightmodel/weight/m_fuel1", "readonly")
local HAS_m_fuel2 = safe_dataref("m_fuel2", "sim/flightmodel/weight/m_fuel2", "readonly")
local HAS_m_fuel3 = safe_dataref("m_fuel3", "sim/flightmodel/weight/m_fuel3", "readonly")

for i = 0, 8 do
    safe_dataref("m_station_"..i, "sim/flightmodel/weight/m_stations["..i.."]", "readonly")
    safe_dataref("m_fuel_"..i,    "sim/flightmodel/weight/m_fuel["..i.."]",     "readonly")
end

local HAS_cg_off_z     = safe_dataref("cg_offset_z",     "sim/flightmodel2/misc/cg_offset_z",     "readonly")
local HAS_cg_off_x     = safe_dataref("cg_offset_x",     "sim/flightmodel2/misc/cg_offset_x",     "readonly")
local HAS_cg_off_z_mac = safe_dataref("cg_offset_z_mac", "sim/flightmodel2/misc/cg_offset_z_mac", "readonly")

-----------------------------------------
-- 5) AUTO VALUES
-----------------------------------------
local function auto_total_kg()   return nz(m_total) end
local function auto_payload_kg() return nz(m_fixed) end

local function sum_station_kg()
    local s = 0.0
    for i = 0, 8 do s = s + nz(_G["m_station_"..i]) end
    return s
end

local function sum_fuel_array_kg()
    local s = 0.0
    for i = 0, 8 do s = s + nz(_G["m_fuel_"..i]) end
    return s
end

local function sum_fuel123_kg()
    return nz(m_fuel1) + nz(m_fuel2) + nz(m_fuel3)
end

-----------------------------------------
-- 6) FUEL SOURCE FOR CALC
-----------------------------------------
-- "F123"  -> m_fuel1+m_fuel2+m_fuel3 (preferred first)
-- "TOTAL" -> m_fuel_total
-- "ARRAY" -> sum(m_fuel[0..8])
local fuel_source = "F123"

local function auto_fob_kg()
    if fuel_source == "F123" then
        return sum_fuel123_kg()
    elseif fuel_source == "ARRAY" then
        return sum_fuel_array_kg()
    else
        return nz(m_fuel_total)
    end
end

local function auto_zfw_kg()
    return auto_total_kg() - auto_fob_kg()
end

local function auto_oew_kg()
    return auto_zfw_kg() - auto_payload_kg()
end

-----------------------------------------
-- 7) MANUAL OVERRIDE (what-if)
-----------------------------------------
local manual_mode = false
local man_total_kg      = 0.0
local man_fob_kg  = 0.0
local man_payload_kg    = 0.0

local calc_message = ""

local function sync_manual_from_auto()
    man_total_kg     = auto_total_kg()
    man_fob_kg = auto_fob_kg()
    man_payload_kg   = auto_payload_kg()
end

sync_manual_from_auto()

-----------------------------------------
-- 8) REPORT BUILDERS
-----------------------------------------
local function build_main_report(total_kg, fob_kg, payload_kg)
    local zfw_kg = total_kg - fob_kg
    local oew_kg = zfw_kg - payload_kg

    local mtow_margin_kg = LIMIT_MTOW_KG - total_kg
    local mzfw_margin_kg = LIMIT_MZFW_KG - zfw_kg
    local oew_delta_kg   = oew_kg - LIMIT_OEW_KG

    local flags = {}
    if zfw_kg > LIMIT_MZFW_KG + 1e-6 then table.insert(flags, "WARN: ZFW > MZFW") end
    if total_kg > LIMIT_MTOW_KG + 1e-6 then table.insert(flags, "WARN: TOTAL > MTOW") end

    local lines = {}
    table.insert(lines, "==== KEY WEIGHTS ====")
    table.insert(lines, "TOTAL      : " .. fmt_mass(total_kg, 1))
    table.insert(lines, "FOB        : " .. fmt_mass(fob_kg, 1) .. "   (source=" .. fuel_source .. ")")
    table.insert(lines, "ZFW        : " .. fmt_mass(zfw_kg, 1) .. "   (MZFW margin: " .. fmt_mass(mzfw_margin_kg, 1) .. ")")
    table.insert(lines, "PAYLOAD    : " .. fmt_mass(payload_kg, 1))
    table.insert(lines, "OEW(check) : " .. fmt_mass(oew_kg, 1) .. string.format("   (d_vs_OEW %.0f kg: %+0.1f kg)", LIMIT_OEW_KG, oew_delta_kg))
    table.insert(lines, "MTOW margin: " .. fmt_mass(mtow_margin_kg, 1))

    table.insert(lines, "")
    table.insert(lines, "==== CG OUTPUTS (from sim/flightmodel2/misc) ====")
    if HAS_cg_off_z then
        table.insert(lines, "cg_offset_z     : " .. fmt_m(nz(cg_offset_z), 3))
    else
        table.insert(lines, "cg_offset_z     : (missing)")
    end
    if HAS_cg_off_x then
        table.insert(lines, "cg_offset_x     : " .. fmt_m(nz(cg_offset_x), 3))
    else
        table.insert(lines, "cg_offset_x     : (missing)")
    end
    if HAS_cg_off_z_mac then
        table.insert(lines, "cg_offset_z_mac : " .. fmt_mac(nz(cg_offset_z_mac), 2))
    else
        table.insert(lines, "cg_offset_z_mac : (missing)")
    end

    table.insert(lines, "")
    if #flags == 0 then
        table.insert(lines, "STATUS: OK")
    else
        table.insert(lines, "STATUS: " .. table.concat(flags, " | "))
    end

    return table.concat(lines, "\n")
end

local function build_debug_report()
    local st_sum = sum_station_kg()
    local fu_arr = sum_fuel_array_kg()
    local fu_123 = sum_fuel123_kg()
    local fu_tot = nz(m_fuel_total)

    local diff_station = st_sum - nz(m_fixed)
    local diff_arr_tot = fu_arr - fu_tot
    local diff_123_tot = fu_123 - fu_tot

    local lines = {}
    table.insert(lines, "==== DEBUG / DIAGNOSTICS ====")

    table.insert(lines, "")
    table.insert(lines, "Raw weights (auto):")
    table.insert(lines, "  m_total      = " .. fmt_mass(nz(m_total), 1))
    table.insert(lines, "  m_fuel_total = " .. fmt_mass(fu_tot, 1))
    table.insert(lines, "  m_fixed      = " .. fmt_mass(nz(m_fixed), 1))
    table.insert(lines, "  m_jettison   = " .. fmt_mass(nz(m_jettison), 1))

    table.insert(lines, "")
    table.insert(lines, "Fuel cross-check:")
    table.insert(lines, "  sum(m_fuel[0..8]) = " .. fmt_mass(fu_arr, 1) .. "  diff_vs_m_fuel_total = " .. fmt_mass(diff_arr_tot, 1))
    table.insert(lines, "  fuel1+fuel2+fuel3 = " .. fmt_mass(fu_123, 1) .. "  diff_vs_m_fuel_total = " .. fmt_mass(diff_123_tot, 1))

    table.insert(lines, "")
    table.insert(lines, "Payload cross-check:")
    table.insert(lines, "  sum(m_stations[0..8]) = " .. fmt_mass(st_sum, 1) .. "  diff_vs_m_fixed = " .. fmt_mass(diff_station, 1))

    return table.concat(lines, "\n")
end

-----------------------------------------
-- 9) WINDOW TOGGLE MACRO
-----------------------------------------
function toggle_window()
    if not show_window then
        show_window = true
        if not my_window then create_floating_window() end
    else
        show_window = false
        if my_window then
            float_wnd_destroy(my_window)
            my_window = nil
        end
    end
end

add_macro("CL650 Weight & Balance: Toggle Window", "toggle_window()", "", "")

-----------------------------------------
-- 10) CREATE WINDOW
-----------------------------------------
function create_floating_window()
    if not SUPPORTS_FLOATING_WINDOWS then
        logMsg("Floating windows not supported by this FlyWithLua version.")
        return
    end

    my_window = float_wnd_create(560, 630, 1, true)
    float_wnd_set_title(my_window, "CL650 W&B + CG (flightmodel2/misc)")
    float_wnd_set_imgui_builder(my_window, "on_build_gui")

    if SCREEN_WIDTH and SCREEN_HEIGHT then
        float_wnd_set_position(my_window, (SCREEN_WIDTH - 560) / 2,
                                          (SCREEN_HEIGHT - 630) / 2)
    end
end

-- ----------------------------
-- Custom commands for key/button binding
-- ----------------------------

-- Show only (bring up window, do not hide if already visible)
function CL650WB_Show()
    if not show_window then
        show_window = true
        if not my_window then
            create_floating_window()
        end
    end
end

-- Toggle (show/hide)
function CL650WB_Toggle()
    toggle_window()
end

-- These will appear in X-Plane bindings under:
-- "FlyWithLua | CL650WB ..."
create_command("FlyWithLua/CL650WB/show_window",
               "CL650 W&B: Show window",
               "CL650WB_Show()",
               "",
               "")

create_command("FlyWithLua/CL650WB/toggle_window",
               "CL650 W&B: Toggle window",
               "CL650WB_Toggle()",
               "",
               "")


-----------------------------------------
-- 11) IMGUI BUILDER
-----------------------------------------
local show_debug = false -- collapsed by default

function on_build_gui(window_id)
    if not show_window then return end

    if not manual_mode then sync_manual_from_auto() end

    imgui.TextUnformatted("CL650 Weight & Balance - CG from sim/flightmodel2/misc")
    imgui.Separator()

    -- Units
    imgui.TextUnformatted("Display Units:")
    imgui.SameLine()
    if imgui.RadioButton("kg##u", display_unit == "kg") then display_unit = "kg" end
    imgui.SameLine()
    if imgui.RadioButton("lbs##u", display_unit == "lbs") then display_unit = "lbs" end

    imgui.Spacing()

    -- Fuel source selector (line break after the label to reduce width)
    imgui.TextUnformatted("Fuel source used for calculations:")
    if imgui.RadioButton("F123 (fuel1+2+3)##fs", fuel_source == "F123") then
        fuel_source = "F123"
        if not manual_mode then sync_manual_from_auto() end
    end
    imgui.SameLine()
    if imgui.RadioButton("TOTAL (m_fuel_total)##fs", fuel_source == "TOTAL") then
        fuel_source = "TOTAL"
        if not manual_mode then sync_manual_from_auto() end
    end
    imgui.SameLine()
    if imgui.RadioButton("ARRAYSUM (m_fuel[0..8])##fs", fuel_source == "ARRAY") then
        fuel_source = "ARRAY"
        if not manual_mode then sync_manual_from_auto() end
    end

    imgui.Spacing()

    -- Manual toggle + sync
    local ch_mode, v_mode = imgui.Checkbox("Manual override (what-if only, no write-back)", manual_mode)
    if ch_mode then
        manual_mode = v_mode
        if not manual_mode then sync_manual_from_auto() end
    end
    imgui.SameLine()
    if imgui.Button("Sync manual from sim##sync") then sync_manual_from_auto() end

    imgui.Spacing()
    imgui.Separator()

    -- Auto summary
    local a_total   = auto_total_kg()
    local a_fuelU   = auto_fob_kg()
    local a_payload = auto_payload_kg()
    local a_zfw     = auto_zfw_kg()
    local a_oew     = auto_oew_kg()

    imgui.TextUnformatted("AUTO (from sim):")
    imgui.TextUnformatted("  TOTAL: " .. fmt_mass(a_total, 1) .. "   FUEL USED: " .. fmt_mass(a_fuelU, 1) .. " (source=" .. fuel_source .. ")")
    imgui.TextUnformatted("  ZFW  : " .. fmt_mass(a_zfw, 1)   .. "   PAYLOAD: " .. fmt_mass(a_payload, 1))
    imgui.TextUnformatted("  OEW(check): " .. fmt_mass(a_oew, 1) .. "   Jettison: " .. fmt_mass(nz(m_jettison), 1))

    imgui.Spacing()
    imgui.Separator()

    -- Inputs with auto shown before
    imgui.TextUnformatted("INPUTS (used for calculation):")

    local supports_disabled = (imgui.BeginDisabled ~= nil and imgui.EndDisabled ~= nil)
    if supports_disabled and (not manual_mode) then imgui.BeginDisabled(true) end

    imgui.TextUnformatted("Auto m_total: " .. fmt_mass(a_total, 1))
    local ch_t, v_t = imgui.InputFloat("TOTAL used##total", to_disp_mass(man_total_kg), 0, 0, "%.1f")
    if ch_t and manual_mode then man_total_kg = math.max(0.0, from_disp_mass(v_t)) end

    imgui.TextUnformatted("Auto fuel used: " .. fmt_mass(a_fuelU, 1))
    local ch_f, v_f = imgui.InputFloat("FUEL used##fuel", to_disp_mass(man_fob_kg), 0, 0, "%.1f")
    if ch_f and manual_mode then man_fob_kg = math.max(0.0, from_disp_mass(v_f)) end

    imgui.TextUnformatted("Auto m_fixed (payload): " .. fmt_mass(a_payload, 1))
    local ch_p, v_p = imgui.InputFloat("PAYLOAD used##payload", to_disp_mass(man_payload_kg), 0, 0, "%.1f")
    if ch_p and manual_mode then man_payload_kg = math.max(0.0, from_disp_mass(v_p)) end

    if supports_disabled and (not manual_mode) then imgui.EndDisabled() end

    imgui.Spacing()
    imgui.Separator()

    -- Calculate / report
    if imgui.Button("Calculate / Refresh Report##calc") then
        local use_total   = manual_mode and man_total_kg     or a_total
        local use_fuelU   = manual_mode and man_fob_kg or a_fuelU
        local use_payload = manual_mode and man_payload_kg   or a_payload
        calc_message = build_main_report(use_total, use_fuelU, use_payload)
    end

    if calc_message ~= "" then
        imgui.Spacing()
        imgui.Separator()
        imgui.TextUnformatted(calc_message)
    end

    imgui.Spacing()
    imgui.Separator()

    -- Debug block collapsed
    local ch_dbg, v_dbg = imgui.Checkbox("Show debug / diagnostics (collapsed by default)", show_debug)
    if ch_dbg then show_debug = v_dbg end
    if show_debug then
        imgui.Spacing()
        imgui.Separator()
        imgui.TextUnformatted(build_debug_report())
    end
end
