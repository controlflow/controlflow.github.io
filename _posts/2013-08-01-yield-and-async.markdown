---
layout: post
title: "C# iterators and async methods: are they really that similar?"
date: 2013-08-01 21:48:00
author: Aleksandr Shvedov
tags: csharp async yield return closures enumerable
---
When C# 5.0 was announced with support for `async`, some skeptics pointed out that its headline feature was hardly new: Jeffrey Richter had been doing similar things for years in his Wintellect Power Threading library, using [`AsyncEnumerator`](http://msdn.microsoft.com/en-us/magazine/cc163323.aspx) and a feature introduced back in C# 2.0: iterator methods.

There is some truth to that. However, while implementing async method decompilation in our product's decompiler engine, I came across enough interesting details of the `async`/`await` transformation to put together a list of differences between async methods and iterators:

* Unlike Python's `yield`, C#'s `yield return` is a *statement*, not an expression. An iterator can yield values, but passing values back into its body from the outside is awkward: it requires something like shared state in a helper object. The `await` keyword, on the other hand, produces an expression. A single statement can contain any number of `await` expressions, even nested ones. This flexibility makes the transformation of an async method into a state machine much more complicated. If an `await` needs to suspend execution, values on the evaluation stack—usually temporary results from evaluating the current statement—must be saved in the state machine.

  The transformation becomes even more complicated because the stack can contain values of a type that C# cannot express directly and that cannot be stored in a closure without making the resulting MSIL unverifiable: *managed references*, used for C#'s `ref` and `out` parameters. In these cases, the compiler has to save everything needed to *reconstruct* the managed reference when the async method resumes. This simple method:

  ```c#
  class Foo
  {
    private async void Bar(int[] xs, int i, Task<int> t)
    {
      M(ref xs[i], await t);
    }
  }
  ```

  Expands into the following code, which even uses the `System.Tuple<...>` family from the .NET 4.0 Base Class Library:

  ```c#
  class Foo
  {
    private void Bar(int[] xs, int i, Task<int> t)
    {
      BarStateMachine sm;
      // capture the parameters and this
      sm._this = this;
      sm._xs = xs;
      sm._i = i;
      sm._t = t;
      // prepare the infrastructure
      sm._builder = AsyncVoidMethodBuilder.Create();
      sm._state = -1;
      // the struct on the stack is now fully initialized
      // start the method without boxing or copying the struct
      sm._builder.Start(ref sm);
    }
  }

  [StructLayout(LayoutKind.Auto)] // let the runtime arrange the fields
  struct BarStateMachine : IAsyncStateMachine
  {
    // infrastructure
    public int _state;
    public AsyncVoidMethodBuilder _builder;
    private TaskAwaiter<int> _awaiter;
    private object _stack;
    // captured state
    public Foo _this;
    public int[] _xs;
    public int _i;
    public Task<int> _t;

    void IAsyncStateMachine.MoveNext()
    {
      try // execution always takes place inside try-catch
      {
        Foo @this;
        int[] xs;
        int i;

        TaskAwaiter<int> awaiter;
        if (_state == -1) // check the state
        {
          // this is the first invocation
          // copy the captured values into local variables
          var thisCopy = _this;
          var xsCopy = _xs;
          var iCopy = _i;

          awaiter = _t.GetAwaiter();
          if (!awaiter.IsCompleted)
          {
            // execution must be suspended
            // save the evaluation stack in a tuple and capture it
            _stack = Tuple.Create(thisCopy, xsCopy, iCopy);
            _state = 0; // advance the state
            _awaiter = awaiter;
            // box the struct, create a continuation delegate,
            // and pass it to the awaiter
            _builder.AwaitUnsafeOnCompleted(ref awaiter, ref this);
            return; // return control to the caller
          }

          // the awaiter can provide the result immediately
          i = iCopy;
          xs = xsCopy;
          @this = thisCopy;
        }
        else // resume execution
        {
          // retrieve the saved evaluation stack from the tuple
          var tuple = (Tuple<Foo, int[], int>) _stack;
          @this = tuple.Item1;
          xs = tuple.Item2;
          i = tuple.Item3;

          awaiter = _awaiter;
          // clear captured values to avoid retaining objects
          _stack = null;
          _awaiter = default(TaskAwaiter<int>);
          _state = -1;
        }

        // retrieve the result from the awaiter
        var result = awaiter.GetResult();
        // finally, call M()
        @this.M(ref xs[i], result);
      }
      catch (Exception ex)
      {
        _state = -2;
        _builder.SetException(ex);
        return;
      }

      _state = -2;
      _builder.SetResult();
    }
  }
  ```

