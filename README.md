# Ruby JIT Challenge

Supplemental material to [Ruby JIT Hacking Guide](https://rubykaigi.org/2023/presentations/k0kubun.html) for RubyKaigi 2023

## Introduction

This is a small tutorial to write a JIT compiler in Ruby.
We don't expect any prior experience in compilers or assembly languages.
It's supposed to take only several minutes if you open all hints, but challenging if you don't.

You'll write a JIT that can compile a Fibonacci benchmark.
With relaxed implementation requirements, you'll hopefully create a JIT faster than existing Ruby JITs with ease.

The goal of this repository is to make you feel comfortable using and/or contributing to Ruby JIT.
More importantly, enjoy writing a compiler in Ruby.

## Setup

This repository assumes an `x86_64-linux` environment.
It also requires a Ruby master build to leverage RJIT's interface to integrate a custom JIT.

It's recommended to use the following Docker container environment.
There's also [bin/docker](./bin/docker) as a shorthand.

```bash
$ docker run -it -v "$(pwd):/app" k0kubun/rjit bash
```

See [Dockerfile](./Dockerfile) if you want to prepare the same environment locally.

## Testing

You'll build a JIT in multiple steps.
Test scripts in `test/*.rb` will help you test them one by one.
You can run them with your JIT enabled with [bin/ruby](./bin/ruby).

```
bin/ruby test/none.rb
```

You can also dump compiled code with `bin/ruby --rjit-dump-disasm test/none.rb`.

For your convenience, `rake test` ([test/jit/compiler\_test.rb](./test/jit/compiler_test.rb))
runs all test scripts with your JIT enabled.

## 1. Compile nil

First, we'll compile the following simple method that just returns nil.

```rb
def none
  nil
end
```

### --dump=insns

In CRuby, each Ruby method is internally compiled into an "Instruction Sequence", also known as ISeq.
The CRuby interpreter executes Ruby code by looping over instructions in this sequence.

Typically, a CRuby JIT takes an ISeq as input to the JIT compiler and outputs machine code
that works in the same way as the ISeq. In this exercise, it's the only input you'll need to take care of.

You can dump ISeqs in a file by `ruby --dump=insns option`.
Let's have a look at the ISeq of `none` method.

```
$ ruby --dump=insns test/none.rb
...
== disasm: #<ISeq:none@test/none.rb:1 (1,0)-(3,3)>
0000 putnil                                                           (   1)[Ca]
0001 leave                                                            (   3)[Re]
```

This means that `none` consists of two instructions: `putnil` and `leave`.

`putnil` instruction puts nil on the "stack" of the Ruby interpreter. Imagine `stack = []; stack << nil`.

`leave` instruction is like `return`. It pops the stack top value and uses it as a return value of the method.
Imagine `return stack.pop`.

NOTE: Click ▼ to open hints.

<details>
<summary>Assembler</summary>

### Assembler

[lib/jit/assembler.rb](./lib/jit/assembler.rb) has an x86\_64 assembler that was copied from RJIT and then simplified.
Feel free to remove it and write it from scratch, but this tutorial will not cover how to encode x86\_64 instructions.

Here's example code using `Assembler`.

```rb
asm = Assembler.new
asm.mov(:rax, [:rsi, 8])
asm.add(:rax, 2)
write(asm)
```

This writes the following machine code into memory.

```asm
mov rax, [rsi + 8]
add rax, 2
```

`rax` and `rsi` are registers.
`[rsi + 8]` is memory access based off of a register, which reads memory 8 bytes after the address in `rsi`.
`2` is an immediate value.

See [lib/jit/assembler.rb](./lib/jit/assembler.rb) for what kind of input it can handle.

</details>
<details>
<summary>Instructions</summary>

### Instructions

There are various x86\_64 instructions.
However, it's enough to use only the following instructions to pass tests in this tutorial.

For `test/none.rb`, only `mov`, `add`, and `ret` are necessary.

| Instruction | Description                                 | Example      | Effect     |
|:------------|:--------------------------------------------|:-------------|:-----------|
| mov         | Assign a value.                             | `mov rax, 1` | `rax = 1`  |
| add         | Add a value.                                | `add rax, 1` | `rax += 1` |
| sub         | Subtract a value.                           | `sub rax, 1` | `rax -= 1` |
| cmp         | Compare values. Use it with cmovl.          | `cmp rdi, rsi`   | `rdi < rsi` |
| cmovl       | Assign a value if left < right.             | `cmovl rax, rcx` | `rax = rcx if rdi < rsi` |
| test        | Compare values. Use it with jz.             | `test rax, 1` | `rax & 1` |
| jz          | Jump if left and right have no common bits. | `jz 0x1234` | `goto 0x1234 if rax & 1 == 0` |
| jmp         | Jump to an address.                         | `jmp 0x1234` | `goto 0x1234` |
| call        | Call a function.                            | `call 0x1234` | `func()` |
| ret         | Return a value.                             | `ret` | `return rax` |

</details>
<details>
<summary>Registers</summary>

### Registers

Registers are like variables in machine code.
You're free to use registers in whatever way, but a [reference implementation](https://github.com/Shopify/ruby-jit-challenge/blob/k0kubun/lib/jit/compiler.rb)
used only the following registers.

| Register | Purpose |
|:---------|:--------|
| rdi      | `ec` (execution context) is set when a JIT function is called. It represents a Ruby thread. Used when you push/pop a stack frame. |
| rsi      | `cfp` (control frame pointer) is set when a JIT function is called. It represents a stack frame. Used when you fetch a local variable or a receiver. |
| rax      | A JIT function return value to be set before `ret` instruction. It can be also used as a "scratch register" to hold temporary values. |
| r8       | A general-purpose register. The reference implementation used this for the 1st slot of the Ruby VM stack, `stack[0]`. |
| r9       | A general-purpose register. The reference implementation used this for the 2nd slot of the Ruby VM stack, `stack[1]`. |
| r10      | A general-purpose register. The reference implementation used this for the 3rd slot of the Ruby VM stack, `stack[2]`. |
| r11      | A general-purpose register. The reference implementation used this for the 4th slot of the Ruby VM stack, `stack[3]`. |

</details>
<details>
<summary>Compiling putnil</summary>

### Compiling putnil

Open [lib/jit/compiler.rb](./lib/jit/compiler.rb) and add a case for `putnil`.

```diff
       # Iterate over each YARV instruction.
       insn_index = 0
       while insn_index < iseq.body.iseq_size
         insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
         case insn.name
         in :nop
           # none
+        in :putnil
+          # ...
         end
         insn_index += insn.len
       end
```

Let's push `nil` onto the stack.
In the scope of this tutorial, it's enough to use a random register as a replacement for a stack slot.

Let's say you decided to use `r8` for `stack[0]`, you could write the code as follows, for example.

```diff
+      STACK = [:r8]

       # Iterate over each YARV instruction.
       insn_index = 0
+      stack_size = 0
       while insn_index < iseq.body.iseq_size
         insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
         case insn.name
         in :nop
           # none
         in :putnil
+          asm.mov(STACK[stack_size], C.to_value(nil))
+          stack_size += 1
         end
         insn_index += insn.len
       end
```

`C` is a module with useful helpers to write a JIT.
`C.to_value` converts any Ruby object into its representation in the C language (and machine code).

`C.to_value(nil)` is 4, so this does `asm.mov(:r8, 4)`, which means `stack[0] = nil`.
This value in `r8` should be then handled by subsequent instructions like `leave`.

</details>
<details>
<summary>Compiling leave</summary>

### Compiling leave

`leave` instruction needs to do two things.

1. Pop a stack frame
2. Return a value

A JIT function is called after a corresponding stack frame is pushed.
However, the Ruby VM is not responsible for popping the stack frame after calling the JIT function.
So a JIT function needs to pop it on `leave` instruction.

A stack frame `cfp` is in `rsi`. The interpreter reads `ec->cfp` to fetch the current stack frame and `ec` is in `rdi`.
Therefore, you can generate code to pop a stack frame as follows.

```diff
       STACK = [:r8]
+      EC = :rdi
+      CFP = :rsi

       # Iterate over each YARV instruction.
       insn_index = 0
       stack_size = 0
       while insn_index < iseq.body.iseq_size
         insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
         case insn.name
         in :nop
           # none
         in :putnil
           asm.mov(STACK[stack_size], C.to_value(nil))
           stack_size += 1
+        in :leave
+          asm.add(CFP, C.rb_control_frame_t.size)
+          asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP)
         end
         insn_index += insn.len
       end
```

The `cfp` grows downward; `cfp -= 1` pushes a frame, and `cfp += 1` pops a frame.
Here, we want to pop a frame, so we do `cfp += 1`.
When we increment a pointer, `1` actually means the size of what it points to.
`cfp` is called `rb_control_frame_t` in the Ruby VM, and you can get its size by `C.rb_control_frame_t.size`.

To set that to `ec->cfp`, you need to get a memory address based off of `ec`.
The offset of `ec->cfp` relative to the head of `ec` is in `C.rb_execution_context_t.offsetof(:cfp)`.
So you can use `[EC, C.rb_execution_context_t.offsetof(:cfp)]` to get `ec->cfp`.

Finally, we'll return a value from the JIT function.
You should set a stack-top value to `rax` and then put `ret` instruction.

```diff
       # Iterate over each YARV instruction.
       insn_index = 0
       stack_size = 0
       while insn_index < iseq.body.iseq_size
         insn = INSNS.fetch(C.rb_vm_insn_decode(iseq.body.iseq_encoded[insn_index]))
         case insn.name
         in :nop
           # none
         in :putnil
           asm.mov(STACK[stack_size], C.to_value(nil))
           stack_size += 1
         in :leave
           asm.add(CFP, C.rb_control_frame_t.size)
           asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP)
+          asm.mov(:rax, STACK[stack_size - 1])
+          asm.ret
         end
         insn_index += insn.len
       end
```

Now you should be able to execute `test/none.rb`. Test it as follows.

```
$ bin/ruby --rjit-dump-disasm test/none.rb
  0x564e87d2c000: mov r8, 4
  0x564e87d2c007: add rsi, 0x40
  0x564e87d2c00b: mov qword ptr [rdi + 0x10], rsi
  0x564e87d2c00f: mov rax, r8
  0x564e87d2c012: ret

nil
```

`rake test` should pass one test that runs `test/none.rb`.

Also try changing what you're giving to `C.to_value` in `putnil` to double-check
the interpreter is calling the JIT function you generated.

</details>

## 2. Compile 1 + 2

Next, we'll compile something more interesting: `Integer#+`.

```rb
def plus
  1 + 2
end
```

### --dump=insns

```
$ ruby --dump=insns test/plus.rb
...
== disasm: #<ISeq:plus@test/plus.rb:1 (1,0)-(3,3)>
0000 putobject_INT2FIX_1_                                             (   2)[LiCa]
0001 putobject                              2
0003 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0005 leave                                                            (   3)[Re]
```

`plus` has four instructions: `putobject_INT2FIX_1_`, `putobject`, `opt_plus`, and `leave`.

`putobject_INT2FIX_1_` is "operand unification" of `putobject 1`.
`putnil` and `leave` didn't take any arguments, but `putobject` does.
We call an argument of instructions an operand.
At `0001`, there's `putobject` instruction, and its operand `2` is at `0002` before `opt_plus` at `0003`.
At `0000`, there's `putobject_INT2FIX_1_` instruction, and its operand `INT2FIX(1)` is unified with `putobject`,
so it doesn't take an operand, which makes the ISeq shorter.

`putobject` (and `putobject_INT2FIX_1_`) pushes an operand to the stack.
Both instructions and operands are in `iseq.body.iseq_encoded`.
To get an operand for `0001 putobject` which is at `0002`, you need to look at `iseq.body.iseq_encoded[2]`.
So that works like `stack << iseq.body.iseq_encoded[2]`.

`opt_plus` pops two objects from the stack, calls `#+`, and pushes the result onto the stack.
So it's `stack << stack.pop + stack.pop`.

<details>
<summary>Compiling putobject</summary>

### Compiling putobject

For `putobject_INT2FIX_1_`, you need to hard-code the operand as `1`.
Instead of `INT2FIX(1)` that is used in C, you can use `C.to_value(1)` instead.
So it can be:

```rb
STACK = [:r8, :r9]

in :putobject_INT2FIX_1_
  asm.mov(STACK[stack_size], C.to_value(1))
  stack_size += 1
```

For `putobject`, you need to get an operand from `iseq.body.iseq_encoded` as explained above.
You could write:

```rb
in :putobject
  operand = iseq.body.iseq_encoded[insn_index + 1]
  asm.mov(STACK[stack_size], operand)
```

</details>

<details>
<summary>Compiling opt_plus</summary>

### Compiling opt\_plus

`opt_plus` is capable of handling any `#+` methods, but specifically optimizes a few methods such as `Integer#+`.
In this tutorial, we're going to handle only `Integer`s. It's okay to assume operands are all `Integer`s.

In CRuby, a small-enough `Integer` is expressed as `(num << 1) + 1`.
So an `Integer` object `1` is expressed as `(1 << 1) + 1`, which is `3`.

You'll take `(num1 << 1) + 1` and `(num2 << 1) + 1` as operands.
If you just add them, the result will be `((num1 + num2) << 1) + 2`.
The actual representation for `num1 + num2` is `((num1 + num2) << 1) + 1`,
so you'll need to subtract it by 1.

Here's an example implementation.

```rb
in :opt_plus
  recv = STACK[stack_size - 2]
  obj = STACK[stack_size - 1]

  asm.add(recv, obj)
  asm.sub(recv, 1)

  stack_size -= 1
```

Test those instructions with `bin/ruby --rjit-dump-disasm test/plus.rb`.

</details>

## 3. Compile fibonacci

Finally, we'll have a look at the benchmark target, Fibonacci.

```rb
def fib(n)
  if n < 2
    return n
  end
  return fib(n-1) + fib(n-2)
end
```

### --dump=insns

```
$ ruby --dump=insns test/fib.rb
...
== disasm: #<ISeq:fib@test/fib.rb:1 (1,0)-(6,3)>
local table (size: 1, argc: 1 [opts: 0, rest: -1, post: 0, block: -1, kw: -1@-1, kwrest: -1])
[ 1] n@0<Arg>
0000 getlocal_WC_0                          n@0                       (   2)[LiCa]
0002 putobject                              2
0004 opt_lt                                 <calldata!mid:<, argc:1, ARGS_SIMPLE>[CcCr]
0006 branchunless                           11
0008 getlocal_WC_0                          n@0                       (   3)[Li]
0010 leave                                  [Re]
0011 putself                                                          (   5)[Li]
0012 getlocal_WC_0                          n@0
0014 putobject_INT2FIX_1_
0015 opt_minus                              <calldata!mid:-, argc:1, ARGS_SIMPLE>[CcCr]
0017 opt_send_without_block                 <calldata!mid:fib, argc:1, FCALL|ARGS_SIMPLE>
0019 putself
0020 getlocal_WC_0                          n@0
0022 putobject                              2
0024 opt_minus                              <calldata!mid:-, argc:1, ARGS_SIMPLE>[CcCr]
0026 opt_send_without_block                 <calldata!mid:fib, argc:1, FCALL|ARGS_SIMPLE>
0028 opt_plus                               <calldata!mid:+, argc:1, ARGS_SIMPLE>[CcCr]
0030 leave                                                            (   6)[Re]
```

`fib` has many more instructions.

`opt_minus` and `opt_lt` are like `opt_plus` except it performs `#-` and `#<` respectively.

`getlocal_WC_0` is operand unification of `getlocal *, 0` where `WC` stands for a wildcard.
It pushes a local variable onto the stack.

`branchunless` jumps to a destination specified by an operand when a stack-top value is
false or nil.

`putself` pushes a receiver onto the stack.

`opt_send_without_block` calls a method with a receiver and arguments on the stack.

<details>
<summary>Compiling opt_minus</summary>

### Compiling opt\_minus

Remember `opt_plus`.
You'll take `(num1 << 1) + 1` and `(num2 << 1) + 1` as operands.
If you subtract one by the other, the result will be `((num1 - num2) << 1)`.
But the actual representation for `num1 - num2` is `((num1 - num2) << 1) + 1`.
So you'll need to add 1 to it.

Here's an example implementation.

```rb
STACK = [:r8, :r9, :r10, :r11]

in :opt_minus
  recv = STACK[stack_size - 2]
  obj = STACK[stack_size - 1]

  asm.sub(recv, obj)
  asm.add(recv, 1)

  stack_size -= 1
```

Test the instruction with `bin/ruby --rjit-dump-disasm test/minus.rb`.

</details>

<details>
<summary>Compiling getlocal</summary>

### Compiling getlocal

`getlocal_WC_0` means `getlocal *, 0`. The `*` part is an operand and it has an index to the local variable from an "environment pointer" (EP).
The `0` part is a "level", which shows how many levels of EPs you need to go deeper to get a local variable.
This is needed when a local variable environment is nested, e.g. a block inside a method.
Since it's `0` this time, you will not need to worry about digging EPs. You'll need to get the EP of the current "control frame" (`cfp`).

`cfp` is in `rsi` and you can get the offset to `cfp->ep` from `C.rb_control_frame_t.offsetof(:ep)`.
So `[:rsi, C.rb_control_frame_t.offsetof(:ep)]` can be used to get an EP.

Once you get an EP, you need to find a local variable. The index is an operand, which can be fetched with `iseq.body.iseq_encoded[insn_index + 1]`.
The index is a positive number but local variables actually live "below" the EP. So you have to negate the index.
Besides, the unit of indexes is a `VALUE` type in C, which represents a Ruby object. So the index to a local variable from an EP is
`-iseq.body.iseq_encoded[insn_index + 1] * C.VALUE.size`.

All in all, an example implementation looks like this.

```rb
in :getlocal_WC_0
  # Get EP
  asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

  # Load the local variable
  idx = iseq.body.iseq_encoded[insn_index + 1]
  asm.mov(STACK[stack_size], [:rax, -idx * C.VALUE.size])

  stack_size += 1
```

Test the instruction with `bin/ruby --rjit-dump-disasm test/local.rb`.

</details>

<details>
<summary>Compiling opt_lt</summary>

### Compiling opt\_lt

Again, assume operands are `Integer`s.
Comparing `(num1 << 1) + 1` and `(num2 << 1) + 1` would return the same result as comparing `num1` and `num2`.
You'll use a `cmp` instruction that compares them.

Once you compare the values, you'll need to generate code that conditionally returns something.
`Integer#<` returns `true` or `false`.
There's a family of instructions that conditionally set a value based on a prior `cmp` (or `test`).
To conditionally set a value if `num1 < num2` holds based on the previous `cmp`,
you can use `cmovl` (conditionally move if less).

An example implementation is as follows.

```rb
in :opt_lt
  recv = STACK[stack_size - 2]
  obj = STACK[stack_size - 1]

  asm.cmp(recv, obj)
  asm.mov(recv, C.to_value(false))
  asm.mov(:rax, C.to_value(true))
  asm.cmovl(recv, :rax)

  stack_size -= 1
```

Test the instruction with `bin/ruby --rjit-dump-disasm test/lt.rb`.

</details>

<details>
<summary>Compiling putself</summary>

### Compiling putself

`fib` method is called without an argument. In Ruby, it implicitly uses the receiver of the current frame (`cfp`).
`cfp` is in `rsi`, and the offset to `cfp->self` (receiver) is implemented at `C.rb_control_frame_t.offsetof(:self)`.
So `[:rsi, C.rb_control_frame_t.offsetof(:self)]` can be used to fetch a receiver.

An example implementation looks like this.

```rb
in :putself
  asm.mov(STACK[stack_size], [CFP, C.rb_control_frame_t.offsetof(:self)])
  stack_size += 1
```

</details>

<details>
<summary>Compiling opt_send_without_block</summary>

### Compiling opt\_send\_without\_block

TODO

</details>

<details>
<summary>Compiling branchunless</summary>

### Compiling branchunless

Congratulations on making it to this stage. You've accomplished a lot already.
I hope you've enjoyed your journey.

TODO

</details>

## 4. Benchmark

Let's measure the performance.
[bin/bench](./bin/bench) allows you to compare your JIT (ruby-jit) and other CRuby JITs.

```
$ bin/bench
Calculating -------------------------------------
                         no-jit        rjit        yjit    ruby-jit
             fib(32)      5.250      19.481      32.841      58.145 i/s

Comparison:
                          fib(32)
            ruby-jit:        58.1 i/s
                yjit:        32.8 i/s - 1.77x  slower
                rjit:        19.5 i/s - 2.98x  slower
              no-jit:         5.2 i/s - 11.08x  slower
```
