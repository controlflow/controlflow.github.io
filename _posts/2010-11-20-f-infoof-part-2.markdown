---
layout: post
title: "F# infoof (part 2)"
date: 2010-11-20 04:46:00
categories: 1622931184
tags: fsharp infoof pattern-matching patterns quotations
---
Итак, следующей задачей будет являться написание функции `methodof`, возвращающей экземпляр `System.Reflection.MethodInfo` по выражению вызова (и не только) метода или функции. На этот раз подробно этапы разработки я приводить не буду, лишь продемонстрирую, как цитируются те или иные использования методов типов и функций модулей. Для этого определим следующий тип и модуль:

```f#
type Foo() =
  static member StaticM() = ()
  member this.InstanceM() = ()
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

И попробуем процитировать вызовы:

```f#
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

Тут вроде всё понятно, основа всех вызовов – образец `Call()`. Однако нам приходится указывать хоть какие-нибудь параметры, для того чтобы процитировать вызов, а реально это может потребоваться только если метод перегружен и требуется типами аргументов подсказать компилятору конкретную перегрузку. Однако можно не указывать аргументы вовсе и тогда F# будет трактовать метод/функцию как значение функционального типа. Посмотрим, как цитируются такие значения:

```f#
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

То есть F# генерирует лямбда-выражение, оборачивающее вызов исходного метода/функции (или несколько вложенных лямбда-выражений, если исходная функция содержит аргументы в каррированной форме). Опознавать такие конструкции нетривиально, поэтому в пространстве имён `Microsoft.FSharp.Quotations` есть модуль `DerivedPatterns`, содержащий активный образец `Lambdas`:

```f#
let (DerivedPatterns.Lambdas(args, body)) = <@ Bar.mixed @>;;

val args : Var list list = [[a; b; c]; [x; y]; [z]]
val body : Expr =
  Call (None, Int32 mixed(Int32, Int32, Int32, Int32, Int32, Int32),
      [a, b, c, x, y, z])
```

Теперь осталось лишь проверить список списков аргументов лямбды (`[[a; b; c]; [x; y]; [z]]`) на соответствие списку параметров при вызове в теле самой вложенной лямбды (`[a, b, c, x, y, z]`). В качестве упражнения очень советую попробовать реализовать активный образец `DerivedPatterns.Lambdas` самостоятельно - это достаточно увлекательная задача.

В итоге можно реализовать вспомогательный активный образец `Func`, совпадающий с описанными выше функциональными значениями, сгенерированными F# из методов и функций. При этом необходимо учесть, что для методов, не имеющих параметров вовсе, генерируются лямбда-выражения с аргументом типа `unit`:

```f#
let (|Func|_|) expr =
  let onlyVar = function Var v -> Some v | _ -> None
  match expr with
    // функ.значения без аргументов
    | Lambda(arg, Call(target, info, []))
        when arg.Type = typeof<unit> -> Some(target, info)

    // функ.значения с одним аргументом
    | Lambda(arg, Call(target, info, [ Var var ]))
        when arg = var -> Some(target, info)

    // функ.значения с набором каррированных
    // или взятых в кортеж аргументов
    | Lambdas(args, Call(target, info, exprs))
        when List.choose onlyVar exprs
           = List.concat args -> Some(target, info)

    | _ -> None
```

Активный образец возвращает пару из экземпляра, чей метод вызывается и экземпляр `MethodInfo` этого метода/функции, при этом активный образец может не совпасть вовсе (об этом свидетельствует `|_|` в конце имени активного образца).

Теперь достаточно легко определить функцию `methodof`, учитывая проблему со скрытыми `let`-выражениями, рассмотренную в первом посте этой серии:

```f#
let methodof expr =
  match expr with
    // любые обычные вызовы: foo.Bar()
    | Call(_, info, _) -> info

    // вызовы и функ.значения через аргумент лямбды:
    // fun (x: string) -> x.Substring(1, 2)
    // fun (x: string) -> x.StartsWith
    | Lambda(arg, Call(Some(Var var), info, _))
    | Lambda(arg, Func(Some(Var var), info))
          when arg = var -> info

    // любые функциональные значения:
    // someString.StartsWith
    | Func(_, info) -> info

    // вызовы и функ.значения через экземпляры:
    // "abc".StartsWith("a")
    // "abc".Substring
    | Let(arg, _, Call(Some (Var var), info, _))
    | Let(arg, _, Func(Some (Var var), info))
         when arg = var -> info

    | _ -> failwith "Not a method expression"
```

И тут возникает один нюанс: такой `methodof` не всегда работает, если на вход подаётся выражение значения функционального типа, созданного из перегруженного метода:

```f#
let foo = Foo()
methodof<@ foo.OverloadedM @>
```

> **error FS0041:**<br/>
> A unique overload for method 'OverloadedM' could not be determined based on type information prior to this program point. The available overloads are shown below (or in the Error List window). A type annotation may be needed.<br/>
> <br/>
> Possible overload: 'member Foo.OverloadedM : string -> unit'.<br/>
> Possible overload: 'member Foo.OverloadedM : int -> unit'.

Компилятору можно подсказать, явно типизируя выражение функционального типа:

```f#
methodof<@ foo.OverloadedM : string -> unit @>
```

При этом возможно частично не указывать типы, если это не будет мешать компилятору F# выбирать требуемую перегрузку (иногда достаточно указать только, что аргумент функционального типа является кортежем из *n* елементов, где *n* - количество параметров исходного метода, см. второй пример):

```f#
methodof<@ foo.OverloadedM : string -> _ @>
methodof<@ foo.OverloadedM : _ * _  -> _ @>
```

Заодно определим функцию `methoddefof`, возвращающую *generic method definition* любого обобщённого метода/функции, реализация тривиальна:

```f#
let methoddefof expr =
  match methodof expr with
    | info when info.IsGenericMethod -> info.GetGenericMethodDefinition()
    | info -> failwithf "%A is not generic" info
```

Итак, проверяем:

```f#
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

Выводит на экран:

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

Всё работает, катаемся! В следующем посте попробуем собрать всё это дело воедино…