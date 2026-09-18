---
layout: post
title: "F# indentation-based syntax rules"
date: 2010-10-04 13:11:00
author: Aleksandr Shvedov
tags: fsharp syntax
---
I'd like to point out a couple of curious features of F#'s indentation-based syntax that you may not have come across. Blocks usually have to maintain a consistent indentation level, but there are exceptions:

```fsharp
let x =
      11.1
    + 22.2
    * 33.3
   ** 44.4
    / 55.5
```

Infix operators (in fact, any infix *tokens*) can appear to the left of a block's indentation level, by exactly the length of the operator plus one character. In other words, only a single space is allowed after the operator. This can sometimes help line up code that uses lots of `(|>)` operators, for example:

```fsharp
// a function that doesn't do anything particularly useful
let someFunction count =

      let someSequnce = { 0 .. count }

      someSequnce
   |> Seq.map ((+) 10)
   |> Seq.toList
   |> function
      | [ 10; 11; x ] when x > 11 -> true
      | _                         -> false

   |> printfn "Answer: %b"
```

There's also an exception for `and` in `let rec` bindings:

```fsharp
let rec xs = { 0 .. 100 }
and ys = { 0 .. 200 }
```

Here, `and` can line up with `let` without causing an error. Within type definitions, the tokens `|`, `}`, `end`, and `and` behave similarly:

```fsharp
type Foo =
| CaseA
| CaseB
| CaseC

and // OK
    Bar(x : int) = class

    member baz.M() = ()

end // OK

type Baz = { x : int
} // OK
```