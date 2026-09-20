---
layout: post
title: "Yet another Y combinator in C#"
date: 2012-04-02 17:18:39
author: Aleksandr Shvedov
tags: y combinator csharp delegates
---
While trying, so far unsuccessfully, to write a typed C# version of the U combinator, which constructs a Y combinator without explicit recursion:

```c#
Y = (λh.λF.F(λx.((h(h))(F))(x))) (λh.λF.F(λx.((h(h))(F))(x)))
```

I arrived at another Y combinator that also avoids explicit recursion, using a recursively defined delegate type. It seemed worth keeping:

```c#
delegate β ƒ<α, β>(α x);
delegate α γ<α>(γ<α> f);

private static ƒ<α, β> Y<α, β>(ƒ<ƒ<α, β>, ƒ<α, β>> f)
{
  return new γ<ƒ<α, β>>(h => F => f(h(h))(F))(h => F => f(h(h))(F));
}
```

We can then express factorial in curried form, with the recursive function as its first argument:

```c#
private static ƒ<int, int> Fact(ƒ<int, int> fact)
{
  return n => (n == 0) ? 1 : n * fact(n - 1);
}
```

And pass it to the combinator:

```c#
var fact = Y<int, int>(Fact);
Console.WriteLine("fact(6) = {0}", fact(6));
```

This gives us recursive behavior without an explicit self-call in either `Y` or `Fact`.

The search for a typed version of the U combinator continues.