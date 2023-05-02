def fib(n)
  if n < 2
    return n
  end
  return fib(n-1) + fib(n-2)
end

fib(2)
p fib(32)
