---
layout: post
title: "C# 5.0 epic breaking change"
date: 2012-03-11 16:29:00
author: Aleksandr Shvedov
tags: csharp vs11 breaking change closure capture
---
Yes, it finally happened. The latest C# compiler, shipped with Visual Studio "11" Beta, has changed the way it expands a `foreach` loop:

```c#
foreach (T x in xs) {
  f(x);
}
```

The `foreach` loop is a surprisingly involved construct with plenty of subtleties. Here I'm only showing the most common case, where `xs` is a variable of type `IEnumerable<T>`. Previously, the compiler would translate this loop into roughly the following:

```c#
{
  IEnumerator<T> e = ((IEnumerable<T>) xs).GetEnumerator();
  try {
    T t;
    while (e.MoveNext()) {
      t = e.Current;
      f(t);
    }
  }
  finally {
    ((IDisposable)e).Dispose();
  }
}
```

Now it produces this instead:

```c#
{
  IEnumerator<T> e = ((IEnumerable<T>) xs).GetEnumerator();
  try {
    while (e.MoveNext()) {
      T t = e.Current;
      f(t);
    }
  }
  finally {
    ((IDisposable)e).Dispose();
  }
}
```

In other words, the iteration variable declaration has moved inside the `while` loop, which changes how closures capture the `foreach` iteration variable. C# closures capture *by reference*: they capture variables themselves, not their values. Under the old rules, all anonymous methods and lambda expressions created in the loop captured the same variable. If they were invoked after the loop had finished, they would "see" its value from the final iteration, rather than the value it held when each anonymous method or lambda expression was created. Although this behavior was clearly defined in the specification and had some justification, the average C# user still stubbornly expected each iteration to capture a *fresh variable*. There's a running joke that changing this behavior would eliminate a good third of all C# questions on Stack Overflow.

Apparently, users had worn the C# team down enough for them to go ahead with a fairly major breaking change. Whatever the reason, consider this code:

```c#
using System;
using System.Collections.Generic;
using System.Linq;

static class Program {
  static void Main() {
    var xs = new List<Action>();
    foreach (var i in Enumerable.Range(1, 3)) {
      xs.Add(() => Console.WriteLine(i));
    }

    foreach (var action in xs) {
      action();
    }
  }
}
```

It now prints what you would expect:

```
1
2
3
```

I think the deciding factor was how hard it is to come up with an example where the old behavior makes sense when a closure is invoked after the loop. In 99% of cases, these closures are simply bugs. Hopefully, this change will make C# more intuitive, and lurking bugs caused by capturing the `foreach` iteration variable will fix themselves when projects are rebuilt with the C# 5.0 compiler.

P.S. This change does not affect the `for` loop, which has a similar problem: a `for` loop isn't inherently tied to the variables that may (or may not) be declared in its initializer.