--!native
--!strict
--!optimize 2

local cpu_module = require("cpu_and_memory")
local memory_module = require("cpu_and_memory")
local decoder_module = require("decoder")
local instructions_module = require("instructions")

local MEMORY_SIZE = 1024 * 1024 -- 1 MB of memory

local cpu = cpu_module.create_cpu()
local memory = memory_module.create_memory(MEMORY_SIZE)

local function print_cpu_state()
    print("CPU State:")
    for i, reg in ipairs(cpu.registers) do
        print(string.format("%s: 0x%08X", reg.name, reg.value))
    end
    print(string.format("IP: 0x%08X", cpu.ip))
    print(string.format("Flags: 0x%08X", cpu.flags))
end

local function print_memory(start_address: number, length: number)
    print("Memory Dump:")
    for i = 0, length - 1, 4 do
        local address = start_address + i
        local value = memory_module.read_memory(memory, address, 4)
        print(string.format("0x%08X: 0x%08X", address, value))
    end
end

local function execute_instruction()
    local instruction = decoder_module.decode_instruction(cpu, memory)
    instructions_module.execute_instruction(cpu, memory, instruction)
    return instruction
end


local x86_emulator = {}

function x86_emulator.run(num_instructions: number)
    for i = 1, num_instructions do
        local instruction = execute_instruction()
        print(string.format("Executed instruction: 0x%02X", instruction.opcode))
        print_cpu_state()
        print("--------------------")
    end
end

function x86_emulator.load_program(program: {number})
    for i, byte in ipairs(program) do
        memory_module.write_memory(memory, i - 1, byte, 1)
    end
    cpu.ip = 0
end

local debug_input_queue = {"s", "c", "b 0x1000", "m 0x1000 16", "q"}
local debug_input_index = 1

local function debug_prompt(): (string, string)
    print("debug> ")
    -- FAKE!
    local input = debug_input_queue[debug_input_index] or ""
    debug_input_index += 1
    
    local command, args = input:match("^(%S+)%s*(.*)")
    return command or "", args or ""
end

function x86_emulator.debug()
    local breakpoints = {}
    local running = true

    local function add_breakpoint(address: number)
        breakpoints[address] = true
        print(string.format("Breakpoint added at 0x%08X", address))
    end
    
    local function remove_breakpoint(address: number)
        breakpoints[address] = nil
        print(string.format("Breakpoint removed from 0x%08X", address))
    end

    local function step()
        local instruction = execute_instruction()
        print(string.format("Executed instruction: 0x%02X", instruction.opcode))
        print_cpu_state()
    end

    local function run_to_breakpoint()
        while running and not breakpoints[cpu.ip] do
            step()
        end
        if breakpoints[cpu.ip] then
            print(string.format("Breakpoint hit at 0x%08X", cpu.ip))
        end
    end

    local function print_help()
        print("Debugger commands:")
        print("  s: Step (execute one instruction)")
        print("  c: Continue (run to next breakpoint)")
        print("  b <address>: Set breakpoint at address")
        print("  d <address>: Delete breakpoint at address")
        print("  p: Print CPU state")
        print("  m <address> <length>: Print memory dump")
        print("  q: Quit debugger")
        print("  h: Show this help message")
    end

    print("x86 Emulator Debugger")
    print("Type 'h' for help")

    while running do
        local command, args = debug_prompt()

        if command == "s" then
            step()
        elseif command == "c" then
            run_to_breakpoint()
        elseif command == "b" then
            local address = tonumber(args, 16)
            if address then
                add_breakpoint(address)
            else
                print("Invalid address")
            end
        elseif command == "d" then
            local address = tonumber(args, 16)
            if address then
                remove_breakpoint(address)
            else
                print("Invalid address")
            end
        elseif command == "p" then
            print_cpu_state()
        elseif command == "m" then
            local address_str, length_str = args:match("(%S+)%s+(%S+)")
            local address = tonumber(address_str, 16)
            local length = tonumber(length_str)
            if address and length then
                print_memory(address, length)
            else
                print("Invalid address or length")
            end
        elseif command == "q" then
            running = false
        elseif command == "h" then
            print_help()
        else
            print("Unknown command. Type 'h' for help.")
        end
    end
end

local function runsuite()
    local function test_mov()
        x86_emulator.load_program({0xB8, 0x78, 0x56, 0x34, 0x12}) -- mov eax, 0x12345678
        x86_emulator.run(1)
        assert(cpu.registers[1].value == 0x12345678, "MOV test failed")
        print("MOV test passed")
    end

    local function test_add()
        x86_emulator.load_program({
            0xB8, 0x01, 0x00, 0x00, 0x00, -- mov eax, 1
            0xB9, 0x02, 0x00, 0x00, 0x00, -- mov ecx, 2
            0x01, 0xC8                    -- add eax, ecx
        })
        x86_emulator.run(3)
        assert(cpu.registers[1].value == 3, "ADD test failed")
        print("ADD test passed")
    end

    local function test_jump()
        x86_emulator.load_program({
            0xB8, 0x01, 0x00, 0x00, 0x00, -- mov eax, 1
            0xEB, 0x03,                   -- jmp +3
            0xB8, 0xFF, 0xFF, 0xFF, 0xFF, -- mov eax, 0xFFFFFFFF (should be skipped)
            0xB9, 0x02, 0x00, 0x00, 0x00  -- mov ecx, 2
        })
        x86_emulator.run(3)
        assert(cpu.registers[1].value == 1, "JMP test failed (EAX)")
        assert(cpu.registers[2].value == 2, "JMP test failed (ECX)")
        print("JMP test passed")
    end

    print("Running x86 emulator tests...")
    test_mov()
    test_add()
    test_jump()
    print("All tests passed!")
end

runsuite()


--[[
local sample = {
    0xB8, 0x01, 0x00, 0x00, 0x00, -- mov eax, 1
    0xB9, 0x02, 0x00, 0x00, 0x00, -- mov ecx, 2
    0x01, 0xC8,                   -- add eax, ecx
    0xC3                          -- ret
}

x86_emulator.load_program(sample)
x86_emulator.debug()

return x86_emulator
--]]