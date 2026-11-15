---Pandoc Lua filter for PowerPoint output from the presentation model.
---Pandoc's PPTX writer omits table blocks nested inside Div containers, so
---unwrap SpecCompiler's semantic table wrapper. Also remove float captions:
---Pandoc assigns each block to a slide-layout placeholder, which can put a
---caption in one column and its table/image in another. Use the section header
---as the slide title instead.

return {{
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
