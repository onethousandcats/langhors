-- main.lua

local bump = require("lib.bump")
local StateMachine = require("state_machine")

local world

local horse = {
    x = 100, y = 300,
    w = 40, h = 20,
    vx = 0, vy = 0,
    facing = 1
}

local floor = { x = 0, y = 500, w = 960, h = 40 }
local wall = { x = 700, y = 200, w = 24, h = 300 }

local GRAVITY = 1400
local MOVE_SPEED = 400
local JUMP_VELOCITY = -520

local grounded = false
local wallDir = 0 -- -1 = left, 1 = right, 0
local jumpPressed = false -- set true for one frame when space is hit

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
    horse.vy = horse.vy + GRAVITY * dt
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

local states = {
    idle = {
        update = function(dt, sm)
            applyHorizontalInput()
            moveAndCollide(dt)
            if not grounded then
                sm:change("fall")
            elseif jumpPressed then
                sm:change("jump")
            elseif horse.vx ~= 0 then
                sm:change("run")
            end
        end
    },
    run = {
        update = function(dt, sm)
            applyHorizontalInput()
            moveAndCollide(dt)
            if not grounded then
                sm:change("fall")
            elseif jumpPressed then
                sm:change("jump")
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
            moveAndCollide(dt)
            if horse.vy >= 0 then
                sm:change("fall")
            end
        end
    },
    fall = {
        update = function(dt, sm)
            applyHorizontalInput()
            moveAndCollide(dt)
            if grounded then
                sm:change(horse.vx == 0 and "idle" or "run")
            end
        end
    },
}

local sm

function love.load()
    world = bump.newWorld(32)
    world:add(horse, horse.x, horse.y, horse.w, horse.h)
    world:add(floor, floor.x, floor.y, floor.w, floor.h)
    world:add(wall, wall.x, wall.y, wall.w, wall.h)

    sm = StateMachine.new(states, "fall")
end

function love.update(dt)    
    sm:update(dt)
    jumpPressed = false
end

function love.keypressed(key)
    if key == "space" then
        jumpPressed = true
    end
end

function love.draw()
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.rectangle("fill", floor.x, floor.y, floor.w, floor.h)
    love.graphics.rectangle("fill", wall.x, wall.y, wall.w, wall.h)

    love.graphics.setColor(0.85, 0.7, 0.5)
    love.graphics.rectangle("fill", horse.x, horse.y, horse.w, horse.h)

love.graphics.setColor(1, 1, 1)
    love.graphics.print("state: " .. sm.current, 10, 10)
end