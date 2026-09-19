---
layout: post
title: "Emulating rank-2/rank-N polymorphism in F#"
date: 2011-06-20 18:53:00
author: Aleksandr Shvedov
tags: fsharp haskell polymorphism rank-2 rank-n types fprog
---
After a long break, I am returning to the blog, now with an engineering degree in Computer Systems and Networks.

Today I want to explore an extension to the type system: parametric polymorphism of rank 2 and higher. Of the languages I know, Haskell supports it through a [GHC language extension](https://wiki.haskell.org/Rank-N_types). Scala's more elaborate type system can also express it, as illustrated in [Higher-Rank Polymorphism in Scala](https://apocalisp.wordpress.com/2010/07/02/higher-rank-polymorphism-in-scala/) and [Towards an Effect System in Scala](https://apocalisp.wordpress.com/2011/03/20/towards-an-effect-system-in-scala-part-1/). Let's investigate the idea and emulate it in a simpler type system. I find a language feature easier to understand once I can see how to implement it at a lower level.

The basic idea is straightforward. In a language with rank-1 parametric polymorphism, we can define polymorphic functions, but passing one to another function requires instantiating it at a particular type. Rank-2 polymorphism removes this restriction. It allows a signature such as `foo: (f<'a>: 'a -> int) -> string` (pseudocode, not valid F#). The function `foo` has no type parameters of its own, but it receives a polymorphic function `f` of type `'a -> int` and can apply it to arguments of different types. I have named the argument `f` only to make the example clearer. The quantifier `<'a>`, corresponding to Haskell's `forall a`, belongs to the argument's type rather than to the outer function.

Rank-2 polymorphism still limits how deeply polymorphic function types can be nested. Passing a rank-2 function to another function requires rank 3, and further nesting requires higher ranks. There is also a separate issue: a type such as `List<(f<'a>: 'a -> 'a)> -> unit`, where a polymorphic type is used as a list's type argument, requires *impredicative polymorphism*. Rank-N polymorphism alone does not allow that.

Arbitrary-rank, or rank-N, polymorphism removes the fixed bound on nesting. It also allows signatures such as `foo<>: (f<'a>: 'a -> (g<'b>: 'b -> 'b)) -> unit`. Here, `foo` receives a polymorphic function `f`, which accepts a value of any type `'a` and returns another polymorphic function `g` of type `'b -> 'b`. Again, `foo` itself has no type parameters. The `<>` notation makes that explicit in this F#-like pseudocode.

F# does not directly support higher-rank function types, nor does the underlying .NET type system provide them in this form. We can, however, emulate them fairly easily. Suppose we have a polymorphic function that prints a value of any type `'a`:

```fsharp
/// printAny : 'a -> unit
let printAny x = printfn "%A" x
```

Now suppose we want to print the contents of a record using a supplied printer function. The printer might write to the console or serialize a value, for example. The difficulty is that the record contains fields of different types:

```fsharp
type Record = { id   : int
                name : string }

/// printRecord : Record -> (? -> unit) -> unit
let printRecord r printer = printer r.id
                            printer r.name

printRecord { id = 123; name = "Alex" } printAny
```

There is no suitable type to put in place of `?`. Using `obj` would lose the static type information we want to preserve: we need a polymorphic function, potentially with constraints on its type parameter. Rank-2 polymorphism would let us express that requirement and pass `printAny` without fixing its type argument.

F# represents function values using generated subclasses of the abstract class `FSharpFunc<'T, 'TResult>`, whose key member is `Invoke: 'T -> 'TResult`. The type arguments of the function type `'a -> 'b` become type arguments of `FSharpFunc<'T, 'TResult>`. Those arguments therefore appear in the signatures of higher-order functions that consume the function value.

The CLI supports generic methods as well as generic types. We can define a type with a generic method such as `Invoke<'T, 'TResult>: 'T -> 'TResult`. The type parameters then belong to the method, without appearing in the containing type's signature. An object of that type can stand in for a polymorphic function value. This preserves the method's type parameters; it does not erase type information at runtime. Here is how to apply the idea to our example in valid F#:

```fsharp
type PolyFunc = abstract Invoke : 'a -> unit

/// printRecord : Record -> PolyFunc -> unit
let printRecord r (printer: PolyFunc) =
  printer.Invoke r.id
  printer.Invoke r.name

printRecord
  { id = 123; name = "Alex" }
  { new PolyFunc with member __.Invoke x = printAny x }
```

`PolyFunc` declares a generic `Invoke` method with the signature we need, so `printRecord` can now be correctly typed. At the call site, we pass an object implementing `PolyFunc`, created with an *F# object expression*. Its `Invoke` implementation forwards the call and its type argument to `printAny`. Written explicitly, that forwarding looks like this:

```fsharp
member __.Invoke<'a> (x: 'a) = printAny<'a> x
```

We can extend the same approach to higher ranks. For example, a function could accept an operation like `printRecord` and invoke it with several different polymorphic printers.