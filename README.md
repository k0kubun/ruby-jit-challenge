# Ruby JIT Challenge

Supplemental material to [Ruby JIT Hacking Guide](https://rubykaigi.org/2023/presentations/k0kubun.html) for RubyKaigi 2023

## 1. Setup

```bash
$ docker pull k0kubun/rjit
$ docker run -it k0kubun/rjit bash
```

## 2. Compile nil

```rb
def none
  nil
end
```

## 3. Compile 1 + 2

```rb
def three
  1 + 2
end
```

## 4. Compile fibonatti

## 5. Benchmark
