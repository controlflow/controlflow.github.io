---
layout: post
title: "C# yield return (part 2)"
date: 2010-09-25 22:19:25
categories: 1186542411
tags: csharp yield enumerable
---
Допустим есть метод-итератор:

```c#
static IEnumerable Bar() { yield break; }
```

Попробуем вызвать его и поковырять возвращённый `IEnumerable`-объект:

```c#
var x = Bar();
Console.WriteLine(x == x.GetEnumerator()); // true
Console.WriteLine(x == x.GetEnumerator()); // false
```

Интересный эффект (оператор == тут действует как проверка ссылочной эквивалентности)… Дело тут в том, что в C# генерирует для итератора всего один класс, который реализует и интерфейс `IEnumerable`, и `IEnumerator`. При этом по вызову `GetEnumerator()` он должен фактически вернуть себя самого, что и происходит в первом вызове. Однако на следующие вызовы переиспользовать самого себя как `IEnumerator` класс уже не может, поэтому создаёт и возвращает свою копию. Однако это не все эффекты:

```c#
var y = Bar();
var t = new Thread(() => {
  Console.WriteLine(y == y.GetEnumerator()); // false
  Console.WriteLine(y == y.GetEnumerator()); // false
});

t.Start();
t.Join();
```

То есть при вызове из потока, отличного от того, в котором экземпляр `IEnumerable` был получен вызовом метода-итератора, создаётся новый экземпляр. Это сделано во избежании ситуации, когда несколько потоков могут обратиться к “свежему” `IEnumerable` одновременно и разделить между собой один и тот же `IEnumerator`.

Кстати, если бы метод-итератор возвращал `IEnumerator`, то никаких подобных проверок и переиспользований компилятор C# не генерировал бы.

Подробное описание всех implementation details итераторов можно посмотреть в reflector’е или почитать [здесь](http://csharpindepth.com/Articles/Chapter6/IteratorBlockImplementation.aspx).