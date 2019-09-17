local Managers = Managers
local OptionsView = OptionsView
local UIRenderer = UIRenderer
local callback = callback

local BUTTON_TYPE = "casual_button"

local function make_button(button_name, scenegraph_id, texture_id, offset, size, tooltip)
	-- First, compute dimensions for the icon such that it will fit within
	-- the given size with a 15% margin.
	local icon_size = UIAtlasHelper.get_atlas_settings_by_texture_name(texture_id).size
	local room_x = size[1] * 0.85
	local room_y = size[2] * 0.85
	local ratio = math.min((room_x / icon_size[1]), (room_y / icon_size[2]))
	icon_size = { math.floor(icon_size[1] * ratio), math.floor(icon_size[2] * ratio) }

	return {
		element = {
			passes = {
				{
					pass_type = "hotspot",
					content_id = "highlight_hotspot",
					style_id = "button_hotspot",
				},
				{
					pass_type = "rect",
					style_id = "background_rect",
				},
				{
					pass_type = "texture",
					texture_id = "texture_id",
					style_id = "texture_id",
				},
				{
					pass_type = "texture",
					texture_id = "texture_hover_id",
					style_id = "texture_hover_id",
					content_check_function = function (content)
						return content.highlight_hotspot.is_hover
					end,
				},
				{
					pass_type = "texture",
					texture_id = "texture_click_id",
					style_id = "texture_click_id",
					content_check_function = function (content)
						return content.highlight_hotspot.is_clicked == 0
					end,
				},
				{
					pass_type = "texture",
					texture_id = "texture_frame_id",
					style_id = "texture_frame_id",
				},
				{
					pass_type = "tooltip_text",
					style_id = "tooltip_text",
					text_id = "tooltip_text",
					content_check_function = function (content)
						local button_hotspot = content.highlight_hotspot
						return content.tooltip_text and button_hotspot.is_hover and button_hotspot.is_clicked ~= 0
					end
				},
			},
		},
		content = {
			highlight_hotspot = {},
			texture_id = texture_id,
			texture_hover_id = "button_state_default",
			texture_click_id = "button_state_default_2",
			texture_frame_id = "button_frame_02",
			tooltip_text = tooltip,
		},
		style = {
			button_hotspot ={
				size = size,
			},
			background_rect = {
				color = { 25, 210, 105, 30 },
				offset = { 0, 0, 0 },
				size = size,
			},
			texture_id = {
				color = { 255, 255, 255, 255 },
				offset = { ((size[1] - icon_size[1]) / 2), ((size[2] - icon_size[2]) / 2), 4 },
				size = icon_size,
			},
			texture_hover_id = {
				color = { 255, 255, 255, 255 },
				offset = { 0, 0, 2 },
				size = { size[1], (size[2] * 1.25) },
			},
			texture_click_id = {
				color = { 255, 255, 255, 255 },
				offset = { 0, 0, 2 },
				size = { size[1], (size[2] * 1.25) },
			},
			texture_frame_id = {
				color = { 255, 255, 255, 255 },
				offset = { 0, 0, 3 },
				size = size,
			},
			tooltip_text = {
				font_size = 24,
				max_width = 500,
				font_type = "hell_shark",
				text_color = Colors.get_color_table_with_alpha("white", 255),
				line_colors = {
					Colors.get_color_table_with_alpha("font_title", 255),
				},
			},
		},
		scenegraph_id = scenegraph_id,
		offset = offset,
	}
end

-- A class that manages widgets we create and insert into fatshark's UI.  It
-- borrows code for stepper widgets from the OptionsView class.
local ExtraWidgetsManager = class()

ExtraWidgetsManager.init = function(self, wwise_world)
	self.wwise_world = wwise_world
	OptionsView._setup_input_functions(self)
	self._input_functions[BUTTON_TYPE] = function(widget, input_source, dt)
		if widget.content.highlight_hotspot.on_release then
			WwiseWorld.trigger_event(self.wwise_world, "Play_hud_select")
			widget.content.callback(widget.content)
		end
	end
	self._widgets = {}
	self._active_popups = {}
end

-- These functions comprise the stepper widget implementation from OptionsView.
ExtraWidgetsManager.build_stepper_widget = OptionsView.build_stepper_widget
ExtraWidgetsManager.animate_element_by_time = OptionsView.animate_element_by_time
ExtraWidgetsManager.on_stepper_arrow_hover = OptionsView.on_stepper_arrow_hover
ExtraWidgetsManager.on_stepper_arrow_dehover = OptionsView.on_stepper_arrow_dehover
ExtraWidgetsManager.handle_mouse_widget_input = OptionsView.handle_mouse_widget_input
ExtraWidgetsManager.make_callback = callback
ExtraWidgetsManager.cb_not_used_saved_value = function() end

-- Returns the widget with the given name.
ExtraWidgetsManager.get_widget = function(self, widget_name)
	return self._widgets[widget_name]
end

