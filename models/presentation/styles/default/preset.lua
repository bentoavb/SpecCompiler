---Technical presentation theme preset.
---The PPTX reference deck contains masters and layouts; this preset applies
---the model's theme and reusable content-layout defaults to a generated copy.

return {
    name = "Presentation Default",
    description = "Single-column technical presentation with a blue accent palette",
    reference_doc = "styles/default/reference.pptx",

    pptx = {
        theme = {
            colors = {
                dk1 = "000080",
                lt1 = "F8FAFC",
                dk2 = "000080",
                lt2 = "E6EEF7",
                accent1 = "2563EB",
                accent2 = "06B6D4",
                accent3 = "14B8A6",
                accent4 = "F59E0B",
                accent5 = "7C3AED",
                accent6 = "475569",
                hlink = "2563EB",
                folHlink = "7C3AED",
            },
            fonts = {
                majorFont = "Aptos Display",
                minorFont = "Aptos",
            },
        },
        body = {
            font_size = 1900,
            space_before_pct = 0,
            line_height = 1.2,
            max_chars_per_line = 100,
        },
        title = {
            font_size = 3000,
            color = "000080",
            bold = true,
            alignment = "ctr",
        },
        content_layout = {
            body_index = 2,
            visual_index = 1,
            title = {x = 457200, y = 205979, cx = 8229600, cy = 857250},
            body = {x = 457200, y = 1076326, cx = 8229600, cy = 3600000},
            visual = {x = 457200, y = 2700000, cx = 8229600, cy = 1600000},
            visual_gap = 120000,
            slide_height = 5143500,
            bottom_margin = 200000,
        },
    },
}
