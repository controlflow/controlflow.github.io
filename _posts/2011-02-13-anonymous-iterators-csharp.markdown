---
layout: post
title: "Anonymous iterators in C#?"
date: 2011-02-13 22:00:00
author: Aleksandr Shvedov
tags: csharp async yield yield return await try finally asyncctp asyncenumerator lambda-expressions
---
Today I want to explore the new C# 5.0 features in the [Async CTP](https://web.archive.org/web/20110222212138/http://www.microsoft.com/downloads/en/details.aspx?FamilyID=18712f38-fcd2-4e9f-9028-8373dc5732b2&displaylang=en), specifically the compiler transformations behind `async` and `await`. I suspect the keyword names may change before release, given their mixed reception. The [specification]({{ site.baseurl }}/assets/docs/csharp-asynchronous-functions-specification-async-ctp-2010-10-28.docx) describes the feature in detail, although the current compiler does not follow it particularly closely.

The core idea is simple, and the compiler has had much of the necessary machinery since C# 2.0: the transformation used for `yield return` iterators. It splits an iterator method into states at `yield return` and `yield break` statements, then generates a class implementing `IEnumerable<T>` or `IEnumerator<T>` (or their non-generic counterparts). The generated `MoveNext()` method contains a large `switch` over those states. Jon Skeet gives a detailed explanation of Microsoft's implementation in [this article](https://csharpindepth.com/Articles/IteratorBlockImplementation).

