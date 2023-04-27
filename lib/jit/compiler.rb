class JIT::Compiler
  # Utilities to call C functions and interact with the Ruby VM.
  # See: https://github.com/ruby/ruby/blob/master/rjit_c.rb
  C = RubyVM::RJIT::C

  # Size of the JIT buffer
  JIT_BUF_SIZE = 1024 * 1024

  # Initialize a JIT buffer. Called only once.
  def initialize
    # Allocate 64MiB of memory. This returns the memory address.
    @jit_buf = C.mmap(JIT_BUF_SIZE)
    # The number of bytes that have been written to @jit_buf.
    @jit_pos = 0
  end

  # Compile an ISeq. Called after --rjit-call-threshold calls.
  def compile(iseq)
    # iseq.body.jit_func = @jit_buf
  end
end
