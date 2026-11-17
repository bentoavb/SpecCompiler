---Pandoc Lua filter for PowerPoint output from the presentation model.
---Pandoc's PPTX writer omits table blocks nested inside Div containers, so
---unwrap SpecCompiler's semantic table wrapper. Also remove float captions:
---Pandoc assigns each block to a slide-layout placeholder, which can put a
---caption in one column and its table/image in another. Use the section header
---as the slide title instead.

local figure_size = require("models.presentation.shared.figure_size")

return {{
    Image = function(image)
        local width, height = image.attributes.width, image.attributes.height
        if width or height then
            local marker = string.format("[[speccompiler-size:%s,%s]]",
                figure_size.normalize(width), figure_size.normalize(height))
            image.title = marker .. " " .. image.title
        end
        return image
    end,
    Div = function(div)
        for _, class in ipairs(div.classes or {}) do
            if class == "speccompiler-table" then
                return div.content
            elseif class == "speccompiler-caption" then
                return {}
            end
        end
        return div
    end,
}}
