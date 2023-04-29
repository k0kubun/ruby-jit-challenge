require_relative 'assembler'

module JIT
  class Compiler
    # Utilities to call C functions and interact with the Ruby VM.
    # See: https://github.com/ruby/ruby/blob/master/rjit_c.rb
    C = RubyVM::RJIT::C

    # Metadata for each YARV instruction.
    INSNS = RubyVM::RJIT::INSNS

    # Size of the JIT buffer
    JIT_BUF_SIZE = 1024 * 1024

    STACK = [:r8, :r9, :r10, :r11]
    EC = :rdi
    CFP = :rsi

    Branch = Struct.new(:start_addr, :compile)

    # Initialize a JIT buffer. Called only once.
    def initialize
      # Allocate 64MiB of memory. This returns the memory address.
      @jit_buf = C.mmap(JIT_BUF_SIZE)
      # The number of bytes that have been written to @jit_buf.
      @jit_pos = 0
    end

    # Compile a method. Called after --rjit-call-threshold calls.
    def compile(iseq)
      blocks = split_blocks(iseq)
      branches = []

      blocks.each do |block|
        block[:start_addr] = compile_block(iseq, **block, branches:, blocks:)
        if block[:start_index] == 0
          # Use it as a JIT function.
          iseq.body.jit_func = block[:start_addr]
        end
      end

      branches.each do |branch|
        with_addr(branch[:start_addr]) do
          asm = Assembler.new
          branch.compile.call(asm)
          write(asm)
        end
      end
    rescue Exception => e
      abort e.full_message
    end

    private

    def compile_block(iseq, start_index:, end_index:, stack_size:, branches:, blocks:)
      # Write machine code to this assembler.
      asm = Assembler.new

      # Iterate over each YARV instruction.
      insn_index = start_index
      while insn_index <= end_index
        insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
        case insn.name
        in :nop
          # none
        in :putnil
          asm.mov(STACK[stack_size], C.to_value(nil))
        in :putobject_INT2FIX_0_
          asm.mov(STACK[stack_size], C.to_value(0))
        in :putobject_INT2FIX_1_
          asm.mov(STACK[stack_size], C.to_value(1))
        in :putobject
          operand = iseq.body.iseq_encoded[insn_index + 1]
          asm.mov(STACK[stack_size], operand)
        in :opt_plus
          recv = STACK[stack_size - 2]
          obj = STACK[stack_size - 1]

          asm.add(recv, obj)
          asm.sub(recv, 1)
        in :opt_minus
          recv = STACK[stack_size - 2]
          obj = STACK[stack_size - 1]

          asm.sub(recv, obj)
          asm.add(recv, 1)
        in :opt_lt
          recv = STACK[stack_size - 2]
          obj = STACK[stack_size - 1]

          asm.cmp(recv, obj)
          asm.mov(recv, C.to_value(false))
          asm.mov(:rax, C.to_value(true))
          asm.cmovl(recv, :rax)
        in :getlocal_WC_0
          # Get EP
          asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

          # Load the local variable
          idx = iseq.body.iseq_encoded[insn_index + 1]
          asm.mov(STACK[stack_size], [:rax, -idx * C.VALUE.size])
        in :branchunless
          next_index = insn_index + insn.len
          next_block = blocks.find { |block| block[:start_index] == next_index }

          jump_index = next_index + iseq.body.iseq_encoded[insn_index + 1]
          jump_block = blocks.find { |block| block[:start_index] == jump_index }

          # This `test` sets ZF only for Qnil and Qfalse, which lets jz jump.
          asm.test(STACK[stack_size - 1], ~C.to_value(nil))

          branch = Branch.new
          branch.compile = proc do |asm|
            dummy_addr = @jit_buf + JIT_BUF_SIZE
            asm.jz(jump_block.fetch(:start_addr, dummy_addr))
            asm.jmp(next_block.fetch(:start_addr, dummy_addr))
          end
          asm.branch(branch) do
            branch.compile.call(asm)
          end
          branches << branch
        in :leave
          # Pop cfp: ec->cfp = cfp + 1 (rdi is EC, rsi is CFP)
          asm.lea(:rax, [CFP, C.rb_control_frame_t.size])
          asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], :rax)

          # return stack[0]
          asm.mov(:rax, STACK[stack_size - 1])
          asm.ret
        end
        stack_size += sp_inc(iseq, insn_index)
        insn_index += insn.len
      end

      # Write machine code into memory
      write(asm)
    end

    # Get a stack size increase for a YARV instruction.
    def sp_inc(iseq, insn_index)
      insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
      case insn.name
      in :opt_plus | :opt_minus | :opt_lt | :leave | :branchunless
        -1
      in :nop
        0
      in :putnil | :putobject_INT2FIX_0_ | :putobject_INT2FIX_1_ | :putobject | :getlocal_WC_0
        1
      end
    end

    # Get a list of basic blocks in a method
    def split_blocks(iseq, insn_index: 0, stack_size: 0, split_indexes: [])
      return [] if split_indexes.include?(insn_index)
      split_indexes << insn_index

      block = { start_index: insn_index, end_index: nil, stack_size: }
      blocks = [block]

      while insn_index < iseq.body.iseq_size
        insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
        case insn.name
        in :nop | :putnil | :putobject_INT2FIX_0_ | :putobject_INT2FIX_1_ | :putobject | :opt_plus | :opt_minus | :opt_lt | :getlocal_WC_0
          stack_size += sp_inc(iseq, insn_index)
          insn_index += insn.len
        in :branchunless
          block[:end_index] = insn_index
          stack_size += sp_inc(iseq, insn_index)
          next_index = insn_index + insn.len
          blocks += split_blocks(iseq, insn_index: next_index, stack_size:, split_indexes:)
          blocks += split_blocks(iseq, insn_index: next_index + iseq.body.iseq_encoded[insn_index + 1], stack_size:, split_indexes:)
          break
        in :leave
          block[:end_index] = insn_index
          break
        end
      end

      blocks
    end

    # Write bytes in a given assembler into @jit_buf.
    # @param asm [JIT::Assembler]
    def write(asm)
      jit_addr = @jit_buf + @jit_pos

      # Append machine code to the JIT buffer
      C.mprotect_write(@jit_buf, JIT_BUF_SIZE) # make @jit_buf writable
      @jit_pos += asm.assemble(jit_addr)
      C.mprotect_exec(@jit_buf, JIT_BUF_SIZE) # make @jit_buf executable

      # Dump disassembly if --rjit-dump-disasm
      if C.rjit_opts.dump_disasm
        C.dump_disasm(jit_addr, @jit_buf + @jit_pos).each do |address, mnemonic, op_str|
          puts "  0x#{format("%x", address)}: #{mnemonic} #{op_str}"
        end
      end
      puts

      jit_addr
    end

    def with_addr(addr)
      jit_pos = @jit_pos
      @jit_pos = addr - @jit_buf
      yield
    ensure
      @jit_pos = jit_pos
    end
  end
end