Developers such as Jeffrey Richter have long used this transformation to simplify asynchronous programming. Helpers such as [AsyncEnumerator](https://learn.microsoft.com/en-us/archive/msdn-magazine/2008/june/concurrent-affairs-simplified-apm-with-the-asyncenumerator) let asynchronous code read much like synchronous code, without a forest of lambdas and closures. The drawback is that the iterator body still has to interact with helper classes.

Let's try the reverse: use `async` methods to implement `yield` iterators. Since lambdas can be asynchronous, this would give us anonymous iterators in C#, where `yield return` is [not allowed inside lambdas](https://learn.microsoft.com/en-us/archive/blogs/ericlippert/iterator-blocks-part-seven-why-no-anonymous-iterators). Here is an ordinary async lambda to start with:

```c#
Func<string, Task> f = async url =>
{
  var web = new System.Net.WebClient();
  var page = await web.DownloadStringTaskAsync(url);
  Console.WriteLine(page);
};
```

Now for the implementation:

```c#
using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading;

public static class Iterator
{
```

First, define a nested awaiter class. It is part of the C# `async` infrastructure; callers should not need to use it directly:

```c#
public abstract class Awaiter<T>
{
  public Awaiter<T> GetAwaiter() { return this; }
  public abstract bool BeginAwait(Action next);
  public abstract void EndAwait();
}
```

According to the CTP specification, an expression used with `await` must have an instance or extension method named `GetAwaiter`. The returned type must define `BeginAwait` and `EndAwait` methods. `BeginAwait` takes a `System.Action` and returns `bool`; `EndAwait` takes no arguments and may return a value of any type or `void`.

When an expression is awaited, the generated code calls its `GetAwaiter()` method, then calls `BeginAwait` on the result, passing an `Action` delegate. `BeginAwait` starts the asynchronous operation and arranges for that delegate to be called when it completes. If the operation starts asynchronously, `BeginAwait` returns `true` and execution of the `async` method is suspended, returning control to its caller.

When the operation completes, the callback resumes the `async` method at the last `await`. The awaiter's `EndAwait` method is then called to retrieve the result, if any. Alternatively, `BeginAwait` can return `false` when no suspension is needed, for example because the operation has already completed. The method then continues synchronously, still calling `EndAwait` to obtain the result.

In our implementation, the awaited value and its awaiter are the same object, so `GetAwaiter` simply returns `this`.

Next, define a delegate type that returns our awaiter. This will be more convenient to use than `Func<T, Awaiter<T>>`:

```c#
public delegate Awaiter<T> Yield<T>(T value);
```

The main public method accepts an `Action` delegate representing an `async` method with a single parameter of type `Yield<T>`:

```c#
public static IEnumerable<T> Of<T>(Action<Yield<T>> @async)
{
  if (@async == null)
    throw new ArgumentNullException("async");

  return new IteratorAwaiter<T>(@async);
}
```

The main work is in `IteratorAwaiter<T>`:

```c#
private sealed class IteratorAwaiter<T> : Awaiter<T>, IEnumerator<T>, IEnumerable<T>
{
  private readonly Action<Yield<T>> @async;
  private readonly int initialThreadId;
  private Action moveNext;
  private T currentValue;

  public IteratorAwaiter(Action<Yield<T>> @async)
  {
    this.@async = @async;
    this.initialThreadId = Thread.CurrentThread.ManagedThreadId;
    this.moveNext = InitialMoveNext;
  }
```

The class stores the `Action` delegate for the `async` method and the current thread ID, for the same reason as a compiler-generated iterator. Initially, `moveNext` points to `InitialMoveNext`. That method invokes the `async` delegate, passing a lambda as its `Yield<T>` argument. The lambda sets `currentValue` and returns this `IteratorAwaiter<T>` instance as the `Awaiter<T>` expected by the `async` infrastructure:

```c#
private void InitialMoveNext()
{
  this.moveNext = null;
  this.@async(value =>
  {
    this.currentValue = value;
    return this;
  });
}
```

This delays execution until the first call to `MoveNext`. An `async` method is not lazy: the code before its first `await` runs *synchronously* when the method is called. A `yield return` iterator, however, does not start executing until `MoveNext` is called. Deferring the invocation of `@async` gives us the same behavior.

The `Awaiter<T>` implementation stores the continuation delegate in `moveNext`, then clears the field when execution resumes and `EndAwait` is called:

```c#
public override bool BeginAwait(Action next)
{
  this.moveNext = next;
  return true;
}

public override void EndAwait()
{
  this.moveNext = null;
}
```

The `IEnumerator<T>` implementation ties this together:

```c#
public T Current
{
  get { return this.currentValue; }
}

object IEnumerator.Current
{
  get { return this.currentValue; }
}

public bool MoveNext()
{
  if (this.moveNext == null) return false;

  this.moveNext();
  return (this.moveNext != null);
}

public void Reset() { }
public void Dispose() { }
```

If you are familiar with iterators, you will immediately notice that `Dispose` is incomplete; I will return to that shortly. For now, look at `MoveNext`: it invokes the delegate in `moveNext`, then checks whether that field is `null`. If the `async` method reaches its end without another `await`, the last call to `EndAwait` leaves `moveNext` set to `null`, indicating that iteration has finished.

Finally, `IEnumerable<T>` reuses this instance as the enumerator if it is requested on the original thread before iteration has started. Otherwise, it creates another `IteratorAwaiter<T>`. Clearing `moveNext` at the start of `InitialMoveNext` ensures that enumeration is no longer considered unstarted. This is the same allocation-saving approach used by C# iterators, where the enumerable and its first enumerator can be the same object:

```c#
public IEnumerator<T> GetEnumerator()
{
  if (Thread.CurrentThread.ManagedThreadId != this.initialThreadId ||
      this.moveNext == null ||
      this.moveNext.Target != this)
  {
    return new IteratorAwaiter<T>(@async);
  }

  return this;
}

IEnumerator IEnumerable.GetEnumerator()
{
  return GetEnumerator();
}
```

The [complete source code was originally published on ideone](http://ideone.com/cvNkF). Stepping through it in a debugger is a useful way to explore how the Async CTP works.

We can now write iterators as lambda expressions. The syntax is reasonably compact, although the element type must be supplied explicitly:

```c#
var xs = Iterator.Of<int>(async yield =>
{
  await yield(100);
  await yield(200);

  for (int i = 0; i < 10; i++)
  {
    await yield(i);

    if (i % 6 == 0)
      return; // instead of yield break
  }
});

foreach (var x in xs)
{
  Console.WriteLine(x);
}
```

The lambda is converted to an `Action<Iterator.Yield<int>>` delegate, which has no return value. A `return` statement therefore takes the place of `yield break`.

The delegate passed as `yield` can be called anywhere, but a value is yielded to the consumer only when the call is awaited. One possible extension would be to buffer values supplied by successive calls to `yield`, then drain that buffer at the next `await`.

In my measurements, this iterator is *1.5–2 times* slower than an ordinary `yield return` iterator, due to the extra delegate calls and the overhead of the `async` infrastructure. It also requires *AsyncCtpLibrary.dll* from the Async CTP, although a small custom implementation could potentially replace that dependency.

Another difference is that `await` is allowed inside the `try` block of a `try`/`catch` statement, where `yield return` is forbidden:

```c#
private static async void CatchIteratorImpl(Iterator.Yield<string> yield)
{
  try
  {
    await yield("inside try");
    throw new Exception();
  }
  catch
  {
    Console.WriteLine("=> catch");
  }
  finally
  {
    Console.WriteLine("=> finally");
  }
}

private static void Main(string[] args)
{
  Iterator
    .Of<string>(CatchIteratorImpl)
    .Materialize()
    .Run(Console.WriteLine);
}
```

This example uses methods from [Reactive Extensions for .NET](https://learn.microsoft.com/en-us/previous-versions/dotnet/reactive-extensions/hh242985(v=vs.103)?redirectedfrom=MSDN). `Run` is essentially a `foreach` loop whose body is the supplied delegate; `Materialize` makes sequence completion visible in the output:

    OnNext(inside try)
    => catch
    => finally
    OnCompleted()

There is a significant limitation: this implementation cannot correctly handle a consumer that stops enumeration early and calls `Dispose`. If an ordinary C# iterator is suspended inside a `try`/`finally` block, disposal executes the `finally` block. Our iterator built from an `async` method does not:

```c#
var xs = Iterator.Of<int>(async yield =>
{
  try
  {
    await yield(1);
    await yield(2);
    await yield(3);
  }
  finally
  {
    Console.WriteLine("=> finally");
  }
});

xs.Take(2) // <== stop enumeration early
  .Materialize()
  .Run(Console.WriteLine);
```

Output:

    OnNext(1)
    OnNext(2)
    OnCompleted()

Compare that with an ordinary iterator:

```c#
private static IEnumerable<int> YieldFinally()
{
  try
  {
    yield return 1;
    yield return 2;
    yield return 3;
  }
  finally
  {
    Console.WriteLine("=> finally");
  }
}

private static void Main(string[] args)
{
  YieldFinally()
    .Take(2)
    .Materialize()
    .Run(Console.WriteLine);
}
```

Its output is:

    OnNext(1)
    OnNext(2)
    => finally
    OnCompleted()

There is no straightforward fix: the Async CTP compiler does not generate the code needed to support this behavior. In effect, there is no way to dispose of an `async` method while it is suspended at an `await`. We can at least detect early disposal and throw an exception, although this check does not guard against an iterator disposing of itself during execution:

```c#
public void Dispose()
{
  if (this.moveNext != null)
    throw new InvalidOperationException("Early disposing is not supported.");
}
```

If the iterator contains no `try`/`finally` or `using` statements, this particular difference from ordinary C# 2.0 iterators disappears. Async lambdas can also be nested, so we can write nested anonymous iterators:

```c#
Iterator.Of<int>(async yield =>
{
  foreach (var x in
    Iterator.Of<int>(async y =>
    {
      await y(1);
      await y(2);
      await y(3);
    }))
  {
    await yield(x + 1);
    await yield(x + 2);
  }
})
.Run(Console.WriteLine);
```

The transformations used for Async CTP methods and C# iterators are similar enough that we can express one feature in terms of the other. This implementation is only an experiment, though: the limitations around `finally` make it unsuitable for general use.