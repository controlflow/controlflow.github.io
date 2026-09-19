---
layout: post
title: "How function values are compiled in F#"
date: 2011-08-03 19:02:00
author: Aleksandr Shvedov
tags: fsharp lambda-expressions closure compiler fprog
---
This continues the [previous post]({{ site.baseurl }}/2011/08/02/csharp-lambda-compile.html) on the transformations .NET language compilers use for anonymous methods and lambda expressions.

Now let us look at F#, which supports function values as well as CLI delegates. F# function values are represented in the CLI by subclasses of the following type:

```c#
namespace Microsoft.FSharp.Core
{
  [Serializable]
  public abstract class FSharpFunc<T, TResult>
  {
    public abstract TResult Invoke(T func);
  }
}
```

Every F# function value has a type of the form `T -> TResult`, or, more generally, `'a -> 'b`. This class resembles a .NET delegate type: it has an `Invoke()` method that can be used to call an F# function from another .NET language. Captured values are stored in fields of its subclasses. Notice the serialization attribute; we will return to it later.

A function with several arguments can be represented as a function taking a single tuple. For example, `fun(x,y) -> x + y` has the following CLI representation:

```c#
[Serializable]
class foo@7 : FSharpFunc<Tuple<int, int>, int>
{
  public override int Invoke(Tuple<int, int> tuple)
  {
    int x = tuple.Item1;
    int y = tuple.Item2;
    return x + y;
  }
}
```

Another option is to use curried functions. The expression `fun x y -> x + y`, or simply `(+)`, is a function that takes an `int` and returns another function of type `int -> int`. Applying that returned function to the second argument gives the sum. F# could compile this into something like:

```c#
[Serializable]
class bar@5 : FSharpFunc<int, FSharpFunc<int, int>>
{
  public override FSharpFunc<int, int> Invoke(int arg)
  {
    return new bar@6(arg);
  }
}

[Serializable]
class bar@6 : FSharpFunc<int, int>
{
  internal int x;
  internal bar@6(int x) { this.x = x; }

  public override int Invoke(int y)
  {
    return this.x + y;
  }
}
```

A call would then look like `f.Invoke(1).Invoke(2)`. This is straightforward, but inefficient when all arguments are supplied at once rather than through partial application: for every argument except the last, we allocate an unnecessary object and copy values into its fields. F# optimizes this representation and actually generates the following type:

```c#
[Serializable]
class hh@7 : OptimizedClosures.FSharpFunc<int, int, int>
{
  public override int Invoke(int x, int y)
  {
    return x + y;
  }
}
```

The F# standard library therefore provides a type specifically for representing curried functions with multiple arguments efficiently. Here is its definition:

```c#
[Serializable]
public abstract class FSharpFunc<T1, T2, TResult>
  : FSharpFunc<T1, FSharpFunc<T2, TResult>> // <---
{
  // an Invoke overload taking two arguments
  public abstract TResult Invoke(T1 arg1, T2 arg2);

  // override of FSharpFunc<T1, FSharpFunc<T2, TResult>>.Invoke()
  public override FSharpFunc<T2, TResult> Invoke(T1 arg)
  {
    // return a FSharpFunc<T2, TResult> that captures this and arg
    return new Invoke@2920<T2, TResult, T1>(this, arg);
  }

  [Serializable]
  private class Invoke@2920<T2, TResult, T1> : FSharpFunc<T2, TResult>
  {
    // the original function and its first argument, captured by the closure
    public FSharpFunc<T1, T2, TResult> f;
    public T1 t;

    internal Invoke@2920(FSharpFunc<T1, T2, TResult> f, T1 t)
    {
      this.f = f;
      this.t = t;
    }

    public override TResult Invoke(T2 arg)
    {
      // both arguments are now available, so call Invoke(T1, T2)
      return this.f.Invoke(this.t, arg);
    }
  }
}
```

The resulting object is still a `FSharpFunc<T1, FSharpFunc<T2, TResult>>`. Calling its single-argument `Invoke()` returns another function, which accepts the second argument and produces the result. That still requires allocating a closure for the first argument. The optimization comes from how fully applied calls are made: instead of using `f.Invoke(arg1).Invoke(arg2)`, F# uses overloads of the static `InvokeFast` method from the standard library. The actual implementation uses slightly different type parameter names:

```c#
public static TResult InvokeFast<T1, T2, TResult>(
  FSharpFunc<T1, FSharpFunc<T2, TResult>> func, T1 x, T2 y)
{
  var func2arg = func as OptimizedClosures.FSharpFunc<T1, T2, TResult>;
  if (func2arg != null) return func2arg.Invoke(x, y);

  return func.Invoke(x).Invoke(y);
}

public static TResult InvokeFast<T1, T2, T3, TResult>(
  FSharpFunc<T1, FSharpFunc<T2, FSharpFunc<T3, TResult>>> func, T1 x, T2 y, T3 z)
{
  var func3arg = func as OptimizedClosures.FSharpFunc<T1, T2, T3, TResult>;
  if (func3arg != null) return func3arg.Invoke(x, y, z);

  var func2arg = func as OptimizedClosures.FSharpFunc<T1, T2, FSharpFunc<T3, TResult>>;
  if (func2arg != null) return func2arg.Invoke(x, y).Invoke(z);

  return InvokeFast<T2, T3, TResult>(func.Invoke(x), y, z);
}

// and so on
```

For this kind of call, F# checks the function's runtime type to see whether it can accept several arguments at once. For a curried function with three arguments, it first tries to pass all three at once. If that is not possible, it tries to pass two, then supplies the third argument to the returned function. Otherwise, it supplies just the first argument and uses the same fast path to apply the remaining two arguments to the returned function.

