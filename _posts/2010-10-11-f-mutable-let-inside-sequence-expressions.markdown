---
layout: post
title: "F# mutable let inside sequence expressions"
date: 2010-10-11 13:31:36
author: Aleksandr Shvedov
tags: fsharp seq ienumerable mutable sequence
---
I ran into an unexpected restriction when using mutable `let` bindings inside F# sequence expressions. The following code compiles and runs:

```fsharp
let xs = seq {
  yield 1
  let mutable x = 0
  x <- 2 // OK
  yield x
}
```

However, moving the assignment into a loop causes the code to fail to compile:

```fsharp
let ys = seq {
  yield 1
  let mutable x = 0
  while true do
    x <- 2 // Error FS0407
    yield x
}
```

The compiler reports the following error:

> `error FS0407:`<br/>
> The mutable variable 'x' is used in an invalid way. Mutable variables cannot be captured by closures. Consider eliminating this use of mutation or using a heap-allocated mutable reference cell via 'ref' and '!'.

The reference to closure capture is not immediately clear from the source code. The diagnostic is particularly difficult to interpret without knowing how sequence expressions or C# iterators are implemented.

The reason for this behavior is that the assignment in the second example ends up in a different state of the sequence expression from the one where the mutable `let` binding is initialized. In the generated `MoveNext()` method, the assignment and the initialization to zero belong to different cases of the `switch` statement.

The F# compiler implicitly splits a sequence expression into regions based on `yield` expressions and control flow. It treats references from a later region to variables declared in an earlier one as closure capture. Whether or not "closure" is the most useful term here, the boundaries between these regions are not obvious from the source code.

There are several possible approaches: disallow mutable bindings inside sequence expressions, allow mutation throughout the expression, or retain the current restriction. I'm not sure which would be preferable, but in any case the diagnostic could explain the restriction more clearly.