-- Adds a stepper widget with the given name to the given scenegraph node.
ExtraWidgetsManager.add_stepper_widget = function(self, stepper_name, scenegraph_id, y_offset)
	local stepper_definition = {
		name = stepper_name,
		widget_type = "stepper",
		setup = ("cb_" .. stepper_name .. "_setup"),
		callback = ("cb_" .. stepper_name),
		-- We need to set this (even though we don't use that event) or build_stepper_widget barfs.
		saved_value = "cb_not_used_saved_value",
	}
	
	local stepper_widget = self:build_stepper_widget(stepper_definition, scenegraph_id, { -840, y_offset, 0 })
	stepper_widget.type = stepper_definition.widget_type
	stepper_widget.name = stepper_name
	stepper_widget.ui_animations = {}

	-- Set the tooltip if there is a callback for doing so.
	local tooltip_callback = self["cb_" .. stepper_name .. "_set_tooltip"]
	if tooltip_callback then
		tooltip_callback(self, stepper_widget.content)
	end
	
	-- Fix up a few things that aren't quite how we want them.  For a start, we just
	-- want the actual stepper, not the text label to the left of it, so restrict the
	-- visible area (and hotspot) to the stepper.
	local style = stepper_widget.style
	local visible_area_size = style.input_field_background.size
	local visible_area_offset = style.input_field_background.offset
	style.highlight_hotspot = {
		size = table.clone(visible_area_size),
		offset = table.clone(visible_area_offset),
	}
	for i, pass in ipairs(stepper_widget.element.passes) do
		if pass.content_id == "highlight_hotspot" then
			pass.style_id = "highlight_hotspot"
		elseif pass.text_id == "tooltip_text" then
			pass.style_id = "tooltip_text"
			-- Prevent the tooltip being automatically treated as a localization id instead
			-- of text.  This expression seems pretty fragile - it might not be worth the
			-- trouble if it keeps breaking (without it you just get angle brackets around
			-- the tooltip text, which I could live with).
			stepper_widget.element.pass_data[i].passes[1].data.style.title_text.localize = false
		end
	end

	-- This offset needs fixing, don't know why.
	local wonky_offset = style.selection_text.offset
	wonky_offset[1] = wonky_offset[1] - 260

	self._widgets[stepper_name] = stepper_widget

	-- Define a mask texture covering just the area we want to be visible.
	local mask_def = {
		scenegraph_id = scenegraph_id,
		element = UIElements.SimpleTexture,
		content = {
			texture_id = "mask_rect",
		},
		style = {
			offset = table.clone(visible_area_offset),
			size = table.clone(visible_area_size),
			color = { 255, 255, 255, 255 },
		},
	}
	local mask_widget = UIWidget.init(mask_def)
	self._widgets[stepper_name .. "_mask"] = mask_widget
end

-- Removes the stepper with the given name.
ExtraWidgetsManager.remove_stepper_widget = function(self, stepper_name)
	self._widgets[stepper_name] = nil
	self._widgets[stepper_name .. "_mask"] = nil
end

-- Adds a simple image button to the given scenegraph node.
ExtraWidgetsManager.add_button_widget = function(self, button_name, scenegraph_id, texture_id, offset, size, tooltip)
	local button_definition = make_button(button_name, scenegraph_id, texture_id, offset, size, tooltip)
	local button_widget = UIWidget.init(button_definition)

	button_widget.type = BUTTON_TYPE
	button_widget.name = button_name
	button_widget.content.callback = callback(self, "cb_" .. button_name)
	self._widgets[button_name] = button_widget
end

-- Removes the button with the given name.
ExtraWidgetsManager.remove_button_widget = function(self, button_name)
	self._widgets[button_name] = nil
end

-- Shows a popup with given name and other arguments as per Managers.popup:queue_popup.
ExtraWidgetsManager.show_popup = function(self, popup_name, ...)
	fassert(not self._active_popups[popup_name], "Popup '%s' already showing", popup_name)
	self._active_popups[popup_name] = Managers.popup:queue_popup(...)
end

-- Draws our widgets and handles any relevant user input.
ExtraWidgetsManager.update = function(self, dt, ui_top_renderer, ui_scenegraph, input_service, render_settings)
	UIRenderer.begin_pass(ui_top_renderer, ui_scenegraph, input_service, dt, nil, render_settings)

	for _, widget in pairs(self._widgets) do
		if widget.ui_animations then
			for name, animation in pairs(widget.ui_animations) do
				UIAnimation.update(animation, dt)
				if UIAnimation.completed(animation) then
					widget.ui_animations[name] = nil
				end
			end
		end

		UIRenderer.draw_widget(ui_top_renderer, widget)

		local hotspot = widget.content.highlight_hotspot
		if hotspot and hotspot.is_hover then
			self:handle_mouse_widget_input(widget, input_service, dt)
		end
	end

	UIRenderer.end_pass(ui_top_renderer)

	self:handle_input(dt)
end

-- Handles any user input relevant to our widgets.
ExtraWidgetsManager.handle_input = function(self, dt)
	for popup_name, popup_id in pairs(self._active_popups) do
		local result = Managers.popup:query_result(popup_id)
		if result then
			Managers.popup:cancel_popup(popup_id)
			self._active_popups[popup_name] = nil
			local callback_name = ("cb_" .. popup_name)
			self[callback_name](self, result)
		end
	end
end

return ExtraWidgetsManager
