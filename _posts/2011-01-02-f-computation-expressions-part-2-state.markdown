---
layout: post
title: "F# computation expressions - part 2: state { ... }"
date: 2011-01-02 16:32:00
categories: 2567177999
tags: fsharp computation expressions monads state
---
К моему сожалению, на языке с энергичным порядком вычислений, коим является F#, невозможно выразить такие разновидности монады `state`, как её ленивая версия ([lazy state monad](http://blog.melding-monads.com/2009/12/30/fun-with-the-lazy-state-monad/), когда в состояние сохраняется не вычисленное значение, а само вычисление) и такой крышеснос, например, как [reverse state monad](http://lukepalmer.wordpress.com/2008/08/10/mindfuck-the-reverse-state-monad/) (она же [backward state monad](http://panicsonic.blogspot.com/2007/12/backwards-state-or-power-of-laziness.html)). Поэтому здесь привожу самую обычную *strict*-версию монады `state`.

В качестве типа вычислений `M<’a>` будем использовать собственный тип-объединение `State<’a,’state>`, просто оборачивающий функции типа `'state -> 'a * 'state`. Дополнительно определяем модуль `State` для частых операций с состоянием и функции `run` для запуска вычисления. Сигнатура:

{% highlight fsharp %}
namespace FSharp.Monads

type State<'a, 'state> =
  State of ('state -> 'a * 'state)

[<RequireQualifiedAccess>]
module State =
  [<GeneralizableValue>]
  val get<'a> : State<'a,'a>
  val set: 's -> State<unit,'s>
  val modify: ('s -> 's) -> State<unit,'s>
  val run : State<'a,'s> -> 's -> 'a

type StateBuilder =
  new: unit -> StateBuilder
  member Bind: State<'a,'s> * ('a -> State<'b,'s>) -> State<'b,'s>
  member Return: 'a -> State<'a,'s>
  member ReturnFrom : State<'a,'s> -> State<'a,'s>
{% endhighlight %}

Реализация:

{% highlight fsharp %}
namespace FSharp.Monads

type State<'a, 'state> =
  State of ('state -> 'a * 'state)

[<RequireQualifiedAccess>]
module State =
  [<GeneralizableValue>]
  let get<'a>  = State(fun (s:'a) -> s, s)
  let set s    = State(fun _ -> (), s)
  let modify f = State(fun s -> (), f s)
  let run (State f) seed = fst (f seed)

type StateBuilder() =
  member b.Bind(State m, f) =
    State(fun s -> 
      let v, s' = m s
      let (State t) = f v in t s')
  member b.Return x = State(fun s -> x, s)
  member b.ReturnFrom x = x : State<_,_>
{% endhighlight %}

В качестве примера, приведу реализацию [алгоритма Евклида](http://ru.wikipedia.org/wiki/%D0%90%D0%BB%D0%B3%D0%BE%D1%80%D0%B8%D1%82%D0%BC_%D0%95%D0%B2%D0%BA%D0%BB%D0%B8%D0%B4%D0%B0) для нахождения наибольшего общего делителя двух целых чисел. Императивный вариант на C# выглядит как-то так:

{% highlight C# %}
int GCD(int x, int y) {
  while (x != y) {
    if (x < y) {
      y = y - x;
    } else {
      x = x - y;
    }
  }

  return x;
}
{% endhighlight %}

Так как изменяемое состояние здесь составляют две переменные `x` и `y`, то в качестве типа `'state` будет выступать кортеж типа `int * int`.

{% highlight fsharp %}
open FSharp.Monads
#nowarn "40"

let state = StateBuilder()

// вспомогательные функции для подмены части состояния
let putX x = State.modify (fun (_,y) -> x, y)
let putY y = State.modify (fun (x,_) -> x, y)

/// Алгоритм Евклида
let rec gcd = state {
  let! x, y = State.get
  if   (x = y) then return x
  elif (x < y) then do! putY (y-x)
                    return! gcd
               else do! putX (x-y)
                    return! gcd }

let x = State.run gcd (6, 21)
printfn "gcd(6, 21) = %d" x
{% endhighlight %}

Вариант “без сахара”:

{% highlight fsharp %}
/// Алгоритм Евклида
let rec gcd' =
  state.Bind(
    State.get,
    fun (x,y) ->
      if   (x = y) then state.Return x
      elif (x < y) then state.Bind(putY (y-x),
                          fun()-> state.ReturnFrom gcd')
                   else state.Bind(putX (x-y),
                          fun()-> state.ReturnFrom gcd'))
{% endhighlight %}

Из-за большого количества скрытых функции, уймы замыканий, передачи через вычисления кортежа с состоянием и постоянного конструирования экземпляров `State<’a,’state>`, всё это работает, мягко говоря, неторопливо, так что не вздумайте всерьёз использовать что-то подобное в F#. Это лишь пример того, как можно моделировать изменяемое состояние с помощью монад.