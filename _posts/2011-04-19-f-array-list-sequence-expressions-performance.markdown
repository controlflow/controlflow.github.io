---
layout: post
title: "F# array/list sequence expressions performance"
date: 2011-04-19 20:00:00
author: Aleksandr Shvedov
tags: fsharp fprog computation expressions builders lists arrays list comprehensions seq
---
While reading sections [6.3.13](https://fsharp.github.io/fslang-spec/expressions/#6313-lists-via-sequence-expressions) and [6.3.14](https://fsharp.github.io/fslang-spec/expressions/#6314-arrays-sequence-expressions) of the [F# specification](https://fsharp.github.io/fslang-spec/), I came across these statements about list `[ ]` and array `[| |]` expressions, also known as *list and array comprehensions*:

* In all cases `[ cexpr ]` elaborates to `FSharp.Collections.Seq.toList(seq { cexpr })`.
* In all cases `[| cexpr |]` elaborates to `FSharp.Collections.Seq.toArray(seq { cexpr })`.

This surprised me. Lists and arrays differ fundamentally from `seq` sequences, which are lazy. Supporting that laziness requires the compiler to generate a substantial amount of code: a state machine, much like the one generated for `yield return` iterators in C#. It splits the sequence expression into states and keeps its local variables in captured state.

That overhead makes sense for a lazy sequence. But what about arrays and lists? When I first learned F#, I assumed that `[ ]` and `[| |]` would produce more efficient code than `seq { }`, since they do not need the machinery for deferred execution. The specification suggested otherwise.

I wanted to see whether a custom computation expression *builder* could avoid this overhead by constructing arrays and lists eagerly. In general, F# compiles computation expressions into calls to builder methods, passing nested lambda expressions as arguments. Sequence expressions are a special case: the compiler generates an optimized state machine for `seq { }`. Could an eager builder outperform that optimized but lazy implementation?

It turns out that it can. The key is that F# allows `inline` on `member` declarations as well as `let` bindings. Making the builder's methods `inline` eliminates many, though not all, of the lambdas. The resulting code constructs the collection in an almost imperative fashion, without deferred execution. I started with an alternative to `[| |]`, using the standard .NET `List<'T>` class:

```fsharp
type FastArrayBuilder<'a>() =
  inherit System.Collections.Generic.List<'a>()

type FastArrayBuilder<'a> with
  member inline arr.Yield(x)       = arr.Add(x)
  member inline arr.YieldFrom(xs)  = arr.AddRange(xs)
  member inline arr.Run(f)         = f(); arr.ToArray()
  member inline arr.Combine((), f) = f()
  member inline arr.Delay(f)       = f
  member inline arr.Zero()         = ()
  member inline arr.For(seq, f)    = for x in seq do f x
  member inline arr.Using(expr, f) = use e = expr in f e
  member inline arr.While(cond, f) = while cond() do f()
  member inline arr.TryWith(t, f)  = try t() with e -> f()
  member inline arr.TryFinally(t, f) = try t() finally f()

let inline fastarray<'a> = FastArrayBuilder<'a>()
```

The builder inherits directly from `List<'T>`, but all its members are defined in a type extension. This works around a limitation in the F# compiler: it rejects calls to public members inherited from CLI types inside these `inline` definitions, while accepting the same calls in a type extension. This may be a compiler bug.

Also, `fastarray` is a *[type function]({{ site.baseurl }}/2010/11/01/f-type-functions.html)*. Each `fastarray` expression needs to start with a fresh, empty `List<'T>`. Every reference to the *value* `fastarray` is compiled as another evaluation of `FastArrayBuilder<'a>()`, creating a new list instance.

Let's compare the two approaches using a reasonably complex array expression. The benchmark repeats the same code for each builder:

```fsharp
Measure.run [

  "[| |]", fun() ->
    [|
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    |]
    |> ignore

  "fastarray { }", fun() ->
    fastarray {
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    }
    |> ignore
]
```

Here are the results. Across different expressions, I measured speedups of 1.5–3 times over `[| |]`. Pay particular attention to the garbage collection counts in the last column:

![]({{ site.baseurl }}/images/fsharp-array-seq.png)

What about lists, one of the foundations of F#? Since `[ ]` expressions also use `seq { }`, let's try an alternative builder for them:

```fsharp
[<Struct>]
type FastListBuilder<'a> =
  new _ = { tail = [] }
  val mutable tail : 'a list

  member inline list.Yield(x) =
    list.tail <- x :: list.tail
  member inline list.YieldFrom(xs) =
    for x in xs do list.tail <- x :: list.tail
  member inline list.Run(f) =
    f(); List.rev list.tail

  member inline list.Combine((), f) = f()
  member inline list.Delay(f)       = f
  member inline list.Zero()         = ()
  member inline list.For(seq, f)    = for x in seq do f x
  member inline list.Using(expr, f) = use e = expr in f e
  member inline list.While(cond, f) = while cond() do f()
  member inline list.TryWith(t, f)  = try t() with e -> f()
  member inline list.TryFinally(t, f) = try t() finally f()

let inline fastlist<'a> = FastListBuilder<'a>(1)
```

This implementation takes a different approach. The builder is a value type, which reduces indirection, and stores a mutable reference to the list accumulated so far. Each `yield` or `yield!` prepends elements to that list. This builds the list in reverse order, so `Run` has to reverse it before returning the result. Inside the F# standard library, we could mutate list nodes to build the list in the right order directly, but that option is not available in user code. Here is the benchmark:

```fsharp
Measure.run [

  "[ ]", fun() ->
    [
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    ]
    |> ignore

  "fastlist { }", fun() ->
    fastlist {
      yield 1; yield 2; yield! {3 .. 4}
      let x1 = 123
      try for i = 1 to 10 do
            if i < 5 then yield i
                          yield! [ x1 ]
            else yield! [| 1; 2; i |]
          yield 777
      finally ()
      for i in 0 .. 10 do
        if i % 2 = 0 then yield! [1]
      yield 99
    }
    |> ignore
]
```

Even with the cost of reversing the list, the results are encouraging: there are fewer than half as many generation 0 garbage collections:

![]({{ site.baseurl }}/images/fsharp-array-seq2.png)

The improvement is worth considering. Immutable lists are fundamental to a functional language such as F#, and a core feature like list comprehensions should be as efficient as possible.

P.S. There are still scenarios where the current translation through `seq { }` makes sense. Can you think of any?