* Iterators have a particular requirement imposed by `IEnumerable`: `GetEnumerator()` can be called more than once. Each returned `IEnumerator` represents a separate execution of the iterator with the original argument values. Parameters are variables, however, and the iterator body may modify them. The C# compiler therefore preserves their original values separately and copies them into each `IEnumerator`. If the iterator returns `IEnumerator` directly, this extra copy is unnecessary: the iterator really is single-use.

  Garbage collection seems to have received less attention when iterators were implemented in C# 2.0. In an ordinary method, objects referenced by local variables—even `this`—can often be collected before the method returns. In an iterator, locals that must survive across `yield return` statements are captured in fields. Those fields can keep the referenced objects alive until the iterator object itself is collected.

  The situation can be improved by tracking when captured variables are no longer needed and clearing their fields to `null`, or `default(T)` for value types. This is what async methods do, as the `_awaiter` field in the example above shows. Async methods are always single-use and do not need to preserve the original invocation's state for another run.

* Calling an iterator method returns control immediately: it captures the arguments in an `IEnumerable`/`IEnumerator` object and returns that object to the caller. With an async method, the point at which control returns can be less predictable. A type implementing the *awaiter pattern* required by `await` is responsible for scheduling the method's continuation and providing the expression's result. It can tell the async method that the operation has already completed. For example, `TaskAwaiter` does this when the awaited task is already complete. In that case, the `await` expression executes synchronously, so it does not guarantee that control will return to the caller at that point.

  It follows that an async method which completes entirely synchronously also returns a task that is already complete. Awaiting that task can then proceed synchronously in the caller as well. This is both a useful optimization and a source of surprises if you expect a particular `await` to split the method's execution into separate stages. To force an asynchronous yield, use `await Task.Yield()`, provided a possible extra context switch is acceptable.

  There is also a useful benefit: unlike an iterator, an async method performs argument validation at the start of its body immediately and synchronously, although exceptions from a task-returning async method are recorded in the returned task. An iterator can hide a violated precondition because its body does not start executing until the first call to `MoveNext()`. That call may never happen at all, as in `xs.Take(0)`.

* Because an async method can execute entirely synchronously, some aspects of decompiling it are much simpler than for a `yield return` iterator. Remove the control-flow edges responsible for suspending `await` expressions—specifically, the `if (!awaiter.IsCompleted) { … }` branches—and the method already becomes recognizable enough for further transformations.

  Iterators have additional control-flow edges too, but theirs make decompilation harder. They need an execution path for the case where a caller invokes `Dispose()` on an `IEnumerator` before the iterator has run to completion. Async methods have no equivalent mechanism, which prevents them from directly providing the full behavior of iterators. On disposal, the iterator executes all `finally` blocks enclosing the `yield return` at which it last suspended:

  ```c#
  private IEnumerator<int> Boo(int x, int y)
  {
    try { yield return x; }
    finally { Console.WriteLine("finally1"); }

    try { yield return y; }
    finally { Console.WriteLine("finally2"); }
  }
  ```

  This becomes something like the following, using the IL `fault` construct in the pseudocode:

  ```c#
  class BooIterator : IEnumerator<int>, IDisposable
  {
    private int _current, _state;
    public int _x, _y;

    public bool MoveNext()
    {
      try
      {
        switch (_state)
        {
          case 0:
            _state = 1;
            _current = _x; // first yield return
            _state = 2;
            return true;
          case 2:
            _state = 1;
            Finally1(); // leave the first try-finally
            _state = 3;
            _current = _y; // second yield return
            _state = 4;
            return true;
          case 4:
            _state = 3;
            Finally2(); // leave the second try-finally
            break;
        }
        return false;
      }
      fault // only when an exception is thrown
      {
        Dispose();
      }
    }

    public void Dispose()
    {
      switch (_state)
      {
        case 1:
        case 2:
          try { } finally { Finally1(); }
          break;
        case 3:
        case 4:
          try { } finally { Finally2(); }
          break;
      }
    }

    private void Finally1()
    {
      _state = -1;
      Console.WriteLine("finally1");
    }

    private void Finally2()
    {
      _state = -1;
      Console.WriteLine("finally2");
    }
  }
  ```

  The same `finally` block may need to run both from `MoveNext()` and from `Dispose()`. Each `finally` block therefore becomes a separate method, and the decompiler has to reconstruct the iterator from pieces spread across several methods. In addition, an iterator always suspends at each `yield return`. The decompiler must build a table of iterator states and replace assignments such as `_state = 42;` with control-flow edges leading directly to the code for state 42.

