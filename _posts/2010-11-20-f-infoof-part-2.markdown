---
layout: post
title: "F# infoof operator (part 2)"
date: 2010-11-20 04:46:00
author: Aleksandr Shvedov
tags: fsharp infoof pattern-matching patterns quotations
---
The next task is to write `methodof`, which returns a `System.Reflection.MethodInfo` from an expression referring to a method or function, including a call expression. Rather than tracing every implementation step, we'll examine how F# quotes the different ways of using type members and module functions. First, define a type and a module:

```fsharp
type Foo() =
  static member StaticM() = ()
  member this.InstanceM() = ()
  member this.WithArgumentM(x: int) = x
  member this.OverloadedM(_: int) = ()
  member this.OverloadedM(_: string) = ()
  member this.OverloadedM(_: int, _: int) = ()

module Bar =
  let func () = ()
  let tupled (x,y) = x + y
  let curried x y = x + y
  let mixed (a,b,c) (x,y) z = a+b+c+x+y+z
  let generic x = x
```

Here are quotations for several calls:

```fsharp
let foo = Foo()
<@ Foo.StaticM() @>
   Call (None, Void StaticM(), [])

<@ foo.InstanceM() @>
   Call (Some foo, Void InstanceM(), [])

<@ foo.WithArgumentM(123) @>
   Call (Some foo, Int32 WithArgumentM(Int32), [Value 123])

<@ Bar.func () @>
   Call (None, Void func(), [])

<@ Bar.tupled (1,2) @>
   Call (None, Int32 tupled(Int32, Int32), [Value 1, Value 2])

<@ Bar.curried 1 2 @>
   Call (None, Int32 curried(Int32, Int32), [Value 1, Value 2])

<@ Bar.mixed (1,2,3) (5,6) 7 @>
   Call (None, Int32 mixed(Int32, Int32, Int32, Int32, Int32, Int32),
      [Value 1, Value 2, Value 3, Value 5, Value 6, Value 7])
```

Each call is represented by a `Call` node. To quote a call, however, we have to supply arguments, even when their values are irrelevant to obtaining the method's metadata. Arguments are useful when their types select a particular overload, but otherwise we can omit them and let F# treat the method or function as a function value. Here is how those values are quoted:

```fsharp
<@ Foo.StaticM @>
   Lambda (unitVar, Call (None, Void StaticM(), []))

<@ foo.InstanceM @>
   Lambda (unitVar, Call (Some foo, Void InstanceM(), []))

<@ foo.WithArgumentM @>
   Lambda (arg00,
     Call (Some foo, Int32 WithArgumentM(Int32), [arg00]))

<@ Bar.func @>
   Lambda (arg00, Call (None, Void func(), []))

<@ Bar.tupled @>
   Lambda (tupledArg,
     Let (x, TupleGet (tupledArg, 0),
       Let (y, TupleGet (tupledArg, 1),
         Call (None, Int32 tupled(Int32, Int32), [x, y]))))

<@ Bar.curried @>
   Lambda (x,
     Lambda (y,
        Call (None, Int32 curried(Int32, Int32), [x, y])))

<@ Bar.mixed @>
   Lambda (tupledArg,
     Let (a, TupleGet (tupledArg, 0),
       Let (b, TupleGet (tupledArg, 1),
         Let (c, TupleGet (tupledArg, 2),
           Lambda (tupledArg,
             Let (x, TupleGet (tupledArg, 0),
               Let (y, TupleGet (tupledArg, 1),
                 Lambda (z,
                   Call (None, Int32 mixed(Int32, Int32, Int32,
                                           Int32, Int32, Int32),
                         [a, b, c, x, y, z])))))))))
```

F# generates a lambda that wraps the original method or function call, or several nested lambdas when the function has curried arguments. Recognizing these structures directly is more involved, so the `DerivedPatterns` module in `Microsoft.FSharp.Quotations` provides the `Lambdas` active pattern:

```fsharp
let (DerivedPatterns.Lambdas(args, body)) = <@ Bar.mixed @>;;

val args : Var list list = [[a; b; c]; [x; y]; [z]]
val body : Expr =
  Call (None, Int32 mixed(Int32, Int32, Int32, Int32, Int32, Int32),
      [a, b, c, x, y, z])
```

We can now compare the flattened list of lambda parameters (`[[a; b; c]; [x; y]; [z]]`) with the variables passed to the call in the innermost body (`[a; b; c; x; y; z]`). Implementing an active pattern equivalent to `DerivedPatterns.Lambdas` is a useful exercise in working with quotation trees.

Using this pattern, we can define a helper active pattern named `Func` that recognizes the function values F# generates from methods and functions. It must also account for parameterless methods, which are wrapped in lambdas taking a `unit` argument:

```fsharp
let (|Func|_|) expr =
  let onlyVar = function Var v -> Some v | _ -> None
  match expr with
    // Function values for methods with no parameters.
    | Lambda(arg, Call(target, info, []))
        when arg.Type = typeof<unit> -> Some(target, info)

    // Function values with one argument.
    | Lambda(arg, Call(target, info, [ Var var ]))
        when arg = var -> Some(target, info)

    // Function values with curried
    // or tupled arguments.
    | Lambdas(args, Call(target, info, exprs))
        when List.choose onlyVar exprs
           = List.concat args -> Some(target, info)

    | _ -> None
```

