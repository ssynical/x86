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

return x86_emulator