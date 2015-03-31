---
layout: post
title: "F# computation expressions - part 4: cont + getCC"
date: 2011-03-15 14:00:00
categories: 3875201115
tags: fsharp cont computation expressions monads callcc getcc
---
Недавно открыл для себя интересную функцию, предназначенную для работы с монадой continuation - `[getCC](http://web.archiveorange.com/archive/v/nDNOv9Pf55aKSZYSQ1bg)`. Эта функция представляет собой `callCC`, как бы возвращающий из себя переданное ему продолжение. То есть становится возможно из любой точки computation expressions получить текущее продолжение и использовать его позже. Фактически это позволяет моделировать `goto` и императивные циклы внутри композиции `cont`-вычислений и замечательно запутывать поток исполнения.

Я решил дополнить [приведенную ранее](http://controlflow.tumblr.com/post/2623145951/f-computation-expressions-part-3-cont) реализацию `cont { }` функциями `getcc` и `getcc’`, при этом выразив их немного проще, чем через `callcc`.

Сигнатура пространства имён:

{% highlight fsharp %}
namespace FSharp.Monads

type Cont<'a, 'result> =
     Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
    val run: ('a -> 'r) -> Cont<'a,'r> -> 'r
    val bind: ('a -> Cont<'b,'r>) -> Cont<'a,'r>  -> Cont<'b,'r>
    val callcc: (('a -> Cont<'b,'r>) -> Cont<'a,'r>) -> Cont<'a,'r>
    val getcc<'a,'r> : Cont<Cont<'a,'r>,'r>
    val getcc': 'a -> Cont<'a * ('a -> Cont<'b,'r>),'r>

[<Class>]
type ContBuilder =
    member Bind: Cont<'a,'r> * ('a -> Cont<'b,'r>) -> Cont<'b,'r>
    member Zero: unit -> Cont<unit, 'r>
    member Combine: Cont<unit,'r> * Cont<'a,'r> -> Cont<'a,'r>
    member Return: 'a -> Cont<'a, 'r>
    member ReturnFrom: Cont<'a,'r> -> Cont<'a,'r>
    member Delay: (unit -> Cont<'a,'r>) -> Cont<'a,'r>

[<AutoOpen>]
module ExtraTopLevelOperators =
    val cont : ContBuilder
{% endhighlight %}

Реализация:

{% highlight fsharp %}
namespace FSharp.Monads

type Cont<'a, 'result> =
     Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
    let run cont (Cont c) = c cont
    let bind f (Cont m) =
        Cont(fun cont ->
                 m (fun r -> let (Cont c) = f r
                             in c cont))
    let callcc f =
        Cont(fun cont ->
                 let g x = Cont(fun _ -> cont x)
                 let (Cont c) = f g in c cont)
    let getcc<'a,'r> =
        Cont(fun cont ->
                 let rec x: Cont<'a,'r> =
                     Cont(fun _ -> cont x)
                 in cont x)
    let getcc' x0 =
        Cont(fun cont ->
                 let rec f x =
                     Cont(fun _ -> cont (x, f))
                 in cont (x0, f))

type ContBuilder() =
    member b.Bind(m,f) = Cont.bind f m
    member b.Return(x) = Cont(fun cont -> cont x)
    member b.Zero()    = Cont(fun cont -> cont ())
    member b.ReturnFrom(x) = x: Cont<_,_>
    member b.Combine(Cont m1, Cont m2) =
        Cont(fun cont -> m1 (fun() -> m2 cont))
    member b.Delay(f) =
        Cont(fun cont -> let (Cont c) = f() in c cont)

[<AutoOpen>]
module ExtraTopLevelOperators =
    let cont = ContBuilder()
{% endhighlight %}

Пример моделирования `goto`-перехода по метке - следующий код будет выполняться пока пользователь будет нажимать клавишу пробела:

{% highlight fsharp %}
open FSharp.Monads
open System

let goto() =
    cont {
           printfn "press space"
           let! jump = Cont.getcc

           let c = Console.ReadKey(true)
           if (c.Key = ConsoleKey.Spacebar) then
               printfn "one more time"
               return! jump

           printfn "completed!"
         }
    |> Cont.run ignore
{% endhighlight %}

Без “сахара” эта функция выглядит следующим образом (обратите внимание, что пришлось определить члены построителя computation expression, такие как `Combine` и `Delay`):

{% highlight fsharp %}
let goto'() =
    printfn "press space"
    cont.Combine(
      cont.Bind(
        Cont.getcc,
        fun jump ->
            let c = Console.ReadKey(true)
            if (c.Key = ConsoleKey.Spacebar) then
                 printfn "one more time"
                 cont.ReturnFrom(jump)
            else cont.Zero()
      ),
      cont.Delay(fun()->
        printfn "completed!"
        cont.Return(())
      )
    )
    |> Cont.run ignore
{% endhighlight %}

С помощью другой функции - `getcc’` - возможно дополнительно передавать некоторое значение при возврате к продолжению, что позволяет моделировать императивные циклы:

{% highlight fsharp %}
let loop() =
    cont {
           let! value, label = Cont.getcc' 0
           printfn "value = %d" value

           if value < 10
              then return! label (value + 1)
         }
    |> Cont.run id
{% endhighlight %}

Без синтаксиса computation expressions:

{% highlight fsharp %}
let loop'() =
    cont.Bind(
      Cont.getcc' 0,
      fun (value, label) ->
        printfn "value = %d" value

        if value < 10
              then cont.ReturnFrom(label (value + 1))
              else cont.Zero())
    |> Cont.run id
{% endhighlight %}

То есть `getcc’` возвращает кортеж из значения некоторого типа и функции с аргументом данного типа, возвращающую продолжение. Какой аргументы вы передадите функции, такое значение и вернет `getcc’` первым элементом кортежа, а изначальное значение берётся из аргумента вызова `getcc’`.