local NumTalentColumns = NumTalentColumns
local NumTalentRows = NumTalentRows

-- Returns an item grid widget which supports showing a lock icon
-- on items that are locked according to our progression.
local function make_hacked_item_grid_widget()
	local definitions = local_require("scripts/ui/views/hero_view/windows/definitions/hero_window_inventory_definitions")

	local item_grid_widget = table.clone(definitions.widgets.item_grid)
	local passes = item_grid_widget.element.passes
	local content = item_grid_widget.content
	local style = item_grid_widget.style
	local rows = content.rows
	local columns = content.columns

	for i = 1, rows, 1 do
		for k = 1, columns, 1 do
			local name_suffix = "_" .. tostring(i) .. "_" .. tostring(k)
			local disabled_name = "disabled_rect" .. name_suffix
			local item_name = "item" .. name_suffix
			local content_check_function = function(ui_content)
				local item = ui_content[item_name]
				return item and item.is_casual_locked
			end

			passes[#passes + 1] = {
				pass_type = "rect",
				style_id = disabled_name,
				content_check_function = content_check_function,
			}

			local offset = style[disabled_name].offset
			local casual_locked_icon_name = "casual_locked_icon" .. name_suffix
			passes[#passes + 1] = {
				pass_type = "texture",
				texture_id = casual_locked_icon_name,
				style_id = casual_locked_icon_name,
				content_check_function = content_check_function,
			}
			content[casual_locked_icon_name] = "locked_icon_01"
			style[casual_locked_icon_name] = {
				size = { 20, 25 },
				color = { 255, 255, 255, 255 },
				offset = { (offset[1] + 12), (offset[2] + 12), (offset[3] + 1) },
			}
		end
	end

	return UIWidget.init(item_grid_widget)
end

-- Modifies the talent_row widgets in the given widget collections by
-- adding a lock icon shown on talents that are locked according
-- to our progression.
local function add_lock_buttons_to_talents(widgets, widgets_by_name)
	local definitions = local_require("scripts/ui/views/hero_view/windows/definitions/hero_window_talents_definitions")

	for i = 1, NumTalentRows, 1 do
		local talent_row_name = ("talent_row_" .. i)
		local talent_row_def = table.clone(definitions.widgets[talent_row_name])
		local passes = talent_row_def.element.passes
		local content = talent_row_def.content
		local style = talent_row_def.style
	
		for j = 1, NumTalentColumns, 1 do
			local name_suffix = ("_" .. j)
			local hotspot_name = ("hotspot" .. name_suffix)
			local frame_name = ("frame" .. name_suffix)
			local button_offset = style[frame_name].offset
			local button_size = style[frame_name].size
			local icon_size = { 30, 38 }
			local x_offset = button_offset[1] + ((button_size[1] - icon_size[1]) / 2)
			local y_offset = button_offset[2] + ((button_size[2] - icon_size[2]) / 2)
			local casual_locked_icon_name = "casual_locked_icon" .. name_suffix

			passes[#passes + 1] = {
				pass_type = "texture",
				texture_id = casual_locked_icon_name,
				style_id = casual_locked_icon_name,
				content_check_function = function(content)
					return content[hotspot_name].disabled
				end,
			}
			content[casual_locked_icon_name] = "locked_icon_01"
			style[casual_locked_icon_name] = {
				size = icon_size,
				color = { 255, 255, 255, 255 },
				offset = { x_offset, y_offset, 10 },
			}
		end
 
		local talent_row = UIWidget.init(talent_row_def)
		widgets[table.index_of(widgets, widgets_by_name[talent_row_name])] = talent_row
		widgets_by_name[talent_row_name] = talent_row
	end
end

return {
	make_hacked_item_grid_widget = make_hacked_item_grid_widget,
	add_lock_buttons_to_talents = add_lock_buttons_to_talents,
}
