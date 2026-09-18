---
layout: post
title: "Exception handling in F# 2.0 sequence expressions"
date: 2010-10-08 10:58:23
author: Aleksandr Shvedov
tags: fsharp seq ienumerable dispose finally
---
I encountered a cleanup bug in F# 2.0 sequence expressions: an exception thrown while disposing a nested enumerator can prevent an outer `finally` block from running. The behavior depends on whether the exception occurs while advancing the sequence or while disposing it.

Consider this sequence expression, with three nested `try`/`finally` blocks:

```fsharp
let xs = seq {
  try yield! seq {
    try yield! seq {
      try yield ()
      finally printfn "dispose::3"
              failwith "foo!"
    }
    finally printfn "dispose::2"
            failwith "bar!"
  }
  finally printfn "dispose::1"
}

for _ in xs do ()
```

The code raises an exception, as expected. The problem is which cleanup handlers execute. All three `finally` blocks should run, from the innermost to the outermost, even if an inner handler throws. Instead, the output in F# 2.0 is:

```text
dispose::3
dispose::2
```

The outermost handler never prints `dispose::1`. If it were releasing a resource instead, that cleanup would be skipped.

To understand this behavior, it helps to look at how F# implements nested sequence expressions. The F# 2.0 implementation of `yield!` uses a stack of `IEnumerator<T>` instances to reduce the overhead of enumerating nested sequences. Disposing the outer sequence therefore involves unwinding this stack and calling `Dispose()` on the remaining enumerators.

The cleanup mechanism differs from that of C# iterator methods. In the generated code I examined, F# does not use CLR `try`/`finally` or `try`/`fault` clauses to unwind these nested sequences. During normal enumeration, an inner sequence's `finally` handler can run as part of a call to `MoveNext()`. If that call throws, the exception propagates to the consumer. The consuming `for` loop then disposes the outermost enumerator, which is responsible for disposing the nested enumerators that are still active.

In the example above, cleanup proceeds as follows:

1. The innermost handler runs during `MoveNext()`, prints `dispose::3`, and throws `"foo!"`.
2. The exception reaches the consuming loop, which calls `Dispose()` on the outermost enumerator.
3. While unwinding the remaining enumerators, the middle handler prints `dispose::2` and throws `"bar!"`. This exception interrupts disposal, so the outermost handler is never reached.

Now remove the exception from the innermost handler, leaving the middle handler unchanged:

```fsharp
let xs = seq {
  try yield! seq {
    try yield! seq {
      try yield ()
      finally printfn "dispose::3"
    }
    finally printfn "dispose::2"
            failwith "bar!"
  }
  finally printfn "dispose::1"
}

for _ in xs do ()
```

This version still throws `"bar!"`, but all three cleanup handlers execute:

```text
dispose::3
dispose::2
dispose::1
```

Here, the first two handlers run during calls to `MoveNext()`. The innermost handler completes normally; the middle handler then throws. When the consuming loop disposes the sequence, the outermost handler is still pending and runs successfully. There is no further exception to interrupt disposal.

The distinction is between an exception that initiates disposal and one that occurs during disposal itself. The latter exposes the bug: unwinding the enumerator stack stops before all pending cleanup handlers have run.

A correct implementation must continue invoking the remaining cleanup handlers even when one of them throws. Whether this can be fixed entirely in the F# standard library, without changes to the compiler-generated code, requires further investigation.