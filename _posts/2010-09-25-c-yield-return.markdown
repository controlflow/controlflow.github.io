---
layout: post
title: "C# yield return (part 1)"
date: 2010-09-25 17:52:00
author: Aleksandr Shvedov
tags: csharp enumerable iterator yield return
---

Until recently, I didn't know that iterator methods in C# (available since version 2.0) could return types other than `IEnumerable<T>`:

```c#
using System.Collections;
using System.Collections.Generic;

class Foo {
  IEnumerable Bar1() { yield return 1; }
  IEnumerator Bar2() { yield return 2; }
  IEnumerable<int> Bar3() { yield return 3; }
  IEnumerator<int> Bar4() { yield return 4; }

  static void Main() { }
}
```

`IEnumerator` (not `IEnumerable`) types are allowed in iterator methods for the convenient implementation of `IEnumerable<T>` in custom collection types.

> **10.14.2 Enumerable interfaces**
> The enumerable interfaces are the non-generic interface System.Collections.IEnumerable and all instantiations of the generic interface System.Collections.Generic.IEnumerable&lt;T&gt;. For the sake of brevity, in this chapter these interfaces are referenced as IEnumerable and IEnumerable&lt;T&gt;, respectively.

By the way, an iterator like this:

```c#
IEnumerable Bar1() { yield return 1; }
```

…actually returns a value of type `IEnumerable<object>`, but this is not documented anywhere in the specification, and it’s not something to rely on, of course…