---Apply presentation-specific layouts to slides based on SpecIR object types.
---TITLE slides use a section-opener treatment; regular SLIDE types retain the
---standard single-column content layout.

local xml = require("infra.format.xml")

local M = {}

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content)
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

local function slide_tree(doc)
    return xml.find_by_name(doc.root, "p:spTree")[1]
end

local function placeholder(shape)
    local nv = xml.find_child(shape, "p:nvSpPr")
    local nvpr = nv and xml.find_child(nv, "p:nvPr")
    return nvpr and xml.find_child(nvpr, "p:ph") or nil
end

local function node_text(node, out)
    out = out or {}
    if node.type == "text" then
        out[#out + 1] = node.value or ""
    else
        for _, child in ipairs(node.kids or {}) do node_text(child, out) end
    end
    return out
end

local function get_title_shape(tree)
    for _, shape in ipairs(xml.find_children(tree, "p:sp")) do
        local ph = placeholder(shape)
        local kind = ph and xml.get_attr(ph, "type")
        if kind == "title" or kind == "ctrTitle" then return shape end
    end
end

local function get_title(shape)
    local tx = shape and xml.find_child(shape, "p:txBody")
    local paragraph = tx and xml.find_children(tx, "a:p")[1]
    return paragraph and table.concat(node_text(paragraph)) or ""
end

local function unnumbered_title(text)
    return (text or ""):gsub("^%s*%d+%.%s+", "")
end

local function set_rect(shape, rect)
    local sppr = xml.find_child(shape, "p:spPr")
    if not sppr then
        sppr = xml.node("p:spPr")
        xml.add_child(shape, sppr)
    end
    local xfrm = xml.find_child(sppr, "a:xfrm")
    if not xfrm then
        xfrm = xml.node("a:xfrm")
        xml.add_child(sppr, xfrm)
    end
    local off = xml.find_child(xfrm, "a:off")
    if not off then
        off = xml.node("a:off")
        xml.add_child(xfrm, off)
    end
    local ext = xml.find_child(xfrm, "a:ext")
    if not ext then
        ext = xml.node("a:ext")
        xml.add_child(xfrm, ext)
    end
    for key, value in pairs({x = rect.x, y = rect.y}) do
        xml.set_attr(off, key, tostring(value))
    end
    for key, value in pairs({cx = rect.cx, cy = rect.cy}) do
        xml.set_attr(ext, key, tostring(value))
    end
end

local function style_title(title_shape, geometry, style)
    set_rect(title_shape, geometry)
    local tx = xml.find_child(title_shape, "p:txBody")
    for _, paragraph in ipairs(tx and xml.find_children(tx, "a:p") or {}) do
        local ppr = xml.find_child(paragraph, "a:pPr")
        if ppr then xml.set_attr(ppr, "algn", "l") end
        for _, run in ipairs(xml.find_children(paragraph, "a:r")) do
            local rpr = xml.find_child(run, "a:rPr")
            if not rpr then
                rpr = xml.node("a:rPr")
                xml.insert_child(run, rpr, 1)
            end
            xml.set_attr(rpr, "sz", tostring(style.font_size or 4200))
            xml.set_attr(rpr, "b", "1")
            local fill = xml.find_child(rpr, "a:solidFill")
            if not fill then
                fill = xml.node("a:solidFill")
                xml.add_child(rpr, fill)
            end
            local color = xml.find_child(fill, "a:srgbClr")
            if not color then
                color = xml.node("a:srgbClr")
                xml.add_child(fill, color)
            end
            xml.set_attr(color, "val", style.color or "000080")
        end
    end
end

local function accent_shape(shape_id, x, y, cx, cy, color)
    return xml.node("p:sp", {}, {
        xml.node("p:nvSpPr", {}, {
            xml.node("p:cNvPr", {id = tostring(shape_id), name = "SpecCompiler Section Accent"}),
            xml.node("p:cNvSpPr"),
            xml.node("p:nvPr"),
        }),
        xml.node("p:spPr", {}, {
            xml.node("a:xfrm", {}, {
                xml.node("a:off", {x = tostring(x), y = tostring(y)}),
                xml.node("a:ext", {cx = tostring(cx), cy = tostring(cy)}),
            }),
            xml.node("a:prstGeom", {prst = "rect"}, {xml.node("a:avLst")}),
            xml.node("a:solidFill", {}, {xml.node("a:srgbClr", {val = color})}),
            xml.node("a:ln", {}, {xml.node("a:noFill")}),
        }),
    })
end

local function accent_shape_id(tree)
    local max_id = 1
    for _, shape in ipairs(xml.find_by_name(tree, "p:cNvPr")) do
        local id = tonumber(xml.get_attr(shape, "id"))
        if id and id > max_id then max_id = id end
    end
    return max_id + 1
end

local function decorate_title_slide(doc, geometry, title_style)
    local tree = slide_tree(doc)
    if not tree then return false end
    local title = get_title_shape(tree)
    if not title then return false end

    style_title(title, geometry.title or {
        x = 914400, y = 850000, cx = 7315200, cy = 1050000,
    }, title_style)

    local old_accents = {}
    for _, shape in ipairs(xml.find_children(tree, "p:sp")) do
        local nv = xml.find_child(shape, "p:nvSpPr")
        local c_nv = nv and xml.find_child(nv, "p:cNvPr")
        if c_nv and xml.get_attr(c_nv, "name") == "SpecCompiler Section Accent" then
            old_accents[#old_accents + 1] = shape
        end
    end
    for _, shape in ipairs(old_accents) do xml.remove_child(tree, shape) end

    local rail_width = geometry.accent_width or 180000
    local slide_height = geometry.slide_height or 5143500
    xml.insert_child(tree, accent_shape(accent_shape_id(tree), 0, 0, rail_width, slide_height,
        geometry.accent_color or "2563EB"), 3)

    -- Move the content placeholder below the large section title, making this
    -- slide feel like a section opener rather than a regular content slide.
    for _, shape in ipairs(xml.find_children(tree, "p:sp")) do
        local ph = placeholder(shape)
        if ph and xml.get_attr(ph, "idx") == "1" then
            set_rect(shape, geometry.body or {
                x = 914400, y = 2250000, cx = 7315200, cy = 2200000,
            })
            break
        end
    end
    return true
end

local function title_types(db_path)
    local titles = {}
    if not db_path then return titles end
    local ok, sqlite = pcall(require, "lsqlite3")
    if not ok then return titles end
    local db = sqlite.open(db_path)
    if not db then return titles end
    for row in db:nrows("SELECT title_text FROM spec_objects WHERE type_ref = 'TITLE'") do
        titles[row.title_text] = true
    end
    db:close()
    return titles
end

---Apply title/section-opener style to slides whose heading is a TITLE object.
---@param extract_dir string Extracted PPTX package directory
---@param slide_targets string[] Ordered slide filenames
---@param db_path string|nil SpecIR database path
---@param style table Geometry and visual style from PPTX preset
---@param log table Logger
---@return boolean success
function M.apply(extract_dir, slide_targets, db_path, config, log)
    config = config or {}
    local titles = title_types(db_path)
    if not next(titles) then return true end
    local geometry = config.title_slide or {}
    local title_style = config.title or {}

    for _, target in ipairs(slide_targets or {}) do
        local path = extract_dir .. "/ppt/slides/" .. target
        local content = read_file(path)
        local doc = content and xml.parse(content)
        local tree = doc and doc.root and slide_tree(doc)
        local title = tree and get_title_shape(tree)
        local text = get_title(title)
        if titles[unnumbered_title(text)] and decorate_title_slide(doc, geometry, title_style) then
            if not write_file(path, xml.serialize(doc)) then
                return false, "Could not write TITLE slide: " .. path
            end
            if log then log.debug("[PPTX-POST] Applied section-opener layout to TITLE slide: %s", text) end
        end
    end
    return true
end

return M
