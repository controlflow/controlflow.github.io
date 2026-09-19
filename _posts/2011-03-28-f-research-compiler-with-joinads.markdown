---
layout: post
title: "F# research compiler with joinads"
date: 2011-03-28 23:08:00
author: Aleksandr Shvedov
tags: fsharp joinads expreremental compiler computation expressions monads
---
Tomas Petricek recently released an experimental build of the F# 2.0 compiler with support for *joinads* and a few other extensions. See his [announcement](https://tomasp.net/blog/fsharp-variations-joinads.aspx/) for details.

The paper [*Reactive, parallel and concurrent programming in F#*](https://tomasp.net/academic/papers/joinads/joinads.pdf) describes joinads, their applications, the required extensions to F# computation expression syntax, and the translation rules. The implementation differs slightly from the paper: for example, rather than passing a list to `Choose`, it generates nested calls to `Choose`.

For example, the `future` joinad lets us start tasks in parallel and wait for their results:

```fsharp
let parallelOr = future {
  match! (after 1000 true), (after 100 true) with
  | !true, _ -> return true
  | _, !true -> return true
  | !a, !b -> return a || b
}
```

If either task returns `true`, the whole expression immediately evaluates to `true`. If a task returns `false`, the expression waits for the other task. Once both results are available, the third case combines them with logical `||`.

The experimental compiler also supports *idioms* (applicative functors in Haskell terminology) through `let! … and` syntax inside computation expressions. Tomas has two related articles, [Idioms in LINQ](https://tomasp.net/blog/idioms-in-linq.aspx/) and [Formlets in LINQ](https://tomasp.net/blog/formlets-in-linq.aspx/), illustrated using C# query syntax.

The compiler and F# Interactive support new constructs such as `match!`, but using them in Visual Studio is less straightforward. The IDE has its own F# parser and code model, so it reports many syntax errors even though the code compiles and runs correctly.

The modified compiler is available as a [binary download](https://tomasp.net/articles/fsharp-joinads/fsharp-joinads.zip) (ZIP, 7 MB) or as [source code for Mono](https://github.com/EHotwagner/FSharp.Extensions/tree/f95df60b5a3b2e72cb7ab8d3f10daf60bba73d8e) (preserved in a fork). There are also [sample implementations](https://github.com/tpetricek/Documents/tree/master/Blog%202011/Joinads) of the `future` and `maybe` joinads and the `ziplist` idiom.