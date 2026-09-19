---
layout: post
title: "CLR array covariance implementation"
date: 2011-04-18 18:00:00
author: Aleksandr Shvedov
tags: fsharp dotnet clr arrays covariance
---
Array covariance has been part of the .NET type system since its first release. It allows an implicit conversion from an array of `B` to an array of `A` whenever there is an *implicit reference conversion* from `B` to `A`. Arrays of value types are therefore excluded.

F# has no syntax for variance annotations on interface or delegate definitions, and it does not apply array covariance implicitly. The runtime still supports array covariance, however, so we can use it through a downcast from `obj`, with a runtime type check:

```fsharp
let xs : string array = [| "abc"; "def"; "ghi" |]
let ys : obj array    = downcast (box xs)
```

If we now treat this as an ordinary `obj[]` and try to store an instance of another reference type in it, we get a `System.ArrayTypeMismatchException`:

```fsharp
// ys is actually a string[]
ys.[0] <- new obj()
```

The runtime keeps track of the array's actual element type and checks writes to arrays of reference types. This check is required not only when writing an element, but also when taking its address:

```fsharp
type Foo =
  // a method with a byref parameter
  static member Bar(x: obj byref) =
    x <- new obj()

Foo.Bar(&ys.[0]) // throws ArrayTypeMismatchException
```

Supporting array covariance therefore adds overhead to writes into arrays of reference types. This also affects collections built on top of those arrays, such as `System.Collections.Generic.List<T>` when `T` is a reference type. F# lists, which are not backed by arrays, are unaffected.

Using the benchmarking code from [this post]({{ site.baseurl }}/2011/02/05/fsharp-measure.html), let's measure the cost of the runtime check. We will compare a regular array with an array of value types that simply wrap a value of type `'a`:

```fsharp
/// A value type representing
/// a storage cell for a value of type 'a
[<Struct>]
type Holder<'a> =
  new x = { Value = x }   // constructor
  val mutable Value: 'a   // mutable storage cell

// an arbitrary value of a reference type
let ref_value = "abc"

Measure.run [ // measure write performance

  "write array elements",
  fun () -> let xs = Array.zeroCreate 1
            for i = 0 to 100000 do
                xs.[0] <- ref_value

  "write wrapped elements",
  fun () -> let xs = Array.zeroCreate 1
            for i = 0 to 100000 do
                xs.[0] <- Holder ref_value
]

Measure.run [ // measure read performance

  "read array elements",
  fun () -> let xs = [| "abc" |]
            for i = 0 to 100000 do
                ignore xs.[0]

  "read wrapped elements",
  fun () -> let xs = [| Holder "abc" |]
            for i = 0 to 100000 do
                ignore xs.[0].Value
]
```

Here are the results on my Core i3 380M at 2.533 GHz. First, writes:

![]({{ site.baseurl }}/images/array-covariance.png)

Reads:

![]({{ site.baseurl }}/images/array-covariance2.png)

The absolute overhead is small: writing an array element is a very fast operation to begin with. Even so, a slowdown of 1.5–2 times can matter across the runtime and framework. In principle, the check could be eliminated when the array's element type is known to be `sealed`, but that does not happen in these measurements.

This value-type wrapper technique can be useful when implementing mutable collections and data structures backed by arrays. Reading the wrapped values has no measurable overhead here, or at least none above the noise in the measurements.

*— update —*

The results for Mono 2.10 on Windows are somewhat different. Note the substantially lower iteration count:

![]({{ site.baseurl }}/images/array-covariance3.png)