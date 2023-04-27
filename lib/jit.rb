require_relative 'jit/version'
require_relative 'jit/compiler'

return unless RubyVM::RJIT.enabled?

# Replace RJIT with JIT::Compiler
RubyVM::RJIT::Compiler.prepend(Module.new {
  def compile(iseq, _)
    @compiler ||= JIT::Compiler.new
    @compiler.compile(iseq)
  end
})

# Enable JIT compilation (paused by --rjit=pause)
RubyVM::RJIT.resume
