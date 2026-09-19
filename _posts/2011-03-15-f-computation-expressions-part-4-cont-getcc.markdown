---
layout: post
title: "F# computation expressions: part 4, cont & getCC"
date: 2011-03-15 14:00:00
author: Aleksandr Shvedov
tags: fsharp cont computation expressions monads callcc getcc
---
I recently came across [`getCC`](https://mail.haskell.org/pipermail/haskell-cafe/2005-July/010623.html), an interesting function for working with the continuation monad. It behaves like a version of `callCC` that returns the captured continuation. This lets us obtain the current continuation at a point inside a computation expression and use it later. In effect, we can model `goto` jumps and imperative loops within a composition of `cont` computations.

I have extended the [earlier implementation]({{ site.baseurl }}/2011/01/06/f-computation-expressions-part-3-cont.html) of `cont { }` with `getcc` and `getcc'`, defining them directly rather than in terms of `callcc`.

Here is the namespace signature:

```fsharp
namespace FSharp.Monads

type Cont<'a, 'result> = Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
  val run: ('a -> 'r) -> Cont<'a,'r> -> 'r
  val bind: ('a -> Cont<'b,'r>) -> Cont<'a,'r>  -> Cont<'b,'r>
  val callcc: (('a -> Cont<'b,'r>) -> Cont<'a,'r>) -> Cont<'a,'r>
  val getcc<'a,'r> : Cont<Cont<'a,'r>,'r>
  val getcc': 'a -> Cont<'a * ('a -> Cont<'b,'r>),'r>

[<Class>]
type ContBuilder =
  member Bind: Cont<'a,'r> * ('a -> Cont<'b,'r>) -> Cont<'b,'r>
  member Zero: unit -> Cont<unit, 'r>
  member Combine: Cont<unit,'r> * Cont<'a,'r> -> Cont<'a,'r>
  member Return: 'a -> Cont<'a, 'r>
  member ReturnFrom: Cont<'a,'r> -> Cont<'a,'r>
  member Delay: (unit -> Cont<'a,'r>) -> Cont<'a,'r>

[<AutoOpen>]
module ExtraTopLevelOperators =
  val cont : ContBuilder
```

Implementation:

```fsharp
namespace FSharp.Monads

type Cont<'a, 'result> = Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
  let run cont (Cont c) = c cont
  let bind f (Cont m) =
    Cont(fun cont ->
             m (fun r -> let (Cont c) = f r
                         in c cont))
  let callcc f =
    Cont(fun cont ->
             let g x = Cont(fun _ -> cont x)
             let (Cont c) = f g in c cont)
  let getcc<'a,'r> =
    Cont(fun cont ->
             let rec x: Cont<'a,'r> =
                 Cont(fun _ -> cont x)
             in cont x)
  let getcc' x0 =
    Cont(fun cont ->
             let rec f x =
                 Cont(fun _ -> cont (x, f))
             in cont (x0, f))

type ContBuilder() =
  member b.Bind(m,f) = Cont.bind f m
  member b.Return(x) = Cont(fun cont -> cont x)
  member b.Zero()    = Cont(fun cont -> cont ())
  member b.ReturnFrom(x) = x: Cont<_,_>
  member b.Combine(Cont m1, Cont m2) =
    Cont(fun cont -> m1 (fun() -> m2 cont))
  member b.Delay(f) =
    Cont(fun cont -> let (Cont c) = f() in c cont)

[<AutoOpen>]
module ExtraTopLevelOperators =
  let cont = ContBuilder()
```

This example models a `goto` jump to a label. It keeps reading keys while the user presses the space bar, and finishes when any other key is pressed:

```fsharp
open FSharp.Monads
open System

let goto() =
  cont {
    printfn "press space"
    let! jump = Cont.getcc

    let c = Console.ReadKey(true)
    if (c.Key = ConsoleKey.Spacebar) then
      printfn "one more time"
      return! jump

    printfn "completed!"
  }
  |> Cont.run ignore
```

Without the computation expression syntax, the function looks like this. This example requires two additional builder methods, `Combine` and `Delay`:

```fsharp
let goto'() =
  printfn "press space"
  cont.Combine(
    cont.Bind(
      Cont.getcc,
      fun jump ->
          let c = Console.ReadKey(true)
          if (c.Key = ConsoleKey.Spacebar) then
               printfn "one more time"
               cont.ReturnFrom(jump)
          else cont.Zero()
    ),
    cont.Delay(fun()->
      printfn "completed!"
      cont.Return(())
    )
  )
  |> Cont.run ignore
```

The other function, `getcc'`, also lets us supply a value when resuming the captured continuation. We can use it to model an imperative loop:

```fsharp
let loop() =
  cont {
    let! value, label = Cont.getcc' 0
    printfn "value = %d" value

    if value < 10
      then return! label (value + 1)
  }
  |> Cont.run id
```

Without the computation expression syntax:

```fsharp
let loop'() =
  cont.Bind(
    Cont.getcc' 0,
    fun (value, label) ->
      printfn "value = %d" value

      if value < 10
        then cont.ReturnFrom(label (value + 1))
        else cont.Zero())
  |> Cont.run id
```

The result of `getcc'` is a tuple containing a value and a function that accepts a value of the same type and returns a continuation computation. Resuming that computation makes the supplied argument appear as the first element of the tuple returned by `getcc'`. On the first pass, that element is the initial argument passed to `getcc'`.