The active pattern returns a pair containing the optional receiver expression and the method's `MethodInfo`. This is a partial active pattern: the trailing `|_|` in its name means that it can fail to match, in which case it returns `None`.

We can now define `methodof`, also handling the implicit `let` bindings discussed in the first post:

```fsharp
let methodof expr =
  match expr with
    // Ordinary calls: foo.Bar()
    | Call(_, info, _) -> info

    // Calls and function values through a lambda parameter:
    // fun (x: string) -> x.Substring(1, 2)
    // fun (x: string) -> x.StartsWith
    | Lambda(arg, Call(Some(Var var), info, _))
    | Lambda(arg, Func(Some(Var var), info))
          when arg = var -> info

    // Function values:
    // someString.StartsWith
    | Func(_, info) -> info

    // Calls and function values through instance expressions:
    // "abc".StartsWith("a")
    // "abc".Substring
    | Let(arg, _, Call(Some (Var var), info, _))
    | Let(arg, _, Func(Some (Var var), info))
         when arg = var -> info

    | _ -> failwith "Not a method expression"
```

There is one complication when a function value is created from an overloaded method: the compiler may not have enough information to choose an overload. For example:

```fsharp
let foo = Foo()
methodof<@ foo.OverloadedM @>
```

> **error FS0041:**<br/>
> A unique overload for method 'OverloadedM' could not be determined based on type information prior to this program point. The available overloads are shown below (or in the Error List window). A type annotation may be needed.<br/>
> <br/>
> Possible overload: 'member Foo.OverloadedM : string -> unit'.<br/>
> Possible overload: 'member Foo.OverloadedM : int -> unit'.

An explicit function type annotation resolves the ambiguity:

```fsharp
methodof<@ foo.OverloadedM : string -> unit @>
```

Parts of the type can be left unspecified when the remaining information is enough to select the overload. Sometimes it is sufficient to specify a tuple with the right number of elements, corresponding to the method's parameter count, as in the second example:

```fsharp
methodof<@ foo.OverloadedM : string -> _ @>
methodof<@ foo.OverloadedM : _ * _  -> _ @>
```

We can also define `methoddefof`, which returns the *generic method definition* of a generic method or function:

```fsharp
let methoddefof expr =
  match methodof expr with
    | info when info.IsGenericMethod -> info.GetGenericMethodDefinition()
    | info -> failwithf "%A is not generic" info
```

Here are examples of the supported forms:

```fsharp
[ methodof<@ Console.ReadLine @>
  methodof<@ Console.ReadLine() @>
  methodof<@ Console.Write '1' @>
  methodof<@ Console.Write 123 @>
  methodof<@ Console.WriteLine(null: string) @>
  methodof<@ "abc".StartsWith @>
  methodof<@ (null: string).StartsWith @>
  methodof<@ fun(s: string) -> s.StartsWith @>
  methodof<@ fun(s: string) -> s.Substring @>
  methodof<@ Console.WriteLine : int -> _ @>
  methodof<@ Console.WriteLine : double -> _ @>
  methodof<@ 1.23.CompareTo : obj -> _ @>
  methodof<@ Math.Max : int * _ -> _ @>
  methodof<@ Math.Max : float * _ -> _ @>
  methodof<@ fun(s: string) ->
             s.ToCharArray : int * int -> char[] @>
  methodof<@ Math.Max(1m, 2m) @>
  methodof<@ Seq.map @>
  methodof<@ List.unzip @>
  methodof<@ 1.23.CompareTo @>
  methoddefof<@ id @>
  methoddefof<@ List.unzip @>
  methoddefof<@ Seq.map @> ]

|> List.iter (printfn "%A")
```

The output is:

    String ReadLine()
    String ReadLine()
    Void Write(Char)
    Void Write(Int32)
    Void WriteLine(String)
    Boolean StartsWith(String)
    Boolean StartsWith(String)
    Boolean StartsWith(String)
    String Substring(Int32)
    Void WriteLine(Int32)
    Void WriteLine(Double)
    Int32 CompareTo(Object)
    Int32 Max(Int32, Int32)
    Double Max(Double, Double)
    Char[] ToCharArray(Int32, Int32)
    Decimal Max(Decimal, Decimal)
    IEnumerable`1[Object]
        Map[Object,Object](FSharpFunc`2[Object,Object],
                           IEnumerable`1[Object])
    Tuple`2[FSharpList`1[Object],FSharpList`1[Object]]
        Unzip[Object,Object](FSharpList`1[Tuple`2[Object, Object]])
    Int32 CompareTo(Double)
    T Identity[T](T)
    Tuple`2[FSharpList`1[T1],FSharpList`1[T2]]
        Unzip[T1,T2](FSharpList`1[Tuple`2[T1,T2]])
    IEnumerable`1[TResult]
        Map[T,TResult](FSharpFunc`2[T,TResult], IEnumerable`1[T])

The next post will cover `eventof` and how F# represents event access in quotations. We will then bring all the helpers together into a complete module in the final post.