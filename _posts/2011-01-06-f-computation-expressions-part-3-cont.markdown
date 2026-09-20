---
layout: post
title: "F# computation expressions: cont (part 3)"
date: 2011-01-06 17:04:00
author: Aleksandr Shvedov
tags: fsharp monads computation expressions cont async callcc
---
Now we turn to the [`cont`](https://hackage.haskell.org/package/mtl-2.0.0.0/docs/Control-Monad-Cont.html) monad and `callCC`. Understanding `cont` is useful both for exploring the idea of the [*mother of all monads*](https://blog.sigfpe.com/2008/12/mother-of-all-monads.html) and for working with [*continuation-passing style*](https://learn.microsoft.com/en-us/archive/blogs/ericlippert/continuation-passing-style-revisited-part-one), a common technique in functional programming.

F#'s standard `async` workflows also use continuations. Instead of a single continuation `k`, they have three: one for successful completion, one for exceptions, and one for cancellation. They also provide infrastructure for working with threads and synchronization contexts.

Here is the signature:

```fsharp
namespace FSharp.Monads

type Cont<'a, 'result> =
  Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
  val run: Cont<'a,'r> -> ('a -> 'r) -> 'r
  val callCC: (('a -> Cont<'b,'r>) -> Cont<'a,'r>) -> Cont<'a,'r>

type ContBuilder =
  new: unit -> ContBuilder
  member Bind: Cont<'a,'r> * ('a -> Cont<'b,'r>) -> Cont<'b,'r>
  member Zero: unit -> Cont<unit,'r>
  member Return: 'a -> Cont<'a,'r>
  member ReturnFrom: Cont<'a,'r> -> Cont<'a,'r>
```

Implementation:

```fsharp
namespace FSharp.Monads

type Cont<'a, 'result> =
  Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
  let run (Cont c) k = c k
  let callCC f =
    Cont(fun c -> let g a = Cont(fun _ -> c a)
                  let (Cont m) = f g in m c)

type ContBuilder() =
  member b.Bind(Cont m, f) =
    Cont(fun k ->
      m (fun r -> let (Cont c) = f r in c k))
  member b.Zero() = Cont(fun k -> k ())
  member b.Return x = Cont(fun k -> k x)
  member b.ReturnFrom x = x : Cont<_,_>
```

For an example, we will translate the [standard `cont` and `callCC` example](https://hackage.haskell.org/package/mtl-2.0.0.0/docs/Control-Monad-Cont.html) into F#. It validates a username and exits early if the name is empty, by invoking an `exit` function inside the `Cont<_,_>` computation passed to `callCC`:

```fsharp
open FSharp.Monads

let cont = ContBuilder()

/// Checks whether the name is empty
let validateName name exit =
  cont { if System.String.IsNullOrEmpty name then
           return! exit "You forgot to enter your name!" }

/// Validates the username
let whatsYourName name =
  Cont.run (cont {
    let! responce =
      Cont.callCC <| fun exit -> cont {
        do! validateName name exit
        return sprintf "Welcome, %s!" name }
    return responce
  }) (printfn "%s")

whatsYourName ""
whatsYourName "Alex"
```

The compiler translates `validateName` as follows:

```fsharp
/// Checks whether the name is empty
let validateName' name exit =
  if System.String.IsNullOrEmpty name
    then cont.ReturnFrom(exit "You forgot to enter your name!")
    else cont.Zero()
```

The translation of `whatsYourName` is a little more involved:

```fsharp
/// Validates the username
let whatsYourName' name =
  Cont.run
    (cont.Bind(
      Cont.callCC (fun exit ->
        cont.Bind(
          validateName' name exit,
          fun _ -> cont.Return (sprintf "Welcome, %s!" name))),
      fun responce -> cont.Return responce))
    (printfn "%s")
```

If `callCC` is unfamiliar, try expanding the calls in this example by hand, substituting each function body step by step. It is a useful exercise for seeing exactly how `callCC` controls the flow of execution.