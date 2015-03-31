---
layout: post
title: "F# computation expressions - part 3: cont { ... }"
date: 2011-01-06 17:04:00
categories: 2623145951
tags: fsharp monads computation expressions cont async callcc
---
Настало время монады [`cont`](http://hackage.haskell.org/packages/archive/mtl/2.0.0.0/doc/html/Control-Monad-Cont.html) и страшного оператора `callCC`. Понимать смысл `cont` очень важно не только потому, что это [мама всех монад](http://blog.sigfpe.com/2008/12/mother-of-all-monads.html), но и для того, чтобы дружить с *[continuation passing style](http://blogs.msdn.com/b/ericlippert/archive/tags/continuation+passing+style/)*, не редко встречающимся в функциональном программировании. Более того, `async` из состава стандартной бибилиотеки F# тоже представляет собой монаду `cont`, только не с одним продолжением `k`, а тремя (обычное продолжение, продолжение при возникновение исключения и продолжение при запросе отмены async workflow), а так же инфраструктурой для управления потоками и контекстами синхронизации.

Итак, сигнатура:

{% highlight fsharp %}
namespace FSharp.Monads

type Cont<'a, 'result> =
     Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
     val run: Cont<'a,'r> -> ('a -> 'r) -> 'r
     val callCC: (('a -> Cont<'b,'r>) -> Cont<'a,'r>) -> Cont<'a,'r>

type ContBuilder =
     new: unit -> ContBuilder
     member Bind: Cont<'a,'r> * ('a -> Cont<'b,'r>) -> Cont<'b,'r>
     member Zero: unit -> Cont<unit,'r>
     member Return: 'a -> Cont<'a,'r>
     member ReturnFrom: Cont<'a,'r> -> Cont<'a,'r>
{% endhighlight %}

Реализация:

{% highlight fsharp %}
namespace FSharp.Monads

type Cont<'a, 'result> =
     Cont of (('a -> 'result) -> 'result)

[<RequireQualifiedAccess>]
module Cont =
     let run (Cont c) k = c k
     let callCC f =
         Cont(fun c -> let g a = Cont(fun _ -> c a)
                       let (Cont m) = f g in m c)

type ContBuilder() =
     member b.Bind(Cont m, f) =
         Cont(fun k ->
            m (fun r -> let (Cont c) = f r in c k))
     member b.Zero() = Cont(fun k -> k ())
     member b.Return x = Cont(fun k -> k x)
     member b.ReturnFrom x = x : Cont<_,_>
{% endhighlight %}

В качестве примера использования перепишем на F# [хрестоматийный пример](http://hackage.haskell.org/packages/archive/mtl/2.0.0.0/doc/html/Control-Monad-Cont.html) использования монады `cont` вместе с функцией `callCC`. Функция осуществляет проверку строки с именем пользователя и осуществляет немедленный выход в случае указания пустого имени - с помощью вызова функции `exit` внутри `Cont<_,_>`-вычисления, переданного в `callCC`:

{% highlight fsharp %}
open FSharp.Monads

let cont = ContBuilder()

/// Проверка строки имени на пустоту
let validateName name exit =
    cont { if System.String.IsNullOrEmpty name then
              return! exit "Вы забыли указать своё имя!" }

/// Проверка имени пользователя
let whatsYourName name =
    Cont.run (cont {
       let! responce =
          Cont.callCC <| fun exit -> cont {
             do! validateName name exit
             return sprintf "Добро пожаловать, %s!" name }
       return responce
    }) (printfn "%s")

whatsYourName ""
whatsYourName "Alex"
{% endhighlight %}

Функция `validateName` разворачивается компилятором следующим образом:

{% highlight fsharp %}
/// Проверка строки имени на пустоту
let validateName' name exit =
    if System.String.IsNullOrEmpty name then
         cont.ReturnFrom(exit "Вы забыли указать своё имя!")
    else cont.Zero()
{% endhighlight %}

Функция `whatsYourName` выглядит немного сложнее:

{% highlight fsharp %}
/// Проверка имени пользователя
let whatsYourName' name =
    Cont.run
       (cont.Bind(
          Cont.callCC (fun exit ->
             cont.Bind(
                validateName' name exit,
                fun _ -> cont.Return <|
                          sprintf "Добро пожаловать, %s!" name)),
          fun responce -> cont.Return responce))
       (printfn "%s")
{% endhighlight %}

Если вы не разбирались с `callCC`, то очень советую взять этот код и аккуратно заинлайнить/применить все вызовы, это не сложно, увлекательно и позволит понять как именно осуществляется контроль потока управления с помощью оператора `callCC`.