Despite the extra checks, this is much more efficient than `f.Invoke(arg1).Invoke(arg2).Invoke(arg3)` in most everyday cases: runtime type checks are relatively cheap. Still, I would avoid curried functions with too many arguments; two or three is usually enough. The F# standard library also applies further optimizations to avoid repeating these checks on every call, for example when invoking the folder function in `List.fold`.

Next, consider functions with no meaningful return value or no input arguments, both of which are useful in an impure functional language. In C# and VB.NET, the .NET standard library provides the `System.Action` family of delegate types for functions with no return value. F# uses the type `unit`, whose only value is `()`, to represent the absence of a meaningful result or input. In most cases, functions and methods that return or accept `unit` compile to ordinary `void` methods or methods with no arguments. For function values, however, `unit` must appear in the representation:

```fsharp
/// f :: unit -> unit
let f = (fun() -> Console.WriteLine("Hello!"))
```

This compiles to:

```c#
[Serializable]
class f@3 : FSharpFunc<Unit, Unit>
{
  public override Unit Invoke(Unit unitVar0) // <---
  {
    Console.WriteLine("Hello!");
    return null; // null represents the value ()
  }
}
```

The overhead is small, but using an ordinary .NET delegate from F# avoids these dummy `unit` values altogether:

```fsharp
let a = Action(fun() -> Console.WriteLine("Hello!"))
```

This produces a separate type:

```c#
[Serializable]
sealed class a@4 // not a subclass of FSharpFunc
{
  internal void Invoke() // the signature is not constrained by FSharpFunc
  {
    Console.WriteLine("Hello!");
  }
}
```

There are other differences between C# anonymous methods and F# function values. You may have noticed that F# generates constructors that copy captured values into fields of `FSharpFunc` subclasses. Why generate these constructors when the method creating the closure could fill in its public fields directly, as C# does? F# even makes some of these fields `internal` rather than `public`. I do not know why they have this accessibility; with this construction scheme, they appear to need no more than `private` access. In C#, on the other hand, the fields must be accessible to the enclosing method so that it can read and modify captured variables.

This brings us to another important difference: in the version of F# used here, mutable local variables cannot be captured by closures. Attempting to do so produces compiler error `FS0407`. This restriction has a significant effect on the generated code. A closure object can simply receive a snapshot of the captured values through its constructor. The enclosing function can continue using its local bindings, since their values cannot change and therefore remain equal to the copies in the closure. There is no need to move the locals into shared mutable fields and rewrite every access to them; their values are copied when each closure is created. When shared mutation is necessary or convenient, F# provides `ref` cells.

This avoids the retention problem caused by two functions or delegates capturing overlapping sets of variables. Here is the problematic C# example rewritten in F#:

```fsharp
let sharedClosure() =
  let xs = Array.zeroCreate 1000000
  let index = ref 0 // a cell holding a mutable value

  let notEventUsed = Action(fun() ->
    Console.WriteLine(xs.[!index] : int))

  fun() -> index := !index + 1
```

The generated code looks like this:

```c#
sealed class notEventUsed@21 // not a subclass of FSharpFunc
{
  public int[] xs;
  public FSharpRef<int> index;

  public notEventUsed@21(int[] xs, FSharpRef<int> index)
  {
    this.xs = xs;
    this.index = index;
  }

  internal void Invoke()
  {
  	Console.WriteLine(this.xs[this.index.Contents]);
  }
}

[Serializable]
class sharedClosure@24 : FSharpFunc<Unit, Unit>
{
  public FSharpRef<int> index;

  internal sharedClosure@24(FSharpRef<int> index)
  {
    this.index = index;
  }

  public override Unit Invoke(Unit unitVar0)
  {
    this.index.Contents = this.index.Contents + 1;
    return null;
  }
}

public static FSharpFunc<Unit, Unit> sharedClosure()
{
  int[] xs = ArrayModule.ZeroCreate<int>(1000000);
  FSharpRef<int> index = Operators.Ref<int>(0);
  Action notEventUsed = new Action(new notEventUsed@21(xs, index).Invoke);
  return new sharedClosure@24(index);
}
```

We get two separate closure objects, each holding its own copy of the reference to the same mutable `index` cell. The binding itself never changes; only the cell's contents do. The returned function retains only `index`, so it does not keep the array alive.

Another benefit of restricting captured bindings to immutable ones is more predictable code. In a C# anonymous method, a captured variable can change because of code elsewhere. For example, several anonymous methods sharing a closure object may run concurrently on different threads. What looks like access to a local variable is then unsynchronized access to shared mutable state. My recommendation is to avoid modifying captured variables.

One more aspect of F# code generation remains: closure serialization. You have probably noticed the many `[Serializable]` annotations in these examples.

The F# compiler has an automatic serialization mechanism that adds `[Serializable]` to eligible F# types unless it is disabled with `[<AutoSerializable false>]`. Function values can also be serializable, which makes it possible to serialize data structures containing functions, such as an unevaluated `LazyList` from F# PowerPack or values built using computation expressions. Another use case is passing closures across .NET application domain boundaries:

```fsharp
open System

let showFromOtherDomain (message: string) =
  let domain = AppDomain.CreateDomain "Temp"
  try domain.DoCallBack(fun() -> Console.WriteLine message)
  finally AppDomain.Unload domain
```

The equivalent C# code fails because its generated closure class is not serializable, while the F# code works as expected. However, the F# compiler sometimes omits `[Serializable]` from closure classes, and I have not found a satisfactory explanation. One concrete case is a closure that captures a .NET array: the corresponding class earlier in this post indeed has no `[Serializable]` annotation. If you know why this happens, please leave a comment.