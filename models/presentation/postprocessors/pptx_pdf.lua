---Optional PPTX-to-PDF export postprocessor.
---Uses the shared LibreOffice process helper after the PPTX package is finalized.

local libreoffice = require("infra.process.libreoffice")

local M = {}

local function enabled(value)
    if value == true then return true end
    if type(value) ~= "string" then return false end
    return value:lower():match("^(true|yes|on|1)$") ~= nil
end

local function resolve_pdf_path(pptx_path, pptx_config, config)
    local configured = pptx_config.pdf_path
    if configured and configured ~= "" then
        local filename = pptx_path:match("([^/\\]+)%.[Pp][Pp][Tt][Xx]$")
            or config.spec_id or "presentation"
        local path = configured:gsub("{spec_id}", filename)
        if not path:match("^/") and not path:match("^%a:[/\\]") then
            path = (config.project_root or ".") .. "/" .. path
        end
        return path
    end

    local pdf_path = pptx_path:gsub("%.[Pp][Pp][Tt][Xx]$", ".pdf")
    if pdf_path == pptx_path then return pptx_path .. ".pdf" end
    return pdf_path
end

---Export each finalized deck when pptx.export_pdf is enabled.
---@param paths string[] Finalized PPTX output paths
---@param config table Project finalization config
---@param log table Logger
function M.finalize(paths, config, log)
    local pptx_config = (config and config.pptx) or {}
    if not enabled(pptx_config.export_pdf) then return end

    for _, pptx_path in ipairs(paths or {}) do
        local pdf_path = resolve_pdf_path(pptx_path, pptx_config, config or {})
        libreoffice.export_pptx_pdf(pptx_path, pdf_path, log)
    end
end

return M
