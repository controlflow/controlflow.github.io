---
layout: post
title: "Unhandled exceptions on the CLR finalizer thread"
date: 2011-11-21 01:23:15
author: Aleksandr Shvedov
tags: csharp clr dotnet .net gc exceptions
---
Here is a known CLR issue that causes an unhandled exception on the finalizer thread:

```c#
using System;
using System.Threading;

sealed class Foo
{
  static Foo() { throw new Exception(".cctor"); }
  public Foo() { Console.WriteLine("Foo()"); }
  ~Foo() { Console.WriteLine("~Foo"); }
}

static class Program
{
  private static void Main()
  {
    Console.WriteLine(
      "@Main thread: {0}", Thread.CurrentThread.ManagedThreadId);

    AppDomain.CurrentDomain.UnhandledException += (_, e) =>
      Console.WriteLine("Unhandled! (@Thread: {0})\n{1}\n",
        Thread.CurrentThread.ManagedThreadId, e.ExceptionObject);

    try { new Foo(); } // trigger a TypeInitializationException
    catch (TypeInitializationException e)
    {
      Console.WriteLine("Handled in main\n{0}\n", e);
    }

    // now try collecting garbage
    Console.WriteLine("Collecting garbage...");
    GC.Collect();
    GC.WaitForPendingFinalizers(); // wait for the finalizer to run

    Console.WriteLine("Finish");
  }
}
```

The attempt to create a `Foo` instance triggers its static constructor, which throws an exception. The runtime wraps that exception in a `TypeInitializationException`, with the original exception available through `InnerException`. The type then remains in a failed initialization state for the lifetime of the application domain: subsequent calls to its static methods or attempts to create an instance fail with the same `TypeInitializationException`.

The problem is that memory for the `Foo` instance has already been allocated when its static constructor throws. The uninitialized object therefore becomes eligible for garbage collection. In fact, .NET objects can become eligible for collection even while their instance constructors are still running.

Since `Foo` has a finalizer, the runtime eventually attempts to invoke it. The finalizer overrides the ordinary virtual `Finalize` method inherited from `System.Object`. In this case, invoking it requires successful type initialization. That check fails with a `TypeInitializationException`, this time on the finalizer thread, outside the `try`/`catch` in `Main`.

The example is artificial, but it illustrates why catching a `TypeInitializationException` does not necessarily allow an application to recover.