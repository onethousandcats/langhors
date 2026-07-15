-- state_machine.lua

local StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.new(states, initialState)
    local self = setmetatable({}, StateMachine)
    self.states = states
    self.current = initialState

    local startState = states[initialState]
    if startState and startState.enter then
        startState.enter()
    end

    return self
end

function StateMachine:update(dt)
    local state = self.states[self.current]
    if state and state.update then
        state.update(dt, self)
    end
end

function StateMachine:change(newStateName)
    if newStateName == self.current then return end

    local oldState = self.states[self.current]
    if oldState and oldState.exit then
        oldState.exit()
    end

    self.current = newStateName

    local newState = self.states[newStateName]
    if newState and newState.enter then
        newState.enter()
    end
end

return StateMachine