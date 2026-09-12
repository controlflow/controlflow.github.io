---
layout: post
title: "C# yield return (part 2)"
date: 2010-09-25 22:19:25
author: Aleksandr Shvedov
tags: csharp yield enumerable
---
Suppose we have an iterator method:

```c#
static IEnumerable Bar() { yield break; }
```

Let's call it and poke around in the `IEnumerable` object it returns:

```c#
var x = Bar();
Console.WriteLine(x == x.GetEnumerator()); // true
Console.WriteLine(x == x.GetEnumerator()); // false
```

An interesting effect (`==` checks reference equality here)... The C# compiler generates just one class for the iterator, implementing both `IEnumerable` and `IEnumerator`. On the first call to `GetEnumerator()`, it can return itself, which explains the first result. On subsequent calls, though, it can no longer reuse itself as an `IEnumerator`, so it creates and returns a new instance of the same class. But that's not the only interesting effect:

```c#
var y = Bar();
var t = new Thread(() => {
  Console.WriteLine(y == y.GetEnumerator()); // false
  Console.WriteLine(y == y.GetEnumerator()); // false
});

t.Start();
t.Join();
```

So when `GetEnumerator()` is called from a thread other than the one that obtained the `IEnumerable` instance by calling the iterator method, it creates a new instance. This prevents multiple threads from accessing a "fresh" `IEnumerable` at the same time and ending up with the same `IEnumerator`.

By the way, if the iterator method returned `IEnumerator`, the C# compiler wouldn't generate any of these checks or any code for reusing the instance.

You can explore all the iterator implementation details in Reflector, or read a detailed explanation [here](http://csharpindepth.com/Articles/Chapter6/IteratorBlockImplementation.aspx).