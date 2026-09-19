---
layout: post
title: "Recursive value definitions in F#"
date: 2010-11-28 22:41:00
author: Aleksandr Shvedov
tags: fsharp letrec let rec recursive lazy
---
Recursive `let` bindings are a familiar part of programming in F# and other languages in the ML family. There is more to them, however, than recursive functions.

With `let rec`, we can define not only *recursive* and *mutually recursive functions*, but also *recursive values*. A practical example is subscribing to an `IObservable` with an `IObserver` that needs to unsubscribe itself under certain conditions:

```fsharp
open System

let source : int IObservable = ...

let rec subscription : IDisposable =
  source.Subscribe {
    new IObserver<int> with
      member o.OnNext(x) =
        if x > 0 then
          subscription.Dispose()
      ...
  }
```

Here, `subscription` is referenced inside its own definition. This works only if the observer's references to `subscription` are deferred until after `Subscribe()` returns. If the value is needed during its own initialization, the compiler can reject the definition when it detects the problem:

```fsharp
let rec foo : int = foo
```

> **error FS0031:** The value 'foo' will be evaluated as part of its own definition

If the compiler cannot detect the early access, it can instead fail at runtime with a less obvious error message:

```fsharp
let rec foo =
    let f() = foo + 1 in f()
```

> **System.InvalidOperationException:** ValueFactory attempted to access the Value property of this instance.

Another example is an infinite Fibonacci sequence. Its recursive definition is possible because sequence expressions defer evaluation:

```fsharp
let rec fibs =
    seq { yield 0
          yield! Seq.scan (+) 1 fibs
    } |> Seq.cache
```

An alternative is to add the sequence to a copy of itself shifted by one element:

```fsharp
let rec fibs' =
    seq { yield 0
          yield 1
          yield! Seq.map2 (+)
                    (Seq.skip 1 fibs')
                               (fibs')
    } |> Seq.cache
```

For these recursive value definitions, the F# compiler issues the following warning:

> **warning FS0040:** This and other recursive references to the object(s) being defined will be checked for initialization-soundness at runtime through the use of a delayed reference. This is because you are defining one or more recursive objects, rather than recursive functions.

The warning can be suppressed with this compiler directive:

```fsharp
#nowarn "40"
```

The warning raises a few questions: what is a *delayed reference*, how are references to a value within its own definition compiled, and what happens if initialization throws an exception?

Consider this deliberately minimal module, where an unused function refers to the value being defined:

```fsharp
module LetRec

let rec foo =
  let neverUsed() = foo + 1
  in 0
```

The F# compiler translates it into something roughly equivalent to:

```fsharp
let rec private foo' =
  lazy (
    let neverUsed() = Lazy.force foo' + 1
    in 0
  )

let foo = Lazy.force foo'
```

The `let rec` binding is still present, but the initialization check is now handled by `lazy`. The body of the `lazy` expression becomes a `unit -> 'T` function that initializes a `System.Lazy<'T>` instance. Defining the recursive value therefore creates a lazy value and immediately forces it. References to the value inside its definition are replaced with calls that force the same lazy value.

If `Lazy<'T>` is forced while its value is already being computed, it throws `System.InvalidOperationException` rather than recursing indefinitely and overflowing the stack. This explains the runtime error above. If initialization throws an exception, that exception is propagated to the caller and cached by `Lazy<'T>` so that later attempts to force the value throw it again. We can observe this by letting a reference to the recursive value escape from its initializer:

```fsharp
let mutable f = (fun() -> 0)

try
  let rec foo : int =
    f <- (fun() -> foo) // save a reference to foo in f
    failwith "Initialization failed."    // then throw an exception

  printfn "foo = %d" foo
with e ->
  printfn "foo = %A" e.Message
```

> foo = Initialization failed.

Calling the function stored in `f` now produces the same exception:

```fsharp
try
  printfn "f() = %d" (f())
with e ->
  printfn "f() = %A" e.Message
```

> f() = Initialization failed.

References to a value within its own definition thus involve `Lazy<'T>`, adding some overhead and potentially surfacing initialization errors later, when an escaped reference is used. Keep initialization simple, and consider whether a function or a small amount of mutable state would be clearer. For the subscription example at the start of this post, the version of [Rx](http://msdn.microsoft.com/en-us/devlabs/ee794896.aspx) available at the time provided `MutableDisposable`:

```c#
var subscription = new System.Disposables.MutableDisposable();

subscription.Disposable = source.Subscribe(x =>
{
  if (x > 0) subscription.Dispose();
});
```