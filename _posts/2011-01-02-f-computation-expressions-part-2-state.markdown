---
layout: post
title: "F# computation expressions: part 2, state"
date: 2011-01-02 16:32:00
author: Aleksandr Shvedov
tags: fsharp computation expressions monads state
---
F# uses eager evaluation, so variants such as the [lazy state monad](https://web.archive.org/web/20110118083258/http://blog.melding-monads.com/2009/12/30/fun-with-the-lazy-state-monad/), where state can contain an unevaluated computation, do not translate directly without introducing laziness explicitly. The same applies to the [reverse state monad](https://web.archive.org/web/20111016192904/http://lukepalmer.wordpress.com/2008/08/10/mindfuck-the-reverse-state-monad/), also known as the [backwards state monad](https://panicsonic.blogspot.com/2007/12/backwards-state-or-power-of-laziness.html). Here we will implement the ordinary *strict* state monad.

Our computation type `M<'a>` will be a discriminated union, `State<'a,'state>`, wrapping a function of type `'state -> 'a * 'state`. We will also define a `State` module with common state operations and a `run` function that executes a computation. Here is the signature:

```fsharp
namespace FSharp.Monads

type State<'a, 'state> =
  State of ('state -> 'a * 'state)

[<RequireQualifiedAccess>]
module State =
  [<GeneralizableValue>]
  val get<'a> : State<'a,'a>
  val set: 's -> State<unit,'s>
  val modify: ('s -> 's) -> State<unit,'s>
  val run : State<'a,'s> -> 's -> 'a

type StateBuilder =
  new: unit -> StateBuilder
  member Bind: State<'a,'s> * ('a -> State<'b,'s>) -> State<'b,'s>
  member Return: 'a -> State<'a,'s>
  member ReturnFrom : State<'a,'s> -> State<'a,'s>
```

Implementation:

```fsharp
namespace FSharp.Monads

type State<'a, 'state> =
  State of ('state -> 'a * 'state)

[<RequireQualifiedAccess>]
module State =
  [<GeneralizableValue>]
  let get<'a>  = State(fun (s:'a) -> s, s)
  let set s    = State(fun _ -> (), s)
  let modify f = State(fun s -> (), f s)
  let run (State f) seed = fst (f seed)

type StateBuilder() =
  member b.Bind(State m, f) =
    State(fun s -> 
      let v, s' = m s
      let (State t) = f v in t s')
  member b.Return x = State(fun s -> x, s)
  member b.ReturnFrom x = x : State<_,_>
```

For an example, we will implement [Euclid's algorithm](https://en.wikipedia.org/wiki/Euclidean_algorithm) for finding the greatest common divisor of two positive integers. An imperative C# version looks like this:

```c#
private int GCD(int x, int y)
{
  while (x != y)
  {
    if (x < y)
    {
      y = y - x;
    }
    else
    {
      x = x - y;
    }
  }

  return x;
}
```

The mutable state consists of two variables, `x` and `y`, so we will use an `int * int` tuple as the type of `'state`.

```fsharp
open FSharp.Monads
#nowarn "40"

let state = StateBuilder()

// helper functions for updating individual parts of the state
let putX x = State.modify (fun (_,y) -> x, y)
let putY y = State.modify (fun (x,_) -> x, y)

/// Euclid's algorithm
let rec gcd = state {
  let! x, y = State.get
  if   (x = y) then return x
  elif (x < y) then do! putY (y-x)
                    return! gcd
               else do! putX (x-y)
                    return! gcd }

let x = State.run gcd (6, 21)
printfn "gcd(6, 21) = %d" x
```

Without the computation expression syntax:

```fsharp
/// Euclid's algorithm
let rec gcd' =
  state.Bind(
    State.get,
    fun (x,y) ->
      if   (x = y) then state.Return x
      elif (x < y) then state.Bind(putY (y-x),
                          fun()-> state.ReturnFrom gcd')
                   else state.Bind(putX (x-y),
                          fun()-> state.ReturnFrom gcd'))
```

The generated functions and closures, the state tuple passed through the computation, and the repeated allocation of `State<'a,'state>` instances all add overhead. I would not use this implementation for performance-sensitive F# code. It serves as an example of how a monad can model changing state.