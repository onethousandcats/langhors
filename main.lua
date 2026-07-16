-- main.lua

local bump = require("lib.bump")
local StateMachine = require("state_machine")

local world

local horse = {
    x = 100, y = 300,
    w = 20, h = 20,
    vx = 0, vy = 0,
    facing = 1
}

-- Level layout as a flat list of solid rectangles. Everything in here gets
-- added to the bump world and drawn the same way, so growing the level from
-- here is just adding entries -- no new named variables needed.
--
-- Rough layout (world x-coordinates):
--   0-400     starting floor
--   400-550   a pit (tests falling + coyote time if you sprint off the edge)
--   550-1000  floor continues, with a floating platform above it
--   1000-1180 a wall-jump corridor: two facing walls with a gap between
--   1204+     floor continues into a staircase of rising platforms
local platforms = {
    { x = 0,    y = 500, w = 400,  h = 40 },  -- starting floor
    { x = 550,  y = 500, w = 450,  h = 40 },  -- floor after the pit
    { x = 650,  y = 380, w = 150,  h = 20 },  -- floating platform to jump onto

    { x = 1000, y = 200, w = 24,   h = 200 }, -- wall-jump corridor: left wall
    { x = 1180, y = 200, w = 24,   h = 300 }, -- wall-jump corridor: right wall
    { x = 1000, y = 500, w = 204,  h = 40 },  -- floor beneath the corridor

    { x = 1204, y = 500, w = 1000, h = 40 },  -- floor continues after corridor
    { x = 1400, y = 420, w = 120,  h = 20 },  -- staircase step 1
    { x = 1600, y = 340, w = 120,  h = 20 },  -- staircase step 2
    { x = 1800, y = 260, w = 120,  h = 20 },  -- staircase step 3 (top)
}

local GRAVITY = 1400
local MOVE_SPEED = 400
local JUMP_VELOCITY = -520
local WALL_SLIDE_MAX_SPEED = 120
local WALL_JUMP_VELOCITY_X = 340
local WALL_JUMP_VELOCITY_Y = -480
local SLIDE_SPEED = 500
local SLIDE_DURATION = 0.4
local COYOTE_TIME = 0.1
local JUMP_BUFFER_TIME = 0.12

local camera = { x = 0, y = 0 }
local CAMERA_SMOOTH = 6

local grounded = false
local wallDir = 0 -- -1 for left wall, 1 for right wall, 0 for no wall

local coyoteTimer = 0
local jumpBufferTimer = 0

local function applyHorizontalInput()
    horse.vx = 0
    if love.keyboard.isDown("left", "a") then
        horse.vx = -MOVE_SPEED
        horse.facing = -1
    elseif love.keyboard.isDown("right", "d") then
        horse.vx = MOVE_SPEED
        horse.facing = 1
    end
end

local function moveAndCollide(dt)
    local goalX = horse.x + horse.vx * dt
    local goalY = horse.y + horse.vy * dt

    local actualX, actualY, cols, len = world:move(horse, goalX, goalY, function ()
        return "slide"
    end)
    horse.x, horse.y = actualX, actualY

    grounded = false
    wallDir = 0
    for i = 1, len do
        local col = cols[i]
        if col.normal.y == -1 then
            grounded = true
            horse.vy = 0
        end
        if col.normal.x == 1 then wallDir = -1 -- wall's surface faces right, meaning it's to our LEFT
        elseif col.normal.x == -1 then wallDir = 1 end
    end
end

local function wantsJump()
    return jumpBufferTimer > 0
end

local function consumeJump()
    jumpBufferTimer = 0
end


