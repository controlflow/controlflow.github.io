---
layout: post
title: "F# type functions"
date: 2010-11-01 00:00:00
author: Aleksandr Shvedov
tags: fsharp type function generalizable typeof let
---
At Vladimir Matveev's suggestion, this post looks at a less familiar feature of F#: *type functions*. You can find his writing on his [new blog](http://intellifactory.com/blogs/vladimir.matveev/) and [old blog](http://v2matveev.blogspot.com/).

Developers learning F# after working with C# may wonder how to express operations such as `typeof(T)`, `default(T)`, and the less frequently used `sizeof(T)`.

What do these C# operators have in common? They are expressions parameterized by a statically known type, have no observable side effects, and produce a result that depends only on the explicitly supplied type argument. Each could be represented by a generic method with no value arguments, such as `Type TypeOf<T>()`. Since such a function is pure and takes no value arguments, it is useful to think of it as a *value parameterized by a type*.

Rather than introducing special language syntax for these operations, F# provides corresponding values in its standard library:

```c#
typeof(List<T>)     =>  typeof<List<T>>
typeof(Action<,,>)  =>  typedefof<Action<_, _, _>>
default(decimal)    =>  Unchecked.defaultof<decimal>
sizeof(int)         =>  sizeof<int>
```

C# has dedicated syntax for referring to a generic type definition: leave the type argument positions empty, as in `Action<>` or `Dictionary<,>`. F# has no separate syntax for this. Instead, use `typedefof<T>`, supplying a constructed generic type with any valid type arguments as `T`. One way to make this more readable is to use `_` for the type arguments. Where the constraints permit it, type inference defaults these arguments to `obj`, as in the example above.

In F#, these type-parameterized `let` bindings, which take no value arguments, are called *type functions*. The standard library contains several more examples that may already be familiar:

```fsharp
List.empty
Array.empty
Seq.empty
Map.empty
```

These values can also be understood as pure generic functions with no value arguments. Unlike `typeof<T>` and the other type functions discussed above, however, they do not require explicit type arguments: F# can infer them from how the values are subsequently used. They represent the same conceptual value across different element types. An empty list of strings and an empty list of integers are both empty; neither contains an element whose value depends on the element type. It is therefore useful to have a *polymorphic* empty-list value that can be used with either type.

The literals `[]` and `[||]` provide syntax for these empty list and array values, corresponding to `List.empty` and `Array.empty`, respectively.

How can we define our own type functions? And why do some require explicit type arguments while others allow them to be inferred?

Defining a type function is rarely necessary in everyday F# code, but the syntax is straightforward: add an explicit type parameter list to a `let` binding that has no value arguments:

```fsharp
// The class hierarchy for type 'T
let typeHierarchy<'T> =
  let rec loop ts (t: System.Type) =
    if t = null then ts
                else loop (t::ts) t.BaseType
  loop [] typeof<'T>
```

Usage:

```fsharp
typeHierarchy<System.IO.FileStream>
 |> List.map (fun t -> t.Name);;

val it : string list =
  ["Object"; "MarshalByRefObject"; "Stream"; "FileStream"]
```

Explicit type parameter lists are not allowed on `let` bindings inside expressions, type definitions, or computation expressions. Type functions can therefore only be defined at module level.

For a type function such as `typeof<T>`, the result type does not depend on the type parameter: the result is always a `System.Type`. There is therefore no information in the result type from which to infer `T`, and inference would otherwise default it to `obj`. It makes sense to *require an explicit type argument*. The standard library's `[<RequiresExplicitTypeArguments>]` attribute does exactly this. It can be applied to `let` bindings and methods to require explicit type arguments rather than allowing F# to infer them. This is useful when a type parameter cannot be inferred from the arguments or the result type. Without the attribute, a call like the following can silently infer `obj`:

```fsharp
type Foo =
   member this.ServicesOfType<'T>(name: string) =
     ...

Foo().ServicesOfType("example") // Compiles, but 'T is inferred as obj.
```

For type functions such as `Seq.empty`, the result type does depend on the type parameter: `Seq.empty<'a>` has type `seq<'a>`. This allows the type argument to be inferred from subsequent use. Consider a simple type function and an attempt to use its result at two different element types:

```fsharp
let myEmptyList<'a> = List.empty<'a>

let func() =
  let empty = myEmptyList
  (1 :: empty, "a" :: empty) // error
```

The compiler reports:

> Type mismatch. Expecting a string list but given a int list. The type ‘string’ does not match the type ‘int’.

The local value `empty` cannot be used polymorphically as both an integer list and a string list. By default, a value obtained from a type function does not participate in F#'s *automatic generalization* in the same way as a function binding. Introducing a function makes the example work:

```fsharp
let func() =
  let empty() = myEmptyList
  (1 :: empty(), "a" :: empty()) // fine
```

The `[<GeneralizableValue>]` attribute addresses this distinction. Annotating the type function allows its value to participate in automatic generalization, so the local binding can be used polymorphically:

```fsharp
[<GeneralizableValue>]
let myEmptyList<'a> = List.empty<'a>

let func() =
  let empty = myEmptyList
  (1 :: empty, "a" :: empty) // fine
```

A type function should generally be marked with either `[<GeneralizableValue>]` or `[<RequiresExplicitTypeArguments>]`, depending on how it is intended to be used.

Finally, an access to a type function is compiled as a call to a generic method. Its definition is evaluated on each access, rather than once when the binding is declared. This matters when the definition allocates mutable state:

```fsharp
let zeroRef<'a> : int ref = ref 0

zeroRef := 1
printfn "%A" zeroRef // {contents = 0;}
```

A type function is best suited to a computation with no observable side effects that can meaningfully be treated as a value parameterized by a type. Define one when that model fits the problem and provides a clear benefit over an ordinary function.