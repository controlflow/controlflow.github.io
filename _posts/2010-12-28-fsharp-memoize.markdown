---
layout: post
title: "Мемоизация функций F# с аргументами в каррированной форме"
date: 2010-12-28 01:09:00
categories: 2487602398
tags: fsharp memoize generics curried closure
---
Сегодня поговорим снова о мемоизации функций, на этот раз применительно к F#. Мемоизация в семействе ML-языков прекрасно выражается в виде функции высшего порядка, принимающую целевую функцию и возвращающую её мемоизированный вариант:

{% highlight fsharp %}
let memoize f =
  let cache = System.Collections.Generic.Dictionary()
  fun x -> match cache.TryGetValue x with
           | true, result -> result
           | _ -> let result = f x
                  cache.Add(x, result)
                  result
{% endhighlight %}

Испытываем:

{% highlight fsharp %}
let incr x = printfn "incr invoked!"
             x + 1

let f = memoize incr

printfn "f 1 = %d" (f 1)
printfn "f 2 = %d" (f 2)
printfn "f 1 = %d" (f 1)
{% endhighlight %}

Вывод:

    f invoked!
    f(1)=2
    f invoked!
    f(2)=3
    f(1)=2

Как и ожидалось, а что насчёт нескольких аргументов, заданных в виде кортежа?

{% highlight fsharp %}
let add (x,y) = printfn "add invoked!"
                x + y

let g = memoize add

printfn "g (1,1) = %d" (g (1,1))
printfn "g (1,2) = %d" (g (1,2))
printfn "g (1,1) = %d" (g (1,1))
{% endhighlight %}

Вывод:

    add invoked!
    g (1,1) = 2
    add invoked!
    g (1,2) = 3
    g (1,1) = 2

Тоже всё ок, так как для типов кортежей определены правила проверки на эквивалентность и вычисления хэш-значения, а значит аргументы в кортеже без проблем находятся в кэше. Но когда дело доходит до функций с аргументами в каррированной форме:

{% highlight fsharp %}
let add x y = printfn "add invoked!"
              x + y

let g = memoize add

printfn "g 1 1 = %d" (g 1 1)
printfn "g 1 2 = %d" (g 1 2)
printfn "g 1 1 = %d" (g 1 1)
{% endhighlight %}

То мемоизация перестаёт работать:

    add invoked!
    g 1 1 = 2
    add invoked!
    g 1 2 = 3
    add invoked!
    g 1 1 = 2

Чтобы понять, почему так происходит, достаточно лишь взглянуть на сигнатуры функций `memoize` и `add`:

{% highlight fsharp %}
val memoize : ('a -> 'b) -> ('a -> 'b) when 'a : equality
val add : int -> int -> int
{% endhighlight %}

Вспоминаем, что в записи `int -> int -> int` стрелка право-ассоциативна, а значит сигнатура на самом деле выглядит как `int -> (int -> int)`. Получается, что мемоизации подвергается применение *первого* аргумента к функции `add`, то есть в кэше хранятся первые аргументы типа `int` и соответствующие им функции `int -> int`.

Решить данную проблему можно следующим образом: если функцию `memoize` будут применять к такой функции, что тип-параметр `'b` будет являться типом функции F#, то перед тем, как сохранять возвращаемое значение в кэш, эту функцию так же следует подвергнуть функции `memoize`. Таким образом мы снова получим “каррированные кэши”, как из [предыдущего поста](http://controlflow.tumblr.com/post/2372528624/postsharp),  то есть при применении аргументов мемоизированная функция `add` будет производить поиск по кэшу первого `int`-аргумента, извлекать из кэша мемоизированную функцию `int -> int`, искать в её кэше второй `int`-аргумент и возвращать значение.

Полная реализация модуля:

{% highlight fsharp %}
module Memoize

open System
open Microsoft.FSharp.Reflection

/// Тип generic-делегата ('a -> 'b)
let private funcDef = typedefof<Func<_,_>>

/// Флаги поиска приватного статического метода
let private staticPrivate =
  Reflection.BindingFlags.Static ||| Reflection.BindingFlags.NonPublic

