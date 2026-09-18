---
layout: post
title: "F# infoof operator (part 1)"
date: 2010-11-20 04:15:00
author: Aleksandr Shvedov
tags: fsharp infoof quotations patterns pattern-matching
---
This series explores F# *pattern matching* and *active patterns*, two useful tools for working with *F# quotations*. As an example, we'll build a set of functions similar in purpose to `typeof<T>`, returning instances of `System.Reflection.MemberInfo` subclasses for properties, methods, functions, constructors, and other code elements. In effect, we'll implement an `infoof()` operation, pronounced *info-of*. Similar helpers are often written in C# using *expression trees*, as in [this example](http://codebetter.com/blogs/patricksmacchia/archive/2010/06/28/elegant-infoof-operators-in-c-read-info-of.aspx). Eric Lippert discusses the idea [here](http://blogs.msdn.com/b/ericlippert/archive/2009/05/21/in-foof-we-trust-a-dialogue.aspx).

Let's start with a function that accepts a quoted F# expression and returns a `System.Reflection.PropertyInfo` when the expression represents a property access:

```fsharp
open Microsoft.FSharp.Quotations.Patterns

let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | _ -> failwith "Not a property expression"
```

The function uses the `PropertyGet` active pattern from `Microsoft.FSharp.Quotations.Patterns` to recognize a property access and extract its metadata. It works for static properties and for properties accessed through variables or literals available at the call site:

```fsharp
propertyof<@ (null : string).Length @>

val it : System.Reflection.PropertyInfo =
  Int32 Length {Name = "Length";
                CanRead = true;
                CanWrite = false;
                DeclaringType = System.String;
                PropertyType = System.Int32; ...}

propertyof<@ System.Console.CapsLock @>

val it : System.Reflection.PropertyInfo =
  Boolean CapsLock {Name = "CapsLock";
                    CanRead = true;
                    CanWrite = false;
                    DeclaringType = System.Console;
                    PropertyType = System.Boolean; ...}
```

Accessing an instance property this way is less convenient when no instance is available. We can support that case by also accepting a quoted lambda whose body accesses a property through the lambda parameter:

```fsharp
<@ fun(s: string) -> s.Length @>

val it : Quotations.Expr<(string -> int)> =
  Lambda (s, PropertyGet (Some (s), Int32 Length, []))
```

The revised `propertyof` function becomes:

```fsharp
let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | Lambda(arg, PropertyGet(Some(Var var), info, _))
        when arg = var -> info
    | _ -> failwith "Not a property expression"
```

This demonstrates an important feature of pattern matching: patterns can be *nested*, allowing complex structures to be recognized directly. If `expr` is a lambda, its parameter is bound to `arg`, and its body is matched against `PropertyGet(Some(Var var), info, _)`. The `Some` requires an instance property access; a static property would have `None` in that position. The receiver must itself be a variable, matched by `Var var`. Finally, the `when` *guard* checks that `var` is the same variable as the lambda parameter `arg`. This rejects expressions such as `fun x -> someOtherVar.Property`, where the property is accessed through a different variable.

Now consider a property access on a different kind of literal. In F#, `123I` is a numeric literal of type `BigInteger`:

```fsharp
propertyof<@ 123I.IsZero @>

System.Exception: Not a property expression
   at FSI_0045.propertyof(FSharpExpr expr)
   at <StartupCode$FSI_0049>.$FSI_0049.main@()
```

Looking at the quotation for a similar property access reveals why this does not match:

```fsharp
<@ 123I.IsOne @>

val it : Quotations.Expr<bool> =
  Let (copyOfStruct,
     Call (None, BigInteger FromInt32[BigInteger](Int32), [Value 123]),
     PropertyGet (Some copyOfStruct, Boolean IsOne, []))
```

F# introduces a `let` binding, initializes it with the `BigInteger` value, and then accesses a property through that binding. In other words, `123I.IsOne` is quoted as `let copyOfStruct = 123I in copyOfStruct.IsOne`. Adding a pattern for this form gives:

```fsharp
let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | Lambda(arg, PropertyGet(Some(Var var), info, _))
    | Let(arg, _, PropertyGet(Some(Var var), info, _))
        when arg = var -> info
    | _ -> failwith "Not a property expression"
```

The `Lambda` and `Let` cases are combined using an *OR pattern*, written with `|`, as in `match x with 1 | 2 | 3 -> true | _ -> false`. This is possible because both alternatives bind the same names (`arg`, `var`, and `info`) with the same types. The `when` guard applies to both alternatives. Here are several examples:

```fsharp
[ propertyof<@ System.Console.Out @>
  propertyof<@ (null: Type).IsClass @>
  propertyof<@ "someStringLiteral".Length @>
  propertyof<@ fun(x: string) -> x.Length @> ]

|> List.iter (printfn "%A")
```

The output is:

    System.IO.TextWriter Out
    Boolean IsClass
    Int32 Length
    Int32 Length

This version is sufficient for now. In the next post, we'll build the more involved `methodof` function.