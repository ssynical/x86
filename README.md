## todo:
* add support for various condition codes
 - JE/JZ, JNE/JNZ, JG, JL, etc

* add CALL and RET instructions for subroutine support
   - implement CALL instruction (pushing return address and jumping to subroutine)
   - implement RET instruction (popping return address and jumping back)
 
* improve arithmetic operations
   - MUL and DIV instructions and INC and DEC operations
 
* implement bitwise shift and rotate instructions
  - add SHL, SHR (logical shifts)
  - add ROL, ROR (rotates)
 
* add a test suite
  - unit tests for each implemented instruction
  - integration tests that execute small x86 programs

* implement basic debugger
  - add support for breakpoints
  - implement step-by-step execution
  - create a simple cli for the debugger

last updated 21/09