/// Тип, параметризуемый типом возвращаемого
/// значения функции, подвергаемой мемоизации
type private AnyMemoizer<'T>() =

  static let memo : Func<'T,'T> =
    match typeof<'T> with

    // если возвращаемое значение является функцией F#
    | t when FSharpType.IsFunction t ->
      // тип аргумента и возвращаемого значения
      let targ, tres = FSharpType.GetFunctionElements t
      // отражение метода мемоизации,
      // соответствующее данным типам
      let runMethod = typeof<FuncMemoizer>
                        .GetMethod("Run", staticPrivate)
                        .GetGenericMethodDefinition()
                        .MakeGenericMethod [| targ; tres |]
      // тип делегата, "пропускающего"
      // через себя возвращаемые значения
      let delType = funcDef.MakeGenericType [| t; t |]
      // создаём делегат из метода мемоизации
      downcast Delegate.CreateDelegate(delType, runMethod)

    | _ -> null // иначе ничего не делаем

    // так как let-привязки в определениях типов всегда
    // private-видимости, то создаём публичный метод
    static member Run(x: 'T) = memo.Invoke x

/// Тип, содержащий generic-метод мемоизации
and private FuncMemoizer =

  static member Run (f: 'a -> 'b) =
    let cache = Collections.Generic.Dictionary()

    // если возвращаемое значение - функция F#
    if FSharpType.IsFunction typeof<'b> then
      fun x -> match cache.TryGetValue x with
               | true, result -> result
               | _ -> // мемоизация возвращаемой функции
                      let result = AnyMemoizer<'b>.Run(f x)
                      cache.Add(x, result)
                      result
    else // иначе обычная мемоизация
      fun x -> match cache.TryGetValue x with
               | true, result -> result
               | _ -> let result = f x
                      cache.Add(x, result)
                      result

/// Мемоизация функций с аргументами в каррированной форме
let curried f = FuncMemoizer.Run f
{% endhighlight %}

Пробуем применить:

{% highlight fsharp %}
let add x y = printfn "add invoked!"
              x + y

let g = Memoize.curried add

printfn "g 1 1 = %d" (g 1 1)
printfn "g 1 2 = %d" (g 1 2)
printfn "g 1 1 = %d" (g 1 1)
{% endhighlight %}

Вывод:

    add invoked!
    g 1 1 = 2
    add invoked!
    g 1 2 = 3
    g 1 1 = 2

Теперь всё работает как и ожидалось, давайте задумаемся о недостатках… Самый большой недостаток данной реализации в том, что невозможно контролировать глубину мемоизации. То есть если исходная мемоизируемая функция с аргументами в каррированной форме возвращает другие функции, то они тоже будут мемоизированы:

{% highlight fsharp %}
let func x y =
  fun a -> printfn "lambda invoked!"
           x + y + a

let f = Memoize.curried func

printfn "(f 1 2) 3 = %d" ((f 1 2) 3)
printfn "(f 1 2) 3 = %d" ((f 1 2) 3)
{% endhighlight %}

Вывод:

```
lambda invoked!
(f 1 2) 3 = 6
(f 1 2) 3 = 6
```
То есть возвращаемая функция так же подвергается мемоизации, а это может не требоваться. Исправить этот недостаток достаточно легко, введя для функции `memoize` параметр глубины и передавая его во вложенные вызовы `memoize`. Реализация доступна [здесь](http://pastebin.com/mJXGMF6d), демонстрация:

{% highlight fsharp %}
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
{% endhighlight %}

Вывод:

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

Ещё один небольшой недостаток данной реализации - использование памяти. Дело в том, что во всех кэшах, кроме самых внешних, хранится функция с частично применёнными аргументами в замыкании + те же аргументы являются ключами словарей. Это легко увидеть в отладчике VisualStudio на таком коде:

{% highlight fsharp %}
let f a b c d e f =
    a + b + c + d + e + f

let fa = f  1
let fb = fa 2
let fc = fb 3
let fd = fc 4
let fe = fd 5
let ff = fe 6
{% endhighlight %}

![]({{ site.baseurl }}/images/fsharp-memoize.png)

То есть замыкание, получаемое при частичном применении аргумента, содержит этот аргумент в поле + ссылку на исходное значение функционального типа.

В следующий раз поговорим о ещё более ненормальном способе мемоизации в F# :)