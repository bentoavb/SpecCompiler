local M = {}

local units = {
    px = 9525,
    pt = 12700,
    pc = 152400,
    ["in"] = 914400,
    cm = 360000,
    mm = 36000,
}

function M.normalize(value)
    if not value then return "-" end
    local number, unit = tostring(value):match("^%s*(%d*%.?%d+)%s*(%a*%%?)%s*$")
    if unit == "" then unit = "px" end
    if not number or tonumber(number) <= 0 or (unit ~= "%" and not units[unit]) then
        error("Invalid presentation image dimension: " .. tostring(value))
    end
    return number .. unit
end

function M.to_emu(value, reference)
    if value == "-" then return nil end
    local number, unit = value:match("^(%d*%.?%d+)(%a*%%?)$")
    if unit == "%" then return tonumber(number) * reference / 100 end
    return tonumber(number) * units[unit]
end

return M
