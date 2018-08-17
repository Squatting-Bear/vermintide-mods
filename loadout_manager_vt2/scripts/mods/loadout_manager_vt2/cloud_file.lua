--[[
	A class for managing a single file within the Steam cloud service.
	I use this instead of SaveManager to make sure I don't perform
	concurrent operations on the same file.
]]
local CloudFile = class(CloudFile)
CloudFile.init = function(self, mod, filename)
	self.filename = filename
	self.token = nil
	self.on_completed = nil
	self.save_data = nil
	self.is_cancelled = false
	mod:hook_safe(TokenManager, "update", function()
		self:update()
	end)
end
CloudFile.is_idle = function(self)
	return not self.on_completed and not self.save_data
end
CloudFile.load = function(self, callback)
	fassert(self:is_idle(), "Attempt to begin CloudFile operation while already busy")
	self.on_completed = callback
end
CloudFile.save = function(self, data, callback)
	fassert(self:is_idle(), "Attempt to begin CloudFile operation while already busy")
	self.on_completed = callback or (function() end)
	self.save_data = data
end
CloudFile.cancel = function(self)
	-- If an operation is in progress we don't actually cancel it, we just clear
	-- its completion callback, which allows a new operation to be queued.
	self.on_completed = nil
	self.save_data = nil
	self.is_cancelled = not not self.token
end
CloudFile.update = function(self)
	if self.token then
		local progress = Cloud.progress(self.token)
		if progress.done then
			if self.on_completed and not self.is_cancelled then
				self.on_completed(progress)
				self.on_completed = nil
				self.save_data = nil
			end
			Cloud.close(self.token)
			self.token = nil
			self.is_cancelled = false
		end
	end
	if not self.token and self.on_completed then
		if self.save_data then
			self.token = Cloud.auto_save(self.filename, self.save_data)
		else
			self.token = Cloud.auto_load(self.filename)
		end
	end
end

return CloudFile
