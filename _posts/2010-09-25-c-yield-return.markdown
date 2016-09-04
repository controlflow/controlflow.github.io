---
layout: post
title: "C# yield return"
date: 2010-09-25 17:52:00
tags: csharp enumerable iterator yield return
---
До недавнего времени совсем не знал, что методы-итераторы в C# (ещё с версии 2.0) могут возвращать типы, отличные от `IEnumerable<T>`:

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

Логично было бы полагать, что именно `IEnumerator`’ы можно возвращать для удобной реализации `IEnumerable<T>` своими типами, а я что-то совсем не догадывался… :(

> **10.14.2 Enumerable interfaces**<br/>
> The enumerable interfaces are the non-generic interface System.Collections.IEnumerable and all instantiations of the generic interface System.Collections.Generic.IEnumerable&lt;T&gt;. For the sake of brevity, in this chapter these interfaces are referenced as IEnumerable and IEnumerable&lt;T&gt;, respectively.

Кстати, такой итератор:

```c#
IEnumerable Bar1() { yield return 1; }
```

…на самом то деле возвращает значение типа `IEnumerable<object>`, но это нигде в спеке не документировано и полагаться на это, конечно же, не стоит… :)