* You may have noticed that, unlike an iterator, an async method uses a generated struct rather than a class to hold its state. This is another optimization: it avoids allocating storage for the captured state on the heap when every `await` completes synchronously. It is hard to say how often that happens in practice; I am skeptical. It certainly complicates compilers and decompilers, which now have to handle captured state stored in value types.

  The two forms of captured state do not combine neatly, either. Async lambdas and anonymous methods therefore generate two separate containers. For example:

  ```c#
  private void M(int x)
  {
    Func<Task> f = async () =>
    {
      Console.WriteLine(x);
    };
  }
  ```

  Becomes:

  ```c#
  private void M(int x)
  {
    var displayClass1 = new DisplayClass1();
    displayClass1._x = x;
    Func<Task> func = displayClass1.Lambda;
  }

  // closure for the lambda expression
  [CompilerGenerated]
  sealed class DisplayClass1
  {
    public int _x;

    public Task Lambda()
    {
      DisplayClass2 displayClass2;
      displayClass2._this = this;
      displayClass2._builder = AsyncTaskMethodBuilder.Create();
      displayClass2._state = -1;
      displayClass2._builder.Start(ref displayClass2);
      return displayClass2._builder.Task;
    }

    // state machine for the async method
    [StructLayout(LayoutKind.Auto)]
    private struct DisplayClass2 : IAsyncStateMachine
    {
      public int _state;
      public AsyncTaskMethodBuilder _builder;
      public DisplayClass1 _this;

      void IAsyncStateMachine.MoveNext()
      {
        try
        {
          if (_state != -3)
            Console.WriteLine(_this._x);
        }
        catch (Exception ex)
        {
          _state = -2;
          _builder.SetException(ex);
          return;
        }
        _state = -2;
        _builder.SetResult();
      }
    }
  }
  ```

* Iterators have one more optimization that async methods do not need. The assumption is that, in the vast majority of uses of an `IEnumerable` iterator, `GetEnumerator()` is called exactly once. It would therefore be useful to avoid allocating a separate `IEnumerator` object. The compiler uses a rather blunt trick to do this:

  ```c#
  [CompilerGenerated]
  private sealed class Iterator
    : IEnumerable<int>, IEnumerator<int> // both interfaces in one object
  {
    private int _current;
    private int _state;
    private int _initialThreadId;

    public Iterator(int state)
    {
      _state = state; // initially -2
      // remember the thread on which the iterator method was called
      _initialThreadId = Environment.CurrentManagedThreadId;
    }

    IEnumerator<int> IEnumerable<int>.GetEnumerator()
    {
      // reuse the object only on the original thread
      if (Environment.CurrentManagedThreadId == _initialThreadId
          && _state == -2) // and only if it has not been used yet
      {
        _state = 0;   // mark it as used
        return this; // no allocation
      }

      return new Iterator(0);
    }

    …
  }
  ```

  Why call it a trick? Because code generation for a language feature now depends on threading infrastructure, which can differ across .NET platforms. The code above was compiled for .NET Framework 4.5, which introduced the static `Environment.CurrentManagedThreadId` property to provide a more uniform way to identify threads. Before 4.5, the same iterator would have used `Thread.CurrentThread.ManagedThreadId`. As a result, an application targeting .NET Framework 4.5, even if its source code uses only .NET Framework 4.0 APIs, can fail with a `MissingMethodException` in an iterator when run on a machine with only .NET Framework 4.0 installed. Async methods are single-use, so they have no need for this optimization.

Despite all these differences in code generation, the one I consider most important for callers is that the point at which an async method returns control is not fixed.