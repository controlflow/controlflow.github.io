---
layout: post
title: "F# computation expressions: maybe (part 1)"
date: 2011-01-02 14:17:00
author: Aleksandr Shvedov
tags: fsharp computation expressions monads maybe option
---
The first post of the year is devoted to monads.

This series collects F# implementations of familiar monads such as `maybe`, `state`, and `continuation`, and perhaps a few others. The examples are primarily educational: F# already provides mutable `let` bindings for state, built-in `seq { … }`, `[ … ]`, and `[| … |]` expressions, and `async { … }` in the standard library. These implementations offer a way to explore common monads without first learning Haskell syntax or the details of *type classes*. I will implement only the computation expression builder methods needed to explain each monad and demonstrate its use. The complete list of builder methods and translation rules is available in the [language reference](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/computation-expressions).

We will start with the `maybe` monad, using F#'s standard `Option<'a>` type as the computation type `M<'a>`. Here is the signature:

```fsharp
namespace FSharp.Monads

type MaybeBuilder =
  new: unit -> MaybeBuilder
  member Zero: unit -> 'a option
  member Bind: 'a option * ('a -> 'b option) -> 'b option
  member Return: 'a -> 'a option
  member ReturnFrom: 'a option -> 'a option
```

Implementation:

```fsharp
namespace FSharp.Monads

type MaybeBuilder() =
  member b.Zero() = None
  member b.Bind(x, f) =
    match x with Some x -> f x
               | None   -> None
  member b.Return x = Some x
  member b.ReturnFrom x = x : _ option
```

As an example, this program reads an integer and tries to find its position in the list of prime numbers from 2 to 100. If the input is not an integer or is not in that list, the computation stops and returns `None`:

```fsharp
open System
open FSharp.Monads

let maybe = MaybeBuilder()

/// The list of prime numbers from 2 to 100
let primes =
  let is_prime x = // inefficient, but sufficient for this example
    Seq.forall (fun y -> x % y > 0) { 2 .. x/2 }
  { 2 .. 100 } |> Seq.filter is_prime
               |> Seq.toList

/// Attempts to read an integer from the console
let inputInt32() =
  maybe {
   let str = Console.ReadLine()
   let success, value = Int32.TryParse str
   if success then return value
  }

/// Attempts to read a prime number from the console
let tryInputPrime() =
  maybe {
    printfn "enter a prime number from 2 to 100:"
    let! prime = inputInt32()
    let! index = List.tryFindIndex ((=) prime) primes
    return prime, index + 1
  }

match tryInputPrime() with
| Some(prime, index) ->
          printfn "entered prime number %d (#%d)" prime index
| None -> printfn "failed to read a prime number"
```

Here is `inputInt32` with the computation expression syntax removed. Note the call to `Zero()`:

```fsharp
/// Attempts to read an integer from the console
let inputInt32'() =
  let str = Console.ReadLine()
  let success, value = Int32.TryParse str
  if success
    then maybe.Return(value)
    else maybe.Zero()
```

And here is the corresponding translation of `tryInputPrime`:

```fsharp
/// Attempts to read a prime number from the console
let tryInputPrime'() =
  printfn "enter a prime number from 2 to 100:"
  maybe.Bind(
    inputInt32(),
    fun prime ->
      maybe.Bind(
        List.tryFindIndex ((=) prime) primes,
        fun index ->
          maybe.Return(prime, index + 1)))
```

The standard library's `Option` module also provides functions for working with `'a option` values, including `map` and `fold`.