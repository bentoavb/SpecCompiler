---Add explicit, sequential slide-number shapes to a PPTX package.
---Numbers are applied in presentation order after layout/overflow processing.

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

local function get_slide_tree(doc)
    return xml.find_by_name(doc.root, "p:spTree")[1]
end

local function slide_number_shape(number, shape_id, style)
    local x = style.x or 8534400
    local y = style.y or 4740000
    local cx = style.cx or 350000
    local cy = style.cy or 250000
    local font_size = style.font_size or 1000
    local color = style.color or "475569"
    return xml.node("p:sp", {}, {
        xml.node("p:nvSpPr", {}, {
            xml.node("p:cNvPr", {id = tostring(shape_id), name = "SpecCompiler Slide Number"}),
            xml.node("p:cNvSpPr", {txBox = "1"}),
            xml.node("p:nvPr"),
        }),
        xml.node("p:spPr", {}, {
            xml.node("a:xfrm", {}, {
                xml.node("a:off", {x = tostring(x), y = tostring(y)}),
                xml.node("a:ext", {cx = tostring(cx), cy = tostring(cy)}),
            }),
            xml.node("a:prstGeom", {prst = "rect"}, {xml.node("a:avLst")}),
            xml.node("a:noFill"),
            xml.node("a:ln", {}, {xml.node("a:noFill")}),
        }),
        xml.node("p:txBody", {}, {
            xml.node("a:bodyPr", {wrap = "none", anchor = "ctr", lIns = "0", tIns = "0", rIns = "0", bIns = "0"}),
            xml.node("a:lstStyle"),
            xml.node("a:p", {}, {
                xml.node("a:pPr", {algn = "r"}, {xml.node("a:buNone")}),
                xml.node("a:r", {}, {
                    xml.node("a:rPr", {lang = "en-US", sz = tostring(font_size)}, {
                        xml.node("a:solidFill", {}, {xml.node("a:srgbClr", {val = color})}),
                    }),
                    xml.node("a:t", {}, {xml.text(tostring(number))}),
                }),
                xml.node("a:endParaRPr", {lang = "en-US", sz = tostring(font_size)}),
            }),
        }),
    })
end

local function number_slide(slide_path, number, style)
    local content = read_file(slide_path)
    if not content then return false, "Could not read slide: " .. slide_path end
    local doc = xml.parse(content)
    if not doc or not doc.root then return false, "Could not parse slide: " .. slide_path end
    local tree = get_slide_tree(doc)
    if not tree then return false, "Slide has no shape tree: " .. slide_path end

    local max_id = 1
    local old_numbers = {}
    for _, properties in ipairs(xml.find_by_name(tree, "p:cNvPr")) do
        local id = tonumber(xml.get_attr(properties, "id"))
        if id and id > max_id then max_id = id end
        if xml.get_attr(properties, "name") == "SpecCompiler Slide Number" then
            local shape = properties.parent and properties.parent.parent
            if shape then old_numbers[#old_numbers + 1] = shape end
        end
    end
    for _, shape in ipairs(old_numbers) do
        xml.remove_child(tree, shape)
    end

    xml.add_child(tree, slide_number_shape(number, max_id + 1, style))
    if not write_file(slide_path, xml.serialize(doc)) then
        return false, "Could not write slide: " .. slide_path
    end
    return true
end

---Add/update slide numbers in the final visible slide order.
---@param extract_dir string Extracted PPTX package directory
---@param slide_targets string[] Ordered slide filenames (e.g. slide1.xml)
---@param style table Position and text styling from the presentation preset
---@return boolean success
---@return string|nil error
function M.apply(extract_dir, slide_targets, style)
    for number, target in ipairs(slide_targets or {}) do
        local slide_path = extract_dir .. "/ppt/slides/" .. target
        local ok, err = number_slide(slide_path, number, style or {})
        if not ok then return false, err end
    end
    return true
end

return M
