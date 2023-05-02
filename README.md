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

### Assembler

TODO

Click ▼ to open hints.

<details>
<summary>Compiling putnil</summary>

### Compiling putnil

TODO

</details>

<details>
<summary>Compiling leave</summary>

### Compiling leave

TODO

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

<details>
<summary>Compiling putobject</summary>

### Compiling leave

TODO

</details>

<details>
<summary>Compiling opt_plus</summary>

### Compiling opt\_plus

TODO

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

<details>
<summary>Compiling opt_minus</summary>

### Compiling opt\_minus

TODO

</details>

<details>
<summary>Compiling getlocal</summary>

### Compiling getlocal

TODO

</details>

<details>
<summary>Compiling opt_lt</summary>

### Compiling opt\_lt

TODO

</details>

<details>
<summary>Compiling branchunless</summary>

### Compiling branchunless

TODO

</details>

<details>
<summary>Compiling opt_send_without_block</summary>

### Compiling opt\_send\_without\_block

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
