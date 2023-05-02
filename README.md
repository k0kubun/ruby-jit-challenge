# Ruby JIT Challenge

Supplemental material to [Ruby JIT Hacking Guide](https://rubykaigi.org/2023/presentations/k0kubun.html) for RubyKaigi 2023

## Setup

This repository assumes an `x86_64-linux` environment and a Ruby master build.
It's recommended to use the following Docker container environment.
There's also [bin/docker](./bin/docker) as a shorthand.

```bash
$ docker run -it -v "$(pwd):/app" k0kubun/rjit bash
```

See [Dockerfile](./Dockerfile) if you want to prepare the same environment locally.

## 1. Compile nil

```rb
def none
  nil
end
```

## 2. Compile 1 + 2

```rb
def three
  1 + 2
end
```

## 3. Compile fibonatti

```rb
def fib(n)
  if n < 2
    return n
  end
  return fib(n-1) + fib(n-2)
end
```

## 4. Benchmark

```
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
