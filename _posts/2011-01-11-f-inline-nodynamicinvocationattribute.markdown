---
layout: post
title: "F# inline: [NoDynamicInvocation] attribute"
date: 2011-01-11 21:01:00
author: Aleksandr Shvedov
tags: fsharp inline nodynamicinvocation generics reflection peverify csharp
---
Let's take a break from monads and look at F# `inline` definitions: both `let` bindings and `member` declarations inside types. They support F#-specific features such as statically resolved type parameters and *member constraints*, and allow the compiler to optimize code by inlining it. These features form a layer on top of the .NET type system.

The interesting question is how F# compiles these definitions to MSIL. The following example contains operations that MSIL cannot express directly for an arbitrary type parameter: adding values of type `^a`, and calling a static member named `Parse` with the signature `string -> ^a`:

```fsharp
type Foo() =
  // member inline InlineAdd:
  //     ^a * ^a -> ^a when ^a: (static member (+): ^a * ^a -> ^a)
  member inline __.InlineAdd(x: ^a, y: ^a): ^a = x + y

  [<NoDynamicInvocation>]
  member inline __.NoDynAdd (x: ^a, y: ^a): ^a = x + y

  // member inline MemberConstraint:
  //     unit -> ^a when ^a: (static member Parse: string -> ^a)
  member inline __.MemberConstraint() =
    printfn "Parsing '123' string..."
    // invoke a member through a member constraint
    (^a: (static member Parse: string -> ^a) "123")
```

This works when the type arguments are known at compile time. Type parameters written as `^a` are called *statically resolved type parameters* in F#. The `InlineAdd` and `NoDynAdd` methods can add values of any type that supports addition:

```fsharp
let foo = Foo()
let res1 = foo.InlineAdd(1, 2)
let res2 = foo.InlineAdd(1m, 2m)
let res3 = foo.NoDynAdd(1, 2)
let res4 = foo.MemberConstraint<int>()
```

Output:

```
Parsing '123' string...

val foo : Foo
val res1 : int = 3
val res2 : decimal = 3M
val res3 : int = 3
val res4 : int = 123
```
Now let's try invoking these methods through .NET reflection. First, obtain a `System.Reflection.MethodInfo` for each method:

```fsharp
let [ add; noDyn; memberConstr ] =
  List.map (typeof<Foo>.GetMethod) [ "InlineAdd"
                                     "NoDynAdd"
                                     "MemberConstraint" ]
```

We can supply the type argument to `InlineAdd` explicitly and invoke it with `int` and `decimal` values:

```fsharp
let res1 = add.MakeGenericMethod(typeof<int>)
              .Invoke(foo, [| box 1; box 2 |])

let res2 = add.MakeGenericMethod(typeof<decimal>)
              .Invoke(foo, [| box 1m; box 2m |])
```

Both calls succeed:
    
    val res1 : obj = 3
    val res2 : obj = 3M

The method also works with a user-defined type that provides an addition operator:

```fsharp
type Bar(value: int) =
  member __.Value = value
  override __.ToString() = sprintf "Bar(%d)" value
  static member (+) (l: Bar, r: Bar) = Bar(l.Value + r.Value)

let res3 = add.MakeGenericMethod(typeof<Bar>)
              .Invoke(foo, [| box (Bar 1); box (Bar 2) |])
```

Now try the same operation with `NoDynAdd`, an otherwise identical `inline` method marked with `[<NoDynamicInvocation>]`:

```fsharp
let res4 = noDyn.MakeGenericMethod(typeof<int>)
                .Invoke(foo, [| box 1; box 2 |])
```

The underlying method throws an exception:

    System.NotSupportedException: Specified method is not supported.
       at FSI_0032.Foo.NoDynAdd[a](a x, a y)

The difference lies in how F# compiles the methods. Here is the generated implementation of `InlineAdd`, decompiled to C#:

```c#
public a InlineAdd<a>(a x, a y)
{
  return LanguagePrimitives.AdditionDynamic<a, a, a>(x, y);
}
```

`AdditionDynamic` is part of the F# runtime infrastructure. It supports addition for types determined at runtime. If the type does not provide a supported addition operation, it throws an exception with a somewhat cryptic message:

> **System.NotSupportedException:**<br/>
> Dynamic invocation of op_Addition involving coercions is not supported.

For an `inline` method marked with `[<NoDynamicInvocation>]`, the compiler emits a stub that throws `NotSupportedException`. As with other inline definitions, the original body is preserved in F#-specific assembly metadata for the compiler to use when inlining:

```c#
[NoDynamicInvocation]
public a NoDynAdd<a>(a x, a y)
{
  throw new NotSupportedException();
}
```

Calls through arbitrary *member constraints* are different. F# provides runtime support for certain built-in operators, but invoking an arbitrary member this way would require resolving member constraints at runtime as well. That is an uncommon use case and difficult to implement efficiently. In the emitted method body, such calls therefore become code that throws `NotSupportedException`. We can see this by invoking `MemberConstraint` through reflection:

```fsharp
let res5 = memberConstr.MakeGenericMethod(typeof<int>)
                       .Invoke(foo, Array.empty)
```

Notice that the side effect occurs before the exception is thrown. If execution never reached the call through the member constraint, the method could complete successfully:

    Parsing '123' string...
    System.NotSupportedException: Specified method is not supported.
       at FSI_0032.Foo.MemberConstraint[a]()

The generated code is equivalent to:

```c#
public a MemberConstraint<a>()
{
  ExtraTopLevelOperators.PrintFormatLine<Unit>(
      new PrintfFormat<Unit, TextWriter, Unit, Unit, Unit>("Parsing '123' string..."));
  throw new NotSupportedException();
}
```

When exposing public `inline` definitions from an F# library, consider what happens if a caller invokes them through reflection. The F# specification also notes that the emitted MSIL for inline definitions may be [unverifiable](https://learn.microsoft.com/en-us/dotnet/framework/tools/peverify-exe-peverify-tool). Applying `[<NoDynamicInvocation>]` prevents dynamic invocation by replacing the emitted implementation with a verifiable stub that throws an exception.