local states = {
    idle = {
        update = function(dt, sm)
            applyHorizontalInput()
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)
            if not grounded then
                sm:change("fall")
            elseif wantsJump() then
                consumeJump()
                sm:change("jump")
            elseif love.keyboard.isDown("down", "s") then
                sm:change("slide")
            elseif horse.vx ~= 0 then
                sm:change("run")
            end
        end
    },
    run = {
        update = function(dt, sm)
            applyHorizontalInput()
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)
            if not grounded then
                sm:change("fall")
            elseif wantsJump() then
                consumeJump()
                sm:change("jump")
            elseif love.keyboard.isDown("down", "s") then
                sm:change("slide")
            elseif horse.vx == 0 then
                sm:change("idle")
            end
        end
    },
    jump = {
        enter = function()
            horse.vy = JUMP_VELOCITY
        end,
        update = function(dt, sm)
            applyHorizontalInput()
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)
            if horse.vy >= 0 then
                sm:change("fall")
            end
        end
    },

    fall = {
        update = function(dt, sm)
            applyHorizontalInput()
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)
            if grounded then
                sm:change(horse.vx == 0 and "idle" or "run")
            elseif wallDir ~= 0 and horse.vy > 0 then
                sm:change("wallslide")
            elseif wantsJump() and coyoteTimer > 0 then
                consumeJump()
                coyoteTimer = 0
                sm:change("jump")
            end
        end
    },

    wallslide = {
        update = function(dt, sm)
            horse.vy = math.min(horse.vy + GRAVITY * dt, WALL_SLIDE_MAX_SPEED)
            moveAndCollide(dt)

            if grounded then
                sm:change("idle")
            elseif wallDir == 0 then
                sm:change("fall")
            elseif wantsJump() then
                consumeJump()
                sm:change("walljump")
            end
        end
    },

    walljump = {
        enter = function()
            horse.vx = -wallDir * WALL_JUMP_VELOCITY_X
            horse.vy = WALL_JUMP_VELOCITY_Y
            horse.facing = -wallDir
        end,
        update = function(dt, sm)
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)
            if horse.vy >= 0 then
                sm:change("fall")
            end
        end
    },

    slide = {
        enter = function(_, _, sm)
            horse.vx = horse.facing * SLIDE_SPEED
        end,
        update = function(dt, sm)
            horse.vy = horse.vy + GRAVITY * dt
            moveAndCollide(dt)

            local decel = (SLIDE_SPEED / SLIDE_DURATION) * dt
            if horse.vx > 0 then
                horse.vx = math.max(horse.vx - decel, 0)
            elseif horse.vx < 0 then
                horse.vx = math.min(horse.vx + decel, 0)
            end

            if not grounded then
                sm:change("fall")
            elseif not love.keyboard.isDown("down", "s") then
                sm:change(math.abs(horse.vx) > 10 and "run" or "idle")
            end
        end
    }
}

local sm

function love.load()
    world = bump.newWorld(32)
    world:add(horse, horse.x, horse.y, horse.w, horse.h)
    
    for _, platform in ipairs(platforms) do
        world:add(platform, platform.x, platform.y, platform.w, platform.h)
    end

    sm = StateMachine.new(states, "fall")

    camera.x = horse.x + horse.w / 2 - love.graphics.getWidth() / 2
    camera.y = horse.y + horse.h / 2 - love.graphics.getHeight() / 2
end

function love.update(dt)
    if grounded then
        coyoteTimer = COYOTE_TIME
    else
        coyoteTimer = math.max(coyoteTimer - dt, 0)
    end
    jumpBufferTimer = math.max(jumpBufferTimer - dt, 0)

    sm:update(dt)

    local targetX = horse.x + horse.w / 2 - love.graphics.getWidth() / 2
    local targetY = horse.y + horse.h / 2 - love.graphics.getHeight() / 2

    local smoothing = 1 - math.exp(-CAMERA_SMOOTH * dt)
    camera.x = camera.x + (targetX - camera.x) * smoothing
    camera.y = camera.y + (targetY - camera.y) * smoothing
end

function love.keypressed(key)
    if key == "space" then
        jumpBufferTimer = JUMP_BUFFER_TIME
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.translate(-camera.x, -camera.y)

    love.graphics.setColor(0.3, 0.3, 0.4)
    for _, platform in ipairs(platforms) do
        love.graphics.rectangle("fill", platform.x, platform.y, platform.w, platform.h)
    end

    love.graphics.setColor(0.85, 0.7, 0.5)
    love.graphics.rectangle("fill", horse.x, horse.y, horse.w, horse.h)

    love.graphics.pop()

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("state: " .. sm.current, 10, 10)
    love.graphics.print("wallDir: " .. tostring(wallDir), 10, 30)
    love.graphics.print("coyote: " .. string.format("%.2f", coyoteTimer), 10, 50)
    love.graphics.print("buffer: " .. string.format("%.2f", jumpBufferTimer), 10, 70)
end