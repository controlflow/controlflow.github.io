---
layout: post
title: "Memoizing curried functions in F#"
date: 2010-12-28 01:09:00
author: Aleksandr Shvedov
tags: fsharp memoize generics curried closure
---
Let's return to function memoization, this time in F#. In the ML family of languages, memoization fits naturally into a higher-order function that takes a function and returns its memoized version:

```fsharp
let memoize f =
  let cache = System.Collections.Generic.Dictionary()
  fun x -> match cache.TryGetValue x with
           | true, result -> result
           | _ -> let result = f x
                  cache.Add(x, result)
                  result
```

Let's try it:

```fsharp
let incr x = printfn "incr invoked!"
             x + 1

let f = memoize incr

printfn "f 1 = %d" (f 1)
printfn "f 2 = %d" (f 2)
printfn "f 1 = %d" (f 1)
```

Output:

    incr invoked!
    f 1 = 2
    incr invoked!
    f 2 = 3
    f 1 = 2

This works as expected. What about a function whose arguments are passed as a tuple?

```fsharp
let add (x,y) = printfn "add invoked!"
                x + y

let g = memoize add

printfn "g (1,1) = %d" (g (1,1))
printfn "g (1,2) = %d" (g (1,2))
printfn "g (1,1) = %d" (g (1,1))
```

Output:

    add invoked!
    g (1,1) = 2
    add invoked!
    g (1,2) = 3
    g (1,1) = 2

This works too: tuples support equality and hashing, so the cache can look up a tuple of arguments. But consider a function with curried arguments:

```fsharp
let add x y = printfn "add invoked!"
              x + y

let g = memoize add

printfn "g 1 1 = %d" (g 1 1)
printfn "g 1 2 = %d" (g 1 2)
printfn "g 1 1 = %d" (g 1 1)
```

Now repeated calls are no longer avoided:

    add invoked!
    g 1 1 = 2
    add invoked!
    g 1 2 = 3
    add invoked!
    g 1 1 = 2

To see why, look at the signatures of `memoize` and `add`:

```fsharp
val memoize : ('a -> 'b) -> ('a -> 'b) when 'a : equality
val add : int -> int -> int
```

The arrow in `int -> int -> int` is right-associative, so the signature is really `int -> (int -> int)`. Only the application of the *first* argument to `add` is memoized: the cache maps `int` arguments to the corresponding `int -> int` functions.

We can address this by checking the return type when applying `memoize`. If the type parameter `'b` is itself an F# function type, we should memoize the returned function before storing it in the cache. This gives us the same kind of "curried caches" as in the [previous post]({{ site.baseurl }}/2010/12/19/postsharp.html). Applying the first `int` argument to the memoized `add` retrieves a memoized `int -> int` function; applying the second argument looks up the result in that function's cache.

Here is the complete module:

```fsharp
module Memoize

open System
open Microsoft.FSharp.Reflection

/// The generic delegate type ('a -> 'b)
let private funcDef = typedefof<Func<_,_>>

/// Binding flags for finding a private static method
let private staticPrivate =
  Reflection.BindingFlags.Static ||| Reflection.BindingFlags.NonPublic

/// A type parameterized by the return type
/// of the function being memoized
type private AnyMemoizer<'T>() =

  static let memo : Func<'T,'T> =
    match typeof<'T> with

    // if the return value is an F# function
    | t when FSharpType.IsFunction t ->
      // get its argument and return types
      let targ, tres = FSharpType.GetFunctionElements t
      // find the memoization method
      // specialized for these types
      let runMethod = typeof<FuncMemoizer>
                        .GetMethod("Run", staticPrivate)
                        .GetGenericMethodDefinition()
                        .MakeGenericMethod [| targ; tres |]
      // a delegate type that transforms
      // returned function values
      let delType = funcDef.MakeGenericType [| t; t |]
      // create a delegate for the memoization method
      downcast Delegate.CreateDelegate(delType, runMethod)

    | _ -> null // otherwise, no transformation is needed

    // let bindings inside types are always private,
    // so expose the operation through a public member
    static member Run(x: 'T) = memo.Invoke x

/// A type containing the generic memoization method
and private FuncMemoizer =

  static member Run (f: 'a -> 'b) =
    let cache = Collections.Generic.Dictionary()

    // if the return value is an F# function
    if FSharpType.IsFunction typeof<'b> then
      fun x -> match cache.TryGetValue x with
               | true, result -> result
               | _ -> // memoize the returned function
                      let result = AnyMemoizer<'b>.Run(f x)
                      cache.Add(x, result)
                      result
    else // otherwise, use ordinary memoization
      fun x -> match cache.TryGetValue x with
               | true, result -> result
               | _ -> let result = f x
                      cache.Add(x, result)
                      result

/// Memoize a function with curried arguments
let curried f = FuncMemoizer.Run f
```

Let's try it:

```fsharp
let add x y = printfn "add invoked!"
              x + y

let g = Memoize.curried add

printfn "g 1 1 = %d" (g 1 1)
printfn "g 1 2 = %d" (g 1 2)
printfn "g 1 1 = %d" (g 1 1)
```

Output:

    add invoked!
    g 1 1 = 2
    add invoked!
    g 1 2 = 3
    g 1 1 = 2

The repeated call now uses the cached result. There are limitations, though. The main one is that we cannot control how deeply memoization proceeds. If a curried function returns another function, that returned function will be memoized too:

```fsharp
let func x y =
  fun a -> printfn "lambda invoked!"
           x + y + a

let f = Memoize.curried func

printfn "(f 1 2) 3 = %d" ((f 1 2) 3)
printfn "(f 1 2) 3 = %d" ((f 1 2) 3)
```

Output:

```
lambda invoked!
(f 1 2) 3 = 6
(f 1 2) 3 = 6
```
Memoizing the returned function may not be what we want. We can address this by adding a depth parameter to the memoization function and passing the remaining depth to each nested call. An implementation is available [here](http://pastebin.com/mJXGMF6d). This example shows the difference:

```fsharp
let func x y =
  printfn "func invoked!"
  fun a -> printfn "lambda invoked!"
           x + y + a

let f = Memoize.curried 3 func
let g = Memoize.curried 2 func

printfn "3 args ======="
printfn "(f 1 2) 3 = %d" ((f 1 2) 3)
printfn "(f 1 2) 3 = %d" ((f 1 2) 3)

printfn "2 args ======="
printfn "(g 1 2) 3 = %d" ((g 1 2) 3)
printfn "(g 1 2) 3 = %d" ((g 1 2) 3)
```

Output:

    3 args =======
    func invoked!
    lambda invoked!
    (f 1 2) 3 = 6
    (f 1 2) 3 = 6
    2 args =======
    func invoked!
    lambda invoked!
    (g 1 2) 3 = 6
    lambda invoked!
    (g 1 2) 3 = 6

Another drawback is memory usage. In the inner layers, memoized functions retain partially applied arguments through closures, while those arguments also serve as dictionary keys. We can see how partial application retains its arguments by stepping through this example in the Visual Studio debugger:

```fsharp
let f a b c d e f =
    a + b + c + d + e + f

let fa = f  1
let fb = fa 2
let fc = fb 3
let fd = fc 4
let fe = fd 5
let ff = fe 6
```

![]({{ site.baseurl }}/images/fsharp-memoize.png)

Each closure produced by partial application stores the supplied argument in a field, along with a reference to the function being partially applied.

Next time, we'll look at another approach to memoization in F#.