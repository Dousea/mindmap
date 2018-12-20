local moonshine = require 'moonshine'
local gate_open, end_game
local font
local player
local map
local memory
local text, queue_text
local gate_sound, memory_sound, ambient
local chromasep, effect
local draw_screen, draw_memory

local function math_dist(x1, y1, x2, y2)
	return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function file_read(file, bytes)
	local byte = {file:read(bytes):byte(1, bytes)}
	local value = 0
	
	for i = 1, #byte do
		value = value + byte[i] * 2 ^ ((i - 1) * 8)
	end
	
	return value
end

function love.load()
	font = {}
	
	for size = 8, 72, 4 do
		font[size] = love.graphics.newFont('consola.ttf', size)
	end
	
	player = {}
	player.x, player.y = 1, 1
	player.fovradius = 9
	player.keytimer = 0
	player.reminderavail = true
	player.reminder = {
		'Something nearby.',
		'There\'s something around here.',
		'It\'s around here somewhere.',
		'Something here.'
	}
	
	end_game = {}
	end_game.status = false
	end_game.timer = 10 -- in seconds
	end_game.imagescale = 1
	end_game.image = love.graphics.newImage 'memory.png'
	
	memory = {}
	memory.hintalpha = 0
	memory.curi = 1
	memory.text = {
		'I remember...',
		'This place is...',
		'Seems I...',
		'It resembles...',
		'This is...'
	}
	memory.avail = {}
	
	map = {}
	
	do
		local file = assert(love.filesystem.newFile('map', 'r'))
		--[=[
		2BYTE	width
		2BYTE	height
		for x = 1, width do
			for y = 1, height do
				1BYTE	type of tile
						0  = floor, 1 = wall
						10 = door
						20 = spawnpoint
						30 = memory
				if type of tile == 1
					1BYTE	red
					1BYTE	green
					1BYTE	blue
		]=]
		local width, height = file_read(file, 2), file_read(file, 2)
		
		for x = 1, width do
			for y = 1, height do
				local type = file_read(file, 1)
				map[x] = map[x] or {}
				map[x][y] = { type = type }
				
				if type == 20 then
					player.x, player.y = x, y
				elseif type == 30 then
					memory.avail[x] = memory.avail[x] or {}
					memory.avail[x][y] = true
				elseif type == 1 then
					map[x][y].color = {
						file_read(file, 1) / 255,
						file_read(file, 1) / 255,
						file_read(file, 1) / 255
					}
				end
			end
		end
		
		file:close()
	end
	
	text = {}
	text.time = -1
	text.queue = {}
	text.object = love.graphics.newText(font[24], '')
	
	-- durtion: duration to show (in seconds)
	-- string: text to show
	function queue_text(duration, string, force)
		-- shift current texts to the right
		-- [1][2][3][4]... -> [ ][1][2][3]...
		if #text.queue > 0 then
			for i = #text.queue, 1 do
				text.queue[i + 1] = text.queue[i]
			end
		end
		
		local i = force and (#text.queue > 0 and #text.queue or 1) or 1
		text.queue[i] = {
			duration,
			string
		}
		
		if #text.queue == 1 or force then
			text.time = duration
			
			text.object:setf(string, love.graphics.getWidth(), 'center')
		end
	end
	
	ambient = love.audio.newSource('ambient.mp3', 'stream')
	memory_sound = love.audio.newSource('memory.wav', 'static')
	gate_sound = love.audio.newSource('gate.wav', 'static')
	
	ambient:play()
	ambient:setLooping(true)
	
	effect = {}
	effect.screen = {}
	effect.memory = {}
	
	-- duration: duration to show (in seconds)
	-- angle: starting angle
	-- radius: starting radius
	function chromasep(duration, angle, angularvel, radius)
		effect.screen.time = duration
		effect.screen.angle = angle
		effect.screen.angularvel = angularvel
		effect.screen.radius = radius
		effect.screen.radiuspertime = radius / duration
	end
	
	chromasep(3, 30, 90, 10)
	
	effect.screen.effect = moonshine(moonshine.effects.chromasep)
	effect.screen.effect.chromasep.angle = math.rad(effect.screen.angle)
	effect.screen.effect.chromasep.radius = effect.screen.radius
	
	effect.memory.effect = moonshine(moonshine.effects.glow)
	effect.memory.x, effect.memory.y = 0, 0
	
	function draw_memory()
		love.graphics.rectangle('fill', effect.memory.x, effect.memory.y, 16, 16)
	end
	
	function draw_screen()
		if end_game.status then
			love.graphics.draw(end_game.image,
				love.graphics.getWidth() / 2, love.graphics.getHeight() / 2, 0,
				end_game.imagescale, end_game.imagescale, end_game.image:getWidth() / 2, end_game.image:getHeight() / 2)
			
			return
		end
		
		for x = player.x - 19, player.x + 19 do
			if map[x] then
				for y = player.y - 15, player.y + 15 do
					if map[x][y] then
						local type = map[x][y].type
						if type == 1 or (type == 10 and not gate_open) or type == 30 then
							local dist = math_dist(x,  y, player.x, player.y)
							
							if dist < player.fovradius then
								local a = 1
								dist = math.floor(dist)
								
								if dist == player.fovradius - 1 then
									a = .25
								elseif dist == player.fovradius - 2 then
									a = .5
								elseif dist == player.fovradius - 3 then
									a = .75
								end
								
								if type == 1 or type == 10 then
									local r, g, b
									
									if type == 1 then
										r, g, b = unpack(map[x][y].color)
									else
										r, g, b = 1, 1, 0
									end
									
									love.graphics.setColor(r, g, b, a)
									love.graphics.rectangle('fill', (x - player.x + 19) * 16, (y - player.y + 15) * 16, 16, 16)
								else
									if memory.avail[x] and memory.avail[x][y] ~= nil then
										effect.memory.x, effect.memory.y = (x - player.x + 19) * 16, (y - player.y + 15) * 16
										
										if memory.avail[x][y] then
											love.graphics.setColor(1, 1, 1, a)
											effect.memory.effect(draw_memory)
										else
											love.graphics.setColor(.5, .5, .5, a)
											draw_memory()
										end
									end
								end
							end
						end
					end
				end
			end
		end
		
		do
			local memx, memy, dist
			
			for x in pairs(memory.avail) do
				for y in pairs(memory.avail[x]) do
					if memory.avail[x][y] then
						local curdist = math_dist(x, y, player.x, player.y)
						
						if not dist or curdist < dist then
							dist = curdist
							memx, memy = x, y
						end
					end
				end
			end
			
			if dist then
				local hintx, hinty = 0, 0
				
				if memx < player.x - 19 then
					hintx = 0
				elseif memx > player.x + 19 then
					hintx = 38
				else
					hintx = memx - player.x + 19
				end
				
				if memy < player.y - 15 then
					hinty = 0
				elseif memy > player.y + 15 then
					hinty = 30
				else
					hinty = memx - player.y + 15
				end
				
				love.graphics.setColor(1, 1, 1, memory.hintalpha)
				love.graphics.rectangle('fill', hintx * 16, hinty * 16, 16, 16)
			end
		end
		
		love.graphics.setColor(1, 0, 1, 1)
		love.graphics.rectangle('fill', 304, 240, 16, 16)
		
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(text.object, 0, love.graphics.getHeight() * .75)
	end
end

function love.update(dt)
	if effect.screen.time > 0 then
		effect.screen.time = effect.screen.time - dt
		effect.screen.angle = effect.screen.angle + effect.screen.angularvel * dt
		effect.screen.radius = effect.screen.radius - effect.screen.radiuspertime * dt
		effect.screen.effect.chromasep.angle = math.rad(effect.screen.angle)
		effect.screen.effect.chromasep.radius = effect.screen.radius
	end
	
	if end_game.status then
		if end_game.timer > 0 then
			end_game.timer = end_game.timer - dt
			end_game.imagescale = end_game.imagescale - 0.01 * dt
		else
			love.event.quit()
		end
		
		return
	end
	
	do
		local up, down = love.keyboard.isDown 'up', love.keyboard.isDown 'down'
		local left, right = love.keyboard.isDown 'left', love.keyboard.isDown 'right'
		
		if up or down or left or right then
			if player.keytimer > 0 then
				player.keytimer = player.keytimer - dt
			else
				player.keytimer = .1
				local dirx, diry = 0, 0
				
				if up then
					diry = -1
				elseif down then
					diry = 1
				elseif left then
					dirx = -1
				else
					dirx = 1
				end
				
				local new_x, new_y = player.x + dirx, player.y + diry
				
				if map[new_x] and map[new_x][new_y] then
					local type = map[new_x][new_y].type
					
					if type == 0 or (type == 10 and gate_open) or type == 30 then
						player.x, player.y = new_x, new_y
						
						if type == 10 then
							end_game.status = true
							
							chromasep(10, 0, 135, 100)
						elseif type == 30 and memory.avail[new_x][new_y] then	
							player.fovradius = player.fovradius + 1
							
							chromasep(2.5, 0, 135, 50)
							
							if memory.curi == 5 then
								gate_sound:play()
								queue_text(5, 'There\'s a gate opening.')
								
								gate_open = true
							else
								memory_sound:play()
								queue_text(5, memory.text[memory.curi], true)
								queue_text(5, 'I need to collect ' .. (5 - memory.curi) .. ' more.')
							end
							
							memory.curi = memory.curi + 1
							memory.avail[new_x][new_y] = false
							memory.hintalpha = 0
						end
					end
				end
			end
		end
	end
	
	do
		local dist
		
		for x in pairs(memory.avail) do
			for y in pairs(memory.avail[x]) do
				if memory.avail[x][y] then
					local curdist = math_dist(x, y, player.x, player.y)
					
					if not dist or curdist < dist then
						dist = curdist
					end
				end
			end
		end
		
		if dist then
			if dist > 30 then
				if not player.reminderavail then
					player.reminderavail = true
				end
			else
				if player.reminderavail then
					player.reminderavail = false
					
					queue_text(5, player.reminder[love.math.random(1, 4)], true)
				end
			end
		end
	end
	
	if #text.queue > 0 and text.time > 0 then
		text.time = text.time - dt
	else
		text.time = -1
		text.queue[#text.queue] = nil
		
		if #text.queue > 0 then
			local queue = text.queue[#text.queue]
			text.time = queue[1]
			
			text.object:setf(queue[2], love.graphics.getWidth(), 'center')
		else
			text.object:setf('', 0, 'center')
		end
	end
	
	if memory.curi < 5 and memory.hintalpha < .75 then
		memory.hintalpha = memory.hintalpha + 0.004 * dt
	end
end

function love.draw()
	effect.screen.effect(draw_screen)
end